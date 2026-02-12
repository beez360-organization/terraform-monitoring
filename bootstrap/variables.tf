variable "location" {
  description = "Azure region for the Terraform state resources"
  type        = string
  default     = "francecentral"
}

variable "state_resource_group_name" {
  description = "Resource group name for Terraform state"
  type        = string
  default     = "rg-terraform-state"
}

variable "state_storage_account_name" {
  description = "Storage account name for Terraform state"
  type        = string
}

variable "state_container_name" {
  description = "Blob container name for Terraform state"
  type        = string
  default     = "tfstate"
}
