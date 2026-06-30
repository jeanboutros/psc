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

---

## Agent Responses to Clarifications (Round 1)

> Reviewed by: Architect/SW Engineer, SW Engineer, Data Architect, Security Reviewer.
> All responses recorded verbatim — no synthesis.

---

### D-004: Verdict Enum Generalisation — Architect Response

**Status:** PROPOSED — awaiting user decision

**Proposal:** The engine defines exactly **two** verdicts that all workflows must support: `pass` and `fail`. Everything else (`classified`, `synthesized`, `adr_written`, etc.) is a **project-defined verdict** that the engine treats as an opaque string label.

**Mechanism:**
- The `Verdict` type is a `NewType[str]` (not a fixed enum) — open set validated externally by JSON Schema.
- The valid verdicts for a state = the keys of its `transitions` dict + engine defaults (`pass`, `fail`).
- The profile may optionally declare a `verdict_registry` for documentation, but the transition keys are the source of truth.
- The JSON Schema `enum` for `verdict` is built dynamically per-state by `VerdictSchemaBuilder`:

```python
class VerdictSchemaBuilder:
    ENGINE_VERDICTS = frozenset({"pass", "fail"})
    
    def build_enum(self, state_transitions: dict[str, Transition]) -> list[str]:
        transition_keys = set(state_transitions.keys())
        valid = self.ENGINE_VERDICTS | transition_keys
        return sorted(valid)
    
    def materialise_schema(self, base_schema: dict, state_transitions: dict) -> dict:
        schema = copy.deepcopy(base_schema)
        schema["properties"]["verdict"]["enum"] = self.build_enum(state_transitions)
        return schema
```

- Transition lookup: `state.transitions.get(verdict)` — plain dict lookup, no enum dispatch table.
- Validation: two-layered — load-time (verdict keys match `^[a-z][a-z0-9_]*$`) + runtime (outcome's verdict is in the materialised enum).
- Rust/Go reimplementation: `type Verdict = String` + `const ENGINE_PASS: &str = "pass"` — no enum type needed.

**Rationale:** A `StrEnum` is a closed set requiring code change. A `NewType[str]` is an open set validated by JSON Schema, matching the spec (workflow JSON defines valid values; Python carries the string). This is the same pattern as ASL's `Choice` rules.

---

### D-007: Dispatch Retry vs Loop Retry — Architect Response

**Status:** PROPOSED — awaiting user decision

**Two distinct mechanisms:**

| Dimension | Dispatch Retry | Re-entry Budget (renamed from "Loop Retry") |
|-----------|---------------|---------------------------------------------|
| Name | `dispatch_retry` | `reentry_budget` |
| Trigger | `DispatchHandler.dispatch()` raises `DispatchError` (timeout, crash, OOM, network) | Gate evaluation returns `fail` verdict; transition has `loop: true` |
| Scope | Per-state (any task/parallel with dispatch_handler) | Per-gate (only gate states) |
| Budget | Global default (configurable); overridable per-state | Global default 3; overridable per-gate via `gate_config.reentry_budget` |
| Backoff | Exponential with jitter | None — loop-back requires substantive work (fix code, re-review) |
| Counter | `meta.attempt` (increments within same entry) | `meta.entry_count` (increments on each state entry) |
| On exhaustion | `fail` verdict → route on `fail` transition or escalate | `exhausted` verdict → route to `ESCALATE` |
| Event fired | `retry.attempted` | `loop.triggered` |

**Why "Re-entry Budget" instead of "Loop Retry":** "Retry" implies the same operation repeated. A loop-back sends the workflow to an *earlier* state to do different work. "Re-entry" captures that the gate is re-entered after the loop-back completes. "Budget" captures it's a finite resource.

**Config additions (`psc_engine.yaml`):**
```yaml
dispatch_retry:
  max_attempts: 3
  backoff:
    strategy: exponential_jitter
    initial_ms: 1000
    multiplier: 2.0
    max_ms: 30000
  on_exhaust: fail

reentry_budget:
  default: 3
  on_exhaust: escalate
```

**Gates confirmed:** NO `dispatch_handler`, NO `retry` block. Gates are driven by `gate_config.reentry_budget`. The top-level `retry_policy` is **removed** (it duplicated gate_config). Gate states retain: `name`, `title`, `phase`, `step`, `kind: "gate"`, `agent` (audit), `gate_config`, `transitions` (with `pass`/`fail`/`exhausted`).

**Dispatch target resolution:** The `dispatch_handler` field on the state names a handler in `DispatcherRegistry`. Built-ins: `engine.subagent_dispatch` (agent), `engine.human_form_dispatch` (human), `engine.system_webhook_dispatch` (service). Unregistered handler → `HandlerNotRegistered` raised at load time.

**Security flag:** Hard engine-level cap required (e.g., `ENGINE_MAX_DISPATCH_ATTEMPTS = 10`, `ENGINE_MAX_REENTRY_BUDGET = 10`). Per-state overrides can reduce but not exceed. `max_attempts: 0` or negative rejected at load time.

---

### D-011: State._registry Issue — Architect Response

**Status:** PROPOSED — Option (c) recommended

**The issue:** `State.__lt__` calls `self._registry._is_ancestor(...)` but `_registry` defaults to `None`. Any comparison on a State constructed outside the registry raises `AttributeError`. Also violates Dependency Inversion (domain → infrastructure).

**Three options:**

| Option | Pros | Cons |
|--------|------|------|
| (a) Guard with `IncomparableStates` | Minimal change; clear error | Coupling remains; still uncomparable outside registry |
| (b) Required constructor arg | Impossible to construct uncomparable State | Serialisation breaks; heavier test setup |
| (c) Free function — remove `_registry` entirely | Clean architecture; fully serialisable; testable; idiomatic Rust match | Loses `s_a0 < s_a1` ergonomic |

**Recommendation: Option (c)** — Remove `_registry` from `State`. Remove `__lt__` from `State`. Add `StateRegistry.is_ancestor(a, b) -> bool`.

**Justification:**
1. Clean architecture — a node cannot know its ancestry without the graph.
2. Serialisability — `State` round-trips through JSON without `_registry` leak.
3. Testability — States constructed freely in tests; `registry.is_ancestor()` for graph semantics.
4. The spec says `__lt__` is a Python ergonomic; a Rust `PartialOrd` would live on the registry, not the node.
5. The ergonomic loss is minimal — `registry.is_ancestor(A0, A3)` is clearer than `A0 < A3`.

---

### D-013: Parallel Advance Mechanism — SW Engineer Response

**Status:** PROPOSED — awaiting user decision

**Key change:** `advance()` absorbs the entire fan-out → join → aggregate → transition lifecycle. No public `aggregate_outcomes` API. The caller only calls `advance(subject_id, branch_outcome)` once per branch return.

**Updated `advance()` flow for parallel state (11 steps):**
1. Load passport (atomic claim/version-CAS).
2. Resolve current state. Assert `kind == "parallel"`.
3. Compute idempotency key = `sha256(subject_id + state + entry_count + branch_id + attempt)`.
4. Idempotency check — if StepRecord with this key exists, short-circuit.
5. Validate branch outcome against `branch_schema` (NOT the composite schema).
6. Write branch outcome via StepWriter.
7. Update `parallel_progress` atomically — remove branch_id from `pending`, add to `returned` with outcome_ref + verdict.
8. Evaluate join: `all` → satisfied when `pending == []`; `quorum:N` → satisfied when `len(returned) >= N`.
9. If join NOT satisfied: save passport, fire `parallel.branch.completed`, return `{advanced: false, join_satisfied: false, pending: [...]}`.
10. If join satisfied: compute composite via `aggregation_rule` (from registry), validate composite against `outcome_schema`, write composite StepRecord, fire standard hook sequence, update passport (state.current = target, clear parallel_progress, merge vars), save + regenerate mirror.
11. Return `{advanced: true, new_state, composite, join_satisfied: true}`.

**`parallel_progress` data structure (updated):**
- `returned` is now a **map** (not array): `{branch_id: {verdict, outcome_ref, uuid, timestamp}}` — O(1) lookup.
- `join` is an **object** (not string): `{"type": "all"}` or `{"type": "quorum", "n": 2, "on_satisfied": "cancel_pending"}`.
- `on_satisfied` controls pending-branch fate: `"cancel_pending"` (default — late outcomes rejected), `"supersede"` (recompute composite), `"discard_late"` (silently discard).

**Dynamic fan_out:** `$roster` resolves to `ctx.vars["domain_classification"]["roster"]` at state entry (not at branch return). The roster is pinned by the A0 decision; never re-resolved.

**Two schemas per parallel state:** `branch_schema` (validated per-branch at step 5) + `outcome_schema` (validated on composite at step 10). For non-parallel states, `branch_schema` is absent.

**Aggregation rule:** Project-specific (`psc.aggregation.specialist_review`), resolved from `AggregationRegistry`. Built-ins: `engine.aggregation.verdict_all_pass`, `engine.aggregation.verdict_unanimous`. The engine calls `rule.aggregate(...)`, validates result against `outcome_schema`, reads `composite["verdict"]` for routing. The engine never interprets PSC fields.

**Crashed specialist recovery:** Caller re-dispatches by step ID (`A1#design`) with `attempt+1`. New idempotency key (attempt incremented). Branch retry budget (default 3) — if exceeded, branch marked `failed` with `verdict: "fail"`.

**Late-arriving outcome after join:** `advance()` checks if state has advanced past the parallel state. If so, outcome is written to disk (audit trail) but does NOT affect the composite or state transition. Returns `STATUS: JOIN_ALREADY_SATISFIED`.

**Security flag:** Aggregation policy (`all` vs `quorum:N`) must be engine-reserved, not workflow-injectable. Only the threshold `N` is configurable and clamped to `[1, len(expected)]`. A malicious branch cannot inject a composite verdict — the aggregation rule is engine-controlled.

---

### D-014: record_decision Unified with advance? — SW Engineer Response

**Status:** DECIDED — Separate (Option B)

**Recommendation:** `record_decision` remains a first-class function, distinct from `advance`.

**Why not unified:**
1. `verdict` is meaningless for a decision — a decision routes via `routing_rule`, not via `transitions[verdict]`. Forcing `verdict: "pass"` is a lie; `"decided"` is a synthetic filler.
2. Routing logic bifurcates inside `advance()` (if decision → routing_rule; else → transitions[verdict]).
3. Schema validation is conditional — `advance()` would need to choose `outcome_schema` vs `decision_schema` based on `state.kind`.
4. Caller ergonomics worsen — must construct an `outcome` object with filler `verdict`.
5. Hook sequence is cleaner separate: `decision.recorded` → `state.exited` → domain event → `state.entered`.

**Refined `record_decision` flow:**
1. Load passport (claim/CAS).
2. Assert `state.kind == "decision_required"` and `is_decision_pending == true`.
3. Idempotency key = `sha256(subject_id + state + entry_count + null + 0)`.
4. Validate `decision_object` against `state.decision_schema` (the discriminated union).
5. Evaluate `routing_rule` (SQL-CASE-style from D-006) — first match → target + event_name.
6. Write decision via StepWriter (decision_object IS the outcome for audit).
7. Fire hooks: `decision.recorded` → `state.exited` → domain event → `transition.triggered` → `state.entered`.
8. Update passport: `state.current = target`, `is_decision_pending = false`, append StepRecord (with `verdict: "decided"` as metadata), apply outputs mapping.
9. Save + regenerate mirror.
10. Return `{new_state, terminal, mirror_updated}`.

**`verdict: "decided"` on StepRecord:** This is a metadata field telling the audit trail "this step was a decision, not a task outcome." It is NOT a routing key — routing was done by the `routing_rule`. This is an engine-level verdict (like `pass`/`fail`), not PSC-specific.

**Security note:** The Security Reviewer noted that unifying would be better for access control (one entry point). However, the SW Engineer counters that two focused functions with distinct validation paths is cleaner and the security concern is addressed by requiring claim ownership for both.

---

### D-024: Passport vs Steps-Written Distinction — Data Architect Response

**Status:** PROPOSED — awaiting user decision

**The separation:**

| Aspect | Passport | StepArtifact |
|--------|----------|--------------|
| What it is | Runtime state — what the engine needs for the next routing decision | Outcome content — the full record of what one step produced |
| Size | Small, bounded | Large, unbounded (findings, recommendations, deliverables, references) |
| Load cost | Fast — single JSON read | On-demand — loaded only when content is required |
| Storage | `passports/<subject>.json` + SQLite `state_json` | `outcomes/<subject>/<step>/<uuid7>.json` on filesystem |
| Mutability | Mutated on every `advance()`; version-bumped | Immutable once written; never rewritten |
| Engine reads | `state.current`, `vars`, `retries_used`, `parallel_progress`, `step_log` (INDEX only), decisions, status flags | `verdict` via `step_log[].verdict` (no need to load artifact); artifact loaded only for queries/display |

**The passport's `step_log` is an INDEX, never a container.** Each entry holds enough metadata to (a) route without loading the artifact and (b) locate the artifact when needed. The artifact content never appears inline.

**Updated passport JSON (outcomes removed):**
- `outcomes` dict → **removed**. The `step_log` index + `load_outcome(outcome_ref)` is the single source of truth.
- `skips` array → **removed** (D-005 removed skip).
- `version_pins` → **removed** (D-023).
- `is_adhoc` → **removed** (D-025).
- `retries` → renamed to `retries_used` (D-022 — consumed only, not budget).
- `status` block → **added** (D-008 — cancelled/deferred/archived flags).
- `event_name` on each `step_log` entry → **added** (needed for audit from index alone).

**`vars` vs outcomes:**
- `vars` holds **projected** values the engine needs for routing (e.g., `findings[*].disposition` — just the disposition field, not the full Finding objects).
- The full Finding objects (with description, suggested_fix, references) live only in the StepArtifact.
- The mapping mechanism is `outputs.produced` (JSONPath read → JSON Pointer write to `vars`).

**Query model:**
- `query(subject_id, what="step_log")` → returns the index (fast, no artifact loading).
- `load_outcome(subject_id, uuid)` → loads a single StepArtifact (on demand).
- `query(subject_id, what="step_log", expand=true)` → index + inlined artifacts (for small logs; use sparingly).

**Logical data model (Mermaid ER):**
- `Subject 1—1 Passport` (runtime state)
- `Passport 1—N StepLogEntry` (index)
- `StepLogEntry N—1 StepArtifact` (via `outcome_ref`; join key = `uuid`)

**Flags raised by Data Architect:**
1. D-008: Terminal detection must check status flags (`cancelled`/`deferred`/`archived`), not just state kind. A subject with `cancelled: true` is terminal regardless of `state.current`.
2. D-008: `defer`/`cancel`/`archive` decisions need a transition `action` variant (status mutation), not just `target`. New mechanism — the `defer` decision in `route.c4` can't target `DEFERRED` (no such state). Raise as follow-up.
3. D-010: Idempotency key valid **only if** `step` includes `#specialist` suffix for parallel branches. Without the suffix, branches collide.
4. D-017: `additionalProperties`/`patternProperties` with object type + classification should be rejected at load time (primitives only).
5. D-022: `retries_used` should be lazily initialised (entries appear on first use), not pre-populated with all gates/tiers at 0.

---

### Security Reviewer — Validation of All Decided Points

| # | Decision | Verdict | Key Risk / Fix |
|---|----------|---------|----------------|
| 1 | D-001 atomicity+re-alignment+mirror flag | SECURITY IMPLICATIONS | Re-alignment must verify verdict against transitions before "correcting"; StepWriter must write inside the DB transaction; mirror flag must log `mirror.disabled` event and be deployment-time only, not per-request |
| 2 | D-005 remove skip | SECURE | Closes S27 (skip all gates); ensure `route.user_disposition` `skip` field and `Transition.skip` are actually removed from workflow JSON and dataclass |
| 3 | D-008 flags not states | SECURITY IMPLICATIONS | `cancelled_by` must be a verified principal, not self-reported; flag-setting must require claim ownership; flags must be append-only (no "un-cancel"); setting `cancelled: false` to resume must be forbidden |
| 4 | D-009 freeze context + deep-copy | SECURE | Join-merge must detect `vars` key collisions across branches and raise, not silently overwrite |
| 5 | D-010 deterministic idempotency key | SECURITY IMPLICATIONS | Predictable key enables adversarial pre-submission — attacker reads passport, pre-computes key, submits conflicting outcome; **fix:** bind key to caller nonce or require lease ownership before `advance()` |
| 6 | D-015 outcome_ref deletion graceful | SECURITY IMPLICATIONS | Deletion is an integrity violation, not a graceful state; log to events table; refuse to `advance` from states whose outcome is missing (can't re-verify verdict); acceptable for read ops but not for write/advance |
| 7 | D-016 project() handles additionalProperties | SECURE (conditional) | Only if `additionalProperties` defaults to non-`public`; current `field_schema is None` passthrough (S3) must be changed to omit/redact by default |
| 8 | D-017 classification on primitives only | SECURITY IMPLICATIONS | Safe only if `project()` recurses into object children unconditionally; current code passes undeclared keys through; **fix:** undeclared keys at any depth must default to non-`public` |

### Security Reviewer — Clarification Security Points

| # | Clarification | Verdict | Key Risk / Fix |
|---|-------------|---------|----------------|
| 9 | D-004 custom verdicts from profile | SECURITY IMPLICATIONS | Gate states may ONLY transition on engine-reserved verdicts (`pass`/`fail`/`exhausted`); profile verdicts cannot shadow reserved names; load-time validation required; a malicious profile injecting `skip_gate` verdict to bypass all gates must be rejected |
| 10 | D-007 per-state retry override | SECURITY IMPLICATIONS | Hard engine-level cap required (`ENGINE_MAX_DISPATCH_ATTEMPTS = 10`, `ENGINE_MAX_REENTRY_BUDGET = 10`); per-state overrides can reduce but not exceed; `max_attempts: 0` or negative rejected at load time |
| 11 | D-013 aggregation inside advance() | SECURITY IMPLICATIONS | Aggregation policy (`all` vs `quorum:N`) must be engine-reserved, not workflow-injectable; only threshold `N` is configurable and clamped to `[1, len(expected)]`; a malicious branch cannot inject composite verdict — aggregation rule is engine-controlled |
| 12 | D-014 unify record_decision with advance | SECURE (one entry point) | But SW Engineer recommends separate; security note: if separate, ensure `record_decision` also applies projection/redaction and writes a StepRecord (currently it doesn't write a StepRecord — audit gap) |

**Cross-cutting dependency:** The Security Reviewer flags that decisions 5, 7, 8, 9, 11 all depend on unresolved security gaps S1 (no auth model), S2 (fail-open default classification), S6 (no tamper-evidence), S10 (unauthenticated session_id). The engine cannot be considered secure until those are addressed. S1, S2, S6, S10 should be elevated to blocking dependencies before any of D-001/D-008/D-010/D-015 is marked IMPLEMENTED.

---

## Updated Progress Summary

| Reviewer | Total | Pending | Clarification Asked | Proposed (awaiting user) | Decided | Implemented |
|----------|-------|---------|--------------------|--------------------------|---------|-------------| 
| SW Engineer | 89 | 66 | 0 | 4 (D-004, D-007, D-011, D-013) | 21 (+2 new: x, xx) | 0 |
| Security | 36 | 32 | 0 | 0 | 4 (D-005, D-009, D-016, D-014) | 0 |
| Docs Writer | 23 | 23 | 0 | 1 (D-024) | 0 | 0 |
| **Total** | **148** | **121** | **0** | **5** | **25** | **0** |

### Items awaiting user decision (PROPOSED):

All 5 PROPOSED items have been decided — see Decisions Log Round 2 below.

### Items decided (awaiting implementation):

D-001, D-002, D-003, D-004, D-005, D-006, D-007, D-008, D-009, D-010, D-011, D-012, D-013, D-014, D-015, D-016, D-017, D-018, D-019, D-020, D-021, D-022, D-023, D-024, D-025, S1, S2, S3, S4, S5, S6, S7, S8, S9, S10.

### Security flags requiring follow-up:

- D-008: `cancelled_by` must be verified principal; flags append-only.
- D-010: Idempotency key must be caller-bound (nonce or lease ownership).
- D-013: Aggregation policy engine-reserved, not workflow-injectable.
- S1, S10 deferred to future security features.
- S6: Hash chain (blockchain-style) for tamper-evidence — D-026.

---

## Decisions Log — Round 2 (user decisions on proposals + security points)

### D-004: Verdict as NewType[str] + dynamic enum — ACCEPTED
**Decision:** Proposal accepted. Verdict is `NewType[str]`; engine knows `pass`/`fail`; transition keys are the source of truth. Gate states may only use engine-reserved verdicts.
**Date:** 2026-06-30
**Status:** DECIDED

### D-007: dispatch_retry vs reentry_budget — ACCEPTED
**Decision:** Proposal accepted. `dispatch_retry` (global, exponential backoff, per-state override) + `reentry_budget` (default 3, per-gate override). Gates have NO dispatch_handler/retry. `retry_policy` removed. Hard engine caps. Config in `psc_engine.yaml`.
**Date:** 2026-06-30
**Status:** DECIDED

### D-011: Remove _registry from State — ACCEPTED (Option c)
**Decision:** Proposal accepted. Remove `_registry` from `State`. Use `StateRegistry.is_ancestor(a, b)`.
**Date:** 2026-06-30
**Status:** DECIDED

### D-013: advance() absorbs parallel join+aggregation — ACCEPTED
**Decision:** Proposal accepted. `advance()` handles parallel internally. No public `aggregate_outcomes`. `returned` is a map. `join` is an object. Two schemas per parallel state.
**Date:** 2026-06-30
**Status:** DECIDED

### D-024: Passport = INDEX, StepArtifact = content — ACCEPTED
**Decision:** Proposal accepted. Passport = runtime state + step_log INDEX. StepArtifact = full outcome. `outcomes` dict removed. `vars` holds projected values. `load_outcome(outcome_ref)` for on-demand loading.
**Date:** 2026-06-30
**Status:** DECIDED

### D-015 CORRECTION: outcome_ref is the ACTUAL outcome, not convenience
**Decision:** CORRECTION from original D-015. `outcome_ref` is NOT "for convenience" — it's the **actual outcome** and should be handled carefully. The protocol should allow for a **string or byte array** as we might want to compress and store the outcome compressed. The **implementation decides** in what format the outcome is stored: in PostgreSQL it can be JSONB, in SQLite it can be a JSON-encoded string, etc. The `outcome_ref` is the reference to the stored outcome; the storage format is implementation-specific.
**Date:** 2026-06-30
**Status:** DECIDED (corrects D-015)

### D-015a: StepOutcome vs AgentOutcome — distinction
**Decision:** The user raises an important distinction: the **StepOutcome** (the data expected from a step/state, validated against the schema) is **different** from the **agent outcome or API outcome** (raw payloads saved for convenience). The `StepOutcome` is the validated, schema-conformant data the engine stores and uses. Raw agent/API payloads are a separate concern (audit/convenience). This needs to be clarified in the data model. The `outcome_ref` points to the StepOutcome (validated data), not the raw agent payload.
**Date:** 2026-06-30
**Status:** CLARIFICATION — needs design distinction between StepOutcome (validated, schema-conformant) and raw payload (agent/API raw output, stored for convenience)

### D-001 CORRECTION: re-alignment — steplog is source of truth, not mirror
**Decision:** CORRECTION from original D-001. The re-alignment was described wrongly. The **source of truth is the step_log**, NOT the mirror. The mirror can be regenerated from the step_log. The re-alignment process: if a StepRecord exists but the passport wasn't updated accordingly, it can correct the passport from the step_log. The mirror is derived from the passport/step_log and can always be regenerated. The `mirror.disabled` is a deployment-time global flag (not per-request, not per-workflow).
**Date:** 2026-06-30
**Status:** DECIDED (corrects D-001)

### D-001a: StepWriter is misaligned — storage is implementation-specific
**Decision:** The user flags that the ontology entry for StepWriter is wrong: "Computes the deterministic storage path for a step's outcome" implies filesystem only. A step's outcome is determined by the **implementation** — it can be a file OR a database record. The `OutcomeStore` protocol should abstract the storage; the implementation decides the format (file, PostgreSQL JSONB, SQLite JSON string, compressed bytes, etc.). StepWriter should be renamed to `OutcomeStore` and the protocol should allow string or byte array (for compression).
**Date:** 2026-06-30
**Status:** DECIDED

### D-016 UPDATED: Default to private (fail-closed)
**Decision:** UPDATED from original D-016. Default classification changes from `public` to **`private`**. All primitives default to `private` unless explicitly specified as `public` or `protected`. This is fail-closed. The `project()` function omits any field without an explicit `classification: "public"` or `classification: "protected"` keyword.
**Date:** 2026-06-30
**Status:** DECIDED (updates D-016, D-017, S2)

### D-017 UPDATED: Recurse + primitives default to private
**Decision:** UPDATED. `project()` must recurse into object children unconditionally. Classification applies to primitives only. All primitives default to `private` unless explicitly specified. This is combined with D-016's fail-closed default.
**Date:** 2026-06-30
**Status:** DECIDED

### D-008 UPDATED: How to track flag events without affecting original state
**Decision:** The user asks: do we track cancelled/deferred/archived events in another append-only log, or keep the same events log but add a category to differentiate state events from flags? 

**Answer (pending agent input):** This needs to be sent to the agents for a recommendation. The user's concern is that flag events (cancelled/deferred/archived) should NOT pollute the workflow state history — the history stays loyal to what actually happened. The flag is metadata about the subject, not a state transition.

Options:
(a) Separate append-only log for flag events (status_changes table)
(b) Same events log with a `category` field ("state_event" vs "status_flag")
(c) Flag events in the passport's `status` block with a timestamp + actor log

**Date:** 2026-06-30
**Status:** CLARIFICATION ASKED — send to agents

### D-009 UPDATED: Vars collision detection at workflow load time
**Decision:** The user adds: a check should travel the workflow and identify variables that have the same name and are present more than once as writable, and create a warning. This is a load-time validation: if two states both write to `$.findings` (via `outputs.produced`), a warning is generated. Not an error (both may legitimately contribute to the same key via merge), but a warning that a collision is possible.
**Date:** 2026-06-30
**Status:** DECIDED

### D-010 UPDATED: What is the proposed approach?
**Decision:** The user asks "what is the proposed approach" for the idempotency key security concern (predictable key enables adversarial pre-submission). The Security Reviewer proposed: bind key to caller nonce or require lease ownership. The user wants a concrete proposal.

**Answer (pending agent input):** Send to agents for a concrete design of the caller-bound idempotency key.

**Date:** 2026-06-30
**Status:** CLARIFICATION ASKED — send to agents

### D-007 UPDATED: Retry config in context or separate config object
**Decision:** The user adds: retry configs should be defined in the config, and either be included in the context or have an additional config object that the workflow uses for its own configuration. The workflow definition can reference the config by name; the engine resolves it at dispatch time. This keeps retry config out of the workflow JSON (which is the state machine, not infrastructure config).
**Date:** 2026-06-30
**Status:** DECIDED

### D-014 UPDATED: record_decision should write a StepRecord
**Decision:** The user confirms: `record_decision` stays separate (as the SW Engineer recommended) AND it should write a StepRecord. The Security Reviewer flagged that `record_decision` currently doesn't write a StepRecord — this is an audit gap. The user agrees: decisions must be in the step log.
**Date:** 2026-06-30
**Status:** DECIDED

### S1: Auth model — OUT OF SCOPE (future improvement)
**Decision:** Auth model is the responsibility of the application implementing the workflow or the API layer. Out of scope for now. Defence-in-depth to be added as future improvement.
**Date:** 2026-06-30
**Status:** DECIDED (deferred)

### S2: Default to private — DECIDED (covered by D-016 UPDATED)
**Decision:** Changed to `private` (fail-closed). Covered by D-016/D-017 UPDATED above.
**Date:** 2026-06-30
**Status:** DECIDED

### S3: Undeclared fields pass through — should be solved
**Decision:** Should be solved by D-016/D-017 (default to private). If not fully solved, flag again.
**Date:** 2026-06-30
**Status:** DECIDED (verify in implementation)

### S4: Fencing token for claim/lease — EXPLAIN
**Decision:** The user asks for an explanation of what a fencing token is. 

**Explanation (pending agent input):** A fencing token is a monotonically increasing number assigned to each claim. When session A's claim is reaped (TTL expired) and session B claims the subject, B gets a higher fencing token. If A then tries to write (its claim was reaped but it doesn't know), the write includes A's old token, which doesn't match B's current token — the write is rejected. Without a fencing token, A's stale write could succeed (it only checks `claimed_by == A`, which is no longer true after reaping, but if the write arrives before the reaper updates the row, it races). Send to agents for a concrete design.

**Date:** 2026-06-30
**Status:** CLARIFICATION ASKED — send to agents

### S5: Encryption at rest — implementation responsibility
**Decision:** Encryption is the responsibility of the implementation class (the `SubjectStore` / `OutcomeStore` implementation). The protocol doesn't mandate encryption; the implementation decides. Flag this as a design decision.
**Date:** 2026-06-30
**Status:** DECIDED

### S6: Tamper-evidence — hash chain (blockchain-style)
**Decision:** Add a hashing mechanism similar to blockchain: `row_hash = hash(current_data + hash_of_previous_row)`. Each event row includes the hash of the previous row, creating a chain. Tampering with any row breaks the chain. The user asks for this or an alternative.
**Date:** 2026-06-30
**Status:** DECIDED (D-026 — hash chain for events table)

### S7: Integrity checks and structural checks
**Decision:** There should be integrity checks and structural checks on workflow definitions, agent files, and outcomes. This covers: (a) workflow definition validation at load time (D-019), (b) agent file existence verification (already in RosterResolver), (c) outcome schema validation (already in advance). Additional: hash verification of workflow definitions and agent files at load time.
**Date:** 2026-06-30
**Status:** DECIDED

### S8: All data should be sanitised
**Decision:** As a principle, all data should be sanitised. This covers: (a) `subject_id` sanitisation (no path traversal — SW#88), (b) `step` sanitisation, (c) string field content validation (no control characters, max length), (d) path traversal prevention in StepWriter/OutcomeStore.
**Date:** 2026-06-30
**Status:** DECIDED

### S9: Adhoc workflow should be a workflow named "adhoc"
**Decision:** The user asks: "adhoc workflow should be a workflow named adhoc. is that agreed?" — This aligns with the existing design (`workflow_id: "psc-adhoc"`). The workflow is named `psc-adhoc` (or just `adhoc`). No access control on who can create adhoc subjects (S1 is out of scope). Confirmed: adhoc is a workflow definition, not a special mode.
**Date:** 2026-06-30
**Status:** DECIDED

### S10: Unauthenticated session_id — future security feature
**Decision:** Added to future security features. The `session_id` authentication is deferred along with S1 (auth model). For now, `session_id` is caller-supplied; this is acceptable for the prototype.
**Date:** 2026-06-30
**Status:** DECIDED (deferred)

---

## Updated Progress Summary (Round 2 — final)

| Reviewer | Total | Pending | Clarification Asked | Decided | Implemented |
|----------|-------|---------|--------------------|---------|-------------| 
| SW Engineer | 89 | 63 | 0 | 26 | 0 |
| Security | 36 | 0 | 0 | 36 | 0 |
| Docs Writer | 23 | 23 | 0 | 0 | 0 |
| **Total** | **148** | **86** | **0** | **62** | **0** |

### All clarifications resolved:

1. **D-008:** Separate `status_log` table (option a) — own hash chain, clean separation from step_log. PROPOSED.
2. **D-010:** Keep bare-tuple key + enforce claim gate as hard precondition. Key is correctness mechanism, not auth. PROPOSED.
3. **D-015a:** StepOutcome (validated) vs RawPayload (forensic). Both in OutcomeStore with `kind` discriminator. `outcome_ref` → StepOutcome. PROPOSED.
4. **S4:** Fencing token (`claim_epoch`) on subjects table. `claim()` returns token. All writes CAS on `claim_epoch`. PROPOSED.

### New decisions from agent proposals (awaiting user confirmation):

- **D-026:** Hash chain (blockchain-style) for events table tamper-evidence — `row_hash = H(prev_hash, row_data)`.
- **D-027:** Separate `status_log` table for flag events (cancelled/deferred/archived) — own hash chain, clean separation.
- **D-028:** Idempotency key stays bare tuple `(subject_id, step, entry_count, attempt)`. Claim gate is the auth boundary, not the key.
- **D-029:** StepOutcome (validated, schema-conformant) vs RawPayload (forensic, optional). Both in OutcomeStore with `kind` field. `outcome_ref` → StepOutcome. `raw_ref` → RawPayload (nullable).
- **D-030:** Fencing token (`claim_epoch`) on subjects table. `claim()` returns token. `save()` CAS on version AND claim_epoch. `LeaseLostError` on mismatch.
- **D-031:** `StepWriter` renamed to `OutcomeStore` (implementation-specific storage: file, JSONB, compressed bytes). Protocol allows string or byte array.
- **D-032:** Default classification is `private` (fail-closed). All primitives default to private unless explicitly `public` or `protected`.
- **D-033:** Retry config (`dispatch_retry` + `reentry_budget`) defined in `psc_engine.yaml`, included in context or referenced by the workflow.

---

## Agent Responses to Round 2 Clarifications

---

### D-008: Flag Event Tracking — Architect Response

**Recommendation:** Option (a) — Separate `status_log` table (append-only, own hash chain).

**Three options evaluated:**

| Option | Pros | Cons |
|--------|------|------|
| (a) Separate `status_log` table | Clean separation; `step_log` stays pure; independent hash chain; queries can't accidentally return flags | Two tables, two chains; full ordered history needs UNION |
| (b) Same `events` table with `category` field | Single hash chain; one table; minimal schema | **Pollutes the step_log** — violates the principle; every query needs `WHERE category='state_event'`; sparse rows |
| (c) Passport `status` block with embedded `history[]` | Locality; no new table | Unbounded array growth; loses row-level tamper-evidence; cross-passport queries need full scan |

**Recommended schema:**
```sql
status_log (
  id          SERIAL,
  subject_id  TEXT REFERENCES subjects(id),
  flag        TEXT,          -- cancelled | deferred | archived | restored
  actor       TEXT,          -- session/agent id
  reason      TEXT,
  ts          TEXT NOT NULL,
  prev_hash   TEXT,          -- hash chain
  hash        TEXT           -- H(prev_hash, row fields)
)
```

**Key principle:** `step_log` records **state transitions** (what the state machine did). `status_log` records **flag changes** (metadata about the subject). Two distinct queries → two distinct stores. The flag is metadata, not a state transition.

---

### D-010: Caller-Bound Idempotency Key — Architect Response

**Recommendation:** Keep the bare-tuple key `(subject_id, step, entry_count, attempt)`. Enforce claim ownership as a hard precondition of `advance()`. Do NOT bind `claim_id` into the key.

**Key insight:** The predictable key is only exploitable if `advance()` is callable *without* a claim. If `advance()` enforces a valid active claim as step 1 (before the idempotency check), an attacker who lacks the lease is rejected at the auth gate, before the idempotency key is consulted. The predictable key is never reachable by an un-leased caller.

**Analysis of binding `claim_id` into the key:**

| Approach | Closes pre-submission? | Retry semantics | Complexity |
|----------|----------------------|-----------------|------------|
| Bare tuple + claim gate enforced | ✅ Yes (gate blocks un-leased callers) | Stable across retries | Lowest |
| Bind key to `claim_id` | ✅ Yes (belt-and-suspenders) | **Breaks if lease rotates mid-retry** — new `claim_id` → new `K` → not deduped | Higher |
| Per-dispatch caller nonce | ✅ Yes | Breaks retry entirely (new nonce each call) | Highest |

**The `claim_id`-bound key breaks retry semantics:** a legitimate retry after a transient lease expiry + re-acquire would compute a different key and fail to dedup — coupling idempotency (correctness) with lease lifetime (liveness).

**Decision:** The idempotency key is a **correctness mechanism** for retry/replay deduplication, NOT an authorization control. Authorization to advance is enforced exclusively by the active-lease check. Document this explicitly. If a future architecture relaxes the claim gate, bind `claim_id` at that point.

---

### D-015a: StepOutcome vs RawPayload — Data Architect Response

**Distinction:**

| Entity | What it is | Mandatory | Read by engine |
|--------|-----------|-----------|----------------|
| **StepOutcome** | Validated, schema-conformant record (verdict + decision + confidence + validated payload fields). Exists only AFTER schema validation passes. | **Mandatory** for every completed step | Yes — routing reads `verdict` and `validated_fields` |
| **RawPayload** | Unprocessed bytes from the DispatchHandler (agent text, HTTP response, form submission) BEFORE normalization/validation. Forensic evidence. | **Optional** but strongly recommended; MANDATORY when validation fails (no StepOutcome exists) | No — never read by routing; only by auditors, challengers, replay tools |

**Storage:** Both stored in `OutcomeStore` with a `kind` discriminator (`step_outcome` vs `raw_payload`). Implementation decides format (PG JSONB, SQLite JSON, compressed bytes).

**`outcome_ref` → StepOutcome** (the validated canonical). `raw_ref` → RawPayload (nullable, separate).

**Data model:**
```
step_log
  ├── outcome_ref ──────► StepOutcome ──► raw_ref ──► RawPayload
  └── raw_ref (nullable) ─────────────────────────► RawPayload
```

- `outcome_ref` set on successful validation. Null if validation failed.
- `raw_ref` on `step_log` set whenever a raw payload was captured, regardless of validation outcome. Covers the `validation_failed` case where `outcome_ref = null` but `raw_ref` is populated.
- When both exist, they resolve to the **same** RawPayload.

**RawPayload fields:** `source_type` (agent_response/api_response/human_submission/webhook_callback/system_event), `content_type`, `encoding` (utf8/gzip/base64), `body` (string|byte[]), `metadata` (http_status, agent_model, token_count), `checksum` (sha256 of original body).

**Compression:** StepOutcome uncompressed (structured JSON, engines query it). RawPayload compressed when `len(body) > threshold` (default 4KB); `gzip` for text/JSON.

**Redaction:** Raw payload redaction happens BEFORE storage. `checksum` computed on the redacted body.

**Key invariant:** `outcome_ref` is NEVER set unless schema validation passed. If validation fails, `outcome_ref = null` and step status is `validation_failed`; `raw_ref` MUST be populated.

---

### S4: Fencing Token — Security Reviewer Response

**What is a fencing token?** A monotonically increasing integer (`claim_epoch`) assigned to each successful `claim()`. Every time a session wins `claim()`, it receives a token strictly greater than the previous holder's. The token must be presented on every subsequent write.

**Distinct from the `version` CAS counter:**
- `version` tracks **state changes** (every `save()`). Purpose: optimistic concurrency on the same valid lease.
- `claim_epoch` tracks **claim ownership generation** (every `claim()`). Purpose: stale-lease rejection.

Both are needed. Neither subsumes the other.

**The write-after-reap corruption scenario (without fencing token):**
1. Session A claims subject → `claimed_by = A`, `claim_epoch = 1`
2. A begins long work (slow LLM call)
3. TTL expires; reaper clears `claimed_by = NULL` (but doesn't touch `claim_epoch`)
4. Session B claims → `claimed_by = B`, `claim_epoch = 2`
5. B writes new state → version 3→4
6. A finishes, calls `save(version=3)` — without fencing token, A's write might succeed (overwriting B's state)

**With fencing token:**
6. A calls `save(version=3, claim_epoch=1)` → `WHERE claim_epoch = 1` doesn't match (row has `claim_epoch = 2`) → 0 rows updated → `LeaseLostError` raised.

**Schema:**
```sql
ALTER TABLE subjects ADD COLUMN claim_epoch INTEGER NOT NULL DEFAULT 0;
```

**Claim (returns the token):**
```sql
UPDATE subjects
  SET claimed_by = :session_id, claimed_at = :now,
      claim_epoch = claim_epoch + 1
  WHERE id = :subject_id
    AND (claimed_by IS NULL OR claimed_at < :cutoff)
RETURNING claim_epoch;
```

**Save (CAS on version AND claim_epoch):**
```sql
UPDATE subjects
  SET state_json = :passport_json, active_steps = :active_steps,
      version = version + 1, updated_at = :now
  WHERE id = :subject_id
    AND version = :expected_version
    AND claim_epoch = :presented_token;
```

**Reaper does NOT touch `claim_epoch`** — only nulls `claimed_by`/`claimed_at`. The next `claim()` increments past the reaped session's token.

**Protocol change:**
- `claim()` returns `int | None` (the token) instead of `bool`
- `save()` gains `claim_epoch: int` parameter
- All write paths (`save`, `advance`, `record_decision`) must thread the token

**Errors:**
- `LeaseLostError` — `claim_epoch` mismatch (non-retryable; must re-claim and recompute)
- `ConcurrentWriteError` — `version` mismatch but `claim_epoch` matched (retryable)

**Example scenario (concrete):**
```
T0  A claims S1 → token 1. A begins long review.
T2  TTL expires. Reaper nulls claimed_by (claim_epoch stays 1).
T3  B claims S1 → token 2. B reads S1 (version=3), computes new state.
T4  B saves(version=3, token=2) → version 4. ✓
T5  A saves(version=3, token=1) → 0 rows (claim_epoch=2≠1) → LeaseLostError.
T6  A re-claims S1 → token 3. Re-reads (version=4), recomputes, saves(token=3) → version 5. ✓
```

**Corruption prevented:** Without the token, A's stale write at T5 could overwrite B's state (version CAS might match if B hadn't written yet, or if the JSON store uses flock read-then-write which doesn't enforce `claimed_by` atomically). With the token, A's write is rejected atomically.