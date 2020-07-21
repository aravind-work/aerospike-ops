variable "prefix" {
  type    = string
  default = "aerospike-eval"
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "ascluster" {
  type = map
  default = {
    "vm_type"         = "Standard_L48s_v2"
    "vm_count"        = "5"
    "disks_per_vm"    = "6"
    //"disk_type"       = "StandardSSD_LRS"
    "disk_type"       = "Premium_LRS"
    //"disk_type"       = "UltraSSD_LRS"
    //"disk_iops_read_write" = "5000"
    //"disk_mbps_read_write" = "500"
    "disk_size_gb"    = "2048"
    "disk_size_tb"    = "2T"

    "as_node_mem"     = "360G"
    "replication_factor" = "3"
    "write_block_size" = "64K"
  }
}

variable "loadgencluster" {
  type = map
  default = {
    "vm_type"  = "Standard_L16s_v2"
    "vm_count" = "6"
  }
}

variable private_ip_prefix {
  type    = string
  default = "10.0.1."
}
variable private_ip_reserved {
  type    = number
  default = 10
}

variable "dev_ips" {
  type    = list(string)
  default = ["192.150.10.0/24"]
  #home ip = "73.189.177.216"
}

variable "admin_username" {
  type    = string
  default = "aerospike"
}

variable "admin_password" {
  type    = string
  default = "Password123!"
}

variable "enable_ultra_ssd" {
  type    = string
  default = "false"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "owner" {
  type    = string
  default = "arsriram"
}

variable "team" {
  type    = string
  default = "uis"
}