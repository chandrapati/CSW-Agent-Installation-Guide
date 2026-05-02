# Network Prerequisites — Detailed

Reference for the network team. Use this when the agent
prerequisites in [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
need to land in firewall / security review tickets.

---

## Required outbound connectivity

From every workload that runs the CSW sensor:

| Direction | Source | Destination | Port / Protocol | Purpose |
|---|---|---|---|---|
| Outbound | Sensor host | CSW cluster public endpoint (FQDN) | TCP/443 (HTTPS) | Agent-to-cluster control plane and telemetry |
| Outbound | Sensor host | NTP source | UDP/123 | Time sync (clock skew breaks TLS auth) |
| Outbound | Sensor host | DNS resolver | UDP/53 (TCP/53 fallback) | Resolve cluster FQDN |
| Outbound | Sensor host | OS / package repo (initial install only) | TCP/443 (HTTPS) | Resolves dependencies during package install |

For SaaS CSW the destination is the regional CSW SaaS endpoint
(documented in your tenant's onboarding email). For on-prem CSW
the destination is your cluster's public DNS / VIP.

> **No inbound from the cluster to the sensor.** The sensor
> initiates and maintains the TLS session — your firewall doesn't
> need any inbound exception for the cluster's IP range.

---

## TLS handshake details

- TLS 1.2 minimum; TLS 1.3 supported in current sensor releases
- Cipher suites: AEAD only (AES-GCM, ChaCha20-Poly1305) in
  current releases; older releases negotiate down to AES-CBC if
  the cluster cert chain demands it
- The sensor pins the CA chain it expects from the cluster — for
  on-prem CSW with internal PKI, the CA chain ships with the
  installer; for SaaS it's a public CA the sensor's bundled
  trust store accepts
- mTLS (mutual TLS): the sensor presents a per-host client cert
  derived from the activation key during initial registration,
  then a long-lived per-host cert for the rest of its life

---

## Bandwidth and traffic shape

For sizing firewall / SD-WAN policy:

| Workload class | Steady-state egress to cluster |
|---|---|
| Quiet workload (DB tier, low flow rate) | 5–20 KB/s |
| Typical app server (medium flow rate) | 50–200 KB/s |
| Busy workload (load balancer, high flow rate) | 200 KB – 2 MB/s |
| Initial inventory burst (first hour after install) | 2–5x the above |

For 1,000 sensors at the typical-app-server tier you should
budget ~100 Mbps aggregate egress to the cluster. Burst tolerant
profiles in QoS (rather than rate-limiting) are the right shape
— sustained rate-limiting causes telemetry loss and inventory
gaps, which can look like agent failures.

---

## Firewall ticket template

Use as a starting point; adapt to your team's ticketing format:

```
SUMMARY: Permit CSW sensor outbound for <scope description>

SOURCE: <CIDR or VLAN containing the workloads to be instrumented>

DESTINATION: <CSW cluster FQDN>
              (resolves to <IP / IP range>; please permit by
               FQDN if possible since the SaaS cluster's
               IPs may rotate within the published range)

PORTS: TCP/443

DIRECTION: Outbound from source to destination only

REASON: Cisco Secure Workload (CSW) agent must reach the
        cluster to register and stream telemetry. Sensor uses
        outbound TLS 1.2+, mutual TLS with per-host client
        certs. No inbound permit required.

VOLUME ESTIMATE: ~100 Kbps per workload steady-state; 200 Kbps
                  burst during first hour after install

ASSOCIATED CHANGES: <NTP source if not already permitted from
                    the source range>

REQUESTOR: <name>
ASSOCIATED PROJECT / CHANGE TICKET: <link>
```

---

## NTP / time sync

The sensor's TLS handshake will fail if the host clock skews
more than ~5 minutes from the cluster. Symptoms look like
"sensor installed but never registers."

- Use the same NTP source the rest of the estate uses
- Verify with `chronyc sources` (RHEL 8+) or `timedatectl
  timesync-status` (modern systemd)
- For Windows: `w32tm /query /status` and `w32tm /query /peers`

If NTP isn't available (rare, but happens in air-gapped or
isolated networks), point the host clock at a host that can
reach NTP and treat that as the time anchor. The sensor only
needs the clock to be correct — it doesn't care about the source.

---

## DNS

- The sensor resolves the cluster FQDN at startup and on
  reconnect — DNS reachability is required at every restart,
  not just at install time
- If you use split-horizon DNS, make sure the sensor's view of
  the cluster FQDN is the *external* one (matching the cluster
  cert's SAN list)
- If you use DNS interception (some content-filter appliances do
  this), make sure the cluster FQDN is on the bypass list — DNS
  interception that returns a placeholder will fail TLS

---

## Cluster-side prerequisites

Beyond the workload-side network items, the CSW cluster needs
to be reachable. For SaaS CSW that's Cisco's responsibility;
for on-prem CSW the cluster admin team needs:

- A public (or routable-from-workload) DNS entry for the cluster
- A valid TLS cert with the cluster FQDN in the SAN list
- The cluster's CA bundle distributed to the install jobs (for
  internal-CA setups)

---

## See also

- [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- [`02-proxy.md`](./02-proxy.md)
- [`03-air-gapped.md`](./03-air-gapped.md)
- [`06-troubleshooting.md`](./06-troubleshooting.md)
