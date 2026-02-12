output "vm_id" {
  value = azurerm_linux_virtual_machine.this.id
}

output "private_ip" {
  value = azurerm_network_interface.this.private_ip_address
}

output "public_ip_address" {
  description = "Public IP of the VM metrics"
  value       = azurerm_public_ip.this.ip_address
}

output "grafana_url" {
  value = "http://${azurerm_public_ip.this.ip_address}:3000"
}