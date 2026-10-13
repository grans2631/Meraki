# Reporting, dashboards, diagnostics, safe local configuration export.
<#
.SYNOPSIS
Summarize availability counts for the Meraki fleet.
.EXAMPLE
Get-MerakiHealth -OrganizationId 'ORG_ID'
#>
function Get-MerakiHealth {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$OrganizationId)
    $inventory = @(Get-MerakiOrganizationInventory -OrganizationId $OrganizationId)
    $networks = @(Get-MerakiNetwork -OrganizationId $OrganizationId)
    $offline = @($inventory | Where-Object Status -eq 'offline')
    $alerting = @($inventory | Where-Object Status -eq 'alerting')
    $online = @($inventory | Where-Object Status -eq 'online')
    $total = $inventory.Count
    [pscustomobject]@{
        OrganizationId = $OrganizationId
        Networks = $networks.Count
        Devices = $total
        Online = $online.Count
        Offline = $offline.Count
        Alerting = $alerting.Count
        UnknownOrDormant = $total - $online.Count - $offline.Count - $alerting.Count
        OnlinePercentage = if ($total -gt 0) { [math]::Round(100 * $online.Count / $total,1) } else { 0 }
        GeneratedAtUtc = [datetime]::UtcNow
    }
}
<#
.SYNOPSIS
Build a read-only fleet summary with per-network and device rows.
.EXAMPLE
Get-MerakiDashboard -OrganizationId 'ORG_ID'
#>
function Get-MerakiDashboard {
    <#
    .SYNOPSIS
    Read-only fleet snapshot containing totals, per-network statistics and device rows.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$OrganizationId)
    $devices = @(Get-MerakiOrganizationInventory -OrganizationId $OrganizationId)
    $networks = @(Get-MerakiNetwork -OrganizationId $OrganizationId)
    $summary = [pscustomobject]@{
        OrganizationId = $OrganizationId
        Networks = $networks.Count
        Devices = $devices.Count
        Online = @($devices | Where-Object Status -eq 'online').Count
        Offline = @($devices | Where-Object Status -eq 'offline').Count
        Alerting = @($devices | Where-Object Status -eq 'alerting').Count
        GeneratedAtUtc = [datetime]::UtcNow
    }
    $perNetwork = foreach ($n in $networks) {
        $rows = @($devices | Where-Object NetworkId -eq $n.id)
        [pscustomobject]@{
            NetworkId = $n.id
            Network = $n.name
            Devices = $rows.Count
            Online = @($rows | Where-Object Status -eq 'online').Count
            Offline = @($rows | Where-Object Status -eq 'offline').Count
            Alerting = @($rows | Where-Object Status -eq 'alerting').Count
        }
    }
    [pscustomobject]@{
        Summary = $summary
        Networks = @($perNetwork)
        Devices = @($devices)
    }
}
<#
.SYNOPSIS
Export fleet health to HTML, JSON or CSV locally.
.EXAMPLE
Export-MerakiDashboard -OrganizationId 'ORG_ID' -Path '.\fleet.html' -Format Html
#>
function Export-MerakiDashboard {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$OrganizationId,
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Html','Csv','Json')][string]$Format='Html'
    )
    $report = Get-MerakiDashboard -OrganizationId $OrganizationId
    switch ($Format) {
        'Csv' { $report.Devices | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 }
        'Json' { ConvertTo-Json -InputObject $report -Depth 25 | Set-Content -LiteralPath $Path -Encoding UTF8 }
        'Html' {
            $style = 'body{font:14px Segoe UI,Arial;margin:25px;background:#f6f8fa;color:#15202b}table{border-collapse:collapse;width:100%;margin-bottom:25px}th,td{border:1px solid #cbd5e1;padding:7px;text-align:left}th{background:#dce6ef}h1{color:#12465b}'
            $head = "<style>$style</style>"
            $html = @()
            $html += '<h1>Meraki Fleet Dashboard</h1>'
            $html += $report.Summary | ConvertTo-Html -Fragment -PreContent '<h2>Fleet summary</h2>'
            $html += $report.Networks | ConvertTo-Html -Fragment -PreContent '<h2>Networks</h2>'
            $html += $report.Devices | ConvertTo-Html -Fragment -PreContent '<h2>Devices</h2>'
            ConvertTo-Html -Head $head -Body ($html -join [environment]::NewLine) -Title 'Meraki Fleet Dashboard' |
                Set-Content -LiteralPath $Path -Encoding UTF8
        }
    }
    Get-Item -LiteralPath $Path
}
<#
.SYNOPSIS
Collect offline devices, firmware, uplink and event diagnostic context.
.EXAMPLE
Get-MerakiNetworkDiagnostics -OrganizationId 'ORG_ID' -NetworkId 'N_123'
#>
function Get-MerakiNetworkDiagnostics {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$OrganizationId,
        [Parameter(Mandatory)][string]$NetworkId
    )
    $network = Get-MerakiNetwork -NetworkId $NetworkId
    if ([string]$network.organizationId -ne $OrganizationId) { throw 'Network does not belong to selected organization.' }
    $devices = @(Get-MerakiOrganizationInventory -OrganizationId $OrganizationId | Where-Object NetworkId -eq $NetworkId)
    $problems = @($devices | Where-Object { $_.Status -ne 'online' })
    $errors = New-Object 'System.Collections.Generic.List[string]'
    $firmware = $null
    $events = $null
    $uplinks = @()
    try { $firmware = Get-MerakiNetworkFirmware -NetworkId $NetworkId }
    catch { $errors.Add('Firmware: ' + $_.Exception.Message) }
    try { $events = Get-MerakiNetworkEvent -NetworkId $NetworkId -PerPage 30 }
    catch { $errors.Add('Events: ' + $_.Exception.Message) }
    try { $uplinks = @(Get-MerakiDeviceUplink -OrganizationId $OrganizationId | Where-Object networkId -eq $NetworkId) }
    catch { $errors.Add('Uplinks: ' + $_.Exception.Message) }
    [pscustomobject]@{
        NetworkId = $NetworkId
        Network = $network.name
        TotalDevices = $devices.Count
        UnhealthyDevices = @($problems)
        Uplinks = $uplinks
        Firmware = $firmware
        Events = $events
        QueryErrors = @($errors)
        SuggestedNextSteps = @(
            'Review device connectivity and upstream switch power/uplink',
            'Check events and outage timestamps against WAN/DHCP/DNS',
            'Compare firmware with maintenance schedule and release notes',
            'Avoid rebooting until upstream connectivity and impact are understood'
        )
        GeneratedAtUtc = [datetime]::UtcNow
    }
}
function ConvertTo-MerakiSafeValue {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [valuetype]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $Value.Keys) {
            $name = [string]$key
            if ($name -match '(?i)(password|secret|token|psk|passphrase|privateKey|apiKey|sharedSecret)') {
                $result[$name] = '[REDACTED]'
            } else { $result[$name] = ConvertTo-MerakiSafeValue $Value[$key] }
        }
        return $result
    }
    if ($Value -is [pscustomobject]) {
        $result = @{}
        foreach ($p in $Value.PSObject.Properties) {
            if ($p.Name -match '(?i)(password|secret|token|psk|passphrase|privateKey|apiKey|sharedSecret)') {
                $result[$p.Name] = '[REDACTED]'
            } else { $result[$p.Name] = ConvertTo-MerakiSafeValue $p.Value }
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $arr = @()
        foreach ($item in $Value) { $arr += ,(ConvertTo-MerakiSafeValue $item) }
        return ,$arr
    }
    return $Value
}
<#
.SYNOPSIS
Export a best-effort redacted network configuration snapshot.
.EXAMPLE
Export-MerakiNetworkConfig -NetworkId 'N_123' -Path '.\site.json'
#>
function Export-MerakiNetworkConfig {
    <#
    .SYNOPSIS
    Export selected readable settings to a LOCAL redacted JSON file.
    .NOTES
    Network configuration can contain sensitive customer topology. Keep reports private.
    #>
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$NetworkId,
        [Parameter(Mandatory)][string]$Path
    )
    $network = Get-MerakiNetwork -NetworkId $NetworkId
    $devices = @(Get-MerakiNetworkDevice -NetworkId $NetworkId)
    $snapshot = @{
        exportedUtc=[datetime]::UtcNow.ToString('o')
        network=$network
        devices=$devices
    }
    if ($network.productTypes -contains 'appliance') {
        try { $snapshot.vlans = @(Get-MerakiApplianceVlan -NetworkId $NetworkId) }
        catch { Write-Warning ('VLAN export unavailable: ' + $_.Exception.Message) }
        try { $snapshot.firewall = Get-MerakiFirewallRules -NetworkId $NetworkId }
        catch { Write-Warning ('Firewall export unavailable: ' + $_.Exception.Message) }
        try { $snapshot.vpn = Get-MerakiVpnConfiguration -NetworkId $NetworkId }
        catch { Write-Warning ('VPN export unavailable: ' + $_.Exception.Message) }
    }
    if ($network.productTypes -contains 'wireless') {
        try { $snapshot.ssids = @(Get-MerakiWirelessSsid -NetworkId $NetworkId) }
        catch { Write-Warning ('Wireless export unavailable: ' + $_.Exception.Message) }
    }
    if ($network.productTypes -contains 'switch') {
        $ports = @{}
        foreach ($device in ($devices | Where-Object { $_.model -match '^(MS|CS)' })) {
            try { $ports[$device.serial] = @(Get-MerakiSwitchPort -Serial $device.serial) }
            catch { Write-Warning ('Switch port export unavailable for ' + $device.serial) }
        }
        $snapshot.switchPorts = $ports
    }
    $safe = ConvertTo-MerakiSafeValue $snapshot
    ConvertTo-Json -InputObject $safe -Depth 60 | Set-Content -LiteralPath $Path -Encoding UTF8
    Get-Item -LiteralPath $Path
}
