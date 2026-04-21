resource "azurerm_eventhub_namespace" "this" {
  name                = "${var.prefix}-ehns"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  capacity            = 1
}

resource "azurerm_eventhub" "logs" {
  name                = "logs-appservice"
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = var.resource_group_name

  partition_count   = 2
  message_retention = 1
}
data "azurerm_eventhub_namespace_authorization_rule" "default" {
  name                = "RootManageSharedAccessKey"
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = var.resource_group_name
}

