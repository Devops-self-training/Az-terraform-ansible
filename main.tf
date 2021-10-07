#Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}



#Create resource group
resource "azurerm_resource_group" "rg" {
  name     = "lab1ResourceGroup"
  location = "southeastasia"
  tags = {
    Environment = "dev"
    Team        = "DevOps"
  }
}

#Create Virtual NetWork
resource "azurerm_virtual_network" "vnet" {
  name = "lab1vnet"

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  #set address space
  address_space = ["10.0.0.0/16"]
}

##Create window VM
resource "azurerm_virtual_machine" "windowVm" {
  name = "lab1windowVm"

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  network_interface_ids = [azurerm_network_interface.windowNic.id]
  vm_size               = "Standard_F2"

  storage_os_disk {
    name              = "osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }

  os_profile {
    computer_name  = "lab1Window"
    admin_username = var.admin_username
    admin_password = var.admin_password
    custom_data    = file("./files/winrm.ps1")
  }

    os_profile_windows_config {
    provision_vm_agent = true
    winrm {
      protocol = "http"
    }
    # Auto-Login's required to configure WinRM
    additional_unattend_config {
      pass         = "oobeSystem"
      component    = "Microsoft-Windows-Shell-Setup"
      setting_name = "AutoLogon"
      content      = "<AutoLogon><Password><Value>${var.admin_password}</Value></Password><Enabled>true</Enabled><LogonCount>1</LogonCount><Username>${var.admin_username}</Username></AutoLogon>"
    }

    # Unattend config is to enable basic auth in WinRM, required for the provisioner stage.
    additional_unattend_config {
      pass         = "oobeSystem"
      component    = "Microsoft-Windows-Shell-Setup"
      setting_name = "FirstLogonCommands"
      content      = file("./files/FirstLogonCommands.xml")
    }
  }

  connection {
    host     = azurerm_public_ip.windowPublicIp.ip_address
    type     = "winrm"
    port     = 5985
    https    = false
    timeout  = "15m"
    user     = var.admin_username
    password = var.admin_password

  }

  provisioner "file" {
    source      = "files/config.ps1"
    destination = "c:/terraform/config.ps1"
  }

  provisioner "remote-exec" {
    on_failure = continue
    inline = [
      "powershell.exe -ExecutionPolicy Bypass -File C:/terraform/config.ps1",      
    ]
  }

  provisioner "local-exec" {
    command = "terraform output -json > ./ansible/data/ip.json; export ANSIBLE_HOST_KEY_CHECKING=False ;ansible-playbook -i ./ansible/hosts ./ansible/main.yml"
  }

}
#Create window public ip
resource "azurerm_public_ip" "windowPublicIp" {
  name = "lab1WindowPublicIp"

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  allocation_method = "Static"

}



##Create linux VM
resource "azurerm_virtual_machine" "linuxVm" {
  name = "lab1LinuxVm"

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  network_interface_ids = [azurerm_network_interface.linuxNic.id]
  vm_size               = "Standard_DS1_v2"

  storage_os_disk {
    name              = "linuxOsDisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_profile {
    computer_name  = "lab1Linux"
    admin_username = var.admin_username
    admin_password = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

}

#Create linux Subnet
resource "azurerm_subnet" "linuxSubnet" {
  name = "lab1linuxSubnet"

  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}


#Create linux public ip
resource "azurerm_public_ip" "linuxPublicIp" {
  name = "lab1LinuxPublicIp"

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  allocation_method = "Static"

}


#Create network interface for linux
resource "azurerm_network_interface" "linuxNic" {
  name = "lab1linuxNic"

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name


  ip_configuration {
    name                          = "linuxNicConfg"
    subnet_id                     = azurerm_subnet.linuxSubnet.id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = azurerm_public_ip.linuxPublicIp.id
  }
}


#Create window Subnet
resource "azurerm_subnet" "windowSubnet" {
  name = "lab1windowSubnet"

  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}



#Create network interface for window
resource "azurerm_network_interface" "windowNic" {
  name = "lab1WindowNic"

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "windowNicConfg"
    subnet_id                     = azurerm_subnet.windowSubnet.id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = azurerm_public_ip.windowPublicIp.id
  }
}



# Create Network Security Group and rule
resource "azurerm_network_security_group" "linuxNsg" {
  name                = "customLinuxNsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

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
    name                       = "Allow-ping-rule"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

# Create Network Security Group and rule for window
resource "azurerm_network_security_group" "windowNsg" {
  name                = "customWindowNsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "windown-rule"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [5985, 22, 3389]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-ping-rule"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# connect network security group to linux network interface
resource "azurerm_network_interface_security_group_association" "unix" {
  network_interface_id      = azurerm_network_interface.linuxNic.id
  network_security_group_id = azurerm_network_security_group.linuxNsg.id

}

# connect network security group to linux network interface
resource "azurerm_network_interface_security_group_association" "win" {
  network_interface_id      = azurerm_network_interface.windowNic.id
  network_security_group_id = azurerm_network_security_group.windowNsg.id
}



variable "admin_username" {
  type        = string
  description = "Administrator user name for virtual machine"
  default     = "hoangld7"
}

variable "admin_password" {
  type        = string
  description = "Password must meet Azure complexity requirements"
  default     = "Dinhhoang1207"

}


output "public_ip_linux" {
  value = azurerm_public_ip.linuxPublicIp.ip_address
}

output "public_ip_window" {
  value = azurerm_public_ip.windowPublicIp.ip_address
}
