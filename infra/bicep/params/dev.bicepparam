using '../main.bicep'

// ---------------------------------------------------------------------------
// DEV environment parameters.
// Placeholders marked <REPLACE_ME> are supplied by the pipeline (variable group)
// or overridden on the CLI: `-p apiClientId=<id> sqlAdminObjectId=<oid> ...`.
// No secrets belong in this file.
// ---------------------------------------------------------------------------
param workload = 'resfrac'
param environmentName = 'dev'

// App Registration (API) client id — token audience becomes api://<apiClientId>.
param apiClientId = '00000000-0000-0000-0000-000000000000' // <REPLACE_ME>
param requiredScope = 'Data.Read'

// Entra group (recommended) that administers Azure SQL.
param sqlAdminObjectId = '00000000-0000-0000-0000-000000000000' // <REPLACE_ME>
param sqlAdminLogin = 'sg-resfrac-sql-admins' // <REPLACE_ME: group display name>
param sqlAdminPrincipalType = 'Group'

// Dev keeps public access + cheap SKUs + no purge protection (easy teardown).
param enablePrivateNetworking = false
param enablePurgeProtection = false
param appServicePlanSku = 'B1'
param sqlDatabaseSku = {
  name: 'Basic'
  tier: 'Basic'
  capacity: 5
}
param logRetentionInDays = 30
param alertEmail = '' // e.g. 'platform-alerts@yourcompany.com'
