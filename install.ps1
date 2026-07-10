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
$LOCAL_SOURCE_ROOT = $env:SCOUTICA_INSTALL_SOURCE_ROOT
$CURRENT_POWERSHELL_EXE = (Get-Process -Id $PID).Path

function Test-SafeRelativeResourcePath([string]$pathValue) {
    if ([string]::IsNullOrWhiteSpace($pathValue)) { return $false }
    if ([System.IO.Path]::IsPathRooted($pathValue)) { return $false }
    if ($pathValue -notmatch '^[A-Za-z0-9._/-]+$') { return $false }
    if ($pathValue -match '(^|[\\/])\.\.?(?:[\\/]|$)') { return $false }
    return $true
}

function Assert-NoReparseComponents([string]$rootPath, [string]$relativePath, [string]$label) {
    $separator = [string][System.IO.Path]::DirectorySeparatorChar
    $current = [System.IO.Path]::GetFullPath($rootPath)
    $segments = $relativePath.Replace('/', $separator).Replace('\', $separator).Split(
        [System.IO.Path]::DirectorySeparatorChar
    )

    foreach ($segment in (@('') + @($segments))) {
        if ($segment) { $current = Join-Path $current $segment }
        if (-not (Test-Path -LiteralPath $current)) { break }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$label contains a symlink or reparse point: $current"
        }
    }
}

function Resolve-InstallDestination([string]$relativePath) {
    if (-not (Test-SafeRelativeResourcePath $relativePath)) {
        throw "Unsafe installer destination in resource contract: $relativePath"
    }

    $separator = [string][System.IO.Path]::DirectorySeparatorChar
    $normalized = $relativePath.Replace('/', $separator).Replace('\', $separator)
    $installRoot = [System.IO.Path]::GetFullPath($INSTALL_DIR)
    if (-not $installRoot.EndsWith($separator)) { $installRoot += $separator }
    $destination = [System.IO.Path]::GetFullPath((Join-Path $INSTALL_DIR $normalized))
    if (-not $destination.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Installer destination escapes SCOUTICA_HOME: $relativePath"
    }
    return $destination
}

function Install-Resource([string]$source, [string]$destination) {
    if (-not (Test-SafeRelativeResourcePath $source)) {
        throw "Unsafe installer source in resource contract: $source"
    }

    $destinationPath = Resolve-InstallDestination $destination
    Assert-NoReparseComponents $INSTALL_DIR $destination "Installer destination"
    $destinationParent = Split-Path -Parent $destinationPath
    New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
    Assert-NoReparseComponents $INSTALL_DIR $destination "Installer destination"

    if ($LOCAL_SOURCE_ROOT) {
        $separator = [string][System.IO.Path]::DirectorySeparatorChar
        $normalizedSource = $source.Replace('/', $separator).Replace('\', $separator)
        $sourceRoot = [System.IO.Path]::GetFullPath($LOCAL_SOURCE_ROOT)
        if (-not $sourceRoot.EndsWith($separator)) { $sourceRoot += $separator }
        $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $LOCAL_SOURCE_ROOT $normalizedSource))
        if (-not $sourcePath.StartsWith($sourceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Installer source escapes SCOUTICA_INSTALL_SOURCE_ROOT: $source"
        }
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Installer source is missing: $sourcePath"
        }
        Assert-NoReparseComponents $LOCAL_SOURCE_ROOT $source "Installer source"
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    } else {
        Invoke-WebRequest -Uri "$REPO_RAW/$source" -OutFile $destinationPath -UseBasicParsing
    }
}

# Fail before creating/downloading anything if the supported validation
# runtime is unavailable. The installer never mutates global Python packages.
$pythonCmd = $null
$supportedPythonFound = $false
foreach ($candidate in @("python3.13", "python3.12", "python3.11", "python3", "python", "py")) {
    if (-not (Get-Command $candidate -ErrorAction SilentlyContinue)) { continue }
    & $candidate -c "import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)" 2>$null
    if ($LASTEXITCODE -ne 0) { continue }
    $supportedPythonFound = $true
    # Keep Python literals single-quoted inside a PowerShell double-quoted
    # argument. Windows PowerShell 5.1 otherwise strips the embedded double
    # quotes while constructing the native command line.
    & $candidate -c "import jsonschema,yaml,sys; c=jsonschema.FormatChecker(); bad=(('relative/path','uri'),('bad host','hostname'),('2024-99-99','date'),('not-a-date','date-time')); sys.exit(0 if all(not c.conforms(value,fmt) for value,fmt in bad) else 1)" 2>$null
    if ($LASTEXITCODE -eq 0) { $pythonCmd = $candidate; break }
}

$pythonPrereq = "python3 -m pip install 'jsonschema[format]' PyYAML"
if (-not $pythonCmd) {
    if ($supportedPythonFound) {
        [Console]::Error.WriteLine("Scoutica requires jsonschema format support and PyYAML.")
        [Console]::Error.WriteLine("Run: $pythonPrereq")
    } else {
        [Console]::Error.WriteLine("Scoutica requires Python 3.11 or newer.")
        [Console]::Error.WriteLine("Install Python 3.11+, then run: $pythonPrereq")
    }
    exit 1
}

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

# --- Step 2: Download and execute the canonical resource contract ---
Write-Host "  → Downloading the Windows resource manifest..." -ForegroundColor Blue
$contractSource = "protocol/platform/cli_support_contract.json"
$contractDestination = "cli_support_contract.json"
Install-Resource $contractSource $contractDestination
$contractPath = Resolve-InstallDestination $contractDestination
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json

if ($contract.installation.contract_source -ne $contractSource -or
    $contract.installation.contract_destination -ne $contractDestination) {
    throw "The CLI support contract has an unexpected bootstrap identity."
}
if ($contract.installation.manifest_version -ne "1.0.0") {
    throw "The installer requires resource manifest version 1.0.0."
}
if ($contract.implementations.windows.capability_set -ne "windows-subset-v1") {
    throw "The installer only supports the windows-subset-v1 capability contract."
}

$windowsResources = @($contract.installation.resources | Where-Object {
    @($_.platforms) -contains "windows"
})
if ($windowsResources.Count -eq 0) {
    throw "The CLI support contract declares no Windows resources."
}

Write-Host "  → Installing Windows capability resources..." -ForegroundColor Blue
$seenDestinations = @{}
$seenDestinations[(Resolve-InstallDestination $contractDestination)] = $true
foreach ($resource in $windowsResources) {
    $resourceSource = [string]$resource.source
    $resourceDestination = [string]$resource.destination
    $resolvedResourceDestination = Resolve-InstallDestination $resourceDestination
    if ($seenDestinations.ContainsKey($resolvedResourceDestination)) {
        throw "Duplicate Windows resource destination in CLI support contract: $resourceDestination"
    }
    $seenDestinations[$resolvedResourceDestination] = $true
    Install-Resource $resourceSource $resourceDestination
}

$requiredDestinations = @(
    "bin/scoutica.ps1",
    "bin/validate_card.py",
    "bin/scan_runtime.py",
    "GENERATE_MY_CARD.md",
    "schemas/candidate_profile.schema.json",
    "schemas/roe.schema.json",
    "schemas/evidence.schema.json",
    "templates/card.gitignore",
    "templates/rules/evaluate-fit.md",
    "templates/rules/negotiate-terms.md",
    "templates/rules/verify-evidence.md",
    "templates/rules/request-interview.md"
)
foreach ($requiredDestination in $requiredDestinations) {
    if (-not (Test-Path -LiteralPath (Resolve-InstallDestination $requiredDestination) -PathType Leaf)) {
        throw "Resource contract did not install required file: $requiredDestination"
    }
}

# Create wrappers pinned to the PowerShell host that ran the installer. A pwsh
# install stays on PowerShell 7; a powershell.exe install stays on 5.1.
$batchHost = $CURRENT_POWERSHELL_EXE.Replace('"', '""')
$batchWrapper = @"
@echo off
"$batchHost" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scoutica.ps1" %*
"@
Set-Content -Path (Join-Path $BIN_DIR "scoutica.cmd") -Value $batchWrapper -Encoding ASCII

# Create a PowerShell function wrapper for the current session with literal
# paths, so it does not depend on installer-scope variables after this script.
$functionHost = $CURRENT_POWERSHELL_EXE.Replace("'", "''")
$functionCli = (Join-Path $BIN_DIR "scoutica.ps1").Replace("'", "''")
$functionBody = "& '$functionHost' -NoProfile -ExecutionPolicy Bypass -File '$functionCli' @args"
Set-Item -Path Function:\global:scoutica -Value ([scriptblock]::Create($functionBody))

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
Write-Host "  Windows capability set: windows-subset-v1" -ForegroundColor White
Write-Host ""
Write-Host "  scoutica init          " -NoNewline -ForegroundColor Cyan; Write-Host "Create your Skill Card (interactive wizard)"
Write-Host "  scoutica init --ai     " -NoNewline -ForegroundColor Cyan; Write-Host "Create your card using AI (paste your CV)"
Write-Host "  scoutica validate      " -NoNewline -ForegroundColor Cyan; Write-Host "Validate your card against schemas"
Write-Host "  scoutica publish       " -NoNewline -ForegroundColor Cyan; Write-Host "Push your card to GitHub"
Write-Host "  scoutica info          " -NoNewline -ForegroundColor Cyan; Write-Host "Show a card summary"
Write-Host "  scoutica help          " -NoNewline -ForegroundColor Cyan; Write-Host "Show supported commands"
Write-Host "  scoutica version       " -NoNewline -ForegroundColor Cyan; Write-Host "Show protocol, implementation, and capability identities"
Write-Host ""
Write-Host "  Full POSIX command parity is not available on Windows yet." -ForegroundColor Yellow
Write-Host "  Note: restart your terminal if 'scoutica' is not found." -ForegroundColor Yellow
Write-Host ""
