#!/usr/bin/env bash
# =============================================================================
# publish-dashboards.sh — push observability/dashboards/*.json to Azure
# Managed Grafana, in the "Beez360" folder, overwriting previous versions.
# =============================================================================
# Auth: Entra ID of the caller (az login / OIDC in CI). The caller needs the
# Grafana Editor (or Admin) role on the instance. No API key.
#
# Usage: observability/scripts/publish-dashboards.sh <grafana-name> [resource-group]
# =============================================================================
set -euo pipefail

GRAFANA="${1:?usage: publish-dashboards.sh <grafana-name> [resource-group]}"
RG="${2:-beez360-frc-observability-rg}"
FOLDER="Beez360"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../dashboards" && pwd)"

az extension add --name amg --upgrade --only-show-errors >/dev/null

if ! az grafana folder show -n "$GRAFANA" -g "$RG" --folder "$FOLDER" >/dev/null 2>&1; then
  az grafana folder create -n "$GRAFANA" -g "$RG" --title "$FOLDER" --only-show-errors >/dev/null
  echo "✓ folder $FOLDER created"
fi

for file in "$DIR"/*.json; do
  az grafana dashboard create -n "$GRAFANA" -g "$RG" \
    --folder "$FOLDER" --definition "@$file" --overwrite true --only-show-errors >/dev/null
  echo "✓ $(basename "$file")"
done
