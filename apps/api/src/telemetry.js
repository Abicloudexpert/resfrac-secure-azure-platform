'use strict';

/**
 * Application Insights bootstrap.
 *
 * We only initialise the SDK when a connection string is present so that the
 * unit-test / local path stays fully offline. Instrumentation-key based config
 * is intentionally NOT supported (deprecated by Microsoft); connection strings
 * carry the regional ingestion endpoint and are the supported path.
 */
let appInsights;

function initTelemetry(config, logger = console) {
  const connectionString = config.telemetry.connectionString;
  if (!connectionString) {
    logger.warn?.('[telemetry] APPLICATIONINSIGHTS_CONNECTION_STRING not set — telemetry disabled');
    return null;
  }

  // Lazy require so the dependency is not loaded during offline unit tests.
  appInsights = require('applicationinsights');

  appInsights
    .setup(connectionString)
    .setAutoCollectRequests(true)
    .setAutoCollectPerformance(true, true)
    .setAutoCollectExceptions(true)
    .setAutoCollectDependencies(true)
    .setAutoCollectConsole(true, true)
    .setSendLiveMetrics(true)
    .setDistributedTracingMode(appInsights.DistributedTracingModes.AI_AND_W3C);

  appInsights.defaultClient.context.tags[appInsights.defaultClient.context.keys.cloudRole] =
    config.telemetry.cloudRole;
  appInsights.defaultClient.context.tags[appInsights.defaultClient.context.keys.cloudRoleInstance] =
    process.env.WEBSITE_INSTANCE_ID || process.env.HOSTNAME || 'local';

  appInsights.start();
  logger.info?.('[telemetry] Application Insights initialised');
  return appInsights.defaultClient;
}

function trackEvent(name, properties = {}) {
  if (appInsights?.defaultClient) {
    appInsights.defaultClient.trackEvent({ name, properties });
  }
}

function trackException(error, properties = {}) {
  if (appInsights?.defaultClient) {
    appInsights.defaultClient.trackException({ exception: error, properties });
  }
}

module.exports = { initTelemetry, trackEvent, trackException };
