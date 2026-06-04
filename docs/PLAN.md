# homeoffice-k8s — Bootstrap Plan (authoritative spec)

> **What this is:** the durable, on-disk specification for building the `k8s-talos1`
> Talos/VMware GitOps cluster. It is paired with **`docs/PROGRESS.md`** (the live
> checkpoint ledger) and **`docs/VERIFIED-VERSIONS.md`** (upstream-verified pins).
> These three files + git history are the source of truth — **not** conversation
> memory. If you are resuming with no context, start at **§7 Context-reset protocol**.

---

## 1. Locked design

| Area | Decision |
|---|---|
| Cluster | `k8s-talos1`, Talos **v1.13.x**, Kubernetes as shipped by that Talos (exact pin → `VERIFIED-VERSIONS.md`) |
| Control plane | `k8s-cp1/2/3` = `.31/.32/.33` · 2 vCPU·8 GiB·64 GiB OS · **tainted `NoSchedule`** · etcd + control plane only |
| Workers | `k8s-worker1/2/3` = `.34/.35/.36` · 6 vCPU·24 GiB·64 GiB OS + **300 GiB Longhorn disk** · all workloads |
| API VIP | `k8s-talos1` `.30` (Talos-managed, layer-2) |
| Network | `172.16.23.0/24`, gw `.1`, DNS `172.16.10.5/.6`, VLAN 23 / `vds01_pg-Kubernetes` |
| LB pool | Cilium **L2 Announcements + LB-IPAM** `.120–.139` (gateway = `.120`) |
| Provisioning | **Terraform only** (`vmware/vsphere`) for VMs; **talosctl scripts** for Talos bring-up. No Ansible. |
| Talos image | Image Factory OVA (extensions `iscsi-tools`, `util-linux-tools`) → vCenter template → cloned |
| PKI custody | `talosctl gen secrets` → **SOPS in git** → rendered by talosctl. **Never in Terraform state.** |
| TF state | **Wasabi S3 backend** (`use_lockfile`); holds vSphere data only (non-precious) |
| vSphere | vcsa01 · dc `ap169home-dc` · cluster `ap169home-cluster01` (esxi01/02) · folder `/vm/Kubernetes` · datastore **`fs1-esxi-ds1`** (all disks) · VMs in cluster **root** pool (no dedicated RP, no DRS rules) |
| GitOps | Argo CD app-of-apps → `platform` ApplicationSet → per-component kustomize dirs, sync-wave ordered; **release-pinned to a SemVer tag** on `git@github.com:abisai2/homeoffice-k8s.git` |
| Secrets | SOPS + age (key `~/.credentials/age/homeoffice-k8s.agekey`), KSOPS in argocd-repo-server |
| Storage | Longhorn workers-only · **replica-3** (apps) + a **replica-1** StorageClass for CNPG |
| Database | CloudNativePG · 3-instance HA · worker anti-affinity · replica-1 volumes (Postgres owns HA) |
| Identity | Authentik on workers · backed by CNPG + Redis |
| TLS | cert-manager + Cloudflare DNS-01 → LE wildcard `*.k8s-talos1.ap169homeoffice.net`; internal A on Technitium → `.120` |
| Backups | **4 layers** → Wasabi: Talos etcd snapshot CronJob · Velero · Longhorn native · Veeam weekly cold VM-image |
| Updates | Renovate (Talos, k8s, charts, images, TF providers) via `github-renovate-homeoffice-k8s.token` |

**Accepted limitation:** 2 ESXi hosts → one host holds 2 control planes; that host failing
breaks etcd quorum. DR + weekly Veeam cold backup is the mitigation; a 3rd host is planned.
Recorded as an ADR.

## 2. Repo layout

```
terraform/   vsphere VMs (clone template), disks, MAC-pin, Wasabi S3 backend
talos/       secrets.sops.yaml (PKI root) + patches/{controlplane,worker,node-*}.yaml ; clusterconfig/ (gitignored)
kubernetes/  bootstrap/ (argocd install + root-app + repo-ssh.sops) ; apps/ (platform-appset + per-component dirs)
scripts/     install-prereqs · talos-gen · bootstrap · cluster-shutdown/startup (Veeam window) · lint · release
docs/        PLAN.md · PROGRESS.md · VERIFIED-VERSIONS.md · DEPLOY-RUNBOOK.md · DR-RUNBOOK.md
             deploy-validation-report.md · adr/ · posts/ · mkdocs.yml
root         README · Taskfile.yml · renovate.json · .sops.yaml · .gitignore · VERSION · CHANGELOG.md
```

Credential → role map lives in §8 of the chat design and the project memory; secret VALUES
are never committed — only SOPS-encrypted ciphertext or out-of-band application at a gate.

## 3. Operating rules

1. **Branch & PR.** All work on branch **`build`**. `main` is never committed to directly;
   integration is via **PR `build → main`** (a gate). The cluster tracks a tag, not a branch.
2. **SemVer, mandatory.** Releases are `vMAJOR.MINOR.PATCH`. The tracked revision is defined
   **once** (in `kubernetes/apps/platform-appset.yaml`) with a matching pin in
   `kubernetes/bootstrap/root-app.yaml`; `scripts/release.sh` bumps both + `VERSION` +
   stamps `CHANGELOG.md`, then commits & tags. No cluster change without a new tag.
3. **Upstream verification — do NOT trust training data.** Before authoring any component's
   config, fetch its **current** upstream docs (version + values/CRD schema + breaking
   changes) and record the result in `VERIFIED-VERSIONS.md` (version, source URL, date).
   Assume the software changed since training. Every phase that authors config has a `.0`
   "VERIFY" checkpoint that must complete first. Source-of-truth URLs are listed in
   `VERIFIED-VERSIONS.md`.
4. **Gate policy (minimal input).** Two tiers:
   - **Autonomous** (no prompt; tracked + committed to `build`): all file authoring,
     scaffolding, `terraform plan`, helm/kubeconform/talosctl **validate**, upstream
     verification, doc writing, PROGRESS updates.
   - **🚦 Approval gate** (the only inputs required): ① `terraform apply` (real VMs) ·
     ② Talos secret generation + bootstrap (real nodes/PKI) · ③ first in-cluster apply
     (Cilium/Argo/secrets) · ④ open/merge PR `build→main` · ⑤ cut a release tag ·
     ⑥ any restore/teardown/shutdown that touches running infra.
   - **Secrets** are never fabricated; real values are sourced from `~/.credentials/` and
     SOPS-encrypted at the relevant gate, never echoed, never committed in plaintext.

## 4. Checkpoint & tracking system (robust, layered, context-resilient)

**Six layers** so progress survives context loss and is auditable:

| Layer | Artifact | Purpose |
|---|---|---|
| 1 Plan | `docs/PLAN.md` (this) | immutable spec: phases → checkpoints |
| 2 Ledger | `docs/PROGRESS.md` | live status + **RESUME HERE** pointer (mutable) |
| 3 Evidence | `docs/validation/<checkpoint>.*` | saved proof of each exit-verify (plan output, kubeconform, talosctl validate, kubectl) |
| 4 VCS | per-checkpoint commits on `build` | revertible history; commit msg = checkpoint id |
| 5 Versions | `docs/VERIFIED-VERSIONS.md` | upstream-verified pins + source + date |
| 6 Memory | project memory file | points a fresh session at layers 1–5 on disk |

**Checkpoint protocol.** Every checkpoint has: `ID` · `deps` (checkpoints that must be ☑) ·
`action` · `exit-verify` (a concrete command + expected result) · `artifact` (path under
`docs/validation/`) · `rollback`. State transitions **☐ pending → ◐ in-progress → ☑ done**
only when exit-verify passes **and** evidence is written **and** the commit is made **and**
`PROGRESS.md` RESUME-HERE is advanced. A failed verify sets **⚠ blocked** with a note.

## 5. Phases & checkpoints

Legend: 🚦 = approval gate · `.0` = mandatory upstream-VERIFY checkpoint. Each phase ships its
matching blog post (§6).

### Phase 0 — Foundation
| ID | Action | Exit-verify |
|---|---|---|
| P0.1 | `git init`; create branch `build`; scaffold dirs; `.gitignore` (clusterconfig/, kubeconfig, *.tfstate, .terraform/, plaintext secrets) | `git rev-parse --abbrev-ref HEAD` = `build`; tree present |
| P0.2 | `.sops.yaml` creation rules → recipient = public key of `homeoffice-k8s.agekey` | `sops` encrypts a scratch file to the correct recipient; `sops -d` round-trips |
| P0.3 | `Taskfile.yml` + repo-pinned `scripts/install-prereqs.sh` (from the disposable installer) | `task --list` shows phased targets |
| P0.4 | docs skeleton: PLAN, PROGRESS, VERIFIED-VERSIONS, `adr/0000-template.md`, `mkdocs.yml`, `posts/` stubs | files exist; mkdocs nav valid |
| P0.5 | `renovate.json` skeleton (datasources: github-releases for Talos, helm for charts, docker, terraform) | JSON valid (`jq .`) |

### Phase 1 — Terraform: template + VMs
| ID | Action | Exit-verify |
|---|---|---|
| P1.0 | VERIFY: `vmware/vsphere` provider current version + `vsphere_virtual_machine` schema; Talos Image Factory OVA process; latest Talos **v1.13.x** + its k8s version | rows written to VERIFIED-VERSIONS |
| P1.1 | Build Image Factory schematic (vmware, `iscsi-tools`+`util-linux-tools`); import OVA → vCenter template (govc/content-library), scripted + documented | `govc vm.info <template>` exists, `template: true` |
| P1.2 | `terraform/` scaffold: `versions.tf` (+ Wasabi S3 backend), `providers.tf` (env creds), `variables.tf`, `terraform.tfvars` (discovered facts) | `terraform init` ok; `terraform validate` ok |
| P1.3 | `vms.tf` (6 clones, OS+data disks, MAC-pin, network, root pool + folder), `outputs.tf` | `terraform plan` = 6 VMs, no errors → `docs/validation/P1.3.plan.txt` |
| 🚦 P1.4 | `terraform apply` | 6 VMs powered; Talos maintenance mode; govc reports guest IPs |

### Phase 2 — Talos config + bootstrap (no SSH)
| ID | Action | Exit-verify |
|---|---|---|
| P2.0 | VERIFY: talosctl **v1.13** machine-config schema (install, disks, kubelet extraMounts, vip, taints) + `talosctl gen` flags | rows in VERIFIED-VERSIONS |
| P2.1 | `talos/patches/{controlplane,worker,node-*}.yaml` + `scripts/talos-gen.sh` (renders per-node configs: static `.31–.36`, VIP `.30`, CNI none, proxy off, CP taint, worker Longhorn disk) | `talosctl validate --mode metal` passes ×6 → `docs/validation/P2.1.validate.txt` |
| 🚦 P2.2 | `talosctl gen secrets` → `talos/secrets.sops.yaml` (SOPS) | `sops -d` round-trips; recipient matches `.sops.yaml` |
| 🚦 P2.3 | `scripts/bootstrap.sh`: discover maint IPs (govc) → `apply-config` → bootstrap etcd on cp1 → fetch kubeconfig | `talosctl etcd members` = 3; `kubectl get nodes` = 6 (NotReady) → evidence saved |

### Phase 3 — Cilium (CNI, LB, Gateway API)
| ID | Action | Exit-verify |
|---|---|---|
| P3.0 | VERIFY: current Cilium chart + values keys (`kubeProxyReplacement`, `l2announcements`, `gatewayAPI`, LB-IPAM CRDs); Gateway API CRD release | rows in VERIFIED-VERSIONS |
| P3.1 | `kubernetes/apps/cilium/` (kustomization helmChart + values + `lb-pool.yaml` + `l2policy.yaml`) | `helm template` + `kubeconform` ok → artifact |
| 🚦 P3.2 | Install Gateway API CRDs + Cilium (bootstrap.sh) | nodes Ready; `cilium status`; LB pool `.120–.139` present |

### Phase 4 — Argo CD + root app-of-apps
| ID | Action | Exit-verify |
|---|---|---|
| P4.0 | VERIFY: current Argo chart + KSOPS wiring (image tag, repo-server initContainer/volume keys) + argoproj API versions | rows in VERIFIED-VERSIONS |
| P4.1 | `kubernetes/bootstrap/argocd/` (values, `repo-ssh.sops.yaml`), `root-app.yaml`, `apps/platform-appset.yaml` | `helm template` + `kubeconform` on appset/root-app ok |
| 🚦 P4.2 | Apply `sops-age` + `repo-ssh` secrets (out-of-band) → install Argo → apply `root-app` | repo-server 1/1 (KSOPS ok); `root` app present |

### Phase 5 — Release / tag mechanism
| ID | Action | Exit-verify |
|---|---|---|
| P5.1 | `scripts/release.sh` + `VERSION` + `CHANGELOG.md`; single-pin discipline (appset + root-app) | dry-run bumps exactly 2 pins; rejects non-SemVer |

### Phase 6 — SOPS/age secret-flow ergonomics
| ID | Action | Exit-verify |
|---|---|---|
| P6.1 | Per-app `secret-generator.yaml` (KSOPS) pattern + `.example` siblings + Taskfile `sops:*` helpers | KSOPS generator renders locally where possible; documented |

### Phase 7 — Platform stack (GitOps waves)
Sync-wave order: `-10` cilium · `-5` cert-manager · `0` gateway · `1` longhorn · `2` cnpg-operator ·
`5` velero · `5` etcd-backup · `10` cnpg-cluster · `15` authentik. Each component:
`.0` VERIFY upstream → author kustomize dir → `helm template`+`kubeconform` (artifact).
| ID | Component | Verify note |
|---|---|---|
| P7.1 | cert-manager + Cloudflare DNS-01 ClusterIssuer | current chart + solver schema; public recursive NS for split-horizon |
| P7.2 | gateway (`Gateway main` + wildcard `Certificate` + sample HTTPRoute) | GatewayClass `cilium` |
| P7.3 | longhorn (workers-only scheduling, replica-3 default + replica-1 SC, **backup-target setting name**) | verify current backupTarget/defaultBackupStore key |
| P7.4 | cnpg-operator | current operator version + `Cluster` API group/version |
| P7.5 | cnpg-cluster (3 instances, anti-affinity, replica-1 SC, backup to Wasabi) | current `Cluster`/`ScheduledBackup` schema |
| P7.6 | authentik (chart, CNPG DSN, Redis, HTTPRoute, media) | current chart values |
| P7.7 | velero (chart + AWS plugin for Wasabi S3, schedules) | current plugin/image + BSL schema |
| P7.8 | etcd-backup (Talos-native `etcd snapshot` CronJob → Wasabi) | talosctl snapshot flow; pinned image |
| 🚦 P7.9 | Cut `v0.1.0`, advance pin → Argo syncs the platform | all apps Synced/Healthy; wildcard cert issued → evidence |

### Phase 8 — Backup wiring + Veeam window
| ID | Action | Exit-verify |
|---|---|---|
| P8.1 | Confirm each layer lands in Wasabi (etcd snapshot, Velero backup, Longhorn backup) | objects present in bucket → evidence |
| P8.2 | `scripts/cluster-shutdown.sh` + `cluster-startup.sh` (cordon→drain→quiesce CNPG/Longhorn→`talosctl shutdown`; ordered power-on) for the weekly Veeam cold-image | dry-run/documented; 🚦 before any real shutdown |

### Phase 9 — DR validation + report
| ID | Action | Exit-verify |
|---|---|---|
| P9.1 | `docs/DR-RUNBOOK.md` (rebuild from git+age+Wasabi; restore etcd/Velero/Longhorn; Veeam whole-VM fallback) + `deploy-validation-report.md` shakedown | documented restore of each layer (gated where destructive) |

### Phase 10 — Docs finalize + PR
| ID | Action | Exit-verify |
|---|---|---|
| P10.1 | Blog posts 01–08, ADRs, `ARCHITECTURE.md`, `mkdocs.yml` nav | links resolve; mkdocs builds (optional) |
| 🚦 P10.2 | Open PR `build → main` | PR created with summary + checklist |

## 6. Documentation plan (blog-post style — "docs are boring, so blog posts")

`docs/posts/` (mkdocs-material, mermaid), one per layer, first-person, honest tradeoffs:
`01-overview` · `02-vmware-and-terraform` · `03-talos-config-and-secrets` ·
`04-gitops-bootstrap` · `05-networking` · `06-storage-and-databases` ·
`07-identity-and-tls` · `08-backups-and-disaster-recovery`.
Plus `ARCHITECTURE.md` (map + sync-wave table, no duplicated facts), ADRs
(`Context/Decision/Consequences`): all-control-plane-dedicated topology, Terraform-only+talosctl,
Cilium L2+Gateway API, SOPS+age single key, release-pinned GitOps, Longhorn+CNPG storage model,
4-layer backup + 2-host limitation/Veeam. `DEPLOY-RUNBOOK.md` (ordered, proven) and the DR runbook.

## 7. Context-reset protocol (READ THIS FIRST when resuming cold)

1. Read `docs/PROGRESS.md` → the **RESUME HERE** block (current phase/checkpoint, branch, last commit).
2. Read this `PLAN.md` (§5) for the checkpoint spec, and `docs/adr/` + `VERIFIED-VERSIONS.md`
   to rehydrate decisions and pins — **trust the disk, not memory**.
3. `git -C <repo> log --oneline -15` on `build` → confirm the last committed checkpoint.
4. Re-run the **exit-verify** of the last ☑ checkpoint to confirm real state matches the ledger.
   If it diverges, mark ⚠ and reconcile before proceeding.
5. Continue at the first ☐ checkpoint after RESUME HERE. Keep checkpoints small; commit and
   update the ledger after each; never hold state only in context.

## 8. Completeness self-review (every operator requirement → where it's covered)

- [x] Plan saved to disk → this file (`docs/PLAN.md`).
- [x] Checkpoints + robust layered tracking → §4 (six layers) + §5 (per-checkpoint verify) + `PROGRESS.md`.
- [x] Tracking between phases → checkpoint deps + ledger RESUME-HERE + per-checkpoint commits.
- [x] Don't trust training data → §3.3 + every `.0` VERIFY checkpoint + `VERIFIED-VERSIONS.md`.
- [x] Build branch → PR into main → §3.1 + P0.1 / P10.2.
- [x] SemVer mandatory → §3.2 + P5.1 + P7.9.
- [x] Documentation crucial, blog-post style → §6 + per-phase posts + ADRs (reference voice studied).
- [x] Run end-to-end, minimal input → §3.4 gate policy (autonomous vs 6 batched gates).
- [x] Context will be an issue → §4 (on-disk layers) + §7 (reset protocol) + project memory layer.
- [x] Ordered phases per task brief → §5 P1→P10 match VMware→Talos→Cilium→Argo→pin→secrets→stack→backups→DR.
```
