$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Cli = Join-Path (Join-Path $RepoRoot "tools") "scoutica.ps1"
$HostExe = (Get-Process -Id $PID).Path
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("scoutica-windows-" + [guid]::NewGuid().ToString("N"))
$Failures = 0

function Assert-True([bool]$condition, [string]$message) {
    if ($condition) {
        Write-Host "PASS: $message"
    } else {
        $script:Failures += 1
        Write-Error "FAIL: $message" -ErrorAction Continue
    }
}

function Assert-Equal($expected, $actual, [string]$message) {
    Assert-True ($expected -eq $actual) "$message (expected=$expected actual=$actual)"
}

function Invoke-TestGit([string]$directory, [string[]]$gitArguments) {
    & git -C $directory @gitArguments >$null 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git -C '$directory' $($gitArguments -join ' ') failed with $LASTEXITCODE"
    }
}

function Write-Utf8NoBom([string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
}

function New-TestRepository([string]$name, [bool]$withOrigin) {
    $repo = Join-Path $Work $name
    $remote = Join-Path $Work "$name.git"
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    & git init $repo >$null 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git init failed" }
    Invoke-TestGit $repo @("config", "user.name", "Alice Developer")
    Invoke-TestGit $repo @("config", "user.email", "alice@example.test")
    Write-Utf8NoBom (Join-Path $repo "profile.json") '{"schema_version":"0.1.0","title":"Backend Engineer"}'
    Invoke-TestGit $repo @("add", "--", "profile.json")
    Invoke-TestGit $repo @("commit", "-m", "initial card")
    Invoke-TestGit $repo @("branch", "-M", "main")
    if ($withOrigin) {
        & git init --bare $remote >$null 2>&1
        if ($LASTEXITCODE -ne 0) { throw "bare git init failed" }
        Invoke-TestGit $repo @("remote", "add", "origin", $remote)
        Invoke-TestGit $repo @("push", "-u", "origin", "main")
    }
    return [PSCustomObject]@{ Repo = $repo; Remote = $remote }
}

function Invoke-ScouticaPublish([string]$repo) {
    $output = (& $HostExe -NoProfile -ExecutionPolicy Bypass -File $Cli publish $repo 2>&1 | Out-String)
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git is required for tests/windows.ps1"
    }
    New-Item -ItemType Directory -Force -Path $Work | Out-Null

    # F-01: a pre-staged unrelated path is named, refused before staging, and
    # leaves both the index and remote branch unchanged.
    $case = New-TestRepository "prestaged-secret" $true
    Write-Utf8NoBom (Join-Path $case.Repo ".env") "SECRET=fixture-only"
    Invoke-TestGit $case.Repo @("add", "--", ".env")
    $indexPath = Join-Path (Join-Path $case.Repo ".git") "index"
    $indexBefore = (Get-FileHash -Algorithm SHA256 $indexPath).Hash
    $remoteBefore = (& git --git-dir=$($case.Remote) rev-parse refs/heads/main).Trim()
    $result = Invoke-ScouticaPublish $case.Repo
    $indexAfter = (Get-FileHash -Algorithm SHA256 $indexPath).Hash
    $remoteAfter = (& git --git-dir=$($case.Remote) rev-parse refs/heads/main).Trim()
    Assert-Equal 1 $result.ExitCode "non-canonical pre-staged path returns nonzero"
    Assert-True ($result.Output -match [regex]::Escape(".env")) "refusal names the blocked path"
    Assert-Equal $indexBefore $indexAfter "refusal leaves index byte-equivalent"
    Assert-Equal $remoteBefore $remoteAfter "refusal does not push"
    Assert-True ($result.Output -notmatch "Pushed to GitHub") "refusal prints no success"

    # Canonical pre-staging is allowed; only exact rule files are added, never
    # an arbitrary file merely because it lives below rules/.
    $case = New-TestRepository "canonical-success" $true
    Write-Utf8NoBom (Join-Path $case.Repo "profile.json") '{"schema_version":"0.1.0","title":"Updated Engineer"}'
    Invoke-TestGit $case.Repo @("add", "--", "profile.json")
    $rulesDir = Join-Path $case.Repo "rules"
    New-Item -ItemType Directory -Force -Path $rulesDir | Out-Null
    Write-Utf8NoBom (Join-Path $rulesDir "secret.txt") "fixture must remain untracked"
    $result = Invoke-ScouticaPublish $case.Repo
    Assert-Equal 0 $result.ExitCode "canonical staged update publishes"
    Assert-True ($result.Output -match "Pushed to GitHub") "successful push reports success"
    & git --git-dir=$($case.Remote) cat-file -e "main:rules/secret.txt" 2>$null
    Assert-True ($LASTEXITCODE -ne 0) "non-canonical rules child is not committed"
    $remoteProfile = (& git --git-dir=$($case.Remote) show "main:profile.json" | Out-String)
    Assert-True ($remoteProfile -match "Updated Engineer") "canonical update reaches origin"

    # F-14: origin is required before Scoutica stages or commits anything.
    $case = New-TestRepository "missing-origin" $false
    Write-Utf8NoBom (Join-Path $case.Repo "profile.json") '{"schema_version":"0.1.0","title":"No Origin"}'
    $headBefore = (& git -C $case.Repo rev-parse HEAD).Trim()
    $indexBefore = (Get-FileHash -Algorithm SHA256 (Join-Path (Join-Path $case.Repo ".git") "index")).Hash
    $result = Invoke-ScouticaPublish $case.Repo
    $headAfter = (& git -C $case.Repo rev-parse HEAD).Trim()
    $indexAfter = (Get-FileHash -Algorithm SHA256 (Join-Path (Join-Path $case.Repo ".git") "index")).Hash
    Assert-Equal 1 $result.ExitCode "missing origin returns nonzero"
    Assert-True ($result.Output -match "No remote 'origin'") "missing origin is explicit"
    Assert-Equal $headBefore $headAfter "missing origin creates no commit"
    Assert-Equal $indexBefore $indexAfter "missing origin leaves index unchanged"
    Assert-True ($result.Output -notmatch "Pushed to GitHub") "missing origin prints no success"

    # A real commit failure is distinct from an up-to-date tree and must stop
    # before push. Git for Windows executes extensionless hooks through sh.
    $case = New-TestRepository "commit-failure" $true
    Write-Utf8NoBom (Join-Path $case.Repo "profile.json") '{"schema_version":"0.1.0","title":"Commit Refused"}'
    $hook = Join-Path (Join-Path (Join-Path $case.Repo ".git") "hooks") "pre-commit"
    Write-Utf8NoBom $hook "#!/bin/sh`nexit 1`n"
    $remoteBefore = (& git --git-dir=$($case.Remote) rev-parse refs/heads/main).Trim()
    $result = Invoke-ScouticaPublish $case.Repo
    $remoteAfter = (& git --git-dir=$($case.Remote) rev-parse refs/heads/main).Trim()
    Assert-Equal 1 $result.ExitCode "commit failure returns nonzero"
    Assert-True ($result.Output -match "Commit failed") "commit failure is explicit"
    Assert-Equal $remoteBefore $remoteAfter "commit failure does not push"
    Assert-True ($result.Output -notmatch "Pushed to GitHub") "commit failure prints no success"

    # A configured origin can still fail at push time; publication must remain
    # nonzero and must never emit the success marker.
    $case = New-TestRepository "push-failure" $true
    Write-Utf8NoBom (Join-Path $case.Repo "profile.json") '{"schema_version":"0.1.0","title":"Push Refused"}'
    Remove-Item -Recurse -Force $case.Remote
    $result = Invoke-ScouticaPublish $case.Repo
    Assert-Equal 1 $result.ExitCode "push failure returns nonzero"
    Assert-True ($result.Output -match "Push failed") "push failure is explicit"
    Assert-True ($result.Output -notmatch "Pushed to GitHub") "push failure prints no success"
} finally {
    if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
}

if ($Failures -gt 0) {
    Write-Error "$Failures Windows publish assertion(s) failed" -ErrorAction Continue
    exit 1
}
Write-Host "All Windows publish assertions passed."
exit 0
