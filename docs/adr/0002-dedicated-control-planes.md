# ADR-0002: Dedicated, tainted control planes (workers-only workloads)

- **Status:** Accepted
- **Date:** 2026-06-04

## Context

`k8s-talos1` is a 6-VM cluster: 3 control planes (`k8s-cp1/2/3`, 2 vCPU · 8 GiB · 64 GiB)
and 3 workers (`k8s-worker1/2/3`, 6 vCPU · 24 GiB · 64 GiB + a 300 GiB Longhorn data disk).
With only six nodes, there is a real pull to let workloads run on the control planes too —
it would reclaim 6 vCPU / 24 GiB of otherwise idle capacity and is a single Talos setting
(`cluster.allowSchedulingOnControlPlanes: true`).

The tension is between **capacity** and **blast radius**. The control planes carry etcd and
the API server; etcd is latency- and fsync-sensitive and tolerates no noisy neighbours. If a
workload OOMs a control plane, starves its disk, or pins its CPU, it can cost an etcd member —
and on this cluster etcd quorum is already fragile (only two ESXi hosts; see ADR-0008). Storage
also forces the question: Longhorn replicas should live on nodes with the data disk and the
`iscsi-tools`/`util-linux-tools` extensions, which is the workers, not the control planes.

## Decision

Keep the control planes **dedicated**. Talos's default `allowSchedulingOnControlPlanes: false`
is set explicitly in `talos/patches/controlplane.yaml`, which leaves the built-in
`node-role.kubernetes.io/control-plane:NoSchedule` taint in place. All workloads — Longhorn,
CNPG, Authentik, the platform components — schedule on the three workers. Longhorn confines
itself to the workers automatically: it adds no toleration for that taint, so we did not need
explicit nodeSelectors for it.

## Consequences

- **Easier:** etcd and the API server get the whole control-plane node — no workload can
  starve a quorum member. Storage placement is unambiguous (data lives where the disks and
  extensions are). The split mirrors how the cluster is operated and reasoned about.
- **Harder / costs accepted:** ~6 vCPU and ~24 GiB of control-plane capacity sit idle by
  design — a deliberate trade of utilisation for stability on a cluster where an etcd member
  is precious. All workload headroom comes from the three workers; scaling compute means
  adding or growing workers, not spreading onto the control planes. Re-evaluate only if a
  third ESXi host removes the quorum-fragility argument and capacity becomes the binding
  constraint.
