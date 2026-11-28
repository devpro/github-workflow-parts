# @summary runs a command at each run, so that the acceptance test finds the second run not idempotent
class not_idempotent {
  exec { 'touch a file':
    command => '/usr/bin/touch /tmp/puppet-not-idempotent.txt',
  }
}
