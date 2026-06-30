# PSC Workflow Engine — Design Document Set

> **Status:** DRAFT. All architecture decisions are marked **[LOCKED]** or **[TENTATIVE]**.
> **Branch:** `feature/workflow-engine`.
> **Owner:** Supreme Leader (orchestrating); design synthesised from parallel agent
> exploration + critique + authoritative research on workflow semantics.

---

## How to read this document set

This is a multi-file design document. Read in order:

| File | Content | Audience |
|------|---------|---------|
| [01-rationale-philosophy.md](01-rationale-philosophy.md) | Purpose, philosophy of approach, design agnosticism principle | All readers — start here |
| [02-high-level-design.md](02-high-level-design.md) | Workflow semantics, ontology, architecture decisions, entity definitions, logical data model | Architects, reviewers |
| [03-data-model.md](03-data-model.md) | Physical data model, JSON schemas, data dictionary, PSC data structures, storage protocols, JSONPath, data classification & redaction, config | Developers, data modellers |
| [04-low-level-design.md](04-low-level-design.md) | Process flow, sequence diagrams, parallel flows, transition table, persistence, multi-session safety, step writing, lifecycle hooks, cancel, OpenCode hooks research, API contracts, e2e test, implementation phasing | Developers |
| [05-ui-ux.md](05-ui-ux.md) | UI views, API integration, user flow diagrams | Designers, frontend developers |
| [06-references.md](06-references.md) | Academic-style references (39+ citations) | All — for verification |

---

## Decision status summary

### Locked decisions (31)

1. Labelled transition system (graph, not linked list); ASL-influenced JSON
2. State comparison via forward-progress DAG (back-edges excluded)
3. Retry (same state, transient) vs loop-back (earlier state, gate failure) — separate mechanisms
4. Process context: input + flat vars + meta (O(1), no full path)
5. Snapshot workflow definition only; NO agent snapshot (agents always latest)
6. JSON+lock+Markdown mirror (JSON authoritative); SQLite/PG for persistence/concurrency
7. Storage protocols (SubjectStore, EventStore, WorkflowDefinitionStore); multi-backend
8. Subject generalisation (ticket/survey/process/review); engine agnostic to subject type
9. `active_steps` (plural) for parallel-aware state tracking
10. Events table mandatory (not optional)
11. Pluggable dispatch handlers (engine doesn't branch on actor_kind)
12. Schema registry + opaque payload (engine validates, doesn't interpret project-specific structures)
13. Schema profile at `workflows/psc-profile.json`
14. JSONPath for inputs/outputs/routing; `python-jsonpath` (RFC 9535 read + RFC 6901 write)
15. Discriminated unions for verdict-conditional outputs (JSON Schema `oneOf`+`const`)
16. Deterministic step writing via StepWriter (agent never picks the path)
17. UUIDv7 for step records (RFC 9562, time-ordered, sortable)
18. Agent-instructed + StepWriter (path 1 only; no plugin observer)
19. Python 3.14+ (StrEnum, uuid7, frozen dataclass, deferred annotations)
20. uv-managed, clean architecture (domain/application/infrastructure)
21. Separate `psc-adhoc` workflow file
22. SemVer workflows + max 2 MAJOR + 90-day grace + force-migrate-or-close
23. Lifecycle hooks (global, fire-and-forget, exception-safe; LoggingHook, ObservabilityHook, EventDispatchHook, AuditHook)
24. Implicit start (WORKFLOW_STARTED + transition to `start_at`); no `__START__` node
25. Terminal detection (`kind: "terminal"` OR no transitions → WORKFLOW_COMPLETED); no `__END__` node
26. Cancel as external signal (`cancel_subject` API; writes CANCELLED; fires WORKFLOW_CANCELLED; abrupt — no STATE_EXITED)
27. Mandatory `event_name` on every transition (validated at load time; Kafka-topic-safe pattern)
28. Generic `subject.*` prefix in event_name, replaced with actual subject_type at dispatch time
29. `WorkflowDefinitionError` + load-time validation (event_name present, targets exist, schemas resolvable, forward-DAG acyclic, start_at exists, terminal exists)
30. Data classification: `public` (default) / `private` (omitted) / `protected` (redacted); on schema, not on data
31. Redactor protocol + RedactorRegistry; DefaultRedactor used when no redactor specified; passport stores cleartext, project() applied at all emission boundaries

### Tentative (1)

- T1: MCP server vs CLI for Supreme Leader call boundary — both surfaces designed, pick at runtime

---

## Open questions for review

1. **MCP vs CLI** — confirm MCP is the boundary (preserves `bash:deny`), or relax `bash:allow` scoped to `psc_engine` calls (simpler, no MCP infra). Both surfaces are designed; the choice is runtime.
2. **Adhoc heuristic** — what's the precise rule the Supreme Leader uses to pick `psc-adhoc` vs `psc-main` at A0? (Single-concern? Single-file-class? No architecture impact? All three?) Needs a concrete decision procedure, not a vague heuristic.
3. **Decision timeout policy** — when a `decision_required` state never receives a decision (E7), after how long does the PM route to `DEFERRED`? Is it a wall-clock timeout or an explicit user/PM action?
4. **Mirror commit cadence** — is the Markdown mirror committed on every `advance()`, or only at phase boundaries / gate passes? Committing every advance is noisy but accurate; committing at boundaries is cleaner but can drift from JSON mid-phase.
5. **Roster proposal vs confirmation split** — does the Supreme Leader propose the roster and the user confirm (two-step, current design), or does the user select from scratch (one-step, simpler but loses the signal-driven default)?
6. **Database vs JSON-only** — the design presents both (§1.2 JSON authoritative; §11 database for persistence/concurrency). Confirm both are required, or drop the database if multi-session safety is not a near-term requirement.
7. **CI lint for sensitive field names** — should the engine ship a CI lint that flags common sensitive field names (`password`, `api_key`, `secret`, `token`, `credential`, `email`, `phone`) not classified as `protected` or `private`?

---

## Executable steps (ordered)

| # | Step | What gets locked |
|---|------|------------------|
| **0.1** | Align on workflow steps & state machine (walk every state, kind, transition, loop flag) | State machine contract |
| **0.2** | Align on outcomes per state (outcome_schema per state, PSC data structures from example logs) | Outcome contracts |
| **0.3** | Align on API contracts (MCP/CLI tool surface, e2e test prototype) | API contracts |
| **0.4** | Create the feature branch `feature/workflow-engine` | Done |
| **0.5** | Commit the design doc set | Done |
| **0.6** | Begin Phase 1 implementation (schemas + library core) | Implementation begins |

> Steps 0.4 and 0.5 are complete. Steps 0.1–0.3 are the next review cycle.