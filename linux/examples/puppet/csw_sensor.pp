# Example Puppet manifest for CSW sensor — Pattern B (internal repo).
#
# Place under modules/csw_sensor/manifests/init.pp in your code tree.
# Hiera lookups expected:
#   csw_sensor::activation_key  (encrypted with eyaml)
#   csw_sensor::scope_label
#   csw_sensor::repo_baseurl
#   csw_sensor::repo_gpgkey_url

class csw_sensor (
  Sensitive[String] $activation_key = Sensitive(lookup('csw_sensor::activation_key')),
  String            $scope_label    = lookup('csw_sensor::scope_label'),
  String            $repo_baseurl   = lookup('csw_sensor::repo_baseurl'),
  String            $repo_gpgkey    = lookup('csw_sensor::repo_gpgkey_url'),
) {

  case $facts['os']['family'] {
    'RedHat': {
      yumrepo { 'csw':
        descr     => 'Cisco Secure Workload Agents',
        baseurl   => "${repo_baseurl}/el${facts['os']['release']['major']}/x86_64",
        enabled   => '1',
        gpgcheck  => '1',
        gpgkey    => $repo_gpgkey,
        sslverify => 'true',
      }
    }
    'Debian': {
      include apt
      apt::source { 'csw':
        location => $repo_baseurl,
        release  => $facts['os']['distro']['codename'],
        repos    => 'main',
        key      => {
          'name'   => 'csw-signing-key.gpg',
          'source' => $repo_gpgkey,
        },
      }
    }
    'Suse': {
      # zypper-based; install zypprepo module or hand-place /etc/zypp/repos.d/csw.repo
      file { '/etc/zypp/repos.d/csw.repo':
        ensure  => file,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => epp('csw_sensor/zypp.repo.epp', {
          'baseurl' => "${repo_baseurl}/sle${facts['os']['release']['major']}/x86_64",
          'gpgkey'  => $repo_gpgkey,
        }),
      }
    }
    default: {
      fail("Unsupported OS family ${facts['os']['family']}")
    }
  }

  file { '/etc/tetration':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0750',
  }

  file { '/etc/tetration/sensor.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0640',
    content => Sensitive(epp('csw_sensor/sensor.conf.epp', {
      'activation_key' => $activation_key.unwrap,
      'scope_label'    => $scope_label,
    })),
    require => File['/etc/tetration'],
    notify  => Service['tetd'],
  }

  package { 'tet-sensor':
    ensure  => latest,
    require => [File['/etc/tetration/sensor.conf']],
  }

  service { 'tetd':
    ensure  => running,
    enable  => true,
    require => Package['tet-sensor'],
  }
}
