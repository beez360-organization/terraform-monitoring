variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}
variable "vm_size" {
  description = "Taille des machines virtuelles"
  type        = string
  default     = "Standard_B2s"
}


variable "subnet_id" {
  type = string
}

variable "vm_name" {
  type = string
}

variable "admin_username" {
  type = string
}

variable "admin_password" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "data_disk_size_gb" {
  description = "Taille du disque data pour Loki / Tempo"
  type        = number
  default     = 50
}


variable "storage_account_key" {
  type        = string
  description = "Primary key of the storage account"
}

variable "storage_account_name" {
  type        = string
  description = "Name of the storage account"
}

variable "key_vault_name" {
  type = string
}

variable "eventhub_connection_string" {
  type      = string
  sensitive = true
}