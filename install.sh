#!/usr/bin/env bash
# ============================================================================
# Scoutica Protocol — CLI Installer
# 
# Install with:
#   curl -fsSL https://raw.githubusercontent.com/traylinx/scoutica-protocol/main/install.sh | bash
#
# This script:
#   1. Downloads the scoutica CLI tool
#   2. Downloads JSON schemas for validation
#   3. Downloads card templates
#   4. Makes the CLI available in your PATH
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

REPO_RAW="https://raw.githubusercontent.com/traylinx/scoutica-protocol/main"
INSTALL_DIR="${SCOUTICA_HOME:-$HOME/.scoutica}"
BIN_DIR="$INSTALL_DIR/bin"
SCHEMAS_DIR="$INSTALL_DIR/schemas"
TEMPLATES_DIR="$INSTALL_DIR/templates"

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                       ║${NC}"
echo -e "${CYAN}║${BOLD}   ⚡ Scoutica Protocol — CLI Installer               ${NC}${CYAN}║${NC}"
echo -e "${CYAN}║                                                       ║${NC}"
echo -e "${CYAN}║   Your skills. Your rules. Your data.                 ║${NC}"
echo -e "${CYAN}║                                                       ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# --- Step 1: Create directories ---
echo -e "${BLUE}→${NC} Creating directories in ${BOLD}$INSTALL_DIR${NC}..."
mkdir -p "$BIN_DIR" "$SCHEMAS_DIR" "$TEMPLATES_DIR" "$TEMPLATES_DIR/rules"

# --- Step 2: Download CLI ---
echo -e "${BLUE}→${NC} Downloading scoutica CLI..."
curl -fsSL "$REPO_RAW/tools/scoutica" -o "$BIN_DIR/scoutica"
chmod +x "$BIN_DIR/scoutica"

# --- Step 3: Download schemas ---
echo -e "${BLUE}→${NC} Downloading JSON schemas..."
for schema in candidate_profile.schema.json roe.schema.json evidence.schema.json; do
    curl -fsSL "$REPO_RAW/protocol/platform/01_schemas/$schema" -o "$SCHEMAS_DIR/$schema"
done

# --- Step 4: Download templates ---
echo -e "${BLUE}→${NC} Downloading card templates..."
curl -fsSL "$REPO_RAW/protocol/templates/SKILL.template.md" -o "$TEMPLATES_DIR/SKILL.template.md"
for rule in evaluate-fit.md negotiate-terms.md verify-evidence.md request-interview.md; do
    curl -fsSL "$REPO_RAW/protocol/templates/rules/$rule" -o "$TEMPLATES_DIR/rules/$rule"
done
curl -fsSL "$REPO_RAW/protocol/templates/card.gitignore" -o "$TEMPLATES_DIR/card.gitignore"

# --- Step 5: Download GENERATE_MY_CARD.md ---
echo -e "${BLUE}→${NC} Downloading AI card generator..."
curl -fsSL "$REPO_RAW/GENERATE_MY_CARD.md" -o "$INSTALL_DIR/GENERATE_MY_CARD.md"

# --- Step 6: Download validation and scan tools ---
echo -e "${BLUE}→${NC} Downloading validation tool..."
curl -fsSL "$REPO_RAW/tools/validate_card.py" -o "$BIN_DIR/validate_card.py"
curl -fsSL "$REPO_RAW/tools/SCAN_PROMPT.md" -o "$BIN_DIR/SCAN_PROMPT.md"

# --- Step 7: Add to PATH ---
SHELL_RC=""
if [ -n "${ZSH_VERSION:-}" ] || [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -n "${BASH_VERSION:-}" ] || [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

PATH_EXPORT="export PATH=\"$BIN_DIR:\$PATH\""
ALREADY_IN_PATH=false

if echo "$PATH" | grep -q "$BIN_DIR"; then
    ALREADY_IN_PATH=true
fi

if [ -n "$SHELL_RC" ] && ! $ALREADY_IN_PATH; then
    MARKER="# scoutica-cli-path-v1"
    if ! grep -qF "$MARKER" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "$MARKER" >> "$SHELL_RC"
        echo "$PATH_EXPORT" >> "$SHELL_RC"
        echo -e "${BLUE}→${NC} Added to PATH in ${BOLD}$SHELL_RC${NC}"
    fi
fi

# Add to current session
export PATH="$BIN_DIR:$PATH"

# --- Done ---
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
echo -e "${GREEN}║   ✅ Scoutica CLI installed successfully!             ║${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}To get started, run:${NC}"
echo ""
echo -e "  ${CYAN}source ${SHELL_RC:-~/.zshrc} && scoutica init${NC}"
echo ""
echo -e "  ${BOLD}All commands:${NC}"
echo ""
echo -e "  ${CYAN}scoutica init${NC}          Create your Skill Card (interactive wizard)"
echo -e "  ${CYAN}scoutica init --ai${NC}     Create your card using AI (paste your CV)"
echo -e "  ${CYAN}scoutica scan ./docs/${NC}  Auto-generate card from docs (uses local AI CLI)"
echo -e "  ${CYAN}scoutica validate${NC}      Validate your card against schemas"
echo -e "  ${CYAN}scoutica publish${NC}       Push your card to GitHub"
echo ""
