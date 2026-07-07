# Security

Security posture for the ResFrac platform, mapped to the assignment's
requirements and to defence-in-depth layers.

## 1. Secret management — no credentials in source control

- **Nothing sensitive is committed.** `.gitignore` blocks `.env`,
  `local.settings.json`, `*.pfx/pem/key`, `azureauth.json`, etc. Only
  `*.example` templates are tracked.
- **Application secrets live in Key Vault.** The API reads them at runtime via
  Managed Identity. Secret *values* are never in Bicep, params, or ARM
  deployment history — they are seeded out-of-band (`provision.ps1` /
  pipeline step) by design.
- **No secrets in app settings.** App settings carry only non-secret config
  (endpoints, ids, feature names).

## 2. Passwordless / identity-based access

| Caller | Target | Mechanism | Credential |
|--------|--------|-----------|-----------|
| API | Key Vault | `DefaultAzureCredential` → system MI | none (token) |
| API | Azure SQL | AAD access token (`azure-active-directory-access-token`) | none (token) |
| Function | Storage (blobs) | Identity-based connection (`AzureWebJobsStorage__*`) | none (token) |
| Pipeline | Azure | Workload Identity Federation (OIDC) | none (federated) |

- **Azure SQL is Entra-only** (`azureADOnlyAuthentication = true`) — SQL logins
  and passwords cannot even be created.
- **Storage shared-key access is disabled** (`allowSharedKeyAccess = false`) —
  account keys are unusable; all access is AAD.

## 3. Least privilege (RBAC)

| Identity | Role | Scope |
|----------|------|-------|
| API MI | Key Vault Secrets User | the vault |
| Function MI | Storage Blob Data Owner | the storage account |
| Function MI | Storage Queue Data Contributor | the storage account |
| API MI (SQL) | `db_datareader` + `db_datawriter` contained user | the database |

- Key Vault uses **RBAC authorization** (not legacy access policies).
- No identity is granted `Owner`/`Contributor` on data services.
- The SQL admin is an **Entra group**, not an individual, for auditability and
  joiner/leaver hygiene.

## 4. OAuth2 / JWT implementation

Validation performed by the API (`apps/api/src/auth/jwt.js`):

- **Signature** — RS256, key resolved from the tenant JWKS by `kid` (cached,
  rate-limited).
- **Issuer** — must equal the configured Entra ID issuer.
- **Audience** — must equal `api://<apiClientId>`.
- **Expiry / not-before** — enforced with a small clock skew tolerance.
- **Authorization** — required `scp` (delegated) or `roles` (application) claim.
- Failures return `401` with a spec-compliant `WWW-Authenticate` header;
  missing scope returns `403`.

The design supports both **user (delegated)** and **service (client
credentials / app-only)** tokens.

## 5. Network security

- **Private networking mode** (default in prod) puts Key Vault, Azure SQL and
  Storage behind **private endpoints** with **private DNS**, and **disables
  public network access**.
- App Service / Function use **regional VNet integration** with
  `vnetRouteAllEnabled` so egress to data services stays on the private network.
- Dev uses public endpoints (with `Allow Azure services`) for simplicity and
  cost; the same template flips to private via one parameter.

## 6. Transport & application hardening

- **HTTPS only**, **TLS 1.2 minimum**, **FTPS disabled** on both apps.
- API middleware: **Helmet** (secure headers), **CORS allow-list**,
  **rate limiting**, JSON body size limit, `x-powered-by` disabled.
- Errors are sanitised — **no stack traces or internal details** returned to
  clients; full detail goes to Application Insights with a correlation id.
- Containerised API runs as a **non-root** user with a health check.

## 7. Secure pipeline practices

- **Secretless auth** via Workload Identity Federation (OIDC).
- Secrets passed as **secret pipeline variables**, mapped via `env:` (never on
  the command line, never logged).
- **Environment approval** gate before production.
- Least-privilege service connection scoped to the target resource group(s).
- Build and deploy are separated; artifacts are immutable
  (`WEBSITE_RUN_FROM_PACKAGE`).

## 8. Threat considerations & mitigations (summary)

| Threat | Mitigation |
|--------|------------|
| Credential leakage | No secrets in source/history; MI + WIF; KV with RBAC |
| Token forgery/replay | Full JWT validation; short-lived tokens; HTTPS only |
| Lateral movement | Least-privilege RBAC; private endpoints; Entra-only SQL |
| Data exfiltration | Public access disabled; shared-key disabled; diagnostics/audit to LAW |
| Supply chain | Pinned dependencies; lint/test gates; artifact immutability |
| DoS | Rate limiting; platform autoscale (future: Front Door WAF) |
