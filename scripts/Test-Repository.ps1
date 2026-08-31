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

$componentLock = Get-Content -LiteralPath (Join-Path $repositoryRoot 'azd-components.lock.json') -Raw |
    ConvertFrom-Json -Depth 100
if ($componentLock.manifestVersion -ne '1.0') {
    throw 'azd-components.lock.json must use manifestVersion 1.0.'
}
if ($null -eq $componentLock.components) {
    throw 'azd-components.lock.json must contain a components array.'
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
Invoke-CheckedCommand -Tool 'az bicep version' -Action {
    & az bicep version | Out-Null
}
Invoke-CheckedCommand -Tool 'az bicep build' -Action {
    & az bicep build --file (Join-Path $repositoryRoot 'infra/main.bicep') --stdout | Out-Null
}

Write-Host 'Checking the working diff for whitespace errors.'
Invoke-CheckedCommand -Tool 'git diff --check' -Action {
    & git -C $repositoryRoot diff --check
}

Write-Host "Repository validation passed: $($pesterResult.PassedCount) Pester tests plus PowerShell, JSON, Node, npm audit, Bicep, and whitespace checks."
