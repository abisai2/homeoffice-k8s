# homeoffice-k8s

Declarative, reproducible, GitOps-driven Kubernetes on **Talos Linux**, running as
**6 VMs** (3 control-plane + 3 workers) on a **VMware/ESXi** cluster. Infrastructure is
created with **Terraform**; the cluster populates itself from this git repo with **Argo CD**,
**release-pinned to a git tag**.

> Bootstrap from nothing → fully working cluster, from a single git repo + one age key.

## Status

🚧 **Under construction.** This repo is being built phase-by-phase against a checkpointed plan.
The authoritative state lives on disk — start here:

- **[`docs/PLAN.md`](docs/PLAN.md)** — the full phased bootstrap plan + checkpoint spec.
- **[`docs/PROGRESS.md`](docs/PROGRESS.md)** — live build ledger (where we are right now).
- **[`docs/VERIFIED-VERSIONS.md`](docs/VERIFIED-VERSIONS.md)** — upstream-verified version pins.
- **[`docs/UPDATE-RUNBOOK.md`](docs/UPDATE-RUNBOOK.md)** — dependency-update flow (Renovate → review → release → sync).

## Stack

| Area | Choice |
|---|---|
| OS / cluster | Talos Linux v1.13.x, 3 control-plane (HA etcd) + 3 workers, API **VIP** `172.16.23.30` |
| Provisioning | **Terraform** (`vmware/vsphere`) + native `talosctl` bring-up (no Ansible) |
| Secrets | SOPS + age (one key restores Talos PKI **and** k8s secrets) |
| GitOps | Argo CD (app-of-apps) + KSOPS, release-pinned to a SemVer tag |
| CNI + LB | Cilium (kube-proxy replacement, L2 announcements, LB-IPAM) |
| Ingress | Cilium **Gateway API** |
| TLS | cert-manager + Cloudflare DNS-01 (Let's Encrypt) |
| Storage | Longhorn (replicated) + **CloudNativePG** (Postgres) |
| Identity | Authentik (SSO / OIDC) |
| Backups | Talos etcd snapshots + Velero + Longhorn + **Veeam** → external S3 (Wasabi) |

## Documentation

The build is documented as a series of blog posts under [`docs/posts/`](docs/posts/) (mkdocs-material),
with the *why* recorded as ADRs in [`docs/adr/`](docs/adr/). Start from
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the system map + sync-wave order.

## Layout

```
terraform/   vSphere VM provisioning (clone Talos template, disks, network)
talos/       talosctl secrets (SOPS) + machine-config patches
kubernetes/  bootstrap/ (Argo install + root app) and apps/ (ApplicationSet → component kustomize dirs)
scripts/     install-prereqs · talos-gen · bootstrap · cluster shutdown/startup · lint · release
docs/        plan, ledger, runbooks, ADRs, and the blog posts
```
