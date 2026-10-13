# MerakiToolkit Command Cookbook

Run Import-Module .\MerakiToolkit\MerakiToolkit.psd1 and Connect-Meraki first.

## Inventory, monitoring and discovery

~~~powershell
Get-MerakiOrganization
Get-MerakiOrganization -OrganizationId 'ORG_ID'
Get-MerakiNetwork -OrganizationId 'ORG_ID'
Get-MerakiNetwork -NetworkId 'N_123'
Get-MerakiDevice -OrganizationId 'ORG_ID'
Get-MerakiDevice -OrganizationId 'ORG_ID' -ProductType switch
Get-MerakiDevice -Serial 'QXXX-XXXX-XXXX'
Get-MerakiNetworkDevice -NetworkId 'N_123'
Get-MerakiInventory -OrganizationId 'ORG_ID'
Get-MerakiOrganizationInventory -OrganizationId 'ORG_ID'
Get-MerakiDeviceAvailability -OrganizationId 'ORG_ID' -Status offline
Get-MerakiNetworkClient -NetworkId 'N_123'
Get-MerakiNetworkEvent -NetworkId 'N_123'
Get-MerakiConfigurationChanges -OrganizationId 'ORG_ID'
~~~

## Firmware, health, dashboard and diagnosis

~~~powershell
Get-MerakiNetworkFirmware -NetworkId 'N_123'
Get-MerakiFirmwareReport -OrganizationId 'ORG_ID' | Export-Csv .\Firmware.csv -NoTypeInformation
Get-MerakiDeviceUplink -OrganizationId 'ORG_ID'
Get-MerakiHealth -OrganizationId 'ORG_ID'
Get-MerakiNetworkDiagnostics -OrganizationId 'ORG_ID' -NetworkId 'N_123'
Get-MerakiDashboard -OrganizationId 'ORG_ID'
Export-MerakiDashboard -OrganizationId 'ORG_ID' -Path .\Fleet.html -Format Html
Export-MerakiNetworkConfig -NetworkId 'N_123' -Path .\Config.json
~~~

## Configuration reads

~~~powershell
Get-MerakiApplianceVlan -NetworkId 'N_123'
Get-MerakiFirewallRules -NetworkId 'N_123'
Get-MerakiVpnConfiguration -NetworkId 'N_123'
Get-MerakiSwitchPort -Serial 'QXXX-XXXX-XXXX'
Get-MerakiWirelessSsid -NetworkId 'N_123'
Get-MerakiWirelessSsid -NetworkId 'N_123' -Number 0
~~~

## Guarded writes (always preview first)

~~~powershell
New-MerakiNetwork -OrganizationId 'ORG_ID' -Name 'Branch01' -ProductTypes appliance,switch,wireless -WhatIf
Add-MerakiOrganizationInventory -OrganizationId 'ORG_ID' -Serials @('QXXX-XXXX-XXXX') -WhatIf
Add-MerakiNetworkDevice -NetworkId 'N_123' -Serials @('QXXX-XXXX-XXXX') -WhatIf
Set-MerakiDevice -Serial 'QXXX-XXXX-XXXX' -Settings @{name='Branch-AP01'} -WhatIf
Set-MerakiSwitchPort -Serial 'QXXX-XXXX-XXXX' -PortId '1' -Settings @{type='access';vlan=10;enabled=$true} -WhatIf
Set-MerakiWirelessSsid -NetworkId 'N_123' -Number 1 -Settings @{name='Guest';enabled=$false} -WhatIf
New-MerakiApplianceVlan -NetworkId 'N_123' -Settings @{id='10';name='Staff';subnet='192.0.2.0/24';applianceIp='192.0.2.1'} -WhatIf
Set-MerakiApplianceVlan -NetworkId 'N_123' -VlanId '10' -Settings @{name='Staff'} -WhatIf
Restart-MerakiDevice -Serial 'QXXX-XXXX-XXXX' -WhatIf
Set-MerakiFirmwareUpgrade -NetworkId 'N_123' -ProductType switch -VersionId 'VERSION_ID' -TimeUtc '2026-12-01T03:00:00Z' -WhatIf
~~~

These two operations REPLACE full settings, and can disrupt connectivity:

~~~powershell
Set-MerakiFirewallRules -NetworkId 'N_123' -Rules @(@{comment='Allow DNS';policy='allow';protocol='udp';srcCidr='any';destCidr='any';destPort='53'}) -WhatIf
Set-MerakiVpnConfiguration -NetworkId 'N_123' -Settings @{mode='none'} -WhatIf
~~~

## Deploy

~~~powershell
Get-MerakiDeploymentPlan -ManifestPath .\MerakiToolkit\examples\full-site.json
Invoke-MerakiDeployment -ManifestPath .\MerakiToolkit\examples\full-site.json -WhatIf
~~~

For MX-only, MS-only or MR-only, set only the relevant product types and omit other configuration blocks. New site deployment creates a combined network if two or more product types are selected.

## API escape hatch

~~~powershell
Invoke-MerakiApi -Path '/organizations'
Invoke-MerakiApi -Path '/organizations/ORG_ID/networks' -AllPages
~~~

Warning: Invoke-MerakiApi supports unguarded raw POST/PUT/DELETE. Prefer high-level ShouldProcess commands for write operations. The module is a broad starter, not every supported endpoint in the Dashboard API.
