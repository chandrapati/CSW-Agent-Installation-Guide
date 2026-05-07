# Linux — Chef Recipe

Chef cookbook pattern for installing and maintaining the CSW
agent. Idiomatic, idempotent, and slots into existing Chef
codebases as a standalone cookbook or as a recipe in a wrapper.

> Working recipe in [`./examples/chef/`](./examples/chef/).

> **Authoritative source — please read.**
> Cisco's documented Linux installation method is the per-cluster
> **Agent Script Installer** (`install_sensor.sh`, generated from
> *Manage → Workloads → Agents → Installer* in the CSW UI). That
> script handles package install, CA placement, activation key
> wiring, and service enable end-to-end.
>
> The patterns below — manage the `.rpm`/`.deb` plus a Chef-
> templated `/etc/tetration/sensor.conf` and `/etc/tetration/ca.pem`
> — are a **community config-management convention**. The paths
> `/etc/tetration/sensor.conf` and `/etc/tetration/ca.pem` are
> **not** paths the Cisco-shipped agent reads by default; the
> agent's own config lives inside the install root (typically
> `/usr/local/tet/`). If you adopt this pattern, either generate
> an installer that has the activation key already baked in
> (Cisco-supported) or add a wrapper recipe that translates the
> `/etc/tetration/` files into the format your release of the
> agent actually consumes. If you don't already have that
> wrapper, prefer wrapping the CSW-generated `install_sensor.sh`
> in an `execute { ... }` resource instead.

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- Chef Infra Client 17+ on the node (any current version works)
- Either:
  - The CSW agent `.rpm` / `.deb` file in a cookbook `files/`
    directory (Pattern A — file push), or
  - An internal package repo containing `tet-sensor` (Pattern B —
    recommended for steady state)

---

## Cookbook layout

```
csw_sensor/
├── metadata.rb
├── attributes/
│   └── default.rb
├── recipes/
│   ├── default.rb
│   ├── repo.rb
│   └── install.rb
├── templates/
│   └── sensor.conf.erb
├── files/
│   └── (place tet-sensor .rpm / .deb here for Pattern A)
└── spec/
    └── (chefspec tests)
```

---

## `metadata.rb`

```ruby
name             'csw_sensor'
maintainer       'security-engineering'
license          'Apache-2.0'
description      'Installs and manages the Cisco Secure Workload sensor'
version          '1.0.0'
chef_version     '>= 17.0'

%w(redhat centos rocky almalinux oracle ubuntu debian suse opensuseleap amazon).each do |os|
  supports os
end
```

---

## `attributes/default.rb`

```ruby
default['csw_sensor']['package_filename']     = nil   # set in wrapper or env attribute
default['csw_sensor']['package_local_path']   = '/tmp/tet-sensor.pkg'
default['csw_sensor']['ca_path']              = '/etc/tetration/ca.pem'
default['csw_sensor']['conf_path']            = '/etc/tetration/sensor.conf'
default['csw_sensor']['service_name']         = 'csw-agent'

# Activation key MUST be set via encrypted data bag, Chef Vault,
# or environment attribute — never hardcode.
default['csw_sensor']['activation_key']       = nil
default['csw_sensor']['scope_label']          = nil

# Internal repo configuration (Pattern B)
default['csw_sensor']['repo']['baseurl_rpm']  = 'https://repo.internal.example.com/csw'
default['csw_sensor']['repo']['baseurl_deb']  = 'https://repo.internal.example.com/csw'
default['csw_sensor']['repo']['gpgkey_url']   = 'https://repo.internal.example.com/keys/csw-signing-key.asc'
```

---

## Pattern A — File-push recipe

### `recipes/default.rb` (Pattern A)

```ruby
#
# Cookbook:: csw_sensor
# Recipe:: default (Pattern A — file-push install)
#

unless node['csw_sensor']['package_filename']
  raise "node['csw_sensor']['package_filename'] must be set"
end

directory '/etc/tetration' do
  owner 'root'
  group 'root'
  mode  '0750'
  action :create
end

# Place the cluster CA chain (on-prem clusters)
cookbook_file node['csw_sensor']['ca_path'] do
  source 'ca.pem'
  owner  'root'
  group  'root'
  mode   '0644'
  only_if { ::File.exist?("#{Chef::Config[:cookbook_path]}/csw_sensor/files/default/ca.pem") rescue false }
end

# Activation config (sensor.conf)
template node['csw_sensor']['conf_path'] do
  source    'sensor.conf.erb'
  owner     'root'
  group     'root'
  mode      '0640'
  variables(
    activation_key: node['csw_sensor']['activation_key'],
    scope_label:    node['csw_sensor']['scope_label']
  )
  notifies :restart, "service[#{node['csw_sensor']['service_name']}]", :delayed
  only_if  { node['csw_sensor']['activation_key'] }
end

# Stage the package
cookbook_file node['csw_sensor']['package_local_path'] do
  source node['csw_sensor']['package_filename']
  owner  'root'
  group  'root'
  mode   '0644'
end

# Install via the right provider
case node['platform_family']
when 'rhel', 'amazon', 'fedora'
  rpm_package 'tet-sensor' do
    source node['csw_sensor']['package_local_path']
    action :install
  end
when 'debian'
  dpkg_package 'tet-sensor' do
    source node['csw_sensor']['package_local_path']
    action :install
  end
when 'suse', 'opensuse', 'opensuseleap'
  rpm_package 'tet-sensor' do
    source node['csw_sensor']['package_local_path']
    action :install
  end
else
  raise "Unsupported platform_family #{node['platform_family']}"
end

# Service
service node['csw_sensor']['service_name'] do
  action [:enable, :start]
end
```

### `templates/sensor.conf.erb`

```erb
# Managed by Chef — do not edit by hand.
ACTIVATION_KEY=<%= @activation_key %>
<% if @scope_label %>
SCOPE=<%= @scope_label %>
<% end %>
```

---

## Pattern B — Internal repo recipes (recommended for steady state)

### `recipes/repo.rb`

```ruby
#
# Cookbook:: csw_sensor
# Recipe:: repo (Pattern B — internal package repo)
#

case node['platform_family']
when 'rhel', 'amazon', 'fedora'
  yum_repository 'csw' do
    description 'Cisco Secure Workload Agents'
    baseurl     "#{node['csw_sensor']['repo']['baseurl_rpm']}/el#{node['platform_version'].to_i}/x86_64"
    gpgcheck    true
    gpgkey      node['csw_sensor']['repo']['gpgkey_url']
    enabled     true
    sslverify   true
    action      :create
  end
when 'debian'
  # Place the keyring
  remote_file '/etc/apt/keyrings/csw-signing-key.asc' do
    source node['csw_sensor']['repo']['gpgkey_url']
    owner  'root'
    group  'root'
    mode   '0644'
  end

  apt_repository 'csw' do
    uri          node['csw_sensor']['repo']['baseurl_deb']
    distribution node['lsb']['codename']
    components   ['main']
    keyserver    nil
    key          ['/etc/apt/keyrings/csw-signing-key.asc']
    deb_src      false
    action       :add
  end
when 'suse', 'opensuse', 'opensuseleap'
  zypper_repository 'csw' do
    description 'Cisco Secure Workload Agents'
    baseurl     "#{node['csw_sensor']['repo']['baseurl_rpm']}/sle#{node['platform_version'].to_i}/x86_64"
    gpgcheck    true
    gpgkey      node['csw_sensor']['repo']['gpgkey_url']
    action      :create
  end
end
```

### `recipes/install.rb`

```ruby
#
# Cookbook:: csw_sensor
# Recipe:: install (Pattern B)
#

include_recipe 'csw_sensor::repo'

directory '/etc/tetration' do
  owner 'root'
  group 'root'
  mode  '0750'
  action :create
end

template node['csw_sensor']['conf_path'] do
  source    'sensor.conf.erb'
  owner     'root'
  group     'root'
  mode      '0640'
  variables(
    activation_key: node['csw_sensor']['activation_key'],
    scope_label:    node['csw_sensor']['scope_label']
  )
  notifies  :restart, "service[#{node['csw_sensor']['service_name']}]", :delayed
end

package 'tet-sensor' do
  action :upgrade           # or :install for fixed version pinned via package version attr
end

service node['csw_sensor']['service_name'] do
  action [:enable, :start]
end
```

---

## Activation key handling — Chef Vault

Never hardcode the activation key. Use Chef Vault:

```bash
# Create the vault item once
knife vault create csw_sensor activation_key \
  --json '{ "key": "<key-from-CSW-UI>" }' \
  --search 'role:web AND chef_environment:prod' \
  --admins 'security-team'

# Rotate
knife vault rotate keys csw_sensor activation_key
```

In the recipe:

```ruby
chef_vault_secret = ChefVault::Item.load('csw_sensor', 'activation_key')
node.default['csw_sensor']['activation_key'] = chef_vault_secret['key']
```

(Or pass via an environment attribute populated from a chef-managed
secrets pipeline.)

---

## Wrapper cookbook example

```ruby
#
# Cookbook:: profile_base
# Recipe:: csw_sensor
#

# Set environment-specific attributes
node.default['csw_sensor']['scope_label'] =
  case node.chef_environment
  when 'prod'  then 'prod:web-tier'
  when 'stage' then 'stage:web-tier'
  else 'dev:default'
  end

# Source activation key from Chef Vault
csw_secret = ChefVault::Item.load('csw_sensor', "activation_key_#{node.chef_environment}")
node.default['csw_sensor']['activation_key'] = csw_secret['key']

# Apply
include_recipe 'csw_sensor::install'
```

---

## ChefSpec test scaffold

```ruby
require 'chefspec'

describe 'csw_sensor::install' do
  context 'on RHEL 9' do
    let(:chef_run) do
      ChefSpec::ServerRunner.new(platform: 'redhat', version: '9') do |node|
        node.normal['csw_sensor']['activation_key'] = 'test-key'
        node.normal['csw_sensor']['scope_label']    = 'test-scope'
      end.converge('csw_sensor::install')
    end

    it 'creates the yum repo' do
      expect(chef_run).to create_yum_repository('csw')
    end

    it 'installs tet-sensor' do
      expect(chef_run).to upgrade_package('tet-sensor')
    end

    it 'enables and starts csw-agent' do
      expect(chef_run).to enable_service('csw-agent')
      expect(chef_run).to start_service('csw-agent')
    end
  end
end
```

---

## When this is the right method

- **Fleet already managed by Chef.** Drop the cookbook in; works
  with your existing Chef Infra Server / Automate workflow.
- **Mixed Linux estate.** The `package`/`service` abstraction
  covers RHEL, Ubuntu, SUSE in one cookbook.

## When this is NOT the right method

- **Greenfield with no existing Chef investment.** Stand up
  Ansible instead — lower start-up cost.
- **Cloud-native estate where image baking is the norm.** Chef
  works in cloud, but Golden AMI / Compute Gallery
  ([cloud/05-golden-ami.md](../cloud/05-golden-ami.md)) is often
  the better fit.

---

## See also

- [`./examples/chef/`](./examples/chef/) — runnable cookbook scaffold
- [`04-ansible.md`](./04-ansible.md), [`05-puppet.md`](./05-puppet.md), [`07-saltstack.md`](./07-saltstack.md)
- [`03-package-repo-satellite.md`](./03-package-repo-satellite.md) — for Pattern B
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md)
