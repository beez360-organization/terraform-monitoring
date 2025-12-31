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

variable "grafana_api_key" {
  description = "API Key for Grafana to import dashboards"
  type        = string
  sensitive   = true
}
variable "data_disk_size_gb" {
  type    = number
  default = 64
}

variable "prometheus_target_ip" {
  description = "IP address of the Prometheus target (vm_metrics or vm_logs_traces depending on context)"
  type        = string
} 

