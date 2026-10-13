variable "subscription_id" {
  description = "Subscription hosting the observability resources (Grafana, action group)"
  type        = string
}

variable "location" {
  description = "Region of the observability resources"
  type        = string
  default     = "francecentral"
}

variable "monitored_subscription_ids" {
  description = "Beez360 subscriptions Grafana reads (prod + nonprod + legacy). Grafana gets Monitoring Reader on each."
  type        = list(string)

  validation {
    condition     = length(var.monitored_subscription_ids) > 0
    error_message = "At least one subscription must be monitored."
  }
}

variable "grafana_name" {
  description = "Azure Managed Grafana instance name (2-23 chars, globally unique endpoint)"
  type        = string
  default     = "beez360-grafana"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,21}[a-zA-Z0-9]$", var.grafana_name))
    error_message = "grafana_name must be 2-23 alphanumerics or hyphens, starting with a letter."
  }
}

variable "grafana_sku" {
  description = "Essential (no instance fee, 20 dashboards, no Grafana alerting/SLA) or Standard (SLA, private endpoint, SMTP, unlimited)"
  type        = string
  default     = "Essential"

  validation {
    condition     = contains(["Essential", "Standard"], var.grafana_sku)
    error_message = "grafana_sku must be Essential or Standard."
  }
}

variable "grafana_major_version" {
  description = "Grafana major version of the managed instance"
  type        = string
  default     = "11"
}

variable "grafana_zone_redundancy_enabled" {
  description = "Zone redundancy (Standard only)"
  type        = bool
  default     = false
}

variable "grafana_admin_group_object_ids" {
  description = "Entra ID groups with the Grafana Admin role"
  type        = list(string)
  default     = []
}

variable "grafana_editor_group_object_ids" {
  description = "Entra ID groups with the Grafana Editor role"
  type        = list(string)
  default     = []
}

variable "grafana_viewer_group_object_ids" {
  description = "Entra ID groups with the Grafana Viewer role"
  type        = list(string)
  default     = []
}

variable "alert_email_receivers" {
  description = "E-mail addresses of the central ops action group"
  type        = list(string)
  default     = []
}

variable "alert_webhook_url" {
  description = "Teams / Slack incoming webhook of the central ops action group (TF_VAR_alert_webhook_url, never in git)"
  type        = string
  default     = null
  sensitive   = true
}

variable "service_health_regions" {
  description = "Azure regions watched by the Service Health alert"
  type        = list(string)
  default     = ["France Central", "Global"]
}

variable "tags" {
  description = "Extra tags"
  type        = map(string)
  default     = {}
}
