'use strict';

/**
 * Key Vault secret access using Managed Identity (DefaultAzureCredential).
 *
 * DefaultAzureCredential resolves, in order:
 *   1. Environment variables (local dev / service principal)
 *   2. Workload Identity / Managed Identity (App Service, Functions, AKS)
 *   3. Azure CLI / Developer CLI (interactive local dev)
 *
 * In Azure this means the App Service system-assigned identity is used, so
 * there are NO secrets in configuration to read the Key Vault.
 */
function createKeyVaultService(config, deps = {}) {
  let client = deps.client || null;
  const cache = new Map();
  const cacheTtlMs = 5 * 60 * 1000;

  function getClient() {
    if (client) return client;
    if (!config.keyVault.uri) {
      throw new Error('Key Vault URI is not configured (KEYVAULT_URI)');
    }
    // Lazy require keeps Azure SDKs out of the offline unit-test path.
    const { SecretClient } = require('@azure/keyvault-secrets');
    const { DefaultAzureCredential } = require('@azure/identity');
    const credential = deps.credential || new DefaultAzureCredential();
    client = new SecretClient(config.keyVault.uri, credential);
    return client;
  }

  async function getSecret(name) {
    const cached = cache.get(name);
    if (cached && cached.expiresAt > Date.now()) return cached.value;
    const secret = await getClient().getSecret(name);
    cache.set(name, { value: secret.value, expiresAt: Date.now() + cacheTtlMs });
    return secret.value;
  }

  return { getSecret, _cache: cache };
}

module.exports = { createKeyVaultService };
