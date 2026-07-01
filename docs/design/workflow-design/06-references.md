# 06 — References

Academic-style citations. All sources were fetched during research unless
noted otherwise.

---

## Workflow Modeling and Semantics

1. **Amazon States Language Specification.** *States Language Specification.*
   https://states-language.net/spec.html — fetched in full. Foundational
   for the labelled-transition-system graph model, `Choice` rules,
   `Parallel` join (AND-join, wait for all branches), `Retry` blocks
   (`max_attempts`, `interval`, `backoff`), and the Context Object
   (`State.RetryCount`).

2. **AWS Step Functions.** *Amazon States Language overview.*
   https://docs.aws.amazon.com/step-functions/latest/dg/concepts-amazon-states-language.html
   — fetched.

3. **AWS Step Functions.** *Context Object.*
   https://docs.aws.amazon.com/step-functions/latest/dg/input-output-contextobject.html
   — fetched. Precedent for `meta.entry_count` / `meta.attempt` (mirrors
   `State.RetryCount`).

4. **AWS Step Functions.** *Workflow variables.*
   https://docs.aws.amazon.com/step-functions/latest/dg/workflow-variables.html
   — fetched. Scoped-variables precedent for the `vars` blackboard.

5. **Object Management Group.** *BPMN 2.0.2 Specification.*
   https://www.omg.org/spec/BPMN/2.0.2/ — landing fetched; full PDF requires
   OMG account. Vocabulary: Task, Gateway (XOR/AND/Inclusive), User Task
   (block + form + resume), sequence flow, boundary error events, loop
   markers.

6. **Camunda.** *BPMN Gateways.*
   https://docs.camunda.io/docs/8.9/components/modeler/bpmn/gateways/ —
   fetched. XOR/AND/OR gateway semantics.

7. **Camunda.** *BPMN User Tasks.*
   https://docs.camunda.io/docs/8.9/components/modeler/bpmn/user-tasks/ —
   fetched. User Task (block + form + resume) precedent for
   `decision_required` states.

8. **Camunda.** *Variables and Variable Scopes.*
   https://docs.camunda.io/docs/components/concepts/variables.md — fetched.
   Scoped variables + output mappings precedent for `vars` and
   engine-managed output binding.

9. **Camunda.** *Process Definition Versioning.*
   https://docs.camunda.io/docs/components/best-practices/operations/versioning-process-definitions/
   — fetched. Snapshot-per-instance consensus.

10. **van der Aalst, W. M. P.** "The Application of Petri Nets to Workflow
    Management: The Workflow Nets." *Journal of Circuits, Systems, and
    Computers*, Vol. 8, No. 1–2, pp. 21–66, 1998.
    DOI: [10.1142/S0218126698000033](https://doi.org/10.1142/S0218126698000033)
    — cited by canonical bibliographic reference (PDF unreachable). WF-net
    soundness (liveness + boundedness); four routing primitives
    (sequential, parallel, choice, iteration).

---

## Durable Execution and Replay

11. **Temporal.** *Workflows — How Workflow replay works.*
    https://docs.temporal.io/workflows — fetched. Replay-from-history model.

12. **Temporal.** *Events and Event History.*
    https://docs.temporal.io/workflow-execution/event — fetched. 51,200-event
    cap + Continue-As-New.

13. **Temporal.** *Workflow Execution overview (Replays, State Transition).*
    https://docs.temporal.io/workflow-execution — fetched.

14. **Temporal.** *Task Queues (server-mediated assignment, persistence).*
    https://docs.temporal.io/task-queue — fetched. Multi-session safety
    precedent.

15. **Temporal.** *Workers (stateless, resurrection).*
    https://docs.temporal.io/workers — fetched.

16. **Temporal.** *Worker Versioning.*
    https://docs.temporal.io/production-deployment/worker-deployments/worker-versioning
    — fetched. Pinned = snapshot-per-instance.

17. **Temporal.** *Python Workflows — Versioning.*
    https://docs.temporal.io/develop/python/workflows/versioning — fetched.
    Patching semantics.

18. **Temporal.** *Python SDK — Activity basics.*
    https://docs.temporal.io/develop/python/activities/basics — fetched.
    Activity returns a value; framework records it in event history.

---

## Step Functions Execution Model

19. **AWS Step Functions.** *Concepts (Standard vs Express, exactly-once,
    1-year).*
    https://docs.aws.amazon.com/step-functions/latest/dg/concepts.html —
    fetched. Snapshot-per-transition persistence model.

20. **AWS Step Functions.** *Activities (taskToken, GetActivityTask,
    heartbeat, timeout).*
    https://docs.aws.amazon.com/step-functions/latest/dg/concepts-activities.html
    — fetched. Single-token-dispatch precedent for multi-session safety.

---

## SQLite Persistence and Concurrency

21. **SQLite.** *Write-Ahead Logging.*
    https://www.sqlite.org/wal.html — fetched. WAL mode, single-writer,
    same-host constraint.

22. **SQLite.** *File Locking And Concurrency in SQLite Version 3.*
    https://www.sqlite.org/lockingv3.html — fetched. SHARED/RESERVED/PENDING/
    EXCLUSIVE locks; why optimistic CAS beats pessimistic locking in SQLite.

---

## UUIDv7 and Time-Ordered Identifiers

23. **IETF.** *RFC 9562 — Universally Unique IDentifiers (UUIDs).* Proposed
    Standard, May 2024. Obsoletes RFC 4122.
    https://datatracker.ietf.org/doc/rfc9562/ — fetched. §5.7 (UUIDv7
    format: 48-bit ms timestamp + version + random), §2.1 (motivation:
    lexical sortability, index locality, no MAC leak), §6.11 (sorting),
    §6.2 (monotonicity within a millisecond).

---

## JSONPath and JSON Pointer

24. **IETF.** *RFC 9535 — JSONPath: Query Expressions for JSON.* Proposed
    Standard, February 2024.
    https://datatracker.ietf.org/doc/rfc9535/ — fetched. The standard
    JSONPath query syntax used for inputs/outputs/routing.

25. **IETF.** *RFC 6901 — JavaScript Object Notation (JSON) Pointer.*
    https://datatracker.ietf.org/doc/rfc6901/ — referenced. Used for
    path-addressed writes to `ctx.vars` (JSONPath is read-only; JSON Pointer
    is the write counterpart).

26. **python-jsonpath.** *RFC 9535 + RFC 6901 + RFC 6902 for Python.*
    https://pypi.org/project/python-jsonpath/ — fetched. The library used
    in the reference implementation for both read (JSONPath) and write
    (JSON Pointer / JSON Patch).

---

## Python 3.14+ Reference Implementation

27. **Python Software Foundation.** *Python 3.14 — enum module.*
    https://docs.python.org/3.14/library/enum.html — fetched. `StrEnum`
    (added 3.11); `__str__` returns the raw value.

28. **Python Software Foundation.** *Python 3.14 — uuid module.*
    https://docs.python.org/3.14/library/uuid.html — fetched. `uuid6()`,
    `uuid7()`, `uuid8()` added in 3.14 per RFC 9562.

29. **Python Software Foundation.** *Python 3.14 — dataclasses module.*
    https://docs.python.org/3.14/library/dataclasses.html — fetched.
    `frozen=True` + `field(default_factory=...)` idiom.

30. **Python Software Foundation.** *Python 3.14 — What's New.*
    https://docs.python.org/3.14/whatsnew/3.14.html — fetched. Deferred
    annotations (PEP 649), `copy.replace()`, template strings (PEP 750).

31. **Smith, J., et al.** *PEP 695 — Type Parameter Syntax.*
    https://peps.python.org/pep-0695/ — the `type` statement (3.12+).

---

## OpenCode Platform

32. **OpenCode.** *Plugins.*
    https://opencode.ai/docs/plugins/ — fetched. Hook system
    (`tool.execute.before`, `tool.execute.after`, `event`); session events.

33. **OpenCode.** *Config.*
    https://opencode.ai/docs/config/ — fetched. No `hooks`/`events` config
    field; extension points are `plugin` and `mcp` only.

34. **OpenCode.** *Agents.*
    https://opencode.ai/docs/agents/ — fetched. Agents configured via
    `prompt` field; `task` permission key governs subagent dispatch.

35. **OpenCode.** *Config JSON Schema.*
    https://opencode.ai/config.json — fetched. Confirms no hook/event/lifecycle
    config fields.

36. **OpenCode.** *SDK — Events.*
    https://opencode.ai/docs/sdk/ — fetched. `client.event.subscribe()` and
    `client.session.messages()`.

37. **OpenCode.** *Server — Events endpoint.*
    https://opencode.ai/docs/server/ — fetched. `/event` SSE endpoint and
    `/session/:id/children`.

---

## Conditional Outputs and Discriminated Unions

38. **JSON Schema.** *A Media Type for Describing JSON Documents (2020-12).*
    §10.2.1 (`oneOf`, `anyOf`, `allOf`); §10.2.2 (`if`/`then`/`else`).
    https://json-schema.org/draft/2020-12/json-schema-core — fetched.

39. **JSON Schema.** *Validation Vocabulary (2020-12).* §6.5.4
    `dependentRequired`.
    https://json-schema.org/draft/2020-12/json-schema-validation — fetched.

40. **TypeScript.** *Handbook — Narrowing — Discriminated unions.*
    https://www.typescriptlang.org/docs/handbook/2/narrowing.html#discriminated-unions
    — fetched.

41. **Pydantic.** *Concepts — Unions — Discriminated unions.*
    https://docs.pydantic.dev/latest/concepts/unions/#discriminated-unions —
    fetched. `Field(discriminator="verdict")` + `Literal` tag.

42. **OpenAPI Initiative.** *OpenAPI Specification 3.0 — Inheritance and
    Polymorphism — Discriminator.*
    https://swagger.io/docs/specification/data-models/inheritance-and-polymorphism/
    — fetched.

---

## Workflow Interceptors and Lifecycle Hooks

43. **Temporal.** *Interceptors.*
    https://docs.temporal.io/develop/python/worker#interceptors — referenced.
    Global hook pattern for logging/observability on every transition.

44. **Camunda 8.** *Internal processing (stream processors, exporters).*
    https://docs.camunda.io/docs/8.7/components/zeebe/technical-concepts/internal-processing/
    — fetched. Event listener / exporter pattern for every record written
    to the stream.

45. **AWS Step Functions.** *Execution history events.*
    https://docs.aws.amazon.com/step-functions/latest/dg/concepts.html —
    fetched. `StateEntered`, `StateExited`, `ExecutionStarted`,
    `ExecutionSucceeded`, `ExecutionFailed` events.

---

## Hash Chains and Tamper-Evidence

46. **Nakamoto, S.** "Bitcoin: A Peer-to-Peer Electronic Cash System." 2008.
    https://bitcoin.org/bitcoin.pdf — referenced. §3 (Timestamp Server):
    each block contains the hash of the previous block, forming a chain;
    tampering with any block requires recomputing all subsequent blocks.
    Precedent for the events table hash chain (`row_hash = H(current_data +
    hash_of_previous_row)`).

---

## Fencing Tokens and Distributed Locking

47. **Kleppmann, M.** "How to do distributed locking." 8 February 2016.
    https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html
    — fetched. Fencing token pattern: a monotonically increasing token
    assigned on each lock acquisition; every write includes the token;
    the resource rejects writes whose token is less than the last-seen
    token. Precedent for `claim_epoch` in the claim/lease protocol.

---

## SQL CASE Expression

48. **PostgreSQL Global Development Group.** *PostgreSQL 17 —
    Conditional Expressions (CASE).*
    https://www.postgresql.org/docs/17/functions-conditional.html —
    fetched. SQL `CASE WHEN condition THEN result ... ELSE default END`
    expression. Precedent for the routing rule DSL: one shape, flat
    evaluation, first-match-wins semantics.

---

## Python Type System

49. **Python Software Foundation.** *PEP 484 — Type Hints.*
    https://peps.python.org/pep-0484/ — referenced. `NewType` for creating
    distinct types with minimal runtime overhead. Precedent for
    `Verdict = NewType("Verdict", str)` — an open set validated externally
    by JSON Schema rather than a closed `StrEnum`.

50. **Python Software Foundation.** *Python 3.14 — hashlib module.*
    https://docs.python.org/3.14/library/hashlib.html — fetched.
    `hashlib.sha256()` for cryptographic hashing used in idempotency keys
    (`sha256(subject_id + step + entry_count + attempt)`) and hash chain
    row hashes.
