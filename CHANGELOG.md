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
