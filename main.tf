terraform {
  required_version = ">= 1.2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
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

# ============================================================================
# GENERATED SECRETS (no secret is committed to git anymore)
# Source of truth = Key Vault. The VM admin password and the Grafana admin
# password are generated here and stored in KV. They are still passed to the
# VMs via cloud-init for bootstrap; the next hardening step is to have the VMs
# fetch them from KV at boot via their Managed Identity (custom_data is
# retrievable by anyone with Reader on the VM).
# ============================================================================
resource "random_password" "vm_admin" {
  length           = 24
  special          = true
  override_special = "!#$%*()-_=+[]{}:?"
}

resource "random_password" "grafana_admin" {
  length           = 24
  special          = true
  override_special = "!#$%*()-_=+[]{}:?"
}

locals {
  vm_admin_password = var.admin_password != null ? var.admin_password : random_password.vm_admin.result
}

resource "azurerm_key_vault_secret" "vm_admin_password" {
  name         = "vm-admin-password"
  value        = local.vm_admin_password
  key_vault_id = module.keyvault.key_vault_id

  depends_on = [module.keyvault]
}

resource "azurerm_key_vault_secret" "grafana_admin_password" {
  name         = "grafana-admin-password"
  value        = random_password.grafana_admin.result
  key_vault_id = module.keyvault.key_vault_id

  depends_on = [module.keyvault]
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

  vm_name               = "vm-logs-traces"
  admin_username        = var.admin_username
  admin_password        = local.vm_admin_password
  allowed_ingress_cidrs = var.allowed_ingress_cidrs

  # Loki/Tempo reach Blob via the VM's Managed Identity (no account key).
  storage_account_name       = module.storage.storage_account_name
  storage_account_id         = module.storage.storage_account_id
  eventhub_connection_string = module.eventhub.connection_string
  key_vault_name             = module.keyvault.key_vault_name
  data_disk_size_gb          = var.data_disk_size_gb
  tags                       = var.tags

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
  admin_password        = local.vm_admin_password
  allowed_ingress_cidrs = var.allowed_ingress_cidrs

  # Promitor scrapes Azure Monitor for this tenant/subscription/RG via the
  # VM's Managed Identity (granted Monitoring Reader below).
  tenant_id                = data.azurerm_client_config.current.tenant_id
  subscription_id          = var.subscription_id
  monitored_resource_group = var.monitored_resource_group
  grafana_admin_password   = random_password.grafana_admin.result
  alert_webhook_url        = var.alert_webhook_url
  data_disk_size_gb        = var.data_disk_size_gb

  prometheus_target_ip = module.vm_logs_traces.private_ip
  grafana_url          = "http://${module.vm_metrics.public_ip_address}:3000"
  prometheus_url       = "http://localhost:9090"
  loki_url             = "http://${module.vm_logs_traces.private_ip}:3100"
  node_exporter_target = "localhost:9100"
  promitor_target      = "localhost:8080"
  tags                 = var.tags

  depends_on = [azurerm_resource_group.rg, module.network, module.storage, module.keyvault]
}


