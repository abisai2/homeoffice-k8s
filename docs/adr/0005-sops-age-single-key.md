# ADR-0005: SOPS + age, one key for Talos PKI and Kubernetes secrets

- **Status:** Accepted
- **Date:** 2026-06-04

## Context

Two kinds of secret material must live somewhere durable: the **Talos PKI root**
(`talosctl gen secrets` — the cluster CA, etcd CA, service-account keys, bootstrap tokens) and
the **Kubernetes application secrets** (Cloudflare token, Wasabi S3 creds, Authentik secret key,
CNPG/Redis passwords, the Argo repo deploy key). The goal of the project is to rebuild the whole
cluster *from a single git repo plus one key* — which means the secrets have to be committed, and
committing plaintext secrets is a non-starter.

The options were: keep secrets out of git entirely (a vault/secret-store the cluster pulls
from — another stateful dependency to run, back up, and bootstrap before anything else), or
encrypt them *into* git. Encrypting into git keeps the "one repo + one key" property and makes
the secrets versioned and reviewable as ciphertext. The risk to manage is key custody: one key
that unlocks everything is also a single thing that, if lost, loses everything, and if leaked,
leaks everything.

## Decision

Encrypt all secret material into git with **SOPS + age, using one key**
(`~/.credentials/age/homeoffice-k8s.agekey`):

- `.sops.yaml` sets the age recipient (the key's public half) as the creation rule for every
  `*.sops.yaml`.
- The **Talos PKI** lives at `talos/secrets.sops.yaml`; `talos-gen.sh` decrypts it at render
  time. It is never placed in Terraform state.
- **Kubernetes secrets** are decrypted in-cluster by **KSOPS** (`viaductoss/ksops:v4.5.1`)
  wired into the argocd-repo-server, so Argo renders `*.sops.yaml` → real Secrets during sync.
  The age private key is applied once, out of band, as the `sops-age` secret.
- Each app follows a `secret-generator.yaml` + `secret.sops.yaml` (+ a plaintext
  `secret.example.yaml` sibling) pattern; real values come from `~/.credentials/` and are
  encrypted at the relevant gate, never echoed, never committed in plaintext.

## Consequences

- **Easier:** the entire system — OS PKI and app secrets alike — restores from git + one age
  key. No external secret store to run or bootstrap first; secrets are versioned, diffable as
  ciphertext, and survive a full rebuild. One mental model and one tool for both layers.
- **Harder / costs accepted:** the age key is the linchpin of disaster recovery — lose it and
  the backups are unreadable, leak it and everything is exposed. Custody is therefore a
  first-class concern (it lives only in `~/.credentials/`, is the documented #1 recovery asset
  in the DR runbook, and must itself be backed up out of band). Rotation means re-encrypting
  every `*.sops.yaml`. SOPS adds a render-time decryption step in both the talos-gen path and
  the Argo repo-server (the KSOPS initContainer/volume wiring) — operational surface that has
  to keep working for syncs to succeed.
