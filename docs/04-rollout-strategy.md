# Rollout Strategy — Monitor → Simulate → Enforce

The single biggest predictor of a healthy CSW deployment is
whether the team takes the **phased rollout** seriously. The
single biggest cause of "CSW broke production" stories is going
straight from "agent installed" to "Enforce mode on, allow-list
authored from one week of data". This doc is the guard-rail.

> See also [`../operations/07-enforcement-mode-rollout.md`](../operations/07-enforcement-mode-rollout.md)
> for the operational playbook (the per-scope steps, simulation log
> review checklist, and roll-back procedure). This doc covers the
> *strategy* — why the phases exist and what to verify between them.

---

## The three phases

### Phase 1 — Monitor (Deep Visibility only)

**Duration.** 30 days minimum for non-seasonal workloads. 60–90
days for workloads with monthly / quarterly cycles (financial
close, EOY, billing runs, scheduled batch jobs).

**Agent state.** Deep Visibility installed and registered. **No
enforcement enabled.** The workload's existing firewall is
unchanged; CSW is observing only.

**What to do during this phase:**

1. **Achieve sensor coverage.** Walk the inventory; reconcile
   against your CMDB or cloud asset list. Hosts without a sensor
   are blind spots in everything that follows. Aim for ≥95 %
   sensor coverage of the in-scope estate before moving on.
2. **Apply scope labels.** Every workload needs labels for
   `business_function`, `environment`, `data_class`, and any
   compliance scope tags (`pci_in_scope`, `cui_scope`, `csf_tier`,
   etc.). Labels are how policy reasons about the estate; without
   them, any policy you author is brittle.
3. **Run ADM (Application Dependency Mapping).** Let CSW observe
   for 14+ days, then run ADM per scope. The output is the
   evidence-based model of "who actually talks to whom" — the
   foundation for the policy you'll author in Phase 2.
4. **Review the workload software inventory and CVE backlog.**
   Phase 1 isn't only about flows — the per-workload package
   inventory and CVE list are valuable on their own and surface
   patching priorities the team can act on immediately.
5. **Check sensor health weekly.** Are all sensors registered?
   Are any reporting "degraded" or "kernel mismatch" status? The
   sensor-health view in CSW *Manage → Agents* is the source of
   truth.

**Exit criteria for Phase 1:**
- ≥95 % sensor coverage of the in-scope estate
- Scope labels applied to all in-scope workloads
- ADM run completed; clusters reviewed and renamed by application
  owners
- 30+ days of flow data captured (or longer for cyclical workloads)

---

### Phase 2 — Simulate

**Duration.** 14–30 days minimum.

**Agent state.** Deep Visibility still on. The agent **profile**
is still in Monitor mode (no enforcement). The change in this
phase is in the **CSW workspace**, not the agent: you author the
intended policy, then run the workspace in **Simulation** to see
what the policy *would have done* if it were enforcing.

**What to do during this phase:**

1. **Author the policy in a workspace.** Build it from the ADM
   clusters you reviewed in Phase 1. Default deny inbound; allow
   only what ADM observed plus what business owners explicitly
   add (scheduled batch jobs, DR failover paths, partner ingress).
2. **Run the workspace in Simulation.** CSW shows, per flow, what
   the *running* (current actual) traffic was and what the
   *simulated* (would-have-been-blocked) traffic would be.
3. **Drain the simulation log.** Every "would have been blocked"
   flow is one of three things:
   - A legitimate flow that ADM missed (rare but real). **Fix the
     policy** to include it, then re-simulate.
   - An undocumented but legitimate flow (more common). **Confirm
     with the application owner**, then update the policy.
   - A genuinely unwanted flow. **Leave it**; the policy is right.
   The job in this phase is to drive the count of category-1 and
   category-2 to zero. When the simulation log only shows category-3
   for an operational cycle (typically 14 days minimum), the policy
   is ready to enforce.
4. **Pre-stage roll-back.** Before promoting to Enforce, document
   exactly how to revert: which workspace toggle, which agent
   profile reset. The team should rehearse this once before going
   live.

**Exit criteria for Phase 2:**
- Policy authored from ADM + business-owner additions
- Simulation log showing only category-3 (genuinely unwanted) flows
  for ≥14 days
- Roll-back path documented and rehearsed
- Sign-off from the application owner(s) for the in-scope workloads

---

### Phase 3 — Enforce

**Duration.** Ongoing. This is steady state.

**Agent state.** Agent **profile** changed to enable Enforcement.
The agent now applies the workspace policy at the workload kernel.
Telemetry continues; policy violations are now blocks, not just
log entries.

**What to do during this phase:**

1. **Promote one workload first.** Pick a low-risk workload from
   the scope (a non-tier-0 service); promote it to Enforcement;
   monitor for 24 hours. If anything is wrong, the blast radius is
   one host.
2. **Promote in waves.** Move from one workload to a small batch
   (2–5 hosts), then to the rest of the scope as confidence grows.
   Each wave should run cleanly for at least one operational cycle
   before the next wave.
3. **Watch for policy drift.** As the application changes (new
   services, new dependencies, new partners), the policy must
   change with it. Schedule a **quarterly policy review** that
   re-runs ADM, diffs against the current policy, and reconciles.
4. **Standing change-management hookup.** Any new flow added to
   the policy must come with a change ticket; any flow removed
   needs the same. CSW workspace history is the audit trail; tie
   each change to your ticketing system reference number in the
   workspace notes.

**There is no exit criterion** — this is steady state. The
workspace lives forever; periodically re-baseline.

---

## Pacing guidance per environment

Different environments tolerate different pacing. Use this as a
starting point, not a hard rule:

| Environment | Phase 1 (Monitor) | Phase 2 (Simulate) | Phase 3 (Enforce) wave size |
|---|---|---|---|
| Lab / non-prod | 7 days | 7 days | All hosts at once |
| Stage | 14 days | 14 days | Half the hosts, then the rest |
| Production, low-risk service | 30 days | 14 days | One host, then 5, then 25 % per week |
| Production, tier-0 service | 60 days | 30 days | One host, then 2, then 10 % per week |
| Production, regulated scope (PCI, CUI, ePHI) | 60–90 days | 30 days | One host, then 2, then 10 % per week, with after-action review per wave |
| OT-adjacent / safety-critical | 90 days minimum | 60 days minimum | One host at a time; co-ordinated outage windows |

The pattern: bigger blast radius → slower pacing.

---

## Common anti-patterns

| Anti-pattern | What goes wrong | Fix |
|---|---|---|
| "We'll skip Monitor and start in Simulate." | ADM has no data to learn from; the policy you author is hypothetical and full of gaps. | Run Monitor for 30+ days first. Always. |
| "We'll promote 100 hosts to Enforce in one ticket." | One bad rule breaks 100 hosts. | One host first, then waves. |
| "We'll author the policy from a network-design doc." | The doc is what the team intended; the live workload talks to things that aren't in the doc. | Use ADM (the as-observed view) plus the doc, not just the doc. |
| "We'll drain the simulation log next sprint." | The log keeps growing; the team gets numb to it. | Drain to zero (category-1 and category-2) before promotion. |
| "We don't have a roll-back plan; we'll figure it out if it breaks." | When it breaks, the response is improvised; outage extends. | Rehearse roll-back before promoting any wave. |
| "We applied policy from one week of data; it'll be fine." | Cyclical workloads (monthly close, quarterly batch) get blocked the first time the cycle hits Enforcement. | Capture a full operational cycle in Monitor before authoring policy. |

---

## What "good" looks like

A well-paced rollout produces these signals:

- Sensor coverage trend up and to the right; >95 % stable
- ADM-derived policies that ship to Simulate within 4–6 weeks of
  Phase 1 start
- Simulation logs that drain to zero category-1 / category-2
  flows before any host is promoted
- Enforce-mode promotion in waves, with after-action review after
  each wave
- Quarterly policy review on the calendar; workspace history full
  of small, ticket-linked changes rather than annual rewrites

---

## See also

- [`01-prerequisites.md`](./01-prerequisites.md) — pre-install gates
- [`02-sensor-types.md`](./02-sensor-types.md) — sensor selection
- [`03-decision-matrix.md`](./03-decision-matrix.md) — install method selection
- [`../operations/07-enforcement-mode-rollout.md`](../operations/07-enforcement-mode-rollout.md) — operational playbook for Phase 3
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md) — when something goes wrong
