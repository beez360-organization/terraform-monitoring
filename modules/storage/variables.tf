variable "resource_group_name" {
  description = "Nom du Resource Group"
  type        = string
}

variable "location" {
  description = "Région Azure"
  type        = string
}

variable "storage_account_name" {
  description = "Nom du Storage Account (unique Azure)"
  type        = string
}

variable "tags" {
  description = "Tags des ressources"
  type        = map(string)
  default     = {}
}
