# --- vSphere placement (discovered from vcsa01 via govc) ----------------------
variable "vsphere_server" {
  description = "vCenter FQDN"
  type        = string
}
variable "vsphere_datacenter" {
  description = "Datacenter name"
  type        = string
}
variable "vsphere_cluster" {
  description = "Compute cluster name"
  type        = string
}
variable "vsphere_resource_pool" {
  description = "Resource pool name (under the cluster)"
  type        = string
}
variable "vsphere_datastore" {
  description = "Datastore for OS + Longhorn data disks (all-NFS per design)"
  type        = string
}
variable "vsphere_network" {
  description = "Distributed portgroup for the cluster (VLAN 23)"
  type        = string
}
variable "vsphere_folder" {
  description = "VM folder (relative to the datacenter vm/ root)"
  type        = string
}
variable "vsphere_template" {
  description = "Talos OVA template to clone"
  type        = string
}

# --- Cluster networking -------------------------------------------------------
variable "network_gateway" {
  description = "Default gateway for the node subnet"
  type        = string
}
variable "network_prefix" {
  description = "Node subnet CIDR prefix length"
  type        = number
}
variable "dns_servers" {
  description = "DNS servers for the nodes"
  type        = list(string)
}

# --- Versions (for tagging / cross-reference; authoritative pins in VERIFIED-VERSIONS.md)
variable "talos_version" {
  description = "Talos version of the template/installer"
  type        = string
}

# --- Nodes --------------------------------------------------------------------
# data_disk = 0 means no Longhorn data disk (control planes). Workers get one.
variable "nodes" {
  description = "Cluster nodes keyed by hostname"
  type = map(object({
    role      = string # controlplane | worker
    ip        = string
    cpu       = number
    memory    = number # MiB
    os_disk   = number # GiB
    data_disk = optional(number, 0)
  }))
}
