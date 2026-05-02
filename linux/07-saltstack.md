# Linux — Salt State

SaltStack pattern for installing and maintaining the CSW agent.
Idiomatic, idempotent, and fits as either a standalone formula or
a state in an existing top file.

> Working state in [`./examples/salt/`](./examples/salt/).

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- SaltStack 3005+ (any current version works)
- Salt master with file_roots configured to host the cookbook /
  formula
- Either:
  - The CSW agent `.rpm` / `.deb` file in the master's file
    roots (Pattern A — file push), or
  - An internal package repo containing `tet-sensor` (Pattern B —
    recommended for steady state)

---

## Formula layout

```
csw_sensor/
├── init.sls                 # entry point — selects pattern A or B
├── repo.sls                 # internal repo source (Pattern B)
├── install.sls              # install + activation
├── service.sls              # ensure tetd running
├── files/
│   ├── sensor.conf.jinja    # rendered to /etc/tetration/sensor.conf
│   └── (tet-sensor packages for Pattern A)
├── pillar.example/
│   └── csw_sensor.sls       # example pillar (activation key, scope)
└── map.jinja                # OS-family-specific values
```

---

## `map.jinja`

```jinja
{% set csw_sensor = salt['grains.filter_by']({
    'RedHat': {
        'package_provider': 'pkg.installed',
        'pkg_url_path': 'el' ~ grains['osmajorrelease'] ~ '/x86_64',
        'service_provider': 'systemd',
    },
    'Debian': {
        'package_provider': 'pkg.installed',
        'pkg_url_path': grains['oscodename'],
        'service_provider': 'systemd',
    },
    'Suse': {
        'package_provider': 'pkg.installed',
        'pkg_url_path': 'sle' ~ grains['osmajorrelease'] ~ '/x86_64',
        'service_provider': 'systemd',
    },
}, grain='os_family', merge=salt['pillar.get']('csw_sensor:lookup')) %}
```

---

## Pattern B — internal repo (recommended)

### `repo.sls`

```jinja
{% from 'csw_sensor/map.jinja' import csw_sensor with context %}
{% set repo_baseurl = pillar['csw_sensor']['repo']['baseurl'] %}
{% set repo_gpgkey = pillar['csw_sensor']['repo']['gpgkey_url'] %}

{% if grains['os_family'] == 'RedHat' %}
csw_yum_repo:
  pkgrepo.managed:
    - name: csw
    - humanname: Cisco Secure Workload Agents
    - baseurl: "{{ repo_baseurl }}/{{ csw_sensor.pkg_url_path }}"
    - gpgcheck: 1
    - gpgkey: "{{ repo_gpgkey }}"
    - enabled: 1
    - sslverify: 1
{% elif grains['os_family'] == 'Debian' %}
csw_apt_keyring:
  file.managed:
    - name: /etc/apt/keyrings/csw-signing-key.asc
    - source: "{{ repo_gpgkey }}"
    - source_hash: "{{ pillar['csw_sensor']['repo']['gpgkey_sha256'] }}"
    - mode: '0644'

csw_apt_source:
  pkgrepo.managed:
    - name: deb [signed-by=/etc/apt/keyrings/csw-signing-key.asc] {{ repo_baseurl }} {{ csw_sensor.pkg_url_path }} main
    - file: /etc/apt/sources.list.d/csw.list
    - require:
      - file: csw_apt_keyring
{% elif grains['os_family'] == 'Suse' %}
csw_zypper_repo:
  pkgrepo.managed:
    - name: csw
    - humanname: Cisco Secure Workload Agents
    - baseurl: "{{ repo_baseurl }}/{{ csw_sensor.pkg_url_path }}"
    - gpgcheck: 1
    - gpgkey: "{{ repo_gpgkey }}"
    - enabled: 1
{% endif %}
```

### `install.sls`

```jinja
{% from 'csw_sensor/map.jinja' import csw_sensor with context %}

include:
  - csw_sensor.repo

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
        scope_label: {{ pillar['csw_sensor'].get('scope_label', '') }}
    - require:
      - file: /etc/tetration

tet-sensor:
  pkg.installed:
    - refresh: true
    - require:
      - file: /etc/tetration/sensor.conf
{% if grains['os_family'] == 'RedHat' %}
      - pkgrepo: csw_yum_repo
{% elif grains['os_family'] == 'Debian' %}
      - pkgrepo: csw_apt_source
{% elif grains['os_family'] == 'Suse' %}
      - pkgrepo: csw_zypper_repo
{% endif %}
```

### `service.sls`

```yaml
include:
  - csw_sensor.install

tetd:
  service.running:
    - enable: true
    - require:
      - pkg: tet-sensor
    - watch:
      - file: /etc/tetration/sensor.conf
```

### `init.sls`

```yaml
include:
  - csw_sensor.service
```

### `files/sensor.conf.jinja`

```jinja
# Managed by Salt — do not edit by hand.
ACTIVATION_KEY={{ activation_key }}
{% if scope_label %}
SCOPE={{ scope_label }}
{% endif %}
```

---

## Pillar (secrets) — `pillar.example/csw_sensor.sls`

```yaml
csw_sensor:
  activation_key: ENC[GPG,...encrypted with master GPG key...]
  scope_label: prod:web-tier
  repo:
    baseurl: https://repo.internal.example.com/csw
    gpgkey_url: https://repo.internal.example.com/keys/csw-signing-key.asc
    gpgkey_sha256: <sha256-of-key-file>
```

Encrypt with [GPG-encrypted pillar](https://docs.saltproject.io/en/latest/topics/pillar/index.html#encrypted-pillars):

```bash
echo -n 'real-activation-key' | gpg --armor --batch --trust-model always --encrypt -r 'salt-master-key'
```

Bind to targeted minions:

```yaml
# /etc/salt/pillar/top.sls
base:
  'G@os_family:RedHat and I@business_unit:web':
    - csw_sensor
```

---

## Top file inclusion

```yaml
# /srv/salt/top.sls
base:
  'csw_targets':
    - csw_sensor
```

Apply:

```bash
# Wave 0 — lab
salt -G 'environment:lab' state.apply csw_sensor

# Wave 1 — stage
salt -G 'environment:stage' state.apply csw_sensor

# Wave 2 — prod (in batches via salt-ssh or with a batch percentage)
salt -G 'environment:prod' state.apply csw_sensor --batch-size=10%
```

---

## Verification with a custom grain

```python
# /srv/salt/_grains/csw_sensor_active.py
import subprocess

def csw_sensor_active():
    try:
        out = subprocess.run(['systemctl', 'is-active', 'tetd'], capture_output=True, text=True, timeout=5)
        return {'csw_sensor_active': out.stdout.strip() == 'active'}
    except Exception:
        return {'csw_sensor_active': False}
```

Refresh the grain after install:

```bash
salt '*' saltutil.sync_grains
salt '*' grains.item csw_sensor_active
```

---

## When this is the right method

- **Fleet already managed by Salt.** Re-uses your existing master,
  pillar, and grain workflow.
- **Reactor-driven workflows.** Salt's event bus + reactor is a
  good fit for "on host registration → apply csw_sensor state".

## When this is NOT the right method

- **Greenfield without existing Salt investment.** Lower-cost
  options exist.

---

## See also

- [`./examples/salt/`](./examples/salt/) — runnable formula scaffold
- [`04-ansible.md`](./04-ansible.md), [`05-puppet.md`](./05-puppet.md), [`06-chef.md`](./06-chef.md)
- [`03-package-repo-satellite.md`](./03-package-repo-satellite.md) — for Pattern B
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md)
