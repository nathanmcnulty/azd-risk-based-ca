Set-StrictMode -Version Latest
$script:GraphBase='https://graph.microsoft.com/v1.0'

function Get-AzdRiskCaLegacyHash {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Value)
    $canonical=ConvertTo-AzdRiskCaComparable $Value
    if ($canonical -is [System.Collections.IDictionary]) { $canonical.Remove('state') }
    elseif ($canonical.PSObject.Properties['state']) { $canonical.PSObject.Properties.Remove('state') }
    $json=($canonical | ConvertTo-Json -Depth 100 -Compress)
    $bytes=[Text.Encoding]::UTF8.GetBytes($json)
    $hash=[Security.Cryptography.SHA256]::HashData($bytes)
    return ([Convert]::ToHexString($hash)).ToLowerInvariant()
}

function ConvertTo-AzdRiskCaLegacyFlatMap {
    [CmdletBinding()] param([AllowNull()][object]$Value, [string]$Path='')
    $result=[ordered]@{}
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or $Value -is [ValueType]) { $result[$Path]=$Value; return $result }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary]) { $result[$Path]=(@($Value) | ConvertTo-Json -Depth 100 -Compress); return $result }
    $properties=if($Value -is [System.Collections.IDictionary]){@($Value.Keys)}else{@($Value.PSObject.Properties.Name)}
    foreach($name in $properties){
        $childPath=if($Path){"$Path.$name"}else{[string]$name}
        $child=ConvertTo-AzdRiskCaLegacyFlatMap (Get-AzdRiskCaProperty $Value ([string]$name)) $childPath
        foreach($key in $child.Keys){$result[$key]=$child[$key]}
    }
    return $result
}

function Compare-AzdRiskCaLegacyFields {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Expected, [Parameter(Mandatory)][object]$Actual)
    $left=ConvertTo-AzdRiskCaLegacyFlatMap (ConvertTo-AzdRiskCaComparable $Expected)
    $right=ConvertTo-AzdRiskCaLegacyFlatMap (ConvertTo-AzdRiskCaComparable $Actual)
    $keys=@(@($left.Keys)+@($right.Keys) | Sort-Object -Unique)
    return @($keys | ForEach-Object { [pscustomobject]@{ field=$_; expected=$left[$_]; actual=$right[$_]; matches=(($left.Contains($_) -eq $right.Contains($_)) -and ([string]$left[$_] -ceq [string]$right[$_])) } })
}

function New-AzdRiskCaLegacyBody {
    [CmdletBinding()] param([Parameter(Mandatory)][ValidateSet('userRisk','signInRisk')][string]$Kind, [Parameter(Mandatory)][object]$Capture, [Parameter(Mandatory)][string]$EmergencyAccessGroupId)
    if (-not $Capture.enabled) { return $null }
    if (-not $Capture.policy) { throw "$Kind capture is enabled but has no policy object." }
    $source=$Capture.policy
    $body=[ordered]@{
        displayName=if($Kind -eq 'userRisk'){'LEGACY MIGRATED - User risk'}else{'LEGACY MIGRATED - Sign-in risk'}
        state='enabledForReportingButNotEnforced'
        conditions=$source.conditions
        grantControls=$source.grantControls
    }
    $sessionControls=Get-AzdRiskCaProperty $source 'sessionControls'
    if ($sessionControls) { $body.sessionControls=$sessionControls }
    $body.conditions = $body.conditions | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    if (-not $body.conditions.users) { throw "$Kind capture must include conditions.users." }
    $exclusions=@($body.conditions.users.excludeGroups) + @($EmergencyAccessGroupId)
    $body.conditions.users.excludeGroups=@($exclusions | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    if ($Kind -eq 'userRisk') {
        if (-not @($body.conditions.userRiskLevels).Count) { throw 'User-risk capture must contain userRiskLevels.' }
        $body.conditions.PSObject.Properties.Remove('signInRiskLevels')
    } else {
        if (-not @($body.conditions.signInRiskLevels).Count) { throw 'Sign-in-risk capture must contain signInRiskLevels.' }
        $body.conditions.PSObject.Properties.Remove('userRiskLevels')
    }
    return [pscustomobject]$body
}

function Invoke-AzdRiskCaLegacyStage {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Capture, [Parameter(Mandatory)][object]$Configuration, [Parameter(Mandatory)][string]$TenantId, [AllowNull()][object]$ExistingMigrationState, [scriptblock]$Checkpoint)
    if ([string]::IsNullOrWhiteSpace($Configuration.EmergencyAccessGroupId)) { throw 'Legacy staging requires AZD_CA_EMERGENCY_ACCESS_GROUP_ID.' }
    if ($Capture.tenantId -and [string]$Capture.tenantId -ne $TenantId) { throw 'Legacy capture belongs to a different tenant.' }
    Get-AzdRiskCaValidatedGroups @($Configuration.EmergencyAccessGroupId) | Out-Null
    $allPolicies=@(Get-AzdRiskCaGraphCollection "$script:GraphBase/identity/conditionalAccess/policies")
    if ($ExistingMigrationState -and $ExistingMigrationState.stage -ne 'staged') { throw 'Legacy replicas can be restaged only before cutover begins.' }
    $ownership=[pscustomobject]@{policies=[ordered]@{}}
    if ($ExistingMigrationState) { foreach($property in @($ExistingMigrationState.policies.PSObject.Properties)){ $ownership.policies[$property.Value.displayName]=$property.Value } }
    $state=[ordered]@{ schemaVersion='1.0'; tenantId=$TenantId; stage='staged'; stagedAt=[DateTimeOffset]::UtcNow.ToString('o'); cutoverAt=$null; retiredAt=$null; operatorAttestation=$null; policies=[ordered]@{} }
    if($ExistingMigrationState){foreach($property in @($ExistingMigrationState.policies.PSObject.Properties)){$state.policies[$property.Name]=$property.Value}}
    foreach ($kind in @('userRisk','signInRisk')) {
        $section=$Capture.$kind
        if (-not $section -or -not $section.enabled) { continue }
        $body=New-AzdRiskCaLegacyBody $kind $section $Configuration.EmergencyAccessGroupId
        $resolved=Resolve-AzdRiskCaPolicy $body $allPolicies $ownership $Configuration.AdoptExisting
        $id=$resolved.id
        if ($resolved.action -eq 'create') { $created=Invoke-AzdRiskCaGraphRequest POST "$script:GraphBase/identity/conditionalAccess/policies" $body; $id=[string]$created.id }
        elseif ($resolved.action -eq 'update') { Invoke-AzdRiskCaGraphRequest PATCH "$script:GraphBase/identity/conditionalAccess/policies/$id" $body | Out-Null }
        $actual=Invoke-AzdRiskCaGraphRequest GET "$script:GraphBase/identity/conditionalAccess/policies/$id"
        if (-not (Test-AzdRiskCaEquivalent $body $actual)) { throw "Staged $kind replica failed post-write verification." }
        $priorRecord=if($ExistingMigrationState){Get-AzdRiskCaProperty $ExistingMigrationState.policies $kind}else{$null}
        $previous=if($priorRecord){$priorRecord.previous}elseif($resolved.adopted){Select-AzdRiskCaDesiredShape $body $resolved.existing}else{$null}
        $state.policies[$kind]=[ordered]@{ id=$id; displayName=$body.displayName; desired=$body; legacyCapture=ConvertTo-AzdRiskCaComparable $section.policy; comparisonHash=Get-AzdRiskCaLegacyHash $body; created=if($priorRecord){[bool]$priorRecord.created}else{($resolved.action -eq 'create')}; adopted=if($priorRecord){[bool]$priorRecord.adopted}else{[bool]$resolved.adopted}; previous=$previous }
        if($Checkpoint){& $Checkpoint ([pscustomobject]$state)}
    }
    if ($state.policies.Count -eq 0) { throw 'The capture did not mark either legacy policy as enabled; no replicas were created.' }
    return [pscustomobject]$state
}

function Invoke-AzdRiskCaLegacyCutover {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$MigrationState, [Parameter(Mandatory)][string]$TenantId, [Parameter(Mandatory)][bool]$LegacyPortalDisabled)
    if ($MigrationState.tenantId -ne $TenantId) { throw 'Migration state belongs to a different tenant.' }
    $comparison=[System.Collections.Generic.List[object]]::new()
    foreach ($property in @($MigrationState.policies.PSObject.Properties)) {
        $record=$property.Value
        $actual=Invoke-AzdRiskCaGraphRequest GET "$script:GraphBase/identity/conditionalAccess/policies/$($record.id)"
        $actualShape=Select-AzdRiskCaDesiredShape $record.desired $actual
        $actualHash=Get-AzdRiskCaLegacyHash $actualShape
        $migrationStage=Get-AzdRiskCaProperty $MigrationState 'stage'
        $expectedStates=if($migrationStage -eq 'cutoverIncomplete'){@('enabled')}else{@('enabledForReportingButNotEnforced','enabled')}
        $matches=($actualHash -eq $record.comparisonHash) -and ($actual.state -in $expectedStates)
        $fieldComparison=Compare-AzdRiskCaLegacyFields $record.desired $actualShape
        $captured=Get-AzdRiskCaProperty $record 'legacyCapture'
        $replicaSettings=[ordered]@{conditions=$record.desired.conditions;grantControls=$record.desired.grantControls}
        $replicaSession=Get-AzdRiskCaProperty $record.desired 'sessionControls'
        if($replicaSession){$replicaSettings.sessionControls=$replicaSession}
        $legacySafetyComparison=if($captured){Compare-AzdRiskCaLegacyFields $captured ([pscustomobject]$replicaSettings)}else{@()}
        $comparison.Add([pscustomobject]@{ kind=$property.Name; policyId=$record.id; expectedHash=$record.comparisonHash; actualHash=$actualHash; matches=$matches; fieldComparison=$fieldComparison; legacyToReplicaComparison=$legacySafetyComparison; safetyDifference='Emergency-access group exclusion added by azd-risk-based-ca' })
        if (-not $matches) { throw "Legacy replica '$($record.displayName)' drifted after staging. Cutover stopped before enablement." }
    }
    foreach ($property in @($MigrationState.policies.PSObject.Properties)) {
        $record=$property.Value
        Invoke-AzdRiskCaGraphRequest PATCH "$script:GraphBase/identity/conditionalAccess/policies/$($record.id)" @{ state='enabled' } | Out-Null
        $actual=Invoke-AzdRiskCaGraphRequest GET "$script:GraphBase/identity/conditionalAccess/policies/$($record.id)"
        if ($actual.state -ne 'enabled') { throw "Legacy replica '$($record.displayName)' was not enabled; legacy disablement must not proceed." }
    }
    $MigrationState.stage=if($LegacyPortalDisabled){'cutoverComplete'}else{'cutoverIncomplete'}
    $MigrationState | Add-Member -NotePropertyName cutoverAt -NotePropertyValue ([DateTimeOffset]::UtcNow.ToString('o')) -Force
    $MigrationState | Add-Member -NotePropertyName operatorAttestation -NotePropertyValue ([pscustomobject]@{ legacyPortalDisabled=$LegacyPortalDisabled; attestedAt=[DateTimeOffset]::UtcNow.ToString('o'); apiVerified=$false }) -Force
    return [pscustomobject]@{ state=$MigrationState; comparison=@($comparison) }
}

function Invoke-AzdRiskCaLegacyRetire {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$MigrationState, [Parameter(Mandatory)][object]$RecommendedState, [Parameter(Mandatory)][string]$TenantId)
    if ($MigrationState.tenantId -ne $TenantId) { throw 'Migration state belongs to a different tenant.' }
    if ($RecommendedState.tenantId -ne $TenantId) { throw 'Recommended policy state belongs to a different tenant.' }
    if ($MigrationState.stage -ne 'cutoverComplete') { throw 'Legacy migration cutover is not complete.' }
    if (@($RecommendedState.policies.PSObject.Properties).Count -ne 9) { throw 'The managed recommendation state does not contain exactly nine policies.' }
    foreach ($property in @($RecommendedState.policies.PSObject.Properties)) {
        $actual=Invoke-AzdRiskCaGraphRequest GET "$script:GraphBase/identity/conditionalAccess/policies/$($property.Value.id)"
        if ($actual.state -ne 'enabled') { throw "Recommended policy '$($property.Name)' is not enabled. Legacy replicas remain enabled." }
    }
    foreach ($property in @($MigrationState.policies.PSObject.Properties)) {
        Invoke-AzdRiskCaGraphRequest PATCH "$script:GraphBase/identity/conditionalAccess/policies/$($property.Value.id)" @{ state='disabled' } | Out-Null
        $actual=Invoke-AzdRiskCaGraphRequest GET "$script:GraphBase/identity/conditionalAccess/policies/$($property.Value.id)"
        if ($actual.state -ne 'disabled') { throw "Legacy replica '$($property.Value.displayName)' was not disabled; retirement is incomplete." }
    }
    $MigrationState.stage='retired'; $MigrationState | Add-Member -NotePropertyName retiredAt -NotePropertyValue ([DateTimeOffset]::UtcNow.ToString('o')) -Force
    return $MigrationState
}

Export-ModuleMember -Function *
