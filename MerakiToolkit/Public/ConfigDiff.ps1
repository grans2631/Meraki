function Get-MerakiConfigDiff {
<#
.SYNOPSIS
Compare one network with its composable desired-state template; never writes to Meraki.
.DESCRIPTION
Reads only declared fields. Missing VLANs are Blocked (v1 only updates existing VLANs).
Firewall desired rules are compared as an ordered complete replacement; snapshots and
explicit approval are required separately before any apply. No secrets are managed.
.EXAMPLE
Get-MerakiConfigDiff -Template '.\customer\assignment.json' -NetworkId 'N_123'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][string]$NetworkId
    )
    $t=Resolve-MerakiConfigTemplate -Template $Template
    if ($NetworkId -cne $t.networkId) {throw 'Requested -NetworkId does not equal template assignment networkId.'}
    $network=Get-MerakiNetwork -NetworkId $NetworkId
    if ([string]$network.id -cne $NetworkId) {throw 'Network lookup ID mismatch.'}
    $desired=$t.settings
    $families=@()
    if(@($desired.wirelessSsids).Count){$families+='wireless'}
    if(@($desired.applianceVlans).Count -or $desired.applianceL3FirewallRules){$families+='appliance'}
    if(@($desired.switchPorts).Count){$families+='switch'}
    foreach($family in $families) {
        if ($family -notin @($network.productTypes)){throw "Network $NetworkId does not support template product family $family."}
    }
    $changes=New-Object 'System.Collections.Generic.List[object]'
    if (@($desired.wirelessSsids).Count) {
        $ssids=@(Get-MerakiWirelessSsid -NetworkId $NetworkId)
        foreach($entry in $desired.wirelessSsids) {
            $number=[int]$entry.number
            $matches=@($ssids | Where-Object { [int]$_.number -eq $number })
            if ($matches.Count -ne 1) {throw "Unable to read precisely one SSID $number on $NetworkId."}
            $actual=Select-MerakiConfigFields -Actual $matches[0] -Desired $entry.settings
            if (-not (Test-MerakiConfigEqual $actual $entry.settings)) {
                $changes.Add([pscustomobject]@{Family='wirelessSsids';Identity=[string]$number;Action='Update';Before=$actual;Desired=$entry.settings;Reason=$null})
            }
        }
    }
    if (@($desired.applianceVlans).Count) {
        $vlans=@(Get-MerakiApplianceVlan -NetworkId $NetworkId)
        foreach($entry in $desired.applianceVlans){
            $id=[string]$entry.id
            $match=@($vlans | Where-Object { [string]$_.id -ceq $id })
            if($match.Count -gt 1){throw "Duplicate live VLAN ID $id."}
            if($match.Count -eq 0){
                $changes.Add([pscustomobject]@{Family='applianceVlans';Identity=$id;Action='Blocked';Before=$null;Desired=$entry.settings;Reason='VLAN is absent: v1 never creates or deletes appliance VLANs.'})
                continue
            }
            $actual=Select-MerakiConfigFields -Actual $match[0] -Desired $entry.settings
            if (-not (Test-MerakiConfigEqual $actual $entry.settings)) {
                $changes.Add([pscustomobject]@{Family='applianceVlans';Identity=$id;Action='Update';Before=$actual;Desired=$entry.settings;Reason=$null})
            }
        }
    }
    if (@($desired.switchPorts).Count) {
        $devices=@(Get-MerakiNetworkDevice -NetworkId $NetworkId)
        $serials=@{}
        foreach($device in $devices){$serials[[string]$device.serial]=$true}
        foreach($entry in $desired.switchPorts) {
            $serial=[string]$entry.serial
            $portId=[string]$entry.portId
            $identity="$serial|$portId"
            if (-not $serials.ContainsKey($serial)) {
                $changes.Add([pscustomobject]@{Family='switchPorts';Identity=$identity;Action='Blocked';Before=$null;Desired=$entry.settings;Reason='Switch serial is not assigned to this network.'})
                continue
            }
            $port=Get-MerakiSwitchPort -Serial $serial -PortId $portId
            if ($null -eq $port){throw "Port $identity was not readable."}
            $actual=Select-MerakiConfigFields -Actual $port -Desired $entry.settings
            if (-not (Test-MerakiConfigEqual $actual $entry.settings)) {
                $changes.Add([pscustomobject]@{Family='switchPorts';Identity=$identity;Action='Update';Before=$actual;Desired=$entry.settings;Reason=$null})
            }
        }
    }
    if ($null -ne $desired.applianceL3FirewallRules) {
        $firewall=Get-MerakiFirewallRules -NetworkId $NetworkId
        if ($null -eq $firewall -or $null -eq $firewall.rules) {throw 'Cannot read the complete live MX L3 firewall ruleset.'}
        $existing=@($firewall.rules)
        $target=@($desired.applianceL3FirewallRules.rules)
        # Compare complete ordered rule list; do not silently ignore unexpected existing rules.
        if(-not (Test-MerakiConfigEqual $existing $target)){
            $changes.Add([pscustomobject]@{Family='applianceL3FirewallRules';Identity='complete-ordered-ruleset';Action='Replace';Before=$existing;Desired=$target;Reason='Replaces the complete MX L3 ruleset (excluding default).'})
        }
    }
    $items=@($changes.ToArray())
    $blocked=@($items | Where-Object Action -eq 'Blocked')
    $fingerprint=Get-MerakiConfigFingerprint -Value ([ordered]@{networkId=$NetworkId;templatePath=$t.assignmentPath;changes=$items})
    [pscustomobject]@{
        schemaVersion='1.0'
        networkId=$NetworkId
        templatePath=$t.assignmentPath
        layers=@($t.layers)
        evaluatedAtUtc=[datetime]::UtcNow.ToString('o')
        hasChanges=($items.Count -gt 0)
        canApply=($blocked.Count -eq 0)
        changeCount=$items.Count
        blockedCount=$blocked.Count
        fingerprint=$fingerprint
        changes=$items
    }
}
