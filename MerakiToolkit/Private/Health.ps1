# Compare current fleet availability against a previously saved local snapshot.
function Compare-MerakiHealthStates {
    param(
        [Parameter(Mandatory)][object[]]$Previous,
        [Parameter(Mandatory)][object[]]$Current
    )
    $old=@{}
    foreach($d in $Previous) {
        if ($d.serial) { $old[[string]$d.serial] = $d }
    }
    $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach($d in $Current) {
        if (-not $d.serial) { continue }
        $serial=[string]$d.serial
        if (-not $old.ContainsKey($serial)) {
            # Newly discovered inventory is not an outage signal.
            continue
        }
        $before=[string]$old[$serial].status
        $after=[string]$d.status
        if ($before -eq $after) { continue }
        $severity='information'
        $kind='changed'
        if ($after -eq 'offline') { $severity='critical';$kind='offline' }
        elseif ($after -eq 'alerting') { $severity='warning';$kind='alerting' }
        elseif ($after -eq 'online' -and $before -in @('offline','alerting')) {
            $severity='information';$kind='recovered'
        }
        $rows.Add([pscustomobject]@{
            serial=$serial
            networkId=[string]$d.networkId
            name=[string]$d.name
            previousStatus=$before
            currentStatus=$after
            severity=$severity
            eventType=$kind
        })
    }
    return @($rows.ToArray() | Sort-Object serial)
}
