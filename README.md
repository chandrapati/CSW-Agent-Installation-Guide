# Cisco Secure Workload — Agent Installation Guide

![Visitors](https://visitor-badge.laobi.icu/badge?page_id=chandrapati.CSW-Agent-Installation-Guide&left_text=visitors)

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
> requirements, installer-script flag table, the Windows VDI /
> golden-image flow, K8s image-pulled-from-cluster behaviour, the
> Istio sidecar port list and the tested Calico configuration,
> and the AnyConnect / ISE alternatives to a CSW agent) is in
> [`docs/00-official-references.md`](./docs/00-official-references.md)
> — read it before any new install attempt.

> **Scope of this audit (May 2026).** Every factual claim about
> agent types, service / process names, file paths, install
> flags, ports, K8s install method, and Windows VDI behaviour in
> this repository has been cross-referenced against the
> [Deploy Software Agents on Workloads](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
> chapter of the **CSW 4.0 On-Premises User Guide**. Where Cisco
> documents something specifically, this repo cites the
> documented value. Where Cisco doesn't document a particular
> detail (typical example: the exact MSI ProductCode, the chart
> name of an internally-maintained Helm chart, or your release's
> exact installer-script filename), the repo says so explicitly
> and points back to the User Guide / your cluster's
> *Manage → Workloads → Agents → Installer* screen as the
> authoritative source for your specific release.

---

## For executives — at a glance

> **CISO / CIO read.** Agent installation is the *foundation* step:
> nothing downstream — visibility, segmentation, or compliance evidence —
> works until workloads are reporting. The business case lives in
> [CSW-User-Education](https://github.com/chandrapati/CSW-User-Education)
> and [CSW-Compliance-Mapping](https://github.com/chandrapati/CSW-Compliance-Mapping);
> what to do *after* agents report is in
> [CSW-Policy-Lifecycle](https://github.com/chandrapati/CSW-Policy-Lifecycle).

- **What gets installed.** A lightweight host **agent** on each
  server / VM / container that observes processes and network flows;
  **agentless cloud connectors** cover AWS / Azure / GCP where an agent
  isn't deployed.
- **Does it risk my apps?** No. The agent installs in **visibility**
  (observe-only) — it reports telemetry and does **not** block traffic.
  Enforcement is a deliberate, later decision turned on per workload via
  policy, not by the install itself.
- **Coverage is the metric.** The goal of this phase is simple and
  measurable: **every in-scope workload reporting**, reconciled against
  your CMDB / cloud inventory. Gaps here become blind spots in every
  audit and incident later.
- **Scale path.** Manual install to validate, then automate at fleet
  scale (Ansible / Puppet / Chef / SaltStack, cloud user-data / golden
  images, K8s DaemonSet). See the decision matrix below.
- **Status / trust.** Draft v1, cross-referenced to the **CSW 4.0**
  User Guide (May 2026 audit). The User Guide is authoritative for your
  specific release.

---

## What's in this repo

- [`README.md`](./README.md) — you are here (overview + decision matrix)
- [`INDEX.md`](./INDEX.md) — jump table by OS / by automation tool / by question
- [`docs/`](./docs/) — background concepts (read first)
  - [`00-official-references.md`](./docs/00-official-references.md) — CSW 4.0 official docs cross-reference (read first!)
  - [`01-prerequisites.md`](./docs/01-prerequisites.md) — network, ports, certs, OS support, sizing
  - [`02-sensor-types.md`](./docs/02-sensor-types.md) — Deep Visibility, Enforcement, UV, NVM, HW, Cloud
  - [`03-decision-matrix.md`](./docs/03-decision-matrix.md) — which method for which environment
  - [`04-rollout-strategy.md`](./docs/04-rollout-strategy.md) — Monitor → Simulate → Enforce
  - [`05-anyconnect-ise-alternatives.md`](./docs/05-anyconnect-ise-alternatives.md) — when no CSW agent is needed (NVM / ISE)
- [`linux/`](./linux/) — all Linux installation methods
  - [`README.md`](./linux/README.md)
  - [`01-manual-rpm-deb.md`](./linux/01-manual-rpm-deb.md) — interactive RPM/DEB on a single host
  - [`02-csw-generated-script.md`](./linux/02-csw-generated-script.md) — the most common enterprise method
  - [`03-package-repo-satellite.md`](./linux/03-package-repo-satellite.md) — internal Yum/APT repo, Satellite, Spacewalk
  - [`04-ansible.md`](./linux/04-ansible.md) — Ansible / Tower / AWX
  - [`05-puppet.md`](./linux/05-puppet.md) — Puppet manifest
  - [`06-chef.md`](./linux/06-chef.md) — Chef recipe
  - [`07-saltstack.md`](./linux/07-saltstack.md) — Salt state
  - [`08-verification.md`](./linux/08-verification.md) — health checks, log locations, common gotchas
  - [`examples/`](./linux/examples/) — runnable Ansible / Puppet / Chef / Salt files
- [`windows/`](./windows/) — all Windows installation methods
  - [`README.md`](./windows/README.md)
  - [`01-msi-silent-install.md`](./windows/01-msi-silent-install.md) — msiexec patterns
  - [`02-csw-generated-powershell.md`](./windows/02-csw-generated-powershell.md) — prebaked PowerShell installer
  - [`03-sccm-deployment.md`](./windows/03-sccm-deployment.md) — Microsoft Configuration Manager
  - [`04-intune-deployment.md`](./windows/04-intune-deployment.md) — Intune Win32 app
  - [`05-group-policy.md`](./windows/05-group-policy.md) — GPO startup script fallback
  - [`06-verification.md`](./windows/06-verification.md)
  - [`examples/`](./windows/examples/) — Intune detection scripts, GPO templates
- [`tanium/`](./tanium/) — Tanium Deploy / Provision (Linux + Windows)
  - [`README.md`](./tanium/README.md) — package layout, **`user.cfg` pre-staging**, rollout
  - [`TANIUM-DEPLOYMENT-CHECKLIST.pdf`](./tanium/TANIUM-DEPLOYMENT-CHECKLIST.pdf) — one-page field checklist (PDF/DOCX)
  - [`examples/`](./tanium/examples/) — staging scripts + install wrappers
- [`cloud/`](./cloud/) — cloud-VM installation patterns
  - [`README.md`](./cloud/README.md)
  - [`01-aws-userdata.md`](./cloud/01-aws-userdata.md) — user_data + IMDSv2 + S3-sourced packages
  - [`02-azure-customdata.md`](./cloud/02-azure-customdata.md) — cloud-init / custom_data
  - [`03-gcp-startup-script.md`](./cloud/03-gcp-startup-script.md) — GCE startup metadata
  - [`04-terraform.md`](./cloud/04-terraform.md) — Terraform examples for AWS / Azure / GCP
  - [`05-golden-ami.md`](./cloud/05-golden-ami.md) — Packer pattern (AWS)
  - [`06-azure-vm-image.md`](./cloud/06-azure-vm-image.md) — Azure Compute Gallery
  - [`examples/`](./cloud/examples/) — Terraform .tf, Packer .pkr.hcl, cloud-init
- [`kubernetes/`](./kubernetes/) — container-orchestrated installations
  - [`README.md`](./kubernetes/README.md)
  - [`01-daemonset-helm.md`](./kubernetes/01-daemonset-helm.md) — official CSW Helm chart pattern
  - [`02-daemonset-yaml.md`](./kubernetes/02-daemonset-yaml.md) — raw manifest for air-gapped / no-Helm shops
  - [`03-eks-aks-gke.md`](./kubernetes/03-eks-aks-gke.md) — managed-K8s service-specific notes
  - [`04-openshift.md`](./kubernetes/04-openshift.md) — Security Context Constraints (SCC) notes
  - [`05-verification.md`](./kubernetes/05-verification.md)
  - `examples/` — Helm values, raw DaemonSet manifest
- [`agentless/`](./agentless/) — cloud connectors (no host agent on the workload)
  - [`README.md`](./agentless/README.md) — when (and when not) to use connectors
  - [`01-aws-cloud-connector.md`](./agentless/01-aws-cloud-connector.md)
  - [`02-azure-cloud-connector.md`](./agentless/02-azure-cloud-connector.md)
  - [`03-gcp-cloud-connector.md`](./agentless/03-gcp-cloud-connector.md)
  - [`04-vcenter-connector.md`](./agentless/04-vcenter-connector.md)
  - [`05-comparison-matrix.md`](./agentless/05-comparison-matrix.md) — agent vs. connector trade-offs
- [`operations/`](./operations/) — lifecycle + day-2 operations
  - [`README.md`](./operations/README.md)
  - [`01-network-prereq.md`](./operations/01-network-prereq.md) — exhaustive port / cert / NTP reference
  - [`02-proxy.md`](./operations/02-proxy.md) — forward / authenticating / decrypting proxy
  - [`03-air-gapped.md`](./operations/03-air-gapped.md) — internet-restricted / air-gapped patterns
  - [`04-upgrade.md`](./operations/04-upgrade.md)
  - [`05-uninstall.md`](./operations/05-uninstall.md) — uninstall + decommission from CSW
  - [`06-troubleshooting.md`](./operations/06-troubleshooting.md) — symptom-first flowcharts
  - [`07-enforcement-rollout.md`](./operations/07-enforcement-rollout.md) — phased Monitor → Simulate → Enforce
  - [`08-evidence-audit.md`](./operations/08-evidence-audit.md) — evidence buckets for compliance audit

---

## How to use this guide

0. **Read [`docs/00-official-references.md`](./docs/00-official-references.md) first.**
   It cross-references the CSW 4.0 On-Premises and SaaS User
   Guides and restates the authoritative items most often missed
   (1 GB storage, root / Administrator privilege, `tet-sensor`
   user under SELinux, the Linux installer flag set, the
   documented Windows VDI / golden-image flow (`-goldenImage`
   PowerShell flag and `nostart=yes` MSI option), K8s
   images-pulled-from-cluster behaviour, the Istio sidecar port
   list, the tested Calico 3.13 Felix configuration, and the
   AnyConnect / ISE no-agent paths).
1. **Read [`docs/01-prerequisites.md`](./docs/01-prerequisites.md) next.**
   Almost every failed CSW agent install traces back to one of:
   a closed firewall port, a TLS trust gap, an unsupported OS /
   kernel, or a clock skew. The prerequisites doc is short on
   purpose — these are the gates.
2. **Pick a sensor type from [`docs/02-sensor-types.md`](./docs/02-sensor-types.md).**
   *Deep Visibility* and *Enforcement* are the two flavours 90 %
   of customer fleets run; AIX, Solaris, and Kubernetes /
   OpenShift agents are the additional documented platforms in
   CSW 4.0. The agentless paths — AnyConnect / ISE / cloud
   connectors and NetFlow / ERSPAN ingestion — cover the cases
   where a host agent is not feasible.
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

Per Cisco's
[Deploy Software Agents on Workloads](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
chapter, CSW 4.0 ships agents for **Linux, Windows, AIX, Solaris,
and Kubernetes / OpenShift**. Agent **type** within those
platforms is one of `Visibility` (deep visibility only),
`Enforcement` (deep visibility + host-firewall enforcement), or
the Kubernetes / OpenShift agent (DaemonSet form factor). The
"Other Agent-Like Tools" section of the Cisco chapter lists
**AnyConnect**, **ISE**, and **SPAN** as connector-fed paths that
do not require a CSW host agent on the workload.

| Sensor / mechanism | What it does | Where it runs | Typical use |
|---|---|---|---|
| **Deep Visibility agent** | Flow + process telemetry, software inventory, CVE lookup | Linux, Windows, AIX, Solaris hosts | Default for every CSW workload that supports it |
| **Enforcement agent** | Deep Visibility + workload-side firewall enforcement (Linux iptables / nftables, Windows WAF or WFP, AIX IPFilter, Solaris IPFilter) | Linux, Windows, AIX, Solaris hosts | Workloads that need policy enforced at the host |
| **Kubernetes / OpenShift agent** | Node-level DaemonSet capturing flows for the node and its pods, with K8s metadata enrichment | EKS, AKS, GKE, OpenShift, plain K8s nodes (Linux + Windows worker nodes) | The K8s / OpenShift platform itself |
| **AnyConnect (connector)** | Flow observations + inventory + labels from Cisco Secure Client (formerly AnyConnect) endpoints with NVM enabled | Endpoints; **no CSW agent on the endpoint** | Corporate laptops / desktops where Secure Client is already deployed |
| **ISE (connector via pxGrid)** | Endpoint metadata from Cisco ISE | Endpoints; **no CSW agent on the endpoint** | Mixed-device estates (printers, IoT, BYOD) where ISE is the source of identity truth |
| **SPAN agents (ERSPAN connector)** | Flow records derived from a port-mirror tunnelled via GRE | Connector on a Secure Workload Ingest Appliance; **no agent on the workload** | When the source device can mirror traffic but cannot export NetFlow / IPFIX |
| **NetFlow / IPFIX / NSEL (connectors)** | Flow records exported natively by the network device | Connector on a Secure Workload Ingest Appliance; **no agent on the workload** | Network appliances, ASA / FTD, F5, NetScaler, Meraki MX, etc. |
| **Cloud Connector** | Inventory + cloud-platform flow logs (VPC Flow Logs / NSG Flow Logs / GCP VPC Flow Logs) and vCenter inventory | CSW-side connector polling the cloud / vCenter control plane; **no agent on the workload** | Cloud accounts where the agent footprint is intentionally minimised; sandbox / DR / partner accounts |

> **What about "Universal Visibility"?** "Universal Visibility"
> (UV) was an agent type in earlier Tetration releases. It does
> **not** appear as an agent type in Cisco's CSW 4.0
> [Deploy Software Agents on Workloads](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
> chapter. If you are running an older release where UV is still
> documented, follow that release's User Guide; this repository
> reflects 4.0 unless explicitly noted.

Detail in [`docs/02-sensor-types.md`](./docs/02-sensor-types.md).

---

## Installation method decision matrix (high level)

| Environment | Recommended primary method | When to use |
|---|---|---|
| One Linux host, one-off | Manual RPM/DEB | First lab install, troubleshooting |
| Many Linux hosts, no automation tool | CSW-generated shell script | Lab sweeps, small fleets |
| Linux or Windows fleet under Tanium | Tanium Deploy + pre-staged `user.cfg` | [`tanium/README.md`](./tanium/README.md) |
| Linux fleet under Ansible | Ansible playbook | Standard enterprise pattern |
| Linux fleet under Puppet / Chef / Salt | Native module / cookbook / state | When that's already your config-mgmt platform |
| Air-gapped Linux | Internal Yum/APT repo (Satellite / Spacewalk / Pulp) | Regulated environments without internet |
| One Windows host | Manual MSI silent install | Lab installs |
| Many Windows hosts under SCCM | SCCM application + required deployment + compliance baseline | Standard enterprise pattern for Windows |
| Windows under Intune | Win32 app + detection script | Cloud-managed Windows fleet |
| Windows without SCCM / Intune | GPO startup script | Domain-joined fallback when neither tool is available |
| Cloud VMs (AWS / Azure / GCP) | Embed in `user_data` / `custom_data` / startup script | New launches; works with any IaC tool |
| Cloud VMs at scale | Golden AMI / Compute Gallery image | Bake the agent into the base image; zero-touch on new launches |
| Kubernetes / OpenShift nodes | **Cisco-documented method:** Agent Script Installer from *Manage → Workloads → Agents → Installer* — the script provisions namespace, RBAC, and the DaemonSet, and each node pulls the agent image from the CSW cluster | Standard pattern for K8s / OpenShift clusters per the CSW 4.0 User Guide |
| Air-gapped K8s | Mirror the agent image to your internal registry; either run the agent script installer pointing at the mirror, or maintain your own raw DaemonSet manifest | When the cluster nodes can't pull from the CSW cluster directly |
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
  service names, and registry paths follow what Cisco documents
  for **CSW 4.0**: the Linux systemd unit is **`csw-agent`**, the
  Windows service is **`CswAgent`** (display name *Cisco Secure
  Workload Deep Visibility*), and the Cisco-documented install
  paths are `/usr/local/tet` (default RPM), `/opt/cisco/tetration`
  (Ubuntu .deb and AIX), `/var/opt/cisco/secure-workload`,
  `C:\Program Files\Cisco Tetration` (Windows), and
  `/opt/cisco/secure-workload` (Solaris). Earlier Tetration
  releases used different service names — confirm against the
  release notes shipped with your specific CSW cluster (or with
  the SaaS portal) before deploying.
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

---

## CSW Integration Guides & Resources

| Repository | Description | Best for |
|------------|-------------|---------|
| [User Education](https://github.com/chandrapati/CSW-User-Education) | Onboarding guides and concept explainers | New CSW users |
| [Agent Installation](https://github.com/chandrapati/CSW-Agent-Installation-Guide) | Deploy CSW agents on Linux / Windows / cloud | Day-1 sensor deployment |
| [Policy Lifecycle](https://github.com/chandrapati/CSW-Policy-Lifecycle) | Policy discovery → enforcement workflow | Policy management |
| [ISE / pxGrid](https://github.com/chandrapati/csw-ise-integration) | ISE/pxGrid: user-identity–aware microsegmentation | Identity & Zero Trust |
| [AnyConnect NVM](https://github.com/chandrapati/csw-anyconnect-nvm) | Endpoint process flows + user identity via NVM | Endpoint telemetry |
| [ServiceNow CMDB](https://github.com/chandrapati/csw-servicenow-integration) | ServiceNow CMDB label enrichment for workload scopes | CMDB-driven policy |
| [Infoblox](https://github.com/chandrapati/csw-infoblox-integration) | Infoblox IPAM/DNS extensible-attribute label enrichment | IPAM/DNS-driven policy |
| [F5 BIG-IP](https://github.com/chandrapati/csw-f5-integration) | F5 virtual-server labels, policy enforcement, IPFIX flow visibility | Load balancer segmentation |
| [AWS Connector](https://github.com/chandrapati/csw-aws-connector) | EC2 tag ingestion + VPC flow logs + Security Group enforcement | AWS workloads |
| [Azure Connector](https://github.com/chandrapati/csw-azure-connector) | Azure VM tag ingestion + VNet flow logs + NSG enforcement | Azure workloads |
| [GCP Connector](https://github.com/chandrapati/csw-gcp-connector) | GCE label ingestion + VPC flow logs + firewall enforcement | GCP workloads |
| [NetFlow](https://github.com/chandrapati/csw-netflow-integration) | NetFlow v9/IPFIX agentless flow ingestion from switches | Network fabric visibility |
| [ERSPAN](https://github.com/chandrapati/csw-erspan-integration) | Agentless packet mirroring for legacy / OT / IoT devices | Deep agentless visibility |
| [Secure Firewall](https://github.com/chandrapati/CSW-Secure-Firewall-Integration-Guide) | NSEL flow ingestion from Cisco Secure Firewall (FTD/ASA) | Firewall flow visibility |
| [Splunk Integration](https://github.com/chandrapati/csw-splunk-integration) | CSW syslog alerts → Splunk SIEM | SecOps / SIEM teams |
| [Compliance Mapping](https://github.com/chandrapati/CSW-Compliance-Mapping) | Map CSW controls to NIST, PCI-DSS, HIPAA, CIS | Compliance & audit |
| [Tenant Insights](https://github.com/chandrapati/CSW-Tenant-Insights) | Tenant-level reporting and analytics | Visibility metrics |
| [Operations Toolkit](https://github.com/chandrapati/CSW-Operations-Toolkit) | Day-2 ops scripts: health checks, reporting, policy analysis | Ongoing operations |

> **Suggested customer journey:**  
> User Education → Agent Installation → Policy Lifecycle → ISE/pxGrid → ServiceNow CMDB → Splunk Integration → Compliance Mapping → Operations Toolkit