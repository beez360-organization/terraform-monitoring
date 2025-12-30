variable "resource_group_name" {
  type        = string
  description = "Nom du Resource Group"
}

variable "location" {
  type        = string
  description = "Région Azure"
}

variable "prefix" {
  type        = string
  description = "Préfixe de nommage"
}

variable "vnet_cidr" {
  type        = string
  description = "CIDR du VNet"
}

variable "metrics_subnet_cidr" {
  type        = string
  description = "CIDR du subnet Metrics"
}

variable "logs_traces_subnet_cidr" {
  type        = string
  description = "CIDR du subnet Logs/Traces"
}
