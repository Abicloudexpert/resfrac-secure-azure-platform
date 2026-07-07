# ADR 0006 — Private networking as an environment toggle

**Status:** Accepted

## Context
Production data services should not be reachable over the public internet, but
dev needs to stay cheap and frictionless.

## Decision
Model private networking as a single Bicep parameter
(`enablePrivateNetworking`). When true: deploy a VNet (app + private-endpoint
subnets), **private endpoints** and **private DNS** for Key Vault, Azure SQL and
Storage, integrate the apps with the VNet, and **disable public network access**
on the data services. Dev defaults to `false`; prod defaults to `true`.

## Rationale
- Same template, same code path — only a parameter differs across environments
  (environment parity).
- Prod gets network isolation and data-exfiltration protection; dev avoids the
  cost/complexity of endpoints and self-hosted CI agents.

## Consequences
- Prod CI migrations that must reach private SQL require a **self-hosted agent
  inside the VNet** (or temporary access) — noted as a future improvement.
- Additional cost for private endpoints and DNS in prod (justified).
