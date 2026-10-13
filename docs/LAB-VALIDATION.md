# Round 3, gate 8 — LIVE Meraki lab validation

**Status: NOT EXECUTED.** This runbook is a test gate only. There is no lab organization ID or API credential supplied in this repository. Do not run against a production organization.

## Prerequisites

1. Identify a dedicated **non-production** Meraki lab organization with API access enabled.
2. Generate a scoped API credential with write rights only for the lab organization. Supply it through a masked Connect-Meraki prompt, not in source code or console arguments.
3. Copy lab-only.json outside the public repository and replace YOUR_LAB_ORGANIZATION_ID with the approved org.
4. Use unique new name beginning ToolkitLAB- and required tag MerakiToolkit-LAB. NO device serials, no firewall changes, no existing network.
5. Check support for the requested product family and entitlement in the lab.

## Stage A — offline

~~~powershell
Import-Module .\MerakiToolkit\MerakiToolkit.psd1 -Force
Get-MerakiDeploymentPlan -ManifestPath .\MerakiToolkit\examples\lab-only.json
Invoke-MerakiDeployment -ManifestPath .\MerakiToolkit\examples\lab-only.json -WhatIf
~~~

## Stage B — read-only live preflight

~~~powershell
Connect-Meraki
Get-MerakiOrganization -OrganizationId 'YOUR_LAB_ORGANIZATION_ID'
Get-MerakiNetwork -OrganizationId 'YOUR_LAB_ORGANIZATION_ID'
~~~

Confirm the organization name and rights are truly non-production before continuing.

## Stage C — one tagged test network

~~~powershell
# Strict validation and explicit confirmation of a new lab network.
.\scripts\Invoke-MerakiLabValidation.ps1 -ManifestPath '.\private-lab.json' -LabOrganizationId 'YOUR_LAB_ORGANIZATION_ID' -Apply
~~~

The script rejects existing network IDs, any device serials, claimToInventory, missing lab tag, non-lab prefix and organization mismatch. It calls plan, WhatIf, prompts before real deployment, and verifies the returned network and its tag. **It creates a real Meraki network on Apply.**

## Evidence / acceptance

- [ ] Organization verified non-production
- [ ] Plan enumerated with zero network changes
- [ ] WhatIf enumerated and verified no network created
- [ ] Exactly one new network created with unique ToolkitLAB- name and MerakiToolkit-LAB tag
- [ ] GET of new network confirms matching organization, name, tag and product type
- [ ] Configuration change and network inventory reviewed for unintended writes
- [ ] Successful result/output and CI results attached to the lab test review
- [ ] Cleanup via Dashboard by lab owner ONLY after evidence recorded
- [ ] Production remains blocked until review confirms results

No deletion is automated: the lab owner must verify and remove the test network when appropriate. Avoid blind cleanup that could affect real equipment.
