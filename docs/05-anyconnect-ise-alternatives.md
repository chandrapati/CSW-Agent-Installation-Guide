# When You Don't Need a CSW Agent — AnyConnect NVM and ISE

CSW 4.0 supports two endpoint-class platforms where **no CSW
agent is required on the device**, because Cisco-side connectors
provide the equivalent telemetry. This doc is the operating
model for both.

> **Official source.** See
> [`00-official-references.md`](./00-official-references.md) for
> the CSW 4.0 User Guide links.

---

## At a glance

| Path | Endpoint side | CSW side | What CSW gets |
|---|---|---|---|
| **AnyConnect NVM** | Cisco Secure Client (formerly AnyConnect) with the Network Visibility Module (NVM) enabled | AnyConnect connector | Flow observations, inventory, labels |
| **Cisco ISE** | Endpoint registered with Cisco ISE (any supported endpoint type) | ISE connector via pxGrid | Endpoint metadata (identity, posture, profile) |
| **CSW host agent (for comparison)** | `csw-agent` / `CswAgent` on the workload (older clusters: `tetd` / `TetSensor`) | Direct sensor → cluster registration | Flow + process + software inventory + CVE + (optional) enforcement |

**Pick by need:**

- Need process attribution, software inventory, CVE lookup, or
  workload-side enforcement → install the CSW agent. The
  connectors do not provide those.
- Need only flow observations (NVM) or endpoint identity /
  posture context (ISE) → the connector is enough; skip the
  agent.
- Need both → run them in parallel. CSW reconciles them.

---

## Path 1 — AnyConnect Network Visibility Module (NVM)

### What NVM is

The Network Visibility Module is a sub-feature of **Cisco Secure
Client** (the product formerly known as AnyConnect). When NVM is
enabled in the Secure Client profile, the endpoint emits IPFIX-
style flow records describing its outbound connections —
5-tuple, byte / packet counters, attributed user identity, and
an optional process name where the OS allows it.

### When NVM is the right answer (and the CSW agent is not needed)

- **Corporate laptops / desktops** in user-endpoint roles. The
  CSW host agent is a server-class control; NVM is the
  endpoint-class equivalent for flow visibility.
- **Devices that already run Secure Client** for VPN /
  ZTNA — flipping on NVM is a profile toggle, not a separate
  install.
- **Endpoints subject to user-privacy controls** that disallow
  per-process telemetry from a third-party agent. NVM's
  collection scope is bounded by the Secure Client profile.

### What NVM does NOT replace

- Server-class workload visibility — Linux / Windows servers,
  AIX, Solaris, Kubernetes nodes. Those need the host agent.
- Workload-side policy enforcement.
- Software inventory + CVE lookup at server-class depth.
- OT / appliance / SAN visibility — use **NetFlow / ERSPAN
  ingestion** via the matching Secure Workload connector
  (see [`02-sensor-types.md` § 5](./02-sensor-types.md)).

### Operating model

1. **Endpoint side.** Cisco Secure Client deployed via your MDM
   (Intune, Workspace ONE, Jamf for macOS) with NVM enabled in
   the Secure Client profile.
2. **CSW side.** *Manage → External Orchestrators / Connectors
   → AnyConnect*. Configure the connector with the Secure Client
   server endpoint (your ISE / Secure Client deployment server)
   and the destination scope where these endpoints should land.
3. **First flows arrive** within minutes of the endpoint
   reaching the network. CSW UI shows the endpoint as a
   registered inventory item with NVM as the source.
4. **Tags + scope membership** flow from the connector. The
   endpoint inherits any tags applied by Secure Client / ISE
   integration.

### Cross-references

- [Cisco Secure Client (formerly AnyConnect) documentation](https://www.cisco.com/c/en/us/support/security/anyconnect-secure-mobility-client-v5/series.html)
  — NVM profile editor and collection definitions
- [Configure and Manage Connectors for Secure Workload (4.0
  On-Prem)](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html)
  — AnyConnect Connector subsection
- [`02-sensor-types.md`](./02-sensor-types.md) — sensor decision
  table

---

## Path 2 — Cisco ISE registration

### What the ISE path is

Endpoints that have authenticated to your network via **Cisco
ISE** (802.1X, MAB, web-auth, posture, profiling) are surfaced
to CSW through the **ISE connector**, which subscribes to ISE's
**pxGrid** topic for endpoint metadata.

### What the ISE path provides

- Endpoint identity (user, device class, MAC, IP, ISE-assigned
  groups)
- Endpoint posture status (compliant / non-compliant / unknown)
- Endpoint profile (Cisco IP Phone, IoT category, BYOD, etc.)
- Last-seen network attachment context

### What the ISE path does NOT provide

- Flow telemetry (use NVM in parallel for that)
- Process attribution
- Software inventory
- Workload-side enforcement

### When the ISE path is the right answer

- **Mixed-device estates** — printers, IoT, OT devices, BYOD,
  contractor laptops — that you want surfaced in CSW inventory
  for context, but where deploying a CSW agent is not feasible
  or appropriate.
- **Posture-driven scoping.** Use ISE-reported posture status as
  a CSW inventory tag and scope membership criterion.
- **Identity-driven enrichment.** Use the ISE-known user /
  device-owner attribution to enrich flows that the host agent
  produces (when the host agent is on the workload but doesn't
  see the user identity at the network layer).

### Operating model

1. **ISE side.** ISE deployment with pxGrid enabled and a
   pxGrid client certificate issued to CSW.
2. **CSW side.** *Manage → External Orchestrators / Connectors
   → ISE*. Configure with the ISE PSN endpoints, pxGrid topics
   to subscribe to, and the destination scope.
3. **First inventory arrives** within minutes. CSW UI shows
   ISE-known endpoints as inventory items with their ISE
   attributes as tags.

### Cross-references

- [Cisco ISE Administrator Guide](https://www.cisco.com/c/en/us/support/security/identity-services-engine/series.html)
  — pxGrid configuration, certificate issuance, topic publishing
- [Configure and Manage Connectors for Secure Workload (4.0
  On-Prem)](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html)
  — ISE Connector subsection

---

## Decision flow

```
Is the endpoint a server-class workload (Linux / Windows server, AIX, Solaris, K8s node)?
    │
    ├── yes → install the CSW host agent (this repo's Linux / Windows / kubernetes runbooks)
    │
    └── no, it's a user-endpoint or appliance-class device
            │
            ├── Does it run Cisco Secure Client?
            │       └── yes → enable NVM; let the AnyConnect connector ingest; no CSW agent
            │
            ├── Is it ISE-registered?
            │       └── yes → ISE connector ingests endpoint metadata; no CSW agent
            │
            ├── Is it a network appliance / SAN / OT system that can't run an agent?
            │       └── yes → NetFlow / ERSPAN ingestion via the matching Secure Workload connector
            │                 (NetFlow / IPFIX / NSEL where the device exports it; ERSPAN otherwise).
            │                 See docs/02-sensor-types.md § 5.
            │
            └── Is it a cloud workload you can't or shouldn't agent?
                    └── yes → Cloud Connector (see ../agentless/)
```

---

## Common combinations in production

### Pattern A — Server agents + endpoint NVM + ISE for context

- CSW host agent on every supported server-class workload
- AnyConnect NVM on every Secure Client–managed laptop
- ISE connector for inventory/identity context across the whole
  802.1X-authenticated estate

CSW reconciles all three: a single host that's both a server
(agent-instrumented) and ISE-known surfaces both signals
attributed to the same inventory item.

### Pattern B — Server agents + ISE only

- CSW host agent on servers
- ISE connector for the user / IoT / OT estate
- No NVM (no Secure Client deployment, or out of scope)

Loses endpoint flow visibility but retains server-side depth and
endpoint identity context.

### Pattern C — Connectors only (no CSW agents anywhere)

- AnyConnect + ISE connectors for the endpoint estate
- Cloud connectors for cloud workloads
- vCenter connector for the on-prem virtual estate

This is the **inventory-first** posture — useful for early
discovery and reconciliation programmes, but you forgo process
attribution, software inventory, CVE lookup, and any path to
enforcement. Layer the agent on top once you've decided which
workloads are in scope for active control.

---

## See also

- [`00-official-references.md`](./00-official-references.md)
- [`01-prerequisites.md`](./01-prerequisites.md)
- [`02-sensor-types.md`](./02-sensor-types.md)
- [`../agentless/`](../agentless/) — cloud / vCenter connectors (the same "no agent" pattern, but for cloud and on-prem virtualisation)
