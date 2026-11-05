variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
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
  type      = string
  sensitive = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
variable "ip_address" {
  type        = string
  description = "Optional static IP for the VM"
  default     = null
}

variable "data_disk_size_gb" {
  type    = number
  default = 64
}

variable "prometheus_target_ip" {
  description = "IP address of the Prometheus target "
  type        = string
}
variable "grafana_url" {
  type        = string
  description = "URL de Grafana"
}
variable "promitor_target" {
  type = string
}


variable "node_exporter_target" {
  type = string
}


variable "prometheus_url" {
  type        = string
  description = "URL de Prometheus"
}

variable "loki_url" {
  type        = string
  description = "URL de Loki"
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "CIDRs allowed on operator ports (Grafana 3000, NGINX 80, SSH 22). Empty = VNet-only."
  default     = []
}

variable "tenant_id" {
  type        = string
  description = "Azure AD tenant id (injected into the Promitor declaration)."
}

variable "subscription_id" {
  type        = string
  description = "Subscription Promitor scrapes (injected into the Promitor declaration)."
}

variable "monitored_resource_group" {
  type        = string
  description = "Resource group Promitor scrapes; also the scope granted to the VM's Managed Identity (Monitoring Reader). Empty = skip role assignment."
  default     = ""
}

variable "grafana_admin_password" {
  type        = string
  description = "Grafana admin password (generated upstream, stored in Key Vault)."
  sensitive   = true
}

variable "alert_webhook_url" {
  type        = string
  description = "Incoming webhook (Slack/Teams) for Grafana alert notifications. Empty = alerts are defined but not delivered until set."
  sensitive   = true
  default     = ""
}
