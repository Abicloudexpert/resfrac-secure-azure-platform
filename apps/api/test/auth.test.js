'use strict';

const request = require('supertest');
const jwt = require('jsonwebtoken');
const { buildTestApp } = require('./helpers');

describe('protected endpoints & OAuth2/JWT validation', () => {
  test('401 when no bearer token is supplied', async () => {
    const { app } = buildTestApp();
    const res = await request(app).get('/api/v1/items');
    expect(res.status).toBe(401);
    expect(res.headers['www-authenticate']).toMatch(/Bearer/);
  });

  test('401 when token signature is invalid', async () => {
    const { app } = buildTestApp();
    // A token signed by an unrelated key must be rejected.
    const forged = jwt.sign({ scp: 'Data.Read' }, 'not-the-real-key', { algorithm: 'HS256' });
    const res = await request(app).get('/api/v1/items').set('Authorization', `Bearer ${forged}`);
    expect(res.status).toBe(401);
  });

  test('401 when token is expired', async () => {
    const { app, sign } = buildTestApp();
    const token = sign({ scp: 'Data.Read' }, { expiresIn: '-60s' });
    const res = await request(app).get('/api/v1/items').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(401);
  });

  test('401 when audience does not match', async () => {
    const { app, sign } = buildTestApp();
    const token = sign({ scp: 'Data.Read' }, { signOptions: { audience: 'api://wrong-audience' } });
    const res = await request(app).get('/api/v1/items').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(401);
  });

  test('403 when a valid token is missing the required scope', async () => {
    const { app, sign } = buildTestApp();
    const token = sign({ scp: 'Some.Other.Scope' });
    const res = await request(app).get('/api/v1/items').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
    expect(res.body.error).toBe('forbidden');
  });

  test('200 with a valid, correctly-scoped delegated token', async () => {
    const { app, sign } = buildTestApp();
    const token = sign({ scp: 'Data.Read', name: 'Ada Lovelace' });
    const res = await request(app).get('/api/v1/items').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.featureFlag).toBe('enabled');
    expect(Array.isArray(res.body.items)).toBe(true);
    expect(res.body.count).toBeGreaterThan(0);
  });

  test('200 with an app-only token carrying the required role', async () => {
    const { app, sign } = buildTestApp();
    const token = sign({ roles: ['Data.Read'] });
    const res = await request(app).get('/api/v1/items').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
  });

  test('whoami reflects token claims', async () => {
    const { app, sign } = buildTestApp();
    const token = sign({ scp: 'Data.Read', name: 'Ada Lovelace', appid: 'client-x' });
    const res = await request(app).get('/api/v1/whoami').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.name).toBe('Ada Lovelace');
    expect(res.body.scopes).toBe('Data.Read');
  });
});
