# Meraki PowerShell Repository

PowerShell automation for Cisco Meraki Dashboard API (MX appliances, MS switches, MR wireless).

## New MerakiToolkit module

The new PowerShell module is under [MerakiToolkit](MerakiToolkit/). It provides inventory, dashboards, diagnostics, provisioning and controlled writes.

Legacy standalone scripts at repository root remain unchanged for compatibility:
- AccessPointFirmwareCheck.ps1
- FirmwareChecks.ps1
- FirmwareDashboard.ps1
- ScheduleFirmwareUpdate.ps1

NOTE: FirmwareDashboard.ps1 also contains unrelated local-admin snippets after its firmware section. Retained for compatibility, not copied into the module.

~~~powershell
Import-Module .\MerakiToolkit\MerakiToolkit.psd1 -Force
Connect-Meraki
Get-MerakiOrganization
Get-MerakiDevice -OrganizationId 'ORG_ID'
Get-MerakiDashboard -OrganizationId 'ORG_ID'
Export-MerakiDashboard -OrganizationId 'ORG_ID' -Path .\Fleet.html -Format Html

Get-MerakiDeploymentPlan -ManifestPath .\MerakiToolkit\examples\full-site.json
Invoke-MerakiDeployment -ManifestPath .\MerakiToolkit\examples\full-site.json -WhatIf
~~~

For setup and caveats, read [module instructions](MerakiToolkit/README.md), [command cookbook](MerakiToolkit/docs/COMMANDS.md), and [example site manifests](MerakiToolkit/examples/).

NEVER commit API keys, PSKs, production customer configuration or other secrets to this public repository. See the [official Cisco Dashboard API documentation](https://developer.cisco.com/meraki/api-v1/api-index/).