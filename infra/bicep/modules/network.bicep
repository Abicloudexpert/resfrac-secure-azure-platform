// ---------------------------------------------------------------------------
// Networking foundation for the private deployment model:
//   * VNet with an app-integration subnet (delegated to App Service) and a
//     dedicated private-endpoints subnet.
//   * Private DNS zones for Key Vault, Azure SQL and Blob storage, linked to
//     the VNet so private endpoints resolve to private IPs.
// This module is only deployed when enablePrivateNetworking = true.
// ---------------------------------------------------------------------------
metadata description = 'VNet, subnets and private DNS zones for private endpoints.'

param namePrefix string
param location string
param tags object
param addressPrefix string = '10.20.0.0/16'
param appSubnetPrefix string = '10.20.1.0/24'
param privateEndpointSubnetPrefix string = '10.20.2.0/24'

var appSubnetName = 'snet-app'
var peSubnetName = 'snet-pe'

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${namePrefix}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [
      {
        name: appSubnetName
        properties: {
          addressPrefix: appSubnetPrefix
          delegations: [
            {
              name: 'appservice-delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Enabled'
          serviceEndpoints: []
        }
      }
      {
        name: peSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          // Must be disabled for private endpoints to be placed in the subnet.
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

var privateDnsZoneNames = [
  'privatelink.vaultcore.azure.net' // Key Vault
  'privatelink${environment().suffixes.sqlServerHostname}' // Azure SQL (e.g. .database.windows.net)
  'privatelink.blob.${environment().suffixes.storage}' // Blob storage
]

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [
  for zone in privateDnsZoneNames: {
    name: zone
    location: 'global'
    tags: tags
  }
]

resource dnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [
  for (zone, i) in privateDnsZoneNames: {
    parent: privateDnsZones[i]
    name: 'link-${namePrefix}'
    location: 'global'
    tags: tags
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
]

output vnetId string = vnet.id
output appSubnetId string = '${vnet.id}/subnets/${appSubnetName}'
output privateEndpointSubnetId string = '${vnet.id}/subnets/${peSubnetName}'
output keyVaultDnsZoneId string = privateDnsZones[0].id
output sqlDnsZoneId string = privateDnsZones[1].id
output blobDnsZoneId string = privateDnsZones[2].id
