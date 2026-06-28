---
name: ci-cd-pipeline
description: "CI/CD pipeline design principles, deployment strategies, environment management, build matrix patterns, artifact management, and pipeline-as-code best practices. Platform-agnostic — loaded alongside platform-specific skills like github-actions."
---

# CI/CD Pipeline Design

## Purpose

This skill provides platform-agnostic CI/CD pipeline design principles. It covers deployment strategies, environment management, build optimization, artifact handling, and pipeline security patterns. For platform-specific implementation details, load the corresponding domain skill (e.g. `github-actions` for GitHub Actions).

## When to Trigger

- Designing a new CI/CD pipeline
- Reviewing an existing pipeline for correctness or security
- Choosing a deployment strategy
- Configuring build matrices and caching
- Setting up multi-environment deployment pipelines
- Auditing pipeline security posture

---

## Pipeline Design Principles

### Core Tenets

1. **Pipeline as Code** — Pipeline definitions are version-controlled alongside application code. No manual configuration in CI/CD platform UIs.
2. **Idempotency** — Pipeline runs produce the same result given the same inputs. No reliance on mutable external state.
3. **Fast Feedback** — Fail fast. Run cheapest checks first (lint → unit test → integration test → e2e).
4. **Least Privilege** — Pipeline credentials have the minimum permissions needed. No shared service accounts with broad access.
5. **Immutable Artifacts** — Build once, deploy many. Artifacts are built once and promoted through environments without rebuilding.
6. **Observability** — Pipeline status, duration, and failure rates are visible and alertable.

### Pipeline Stages (Canonical Order)

```
TRIGGER → CHECKOUT → LINT → BUILD → UNIT TEST → INTEGRATION TEST → SECURITY SCAN → ARTIFACT → DEPLOY STAGING → SMOKE TEST → DEPLOY PRODUCTION
```

Each stage gates the next. A failure at any stage halts the pipeline.

---

## Deployment Strategies

### Blue-Green Deployment

Two identical environments (blue = current, green = new). Traffic switches atomically.

| Pros | Cons |
|------|------|
| Zero-downtime switch | Double infrastructure cost |
| Instant rollback (switch back) | Database migration complexity |
| Full testing in production-like env | Session state handling |

**When to use:** Critical services where downtime is unacceptable and infrastructure cost is manageable.

### Canary Deployment

New version deployed alongside old. Small percentage of traffic routed to new version, gradually increased.

| Pros | Cons |
|------|------|
| Real-user validation with limited blast radius | Complex traffic routing |
| Gradual confidence building | Longer deployment window |
| Automated rollback on error rate spike | Requires sophisticated monitoring |

**When to use:** High-traffic services where real-user validation is essential before full rollout.

### Rolling Deployment

Instances updated one at a time or in batches. Old and new versions coexist briefly.

| Pros | Cons |
|------|------|
| No additional infrastructure | Rollback is slow (reverse the roll) |
| Gradual rollout | Brief period of mixed versions |
| Works with most orchestrators | Capacity reduced during rollout |

**When to use:** Containerized services on Kubernetes or similar orchestrators.

### Feature Flags

Code deployed dark, features toggled on/off at runtime.

| Pros | Cons |
|------|------|
| Decouples deploy from release | Flag debt and cleanup burden |
| Instant rollback (turn flag off) | Testing matrix explosion |
| A/B testing and gradual rollout | Requires flag management infrastructure |

**When to use:** Teams practicing continuous delivery who need fine-grained release control.

---

## Environment Management

### Environment Hierarchy

| Environment | Purpose | Protection |
|-------------|---------|------------|
| `development` | Developer sandbox, feature branches | None — auto-deploy on push |
| `staging` | Pre-production validation, integration testing | Required reviewer approval |
| `production` | Live user-facing environment | Required reviewer approval + branch protection |

### Environment Configuration

- **Secrets per environment** — API keys, database URLs, certificates scoped to each environment
- **Configuration as code** — Environment variables defined in pipeline config, not manually in platform UI
- **Parity principle** — Staging mirrors production as closely as possible (same infrastructure, same data shape)
- **Ephemeral environments** — Per-PR or per-branch environments created on demand, destroyed after merge

---

## Build Optimization

### Caching Strategy

| Cache Target | Key Pattern | Invalidation |
|-------------|-------------|--------------|
| Dependencies | `os-lang-hash(lockfile)` | Lockfile changes |
| Build output | `os-branch-hash(src)` | Source changes |
| Docker layers | Layer caching via buildkit | Dockerfile changes |
| Test results | `os-branch-hash(test-src)` | Test source changes |

### Build Matrix Design

```yaml
# Example: test across OS × language version
matrix:
  os: [ubuntu-latest, windows-latest, macos-latest]
  version: [18, 20, 22]
  exclude:
    - os: windows-latest
      version: 18
  include:
    - os: ubuntu-latest
      version: 23
      experimental: true
```

**Rules:**
- `fail-fast: false` for matrices where failures are independent
- `fail-fast: true` when all matrix jobs must pass
- Use `exclude` to remove known-incompatible combinations
- Use `include` to add special cases (e.g. experimental versions)
- Maximum matrix size: 256 jobs (platform limit)

### Parallelization

- Independent jobs run in parallel by default
- Use `needs` only for true dependencies
- Split large test suites across parallel jobs by test sharding
- Use job outputs to pass data between dependent jobs

---

## Artifact Management

### Build-Once Principle

Artifacts are built exactly once (in the build stage) and promoted through environments:

```
BUILD → artifact → STAGING DEPLOY → artifact → PRODUCTION DEPLOY
```

Never rebuild for each environment. Rebuilding introduces configuration drift and invalidates testing.

### Artifact Types

| Type | Storage | Retention |
|------|---------|-----------|
| Build outputs (binaries, packages) | Pipeline artifact store | 1-90 days |
| Docker images | Container registry | Per tag policy |
| Test reports | Pipeline artifact store | 30 days |
| Coverage reports | Pipeline artifact store or dedicated service | 30 days |
| Provenance attestations | Pipeline artifact store | Permanent |

### Provenance and SBOM

- Generate SLSA provenance attestations for build artifacts
- Generate Software Bill of Materials (SBOM) for dependency transparency
- Verify attestations before deployment

---

## Pipeline Security

### Credential Management

| Principle | Implementation |
|-----------|---------------|
| Least privilege | Scoped service accounts per pipeline stage |
| Short-lived credentials | OIDC tokens instead of long-lived secrets |
| Secret rotation | Automated rotation with audit trail |
| No secrets in logs | Masking, structured logging, log scanning |
| Environment isolation | Secrets scoped to specific environments |

### Pipeline Code Review

- Pipeline definition files require the same review rigor as application code
- Use CODEOWNERS to require pipeline team approval for workflow changes
- Run security scanners against pipeline definitions (detect script injection, excessive permissions)
- Pin all external actions and container images to immutable references (SHA digests)

### Supply Chain Security

- Verify artifact signatures before deployment
- Scan dependencies for known vulnerabilities (Snyk, Dependabot, OWASP Dependency-Check)
- Scan container images for vulnerabilities (Trivy, Grype, Docker Scout)
- Generate and verify SLSA provenance
- Use OpenSSF Scorecard to assess pipeline security posture

---

## Pipeline Monitoring

### Key Metrics

| Metric | What It Tells You |
|--------|-------------------|
| Pipeline duration | Build/deploy speed; identifies bottlenecks |
| Failure rate | Stability; spike indicates regression |
| Mean time to recovery (MTTR) | How fast can you roll back |
| Deployment frequency | Throughput; DORA metric |
| Change failure rate | Quality; DORA metric |
| Queue time | Runner availability; scaling indicator |

### Alerting

- Alert on pipeline failure for default branch
- Alert on deployment failure to production
- Alert on security scan findings above threshold
- Alert on pipeline duration exceeding baseline

---

## Rollback Strategy

### Automated Rollback Triggers

- Error rate spike after deployment (monitoring threshold)
- Health check failure on new version
- Smoke test failure post-deployment
- Manual abort during canary phase

### Rollback Procedure

1. **Stop** — Halt traffic to new version
2. **Restore** — Route traffic to previous known-good version
3. **Investigate** — Analyze logs, metrics, and error traces from failed deployment
4. **Fix forward or revert** — Decide whether to fix the issue in a new version or revert the code change
5. **Post-mortem** — Document root cause and preventive measures

---

## Self-Reflection Clause

After any CI/CD pipeline failure or deployment incident, the responsible agent MUST ask:

1. **Why was this failure not caught earlier?** — What stage, check, or gate should have caught it?
2. **What procedural safeguard would have caught it?** — What specific test, scan, or approval step would have prevented it?
3. **Update the knowledge base** — Add the lesson to this skill or the platform-specific domain skill.
