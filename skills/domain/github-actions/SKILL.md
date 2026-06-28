---
name: github-actions
description: "GitHub Actions workflow authoring, syntax reference, security hardening, and best practices. Covers workflow YAML structure, events, jobs, runners, secrets, OIDC, action pinning, Dependabot, and marketplace actions. Load when designing or reviewing GitHub Actions CI/CD pipelines."
---

# GitHub Actions

## Purpose

This skill provides the authoritative reference for GitHub Actions workflow design, syntax, security hardening, and operational best practices. It is based on the official GitHub Actions documentation at `docs.github.com/en/actions`.

## When to Trigger

- Designing or reviewing GitHub Actions workflows
- Setting up CI/CD pipelines on GitHub
- Auditing workflow security (secrets, permissions, script injection)
- Configuring deployment environments and protection rules
- Migrating CI/CD from another platform to GitHub Actions
- Setting up Dependabot for action version updates

---

## Workflow Fundamentals

### File Location and Naming

Workflow files are YAML (`.yml` or `.yaml`) stored in `.github/workflows/` at the repository root. GitHub discovers and runs all workflow files in this directory.

### Core Structure

```yaml
name: CI
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm test
```

### Key Top-Level Fields

| Field | Required | Purpose |
|-------|----------|---------|
| `name` | No | Display name in Actions tab |
| `run-name` | No | Dynamic run name using expressions |
| `on` | Yes | Events that trigger the workflow |
| `permissions` | No | GITHUB_TOKEN scope (default: read/write) |
| `env` | No | Environment variables for all jobs |
| `jobs` | Yes | Work items executed on runners |
| `concurrency` | No | Prevent parallel runs of the same group |

---

## Events (`on`)

### Common Event Types

| Event | Use Case |
|-------|----------|
| `push` | Code pushed to repository |
| `pull_request` | PR opened, synchronized, reopened |
| `schedule` | Cron-based scheduled runs |
| `workflow_dispatch` | Manual trigger with optional inputs |
| `workflow_call` | Reusable workflow called by another |
| `workflow_run` | Triggered by completion of another workflow |
| `release` | Release published, created, edited |
| `issues` | Issue opened, labeled, etc. |
| `pull_request_target` | PR from fork with base repo context (elevated permissions — use with caution) |

### Event Filters

```yaml
on:
  push:
    branches: [main, 'releases/**']
    paths: ['src/**', '!src/docs/**']
  pull_request:
    types: [opened, synchronize, reopened]
    branches-ignore: ['dependabot/**']
  schedule:
    - cron: '0 9 * * 1-5'
```

### Activity Types

Some events support `types` to narrow triggering conditions:

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
  issues:
    types: [opened, labeled]
```

---

## Jobs

### Job Structure

```yaml
jobs:
  <job_id>:
    name: <display name>
    runs-on: <runner label>
    needs: [<job_id>, ...]
    if: <condition>
    permissions:
      contents: read
    env:
      KEY: value
    concurrency:
      group: <group-name>
      cancel-in-progress: true
    defaults:
      run:
        shell: bash
        working-directory: ./src
    steps:
      - name: <step name>
        uses: <action-reference>
        with:
          <input>: <value>
      - name: <step name>
        run: <shell command>
        env:
          KEY: value
```

### Runner Selection

| Label | OS | Use Case |
|-------|-----|----------|
| `ubuntu-latest` | Ubuntu Linux | General purpose, Docker support |
| `windows-latest` | Windows Server | .NET, Windows-specific builds |
| `macos-latest` | macOS | iOS/macOS builds, Xcode |
| `ubuntu-24.04-arm` | Ubuntu ARM64 | ARM-native builds |
| `self-hosted` | Custom | Specific hardware, private network access |

### Job Dependencies

Jobs run in parallel by default. Use `needs` to create sequential dependencies:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps: [ ... ]
  test:
    needs: build
    runs-on: ubuntu-latest
    steps: [ ... ]
  deploy:
    needs: [build, test]
    runs-on: ubuntu-latest
    steps: [ ... ]
```

### Matrix Strategies

```yaml
jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest]
        node: [18, 20, 22]
        exclude:
          - os: windows-latest
            node: 18
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node }}
```

---

## Steps and Actions

### Step Types

| Type | Syntax | Purpose |
|------|--------|---------|
| Action | `uses: <owner>/<repo>@<ref>` | Reusable action from marketplace or repo |
| Shell | `run: <command>` | Inline shell script |
| Docker | `uses: docker://<image>:<tag>` | Run in Docker container |

### Common Marketplace Actions

| Action | Purpose |
|--------|---------|
| `actions/checkout@v4` | Check out repository code |
| `actions/setup-node@v4` | Set up Node.js environment |
| `actions/setup-python@v5` | Set up Python environment |
| `actions/setup-java@v4` | Set up Java environment |
| `actions/setup-go@v5` | Set up Go environment |
| `actions/cache@v4` | Cache dependencies |
| `actions/upload-artifact@v4` | Upload build artifacts |
| `actions/download-artifact@v4` | Download build artifacts |
| `actions/create-release@v1` | Create GitHub release |
| `docker/login-action@v3` | Log in to container registry |
| `docker/build-push-action@v6` | Build and push Docker images |
| `github/codeql-action/init@v3` | Initialize CodeQL analysis |
| `ossf/scorecard-action@v2` | OpenSSF Scorecard security scan |

---

## Secrets and Authentication

### GITHUB_TOKEN

Every workflow run automatically receives a `GITHUB_TOKEN` secret. Its permissions should follow the principle of least privilege:

```yaml
permissions:
  contents: read
  packages: write
  id-token: write
```

### Repository and Environment Secrets

```yaml
steps:
  - run: deploy.sh
    env:
      API_KEY: ${{ secrets.API_KEY }}
```

Environment secrets with protection rules:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps: [ ... ]
```

### OpenID Connect (OIDC)

For cloud provider authentication without long-lived secrets:

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789:role/github-actions
          aws-region: us-east-1
```

---

## Security Hardening Checklist

Per the official GitHub Actions security hardening guide (`docs.github.com/en/actions/security-guides/security-hardening-for-github-actions`):

### Secrets Management

- [ ] GITHUB_TOKEN permissions set to minimum required (prefer `contents: read` default)
- [ ] No secrets stored as plaintext in workflow files
- [ ] Sensitive generated values registered with `::add-mask::`
- [ ] Structured data (JSON, YAML) not used as secret values
- [ ] Secrets rotated periodically
- [ ] Environment secrets protected by required reviewers

### Action Security

- [ ] Third-party actions pinned to full-length commit SHA
- [ ] Action source code audited for secret handling
- [ ] Verified creator badge checked on GitHub Marketplace
- [ ] Dependabot configured for action version updates
- [ ] Dependency graph enabled to track action dependencies

### Script Injection Prevention

- [ ] Untrusted input (PR titles, issue bodies, commit messages) never interpolated directly into `run:` scripts
- [ ] Intermediate environment variables used for untrusted input
- [ ] Actions preferred over inline scripts for processing context values

### Workflow Triggers

- [ ] `pull_request_target` avoided unless absolutely necessary
- [ ] `workflow_run` used for privilege separation instead of `pull_request_target`
- [ ] Workflows triggered on `pull_request_target` or `workflow_run` do not check out untrusted code
- [ ] CodeQL scanning enabled for workflow files
- [ ] OpenSSF Scorecard action configured

### Runner Security

- [ ] Self-hosted runners not used for public repositories
- [ ] Self-hosted runners organized into groups with access controls
- [ ] Just-in-time (JIT) runners used for ephemeral execution
- [ ] Runner environment audited for sensitive data (SSH keys, API tokens)

### Code Review

- [ ] Workflow files covered by CODEOWNERS
- [ ] Dependency review action enabled on PRs
- [ ] Workflow changes require approval from designated reviewers

---

## Caching and Artifacts

### Dependency Caching

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.npm
    key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-node-
```

### Artifact Upload

```yaml
- uses: actions/upload-artifact@v4
  with:
    name: build-output
    path: dist/
    retention-days: 7
```

### Artifact Attestations

```yaml
- uses: actions/attest-build-provenance@v2
  with:
    subject-path: dist/my-app
```

---

## Deployment Environments

### Environment Configuration

```yaml
jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    environment:
      name: staging
      url: https://staging.example.com
    steps: [ ... ]

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://example.com
    steps: [ ... ]
```

### Concurrency Control

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

---

## Reusable Workflows

### Caller

```yaml
jobs:
  call-workflow:
    uses: octo-org/example-repo/.github/workflows/reusable.yml@main
    with:
      node-version: '20'
    secrets:
      token: ${{ secrets.PAT }}
```

### Called Workflow

```yaml
on:
  workflow_call:
    inputs:
      node-version:
        required: true
        type: string
    secrets:
      token:
        required: true
    outputs:
      result:
        value: ${{ jobs.build.outputs.output1 }}

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      output1: ${{ steps.build.outputs.result }}
    steps:
      - id: build
        run: echo "result=success" >> $GITHUB_OUTPUT
```

---

## Dependabot for Actions

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      actions:
        patterns:
          - "*"
```

---

## Self-Reflection Clause

After any CI/CD pipeline failure or security finding, the responsible agent MUST ask:

1. **Why was this not caught earlier?** — What review, test, or automation gap allowed it through?
2. **What procedural safeguard would have caught it?** — What specific check, gate, or automated scan would have prevented it?
3. **Update the knowledge base** — Add the lesson to this skill or the ci-cd-pipeline skill.
