# ADR-0003: Terraform for VMs, talosctl for the cluster — no Ansible

- **Status:** Accepted
- **Date:** 2026-06-04

## Context

Two layers need automating: the VMware infrastructure (six VMs cloned from a Talos template,
disks, NICs, MAC pins) and the cluster itself (machine config, secrets, etcd bootstrap). The
home lab's older infrastructure leaned on Ansible, so the default would have been to reach for
it again here.

Talos changes that calculus. It is an immutable, API-driven OS with no SSH and no package
manager — the very things Ansible's SSH-and-modules model exists to drive. There is nothing for
Ansible to log into. Talos is configured declaratively by applying a machine-config document
over its gRPC API with `talosctl`, which is the native, first-class tool for the job. Bringing
Ansible into the loop would mean wrapping `talosctl`/`govc` calls in `command:`/`shell:` tasks —
all of Ansible's ceremony, none of its idempotent modules.

## Decision

Use **two purpose-built tools and no Ansible**:

- **Terraform** (`vmware/vsphere` provider) owns the VMware layer — `terraform/` clones the
  template into six VMs with static MACs, the OS disk, and the workers' 300 GiB data disk.
  State lives in a Wasabi S3 backend and holds vSphere data only (non-precious; never PKI).
- **`talosctl` driven by shell scripts** owns the cluster — `scripts/talos-gen.sh` renders
  per-node configs from `talos/patches/`, and `scripts/bootstrap.sh` discovers the
  maintenance-mode IPs, applies the configs, bootstraps etcd on `cp1`, and fetches the
  kubeconfig.

## Consequences

- **Easier:** each tool is used for what it is good at — Terraform's plan/apply/state for
  cloud resources, `talosctl`'s native API for the OS. No SSH key distribution, no inventory,
  no `command:` wrappers. Fewer moving parts and one less language/runtime to maintain.
- **Harder / costs accepted:** two tools instead of one orchestrator, so the bring-up order
  lives in `scripts/` and the runbook rather than a single playbook. The shell scripts are
  bespoke (idempotency is our responsibility, not a module's) — kept small, `bash -n`/shellcheck
  clean, and checkpoint-verified. Anyone expecting an Ansible repo has a short ramp; the README
  and posts call out the split explicitly.
