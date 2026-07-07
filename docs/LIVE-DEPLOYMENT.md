# Live Deployment Evidence (dev)

This document records an **actual, verified deployment** of the ResFrac platform
to Azure using the Infrastructure-as-Code and scripts in this repository. It
proves the solution is not just designed but runs end-to-end with **zero secrets
in code** and **passwordless** service-to-service auth.

- **Subscription:** `Azure subscription 1` (`8e132557-ad65-47d6-aae7-3b9b51ee1d65`)
- **Tenant:** `23ff5e9b-c19d-4edd-9db8-8bef4ddc8e86`
- **Resource group:** `rg-resfrac-dev`
- **Region:** `centralus`  *(chosen because this new subscription has 0 App
  Service vCPU quota in `eastus2`/`eastus`/`westus`; `centralus`/`westus3` have
  capacity — an account limitation, not a solution constraint)*

## Deployed resources

| Resource | Name |
| --- | --- |
| Log Analytics workspace | `log-resfrac-dev` |
| Application Insights | `appi-resfrac-dev` |
| App Service plan (Linux, dedicated) | `asp-resfrac-dev` |
| API (App Service) | `app-resfrac-api-dev-rfpuvk` |
| Function App (Python 3.11) | `func-resfrac-dev-rfpuvk` |
| Storage (keyless / Entra) | `stresfracdevrfpuvk` |
| Key Vault (RBAC) | `kv-resfrac-dev-rfpuvk` |
| Azure SQL (Entra-only auth) | `sql-resfrac-dev-rfpuvk` / db `sqldb-resfrac-dev` |
| Action group | `ag-resfrac-dev` |
| Availability web test | `webtest-resfrac-dev-health` |
| Alerts | `alert-resfrac-dev-availability`, `alert-resfrac-dev-app-failures`, `alert-resfrac-dev-plan-cpu` |

Public endpoints:

- API: `https://app-resfrac-api-dev-rfpuvk.azurewebsites.net`
- Function: `https://func-resfrac-dev-rfpuvk.azurewebsites.net`

## Identity model (no passwords anywhere)

- **API App Registration** `resfrac-api` (`961ef82c-aa52-48b7-9a70-ffb1f1942428`)
  exposes app role **`Data.Read`** and uses v2 access tokens
  (`requestedAccessTokenVersion = 2`).
- **API system-assigned Managed Identity** → Key Vault (Secrets User) and Azure
  SQL (contained user `db_datareader` + `db_datawriter`). No connection strings,
  no SQL passwords.
- **Function system-assigned Managed Identity** → Storage (Blob Data
  Owner/Contributor) via `AzureWebJobsStorage__*` identity settings. No storage
  account keys.
- **Azure SQL admin** is the Entra group `sg-resfrac-sql-admins` (Entra-only
  authentication; SQL auth disabled).

## One-time bootstrap: SQL server → Directory Readers

Creating a contained DB user for a managed identity with
`CREATE USER ... FROM EXTERNAL PROVIDER` requires the **SQL logical server's
identity** to resolve the identity in Microsoft Entra, which needs the
**Directory Readers** role. This is granted once by an administrator (it is
deliberately *not* given to the CI principal — a deployment identity should not
be able to modify directory roles):

```bash
SQLMI=$(az sql server show -n <sql-server> -g <rg> --query identity.principalId -o tsv)
ROLE=$(az rest --method get \
  --url "https://graph.microsoft.com/v1.0/directoryRoles?\$filter=roleTemplateId eq '88d8e3e3-8f55-4a1e-953a-9b9898b8876b'" \
  --query "value[0].id" -o tsv)   # activate first if empty
az rest --method post \
  --url "https://graph.microsoft.com/v1.0/directoryRoles/$ROLE/members/\$ref" \
  --headers "Content-Type=application/json" \
  --body "{\"@odata.id\":\"https://graph.microsoft.com/v1.0/directoryObjects/$SQLMI\"}"
```

The alternative (no directory role) is to create the user with an explicit SID
derived from the identity's **application/client id** — an MI's SQL SID is its
client id, *not* its object id: `CREATE USER [name] WITH SID = <0x…>, TYPE = E`.

## Verification (smoke tests, all green)

Run:

```bash
SMOKE_CLIENT_SECRET=<app-only secret> \
pwsh infra/scripts/smoke-test.ps1 \
  -ApiUrl      https://app-resfrac-api-dev-rfpuvk.azurewebsites.net \
  -FunctionUrl https://func-resfrac-dev-rfpuvk.azurewebsites.net \
  -TenantId    23ff5e9b-c19d-4edd-9db8-8bef4ddc8e86 \
  -ClientId    961ef82c-aa52-48b7-9a70-ffb1f1942428 \
  -ApiAudience api://961ef82c-aa52-48b7-9a70-ffb1f1942428
```

Result:

```
[ok] API /health -> 200
[ok] API /health/ready -> 200        # SQL + Key Vault reachable via Managed Identity
[ok] API /api/v1/items (anonymous) -> 401
[ok] API /api/v1/items (authorized) -> 200
[ok] Function /api/health -> 200
All smoke tests passed
```

The authorized call returns data that exercises **every** integration in one
response — Key Vault (feature flag) + SQL (items) read via Managed Identity,
gated by an OAuth2 app-only token carrying the `Data.Read` role:

```json
{
  "featureFlag": "enabled",
  "count": 3,
  "items": [
    { "Id": 1, "Name": "well-telemetry-baseline" },
    { "Id": 2, "Name": "fracture-model-v2" },
    { "Id": 3, "Name": "reservoir-sim-config" }
  ]
}
```

The Function's timer wrote heartbeat blobs to Storage via its Managed Identity;
`GET /api/summary` (function-key protected) read them back:

```json
{ "container": "heartbeats", "heartbeatCount": 2, "environment": "dev" }
```

## How it was deployed

1. `az bicep install`; register resource providers.
2. Bootstrap identity: create `resfrac-api` App Registration + `Data.Read` app
   role + service principal; create `sg-resfrac-sql-admins` Entra group.
3. `infra/scripts/provision.ps1` — resource group + Bicep deployment + seed the
   Key Vault demo secret.
4. `infra/sql/run-sql.cjs` — passwordless (AAD token) apply of `schema.sql` and
   the Managed Identity `GRANT`s.
5. Deploy code: API via `az webapp deploy` (run-from-package); Function built
   with Linux `manylinux`/cp311 wheels and deployed as a package.
6. `infra/scripts/smoke-test.ps1` — end-to-end validation.

> Note: the CI pipeline (`pipelines/`) runs on `ubuntu-latest`, so it packages
> both apps natively; the `manylinux` wheel step above is only needed when
> building the Function from a non-Linux workstation.

## Teardown

```bash
pwsh infra/scripts/teardown.ps1 -Environment dev        # or:
az group delete -n rg-resfrac-dev --yes --no-wait
```

Also remove the bootstrap identity objects if no longer needed:

```bash
az ad app delete --id 961ef82c-aa52-48b7-9a70-ffb1f1942428
az ad group delete --group sg-resfrac-sql-admins
```

> Cost note: the dev footprint uses a Basic App Service plan, a Basic Azure SQL
> database, and standard Key Vault/Storage — a few USD/day. Tear down when done.
