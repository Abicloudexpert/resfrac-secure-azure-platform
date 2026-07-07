'use strict';

const { trackException } = require('../telemetry');

/** Attaches/propagates a correlation id for every request. */
function requestId() {
  return (req, res, next) => {
    const id =
      req.headers['x-request-id'] ||
      req.headers['request-id'] ||
      (globalThis.crypto?.randomUUID ? globalThis.crypto.randomUUID() : `${Date.now()}-${Math.random()}`);
    req.id = id;
    res.setHeader('x-request-id', id);
    next();
  };
}

/** 404 handler for unmatched routes. */
function notFound() {
  return (req, res) => {
    res.status(404).json({ error: 'not_found', message: `No route for ${req.method} ${req.path}` });
  };
}

/** Centralised error handler — never leaks stack traces to clients. */
function errorHandler(logger) {
  return (err, req, res, _next) => {
    const status = err.status || err.statusCode || 500;
    logger.error('Unhandled error', {
      requestId: req.id,
      status,
      error: err.message,
      stack: err.stack,
    });
    trackException(err, { requestId: req.id, path: req.path });
    res.status(status).json({
      error: status >= 500 ? 'internal_error' : 'request_error',
      message: status >= 500 ? 'An unexpected error occurred' : err.message,
      requestId: req.id,
    });
  };
}

module.exports = { requestId, notFound, errorHandler };
