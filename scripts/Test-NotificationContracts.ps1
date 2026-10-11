#Requires -Version 7.6
[CmdletBinding()]
param(
    [System.Collections.IDictionary] $Definition = (
        Get-Content (Join-Path $PSScriptRoot '../infra/modules/logic-app-definition.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 100
    )
)

# Validate the existing Storage managed-identity contract without executing a workflow.
# Accept a definition argument so negative fixtures exercise this same repository gate.
function Test-StorageAudience {
    param([object] $Node, [string] $Path)
    $count = 0
    if ($Node -is [System.Collections.IDictionary]) {
        if ($Node.Contains('authentication')) {
            $authentication = $Node['authentication']
            if ($authentication -is [System.Collections.IDictionary] -and
                $authentication['type'] -eq 'ManagedServiceIdentity') {
                if ($authentication['audience'] -cne 'https://storage.azure.com/') {
                    throw "Storage managed-identity audience is missing or invalid at $Path."
                }
                $count++
            }
        }
        foreach ($key in $Node.Keys) { $count += Test-StorageAudience $Node[$key] "$Path.$key" }
    }
    elseif ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
        $index = 0
        foreach ($child in $Node) { $count += Test-StorageAudience $child "$Path[$index]"; $index++ }
    }
    return $count
}

if ((Test-StorageAudience $Definition 'definition') -lt 1) {
    throw 'Workflow definition has no Storage managed-identity audience to validate.'
}
