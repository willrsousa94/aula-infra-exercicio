terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

resource "azurerm_resource_group" "wrs-aulainfracloud" {
  name     = "willexcloudinfra"
  location = "Central US"
}

resource "azurerm_virtual_network" "vnet-wrsinfra" {
  name                = "vnet-wrs"
  location            = azurerm_resource_group.wrs-aulainfracloud.location
  resource_group_name = azurerm_resource_group.wrs-aulainfracloud.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    environment = "Production"
    faculdade   = "impacta"
    turma       = "ES23"
  }
}

resource "azurerm_subnet" "sub-wrsinfra" {
  name                 = "sub-wrs"
  resource_group_name  = azurerm_resource_group.wrs-aulainfracloud.name
  virtual_network_name = azurerm_virtual_network.vnet-wrsinfra.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "ip-wrsinfra" {
  name                = "ip-wrs1"
  resource_group_name = azurerm_resource_group.wrs-aulainfracloud.name
  location            = azurerm_resource_group.wrs-aulainfracloud.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }
}

resource "azurerm_network_security_group" "nsg-wrsinfra" {
  name                = "nsg-wrs"
  location            = azurerm_resource_group.wrs-aulainfracloud.location
  resource_group_name = azurerm_resource_group.wrs-aulainfracloud.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "web"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "Production"
  }
}

resource "azurerm_network_interface" "nic-wrsinfra" {
  name                = "nic-wrs1"
  location            = azurerm_resource_group.wrs-aulainfracloud.location
  resource_group_name = azurerm_resource_group.wrs-aulainfracloud.name

  ip_configuration {
    name                          = "ip-wrs-nic"
    subnet_id                     = azurerm_subnet.sub-wrsinfra.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip-wrsinfra.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic-nsg-wrsinfra" {
  network_interface_id      = azurerm_network_interface.nic-wrsinfra.id
  network_security_group_id = azurerm_network_security_group.nsg-wrsinfra.id
}

resource "azurerm_virtual_machine" "vm-wrsinfra" {
  name                  = "vm-wrs"
  location              = azurerm_resource_group.wrs-aulainfracloud.location
  resource_group_name   = azurerm_resource_group.wrs-aulainfracloud.name
  network_interface_ids = [azurerm_network_interface.nic-wrsinfra.id]
  vm_size               = "Standard_D2ads_v5"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "hostname"
    admin_username = var.user
    admin_password = var.pwd_user
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "staging"
  }
}

data "azurerm_public_ip" "ip-wrs" {
  name                = azurerm_public_ip.ip-wrsinfra.name
  resource_group_name = azurerm_resource_group.wrs-aulainfracloud.name
}

resource "null_resource" "install-apache" {
  connection {
    type     = "ssh"
    host     = data.azurerm_public_ip.ip-wrs.ip_address
    user     = var.user
    password = var.pwd_user
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install -y apache2"
    ]
  }

  depends_on = [
    azurerm_virtual_machine.vm-wrsinfra
  ]
}

resource "null_resource" "upload-app" {
  connection {
    type     = "ssh"
    host     = data.azurerm_public_ip.ip-wrs.ip_address
    user     = var.user
    password = var.pwd_user
  }

  provisioner "file" {
    source      = "app"
    destination = "/home/testadmin"
  }

  depends_on = [
    azurerm_virtual_machine.vm-wrsinfra
  ]
}
