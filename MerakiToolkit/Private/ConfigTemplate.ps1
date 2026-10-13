# Pure, offline resolver for Meraki desired-state v1 templates.
# A template assignment links one network to a base layer plus ordered overlays.
function ConvertTo-MerakiTemplateDictionary {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $d = @{}
        foreach ($key in $Value.Keys) { $d[[string]$key] = ConvertTo-MerakiTemplateDictionary $Value[$key] }
        return ,$d
    }
    if ($Value -is [pscustomobject]) {
        $d = @{}
        foreach ($p in $Value.PSObject.Properties) { $d[$p.Name] = ConvertTo-MerakiTemplateDictionary $p.Value }
        return ,$d
    }
    if ($Value -is [array]) {
        $a = @()
        foreach ($item in $Value) { $a += ,(ConvertTo-MerakiTemplateDictionary $item) }
        return ,$a
    }
    return $Value
}
function Read-MerakiTemplateFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Kind)
    $file = [IO.Path]::GetFullPath($Path)
    if (-not [IO.File]::Exists($file)) { throw "Template file missing: $file" }
    $data = ConvertTo-MerakiTemplateDictionary (Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    if ($data.schemaVersion -cne '1.0' -or $data.kind -cne $Kind) {
        throw "$file must declare schemaVersion '1.0' and kind '$Kind'."
    }
    return $data
}
function Assert-MerakiTemplateKeys {
    param([hashtable]$Value,[string[]]$Allowed,[string]$Path)
    foreach ($key in $Value.Keys) {
        if ([string]$key -cnotin $Allowed) { throw "Unsupported template field '$Path.$key'. v1 is intentionally restricted." }
    }
}
function Test-MerakiTemplateLayer {
    param([hashtable]$Layer)
    Assert-MerakiTemplateKeys $Layer @('kind','schemaVersion','description','wirelessSsids','applianceVlans','applianceL3FirewallRules','switchPorts') 'layer'
    $keyRules = @(
        @{field='wirelessSsids'; identity='number'; setting=@('name','enabled')},
        @{field='applianceVlans'; identity='id'; setting=@('name','subnet','applianceIp')},
        @{field='switchPorts'; identity='serial|portId'; setting=@('name','enabled','type','vlan','allowedVlans')}
    )
    foreach ($rule in $keyRules) {
        $field=$rule.field
        if (-not $Layer.ContainsKey($field)) {continue}
        if ($Layer[$field] -isnot [array]) {throw "$field must be an array."}
        $identities=@{}
        foreach ($item in $Layer[$field]) {
            if ($item -isnot [hashtable]) {throw "$field entries must be objects."}
            $allowed = if($field -eq 'switchPorts') {@('serial','portId','settings')} elseif($field -eq 'wirelessSsids') {@('number','settings')} else {@('id','settings')}
            Assert-MerakiTemplateKeys $item $allowed $field
            $id = if($field -eq 'switchPorts') {"$($item.serial)|$($item.portId)"} else {[string]$item[$rule.identity]}
            if ([string]::IsNullOrWhiteSpace($id) -or $id -match '^\|$' -or $id -match '^(\||\S+\|)$') { throw "Missing $field identity." }
            if ($field -eq 'wirelessSsids' -and ([string]$item.number -notmatch '^(?:[0-9]|1[0-4])$')) {throw 'SSID number must be between 0 and 14.'}
            if ($identities.ContainsKey($id)) {throw "Duplicate $field identity '$id' in a single layer."}
            $identities[$id]=$true
            if ($item.settings -isnot [hashtable] -or $item.settings.Count -eq 0) {throw "$field $id needs a nonempty settings object."}
            Assert-MerakiTemplateKeys $item.settings $rule.setting "$field[$id].settings"
            foreach($key in $item.settings.Keys) {
                if ($null -eq $item.settings[$key]) {throw "Null is not allowed in $field $id setting '$key'."}
            }
            if ($field -eq 'wirelessSsids' -and $item.settings.ContainsKey('enabled') -and $item.settings.enabled -isnot [bool]) {throw 'SSID enabled must be a boolean.'}
            if ($field -eq 'switchPorts' -and $item.settings.ContainsKey('enabled') -and $item.settings.enabled -isnot [bool]) {throw 'Switch enabled must be a boolean.'}
        }
    }
    if ($Layer.ContainsKey('applianceL3FirewallRules')) {
        $fw=$Layer.applianceL3FirewallRules
        if($fw -isnot [hashtable]) {throw 'applianceL3FirewallRules must be an object.'}
        Assert-MerakiTemplateKeys $fw @('rules') 'applianceL3FirewallRules'
        if ($fw.rules -isnot [array] -or $fw.rules.Count -eq 0) {throw 'Firewall replacement requires a nonempty complete ordered rules array.'}
        foreach($rule in $fw.rules) {
            if ($rule -isnot [hashtable]) {throw 'Each firewall rule must be an object.'}
            Assert-MerakiTemplateKeys $rule @('policy','protocol','srcCidr','destCidr','srcPort','destPort','comment','syslogEnabled') 'firewall.rule'
            foreach($key in @('policy','protocol','srcCidr','destCidr')){
                if ([string]::IsNullOrWhiteSpace([string]$rule[$key])) {throw "Missing firewall field $key."}
            }
            if ($rule.policy -notin @('allow','deny') -or $rule.protocol -notin @('any','icmp','icmp6','tcp','udp')) {throw 'Unsupported firewall policy/protocol.'}
        }
    }
}
function Merge-MerakiTemplateLayer {
    param([hashtable]$Desired,[hashtable]$Layer)
    foreach($family in @('wirelessSsids','applianceVlans','switchPorts')){
        if (-not $Layer.ContainsKey($family)) {continue}
        foreach($item in @($Layer[$family])){
            $id=if($family -eq 'switchPorts') {"$($item.serial)|$($item.portId)"} elseif($family -eq 'wirelessSsids') {[string]$item.number} else {[string]$item.id}
            $existing=@($Desired[$family] | Where-Object {
                $x=if($family -eq 'switchPorts') {"$($_.serial)|$($_.portId)"} elseif($family -eq 'wirelessSsids') {[string]$_.number} else {[string]$_.id}
                $x -ceq $id
            })
            if($existing.Count -gt 0){
                foreach($k in $item.settings.Keys){$existing[0].settings[$k]=$item.settings[$k]}
            }else{$Desired[$family] += ,$item}
        }
    }
    if ($Layer.ContainsKey('applianceL3FirewallRules')) {
        # Deliberate whole-set replacement; array order is meaningful.
        $Desired.applianceL3FirewallRules=$Layer.applianceL3FirewallRules
    }
}
function Resolve-MerakiConfigTemplate {
    param([Parameter(Mandatory)][string]$Template)
    $file=[IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Template))
    $assignment=Read-MerakiTemplateFile -Path $file -Kind 'MerakiConfigAssignment'
    Assert-MerakiTemplateKeys $assignment @('kind','schemaVersion','description','networkId','base','overlays') 'assignment'
    if ([string]::IsNullOrWhiteSpace([string]$assignment.networkId) -or [string]::IsNullOrWhiteSpace([string]$assignment.base)) {
        throw 'Assignment requires exact networkId (string) and base filepath.'
    }
    if (-not ($assignment.networkId -is [string])) {throw 'Network IDs must remain strings.'}
    if ($assignment.ContainsKey('overlays') -and $assignment.overlays -isnot [array]) {throw 'overlays must be an array.'}
    $root=[IO.Path]::GetDirectoryName($file)
    $layers=@($assignment.base)+@($assignment.overlays | Where-Object { $null -ne $_ })
    $merged=@{wirelessSsids=@();applianceVlans=@();switchPorts=@();applianceL3FirewallRules=$null}
    foreach($relative in $layers){
        if ([string]::IsNullOrWhiteSpace([string]$relative)) {throw 'Layer file path cannot be blank.'}
        $layerFile=[IO.Path]::GetFullPath([IO.Path]::Combine($root,[string]$relative))
        $layer=Read-MerakiTemplateFile -Path $layerFile -Kind 'MerakiConfigLayer'
        Test-MerakiTemplateLayer $layer
        Merge-MerakiTemplateLayer -Desired $merged -Layer $layer
    }
    [pscustomobject]@{
        schemaVersion='1.0'
        assignmentPath=$file
        networkId=[string]$assignment.networkId
        layers=@($layers)
        settings=$merged
    }
}
