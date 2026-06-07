# OpenCode Workflow

A reusable multi-agent validation pipeline, skill system, and project management toolkit for [OpenCode](https://github.com/opencode-ai/opencode)-based development.

## What Is This?

OpenCode Workflow provides the structure for disciplined, multi-agent software development:

- **10 specialist agents** that follow a 3-phase pipeline (Requirements → Build → Verify)
- **8 core skills** that are always installed (assumption-trap, PAU loop, compliance gates, etc.)
- **9 process skills** for design reviews, debugging, testing, and more
- **6 domain skills** for specific tech stacks (nRF24L01+, ESP-IDF, BLE, etc.)
- **Tiered compliance gates** (T1 Mechanical, T2 Architectural, T3 Semantic) enforced at every phase transition
- **Project management scripts** (ticket ID generation, T1 compliance check)
- **An install script** that sets everything up in any project directory

## Quick Start

```bash
# Clone the repository
git clone https://github.com/your-org/opencode-workflow.git

# Install into your project (interactive — selects domain skills)
cd /path/to/your/project
/path/to/opencode-workflow/install.sh

# Or install into a specific directory
/path/to/opencode-workflow/install.sh /path/to/project

# Non-interactive: install everything
/path/to/opencode-workflow/install.sh --non-interactive /path/to/project

# Core-only: skip domain skill selection
/path/to/opencode-workflow/install.sh --core-only /path/to/project
```

After installation, your project will have:

```
your-project/
  .opencode/
    agents/                    # 10 agent definitions
    skills/                    # Core + selected domain skills
    merge/                     # Merge prompts for conflicts (if any)
  docs/
    pipeline/
      scripts/
        t1-check.sh           # T1 mechanical compliance check
    project-management/
      next-id.mjs              # Ticket/epic/ADR ID generator
      counters.json            # ID counters
      open/                    # Open tickets
      backlog/                 # Backlog tickets
      closed/                  # Closed tickets
      epics/                   # Epic definitions
      clarifications/          # Clarification requests
      advisories/              # Advisory flags
      adr/                     # Architecture decision records
      designs/                 # Design documents
      chores/                  # Chores
      reviews/                 # Review records
```

## Skill Loading Protocol

When a task is dispatched, skills are loaded in this order:

1. **`assumption-trap`** — FIRST, always. Halts on ambiguity.
2. **Core skills** — `compliance-gate`, `pipeline`, `pau-loop`, `verification-before-completion`, `self-audit-checklist`, `review-confidence`, `flag-protocol`, `type-design-review`, `silent-failure`
3. **Domain skills** — loaded based on the tech stack in `AGENTS.md` (e.g., `nrf24l01plus` for nRF24L01+ chip, `ble-protocol` for Bluetooth LE)
4. **Phase skills** — loaded based on pipeline phase:
   - Phase A: `brainstorming`, `grill-me`
   - Phase B: `incremental-execution`, `test-driven-development`
   - Phase C: `review-confidence`, `self-audit-checklist`

### Skill Categories

| Category | Skills | Always Installed? |
|----------|--------|-------------------|
| **Core** | assumption-trap, pau-loop, incremental-execution, compliance-gate, pipeline, review-confidence, flag-protocol, self-audit-checklist | ✅ Yes |
| **Process** | brainstorming, grill-me, datasheet-verification, systematic-debugging, test-driven-development, verification-before-completion, memory-safety, type-design-review, silent-failure | ✅ Yes |
| **Domain** | nrf24l01plus, esp-idf, cpp-embedded, ble-protocol, ubertooth, nrf52840-sniffer | ❌ Optional |

## The Pipeline

### Three-Phase Workflow

```
Phase A: REQUIREMENTS & DESIGN  →  Phase B: BUILD (PAU Loop)  →  Phase C: MULTI-AGENT VERIFY
```

### Phase A — Requirements & Design
1. All specialists review the proposal in parallel
2. Dual-Model Challenge: primary pass produces, challenger critiques
3. A-GATE: All specialists must issue APPROVED before Phase B

### Phase B — Build (PAU Loop)
1. Code Architect implements incrementally (one unit at a time)
2. B-UNIT-GATE (T1 + T-ARCH) after each unit
3. B-FINAL-GATE (T1 + T2 + T-ARCH) after all units

### Phase C — Multi-Agent Verify
1. Dual-Model Challenge on the implementation
2. All specialists review in parallel
3. C-GATE: T1 + T3 + T-ARCH must all pass before commit

## Tiered Compliance Gates

| Tier | Type | Who Runs | Checks |
|------|------|----------|--------|
| **T1** | Mechanical | Code Architect (automated) | Build passes, Doxygen, no decision refs, no raw integers, reserved bits |
| **T2** | Architectural | Software Engineer | Platform boundary, namespace hygiene, API surface, no mutable globals |
| **T3** | Semantic | All 6 specialists | Datasheet fidelity, protocol correctness, security, test coverage, docs |
| **T-ARCH** | Architecture + Principles | Software Engineer / Agency Director | Logical consistency, structural soundness, principle alignment, completeness |

Each tier has an **independent 3-retry budget** at each gate. After 3 failures at any tier, escalation to the user.

## Agents

| Agent | Role | Mode |
|-------|------|------|
| `agency-director` | Orchestrator — dispatches tasks to specialists | primary |
| `software-engineer` | Architecture, API design, HAL interfaces | subagent |
| `hardware-engineer` | Datasheet verification, register models | subagent |
| `wireless-expert` | RF protocol compliance, channel mapping | subagent |
| `security-reviewer` | Buffer safety, stack depth, secrets handling | subagent |
| `test-engineer` | Test strategy, static_assert, coverage | subagent |
| `docs-writer` | Doxygen, learning docs, reference verification | subagent |
| `code-architect` | Primary implementation agent (PAU loop) | subagent |
| `memory-safety` | C++ memory safety, RAII, heap analysis | subagent |
| `pm` | Task master — sole authority for creating tasks | subagent |

## Project Management

### Ticket IDs

Use `next-id.mjs` to generate sequentially-numbered IDs:

```bash
# Generate the next ticket ID
node docs/project-management/next-id.mjs ticket
# {"kind":"ticket","ids":["owf-0001"],"dryRun":false}

# Generate 5 ticket IDs at once
node docs/project-management/next-id.mjs ticket 5
# {"kind":"ticket","ids":["owf-0002","owf-0003","owf-0004","owf-0005","owf-0006"],"dryRun":false}

# Other ID types
node docs/project-management/next-id.mjs epic
node docs/project-management/next-id.mjs clarification
node docs/project-management/next-id.mjs adr
node docs/project-management/next-id.mjs advisory
node docs/project-management/next-id.mjs design
node docs/project-management/next-id.mjs chore

# Dry run (preview without updating counters)
node docs/project-management/next-id.mjs ticket --dry-run
```

The ID prefix defaults to `owf` but can be configured:
- Set `ID_PREFIX` environment variable: `ID_PREFIX=myproj node next-id.mjs ticket`
- Edit the default in `next-id.mjs` directly

### Directory Structure

| Directory | Purpose |
|-----------|---------|
| `open/` | Active tickets |
| `backlog/` | Tickets waiting to be started |
| `closed/` | Completed tickets |
| `epics/` | Large feature definitions |
| `clarifications/` | Questions needing answers |
| `advisories/` | Non-blocking flags |
| `adr/` | Architecture Decision Records |
| `designs/` | Design documents |
| `chores/` | Small tasks |
| `reviews/` | Review records |

### Flag Protocol

Non-PM agents raise flags using this format:

```markdown
## Flag: [type] — [short title]

| Field | Value |
|-------|-------|
| Type | task / clarification / decision / advisory |
| Priority | critical / high / medium / low |
| Raised by | Agent role |
| Blocking | yes / no |

## Description
What was found and why it needs attention.

## Evidence
Code snippets, datasheet references, or PoC.

## Suggested action
What the flagging agent recommends.
```

Only the PM agent creates actual tasks. All other agents raise flags.

## How to Add Your Own Domain Skills

1. Create a new directory under `.opencode/skills/your-skill-name/`
2. Create a `SKILL.md` file with YAML frontmatter:

```yaml
---
name: your-skill-name
description: "One-line description of when to trigger this skill (1-1024 characters)."
---

# Your Skill Title

## Purpose
What this skill provides and when to use it.

## When to Trigger
List the conditions that should cause OpenCode to load this skill.

## Content
Your skill content here — rules, checklists, patterns, gotchas.

## Self-Reflection Clause
After fixing any bug, ask:
1. Why was this bug missed?
2. What procedural safeguard would have caught it?
3. Update this skill or the learning docs.
```

3. Reference it in `AGENTS.md` under the Skill Registry:

```yaml
| your-skill-name | Trigger condition description |
```

**Important:** The `name` field in the YAML frontmatter must match the directory name exactly.

## How to Customize Agents for Your Project

Agent files are plain Markdown with YAML frontmatter. To customize:

1. Edit the `description` field to match your project's context
2. Modify the skill loading list in the Initialisation Protocol section
3. Adjust the `model` field (e.g., `anthropic/claude-opus-4`, `openai/gpt-4o`)
4. Set `mode: primary` for your orchestrator, `mode: subagent` for all others
5. Adjust the `permission` block for each agent's access needs

Example agent frontmatter:

```yaml
---
description: "Your project's software architect. Reviews API design, component boundaries, HAL interfaces."
mode: subagent
model: anthropic/claude-sonnet-4-20250514
permission:
  edit: deny
  bash: allow
  skill: allow
  task: deny
---
```

## How the Install Script Handles Conflicts

The install script is **idempotent** — running it multiple times is safe.

For each file, the script checks whether the existing file has been modified since the last install:

| Situation | Action |
|-----------|--------|
| File doesn't exist | Create it |
| File exists, unmodified since last install | Update to new version |
| File exists, modified by the user | Create a merge prompt at `.opencode/merge/<filename>.merge.md` |

The merge prompt contains both the new version (from opencode-workflow) and the current version (from your project), with instructions to resolve the conflict and remove the merge file when done.

**`counters.json` is never overwritten** — your project's ticket/epic/ADR counter state is always preserved.

The T1 check script is automatically configured with your project's root directory during installation.

## Compatibility with OpenCode Config Format

This system follows the official OpenCode configuration format:

**Agents** (`.opencode/agents/*.md`):
- YAML frontmatter with `description` (required), `mode`, `model`, `temperature`, `permissions`
- File name becomes the agent name (e.g., `code-architect.md` → `code-architect` agent)
- Located in `.opencode/agents/` (project) or `~/.config/opencode/agents/` (global)

**Skills** (`.opencode/skills/<name>/SKILL.md`):
- YAML frontmatter with `name` and `description` (both required)
- `name` must match the directory name
- Description must be 1–1024 characters
- Located in `.opencode/skills/` (project) or `~/.config/opencode/skills/` (global)

## Repository Structure

```
opencode-workflow/
  README.md                    # This file
  LICENSE                      # MIT license
  install.sh                   # Installation script
  agents/                      # 10 agent definitions
    agency-director.md
    software-engineer.md
    hardware-engineer.md
    wireless-expert.md
    security-reviewer.md
    test-engineer.md
    docs-writer.md
    code-architect.md
    memory-safety.md
    pm.md
  skills/
    core/                      # 17 core + process skills (always installed)
      assumption-trap/SKILL.md
      pau-loop/SKILL.md
      incremental-execution/SKILL.md
      compliance-gate/SKILL.md
      pipeline/SKILL.md
      review-confidence/SKILL.md
      flag-protocol/SKILL.md
      self-audit-checklist/SKILL.md
      brainstorming/SKILL.md
      grill-me/SKILL.md
      datasheet-verification/SKILL.md
      systematic-debugging/SKILL.md
      test-driven-development/SKILL.md
      verification-before-completion/SKILL.md
      memory-safety/SKILL.md
      type-design-review/SKILL.md
      silent-failure/SKILL.md
    domain/                    # 6 domain skills (optional)
      nrf24l01plus/SKILL.md
      esp-idf/SKILL.md
      cpp-embedded/SKILL.md
      ble-protocol/SKILL.md
      ubertooth/SKILL.md
      nrf52840-sniffer/SKILL.md
  scripts/
    t1-check.sh                # T1 mechanical compliance check
    next-id.mjs                # Ticket/epic/ADR ID generator
    counters.json              # Template counters file
```

## The Self-Reflection Clause

Every agent and skill includes a self-reflection clause. After fixing any bug or resolving an issue:

1. **Why was this bug missed?** — What review, test, or protocol gap allowed it through?
2. **What procedural safeguard would have caught it?** — What specific check or step would have prevented it?
3. **Update the knowledge base** — Add the lesson to the relevant skill or learning doc.

This ensures that every failure becomes a permanent improvement to the workflow.

## License

MIT License — see [LICENSE](LICENSE) for details.