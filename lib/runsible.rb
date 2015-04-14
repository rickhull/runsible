autoload :YAML, 'yaml'
autoload :Net, 'net/ssh'
autoload :Pony, 'pony'
autoload :Slop, 'slop'

# - this module is deliberately written without private state
# - whenever a remote command sends data to STDOUT or STDERR, Runsible will
#   immediately send it to the corresponding local IO
# - Runsible itself writes some warnings and timestamped command delimiters to
#   STDOUT and STDERR
#
module Runsible
  class Error < RuntimeError; end
  class CommandFailure < Runsible::Error; end # nonzero exit

  # defaults
  SETTINGS = {
    user: ENV['USER'],
    host: '127.0.0.1',
    port: 22,
    retries: 0,
    vars: [],
  }

  # defaults
  SSH_OPTIONS = {
    forward_agent: true,
    paranoid: false,
    timeout: 10, # connection timeout, raises on expiry
  }

  ### Utility stuff ###

  # provide a better string representation for all Exceptions
  def self.excp(excp)
    "#{excp.class}: #{excp.message}"
  end

  # return SETTINGS with string keys, using values from hsh if passed in
  def self.apply_defaults(hsh = nil)
    hsh ||= Hash.new
    SETTINGS.each { |sym, v|
      hsh[sym.to_s] ||= v
    }
    hsh
  end

  # read VERSION from filesystem
  def self.version
    File.read(File.join(__dir__, '..', 'VERSION'))
  end

  # send alert depending on settings
  def self.alert(topic, message, settings)
    backend = settings['alerts'] && settings['alerts']['backend']
    case backend
    when 'disabled', nil, false
      self.warn "DISABLED ALERT: [#{topic}] #{message}"
      return
    when 'email'
      Pony.mail(to: settings.fetch(:address),
                from: 'runsible@spoon',
                subject: topic,
                body: message)
    when 'kafka', 'slack'
      # TODO
      raise Error, "unsupported backend: #{backend.inspect}"
    else
      raise Error, "unknown backend: #{backend.inspect}"
    end
  end

  # send warnings to both STDOUT and STDERR
  def self.warn(msg)
    $stdout.puts msg
    $stderr.puts msg
  end

  # warn, alert, exit 1
  def self.die!(msg, settings)
    self.warn(msg)
    self.alert("runsible:fatal:#{Process.pid}", msg, settings)
    exit 1
  end

  ### CLI or bin/runsible stuff ###

  # parse CLI arguments
  def self.slop_parse
    d = SETTINGS # display defaults
    Slop.parse do |o|
      o.banner = "usage: runsible [options] yaml_file"
      o.on '-h', '--help' do
        puts o
        exit 0
      end
      o.on     '-v', '--version', 'show runsible version' do
        puts Runsible.version
        exit 0
      end

      o.string '-u', '--user',    "remote user [#{d[:user]}]"
      o.string '-H', '--host',    "remote host [#{d[:host]}]"
      o.int    '-p', '--port',    "remote port [#{d[:port]}]"
      o.int    '-r', '--retries', "retry count [#{d[:retries]}]"
      o.bool   '-s', '--silent',  'suppress alerts'
      # this feature does not yet work as expected
      # https://github.com/net-ssh/net-ssh/issues/236
      #  o.string '-v', '--vars',    'list of vars to pass, e.g.: "FOO BAR"'
    end
  end

  # load yaml from CLI arguments
  def self.extract_yaml(opts)
    yaml_filename = opts.arguments.shift
    self.usage(opts, "yaml_file is required") if yaml_filename.nil?

    begin
      yaml = YAML.load_file(yaml_filename)
    rescue RuntimeError => e
      Runsible.usage(opts, "could not load yaml_file\n#{self.excp(e)}")
    end
    yaml
  end

  # provide a friendly message for the user
  def self.usage(opts, msg=nil)
    puts opts
    puts
    puts msg if msg
    exit 1
  end

  # bin/runsible entry point
  def self.spoon(ssh_options = Hash.new)
    opts = Runsible.slop_parse
    yaml = self.extract_yaml(opts)
    settings = self.merge(opts, Runsible.apply_defaults(yaml['settings']))
    self.ssh_runlist(settings, yaml['runlist'], ssh_options, yaml)
  end

  ### Library stuff ###

  # run a YAML file without any consideration for command line options
  def self.run_yaml(yaml_filename, ssh_options = Hash.new)
    yaml = YAML.load_file(yaml_filename)
    settings = self.apply_defaults(yaml['settings'])
    self.ssh_runlist(settings, yaml['runlist'], ssh_options, yaml)
  end

  # initiate ssh connection, perform the runlist
  def self.ssh_runlist(settings, runlist, ssh_options, yaml)
    ssh_options = SSH_OPTIONS.merge(ssh_options)
    ssh_options[:port] ||= settings.fetch('port')
    ssh_options[:send_env] ||= settings['vars'] if settings['vars']
    host, user = settings.fetch('host'), settings.fetch('user')
    Net::SSH.start(host, user, ssh_options) { |ssh|
      self.exec_runlist(ssh, runlist, settings, yaml)
    }
  end

  # execute runlist with failure handling, retries, alerting, etc.
  # runlist can be nil
  def self.exec_runlist(ssh, runlist, settings, yaml = Hash.new)
    (runlist || Array.new).each { |run|
      cmd = run.fetch('command')
      retries = run['retries'] || settings['retries']
      on_failure = run['on_failure'] || 'exit'

      begin
        self.exec_retry(ssh, cmd, retries)
      rescue CommandFailure, Net::SSH::Exception => e
        excp = self.excp(e)
        self.warn excp
        msg = "#{retries} retries exhausted; on_failure: #{on_failure}"
        self.warn msg
        self.alert("retries exhausted", excp, settings)

        case on_failure
        when 'continue'
          next
        when 'exit'
        else
          if yaml[on_failure]
            self.warn "found #{yaml[on_failure]} runlist"
            # pass empty hash for yaml here to prevent infinite loops
            self.exec_runlist(ssh, yaml[on_failure], settings, Hash.new)
            self.warn "exiting failure after #{yaml[on_failure]}"
          else
            self.warn "#{on_failure} unknown"
          end
        end
        self.die!("exiting after `#{cmd}` ultimately failed", settings)
      end
    }
  end

  # retry several times, rescuing CommandFailure
  # raises on SSH channel exec failure and CommandFailure on final retry
  def self.exec_retry(ssh, cmd, retries)
    self.banner_wrap(cmd) {
      success = false
      retries.times { |i|
        begin
          success = self.exec(ssh, cmd)
          break
        rescue CommandFailure => e
          $stdout.puts "#{e}; retrying shortly..."
          $stderr.puts e
          sleep 2
        end
      }
      # the final retry, may blow up
      success or self.exec(ssh, cmd)
    }
  end

  # prints remote STDOUT to local STDOUT, likewise for STDERR
  # raises on SSH channel exec failure or nonzero exit status
  def self.exec(ssh, cmd)
    exit_code = nil
    ssh.open_channel do |channel|
      channel.exec(cmd) do |ch, success|
        raise(Net::SSH::Exception, "SSH channel exec failure") unless success
        channel.on_data do |ch,data|
          $stdout.puts data
        end
        channel.on_extended_data do |ch,type,data|
          $stderr.puts data
        end
        channel.on_request("exit-status") do |ch,data|
          exit_code = data.read_long
        end
      end
    end
    ssh.loop # nothing actually executes until this call
    raise(CommandFailure, "[exit #{exit_code}] #{cmd}") unless exit_code == 0
    true
  end

  ### Necessities ###

  # opts has symbol keys, overrides settings (string keys)
  # return a hash with string keys
  def self.merge(opts, settings)
    Runsible::SETTINGS.keys.each { |sym|
      settings[sym.to_s] = opts[sym] if opts[sym]
    }
    settings['alerts'] = {} if opts.silent?
    settings
  end

  # delimits the beginning of command output
  def self.begin_banner(msg)
    "RUNSIBLE >>> [#{self.timestamp}] >>> #{msg} >>>>>"
  end

  # delimits the end of command output
  def self.end_banner(msg)
    "<<<<< #{msg} <<< [#{self.timestamp}] <<< RUNSIBLE"
  end

  # self-explanatory
  def self.timestamp(t = Time.now)
    t.strftime("%b%d %H:%M:%S")
  end

  # display begin/end banners, yielding to the block in between
  def self.banner_wrap(msg)
    self.warn self.begin_banner(msg)
    val = block_given? ? yield : true
    self.warn self.end_banner(msg)
    val
  end
end
