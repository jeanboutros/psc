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
FORCE=false
COMPARE_ONLY=false

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
            echo "  -f, --force         Skip modification checks — overwrite all files"
            echo "  --compare           Dry-run: compare source vs target, show what would change"
            echo "  --help              Show this help message"
            echo ""
            echo "If TARGET_DIR is not specified, the current directory is used."
            echo ""
            echo "Environment variables:"
            echo "  ID_PREFIX  Prefix for ticket IDs (default: derived from directory name)"
            exit 0
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            ;;
        --core-only)
            CORE_ONLY=true
            ;;
        -f|--force)
            FORCE=true
            ;;
        --compare)
            COMPARE_ONLY=true
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
PM_DIR="$TARGET_DIR/docs/project-management"

MERGE_DIR="$TARGET_DIR/.opencode/merge"

# Source directories
SRC_AGENTS_DIR="$SCRIPT_DIR/agents"
SRC_CORE_SKILLS_DIR="$SCRIPT_DIR/skills/core"
SRC_DOMAIN_SKILLS_DIR="$SCRIPT_DIR/skills/domain"

# ─── Helper functions ────────────────────────────────────────────────────

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }

# Install a file, creating merge prompt if user modified it.
# Uses cmp + checksum marker — deterministic, no git dependency.
# In --compare mode, reports status without writing anything.
install_file() {
    local src="$1"
    local dest="$2"
    local description="$3"

    if [ ! -f "$src" ]; then
        if [ "$COMPARE_ONLY" = true ]; then
            echo -e "  ${RED}[MISS]${NC} $description — source missing: $src"
        else
            warn "Source file missing: $src"
        fi
        return 1
    fi

    local dest_dir
    dest_dir="$(dirname "$dest")"

    if [ ! -f "$dest" ]; then
        if [ "$COMPARE_ONLY" = true ]; then
            echo -e "  ${GREEN}[NEW]${NC}  $description — would create"
            return 0
        fi
        mkdir -p "$dest_dir"
        cp "$src" "$dest"
        ok "Created: $description"
        sha256sum "$dest" | cut -d' ' -f1 > "${dest}.opencode-workflow.sha256"
        return 0
    fi

    # --force: skip all checks, overwrite unconditionally
    if [ "$FORCE" = true ]; then
        if [ "$COMPARE_ONLY" = true ]; then
            echo -e "  ${YELLOW}[FORCE]${NC} $description — would force-overwrite"
            return 0
        fi
        mkdir -p "$dest_dir"
        cp "$src" "$dest"
        ok "Force-overwritten: $description"
        sha256sum "$dest" | cut -d' ' -f1 > "${dest}.opencode-workflow.sha256"
        return 0
    fi

    # Destination identical to current source — nothing to do
    if cmp -s "$src" "$dest"; then
        if [ "$COMPARE_ONLY" = true ]; then
            echo -e "  ${BLUE}[SAME]${NC} $description — identical"
        fi
        return 0
    fi

    # Destination differs from source. Check checksum marker to determine why.
    local marker="${dest}.opencode-workflow.sha256"
    if [ -f "$marker" ]; then
        local old_sha new_sha
        old_sha="$(cat "$marker")"
        new_sha="$(sha256sum "$dest" | cut -d' ' -f1)"
        if [ "$old_sha" = "$new_sha" ]; then
            # Unchanged since last install — source was updated, safe to overwrite
            if [ "$COMPARE_ONLY" = true ]; then
                echo -e "  ${GREEN}[UPD]${NC}  $description — source updated, target unchanged"
                return 0
            fi
            mkdir -p "$dest_dir"
            cp "$src" "$dest"
            ok "Updated: $description"
            sha256sum "$dest" | cut -d' ' -f1 > "${dest}.opencode-workflow.sha256"
            return 0
        fi
    fi

    # User modified the file — create merge prompt
    if [ "$COMPARE_ONLY" = true ]; then
        echo -e "  ${YELLOW}[MOD]${NC}  $description — user modified, would create merge prompt"
        return 0
    fi

    mkdir -p "$dest_dir"
    local merge_file="$MERGE_DIR/$(basename "$dest").merge.md"
    mkdir -p "$MERGE_DIR"

    cat > "$merge_file" << MERGEEOF
# Merge Required: $(basename "$dest")

## Source (opencode-workflow)
\`\`\`
$(cat "$src")
\`\`\`

## Target (your project)
\`\`\`
$(cat "$dest")
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
    mkdir -p "$PM_DIR"

    # next-id.mjs — copy from docs/project-management/ (ISB pattern, 9 kinds, no fallback)
    install_file "$SCRIPT_DIR/docs/project-management/next-id.mjs" "$PM_DIR/next-id.mjs" "next-id.mjs"

    # counters.json — only create if it doesn't already exist (never overwrite)
    if [ ! -f "$PM_DIR/counters.json" ]; then
        cp "$SCRIPT_DIR/docs/project-management/counters.json" "$PM_DIR/counters.json"
        ok "Created: counters.json (initial values)"
    else
        info "counters.json already exists — keeping existing version (not overwritten)"
    fi
}

# ─── Initialize project management directories ───────────────────────────

init_pm_dirs() {
    info "Initializing project management directories..."

    local pm_subdirs=(
        "tickets/open"
        "tickets/active"
        "tickets/closed"
        "tickets/blocked"
        "epics"
        "adhoc"
        "clarifications"
        "advisories"
        "decisions"
        "passports"
        "logs/tickets"
        "logs/conversations"
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
    echo -e "  4. Start using OpenCode with: ${BOLD}opencode${NC}"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════════─╗${NC}"
echo -e "${BOLD}║          OpenCode Workflow System Installer                ║${NC}"
echo -e "${BOLD}╚═════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$COMPARE_ONLY" = true ]; then
    echo -e "${BOLD}═══ COMPARE MODE — dry-run, no files will be written ═══${NC}"
    echo ""
    echo -e "  Source: ${BLUE}$SCRIPT_DIR${NC}"
    echo -e "  Target: ${BLUE}$TARGET_DIR${NC}"
    echo ""
    echo -e "  Legend:"
    echo -e "  ${GREEN}[NEW]${NC}  — file doesn't exist in target, would be created"
    echo -e "  ${GREEN}[UPD]${NC}  — source updated, target unchanged since last install, would overwrite"
    echo -e "  ${YELLOW}[MOD]${NC}  — user modified target, would create merge prompt"
    echo -e "  ${YELLOW}[FORCE]${NC} — would force-overwrite (with --force)"
    echo -e "  ${BLUE}[SAME]${NC} — identical, no action needed"
    echo -e "  ${RED}[MISS]${NC} — source file missing"
    echo ""

    echo -e "${BOLD}── Agents ──${NC}"
    for agent_file in "$SRC_AGENTS_DIR"/*.md; do
        [ -f "$agent_file" ] || continue
        _name="$(basename "$agent_file")"
        install_file "$agent_file" "$AGENTS_DIR/$_name" "agent: ${_name%.md}"
    done

    echo ""
    echo -e "${BOLD}── Core Skills ──${NC}"
    for skill_dir in "$SRC_CORE_SKILLS_DIR"/*/; do
        [ -d "$skill_dir" ] || continue
        _skill_name="$(basename "$skill_dir")"
        _skill_file="$skill_dir/SKILL.md"
        [ -f "$_skill_file" ] || continue
        install_file "$_skill_file" "$CORE_SKILLS_DIR/$_skill_name/SKILL.md" "core skill: $_skill_name"
    done

    echo ""
    echo -e "${BOLD}── Domain Skills ──${NC}"
    for skill_dir in "$SRC_DOMAIN_SKILLS_DIR"/*/; do
        [ -d "$skill_dir" ] || continue
        _skill_name="$(basename "$skill_dir")"
        _skill_file="$skill_dir/SKILL.md"
        [ -f "$_skill_file" ] || continue
        install_file "$_skill_file" "$DOMAIN_SKILLS_DIR/$_skill_name/SKILL.md" "domain skill: $_skill_name"
    done

    echo ""
    echo -e "${BOLD}── Scripts ──${NC}"
    install_file "$SCRIPT_DIR/docs/project-management/next-id.mjs" "$PM_DIR/next-id.mjs" "next-id.mjs"
    if [ ! -f "$PM_DIR/counters.json" ]; then
        echo -e "  ${GREEN}[NEW]${NC}  counters.json — would create"
    else
        echo -e "  ${BLUE}[SAME]${NC} counters.json — exists, never overwritten"
    fi

    echo ""
    echo -e "${BOLD}═══ Compare complete. Run without --compare to install. ═══${NC}"
    echo ""
    exit 0
fi

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