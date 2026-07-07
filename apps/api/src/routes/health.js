'use strict';

const express = require('express');

/**
 * Liveness vs readiness separation (Kubernetes/App Service best practice):
 *   - GET /health        : liveness. Cheap, no dependencies. Used by the
 *                          platform to decide whether to restart the instance
 *                          and by the availability alert.
 *   - GET /health/ready  : readiness. Verifies downstream dependencies
 *                          (Key Vault + SQL). Used by deployment smoke tests
 *                          and load-balancer gating.
 */
function healthRouter({ config, db, keyVault, startedAt }) {
  const router = express.Router();

  router.get('/health', (_req, res) => {
    res.status(200).json({
      status: 'ok',
      service: config.serviceName,
      version: process.env.APP_VERSION || 'dev',
      env: config.env,
      uptimeSeconds: Math.floor((Date.now() - startedAt) / 1000),
      timestamp: new Date().toISOString(),
    });
  });

  router.get('/health/ready', async (_req, res) => {
    const checks = {};
    let healthy = true;

    if (config.sql.enabled) {
      try {
        checks.sql = (await db.ping()) ? 'ok' : 'degraded';
        if (checks.sql !== 'ok') healthy = false;
      } catch (err) {
        checks.sql = `error: ${err.message}`;
        healthy = false;
      }
    } else {
      checks.sql = 'disabled';
    }

    if (config.keyVault.enabled) {
      try {
        await keyVault.getSecret(config.keyVault.demoSecretName);
        checks.keyVault = 'ok';
      } catch (err) {
        checks.keyVault = `error: ${err.message}`;
        healthy = false;
      }
    } else {
      checks.keyVault = 'disabled';
    }

    res.status(healthy ? 200 : 503).json({
      status: healthy ? 'ready' : 'not-ready',
      checks,
      timestamp: new Date().toISOString(),
    });
  });

  return router;
}

module.exports = { healthRouter };
