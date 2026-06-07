#!/usr/bin/env bash
# opencode-workflow Installer
# ==========================
# Installs the OpenCode workflow system (agents, skills, scripts) into a project.
#
# Usage:
#   ./install.sh                          # Install into current directory
#   ./install.sh /path/to/project         # Install into specified directory
#   ./install.sh --non-interactive /path  # Install all skills (no prompting)
#   ./install.sh --core-only /path        # Install only core skills
#   ./install.sh --help                   # Show help
#
# Environment variables:
#   ID_PREFIX    - Prefix for ticket IDs (default: derived from directory name)
#
# The script is idempotent — running it multiple times is safe.
# Modified files are preserved as merge prompts rather than overwritten.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Colors ─────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Argument parsing ────────────────────────────────────────────────────

TARGET_DIR=""
NON_INTERACTIVE=false
CORE_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "Usage: $0 [OPTIONS] [TARGET_DIR]"
            echo ""
            echo "Install the OpenCode workflow system into a project directory."
            echo ""
            echo "Options:"
            echo "  --non-interactive   Install all skills without prompting"
            echo "  --core-only         Install only core skills (no domain skills)"
            echo "  --help              Show this help message"
            echo ""
            echo "If TARGET_DIR is not specified, the current directory is used."
            echo ""
            echo "Environment variables:"
            echo "  ID_PREFIX  Prefix for ticket IDs (default: derived from directory name)"
            echo "  BUILD_CMD  Build command for t1-check.sh (default: 'idf.py build')"
            exit 0
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            ;;
        --core-only)
            CORE_ONLY=true
            ;;
        -*)
            echo -e "${RED}Unknown option: $arg${NC}" >&2
            exit 1
            ;;
        *)
            if [ -z "$TARGET_DIR" ]; then
                TARGET_DIR="$arg"
            else
                echo -e "${RED}Multiple target directories specified${NC}" >&2
                exit 1
            fi
            ;;
    esac
done

if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$(pwd)"
fi

TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
    echo -e "${RED}Target directory does not exist: $TARGET_DIR${NC}" >&2
    exit 1
}

# ─── Configuration ──────────────────────────────────────────────────────

# Derive a short project prefix from the directory name
PROJECT_NAME="$(basename "$TARGET_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"
ID_PREFIX="${ID_PREFIX:-${PROJECT_NAME:-psc}}"

AGENTS_DIR="$TARGET_DIR/.opencode/agents"
CORE_SKILLS_DIR="$TARGET_DIR/.opencode/skills"
DOMAIN_SKILLS_DIR="$TARGET_DIR/.opencode/skills"
PIPELINE_SCRIPTS_DIR="$TARGET_DIR/docs/pipeline/scripts"
PM_DIR="$TARGET_DIR/docs/project-management"

MERGE_DIR="$TARGET_DIR/.opencode/merge"

# Source directories
SRC_AGENTS_DIR="$SCRIPT_DIR/agents"
SRC_CORE_SKILLS_DIR="$SCRIPT_DIR/skills/core"
SRC_DOMAIN_SKILLS_DIR="$SCRIPT_DIR/skills/domain"
SRC_SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# ─── Helper functions ────────────────────────────────────────────────────

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }

# Check if a file has been modified from a previous install
# Returns 0 if safe to overwrite, 1 if modified (needs merge)
is_file_modified() {
    local target="$1"

    if [ ! -f "$target" ]; then
        return 0  # File doesn't exist, safe to create
    fi

    # If we're in a git repo, use git to check if the file was modified
    if git -C "$(dirname "$target")" rev-parse --git-dir >/dev/null 2>&1; then
        local rel_path
        rel_path="$(cd "$(dirname "$target")" && git ls-files --error-unmatch "$(basename "$target")" 2>/dev/null)" || {
            # File is not tracked by git — it's new or untracked
            # Check if it looks like it was from a previous install
            if head -5 "$target" 2>/dev/null | grep -qi "opencode-workflow\|opencode workflow\|installed by"; then
                # Was installed by us before, safe to overwrite if unchanged by user
                if git -C "$(dirname "$target")" diff --quiet -- "$(basename "$target")" 2>/dev/null; then
                    return 0  # Unmodified since last commit, safe to overwrite
                else
                    return 1  # Modified by user, needs merge
                fi
            fi
            return 1  # New untracked file, don't overwrite
        }
        # File is tracked by git
        if git -C "$(dirname "$target")" diff --quiet HEAD -- "$(basename "$target")" 2>/dev/null; then
            return 0  # Unmodified from HEAD, safe to overwrite
        else
            return 1  # Modified, needs merge
        fi
    fi

    # Not in a git repo — use checksum comparison with a marker
    local marker="${target}.opencode-workflow.sha256"
    if [ -f "$marker" ]; then
        local old_sha new_sha
        old_sha="$(cat "$marker")"
        new_sha="$(sha256sum "$target" | cut -d' ' -f1)"
        if [ "$old_sha" = "$new_sha" ]; then
            return 0  # Unchanged from previous install, safe to overwrite
        else
            return 1  # Modified since install, needs merge
        fi
    fi

    # No marker file — assume it was manually created
    # Check if it looks like an opencode file
    if head -3 "$target" 2>/dev/null | grep -qi "description\|name\|mode\|opencode"; then
        # Likely an opencode file, but we can't tell if it was modified
        return 1  # Needs merge to be safe
    fi

    return 1  # Err on the side of caution
}

# Install a file, creating merge prompt if needed
install_file() {
    local src="$1"
    local dest="$2"
    local description="$3"

    if [ ! -f "$src" ]; then
        warn "Source file missing: $src"
        return 1
    fi

    local dest_dir
    dest_dir="$(dirname "$dest")"
    mkdir -p "$dest_dir"

    if [ ! -f "$dest" ]; then
        # File doesn't exist — create it
        cp "$src" "$dest"
        ok "Created: $description"
        # Save checksum marker
        sha256sum "$dest" | cut -d' ' -f1 > "${dest}.opencode-workflow.sha256"
        return 0
    fi

    # File exists — check if it was modified
    if is_file_modified "$dest"; then
        # Safe to overwrite
        cp "$src" "$dest"
        ok "Updated: $description"
        sha256sum "$dest" | cut -d' ' -f1 > "${dest}.opencode-workflow.sha256"
        return 0
    else
        # Modified by user — create merge prompt
        local merge_file="$MERGE_DIR/$(basename "$dest").merge.md"
        mkdir -p "$MERGE_DIR"

        local src_content dest_content
        src_content="$(cat "$src")"
        dest_content="$(cat "$dest")"

        cat > "$merge_file" << MERGEEOF
# Merge Required: $(basename "$dest")

## Source (opencode-workflow)
\`\`\`
${src_content}
\`\`\`

## Target (your project)
\`\`\`
${dest_content}
\`\`\`

## Instructions
The file $(basename "$dest") has been modified locally. Please merge:
1. Review both versions above
2. Keep your customizations that are still relevant
3. Adopt new workflow improvements from the source
4. Remove this merge file when done
MERGEEOF

        warn "Modified: $description — merge prompt created at $merge_file"
        return 0
    fi
}

# ─── Skill selection ─────────────────────────────────────────────────────

DOMAIN_SKILLS=(
    "nrf24l01plus:NRF24L01+ radio chip — register gotchas, SPI traps, GPIO caveats, clone detection"
    "esp-idf:ESP-IDF framework — build system, FreeRTOS, SPI, GPIO, error handling patterns"
    "cpp-embedded:C++ embedded patterns — typed enums, register structs, Doxygen, HAL interfaces, platform independence"
    "ble-protocol:BLE protocol — advertising channels, PDU types, data whitening, bit order, CRC-24"
    "ubertooth:Ubertooth One — BLE testing tool, packet injection, passive sniffing, cross-validation"
    "nrf52840-sniffer:nRF52840 Dongle — BLE sniffer, Wireshark extcap, cross-validation with ESP32"
    # Add your own domain skills here, e.g.:
    # "my-domain:My domain — description of when to load this skill"
)

SELECTED_DOMAIN_SKILLS=()

select_domain_skills() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Domain Skill Selection${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Select the domain skills you want to install."
    echo "These are OPTIONAL — install only the ones matching your tech stack."
    echo ""

    local i=1
    for skill_entry in "${DOMAIN_SKILLS[@]}"; do
        local skill_name="${skill_entry%%:*}"
        local skill_desc="${skill_entry#*:}"
        echo -e "  ${BOLD}$i)${NC} ${GREEN}$skill_name${NC} — $skill_desc"
        i=$((i + 1))
    done

    echo ""
    echo -e "  ${BOLD}0)${NC} None (skip all domain skills)"
    echo -e "  ${BOLD}A)${NC} All domain skills"
    echo ""

    read -rp "Enter numbers separated by spaces (or 'A' for all, '0' for none): " selection

    if [ "$selection" = "0" ] || [ "$selection" = "n" ] || [ "$selection" = "N" ]; then
        info "No domain skills selected."
        return
    fi

    if [ "$selection" = "A" ] || [ "$selection" = "a" ]; then
        for skill_entry in "${DOMAIN_SKILLS[@]}"; do
            local skill_name="${skill_entry%%:*}"
            SELECTED_DOMAIN_SKILLS+=("$skill_name")
        done
        ok "All ${#DOMAIN_SKILLS[@]} domain skills selected."
        return
    fi

    for choice in $selection; do
        local idx="$choice"
        if [ "$idx" -ge 1 ] && [ "$idx" -le "${#DOMAIN_SKILLS[@]}" ] 2>/dev/null; then
            local skill_entry="${DOMAIN_SKILLS[$((idx - 1))]}"
            local skill_name="${skill_entry%%:*}"
            SELECTED_DOMAIN_SKILLS+=("$skill_name")
            ok "Selected: $skill_name"
        else
            warn "Invalid selection: $idx (skipping)"
        fi
    done
}

# ─── Install agents ───────────────────────────────────────────────────────

install_agents() {
    info "Installing agents..."
    mkdir -p "$AGENTS_DIR"

    for agent_file in "$SRC_AGENTS_DIR"/*.md; do
        [ -f "$agent_file" ] || continue
        local agent_name
        agent_name="$(basename "$agent_file")"
        install_file "$agent_file" "$AGENTS_DIR/$agent_name" "agent: $agent_name"
    done
}

# ─── Install core skills ─────────────────────────────────────────────────

install_core_skills() {
    info "Installing core skills..."
    mkdir -p "$CORE_SKILLS_DIR"

    for skill_dir in "$SRC_CORE_SKILLS_DIR"/*/; do
        [ -d "$skill_dir" ] || continue
        local skill_name
        skill_name="$(basename "$skill_dir")"
        [ -f "$skill_dir/SKILL.md" ] || continue
        mkdir -p "$CORE_SKILLS_DIR/$skill_name"
        install_file "$skill_dir/SKILL.md" "$CORE_SKILLS_DIR/$skill_name/SKILL.md" "core skill: $skill_name"
    done
}

# ─── Install domain skills ───────────────────────────────────────────────

install_domain_skills() {
    if [ ${#SELECTED_DOMAIN_SKILLS[@]} -eq 0 ]; then
        info "No domain skills to install."
        return
    fi

    info "Installing ${#SELECTED_DOMAIN_SKILLS[@]} domain skill(s)..."
    mkdir -p "$DOMAIN_SKILLS_DIR"

    for skill_name in "${SELECTED_DOMAIN_SKILLS[@]}"; do
        local skill_src="$SRC_DOMAIN_SKILLS_DIR/$skill_name/SKILL.md"
        if [ -f "$skill_src" ]; then
            mkdir -p "$DOMAIN_SKILLS_DIR/$skill_name"
            install_file "$skill_src" "$DOMAIN_SKILLS_DIR/$skill_name/SKILL.md" "domain skill: $skill_name"
        else
            warn "Domain skill source not found: $skill_name"
        fi
    done
}

# ─── Install scripts ─────────────────────────────────────────────────────

install_scripts() {
    info "Installing scripts..."
    mkdir -p "$PIPELINE_SCRIPTS_DIR"
    mkdir -p "$PM_DIR"

    # t1-check.sh
    install_file "$SRC_SCRIPTS_DIR/t1-check.sh" "$PIPELINE_SCRIPTS_DIR/t1-check.sh" "t1-check.sh"
    chmod +x "$PIPELINE_SCRIPTS_DIR/t1-check.sh" 2>/dev/null || true

    # Update PROJECT_ROOT in t1-check.sh to use the target directory
    if [ -f "$PIPELINE_SCRIPTS_DIR/t1-check.sh" ]; then
        # Replace the placeholder with the actual project root
        sed -i "s|^PROJECT_ROOT=.*|PROJECT_ROOT=\"$TARGET_DIR\"|" "$PIPELINE_SCRIPTS_DIR/t1-check.sh" 2>/dev/null || true
    fi

    # next-id.mjs
    install_file "$SRC_SCRIPTS_DIR/next-id.mjs" "$PM_DIR/next-id.mjs" "next-id.mjs"

    # counters.json — only create if it doesn't already exist (never overwrite)
    if [ ! -f "$PM_DIR/counters.json" ]; then
        cp "$SRC_SCRIPTS_DIR/counters.json" "$PM_DIR/counters.json"
        ok "Created: counters.json (initial values)"

        # Update the prefix in next-id.mjs to use the project prefix
        if [ -f "$PM_DIR/next-id.mjs" ]; then
            sed -i "s/const ID_PREFIX = process.env.ID_PREFIX || \"psc\";/const ID_PREFIX = process.env.ID_PREFIX || \"$ID_PREFIX\";/" "$PM_DIR/next-id.mjs" 2>/dev/null || true
        fi
    else
        info "counters.json already exists — keeping existing version (not overwritten)"
    fi
}

# ─── Initialize project management directories ───────────────────────────

init_pm_dirs() {
    info "Initializing project management directories..."

    local pm_subdirs=(
        "open"
        "backlog"
        "closed"
        "epics"
        "clarifications"
        "advisories"
        "adr"
        "designs"
        "chores"
        "reviews"
        "passports"
    )

    for subdir in "${pm_subdirs[@]}"; do
        mkdir -p "$PM_DIR/$subdir"
    done

    ok "Project management directories initialized"
}

# ─── Print summary ────────────────────────────────────────────────────────

print_summary() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  OpenCode Workflow — Installation Summary${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Target directory:  ${GREEN}$TARGET_DIR${NC}"
    echo -e "  ID prefix:         ${GREEN}$ID_PREFIX${NC}"
    echo ""

    local agent_count
    agent_count="$(find "$AGENTS_DIR" -name '*.md' 2>/dev/null | wc -l)"
    echo -e "  Agents installed:  ${GREEN}${agent_count}${NC}"

    # Count core skills by listing the source core directory
    local core_count=0
    for skill_dir in "$SRC_CORE_SKILLS_DIR"/*/; do
        [ -d "$skill_dir" ] || continue
        [ -f "$skill_dir/SKILL.md" ] || continue
        core_count=$((core_count + 1))
    done
    echo -e "  Core skills:      ${GREEN}${core_count}${NC}"

    local domain_count
    domain_count="${#SELECTED_DOMAIN_SKILLS[@]}"
    echo -e "  Domain skills:    ${GREEN}${domain_count}${NC}"
    if [ "$domain_count" -gt 0 ]; then
        for skill_name in "${SELECTED_DOMAIN_SKILLS[@]}"; do
            echo -e "                      - $skill_name"
        done
    fi

    # Check for merge prompts
    local merge_count=0
    if [ -d "$MERGE_DIR" ]; then
        merge_count="$(find "$MERGE_DIR" -name '*.merge.md' 2>/dev/null | wc -l)"
    fi

    if [ "$merge_count" -gt 0 ]; then
        echo ""
        echo -e "  ${YELLOW}⚠ ${merge_count} file(s) need manual merging:${NC}"
        for merge_file in "$MERGE_DIR"/*.merge.md; do
            [ -f "$merge_file" ] || continue
            echo -e "    ${YELLOW}$(basename "$merge_file" .merge.md)${NC}"
        done
        echo ""
        echo -e "  ${BOLD}To resolve merges, copy and paste the following prompt into your LLM:${NC}"
        echo ""
        echo -e "  ${BLUE}────────────────────────────────────────────────────────────────────────${NC}"
        echo -e "  ${BLUE}I have merge conflict files in .opencode/merge/*.md that need resolving.${NC}"
        echo -e "  ${BLUE}Each file contains the upstream (opencode-workflow) version and my local${NC}"
        echo -e "  ${BLUE}(modified) version of an OpenCode agent or skill definition.${NC}"
        echo -e ""
        echo -e "  ${BLUE}For each merge file:${NC}"
        echo -e "  ${BLUE}1. Read the file in .opencode/merge/<filename>.merge.md${NC}"
        echo -e "  ${BLUE}2. Compare the 'Source (opencode-workflow)' section with the 'Target (your project)' section${NC}"
        echo -e "  ${BLUE}3. Produce a merged version that:${NC}"
        echo -e "  ${BLUE}   - Keeps all my local customisations that are still relevant${NC}"
        echo -e "  ${BLUE}   - Adopts the new workflow improvements from upstream${NC}"
        echo -e "  ${BLUE}   - Maintains YAML frontmatter consistency (description, mode, permissions)${NC}"
        echo -e "  ${BLUE}4. Write the merged result to the corresponding agent/skill file in .opencode/${NC}"
        echo -e "  ${BLUE}5. After all merges are resolved, delete the .opencode/merge/ directory${NC}"
        echo -e "  ${BLUE}────────────────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${YELLOW}After merging, you MUST delete the .opencode/merge/ directory to avoid future errors:${NC}"
        echo -e "  ${BOLD}  rm -rf .opencode/merge/${NC}"
    fi

    echo ""
    echo -e "  Project management directories: ${GREEN}docs/project-management/${NC}"
    echo -e "  T1 check script:                ${GREEN}docs/pipeline/scripts/t1-check.sh${NC}"
    echo -e "  Next-ID script:                 ${GREEN}docs/project-management/next-id.mjs${NC}"
    echo ""

    if [ "$merge_count" -eq 0 ]; then
        echo -e "  ${GREEN}✅ All files installed successfully!${NC}"
    else
        echo -e "  ${YELLOW}⚠ Installation complete with ${merge_count} merge(s) pending.${NC}"
    fi

    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo -e "  1. Customise AGENTS.md in your project root (tech stack, project details)"
    echo -e "  2. If merge prompts were generated: copy the LLM prompt above into your AI assistant"
    echo -e "  3. After merging: ${BOLD}rm -rf .opencode/merge/${NC}"
    echo -e "  4. Run: ${BLUE}bash docs/pipeline/scripts/t1-check.sh${NC} to verify T1 checks"
    echo -e "  5. Start using OpenCode with: ${BLUE}opencode${NC}"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════════─╗${NC}"
echo -e "${BOLD}║          OpenCode Workflow System Installer                ║${NC}"
echo -e "${BOLD}╚═════════════════════════════════════════════════════════════╝${NC}"
echo ""

info "Installing into: $TARGET_DIR"
info "Workflow source:  $SCRIPT_DIR"

# Step 1: Create directory structure
info "Creating directory structure..."
mkdir -p "$AGENTS_DIR"
mkdir -p "$CORE_SKILLS_DIR"
mkdir -p "$MERGE_DIR"

# Step 2: Install core agents and core skills
install_agents
install_core_skills

# Step 3: Select and install domain skills
if [ "$CORE_ONLY" = true ]; then
    info "Core-only mode — skipping domain skill selection."
elif [ "$NON_INTERACTIVE" = true ]; then
    info "Non-interactive mode — installing all domain skills."
    for skill_entry in "${DOMAIN_SKILLS[@]}"; do
        SELECTED_DOMAIN_SKILLS+=("${skill_entry%%:*}")
    done
    install_domain_skills
else
    select_domain_skills
    install_domain_skills
fi

# Step 4: Install scripts
install_scripts

# Step 5: Initialize project management directories
init_pm_dirs

# Step 6: Print summary
print_summary