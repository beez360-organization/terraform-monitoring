##############################
# Outputs
##############################
output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "primary_access_key" {
  description = "Storage account key1 (primary access key)"
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}