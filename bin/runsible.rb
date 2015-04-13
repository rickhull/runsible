#!/usr/bin/env ruby

require 'yaml'
require 'slop'
require 'runsible'

opts = Slop.parse do |o|
  o.banner = "usage: runcible.rb [options] yaml_file"
  o.string '-u', '--user',    "remote user [#{ENV['USER']}]]", default: ENV['USER']
  o.string '-H', '--host',    'remote host [127.0.0.1]', default: "127.0.0.1"
  o.int    '-p', '--port',    'remote port [22]',        default: 22
  o.int    '-r', '--retries', 'number of retry attempts [0]', default: 0
  o.bool   '-s', '--silent',  'suppress alerts'
  # this feature does not yet work as expected
  # https://github.com/net-ssh/net-ssh/issues/236
  #  o.string '-v', '--vars',    'list of vars to pass thru, e.g.: "FOO BAR"'
end

yaml_filename = opts.arguments.shift
Runsible.usage(opts, "yaml_file is a required argument") if yaml_filename.nil?

begin
  yaml = YAML.load_file(yaml_filename)
rescue YAML::Error
  Runsible.usage(opts, "could not load yaml_file")
end

settings = yaml['settings'] || Hash.new
runlist = yaml['runlist'] || Array.new

# runlist > opts > settings; merge opts into settings
%w[user host port retries vars silent].each { |cfg|
  opt = opts[cfg.to_sym]
  settings[cfg] = opt if opt
}

Runsible.ssh_runlist(settings, runlist, Hash.new, yaml)
