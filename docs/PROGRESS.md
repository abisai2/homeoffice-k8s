# homeoffice-k8s — Build Progress Ledger (live state)

> **This file is the live source of truth for where the build is.** It is updated after
> **every** checkpoint. A fresh context rehydrates from here — see `PLAN.md §7`.
> Status legend: ☐ pending · ◐ in-progress · ☑ done · ⚠ blocked.

## RESUME HERE
- **Phase / checkpoint:** P0.1 (not yet started — awaiting operator go + gate-policy confirm)
- **Branch:** `build` (not yet created)
- **Last commit:** none
- **Next action:** on go, execute P0.1 (`git init` + `build` branch + scaffold).
- **Open approval gates ahead:** 🚦 P1.4 apply · P2.2 secrets · P2.3 bootstrap · P3.2/P4.2 in-cluster · P7.9 tag · P8.2/P9.1 restore/shutdown · P10.2 PR.

## Gate policy (confirmed: ___)
Autonomous: authoring, scaffolding, `terraform plan`, validate/lint, verification, docs, commits to `build`.
Approval required: ① terraform apply ② Talos secrets+bootstrap ③ first in-cluster apply ④ PR build→main ⑤ release tag ⑥ restore/teardown/shutdown.

## Checkpoint status

### Phase 0 — Foundation
- ☐ P0.1 git init + `build` branch + scaffold + .gitignore
- ☐ P0.2 `.sops.yaml` creation rules (homeoffice-k8s age recipient)
- ☐ P0.3 Taskfile + repo-pinned install-prereqs.sh
- ☐ P0.4 docs skeleton (PLAN/PROGRESS/VERIFIED-VERSIONS/adr/mkdocs/posts)
- ☐ P0.5 renovate.json skeleton

### Phase 1 — Terraform: template + VMs
- ☐ P1.0 VERIFY vsphere provider + Image Factory + Talos v1.13.x
- ☐ P1.1 Image Factory schematic + OVA → vCenter template
- ☐ P1.2 terraform scaffold + Wasabi backend (`init`/`validate`)
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
