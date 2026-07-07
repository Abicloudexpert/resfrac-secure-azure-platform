# ADR 0001 — Infrastructure as Code with Bicep

**Status:** Accepted

## Context
We need IaC for an Azure-only estate that is readable, modular, and easy to
integrate into an Azure DevOps pipeline.

## Decision
Use **Bicep** (modular, with `main.bicep` orchestrating per-concern modules and
per-environment `.bicepparam` files).

## Rationale
- Azure-native; **no state backend** to secure/manage (unlike Terraform).
- First-class, same-day support for new ARM resource types and properties.
- Native `what-if` for safe change previews in the pipeline.
- Compiles to ARM; transparent and auditable.

## Consequences
- Tied to Azure (acceptable — the assignment is Azure-specific).
- Team must know Bicep (well-documented, small surface area).
- Multi-cloud would require a rethink (not a current requirement).
