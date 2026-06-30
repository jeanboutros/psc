# META-PROMPT: Update Design Document + Validation Review

## Context

You are working on the PSC (Politburo Standing Committee) workflow engine design. The design document set lives at `docs/design/workflow-design/` (7 files: 00-README through 06-references, plus 07-review-analysis). A three-agent review (SW Engineer, Security Reviewer, Docs Writer) produced 148 review points, ALL of which have been decided in `07-review-analysis.md`.

## Your Task

You have TWO phases to complete, IN ORDER:

### PHASE 1: Update the design documents

Read `docs/design/workflow-design/07-review-analysis.md` — it contains all 148 decisions. Update the 6 design files (01 through 06) to implement every decision. Key changes to make:

**Architecture & Semantics (02-high-level-design.md):**
- Replace `AgentOutcome` with `StepOutcome` everywhere in engine-level spec (D-002). `AgentOutcome` only in PSC profile.
- Verdict is `NewType[str]`, not a fixed enum. Engine knows `pass`/`fail` only (D-004). Dynamic JSON Schema enum via `VerdictSchemaBuilder`.
- Remove `skip` from `Transition` and all references (D-005, #4). Remove `skips` from passport.
- Routing rules unified to SQL-CASE-style (D-006). `route.c4` becomes normal transitions. Routing rules only for conditional evaluation: `CASE WHEN condition THEN target; ELSE default; END`.
- Cancelled/deferred/archived are STATUS FLAGS on passport, NOT synthetic terminal states (D-008, #7). No `CANCELLED`/`DEFERRED` in the states map.
- Freeze `Context`; deep-copy `vars` per parallel branch (D-009, #8).
- Deterministic idempotency key = `sha256(subject_id + step + entry_count + attempt)` (D-010, #9). Document claim gate is the auth boundary, key is correctness mechanism (D-028).
- Remove `_registry` from `State`; use `StateRegistry.is_ancestor(a, b)` (D-011, #25).
- Rename `Transition.outcome` to `verdict` (D-012, #11).
- `advance()` absorbs parallel join+aggregation internally (D-013). No public `aggregate_outcomes` API.
- `record_decision` stays separate (D-014). It MUST write a StepRecord.
- Default classification is `private` (fail-closed) (D-016/D-017/D-032, #78). All primitives default to private unless explicitly `public` or `protected`.
- `project()` recurses into objects; classification on primitives only; undeclared fields default to private (D-016/D-017, S3).
- Pluggable dispatch handlers (D-007, #6). Gates have NO `dispatch_handler`, NO `retry`. `dispatch_retry` (global + per-state, exponential backoff) vs `reentry_budget` (default 3, per-gate). `retry_policy` removed.
- Lifecycle hooks: `on_event(event: str, context: dict)`. Engine events + domain event_name. Write before hooks fire (#39). Critical hooks (audit) fail-closed (#36). Drop AuditHook (#37).
- Mandatory `event_name` on every transition including routing_rule branches (D-013, #58). `subject.*` prefix replaced at runtime.
- Load-time validation: `WorkflowDefinitionError` for missing event_name, unknown targets, unresolvable schemas/handlers, cyclic forward-DAG, missing start_at, no terminal, phase FK, name==dict_key, gate states must not have dispatch_handler/retry (D-014, #18, #70, #71).
- Fencing token (`claim_epoch`) on subjects table (D-030, S4). `claim()` returns token. All writes CAS on version AND claim_epoch. `LeaseLostError` on mismatch.
- Hash chain for events table (D-026, S6): `row_hash = H(prev_hash, row_data)`.
- Separate `status_log` table for flag events (D-027, D-008). Own hash chain. Clean separation from step_log.
- `StepWriter` renamed to `OutcomeStore` (D-031, #76). Protocol allows string or byte array. Implementation decides format (PG JSONB, SQLite JSON, compressed). Split into StepPathResolver + OutcomeRepository + StepRecordFactory.
- `StepOutcome` (validated, schema-conformant) vs `RawPayload` (forensic, optional) (D-015a, D-029). Both in OutcomeStore with `kind` discriminator. `outcome_ref` → StepOutcome. `raw_ref` → RawPayload (nullable).
- Snapshot workflow definition only (NOT agents) (D-004). Agents resolved from `agents_folder` at dispatch time. If agent changes, issue warning (#47).
- `agent` field moved to profile as abstract roles (orchestrator/architect/reviewer). Role maps to agent, human, or service (#73).
- A0 becomes `decision_required` with `decision.roster_confirmation` (#61). Document task vs decision_required difference clearly.
- `Context.is_retry` split into `is_loop_back` (entry_count>1) + `is_retry` (attempt>0) (#27).
- Split `SubjectStore` into `SubjectReader`/`SubjectWriter`/`SubjectClaimStore` (#77).
- `ConfigPort` protocol in domain; `Config` in infrastructure (#79).
- Full exception hierarchy: `WorkflowError(base)` + `WorkflowDefinitionError`, `RoutingError`, `GateExhaustedError`, `DispatchError`, `IncomparableStates`, `SubjectNotFoundError`, `PassportValidationError`, `LeaseLostError`, `ConcurrentWriteError`, `HandlerNotRegistered`, `RedactorNotRegisteredError` (#51, S18).

**Data Model (03-data-model.md):**
- Remove `outcomes` dict from passport (D-024). `step_log` is the INDEX. `load_outcome(outcome_ref)` for on-demand loading.
- Remove `skips`, `version_pins`, `is_adhoc`, `stamp` from passport.
- Rename `retries` to `retries_used` (lazy init, entries on first use only) (D-022).
- Add `status` block: `{cancelled: false, deferred: false, archived: false}` (D-008).
- Add `event_name` on each `step_log` entry.
- Add `idempotency_key` on `StepRecord`.
- Add `claim_epoch` column to `subjects` table (D-030).
- Add `status_log` table (D-027).
- Add hash chain columns to `events` table (D-026).
- Add `subjects_summary` table for fast queries (#84).
- Add index on `subjects.claimed_at` (#85).
- `PRAGMA foreign_keys = ON` (#86).
- `gate_config.reentry_budget` replaces `retry_budget` (D-007).
- `dispatch_retry` config in `psc_engine.yaml` (D-007, D-033).
- `reentry_budget` config in `psc_engine.yaml` (D-007, D-033).
- Remove `retry_policy` from workflow JSON (D-007, #69).
- Remove `max_review_rounds` from workflow JSON (#54). Keep `round_budget` on gate.
- JSON Pointer keys + JSONPath values for `outputs.produced` (#44).
- Fix JSONPath filter syntax per RFC 9535 (#45).
- Profile versioning: `psc-profile.json` carries SemVer; workflow pins `profile_version` (#46).
- `gate_config.base` JSON Schema (#68).
- `passport.base` JSON Schema (D-021).
- `decision.user_disposition` schema defined (#60).
- `decision.roster_confirmation` schema defined (#61).
- PSC data structures from example logs (Finding, Gap, Recommendation, etc.) — already in §3.2, verify completeness.
- `RosterProposal` dataclass defined (#62).
- `OutcomeStore` protocol (replaces StepWriter) — allows string or byte array (D-031).
- `StepOutcome` vs `RawPayload` data model (D-029).
- `WorkflowDefinition` return type for `load_workflow` (#63).
- `CurrentStateResult` return type for `current_state` (#64).
- `QueryWhat` enum for query API (#65).
- `RosterResolver.validate_roster` — entries must be in `agents_folder` (#49).
- `SignalMatcher` protocol — case-fold matching, pluggable (#48).
- SQLite migrations via numbered SQL files (#82).
- `WorkflowDefinitionRecord` with lifecycle metadata (#83).
- Path sanitisation: `subject_id` validated against strict pattern; subdirectory structure for outcomes (#88, S8).
- `psc-adhoc` full workflow JSON with A0L defined (#D16, D17).
- Sequential tier evaluation, first-fail triggers loop-back (D18).

**Low-Level Design (04-low-level-design.md):**
- `advance()` flow updated for parallel join+aggregation (D-013). 11-step flow. No `aggregate_outcomes` API.
- `record_decision` flow updated — writes StepRecord, fires hooks (D-014).
- Re-alignment process: step_log is source of truth; passport corrected from step_log; mirror regenerated from passport (D-001 correction).
- `mirror.disabled` is deployment-time global flag (D-001).
- Hook firing sequence: write StepRecord + update passport BEFORE hooks; then state.exited → domain event_name → transition.triggered → state.entered; terminal: state.entered then terminal event; cancel: only workflow.cancelled (#39, #40).
- `cancel_subject` sets status flag, fires `workflow.cancelled`, releases claim. No synthetic state (D-008).
- Fencing token in claim/save/advance/record_decision (D-030, S4).
- `load_outcome(subject_id, uuid)` added to API table (D5).
- `new_subject(...)` added to API table (D8).
- `cancel_subject(...)` in API table.
- `validate_passport` checks enumerated (#67).
- `route_for_outcome` documented as read-only preview (#66).
- Connection lifecycle: per-operation from pool (#87).
- Clean architecture layering subsection with file tree (#75).
- `WorkflowService` defined with method surface (#74).
- E2E test updated: remove `aggregate_outcomes` calls (#89); use `needs_clarification` not `needs_info` (D7); use `StepOutcome` not `AgentOutcome` (D9).
- Review_round increment at CR2→B2 (#55). Full B+C re-walk documented (#56). Engine computes completion from plan units (#57).

**UI/UX (05-ui-ux.md):**
- UI must HTML-escape all dynamic content (S25).
- `load_outcome` API call in History Timeline and Outcome Viewer (D5).

**Rationale/Philosophy (01-rationale-philosophy.md):**
- Replace `AgentOutcome` with `StepOutcome` in agnosticism principle (D-002).

**References (06-references.md):**
- Add RFC 6901 (JSON Pointer) if not already there.
- Add python-jsonpath library reference.

**README (00-README.md):**
- Update decision count (was 31 locked + 1 tentative; now 148 decided).

### PHASE 2: Launch validation review with 5 agents

After ALL design docs are updated, launch 5 parallel review agents:

1. **Documentation Engineer** — review for completeness, consistency, cross-references, terminology alignment, clarity, audience appropriateness, missing sections, structural issues. Check that all 148 decisions are reflected in the docs. Flag any decision not implemented.

2. **Test Engineer** — review the testing strategy (should be a new file `08-testing-strategy.md`), the e2e test prototype, coverage of happy/unhappy paths, TDD requirements (redactors, load-time validation, state machine transitions), property tests, parallel join tests, idempotency tests, fencing token tests. Propose additional test scenarios.

3. **SW Engineer/Architect** — review the updated architecture for SOLID compliance, clean architecture layering, protocol design, API surface consistency, type safety, the OutcomeStore/StepOutcome/RawPayload model, the parallel advance mechanism, the routing_rule SQL-CASE-style DSL, the verdict generalisation.

4. **Security Reviewer** — review the updated security posture: default-private classification, fencing tokens, hash chains, status_log separation, path sanitisation, content validation, RedactorNotRegisteredError, HookErrorSink, and the future security backlog.

5. **Data Architect/Modeller** — review the updated data model: passport shape (outcomes removed, retries_used, status flags, event_name on step_log), OutcomeStore protocol, StepOutcome vs RawPayload, subjects/subjects_summary/events/status_log tables, gate_config schema, passport.base schema, profile versioning, SQLite schema migrations, hash chain implementation.

Each agent must:
- Read ALL updated design files
- Produce a structured review: [CRITICAL GAPS], [GAPS], [CHALLENGES], [RECOMMENDATIONS], [PROPOSALS]
- Flag every point individually — no synthesis, no summary, no detail lost
- Reference the exact file and section for each point
- Note any of the 148 decisions that are NOT reflected in the updated docs

## File locations

- Design docs: `docs/design/workflow-design/00-README.md` through `07-review-analysis.md`
- Branch: `feature/workflow-engine`
- Project root: `/home/huyang/projects/psc`

## Important rules

- All diagrams in Mermaid
- Python 3.14+ syntax (StrEnum, uuid7, deferred annotations, copy.replace)
- `uv`-managed, clean architecture (domain/application/infrastructure)
- Context7 must be checked for any library APIs used
- All references must be authoritative (fetched URLs, not training data)
- Conventional Commits for all commits
- Do NOT commit until the review is complete
- Record all review findings in `07-review-analysis.md` (append a new section)