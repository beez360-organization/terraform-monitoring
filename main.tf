terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-monitoring"
  location = var.location
}




module "network" {
  source = "./modules/network"

  resource_group_name       = var.resource_group_name
  location                  = var.location
  prefix                    = var.prefix
  vnet_cidr                 = var.vnet_cidr
  metrics_subnet_cidr       = var.metrics_subnet_cidr
  logs_traces_subnet_cidr   = var.logs_traces_subnet_cidr
}

module "vm_metrics" {
  source              = "./modules/vm_metrics"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = module.network.metrics_subnet_id
  vm_name             = "vm-metrics"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  grafana_api_key = var.grafana_api_key
  prometheus_target_ip = module.vm_logs_traces.public_ip_address

  tags                = var.tags
}

module "vm_logs_traces" {
  source              = "./modules/vm_logs_traces"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = module.network.logs_traces_subnet_id
  vm_name             = "vm-logs-traces"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  tags                = var.tags
}


module "storage" {
  source              = "./modules/storage"
  resource_group_name = var.resource_group_name
  location            = var.location

  storage_account_name = var.storage_account_name
  tags                = var.tags
}


