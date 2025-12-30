output "vm_id" {
  description = "ID de la VM Logs/Traces"
  value       = azurerm_linux_virtual_machine.vm.id
}


output "private_ip" {
  description = "IP privée de la VM Logs/Traces"
  value       = azurerm_network_interface.nic.private_ip_address
}
output "public_ip_address" {
  value = azurerm_public_ip.this.ip_address
}
