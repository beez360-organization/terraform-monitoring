output "connection_string" {
  value     = azurerm_eventhub_authorization_rule.fluentbit.primary_connection_string
  sensitive = true
}