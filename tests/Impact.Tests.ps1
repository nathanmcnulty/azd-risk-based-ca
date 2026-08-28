BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../scripts/AzdRiskCa.Graph.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../scripts/AzdRiskCa.Impact.psm1') -Force
    $script:start=[DateTimeOffset]'2026-07-29T00:00:00Z'
    $script:end=[DateTimeOffset]'2026-08-28T00:00:00Z'
    $script:metricIds=@('signInHigh','signInLowMedium','signInMediumHigh','riskyUserHighCurrent','riskyUserMediumHighCurrent')
}

Describe 'Microsoft Graph aggregate risk batch' {
    It 'builds five filtered count requests in one batch' {
        $batch=New-AzdRiskCaImpactBatchRequest $script:start $script:end
        @($batch.body.requests).Count | Should -Be 5
        @($batch.body.requests.id) | Should -Be $script:metricIds
        foreach($request in $batch.body.requests){
            $request.method | Should -Be 'GET'
            $request.headers.ConsistencyLevel | Should -Be 'eventual'
            $request.url | Should -Match '/\$count\?\$filter='
        }
        $signInUrls=@($batch.body.requests | Where-Object id -like 'signIn*' | ForEach-Object { [uri]::UnescapeDataString($_.url) })
        foreach($url in $signInUrls){
            $url | Should -Match '^/auditLogs/signIns/\$count\?\$filter='
            $url | Should -Match 'createdDateTime ge 2026-07-29T00:00:00Z'
            $url | Should -Match 'createdDateTime lt 2026-08-28T00:00:00Z'
            $url | Should -Match ([regex]::Escape("signInEventTypes/any(t: t eq 'interactiveUser')"))
            $url | Should -Match ([regex]::Escape("signInEventTypes/any(t: t eq 'nonInteractiveUser')"))
        }
        $riskyUserUrls=@($batch.body.requests | Where-Object id -like 'riskyUser*' | ForEach-Object { [uri]::UnescapeDataString($_.url) })
        foreach($url in $riskyUserUrls){
            $url | Should -Match '^/identityProtection/riskyUsers/\$count\?\$filter='
            $url | Should -Match "riskState eq 'atRisk' or riskState eq 'confirmedCompromised'"
            $url | Should -Match 'isDeleted eq false'
        }
    }

    It 'returns event and current-user counts without enumerating identities' {
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Impact {
            [pscustomobject]@{responses=@(
                [pscustomobject]@{id='signInHigh';status=200;body='2'},
                [pscustomobject]@{id='signInLowMedium';status=200;body='7'},
                [pscustomobject]@{id='signInMediumHigh';status=200;body='5'},
                [pscustomobject]@{id='riskyUserHighCurrent';status=200;body='3'},
                [pscustomobject]@{id='riskyUserMediumHighCurrent';status=200;body='11'}
            )}
        }
        $result=Get-AzdRiskCaHistoricalImpact ([pscustomobject]@{tenantId='tenant'}) -AsOf $script:end
        $result.schemaVersion | Should -Be '2.0'
        $result.period.days | Should -Be 30
        $result.estimate.summary | Should -Match '2 high-risk, 7 low/medium-risk, and 5 medium/high-risk user sign-in events'
        $result.estimate.summary | Should -Match '3 high-risk and 11 medium/high-risk users'
        $result.dataQuality.availableMeasurements | Should -Be 5
        $result.dataQuality.unavailableMeasurements | Should -Be 0
        ($result.estimate.measurements | Where-Object id -eq 'signInMediumHigh').count | Should -Be 5
        ($result.policies | Where-Object name -eq 'User-SignInRisk-MediumHigh-RequireMFA').unit | Should -Be 'signInEvents'
        ($result.policies | Where-Object name -eq 'User-UserRisk-High-RiskRemediation').unit | Should -Be 'users'
        @($result.policies | Where-Object targetingApplied).Count | Should -Be 0
        $result.investigate.riskyUsers | Should -Be 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/IdentityProtectionMenuBlade/~/RiskyUsers'
        $result.investigate.riskySignIns | Should -Be 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/IdentityProtectionMenuBlade/~/RiskySignIns'
        Assert-MockCalled Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Impact -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'https://graph.microsoft.com/beta/$batch' -and @($Body.requests).Count -eq 5
        }
    }

    It 'marks a failed count unavailable instead of substituting zero' {
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Impact {
            [pscustomobject]@{responses=@(
                [pscustomobject]@{id='signInHigh';status=400;body=[pscustomobject]@{error='unsupported'}},
                [pscustomobject]@{id='signInLowMedium';status=200;body='0'},
                [pscustomobject]@{id='signInMediumHigh';status=200;body='0'},
                [pscustomobject]@{id='riskyUserHighCurrent';status=200;body='0'},
                [pscustomobject]@{id='riskyUserMediumHighCurrent';status=200;body='0'}
            )}
        }
        $result=Get-AzdRiskCaHistoricalImpact ([pscustomobject]@{tenantId='tenant'}) -AsOf $script:end
        $failed=$result.estimate.measurements | Where-Object id -eq 'signInHigh'
        $failed.available | Should -BeFalse
        $failed.count | Should -BeNullOrEmpty
        $failed.status | Should -Be 'http400'
        $result.estimate.summary | Should -Match 'unavailable high-risk, 0 low/medium-risk'
        $result.dataQuality.unavailableMeasurements | Should -Be 1
    }

    It 'returns links and unavailable metrics when the outer batch request fails' {
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Impact { throw 'batch unavailable' }
        $result=Get-AzdRiskCaHistoricalImpact ([pscustomobject]@{tenantId='tenant'}) -AsOf $script:end
        $result.dataQuality.batchStatus | Should -Be 'failed'
        $result.dataQuality.availableMeasurements | Should -Be 0
        $result.dataQuality.unavailableMeasurements | Should -Be 5
        @($result.estimate.measurements | Where-Object { $null -ne $_.count }).Count | Should -Be 0
        $result.investigate.riskyUsers | Should -Match 'IdentityProtectionMenuBlade/~/RiskyUsers$'
    }

    It 'marks the four registration policies unevaluable' {
        Mock Invoke-AzdRiskCaGraphRequest -ModuleName AzdRiskCa.Impact { throw 'batch unavailable' }
        $result=Get-AzdRiskCaHistoricalImpact ([pscustomobject]@{tenantId='tenant'}) -AsOf $script:end
        $unevaluated=@($result.policies | Where-Object evaluable -eq $false)
        $unevaluated.Count | Should -Be 4
        foreach($policy in $unevaluated){
            $policy.count | Should -BeNullOrEmpty
            $policy.note | Should -Match 'registration'
        }
    }
}
