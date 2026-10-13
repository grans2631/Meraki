# All configuration writes use PowerShell ShouldProcess. Pass -WhatIf to preview.
<#
.SYNOPSIS
Create a new Dashboard network with selected product families.
.EXAMPLE
New-MerakiNetwork -OrganizationId 'ORG_ID' -Name 'Lab' -ProductTypes appliance,switch -WhatIf
#>
function New-MerakiNetwork {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$OrganizationId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('appliance','switch','wireless','camera','cellularGateway','sensor')][string[]]$ProductTypes,
        [string]$TimeZone = 'America/New_York',
        [string[]]$Tags,
        [string]$CopyFromNetworkId
    )
    $body = @{name=$Name;productTypes=@($ProductTypes | Select-Object -Unique);timeZone=$TimeZone}
    if ($Tags) { $body.tags=$Tags }
    if ($CopyFromNetworkId) { $body.copyFromNetworkId=$CopyFromNetworkId }
    if ($PSCmdlet.ShouldProcess("$OrganizationId/$Name",'Create network')) {
        Invoke-MerakiApi -Method POST -Path "/organizations/$OrganizationId/networks" -Body $body
    }
}
function Add-MerakiNetworkDevice {
    <#
    .SYNOPSIS
    Assign claimed device serials to a selected network.
    .DESCRIPTION
    Serial numbers must be claimed into organization inventory before assigning to a network.
    .EXAMPLE
    Add-MerakiNetworkDevice -NetworkId 'N_123' -Serials @('QXXX-XXXX-XXXX') -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$NetworkId,[Parameter(Mandatory)][string[]]$Serials)
    $unique = @($Serials | Select-Object -Unique)
    if (-not $unique.Count) { throw 'Specify at least one serial.' }
    if ($PSCmdlet.ShouldProcess($NetworkId,("Assign {0} serial(s) to network" -f $unique.Count))) {
        Invoke-MerakiApi -Method POST -Path "/networks/$NetworkId/devices/claim" -Body @{serials=$unique}
    }
}
<#
.SYNOPSIS
Update name, tags or other supported device metadata.
.EXAMPLE
Set-MerakiDevice -Serial 'QXXX-XXXX-XXXX' -Settings @{name='Lab-AP01'} -WhatIf
#>
function Set-MerakiDevice {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][hashtable]$Settings
    )
    Assert-MerakiSettings $Settings
    $allowed = @('name','address','notes','tags','lat','lng','moveMapMarker')
    foreach ($key in $Settings.Keys) {
        if ($key -notin $allowed) { throw "Unsupported device metadata property: $key" }
    }
    if ($PSCmdlet.ShouldProcess($Serial,'Update device metadata')) {
        Invoke-MerakiApi -Method PUT -Path "/devices/$Serial" -Body $Settings
    }
}
<#
.SYNOPSIS
Update a switch port; review VLAN and PoE impact.
.EXAMPLE
Set-MerakiSwitchPort -Serial 'QXXX-XXXX-XXXX' -PortId '1' -Settings @{name='AP'} -WhatIf
#>
function Set-MerakiSwitchPort {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][string]$PortId,
        [Parameter(Mandatory)][hashtable]$Settings
    )
    Assert-MerakiSettings $Settings
    if ($PSCmdlet.ShouldProcess("$Serial port $PortId",'Update switch port settings')) {
        Invoke-MerakiApi -Method PUT -Path "/devices/$Serial/switch/ports/$PortId" -Body $Settings
    }
}
<#
.SYNOPSIS
Update SSID settings in a network.
.EXAMPLE
Set-MerakiWirelessSsid -NetworkId 'N_123' -Number 0 -Settings @{enabled=$false} -WhatIf
#>
function Set-MerakiWirelessSsid {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$NetworkId,
        [Parameter(Mandatory)][ValidateRange(0,14)][int]$Number,
        [Parameter(Mandatory)][hashtable]$Settings
    )
    Assert-MerakiSettings $Settings
    if ($PSCmdlet.ShouldProcess("$NetworkId SSID $Number",'Update wireless SSID')) {
        Invoke-MerakiApi -Method PUT -Path "/networks/$NetworkId/wireless/ssids/$Number" -Body $Settings
    }
}
<#
.SYNOPSIS
Create an MX VLAN when VLAN mode is already enabled.
.EXAMPLE
New-MerakiApplianceVlan -NetworkId 'N_123' -Settings @{id='10';name='Lab';subnet='192.0.2.0/24';applianceIp='192.0.2.1'} -WhatIf
#>
function New-MerakiApplianceVlan {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$NetworkId,[Parameter(Mandatory)][hashtable]$Settings)
    foreach ($key in @('id','name','subnet','applianceIp')) {
        if (-not $Settings.ContainsKey($key)) { throw "VLAN settings require '$key'." }
    }
    if ($PSCmdlet.ShouldProcess("$NetworkId VLAN $($Settings.id)",'Create appliance VLAN')) {
        Invoke-MerakiApi -Method POST -Path "/networks/$NetworkId/appliance/vlans" -Body $Settings
    }
}
<#
.SYNOPSIS
Update the properties of an existing MX VLAN.
.EXAMPLE
Set-MerakiApplianceVlan -NetworkId 'N_123' -VlanId '10' -Settings @{name='Lab'} -WhatIf
#>
function Set-MerakiApplianceVlan {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$NetworkId,
        [Parameter(Mandatory)][string]$VlanId,
        [Parameter(Mandatory)][hashtable]$Settings
    )
    Assert-MerakiSettings $Settings
    if ($PSCmdlet.ShouldProcess("$NetworkId VLAN $VlanId",'Update appliance VLAN')) {
        Invoke-MerakiApi -Method PUT -Path "/networks/$NetworkId/appliance/vlans/$VlanId" -Body $Settings
    }
}
function Set-MerakiFirewallRules {
    <#
    .SYNOPSIS
    Replace the ENTIRE MX L3 ruleset; never use a partial list.
    .DESCRIPTION
    CAUTION: replaces the COMPLETE MX L3 firewall rule set, not a single entry.
    Back up current rules and review your plan before applying.
    .EXAMPLE
    Set-MerakiFirewallRules -NetworkId 'N_123' -Rules @(@{comment='Allow DNS';policy='allow';protocol='udp';srcCidr='any';destCidr='any';destPort='53'}) -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$NetworkId,[Parameter(Mandatory)][object[]]$Rules)
    if ($Rules.Count -eq 0) { throw 'Refusing empty firewall rule replacement.' }
    if ($PSCmdlet.ShouldProcess($NetworkId,'REPLACE ALL MX L3 firewall rules')) {
        Invoke-MerakiApi -Method PUT -Path "/networks/$NetworkId/appliance/firewall/l3FirewallRules" -Body @{rules=$Rules}
    }
}
<#
.SYNOPSIS
Replace MX site-to-site VPN settings; potentially disruptive.
.EXAMPLE
Set-MerakiVpnConfiguration -NetworkId 'N_123' -Settings @{mode='none'} -WhatIf
#>
function Set-MerakiVpnConfiguration {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$NetworkId,[Parameter(Mandatory)][hashtable]$Settings)
    Assert-MerakiSettings $Settings
    if ($PSCmdlet.ShouldProcess($NetworkId,'Replace site-to-site VPN settings')) {
        Invoke-MerakiApi -Method PUT -Path "/networks/$NetworkId/appliance/vpn/siteToSiteVpn" -Body $Settings
    }
}
<#
.SYNOPSIS
Reboot a Meraki device; disrupts network service.
.EXAMPLE
Restart-MerakiDevice -Serial 'QXXX-XXXX-XXXX' -WhatIf
#>
function Restart-MerakiDevice {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$Serial)
    if ($PSCmdlet.ShouldProcess($Serial,'REBOOT DEVICE (service interruption)')) {
        Invoke-MerakiApi -Method POST -Path "/devices/$Serial/reboot"
    }
}
function Set-MerakiFirmwareUpgrade {
    <#
    .SYNOPSIS
    Schedule a network product-family firmware upgrade by version ID.
    .DESCRIPTION
    Schedule an explicit firmware version ID and ISO 8601 UTC time.
    The API may refuse upgrades on unsupported networks or versions.
    .EXAMPLE
    Set-MerakiFirmwareUpgrade -NetworkId 'N_123' -ProductType switch -VersionId 'VERSION_ID' -TimeUtc '2026-12-01T03:00:00Z' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$NetworkId,
        [Parameter(Mandatory)][ValidateSet('appliance','switch','wireless','camera','cellularGateway','sensor')][string]$ProductType,
        [Parameter(Mandatory)][string]$VersionId,
        [Parameter(Mandatory)][datetime]$TimeUtc
    )
    if ($TimeUtc.ToUniversalTime() -le [datetime]::UtcNow) { throw 'Firmware schedule must be in the future.' }
    $timestamp = $TimeUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $body = @{products=@{$ProductType=@{nextUpgrade=@{time=$timestamp;toVersion=@{id=$VersionId}}}}}
    if ($PSCmdlet.ShouldProcess("$NetworkId/$ProductType","Schedule firmware $VersionId at $timestamp")) {
        Invoke-MerakiApi -Method PUT -Path "/networks/$NetworkId/firmwareUpgrades" -Body $body
    }
}
