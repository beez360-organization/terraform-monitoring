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
module "eventhub" {
  source = "./modules/eventhub"

  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location

  depends_on = [azurerm_resource_group.rg]
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
  source              = "./modules/vm_logs_traces"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  subnet_id           = module.network.logs_traces_subnet_id

  vm_name        = "vm-logs-traces"
  admin_username = var.admin_username
  admin_password = var.admin_password

  storage_account_name = module.storage.storage_account_name
  storage_account_key  = module.storage.primary_access_key
  eventhub_connection_string = module.eventhub.connection_string
  key_vault_name = module.keyvault.key_vault_name
  tags           = var.tags



  depends_on = [
    module.network,
    module.storage,
    module.keyvault,
    module.eventhub
  ]
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
  tags                  = var.tags

  depends_on = [azurerm_resource_group.rg,module.network, module.storage, module.keyvault]
}


