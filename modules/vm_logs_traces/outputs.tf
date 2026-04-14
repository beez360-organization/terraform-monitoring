output "vm_id" {
  description = "ID de la VM Logs/Traces"
  value       = azurerm_linux_virtual_machine.this.id
}

output "private_ip" {
  description = "IP privée de la VM Logs/Traces"
  value       = azurerm_network_interface.this.private_ip_address
}
output "public_ip_address" {
  value = azurerm_public_ip.this.ip_address
}
output "principal_id" {
  value = azurerm_linux_virtual_machine.this.identity[0].principal_id
}
