# Network Prerequisites — Detailed

Reference for the network team. Use this when the agent
prerequisites in [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
need to land in firewall / security review tickets.

> **Authoritative source.** All port / connection claims here
> are sourced from the *Connectivity Information* section
> (Table 2 in the chapter) of Cisco's
> [Deploy Software Agents on Workloads (4.0 On-Prem)](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
> guide. Bandwidth / sizing numbers are practitioner estimates
> — Cisco does not publish per-workload bandwidth figures, so
> validate with a small pilot before sizing WAN circuits.

---

## Required outbound connectivity

The exact port set depends on **agent type (Visibility vs.
Enforcement)** and **deployment mode (on-premises vs. SaaS)**:

### On-premises CSW

| Direction | Source | Destination | Port / Protocol | Purpose |
|---|---|---|---|---|
| Outbound | Workload | **Config server (Sensor VIP)** | TCP/**443** | Registration, configuration, software updates |
| Outbound | Workload | **All collectors** | TCP/**5640** | Flow telemetry upload |
| Outbound | Workload (Enforcement only) | **One** of the enforcement endpoints | TCP/**5660** | Policy fetch + enforcement ack |
| Outbound | Kubernetes / OpenShift node | **Config server** | TCP/**443** | Docker image fetch |

### SaaS CSW

| Direction | Source | Destination | Port / Protocol | Purpose |
|---|---|---|---|---|
| Outbound | Workload | Config server FQDN | TCP/**443** | Registration, configuration, software updates |
| Outbound | Workload | Collectors | TCP/**443** | Flow telemetry upload |
| Outbound | Workload (Enforcement only) | Enforcement endpoint | TCP/**443** | Policy fetch + enforcement ack |

> **SaaS — everything on 443.** The SaaS endpoints multiplex
> control / telemetry / enforcement onto the same TCP/443. If
> you've already got an outbound 443 hole for the SaaS FQDN,
> you've got everything you need.

### Plus, every deployment

| Direction | Source | Destination | Port / Protocol | Purpose |
|---|---|---|---|---|
| Outbound | Workload | NTP source | UDP/**123** | Time sync (clock skew breaks TLS auth) |
| Outbound | Workload | DNS resolver | UDP/**53** (TCP/53 fallback) | Resolve cluster FQDN(s) |
| Outbound | Workload | OS / package repo (initial install only) | TCP/443 | Resolves dependencies during package install |

> **Where to find your cluster's IPs.** *Platform → Cluster
> Configuration*: the **Sensor VIP** is the config server; the
> **External IPs** list the collector(s) and enforcer(s). The
> *Manage → Workloads → Agents → Installer* screen also reflects
> this for the cluster you're logged into.

> **High availability.** Per Cisco: *"Deep visibility and
> enforcement agents connect to all available collectors. The
> enforcement agent connects to only one of the available
> endpoints."* For HA on-prem clusters, the firewall rule must
> permit egress to **every** collector / enforcer IP — not
> just the first one returned by DNS or the one the agent
> currently happens to use.

> **No inbound from the cluster to the workload.** Per Cisco:
> *"The Secure Workload agent always acts as a client to
> initiate the connections to the services hosted within the
> cluster, and never opens a connection as a server. … An
> agent can be located behind NAT."* The cluster never connects
> *to* the workload — your firewall doesn't need any inbound
> exception from the cluster's IP range.

---

## TLS handshake details

What's documented vs. what's release-specific:

**Documented by Cisco (4.0 chapter):**

- The agent uses TLS to secure the TCP connections to all
  cluster services.
- The agent validates the cluster's TLS certificate **against
  a local CA installed with the agent** (the `ca.cert` shipped
  in the installer). Any other certificate sent to the agent
  results in connection failure.
- Proxies must be configured to **bypass SSL/TLS decryption**
  for agent communications (otherwise the proxy's certificate
  fails validation against the agent's local CA).

**Not formally documented in the public 4.0 chapter — practitioner observations, treat as release-specific:**

- Minimum TLS version, exact cipher suite list. Most current
  releases negotiate TLS 1.2+ with AEAD ciphers; if you have a
  hard organisational TLS-version policy, validate it against
  your agent + cluster release with a TLS scan.
- Whether per-host client certificates are minted from the
  activation key on first registration vs. issued separately.
  Functionally the agent uses TLS plus per-host identity
  established at registration; the precise mechanism varies by
  release. If your security review needs the formal
  description, request it through your Cisco TAC / account
  team rather than relying on community write-ups.

---

## Bandwidth and traffic shape

> **Caveat.** Cisco does not publish per-workload bandwidth
> figures in the public 4.0 documentation. The numbers below
> are practitioner estimates from production deployments — use
> them for first-pass sizing, then validate with a pilot of
> ~50–100 agents before committing WAN-circuit sizing.

| Workload class | Approximate steady-state egress to cluster |
|---|---|
| Quiet workload (DB tier, low flow rate) | low tens of KB/s |
| Typical app server | low hundreds of KB/s |
| Busy workload (load balancer / high flow rate) | up to a few MB/s |
| Initial inventory burst (first hour after install) | 2–5× the above |

For sizing, **validate with a sample** before extrapolating.
For 1,000 typical-app-server agents, ~100 Mbps aggregate
egress is a reasonable first-pass budget. **Burst-tolerant**
QoS profiles (rather than hard rate-limiting) are the right
shape — sustained rate-limiting causes telemetry loss and
inventory gaps, which can look like agent failures.

---

## Firewall ticket template

Use as a starting point; adapt to your team's ticketing
format. Adjust for on-prem vs. SaaS per the tables above.

```
SUMMARY: Permit CSW agent outbound for <scope description>

SOURCE: <CIDR or VLAN containing the workloads to be instrumented>

DESTINATION: <CSW cluster FQDN(s)>
              (resolves to <IP / IP range>; please permit by
               FQDN if possible since the SaaS cluster's
               IPs may rotate within the published range)

PORTS:
  - TCP/443  (config server; all deployments)
  - TCP/5640 (collectors; on-prem only)
  - TCP/5660 (enforcer; on-prem only, for Enforcement agents)
  - UDP/123  (NTP, if not already permitted)
  - UDP/53 + TCP/53 (DNS, if not already permitted)

DIRECTION: Outbound from source to destination only.
           No inbound from cluster to workload required.

REASON: Cisco Secure Workload (CSW) agent must reach the
        cluster to register and stream telemetry. Per Cisco's
        Deploy Software Agents documentation:
        - Agent only acts as a client (never as a server)
        - Agent validates cluster TLS cert against its own
          local CA — proxies must bypass SSL inspection for
          this destination

VOLUME ESTIMATE (validate via pilot):
  ~100 Kbps per workload steady-state typical, with bursts
  to ~200–500 Kbps during the first hour after install

ASSOCIATED CHANGES:
  - NTP source if not already permitted from the source range
  - SSL-inspection bypass on the cluster FQDN

REQUESTOR: <name>
ASSOCIATED PROJECT / CHANGE TICKET: <link>
```

---

## NTP / time sync

The agent's TLS handshake will fail if the host clock skews
more than a few minutes from the cluster. Symptoms look like
"agent installed but never registers."

- Use the same NTP source the rest of the estate uses
- Verify with `chronyc sources` (RHEL 8+) or `timedatectl
  timesync-status` (modern systemd)
- For Windows: `w32tm /query /status` and `w32tm /query /peers`

If NTP isn't available (rare, but happens in air-gapped or
isolated networks), point the host clock at a host that can
reach NTP and treat that as the time anchor. The agent only
needs the clock to be correct — it doesn't care about the
source.

---

## DNS

- The agent resolves the cluster FQDN at startup and on
  reconnect — DNS reachability is required at every restart,
  not just at install time.
- If you use split-horizon DNS, make sure the agent's view of
  the cluster FQDN is the one whose IPs the cluster cert's
  SAN list covers.
- If you use DNS interception (some content-filter appliances
  do this), make sure the cluster FQDN is on the bypass list —
  DNS interception that returns a placeholder will fail TLS.

---

## SSL / TLS inspection

> **Direct from Cisco:** *"Configure explicit or transparent
> web proxies to bypass SSL/TLS decryption for agent
> communications. If bypass rules are not configured, proxies
> may attempt to decrypt SSL/TLS traffic by sending their own
> certificate to the agent. Since the agent only uses its
> local CA to validate certificates, proxy certificates will
> cause connection failures."*

In practice this means: any forward proxy, NGFW, or CASB on the
egress path **must allow-list the CSW cluster FQDN(s) for
SSL-bypass.** If your security policy is "decrypt all egress
HTTPS," this is the exception you'll need to carve out for CSW.

See [`02-proxy.md`](./02-proxy.md) for the full proxy treatment.

---

## Cluster-side prerequisites

Beyond the workload-side network items, the CSW cluster needs
to be reachable. For SaaS CSW that's Cisco's responsibility;
for on-prem CSW the cluster admin team needs:

- A public (or routable-from-workload) DNS entry for each
  cluster IP that workloads will reach (Sensor VIP, collectors,
  enforcers).
- A valid TLS cert chain with the cluster FQDN(s) in the SAN
  list, signed by the CA bundled in the agent installer.
- The agent installer regenerated and re-distributed any time
  the cluster CA / certs change (otherwise existing agents
  validate fine, but freshly installed agents fail TLS).

---

## See also

- [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md) — agent-side prereq summary
- [`02-proxy.md`](./02-proxy.md) — proxy / SSL-inspection bypass
- [`03-air-gapped.md`](./03-air-gapped.md) — air-gapped install paths
- [`06-troubleshooting.md`](./06-troubleshooting.md) — common network-side failure modes
