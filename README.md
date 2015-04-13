Runsible
========
Runsible uses [SSH](http://en.wikipedia.org/wiki/SSH)
(via [net/ssh](https://github.com/net-ssh/net-ssh)) to execute remote commands,
handling failures with retries and alerting.  It captures remote STDOUT and
STDERR and outputs them locally.  Commands are executed sequentially in a
"runlist".

An executable `runsible` is provided, which looks for a YAML file in the
command line arguments. The YAML file defines the runlist and settings, while
the command line options for `runsible` can override the YAML settings.

Features
--------
* Use SSH for remote transport and execution
* Use your local ssh_config, keys, agent, etc.
* Declare runlists and settings in YAML format
* Robust failure handling including:
  - Retries
  - Alerts via email (soon: [kafka](http://kafka.apache.org),
    [rabbitmq](http://rabbitmq.com), [slack](http://slack.com))
  - `continue` / `exit` / `cleanup` after command failure
* Runs locally - no remote software or agents to manage

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
The top-level YAML structure is a hash.  Primary keys are 'settings' and
'runlist', though neither are necessary.  Optionally you can define a
'cleanup' section and point to it with `on_failure: cleanup` in a runlist item.

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
Note that `vars` is not behaving as expected and is unsupported at the moment.
See https://github.com/net-ssh/net-ssh/issues/236 for details.

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

Note that the last `- command: true` runlist item will never execute.  The
previous `- command: false` with 2 retries will exit, since it doesn't have
`on_failure: continue`, and the default value is `exit`.

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
