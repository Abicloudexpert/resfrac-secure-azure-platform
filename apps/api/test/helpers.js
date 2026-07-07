'use strict';

const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { loadConfig } = require('../src/config');
const { createLogger } = require('../src/logger');
const { createApp } = require('../src/app');

/**
 * Generates an in-memory RSA key pair and returns:
 *  - a `getKey` resolver compatible with jsonwebtoken (mimics the JWKS lookup)
 *  - a `sign(payload)` helper to mint valid tokens for the test issuer/audience
 *
 * This lets us exercise the REAL jwt.verify path (signature, iss, aud, exp)
 * with zero network access.
 */
function buildTestAuth({ issuer, audience }) {
  const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });
  const kid = 'test-key-1';

  const getKey = (header, callback) => {
    if (header.kid !== kid) return callback(new Error('unknown kid'));
    return callback(null, publicKey);
  };

  const sign = (payload = {}, options = {}) =>
    jwt.sign(payload, privateKey, {
      algorithm: 'RS256',
      keyid: kid,
      issuer,
      audience,
      subject: payload.sub || 'test-subject',
      expiresIn: options.expiresIn || '5m',
      ...options.signOptions,
    });

  return { getKey, sign, publicKey };
}

/** Builds an app instance wired with fakes for db + key vault. */
function buildTestApp(overrides = {}) {
  const env = {
    NODE_ENV: 'test',
    SERVICE_NAME: 'resfrac-api-test',
    AZURE_TENANT_ID: '11111111-1111-1111-1111-111111111111',
    API_CLIENT_ID: '22222222-2222-2222-2222-222222222222',
    AUTH_REQUIRED_SCOPE: 'Data.Read',
    ...overrides.env,
  };
  const config = loadConfig(env);
  const logger = createLogger({ service: 'test', level: 'error' });

  const testAuth = buildTestAuth({ issuer: config.auth.issuer, audience: config.auth.audience });

  const db = overrides.db || {
    ping: async () => true,
    listItems: async (limit) =>
      [
        { Id: 1, Name: 'alpha', CreatedAt: '2026-01-01T00:00:00Z' },
        { Id: 2, Name: 'beta', CreatedAt: '2026-01-02T00:00:00Z' },
      ].slice(0, limit),
    close: async () => {},
  };

  const keyVault = overrides.keyVault || {
    getSecret: async () => 'enabled',
  };

  const app = createApp({
    config,
    logger,
    db,
    keyVault,
    authDeps: { getKey: testAuth.getKey },
  });

  return { app, config, sign: testAuth.sign, testAuth };
}

module.exports = { buildTestApp, buildTestAuth };
