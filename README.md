# Meraki PowerShell Repository

PowerShell automation for Cisco Meraki Dashboard API (MX appliances, MS switches, MR wireless).

## New MerakiToolkit module

The new PowerShell module is under [MerakiToolkit](MerakiToolkit/). It provides inventory, dashboards, diagnostics, provisioning and controlled writes.

Legacy script filenames at repository root remain only as fail-fast stubs that throw `use MerakiToolkit`:
- AccessPointFirmwareCheck.ps1
- FirmwareChecks.ps1
- FirmwareDashboard.ps1
- ScheduleFirmwareUpdate.ps1

The legacy firmware scripts no longer execute API requests or unrelated local-admin code. Use the module commands instead.

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