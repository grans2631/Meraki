function Invoke-MerakiConfigTemplate {
<#
.SYNOPSIS
Apply previewed template changes after approval, validated snapshot and post-apply readback.
.DESCRIPTION
Requires a reviewed Get-MerakiConfigDiff fingerprint, -Approve and a NEW secure SnapshotPath.
The command rechecks the live state after the snapshot and aborts on concurrent changes.
Does not automatically roll back. v1 excludes secrets, VLAN creation and deletion.
.EXAMPLE
Invoke-MerakiConfigTemplate -Template '.\assignment.json' -NetworkId 'N_123' -WhatIf
.EXAMPLE
Invoke-MerakiConfigTemplate -Template '.\assignment.json' -NetworkId 'N_123' -SnapshotPath 'C:\Secure\Meraki\before.json' -ApprovedFingerprint 'HASH_FROM_DIFF' -Approve
#>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][string]$NetworkId,
        [string]$SnapshotPath,
        [string]$ApprovedFingerprint,
        [switch]$Approve,
        [switch]$AllowFirewallReplacement
    )
    $diff=Get-MerakiConfigDiff -Template $Template -NetworkId $NetworkId
    if ($diff.blockedCount -gt 0 -or -not $diff.canApply) {
        throw "Template has $($diff.blockedCount) blocked change(s); resolve before applying."
    }
    if ($diff.changeCount -eq 0) {
        return [pscustomobject]@{status='InSync';networkId=$NetworkId;diff=$diff}
    }
    if ($WhatIfPreference -or $PSBoundParameters.ContainsKey('WhatIf')) {
        [void]$PSCmdlet.ShouldProcess($NetworkId,"PREVIEW $($diff.changeCount) template changes, no writes")
        return $diff
    }
    if (-not $Approve -or [string]::IsNullOrWhiteSpace($ApprovedFingerprint) -or
        $ApprovedFingerprint -cne $diff.fingerprint) {
        throw 'No approved matching diff. Run Get-MerakiConfigDiff, review changes, then specify -Approve and exact -ApprovedFingerprint.'
    }
    if ([string]::IsNullOrWhiteSpace($SnapshotPath)) {throw 'Provide a new -SnapshotPath for a local pre-apply export.'}
    if (@($diff.changes | Where-Object Family -eq 'applianceL3FirewallRules').Count -gt 0 -and -not $AllowFirewallReplacement) {
        throw 'Complete ordered firewall ruleset replacement requires -AllowFirewallReplacement.'
    }
    $snapshotFull=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SnapshotPath)
    if (Test-Path -LiteralPath $snapshotFull) {throw 'SnapshotPath already exists; refusing overwrite.'}
    $parent=Split-Path -Path $snapshotFull -Parent
    if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw 'Snapshot parent directory must already exist and be secured.'
    }
    $dir=$parent
    while($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir '.git')) {
            throw 'Snapshot directory is inside a Git working tree. Store private customer snapshots outside repositories.'
        }
        $up=Split-Path -Path $dir -Parent
        if (-not $up -or $up -eq $dir) {break}
        $dir=$up
    }
    if (-not $PSCmdlet.ShouldProcess($NetworkId,("APPROVED apply {0} setting changes after local snapshot" -f $diff.changeCount))){
        return $diff
    }
    $completed=New-Object 'System.Collections.Generic.List[string]'
    $snapshotCreated=$false
    try {
        Export-MerakiNetworkConfig -NetworkId $NetworkId -Path $snapshotFull -ErrorAction Stop | Out-Null
        $snapshotCreated=$true
        if (-not (Test-Path -LiteralPath $snapshotFull -PathType Leaf)) {throw 'Snapshot export did not create a file.'}
        [void](Assert-MerakiConfigSnapshot -Path $snapshotFull -Diff $diff)
        $recheck=Get-MerakiConfigDiff -Template $Template -NetworkId $NetworkId
        if ($recheck.fingerprint -cne $diff.fingerprint -or -not $recheck.canApply) {
            throw 'Live state or template changed between approval and snapshot. No configuration changes applied.'
        }
        foreach ($change in @($diff.changes)){
            switch ($change.Family) {
                'wirelessSsids' {
                    Set-MerakiWirelessSsid -NetworkId $NetworkId -Number ([int]$change.Identity) -Settings $change.Desired -Confirm:$false -ErrorAction Stop | Out-Null
                }
                'applianceVlans' {
                    Set-MerakiApplianceVlan -NetworkId $NetworkId -VlanId $change.Identity -Settings $change.Desired -Confirm:$false -ErrorAction Stop | Out-Null
                }
                'switchPorts' {
                    $parts=$change.Identity.Split('|')
                    Set-MerakiSwitchPort -Serial $parts[0] -PortId $parts[1] -Settings $change.Desired -Confirm:$false -ErrorAction Stop | Out-Null
                }
                'applianceL3FirewallRules' {
                    Set-MerakiFirewallRules -NetworkId $NetworkId -Rules @($change.Desired) -Confirm:$false -ErrorAction Stop | Out-Null
                }
                default {throw "Refusing unknown change family $($change.Family)"}
            }
            $completed.Add("$($change.Family):$($change.Identity)")
        }
        $verified=Get-MerakiConfigDiff -Template $Template -NetworkId $NetworkId
        if ($verified.changeCount -ne 0 -or -not $verified.canApply) {
            throw ("Post-apply verification found {0} remaining change(s). No automatic rollback." -f $verified.changeCount)
        }
        [pscustomobject]@{
            status='Verified'
            networkId=$NetworkId
            appliedCount=$completed.Count
            applied=@($completed.ToArray())
            snapshotPath=$snapshotFull
            snapshotSha256=(Get-FileHash -LiteralPath $snapshotFull -Algorithm SHA256).Hash
            verifiedAtUtc=[datetime]::UtcNow.ToString('o')
            note='No automatic rollback. Follow the documented manual recovery procedure if needed.'
        }
    }
    catch {
        $label=if($snapshotCreated){$snapshotFull}else{'NOT CREATED'}
        throw ("CONFIG TEMPLATE APPLY HALTED: {0}. Completed writes: {1}. Snapshot: {2}. No automatic rollback." -f $_.Exception.Message,$completed.Count,$label)
    }
}
