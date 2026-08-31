[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$pollerRoot = Join-Path $repositoryRoot 'src/risk-notification-poller'

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)] [string] $Tool,
        [Parameter(Mandatory)] [scriptblock] $Action
    )

    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Tool failed with exit code $LASTEXITCODE."
    }
}

foreach ($command in 'az', 'git', 'node', 'npm') {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "$command is required for repository validation."
    }
}

Write-Host 'Parsing repository PowerShell files.'
$parseErrors = [System.Collections.Generic.List[object]]::new()
$powerShellFiles = @(
    Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File |
        Where-Object {
            $_.Extension -in '.ps1', '.psm1', '.psd1' -and
            $_.FullName -notmatch '[\\/](?:\.azure|node_modules|reports)[\\/]'
        }
)
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $fileErrors = $null
    [void] [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref] $tokens,
        [ref] $fileErrors
    )
    foreach ($parseError in @($fileErrors)) {
        $parseErrors.Add($parseError)
    }
}
if ($parseErrors.Count -gt 0) {
    throw ($parseErrors | Format-List | Out-String)
}

Write-Host 'Running PSScriptAnalyzer.'
Import-Module PSScriptAnalyzer -MinimumVersion 1.25.0 -Force -ErrorAction Stop
$analysis = @(Invoke-ScriptAnalyzer -Path (Join-Path $repositoryRoot 'scripts') -Recurse -Severity Error)
if ($analysis.Count -gt 0) {
    throw ($analysis | Format-Table -AutoSize | Out-String)
}

Write-Host 'Validating tracked JSON and the component inventory.'
$trackedJson = @(& git -C $repositoryRoot ls-files -- '*.json')
if ($LASTEXITCODE -ne 0) {
    throw 'git ls-files failed while locating tracked JSON files.'
}
foreach ($relativePath in $trackedJson) {
    Get-Content -LiteralPath (Join-Path $repositoryRoot $relativePath) -Raw |
        ConvertFrom-Json -Depth 100 -AsHashtable |
        Out-Null
}

$componentLockPath = Join-Path $repositoryRoot 'azd-components.lock.json'
$componentLockSchemaPath = Join-Path $repositoryRoot 'schemas/azd-components-lock.schema.json'
$componentLockJson = Get-Content -LiteralPath $componentLockPath -Raw
if (-not ($componentLockJson | Test-Json -SchemaFile $componentLockSchemaPath -ErrorAction Stop)) {
    throw 'azd-components.lock.json does not satisfy the checked-in component lock schema.'
}

Write-Host 'Running repository Pester tests without tenant access.'
Import-Module Pester -MinimumVersion 5.7.1 -Force -ErrorAction Stop
Set-StrictMode -Off
try {
    $pesterResult = Invoke-Pester -Path (Join-Path $repositoryRoot 'tests') -Output Detailed -PassThru
}
finally {
    Set-StrictMode -Version Latest
}
if ($pesterResult.FailedCount -gt 0) {
    throw "$($pesterResult.FailedCount) Pester test(s) failed."
}

Write-Host 'Checking and testing the notification poller.'
Invoke-CheckedCommand -Tool 'npm ci' -Action {
    & npm ci --ignore-scripts --prefix $pollerRoot
}
Invoke-CheckedCommand -Tool 'node --check' -Action {
    & node --check (Join-Path $pollerRoot 'src/index.js')
}
Invoke-CheckedCommand -Tool 'npm test' -Action {
    & npm test --prefix $pollerRoot
}
Invoke-CheckedCommand -Tool 'npm audit' -Action {
    & npm audit --omit=dev --audit-level=high --prefix $pollerRoot
}

Write-Host 'Building the root Bicep template to stdout.'
$bicepVersionOutput = (& az bicep version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "az bicep version failed with exit code $LASTEXITCODE."
}
if ($bicepVersionOutput -notmatch '^Bicep CLI version 0\.46\.1(?:\s|$)') {
    throw "Bicep CLI v0.46.1 is required; found: $bicepVersionOutput"
}
Invoke-CheckedCommand -Tool 'az bicep build' -Action {
    & az bicep build --file (Join-Path $repositoryRoot 'infra/main.bicep') --stdout --no-restore | Out-Null
}

Write-Host 'Checking committed and working changes for whitespace errors.'
Invoke-CheckedCommand -Tool 'git show --check HEAD' -Action {
    & git -C $repositoryRoot show --check --format= HEAD
}
Invoke-CheckedCommand -Tool 'git diff --check (working tree)' -Action {
    & git -C $repositoryRoot diff --check
}
Invoke-CheckedCommand -Tool 'git diff --cached --check' -Action {
    & git -C $repositoryRoot diff --cached --check
}

$baseReference = if ($env:GITHUB_BASE_REF) { "origin/$($env:GITHUB_BASE_REF)" } else { 'origin/main' }
& git -C $repositoryRoot rev-parse --verify --quiet "$baseReference^{commit}" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    $mergeBase = (& git -C $repositoryRoot merge-base HEAD $baseReference).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $mergeBase) {
        throw "Unable to determine the merge base with $baseReference."
    }
    Invoke-CheckedCommand -Tool "git diff --check $mergeBase..HEAD" -Action {
        & git -C $repositoryRoot diff --check "$mergeBase..HEAD"
    }
}

Write-Host "Repository validation passed: $($pesterResult.PassedCount) Pester tests plus PowerShell, schema-constrained JSON, Node, npm audit, pinned Bicep, and committed/working whitespace checks."
