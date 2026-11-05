output "grafana_endpoint" {
  description = "Grafana URL (Entra ID SSO)"
  value       = azurerm_dashboard_grafana.this.endpoint
}

output "grafana_name" {
  description = "Grafana instance name (for `az grafana dashboard ...`)"
  value       = azurerm_dashboard_grafana.this.name
}

output "resource_group_name" {
  description = "Observability resource group"
  value       = azurerm_resource_group.this.name
}

output "ops_action_group_id" {
  description = "Central action group — set as alert_action_group_id in the platforms to route all alerts to one place"
  value       = azurerm_monitor_action_group.ops.id
}
