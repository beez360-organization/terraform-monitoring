data "template_file" "loki_config" {
  template = file("${path.module}/loki_config.yaml.tpl")
  vars = {
    storage_account_name = var.storage_account_name
    storage_account_key  = var.storage_account_key
  }
}

data "template_file" "tempo_config" {
  template = file("${path.module}/tempo_config.yaml.tpl")
  vars = {
    storage_account_name = var.storage_account_name
    storage_account_key  = var.storage_account_key
  }
}

resource "local_file" "loki_config_yaml" {
  content  = data.template_file.loki_config.rendered
  filename = "${path.module}/generated/loki-config.yaml"
}

resource "local_file" "tempo_config_yaml" {
  content  = data.template_file.tempo_config.rendered
  filename = "${path.module}/generated/tempo-config.yaml"
}


