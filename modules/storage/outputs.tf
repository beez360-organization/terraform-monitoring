output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "primary_access_key" {
  value     = azurerm_storage_account.this.primary_access_key
  sensitive = true
}

output "logs_container_name" {
  value = azurerm_storage_container.logs.name
}

output "storage_account_id" {
  value = azurerm_storage_account.this.id
}

output "traces_container_name" {
  value = azurerm_storage_container.traces.name
}
