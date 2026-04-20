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


resource "azurerm_eventhub_namespace_authorization_rule" "sap" {
  name                = "RootManageSharedAccessKey"
  resource_group_name = var.resource_group_name
  namespace_name      = azurerm_eventhub_namespace.this.name

  listen = true
  send   = true
  manage = true
}