'use strict';

const { loadConfig, assertProductionConfig } = require('./config');
const { createLogger } = require('./logger');
const { initTelemetry } = require('./telemetry');
const { createApp } = require('./app');
const { createDbService } = require('./services/db');
const { createKeyVaultService } = require('./services/keyvault');

function main() {
  const config = loadConfig();
  const logger = createLogger({ service: config.serviceName, level: process.env.LOG_LEVEL });

  const problems = assertProductionConfig(config); // throws in production if invalid
  if (problems.length) {
    logger.warn('Configuration warnings (non-production)', { problems });
  }

  // Telemetry first so early errors are captured.
  initTelemetry(config, logger);

  const db = createDbService(config);
  const keyVault = createKeyVaultService(config);
  const app = createApp({ config, logger, db, keyVault });

  const server = app.listen(config.port, () => {
    logger.info('API listening', { port: config.port, env: config.env });
  });

  // Graceful shutdown so in-flight requests drain and the SQL pool closes.
  const shutdown = (signal) => {
    logger.info('Shutting down', { signal });
    server.close(async () => {
      try {
        await db.close();
      } catch (err) {
        logger.error('Error closing DB pool', { error: err.message });
      }
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10_000).unref();
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  return server;
}

if (require.main === module) {
  main();
}

module.exports = { main };
