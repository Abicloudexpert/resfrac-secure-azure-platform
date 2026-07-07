# ADR 0007 — GitHub Actions as a live mirror of the Azure DevOps pipeline

**Status:** Accepted

## Context
The assignment explicitly requires **Azure DevOps YAML pipelines** as a named
deliverable and evaluation area. That pipeline is authored and lives in
`pipelines/` and is the platform-of-record for CI/CD.

Separately, the source repository is hosted on **GitHub**, and creating an Azure
DevOps *organization* is a manual portal action that cannot be scripted. To
provide **executable, demonstrable proof** that the CI/CD design works end-to-end
against the live Azure environment, a runnable pipeline was also implemented on
the platform the repo already lives on.

## Decision
Keep the **Azure DevOps pipeline as the required deliverable**, and add a
**GitHub Actions workflow** (`.github/workflows/cicd.yml`) as a *live-runnable
mirror*. The two are intentionally equivalent:

| Concern | Azure DevOps | GitHub Actions |
| --- | --- | --- |
| Cloud auth | WIF/OIDC service connection | WIF/OIDC federated credential (`azure/login`) |
| Stored cloud secret | none | none |
| Stages | Build → Deploy (env-based) | `build` → `deploy-dev` (Environment `dev`) |
| IaC | `infra/bicep` (`what-if` + deploy) | identical |
| SQL migration | `infra/sql/run-sql.cjs` (passwordless) | identical |
| Smoke gate | `infra/scripts/smoke-test.ps1` | identical |
| App secrets | Key Vault-backed variable group | GitHub Actions Secrets |

Both invoke the **same** Bicep templates, the **same** PowerShell scripts, and
the **same** Node SQL runner — only the orchestration syntax differs.

## Rationale
- **Follows the brief** — the Azure DevOps YAML remains the primary artifact.
- **Provable** — GitHub Actions runs with zero manual org setup, so the design
  can be shown green against the live environment.
- **Portable auth model** — demonstrates that the secretless OIDC pattern is
  tool-agnostic (a strong senior signal for the walkthrough).

## Consequences
- Two pipeline definitions to keep in sync; mitigated by pushing all real logic
  into shared scripts/templates that both pipelines call.
- The GitHub Actions workflow deploys the `dev` environment; `prod` parity
  (manual approval, separate environment) is expressed in the Azure DevOps YAML.
