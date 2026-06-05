# ADR-0007: Storage model — Longhorn for volumes, CloudNativePG for Postgres

- **Status:** Accepted
- **Date:** 2026-06-04

## Context

Stateful workloads need two different things, and conflating them is a common mistake.
General-purpose pods (Authentik media, Redis, anything that wants a PVC) need replicated block
storage that survives a node loss. Postgres needs *database* high availability — streaming
replication, failover, consistent backups with point-in-time recovery — which is a different
problem from block-level replication.

The naive approach is to run Postgres on a replica-3 Longhorn volume and call it HA. That
double-replicates: Longhorn copies every block three times *and* you would still want Postgres
replicas for failover, so a 3-instance Postgres on replica-3 volumes is nine physical copies of
the data, with two independent systems both thinking they own durability — and Postgres is
unhappy sharing its fsync path with a network block device's replication.

## Decision

Split the two concerns by tool, and let each own its own replication:

- **Longhorn 1.12.0** (`kubernetes/apps/longhorn/`) provides replicated block storage,
  **workers-only** (control planes are tainted; Longhorn adds no toleration — see ADR-0002) on
  the 300 GiB data disks. The default StorageClass is **replica-3** for general workloads, plus
  a **`longhorn-r1` replica-1** StorageClass for cases where the application replicates its own
  data.
- **CloudNativePG 1.29.1** (`kubernetes/apps/cnpg-{operator,cluster}/`) runs Postgres as a
  **3-instance HA cluster** with worker anti-affinity, and crucially its PVCs use the
  **replica-1** StorageClass — **Postgres owns HA**, so Longhorn must not replicate underneath
  it. Backups go to Wasabi via the **Barman Cloud Plugin v0.12.0** (the native
  `barmanObjectStore` field is deprecated as of CNPG 1.26; the plugin is the operator-chosen
  path).

## Consequences

- **Easier:** each layer does one job. Ordinary PVCs get transparent 3-way block replication;
  Postgres gets real database HA + WAL-based PITR without paying for redundant block copies.
  CNPG manages failover, backups, and recovery as Postgres concepts, not volume tricks.
- **Harder / costs accepted:** the replica-1-for-CNPG rule is a sharp edge — putting a Postgres
  cluster on the replica-3 default would silently 3× its storage and fight its fsync path, so
  the cnpg-cluster manifests must pin `longhorn-r1` deliberately. Two storage systems to operate
  and back up (Longhorn native backups *and* CNPG Barman), and two failure models to understand.
  Longhorn's replicas live on three workers only, so worker count is the replication domain —
  losing two workers at once threatens replica-3 availability.
