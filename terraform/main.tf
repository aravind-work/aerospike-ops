locals {
  tags = {
    environment = var.env
    owner       = var.owner
    team        = var.team
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  # The "feature" block is required for AzureRM provider 2.x. 
  # If you're using version 1.x, the "features" block is not allowed.
  version = "~>2.0"
  features {}
}

# Create a resource group if it doesn't exist
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = local.tags
}

# Create virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = local.tags
}

# Create subnet
resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create public IPs for Aerospike nodes
resource "azurerm_public_ip" "publicip" {
  count               = var.ascluster["vm_count"] + var.loadgencluster["vm_count"]
  name                = "${var.prefix}-publicip-${count.index}"
  domain_name_label   = "${var.prefix}-dn-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  tags                = local.tags
  zones               = [tostring("${( count.index % 3) + 1}")]
  sku                 = "Standard"
}
resource "local_file" "public_ip_file" {
  depends_on = [azurerm_public_ip.publicip]
  content    = join(", ", azurerm_public_ip.publicip.*.ip_address)
  filename   = "out/ips.txt"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

# Create Network Security rule and associate with NSG
resource "azurerm_network_security_rule" "ssh" {
  name                        = "ssh"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = var.dev_ips
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_security_rule" "amc" {
  name                        = "amc"
  priority                    = 2000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8081"
  source_address_prefixes     = var.dev_ips
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

# Create network interface
resource "azurerm_network_interface" "nic" {
  count                         = var.ascluster["vm_count"] + var.loadgencluster["vm_count"]
  name                          = "${var.prefix}-nic-${count.index}"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  enable_accelerated_networking = "true"
  ip_configuration {
    name                          = "${var.prefix}-ipconfiguration"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    public_ip_address_id          = azurerm_public_ip.publicip[count.index].id
    private_ip_address            = "${var.private_ip_prefix}${count.index + var.private_ip_reserved}"
  }
  tags = local.tags
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "nic-nsg-assoc" {
  count                     = var.ascluster["vm_count"] + var.loadgencluster["vm_count"]
  network_interface_id      = azurerm_network_interface.nic.*.id[count.index]
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.rg.name
  }
  byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "storageaccount" {
  name                     = "diag${random_id.randomId.hex}" # todo::rename
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = local.tags
}

# Create an SSH key and write to file
resource "tls_private_key" "sshprivatekey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create virtual machine for Aerospike
resource "azurerm_linux_virtual_machine" "aerovm" {
  count                 = var.ascluster["vm_count"]
  name                  = "${var.prefix}-vm-${count.index}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic.*.id[count.index]]
  size                  = var.ascluster["vm_type"]
  zone                  = tostring("${( count.index % 3) + 1}")

  additional_capabilities {
    ultra_ssd_enabled = var.enable_ultra_ssd
  }

  os_disk {
    name                 = "OsDisk-aerovm-${count.index}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  computer_name                   = "${var.prefix}-vm-${count.index}"
  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.sshprivatekey.public_key_openssh
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.storageaccount.primary_blob_endpoint
  }

  tags = local.tags

  # This is to ensure SSH comes up before we run the local exec.
  provisioner "remote-exec" {
    inline = ["echo 'Hello World'"]

    connection {
      type        = "ssh"
      host        = azurerm_public_ip.publicip.*.fqdn[count.index]
      user        = var.admin_username
      private_key = tls_private_key.sshprivatekey.private_key_pem
    }
  }
}

data "template_file" "snapshot_urls" {
  template = "${file("out/disk-snapshots.txt")}"
}

# Create Managed Disks
resource "azurerm_managed_disk" "datadisks" {
  count                = var.ascluster["vm_count"] * var.ascluster["disks_per_vm"]
  name                 = "${var.prefix}-datadisk-${count.index}"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_type = var.ascluster["disk_type"]
  disk_size_gb         = var.ascluster["disk_size_gb"]
  //create_option        = "Empty"
  source_resource_id =  trimspace(split(",", data.template_file.snapshot_urls.rendered)[count.index])
  //source_resource_id   = "/subscriptions/60631e84-1bf3-42ca-bacc-c5242b586725/resourceGroups/aerospike-eval2-rg/providers/Microsoft.Compute/snapshots/aerospike-eval2-datadisk-snapshot-${count.index}"
  create_option        = "Copy"
  //source_resource_id   = azurerm_snapshot.snapshots.*.id[count.index]
  tags                 = local.tags
  zones                = [element(azurerm_linux_virtual_machine.aerovm.*.zone, ceil((count.index + 1) * 1.0 / var.ascluster["disks_per_vm"]) - 1)]
}

# Attach disk to VM
resource "azurerm_virtual_machine_data_disk_attachment" "data-disk-attach" {
  count              = var.ascluster["vm_count"] * var.ascluster["disks_per_vm"]
  managed_disk_id    = azurerm_managed_disk.datadisks.*.id[count.index]
  virtual_machine_id = element(azurerm_linux_virtual_machine.aerovm.*.id, ceil((count.index + 1) * 1.0 / var.ascluster["disks_per_vm"]) - 1)
  lun                = count.index % var.ascluster["disks_per_vm"]
  caching            = "None"
  create_option      = "Attach"
  depends_on         = [azurerm_managed_disk.datadisks, azurerm_linux_virtual_machine.aerovm]
}


# Create virtual machine for load generator
resource "azurerm_linux_virtual_machine" "loadgenvm" {
  count                 = var.loadgencluster["vm_count"]
  name                  = "${var.prefix}-loadgen-vm-${count.index}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic.*.id[var.ascluster["vm_count"] + count.index]]
  size                  = var.loadgencluster["vm_type"]
  zone                  = tostring("${( (var.ascluster["vm_count"] + count.index) % 3) + 1}")

  depends_on = [
    azurerm_network_interface_security_group_association.nic-nsg-assoc
  ]

  additional_capabilities {
    ultra_ssd_enabled = false
  }

  os_disk {
    name = "OsDisk-loadgenvm-${count.index}"
    caching = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer = "UbuntuServer"
    sku = "16.04-LTS"
    version = "latest"
  }

  computer_name = "${var.prefix}-loadgen-vm-${count.index}"
  admin_username = var.admin_username
  admin_password = var.admin_password
  disable_password_authentication = true

  admin_ssh_key {
    username = var.admin_username
    public_key = tls_private_key.sshprivatekey.public_key_openssh
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.storageaccount.primary_blob_endpoint
  }

  tags = local.tags

  # This is to ensure SSH comes up before we run the local exec.
  provisioner "remote-exec" {
    inline = [
      "echo 'Hello World'"]

    connection {
      type = "ssh"
      host = azurerm_public_ip.publicip.*.fqdn[count.index]
      user = var.admin_username
      private_key = tls_private_key.sshprivatekey.private_key_pem
    }
  }
}

resource "azurerm_snapshot" "snapshots" {
  count                = var.create_snapshots ? var.ascluster["vm_count"] * var.ascluster["disks_per_vm"] : 0
  name                 = "${var.prefix}-datadisk-snapshot-${count.index}"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  create_option        = "Copy"
  source_resource_id   = azurerm_managed_disk.datadisks.*.id[count.index]
}
resource "local_file" "snapshot-locations-file" {
  count      = var.create_snapshots ? 1 : 0
  depends_on = [azurerm_snapshot.snapshots]
  content    = join(", ", azurerm_snapshot.snapshots.*.id)
  filename   = "out/disk-snapshots.txt"
}

# Use null resource to run provisioners - possible to taint without re-creating VMs
resource "null_resource" "provisioner-loadgen" {
  depends_on = [azurerm_linux_virtual_machine.loadgenvm]
  provisioner "local-exec" {
    command = "export ANSIBLE_HOST_KEY_CHECKING=False; ansible-playbook -i ../ansible/inventory.yaml --user ${var.admin_username} --private-key ${local_file.private_key_openssh.filename} ../ansible/loadgen.yaml"
  }
}
resource "null_resource" "provisioner-aerospike" {
  depends_on = [azurerm_linux_virtual_machine.aerovm, azurerm_virtual_machine_data_disk_attachment.data-disk-attach]
  provisioner "local-exec" {
    command = "export ANSIBLE_HOST_KEY_CHECKING=False; ansible-playbook -i ../ansible/inventory.yaml --user ${var.admin_username} --private-key ${local_file.private_key_openssh.filename} ../ansible/aerospike.yaml"
  }
}
resource "null_resource" "provisioner-amc" {
  depends_on = [null_resource.provisioner-aerospike]
  provisioner "local-exec" {
    command = "export ANSIBLE_HOST_KEY_CHECKING=False; ansible-playbook -i ../ansible/inventory.yaml --user ${var.admin_username} --private-key ${local_file.private_key_openssh.filename} ../ansible/amc.yaml"
  }
}



