# Pester 5 isolated unit tests for pure, no-network functions.
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'MerakiToolkit/MerakiToolkit.psd1') -Force -ErrorAction Stop
}
Describe 'MerakiToolkit pure helpers' {
    Context 'Manifest validation' {
        It 'accepts a minimal MR-only manifest' {
            $manifest = @'
{"organizationId":"ORG_TEST","network":{"name":"Test Lab","productTypes":["wireless"]},"devices":[{"serial":"QXXX-1111-1111","productType":"wireless"}]}
'@
            $path = Join-Path $TestDrive 'valid.json'
            $manifest | Set-Content -LiteralPath $path
            InModuleScope MerakiToolkit -Parameters @{ManifestPath=$path} {
                $m = Read-MerakiManifest -ManifestPath $ManifestPath
                $m.organizationId | Should -Be 'ORG_TEST'
                @($m.devices).Count | Should -Be 1
            }
        }
        It 'rejects duplicate device serials' {
            $manifest = @'
{"organizationId":"ORG_TEST","network":{"name":"Test Lab","productTypes":["wireless"]},"devices":[{"serial":"QXXX-1111-1111","productType":"wireless"},{"serial":"QXXX-1111-1111","productType":"wireless"}]}
'@
            $path = Join-Path $TestDrive 'duplicate.json'
            $manifest | Set-Content -LiteralPath $path
            InModuleScope MerakiToolkit -Parameters @{ManifestPath=$path} {
                { Read-MerakiManifest -ManifestPath $ManifestPath } | Should -Throw '*Duplicate device serial*'
            }
        }
        It 'rejects device types absent from declared network types' {
            $manifest = @'
{"organizationId":"ORG_TEST","network":{"name":"Test Lab","productTypes":["wireless"]},"devices":[{"serial":"QXXX-1111-1111","productType":"switch"}]}
'@
            $path = Join-Path $TestDrive 'mismatch.json'
            $manifest | Set-Content -LiteralPath $path
            InModuleScope MerakiToolkit -Parameters @{ManifestPath=$path} {
                { Read-MerakiManifest -ManifestPath $ManifestPath } | Should -Throw '*not selected*'
            }
        }
        It 'accepts camera and sensor product families' {
            $manifest = @'
{"organizationId":"ORG_TEST","network":{"name":"Test Lab","productTypes":["camera","sensor"]},"devices":[{"serial":"QXXX-1111-1111","productType":"camera"}]}
'@
            $path = Join-Path $TestDrive 'camera.json'
            $manifest | Set-Content -LiteralPath $path
            InModuleScope MerakiToolkit -Parameters @{ManifestPath=$path} {
                $m=Read-MerakiManifest -ManifestPath $ManifestPath
                @($m.network.productTypes).Count | Should -Be 2
            }
        }
    }
    Context 'Query string generation' {
        It 'URL encodes values and orders keys consistently' {
            InModuleScope MerakiToolkit {
                $actual = ConvertTo-MerakiQueryString -Query @{z='a b/c';a='x&y'}
                $actual | Should -Be 'a=x%26y&z=a%20b%2Fc'
            }
        }
        It 'expands array query parameters and lowercases booleans' {
            InModuleScope MerakiToolkit {
                $actual = ConvertTo-MerakiQueryString -Query @{networkIds=@('N_1','N_2');all=$true}
                $actual | Should -Be 'all=true&networkIds=N_1&networkIds=N_2'
            }
        }
        It 'omits null values without returning a trailing separator' {
            InModuleScope MerakiToolkit {
                (ConvertTo-MerakiQueryString -Query @{foo=$null;count=2}) | Should -Be 'count=2'
            }
        }
    }
    Context 'Redaction' {
        It 'redacts nested API keys, passwords, sharedSecret, and PSKs' {
            InModuleScope MerakiToolkit {
                $obj = @{
                    auth = @{apiKey='test-key';password='p@ss';nested=@{sharedSecret='secret'}}
                    wifi = [pscustomobject]@{psk='test-psk';name='Guest'}
                    subnet='192.0.2.0/24'
                }
                $actual = ConvertTo-MerakiSafeValue $obj
                $actual.auth.apiKey | Should -Be '[REDACTED]'
                $actual.auth.password | Should -Be '[REDACTED]'
                $actual.auth.nested.sharedSecret | Should -Be '[REDACTED]'
                $actual.wifi.psk | Should -Be '[REDACTED]'
                $actual.wifi.name | Should -Be 'Guest'
                $actual.subnet | Should -Be '192.0.2.0/24'
            }
        }
        It 'redacts secret fields in arrays of objects' {
            InModuleScope MerakiToolkit {
                $obj = @{devices=@([pscustomobject]@{name='A';token='do-not-show'})}
                $actual = ConvertTo-MerakiSafeValue $obj
                $actual.devices[0].token | Should -Be '[REDACTED]'
                $actual.devices[0].name | Should -Be 'A'
            }
        }
    }
}
