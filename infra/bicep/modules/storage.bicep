// ---------------------------------------------------------------------------
// General-purpose Storage account (used by the Python Function for heartbeat
// blobs AND, via identity-based connection, as the Functions host storage).
//
// Security posture:
//   * Shared key access DISABLED -> fully passwordless (AAD only).
//   * Public blob access DISABLED.
//   * TLS 1.2 minimum, HTTPS only.
//   * Public network access disabled + private endpoint when private mode is on.
// ---------------------------------------------------------------------------
metadata description = 'Hardened, passwordless general-purpose v2 Storage account.'

param name string
param location string
param tags object
param logAnalyticsId string

@description('Blob container created for Function heartbeat output.')
param heartbeatContainer string = 'heartbeats'

param enablePrivateNetworking bool = false
param privateEndpointSubnetId string = ''
param blobDnsZoneId string = ''

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    publicNetworkAccess: enablePrivateNetworking ? 'Disabled' : 'Enabled'
    networkAcls: {
      defaultAction: enablePrivateNetworking ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: heartbeatContainer
  properties: {
    publicAccess: 'None'
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: blobService
  properties: {
    workspaceId: logAnalyticsId
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
      }
    ]
  }
}

resource blobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (enablePrivateNetworking) {
  name: 'pe-${name}-blob'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'blob'
        properties: {
          privateLinkServiceId: storage.id
          groupIds: ['blob']
        }
      }
    ]
  }
}

resource blobPeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (enablePrivateNetworking) {
  parent: blobPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: blobDnsZoneId
        }
      }
    ]
  }
}

output storageAccountName string = storage.name
output storageAccountId string = storage.id
output blobEndpoint string = storage.properties.primaryEndpoints.blob
output queueEndpoint string = storage.properties.primaryEndpoints.queue
output tableEndpoint string = storage.properties.primaryEndpoints.table
