require 'pony'
require 'net/ssh'

# for nonzero exit status of a remote command
class CommandFailure < RuntimeError
  def to_s(*args)
    "#{self.class}: #{super(*args)}"
  end
end

# - this module is deliberately written without private state
# - it is meant to be used in the helper style
# - whenever a remote command sends data to STDOUT or STDERR, Runsible will
#   immediately send it to the corresponding local IO
# - Runsible itself writes some warnings and timestamped command delimeters to
#   STDOUT and STDERR
#
module Runsible
  SSH_CNX_TIMEOUT = 10
  class Error < RuntimeError; end

  def self.usage(opts, msg=nil)
    puts opts
    puts
    puts msg if msg
    exit 1
  end

  def self.alert(to, subject, body, backend=:email)
    case backend
    when :email
      Pony.mail(to: to,
                from: 'runsible@spoon',
                subject: subject,
                body: body)
    when :kafka
      # TODO
      raise Error, "unsupported backend: #{backend.inspect}"
    else
      raise Error, "unknown backend: #{backend.inspect}"
    end
  end

  def self.warn(msg)
    $stdout.puts msg
    $stderr.puts msg
  end

  def self.ssh_runlist(settings, runlist, ssh_options, yaml)
    ssh_options[:forward_agent] ||= true
    ssh_options[:port] ||= settings.fetch('port')
    ssh_options[:send_env] ||= settings['vars'] if settings['vars']
    ssh_options[:timeout] ||= SSH_CNX_TIMEOUT
    host, user = settings.fetch('host'), settings.fetch('user')
    Net::SSH.start(host, user, ssh_options) { |ssh|
      self.exec_runlist(ssh, runlist, settings, yaml)
    }
  end

  def self.die!(msg, alert_to)
    self.warn(msg)
    self.alert(alert_to, "Runsible: FATAL #{msg}", msg)
    exit 1
  end

  # execute runlist with failure handling, retries, alerting, etc.
  def self.exec_runlist(ssh, runlist, settings, yaml = Hash.new)
    runlist.each { |run|
      cmd = run.fetch('command')
      retries = run['retries'] || settings['retries']
      on_failure = run['on_failure'] || 'exit'

      begin
        self.exec_retry(ssh, cmd, retries)
      rescue CommandFailure, Net::SSH::Exception => e
        self.warn e
        msg = "#{retries} retries exhausted; on_failure: #{on_failure}"
        self.warn msg
        self.alert(settings['email'], "retries exhausted", e.to_s)

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
        self.die!("exiting after `#{cmd}` ultimately failed")
      end
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
    exit_code == 0 or raise(CommandFailure, "[exit #{exit_code}] #{cmd}")
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

  def self.begin_banner(msg)
    "RUNSIBLE >>> [#{self.timestamp}] >>> #{msg} >>>>>"
  end

  def self.end_banner(msg)
    "<<<<< #{msg} <<< [#{self.timestamp}] <<< RUNSIBLE"
  end

  def self.timestamp(t = Time.now)
    t.strftime("%b%d %H:%M:%S")
  end

  def self.banner_wrap(msg)
    self.warn self.begin_banner(msg)
    yield if block_given?
    self.warn self.end_banner(msg)
  end
end
