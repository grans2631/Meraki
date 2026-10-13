# Regression tests: the exported help blocks must be unique and discoverable.
# Pure source inspection; no Dashboard API access is required.
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'MerakiToolkit/MerakiToolkit.psd1') -Force -ErrorAction Stop
    $exportNames = @((Get-Command -Module MerakiToolkit -CommandType Function).Name)
    $sourceFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $root 'MerakiToolkit') -Filter '*.ps1' -Recurse -File
    )
}

Describe 'MerakiToolkit comment-based help' {
    It 'exports functions and tests the full module surface' {
        $exportNames.Count | Should -BeGreaterThan 40
    }

    It 'has exactly one adjacent help block per exported function with synopsis and example' {
        $found = @{}
        foreach ($file in $sourceFiles) {
            $source = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors)
            $parseErrors.Count | Should -Be 0
            $definitions = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            },$true)
            foreach ($definition in $definitions) {
                $name = $definition.Name
                if ($name -notin $exportNames) { continue }
                $found[$name] = $true
                $before = $source.Substring(0,$definition.Extent.StartOffset)
                $outer = $null
                $pos = $before.LastIndexOf('<#',[System.StringComparison]::Ordinal)
                if ($pos -ge 0) {
                    $candidate = $before.Substring($pos)
                    if ([regex]::IsMatch($candidate,'\A<#[\s\S]*?#>\s*\z')) {
                        $outer = $candidate
                    }
                }
                $body = $definition.Body.Extent.Text
                $innerMatch = [regex]::Match($body,'\A\{\s*(<#[\s\S]*?#>)')
                $inner = if ($innerMatch.Success) { $innerMatch.Groups[1].Value } else { $null }
                $blocks = @(@($outer,$inner) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                $blocks.Count | Should -Be 1 -Because "$name should have one comment-based help block"
                $blocks[0] | Should -Match '(?m)^\s*\.SYNOPSIS\s*$'
                $blocks[0] | Should -Match '(?m)^\s*\.EXAMPLE\s*$'
            }
        }
        foreach ($name in $exportNames) {
            $found.ContainsKey($name) | Should -BeTrue -Because "$name should be found in module source"
        }
    }

    It 'exposes help synopsis and examples to Get-Help' {
        foreach ($name in $exportNames) {
            $help = Get-Help -Name $name -Full
            [string]$help.Synopsis | Should -Not -BeNullOrEmpty -Because "$name needs a synopsis"
            $examples = @($help.examples.example | Where-Object { $null -ne $_ })
            $examples.Count | Should -BeGreaterThan 0 -Because "$name needs at least one discoverable example"
        }
    }
}
