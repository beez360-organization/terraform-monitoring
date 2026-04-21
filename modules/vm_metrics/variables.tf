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
