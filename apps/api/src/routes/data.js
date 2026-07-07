'use strict';

const express = require('express');
const { requireAuth, requireScope } = require('../auth/jwt');

/**
 * Protected business endpoints.
 *
 * Every route here requires a valid Entra ID bearer token AND the configured
 * scope/role. This demonstrates the full request path:
 *   client -> (Entra ID token) -> API -> Managed Identity -> Azure SQL / Key Vault
 */
function dataRouter({ config, db, keyVault, authDeps = {} }) {
  const router = express.Router();
  const authenticate = requireAuth(config, authDeps);
  const authorize = requireScope(config.auth.requiredScope);

  // Returns the authenticated principal (useful for debugging token contents).
  router.get('/api/v1/whoami', authenticate, (req, res) => {
    res.json({
      subject: req.user.sub,
      appId: req.user.appid || req.user.azp,
      scopes: req.user.scp || null,
      roles: req.user.roles || [],
      name: req.user.name || null,
    });
  });

  // Protected data read: retrieves a Key Vault flag + rows from Azure SQL.
  router.get('/api/v1/items', authenticate, authorize, async (req, res, next) => {
    try {
      const limit = Math.min(parseInt(req.query.limit || '20', 10) || 20, 100);
      let featureFlag = null;
      if (config.keyVault.enabled) {
        featureFlag = await keyVault.getSecret(config.keyVault.demoSecretName);
      }
      const items = config.sql.enabled ? await db.listItems(limit) : [];
      res.json({
        featureFlag,
        count: items.length,
        items,
      });
    } catch (err) {
      next(err);
    }
  });

  return router;
}

module.exports = { dataRouter };
