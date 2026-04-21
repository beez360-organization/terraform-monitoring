output "connection_string" {
  value     = data.azurerm_eventhub_namespace_authorization_rule.default.primary_connection_string
  sensitive = true
}