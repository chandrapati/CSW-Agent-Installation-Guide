# Operations — Enforcement Rollout Pattern

The hardest part of CSW isn't installing the agent — it's
turning enforcement on without breaking production. This doc is
the operating pattern for getting from *sensor installed* to
*policy enforced* safely.

> Everything here assumes the **Enforcement** sensor type (not
> Deep Visibility). For details, see
> [`../docs/02-sensor-types.md`](../docs/02-sensor-types.md).

---

## The four stages

```
   Stage 1            Stage 2              Stage 3             Stage 4
   ───────            ───────              ───────             ───────
   MONITOR            POLICY DRAFT         SIMULATE            ENFORCE
   (visibility)       (no effect)          (dry-run)           (real)

   sensor capturing   policy authored,     policy in           policy in
   flows; learning    workspace =          workspace =         workspace =
   the application;   "Draft"; not         "Simulate"; CSW     "Enforce"; rules
   no policy at all   applied to host      shows what would    written to host
                                           be allowed/denied   firewall

   duration:          duration:            duration:           duration:
   2-4 weeks          1-2 weeks            2-4 weeks           ongoing
   per scope          per scope            per scope           with regular
                                                               iteration
```

This is the same shape as the broader rollout strategy in
[`../docs/04-rollout-strategy.md`](../docs/04-rollout-strategy.md),
but applied per **scope** (per application or per business unit)
rather than per host.

---

## Stage 1 — Monitor

**Goal:** capture enough flow data to write meaningful policy.

- Sensors deployed in *Deep Visibility* mode
- Workspace exists for the scope but no policy is authored yet
- Use *Investigate → Flows* and *Visualize → Flow Map* to learn
  the application

**Exit criteria for Stage 1:**

- 2–4 weeks of flow data covering at least one full business
  cycle (month-end, quarter-end, batch window — whichever
  matters most for this app)
- All scope members have an active sensor (no agent gaps)
- Application owner agrees the captured topology is reasonable

---

## Stage 2 — Policy draft

**Goal:** author the policy from the captured flow data.

- Use CSW's **Automated Policy Discovery (ADM)** as a starting
  point. ADM proposes policy rules from observed flows; treat
  the output as a draft, not the final answer.
- Refine the draft with the application team:
  - Group similar workloads into *clusters* (web tier, app tier,
    DB tier)
  - Convert IP-based rules into label-based rules where possible
    (IP-based rules don't survive auto-scaling)
  - Add explicit *deny* rules for the obvious bad — egress to
    public IPs from a DB tier, e.g.
- Workspace status: *Draft*. Nothing is applied to hosts yet.

**Exit criteria for Stage 2:**

- Policy reviewed by app owner and security team
- Rule count is reasonable (a tier of 50 hosts with 200 rules is
  a smell — usually means too many IP-based rules; refactor to
  labels)
- ADM coverage report: >95% of observed flows are matched by a
  rule (the remaining 5% are usually rare integration paths)

---

## Stage 3 — Simulate

**Goal:** confirm the policy doesn't block anything that
shouldn't be blocked.

- Workspace status: *Simulate*. CSW computes "what would have
  been allowed/denied" for every flow but **doesn't actually
  enforce** at the host firewall.
- Watch *Investigate → Policy Analysis* daily:
  - **False denies** (real flows that policy would block) →
    investigate; either fix the flow (legit traffic the policy
    missed) or fix the policy (legitimate exception)
  - **False allows** (rare; usually fine) → log for review
- Span at least one full business cycle in Simulate. The flows
  that catch you out are always the rare ones.

**Exit criteria for Stage 3:**

- Zero false denies for at least 7 consecutive days
- App owner sign-off
- Change ticket / change advisory board approval if your estate
  requires one for policy changes

---

## Stage 4 — Enforce

**Goal:** actually push the policy to the host firewall.

- Workspace status: *Enforce*. The sensor writes iptables /
  nftables rules (Linux) or WFP filters (Windows) on each host
  in the scope.
- For the **first 24 hours** after flipping to Enforce: have
  someone on standby. Real-world breakage shows up in the first
  business hour usually.
- Watch *Investigate → Policy Events*:
  - Denies that are unexpected → roll back the rule that's
    biting; investigate; re-author
  - Denies that are expected (the bad you wanted to block) →
    document as a win
- Workspace iteration: weekly initially, monthly once stable
  (new flow patterns from app changes always appear)

**Exit criteria for Stage 4:**

- Stable for 2+ weeks with denies tracking only the expected
  bad
- App owner agrees the policy is the operating posture
- Move to the next scope's Stage 1

---

## Rollback

Each stage has a clear rollback:

| Stage | Rollback | Time to revert |
|---|---|---|
| Monitor | n/a — no policy applied | n/a |
| Draft | n/a — no policy applied | n/a |
| Simulate | Flip workspace back to Draft | seconds |
| Enforce | Flip workspace back to Simulate (rules removed from hosts) | seconds; ride the next heartbeat |

The "seconds" caveat: the sensor reconverges on its next
heartbeat, which is typically <30 seconds. There's no per-host
manual cleanup needed.

---

## Pacing across scopes

Don't enforce more than a few scopes at once. A reasonable
pacing pattern for an estate of dozens of applications:

| Wave | Scope class | Pace |
|---|---|---|
| 1 | Stateless / non-critical apps | 1 scope per week |
| 2 | Stateful but recoverable (caches, queues) | 1 scope per 2 weeks |
| 3 | Customer-facing / revenue-impacting | 1 scope per month, with explicit business sign-off |
| 4 | Critical infrastructure (DBs, AD, DNS) | 1 scope per quarter, with extra scrutiny |

The pace is calibrated to your team's capacity to investigate
denies — burning out on rule debugging is the most common
reason enforcement programmes stall.

---

## Anti-patterns

| Anti-pattern | Why it bites | Fix |
|---|---|---|
| Skipping Simulate ("we know the policy is right") | Always wrong. Production has paths nobody documented. | Run Simulate for a full business cycle |
| Bulk Enforce across many scopes at once | One scope's bad rules cause noise that masks others' real issues | Pace per the table above |
| IP-based rules in autoscaled environments | Rules expire as instances rotate | Use label-based rules |
| Enforcing on a scope where some hosts have no agent | Those hosts won't enforce; effective posture is mixed | Confirm 100% sensor coverage before flipping Enforce |
| No app owner involvement | Policy will be wrong; policy will get rolled back; trust will erode | Make app owner a named approver at every stage transition |
| "Default deny everywhere" without graduated rollout | Outages | Start with allow-list against Simulate-mode evidence; tighten over time |

---

## See also

- [`../docs/02-sensor-types.md`](../docs/02-sensor-types.md) — Enforcement vs. Deep Visibility
- [`../docs/04-rollout-strategy.md`](../docs/04-rollout-strategy.md) — broader rollout shape
- [`08-evidence-audit.md`](./08-evidence-audit.md) — capturing enforcement evidence for audit
