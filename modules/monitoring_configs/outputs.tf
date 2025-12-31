

output "loki_config" {
  value = data.template_file.loki_config.rendered
}

output "tempo_config" {
  value = data.template_file.tempo_config.rendered
}