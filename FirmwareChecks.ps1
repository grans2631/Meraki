param(
    [string]$APIKey = "04d4d9f21d661b8b817cf8491e5178252bbeec83",
    [string]$OrgId  = "464563"
)

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($APIKey) -or $APIKey -eq "YOUR_API_KEY") {
    Write-Output "Error: APIKey parameter is required"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($OrgId) -or $OrgId -eq "YOUR_ORG_ID") {
    Write-Output "Error: OrgId parameter is required"
    exit 1
}

# Meraki API base URL
$BaseUrl = "https://api.meraki.com/api/v1"

# Headers
$Headers = @{
    "X-Cisco-Meraki-API-Key" = $APIKey
    "Content-Type"           = "application/json"
}

function Get-MerakiFirewallFirmware {
    param(
        [string]$APIKey,
        [string]$OrgId
    )

    try {
        Write-Output "Fetching devices for Organization: $OrgId..."

        $DevicesUri = "$BaseUrl/organizations/$OrgId/devices"

        $Devices = Invoke-RestMethod `
            -Uri $DevicesUri `
            -Headers $Headers `
            -Method Get `
            -ErrorAction Stop

        if (-not $Devices) {
            Write-Output "No devices found in organization."
            return @()
        }

        Write-Output "Found $($Devices.Count) total devices. Filtering for firewalls..."

        $Firewalls = $Devices | Where-Object { $_.model -match "^MX" }

        if (-not $Firewalls) {
            Write-Output "No firewalls found in organization."
            return @()
        }

        Write-Output "Found $($Firewalls.Count) firewall(s). Retrieving firmware, status, and last firmware update..."

        # Get device statuses
        $StatusesUri = "$BaseUrl/organizations/$OrgId/devices/statuses"

        $DeviceStatuses = @()
        try {
            $DeviceStatuses = Invoke-RestMethod `
                -Uri $StatusesUri `
                -Headers $Headers `
                -Method Get `
                -ErrorAction Stop
        }
        catch {
            Write-Output "⚠ Could not retrieve device statuses"
        }

        $FirmwareResults = @()

        foreach ($Firewall in $Firewalls) {
            try {
                $FirewallId = $Firewall.serial
                $DeviceName = if ($Firewall.name) { $Firewall.name } else { $Firewall.serial }
                $Model      = $Firewall.model
                $NetworkId  = $Firewall.networkId

                # Get current firmware
                $DeviceDetailsUri = "$BaseUrl/devices/$FirewallId"

                $DeviceDetails = Invoke-RestMethod `
                    -Uri $DeviceDetailsUri `
                    -Headers $Headers `
                    -Method Get `
                    -ErrorAction Stop

                $CurrentFirmware = if ($DeviceDetails.firmware) { $DeviceDetails.firmware } else { "Unknown" }

                # Get status
                $DeviceStatusObj = $DeviceStatuses | Where-Object { $_.serial -eq $FirewallId }
                $Status = if ($DeviceStatusObj -and $DeviceStatusObj.status) {
                    $DeviceStatusObj.status
                }
                else {
                    "Unknown"
                }

                # Get last firmware update time (network-level appliance firmware upgrade info)
                $LastFirmwareUpdate = "Unknown"
                if ($NetworkId) {
                    $FirmwareUpgradeUri = "$BaseUrl/networks/$NetworkId/firmwareUpgrades"

                    try {
                        $FirmwareUpgradeInfo = Invoke-RestMethod `
                            -Uri $FirmwareUpgradeUri `
                            -Headers $Headers `
                            -Method Get `
                            -ErrorAction Stop

                        if ($FirmwareUpgradeInfo.products.appliance.lastUpgrade.time) {
                            $LastFirmwareUpdate = $FirmwareUpgradeInfo.products.appliance.lastUpgrade.time
                        }
                    }
                    catch {
                        Write-Output "⚠ Could not retrieve last firmware update for $DeviceName"
                    }
                }

                $FirmwareResults += [PSCustomObject]@{
                    DeviceName         = $DeviceName
                    Model              = $Model
                    Serial             = $FirewallId
                    CurrentFirmware    = $CurrentFirmware
                    LastFirmwareUpdate = $LastFirmwareUpdate
                    Status             = $Status
                }

                Write-Output "✓ $DeviceName - Firmware: $CurrentFirmware | Last Update: $LastFirmwareUpdate | Status: $Status"
            }
            catch {
                Write-Output "✗ Error retrieving data for $($Firewall.name): $($_.Exception.Message)"

                $FirmwareResults += [PSCustomObject]@{
                    DeviceName         = if ($Firewall.name) { $Firewall.name } else { $Firewall.serial }
                    Model              = $Firewall.model
                    Serial             = $Firewall.serial
                    CurrentFirmware    = "Error"
                    LastFirmwareUpdate = "Error"
                    Status             = "Error"
                }
            }
        }

        return $FirmwareResults
    }
    catch {
        Write-Output "API call failed: $($_.Exception.Message)"

        if ($_.Exception.InnerException) {
            Write-Output "Inner exception: $($_.Exception.InnerException.Message)"
        }

        return @()
    }
}

# Execute
$Results = Get-MerakiFirewallFirmware -APIKey $APIKey -OrgId $OrgId

if ($Results.Count -gt 0) {
    Write-Output ""
    Write-Output "============================================================"
    Write-Output "FIREWALL FIRMWARE SUMMARY"
    Write-Output "============================================================"

    $Results | Format-Table -Property DeviceName, Model, Serial, CurrentFirmware, LastFirmwareUpdate, Status -AutoSize

    # Export
    $CsvPath = "MerakiFirewallFirmware_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $Results | Export-Csv -Path $CsvPath -NoTypeInformation

    Write-Output ""
    Write-Output "Results exported to: $CsvPath"
}
else {
    Write-Output "No firewall data retrieved."
    exit 1
}

exit 0
