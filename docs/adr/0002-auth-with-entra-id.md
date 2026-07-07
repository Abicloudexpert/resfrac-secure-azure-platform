# ADR 0002 — Authentication with Microsoft Entra ID (OAuth2/JWT)

**Status:** Accepted

## Context
The API needs OAuth2/JWT authentication. The assignment states a preference for
Microsoft Entra ID.

## Decision
Validate **Entra ID-issued JWT bearer tokens** in the API. Authorize on `scp`
(delegated) or `roles` (application) claims. Audience is `api://<apiClientId>`.

## Rationale
- Assignment-preferred and enterprise-standard.
- Integrates cleanly with Managed Identity for downstream resources.
- No password/user store to build or secure.
- Supports both user (delegated) and service (client-credentials) callers.

## Implementation notes
- Signing keys resolved from the tenant JWKS by `kid`, cached and rate-limited.
- Validates signature (RS256), `iss`, `aud`, `exp`/`nbf` with small clock skew.
- Returns spec-compliant `401` (`WWW-Authenticate`) and `403` for missing scope.
- Key resolver is injectable → the suite tests the real verification path
  offline with a locally generated RSA key.

## Consequences
- Requires an App Registration and correct audience/scope configuration.
- Token/claims configuration is an operational prerequisite (documented).
