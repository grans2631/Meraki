# Read-only inventory and configuration commands

<#
.SYNOPSIS
List accessible organizations or get a specific organization.
.EXAMPLE
Get-MerakiOrganization
#>
function Get-MerakiOrganization {
    [CmdletBinding()]param([string]$OrganizationId)
    if ($OrganizationId) { return Invoke-MerakiApi -Path "/organizations/$OrganizationId" }
    Invoke-MerakiApi -Path '/organizations' -AllPages
}
<#
.SYNOPSIS
List networks in an organization or retrieve one network.
.EXAMPLE
Get-MerakiNetwork -OrganizationId 'ORG_ID'
#>
function Get-MerakiNetwork {
    [CmdletBinding(DefaultParameterSetName='ByOrg')]
    param(
        [Parameter(ParameterSetName='ByOrg',Mandatory)][string]$OrganizationId,
        [Parameter(ParameterSetName='ById',Mandatory)][string]$NetworkId
    )
    if ($NetworkId) { return Invoke-MerakiApi -Path "/networks/$NetworkId" }
    Invoke-MerakiApi -Path "/organizations/$OrganizationId/networks" -AllPages
}
<#
.SYNOPSIS
Get a device by serial or list devices in an organization.
.EXAMPLE
Get-MerakiDevice -OrganizationId 'ORG_ID' -ProductType wireless
#>
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
<#
.SYNOPSIS
List devices assigned to a Dashboard network.
.EXAMPLE
Get-MerakiNetworkDevice -NetworkId 'N_123'
#>
function Get-MerakiNetworkDevice {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$NetworkId)
    Invoke-MerakiApi -Path "/networks/$NetworkId/devices" -AllPages
}
<#
.SYNOPSIS
List organization inventory including unassigned devices.
.EXAMPLE
Get-MerakiInventory -OrganizationId 'ORG_ID'
#>
function Get-MerakiInventory {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$OrganizationId)
    # Includes claimed but unassigned inventory.
    Invoke-MerakiApi -Path "/organizations/$OrganizationId/inventory/devices" -AllPages
}
<#
.SYNOPSIS
Get device online/offline availability for an organization.
.EXAMPLE
Get-MerakiDeviceAvailability -OrganizationId 'ORG_ID' -Status offline
#>
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
<#
.SYNOPSIS
Join network, device and availability data into inventory rows.
.EXAMPLE
Get-MerakiOrganizationInventory -OrganizationId 'ORG_ID'
#>
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
<#
.SYNOPSIS
List clients seen by a Meraki network over a timespan.
.EXAMPLE
Get-MerakiNetworkClient -NetworkId 'N_123' -Timespan 86400
#>
function Get-MerakiNetworkClient {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$NetworkId,
        [ValidateRange(60,2592000)][int]$Timespan = 86400,
        [ValidateRange(3,1000)][int]$PerPage = 100
    )
    Invoke-MerakiApi -Path "/networks/$NetworkId/clients" -Query @{timespan=$Timespan;perPage=$PerPage} -AllPages
}
<#
.SYNOPSIS
Get recent event payloads from one network.
.EXAMPLE
Get-MerakiNetworkEvent -NetworkId 'N_123'
#>
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
<#
.SYNOPSIS
Read network-level firmware details and schedules.
.EXAMPLE
Get-MerakiNetworkFirmware -NetworkId 'N_123'
#>
function Get-MerakiNetworkFirmware {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$NetworkId)
    Invoke-MerakiApi -Path "/networks/$NetworkId/firmwareUpgrades"
}
<#
.SYNOPSIS
Report product-specific firmware versions and upgrade metadata across networks.
.EXAMPLE
Get-MerakiFirmwareReport -OrganizationId 'ORG_ID'
#>
function Get-MerakiFirmwareReport {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$OrganizationId)
    foreach ($n in @(Get-MerakiNetwork -OrganizationId $OrganizationId)) {
        try {
            $info = Get-MerakiNetworkFirmware -NetworkId $n.id
            foreach ($type in @('appliance','switch','wireless')) {
                $product = $info.products.$type
                if (-not $product) { continue }
                # A listed alternative version is NOT necessarily recommended.
                # Null means the API has insufficient version metadata to compare.
                $available = $product.availableVersions
                $current = $product.currentVersion
                $upgradeAvailable = $null
                if ($null -ne $available) {
                    $upgradeAvailable = $false
                    foreach ($candidate in @($available)) {
                        if ($null -eq $candidate) { continue }
                        if ($current.id -and $candidate.id) {
                            if ([string]$candidate.id -ne [string]$current.id) { $upgradeAvailable = $true; break }
                        }
                        elseif ($current.shortName -and $candidate.shortName) {
                            if ([string]$candidate.shortName -ne [string]$current.shortName) { $upgradeAvailable = $true; break }
                        }
                        elseif ($current.firmware -and $candidate.firmware) {
                            if ([string]$candidate.firmware -ne [string]$current.firmware) { $upgradeAvailable = $true; break }
                        }
                        else { $upgradeAvailable = $null }
                    }
                }
                [pscustomobject]@{
                    NetworkName = $n.name
                    NetworkId = $n.id
                    ProductType = $type
                    CurrentVersion = $product.currentVersion.shortName
                    ReleaseType = $product.currentVersion.releaseType
                    LastUpgrade = $product.lastUpgrade.time
                    NextUpgrade = $product.nextUpgrade.time
                    UpgradeAvailable = $upgradeAvailable
                }
            }
        } catch {
            Write-Warning ("Could not retrieve firmware for network '{0}': {1}" -f $n.name,$_.Exception.Message)
        }
    }
}
<#
.SYNOPSIS
List wireless SSIDs or retrieve one numbered SSID.
.EXAMPLE
Get-MerakiWirelessSsid -NetworkId 'N_123' -Number 0
#>
function Get-MerakiWirelessSsid {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$NetworkId,
        [ValidateRange(0,14)][Nullable[int]]$Number
    )
    if ($PSBoundParameters.ContainsKey('Number')) {
        return Invoke-MerakiApi -Path "/networks/$NetworkId/wireless/ssids/$Number"
    }
    Invoke-MerakiApi -Path "/networks/$NetworkId/wireless/ssids"
}
<#
.SYNOPSIS
List or retrieve MS switch port settings.
.EXAMPLE
Get-MerakiSwitchPort -Serial 'QXXX-XXXX-XXXX'
#>
function Get-MerakiSwitchPort {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$Serial,
        [string]$PortId
    )
    if ($PortId) { return Invoke-MerakiApi -Path "/devices/$Serial/switch/ports/$PortId" }
    Invoke-MerakiApi -Path "/devices/$Serial/switch/ports"
}
<#
.SYNOPSIS
List or retrieve MX appliance VLAN configurations.
.EXAMPLE
Get-MerakiApplianceVlan -NetworkId 'N_123'
#>
function Get-MerakiApplianceVlan {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$NetworkId,
        [string]$VlanId
    )
    if ($VlanId) { return Invoke-MerakiApi -Path "/networks/$NetworkId/appliance/vlans/$VlanId" }
    Invoke-MerakiApi -Path "/networks/$NetworkId/appliance/vlans"
}
<#
.SYNOPSIS
Read the complete MX L3 firewall rule collection.
.EXAMPLE
Get-MerakiFirewallRules -NetworkId 'N_123'
#>
function Get-MerakiFirewallRules {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$NetworkId)
    Invoke-MerakiApi -Path "/networks/$NetworkId/appliance/firewall/l3FirewallRules"
}
<#
.SYNOPSIS
Read MX site-to-site VPN configuration.
.EXAMPLE
Get-MerakiVpnConfiguration -NetworkId 'N_123'
#>
function Get-MerakiVpnConfiguration {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$NetworkId)
    Invoke-MerakiApi -Path "/networks/$NetworkId/appliance/vpn/siteToSiteVpn"
}
<#
.SYNOPSIS
List Dashboard configuration changes in an organization.
.EXAMPLE
Get-MerakiConfigurationChanges -OrganizationId 'ORG_ID'
#>
function Get-MerakiConfigurationChanges {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$OrganizationId,
        [ValidateRange(3,1000)][int]$PerPage = 100
    )
    Invoke-MerakiApi -Path "/organizations/$OrganizationId/configurationChanges" -Query @{perPage=$PerPage} -AllPages
}
<#
.SYNOPSIS
Read MX appliance uplink status across an organization.
.EXAMPLE
Get-MerakiDeviceUplink -OrganizationId 'ORG_ID'
#>
function Get-MerakiDeviceUplink {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$OrganizationId)
    Invoke-MerakiApi -Path "/organizations/$OrganizationId/appliance/uplink/statuses" -AllPages
}
