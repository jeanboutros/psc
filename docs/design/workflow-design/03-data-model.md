# 03 — Data Model: Physical Schema, Data Dictionary, and Data Structures

> **Status:** DRAFT. Schemas are JSON Schema 2020-12. Python prototypes are
> executable specs, not final implementations.

---

## 3.1 Engine Contract (Generic)

The engine knows ONLY this minimal contract. Everything else is opaque payload.

### OutcomeContract — the minimal routing contract

```jsonc
"outcome.base": {
  "type": "object",
  "required": ["verdict"],
  "properties": {
    "verdict": { "type": "string" },
    "decision": { "type": ["object", "null"] },
    "confidence": { "type": "integer", "minimum": 0, "maximum": 100 }
  }
}
```

The engine reads `verdict` for routing, `decision` for decision_required states,
and `confidence` for parallel aggregation (min across outcomes). Everything else
in the outcome is opaque JSON stored by OutcomeStore.

### Verdict — `NewType[str]` with dynamic JSON Schema enum

The engine defines exactly **two** verdicts that all workflows must support:
`pass` and `fail`. Everything else is a **project-defined verdict** that the
engine treats as an opaque string label. The `Verdict` type is a `NewType[str]`
(not a fixed enum) — an open set validated externally by JSON Schema.

```python
from typing import NewType

Verdict = NewType("Verdict", str)

# Engine-reserved verdicts. `pass` / `fail` are emitted by all task and gate
# handlers. `exhausted` is emitted by the engine when a gate's reentry_budget
# is fully consumed. Projects MUST NOT shadow these names.
ENGINE_VERDICTS: frozenset[str] = frozenset({"pass", "fail", "exhausted"})

# Hard engine caps — refuse misconfigured workflows at load time.
ENGINE_MAX_DISPATCH_ATTEMPTS: int = 10
ENGINE_MAX_REENTRY_BUDGET: int = 10

# Reserved ctx.vars paths (JSON Pointer format). Handler writes to these
# paths raise `ReservedVarsPathError`. The engine manages them exclusively.
# Q20 decision.
ENGINE_RESERVED_VARS_PATHS: frozenset[str] = frozenset({
    "/state",                        # current-state metadata
    "/retries_used",                 # gate retry counters
    "/status",                       # cancelled/deferred/archived flags
    "/domain_classification/roster", # $roster source — mutating breaks fan_out
    "/parallel_progress",            # parallel branch state
    "/step_log",                     # step index
    "/gate_results",                 # gate history
    "/decisions",                    # decision history
    "/loop_history",                 # loop-back history
    "/corrections",                  # RC corrections
    "/reviews",                      # review round state
})

class VerdictSchemaBuilder:
    """Builds the per-state JSON Schema enum for verdict dynamically."""

    ENGINE_VERDICTS = ENGINE_VERDICTS

    def build_enum(self, state_transitions: dict[str, "Transition"]) -> list[str]:
        transition_keys = set(state_transitions.keys())
        valid = self.ENGINE_VERDICTS | transition_keys
        return sorted(valid)

    def materialise_schema(self, base_schema: dict, state_transitions: dict) -> dict:
        import copy
        schema = copy.deepcopy(base_schema)
        schema["properties"]["verdict"]["enum"] = self.build_enum(state_transitions)
        return schema
```

- Transition lookup: `state.transitions.get(verdict)` — plain dict lookup.
- Validation: two-layered — load-time (verdict keys match `^[a-z][a-z0-9_]*$`) + runtime (outcome's verdict is in the materialised enum).
- Gate states may ONLY transition on engine-reserved verdicts (`pass`/`fail`/`exhausted`). Project-defined verdicts on a gate state are rejected at load time by `WorkflowDefinitionError`.

### StateKind enum

```python
class StateKind(StrEnum):
    TASK = "task"
    PARALLEL = "parallel"
    GATE = "gate"
    DECISION_REQUIRED = "decision_required"
    TERMINAL = "terminal"
```

### Transition (with mandatory event_name)

```python
@dataclass(frozen=True)
class Transition:
    verdict: Verdict          # The verdict label that selects this edge
    target: str
    event_name: str           # MANDATORY — e.g. "subject.phase-a.classified"
    loop: bool = False
```

### DispatchHandler protocol

```python
class DispatchHandler(Protocol):
    def dispatch(self, state: "State", ctx: "Context") -> "StepOutcome | RawPayload":
        """Execute the state's actor and return either a validated
        StepOutcome (happy path) or a RawPayload (validation failed —
        preserved for forensic review). Schema resolved at handler
        construction time. Raises DispatchError on transport-layer failure
        (timeout, crash, OOM); returning RawPayload signals a
        validation-layer failure (handler responded but response did not
        match schema). Q16 decision."""
        ...
```

Built-in handlers: `engine.subagent_dispatch`, `engine.human_form_dispatch`,
`engine.system_webhook_dispatch`. Projects register custom handlers at startup.
Gates have NO `dispatch_handler` — they are driven by `gate_config.reentry_budget`
and evaluated by `GateRunner` (see §4.1d in `04-low-level-design.md`).

### SchemaRegistry

```python
class SchemaRegistry:
    def register(self, name: str, schema: dict) -> None: ...
    def resolve(self, name: str) -> dict: ...
    def validate(self, name: str, instance: dict) -> tuple[bool, list[str]]: ...
```

### LifecycleHook + EngineEvent

```python
class EngineEvent(StrEnum):
    WORKFLOW_STARTED = "workflow.started"
    WORKFLOW_COMPLETED = "workflow.completed"
    WORKFLOW_CANCELLED = "workflow.cancelled"
    WORKFLOW_ESCALATED = "workflow.escalated"
    STATE_ENTERED = "state.entered"
    STATE_EXITED = "state.exited"
    TRANSITION_TRIGGERED = "transition.triggered"
    GATE_PASSED = "gate.passed"
    GATE_FAILED = "gate.failed"
    GATE_EXHAUSTED = "gate.exhausted"
    DECISION_RECORDED = "decision.recorded"
    PARALLEL_BRANCH_STARTED = "parallel.branch.started"
    PARALLEL_BRANCH_COMPLETED = "parallel.branch.completed"
    PARALLEL_JOIN_SATISFIED = "parallel.join.satisfied"
    LOOP_TRIGGERED = "loop.triggered"
    RETRY_ATTEMPTED = "retry.attempted"
    SUBJECT_CLAIMED  = "subject.claimed"       # payload carries ClaimReason
    SUBJECT_RELEASED = "subject.released"      # payload carries ReleaseReason
    # NOTE: SUBJECT_STALE_REAPED removed — a reaper release IS a release with
    # `reason == ReleaseReason.LEASE_TTL_EXCEEDED`. Downstream consumers filter
    # on payload.reason to distinguish.

class ClaimReason(StrEnum):
    """Why a subject was claimed. Payload attribute of SUBJECT_CLAIMED."""
    CALLER_INITIATED   = "caller_initiated"    # Default — interactive/programmatic acquire
    RECLAIM_AFTER_REAP = "reclaim_after_reap"  # Caller detected prior reap, re-acquires
    SYSTEM_INITIATED   = "system_initiated"    # Cron / scheduler / background worker
    FORCED_BY_ADMIN    = "forced_by_admin"     # Future — admin override (auth-deferred)

class ReleaseReason(StrEnum):
    """Why a subject was released. Payload attribute of SUBJECT_RELEASED."""
    CALLER_INITIATED   = "caller_initiated"    # Normal — release() or claimed() context exit
    LEASE_TTL_EXCEEDED = "lease_ttl_exceeded"  # Reaper — stale claim released
    FORCED_BY_ADMIN    = "forced_by_admin"     # Future — admin override (auth-deferred)
    SESSION_TERMINATED = "session_terminated"  # Future — auth-driven (e.g. user logged out)

class LifecycleHook(Protocol):
    def on_event(self, event: str, context: dict) -> None: ...
```

### Storage protocols

```python
@dataclass(frozen=True)
class ClaimResult:
    claimed: bool
    claim_epoch: int | None   # Fencing token — monotonically increasing

class ClaimLogKind(StrEnum):
    """Row kind for claim_log. Ownership transitions only; heartbeats
    are excluded (they update subjects.claimed_at directly)."""
    CLAIMED  = "claimed"
    RELEASED = "released"

@dataclass(frozen=True)
class ClaimLogEntry:
    """One row of the claim_log table. Hash-chained with own chain
    (same formula as events / status_log)."""
    id: int
    subject_id: str
    kind: ClaimLogKind
    session_id: str
    claim_epoch: int
    actor: str                # session_id for caller-initiated;
                              # 'system:reaper' for reaper;
                              # 'system:admin' for future admin overrides.
    reason: str               # ClaimReason value (kind=CLAIMED) or
                              # ReleaseReason value (kind=RELEASED).
    ts: str                   # ISO-8601 timestamp
    prev_hash: str | None
    row_hash: str

@dataclass(frozen=True)
class InflightSubject:
    subject_id: str
    workflow_id: str
    workflow_version: str
    active_steps: list[str]

# StepRecord (defined in §3.8) is the canonical event/step record shape.
# EventStore.load_events returns StepRecord instances with `prev_hash` and
# `row_hash` populated by the store implementation (fields present but
# unpopulated on the write path). There is NO separate EventRecord type —
# read and write use the same shape (Q3 decision).

class SubjectReader(Protocol):
    def load(self, subject_id: str) -> dict | None: ...
    def load_inflight(self) -> list[InflightSubject]: ...

class SubjectWriter(Protocol):
    def save(self, subject_id: str, passport_json: str,
             version: int, claim_epoch: int) -> int: ...

class SubjectClaimStore(Protocol):
    """Fencing-token-based claim/lease with hash-chained audit trail.

    Every ownership transition (claim, release) writes a row to `claim_log`
    with its own hash chain (engine-managed `prev_hash`, same formula as
    `events` and `status_log`). Heartbeats update `subjects.claimed_at` but
    do NOT write to `claim_log` — they are lease-liveness pings, not
    ownership changes."""

    def claim(self, subject_id: str, session_id: str,
              reason: ClaimReason = ClaimReason.CALLER_INITIATED,
              lease_ttl_seconds: int = 300) -> ClaimResult:
        """Atomic CAS claim. On success:
          1. Set claimed_by=session_id, claimed_at=now, increment claim_epoch.
          2. Append `claim_log` row (kind=CLAIMED, reason, actor=session_id).
          3. Fire `SUBJECT_CLAIMED` hook AFTER the row commits.
        Returns ClaimResult{claimed, claim_epoch}."""
        ...
    def release(self, subject_id: str, session_id: str,
                reason: ReleaseReason = ReleaseReason.CALLER_INITIATED) -> bool:
        """Release a claim held by `session_id`. On success:
          1. Null claimed_by, claimed_at (claim_epoch UNCHANGED — fencing token).
          2. Append `claim_log` row (kind=RELEASED, reason, actor=session_id).
          3. Fire `SUBJECT_RELEASED` hook."""
        ...
    def heartbeat(self, subject_id: str, session_id: str) -> bool:
        """Refresh the lease. Updates subjects.claimed_at only; NO claim_log
        row, NO hook fired. Returns False if the claim was already reaped."""
        ...
    def reap_stale_claims(self, lease_ttl_seconds: int = 300) -> int:
        """Reaper — releases claims older than TTL. For each reaped claim:
          1. Null claimed_by, claimed_at (claim_epoch UNCHANGED).
          2. Append `claim_log` row (kind=RELEASED,
             reason=ReleaseReason.LEASE_TTL_EXCEEDED, actor='system:reaper').
          3. Fire `SUBJECT_RELEASED` hook with the reaper's actor value.
        Returns the count of reaped claims."""
        ...

class ClaimLog(Protocol):
    """Append-only ownership-transition log with own hash chain (engine-managed
    prev_hash). Symmetric with `EventStore` (step chain) and `StatusLog`
    (flag chain). Records CLAIMED and RELEASED transitions only — heartbeats
    are excluded to keep write volume proportional to actual state change."""
    def append(self, subject_id: str, kind: "ClaimLogKind",
               session_id: str, claim_epoch: int, actor: str,
               reason: str | None) -> "ClaimLogEntry":
        """`reason` MUST be a ClaimReason value when kind=CLAIMED, a
        ReleaseReason value when kind=RELEASED. `actor` is the session_id
        for caller-initiated events, or 'system:reaper' / 'system:admin'
        for engine-initiated events. `prev_hash` is looked up internally
        from the previous row."""
        ...
    def load_history(self, subject_id: str) -> list["ClaimLogEntry"]: ...
    def load_currently_claimed(self) -> list[str]:
        """Convenience: subject_ids whose most-recent claim_log row has
        kind=CLAIMED. Cross-checked against subjects.claimed_by for
        consistency; discrepancies raise `PassportValidationError`."""
        ...

class EventStore(Protocol):
    def append(self, record: "StepRecord") -> None: ...       # write: hash fields ignored
    def load_events(self, subject_id: str) -> list["StepRecord"]: ...   # read: hash fields populated

class StatusLog(Protocol):
    """Separate append-only log for status flag events (cancelled/deferred/archived).
    Hash-chain is engine-managed — the implementation reads the previous row's
    row_hash internally; the caller does NOT pass prev_hash (Q29 decision)."""
    def append(self, subject_id: str, flag: str, actor: str,
               reason: str) -> "StatusLogEntry": ...
    def load_status(self, subject_id: str) -> list["StatusLogEntry"]: ...

class WorkflowDefinitionStore(Protocol):
    def load_definition(self, workflow_id: str, version: str) -> WorkflowDefinitionRecord: ...
    def save_definition(self, workflow_id: str, version: str,
                        definition_json: str) -> None: ...
```

### Data classification & redaction

```python
class Redactor(Protocol):
    def redact(self, value: Any) -> Any: ...

class DefaultRedactor:
    def redact(self, value: Any) -> Any:
        return "[REDACTED]"

class EmailRedactor:
    def redact(self, value: str) -> str:
        # jean.boutros@gmail.com → j***.b*****@g*****.com
        if not isinstance(value, str) or "@" not in value:
            return "[REDACTED]"
        local, domain = value.rsplit("@", 1)
        redacted_local = local[0] + "*" * (len(local) - 1) if local else "*"
        redacted_domain = domain[0] + "*" * (len(domain) - 1) if domain else "*"
        return f"{redacted_local}@{redacted_domain}"

class TokenRedactor:
    def redact(self, value: str) -> str:
        # abcd1234efgh5678xfg → abcd**************xfg
        if not isinstance(value, str) or len(value) <= 7:
            return "[REDACTED]"
        return value[:4] + "*" * (len(value) - 7) + value[-3:]

class RedactorRegistry:
    # Built-in: DefaultRedactor. Email/Token registered at startup or in profile.
    def register(self, name: str, redactor: Redactor) -> None: ...
    def resolve(self, name: str) -> Redactor: ...
```

**Schema-level annotation (JSON Schema custom keywords):**

```jsonc
{
  "api_key": { "type": "string", "classification": "protected", "redactor": "TokenRedactor" },
  "password": { "type": "string", "classification": "protected" },
  "internal_notes": { "type": "string", "classification": "private" },
  "title": { "type": "string" }
}
```

- No `classification` keyword → `private` (fail-closed default).
- `protected` with no `redactor` → `DefaultRedactor` → `[REDACTED]`.
- `private` → omitted entirely from events/logs/API/mirror.
- Classification applies to **primitives only**. Objects are not classified as a whole — their child fields are classified individually.
- `project()` recurses into object children unconditionally. Undeclared fields at any depth default to `private`.

**`project()` applied at every external boundary:**

```python
import re

def _classify_and_emit(value: Any, field_schema: dict | None,
                       redactors: RedactorRegistry) -> tuple[bool, Any]:
    """Return (emit?, projected_value). Default classification is private
    (fail-closed). Classification on primitives only."""
    if field_schema is None:
        return (False, None)  # Undeclared → private
    classification = field_schema.get("classification", "private")
    if classification == "private":
        return (False, None)
    if classification == "protected":
        redactor_name = field_schema.get("redactor", "DefaultRedactor")
        return (True, redactors.resolve(redactor_name).redact(value))
    if classification == "public":
        return (True, project(value, field_schema, redactors))
    return (False, None)  # Unknown classification token → private

def project(data: Any, schema: dict | None, redactors: RedactorRegistry) -> Any:
    """Omit private, redact protected, pass public. Recurses into nested
    objects and arrays. Default classification is private (fail-closed).
    Classification applies to primitives only. Honours additionalProperties
    and patternProperties (D-016).

    Fail-closed contract: if `schema is None` we cannot classify any field,
    so we omit everything (return None for primitives/objects, [] for lists).
    This prevents accidental cleartext leakage when a caller forgets to pass
    the matching schema."""
    if data is None:
        return None
    if schema is None:
        # Fail-closed: no schema → cannot classify → omit everything.
        if isinstance(data, list):
            return []
        if isinstance(data, dict):
            return {}
        return None  # Primitive without schema → private
    if isinstance(data, list):
        return [project(item, schema.get("items"), redactors) for item in data]
    if isinstance(data, dict):
        properties: dict = schema.get("properties", {})
        pattern_properties: dict = schema.get("patternProperties", {})
        additional_properties = schema.get("additionalProperties", False)
        # additionalProperties may be False (forbid extras), True (allow but
        # untyped → treat as private), or a sub-schema (apply classification).
        result: dict = {}
        for key, value in data.items():
            field_schema = properties.get(key)
            if field_schema is None:
                # Try patternProperties first
                for pattern, sub in pattern_properties.items():
                    if re.search(pattern, key):
                        field_schema = sub
                        break
            if field_schema is None and isinstance(additional_properties, dict):
                field_schema = additional_properties
            # else: still None → omit (private fail-closed)
            emit, projected = _classify_and_emit(value, field_schema, redactors)
            if emit:
                result[key] = projected
        return result
    return data
```

> **Load-time validation:** schemas with `unevaluatedProperties` are rejected
> by `WorkflowDefinitionError`. `additionalProperties: true` without a
> classification is allowed, but the matched fields default to `private`
> (omitted). Object-typed `additionalProperties` / `patternProperties` with a
> `classification` keyword are rejected — classification is on primitives only.

| Boundary | Projected? | Why |
|----------|-----------|-----|
| Passport JSON (stored) | No | Workflow needs real values |
| `ctx.vars` (handler context) | No | Handler needs real values |
| Event dispatch (hooks) | Yes | Events go to external bus |
| Audit log (events table) | Yes | Audit trail reviewed by humans |
| Markdown mirror | Yes | Humans review diffs |
| API responses (MCP/CLI) | Yes | External consumers |

---

## 3.1a Engine-Level Base JSON Schemas

These schemas are part of the engine contract. The engine validates passports,
gate configs, and workflow definitions against them at load time and on every
read. Projects MAY NOT modify them; they extend other schemas via the profile.

### `subject_id` — pattern (Q18 — two-tier validation)

The engine enforces a **fail-closed minimum pattern** on every `subject_id`
to prevent path traversal, control characters, and filesystem injection.
Profiles MAY tighten this pattern further (e.g. PSC forces the `TKT-0001`
shape) but MUST NOT weaken it.

**Engine minimum** (in `psc_engine.yaml → subject_id.engine_pattern`,
default):

```
^[A-Z0-9_-]{4,64}$
```

- Uppercase alphanumerics, hyphen, underscore only — no `/`, `.`, whitespace,
  or non-ASCII.
- 4–64 characters — bounded length prevents pathological allocations.

**PSC profile tightening** (in `psc_engine.yaml → subject_id.profile_pattern`):

```
^[A-Z]{3,4}-[0-9]{4,}$
```

Examples that match: `TKT-0001`, `SVY-0042`, `PRC-1234`, `REV-99999`.
Examples the engine rejects: `../etc/passwd`, `tkt-0001` (lowercase),
`TKT 0001` (space), `` (empty).

The engine validates against `subject_id.engine_pattern` first (fail-closed).
If a `profile_pattern` is configured, the engine also validates against it.
Load-time validation asserts the profile pattern is a **subset** of the
engine pattern (regex intersection check) — a profile MUST NOT allow shapes
the engine forbids.

### `passport.base` JSON Schema

```jsonc
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "passport.base",
  "type": "object",
  "required": ["subject_id", "workflow_id", "workflow_version", "state", "step_log"],
  "properties": {
    "subject_id": { "type": "string", "pattern": "^[A-Z0-9_-]{4,64}$" },
    "subject_id_profile_pattern": { "type": "string", "description": "Optional; if set, additional tightening applied by engine." },
    "subject_type": { "type": "string", "pattern": "^[a-z][a-z0-9_]*$" },
    "title": { "type": "string", "maxLength": 500 },
    "request": { "type": "string", "maxLength": 10000 },
    "requester": { "type": "string", "maxLength": 200 },
    "created_at": { "type": "string", "format": "date-time" },
    "updated_at": { "type": "string", "format": "date-time" },
    "workflow_id": { "type": "string", "pattern": "^[a-z][a-z0-9_-]*$" },
    "workflow_version": { "type": "string", "pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+$" },
    "profile_version": { "type": "string", "pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+$" },
    "status": {
      "type": "object",
      "properties": {
        "cancelled": { "type": "boolean" },
        "deferred":  { "type": "boolean" },
        "archived":  { "type": "boolean" }
      },
      "additionalProperties": false
    },
    "domain_classification": { "type": "object" },
    "state": {
      "type": "object",
      "required": ["current", "phase"],
      "properties": {
        "current":                  { "type": "string" },
        "phase":                    { "type": "string" },
        "entered_at":               { "type": "string", "format": "date-time" },
        "is_decision_pending":      { "type": "boolean" },
        "pending_decision_schema":  { "type": "string" }
      }
    },
    "retries_used": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "additionalProperties": { "type": "integer", "minimum": 0 }
      }
    },
    "review_round": { "type": "integer", "minimum": 0 },
    "vars": { "type": "object" },
    "step_log": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["step", "uuid", "verdict", "event_name", "idempotency_key"],
        "properties": {
          "step":            { "type": "string" },
          "role":            { "type": ["string", "null"] },
          "model":           { "type": ["string", "null"] },
          "started_at":      { "type": "string", "format": "date-time" },
          "completed_at":    { "type": ["string", "null"], "format": "date-time" },
          "status":          { "type": "string", "enum": ["complete", "validation_failed", "dispatched", "pending"] },
          "from_state":      { "type": ["string", "null"] },
          "entry_count":     { "type": "integer", "minimum": 1 },
          "attempt":         { "type": "integer", "minimum": 0 },
          "verdict":         { "type": "string" },
          "event_name":      { "type": "string" },
          "uuid":            { "type": "string", "format": "uuid" },
          "outcome_ref":     { "type": ["string", "null"] },
          "raw_ref":         { "type": ["string", "null"] },
          "idempotency_key": { "type": "string", "pattern": "^sha256:[0-9a-f]{64}$" }
        }
      }
    },
    "gate_results":      { "type": "array" },
    "decisions":         { "type": "array" },
    "loop_history":      { "type": "array" },
    "corrections":       { "type": "array" },
    "reviews":           { "type": "object" },
    "parallel_progress": { "type": "object" }
  }
}
```

The engine validates the passport against `passport.base` on every
`SubjectStore.load` and after every mutation before save. A validation failure
raises `PassportValidationError`.

### `gate_config.base` JSON Schema

```jsonc
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "gate_config.base",
  "type": "object",
  "required": ["tiers", "reentry_budget"],
  "properties": {
    "tiers": {
      "type": "array",
      "items": { "type": "string", "pattern": "^T[1-3]$|^T-ARCH$" },
      "minItems": 1,
      "uniqueItems": true
    },
    "reentry_budget": {
      "type": "object",
      "additionalProperties": {
        "type": "integer",
        "minimum": 1,
        "maximum": 10
      }
    },
    "round_budget": { "type": "integer", "minimum": 1, "maximum": 10 }
  },
  "additionalProperties": false
}
```

> **Note:** `tiers` and `reentry_budget` keys MUST be in
> `T1 | T2 | T3 | T-ARCH`. The engine enforces this at load time —
> misconfigured tier names raise `WorkflowDefinitionError`. The `maximum: 10`
> on `reentry_budget` matches `ENGINE_MAX_REENTRY_BUDGET`. The tier name
> pattern is engine-enforced and cannot be extended by profiles.

### `outcome.base` JSON Schema

Already defined in §3.1. Repeated here for completeness:

```jsonc
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "outcome.base",
  "type": "object",
  "required": ["verdict"],
  "properties": {
    "verdict":    { "type": "string" },
    "decision":   { "type": ["object", "null"] },
    "confidence": { "type": "integer", "minimum": 0, "maximum": 100 }
  }
}
```

### `step_record.base` JSON Schema (used by `EventStore.append`)

```jsonc
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "step_record.base",
  "type": "object",
  "required": ["uuid", "subject_id", "step", "verdict", "event_name", "idempotency_key", "timestamp"],
  "properties": {
    "uuid":            { "type": "string", "format": "uuid" },
    "subject_id":      { "type": "string", "pattern": "^[A-Z0-9_-]{4,64}$" },
    "step":            { "type": "string" },
    "role":            { "type": ["string", "null"] },
    "model":           { "type": ["string", "null"] },
    "from_state":      { "type": ["string", "null"] },
    "entry_count":     { "type": "integer", "minimum": 1 },
    "attempt":         { "type": "integer", "minimum": 0 },
    "verdict":         { "type": "string" },
    "event_name":      { "type": "string" },
    "status":          { "type": "string", "enum": ["complete", "validation_failed", "dispatched", "pending"] },
    "started_at":      { "type": "string", "format": "date-time" },
    "completed_at":    { "type": ["string", "null"], "format": "date-time" },
    "outcome_ref":     { "type": ["string", "null"] },
    "raw_ref":         { "type": ["string", "null"] },
    "idempotency_key": { "type": "string", "pattern": "^sha256:[0-9a-f]{64}$" },
    "timestamp":       { "type": "string", "format": "date-time" }
  }
}
```

### `event_name` — pattern

Domain event names use Kafka-topic-safe pattern. After `subject` is replaced
with the actual `subject_type`, the result MUST match:

```
^[a-z][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)+$
```

The engine re-validates the substituted `event_name` after substitution. A
failure aborts the transition with `WorkflowDefinitionError` at load time
(when discoverable) or `RoutingError` at runtime (when the substituted form
fails).

### `profile.base` JSON Schema (Q28)

The project profile file (e.g. `workflows/psc-profile.json`) defines
schemas, aggregation rule names, signals, and role mappings. The engine
validates every profile against this base schema at load time.

```jsonc
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "profile.base",
  "type": "object",
  "required": ["$id", "version", "schemas"],
  "properties": {
    "$id": { "type": "string" },
    "version": { "type": "string", "pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+$" },
    "schemas": {
      "type": "object",
      "description": "Named JSON Schemas for project outcomes, decisions, and payload types.",
      "additionalProperties": { "type": "object" }
    },
    "aggregation_rules": {
      "type": "object",
      "description": "Named aggregation rule identifiers (registered at runtime).",
      "additionalProperties": { "type": "string" }
    },
    "signals": {
      "type": "array",
      "description": "Signal-to-specialist mappings used by RosterResolver.",
      "items": {
        "type": "object",
        "required": ["specialist", "signals"],
        "properties": {
          "specialist": { "type": "string" },
          "signals": { "type": "array", "items": { "type": "string" }, "uniqueItems": true }
        }
      }
    },
    "role_mapping": {
      "type": "object",
      "description": "Abstract role → concrete agent/handler name.",
      "additionalProperties": { "type": "string" }
    },
    "redactors": {
      "type": "object",
      "description": "Named redactor implementations to register.",
      "additionalProperties": { "type": "string" }
    }
  },
  "additionalProperties": false
}
```

> **Note:** The engine ships a default profile validator; projects MAY
> extend the schema via `$defs` and `allOf` but MUST NOT weaken the
> `required` set or `additionalProperties: false` guarantee at the
> top level. `version` uses SemVer; workflows pin `profile_version`
> to a specific major/minor.

---

## 3.2 PSC Project Profile (Example — `workflows/psc-profile.json`)

> **Note:** A different project (survey, process, review) would define its
> own profile. The engine is agnostic to the profile's contents.

### PSC data structures (from example logs)

```python
# psc_engine/domain/outcomes.py — PSC-specific (in psc-profile.json)

class Severity(StrEnum):
    CRITICAL = "critical"    # ≥90 confidence, must fix
    HIGH = "high"            # 80-89, blocking
    MODERATE = "moderate"    # 70-79, should fix
    LOW = "low"              # 40-59, nice to have
    TRIVIAL = "trivial"      # 0-39, style/nit
    NONE = "none"            # no finding

class FindingStatus(StrEnum):
    OPEN = "open"
    RESOLVED = "resolved"
    WONT_FIX = "wont_fix"

class Priority(StrEnum):
    MUST_FIX = "must_fix"
    SHOULD_FIX = "should_fix"
    CONSIDER = "consider"

@dataclass(frozen=True)
class Finding:
    id: str                    # "F1", "GAP-1", "CR1-F1"
    confidence: int            # 0-100; ≥80 = blocking
    severity: Severity
    category: str              # "security", "architecture", "test", "docs", etc.
    description: str
    file_line: str | None     # "postrm:163-178"
    suggested_fix: str | None
    status: FindingStatus
    reference: "Reference | None"

@dataclass(frozen=True)
class Gap:
    id: str                    # "GAP-1"
    confidence: int
    finding: str               # description
    impact: str
    severity: Severity
    recommendation: str

@dataclass(frozen=True)
class Recommendation:
    id: str                    # "R1"
    priority: Priority
    description: str
    confidence: int
    addresses: list[str]       # finding IDs this recommendation resolves
    links: list[str]

@dataclass(frozen=True)
class Reference:
    claim: str
    source: str                # "Debian Policy Manual v4.7.4.1, §6.5"
    url: str
    verification_date: str    # ISO date

@dataclass(frozen=True)
class Deliverable:
    type: str                  # "file" / "adr" / "decision" / "advisory" / "clarification"
    ref: str
    sha: str | None
    lines_changed: str | None  # "+19 lines"

@dataclass(frozen=True)
class Agreement:
    id: str
    description: str
    covers: list[str]
    links: list[str]

@dataclass(frozen=True)
class Disagreement:
    id: str
    description: str
    primary_view: str
    challenger_view: str
    links: list[str]

@dataclass(frozen=True)
class MissingConsideration:
    id: str
    description: str
    edge_case: str
    links: list[str]

@dataclass(frozen=True)
class GateResult:
    gate: str
    tier: str
    result: str                # "pass" / "fail"
    attempt: int

@dataclass(frozen=True)
class SpecialistVerdict:
    specialist: str
    verdict: str
    key_findings: str

@dataclass(frozen=True)
class CorrectionRecord:
    retry: int
    gate: str
    tier: str
    rc_category: str           # RC-1..RC-5
    root_cause: str
    corrective_action: str

@dataclass(frozen=True)
class PlanUnit:
    unit_number: int
    description: str
    files: list[str]

@dataclass(frozen=True)
class ApplyUnit:
    unit_number: int
    build_result: str
    files_changed: str
    what_was_done: str

@dataclass(frozen=True)
class ValidateResult:
    full_build: str
    ac_coverage: str
    acceptance_criteria: list[str]

@dataclass(frozen=True)
class SelfAuditEntry:
    category: str
    checked: str              # "yes" / "N/A"
    result: str              # "PASS" / finding description

@dataclass(frozen=True)
class SelfReflection:
    why: str
    what_caught_it: str
    knowledge_update: str

@dataclass(frozen=True)
class OWASPExpansion:
    concern_category: str    # "Firmware Updates (A08)"
    trigger: str
    assessment: str          # "PASS" + evidence

@dataclass(frozen=True)
class NewTicketCreated:
    ticket_id: str
    type: str
    reason: str
```

### PSC outcome schemas (allOf outcome.base + PSC fields)

Each PSC outcome schema inherits the engine contract and adds PSC-specific
payload fields:

```jsonc
"psc.outcome.specialist_review": {
  "allOf": [
    { "$ref": "outcome.base" },
    {
      "type": "object",
      "properties": {
        "findings": { "type": "array", "items": { "$ref": "psc.finding" } },
        "recommendations": { "type": "array", "items": { "$ref": "psc.recommendation" } },
        "gaps": { "type": "array", "items": { "$ref": "psc.gap" } },
        "deliverables": { "type": "array", "items": { "$ref": "psc.deliverable" } },
        "references": { "type": "array", "items": { "$ref": "psc.reference" } },
        "self_audit": { "type": "array", "items": { "$ref": "psc.self_audit_entry" } },
        "self_reflection": { "$ref": "psc.self_reflection" },
        "owasp_expansion": { "type": "array", "items": { "$ref": "psc.owasp_expansion" } }
      }
    }
  ]
}
```

### PSC decision schemas (discriminated unions)

```jsonc
"decision.roster_confirmation": {
  "type": "object",
  "required": ["roster", "rationale"],
  "properties": {
    "roster": {
      "type": "array",
      "items": { "type": "string", "pattern": "^[a-z][a-z0-9_-]*$" },
      "minItems": 1, "maxItems": 10, "uniqueItems": true
    },
    "rationale": { "type": "string", "maxLength": 2000 }
  },
  "additionalProperties": false
}
```

```jsonc
"decision.user_disposition": {
  "type": "object",
  "required": ["findings"],
  "properties": {
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "disposition"],
        "properties": {
          "id": { "type": "string" },
          "disposition": {
            "type": "string",
            "enum": ["IMPLEMENT_NOW", "ACCEPT", "DEFER", "REJECT"]
          },
          "rationale": { "type": "string", "maxLength": 2000 }
        },
        "additionalProperties": false
      },
      "minItems": 1
    }
  },
  "additionalProperties": false
}
```

```jsonc
"decision.c4_completion": {
  "type": "object",
  "required": ["decision"],
  "oneOf": [
    { "properties": { "decision": { "const": "complete" }, "rationale": { "type": "string" } },
      "required": ["decision", "rationale"] },
    { "properties": { "decision": { "const": "rework" }, "rationale": { "type": "string" },
      "rework_scope": { "type": "array", "items": { "type": "string" } } },
      "required": ["decision", "rationale", "rework_scope"] },
    { "properties": { "decision": { "const": "backlog_split" }, "rationale": { "type": "string" },
      "backlog_refs": { "type": "array", "items": { "type": "string" } } },
      "required": ["decision", "rationale", "backlog_refs"] },
    { "properties": { "decision": { "const": "escalate" }, "rationale": { "type": "string" } },
      "required": ["decision", "rationale"] },
    { "properties": { "decision": { "const": "defer" }, "rationale": { "type": "string" },
      "defer_until": { "type": "string" } },
      "required": ["decision", "rationale", "defer_until"] },
    { "properties": { "decision": { "const": "add_tests" }, "rationale": { "type": "string" },
      "test_scope": { "type": "array", "items": { "type": "string" } } },
      "required": ["decision", "rationale", "test_scope"] }
  ]
}
```

### Verdict-conditional outputs (discriminated union on verdict)

```jsonc
"outcome.review_verdict": {
  "type": "object",
  "required": ["verdict"],
  "oneOf": [
    { "properties": { "verdict": { "const": "approve" }, "note": { "type": "string" },
      "links": { "type": "array", "items": { "type": "string" } } },
      "required": ["verdict", "note"] },
    { "properties": { "verdict": { "const": "reject" }, "reason": { "type": "string" } },
      "required": ["verdict", "reason"] },
    { "properties": { "verdict": { "const": "conditional_pass" },
      "concerns": { "type": "array", "items": { "type": "string" } } },
      "required": ["verdict", "concerns"] }
  ]
}
```

---

## 3.3 Workflow Definition JSON

ASL-influenced. States map + `start_at` + transitions with mandatory `event_name`
+ `loop` flag + `outcome_schema`. Gates have NO `dispatch_handler` or `retry` blocks.
`agent` field uses abstract roles (orchestrator/architect/reviewer) mapped via profile.

### `psc-main` workflow (with event_name on every transition)

```jsonc
{
  "workflow_id": "psc-main",
  "version": "2.0.0",
  "profile_version": "1.0.0",
  "subject_type": "ticket",
  "start_at": "A0",
  "phases": [
    {"id":"A","ord":0}, {"id":"B","ord":1}, {"id":"C","ord":2}, {"id":"CR","ord":3}
  ],
  "states": {
    "A0": {
      "name":"A0","title":"Task Definition & Roster Proposal",
      "phase":"A","step":0,"kind":"task",
      "role":"orchestrator",
      "dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.roster_proposal",
      "outputs": {
        "produced": {
          "/domain_classification": "$.domain_classification",
          "/proposed_roster": "$.roster"
        },
        "carried_forward": true
      },
      "transitions": {
        "proposed": {"target":"A0c","event_name":"subject.phase-a.roster-proposed"}
      }
    },
    "A0c": {
      "name":"A0c","title":"Roster Confirmation",
      "phase":"A","step":1,"kind":"decision_required",
      "role":"reviewer",
      "decision_schema":"decision.roster_confirmation",
      "routing_rule":"route.roster_confirmation",
      "inputs": { "required": ["$.proposed_roster", "$.domain_classification"] },
      "outputs": { "produced": {"/roster": "$.roster"}, "carried_forward": true },
      "transitions": {}
    },
    "A1": {
      "name":"A1","title":"Parallel Specialist Review",
      "phase":"A","step":2,"kind":"parallel",
      "role":"orchestrator",
      "dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.specialist_composite",
      "branch_schema":"psc.outcome.specialist_review",
      "aggregation_rule":"psc.aggregation.specialist_composite",
      "fan_out":"$roster","join":{"type":"all"},
      "transitions": { "reviews_complete":{"target":"A2","event_name":"subject.phase-a.reviews-complete"} }
    },
    "A2": {
      "name":"A2","title":"Dual-Model Challenge",
      "phase":"A","step":3,"kind":"parallel",
      "role":"orchestrator",
      "dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.challenge_composite",
      "branch_schema":"psc.outcome.challenge_branch",
      "aggregation_rule":"psc.aggregation.challenge_composite",
      "fan_out":["primary","challenger"],"join":{"type":"all"},
      "transitions": { "challenge_complete":{"target":"A2b","event_name":"subject.phase-a.challenge-complete"} }
    },
    "A2b": {
      "name":"A2b","title":"Synthesis Artifact Creation",
      "phase":"A","step":4,"kind":"task",
      "role":"architect",
      "dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.synthesis",
      "transitions": { "synthesized":{"target":"A2c","event_name":"subject.phase-a.synthesized"} }
    },
    "A2c": {
      "name":"A2c","title":"Decision Register Presentation",
      "phase":"A","step":5,"kind":"task",
      "role":"reviewer",
      "dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.disposition_proposal",
      "inputs": { "required": ["$.findings"], "optional": ["$.synthesis_ref"] },
      "outputs": {
        "produced": {"/proposed_dispositions": "$.findings[*].proposed_disposition"},
        "carried_forward": true
      },
      "transitions": { "presented":{"target":"A2cc","event_name":"subject.phase-a.disposition-presented"} }
    },
    "A2cc": {
      "name":"A2cc","title":"User Disposition Decision",
      "phase":"A","step":6,"kind":"decision_required",
      "role":"reviewer",
      "decision_schema":"decision.user_disposition",
      "routing_rule":"route.user_disposition",
      "inputs": { "required": ["$.proposed_dispositions", "$.findings"] },
      "outputs": { "produced": {"/dispositions": "$.findings[*].disposition"}, "carried_forward": true },
      "transitions": {}
    },
    "A2a": {
      "name":"A2a","title":"ADR Creation",
      "phase":"A","step":7,"kind":"task",
      "role":"architect",
      "dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.adr",
      "transitions": { "adr_written":{"target":"A3","event_name":"subject.phase-a.adr-written"} }
    },
    "A3": {
      "name":"A3","title":"A-GATE",
      "phase":"A","step":8,"kind":"gate",
      "role":"orchestrator",
      "gate_config":"gate.A3",
      "transitions": {
        "pass":      {"target":"B1","event_name":"subject.phase-a.gate-passed"},
        "fail":      {"target":"A2a","loop":true,"event_name":"subject.phase-a.gate-failed"},
        "exhausted": {"target":"ESCALATE","event_name":"subject.phase-a.gate-exhausted"}
      }
    },
    "B1": { "name":"B1","title":"PLAN","phase":"B","step":0,"kind":"task",
      "role":"architect",
      "dispatch_handler":"engine.subagent_dispatch","outcome_schema":"psc.outcome.plan",
      "transitions": { "planned":{"target":"B2","event_name":"subject.phase-b.planned"} } },
    "B2": { "name":"B2","title":"APPLY (per unit)","phase":"B","step":1,"kind":"task",
      "role":"architect",
      "dispatch_handler":"engine.subagent_dispatch","outcome_schema":"psc.outcome.unit_apply",
      "transitions": {
        "unit_applied":{"target":"B2a","event_name":"subject.phase-b.unit-applied"},
        "units_complete":{"target":"B3","event_name":"subject.phase-b.units-complete"} } },
    "B2a": { "name":"B2a","title":"B-UNIT-GATE","phase":"B","step":2,"kind":"gate",
      "role":"orchestrator",
      "gate_config":"gate.B2a",
      "transitions": {
        "pass":{"target":"B2","event_name":"subject.phase-b.unit-gate-passed"},
        "fail":{"target":"B2","loop":true,"event_name":"subject.phase-b.unit-gate-failed"},
        "exhausted":{"target":"ESCALATE","event_name":"subject.phase-b.unit-gate-exhausted"} } },
    "B3": { "name":"B3","title":"VALIDATE","phase":"B","step":3,"kind":"task",
      "role":"architect",
      "dispatch_handler":"engine.subagent_dispatch","outcome_schema":"psc.outcome.validate",
      "transitions": { "validated":{"target":"B3a","event_name":"subject.phase-b.validated"} } },
    "B3a": { "name":"B3a","title":"B-FINAL-GATE","phase":"B","step":4,"kind":"gate",
      "role":"orchestrator",
      "gate_config":"gate.B3a",
      "transitions": {
        "pass":{"target":"C0","event_name":"subject.phase-b.final-gate-passed"},
        "fail":{"target":"B1","loop":true,"event_name":"subject.phase-b.final-gate-failed"},
        "exhausted":{"target":"ESCALATE","event_name":"subject.phase-b.final-gate-exhausted"} } },
    "C0": { "name":"C0","title":"T1 Re-run","phase":"C","step":0,"kind":"task",
      "role":"orchestrator",
      "dispatch_handler":"engine.subagent_dispatch","outcome_schema":"psc.outcome.t1_rerun",
      "transitions": { "done":{"target":"C1","event_name":"subject.phase-c.t1-rerun-done"} } },
    "C1": { "name":"C1","title":"Dual-Model Challenge (Verification)","phase":"C","step":1,"kind":"parallel",
      "role":"orchestrator","dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.challenge_composite",
      "branch_schema":"psc.outcome.challenge_branch",
      "aggregation_rule":"psc.aggregation.challenge_composite",
      "fan_out":["primary","challenger"],"join":{"type":"all"},
      "transitions": { "challenge_complete":{"target":"C2","event_name":"subject.phase-c.challenge-complete"} } },
    "C2": { "name":"C2","title":"Parallel Specialist Approval","phase":"C","step":2,"kind":"parallel",
      "role":"orchestrator","dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.approval_composite",
      "branch_schema":"psc.outcome.approval_branch",
      "aggregation_rule":"psc.aggregation.approval_composite",
      "fan_out":"$roster","join":{"type":"all"},
      "transitions": {
        "all_approved":{"target":"C3","event_name":"subject.phase-c.all-approved"},
        "any_rejected":{"target":"CR1","event_name":"subject.phase-c.any-rejected"} } },
    "C3": { "name":"C3","title":"C-GATE","phase":"C","step":3,"kind":"gate",
      "role":"orchestrator",
      "gate_config":"gate.C3",
      "transitions": {
        "pass":{"target":"C4p","event_name":"subject.phase-c.gate-passed"},
        "fail":{"target":"B1","loop":true,"event_name":"subject.phase-c.gate-failed"},
        "exhausted":{"target":"ESCALATE","event_name":"subject.phase-c.gate-exhausted"} } },
    "C4p": { "name":"C4p","title":"PM Completion Analysis (propose)","phase":"C","step":4,"kind":"task",
      "role":"architect","dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.completion_analysis",
      "outputs": { "produced": {"/proposed_decision": "$.recommendation"}, "carried_forward": true },
      "transitions": { "analysed": {"target":"C4","event_name":"subject.phase-c.completion-analysed"} } },
    "C4": { "name":"C4","title":"PM Completion Review (decide)","phase":"C","step":5,"kind":"decision_required",
      "role":"reviewer",
      "decision_schema":"decision.c4_completion","routing_rule":"route.c4",
      "inputs": { "required": ["$.proposed_decision", "$.findings"] },
      "transitions": {} },
    "CR1": { "name":"CR1","title":"Code Review Round","phase":"CR","step":0,"kind":"task",
      "role":"reviewer",
      "dispatch_handler":"engine.subagent_dispatch","outcome_schema":"psc.outcome.review",
      "transitions": { "reviewed":{"target":"CR2","event_name":"subject.phase-cr.reviewed"} } },
    "CR2": { "name":"CR2","title":"CR-GATE","phase":"CR","step":1,"kind":"gate",
      "role":"orchestrator",
      "gate_config":"gate.CR2",
      "transitions": {
        "pass":      {"target":"CR3","event_name":"subject.phase-cr.accept"},
        "fail":      {"target":"B2","loop":true,"event_name":"subject.phase-cr.request-changes"},
        "exhausted": {"target":"ESCALATE","event_name":"subject.phase-cr.exhausted"} } },
    "CR3": { "name":"CR3","title":"Review Acceptance","phase":"CR","step":2,"kind":"task",
      "role":"reviewer",
      "dispatch_handler":"engine.subagent_dispatch","outcome_schema":"psc.outcome.acceptance",
      "transitions": { "accepted":{"target":"COMMIT","event_name":"subject.phase-cr.accepted"} } },
    "COMMIT":   { "name":"COMMIT","title":"Commit","phase":"CR","step":3,"kind":"terminal" },
    "ESCALATE": { "name":"ESCALATE","title":"Escalate","phase":"CR","step":4,"kind":"terminal" }
  },
  "gate_configs": {
    "gate.A3":  {"tiers":["T3","T-ARCH"],"reentry_budget":{"T3":3,"T-ARCH":3}},
    "gate.B2a": {"tiers":["T1","T-ARCH"],"reentry_budget":{"T1":3,"T-ARCH":3}},
    "gate.B3a": {"tiers":["T1","T2","T-ARCH"],"reentry_budget":{"T1":3,"T2":3,"T-ARCH":3}},
    "gate.C3":  {"tiers":["T1","T3","T-ARCH"],"reentry_budget":{"T1":3,"T3":3,"T-ARCH":3}},
    "gate.CR2": {"tiers":["T3"],"reentry_budget":{"T3":5},"round_budget":5}
  },
  "routing_rules": {
    "route.roster_confirmation": {
      "CASE": [
        {"WHEN": "$.roster[*]", "THEN": {"target":"A1","event_name":"subject.phase-a.roster-confirmed"}}
      ],
      "ELSE": {"target":"A0","loop":true,"event_name":"subject.phase-a.roster-rejected"}
    },
    "route.user_disposition": {
      "CASE": [
        {"WHEN": "$.findings[?(@.disposition==\"IMPLEMENT_NOW\" || @.disposition==\"ACCEPT\")]",
         "THEN": {"target":"A2a","event_name":"subject.phase-a.disposition-accepted"}}
      ],
      "ELSE": {"target":"A3","event_name":"subject.phase-a.disposition-rejected"}
    },
    "route.c4": {
      "CASE": [
        {"WHEN": "$[?(@.decision==\"complete\")]",      "THEN": {"target":"CR1","event_name":"subject.phase-c.complete"}},
        {"WHEN": "$[?(@.decision==\"backlog_split\")]", "THEN": {"target":"CR1","event_name":"subject.phase-c.backlog-split"}},
        {"WHEN": "$[?(@.decision==\"rework\")]",        "THEN": {"target":"B1","loop":true,"event_name":"subject.phase-c.rework"}},
        {"WHEN": "$[?(@.decision==\"escalate\")]",      "THEN": {"target":"ESCALATE","event_name":"subject.phase-c.escalate"}},
        {"WHEN": "$[?(@.decision==\"defer\")]",         "THEN": {"target":"C4p","event_name":"subject.phase-c.deferred"}},
        {"WHEN": "$[?(@.decision==\"add_tests\")]",     "THEN": {"target":"B1","loop":true,"event_name":"subject.phase-c.add-tests"}}
      ],
      "ELSE": {"target":"C4p","event_name":"subject.phase-c.unknown-decision"}
    }
  }
}
```

> **Note:** `event_name` uses `subject.*` prefix in the definition. At
> dispatch time, the engine replaces `subject` with the actual `subject_type`
> (e.g. `ticket.phase-a.classified`). Routing rules use SQL-CASE-style:
> `CASE WHEN condition THEN target; ELSE default; END`. Every branch has
> mandatory `event_name`. Gates have NO `dispatch_handler` or `retry` blocks.
> `agent` replaced by `role` (orchestrator/architect/reviewer) — mapped to
> agent/human/service via profile. `retry_policy` and `max_review_rounds` removed.
> `reentry_budget` replaces `retry_budget`. `defer` decision sets status flag
> (not a synthetic `DEFERRED` state).
>
> **Decision-state pairing (Q2 resolution):** Every user-facing decision is
> split into two consecutive states — one `task` that PROPOSES (Supreme Leader
> or PM analyses inputs, produces a recommendation), and one `decision_required`
> that CONFIRMS/DECIDES (blocks until `record_decision()`). This separates the
> "propose" concern from the "decide" concern. The pairs in `psc-main` are:
> - `A0` (propose roster) → `A0c` (confirm roster)
> - `A2c` (present dispositions) → `A2cc` (user decides dispositions)
> - `C4p` (propose completion analysis) → `C4` (PM decides completion)
> The routing rule (e.g. `route.roster_confirmation`) is attached to the
> `decision_required` state, not the `task` state. The `task` state just
> emits `verdict: "proposed"|"presented"|"analysed"` and transitions
> deterministically to its paired `decision_required` state.

---

## 3.4 Passport JSON

The passport is the **runtime state** — what the engine needs for the next
routing decision. The `step_log` is an INDEX, never a container. Full outcome
content lives in `OutcomeStore` and is loaded on demand via `load_outcome()`.

```jsonc
{
  "subject_id": "TKT-0001",
  "subject_type": "ticket",
  "title": "Add BLE scan filter",
  "request": "<original instruction>",
  "requester": "user",
  "created_at": "2026-06-29T10:00:00Z",
  "updated_at": "2026-06-29T11:30:00Z",
  "workflow_id": "psc-main",
  "workflow_version": "2.0.0",
  "profile_version": "1.0.0",

  "status": {
    "cancelled": false,
    "deferred": false,
    "archived": false
  },

  "domain_classification": {
    "primary":"security","secondary":["test"],
    "roster":["security","test","design"]
  },

  "state": {
    "current":"A2c","phase":"A","entered_at":"2026-06-29T11:00:00Z",
    "is_decision_pending":true,"pending_decision_schema":"decision.user_disposition"
  },

  "retries_used": {
    "A3": {"T3":1}
  },
  "review_round": 0,
  "vars": {},
  "step_log": [
    {"step":"A0","role":"orchestrator","model":"glm-5.2",
     "started_at":"...","completed_at":"...",
     "status":"complete","from_state":null,"entry_count":1,"attempt":0,
     "event_name":"ticket.phase-a.roster-confirmed",
     "uuid":"01923a8b-...","outcome_ref":"outcomes/TKT-0001/A0/01923a8b-....json",
     "raw_ref":null,"idempotency_key":"sha256:abc123..."}
  ],
  "gate_results": [], "decisions": [], "loop_history": [], "corrections": [],
  "reviews": {"current_round":0,"rounds":[]},
  "parallel_progress": {
    "A1": {"expected":["security","test","design"],
           "returned":{"security":{"verdict":"pass","outcome_ref":"...","uuid":"...","timestamp":"..."}},
           "pending":["test","design"],
           "join":{"type":"all"}}
  }
}
```

> **Note:** No `agent_snapshot` field — agents are NOT snapshotted. The engine
> resolves agent files from `agents_folder` at dispatch time (always latest).
> If agent changes, a warning is issued. `outcomes` dict removed — `step_log`
> is the index. `skips`, `version_pins`, `is_adhoc`, `stamp` removed.
> `retries` → `retries_used` (lazy init, entries on first use only).
> `status` block added for cancelled/deferred/archived flags.
> `event_name` and `idempotency_key` on each `step_log` entry.
> `max_review_rounds` removed; `round_budget` on gate.
> `profile_version` pins the schema profile version.

---

## 3.5 Physical Data Model — SQLite

```sql
PRAGMA foreign_keys = ON;

CREATE TABLE subjects (
    id                       TEXT PRIMARY KEY,
    workflow_id              TEXT NOT NULL,
    workflow_version         TEXT NOT NULL,
    workflow_definition_hash TEXT NOT NULL,        -- Q22: SHA-256 of pinned workflow JSON
    profile_version          TEXT NOT NULL DEFAULT '1.0.0',
    subject_type             TEXT NOT NULL DEFAULT 'ticket',
    active_steps             TEXT NOT NULL DEFAULT '[]',
    state_json               TEXT NOT NULL,
    claimed_by               TEXT,
    claimed_at               TEXT,
    claim_epoch              INTEGER NOT NULL DEFAULT 0,
    version                  INTEGER NOT NULL DEFAULT 1,
    updated_at               TEXT NOT NULL
);
CREATE INDEX idx_subjects_claimed_at ON subjects(claimed_at);

CREATE TABLE subjects_summary (
    subject_id      TEXT PRIMARY KEY REFERENCES subjects(id),
    title           TEXT,
    current_state   TEXT,
    phase           TEXT,
    is_terminal     INTEGER NOT NULL DEFAULT 0,
    is_cancelled    INTEGER NOT NULL DEFAULT 0,
    is_deferred     INTEGER NOT NULL DEFAULT 0,
    is_archived     INTEGER NOT NULL DEFAULT 0,
    updated_at      TEXT NOT NULL
);

CREATE TABLE workflow_definitions (
    id              TEXT NOT NULL,
    version         TEXT NOT NULL,
    profile_version TEXT NOT NULL,                 -- Q32: denormalised for query
    definition      TEXT NOT NULL,
    definition_hash TEXT NOT NULL,                 -- Q22: SHA-256 of definition JSON
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    PRIMARY KEY (id, version)
);
CREATE INDEX idx_workflow_definitions_profile ON workflow_definitions(profile_version);

CREATE TABLE events (
    uuid            TEXT PRIMARY KEY,
    subject_id      TEXT NOT NULL REFERENCES subjects(id),
    step            TEXT NOT NULL,
    role            TEXT,
    model           TEXT,
    from_state      TEXT,
    entry_count     INTEGER NOT NULL,
    attempt         INTEGER NOT NULL,
    verdict         TEXT NOT NULL,
    event_name      TEXT NOT NULL,
    status          TEXT NOT NULL CHECK (status IN ('complete','validation_failed','dispatched','pending')),
    started_at      TEXT NOT NULL,
    completed_at    TEXT,
    outcome_ref     TEXT,
    raw_ref         TEXT,
    idempotency_key TEXT NOT NULL UNIQUE,
    timestamp       TEXT NOT NULL,
    prev_hash       TEXT,
    row_hash        TEXT NOT NULL
);
CREATE INDEX idx_events_subject ON events(subject_id, uuid);
CREATE INDEX idx_events_idempotency ON events(idempotency_key);

CREATE TABLE status_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    subject_id  TEXT NOT NULL REFERENCES subjects(id),
    flag        TEXT NOT NULL,
    actor       TEXT,
    reason      TEXT,
    ts          TEXT NOT NULL,
    prev_hash   TEXT,
    row_hash    TEXT NOT NULL
);
CREATE INDEX idx_status_log_subject ON status_log(subject_id, id);

CREATE TABLE claim_log (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    subject_id   TEXT NOT NULL REFERENCES subjects(id),
    kind         TEXT NOT NULL CHECK (kind IN ('claimed','released')),
    session_id   TEXT NOT NULL,
    claim_epoch  INTEGER NOT NULL,
    actor        TEXT NOT NULL,        -- session_id for caller, 'system:reaper' for reaper
    reason       TEXT NOT NULL,         -- ClaimReason value (kind=claimed)
                                        -- ReleaseReason value (kind=released)
    ts           TEXT NOT NULL,
    prev_hash    TEXT,
    row_hash     TEXT NOT NULL
);
CREATE INDEX idx_claim_log_subject   ON claim_log(subject_id, id);
CREATE INDEX idx_claim_log_currency  ON claim_log(subject_id, id DESC);
CREATE INDEX idx_claim_log_ttl_reap  ON claim_log(reason, ts) WHERE reason='lease_ttl_exceeded';
```

> **Note:** `claim_epoch` is a fencing token — monotonically increasing,
> assigned on each successful `claim()`. All writes CAS on `version` AND
> `claim_epoch`. `events` table has a SHA-256 hash chain:
> `row_hash = sha256(prev_hash || canonical_json(row_data))` where
> `row_data` is the canonical JSON serialisation (RFC 8785 JCS) of the
> row's persisted fields in declaration order, excluding `row_hash` itself.
> Genesis row uses `prev_hash = sha256("GENESIS:" || workflow_id || ":" || subject_id)`.
> `status_log` is a separate append-only log for status-flag events
> (cancelled/deferred/archived) with its own hash chain (same formula).
> `claim_log` is a separate append-only log for ownership transitions
> (claimed/released) with its own hash chain — heartbeats are excluded
> (they update `subjects.claimed_at` directly). Three chains total:
> `events` (step transitions), `status_log` (flag events), `claim_log`
> (ownership transitions). `subjects_summary` for fast queries without
> loading full `state_json`. SQLite migrations via numbered SQL files.
> `PRAGMA foreign_keys = ON` per connection.

---

## 3.6 JSONPath for Inputs, Outputs, and Routing

Uses `python-jsonpath` (RFC 9535 read + RFC 6901 JSON Pointer write).

### Inputs — JSONPath expressions validated before dispatch

```jsonc
"inputs": {
  "required": ["$.findings", "$.domain_classification.roster"],
  "optional": ["$.synthesis_ref"]
}
```

`advance()` validates each required path returns a non-empty nodelist via
`python_jsonpath.find(path, ctx.vars)` before dispatching. Missing → `STATUS: BLOCKED`.

### Outputs — path-to-path mapping (JSON Pointer keys + JSONPath values)

```jsonc
"outputs": {
  "produced": {
    "/dispositions": "$.findings[*].disposition",
    "/decisions": "$.decision"
  },
  "carried_forward": true
}
```

Keys are JSON Pointer paths (RFC 6901) for writing to `ctx.vars`. Values are
JSONPath expressions (RFC 9535) for reading from the outcome. `carried_forward`
means produced outputs are merged into `ctx.vars` of the target state.

### Routing rules — SQL-CASE-style with RFC 9535 filter selectors

```jsonc
"route.user_disposition": {
  "CASE": [
    {"WHEN": "$.findings[?(@.disposition==\"IMPLEMENT_NOW\" || @.disposition==\"ACCEPT\")]",
     "THEN": {"target":"A2a","event_name":"subject.phase-a.disposition-accepted"}}
  ],
  "ELSE": {"target":"A3","event_name":"subject.phase-a.disposition-rejected"}
}
```

Engine evaluates each `WHEN` condition via `python_jsonpath.find(condition, ctx.vars)`.
First non-empty nodelist → `THEN` branch. No match → `ELSE` branch. Every branch
has mandatory `event_name`. JSONPath filter syntax per RFC 9535:
`[?(@.field=="value")]`.

> **JSONPath rules for routing conditions:**
> 1. Each `WHEN` MUST be a valid RFC 9535 JSONPath expression. The engine
>    evaluates it against `ctx.vars` and treats a **non-empty nodelist** as
>    truthy and an **empty nodelist** as falsy.
> 2. To test a scalar at the root, wrap the comparison in a filter selector
>    on the root: `$[?(@.decision=="complete")]` — NOT `$.decision == "complete"`,
>    which is not a JSONPath expression at all.
> 3. To test array non-empty, use the wildcard selector: `$.roster[*]` —
>    yields no nodes for `[]`, one or more nodes otherwise.
> 4. To test array contains an element matching a predicate, use a filter
>    selector inside the array: `$.findings[?(@.disposition=="ACCEPT")]`.
> 5. Load-time validation: the engine parses every `WHEN` with
>    `python_jsonpath.parse` and raises `WorkflowDefinitionError` on any
>    malformed expression. Quoted strings inside `WHEN` use escaped
>    double-quotes per JSON spec.

---

## 3.7 Config — `psc_engine.yaml`

```yaml
paths:
  agents_folder: agents
  workflows_folder: workflows
  passports_folder: docs/project-management/passports
  outcomes_folder: docs/project-management/outcomes
  db_path: docs/project-management/psc.db

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

claim:
  lease_ttl_seconds: 300
  heartbeat_interval_seconds: 150      # default = lease_ttl // 2

projection:
  max_depth: 50                        # Q19 — bound project() recursion

subject_id:
  # Q18 — engine-minimum pattern (no path traversal); profile may tighten
  engine_pattern: "^[A-Z0-9_-]{4,64}$"
  # Optional: profile-specific pattern (must be a tightening — subset of engine_pattern)
  profile_pattern: "^[A-Z]{3,4}-[0-9]{4,}$"

roster:
  default: [sw-engineer, test-engineer, docs-writer]
  minimum: [sw-engineer, test-engineer, docs-writer]
  max: 10
  signals:
    - specialist: hardware-engineer
      signals: [hardware, registers, gpio, timers, peripherals]
    - specialist: wireless-expert
      signals: [wireless, rf, ble, radio]
    - specialist: security-reviewer
      signals: [auth, secrets, crypto, network, input-parsing]
    - specialist: bash-specialist
      signals: [shell, bash, posix-sh]

role_mapping:
  orchestrator: supreme-leader
  architect: code-architect
  reviewer: code-reviewer
```

Any `<name>.md` in `agents_folder` is a valid specialist — selectable at A0
even if not in the signals list. `dispatch_retry` defines global retry with
exponential backoff for transient dispatch failures; overridable per-state.
`reentry_budget` defines global default for gate re-entry after loop-back;
overridable per-gate. `role_mapping` maps abstract roles to concrete agent names.
`claim.heartbeat_interval_seconds` (Q21) is used by the `claimed()` context
manager to refresh the lease. `projection.max_depth` (Q19) caps `project()`
recursion; exceeding it raises `ProjectDepthExceeded`. `subject_id.engine_pattern`
(Q18) is the fail-closed engine minimum; `subject_id.profile_pattern` may
further tighten it but must be a subset.
`SignalMatcher` uses case-fold matching, pluggable via profile.

---

## 3.8 State Model (Python prototype)

```python
# psc_engine/domain/state.py — Python 3.14+
from dataclasses import dataclass, field
from enum import StrEnum

class StateKind(StrEnum):
    TASK = "task"
    PARALLEL = "parallel"
    GATE = "gate"
    DECISION_REQUIRED = "decision_required"
    TERMINAL = "terminal"

# Exception hierarchy — every workflow-engine error inherits from WorkflowError
# so callers can `except WorkflowError:` to catch any engine error.
class WorkflowError(Exception):
    """Base class for all workflow-engine errors."""

class WorkflowDefinitionError(WorkflowError):
    """Raised at load time when the workflow JSON is malformed."""

class RoutingError(WorkflowError):
    """Raised when no transition matches the outcome verdict."""

class GateExhaustedError(WorkflowError):
    """Raised when a gate's reentry_budget is exhausted."""

class DispatchError(WorkflowError):
    """Raised when a dispatch handler fails."""

class SubjectNotFoundError(WorkflowError):
    """Raised when a subject_id is not found."""

class PassportValidationError(WorkflowError):
    """Raised when passport JSON fails schema validation."""

class LeaseLostError(WorkflowError):
    """Raised on claim_epoch mismatch — non-retryable; must re-claim and recompute."""

class ConcurrentWriteError(WorkflowError):
    """Raised on version mismatch but claim_epoch matched — retryable."""

class HandlerNotRegistered(WorkflowError):
    """Raised when a dispatch handler name is not in the registry."""

class RedactorNotRegisteredError(WorkflowError):
    """Raised when a redactor name is not in the registry."""

class StateKindMismatchError(WorkflowError):
    """Raised when an operation does not match the current state's kind
    (e.g. record_decision() on a task state, advance() with a non-gate
    verdict on a gate state). Q10 decision."""

class ReservedVarsPathError(WorkflowError):
    """Raised when a handler attempts to write to an engine-managed
    path in ctx.vars (see ENGINE_RESERVED_VARS_PATHS). Q20 decision."""

class ProjectDepthExceeded(WorkflowError):
    """Raised when project() recursion exceeds max_project_depth
    (default 50; configurable). Q19 decision."""

class VarsCollisionError(WorkflowError):
    """Raised at parallel join when two branches wrote different values
    to the same ctx.vars key (strict mode). Q9 decision. Use branch-
    namespaced outputs.produced to avoid the collision."""

class IncomparableStates(WorkflowError):
    """Raised when two states cannot be compared for forward progress."""
    def __init__(self, a: str, b: str):
        super().__init__(
            f"State {a} and state {b} are incomparable: "
            f"no directed path between them in the forward-progress DAG.")

@dataclass(frozen=True)
class Transition:
    verdict: Verdict
    target: str
    event_name: str
    loop: bool = False

### FanOut discriminated union (Q12)

```python
from typing import Literal, Union
from dataclasses import dataclass

@dataclass(frozen=True)
class FanOutStatic:
    """Fan-out to a fixed list of branch identifiers."""
    kind: Literal["static"] = "static"
    branches: tuple[str, ...] = ()

@dataclass(frozen=True)
class FanOutDynamic:
    """Fan-out to a dynamically resolved list. Currently only `$roster`
    is supported — resolves to `ctx.vars['domain_classification']['roster']`
    at state entry (pinned by A0c decision, not re-resolved)."""
    kind: Literal["dynamic"] = "dynamic"
    source: Literal["$roster"] = "$roster"

FanOut = Union[FanOutStatic, FanOutDynamic]
```

### JoinConfig discriminated union (Q26)

```python
@dataclass(frozen=True)
class JoinAll:
    """Join satisfied when every branch in fan_out has returned."""
    type: Literal["all"] = "all"

@dataclass(frozen=True)
class JoinQuorum:
    """Join satisfied when at least `n` branches have returned. `on_satisfied`
    controls what happens to still-pending branches:
      - "cancel_pending" (default) — pending branches are rejected on return
      - "supersede"                — composite is recomputed with each late outcome
      - "discard_late"             — pending branches accepted silently but not aggregated
    """
    n: int
    on_satisfied: Literal["cancel_pending", "supersede", "discard_late"] = "cancel_pending"
    type: Literal["quorum"] = "quorum"

JoinConfig = Union[JoinAll, JoinQuorum]
```

### State (with aggregation_rule + typed fan_out/join)

```python
@dataclass(frozen=True)
class State:
    name: str
    title: str
    phase: str
    step: int
    kind: StateKind
    role: str | None = None
    dispatch_handler: str | None = None
    outcome_schema: str | None = None
    branch_schema: str | None = None
    decision_schema: str | None = None
    routing_rule: str | None = None
    gate_config: str | None = None
    fan_out: FanOut | None = None                 # Q12 — typed union
    join: JoinConfig | None = None                # Q26 — typed union
    aggregation_rule: str | None = None           # Q6 — required for kind == parallel
    inputs: dict | None = None
    outputs: dict | None = None
    transitions: dict[Verdict, "Transition"] = field(default_factory=dict)

    def __str__(self) -> str:
        return f"{self.name} ({self.title})"

    def __eq__(self, other: object) -> bool:
        return isinstance(other, State) and self.name == other.name

    def __hash__(self) -> int:
        return hash(self.name)
```

> **Note:** `State.id` removed — identified by `name`. `_registry` removed —
> use `StateRegistry.is_ancestor(a, b)` for comparison. `agent` replaced by
> `role` (orchestrator/architect/reviewer) — mapped to concrete agent via
> `role_mapping` in config. `Transition.outcome` → `verdict`. `skip` removed.
> `branch_schema` added for parallel states (per-branch validation).
> `dispatch_handler` is `None` for gate and terminal states.

### Context model

```python
@dataclass(frozen=True)
class StateMeta:
    from_state: str | None
    entry_count: int
    attempt: int
    entered_at: datetime

@dataclass(frozen=True)
class Context:
    input: dict[str, Any]
    vars: dict[str, Any]
    meta: StateMeta

    def is_loop_back(self) -> bool:
        """True when re-entering a state after a loop-back (entry_count > 1)."""
        return self.meta.entry_count > 1

    def is_retry(self) -> bool:
        """True when retrying the same state after a transient failure (attempt > 0)."""
        return self.meta.attempt > 0

    def reached_from(self, state_name: str) -> bool:
        return self.meta.from_state == state_name
```

> **Note:** `Context` is frozen. `vars` is deep-copied per parallel branch;
> merged at join time under engine control. `is_retry` split into
> `is_loop_back` (entry_count>1) and `is_retry` (attempt>0).

### OutcomeStore + StepRecord + StepOutcome + RawPayload

```python
from typing import Literal, NewType

# Opaque references returned by OutcomeStore.write_* — engine treats them
# as strings and passes back to load_* unchanged (Q31 decision).
OutcomeRef = NewType("OutcomeRef", str)
RawRef     = NewType("RawRef", str)

StepStatus = Literal["complete", "validation_failed", "dispatched", "pending"]

@dataclass(frozen=True)
class StepRecord:
    """Canonical event/step record. Used as both:
      - write input to EventStore.append (prev_hash/row_hash unset — engine assigns)
      - read output from EventStore.load_events (prev_hash/row_hash populated by store).
    Q3 decision: no separate EventRecord type."""
    uuid: uuid.UUID
    subject_id: str
    step: str                         # "A0" or "A1#security" (parallel branch)
    role: str | None                  # orchestrator | architect | reviewer
    model: str | None                 # Concrete model identifier from dispatch metadata
    from_state: str | None
    entry_count: int
    attempt: int
    verdict: Verdict
    event_name: str
    status: StepStatus
    started_at: str                   # ISO-8601
    completed_at: str | None          # ISO-8601, None while pending
    outcome_ref: OutcomeRef | None    # → StepOutcome (None when validation failed)
    raw_ref: RawRef | None            # → RawPayload (MANDATORY when outcome_ref is None)
    idempotency_key: str
    timestamp: str                    # ISO-8601 — engine-assigned at append time
    # Hash-chain columns — populated on read from EventStore, ignored on write.
    prev_hash: str | None = None
    row_hash: str | None = None

@dataclass(frozen=True)
class StatusLogEntry:
    """Typed row returned by StatusLog.load_status (Q33 decision)."""
    id: int
    subject_id: str
    flag: Literal["cancelled", "deferred", "archived"]
    actor: str | None
    reason: str | None
    ts: str                           # ISO-8601
    prev_hash: str | None
    row_hash: str

@dataclass(frozen=True)
class StepOutcome:
    """Validated, schema-conformant record. Exists only AFTER validation passes.
    `verdict` has NO default — every StepOutcome MUST be constructed with an
    explicit verdict (Q27 decision — prevents accidental 'pass' from missing arg)."""
    verdict: Verdict
    kind: Literal["step_outcome"] = "step_outcome"  # Discriminator (D-015a)
    decision: dict | None = None
    confidence: int | None = None
    validated_fields: dict = field(default_factory=dict)

@dataclass(frozen=True)
class RawPayload:
    """Unprocessed bytes from the dispatch handler. Forensic evidence."""
    kind: Literal["raw_payload"] = "raw_payload"  # Discriminator (D-015a)
    source_type: str = ""             # "agent" | "human_form" | "webhook"
    content_type: str = ""            # "application/json" | "text/markdown" | ...
    encoding: str = "utf-8"
    body: str | bytes = b""
    metadata: dict = field(default_factory=dict)  # request_id, timing, headers
    checksum: str | None = None       # sha256 of body

class OutcomeStore(Protocol):
    """Protocol for storing step outcomes. Implementation decides format
    (PG JSONB, SQLite JSON, compressed bytes) and returns an opaque ref.

    Q5 decision: internal helpers (`StepPathResolver`, `OutcomeRepository`,
    `StepRecordFactory`) are implementation-internal to
    infrastructure/outcome_store/ and are not exposed as domain protocols.

    Q31 decision: `outcome_ref` and `raw_ref` are `NewType[str]`. The engine
    treats them as opaque and passes back to `load_*` unchanged."""
    def write_step_outcome(self, subject_id: str, step: str,
                           outcome: StepOutcome) -> OutcomeRef: ...
    def write_raw_payload(self, subject_id: str, step: str,
                          payload: RawPayload) -> RawRef: ...
    def load_outcome(self, outcome_ref: OutcomeRef) -> StepOutcome | None: ...
    def load_raw(self, raw_ref: RawRef) -> RawPayload | None: ...
```

> **Note:** `StepWriter` renamed to `OutcomeStore`. Protocol allows string or
> byte array. Implementation decides format. Split into `StepPathResolver` +
> `OutcomeRepository` + `StepRecordFactory`. `StepOutcome` is the validated,
> schema-conformant data with `kind: "step_outcome"` discriminator. `RawPayload`
> is the unprocessed forensic evidence with `kind: "raw_payload"` discriminator.
> `outcome_ref` → StepOutcome. `raw_ref` → RawPayload (nullable). `raw_ref`
> is MANDATORY when validation fails (no StepOutcome exists). `idempotency_key`
> = `"sha256:" || hex(sha256(canonical_json({"v":1, "subject_id":..., "step":..., "entry_count":..., "attempt":...})))`
> per Q14 (RFC 8785 canonical JSON, versioned tag). Path sanitisation:
> `subject_id` validated against strict pattern; subdirectory structure for
> outcomes. `StepRecord` carries `model`, `status`, `started_at`, `completed_at`
> for parity with the passport `step_log` entries.

---

## 3.9 API Result Types

Frozen dataclasses returned by `WorkflowService` methods. Defined here in the
data model because they are part of the contract callers depend on.

```python
# psc_engine/domain/api_results.py

from dataclasses import dataclass, field
from enum import StrEnum

class QueryWhat(StrEnum):
    """Selector for WorkflowService.query(). Per-subject only.
    Cross-subject filters live on SubjectListFilter (used by
    WorkflowService.list_subjects) per Q4 decision."""
    STEP_LOG = "step_log"
    STATUS_LOG = "status_log"
    CLAIM_LOG = "claim_log"
    DECISIONS = "decisions"
    VARS = "vars"
    GATE_RESULTS = "gate_results"
    CORRECTIONS = "corrections"
    LOOP_HISTORY = "loop_history"
    PARALLEL_PROGRESS = "parallel_progress"
    FULL = "full"

@dataclass(frozen=True)
class StatusFlags:
    cancelled: bool = False
    deferred: bool = False
    archived: bool = False

@dataclass(frozen=True)
class CurrentStateResult:
    """Return type of WorkflowService.current_state()."""
    state: "State"
    is_terminal: bool
    is_decision_pending: bool
    pending_decision_schema: str | None
    possible_verdicts: list[str]
    status_flags: StatusFlags
    error: str | None = None  # populated when subject not found

@dataclass(frozen=True)
class PossibleOutcome:
    """One row returned by WorkflowService.possible_outcomes().

    For `task` and `parallel` states, one row per `state.transitions[verdict]`.
    For `gate` states, one row per engine-reserved verdict (`pass`, `fail`,
    `exhausted`) defined on the state.
    For `decision_required` states, `possible_outcomes()` returns a single
    synthetic row with `verdict="decided"`, `target=None`, `outcome_schema`
    set to the `decision_schema`, and `inputs_required` listing the routing
    rule's JSONPath dependencies. The caller MUST use `record_decision()`,
    NOT `advance()`, for decision_required states.
    For `terminal` states, the result list is empty."""
    verdict: str
    target: str | None             # None for decision_required and terminal
    event_name: str | None         # None for decision_required (routing-rule driven)
    outcome_schema: str | None
    decision_schema: str | None    # set ONLY for decision_required
    routing_rule: str | None       # set ONLY for decision_required
    inputs_required: list[str]
    inputs_optional: list[str]
    loop: bool

@dataclass(frozen=True)
class AdvanceResult:
    """Return type of WorkflowService.advance()."""
    advanced: bool
    new_state: str | None
    next_role: str | None         # The role mapped for the new state (decision #73)
    terminal: bool
    mirror_updated: bool
    join_satisfied: bool | None   # None for non-parallel states
    pending: list[str] | None     # parallel branches still pending
    composite_ref: str | None     # outcome_ref of the composite (parallel only)
    retry_available: bool | None  # for gate-fail transitions
    reentry_used: int | None      # current reentry count for the gate
    failed_tier: str | None       # set only for gate fail/exhausted transitions

@dataclass(frozen=True)
class DecisionResult:
    """Return type of WorkflowService.record_decision()."""
    new_state: str
    terminal: bool
    mirror_updated: bool

@dataclass(frozen=True)
class RoutePreview:
    """Return type of WorkflowService.route_for_outcome() — read-only."""
    target: str
    event_name: str
    loop: bool
    role: str | None

@dataclass(frozen=True)
class ValidationResult:
    valid: bool
    errors: list[str] = field(default_factory=list)

@dataclass(frozen=True)
class CancelResult:
    cancelled: bool
    terminal: bool                 # always False — cancel does not produce a terminal state

@dataclass(frozen=True)
class MigrationResult:
    migrated: bool
    incompatibilities: list[str] = field(default_factory=list)
    new_version: str | None = None

@dataclass(frozen=True)
class RosterProposal:
    """Return type of WorkflowService.propose_roster()."""
    suggested: list[str]           # Specialist agent names, deduplicated
    matched_signals: dict[str, list[str]]  # specialist → signals that matched
    rationale: str

@dataclass(frozen=True)
class RosterValidation:
    valid: bool
    errors: list[str] = field(default_factory=list)
    unknown_agents: list[str] = field(default_factory=list)

@dataclass(frozen=True)
class QueryResult:
    """Return type of WorkflowService.query() — dict/list shape depending
    on QueryWhat. Callers that want static typing should use the
    per-selector methods (Q15 decision):
      - get_step_log(subject_id) -> StepLogResult
      - get_status_log(subject_id) -> StatusLogResult
      - get_vars(subject_id) -> VarsResult
      - get_full(subject_id) -> FullResult
    or the discriminated union types below."""
    what: QueryWhat
    data: dict | list

# Discriminated union alternatives to QueryResult.data (Q15 decision).
# Each corresponds to one per-subject QueryWhat selector.

@dataclass(frozen=True)
class StepLogResult:
    subject_id: str
    entries: list["StepRecord"]

@dataclass(frozen=True)
class StatusLogResult:
    subject_id: str
    entries: list["StatusLogEntry"]

@dataclass(frozen=True)
class ClaimLogResult:
    subject_id: str
    entries: list["ClaimLogEntry"]

@dataclass(frozen=True)
class DecisionsResult:
    subject_id: str
    entries: list[dict]

@dataclass(frozen=True)
class VarsResult:
    subject_id: str
    vars: dict

@dataclass(frozen=True)
class GateResultsResult:
    subject_id: str
    entries: list[dict]

@dataclass(frozen=True)
class CorrectionsResult:
    subject_id: str
    entries: list[dict]

@dataclass(frozen=True)
class LoopHistoryResult:
    subject_id: str
    entries: list[dict]

@dataclass(frozen=True)
class ParallelProgressResult:
    subject_id: str
    progress: dict

@dataclass(frozen=True)
class FullResult:
    subject_id: str
    passport: dict

# Cross-subject list filter (Q4 — list_subjects API)
class SubjectListFilter(StrEnum):
    ALL = "all"
    BLOCKED = "blocked"         # is_decision_pending OR waiting on parallel branches
    ESCALATED = "escalated"     # terminal state == ESCALATE
    PENDING = "pending"         # is_decision_pending == True
    INFLIGHT = "inflight"       # non-terminal, non-cancelled
    CANCELLED = "cancelled"
    DEFERRED = "deferred"
    ARCHIVED = "archived"

@dataclass(frozen=True)
class SubjectSummary:
    """One row returned by WorkflowService.list_subjects()."""
    subject_id: str
    subject_type: str
    title: str | None
    workflow_id: str
    workflow_version: str
    current_state: str
    phase: str
    is_terminal: bool
    is_decision_pending: bool
    status_flags: StatusFlags
    updated_at: str

@dataclass(frozen=True)
class WorkflowDefinition:
    """Return type of WorkflowService.load_workflow()."""
    workflow_id: str
    version: str
    profile_version: str
    subject_type: str
    start_at: str
    states: dict[str, "State"]
    gate_configs: dict[str, dict]
    routing_rules: dict[str, dict]
    registry: "StateRegistry"

@dataclass(frozen=True)
class WorkflowDefinitionRecord:
    """Return type of WorkflowDefinitionStore.load_definition()."""
    workflow_id: str
    version: str
    profile_version: str                          # Q32 — denormalised
    definition_json: str
    definition_hash: str                          # Q22 — SHA-256 of definition_json
    created_at: str
    updated_at: str
```

---

## 3.10 Registries, Resolvers, and Config Port

Engine components for runtime resolution of names → implementations. All
registries follow the same shape: `register(name, impl)` + `resolve(name)`.

```python
# psc_engine/domain/registries.py

class DispatcherRegistry:
    def register(self, name: str, handler: DispatchHandler) -> None: ...
    def resolve(self, name: str) -> DispatchHandler:
        """Raises HandlerNotRegistered if name is not registered."""
        ...

class HookRegistry:
    def register(self, hook: LifecycleHook, critical: bool = False) -> None: ...
    def hooks_for(self, event: str) -> list[tuple[LifecycleHook, bool]]: ...

class AggregationRegistry:
    def register(self, name: str, rule: "AggregationRule") -> None: ...
    def resolve(self, name: str) -> "AggregationRule": ...

class AggregationRule(Protocol):
    """Aggregates parallel branch outcomes into a composite outcome."""
    def aggregate(self, state: "State",
                  returned: dict[str, dict]) -> dict: ...

class StateRegistry:
    """Free function holder for state-comparison and lookup."""
    def get_state(self, name: str) -> "State":
        """Raises KeyError if name not in registry."""
        ...
    def get_start_state(self) -> "State": ...
    def get_terminal_states(self) -> list["State"]: ...
    def is_ancestor(self, a: "State", b: "State") -> bool:
        """True iff there is a directed path a → ... → b in the
        forward-progress DAG (back-edges excluded). Returns False
        when no path exists in either direction.

        Use `compare_states(a, b)` when callers need to distinguish
        "a precedes b", "b precedes a", and "incomparable" — that
        helper raises `IncomparableStates` when neither path exists."""
        ...
    def compare_states(self, a: "State", b: "State") -> int:
        """Returns -1 if a precedes b, +1 if b precedes a, 0 if a == b.
        Raises `IncomparableStates` when neither directed path exists
        in the forward-progress DAG."""
        ...

class SignalMatcher(Protocol):
    """Case-fold match of domain signals to roster entries. Pluggable."""
    def matches(self, signal: str, candidate_signals: list[str]) -> bool: ...

class RosterResolver:
    def __init__(self, agents_folder: str, signal_matcher: SignalMatcher,
                 config: "ConfigPort"): ...
    def propose(self, domain_signals: list[str]) -> RosterProposal: ...
    def validate_roster(self, selection: list[str]) -> RosterValidation: ...

class ConfigPort(Protocol):
    """Domain-layer protocol for engine configuration. The concrete Config
    in infrastructure implements this; the domain depends only on the port."""
    @property
    def agents_folder(self) -> str: ...
    @property
    def workflows_folder(self) -> str: ...
    @property
    def passports_folder(self) -> str: ...
    @property
    def outcomes_folder(self) -> str: ...
    @property
    def db_path(self) -> str: ...
    @property
    def dispatch_retry_max_attempts(self) -> int: ...
    @property
    def dispatch_retry_backoff(self) -> dict: ...
    @property
    def reentry_budget_default(self) -> int: ...
    @property
    def lease_ttl_seconds(self) -> int: ...
    @property
    def heartbeat_interval_seconds(self) -> int: ...
    @property
    def max_project_depth(self) -> int: ...              # Q19
    @property
    def subject_id_engine_pattern(self) -> str: ...      # Q18
    @property
    def subject_id_profile_pattern(self) -> str | None: ...
    @property
    def roster_default(self) -> list[str]: ...
    @property
    def roster_minimum(self) -> list[str]: ...
    @property
    def roster_max(self) -> int: ...
    @property
    def roster_signals(self) -> list[dict]: ...
    @property
    def role_mapping(self) -> dict[str, str]: ...

@dataclass(frozen=True)
class Config:
    """Infrastructure-layer concrete config. Implements ConfigPort."""
    agents_folder: str
    workflows_folder: str
    passports_folder: str
    outcomes_folder: str
    db_path: str
    dispatch_retry_max_attempts: int
    dispatch_retry_backoff: dict
    reentry_budget_default: int
    lease_ttl_seconds: int
    heartbeat_interval_seconds: int
    max_project_depth: int
    subject_id_engine_pattern: str
    subject_id_profile_pattern: str | None
    roster_default: list[str]
    roster_minimum: list[str]
    roster_max: int
    roster_signals: list[dict]
    role_mapping: dict[str, str]

class HookErrorSink(Protocol):
    """Sink for non-critical hook errors. Critical hooks fail-closed; this
    sink is invoked only for non-critical hooks that raised."""
    def record(self, event: str, hook_name: str, exc: BaseException) -> None: ...

class Redactor(Protocol):
    def redact(self, value: Any) -> Any: ...
```

> **Note:** `Redactor.redact(value) -> Any` is intentionally `Any` so that
> non-string protected values (numbers, booleans, opaque blobs) can be passed
> through a redactor without coercion. `EmailRedactor` narrows the input type
> for clarity but Liskov substitutability is preserved at runtime — the
> registry calls `redact(value)` with whatever the schema provides; type
> checkers may warn on the narrowing but it does not break dispatch.

---

## 3.11 Adhoc Workflow JSON — `psc-adhoc`

Separate workflow definition for non-PSC-grade tasks. Skips parallel review,
challenge, user-disposition; T1 only; reentry budgets halved. The PM dispatches
this workflow when the Supreme Leader determines a task is "single-concern,
single-file-class, no architecture impact" (subject to refinement — see
[00-README.md](00-README.md) open question 2).

```jsonc
{
  "workflow_id": "psc-adhoc",
  "version": "1.0.0",
  "profile_version": "1.0.0",
  "subject_type": "ticket",
  "start_at": "A0L",
  "phases": [
    {"id": "A", "ord": 0}, {"id": "B", "ord": 1}, {"id": "CR", "ord": 2}
  ],
  "states": {
    "A0L": {
      "name": "A0L", "title": "Lightweight Task Definition (propose)",
      "phase": "A", "step": 0, "kind": "task",
      "role": "orchestrator",
      "dispatch_handler": "engine.subagent_dispatch",
      "outcome_schema": "psc.outcome.roster_proposal",
      "outputs": {
        "produced": {"/proposed_roster": "$.roster"},
        "carried_forward": true
      },
      "transitions": {
        "proposed": {"target": "A0Lc", "event_name": "subject.phase-a.adhoc-roster-proposed"}
      }
    },
    "A0Lc": {
      "name": "A0Lc", "title": "Roster Confirmation (adhoc)",
      "phase": "A", "step": 1, "kind": "decision_required",
      "role": "reviewer",
      "decision_schema": "decision.roster_confirmation",
      "routing_rule": "route.roster_confirmation_adhoc",
      "inputs": { "required": ["$.proposed_roster"] },
      "outputs": { "produced": {"/roster": "$.roster"}, "carried_forward": true },
      "transitions": {}
    },
    "A1L": {
      "name": "A1L", "title": "Single-Specialist Review",
      "phase": "A", "step": 2, "kind": "task",
      "role": "reviewer",
      "dispatch_handler": "engine.subagent_dispatch",
      "outcome_schema": "psc.outcome.specialist_review",
      "transitions": {
        "pass":  {"target": "B1L", "event_name": "subject.phase-a.adhoc-reviewed"},
        "fail":  {"target": "A0L", "loop": true, "event_name": "subject.phase-a.adhoc-rejected"}
      }
    },
    "B1L": {
      "name": "B1L", "title": "Lightweight Plan & Apply",
      "phase": "B", "step": 0, "kind": "task",
      "role": "architect",
      "dispatch_handler": "engine.subagent_dispatch",
      "outcome_schema": "psc.outcome.unit_apply",
      "transitions": {
        "applied": {"target": "B3L", "event_name": "subject.phase-b.adhoc-applied"}
      }
    },
    "B3L": {
      "name": "B3L", "title": "VALIDATE (T1 only)",
      "phase": "B", "step": 1, "kind": "task",
      "role": "architect",
      "dispatch_handler": "engine.subagent_dispatch",
      "outcome_schema": "psc.outcome.validate",
      "transitions": {
        "validated": {"target": "B3aL", "event_name": "subject.phase-b.adhoc-validated"}
      }
    },
    "B3aL": {
      "name": "B3aL", "title": "T1 GATE",
      "phase": "B", "step": 2, "kind": "gate",
      "role": "orchestrator",
      "gate_config": "gate.B3aL",
      "transitions": {
        "pass":      {"target": "CR1L", "event_name": "subject.phase-b.adhoc-gate-passed"},
        "fail":      {"target": "B1L",  "loop": true, "event_name": "subject.phase-b.adhoc-gate-failed"},
        "exhausted": {"target": "ESCALATE", "event_name": "subject.phase-b.adhoc-gate-exhausted"}
      }
    },
    "CR1L": {
      "name": "CR1L", "title": "Lightweight Code Review",
      "phase": "CR", "step": 0, "kind": "task",
      "role": "reviewer",
      "dispatch_handler": "engine.subagent_dispatch",
      "outcome_schema": "psc.outcome.review",
      "transitions": {
        "reviewed": {"target": "CR2L", "event_name": "subject.phase-cr.adhoc-reviewed"}
      }
    },
    "CR2L": {
      "name": "CR2L", "title": "CR GATE",
      "phase": "CR", "step": 1, "kind": "gate",
      "role": "orchestrator",
      "gate_config": "gate.CR2L",
      "transitions": {
        "pass":      {"target": "COMMIT",   "event_name": "subject.phase-cr.adhoc-accept"},
        "fail":      {"target": "B1L",      "loop": true, "event_name": "subject.phase-cr.adhoc-request-changes"},
        "exhausted": {"target": "ESCALATE", "event_name": "subject.phase-cr.adhoc-exhausted"}
      }
    },
    "COMMIT":   {"name": "COMMIT",   "title": "Commit",   "phase": "CR", "step": 2, "kind": "terminal"},
    "ESCALATE": {"name": "ESCALATE", "title": "Escalate", "phase": "CR", "step": 3, "kind": "terminal"}
  },
  "gate_configs": {
    "gate.B3aL": {"tiers": ["T1"], "reentry_budget": {"T1": 2}},
    "gate.CR2L": {"tiers": ["T1"], "reentry_budget": {"T1": 2}, "round_budget": 3}
  },
  "routing_rules": {
    "route.roster_confirmation_adhoc": {
      "CASE": [
        {"WHEN": "$.roster[*]",
         "THEN": {"target": "A1L", "event_name": "subject.phase-a.adhoc-roster-confirmed"}}
      ],
      "ELSE": {"target": "A0L", "loop": true,
               "event_name": "subject.phase-a.adhoc-roster-rejected"}
    }
  }
}
```

> **Differences from `psc-main`:**
> - `A1L` is `task` (single specialist), not `parallel`
> - A2/A2b/A2c (challenge + synthesis + user-disposition) dropped entirely
> - A2a (ADR creation) dropped — adhoc by definition has no ADR
> - C0/C1/C2/C3/C4 dropped — no challenge, no parallel approval, no PM completion review
> - `B1` and `B2`/`B2a` collapsed into `B1L` (plan + apply in one task)
> - `gate.B3aL` and `gate.CR2L` use T1 only; reentry budget halved (2)
> - `round_budget: 3` on `CR2L` (down from 5)
> - `A0L` replaces `A0` — same semantics, different label to make the
>   adhoc origin visible in step_log entries
> - All event names use `adhoc-*` suffix in the phase-specific segment so
>   downstream consumers can distinguish adhoc from main events