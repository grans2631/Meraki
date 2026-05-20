param(
    [Parameter(Mandatory = $true)]
    [string]$APIKey,

    [Parameter(Mandatory = $true)]
    [string]$OrgId,

    [Parameter(Mandatory = $true)]
    [ValidateSet("appliance", "switch", "wireless")]
    [string]$ProductType,

    [Parameter(Mandatory = $true)]
    [string]$ScheduleTimeUtc,

    [string[]]$NetworkNames = @(),

    [switch]$WhatIf
)

$BaseUrl = "https://api.meraki.com/api/v1"

$Headers = @{
    "X-Cisco-Meraki-API-Key" = $APIKey
    "Content-Type"           = "application/json"
}

function Get-ProductPresence {
    param(
        [object[]]$NetworkDevices
    )

    [PSCustomObject]@{
        HasAppliance = [bool]($NetworkDevices | Where-Object { $_.model -match "^MX|^Z" })
        HasSwitch    = [bool]($NetworkDevices | Where-Object { $_.model -match "^MS|^CS" })
        HasWireless  = [bool]($NetworkDevices | Where-Object { $_.model -match "^MR" })
    }
}

function Get-CurrentAndAvailableVersion {
    param(
        [object]$ProductInfo
    )

    $current = if ($ProductInfo.currentVersion.shortName) {
        $ProductInfo.currentVersion.shortName
    }
    elseif ($ProductInfo.currentVersion.firmware) {
        $ProductInfo.currentVersion.firmware
    }
    else {
        "Unknown"
    }

    $targetVersionId = $null
    $targetVersionName = $null

    if ($ProductInfo.availableVersions -and $ProductInfo.availableVersions.Count -gt 0) {
        $targetVersionId = $ProductInfo.availableVersions[0].id

        $targetVersionName = if ($ProductInfo.availableVersions[0].shortName) {
            $ProductInfo.availableVersions[0].shortName
        }
        elseif ($ProductInfo.availableVersions[0].firmware) {
            $ProductInfo.availableVersions[0].firmware
        }
    }

    [PSCustomObject]@{
        CurrentVersion   = $current
        TargetVersionId  = $targetVersionId
        TargetVersion    = $targetVersionName
    }
}

try {
    [void][datetime]::Parse($ScheduleTimeUtc)
}
catch {
    Write-Output "ScheduleTimeUtc must be a valid ISO-8601 datetime, for example: 2026-04-20T03:00:00Z"
    exit 1
}

try {
    Write-Output "Fetching organization networks..."
    $Networks = Invoke-RestMethod `
        -Uri "$BaseUrl/organizations/$OrgId/networks" `
        -Headers $Headers `
        -Method Get `
        -ErrorAction Stop

    if (-not $Networks) {
        Write-Output "No networks found in organization."
        exit 1
    }

    Write-Output "Fetching organization devices..."
    $Devices = Invoke-RestMethod `
        -Uri "$BaseUrl/organizations/$OrgId/devices" `
        -Headers $Headers `
        -Method Get `
        -ErrorAction Stop

    if (-not $Devices) {
        Write-Output "No devices found in organization."
        exit 1
    }

    $Results = @()

    foreach ($Network in $Networks) {
        $NetworkId = $Network.id
        $NetworkName = $Network.name

        if ($NetworkNames.Count -gt 0 -and $NetworkName -notin $NetworkNames) {
            continue
        }

        $NetworkDevices = $Devices | Where-Object { $_.networkId -eq $NetworkId }
        if (-not $NetworkDevices) {
            continue
        }

        $Presence = Get-ProductPresence -NetworkDevices $NetworkDevices

        switch ($ProductType) {
            "appliance" {
                if (-not $Presence.HasAppliance) { continue }
            }
            "switch" {
                if (-not $Presence.HasSwitch) { continue }
            }
            "wireless" {
                if (-not $Presence.HasWireless) { continue }
            }
        }

        try {
            $FirmwareInfo = Invoke-RestMethod `
                -Uri "$BaseUrl/networks/$NetworkId/firmwareUpgrades" `
                -Headers $Headers `
                -Method Get `
                -ErrorAction Stop
        }
        catch {
            Write-Output "Failed to get firmware info for network '$NetworkName': $($_.Exception.Message)"
            continue
        }

        $ProductInfo = $FirmwareInfo.products.$ProductType
        if (-not $ProductInfo) {
            Write-Output "No '$ProductType' firmware section found for '$NetworkName'."
            continue
        }

        $VersionInfo = Get-CurrentAndAvailableVersion -ProductInfo $ProductInfo

        if (-not $VersionInfo.TargetVersionId) {
            Write-Output "No available upgrade found for '$NetworkName' ($ProductType). Current: $($VersionInfo.CurrentVersion)"
            $Results += [PSCustomObject]@{
                Network         = $NetworkName
                ProductType     = $ProductType
                CurrentVersion  = $VersionInfo.CurrentVersion
                TargetVersion   = "None"
                ScheduledTime   = ""
                Result          = "No upgrade available"
            }
            continue
        }

        $Body = @{
            products = @{
                $ProductType = @{
                    nextUpgrade = @{
                        time      = $ScheduleTimeUtc
                        toVersion = @{
                            id = $VersionInfo.TargetVersionId
                        }
                    }
                }
            }
        } | ConvertTo-Json -Depth 6

        if ($WhatIf) {
            Write-Output "[WhatIf] Would schedule $ProductType upgrade for '$NetworkName' from '$($VersionInfo.CurrentVersion)' to '$($VersionInfo.TargetVersion)' at $ScheduleTimeUtc"
            $Results += [PSCustomObject]@{
                Network         = $NetworkName
                ProductType     = $ProductType
                CurrentVersion  = $VersionInfo.CurrentVersion
                TargetVersion   = $VersionInfo.TargetVersion
                ScheduledTime   = $ScheduleTimeUtc
                Result          = "Preview only"
            }
            continue
        }

        try {
            Invoke-RestMethod `
                -Uri "$BaseUrl/networks/$NetworkId/firmwareUpgrades" `
                -Headers $Headers `
                -Method Put `
                -Body $Body `
                -ErrorAction Stop | Out-Null

            Write-Output "Scheduled $ProductType upgrade for '$NetworkName' from '$($VersionInfo.CurrentVersion)' to '$($VersionInfo.TargetVersion)' at $ScheduleTimeUtc"

            $Results += [PSCustomObject]@{
                Network         = $NetworkName
                ProductType     = $ProductType
                CurrentVersion  = $VersionInfo.CurrentVersion
                TargetVersion   = $VersionInfo.TargetVersion
                ScheduledTime   = $ScheduleTimeUtc
                Result          = "Scheduled"
            }
        }
        catch {
            Write-Output "Failed to schedule upgrade for '$NetworkName': $($_.Exception.Message)"

            $Results += [PSCustomObject]@{
                Network         = $NetworkName
                ProductType     = $ProductType
                CurrentVersion  = $VersionInfo.CurrentVersion
                TargetVersion   = $VersionInfo.TargetVersion
                ScheduledTime   = $ScheduleTimeUtc
                Result          = "Failed"
            }
        }
    }

    Write-Output ""
    Write-Output "============================================================"
    Write-Output "FIRMWARE SCHEDULING SUMMARY"
    Write-Output "============================================================"
    $Results | Sort-Object Network | Format-Table -AutoSize

    $CsvPath = "MerakiFirmwareScheduling_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $Results | Export-Csv -Path $CsvPath -NoTypeInformation
    Write-Output ""
    Write-Output "Results exported to: $CsvPath"
}
catch {
    Write-Output "Fatal error: $($_.Exception.Message)"
    exit 1
}

exit 0
