# Operations — Audit Evidence and Reporting

CSW deployments routinely sit in scope for compliance audits.
This doc covers the evidence the agent install (and the broader
CSW deployment) produces, where it lives, and how to package it
for an auditor.

---

## What auditors typically ask for

In our experience the recurring questions across PCI, HIPAA,
SOC 2, ISO 27001, NIS2, DORA, and the US-sector frameworks
(NERC-CIP, TSA Pipeline, etc.) sort into five buckets:

1. **Coverage.** Of all in-scope workloads, how many have a
   working CSW agent?
2. **Posture.** What policy is enforced on those workloads, and
   when did it last change?
3. **Drift.** What's the gap between intended state and actual
   state, today?
4. **Detection.** What did CSW detect, and what was done?
5. **Lifecycle.** How are agents deployed, patched, and
   decommissioned?

Map each evidence artefact below to one or more of those
buckets so it's easy to assemble a per-control evidence binder.

---

## Bucket 1 — Coverage evidence

| Artefact | Source | Format | Refresh cadence |
|---|---|---|---|
| Agent inventory by scope | CSW UI: *Manage → Agents → Software Agents* (filter by scope) | CSV export | Live |
| Agent vs. cloud-connector reconciliation report | Internal report from CSW data via OpenAPI | CSV / PDF | Monthly |
| Coverage by application (using inventory tags) | CSW UI: *Organize → Inventory → Filter by app* | CSV | Live |
| Per-host install confirmation log | Your config-management tool's run history (Ansible AWX, Puppet PE, Chef Automate, Salt log) | Text / JSON | Per change |

Sample auditor-friendly coverage statement:

> *"As of 2026-04-30, 4,712 of 4,738 in-scope workloads have an
> active CSW Deep Visibility agent (99.5% coverage). The 26
> uninstrumented hosts are documented in the exception register
> (link), with compensating controls."*

---

## Bucket 2 — Posture evidence

| Artefact | Source | Format | Refresh cadence |
|---|---|---|---|
| Per-scope enforced policy (rule list) | CSW UI: *Defend → Workspace → Enforced Policy* | CSV / JSON | Live |
| Workspace change log (who changed what, when) | CSW UI: *Defend → Workspace → Change Log* | Built-in | Live |
| Policy approval evidence | Your change-management tool (ServiceNow, Jira, etc.) | Per ticket | Per change |
| Compliance-framework mapping (CSW capabilities → controls) | [`CSW-Compliance-Mapping`](https://github.com/chandrapati/CSW-Compliance-Mapping) repo | Markdown / DOCX / PDF / HTML | Per release |

The compliance-mapping repo specifically provides the
control-by-control "what CSW does for this control" evidence
auditors increasingly ask for.

---

## Bucket 3 — Drift evidence

| Artefact | Source | Format | Refresh cadence |
|---|---|---|---|
| Agent version drift across the fleet | CSW UI: *Manage → Agents → Versions* | Built-in | Live |
| Workloads in scope but uninstrumented (shadow workload report) | CSW UI: *Organize → Inventory → reconciliation view* | CSV | Weekly |
| Policy drift (intended vs. enforced) | CSW UI: *Defend → Workspace → Policy Analysis* | CSV | Live |
| Inventory tag drift (workloads where tags don't match the orchestrator) | CSW UI inventory + your CMDB | CSV | Weekly |

The drift evidence is the one auditors increasingly insist on.
"Show me the gap between policy-on-paper and policy-on-host" is
a common SOC 2 / ISO 27001 question.

---

## Bucket 4 — Detection evidence

| Artefact | Source | Format | Refresh cadence |
|---|---|---|---|
| Per-policy denies | CSW UI: *Investigate → Policy Events* | CSV | Live |
| Forensic flow data | CSW UI: *Investigate → Flows* | CSV / JSON via OpenAPI | Live |
| Per-host CVE list | CSW UI: *Defend → Vulnerabilities* | CSV | Daily |
| Anomaly / behaviour alerts | CSW UI: *Investigate → Alerts* | CSV / SIEM forwarding | Live |
| SIEM forwarding receipts | Your SIEM | Per integration | Live |

For audits, the *Investigate → Policy Events* export combined
with the *Vulnerabilities* export is usually enough for the
"detection" bucket.

---

## Bucket 5 — Lifecycle evidence

| Artefact | Source | Format | Refresh cadence |
|---|---|---|---|
| Agent install runbook | This repo | Markdown | Per release |
| Per-host install log | Config-management tool history | Text / JSON | Per change |
| Patching cadence policy | Internal SecOps doc | Markdown / PDF | Annual |
| Decommission log | CSW UI: *Manage → Agents → Decommissioned* + change tickets | Built-in + per ticket | Live |
| Change-management ticket history | Your CMDB / ticketing | Per ticket | Live |

This bucket is the easiest to assemble (everything is in tools
auditors already trust) but the easiest to skip — make sure the
runbook reference is in the binder.

---

## Putting it together — annual audit binder template

A workable per-scope binder structure:

```
/audit-binder-2026-Q2/
├── 00-summary.md                      # one page, exec-friendly
├── 01-coverage/
│   ├── agent-inventory-2026-04-30.csv
│   ├── coverage-by-app.csv
│   └── exception-register.md
├── 02-posture/
│   ├── enforced-policy-per-scope.json
│   ├── workspace-change-log-2025-Q4-to-2026-Q2.csv
│   ├── change-tickets/
│   │   ├── CHG-2026-001234.pdf
│   │   └── ...
│   └── compliance-mapping/            # from CSW-Compliance-Mapping repo
├── 03-drift/
│   ├── agent-version-drift-2026-04-30.csv
│   ├── shadow-workload-report-2026-04-30.csv
│   └── policy-drift-2026-04-30.csv
├── 04-detection/
│   ├── policy-events-2026-Q1.csv
│   ├── vulnerabilities-2026-04-30.csv
│   └── alerts-2026-Q1.csv
├── 05-lifecycle/
│   ├── install-runbook-snapshot/      # this repo at a known commit
│   ├── ansible-run-history-2026-Q1.json
│   └── patching-policy-2026.md
└── 06-evidence-of-control-operation/
    ├── monthly-review-meeting-notes/
    └── quarterly-attestation-2026-Q1.pdf
```

The exact mapping from artefacts to controls depends on the
framework. The
[`CSW-Compliance-Mapping`](https://github.com/chandrapati/CSW-Compliance-Mapping)
repo's per-framework runbooks tell you which artefacts cover
which controls (PCI 1.x, HIPAA §164.312, NIST CSF PR.AC, etc.).

---

## Automation pointers

Most of the data above is queryable via the CSW OpenAPI:

```python
# Pseudo-code; actual endpoints vary by release
from tetpyclient import RestClient

client = RestClient("https://csw.example.com",
                    api_key="<key>", api_secret="<secret>",
                    verify=True)

# Coverage
agents = client.get("/openapi/v1/sensors").json()

# Per-scope enforced policy
scopes = client.get("/openapi/v1/app_scopes").json()
for s in scopes:
    policy = client.get(f"/openapi/v1/policies?scope_id={s['id']}").json()
    # ... export to CSV ...

# Vulnerabilities
vulns = client.get("/openapi/v1/vulnerabilities").json()

# Policy events
events = client.get("/openapi/v1/policy_events").json()
```

The companion
[`CSW-Tenant-Insights`](https://github.com/chandrapati/CSW-Tenant-Insights)
repo has working examples — including the executive-report
generators that wrap a lot of this logic.

---

## See also

- [`CSW-Compliance-Mapping`](https://github.com/chandrapati/CSW-Compliance-Mapping) — control-by-control mappings
- [`CSW-Tenant-Insights`](https://github.com/chandrapati/CSW-Tenant-Insights) — executive reporting
- [`07-enforcement-rollout.md`](./07-enforcement-rollout.md) — posture evidence ties closely to the enforcement workflow
- [`05-uninstall.md`](./05-uninstall.md) — decommission evidence
