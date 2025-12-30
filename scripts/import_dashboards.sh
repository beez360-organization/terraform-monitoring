#!/bin/bash
set -e

GRAFANA_URL="$1"
API_KEY="$2"
DASHBOARDS_DIR="$3"

if [[ -z "$GRAFANA_URL" || -z "$API_KEY" || -z "$DASHBOARDS_DIR" ]]; then
  echo "Usage: $0 <grafana_url> <api_key> <dashboards_dir>"
  exit 1
fi

for dashboard_file in "$DASHBOARDS_DIR"/*.json; do
  echo "Importing dashboard $dashboard_file ..."
  DASH_JSON=$(jq -c '.' "$dashboard_file")
  
  RESPONSE=$(curl -s -X POST "${GRAFANA_URL}/api/dashboards/db" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "{\"dashboard\":$DASH_JSON,\"overwrite\":true}")

  echo "Response: $RESPONSE"
done
