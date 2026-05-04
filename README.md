# Cisco Secure Workload — Agent Installation Guide

A practitioner-oriented reference for installing and operating the
Cisco Secure Workload (CSW) host agent — the component formerly
known as *Tetration sensor* — across Linux, Windows, cloud,
container, and agentless environments. Written for security
engineers, platform owners, and POV teams who need to get from
*"we bought CSW"* to *"every workload reports flow + process
telemetry into a working policy workspace"* without surprises.

> **Status.** Draft v1. Patterns and command shapes are
> documentation-grade and reflect typical operating practice. The
> authoritative source for any specific CSW release remains the
> *Cisco Secure Workload User Guide* and your release notes; always
> cross-check version-specific details there before relying on this
> repository in a customer engagement.

> **Official Cisco documentation — CSW 4.0:**
> [On-Premises 4.0 User Guide](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40.html)
> · [SaaS 4.0 User Guide](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-saas-v40.html).
> A consolidated cross-reference (with the canonical pre-install
> requirements, installer-script flag table, NPCAP / golden-image
> caveat, K8s service-mesh and CNI support notes, and the
> AnyConnect / ISE alternatives to a CSW agent) is in
> [`docs/00-official-references.md`](./docs/00-official-references.md)
> — read it before any new install attempt.

---

## What's in this repo

```
CSW-Agent-Installation-Guide/
├── README.md                  ← you are here (overview + decision matrix)
├── INDEX.md                   ← jump table by OS / by automation tool / by question
├── docs/                      ← background concepts (read first)
│   ├── 00-official-references.md    ← CSW 4.0 official docs cross-reference (read first!)
│   ├── 01-prerequisites.md          ← network, ports, certs, OS support, sizing
│   ├── 02-sensor-types.md           ← Deep Visibility, Enforcement, UV, NVM, HW, Cloud
│   ├── 03-decision-matrix.md        ← which method for which environment
│   ├── 04-rollout-strategy.md       ← Monitor → Simulate → Enforce
│   └── 05-anyconnect-ise-alternatives.md ← when no CSW agent is needed (NVM / ISE)
├── linux/                     ← all Linux installation methods
│   ├── README.md
│   ├── 01-manual-rpm-deb.md         ← interactive RPM/DEB on a single host
│   ├── 02-csw-generated-script.md   ← the most common enterprise method
│   ├── 03-package-repo-satellite.md ← internal Yum/APT repo, Satellite, Spacewalk
│   ├── 04-ansible.md                ← Ansible / Tower / AWX
│   ├── 05-puppet.md                 ← Puppet manifest
│   ├── 06-chef.md                   ← Chef recipe
│   ├── 07-saltstack.md              ← Salt state
│   ├── 08-verification.md           ← health checks, log locations, common gotchas
│   └── examples/                    ← runnable Ansible / Puppet / Chef / Salt files
├── windows/                   ← all Windows installation methods
│   ├── README.md
│   ├── 01-msi-silent-install.md     ← msiexec patterns
│   ├── 02-csw-generated-powershell.md ← prebaked PowerShell installer
│   ├── 03-sccm-deployment.md        ← Microsoft Configuration Manager
│   ├── 04-intune-deployment.md      ← Intune Win32 app
│   ├── 05-group-policy.md           ← GPO startup script fallback
│   ├── 06-verification.md
│   └── examples/                    ← Intune detection scripts, GPO templates
├── cloud/                     ← cloud-VM installation patterns
│   ├── README.md
│   ├── 01-aws-userdata.md           ← user_data + IMDSv2 + S3-sourced packages
│   ├── 02-azure-customdata.md       ← cloud-init / custom_data
│   ├── 03-gcp-startup-script.md     ← GCE startup metadata
│   ├── 04-terraform.md              ← Terraform examples for AWS / Azure / GCP
│   ├── 05-golden-ami.md             ← Packer pattern (AWS)
│   ├── 06-azure-vm-image.md         ← Azure Compute Gallery
│   └── examples/                    ← Terraform .tf, Packer .pkr.hcl, cloud-init
├── kubernetes/                ← container-orchestrated installations
│   ├── README.md
│   ├── 01-daemonset-helm.md         ← official CSW Helm chart pattern
│   ├── 02-daemonset-yaml.md         ← raw manifest for air-gapped / no-Helm shops
│   ├── 03-eks-aks-gke.md            ← managed-K8s service-specific notes
│   ├── 04-openshift.md              ← Security Context Constraints (SCC) notes
│   ├── 05-verification.md
│   └── examples/                    ← Helm values, raw DaemonSet manifest
├── agentless/                 ← cloud connectors (no host agent on the workload)
│   ├── README.md                    ← when (and when not) to use connectors
│   ├── 01-aws-cloud-connector.md
│   ├── 02-azure-cloud-connector.md
│   ├── 03-gcp-cloud-connector.md
│   ├── 04-vcenter-connector.md
│   └── 05-comparison-matrix.md      ← agent vs. connector trade-offs
└── operations/                ← lifecycle + day-2 operations
    ├── README.md
    ├── 01-network-prereq.md         ← exhaustive port / cert / NTP reference
    ├── 02-proxy.md                  ← forward / authenticating / decrypting proxy
    ├── 03-air-gapped.md             ← internet-restricted / air-gapped patterns
    ├── 04-upgrade.md
    ├── 05-uninstall.md              ← uninstall + decommission from CSW
    ├── 06-troubleshooting.md        ← symptom-first flowcharts
    ├── 07-enforcement-rollout.md    ← phased Monitor → Simulate → Enforce
    └── 08-evidence-audit.md         ← evidence buckets for compliance audit
```

---

## How to use this guide

0. **Read [`docs/00-official-references.md`](./docs/00-official-references.md) first.**
   It cross-references the CSW 4.0 On-Premises and SaaS User
   Guides and restates the authoritative items most often missed
   (1 GB storage, root / Administrator privilege, `tet-sensor`
   user under SELinux, the Linux installer flag set, the Windows
   NPCAP golden-image trap, K8s images-pulled-from-cluster
   behaviour, Istio + Calico support, and the AnyConnect / ISE
   no-agent paths).
1. **Read [`docs/01-prerequisites.md`](./docs/01-prerequisites.md) next.**
   Almost every failed CSW agent install traces back to one of:
   a closed firewall port, a TLS trust gap, an unsupported OS /
   kernel, or a clock skew. The prerequisites doc is short on
   purpose — these are the gates.
2. **Pick a sensor type from [`docs/02-sensor-types.md`](./docs/02-sensor-types.md).**
   *Deep Visibility* and *Enforcement* are the two flavours 90 %
   of customer fleets run; the other four (Universal Visibility,
   AnyConnect NVM, NetFlow / ERSPAN ingestion, Cloud Sensor) have
   specific niches that the doc walks through.
3. **Pick an installation method from [`docs/03-decision-matrix.md`](./docs/03-decision-matrix.md).**
   The matrix maps environment shape (one host vs. fleet, on-prem
   vs. cloud, with vs. without an automation pipeline) to the
   recommended method.
4. **Follow the per-method runbook** under
   [`linux/`](./linux/README.md),
   [`windows/`](./windows/README.md),
   [`cloud/`](./cloud/README.md),
   [`kubernetes/`](./kubernetes/README.md), or
   [`agentless/`](./agentless/README.md). Each runbook is
   self-contained: prerequisites, install steps, verification,
   common errors.
5. **For first-time POV deployments, read
   [`operations/07-enforcement-rollout.md`](./operations/07-enforcement-rollout.md).**
   Going straight to Enforce on day one is the single most common
   cause of "CSW broke production" stories. The phased rollout
   pattern avoids it.

---

## Sensor types at a glance

| Sensor type | What it does | Where it runs | Typical use |
|---|---|---|---|
| **Deep Visibility** | Flow + process telemetry, software inventory, vulnerability lookup | Linux + Windows hosts | Default for every CSW workload that supports it |
| **Enforcement** | Deep Visibility + workload-side firewall enforcement | Linux + Windows hosts | Workloads that need policy enforced at the host |
| **Universal Visibility (UV)** | Lighter-weight flow telemetry, no enforcement | Older OS, ARM, embedded, niche kernels | When the Deep agent isn't supported on the platform |
| **AnyConnect NVM** | Endpoint flow telemetry from user devices | Laptops / desktops via Cisco Secure Client | User-endpoint visibility (BYOD-style) |
| **NetFlow / ERSPAN ingestion** | Flow records exported by the network device (NetFlow v9 / IPFIX / ERSPAN / NSEL) | Connector on a Secure Workload Ingest Appliance — **no agent on the workload** | When agents are not allowed (network appliances, storage / SAN controllers, OT gateways). See the [Connectors chapter on docs.cisco.com](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html). |
| **Cloud Sensor / Cloud Connector** | Agentless inventory + flow logs via cloud APIs | CSW pulls from AWS / Azure / GCP / vCenter | Cloud accounts with broad workload coverage requirements; DR or sandbox accounts where agents aren't deployed |

Detail in [`docs/02-sensor-types.md`](./docs/02-sensor-types.md).

---

## Installation method decision matrix (high level)

| Environment | Recommended primary method | When to use |
|---|---|---|
| One Linux host, one-off | Manual RPM/DEB | First lab install, troubleshooting |
| Many Linux hosts, no automation tool | CSW-generated shell script | Lab sweeps, small fleets |
| Linux fleet under Ansible | Ansible playbook | Standard enterprise pattern |
| Linux fleet under Puppet / Chef / Salt | Native module / cookbook / state | When that's already your config-mgmt platform |
| Air-gapped Linux | Internal Yum/APT repo (Satellite / Spacewalk / Pulp) | Regulated environments without internet |
| One Windows host | Manual MSI silent install | Lab installs |
| Many Windows hosts under SCCM | SCCM application + required deployment + compliance baseline | Standard enterprise pattern for Windows |
| Windows under Intune | Win32 app + detection script | Cloud-managed Windows fleet |
| Windows without SCCM / Intune | GPO startup script | Domain-joined fallback when neither tool is available |
| Cloud VMs (AWS / Azure / GCP) | Embed in `user_data` / `custom_data` / startup script | New launches; works with any IaC tool |
| Cloud VMs at scale | Golden AMI / Compute Gallery image | Bake the agent into the base image; zero-touch on new launches |
| Kubernetes / OpenShift nodes | DaemonSet via Helm chart | Standard pattern for K8s clusters |
| Air-gapped K8s | Raw DaemonSet manifest with internal registry | When Helm or external chart pulls aren't permitted |
| Cloud accounts with broad workload coverage and minimal agent footprint | Cloud Connector (agentless) | Inventory + flow-log scope where deploying agents is impractical |
| Workloads where agents are not allowed | NetFlow / ERSPAN ingestion via the appropriate Secure Workload connector + Cloud Connector | Network appliances, storage / SAN controllers, OT systems — use the device's native NetFlow / IPFIX / NSEL export where available; fall back to ERSPAN when only port-mirroring is supported |

Full decision tree with phased-rollout commentary in
[`docs/03-decision-matrix.md`](./docs/03-decision-matrix.md).

---

## Companion repositories

This repo is the **deployment** half of the CSW practitioner
toolkit. The other two repositories hold the framework-mapping and
tenant-insight halves:

- [`chandrapati/CSW-Compliance-Mapping`](https://github.com/chandrapati/CSW-Compliance-Mapping)
  — sixteen compliance, sector, and zero-trust frameworks mapped
  to CSW capability with runbooks and customer reports. Use it
  when a customer asks "how do I evidence Control X?"
- [`chandrapati/CSW-Tenant-Insights`](https://github.com/chandrapati/CSW-Tenant-Insights)
  *(private)* — CISO and POV report generators that take a live
  CSW evidence bundle and produce executive narrative. Use it
  during a POV to demonstrate value beyond the green-yellow-red
  posture dashboard.

---

## Disclaimer

The patterns, command examples, sample playbooks, and operational
guidance in this repository are provided for **informational and
reference purposes only**. They are not a substitute for the
official Cisco Secure Workload product documentation, your
organisation's change-management process, or qualified consulting
engagement.

> **Official Cisco Secure Workload documentation.** The full set
> of canonical pointers — User Guides (4.0
> [On-Premises](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40.html)
> and [SaaS](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-saas-v40.html)),
> [Compatibility Matrix](https://www.cisco.com/c/m/en_us/products/security/secure-workload-compatibility-matrix.html),
> Connectors chapter, per-OS install pages, release notes — is
> consolidated in
> [`docs/00-official-references.md`](./docs/00-official-references.md).
> The
> [CSW 4.0 documentation landing page](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/landing-page/secureworkload-40-docs.html)
> is the navigation root if you need to drill into a section that
> isn't called out in this repo. **When this guide and the User
> Guide disagree, the User Guide wins.**

Specifically:

- Cisco Secure Workload package names, default install paths,
  systemd unit names (`tetd`), Windows service names, and registry
  paths reflect typical practice at the time of authoring. The
  authoritative source for any specific CSW release is the
  [*Cisco Secure Workload User Guide*](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40.html)
  and the release notes shipped with your CSW cluster (or with
  the SaaS portal). Cross-check before deploying.
- This guide is **release-version-agnostic** in its structure but
  may include commands that change between major versions. Look
  for version-specific notes inline; when in doubt, refer to the
  installer screen text shown in your CSW *Manage → Agents* UI,
  which is always generated for your specific cluster version.
- Sample automation (Ansible, Puppet, Chef, Salt, Terraform,
  Packer, Helm) is illustrative; tailor variable names, secret
  references, and inventory shape to your existing pipelines
  before running in production.
- Production deployments should always start in **Monitoring**
  mode and progress to Enforcement only after the simulation
  workflow ([`operations/07-enforcement-rollout.md`](./operations/07-enforcement-rollout.md))
  has retired the obvious would-be-blocked flows. Going straight
  to Enforce on day one is the single most common cause of
  preventable outages during CSW rollouts.

### Questions, sizing, licensing, or anything else?

For questions about your specific deployment — release-version
specifics, customer-environment trade-offs, sizing, licensing,
Compatibility-Matrix edge cases, or anything that requires
cluster-side workflow review — **reach out to your Cisco Secure
Workload account team** (your assigned Cisco SE or partner SE).
If you don't yet have an account team, the
[Cisco Secure Workload product home page](https://www.cisco.com/c/en/us/products/security/secure-workload/index.html)
has the *Contact Cisco* / *Get a demo* / *Find a partner* paths,
or use [Cisco's general contact page](https://www.cisco.com/c/en/us/about/contact-cisco.html).
For incidents on a deployed cluster,
[open a Cisco TAC case](https://www.cisco.com/c/en/us/support/index.html).

This document should receive subject-matter-expert review before
being used to gate any production change.
