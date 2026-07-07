'use strict';

/**
 * Minimal, dependency-free structured JSON logger.
 *
 * Emitting single-line JSON to stdout means the platform (App Service /
 * Application Insights / Log Analytics) captures well-structured logs without a
 * heavyweight logging framework. Correlation is carried via `operation_Id`.
 */
const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };

function createLogger(options = {}) {
  const minLevel = LEVELS[options.level || process.env.LOG_LEVEL || 'info'] || LEVELS.info;
  const base = { service: options.service || 'resfrac-api', ...options.base };

  function emit(level, msg, meta = {}) {
    if (LEVELS[level] < minLevel) return;
    const record = {
      timestamp: new Date().toISOString(),
      level,
      message: msg,
      ...base,
      ...meta,
    };
    const line = JSON.stringify(record);
    if (level === 'error') process.stderr.write(`${line}\n`);
    else process.stdout.write(`${line}\n`);
  }

  return {
    debug: (m, meta) => emit('debug', m, meta),
    info: (m, meta) => emit('info', m, meta),
    warn: (m, meta) => emit('warn', m, meta),
    error: (m, meta) => emit('error', m, meta),
    child: (extra) => createLogger({ ...options, base: { ...base, ...extra } }),
  };
}

module.exports = { createLogger };
