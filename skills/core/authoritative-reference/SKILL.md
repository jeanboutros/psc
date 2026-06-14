---
name: authoritative-reference
description: "Mandatory referencing protocol. Every factual claim, implementation decision, and review finding MUST cite an authoritative source. Agents must search the web, fetch official documentation, and verify against the latest version before acting. Challengers validate that references are present, authoritative, and correctly applied."
---

# Authoritative Reference Protocol

## Purpose

No agent may rely solely on training data or memory for any claim, implementation decision, or review finding. Every piece of information that has an authoritative source MUST be verified against that source before use, and the reference MUST be cited in the agent's output.

This skill transforms all agents from "I think" to "I verified, and here is the proof."

## When to Trigger

- **Before writing any code** that uses a library, framework, language feature, or protocol
- **Before making any factual claim** about a spec, standard, behaviour, or limit
- **Before recommending an approach** — best-practices must come from the authority, not memory
- **During review** — verify that the implementation actually applies what the reference says
- **During challenge** — validate that references are present, authoritative, and correctly applied

**Do NOT trigger** for project-internal conventions already documented in AGENTS.md or project files.

---

## The Iron Rules

### Rule 1 — Verify Before Acting

Before writing code, making a claim, or recommending an approach, the agent MUST:

1. **Identify the authoritative source** for the information
2. **Fetch or search** for the latest version of that source
3. **Read the relevant section** of the source
4. **Verify** that the agent's understanding matches what the source actually says
5. **Cite** the source in the output

If the source contradicts the agent's initial understanding, the agent MUST follow the source, not its memory.

### Rule 2 — Cite with Academic Rigour

Every factual claim, implementation decision, and review finding MUST include a citation. Acceptable citation formats:

| Source Type | Citation Format | Example |
|-------------|----------------|---------|
| Official documentation | `[Source: <URL>, accessed <date>]` | `[Source: https://docs.python.org/3/library/asyncio.html, accessed 2025-01-15]` |
| Context7 lookup | `[Context7: <library>/<version>, "<query>"]` | `[Context7: /expressjs/express/v4.21, "error handling middleware"]` |
| Specification / RFC | `[Spec: <name>, Section <X.Y>]` | `[Spec: RFC 7540, Section 5.3.1]` |
| Manufacturer datasheet | `[Datasheet: <part>, p.<page>, Table/Fig <n>]` | `[Datasheet: nRF52840, p.142, Table 28]` |
| Well-architected framework | `[Framework: <name>, Section <X>]` | `[Framework: AWS Well-Architected, Reliability Pillar, REL-01]` |
| Peer-reviewed paper | `[Paper: <author>, <year>, "<title>"]` | `[Paper: Dijkstra, 1968, "Go To Statement Considered Harmful"]` |
| Official standard | `[Standard: <name>, Clause <n>]` | `[Standard: ISO 27001:2022, Clause A.8.1]` |

### Rule 3 — Seek Beyond Implementation Details

When verifying against a source, agents MUST NOT stop at "does this API exist?" They MUST also seek:

| Category | What to Look For |
|----------|-----------------|
| Best practices | The publisher's recommended approach, not just any approach that works |
| Gotchas | Common mistakes, pitfalls, warnings, deprecation notices |
| Production-grade recommendations | Scaling, performance, security, observability guidance |
| Version-specific changes | Breaking changes, migration guides, feature flags |
| Anti-patterns | Patterns the publisher explicitly warns against |
| Alternatives | When the publisher recommends a different approach for the use case |

### Rule 4 — Challenger Validation Duty

All challenger agents have an **additional responsibility** beyond their primary challenge role:

1. **Reference presence check** — Every claim in the primary agent's output MUST have at least one citation. Flag any uncited claims.
2. **Reference authority check** — Verify that cited sources are authoritative (official docs, spec, manufacturer, recognized authority). Flag non-authoritative sources (blog posts without citations, Stack Overflow answers, AI-generated content).
3. **Reference accuracy check** — Fetch the cited source and verify that it actually says what the primary agent claims it says. Flag misattributions.
4. **Implementation alignment check** — Verify that the code or design actually implements what the reference recommends. Flag implementations that cite a reference but do the opposite or something different.
5. **Completeness check** — Verify that the primary agent sought best practices, gotchas, and production-grade recommendations — not just API existence. Flag "shallow verification" where the reference was checked but only for surface-level facts.

---

## Verification Protocol by Domain

### Programming and Libraries

```
1. Identify the library/framework/language and its current version
2. Use Context7 (CLI → MCP → URL fallback) to fetch the latest docs
3. Verify: API signatures, parameter types, return values, error handling
4. Seek: Best practices, migration guides, deprecation notices, security advisories
5. Seek: Production-grade patterns (connection pooling, error boundaries, observability)
6. Cite: [Context7: <library>/<version>, "<query>"] or [Source: <official-docs-URL>]
```

### Protocols and Standards (BLE, HTTP, RFCs)

```
1. Identify the specification and its version/revision
2. Fetch the official specification document from the authority's website
3. Verify: Protocol behaviour, state transitions, mandatory vs optional fields
4. Seek: Common implementation mistakes, errata, interoperability notes
5. Cite: [Spec: <name>, Section <X.Y>] or [Source: <specification-URL>]
```

### Hardware (Datasheets, Register Maps)

```
1. Identify the part number and revision
2. Locate the manufacturer's datasheet (local copy in docs/datasheets/ or official website)
3. Verify: Register addresses, bit layouts, timing constraints, encoding tables
4. Seek: Errata sheets, application notes, silicon revision differences
5. Cite: [Datasheet: <part>, p.<page>, Table/Fig <n>]
```

### Architecture and Design (Frameworks, Patterns)

```
1. Identify the well-architected framework or reference architecture
2. Fetch the authoritative guide (AWS Well-Architected, Google SRE book, etc.)
3. Verify: Pillar alignment, recommended patterns, anti-patterns
4. Seek: Trade-offs, when NOT to use a pattern, scaling considerations
5. Cite: [Framework: <name>, Section <X>] or [Source: <framework-URL>]
```

### Security (OWASP, CVEs)

```
1. Identify the relevant OWASP category or CVE
2. Fetch from the authoritative source (owasp.org, cve.org, NVD)
3. Verify: Vulnerability description, affected versions, remediation steps
4. Seek: Common bypass patterns, defence-in-depth recommendations
5. Cite: [Standard: OWASP Top 10:2021, <category>] or [Source: <cve-URL>]
```

---

## Reference Quality Hierarchy

When multiple sources conflict, follow this hierarchy (highest authority first):

| Priority | Source Type | Trust Level |
|----------|-----------|-------------|
| 1 | Official specification / RFC / standard | Definitive |
| 2 | Manufacturer datasheet / official docs | Definitive |
| 3 | Publisher's official documentation (docs.*) | Authoritative |
| 4 | Context7-verified library documentation | Authoritative |
| 5 | Well-architected framework (AWS, Google, Azure) | Authoritative |
| 6 | Peer-reviewed academic paper | High |
| 7 | Recognized expert book (O'Reilly, Addison-Wesley) | High |
| 8 | Official GitHub repository (README, issues, PRs) | Moderate |
| 9 | Stack Overflow with official docs citation | Moderate |
| 10 | Blog post / tutorial without citations | Low — do NOT cite as authoritative |

**Rule:** If the only available source is at trust level 8 or below, the agent MUST flag this as a low-confidence reference and explicitly state the limitation.

---

## Output Format

### For Implementation Agents (Code Architect, UI Engineer, etc.)

Every implementation output MUST include a **References** section:

```markdown
## References

| Claim / Decision | Source | Verification |
|-----------------|--------|-------------|
| Using X API for Y | [Context7: /org/lib/v2.1, "X API"] | Fetched 2025-01-15 — API signature confirmed |
| Error handling pattern | [Source: https://docs.lib.com/errors, accessed 2025-01-15] | Official recommended pattern confirmed |
| Connection pool size | [Framework: AWS Well-Architected, Performance Pillar, PERF-03] | Production-grade recommendation confirmed |
| Avoiding Z anti-pattern | [Source: https://docs.lib.com/antipatterns, accessed 2025-01-15] | Anti-pattern confirmed with migration guide |
```

### For Review / Challenger Agents

Every review MUST include a **Reference Validation** section:

```markdown
## Reference Validation

| Primary Claim | Reference Provided | Authority Level | Verified? | Correctly Applied? |
|--------------|-------------------|-----------------|-----------|-------------------|
| <claim> | <citation> | <1-10> | ✓/✗ | ✓/✗/Partial |
| <claim with no ref> | NONE | N/A | ✗ — Missing reference | N/A |

### Findings

- [✓/✗] All factual claims have at least one citation
- [✓/✗] All citations are from authoritative sources (trust level 1-7)
- [✓/✗] All cited sources were verified to actually support the claim
- [✓/✗] Implementation follows what the reference recommends
- [✓/✗] Best practices, gotchas, and production-grade guidance were sought
```

---

## Context7 Integration

When a task involves a library, framework, or API, agents MUST use the `context7-docs` skill as the primary verification tool:

1. **Resolve** the library via Context7 CLI or MCP
2. **Fetch** the relevant documentation sections
3. **Verify** API signatures, parameters, return values against the fetched docs
4. **Seek** best practices, migration guides, deprecation notices
5. **Cite** using `[Context7: <library>/<version>, "<query>"]` format

If Context7 is unavailable, fall back to fetching the official documentation URL directly. If the official URL is also unreachable, state explicitly that verification was not possible and flag the output accordingly.

---

## Self-Reflection Clause

After any issue caused by outdated, incorrect, or unverified information:

1. **Was the authoritative source fetched before acting?** — If not, this skill was not triggered when it should have been.
2. **Was the citation verified against the source?** — If the code doesn't match the cited reference, verification was shallow.
3. **Were best practices and gotchas sought?** — If only API existence was verified, the verification was incomplete.
4. **Update the knowledge base** — Add the lesson to the relevant skill or learning doc in `docs/learning/` so the same class of error is caught earlier next time.