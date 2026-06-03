# DRS "should" (preferential) anti-affinity: spread the 3 control planes across
# hosts, and the 3 workers across hosts. mandatory = false on purpose — with only
# 2 ESXi hosts these can't be fully satisfied, and a "must" rule would block the
# weekly collapse-to-one-host Veeam window and host maintenance. See the 2-host ADR.
resource "vsphere_compute_cluster_vm_anti_affinity_rule" "control_plane" {
  name               = "talos-control-plane-antiaffinity"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
  mandatory          = false
  virtual_machine_ids = [
    for k, vm in vsphere_virtual_machine.node : vm.id if var.nodes[k].role == "controlplane"
  ]
}

resource "vsphere_compute_cluster_vm_anti_affinity_rule" "workers" {
  name               = "talos-workers-antiaffinity"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
  mandatory          = false
  virtual_machine_ids = [
    for k, vm in vsphere_virtual_machine.node : vm.id if var.nodes[k].role == "worker"
  ]
}
