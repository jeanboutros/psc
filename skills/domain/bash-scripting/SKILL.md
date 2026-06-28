---
name: bash-scripting
description: "Bash scripting standards, defensive programming, POSIX portability, testing frameworks, and security hardening. Triggered when writing, reviewing, or testing shell scripts — strict mode, guard clauses, trap cleanup, subprocess management, bashisms detection, shUnit2/BATS testing, and script security scanning."
---

# Bash Scripting Standards, Methodology, and Testing

## Purpose

This skill defines mandatory standards for writing robust, portable, and verifiable shell scripts. It covers defensive programming patterns, POSIX portability rules, testing frameworks, and security hardening. Agents writing or reviewing shell scripts must follow these rules.

This skill is **complementary** to `github` (which covers commit conventions and SSH auth) and `ci-cd-pipeline` (which covers CI/CD pipeline design). It focuses on **shell script engineering quality** — how to write scripts that are correct, portable, testable, and secure.

---

## 1. Cognitive Framework — When to Use Bash

### 1.1 Shell Scripting Is Stream Orchestration

Shell scripting functions primarily as an orchestrator of distinct, process-isolated utilities connected by stream-based textual pipelines. Treating a shell script as a conventional application in a general-purpose language is an architectural error.

**Use bash when:**
- Orchestrating system commands and build toolchains
- Text-processing pipelines (filtering, transforming, redirecting)
- Environment preparation and configuration
- Glue code between tools and services

**Do NOT use bash when:**
- Complex, nested, or multi-dimensional data structures are needed
- Strict API integrations with typed contracts are required
- Intricate character escaping or encoding is involved
- The task requires more than simple scalar variables or sequential arrays

### 1.2 Incremental Pipeline Construction

Build automation pipelines incrementally. Run the initial command in isolation to observe its output, append a filter utility, verify the transformation, and iteratively build the pipeline. This prevents over-engineered shell logic.

---

## 2. Strict Mode — Mandatory Execution Environment

### 2.1 Required Shell Options

Every production-grade script MUST set these options at the top of the file:

```bash
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
```

| Option | Effect |
|--------|--------|
| `errexit` (`set -e`) | Exit immediately if any command returns non-zero |
| `nounset` (`set -u`) | Treat unbound variable references as errors |
| `pipefail` | Pipeline exit status is the last non-zero exit in the chain |
| `errtrace` | ERR trap fires in functions and subshells |

### 2.2 Arithmetic Expression Trap

In Bash, evaluating an arithmetic expression that results in zero (e.g. `(( i++ ))` when `i` is 0) returns exit status 1. Under `errexit`, this exits the script prematurely.

```bash
# BROKEN — exits script when i is 0
(( i++ ))

# CORRECT — safe increment
(( i++ )) || true
```

### 2.3 Unbound Variable Handling

Use parameter expansion defaults for optionally-set variables:

```bash
# Provide a default fallback
active_profile="${ENVIRONMENT_PROFILE:-production}"

# Force termination with custom error if critical variable is missing
database_url="${DB_CONNECTION_URL:?Database connection URL must be specified.}"
```

---

## 3. Guard Clauses

### 3.1 Pattern

A guard clause evaluates a precondition at the start of a block and exits early if not met. This prevents deep nested if-then-else blocks.

```bash
parse_configuration_file() {
  local target_file="${1}"

  if [ ! -f "${target_file}" ]; then
    echo "Error: Configuration file '${target_file}' does not exist." >&2
    return 1
  fi

  if [ ! -r "${target_file}" ]; then
    echo "Error: Configuration file '${target_file}' is unreadable." >&2
    return 1
  fi

  # Primary logic continues here without nesting
  echo "Processing file: ${target_file}"
}
```

### 3.2 Binary Dependency Verification

Scripts that rely on external tools MUST verify those binaries are available before use. Use `command -v` — it is POSIX-compliant and avoids spawning external processes.

```bash
verify_binary_dependency() {
  local target_binary="${1}"

  if ! command -v "${target_binary}" >/dev/null 2>&1; then
    echo "Error: Required command '${target_binary}' is not available." >&2
    exit 1
  fi
}
```

---

## 4. Error Handling and Diagnostics

### 4.1 Timestamped Error Output

Error messages MUST use a consistent format with ISO-8601 timestamps:

```bash
log_error() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}
```

### 4.2 Call Stack Backtrace

Scripts SHOULD print a call stack trace when an unexpected error occurs:

```bash
generate_stack_trace() {
  local error_code=$?
  local total_frames=${#BASH_LINENO[@]}

  log_error "Command failed with status ${error_code} at line ${BASH_LINENO[0]}"

  for ((i = 1; i < total_frames; i++)); do
    local file="${BASH_SOURCE[i]}"
    local line="${BASH_LINENO[i-1]}"
    local func="${FUNCNAME[i]}"
    log_error "  File \"${file}\", line ${line}, in function ${func}"
  done
}

trap 'generate_stack_trace' ERR
```

### 4.3 Function Documentation Headers

Complex shell functions MUST be documented with descriptive headers documenting global variable dependencies, input arguments, output streams, and return codes:

```bash
############################################################
# Safely parse JSON payload.
# Globals:
#   WORKSPACE_DIR
# Arguments:
#   A string representing the raw JSON payload.
# Outputs:
#   Writes parsed values to standard output.
# Returns:
#   0 on successful parsing, non-zero on error.
############################################################
parse_json_payload() {
  local raw_payload="${1}"
  # Implementation details...
}
```

---

## 5. Process Lifecycle Management

### 5.1 Signal Isolation and Resource Cleanup

Scripts that create temporary files or directories MUST register a trap handler for cleanup on EXIT, INT, and TERM signals:

```bash
initialize_secure_workspace() {
  local temp_dir_template="/tmp/application_run"
  local sandbox_dir="${temp_dir_template}.${RANDOM}.${RANDOM}.${RANDOM}.$$"

  (umask 077 && mkdir -p "${sandbox_dir}") || {
    echo "Fatal Error: Failed to create secure sandbox directory." >&2
    exit 1
  }

  readonly WORKSPACE_DIR="${sandbox_dir}"

  trap 'purge_secure_workspace' EXIT INT TERM
}

purge_secure_workspace() {
  if [ -d "${WORKSPACE_DIR:-}" ]; then
    rm -rf "${WORKSPACE_DIR}"
  fi
}
```

### 5.2 Asynchronous Subprocess Monitoring

Background tasks MUST be monitored with `wait` and their exit statuses collected individually:

```bash
run_asynchronous_pipeline() {
  local target_scripts=("data_extractor.sh" "log_analyzer.sh" "cache_purger.sh")
  local process_ids=()
  local execution_statuses=()

  for script in "${target_scripts[@]}"; do
    "./${script}" &
    process_ids+=($!)
  done

  for pid in "${process_ids[@]}"; do
    wait "${pid}"
    execution_statuses+=($?)
  done

  local index=0
  for status in "${execution_statuses[@]}"; do
    if [ "${status}" -ne 0 ]; then
      echo "Subprocess '${target_scripts[index]}' failed with exit code: ${status}" >&2
      exit 1
    else
      echo "Subprocess '${target_scripts[index]}' completed successfully."
    fi
    ((index++)) || true
  done
}
```

---

## 6. POSIX Portability

### 6.1 Bashisms and Their POSIX Alternatives

Scripts targeting `/bin/sh` MUST avoid bash-specific constructs. The following table maps common non-portable extensions to POSIX-compliant alternatives:

| Shell Feature | Bash-Specific (Bashism) | POSIX-Compliant Alternative |
|---------------|------------------------|----------------------------|
| **Arrays** | `arr=("a" "b" "c")` | `set -- "a" "b" "c"` |
| **String Substitution** | `${var//pattern/repl}` | `printf '%s\n' "$var" \| tr ',' ' '` |
| **Process Substitution** | `diff <(cmd1) <(cmd2)` | `tmpdir=$(mktemp -d); cmd1 > "$tmpdir/1"` |
| **Conditional Testing** | `[[ "$var" == "val" ]]` | `[ "$var" = "val" ]` |
| **Here Strings** | `read -r line <<< "$input"` | `read -r line <<EOF` (Here-document) |
| **Sourcing Files** | `source ./config.sh` | `. ./config.sh` |

### 6.2 Portability Testing

Scripts MUST be validated with static analysis tools:

```bash
# Check for bashisms (Debian Devscripts utility)
checkbashisms --force --extra /usr/local/bin/bootstrap.sh

# Run ShellCheck with strict POSIX shell target
shellcheck --shell=sh /usr/local/bin/bootstrap.sh
```

### 6.3 Performance Considerations

| Operation | Bash Native | POSIX (External) | Speedup |
|-----------|-------------|------------------|---------|
| Regex matching | `[[ "$data" =~ $pattern ]]` | `expr` or `grep` | ~60x |
| Substring extraction | `${var#pattern}` | `sed` or `cut` | ~50x |
| String pattern matching | `[[ ... ]]` | `case ... esac` | ~50x |
| File read into variable | `data=$(<file)` | `grep` or `cat` | ~10x |
| Function return via nameref | `declare -n ref=$1` | `ret=$(func)` (subshell) | ~10x |

When portability is not required, use Bash native features for performance. When portability is required, accept the overhead of external utilities.

---

## 7. Testing Frameworks

### 7.1 Framework Selection

| Framework | Best For | Pattern |
|-----------|----------|---------|
| **shUnit2** | Portable, zero-dependency unit testing | xUnit |
| **BATS** | CLI testing with TAP output, CI integration | TAP |
| **ShellSpec** | BDD-style with custom DSL, JUnit output | BDD |
| **bash-spec** | Lightweight BDD in pure shell | BDD |

### 7.2 shUnit2 Test Structure

shUnit2 scans for functions prefixed with `test` and executes them sequentially. It provides `setUp` and `tearDown` hooks:

```bash
#!/bin/bash
# test_math_subsystem.sh

setUp() {
  work_val=10
}

tearDown() {
  unset work_val
}

test_addition_operation() {
  local result=$((work_val + 5))
  assertEquals "Arithmetic evaluation failed." 15 "${result}"
}

test_zero_division() {
  ./divide.sh "${work_val}" 0 >/dev/null 2>&1
  assertNotEquals "Division by zero did not trigger failure status." 0 $?
}

# Source shUnit2 to begin test execution
. ./lib/shunit2
```

### 7.3 BATS Test Structure

BATS uses a custom interpreter with `@test` annotations and a `run` helper:

```bash
#!/usr/bin/env bats
# test_user_management.bats

load './src/user_library.sh'

setup() {
  curl() {
    echo '{"status": "active"}'
    return 0
  }
}

@test "validate_user_profile should return 0 and output valid status" {
  run validate_user_profile "admin"

  [ "$status" -eq 0 ]
  [ "$output" = '{"status": "active"}' ]
}

@test "validate_user_profile should return error status for empty username" {
  run validate_user_profile ""

  [ "$status" -eq 1 ]
}
```

### 7.4 Testing Rules

1. **Every script that performs logic beyond simple command chaining MUST have tests.**
2. **Tests MUST run in CI/CD pipelines before deployment.**
3. **Mock external commands** (curl, git, docker) to isolate test runs from network and system state.
4. **Test error paths** — not just the happy path. Verify exit codes for failure conditions.
5. **Use `run` helper** (BATS) or `$?` checks (shUnit2) to verify exit statuses.

---

## 8. Security Hardening

### 8.1 Threat Categories

| Threat | Mitigation |
|--------|-----------|
| **Command Injection** | Sanitize all user input and external metadata before use in commands |
| **Path Traversal** | Validate extraction paths; never extract archives to uncontrolled locations |
| **Credentials Exfiltration** | Never log or echo environment variables containing secrets |
| **Configuration Injection** | Validate YAML/JSON input before parsing; use strict parsers |
| **Update Drift** | Pin script versions with SHA-256 integrity hashes |

### 8.2 Cryptographic Verification

Scripts fetched from external sources MUST be validated with SHA-256 integrity hashes:

```bash
expected_hash="a1b2c3d4e5f6..."
actual_hash=$(sha256sum downloaded_script.sh | cut -d' ' -f1)

if [ "${actual_hash}" != "${expected_hash}" ]; then
  echo "Error: Integrity check failed for downloaded script." >&2
  exit 1
fi
```

### 8.3 Sandbox Isolation

Scripts that execute untrusted code or process external input MUST run in isolated environments with strict disk and network limits. Never run unvetted scripts directly on host systems.

### 8.4 Least Privilege

Scripts MUST execute with the lowest possible system privileges. Use `allowed-tools` specifications to limit which external binaries a script can invoke.

### 8.5 Static Security Scanning

Before any script is deployed, it MUST be scanned:

```bash
shellcheck --severity=warning script.sh
```

---

## 9. Self-Reflection Clause

After fixing any shell script bug (silent failure, portability issue, security vulnerability, race condition), agents MUST answer:

1. **Why was this bug missed?** What assumption about shell behaviour, portability, or execution environment led to the incorrect code?
2. **What procedural safeguard would have caught it?** What specific check, test, or linting rule should be added?
3. **Update the knowledge base** — add the lesson to this skill or the relevant learning doc in `docs/learning/`.

### Process for Updating This Skill

When a new shell scripting trap or pattern is discovered:

1. Add it as a new subsection under the relevant section with:
   - A one-line **Rule** in bold
   - The mechanism that makes it a trap
   - Correct code example
   - Broken code example (commented out, marked `// BROKEN` or `# BROKEN`)
   - Explanation of why the correct form matters
2. Commit with: `docs(skills): add bash scripting rule — [rule name]`

---

## 10. References

- Google Shell Style Guide: https://google.github.io/styleguide/shellguide.html
- POSIX Shell Specification: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html
- ShellCheck: https://www.shellcheck.net/
- shUnit2: https://github.com/kward/shunit2
- BATS (Bash Automated Testing System): https://github.com/bats-core/bats-core
- ShellSpec: https://github.com/shellspec/shellspec
- OWASP Agentic Skills Top 10: https://owasp.org/www-project-agentic-skills-top-10/
- checkbashisms (Debian Devscripts): https://manpages.debian.org/testing/devscripts/checkbashisms.1.en.html
