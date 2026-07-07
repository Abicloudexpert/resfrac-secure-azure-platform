# AI-Assisted Development Disclosure

Per the assignment's AI-Assisted Development Policy, this documents how AI
tooling was used. The use of AI does not diminish authorship: **every design
decision, line of code, and configuration here is understood and defensible**,
and I can explain and modify any of it during the walkthrough.

## Tools used

- An AI coding assistant (Claude-based, via the Cursor IDE) was used as a
  pair-programming aid to scaffold boilerplate, accelerate documentation, and
  cross-check Azure API versions and best practices.

## How it was used

- **Scaffolding & boilerplate**: initial structure of the Express app, the
  Bicep modules, PowerShell scripts, and pipeline templates.
- **Review & hardening**: prompting for security best practices (passwordless
  patterns, least-privilege RBAC, JWT validation completeness) and refining
  accordingly.
- **Documentation**: drafting README/ADRs/runbook, which were then edited for
  accuracy against the actual implementation.

## What was verified by a human (not assumed)

To keep the submission "facts, not assumptions", the generated artifacts were
**executed and validated locally** rather than trusted blindly:

- API: `npm ci`, `npm run lint`, `npm test` → 17 passing tests, lint clean.
- Function: `pytest`, `ruff check` → 8 passing tests, lint clean.
- Bicep: compiled with the Bicep CLI (`bicep build`) → no warnings/errors; both
  `.bicepparam` files validated.
- PowerShell: all scripts parsed with the PowerShell AST parser → no errors.
- Pipeline YAML: parsed → valid.
- Diagrams: rendered from Mermaid source to SVG/PNG.

## Design decisions I own (examples I can defend in depth)

- Why **Bicep** over Terraform for an Azure-only estate.
- Why a **Dedicated App Service Plan** enables identity-based (keyless) Function
  storage without an Azure Files content share.
- The exact **JWT validation** steps and why `scp` **and** `roles` are checked.
- Why **Storage shared-key access is disabled** and how the Functions host still
  works (identity-based `AzureWebJobsStorage__*`).
- Why SQL **contained users** are created via T-SQL (ARM limitation) and the
  admin-identity requirement that follows.

See [`docs/adr/`](./adr) for the recorded decisions and their trade-offs.

## Reproducing

All verification commands are listed in the root
[`README.md` → Verification](../README.md#verification).
