$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Installer = Join-Path $RepoRoot "install.ps1"
$ContractPath = Join-Path (Join-Path (Join-Path $RepoRoot "protocol") "platform") "cli_support_contract.json"
$HostExe = (Get-Process -Id $PID).Path
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("scoutica-windows-" + [guid]::NewGuid().ToString("N"))
$InstallHome = Join-Path $Work "installed"
$Cli = Join-Path (Join-Path $InstallHome "bin") "scoutica.ps1"
$Failures = 0
$OriginalProcessPath = $env:Path
$HadProcessScouticaHome = Test-Path Env:SCOUTICA_HOME
$OriginalProcessScouticaHome = $env:SCOUTICA_HOME
$HadProcessInstallSource = Test-Path Env:SCOUTICA_INSTALL_SOURCE_ROOT
$OriginalProcessInstallSource = $env:SCOUTICA_INSTALL_SOURCE_ROOT
$OriginalUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$OriginalUserScouticaHome = [Environment]::GetEnvironmentVariable("SCOUTICA_HOME", "User")

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

function Invoke-Scoutica([string[]]$arguments, [AllowNull()][string]$stdinText = $null) {
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 wraps a child process's stderr as a
        # NativeCommandError. Expected negative-path invocations must capture
        # that diagnostic without the harness's Stop preference aborting first.
        $ErrorActionPreference = "Continue"
        if ($null -eq $stdinText) {
            $output = (& $HostExe -NoProfile -ExecutionPolicy Bypass -File $Cli @arguments 2>&1 | Out-String)
        } else {
            $output = ($stdinText | & $HostExe -NoProfile -ExecutionPolicy Bypass -File $Cli @arguments 2>&1 | Out-String)
        }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    return [PSCustomObject]@{ ExitCode = $exitCode; Output = $output }
}

function Resolve-InstalledResource([string]$relativePath) {
    $separator = [string][System.IO.Path]::DirectorySeparatorChar
    return Join-Path $InstallHome $relativePath.Replace('/', $separator)
}

function Invoke-InstallerContractFixture(
    [string]$name,
    [object[]]$resources,
    [AllowNull()][scriptblock]$prepare = $null,
    [switch]$invokeGlobalFunction
) {
    $sourceRoot = Join-Path $Work ("contract-source-" + $name)
    $fixtureHome = Join-Path $Work ("contract-home-" + $name)
    $contractDirectory = Join-Path (Join-Path $sourceRoot "protocol") "platform"
    New-Item -ItemType Directory -Force -Path $contractDirectory | Out-Null
    $fixtureContract = [ordered]@{
        contract_version = "1.0.0"
        protocol_version = "0.4.0"
        implementations = [ordered]@{
            windows = [ordered]@{
                capability_set = "windows-subset-v1"
            }
        }
        installation = [ordered]@{
            manifest_version = "1.0.0"
            contract_source = "protocol/platform/cli_support_contract.json"
            contract_destination = "cli_support_contract.json"
            resources = $resources
        }
    }
    Write-Utf8NoBom `
        (Join-Path $contractDirectory "cli_support_contract.json") `
        ($fixtureContract | ConvertTo-Json -Depth 10)
    if ($null -ne $prepare) { & $prepare $sourceRoot $fixtureHome }

    $savedHome = $env:SCOUTICA_HOME
    $savedSource = $env:SCOUTICA_INSTALL_SOURCE_ROOT
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $env:SCOUTICA_HOME = $fixtureHome
        $env:SCOUTICA_INSTALL_SOURCE_ROOT = $sourceRoot
        $ErrorActionPreference = "Continue"
        if ($invokeGlobalFunction) {
            $escapedInstaller = $Installer.Replace("'", "''")
            $harnessPath = Join-Path $Work ("global-function-" + $name + ".ps1")
            $harness = @'
. '__INSTALLER__'
Write-Output ("HARNESS_HOST_MAJOR={0}" -f $PSVersionTable.PSVersion.Major)
scoutica probe
'@
            $harness = $harness.Replace('__INSTALLER__', $escapedInstaller)
            Write-Utf8NoBom $harnessPath $harness
            $output = (& $HostExe -NoProfile -ExecutionPolicy Bypass -File $harnessPath 2>&1 | Out-String)
        } else {
            $output = (& $HostExe -NoProfile -ExecutionPolicy Bypass -File $Installer 2>&1 | Out-String)
        }
        $exitCode = $LASTEXITCODE
    } finally {
        $env:SCOUTICA_HOME = $savedHome
        $env:SCOUTICA_INSTALL_SOURCE_ROOT = $savedSource
        $ErrorActionPreference = $savedErrorActionPreference
    }
    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output = $output
        Home = $fixtureHome
        SourceRoot = $sourceRoot
    }
}

function Invoke-InstallerWithFakePython([string]$name, [ValidateSet("missing", "old")][string]$mode) {
    $fakeBin = Join-Path $Work ("fake-python-" + $name)
    $fixtureHome = Join-Path $Work ("python-home-" + $name)
    New-Item -ItemType Directory -Force -Path $fakeBin | Out-Null
    if ($mode -eq "missing") {
        $body = @'
@echo off
if exist "%~dp0seen-%~n0" exit /b 1
type nul > "%~dp0seen-%~n0"
exit /b 0
'@
    } else {
        $body = "@echo off`r`nexit /b 1`r`n"
    }
    foreach ($candidate in @("python3.13", "python3.12", "python3.11", "python3", "python", "py")) {
        Set-Content -LiteralPath (Join-Path $fakeBin ($candidate + ".cmd")) -Value $body -Encoding ASCII
    }

    $savedPath = $env:Path
    $savedHome = $env:SCOUTICA_HOME
    $savedSource = $env:SCOUTICA_INSTALL_SOURCE_ROOT
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $env:Path = "$fakeBin;$savedPath"
        $env:SCOUTICA_HOME = $fixtureHome
        $env:SCOUTICA_INSTALL_SOURCE_ROOT = $RepoRoot
        $ErrorActionPreference = "Continue"
        $output = (& $HostExe -NoProfile -ExecutionPolicy Bypass -File $Installer 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
    } finally {
        $env:Path = $savedPath
        $env:SCOUTICA_HOME = $savedHome
        $env:SCOUTICA_INSTALL_SOURCE_ROOT = $savedSource
        $ErrorActionPreference = $savedErrorActionPreference
    }
    return [PSCustomObject]@{ ExitCode = $exitCode; Output = $output; Home = $fixtureHome }
}

function New-TestJunction([string]$linkPath, [string]$targetPath) {
    New-Item -ItemType Directory -Force -Path $targetPath | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $linkPath) | Out-Null
    $command = 'mklink /J "{0}" "{1}"' -f $linkPath.Replace('"', '""'), $targetPath.Replace('"', '""')
    $output = (& cmd.exe /d /c $command 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
    return [PSCustomObject]@{
        Created = ($exitCode -eq 0 -and (Test-Path -LiteralPath $linkPath))
        Output = $output
    }
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
    return Invoke-Scoutica @("publish", $repo)
}

try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git is required for tests/windows.ps1"
    }
    New-Item -ItemType Directory -Force -Path $Work | Out-Null

    # Dependency failures must occur before any install-root mutation. Fake
    # every discoverable Python name so the test never falls through to the
    # runner's real interpreter.
    $result = Invoke-InstallerWithFakePython "missing-dependencies" "missing"
    Assert-Equal 1 $result.ExitCode "missing strict Python dependencies fail clean install"
    Assert-True ($result.Output -match [regex]::Escape("Run: python3 -m pip install 'jsonschema[format]' PyYAML")) "missing dependency guidance is exact"
    Assert-True (-not (Test-Path -LiteralPath $result.Home)) "missing dependencies leave SCOUTICA_HOME untouched"

    $result = Invoke-InstallerWithFakePython "old-python" "old"
    Assert-Equal 1 $result.ExitCode "unsupported Python versions fail clean install"
    Assert-True ($result.Output -match "Python 3\.11 or newer") "old-Python diagnostic states minimum version"
    Assert-True ($result.Output -match [regex]::Escape("Install Python 3.11+, then run: python3 -m pip install 'jsonschema[format]' PyYAML")) "old-Python guidance is exact"
    Assert-True (-not (Test-Path -LiteralPath $result.Home)) "old Python leaves SCOUTICA_HOME untouched"

    # Install into an isolated SCOUTICA_HOME from the current checkout. The
    # installer still executes its production resource-contract path; only the
    # byte source is local so CI never depends on the state of the main branch.
    $env:SCOUTICA_HOME = $InstallHome
    $env:SCOUTICA_INSTALL_SOURCE_ROOT = $RepoRoot
    $installOutput = (& $HostExe -NoProfile -ExecutionPolicy Bypass -File $Installer 2>&1 | Out-String)
    Assert-Equal 0 $LASTEXITCODE "clean Windows install succeeds"
    Assert-True ($installOutput -match "windows-subset-v1") "installer reports the exact capability set"
    Assert-True (Test-Path -LiteralPath $Cli -PathType Leaf) "tests execute the installed CLI, not the repository script"

    $contract = Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json
    $windows = $contract.implementations.windows
    $windowsResources = @($contract.installation.resources | Where-Object {
        @($_.platforms) -contains "windows"
    })
    foreach ($resource in $windowsResources) {
        $installedPath = Resolve-InstalledResource ([string]$resource.destination)
        Assert-True (Test-Path -LiteralPath $installedPath -PathType Leaf) ("installed resource: " + $resource.destination)
    }
    $installedContract = Resolve-InstalledResource ([string]$contract.installation.contract_destination)
    Assert-True (Test-Path -LiteralPath $installedContract -PathType Leaf) "installer preserves the capability/resource contract"
    Assert-Equal `
        (Get-FileHash -Algorithm SHA256 $ContractPath).Hash `
        (Get-FileHash -Algorithm SHA256 $installedContract).Hash `
        "installed contract is byte-equivalent to the source contract"
    $batchWrapperPath = Resolve-InstalledResource "bin/scoutica.cmd"
    Assert-True (Test-Path -LiteralPath $batchWrapperPath -PathType Leaf) "installer creates the command wrapper"
    $batchWrapperText = Get-Content -LiteralPath $batchWrapperPath -Raw
    Assert-True ($batchWrapperText -match [regex]::Escape($HostExe)) "command wrapper preserves the installer PowerShell host"

    # The local-source seam used by these tests must not weaken production
    # manifest boundaries. Try destination/source traversal and duplicate
    # destinations against the installer itself, not only the Python checker.
    $fixtureSource = "protocol/platform/cli_support_contract.json"
    $result = Invoke-InstallerContractFixture "destination-traversal" @(
        [ordered]@{
            source = $fixtureSource
            destination = "../destination-escaped.txt"
            platforms = @("windows")
        }
    )
    Assert-True ($result.ExitCode -ne 0) "installer rejects contract destination traversal"
    Assert-True ($result.Output -match "Unsafe installer destination") "destination traversal diagnostic is explicit"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Work "destination-escaped.txt"))) "destination traversal writes nothing outside SCOUTICA_HOME"

    $result = Invoke-InstallerContractFixture "source-traversal" @(
        [ordered]@{
            source = "../source-escaped.txt"
            destination = "bin/source-escaped.txt"
            platforms = @("windows")
        }
    )
    Assert-True ($result.ExitCode -ne 0) "installer rejects contract source traversal"
    Assert-True ($result.Output -match "Unsafe installer source") "source traversal diagnostic is explicit"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $result.Home "bin/source-escaped.txt"))) "source traversal installs no file"

    $result = Invoke-InstallerContractFixture "duplicate-destination" @(
        [ordered]@{
            source = $fixtureSource
            destination = "bin/duplicate.txt"
            platforms = @("windows")
        },
        [ordered]@{
            source = $fixtureSource
            destination = "bin//duplicate.txt"
            platforms = @("windows")
        }
    )
    Assert-True ($result.ExitCode -ne 0) "installer rejects duplicate contract destinations"
    Assert-True ($result.Output -match "Duplicate Windows resource destination") "duplicate destination diagnostic is explicit"

    # A manifest cannot omit any file required by the supported command layout.
    $result = Invoke-InstallerContractFixture "omitted-layout" @(
        [ordered]@{
            source = $fixtureSource
            destination = "bin/scoutica.ps1"
            platforms = @("windows")
        }
    )
    Assert-True ($result.ExitCode -ne 0) "installer rejects an incomplete supported layout"
    Assert-True ($result.Output -match [regex]::Escape("Resource contract did not install required file: bin/validate_card.py")) "omitted-resource diagnostic names the first missing requirement"

    # Existing junctions under either boundary must be rejected without
    # touching the outside victim. GitHub Windows runners support directory
    # junctions without elevated symlink privileges.
    $destinationVictimDir = Join-Path $Work "destination-junction-victim"
    $destinationVictimFile = Join-Path $destinationVictimDir "victim.txt"
    New-Item -ItemType Directory -Force -Path $destinationVictimDir | Out-Null
    Write-Utf8NoBom $destinationVictimFile "destination-victim-unchanged"
    $script:DestinationJunction = $null
    $destinationPrepare = {
        param($sourceRoot, $fixtureHome)
        New-Item -ItemType Directory -Force -Path $fixtureHome | Out-Null
        $script:DestinationJunction = New-TestJunction (Join-Path $fixtureHome "linked") $destinationVictimDir
    }
    $result = Invoke-InstallerContractFixture "destination-junction" @(
        [ordered]@{
            source = $fixtureSource
            destination = "linked/victim.txt"
            platforms = @("windows")
        }
    ) $destinationPrepare
    Assert-True ([bool]$script:DestinationJunction.Created) ("Windows runner must create destination junction: " + $script:DestinationJunction.Output)
    if ($script:DestinationJunction.Created) {
        Assert-True ($result.ExitCode -ne 0) "installer rejects destination junction"
        Assert-True ($result.Output -match "Installer destination contains a symlink or reparse point") "destination-junction diagnostic is explicit"
        Assert-Equal "destination-victim-unchanged" (Get-Content -LiteralPath $destinationVictimFile -Raw) "destination-junction victim remains unchanged"
    }

    $sourceVictimDir = Join-Path $Work "source-junction-victim"
    $sourceVictimFile = Join-Path $sourceVictimDir "payload.txt"
    New-Item -ItemType Directory -Force -Path $sourceVictimDir | Out-Null
    Write-Utf8NoBom $sourceVictimFile "source-victim-unchanged"
    $script:SourceJunction = $null
    $sourcePrepare = {
        param($sourceRoot, $fixtureHome)
        $script:SourceJunction = New-TestJunction (Join-Path $sourceRoot "linked") $sourceVictimDir
    }
    $result = Invoke-InstallerContractFixture "source-junction" @(
        [ordered]@{
            source = "linked/payload.txt"
            destination = "bin/copied.txt"
            platforms = @("windows")
        }
    ) $sourcePrepare
    Assert-True ([bool]$script:SourceJunction.Created) ("Windows runner must create source junction: " + $script:SourceJunction.Output)
    if ($script:SourceJunction.Created) {
        Assert-True ($result.ExitCode -ne 0) "installer rejects source junction"
        Assert-True ($result.Output -match "Installer source contains a symlink or reparse point") "source-junction diagnostic is explicit"
        Assert-Equal "source-victim-unchanged" (Get-Content -LiteralPath $sourceVictimFile -Raw) "source-junction victim remains unchanged"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $result.Home "bin/copied.txt"))) "source junction installs no file"
    }

    # Dot-source the installer and invoke its global function inside one child
    # host. A probe CLI reports the actual host major used by that function.
    $requiredWindowsLayout = @(
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
    $probeResources = @()
    foreach ($destination in $requiredWindowsLayout) {
        $probeResources += [ordered]@{
            source = "probe.ps1"
            destination = $destination
            platforms = @("windows")
        }
    }
    $probePrepare = {
        param($sourceRoot, $fixtureHome)
        Write-Utf8NoBom (Join-Path $sourceRoot "probe.ps1") 'Write-Output ("FUNCTION_HOST_MAJOR={0}" -f $PSVersionTable.PSVersion.Major)'
    }
    $result = Invoke-InstallerContractFixture "global-function" $probeResources $probePrepare -invokeGlobalFunction
    Assert-Equal 0 $result.ExitCode "installer global function executes in the installer child"
    Assert-True ($result.Output -match ("HARNESS_HOST_MAJOR=" + $PSVersionTable.PSVersion.Major)) "global-function harness uses current CI lane major"
    Assert-True ($result.Output -match ("FUNCTION_HOST_MAJOR=" + $PSVersionTable.PSVersion.Major)) "global function preserves current CI lane host major"

    # Truthful identity and exact help surface.
    $result = Invoke-Scoutica @("version")
    Assert-Equal 0 $result.ExitCode "version command succeeds"
    Assert-True ($result.Output -match [regex]::Escape("Scoutica Protocol $($contract.protocol_version)")) "version reports protocol identity"
    Assert-True ($result.Output -match [regex]::Escape("PowerShell implementation $($windows.implementation_version)")) "version reports implementation identity"
    Assert-True ($result.Output -match [regex]::Escape("Capability set $($windows.capability_set)")) "version reports capability identity"
    Assert-True ($result.Output -notmatch "CLI v0\.4\.0") "version does not imply full CLI parity"
    $wrapperOutput = (& $batchWrapperPath version 2>&1 | Out-String)
    Assert-Equal 0 $LASTEXITCODE "installed command wrapper executes"
    Assert-True ($wrapperOutput -match [regex]::Escape($windows.capability_set)) "installed command wrapper reaches the same capability identity"

    foreach ($alias in $windows.command_aliases.version) {
        $aliasResult = Invoke-Scoutica @([string]$alias)
        Assert-Equal 0 $aliasResult.ExitCode ("version alias succeeds: " + $alias)
        Assert-True ($aliasResult.Output -match [regex]::Escape($windows.capability_set)) ("version alias reports capability: " + $alias)
    }

    $result = Invoke-Scoutica @("help")
    Assert-Equal 0 $result.ExitCode "help command succeeds"
    foreach ($supported in $windows.supported_commands) {
        Assert-True ($result.Output -match [regex]::Escape([string]$supported)) ("help advertises supported command: " + $supported)
    }
    foreach ($unsupported in $windows.known_unsupported_commands) {
        Assert-True ($result.Output -notmatch ("(?m)^\s+" + [regex]::Escape([string]$unsupported) + "(?:\s|$)")) ("help omits unsupported command: " + $unsupported)
    }
    foreach ($alias in $windows.command_aliases.help) {
        $aliasResult = Invoke-Scoutica @([string]$alias)
        Assert-Equal 0 $aliasResult.ExitCode ("help alias succeeds: " + $alias)
        Assert-True ($aliasResult.Output -match [regex]::Escape($windows.capability_set)) ("help alias reports capability: " + $alias)
    }
    $result = Invoke-Scoutica ([string[]]@())
    Assert-Equal 0 $result.ExitCode "no-argument invocation defaults to help"
    Assert-True ($result.Output -match [regex]::Escape($windows.capability_set)) "no-argument help reports capability identity"

    # Every known POSIX-only top-level command is deliberately unsupported
    # (exit 2); a genuine typo remains a distinct unknown-command error (exit 1).
    foreach ($unsupported in $windows.known_unsupported_commands) {
        $result = Invoke-Scoutica @([string]$unsupported)
        Assert-Equal 2 $result.ExitCode ("known unsupported command exits 2: " + $unsupported)
        Assert-True ($result.Output -match [regex]::Escape($windows.capability_set)) ("unsupported diagnostic names capability set: " + $unsupported)
    }
    $result = Invoke-Scoutica @("definitely-not-a-command")
    Assert-Equal 1 $result.ExitCode "unknown command typo exits 1"
    Assert-True ($result.Output -match "Unknown command") "unknown command diagnostic is explicit"

    # init --ai is a supported handoff, not an alias for the POSIX scan runtime.
    $aiTarget = Join-Path $Work "ai-card"
    $result = Invoke-Scoutica @("init", "--ai", $aiTarget) "n`n"
    Assert-Equal 0 $result.ExitCode "init --ai handoff succeeds"
    Assert-True ($result.Output -match "GENERATE_MY_CARD\.md") "init --ai points to the installed AI guide"

    # Exercise the interactive wizard through redirected stdin, then validate
    # the generated card using only the isolated install layout.
    $initCard = Join-Path $Work "initialized-card"
    New-Item -ItemType Directory -Force -Path $initCard | Out-Null
    $initAnswers = @(
        "Alice Developer",
        "Backend Engineer",
        "4",
        "8",
        "1",
        "Backend Engineering",
        "Python, SQL",
        "Docker",
        "",
        "",
        "",
        "BSc Computer Science",
        "Backend engineer using Python and SQL.",
        "y",
        "n",
        "n",
        "n",
        "n",
        "80000",
        "1",
        "",
        "Python",
        "1",
        "n"
    ) -join "`n"
    $result = Invoke-Scoutica @("init", $initCard) ($initAnswers + "`n")
    Assert-Equal 0 $result.ExitCode "interactive init succeeds"
    foreach ($cardFile in @("profile.json", "rules.yaml", "evidence.json", "SKILL.md", ".gitignore")) {
        Assert-True (Test-Path -LiteralPath (Join-Path $initCard $cardFile) -PathType Leaf) ("init creates " + $cardFile)
    }
    Assert-Equal `
        (Get-FileHash -Algorithm SHA256 (Join-Path $RepoRoot "protocol/templates/card.gitignore")).Hash `
        (Get-FileHash -Algorithm SHA256 (Join-Path $initCard ".gitignore")).Hash `
        "init installs the canonical card.gitignore"

    # Windows can expose python3* Store aliases ahead of setup-python's working
    # python.exe. Runtime validation must probe and skip those aliases instead
    # of treating command-name presence as a usable interpreter.
    $shadowPythonBin = Join-Path $Work "shadow-python-aliases"
    New-Item -ItemType Directory -Force -Path $shadowPythonBin | Out-Null
    foreach ($candidate in @("python3.13", "python3.12", "python3.11", "python3")) {
        Set-Content -LiteralPath (Join-Path $shadowPythonBin ($candidate + ".cmd")) `
            -Value "@echo off`r`nexit /b 1`r`n" -Encoding ASCII
    }
    $savedPath = $env:Path
    try {
        $env:Path = "$shadowPythonBin;$savedPath"
        $result = Invoke-Scoutica @("validate", $initCard)
    } finally {
        $env:Path = $savedPath
    }
    if ($result.ExitCode -ne 0) { Write-Host $result.Output }
    Assert-Equal 0 $result.ExitCode "installed validate accepts the initialized card"
    Assert-True ($result.Output -match "Candidate Card is valid!") "validation reports success"

    $invalidCard = Join-Path $Work "invalid-card"
    New-Item -ItemType Directory -Force -Path $invalidCard | Out-Null
    Write-Utf8NoBom (Join-Path $invalidCard "profile.json") '{}'
    $result = Invoke-Scoutica @("validate", $invalidCard)
    Assert-True ($result.ExitCode -ne 0) "installed validate propagates validation failure"

    $result = Invoke-Scoutica @("info", $initCard)
    Assert-Equal 0 $result.ExitCode "info command succeeds"
    Assert-True ($result.Output -match "Alice Developer") "info summarizes the initialized card"
    $missingInfoCard = Join-Path $Work "missing-info-card"
    New-Item -ItemType Directory -Force -Path $missingInfoCard | Out-Null
    $result = Invoke-Scoutica @("info", $missingInfoCard)
    Assert-Equal 1 $result.ExitCode "info fails when profile.json is absent"
    Assert-True ($result.Output -match "No profile\.json found") "info failure is explicit"

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
    [Environment]::SetEnvironmentVariable("Path", $OriginalUserPath, "User")
    [Environment]::SetEnvironmentVariable("SCOUTICA_HOME", $OriginalUserScouticaHome, "User")
    $env:Path = $OriginalProcessPath
    if ($HadProcessScouticaHome) {
        $env:SCOUTICA_HOME = $OriginalProcessScouticaHome
    } else {
        Remove-Item Env:SCOUTICA_HOME -ErrorAction SilentlyContinue
    }
    if ($HadProcessInstallSource) {
        $env:SCOUTICA_INSTALL_SOURCE_ROOT = $OriginalProcessInstallSource
    } else {
        Remove-Item Env:SCOUTICA_INSTALL_SOURCE_ROOT -ErrorAction SilentlyContinue
    }
    if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
}

if ($Failures -gt 0) {
    Write-Error "$Failures Windows assertion(s) failed" -ErrorAction Continue
    exit 1
}
Write-Host "All Windows capability, install, and publication assertions passed."
exit 0
