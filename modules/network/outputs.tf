output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "metrics_subnet_id" {
  value = azurerm_subnet.metrics.id
}

output "logs_traces_subnet_id" {
  value = azurerm_subnet.logs_traces.id
}
