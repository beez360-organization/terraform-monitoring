output "resource_group_name" {
  description = "Nom du groupe de ressources créé"
  value       = var.resource_group_name
}

output "vm_metrics_id" {
  description = "ID de la VM Metrics"
  value       = module.vm_metrics.vm_id
}

output "vm_metrics_ip" {
  description = "IP privée de la VM Metrics"
  value       = module.vm_metrics.private_ip
}

output "vm_logs_traces_id" {
  description = "ID de la VM Logs/Traces"
  value       = module.vm_logs_traces.vm_id
}

output "vm_logs_traces_ip" {
  description = "IP privée de la VM Logs/Traces"
  value       = module.vm_logs_traces.private_ip
}

output "primary_storage_key" {
  description = "Clé primaire du compte de stockage"
  value       = local.storage_account_key
  sensitive   = true
}
