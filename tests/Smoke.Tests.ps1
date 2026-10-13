# Offline test suite: no API credentials or customer network calls.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $root 'MerakiToolkit/MerakiToolkit.psd1'
$moduleFiles = @(Get-ChildItem -Path (Join-Path $root 'MerakiToolkit') -Include '*.ps1','*.psm1' -File -Recurse)
foreach ($file in $moduleFiles) {
    $tokens=$null
    $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) { throw "Parse errors in $($file.Name): $($errors -join '; ')" }
}
Import-Module $modulePath -Force -ErrorAction Stop
$expected = @('Connect-Meraki','Get-MerakiDevice','Get-MerakiDashboard','Get-MerakiDeploymentPlan',
    'Invoke-MerakiDeployment','Set-MerakiFirmwareUpgrade','Restart-MerakiDevice','Add-MerakiOrganizationInventory')
foreach ($cmd in $expected) {
    if (-not (Get-Command $cmd -Module MerakiToolkit -ErrorAction SilentlyContinue)) {
        throw "Missing command: $cmd"
    }
}
foreach ($ex in @('full-site.json','ms-mr-existing.json','mr-only-existing.json')) {
    $path = Join-Path $root "MerakiToolkit/examples/$ex"
    $plan = Get-MerakiDeploymentPlan -ManifestPath $path
    if (-not $plan.OrganizationId -or $plan.Actions.Count -lt 2) { throw "Invalid plan $ex" }
    $preview = Invoke-MerakiDeployment -ManifestPath $path -WhatIf
    if (-not $preview -or $preview.OrganizationId -ne $plan.OrganizationId) { throw "Invalid WhatIf $ex" }
}
$badPath = Join-Path ([IO.Path]::GetTempPath()) ('meraki-invalid-' + [guid]::NewGuid() + '.json')
try {
    '{"organizationId":"a","network":{"name":"x","productTypes":["wireless"]},"devices":[{"serial":"A","productType":"wireless"},{"serial":"A","productType":"wireless"}]}' |
        Set-Content -LiteralPath $badPath
    $thrown = $false
    try { Get-MerakiDeploymentPlan -ManifestPath $badPath | Out-Null } catch { $thrown = $true }
    if (-not $thrown) { throw 'Duplicate serial validation did not reject invalid manifest.' }
} finally { Remove-Item -LiteralPath $badPath -ErrorAction SilentlyContinue }
Write-Output ("PASS: Imported MerakiToolkit. {0} exported commands. Examples validated." -f (Get-Command -Module MerakiToolkit).Count)
