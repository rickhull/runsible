[![Gem Version](https://badge.fury.io/rb/runsible.svg)](http://badge.fury.io/rb/runsible)

Runsible
========
Runsible uses [SSH](http://en.wikipedia.org/wiki/Secure_Shell)
(via [net-ssh](https://github.com/net-ssh/net-ssh)) to execute remote commands,
handling failures with retries and alerting.  It captures remote STDOUT and
STDERR and outputs them locally.  Commands are executed sequentially in a
"runlist".

An executable `runsible` is provided, which looks for a
[YAML](http://en.wikipedia.org/wiki/YAML) file in the command line arguments.
The YAML file defines the runlist and settings, while the command line options
for `runsible` can override the YAML settings.

Features
--------
* Use SSH for remote transport and execution
  - Use your local ssh_config, keys, agent, etc.
* Declare runlists and settings in YAML format
* Robust failure handling including:
  - Retries
  - Alerts via [email](https://github.com/benprew/pony)
    (soon: [kafka](http://kafka.apache.org),
           [rabbitmq](http://rabbitmq.com),
           [slack](http://slack.com))
  - `continue` / `exit` / `cleanup`
* Runs locally - no additional software or agents to manage on the command
  target
  - Command target must be running SSH service

Installation
------------
Install the gem:

```
$ gem install runsible       # sudo as necessary
```
Or, if using [Bundler](http://bundler.io/), add to your Gemfile:

```ruby
gem 'runsible', '~> 0.1'
```

Usage
-----

`runsible /path/to/file.yaml`

```
$ runsible -h
usage: runsible [options] yaml_file
    -h, --help
    -v, --version  show runsible version
    -u, --user     remote user [rwh]
    -H, --host     remote host [127.0.0.1]
    -p, --port     remote port [22]
    -r, --retries  retry count [0]
    -s, --silent   suppress alerts
```

YAML Configuration
------------------
The top-level YAML structure is a hash.  Primary keys are 'settings' and
'runlist', though neither are necessary.  Optionally you can define a
'cleanup' section and point to it with `on_failure: cleanup` in a runlist item.

The minimal YAML file is empty.  `runsible empty.yaml` will use internal
defaults to attempt to SSH to `127.0.0.1:22` as the current user.

*Real-world Example*
```
settings:
  user: root
  alerts:
    backend: email
    address: alerts@bigco.local

runlist:
  - command: ./setup_fs
  - command: source anaconda/bin/activate graphlab
  - command: python scorer.py
    retries: 5
    on_failure: cleanup

cleanup:
  - command: python wipe_cache.py
```

*Maximal Settings Example*
```
settings:
  silent: no
  retries: 5
  alerts:
    backend: email
    address: alerts@bigco.local
  user: root
  host: bigco.local
  port: 80
  vars: FOO BAR BAZ
```

All of the above is optional.
Note that `vars` is not behaving as expected and is unsupported at the moment.
See https://github.com/net-ssh/net-ssh/issues/236 for details.

*Simple Runlist Example*
```
runlist:
  - command: false
    retries: 3
    on_failure: continue
  - command: true
  - command: false
  - command: true
```

Note that the last `- command: true` runlist item will never execute.  The
previous `- command: false` will exit, since it doesn't have
`on_failure: continue` and the default value is `exit`.

*Empty Runlist*

The SSH connection will still be attempted according to defaults and any
settings provided.  The connection will be closed immediately.


Commands
--------

* Commands are executed in the context of a remote shell provided by SSH
* Commands are executed sequentially within a runlist
* Shell exit code determines command success or failure
* On success, execution proceeds to the next command in the runlist
* On failure, if there are retries configured, the command will be retried
  after a short delay
* When retries are exhausted, an alert goes out, and `on_failure` determines
  the flow of execution
  - `exit` is the default, aborting the runlist and causing `runsible` to exit
     with non-zero status code
  - `continue` is used to proceed to the next command in the runlist
  - `cleanup` proceeds to another runlist keyed by `cleanup`
