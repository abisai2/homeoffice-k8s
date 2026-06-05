# The 6 Talos VMs, cloned from the talos-v1.13.3 template.
#
# Talos is immutable and API-managed — there is NO guest customization here.
# Machine config is injected out-of-band by the Phase-2 bootstrap (govc sets
# guestinfo.talos.config from the SOPS-decrypted per-node config), so the PKI
# never enters Terraform state and bring-up does not depend on VLAN DHCP.
resource "vsphere_virtual_machine" "node" {
  for_each = var.nodes

  name             = each.key
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id # cluster root pool — no dedicated resource pool
  datastore_id     = data.vsphere_datastore.ds.id
  folder           = var.vsphere_folder

  num_cpus  = each.value.cpu
  memory    = each.value.memory
  guest_id  = data.vsphere_virtual_machine.template.guest_id
  scsi_type = data.vsphere_virtual_machine.template.scsi_type
  firmware  = data.vsphere_virtual_machine.template.firmware

  # Talos has no VMware guest customization and may sit in maintenance mode with
  # no IP until configured — don't block apply waiting for a guest IP.
  wait_for_guest_net_timeout = 0
  wait_for_guest_ip_timeout  = 0

  annotation = "Talos ${var.talos_version} ${each.value.role} — Terraform (homeoffice-k8s)"

  network_interface {
    network_id   = data.vsphere_network.net.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  # OS / system disk (cloned from template, grown to the requested size).
  disk {
    label            = "os"
    size             = each.value.os_disk
    unit_number      = 0
    thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned
  }

  # Dedicated Longhorn data disk (workers only; data_disk = 0 on control planes).
  dynamic "disk" {
    for_each = each.value.data_disk > 0 ? [each.value.data_disk] : []
    content {
      label            = "longhorn"
      size             = disk.value
      unit_number      = 1
      thin_provisioned = true
    }
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }
}
