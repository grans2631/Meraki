function Get-MerakiHealthDiff {
<#
.SYNOPSIS
Track device availability changes between fleet polls and emit webhook-ready JSON.
.DESCRIPTION
Read-only Meraki API operations. Persists a minimal local baseline and emits only changed
device statuses. A first run seeds the baseline and produces zero alerts. Does not POST
any webhook, change Dashboard config, or autonomously remediate issues.
.EXAMPLE
Get-MerakiHealthDiff -OrganizationId 'ORG_ID' -StatePath '.\state\meraki-org.json' -OutJsonPath '.\alerts.json'
.EXAMPLE
(Get-MerakiHealthDiff -OrganizationId 'ORG_ID' -StatePath '.\state\meraki-org.json' -NoSave).changes
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OrganizationId,
        [Parameter(Mandatory)][string]$StatePath,
        [string]$OutJsonPath,
        [switch]$NoSave
    )
    $snapshotPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StatePath)
    $previous=@()
    $baseline= -not (Test-Path -LiteralPath $snapshotPath)
    if (-not $baseline) {
        $saved=Get-Content -LiteralPath $snapshotPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ([string]$saved.organizationId -ne $OrganizationId) {
            throw 'Refusing to compare snapshot from a different Meraki organization.'
        }
        $previous=@($saved.devices | Where-Object { $null -ne $_ })
    }
    $inventory=@(Get-MerakiOrganizationInventory -OrganizationId $OrganizationId)
    $current=@(foreach($d in $inventory) {
        [pscustomobject]@{
            serial=[string]$d.Serial
            networkId=[string]$d.NetworkId
            name=[string]$d.Name
            status=[string]$d.Status
        }
    })
    $changes=@()
    if (-not $baseline) {
        $changes=@(Compare-MerakiHealthStates -Previous $previous -Current $current)
    }
    # Do not emit missing devices as "offline"; absence may be API pagination or permissions.
    $currentSerials=@{}
    foreach($d in $current) { if($d.serial) { $currentSerials[[string]$d.serial]=$true } }
    $missing=@(foreach($d in $previous) {
        if ($d.serial -and -not $currentSerials.ContainsKey([string]$d.serial)) { [string]$d.serial }
    })
    $timestamp=[datetime]::UtcNow.ToString('o')
    $event=[pscustomobject]@{
        schemaVersion='1.0'
        source='MerakiToolkit'
        eventType='meraki.device.availability.diff'
        organizationId=$OrganizationId
        observedAtUtc=$timestamp
        baselineCreated=$baseline
        changeCount=$changes.Count
        changes=@($changes)
        missingSerials=@($missing)
        note='Missing serials are NOT classified as offline. Assess monitoring coverage separately.'
    }
    if (-not $NoSave) {
        $parent=Split-Path -Path $snapshotPath -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }
        $state=[pscustomobject]@{
            schemaVersion='1.0'
            organizationId=$OrganizationId
            observedAtUtc=$timestamp
            devices=@($current)
        }
        $temp=$snapshotPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        try {
            ConvertTo-Json -InputObject $state -Depth 10 |
                Set-Content -LiteralPath $temp -Encoding UTF8 -ErrorAction Stop
            Move-Item -LiteralPath $temp -Destination $snapshotPath -Force -ErrorAction Stop
        } finally {
            if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        }
    }
    if ($OutJsonPath) {
        ConvertTo-Json -InputObject $event -Depth 12 |
            Set-Content -LiteralPath $OutJsonPath -Encoding UTF8 -ErrorAction Stop
    }
    return $event
}
