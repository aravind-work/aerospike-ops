# Write the ssh keys tofile
resource "local_file" "public_key_openssh" {
  depends_on 		= [tls_private_key.sshprivatekey]
  content    		= tls_private_key.sshprivatekey.public_key_openssh
  filename   		= "out/id_rsa_tf.pub"
  file_permission	= "0600"
}
resource "local_file" "private_key_openssh" {
  depends_on 		= [tls_private_key.sshprivatekey]
  content    		= tls_private_key.sshprivatekey.private_key_pem
  filename   		= "out/id_rsa_tf"
  file_permission	= "0600"
}

# Write the ansible inventory file
data "template_file" "ansible_inventory" {
  template = "[as]\n$${as_ips}\n\n[as_dns]\n$${as_dns}\n\n[as_private]\n$${as_private_ips}\n\n[amc]\n$${amc_host}\n\n[loadgen]\n$${loadgen_ips}\n\n[loadgen_dns]\n$${loadgen_dns}\n\n[loadgen_private]\n$${loadgen_private_ips}"

  vars = {
    as_ips = join("\n", slice(azurerm_public_ip.publicip.*.ip_address, 0, var.ascluster["vm_count"]))
    as_dns = join("\n", slice(azurerm_public_ip.publicip.*.fqdn, 0, var.ascluster["vm_count"]))
    as_private_ips = join("\n", slice(azurerm_network_interface.nic.*.private_ip_address, 0, var.ascluster["vm_count"]))

    amc_host = azurerm_public_ip.publicip[0].fqdn

    loadgen_ips	= join("\n", slice(azurerm_public_ip.publicip.*.ip_address, var.ascluster["vm_count"], var.ascluster["vm_count"] + var.loadgencluster["vm_count"]))
    loadgen_dns	= join("\n", slice(azurerm_public_ip.publicip.*.fqdn, var.ascluster["vm_count"], var.ascluster["vm_count"] + var.loadgencluster["vm_count"]))
    loadgen_private_ips	= join("\n", slice(azurerm_network_interface.nic.*.private_ip_address, var.ascluster["vm_count"], var.ascluster["vm_count"] + var.loadgencluster["vm_count"]))
  }
}
resource "local_file" "ansible_inventory" {
  depends_on 		= [azurerm_public_ip.publicip]
  content    		= data.template_file.ansible_inventory.rendered
  filename   		= "../ansible/inventory.yaml"
  file_permission	= "0700"
}

#Write ansible vars file for common role
resource "local_file" "ansible_vars" {
  content    		= "real_user: ${var.admin_username}\nreplication_factor: ${var.ascluster["replication_factor"]}\nwrite_block_size: '${var.ascluster["write_block_size"]}'\nmemory_size: '${var.ascluster["as_node_mem"]}'\nmanaged_disk_size: '${var.ascluster["disk_size_tb"]}'\ndisks_per_vm: ${var.ascluster["disks_per_vm"]}"
  filename   		= "../ansible/roles/common/vars/tf-vars.yaml"
  file_permission	= "0700"
}