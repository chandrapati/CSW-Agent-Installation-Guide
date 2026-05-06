# Example Salt state file for CSW sensor — Pattern B (internal repo).
#
# Place under /srv/salt/csw_sensor/init.sls (or include from a top file).
#
# Required pillar:
#   csw_sensor:
#     activation_key: <string, encrypted via GPG-encrypted pillar>
#     scope_label:    <string>
#     repo:
#       baseurl:        <string>
#       gpgkey_url:     <string>
#       gpgkey_sha256:  <string>

{% set os_family = grains['os_family'] %}
{% set baseurl = pillar['csw_sensor']['repo']['baseurl'] %}
{% set gpgkey = pillar['csw_sensor']['repo']['gpgkey_url'] %}

{% if os_family == 'RedHat' %}
csw_yum_repo:
  pkgrepo.managed:
    - name: csw
    - humanname: Cisco Secure Workload Agents
    - baseurl: "{{ baseurl }}/el{{ grains['osmajorrelease'] }}/x86_64"
    - gpgcheck: 1
    - gpgkey: "{{ gpgkey }}"
    - enabled: 1
    - sslverify: 1
{% elif os_family == 'Debian' %}
csw_apt_keyring:
  file.managed:
    - name: /etc/apt/keyrings/csw-signing-key.asc
    - source: "{{ gpgkey }}"
    - source_hash: "{{ pillar['csw_sensor']['repo']['gpgkey_sha256'] }}"
    - mode: '0644'

csw_apt_source:
  pkgrepo.managed:
    - name: deb [signed-by=/etc/apt/keyrings/csw-signing-key.asc] {{ baseurl }} {{ grains['oscodename'] }} main
    - file: /etc/apt/sources.list.d/csw.list
    - require:
      - file: csw_apt_keyring
{% elif os_family == 'Suse' %}
csw_zypper_repo:
  pkgrepo.managed:
    - name: csw
    - humanname: Cisco Secure Workload Agents
    - baseurl: "{{ baseurl }}/sle{{ grains['osmajorrelease'] }}/x86_64"
    - gpgcheck: 1
    - gpgkey: "{{ gpgkey }}"
    - enabled: 1
{% endif %}

/etc/tetration:
  file.directory:
    - user: root
    - group: root
    - mode: '0750'

/etc/tetration/sensor.conf:
  file.managed:
    - source: salt://csw_sensor/files/sensor.conf.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: '0640'
    - context:
        activation_key: {{ pillar['csw_sensor']['activation_key'] }}
        scope_label: {{ pillar['csw_sensor']['scope_label'] }}
    - require:
      - file: /etc/tetration

tet-sensor:
  pkg.installed:
    - refresh: true
    - require:
      - file: /etc/tetration/sensor.conf

csw-agent:
  service.running:
    - enable: true
    - require:
      - pkg: tet-sensor
    - watch:
      - file: /etc/tetration/sensor.conf
