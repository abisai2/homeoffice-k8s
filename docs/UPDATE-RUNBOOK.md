# Update Runbook — Renovate → review → release → sync

How dependency updates flow from upstream releases into the `k8s-talos1` cluster.
Automation finds and proposes updates; **nothing reaches the cluster without two human
gates** — the PR merge and the release tag. Versions themselves live in
[`VERIFIED-VERSIONS.md`](VERIFIED-VERSIONS.md); this file is the process.

```
upstream release
      │
      ▼
[1] Renovate CronJob (in-cluster, Mon 02:00 UTC) ── detects outdated pins
      │
      ▼
[2] PR per update (+ Dependency Dashboard issue) ── automated, schedule-gated
      │
      ▼  GATE 1: human review + merge
[3] Review: release notes, render hazards, VERIFIED-VERSIONS row ── merge to main
      │           (merging deploys NOTHING — the cluster tracks a tag)
      ▼  GATE 2: release tag
[4] task release -- patch → push tag → apply root-app ── Argo syncs in wave order
```

## 1. Detection (automated)

The `renovate` CronJob (`kubernetes/apps/renovate/`, namespace `renovate`) runs
**Monday 02:00 UTC** against `abisai2/homeoffice-k8s` (platform=github, fine-grained
PAT in the KSOPS secret `renovate-secrets`). What it tracks is defined in the
repo-root [`renovate.json`](../renovate.json):

| Manager | Watches | Examples |
|---|---|---|
| `kustomize` | `helmCharts[].version` in every `kubernetes/apps/*/kustomization.yaml` (HTTP **and** `oci://` repos) | netbox, cilium, cert-manager, longhorn, cnpg-operator, velero, authentik |
| `helm-values` | image pins inside values files | velero AWS plugin, KSOPS image |
| `terraform` | provider pins | `vmware/vsphere` |
| `custom.regex` | `talos_version` in `terraform/terraform.tfvars` | grouped as one `talos` PR |

The **appservices01 docker-services Renovate is a separate instance** (platform=gitea,
`docker-services-*` only) — it never touches this repo.

## 2. PRs + Dependency Dashboard (automated)

- One PR per update (Talos toolchain grouped), with upstream release notes attached.
  Majors get the `major-update` label.
- The in-repo `schedule` (`* 0-6 * * 1`, UTC) limits PR creation to the Monday window;
  detection outside the window parks updates as **Awaiting Schedule**.
- The [Dependency Dashboard issue](https://github.com/abisai2/homeoffice-k8s/issues/13)
  is the control panel: it lists pending/open/rate-limited updates, and ticking a
  checkbox forces that update on the next run (manual run:
  `kubectl -n renovate create job --from=cronjob/renovate renovate-manual`).

## 3. Review + merge (GATE 1 — human)

Per PR, before merging:

1. **Read the upstream release notes** (attached to the PR) for breaking changes,
   values-schema changes, and CRD changes.
2. **Chart PRs — re-check the two offline-render hazards** if the chart's templates or
   secret logic changed (we render offline via kustomize+helm, no live cluster):
   - `.Capabilities.APIVersions.Has` gates → silently dropped objects → force the
     `create:`/enable flag in values.
   - `lookup`/`randAlphaNum`/`uuidv4` secret generation → render churn → pin to an
     `existingSecret`. Verify: render the app twice, diff for byte-identical output
     (`task sops:render -- kubernetes/apps/<app>`).
3. **Update the component's row in [`VERIFIED-VERSIONS.md`](VERIFIED-VERSIONS.md)**
   (version, date, any new gotchas) — push to the PR branch.
4. Merge. **A merge to `main` deploys nothing** — Argo tracks the release tag.

**Special case — Talos PRs** (`renovate/talos` branch): this is a cluster **OS
upgrade**, not a config bump. Do NOT just merge: it needs a new Image Factory
installer/schematic build (`scripts/talos-image.sh`), the rolling
`talosctl upgrade` procedure, and the Veeam window awareness. Majors of
PostgreSQL-adjacent things (CNPG operator) and Cilium minors also deserve a read of
their dedicated upgrade docs before merging.

## 4. Release + sync (GATE 2 — human)

Batch one or more merged update PRs into a release:

```bash
git checkout -b chore/release && git pull https://github.com/abisai2/homeoffice-k8s.git main
task release -- patch                     # bumps both targetRevision pins + VERSION + CHANGELOG, tags vX.Y.Z
git push https://github.com/abisai2/homeoffice-k8s.git HEAD vX.Y.Z   # SSH push is read-only; HTTPS w/ write token
# PR + merge the release commit to main, then point the cluster at the tag:
kubectl apply -f kubernetes/bootstrap/root-app.yaml   # declarative equiv of: argocd app set root --revision vX.Y.Z
```

Argo syncs the bumped apps in sync-wave order; watch with
`kubectl -n argocd get applications` until Synced/Healthy, then spot-check the
changed app (pods, app URL).

## Operational notes

- Renovate runner image is the **major tag** `renovate/renovate:43` +
  `imagePullPolicy: Always` (floats 43.x; an exact pin couldn't self-update because
  the `kubernetes` manager isn't enabled). Bump the major in
  `kubernetes/apps/renovate/cronjob.yaml` when upstream cuts 44.
- Run logs: `kubectl -n renovate logs job/<job-name>`; the job history keeps the
  last 3 runs.
- If a chart update breaks the offline render, the Argo app for that component goes
  Unknown/Degraded at sync — `task sops:render -- kubernetes/apps/<app>` locally
  reproduces the repo-server's exact render path.
