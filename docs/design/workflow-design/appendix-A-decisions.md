# Appendix A — Design Decision Log

> **Status:** APPENDIX (not part of the main design). Historical record of
> the design decisions taken across three review rounds (round 1: 148 review
> points, round 2: 483 findings, round 3: 327 findings + 33 Q-decisions).
> Only the **outcomes** are recorded here — alternatives considered and
> reviewer counter-statements have been dropped. For the full audit trail,
> see the git history of `07-review-analysis*.md` before commit
> `feature/workflow-engine`.
> **Purpose:** allow a future reader to trace any element of the design
> back to the decision that produced it.

---

## A.1 Reading This Log

- Each decision is one line: **ID → description → source finding**.
- `D-###` are round-1 decisions from the SW engineer's numbered list.
- `#N` are decisions numbered in the round-1 SW engineer response set.
- `S#` and `D#` and `Doc#` are round-1 security / docs / test findings.
- `Q#` are round-3 questions the user answered.
- Every ID is grep-friendly across the design docs.

---

## A.2 State Machine

| ID | Decision |
|----|----------|
| D-001 | `step_log` is the source of truth for re-alignment; passport corrected from `step_log`; mirror regenerated from passport; `mirror.disabled` is a deployment-time global flag |
| D-005 | `skip` semantics removed entirely — workflows must model alternative paths explicitly |
| D-006 | Routing rules unified to SQL-CASE-style (`CASE WHEN ... THEN ... ELSE ... END`) |
| D-007 | Two independent budgets: `dispatch_retry` (transient failures, exponential backoff) and `reentry_budget` (gate loop-back). Gates have NO `dispatch_handler` |
| D-008 | Cancelled / deferred / archived are **status flags** on the passport, not synthetic terminal states. Flag events live in a separate `status_log` table |
| D-011 | `State._registry` removed; `StateRegistry.is_ancestor(a, b)` is a free function on the registry |
| D-013 | `advance()` absorbs parallel fan-out → join → aggregation. No public `aggregate_outcomes` API. Return shape carries `join_satisfied` + `pending` |
| D-014 | `record_decision` is a first-class function separate from `advance`. Writes a `StepRecord` with `verdict: "decided"` |
| D-018 | Gate tier evaluation is sequential; first-fail triggers loop-back to the correction state |
| Q1 | Gates emit only `pass` / `fail` / `exhausted`. CR2 (`accept` / `request_changes`) renamed to `pass` / `fail` in workflow JSON; same for `psc-adhoc` CR2L |
| Q2 | Every user-facing decision is a **two-state pair**: a `task` that PROPOSES, followed by a `decision_required` that CONFIRMS. Pairs in `psc-main`: A0→A0c, A2c→A2cc, C4p→C4. Adhoc: A0L→A0Lc |
| Q6 | `State.aggregation_rule: str \| None` field; required at load time for `kind == "parallel"` |
| Q7 | `Transition.verdict` field kept for ergonomics + load-time invariant `assert key == transition.verdict` |
| Q9 | Parallel `vars` merge is strict — collisions raise `VarsCollisionError`. Use branch-namespaced `outputs.produced` (`/branches/{branch_id}/...`) to avoid collisions |
| Q10 | `StateKindMismatchError(WorkflowError)` raised when an operation does not match the current state's kind |
| Q12 | `FanOut = FanOutStatic \| FanOutDynamic` discriminated union (JSON form unchanged; parsed representation typed) |
| Q26 | `JoinConfig = JoinAll \| JoinQuorum(n, on_satisfied)` discriminated union |
| Q27 | `StepOutcome.verdict` has NO default — every construction requires an explicit verdict |

## A.3 Verdicts

| ID | Decision |
|----|----------|
| D-002 | `AgentOutcome` replaced by `StepOutcome` (agnostic to actor kind — agent/human/system) |
| D-003 / D-004 | `Verdict = NewType("Verdict", str)` — open set validated by JSON Schema, not a fixed enum. Engine reserves `pass` / `fail` / `exhausted`; projects extend via transition keys |
| D-012 | `Transition.outcome` renamed to `verdict` with type `Verdict` |
| D-015 (corrected) / D-015a | `outcome_ref` → validated `StepOutcome`; `raw_ref` → unprocessed `RawPayload`. Both stored in `OutcomeStore`. `raw_ref` is MANDATORY when validation fails (no `StepOutcome` exists) |
| #34 | Verdict is `NewType[str]`; engine knows `pass`/`fail`; transition keys are source of truth |

## A.4 Data Classification & Security

| ID | Decision |
|----|----------|
| D-016 | `project()` handles `additionalProperties` and `patternProperties`; `unevaluatedProperties` rejected at load time. Fail-closed default: undeclared fields default to `private` |
| D-017 | Classification applies to **primitives only**; objects are not classified as a whole — their child fields are classified individually |
| D-018 (repurposed) | Redactors are TDD-mandated |
| D-019 | Load-time validation is TDD-mandated |
| Q4 | Cross-subject listing lives on `list_subjects(filter: SubjectListFilter, limit, offset)`; `query()` is per-subject only |
| Q17 | `WorkflowService.verify_chain(subject_id, include_status_log=True)` returns `ChainVerificationResult`. CLI subcommand `psc verify` deferred to Phase 3 |
| Q18 | Two-tier `subject_id` validation: engine minimum `^[A-Z0-9_-]{4,64}$`; profile MAY tighten (PSC uses `^[A-Z]{3,4}-[0-9]{4,}$`). Load-time asserts profile ⊂ engine |
| Q19 | `psc_engine.yaml → projection.max_depth: 50`. `ProjectDepthExceeded(WorkflowError)` raised on breach |
| Q20 | `ENGINE_RESERVED_VARS_PATHS` frozenset; handler writes to reserved paths raise `ReservedVarsPathError` |
| Q22 | Snapshotted workflow definition is integrity-checked: `subjects.workflow_definition_hash` + `workflow_definitions.definition_hash`; verified at load |
| SCG-1 | Hash chain formula named: `row_hash = sha256(prev_hash || canonical_json(row_data))` (RFC 8785 JCS). Genesis: `sha256("GENESIS:" || workflow_id || ":" || subject_id)` |

## A.5 Storage & Persistence

| ID | Decision |
|----|----------|
| D-024 | Passport = runtime state + `step_log` INDEX. `StepArtifact` = full outcome content. `outcomes` dict removed from passport |
| D-030 | Fencing token: `claim()` returns `ClaimResult{claim_epoch}`. All writes CAS on `version` AND `claim_epoch` |
| D-031 | `StepWriter` renamed to `OutcomeStore`; format is implementation-specific (JSON file / PG JSONB / SQLite JSON / compressed bytes) |
| #26 | Events hash chain: tamper-evidence via `row_hash = H(prev_hash, row_data)` |
| #27 | Separate `status_log` table for status-flag events (own hash chain, engine-managed `prev_hash`) — Q29 confirms engine-managed |
| Q3 | `EventRecord` unified into `StepRecord` with optional `prev_hash` / `row_hash` populated on read |
| Q11 | `VerdictSchemaBuilder` lives in `infrastructure/schema/`, not in the domain layer |
| Q29 | `StatusLog.append(subject_id, flag, actor, reason) → StatusLogEntry` — engine-managed `prev_hash` (no caller-supplied hash) |
| Q30 | `InflightSubject.workflow_version` added (saves a round-trip when re-loading definition) |
| Q31 | `OutcomeRef = NewType("OutcomeRef", str)`; `RawRef = NewType("RawRef", str)` |
| Q32 | `workflow_definitions.profile_version` denormalised column; queryable |
| Q33 | `StatusLog.load_status` returns `list[StatusLogEntry]` (frozen dataclass, not `list[dict]`) |

## A.6 Concurrency & Claims

| ID | Decision |
|----|----------|
| D-009 | `Context` is frozen; `vars` deep-copied per parallel branch; merged at join time under engine control |
| D-010 | Idempotency key is a correctness (not authorization) mechanism. Q14 supersedes the formula. Auth boundary is the claim gate |
| Q14 | Idempotency key: `"sha256:" || hex(sha256(canonical_json({"v": 1, "subject_id": ..., "step": ..., "entry_count": ..., "attempt": ...})))` |
| Q21 | Claim TTL 300s (config). `WorkflowService.claimed(...)` context manager provides auto-heartbeat via a background thread; `SubjectClaimStore.heartbeat()` protocol method exists |
| #4 (round 1) | Lease + reaper with TTL; reaper does NOT touch `claim_epoch` — only nulls `claimed_by`/`claimed_at` |
| **CLM-1** | `SUBJECT_STALE_REAPED` removed from `EngineEvent` — a reaper release is a `SUBJECT_RELEASED` event with `reason == ReleaseReason.LEASE_TTL_EXCEEDED` and `actor == "system:reaper"`. Downstream consumers discriminate by payload, not by event type |
| **CLM-2** | `ClaimReason(StrEnum)` added: `CALLER_INITIATED` / `RECLAIM_AFTER_REAP` / `SYSTEM_INITIATED` / `FORCED_BY_ADMIN`. Passed to `claim()` / `claimed(...)` |
| **CLM-3** | `ReleaseReason(StrEnum)` added: `CALLER_INITIATED` / `LEASE_TTL_EXCEEDED` / `FORCED_BY_ADMIN` / `SESSION_TERMINATED`. Passed to `release()` / attached by reaper |
| **CLM-4** | New `claim_log` table + `ClaimLog` protocol + `ClaimLogEntry` dataclass. Own hash chain (same formula as `events` and `status_log`). Records ownership transitions only (CLAIMED / RELEASED) — heartbeats update `subjects.claimed_at` in place and are NOT logged |
| **CLM-5** | `SubjectClaimStore` signatures updated: `claim(subject_id, session_id, reason=CALLER_INITIATED, lease_ttl_seconds=300)`, `release(subject_id, session_id, reason=CALLER_INITIATED)`, `reap_stale_claims(lease_ttl_seconds)` internally uses `ReleaseReason.LEASE_TTL_EXCEEDED` |
| **CLM-6** | `QueryWhat.CLAIM_LOG` selector + `ClaimLogResult` result type — per-subject ownership history is queryable via `WorkflowService.query(subject_id, QueryWhat.CLAIM_LOG)` |
| **CLM-7** | Firing rules (§4.9.2): `SUBJECT_CLAIMED` after `claim_log.append(CLAIMED)` commits; `SUBJECT_RELEASED` after `claim_log.append(RELEASED)` commits (both `release()` and reaper paths). Heartbeats fire NO hook |

## A.7 API Contracts

| ID | Decision |
|----|----------|
| #66 | `route_for_outcome(subject_id, outcome) → RoutePreview` — read-only preview of `advance()` routing |
| #67 | `validate_passport(subject_id) → ValidationResult` — checks step_log integrity, state reachability, `parallel_progress` consistency, `retries_used ≤ budget`, `vars` schema conformance, status flag consistency, `claim_epoch` validity |
| #73 | `agent` field replaced by `role` (orchestrator / architect / reviewer) — mapped to concrete agent/human/service via profile |
| Q13 | `new_subject(domain_signals: list[str])` required; `propose_roster(domain_signals: list[str] \| None = None)` optional — asymmetry is intentional (new_subject initialises, propose_roster reads) |
| Q15 | `QueryResult` becomes a discriminated union: `StepLogResult`, `StatusLogResult`, `DecisionsResult`, `VarsResult`, `GateResultsResult`, `CorrectionsResult`, `LoopHistoryResult`, `ParallelProgressResult`, `FullResult` |
| Q16 | `DispatchHandler.dispatch(state, ctx) → StepOutcome \| RawPayload` — validation failure signalled by returning `RawPayload`; transport failure raises `DispatchError` |
| Q23 | `WorkflowService.load_workflow_for_subject(subject_id) → WorkflowDefinition` convenience method (reads pinned version from passport + verifies hash) |
| Q24 | `WorkflowService` remains a monolith (cohesion outweighs size; revisit if methods > 25) |
| Q25 | `AggregationRule.aggregate(state, returned: dict) → dict` — dicts validated by JSON Schema (no typed dataclasses) |

## A.8 Schemas & Types

| ID | Decision |
|----|----------|
| D-021 | `passport.base` JSON Schema — validated on every `SubjectStore.load` |
| D-022 | Store `retries_used`; derive budget from snapshotted workflow definition. Lazy init (entries appear on first use) |
| D-023 | Drop `version_pins`; keep only `workflow_version` |
| D-025 | Drop `is_adhoc`; derive from `workflow_id` |
| #62 | `RosterProposal` dataclass |
| #63 | `WorkflowDefinition` return type (frozen dataclass + StateRegistry) |
| #64 | `CurrentStateResult` return type |
| #65 | `QueryWhat` enum |
| #83 | `WorkflowDefinitionRecord` return type |
| #48 | `SignalMatcher` protocol (case-fold matching, pluggable) |
| #79 | `ConfigPort` protocol + `Config` frozen dataclass (DIP separation) |
| Q5 | `OutcomeStore` sub-protocols (`StepPathResolver`, `OutcomeRepository`, `StepRecordFactory`) remain implementation-internal to `infrastructure/outcome_store/` — NOT exposed as domain protocols |
| Q28 | `profile.base` JSON Schema added (top-level: `$id`, `version`, `schemas`, `aggregation_rules`, `signals`, `role_mapping`, `redactors`) |

## A.9 Lifecycle & Events

| ID | Decision |
|----|----------|
| #24 (round 1) | Implicit start: `WORKFLOW_STARTED` event + transition to `start_at`; no `__START__` node |
| #25 | Terminal detection: `kind: "terminal"` OR no transitions → `WORKFLOW_COMPLETED`; no `__END__` node |
| #26 | Cancel is an external signal (`cancel_subject` API); sets `cancelled: true` status flag; fires `WORKFLOW_CANCELLED`; abrupt (no `STATE_EXITED` for the abandoned state) |
| #27 | Mandatory `event_name` on every transition (Kafka-topic-safe pattern); validated at load time |
| #28 | Generic `subject.*` prefix in `event_name`, replaced with actual `subject_type` at dispatch time |
| #23 | Lifecycle hooks: global, fire-and-forget, exception-safe. Critical hooks fail-closed via `HookErrorSink`. Built-ins: LoggingHook, ObservabilityHook, EventDispatchHook. `AuditHook` dropped — `EventStore` IS the audit trail |
| #39 | Hook order: write `StepRecord` + update passport BEFORE hooks. Sequence: `state.exited` → domain event_name → `transition.triggered` → `state.entered` |
| #40 | Terminal hooks: `state.entered` first, then terminal event; cancel: only `workflow.cancelled` |

## A.10 Testing

| ID | Decision |
|----|----------|
| D-020 | `08-testing-strategy.md` — comprehensive test plan (created round 2) |
| TR-1 | Test organisation mirrors `psc_engine/` Clean Architecture layers (`tests/domain/`, `tests/application/`, `tests/infrastructure/`, `tests/integration/`, `tests/property/`) |
| Test scope from Q1-Q33 (to be added when Phase 1 begins) | Q2 propose/confirm walk-throughs; Q9 VarsCollisionError with branch namespacing; Q10 StateKindMismatchError; Q14 versioned key determinism; Q17 verify_chain happy + tampered; Q19 ProjectDepthExceeded; Q20 ReservedVarsPathError; Q21 heartbeat auto-refresh; Q22 workflow_definition_hash verification; Q26 JoinQuorum modes; Q29 StatusLog prev_hash management; Q31 OutcomeRef/RawRef type-checks |

## A.11 Parked Item

| ID | Item |
|----|------|
| **Q8** | `Context.input` source semantics — user asked to defer. Three candidates recorded for future review: (a) engine pre-resolves `state.inputs.required` JSONPath into `ctx.input`, (b) remove `ctx.input` entirely (handlers read `ctx.vars`), (c) `ctx.input` carries dispatch envelope metadata (subject_id, prior refs, attempt). Until decided, handlers MUST NOT rely on `ctx.input` being populated |

---

## A.12 Round-Level Counts (for historical reference)

| Round | Reviewers | Total findings | Fixes applied | Decisions | Deferred | False positives |
|-------|-----------|----------------|---------------|-----------|----------|-----------------|
| 1 | 3 (SW / Security / Docs) | 148 | ~50 in the round | 25 (D-001..D-025) + ~130 sub-decisions | ~30 to future security backlog | n/a (initial round) |
| 2 | 5 (Docs / Test / SW / Security / Data) | 483 (88 critical + 316 gaps + 32 challenges + 36 recs + 11 proposals) | 16 in round 2 | — | 237 | 71 (stale-snapshot) |
| 3 | 5 (same) | 327 | 22 straightforward + 29 decision-driven | 33 Q-decisions | ~150 (mostly test-strategy items) | ~20 |

For the full trace-back including reviewer critique, alternative proposals,
and reviewer-by-reviewer analysis, use `git log --all
docs/design/workflow-design/07-review-analysis*.md` prior to the commit
where those files were removed.
