# =============================================================================
# Beez360 observability — Azure-native (v2)
# =============================================================================
# Replaces the self-hosted LGTM VMs (Prometheus + Promitor + Loki + Tempo +
# Event Hub) with what the platforms ALREADY produce and pay for:
#   - platform metrics          → Azure Monitor metrics (free)
#   - App Service / PG logs     → each platform's Log Analytics workspace
#   - traces / requests         → workspace-based Application Insights
# Grafana only READS them, through its managed identity. Alerting lives in
# Azure Monitor (platform module `enable_alerts`, + service health below), so
# it keeps working even if Grafana is down.
#
# Runs side by side with the legacy stack (root of this repo, other state
# key). Decommission the legacy VMs once the dashboards are validated.
# =============================================================================

locals {
  tags = merge(var.tags, {
    Project   = "beez360"
    Purpose   = "observability"
    ManagedBy = "opentofu"
  })

  # Grafana role → Entra ID groups
  grafana_role_groups = merge(
    { for id in var.grafana_admin_group_object_ids : "admin-${id}" => { role = "Grafana Admin", principal = id } },
    { for id in var.grafana_editor_group_object_ids : "editor-${id}" => { role = "Grafana Editor", principal = id } },
    { for id in var.grafana_viewer_group_object_ids : "viewer-${id}" => { role = "Grafana Viewer", principal = id } },
  )
}

resource "azurerm_resource_group" "this" {
  name     = "beez360-frc-observability-rg"
  location = var.location
  tags     = local.tags
}

# -----------------------------------------------------------------------------
# Azure Managed Grafana
# Essential: no instance fee (active users only), Azure data sources, max 20
# dashboards, no Grafana alerting/SLA → enough here because alerting is in
# Azure Monitor. Switch to Standard (X1) for SLA / private endpoint / SMTP.
# -----------------------------------------------------------------------------
resource "azurerm_dashboard_grafana" "this" {
  name                  = var.grafana_name
  resource_group_name   = azurerm_resource_group.this.name
  location              = var.location
  sku                   = var.grafana_sku
  grafana_major_version = var.grafana_major_version

  # Entra ID SSO only: no API keys; dashboards are pushed with `az grafana` (Entra auth).
  api_key_enabled               = false
  public_network_access_enabled = true
  zone_redundancy_enabled       = var.grafana_sku == "Standard" ? var.grafana_zone_redundancy_enabled : false

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

# Grafana reads metrics + logs of every Beez360 subscription (prod & nonprod)
# with its own identity — no service principal secret, no scraper VM.
resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  for_each = toset(var.monitored_subscription_ids)

  scope                = "/subscriptions/${each.value}"
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

# The deploying identity (CI) publishes the dashboards with `az grafana`.
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "deployer_grafana_admin" {
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "grafana_users" {
  for_each = local.grafana_role_groups

  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal
}

# -----------------------------------------------------------------------------
# Central alert routing (Teams / e-mail). Platforms can point their alerts
# here (platform module input alert_action_group_id) instead of creating one
# action group each.
# -----------------------------------------------------------------------------
resource "azurerm_monitor_action_group" "ops" {
  name                = "beez360-ops-ag"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "bz360ops"
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = toset(var.alert_email_receivers)
    content {
      name                    = "email-${replace(email_receiver.value, "/[^a-zA-Z0-9]/", "-")}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  dynamic "webhook_receiver" {
    for_each = var.alert_webhook_url != null ? [1] : []
    content {
      name                    = "chatops"
      service_uri             = var.alert_webhook_url
      use_common_alert_schema = true
    }
  }
}

# Azure incidents / planned maintenance affecting the services Beez360 uses,
# in its regions (free).
resource "azurerm_monitor_activity_log_alert" "service_health" {
  for_each = toset(var.monitored_subscription_ids)

  name                = "beez360-service-health-${substr(each.value, 0, 8)}"
  resource_group_name = azurerm_resource_group.this.name
  location            = "global"
  scopes              = ["/subscriptions/${each.value}"]
  description         = "Azure Service Health: incidents and maintenance on Beez360 services"
  tags                = local.tags

  criteria {
    category = "ServiceHealth"

    service_health {
      events    = ["Incident", "Maintenance", "Security"]
      locations = var.service_health_regions
      services = [
        "App Service",
        "Azure Database for PostgreSQL flexible servers",
        "Key Vault",
        "Storage",
        "Container Registry",
        "Azure Monitor",
      ]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }
}
