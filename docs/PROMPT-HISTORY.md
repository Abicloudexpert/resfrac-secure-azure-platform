# Prompt History & Engineering Narrative

This is a curated record of how the solution was driven, per the assignment's
AI-Assisted Development Policy ("share the chat transcript or prompt history…
be prepared to explain all generated code and design decisions").

AI was used as a **pair-programming accelerator**; the **engineering direction,
architecture, trade-offs, and validation were human-led**. Every decision below
is one I can defend and modify on the spot. The theme throughout was
*"facts, not assumptions"* — nothing was accepted until it was executed and
verified.

---

## How I worked

1. Start from the brief and derive explicit requirements (security posture,
   passwordless everywhere, multi-stage CI/CD, monitoring, teardown).
2. Direct the AI to scaffold against those constraints, then **review, harden,
   and correct** each artifact.
3. **Prove it** — run tests, compile IaC, deploy to Azure, and smoke-test the
   live endpoints before calling anything "done".

---

## Key direction points (prompts → decision → why)

**1. "Azure-only estate — pick an IaC tool and justify it; modular, not one
monolith."**
→ Bicep, split into per-concern modules (`monitoring`, `network`, `data`,
`compute`, `rbac`, `alerts`). Bicep gives first-class Azure resource support and
no state file to manage. (ADR 0001)

**2. "No passwords or keys anywhere — API↔SQL, API↔Key Vault, Function↔Storage."**
→ System-assigned Managed Identities + Entra-only SQL auth + Key Vault RBAC +
storage with shared-key access **disabled** (`AzureWebJobsStorage__*` identity
settings). Drove the choice of a Dedicated plan so the Function needs no
storage-key content share. (ADRs 0003, 0004)

**3. "JWT validation must be complete and support both user and service tokens."**
→ Validate signature (JWKS), issuer, audience, expiry; authorize on `scp`
(delegated) **or** `roles` (application). This later mattered in production —
see issue #1 below.

**4. "Secretless CI/CD — no stored cloud credentials."**
→ Workload Identity Federation (OIDC) for both Azure DevOps and GitHub Actions;
app secrets from a Key Vault-backed variable group / Actions secrets, never on
the command line. (ADR 0005)

**5. "Migrations can't use sqlcmd/passwords — solve it cleanly."**
→ A small Node runner (`infra/sql/run-sql.cjs`) that authenticates with an Entra
token via `DefaultAzureCredential` and applies schema + Managed-Identity
`GRANT`s. Cross-platform, passwordless, idempotent.

**6. "Keep Azure DevOps as required, but prove the pipeline actually runs."**
→ Kept the ADO YAML as the deliverable and added an equivalent **GitHub Actions**
workflow that runs the *same* Bicep/scripts live via OIDC. (ADR 0007)

---

## Issues I caught and drove to resolution (live)

These are the moments that show judgment under real conditions — good
walkthrough material.

**#1 — v1 vs v2 token audience.** The protected endpoint returned 401 with a
valid app token. Root cause: Entra v2 access tokens carry the bare client-id as
`aud`, while the API expected the `api://<clientId>` (v1) form. Fix: set the app
registration's `requestedAccessTokenVersion = 2` **and** make the API accept both
audience forms (robust across token versions). Verified with a decoded token.

**#2 — Subscription quota.** The new subscription had **0 App Service vCPU quota**
in `eastus2`/`eastus`/`westus`. Rather than compromise the design, I probed
regions via `what-if` and deployed unchanged to `centralus` (which had capacity).

**#3 — Cross-platform Function build.** Building on macOS produced the wrong
(non-Linux) Python wheels. Fix: build `manylinux`/cp311 wheels for the local
deploy; the CI pipeline runs on Linux so it packages natively — documented so the
distinction is explicit.

**#4 — CI container had no Node.** The first GitHub Actions run failed because the
`azure/cli` container lacks Node for the SQL runner. Fix: run that step on the
host runner (where `az` is already OIDC-authenticated and Node is present).

**#5 — Deploy determinism.** Made the API's Node startup command explicit in
Bicep so run-from-package deploys behave identically everywhere, instead of
relying on the platform's default detection.

---

## Proof (not claims)

- Local: 17 API tests + 8 Function tests passing; ruff/eslint clean; Bicep
  compiles; PowerShell AST-parses.
- Azure (dev, `centralus`): live smoke tests green — `/health`, `/health/ready`
  (SQL + Key Vault via MI), anonymous `401`, authorized `200` returning real
  Key Vault + SQL data; Function timer→Storage→`/api/summary`.
- CI/CD: GitHub Actions run **green end-to-end** (build → OIDC → Bicep →
  KV secret → SQL migration → app deploy → smoke), secretless.

---

## Walkthrough cheat-sheet (be ready to answer)

- **"Walk me through auth."** Client gets an Entra token (delegated `scp` or
  app `roles`); API validates signature/issuer/audience/expiry via JWKS; app→SQL
  and app→Key Vault use the API's Managed Identity — no secrets.
- **"How do you deploy with no stored credentials?"** OIDC federation: the
  pipeline exchanges a short-lived GitHub/ADO token for an Azure token; the
  federated identity is scoped to the resource group.
- **"How would you investigate an incident?"** App Insights (failures, deps,
  live metrics) + Log Analytics (KQL over diagnostic logs) + the three alerts
  (availability web test, app-failure, plan-CPU) → action group. Rollback =
  redeploy previous immutable artifact / re-run pipeline at prior commit.
- **"What would you do next for prod?"** Enable private networking
  (`enablePrivateNetworking=true` → private endpoints + DNS), add staging slots
  with swap, and per-environment approvals (already modeled in the ADO `prod`
  stage).
- **"What are the trade-offs?"** Dedicated plan (predictable + keyless storage)
  vs Consumption (cheaper, cold starts); Bicep (Azure-native) vs Terraform
  (multi-cloud); contained SQL users via T-SQL (ARM can't express them).
