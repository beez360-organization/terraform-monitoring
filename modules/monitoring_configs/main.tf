# resource "null_resource" "configure_grafana" {
#   depends_on = [azurerm_virtual_machine.vm]
#
#   provisioner "local-exec" {
#     command = <<EOT
#       ./scripts/import_dashboards.sh \
#         --grafana-url ${var.grafana_url} \
#         --api-key ${var.grafana_api_key} \
#         --dashboards-dir ./grafana_dashboards
#     EOT
#   }
# }




data "template_file" "tempo_config" {
  template = file("${path.module}/monitoring_configs/tempo_config.yaml.tpl")

  vars = {
    storage_account_name = var.storage_account_name
    storage_account_key  = local.storage_account_key
  }
}

resource "local_file" "tempo_config_yaml" {
  content  = data.template_file.tempo_config.rendered
  filename = "${path.module}/generated/tempo_config.yaml"
}
