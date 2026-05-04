# Installation Method Decision Matrix

You've read [`01-prerequisites.md`](./01-prerequisites.md) and
picked a sensor type from
[`02-sensor-types.md`](./02-sensor-types.md). Now pick the
installation method that fits your environment.

The matrix below answers: *given my environment, which method is
the lowest-friction and most operationally durable for the long
run?*

> **Official source for software-agent install paths.**
> [Deploy Software Agents on Workloads (4.0 On-Prem)](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
> documents both Cisco-supported install methods — the Agent Image
> Installer (manual `.rpm` / `.deb` / `.msi`) and the Agent Script
> Installer (the script CSW generates per tenant). Everything
> beyond those two methods (Ansible, Puppet, Chef, Salt, Helm,
> Terraform, golden images, etc.) is practitioner orchestration
> *around* those two install paths — the runbooks in this repo
> show the patterns, but the underlying installer-script flag set
> and per-OS installer behaviour are owned by the User Guide.
> See [`00-official-references.md`](./00-official-references.md)
> for the full link list.

---

## The Linux flowchart

```
                Do you have a config-management tool already?
                                  │
              ┌───────────────────┴────────────────────┐
            yes                                       no
              │                                        │
   Which one?                                  How big is the fleet?
              │                                        │
              │              ┌─────────────────────────┴─────────────────────┐
              │              1 host (lab)                  many hosts (no automation)
              │              │                                                │
              │   Manual RPM/DEB                          CSW-generated shell script
              │   linux/01-manual-rpm-deb.md              linux/02-csw-generated-script.md
              │                                                pushed via your existing
              │                                                remote-exec channel
              │                                                (jump host loop, parallel-ssh,
              │                                                 mssh, fabric, etc.)
   ┌──────────┼──────────┬──────────┬──────────┐
 Ansible   Puppet     Chef     Salt      Air-gapped?
   │          │         │         │            │
   │          │         │         │      Yes → Internal Yum/APT repo
   │          │         │         │           via Satellite / Spacewalk / Pulp
   │          │         │         │           linux/03-package-repo-satellite.md
   │          │         │         │
   linux/    linux/   linux/    linux/
   04-       05-      06-       07-
   ansible   puppet   chef      saltstack
```

---

## The Windows flowchart

```
                  What's your Windows config-management platform?
                                  │
        ┌─────────────────────────┼─────────────────────┬───────────────┐
       SCCM                    Intune                  GPO        None of the above
        │                         │                     │                │
        │                         │                     │                │
   windows/03-              windows/04-           windows/05-       Manual MSI
   sccm-deployment.md       intune-deployment.md  group-policy.md   windows/01-msi-silent-install.md
                                                                    or
                                                                    CSW-generated PowerShell
                                                                    windows/02-csw-generated-powershell.md
```

---

## The cloud flowchart

```
                  How are cloud VMs provisioned?
                                  │
              ┌───────────────────┴───────────────────────┐
       Imperative (manual/console)              IaC (Terraform / CloudFormation / ARM / Bicep)
              │                                                          │
              │                                                          │
   Bake into the launching tool's                       ┌────────────────┴───────────────┐
   user_data / custom_data field             First-launch hook              Image-baked
   per provider:                               │                                  │
                                                              │                                  │
   AWS:    cloud/01-aws-userdata.md            │                                  │
   Azure:  cloud/02-azure-customdata.md      Embed in user_data /          Build a Golden AMI
   GCP:    cloud/03-gcp-startup-script.md    custom_data:                  / Compute Gallery image
                                              cloud/04-terraform.md         with the agent
                                                                            preinstalled:
                                                                            cloud/05-golden-ami.md
                                                                            cloud/06-azure-vm-image.md
                                                                            (for fleet scale; the
                                                                             "best" pattern at scale)
```

---

## The Kubernetes flowchart

```
                       Is Helm permitted in the cluster?
                                  │
              ┌───────────────────┴────────────────────┐
            yes                                       no
              │                                        │
   kubernetes/01-daemonset-helm.md         kubernetes/02-daemonset-yaml.md
                                                       │
                                                       │
                                            (raw DaemonSet manifest with images
                                             from your internal registry)


               Which K8s distro?
                       │
   ┌───────────────────┼─────────────────┬──────────────────┐
  EKS / AKS / GKE    OpenShift        Plain K8s         Rancher / RKE
        │                  │                │                   │
   kubernetes/03-     kubernetes/04-     kubernetes/01     kubernetes/01
   eks-aks-gke.md     openshift.md       (Helm) or 02      (Helm) or 02
                      (Security Context  (raw)             (raw)
                       Constraints
                       adjustments)
```

---

## The agentless decision

```
              Why am I considering the Cloud Connector?
                                  │
   ┌──────────────────────────────┼──────────────────────────────┐
   │                              │                              │
"To replace agents"        "To complement agents"      "Specific accounts where
                                                        agents aren't deployed"
   │                              │                              │
   Don't.                  Recommended pattern.         Recommended pattern.
   Use agents on every     Connector catches            Connector covers DR /
   workload you can.       unmanaged shadow             sandbox / partner
   The Connector is        workloads + provides         accounts where the
   meaningfully thinner    cross-cloud flow-log         agent install team
   than an agent.          inventory.                   doesn't have access.
```

Detail in [`../agentless/`](../agentless/).

---

## Method-by-method comparison

| Method | Best for | Effort to set up | Effort to maintain | Air-gap friendly | Notes |
|---|---|---|---|---|---|
| Manual RPM/DEB | One-off lab installs | Low (single host) | High (no automation) | Yes | Use only for labs; doesn't scale |
| Manual MSI | One-off lab installs | Low (single host) | High (no automation) | Yes | Use only for labs; doesn't scale |
| CSW-generated shell / PowerShell script | Small to medium fleets without automation | Low | Medium (manual rerun for upgrades) | Limited (script downloads from cluster URL) | The most common method for first-month POVs |
| Internal Yum/APT repo (Satellite / Spacewalk / Pulp) | Air-gapped or change-controlled Linux fleets | Medium (set up the repo) | Low (treat like any other RPM) | Yes | Works inside existing OS-patching pipelines |
| Ansible | Linux fleets where Ansible already runs | Medium (write playbook) | Low (one play to upgrade fleet) | Yes (with offline package source) | Most common enterprise Linux pattern |
| Puppet | Linux fleets where Puppet runs | Medium | Low | Yes | Idiomatic Puppet manifest |
| Chef | Linux fleets where Chef runs | Medium | Low | Yes | Idiomatic Chef recipe |
| Salt | Linux fleets where Salt runs | Medium | Low | Yes | Idiomatic Salt state |
| SCCM | Windows fleets under Configuration Manager | Medium (package + deployment + compliance baseline) | Low | Yes | Standard enterprise Windows pattern |
| Intune | Windows fleets under Microsoft Endpoint Manager (cloud) | Medium (Win32 app + detection script) | Low | No (Intune is cloud-managed) | Standard for cloud-managed Windows |
| GPO startup script | Windows fleets without SCCM / Intune | Low (script + GPO) | Medium (GPO is coarse) | Yes | Fallback only |
| Cloud `user_data` / `custom_data` / startup script | New cloud VMs | Low | Low | Limited (cloud-provider native) | Works with any IaC tool |
| Terraform module | New cloud VMs in IaC pipelines | Medium (write the module) | Low | Yes (with private package source) | Embeds in `user_data` / `custom_data` |
| Golden AMI / Compute Gallery image | Cloud at scale | High (image-bake pipeline) | Low (ship new image; rollouts replace) | Yes (private registry) | Best pattern at scale; zero-touch on new VMs |
| Helm DaemonSet | Kubernetes / OpenShift | Low (Helm install) | Low (`helm upgrade`) | Limited (chart pull) | Standard K8s pattern |
| Raw DaemonSet manifest | Air-gapped K8s; no-Helm shops | Medium | Low | Yes (with internal registry) | Use when Helm isn't permitted |
| Cloud Connector (agentless) | Inventory + flow-log scope without agent | Medium (IAM / RBAC + connector config) | Low | No (connector talks to public cloud APIs) | Complementary to host agents |
| **NetFlow / ERSPAN ingestion** via Secure Workload connector | Workloads that forbid agents (network appliances, storage / SAN, OT) | Medium — Ingest Appliance + connector + source-device export config | Low (after deployment) | Yes | Use the device's native NetFlow / IPFIX / NSEL export where available; fall back to ERSPAN for port-mirror-only sources. See [Cisco Connectors chapter](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html). |

---

## Common combinations

Most production fleets end up with **multiple methods running in
parallel**. A typical large enterprise looks like:

| Workload class | Method |
|---|---|
| Existing on-prem Linux servers | Ansible playbook against current inventory |
| New on-prem Linux VMs | Same Ansible playbook in post-build hook |
| Cloud VMs (AWS / Azure) | Golden image with agent baked in; Terraform module hands them off to CSW with the right scope label |
| Existing Windows servers | SCCM application + required deployment |
| New Windows servers | Same SCCM deployment + image-baked agent for the most-common builds |
| Kubernetes (EKS, AKS, on-prem RKE) | DaemonSet via Helm in each cluster |
| Storage / network appliances | NetFlow / ERSPAN ingestion via the matching Secure Workload connector — NetFlow / IPFIX / NSEL where the device exports it, ERSPAN of the storage / appliance VLAN otherwise |
| DR / sandbox cloud accounts | Cloud Connector for inventory + flow-log visibility |
| Corporate laptops | AnyConnect NVM via Cisco Secure Client + Intune |

Plan for this fan-out from day one — it's easier to have three
or four methods running cleanly than to force a single method to
cover every shape.

---

## See also

- [`01-prerequisites.md`](./01-prerequisites.md) — gates that apply to every method
- [`02-sensor-types.md`](./02-sensor-types.md) — pick the sensor before picking the method
- [`04-rollout-strategy.md`](./04-rollout-strategy.md) — phased Monitor → Simulate → Enforce
- The per-method runbooks under [`../linux/`](../linux/), [`../windows/`](../windows/), [`../cloud/`](../cloud/), [`../kubernetes/`](../kubernetes/), [`../agentless/`](../agentless/)
