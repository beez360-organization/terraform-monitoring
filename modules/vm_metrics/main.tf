

##############################
# NSG
##############################
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.vm_name}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Prometheus
  security_rule {
    name                       = "AllowPrometheus"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "9090"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
  }

  # Node Exporter
  security_rule {
    name                       = "AllowNodeExporter"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "9100"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
  }

  # Grafana
  security_rule {
    name                       = "AllowGrafana"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "3000"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
  }

  # Promitor
  security_rule {
    name                       = "AllowPromitor"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "8080"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
  }

  # Loki
  security_rule {
    name                       = "AllowLoki"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "3100"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
  }

  # Tempo
  security_rule {
    name                       = "AllowTempo"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "3200"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
  }

  # SSH
  security_rule {
    name                       = "AllowSSH"
    priority                   = 160
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "22"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
  }

  # VNet
  security_rule {
    name                       = "AllowVnetInBound"
    priority                   = 2000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Azure LB
  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 2001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Deny all inbound
  security_rule {
    name                       = "DenyAllInBound"
    priority                   = 3000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
  }

  # OUTBOUND (corrigé)
  security_rule {
    name                       = "AllowInternetOutBound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllOutBound"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "*"
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
  domain_name_label = "beez360-dashboard"
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
    GRAFANA_URL        = var.grafana_url
    PROM_URL           = var.prometheus_url
    LOKI_URL           = var.loki_url
    PROM_NODE_EXPORTER = var.node_exporter_target
    PROM_PROMITOR      = var.promitor_target
    GITHUB_SSH_KEY     = var.github_ssh_key
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