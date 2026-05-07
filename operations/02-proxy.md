# Operations — Proxy and NAT Environments

The sensor supports HTTPS forward proxies. This doc is the
practitioner walkthrough — what the supported proxy modes are,
how to configure them per OS, and the patterns that catch teams
out.

---

## Supported modes

- **HTTP CONNECT proxy** — standard forward proxy that tunnels
  the sensor's TLS session through. The proxy sees only the
  TLS hostname (SNI), not the contents.
- **PAC (Proxy Auto-Configuration) file** — current sensor
  releases support PAC-driven proxy selection. Use only if
  your estate already runs on PAC.
- **Authenticating proxy (Basic / NTLM)** — supported with
  caveats; see "Authenticating proxies" below.

NOT supported (or strongly discouraged):

- **TLS-decrypting proxies** — the sensor uses mTLS with a
  per-host client cert; a decrypting proxy that re-signs the
  cluster cert breaks mTLS. If your proxy decrypts by default,
  add the CSW cluster FQDN to its bypass list.
- **SOCKS proxies** — not supported.

---

## Linux configuration

Use Cisco-documented installer options for proxy configuration.
For CSW 4.0 Linux installs, the generated installer documents
`--proxy=<proxy_string>` and `--no-proxy`; use the script's
`--help` output for your release.

### At install time — CSW-generated script

The script honours `HTTPS_PROXY` from the environment if set
before the script runs:

```bash
sudo ./tetration_linux_installer.sh --proxy=http://proxy.internal.example.com:8080
```

You can also use `--no-proxy` to force direct egress when needed.

### On an already-installed agent

```bash
sudo systemctl stop csw-agent

sudo tee /usr/local/tet/conf/proxy.conf >/dev/null <<EOF
HTTPS_PROXY_HOST=proxy.internal.example.com
HTTPS_PROXY_PORT=8080
EOF

sudo systemctl start csw-agent

# Confirm
sudo journalctl -u csw-agent --since "5 minutes ago" | grep -i proxy
```

### Bypass list (non-proxied destinations)

If the sensor needs to reach NTP, DNS, or anything else without
the proxy, set:

```bash
NO_PROXY_LIST=127.0.0.1,localhost,.internal.example.com
```

in the same `proxy.conf`.

---

## Windows configuration

For CSW 4.0 Windows agents, prefer the Cisco-documented installer
parameters (`proxy=""` for MSI or `-proxy <ProxyString>` for the
PowerShell installer). If you must change proxy settings after
install, confirm the file / registry location with your release's
Cisco guide or TAC before editing it manually.

```powershell
# Stop the service
Stop-Service CswAgent

# Write the proxy config
$cfg = @"
HTTPS_PROXY_HOST=proxy.internal.example.com
HTTPS_PROXY_PORT=8080
"@
Set-Content -Path "$env:PROGRAMDATA\Cisco\Tetration\proxy.conf" -Value $cfg

# Start the service
Start-Service CswAgent

# Confirm
Get-WinEvent -LogName Application -MaxEvents 50 |
  Where-Object { $_.Message -match 'proxy' }
```

For MSI silent installs you can pass proxy as a property:

```powershell
# Replace <installer.msi> with the exact filename from your CSW UI
# or extracted Agent Image Installer package.
msiexec /i <installer.msi> /quiet `
  proxy="http://proxy.internal.example.com:8080"
```

---

## Cloud workloads

For VMs deployed via cloud-init / `user_data` / `custom_data`,
set the proxy env var at the top of the script before downloading
the agent payload. See examples:

- [`../cloud/examples/cloud-init/aws-csw-rhel9.sh`](../cloud/examples/cloud-init/aws-csw-rhel9.sh)
- [`../cloud/examples/cloud-init/azure-csw-rhel9.yaml`](../cloud/examples/cloud-init/azure-csw-rhel9.yaml)
- [`../cloud/examples/cloud-init/gcp-csw-rhel9.sh`](../cloud/examples/cloud-init/gcp-csw-rhel9.sh)

For Kubernetes, the proxy env vars go into the DaemonSet's
container env:

```yaml
env:
  - name: HTTPS_PROXY
    value: http://proxy.internal.example.com:8080
  - name: NO_PROXY
    value: 127.0.0.1,localhost,.internal.example.com
```

For Helm, set the same values via the chart's `extraEnv:` block
(actual key name depends on chart version).

---

## Authenticating proxies

| Auth scheme | Supported? | Notes |
|---|---|---|
| Basic auth in URL (`http://user:pass@proxy:8080`) | yes | Strongly discouraged — the password lands in `proxy.conf` in plain text and tends to leak into logs |
| NTLM | yes (current releases) | Configure with separate `HTTPS_PROXY_USER` / `HTTPS_PROXY_PASS` keys; cross-check release docs for the field names |
| Kerberos | partial | Supported on hosts already in the AD domain; requires `kinit` keytab and additional config |
| OAuth / token-based | not supported | If your proxy requires OAuth, deploy a non-authenticating proxy in front of the sensor segment |

If you're stuck behind an authenticating proxy and the user/pass
pattern feels brittle, the cleanest solution is usually to deploy
a small **transparent egress** for the sensor segment that
shoulders auth on its behalf — saves credential rotation pain.

---

## TLS-decrypting proxies (the failure mode)

If your estate's proxy decrypts and re-signs HTTPS traffic by
default, the CSW sensor will fail mTLS. Symptoms:

- Sensor installs and starts cleanly
- TLS handshake to the cluster completes
- Registration fails because the per-host client cert isn't
  what the cluster expects
- Sensor log shows `TLS handshake failed: bad certificate` or
  similar

Fix: add the CSW cluster FQDN to the proxy's bypass list. Most
enterprise proxy products have a "do not decrypt" list precisely
for this kind of mTLS-bound traffic.

---

## Verification

```bash
# Linux
sudo journalctl -u csw-agent --since "10 minutes ago" | grep -E "(proxy|cluster)"

# Windows
Get-WinEvent -LogName Application -MaxEvents 100 |
  Where-Object { $_.Message -match 'proxy|cluster' }
```

In the CSW UI: the host should appear as registered within
2 minutes. If the proxy is misconfigured, the host stays in
"Pending" state.

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Sensor logs show `proxy CONNECT failed: 407` | Authenticating proxy rejected the request | Provide credentials via `HTTPS_PROXY_USER` / `HTTPS_PROXY_PASS` |
| Sensor TLS handshake fails right after CONNECT succeeds | TLS-decrypting proxy is re-signing | Add cluster FQDN to proxy bypass list |
| Sensor registers but inventory updates are slow / missing | Proxy is rate-limiting the sensor's HTTP/2 multiplex | Raise the rate limit for the sensor segment, or whitelist the cluster FQDN from rate limiting |
| Works for IPv4 but fails for IPv6 | Proxy doesn't bind on the host's IPv6 interface | Either resolve the cluster FQDN as IPv4-only on these hosts, or fix the proxy's IPv6 listener |
| Proxy works at install but breaks after host reboot | Env var was set in interactive shell, not persisted into systemd unit | Use `proxy.conf` rather than env var |

---

## See also

- [`01-network-prereq.md`](./01-network-prereq.md)
- [`03-air-gapped.md`](./03-air-gapped.md)
- [`06-troubleshooting.md`](./06-troubleshooting.md)
