# Windows — Microsoft Intune

For cloud-managed Windows estates (Azure AD-joined, Intune
enrolled). Package the CSW MSI as a Win32 app, define a detection
rule that watches the `TetSensor` service, deploy as Required to
the device group. Optionally add a custom compliance setting that
flags devices where the agent isn't running.

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- Intune (Microsoft Endpoint Manager) tenant with rights to
  publish Win32 apps and define compliance policies
- The CSW MSI (`TetrationAgentInstaller-3.x.y.z-x64.msi`)
  downloaded from the CSW UI for your target scope and sensor type
- Windows 10/11 or Windows Server devices enrolled into Intune
  (Azure AD joined or hybrid joined)
- Microsoft's `IntuneWinAppUtil.exe` packaging tool
  ([download from Microsoft](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-prepare))

---

## Step 1 — Wrap the MSI as a `.intunewin` package

Intune Win32 apps are deployed as `.intunewin` archives (a
proprietary container that wraps the actual installer). Build one:

```cmd
:: Stage the source folder
mkdir C:\temp\csw-intune-src
copy TetrationAgentInstaller-3.x.y.z-x64.msi C:\temp\csw-intune-src\

:: Wrap
IntuneWinAppUtil.exe ^
  -c C:\temp\csw-intune-src ^
  -s TetrationAgentInstaller-3.x.y.z-x64.msi ^
  -o C:\temp\csw-intune-out

:: Output: C:\temp\csw-intune-out\TetrationAgentInstaller-3.x.y.z-x64.intunewin
```

---

## Step 2 — Create the Win32 app in Intune

In the Intune admin centre:

1. *Apps → Windows → Add → Windows app (Win32)*
2. **App information** — upload the `.intunewin`; fill in:
   - Name: *Cisco Secure Workload Sensor 3.x.y.z*
   - Publisher: *Cisco Systems*
   - Description: clear summary; link to internal runbook
   - Version: `3.x.y.z` (Intune doesn't auto-detect from MSI)
3. **Program**:
   - Install command:
     ```
     msiexec /i "TetrationAgentInstaller-3.x.y.z-x64.msi" /quiet /norestart /L*v "%TEMP%\tetsensor-install.log"
     ```
   - Uninstall command: pre-fill from MSI ProductCode (Intune
     auto-fills if you used the MSI properties extracted from the
     `.intunewin`). Or:
     ```
     msiexec /x {MSI-PRODUCT-CODE-GUID} /quiet /norestart
     ```
   - Install behaviour: *System* (the agent installs system-wide)
   - Device restart behaviour: *No specific action* (CSW agent
     does not require a reboot)
4. **Requirements**:
   - Operating system architecture: *64-bit*
   - Minimum operating system: *Windows Server 2016* or your
     fleet's minimum
   - Disk space free: 1 GB (a buffer)
   - Optional: a custom requirement script (`Test-Path
     C:\Windows\System32\drivers\<filter-driver>.sys`) to skip
     hosts where the platform team has explicitly blocked third-
     party drivers
5. **Detection rules** — this is the critical step. Choose
   *Use a custom detection script*; supply the script in
   [`./examples/intune/detection-tetsensor.ps1`](./examples/intune/detection-tetsensor.ps1):

   ```powershell
   # Returns Compliant only when TetSensor service is Running.
   # Intune reads STDOUT and a 0 exit code as "detected".
   $svc = Get-Service -Name TetSensor -ErrorAction SilentlyContinue
   if ($null -eq $svc) {
       exit 1
   }
   if ($svc.Status -ne 'Running') {
       exit 1
   }
   Write-Output "Cisco Secure Workload sensor present and running"
   exit 0
   ```

   Set: *Run script as 32-bit process on 64-bit clients = No*;
   *Enforce script signature check = No* (or sign the script).

6. **Dependencies / Supersedence**:
   - Dependencies: typically none
   - Supersedence: when you publish v3.x.y+1.z, supersede this
     app and choose *Uninstall the previous app* per your org's
     preference
7. **Assignments**:
   - Required for the device group of in-scope hosts
   - Available (optional): a self-service version for opt-in
     pilots
   - Uninstall: a separate group used to clean up specific hosts
8. **Review + create**

---

## Step 3 — Add a Compliance setting (optional but recommended)

Intune **Compliance Policies** can mark a device non-compliant if
the agent isn't running. Conditional Access can then react.

1. *Devices → Compliance policies → Create policy* → Windows 10
   and later
2. Add a *Custom Compliance* setting (requires the *Compliance
   Settings (Custom)* preview/GA feature in your tenant)
3. Provide:
   - A **discovery script** (PowerShell) — returns a JSON object
     with one or more named values:

     ```powershell
     $svc = Get-Service -Name TetSensor -ErrorAction SilentlyContinue
     $running = ($svc -ne $null) -and ($svc.Status -eq 'Running')
     # Output a single JSON object
     @{ TetSensorRunning = if ($running) { "true" } else { "false" } } |
       ConvertTo-Json -Compress
     ```

   - A **JSON rule file** that asserts `TetSensorRunning == "true"`:

     ```json
     {
       "Rules": [
         {
           "SettingName": "TetSensorRunning",
           "Operator": "IsEquals",
           "DataType": "String",
           "Operand": "true",
           "MoreInfoUrl": "https://internal-wiki/CSW-agent-troubleshooting",
           "RemediationStrings": [
             {
               "Language": "en_US",
               "Title": "Cisco Secure Workload sensor is not running",
               "Description": "Open a ticket with the security team referencing this device's name."
             }
           ]
         }
       ]
     }
     ```

4. Assign to the same device group as the Win32 app.

When the agent is healthy, the device is compliant. When it isn't,
the device is non-compliant and (if Conditional Access is wired
up) loses access to corporate resources until the agent is
remediated.

---

## Step 4 — Wave-based rollout via Azure AD groups

Standard Intune pattern for safe production rollout: assign the
Required deployment to **dynamic** or **assigned** Azure AD groups
that represent waves. Examples:

| Wave | Group | Group rule |
|---|---|---|
| Lab | *CSW Sensor — Lab* | Manual list of test devices |
| Stage | *CSW Sensor — Stage* | `device.deviceCategory -eq "Stage"` |
| Prod canary | *CSW Sensor — Prod Canary* | Manual list of 10 prod hosts |
| Prod | *CSW Sensor — Prod* | All servers in the corp tenant minus the above |

Move the assignment from *Available* (opt-in) to *Required*
(enforced) as you advance from canary to general rollout.

---

## Step 5 — Day-2 patching cadence (CSW agent upgrades)

1. Wrap the new MSI version into a new `.intunewin`
2. Create a new Win32 app *Cisco Secure Workload Sensor 3.x.y+1.z*
3. Add a **Supersedence** rule: new app supersedes the previous
   version
4. Assign the new app to the same wave groups
5. Older app is automatically uninstalled (or upgrade-in-place,
   depending on your supersedence settings)

The detection script and compliance policy are version-agnostic
and continue to report correctly through upgrades.

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| App stays "Pending" forever in Intune monitoring | Device hasn't synced with Intune since assignment | Force sync: Settings → Accounts → Access work or school → Sync; or Intune *Sync* action on the device record |
| Install completes but detection says "not detected" | Service not in Running state at detection time (race condition) | Detection script already returns 1 if service is missing or not running; Intune retries on next sync. If persistent, increase install grace period |
| Compliance setting shows non-compliant immediately after install | Compliance evaluation runs before Win32 app installation completes | Compliance evaluation happens on its own schedule; expect resolution within an hour |
| MSI installs but agent never registers | Activation key issue or network egress | Verify outbound 443 to cluster from the device; verify activation key in CSW UI; reinstall via Intune *Reinstall* action |
| "0x87D300C9" — required app installation failed | Intune-specific error code; root cause varies | Pull the IME log: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` |

Full troubleshooting in
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

---

## When this is the right method

- **Cloud-managed Windows fleets** (Azure AD joined, Intune
  enrolled). The native pattern.
- **Hybrid fleets** where SCCM and Intune coexist; use Intune for
  cloud-only devices, SCCM for AD-joined.
- **Modern endpoint management strategy** that wants compliance
  signals feeding Conditional Access.

## When this is NOT the right method

- **Devices not enrolled in Intune.** GPO ([05](./05-group-policy.md))
  or SCCM is the path.
- **AD-joined fleets where SCCM is already the standard.** Don't
  fragment your Windows endpoint management; stick with SCCM
  ([03](./03-sccm-deployment.md)).

---

## See also

- [`./examples/intune/detection-tetsensor.ps1`](./examples/intune/detection-tetsensor.ps1) — runnable detection script
- [`01-msi-silent-install.md`](./01-msi-silent-install.md) — what the MSI does on a single host
- [`03-sccm-deployment.md`](./03-sccm-deployment.md) — on-prem alternative
- [`05-group-policy.md`](./05-group-policy.md)
- [`06-verification.md`](./06-verification.md)
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md)
