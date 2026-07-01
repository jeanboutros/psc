# 10 — Backlog & Future Work

> **Status:** BACKLOG. Items in this document are **known deferrals** — they
> are real work identified by design reviews but explicitly out of scope for
> the current design pass. Each item is tagged by phase, owner concern, and
> the review finding that raised it. Items here are candidates for future
> design cycles or implementation-phase spikes — they are NOT hidden defects.

---

## 10.1 How to Read This Backlog

- **Phase tag** — which implementation phase (per §4.14 Implementation
  Phasing) is expected to consume the item. `Phase 1..5` map to the phases
  in the low-level design. `Ops` means an operations concern (deployment,
  monitoring, security posture) outside the engine itself. `Post-launch`
  means after MVP.
- **Concern** — the primary domain (security, migration, observability, …).
- **Source** — the review round + finding ID that flagged it. See
  `appendix-A-decisions.md` for the ID glossary.
- **Priority** — `P1` (must-fix before launch), `P2` (planned within first
  6 months), `P3` (nice-to-have / speculative).
- **Blocked-by** — dependency on another backlog item or external
  precondition.

---

## 10.2 Parked Design Decisions

Items where the design intentionally left the question open.

| ID | Description | Priority | Blocked-by |
|----|-------------|----------|-----------|
| **Q8** | `Context.input` source semantics. Three candidates on the table: (a) engine pre-resolves `state.inputs.required` JSONPath into `ctx.input`; (b) remove `ctx.input`; (c) `ctx.input` carries dispatch-envelope metadata. Handlers MUST NOT rely on `ctx.input` until decided | P2 | User review |
| **Adhoc heuristic** | Precise rule for choosing `psc-adhoc` vs `psc-main` at A0 — "single-concern, single-file-class, no architecture impact" needs to become a concrete decision procedure | P2 | User review |
| **CR3 as a step** | Whether CR3 (author acceptance formality) is a live step or a dead step. Currently kept | P3 | User review |
| **MCP vs CLI** | Runtime choice between MCP boundary (preserves `bash:deny`) and scoped `bash:allow` calling `psc_engine`. Both surfaces designed; pick at runtime | P1 | Deployment decision |
| **Decision timeout** | When a `decision_required` state never receives a decision (E7 unhappy path), how long before the PM routes to `deferred`? Wall-clock or explicit action? | P2 | User review |
| **Mirror commit cadence** | Commit Markdown mirror on every `advance()` or at phase boundaries / gate passes | P2 | User review |
| **Database vs JSON-only** | Confirm the database backend is needed at MVP, or drop it if multi-session safety is not a near-term requirement | P1 | Runtime scale decision |
| **CI lint for sensitive fields** | Ship a CI lint that flags common sensitive field names (`password`, `api_key`, `secret`, `token`, `credential`, `email`, `phone`) not classified as `protected`/`private` | P2 | Post-MVP |

## 10.3 Security Backlog

Items deferred from rounds 1-3 pending the authentication track.

| Item | Source | Priority | Phase |
|------|--------|----------|-------|
| **Authentication (S1)** — real auth boundary so `session_id` is not caller-supplied. Blocks: rate-limiting the claim gate, verifying `cancelled_by`, adhoc-workflow access control | Round 1 S1; Round 2 SCG-1, SCG-3, SG-17; Round 3 SCG-2, SCG-5 | P1 | Post-launch (separate design pass) |
| **Encryption at rest** — passport JSON + outcomes on disk are cleartext. Wrapper store (`EncryptedSubjectStore`) or filesystem-level encryption | Round 2 SG-14, SR-5, SP-3; Round 3 SCG-4 | P2 | Ops |
| **File permissions (0600)** — passport JSON, outcomes, agent files. Deployment concern | Round 2 SG-13, SG-26, SR-16 | P2 | Ops |
| **Rate limiting on `claim()`** — prevent `claim_epoch` DoS by an authenticated attacker | Round 2 SG-28; Round 3 SCG-5 | P2 | Post-auth |
| **Content Security Policy (CSP)** — for the UI. UI-layer deployment concern | Round 2 SG-22, SR-20 | P2 | Ops (UI) |
| **Integrity signing of workflow definitions and agent files** — beyond the `workflow_definition_hash` we already store; signing prevents undetected tampering upstream | Round 2 SG-12, SG-15, SR-4 | P3 | Post-launch |
| **`SecurityConfig` section in `psc_engine.yaml`** — add when the first security knob lands | Round 2 SP-5 | P2 | Post-auth |
| **Configurable size caps** — `max_raw_payload_bytes`, `max_vars_bytes`. Currently unbounded | Round 2 SG-24, SG-25, SR-14, SR-15; Round 3 SecP-3 | P2 | Phase 1 config |
| **`reason` field maxLength** — currently unbounded in `passport.base` schema | Round 2 SG-29; Round 3 | P2 | Phase 1 |

## 10.4 Integrity & Audit Backlog

Items that harden the hash-chain and verification story beyond Phase 1 basics.

| Item | Source | Priority | Phase |
|------|--------|----------|-------|
| **`psc verify` CLI subcommand** — offline chain verification. The runtime API `verify_chain()` (Q17) is landed; the CLI wraps it | Round 2 SR-3, SP-6; Round 3 Q17 partial | P2 | Phase 3 |
| **Cross-chain binding** — link `events` ↔ `status_log` hash chains so an attacker can't remove one row from either without breaking the other | Round 2 SCH-5, SP-4 | P3 | Post-launch |
| **PassportIntegrityHash** — hash of passport included in each event, so events reference a specific passport state | Round 2 SP-2 | P3 | Post-launch (profile cost) |

## 10.5 Storage / Data Model Backlog

Items that add operational polish without changing the core contract.

| Item | Source | Priority | Phase |
|------|--------|----------|-------|
| **Migration strategy document** — how a subject at workflow v2.0.0 migrates to v2.1.0; mapping files; incompatible-MAJOR handling | Round 2 MP-1, MCH-2, CR-PENDING-7 | P1 | Phase 5 |
| **`subjects_summary` update mechanism** — trigger-based? application-level? denormalised columns need a documented refresh path | Round 2 MG-19, MG-35, MR-8 | P2 | Phase 1 |
| **RawPayload compression** — currently implementation-defined; document expected size envelope and codec | Round 2 MG-20, MR-9, AG-74 | P3 | Phase 1 tuning |
| **Late-arriving branch outcome audit** — when a parallel state receives an outcome after quorum satisfied with `on_satisfied: cancel_pending`, where does the late payload go? Options: outcome-store-audit-only, discard, log | Round 3 SG (late branch); Round 2 AG-5, AG-6 | P2 | Phase 1 |
| **Multi-backend schema portability** — SQLite (`AUTOINCREMENT`) vs PostgreSQL (`IDENTITY`), JSON vs JSONB. Currently per-backend migration files | Round 2 MG-33, MCH-3 | P2 | Phase 3 (backend swap) |
| **`SchemaProfile` loading semantics** — how the engine loads and caches the profile, error semantics on missing schemas | Round 2 AG-46 | P2 | Phase 1 |
| **Reaper orchestration** — how often does the reaper run? scheduled? on demand? On each reap it appends `claim_log(kind='released', reason='lease_ttl_exceeded', actor='system:reaper')` and fires `SUBJECT_RELEASED` | Round 2 AG-47 | P2 | Phase 3 |
| **`ClaimLog` retention policy** — currently unbounded (matches `events`). Add rotation / archival strategy once volumes justify it | CLM-4 (new) | P3 | Post-launch |
| **`FORCED_BY_ADMIN` / `SESSION_TERMINATED` claim/release reasons** — enum values defined but no code path emits them yet. Depends on auth work | CLM-2, CLM-3 (new) | P2 | Post-auth |

## 10.6 Observability Backlog

Items that improve operator visibility.

| Item | Source | Priority | Phase |
|------|--------|----------|-------|
| **`EventDispatchHook` transactional outbox** — at-least-once event bus delivery. Currently documented as Phase 5 | Round 2 AG-56 | P1 | Phase 5 |
| **`workflow.escalated` event enum entry** — confirmed present; verify all producers | Round 2 AG-57 | P3 | Phase 1 verification |
| **Dashboard for blocked / escalated / deferred subjects** — powered by `list_subjects()` (Q4). UI concern | Round 3 Q4 | P2 | Phase 6 (UI) |

## 10.7 Correctness Polish

Items that tighten load-time validation and runtime guarantees.

| Item | Source | Priority | Phase |
|------|--------|----------|-------|
| **`join.type` load-time validation** — implemented via typed `JoinConfig` (Q26); ensure regression tests exist | Round 2 SG-20, SR-6 | P1 | Phase 1 tests |
| **`UNIQUE` on `events(idempotency_key)`** — implemented via SQL constraint | Round 2 MG-38, AG-89 | P1 | Phase 1 tests |
| **`fan_out $roster` schema validation** — implemented via typed `FanOut` (Q12) | Round 2 MG-25 | P1 | Phase 1 tests |
| **Explicit `H` and genesis-hash spec** — implemented (SHA-256 + RFC 8785); ensure documented | Round 2 SG-3, SG-4, SR-2, CR-PENDING-1, CR-PENDING-2 | P1 | Phase 1 tests |
| **`domain_signals` validation** — RosterResolver validates against known signals; document behaviour on unknown signals | Round 2 SG-23, SR-18 | P2 | Phase 1 |
| **`confidence` advisory annotation** — schema-level; documentation-only concern | Round 2 SG-8, SR-11 | P3 | Phase 1 docs |
| **`root_cause` enum validation** — RC-1..RC-5 enforced by the PSC profile | Round 2 SG-6, SR-10 | P2 | Phase 1 (profile) |
| **Content validation constraints on profile** — length caps, control-character rejection | Round 2 SG-7, SR-9 (partly done via passport.base) | P2 | Phase 1 (profile) |

## 10.8 UI / UX Backlog

Beyond `05-ui-ux.md`. All P2/P3 — none block engine implementation.

| Item | Source | Priority | Phase |
|------|--------|----------|-------|
| **Dashboard implementation** | Round 3 Q4 | P2 | Phase 6 |
| **CSP header** | Round 2 SG-22 | P2 | Ops |
| **UI walk-through video / interactive demo** | — | P3 | Post-launch |

## 10.9 Testing Backlog (Beyond `08-testing-strategy.md`)

The strategy document enumerates the test files. This backlog captures test
scenarios discovered in Q1-Q33 that need parameterised test cases created
when the strategy is implemented.

| Scenario | Test file | Priority |
|----------|-----------|----------|
| Q2 propose/confirm walk-throughs (A0→A0c, A2c→A2cc, C4p→C4, A0L→A0Lc) | `tests/integration/test_e2e_happy_path.py` | P1 |
| Q9 `VarsCollisionError` with branch-namespaced outputs | `tests/application/test_advance_parallel.py` | P1 |
| Q10 `StateKindMismatchError` on `record_decision` against task state | `tests/application/test_record_decision.py` | P1 |
| Q14 versioned idempotency key determinism (RFC 8785) | `tests/domain/test_outcome.py`, `tests/property/test_idempotency_properties.py` | P1 |
| Q17 `verify_chain` happy + tampered chain | `tests/application/test_workflow_service.py`, `tests/property/test_hash_chain_properties.py` | P1 |
| Q19 `ProjectDepthExceeded` at max_depth+1 nesting | `tests/domain/test_project.py` | P1 |
| Q20 `ReservedVarsPathError` on handler write to `/state`, `/retries_used`, etc. | `tests/domain/test_context.py` | P1 |
| Q21 heartbeat auto-refresh crossing TTL | `tests/application/test_claim.py` | P1 |
| Q22 `workflow_definition_hash` verification on load | `tests/application/test_workflow_service.py` | P1 |
| Q26 `JoinQuorum` with `cancel_pending` / `supersede` / `discard_late` modes | `tests/application/test_advance_parallel.py` | P1 |
| Q29 `StatusLog` engine-managed `prev_hash` | `tests/infrastructure/test_sqlite_status_log.py` | P1 |
| Q31 `OutcomeRef` / `RawRef` type-check | `tests/domain/test_outcome.py` (pyright/mypy) | P2 |

---

## 10.10 Explicit Non-Goals for MVP

Items that were considered and consciously excluded from the current design
scope. Documenting them here prevents re-litigating.

| Non-goal | Rationale |
|----------|-----------|
| **Distributed multi-node execution** | Single-node with SQLite/JSON is sufficient for MVP. PG backend covers multi-process on one host. Cross-host distribution is a future scale-out concern |
| **Priority queues / SLA-aware scheduling** | The engine is state-machine driven, not queue-driven. External schedulers can drive `advance()` per their own policies |
| **Web-based workflow editor** | Workflow JSON is authored by design engineers, not runtime users. A visual editor is post-launch UX polish |
| **Real-time notifications (websockets)** | The `EventDispatchHook` publishes to an event bus; notification UIs are downstream consumers, not the engine's concern |
| **Full-text search on `step_log`** | Query API is structural; full-text is a search-service concern. If needed, `EventDispatchHook` can feed an external index |
| **PII / GDPR compliance tooling** | The `project()` / redaction infrastructure enables compliant emission, but a compliance suite (data-subject requests, retention deletion) is out of scope |

---

## 10.11 Adding to the Backlog

When a new deferral is identified:

1. Categorise under the appropriate §10.N section.
2. Assign a priority (P1 / P2 / P3).
3. Cite the source finding (`Q##`, `D-###`, `AG-##`, `SG-##`, etc.) so the
   trace back to `appendix-A-decisions.md` is preserved.
4. If the item unblocks other work, note it in the **Blocked-by** column of
   the dependents.
5. If a backlog item is completed, DO NOT delete it — mark it "DONE
   (phase-X commit-abc123)" so the historical record survives.
