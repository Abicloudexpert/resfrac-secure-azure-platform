#!/usr/bin/env node
/**
 * Passwordless T-SQL runner.
 *
 * Executes a .sql file against Azure SQL using a Microsoft Entra ID access
 * token obtained via DefaultAzureCredential (Managed Identity / az login / WIF).
 * There are NO passwords. Batches are split on lines containing only `GO`.
 *
 * Usage (run from a directory whose node_modules contains mssql + @azure/identity,
 * e.g. apps/api after `npm ci`):
 *   node infra/sql/run-sql.cjs --server <fqdn> --database <db> --file <path.sql>
 *
 * Optional token substitution for the grant template is done by the caller
 * (provision.ps1 / pipeline) before invoking this script.
 */
'use strict';

const fs = require('fs');
const { DefaultAzureCredential } = require('@azure/identity');
const sql = require('mssql');

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const key = argv[i].replace(/^--/, '');
    args[key] = argv[i + 1];
    i += 1;
  }
  return args;
}

function splitBatches(text) {
  return text
    .split(/^\s*GO\s*$/gim)
    .map((b) => b.trim())
    .filter((b) => b.length > 0);
}

async function main() {
  const { server, database, file } = parseArgs(process.argv);
  if (!server || !database || !file) {
    console.error('Usage: run-sql.cjs --server <fqdn> --database <db> --file <path.sql>');
    process.exit(2);
  }

  const script = fs.readFileSync(file, 'utf8');
  const batches = splitBatches(script);

  const credential = new DefaultAzureCredential();
  const token = await credential.getToken('https://database.windows.net/.default');

  const pool = new sql.ConnectionPool({
    server,
    database,
    options: { encrypt: true, trustServerCertificate: false },
    authentication: { type: 'azure-active-directory-access-token', options: { token: token.token } },
  });

  await pool.connect();
  console.log(`Connected to ${server}/${database}; executing ${batches.length} batch(es)...`);
  try {
    for (let i = 0; i < batches.length; i += 1) {
      await pool.request().batch(batches[i]);
      console.log(`  batch ${i + 1}/${batches.length} ok`);
    }
  } finally {
    await pool.close();
  }
  console.log('SQL execution complete.');
}

main().catch((err) => {
  console.error(`SQL execution failed: ${err.message}`);
  process.exit(1);
});
