<#
.SYNOPSIS
    Shared helpers for the ResFrac provisioning/deployment scripts.
    Cross-platform PowerShell (pwsh 7+). Wraps the Azure CLI for idempotent,
    well-logged operations.
#>

Set-StrictMode -Version Latest

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "    [ok] $Message" -ForegroundColor Green }
function Write-Warn2 { param([string]$Message) Write-Host "    [warn] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "    [error] $Message" -ForegroundColor Red }

function Assert-Tool {
    param([Parameter(Mandatory)][string]$Name, [string]$InstallHint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required tool '$Name' not found on PATH. $InstallHint"
    }
}

function Assert-AzLogin {
    <# Ensures an active Azure CLI session and optionally selects a subscription. #>
    param([string]$SubscriptionId)
    Assert-Tool -Name 'az' -InstallHint 'Install: https://learn.microsoft.com/cli/azure/install-azure-cli'
    $acct = az account show 2>$null | ConvertFrom-Json
    if (-not $acct) { throw "Not logged in to Azure. Run 'az login' first." }
    if ($SubscriptionId) {
        az account set --subscription $SubscriptionId | Out-Null
        $acct = az account show | ConvertFrom-Json
    }
    Write-Ok "Azure subscription: $($acct.name) ($($acct.id))"
    return $acct
}

function Invoke-Az {
    <# Runs an az command (array of args), throws on non-zero exit, returns stdout. #>
    param([Parameter(Mandatory)][string[]]$Args, [switch]$AllowFailure)
    $output = & az @Args 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        throw "az $($Args -join ' ') failed (exit $LASTEXITCODE):`n$output"
    }
    return $output
}

function Get-CurrentPrincipalObjectId {
    <# Returns the object id of the signed-in user OR the executing service principal. #>
    $acct = az account show | ConvertFrom-Json
    if ($acct.user.type -eq 'servicePrincipal') {
        $appId = $acct.user.name
        $sp = az ad sp show --id $appId 2>$null | ConvertFrom-Json
        if ($sp) { return $sp.id }
    }
    $me = az ad signed-in-user show 2>$null | ConvertFrom-Json
    if ($me) { return $me.id }
    throw "Unable to resolve the current principal's object id."
}

function Get-DeploymentOutputs {
    <# Returns a hashtable of a completed resource-group deployment's outputs. #>
    param([Parameter(Mandatory)][string]$ResourceGroup, [Parameter(Mandatory)][string]$DeploymentName)
    $json = az deployment group show -g $ResourceGroup -n $DeploymentName --query properties.outputs | ConvertFrom-Json
    $result = @{}
    foreach ($p in $json.PSObject.Properties) { $result[$p.Name] = $p.Value.value }
    return $result
}

function Get-DefaultResourceGroupName {
    param([Parameter(Mandatory)][string]$Workload, [Parameter(Mandatory)][string]$Environment)
    return "rg-$Workload-$Environment"
}

Export-ModuleMember -Function *
