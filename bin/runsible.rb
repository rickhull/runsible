#!/usr/bin/env ruby

require 'yaml'
require 'slop'
require 'runsible'

$opts = Slop.parse do |o|
  o.banner = "usage: runcible.rb [options] yaml_file"
  o.string '-u' '--user', 'remote user [root]', default: "root"
  o.string '-H', '--host', 'remote host', default: "127.0.0.1"
  o.int '-p', '--port', 'remote port [22]', default: 22
  o.int '-r', '--retries', 'number of retry attempts [0]', default: 0
  o.string '-m', '--email', 'where to send email alerts'
  o.bool '-s', '--silent', "suppress alerts"
  o.string '-v', '--vars', 'list of vars to pass thru, e.g.: "FOO BAR"'
end

def alert(to, subject, body)
  Runsible.email_alert(to, subject, body) unless $silent
end

def usage(msg = nil)
  Runsible.usage($opts, msg)
end

yaml_filename = $opts.arguments.shift
usage("yaml_file is a required argument") if yaml_filename.nil?

# yaml['settings'] provides static defaults
# $opts can override yaml['settings']
# yaml['runlist'][n] overrides everything

begin
  yaml = YAML.load_file(yaml_filename)
rescue YAML::Error
  usage("could not load yaml_file")
end

settings = yaml['settings'] || Hash.new
runlist = yaml['runlist'] || Array.new

# merge $opts into settings
%w[user host port retries email vars].each { |cfg|
  opt = $opts[cfg.to_sym]
  settings[cfg] = opt if opt
}
$silent = opts.silent? || !settings['alert']
vars = settings['vars'] || []
vars = vars.split if vars.is_a?(String)

# begin SSH session
Net::SSH.start(settings.fetch('host'),
               settings.fetch('user'),
               port: settings.fetch('port'),
               forward_agent: true,
               send_env: vars,
               timeout: 10) { |ssh|

  # execute runlist with failure handling, retries, alerting, etc.
  runlist.each { |run|
    cmd = run.fetch('command')
    retries = run['retries'] || settings['retries']
    on_failure = run['on_failure'] || 'exit'

    begin
      Runsible.retry_ssh(ssh, cmd, retries)
    rescue CommandFailure, Net::SSH::Exception => e
      alert(settings['email'], "test_subject", e.to_s)
      case on_failure
      when 'exit'
        exit 1
      when 'continue'
        # ok
      else
        if yaml[on_failure]
          warn "on_failure: #{on_failure} found in YAML; not yet supported"
        else
          warn "unknown on_failure: #{on_failure}"
        end
        exit 1
      end
    end
  }
}
