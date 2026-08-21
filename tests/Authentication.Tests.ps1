BeforeAll { Import-Module (Join-Path $PSScriptRoot '../scripts/AzdRiskCa.Authentication.psm1') -Force }
Describe 'Least-privilege delegated scopes' {
    It 'uses the five base permissions including operator fallback resolution' { (Get-AzdRiskCaGraphPermissionScope none) | Should -Be @('Group.Read.All','Policy.Read.All','Policy.ReadWrite.ConditionalAccess','RoleManagement.Read.Directory','User.Read') }
    It 'requests app assignment permissions only for Graph polling' { Get-AzdRiskCaGraphPermissionScope graph | Should -Contain 'AppRoleAssignment.ReadWrite.All'; Get-AzdRiskCaGraphPermissionScope none | Should -Not -Contain 'AppRoleAssignment.ReadWrite.All'; Get-AzdRiskCaGraphPermissionScope logAnalytics | Should -Not -Contain 'Application.Read.All' }
}

Describe 'Standard cached Graph authentication' {
    It 'always hydrates the current process with ordinary Connect-MgGraph' {
        $scopes=Get-AzdRiskCaGraphPermissionScope none
        Mock Connect-MgGraph -ModuleName AzdRiskCa.Authentication {}
        Mock Invoke-MgGraphRequest -ModuleName AzdRiskCa.Authentication {}
        Mock Get-MgContext -ModuleName AzdRiskCa.Authentication {
            [pscustomobject]@{TenantId='11111111-1111-1111-1111-111111111111';Scopes=$scopes}
        }
        $configuration=[pscustomobject]@{NotificationMode='none'}
        Connect-AzdRiskCaGraph ([guid]'11111111-1111-1111-1111-111111111111') $configuration | Out-Null
        Assert-MockCalled Connect-MgGraph -ModuleName AzdRiskCa.Authentication -Times 1 -ParameterFilter {
            $TenantId -eq '11111111-1111-1111-1111-111111111111' -and
            $ContextScope -eq 'CurrentUser' -and
            $null -eq $UseDeviceAuthentication
        }
        Assert-MockCalled Invoke-MgGraphRequest -ModuleName AzdRiskCa.Authentication -Times 1 -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq 'https://graph.microsoft.com/v1.0/me?$select=id'
        }
    }
    It 'fails clearly when standard WAM authentication cannot initialize in the host' {
        $scopes=Get-AzdRiskCaGraphPermissionScope none
        Mock Connect-MgGraph -ModuleName AzdRiskCa.Authentication {}
        Mock Get-MgContext -ModuleName AzdRiskCa.Authentication {
            [pscustomobject]@{TenantId='11111111-1111-1111-1111-111111111111';Scopes=$scopes}
        }
        Mock Invoke-MgGraphRequest -ModuleName AzdRiskCa.Authentication { throw 'InteractiveBrowserCredential authentication failed: A window handle must be configured.' }
        $configuration=[pscustomobject]@{NotificationMode='none'}
        { Connect-AzdRiskCaGraph ([guid]'11111111-1111-1111-1111-111111111111') $configuration } | Should -Throw '*interactive terminal*Device-code authentication is not supported*'
    }
}
