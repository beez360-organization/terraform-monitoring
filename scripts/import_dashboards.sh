#!/bin/bash
set -e

grafana_url="$1"
api_key="$2"
DASHBOARDS_DIR="$3"

if [[ -z "$grafana_url" || -z "$api_key" || -z "$DASHBOARDS_DIR" ]]; then
  echo "Usage: $0 <grafana_url> <api_key> <dashboards_dir>"
  exit 1
fi

for dashboard_file in "$DASHBOARDS_DIR"/*.json; do
  echo "Importing dashboard $dashboard_file ..."
  DASH_JSON=$(jq -c '.' "$dashboard_file")
  
  RESPONSE=$(curl -s -X POST "${grafana_url}/api/dashboards/db" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $api_key" \
    -d "{\"dashboard\":$DASH_JSON,\"overwrite\":true}")

  echo "Response: $RESPONSE"
done
