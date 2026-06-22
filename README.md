# LumiTure Cloud Onboarding — Internal (full / multi-env)

> 🔒 **Internal CloudMile repo.** Full, multi-env version of the cloud onboarding tooling — supports **all environments** (`prod`/`dev`/`staging`/`sandbox`) and carries internal notes.
>
> **The customer-facing public version is [`CloudMile-Product/lumiture-cloud-onboard`](https://github.com/CloudMile-Product/lumiture-cloud-onboard)** — prod-only, clean, no internal references. Keep customer-facing changes flowing there; this repo is for internal use (multi-env testing, dev/staging/sandbox runs).

This repo holds **one sibling flow per cloud** under its own folder. They share a consistent shape (a guided entry point + the same "form values" contract the in-product wizard expects) but each runs on its cloud's native surface — we deliberately do **not** couple credential ceremonies into one apply.

## Clouds

| Cloud | Folder | Native surface | Customer grant | IaC | Status |
|---|---|---|---|---|---|
| **GCP** | [`gcp/`](gcp/) | Google Cloud Shell | IAM on existing BQ export (`bigquery.dataViewer` + `billing.viewer`) | Terraform | ✅ Live |
| **Azure** | [`azure/`](azure/) | Azure Cloud Shell + browser admin-consent | Admin-consent + Cost Management Reader + Storage Blob Data Reader + cost export + Event Grid subscription | Bicep | 🧪 POC (validated on sandbox 2026-06-22) |
| **AWS** | — | CloudFormation Launch-Stack / AWS CloudShell | Cross-account IAM role (+ ExternalId) | CloudFormation | ⬜ Planned |

Start with the per-cloud README:
- **[`gcp/README.md`](gcp/README.md)** — discovery + IAM grant + form values (`--env` selects SA + API base)
- **[`azure/README.md`](azure/README.md)** — open Azure Cloud Shell → admin-consent → guided grant + export + event subscription

## Environments

`--env` (bash) / `lumiture_environment` (TF) selects the target — this is the internal repo's reason to exist (the public repo is prod-only):

| env | GCP service account | API base |
|---|---|---|
| `prod` | `lumiture-client@tw-rd-app-finops-prod` | `https://api.lumiture.ai` |
| `dev` / `staging` | `lumiture-client@tw-rd-app-finops-dev` | `https://dev-api…` / `https://stg-api…` |
| `sandbox` | `lumiture-client@tw-rd-app-finops-dev` | `https://sandbox-api…` |

For Azure, `--lumiture-app-id` overrides the multi-tenant SP (sandbox/dev uses `99e6a4c9-8c5b-4481-bd9b-522cd30ec3c3`); `--event-trigger-url` (or `--lumiture-api` + `--lumiture-jwt`) wires the env-specific billing event-trigger Function.

## Why per-cloud, not one unified apply

Each cloud's grant is structurally different (GCP IAM on a BQ dataset; Azure admin-consent + RBAC + a cost export + an Event Grid subscription; AWS a cross-account role), runs on a different native surface, and lands data through a different path. Forcing them into a single apply would couple independent credential ceremonies and forfeit the zero-credential property each native shell provides. **What is shared** is the *packaging and contract*, not the execution.

Recorded as an ADR in the LumiTure specs repo: `infra/decisions/0001-per-cloud-onboarding-surfaces.md`.

## Relationship to other repos

- **Public client repo:** [`CloudMile-Product/lumiture-cloud-onboard`](https://github.com/CloudMile-Product/lumiture-cloud-onboard) (prod-only, what customers run via the Cloud Shell badge).
- **Specs / design:** LumiTure specs repo, `changes/gcp-onboarding-automation/` (+ `multi-cloud-onboarding-draft.md`).

## License

Apache-2.0.
