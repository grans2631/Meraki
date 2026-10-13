# Read-only inventory and configuration commands

function Get-MerakiOrganization {
    [CmdletBinding()]param([string]$OrganizationId)
    if ($OrganizationId) { return Invoke-MerakiApi -Path "/organizations/$OrganizationId" }
    Invoke-MerakiApi -Path '/organizations' -AllPages
}
function Get-MerakiNetwork {
    [CmdletBinding(DefaultParameterSetName='ByOrg')]
    param(
        [Parameter(ParameterSetName='ByOrg',Mandatory)][string]$OrganizationId,
        [Parameter(ParameterSetName='ById',Mandatory)][string]$NetworkId
    )
    if ($NetworkId) { return Invoke-MerakiApi -Path "/networks/$NetworkId" }
    Invoke-MerakiApi -Path "/organizations/$OrganizationId/networks" -AllPages
}
function Get-MerakiDevice {
    [CmdletBinding(DefaultParameterSetName='ByOrg')]
    param(
        [Parameter(ParameterSetName='ByOrg',Mandatory)][string]$OrganizationId,
        [Parameter(ParameterSetName='BySerial',Mandatory)][string]$Serial,
        [Parameter(ParameterSetName='ByOrg')][ValidateSet('appliance','switch','wireless')][string]$ProductType
    )
    if ($Serial) { return Invoke-MerakiApi -Path "/devices/$Serial" }
    $query = @{}
    if ($ProductType) { $query.productTypes = $ProductType }
    Invoke-MerakiApi -Path "/organizations/$OrganizationId/devices" -Query $query -AllPages
}
function Get-MerakiNetworkDevice {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$NetworkId)
    Invoke-MerakiApi -Path "/networks/$NetworkId/devices" -AllPages
}
function Get-MerakiInventory {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$OrganizationId)
    # Includes claimed but unassigned inventory.
    Invoke-MerakiApi -Path "/organizations/$OrganizationId/inventory/devices" -AllPages
}
function Get-MerakiDeviceAvailability {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$OrganizationId,
        [string]$NetworkId,
        [ValidateSet('online','offline','alerting','dormant')][string]$Status
    )
    $q = @{}
    if ($NetworkId) { $q.networkIds = $NetworkId }
    if ($Status) { $q.statuses = $Status }
    Invoke-MerakiApi -Path "/organizations/$OrganizationId/devices/availabilities" -Query $q -AllPages
}
function Get-MerakiOrganizationInventory {
    <#
    .SYNOPSIS
    Correlate inventory with network and availability data by device serial.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$OrganizationId)
    $networks = @(Get-MerakiNetwork -OrganizationId $OrganizationId)
    $devices = @(Get-MerakiDevice -OrganizationId $OrganizationId)
    $availability = @(Get-MerakiDeviceAvailability -OrganizationId $OrganizationId)
    $netById = @{}
    $statusBySerial = @{}
    foreach ($n in $networks) { $netById[[string]$n.id] = $n }
    foreach ($s in $availability) { $statusBySerial[[string]$s.serial] = $s }
    foreach ($d in $devices) {
        $s = $statusBySerial[[string]$d.serial]
        $n = $netById[[string]$d.networkId]
        [pscustomobject]@{
            OrganizationId = $OrganizationId
            NetworkId      = $d.networkId
            Network        = if ($n) { $n.name } else { $null }
            Serial         = $d.serial
            Name           = $d.name
            Model          = $d.model
            ProductType    = $d.productType
            Firmware       = $d.firmware
            LanIp          = $d.lanIp
            Status         = if ($s) { $s.status } else { 'unknown' }
            Mac            = $d.mac
            Tags           = ($d.tags -join ',')
        }
    }
}
function Get-MerakiNetworkClient {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$NetworkId,
        [ValidateRange(60,2592000)][int]$Timespan = 86400,
        [ValidateRange(3,1000)][int]$PerPage = 100
    )
    Invoke-MerakiApi -Path "/networks/$NetworkId/clients" -Query @{timespan=$Timespan;perPage=$PerPage} -AllPages
}
function Get-MerakiNetworkEvent {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$NetworkId,
        [ValidateRange(3,1000)][int]$PerPage = 100,
        [ValidateSet('appliance','switch','wireless')][string]$ProductType
    )
    $q = @{ perPage=$PerPage }
    if ($ProductType) { $q.productType=$ProductType }
    # Meraki's events response contains events plus cursor metadata; return as-is.
    Invoke-MerakiApi -Path "/networks/$NetworkId/events" -Query $q
}
function Get-MerakiNetworkFirmware {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$NetworkId)
    Invoke-MerakiApi -Path "/networks/$NetworkId/firmwareUpgrades"
}
function Get-MerakiFirmwareReport {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$OrganizationId)
    foreach ($n in @(Get-MerakiNetwork -OrganizationId $OrganizationId)) {
        try {
            $info = Get-MerakiNetworkFirmware -NetworkId $n.id
            foreach ($type in @('appliance','switch','wireless')) {
                $product = $info.products.$type
                if (-not $product) { continue }
                [pscustomobject]@{
                    NetworkName = $n.name
                    NetworkId = $n.id
                    ProductType = $type
                    CurrentVersion = $product.currentVersion.shortName
                    ReleaseType = $product.currentVersion.releaseType
                    LastUpgrade = $product.lastUpgrade.time
                    NextUpgrade = $product.nextUpgrade.time
                    UpgradeAvailable = $product.isUpgradeAvailable
                }
            }
        } catch {
            Write-Warning ("Could not retrieve firmware for network '{0}': {1}" -f $n.name,$_.Exception.Message)
        }
    }
}
function Get-MerakiWirelessSsid {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$NetworkId,
        [ValidateRange(0,14)][int]$Number = -1
    )
    if ($PSBoundParameters.ContainsKey('Number')) {
        return Invoke-MerakiApi -Path "/networks/$NetworkId/wireless/ssids/$Number"
    }
    Invoke-MerakiApi -Path "/networks/$NetworkId/wireless/ssids"
}
function Get-MerakiSwitchPort {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$Serial,
        [string]$PortId
    )
    if ($PortId) { return Invoke-MerakiApi -Path "/devices/$Serial/switch/ports/$PortId" }
    Invoke-MerakiApi -Path "/devices/$Serial/switch/ports"
}
function Get-MerakiApplianceVlan {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$NetworkId,
        [string]$VlanId
    )
    if ($VlanId) { return Invoke-MerakiApi -Path "/networks/$NetworkId/appliance/vlans/$VlanId" }
    Invoke-MerakiApi -Path "/networks/$NetworkId/appliance/vlans"
}
function Get-MerakiFirewallRules {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$NetworkId)
    Invoke-MerakiApi -Path "/networks/$NetworkId/appliance/firewall/l3FirewallRules"
}
function Get-MerakiVpnConfiguration {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$NetworkId)
    Invoke-MerakiApi -Path "/networks/$NetworkId/appliance/vpn/siteToSiteVpn"
}
function Get-MerakiConfigurationChanges {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$OrganizationId,
        [ValidateRange(3,1000)][int]$PerPage = 100
    )
    Invoke-MerakiApi -Path "/organizations/$OrganizationId/configurationChanges" -Query @{perPage=$PerPage} -AllPages
}
function Get-MerakiDeviceUplink {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$OrganizationId)
    Invoke-MerakiApi -Path "/organizations/$OrganizationId/appliance/uplink/statuses" -AllPages
}
