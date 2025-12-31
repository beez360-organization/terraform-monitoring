



variable "prometheus_alert_rules_path" {
  description = "Chemin vers fichiers YAML règles alerting Prometheus"
  type        = string
  default     = "./prometheus_alert_rules"
}

variable "storage_account_name" {
  type = string
}

variable "storage_account_key" {
  type = string
}

variable "loki_address" {
  type = string
}

variable "prometheus_targets" {
  type    = list(string)
  default = []
}




