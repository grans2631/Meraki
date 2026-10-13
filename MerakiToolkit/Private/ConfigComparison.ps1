function Get-MerakiConfigFieldValue {
    param([AllowNull()][object]$Object,[string]$Name)
    if ($null -eq $Object) {return $null}
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {return $Object[$Name]}
        return $null
    }
    $p=$Object.PSObject.Properties[$Name]
    if ($p) {return $p.Value}
    return $null
}
function Select-MerakiConfigFields {
    param([AllowNull()][object]$Actual,[System.Collections.IDictionary]$Desired)
    $result=[ordered]@{}
    foreach($key in ($Desired.Keys | Sort-Object)) {
        $result[$key]=Get-MerakiConfigFieldValue -Object $Actual -Name $key
    }
    return $result
}
function ConvertTo-MerakiConfigCanonical {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) {return $null}
    if($Value -is [System.Collections.IDictionary]){
        $out=[ordered]@{}
        foreach($key in @($Value.Keys | Sort-Object)){ $out[$key]=ConvertTo-MerakiConfigCanonical $Value[$key] }
        return $out
    }
    if($Value -is [pscustomobject]){
        $out=[ordered]@{}
        foreach($p in @($Value.PSObject.Properties | Sort-Object Name)){ $out[$p.Name]=ConvertTo-MerakiConfigCanonical $p.Value }
        return $out
    }
    if($Value -is [array]){
        $out=@()
        foreach($v in $Value){$out += ,(ConvertTo-MerakiConfigCanonical $v)}
        return ,$out
    }
    return $Value
}
function ConvertTo-MerakiConfigJson {
    param([AllowNull()][object]$Value)
    $canonical=ConvertTo-MerakiConfigCanonical $Value
    ConvertTo-Json -InputObject $canonical -Depth 64 -Compress
}
function Test-MerakiConfigEqual {
    param([AllowNull()][object]$Before,[AllowNull()][object]$Desired)
    return ((ConvertTo-MerakiConfigJson $Before) -ceq (ConvertTo-MerakiConfigJson $Desired))
}
function Get-MerakiConfigFingerprint {
    param([Parameter(Mandatory)][object]$Value)
    $bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-MerakiConfigJson $Value))
    $sha=[Security.Cryptography.SHA256]::Create()
    try {([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}
    finally {$sha.Dispose()}
}
