#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Provisions the full ResFrac Azure platform for an environment.

.DESCRIPTION
    Idempotent end-to-end infrastructure provisioning:
      1. Ensures the resource group exists.
      2. Deploys the Bicep stack (main.bicep + <env>.bicepparam) with overrides.
      3. Grants the deploying principal 'Key Vault Secrets Officer' and seeds the
         demonstration secret (secret values live OUTSIDE source/IaC by design).
      4. Applies the SQL schema and grants the API managed identity a
         least-privilege contained database user (passwordless, via AAD).

    Safe to re-run: every step is guarded / idempotent.

.EXAMPLE
    ./provision.ps1 -Environment dev -Location eastus2 `
        -ApiClientId <guid> -SqlAdminObjectId <guid> -SqlAdminLogin 'sg-resfrac-sql-admins' `
        -AlertEmail platform-alerts@contoso.com

.NOTES
    Requires: az CLI (logged in), and (for the SQL step) sqlcmd (go-sqlcmd).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('dev', 'test', 'prod')][string]$Environment = 'dev',
    [string]$Location = 'eastus2',
    [string]$Workload = 'resfrac',
    [string]$ResourceGroup,
    [string]$SubscriptionId,

    [Parameter(Mandatory)][string]$ApiClientId,
    [Parameter(Mandatory)][string]$SqlAdminObjectId,
    [Parameter(Mandatory)][string]$SqlAdminLogin,
    [ValidateSet('User', 'Group', 'Application')][string]$SqlAdminPrincipalType = 'Group',

    [string]$AlertEmail = '',
    [string]$DemoSecretName = 'api-feature-flag',
    [string]$DemoSecretValue = 'enabled',
    [switch]$SkipSql
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/common.psm1" -Force

$bicepDir = Resolve-Path "$PSScriptRoot/../bicep"
$sqlDir = Resolve-Path "$PSScriptRoot/../sql"
if (-not $ResourceGroup) { $ResourceGroup = Get-DefaultResourceGroupName -Workload $Workload -Environment $Environment }
$deploymentName = "resfrac-$Environment-$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Step "Provisioning environment '$Environment' into resource group '$ResourceGroup' ($Location)"
$acct = Assert-AzLogin -SubscriptionId $SubscriptionId

# --- 1. Resource group -----------------------------------------------------
Write-Step 'Ensuring resource group'
if ($PSCmdlet.ShouldProcess($ResourceGroup, 'Create resource group')) {
    Invoke-Az -Args @('group', 'create', '-n', $ResourceGroup, '-l', $Location, '--tags', "workload=$Workload", "environment=$Environment") | Out-Null
    Write-Ok "Resource group ready"
}

# --- 2. Bicep deployment ---------------------------------------------------
Write-Step 'Deploying infrastructure (Bicep)'
$paramFile = Join-Path $bicepDir "params/$Environment.bicepparam"
$deployArgs = @(
    'deployment', 'group', 'create',
    '-g', $ResourceGroup,
    '-n', $deploymentName,
    '-f', (Join-Path $bicepDir 'main.bicep'),
    '-p', $paramFile,
    '-p', "location=$Location",
    '-p', "apiClientId=$ApiClientId",
    '-p', "sqlAdminObjectId=$SqlAdminObjectId",
    '-p', "sqlAdminLogin=$SqlAdminLogin",
    '-p', "sqlAdminPrincipalType=$SqlAdminPrincipalType",
    '-p', "alertEmail=$AlertEmail"
)
if ($PSCmdlet.ShouldProcess($ResourceGroup, 'Deploy Bicep stack')) {
    Invoke-Az -Args $deployArgs | Out-Null
    Write-Ok "Deployment '$deploymentName' complete"
}

$outputs = Get-DeploymentOutputs -ResourceGroup $ResourceGroup -DeploymentName $deploymentName
Write-Ok "API:      $($outputs.apiUrl)"
Write-Ok "Function: $($outputs.functionUrl)"
Write-Ok "KeyVault: $($outputs.keyVaultName)"
Write-Ok "SQL:      $($outputs.sqlServerFqdn) / $($outputs.sqlDatabaseName)"

# --- 3. Key Vault secret (out-of-band; not in IaC) -------------------------
Write-Step 'Seeding demonstration secret in Key Vault'
$principalId = Get-CurrentPrincipalObjectId
$kvId = az keyvault show -n $outputs.keyVaultName --query id -o tsv
# 'Key Vault Secrets Officer' = b86a8fe4-44ce-4948-aee5-eccb2c155cd7
Invoke-Az -Args @('role', 'assignment', 'create', '--assignee-object-id', $principalId,
    '--assignee-principal-type', ($acct.user.type -eq 'servicePrincipal' ? 'ServicePrincipal' : 'User'),
    '--role', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7', '--scope', $kvId) -AllowFailure | Out-Null
Write-Warn2 'Waiting 30s for RBAC propagation before writing the secret...'
Start-Sleep -Seconds 30
if ($PSCmdlet.ShouldProcess($outputs.keyVaultName, "Set secret '$DemoSecretName'")) {
    Invoke-Az -Args @('keyvault', 'secret', 'set', '--vault-name', $outputs.keyVaultName,
        '--name', $DemoSecretName, '--value', $DemoSecretValue) | Out-Null
    Write-Ok "Secret '$DemoSecretName' set"
}

# --- 4. SQL schema + managed-identity grant --------------------------------
if ($SkipSql) {
    Write-Warn2 'Skipping SQL configuration (-SkipSql).'
}
elseif (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Warn2 'sqlcmd not found; skipping SQL step. Run infra/sql/*.sql manually as an Entra admin.'
}
else {
    Write-Step 'Applying SQL schema and granting managed identity'
    $server = $outputs.sqlServerFqdn
    $db = $outputs.sqlDatabaseName

    # Substitute the grant template with the actual app identity names.
    $grantTmpl = Get-Content (Join-Path $sqlDir 'grant-managed-identities.sql.tmpl') -Raw
    $grantSql = $grantTmpl.Replace('{{API_APP_NAME}}', $outputs.apiName).Replace('{{FUNCTION_APP_NAME}}', $outputs.functionAppName)
    $grantFile = Join-Path ([System.IO.Path]::GetTempPath()) 'resfrac-grant.sql'
    Set-Content -Path $grantFile -Value $grantSql

    if ($PSCmdlet.ShouldProcess("$server/$db", 'Apply schema + grants (AAD auth)')) {
        & sqlcmd -S $server -d $db --authentication-method ActiveDirectoryDefault -b -i (Join-Path $sqlDir 'schema.sql')
        if ($LASTEXITCODE -ne 0) { throw "schema.sql failed (exit $LASTEXITCODE)" }
        & sqlcmd -S $server -d $db --authentication-method ActiveDirectoryDefault -b -i $grantFile
        if ($LASTEXITCODE -ne 0) { throw "grant script failed (exit $LASTEXITCODE)" }
        Remove-Item $grantFile -Force -ErrorAction SilentlyContinue
        Write-Ok 'SQL schema applied and API identity granted db_datareader/db_datawriter'
    }
}

Write-Step 'Provisioning complete'
$outputs | ConvertTo-Json -Depth 5
