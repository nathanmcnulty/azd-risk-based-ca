Set-StrictMode -Version Latest
$script:GraphBase = 'https://graph.microsoft.com/v1.0'
$script:GraphBetaBase = 'https://graph.microsoft.com/beta'
$script:TapStrengthName = 'Temporary Access Pass'
$script:TapCombinations = @('temporaryAccessPassMultiUse','temporaryAccessPassOneTime')
$script:RiskRemediationPolicyName = 'User-UserRisk-High-RiskRemediation'

function Get-AzdRiskCaProperty {
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Invoke-AzdRiskCaGraphRequest {
    [CmdletBinding()] param([Parameter(Mandatory)][ValidateSet('GET','POST','PATCH','DELETE')][string]$Method, [Parameter(Mandatory)][string]$Uri, [AllowNull()][object]$Body)
    $parameters = @{ Method=$Method; Uri=$Uri; OutputType='PSObject'; ErrorAction='Stop' }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) { $parameters.Body = ($Body | ConvertTo-Json -Depth 100 -Compress); $parameters.ContentType = 'application/json' }
    Invoke-MgGraphRequest @parameters
}

function Get-AzdRiskCaGraphCollection {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Uri)
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $response = Invoke-AzdRiskCaGraphRequest GET $next
        foreach ($item in @($response.value)) { $items.Add($item) }
        $next = [string](Get-AzdRiskCaProperty $response '@odata.nextLink')
    }
    return @($items)
}

function Test-AzdRiskCaPreviewPolicy {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Policy)
    if ($Policy -is [string]) { return $Policy -eq $script:RiskRemediationPolicyName }
    $name = Get-AzdRiskCaProperty $Policy 'displayName'
    $grants = Get-AzdRiskCaProperty $Policy 'grantControls'
    $controls = @(Get-AzdRiskCaProperty $grants 'builtInControls')
    return $name -eq $script:RiskRemediationPolicyName -or $controls -contains 'riskRemediation'
}

function Get-AzdRiskCaPolicyUri {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Policy, [AllowNull()][string]$Id)
    $base = if (Test-AzdRiskCaPreviewPolicy $Policy) { $script:GraphBetaBase } else { $script:GraphBase }
    $uri = "$base/identity/conditionalAccess/policies"
    if ($Id) { $uri += "/$Id" }
    return $uri
}

function ConvertTo-AzdRiskCaComparable {
    [CmdletBinding()] param([AllowNull()][object]$Value, [int]$Depth = 0)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [bool] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [System.Collections.IDictionary] -or ($Value.PSObject -and @($Value.PSObject.Properties).Count -gt 0 -and $Value -isnot [System.Collections.IEnumerable])) {
        $properties = if ($Value -is [System.Collections.IDictionary]) { @($Value.Keys | ForEach-Object { [pscustomobject]@{ Name=[string]$_; Value=$Value[$_] } }) } else { @($Value.PSObject.Properties) }
        $result = [ordered]@{}
        $metadataPattern = if ($Depth -eq 0) { '(@odata|^id$|^createdDateTime$|^modifiedDateTime$|^templateId$)' } else { '(@odata|^createdDateTime$|^modifiedDateTime$|^templateId$)' }
        foreach ($property in @($properties | Where-Object { $_.Name -notmatch $metadataPattern } | Sort-Object Name)) {
            if ($property.Name -eq 'guestOrExternalUserTypes' -and $property.Value -is [string]) {
                $result[$property.Name] = (@($property.Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object) -join ',')
            } else {
                $result[$property.Name] = ConvertTo-AzdRiskCaComparable $property.Value ($Depth + 1)
            }
        }
        return [pscustomobject]$result
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $converted = @($Value | ForEach-Object { ConvertTo-AzdRiskCaComparable $_ ($Depth + 1) })
        if (@($converted | Where-Object { $_ -isnot [string] }).Count -eq 0) { return @($converted | Sort-Object) }
        return $converted
    }
    return $Value
}

function Select-AzdRiskCaDesiredShape {
    param([AllowNull()][object]$Desired, [AllowNull()][object]$Actual)
    if ($null -eq $Desired) { return $null }
    if ($Desired -is [string] -or $Desired -is [bool] -or $Desired -is [ValueType]) { return $Actual }
    if ($Desired -is [System.Collections.IDictionary] -or ($Desired.PSObject -and @($Desired.PSObject.Properties).Count -gt 0 -and $Desired -isnot [System.Collections.IEnumerable])) {
        $properties = if ($Desired -is [System.Collections.IDictionary]) { @($Desired.Keys) } else { @($Desired.PSObject.Properties.Name) }
        $result = [ordered]@{}
        foreach ($name in @($properties | Sort-Object)) { $result[$name] = Select-AzdRiskCaDesiredShape (Get-AzdRiskCaProperty $Desired $name) (Get-AzdRiskCaProperty $Actual $name) }
        return [pscustomobject]$result
    }
    if ($Desired -is [System.Collections.IEnumerable]) {
        $values = @($Actual)
        if (@($Desired).Count -eq 0) { return @() }
        if (@($Desired | Where-Object { $_ -isnot [string] }).Count -eq 0) { return @($values | ForEach-Object { [string]$_ } | Sort-Object) }
        return @($values | ForEach-Object { ConvertTo-AzdRiskCaComparable $_ })
    }
    return $Actual
}

function Test-AzdRiskCaEquivalent {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Desired, [Parameter(Mandatory)][object]$Actual)
    $left = ConvertTo-AzdRiskCaComparable $Desired | ConvertTo-Json -Depth 100 -Compress
    $selected = Select-AzdRiskCaDesiredShape $Desired $Actual
    $right = ConvertTo-AzdRiskCaComparable $selected | ConvertTo-Json -Depth 100 -Compress
    return $left -ceq $right
}

function Get-AzdRiskCaTenantId {
    $context = Get-MgContext
    if (-not $context -or -not $context.TenantId) { throw 'No Microsoft Graph context is available.' }
    return [string]$context.TenantId
}

function Get-AzdRiskCaCurrentOperator {
    [CmdletBinding()] param()
    try { $user=Invoke-AzdRiskCaGraphRequest GET ($script:GraphBase + '/me?$select=id,displayName,userPrincipalName') }
    catch { throw "No emergency-access group is configured and the authenticated operator could not be resolved through Microsoft Graph /me. $($_.Exception.Message)" }
    if (-not $user.id) { throw 'No emergency-access group is configured and Microsoft Graph /me returned no user object ID.' }
    return [pscustomobject]@{ id=[string]$user.id; displayName=[string]$user.displayName; userPrincipalName=[string]$user.userPrincipalName }
}

function Get-AzdRiskCaBuiltInRoleTemplateIds {
    # Graph currently rejects a server-side isBuiltIn filter for this collection in some tenants.
    # Retrieve the selected fields and apply the built-in filter deterministically client-side.
    $uri = "$script:GraphBase/roleManagement/directory/roleDefinitions?`$select=id,templateId,displayName,isBuiltIn"
    $roles = @(Get-AzdRiskCaGraphCollection $uri | Where-Object { $_.isBuiltIn -eq $true -and $_.templateId })
    if ($roles.Count -eq 0) { throw 'Microsoft Graph returned no built-in directory role definitions.' }
    return @($roles | Sort-Object displayName | ForEach-Object { [pscustomobject]@{ id=[string]$_.templateId; displayName=[string]$_.displayName } })
}

function Get-AzdRiskCaValidatedGroups {
    [CmdletBinding()] param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Ids)
    $groups = [System.Collections.Generic.List[object]]::new()
    foreach ($id in @($Ids | Sort-Object -Unique)) {
        try { $group = Invoke-AzdRiskCaGraphRequest GET "$script:GraphBase/groups/${id}?`$select=id,displayName" } catch { throw "Group '$id' was not found in the connected tenant or cannot be read. $($_.Exception.Message)" }
        if ([string]$group.id -ne $id) { throw "Group validation returned an unexpected object for '$id'." }
        $groups.Add([pscustomobject]@{ id=[string]$group.id; displayName=[string]$group.displayName })
    }
    return @($groups)
}

function New-AzdRiskCaUsers {
    param([Parameter(Mandatory)][ValidateSet('admin','all','internal')][string]$Scope, [string[]]$RoleIds=@(), [string[]]$AdminGroups=@(), [string[]]$ExcludeGroups=@(), [string[]]$ExcludeUsers=@())
    $users = [ordered]@{ includeUsers=@(); excludeUsers=@($ExcludeUsers | Sort-Object -Unique); includeGroups=@(); excludeGroups=@($ExcludeGroups | Sort-Object -Unique); includeRoles=@(); excludeRoles=@() }
    if ($Scope -eq 'admin') { $users.includeRoles=@($RoleIds | Sort-Object -Unique); $users.includeGroups=@($AdminGroups | Sort-Object -Unique) } else { $users.includeUsers=@('All') }
    if ($Scope -eq 'internal') {
        $users.excludeGuestsOrExternalUsers = [ordered]@{ guestOrExternalUserTypes='b2bCollaborationGuest,b2bCollaborationMember,b2bDirectConnectUser,internalGuest,otherExternalUser,serviceProvider'; externalTenants=[ordered]@{ membershipKind='all' } }
    }
    return $users
}

function New-AzdRiskCaPolicyBody {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][ValidateSet('admin','all','internal')][string]$Scope,
        [ValidateSet('user','signIn')][string]$RiskType,
        [string[]]$RiskLevels,
        [Parameter(Mandatory)][ValidateSet('block','mfa','riskRemediation','strength')][string]$Control,
        [ValidateSet('applications','registerSecurityInfo','registerDevice')][string]$Target='applications',
        [Parameter(Mandatory)][string]$State,
        [string[]]$RoleIds=@(), [string[]]$AdminGroups=@(), [string[]]$ExcludeGroups=@(), [string[]]$ExcludeUsers=@(), [string]$AuthenticationStrengthId
    )
    $conditions = [ordered]@{ users=New-AzdRiskCaUsers $Scope $RoleIds $AdminGroups $ExcludeGroups $ExcludeUsers; clientAppTypes=@('all') }
    if ($RiskType -eq 'user') { $conditions.userRiskLevels=@($RiskLevels) } else { $conditions.signInRiskLevels=@($RiskLevels) }
    if ($Target -eq 'applications') { $conditions.applications=[ordered]@{ includeApplications=@('All'); excludeApplications=@(); includeUserActions=@() } }
    elseif ($Target -eq 'registerSecurityInfo') { $conditions.applications=[ordered]@{ includeApplications=@(); excludeApplications=@(); includeUserActions=@('urn:user:registersecurityinfo') } }
    else { $conditions.applications=[ordered]@{ includeApplications=@(); excludeApplications=@(); includeUserActions=@('urn:user:registerdevice') } }
    $grants = switch ($Control) {
        'block' { [ordered]@{ operator='OR'; builtInControls=@('block') } }
        'mfa' { [ordered]@{ operator='OR'; builtInControls=@('mfa') } }
        'riskRemediation' { [ordered]@{ operator='AND'; builtInControls=@('mfa','riskRemediation') } }
        'strength' { [ordered]@{ operator='OR'; builtInControls=@(); authenticationStrength=[ordered]@{ id=$AuthenticationStrengthId } } }
    }
    $body = [ordered]@{ displayName=$DisplayName; state=if($State -eq 'reportOnly'){'enabledForReportingButNotEnforced'}else{'enabled'}; conditions=$conditions; grantControls=$grants }
    if ($Target -eq 'applications') { $body.sessionControls=[ordered]@{ signInFrequency=[ordered]@{ value=$null; type=$null; isEnabled=$true; frequencyInterval='everyTime'; authenticationType='primaryAndSecondaryAuthentication' } } }
    return [pscustomobject]$body
}

function Get-AzdRiskCaPolicyBodies {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Configuration, [Parameter(Mandatory)][string[]]$RoleIds, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ExcludeGroups, [Parameter(Mandatory)][string]$AuthenticationStrengthId, [AllowEmptyCollection()][string[]]$ExcludeUsers=@())
    $adminGroups = if ($Configuration.AdminCoverageGroupId) { @($Configuration.AdminCoverageGroupId) } else { @() }
    $common = @{ State=$Configuration.PolicyState; RoleIds=$RoleIds; AdminGroups=$adminGroups; ExcludeGroups=$ExcludeGroups; ExcludeUsers=$ExcludeUsers }
    return @(
        New-AzdRiskCaPolicyBody @common -DisplayName 'Admin-SignInRisk-High-Block' -Scope admin -RiskType signIn -RiskLevels high -Control block
        New-AzdRiskCaPolicyBody @common -DisplayName 'Admin-SignInRisk-LowMedium-RequireMFA' -Scope admin -RiskType signIn -RiskLevels low,medium -Control mfa
        New-AzdRiskCaPolicyBody @common -DisplayName 'Admin-UserRisk-MediumHigh-Block' -Scope admin -RiskType user -RiskLevels medium,high -Control block
        New-AzdRiskCaPolicyBody @common -DisplayName 'User-SignInRisk-MediumHigh-RequireMFA' -Scope all -RiskType signIn -RiskLevels medium,high -Control mfa
        New-AzdRiskCaPolicyBody @common -DisplayName 'User-UserRisk-High-RiskRemediation' -Scope internal -RiskType user -RiskLevels high -Control riskRemediation
        New-AzdRiskCaPolicyBody @common -DisplayName 'User-UserRisk-Any-Block-SecurityInfoRegistration' -Scope all -RiskType user -RiskLevels low,medium,high -Control block -Target registerSecurityInfo
        New-AzdRiskCaPolicyBody @common -DisplayName 'User-SignInRisk-Any-Block-SecurityInfoRegistration' -Scope all -RiskType signIn -RiskLevels low,medium,high -Control block -Target registerSecurityInfo
        New-AzdRiskCaPolicyBody @common -DisplayName 'User-UserRisk-Any-RequireStrongAuth-DeviceRegistration' -Scope all -RiskType user -RiskLevels low,medium,high -Control strength -Target registerDevice -AuthenticationStrengthId $AuthenticationStrengthId
        New-AzdRiskCaPolicyBody @common -DisplayName 'User-SignInRisk-Any-RequireStrongAuth-DeviceRegistration' -Scope all -RiskType signIn -RiskLevels low,medium,high -Control strength -Target registerDevice -AuthenticationStrengthId $AuthenticationStrengthId
    )
}

function Resolve-AzdRiskCaAuthenticationStrength {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Configuration, [AllowNull()][object]$State)
    $strengths = @(Get-AzdRiskCaGraphCollection "$script:GraphBase/policies/authenticationStrengthPolicies")
    if (-not $Configuration.UseTapAuthenticationStrength) {
        $matches = @($strengths | Where-Object { $_.policyType -eq 'builtIn' -and (($_.id -eq '00000000-0000-0000-0000-000000000004') -or ($_.displayName -match 'Phishing-resistant')) })
        if ($matches.Count -ne 1) { throw 'The built-in phishing-resistant authentication strength could not be resolved unambiguously.' }
        return [pscustomobject]@{ id=[string]$matches[0].id; action='none'; created=$false; adopted=$false; existing=$matches[0]; body=$null }
    }
    $body = [ordered]@{ displayName=$script:TapStrengthName; description='Managed by azd-risk-based-ca. TAP one-time and multi-use only.'; requirementsSatisfied='mfa'; allowedCombinations=@($script:TapCombinations) }
    $adopted = $false
    $record = Get-AzdRiskCaProperty (Get-AzdRiskCaProperty $State 'authenticationStrength') 'id'
    $existing = if ($record) { @($strengths | Where-Object id -eq $record) | Select-Object -First 1 } else { $null }
    if (-not $existing) {
        $byName = @($strengths | Where-Object displayName -eq $script:TapStrengthName)
        if ($byName.Count -gt 1) { throw "Multiple authentication strengths are named '$script:TapStrengthName'." }
        if ($byName.Count -eq 1) {
            if (-not $Configuration.AdoptExisting) { throw "Authentication strength '$script:TapStrengthName' exists but is not owned by this environment. Set AZD_CA_ADOPT_EXISTING=true after review." }
            $existing=$byName[0]; $adopted=$true
        }
    }
    if (-not $existing) { return [pscustomobject]@{ id=$null; action='create'; created=$true; adopted=$false; existing=$null; body=[pscustomobject]$body } }
    if ($existing.policyType -eq 'builtIn') { throw "'$script:TapStrengthName' resolves to a built-in policy and cannot be adopted." }
    $equivalent = ((@($existing.allowedCombinations | Sort-Object) -join ',') -ceq (@($script:TapCombinations | Sort-Object) -join ',')) -and ([string]$existing.description -ceq [string]$body.description)
    return [pscustomobject]@{ id=[string]$existing.id; action=if($equivalent){'none'}else{'update'}; created=$false; adopted=[bool]$adopted; existing=$existing; body=[pscustomobject]$body }
}

function Resolve-AzdRiskCaPolicy {
    param([Parameter(Mandatory)][object]$Body, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Policies, [AllowNull()][object]$State, [bool]$AdoptExisting)
    $records = Get-AzdRiskCaProperty $State 'policies'
    $record = Get-AzdRiskCaProperty $records $Body.displayName
    $existing = if ($record) { @($Policies | Where-Object id -eq (Get-AzdRiskCaProperty $record 'id')) | Select-Object -First 1 } else { $null }
    $adopted = $false
    if (-not $existing) {
        $matches = @($Policies | Where-Object displayName -eq $Body.displayName)
        if ($matches.Count -gt 1) { throw "Multiple Conditional Access policies are named '$($Body.displayName)'." }
        if ($matches.Count -eq 1) {
            if (-not $AdoptExisting) { throw "Conditional Access policy '$($Body.displayName)' exists but is not owned by this environment. Set AZD_CA_ADOPT_EXISTING=true after review." }
            $existing=$matches[0]; $adopted=$true
        }
    }
    if (-not $existing) { return [pscustomobject]@{ displayName=$Body.displayName; id=$null; action='create'; body=$Body; existing=$null; adopted=$false } }
    return [pscustomobject]@{ displayName=$Body.displayName; id=[string]$existing.id; action=if(Test-AzdRiskCaEquivalent $Body $existing){'none'}else{'update'}; body=$Body; existing=$existing; adopted=$adopted }
}

function New-AzdRiskCaPlan {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Configuration, [AllowNull()][object]$State)
    $tenantId = Get-AzdRiskCaTenantId
    if ($State -and (Get-AzdRiskCaProperty $State 'tenantId') -ne $tenantId) { throw 'Saved state belongs to a different tenant.' }
    $warnings = [System.Collections.Generic.List[string]]::new()
    if (-not $Configuration.AdminCoverageGroupId) { $warnings.Add('No admin coverage group is configured. Role targeting does not include custom roles or administrative-unit-scoped assignments.') }
    $fallbackOperator=$null
    $excludeUsers=@()
    if (-not $Configuration.EmergencyAccessGroupId) {
        $fallbackOperator=Get-AzdRiskCaCurrentOperator
        $excludeUsers=@($fallbackOperator.id)
        $warnings.Add("No emergency-access group is configured. Authenticated operator '$($fallbackOperator.userPrincipalName)' ($($fallbackOperator.id)) is excluded from every policy as a single-user failsafe; configure a durable emergency-access group as soon as possible.")
    }
    $groupIds = @(@($Configuration.EmergencyAccessGroupId,$Configuration.AdminCoverageGroupId) + @($Configuration.AdditionalExcludeGroupIds) | Where-Object { $_ })
    $groups = @(Get-AzdRiskCaValidatedGroups $groupIds)
    $excludeGroups = @(@($Configuration.EmergencyAccessGroupId) + @($Configuration.AdditionalExcludeGroupIds) | Where-Object { $_ } | Sort-Object -Unique)
    $roles = @(Get-AzdRiskCaBuiltInRoleTemplateIds)
    $strength = Resolve-AzdRiskCaAuthenticationStrength $Configuration $State
    $strengthId = if ($strength.id) { $strength.id } else { '__CREATED_TAP_STRENGTH__' }
    $bodies = @(Get-AzdRiskCaPolicyBodies $Configuration @($roles.id) $excludeGroups $strengthId $excludeUsers)
    # The beta collection is required to discover policies containing preview-only controls,
    # which v1.0 omits and returns error 1037 when addressed directly.
    $existingPolicies = @(Get-AzdRiskCaGraphCollection "$script:GraphBetaBase/identity/conditionalAccess/policies")
    $policies = @($bodies | ForEach-Object { Resolve-AzdRiskCaPolicy $_ $existingPolicies $State $Configuration.AdoptExisting })
    $safeConfiguration = [pscustomobject]@{
        PolicyState=$Configuration.PolicyState
        EmergencyAccessGroupId=$Configuration.EmergencyAccessGroupId
        AdminCoverageGroupId=$Configuration.AdminCoverageGroupId
        AdditionalExcludeGroupIds=@($Configuration.AdditionalExcludeGroupIds)
        UseTapAuthenticationStrength=$Configuration.UseTapAuthenticationStrength
        AdoptExisting=$Configuration.AdoptExisting
        GraphAuthenticationMethod=$Configuration.GraphAuthenticationMethod
        NotificationMode=$Configuration.NotificationMode
        AdminTeamsDeliveryMode=$Configuration.AdminTeamsDeliveryMode
        HasAdminTeamsTarget=(-not [string]::IsNullOrWhiteSpace($Configuration.AdminTeamsTeamId) -and -not [string]::IsNullOrWhiteSpace($Configuration.AdminTeamsChannelId))
        HasAdminTeamsWorkflowUrl=(-not [string]::IsNullOrWhiteSpace($Configuration.AdminTeamsWorkflowUrl))
        HasUserTeamsWorkflowUrl=(-not [string]::IsNullOrWhiteSpace($Configuration.UserTeamsWorkflowUrl))
        LogAnalyticsWorkspaceResourceId=$Configuration.LogAnalyticsWorkspaceResourceId
        LogAnalyticsWorkspaceLocation=$Configuration.LogAnalyticsWorkspaceLocation
    }
    return [pscustomobject]@{ schemaVersion='1.0'; generatedAt=[DateTimeOffset]::UtcNow.ToString('o'); tenantId=$tenantId; policyState=$Configuration.PolicyState; configuration=$safeConfiguration; warnings=@($warnings); validatedGroups=$groups; emergencyFallbackUser=$fallbackOperator; builtInRoles=$roles; authenticationStrength=$strength; policies=$policies }
}

function Invoke-AzdRiskCaApply {
    [CmdletBinding(SupportsShouldProcess)] param([Parameter(Mandatory)][object]$Plan, [AllowNull()][object]$ExistingState, [scriptblock]$Checkpoint)
    $state = [ordered]@{ schemaVersion='1.0'; tenantId=$Plan.tenantId; updatedAt=[DateTimeOffset]::UtcNow.ToString('o'); authenticationStrength=$null; policies=[ordered]@{} }
    $rollbackActions = [System.Collections.Generic.List[object]]::new()
    $priorStrength=Get-AzdRiskCaProperty $ExistingState 'authenticationStrength'
    if($priorStrength){$state.authenticationStrength=$priorStrength}
    $priorPolicies=Get-AzdRiskCaProperty $ExistingState 'policies'
    if($priorPolicies){foreach($property in @($priorPolicies.PSObject.Properties)){$state.policies[$property.Name]=$property.Value}}
    try {
        $strength = $Plan.authenticationStrength
        $strengthId = $strength.id
        if ($strength.action -eq 'create' -and $PSCmdlet.ShouldProcess($strength.body.displayName,'create authentication strength')) {
            $created = Invoke-AzdRiskCaGraphRequest POST "$script:GraphBase/policies/authenticationStrengthPolicies" $strength.body; $strengthId=[string]$created.id
            $rollbackActions.Add([pscustomobject]@{ kind='deleteStrength'; id=$strengthId; name=$strength.body.displayName })
        } elseif ($strength.action -eq 'update' -and $PSCmdlet.ShouldProcess($strength.body.displayName,'update authentication strength')) {
            $rollbackActions.Add([pscustomobject]@{ kind='restoreStrength'; id=$strengthId; name=$strength.body.displayName; previous=$strength.existing })
            Invoke-AzdRiskCaGraphRequest PATCH "$script:GraphBase/policies/authenticationStrengthPolicies/$strengthId" @{ displayName=$strength.body.displayName; description=$strength.body.description } | Out-Null
            Invoke-AzdRiskCaGraphRequest POST "$script:GraphBase/policies/authenticationStrengthPolicies/$strengthId/updateAllowedCombinations" @{ allowedCombinations=@($strength.body.allowedCombinations) } | Out-Null
        }
        if ($Plan.configuration.UseTapAuthenticationStrength) {
            $existingStrengthRecord=Get-AzdRiskCaProperty $ExistingState 'authenticationStrength'
            if ($existingStrengthRecord -and $existingStrengthRecord.id -eq $strengthId) {
                $state.authenticationStrength=[ordered]@{ id=$strengthId; created=[bool]$existingStrengthRecord.created; adopted=[bool]$existingStrengthRecord.adopted; previous=$existingStrengthRecord.previous }
            } else {
                $previousStrength = if ($strength.adopted) { Select-AzdRiskCaDesiredShape $strength.body $strength.existing } else { $null }
                $state.authenticationStrength=[ordered]@{ id=$strengthId; created=($strength.action -eq 'create'); adopted=[bool]$strength.adopted; previous=$previousStrength }
            }
        }
        if($Checkpoint){& $Checkpoint ([pscustomobject]$state)}
        foreach ($policy in @($Plan.policies)) {
            $body = $policy.body | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
            $bodyStrength=Get-AzdRiskCaProperty $body.grantControls 'authenticationStrength'
            if ($bodyStrength -and $bodyStrength.id -eq '__CREATED_TAP_STRENGTH__') { $bodyStrength.id=$strengthId }
            $policyId=$policy.id
            $policyUri=Get-AzdRiskCaPolicyUri $body $policyId
            if ($policy.action -eq 'create' -and $PSCmdlet.ShouldProcess($policy.displayName,'create Conditional Access policy')) {
                $created=Invoke-AzdRiskCaGraphRequest POST (Get-AzdRiskCaPolicyUri $body $null) $body; $policyId=[string]$created.id
                $rollbackActions.Add([pscustomobject]@{ kind='deletePolicy'; id=$policyId; name=$policy.displayName; body=$body })
            } elseif ($policy.action -eq 'update' -and $PSCmdlet.ShouldProcess($policy.displayName,'update Conditional Access policy')) {
                $rollbackActions.Add([pscustomobject]@{ kind='restorePolicy'; id=$policyId; name=$policy.displayName; previous=(ConvertTo-AzdRiskCaComparable $policy.existing) })
                Invoke-AzdRiskCaGraphRequest PATCH $policyUri $body | Out-Null
            }
            if (-not $policyId) { throw "Graph did not return an object ID for '$($policy.displayName)'." }
            $existingPoliciesState=Get-AzdRiskCaProperty $ExistingState 'policies'
            $existingRecord=Get-AzdRiskCaProperty $existingPoliciesState $policy.displayName
            if ($existingRecord -and $existingRecord.id -eq $policyId) {
                $state.policies[$policy.displayName]=[ordered]@{ id=$policyId; created=[bool]$existingRecord.created; adopted=[bool]$existingRecord.adopted; previous=$existingRecord.previous }
            } else {
                $previous = if ($policy.adopted) { ConvertTo-AzdRiskCaComparable $policy.existing } else { $null }
                $state.policies[$policy.displayName]=[ordered]@{ id=$policyId; created=($policy.action -eq 'create'); adopted=[bool]$policy.adopted; previous=$previous }
            }
            if($Checkpoint){& $Checkpoint ([pscustomobject]$state)}
        }
    } catch {
        $applyError=$_
        $rollbackErrors=[System.Collections.Generic.List[string]]::new()
        $actions=@($rollbackActions)
        [array]::Reverse($actions)
        foreach($action in $actions){
            try {
                switch($action.kind){
                    'deletePolicy' { Invoke-AzdRiskCaGraphRequest DELETE (Get-AzdRiskCaPolicyUri $action.body $action.id) | Out-Null }
                    'restorePolicy' { Invoke-AzdRiskCaGraphRequest PATCH (Get-AzdRiskCaPolicyUri $action.previous $action.id) $action.previous | Out-Null }
                    'deleteStrength' { Invoke-AzdRiskCaGraphRequest DELETE "$script:GraphBase/policies/authenticationStrengthPolicies/$($action.id)" | Out-Null }
                    'restoreStrength' {
                        Invoke-AzdRiskCaGraphRequest PATCH "$script:GraphBase/policies/authenticationStrengthPolicies/$($action.id)" @{ displayName=$action.previous.displayName; description=$action.previous.description } | Out-Null
                        Invoke-AzdRiskCaGraphRequest POST "$script:GraphBase/policies/authenticationStrengthPolicies/$($action.id)/updateAllowedCombinations" @{ allowedCombinations=@($action.previous.allowedCombinations) } | Out-Null
                    }
                }
            } catch { $rollbackErrors.Add("$($action.kind) '$($action.name)': $($_.Exception.Message)") }
        }
        if($rollbackErrors.Count -gt 0){
            $rollbackException=[System.InvalidOperationException]::new("Conditional Access apply failed: $($applyError.Exception.Message). Automatic rollback was incomplete: $($rollbackErrors -join '; ')",$applyError.Exception)
            $rollbackException.Data['AzdRiskCaRollbackIncomplete']=$true
            throw $rollbackException
        }
        throw $applyError
    }
    return [pscustomobject]$state
}

function Test-AzdRiskCaAppliedState {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Plan, [Parameter(Mandatory)][object]$State)
    $failures=[System.Collections.Generic.List[string]]::new()
    $pending=@($Plan.policies)
    $lastFailure=@{}
    for ($attempt=1; $attempt -le 6 -and $pending.Count -gt 0; $attempt++) {
        $retry=[System.Collections.Generic.List[object]]::new()
        foreach ($policy in $pending) {
            $record=Get-AzdRiskCaProperty $State.policies $policy.displayName
            try {
                $actual=Invoke-AzdRiskCaGraphRequest GET (Get-AzdRiskCaPolicyUri $policy.body ([string]$record.id))
                $desired=$policy.body | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
                $desiredStrength=Get-AzdRiskCaProperty $desired.grantControls 'authenticationStrength'
                if ($desiredStrength -and $desiredStrength.id -eq '__CREATED_TAP_STRENGTH__') { $desiredStrength.id=$State.authenticationStrength.id }
                if (Test-AzdRiskCaEquivalent $desired $actual) { $lastFailure.Remove($policy.displayName); continue }
                $lastFailure[$policy.displayName]="$($policy.displayName): desired and actual differ"
            } catch {
                $lastFailure[$policy.displayName]="$($policy.displayName): could not re-read"
            }
            $retry.Add($policy)
        }
        $pending=@($retry)
        if ($pending.Count -gt 0 -and $attempt -lt 6) { Start-Sleep -Seconds ($attempt * 2) }
    }
    foreach ($policy in $pending) { $failures.Add([string]$lastFailure[$policy.displayName]) }
    return [pscustomobject]@{ valid=($failures.Count -eq 0); failures=@($failures) }
}

function Remove-AzdRiskCaManagedObjects {
    [CmdletBinding(SupportsShouldProcess)] param([Parameter(Mandatory)][object]$State)
    foreach ($recordProperty in @($State.policies.PSObject.Properties)) {
        $record=$recordProperty.Value
        $policyUri=Get-AzdRiskCaPolicyUri ([string]$recordProperty.Name) ([string]$record.id)
        if ($record.created -and $PSCmdlet.ShouldProcess($recordProperty.Name,'delete solution-created Conditional Access policy')) { Invoke-AzdRiskCaGraphRequest DELETE $policyUri | Out-Null }
        elseif ($record.adopted -and $record.previous -and $PSCmdlet.ShouldProcess($recordProperty.Name,'restore adopted Conditional Access policy')) { Invoke-AzdRiskCaGraphRequest PATCH $policyUri $record.previous | Out-Null }
    }
    $policyFailures=@()
    for($attempt=1;$attempt -le 10;$attempt++){
        $policies=@(Get-AzdRiskCaGraphCollection "$script:GraphBetaBase/identity/conditionalAccess/policies")
        $policyFailures=@()
        foreach($recordProperty in @($State.policies.PSObject.Properties)){
            $record=$recordProperty.Value
            $actual=@($policies | Where-Object id -eq $record.id) | Select-Object -First 1
            if($record.created -and $actual){$policyFailures += "$($recordProperty.Name): created policy still exists"}
            elseif($record.adopted -and $record.previous -and (-not $actual -or -not (Test-AzdRiskCaEquivalent $record.previous $actual))){$policyFailures += "$($recordProperty.Name): adopted policy is not restored"}
        }
        if($policyFailures.Count -eq 0){break}
        if($attempt -lt 10){Start-Sleep -Seconds 2}
    }
    if($policyFailures.Count){throw "Conditional Access cleanup did not converge: $($policyFailures -join '; '). Ownership state was preserved."}
    if ($State.authenticationStrength -and $State.authenticationStrength.created) {
        $policies=@(Get-AzdRiskCaGraphCollection "$script:GraphBetaBase/identity/conditionalAccess/policies")
        $references=@($policies | Where-Object { $grant=Get-AzdRiskCaProperty $_ 'grantControls'; $reference=Get-AzdRiskCaProperty $grant 'authenticationStrength'; $reference -and $reference.id -eq $State.authenticationStrength.id })
        if ($references.Count) { throw "TAP authentication strength is still referenced by $($references.Count) Conditional Access policy/policies; cleanup stopped." }
        if ($PSCmdlet.ShouldProcess($State.authenticationStrength.id,'delete solution-created TAP authentication strength')) { Invoke-AzdRiskCaGraphRequest DELETE "$script:GraphBase/policies/authenticationStrengthPolicies/$($State.authenticationStrength.id)" | Out-Null }
    } elseif ($State.authenticationStrength -and $State.authenticationStrength.adopted -and $State.authenticationStrength.previous -and $PSCmdlet.ShouldProcess($State.authenticationStrength.id,'restore adopted TAP authentication strength')) {
        $prior=$State.authenticationStrength.previous
        Invoke-AzdRiskCaGraphRequest PATCH "$script:GraphBase/policies/authenticationStrengthPolicies/$($State.authenticationStrength.id)" @{ displayName=$prior.displayName; description=$prior.description } | Out-Null
        Invoke-AzdRiskCaGraphRequest POST "$script:GraphBase/policies/authenticationStrengthPolicies/$($State.authenticationStrength.id)/updateAllowedCombinations" @{ allowedCombinations=@($prior.allowedCombinations) } | Out-Null
    }
    if($State.authenticationStrength){
        $strengthFailures=@()
        for($attempt=1;$attempt -le 10;$attempt++){
            $strengths=@(Get-AzdRiskCaGraphCollection "$script:GraphBase/policies/authenticationStrengthPolicies")
            $actual=@($strengths | Where-Object id -eq $State.authenticationStrength.id) | Select-Object -First 1
            $strengthFailures=@()
            if($State.authenticationStrength.created -and $actual){$strengthFailures += 'solution-created TAP authentication strength still exists'}
            elseif($State.authenticationStrength.adopted -and $State.authenticationStrength.previous){
                $prior=$State.authenticationStrength.previous
                $same=($actual -and [string]$actual.displayName -ceq [string]$prior.displayName -and [string]$actual.description -ceq [string]$prior.description -and (@($actual.allowedCombinations | Sort-Object) -join ',') -ceq (@($prior.allowedCombinations | Sort-Object) -join ','))
                if(-not $same){$strengthFailures += 'adopted TAP authentication strength is not restored'}
            }
            if($strengthFailures.Count -eq 0){break}
            if($attempt -lt 10){Start-Sleep -Seconds 2}
        }
        if($strengthFailures.Count){throw "Authentication-strength cleanup did not converge: $($strengthFailures -join '; '). Ownership state was preserved."}
    }
}

Export-ModuleMember -Function *
