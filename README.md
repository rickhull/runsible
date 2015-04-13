Runsible
========
Runsible uses SSH to execute remote commands, handling failures with retries
and alerting.  It captures remote STDOUT and STDERR and outputs them locally.
Commands are executed sequentially in a "runlist".

An executable `runsible` is provided, which parses a YAML file which is
provided as a command line argument.  The YAML file defines the runlist and
settings, while the command line options for `runsible` can override the
YAML settings.

Features
--------
* Use SSH for remote transport and execution
* Declare runlists and settings in YAML format
* Robust failure handling including:
  - Retries
  - Alerts via email (soon: kafka, rabbitmq, slack)
  - continue / exit / cleanup after command failure

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

YAML Configuration
------------------
Top-level yaml structure is a hash.  Primary keys are 'settings' and 'runlist',
though neither are necessary.  Optionally you can define a 'cleanup' section,
and point to it with `on_failure: cleanup` in your runlist.

The minimal YAML file is empty.  `runsible empty.yaml` will use internal
defaults to attempt to SSH to `127.0.0.1:22` as the current user.

*Maximal Settings Example*
```
settings:
  silent: no
  retries: 5
  alerts:
    backend: email
    address: foo@bar
  user: root
  host: runsible.com
  port: 80
  vars: FOO BAR BAZ
```

All of the above is optional.

*Maximal Runlist Example*
```
runlist:
  - command: false
    retries: 3
    on_failure: continue
  - command: true
    on_failure: exit
  - command: false
    retries: 2
  - command: true
```

The last `- command: true` will never execute.  The previous `false` with 2
retries will exit, since it doesn't have `on_failure: continue`.
```

*Empty Runlist*

The ssh connection will still be attempted according to defaults and any
settings provided.  The connection will be closed immediately.

Commands
--------

Commands are executed sectionally within a runlist.  They are executed
within the context of a remote shell provided by SSH.  Shell exit code is
used to determine success or failure.  On a successful command, execution
proceeds to the next command in the runlist.  On failure, if there are retries
configured for the command, it will be retried after a short delay.  If the
last try fails, then an alert goes out, and the `on_failure` configuration
determines the flow of execution.  `on_failure: exit` is the default,
aborting the runlist and causing `runsible` to exit with non-zero status code.
`on_failure: continue` is another common option.
