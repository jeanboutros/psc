# AGENTS.md — Project Configuration

## Project Identity

| Field | Value |
|-------|-------|
| Name | PSC — Politburo Standing Committee |
| Repository | opencode-workflow |
| License | MIT |
| Role | **Upstream source-of-truth for the OpenCode workflow system.** The agents, skills, and pipeline definitions in this repository are installed into downstream projects via `install.sh`. Changes made here propagate to all projects using this workflow. |

## What PSC Provides

PSC is **not** a project that ships application code. It is the **workflow engine** — the agents, skills, pipeline state machine, compliance gates, and passport system that downstream projects install. Downstream projects (e.g. tian-er) add their own application code, design documents, and project-specific AGENTS.md sections on top of this workflow foundation.

### Upstream Artifacts (propagate to all downstream projects)

These files are the workflow definition. Changes here MUST be considered for propagation:

| Artifact | Installed to | Scope |
|----------|-------------|-------|
| `agents/*.md` | `.opencode/agents/` | Agent role definitions, permission blocks, dispatch envelopes |
| `skills/core/*/SKILL.md` | `.opencode/skills/<name>/SKILL.md` | Core skill definitions |
| `skills/domain/*/SKILL.md` | `.opencode/skills/<name>/SKILL.md` | Domain-specific skill definitions |
| `skills/core/pipeline/SKILL.md` | `.opencode/skills/pipeline/SKILL.md` | Pipeline state machine, enforcement protocol, routing table |
| `skills/core/pipeline-passport/SKILL.md` | `.opencode/skills/pipeline-passport/SKILL.md` | Passport format and rules |
| `skills/core/compliance-gate/SKILL.md` | `.opencode/skills/compliance-gate/SKILL.md` | Tiered compliance gate definitions |
| **Pipeline rules in AGENTS.md** | AGENTS.md (relevant sections) | Agent Permission Validation Rule, Documentation-Update Rule, Post-Change Verification Checklist, Pipeline Enforcement Protocol, Diagram Standard, Pipeline Generality Principle |
| `scripts/*` | `docs/project-management/` | next-id, counters |
| `docs/project-management/next-id.mjs` | `docs/project-management/next-id.mjs` | Atomic ID generator (9 kinds) |
| `docs/project-management/counters.json` | `docs/project-management/counters.json` | Counter state (must exist, never recreated) |
| `docs/pipeline.md` | `docs/pipeline.md` | Human-facing pipeline specification |
| `install.sh` | N/A (run from PSC repo) | Installation script |

### PSC-Only Artifacts (do NOT propagate)

These are specific to the PSC repository itself and never propagate to downstream projects:

| Artifact | Why PSC-only |
|----------|-------------|
| PSC's `README.md` | Downstream projects have their own README |
| PSC's `AGENTS.md` Project Identity section | Downstream projects have their own identity |
| PSC's `AGENTS.md` Tech Stack section | Downstream projects define their own tech stack |
| PSC's `AGENTS.md` Skill Registry | The registry describes installed skills — downstream AGENTS.md may differ |
| PSC's `AGENTS.md` Commit Rules | Downstream projects define their own commit conventions |
| PSC-specific directories | `docs/learning/`, test fixtures, etc. |

### Downstream Propagation Protocol

When changes are made to upstream artifacts in PSC, a request may be made to apply the same changes to downstream projects. When performing such propagation:

1. **Propagate all pipeline rule changes** — changes to the Pipeline Enforcement Protocol, dispatch envelope format, passport rules, compliance gates, and agent permission blocks MUST be applied to downstream projects' counterparts.
2. **Propagate agent/skill file changes** — if `agents/supreme-leader.md` or `agents/pm.md` changed, apply the same changes to the downstream `.opencode/agents/` copies. If a core skill changed, propagate it.
3. **Propagate relevant AGENTS.md rules** — the Agent Permission Validation Rule, Documentation-Update Rule, Post-Change Verification Checklist, Pipeline Enforcement rules, Diagram Standard, and Pipeline Generality Principle in AGENTS.md propagate. PSC-only sections (Project Identity, Tech Stack, Skill Registry) do NOT propagate.
4. **Do NOT overwrite project-specific customizations** — downstream projects may have customized their AGENTS.md with project principles, naming conventions, design document structures, etc. Only add or update the pipeline-related rules; never remove project-specific content.
5. **Respect downstream directory structure** — if the downstream project nests files under `.opencode/` (as the install script does), use those paths. Do not assume top-level `agents/` or `skills/core/` directories.
6. **Verify permission blocks after propagation** — after updating an agent file, run the Permission Validation Rule check to confirm the downstream agent's permissions still match its declared role.

---

## Online Validation Rule

**Agents MUST verify facts, specifications, and conventions against their online sources before acting.** Do not rely on training data or memory for anything that has an authoritative URL.

Examples:
- Before writing a commit → check [conventionalcommits.org](https://www.conventionalcommits.org/en/v1.0.0/) for the current spec
- Before using an API → check the library's official docs
- Before citing a standard (WCAG, OWASP, RFC) → fetch the canonical page
- Before installing a package → verify it exists and check the current version

If a source is unreachable, state that explicitly and ask the user rather than guessing from memory.

### Authoritative Reference Principle

**Every factual claim, implementation decision, and review finding MUST cite an authoritative source.** This principle applies to all domains — not just programming:

| Domain | Authority | Verification Method |
|--------|-----------|---------------------|
| Libraries / APIs | Official docs, Context7 | Fetch latest version-specific docs |
| Protocols | Official spec (RFC, Bluetooth SIG) | Fetch the specification document |
| Hardware | Manufacturer datasheet, errata | Verify against local copy or official site |
| Architecture | Well-architected frameworks (AWS, Google SRE) | Fetch the relevant pillar/section |
| Security | OWASP, CVE databases, NVD | Fetch the category or CVE page |
| Standards | ISO, W3C, IETF | Fetch the canonical standard page |

**Mandatory for all agents:**

1. **Search before acting** — Use `websearch`, `webfetch`, or Context7 to find the authoritative source before writing code or making claims.
2. **Cite with academic rigour** — Every claim must include a citation in the format defined by the `authoritative-reference` skill.
3. **Seek beyond implementation details** — When verifying a source, also look for best practices, gotchas, production-grade recommendations, deprecation notices, and anti-patterns. Do not stop at "does this API exist?"
4. **Challenger validation duty** — All challenger agents MUST validate that references are present, authoritative, and correctly applied. See the `authoritative-reference` skill for the Reference Validation format.

### Context7 — Library Documentation Lookup

When agents need library or API documentation, they SHOULD use [Context7](https://github.com/upstash/context7) to fetch up-to-date, version-specific docs directly into the prompt. This prevents hallucinated APIs, outdated code examples, and generic answers based on stale training data.

**Setup (one-time, requires Node.js 18+):**

```bash
npx ctx7 setup
```

This authenticates via OAuth, generates an API key, and installs the appropriate skill or MCP server. Use `--cursor`, `--claude`, or `--opencode` to target a specific agent. For manual MCP configuration, use server URL `https://mcp.context7.com/mcp` with a `CONTEXT7_API_KEY` header (free key from [context7.com/dashboard](https://context7.com/dashboard)).

**Available tools:**

| Mode | Command / Tool | Purpose |
|------|---------------|---------|
| CLI | `ctx7 library <name> <query>` | Search the Context7 index for a library and get its ID |
| CLI | `ctx7 docs <libraryId> <query>` | Fetch documentation for a library by its Context7 ID |
| MCP | `resolve-library-id` | Resolve a library name into a Context7-compatible ID |
| MCP | `query-docs` | Retrieve documentation by library ID (e.g. `/vercel/next.js`) |

**Usage in prompts:** append `use context7` to any library-related question, or specify a library ID directly with `/org/repo` syntax (e.g. `use library /supabase/supabase`).

**Rule for all agents:** Always use Context7 when needing library/API documentation, code generation, setup, or configuration steps — without the user having to explicitly ask. If Context7 is not available, fall back to fetching the library's official documentation URL directly.

---

## Deterministic Execution Rule

**Agents MUST execute known-command tasks in a single deterministic step.** No exploration, dry-runs, re-reading, or summarization when the command and its expected output are fully predictable.

### The Rule

1. **One step for known commands.** If you know the exact command and can predict the output shape, run it once. No dry-runs, no exploratory reads, no "let me first check" steps.
2. **No exploratory reading before execution.** Do not read source code, configuration files, or state files before running a command you already know how to use. Reading is for understanding; execution is for doing.
3. **No verification steps for predictable operations.** Do not re-read state files, re-list directories, or re-check counters after a deterministic operation. The command's exit code and output are sufficient evidence.
4. **No summarization of obvious results.** When the output is self-explanatory, state the result in one line.
5. **Batch independent operations.** When multiple operations are independent, run them in parallel.

### Examples

| Task | Wrong (multi-step) | Right (one step) |
|------|-------------------|-----------------|
| Get next ID | Read script → dry-run → run → read counter → list files → summarize | Run `next-id.mjs <kind>` → state the ID |
| Check build | Read Makefile → read config → run build → summarize | Run the build command → state pass/fail |
| Install package | Check package.json → check if installed → install → verify | Run install → state done |
| Create file | Check dir exists → list dir → write file → verify | Write the file → state created |

### Exceptions

The only valid reasons to multi-step a known-command task:
1. **Destructive operations** — `rm`, `git push --force`, `DROP TABLE`. Always confirm or dry-run destructive operations.
2. **First encounter** — If you have never seen a tool before, reading its source or help output is justified once per tool.
3. **Ambiguous requirements** — If the task is unclear, ask for clarification rather than exploring randomly.

Full protocol details are in the `deterministic-execution` skill.

---

## Git Push Rules

Agents MUST use the SSH agent socket for all git push operations. Subagent environments do not inherit `SSH_AUTH_SOCK`, so every push command MUST use:

```bash
SSH_AUTH_SOCK=~/.ssh/agent.sock git push origin main
```

**Pre-flight check (mandatory before every push):**

```bash
SSH_AUTH_SOCK=~/.ssh/agent.sock ssh -T git@github.com 2>&1 | grep -q "successfully authenticated" || { echo "SSH check failed"; exit 1; }
```

**If SSH check fails**, do NOT attempt `git push` without the socket. Do NOT switch the remote to HTTPS. Follow the resolution protocol in `skills/core/github/SKILL.md`.

**Force-push is FORBIDDEN.** If the branch has diverged, use `git pull --rebase origin main` then retry the push with the SSH agent socket.

---

## Commit Rules

### Conventional Commits v1.0.0 (Mandatory)

Every commit MUST follow the [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) specification.

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

Only `feat` and `fix` are required by the spec. The additional types below follow the [Angular convention](https://github.com/angular/angular/blob/22b96b9/CONTRIBUTING.md#-commit-message-guidelines) recommended by the spec.

| Type | When to Use |
|------|-------------|
| `feat` | New feature — agent, skill, script, or capability (correlates with SemVer MINOR) |
| `fix` | Bug fix in an existing file (correlates with SemVer PATCH) |
| `docs` | Documentation-only changes (README, pipeline.md, AGENTS.md) |
| `refactor` | Code restructuring with no behaviour change |
| `chore` | Maintenance (counters reset, dependency updates, file moves) |
| `style` | Formatting, whitespace, punctuation — no logic change |
| `test` | Adding or updating tests |
| `build` | Build system or external dependency changes |
| `ci` | CI configuration changes |
| `perf` | Performance improvement with no functional change |
| `revert` | Reverts a previous commit (body SHOULD reference the reverted SHA) |

### Scope (Optional)

A scope MAY be provided after the type. Use the file or directory name:

- `feat(product-designer): add discovery protocol for UI projects`
- `fix(next-id): correct default prefix fallback`
- `docs(readme): add human review status table`
- `refactor(compliance-gate): remove project-specific datasheet refs`

### Breaking Changes

A commit that introduces a breaking change MUST either:
- Append `!` after the type/scope, e.g. `feat(api)!: remove legacy endpoint`
- Include a `BREAKING CHANGE:` footer in the commit body

Both may be used together. A `BREAKING CHANGE` correlates with SemVer MAJOR.

### Body (Mandatory in This Project)

The spec makes the body optional. **This project makes it mandatory.** Every commit MUST include a body that describes:
1. **What** changed (the specific modification)
2. **Why** it changed (the motivation or issue it addresses)

The body MUST begin one blank line after the description.

```
feat(post-rejection-correction): add root-cause correction protocol

Add new core skill that requires agents to classify gate failures
into five root-cause categories (RC-1 through RC-5) before retrying.
This prevents retry loops from repeating the same class of mistake
without learning from the rejection.
```

### Footers (Optional)

One or more footers MAY be provided one blank line after the body. Each footer uses `token: value` or `token #value` format, e.g.:

```
Refs: #123
Reviewed-by: Jean
BREAKING CHANGE: old API removed
```

### Commit Granularity

- **One file per commit** is the default. Each file gets its own commit with a clear message.
- **Bundle only when tightly coupled** — files that are part of the same logical change and would be broken if committed separately may be grouped. Examples:
  - A new agent + its entry in the pipeline routing table
  - A new skill + a reference to it in compliance-gate
  - A rename that touches an import and its source
- **Never bundle unrelated changes** — "cleaned up a few things" commits are banned.
- **When in doubt, split** — two small commits are better than one muddled commit.

### Commit Message Quality

| Bad | Good |
|-----|------|
| `update readme` | `docs(readme): add human review status table for all project files` |
| `fix stuff` | `fix(pipeline): replace idf.py build with generic build command reference` |
| `add files` | `feat(ui-engineer): add frontend implementation agent for UI projects` |
| `changes` | `refactor(t1-check): remove ESP32-specific build checks` |

### Multi-Type Commits

If a commit conforms to more than one type, split it into multiple commits. This is a core benefit of the Conventional Commits spec — it drives more organised commits.

---

## Documentation-Update Rule

**After any change to the project, agents MUST update all affected documentation before considering the task complete.**

This includes but is not limited to:
- **README.md Review & Test Status tables** — add/remove rows when files are created, deleted, or renamed
- **AGENTS.md Skill Registry** — add/remove entries when skills are created or deleted
- **Pipeline routing table** (`skills/core/pipeline/SKILL.md`) — update when agents or intents change
- **Pipeline passport template** — update when pipeline steps change
- **docs/pipeline.md** — update when compliance tiers, gates, or dispatch rules change
- **Agent permission blocks** — validate `edit`/`bash` against agent role per the Permission Validation Rule below

If a change touches multiple docs, each doc update may be bundled with the triggering change when they are tightly coupled (per the Commit Granularity rule).

### Post-Change Verification Checklist

After every change, before considering the task complete, the agent MUST run this checklist:

- [ ] **AGENTS.md** — Did I add or remove a skill? Update the Skill Registry. Did I create or change an agent? Run the Permission Validation Rule check. Did I add a pipeline rule? Check it against the Pipeline Generality Principle.
- [ ] **docs/pipeline.md** — Did I change a gate, tier, dispatch rule, or enforcement protocol? Update this doc.
- [ ] **skills/core/pipeline/SKILL.md** — Did I add or change an agent intent? Update the routing table. Did pipeline steps change? Update the passport template reference. Are diagrams in Mermaid? Check against the Diagram Standard.
- [ ] **skills/core/pipeline-passport/SKILL.md** — Did I add or remove a pipeline step? Update the Required Steps template.
- [ ] **README.md** — Did I create, delete, or rename a file? Update the Review & Test Status tables.
- [ ] **Agent `permission:` block** — Did I create or change an agent? Validate `edit`/`bash` against the Permission Validation Rule. This is not optional — dispatch-only agents with `edit: allow` are a structural defect.
- [ ] **Pipeline generality** — Did I add project-specific examples, commands, or domain references to pipeline artifacts? Remove them or move them to a domain skill. Pipeline rules must be generic.

If a checklist item doesn't apply, mark it `N/A`. If you skip an item without justification, the change is incomplete.

---

## Diagram Standard

Diagrams in pipeline skills, agent definitions, and documentation MUST use **Mermaid** syntax wherever possible. Mermaid diagrams are renderable in Markdown viewers, Git platforms, and documentation sites without external tooling.

Rules:
- **State machines, flowcharts, sequence diagrams** — use Mermaid. Do not use ASCII art when a Mermaid diagram can express the same information.
- **Tables and structured data** — remain as Markdown tables. Mermaid is for relational and sequential information, not tabular data.
- **Existing ASCII diagrams** — when modifying a file that already contains an ASCII state machine or flowchart, convert it to Mermaid in the same edit. Do not leave a mix of ASCII and Mermaid in the same file.
- **Embedding** — use fenced code blocks with the `mermaid` language tag:

````
```mermaid
stateDiagram-v2
    [*] --> A0
    A0 --> A1
    A1 --> A2
```
````

- **Complexity** — if a diagram has more than 15 nodes, consider splitting it into sub-diagrams (one per phase) rather than producing an unreadable monolith.

---

## Pipeline Generality Principle

**PSC is an upstream workflow engine used by multiple projects. Pipeline definitions, compliance gates, agent role descriptions, and RCAs MUST remain generic and project-agnostic.**

### Rules

1. **No project-specific technical details in pipeline artifacts.** The pipeline, compliance gates, passport format, dispatch envelopes, and agent role definitions must not reference any specific project's code, framework, hardware, or domain. Example violations:
   - Referencing `init()` as a canonical silent-failure example in the pipeline skill — the example is project-specific.
   - Hardcoding `idf.py build` as a T1 build check — the build command belongs in the downstream project's AGENTS.md, not in the upstream pipeline.
   - Naming a specific register or protocol in a compliance gate — domain-specific checks belong in domain skills.

2. **Project-specific details belong in two places only:**
   - **Downstream project AGENTS.md** — tech stack, build commands, domain-specific traps, naming conventions.
   - **Domain skills** — skills scoped to a specific technology (e.g. `esp-idf`, `ble-protocol`, `tdd-cpp`) may contain language- or framework-specific rules. These are optional and only loaded when a task touches that domain.

3. **When writing RCAs, ACRs, or change requests** that affect the general pipeline:
   - Frame the problem and solution in abstract terms. Instead of "init() is never called," write "a function silently fails when its precondition is not met."
   - Instead of "the ESP32 build fails," write "the build command for the target platform fails."
   - Instead of "nRF24L01+ register CONFIG at bit 0," write "a hardware register bit position."
   - Concrete examples may be provided in parenthetical notes, but the rule itself must be generic.

4. **The only exception** is when a skill is explicitly scoped to a language or framework (e.g. `doxygen-cpp`, `tdd-cpp`, `esp-idf`). These skills are domain-specific by design and are not part of the generic pipeline — they are only loaded when a task touches that domain.

5. **When propagating changes downstream**, strip any PSC-specific examples before applying. Downstream projects should see generic pipeline rules, not PSC's internal examples.

---

## Agent Permission Validation Rule

**Every agent's `permission:` block must match its declared role. Mismatches are a structural defect.**

When creating or modifying an agent file, validate these constraints:

| If the agent's Role says... | Then `permission.edit` must be... | And `permission.bash` must be... |
|-----------------------------|-----------------------------------|----------------------------------|
| Dispatch-only / orchestrator / "never executes work" / "never writes code" | `deny` | `deny` |
| Read-only reviewer (does not produce code) | `deny` | `allow` (for building/documenting) |
| Task management only (PM) | `allow` (only for management files) | `allow` |
| Code-producing agent (Code Architect, UI Engineer) | `allow` | `allow` |
| Security reviewer / test engineer | `allow` | `allow` |

**Default denial for dispatch-only agents:** Any agent with "DISPATCH-ONLY" in its role description, or whose constraints say "Can edit code: No", MUST have `permission.edit: deny` and `permission.bash: deny` in its YAML frontmatter.

**The check:** After any agent file change, verify:
1. The permission block is present in the YAML frontmatter
2. `edit` matches the agent's declared capabilities (if "never writes code" → `deny`)
3. `bash` matches the agent's declared capabilities (if "coordination only" → `deny`)
4. The `Constraints` section in the body does not contradict the YAML permissions

This rule exists because advisory text ("I should not write code") is insufficient — the YAML permission block is the runtime enforcement. A dispatch-only orchestrator with `edit: allow` is a breach vector for bypassing the pipeline.

---

## Tech Stack

| Component | Value |
|-----------|-------|
| Agent runtime | OpenCode / Claude Code / Cursor / Copilot |
| Skill format | SKILL.md with YAML frontmatter |
| Agent format | Markdown with YAML frontmatter |
| ID generator | Node.js (next-id.mjs) |
| Installer | Bash (install.sh) |

---

## Skill Registry

### Core Skills (Always Loaded)

| Skill | Purpose |
|-------|---------|
| assumption-trap | Halt on ambiguity — never guess |
| authoritative-reference | Mandatory referencing — every claim cites an authoritative source; challengers validate references |
| brainstorming | Phase A creative exploration |
| ci-cd-pipeline | CI/CD pipeline design principles, deployment strategies, environment management, build matrix patterns, artifact management |
| compliance-gate | Tiered gate system (T1/T2/T3/T-ARCH) |
| context7-docs | Fetch up-to-date library/API docs (CLI → MCP → URL fallback) |
| cross-document-consistency | Grep-based cross-document checks (DC-1 through DC-4) |
| datasheet-verification | Verify claims against source documents |
| deterministic-execution | Execute known-command tasks in a single step — no exploration, dry-runs, or re-reading for predictable operations |
| doxygen-cpp | Doxygen documentation standard for C/C++ projects |
| flag-protocol | Structured request format for non-PM agents |
| github | Conventional commits, SSH auth, safe push, commit granularity |
| grill-me | Adversarial design review |
| incremental-execution | Unit-by-unit implementation |
| memory-safety | Memory safety review (C/C++ projects) |
| multi-model-validation | Launch parallel generic agents (2+ models) for cross-validation, fact-checking, requirement refinement |
| pau-loop | Plan → Apply → Validate loop |
| pipeline | Full pipeline state machine |
| pipeline-passport | Task tracking card |
| post-rejection-correction | Root-cause analysis before retry |
| review-confidence | 0-100 confidence scoring |
| self-audit-checklist | Mandatory pre-verdict checklist |
| silent-failure | Detect silent failure modes |
| skill-recruiter | Online skill search, safety scanning, skill gap detection, conversation synthesis |
| software-engineering-principles | Clean Architecture, SOLID, DRY, TDD, C4 model, state machine docs, module dependency rules |
| systematic-debugging | Structured debugging protocol |
| tdd-cpp | Test-driven development for C++ |
| test-driven-development | Generic TDD loop |
| type-design-review | Type system and API review |
| verification-before-completion | Final verification before marking done |

### Domain Skills (Optional — Project-Specific)

| Skill | Purpose |
|-------|---------|
| bash-scripting | Bash scripting standards, defensive programming, POSIX portability, testing frameworks, security hardening |
| ble-protocol | BLE protocol compliance |
| cpp-embedded | Embedded C++ patterns |
| design-taste | Anti-slop frontend design |
| esp-idf | ESP-IDF framework |
| github-actions | GitHub Actions workflow syntax, events, jobs, runners, secrets, OIDC, security hardening, Dependabot, marketplace actions |
| nrf24l01plus | nRF24L01+ radio chip |
| nrf52840-sniffer | nRF52840 sniffer |
| ubertooth | Ubertooth platform |
| ux-patterns | UX interaction patterns and state management |
