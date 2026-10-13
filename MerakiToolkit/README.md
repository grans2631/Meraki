# MerakiToolkit v0.1.0

PowerShell 5.1+/7 module for Meraki Dashboard API v1, providing reusable API access, monitoring, fleet discovery, diagnostics, guarded configuration changes, deployments, and reporting.

## Install

~~~powershell
git clone https://github.com/grans2631/Meraki.git
Set-Location .\Meraki
Import-Module .\MerakiToolkit\MerakiToolkit.psd1 -Force
Get-Command -Module MerakiToolkit | Sort-Object Name
~~~

## Connection

~~~powershell
Connect-Meraki    # masked API key prompt, key stays in process memory
Get-MerakiOrganization
Disconnect-Meraki
~~~

For unattended execution, provide MERAKI_DASHBOARD_API_KEY from a secure task scheduler / CI secrets provider and use Connect-Meraki -UseEnvironment. Do not supply API keys on command lines or commit keys to Git. Dashboard API must be enabled and the API account must have correct scopes. Claims can need licensing-write permissions.

## Read fleet and export reports

~~~powershell
$org = 'ORG_ID'
Get-MerakiNetwork -OrganizationId $org
Get-MerakiInventory -OrganizationId $org
Get-MerakiOrganizationInventory -OrganizationId $org |
    Sort-Object Network,Name | Format-Table
Get-MerakiDeviceAvailability -OrganizationId $org -Status offline
Get-MerakiFirmwareReport -OrganizationId $org | Export-Csv .\Firmware.csv -NoTypeInformation
Get-MerakiHealth -OrganizationId $org
Get-MerakiNetworkDiagnostics -OrganizationId $org -NetworkId 'N_12345'
Export-MerakiDashboard -OrganizationId $org -Format Html -Path .\Fleet.html
Export-MerakiNetworkConfig -NetworkId 'N_12345' -Path .\Config.json
~~~

Reports can include customer metadata and addressing. Although configuration export redacts commonly-named secret fields, use a restricted local storage location and inspect every export before sharing. Never commit reports to this public repository.

## Deploy any combination of MX, MS and MR

Set network.productTypes in JSON to any subset of appliance, switch, wireless, camera, cellularGateway, and sensor. Current per-product configuration automation is implemented for MX/MS/MR; new families are supported for inventory, network creation, naming and firmware where available. Use network.existingNetworkId for an existing site, or provide network.name to create a new network. Devices need serial and productType. They must be in organization inventory unless claimToInventory is explicitly true.

~~~powershell
# Offline plan, no API calls and no changes
Get-MerakiDeploymentPlan -ManifestPath .\MerakiToolkit\examples\full-site.json

# Safe preview
Invoke-MerakiDeployment -ManifestPath .\MerakiToolkit\examples\full-site.json -WhatIf

# Live execution, explicit confirmation
Invoke-MerakiDeployment -ManifestPath .\private-site.json

# Optional replacement of ALL L3 firewall rules and/or site-to-site VPN config
Invoke-MerakiDeployment -ManifestPath .\private-site.json -AllowDisruptiveChanges
~~~

Order: verify or create network, claim missing inventory (opt-in), assign serials, update names, apply MX VLANs, MS ports, MR SSIDs, and optional gated MX firewall/VPN replacements.

Provide Wi-Fi keys through a manifest reference such as "ENV:MERAKI_WIFI_PSK", which is resolved only when applying. Keep live customer manifests OUTSIDE this public repo. Every high-level write supports -WhatIf and -Confirm. The generic Invoke-MerakiApi supports unguarded raw API writes and should be limited to advanced, reviewed operations.

## Current limitations

This is an initial implementation, NOT a fully tested turnkey zero-touch solution. It does not perform static local WAN bootstrap, licensing, physical uplink wiring, MX VLAN-mode enablement, full HA, stack provisioning, NAT, every security rule, or all Meraki API features. If using MX VLANs, first enable VLAN mode as required. Device assignment can take several minutes to propagate before subsequent API writes succeed.

Deployments are not transactional and have NO automatic rollback. Back up configurations, conduct maintenance windows and lab tests, and audit device health following changes.

## Feature set

- Discovery: organizations, sites, assigned/unassigned inventory, statuses, clients, network events, firmware, switch ports, MX VLAN/firewall/VPN, wireless SSIDs, WAN uplinks, configuration changes.
- Change: create network, claim to inventory/network, set device metadata, MX VLAN, MS ports, MR SSID, replace MX L3 firewall/VPN, reboot, schedule firmware.
- Reports: fleet health, dashboard object, local HTML/CSV/JSON dashboard and local redacted config snapshot.
- Deployment: JSON configuration, offline preview, modular MX/MS/MR selection, changes behind confirmation.

## Tests

~~~powershell
pwsh -NoProfile -File .\tests\Smoke.Tests.ps1
# On Windows PowerShell 5.1:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Smoke.Tests.ps1
~~~

Tests check parsing/import, manifest validation and WhatIf behavior with no API credentials. They are not end-to-end API integration tests.

Future: WAN/HA, advanced RF monitoring, automated repair recommendations, configuration drift, backup/restore automation, Domotz/StackWitness integration, richer dashboard UI and scheduled telemetry.

Cisco API reference: https://developer.cisco.com/meraki/api-v1/api-index/
