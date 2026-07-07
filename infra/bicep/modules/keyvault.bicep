// ---------------------------------------------------------------------------
// Key Vault with RBAC authorization (no access policies), soft-delete and
// optional purge protection.
//
// Deliberate design: this module provisions the *vault* only. Secret VALUES are
// injected out-of-band by the operator/pipeline (see infra/scripts/provision.ps1
// -> `az keyvault secret set`). This (a) keeps secrets out of source and ARM
// deployment history, and (b) avoids the well-known RBAC role-propagation race
// when writing secrets to an RBAC-enabled vault in the same deployment.
// ---------------------------------------------------------------------------
metadata description = 'RBAC-enabled Key Vault with optional private endpoint.'

param name string
param location string
param tags object
param tenantId string
param logAnalyticsId string

@description('Enable purge protection (recommended for prod; blocks immediate teardown).')
param enablePurgeProtection bool = false

param enablePrivateNetworking bool = false
param privateEndpointSubnetId string = ''
param keyVaultDnsZoneId string = ''

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: enablePurgeProtection ? true : null
    publicNetworkAccess: enablePrivateNetworking ? 'Disabled' : 'Enabled'
    networkAcls: {
      defaultAction: enablePrivateNetworking ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: keyVault
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
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource kvPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (enablePrivateNetworking) {
  name: 'pe-${name}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'vault'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: ['vault']
        }
      }
    ]
  }
}

resource kvPeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (enablePrivateNetworking) {
  parent: kvPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vault'
        properties: {
          privateDnsZoneId: keyVaultDnsZoneId
        }
      }
    ]
  }
}

output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
