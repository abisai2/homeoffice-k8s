# ADR-0001: VMware guest integration via the vmtoolsd-guest-agent extension

- **Status:** Accepted
- **Date:** 2026-06-03

## Context

vCenter reported the nodes' VMware Tools as `guestToolsUnmanaged` / version `2147483647`
/ **Not running**, with no guest IP or hostname. Investigation (and the powered-off,
never-booted template showing the *identical* values) established that the
`guestToolsUnmanaged`/`2147483647` flag is **static metadata baked into the Talos VMware
OVA** — not evidence of a running daemon. Talos is an immutable OS with no package
manager; the only way to run an actual VMware guest agent is the `siderolabs/vmtoolsd-guest-agent`
system extension (which ships `talos-vmtoolsd`, a slim Go reimplementation — not upstream
open-vm-tools). The original schematic (`613e1592…`) carried only `iscsi-tools` +
`util-linux-tools`, so no agent ran.

The operator requires VMware Tools functional in the environment (guest IP/hostname,
heartbeat, and vCenter power control surface details only available with a running agent),
and requires the fix to be repeatable. Tension: it adds an extension (larger image,
another reboot of every node, and the node-image build — previously a manual P1.1 step —
must become reproducible) in exchange for vСenter-side visibility that the cluster does
not strictly need to function.

## Decision

Add `siderolabs/vmtoolsd-guest-agent` to the node image. Encode the image as code:
`talos/image/schematic.yaml` is the canonical extension set; `scripts/talos-image.sh`
deterministically reproduces the schematic ID, OVA, and template import; and
`talos/patches/common.yaml` pins the resulting installer
(`factory.talos.dev/installer/a28d8637…77d7:v1.13.3`). Existing nodes get it via a rolling
`talosctl upgrade -i <installer>`; future clones get it from the rebuilt template.

## Consequences

- **Easier:** vCenter shows guest IP/hostname, heartbeat/health, and clean power
  operations; the node image build is now reproducible from source (closes the manual-P1.1
  gap), so the extension set is reviewable and Renovate-trackable.
- **Harder / costs accepted:** every node reboots once to take the new image (safe here —
  empty cluster, etcd quorum tolerates one CP at a time); the OVA template must be rebuilt
  to keep new clones consistent (replacing the old template is a destructive, operator-gated
  step); slightly larger image. vCenter will still display `Unmanaged` / `2147483647` — that
  is correct and permanent for open-vm-tools (guest-managed); what changes is **Running** +
  IP/hostname/heartbeat. The agent is a management convenience, not a cluster dependency
  (Talos handles time sync and shutdown itself).
