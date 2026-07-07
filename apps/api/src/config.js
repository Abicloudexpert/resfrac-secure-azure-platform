'use strict';

/**
 * Centralised, validated configuration.
 *
 * Design intent:
 *  - The app is configured ENTIRELY from environment variables so that the same
 *    image/artifact is promoted unchanged across dev/prod (12-factor).
 *  - NO secrets are hard-coded. Secrets that cannot be sourced via Managed
 *    Identity (e.g. a third-party API key) are read at runtime from Key Vault.
 *  - Azure SQL and Key Vault are accessed with Managed Identity (DefaultAzureCredential),
 *    so there are no connection strings containing passwords anywhere.
 */

function toBool(value, fallback = false) {
  if (value === undefined || value === null || value === '') return fallback;
  return ['1', 'true', 'yes', 'on'].includes(String(value).toLowerCase());
}

function loadConfig(env = process.env) {
  const tenantId = env.AZURE_TENANT_ID || '';
  const apiClientId = env.API_CLIENT_ID || '';

  const config = {
    env: env.NODE_ENV || 'development',
    port: parseInt(env.PORT || '8080', 10),
    serviceName: env.SERVICE_NAME || 'resfrac-api',

    // ---- Microsoft Entra ID (OAuth2 / OIDC) token validation ----
    auth: {
      enabled: toBool(env.AUTH_ENABLED, true),
      tenantId,
      // Accept v2.0 issuer by default. For multi-tenant/CIAM adjust accordingly.
      issuer: env.AUTH_ISSUER || (tenantId ? `https://login.microsoftonline.com/${tenantId}/v2.0` : ''),
      jwksUri:
        env.AUTH_JWKS_URI ||
        (tenantId ? `https://login.microsoftonline.com/${tenantId}/discovery/v2.0/keys` : ''),
      // Audience is the App Registration. Entra issues the App ID URI
      // (`api://<clientId>`) in v1 access tokens and the bare client id in v2
      // tokens, so we accept BOTH forms to stay robust across token versions.
      // AUTH_AUDIENCE (comma-separated) overrides the derived defaults.
      audience: env.AUTH_AUDIENCE
        ? env.AUTH_AUDIENCE.split(',').map((s) => s.trim()).filter(Boolean)
        : (apiClientId ? [`api://${apiClientId}`, apiClientId] : []),
      // Scope (delegated) or app role (application) required for protected routes.
      requiredScope: env.AUTH_REQUIRED_SCOPE || 'Data.Read',
    },

    // ---- Azure SQL (accessed via Managed Identity AAD token) ----
    sql: {
      enabled: toBool(env.SQL_ENABLED, true),
      server: env.SQL_SERVER || '', // e.g. sql-resfrac-dev.database.windows.net
      database: env.SQL_DATABASE || '',
      // The AAD scope used to obtain an access token for Azure SQL.
      scope: 'https://database.windows.net/.default',
      connectTimeoutMs: parseInt(env.SQL_CONNECT_TIMEOUT_MS || '15000', 10),
    },

    // ---- Key Vault (accessed via Managed Identity) ----
    keyVault: {
      enabled: toBool(env.KEYVAULT_ENABLED, true),
      uri: env.KEYVAULT_URI || '', // e.g. https://kv-resfrac-dev.vault.azure.net
      // Name of a demonstration secret retrieved to prove KV integration.
      demoSecretName: env.KEYVAULT_DEMO_SECRET || 'api-feature-flag',
    },

    // ---- Application Insights ----
    telemetry: {
      connectionString: env.APPLICATIONINSIGHTS_CONNECTION_STRING || '',
      cloudRole: env.SERVICE_NAME || 'resfrac-api',
    },

    // ---- HTTP hardening ----
    http: {
      corsOrigins: (env.CORS_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean),
      rateLimitWindowMs: parseInt(env.RATE_LIMIT_WINDOW_MS || '60000', 10),
      rateLimitMax: parseInt(env.RATE_LIMIT_MAX || '100', 10),
    },
  };

  return config;
}

/**
 * Fail fast on misconfiguration in production. Never throws in test/dev so the
 * suite and local exploration can run without a full Azure footprint.
 */
function assertProductionConfig(config) {
  const problems = [];
  if (config.auth.enabled) {
    if (!config.auth.issuer) problems.push('AUTH_ISSUER / AZURE_TENANT_ID is required');
    if (!config.auth.jwksUri) problems.push('AUTH_JWKS_URI / AZURE_TENANT_ID is required');
    if (!config.auth.audience || config.auth.audience.length === 0) {
      problems.push('AUTH_AUDIENCE / API_CLIENT_ID is required');
    }
  }
  if (config.sql.enabled && (!config.sql.server || !config.sql.database)) {
    problems.push('SQL_SERVER and SQL_DATABASE are required when SQL is enabled');
  }
  if (config.keyVault.enabled && !config.keyVault.uri) {
    problems.push('KEYVAULT_URI is required when Key Vault is enabled');
  }
  if (problems.length && config.env === 'production') {
    throw new Error(`Invalid production configuration:\n - ${problems.join('\n - ')}`);
  }
  return problems;
}

module.exports = { loadConfig, assertProductionConfig, toBool };
