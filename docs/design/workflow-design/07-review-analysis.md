# Review Analysis — PSC Workflow Engine Design

> **Status:** IN PROGRESS. Points are recorded with status and decisions.
> Only when ALL points are covered will relevant ones move to ADRs and
> design changes be made.
>
> **Reviewers:** SW Engineer (89 points), Security Reviewer (36 points),
> Docs Writer (23 points). Total: 148 points.
>
> **Legend:** `[PENDING]` = not yet addressed | `[CLARIFICATION ASKED]` = user needs more info | `[DECIDED]` = decision recorded | `[IMPLEMENTED]` = change made in design docs

---

## SW Engineer Review (89 points)

### Critical Gaps

| # | Point | Status | Decision / Clarification |
|---|-------|--------|--------------------------|
| 1 | No atomicity boundary around `advance()` — StepWriter.write, passport save, mirror regen, hooks are separate operations with no transaction | [DECIDED] | Atomicity to be corrected. A re-alignment process should check if the StepRecord exists and if the passport is not updated accordingly, it can correct it and recover from the failure. Same for the regenerated mirror. The regenerated mirror should be a **feature flag** that can be turned off in workflows that are not agentic or that have other means of logging agent outputs. |
| x | (NEW) Document 01 mentions `AgentOutcome` in the Design Agnosticism principle — this is a contradiction. The principle says the engine is language-agnostic but names a PSC-specific Python class. | [DECIDED] | Suggest replacing `AgentOutcome` with an agnostic term: **`StepOutcome`** — the outcome of a step, regardless of whether the actor is an agent, human, or system. The term `AgentOutcome` should not appear in the agnosticism principle or any engine-level spec; it may appear in the PSC profile as a PSC-specific specialization. |
| 2 | `outcome.base` schema allows `verdict` as a free-form string, not the enum | [DECIDED] | Correct. `verdict` should be an enum. How to implement is tied to point 3 (the enum must support both predefined engine values and custom project values). |
| 3 | `Verdict` enum mixes engine-generic (`pass`/`fail`) and PSC-specific (`classified`, `adr_written`, etc.) values — violates Design Agnosticism | [CLARIFICATION ASKED] | Correct. How is this going to be implemented? It affects point 2. Need a mechanism where the engine defines a minimal set of verdicts (`pass`, `fail`) and projects extend with custom verdicts in their profile. The verdict enum must be: (a) predefined values for engine routing, (b) flexible to accommodate custom values from the profile. Needs design for how the JSON Schema `enum` is built dynamically from the workflow's transition keys + engine defaults. |
| 4 | `skip` semantics are undefined | [DECIDED] | Suggest `skip` be **removed** to respect determinism. Unless the workflow defines an alternative path (a real transition to a state that handles the case), a skip will be a reason for abuse. The workflow must explicitly model alternative paths, not implicitly skip states. |
| 5 | Two incompatible `routing_rule` shapes with no schema | [DECIDED] | `route.c4` can be replaced by normal `transitions` (it's a simple lookup table). Routing rules are only for conditions that require evaluation, and they should be similar to a SQL `CASE` statement: `CASE WHEN condition THEN target; WHEN condition2 THEN target2; ELSE default; END`. This avoids nested conditions. One DSL, one shape, SQL-CASE-style. |
| 6 | Gates have `dispatch_handler` they never use and `retry` that doesn't apply | [CLARIFICATION ASKED] | Need clarification on how the workflow engine knows if a step is to be dispatched to an agent, a service (API), or a human via UI. We should clarify the retry mechanism: (a) If a step fails for any reason, there should be a **retry and back-off defined globally** that can be **overridden in the definition**. (b) There is another type of retry specific to **loops** — perhaps we need to name it properly to have a distinction. Loop retry is defined in the schema with a **global default of 3**. Need design for: global dispatch retry + backoff (overridable per state), vs. loop retry budget (global default 3, overridable per gate). Also need to clarify: gates should NOT have `dispatch_handler` or `retry` blocks — those are for task states. Gates are driven by `gate_config.retry_budget`. |
| 7 | `cancel_subject` and `DEFERRED` reference synthetic terminal states absent from the workflow JSON | [DECIDED] | Cancelled, deferred, archived should **not pollute the workflow history**. They are **flags** that indicate a workflow is abandoned, cancelled, or archived, but the history stays loyal to what actually happened without affecting it. The passport gets a status flag (`cancelled: true`, `deferred: true`, `archived: true`); the `state.current` stays at whatever state the workflow was actually at when the flag was set. No synthetic `CANCELLED` or `DEFERRED` states in the graph. |
| 8 | `Context.vars` is mutable and shared across parallel branches — race condition | [DECIDED] | Agree. Context should be frozen; `vars` deep-copied per parallel branch; merged at join time under the engine's control. |
| 9 | No idempotency key on `advance()` | [DECIDED] | Agree. A **predictable deterministic idempotency key** should be calculated. It can be the step + attempt count or something that is invariant — i.e., a function of `(subject_id, step, entry_count, attempt)` that is the same if the same call is retried. |
| 10 | `State.__lt__` dereferences `_registry` which defaults to `None` | [CLARIFICATION ASKED] | Need more information. The user wants to understand the issue better before deciding. The issue: `State.__lt__` calls `self._registry._is_ancestor(...)` but `_registry` defaults to `None`, so any comparison on a State constructed outside the registry raises `AttributeError`. Need to present options: (a) guard with `if self._registry is None: raise IncomparableStates`, (b) make `_registry` a required constructor argument, (c) remove `_registry` from State and use a free function `is_ancestor(registry, a, b)`. |
| 11 | `Transition.outcome` type is inconsistent (`Verdict` vs `str`) | [DECIDED] | If `Transition.outcome` means verdict, it should be **renamed to `verdict`** and have the type `Verdict`. This should consider points 2 and 3 — the `Verdict` type must support predefined engine values AND be flexible for custom project values. |
| 12 | `aggregate_outcomes` is called outside the engine's atomicity boundary | [CLARIFICATION ASKED] | Need more information and more details on the suggested mechanism to: (a) advance parallel tasks, (b) track how many states are currently active/actionable (in the case of parallel routes), (c) how a state is configured to await all parallel branches to be completed, (d) how `aggregate_outcomes` works with dynamic outcomes. Need a detailed design for the parallel-join mechanism inside `advance()`. |
| 13 | No defined behaviour for `advance()` on terminal, decision_pending, or gate-without-begin_gate states | [CLARIFICATION ASKED] | Does `record_decision` need to be a first-class function, or can `record_decision` be the same as `advance` with the decision being the input and the condition being `is_decision_pending=true`? If unified, then `advance(subject_id, outcome)` where `outcome.decision` is populated when `is_decision_pending` would replace `record_decision` entirely. Need to decide: one unified `advance` or two separate functions. |
| 14 | No foreign-key / referential integrity for `outcome_ref` paths | [DECIDED] | `outcome_ref` is only for convenience. If it gets deleted, it should be handled gracefully — the engine should say "no longer exists" and the step_log entry retains its metadata (uuid, verdict, timestamp, etc.) but the outcome content is inaccessible. Not an error; a degraded state. |
| 15 | `project()` does not handle `additionalProperties`, `patternProperties`, or `unevaluatedProperties` | [DECIDED] | Correct. `project()` must handle `additionalProperties` and `patternProperties` classification. `unevaluatedProperties` schemas should be rejected at load time. |
| 16 | `project()` does not recurse into `protected` values | [DECIDED] | Classification should be applied to **any primitive** only. It should **not** be applicable to objects. If a field is an object, its child fields are classified individually. This simplifies the projection: redactors only ever see scalar values. |
| 17 | `EmailRedactor` and `TokenRedactor` have correctness bugs | [DECIDED] | Correct. Should be battle-tested using TDD. |
| 18 | Load-time validation omits several structural invariants | [DECIDED] | Agree. Should be battle-tested using TDD. |
| xx | (NEW) Testing strategy file should be added | [DECIDED] | A testing strategy file should be added to the design set. It should discuss: (a) where TDD is a must (state machine, routing, projection, redaction, validation), (b) how unit testing is used to cover happy and unhappy scenarios, (c) how e2e should be the final stress test of the workflow. |
| 19 | No schema for the passport JSON itself | [DECIDED] | Agree. Add `passport.base` JSON Schema, validated on every `SubjectStore.load`. |
| 20 | `retries` denormalised from `gate_configs` and can drift | [DECIDED] | Agree. Store only `retries_used`; derive budget from the snapshotted workflow definition. |
| 21 | `version_pins.workflow` duplicates `workflow_version` | [DECIDED] | Agree. Keep only `workflow_version`; drop `version_pins`. |
| 22 | `outcomes` dict and `step_log[].outcome_ref` store outcomes in two places | [CLARIFICATION ASKED] | If I agree (that `outcomes` is redundant), then what is the distinction between a passport and the steps written? Need to clarify: the passport is the **runtime state** (current state, retries, decisions, parallel progress, vars, step_log index); the steps written (via StepWriter) are the **artifacts** (the full outcome JSON). The passport references artifacts via `outcome_ref` but does not contain them. Is this the right separation? |
| 23 | `is_adhoc` denormalises `workflow_id` | [DECIDED] | Correct. Drop `is_adhoc`; derive from `workflow_id`. |

### Gaps (24-89)

| # | Point | Status | Decision / Clarification |
|---|-------|--------|--------------------------|
| 24 | `State._registry` back-reference couples State to StateRegistry | [PENDING] | |
| 25 | `State.__eq__`/`__hash__` override frozen-dataclass defaults | [PENDING] | |
| 26 | `Context.is_retry` conflates loop-back and retry | [PENDING] | |
| 27 | `DispatchHandler.dispatch` takes `state: dict`, not `State` | [PENDING] | |
| 28 | `DispatchHandler.dispatch` takes `outcome_schema: dict` — redundant | [PENDING] | |
| 29 | `EventStore.append` takes `uuid: UUID` — who generates it? | [PENDING] | |
| 30 | `EventStore.load_events` returns `list[dict]` — untyped | [PENDING] | |
| 31 | `SubjectStore.load_inflight` returns positional tuple | [PENDING] | |
| 32 | `SubjectStore.save` takes `active_steps` separately from `state_json` | [PENDING] | |
| 33 | `claim` returns `bool` — loser doesn't know it lost | [PENDING] | |
| 34 | `reap_stale_claims` releases but doesn't re-dispatch | [PENDING] | |
| 35 | `HookRegistry` silently swallows exceptions | [PENDING] | |
| 36 | `AuditHook` and `EventStore` overlap | [PENDING] | |
| 37 | `EventDispatchHook` has no outbox — at-least-once not guaranteed | [PENDING] | |
| 38 | Hook firing order — inconsistent visibility | [PENDING] | |
| 39 | `workflow.escalated` vs `state.entered` for ESCALATE — order undefined | [PENDING] | |
| 40 | `fan_out: "$roster"` — JSONPath doesn't resolve | [PENDING] | |
| 41 | `join: "quorum:N"` mentioned but never defined | [PENDING] | |
| 42 | `carried_forward: true` on `outputs` is undefined | [PENDING] | |
| 43 | `outputs.produced` mapping mixes JSONPath and JSON Pointer | [PENDING] | |
| 44 | `route.user_disposition.match` JSONPath filter syntax malformed per RFC 9535 | [PENDING] | |
| 45 | No versioning of `psc-profile.json` | [PENDING] | |
| 46 | `agents_folder` resolved at dispatch time — agent deletion breaks re-dispatch | [PENDING] | |
| 47 | `Config.roster.signals` are plain strings with no tokeniser | [PENDING] | |
| 48 | `RosterResolver.validate_roster` rejects custom entries | [PENDING] | |
| 49 | `propose_roster` takes `domain_signals` but contract undefined | [PENDING] | |
| 50 | No `DispatchError` in the exception hierarchy | [PENDING] | |
| 51 | No retry policy for `DispatchHandler.dispatch` failures | [PENDING] | |
| 52 | `migrate` API has no defined semantics | [PENDING] | |
| 53 | `max_review_rounds` and `gate.CR2.round_budget` overlap | [PENDING] | |
| 54 | `review_round` increment point undefined | [PENDING] | |
| 55 | After CR2 `request_changes` → B2, does workflow re-enter CR1 or skip to CR2? | [PENDING] | |
| 56 | B2 lets agent decide when units are complete — judgement in `task` state | [PENDING] | |
| 57 | `A2c` has empty `transitions: {}` — two routing mechanisms | [PENDING] | |
| 58 | `route.user_disposition` and `route.c4` emit no `event_name` | [PENDING] | |
| 59 | `decision.user_disposition` schema referenced but never defined | [PENDING] | |
| 60 | `A0` decision schema is missing — judgement point modelled as `task` | [PENDING] | |
| 61 | `propose_roster` returns `RosterProposal` but type undefined | [PENDING] | |
| 62 | `load_workflow` returns "workflow object" — ambiguous type | [PENDING] | |
| 63 | `current_state` return type unspecified | [PENDING] | |
| 64 | `possible_outcomes` return shape undocumented | [PENDING] | |
| 65 | `query` API uses magic strings | [PENDING] | |
| 66 | `route_for_outcome` relationship to `advance` unclear | [PENDING] | |
| 67 | `validate_passport` checks are undefined | [PENDING] | |
| 68 | No schema for `gate_config` | [PENDING] | |
| 69 | `retry_policy` and `gate_config.retry_budget` — two sources of truth | [PENDING] | |
| 70 | `phases` array has `ord` but states reference `phase` by `id` — no FK validation | [PENDING] | |
| 71 | `states` dict keyed by name but each state also has `name` field — drift risk | [PENDING] | |
| 72 | `agent: ""` on terminal states is empty-string sentinel | [PENDING] | |
| 73 | `agent` field couples workflow to project-specific agent names | [PENDING] | |
| 74 | `WorkflowService` imported in e2e test but never defined | [PENDING] | |
| 75 | Clean architecture layers mentioned but not detailed | [PENDING] | |
| 76 | SRP: `StepWriter` has three responsibilities | [PENDING] | |
| 77 | ISP: `SubjectStore` is a fat protocol | [PENDING] | |
| 78 | LSP: `EmailRedactor.redact(value: str)` narrows `Redactor.redact(value: Any)` | [PENDING] | |
| 79 | DIP: `Config` is concrete dataclass passed into application layer | [PENDING] | |
| 80 | No deadlock/livelock detection for claims | [PENDING] | |
| 81 | No retention policy for `events` table | [PENDING] | |
| 82 | No SQLite schema migration mechanism | [PENDING] | |
| 83 | `WorkflowDefinitionStore.load_definition` returns dict — no lifecycle metadata | [PENDING] | |
| 84 | `subjects.state_json TEXT` — no indexing | [PENDING] | |
| 85 | No index on `subjects.claimed_by`/`claimed_at` | [PENDING] | |
| 86 | `events` table FK not enforced by default in SQLite | [PENDING] | |
| 87 | No defined connection lifecycle for SQLite/PG | [PENDING] | |
| 88 | `StepWriter` path collision risk with `step.replace("#","_")` | [PENDING] | |
| 89 | `test_happy_path` calls `aggregate_outcomes` explicitly | [PENDING] | |

---

## Security Reviewer Review (36 points)

### Critical Gaps

| # | Point | Status | Decision / Clarification |
|---|-------|--------|--------------------------|
| S1 | No authentication or authorisation model | [PENDING] | |
| S2 | Data classification defaults to `public` (fail-open) | [PENDING] | |
| S3 | Undeclared fields pass through `project()` unredacted | [PENDING] | |
| S4 | No fencing token for claim/lease — write-after-reap corruption | [PENDING] | |
| S5 | Cleartext passport storage with no encryption-at-rest | [PENDING] | |
| S6 | No tamper-evidence on audit trail (events table) | [PENDING] | |
| S7 | No integrity verification on workflow definitions or agent files | [PENDING] | |
| S8 | Path traversal in StepWriter via unsanitised `subject_id` | [PENDING] | |
| S9 | No access control on adhoc workflow — bypasses all gates | [PENDING] | |
| S10 | Unauthenticated `session_id` enables claim DoS and stealing | [PENDING] | |

### Gaps

| # | Point | Status | Decision / Clarification |
|---|-------|--------|--------------------------|
| S11 | JSON Pointer write paths not validated | [PENDING] | |
| S12 | `system_webhook_dispatch` has no SSRF protections | [PENDING] | |
| S13 | Event dispatch has no auth, TLS, or message signing | [PENDING] | |
| S14 | No secret management system | [PENDING] | |
| S15 | No rate limiting on any API endpoint | [PENDING] | |
| S16 | No threat model documented | [PENDING] | |
| S17 | No security configuration in `psc_engine.yaml` | [PENDING] | |
| S18 | `RedactorRegistry.resolve()` behaviour on missing name unspecified | [PENDING] | |
| S19 | Hook failures silently swallowed — AuditHook can fail without detection | [PENDING] | |
| S20 | No audit log retention, archival, or disposal policy | [PENDING] | |
| S21 | PostgreSQL connection security unspecified | [PENDING] | |
| S22 | SQLite database file permissions unspecified | [PENDING] | |
| S23 | MCP server transport security unspecified | [PENDING] | |
| S24 | No input validation beyond JSONPath existence check | [PENDING] | |
| S25 | Outcome JSON Schema validates structure, not semantics — stored XSS risk | [PENDING] | |
| S26 | No compartmentalisation between workflows | [PENDING] | |
| S27 | Routing rule `skip` field — can skip all gates (related to SW#4) | [PENDING] | |
| S28 | `gate_fail` root_cause is a free string — no validation | [PENDING] | |
| S29 | `confidence` field is self-reported and unverified | [PENDING] | |
| S30 | `model` field in step log has no integrity verification | [PENDING] | |
| S31 | `query` API has no access control | [PENDING] | |
| S32 | `migrate` API has no authorisation | [PENDING] | |
| S33 | `load_workflow` has no access control | [PENDING] | |
| S34 | `propose_roster` accepts attacker-controlled `domain_signals` | [PENDING] | |
| S35 | Domain `event_name` runtime substitution not re-validated | [PENDING] | |
| S36 | `EmailRedactor` partially discloses email structure | [PENDING] | |

---

## Docs Writer Review (23 points)

### Critical Gaps

| # | Point | Status | Decision / Clarification |
|---|-------|--------|--------------------------|
| D1 | `DEFERRED` state referenced but never defined (related to SW#7) | [PENDING] | Related to SW#7 — user decided cancelled/deferred/archived are flags, not states. This point should be resolved by SW#7's decision. |
| D2 | `EventStore.append` signature omits `event_name` | [PENDING] | |
| D3 | Aggregation verdict for A1 doesn't match its transition outcome key | [PENDING] | |
| D4 | `outputs.produced` schema inconsistent between §3.3 and §3.6 | [PENDING] | |
| D5 | No read API for outcome JSON; UI requires one | [PENDING] | |
| D6 | `needs_clarification` verdict absent from `Verdict` enum | [PENDING] | |
| D7 | e2e test uses `verdict="needs_info"` but A0 has no `needs_info` transition | [PENDING] | |
| D8 | `new_subject` API absent from the API contract table | [PENDING] | |

### Gaps

| # | Point | Status | Decision / Clarification |
|---|-------|--------|--------------------------|
| D9 | `AgentOutcome` class used in e2e test but never defined | [PENDING] | |
| D10 | `State` dataclass missing fields from workflow JSON | [PENDING] | |
| D11 | `State.id: int` has no source in workflow JSON | [PENDING] | |
| D12 | `StateRegistry` referenced but never defined | [PENDING] | |
| D13 | Routing-rule transitions lack `event_name` (related to SW#58) | [PENDING] | |
| D14 | `skip` semantics undefined (related to SW#4) | [PENDING] | |
| D15 | `stamp` / `STMP-####` used but never defined | [PENDING] | |
| D16 | `A0L` referenced but never defined | [PENDING] | |
| D17 | `psc-adhoc` workflow JSON not provided | [PENDING] | |
| D18 | Gate tier sequencing undefined | [PENDING] | |
| D19 | `$`-prefix variable convention undocumented | [PENDING] | |
| D20 | `quorum:N` join mentioned but never defined | [PENDING] | |
| D21 | `max_review_rounds` vs `round_budget` relationship unclear (related to SW#53) | [PENDING] | |
| D22 | Workflow definition snapshot mechanism inconsistent | [PENDING] | |
| D23 | Schema profile not versioned or snapshotted per subject | [PENDING] |

---

## Progress Summary

| Reviewer | Total | Pending | Clarification Asked | Decided | Implemented |
|----------|-------|---------|--------------------|--------|-------------| 
| SW Engineer | 89 | 66 | 4 (#3, #6, #10, #12, #13) | 19 (+2 new: x, xx) | 0 |
| Security | 36 | 36 | 0 | 0 | 0 |
| Docs Writer | 23 | 23 | 0 | 0 | 0 |
| **Total** | **148** | **125** | **4** | **21** | **0** |

---

## Decisions Log (ordered by decision)

### D-001: Atomicity + re-alignment (SW#1)
**Decision:** `advance()` must be atomic. A re-alignment process checks if a StepRecord exists but the passport wasn't updated — it corrects and recovers. Same for the mirror. The Markdown mirror is a **feature flag** (can be turned off for non-agentic workflows or those with other logging).
**Date:** 2026-06-30
**Status:** DECIDED

### D-002: Replace `AgentOutcome` with `StepOutcome` in agnosticism principle (SW#x)
**Decision:** The term `AgentOutcome` is PSC-specific and contradicts Design Agnosticism. Replace with **`StepOutcome`** — agnostic to actor kind (agent/human/system). `AgentOutcome` may appear in the PSC profile as a specialization, not in engine-level specs.
**Date:** 2026-06-30
**Status:** DECIDED

### D-003: Verdict must be an enum (SW#2)
**Decision:** `verdict` in `outcome.base` schema must be an enum, not a free-form string.
**Date:** 2026-06-30
**Status:** DECIDED (implementation tied to D-004)

### D-004: Verdict enum generalisation (SW#3)
**Decision:** PENDING — need design for how the enum supports predefined engine values (`pass`, `fail`) + custom project values from the profile. Affects D-003.
**Date:** 2026-06-30
**Status:** CLARIFICATION ASKED

### D-005: Remove `skip` (SW#4)
**Decision:** `skip` is removed entirely. The workflow must explicitly model alternative paths via real transitions. No implicit skipping.
**Date:** 2026-06-30
**Status:** DECIDED

### D-006: Unify routing rules to SQL-CASE-style (SW#5)
**Decision:** `route.c4` (simple lookup) is replaced by normal `transitions`. Routing rules are only for conditions requiring evaluation, structured as SQL `CASE WHEN ... THEN ... ELSE ... END`. One DSL, one shape.
**Date:** 2026-06-30
**Status:** DECIDED

### D-007: Clarify dispatch retry vs loop retry (SW#6)
**Decision:** PENDING — need design for: (a) global dispatch retry + backoff (overridable per state), (b) loop retry budget (global default 3, overridable per gate). Also clarify how engine knows dispatch target (agent/service/human). Gates should NOT have `dispatch_handler` or `retry` blocks.
**Date:** 2026-06-30
**Status:** CLARIFICATION ASKED

### D-008: Cancelled/deferred/archived are flags, not states (SW#7)
**Decision:** Cancelled, deferred, archived are **status flags** on the passport, not synthetic terminal states in the graph. The history stays loyal to what actually happened. `state.current` stays at the actual state when the flag was set.
**Date:** 2026-06-30
**Status:** DECIDED

### D-009: Freeze Context + deep-copy vars per parallel branch (SW#8)
**Decision:** Context is frozen; `vars` is deep-copied per parallel branch; merged at join time under engine control.
**Date:** 2026-06-30
**Status:** DECIDED

### D-010: Deterministic idempotency key (SW#9)
**Decision:** A predictable deterministic idempotency key calculated from invariant properties (e.g., `subject_id + step + entry_count + attempt`).
**Date:** 2026-06-30
**Status:** DECIDED

### D-011: Clarify State.__lt__ / _registry issue (SW#10)
**Decision:** PENDING — user needs more information.
**Date:** 2026-06-30
**Status:** CLARIFICATION ASKED

### D-012: Rename Transition.outcome to verdict (SW#11)
**Decision:** `Transition.outcome` is renamed to `verdict` with type `Verdict`. Must consider D-003/D-004 (predefined + custom values).
**Date:** 2026-06-30
**Status:** DECIDED

### D-013: Clarify parallel advance mechanism (SW#12)
**Decision:** PENDING — need detailed design for parallel-join inside `advance()`: tracking active states, awaiting branches, dynamic outcomes.
**Date:** 2026-06-30
**Status:** CLARIFICATION ASKED

### D-014: Unify record_decision with advance? (SW#13)
**Decision:** PENDING — can `record_decision` be the same as `advance` with the decision as input when `is_decision_pending=true`?
**Date:** 2026-06-30
**Status:** CLARIFICATION ASKED

### D-015: outcome_ref is convenience, handle deletion gracefully (SW#14)
**Decision:** `outcome_ref` is for convenience. If deleted, engine says "no longer exists" — degraded state, not an error. Step log retains metadata.
**Date:** 2026-06-30
**Status:** DECIDED

### D-016: project() handles additionalProperties (SW#15)
**Decision:** `project()` must handle `additionalProperties` and `patternProperties`. `unevaluatedProperties` rejected at load time.
**Date:** 2026-06-30
**Status:** DECIDED

### D-017: Classification only on primitives, not objects (SW#16)
**Decision:** Classification applies to **primitives only**. Objects are not classified as a whole — their child fields are classified individually. Redactors only see scalar values.
**Date:** 2026-06-30
**Status:** DECIDED

### D-018: Redactors battle-tested with TDD (SW#17)
**Decision:** Redactor implementations must be battle-tested using TDD.
**Date:** 2026-06-30
**Status:** DECIDED

### D-019: Load-time validation battle-tested with TDD (SW#18)
**Decision:** Load-time validation must be battle-tested using TDD.
**Date:** 2026-06-30
**Status:** DECIDED

### D-020: Add testing strategy file (SW#xx)
**Decision:** A testing strategy file is added to the design set. Covers: where TDD is a must, unit testing for happy/unhappy, e2e as final stress test.
**Date:** 2026-06-30
**Status:** DECIDED

### D-021: Add passport.base JSON Schema (SW#19)
**Decision:** Add `passport.base` JSON Schema, validated on every `SubjectStore.load`.
**Date:** 2026-06-30
**Status:** DECIDED

### D-022: Store retries_used, derive budget (SW#20)
**Decision:** Store only `retries_used`; derive budget from the snapshotted workflow definition at gate-evaluation time.
**Date:** 2026-06-30
**Status:** DECIDED

### D-023: Drop version_pins (SW#21)
**Decision:** Keep only `workflow_version`; drop `version_pins`.
**Date:** 2026-06-30
**Status:** DECIDED

### D-024: Clarify passport vs steps distinction (SW#22)
**Decision:** PENDING — if `outcomes` dict is removed from passport, what is the distinction between a passport and the steps written? Need to clarify the separation.
**Date:** 2026-06-30
**Status:** CLARIFICATION ASKED

### D-025: Drop is_adhoc (SW#23)
**Decision:** Drop `is_adhoc`; derive from `workflow_id`.
**Date:** 2026-06-30
**Status:** DECIDED

---

## Clarifications Needed (open items)

1. **D-004 (SW#3):** How to implement a Verdict enum that supports predefined engine values (`pass`/`fail`) + custom project values from the profile, validated in JSON Schema.
2. **D-007 (SW#6):** Design for: (a) global dispatch retry + backoff (overridable), (b) loop retry budget (default 3, overridable per gate), (c) how engine knows dispatch target (agent/service/human).
3. **D-011 (SW#10):** Present options for `State._registry` issue (guard / required arg / free function).
4. **D-013 (SW#12):** Detailed design for parallel-join inside `advance()`.
5. **D-014 (SW#13):** Can `record_decision` be unified with `advance`?
6. **D-024 (SW#22):** Clarify the passport vs steps-written distinction after removing the `outcomes` dict.