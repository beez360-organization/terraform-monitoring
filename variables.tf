variable "resource_group_name" {
  description = "Nom du groupe de ressources"
  type        = string
  default     = "rg-monitoring"
}

variable "location" {
  description = "Région Azure"
  type        = string
  default     = "francecentral"
}

variable "regions" {
  description = "Liste des régions Azure"
  type        = map(string)
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
  description = "Optional override for the VM admin password. Leave null to auto-generate a strong password (stored in Key Vault). NEVER commit a real value."
  type        = string
  sensitive   = true
  default     = null
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach operator ports (Grafana 3000, NGINX 80, SSH 22). Empty = VNet-only (no public access). Data-plane ports (Prometheus, Loki, Tempo, OTLP) are always VNet-only."
  type        = list(string)
  default     = []
}

variable "monitored_resource_group" {
  description = "Resource group that Promitor scrapes via Azure Monitor (the platform RG to observe)."
  type        = string
  default     = ""
}

variable "alert_webhook_url" {
  description = "Incoming webhook (Slack/Teams) for Grafana alerts. Empty = rules defined but not delivered. Prefer setting via TF_VAR_alert_webhook_url (it's secret-ish)."
  type        = string
  sensitive   = true
  default     = ""
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
  default     = "Standard_B2s"
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

variable "logs_traces_ip" {

  default = ""

}
variable "subscription_id" {
  description = "Azure subscription id Promitor scrapes (set in tfvars or TF_VAR_subscription_id — not hardcoded)."
  type        = string
}
variable "key_vault_name" {
  type = string
}