'use strict';

const request = require('supertest');
const { buildTestApp } = require('./helpers');

describe('health endpoints', () => {
  test('GET /health returns 200 and liveness payload (no auth required)', async () => {
    const { app, config } = buildTestApp();
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.service).toBe(config.serviceName);
    expect(res.headers['x-request-id']).toBeDefined();
  });

  test('GET /health/ready returns 200 when dependencies are healthy', async () => {
    const { app } = buildTestApp();
    const res = await request(app).get('/health/ready');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ready');
    expect(res.body.checks.sql).toBe('ok');
    expect(res.body.checks.keyVault).toBe('ok');
  });

  test('GET /health/ready returns 503 when SQL is down', async () => {
    const { app } = buildTestApp({
      db: {
        ping: async () => {
          throw new Error('connection refused');
        },
        listItems: async () => [],
        close: async () => {},
      },
    });
    const res = await request(app).get('/health/ready');
    expect(res.status).toBe(503);
    expect(res.body.status).toBe('not-ready');
    expect(res.body.checks.sql).toMatch(/error/);
  });
});
