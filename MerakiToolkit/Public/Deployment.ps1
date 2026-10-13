# Declarative MX / MS / MR deployment. Explicit review first; no writes in planning mode.
function ConvertTo-MerakiHashtable {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [valuetype]) { return $Value }
    if ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject]) {
        $table = @{}
        $items = if ($Value -is [System.Collections.IDictionary]) { $Value.Keys } else { $Value.PSObject.Properties.Name }
        foreach ($key in $items) {
            $v = if ($Value -is [System.Collections.IDictionary]) { $Value[$key] } else { $Value.$key }
            $table[[string]$key] = ConvertTo-MerakiHashtable $v
        }
        return $table
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $result = @()
        foreach ($item in $Value) { $result += ,(ConvertTo-MerakiHashtable $item) }
        return ,$result
    }
    return $Value
}
function Resolve-MerakiManifestSetting {
    param([AllowNull()][object]$Value)
    if ($Value -is [string] -and $Value -match '^ENV:([A-Za-z_][A-Za-z0-9_]*)$') {
        $name = $Matches[1]
        $secret = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrEmpty($secret)) { throw "Required environment variable '$name' is not set." }
        return $secret
    }
    if ($Value -is [hashtable]) {
        $v = @{}
        foreach ($key in $Value.Keys) { $v[$key] = Resolve-MerakiManifestSetting $Value[$key] }
        return $v
    }
    if ($Value -is [array]) {
        $result = @()
        foreach ($item in $Value) { $result += ,(Resolve-MerakiManifestSetting $item) }
        return ,$result
    }
    return $Value
}
function Read-MerakiManifest {
    param([Parameter(Mandatory)][string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Manifest not found: $ManifestPath" }
    $raw = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop
    $manifest = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
    if (-not $manifest.organizationId) { throw 'Missing organizationId.' }
    if (-not $manifest.network) { throw 'Missing network object.' }
    if (-not $manifest.network.existingNetworkId -and -not $manifest.network.name) {
        throw 'Specify network.name or network.existingNetworkId.'
    }
    $types = @($manifest.network.productTypes)
    if (-not $types.Count -or ($types | Where-Object { $_ -notin @('appliance','switch','wireless') })) {
        throw 'network.productTypes must contain one or more of appliance, switch, wireless.'
    }
    $serials = @()
    foreach ($d in @($manifest.devices | Where-Object { $null -ne $_ })) {
        if (-not $d.serial -or -not $d.productType) { throw 'Each device requires serial and productType.' }
        if ($d.productType -notin $types) { throw "Device $($d.serial) type $($d.productType) is not selected." }
        $serials += [string]$d.serial
    }
    if (@($serials | Select-Object -Unique).Count -ne $serials.Count) { throw 'Duplicate device serial in manifest.' }
    if ($manifest.mx -and 'appliance' -notin $types) { throw 'MX config requires appliance product type.' }
    if ($manifest.ms -and 'switch' -notin $types) { throw 'MS config requires switch product type.' }
    if ($manifest.mr -and 'wireless' -notin $types) { throw 'MR config requires wireless product type.' }
    foreach ($s in @($manifest.mr.ssids | Where-Object { $null -ne $_ })) {
        if ($null -eq $s.number -or [int]$s.number -lt 0 -or [int]$s.number -gt 14 -or -not $s.settings) {
            throw 'Each SSID needs number 0-14 and settings.'
        }
    }
    foreach ($p in @($manifest.ms.ports | Where-Object { $null -ne $_ })) {
        if (-not $p.serial -or -not $p.portId -or -not $p.settings) {
            throw 'Each MS port needs serial, portId and settings.'
        }
    }
    return $manifest
}
<#
.SYNOPSIS
Validate a site manifest and return a no-write action plan.
.EXAMPLE
Get-MerakiDeploymentPlan -ManifestPath '.\MerakiToolkit\examples\full-site.json'
#>
function Get-MerakiDeploymentPlan {
    <#
    .SYNOPSIS
    Validate the JSON manifest and produce a readable NO-WRITES deployment plan.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ManifestPath)
    $m = Read-MerakiManifest -ManifestPath $ManifestPath
    $steps = New-Object 'System.Collections.Generic.List[string]'
    if (-not $m.network.existingNetworkId) { $steps.Add('Create new network') }
    else { $steps.Add('Use existing network (verify organization and products)') }
    if ($m.claimToInventory) { $steps.Add('Claim missing serials into organization inventory') }
    foreach ($d in @($m.devices | Where-Object { $null -ne $_ })) {
        $steps.Add(("Assign/verify {0} {1}; update name if provided" -f $d.productType,$d.serial))
    }
    foreach ($v in @($m.mx.vlans | Where-Object { $null -ne $_ })) {
        $steps.Add(("Create/update MX VLAN {0}" -f $v.id))
    }
    foreach ($p in @($m.ms.ports | Where-Object { $null -ne $_ })) {
        $steps.Add(("Configure MS port {0}/{1}" -f $p.serial,$p.portId))
    }
    foreach ($s in @($m.mr.ssids | Where-Object { $null -ne $_ })) {
        $steps.Add(("Configure MR SSID {0}" -f $s.number))
    }
    if ($m.mx.firewallRules) { $steps.Add('REPLACE entire MX L3 firewall rule set (disruptive)') }
    if ($m.mx.vpn) { $steps.Add('REPLACE MX site-to-site VPN configuration (disruptive)') }
    [pscustomobject]@{
        ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path
        OrganizationId = $m.organizationId
        NetworkName = $m.network.name
        ExistingNetworkId = $m.network.existingNetworkId
        ProductTypes = @($m.network.productTypes)
        DeviceCount = @($m.devices | Where-Object { $null -ne $_ }).Count
        Actions = @($steps.ToArray())
        Warnings = @(
            'Planning does not verify Meraki live state. Changes are not atomic.',
            'Physical WAN connectivity, licensing, and local uplink bootstrap may still be required.',
            'Do not store Wi-Fi secrets or API keys in Git. Use ENV:NAME references.'
        )
    }
}
<#
.SYNOPSIS
Deploy the manifest after explicit approval; -WhatIf leaves the network unchanged.
.EXAMPLE
Invoke-MerakiDeployment -ManifestPath '.\MerakiToolkit\examples\full-site.json' -WhatIf
#>
function Invoke-MerakiDeployment {
    <#
    .SYNOPSIS
    Apply modular Meraki site configuration after explicit approval.
    .EXAMPLE
    Invoke-MerakiDeployment -ManifestPath .\site.json -WhatIf
    .EXAMPLE
    Invoke-MerakiDeployment -ManifestPath .\site.json -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [switch]$AllowDisruptiveChanges
    )
    $plan = Get-MerakiDeploymentPlan -ManifestPath $ManifestPath
    if (-not $PSCmdlet.ShouldProcess($plan.OrganizationId,("Apply {0}-operation Meraki deployment" -f $plan.Actions.Count))) {
        return $plan
    }
    $m = Read-MerakiManifest -ManifestPath $ManifestPath
    if (($m.mx.firewallRules -or $m.mx.vpn) -and -not $AllowDisruptiveChanges) {
        throw 'Firewall/VPN replacement requires -AllowDisruptiveChanges.'
    }
    $log = New-Object 'System.Collections.Generic.List[string]'
    $networkId = [string]$m.network.existingNetworkId
    try {
        if ($networkId) {
            $network = Get-MerakiNetwork -NetworkId $networkId
            if ([string]$network.organizationId -ne [string]$m.organizationId) { throw 'Existing network is in a different organization.' }
            foreach ($t in @($m.network.productTypes)) {
                if ($t -notin @($network.productTypes)) { throw "Existing network does not support $t." }
            }
        } else {
            $matches = @(Get-MerakiNetwork -OrganizationId $m.organizationId | Where-Object name -eq $m.network.name)
            if ($matches.Count -gt 0) { throw 'A network with this name already exists. Set existingNetworkId to explicitly use it.' }
            $newParams = @{OrganizationId=$m.organizationId;Name=$m.network.name;ProductTypes=@($m.network.productTypes);Confirm=$false}
            if ($m.network.timeZone) { $newParams.TimeZone=[string]$m.network.timeZone }
            $network = New-MerakiNetwork @newParams
            $networkId = $network.id
            $log.Add("Created network: $networkId")
        }
        $inventory = @(Get-MerakiInventory -OrganizationId $m.organizationId)
        $orgInventory = @{}
        foreach ($i in $inventory) { $orgInventory[[string]$i.serial] = $i }
        $missing = @()
        foreach ($d in @($m.devices | Where-Object { $null -ne $_ })) {
            if (-not $orgInventory.ContainsKey([string]$d.serial)) { $missing += [string]$d.serial }
        }
        if ($missing.Count -gt 0) {
            if (-not $m.claimToInventory) {
                throw ('Serial(s) not in organization inventory: ' + ($missing -join ', ') + '. Set claimToInventory:true only with authorization.')
            }
            Add-MerakiOrganizationInventory -OrganizationId $m.organizationId -Serials $missing -Confirm:$false | Out-Null
            $log.Add(("Claimed {0} serial(s) to org" -f $missing.Count))
        }
        foreach ($d in @($m.devices | Where-Object { $null -ne $_ })) {
            $serial = [string]$d.serial
            $old = $orgInventory[$serial]
            if ($old -and $old.networkId -and [string]$old.networkId -ne [string]$networkId) {
                throw "Serial $serial belongs to another network: $($old.networkId). Manual reassignment required."
            }
            if (-not $old -or -not $old.networkId) {
                Add-MerakiNetworkDevice -NetworkId $networkId -Serials @($serial) -Confirm:$false | Out-Null
                $log.Add("Assigned serial: $serial")
            }
            if ($d.name) {
                Set-MerakiDevice -Serial $serial -Settings @{name=[string]$d.name} -Confirm:$false | Out-Null
                $log.Add("Updated device name: $serial")
            }
        }
        if ($m.mx.vlans) {
            # VLAN mode must already be enabled. Never flip appliance LAN mode silently.
            $existingVlans = @(Get-MerakiApplianceVlan -NetworkId $networkId)
            $ids = @{}
            foreach ($v in $existingVlans) { $ids[[string]$v.id]=$true }
            foreach ($v in $m.mx.vlans) {
                $body = Resolve-MerakiManifestSetting (ConvertTo-MerakiHashtable $v)
                $vlan = [string]$body.id
                if ($ids.ContainsKey($vlan)) {
                    Set-MerakiApplianceVlan -NetworkId $networkId -VlanId $vlan -Settings $body -Confirm:$false | Out-Null
                } else {
                    New-MerakiApplianceVlan -NetworkId $networkId -Settings $body -Confirm:$false | Out-Null
                }
                $log.Add("Configured MX VLAN: $vlan")
            }
        }
        foreach ($p in @($m.ms.ports | Where-Object { $null -ne $_ })) {
            $body = Resolve-MerakiManifestSetting (ConvertTo-MerakiHashtable $p.settings)
            Set-MerakiSwitchPort -Serial $p.serial -PortId $p.portId -Settings $body -Confirm:$false | Out-Null
            $log.Add("Configured MS port: $($p.serial)/$($p.portId)")
        }
        foreach ($s in @($m.mr.ssids | Where-Object { $null -ne $_ })) {
            $body = Resolve-MerakiManifestSetting (ConvertTo-MerakiHashtable $s.settings)
            Set-MerakiWirelessSsid -NetworkId $networkId -Number ([int]$s.number) -Settings $body -Confirm:$false | Out-Null
            $log.Add("Configured MR SSID: $($s.number)")
        }
        if ($m.mx.firewallRules) {
            $rules = Resolve-MerakiManifestSetting (ConvertTo-MerakiHashtable @($m.mx.firewallRules))
            Set-MerakiFirewallRules -NetworkId $networkId -Rules @($rules) -Confirm:$false | Out-Null
            $log.Add('Replaced MX L3 firewall rules')
        }
        if ($m.mx.vpn) {
            $vpn = Resolve-MerakiManifestSetting (ConvertTo-MerakiHashtable $m.mx.vpn)
            Set-MerakiVpnConfiguration -NetworkId $networkId -Settings $vpn -Confirm:$false | Out-Null
            $log.Add('Replaced MX VPN settings')
        }
        [pscustomobject]@{
            Result='Completed'
            NetworkId=$networkId
            OrganizationId=$m.organizationId
            Operations=@($log.ToArray())
            Warning='Review device health and connectivity; this operation is not transactional.'
        }
    } catch {
        throw ("Deployment halted for network '{0}' after {1} completed operations. No automatic rollback. Reason: {2}" -f $networkId,$log.Count,$_.Exception.Message)
    }
}
