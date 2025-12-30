



variable "prometheus_alert_rules_path" {
  description = "Chemin vers fichiers YAML règles alerting Prometheus"
  type        = string
  default     = "./prometheus_alert_rules"
}

variable "loki_config_path" {
  description = "Chemin vers fichier config Loki"
  type        = string
  default     = "./loki_config.yaml"
}

variable "tempo_config_path" {
  description = "Chemin vers fichier config Tempo"
  type        = string
  default     = "./tempo_config.yaml"
}



