function Connect-Meraki {
    <#
    .SYNOPSIS
    Authenticate to Cisco Meraki Dashboard API for the current PowerShell process.
    .EXAMPLE
    Connect-Meraki
    .EXAMPLE
    $env:MERAKI_DASHBOARD_API_KEY = 'set-via-a-secret-store'
    Connect-Meraki -UseEnvironment
    #>
    [CmdletBinding(DefaultParameterSetName='Prompt')]
    param(
        [Parameter(ParameterSetName='Plain',Mandatory)][string]$ApiKey,
        [Parameter(ParameterSetName='Secure',Mandatory)][securestring]$SecureApiKey,
        [Parameter(ParameterSetName='Environment',Mandatory)][switch]$UseEnvironment,
        [ValidateRange(0,8)][int]$MaxRetries = 4
    )
    if ($PSCmdlet.ParameterSetName -eq 'Environment') {
        $ApiKey = [Environment]::GetEnvironmentVariable('MERAKI_DASHBOARD_API_KEY')
        if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw 'MERAKI_DASHBOARD_API_KEY is not set.' }
    }
    if ($PSCmdlet.ParameterSetName -eq 'Prompt') {
        $SecureApiKey = Read-Host 'Enter Meraki Dashboard API key' -AsSecureString
    }
    if ($SecureApiKey) {
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureApiKey)
        try { $ApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    }
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw 'API key cannot be blank.' }
    $script:MerakiApiKey = $ApiKey
    $script:MerakiMaxRetries = $MaxRetries
    Get-MerakiConnection
}
function Disconnect-Meraki {
    [CmdletBinding()]param()
    $script:MerakiApiKey = $null
}
function Get-MerakiConnection {
    [CmdletBinding()]param()
    [pscustomobject]@{
        Connected = -not [string]::IsNullOrWhiteSpace($script:MerakiApiKey)
        ApiBase = $script:MerakiApiBase
        MaxRetries = $script:MerakiMaxRetries
        Credential = 'Not displayed'
    }
}
function ConvertTo-MerakiQueryString {
    param([hashtable]$Query)
    if (-not $Query -or $Query.Count -eq 0) { return '' }
    $pairs = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in ($Query.Keys | Sort-Object)) {
        $values = @($Query[$key])
        foreach ($value in $values) {
            if ($null -eq $value) { continue }
            if ($value -is [bool]) { $value = $value.ToString().ToLowerInvariant() }
            $pairs.Add(([uri]::EscapeDataString([string]$key) + '=' + [uri]::EscapeDataString([string]$value)))
        }
    }
    return ($pairs -join '&')
}
function Invoke-MerakiApi {
    <#
    .SYNOPSIS
    Generic Dashboard API v1 request with GET pagination and bounded retry behavior.
    .DESCRIPTION
    Accepts only relative /api/v1 paths; never sends the API key to a supplied remote URL.
    For writes, use high-level ShouldProcess wrappers unless you explicitly intend a raw API call.
    .EXAMPLE
    Invoke-MerakiApi -Path '/organizations'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PUT','DELETE')][string]$Method = 'GET',
        [Parameter(Mandatory)][ValidatePattern('^/')][string]$Path,
        [hashtable]$Query,
        [AllowNull()][object]$Body,
        [switch]$AllPages
    )
    if (-not $script:MerakiApiKey) { throw 'Not connected. Run Connect-Meraki first.' }
    if ($Path -match '^//' -or $Path -match '[?#]' -or $Path -match '(?i)%2f%2f') {
        throw 'Path must be an API-relative path; specify query parameters with -Query.'
    }
    if ($AllPages -and $Method -ne 'GET') { throw '-AllPages requires GET.' }
    $qs = ConvertTo-MerakiQueryString -Query $Query
    $url = $script:MerakiApiBase.TrimEnd('/') + $Path
    if ($qs) { $url += '?' + $qs }
    $headers = @{
        'X-Cisco-Meraki-API-Key' = $script:MerakiApiKey
        'Accept' = 'application/json'
    }
    $json = $null
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $json = ConvertTo-Json -InputObject $Body -Depth 60 -Compress
    }
    $pages = 0
    do {
        $pages++
        if ($pages -gt 1000) { throw 'Pagination safety limit exceeded.' }
        $response = $null
        for ($attempt = 0; $attempt -le $script:MerakiMaxRetries; $attempt++) {
            try {
                $request = @{
                    Uri = $url
                    Method = $Method
                    Headers = $headers
                    UseBasicParsing = $true
                    ErrorAction = 'Stop'
                }
                if ($null -ne $json) {
                    $request.ContentType = 'application/json'
                    $request.Body = $json
                }
                $response = Invoke-WebRequest @request
                break
            }
            catch {
                $code = 0
                if ($_.Exception.Response) {
                    try { $code = [int]$_.Exception.Response.StatusCode } catch { }
                }
                $retryable = ($Method -eq 'GET' -and $code -in @(429,500,502,503,504))
                if (-not $retryable -or $attempt -ge $script:MerakiMaxRetries) {
                    throw ('Meraki API {0} {1} failed (HTTP {2}). {3}' -f $Method, $Path, $code, $_.Exception.Message)
                }
                $delay = [Math]::Min(30,[Math]::Pow(2, $attempt + 1))
                if ($code -eq 429) {
                    try {
                        $retryAfter = [double]$_.Exception.Response.Headers['Retry-After']
                        if ($retryAfter -gt 0) { $delay = [Math]::Min(120,$retryAfter) }
                    } catch { }
                }
                Start-Sleep -Seconds ([int][Math]::Ceiling($delay))
            }
        }
        if ($response.Content -and $response.Content.Trim()) {
            $data = ConvertFrom-Json -InputObject $response.Content
            if ($null -ne $data) { Write-Output $data }
        }
        $next = $null
        if ($AllPages) {
            $links = [string]$response.Headers['Link']
            foreach ($part in ($links -split ',')) {
                if ($part -match '<([^>]+)>;\s*rel="?next"?') {
                    $candidate = [uri]$Matches[1]
                    # No cross-host auth header forwarding through untrusted pagination links.
                    if ($candidate.Scheme -ne 'https' -or $candidate.Host -notmatch '(^|\.)meraki\.com$') {
                        throw 'Refusing unsafe Meraki pagination URL.'
                    }
                    $next = $candidate.AbsoluteUri
                    break
                }
            }
        }
        $url = $next
    } while ($next)
}
function Assert-MerakiSettings {
    param([object]$Settings)
    if ($null -eq $Settings) { throw 'Settings cannot be null.' }
    if ($Settings -is [hashtable] -and $Settings.Count -eq 0) { throw 'Settings cannot be empty.' }
}
