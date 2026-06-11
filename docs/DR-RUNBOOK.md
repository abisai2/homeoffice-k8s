# Disaster Recovery Runbook — k8s-talos1

Operational recovery procedures for the `k8s-talos1` Talos cluster. Pairs with the
backup wiring verified in **P8.1** (`docs/validation/P8.1.backups.txt`) and the
shutdown/startup scripts from **P8.2**.

> **Legend:** 🚦 = destructive / gated — run only with intent, after confirming the
> failure is real. Commands assume `cd` into the repo and the env below.

## 0. Recovery assets — protect these off-cluster

Recovery is impossible without all four. None live only inside the cluster.

| Asset | Location | Why it's critical |
|---|---|---|
| **SOPS age key** | `~/.credentials/age/homeoffice-k8s.agekey` | The linchpin. Decrypts `talos/secrets.sops.yaml` (cluster PKI/identity) **and** every app secret. Lose it → no from-git rebuild, no secret decrypt. |
| **Git repo** | `github.com/abisai2/homeoffice-k8s` (+ local `/mnt/homeoffice-infra/repos/homeoffice-k8s`) | All IaC + SOPS-encrypted secrets + pinned versions (`v0.1.2`). |
| **Wasabi creds** | `~/.credentials/api-tokens/wasabi-homeoffice-k8s.creds` | Read the backup bucket `homeoffice-k8s-backups` (longhorn/ cnpg/ velero/ etcd/). |
| **vCenter creds** | `~/.credentials/api-tokens/vcenter-admin.creds` | Power/clone VMs (govc), Veeam restore target. |

Shared env for the commands below:
```bash
cd /mnt/homeoffice-infra/repos/homeoffice-k8s
export KUBECONFIG=$PWD/talos/clusterconfig/kubeconfig
export SOPS_AGE_KEY_FILE=~/.credentials/age/homeoffice-k8s.agekey
TC=talos/clusterconfig/talosconfig
# govc (VM ops):   set -a; source ~/.credentials/api-tokens/vcenter-admin.creds; set +a
# Wasabi (restore):set -a; source ~/.credentials/api-tokens/wasabi-homeoffice-k8s.creds; set +a
#   then map WASABI_* -> AWS_* and use --endpoint-url https://s3.us-east-1.wasabisys.com
```

## 1. The 4-layer backup model (what protects what)

| Layer | Protects | Wasabi prefix | Schedule | Restore § |
|---|---|---|---|---|
| **etcd snapshot** (Talos CronJob) | k8s API state (the cluster itself) | `etcd/` | 01:00 daily | §B |
| **CNPG / Barman** | PostgreSQL data (authentik / netbox / litellm DBs) | `cnpg/` (base + WAL) | base 02:00 daily + continuous WAL | §F |
| **Longhorn** (RecurringJob) | PV data (authentik + netbox media, PG volumes) | `longhorn/` | 04:00 daily, retain 7 | §E |
| **Velero** | k8s resource manifests (all ns) | `velero/` | 03:00 daily, 30d TTL | §D |
| **Veeam** (external) | Whole-VM cold images | Veeam repo | weekly window (P8.2) | §G |

GitOps means most "config" is already safe in git — Velero/etcd protect *live* state that
isn't in git; Longhorn/CNPG protect *data*; Veeam is the whole-machine fallback.

## 2. Pick a procedure

| Symptom | Procedure |
|---|---|
| One node dead/corrupt, quorum intact | **§A** replace node |
| etcd quorum lost (≥2 CPs gone) but VMs/disks OK | **§B** etcd recover-from-snapshot |
| Cluster gone / starting from bare vSphere | **§C** full rebuild from git+age+Wasabi |
| A k8s object/namespace deleted, cluster healthy | **§D** Velero restore |
| A PV lost/corrupt | **§E** Longhorn restore |
| Postgres data lost/corrupt | **§F** CNPG recovery |
| Recent whole-VM rollback available & faster | **§G** Veeam whole-VM |

---

## §A. Replace a single failed node (quorum intact)

Non-destructive to the cluster; the node is reprovisioned.
1. 🚦 If etcd member is unhealthy, remove it: `talosctl --talosconfig $TC -n <good-cp> etcd remove-member <name>`.
2. Recreate the VM: `cd terraform && terraform apply` (re-clones from the `talos-v1.13.3` template) — or `govc vm.power -on` if the VM exists.
3. Re-inject config: `./scripts/bootstrap.sh talos` (idempotent — skips healthy nodes, configures the new one).
4. The node rejoins (etcd for a CP, scheduling for a worker). Verify: `kubectl get nodes`, `talosctl --talosconfig $TC -n 172.16.23.31 etcd members` (= 3).

## §B. 🚦 etcd recovery from snapshot (quorum lost, disks intact)

Restores the k8s control-plane state from the latest `etcd/` snapshot. Verified against
Talos v1.13 disaster-recovery docs.

1. **Confirm it's unrecoverable** — etcd truly has no quorum:
   ```bash
   for n in 172.16.23.31 172.16.23.32 172.16.23.33; do talosctl --talosconfig $TC -n $n service etcd; done
   ```
2. **Get the snapshot** — download the newest from Wasabi (or use a fresh `talosctl etcd snapshot` if any member is still up):
   ```bash
   # AWS_* exported from wasabi creds:
   aws s3 cp "s3://homeoffice-k8s-backups/etcd/$(aws s3 ls s3://homeoffice-k8s-backups/etcd/ --endpoint-url https://s3.us-east-1.wasabisys.com | tail -1 | awk '{print $4}')" /tmp/etcd-restore.snapshot --endpoint-url https://s3.us-east-1.wasabisys.com
   ```
3. 🚦 **Wipe etcd data** on all 3 control planes (EPHEMERAL holds `/var/lib/etcd`):
   ```bash
   for n in 172.16.23.31 172.16.23.32 172.16.23.33; do
     talosctl --talosconfig $TC -n $n reset --system-labels-to-wipe EPHEMERAL --graceful=false --reboot
   done   # nodes reboot, come back WITHOUT etcd, awaiting bootstrap
   ```
4. 🚦 **Recover on ONE node** (the snapshot is a real `etcd snapshot`, so the integrity hash is valid — no `--recover-skip-hash-check`):
   ```bash
   talosctl --talosconfig $TC -n 172.16.23.31 -e 172.16.23.31 bootstrap --recover-from=/tmp/etcd-restore.snapshot
   ```
5. etcd becomes healthy on .31 → apiserver up on the VIP `.30` → cp2/cp3 rejoin automatically.
   Verify: `talosctl --talosconfig $TC -n 172.16.23.31 etcd members` (= 3), `kubectl get nodes`.
6. Run **§3 post-recovery validation**. (App data on Longhorn/CNPG is untouched by an etcd
   restore — only the k8s object store rewinds to the snapshot time.)

## §C. 🚦 Full rebuild from git + age + Wasabi (cluster lost)

Rebuilds the entire platform from the four recovery assets. Cluster *identity* (PKI) is
restored from `talos/secrets.sops.yaml` in git (decrypted with the age key), so the new
cluster is the same cluster — node IPs, VIP, CA all match.

1. **Prereqs:** age key + repo present; `task deps` clean; vCenter + Wasabi creds available.
2. **VMs:** `cd terraform && terraform apply` → 6 VMs from the `talos-v1.13.3` template (carries vmtoolsd).
3. **Talos + etcd:**
   ```bash
   set -a; source ~/.credentials/api-tokens/vcenter-admin.creds; set +a   # GOVC_*
   ./scripts/bootstrap.sh talos        # guestinfo config (PKI from secrets.sops.yaml) -> bootstrap etcd -> kubeconfig
   ```
   *(If recovering k8s state too, instead of a clean bootstrap use §B step 4’s `bootstrap --recover-from` to seed etcd from the snapshot.)*
4. **Platform (Cilium + Argo + GitOps):**
   ```bash
   ./scripts/bootstrap.sh cluster      # Gateway API CRDs + Cilium -> Argo CD + KSOPS + root app-of-apps
   ```
   Argo resolves the pinned tag (the `targetRevision` in `root-app.yaml`; `v0.2.0` as of
   2026-06-10) and syncs all platform apps. Wait for green:
   `kubectl get applications -n argocd` (all Synced/Healthy).
5. **Re-point the live Longhorn backup target** (the seed ConfigMap only acts at first boot — same one-time catch-up as P8.1):
   ```bash
   kubectl patch backuptarget.longhorn.io default -n longhorn-system --type merge \
     -p '{"spec":{"backupTargetURL":"s3://homeoffice-k8s-backups@us-east-1/longhorn/","credentialSecret":"longhorn-backup-credential"}}'
   ```
6. **Restore data** into the fresh platform: PostgreSQL via **§F**, any standalone PVs via **§E**.
7. **§3 validation.**

## §D. Velero restore (k8s resources)

Restores manifests (Velero here is resources-only — Longhorn/CNPG own the volume data).
```bash
velero backup get                                  # pick a backup
velero restore create --from-backup <BACKUP> --wait
# scope it: --include-namespaces <ns>   ; conflict policy: --existing-resource-policy update
velero restore describe <restore> --details
```
Use for accidental deletion of k8s objects (a namespace, a Deployment, RBAC, etc.). For
stateful apps, restore the manifests here **and** the data via §E/§F.

## §E. Longhorn volume restore (from backup)

Backups live under `longhorn/backupstore/`. With the BackupTarget `available=true`:
1. List backups: `kubectl get backupvolumes.longhorn.io -n longhorn-system` (or Longhorn UI → Backup).
2. Restore a backup to a new volume — Longhorn UI (Backup → Restore) is simplest, or declare a
   PVC backed by the restored volume via a Longhorn `StorageClass` with `fromBackup`. The restored
   volume reattaches to a workload by name.
3. 🚦 If overwriting a live PVC, scale the consumer to 0 first, restore, then scale back.
Verify: `kubectl get volumes.longhorn.io -n longhorn-system` → `state: attached`, `robustness: healthy`.

## §F. 🚦 CNPG (PostgreSQL) recovery from Barman

Bootstraps a **new** Cluster from the `cnpg/` Barman archive (base backup + WALs). Verified
against the Barman Cloud Plugin recovery docs. The ObjectStore `wasabi-store` and original
`serverName: postgres` are reused as the recovery source.

🚦 To recover in place, first delete the broken Cluster (`kubectl delete cluster postgres -n
databases`) — **this deletes the PVCs**; only do it when the live data is already lost.

```yaml
# recovery-cluster.yaml — apply into ns databases
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres
  namespace: databases
spec:
  instances: 3
  storage: { storageClass: longhorn-r1, size: 10Gi }
  bootstrap:
    recovery:
      source: postgres-backup        # -> externalClusters entry below
      # recoveryTarget: { targetTime: "YYYY-MM-DD HH:MM:SS" }   # optional PITR
  externalClusters:
    - name: postgres-backup
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: wasabi-store   # the ObjectStore CR (kept in git)
          serverName: postgres             # original cluster name = backup folder
  # resume WAL archiving on the recovered cluster:
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters: { barmanObjectName: wasabi-store, serverName: postgres }
  managed:
    roles:
      - { name: authentik, ensure: present, login: true, passwordSecret: { name: authentik-db-role } }
      - { name: netbox,    ensure: present, login: true, passwordSecret: { name: netbox-db-role } }
      - { name: litellm,   ensure: present, login: true, passwordSecret: { name: litellm-db-role } }
```
Apply the ObjectStore + credential first (they ship in `kubernetes/apps/cnpg-cluster/`), then
this manifest. Verify: `kubectl get cluster postgres -n databases` → `readyInstances: 3`,
phase healthy; the app DBs (authentik / netbox / litellm) reconnect.
> NOTE: this mirrors the live `cluster.yaml` plus the `bootstrap.recovery`/`externalClusters`
> stanzas. After recovery, revert to the git-managed `cluster.yaml` (without recovery) so Argo
> stays in sync — or let the recovery cluster run and prune the recovery stanzas in a follow-up commit.

## §G. 🚦 Veeam whole-VM fallback

Fastest path when a recent weekly cold image (P8.2) predates the incident and a full rebuild
is overkill.
1. Veeam console → restore the 6 VMs (`k8s-cp1..3`, `k8s-worker1..3`) to vSphere, powered **off**.
2. Bring them up in order: `set -a; source vcenter-admin.creds; set +a; ./scripts/cluster-startup.sh`.
3. The cluster resumes at the image's point in time (etcd + volumes consistent because the image
   was taken after a graceful `cluster-shutdown.sh`). Run **§3**. Data written after the image
   is lost — layer §D/§E/§F restores on top if a newer RPO is needed.

---

## §3. Post-recovery validation

```bash
kubectl get nodes -o wide                                              # 6 Ready
talosctl --talosconfig $TC -n 172.16.23.31 etcd members               # 3 members
kubectl get applications -n argocd \
  -o custom-columns=N:.metadata.name,S:.status.sync.status,H:.status.health.status  # all Synced/Healthy
kubectl get cluster postgres -n databases                             # readyInstances 3
kubectl get volumes.longhorn.io -n longhorn-system                    # attached/healthy
kubectl get backuptarget.longhorn.io default -n longhorn-system -o jsonpath='{.status.available}'  # true
# smoke test an app path (authentik) + confirm next scheduled backups land in Wasabi.
```

## RPO / RTO (informal)

- **RPO:** etcd ≤24h (daily) + continuous PG WAL (≈minutes) + Longhorn ≤24h + weekly Veeam.
- **RTO:** node replace minutes (§A); etcd recover ~15–30 min (§B); full rebuild ~1–2 h (§C);
  Veeam ~time-to-restore-6-VMs (§G).
- The recovery assets in §0 are the hard dependency — verify the age-key backup periodically.
