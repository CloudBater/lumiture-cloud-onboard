# LumiTure Cloud Onboarding — internal dev fork

> ### ⚠️ This is not the repo you want
>
> This is the **internal development fork**, and it shares its name with the real one.
> Customers and anyone onboarding for real should use the canonical repo:
>
> ### 👉 **<https://github.com/CloudMile-Product/lumiture-cloud-onboard>**
>
> This fork adds internal multi-environment switches (`--env dev|staging|sandbox`) that
> point the onboarding at **non-production** LumiTure endpoints. Running it against a real
> customer would wire their billing data to the wrong environment. It also carries
> `uninstall.sh`, which exists to tear a test subscription down and is not part of the
> customer flow. See [`INTERNAL.md`](INTERNAL.md).

> 繁體中文（IT SOP）：[`README.zh-TW.md`](README.zh-TW.md)

> Guided, low-install, customer-driven onboarding flows that grant [LumiTure](https://app.lumiture.ai) **read-only** access to a customer's cloud **billing/cost data** — each on that cloud's own native surface, in the customer's own identity. LumiTure never sees the customer's credentials.

This repo holds **one sibling flow per cloud**. They share a consistent shape (a guided entry point + the same "form values" contract the in-product wizard expects) but each runs on its cloud's native surface — we deliberately do **not** couple three credential ceremonies into one apply. See the [decision record](#design-decision).

## Clouds

| Cloud | Folder | Native surface | Customer grant | IaC | Status |
|---|---|---|---|---|---|
| **GCP** | [`gcp/`](gcp/) | Google Cloud Shell ([badge](gcp/README.md#try-it)) | IAM on existing BQ export | Terraform | ✅ Live |
| **Azure** | [`azure/`](azure/) | Azure Cloud Shell + browser admin-consent | Admin-consent + Cost Management Reader + Storage Blob Data Reader | Bicep | ✅ Live |
| **AWS** | — | CloudFormation Launch-Stack / AWS CloudShell | Cross-account IAM role (+ ExternalId) | CloudFormation | ⬜ Planned |

Start with the per-cloud README:
- **[`gcp/README.md`](gcp/README.md)** — "Open in Cloud Shell" badge → guided grant
- **[`azure/README.md`](azure/README.md)** — open Azure Cloud Shell → clone → guided grant

## Why per-cloud, not one unified apply

Each cloud's grant is structurally different (GCP IAM on a BQ dataset; Azure admin-consent + RBAC + a cost export; AWS a cross-account role), runs on a different native surface, and lands data through a different path. Forcing them into a single Terraform apply or one Cloud Shell run would couple three independent credential ceremonies and forfeit the zero-credential property each native shell provides.

**What is shared** is the *packaging and contract*, not the execution: a consistent variable/output shape per cloud, and a parallel same-shaped onboarding flow.

## License

MIT — see [`LICENSE`](LICENSE).
