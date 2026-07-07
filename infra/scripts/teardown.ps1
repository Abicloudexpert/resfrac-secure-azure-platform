#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tears down an environment by deleting its resource group.

.DESCRIPTION
    Destructive. Requires explicit confirmation (or -Force). Optionally purges
    the soft-deleted Key Vault so the name can be reused immediately (only
    possible when purge protection is disabled — i.e. non-prod).

.EXAMPLE
    ./teardown.ps1 -ResourceGroup rg-resfrac-dev -PurgeKeyVault
.EXAMPLE
    ./teardown.ps1 -ResourceGroup rg-resfrac-dev -Force
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [string]$SubscriptionId,
    [switch]$PurgeKeyVault,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/common.psm1" -Force

Assert-AzLogin -SubscriptionId $SubscriptionId | Out-Null

$exists = az group exists -n $ResourceGroup
if ($exists -ne 'true') {
    Write-Warn2 "Resource group '$ResourceGroup' does not exist. Nothing to do."
    return
}

# Capture Key Vault names before deletion (needed for purge).
$kvNames = @()
if ($PurgeKeyVault) {
    $kvNames = (az keyvault list -g $ResourceGroup --query "[].name" -o tsv) -split "`n" | Where-Object { $_ }
}

if (-not $Force -and -not $PSCmdlet.ShouldProcess($ResourceGroup, 'DELETE resource group and ALL resources')) {
    Write-Warn2 'Aborted.'
    return
}
if (-not $Force) {
    $confirm = Read-Host "Type the resource group name '$ResourceGroup' to confirm deletion"
    if ($confirm -ne $ResourceGroup) { Write-Warn2 'Confirmation mismatch. Aborted.'; return }
}

Write-Step "Deleting resource group '$ResourceGroup'"
Invoke-Az -Args @('group', 'delete', '-n', $ResourceGroup, '--yes') | Out-Null
Write-Ok 'Resource group deleted'

foreach ($kv in $kvNames) {
    Write-Step "Purging soft-deleted Key Vault '$kv'"
    Invoke-Az -Args @('keyvault', 'purge', '-n', $kv) -AllowFailure | Out-Null
    Write-Ok "Purged '$kv' (or purge protection prevented it)"
}

Write-Step 'Teardown complete'
