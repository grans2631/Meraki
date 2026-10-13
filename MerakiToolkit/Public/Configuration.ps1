# All configuration writes use PowerShell ShouldProcess. Pass -WhatIf to preview.
function New-MerakiNetwork {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$OrganizationId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('appliance','switch','wireless')][string[]]$ProductTypes,
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
    .DESCRIPTION
    Serial numbers must be claimed into organization inventory before assigning to a network.
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$NetworkId,[Parameter(Mandatory)][string[]]$Serials)
    $unique = @($Serials | Select-Object -Unique)
    if (-not $unique.Count) { throw 'Specify at least one serial.' }
    if ($PSCmdlet.ShouldProcess($NetworkId,("Assign {0} serial(s) to network" -f $unique.Count))) {
        Invoke-MerakiApi -Method POST -Path "/networks/$NetworkId/devices/claim" -Body @{serials=$unique}
    }
}
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
    .DESCRIPTION
    CAUTION: replaces the COMPLETE MX L3 firewall rule set, not a single entry.
    Back up current rules and review your plan before applying.
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$NetworkId,[Parameter(Mandatory)][object[]]$Rules)
    if ($Rules.Count -eq 0) { throw 'Refusing empty firewall rule replacement.' }
    if ($PSCmdlet.ShouldProcess($NetworkId,'REPLACE ALL MX L3 firewall rules')) {
        Invoke-MerakiApi -Method PUT -Path "/networks/$NetworkId/appliance/firewall/l3FirewallRules" -Body @{rules=$Rules}
    }
}
function Set-MerakiVpnConfiguration {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$NetworkId,[Parameter(Mandatory)][hashtable]$Settings)
    Assert-MerakiSettings $Settings
    if ($PSCmdlet.ShouldProcess($NetworkId,'Replace site-to-site VPN settings')) {
        Invoke-MerakiApi -Method PUT -Path "/networks/$NetworkId/appliance/vpn/siteToSiteVpn" -Body $Settings
    }
}
function Restart-MerakiDevice {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$Serial)
    if ($PSCmdlet.ShouldProcess($Serial,'REBOOT DEVICE (service interruption)')) {
        Invoke-MerakiApi -Method POST -Path "/devices/$Serial/reboot"
    }
}
function Set-MerakiFirmwareUpgrade {
    <#
    .DESCRIPTION
    Schedule an explicit firmware version ID and ISO 8601 UTC time.
    The API may refuse upgrades on unsupported networks or versions.
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$NetworkId,
        [Parameter(Mandatory)][ValidateSet('appliance','switch','wireless')][string]$ProductType,
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
