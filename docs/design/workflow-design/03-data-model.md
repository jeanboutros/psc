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
in the outcome is opaque JSON stored by StepWriter.

### Verdict enum

```python
class Verdict(StrEnum):
    PASS = "pass"
    FAIL = "fail"
    NEEDS_DECISION = "needs_decision"
    NEEDS_INFO = "needs_info"
    REQUEST_CHANGES = "request_changes"
    APPROVED = "approved"
    CLASSIFIED = "classified"
    REVIEWS_COMPLETE = "reviews_complete"
    CHALLENGE_COMPLETE = "challenge_complete"
    SYNTHESIZED = "synthesized"
    ADR_WRITTEN = "adr_written"
    PLANNED = "planned"
    UNIT_APPLIED = "unit_applied"
    UNITS_COMPLETE = "units_complete"
    VALIDATED = "validated"
    DONE = "done"
    ALL_APPROVED = "all_approved"
    ANY_REJECTED = "any_rejected"
    REVIEWED = "reviewed"
    ACCEPT = "accept"
    ACCEPTED = "accepted"
    EXHAUSTED = "exhausted"
```

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
    outcome: Verdict
    target: str
    event_name: str           # MANDATORY — e.g. "subject.phase-a.classified"
    loop: bool = False
    skip: tuple[str, ...] = ()
```

### DispatchHandler protocol

```python
class DispatchHandler(Protocol):
    def dispatch(self, state: dict, ctx: "Context",
                 outcome_schema: dict) -> dict:
        """Execute the state's actor and return an AgentOutcome dict.
        Raises DispatchError on failure."""
        ...
```

Built-in handlers: `engine.subagent_dispatch`, `engine.human_form_dispatch`,
`engine.system_webhook_dispatch`. Projects register custom handlers at startup.

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
    SUBJECT_CLAIMED = "subject.claimed"
    SUBJECT_RELEASED = "subject.released"
    SUBJECT_STALE_REAPED = "subject.stale.reaped"

class LifecycleHook(Protocol):
    def on_event(self, event: str, context: dict) -> None: ...
```

### Storage protocols

```python
class SubjectStore(Protocol):
    def load(self, subject_id: str) -> dict | None: ...
    def save(self, subject_id: str, passport_json: str,
             active_steps: list[str], version: int) -> int: ...
    def load_inflight(self) -> list[tuple[str, str, list[str]]]: ...
    def claim(self, subject_id: str, session_id: str,
              lease_ttl_seconds: int = 300) -> bool: ...
    def release(self, subject_id: str, session_id: str) -> bool: ...
    def reap_stale_claims(self, lease_ttl_seconds: int = 300) -> int: ...

class EventStore(Protocol):
    def append(self, subject_id: str, step: str, agent: str,
               from_state: str | None, verdict: str,
               outcome_ref: str, uuid: UUID) -> None: ...
    def load_events(self, subject_id: str) -> list[dict]: ...

class WorkflowDefinitionStore(Protocol):
    def load_definition(self, workflow_id: str, version: str) -> dict: ...
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

- No `classification` keyword → `public` (default).
- `protected` with no `redactor` → `DefaultRedactor` → `[REDACTED]`.
- `private` → omitted entirely from events/logs/API/mirror.

**`project()` applied at every external boundary:**

```python
def project(data: Any, schema: dict | None, redactors: RedactorRegistry) -> Any:
    """Omit private, redact protected, pass public. Recurses into
    nested objects and arrays."""
    if data is None or schema is None:
        return data
    if isinstance(data, list):
        return [project(item, schema.get("items"), redactors) for item in data]
    if isinstance(data, dict):
        properties = schema.get("properties", {})
        result = {}
        for key, value in data.items():
            field_schema = properties.get(key)
            if field_schema is None:
                result[key] = value
                continue
            classification = field_schema.get("classification", "public")
            if classification == "private":
                continue
            elif classification == "protected":
                redactor_name = field_schema.get("redactor", "DefaultRedactor")
                result[key] = redactors.resolve(redactor_name).redact(value)
            else:
                result[key] = project(value, field_schema, redactors)
        return result
    return data
```

| Boundary | Projected? | Why |
|----------|-----------|-----|
| Passport JSON (stored) | No | Workflow needs real values |
| `ctx.vars` (handler context) | No | Handler needs real values |
| Event dispatch (hooks) | Yes | Events go to external bus |
| Audit log (events table) | Yes | Audit trail reviewed by humans |
| Markdown mirror | Yes | Humans review diffs |
| API responses (MCP/CLI) | Yes | External consumers |

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
+ `loop` flag + `retry` blocks + `dispatch_handler` + `outcome_schema`.

### `psc-main` workflow (with event_name on every transition)

```jsonc
{
  "workflow_id": "psc-main",
  "version": "2.0.0",
  "subject_type": "ticket",
  "start_at": "A0",
  "phases": [
    {"id":"A","ord":0}, {"id":"B","ord":1}, {"id":"C","ord":2}, {"id":"CR","ord":3}
  ],
  "states": {
    "A0": {
      "name":"A0","title":"Task Definition & Domain Classification",
      "phase":"A","step":0,"kind":"task","agent":"supreme-leader",
      "dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.task_definition",
      "transitions": {
        "classified":          {"target":"A1","event_name":"subject.phase-a.classified"},
        "needs_clarification": {"target":"A0","loop":true,"event_name":"subject.phase-a.clarification-needed"}
      }
    },
    "A1": {
      "name":"A1","title":"Parallel Specialist Review",
      "phase":"A","step":1,"kind":"parallel","agent":"supreme-leader",
      "dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.specialist_composite",
      "fan_out":"$roster","join":"all",
      "transitions": { "reviews_complete":{"target":"A2","event_name":"subject.phase-a.reviews-complete"} }
    },
    "A2": {
      "name":"A2","title":"Dual-Model Challenge",
      "phase":"A","step":2,"kind":"parallel","agent":"supreme-leader",
      "dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.challenge_composite",
      "fan_out":["primary","challenger"],"join":"all",
      "transitions": { "challenge_complete":{"target":"A2b","event_name":"subject.phase-a.challenge-complete"} }
    },
    "A2b": {
      "name":"A2b","title":"Synthesis Artifact Creation",
      "phase":"A","step":3,"kind":"task","agent":"pm",
      "dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.synthesis",
      "transitions": { "synthesized":{"target":"A2c","event_name":"subject.phase-a.synthesized"} }
    },
    "A2c": {
      "name":"A2c","title":"Decision Register Presentation",
      "phase":"A","step":4,"kind":"decision_required","agent":"user",
      "dispatch_handler":"engine.human_form_dispatch",
      "decision_schema":"decision.user_disposition",
      "routing_rule":"route.user_disposition",
      "inputs": { "required": ["$.findings"], "optional": ["$.synthesis_ref"] },
      "outputs": { "produced": ["$.dispositions"], "carried_forward": true },
      "transitions": {}
    },
    "A2a": {
      "name":"A2a","title":"ADR Creation",
      "phase":"A","step":5,"kind":"task","agent":"code-architect",
      "dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.adr",
      "transitions": { "adr_written":{"target":"A3","event_name":"subject.phase-a.adr-written"} }
    },
    "A3": {
      "name":"A3","title":"A-GATE",
      "phase":"A","step":6,"kind":"gate","agent":"supreme-leader",
      "dispatch_handler":"engine.subagent_dispatch",
      "gate_config":"gate.A3",
      "transitions": {
        "pass":      {"target":"B1","event_name":"subject.phase-a.gate-passed"},
        "fail":      {"target":"A2a","loop":true,"event_name":"subject.phase-a.gate-failed"},
        "exhausted": {"target":"ESCALATE","event_name":"subject.phase-a.gate-exhausted"}
      },
      "retry": [{"error_equals":["gate_fail"],"max_attempts":3}]
    },
    "B1": { "name":"B1","title":"PLAN","phase":"B","step":0,"kind":"task","agent":"code-architect",
      "dispatch_handler":"engine.subagent_dispatch","outcome_schema":"psc.outcome.plan",
      "transitions": { "planned":{"target":"B2","event_name":"subject.phase-b.planned"} } },
    "B2": { "name":"B2","title":"APPLY (per unit)","phase":"B","step":1,"kind":"task","agent":"code-architect",
      "dispatch_handler":"engine.subagent_dispatch","outcome_schema":"psc.outcome.unit_apply",
      "transitions": {
        "unit_applied":{"target":"B2a","event_name":"subject.phase-b.unit-applied"},
        "units_complete":{"target":"B3","event_name":"subject.phase-b.units-complete"} } },
    "B2a": { "name":"B2a","title":"B-UNIT-GATE","phase":"B","step":2,"kind":"gate","agent":"supreme-leader",
      "dispatch_handler":"engine.subagent_dispatch","gate_config":"gate.B2a",
      "transitions": {
        "pass":{"target":"B2","event_name":"subject.phase-b.unit-gate-passed"},
        "fail":{"target":"B2","loop":true,"event_name":"subject.phase-b.unit-gate-failed"},
        "exhausted":{"target":"ESCALATE","event_name":"subject.phase-b.unit-gate-exhausted"} },
      "retry":[{"error_equals":["gate_fail"],"max_attempts":3}] },
    "B3": { "name":"B3","title":"VALIDATE","phase":"B","step":3,"kind":"task","agent":"code-architect",
      "dispatch_handler":"engine.subagent_dispatch","outcome_schema":"psc.outcome.validate",
      "transitions": { "validated":{"target":"B3a","event_name":"subject.phase-b.validated"} } },
    "B3a": { "name":"B3a","title":"B-FINAL-GATE","phase":"B","step":4,"kind":"gate","agent":"supreme-leader",
      "dispatch_handler":"engine.subagent_dispatch","gate_config":"gate.B3a",
      "transitions": {
        "pass":{"target":"C0","event_name":"subject.phase-b.final-gate-passed"},
        "fail":{"target":"B1","loop":true,"event_name":"subject.phase-b.final-gate-failed"},
        "exhausted":{"target":"ESCALATE","event_name":"subject.phase-b.final-gate-exhausted"} },
      "retry":[{"error_equals":["gate_fail"],"max_attempts":3}] },
    "C0": { "name":"C0","title":"T1 Re-run","phase":"C","step":0,"kind":"task","agent":"supreme-leader",
      "dispatch_handler":"engine.subagent_dispatch","outcome_schema":"psc.outcome.t1_rerun",
      "transitions": { "done":{"target":"C1","event_name":"subject.phase-c.t1-rerun-done"} } },
    "C1": { "name":"C1","title":"Dual-Model Challenge (Verification)","phase":"C","step":1,"kind":"parallel",
      "agent":"supreme-leader","dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.challenge_composite",
      "fan_out":["primary","challenger"],"join":"all",
      "transitions": { "challenge_complete":{"target":"C2","event_name":"subject.phase-c.challenge-complete"} } },
    "C2": { "name":"C2","title":"Parallel Specialist Approval","phase":"C","step":2,"kind":"parallel",
      "agent":"supreme-leader","dispatch_handler":"engine.subagent_dispatch",
      "outcome_schema":"psc.outcome.approval_composite",
      "fan_out":"$roster","join":"all",
      "transitions": {
        "all_approved":{"target":"C3","event_name":"subject.phase-c.all-approved"},
        "any_rejected":{"target":"CR1","event_name":"subject.phase-c.any-rejected"} } },
    "C3": { "name":"C3","title":"C-GATE","phase":"C","step":3,"kind":"gate","agent":"supreme-leader",
      "dispatch_handler":"engine.subagent_dispatch","gate_config":"gate.C3",
      "transitions": {
        "pass":{"target":"C4","event_name":"subject.phase-c.gate-passed"},
        "fail":{"target":"B1","loop":true,"event_name":"subject.phase-c.gate-failed"},
        "exhausted":{"target":"ESCALATE","event_name":"subject.phase-c.gate-exhausted"} },
      "retry":[{"error_equals":["gate_fail"],"max_attempts":3}] },
    "C4": { "name":"C4","title":"PM Completion Review","phase":"C","step":4,"kind":"decision_required",
      "agent":"pm","dispatch_handler":"engine.subagent_dispatch",
      "decision_schema":"decision.c4_completion","routing_rule":"route.c4",
      "transitions": {} },
    "CR1": { "name":"CR1","title":"Code Review Round","phase":"CR","step":0,"kind":"task","agent":"code-reviewer",
      "dispatch_handler":"engine.subagent_dispatch","outcome_schema":"psc.outcome.review",
      "transitions": { "reviewed":{"target":"CR2","event_name":"subject.phase-cr.reviewed"} } },
    "CR2": { "name":"CR2","title":"CR-GATE","phase":"CR","step":1,"kind":"gate","agent":"supreme-leader",
      "dispatch_handler":"engine.subagent_dispatch","gate_config":"gate.CR2",
      "transitions": {
        "accept":{"target":"CR3","event_name":"subject.phase-cr.accept"},
        "request_changes":{"target":"B2","loop":true,"event_name":"subject.phase-cr.request-changes"},
        "exhausted":{"target":"ESCALATE","event_name":"subject.phase-cr.exhausted"} },
      "retry":[{"error_equals":["gate_fail"],"max_attempts":5}] },
    "CR3": { "name":"CR3","title":"Review Acceptance","phase":"CR","step":2,"kind":"task","agent":"code-reviewer",
      "dispatch_handler":"engine.subagent_dispatch","outcome_schema":"psc.outcome.acceptance",
      "transitions": { "accepted":{"target":"COMMIT","event_name":"subject.phase-cr.accepted"} } },
    "COMMIT":   { "name":"COMMIT","title":"Commit","phase":"CR","step":3,"kind":"terminal","agent":"" },
    "ESCALATE": { "name":"ESCALATE","title":"Escalate","phase":"CR","step":4,"kind":"terminal","agent":"" }
  },
  "gate_configs": {
    "gate.A3":  {"tiers":["T3","T-ARCH"],"retry_budget":{"T3":3,"T-ARCH":3}},
    "gate.B2a": {"tiers":["T1","T-ARCH"],"retry_budget":{"T1":3,"T-ARCH":3}},
    "gate.B3a": {"tiers":["T1","T2","T-ARCH"],"retry_budget":{"T1":3,"T2":3,"T-ARCH":3}},
    "gate.C3":  {"tiers":["T1","T3","T-ARCH"],"retry_budget":{"T1":3,"T3":3,"T-ARCH":3}},
    "gate.CR2": {"tiers":["T3"],"retry_budget":{"T3":5},"round_budget":5}
  },
  "routing_rules": {
    "route.user_disposition": {
      "match": "$.findings[?@.disposition=='IMPLEMENT_NOW' || @.disposition=='ACCEPT']",
      "on_match": {"target":"A2a"},
      "on_no_match": {"target":"A3","skip":["A2a"]}
    },
    "route.c4": {
      "complete":{"target":"CR1"},
      "backlog_split":{"target":"CR1"},
      "rework":{"target":"B1","loop":true},
      "escalate":{"target":"ESCALATE"},
      "defer":{"target":"DEFERRED"},
      "add_tests":{"target":"B1","loop":true}
    }
  },
  "retry_policy": {"max_per_tier":3,"on_exhaust":"ESCALATE"},
  "max_review_rounds": 5
}
```

> **Note:** `event_name` uses `subject.*` prefix in the definition. At
> dispatch time, the engine replaces `subject` with the actual `subject_type`
> (e.g. `ticket.phase-a.classified`).

---

## 3.4 Passport JSON

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
  "is_adhoc": false,

  "domain_classification": {
    "primary":"security","secondary":["test"],
    "roster":["security","test","design"]
  },

  "state": {
    "current":"A2c","phase":"A","entered_at":"2026-06-29T11:00:00Z",
    "is_decision_pending":true,"pending_decision_schema":"decision.user_disposition"
  },

  "retries": {
    "A3": {"T3":0,"T-ARCH":0}, "B2a": {"T1":0,"T-ARCH":0},
    "B3a": {"T1":0,"T2":0,"T-ARCH":0}, "C3": {"T1":0,"T3":0,"T-ARCH":0},
    "CR2": {"T3":0}
  },
  "review_round": 0, "max_review_rounds": 5,
  "vars": {},
  "step_log": [
    {"step":"A0","agent":"supreme-leader","model":"glm-5.2",
     "started_at":"...","completed_at":"...","stamp":"STMP-0001",
     "status":"complete","from_state":null,"entry_count":1,"attempt":0,
     "uuid":"01923a8b-...","outcome_ref":"outcomes/TKT-0001/A0/01923a8b-....json"}
  ],
  "outcomes": {"A0": {}},
  "gate_results": [], "decisions": [], "loop_history": [], "corrections": [],
  "reviews": {"current_round":0,"rounds":[]},
  "skips": [],
  "parallel_progress": {
    "A1": {"expected":["security","test","design"],"returned":["security"],
           "pending":["test","design"],"join":"all"}
  },
  "version_pins": {"workflow":"2.0.0"}
}
```

> **Note:** No `agent_snapshot` field — agents are NOT snapshotted. The engine
> resolves agent files from `agents_folder` at dispatch time (always latest).

---

## 3.5 Physical Data Model — SQLite

```sql
CREATE TABLE subjects (
    id              TEXT PRIMARY KEY,
    workflow_id     TEXT NOT NULL,
    workflow_version TEXT NOT NULL,
    subject_type    TEXT NOT NULL DEFAULT 'ticket',
    active_steps    TEXT NOT NULL DEFAULT '[]',
    state_json      TEXT NOT NULL,
    claimed_by      TEXT,
    claimed_at      TEXT,
    version         INTEGER NOT NULL DEFAULT 1,
    updated_at      TEXT NOT NULL
);

CREATE TABLE workflow_definitions (
    id          TEXT NOT NULL,
    version     TEXT NOT NULL,
    definition  TEXT NOT NULL,
    PRIMARY KEY (id, version)
);

CREATE TABLE events (
    uuid        TEXT PRIMARY KEY,
    subject_id  TEXT NOT NULL REFERENCES subjects(id),
    step        TEXT NOT NULL,
    agent       TEXT,
    from_state  TEXT,
    verdict     TEXT,
    event_name  TEXT,
    outcome_ref TEXT,
    timestamp   TEXT NOT NULL
);
CREATE INDEX idx_events_subject ON events(subject_id, uuid);
```

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

### Outputs — path-to-path mapping (JSONPath read + JSON Pointer write)

```jsonc
"outputs": {
  "produced": {
    "$.dispositions": "$.findings[*].disposition",
    "$.decisions[*]": "$.decision"
  },
  "carried_forward": true
}
```

### Routing rules — RFC 9535 filter selectors

```jsonc
"route.user_disposition": {
  "match": "$.findings[?@.disposition=='IMPLEMENT_NOW' || @.disposition=='ACCEPT']",
  "on_match": {"target":"A2a"},
  "on_no_match": {"target":"A3","skip":["A2a"]}
}
```

Engine evaluates `find(match, ctx.vars)` — non-empty nodelist → `on_match` branch.

---

## 3.7 Config — `psc_engine.yaml`

```yaml
paths:
  agents_folder: agents
  workflows_folder: workflows
  passports_folder: docs/project-management/passports

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
```

Any `<name>.md` in `agents_folder` is a valid specialist — selectable at A0
even if not in the signals list.

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

class IncomparableStates(Exception):
    def __init__(self, a: "State", b: "State"):
        super().__init__(
            f"State {a.name} and state {b.name} are incomparable: "
            f"no directed path between them in the forward-progress DAG.")

@dataclass(frozen=True)
class Transition:
    outcome: str
    target: str
    event_name: str
    loop: bool = False
    skip: tuple[str, ...] = ()

@dataclass(frozen=True)
class State:
    id: int
    name: str
    title: str
    phase: str
    step: int
    kind: StateKind
    agent: str
    dispatch_handler: str = "engine.subagent_dispatch"
    outcome_schema: str = "outcome.base"
    transitions: dict[str, Transition] = field(default_factory=dict)

    def __str__(self) -> str:
        return f"{self.name} ({self.title})"

    def __lt__(self, other: "State") -> bool:
        if self.name == other.name: return False
        return self._registry._is_ancestor(self.name, other.name)

    def __eq__(self, other: object) -> bool:
        return isinstance(other, State) and self.name == other.name

    def __hash__(self) -> int:
        return hash(self.name)

    _registry: "StateRegistry | None" = field(default=None, repr=False, compare=False)
```

### Context model

```python
@dataclass(frozen=True)
class StateMeta:
    from_state: str | None
    entry_count: int
    attempt: int
    entered_at: datetime

@dataclass
class Context:
    input: dict[str, Any]
    vars: dict[str, Any]
    meta: StateMeta

    def is_retry(self) -> bool:
        return self.meta.entry_count > 1 or self.meta.attempt > 0

    def reached_from(self, state_name: str) -> bool:
        return self.meta.from_state == state_name
```

### StepWriter + StepRecord

```python
@dataclass(frozen=True)
class StepRecord:
    uuid: uuid.UUID
    subject_id: str
    step: str
    agent: str
    from_state: str | None
    entry_count: int
    attempt: int
    verdict: str
    event_name: str
    outcome_ref: str
    timestamp: str

class StepWriter:
    def __init__(self, outcomes_folder: Path): ...
    def write(self, subject_id, step, outcome, agent, from_state,
              entry_count, attempt, verdict, event_name) -> StepRecord:
        step_uuid = uuid.uuid7()  # Python 3.14+
        path = self._folder / subject_id / step.replace("#","_") / f"{step_uuid}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(outcome, indent=2), encoding="utf-8")
        return StepRecord(uuid=step_uuid, subject_id=subject_id, step=step, ...)
```