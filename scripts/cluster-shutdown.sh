#!/usr/bin/env bash
# Graceful cold-shutdown of the k8s-talos1 cluster for the weekly Veeam cold-image.
#
# Order: preflight health -> cordon ALL nodes -> hibernate CNPG -> drain workers ->
# wait Longhorn volumes detached -> `talosctl shutdown` workers -> `talosctl shutdown`
# control planes (etcd stops clean) -> confirm powered off via govc. Cordoning everything
# FIRST means drained pods terminate in place (nowhere to reschedule) instead of churning
# across shrinking capacity. etcd data + Longhorn replicas persist on the (now stopped)
# VM disks, so the Veeam image is crash-consistent and `cluster-startup.sh` brings it back.
#
# Usage:
#   set -a; source ~/.credentials/api-tokens/vcenter-admin.creds; set +a   # GOVC_* (power-state check)
#   ./scripts/cluster-shutdown.sh --dry-run     # print the plan, touch nothing
#   ./scripts/cluster-shutdown.sh               # 🚦 REAL shutdown — gated, run by the operator
#
# Pairs with scripts/cluster-startup.sh. GOVC_* is optional (only the final power-off
# confirmation needs it); the shutdown itself is kubectl + talosctl.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$REPO"
: "${SOPS_AGE_KEY_FILE:=$HOME/.credentials/age/homeoffice-k8s.agekey}"; export SOPS_AGE_KEY_FILE

OUT="talos/clusterconfig"
TC="$OUT/talosconfig"
export KUBECONFIG="$REPO/$OUT/kubeconfig"
VMDIR="/ap169home-dc/vm/Kubernetes"
CP_NODES=(k8s-cp1:172.16.23.31 k8s-cp2:172.16.23.32 k8s-cp3:172.16.23.33)
WK_NODES=(k8s-worker1:172.16.23.34 k8s-worker2:172.16.23.35 k8s-worker3:172.16.23.36)
CNPG_NS="databases"; CNPG_CLUSTER="postgres"
DRAIN_TIMEOUT="300s"

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
say(){ printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
require(){ command -v "$1" >/dev/null || { echo "MISSING: $1"; exit 1; }; }
# run a MUTATING command (skipped/echoed under --dry-run)
run(){ if [ "$DRY" = 1 ]; then echo "  [dry-run] $*"; else echo "  + $*"; "$@"; fi; }

require kubectl; require talosctl
HAVE_GOVC=0; command -v govc >/dev/null && [ -n "${GOVC_URL:-}" ] && HAVE_GOVC=1
node_up(){ timeout 5 talosctl --talosconfig "$TC" -n "$1" -e "$1" version >/dev/null 2>&1; }
ts(){ talosctl --talosconfig "$TC" -n "$1" -e "$1" "${@:2}"; }

# ---------------------------------------------------------------- 1. preflight
say "Preflight"
if [ "$DRY" = 1 ]; then
  echo "  [dry-run] would require: 6/6 nodes Ready, etcd 3 members, API healthy"
else
  kubectl get --raw=/readyz >/dev/null || { echo "  ERROR: kube API not reachable"; exit 1; }
  notready=$(kubectl get nodes --no-headers | grep -cv ' Ready ' || true)
  [ "$notready" -eq 0 ] || echo "  WARN: $notready node(s) not Ready — continuing shutdown anyway"
  members=$(ts 172.16.23.31 etcd members 2>/dev/null | grep -c '172\.16\.23\.' || true)
  echo "  etcd members: $members (expect 3)"
  kubectl get nodes -o wide
fi

# ---------------------------------------------------------------- 2. cordon all
say "Cordon all nodes (stop scheduling/rescheduling)"
for nv in "${CP_NODES[@]}" "${WK_NODES[@]}"; do run kubectl cordon "${nv%%:*}"; done

# ---------------------------------------------------------------- 3. hibernate CNPG
say "Quiesce CNPG ($CNPG_NS/$CNPG_CLUSTER) — declarative hibernation (clean PG shutdown)"
run kubectl annotate cluster "$CNPG_CLUSTER" -n "$CNPG_NS" cnpg.io/hibernation=on --overwrite
if [ "$DRY" = 1 ]; then
  echo "  [dry-run] would wait for postgres-* pods to terminate"
else
  for i in $(seq 1 30); do
    p=$(kubectl get pods -n "$CNPG_NS" -l cnpg.io/cluster="$CNPG_CLUSTER" --no-headers 2>/dev/null | wc -l)
    echo "  [$i] CNPG pods remaining: $p"; [ "$p" -eq 0 ] && break; sleep 5
  done
fi

# ---------------------------------------------------------------- 4. drain workers
say "Drain workers (evict remaining app pods → Longhorn volumes detach)"
for nv in "${WK_NODES[@]}"; do
  run kubectl drain "${nv%%:*}" --ignore-daemonsets --delete-emptydir-data --force --timeout="$DRAIN_TIMEOUT"
done

# ---------------------------------------------------------------- 5. wait detach
say "Wait for all Longhorn volumes to detach (clean replicas for the image)"
if [ "$DRY" = 1 ]; then
  echo "  [dry-run] would poll volumes.longhorn.io until all state=detached"
else
  for i in $(seq 1 30); do
    att=$(kubectl get volumes.longhorn.io -n longhorn-system -o jsonpath='{range .items[*]}{.status.state}{"\n"}{end}' 2>/dev/null | grep -cv '^detached$' || true)
    echo "  [$i] volumes not yet detached: $att"; [ "$att" -eq 0 ] && break; sleep 5
  done
fi

# ---------------------------------------------------------------- 6. shutdown workers
say "Shutdown workers (talosctl --force, already drained)"
for nv in "${WK_NODES[@]}"; do
  ip="${nv##*:}"
  if [ "$DRY" = 0 ] && ! node_up "$ip"; then echo "  ${nv%%:*} ($ip): already down — skip"; continue; fi
  run talosctl --talosconfig "$TC" -n "$ip" -e "$ip" shutdown --force --wait=false
done

# ---------------------------------------------------------------- 7. shutdown CPs
say "Shutdown control planes (talosctl --force; etcd stops clean) — bootstrap node (.31) last"
for nv in k8s-cp3:172.16.23.33 k8s-cp2:172.16.23.32 k8s-cp1:172.16.23.31; do
  ip="${nv##*:}"
  if [ "$DRY" = 0 ] && ! node_up "$ip"; then echo "  ${nv%%:*} ($ip): already down — skip"; continue; fi
  run talosctl --talosconfig "$TC" -n "$ip" -e "$ip" shutdown --force --wait=false
done

# ---------------------------------------------------------------- 8. confirm power-off
say "Confirm VMs powered off (govc)"
if [ "$HAVE_GOVC" = 0 ]; then
  echo "  (GOVC_* not set — skipping power-off confirmation; source vcenter-admin.creds to enable)"
elif [ "$DRY" = 1 ]; then
  echo "  [dry-run] would poll runtime.powerState=poweredOff for all 6 VMs"
else
  for nv in "${CP_NODES[@]}" "${WK_NODES[@]}"; do
    nm="${nv%%:*}"; off=0
    for i in $(seq 1 24); do
      st=$(govc object.collect -s "$VMDIR/$nm" runtime.powerState 2>/dev/null || true)
      [ "$st" = "poweredOff" ] && { echo "  $nm: poweredOff"; off=1; break; }
      sleep 5
    done
    [ "$off" = 1 ] || echo "  WARN: $nm not poweredOff yet (last=$st) — check manually before imaging"
  done
fi

say "DONE — cluster halted. Take the Veeam cold image, then: ./scripts/cluster-startup.sh"
