# Deployment Validation Report — k8s-talos1

**Date:** 2026-06-04 · **Platform pin:** `v0.1.2` · **Status:** ✅ PASS — platform live, all
backup layers verified, DR procedures documented.

Shakedown of the `k8s-talos1` build (Phases 0–9). Evidence files referenced inline live under
`docs/validation/`. Live checks are read-only against the running cluster.

## 1. Cluster topology & health

| Check | Result |
|---|---|
| Nodes | **6/6 Ready** — `k8s-cp1..3` + `k8s-worker1..3`, Kubernetes **v1.36.1**, Talos **v1.13.3** |
| Control plane | etcd **3 members**, VIP `.30`, control planes tainted (workers-only scheduling) |
| CNI | Cilium **1.19.4**, kube-proxy-free, LB-IPAM pool `.120–.139`, L2 announcements |
| Ingress | Gateway API **v1.4.1**, GatewayClass `cilium`, Gateway `main` **Programmed @ 172.16.23.120** |
| GitOps | Argo CD **9.5.17** — root + 10 platform apps = **11/11 Synced/Healthy @ v0.1.2** |
| TLS | wildcard `*.k8s-talos1.ap169homeoffice.net` Cert **Ready** via **letsencrypt-prod** (trusted) |
| Identity | authentik (external CNPG + self-hosted Redis), HTTPRoute on the shared gateway |
| Storage | Longhorn **1.12.0** (workers-only), default SC replica-3 + `longhorn-r1` replica-1 |
| Database | CloudNativePG **1.29.1**, `postgres` cluster **3/3** healthy, Barman Cloud Plugin **v0.12.0** |

## 2. Backup verification (P8.1)

All four layers confirmed landing in Wasabi `homeoffice-k8s-backups` on 2026-06-04 via
operator-run on-demand backups, then verified read-only. Evidence: `docs/validation/P8.1.backups.txt`.

| Layer | Prefix | Verified | Live schedule |
|---|---|---|---|
| etcd snapshot | `etcd/` | ✅ 16.9 MB snapshot uploaded | CronJob 01:00 (`--nodes` fix in v0.1.2) |
| CNPG / Barman | `cnpg/` | ✅ base backup `completed` + continuous WAL | ScheduledBackup 02:00 + WAL |
| Velero | `velero/` | ✅ `Completed`, 879 items | Schedule 03:00, 30d TTL |
| Longhorn | `longhorn/` | ✅ volume backup `Completed`, 17 objs | RecurringJob 04:00, retain 7 (added in v0.1.2) |

Two defects were found and root-caused during P8.1 (both fixed in `v0.1.2`, live-verified):
- **Longhorn** backup target empty — `defaultSettings.backupTarget` → `defaultBackupStore.*`
  (Longhorn 1.12 moved the key) + one-time live BackupTarget patch.
- **etcd-backup** CronJob missing `--nodes` → `talosctl etcd snapshot` errored on first run.

## 3. DR readiness (P8.2 + P9.1)

| Item | Status |
|---|---|
| `scripts/cluster-shutdown.sh` / `cluster-startup.sh` | ✅ authored, shellcheck-clean, `--dry-run` verified (P8.2) |
| Weekly Veeam cold-image window | ✅ graceful quiesce + ordered power-on scripted (🚦 real run gated) |
| `docs/DR-RUNBOOK.md` | ✅ procedures for §A node replace · §B etcd recover · §C full rebuild · §D Velero · §E Longhorn · §F CNPG · §G Veeam |
| Recovery assets documented | ✅ age key, git repo, Wasabi creds, vCenter creds (DR-RUNBOOK §0) |
| Restorable artifacts present in Wasabi | ✅ etcd snapshot, CNPG base `20260605T001449/`, Longhorn `volume.cfg` |

Actual restores are **gated** (destructive) — documented, not executed; a live restore drill is
the natural P9 follow-on against the Veeam image.

## 4. Verified component versions

`Talos v1.13.3 · k8s v1.36.1 · Cilium 1.19.4 · Gateway API v1.4.1 · Argo CD 9.5.17 · KSOPS
v4.5.1 · Longhorn 1.12.0 · CloudNativePG 1.29.1 (chart 0.28.2) · Barman Cloud Plugin v0.12.0 ·
authentik 2026.5.2 · Velero 1.18.1 (chart 12.0.2) + AWS plugin v1.14.1.` Full provenance:
`docs/VERIFIED-VERSIONS.md`.

## 5. Outstanding follow-ups (non-blocking)

- **DNS:** Technitium internal A record `*.k8s-talos1.ap169homeoffice.net → 172.16.23.120` for
  in-cluster app reachability by name (the Gateway is live at `.120`).
- **Observability:** no metrics stack yet — CNPG/Velero PodMonitors and Longhorn metrics are
  disabled (`monitoring.*` off) until Prometheus exists.
- **DR drill:** execute one controlled shutdown → Veeam → startup → restore cycle to convert the
  documented procedures (P9.1) into a tested RTO/RPO.
- **Push:** the P8.2 + ledger commits are committed on `build` but pending push (operator/gated).

## Verdict

The platform meets its build goals: HA Talos cluster, GitOps-managed stack, end-to-end secret
encryption, four independent backup layers proven to reach off-site object storage, and a
documented recovery path for every layer plus a whole-VM fallback. **Ready for use**, with the
DR drill and DNS/observability items tracked above.
