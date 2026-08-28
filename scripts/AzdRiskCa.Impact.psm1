Set-StrictMode -Version Latest

$script:GraphBetaBatchUri = 'https://graph.microsoft.com/beta/$batch'
$script:RiskyUsersPortalUri = 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/IdentityProtectionMenuBlade/~/RiskyUsers'
$script:RiskySignInsPortalUri = 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/IdentityProtectionMenuBlade/~/RiskySignIns'
$script:EvaluatedPolicies = @(
    [pscustomobject]@{ name='Admin-SignInRisk-High-Block'; metricId='signInHigh'; note='Tenant-wide high-risk sign-in events; administrator targeting and exclusions are not applied.' }
    [pscustomobject]@{ name='Admin-SignInRisk-LowMedium-RequireMFA'; metricId='signInLowMedium'; note='Tenant-wide low- or medium-risk sign-in events; administrator targeting and exclusions are not applied.' }
    [pscustomobject]@{ name='Admin-UserRisk-MediumHigh-Block'; metricId='riskyUserMediumHighCurrent'; note='Current tenant-wide medium/high risky users; administrator targeting and exclusions are not applied.' }
    [pscustomobject]@{ name='User-SignInRisk-MediumHigh-RequireMFA'; metricId='signInMediumHigh'; note='Tenant-wide medium/high-risk sign-in events; Conditional Access targeting and exclusions are not applied.' }
    [pscustomobject]@{ name='User-UserRisk-High-RiskRemediation'; metricId='riskyUserHighCurrent'; note='Current tenant-wide high-risk users; internal-user targeting and exclusions are not applied.' }
)
$script:UnevaluatedPolicyNames = @(
    'User-UserRisk-Any-Block-SecurityInfoRegistration'
    'User-SignInRisk-Any-Block-SecurityInfoRegistration'
    'User-UserRisk-Any-RequireStrongAuth-DeviceRegistration'
    'User-SignInRisk-Any-RequireStrongAuth-DeviceRegistration'
)

function Get-AzdRiskCaImpactProperty {
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-AzdRiskCaIdentityProtectionLinks {
    [CmdletBinding()] param()
    return [pscustomobject]@{
        riskyUsers = $script:RiskyUsersPortalUri
        riskySignIns = $script:RiskySignInsPortalUri
    }
}

function New-AzdRiskCaImpactCountUrl {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Filter)
    return "/$Path/`$count?`$filter=$([uri]::EscapeDataString($Filter))"
}

function New-AzdRiskCaImpactBatchRequest {
    param([Parameter(Mandatory)][DateTimeOffset]$Start, [Parameter(Mandatory)][DateTimeOffset]$End)
    $startText = $Start.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $endText = $End.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $dateFilter = "createdDateTime ge $startText and createdDateTime lt $endText"
    $userSignIns = "(signInEventTypes/any(t: t eq 'interactiveUser') or signInEventTypes/any(t: t eq 'nonInteractiveUser'))"
    $currentRisk = "(riskState eq 'atRisk' or riskState eq 'confirmedCompromised') and isDeleted eq false"
    $definitions = @(
        [pscustomobject]@{ id='signInHigh'; path='auditLogs/signIns'; filter="$dateFilter and riskLevelDuringSignIn eq 'high' and $userSignIns"; kind='historicalSignInEvents'; label='High-risk sign-in events during the reporting period' }
        [pscustomobject]@{ id='signInLowMedium'; path='auditLogs/signIns'; filter="$dateFilter and (riskLevelDuringSignIn eq 'low' or riskLevelDuringSignIn eq 'medium') and $userSignIns"; kind='historicalSignInEvents'; label='Low- or medium-risk sign-in events during the reporting period' }
        [pscustomobject]@{ id='signInMediumHigh'; path='auditLogs/signIns'; filter="$dateFilter and (riskLevelDuringSignIn eq 'medium' or riskLevelDuringSignIn eq 'high') and $userSignIns"; kind='historicalSignInEvents'; label='Medium- or high-risk sign-in events during the reporting period' }
        [pscustomobject]@{ id='riskyUserHighCurrent'; path='identityProtection/riskyUsers'; filter="$currentRisk and riskLevel eq 'high'"; kind='currentRiskyUsers'; label='Currently actionable high-risk users' }
        [pscustomobject]@{ id='riskyUserMediumHighCurrent'; path='identityProtection/riskyUsers'; filter="$currentRisk and (riskLevel eq 'medium' or riskLevel eq 'high')"; kind='currentRiskyUsers'; label='Currently actionable medium- or high-risk users' }
    )
    $requests = foreach ($definition in $definitions) {
        [ordered]@{
            id = $definition.id
            method = 'GET'
            url = New-AzdRiskCaImpactCountUrl $definition.path $definition.filter
            headers = @{ ConsistencyLevel='eventual' }
        }
    }
    return [pscustomobject]@{ definitions=$definitions; body=[ordered]@{ requests=@($requests) } }
}

function New-AzdRiskCaUnavailableMetric {
    param([Parameter(Mandatory)][object]$Definition, [Parameter(Mandatory)][string]$Status)
    return [pscustomobject]@{
        id = $Definition.id
        label = $Definition.label
        kind = $Definition.kind
        available = $false
        count = $null
        status = $Status
    }
}

function ConvertFrom-AzdRiskCaImpactBatchResponse {
    param([Parameter(Mandatory)][object]$BatchResponse, [Parameter(Mandatory)][object[]]$Definitions)
    $responses = @(Get-AzdRiskCaImpactProperty $BatchResponse 'responses')
    $metrics = [System.Collections.Generic.List[object]]::new()
    foreach ($definition in $Definitions) {
        $response = @($responses | Where-Object { [string]$_.id -eq [string]$definition.id }) | Select-Object -First 1
        if (-not $response) {
            $metrics.Add((New-AzdRiskCaUnavailableMetric $definition 'missingResponse'))
            continue
        }
        $statusCode = [int](Get-AzdRiskCaImpactProperty $response 'status')
        $count = 0L
        $body = Get-AzdRiskCaImpactProperty $response 'body'
        if ($statusCode -ne 200 -or -not [long]::TryParse([string]$body, [ref]$count)) {
            $metrics.Add((New-AzdRiskCaUnavailableMetric $definition "http$statusCode"))
            continue
        }
        $metrics.Add([pscustomobject]@{
            id = $definition.id
            label = $definition.label
            kind = $definition.kind
            available = $true
            count = $count
            status = 'available'
        })
    }
    return @($metrics)
}

function Get-AzdRiskCaMetricDisplayValue {
    param([Parameter(Mandatory)][object]$Metric)
    if ($Metric.available) { return [string]$Metric.count }
    return 'unavailable'
}

function Get-AzdRiskCaHistoricalImpact {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][object]$Plan,
        [ValidateRange(1,30)][int]$Days = 30,
        [DateTimeOffset]$AsOf = [DateTimeOffset]::UtcNow
    )
    $end = $AsOf.ToUniversalTime()
    $start = $end.AddDays(-$Days)
    $batch = New-AzdRiskCaImpactBatchRequest $start $end
    try {
        $response = Invoke-AzdRiskCaGraphRequest POST $script:GraphBetaBatchUri $batch.body
        $metrics = @(ConvertFrom-AzdRiskCaImpactBatchResponse $response @($batch.definitions))
        $batchStatus = 'completed'
    } catch {
        $metrics = @($batch.definitions | ForEach-Object { New-AzdRiskCaUnavailableMetric $_ 'batchRequestFailed' })
        $batchStatus = 'failed'
    }

    $metricById = @{}
    foreach ($metric in $metrics) { $metricById[$metric.id] = $metric }
    $policies = [System.Collections.Generic.List[object]]::new()
    foreach ($mapping in $script:EvaluatedPolicies) {
        $metric = $metricById[$mapping.metricId]
        $policies.Add([pscustomobject]@{
            name = $mapping.name
            evaluable = $true
            metricId = $mapping.metricId
            available = $metric.available
            count = $metric.count
            unit = if ($metric.kind -eq 'historicalSignInEvents') { 'signInEvents' } else { 'users' }
            targetingApplied = $false
            note = $mapping.note
        })
    }
    foreach ($name in $script:UnevaluatedPolicyNames) {
        $policies.Add([pscustomobject]@{
            name = $name
            evaluable = $false
            metricId = $null
            available = $false
            count = $null
            unit = $null
            targetingApplied = $false
            note = 'Graph sign-in and risky-user reports do not identify security-info or device-registration attempts reliably.'
        })
    }

    $highSignIns = Get-AzdRiskCaMetricDisplayValue $metricById.signInHigh
    $lowMediumSignIns = Get-AzdRiskCaMetricDisplayValue $metricById.signInLowMedium
    $mediumHighSignIns = Get-AzdRiskCaMetricDisplayValue $metricById.signInMediumHigh
    $highUsers = Get-AzdRiskCaMetricDisplayValue $metricById.riskyUserHighCurrent
    $mediumHighUsers = Get-AzdRiskCaMetricDisplayValue $metricById.riskyUserMediumHighCurrent
    $summary = "Previous $Days days: $highSignIns high-risk, $lowMediumSignIns low/medium-risk, and $mediumHighSignIns medium/high-risk user sign-in events. Currently: $highUsers high-risk and $mediumHighUsers medium/high-risk users. Counts are tenant-wide and do not apply Conditional Access targeting or exclusions."

    return [pscustomobject]@{
        schemaVersion = '2.0'
        generatedAt = $end.ToString('o')
        tenantId = [string]$Plan.tenantId
        period = [pscustomobject]@{ days=$Days; start=$start.ToString('o'); end=$end.ToString('o') }
        estimate = [pscustomobject]@{ summary=$summary; measurements=$metrics }
        policies = @($policies)
        dataQuality = [pscustomobject]@{
            batchStatus = $batchStatus
            availableMeasurements = @($metrics | Where-Object available).Count
            unavailableMeasurements = @($metrics | Where-Object available -eq $false).Count
            countEndpointContract = 'The filtered /$count behavior is live-validated but not documented for these collection APIs; unavailable counts are never replaced with zero.'
        }
        investigate = Get-AzdRiskCaIdentityProtectionLinks
        assumptions = @(
            'Sign-in measurements count events, not distinct users.'
            'Risky-user measurements are a current actionable snapshot, not a historical count.'
            'All measurements are tenant-wide upper bounds before current policy targeting, administrator membership, internal-user classification, and exclusions.'
            'Interactive and noninteractive user sign-ins are included; workload identity event types are excluded.'
            'Security-info registration and device-registration policies are intentionally not estimated.'
        )
    }
}

Export-ModuleMember -Function *
