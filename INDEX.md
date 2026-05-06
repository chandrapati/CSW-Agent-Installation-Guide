# Quick Index — by OS, by Tool, by Question

> See [`README.md`](./README.md) for the high-level overview and the
> top-level decision matrix. This index is for jumping directly to
> the runbook that answers a specific question.

---

## By operating system

| OS family | Native methods | Automation methods |
|---|---|---|
| **RHEL / CentOS / Rocky / Alma / Oracle Linux** | [Manual RPM](./linux/01-manual-rpm-deb.md) · [CSW shell script](./linux/02-csw-generated-script.md) · [Yum repo / Satellite](./linux/03-package-repo-satellite.md) | [Ansible](./linux/04-ansible.md) · [Puppet](./linux/05-puppet.md) · [Chef](./linux/06-chef.md) · [Salt](./linux/07-saltstack.md) |
| **Ubuntu / Debian** | [Manual DEB](./linux/01-manual-rpm-deb.md) · [CSW shell script](./linux/02-csw-generated-script.md) · [APT repo](./linux/03-package-repo-satellite.md) | [Ansible](./linux/04-ansible.md) · [Puppet](./linux/05-puppet.md) · [Chef](./linux/06-chef.md) · [Salt](./linux/07-saltstack.md) |
| **SUSE / SLES** | [Manual RPM (zypper)](./linux/01-manual-rpm-deb.md) · [CSW shell script](./linux/02-csw-generated-script.md) | [Ansible](./linux/04-ansible.md) · [Puppet](./linux/05-puppet.md) |
| **Windows Server / Windows Client** | [Manual MSI](./windows/01-msi-silent-install.md) · [CSW PowerShell script](./windows/02-csw-generated-powershell.md) | [SCCM](./windows/03-sccm-deployment.md) · [Intune](./windows/04-intune-deployment.md) · [GPO](./windows/05-group-policy.md) · [Ansible (WinRM)](./linux/04-ansible.md) |
| **AIX / Solaris** | CSW 4.0 ships **AIX** and **Solaris** agents (Deep Visibility + Enforcement) — see [Cisco's *Install AIX Agents*](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html) and *Install Solaris Agents* sections | Same agent script installer pattern as Linux |
| **macOS / iOS / Android (endpoints)** | AnyConnect NVM via Cisco Secure Client (no CSW agent on the endpoint) — see [sensor types](./docs/02-sensor-types.md) | MDM-based deployment of Cisco Secure Client; AnyConnect connector on the CSW side |

---

## By automation tool

| Tool | Linux runbook | Windows runbook | Notes |
|---|---|---|---|
| **Ansible** | [linux/04-ansible.md](./linux/04-ansible.md) | Same playbook with `winrm` connection plugin | Most common enterprise pattern for Linux fleets |
| **Puppet** | [linux/05-puppet.md](./linux/05-puppet.md) | Module supports Windows; structure mirrors Linux manifest | Use the official Puppet Forge tetration module if available; otherwise the manifest in this repo |
| **Chef** | [linux/06-chef.md](./linux/06-chef.md) | Cookbook supports Windows | |
| **Salt** | [linux/07-saltstack.md](./linux/07-saltstack.md) | State files support Windows | |
| **SCCM (Microsoft Configuration Manager)** | n/a | [windows/03-sccm-deployment.md](./windows/03-sccm-deployment.md) | Standard enterprise pattern for Windows |
| **Intune** | n/a | [windows/04-intune-deployment.md](./windows/04-intune-deployment.md) | Cloud-managed Windows fleet |
| **Group Policy (GPO)** | n/a | [windows/05-group-policy.md](./windows/05-group-policy.md) | Fallback when SCCM / Intune are not available |
| **Terraform** | [cloud/04-terraform.md](./cloud/04-terraform.md) | [cloud/04-terraform.md](./cloud/04-terraform.md) | Embed agent in `user_data` / `custom_data` |
| **Packer** | [cloud/05-golden-ami.md](./cloud/05-golden-ami.md) | [cloud/05-golden-ami.md](./cloud/05-golden-ami.md) | Bake agent into the base image |
| **Helm (K8s)** | [kubernetes/01-daemonset-helm.md](./kubernetes/01-daemonset-helm.md) | n/a | Community / internally-maintained pattern. **Cisco's documented K8s install method is the Agent Script Installer** (it provisions namespace, RBAC, and DaemonSet for you) — see [kubernetes/02-daemonset-yaml.md](./kubernetes/02-daemonset-yaml.md) and the [Install Kubernetes or OpenShift Agents](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html) section of the CSW 4.0 User Guide. |
| **Cloud-init** | [cloud/01-aws-userdata.md](./cloud/01-aws-userdata.md) · [cloud/02-azure-customdata.md](./cloud/02-azure-customdata.md) · [cloud/03-gcp-startup-script.md](./cloud/03-gcp-startup-script.md) | Same | First-boot install on cloud VMs |

---

## By environment shape

| Environment shape | Recommended path |
|---|---|
| **Single host, lab / testing** | [Manual RPM/DEB](./linux/01-manual-rpm-deb.md) or [CSW shell script](./linux/02-csw-generated-script.md) |
| **Linux fleet, no automation tool yet** | [CSW-generated shell script](./linux/02-csw-generated-script.md) pushed via your existing remote-execution channel |
| **Linux fleet, Ansible already in use** | [Ansible playbook](./linux/04-ansible.md) — most common enterprise pattern |
| **Linux fleet, Puppet / Chef / Salt already in use** | Native module / cookbook / state — see linux/05–07 |
| **Air-gapped Linux** | [Internal Yum/APT repo via Satellite / Spacewalk / Pulp](./linux/03-package-repo-satellite.md) |
| **Windows fleet under SCCM** | [SCCM application + required deployment + compliance baseline](./windows/03-sccm-deployment.md) |
| **Windows fleet under Intune** | [Intune Win32 app + detection script](./windows/04-intune-deployment.md) |
| **Windows fleet without SCCM / Intune** | [GPO startup script fallback](./windows/05-group-policy.md) |
| **AWS EC2** | [user_data via Terraform](./cloud/01-aws-userdata.md) for new launches; [Golden AMI / Packer](./cloud/05-golden-ami.md) for fleet scale |
| **Azure VMs** | [custom_data / cloud-init](./cloud/02-azure-customdata.md); [Compute Gallery image](./cloud/06-azure-vm-image.md) for fleet scale |
| **GCP Compute Engine** | [Startup script via instance metadata](./cloud/03-gcp-startup-script.md); custom image for fleet scale |
| **Kubernetes (EKS / AKS / GKE / on-prem)** | [Agent Script Installer (Cisco-documented)](./kubernetes/02-daemonset-yaml.md); [Helm chart (community pattern)](./kubernetes/01-daemonset-helm.md) when your shop maintains its own chart |
| **OpenShift** | [DaemonSet with SCC adjustments](./kubernetes/04-openshift.md) |
| **Cloud accounts where deploying agents on every workload is impractical** | [Cloud Connector (agentless)](./agentless/README.md) for inventory + flow-log-tier visibility |
| **Network appliances / OT systems where agents are not allowed** | [NetFlow / ERSPAN ingestion](./docs/02-sensor-types.md) via the matching Secure Workload connector — see [Cisco's Connectors chapter](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html) |

---

## By question

| If you're asking… | Start here |
|---|---|
| *"Where is the official Cisco documentation for CSW 4.0?"* | [docs/00-official-references.md](./docs/00-official-references.md) — links the 4.0 On-Prem and SaaS User Guides |
| *"Which exact installer flags does CSW 4.0 ship?"* | [docs/00-official-references.md](./docs/00-official-references.md) (Linux installer flag table) |
| *"Can I bake the Windows agent into a VM template / golden image?"* | **Yes** — Cisco documents the path. Use `-goldenImage` (PowerShell installer) or `nostart=yes` (MSI installer); see [docs/00-official-references.md](./docs/00-official-references.md) (Windows VDI / golden-image flow) and [windows/README.md](./windows/README.md). |
| *"Do I need a CSW agent on AnyConnect endpoints or ISE-registered devices?"* | [docs/05-anyconnect-ise-alternatives.md](./docs/05-anyconnect-ise-alternatives.md) |
| *"Does CSW support Istio?"* | [docs/00-official-references.md](./docs/00-official-references.md) (K8s service mesh) and [kubernetes/README.md](./kubernetes/README.md) |
| *"What Calico version / Felix config does CSW 4.0 support?"* | [docs/00-official-references.md](./docs/00-official-references.md) (Calico 3.13 + Felix config) |
| *"What ports do I need open and to where?"* | [operations/01-network-prereq.md](./operations/01-network-prereq.md) |
| *"What OS versions are supported?"* | [docs/01-prerequisites.md](./docs/01-prerequisites.md) |
| *"Which sensor type should this workload run?"* | [docs/02-sensor-types.md](./docs/02-sensor-types.md) |
| *"Which install method fits my environment?"* | [docs/03-decision-matrix.md](./docs/03-decision-matrix.md) |
| *"How do I deploy without breaking production traffic?"* | [operations/07-enforcement-rollout.md](./operations/07-enforcement-rollout.md) |
| *"How do I know if the install actually worked?"* | [linux/08-verification.md](./linux/08-verification.md) · [windows/06-verification.md](./windows/06-verification.md) |
| *"My agent is installed but not registering with the cluster — why?"* | [operations/06-troubleshooting.md](./operations/06-troubleshooting.md) |
| *"How do I configure the agent behind a corporate proxy?"* | [operations/02-proxy.md](./operations/02-proxy.md) |
| *"How do I deploy in an air-gapped environment?"* | [operations/03-air-gapped.md](./operations/03-air-gapped.md) |
| *"How do I upgrade the agent to a new version?"* | [operations/04-upgrade.md](./operations/04-upgrade.md) |
| *"How do I cleanly uninstall?"* | [operations/05-uninstall.md](./operations/05-uninstall.md) |
| *"What evidence do I capture before opening a TAC case?"* | [operations/08-evidence-audit.md](./operations/08-evidence-audit.md) |
| *"What evidence does CSW produce for a compliance audit?"* | [operations/08-evidence-audit.md](./operations/08-evidence-audit.md) |
| *"Should I deploy the host agent or use a Cloud Connector?"* | [agentless/README.md](./agentless/README.md) and [agentless/05-comparison-matrix.md](./agentless/05-comparison-matrix.md) |
| *"How do I get visibility into network appliances / OT systems / SAN controllers that can't run a CSW agent?"* | [docs/02-sensor-types.md § 5 NetFlow / ERSPAN ingestion](./docs/02-sensor-types.md) — uses the device's own NetFlow / IPFIX / ERSPAN export landing on a Secure Workload Ingest Appliance |

---

## Disclaimer

Everything in this index points to draft v1 documentation. The
authoritative source for any specific CSW release remains the
*Cisco Secure Workload User Guide* and your release notes; always
cross-check before relying on this repository for a customer
engagement. See [`README.md`](./README.md) for the full disclaimer.
