resource "azurerm_key_vault" "this" {
  name                = "${var.prefix}-kv"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id

  sku_name = "standard"

  enable_rbac_authorization = false

  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = var.tags
}


