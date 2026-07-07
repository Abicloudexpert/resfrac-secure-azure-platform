'use strict';

const { loadConfig } = require('../src/config');
const { createDbService } = require('../src/services/db');
const { createKeyVaultService } = require('../src/services/keyvault');

const config = loadConfig({
  SQL_SERVER: 'sql-test.database.windows.net',
  SQL_DATABASE: 'db-test',
  KEYVAULT_URI: 'https://kv-test.vault.azure.net',
});

function fakePool() {
  return {
    connected: true,
    request() {
      return {
        input() {
          return this;
        },
        async query(q) {
          if (/SELECT 1/i.test(q)) return { recordset: [{ ok: 1 }] };
          return {
            recordset: [{ Id: 1, Name: 'alpha', CreatedAt: '2026-01-01T00:00:00Z' }],
          };
        },
      };
    },
    close: async () => {},
  };
}

describe('db service (injected pool + AAD token)', () => {
  test('ping returns true against a healthy pool', async () => {
    const svc = createDbService(config, { pool: fakePool() });
    await expect(svc.ping()).resolves.toBe(true);
  });

  test('listItems returns rows using a parameterised query', async () => {
    const svc = createDbService(config, {
      pool: fakePool(),
      sqlModule: { Int: 'Int' },
    });
    const rows = await svc.listItems(5);
    expect(rows).toHaveLength(1);
    expect(rows[0].Name).toBe('alpha');
    await svc.close();
  });
});

describe('key vault service (injected client + cache)', () => {
  test('fetches a secret and caches subsequent reads', async () => {
    let calls = 0;
    const svc = createKeyVaultService(config, {
      client: {
        getSecret: async (name) => {
          calls += 1;
          return { value: `value-for-${name}` };
        },
      },
    });
    const first = await svc.getSecret('api-feature-flag');
    const second = await svc.getSecret('api-feature-flag');
    expect(first).toBe('value-for-api-feature-flag');
    expect(second).toBe(first);
    expect(calls).toBe(1); // second read served from cache
  });
});
