# Provisioning Talos VMs on VMware with Terraform

The cluster runs on VMware — vCenter `vcsa01`, datacenter `ap169home-dc`, two ESXi hosts in
`ap169home-cluster01`, VMs in the `/vm/Kubernetes` folder on the `fs1-esxi-ds1` datastore. The
job of this layer is narrow and well-defined: turn a Talos image into six identical-ish VMs,
reproducibly, with nothing hand-clicked in the vSphere UI. That is a Terraform job, and **only**
a Terraform job — `talosctl` takes over from there ([ADR-0003](../adr/0003-terraform-talosctl-no-ansible.md)).

## The image comes first

Talos doesn't ship one universal image; you compose the one you need from the **Image Factory**.
You declare a *schematic* — the set of system extensions baked in — and the Factory gives you a
deterministic ID and an OVA to match.

`talos/image/schematic.yaml` is the canonical extension set for this cluster:

- `siderolabs/iscsi-tools` and `siderolabs/util-linux-tools` — required by Longhorn.
- `siderolabs/vmtoolsd-guest-agent` — so vCenter actually sees guest IP/hostname/heartbeat and
  can do clean power operations. This one was added after a detour ([ADR-0001](../adr/0001-vmtoolsd-guest-agent-extension.md)):
  vCenter reported VMware Tools as "Not running / 2147483647 / unmanaged," which turned out to
  be *static metadata baked into the Talos OVA* (the never-booted template showed the identical
  values) rather than a missing daemon. Talos has no package manager, so the only way to run a
  real guest agent is this extension.

`scripts/talos-image.sh` turns the schematic into a Factory schematic ID
(`a28d8637…77d7`), pulls the OVA, and imports it into vCenter as a template. Encoding the image
as code is what makes the node build reproducible instead of a one-off manual step.

> **A version trap worth flagging.** The vSphere provider **moved from `hashicorp/vsphere` to
> `vmware/vsphere`**. The old HashiCorp mirror is stale (stuck at 2.12); the live provider is
> `vmware/vsphere 2.16.0`. Pinning the wrong source silently gives you an outdated provider —
> recorded in `VERIFIED-VERSIONS.md`.

## Terraform owns the VMs, not the secrets

`terraform/` is deliberately small:

```
versions.tf    provider pins (vmware/vsphere 2.16.0) + Wasabi S3 backend (use_lockfile)
providers.tf   vSphere connection, creds from env
variables.tf   typed inputs
terraform.tfvars  discovered facts (datacenter, cluster, datastore, network, template…)
data.tf        look up the existing vSphere objects
vms.tf         6 clones from the template
outputs.tf     guest IPs etc.
```

`vms.tf` clones the template six times: three control planes (2 vCPU / 8 GiB) and three workers
(6 vCPU / 24 GiB), each with a 64 GiB OS disk, workers getting an extra **300 GiB disk** for
Longhorn. NICs are pinned to **static MACs** on VLAN 23 (`vds01_pg-Kubernetes`) — the MAC pin
matters because the IP assignment is static and we want it stable across rebuilds. The VMs go in
the cluster's **root resource pool** — no dedicated pool, no DRS anti-affinity rules — because
with two hosts there is nothing useful to spread across (see the two-host story in
[ADR-0008](../adr/0008-backups-two-host-limitation-veeam.md)).

State lives in a **Wasabi S3 backend**. Two deliberate choices there: `use_lockfile` (so the
state lock doesn't need a separate DynamoDB-style table), and the understanding that **this state
is non-precious** — it describes vSphere objects, nothing more. The PKI and secrets never touch
Terraform state; they live in SOPS ([ADR-0005](../adr/0005-sops-age-single-key.md)). If the
state were lost, you re-import; if it leaked, no secrets leak with it.

## The handoff

`terraform apply` is the first of the project's approval gates — it makes real VMs. When it
finishes, six VMs are powered on and sitting in Talos **maintenance mode**: booted, on the
network, waiting for a machine config, with no OS installed to disk yet. `govc` reports their
guest IPs. That is the clean line where Terraform's job ends and the next post — Talos config and
secrets — begins.
