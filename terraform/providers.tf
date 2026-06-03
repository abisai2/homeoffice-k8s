# vCenter connection. The username/password are NOT stored here — they are read
# from the environment (VSPHERE_USER / VSPHERE_PASSWORD), sourced at apply time
# from ~/.credentials/api-tokens/vcenter-admin.creds (mr-robot, write access).
# vCenter uses a VMCA self-signed cert, so verification is disabled.
provider "vsphere" {
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}
