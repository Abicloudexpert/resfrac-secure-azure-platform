#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Post-deployment smoke tests. Exits non-zero on failure (pipeline gate).

.DESCRIPTION
    Validates the deployed platform end-to-end:
      * API GET /health          -> 200 (liveness)
      * API GET /health/ready     -> 200 (dependencies: SQL + Key Vault reachable)
      * API GET /api/v1/items     -> 401 without a token (authn enforced)
      * (optional) with a client-credentials token -> 200 and returns data
      * Function GET /api/health   -> 200

.EXAMPLE
    ./smoke-test.ps1 -ApiUrl https://app-x.azurewebsites.net -FunctionUrl https://func-x.azurewebsites.net
.EXAMPLE
    # Full auth check using an app-only token (service principal with the app role):
    ./smoke-test.ps1 -ApiUrl ... -TenantId ... -ClientId ... -ClientSecret ... -ApiAudience api://<apiClientId>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ApiUrl,
    [string]$FunctionUrl,
    [int]$TimeoutSec = 20,
    [int]$RetryCount = 10,
    [int]$RetryDelaySec = 15,

    # Optional OAuth2 client-credentials flow to exercise the protected endpoint.
    [string]$TenantId,
    [string]$ClientId,
    # Falls back to the SMOKE_CLIENT_SECRET env var so CI can pass it as a
    # secret (mapped via env, never on the command line / logs).
    [string]$ClientSecret = $env:SMOKE_CLIENT_SECRET,
    [string]$ApiAudience
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/common.psm1" -Force

$failures = 0

function Test-Endpoint {
    param([string]$Name, [string]$Url, [int]$ExpectedStatus, [hashtable]$Headers = @{}, [switch]$Retry)
    $attempts = $Retry ? $RetryCount : 1
    for ($i = 1; $i -le $attempts; $i++) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -Headers $Headers -TimeoutSec $TimeoutSec -SkipHttpErrorCheck
            $status = [int]$resp.StatusCode
            if ($status -eq $ExpectedStatus) {
                Write-Ok "$Name -> $status (expected $ExpectedStatus)"
                return $true
            }
            Write-Warn2 "$Name -> $status (expected $ExpectedStatus) [attempt $i/$attempts]"
        }
        catch {
            Write-Warn2 "$Name -> error: $($_.Exception.Message) [attempt $i/$attempts]"
        }
        if ($i -lt $attempts) { Start-Sleep -Seconds $RetryDelaySec }
    }
    Write-Err "$Name FAILED"
    return $false
}

Write-Step "Smoke testing API at $ApiUrl"
# Warm-up + liveness (retried: app may still be starting after deploy).
if (-not (Test-Endpoint -Name 'API /health' -Url "$ApiUrl/health" -ExpectedStatus 200 -Retry)) { $failures++ }
if (-not (Test-Endpoint -Name 'API /health/ready' -Url "$ApiUrl/health/ready" -ExpectedStatus 200 -Retry)) { $failures++ }
# Protected endpoint must reject anonymous callers.
if (-not (Test-Endpoint -Name 'API /api/v1/items (anonymous)' -Url "$ApiUrl/api/v1/items" -ExpectedStatus 401)) { $failures++ }

# Optional: acquire an app-only token and confirm authorized access works.
if ($TenantId -and $ClientId -and $ClientSecret -and $ApiAudience) {
    Write-Step 'Acquiring OAuth2 client-credentials token'
    try {
        $tokenResp = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body @{
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = "$ApiAudience/.default"
            grant_type    = 'client_credentials'
        }
        $auth = @{ Authorization = "Bearer $($tokenResp.access_token)" }
        # Retried: the first authorized request warms the SQL pool + acquires the
        # Managed Identity token, which can exceed the per-request timeout on a
        # cold instance.
        if (-not (Test-Endpoint -Name 'API /api/v1/items (authorized)' -Url "$ApiUrl/api/v1/items" -ExpectedStatus 200 -Headers $auth -Retry)) { $failures++ }
    }
    catch {
        Write-Err "Token acquisition failed: $($_.Exception.Message)"
        $failures++
    }
}
else {
    Write-Warn2 'Skipping authorized-endpoint check (no client credentials supplied).'
}

if ($FunctionUrl) {
    Write-Step "Smoke testing Function at $FunctionUrl"
    if (-not (Test-Endpoint -Name 'Function /api/health' -Url "$FunctionUrl/api/health" -ExpectedStatus 200 -Retry)) { $failures++ }
}

if ($failures -gt 0) {
    Write-Err "$failures smoke test(s) failed."
    exit 1
}
Write-Step 'All smoke tests passed'
