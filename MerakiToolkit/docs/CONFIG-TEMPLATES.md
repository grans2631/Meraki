# Round 4: Meraki desired-state v1 operator runbook

**Review-only. No live Meraki lab testing performed.** Round 3 PR #9 remains the non-production test gate.

## Scope

| Family | Desired fields | Write scope |
|---|---|---|
| Wireless SSID | name, enabled | Existing numbered SSID |
| MX VLAN | name, subnet, applianceIp | Existing VLAN updates ONLY |
| MS switch port | name, enabled, type, vlan, allowedVlans | Existing port on assigned switch |
| MX L3 firewall | Complete ordered rules list | **Whole list replacement** with extra opt-in |

Unsupported: PSKs/credentials/secrets, VLAN create/delete, arbitrary setting fields, WAN/NAT/HA, generic cross-client bulk changes, and automatic rollback. Other raw Invoke-MerakiApi and Set-* commands remain available outside the guarded template workflow; restrict their use operationally.

## Versioned JSON composition

Schema: MerakiToolkit/templates/schema-v1.json. Assignment kind MerakiConfigAssignment names an exact string networkId, a base layer path, ordered overlay paths. Base and overlays have kind MerakiConfigLayer and schemaVersion "1.0". Overlay entries merge by SSID number, VLAN ID or switch serial/portId. Only explicitly provided settings override earlier layers. An L3 firewall rules array, if included, replaces the entire previous desired ordered list. Unmentioned objects are UNMANAGED rather than deleted.

Copy sample files to a secure folder OUTSIDE this public repository, and update network ID and device serials:
- templates/examples/base.json
- templates/examples/overlays/small-office.json
- templates/examples/assignments/small-office.example.json
- templates/examples/overlays/FIREWALL-WHOLE-REPLACEMENT-EXAMPLE-DO-NOT-APPLY.json (not enabled by sample assignment)

## Zero-write preview and explicit application

~~~powershell
Import-Module .\MerakiToolkit\MerakiToolkit.psd1 -Force
Connect-Meraki

$networkId = 'N_LAB_NETWORK_ID'
$template = 'C:\Secure\Meraki\customer\assignment.json'

# Read-only plan: inspect EVERY before/desired setting and whole firewall rules.
$plan = Get-MerakiConfigDiff -Template $template -NetworkId $networkId
$plan | Select-Object networkId,changeCount,blockedCount,canApply,fingerprint
$plan.changes | Format-List Family,Identity,Action,Before,Desired,Reason

Invoke-MerakiConfigTemplate -Template $template -NetworkId $networkId -WhatIf

# Apply only after the entire plan is reviewed and blockedCount is zero.
# Parent directory must already exist, be secured, and be OUTSIDE Git.
$snapshot = 'C:\Secure\Meraki\before-change-UNIQUE.json'
Invoke-MerakiConfigTemplate -Template $template -NetworkId $networkId -SnapshotPath $snapshot -ApprovedFingerprint $plan.fingerprint -Approve

# For a FULL firewall ruleset replacement, separately add:
# -AllowFirewallReplacement
~~~

The last command uses PowerShell ShouldProcess to prompt for confirmation. It aborts unless it can read and validate a NEW Export-MerakiNetworkConfig snapshot with all targeted prior settings, and unless a second diff has the same approved fingerprint. Post-apply readback must show zero remaining differences.

**No automatic rollback:** if a write or verification fails, some settings could be changed. Do not assume transactionality. Exports are redacted and can omit unsupported settings; v1 prohibits editing SSID secrets because those cannot be recovered from this snapshot.

## Manual rollback from snapshot (human-reviewed)

1. Stop further writes. Preserve snapshot and SHA-256 hash, identify completed operations and ensure snapshot.network.id matches the affected site.
2. Confirm every needed section and field was actually exported. Missing, ambiguous or redacted prior values are a STOP condition. Meraki Dashboard/manual recovery may be required.
3. For each changed SSID, read snapshot.ssids by number; preview Set-MerakiWirelessSsid -WhatIf restoring only name/enabled fields touched. Approve deliberately.
4. For VLANs, select snapshot.vlans by ID; preview Set-MerakiApplianceVlan restoring only the changed name/subnet/applianceIp fields. Routing changes are disruptive and need a rollback maintenance plan.
5. For switches, select snapshot.switchPorts by serial and portId; preview Set-MerakiSwitchPort for touched keys only. Consider trunk/uplink/PoE implications.
6. For firewall replacements, ONLY use snapshot.firewall.rules when that entire ordered list is verified intact. Preview Set-MerakiFirewallRules -WhatIf and obtain separate approval for full replacement (NEVER a partial list).
7. Verify each restored value via the relevant Get-* command and confirm network reachability before closing the change.

Example: preview restoration of a VLAN **name only**:

~~~powershell
$before = Get-Content -LiteralPath $snapshot -Raw | ConvertFrom-Json
if ([string]$before.network.id -ne $networkId) { throw 'Wrong snapshot network' }
$old = @($before.vlans | Where-Object { [string]$_.id -eq '10' })
if ($old.Count -ne 1) { throw 'VLAN 10 missing or ambiguous' }
Set-MerakiApplianceVlan -NetworkId $networkId -VlanId '10' -Settings @{name=$old[0].name} -WhatIf
# Remove -WhatIf only after independent human approval.
~~~

Never replay an entire snapshot blindly or revert changes made by another administrator after the snapshot. Store snapshots securely; they contain confidential customer network topology.

## Observe-only drift and monitoring JSON

~~~powershell
$drift = Get-MerakiConfigDrift -Template $template -NetworkId $networkId -StatePath 'C:\Secure\Meraki\state\lab.json' -OutJsonPath 'C:\Secure\Meraki\alerts\lab.json'
$drift | Select-Object conformance,transition,changeCount,blockedCount
$drift.changes | Format-List
~~~

First observation seeds a baseline. Future polls emit drift-detected, drift-changed, blocked, or resolved transitions with the complete planned changes. JSON can be consumed by Automate, but this module neither sends a webhook nor attempts a repair.

**Release gate:** Offline mocked Pester and smoke tests run on Windows PowerShell 5.1 and PowerShell 7. They do not validate the API against live hardware. Review each of five stacked PRs independently; no production use until the separate non-production lab test gate is accepted.
