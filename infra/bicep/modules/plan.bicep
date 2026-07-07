// ---------------------------------------------------------------------------
// Single Linux App Service Plan shared by the Node API and the Python Function
// (Dedicated hosting). Dedicated hosting is chosen deliberately so we can:
//   * use identity-based (passwordless) AzureWebJobsStorage without an Azure
//     Files content share,
//   * enable regional VNet integration for private egress,
//   * avoid cold starts for the API.
// ---------------------------------------------------------------------------
metadata description = 'Linux App Service Plan (Dedicated) shared by API + Function.'

param name string
param location string
param tags object

@description('Plan SKU, e.g. B1 (dev) or P1v3 (prod).')
param skuName string = 'B1'

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: 'linux'
  properties: {
    reserved: true // required for Linux
  }
}

output planId string = plan.id
output planName string = plan.name
