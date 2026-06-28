---
name: github
description: "Git operations for PSC: conventional commits, SSH agent socket authentication, safe push, commit granularity rules. Triggered by commit, push, or any git operation."
---

# GitHub Workflow

## Purpose

Operationalizes the Commit Rules from `AGENTS.md` into executable git workflows. Every commit and push operation MUST follow this skill. It ensures all commits conform to the Conventional Commits v1.0.0 spec, pass pre-push safety checks, and resolve SSH authentication issues that arise in subagent environments.

## When to Trigger

- User says "commit", "push", or any git operation
- An agent needs to stage, commit, or push changes
- Auto-loaded alongside `verification-before-completion` — no push claim without fresh `git push` output

---

## Conventional Commits v1.0.0

Per the canonical spec at https://www.conventionalcommits.org/en/v1.0.0/:

### Format

```
<type>[optional scope][!]: <description>

[body — mandatory in this project]

[optional footer(s)]
```

### Type Table (PSC)

| Type | When to Use |
|------|-------------|
| `feat` | New feature — agent, skill, script, or capability (SemVer MINOR) |
| `fix` | Bug fix in an existing file (SemVer PATCH) |
| `docs` | Documentation-only changes (README, pipeline.md, AGENTS.md) |
| `refactor` | Code restructuring with no behaviour change |
| `chore` | Maintenance (counters reset, dependency updates, file moves) |
| `style` | Formatting, whitespace, punctuation — no logic change |
| `test` | Adding or updating tests |
| `build` | Build system or external dependency changes |
| `ci` | CI configuration changes |
| `perf` | Performance improvement with no functional change |
| `revert` | Reverts a previous commit (body SHOULD reference the reverted SHA) |

### Scope Convention

Use the file or directory name as scope:

```
feat(product-designer): add discovery protocol for UI projects
fix(next-id): correct default prefix fallback
docs(readme): add human review status table
refactor(compliance-gate): remove project-specific datasheet refs
```

### Breaking Changes

A breaking change MUST either:
- Append `!` after the type/scope: `feat(api)!: remove legacy endpoint`
- Include a `BREAKING CHANGE:` footer in the commit body

Both may be used together.

### Commit Body (Mandatory)

Every commit MUST include a body describing:
1. **What** changed (the specific modification)
2. **Why** it changed (the motivation or issue it addresses)

The body begins one blank line after the description.

Example:
```
feat(post-rejection-correction): add root-cause correction protocol

Add new core skill that requires agents to classify gate failures
into five root-cause categories (RC-1 through RC-5) before retrying.
This prevents retry loops from repeating the same class of mistake
without learning from the rejection.
```

### Bad Examples

| Bad | Good |
|-----|------|
| `update readme` | `docs(readme): add human review status table for all project files` |
| `fix stuff` | `fix(pipeline): replace idf.py build with generic build command reference` |
| `add files` | `feat(ui-engineer): add frontend implementation agent for UI projects` |
| `changes` | `refactor(t1-check): remove ESP32-specific build checks` |

---

## Commit Granularity

### Default Rule

**One file per commit is the default.** Each file gets its own commit with a clear message.

### Bundling Rules

- **Bundle only when tightly coupled** — files that are part of the same logical change and would be broken if committed separately:
  - A new agent + its entry in the pipeline routing table
  - A new skill + a reference to it in compliance-gate
  - A rename that touches an import and its source
- **Never bundle unrelated changes** — "cleaned up a few things" commits are banned
- **When in doubt, split** — two small commits are better than one muddled commit

### Decision Tree

| Scenario | Action |
|----------|--------|
| 1 file | One commit |
| 2-5 files, same component | One commit with scope |
| 2-5 files, different components | Multiple commits |
| Design doc + associated ADR | One commit (tightly coupled) |
| Design doc + skill update | Two commits (different domains) |

---

## Commit Retry Protocol

Do NOT create "fix typo" follow-up commits.

If pre-commit hook rejects:
```bash
git add <fixed-files>
git commit --amend
```

If already pushed:
```bash
git commit --amend --no-edit
```

---

## SSH Authentication — The Agent Socket Problem

Subagents do NOT inherit `SSH_AUTH_SOCK`. This causes every `git push` to fail with `Permission denied (publickey)` when running inside subagent sessions.

### The Solution

Every push command MUST use the explicit agent socket:

```bash
SSH_AUTH_SOCK=~/.ssh/agent.sock git push origin main
```

### Pre-Flight Check (Run Before ANY Push)

```bash
SSH_AUTH_SOCK=~/.ssh/agent.sock ssh -T git@github.com 2>&1 | grep -q "successfully authenticated" || {
    echo "SSH check failed — cannot push"
    exit 1
}
```

### Resolution Protocol When Push Fails

1. `ls ~/.ssh/agent.sock` — verify socket exists
2. `cat ~/.ssh/config` — verify IdentityFile for Host github.com
3. `ssh -i ~/.ssh/github_key -T git@github.com` — direct key test
4. If all fail: **STOP**. Report fingerprint: `ssh-keygen -lf ~/.ssh/github_key.pub`
5. **Never attempt password-based auth.** SSH keys only.

---

## Push Safety Rules

### Pre-Push Verification (4 Checks)

1. **Conventional format:** `git log --oneline origin/main..HEAD` — verify all commits follow conventional format
2. **No WIP:** `git log --oneline -10 | grep -iE 'wip|tmp|fixup|todo.commit'` — must return empty
3. **Logical grouping:** `git diff --stat origin/main..HEAD` — verify file groupings make sense
4. **SSH:** Run pre-flight SSH authentication check

### Force-Push is FORBIDDEN

`git push --force origin main` is **never** permitted. If the branch has diverged:

```bash
git pull --rebase origin main
SSH_AUTH_SOCK=~/.ssh/agent.sock git push origin main
```

### Post-Push Verification

```bash
git log --oneline -5
git log --oneline origin/main -5
```

Both outputs MUST match — all local commits must be visible on the remote.

---

## After Every Push

Per AGENTS.md Documentation-Update Rule, update `README.md` if the push includes:
- New files, deleted files, or renamed files
- New components or skill entries
- Status changes (Phase A→B, review pass→fail)

---

## Destructive Operations Safety

### FORBIDDEN Without Prior Safeguard

These operations **MUST NOT** be run when there are uncommitted changes in the working tree:

| Operation | Risk |
|-----------|------|
| `git reset --hard` | Discards ALL uncommitted changes irreversibly |
| `git reset --hard HEAD~N` | Discards uncommitted changes AND rewinds history |
| `git checkout -- <file>` | Discards unstaged changes in a file |
| `git clean -fd` | Deletes untracked files and directories |
| `git stash drop` | Permanently deletes stashed changes |

### Mandatory Pre-Check

Before running ANY destructive git operation, run this check and verify the output:

```bash
git status --porcelain
```

- If the output is **empty** — safe to proceed (no uncommitted changes exist)
- If the output is **non-empty** — **STOP**. There is uncommitted work at risk of being lost.

### Resolution When Uncommitted Work Exists

1. **Commit the work first** (use this skill's commit workflow)
2. **Stash it first:** `git stash push -m "safety stash before destructive op"`
3. **Abort the destructive operation** — never proceed with uncommitted changes present

### Pre-Check Wrapper

Use this pattern to guard any destructive git operation:

```bash
# Guard: refuse destructive operations if working tree is dirty
if [ -n "$(git status --porcelain)" ]; then
    echo "REFUSING: uncommitted changes would be lost. Commit or stash first."
    exit 1
fi
# Only then proceed
git reset --hard HEAD~1
```

---

## Troubleshooting Reference

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| `Permission denied (publickey)` | Subagent missing `SSH_AUTH_SOCK` | `SSH_AUTH_SOCK=~/.ssh/agent.sock git push origin main` |
| `Could not read from remote` | Wrong remote or no network | `git remote -v`, verify connectivity |
| `fatal: not a git repository` | Wrong working directory | `cd` to repo root |
| `Your branch is ahead of origin/main by N commits` | Unpushed work exists | Informational — not an error |
| `merge conflict` | Diverged history | `git pull --rebase origin main` — NEVER force-push |
| `error: failed to push some refs` | Remote has newer commits | `git pull --rebase` then retry |
| Commit hook rejected | Bad commit message | `git commit --amend` with corrected message |
| `git reset` requested with dirty working tree | Uncommitted changes would be lost | Run `git status --porcelain` first. If non-empty: commit or stash before reset. |

---

## Bash Snippet Quick Reference

**All shell scripts MUST start with `set -euo pipefail`:**

- `set -e` — exit immediately on any command failure
- `set -u` — treat unset variables as errors
- `set -o pipefail` — pipeline fails if any command in the pipe fails

```bash
#!/usr/bin/env bash
set -euo pipefail

# Stage and commit
git add <file1> <file2>
git commit -m "docs(c03): fix References format" -m "What: converted table to [N] citations" -m "Why: per AGENTS.md Mandatory Citations Rule"

# Verify before push
git log --oneline origin/main..HEAD

# Pre-flight SSH check
SSH_AUTH_SOCK=~/.ssh/agent.sock ssh -T git@github.com

# Push (always with explicit SSH agent socket)
SSH_AUTH_SOCK=~/.ssh/agent.sock git push origin main

# Verify after push
git log --oneline -5
git log --oneline origin/main -5

# Diverged branch recovery (NEVER force-push)
git pull --rebase origin main
SSH_AUTH_SOCK=~/.ssh/agent.sock git push origin main

# Amend after pre-commit hook rejection
git add <fixed-files>
git commit --amend --no-edit
```

---

## Self-Reflection Clause

After any git failure:

1. **Why did this failure occur?** — What specific condition or missing check caused it?
2. **What procedural check would have prevented it?** — What should have been verified before the operation?
3. **Update the Troubleshooting Reference table** — Add new symptom/diagnosis/fix rows so the same class of failure is caught earlier next time.
