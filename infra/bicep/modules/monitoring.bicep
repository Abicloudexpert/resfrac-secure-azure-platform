// ---------------------------------------------------------------------------
// Observability foundation: Log Analytics workspace + workspace-based
// Application Insights. All other resources send diagnostics here.
// ---------------------------------------------------------------------------
metadata description = 'Log Analytics workspace and workspace-based Application Insights.'

@description('Base name prefix, e.g. resfrac-dev.')
param namePrefix string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Data retention in days for Log Analytics.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Daily ingestion cap in GB (-1 for uncapped). Guards against cost surprises.')
param dailyQuotaGb int = -1

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${namePrefix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: dailyQuotaGb == -1 ? null : {
      dailyQuotaGb: dailyQuotaGb
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${namePrefix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
    DisableIpMasking: false
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output logAnalyticsId string = logAnalytics.id
output logAnalyticsName string = logAnalytics.name
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
@description('Instrumentation key retained for legacy tooling; connection string is preferred.')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
