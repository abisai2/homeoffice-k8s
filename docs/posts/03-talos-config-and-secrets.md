# Talos machine config and one age key to rule them all

At the end of the last post there are six VMs in Talos **maintenance mode**: booted, networked,
no OS on disk, waiting for instructions. Talos is configured entirely by applying a YAML
*machine-config* document over its gRPC API — there is no SSH, no console login, no `apt`. This
is the part of the build I like most, because it is where "rebuildable from git" stops being a
slogan and becomes literally true.

## Config as patches, rendered per node

I did not want six hand-maintained machine configs drifting apart. Instead `talos/patches/`
holds the *differences* and `scripts/talos-gen.sh` renders the final per-node configs:

```
talos/patches/
  common.yaml         shared (pins the installer image from the schematic)
  controlplane.yaml   cluster-wide: CNI none, kube-proxy disabled, CPs stay tainted
  worker.yaml         worker role + the Longhorn data disk
  nodes/controlplane/k8s-cp{1,2,3}.yaml   static IP .31/.32/.33
  nodes/worker/k8s-worker{1,2,3}.yaml     static IP .34/.35/.36
```

The interesting decisions all live in `controlplane.yaml`:

```yaml
cluster:
  allowSchedulingOnControlPlanes: false   # CPs dedicated/tainted — ADR-0002
  network:
    cni:
      name: none                          # Cilium provides the CNI — ADR-0004
  proxy:
    disabled: true                        # Cilium replaces kube-proxy
```

`cni: none` and `proxy.disabled` are why the nodes come up `NotReady` and *stay* that way until
Cilium is installed — that is expected, not a bug. The API **VIP `.30`** is Talos-managed (layer-2),
so there is a stable API endpoint before any LoadBalancer exists. `allowSchedulingOnControlPlanes:
false` keeps the three control planes dedicated to etcd and the API ([ADR-0002](../adr/0002-dedicated-control-planes.md)).

> **A schema quirk I had to work around:** `talosctl gen` emits a trailing `kind: HostnameConfig`
> document that the validator rejects, so `talos-gen.sh` strips it. Small, but the kind of thing
> that only shows up when you actually run the current version instead of trusting old docs —
> noted in `VERIFIED-VERSIONS.md`.

Every rendered config is checked with `talosctl validate --mode metal` before anything is applied.

## One age key for the PKI

`talosctl gen secrets` produces the **PKI root** — the cluster CA, etcd CA, service-account keys,
bootstrap tokens. This is the crown jewels: whoever holds it can mint identities for the whole
cluster. It must persist (so the cluster is rebuildable) but it must never sit in plaintext, and
it must **never** end up in Terraform state.

The answer is the same mechanism used for every other secret in the repo: **SOPS + age, one key**
([ADR-0005](../adr/0005-sops-age-single-key.md)). The PKI is encrypted to
`talos/secrets.sops.yaml` against the age recipient declared in `.sops.yaml`, and `talos-gen.sh`
decrypts it at render time. The same `~/.credentials/age/homeoffice-k8s.agekey` later unlocks the
Kubernetes application secrets. **One key restores the entire system** — which is also why it is
the single most important thing to back up (the DR runbook calls it the linchpin).

## Bootstrap

`scripts/bootstrap.sh` does the bring-up, and it is a gate — it writes to real disks and creates
real PKI:

1. Discover the maintenance-mode IPs with `govc`.
2. `talosctl apply-config` the rendered config to each node — Talos installs to disk and reboots.
3. `talosctl bootstrap` **etcd on `cp1` only** (exactly once — bootstrapping more than one node is
   how you get a split brain).
4. Fetch the kubeconfig.

After that: `talosctl etcd members` shows **3 members**, and `kubectl get nodes` shows **6 nodes,
all NotReady** — correct, because there is still no CNI. The cluster has a brain and an API
endpoint; it has no network yet. That is the next post.
