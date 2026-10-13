BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MerakiToolkit/MerakiToolkit.psd1') -Force
}
Describe 'Fail-closed desired-state apply gates' {
    It 'rejects execution with no approved fingerprint and performs zero writes' {
        $change=[pscustomobject]@{Family='wirelessSsids';Identity='0';Action='Update';Before=@{name='Old'};Desired=@{name='New'}}
        InModuleScope MerakiToolkit -Parameters @{Change=$change} {
            Mock Get-MerakiConfigDiff { [pscustomobject]@{networkId='N_123';changeCount=1;canApply=$true;blockedCount=0;fingerprint='expectedhash';changes=@($Change)} }
            Mock Export-MerakiNetworkConfig {throw 'Snapshot must never be attempted'}
            Mock Set-MerakiWirelessSsid {throw 'Write must never occur'}
            { Invoke-MerakiConfigTemplate -Template 'placeholder.json' -NetworkId 'N_123' -Approve -ApprovedFingerprint 'wrong' -Confirm:$false } | Should -Throw '*No approved matching diff*'
            Should -Invoke Export-MerakiNetworkConfig -Times 0
            Should -Invoke Set-MerakiWirelessSsid -Times 0
        }
    }
    It 'previews a change under WhatIf without exporting or applying' {
        $change=[pscustomobject]@{Family='wirelessSsids';Identity='0';Action='Update';Before=@{name='Old'};Desired=@{name='New'}}
        InModuleScope MerakiToolkit -Parameters @{Change=$change} {
            Mock Get-MerakiConfigDiff { [pscustomobject]@{networkId='N_123';changeCount=1;canApply=$true;blockedCount=0;fingerprint='expectedhash';changes=@($Change)} }
            Mock Export-MerakiNetworkConfig {throw 'No snapshot should be written during WhatIf'}
            Mock Set-MerakiWirelessSsid {throw 'No Meraki change permitted during WhatIf'}
            $plan=Invoke-MerakiConfigTemplate -Template 'placeholder.json' -NetworkId 'N_123' -WhatIf
            $plan.fingerprint | Should -BeExactly 'expectedhash'
            Should -Invoke Export-MerakiNetworkConfig -Times 0
            Should -Invoke Set-MerakiWirelessSsid -Times 0
        }
    }
    It 'halts when no full snapshot can be produced; makes zero configuration writes' {
        $change=[pscustomobject]@{Family='wirelessSsids';Identity='0';Action='Update';Before=@{name='Old'};Desired=@{name='New'}}
        $snapshot=Join-Path $TestDrive 'pre-apply.json'
        InModuleScope MerakiToolkit -Parameters @{Change=$change;Snapshot=$snapshot} {
            Mock Get-MerakiConfigDiff { [pscustomobject]@{networkId='N_123';changeCount=1;canApply=$true;blockedCount=0;fingerprint='expectedhash';changes=@($Change)} }
            Mock Export-MerakiNetworkConfig {
                '{"network":{"id":"N_123"}}' | Set-Content -LiteralPath $Path
                Get-Item -LiteralPath $Path
            }
            Mock Set-MerakiWirelessSsid {throw 'Write must not run with incomplete snapshot'}
            { Invoke-MerakiConfigTemplate -Template 'placeholder.json' -NetworkId 'N_123' -Approve -ApprovedFingerprint 'expectedhash' -SnapshotPath $Snapshot -Confirm:$false } | Should -Throw '*Snapshot incomplete*'
            Should -Invoke Export-MerakiNetworkConfig -Times 1
            Should -Invoke Set-MerakiWirelessSsid -Times 0
        }
    }
}
