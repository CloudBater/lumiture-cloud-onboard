# LumiTure GCP Onboarding — Internal (full / multi-env)

> 🔒 **Internal CloudMile repo.** Full version of the GCP onboarding tooling — supports **all environments** (`prod`/`dev`/`staging`/`sandbox`) and carries internal notes.
>
> **The customer-facing public version is [`CloudMile-Product/lumiture-gcp-onboard`](https://github.com/CloudMile-Product/lumiture-gcp-onboard)** — prod-only, clean, no internal references. Keep customer-facing changes flowing there; this repo is for internal use (multi-env testing, dev/staging/sandbox runs).

## What's in this repo

| File | Purpose |
|---|---|
| `tutorial.md` | Cloud Shell guided walkthrough |
| `onboard-wrapper.sh` | Interactive bash wrapper |
| `lumiture-gcp-onboard.sh` | Onboarding script — discovery + IAM grant + form values. `--env prod\|dev\|staging\|sandbox` selects the SA + API base. |
| `terraform/` | Terraform module (multi-env via `lumiture_environment`) |

## What it does

1. Discovers the Cloud Billing Account and BigQuery export dataset
2. Validates the export is producing data
3. Grants `BigQuery Data Viewer` on the export datasets **and** `Billing Account Viewer` (`roles/billing.viewer`) on the billing account to LumiTure's read-only service account — both required by the integration validation
4. Prints the form values to paste into the LumiTure wizard (or auto-submits)

## Environments

`--env` (bash) / `lumiture_environment` (TF) selects the target:

| env | service account | API base |
|---|---|---|
| `prod` | `lumiture-client@tw-rd-app-finops-prod` | `https://api.lumiture.ai` |
| `dev` / `staging` | `lumiture-client@tw-rd-app-finops-dev` | `https://dev-api…` / `https://stg-api…` |
| `sandbox` | `lumiture-client@tw-rd-app-finops-dev` | `https://sandbox-api…` |

## Relationship to other repos

- **Public client repo:** `CloudMile-Product/lumiture-gcp-onboard` (prod-only, what customers run via the Cloud Shell badge).
- **Specs / design:** LumiTure specs repo, `changes/gcp-onboarding-automation/`.

## License

Apache-2.0.
