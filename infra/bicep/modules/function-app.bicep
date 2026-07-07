// ---------------------------------------------------------------------------
// Python Function App (Linux, Dedicated plan) with identity-based storage.
//   * System-assigned Managed Identity (Storage + host storage).
//   * AzureWebJobsStorage uses identity-based connection (no keys):
//     the *_serviceUri settings + role assignments replace the connection string.
//   * App Insights via connection string; logs flow automatically.
// ---------------------------------------------------------------------------
metadata description = 'Python Function App with identity-based (passwordless) storage.'

param name string
param location string
param tags object
param planId string
param appInsightsConnectionString string
param logAnalyticsId string

@description('Python runtime, e.g. PYTHON|3.11.')
param linuxFxVersion string = 'PYTHON|3.11'

param storageBlobEndpoint string
param storageQueueEndpoint string
param storageTableEndpoint string
param storageAccountUrl string
param heartbeatContainer string = 'heartbeats'
param environmentName string

param enablePrivateNetworking bool = false
param appSubnetId string = ''

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: planId
    httpsOnly: true
    virtualNetworkSubnetId: enablePrivateNetworking ? appSubnetId : null
    vnetRouteAllEnabled: enablePrivateNetworking ? true : false
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      alwaysOn: true
      appSettings: [
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'false' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        // ---- Identity-based AzureWebJobsStorage (passwordless) ----
        { name: 'AzureWebJobsStorage__blobServiceUri', value: storageBlobEndpoint }
        { name: 'AzureWebJobsStorage__queueServiceUri', value: storageQueueEndpoint }
        { name: 'AzureWebJobsStorage__tableServiceUri', value: storageTableEndpoint }
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        // ---- Application config ----
        { name: 'STORAGE_ACCOUNT_URL', value: storageAccountUrl }
        { name: 'HEARTBEAT_CONTAINER', value: heartbeatContainer }
        { name: 'ENVIRONMENT', value: environmentName }
        { name: 'SERVICE_NAME', value: name }
      ]
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: functionApp
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      { category: 'FunctionAppLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

output functionAppName string = functionApp.name
output functionAppPrincipalId string = functionApp.identity.principalId
output functionAppDefaultHostName string = functionApp.properties.defaultHostName
output functionAppId string = functionApp.id
