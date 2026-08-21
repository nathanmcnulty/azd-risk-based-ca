BeforeAll { Import-Module (Join-Path $PSScriptRoot '../scripts/AzdRiskCa.Graph.psm1') -Force; Import-Module (Join-Path $PSScriptRoot '../scripts/AzdRiskCa.Legacy.psm1') -Force }
Describe 'Legacy migration lifecycle' {
    BeforeEach {
        $script:capture=[pscustomobject]@{enabled=$true;policy=[pscustomobject]@{conditions=[pscustomobject]@{users=[pscustomobject]@{includeUsers=@('All');excludeGroups=@()};userRiskLevels=@('high');signInRiskLevels=@('medium');clientAppTypes=@('all');applications=[pscustomobject]@{includeApplications=@('All')}};grantControls=[pscustomobject]@{operator='OR';builtInControls=@('mfa')}}}
    }
    It 'adds mandatory emergency exclusion and separates risk kinds' { $body=New-AzdRiskCaLegacyBody userRisk $script:capture 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'; $body.conditions.users.excludeGroups | Should -Contain 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'; $body.conditions.PSObject.Properties.Name | Should -Not -Contain 'signInRiskLevels'; $body.state | Should -Be 'enabledForReportingButNotEnforced' }
    It 'produces stable comparison hashes across property order' { $a=[ordered]@{b=2;a=1}; $b=[ordered]@{a=1;b=2}; Get-AzdRiskCaLegacyHash $a | Should -Be (Get-AzdRiskCaLegacyHash $b) }
    It 'produces a field-level safety difference for the emergency exclusion' { $before=[pscustomobject]@{conditions=[pscustomobject]@{users=[pscustomobject]@{excludeGroups=@()}}}; $after=[pscustomobject]@{conditions=[pscustomobject]@{users=[pscustomobject]@{excludeGroups=@('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')}}}; $difference=Compare-AzdRiskCaLegacyFields $before $after | Where-Object field -eq 'conditions.users.excludeGroups'; $difference.matches | Should -BeFalse }
    It 'stops cutover on replica drift before any PATCH' {
        $desired=New-AzdRiskCaLegacyBody userRisk $script:capture 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'; $state=[pscustomobject]@{tenantId='tenant';policies=[pscustomobject]@{userRisk=[pscustomobject]@{id='id';displayName=$desired.displayName;desired=$desired;comparisonHash=Get-AzdRiskCaLegacyHash $desired}}}
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Legacy { [pscustomobject]@{displayName=$desired.displayName;state='disabled';conditions=$desired.conditions;grantControls=$desired.grantControls} }
        { Invoke-AzdRiskCaLegacyCutover $state tenant $false } | Should -Throw '*drifted*'
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Legacy -ParameterFilter {$Method -eq 'PATCH'} -Times 0
    }
    It 'refuses retirement before a complete cutover' { $migration=[pscustomobject]@{tenantId='tenant';stage='cutoverIncomplete'}; { Invoke-AzdRiskCaLegacyRetire $migration ([pscustomobject]@{tenantId='tenant'}) tenant } | Should -Throw '*not complete*' }
    It 'rejects migration state from another tenant before reading policies' {
        $migration=[pscustomobject]@{tenantId='other';stage='cutoverComplete';policies=[pscustomobject]@{}}
        $recommended=[pscustomobject]@{tenantId='tenant';policies=[pscustomobject]@{}}
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Legacy {}
        { Invoke-AzdRiskCaLegacyRetire $migration $recommended tenant } | Should -Throw '*Migration state belongs to a different tenant*'
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Legacy -Times 0
    }
    It 'rejects recommended state from another tenant before reading policies' {
        $migration=[pscustomobject]@{tenantId='tenant';stage='cutoverComplete';policies=[pscustomobject]@{}}
        $recommended=[pscustomobject]@{tenantId='other';policies=[pscustomobject]@{}}
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Legacy {}
        { Invoke-AzdRiskCaLegacyRetire $migration $recommended tenant } | Should -Throw '*Recommended policy state belongs to a different tenant*'
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Legacy -Times 0
    }
    It 'verifies a legacy replica is disabled before recording retirement' {
        $recommendedPolicies=[ordered]@{}
        1..9 | ForEach-Object { $recommendedPolicies["Recommended $_"]=[pscustomobject]@{id="recommended-$_"} }
        $recommended=[pscustomobject]@{tenantId='tenant';policies=[pscustomobject]$recommendedPolicies}
        $migration=[pscustomobject]@{tenantId='tenant';stage='cutoverComplete';policies=[pscustomobject]@{userRisk=[pscustomobject]@{id='legacy-id';displayName='LEGACY MIGRATED - User risk'}}}
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Legacy {
            if($Uri -like '*/legacy-id' -and $Method -eq 'GET'){return [pscustomobject]@{state='disabled'}}
            if($Method -eq 'GET'){return [pscustomobject]@{state='enabled'}}
        }
        $result=Invoke-AzdRiskCaLegacyRetire $migration $recommended tenant
        $result.stage | Should -Be 'retired'
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Legacy -Times 1 -ParameterFilter {$Method -eq 'PATCH' -and $Uri -like '*/legacy-id' -and $Body.state -eq 'disabled'}
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Legacy -Times 1 -ParameterFilter {$Method -eq 'GET' -and $Uri -like '*/legacy-id'}
    }
    It 'enables replicas before recording incomplete portal attestation' {
        $desired=New-AzdRiskCaLegacyBody userRisk $script:capture 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
        $state=[pscustomobject]@{tenantId='tenant';stage='staged';policies=[pscustomobject]@{userRisk=[pscustomobject]@{id='id';displayName=$desired.displayName;desired=$desired;legacyCapture=$script:capture.policy;comparisonHash=Get-AzdRiskCaLegacyHash $desired}}}
        $script:sequence=[Collections.Generic.List[string]]::new(); $script:getCount=0
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Legacy {
            $script:sequence.Add($Method)
            if($Method -eq 'GET'){$script:getCount+=1; $actual=$desired|ConvertTo-Json -Depth 50|ConvertFrom-Json -Depth 50; if($script:getCount -gt 1){$actual.state='enabled'}; return $actual}
        }
        $result=Invoke-AzdRiskCaLegacyCutover $state tenant $false
        $result.state.stage | Should -Be 'cutoverIncomplete'
        $script:sequence | Should -Be @('GET','PATCH','GET')
    }
}
