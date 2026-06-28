#!/usr/bin/env node

/**
 * Generate the next ticket, epic, adhoc, clarification, decision, advisory,
 * mistake, ADR, or conversation number(s).
 *
 * Usage:
 *   node next-id.mjs ticket              # next ticket id
 *   node next-id.mjs ticket 5            # next 5 ticket ids
 *   node next-id.mjs epic                # next epic id
 *   node next-id.mjs adhoc               # next adhoc id
 *   node next-id.mjs clarification       # next clarification id
 *   node next-id.mjs decision            # next decision id
 *   node next-id.mjs advisory            # next advisory id
 *   node next-id.mjs mistake             # next mistake id
 *   node next-id.mjs adr                 # next ADR id
 *   node next-id.mjs conversation        # next conversation id
 *   node next-id.mjs ticket --dry-run    # preview without updating counters
 *
 * Output (JSON, one object per run — easy for LLMs to parse):
 *   { "kind": "ticket", "ids": ["psc-0001"], "dryRun": false }
 */

import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const COUNTERS_PATH = resolve(__dirname, "counters.json");

const KIND_CONFIG = {
    ticket:        { key: "lastTicket",        prefix: "psc",           width: 4 },
    epic:          { key: "lastEpic",          prefix: "psc-epic",      width: 3 },
    adhoc:         { key: "lastAdhoc",         prefix: "psc-adhoc",     width: 4 },
    clarification: { key: "lastClarification", prefix: "psc-clar",      width: 4 },
    decision:      { key: "lastDecision",      prefix: "psc-dec",       width: 4 },
    advisory:      { key: "lastAdvisory",      prefix: "psc-adv",       width: 4 },
    mistake:       { key: "lastMistake",       prefix: "psc-mistake",   width: 4 },
    adr:           { key: "lastAdr",           prefix: "psc-adr",       width: 4 },
    conversation:  { key: "lastConversation",  prefix: "psc-conv",      width: 4 },
};

// ── Argument parsing ────────────────────────────────────────────────

function parseArgs(argv) {
    const args = argv.slice(2);
    const dryRun = args.includes("--dry-run");
    const positional = args.filter((a) => a !== "--dry-run");

    const kind = positional[0];
    if (!kind || !(kind in KIND_CONFIG)) {
        console.error(
            "Usage: node next-id.mjs <ticket|epic|adhoc|clarification|decision|advisory|mistake|adr|conversation> [count] [--dry-run]",
        );
        process.exit(1);
    }

    const count = positional[1] ? Number.parseInt(positional[1], 10) : 1;
    if (!Number.isFinite(count) || count < 1) {
        console.error("Count must be a positive integer.");
        process.exit(1);
    }

    return { kind, count, dryRun };
}

// ── Counter I/O ─────────────────────────────────────────────────────

function loadCounters() {
    return JSON.parse(readFileSync(COUNTERS_PATH, "utf-8"));
}

function saveCounters(counters) {
    writeFileSync(COUNTERS_PATH, JSON.stringify(counters, null, 2) + "\n");
}

// ── ID generation ───────────────────────────────────────────────────

function formatId(prefix, number, width) {
    return `${prefix}-${String(number).padStart(width, "0")}`;
}

function generateIds(counters, kind, count) {
    const { key, prefix, width } = KIND_CONFIG[kind];
    const ids = [];
    let last = Number(counters[key]) || 0;

    for (let i = 0; i < count; i++) {
        last += 1;
        ids.push(formatId(prefix, last, width));
    }

    return { ids, updatedLast: last, counterKey: key };
}

// ── Main ────────────────────────────────────────────────────────────

function run() {
    const { kind, count, dryRun } = parseArgs(process.argv);
    const counters = loadCounters();
    const { ids, updatedLast, counterKey } = generateIds(counters, kind, count);

    if (!dryRun) {
        counters[counterKey] = updatedLast;
        saveCounters(counters);
    }

    const result = { kind, ids, dryRun };
    console.log(JSON.stringify(result, null, 2));
}

run();
