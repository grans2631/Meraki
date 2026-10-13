# Lab-only verification harness. No writes without -Apply + ShouldProcess approval.
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$LabOrganizationId,
    [switch]$Apply
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MerakiToolkit/MerakiToolkit.psd1') -Force -ErrorAction Stop
$m=Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if ([string]$m.organizationId -ne $LabOrganizationId) {throw 'Manifest org ID does not match explicit -LabOrganizationId.'}
if ($m.network.existingNetworkId) {throw 'Lab test must CREATE a new network; existingNetworkId is prohibited.'}
if (-not ([string]$m.network.name).StartsWith('ToolkitLAB-',[StringComparison]::Ordinal)) {
    throw 'Lab network name must start with ToolkitLAB-.'
}
if ('MerakiToolkit-LAB' -notin @($m.network.tags)) {throw 'MerakiToolkit-LAB tag is required.'}
if (@($m.devices | Where-Object { $null -ne $_ }).Count -gt 0) {throw 'Lab gate prohibits assigning real device serials.'}
if ($m.claimToInventory -eq $true -or $m.mx -or $m.ms -or $m.mr) {
    throw 'Lab gate is network-only; claims and MX/MS/MR device settings are prohibited.'
}
$plan=Get-MerakiDeploymentPlan -ManifestPath $ManifestPath
$plan | Format-List
$preview=Invoke-MerakiDeployment -ManifestPath $ManifestPath -WhatIf
if ($Apply) {
    if (-not (Get-MerakiConnection).Connected) { Connect-Meraki | Out-Null }
    $target="$LabOrganizationId / $($m.network.name)"
    if ($PSCmdlet.ShouldProcess($target,'CREATE exactly one tagged lab network')) {
        $result=Invoke-MerakiDeployment -ManifestPath $ManifestPath -Confirm:$false
        $network=Get-MerakiNetwork -NetworkId $result.NetworkId
        if ([string]$network.organizationId -ne $LabOrganizationId -or
            [string]$network.name -ne [string]$m.network.name -or
            'MerakiToolkit-LAB' -notin @($network.tags)) {
            throw "Lab network was created but post-create verification failed. Check network ID $($result.NetworkId) in Dashboard."
        }
        [pscustomobject]@{
            outcome='LabNetworkVerified'
            labOrganizationId=$LabOrganizationId
            networkId=$result.NetworkId
            networkName=$network.name
            tags=@($network.tags)
            verifiedAtUtc=[datetime]::UtcNow.ToString('o')
        }
    }
}
