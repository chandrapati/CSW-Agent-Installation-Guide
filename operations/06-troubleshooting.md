# Operations — Troubleshooting Flowcharts

A symptom-first index for the patterns that recur across every
install method. Each entry points at the right next-step doc or
gives the diagnostic command directly.

---

## Symptom 1 — "Sensor installed but never appears in CSW UI"

```
Sensor installs cleanly?
  no  → check package install logs (yum / apt / msiexec verbose)
  yes ↓
Service running?
  no  → systemctl status csw-agent (Linux) / Get-Service CswAgent (Windows)
        → check journalctl -u csw-agent / Application Event Log
  yes ↓
Host can resolve cluster FQDN?
  no  → fix DNS; see operations/01-network-prereq.md
  yes ↓
Host can reach cluster on TCP/443?
  no  → firewall / proxy issue; see operations/02-proxy.md
        For air-gapped: confirm internal route to cluster
  yes ↓
TLS handshake completes?
  no  → check sensor log for cert errors
        - clock skew > 5min? fix NTP
        - CA chain missing? distribute internal CA
        - decrypting proxy? add cluster FQDN to bypass list
  yes ↓
Activation key valid?
  no  → regenerate from CSW UI; re-deploy with new key
  yes ↓
File a TAC case — atypical pattern
```

---

## Symptom 2 — "Sensor appears in CSW but reports no flows"

```
Sensor service running?
  no  → see Symptom 1
  yes ↓
Sensor type is Deep Visibility or Enforcement?
  no  → check the agent type and connector source in CSW UI
  yes ↓
Host has any actual network traffic?
  no  → run `ss -tn` (Linux) / `netstat -ano` (Windows);
        if empty, the host is genuinely idle
  yes ↓
Linux: kernel module loaded?
  no  → lsmod | grep -i tet; if empty, modprobe failed —
        check dmesg for errors
  yes ↓
Windows: WFP filters present?
  no  → netsh wfp show state; check for tetration-* filters
  yes ↓
Kubernetes: hostNetwork: true and host paths mounted?
  no  → see kubernetes/05-verification.md
  yes ↓
Wait 5 more minutes; flows are batched.
If still no flows: file a TAC case.
```

---

## Symptom 3 — "Sensor consumes too much CPU / memory"

```
Initial inventory phase (first 1-2 hours after install)?
  yes → expected; resource use will subside
  no  ↓
Sensor profile matches workload class?
  no  → in CSW UI: Manage → Agents → Configuration Profiles
        For high-flow hosts (LBs, busy NLB targets), use the
        "high-flow" profile or raise the per-flow rate cap
  yes ↓
Host's flow rate genuinely high?
  yes → expected; raise the resource limit if the host has
        headroom, or move the workload to a profile with lower
        flow capture fidelity
  no  ↓
Anomalous pattern — check sensor log for repeating errors
that imply a tight retry loop (DNS resolve, TLS handshake)
```

---

## Symptom 4 — "Sensor restarts every few minutes"

Linux:
```bash
sudo systemctl status csw-agent
sudo journalctl -u csw-agent --since "1 hour ago" | tail -100
```

Look for:

- `Out of memory` → resource limit too low for this host's flow
  rate; raise the limit
- `Killed signal SIGKILL` → systemd OOM killer; same fix
- `TLS handshake failed` repeatedly → cluster connectivity is
  flapping; check network path
- `Activation token rejected` → token expired or rotated; re-key

Windows:
```powershell
Get-WinEvent -LogName Application -MaxEvents 100 |
  Where-Object { $_.ProviderName -like '*Csw*' -or $_.ProviderName -like '*Cisco*' -or $_.Message -like '*CswAgent*' -or $_.Message -like '*Secure Workload*' } |
  Where-Object { $_.LevelDisplayName -in 'Error','Warning' }
```

---

## Symptom 5 — "Inventory tags missing or wrong"

```
Sensor registered with the right scope?
  no  → re-register with the right activation key (each key
        is bound to a scope)
  yes ↓
Tags are user-defined annotations expected to come from
inventory upload / orchestrator?
  yes → check inventory upload pipeline; verify orchestrator
        connector is healthy
  no  ↓
For cloud workloads: connector inventory in sync?
  yes → tags from cloud-side appear within 1 hour of cloud-side
        change; if stale, re-sync the connector
  no  → see agentless/0X-cloud-connector.md for the right cloud
```

---

## Symptom 6 — "Enforcement isn't taking effect on the host"

```
Sensor type is Enforcement (not Deep Visibility)?
  no  → re-install with Enforcement sensor type
  yes ↓
Host is in an enforced segment (CSW UI: scope is enforced)?
  no  → policy is published but not enforced at this scope —
        flip the scope to enforced after dry-run / monitor mode
  yes ↓
Linux: iptables / nftables rules present?
  no  → sudo iptables -L -n | head; sudo nft list ruleset
        If empty, the sensor isn't writing rules — check log
  yes ↓
Windows: WFP filters present?
  no  → netsh wfp show filters | findstr -i tetration
  yes ↓
Confirm the policy actually targets this host
(the host is in the source/dest set for the rule)
```

See also [`07-enforcement-rollout.md`](./07-enforcement-rollout.md)
for the broader enforcement design pattern.

---

## Symptom 7 — "K8s DaemonSet pod stuck in Pending"

```
Cluster has Pod Security Admission with restricted profile?
  yes → namespace needs pod-security.kubernetes.io/enforce=privileged
        kubectl label namespace tetration \
          pod-security.kubernetes.io/enforce=privileged
  no  ↓
OpenShift cluster?
  yes → privileged SCC needs to be bound to the SA
        oc adm policy add-scc-to-user privileged \
          -z <serviceaccount-from-cisco-installer> -n tetration
  no  ↓
Image pull failing?
  yes → see Symptom 8
  no  ↓
Pod scheduling failing on tainted nodes?
  yes → add tolerations: [- operator: Exists]
  no  ↓
Run `kubectl describe pod -n tetration <pod>` for events
```

---

## Symptom 8 — "K8s sensor pod ImagePullBackOff"

```
Cluster nodes can reach Cisco's published registry?
  no  → mirror image to internal registry; override
        image.repository in chart values / DaemonSet manifest
  yes ↓
imagePullSecret configured if internal registry needs auth?
  no  → kubectl create secret docker-registry internal-registry-pull \
          --docker-server=registry.internal.example.com \
          --docker-username=<user> --docker-password=<pass>
        Reference in pod spec: imagePullSecrets:
  yes ↓
Image tag actually exists in the registry?
  no  → re-mirror the right tag
  yes ↓
Run `kubectl describe pod` for the exact pull error
```

---

## When to file a TAC case

File a Cisco TAC case if:

- Sensor logs show the same error pattern repeatedly and none of
  the patterns above apply
- Sensor crashes with `SIGSEGV` / `BSOD` / kernel panic
- Cluster-side issue (the cluster admin team should escalate)
- Performance regression after a known-good upgrade

Include in the case:

- Sensor version (`tet-sensor --version`)
- OS / kernel version
- Sensor logs covering the error window
- Output of `tet-sensor --diagnostics` (if your release ships
  this command; check release notes)
- Network path diagram (workload → cluster)

---

## See also

- All install-method docs have their own "Common gotchas"
  table — check there first
- [`01-network-prereq.md`](./01-network-prereq.md)
- [`02-proxy.md`](./02-proxy.md)
- [`07-enforcement-rollout.md`](./07-enforcement-rollout.md)
