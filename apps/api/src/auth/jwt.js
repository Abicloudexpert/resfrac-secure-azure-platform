'use strict';

const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

/**
 * OAuth2 / OIDC bearer-token validation for Microsoft Entra ID.
 *
 * Validation performed (RFC 7519 / OAuth2 best practice):
 *   - signature       : RS256, key resolved from the tenant JWKS by `kid`
 *   - issuer (iss)     : must equal the configured Entra ID issuer
 *   - audience (aud)   : must equal this API's Application ID URI / client id
 *   - expiry (exp/nbf) : enforced by jsonwebtoken
 *   - authorization    : requiredScope checked against `scp` (delegated) or
 *                        `roles` (application permissions)
 *
 * The signing-key resolver is injectable (`deps.getKey`) so the middleware is
 * unit-testable offline with a locally generated RSA key — no network calls.
 */
function buildKeyResolver(config) {
  const client = jwksClient({
    jwksUri: config.auth.jwksUri,
    cache: true,
    cacheMaxEntries: 5,
    cacheMaxAge: 10 * 60 * 1000, // 10 minutes
    rateLimit: true,
    jwksRequestsPerMinute: 10,
  });
  return function getKey(header, callback) {
    client.getSigningKey(header.kid, (err, key) => {
      if (err) return callback(err);
      return callback(null, key.getPublicKey());
    });
  };
}

function extractBearerToken(req) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (!token || scheme.toLowerCase() !== 'bearer') return null;
  return token;
}

function requireAuth(config, deps = {}) {
  // When auth is disabled (explicit opt-out for local smoke tests only) we
  // short-circuit but stamp a synthetic principal so downstream code is uniform.
  if (!config.auth.enabled) {
    return (req, _res, next) => {
      req.user = { sub: 'auth-disabled', scp: config.auth.requiredScope };
      next();
    };
  }

  const getKey = deps.getKey || buildKeyResolver(config);
  const verifyOptions = {
    audience: config.auth.audience,
    issuer: config.auth.issuer,
    algorithms: ['RS256'],
    clockTolerance: 5,
  };

  return function authenticate(req, res, next) {
    const token = extractBearerToken(req);
    if (!token) {
      return res
        .status(401)
        .set('WWW-Authenticate', 'Bearer error="invalid_request"')
        .json({ error: 'unauthorized', message: 'Missing or malformed Authorization header' });
    }
    jwt.verify(token, getKey, verifyOptions, (err, decoded) => {
      if (err) {
        return res
          .status(401)
          .set('WWW-Authenticate', `Bearer error="invalid_token", error_description="${err.message}"`)
          .json({ error: 'unauthorized', message: err.message });
      }
      req.user = decoded;
      return next();
    });
  };
}

/**
 * Authorisation: require a delegated scope (`scp`) OR an application role (`roles`).
 * Supports both delegated (user) and app-only (service-to-service) tokens.
 */
function requireScope(requiredScope) {
  return function authorize(req, res, next) {
    const scopes = String(req.user?.scp || '').split(' ').filter(Boolean);
    const roles = Array.isArray(req.user?.roles) ? req.user.roles : [];
    if (scopes.includes(requiredScope) || roles.includes(requiredScope)) {
      return next();
    }
    return res.status(403).json({
      error: 'forbidden',
      message: `Token is missing required scope/role '${requiredScope}'`,
    });
  };
}

module.exports = { requireAuth, requireScope, buildKeyResolver, extractBearerToken };
