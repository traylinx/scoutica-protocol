# ============================================================================
# Scoutica CLI — Windows PowerShell Edition
#
# Commands:
#   scoutica init          Interactive wizard to create your Skill Card
#   scoutica init --ai     Generate card using AI (paste GENERATE_MY_CARD.md)
#   scoutica validate      Validate your card against protocol schemas
#   scoutica publish       Push your card to GitHub
#   scoutica info          Show card summary
#   scoutica help          Show this help
# ============================================================================

$ErrorActionPreference = "Stop"
$PROTOCOL_VERSION = "0.4.0"
$IMPLEMENTATION_VERSION = "0.1.0"
$CAPABILITY_SET = "windows-subset-v1"
$KNOWN_UNSUPPORTED_COMMANDS = @(
    "import", "scan", "resolve", "preview", "update", "doctor", "status", "logs",
    "org", "role", "evaluate", "jobs", "send", "inbox", "reply", "deliver",
    "register", "identity"
)
$SCOUTICA_HOME = if ($env:SCOUTICA_HOME) { $env:SCOUTICA_HOME } else { Join-Path $env:USERPROFILE ".scoutica" }
$SCHEMAS_DIR = Join-Path $SCOUTICA_HOME "schemas"
$TEMPLATES_DIR = Join-Path $SCOUTICA_HOME "templates"
$SCRIPT_ROOT = $PSScriptRoot  # Capture at top level for use inside functions

# ─── Helpers ──────────────────────────────────────────────────────────────────

function Write-Header($title) {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║   ⚡ Scoutica — $title" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Ask($prompt, $default) {
    if ($null -ne $default -and $default -ne '') {
        Write-Host "  $prompt [$default]: " -NoNewline -ForegroundColor White
    } else {
        Write-Host "  $($prompt): " -NoNewline -ForegroundColor White
    }
    $result = Read-Host
    if ([string]::IsNullOrWhiteSpace($result) -and $default) { return $default }
    return $result
}

function Ask-List($prompt, $hint) {
    Write-Host "  $prompt ($hint): " -NoNewline -ForegroundColor White
    return Read-Host
}

function Ask-Choice($prompt, [string[]]$options) {
    Write-Host "  $prompt" -ForegroundColor White
    for ($i = 0; $i -lt $options.Count; $i++) {
        Write-Host "    $($i+1)) $($options[$i])" -ForegroundColor Cyan
    }
    while ($true) {
        Write-Host "  Choose [1-$($options.Count)]: " -NoNewline -ForegroundColor White
        $choice = Read-Host
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $options.Count) {
            return $options[[int]$choice - 1]
        }
        Write-Host "  Invalid choice. Try again." -ForegroundColor Yellow
    }
}

function Ask-YesNo($prompt) {
    Write-Host "  $prompt [y/N]: " -NoNewline -ForegroundColor White
    $answer = Read-Host
    return $answer -match "^[Yy]"
}

function Write-Success($msg) { Write-Host "  ✅ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  ⚠️  $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "  ❌ $msg" -ForegroundColor Red }

function ConvertTo-JsonArray([string]$csv) {
    $items = $csv.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    $quoted = $items | ForEach-Object { ([string]$_ | ConvertTo-Json -Compress) }
    return "[$($quoted -join ', ')]"
}

function ConvertTo-YamlList([string]$csv, [string]$indent = "    ") {
    $items = $csv.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    return ($items | ForEach-Object { "${indent}- $(ConvertTo-YamlScalar $_)" }) -join "`n"
}

# ─── INIT Command ─────────────────────────────────────────────────────────────

function ConvertTo-JsonScalar([object]$v) {
    # JSON-encode ONE scalar so embedded quotes/backslashes/newlines cannot corrupt the file.
    if ($null -eq $v) { return '""' }
    return ([string]$v | ConvertTo-Json -Compress)
}

function ConvertTo-YamlScalar([object]$v) {
    # YAML double-quoted scalar. Escape backslash + quote, then encode EVERY C0 control char: raw
    # controls (e.g. U+0001) are illegal inside a double-quoted scalar and would yield invalid YAML.
    $t = ([string]$v) -replace '\\', '\\' -replace '"', '\"'
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $t.ToCharArray()) {
        $code = [int]$ch
        switch ($code) {
            9  { [void]$sb.Append('\t') }
            10 { [void]$sb.Append('\n') }
            13 { [void]$sb.Append('\r') }
            default {
                if ($code -lt 0x20 -or $code -eq 0x7F) { [void]$sb.AppendFormat('\x{0:x2}', $code) }
                else { [void]$sb.Append($ch) }
            }
        }
    }
    return '"' + $sb.ToString() + '"'
}

function Invoke-Init {
    param([string]$targetDir = ".", [switch]$AI)
    
    if ($AI) {
        Invoke-InitAI -targetDir $targetDir
        return
    }
    
    Write-Header "Create Your Skill Card"
    
    Write-Host "  Answer the questions below to generate your Scoutica Skill Card." -ForegroundColor DarkGray
    Write-Host "  Press Enter to skip optional fields or accept defaults." -ForegroundColor DarkGray
    Write-Host ""
    
    # ── Section 1: Identity ──
    Write-Host "  ━━━ 👤 Identity ━━━" -ForegroundColor Magenta
    Write-Host ""
    $name = Ask "Your professional name"
    $title = Ask "Professional title" "Software Engineer"
    $seniority = Ask-Choice "Seniority level" @("entry","junior","mid","senior","lead","manager","director","executive")
    $years = Ask "Years of experience" "5"
    $availability = Ask-Choice "Availability" @("immediately","in_2_weeks","in_4_weeks","in_8_weeks","not_looking")
    Write-Host ""
    
    # ── Section 2: Skills ──
    Write-Host "  ━━━ 🛠️  Skills & Expertise ━━━" -ForegroundColor Magenta
    Write-Host ""
    $domains = Ask-List "Primary domains" "e.g. Backend Engineering, DevOps"
    $skills = Ask-List "Key skills" "e.g. Python, Leadership, SQL"
    $tools = Ask-List "Tools & platforms" "e.g. Docker, AWS, Figma"
    $certs = Ask-List "Certifications" "optional, e.g. AWS SA, PMP"
    $specializations = Ask-List "Specializations" "optional"
    Write-Host ""
    
    # ── Section 3: Languages ──
    Write-Host "  ━━━ 🌍 Languages ━━━" -ForegroundColor Magenta
    Write-Host ""
    $langEntries = @()
    do {
        $lang = Ask "Language (press Enter to finish)" ""
        if ([string]::IsNullOrWhiteSpace($lang)) { break }
        $level = Ask-Choice "Level for $lang" @("native","fluent","professional","basic")
        $langEntries += @{ language = $lang; level = $level }
    } while (Ask-YesNo "Add another language?")
    
    $langJson = ($langEntries | ForEach-Object {
        "{`"language`": $(ConvertTo-JsonScalar $_.language), `"level`": $(ConvertTo-JsonScalar $_.level)}"
    }) -join ", "
    $langJson = "[$langJson]"
    Write-Host ""
    
    # ── Section 4: Summary ──
    Write-Host "  ━━━ 📝 Summary ━━━" -ForegroundColor Magenta
    Write-Host ""
    $education = Ask "Education" ""
    $summary = Ask "Professional summary (2-3 sentences)" ""
    Write-Host ""
    
    # ── Section 5: Rules of Engagement ──
    Write-Host "  ━━━ 📋 Rules of Engagement ━━━" -ForegroundColor Magenta
    Write-Host ""
    
    $engTypes = @()
    foreach ($etype in @("permanent","contract","fractional","advisory","internship")) {
        if (Ask-YesNo "Accept $etype?") { $engTypes += $etype }
    }
    Write-Host ""
    
    $compPermanent = ""; $compContract = ""; $compAdvisory = ""
    Write-Host "  Minimum compensation (EUR, or 'negotiable'):" -ForegroundColor White
    if ($engTypes -contains "permanent") { $compPermanent = Ask "  Annual salary minimum" "negotiable" }
    if ($engTypes -contains "contract") { $compContract = Ask "  Daily rate minimum" "negotiable" }
    if ($engTypes -contains "advisory") { $compAdvisory = Ask "  Hourly rate minimum" "negotiable" }
    Write-Host ""
    
    $remotePolicy = Ask-Choice "Remote policy" @("remote_only","hybrid","flexible","on_site")
    $hybridLocations = ""
    if ($remotePolicy -eq "hybrid") {
        $hybridLocations = Ask-List "Hybrid locations" "e.g. Berlin, New York"
    }
    Write-Host ""
    
    $blocked = Ask-List "Blocked industries" "optional, e.g. gambling, weapons"
    $prefStack = Ask-List "Preferred tech/skill keywords" "for matching"
    $stackMin = Ask "Min keyword matches before soft-reject" "3"
    Write-Host ""
    
    # ── Section 6: Evidence ──
    Write-Host "  ━━━ 🔗 Public Evidence ━━━" -ForegroundColor Magenta
    Write-Host ""
    $evItems = @()
    while (Ask-YesNo "Add an evidence item?") {
        $evType = Ask-Choice "Type" @("github_repo","website","portfolio","certificate","article","review","case_study","publication","video","other")
        $evTitle = Ask "Title"
        $evUrl = Ask "URL"
        $evDesc = Ask "What does this prove?"
        $evSkills = Ask-List "Skills demonstrated" "comma-separated"
        
        $evItems += @{
            type = $evType; title = $evTitle; url = $evUrl
            description = $evDesc; skills = $evSkills
        }
        Write-Host ""
    }
    
    # ── Generate Files ──
    Write-Header "Generating Your Skill Card"
    
    $rulesPath = Join-Path $targetDir "rules"
    New-Item -ItemType Directory -Force -Path $rulesPath | Out-Null
    
    # --- profile.json ---
    $profileJson = @"
{
  "schema_version": "0.1.0",
  "name": $(ConvertTo-JsonScalar $name),
  "title": $(ConvertTo-JsonScalar $title),
  "seniority": $(ConvertTo-JsonScalar $seniority),
  "years_experience": $(if ($years -match '^\d+$') { $years } else { 0 }),
  "availability": $(ConvertTo-JsonScalar $availability),
  "primary_domains": $(ConvertTo-JsonArray $domains),
  "skills": $(ConvertTo-JsonArray $skills),
  "tools_and_platforms": $(ConvertTo-JsonArray $tools),
  "certifications_and_licenses": $(ConvertTo-JsonArray $certs),
  "specializations": $(ConvertTo-JsonArray $specializations),
  "spoken_languages": $langJson,
  "education": $(ConvertTo-JsonScalar $education),
  "summary": $(ConvertTo-JsonScalar $summary)
}
"@
    [System.IO.File]::WriteAllText((Join-Path $targetDir "profile.json"), $profileJson, [System.Text.UTF8Encoding]::new($false))
    Write-Success "Created profile.json"
    
    # --- rules.yaml ---
    $engYaml = ($engTypes | ForEach-Object { "    - $_" }) -join "`n"
    
    $compBlock = ""
    if ($compPermanent -or $compContract -or $compAdvisory) {
        $compBlock = "  compensation:`n    minimum_base_eur:"
        if ($compPermanent) {
            $compBlock += "`n      permanent: $(if ($compPermanent -match '^\d+$') { $compPermanent } else { ConvertTo-YamlScalar $compPermanent })"
        }
        if ($compContract) {
            $compBlock += "`n      contract: $(if ($compContract -match '^\d+$') { $compContract } else { ConvertTo-YamlScalar $compContract })"
        }
        if ($compAdvisory) {
            $compBlock += "`n      advisory: $(if ($compAdvisory -match '^\d+$') { $compAdvisory } else { ConvertTo-YamlScalar $compAdvisory })"
        }
    }
    
    $hybridYaml = if ($hybridLocations) { ConvertTo-YamlList $hybridLocations } else { "    []" }
    $blockedYaml = if ($blocked) { ConvertTo-YamlList $blocked } else { "    []" }
    $stackYaml = if ($prefStack) { ConvertTo-YamlList $prefStack "      " } else { "      []" }
    
    $rulesYaml = @"
schema_version: "0.1.0"

engagement:
  allowed_types:
$engYaml
$compBlock

remote:
  policy: $(ConvertTo-YamlScalar $remotePolicy)
  hybrid_locations:
$hybridYaml

filters:
  blocked_industries:
$blockedYaml
  stack_keywords:
    preferred:
$stackYaml
  soft_reject:
    weak_stack_overlap_below: $(if ($stackMin -match '^\d+$') { $stackMin } else { 0 })

privacy:
  zone_1_public:
    - title
    - seniority
    - primary_domains
    - availability
  zone_2_paid:
    - full_profile
    - evidence
    - experience_details
  zone_3_private:
    - email
    - phone
    - exact_salary
"@
    [System.IO.File]::WriteAllText((Join-Path $targetDir "rules.yaml"), $rulesYaml, [System.Text.UTF8Encoding]::new($false))
    Write-Success "Created rules.yaml"
    
    # --- evidence.json ---
    $evJson = ($evItems | ForEach-Object {
        "    {`n      `"type`": $(ConvertTo-JsonScalar $_.type),`n      `"title`": $(ConvertTo-JsonScalar $_.title),`n      `"url`": $(ConvertTo-JsonScalar $_.url),`n      `"description`": $(ConvertTo-JsonScalar $_.description),`n      `"skills_demonstrated`": $(ConvertTo-JsonArray $_.skills)`n    }"
    }) -join ",`n"
    
    $evidenceJson = @"
{
  "schema_version": "0.1.0",
  "items": [
$evJson
  ]
}
"@
    [System.IO.File]::WriteAllText((Join-Path $targetDir "evidence.json"), $evidenceJson, [System.Text.UTF8Encoding]::new($false))
    Write-Success "Created evidence.json"
    
    # --- SKILL.md ---
    # Body is Markdown prose: strip control chars so a name/title can't inject a new block/line
    # (frontmatter scalars below are separately escaped via ConvertTo-YamlScalar).
    $nameLine = ($name -replace '[\x00-\x1F]+', ' ').Trim()
    $titleLine = ($title -replace '[\x00-\x1F]+', ' ').Trim()
    $skillMd = @"
---
name: scoutica
description: $(ConvertTo-YamlScalar "$name — AI-readable professional profile with automated opportunity filtering")
metadata:
  tags: $(ConvertTo-YamlScalar ($skills.ToLower() -replace ',', ', '))
  author: $(ConvertTo-YamlScalar $name)
  version: 0.1.0
---

# Scoutica

This skill provides an AI-readable professional profile for **$nameLine** — $titleLine.

It allows any AI agent to:
- Understand this candidate's capabilities and experience
- Evaluate fit against a role or opportunity
- Check whether an opportunity meets the candidate's policies
- Access public evidence of work
- Request an interview handoff if the opportunity passes all checks

## Data Files

- [profile.json](./profile.json)
- [rules.yaml](./rules.yaml)
- [evidence.json](./evidence.json)

## Evaluation Rules

- [evaluate-fit.md](./rules/evaluate-fit.md)
- [negotiate-terms.md](./rules/negotiate-terms.md)
- [verify-evidence.md](./rules/verify-evidence.md)
- [request-interview.md](./rules/request-interview.md)

## Important Rules
1. Never fabricate capabilities. Only report what is in ``profile.json``.
2. Respect the Rules of Engagement. If ``rules.yaml`` says REJECT, do not override.
3. Candidate sovereignty. This profile serves the candidate, not the employer.
"@
    [System.IO.File]::WriteAllText((Join-Path $targetDir "SKILL.md"), $skillMd, [System.Text.UTF8Encoding]::new($false))
    Write-Success "Created SKILL.md"
    
    # --- Copy rule templates ---
    $templateRulesDir = Join-Path $TEMPLATES_DIR "rules"
    if (Test-Path $templateRulesDir) {
        Copy-Item -Path (Join-Path $templateRulesDir "*.md") -Destination $rulesPath -Force
        Write-Success "Copied evaluation rule templates"
    } else {
        Write-Warn "Rule templates not found — run installer first"
    }

    # Copy the gitignore template to .gitignore so secrets (.env, raw CVs, .scoutica/) are never
    # staged. Git only honors a file literally named .gitignore (F-HIGH-PS-002).
    $giDest = Join-Path $targetDir ".gitignore"
    $giSrc = Join-Path $TEMPLATES_DIR "card.gitignore"
    if (-not (Test-Path $giDest)) {
        if (Test-Path $giSrc) {
            Copy-Item -Path $giSrc -Destination $giDest -Force
            Write-Success "Created .gitignore (protects secrets from accidental commits)"
        } else {
            Write-Warn "card.gitignore template not found — publish may stage unintended files"
        }
    }
    
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║   🎉 Your Scoutica Skill Card is ready!              ║" -ForegroundColor Green
    Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Files created in: $targetDir/" -ForegroundColor White
    Write-Host ""
    Write-Host "  scoutica validate   " -NoNewline -ForegroundColor Cyan; Write-Host "Check your card for errors"
    Write-Host "  scoutica publish    " -NoNewline -ForegroundColor Cyan; Write-Host "Push to GitHub"
    Write-Host ""
}

# ─── INIT --AI Command ───────────────────────────────────────────────────────

function Invoke-InitAI([string]$targetDir = ".") {
    Write-Header "AI-Powered Card Creation"
    
    $genFile = Join-Path $SCOUTICA_HOME "GENERATE_MY_CARD.md"
    Write-Host "  The easiest way to create your card with AI:" -ForegroundColor White
    Write-Host ""
    Write-Host "  1. Copy the contents of: $genFile" -ForegroundColor White
    Write-Host "  2. Paste it into any AI assistant (ChatGPT, Claude, Gemini, etc.)" -ForegroundColor DarkGray
    Write-Host "  3. Follow the conversation" -ForegroundColor DarkGray
    Write-Host "  4. Save the generated files to: $targetDir/" -ForegroundColor DarkGray
    Write-Host ""
    
    if (Test-Path $genFile) {
        if (Ask-YesNo "Copy GENERATE_MY_CARD.md to clipboard?") {
            Get-Content $genFile -Raw | Set-Clipboard
            Write-Success "Copied to clipboard! Paste into your AI assistant."
        }
    } else {
        Write-Err "GENERATE_MY_CARD.md not found. Re-run the installer."
    }
}

# ─── VALIDATE Command ────────────────────────────────────────────────────────

function Invoke-Validate([string]$cardDir = ".") {
    Write-Header "Validate Skill Card"
    
    # Select a runnable validation interpreter, not merely the first command
    # name present on PATH. Windows can expose python3.exe as a non-functional
    # Store alias even when setup-python installed a working python.exe.
    $pythonCmd = $null
    foreach ($candidate in @("python3.13", "python3.12", "python3.11", "python3", "python", "py")) {
        if (-not (Get-Command $candidate -ErrorAction SilentlyContinue)) { continue }
        & $candidate -c "import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)" 2>$null
        if ($LASTEXITCODE -ne 0) { continue }
        & $candidate -c 'import jsonschema,yaml,sys; c=jsonschema.FormatChecker(); bad=(("relative/path","uri"),("bad host","hostname"),("2024-99-99","date"),("not-a-date","date-time")); sys.exit(0 if all(not c.conforms(value,fmt) for value,fmt in bad) else 1)' 2>$null
        if ($LASTEXITCODE -eq 0) { $pythonCmd = $candidate; break }
    }
    
    if (-not $pythonCmd) {
        Write-Err "Python 3.11+, jsonschema, and PyYAML are required for schema validation"
        Write-Host "  Run: python3 -m pip install 'jsonschema[format]' PyYAML" -ForegroundColor DarkGray
        exit 1
    }
    
    # Find validator — use $SCRIPT_ROOT captured at top level (not $MyInvocation which is empty in functions)
    $validator = $null
    $candidates = @(
        (Join-Path $SCOUTICA_HOME "bin" "validate_card.py"),
        (Join-Path $SCRIPT_ROOT "validate_card.py"),
        (Join-Path $SCOUTICA_HOME "tools" "validate_card.py")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $validator = $c; break }
    }
    
    if (-not $validator) {
        Write-Err "Validation script not found. Re-run the installer."
        exit 1
    }
    
    & $pythonCmd $validator $cardDir
    $validationExit = $LASTEXITCODE
    if ($validationExit -ne 0) { exit $validationExit }
}

# ─── PUBLISH Command ─────────────────────────────────────────────────────────

function Get-PublishCanonicalPaths {
    # Exact candidate-card publication surface. Both index checks and staging
    # consume this one list so a directory can never broaden the boundary.
    $paths = @()
    foreach ($path in @('profile.json','rules.yaml','evidence.json','SKILL.md','scoutica.json','README.md','.gitignore')) {
        $paths += $path
    }
    $paths += @(
        'rules/evaluate-fit.md',
        'rules/negotiate-terms.md',
        'rules/verify-evidence.md',
        'rules/request-interview.md'
    )
    return $paths
}

function Write-PublishError([string]$message) {
    [Console]::Error.WriteLine("  ❌ $message")
}

function Test-PublishIndex([System.Collections.Generic.HashSet[string]]$allowedPaths, [string]$phase) {
    $stagedPaths = @(& git diff --cached --name-only --)
    if ($LASTEXITCODE -ne 0) {
        Write-PublishError "Unable to inspect the Git index during $phase."
        return $false
    }

    $blockedPaths = @()
    foreach ($path in $stagedPaths) {
        if (-not $allowedPaths.Contains([string]$path)) {
            $blockedPaths += [string]$path
        }
    }
    if ($blockedPaths.Count -gt 0) {
        Write-PublishError "Refusing publish: the Git index contains non-canonical path(s):"
        foreach ($path in $blockedPaths) {
            [Console]::Error.WriteLine("     $path")
        }
        return $false
    }
    return $true
}

function Invoke-Publish([string]$cardDir = ".") {
    Write-Header "Publish to GitHub"
    
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Err "Git is required for publishing"
        exit 1
    }
    
    Push-Location $cardDir
    try {
        if (Test-Path ".git") {
            $allowedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($path in (Get-PublishCanonicalPaths)) {
                [void]$allowedPaths.Add($path)
            }

            # Refuse before any Scoutica staging. A refusal leaves the caller's
            # pre-existing index byte-for-byte unchanged.
            if (-not (Test-PublishIndex $allowedPaths "pre-staging check")) { exit 1 }

            $origin = & git remote get-url origin 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$origin)) {
                Write-PublishError "No remote 'origin' configured."
                [Console]::Error.WriteLine("     Run: git remote add origin https://github.com/YOU/YOUR-CARD.git")
                exit 1
            }

            $branch = & git branch --show-current 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$branch)) {
                Write-PublishError "Cannot publish from a detached HEAD or unresolved branch."
                exit 1
            }

            foreach ($path in (Get-PublishCanonicalPaths)) {
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    & git add -- $path
                    if ($LASTEXITCODE -ne 0) {
                        Write-PublishError ("Failed to stage canonical path: {0}" -f $path)
                        exit 1
                    }
                }
            }

            # Defense in depth: prove the final index is still bounded before commit.
            if (-not (Test-PublishIndex $allowedPaths "post-staging check")) { exit 1 }

            & git diff --cached --quiet --exit-code --
            $diffExit = $LASTEXITCODE
            if ($diffExit -eq 1) {
                $msg = "Update Scoutica Skill Card — $(Get-Date -Format 'yyyy-MM-dd')"
                & git commit -m $msg 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-PublishError "Commit failed; nothing was pushed."
                    exit 1
                }
            } elseif ($diffExit -ne 0) {
                Write-PublishError "Unable to inspect staged changes; nothing was pushed."
                exit 1
            }

            & git push origin $branch
            if ($LASTEXITCODE -ne 0) {
                Write-PublishError "Push failed. Check your remote configuration or permissions."
                exit 1
            }
            Write-Success "Pushed to GitHub!"
        } else {
            $repoName = Ask "GitHub repo name" "my-scoutica-card"
            $ghUser = Ask "GitHub username"

            & git init
            if ($LASTEXITCODE -ne 0) {
                Write-PublishError "Git repository initialization failed."
                exit 1
            }

            $allowedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($path in (Get-PublishCanonicalPaths)) {
                [void]$allowedPaths.Add($path)
            }
            if (-not (Test-PublishIndex $allowedPaths "pre-staging check")) { exit 1 }

            foreach ($path in (Get-PublishCanonicalPaths)) {
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    & git add -- $path
                    if ($LASTEXITCODE -ne 0) {
                        Write-PublishError ("Failed to stage canonical path: {0}" -f $path)
                        exit 1
                    }
                }
            }
            if (-not (Test-PublishIndex $allowedPaths "post-staging check")) { exit 1 }

            & git commit -m "Initial Scoutica Skill Card"
            if ($LASTEXITCODE -ne 0) {
                Write-PublishError "Commit failed; nothing was pushed."
                exit 1
            }
            & git branch -M main
            if ($LASTEXITCODE -ne 0) {
                Write-PublishError "Failed to create the main branch."
                exit 1
            }
            & git remote add origin "https://github.com/$ghUser/$repoName.git"
            if ($LASTEXITCODE -ne 0) {
                Write-PublishError "Failed to configure remote 'origin'."
                exit 1
            }

            Write-Host ""
            Write-PublishError "Repository initialized locally, but it has not been published."
            [Console]::Error.WriteLine("     Create the repo at https://github.com/new, then run this command again.")
            exit 1
        }
    } finally {
        Pop-Location
    }
}

# ─── INFO Command ─────────────────────────────────────────────────────────────

function Invoke-Info([string]$cardDir = ".") {
    Write-Header "Skill Card Summary"
    
    $profilePath = Join-Path $cardDir "profile.json"
    if (-not (Test-Path $profilePath)) {
        Write-Err "No profile.json found in $cardDir"
        Write-Host "  Run 'scoutica init' first." -ForegroundColor DarkGray
        exit 1
    }
    
    $profile = Get-Content $profilePath -Raw | ConvertFrom-Json
    Write-Host "  $($profile.name)" -ForegroundColor White -NoNewline; Write-Host ""
    Write-Host "  $($profile.title) ($($profile.seniority))" -ForegroundColor DarkGray
    Write-Host "  Availability: $($profile.availability)"
    Write-Host "  Skills: $($profile.skills.Count)"
    
    $evPath = Join-Path $cardDir "evidence.json"
    if (Test-Path $evPath) {
        $ev = Get-Content $evPath -Raw | ConvertFrom-Json
        Write-Host "  Evidence: $($ev.items.Count) items"
    }
    Write-Host ""
}

# ─── HELP Command ─────────────────────────────────────────────────────────────

function Invoke-Help {
    Write-Host ""
    Write-Host "  Scoutica Protocol $PROTOCOL_VERSION" -ForegroundColor White
    Write-Host "  PowerShell implementation $IMPLEMENTATION_VERSION" -ForegroundColor DarkGray
    Write-Host "  Capability set $CAPABILITY_SET" -ForegroundColor DarkGray
    Write-Host "  Your skills. Your rules. Your data." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Usage: scoutica <command> [options] [directory]" -ForegroundColor White
    Write-Host ""
    Write-Host "  Commands:" -ForegroundColor White
    Write-Host "    init          " -NoNewline -ForegroundColor Cyan; Write-Host "Create your Skill Card (interactive wizard)"
    Write-Host "    init --ai     " -NoNewline -ForegroundColor Cyan; Write-Host "Create card using AI assistant"
    Write-Host "    validate      " -NoNewline -ForegroundColor Cyan; Write-Host "Validate card against protocol schemas"
    Write-Host "    publish       " -NoNewline -ForegroundColor Cyan; Write-Host "Push card to GitHub"
    Write-Host "    info          " -NoNewline -ForegroundColor Cyan; Write-Host "Show card summary"
    Write-Host "    help          " -NoNewline -ForegroundColor Cyan; Write-Host "Show this help"
    Write-Host "    version       " -NoNewline -ForegroundColor Cyan; Write-Host "Show version"
    Write-Host ""
    Write-Host "  Learn more: https://github.com/traylinx/scoutica-protocol" -ForegroundColor Cyan
    Write-Host ""
}

function Invoke-Version {
    Write-Host "Scoutica Protocol $PROTOCOL_VERSION"
    Write-Host "PowerShell implementation $IMPLEMENTATION_VERSION"
    Write-Host "Capability set $CAPABILITY_SET"
}

# ─── Main Router ──────────────────────────────────────────────────────────────

$command = if ($args.Count -gt 0) { $args[0] } else { "help" }
$remaining = if ($args.Count -gt 1) { $args[1..($args.Count-1)] } else { @() }

switch ($command) {
    "init" {
        $ai = $remaining -contains "--ai"
        $dir = ($remaining | Where-Object { $_ -ne "--ai" } | Select-Object -First 1)
        if (-not $dir) { $dir = "." }
        if ($ai) { Invoke-InitAI -targetDir $dir }
        else { Invoke-Init -targetDir $dir }
    }
    "validate" { $d = ($remaining | Select-Object -First 1); if (-not $d) { $d = "." }; Invoke-Validate $d }
    "publish"  { $d = ($remaining | Select-Object -First 1); if (-not $d) { $d = "." }; Invoke-Publish $d }
    "info"     { $d = ($remaining | Select-Object -First 1); if (-not $d) { $d = "." }; Invoke-Info $d }
    "help"     { Invoke-Help }
    "--help"   { Invoke-Help }
    "-h"       { Invoke-Help }
    "version"  { Invoke-Version }
    "--version" { Invoke-Version }
    "-v"       { Invoke-Version }
    default    {
        if ($KNOWN_UNSUPPORTED_COMMANDS -contains $command) {
            [Console]::Error.WriteLine(
                "Command '$command' is not supported by PowerShell capability set $CAPABILITY_SET. " +
                "Use the POSIX implementation for this command."
            )
            exit 2
        }
        [Console]::Error.WriteLine(("Unknown command: {0}" -f $command))
        Invoke-Help
        exit 1
    }
}
