# PSC Workflow Engine — Design Document Set

> **Status:** DESIGN COMPLETE. Three review rounds resolved. Design is ready
> for Phase 1 implementation.
> **Branch:** `feature/workflow-engine`.
> **Owner:** Supreme Leader (orchestrating); design synthesised from parallel
> agent exploration + critique + authoritative research on workflow semantics.

---

## How to read this document set

This is a multi-file design document. Read in order:

| File | Content | Audience |
|------|---------|---------|
| [01-rationale-philosophy.md](01-rationale-philosophy.md) | Purpose, philosophy of approach, design agnosticism principle | All readers — start here |
| [02-high-level-design.md](02-high-level-design.md) | Workflow semantics, ontology, architecture decisions, entity definitions, logical data model | Architects, reviewers |
| [03-data-model.md](03-data-model.md) | Physical data model, JSON schemas, data dictionary, PSC data structures, storage protocols, JSONPath, data classification & redaction, config | Developers, data modellers |
| [04-low-level-design.md](04-low-level-design.md) | **Application lifecycle (§4.0)**, process flow, sequence diagrams, parallel flows, transition table, persistence, multi-session safety, step writing, lifecycle hooks, cancel, OpenCode hooks research, API contracts, e2e test, implementation phasing | Developers |
| [05-ui-ux.md](05-ui-ux.md) | UI views, API integration, user flow diagrams | Designers, frontend developers |
| [06-references.md](06-references.md) | Academic-style references (50 citations) | All — for verification |
| [08-testing-strategy.md](08-testing-strategy.md) | Testing strategy: TDD requirements, unit test coverage, e2e stress tests | Developers |
| [09-mvp-and-roadmap.md](09-mvp-and-roadmap.md) | MVP scope, roadmap, phase gates | Product, developers |
| [10-backlog.md](10-backlog.md) | Deferred items, future work, non-goals, parked decisions | Product, architects |
| [appendix-A-decisions.md](appendix-A-decisions.md) | Consolidated decision log from three review rounds (no alternatives, just outcomes) | Reviewers, architects — for trace-back |

The design set has been reviewed three times (see appendix A). All decisions
are recorded there; the backlog captures deferred items and non-goals.

---

## Where to find things

If you're looking for… | Read…
---|---
**"How does a subject flow from creation to COMMIT?"** | `04-low-level-design.md` §4.0 (Application Lifecycle) — master diagram + happy-path sequence
**"What kinds of state exist, and how does the engine handle each?"** | `04-low-level-design.md` §4.0.1 (Kind Behaviour Matrix) + §4.1a–d (per-kind advance flows)
**"How does the engine handle failures?"** | `04-low-level-design.md` §4.0.4 (unhappy-path overview) + §4.1 (unhappy path table)
**"What does the passport look like on disk?"** | `03-data-model.md` §3.4 (JSON example) + §3.1a (`passport.base` schema)
**"How is data classified and redacted?"** | `02-high-level-design.md` §2.10 + `03-data-model.md` §3.1 (classification + `project()`)
**"How do I add a new specialist agent?"** | `03-data-model.md` §3.7 (config), `02-high-level-design.md` §2.30 (SignalMatcher)
**"How is a decision recorded and routed?"** | `04-low-level-design.md` §4.1b (record_decision flow), `03-data-model.md` §3.2 (decision schemas), §3.6 (routing rules)
**"Why does the design say X instead of Y?"** | `appendix-A-decisions.md` (grep for the affected term)
**"What's not being built yet?"** | `10-backlog.md`

---

## Key architecture decisions (top-of-mind list)

For the complete decision log see [appendix-A-decisions.md](appendix-A-decisions.md).

1. Labelled transition system (graph, not linked list); ASL-influenced JSON
2. State comparison via forward-progress DAG (back-edges excluded)
3. Retry (same state, transient) vs loop-back (earlier state, gate failure) — separate mechanisms
4. Process context: input + flat vars + meta (O(1), no full path)
5. Snapshot workflow definition only; NO agent snapshot (agents always latest)
6. JSON+lock+Markdown mirror (JSON authoritative); SQLite/PG for persistence/concurrency
7. Storage protocols (`SubjectReader`/`SubjectWriter`/`SubjectClaimStore`, `EventStore`, `OutcomeStore`, `StatusLog`, `WorkflowDefinitionStore`); multi-backend
8. Subject generalisation (ticket/survey/process/review); engine agnostic to subject type
9. `active_steps` (plural) for parallel-aware state tracking
10. Events table mandatory (not optional)
11. Pluggable dispatch handlers (engine doesn't branch on actor_kind)
12. Schema registry + opaque payload (engine validates, doesn't interpret project-specific structures)
13. Schema profile at `workflows/psc-profile.json`; `profile.base` JSON Schema
14. JSONPath for inputs/outputs/routing; `python-jsonpath` (RFC 9535 read + RFC 6901 write)
15. Discriminated unions for verdict-conditional outputs (JSON Schema `oneOf`+`const`)
16. Deterministic step writing via `OutcomeStore` (agent never picks the path)
17. UUIDv7 for step records (RFC 9562, time-ordered, sortable)
18. Agent-instructed + `OutcomeStore` (path 1 only; no plugin observer)
19. Python 3.14+ (StrEnum, uuid7, frozen dataclass, deferred annotations)
20. uv-managed, clean architecture (domain/application/infrastructure)
21. Separate `psc-adhoc` workflow file
22. SemVer workflows + max 2 MAJOR + 90-day grace + force-migrate-or-close
23. Lifecycle hooks (global, fire-and-forget, exception-safe); `AuditHook` dropped — `EventStore` IS the audit trail
24. Implicit start (WORKFLOW_STARTED + transition to `start_at`); no `__START__` node
25. Terminal detection (`kind: "terminal"` OR no transitions → WORKFLOW_COMPLETED); no `__END__` node
26. Cancel as external signal (`cancel_subject` API); writes CANCELLED status flag; fires WORKFLOW_CANCELLED
27. Mandatory `event_name` on every transition; Kafka-topic-safe pattern
28. Data classification: `private` (default, fail-closed) / `public` / `protected` (redacted); on schema, not on data
29. `project()` handles `additionalProperties`/`patternProperties`; fail-closed depth cap (`ProjectDepthExceeded`)
30. Verdict as `NewType[str]`; engine reserves `pass`/`fail`/`exhausted`
31. Every decision is a two-state pair: `task` (propose) → `decision_required` (confirm/decide)
32. Fencing token (`claim_epoch`) + auto-heartbeat context manager
33. SHA-256 hash chain on events and status_log (RFC 8785 canonical JSON)
34. Workflow definition integrity hash stored on `subjects` + `workflow_definitions`

---

## Executable steps (ordered)

| # | Step | What gets locked |
|---|------|------------------|
| **0.1** | Align on workflow steps & state machine | State machine contract |
| **0.2** | Align on outcomes per state | Outcome contracts |
| **0.3** | Align on API contracts | API contracts |
| **0.4** | Create the feature branch `feature/workflow-engine` | Done |
| **0.5** | Commit the design doc set | Done |
| **0.6** | Consolidate reviews into `appendix-A-decisions.md`; create `10-backlog.md`; add §4.0 Application Lifecycle | **Done — this pass** |
| **0.7** | Begin Phase 1 implementation (schemas + library core) | Implementation begins |

Steps 0.1–0.6 are complete. The design is consistent, decision-traceable, and
ready for implementation. Backlog items in `10-backlog.md` are deliberately
deferred and do not block Phase 1.
