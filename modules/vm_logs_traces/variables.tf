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


variable "storage_account_name" {
  type        = string
  description = "Name of the storage account (Loki/Tempo backend, accessed via Managed Identity)"
}

variable "storage_account_id" {
  type        = string
  description = "Resource ID of the storage account — used to grant the VM's Managed Identity Blob access"
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "CIDRs allowed on operator ports (SSH). Empty = VNet-only."
  default     = []
}

variable "key_vault_name" {
  type = string
}

variable "eventhub_connection_string" {
  type      = string
  sensitive = true
}