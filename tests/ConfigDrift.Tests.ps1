BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MerakiToolkit/MerakiToolkit.psd1') -Force
}
Describe 'Desired-state drift observe-only monitor' {
    It 'seeds a baseline and emits change events after state transition with no API writes' {
        $state=Join-Path $TestDrive 'drift-baseline.json'
        InModuleScope MerakiToolkit -Parameters @{State=$state} {
            $script:mockDriftMode='baseline'
            Mock Get-MerakiConfigDiff {
                if ($script:mockDriftMode -eq 'baseline') {
                    return [pscustomobject]@{
                        networkId='N_123';templatePath='C:\Lab\assignment.json'
                        changeCount=0;blockedCount=0;fingerprint='clean';changes=@()
                    }
                }
                return [pscustomobject]@{
                    networkId='N_123';templatePath='C:\Lab\assignment.json'
                    changeCount=1;blockedCount=0;fingerprint='dirty'
                    changes=@([pscustomobject]@{Family='wirelessSsids';Identity='0';Action='Update'})
                }
            }
            Mock Invoke-MerakiApi { throw 'No write or raw API call is allowed.' }
            $first=Get-MerakiConfigDrift -Template 'assignment.json' -NetworkId 'N_123' -StatePath $State
            $first.baselineCreated | Should -BeTrue
            $first.transition | Should -Be 'none'
            $first.conformance | Should -Be 'conformant'
            $script:mockDriftMode='drift'
            $second=Get-MerakiConfigDrift -Template 'assignment.json' -NetworkId 'N_123' -StatePath $State
            $second.baselineCreated | Should -BeFalse
            $second.transition | Should -Be 'drift-detected'
            $second.changes.Count | Should -Be 1
            Should -Invoke Invoke-MerakiApi -Times 0
        }
    }
}
