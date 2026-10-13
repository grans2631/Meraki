@{
    RootModule = 'MerakiToolkit.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'b36ba426-192f-4960-bb34-42cde2c0a611'
    Author = 'Meraki Toolkit Contributors'
    CompanyName = 'Community'
    Copyright = '(c) 2026'
    Description = 'Cisco Meraki API PowerShell toolkit: inventory, deployment, monitoring, diagnostics, dashboards and guarded changes.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
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
        'Get-MerakiDeploymentPlan','Invoke-MerakiDeployment'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Meraki','Cisco','Dashboard','API','MSP','Networking')
            ProjectUri = 'https://github.com/grans2631/Meraki'
        }
    }
}