#!/usr/bin/env ruby

require 'yaml'
require 'slop'
require 'runsible'

$opts = Slop.parse do |o|
  o.banner = "usage: runcible.rb [options] yaml_file"
  o.string '-u', '--user',    "remote user [#{ENV['USER']}]]", default: ENV['USER']
  o.string '-H', '--host',    'remote host [127.0.0.1]', default: "127.0.0.1"
  o.int    '-p', '--port',    'remote port [22]',        default: 22
  o.int    '-r', '--retries', 'number of retry attempts [0]', default: 0
  o.string '-m', '--email',   'where to send email alerts'
  o.bool   '-s', '--silent',  'suppress alerts'
  o.string '-v', '--vars',    'list of vars to pass thru, e.g.: "FOO BAR"'
end

def alert(to, subject, body)
  Runsible.email_alert(to, subject, body) unless $silent
end

def usage(msg = nil)
  Runsible.usage($opts, msg)
end

yaml_filename = $opts.arguments.shift
usage("yaml_file is a required argument") if yaml_filename.nil?

begin
  yaml = YAML.load_file(yaml_filename)
rescue YAML::Error
  usage("could not load yaml_file")
end

settings = yaml['settings'] || Hash.new
runlist = yaml['runlist'] || Array.new

# yaml['settings'] provides static defaults
# $opts can override yaml['settings']
# yaml['runlist'][n] overrides everything

# merge $opts into settings
%w[user host port retries email vars silent].each { |cfg|
  opt = $opts[cfg.to_sym]
  settings[cfg] = opt if opt
}

#if !vars.empty?
#  Runsible.warn "SSH :send_env does not behave as expected"
#  Runsible.warn "vars (#{vars.join(' ')}) will be ignored!"
#end

Runsible.ssh_runlist(settings, runlist, Hash.new, yaml)
