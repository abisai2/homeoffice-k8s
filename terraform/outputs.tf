# Per-node facts the Phase-2 bootstrap consumes (assigned MAC, configured static
# IP, vCenter moref/uuid). MACs are vCenter-assigned; the static IPs are applied
# by the Talos machine config, not DHCP.
output "nodes" {
  description = "Provisioned Talos nodes"
  value = {
    for k, vm in vsphere_virtual_machine.node : k => {
      role = var.nodes[k].role
      ip   = var.nodes[k].ip
      moid = vm.moid
      uuid = vm.uuid
      mac  = try(vm.network_interface[0].mac_address, null)
    }
  }
}
