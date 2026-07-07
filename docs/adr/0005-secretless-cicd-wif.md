# ADR 0005 — Secretless CI/CD with Workload Identity Federation

**Status:** Accepted

## Context
The pipeline must deploy to Azure securely without storing long-lived cloud
credentials, per "secure pipeline practices".

## Decision
Authenticate the Azure DevOps service connection using **Workload Identity
Federation (OIDC)**. Application secrets come from a **Key Vault-backed variable
group** and are passed as **secret variables** (mapped via `env:`).

## Rationale
- **No service-principal secret** to store, rotate, or leak — the ADO org is a
  federated trust subject; Azure issues short-lived tokens per run.
- Secrets never appear on command lines or in logs.
- Least-privilege service connection scoped to the target resource group(s).

## Consequences
- One-time federated-credential setup (documented in README).
- Migrations that touch SQL require the federated identity to be a SQL Entra
  admin (or in the admin group).
