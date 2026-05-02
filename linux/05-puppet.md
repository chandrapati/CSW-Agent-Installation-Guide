# Linux — Puppet Manifest

Puppet pattern for installing and maintaining the CSW agent.
Idiomatic, idempotent, and slots into existing Puppet codebases
as a standalone module or a class in a profile.

> Working manifest in [`./examples/puppet/`](./examples/puppet/).

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- Puppet 6+ on the agent (any current version works)
- Either:
  - The CSW agent `.rpm` / `.deb` file available (Pattern A — file
    push), or
  - An internal package repo containing `tet-sensor` (Pattern B —
    recommended for steady state)

---

## Pattern A — File push (manifest places the package, then installs)

Suitable for small fleets and air-gapped Puppet masters that
serve their own files.

### `manifests/init.pp`

```puppet
# @summary Install and manage the Cisco Secure Workload sensor
#
# @param sensor_package_source
#   Puppet file source URL of the .rpm/.deb package, e.g.
#   'puppet:///modules/csw_sensor/tet-sensor-3.x.y.z-1.el9.x86_64.rpm'.
#
# @param ca_source
#   Puppet file source URL for the cluster CA chain (on-prem clusters).
#
# @param activation_key
#   Activation key from CSW Manage → Agents → Install Agent.
#   Should come from Hiera + eyaml, never plain text.
#
# @param scope_label
#   Optional scope label key=value for first-registration assignment.
class csw_sensor (
  String $sensor_package_source,
  String $ca_source = '',
  String $activation_key = '',
  String $scope_label = '',
) {

  $package_local_path = '/tmp/tet-sensor.pkg'
  $sensor_conf        = '/etc/tetration/sensor.conf'
  $ca_path            = '/etc/tetration/ca.pem'

  file { '/etc/tetration':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0750',
  }

  if $ca_source != '' {
    file { $ca_path:
      ensure => file,
      source => $ca_source,
      owner  => 'root',
      group  => 'root',
      mode   => '0644',
      require => File['/etc/tetration'],
      before  => Package['tet-sensor'],
    }
  }

  if $activation_key != '' {
    file { $sensor_conf:
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0640',
      content => epp('csw_sensor/sensor.conf.epp', {
        'activation_key' => $activation_key,
        'scope_label'    => $scope_label,
      }),
      require => File['/etc/tetration'],
      before  => Package['tet-sensor'],
    }
  }

  file { $package_local_path:
    ensure  => file,
    source  => $sensor_package_source,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
  }

  package { 'tet-sensor':
    ensure   => installed,
    provider => $facts['os']['family'] ? {
      'RedHat'   => 'rpm',
      'Debian'   => 'dpkg',
      'Suse'     => 'rpm',
      default    => undef,
    },
    source   => $package_local_path,
    require  => File[$package_local_path],
  }

  service { 'tetd':
    ensure  => running,
    enable  => true,
    require => Package['tet-sensor'],
  }
}
```

### `templates/sensor.conf.epp`

```puppet
<%- |
  String $activation_key,
  String $scope_label,
| -%>
# Managed by Puppet — do not edit by hand.
ACTIVATION_KEY=<%= $activation_key %>
<%- if $scope_label != '' { -%>
SCOPE=<%= $scope_label %>
<%- } -%>
```

### Hiera secrets (encrypted with eyaml)

```yaml
# data/role/web.yaml
csw_sensor::activation_key: 'ENC[PKCS7,...encrypted...]'
csw_sensor::scope_label: 'prod:web-tier'
```

### Profile usage

```puppet
class profile::base::csw_sensor {
  class { 'csw_sensor':
    sensor_package_source => 'puppet:///modules/csw_sensor/tet-sensor-3.x.y.z-1.el9.x86_64.rpm',
    ca_source             => 'puppet:///modules/csw_sensor/ca.pem',
    activation_key        => lookup('csw_sensor::activation_key'),
    scope_label           => lookup('csw_sensor::scope_label'),
  }
}
```

---

## Pattern B — Internal repo (recommended for steady state)

Combine [`03-package-repo-satellite.md`](./03-package-repo-satellite.md)
with Puppet's native `yumrepo` / `apt::source` resources.

### `manifests/repo.pp`

```puppet
class csw_sensor::repo {

  case $facts['os']['family'] {
    'RedHat': {
      yumrepo { 'csw':
        descr     => 'Cisco Secure Workload Agents',
        baseurl   => "https://repo.internal.example.com/csw/el${facts['os']['release']['major']}/x86_64",
        enabled   => '1',
        gpgcheck  => '1',
        gpgkey    => 'https://repo.internal.example.com/keys/csw-signing-key.asc',
        sslverify => 'true',
      }
    }
    'Debian': {
      include apt
      apt::source { 'csw':
        location => 'https://repo.internal.example.com/csw',
        release  => $facts['os']['distro']['codename'],
        repos    => 'main',
        key      => {
          'name'   => 'csw-signing-key.gpg',
          'source' => 'https://repo.internal.example.com/keys/csw-signing-key.asc',
        },
      }
    }
    default: {
      fail("Unsupported OS family ${facts['os']['family']}")
    }
  }
}
```

### `manifests/install.pp`

```puppet
class csw_sensor::install {
  include csw_sensor::repo

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
    content => epp('csw_sensor/sensor.conf.epp', {
      'activation_key' => lookup('csw_sensor::activation_key'),
      'scope_label'    => lookup('csw_sensor::scope_label', { 'default_value' => '' }),
    }),
    require => File['/etc/tetration'],
    before  => Package['tet-sensor'],
  }

  package { 'tet-sensor':
    ensure  => latest,                        # use 'present' for fixed version
    require => Class['csw_sensor::repo'],
  }

  service { 'tetd':
    ensure  => running,
    enable  => true,
    require => Package['tet-sensor'],
  }
}
```

For pinned versions:

```puppet
package { 'tet-sensor':
  ensure => '3.10.1.45',
}
```

### Profile

```puppet
class profile::base::csw_sensor {
  include csw_sensor::install
}
```

---

## Wave-based rollout via Puppet environments / fact-driven gating

Puppet's natural unit of pacing is the **environment** (Puppet
environments, not Linux ones). Standard pattern:

- `production` environment runs the manifest with the current
  approved version
- `staging` environment is one version ahead
- `development` environment tracks newest

Migrate hosts between environments to drive waves.

For finer control without environment moves, gate on a fact:

```puppet
# manifests/init.pp
class csw_sensor (
  ...
) {
  if $facts['csw_rollout_wave'] in ['lab', 'stage', 'prod_wave_1'] {
    # apply install class
    include csw_sensor::install
  } else {
    notify { "Host ${facts['fqdn']} not in current CSW rollout wave; skipping": }
  }
}
```

Set `csw_rollout_wave` via a custom fact, ENC, or PuppetDB query.
The wave moves forward by changing the fact value across batches
of hosts.

---

## Verification (puppet apply --noop or PE Console reports)

The standard Puppet feedback loop covers verification:

- Run reports show `Service[tetd] ensure=running` per host
- PuppetDB query `select certname, value from facts where name='csw_agent_active'` (after a custom fact is added) gives a fleet view
- Combined with the CSW UI's *Manage → Agents* sensor health
  view, you have two-source confirmation

A custom fact for sensor health:

```ruby
# lib/facter/csw_agent_active.rb
Facter.add(:csw_agent_active) do
  setcode do
    Facter::Core::Execution.execute('systemctl is-active tetd', timeout: 5).strip == 'active'
  end
end
```

---

## When this is the right method

- **Fleet already managed by Puppet.** Drop the module in;
  re-uses your existing Puppet operational model (PE Console,
  reports, environments, PuppetDB queries).
- **Mixed Linux estate.** The `package`/`service` abstraction
  gives you one manifest across RHEL, Ubuntu, SUSE.

## When this is NOT the right method

- **Greenfield with no existing Puppet investment.** Standing up
  Puppet just for CSW is overkill — Ansible has a lower
  set-up cost.
- **Cloud-native estate where image baking is the norm.**
  Puppet works in cloud, but the Golden AMI / Compute Gallery
  pattern ([cloud/05-golden-ami.md](../cloud/05-golden-ami.md))
  is often the better fit.

---

## See also

- [`./examples/puppet/`](./examples/puppet/) — runnable manifest + EPP template + Hiera example
- [`04-ansible.md`](./04-ansible.md), [`06-chef.md`](./06-chef.md), [`07-saltstack.md`](./07-saltstack.md)
- [`03-package-repo-satellite.md`](./03-package-repo-satellite.md) — for Pattern B
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md)
