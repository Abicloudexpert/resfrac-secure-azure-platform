// ===========================================================================
// ResFrac — Senior Azure DevOps Assignment
// Root deployment (resource-group scope). Orchestrates the full platform:
//   monitoring -> [network] -> storage + key vault + sql -> plan
//     -> api + function -> rbac -> alerts
//
// Deploy:
//   az deployment group create -g <rg> -f main.bicep -p @params/dev.bicepparam
// ===========================================================================
targetScope = 'resourceGroup'

metadata description = 'Root Bicep template for the ResFrac secure Azure platform.'

// ---- Core parameters ----
@description('Workload short name used in resource naming.')
param workload string = 'resfrac'

@allowed(['dev', 'test', 'prod'])
param environmentName string = 'dev'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Entra ID tenant id (defaults to the deployment tenant).')
param tenantId string = tenant().tenantId

// ---- App identity / auth ----
@description('Client (application) id of the API App Registration used as the token audience.')
param apiClientId string

@description('Required OAuth2 scope / app role for protected API routes.')
param requiredScope string = 'Data.Read'

// ---- SQL Entra admin ----
@description('Object id of the Entra principal (group recommended) set as SQL admin.')
param sqlAdminObjectId string

@description('Display name of the SQL Entra admin principal.')
param sqlAdminLogin string

@allowed(['User', 'Group', 'Application'])
param sqlAdminPrincipalType string = 'Group'

// ---- Toggles / sizing ----
@description('Deploy VNet + private endpoints and disable public access on data services.')
param enablePrivateNetworking bool = false

@description('Enable Key Vault purge protection (recommended for prod).')
param enablePurgeProtection bool = false

@description('App Service Plan SKU.')
param appServicePlanSku string = 'B1'

@description('Azure SQL database SKU object.')
param sqlDatabaseSku object = {
  name: 'Basic'
  tier: 'Basic'
  capacity: 5
}

@description('Log Analytics retention (days).')
param logRetentionInDays int = 30

@description('Email for Azure Monitor alert notifications.')
param alertEmail string = ''

// ---- Naming ----
var namePrefix = '${workload}-${environmentName}'
var uniqueToken = take(uniqueString(resourceGroup().id, workload, environmentName), 6)

var names = {
  keyVault: 'kv-${workload}-${environmentName}-${uniqueToken}'
  storage: toLower('st${workload}${environmentName}${uniqueToken}')
  sqlServer: 'sql-${namePrefix}-${uniqueToken}'
  sqlDatabase: 'sqldb-${namePrefix}'
  plan: 'asp-${namePrefix}'
  api: 'app-${workload}-api-${environmentName}-${uniqueToken}'
  function: 'func-${workload}-${environmentName}-${uniqueToken}'
}

var tags = {
  workload: workload
  environment: environmentName
  managedBy: 'bicep'
  project: 'resfrac-azure-devops-assignment'
}

// ---- Observability foundation ----
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    retentionInDays: logRetentionInDays
  }
}

// ---- Networking (only in private mode) ----
module network 'modules/network.bicep' = if (enablePrivateNetworking) {
  name: 'network'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
  }
}

// Subnet / DNS ids resolved conditionally (empty strings when public mode).
// The non-null assertion (!) is safe: these are only read when the same
// enablePrivateNetworking condition that created the module is true.
var appSubnetId = enablePrivateNetworking ? network!.outputs.appSubnetId : ''
var peSubnetId = enablePrivateNetworking ? network!.outputs.privateEndpointSubnetId : ''
var kvDnsZoneId = enablePrivateNetworking ? network!.outputs.keyVaultDnsZoneId : ''
var sqlDnsZoneId = enablePrivateNetworking ? network!.outputs.sqlDnsZoneId : ''
var blobDnsZoneId = enablePrivateNetworking ? network!.outputs.blobDnsZoneId : ''

// ---- Data + secrets ----
module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    name: names.storage
    location: location
    tags: tags
    logAnalyticsId: monitoring.outputs.logAnalyticsId
    enablePrivateNetworking: enablePrivateNetworking
    privateEndpointSubnetId: peSubnetId
    blobDnsZoneId: blobDnsZoneId
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    name: names.keyVault
    location: location
    tags: tags
    tenantId: tenantId
    logAnalyticsId: monitoring.outputs.logAnalyticsId
    enablePurgeProtection: enablePurgeProtection
    enablePrivateNetworking: enablePrivateNetworking
    privateEndpointSubnetId: peSubnetId
    keyVaultDnsZoneId: kvDnsZoneId
  }
}

module sql 'modules/sql.bicep' = {
  name: 'sql'
  params: {
    serverName: names.sqlServer
    databaseName: names.sqlDatabase
    location: location
    tags: tags
    logAnalyticsId: monitoring.outputs.logAnalyticsId
    tenantId: tenantId
    sqlAdminObjectId: sqlAdminObjectId
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPrincipalType: sqlAdminPrincipalType
    databaseSku: sqlDatabaseSku
    enablePrivateNetworking: enablePrivateNetworking
    privateEndpointSubnetId: peSubnetId
    sqlDnsZoneId: sqlDnsZoneId
  }
}

// ---- Compute plan ----
module plan 'modules/plan.bicep' = {
  name: 'plan'
  params: {
    name: names.plan
    location: location
    tags: tags
    skuName: appServicePlanSku
  }
}

// ---- Applications ----
module apiApp 'modules/api-app.bicep' = {
  name: 'api-app'
  params: {
    name: names.api
    location: location
    tags: tags
    planId: plan.outputs.planId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    logAnalyticsId: monitoring.outputs.logAnalyticsId
    tenantId: tenantId
    apiClientId: apiClientId
    requiredScope: requiredScope
    sqlServerFqdn: sql.outputs.sqlServerFqdn
    sqlDatabaseName: sql.outputs.databaseName
    keyVaultUri: keyVault.outputs.keyVaultUri
    environmentName: environmentName
    enablePrivateNetworking: enablePrivateNetworking
    appSubnetId: appSubnetId
  }
}

module functionApp 'modules/function-app.bicep' = {
  name: 'function-app'
  params: {
    name: names.function
    location: location
    tags: tags
    planId: plan.outputs.planId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    logAnalyticsId: monitoring.outputs.logAnalyticsId
    storageBlobEndpoint: storage.outputs.blobEndpoint
    storageQueueEndpoint: storage.outputs.queueEndpoint
    storageTableEndpoint: storage.outputs.tableEndpoint
    storageAccountUrl: storage.outputs.blobEndpoint
    environmentName: environmentName
    enablePrivateNetworking: enablePrivateNetworking
    appSubnetId: appSubnetId
  }
}

// ---- Least-privilege RBAC (after identities exist) ----
module rbac 'modules/rbac.bicep' = {
  name: 'rbac'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    storageAccountName: storage.outputs.storageAccountName
    apiPrincipalId: apiApp.outputs.apiPrincipalId
    functionPrincipalId: functionApp.outputs.functionAppPrincipalId
  }
}

// ---- Monitoring alerts ----
module alerts 'modules/alerts.bicep' = {
  name: 'alerts'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    appInsightsId: monitoring.outputs.appInsightsId
    appServicePlanId: plan.outputs.planId
    healthEndpointUrl: 'https://${apiApp.outputs.apiDefaultHostName}/health'
    alertEmail: alertEmail
  }
}

// ---- Outputs (consumed by deploy scripts / pipeline) ----
output apiName string = apiApp.outputs.apiName
output apiUrl string = 'https://${apiApp.outputs.apiDefaultHostName}'
output apiHealthUrl string = 'https://${apiApp.outputs.apiDefaultHostName}/health'
output apiPrincipalId string = apiApp.outputs.apiPrincipalId
output functionAppName string = functionApp.outputs.functionAppName
output functionUrl string = 'https://${functionApp.outputs.functionAppDefaultHostName}'
output functionPrincipalId string = functionApp.outputs.functionAppPrincipalId
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output storageAccountName string = storage.outputs.storageAccountName
output sqlServerName string = sql.outputs.sqlServerName
output sqlServerFqdn string = sql.outputs.sqlServerFqdn
output sqlDatabaseName string = sql.outputs.databaseName
output appInsightsName string = monitoring.outputs.appInsightsName
output logAnalyticsName string = monitoring.outputs.logAnalyticsName
