# Linux — Internal Package Repo (Satellite / Spacewalk / Pulp / Foreman / Aptly)

For air-gapped environments, regulated environments, and any
fleet that already manages OS packages through a centralised
internal repository, **publish the CSW agent package to that repo
and let your existing patching pipeline install it** like any
other package. This is the cleanest method for change-controlled
fleets because the install becomes "just another OS update".

> This doc covers the **packaging side** — how to put the CSW
> agent in your internal repo and configure clients to find it.
> The **first-time activation** (the cluster-side handshake with
> the activation key) still happens once per host. Two patterns
> for activation are covered at the end of this doc.

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- An internal Yum/DNF repository (Satellite, Spacewalk, Foreman,
  Pulp, Katello, or a plain HTTP-served `createrepo`-managed
  directory) **or** an internal APT repository (Aptly, reprepro,
  Pulp-Deb, Artifactory APT, Nexus APT)
- The CSW agent `.rpm` / `.deb` packages downloaded from the CSW
  *Manage → Agents → Install Agent* UI for each (OS family, sensor
  type) combination you support
- Admin rights on the internal repo

---

## Step 1 — Download the agent packages

For each supported (OS family, sensor type) combination, download
the package from the CSW UI. A typical organisation needs:

| Combination | File pattern |
|---|---|
| RHEL 7 family, Deep Visibility | `tet-sensor-3.x.y.z-1.el7.x86_64.rpm` |
| RHEL 8/9 family, Deep Visibility | `tet-sensor-3.x.y.z-1.el9.x86_64.rpm` |
| Ubuntu 20.04, Deep Visibility | `tet-sensor-3.x.y.z-1.ubuntu20_amd64.deb` |
| Ubuntu 22.04, Deep Visibility | `tet-sensor-3.x.y.z-1.ubuntu22_amd64.deb` |
| SLES 15, Deep Visibility | `tet-sensor-3.x.y.z-1.sle15.x86_64.rpm` |
| (same again with `tet-sensor-enforcer-...` for Enforcement) | |

Capture the GPG signing key from the CSW UI (the install screen
documents the key fingerprint and where to download it). You'll
need to import the key into your repo and into client trust
stores.

---

## Step 2A — Publish to a Yum/DNF repo

### 2A.1 — On the repo server

```bash
# Choose a repo path (Satellite / Foreman use their own UI; for
# a plain HTTP repo, this is the directory layout)
sudo mkdir -p /var/www/html/internal-repos/csw/el9/x86_64

# Drop the RPMs in
sudo cp tet-sensor-3.x.y.z-1.el9.x86_64.rpm \
        tet-sensor-enforcer-3.x.y.z-1.el9.x86_64.rpm \
        /var/www/html/internal-repos/csw/el9/x86_64/

# Generate metadata
sudo createrepo --update /var/www/html/internal-repos/csw/el9/x86_64

# Sign the metadata if your org policy requires
# (substitute your own GPG key reference; see below for key handling)
sudo gpg --detach-sign --armor \
   --local-user 'CSW Internal Repo Key' \
   /var/www/html/internal-repos/csw/el9/x86_64/repodata/repomd.xml
```

For Satellite or Foreman/Katello, follow the product's normal
"sync external repo" or "import package" workflow instead of the
`createrepo` commands above.

### 2A.2 — On each client workload

Drop a repo file:

```ini
# /etc/yum.repos.d/csw.repo
[csw]
name=Cisco Secure Workload Agents
baseurl=https://repo.internal.example.com/internal-repos/csw/el9/x86_64
enabled=1
gpgcheck=1
gpgkey=https://repo.internal.example.com/keys/csw-signing-key.asc
sslverify=1
```

Refresh metadata and install:

```bash
sudo dnf clean all
sudo dnf install -y tet-sensor
```

### 2A.3 — Push the repo file via your config-management tool

Don't drop the `csw.repo` file by hand on every host. Use your
existing channel:

- Ansible: `ansible.builtin.copy` or `ansible.builtin.template`
- Puppet: `yumrepo` resource
- Chef: `yum_repository` resource
- Salt: `pkgrepo.managed`

The agent install itself follows in the same playbook /
manifest / recipe / state.

---

## Step 2B — Publish to an APT repo

### 2B.1 — On the repo server (Aptly example)

```bash
# Create the repo (one-time setup)
aptly repo create -distribution=focal -component=main csw-ubuntu20

# Add the .deb file
aptly repo add csw-ubuntu20 \
  ./tet-sensor-3.x.y.z-1.ubuntu20_amd64.deb \
  ./tet-sensor-enforcer-3.x.y.z-1.ubuntu20_amd64.deb

# Publish (signed)
aptly publish repo -gpg-key='CSW Internal Repo Key' csw-ubuntu20 csw

# Update after adding new packages
# aptly repo add csw-ubuntu20 ./tet-sensor-...new-version.deb
# aptly publish update focal csw
```

For Pulp-Deb / reprepro / Artifactory / Nexus APT, follow the
product's documentation; the result is the same — a signed APT
repo URL with `dists/<release>/main/binary-amd64/` containing the
`tet-sensor` packages.

### 2B.2 — On each client workload

Drop an APT source list:

```ini
# /etc/apt/sources.list.d/csw.list
deb [signed-by=/etc/apt/keyrings/csw-signing-key.gpg] \
    https://repo.internal.example.com/csw focal main
```

And the signing key:

```bash
# /etc/apt/keyrings/csw-signing-key.gpg
sudo curl -fsSL https://repo.internal.example.com/keys/csw-signing-key.asc | \
  sudo gpg --dearmor -o /etc/apt/keyrings/csw-signing-key.gpg
sudo chmod 644 /etc/apt/keyrings/csw-signing-key.gpg
```

Install:

```bash
sudo apt update
sudo apt install -y tet-sensor
```

### 2B.3 — Push the source list via your config-management tool

Same pattern as Yum:

- Ansible: `ansible.builtin.apt_repository`
- Puppet: `apt::source` (puppetlabs/apt module)
- Chef: `apt_repository` resource
- Salt: `pkgrepo.managed`

---

## Step 3 — Activation (post-install)

Installing the package puts the binaries in place and (depending
on your CSW release) starts `tetd`, but the agent doesn't yet
know which cluster to register with. There are two patterns for
handling this:

### Pattern A — Drop a config file before the package install

Place `/etc/tetration/sensor.conf` (or the release-equivalent)
**before** the package install with cluster URL, activation key,
and CA chain. The package install picks it up. Suitable for
config-managed environments.

```bash
# Example /etc/tetration/sensor.conf
ACTIVATION_KEY=<key-from-CSW-UI>
HTTPS_PROXY_HOST=<proxy.host>
HTTPS_PROXY_PORT=<port>
SCOPE=<scope-name>
```

```bash
# Place before install
sudo install -m 0640 sensor.conf /etc/tetration/sensor.conf
sudo install -m 0644 ca.pem /etc/tetration/ca.pem

# Then install
sudo dnf install -y tet-sensor
```

The activation key value comes from the CSW *Manage → Agents*
UI — generate it once for the scope and treat it as a secret.

### Pattern B — Use the CSW-generated installer instead

If Pattern A is awkward (e.g., the per-scope key fan-out is too
big), use the CSW-generated shell script
([02](./02-csw-generated-script.md)) for activation, and use the
internal repo just for **upgrades** (where the activation has
already happened on first install).

---

## Step 4 — Day-2 patching pipeline

Once the package is in your internal repo and the CA / activation
config is in place, the agent participates in your normal OS
patching pipeline:

```bash
# Routine patching cycle on each host
sudo dnf update -y                  # picks up new tet-sensor when published
# or
sudo apt update && sudo apt upgrade -y
```

**Recommendation.** Pin the agent version in non-prod first,
let your standard validation cycle run for 1–2 weeks, then
promote to prod. The agent is reasonably backward-compatible but
each release has its own kernel-compat matrix.

For a stricter promotion model, publish to two repo branches
(e.g., `csw-staging` and `csw-prod`); promote between them after
validation.

---

## Step 5 — GPG key handling

Treat the CSW-published signing key like any other vendor key:

- Pull the key from the CSW UI (Install Agent screen) on
  download
- Validate the fingerprint against the value documented in your
  release's install guide
- Import into your internal repo's signing chain (or republish
  signed by your internal key — a common Satellite pattern)
- Ship the public key to clients via your config-management tool
  (`/etc/pki/rpm-gpg/`, `/etc/apt/keyrings/`)
- Rotate when CSW releases a new key (rare; documented in
  release notes)

---

## When this is the right method

- **Air-gapped environments.** No outbound from workloads to
  cisco.com or to a customer-portal URL.
- **Regulated change-controlled environments** where every
  package install needs a CR ticket and an audit trail. The repo
  + patching pipeline already satisfies this.
- **Linux-heavy fleets where Satellite / Spacewalk / Pulp is the
  authoritative package source.** Adding the CSW agent there is
  organisationally cheap once the workflow is set up.

## When this is NOT the right method

- **Greenfield environments without an internal repo yet.** Stand
  up Ansible first; cross to the internal-repo pattern when the
  patching team adopts one.
- **Cloud-only fleets.** Cloud workloads usually pull from
  cloud-provider repo mirrors; a separate Pulp / Aptly server is
  often unnecessary overhead.

---

## See also

- [`01-manual-rpm-deb.md`](./01-manual-rpm-deb.md) — what the agent does once installed
- [`02-csw-generated-script.md`](./02-csw-generated-script.md) — alternative activation path
- [`04-ansible.md`](./04-ansible.md) — push the repo file + install in one play
- [`../operations/03-air-gapped.md`](../operations/03-air-gapped.md) — broader air-gap guidance
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md) — running upgrades through this pipeline
