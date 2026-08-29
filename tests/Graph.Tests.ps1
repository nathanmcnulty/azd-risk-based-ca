BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../scripts/AzdRiskCa.Graph.psm1') -Force
    $script:emergency='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
    $script:coverage='cccccccc-cccc-cccc-cccc-cccccccccccc'
    $script:role='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:strength='00000000-0000-0000-0000-000000000004'
    $script:config=[pscustomobject]@{PolicyState='reportOnly';AdminCoverageGroupId=$script:coverage}
    $script:bodies=@(Get-AzdRiskCaPolicyBodies $script:config @($script:role) @($script:emergency) $script:strength)
}

Describe 'Applied-state validation consistency' {
    BeforeEach {
        $body=[pscustomobject]@{
            displayName='Retry policy'
            state='enabledForReportingButNotEnforced'
            conditions=[pscustomobject]@{}
            grantControls=[pscustomobject]@{}
        }
        $script:validationPlan=[pscustomobject]@{policies=@([pscustomobject]@{displayName=$body.displayName;body=$body})}
        $script:validationState=[pscustomobject]@{policies=[pscustomobject]@{'Retry policy'=[pscustomobject]@{id='retry-id'}};authenticationStrength=$null}
        Mock Start-Sleep -ModuleName AzdRiskCa.Graph {}
    }

    It 'retries transient policy read failures and then validates the policy' {
        $script:readAttempts=0
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph {
            $script:readAttempts++
            if($script:readAttempts -lt 3){throw 'not replicated'}
            [pscustomobject]@{displayName='Retry policy';state='enabledForReportingButNotEnforced';conditions=[pscustomobject]@{};grantControls=[pscustomobject]@{}}
        }
        $result=Test-AzdRiskCaAppliedState $script:validationPlan $script:validationState
        $result.valid | Should -BeTrue
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph -Times 3
        Assert-MockCalled Start-Sleep -ModuleName AzdRiskCa.Graph -Times 2
    }

    It 'fails after bounded retries when a policy never becomes readable' {
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph { throw 'still unavailable' }
        $result=Test-AzdRiskCaAppliedState $script:validationPlan $script:validationState
        $result.valid | Should -BeFalse
        $result.failures | Should -Contain 'Retry policy: could not re-read'
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph -Times 6
        Assert-MockCalled Start-Sleep -ModuleName AzdRiskCa.Graph -Times 5
    }
}
Describe 'Canonical recommended policy payloads' {
    It 'builds exactly the nine approved names' { @($script:bodies).Count | Should -Be 9; @($script:bodies.displayName) | Should -Be @('Admin-SignInRisk-High-Block','Admin-SignInRisk-LowMedium-RequireMFA','Admin-UserRisk-MediumHigh-Block','User-SignInRisk-MediumHigh-RequireMFA','User-UserRisk-High-RiskRemediation','User-UserRisk-Any-Block-SecurityInfoRegistration','User-SignInRisk-Any-Block-SecurityInfoRegistration','User-UserRisk-Any-RequireStrongAuth-DeviceRegistration','User-SignInRisk-Any-RequireStrongAuth-DeviceRegistration') }
    It 'defaults every policy to Graph report-only state' { @($script:bodies | Where-Object state -ne 'enabledForReportingButNotEnforced').Count | Should -Be 0 }
    It 'maps explicit enabled mode to Graph enabled state' { $enabled=[pscustomobject]@{PolicyState='enabled';AdminCoverageGroupId=''}; $values=Get-AzdRiskCaPolicyBodies $enabled @($script:role) @($script:emergency) $script:strength; @($values | Where-Object state -ne 'enabled').Count | Should -Be 0 }
    It 'keeps user and sign-in risk conditions separate' { foreach($body in $script:bodies){ $names=@($body.conditions.Keys); (($names -contains 'userRiskLevels') -xor ($names -contains 'signInRiskLevels')) | Should -BeTrue } }
    It 'adds every-time sign-in frequency to baseline policies only' { @($script:bodies | Where-Object sessionControls).Count | Should -Be 5; foreach($body in @($script:bodies | Select-Object -First 5)){ $body.sessionControls.signInFrequency.frequencyInterval | Should -Be 'everyTime' }; foreach($body in @($script:bodies | Select-Object -Skip 5)){ $body.PSObject.Properties.Name | Should -Not -Contain 'sessionControls' } }
    It 'targets all dynamically supplied roles and the admin coverage group' { foreach($body in @($script:bodies | Where-Object displayName -like 'Admin-*')){ $body.conditions.users.includeRoles | Should -Contain $script:role; $body.conditions.users.includeGroups | Should -Contain $script:coverage } }
    It 'excludes emergency access from every policy' { foreach($body in $script:bodies){ $body.conditions.users.excludeGroups | Should -Contain $script:emergency } }
    It 'excludes the authenticated operator from every policy when used as the failsafe' { $operator='dddddddd-dddd-dddd-dddd-dddddddddddd'; $values=Get-AzdRiskCaPolicyBodies $script:config @($script:role) @() $script:strength @($operator); foreach($body in $values){ $body.conditions.users.excludeUsers | Should -Contain $operator } }
    It 'excludes every supported guest and external-user type from high-user-risk remediation' { $policy=$script:bodies | Where-Object displayName -eq 'User-UserRisk-High-RiskRemediation'; $policy.conditions.users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes | Should -Be 'b2bCollaborationGuest,b2bCollaborationMember,b2bDirectConnectUser,internalGuest,otherExternalUser,serviceProvider'; $policy.conditions.users.excludeGuestsOrExternalUsers.externalTenants.membershipKind | Should -Be 'all' }
    It 'uses the intentional mfa and riskRemediation AND grant' { $policy=$script:bodies | Where-Object displayName -eq 'User-UserRisk-High-RiskRemediation'; $policy.grantControls.operator | Should -Be 'AND'; $policy.grantControls.builtInControls | Should -Be @('mfa','riskRemediation') }
    It 'blocks security-information registration' { foreach($policy in @($script:bodies | Where-Object displayName -like '*SecurityInfoRegistration')){ $policy.conditions.applications.includeUserActions | Should -Be @('urn:user:registersecurityinfo'); $policy.grantControls.builtInControls | Should -Be @('block') } }
    It 'never blocks device registration and uses the selected strength' { foreach($policy in @($script:bodies | Where-Object displayName -like '*DeviceRegistration')){ $policy.conditions.applications.includeUserActions | Should -Be @('urn:user:registerdevice'); $policy.grantControls.builtInControls | Should -Not -Contain 'block'; $policy.grantControls.authenticationStrength.id | Should -Be $script:strength } }
    It 'normalizes response metadata when comparing' { $actual=$script:bodies[0] | ConvertTo-Json -Depth 50 | ConvertFrom-Json -Depth 50; $actual | Add-Member id 'policy-id'; $actual | Add-Member '@odata.context' 'tenant-specific'; Test-AzdRiskCaEquivalent $script:bodies[0] $actual | Should -BeTrue }
    It 'treats guest and external-user type ordering as semantic set ordering' { $policy=$script:bodies | Where-Object displayName -eq 'User-UserRisk-High-RiskRemediation'; $actual=$policy | ConvertTo-Json -Depth 50 | ConvertFrom-Json -Depth 50; $actual.conditions.users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes='internalGuest,b2bCollaborationGuest,b2bCollaborationMember,b2bDirectConnectUser,otherExternalUser,serviceProvider'; Test-AzdRiskCaEquivalent $policy $actual | Should -BeTrue }
    It 'detects drift in a nested authentication-strength ID' { $policy=$script:bodies | Where-Object displayName -like '*DeviceRegistration' | Select-Object -First 1; $actual=$policy | ConvertTo-Json -Depth 50 | ConvertFrom-Json -Depth 50; $actual.grantControls.authenticationStrength.id='ffffffff-ffff-ffff-ffff-ffffffffffff'; Test-AzdRiskCaEquivalent $policy $actual | Should -BeFalse }
}

Describe 'Built-in directory role discovery' {
    It 'filters built-in roles client-side without an unsupported Graph filter' {
        Mock Get-AzdRiskCaGraphCollection -ModuleName AzdRiskCa.Graph {
            @(
                [pscustomobject]@{id='role-definition';templateId='built-in-template';displayName='Built in';isBuiltIn=$true}
                [pscustomobject]@{id='custom-role';templateId='custom-template';displayName='Custom';isBuiltIn=$false}
            )
        }
        $roles=@(Get-AzdRiskCaBuiltInRoleTemplateIds)
        $roles.Count | Should -Be 1
        $roles[0].id | Should -Be 'built-in-template'
        Assert-MockCalled Get-AzdRiskCaGraphCollection -ModuleName AzdRiskCa.Graph -Times 1 -ParameterFilter { $Uri -like '*/roleDefinitions?*' -and $Uri -notmatch '\$filter' }
    }
}

Describe 'Tenant-local group validation' {
    It 'uses an unambiguous group ID boundary before the query string' {
        $groupId='55555555-5555-5555-5555-555555555555'
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph { [pscustomobject]@{id=$groupId;displayName='Emergency access'} }
        $groups=@(Get-AzdRiskCaValidatedGroups @($groupId))
        $groups.Count | Should -Be 1
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph -Times 1 -ParameterFilter { $Uri -eq "https://graph.microsoft.com/v1.0/groups/${groupId}?`$select=id,displayName" }
    }
}

Describe 'Emergency-access operator fallback' {
    It 'resolves only the authenticated operator through Microsoft Graph me' {
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph {
            [pscustomobject]@{id='operator-id';displayName='Operator';userPrincipalName='operator@example.test'}
        }
        $operator=Get-AzdRiskCaCurrentOperator
        $operator.id | Should -Be 'operator-id'
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph -Times 1 -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq 'https://graph.microsoft.com/v1.0/me?$select=id,displayName,userPrincipalName'
        }
    }

    It 'fails closed when the authenticated operator cannot be resolved' {
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph { throw 'lookup failed' }
        { Get-AzdRiskCaCurrentOperator } | Should -Throw '*No emergency-access group*operator could not be resolved*'
    }
}

Describe 'Conditional Access API version routing' {
    It 'uses beta only for the preview risk-remediation policy' {
        $remediation=$script:bodies | Where-Object displayName -eq 'User-UserRisk-High-RiskRemediation'
        Get-AzdRiskCaPolicyUri $remediation 'policy-id' | Should -Be 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies/policy-id'
        Get-AzdRiskCaPolicyUri $script:bodies[0] 'policy-id' | Should -Be 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/policy-id'
    }
}

Describe 'Ownership and adoption' {
    It 'rejects an unowned matching name' { $existing=[pscustomobject]@{id='one';displayName=$script:bodies[0].displayName}; { Resolve-AzdRiskCaPolicy $script:bodies[0] @($existing) $null $false } | Should -Throw '*not owned*' }
    It 'adopts only when explicitly requested and saves update action' { $existing=[pscustomobject]@{id='one';displayName=$script:bodies[0].displayName;state='disabled';conditions=@{};grantControls=@{}}; $result=Resolve-AzdRiskCaPolicy $script:bodies[0] @($existing) $null $true; $result.adopted | Should -BeTrue; $result.action | Should -Be 'update' }
    It 'uses a recorded object ID instead of name ownership' { $existing=$script:bodies[0] | ConvertTo-Json -Depth 50 | ConvertFrom-Json -Depth 50; $existing | Add-Member id 'recorded-id'; $state=[pscustomobject]@{policies=[pscustomobject]@{$($script:bodies[0].displayName)=[pscustomobject]@{id='recorded-id'}}}; (Resolve-AzdRiskCaPolicy $script:bodies[0] @($existing) $state $false).action | Should -Be 'none' }
}

Describe 'TAP authentication strength lifecycle' {
    BeforeEach { Mock Get-AzdRiskCaGraphCollection -ModuleName AzdRiskCa.Graph { @() } }
    It 'plans a TAP-only strength with both combinations' { $c=[pscustomobject]@{UseTapAuthenticationStrength=$true;AdoptExisting=$false}; $r=Resolve-AzdRiskCaAuthenticationStrength $c $null; $r.action | Should -Be 'create'; $r.body.allowedCombinations | Should -Be @('temporaryAccessPassMultiUse','temporaryAccessPassOneTime') }
    It 'refuses a same-name custom strength without adoption' { Mock Get-AzdRiskCaGraphCollection -ModuleName AzdRiskCa.Graph { @([pscustomobject]@{id='tap';displayName='Temporary Access Pass';policyType='custom';allowedCombinations=@('temporaryAccessPassOneTime')}) }; $c=[pscustomobject]@{UseTapAuthenticationStrength=$true;AdoptExisting=$false}; { Resolve-AzdRiskCaAuthenticationStrength $c $null } | Should -Throw '*ADOPT_EXISTING*' }
    It 'resolves the built-in phishing-resistant strength by stable ID' { Mock Get-AzdRiskCaGraphCollection -ModuleName AzdRiskCa.Graph { @([pscustomobject]@{id='00000000-0000-0000-0000-000000000004';displayName='Phishing-resistant MFA';policyType='builtIn'}) }; $c=[pscustomobject]@{UseTapAuthenticationStrength=$false;AdoptExisting=$false}; (Resolve-AzdRiskCaAuthenticationStrength $c $null).id | Should -Be '00000000-0000-0000-0000-000000000004' }
    It 'uses the supported action endpoint when changing TAP combinations' {
        $body=[pscustomobject]@{displayName='Temporary Access Pass';description='Managed';requirementsSatisfied='mfa';allowedCombinations=@('temporaryAccessPassOneTime','temporaryAccessPassMultiUse')}
        $plan=[pscustomobject]@{tenantId='tenant';configuration=[pscustomobject]@{UseTapAuthenticationStrength=$true};authenticationStrength=[pscustomobject]@{id='tap-id';action='update';body=$body;adopted=$true;existing=[pscustomobject]@{description='old';allowedCombinations=@('temporaryAccessPassOneTime')}};policies=@()}
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph {}
        Invoke-AzdRiskCaApply $plan $null -Confirm:$false | Out-Null
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph -Times 1 -ParameterFilter {$Method -eq 'POST' -and $Uri -like '*/updateAllowedCombinations' -and $Body.allowedCombinations.Count -eq 2}
    }
}

Describe 'Cleanup guard' {
    It 'refuses to delete a TAP strength while any policy references it' {
        $state=[pscustomobject]@{policies=[pscustomobject]@{};authenticationStrength=[pscustomobject]@{id='tap-id';created=$true;adopted=$false}}
        Mock Get-AzdRiskCaGraphCollection -ModuleName AzdRiskCa.Graph { @([pscustomobject]@{grantControls=[pscustomobject]@{authenticationStrength=[pscustomobject]@{id='tap-id'}}}) }
        { Remove-AzdRiskCaManagedObjects $state -Confirm:$false } | Should -Throw '*still referenced*'
    }
    It 'restores the recorded canonical body for an adopted policy' {
        $previous=[pscustomobject]@{displayName='Adopted';state='disabled';conditions=[pscustomobject]@{users=[pscustomobject]@{includeUsers=@('All')}};grantControls=[pscustomobject]@{operator='OR';builtInControls=@('mfa')}}
        $state=[pscustomobject]@{policies=[pscustomobject]@{Adopted=[pscustomobject]@{id='policy-id';created=$false;adopted=$true;previous=$previous}};authenticationStrength=$null}
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph {}
        Mock Get-AzdRiskCaGraphCollection -ModuleName AzdRiskCa.Graph { @([pscustomobject]@{id='policy-id';displayName='Adopted';state='disabled';conditions=[pscustomobject]@{users=[pscustomobject]@{includeUsers=@('All')}};grantControls=[pscustomobject]@{operator='OR';builtInControls=@('mfa')}}) }
        Remove-AzdRiskCaManagedObjects $state -Confirm:$false
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph -Times 1 -ParameterFilter {$Method -eq 'PATCH' -and $Uri -like '*/policy-id' -and $Body.state -eq 'disabled'}
    }
    It 'preserves a nested authentication-strength ID in adopted rollback state' {
        $policy=$script:bodies | Where-Object displayName -like '*DeviceRegistration' | Select-Object -First 1
        $existing=$policy | ConvertTo-Json -Depth 50 | ConvertFrom-Json -Depth 50
        $existing | Add-Member id 'policy-id'
        $plan=[pscustomobject]@{tenantId='tenant';configuration=[pscustomobject]@{UseTapAuthenticationStrength=$false};authenticationStrength=[pscustomobject]@{id=$script:strength;action='none'};policies=@([pscustomobject]@{displayName=$policy.displayName;id='policy-id';action='update';body=$policy;existing=$existing;adopted=$true})}
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph {}
        $state=Invoke-AzdRiskCaApply $plan $null -Confirm:$false
        $state.policies[$policy.displayName].previous.grantControls.authenticationStrength.id | Should -Be $script:strength
    }
    It 'deletes an unreferenced solution-created TAP strength' {
        $state=[pscustomobject]@{policies=[pscustomobject]@{};authenticationStrength=[pscustomobject]@{id='tap-id';created=$true;adopted=$false}}
        Mock Get-AzdRiskCaGraphCollection -ModuleName AzdRiskCa.Graph { @() }
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph {}
        Remove-AzdRiskCaManagedObjects $state -Confirm:$false
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph -Times 1 -ParameterFilter {$Method -eq 'DELETE' -and $Uri -like '*/tap-id'}
    }
}

Describe 'Fail-closed application' {
    It 'stops on riskRemediation rejection without a fallback write' {
        $policy=$script:bodies | Where-Object displayName -eq 'User-UserRisk-High-RiskRemediation'
        $plan=[pscustomobject]@{tenantId='tenant';configuration=[pscustomobject]@{UseTapAuthenticationStrength=$false};authenticationStrength=[pscustomobject]@{id=$script:strength;action='none'};policies=@([pscustomobject]@{displayName=$policy.displayName;id=$null;action='create';body=$policy;adopted=$false})}
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph { throw 'Graph rejected riskRemediation payload' }
        { Invoke-AzdRiskCaApply $plan $null -Confirm:$false } | Should -Throw '*Graph rejected*'
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph -Times 1 -ParameterFilter { $Uri -like 'https://graph.microsoft.com/beta/*' }
    }
    It 'preserves created ownership across an idempotent repeat run' {
        $policy=$script:bodies[0]
        $plan=[pscustomobject]@{tenantId='tenant';configuration=[pscustomobject]@{UseTapAuthenticationStrength=$false};authenticationStrength=[pscustomobject]@{id=$script:strength;action='none'};policies=@([pscustomobject]@{displayName=$policy.displayName;id='policy-id';action='none';body=$policy;adopted=$false})}
        $existing=[pscustomobject]@{policies=[pscustomobject]@{$($policy.displayName)=[pscustomobject]@{id='policy-id';created=$true;adopted=$false;previous=$null}}}
        $next=Invoke-AzdRiskCaApply $plan $existing -Confirm:$false
        $next.policies[$policy.displayName].created | Should -BeTrue
    }
    It 'restores earlier policy updates when a later update fails' {
        $first=$script:bodies[0] | ConvertTo-Json -Depth 50 | ConvertFrom-Json -Depth 50
        $second=$script:bodies[1] | ConvertTo-Json -Depth 50 | ConvertFrom-Json -Depth 50
        $first.state='enabled'; $second.state='enabled'
        $firstExisting=$first | ConvertTo-Json -Depth 50 | ConvertFrom-Json -Depth 50
        $secondExisting=$second | ConvertTo-Json -Depth 50 | ConvertFrom-Json -Depth 50
        $firstExisting.state='enabledForReportingButNotEnforced'; $secondExisting.state='enabledForReportingButNotEnforced'
        $firstExisting | Add-Member id 'first-id'; $secondExisting | Add-Member id 'second-id'
        $plan=[pscustomobject]@{
            tenantId='tenant'
            configuration=[pscustomobject]@{UseTapAuthenticationStrength=$false}
            authenticationStrength=[pscustomobject]@{id=$script:strength;action='none'}
            policies=@(
                [pscustomobject]@{displayName=$first.displayName;id='first-id';action='update';body=$first;existing=$firstExisting;adopted=$false},
                [pscustomobject]@{displayName=$second.displayName;id='second-id';action='update';body=$second;existing=$secondExisting;adopted=$false}
            )
        }
        $script:calls=[System.Collections.Generic.List[string]]::new()
        $script:enabledWrites=0
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph {
            if($Method -eq 'PATCH'){
                $script:calls.Add("$Uri|$($Body.state)")
                if($Body.state -eq 'enabled'){
                    $script:enabledWrites++
                    if($script:enabledWrites -eq 2){ throw 'simulated token failure' }
                }
            }
        }
        { Invoke-AzdRiskCaApply $plan $null -Confirm:$false } | Should -Throw '*simulated token failure*'
        @($script:calls)[-2] | Should -BeLike '*second-id|enabledForReportingButNotEnforced'
        @($script:calls)[-1] | Should -BeLike '*first-id|enabledForReportingButNotEnforced'
    }
    It 'marks an incomplete automatic rollback so checkpoint state is retained' {
        $policy=$script:bodies[0] | ConvertTo-Json -Depth 50 | ConvertFrom-Json -Depth 50
        $policy.state='enabled'
        $existing=$policy | ConvertTo-Json -Depth 50 | ConvertFrom-Json -Depth 50
        $existing.state='enabledForReportingButNotEnforced'
        $existing | Add-Member id 'policy-id'
        $plan=[pscustomobject]@{tenantId='tenant';configuration=[pscustomobject]@{UseTapAuthenticationStrength=$false};authenticationStrength=[pscustomobject]@{id=$script:strength;action='none'};policies=@([pscustomobject]@{displayName=$policy.displayName;id='policy-id';action='update';body=$policy;existing=$existing;adopted=$false})}
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Graph { throw 'simulated persistent token failure' }
        $caught=$null
        try { Invoke-AzdRiskCaApply $plan $null -Confirm:$false | Out-Null } catch { $caught=$_ }
        $caught.Exception.Message | Should -BeLike '*Automatic rollback was incomplete*'
        $caught.Exception.Data['AzdRiskCaRollbackIncomplete'] | Should -BeTrue
    }
}

Describe 'Plan report redaction' {
    It 'does not serialize Teams callback bearer secrets' {
        Mock Get-AzdRiskCaTenantId -ModuleName AzdRiskCa.Graph { 'tenant' }
        Mock Get-AzdRiskCaValidatedGroups -ModuleName AzdRiskCa.Graph { @() }
        Mock Get-AzdRiskCaBuiltInRoleTemplateIds -ModuleName AzdRiskCa.Graph { @([pscustomobject]@{id=$script:role;displayName='Role'}) }
        Mock Get-AzdRiskCaCurrentOperator -ModuleName AzdRiskCa.Graph { [pscustomobject]@{id='operator-id';displayName='Operator';userPrincipalName='operator@example.test'} }
        Mock Resolve-AzdRiskCaAuthenticationStrength -ModuleName AzdRiskCa.Graph { [pscustomobject]@{id=$script:strength;action='none';created=$false;adopted=$false;existing=$null;body=$null} }
        Mock Get-AzdRiskCaGraphCollection -ModuleName AzdRiskCa.Graph { @() }
        $configuration=[pscustomobject]@{PolicyState='reportOnly';EmergencyAccessGroupId='';AdminCoverageGroupId='';AdditionalExcludeGroupIds=@();UseTapAuthenticationStrength=$false;AdoptExisting=$false;GraphAuthenticationMethod='browser';NotificationMode='graph';AdminTeamsDeliveryMode='workflowWebhook';AdminTeamsWorkflowUrl='https://secret.example/admin';UserTeamsWorkflowUrl='https://secret.example/user';AdminTeamsTeamId='';AdminTeamsChannelId='';LogAnalyticsWorkspaceResourceId='';LogAnalyticsWorkspaceLocation=''}
        $json=New-AzdRiskCaPlan $configuration $null | ConvertTo-Json -Depth 100
        $json | Should -Not -Match 'secret\.example'
        $json | Should -Match 'HasAdminTeamsWorkflowUrl'
    }
}
