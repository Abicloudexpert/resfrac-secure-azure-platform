'use strict';

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');

const { healthRouter } = require('./routes/health');
const { dataRouter } = require('./routes/data');
const { requestId, notFound, errorHandler } = require('./middleware/errorHandler');

/**
 * Express application factory.
 *
 * Dependencies (db, keyVault, logger, auth key resolver) are injected so the
 * app can be assembled with real Azure clients in production and with fakes in
 * unit tests — keeping tests hermetic and fast.
 */
function createApp({ config, logger, db, keyVault, authDeps = {} }) {
  const app = express();
  const startedAt = Date.now();

  app.disable('x-powered-by');
  app.set('trust proxy', 1); // App Service / Front Door terminate TLS upstream

  app.use(helmet());
  app.use(express.json({ limit: '1mb' }));
  app.use(requestId());

  if (config.http.corsOrigins.length) {
    app.use(cors({ origin: config.http.corsOrigins }));
  }

  app.use(
    rateLimit({
      windowMs: config.http.rateLimitWindowMs,
      max: config.http.rateLimitMax,
      standardHeaders: true,
      legacyHeaders: false,
      // Never rate-limit liveness probes.
      skip: (req) => req.path === '/health',
    }),
  );

  // Structured access log.
  app.use((req, res, next) => {
    const start = Date.now();
    res.on('finish', () => {
      logger.info('request', {
        requestId: req.id,
        method: req.method,
        path: req.path,
        status: res.statusCode,
        durationMs: Date.now() - start,
      });
    });
    next();
  });

  app.use(healthRouter({ config, db, keyVault, startedAt }));
  app.use(dataRouter({ config, db, keyVault, authDeps }));

  app.use(notFound());
  app.use(errorHandler(logger));

  return app;
}

module.exports = { createApp };
