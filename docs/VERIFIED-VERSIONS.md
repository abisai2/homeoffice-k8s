# Verified Upstream Versions & Config Notes

> **Rule:** do NOT trust training data for the software stack. Before authoring a
> component's config, fetch its **current** upstream version/schema (live registry, `helm
> show values`, `talosctl images`, GitHub API) and record it here: pinned version, source,
> date, and config-schema notes (esp. keys that changed). Renovate keeps these current.
>
> Status: ⛔ PENDING · ✅ VERIFIED. Filled at each component's `.0` checkpoint.

| Component | Pinned version | Source of truth (verified via) | Verified | Notes |
|---|---|---|---|---|
| Talos Linux | **v1.13.3** ✅ | GitHub releases API (latest v1.13.x) | 2026-06-03 | installed talosctl client matches |
| Kubernetes | **v1.36.1** ✅ | `talosctl images default` (kube-apiserver/kubelet) | 2026-06-03 | etcd v3.6.11; installed kubectl 1.36.1 matches |
| Talos Image Factory | **schematic `613e1592b2da41ae5e265e8789429f22e121aab91cb4deb6bc3c0b6262961245`** ✅ | factory.talos.dev (POST /schematics) | 2026-06-03 | OVA `vmware-amd64.ova` v1.13.3 (206 MiB, HTTP 200); installer image `factory.talos.dev/installer/613e1592…961245:v1.13.3` (use in Talos `install.image`); ext `iscsi-tools` + `util-linux-tools` (vmware platform ships open-vm-tools — no guest-agent ext) |
| Terraform | **v1.15.5** ✅ | installed | 2026-06-03 | supports S3 backend `use_lockfile` |
| vsphere provider | **vmware/vsphere 2.16.0** ✅ | registry.terraform.io/v1/providers/vmware/vsphere | 2026-06-03 | provider MOVED hashicorp→vmware (hashicorp mirror stale at 2.12); init+validate OK; verify `vsphere_virtual_machine`/anti-affinity schema at P1.3 |
| Gateway API CRDs | **v1.5.1** ✅ | GitHub kubernetes-sigs/gateway-api latest | 2026-06-03 | standard channel; install before Cilium gatewayAPI |
| Cilium (chart) | ⛔ | `helm show values` + https://docs.cilium.io | — | `kubeProxyReplacement`, `l2announcements`, `gatewayAPI`, LB-IPAM CRDs (verify at P3.0) |
| Argo CD (chart) | ⛔ | https://artifacthub.io/packages/helm/argo/argo-cd | — | repo-server KSOPS init/volume keys (P4.0) |
| KSOPS | ⛔ | https://github.com/viaduct-ai/kustomize-sops/releases | — | exec plugin image tag for repo-server (P4.0) |
| SOPS | installed ✅ | mgmt | 2026-06-03 | round-trip verified P0.2 |
| cert-manager (chart) | ⛔ | https://cert-manager.io/docs | — | Cloudflare DNS-01 solver; recursive NS for split-horizon (P7.1) |
| Longhorn (chart) | ⛔ | https://longhorn.io/docs | — | **backup-target setting key**; node scheduling (P7.3) |
| CloudNativePG (operator) | ⛔ | https://cloudnative-pg.io/documentation/ | — | `Cluster`/`ScheduledBackup` API group+version (P7.4) |
| Authentik (chart) | ⛔ | https://docs.goauthentik.io | — | external CNPG DSN, Redis, media PVC (P7.6) |
| Velero (chart + plugin) | ⛔ | https://velero.io/docs · velero-plugin-for-aws | — | AWS plugin for Wasabi (custom endpoint/region) (P7.7) |
| Renovate | ⛔ | https://docs.renovatebot.com | — | manager config refined at P7 |
| govc | 0.52.0 ✅ | installed | 2026-06-03 | template import + discovery |
