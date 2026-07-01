# 01 — Rationale, Philosophy, and Principles

> **Status:** DRAFT.
> **Branch:** `feature/workflow-engine`.

---

## Purpose

Replace the loosely-defined markdown passport and prose-driven agent handoff
with a **deterministic, semi-structured workflow engine**: JSON + JSON Schema
for the workflow definition and passport, a Python library that answers
state-machine questions, and an MCP/CLI surface the dispatch-only Supreme
Leader can call without violating its permission block.

The agent never decides "what's next" for deterministic transitions — it calls
a function and gets a response. The five genuine judgement points (A0 roster
confirmation, A2c user disposition, C4 PM completion, gate-fail root-cause
correction, and ambiguous-instruction clarification) are recorded as typed
decision objects and routed by their declared fields.

---

## Philosophy of Approach

This design follows four philosophical commitments, each grounded in the
authoritative research cited in [06-references.md](06-references.md):

### 1. Make the machine a machine, not a document

The current PSC pipeline encodes its state machine in 2,000+ lines of prose
across `pipeline/SKILL.md`, `supreme-leader.md`, and `pm.md`. An LLM must
read and follow all of it — and LLMs drift. The philosophical commitment
here is that routing correctness belongs in a **compile-time artefact**
(the JSON workflow definition), not a **prompt-time hope** (prose an agent
is told to obey). The state machine becomes testable; the agent becomes a
caller of deterministic functions.

### 2. Separate routing from judgement

A workflow has two kinds of decision points: those that are a pure
function of recorded state (gate pass/fail, retry budget, join
satisfaction), and those that require human or agent judgement (roster
classification, user disposition, PM completion, root-cause
classification). The design refuses to bake the second kind into the
transition graph. Judgement points are first-class `decision_required`
states that halt the machine; a typed decision object is supplied;
routing then proceeds deterministically off the decision's declared
fields. This keeps the state machine dumb and puts the intelligence in
declared objects the machine can reason about structurally.

### 3. The worker is a pure producer; placement is computed above it

No mature workflow engine lets the worker decide where its output lands.
In Camunda the engine decides via BPMN element scope + output mappings;
in Temporal the framework decides via activity ID + workflow run ID; in
Step Functions the engine decides via ASL state name + `ResultPath`. The
PSC engine follows the same principle: **the agent does not choose where
to write its outcome**. A class that is aware of the step identity and
the subject identity computes the storage path/id deterministically. This
is the "engine-managed output binding" pattern.

### 4. Preserve what works; replace what drifts

The existing PSC audit model — git-committable markdown passports, ADRs,
decision/advisory/clarification files, human review in diffs — is the
project's greatest strength. The design preserves it via a derived
Markdown mirror regenerated on every state transition. What gets replaced
is the prose-driven routing and the un-enforced handoff protocol, not
the reviewable artefacts.

---

## Design Agnosticism — A Principle

> **Principle:** The workflow definition, state machine semantics, passport
> shape, and routing rules defined in this document are **language-agnostic**.
> They are expressed as JSON data and a labelled transition system, not as
> Python code. The design should be valid for re-implementation in any
> language that can read JSON, evaluate boolean conditions, and persist
> state.

This Python prototype is the **reference implementation**, not the
specification. The specification is the JSON workflow definition, the
passport schema, the StepOutcome contract, and the transition table. A
Rust, Go, or TypeScript implementation that reads the same workflow JSON,
implements the same `advance`/`gate_fail`/`record_decision` semantics, and
writes the same passport JSON is a valid interoperable engine.

### What is Python-specific and must not leak into the spec

- `StrEnum`, `@dataclass(frozen=True)`, `field(default_factory=...)` are
  implementation conveniences in the reference library, not contract
  requirements.
- `StateRegistry.is_ancestor(a, b)` (forward-progress DAG comparison) is
  the spec-level semantic; a Rust implementation would use a `PartialOrd`
  impl with the same semantics. The `StateRegistry` class is a Python idiom
  for a graph store; other languages may use a struct, a map, or a database.

### What is language-agnostic and IS the spec

- The workflow JSON shape (states map, transitions with `verdict → target`,
  `loop` flag, `event_name` (mandatory), `reentry_budget` blocks, `kind` enum values).
- The passport JSON shape.
- The StepOutcome contract (`{ verdict, decision?, confidence? }`) — the
  minimal contract the engine routes on. `verdict` is a `NewType(str, ...)`,
  not a fixed enum, allowing project-specific verdict values while retaining
  type safety at the engine boundary.
- The forward-progress DAG comparison semantic (`StateRegistry.is_ancestor(a, b)`
  returns `True` iff `a` is a strict ancestor of `b` in the graph with
  `loop:true` edges removed; `IncomparableStates` when no path either way).
- The context model (`input` + `vars` + `meta`). Context is frozen;
  `vars` are deep-copied per parallel branch to prevent cross-branch
  mutation. `Context.is_retry` is split into `is_loop_back` (entry_count > 1)
  and `is_retry` (attempt > 0).
- The deterministic idempotency key: `sha256(subject_id + step + entry_count + attempt)`.
- The deterministic-vs-judgement transition table.
- The data classification model (`public` / `private` / `protected` +
  `Redactor` protocol). Default classification is `private` (fail-closed).
  Classification applies to primitives only; `project()` recurses into
  objects. Undeclared fields default to `private`. Redactors parse
  everything to string; retention is unbounded. A `RedactorNotRegisteredError`
  is raised when a redactor is missing for a classified field.
- The lifecycle event model (engine events + domain event_name per
  transition). The events table uses a hash chain for tamper-evidence.
  A separate `status_log` table records flag events (cancelled, deferred,
  archived) — these are status flags, not synthetic terminal states.
- `advance()` absorbs parallel join and aggregation internally; the caller
  does not manage fork/join mechanics.
- `record_decision` stays a separate operation from `advance`; it writes a
  `StepRecord` with the decision payload.
- The exception hierarchy: `WorkflowError` (base) with subclasses for
  specific error conditions.
- A0 (roster confirmation) is modelled as a `decision_required` state with
  `decision.roster_confirmation`.
- Hooks: `HookErrorSink` collects non-fatal hook errors; critical hooks
  (audit) fail-closed. Write-before-hooks fire in registration order.
  There is no separate `AuditHook` — the `EventStore` IS the audit trail.
- Agent snapshot: agents are resolved from `agents_folder` at dispatch time;
  if an agent definition has changed since the last dispatch, a warning is
  issued.
- Configuration: `ConfigPort` protocol lives in the domain layer; `Config`
  implementation lives in the infrastructure layer.
- Path sanitisation: all file paths derived from workflow data are sanitised
  to prevent path traversal.
- UI safety: any UI rendering dynamic workflow content MUST HTML-escape it.

### Python 3.14+ is chosen for the reference implementation

Because it offers `enum.StrEnum`, `uuid.uuid7()` (RFC 9562, time-ordered
UUIDs), deferred annotations (PEP 649), `copy.replace()`, improved
error messages, and `typing.NewType` for `Verdict` — all of which reduce
boilerplate and improve the prototype's fidelity to the spec. Requiring
3.14+ is a prototype decision, not a spec decision.

### Actor generalisation

The engine does not know what an "agent" or a "human" is. It knows about
`DispatchHandler.dispatch()` — a pluggable protocol registered in the
`DispatcherRegistry`. A state declares which handler to use
(`"dispatch_handler": "engine.subagent_dispatch"`). The handler owns all
actor-specific logic (LLM subagent dispatch, human form presentation,
system webhook call, or any custom dispatch mode). The outcome contract
is identical regardless of actor kind. This is consistent with the Design
Agnosticism principle: the engine is reusable across projects with
different actor mixes (agent-only, human-only, system-only, or any
combination).

Gates have NO `dispatch_handler` and NO `retry` — they are pure evaluation
points, not dispatch targets. The engine resolves dispatch targets via the
`dispatch_handler` name in the `DispatcherRegistry`.

The `agent` field is moved to the project profile as abstract roles
(orchestrator, architect, reviewer). A role maps to an agent, a human, or
a service at the profile level, keeping the engine agnostic to actor
identity.

Dispatch retry uses `dispatch_retry` (global + per-state, exponential
backoff) for transient dispatch failures. Gate reentry uses
`reentry_budget` (default 3, per-gate) for gate-fail retry loops.

### Payload generalisation

The engine validates project-specific data structures (Finding,
Recommendation, Gap, etc.) via the `SchemaRegistry` but does not interpret
them. These structures live in a project-specific schema profile
(`workflows/psc-profile.json`). A different project (survey, process,
review) defines its own profile. The engine is agnostic to the profile's
contents — it routes on `verdict` (the engine contract) and stores the
rest as opaque JSON.

The engine distinguishes two payload categories:
- **StepOutcome** — validated, schema-conformant payload produced by a step.
- **RawPayload** — forensic, optional capture of the raw output before
  validation, preserved for debugging and audit.

Outcomes are written via the `OutcomeStore` protocol, which accepts either
a string or a byte array; the implementation decides the storage format.

### Claim and lease safety

The engine uses a fencing token (`claim_epoch`) for claim/lease safety.
Each claim increments the epoch; a stale claim with an outdated epoch is
rejected, preventing split-brain dispatch.

---

## References

All citations are in [06-references.md](06-references.md). Key foundational
sources:

- Amazon States Language spec — https://states-language.net/spec.html
- OMG BPMN 2.0.2 — https://www.omg.org/spec/BPMN/2.0.2/
- Camunda 8 docs — https://docs.camunda.io/
- Temporal docs — https://docs.temporal.io/
- RFC 9562 (UUIDv7) — https://datatracker.ietf.org/doc/rfc9562/
- RFC 9535 (JSONPath) — https://datatracker.ietf.org/doc/rfc9535/
- Python 3.14 docs — https://docs.python.org/3.14/
