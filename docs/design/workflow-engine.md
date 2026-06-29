# PSC Workflow Engine — Design Document

> **Status:** DRAFT. All architecture decisions are marked **[LOCKED]** or **[TENTATIVE]**.
> **Branch:** `feature/workflow-engine` (created as the first executable step, per §0).
> **Owner:** Supreme Leader (orchestrating); design synthesised from parallel agent
> exploration + critique + authoritative research on workflow semantics.

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

## 0. Executable Steps (ordered)

These are the concrete first actions. Each is a shippable, testable unit.
**The API contracts (§0.1–0.3) are agreed before any code is written.**

| # | Step | What gets locked | Why first |
|---|------|------------------|-----------|
| **0.1** | **Align on workflow steps & state machine** — walk every state (A0…CR3), its `kind` (task/parallel/gate/decision_required/terminal), its outgoing transitions, and whether each transition is a loop-back. Lock the transition table (§7) as the contract. | State machine contract | Foundation everything depends on |
| **0.2** | **Align on outcomes per state** — for each state, agree the `outcome_schema` (the fields an agent fills and returns). Lock the AgentOutcome shape (§2.3) and the per-state variants. Includes the Python prototypes for `State`, `StateRegistry`, `Context`, `ConfigReader`, `RosterResolver` (§2.4, §2.5). | Outcome contracts | The data contracts the state machine routes on |
| **0.3** | **Align on API contracts** — lock the MCP/CLI tool surface (§3): tool names, inputs, outputs, deterministic-vs-error semantics. Both surfaces (MCP + CLI) share these contracts; only the transport differs. Includes the end-to-end test prototype (§3.3) as the executable spec. | API contracts | "All API contracts agreed before coding" — no implementation starts until these are signed off |
| **0.4** | **Create the feature branch** `feature/workflow-engine` | First executable step | Isolates all workflow-engine work from `main` |
| **0.5** | Commit this design doc to `docs/design/workflow-engine.md` on the branch | Version-controlled record of the locked design | Reviewable before any code |
| **0.6** | Begin Phase 1 of implementation (§9) — schemas + library core | Implementation begins | The contracts from 0.1–0.3 become the spec |

> **Status:** Steps 0.4 and 0.5 are complete (this commit). Steps 0.1–0.3 are
> the next review cycle; no implementation begins until they are signed off.

---

## 1. Architecture Decisions

### 1.1 State-machine access boundary — dual surface [TENTATIVE]

**Decision:** Design both surfaces; pick at runtime.

The `psc_engine` library is pure logic with no I/O. Two thin, swappable wrappers
expose identical contracts:

- **MCP server `psc-state`** — the Supreme Leader calls `mcp__psc_state__*`
  tools. No `bash` needed; MCP is a separate channel from `bash:`. Preserves
  `edit: deny, bash: deny` and the dispatch-only invariant. Requires the
  OpenCode runtime to expose MCP tools to the primary agent.
- **CLI `python -m psc_engine ...`** — the Supreme Leader calls via `bash`.
  Simpler, no MCP infrastructure. Requires updating the Permission
  Validation Rule (dispatch-only no longer implies `bash: deny` when the only
  permitted bash invocations are `psc_engine` calls).

The API contracts (tool names, inputs, outputs) are identical across both.
The choice is deferred to runtime / §11 open question 1. No agent overhead
either way — neither surface requires a helper agent.

**Review note:** if you prefer one surface, the library implementation
underneath is identical; only the wrapper changes.

---

### 1.2 Storage — JSON + advisory lock + derived Markdown mirror [LOCKED]

Each ticket stores its state as a **JSON file** (`passports/<TKT>.json`)
guarded by an advisory `flock`. On every state transition, a **read-only
Markdown mirror** (`passports/<TKT>.md`) is auto-generated and committed;
drift between regenerated and committed copy is a CI failure.

**Why:** The current system is already **single-writer** — agents return
outcomes as text; the Supreme Leader (via the state service) aggregates and
writes. Parallel agents do not write the passport concurrently. Therefore:

- The locking/retry problem the original brief worried about is largely
  **theoretical** under the single-writer model. `flock` guards the rare
  re-entrant write.
- SQLite-WAL offers atomicity/queries that are wasted on single-writer-per-
  ticket, breaks per-ticket portability, and destroys the git-diff-reviewable
  property the audit model depends on.
- JSON preserves portability, version-pinning, and human reviewability at
  near-zero cost.

**Markdown mirror rationale:** humans review markdown diffs today; building
JSON review tooling is unbudgeted. JSON is authoritative; the mirror is
regenerated on every `advance()` and committed, marked
`<!-- AUTO-GENERATED from <TKT>.json; do not edit -->`. A `validate_passport`
check regenerates the mirror and diffs it against the committed copy — drift
is a CI failure. A reviewer never has to learn JSON.

---

### 1.3 Decision-required states — five judgement points [LOCKED]

The five judgement points are **first-class `decision_required` states** in the
workflow, not branches baked into the transition graph. The machine halts at a
decision state; a typed decision object is supplied (by user or PM); the
outbound transition is computed **deterministically from the decision object's
fields** via routing rules declared in the workflow.

**The five judgement points:**

1. **A0 — task-domain classification + roster confirmation** (Supreme Leader
   proposes a roster from domain signals; user confirms via a checklist with
   defaults pre-selected; user can keep as-is, deselect, or add a custom
   specialist entry if `<name>.md` exists in `agents_folder`).
2. **A2c — user disposition** (human rules on each A2 finding:
   ACCEPT/REJECT/BACKLOG/DEFER/IMPLEMENT_NOW).
3. **C4 — PM completion decision** (6-way:
   complete/backlog_split/rework/escalate/defer/add_tests).
4. **Gate-fail root-cause correction** (agent classifies RC-1..RC-5 before
   retry; routing is deterministic by tier, but the RC classification is
   agent judgement).
5. **A0 clarification loop** (ambiguous instruction → Supreme Leader cannot
   classify → outcome `needs_clarification` → routes to PM to ask the user;
   loops at A0 until clarified).

**Rule:** the state machine never *computes* a judgement; it *records* it and
routes off its declared fields.

---

### 1.4 Schema evolution — snapshot workflow + agents into the ticket at A0 [LOCKED]

At task creation (A0), the workflow definition JSON **and** the referenced
agent definition files are **copied into the ticket directory**
(`snapshots/<TKT>/workflow.json`, `snapshots/<TKT>/agents/`). The passport
pins that snapshot. In-flight tickets run against their frozen snapshot for
their entire lifetime.

**Why:** if the security specialist's role changes mid-flight, re-running C2
against the new definition can produce conclusions inconsistent with the
B-phase assumptions — a silent correctness regression. Snapshots guarantee
reproducibility. This is the **snapshot-per-instance** consensus across
Camunda, Step Functions, and Temporal-Pinned (see §1.7, §12 references).

**Versioning policy:**

- Workflows are **SemVer** (`MAJOR.MINOR.PATCH`).
- PATCH (transition/schema bugfix, backward compatible) and MINOR (new
  optional states/fields, additive) auto-apply to **new** tickets only.
- MAJOR (breaking schema/transition change) creates a new workflow file;
  new tickets pin the new MAJOR, in-flight tickets keep theirs.
- **Max 2 concurrent MAJOR versions supported.** Shipping a third retires
  the oldest immediately (its grace window already elapsed).
- When a new MAJOR ships, the old enters `DEPRECATED` (rejects new tickets,
  serves in-flight). After a **90-day grace** window, any ticket still on
  the deprecated version is force-migrated (PM review + recorded decision)
  or closed.
- **No auto-migration of in-flight tickets.** A ticket that needs a new
  workflow version is closed and re-opened, or explicitly re-pinned by the
  PM with a recorded decision.

---

### 1.5 Human review trail — derived Markdown mirror, JSON authoritative [LOCKED]

JSON is authoritative; `passports/<TKT>.md` is regenerated on every `advance()`
and committed. A `validate_passport` check regenerates the mirror and diffs it
against the committed copy — drift is a CI failure.

**Why:** building JSON review tooling is a large investment for a payoff
humans already get from `git diff` + a Markdown viewer. The mirror preserves
the existing review workflow with zero new tooling. JSON tooling is built only
for machines (the state service, CI, the `psc` CLI); humans get Markdown.

---

### 1.6 Adhoc tasks — separate workflow file `psc-adhoc` [LOCKED]

Adhoc/small tasks run a **separate workflow definition** `psc-adhoc`
(version-pinned independently), not a branch inside `psc-main`.

**Why:** branching inside one workflow couples the two lifecycles and makes
the state table unreadable; a distinct workflow file lets small-task rules
evolve without touching the main pipeline, and a ticket pins whichever it uses.

**The `psc-adhoc` workflow** (full definition in §8):

- **Skipped/lightened:** A1 parallel fan-out → single reviewer; A2 dual-model
  challenge → dropped; A2c user-disposition → PM decides inline; T2/T3 deep
  tiers → T1 only (findings still collected opportunistically but not
  gating); retry budgets halved (2 not 3); review rounds 3 not 5.
- **Mandatory, never skippable:**
  1. A0L task definition (an ambiguous adhoc task is more dangerous than a
     structured one because there's less downstream scrutiny).
  2. T1 mechanical gate (build/docs/grep) at B2a, B3a, C3L — a non-building
     change is always wrong regardless of task size. T1 is the cheapest,
     highest-signal check.
  3. B build + B3a gate — no change ships unvalidated.
  4. CR code review — even small changes get a reviewer pass (reduced rounds,
     not optional).

**Selection:** the Supreme Leader chooses the workflow at ticket creation
(`psc new-ticket --workflow=psc-adhoc`) based on the A0 classification's
`is_adhoc` heuristic (single-concern, single-file-class, no architecture
impact). The choice is recorded and not re-evaluated mid-flight (would break
the version-pin invariant). If an adhoc task grows scope, the PM closes it
and opens a `psc-main` ticket.

---

### 1.7 Workflow semantics — BPMN 2.0.2 + ASL vocabulary + LTS graph [LOCKED]

Grounded in authoritative research (see §12 references). Our terms map to
industry standards as follows:

| Our term | Standard term | Authority |
|----------|--------------|-----------|
| Phase | (no BPMN equivalent; grouping/ordinal) | Metadata field, not a graph element |
| Step / State | **Task** (BPMN) / **State** (ASL) | A node in the graph |
| Gate | **Gateway** (BPMN) / **Choice state** (ASL) | A routing node with conditions |
| Decision | **User Task** (BPMN) | Blocks until a human/PM supplies a form; output becomes variables; a downstream Choice routes on them |
| Outcome | **Task output / event payload** (ASL) | The JSON that flows along the edge to the next state |
| Verdict | **Choice Rule condition** (ASL) / **Gateway condition** (BPMN) | The evaluated predicate that selects which outgoing edge to take |
| Kind | **State type** (ASL: Task, Choice, Parallel, Wait, Succeed, Fail) | The category of a node |
| Tier | (no standard; project-specific) | Metadata on a gate |
| Retry | **Retry** block (ASL: `max_attempts`, `interval`, `backoff`) | Re-execute the *same* state on transient failure, with a budget |
| Loop-back | **Explicit `Next` edge to an earlier state** (ASL) / **Boundary error event** (BPMN) | Transition to an *earlier* state on substantive failure — a cycle in the graph |

**Representation:** a **labeled transition system** (graph, not linked list),
ASL-influenced. Each state holds a `transitions: dict[Verdict, Transition]`
where `Transition = {target: state_name, loop: bool, skip: list[str]}`.
Edges are labeled by outcomes; multiple states can transition to the same
state (multiple incoming edges). This matches ASL exactly: "States can have
multiple incoming transitions from other states" (ASL spec, §Transitions).

**Retry vs loop-back — two distinct mechanisms, two distinct budgets:**

- **Retry** = re-execute the *same* state due to a transient error, with a
  budget (`max_attempts`). Modeled as an ASL-style `retry` block on the state.
  Budget is per-state-execution; resets on transition.
- **Loop-back** = transition to an *earlier* state due to a substantive gate
  failure, with its own budget. Modeled as an explicit `Next` edge with
  `loop: true` flag — a cycle in the graph. The graph allows arbitrary
  `next` targets. Track a `gate_failure_count` variable to cap iterations.

---

### 1.8 Process context model — input + vars + meta [LOCKED]

Grounded in ASL, Camunda, and Temporal (see §12 references). A state handler
receives a `Context` with exactly three things:

1. **`input`** — the payload passed in from the transition (the
   predecessor's output or the loop-back payload). Mirrors ASL's "output
   from the first state is passed as input to the second" and Camunda's job
   variables.
2. **`vars`** — a **flat** mutable mapping of workflow variables visible to
   this state. This is the ASL/Camunda blackboard. Handlers read what they
   need; they write selected outputs back via an explicit `set` API, mirroring
   Camunda's output mappings and ASL's `Assign`. Flat (not hierarchically
   scoped) — sufficient for our single-process-per-ticket model; our parallel
   branches are short-lived specialists, not long subprocesses.
3. **`meta`** — a small fixed-shape metadata record:
   `{ from_state, entry_count, attempt, entered_at }`. `from_state` is the
   single predecessor name (one-step window). `entry_count` lets a gate ask
   "am I being revisited?" the way ASL's `State.RetryCount` does. `attempt`
   exposes Retrier attempts. O(1) memory.

**Do NOT expose a full path list.** None of ASL, Camunda, or Temporal does,
and for good reason: it couples every state to the entire history shape,
blows up memory for long-lived runs, and breaks if the graph is refactored.
The "where did I come from" question is answered by *one step* (`from_state`)
plus *intentional signals stored in `vars`* (e.g.
`vars["retry_reason"] = "gate_failed"` set by the gate's own retry handler).

The full `step_log` in the passport is the persisted audit trail (what all
three engines keep service-side), but it is **not** surfaced to handlers.

---

## 2. Data Model

Schemas are JSON Schema 2020-12. Python prototypes are embedded verbatim —
they are the executable spec for §0.2 and §0.3, not the final implementation.

### 2.1 Workflow Definition — `workflows/<id>/<version>.json`

ASL-influenced. A `states` map + `start_at` + explicit `transitions` with
`outcome → target` + `loop` flag on back-edges + `kind` (state type) +
`retry` blocks for transient retry + `decision_schema`/`routing_rule` for
User Task (decision) states.

```jsonc
{
  "workflow_id": "psc-main",
  "version": "2.0.0",
  "start_at": "A0",
  "phases": [
    {"id":"A","ord":0},
    {"id":"B","ord":1},
    {"id":"C","ord":2},
    {"id":"CR","ord":3}
  ],
  "states": {
    "A0": {
      "name":"A0","title":"Task Definition & Domain Classification",
      "phase":"A","step":0,"kind":"task","agent":"supreme-leader",
      "transitions": {
        "classified":          {"target":"A1"},
        "needs_clarification": {"target":"A0","loop":true}
      }
    },
    "A1": {
      "name":"A1","title":"Parallel Specialist Review",
      "phase":"A","step":1,"kind":"parallel","agent":"supreme-leader",
      "fan_out":"$roster","join":"all",
      "transitions": {"reviews_complete":{"target":"A2"}}
    },
    "A2": {
      "name":"A2","title":"Dual-Model Challenge",
      "phase":"A","step":2,"kind":"parallel","agent":"supreme-leader",
      "fan_out":["primary","challenger"],"join":"all",
      "transitions": {"challenge_complete":{"target":"A2b"}}
    },
    "A2b": {
      "name":"A2b","title":"Synthesis Artifact Creation",
      "phase":"A","step":3,"kind":"task","agent":"pm",
      "transitions": {"synthesized":{"target":"A2c"}}
    },
    "A2c": {
      "name":"A2c","title":"Decision Register Presentation",
      "phase":"A","step":4,"kind":"decision_required","agent":"user",
      "decision_schema":"decision.user_disposition",
      "routing_rule":"route.user_disposition",
      "transitions": {}
    },
    "A2a": {
      "name":"A2a","title":"ADR Creation",
      "phase":"A","step":5,"kind":"task","agent":"code-architect",
      "transitions": {"adr_written":{"target":"A3"}}
    },
    "A3": {
      "name":"A3","title":"A-GATE",
      "phase":"A","step":6,"kind":"gate","agent":"supreme-leader",
      "gate_config":"gate.A3",
      "transitions": {
        "pass":      {"target":"B1"},
        "fail":      {"target":"A2a","loop":true},
        "exhausted": {"target":"ESCALATE"}
      },
      "retry": [{"error_equals":["gate_fail"],"max_attempts":3}]
    },
    "B1": {
      "name":"B1","title":"PLAN",
      "phase":"B","step":0,"kind":"task","agent":"code-architect",
      "transitions": {"planned":{"target":"B2"}}
    },
    "B2": {
      "name":"B2","title":"APPLY (per unit)",
      "phase":"B","step":1,"kind":"task","agent":"code-architect",
      "transitions": {
        "unit_applied":   {"target":"B2a"},
        "units_complete": {"target":"B3"}
      }
    },
    "B2a": {
      "name":"B2a","title":"B-UNIT-GATE",
      "phase":"B","step":2,"kind":"gate","agent":"supreme-leader",
      "gate_config":"gate.B2a",
      "transitions": {
        "pass":      {"target":"B2"},
        "fail":      {"target":"B2","loop":true},
        "exhausted": {"target":"ESCALATE"}
      },
      "retry": [{"error_equals":["gate_fail"],"max_attempts":3}]
    },
    "B3": {
      "name":"B3","title":"VALIDATE",
      "phase":"B","step":3,"kind":"task","agent":"code-architect",
      "transitions": {"validated":{"target":"B3a"}}
    },
    "B3a": {
      "name":"B3a","title":"B-FINAL-GATE",
      "phase":"B","step":4,"kind":"gate","agent":"supreme-leader",
      "gate_config":"gate.B3a",
      "transitions": {
        "pass":      {"target":"C0"},
        "fail":      {"target":"B1","loop":true},
        "exhausted": {"target":"ESCALATE"}
      },
      "retry": [{"error_equals":["gate_fail"],"max_attempts":3}]
    },
    "C0": {
      "name":"C0","title":"T1 Re-run",
      "phase":"C","step":0,"kind":"task","agent":"supreme-leader",
      "transitions": {"done":{"target":"C1"}}
    },
    "C1": {
      "name":"C1","title":"Dual-Model Challenge (Verification)",
      "phase":"C","step":1,"kind":"parallel","agent":"supreme-leader",
      "fan_out":["primary","challenger"],"join":"all",
      "transitions": {"challenge_complete":{"target":"C2"}}
    },
    "C2": {
      "name":"C2","title":"Parallel Specialist Approval",
      "phase":"C","step":2,"kind":"parallel","agent":"supreme-leader",
      "fan_out":"$roster","join":"all",
      "transitions": {
        "all_approved": {"target":"C3"},
        "any_rejected": {"target":"CR1"}
      }
    },
    "C3": {
      "name":"C3","title":"C-GATE",
      "phase":"C","step":3,"kind":"gate","agent":"supreme-leader",
      "gate_config":"gate.C3",
      "transitions": {
        "pass":      {"target":"C4"},
        "fail":      {"target":"B1","loop":true},
        "exhausted": {"target":"ESCALATE"}
      },
      "retry": [{"error_equals":["gate_fail"],"max_attempts":3}]
    },
    "C4": {
      "name":"C4","title":"PM Completion Review",
      "phase":"C","step":4,"kind":"decision_required","agent":"pm",
      "decision_schema":"decision.c4_completion",
      "routing_rule":"route.c4",
      "transitions": {}
    },
    "CR1": {
      "name":"CR1","title":"Code Review Round",
      "phase":"CR","step":0,"kind":"task","agent":"code-reviewer",
      "transitions": {"reviewed":{"target":"CR2"}}
    },
    "CR2": {
      "name":"CR2","title":"CR-GATE",
      "phase":"CR","step":1,"kind":"gate","agent":"supreme-leader",
      "gate_config":"gate.CR2",
      "transitions": {
        "accept":          {"target":"CR3"},
        "request_changes": {"target":"B2","loop":true},
        "exhausted":       {"target":"ESCALATE"}
      },
      "retry": [{"error_equals":["gate_fail"],"max_attempts":5}]
    },
    "CR3": {
      "name":"CR3","title":"Review Acceptance",
      "phase":"CR","step":2,"kind":"task","agent":"code-reviewer",
      "transitions": {"accepted":{"target":"COMMIT"}}
    },
    "COMMIT": {
      "name":"COMMIT","title":"Commit",
      "phase":"CR","step":3,"kind":"terminal","agent":""
    },
    "ESCALATE": {
      "name":"ESCALATE","title":"Escalate",
      "phase":"CR","step":4,"kind":"terminal","agent":""
    }
  },
  "gate_configs": {
    "gate.A3":  {"tiers":["T3","T-ARCH"],"retry_budget":{"T3":3,"T-ARCH":3}},
    "gate.B2a": {"tiers":["T1","T-ARCH"],"retry_budget":{"T1":3,"T-ARCH":3}},
    "gate.B3a": {"tiers":["T1","T2","T-ARCH"],"retry_budget":{"T1":3,"T2":3,"T-ARCH":3}},
    "gate.C3":  {"tiers":["T1","T3","T-ARCH"],"retry_budget":{"T1":3,"T3":3,"T-ARCH":3}},
    "gate.CR2": {"tiers":["T3"],"retry_budget":{"T3":5},"round_budget":5}
  },
  "decision_schemas": {
    "decision.user_disposition": {
      "type":"object",
      "properties":{
        "findings":{
          "type":"array",
          "items":{"type":"object","properties":{
            "finding_id":{"type":"string"},
            "disposition":{"type":"string",
              "enum":["ACCEPT","REJECT","BACKLOG","DEFER","IMPLEMENT_NOW"]}
          }}
        }
      }
    },
    "decision.roster_confirmation": {
      "type":"object",
      "properties":{
        "roster":{"type":"array","items":{"type":"string"},
          "default":["sw-engineer","test-engineer","docs-writer"]},
        "added_custom":{"type":"array","items":{"type":"object",
          "properties":{
            "name":{"type":"string"},
            "domain_signals":{"type":"array","items":{"type":"string"}}
          }}},
        "rationale":{"type":"string"}
      }
    },
    "decision.c4_completion": {
      "type":"object",
      "properties":{
        "decision":{"type":"string",
          "enum":["complete","backlog_split","rework","escalate","defer","add_tests"]},
        "rationale":{"type":"string"},
        "backlog_refs":{"type":"array","items":{"type":"string"}}
      }
    }
  },
  "routing_rules": {
    "route.user_disposition": {
      "match":"any finding.disposition == IMPLEMENT_NOW || ACCEPT",
      "on_match":{"target":"A2a"},
      "on_no_match":{"target":"A3","skip":["A2a"]}
    },
    "route.c4": {
      "complete":{"target":"CR1"},
      "backlog_split":{"target":"CR1"},
      "rework":{"target":"B1","loop":true},
      "escalate":{"target":"ESCALATE"},
      "defer":{"target":"DEFERRED"},
      "add_tests":{"target":"B1","loop":true,"scope":"tests"}
    }
  },
  "retry_policy": {"max_per_tier":3,"on_exhaust":"ESCALATE"},
  "max_review_rounds": 5
}
```

### 2.2 Passport — `passports/<TKT>.json`

```jsonc
{
  "ticket_id": "TKT-0001",
  "title": "Add BLE scan filter",
  "request": "<original instruction>",
  "requester": "user",
  "created_at": "2026-06-29T10:00:00Z",
  "updated_at": "2026-06-29T11:30:00Z",
  "workflow_id": "psc-main",
  "workflow_version": "2.0.0",
  "agent_snapshot": {"ref":"snapshots/TKT-0001/agents/","taken_at":"2026-06-29T10:00:00Z"},
  "is_adhoc": false,

  "domain_classification": {
    "primary":"security",
    "secondary":["test"],
    "roster":["security","test","design"]
  },

  "state": {
    "current":"A2c",
    "phase":"A",
    "entered_at":"2026-06-29T11:00:00Z",
    "is_decision_pending":true,
    "pending_decision_schema":"decision.user_disposition"
  },

  "retries": {
    "A3":  {"T3":0,"T-ARCH":0},
    "B2a": {"T1":0,"T-ARCH":0},
    "B3a": {"T1":0,"T2":0,"T-ARCH":0},
    "C3":  {"T1":0,"T3":0,"T-ARCH":0},
    "CR2": {"T3":0}
  },
  "review_round": 0,
  "max_review_rounds": 5,

  "vars": {},

  "step_log": [
    {"step":"A0","agent":"supreme-leader","model":"glm-5.2",
     "started_at":"...","completed_at":"...","stamp":"STMP-0001",
     "status":"complete","from_state":null,"entry_count":1,"attempt":0}
  ],
  "outcomes": {"A0": {}},
  "gate_results": [],
  "decisions": [],
  "loop_history": [],
  "corrections": [],
  "reviews": {"current_round":0,"rounds":[]},
  "skips": [],
  "parallel_progress": {
    "A1": {
      "expected":["security","test","design"],
      "returned":["security"],
      "pending":["test","design"],
      "join":"all"
    }
  },
  "version_pins": {"workflow":"2.0.0","agent_snapshot":"snapshots/TKT-0001"}
}
```

### 2.3 Agent Outcome — returned by every agent at every step

```jsonc
{
  "step": "A1#security",
  "agent": "security-specialist",
  "model": "glm-5.1",
  "role": "specialist",
  "verdict": "pass",
  "confidence": 87,
  "findings": [
    {"id":"F1","severity":"blocker",
     "category":"security",
     "message":"unbounded memcpy in scan parser",
     "reference":"https://owasp.org/..."}
  ],
  "agreements": [],
  "disagreements": [],
  "missing_considerations": [],
  "recommendations": [],
  "deliverables": [
    {"type":"file","ref":"src/scan.c","sha":"abc123"},
    {"type":"adr","ref":"docs/adr/0007.md"}
  ],
  "flags": [
    {"type":"assumption","severity":"high","detail":"assumed buffer ≤ MTU without check"}
  ],
  "decision": null,
  "gate_result": null,
  "root_cause": null,
  "timestamp": "2026-06-29T10:05:00Z"
}
```

Composite outcomes (`outcome.specialist_composite`, `outcome.challenge_composite`,
`outcome.approval_composite`) wrap a list of per-agent outcomes plus a
synthesised verdict — see §6 (Parallel Flows).

### 2.4 State Model — Python prototype (executable spec for §0.2)

```python
# psc_engine/domain/state.py
from __future__ import annotations
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class StateKind(Enum):
    """The category of a state. Enum because it has no parameters."""
    TASK = "task"
    PARALLEL = "parallel"
    GATE = "gate"
    DECISION_REQUIRED = "decision_required"
    TERMINAL = "terminal"

    def __str__(self) -> str:
        return self.value


class Verdict(Enum):
    """The result an agent returns. Enum because it has no parameters.
    If a verdict ever needs parameters (e.g. gate verdict with tier
    results), add a GateVerdict class alongside this enum."""
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

    def __str__(self) -> str:
        return self.value


class IncomparableStates(Exception):
    """Raised when two states have no directed path between them in the
    forward-progress DAG — neither is an ancestor of the other."""
    def __init__(self, a: "State", b: "State"):
        super().__init__(
            f"State {a.name} and state {b.name} are incomparable: "
            f"no directed path between them in the forward-progress DAG."
        )
        self.a, self.b = a, b


@dataclass(frozen=True)
class Transition:
    """A labeled edge: 'on this outcome, go to that state.'
    loop=True marks a back-edge (excluded from the comparison graph)."""
    outcome: Verdict
    target: str
    loop: bool = False
    skip: tuple[str, ...] = field(default_factory=tuple)


@dataclass(frozen=True)
class State:
    """Base class for all workflow states. Loaded dynamically from JSON;
    each gets a runtime id. Comparable via path-reachability in the
    forward-progress DAG (back-edges excluded)."""
    id: int
    name: str
    title: str
    phase: str
    step: int
    kind: StateKind
    agent: str
    transitions: dict[Verdict, Transition] = field(default_factory=dict)

    def __str__(self) -> str:
        return f"{self.name} ({self.title})"

    def __repr__(self) -> str:
        return f"State({self.name!r}, kind={self.kind})"

    def __lt__(self, other: "State") -> bool:
        """self < other  iff  self is a strict ancestor of other
        (path from self to other exists, self ≠ other) in the forward DAG.
        Raises IncomparableStates if no path either way."""
        if self is other or self.name == other.name:
            return False
        return self._registry._is_ancestor(self.name, other.name)

    def __le__(self, other: "State") -> bool:
        if self.name == other.name:
            return True
        return self.__lt__(other)

    def __gt__(self, other: "State") -> bool:
        return other.__lt__(self)

    def __ge__(self, other: "State") -> bool:
        return other.__le__(self)

    def __eq__(self, other: object) -> bool:
        return isinstance(other, State) and self.name == other.name

    def __hash__(self) -> int:
        return hash(self.name)

    _registry: "StateRegistry | None" = field(default=None, repr=False, compare=False)


class StateRegistry:
    """Holds the dynamically-loaded states and the forward-progress DAG.
    A dict[str, State] at its core; provides ancestor queries for comparison.
    Forward-progress DAG = full graph with back-edges (loop=True) removed,
    so cycles don't pollute the ancestor relation."""
    def __init__(self):
        self._states: dict[str, State] = {}
        self._next_id: int = 0
        self._forward_descendants: dict[str, set[str]] = {}
        self._full_graph: dict[str, set[str]] = {}

    def load_from_workflow(self, workflow_def: dict) -> None:
        """Load states from a workflow JSON definition (ASL-style).
        Assigns runtime ids, builds the forward-progress DAG (back-edges
        where transition.loop == True are excluded)."""
        self._states.clear()
        self._next_id = 0
        for name, sdef in workflow_def["states"].items():
            kind = StateKind(sdef["kind"])
            st = State(
                id=self._next_id, name=name, title=sdef["title"],
                phase=sdef["phase"], step=sdef["step"], kind=kind,
                agent=sdef.get("agent", ""), transitions={},
            )
            st._registry = self
            self._states[name] = st
            self._next_id += 1
        for name, sdef in workflow_def["states"].items():
            transitions: dict[Verdict, Transition] = {}
            for outcome_key, tdef in sdef.get("transitions", {}).items():
                transitions[Verdict(outcome_key)] = Transition(
                    outcome=Verdict(outcome_key),
                    target=tdef["target"],
                    loop=tdef.get("loop", False),
                    skip=tuple(tdef.get("skip", [])),
                )
            old = self._states[name]
            self._states[name] = State(
                id=old.id, name=old.name, title=old.title,
                phase=old.phase, step=old.step, kind=old.kind,
                agent=old.agent, transitions=transitions,
            )
            self._states[name]._registry = self
        self._build_dags()

    def _build_dags(self) -> None:
        """Build the forward-progress DAG (back-edges excluded) and the full graph."""
        self._full_graph = {n: set() for n in self._states}
        self._forward_descendants = {n: set() for n in self._states}
        for name, st in self._states.items():
            for t in st.transitions.values():
                self._full_graph[name].add(t.target)
                if not t.loop:
                    self._forward_descendants[name].add(t.target)
        # transitive closure of the forward DAG (reachability)
        changed = True
        while changed:
            changed = False
            for n in self._states:
                new = set(self._forward_descendants[n])
                for child in list(self._forward_descendants[n]):
                    new |= self._forward_descendants.get(child, set())
                if new != self._forward_descendants[n]:
                    self._forward_descendants[n] = new
                    changed = True

    def _is_ancestor(self, a: str, b: str) -> bool:
        """True iff a is a strict ancestor of b in the forward-progress DAG.
        Raises IncomparableStates if neither is an ancestor of the other."""
        if a == b:
            return False
        a_anc_b = b in self._forward_descendants.get(a, set())
        b_anc_a = a in self._forward_descendants.get(b, set())
        if a_anc_b:
            return True
        if b_anc_a:
            return False
        raise IncomparableStates(self._states[a], self._states[b])

    def __getitem__(self, name: str) -> State:
        return self._states[name]

    def __contains__(self, name: str) -> bool:
        return name in self._states

    def all_states(self) -> list[State]:
        return list(self._states.values())
```

### 2.5 Context Model — Python prototype (executable spec for §0.2)

```python
# psc_engine/domain/context.py
from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any


@dataclass(frozen=True)
class StateMeta:
    """Fixed-shape metadata: how the process reached this state.
    Mirrors ASL's Context Object (State.RetryCount) — a small metadata
    record, NOT a path array. Memory: O(1)."""
    from_state: str | None
    entry_count: int
    attempt: int
    entered_at: datetime


@dataclass
class Context:
    """What a state handler sees when the process reaches a state.
    Grounded in ASL (predecessor output + variables + RetryCount),
    Camunda (scoped variables), Temporal (locals reconstructed from
    history). Deliberately NOT a full path: no engine exposes one."""
    input: dict[str, Any]
    vars: dict[str, Any]
    meta: StateMeta

    def is_retry(self) -> bool:
        """True iff this state is being re-entered after a gate failure
        or a transient retry (mirrors ASL State.RetryCount > 0)."""
        return self.meta.entry_count > 1 or self.meta.attempt > 0

    def reached_from(self, state_name: str) -> bool:
        """True iff the single predecessor is `state_name`. Use this
        to distinguish happy-path entry from loop-back entry."""
        return self.meta.from_state == state_name
```

### 2.6 Config + Roster — Python prototype (executable spec for §0.2)

```yaml
# psc_engine.yaml — workflow engine configuration
# PyYAML (stdlib can't read YAML); managed by uv.

paths:
  agents_folder: agents          # any <name>.md here is a valid specialist
  workflows_folder: workflows
  passports_folder: docs/project-management/passports

roster:
  # pre-selected defaults when the user confirms at A0
  default:
    - sw-engineer
    - test-engineer
    - docs-writer
  # cannot be deselected below this
  minimum:
    - sw-engineer
    - test-engineer
    - docs-writer
  max: 10
  # domain-signal -> suggested specialist. NOT a closed set: any <name>.md
  # present in agents_folder is selectable at A0, even if not listed here.
  signals:
    - specialist: hardware-engineer
      signals: [hardware, registers, gpio, timers, peripherals]
    - specialist: wireless-expert
      signals: [wireless, rf, ble, radio]
    - specialist: security-reviewer
      signals: [auth, secrets, crypto, network, input-parsing]
    - specialist: product-designer
      signals: [ui, ux, dashboard, screens]
    - specialist: ux-engineer
      signals: [ui, ux]
    - specialist: ui-engineer
      signals: [frontend, html, css, react, vue]
    - specialist: devops-specialist
      signals: [ci, cd, deployment, github-actions, docker, kubernetes]
    - specialist: bash-specialist
      signals: [shell, bash, posix-sh]
```

```python
# psc_engine/infrastructure/config.py
from __future__ import annotations
from dataclasses import dataclass, field
from pathlib import Path
import yaml  # PyYAML — managed by uv


@dataclass(frozen=True)
class RosterConfig:
    default: list[str]
    minimum: list[str]
    max: int
    signals: dict[str, list[str]] = field(default_factory=dict)


@dataclass(frozen=True)
class Config:
    agents_folder: Path
    workflows_folder: Path
    passports_folder: Path
    roster: RosterConfig


class ConfigReader:
    """Reads psc_engine.yaml once; cached for the process lifetime."""
    def __init__(self, path: Path):
        self._path = path

    def read(self) -> Config:
        with open(self._path, "r", encoding="utf-8") as f:
            raw = yaml.safe_load(f)
        signals = {s["specialist"]: s["signals"]
                   for s in raw.get("roster", {}).get("signals", [])}
        return Config(
            agents_folder=Path(raw["paths"]["agents_folder"]),
            workflows_folder=Path(raw["paths"]["workflows_folder"]),
            passports_folder=Path(raw["paths"]["passports_folder"]),
            roster=RosterConfig(
                default=raw["roster"]["default"],
                minimum=raw["roster"]["minimum"],
                max=raw["roster"]["max"],
                signals=signals,
            ),
        )


# psc_engine/domain/roster.py
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class RosterProposal:
    suggested: list[str]
    available: list[str]
    minimum: list[str]
    max: int


class RosterResolver:
    """Proposes a roster from domain signals; validates any user selection
    against the agents_folder (accepts new specialists by file existence)."""
    def __init__(self, agents_folder: Path, roster_cfg):
        self._folder = agents_folder
        self._cfg = roster_cfg

    def available_specialists(self) -> list[str]:
        # Any *.md in the agents folder is a valid specialist.
        return sorted(p.stem for p in self._folder.glob("*.md"))

    def propose(self, domain_signals: list[str]) -> RosterProposal:
        suggested = list(self._cfg.default)
        for specialist, sigs in self._cfg.signals.items():
            if specialist in suggested:
                continue
            if any(sig in domain_signals for sig in sigs):
                suggested.append(specialist)
        suggested = suggested[:self._cfg.max]
        for m in self._cfg.minimum:
            if m not in suggested:
                suggested.append(m)
        return RosterProposal(
            suggested=suggested,
            available=self.available_specialists(),
            minimum=list(self._cfg.minimum),
            max=self._cfg.max,
        )

    def validate_user_selection(self, selection: list[str]) -> tuple[bool, list[str]]:
        available = set(self.available_specialists())
        errors = []
        for s in selection:
            if s not in available:
                errors.append(f"unknown specialist '{s}' (no {s}.md in {self._folder})")
        for m in self._cfg.minimum:
            if m not in selection:
                errors.append(f"minimum specialist '{m}' not selected")
        if len(selection) > self._cfg.max:
            errors.append(f"too many specialists ({len(selection)} > {self._cfg.max})")
        return (not errors, errors)
```

**Design property:** dropping a new `bash-specialist.md` into `agents/` makes
it selectable with no code or config change — it appears in
`available_specialists()` and the user can add it at A0 even if no signal
rule mentions it.

---

## 3. The Python Library / CLI / MCP

### 3.1 Clean architecture + uv

```
psc_engine/
  domain/         # pure logic: states, transitions, aggregation, schemas, validation
  application/    # use-cases: advance_state, record_decision, run_gate (orchestrates domain)
  infrastructure/ # adapters: json_store, mcp_server, cli, mirror_writer
  tests/
pyproject.toml   # uv-managed; PyYAML dependency
```

- **`psc_engine`** (library) — pure logic with no I/O except via an injected
  store. Imported by the CLI and MCP server; never imported by agents.
- **`psc`** (CLI) — `psc workflow list|show|validate`, `psc passport
  show|validate|history|mirror`, `psc migrate`, `psc snapshot agents`,
  `psc new-ticket`. Used by humans / PM / CI; never by the Supreme Leader.
- **`psc-state`** (MCP server) — the surface the Supreme Leader calls
  (whitelisted `psc-state.*` tools). Wraps `psc_engine` + a JSON-file store.

**Environment:** `uv`-managed; single `pyproject.toml`; `uv sync`; `uv run`.
Phase 1 establishes layer boundaries; no adapter code until Phase 3.

### 3.2 API contract table (MCP / CLI share identical contracts)

| Tool | Inputs | Returns | Deterministic computation |
|------|--------|---------|----------------------------|
| `load_workflow` | `workflow_id`, `version` | workflow object | Reads `workflows/<id>/<version>.json`. Pure load. |
| `current_state` | `ticket_id` | `State` (with `__str__` + comparison) + `{phase, kind, is_decision_pending, pending_decision_schema, is_gate, retry_counts, review_round, parallel_progress}` | Reads passport; derives from `state.current` + workflow state def + `retries`/`parallel_progress`. |
| `possible_outcomes` | `ticket_id` | list of `{outcome_key, schema_ref, agent, instruction, expected_outcomes}` | Looks up current state's `transitions`; for `parallel` resolves `$roster` from passport; for `decision_required` returns the decision schema + routing preview. |
| `advance` | `ticket_id`, `outcome` (AgentOutcome) | `{new_state, next_agent, instruction, expected_outcomes, terminal, mirror_updated}` | (1) validate outcome against current state's `outcome_schema`; (2) if parallel, merge into `parallel_progress`, advance only when join satisfied; (3) compute target via `transitions[outcome.verdict]` or routing_rule for decision states; (4) update `step_log`/`outcomes`/`retries`/`loop_history`/`vars`; (5) regenerate Markdown mirror; (6) return next dispatch info. Rejects if schema invalid or precondition unmet (returns error list, no mutation). |
| `route_for_outcome` | `ticket_id`, `outcome` | `{target, agent, instruction, expected_outcomes, loop?, skip[]?}` | Pure routing: same computation as advance step 3, **without mutating**. Used to preview before committing. |
| `validate_passport` | `ticket_id` | `{valid: bool, errors: [...]}` | Invariants: every step in `step_log` has a stamp; every skip has justification; no `parallel_progress` pending when advancing; no missing-previous-step; retry budget not exceeded; mirror matches JSON. |
| `record_decision` | `ticket_id`, `state`, `decision_object` | `{new_state, ...}` | Validates decision against `decision_schemas[state]`, appends to `decisions`, computes target via `routing_rules[state]` from decision fields, advances. |
| `begin_gate` | `ticket_id`, `gate_state` | `{gate_id, tiers, retry_budget}` | Initialises retry tracking for that gate instance (idempotent). |
| `gate_fail` | `ticket_id`, `gate_state`, `tier`, `findings`, `root_cause` | `{retry_available: bool, next_state, retries_used, exhausted: bool}` | Increments `retries[gate][tier]`; if `>= budget` → `ESCALATE`; else → loop-back target + requires `root_cause` in RC-1..RC-5. |
| `aggregate_outcomes` | `ticket_id`, `state`, `outcomes[]` | composite outcome | Merges parallel outcomes per join rule (see §6). Does not advance. |
| `query` | `ticket_id`, `what` | result set | Read-only filters over passport (`step_log`, `gate_history`, `decision_log`, `pending`). |
| `migrate` | `ticket_id`, `target_version` | `{migrated: bool, incompatibilities[]}` | Only if compatible (same MAJOR or documented migration). In-flight migration is **not** auto; returns incompatibility list if breaking. |
| `propose_roster` | `ticket_id`, `domain_signals` | `RosterProposal` | Reads `agents_folder`; proposes defaults + signal-matched specialists. |
| `validate_roster` | `ticket_id`, `selection` | `{valid: bool, errors[]}` | Checks file existence in `agents_folder` + minimum + max. |

### 3.3 End-to-end test prototype (executable spec for §0.3)

This is the "fully functional by an agent or manually" proof — the library
is drivable end-to-end in Python, so the same path an agent takes (via MCP
or CLI) can be tested deterministically.

```python
# tests/test_e2e_happy_and_unhappy.py
import pytest
from psc_engine.application.workflow_service import WorkflowService
from psc_engine.domain.outcome import AgentOutcome
from psc_engine.infrastructure.config import ConfigReader
from psc_engine.infrastructure.json_store import JsonPassportStore


@pytest.fixture
def svc(tmp_path):
    cfg = ConfigReader(tmp_path / "psc_engine.yaml").read()
    store = JsonPassportStore(cfg.passports_folder)
    return WorkflowService(
        workflows_folder=cfg.workflows_folder,
        store=store,
        config=cfg,
    )


def _outcome(step, agent, verdict="pass", **extra):
    return AgentOutcome(
        step=step, agent=agent, verdict=verdict,
        confidence=100, findings=[], deliverables=[], flags=[],
        decision=None, gate_result=None, root_cause=None, **extra
    )


# --- HAPPY PATH: feature ticket A0 -> COMMIT ---
def test_happy_path_full_pipeline(svc):
    tkt = svc.new_ticket(
        workflow_id="psc-main", version="2.0.0",
        title="add BLE scan filter",
        request="drop advs without mfr service UUID",
        domain_signals=["wireless", "security"],
    )
    assert svc.current_state(tkt).state.name == "A0"

    # A0: user confirms roster (defaults + wireless/security proposed)
    proposal = svc.propose_roster(tkt)
    ok, _ = svc.validate_roster(tkt, proposal.suggested)
    assert ok
    svc.record_decision(tkt, "A0",
        {"roster": proposal.suggested, "rationale": "accepted proposal"})
    assert svc.current_state(tkt).state.name == "A1"
    assert svc.current_state(tkt).state.kind.value == "parallel"

    # A1: each specialist returns; advance doesn't fire until join satisfied
    for s in proposal.suggested:
        r = svc.advance(tkt, _outcome(f"A1#{s}", s, verdict="pass"))
        assert r.advanced == (s == proposal.suggested[-1])
    composite = svc.aggregate_outcomes(tkt, "A1")
    assert composite.verdict.value == "pass"
    svc.advance(tkt, composite)
    assert svc.current_state(tkt).state.name == "A2"

    # A2: primary + challenger (challenger disagrees -> needs_decision)
    svc.advance(tkt, _outcome("A2#primary", "sw-engineer", "pass"))
    svc.advance(tkt, _outcome("A2#challenger", "code-architect-challenger",
        "needs_decision", disagreements=["D1"], confidence=72))
    svc.advance(tkt, svc.aggregate_outcomes(tkt, "A2"))
    assert svc.current_state(tkt).state.name == "A2b"

    # A2b -> A2c (decision_required, user dispositions)
    svc.advance(tkt, _outcome("A2b", "pm", "pass"))
    assert svc.current_state(tkt).is_decision_pending
    svc.record_decision(tkt, "A2c",
        {"findings": [{"finding_id": "F1", "disposition": "ACCEPT"}]})
    assert svc.current_state(tkt).state.name == "A2a"   # ACCEPT -> ADR

    # A2a -> A3 gate
    svc.advance(tkt, _outcome("A2a", "code-architect", "pass",
        deliverables=[{"type": "adr", "ref": "docs/adr/0001.md"}]))
    assert svc.current_state(tkt).state.name == "A3"
    assert svc.current_state(tkt).state.kind.value == "gate"

    # A3 gate pass
    svc.begin_gate(tkt, "A3")
    svc.advance(tkt, _outcome("A3", "sw-engineer", "pass",
        gate_result={"tier": "T3", "result": "pass"},
        gate_result_t_arch={"result": "pass"}))
    assert svc.current_state(tkt).state.name == "B1"

    # ... B1 -> B2 -> B2a (pass) -> B3 -> B3a (pass) -> C0 -> C1 -> C2 -> C3 -> C4 ...
    # (elided for brevity; same pattern)
    svc.record_decision(tkt, "C4",
        {"decision": "complete", "rationale": "all green"})
    assert svc.current_state(tkt).state.name == "CR1"
    # CR1 -> CR2 (accept) -> CR3 -> COMMIT
    svc.advance(tkt, _outcome("CR1", "code-reviewer", "pass"))
    svc.begin_gate(tkt, "CR2")
    svc.advance(tkt, _outcome("CR2", "code-reviewer", "pass",
        gate_result={"verdict": "APPROVED",
                     "blocking_findings_resolved": True}))
    svc.advance(tkt, _outcome("CR3", "code-reviewer", "accepted"))
    assert svc.current_state(tkt).state.name == "COMMIT"
    assert svc.current_state(tkt).state.kind.value == "terminal"


# --- UNHAPPY PATHS ---
def test_unknown_ticket_returns_error(svc):
    r = svc.current_state("TKT-9999")
    assert r.error == "ticket_not_found"


def test_ambiguous_instruction_loops_at_a0(svc):
    tkt = svc.new_ticket("psc-main", "2.0.0", "fix the thing",
                          "fix the thing", [])
    svc.advance(tkt, _outcome("A0", "supreme-leader", "needs_info"))
    assert svc.current_state(tkt).state.name == "A0"   # stays, routes to pm


def test_passport_missing(svc, tmp_path):
    tkt = svc.new_ticket("psc-main", "2.0.0", "x", "x", [])
    (tmp_path / f"passports/{tkt}.json").unlink()
    r = svc.current_state(tkt)
    assert r.error == "passport_missing"


def test_advance_rejects_when_parallel_pending(svc):
    tkt = svc.new_ticket("psc-main", "2.0.0", "x", "x", ["security"])
    svc.record_decision(tkt, "A0",
        {"roster": ["sw-engineer", "test-engineer", "docs-writer",
                     "security-reviewer"], "rationale": ""})
    # only 1 of 4 returns
    r = svc.advance(tkt, _outcome("A1#sw-engineer", "sw-engineer", "pass"))
    assert r.advanced is False
    assert "parallel_pending" in r.errors


def test_gate_fail_then_exhaust_then_escalate(svc):
    tkt = svc.new_ticket("psc-main", "2.0.0", "x", "x", [])
    # ... walk to A3 ...
    svc.begin_gate(tkt, "A3")
    for attempt in range(3):
        r = svc.gate_fail(tkt, "A3", "T3", [{"id": "G1"}], root_cause="RC-2")
        assert r.retry_available == (attempt < 2)
    assert svc.current_state(tkt).state.name == "ESCALATE"
    assert svc.current_state(tkt).state.kind.value == "terminal"


def test_decision_never_arrives_stays_put(svc):
    tkt = svc.new_ticket("psc-main", "2.0.0", "x", "x", [])
    # ... walk to A2c ...
    assert svc.current_state(tkt).is_decision_pending
    # call current_state repeatedly; never auto-advances
    for _ in range(5):
        assert svc.current_state(tkt).state.name == "A2c"


def test_new_specialist_accepted_by_file_existence(svc, tmp_path):
    # drop a new agent file; it becomes selectable without code/config change
    (tmp_path / "agents" / "bash-specialist.md").write_text("# bash specialist")
    proposal = svc.propose_roster_for_signals(["shell"])
    assert "bash-specialist" in proposal.available
    ok, _ = svc.validate_roster(tkt=None,
        selection=["sw-engineer", "test-engineer", "docs-writer",
                   "bash-specialist"])
    assert ok


def test_state_comparison_forward_progress_dag(svc):
    tkt = svc.new_ticket("psc-main", "2.0.0", "x", "x", [])
    A0 = svc.current_state(tkt).state
    # walk to A3 ...
    A3 = svc.current_state(tkt).state
    assert A0 < A3
    assert A3 > A0
    assert not (A0 < A0)
    # the back-edge A3 -> A2a (loop) is excluded from the comparison DAG
    A2a = svc.registry["A2a"]
    assert A2a < A3
    assert not (A3 < A2a)
```

**Usage by logger:**

```python
import logging
logging.info(f"current state is {A0}")
# -> "current state is A0 (Task Definition & Domain Classification)"
```

---

## 4. Process Flow

### 4.1 Numbered list (instruction arrives at the Supreme Leader)

1. Supreme Leader receives an instruction (user message or subagent return).
2. **Has task?** Parse for a `TKT-####` reference.
   - None + new request → dispatch PM to create ticket (`psc new-ticket`);
     PM snapshots agents + workflow, writes `passports/<TKT>.json`
     (state=A0) + mirror.
   - References a missing ticket → unhappy path (§4.4 E2).
3. `load_workflow(workflow_id, workflow_version)` from the passport's
   version pins.
4. `current_state(ticket_id)` → `State` object (with `__str__` + comparison)
   + current state, kind, pending flags, retry counts, parallel progress.
5. **Decision pending?** If `is_decision_pending` → do not dispatch; the
   decision must be supplied (by user or PM). Wait / request decision.
6. `possible_outcomes(ticket_id)` → list of outcome keys + schemas + agent
   + instruction + expected_outcomes.
7. **Parallel?** If `kind=parallel` → dispatch each specialist subagent in
   parallel with a dispatch envelope containing the outcome schema.
8. **Gate?** If `kind=gate` → run the gate tiers per `gate_config`; collect
   `gate_result` into an outcome; call `advance` or `gate_fail`.
9. **Task?** Dispatch the single bound agent with instruction + outcome
   schema; await outcome JSON.
10. Agent returns AgentOutcome. Supreme Leader calls
    `advance(ticket_id, outcome)`.
11. `advance` validates against schema, records, computes next state,
    regenerates mirror, returns
    `{new_state, next_agent, instruction, expected_outcomes, terminal}`.
12. If `terminal` (COMMIT/ESCALATE/DEFERRED) → stop, report to user. Else
    loop to step 4.

### 4.2 Mermaid flowchart

```mermaid
flowchart TD
    S([Instruction arrives]) --> H{Has TKT ref?}
    H -- no, new request --> NT[PM creates ticket via psc new-ticket, snapshot agents, write passport JSON+mirror]
    H -- ref missing --> UE1[Unhappy: unknown ticket]
    H -- yes --> LW[load_workflow from passport pins]
    NT --> LW
    LW --> CS[current_state via psc-state MCP / psc CLI]
    CS --> DP{decision_pending?}
    DP -- yes --> WD[Wait / request decision]
    WD --> RD[record_decision]
    RD --> CS
    DP -- no --> PO[possible_outcomes]
    PO --> KP{kind?}
    KP -- parallel --> PAR[dispatch fan-out in parallel]
    KP -- gate --> GATE[run gate tiers]
    KP -- task --> TASK[dispatch single agent]
    KP -- decision_required --> DEC[request decision]
    PAR --> AGG[aggregate_outcomes]
    GATE --> GR{gate pass?}
    GR -- pass --> ADV
    GR -- fail --> GF[gate_fail + RC correction]
    GF --> RETRY{retries left?}
    RETRY -- yes --> PAR
    RETRY -- no --> ESC[ESCALATE]
    TASK --> AO[AgentOutcome returned]
    AGG --> AO
    AO --> ADV[advance: validate schema, record, compute next, regenerate mirror]
    DEC --> AO
    ADV --> TERM{terminal?}
    TERM -- yes --> END([COMMIT / ESCALATE / DEFERRED])
    TERM -- no --> CS
```

### 4.3 Happy path — clean new feature

1. User issues request → Supreme Leader sees no `TKT-####` → dispatches PM
   to create ticket; PM runs `psc new-ticket --workflow=psc-main`, snapshots
   agents + workflow into the ticket dir, writes `passports/TKT-0001.json`
   (state=A0) + mirror.
2. `current_state` → A0 (task, agent=supreme-leader). Supreme Leader
   classifies domain → proposes roster via `propose_roster` (reads
   `agents_folder`); user confirms via checklist
   (`decision.roster_confirmation`).
3. `record_decision` stores roster → `advance` → A1 (parallel,
   `fan_out=$roster`). Dispatches specialists in parallel, each with the
   outcome schema.
4. Each specialist returns an AgentOutcome; `advance` marks it returned in
   `parallel_progress`; when `pending==[]`, `aggregate_outcomes` builds the
   composite; `advance` → A2.
5. A2 dual-model (primary + challenger on glm-5.1) → A2b (PM synthesis) →
   A2c (decision_required, machine halts).
6. User dispositions findings → `record_decision` → routing rule picks A2a
   (ADR) or skips to A3.
7. A3 gate (T3+T-ARCH) → B1 → B2/B2a per unit (loops with RC corrections) →
   B3a → C0 → C1 → C2 → C3 → C4 (decision_required) → PM picks `complete` →
   CR1 → CR2 → CR3 → COMMIT.
8. `advance` returns `terminal=COMMIT`. Supreme Leader reports completion.
   Mirror committed.

### 4.4 Unhappy paths (entry)

| Case | Trigger | State machine returns | Supreme Leader action |
|------|---------|-----------------------|-----------------------|
| **E2 Unknown ticket** | Instruction cites `TKT-0099` that doesn't exist | `{error:"ticket_not_found"}` | Halt; ask user to confirm new vs typo; PM creates if new |
| **E3 Ambiguous instruction** | No TKT ref + request unclear | A0 stays; outcome `verdict:needs_clarification` → next_agent=pm | PM asks user; loops at A0 until clarified |
| **E4 Passport missing** | TKT exists, JSON absent | `{error:"passport_missing"}` | Halt; PM restores from git/mirror or recreates (recorded decision); no work proceeds |
| **E5 Prior step unstamped** | `validate_passport` finds a missing stamp or non-empty `pending` at advance time | `advance` returns `{valid:false, errors:["step_unstamped:A1","parallel_pending:test"]}` — **no mutation** | Re-dispatch the missing specialist or stamp; state unchanged |
| **E6 Gate exhausted** | `gate_fail` with `retries >= budget` | `{exhausted:true, next_state:ESCALATE, terminal:true}` | Report to user with gate history + RC corrections log |
| **E7 Decision never arrives** | `is_decision_pending` and no response | State unchanged; only the decision schema is returned | Re-request; after timeout PM may route to `DEFERRED` terminal via a recorded decision |

---

## 5. Sequence Diagram — one full stage transition

```mermaid
sequenceDiagram
    autonumber
    participant SL as Supreme Leader
    participant MCP as psc-state (MCP / CLI)
    participant Spec as Specialists (parallel)
    participant Ch as Challenger (glm-5.1)
    participant U as User / PM
    participant F as passport.json + mirror.md

    SL->>MCP: current_state(TKT-0001)
    MCP-->>SL: {state:A1, kind:parallel, roster:[security,test]}
    SL->>MCP: possible_outcomes(TKT-0001)
    MCP-->>SL: [{agent:security,schema:outcome.specialist_review}, {agent:test,...}]

    par fan-out
        SL->>Spec: dispatch security (envelope + schema)
        Spec-->>SL: AgentOutcome{verdict:pass, findings:[F1]}
    and
        SL->>Spec: dispatch test
        Spec-->>SL: AgentOutcome{verdict:pass}
    end

    SL->>MCP: aggregate_outcomes(TKT-0001, A1, [sec, test])
    MCP-->>SL: composite{verdict:pass, findings:[F1]}
    SL->>MCP: advance(TKT-0001, composite)
    MCP->>F: write JSON + regenerate mirror
    MCP-->>SL: {new_state:A2, next:supreme-leader}

    par dual-model challenge
        SL->>Spec: dispatch primary
        Spec-->>SL: AgentOutcome{verdict:pass}
    and
        SL->>Ch: dispatch challenger
        Ch-->>SL: AgentOutcome{disagreements:[D1], confidence:72}
    end

    SL->>MCP: advance(TKT-0001, challenge_composite)
    MCP-->>SL: {new_state:A2c, is_decision_pending:true}
    Note over SL,U: machine halts - decision required
    U-->>SL: decision{findings:[{F1,ACCEPT}]}
    SL->>MCP: record_decision(TKT-0001, A2c, decision)
    MCP-->>SL: {new_state:A2a, instruction:write ADR}
    SL->>Spec: dispatch code-architect (ADR)
    Spec-->>SL: AgentOutcome{deliverables:[adr]}
    SL->>MCP: advance(TKT-0001, adr_outcome)
    MCP-->>SL: {new_state:A3, kind:gate}

    SL->>MCP: begin_gate(TKT-0001, A3)
    MCP-->>SL: {tiers:[T3,T-ARCH], budget:{T3:3,T-ARCH:3}}
    SL->>Spec: run T3 + T-ARCH
    Spec-->>SL: gate_result{tier:T3, pass:false, findings:[G1]}

    alt retries left
        SL->>MCP: gate_fail(TKT-0001, A3, T3, [G1], RC-2)
        MCP-->>SL: {retry_available:true, next:A2a, retries_used:1}
        Note over SL: re-dispatch A2a to fix G1
    else exhausted
        SL->>MCP: gate_fail(..., RC-x)
        MCP-->>SL: {exhausted:true, terminal:ESCALATE}
    end
```

---

## 6. Parallel Flows & Aggregation

A `parallel` state declares `fan_out` (static list or `$roster` resolved
from a prior outcome) and a `join` rule (`all` or `quorum:N`). On entering a
parallel state, `advance` writes:

```jsonc
"parallel_progress": {
  "expected": ["security","test","design"],
  "returned": [],
  "pending":  ["security","test","design"],
  "join": "all"
}
```

Each specialist is dispatched with a **per-specialist step ID** (e.g.
`A1#security`) and the outcome schema. When an agent returns, `advance`
marks it returned, moves it from `pending` to `returned`, and stores the
outcome keyed by `step+agent`. **The state does not advance until `join` is
satisfied.**

- For `join:all`, advance when `pending == []`.
- For `join:quorum:N`, advance when `len(returned) >= N`.

A crashed specialist leaves a `pending` entry; the Supreme Leader re-dispatches
that specific step ID, not the whole fan-out. `advance` refuses to accept an
outcome for a specialist not in `expected`, and refuses to advance while
`pending` is non-empty.

### Aggregation rule (when join satisfied, Supreme Leader calls `aggregate_outcomes`)

- **verdict**:
  - A1/specialist review: `pass` if all returned `pass`; `fail` if any
    `fail`; `needs_decision` if any `needs_info`.
  - C2/approval: `all_approved` if every specialist `verdict==approved`;
    `any_rejected` if any `verdict==request_changes` or `fail`.
  - A2/C1 challenge: `pass` if primary pass AND challenger has no
    `blocker`-severity disagreements; `needs_decision` if disagreements
    exist (routes to A2b synthesis).
- **findings**: union of all `findings`, deduplicated by
  `(category, message)` hash, retaining the highest severity.
- **agreements/disagreements/missing_considerations/recommendations**: merged
  from challenger outcomes only.
- **confidence**: min across returned outcomes (the weakest link governs).
- **flags**: union.
- **deliverables**: union.

The composite is stored as `outcomes[state]` and the state advances on the
composite's `verdict`. **The orchestrator never writes the passport directly**
— it always hands outcomes to `advance`, which writes. The aggregation is
the only place synthesis logic lives; it is library code, not agent prose.

---

## 7. Deterministic vs Judgement — exhaustive transition table

`loop?` column marks back-edges (excluded from the comparison DAG).

| # | Transition | Class | loop? | Routed by |
|---|-----------|-------|-------|-----------|
| 1 | A0 → A1 (classified) | DETERMINISTIC (transition) / JUDGEMENT (roster field) | no | outcome.verdict + decision.roster |
| 2 | A0 → A0 (needs_clarification) | DETERMINISTIC | yes | outcome.verdict=needs_info |
| 3 | A1 → A2 (reviews_complete) | DETERMINISTIC | no | join:all satisfied → composite verdict |
| 4 | A2 → A2b (challenge_complete) | DETERMINISTIC | no | join:all on primary+challenger |
| 5 | A2b → A2c (synthesized) | DETERMINISTIC | no | PM synthesis outcome.verdict |
| 6 | A2c → A2a / skip→A3 | **JUDGEMENT** | no | decision.user_disposition findings[].disposition |
| 7 | A2a → A3 (adr_written) | DETERMINISTIC | no | outcome.verdict |
| 8 | A3 → B1 (pass) | DETERMINISTIC | no | gate all tiers pass |
| 9 | A3 → A2a (fail) | DETERMINISTIC (routing) / **JUDGEMENT** (RC correction) | yes | tier fail + RC classification |
| 10 | A3 → ESCALATE (exhausted) | DETERMINISTIC | no | retries ≥ budget |
| 11 | B1 → B2 (planned) | DETERMINISTIC | no | outcome.verdict |
| 12 | B2 → B2a (unit_applied) | DETERMINISTIC | no | outcome.verdict |
| 13 | B2 → B3 (units_complete) | DETERMINISTIC | no | plan units exhausted |
| 14 | B2a → B2 (pass, next unit) | DETERMINISTIC | no | gate pass |
| 15 | B2a → B2 (fail, rework) | DETERMINISTIC / **JUDGEMENT** (RC) | yes | tier fail |
| 16 | B2a → ESCALATE (exhausted) | DETERMINISTIC | no | retries ≥ budget |
| 17 | B3 → B3a (validated) | DETERMINISTIC | no | outcome.verdict |
| 18 | B3a → C0 (pass) | DETERMINISTIC | no | gate pass |
| 19 | B3a → B1 (fail) | DETERMINISTIC / **JUDGEMENT** (RC) | yes | tier fail |
| 20 | B3a → ESCALATE (exhausted) | DETERMINISTIC | no | retries ≥ budget |
| 21 | C0 → C1 (done) | DETERMINISTIC | no | T1 re-run outcome |
| 22 | C1 → C2 (challenge_complete) | DETERMINISTIC | no | join:all |
| 23 | C2 → C3 (all_approved) | DETERMINISTIC | no | composite verdict |
| 24 | C2 → CR1 (any_rejected) | DETERMINISTIC | no | composite verdict |
| 25 | C3 → C4 (pass) | DETERMINISTIC | no | gate pass |
| 26 | C3 → B1 (fail) | DETERMINISTIC / **JUDGEMENT** (RC) | yes | tier fail |
| 27 | C3 → ESCALATE (exhausted) | DETERMINISTIC | no | retries ≥ budget |
| 28 | C4 → CR1 / B1 / ESCALATE / DEFERRED | **JUDGEMENT** | varies | decision.c4_completion.decision field |
| 29 | CR1 → CR2 (reviewed) | DETERMINISTIC | no | outcome.verdict |
| 30 | CR2 → CR3 (accept) | DETERMINISTIC | no | gate accept |
| 31 | CR2 → B2 (request_changes) | DETERMINISTIC / **JUDGEMENT** (RC) | yes | round++ + reviewer findings |
| 32 | CR2 → ESCALATE (rounds exhausted) | DETERMINISTIC | no | review_round ≥ max_review_rounds |
| 33 | CR3 → COMMIT (accepted) | DETERMINISTIC | no | outcome.verdict |
| 34 | COMMIT / ESCALATE / DEFERRED | terminal | — | — |

**Summary:** five genuine judgement points — A0 roster confirmation, A2c user
disposition, C4 PM completion decision, gate-fail root-cause correction
(RC-1..RC-5), and A0 clarification loop. Everything else the library computes
from outcomes/decisions/counters. The judgement points are all recorded as
structured objects, so the *routing* that follows them is still deterministic.

---

## 8. Adhoc Workflow Variant — `psc-adhoc`

A **separate workflow definition** (version-pinned independently). Not a
branch inside `psc-main`.

```jsonc
{
  "workflow_id": "psc-adhoc",
  "version": "1.0.0",
  "start_at": "A0L",
  "phases": [
    {"id":"A","ord":0},
    {"id":"B","ord":1},
    {"id":"C","ord":2},
    {"id":"CR","ord":3}
  ],
  "states": {
    "A0L": {
      "name":"A0L","title":"Task Definition (lightweight)",
      "phase":"A","step":0,"kind":"task","agent":"supreme-leader",
      "transitions": {
        "classified":          {"target":"A1L"},
        "needs_clarification": {"target":"A0L","loop":true}
      }
    },
    "A1L": {
      "name":"A1L","title":"Single Reviewer",
      "phase":"A","step":1,"kind":"task","agent":"supreme-leader",
      "transitions": {"reviewed":{"target":"A2L"}}
    },
    "A2L": {
      "name":"A2L","title":"Lightweight Gate",
      "phase":"A","step":2,"kind":"gate","agent":"supreme-leader",
      "gate_config":"gate.A2L",
      "transitions": {
        "pass":      {"target":"B1"},
        "fail":      {"target":"A1L","loop":true},
        "exhausted": {"target":"ESCALATE"}
      },
      "retry": [{"error_equals":["gate_fail"],"max_attempts":2}]
    },
    "B1": {
      "name":"B1","title":"PLAN",
      "phase":"B","step":0,"kind":"task","agent":"code-architect",
      "transitions": {"planned":{"target":"B2"}}
    },
    "B2": {
      "name":"B2","title":"APPLY (per unit)",
      "phase":"B","step":1,"kind":"task","agent":"code-architect",
      "transitions": {
        "unit_applied":   {"target":"B2a"},
        "units_complete": {"target":"B3"}
      }
    },
    "B2a": {
      "name":"B2a","title":"B-UNIT-GATE (T1 only)",
      "phase":"B","step":2,"kind":"gate","agent":"supreme-leader",
      "gate_config":"gate.B2aL",
      "transitions": {
        "pass":      {"target":"B2"},
        "fail":      {"target":"B2","loop":true},
        "exhausted": {"target":"ESCALATE"}
      },
      "retry": [{"error_equals":["gate_fail"],"max_attempts":2}]
    },
    "B3": {
      "name":"B3","title":"VALIDATE",
      "phase":"B","step":3,"kind":"task","agent":"code-architect",
      "transitions": {"validated":{"target":"B3a"}}
    },
    "B3a": {
      "name":"B3a","title":"B-FINAL-GATE (T1 only)",
      "phase":"B","step":4,"kind":"gate","agent":"supreme-leader",
      "gate_config":"gate.B3aL",
      "transitions": {
        "pass":      {"target":"C0"},
        "fail":      {"target":"B1","loop":true},
        "exhausted": {"target":"ESCALATE"}
      },
      "retry": [{"error_equals":["gate_fail"],"max_attempts":2}]
    },
    "C0": {
      "name":"C0","title":"T1 Re-run",
      "phase":"C","step":0,"kind":"task","agent":"supreme-leader",
      "transitions": {"done":{"target":"C1L"}}
    },
    "C1L": {
      "name":"C1L","title":"Lightweight Verification",
      "phase":"C","step":1,"kind":"task","agent":"supreme-leader",
      "transitions": {"reviewed":{"target":"C2L"}}
    },
    "C2L": {
      "name":"C2L","title":"Single Approval",
      "phase":"C","step":2,"kind":"task","agent":"supreme-leader",
      "transitions": {
        "approved": {"target":"C3L"},
        "rejected": {"target":"CR1"}
      }
    },
    "C3L": {
      "name":"C3L","title":"C-GATE (T1 only)",
      "phase":"C","step":3,"kind":"gate","agent":"supreme-leader",
      "gate_config":"gate.C3L",
      "transitions": {
        "pass":      {"target":"CR1"},
        "fail":      {"target":"B1","loop":true},
        "exhausted": {"target":"ESCALATE"}
      },
      "retry": [{"error_equals":["gate_fail"],"max_attempts":2}]
    },
    "CR1": {
      "name":"CR1","title":"Code Review Round",
      "phase":"CR","step":0,"kind":"task","agent":"code-reviewer",
      "transitions": {"reviewed":{"target":"CR2"}}
    },
    "CR2": {
      "name":"CR2","title":"CR-GATE",
      "phase":"CR","step":1,"kind":"gate","agent":"supreme-leader",
      "gate_config":"gate.CR2",
      "transitions": {
        "accept":          {"target":"CR3"},
        "request_changes": {"target":"B2","loop":true},
        "exhausted":       {"target":"ESCALATE"}
      },
      "retry": [{"error_equals":["gate_fail"],"max_attempts":3}]
    },
    "CR3": {
      "name":"CR3","title":"Review Acceptance",
      "phase":"CR","step":2,"kind":"task","agent":"code-reviewer",
      "transitions": {"accepted":{"target":"COMMIT"}}
    },
    "COMMIT":   {"name":"COMMIT","title":"Commit","phase":"CR","step":3,"kind":"terminal","agent":""},
    "ESCALATE": {"name":"ESCALATE","title":"Escalate","phase":"CR","step":4,"kind":"terminal","agent":""}
  },
  "gate_configs": {
    "gate.A2L":  {"tiers":["T-ARCH"],"retry_budget":{"T-ARCH":2}},
    "gate.B2aL": {"tiers":["T1"],"retry_budget":{"T1":2}},
    "gate.B3aL": {"tiers":["T1"],"retry_budget":{"T1":2}},
    "gate.C3L":  {"tiers":["T1"],"retry_budget":{"T1":2}},
    "gate.CR2":  {"tiers":["T3"],"retry_budget":{"T3":3},"round_budget":3}
  },
  "retry_policy": {"max_per_tier":2,"on_exhaust":"ESCALATE"},
  "max_review_rounds": 3
}
```

### What is skipped vs kept

- **Skipped/lightened:** A1 parallel fan-out → single reviewer; A2 dual-model
  challenge → dropped; A2c user-disposition gate → PM/supreme-leader decides
  inline; T2/T3 deep tiers → T1 only (findings still collected
  opportunistically but not gating); retry budgets halved (2 not 3); review
  rounds 3 not 5.
- **Mandatory, never skippable:**
  1. **A0L task definition** — an ambiguous adhoc task is more dangerous than
     a structured one because there's less downstream scrutiny.
  2. **T1 mechanical gate** at B2a, B3a, C3L — a non-building change is
     always wrong regardless of task size. T1 is the cheapest, highest-signal
     check.
  3. **B build + B3a gate** — no change ships unvalidated.
  4. **CR code review** — even small changes get a reviewer pass (reduced
     rounds, not optional).

**Justification:** adhoc tasks are bounded in scope (one unit, one concern).
The cost of dual-model challenge + full T2/T3 + 6-way C4 + 5 review rounds
is not justified; the risk of skipping T1/build/review is. The adhoc workflow
is a *reduced-confidence* path, not a *no-confidence* path — it accepts
higher residual risk in exchange for velocity, but never zero confidence.

---

## 9. Implementation Phasing

| Phase | Build | Shippable test | Depends on |
|-------|-------|----------------|------------|
| **1 — Schemas + library core** | JSON Schemas (workflow, passport, AgentOutcome, decisions). `psc_engine` domain layer: `State`, `StateRegistry`, `Context`, `ConfigReader`, `RosterResolver`. `psc` CLI for `validate`. `pyproject.toml` (uv) + PyYAML dep. | Schema validation + invariants green on fixtures | — |
| **2 — State machine + gates + decisions** (riskiest) | `advance`, `route_for_outcome`, `begin_gate`, `gate_fail` (retry vs loop-back), `record_decision` + routing rules, `aggregate_outcomes` + join, `migrate`. Application layer use-cases. | Exhaustive transition-table tests (every row of §7) + property tests (retries never exceed budget; parallel never advances with pending; decision state never auto-advances; mirror matches JSON; state comparison via forward-progress DAG) | Phase 1 |
| **3 — MCP server + CLI + snapshots + mirror** | `psc-state` MCP server (whitelisted `psc-state.*`); `psc` CLI subcommands; agent/workflow snapshotting at A0; Markdown mirror + drift CI. Wire Supreme Leader MCP whitelist (or relax `bash` for CLI — §11.1). | Manual A0→A1 dispatch round-trip through MCP / CLI | Phase 2 |
| **4 — Parallel aggregation wiring** | Real A1/C1/C2 fan-out; dispatch envelope generator; `parallel_progress` recovery (re-dispatch a single crashed specialist by step ID) | 3-specialist fan-out where one fails completes only after re-dispatch | Phase 3 |
| **5 — Adhoc workflow + lifecycle** | `psc-adhoc` workflow definition + tests; `migrate` compatibility; DEPRECATED lifecycle (max 2 MAJOR, 90-day grace) | `psc-main` ticket cannot migrate across MAJOR without incompatibility report; `psc-adhoc` runs end-to-end | Phases 1–4 |

**Risk ranking:** Phase 2 (state correctness) ≫ Phase 3 (mirror/MCP boundary)
> Phase 4 (parallel recovery) > Phase 5 (lifecycle) > Phase 1 (schemas). Phase
2 is where a subtle off-by-one in retry accounting or a missed join condition
silently corrupts tickets — it gets the most test investment.

---

## 10. Risks and Opportunities

### Three biggest risks

1. **The Supreme Leader's permission block forbids the call path the
   original brief assumes.** Resolved by designing both surfaces (MCP +
   CLI) and deferring the choice to runtime (§11.1). No agent overhead
   either way.
2. **Per-ticket versioning without a deprecation policy is a slow-burning
   liability.** Resolved by SemVer + max 2 concurrent MAJOR + 90-day grace +
   force-migrate-or-close + agent/workflow snapshots per ticket.
3. **Markdown→JSON migration destroys the human-review audit trail.**
   Resolved by JSON authoritative + auto-generated Markdown mirror + CI drift
   check.

### Three biggest opportunities

1. **Deterministic, unit-testable routing.** Today routing correctness lives
   in 2,000+ lines of prose an LLM must obey. The JSON workflow + `advance`
   makes routing a compile-time artefact, not a prompt-time hope.
2. **Cross-ticket analytics.** Structured per-ticket state answers "which
   tier fails most?", "which specialist issues the most REJECTEDs?",
   "median retry count at B-UNIT-GATE?" — impossible today without grepping
   hundreds of markdown files.
3. **Adhoc routing without bypass.** A defined `psc-adhoc` workflow enforces
   the No-Hotfix-Bypass rule structurally rather than rhetorically.

---

## 11. Open Questions for Review

These are the loose ends to resolve before locking the design:

1. **MCP vs CLI** — confirm MCP is the boundary (preserves `bash:deny`), or
   relax `bash:allow` scoped to `psc_engine` calls (simpler, no MCP infra).
   Both surfaces are designed; the choice is runtime.
2. **Adhoc heuristic** — what's the precise rule the Supreme Leader uses to
   pick `psc-adhoc` vs `psc-main` at A0? (Single-concern? Single-file-class?
   No architecture impact? All three?) Needs a concrete decision procedure,
   not a vague heuristic.
3. **Decision timeout policy** — when a `decision_required` state never
   receives a decision (E7), after how long does the PM route to `DEFERRED`?
   Is it a wall-clock timeout or an explicit user/PM action?
4. **Agent snapshot granularity** — snapshot *all* agent files, or only the
   ones the workflow references (the specialist roster)? Snapshotting all is
   simpler; snapshotting only referenced ones is leaner.
5. **Mirror commit cadence** — is the Markdown mirror committed on every
   `advance()`, or only at phase boundaries / gate passes? Committing every
   advance is noisy but accurate; committing at boundaries is cleaner but can
   drift from JSON mid-phase.
6. **Roster proposal vs confirmation split** — does the Supreme Leader
   propose the roster and the user confirm (two-step, current design), or
   does the user select from scratch (one-step, simpler but loses the
   signal-driven default)?

---

## 12. References

Authoritative sources fetched during research (§1.7, §1.8, §2.4, §2.5):

| Source | URL | Status |
|--------|-----|--------|
| Amazon States Language spec | https://states-language.net/spec.html | Fetched in full — foundational for the LTS graph model, `Choice` rules, `Parallel` join, `Retry` blocks, Context Object |
| AWS Step Functions ASL overview | https://docs.aws.amazon.com/step-functions/latest/dg/concepts-amazon-states-language.html | Fetched |
| AWS Step Functions Context Object | https://docs.aws.amazon.com/step-functions/latest/dg/input-output-contextobject.html | Fetched — `State.RetryCount` precedent for `meta.entry_count`/`meta.attempt` |
| AWS Step Functions workflow variables | https://docs.aws.amazon.com/step-functions/latest/dg/workflow-variables.html | Fetched — scoped variables precedent for `vars` blackboard |
| OMG BPMN 2.0.2 spec | https://www.omg.org/spec/BPMN/2.0.2/ | Landing fetched; full PDF requires OMG account — vocabulary (Task, Gateway, User Task, sequence flow) |
| Camunda Gateways | https://docs.camunda.io/docs/8.9/components/modeler/bpmn/gateways/ | Fetched — XOR/AND/OR gateway semantics |
| Camunda User Tasks | https://docs.camunda.io/docs/8.9/components/modeler/bpmn/user-tasks/ | Fetched — User Task (block + form + resume) precedent for `decision_required` |
| Camunda Variables | https://docs.camunda.io/docs/components/concepts/variables.md | Fetched — scoped variables precedent |
| Camunda Process Definition Versioning | https://docs.camunda.io/docs/components/best-practices/operations/versioning-process-definitions/ | Fetched — snapshot-per-instance consensus |
| Temporal Workflows | https://docs.temporal.io/workflows | Fetched — replay-from-history model |
| Temporal Event History | https://docs.temporal.io/workflow-execution/event | Fetched — 51,200-event cap + Continue-As-New |
| Temporal Worker Versioning | https://docs.temporal.io/production-deployment/worker-deployments/worker-versioning | Fetched — Pinned = snapshot-per-instance |
| Temporal Python Versioning | https://docs.temporal.io/develop/python/workflows/versioning | Fetched — patching semantics |
| Van der Aalst, "Application of Petri Nets to Workflow Management" (1998) | DOI 10.1142/S0218126698000033 | Cited by canonical bibliographic reference (PDF unreachable) — WF-net soundness |

---

_End of design document. Decisions marked [LOCKED] are confirmed; [TENTATIVE]
and §11 open questions are pending review._