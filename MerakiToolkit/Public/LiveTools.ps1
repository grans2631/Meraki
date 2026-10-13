# Live Tools jobs are asynchronous. Starting a job does NOT mean it succeeded.
# Cisco: POST /devices/{serial}/liveTools/...; poll GET using returned job ID.
function Start-MerakiDevicePing {
<#
.SYNOPSIS
Enqueue a device-originated ICMP ping job to a target.
.EXAMPLE
Start-MerakiDevicePing -Serial 'QXXX-XXXX-XXXX' -Target '1.1.1.1' -Count 3 -WhatIf
#>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][string]$Target,
        [ValidateRange(1,5)][int]$Count=5,
        [hashtable]$Callback
    )
    $body=@{target=$Target;count=$Count}
    if ($Callback) {$body.callback=$Callback}
    if ($PSCmdlet.ShouldProcess($Serial,"Run live ping to $Target")) {
        Invoke-MerakiApi -Method POST -Path "/devices/$Serial/liveTools/ping" -Body $body
    }
}
function Start-MerakiCableTest {
<#
.SYNOPSIS
Enqueue an MS switch-port cable diagnostic job; availability varies by model.
.EXAMPLE
Start-MerakiCableTest -Serial 'QXXX-XXXX-XXXX' -Ports @('3') -WhatIf
#>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][string[]]$Ports,
        [hashtable]$Callback
    )
    if ($Ports.Count -eq 0) {throw 'At least one port is required.'}
    $body=@{ports=@($Ports | Select-Object -Unique)}
    if ($Callback) {$body.callback=$Callback}
    if ($PSCmdlet.ShouldProcess($Serial,"Start cable test on ports: $($body.ports -join ',')")) {
        Invoke-MerakiApi -Method POST -Path "/devices/$Serial/liveTools/cableTest" -Body $body
    }
}
function Start-MerakiThroughputTest {
<#
.SYNOPSIS
Start a Meraki device-originated throughput test (may consume WAN bandwidth).
.EXAMPLE
Start-MerakiThroughputTest -Serial 'QXXX-XXXX-XXXX' -WhatIf
#>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$Serial,
        [hashtable]$Callback
    )
    $body=@{}
    if ($Callback) {$body.callback=$Callback}
    if ($PSCmdlet.ShouldProcess($Serial,'Start 10-second throughput test (uses bandwidth)')) {
        Invoke-MerakiApi -Method POST -Path "/devices/$Serial/liveTools/throughputTest" -Body $body
    }
}
function Start-MerakiPortCycle {
<#
.SYNOPSIS
Power-cycle specified switch ports (may drop PoE and connectivity).
.EXAMPLE
Start-MerakiPortCycle -Serial 'QXXX-XXXX-XXXX' -Ports @('4') -AllowDisruption -WhatIf
#>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][string[]]$Ports,
        [Parameter(Mandatory)][switch]$AllowDisruption,
        [hashtable]$Callback
    )
    if ($Ports.Count -eq 0) {throw 'At least one port is required.'}
    $body=@{ports=@($Ports | Select-Object -Unique)}
    if ($Callback) {$body.callback=$Callback}
    if ($PSCmdlet.ShouldProcess($Serial,"DISRUPT network/PoE connectivity cycling port(s): $($body.ports -join ',')")) {
        Invoke-MerakiApi -Method POST -Path "/devices/$Serial/liveTools/ports/cycle" -Body $body
    }
}
function Start-MerakiWakeOnLan {
<#
.SYNOPSIS
Enqueue Wake-on-LAN packet targeting a MAC and VLAN from a Meraki device.
.EXAMPLE
Start-MerakiWakeOnLan -Serial 'QXXX-XXXX-XXXX' -VlanId 10 -Mac '00:11:22:33:44:55' -WhatIf
#>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][ValidateRange(1,4094)][int]$VlanId,
        [Parameter(Mandatory)][ValidatePattern('^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$')][string]$Mac,
        [hashtable]$Callback
    )
    $body=@{vlanId=$VlanId;mac=$Mac}
    if ($Callback) {$body.callback=$Callback}
    if ($PSCmdlet.ShouldProcess($Serial,"Send Wake-on-LAN for $Mac on VLAN $VlanId")) {
        Invoke-MerakiApi -Method POST -Path "/devices/$Serial/liveTools/wakeOnLan" -Body $body
    }
}
function Get-MerakiLiveToolResult {
<#
.SYNOPSIS
Retrieve the asynchronous result of a previously enqueued live-tools job.
.EXAMPLE
Get-MerakiLiveToolResult -Serial 'QXXX-XXXX-XXXX' -Tool ping -JobId '1284392014819'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][ValidateSet('ping','cableTest','throughputTest','ports/cycle','wakeOnLan')][string]$Tool,
        [Parameter(Mandatory)][string]$JobId
    )
    $encoded=[uri]::EscapeDataString($JobId)
    Invoke-MerakiApi -Path "/devices/$Serial/liveTools/$Tool/$encoded"
}
function Get-MerakiFailedClientConnections {
<#
.SYNOPSIS
List wireless client association/authentication/DHCP/DNS connection failures.
.EXAMPLE
Get-MerakiFailedClientConnections -NetworkId 'N_123' -Timespan 3600 -Ssid 0
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$NetworkId,
        [ValidateRange(1,604800)][int]$Timespan=86400,
        [ValidateSet('2.4','5','6')][string]$Band,
        [ValidateRange(0,14)][Nullable[int]]$Ssid,
        [string]$ApTag,
        [string]$Serial,
        [string]$ClientId
    )
    $q=@{timespan=$Timespan}
    if ($Band) {$q.band=$Band}
    if ($PSBoundParameters.ContainsKey('Ssid')) {$q.ssid=$Ssid}
    if ($ApTag) {$q.apTag=$ApTag}
    if ($Serial) {$q.serial=$Serial}
    if ($ClientId) {$q.clientId=$ClientId}
    Invoke-MerakiApi -Path "/networks/$NetworkId/wireless/failedConnections" -Query $q
}
