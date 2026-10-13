locals {
  # Operator ports (Grafana, NGINX, SSH) restricted to this allowlist;
  # empty list = VNet-only (no public exposure).
  admin_is_vnet = length(var.allowed_ingress_cidrs) == 0
}

##############################
# NSG — data ports VNet-only, operator ports allowlisted (no public 0.0.0.0/0)
##############################
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.vm_name}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # --- Data plane: intra-VNet only ---
  security_rule {
    name                       = "AllowPrometheusVnet"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9090"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowNodeExporterVnet"
    priority                   = 310
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9100"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowPromitorVnet"
    priority                   = 320
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAlertmanagerVnet"
    priority                   = 330
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9093"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # --- Operator: Grafana / NGINX / SSH from the allowlist (or VNet when empty) ---
  security_rule {
    name                       = "AllowGrafana"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = local.admin_is_vnet ? "VirtualNetwork" : null
    source_address_prefixes    = local.admin_is_vnet ? null : var.allowed_ingress_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowNginx"
    priority                   = 410
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = local.admin_is_vnet ? "VirtualNetwork" : null
    source_address_prefixes    = local.admin_is_vnet ? null : var.allowed_ingress_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSH"
    priority                   = 420
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.admin_is_vnet ? "VirtualNetwork" : null
    source_address_prefixes    = local.admin_is_vnet ? null : var.allowed_ingress_cidrs
    destination_address_prefix = "*"
  }

  # --- Baseline ---
  security_rule {
    name                       = "AllowVnetInBound"
    priority                   = 2000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 2001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInBound"
    priority                   = 3000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

##############################
# NSG association
##############################
resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = var.subnet_id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

##############################
# Public IP
##############################
resource "azurerm_public_ip" "this" {
  name                = "${var.vm_name}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  domain_name_label   = "beez360-dashboard"
  sku                 = "Standard"
  tags                = var.tags
}

##############################
# NIC
##############################
resource "azurerm_network_interface" "this" {
  name                = "${var.vm_name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id
  }

  tags = var.tags
}

##############################
# Cloud-init
##############################
locals {
  cloud_init = templatefile("${path.module}/cloud-init.yaml.tpl", {
    GRAFANA_URL            = var.grafana_url
    PROM_URL               = var.prometheus_url
    LOKI_URL               = var.loki_url
    PROM_NODE_EXPORTER     = var.node_exporter_target
    PROM_PROMITOR          = var.promitor_target
    TENANT_ID              = var.tenant_id
    SUBSCRIPTION_ID        = var.subscription_id
    MONITORED_RG           = var.monitored_resource_group
    GRAFANA_ADMIN_PASSWORD = var.grafana_admin_password
    ALERT_WEBHOOK_URL      = var.alert_webhook_url
  })
}

##############################
# VM
##############################
resource "azurerm_linux_virtual_machine" "this" {
  name                = var.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = "Standard_B2s"

  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.this.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 32
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(local.cloud_init)

  tags = var.tags
}

##############################
# Managed Identity → Azure Monitor (Promitor scraping)
# Monitoring Reader on the observed resource group.
##############################
resource "azurerm_role_assignment" "promitor_monitoring_reader" {
  count = var.monitored_resource_group != "" ? 1 : 0

  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${var.monitored_resource_group}"
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_linux_virtual_machine.this.identity[0].principal_id
}

##############################
# Data disk (resilience) — Prometheus TSDB + Grafana DB survive VM recreation.
# Premium SSD, mounted at /data by cloud-init.
##############################
resource "azurerm_managed_disk" "data" {
  name                 = "${var.vm_name}-data"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
  tags                 = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_linux_virtual_machine.this.id
  lun                = 0
  caching            = "ReadWrite"
}
