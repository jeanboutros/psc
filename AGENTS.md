# AGENTS.md — Project Configuration

## Project Identity

| Field | Value |
|-------|-------|
| Name | PSC — Politburo Standing Committee |
| Repository | opencode-workflow |
| License | MIT |

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

If a change touches multiple docs, each doc update may be bundled with the triggering change when they are tightly coupled (per the Commit Granularity rule).

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
