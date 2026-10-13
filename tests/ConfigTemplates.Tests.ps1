BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MerakiToolkit/MerakiToolkit.psd1') -Force
}
Describe 'Meraki desired-state template v1 resolver' {
    BeforeEach {
        $dir=Join-Path $TestDrive 'layers'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        '{"kind":"MerakiConfigLayer","schemaVersion":"1.0","wirelessSsids":[{"number":0,"settings":{"name":"Base","enabled":false}}],"applianceVlans":[{"id":"10","settings":{"name":"Office"}}]}' | Set-Content -LiteralPath (Join-Path $dir 'base.json')
        '{"kind":"MerakiConfigLayer","schemaVersion":"1.0","wirelessSsids":[{"number":0,"settings":{"enabled":true}},{"number":1,"settings":{"name":"Guest"}}],"applianceVlans":[{"id":"10","settings":{"subnet":"192.0.2.0/24"}}]}' | Set-Content -LiteralPath (Join-Path $dir 'overlay.json')
        '{"kind":"MerakiConfigAssignment","schemaVersion":"1.0","networkId":"N_123456789012345678","base":"base.json","overlays":["overlay.json"]}' | Set-Content -LiteralPath (Join-Path $dir 'assignment.json')
    }
    It 'merges overlays by identity and preserves numeric-string network ID' {
        $template=Join-Path $TestDrive 'layers/assignment.json'
        InModuleScope MerakiToolkit -Parameters @{Template=$template} {
            $result=Resolve-MerakiConfigTemplate -Template $Template
            $result.networkId | Should -BeExactly 'N_123456789012345678'
            @($result.settings.wirelessSsids).Count | Should -Be 2
            $result.settings.wirelessSsids[0].settings.name | Should -Be 'Base'
            $result.settings.wirelessSsids[0].settings.enabled | Should -BeTrue
            $result.settings.applianceVlans[0].settings.subnet | Should -Be '192.0.2.0/24'
        }
    }
    It 'refuses unsupported SSID secret changes' {
        $file=Join-Path $TestDrive 'layers/overlay.json'
        '{"kind":"MerakiConfigLayer","schemaVersion":"1.0","wirelessSsids":[{"number":0,"settings":{"psk":"plaintext"}}]}' | Set-Content -LiteralPath $file
        $template=Join-Path $TestDrive 'layers/assignment.json'
        InModuleScope MerakiToolkit -Parameters @{Template=$template} {
            { Resolve-MerakiConfigTemplate -Template $Template } | Should -Throw '*Unsupported template field*'
        }
    }
    It 'refuses unversioned configurations' {
        $file=Join-Path $TestDrive 'layers/base.json'
        '{"kind":"MerakiConfigLayer","schemaVersion":"2.0"}' | Set-Content -LiteralPath $file
        $template=Join-Path $TestDrive 'layers/assignment.json'
        InModuleScope MerakiToolkit -Parameters @{Template=$template} {
            { Resolve-MerakiConfigTemplate -Template $Template } | Should -Throw '*schemaVersion*'
        }
    }
    It 'rejects duplicate keyed entries within a single layer' {
        $file=Join-Path $TestDrive 'layers/base.json'
        '{"kind":"MerakiConfigLayer","schemaVersion":"1.0","applianceVlans":[{"id":"10","settings":{"name":"A"}},{"id":"10","settings":{"name":"B"}}]}' | Set-Content -LiteralPath $file
        $template=Join-Path $TestDrive 'layers/assignment.json'
        InModuleScope MerakiToolkit -Parameters @{Template=$template} {
            { Resolve-MerakiConfigTemplate -Template $Template } | Should -Throw '*Duplicate*'
        }
    }
}
