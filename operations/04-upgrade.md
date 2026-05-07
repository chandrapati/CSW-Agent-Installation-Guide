# Operations — Upgrade Workflow

The CSW sensor releases on a regular cadence (typically every
few weeks). Cluster upgrades are coordinated with your CSW admin
team; sensor upgrades are driven from your side and follow the
same patching pipelines you already operate.

---

## Compatibility window

The cluster supports a wide N-1 / N-2 sensor version window
(check the matrix for your release). You don't need to be on
the latest sensor on day one; you do need to clear major
version drift within a quarter or so to stay in support.

| Cluster version | Sensor versions accepted |
|---|---|
| Current | Current and last 2–3 majors (typical) |
| N-1 | Same |
| N-2 | Same |

The CSW UI's *Manage → Agents → Versions* page shows the
current spread across your fleet.

---

## Upgrade triggers

| Trigger | Cadence | Notes |
|---|---|---|
| Routine release | Quarterly is a common operational cadence | Bundles bug fixes + small feature improvements |
| Security advisory | As needed | Cisco PSIRT will publish advisories; treat per your normal CVE response SLA |
| Cluster upgrade requires a sensor floor | When CSW admin team coordinates | Cluster team will tell you the new floor; plan sensor catch-up before the cluster cut |
| New feature you need (e.g., new enforcement mode) | When you need it | Pilot the new sensor on one cluster before fleet-wide |

---

## Upgrade workflow per install method

| Install method | Upgrade path |
|---|---|
| Manual RPM/DEB | Re-run `rpm -Uvh` / `dpkg -i` with the new package on a per-host wave |
| CSW-generated script | Re-run the install script — it detects the existing install and upgrades in place |
| Internal package repo | Push new version to repo; workloads pick it up on next patch cycle |
| Ansible / Puppet / Chef / Salt | Update the version pin in the playbook / manifest / recipe; re-run on a per-host wave |
| SCCM / Intune | Use *supersedence* on the application; SCCM rolls out the new version to its waves |
| GPO startup script | Update `$msi` path on the central share; users pick up at next reboot (slow — prefer SCCM / Intune for fleet upgrades) |
| AWS user_data | Update the package version in your S3 / SSM payload; use rolling instance replacement on the ASG |
| Azure custom_data | Same pattern; rolling VMSS instance replacement |
| GCP startup-script | Same pattern; managed instance group rolling update |
| Golden AMI / Compute Gallery / GCE custom image | Bake new image; roll out via standard image-update pipeline |
| Helm DaemonSet | `helm upgrade` with new chart / image version; DaemonSet rolling update handles the rest |
| Raw DaemonSet manifest | Update `image:` tag; `kubectl apply`; rolling update |

In every case, the **CSW UI's *Manage → Agents → Versions***
page is your source of truth for catch-up progress across the
fleet.

---

## Wave-based rollout

Same shape as the initial install rollout
([`../docs/04-rollout-strategy.md`](../docs/04-rollout-strategy.md)):

| Wave | Duration | Exit criteria |
|---|---|---|
| Lab | 1–3 days | New sensor registers; no error logs; flow data continues |
| Stage | 3–7 days | Same; plus no inventory drift; no policy events |
| Prod canary | 1 week | Same; plus operational stability under real load |
| Prod rest | 2–4 weeks (paced) | Catch-up reaches >95% of fleet on the new version |

For routine upgrades the lab + stage waves can be very short.
For a sensor with a major-version bump, treat it like a fresh
install — the slower waves catch regressions early.

---

## During the upgrade

### What happens to telemetry

- The sensor restart is brief (seconds, not minutes)
- During restart, in-flight flows are not captured; the sensor
  resumes capture as soon as it's back up
- For enforcement-mode hosts, the host firewall rules persist
  across the sensor restart — there's no enforcement gap

### What happens to existing host policy

- The host's enforced policy is held in the kernel firewall;
  the sensor restart doesn't drop it
- If the new sensor has a policy schema bump, it converges to
  the new schema on first heartbeat post-restart
- No new policy is pushed during the restart window

### Rollback plan

- Keep the previous sensor package on the artefact path so a
  rollback is just an `rpm -Uvh --oldpackage` (or equivalent)
  away
- For golden-image patterns: keep the previous AMI / VHD / GCE
  image on the path until the new image has burned in for a
  week
- For Helm: `helm rollback csw-agent <previous-revision>`

---

## Post-upgrade verification

```bash
# Linux
sudo /usr/local/tet/tet-sensor --version
sudo systemctl status csw-agent
sudo journalctl -u csw-agent --since "10 minutes ago" | grep -E "(ERROR|FATAL)"
```

```powershell
# Windows
Get-WmiObject -Class Win32_Product `
  -Filter "Name like '%Cisco Secure Workload%' OR Name like '%Tetration%'" |
  Select-Object Name, Version
Get-Service -Name CswAgent -ErrorAction SilentlyContinue
Get-WinEvent -LogName Application -MaxEvents 50 |
  Where-Object { $_.ProviderName -like '*Csw*' -or $_.ProviderName -like '*Cisco*' -or $_.Message -like '*CswAgent*' -or $_.Message -like '*Secure Workload*' }
```

In CSW UI:

- *Manage → Agents → click a host*: version should match the
  new release
- *Investigate → Flows → filter by the host*: flow data should
  continue without gap

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Upgrade succeeds but agent shows as "old version" in UI | Cached version in CSW; ride out the next heartbeat | Wait 5 minutes; if persistent, restart the sensor service |
| Upgrade fails with "package conflicts with running service" | Some Linux distros don't auto-stop the service on `rpm -Uvh` | `systemctl stop csw-agent && rpm -Uvh && systemctl start csw-agent` |
| GPO upgrade pattern doesn't catch laptops that weren't online | GPO startup script only runs at boot | Move to SCCM / Intune for fleet upgrades |
| Helm upgrade triggers all nodes' sensors to restart at once | DaemonSet `maxUnavailable` not set | Set `maxUnavailable: 1` in the DaemonSet update strategy |
| New sensor version logs noisy warnings about deprecated config | Config schema bumped | Re-render `sensor.conf` from latest template; restart |

---

## See also

- [`../docs/04-rollout-strategy.md`](../docs/04-rollout-strategy.md)
- [`05-uninstall.md`](./05-uninstall.md)
- [`06-troubleshooting.md`](./06-troubleshooting.md)
