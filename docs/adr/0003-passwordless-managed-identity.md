# ADR 0003 — Passwordless access via Managed Identity

**Status:** Accepted

## Context
Requirements emphasise secure secret management, no credentials in source, and
managed identities. Traditional connection strings/keys are a liability.

## Decision
Use **system-assigned Managed Identities** for all service-to-service access:
- API → Key Vault (`DefaultAzureCredential`) and Azure SQL (AAD access token).
- Function → Storage (identity-based `AzureWebJobsStorage__*` + data blob).
Disable SQL logins (**Entra-only**) and Storage **shared-key** access entirely.

## Rationale
- Eliminates secret sprawl and rotation risk for the data plane.
- Credentials are short-lived tokens issued by Entra ID; nothing to leak.
- Auditable via Entra sign-in and resource audit logs.

## Consequences
- SQL contained users must be created via T-SQL (see ADR 0004 dependency /
  README); the deploying identity must be a SQL Entra admin.
- Local development uses developer identity (`az login`) via
  `DefaultAzureCredential`; offline tests inject fakes.
