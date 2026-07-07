'use strict';

/**
 * Azure SQL access using a Microsoft Entra ID access token obtained via
 * Managed Identity — i.e. passwordless. There is NO SQL login/password
 * anywhere in the codebase, pipeline, or configuration.
 *
 * The App Service system-assigned identity is granted a contained database
 * user (see infra/scripts + docs) with least-privilege (db_datareader/writer),
 * and tedious authenticates with `azure-active-directory-access-token`.
 *
 * A short-lived token cache avoids requesting a new AAD token on every query;
 * the connection pool is created lazily and reused.
 */
function createDbService(config, deps = {}) {
  let pool = null;
  let tokenCache = null; // { token, expiresOnTimestamp }

  async function getAccessToken() {
    const now = Date.now();
    if (tokenCache && tokenCache.expiresOnTimestamp - now > 60_000) {
      return tokenCache.token;
    }
    if (deps.getToken) {
      tokenCache = await deps.getToken();
      return tokenCache.token;
    }
    const { DefaultAzureCredential } = require('@azure/identity');
    const credential = deps.credential || new DefaultAzureCredential();
    const result = await credential.getToken(config.sql.scope);
    tokenCache = { token: result.token, expiresOnTimestamp: result.expiresOnTimestamp };
    return tokenCache.token;
  }

  async function getPool() {
    if (pool && pool.connected) return pool;
    if (deps.pool) {
      pool = deps.pool;
      return pool;
    }
    const sql = require('mssql');
    const token = await getAccessToken();
    pool = new sql.ConnectionPool({
      server: config.sql.server,
      database: config.sql.database,
      options: {
        encrypt: true,
        trustServerCertificate: false,
        connectTimeout: config.sql.connectTimeoutMs,
      },
      authentication: {
        type: 'azure-active-directory-access-token',
        options: { token },
      },
    });
    await pool.connect();
    return pool;
  }

  /** Lightweight readiness probe used by /health/ready. */
  async function ping() {
    const p = await getPool();
    const result = await p.request().query('SELECT 1 AS ok');
    return result.recordset?.[0]?.ok === 1;
  }

  /** Example protected read used by the /api/v1/items endpoint. */
  async function listItems(limit = 20) {
    const p = await getPool();
    const sql = deps.sqlModule || require('mssql');
    const result = await p
      .request()
      .input('limit', sql.Int, limit)
      .query(
        'SELECT TOP (@limit) Id, Name, CreatedAt FROM dbo.Items ORDER BY CreatedAt DESC',
      );
    return result.recordset;
  }

  async function close() {
    if (pool && pool.close) await pool.close();
    pool = null;
  }

  return { getPool, ping, listItems, close };
}

module.exports = { createDbService };
