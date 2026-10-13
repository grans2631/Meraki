function Assert-MerakiConfigSnapshot {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Diff)
    $snapshot=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if (-not $snapshot.network -or [string]$snapshot.network.id -cne [string]$Diff.networkId) {
        throw 'Snapshot missing or wrong network identity.'
    }
    foreach($change in @($Diff.changes)) {
        $found=$null
        switch($change.Family){
            'wirelessSsids' {
                if ($null -eq $snapshot.ssids){throw 'Snapshot incomplete: wireless SSIDs were not exported.'}
                $found=@($snapshot.ssids | Where-Object { [string]$_.number -ceq $change.Identity })
            }
            'applianceVlans' {
                if ($null -eq $snapshot.vlans){throw 'Snapshot incomplete: appliance VLANs were not exported.'}
                $found=@($snapshot.vlans | Where-Object { [string]$_.id -ceq $change.Identity })
            }
            'switchPorts' {
                if ($null -eq $snapshot.switchPorts){throw 'Snapshot incomplete: switch ports were not exported.'}
                $parts=$change.Identity.Split('|')
                if ($parts.Count -ne 2) {throw 'Invalid planned switch identity.'}
                $ports=Get-MerakiConfigFieldValue -Object $snapshot.switchPorts -Name $parts[0]
                if ($null -eq $ports) {throw "Snapshot missing switch serial $($parts[0])."}
                $found=@($ports | Where-Object { [string]$_.portId -ceq $parts[1] })
            }
            'applianceL3FirewallRules' {
                if ($null -eq $snapshot.firewall -or $null -eq $snapshot.firewall.rules){
                    throw 'Snapshot incomplete: full firewall ruleset missing.'
                }
                if (-not (Test-MerakiConfigEqual @($snapshot.firewall.rules) @($change.Before))){
                    throw 'Snapshot firewall rules do not match the preview. Aborting.'
                }
                continue
            }
            default {throw "Unknown template family: $($change.Family)"}
        }
        if ($found.Count -ne 1) {throw "Snapshot missing or ambiguous target: $($change.Family) $($change.Identity)."}
        $previous=Select-MerakiConfigFields -Actual $found[0] -Desired $change.Desired
        if (-not (Test-MerakiConfigEqual $previous $change.Before)) {
            throw "Snapshot settings disagree with pre-apply diff for $($change.Family) $($change.Identity)."
        }
    }
    return $true
}
