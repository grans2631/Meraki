BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MerakiToolkit/MerakiToolkit.psd1') -Force
}
Describe 'Read-only network desired-state diffs' {
    It 'reports an SSID change and does not call write commands' {
        $dir=Join-Path $TestDrive 'diff'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        '{"kind":"MerakiConfigLayer","schemaVersion":"1.0","wirelessSsids":[{"number":0,"settings":{"name":"LabSSID","enabled":true}}]}' | Set-Content -LiteralPath (Join-Path $dir 'base.json')
        '{"kind":"MerakiConfigAssignment","schemaVersion":"1.0","networkId":"N_456","base":"base.json"}' | Set-Content -LiteralPath (Join-Path $dir 'assignment.json')
        $template=Join-Path $dir 'assignment.json'
        InModuleScope MerakiToolkit -Parameters @{Template=$template} {
            Mock Get-MerakiNetwork { [pscustomobject]@{id='N_456';productTypes=@('wireless')} }
            Mock Get-MerakiWirelessSsid { [pscustomobject]@{number=0;name='OldSSID';enabled=$true} }
            Mock Invoke-MerakiApi { throw 'Should never invoke raw API directly in this mocked diff.' }
            $result=Get-MerakiConfigDiff -Template $Template -NetworkId 'N_456'
            $result.changeCount | Should -Be 1
            $result.changes[0].Family | Should -Be 'wirelessSsids'
            $result.changes[0].Before.name | Should -Be 'OldSSID'
            $result.changes[0].Desired.name | Should -Be 'LabSSID'
            $result.fingerprint.Length | Should -Be 64
            Should -Invoke Invoke-MerakiApi -Times 0
        }
    }
    It 'blocks missing VLAN creation instead of treating it as a safe write' {
        $dir=Join-Path $TestDrive 'vlan'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        '{"kind":"MerakiConfigLayer","schemaVersion":"1.0","applianceVlans":[{"id":"10","settings":{"name":"Lab"}}]}' | Set-Content -LiteralPath (Join-Path $dir 'base.json')
        '{"kind":"MerakiConfigAssignment","schemaVersion":"1.0","networkId":"N_456","base":"base.json"}' | Set-Content -LiteralPath (Join-Path $dir 'assignment.json')
        $template=Join-Path $dir 'assignment.json'
        InModuleScope MerakiToolkit -Parameters @{Template=$template} {
            Mock Get-MerakiNetwork { [pscustomobject]@{id='N_456';productTypes=@('appliance')} }
            Mock Get-MerakiApplianceVlan { @() }
            $result=Get-MerakiConfigDiff -Template $Template -NetworkId 'N_456'
            $result.canApply | Should -BeFalse
            $result.changes[0].Action | Should -Be 'Blocked'
        }
    }
    It 'compares firewall rule order and canonical object property ordering' {
        InModuleScope MerakiToolkit {
            $a=@(@{srcCidr='any';policy='allow'},@{srcCidr='10.0.0.0/8';policy='deny'})
            $b=@(@{policy='allow';srcCidr='any'},@{policy='deny';srcCidr='10.0.0.0/8'})
            (Test-MerakiConfigEqual $a $b) | Should -BeTrue
            (Test-MerakiConfigEqual $a @($b[1],$b[0])) | Should -BeFalse
        }
    }
}
