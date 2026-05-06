# Operations — Uninstall and Decommission

When you take the CSW sensor off a host, you want to leave the
host clean — service stopped and disabled, kernel hooks
unloaded, files removed, host de-registered from the cluster
inventory.

This doc covers the two flavours:

- **Decommission** — removing a host from CSW because the host
  itself is going away (server is being retired)
- **Uninstall** — removing the agent from a host that's staying
  around

---

## Linux — Uninstall

```bash
# Stop the service first so the kernel hooks unload cleanly
sudo systemctl stop csw-agent
sudo systemctl disable csw-agent

# Remove the package
# RHEL / CentOS / Oracle Linux / Amazon Linux
sudo rpm -e tet-sensor

# Ubuntu / Debian
sudo apt-get purge tet-sensor

# Confirm files are gone
ls -la /usr/local/tet/ 2>&1   # Should be "No such file or directory"
ls -la /etc/systemd/system/csw-agent.service 2>&1

# Remove any leftover config (rpm/dpkg sometimes leaves /etc bits)
sudo rm -rf /usr/local/tet/ /etc/tetration/

# Confirm the kernel module is gone
lsmod | grep -i tet     # Should return nothing
```

If the host is staying around, that's it. If the host is being
decommissioned, also de-register from CSW (next section).

---

## Windows — Uninstall

```powershell
# Stop the service
Stop-Service CswAgent
Set-Service -Name CswAgent -StartupType Disabled

# Uninstall the MSI
$product = Get-WmiObject -Class Win32_Product -Filter "Name LIKE '%Cisco Secure Workload%'"
if ($product) {
    $product.Uninstall()
}

# Or via msiexec with the product code
# msiexec /x {PRODUCT-CODE-FROM-INSTALL} /quiet /norestart

# Confirm
Get-Service -Name CswAgent 2>$null   # Should error (service gone)
Test-Path "$env:PROGRAMFILES\Cisco\Tetration"
Test-Path "$env:PROGRAMDATA\Cisco\Tetration"

# Remove leftover config (MSI sometimes leaves ProgramData)
Remove-Item -Recurse -Force "$env:PROGRAMDATA\Cisco\Tetration" -ErrorAction SilentlyContinue
```

---

## Kubernetes — Uninstall

### Helm

```bash
helm uninstall csw-sensor -n csw-sensor

# Helm leaves the namespace and Secret behind by default
kubectl delete secret csw-sensor-config -n csw-sensor
kubectl delete namespace csw-sensor
```

### Raw manifest

```bash
kubectl delete -n csw-sensor -f daemonset.yaml
kubectl delete -n csw-sensor -f rbac.yaml
kubectl delete secret csw-sensor-config -n csw-sensor
kubectl delete namespace csw-sensor
```

The DaemonSet's host-path mounts are read-only — uninstall
doesn't touch the host filesystem. Confirm by SSH'ing to a node:

```bash
ls -la /var/log/csw/ 2>&1  # Should not exist; sensor logs were inside the pod
```

---

## De-register from CSW

If you uninstall but don't de-register, the host shows up as
"Pending / Last Seen N hours ago" in CSW indefinitely.
De-registration cleans the inventory.

### From the CSW UI

1. *Manage → Agents → Software Agents*
2. Filter or search for the host
3. Select → *Decommission*

### Via CSW API

```bash
# Look up the agent UUID
curl -k -X GET \
  -H "Cookie: session_token=<token>" \
  "https://csw.example.com/openapi/v1/sensors?agent_uuid=<uuid>"

# Decommission
curl -k -X DELETE \
  -H "Cookie: session_token=<token>" \
  "https://csw.example.com/openapi/v1/sensors/<uuid>"
```

For fleet decommission (e.g., retiring a whole VLAN), bulk via
the API with a script that loops through agent UUIDs filtered
by inventory tag.

---

## Cloud / autoscaling considerations

For autoscaling groups (ASGs / VMSS / MIGs) where instances
come and go automatically:

- **Don't manually de-register** — the cluster's inventory
  reaper handles dead instances after a configurable grace
  period (default 24h)
- **Confirm the reaper is enabled** in *Manage → Agents → Settings*
- **For ephemeral patterns where you want immediate cleanup**:
  add a shutdown hook in the instance lifecycle that calls the
  CSW DELETE API before the instance terminates

```bash
# Example shutdown hook (add to systemd in the AMI)
cat > /etc/systemd/system/csw-decommission.service <<'EOF'
[Unit]
Description=Decommission CSW sensor on shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/csw-decommission.sh

[Install]
WantedBy=halt.target reboot.target shutdown.target
EOF

cat > /usr/local/bin/csw-decommission.sh <<'EOF'
#!/bin/bash
UUID=$(cat /usr/local/tet/agent_uuid 2>/dev/null)
[ -z "$UUID" ] && exit 0
curl -sk -X DELETE \
  -H "X-Tetration-Sensor-Token: $(cat /usr/local/tet/api_token)" \
  "https://csw.example.com/openapi/v1/sensors/${UUID}"
EOF
chmod +x /usr/local/bin/csw-decommission.sh
systemctl enable csw-decommission.service
```

(For ASG patterns, the lifecycle hook on the ASG itself is
usually a cleaner approach than a host-side shutdown handler.)

---

## Verification

- *Manage → Agents → Software Agents → filter by hostname*: the
  host should be absent (decommissioned) or in
  "Decommissioned / Last Seen" state
- *Investigate → Flows → filter by the host's last known IP*:
  no new flows after the uninstall window
- The kernel module is unloaded on the host (`lsmod | grep -i
  tet` returns nothing)

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Service won't stop ("active (deactivating)") | In-flight telemetry buffer flush | Wait 30s; if still stuck, `systemctl kill -s SIGKILL csw-agent` |
| Package removed but service still listed | systemd cache | `systemctl daemon-reload` |
| Kernel module still loaded after uninstall | Active connections still using the module | Reboot the host or `rmmod` after closing connections |
| Host shows up as "Pending" in CSW for days | Uninstall but not decommissioned | Decommission via UI or API |
| Decommissioned host re-appears | Sensor wasn't actually uninstalled; re-registered on its next heartbeat | Confirm `csw-agent` is gone on the host first, then decommission again |
| Helm uninstall leaves the namespace | Default Helm behaviour | Explicit `kubectl delete namespace csw-sensor` |

---

## See also

- [`04-upgrade.md`](./04-upgrade.md)
- [`06-troubleshooting.md`](./06-troubleshooting.md)
- [`08-evidence-audit.md`](./08-evidence-audit.md) — useful when a decommission is in scope of an audit
