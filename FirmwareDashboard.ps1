param(
    [string]$APIKey = "04d4d9f21d661b8b817cf8491e5178252bbeec83",
    [string]$OrgId  = "629378047925027937"
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

$BaseUrl = "https://api.meraki.com/api/v1"

$Headers = @{
    "X-Cisco-Meraki-API-Key" = $APIKey
    "Content-Type"           = "application/json"
}

function Get-ProductRow {
    param(
        [string]$NetworkName,
        [string]$DeviceType,
        [string]$DeviceModels,
        $ProductInfo
    )

    if (-not $ProductInfo) { return $null }

    $CurrentFirmware = if ($ProductInfo.currentVersion.shortName) {
        $ProductInfo.currentVersion.shortName
    }
    elseif ($ProductInfo.currentVersion.firmware) {
        $ProductInfo.currentVersion.firmware
    }
    else {
        "Unknown"
    }

    $FirmwareType = if ($ProductInfo.currentVersion.releaseType) {
        $ProductInfo.currentVersion.releaseType
    }
    else {
        "Unknown"
    }

    $UpgradeScheduled = if ($ProductInfo.nextUpgrade -and $ProductInfo.nextUpgrade.time) {
        "Yes"
    }
    else {
        "No"
    }

    $ScheduledFor = if ($ProductInfo.nextUpgrade -and $ProductInfo.nextUpgrade.time) {
        $ProductInfo.nextUpgrade.time
    }
    else {
        ""
    }

    $LastFirmwareUpdate = if ($ProductInfo.lastUpgrade -and $ProductInfo.lastUpgrade.time) {
        $ProductInfo.lastUpgrade.time
    }
    else {
        "Unknown"
    }

    # Practical approximation from API fields:
    # - Upgrade scheduled if nextUpgrade exists
    # - Upgrade available if availableVersions exists and current version differs
    # - Otherwise up to date
    $Availability = "Up to date"

    if ($UpgradeScheduled -eq "Yes") {
        $Availability = "Upgrade scheduled"
    }
    elseif ($ProductInfo.availableVersions -and $ProductInfo.availableVersions.Count -gt 0) {
        $FirstAvailableVersion = if ($ProductInfo.availableVersions[0].shortName) {
            $ProductInfo.availableVersions[0].shortName
        }
        elseif ($ProductInfo.availableVersions[0].firmware) {
            $ProductInfo.availableVersions[0].firmware
        }
        else {
            $null
        }

        if ($FirstAvailableVersion -and $FirstAvailableVersion -ne $CurrentFirmware) {
            $Availability = "Upgrade available"
        }
    }

    return [PSCustomObject]@{
        Network            = $NetworkName
        DeviceType         = $DeviceType
        DeviceModels       = $DeviceModels
        CurrentFirmware    = $CurrentFirmware
        FirmwareType       = $FirmwareType
        Availability       = $Availability
        UpgradeScheduled   = $UpgradeScheduled
        ScheduledFor       = $ScheduledFor
        LastFirmwareUpdate = $LastFirmwareUpdate
    }
}

function Get-MerakiFirmwareOverview {
    param(
        [string]$OrgId
    )

    try {
        Write-Output "Fetching organization networks..."
        $NetworksUri = "$BaseUrl/organizations/$OrgId/networks"

        $Networks = Invoke-RestMethod `
            -Uri $NetworksUri `
            -Headers $Headers `
            -Method Get `
            -ErrorAction Stop

        if (-not $Networks) {
            Write-Output "No networks found in organization."
            return @()
        }

        Write-Output "Fetching organization devices..."
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

        $Results = @()

        foreach ($Network in $Networks) {
            try {
                $NetworkId   = $Network.id
                $NetworkName = $Network.name

                # Identify which product families exist in this network
                $NetworkDevices = $Devices | Where-Object { $_.networkId -eq $NetworkId }

                if (-not $NetworkDevices) {
                    continue
                }

                $WirelessDevices  = $NetworkDevices | Where-Object { $_.model -match "^MR" }
                $SwitchDevices    = $NetworkDevices | Where-Object { $_.model -match "^MS" -or $_.model -match "^CS" }
                $ApplianceDevices = $NetworkDevices | Where-Object { $_.model -match "^MX|^Z" }

                $FirmwareUri = "$BaseUrl/networks/$NetworkId/firmwareUpgrades"

                $FirmwareInfo = Invoke-RestMethod `
                    -Uri $FirmwareUri `
                    -Headers $Headers `
                    -Method Get `
                    -ErrorAction Stop

                if ($WirelessDevices -and $FirmwareInfo.products.wireless) {
                    $WirelessModels = ($WirelessDevices | Select-Object -ExpandProperty model -Unique | Sort-Object) -join ", "
                    $Row = Get-ProductRow `
                        -NetworkName $NetworkName `
                        -DeviceType "Wireless" `
                        -DeviceModels $WirelessModels `
                        -ProductInfo $FirmwareInfo.products.wireless

                    if ($Row) { $Results += $Row }
                    Write-Output "✓ $NetworkName - Wireless processed"
                }

                if ($SwitchDevices -and $FirmwareInfo.products.switch) {
                    $SwitchModels = ($SwitchDevices | Select-Object -ExpandProperty model -Unique | Sort-Object) -join ", "
                    $Row = Get-ProductRow `
                        -NetworkName $NetworkName `
                        -DeviceType "Switch" `
                        -DeviceModels $SwitchModels `
                        -ProductInfo $FirmwareInfo.products.switch

                    if ($Row) { $Results += $Row }
                    Write-Output "✓ $NetworkName - Switch processed"
                }

                if ($ApplianceDevices -and $FirmwareInfo.products.appliance) {
                    $ApplianceModels = ($ApplianceDevices | Select-Object -ExpandProperty model -Unique | Sort-Object) -join ", "
                    $Row = Get-ProductRow `
                        -NetworkName $NetworkName `
                        -DeviceType "Appliance" `
                        -DeviceModels $ApplianceModels `
                        -ProductInfo $FirmwareInfo.products.appliance

                    if ($Row) { $Results += $Row }
                    Write-Output "✓ $NetworkName - Appliance processed"
                }
            }
            catch {
                Write-Output "✗ Error retrieving firmware information for network '$($Network.name)': $($_.Exception.Message)"
            }
        }

        return $Results
    }
    catch {
        Write-Output "API call failed: $($_.Exception.Message)"
        if ($_.Exception.InnerException) {
            Write-Output "Inner exception: $($_.Exception.InnerException.Message)"
        }
        return @()
    }
}

$Results = Get-MerakiFirmwareOverview -OrgId $OrgId

if ($Results.Count -gt 0) {
    Write-Output ""
    Write-Output "============================================================"
    Write-Output "MERAKI FIRMWARE OVERVIEW"
    Write-Output "============================================================"

    $Results | Sort-Object Network, DeviceType |
        Format-Table -Property Network, DeviceType, DeviceModels, CurrentFirmware, FirmwareType, Availability, UpgradeScheduled, ScheduledFor, LastFirmwareUpdate -AutoSize

    $CsvPath = "MerakiFirmwareOverview_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $Results | Export-Csv -Path $CsvPath -NoTypeInformation

    Write-Output ""
    Write-Output "Results exported to: $CsvPath"
}
else {
    Write-Output "No firmware data retrieved."
    exit 1
}

exit 0



(Get-CimInstance Win32_ComputerSystem).UserName


try {
    $LoggedOnUser = '@LoggedInUser@'

    # Validate variable
    if ([string]::IsNullOrWhiteSpace($LoggedOnUser) -or $LoggedOnUser -eq '@LoggedInUser@') {
        Write-Output "False"
        exit 1
    }

    # Normalize user format
    if ($LoggedOnUser -match '\\') {
        $Domain, $User = $LoggedOnUser -split '\\', 2
    }
    else {
        $Domain = $env:COMPUTERNAME
        $User   = $LoggedOnUser
    }

    $FullUser = "$Domain\$User"

    # Get local admins
    $Admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop

    # Check membership
    $IsAdmin = $Admins | Where-Object { $_.Name -eq $FullUser }

    if ($IsAdmin) {
        Write-Output "True"
        exit 0
    }
    else {
        Write-Output "False"
        exit 0
    }
}
catch {
    Write-Output "False"
    exit 1
}










try {
    $LoggedOnUser = (Get-CimInstance Win32_ComputerSystem).UserName

    if (-not $LoggedOnUser) {
        exit 1
    }

    if ($LoggedOnUser -match "\\") {
        $FullUser = $LoggedOnUser
    }
    else {
        $FullUser = "$env:COMPUTERNAME\$LoggedOnUser"
    }

    $GroupName = "Administrators"
    $ExistingMembers = Get-LocalGroupMember -Group $GroupName -ErrorAction Stop

    if ($ExistingMembers.Name -contains $FullUser) {
        Write-Output "User is already a member of Local Admin Group"
        exit 0
    }

    exit 1
}
catch {
    exit 1
}
