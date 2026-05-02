# Linux — Ansible Playbook

The most common enterprise pattern for Linux fleets. Ansible
handles inventory, parallel execution, retry logic, and audit
logging — all the things a one-shot script doesn't. Pair Ansible
with either a CSW-generated installer or an internal package repo
for fully automated, idempotent rollout and upgrade.

> Working playbooks and inventory examples in
> [`./examples/ansible/`](./examples/ansible/).

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- Ansible 2.12+ (any current version works)
- An Ansible inventory of target hosts with SSH access and
  `become` privilege
- Either:
  - The CSW-generated `install_sensor.sh` (per scope) — Pattern A,
  - The CSW agent `.rpm` / `.deb` packages — Pattern B (manual), or
  - An internal package repo containing `tet-sensor` — Pattern C
    (recommended for steady state)

---

## Pattern A — Push the CSW-generated installer

Simplest. Treats the script as an opaque blob that does the right
thing per host.

### `playbook-install-script.yml`

```yaml
---
- name: Install Cisco Secure Workload sensor (CSW-generated script)
  hosts: csw_targets
  become: true
  gather_facts: true
  vars:
    csw_installer_local_path: "files/install_sensor.sh"
    csw_installer_remote_path: "/tmp/install_sensor.sh"

  tasks:
    - name: Verify the OS is on the supported list
      ansible.builtin.assert:
        that:
          - ansible_facts['os_family'] in ['RedHat', 'Debian', 'Suse']
        fail_msg: "OS family {{ ansible_facts['os_family'] }} not supported by this play"

    - name: Copy installer to target
      ansible.builtin.copy:
        src: "{{ csw_installer_local_path }}"
        dest: "{{ csw_installer_remote_path }}"
        owner: root
        group: root
        mode: '0700'

    - name: Run installer (idempotent — script no-ops if sensor already present)
      ansible.builtin.command:
        cmd: "{{ csw_installer_remote_path }} --silent"
        creates: /usr/local/tet/tet-sensor
      register: csw_install
      timeout: 600

    - name: Show installer output (on first install)
      ansible.builtin.debug:
        var: csw_install.stdout_lines
      when: csw_install.changed

    - name: Ensure tetd is running and enabled
      ansible.builtin.systemd:
        name: tetd
        state: started
        enabled: true
        daemon_reload: true

    - name: Remove installer copy
      ansible.builtin.file:
        path: "{{ csw_installer_remote_path }}"
        state: absent
```

### Inventory shape

```ini
# inventory/csw-targets.ini
[csw_targets:children]
prod_linux
stage_linux

[prod_linux]
prod-web-[01:20].example.com
prod-app-[01:30].example.com

[stage_linux]
stage-web-[01:05].example.com
```

### Run

```bash
# Wave 1 — stage
ansible-playbook -i inventory/csw-targets.ini \
  --limit stage_linux \
  playbook-install-script.yml

# Wave 2 — prod (after stage validation)
ansible-playbook -i inventory/csw-targets.ini \
  --limit prod_linux \
  playbook-install-script.yml
```

---

## Pattern B — Push the package directly (no internal repo)

Suitable when you have the package files but don't want to stand
up an internal repo.

### `playbook-install-package.yml`

```yaml
---
- name: Install Cisco Secure Workload sensor (direct package push)
  hosts: csw_targets
  become: true
  gather_facts: true
  vars:
    csw_package_local_dir: "files/packages"
    csw_package_remote_path: "/tmp/tet-sensor.pkg"
    csw_ca_local_path: "files/ca.pem"

  tasks:
    - name: Choose package per OS family
      ansible.builtin.set_fact:
        csw_package_filename: >-
          {%- if ansible_facts['os_family'] == 'RedHat' and ansible_facts['distribution_major_version'] in ['7'] -%}
            tet-sensor-3.x.y.z-1.el7.x86_64.rpm
          {%- elif ansible_facts['os_family'] == 'RedHat' and ansible_facts['distribution_major_version'] in ['8','9'] -%}
            tet-sensor-3.x.y.z-1.el9.x86_64.rpm
          {%- elif ansible_facts['os_family'] == 'Debian' and ansible_facts['distribution_version'] is search('^20') -%}
            tet-sensor-3.x.y.z-1.ubuntu20_amd64.deb
          {%- elif ansible_facts['os_family'] == 'Debian' and ansible_facts['distribution_version'] is search('^22') -%}
            tet-sensor-3.x.y.z-1.ubuntu22_amd64.deb
          {%- elif ansible_facts['os_family'] == 'Suse' -%}
            tet-sensor-3.x.y.z-1.sle15.x86_64.rpm
          {%- else -%}
            UNSUPPORTED
          {%- endif -%}

    - name: Fail if OS / version isn't on the supported list
      ansible.builtin.fail:
        msg: "No package mapped for {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}"
      when: csw_package_filename == 'UNSUPPORTED'

    - name: Ensure /etc/tetration exists
      ansible.builtin.file:
        path: /etc/tetration
        state: directory
        owner: root
        group: root
        mode: '0750'

    - name: Place cluster CA chain (on-prem clusters; harmless for SaaS)
      ansible.builtin.copy:
        src: "{{ csw_ca_local_path }}"
        dest: /etc/tetration/ca.pem
        owner: root
        group: root
        mode: '0644'
      when: csw_ca_local_path is defined

    - name: Copy agent package to target
      ansible.builtin.copy:
        src: "{{ csw_package_local_dir }}/{{ csw_package_filename }}"
        dest: "{{ csw_package_remote_path }}"
        owner: root
        group: root
        mode: '0644'

    - name: Install on RPM-based hosts
      ansible.builtin.dnf:
        name: "{{ csw_package_remote_path }}"
        state: present
        disable_gpg_check: false
      when: ansible_facts['pkg_mgr'] in ['dnf', 'yum']

    - name: Install on DEB-based hosts
      ansible.builtin.apt:
        deb: "{{ csw_package_remote_path }}"
        state: present
      when: ansible_facts['pkg_mgr'] == 'apt'

    - name: Ensure tetd is running and enabled
      ansible.builtin.systemd:
        name: tetd
        state: started
        enabled: true
        daemon_reload: true

    - name: Cleanup
      ansible.builtin.file:
        path: "{{ csw_package_remote_path }}"
        state: absent
```

---

## Pattern C — Use an internal package repo (recommended for steady state)

Combine [`03-package-repo-satellite.md`](./03-package-repo-satellite.md)
with Ansible: push the repo definition once, then install via the
package manager.

### `playbook-install-from-repo.yml`

```yaml
---
- name: Install Cisco Secure Workload sensor (internal repo)
  hosts: csw_targets
  become: true
  gather_facts: true

  tasks:
    - name: Configure CSW repo (RHEL family)
      ansible.builtin.yum_repository:
        name: csw
        description: "Cisco Secure Workload Agents"
        baseurl: "https://repo.internal.example.com/csw/el{{ ansible_facts['distribution_major_version'] }}/x86_64"
        gpgcheck: true
        gpgkey: "https://repo.internal.example.com/keys/csw-signing-key.asc"
        sslverify: true
        enabled: true
      when: ansible_facts['os_family'] == 'RedHat'

    - name: Configure CSW repo signing key (Debian family)
      ansible.builtin.get_url:
        url: "https://repo.internal.example.com/keys/csw-signing-key.asc"
        dest: /etc/apt/keyrings/csw-signing-key.asc
        mode: '0644'
      when: ansible_facts['os_family'] == 'Debian'

    - name: Configure CSW APT source
      ansible.builtin.apt_repository:
        repo: "deb [signed-by=/etc/apt/keyrings/csw-signing-key.asc] https://repo.internal.example.com/csw {{ ansible_facts['distribution_release'] }} main"
        filename: csw
        state: present
        update_cache: true
      when: ansible_facts['os_family'] == 'Debian'

    - name: Place activation config (one file per scope or per host group)
      ansible.builtin.template:
        src: templates/sensor.conf.j2
        dest: /etc/tetration/sensor.conf
        owner: root
        group: root
        mode: '0640'

    - name: Install tet-sensor
      ansible.builtin.package:
        name: tet-sensor
        state: present

    - name: Ensure tetd running and enabled
      ansible.builtin.systemd:
        name: tetd
        state: started
        enabled: true
        daemon_reload: true
```

### `templates/sensor.conf.j2`

```jinja
# Managed by Ansible — do not edit by hand.
ACTIVATION_KEY={{ csw_activation_key }}
{% if csw_proxy_host is defined %}
HTTPS_PROXY_HOST={{ csw_proxy_host }}
HTTPS_PROXY_PORT={{ csw_proxy_port }}
{% endif %}
SCOPE={{ csw_scope }}
```

### `group_vars/prod_linux.yml`

```yaml
csw_activation_key: "{{ vault_csw_activation_key_prod }}"
csw_scope: "prod:web-tier"
```

Activation keys belong in **Ansible Vault**, not plain text:

```bash
ansible-vault encrypt group_vars/prod_linux/vault.yml
```

```yaml
# group_vars/prod_linux/vault.yml (encrypted)
vault_csw_activation_key_prod: "<key-from-CSW-UI>"
```

---

## Verification play (run after install)

```yaml
---
- name: Verify CSW sensor is installed and running
  hosts: csw_targets
  become: true
  gather_facts: false

  tasks:
    - name: Confirm tet-sensor is installed
      ansible.builtin.command: rpm -q tet-sensor
      register: pkg_query
      changed_when: false
      failed_when: pkg_query.rc != 0
      when: ansible_facts['os_family'] == 'RedHat'

    - name: Confirm tetd is active
      ansible.builtin.command: systemctl is-active tetd
      register: tetd_state
      changed_when: false
      failed_when: tetd_state.stdout.strip() != 'active'

    - name: Confirm sensor can reach cluster (port open)
      ansible.builtin.wait_for:
        host: "{{ csw_cluster_fqdn }}"
        port: 443
        timeout: 10
      vars:
        csw_cluster_fqdn: "csw.example.com"

    - name: Tail recent agent log
      ansible.builtin.command: tail -50 /var/log/tetration/tet-sensor.log
      register: log_tail
      changed_when: false

    - name: Show recent log
      ansible.builtin.debug:
        var: log_tail.stdout_lines
```

---

## Ansible Tower / AWX / Automation Platform

Wrap the playbooks above in a Tower/AWX **Job Template**:

- Project: a Git repo containing the playbooks
- Inventory: synced from your CMDB / dynamic source
- Credentials: machine credential for SSH + Ansible Vault password
  for the activation key
- Schedule: a one-time run for the initial wave; recurring
  schedules for upgrades (point at the internal repo and let
  `dnf update tet-sensor` pick up new versions)
- Surveys: prompt for `--limit` so operators target a subset

For multi-tenant or multi-cluster environments, parameterise
`csw_cluster_fqdn` and `csw_activation_key` per Tower/AWX
**Project / Inventory** combination so the job template applies
to one tenant at a time.

---

## Wave-based rollout pattern

Standard pattern for safe production rollout:

```bash
# Wave 0 — lab
ansible-playbook -i inventory/csw-targets.ini \
  --limit lab playbook-install-from-repo.yml

# Wave 1 — stage
ansible-playbook -i inventory/csw-targets.ini \
  --limit stage_linux playbook-install-from-repo.yml

# Wave 2 — prod, 5 hosts
ansible-playbook -i inventory/csw-targets.ini \
  --limit "prod_linux[0:5]" playbook-install-from-repo.yml

# Wave 3 — prod, batches of 25 % per day
ansible-playbook -i inventory/csw-targets.ini \
  --limit "prod_linux[5:54]" playbook-install-from-repo.yml
# ...etc
```

Combine with `--check` and `--diff` for dry runs:

```bash
ansible-playbook --check --diff -i inventory/csw-targets.ini \
  --limit prod_linux playbook-install-from-repo.yml
```

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Play hangs at "Run installer" | Script can't reach cluster (network / proxy) | Set `HTTPS_PROXY` in the play environment, or use Pattern B / C with proxy in `sensor.conf` |
| Repo install fails with "no package found" | Repo definition correct but metadata not refreshed on the host | Add `update_cache: true` (apt) or `dnf clean all` task before install |
| Sensor installs but not registered | Activation config / key issue | Check `/etc/tetration/sensor.conf`; verify the key in CSW UI; rerun with `--tags activate` |
| Some hosts succeed, some fail with kernel error | Mixed kernel versions in fleet | Add `pre_tasks` that confirm `kernel-headers` matches `uname -r`; or move outliers to UV |

---

## Why Ansible

- **Idempotent.** Re-runs are safe.
- **Wave-friendly.** `--limit` makes phased rollout natural.
- **Auditable.** Each Tower/AWX job is a logged event tied to an
  operator and a target list.
- **Composable.** Bolt onto existing playbooks; install CSW as
  one role in your standard host-config bundle.
- **Universal.** Same playbook covers RHEL, Ubuntu, SUSE, Amazon
  Linux variants, and (with the `winrm` connection plugin) can
  push the Windows MSI install too.

---

## See also

- [`./examples/ansible/`](./examples/ansible/) — runnable inventory + playbook + template files
- [`05-puppet.md`](./05-puppet.md), [`06-chef.md`](./06-chef.md), [`07-saltstack.md`](./07-saltstack.md) — alternative config-mgmt platforms
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md) — running upgrades through Ansible
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md)
