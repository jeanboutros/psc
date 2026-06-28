# PSC Pipeline — Full Specification

> This is the deep dive. For the overview, see [../README.md](../README.md).

## The Standing Committee Model

PSC draws its execution philosophy from the efficiency of standing committees: small groups with clear mandates, rapid decision-making, and enforced accountability. Every agent has exactly one job. Every gate passes or fails objectively. No infinite review cycles, no scope creep, no "looks good to me" rubber stamps.

The Supreme Leader is the orchestrator — it dispatches work, enforces protocol, and escalates when retries are exhausted. It never writes code, never designs, never decides technical questions. Those decisions belong to the specialist closest to the problem.

---

## Phase A — Requirements & Design

**Goal:** Define and validate "What" and "How" before writing a single line of code.

### Task Domain Classification

Before dispatching Phase A, the task scope is classified to determine the specialist roster. The specialist count is **not fixed** — it depends on what the task touches.

| Domain Signal | Required Specialist |
|---------------|-------------------|
| Always | SW Engineer, Test Engineer, Docs Writer |
| Hardware, registers, GPIO, timers, peripherals | Hardware Engineer |
| Wireless, RF, BLE, radio protocols | Wireless Expert |
| Auth, secrets, crypto, network, input parsing | Security Reviewer |
| UI, frontend, dashboard, screens, UX | Product Designer + UX Engineer |
| Frontend code (HTML/CSS/JS/TSX/React/Vue) | UI Engineer (Phase B) |
| CI/CD, deployment, pipelines, GitHub Actions, Docker, Kubernetes, infrastructure | DevOps Specialist |

### Sub-steps

| Step | Name | Description | Who |
|------|------|-------------|-----|
| A0 | Task Definition | Produce detailed task specification: acceptance criteria, files, constraints, test strategy, doc plan. **Classify task domain** to determine specialist roster. | All agents collaborate |
| A1 | Parallel Specialist Review | All applicable specialists review the proposal independently | Specialist roster per Task Domain Classification |
| A2 | Dual-Model Challenge | Two model passes review architecture: primary produces, challenger critiques | Supreme Leader orchestrates |
| A2b | Synthesis Artifact Creation | PM creates individual decision, advisory, and clarification files from A2 synthesis findings in `docs/project-management/decisions/`, `advisories/`, `clarifications/`. | PM |
| A2c | Decision Register Presentation | Supreme Leader presents complete Decision Register to user in 4 priority-ordered rounds. User rules on each finding. | Supreme Leader presents, user decides |
| A2a | ADR Creation | Every resolved design decision from A2 MUST have an ADR file created at `docs/adr/<adr-id>.md`. Use `node docs/project-management/next-id.mjs adr` to get the next ADR sequence number. | SW Engineer (writes), Docs Writer (reviews) |
| A3 | A-GATE | T3 + T-ARCH compliance check | All dispatched specialists (T3), SW Engineer (T-ARCH) |

### A-GATE Pass Criteria

- All dispatched specialists issue **APPROVED** or **CONDITIONAL PASS**
- T-ARCH passes
- Every resolved design decision has an ADR file
- All synthesis artifacts created in `decisions/`, `advisories/`, `clarifications/` with user decisions recorded
- On fail: loop back to A1 with specific critique (max 3 loops per tier)

---

## Phase B — Build (PAU Loop)

**Goal:** Implement incrementally with self-validation, enforced by compliance gates.

### Sub-steps

| Step | Name | Description | Who |
|------|------|-------------|-----|
| B1 | PLAN | Read task, identify files, list acceptance criteria, declare logical units | Code Architect |
| B2 | APPLY (per unit) | Implement one logical unit, run build verification | Code Architect |
| B2a | B-UNIT-GATE | T1 + T-ARCH compliance check after each unit | Code Architect (T1), SW Engineer (T-ARCH) |
| B3 | VALIDATE | Full build, optional flash test | Code Architect |
| B3a | B-FINAL-GATE | T1 + T2 + T-ARCH compliance check after all units | Code Architect (T1), SW Engineer (T2 + T-ARCH) |

### B-UNIT-GATE Pass Criteria

- All 8 T1 checks pass + T-ARCH passes
- On fail: fix and retry (max 3× per tier)

### B-FINAL-GATE Pass Criteria

- T1 passes + T2 passes + T-ARCH passes
- On fail: route to appropriate fixer (max 3× per tier)

### The PAU Loop

Each unit follows **Plan → Apply → Validate**:

1. **Plan** — identify the unit, declare what changes are needed, list acceptance criteria
2. **Apply** — implement the changes, run build verification
3. **Validate** — run T1 checks, verify acceptance criteria, move to next unit or gate

---

## Phase C — Multi-Agent Verify

**Goal:** Final check before code review. ALL specialist agents must approve.

### Sub-steps

| Step | Name | Description | Who |
|------|------|-------------|-----|
| C0 | T1 Re-run | Mechanical compliance re-check on final codebase | Code Architect |
| C1 | Dual-Model Challenge (Verification) | Primary verifier + challenger verifier | Supreme Leader orchestrates |
| C2 | Parallel Specialist Approval | All dispatched specialists review independently | All dispatched specialists |
| C3 | C-GATE | T1 re-run + T3 + T-ARCH | Code Architect (T1), Dispatched specialists (T3), SW Engineer (T-ARCH) |
| C4 | PM Completion Review | Review all verdicts, decide: CLOSE / CLOSE+NEW / BLOCK / RE-DISPATCH / CANCEL / ARCHIVE | PM |

### C-GATE Pass Criteria

- T1 passes + all dispatched specialists APPROVED + T-ARCH passes

---

## Phase CR — Code Review

**Goal:** Structured, multi-round code review of the completed implementation before commit. Every ticket MUST go through at least one code review round.

### Sub-steps

| Step | Name | Description | Who |
|------|------|-------------|-----|
| CR1 | Code Review Round | Reviewer produces a structured code review with summary, detailed assessment, findings with confidence scores, changes still pending, and verdict | Dispatched reviewer(s) |
| CR2 | CR-GATE | All blocking findings (confidence ≥80) resolved. No open changes still pending. Reviewer verdict is APPROVED | Supreme Leader orchestrates |
| CR3 | Review Acceptance | Author confirms all review feedback is addressed | Code Architect (author) |

### CR-GATE Pass Criteria

- All blocking findings (confidence ≥80) from all review rounds are resolved
- Changes Still Pending list is empty
- Reviewer verdict is APPROVED

### CR-GATE Failure Routing

- CONDITIONAL PASS with rework → CR1 next round
- REJECTED with code changes needed → B2 (fix code), then re-enter Phase C and CR

### Code Review Format

Every code review round MUST produce a review record with:

1. **Review Metadata** — reviewer, date, files reviewed
2. **Summary** — 1-3 sentence overview of changes and quality
3. **Detailed Assessment** — organized by: Correctness, Design & Architecture, Code Quality, Testing, Documentation, Security & Safety
4. **Findings** — table with ID, confidence score, severity, file:line, description, suggested fix, status
5. **Changes Still Pending** — list of changes that must be made before review passes (MUST be empty for CR-GATE pass)
6. **Verdict** — APPROVED / CONDITIONAL PASS / REJECTED with rationale

### Code Review Rules

1. Every ticket MUST go through at least one code review round
2. Multiple rounds are expected for non-trivial changes
3. Changes Still Pending list MUST be empty for CR-GATE to pass
4. Findings use the review-confidence scoring system (≥80 blocks)
5. Code reviews are in addition to, not instead of, Phase C specialist reviews
6. Review records are permanent — appended to passport, never edited
7. CR-GATE failure with code changes needed loops back to B2, then re-enters C and CR
8. Maximum 5 review rounds per ticket, then escalate to user

---

## Compliance Tiers

Every gate checks one or more compliance tiers. Each tier has an **independent retry budget of 3**.

### T1 — Mechanical (Automated)

| # | Check | Criterion |
|---|-------|-----------|
| 1 | Build passes | Project build command exits 0 |
| 2 | No compiler warnings | `-Werror` is active; any warning is a failure |
| 3 | Doc-standard on all public API | Every public function/class/struct has a doc comment per the language-specific standard (e.g. `/** ... */` for Doxygen, JSDoc for JS) |
| 4 | No decision references in code | No `D-1:`, no "replaces the former..." |
| 5 | No raw integers in public API | Finite-value fields use `enum class`, not `uint8_t` |
| 6 | Reserved bits written as 0 | Register writes clear reserved bits |
| 7 | File placement | Library code in `components/`, app code in `main/` |
| 8 | Platform independence | Library headers include only `<cstdint>`, `<cstring>`, and own headers |

### T2 — Architectural (Software Engineer)

| # | Check | Criterion |
|---|-------|-----------|
| 1 | Platform boundary | All hardware access through `Hal` interface |
| 2 | Namespace hygiene | Clean hierarchy, no pollution |
| 3 | Typed enums | Every field with finite legal values uses `enum class` |
| 4 | No mutable globals | Stateful singletons forbidden |
| 5 | Build dependencies | Component dependencies correct and minimal |

### T3 — Semantic (All Dispatched Specialists)

All dispatched specialists (per the task-driven roster) must issue APPROVED or CONDITIONAL PASS:
- Software Engineer — architecture, API surface, SOLID
- Hardware Engineer — datasheet fidelity, register correctness, timing (if in scope)
- Wireless Expert — protocol compliance, channel mapping, modulation (if in scope)
- Security Reviewer — attack surfaces, buffer safety, secrets handling (if in scope)
- Test Engineer — test coverage, edge cases, static assertions
- Docs Writer — documentation completeness, reference accuracy, cross-document consistency

### T-ARCH — Structural & Principles

| # | Check | Criterion |
|---|-------|-----------|
| 1 | Logical consistency | No contradictions within the design |
| 2 | Structural soundness | No circular dependencies, clean layering |
| 3 | Principle alignment | Follows project principles (typed API, RAII, etc.) |
| 4 | Completeness | All requirements covered, no orphaned code |

---

## Compliance Gate State Machine

```
                                     ┌───────────────────────────────────────────────┐
                                     │                                               │
                                     ▼                                               │
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│  A0:Task │───▶│A1:Review│───▶│A2:Dual │───▶│A2b:Art- │───▶│A2c:Dec- │───▶│A2a:ADRs │───▶│A3:A-GATE│───▶│ B1:PLAN │
│  Def     │    │Parallel │    │Challenge│    │ifacts   │    │ision Reg│    │Create   │    │T3+T-ARCH│    │         │
└─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘    └────┬────┘    └─────────┘
                                                                   ▲                           │
                                                                   │ FAIL (3× T3 or T-ARCH)    │
                                                                   │                           │ PASS
                                                                   │                           ▼
                                                              ┌──────────┐              ┌──────────┐
                                                              │A1:Review │◀── 3×T3 ───│B2a:UNIT  │
                                                              │(loop back│             │GATE      │
                                                              │ with cri-│             │T1+T-ARCH │
                                                              │ tique)    │             └────┬─────┘
                                                              └──────────┘                  │       │
                                                                                                  │       │
                                                                       PASS ────────────────────┘       │
                                                                                            │
                                                                                    ┌───────▼──────┐
                                                                                    │More units?   │
                                                                                    └──┬────────┬─┘
                                                                                       │YES     │NO
                                                                                       │        │
                                                                                       │        ▼
                                                                                       │  ┌──────────┐
                                                                                       │  │B3a:FINAL │
                                                                                       │  │GATE      │
                                                                                       │  │T1+T2+ARCH│
                                                                                       │  └────┬─────┘
                                                                                       │       │
                                                                                       │  FAIL (3× any tier)
                                                                                       │  ┌─────│─────┐
                                                                                       │  │ LOOP BACK │
                                                                                       │  └─────│─────┘
                                                                                       │       │ PASS
                                                                                       │       ▼
                                                                                       │  ┌──────────┐
                                                                                       │  │C0:T1 re-  │
                                                                                       │  │run        │
                                                                                       │  └────┬─────┘
                                                                                       │       │
                                                                                       │       ▼
                                                                                       │  ┌──────────┐
                                                                                       │  │C1:Dual   │
                                                                                       │  │Challenge │
                                                                                       │  │(Verify)  │
                                                                                       │  └────┬─────┘
                                                                                       │       │
                                                                                       │       ▼
                                                                                       │  ┌──────────┐
                                                                                       │  │C2:Special-│
                                                                                       │  │ist Appro-│
                                                                                       │  │val (T3)  │
                                                                                       │  └────┬─────┘
                                                                                       │       │
                                                                                       │       ▼
                                                                                       │  ┌──────────┐
                                                                                       │  │C3:C-GATE │
                                                                                       │  │T1+T3+ARCH │
                                                                                       │  └────┬─────┘
                                                                                       │       │
                                                                                       │  FAIL (3× any tier)
                                                                                       │  ┌─────│─────┐
                                                                                       │  │ LOOP BACK│
                                                                                       │  └─────│─────┘
                                                                                       │       │ PASS
                                                                                       │       ▼
                                                                                       │  ┌──────────┐
                                                                                       │  │C4:PM     │
                                                                                       │  │Review    │
                                                                                       │  └────┬─────┘
                                                                                       │       │
                                                                                       │       ▼
                                                                                       │  ┌──────────┐◀──┐
                                                                                       │  │CR1:Code  │   │
                                                                                       │  │Review    │   │ next round
                                                                                       │  └────┬─────┘   │
                                                                                       │       │         │
                                                                                       │       ▼         │
                                                                                       │  ┌──────────┐   │
                                                                                       │  │CR2:CR-   │   │
                                                                                       │  │GATE      │───┘ (CONDITIONAL PASS
                                                                                       │  └────┬─────┘    with rework)
                                                                                       │       │
                                                                                       │  REJECTED  │ APPROVED
                                                                                       │  (code ──→ B2 (fix code), then re-enter C and CR)
                                                                                       │  changes)
                                                                                       │       │
                                                                                       │       ▼
                                                                                       │  ┌──────────┐
                                                                                       │  │CR3:Review│
                                                                                       │  │Acceptance│
                                                                                       │  └────┬─────┘
                                                                                       │       │
                                                                                       │       ▼
                                                                                       │  ┌──────────┐
                                                                                       │  │ COMMIT   │
                                                                                       │  └──────────┘
```

### State Transition Table

| From | Event | To | Condition |
|------|-------|----|-----------|
| A0 | Task defined | A1 | Task domain classified, specialist roster determined |
| A1 | Reviews complete | A2 | All dispatched specialists reviewed |
| A2 | Challenge complete | A2b | Synthesis produced, decisions identified |
| A2b | Artifacts created | A2c | PM created individual files in decisions/, advisories/, clarifications/ |
| A2c | User decisions received | A2a | User has ruled on all findings; PM updated artifact statuses |
| A2a | ADRs created | A3 | ADR file exists for every resolved decision |
| A3 | A-GATE passes | B1 | All dispatched specialists APPROVED/CONDITIONAL PASS + T-ARCH passes + ADRs present + artifacts created and user decisions recorded |
| A3 | A-GATE fails | A1 | REJECTED or T-ARCH fail; loop back (max 3×) |
| B1 | Plan complete | B2 | Logical units identified |
| B2 | Unit implemented | B2a | Build passes locally |
| B2a | B-UNIT-GATE passes | B2 (next unit) | T1 + T-ARCH pass |
| B2a | B-UNIT-GATE fails | B2 (fix) | T1 or T-ARCH fail; retry (max 3× per tier) |
| B2 | All units done | B3a | All units pass B-UNIT-GATE |
| B3a | B-FINAL-GATE passes | C0 | T1 + T2 + T-ARCH pass |
| B3a | B-FINAL-GATE fails | B2 (fix) | Any tier fails (max 3× per tier) |
| C0 | T1 re-run passes | C1 | All T1 checks pass |
| C0 | T1 re-run fails | B2 (fix) | Code Architect fixes (max 3×) |
| C1 | Challenge complete | C2 | Synthesis produced |
| C2 | Reviews complete | C3 | All dispatched specialists reviewed |
| C3 | C-GATE passes | C4 | All dispatched APPROVED + T1 pass + T-ARCH pass |
| C4 | PM issues CLOSE or CLOSE+NEW | CR1 | PM decides to close, proceed to code review |
| C4 | PM issues BLOCK | BLOCKED | Ticket paused, clarification ticket created |
| C4 | PM issues RE-DISPATCH | A0 (new cycle) | Rework, new dispatch cycle |
| C4 | PM issues CANCEL | CLOSED (cancelled) | Replacement + delta analysis tickets created |
| C4 | PM issues ARCHIVE | CLOSED (archived) | No replacement |
| C3 | C-GATE fails | C0 or C2 or B2 | T1→C0, T3→C2, T-ARCH→B2 |
| CR1 | Code review round complete | CR2 | Review record produced with findings and verdict |
| CR2 | CR-GATE passes | CR3 | No blocking findings, Changes Still Pending empty, verdict APPROVED |
| CR2 | CR-GATE fails (CONDITIONAL PASS) | CR1 (next round) | Rework needed but no code changes beyond review scope |
| CR2 | CR-GATE fails (REJECTED) | B2 (fix code) | Code changes needed; re-enter C and CR after fixes |
| CR3 | Author confirms feedback addressed | COMMIT | All review rounds complete, all findings resolved |
| CR3 | Author identifies unresolved findings | B2 (fix code) | Loop back, then re-enter C and CR |
| CR | 5 review rounds exhausted | ESCALATE | Unresolved blocking findings → Supreme Leader escalates to user |
| Any | 3 retries exhausted at any tier | ESCALATE | Supreme Leader presents violation report to user |

---

## Dispatch Envelope

Every agent dispatch carries a structured envelope:

```yaml
ticket: "<task-id>"
phase: "<A|B|C|CR>"
step: "<A0|A1|A2|A2a|A3|B1|B2|B2a|B3|B3a|C0|C1|C2|C3|C4|CR1|CR2|CR3>"
trigger: "<reason for this dispatch>"
agent: "<agent-role>"
passport: "docs/project-management/passports/<ticket-id>-passport.md"
skills_loaded:
  - "assumption-trap"
  - "compliance-gate"
  - "pipeline"
  - "pau-loop"
  - "<domain-specific-skills>"
expected_outcomes:
  - "<specific deliverable 1>"
  - "<specific deliverable 2>"
next_agent: "<agent-role or 'user' for escalation>"
retry_count:
  T1: <number>
  T2: <number>
  T3: <number>
  T-ARCH: <number>
review_round: <number>
OWASP_expansion: "<none | list of added compliance categories>"
```

### Field Definitions

| Field | Description |
|-------|-------------|
| `ticket` | Unique task identifier |
| `phase` | Current pipeline phase (A, B, C, or CR) |
| `step` | Current step within the phase |
| `trigger` | Why this dispatch occurred |
| `agent` | The agent being dispatched to |
| `passport` | Path to the pipeline passport file tracking completed steps for this task |
| `skills_loaded` | Skills loaded for this dispatch (always includes core) |
| `expected_outcomes` | Concrete, verifiable deliverables expected |
| `next_agent` | Who receives the output next |
| `retry_count` | Current retry count for each tier at the current gate |
| `review_round` | Current code review round number (0 if not in CR phase) |
| `OWASP_expansion` | Any OWASP compliance categories added for this task |

---

## Agent Routing

| Intent | Agent | Key Skills |
|--------|-------|------------|
| Architecture design | Software Engineer | assumption-trap, compliance-gate, type-design-review |
| Register model design | Hardware Engineer | assumption-trap, datasheet-verification, domain |
| RF protocol design | Wireless Expert | assumption-trap, datasheet-verification, domain |
| Security analysis | Security Reviewer | assumption-trap, silent-failure, memory-safety |
| Test strategy | Test Engineer | assumption-trap, test-driven-development |
| Documentation plan | Docs Writer | assumption-trap, verification-before-completion |
| Implementation | Code Architect | pau-loop, incremental-execution, compliance-gate |
| T1 compliance check | Code Architect | compliance-gate, verification-before-completion |
| T2 architectural review | Software Engineer | compliance-gate, type-design-review |
| T3 semantic review | All dispatched specialists | compliance-gate, domain-specific skills |
| T-ARCH review | Software Engineer | compliance-gate, type-design-review |
| Memory safety review | Memory Safety | assumption-trap, memory-safety |
| Gate orchestration | Supreme Leader | pipeline, compliance-gate, flag-protocol |
| Dispatch/routing | Supreme Leader | pipeline, flag-protocol |
| Task creation | PM | pipeline, flag-protocol |
| Code review (CR1) | Software Engineer (or dispatched reviewer) | compliance-gate, review-confidence, self-audit-checklist |
| CR-GATE orchestration | Supreme Leader | pipeline, compliance-gate, pipeline-passport |
| Review acceptance (CR3) | Code Architect (author) | compliance-gate, verification-before-completion |
| Debugging | Code Architect | systematic-debugging, domain |
| Product vision / requirements discovery | Product Designer | assumption-trap, design-taste, ux-patterns |
| Interaction design / UX review | UX Engineer | assumption-trap, ux-patterns, design-taste |
| UI implementation | UI Engineer | pau-loop, incremental-execution, design-taste, ux-patterns |
| CI/CD pipeline design | DevOps Specialist | assumption-trap, ci-cd-pipeline, github-actions |
| GitHub Actions workflow | DevOps Specialist | assumption-trap, ci-cd-pipeline, github-actions |
| Deployment strategy | DevOps Specialist | assumption-trap, ci-cd-pipeline, github-actions |
| Infrastructure / runner config | DevOps Specialist | assumption-trap, ci-cd-pipeline, github-actions |
| Shell script design / review | Bash Specialist | assumption-trap, bash-scripting |
| Shell script portability audit | Bash Specialist | assumption-trap, bash-scripting |
| Shell script security hardening | Bash Specialist | assumption-trap, bash-scripting |
| Shell script testing strategy | Bash Specialist | assumption-trap, bash-scripting |

---

## Dual-Model Challenge Protocol

Used in **Phase A** (architecture) and **Phase C** (verification).

### How It Works

1. **Primary pass** — First model produces the output (architecture proposal or verification).
2. **Challenger pass** — Second model independently reviews, looking for:
   - Contradictions with datasheet/spec
   - Missed edge cases
   - Unsupported assumptions
   - Security gaps
   - Protocol non-compliance
   - T-ARCH violations (logical errors, structural issues, principle misalignment)
3. **Synthesis** — Supreme Leader merges findings into a synthesis document. Then dispatches to PM for artifact creation, runs the Pre-Presentation Gate, and presents the complete Decision Register to the user in 4 priority-ordered rounds:
   - **Round 1: Disagreements** — user breaks ties (Primary / Challenger / Neither)
   - **Round 2: One-Sided Findings** — user dispositions each (ACCEPT / REJECT / BACKLOG / DEFER / IMPLEMENT NOW)
   - **Round 3: Recommendations** — user prioritizes
   - **Round 4: Agreements** — user may review or skip
   - **Fast-Track Option** — when >10 findings, offer to present critical+high now, backlog rest

**NO finding may be routed to Phase B without user disposition.** The Supreme Leader MUST NOT decide which findings are "accepted for implementation" — only the user can make that decision.

### When to Invoke

| Scenario | Use Dual-Model? |
|----------|-----------------|
| New register implementation | Yes |
| New protocol feature | Yes |
| HAL interface change | Yes |
| Architecture change | Yes |
| Bug fix in existing code | No (single pass) |
| Documentation-only change | No |
| Trivial refactor (rename, move) | No |

---

## Skill Loading Protocol

### Mandatory Loading Order

When a task is dispatched, skills must be loaded in this order:

1. `assumption-trap` — FIRST, always
2. `compliance-gate` — tiered checks, OWASP expansion
3. `pipeline` — this skill, state machine
4. `pau-loop` — for Phase B work
5. Domain-specific skills as needed

### Skill Categories

1. **Core skills** (always loaded): assumption-trap, compliance-gate, pipeline, pau-loop, verification-before-completion, self-audit-checklist, review-confidence, type-design-review, silent-failure
2. **Domain skills** (loaded based on task): project-specific skills matching the tech stack
3. **Phase skills** (loaded based on phase): brainstorming (Phase A), incremental-execution (Phase B), grill-me (Phase A or C Dual-Model Challenge)
4. **Compliance expansion** (loaded based on OWASP triggers): review task for new concern categories and load additional compliance checks as needed

---

## Pipeline Passport

Every task carries a **passport** that tracks which pipeline steps have been completed. No step may be skipped without written justification. An agent receiving a task with a missing previous step must reject it and return STATUS: BLOCKED to the Supreme Leader.

Passports are stored in `docs/project-management/passports/<ticket-id>-passport.md` and are created by the PM when a ticket is opened. For the full passport format and rules, see `.opencode/skills/pipeline-passport/SKILL.md`.

Key passport rules:

1. **No step without a stamp** — every step must be checked off before the next step begins
2. **No skip without justification** — a written justification and Supreme Leader authorisation are required
3. **Loops are tracked** — every A→B→A loop is recorded in the passport's Loop History section
4. **Passport travels with dispatch** — the passport file path is included in every dispatch envelope

---

## Pipeline Enforcement Protocol

The pipeline is **not advisory**. It is **mandatory**. The Supreme Leader MUST enforce these rules before every dispatch. No exceptions.

### No-Hotfix-Bypass Rule

The pipeline has **no bypass, no shortcut, no fast-track**. Every change — regardless of urgency, size, or type — must go through the full pipeline: Phase A → Phase B → Phase C → Phase CR.

| Claim | Reality |
|-------|---------|
| "It's just a quick fix" | It's a bugfix ticket. Dispatch to PM for passport creation, then Phase A. |
| "It's a one-line change" | One line still needs review, testing, and gate approval. |
| "It's urgent / production down" | Urgency does not exempt quality. Create a `bugfix` ticket and run the pipeline. |
| "I can just dispatch to code-architect directly" | No. PM creates the ticket and passport first. |

If the Supreme Leader detects it is about to bypass the pipeline, it MUST: STOP → classify ticket type → dispatch to `@pm` with `trigger: "create-passport"` → wait → only then proceed with pipeline routing.

For pipeline violations discovered after the fact: create a `mistake` ticket, run `post-rejection-correction`, then start the actual fix properly through the full pipeline.

### Pre-Dispatch Gate (Non-Skippable)

Before the Supreme Leader classifies intent or routes to any agent, it MUST execute this gated sequence:

| Gate Step | Check | Failure Action |
|-----------|-------|----------------|
| **PM Gate** | If new task: passport must be created by PM before any routing. Supreme Leader dispatches to PM with `trigger: "create-passport"` and waits. | BLOCKED — no routing until passport exists. |
| **Passport Exists** | Passport file at `docs/project-management/passports/<ticket-id>-passport.md` exists on disk. | BLOCKED — dispatch to PM for passport creation. |
| **Prior Steps Stamped** | All steps before target step have timestamps and results in Step Log. | BLOCKED — route to missing step's agent. |
| **Gate Results Recorded** | If at a gate, Gate Results table has current attempt entries. | BLOCKED — run gate first. |
| **Skips Justified** | Any unchecked Required Step has corresponding Skipped Steps entry with authorisation. | BLOCKED — require authorisation. |
| **Correction Records** | If retry_count > 0 for any tier, Correction Record exists in passport. | BLOCKED — dispatch to producing agent for post-rejection-correction. |
| **No-Bypass Check** | The dispatch is NOT routing directly to a producing agent for a code change without a passport and Phase A completion. | BLOCKED — dispatch to PM for passport creation. |

### Role Separation Rules

| Rule | Enforcement |
|------|-------------|
| Only PM creates passports | Supreme Leader MUST NOT create passport files. If none exists, dispatch to PM and wait. |
| Only PM creates tickets | Supreme Leader MUST NOT create task entries in TODO.md or ticket files. |
| Supreme Leader is dispatch-only | Supreme Leader MUST NOT perform specialist work. If a specialist fails, report to user — do not fill in. |
| No combined PM + Supreme Leader | These roles operate at different steps. The envelope must go PM → Supreme Leader, never both at once. |

### Status Protocol

When any enforcement check fails:

```
STATUS: BLOCKED
Reason: <which check failed and why>
Action Required: <what must happen to unblock>
```

The Supreme Leader must return this to the user immediately. Do NOT proceed to routing. Do NOT attempt to self-resolve.

---

## Self-Reflection Clause

After any pipeline violation or gate failure, the responsible agent MUST ask:

1. **Why was this not caught earlier?** — What review, test, or protocol gap allowed it through?
2. **What procedural safeguard would have caught it?** — What specific check, test, or verification step would have prevented it?
3. **Update the knowledge base** — Add the lesson to the relevant skill or learning doc.

Violations in the pipeline process itself (wrong routing, missed gate, skipped step) should be logged as flags and added to the pipeline skill's lessons learned.

---

## How the Install Script Handles Conflicts

The install script is **idempotent** — running it multiple times is safe.

| Situation | Action |
|-----------|--------|
| File doesn't exist | Create it |
| File exists, unmodified since last install | Update to new version |
| File exists, modified by the user | Create a merge prompt at `.opencode/merge/<filename>.merge.md` |

The merge prompt contains both the new version (upstream) and the current version (local), with instructions to resolve the conflict and delete the merge file when done.

**`counters.json` is never overwritten** — your project's ticket/epic/ADR counter state is always preserved.