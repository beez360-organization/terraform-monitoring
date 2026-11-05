terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 5.0"
    }
  }

  # Same state account as the legacy monitoring stack, separate key:
  # both stacks run side by side until the legacy VMs are decommissioned.
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstatebeez360"
    container_name       = "tfstate"
    key                  = "observability.tfstate"
    use_oidc             = true
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  use_oidc        = true
  features {}
}
