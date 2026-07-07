#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Packages and deploys the Node.js API and Python Function to Azure.

.DESCRIPTION
    Uses zip-deploy with WEBSITE_RUN_FROM_PACKAGE (immutable, atomic deploys):
      * API      : production npm install, zipped, deployed to the Web App.
      * Function : dependencies vendored into .python_packages, zipped, deployed.
    Discovers target resource names from the resource group tags if not supplied.

.EXAMPLE
    ./deploy-apps.ps1 -ResourceGroup rg-resfrac-dev -ApiName <app> -FunctionName <func>
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ApiName,
    [Parameter(Mandatory)][string]$FunctionName,
    [string]$SubscriptionId,
    [switch]$SkipApi,
    [switch]$SkipFunction
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/common.psm1" -Force

$repoRoot = Resolve-Path "$PSScriptRoot/../.."
$apiDir = Join-Path $repoRoot 'apps/api'
$funcDir = Join-Path $repoRoot 'apps/function'
$artifactDir = Join-Path $repoRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

Assert-AzLogin -SubscriptionId $SubscriptionId | Out-Null

# --- API -------------------------------------------------------------------
if (-not $SkipApi) {
    Write-Step "Packaging API ($ApiName)"
    Assert-Tool -Name 'npm' -InstallHint 'Install Node.js 20+.'
    Push-Location $apiDir
    try {
        & npm ci --omit=dev
        if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }
        $apiZip = Join-Path $artifactDir 'api.zip'
        if (Test-Path $apiZip) { Remove-Item $apiZip -Force }
        # Include only runtime files (src + node_modules + package manifests).
        Compress-Archive -Path 'src', 'node_modules', 'package.json', 'package-lock.json' -DestinationPath $apiZip -Force
        Write-Ok "Built $apiZip"
    }
    finally { Pop-Location }

    if ($PSCmdlet.ShouldProcess($ApiName, 'Zip-deploy API')) {
        Write-Step "Deploying API to $ApiName"
        Invoke-Az -Args @('webapp', 'deploy', '-g', $ResourceGroup, '-n', $ApiName,
            '--src-path', (Join-Path $artifactDir 'api.zip'), '--type', 'zip') | Out-Null
        Write-Ok 'API deployed'
    }
}

# --- Function --------------------------------------------------------------
if (-not $SkipFunction) {
    Write-Step "Packaging Function ($FunctionName)"
    Assert-Tool -Name 'python3' -InstallHint 'Install Python 3.11.'
    Push-Location $funcDir
    try {
        $pkgDir = Join-Path $funcDir '.python_packages/lib/site-packages'
        if (Test-Path (Join-Path $funcDir '.python_packages')) { Remove-Item (Join-Path $funcDir '.python_packages') -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $pkgDir | Out-Null
        & python3 -m pip install --target $pkgDir -r requirements.txt
        if ($LASTEXITCODE -ne 0) { throw 'pip install failed' }

        $funcZip = Join-Path $artifactDir 'function.zip'
        if (Test-Path $funcZip) { Remove-Item $funcZip -Force }
        Compress-Archive -Path 'function_app.py', 'host.json', 'requirements.txt', 'shared', '.python_packages' -DestinationPath $funcZip -Force
        Write-Ok "Built $funcZip"
    }
    finally { Pop-Location }

    if ($PSCmdlet.ShouldProcess($FunctionName, 'Zip-deploy Function')) {
        Write-Step "Deploying Function to $FunctionName"
        # Ensure run-from-package, then push the zip.
        Invoke-Az -Args @('functionapp', 'config', 'appsettings', 'set', '-g', $ResourceGroup, '-n', $FunctionName,
            '--settings', 'WEBSITE_RUN_FROM_PACKAGE=1') | Out-Null
        Invoke-Az -Args @('functionapp', 'deployment', 'source', 'config-zip', '-g', $ResourceGroup, '-n', $FunctionName,
            '--src', (Join-Path $artifactDir 'function.zip')) | Out-Null
        Write-Ok 'Function deployed'
    }
}

Write-Step 'Application deployment complete'
