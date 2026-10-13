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

# Least-privilege SAS for Fluent Bit: Listen only (no Send, no Manage),
# scoped to the single `logs` event hub — replaces the namespace-wide
# RootManageSharedAccessKey that was previously handed to the VM.
resource "azurerm_eventhub_authorization_rule" "fluentbit_listen" {
  name                = "fluentbit-listen"
  namespace_name      = azurerm_eventhub_namespace.this.name
  eventhub_name       = azurerm_eventhub.logs.name
  resource_group_name = var.resource_group_name

  listen = true
  send   = false
  manage = false
}