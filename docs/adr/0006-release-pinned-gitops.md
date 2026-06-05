# ADR-0006: Release-pinned GitOps — Argo tracks a SemVer tag, not a branch

- **Status:** Accepted
- **Date:** 2026-06-04

## Context

With Argo CD auto-syncing the platform, the question is *what revision* it tracks. The common
default is a branch (`HEAD` of `main`): every merge deploys immediately. That is convenient but
it couples "I committed" to "the cluster changed" — a doc typo, a half-finished component, or a
mistaken merge all reach the live cluster the moment they land, and "what is actually running"
is a moving target you can only name by commit SHA after the fact.

This project wanted the opposite: commits are cheap and frequent (every checkpoint commits to
the `build` branch), but a *deploy* should be a deliberate, named, revertible event. That points
at tracking an immutable tag instead of a branch, and at making releases boring and mechanical
so the discipline actually holds.

## Decision

Argo CD tracks an **immutable SemVer git tag**, and a release is the only way the cluster
changes:

- The tracked revision is defined **once** in `kubernetes/apps/platform-appset.yaml`
  (`targetRevision`), mirrored in `kubernetes/bootstrap/root-app.yaml`, with the same value in
  `VERSION`. Components are an Argo `ApplicationSet` (one Application per component, sync-wave
  ordered) all sourced at that single pin.
- `scripts/release.sh` (`task release -- X.Y.Z`) bumps those pins in lockstep, promotes the
  `[Unreleased]` section of `CHANGELOG.md`, commits, and tags `vX.Y.Z`. It rejects non-SemVer
  input. **No cluster change without a new tag.**
- Day-to-day work happens on `build`; `main` is integrated only via PR (a gate). The cluster
  follows tags, not either branch — though during initial bring-up it temporarily tracked
  `build` to iterate, then was pinned back to a tag.

## Consequences

- **Easier:** "what's running" is a tag (`v0.1.2`), not a SHA you have to go look up. Rollback
  is repointing to the previous tag. Releases are auditable in `CHANGELOG.md` and atomic across
  all components (one pin). Committing to `build` is safe — it does not touch the cluster.
- **Harder / costs accepted:** an extra step between commit and deploy — nothing ships until a
  tag is cut, so a hotfix is "commit + release," not just "merge." The single-pin discipline
  must be respected (two files + `VERSION` in lockstep); `release.sh` exists precisely so this
  is mechanical rather than manual and error-prone. The bring-up exception (tracking `build`
  briefly) is the kind of drift to avoid once the cluster is live — it is acceptable only
  during initial construction.
