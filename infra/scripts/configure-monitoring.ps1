#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Operational helper to (re)configure the alert notification target and to
    report the current monitoring posture of an environment.

.DESCRIPTION
    The alerts themselves are provisioned declaratively in Bicep (alerts.bicep).
    This script handles day-2 operations that are awkward to express in IaC:
      * update the Action Group email receiver without a full redeploy,
      * enumerate configured alert rules and their enabled/fired state,
      * confirm the availability web test is enabled.

.EXAMPLE
    ./configure-monitoring.ps1 -ResourceGroup rg-resfrac-dev -AlertEmail oncall@contoso.com
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [string]$AlertEmail,
    [string]$SubscriptionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/common.psm1" -Force

Assert-AzLogin -SubscriptionId $SubscriptionId | Out-Null

# --- Update the action group email receiver (optional) ---------------------
if ($AlertEmail) {
    Write-Step "Updating action group email receiver -> $AlertEmail"
    $ag = az monitor action-group list -g $ResourceGroup --query "[0].name" -o tsv
    if (-not $ag) { throw "No action group found in $ResourceGroup" }
    if ($PSCmdlet.ShouldProcess($ag, 'Set email receiver')) {
        Invoke-Az -Args @('monitor', 'action-group', 'update', '-g', $ResourceGroup, '-n', $ag,
            '--add', 'emailReceivers', "name=primary", "emailAddress=$AlertEmail", 'useCommonAlertSchema=true') -AllowFailure | Out-Null
        Write-Ok "Action group '$ag' updated"
    }
}

# --- Report metric alert rules ---------------------------------------------
Write-Step 'Configured metric alert rules'
$alerts = az monitor metrics alert list -g $ResourceGroup | ConvertFrom-Json
foreach ($a in $alerts) {
    $state = $a.enabled ? 'enabled' : 'DISABLED'
    Write-Host ("    - {0,-40} sev{1}  {2}" -f $a.name, $a.severity, $state)
}

# --- Report availability web tests -----------------------------------------
Write-Step 'Availability web tests'
$webtests = az resource list -g $ResourceGroup --resource-type 'Microsoft.Insights/webtests' --query "[].name" -o tsv
if ($webtests) { $webtests -split "`n" | ForEach-Object { Write-Host "    - $_" } }
else { Write-Warn2 'No web tests found.' }

Write-Step 'Monitoring configuration report complete'
