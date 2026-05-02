# Agentless — vCenter Connector

CSW pulls VM inventory and metadata (host, cluster, datastore,
folder, tags) from vCenter Server. No agent runs on the guest
VMs themselves; this is purely the vSphere control-plane view.

---

## What you get

- VM, host (ESXi), cluster, datastore, port group, folder
  inventory across the connected vCenters
- vSphere tags as inventory enrichment in CSW
- Reconciliation against the host-agent inventory: which VMs
  have an agent, which don't
- Per-VM metadata: CPU/RAM, OS family (as reported by VMware
  Tools), datastore location, network adapters, attached host

## What you don't get

- Network flow data — vCenter doesn't expose flow telemetry on
  its own. For flow data you need either:
  - The **host agent** on the guest VMs, or
  - **NSX flow data** ingested via a separate connector (in
    releases that support it), or
  - Out-of-band flow capture (port mirror to a hardware sensor —
    see [`../docs/02-sensor-types.md`](../docs/02-sensor-types.md))
- Process / software / CVE / enforcement on the guest

---

## When this is the right answer

- **Brownfield discovery** — see what's actually in vCenter,
  reconcile against the agent-installed view, identify shadow
  VMs that nobody installed an agent on
- **VMs you can't agent** — appliances (network virtual appliances,
  vendor-supplied images that disallow third-party agents),
  legacy guests
- **Inventory-only segments** — DR replicas, vendor-managed
  enclaves where you want metadata but not telemetry

It's NOT enough on its own for segmentation work — without flow
data, CSW can't propose policy. Pair it with the agent on
representative guests.

---

## Prerequisites

- vCenter Server 7.0 U3+ (older versions supported in older CSW
  releases; check the matrix)
- Network reachability from the CSW connector to the vCenter
  API endpoint (usually 443) — for on-prem CSW this is direct,
  for SaaS CSW you'll likely need a connector appliance inside
  your DC. See "Connector appliance" below.
- vSphere read-only role permissions

---

## Step 1 — Create a dedicated vSphere user

In vCenter:

1. Create a Single Sign-On user (or use an Active Directory
   user) — `csw-connector@vsphere.local` is conventional
2. Set a strong password (rotate per your policy)
3. Document the credential in your secrets store

---

## Step 2 — Grant a read-only role at the inventory root

In vCenter:

1. Navigate to *Administration → Roles*
2. Either use the built-in **Read-Only** role, or clone it and
   add `vSphere Tagging → Assign and unassign vSphere tag`
   permission so CSW can read tags
3. Navigate to *Inventory → vCenter root → Permissions → Add*
4. Add the user from Step 1 with the role from Step 2
5. **Check "Propagate to children"** so the role applies to all
   datacenters, clusters, and VMs

> If you want to limit CSW to a subset of the inventory (e.g.,
> a specific folder or resource pool), grant the role at that
> object instead of the root. CSW will only see what the user
> can see.

---

## Step 3 — (Optional) Connector appliance in your DC

For SaaS CSW, the cluster reaches into your DC through a
**connector appliance** — a Cisco-published OVA you deploy in
vSphere (or as a Linux VM running the connector container).
The appliance establishes an outbound TLS tunnel to the CSW
cluster and proxies the vCenter API calls.

Deployment summary:

1. Download the OVA from the CSW UI (*Manage → Connector
   Appliances → Download*)
2. Deploy in vCenter (a few CPU / GB RAM; see Cisco's published
   sizing for your release)
3. Console into the appliance, run the bootstrap with the
   activation token from CSW
4. The appliance appears in CSW within a minute as
   `Online`

For on-prem CSW the appliance step is usually unnecessary
because the cluster is already inside the DC perimeter.

---

## Step 4 — Configure the connector in the CSW UI

1. Log into the CSW UI
2. Navigate to *Manage → External Orchestrators → vCenter*
3. Click *Add Connector*
4. Provide:
   - Connector name (e.g., `vcenter-prod-dc1`)
   - vCenter FQDN or IP
   - vSphere username + password from Step 1
   - vCenter SSL certificate fingerprint (or trust the public
     CA the cert chains to)
   - Connector appliance to use (if you deployed one in Step 3)
5. Click *Test Connection*. CSW logs in to vCenter and reads
   the inventory root.
6. Save. First inventory sync runs within minutes.

---

## Step 5 — Verify

- *Organize → Inventory → Filter by `vsphere_cluster = <cluster>`*
- *Click into a VM*: vSphere folder, host, datastore, tags should
  all appear as inventory attributes
- *Manage → External Orchestrators → click the connector*: last
  successful sync timestamp should be recent (< 5 minutes)

---

## Multi-vCenter at scale

Each vCenter is its own connector record. For dozens of
vCenters:

- Use a single set of vSphere SSO credentials federated to
  Active Directory; rotate centrally
- Naming convention: `vcenter-<region>-<dc>-<env>` so the
  inventory tags sort cleanly in CSW
- For the connector appliance, one appliance can typically
  serve multiple vCenters in the same DC — confirm sizing for
  your scale

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| "Test Connection" fails with TLS error | vCenter cert is self-signed and the fingerprint isn't trusted | Either install a properly-signed cert in vCenter, or paste the SHA-256 fingerprint into the connector setup form |
| Sync succeeds but only some clusters appear | Read-only role granted at a sub-folder, not at the inventory root | Re-grant at vCenter root with "Propagate to children" |
| Tags don't appear on inventory | Read-only role doesn't include `vSphere Tagging → Read` | Clone Read-Only and add the tagging permission, then re-bind |
| Sync is slow / times out on very large vCenters (10k+ VMs) | Default page-size is too aggressive | In CSW, lower the inventory pull cadence or shard by folder |
| Connector appliance reports `Disconnected` after a vCenter restart | Session token expired; appliance retries with backoff | Should self-heal within a few minutes; if persistent, restart the connector container on the appliance |

---

## See also

- [`05-comparison-matrix.md`](./05-comparison-matrix.md)
- [`../docs/02-sensor-types.md`](../docs/02-sensor-types.md) — including the *Hardware Sensor* option for flow capture without guest agents
- [`../linux/`](../linux/) and [`../windows/`](../windows/) — agent path for guest VMs
