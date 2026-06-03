# Discovered from vcsa01.homeoffice.local (govc, 2026-06-03). Non-secret.
# vCenter credentials come from the environment (VSPHERE_USER/VSPHERE_PASSWORD).

vsphere_server        = "vcsa01.homeoffice.local"
vsphere_datacenter    = "ap169home-dc"
vsphere_cluster       = "ap169home-cluster01"
vsphere_resource_pool = "Kubernetes Pool"
vsphere_datastore     = "fs1-esxi-ds1"
vsphere_network       = "vds01_pg-Kubernetes"
vsphere_folder        = "Kubernetes"
vsphere_template      = "talos-v1.13.3"

network_gateway = "172.16.23.1"
network_prefix  = 24
dns_servers     = ["172.16.10.5", "172.16.10.6"]

talos_version = "v1.13.3"

# 3 dedicated control planes (tainted, etcd-only) + 3 workers (all workloads).
nodes = {
  "k8s-cp1"     = { role = "controlplane", ip = "172.16.23.31", cpu = 2, memory = 8192, os_disk = 64 }
  "k8s-cp2"     = { role = "controlplane", ip = "172.16.23.32", cpu = 2, memory = 8192, os_disk = 64 }
  "k8s-cp3"     = { role = "controlplane", ip = "172.16.23.33", cpu = 2, memory = 8192, os_disk = 64 }
  "k8s-worker1" = { role = "worker", ip = "172.16.23.34", cpu = 6, memory = 24576, os_disk = 64, data_disk = 300 }
  "k8s-worker2" = { role = "worker", ip = "172.16.23.35", cpu = 6, memory = 24576, os_disk = 64, data_disk = 300 }
  "k8s-worker3" = { role = "worker", ip = "172.16.23.36", cpu = 6, memory = 24576, os_disk = 64, data_disk = 300 }
}
