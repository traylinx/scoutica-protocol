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
DIM='\033[2m'
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
mkdir -p "$BIN_DIR" "$SCHEMAS_DIR" "$SCHEMAS_DIR/recruiter" "$TEMPLATES_DIR" "$TEMPLATES_DIR/rules"

# --- Step 2: Download CLI ---
echo -e "${BLUE}→${NC} Downloading scoutica CLI..."
curl -fsSL "$REPO_RAW/tools/scoutica" -o "$BIN_DIR/scoutica"
chmod +x "$BIN_DIR/scoutica"

# --- Step 3: Download candidate schemas ---
echo -e "${BLUE}→${NC} Downloading candidate schemas..."
for schema in candidate_profile.schema.json roe.schema.json evidence.schema.json; do
    curl -fsSL "$REPO_RAW/protocol/platform/01_schemas/$schema" -o "$SCHEMAS_DIR/$schema"
done

# --- Step 3b: Download recruiter schemas ---
echo -e "${BLUE}→${NC} Downloading recruiter schemas..."
for schema in recruiter_profile.schema.json hiring_rules.schema.json role.schema.json reputation.schema.json message.schema.json; do
    curl -fsSL "$REPO_RAW/schemas/recruiter/$schema" -o "$SCHEMAS_DIR/recruiter/$schema"
done

# --- Step 3c: Download discovery schema ---
curl -fsSL "$REPO_RAW/schemas/scoutica_discovery.schema.json" -o "$SCHEMAS_DIR/scoutica_discovery.schema.json" 2>/dev/null || true

# --- Step 4: Download templates ---
echo -e "${BLUE}→${NC} Downloading card templates..."
curl -fsSL "$REPO_RAW/protocol/templates/SKILL.template.md" -o "$TEMPLATES_DIR/SKILL.template.md"
curl -fsSL "$REPO_RAW/protocol/templates/EMPLOYER_CARD.template.md" -o "$TEMPLATES_DIR/EMPLOYER_CARD.template.md" 2>/dev/null || true
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
echo -e "${GREEN}║   Create your AI-readable Skill Card in seconds.     ║${NC}"
echo -e "${GREEN}║   Drop your CV in a folder → run one command → done. ║${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}⚡ Quick Start (recommended):${NC}"
echo ""
echo -e "  ${CYAN}source ${SHELL_RC:-~/.zshrc}${NC}"
echo -e "  ${CYAN}scoutica scan ~/CV/${NC}              ${DIM}# Point at your CV folder — done!${NC}"
echo ""
echo -e "  ${DIM}Just put your CV (PDF, Markdown, DOCX, or text) in a folder${NC}"
echo -e "  ${DIM}and run the command above. AI does the rest.${NC}"
echo ""
echo -e "  ${BOLD}🚀 Create your card:${NC}"
echo ""
echo -e "  ${CYAN}scoutica scan \<docs-folder\>${NC}     Auto-generate from your documents (AI-powered)"
echo -e "  ${CYAN}scoutica scan ~/CV/ --clipboard${NC}  Copy prompt to clipboard (use with any AI chat)"
echo -e "  ${CYAN}scoutica init${NC}                    Step-by-step interactive wizard"
echo -e "  ${CYAN}scoutica init --ai${NC}               Create via AI assistant (paste your CV)"
echo ""
echo -e "  ${BOLD}🔧 Manage your card:${NC}"
echo ""
echo -e "  ${CYAN}scoutica info${NC}                    View your card summary"
echo -e "  ${CYAN}scoutica validate${NC}                Validate against protocol schemas"
echo -e "  ${CYAN}scoutica publish${NC}                 Push your card to GitHub"
echo -e "  ${CYAN}scoutica resolve \<url\>${NC}           Fetch and display any card by URL"
echo ""
echo -e "  ${BOLD}⚙️  Advanced:${NC}"
echo ""
echo -e "  ${CYAN}scoutica doctor${NC}                  System diagnostics and health check"
echo -e "  ${CYAN}scoutica update${NC}                  Update CLI to the latest version"
echo -e "  ${CYAN}scoutica help${NC}                    Show all commands with examples"
echo -e "  ${CYAN}scoutica version${NC}                 Show version"
echo ""
echo -e "  ${BOLD}🏢 Employer / Recruiter:${NC}"
echo ""
echo -e "  ${CYAN}scoutica org init${NC}                Create Employer Identity Card"
echo -e "  ${CYAN}scoutica org verify${NC}              Verify domain ownership"
echo -e "  ${CYAN}scoutica role create${NC}             Create a structured job posting"
echo -e "  ${CYAN}scoutica role validate${NC}           Validate role(s) against schemas"
echo ""
echo -e "  ${BOLD}📚 Learn more:${NC}"
echo ""
echo -e "  ${CYAN}Docs:${NC}       https://docs.scoutica.com"
echo -e "  ${CYAN}GitHub:${NC}     https://github.com/traylinx/scoutica-protocol"
echo -e "  ${CYAN}AI Guide:${NC}   ${SCOUTICA_HOME:-~/.scoutica}/GENERATE_MY_CARD.md"
echo ""
