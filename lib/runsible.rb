require 'pony'
require 'net/ssh'

class CommandFailure < RuntimeError; end

module Runsible
  def self.usage(opts, msg=nil)
    puts opts
    puts
    puts msg if msg
    exit 1
  end

  def self.email_alert(to, subject, body)
    Pony.mail(to: to,
              from: 'runsible@glassdoor.com',
              subject: subject,
              body: body)
  end

  # TODO: kafka_alert

  # prints remote STDOUT to local STDOUT, likewise for STDERR
  # raises on SSH channel exec failure or nonzero exit status
  def self.ssh_exec(ssh, cmd)
    exit_code = nil
    ssh.open_channel do |channel|
      channel.exec(command) do |ch, success|
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
  def self.ssh_retry(ssh, cmd, retries)
    self.banner_wrap(cmd) {
      success = false
      retries.times { |i|
        begin
          success = self.ssh_exec(ssh, cmd)
        rescue CommandFailure => e
          $stderr.puts e
          sleep 5
        end
        break if success
      }
      # the final retry, may blow up
      success or self.ssh_exec(ssh, cmd)
    }
  end

  def self.begin_banner(msg)
    "RUNSIBLE > #{self.timestamp} > #{msg} >>>"
  end

  def self.end_banner(msg)
    "<<< #{msg} < #{self.timestamp} < RUNSIBLE"
  end

  def self.timestamp(t = Time.now)
    t.strftime("%b%d %H:%M:%S")
  end

  def self.banner_wrap(msg)
    [$stdout, $stderr].each { |io| io.puts begin_banner(msg) }
    yield if block_given?
    [$stdout, $stderr].each { |io| io.puts end_banner(msg) }
    val
  end
end
