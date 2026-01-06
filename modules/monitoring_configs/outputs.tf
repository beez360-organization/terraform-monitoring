
output "loki_config_path" {
  value = local_file.loki_config_yaml.filename
}

output "tempo_config_path" {
  value = local_file.tempo_config_yaml.filename
}


output "primary_storage_key" {
  value = var.storage_account_key
}
