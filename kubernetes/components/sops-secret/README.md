# KSOPS secret pattern

How an app ships an encrypted Kubernetes Secret in this GitOps repo. Argo CD's
repo-server decrypts it at render time via the KSOPS exec plugin (wired in
`kubernetes/bootstrap/argocd/values.yaml`: ksops init container, the `sops-age`
secret mounted, `SOPS_AGE_KEY_FILE` set, and
`kustomize.buildOptions: --enable-alpha-plugins --enable-exec --enable-helm`).

This directory is a **reference** — it is not deployed (the platform ApplicationSet
only reads `kubernetes/apps/*`). The `secret.sops.yaml` here holds fake values so the
pattern renders end-to-end as a worked example.

## Files

| File | In git? | Purpose |
|------|---------|---------|
| `secret.example.yaml`  | yes, **plaintext** | placeholder showing the Secret's shape (no real values) |
| `secret.sops.yaml`     | yes, **encrypted** | the real Secret, SOPS-encrypted to the cluster age key |
| `secret-generator.yaml`| yes | KSOPS generator: tells kustomize to decrypt + emit `secret.sops.yaml` |
| `kustomization.yaml`   | yes | references the generator under `generators:` |

## Add an encrypted secret to an app

```bash
APP=kubernetes/apps/<name>
cp kubernetes/components/sops-secret/secret.example.yaml   "$APP/secret.sops.yaml"
cp kubernetes/components/sops-secret/secret-generator.yaml "$APP/secret-generator.yaml"
# edit "$APP/secret.sops.yaml": real name/namespace/keys (still plaintext at this point)
task sops:encrypt -- "$APP/secret.sops.yaml"     # encrypts in place (catch-all .sops.yaml rule)
# in "$APP/kustomization.yaml" add:   generators: [secret-generator.yaml]
task sops:render -- "$APP"                        # verify it decrypts + renders locally (needs ksops)
git add "$APP/secret.sops.yaml" "$APP/secret-generator.yaml" "$APP/kustomization.yaml"
# optionally keep a redacted "$APP/secret.example.yaml" sibling for documentation
```

## Rules

- **Never commit a plaintext `*.sops.yaml`.** Encrypt immediately after editing
  (`task sops:encrypt`). The `*.example.yaml` sibling is the only plaintext that
  belongs in git, and it must contain no real values.
- Edit an existing encrypted secret with `task sops:edit -- <file>` (decrypts to your
  `$EDITOR`, re-encrypts on save) — never decrypt to a tracked file.
- The age **private** key lives only in `~/.credentials/age/homeoffice-k8s.agekey`
  (and, in-cluster, the `sops-age` Secret). Creation rules + recipient: `.sops.yaml`.
