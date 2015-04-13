Gem::Specification.new do |s|
  s.name = 'runsible'
  s.required_ruby_version = "~> 2"
  s.version = File.read(File.join(__dir__, 'VERSION'))
  s.summary = 'Run remote tasks sanely via SSH with failure handling'
  s.description =
    'Runsible runs remote commands via net-ssh with retries and alerting'
  s.authors = ['Rick Hull']
  s.homepage = 'https://github.com/rickhull/runsible'
  s.license = 'GPL'

  s.files = [
    'runsible.gemspec',
    'VERSION',
    'lib/runsible.rb',
    'bin/runsible',
  ]
  s.executables = ['runsible']
  s.add_runtime_dependency 'slop', '~> 4.0'
  s.add_runtime_dependency 'net-ssh', '~> 2.7'
  s.add_runtime_dependency 'pony', '~> 1.0'

  s.add_development_dependency 'buildar', '~> 2.0'
end
