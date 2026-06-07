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
| **Pipeline rules in AGENTS.md** | AGENTS.md (relevant sections) | Agent Permission Validation Rule, Documentation-Update Rule, Post-Change Verification Checklist, Pipeline Enforcement Protocol |
| `scripts/*` | `docs/pipeline/scripts/`, `docs/project-management/` | T1 checks, next-id, counters |
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
3. **Propagate relevant AGENTS.md rules** — the Agent Permission Validation Rule, Documentation-Update Rule, Post-Change Verification Checklist, and Pipeline Enforcement rules in AGENTS.md propagate. PSC-only sections (Project Identity, Tech Stack, Skill Registry) do NOT propagate.
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

- [ ] **AGENTS.md** — Did I add or remove a skill? Update the Skill Registry. Did I create or change an agent? Run the Permission Validation Rule check.
- [ ] **docs/pipeline.md** — Did I change a gate, tier, dispatch rule, or enforcement protocol? Update this doc.
- [ ] **skills/core/pipeline/SKILL.md** — Did I add or change an agent intent? Update the routing table. Did pipeline steps change? Update the passport template reference.
- [ ] **skills/core/pipeline-passport/SKILL.md** — Did I add or remove a pipeline step? Update the Required Steps template.
- [ ] **README.md** — Did I create, delete, or rename a file? Update the Review & Test Status tables.
- [ ] **Agent `permission:` block** — Did I create or change an agent? Validate `edit`/`bash` against the Permission Validation Rule. This is not optional — dispatch-only agents with `edit: allow` are a structural defect.

If a checklist item doesn't apply, mark it `N/A`. If you skip an item without justification, the change is incomplete.

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
| brainstorming | Phase A creative exploration |
| compliance-gate | Tiered gate system (T1/T2/T3/T-ARCH) |
| context7-docs | Fetch up-to-date library/API docs (CLI → MCP → URL fallback) |
| datasheet-verification | Verify claims against source documents |
| flag-protocol | Structured request format for non-PM agents |
| grill-me | Adversarial design review |
| incremental-execution | Unit-by-unit implementation |
| memory-safety | Memory safety review (C/C++ projects) |
| pau-loop | Plan → Apply → Validate loop |
| pipeline | Full pipeline state machine |
| pipeline-passport | Task tracking card |
| post-rejection-correction | Root-cause analysis before retry |
| review-confidence | 0-100 confidence scoring |
| self-audit-checklist | Mandatory pre-verdict checklist |
| silent-failure | Detect silent failure modes |
| systematic-debugging | Structured debugging protocol |
| tdd-cpp | Test-driven development for C++ |
| test-driven-development | Generic TDD loop |
| type-design-review | Type system and API review |
| verification-before-completion | Final verification before marking done |

### Domain Skills (Optional — Project-Specific)

| Skill | Purpose |
|-------|---------|
| ble-protocol | BLE protocol compliance |
| cpp-embedded | Embedded C++ patterns |
| design-taste | Anti-slop frontend design |
| esp-idf | ESP-IDF framework |
| nrf24l01plus | nRF24L01+ radio chip |
| nrf52840-sniffer | nRF52840 sniffer |
| ubertooth | Ubertooth platform |
| ux-patterns | UX interaction patterns and state management |
