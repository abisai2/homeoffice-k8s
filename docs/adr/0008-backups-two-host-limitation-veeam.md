# ADR-0008: Four-layer backups, the two-host limitation, and the Veeam cold image

- **Status:** Accepted
- **Date:** 2026-06-04

## Context

This cluster has a structural weakness it cannot engineer away in software: there are only
**two ESXi hosts** (`esxi01`/`esxi02`). Three control-plane VMs across two hosts means one host
necessarily runs **two** etcd members — and losing that host loses etcd quorum. A third host is
planned but not present. The cluster is also the home of real data (Postgres, Authentik,
Longhorn volumes), so "the cluster is fine" and "the data is safe" are separate guarantees that
need separate evidence.

A single backup mechanism cannot cover this. etcd, application databases, block volumes, and the
"the control plane is unrecoverable, restore the whole VM" case are genuinely different recovery
problems with different RPOs and different restore procedures. And because of the two-host
limitation, we specifically need a recovery path that does **not** depend on etcd quorum
surviving — a way back even if the cluster's brain is gone.

## Decision

Run **four independent in-cluster backup layers**, all landing in Wasabi S3
(`homeoffice-k8s-backups`), **plus** a weekly **Veeam** cold whole-VM image as the
quorum-independent fallback:

| Layer | What it protects | Mechanism | Schedule |
|---|---|---|---|
| etcd snapshot | cluster state / control plane | Talos-native `etcd snapshot` CronJob → `etcd/` | 01:00 |
| CNPG / Barman | Postgres (base + continuous WAL, PITR) | Barman Cloud Plugin → `cnpg/` | 02:00 + WAL |
| Velero | k8s API resources (manifests) | Velero + AWS plugin → `velero/` | 03:00, 30d |
| Longhorn | block volume data | RecurringJob → `longhorn/` | 04:00, retain 7 |
| **Veeam** | **whole VMs (quorum-independent)** | weekly cold image (quiesced) | weekly window |

The Veeam cold image is taken against a gracefully quiesced cluster:
`scripts/cluster-shutdown.sh` cordons, hibernates CNPG, drains workers, waits for Longhorn
volumes to detach, and halts the nodes for a crash-consistent image; `cluster-startup.sh` brings
them back in order. Every layer's restore is documented in `docs/DR-RUNBOOK.md`, including
etcd recover-from-snapshot (`talosctl bootstrap --recover-from`) and the full rebuild from
git + age + Wasabi.

## Consequences

- **Easier:** four independent off-site copies plus a whole-VM fallback — the loss of any single
  layer (or the etcd quorum itself) is survivable. PITR for Postgres; a documented, tested-on-disk
  restore for every layer; the Veeam image specifically covers the "two hosts, quorum gone" case
  that the in-cluster layers cannot. All four layers were verified landing in Wasabi (P8.1).
- **Harder / costs accepted:** four backup systems to run, monitor, and keep current — more
  moving parts and more that can silently stop working (two real defects were found and fixed at
  P8.1: the Longhorn target key and the etcd `--nodes` flag). The Veeam window needs a graceful
  shutdown/startup, which is scripted but operationally heavier than a hot backup. **None of this
  removes the root cause** — the two-host topology — it only mitigates it; the accepted residual
  risk is recorded here until a third ESXi host restores real quorum tolerance. Restores are
  documented but a live end-to-end DR drill remains an outstanding follow-up.
