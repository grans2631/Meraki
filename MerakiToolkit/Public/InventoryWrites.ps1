<#
.SYNOPSIS
Claim device serials into organization inventory.
.EXAMPLE
Add-MerakiOrganizationInventory -OrganizationId 'ORG_ID' -Serials @('QXXX-XXXX-XXXX') -WhatIf
#>
function Add-MerakiOrganizationInventory {
    <#
    .SYNOPSIS
    Claim unassigned Meraki device serials into an organization inventory.
    .DESCRIPTION
    Uses licensing-scoped API permissions. Cisco limits claim requests, and claiming may
    affect licensing. This does NOT assign devices to a Dashboard network.
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$OrganizationId,
        [Parameter(Mandatory)][string[]]$Serials
    )
    $unique = @($Serials | Select-Object -Unique)
    if (-not $unique.Count) { throw 'At least one serial is required.' }
    if ($PSCmdlet.ShouldProcess($OrganizationId,("Claim {0} device(s) to organization inventory" -f $unique.Count))) {
        Invoke-MerakiApi -Method POST -Path "/organizations/$OrganizationId/inventory/claim" -Body @{serials=$unique}
    }
}
