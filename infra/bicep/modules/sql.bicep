// ---------------------------------------------------------------------------
// Azure SQL logical server + database with Microsoft Entra-only authentication
// (SQL authentication disabled). The App Service / Function identities are
// added as contained database users out-of-band (T-SQL, see infra/sql/*.sql)
// because data-plane user creation is not expressible in ARM/Bicep.
//
// Security posture:
//   * azureADOnlyAuthentication = true  -> no SQL logins/passwords exist.
//   * minimalTlsVersion 1.2, encrypted connections enforced by the client.
//   * Public network access disabled + private endpoint in private mode.
// ---------------------------------------------------------------------------
metadata description = 'Entra-only Azure SQL server + database, optionally private.'

param serverName string
param databaseName string
param location string
param tags object
param logAnalyticsId string

@description('Object id of the Entra admin (user or group) for the SQL server.')
param sqlAdminObjectId string

@description('Display name of the Entra admin principal.')
param sqlAdminLogin string

@description('Principal type of the Entra admin.')
@allowed(['User', 'Group', 'Application'])
param sqlAdminPrincipalType string = 'Group'

param tenantId string

@description('Database SKU. Basic for dev; scale up for prod.')
param databaseSku object = {
  name: 'Basic'
  tier: 'Basic'
  capacity: 5
}

@description('Max database size in bytes.')
param maxSizeBytes int = 2147483648 // 2 GB (Basic)

param enablePrivateNetworking bool = false
param privateEndpointSubnetId string = ''
param sqlDnsZoneId string = ''

@description('When not private, allow other Azure services (e.g. pipeline agents) to connect.')
param allowAzureServices bool = true

// The server's system-assigned identity is granted the "Directory Readers"
// Entra role out-of-band (one-time admin bootstrap, see docs/LIVE-DEPLOYMENT.md).
// That lets `CREATE USER ... FROM EXTERNAL PROVIDER` resolve the app/Function
// managed identities in Entra when their contained DB users are created. The
// role is intentionally not granted by CI (a deployment identity should not be
// able to modify directory roles).
resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: serverName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: enablePrivateNetworking ? 'Disabled' : 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: sqlAdminPrincipalType
      login: sqlAdminLogin
      sid: sqlAdminObjectId
      tenantId: tenantId
      azureADOnlyAuthentication: true
    }
  }
}

resource database 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  tags: tags
  sku: databaseSku
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: maxSizeBytes
    zoneRedundant: false
  }
}

// Allow Azure services (0.0.0.0) only when not fully private, so pipeline agents
// and the App Service can reach the server without a private endpoint.
resource allowAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = if (!enablePrivateNetworking && allowAzureServices) {
  parent: sqlServer
  name: 'AllowAllAzureIPs'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource auditToLaw 'Microsoft.Sql/servers/databases/auditingSettings@2023-08-01-preview' = {
  parent: database
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
  }
}

resource dbDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: database
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Basic'
        enabled: true
      }
    ]
  }
}

resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (enablePrivateNetworking) {
  name: 'pe-${serverName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'sqlServer'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: ['sqlServer']
        }
      }
    ]
  }
}

resource sqlPeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (enablePrivateNetworking) {
  parent: sqlPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'sql'
        properties: {
          privateDnsZoneId: sqlDnsZoneId
        }
      }
    ]
  }
}

output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = database.name
