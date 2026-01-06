resource "azurerm_network_security_group" "nsg" {
  name                = "${var.vm_name}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Autorise Prometheus
  security_rule {
    name                       = "AllowPrometheus"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9090"
    source_address_prefix      = "*" # À restreindre selon besoin
    destination_address_prefix = "*"
  }

  # Autorise Grafana
  security_rule {
    name                       = "AllowGrafana"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*" # À restreindre
    destination_address_prefix = "*"
  }

  # Autorise Loki
  security_rule {
    name                       = "AllowLoki"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3100"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Autorise Tempo
  security_rule {
    name                       = "AllowTempo"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3200"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Autorise SSH
  security_rule {
    name                       = "AllowSSH"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*" # À restreindre idéalement à IPs des VMs
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = var.subnet_id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_public_ip" "this" {
  name                = "${var.vm_name}-public-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

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
}

data "template_file" "cloud_init" {
  template = file("${path.module}/cloud-init.yaml")

   vars = {
    grafana_url          = "http://${azurerm_public_ip.this.ip_address}:3000"
    api_key              = var.grafana_api_key
    prometheus_target_ip = var.prometheus_target_ip
    admin_password       = var.admin_password
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
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

  custom_data = base64encode(data.template_file.cloud_init.rendered)

  tags = var.tags
}

resource "azurerm_managed_disk" "data_disk" {
  name                 = "${var.vm_name}-data-disk"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = "Standard_LRS"  
  create_option        = "Empty"
  disk_size_gb         = 64              
  tags                 = var.tags
}


resource "azurerm_virtual_machine_data_disk_attachment" "data_disk_attachment" {
  managed_disk_id    = azurerm_managed_disk.data_disk.id
  virtual_machine_id = azurerm_linux_virtual_machine.this.id
  lun                = 0
  caching            = "ReadWrite"
  create_option      = "Attach"
}

resource "null_resource" "copy_dashboards" {
  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = var.admin_username
      password = var.admin_password
      host     = azurerm_public_ip.this.ip_address
    }
    inline = [
      "mkdir -p /tmp/grafana_dashboards"
    ]
  }

  provisioner "file" {
    source      = "${path.module}/../monitoring_configs/grafana_dashboards"
    destination = "/tmp"
    connection {
      type     = "ssh"
      user     = var.admin_username
      password = var.admin_password
      host     = azurerm_public_ip.this.ip_address
    }
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = var.admin_username
      password = var.admin_password
      host     = azurerm_public_ip.this.ip_address
    }
    inline = [
      "sudo mkdir -p /etc/grafana/dashboards",
      "sudo cp -r /tmp/grafana_dashboards/* /etc/grafana/dashboards/",
      "sudo chown -R grafana:grafana /etc/grafana/dashboards",
      "rm -rf /tmp/grafana_dashboards"
    ]
  }
}

resource "null_resource" "generate_grafana_api_key" {
  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      host     = azurerm_public_ip.this.ip_address
      user     = var.admin_username
      password = var.admin_password
    }

    inline = [
      "sudo apt-get update && sudo apt-get install -y jq",
      "API_KEY=$(curl -s -X POST \"http://localhost:3000/api/auth/keys\" -u admin:${var.admin_password} -H \"Content-Type: application/json\" -d '{\"name\":\"terraform-import\",\"role\":\"Admin\",\"secondsToLive\":86400}' | jq -r '.key')",
      "echo $API_KEY | sudo tee /etc/grafana/api_key"
    ]
  }

  depends_on = [azurerm_linux_virtual_machine.this, azurerm_network_interface.this]
}


