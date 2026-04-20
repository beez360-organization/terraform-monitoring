output "connection_string" {
  value     = azurerm_eventhub_namespace_authorization_rule.sap.primary_connection_string
  sensitive = true
}

