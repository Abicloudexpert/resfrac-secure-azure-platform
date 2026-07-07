// ---------------------------------------------------------------------------
// Node.js API Web App (Linux, Dedicated plan).
//   * System-assigned Managed Identity (used for Key Vault + Azure SQL).
//   * HTTPS only, TLS 1.2, FTPS disabled, health check on /health.
//   * Optional regional VNet integration for private egress.
//   * App settings inject Entra ID / SQL / Key Vault / App Insights config —
//     NO secrets (identity-based access everywhere).
// ---------------------------------------------------------------------------
metadata description = 'Node.js API Web App with system-assigned identity.'

param name string
param location string
param tags object
param planId string
param appInsightsConnectionString string
param logAnalyticsId string

@description('Node runtime, e.g. NODE|22-lts.')
param linuxFxVersion string = 'NODE|22-lts'

// ---- Application configuration (non-secret) ----
param tenantId string
param apiClientId string
param requiredScope string = 'Data.Read'
param sqlServerFqdn string
param sqlDatabaseName string
param keyVaultUri string
@description('Name of the Key Vault secret the API reads (not a secret value).')
param keyVaultDemoSecretName string = 'api-feature-flag'
param environmentName string

param enablePrivateNetworking bool = false
param appSubnetId string = ''

resource api 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'app,linux'
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
      healthCheckPath: '/health'
      appSettings: [
        { name: 'NODE_ENV', value: 'production' }
        { name: 'PORT', value: '8080' }
        { name: 'WEBSITES_PORT', value: '8080' }
        { name: 'SERVICE_NAME', value: name }
        { name: 'APP_VERSION', value: '#{Build.BuildNumber}#' }
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'false' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        { name: 'ApplicationInsightsAgent_EXTENSION_VERSION', value: '~3' }
        { name: 'AZURE_TENANT_ID', value: tenantId }
        { name: 'API_CLIENT_ID', value: apiClientId }
        { name: 'AUTH_REQUIRED_SCOPE', value: requiredScope }
        { name: 'AUTH_ENABLED', value: 'true' }
        { name: 'SQL_ENABLED', value: 'true' }
        { name: 'SQL_SERVER', value: sqlServerFqdn }
        { name: 'SQL_DATABASE', value: sqlDatabaseName }
        { name: 'KEYVAULT_ENABLED', value: 'true' }
        { name: 'KEYVAULT_URI', value: keyVaultUri }
        { name: 'KEYVAULT_DEMO_SECRET', value: keyVaultDemoSecretName }
        { name: 'ENVIRONMENT', value: environmentName }
      ]
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: api
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      { category: 'AppServiceHTTPLogs', enabled: true }
      { category: 'AppServiceConsoleLogs', enabled: true }
      { category: 'AppServiceAppLogs', enabled: true }
      { category: 'AppServicePlatformLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

output apiName string = api.name
output apiPrincipalId string = api.identity.principalId
output apiDefaultHostName string = api.properties.defaultHostName
output apiId string = api.id
