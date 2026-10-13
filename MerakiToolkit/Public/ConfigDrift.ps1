function Get-MerakiConfigDrift {
<#
.SYNOPSIS
Check assigned Meraki template conformance and generate drift-change events, with no Dashboard writes.
.DESCRIPTION
Extends Get-MerakiHealthDiff's baseline/change pattern for desired-state conformance.
It stores a local baseline, includes the complete live read-only diff, and emits JSON
suitable for external monitoring. Does not post a webhook or modify Meraki settings.
.EXAMPLE
Get-MerakiConfigDrift -Template '.\customer\assignment.json' -NetworkId 'N_123' -StatePath 'C:\Secure\Meraki\state.json' -OutJsonPath 'C:\Secure\Meraki\drift.json'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][string]$NetworkId,
        [Parameter(Mandatory)][string]$StatePath,
        [string]$OutJsonPath,
        [switch]$NoSave
    )
    $diff=Get-MerakiConfigDiff -Template $Template -NetworkId $NetworkId
    $templatePath=[IO.Path]::GetFullPath($diff.templatePath)
    $stateFull=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StatePath)
    $exists=Test-Path -LiteralPath $stateFull -PathType Leaf
    $previous=$null
    if ($exists) {
        $previous=Get-Content -LiteralPath $stateFull -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ([string]$previous.networkId -cne $NetworkId -or [IO.Path]::GetFullPath([string]$previous.templatePath) -cne $templatePath) {
            throw 'Saved drift baseline belongs to a different network or template assignment.'
        }
    }
    $state=if($diff.blockedCount -gt 0){'blocked'}elseif($diff.changeCount -gt 0){'drifted'}else{'conformant'}
    $transition='none'
    if($exists) {
        if ([string]$previous.conformance -cne $state) {
            $transition=if($state -eq 'conformant'){'resolved'}elseif($state -eq 'blocked'){'blocked'}else{'drift-detected'}
        }
        elseif ($state -ne 'conformant' -and [string]$previous.fingerprint -cne $diff.fingerprint) {
            $transition='drift-changed'
        }
    }
    $now=[datetime]::UtcNow.ToString('o')
    $payload=[pscustomobject]@{
        schemaVersion='1.0'
        source='MerakiToolkit'
        eventType='meraki.network.config.conformance'
        networkId=$NetworkId
        templatePath=$templatePath
        observedAtUtc=$now
        baselineCreated=(-not $exists)
        conformance=$state
        transition=$transition
        changeCount=$diff.changeCount
        blockedCount=$diff.blockedCount
        fingerprint=$diff.fingerprint
        changes=@($diff.changes)
        actionsTaken=@()
        note='Observe-only. No Dashboard writes, webhook delivery or automatic remediation.'
    }
    if (-not $NoSave) {
        $parent=Split-Path -Path $stateFull -Parent
        if (-not (Test-Path -LiteralPath $parent -PathType Container)){
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }
        $record=[pscustomobject]@{
            schemaVersion='1.0';networkId=$NetworkId;templatePath=$templatePath
            observedAtUtc=$now;conformance=$state;fingerprint=$diff.fingerprint
        }
        $temp=$stateFull+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        try {
            ConvertTo-Json -InputObject $record -Depth 12 |
                Set-Content -LiteralPath $temp -Encoding UTF8 -ErrorAction Stop
            Move-Item -LiteralPath $temp -Destination $stateFull -Force -ErrorAction Stop
        }finally{
            if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}
        }
    }
    if ($OutJsonPath) {
        ConvertTo-Json -InputObject $payload -Depth 64 |
            Set-Content -LiteralPath $OutJsonPath -Encoding UTF8 -ErrorAction Stop
    }
    return $payload
}
