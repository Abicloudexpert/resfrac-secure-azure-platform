'use strict';

const { loadConfig, assertProductionConfig } = require('../src/config');

describe('config', () => {
  test('derives Entra ID issuer/jwks/audience from tenant + client id', () => {
    const c = loadConfig({
      AZURE_TENANT_ID: 'tid',
      API_CLIENT_ID: 'cid',
    });
    expect(c.auth.issuer).toBe('https://login.microsoftonline.com/tid/v2.0');
    expect(c.auth.jwksUri).toBe('https://login.microsoftonline.com/tid/discovery/v2.0/keys');
    // Accepts both the v1 (App ID URI) and v2 (bare client id) audience forms.
    expect(c.auth.audience).toEqual(['api://cid', 'cid']);
  });

  test('does not throw for incomplete non-production config', () => {
    const c = loadConfig({ NODE_ENV: 'development' });
    expect(() => assertProductionConfig(c)).not.toThrow();
  });

  test('throws for incomplete production config', () => {
    const c = loadConfig({ NODE_ENV: 'production' });
    expect(() => assertProductionConfig(c)).toThrow(/Invalid production configuration/);
  });
});
