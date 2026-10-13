locals {
  # Operator ports (SSH) are restricted to this allowlist; empty list = VNet-only.
  admin_is_vnet = length(var.allowed_ingress_cidrs) == 0
}

##############################
# NSG — data ports are VNet-only, SSH is allowlisted (no public 0.0.0.0/0)
##############################
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.vm_name}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # --- Data plane: intra-VNet only ---
  security_rule {
    name                       = "AllowLokiVnet"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3100"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowTempoVnet"
    priority                   = 310
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3200"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowOtlpVnet"
    priority                   = 320
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "4317"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # --- Operator: SSH from the allowlist (or VNet-only when empty) ---
  security_rule {
    name                       = "AllowSSH"
    priority                   = 400
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
    name                       = "AllowAzureLoadBalancerInBound"
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
  sku                 = "Standard"
  tags                = var.tags
  domain_name_label   = "${var.vm_name}-loki"
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

  # No storage account KEY in cloud-init anymore — Loki uses Managed Identity.
  # Fluent Bit ships to the local Loki (127.0.0.1). Event Hub SAS is Listen-only.
  custom_data = base64encode(
    replace(
      replace(
        replace(
          file("${path.module}/cloud-init.yaml.tpl"),
          "__STORAGE_ACCOUNT_NAME__", var.storage_account_name
        ),
        "__EVENTHUB_SAS__", var.eventhub_connection_string
      ),
      "__VM_LOGS_IP__", "127.0.0.1"
    )
  )

  tags = var.tags
}

##############################
# Managed Identity → Blob (Loki/Tempo) — replaces the storage account key
##############################
resource "azurerm_role_assignment" "vm_blob" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.this.identity[0].principal_id
}

##############################
# Data disk (resilience) — Loki index/cache/compactor survive VM recreation.
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
