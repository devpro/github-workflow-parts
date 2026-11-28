# @summary writes a file, so that the acceptance test applies a change without root access
#
# @param path
#   the file to write
class fixture (
  String[1] $path = '/tmp/puppet-fixture.txt',
) {
  file { $path:
    ensure  => file,
    content => "managed by Puppet\n",
  }
}
