# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The version is the **single platform pin** Argo CD tracks — `targetRevision` in
`kubernetes/bootstrap/root-app.yaml` and `kubernetes/apps/platform-appset.yaml`,
mirrored in `VERSION`. Cut a release with `scripts/release.sh` (or `task release -- X.Y.Z`),
which bumps all three in lockstep, promotes the `[Unreleased]` section below, commits,
and tags `vX.Y.Z`. The first tag `v0.1.0` is cut at P7.9 (the pins are pre-set to it);
`release.sh` bumps from there.

## [Unreleased]

### Added
- ops: `scripts/cluster-shutdown.sh` + `scripts/cluster-startup.sh` for the weekly Veeam
  cold-image window. Shutdown gracefully quiesces the cluster (cordon all → CNPG hibernate →
  drain workers → wait Longhorn volumes detached → `talosctl shutdown` workers then control
  planes → confirm powered off via govc) for a crash-consistent image; startup powers on via
  govc in order (control planes → etcd quorum + API → workers → uncordon → resume CNPG →
  verify). Both support `--dry-run`. (Taskfile `shutdown`/`startup` already wrap them.)
- docs: `docs/DR-RUNBOOK.md` (recovery assets + per-layer restore procedures — etcd
  recover-from-snapshot, full rebuild from git+age+Wasabi, Velero, Longhorn, CNPG Barman
  recovery, Veeam whole-VM fallback) and `docs/deploy-validation-report.md` (build shakedown).

### Fixed
- argocd: add the missing `HTTPRoute` (`kubernetes/bootstrap/argocd/httproute.yaml`) that
  attaches `argocd.k8s-talos1.ap169homeoffice.net` to the Cilium Gateway's `https` listener,
  and apply it from `bootstrap.sh`'s argocd step. The argo-cd chart sets `global.domain` +
  `server.insecure` but creates no Gateway API route, so the host was never wired to the
  Gateway and the UI returned a bare Envoy 404. (Argo CD is bootstrap-managed, not in the
  ApplicationSet, so nothing self-healed it.)
- docs: correct the Longhorn backup-target key in `VERIFIED-VERSIONS.md`
  (`defaultSettings.*` → `defaultBackupStore.*`, the actual Longhorn 1.12 key).

## [0.1.2] - 2026-06-04

### Added
- longhorn: `daily-backup` RecurringJob (group `default`, `task: backup`, cron `0 4 * * *`,
  retain 7) — daily volume backups to the Wasabi backup target. Was deferred from P7.3;
  Longhorn was the only backup layer without a daily schedule (cnpg 02:00 / velero 03:00 /
  etcd 01:00).

### Fixed
- longhorn: set the backup target via `defaultBackupStore.*` instead of `defaultSettings.*`.
  Longhorn 1.12 removed the legacy `backup-target` *setting* and seeds the BackupTarget CRD
  from `defaultBackupStore.{backupTarget,backupTargetCredentialSecret}` — the `defaultSettings`
  keys were silently ignored, leaving the `default` BackupTarget empty (`available: false`).
  (Running cluster also needed a one-time live patch of the `default` BackupTarget — the seed
  ConfigMap is consumed only at first boot.)
- etcd-backup: add `--nodes=172.16.23.31` to the `talosctl etcd snapshot` args. The scoped
  talosconfig sets endpoints but no default node, and `etcd snapshot` targets exactly one
  node — without it talosctl errored "nodes are not set for the command" and the CronJob
  failed on its first real run.

## [0.1.1] - 2026-06-04

### Changed
- gateway: flip the wildcard `Certificate` issuer `letsencrypt-staging` → `letsencrypt-prod`
  for a trusted cert (staging validated the DNS-01/Cloudflare flow end-to-end).

### Fixed
- longhorn: disable the pre-upgrade checker Job (`preUpgradeChecker.jobEnabled: false`).
  Rendered as a helm pre-upgrade hook it became an Argo PreSync hook that deadlocked the
  first sync — the Job needs `longhorn-service-account`, a Sync-phase resource gated behind
  the hook. Longhorn's chart explicitly recommends disabling it for Argo CD / GitOps.
- velero: render CRDs declaratively (`includeCRDs: true`) and disable the chart's CRD-install
  hook (`upgradeCRDs: false`). The chart ships CRDs in `crds/` (excluded by kustomize-helm by
  default), so the `BackupStorageLocation`/`Schedule` CRs failed pre-sync dry-run ("CRD not
  found") and aborted the whole sync before the pre-install hook could create them.
- longhorn: label the `longhorn-system` namespace `pod-security.kubernetes.io/enforce:
  privileged`. Talos enforces `baseline` PSS on all non-kube-system namespaces, which rejects
  the privileged, host-path `longhorn-manager` DaemonSet. Added an explicit Namespace manifest.
- argo: enable `ServerSideDiff=true` (compare-options) on all platform Applications via the
  ApplicationSet. The client-side default diff flagged CRD-schema defaults (Gateway API
  HTTPRoute/Gateway `group`/`kind`/`weight`/`matches.path`) and CNPG mutating-webhook fields
  as perpetual false `OutOfSync` (Healthy but never Synced). SSA-based diff scopes comparison
  to Argo-managed fields.

## [0.1.0] - 2026-06-04

### Added
- Talos Linux v1.13.3 cluster: 6 VMs (3 control-plane HA + 3 workers) on vSphere,
  static IPs `.31`–`.36`, control-plane VIP `.30`; custom image carries the
  `vmtoolsd-guest-agent` extension (talos-vmtoolsd → vCenter guest integration).
- Terraform (`vmware/vsphere` 2.16.0) VM provisioning on the cluster root pool;
  Wasabi S3 state backend.
- Cilium 1.19.4 CNI: kube-proxy-free, L2 LB-IPAM pool `.120`–`.139`, Gateway API
  v1.4.1 (standard + experimental `tlsroutes`) with the `cilium` GatewayClass, Hubble.
- Argo CD 9.5.17 GitOps with KSOPS/SOPS-age decryption; app-of-apps (`root`) +
  10-component platform `ApplicationSet` (sync-wave ordered).
- Platform stack (GitOps waves): cert-manager (Let's Encrypt, Cloudflare DNS-01) +
  Cilium Gateway API gateway with wildcard TLS + Longhorn (workers-only) +
  CloudNativePG operator and a 3-instance HA cluster with Barman Cloud Plugin
  backups + authentik (external CNPG + self-hosted Redis) + Velero + a Talos
  `etcd snapshot` CronJob. All secrets via KSOPS/SOPS-age; backups to Wasabi S3.
- SOPS/age secret flow; bring-up + tooling scripts
  (`talos-image`, `talos-gen`, `bootstrap`, `release`); docs, ADRs, validation evidence.
