variable "resource_group_name" {
  description = "Nom du groupe de ressources"
  type        = string
}

variable "location" {
  description = "Région Azure"
  type        = string
  default     = "francecentral"
}

variable "regions" {
  description = "Liste des régions Azure"
  type = map(string)
  default = {
    france_centrale = "France Central"
    europe_west     = "West Europe"
  }
}



variable "prefix" {
  description = "Préfixe utilisé pour les ressources"
  type        = string
}

variable "vnet_cidr" {
  description = "CIDR du réseau virtuel"
  type        = string
}

variable "metrics_subnet_cidr" {
  description = "CIDR du subnet metrics"
  type        = string
}

variable "logs_traces_subnet_cidr" {
  description = "CIDR du subnet logs & traces"
  type        = string
}

variable "admin_username" {
  description = "Nom d'utilisateur administrateur des VMs"
  type        = string
}

variable "admin_password" {
  description = "Mot de passe admin des VMs"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags pour les ressources"
  type        = map(string)
  default     = {}
}

variable "storage_account_name" {
  description = "Nom du compte de stockage"
  type        = string
}

variable "vm_size" {
  description = "Taille des machines virtuelles"
  type        = string
  default     = "Standard_B1s"
}

variable "data_disk_size_gb" {
  description = "Taille du disque de données (GB)"
  type        = number
  default     = 128
}

variable "image_publisher" {
  description = "Éditeur de l'image OS"
  type        = string
  default     = "Canonical"
}

variable "image_offer" {
  description = "Offre de l'image OS"
  type        = string
  default     = "UbuntuServer"
}

variable "image_sku" {
  description = "SKU de l'image OS"
  type        = string
  default     = "20.04-LTS"
}
