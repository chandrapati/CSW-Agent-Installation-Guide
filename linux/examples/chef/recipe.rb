#
# Cookbook:: csw_sensor
# Recipe:: install (Pattern B — internal package repo)
#
# Required attributes (set via wrapper or environment):
#   node['csw_sensor']['activation_key']      (use Chef Vault)
#   node['csw_sensor']['scope_label']
#   node['csw_sensor']['repo']['baseurl_rpm']
#   node['csw_sensor']['repo']['baseurl_deb']
#   node['csw_sensor']['repo']['gpgkey_url']
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
else
  raise "Unsupported platform_family #{node['platform_family']}"
end

directory '/etc/tetration' do
  owner 'root'
  group 'root'
  mode  '0750'
  action :create
end

template '/etc/tetration/sensor.conf' do
  source    'sensor.conf.erb'
  owner     'root'
  group     'root'
  mode      '0640'
  sensitive true
  variables(
    activation_key: node['csw_sensor']['activation_key'],
    scope_label:    node['csw_sensor']['scope_label']
  )
  notifies :restart, 'service[csw-agent]', :delayed
end

package 'tet-sensor' do
  action :upgrade
end

service 'csw-agent' do
  supports status: true, restart: true, reload: false
  action   [:enable, :start]
end
