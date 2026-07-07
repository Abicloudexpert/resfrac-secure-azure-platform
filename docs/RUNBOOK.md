# Operations Runbook

Concise, action-oriented procedures for on-call. Pair with
[`MONITORING.md`](./MONITORING.md) for query detail.

## Quick reference

| Item | Value |
|------|-------|
| Resource groups | `rg-resfrac-dev`, `rg-resfrac-prod` |
| API liveness | `GET https://<api-host>/health` |
| API readiness | `GET https://<api-host>/health/ready` |
| Function health | `GET https://<func-host>/api/health` |
| Telemetry | Application Insights `appi-resfrac-<env>` → LAW `log-resfrac-<env>` |
| Alerts | Action Group `ag-resfrac-<env>` |

## Alert playbooks

### 🔴 Availability alert (Sev1) — `/health` failing

1. Manually hit `GET /health` and `/health/ready`. If `ready` fails, note which
   dependency (`sql` / `keyVault`).
2. Check App Service → *Diagnose and solve problems*; check instance health and
   recent restarts.
3. Check for a recent deployment (pipeline history). If correlated → **roll back
   the app** (see below).
4. If a dependency is down (SQL/KV): check that resource's health and the
   private endpoint / firewall configuration.
5. Escalate if not mitigated within the Sev1 window.

### 🟠 Application-failure alert (Sev2) — elevated 5xx

1. App Insights → *Failures*: identify the failing operation and `resultCode`.
2. Inspect `exceptions` (KQL in MONITORING.md) for the root cause.
3. Common causes: bad deploy (roll back), dependency failure (SQL/KV),
   auth/config drift (check app settings), throttling.

### 🟠 Infrastructure alert (Sev2) — plan CPU > 80%

1. Confirm sustained load in App Service Plan metrics.
2. Short term: **scale out** (increase instance count) or **scale up** (larger
   SKU): `az appservice plan update -g <rg> -n asp-resfrac-<env> --sku P1v3`.
3. Investigate whether the load is legitimate (traffic) or pathological (retry
   storm, hot loop) via App Insights *Performance*.

## Common procedures

### Roll back the application to the previous build

```bash
# Pipeline: re-run the Deploy stage selecting the previous successful run's artifacts,
# or redeploy a specific commit's artifact:
pwsh infra/scripts/deploy-apps.ps1 -ResourceGroup rg-resfrac-<env> \
  -ApiName <app> -FunctionName <func>   # after checking out the last-good commit
```

### Redeploy / converge infrastructure

```bash
az deployment group what-if -g rg-resfrac-<env> -f infra/bicep/main.bicep \
  -p infra/bicep/params/<env>.bicepparam    # preview
pwsh infra/scripts/provision.ps1 -Environment <env> ... -SkipSql   # apply
```

### Rotate a Key Vault secret

```bash
az keyvault secret set --vault-name kv-resfrac-<env>-<token> \
  --name api-feature-flag --value <new-value>
# API picks up the new version within the cache TTL (5 min) or on restart.
```

### Grant/refresh SQL access for the API identity

```bash
# Connect to the DB as the Entra SQL admin, then:
#   CREATE USER [<app-name>] FROM EXTERNAL PROVIDER;
#   ALTER ROLE db_datareader ADD MEMBER [<app-name>];
#   ALTER ROLE db_datawriter ADD MEMBER [<app-name>];
# Automated by infra/sql/grant-managed-identities.sql.tmpl via provision.ps1.
```

### Point-in-time restore of Azure SQL

```bash
az sql db restore -g rg-resfrac-<env> -s sql-resfrac-<env>-<token> \
  -n sqldb-resfrac-<env> --dest-name sqldb-resfrac-<env>-restored \
  --time "2026-07-07T09:00:00Z"
```

### Tear down an environment

```bash
pwsh infra/scripts/teardown.ps1 -ResourceGroup rg-resfrac-<env> -PurgeKeyVault
# Prod has purge protection; the KV name is retained until the retention period.
```

## Escalation

1. On-call engineer (Action Group email).
2. Platform/DevOps lead.
3. Service owner (data/SQL, identity/Entra) as needed.
