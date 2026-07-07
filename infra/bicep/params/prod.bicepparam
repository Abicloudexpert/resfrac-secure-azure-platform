using '../main.bicep'

// ---------------------------------------------------------------------------
// PROD environment parameters.
// Private networking ON, purge protection ON, production-grade SKUs.
// Placeholders <REPLACE_ME> are supplied by the pipeline variable group.
// ---------------------------------------------------------------------------
param workload = 'resfrac'
param environmentName = 'prod'

param apiClientId = '00000000-0000-0000-0000-000000000000' // <REPLACE_ME>
param requiredScope = 'Data.Read'

param sqlAdminObjectId = '00000000-0000-0000-0000-000000000000' // <REPLACE_ME>
param sqlAdminLogin = 'sg-resfrac-sql-admins' // <REPLACE_ME: group display name>
param sqlAdminPrincipalType = 'Group'

// Production hardening.
param enablePrivateNetworking = true
param enablePurgeProtection = true
param appServicePlanSku = 'P1v3'
param sqlDatabaseSku = {
  name: 'S1'
  tier: 'Standard'
  capacity: 20
}
param logRetentionInDays = 90
param alertEmail = '' // e.g. 'platform-alerts@yourcompany.com'
