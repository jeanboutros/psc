# Project Management Directory Index

## Structure

```
docs/project-management/
├── next-id.mjs                    # Atomic ID generator (9 kinds, ISB pattern)
├── counters.json                  # Counter state (must exist, never recreated)
├── passports/                     # Pipeline passports
│   └── <ticket-id>-passport.md
├── tickets/                       # Ticket files (universal unit of work)
│   ├── open/                      # Ready for dispatch
│   ├── active/                    # Currently in pipeline
│   ├── closed/                    # Completed (completed / cancelled / archived)
│   └── blocked/                   # Waiting for clarification/dependency
├── epics/                         # Epic definitions (no pipeline)
├── adhoc/                         # Adhoc request tickets
├── clarifications/                # Clarification requests and resolutions
├── advisories/                    # Advisory flags
├── decisions/                     # Decision records
├── logs/                          # Universal log directory
│   ├── tickets/                   # Per-ticket execution logs
│   │   └── <ticket-id>/           # One directory per ticket
│   │       ├── INDEX.md           # Chronological step index
│   │       └── <step>.md          # One file per agent per step
│   ├── conversations/             # Auto-logged session conversations
│   │   └── <conv-id>.md
│   └── index.md                   # Cross-reference index of all logs
└── INDEX.md                       # This file
```

## ID System

| Kind | Prefix | Width | Command |
|------|--------|-------|---------|
| ticket | `psc` | 4 | `node next-id.mjs ticket` |
| epic | `psc-epic` | 3 | `node next-id.mjs epic` |
| adhoc | `psc-adhoc` | 4 | `node next-id.mjs adhoc` |
| clarification | `psc-clar` | 4 | `node next-id.mjs clarification` |
| decision | `psc-dec` | 4 | `node next-id.mjs decision` |
| advisory | `psc-adv` | 4 | `node next-id.mjs advisory` |
| mistake | `psc-mistake` | 4 | `node next-id.mjs mistake` |
| adr | `psc-adr` | 4 | `node next-id.mjs adr` |
| conversation | `psc-conv` | 4 | `node next-id.mjs conversation` |

## Ticket Types

| Type | Pipeline Path | Closure Types |
|------|---------------|---------------|
| feature | Full A→B→C→C4→COMMIT | completed, cancelled, archived |
| bugfix | Full A→B→C→C4→COMMIT | completed, cancelled, archived |
| adhoc | Full A→B→C→C4→COMMIT | completed, cancelled, archived |
| clarification | A-only: A0→A1→A3→C4 | completed |
| decision | A-only: A0→A1→(A2)→(A2a)→A3→C4 | completed |
| advisory | Log-only: A0→C4 | completed |
| mistake | Log-only: A0→C4 | completed |
| epic | No pipeline | — |
| conversation | No ticket, no PM, auto-logged | — |

## Key Rules

1. **Ticket is the universal unit of work.** Everything except conversations gets a ticket.
2. **Counters.json must exist.** If deleted, the ID generator fails — numbers are never reused.
3. **Every agent outcome is logged.** One file per agent per step in the ticket's log directory.
4. **Conversations are auto-logged.** Supreme Leader creates conversation logs at session end.
5. **Only PM creates tickets and moves them between status directories.**
6. **C4 is the final decision point.** PM reviews all verdicts before COMMIT.
