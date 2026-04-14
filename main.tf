terraform {
  required_version = ">= 1.2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.99"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstatebeez360"
    container_name       = "tfstate"
    key                  = "monitoring.tfstate"

    use_oidc = true
  }
}
data "azurerm_client_config" "current" {}
provider "azurerm" {
  features {}
    use_oidc = true

}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}
module "network" {
  source = "./modules/network"

  resource_group_name     = azurerm_resource_group.rg.name
  location                = var.location
  prefix                  = var.prefix
  vnet_cidr               = var.vnet_cidr
  metrics_subnet_cidr     = var.metrics_subnet_cidr
  logs_traces_subnet_cidr = var.logs_traces_subnet_cidr

  depends_on = [azurerm_resource_group.rg]
}

module "storage" {
  source               = "./modules/storage"
  resource_group_name  = azurerm_resource_group.rg.name
  location             = var.location
  storage_account_name = var.storage_account_name
  tags                 = var.tags

  depends_on = [azurerm_resource_group.rg]
}
module "keyvault" {
  source = "./modules/keyvault"

  prefix              = var.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  storage_account_key = module.storage.primary_access_key
  tags                = var.tags
  depends_on = [
  azurerm_resource_group.rg,
  module.storage
]
}
module "vm_logs_traces" {
  source               = "./modules/vm_logs_traces"
  resource_group_name  = azurerm_resource_group.rg.name
  location             = var.location
  subnet_id            = module.network.logs_traces_subnet_id
  vm_name              = "vm-logs-traces"
  admin_username       = var.admin_username
  admin_password       = var.admin_password
  storage_account_name = module.storage.storage_account_name
  storage_account_key  = module.storage.primary_access_key
  key_vault_name       = module.keyvault.key_vault_name
  tags                 = var.tags

  depends_on = [module.network, module.storage, module.keyvault]
}

module "vm_metrics" {
  source                = "./modules/vm_metrics"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = var.location
  subnet_id             = module.network.metrics_subnet_id
  vm_name               = "vm-metrics"
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  prometheus_target_ip  = module.vm_logs_traces.public_ip_address
  grafana_url           = "http://${module.vm_metrics.public_ip_address}:3000"
  prometheus_url        = "http://${module.vm_metrics.public_ip_address}:9090"
  loki_url              = "http://${module.vm_logs_traces.public_ip_address}:3100"
  node_exporter_target = "${module.vm_metrics.public_ip_address}:9100"
  promitor_target      = "${module.vm_metrics.public_ip_address}:8080"
  github_ssh_key = tls_private_key.github.private_key_pem
  tags                  = var.tags

  depends_on = [azurerm_resource_group.rg,module.network, module.storage, module.keyvault]
}

resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = module.keyvault.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete"
  ]
}
resource "tls_private_key" "github" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "azurerm_key_vault_secret" "github_ssh_key" {
  name         = "github-ssh-key"
  value        = tls_private_key.github.private_key_pem
  key_vault_id = module.keyvault.key_vault_id
  depends_on = [
    azurerm_key_vault_access_policy.terraform
  ]
}

resource "azurerm_key_vault_secret" "storage_key" {
  name         = "storage-account-key"
  value        = module.storage.primary_access_key
  key_vault_id = module.keyvault.key_vault_id

  depends_on = [
    azurerm_key_vault_access_policy.terraform
  ]
}