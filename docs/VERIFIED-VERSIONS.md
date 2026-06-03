# Verified Upstream Versions & Config Notes

> **Rule:** do NOT trust training data for the software stack. Before authoring a
> component's config, fetch its **current** upstream docs and record here: the pinned
> version, the authoritative source URL, the date verified, and any config-schema notes
> (especially keys that changed). Renovate keeps these current after bootstrap.
>
> Status: ⛔ PENDING (not yet verified) · ✅ VERIFIED. Fill the row at the component's `.0` checkpoint.

| Component | Pinned version | Source of truth (verify here) | Verified | Notes |
|---|---|---|---|---|
| Talos Linux | _v1.13.x_ ⛔ | https://github.com/siderolabs/talos/releases · https://www.talos.dev/v1.13/ | — | confirm latest 1.13 patch + shipped Kubernetes version |
| Talos Image Factory | schematic ⛔ | https://factory.talos.dev | — | vmware platform; extensions iscsi-tools + util-linux-tools |
| Kubernetes | _as shipped_ ⛔ | (from Talos release notes) | — | match kubectl client to this |
| Terraform | ≥1.9 ⛔ | https://developer.hashicorp.com/terraform | — | `use_lockfile` S3 backend needs ≥1.10 — verify |
| vsphere provider | ⛔ | https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs | — | `vsphere_virtual_machine`, anti-affinity rule schema |
| Cilium (chart) | ⛔ | https://docs.cilium.io · https://github.com/cilium/cilium/releases | — | `kubeProxyReplacement`, `l2announcements`, `gatewayAPI`, LB-IPAM CRDs |
| Gateway API CRDs | ⛔ | https://github.com/kubernetes-sigs/gateway-api/releases | — | standard channel; install before Cilium gatewayAPI |
| Argo CD (chart) | ⛔ | https://artifacthub.io/packages/helm/argo/argo-cd | — | repo-server KSOPS init/volume keys |
| KSOPS | ⛔ | https://github.com/viaduct-ai/kustomize-sops/releases | — | exec plugin image tag for repo-server |
| SOPS | ⛔ | https://github.com/getsops/sops/releases | — | |
| cert-manager (chart) | ⛔ | https://cert-manager.io/docs · https://artifacthub.io/packages/helm/cert-manager/cert-manager | — | Cloudflare DNS-01 solver; recursive NS for split-horizon |
| Longhorn (chart) | ⛔ | https://longhorn.io/docs · https://github.com/longhorn/longhorn/releases | — | **backup-target setting key** (backupTarget vs defaultBackupStore); node scheduling |
| CloudNativePG (operator) | ⛔ | https://cloudnative-pg.io/documentation/ | — | `Cluster`/`ScheduledBackup` API group+version |
| Authentik (chart) | ⛔ | https://docs.goauthentik.io · https://artifacthub.io/packages/helm/goauthentik/authentik | — | external CNPG DSN, Redis, media PVC |
| Velero (chart + plugin) | ⛔ | https://velero.io/docs · https://github.com/vmware-tanzu/velero-plugin-for-aws | — | AWS plugin for Wasabi (S3-compatible, custom endpoint/region) |
| Renovate | ⛔ | https://docs.renovatebot.com | — | datasources: github-releases, helm, docker, terraform |
| govc | 0.52.0 ✅ | (installed on mgmt) | 2026-06-03 | VMware CLI for template import + discovery |
