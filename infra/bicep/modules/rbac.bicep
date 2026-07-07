// ---------------------------------------------------------------------------
// Least-privilege role assignments for the workload identities.
//
//   API MI       -> Key Vault Secrets User        (read secrets only)
//   Function MI  -> Storage Blob Data Owner        (heartbeats + host blob leases)
//   Function MI  -> Storage Queue Data Contributor (host queue features)
//
// Azure SQL access is NOT granted via RBAC: the identities are added as
// contained database users with db_datareader/db_datawriter via T-SQL
// (infra/sql/*.sql) — data-plane least privilege that ARM cannot express.
// ---------------------------------------------------------------------------
metadata description = 'Least-privilege RBAC for API + Function managed identities.'

param keyVaultName string
param storageAccountName string
param apiPrincipalId string
param functionPrincipalId string

// Built-in role definition IDs (stable GUIDs).
var roles = {
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  storageBlobDataOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  storageQueueDataContributor: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource apiKvSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, apiPrincipalId, roles.keyVaultSecretsUser)
  scope: keyVault
  properties: {
    principalId: apiPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.keyVaultSecretsUser)
  }
}

resource funcBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionPrincipalId, roles.storageBlobDataOwner)
  scope: storage
  properties: {
    principalId: functionPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataOwner)
  }
}

resource funcQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionPrincipalId, roles.storageQueueDataContributor)
  scope: storage
  properties: {
    principalId: functionPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageQueueDataContributor)
  }
}
