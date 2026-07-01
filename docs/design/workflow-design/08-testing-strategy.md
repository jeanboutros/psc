# 08 — Testing Strategy

> **Status:** DRAFT. Synthesised from Test Engineer review (round 2) and the
> Clean Architecture layering in `04-low-level-design.md` §4.12.

---

## 1. Testing Philosophy

The engine is a state machine with hard correctness requirements (idempotency,
fencing, hash chains, redaction, validation). Bugs in the engine cause data
loss, silent corruption, or audit-trail tampering. The testing strategy is
therefore biased toward **TDD where mandated** and **property-based testing
for state-machine invariants**, complemented by unit and integration tests.

| Layer | Primary technique | Why |
|-------|------------------|-----|
| Domain (state, context, outcome, passport, project, verdict) | TDD + property-based (Hypothesis) | Pure functions; state-machine invariants; security-critical (redaction) |
| Application (advance, record_decision, claim, cancel) | TDD + integration with stubs | Orchestration logic with multiple side effects |
| Infrastructure (stores, dispatchers, hooks) | Unit + contract tests | Adapter pattern; one suite per backend |
| Integration | Full-workflow walkthrough tests | Catches inter-layer drift |
| E2E | Driven from CLI/MCP | Validates deployed surface |

**Coverage targets:**

| Layer | Line | Branch | Mutation |
|-------|------|--------|----------|
| Domain | 100% | 100% | ≥ 90% |
| Application | 95% | 90% | ≥ 80% |
| Infrastructure | 90% | 80% | n/a |
| Integration / E2E | n/a | n/a | n/a |

---

## 2. TDD-Mandated Areas

Per design decisions (D-016 `project()`, D-029 load-time validation, D-031
OutcomeStore, S2 redactors), the following modules are TDD-mandated:

1. **State machine routing** — `Transition` lookup, `loop` semantics,
   `StateRegistry.is_ancestor`, forward-DAG construction with back-edge
   exclusion.
2. **Routing rules** — SQL-CASE-style `CASE WHEN ... THEN ... ELSE ... END`
   evaluation via `python-jsonpath`. RFC 9535 filter selector compliance.
3. **`project()` function** — classification, recursion into nested
   objects/arrays, `additionalProperties`/`patternProperties` handling,
   fail-closed defaults, redactor invocation.
4. **Redactors** — `DefaultRedactor`, `EmailRedactor`, `TokenRedactor`, and
   the `RedactorRegistry`.
5. **Load-time validation** — every `WorkflowDefinitionError` path
   (missing event_name, unreachable target, cyclic forward-DAG, missing
   start_at, missing terminal, gate with dispatch_handler, etc.).
6. **`VerdictSchemaBuilder`** — dynamic enum construction including
   engine-reserved verdicts.
7. **Idempotency-key construction** — `sha256(subject_id + step +
   entry_count + attempt)` for non-parallel; `+ branch_id` for parallel.
8. **Hash chain** — `row_hash = H(prev_hash, row_data)` deterministic; chain
   verification API.
9. **`StateRegistry.is_ancestor`** — back-edge exclusion; `IncomparableStates`
   raised when no directed path exists.

For each module, the workflow is **write a failing test first**, implement
until green, then refactor. Tests in `tests/domain/` are the executable
specification.

---

## 3. Unit Test Coverage Matrix

Mirrors the source tree in `04-low-level-design.md` §4.12.

### 3.1 Domain layer (`tests/domain/`)

| File | Module under test | Key cases |
|------|-------------------|-----------|
| `test_state.py` | `State`, `StateKind` | `__eq__`/`__hash__`; immutability; rejection of contradictory kind+field combos |
| `test_state_registry.py` | `StateRegistry` | `is_ancestor` happy, reverse, equal, back-edge-only, `IncomparableStates` |
| `test_transition.py` | `Transition` | Frozen; verdict type; loop flag |
| `test_context.py` | `Context`, `StateMeta` | Frozen; `is_loop_back`, `is_retry`, `reached_from`; `vars` deep-copy on branch |
| `test_outcome.py` | `StepOutcome`, `RawPayload`, `StepRecord` | `kind` discriminator; field parity with passport step_log |
| `test_passport.py` | `Passport`, `StatusFlags` | Status flag mutation; step_log INDEX behaviour; lazy `retries_used` init |
| `test_workflow.py` | `WorkflowDefinition` | Load + freeze; state lookup; routing rule binding |
| `test_protocols.py` | All `Protocol` classes | Static-only checks (mypy/pyright); runtime structural conformance |
| `test_exceptions.py` | Full hierarchy | Every subclass derives from `WorkflowError`; `IncomparableStates` correctly inherits |
| `test_verdict_schema_builder.py` | `VerdictSchemaBuilder` | `build_enum` includes `pass/fail/exhausted`; `materialise_schema` per state |
| `test_project.py` | `project()` | Private/public/protected; recursion; `additionalProperties` true/false/sub-schema; `patternProperties`; arrays; fail-closed defaults; `unevaluatedProperties` rejection at load time |
| `test_redactors.py` | All redactors + registry | Email mask; token mask; default `[REDACTED]`; missing redactor → `RedactorNotRegisteredError` |
| `test_api_results.py` | `CurrentStateResult`, `AdvanceResult`, `RosterProposal`, etc. | Field defaults; frozen; serialisation |

### 3.2 Application layer (`tests/application/`)

| File | Module under test | Key cases |
|------|-------------------|-----------|
| `test_advance_task.py` | task `advance()` flow (4.1c) | All 9 steps; routing happy + `RoutingError`; idempotency short-circuit |
| `test_advance_gate.py` | gate `advance()` flow (4.1d) | `pass`/`fail`/`exhausted`; budget exhaustion; ESCALATE path |
| `test_advance_parallel.py` | parallel `advance()` flow (4.1a) | `all` join; `quorum:N`; late-arriving branch; crashed branch; `on_satisfied` modes |
| `test_record_decision.py` | `record_decision()` flow (4.1b) | Schema validation; routing rule first-match; `is_decision_pending` toggle |
| `test_cancel.py` | `cancel_subject` | Sets flag, fires `workflow.cancelled`; appends to `status_log`; abrupt — no `state.exited`; idempotent |
| `test_claim.py` | claim/release with fencing | `claim_epoch` increments; `LeaseLostError` on mismatch; `ConcurrentWriteError` on version mismatch; `claim_log` row written on every claim/release with correct `kind`/`reason`/`actor`; `SUBJECT_CLAIMED` + `SUBJECT_RELEASED` hooks fire after commit; heartbeat writes NO `claim_log` row and fires NO hook |
| `test_reaper.py` | stale claim reaper | TTL respected; does NOT touch `claim_epoch`; `claim_log` row written with `kind='released'`, `reason='lease_ttl_exceeded'`, `actor='system:reaper'`; `SUBJECT_RELEASED` hook fires with reaper's actor value |
| `test_workflow_service.py` | `WorkflowService` integration | All method dispatch; dependency wiring; query API per `QueryWhat` |
| `test_realignment.py` | step_log → passport re-alignment | Crash mid-advance; truncated passport; step_log is source of truth |
| `test_migration.py` | `migrate()` | Compatible upgrade; incompatible MAJOR; mapping file required |

### 3.3 Infrastructure layer (`tests/infrastructure/`)

| File | Backend | Contract |
|------|---------|----------|
| `test_json_subject_store.py` | JSON file | `flock` advisory; atomic RMW; claim contract |
| `test_sqlite_subject_store.py` | SQLite | `PRAGMA foreign_keys = ON`; WAL mode; CAS on version AND claim_epoch |
| `test_pg_subject_store.py` | PostgreSQL | Same contract; transactional |
| `test_sqlite_event_store.py` | SQLite | Hash chain consistency; `prev_hash` chained; no UPDATE/DELETE allowed |
| `test_pg_event_store.py` | PostgreSQL | Same |
| `test_json_outcome_store.py` | filesystem | Path sanitisation; `subject_id` pattern enforced; subdirectory layout |
| `test_sqlite_outcome_store.py` | SQLite | JSON storage; `kind` discriminator preserved |
| `test_pg_outcome_store.py` | PostgreSQL JSONB | Same |
| `test_sqlite_status_log.py` | SQLite | Separate chain; `restored` flag is FORBIDDEN; only `cancelled`/`deferred`/`archived` accepted |
| `test_sqlite_claim_log.py` | SQLite | Separate chain (own `prev_hash` / `row_hash`); rows accepted only for `kind IN ('claimed','released')`; `reason` validated against `ClaimReason` for CLAIMED and `ReleaseReason` for RELEASED; `prev_hash` engine-managed (caller does NOT supply it); heartbeats never appear |
| `test_workflow_definition_store.py` | filesystem + DB | Versioned load; immutable per (id, version) |
| `test_schema_registry.py` | SchemaRegistry | Register + resolve + validate; `outcome.base` always loadable |
| `test_dispatcher_registry.py` | DispatcherRegistry | Built-in handlers; `HandlerNotRegistered` on unknown name |
| `test_hook_registry.py` | HookRegistry | Critical fail-closed; non-critical via `HookErrorSink` |
| `test_aggregation_registry.py` | AggregationRegistry | Built-in `verdict_all_pass`, `verdict_unanimous` |
| `test_config.py` | Config + ConfigPort | YAML load; default values; missing keys; validation against hard caps |
| `test_subagent_dispatch.py` | subagent dispatch | Envelope shape; error → `DispatchError`; metadata captured |
| `test_human_form_dispatch.py` | human form dispatch | Blocking wait; timeout; cancellation |
| `test_event_dispatch_hook.py` | EventDispatchHook | Transactional outbox; at-least-once; ordering |

### 3.4 Property tests (`tests/property/`)

Using Hypothesis. These tests assert invariants that must hold for **any**
valid input.

| File | Invariant |
|------|-----------|
| `test_state_machine_properties.py` | For every workflow + valid sequence of advances, `state.current` is always reachable from `start_at` via forward edges + loop-backs. The forward-progress DAG (loops removed) is acyclic. |
| `test_idempotency_properties.py` | For every `(subject_id, step, entry_count, attempt)`, repeated advances produce exactly one StepRecord. The key is deterministic given identical inputs. |
| `test_hash_chain_properties.py` | For every event sequence, recomputing `row_hash = H(prev_hash, row_data)` reproduces the persisted chain. Any single-row mutation breaks the chain. |
| `test_project_properties.py` | For every `(data, schema)` pair, the output contains no field whose schema classification is `private`. Fields with `additionalProperties: false` are never emitted. The fail-closed default omits undeclared fields at every depth. |
| `test_verdict_enum_properties.py` | The materialised enum always contains `{pass, fail, exhausted}` and exactly the transition keys of the state. No project verdict shadows engine-reserved names. |
| `test_routing_first_match.py` | For every routing rule, `WHEN` branches are evaluated in order; the first match wins; `ELSE` is taken iff no `WHEN` matches. |

---

## 4. Integration Test Scenarios (`tests/integration/`)

Each test walks an entire workflow with real (in-memory or tmp-path-backed)
infrastructure. The Supreme Leader is replaced by a deterministic driver.

| File | Scenario |
|------|----------|
| `test_e2e_happy_path.py` | `psc-main`: A0 → A1 (parallel) → A2 → A2b → A2c → A2a → A3 → B1 → B2 → B2a → B3 → B3a → C0 → C1 → C2 → C3 → C4 → CR1 → CR2 → CR3 → COMMIT. Verify every state.entered and state.exited hook fires; passport matches step_log; mirror is up to date. |
| `test_e2e_unhappy_subject_not_found.py` | E2 from §4.1 unhappy table. |
| `test_e2e_unhappy_ambiguous_a0.py` | E3 — A0 loops on empty roster. |
| `test_e2e_unhappy_passport_missing.py` | E4 — delete passport JSON; re-align from step_log. |
| `test_e2e_gate_exhausted.py` | A3 gate fails 3× → ESCALATE; verify `gate.exhausted` and `workflow.escalated` hooks fire. |
| `test_e2e_decision_timeout.py` | E7 — decision never arrives → `deferred` flag set after timeout. |
| `test_e2e_cancel_midflight.py` | E8 — cancel during A2 (parallel); flag set; pending branches not joined. |
| `test_e2e_parallel_quorum.py` | `join: {type: quorum, n: 2}`; satisfied after 2 of 3; late branch with `on_satisfied: cancel_pending` rejected. |
| `test_e2e_parallel_supersede.py` | `on_satisfied: supersede` — composite recomputed when late branch arrives. |
| `test_e2e_parallel_crashed_branch.py` | One branch raises `DispatchError`; retry within budget; exceed → branch marked `failed`. |
| `test_e2e_cr2_request_changes.py` | CR2 → B2 loop; review_round incremented; round_budget enforced. |
| `test_e2e_c4_decisions.py` | All six C4 decisions (complete, rework, backlog_split, escalate, defer, add_tests). |
| `test_e2e_adhoc.py` | `psc-adhoc`: A0L → A1L → B1L → B3L → B3aL → CR1L → CR2L → COMMIT. |
| `test_e2e_migration.py` | Subject created at workflow v2.0.0; migrate to v2.1.0 (compatible). Reject 3.0.0 without mapping file. |
| `test_e2e_realignment.py` | Crash mid-advance after StepRecord written but before passport saved. Re-align reconstructs passport from step_log. |
| `test_e2e_multi_session.py` | Two sessions race on claim; only one wins; fencing token rejects stale writer. |
| `test_e2e_redaction.py` | Outcome with email + token fields; verify events table contains redacted values; passport JSON contains cleartext. |

---

## 5. Property-Based Tests

See §3.4. Property tests are first-class — they catch classes of bugs that
example-based tests cannot. The state machine and hash chain are particularly
well-suited.

```python
# Example: hash chain integrity
from hypothesis import given, strategies as st

@given(st.lists(st.dictionaries(st.text(min_size=1, max_size=20),
                                st.text(min_size=0, max_size=200)),
                min_size=1, max_size=50))
def test_hash_chain_integrity(rows):
    store = SqliteEventStore(":memory:")
    for row in rows:
        store.append_raw(row)
    # Re-verify every row
    chain = store.load_events("test-subject")
    for i, ev in enumerate(chain):
        expected = sha256(ev.prev_hash + canonical_json(ev._row_data))
        assert ev.row_hash == expected
```

---

## 6. E2E Test Suite (driven from CLI/MCP)

E2E tests use the actual CLI (`python -m psc_engine`) or MCP server
(`psc-state`). They are slower than integration tests and run on every PR.

| File | Driver | Scenario |
|------|--------|----------|
| `test_cli_happy.py` | CLI | `psc new-subject`, `psc advance`, `psc record-decision`, `psc current-state` chain |
| `test_cli_concurrent.py` | CLI | Two CLI processes claim same subject; fencing token rejects loser |
| `test_mcp_happy.py` | MCP | Same happy path via MCP tool calls |
| `test_mcp_redaction.py` | MCP | MCP response contains projected (redacted) fields; passport on disk does not |

---

## 7. Test Infrastructure

### 7.1 Fixtures (`tests/conftest.py`)

```python
@pytest.fixture
def tmp_workflow(tmp_path):
    """Minimal valid workflow JSON written to tmp_path."""

@pytest.fixture
def in_memory_engine(tmp_path):
    """Engine wired with in-memory SQLite + tmp-path filesystem."""

@pytest.fixture
def hook_spy():
    """Records every fired hook; assertable in tests."""

@pytest.fixture
def deterministic_uuid7(monkeypatch):
    """Patches uuid.uuid7 to a counter; tests assert against fixed UUIDs."""

@pytest.fixture
def frozen_clock(monkeypatch):
    """Freezes datetime.now() at 2026-06-30T00:00:00Z."""
```

### 7.2 Test data

`tests/fixtures/workflows/` holds versioned workflow JSONs used by tests.
Each fixture has a comment header explaining what it exercises:

```
tests/fixtures/workflows/
├── minimal.json            # Only A0 → COMMIT
├── parallel_only.json      # Single parallel state, all join
├── parallel_quorum.json    # Quorum join with on_satisfied modes
├── gates_only.json         # Gate chain
├── cyclic.json             # MUST fail load-time validation
├── missing_event_name.json # MUST fail load-time validation
└── psc_main_v2.json        # Full psc-main pinned at 2.0.0
```

### 7.3 CI integration

| Stage | Command | Gate |
|-------|---------|------|
| Lint | `ruff check . && ruff format --check .` | Required |
| Type | `pyright psc_engine tests` | Required |
| Domain unit + property | `pytest tests/domain tests/property -x` | Required; 100% line coverage |
| Application unit | `pytest tests/application -x` | Required; ≥ 95% line |
| Infrastructure | `pytest tests/infrastructure --backends=json,sqlite,pg -x` | Required (PG via service container) |
| Integration | `pytest tests/integration -x` | Required |
| E2E | `pytest tests/e2e -x --slow` | Required on `main`, optional on PR |
| Mutation | `mutmut run --paths-to-mutate=psc_engine/domain` | Required: ≥ 90% killed |

---

## 8. Test-Driven Implementation Cadence

For each module marked TDD-mandated (§2), follow the PAU loop:

1. **Plan** — write the test cases in the test file (no impl yet).
2. **Apply** — implement enough code to make the next test green.
3. **Validate** — run the test suite; if green, move to the next test.
4. **Refactor** — clean up. Tests stay green.

Commits follow Conventional Commits (per `AGENTS.md`):

```
test(domain/project): add fail-closed test for undeclared fields
feat(domain/project): implement classification recursion
refactor(domain/project): extract _classify_and_emit helper
```

---

## 9. Open Items

| Item | Status |
|------|--------|
| Mutation testing config (mutmut vs cosmic-ray) | Open — defer to Phase 1 |
| Property-test strategy library | Open — start with `hypothesis.strategies`; extract reusable strategies per domain entity |
| Performance budget for tests | Open — target: domain + application < 30s; integration < 2min; e2e < 5min |
| Test data redaction in CI logs | Open — ensure fixtures contain only synthetic data; CI must not leak real values |
