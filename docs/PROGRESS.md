# homeoffice-k8s — Build Progress Ledger (live state)

> **This file is the live source of truth for where the build is.** It is updated after
> **every** checkpoint. A fresh context rehydrates from here — see `PLAN.md §7`.
> Status legend: ☐ pending · ◐ in-progress · ☑ done · ⚠ blocked.

## RESUME HERE
- **Phase / checkpoint:** P1.3 (next) — author `terraform/vms.tf` (clone `talos-v1.13.3` ×6) + anti-affinity + outputs
- **Branch:** `build`
- **Last commit:** P1.2 (terraform scaffold + Wasabi backend init/validate)
- **Next action:** P1.3 — write `vms.tf` (vsphere_virtual_machine clone from template per `var.nodes`: OS disk, optional 300G data disk on workers, MAC-pinned NIC on `vds01_pg-Kubernetes`), `anti-affinity.tf` (DRS should-rules: separate CPs, separate workers), `outputs.tf` (name→MAC/ip). Verify `terraform plan` = 6 to add → `docs/validation/P1.3.plan.txt`. Then 🚦-free P1.4 apply.
- **TF env reminder:** export `AWS_ACCESS_KEY_ID/SECRET` from `wasabi-homeoffice-k8s.creds` (backend) and `VSPHERE_USER/PASSWORD` from `vcenter-admin.creds` (provider) before plan/apply.
- **Key facts:** template `talos-v1.13.3` in `/ap169home-dc/vm/Templates` (config.template=true) · schematic `613e1592…961245` · installer img `factory.talos.dev/installer/613e1592…961245:v1.13.3` · network `vds01_pg-Kubernetes` · ds `fs1-esxi-ds1` · pool `Kubernetes Pool` · folder `/vm/Kubernetes` · TF creds via `vcenter-admin.creds` (VSPHERE_USER/PASSWORD env).
- **Verified pins:** Talos v1.13.3 · k8s v1.36.1 · vsphere 2.12.0 · Gateway API v1.5.1.
- **Remaining pauses (max-autonomy):** 🚦 only **PR build→main (P10.2)** and any **destructive restore/teardown** (P8.2/P9.1). Everything else (apply, bootstrap, in-cluster, tags) runs unattended.

## Gate policy (confirmed: Maximum autonomy)
Autonomous (no pause): authoring, scaffolding, `terraform apply`, Talos secrets+bootstrap, in-cluster
applies, release tags, commits to `build` — all tracked here + committed.
Approval required ONLY: ④ PR build→main, ⑥ destructive restore/teardown/shutdown of running infra.

## Checkpoint status

### Phase 0 — Foundation ✅
- ☑ P0.1 git init + `build` branch + scaffold + .gitignore — `cbbbaf5`
- ☑ P0.2 `.sops.yaml` creation rules (homeoffice-k8s age recipient; round-trip verified) — `997e088`
- ☑ P0.3 Taskfile + repo-pinned install-prereqs.sh — `19eabea`
- ☑ P0.4 docs skeleton (PLAN/PROGRESS/VERIFIED-VERSIONS/adr/mkdocs/posts) — `058c925`
- ☑ P0.5 renovate.json skeleton (valid JSON) — `58b1296`

### Phase 1 — Terraform: template + VMs
- ☑ P1.0 VERIFY — Talos v1.13.3, k8s v1.36.1, vsphere provider 2.12.0, Gateway API v1.5.1
- ☑ P1.1 Image Factory schematic `613e1592…` + OVA → vCenter template `talos-v1.13.3` (config.template=true) — evidence `docs/validation/P1.1.template.txt`
- ☑ P1.2 terraform scaffold + Wasabi backend (vmware/vsphere 2.16.0, `init`+`validate` OK) — evidence `docs/validation/P1.2.init.txt`
- ☐ P1.3 vms.tf + anti-affinity + outputs (`plan` = 6 VMs)
- ☐ 🚦 P1.4 terraform apply (real VMs)

### Phase 2 — Talos config + bootstrap
- ☐ P2.0 VERIFY talosctl v1.13 machine-config schema
- ☐ P2.1 patches + talos-gen.sh (`validate --mode metal` ×6)
- ☐ 🚦 P2.2 gen secrets → secrets.sops.yaml
- ☐ 🚦 P2.3 bootstrap (etcd 3 members; 6 nodes NotReady)

### Phase 3 — Cilium
- ☐ P3.0 VERIFY Cilium chart + values keys + Gateway API CRDs
- ☐ P3.1 cilium kustomize dir (helm template + kubeconform)
- ☐ 🚦 P3.2 install Cilium + Gateway API CRDs (nodes Ready)

### Phase 4 — Argo CD + root app
- ☐ P4.0 VERIFY Argo chart + KSOPS wiring
- ☐ P4.1 bootstrap/argocd + root-app + platform-appset (lint)
- ☐ 🚦 P4.2 apply secrets + install Argo + root-app

### Phase 5 — Release/tag mechanism
- ☐ P5.1 release.sh + VERSION + CHANGELOG (SemVer-enforced)

### Phase 6 — Secret-flow ergonomics
- ☐ P6.1 KSOPS secret-generator pattern + .example + Taskfile sops helpers

### Phase 7 — Platform stack (GitOps waves)
- ☐ P7.1 cert-manager + Cloudflare DNS-01
- ☐ P7.2 gateway + wildcard Certificate
- ☐ P7.3 longhorn (workers-only, replica-3 + replica-1 SC)
- ☐ P7.4 cnpg-operator
- ☐ P7.5 cnpg-cluster (3-instance HA)
- ☐ P7.6 authentik
- ☐ P7.7 velero (Wasabi BSL + schedules)
- ☐ P7.8 etcd-backup (Talos-native CronJob)
- ☐ 🚦 P7.9 cut v0.1.0 + advance pin (apps Synced/Healthy)

### Phase 8 — Backup wiring + Veeam window
- ☐ P8.1 verify each backup lands in Wasabi
- ☐ P8.2 cluster-shutdown.sh / cluster-startup.sh (🚦 before real run)

### Phase 9 — DR validation + report
- ☐ P9.1 DR-RUNBOOK + deploy-validation-report (gated restores)

### Phase 10 — Docs finalize + PR
- ☐ P10.1 posts 01–08 + ADRs + ARCHITECTURE.md + mkdocs nav
- ☐ 🚦 P10.2 open PR build→main

## Decision log
Locked decisions are recorded as ADRs under `docs/adr/`. Environment facts + credential map
are in `PLAN.md §1` and the project memory.

## Event log (append-only)
- (init) Ledger created. Awaiting go on P0.1.
- P0 complete: repo scaffolded on `build`, SOPS round-trip verified, 5 checkpoint commits (`cbbbaf5`..`58b1296`). Tooling verified: terraform 1.15.5, kubectl 1.36.1, talosctl/sops/age/govc/cilium/argocd/velero present. Wasabi region us-east-1. Gate policy: maximum autonomy. Next: P1.0.
- P1.1: Talos v1.13.3 OVA (schematic 613e1592…) imported to fs1-esxi-templates as template talos-v1.13.3 (config.template=true). Build via factory.talos.dev; vmware-amd64.ova 206 MiB.
- P1.2: Wasabi buckets created (homeoffice-k8s-tfstate versioned, homeoffice-k8s-backups). Terraform scaffold authored; provider corrected hashicorp→vmware/vsphere 2.16.0; init against Wasabi S3 backend (use_lockfile) + validate succeeded.
