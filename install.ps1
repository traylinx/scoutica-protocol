# ============================================================================
# Scoutica Protocol — Windows CLI Installer (PowerShell)
#
# Install with:
#   powershell -c "irm https://raw.githubusercontent.com/traylinx/scoutica-protocol/main/install.ps1 | iex"
#
# Or from PowerShell directly:
#   irm https://raw.githubusercontent.com/traylinx/scoutica-protocol/main/install.ps1 | iex
# ============================================================================

$ErrorActionPreference = "Stop"

$REPO_RAW = "https://raw.githubusercontent.com/traylinx/scoutica-protocol/main"
$INSTALL_DIR = if ($env:SCOUTICA_HOME) { $env:SCOUTICA_HOME } else { Join-Path $env:USERPROFILE ".scoutica" }
$BIN_DIR = Join-Path $INSTALL_DIR "bin"
$SCHEMAS_DIR = Join-Path $INSTALL_DIR "schemas"
$TEMPLATES_DIR = Join-Path $INSTALL_DIR "templates"
$RULES_DIR = Join-Path $TEMPLATES_DIR "rules"

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                                                       ║" -ForegroundColor Cyan
Write-Host "  ║   ⚡ Scoutica Protocol — CLI Installer               ║" -ForegroundColor Cyan
Write-Host "  ║                                                       ║" -ForegroundColor Cyan
Write-Host "  ║   Your skills. Your rules. Your data.                 ║" -ForegroundColor Cyan
Write-Host "  ║                                                       ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Create directories ---
Write-Host "  → Creating directories in $INSTALL_DIR..." -ForegroundColor Blue
New-Item -ItemType Directory -Force -Path $BIN_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $SCHEMAS_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $TEMPLATES_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $RULES_DIR | Out-Null

# --- Step 2: Download CLI ---
Write-Host "  → Downloading scoutica CLI..." -ForegroundColor Blue
Invoke-WebRequest -Uri "$REPO_RAW/tools/scoutica.ps1" -OutFile (Join-Path $BIN_DIR "scoutica.ps1") -UseBasicParsing

# Create a batch wrapper so users can just type 'scoutica' from cmd.exe
$batchWrapper = @"
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0scoutica.ps1" %*
"@
Set-Content -Path (Join-Path $BIN_DIR "scoutica.cmd") -Value $batchWrapper -Encoding ASCII

# Create a PowerShell function wrapper for the current session
function global:scoutica { & powershell -ExecutionPolicy Bypass -File (Join-Path $BIN_DIR 'scoutica.ps1') @args }

# --- Step 3: Download schemas ---
Write-Host "  → Downloading JSON schemas..." -ForegroundColor Blue
$schemas = @("candidate_profile.schema.json", "roe.schema.json", "evidence.schema.json")
foreach ($schema in $schemas) {
    Invoke-WebRequest -Uri "$REPO_RAW/protocol/platform/01_schemas/$schema" -OutFile (Join-Path $SCHEMAS_DIR $schema) -UseBasicParsing
}

# --- Step 4: Download templates ---
Write-Host "  → Downloading card templates..." -ForegroundColor Blue
Invoke-WebRequest -Uri "$REPO_RAW/protocol/templates/SKILL.template.md" -OutFile (Join-Path $TEMPLATES_DIR "SKILL.template.md") -UseBasicParsing
$rules = @("evaluate-fit.md", "negotiate-terms.md", "verify-evidence.md", "request-interview.md")
foreach ($rule in $rules) {
    Invoke-WebRequest -Uri "$REPO_RAW/protocol/templates/rules/$rule" -OutFile (Join-Path $RULES_DIR $rule) -UseBasicParsing
}

# --- Step 5: Download GENERATE_MY_CARD.md ---
Write-Host "  → Downloading AI card generator..." -ForegroundColor Blue
Invoke-WebRequest -Uri "$REPO_RAW/GENERATE_MY_CARD.md" -OutFile (Join-Path $INSTALL_DIR "GENERATE_MY_CARD.md") -UseBasicParsing

# --- Step 6: Download validation script ---
Write-Host "  → Downloading validation tool..." -ForegroundColor Blue
Invoke-WebRequest -Uri "$REPO_RAW/tools/validate_card.py" -OutFile (Join-Path $BIN_DIR "validate_card.py") -UseBasicParsing

# --- Step 7: Add to PATH ---
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$BIN_DIR*") {
    Write-Host "  → Adding to user PATH..." -ForegroundColor Blue
    [Environment]::SetEnvironmentVariable("Path", "$BIN_DIR;$currentPath", "User")
    $env:Path = "$BIN_DIR;$env:Path"
}

# --- Step 8: Set environment variable ---
[Environment]::SetEnvironmentVariable("SCOUTICA_HOME", $INSTALL_DIR, "User")
$env:SCOUTICA_HOME = $INSTALL_DIR

# --- Done ---
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║                                                       ║" -ForegroundColor Green
Write-Host "  ║   ✅ Scoutica CLI installed successfully!             ║" -ForegroundColor Green
Write-Host "  ║                                                       ║" -ForegroundColor Green
Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  To get started, run:" -ForegroundColor White
Write-Host ""
Write-Host "  scoutica init" -ForegroundColor Cyan
Write-Host ""
Write-Host "  All commands:" -ForegroundColor White
Write-Host ""
Write-Host "  scoutica init          " -NoNewline -ForegroundColor Cyan; Write-Host "Create your Skill Card (interactive wizard)"
Write-Host "  scoutica init --ai     " -NoNewline -ForegroundColor Cyan; Write-Host "Create your card using AI (paste your CV)"
Write-Host "  scoutica validate      " -NoNewline -ForegroundColor Cyan; Write-Host "Validate your card against schemas"
Write-Host "  scoutica publish       " -NoNewline -ForegroundColor Cyan; Write-Host "Push your card to GitHub"
Write-Host ""
Write-Host "  Note: restart your terminal if 'scoutica' is not found." -ForegroundColor Yellow
Write-Host ""
