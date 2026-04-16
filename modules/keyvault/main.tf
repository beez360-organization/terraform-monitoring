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

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.this.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete"
  ]
    depends_on = [
    azurerm_key_vault.this
  ]

}
