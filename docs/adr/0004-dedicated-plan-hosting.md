# ADR 0004 — Dedicated App Service Plan hosting for API + Function

**Status:** Accepted

## Context
The Function must be passwordless (ADR 0003) and, in prod, reach data services
over a private network. Consumption/Elastic-Premium Functions require an Azure
Files **content share** (`WEBSITE_CONTENTAZUREFILECONNECTIONSTRING`) which is
awkward to make fully keyless and complicates private networking.

## Decision
Host **both** the Node API and the Python Function on a **single Linux Dedicated
App Service Plan**.

## Rationale
- Dedicated hosting does **not** require the Files content share, so
  `AzureWebJobsStorage` can be **identity-based** (keyless) end-to-end.
- Enables **regional VNet integration** for private egress.
- Removes cold starts for the API; a shared plan keeps cost reasonable.

## Consequences
- Small always-on compute cost vs Consumption's scale-to-zero. Acceptable and
  cost-shared across two apps.
- Scaling is plan-level (scale out/up) rather than per-execution. For spiky,
  independent Function load, split onto its own plan or move to Flex Consumption
  with identity-based storage (future option).
