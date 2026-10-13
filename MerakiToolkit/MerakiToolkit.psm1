# MerakiToolkit - modular Cisco Meraki Dashboard API client
# Optional manifest properties are allowed; do not set caller/module-wide strict mode.
$script:MerakiApiBase = 'https://api.meraki.com/api/v1'
$script:MerakiApiKey = $null
$script:MerakiMaxRetries = 4
foreach ($folder in @('Private','Public')) {
    foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' -File | Sort-Object Name)) {
        . $file.FullName
    }
}
Export-ModuleMember -Function @(
    'Connect-Meraki','Disconnect-Meraki','Get-MerakiConnection','Invoke-MerakiApi',
    'Get-MerakiOrganization','Get-MerakiNetwork','Get-MerakiDevice','Get-MerakiNetworkDevice',
    'Get-MerakiDeviceAvailability','Get-MerakiInventory','Get-MerakiOrganizationInventory',
    'Get-MerakiNetworkClient','Get-MerakiNetworkEvent','Get-MerakiNetworkFirmware',
    'Get-MerakiFirmwareReport','Get-MerakiWirelessSsid','Get-MerakiSwitchPort',
    'Get-MerakiApplianceVlan','Get-MerakiFirewallRules','Get-MerakiVpnConfiguration',
    'Get-MerakiConfigurationChanges','Get-MerakiDeviceUplink','Get-MerakiHealth',
    'Get-MerakiDashboard','Export-MerakiDashboard','Get-MerakiNetworkDiagnostics',
    'Export-MerakiNetworkConfig','New-MerakiNetwork','Add-MerakiNetworkDevice','Add-MerakiOrganizationInventory',
    'Set-MerakiDevice','Set-MerakiSwitchPort','Set-MerakiWirelessSsid',
    'New-MerakiApplianceVlan','Set-MerakiApplianceVlan',
    'Set-MerakiFirewallRules','Set-MerakiVpnConfiguration',
    'Restart-MerakiDevice','Set-MerakiFirmwareUpgrade',
    'Get-MerakiDeploymentPlan','Invoke-MerakiDeployment',
        'Start-MerakiDevicePing','Start-MerakiCableTest','Start-MerakiThroughputTest','Start-MerakiPortCycle','Start-MerakiWakeOnLan','Get-MerakiLiveToolResult','Get-MerakiFailedClientConnections','Get-MerakiHealthDiff','Get-MerakiConfigDiff','Invoke-MerakiConfigTemplate'
)