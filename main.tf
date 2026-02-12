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
  }
}

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

  resource_group_name     = var.resource_group_name
  location                = var.location
  prefix                  = var.prefix
  vnet_cidr               = var.vnet_cidr
  metrics_subnet_cidr     = var.metrics_subnet_cidr
  logs_traces_subnet_cidr = var.logs_traces_subnet_cidr

  depends_on = [azurerm_resource_group.rg]
}

module "storage" {
  source               = "./modules/storage"
  resource_group_name  = var.resource_group_name
  location             = var.location
  storage_account_name = var.storage_account_name
  tags                 = var.tags

  depends_on = [azurerm_resource_group.rg]
}

module "vm_logs_traces" {
  source               = "./modules/vm_logs_traces"
  resource_group_name  = var.resource_group_name
  location             = var.location
  subnet_id            = module.network.logs_traces_subnet_id
  vm_name              = "vm-logs-traces"
  admin_username       = var.admin_username
  admin_password       = var.admin_password
  storage_account_name = module.storage.storage_account_name
  storage_account_key  = module.storage.primary_access_key
  tags                 = var.tags

  depends_on = [module.storage]
}

module "vm_metrics" {
  source                = "./modules/vm_metrics"
  resource_group_name   = var.resource_group_name
  location              = var.location
  subnet_id             = module.network.metrics_subnet_id
  vm_name               = "vm-metrics"
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  prometheus_target_ip  = module.vm_logs_traces.public_ip_address
  grafana_url           = "http://${module.vm_metrics.public_ip_address}:3000"
  prometheus_url        = "http://${module.vm_metrics.public_ip_address}:9090"
  loki_url              = "http://${module.vm_logs_traces.public_ip_address}:3100"
  tags                  = var.tags

  depends_on = [azurerm_resource_group.rg]
}
