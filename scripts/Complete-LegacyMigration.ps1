$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Authentication.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Graph.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Legacy.psm1') -Force
Import-AzdEnvironment; Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.30.0 -Force
$configuration=Get-AzdRiskCaConfiguration; $path=Get-AzdRiskCaDataPath 'legacy-migration-state.json'
if (-not (Test-Path -LiteralPath $path)) { throw 'No staged legacy migration exists.' }
$state=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
$tenantId=(az account show --query tenantId -o tsv).Trim(); Connect-AzdRiskCaGraph ([guid]$tenantId) $configuration | Out-Null
$confirmation=Read-Host "Type tenant ID $tenantId to enable the replicas before legacy portal disablement"
Assert-AzdRiskCaTenantConfirmation $tenantId $confirmation
$portalUrls=@('https://portal.azure.com/#view/Microsoft_AAD_IAM/IdentityProtectionMenuBlade/~/UserRiskPolicy','https://portal.azure.com/#view/Microsoft_AAD_IAM/IdentityProtectionMenuBlade/~/SignInRiskPolicy')
Write-Host 'Replicas will be enabled first. You must then disable the applicable legacy policies in both portal pages.'
foreach($url in $portalUrls){ Write-Host $url }
$result=Invoke-AzdRiskCaLegacyCutover $state $tenantId $false
Save-AzdRiskCaJson $result.comparison (Join-Path (Split-Path -Parent $PSScriptRoot) 'reports/legacy-cutover-comparison.json')
foreach($url in $portalUrls){ try { Start-Process $url } catch { Write-Warning "Could not open $url automatically." } }
$attestation=Read-Host 'After disabling every applicable legacy policy in the portal, type DISABLED; otherwise press Enter'
$result.state.stage=if($attestation -ceq 'DISABLED'){'cutoverComplete'}else{'cutoverIncomplete'}
$result.state.operatorAttestation=[pscustomobject]@{ legacyPortalDisabled=($attestation -ceq 'DISABLED'); attestedAt=[DateTimeOffset]::UtcNow.ToString('o'); apiVerified=$false }
Save-AzdRiskCaJson $result.state $path
if ($result.state.stage -eq 'cutoverIncomplete') { Write-Warning 'Cutover is incomplete. Replacement coverage remains enabled; rerun this script after completing portal disablement.' } else { Write-Host 'Legacy disablement recorded as operator-attested (not API-verified).' }
