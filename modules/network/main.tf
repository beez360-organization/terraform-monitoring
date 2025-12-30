resource "azurerm_virtual_network" "this" {
  name                = "${var.prefix}-vnet"
  address_space       = [var.vnet_cidr]
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "metrics" {
  name                 = "${var.prefix}-metrics-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.metrics_subnet_cidr]
}

resource "azurerm_subnet" "logs_traces" {
  name                 = "${var.prefix}-logs-traces-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.logs_traces_subnet_cidr]
}
