resource "azurerm_key_vault" "this" {
  name                = "${var.prefix}-kv"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id

  sku_name = "standard"

  rbac_authorization_enabled = true

  soft_delete_retention_days = 90
  purge_protection_enabled   = true
  tags                       = var.tags
}
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}


