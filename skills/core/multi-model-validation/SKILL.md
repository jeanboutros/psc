---
name: multi-model-validation
description: "Launch parallel generic agents using 2+ models for cross-validation, fact-checking, requirement refinement, and knowledge verification. Available to supreme-leader and PM only. Uses priority-ordered model selection based on task complexity."
---

# Multi-Model Validation

## Purpose

This skill defines the protocol for launching parallel generic agents using multiple AI models to cross-validate information, refine requirements, confirm findings, and fact-check claims. It provides a structured approach to multi-model reasoning that strengthens confidence through agreement and surfaces risks through disagreement.

## When to Trigger

- **Before Phase A dispatch** — Refine ambiguous requirements, validate scope, confirm understanding
- **After specialist reviews (A1, C2)** — Cross-validate specialist findings, confirm verdicts
- **During Dual-Model Challenge (A2, C1)** — Supplement specialist challenger output with additional model perspectives
- **When internet-sourced knowledge is used** — Verify claims against multiple models
- **When requirements are ambiguous** — Gather multiple perspectives to resolve ambiguity
- **Before C4 (PM review)** — Validate all findings and decisions before PM makes final call
- **When a specialist raises STATUS: BLOCKED** — Gather additional perspectives to resolve blockers

## Who Can Invoke

**Only the Supreme Leader and PM can invoke multi-model validation.** Other agents must raise a flag for the Supreme Leader or PM to trigger validation.

## Model Priority

When selecting models for validation, use this priority order. Higher-priority models are preferred first.

| Priority | Model | Agent | Strengths |
|----------|-------|-------|-----------|
| 1 | `ollama-cloud/kimi-k2.7-code` | `general-kimi` | Code reasoning, logical analysis, structured thinking |
| 2 | `ollama-cloud/nemotron-3-ultra` | `general-nemotron` | Decision quality, comprehensive analysis, balanced reasoning |
| 3 | `ollama-cloud/minimax-m3` | `general-minimax` | Code review, correctness checking, detail-oriented analysis |
| 4 | `ollama-cloud/glm-5.1` | `general-glm` | Independent perspective, creative alternatives, challenge assumptions |
| 5 | `ollama-cloud/deepseek-v4-pro` | `general-deepseek` | General reasoning, consistency checking, broad knowledge |

## Complexity-Based Model Selection

The number of models dispatched depends on task complexity:

| Complexity | Models | When to Use | Example |
|------------|--------|-------------|---------|
| Low | 2 (kimi + nemotron) | Simple fact check, confirm a single claim, validate a straightforward requirement | "Does this datasheet support this register value?" |
| Medium | 3 (kimi + nemotron + minimax) | Cross-validate findings, refine ambiguous requirements, confirm specialist verdicts | "Is this architecture approach sound?" |
| High | 4 (kimi + nemotron + minimax + glm) | Validate critical claims, multi-perspective analysis, resolve conflicting information | "Verify this security finding across multiple models" |
| Critical | All 5 | Fact-check against references, validate internet-sourced knowledge, resolve fundamental disagreements | "This internet-sourced protocol spec conflicts with the datasheet" |

### Complexity Assessment

When determining complexity, consider:

1. **Ambiguity level** — How unclear is the question? Higher ambiguity → higher complexity
2. **Impact** — What happens if the answer is wrong? Higher impact → higher complexity
3. **Disagreement** — Are specialists disagreeing? Active disagreement → higher complexity
4. **Source reliability** — Is the information from a trusted source? Untrusted source → higher complexity
5. **Reversibility** — Can the decision be easily reversed? Irreversible → higher complexity

## Protocol

### Step 1: Determine Complexity

The Supreme Leader or PM assesses the validation task and selects the appropriate complexity tier.

### Step 2: Dispatch Agents

Dispatch the selected `general-*` agents in parallel. Each agent receives the same prompt:

```yaml
phase: <current phase>
step: multi-model-validation
trigger: <what triggered this validation>
validation_task: |
  <Clear, specific question or task for validation>
  Include all relevant context: findings to verify, claims to check,
  requirements to refine, or decisions to validate.
complexity: <low|medium|high|critical>
models_dispatched: [<list of model names>]
expected_outcomes:
  - agreements: points where all models agree
  - disagreements: points where models disagree, with reasoning
  - ambiguities_found: questions or gaps identified
  - recommendations: specific suggestions with confidence scores
output_to: supreme-leader (or pm)
```

### Step 3: Collect Responses

Wait for all dispatched agents to complete. Each agent produces a validation result with:

| Field | Content |
|-------|---------|
| Model | Which model produced this result |
| Task | Brief description of what was validated |
| Confidence | 0-100 confidence score |
| Agreements | Points where this model agrees with the primary analysis or other models |
| Disagreements | Points where this model disagrees, with evidence or reasoning |
| Ambiguities Found | Questions, missing context, or unstated assumptions identified |
| Recommendations | Specific suggestions for improvement or clarification |

### Step 4: Synthesize

Combine all validation results into a synthesis:

```markdown
## Multi-Model Validation Synthesis

| Field | Value |
|-------|-------|
| Task | <what was validated> |
| Complexity | <low|medium|high|critical> |
| Models Used | <list> |
| Date | <ISO timestamp> |

### Consensus Points
[Points where ALL or MOST models agree — high confidence]

### Disagreements
[Points where models disagree — needs resolution]

| Point | Model A | Model B | Resolution |
|-------|---------|---------|------------|
| <issue> | <position> | <position> | <how resolved or escalated> |

### Ambiguities Identified
[Questions or gaps found by any model]

### Recommendations (Prioritised)
1. [Highest priority recommendation]
2. [Next priority]
...

### Confidence Assessment
| Aspect | Confidence | Reasoning |
|--------|-----------|-----------|
| <what> | <0-100> | <why> |
```

### Step 5: Apply Results

- **Consensus points** — Strengthen confidence in the finding or decision
- **Disagreements** — Must be resolved before proceeding; escalate to user if necessary
- **Ambiguities** — Add to the assumption-trap list; resolve before moving to the next phase
- **Recommendations** — Consider for incorporation; add to the passport if accepted

### Step 6: Log

Write the synthesis to the log directory:

```markdown
# <Step>: Multi-Model Validation

| Field | Value |
|-------|-------|
| Agent | supreme-leader (or pm) |
| Timestamp | <ISO timestamp> |
| Step | <current pipeline step> |
| Complexity | <low|medium|high|critical> |
| Models Dispatched | <list> |

## Synthesis Summary
<Brief summary of the validation result>

## Key Disagreements
<List of unresolved disagreements, if any>

## Action Items
<List of actions taken based on validation>
```

## Integration with Pipeline

### Phase A Integration

- **A0** (Task Definition) — After classifying task domain, validate that the scope is correctly understood
- **A1** (Specialist Review) — After specialist reviews, cross-validate key findings
- **A2** (Dual-Model Challenge) — Supplement the specialist challenger with general model perspectives
- **A3** (A-GATE) — Before gate, validate any contested decisions

### Phase C Integration

- **C1** (Dual-Model Challenge Verification) — Supplement the specialist challenger with general model perspectives
- **C2** (Specialist Approval) — After specialist reviews, cross-validate any contested verdicts
- **C3** (C-GATE) — Before gate, validate any contested findings

### PM Integration

- **C4** (PM Completion Review) — Before making the final decision, validate contested claims or findings
- **Clarification resolution** — When resolving a BLOCKED ticket, validate the user's clarification against multiple models

## Constraints

- Only supreme-leader and PM can invoke this skill
- All general agents are read-only — they validate, they never produce implementation work
- Results are advisory — they inform decisions but do not override specialist verdicts
- Disagreements between models MUST be surfaced in the synthesis, not hidden
- The synthesis MUST be written to the log directory for audit trail
- This skill does NOT replace the Dual-Model Challenge with specialist challengers — it supplements it with broader perspectives