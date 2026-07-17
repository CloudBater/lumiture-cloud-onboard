#!/usr/bin/env bash
#
# uninstall.sh — remove everything azure/init.sh created for ONE subscription.
#
# INTERNAL tooling: intended for repeated onboarding tests against a personal or test
# subscription, so a first-time run can be simulated over and over. It is deliberately
# NOT referenced from the customer-facing docs.
#
# Usage:
#   ./uninstall.sh --subscription-id <guid> [options]
#
#   --subscription-id <guid>   subscription to clean (required; no auto-detect on purpose)
#   --storage-account <name>   override (default: derived exactly as init.sh does)
#   --storage-rg <name>        override (default: lumiture-billing-rg)
#   --delete-storage           also delete the storage account (drops all export blobs).
#                              Needed for a TRUE virgin re-test; without it init.sh will
#                              reuse the existing account on the next run.
#   --yes                      skip the confirmation prompt
#   --dry-run                  print what would be removed, change nothing
#
# For a completely virgin subscription also remove the resource group afterwards:
#   az group delete --subscription <guid> --name lumiture-billing-rg --yes
# (that also takes any non-LumiTure resources living in that RG — check first.)
#
set -euo pipefail

readonly LUMITURE_APP_ID_PROD="c871cf6f-dd8d-487a-a908-a66245655b0e"
readonly LUMITURE_APP_ID_DEV="99e6a4c9-8c5b-4481-bd9b-522cd30ec3c3"
readonly ROLE_COST_READER="Cost Management Reader"
readonly ROLE_BLOB_READER="Storage Blob Data Reader"
readonly ROLE_USAGE_BASE="LumiTure FinOps Reader"
readonly CONTAINER="billing-export"
readonly EVENT_SUB_NAME="lumiture-billing-export"
readonly EXPORT_NAMES=("daily-actual-cost" "daily-focus-cost" "daily-amortized-cost")
# Every api-version an export may have been created under. Exports of different
# generations can share a name; see the delete loop below.
readonly EXPORT_API_VERSIONS=("2025-03-01" "2023-11-01" "2023-07-01-preview")

c_blu=$'\e[0;34m'; c_grn=$'\e[0;32m'; c_ylw=$'\e[0;33m'; c_red=$'\e[0;31m'; c_off=$'\e[0m'
log()  { printf "%b %s\n" "${c_blu}[lumiture]${c_off}" "$*" >&2; }
ok()   { printf "%b %s\n" "${c_grn}[ ok ]${c_off}"     "$*" >&2; }
warn() { printf "%b %s\n" "${c_ylw}[warn]${c_off}"     "$*" >&2; }
err()  { printf "%b %s\n" "${c_red}[err ]${c_off}"     "$*" >&2; }
die()  { err "$*"; exit 1; }

SUBSCRIPTION_ID=""; STORAGE_ACCOUNT=""; STORAGE_RG=""
DELETE_STORAGE=0; ASSUME_YES=0; DRY_RUN=0
REMOVED=(); FAILED=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription-id) SUBSCRIPTION_ID="$2"; shift 2 ;;
    --storage-account) STORAGE_ACCOUNT="$2"; shift 2 ;;
    --storage-rg) STORAGE_RG="$2"; shift 2 ;;
    --delete-storage) DELETE_STORAGE=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) die "Unknown argument: $1 (see --help)" ;;
  esac
done

[[ -n "${SUBSCRIPTION_ID}" ]] || die "Missing --subscription-id. This script deletes things; it will not guess the target."
command -v az >/dev/null || die "az CLI not found"
command -v jq >/dev/null || die "jq not found"

STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-ltexp$(printf '%s' "${SUBSCRIPTION_ID}" | tr -d '-' | cut -c1-15)}"
STORAGE_RG="${STORAGE_RG:-lumiture-billing-rg}"
readonly SCOPE="/subscriptions/${SUBSCRIPTION_ID}"

run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then log "DRY-RUN: $*"; return 0; fi
  "$@"
}

log "Uninstall target — subscription ${SUBSCRIPTION_ID}, storage ${STORAGE_ACCOUNT} (rg ${STORAGE_RG})"
az account set --subscription "${SUBSCRIPTION_ID}" -o none 2>/dev/null \
  || die "Cannot select subscription ${SUBSCRIPTION_ID} — run 'az login'."

if [[ "${ASSUME_YES}" -eq 0 && "${DRY_RUN}" -eq 0 ]]; then
  warn "This removes the LumiTure exports, Event Grid subscription, role assignments and"
  warn "custom usage role from subscription ${SUBSCRIPTION_ID}."
  [[ "${DELETE_STORAGE}" -eq 1 ]] && warn "It ALSO deletes storage account ${STORAGE_ACCOUNT} and every export blob in it."
  read -r -p "Continue? [y/N] " reply
  [[ "${reply}" =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }
fi

# -----------------------------------------------------------------------------
# 1 — Event Grid subscription (cut delivery first, so nothing fires mid-teardown)
# -----------------------------------------------------------------------------
log "Phase 1 — Removing Event Grid subscription '${EVENT_SUB_NAME}'…"
storage_id=$(az storage account show -n "${STORAGE_ACCOUNT}" -g "${STORAGE_RG}" --query id -o tsv 2>/dev/null || true)
if [[ -n "${storage_id}" ]]; then
  if az eventgrid event-subscription show --name "${EVENT_SUB_NAME}" --source-resource-id "${storage_id}" -o none 2>/dev/null; then
    if run az eventgrid event-subscription delete --name "${EVENT_SUB_NAME}" --source-resource-id "${storage_id}" -o none; then
      ok "  Event Grid subscription removed"; REMOVED+=("event-grid:${EVENT_SUB_NAME}")
    else
      warn "  Event Grid subscription delete failed"; FAILED+=("event-grid:${EVENT_SUB_NAME}")
    fi
  else
    log "  none found"
  fi
else
  log "  storage account not found — skipping"
fi

# -----------------------------------------------------------------------------
# 2 — Cost Management exports
# Exports of two API generations can COEXIST under the same name (legacy ids have no
# leading slash, newer ones do), and a delete-by-name always resolves to the legacy one.
# So delete each name in a loop until it is really gone, trying each api-version: one
# pass would silently leave the shadowed twin behind.
# -----------------------------------------------------------------------------
log "Phase 2 — Removing Cost Management exports…"
export_exists() {
  az rest --method get \
    --url "https://management.azure.com${SCOPE}/providers/Microsoft.CostManagement/exports?api-version=2023-07-01-preview" 2>/dev/null \
    | jq -e --arg n "$1" '.value // [] | map(select(.name == $n)) | length > 0' >/dev/null 2>&1
}
for name in "${EXPORT_NAMES[@]}"; do
  export_exists "${name}" || continue
  for _attempt in 1 2 3; do
    export_exists "${name}" || break
    deleted=0
    for v in "${EXPORT_API_VERSIONS[@]}"; do
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "DRY-RUN: delete export ${name} (api ${v})"; deleted=1; break
      fi
      if az rest --method delete \
          --url "https://management.azure.com${SCOPE}/providers/Microsoft.CostManagement/exports/${name}?api-version=${v}" \
          -o none 2>/dev/null; then
        deleted=1; break
      fi
    done
    [[ "${deleted}" -eq 1 ]] || break
    [[ "${DRY_RUN}" -eq 1 ]] && break
    sleep 2
  done
  if [[ "${DRY_RUN}" -eq 1 ]] || ! export_exists "${name}"; then
    ok "  export '${name}' removed"; REMOVED+=("export:${name}")
  else
    warn "  export '${name}' still present — delete it in the portal"; FAILED+=("export:${name}")
  fi
done

# -----------------------------------------------------------------------------
# 3 — Role assignments, LumiTure SPs only
# The subscription also carries assignments for the human owner and for the FOCUS
# export's own managed identity. Only ever touch LumiTure's service principals.
# -----------------------------------------------------------------------------
log "Phase 3 — Removing LumiTure role assignments…"
for app_id in "${LUMITURE_APP_ID_DEV}" "${LUMITURE_APP_ID_PROD}"; do
  sp_oid=$(az ad sp show --id "${app_id}" --query id -o tsv 2>/dev/null || true)
  [[ -n "${sp_oid}" ]] || { log "  SP ${app_id} not in this tenant — skipping"; continue; }
  # IFS=tab: every role name here contains spaces ("Cost Management Reader"), so the
  # default word-splitting would truncate it to "Cost" and delete the wrong thing.
  while IFS=$'\t' read -r role scope; do
    [[ -n "${role}" ]] || continue
    if run az role assignment delete --assignee "${sp_oid}" --role "${role}" --scope "${scope}" -o none 2>/dev/null; then
      ok "  removed '${role}' from ${app_id:0:8} at ${scope##*/}"; REMOVED+=("role-assignment:${role}")
    else
      warn "  could not remove '${role}' from ${app_id:0:8}"; FAILED+=("role-assignment:${role}")
    fi
  done < <(az role assignment list --all --assignee "${sp_oid}" \
             --query "[?contains(scope, '${SUBSCRIPTION_ID}')].[roleDefinitionName, scope]" -o tsv 2>/dev/null || true)
done

# -----------------------------------------------------------------------------
# 4 — Custom usage role definition(s)
# Delete only when THIS subscription is its sole assignableScope; otherwise another
# subscription still depends on it, so just drop our scope. Matching is client-side:
# `az role definition list --name` filters server-side and cannot match the
# per-subscription name (it contains parentheses).
# -----------------------------------------------------------------------------
log "Phase 4 — Removing custom usage role…"
per_sub_role="${ROLE_USAGE_BASE} (${SUBSCRIPTION_ID:0:8})"
visible=$(az role definition list --custom-role-only true -o json --only-show-errors 2>/dev/null || echo '[]')
for candidate in "${ROLE_USAGE_BASE}" "${per_sub_role}"; do
  def=$(printf '%s' "${visible}" | jq -c --arg n "${candidate}" '[.[] | select(.roleName == $n)] | first // empty')
  [[ -n "${def}" ]] || continue
  n_scopes=$(printf '%s' "${def}" | jq '.assignableScopes | length')
  if [[ "${n_scopes}" -le 1 ]]; then
    # Address by the definition's GUID rather than its display name — unambiguous, and it
    # sidesteps the server-side --name filter entirely.
    #
    # Do NOT verify by re-listing: RBAC deletes can take minutes to reflect, so an
    # immediate re-read reports a successful delete as "still present". Trust az's exit
    # code here (it does surface real failures) and tell the user about the lag.
    role_guid=$(printf '%s' "${def}" | jq -r '.name')
    if run az role definition delete --name "${role_guid}" --scope "${SCOPE}" -o none 2>/dev/null; then
      ok "  role definition '${candidate}' deleted (sole scope was this subscription)"; REMOVED+=("role-definition:${candidate}")
    else
      warn "  could not delete role definition '${candidate}'"; FAILED+=("role-definition:${candidate}")
    fi
  else
    log "  '${candidate}' also serves ${n_scopes} scopes — removing only this subscription's"
    shrunk=$(printf '%s' "${def}" | jq -c --arg s "${SCOPE}" '
      .assignableScopes = (.assignableScopes | map(select(. != $s)))
      | del(.createdOn, .updatedOn, .createdBy, .updatedBy, .type)')
    if run az role definition update --role-definition "${shrunk}" -o none 2>/dev/null; then
      ok "  '${candidate}' scope removed (definition kept for the other subscriptions)"; REMOVED+=("role-scope:${candidate}")
    else
      warn "  could not update role definition '${candidate}'"; FAILED+=("role-definition:${candidate}")
    fi
  fi
done

# -----------------------------------------------------------------------------
# 5 — Storage account (opt-in)
# -----------------------------------------------------------------------------
if [[ "${DELETE_STORAGE}" -eq 1 ]]; then
  log "Phase 5 — Deleting storage account ${STORAGE_ACCOUNT}…"
  if [[ -n "${storage_id}" ]]; then
    if run az storage account delete -n "${STORAGE_ACCOUNT}" -g "${STORAGE_RG}" --yes -o none 2>/dev/null; then
      ok "  storage account deleted"; REMOVED+=("storage:${STORAGE_ACCOUNT}")
      log "  NOTE: Azure holds a deleted storage-account name briefly — if the next init.sh"
      log "  run fails to create it, wait a few minutes rather than assuming a script bug."
    else
      warn "  storage account delete failed"; FAILED+=("storage:${STORAGE_ACCOUNT}")
    fi
  else
    log "  not found — skipping"
  fi
else
  log "Phase 5 — Keeping storage account (pass --delete-storage for a virgin re-test)"
fi

# -----------------------------------------------------------------------------
# Summary — never claim success we did not verify
# -----------------------------------------------------------------------------
echo >&2
log "Removed ${#REMOVED[@]} item(s):"
for r in "${REMOVED[@]:-}"; do [[ -n "${r}" ]] && log "  - ${r}"; done
if [[ "${#FAILED[@]}" -gt 0 ]]; then
  err "${#FAILED[@]} item(s) could NOT be removed:"
  for f in "${FAILED[@]}"; do err "  - ${f}"; done
  err "Uninstall INCOMPLETE — a re-run of init.sh may not behave like a first-time onboarding."
  exit 1
fi
ok "Uninstall complete — subscription ${SUBSCRIPTION_ID} is ready for a fresh init.sh run"
[[ "${DELETE_STORAGE}" -eq 0 ]] && log "(storage account kept — init.sh will reuse it; add --delete-storage for a true first-time test)"
exit 0
