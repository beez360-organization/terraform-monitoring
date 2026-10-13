output "connection_string" {
  value     = azurerm_eventhub_authorization_rule.fluentbit_listen.primary_connection_string
  sensitive = true
}