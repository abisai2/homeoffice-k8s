#!/usr/bin/env bash
# Ordered power-on of the k8s-talos1 cluster after the weekly Veeam cold-image window.
#
# Order: power on control planes (govc) -> wait Talos API + etcd quorum (3 members) +
# kube API on the VIP -> power on workers -> wait all 6 nodes Ready -> uncordon ->
# resume CNPG (clear hibernation) -> verify. Control planes come up first so etcd reforms
# quorum and the apiserver is live before workers rejoin. Talos auto-boots from the same
# disks; Longhorn volumes reattach as workloads resume. Reverses scripts/cluster-shutdown.sh.
#
# Usage:
#   set -a; source ~/.credentials/api-tokens/vcenter-admin.creds; set +a   # GOVC_* (REQUIRED — powers VMs)
#   ./scripts/cluster-startup.sh --dry-run      # print the plan, touch nothing
#   ./scripts/cluster-startup.sh                # power on + bring back to Ready
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$REPO"
: "${SOPS_AGE_KEY_FILE:=$HOME/.credentials/age/homeoffice-k8s.agekey}"; export SOPS_AGE_KEY_FILE

OUT="talos/clusterconfig"
TC="$OUT/talosconfig"
export KUBECONFIG="$REPO/$OUT/kubeconfig"
VMDIR="/ap169home-dc/vm/Kubernetes"
VIP_NODE="172.16.23.31"            # bootstrap CP — talosctl apid target for etcd checks
CP_NODES=(k8s-cp1:172.16.23.31 k8s-cp2:172.16.23.32 k8s-cp3:172.16.23.33)
WK_NODES=(k8s-worker1:172.16.23.34 k8s-worker2:172.16.23.35 k8s-worker3:172.16.23.36)
CNPG_NS="databases"; CNPG_CLUSTER="postgres"

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
say(){ printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
require(){ command -v "$1" >/dev/null || { echo "MISSING: $1"; exit 1; }; }
run(){ if [ "$DRY" = 1 ]; then echo "  [dry-run] $*"; else echo "  + $*"; "$@"; fi; }

require govc; require talosctl; require kubectl
[ "$DRY" = 1 ] || [ -n "${GOVC_URL:-}" ] || { echo "ERROR: GOVC_URL unset — run: set -a; source ~/.credentials/api-tokens/vcenter-admin.creds; set +a"; exit 1; }
node_up(){ timeout 5 talosctl --talosconfig "$TC" -n "$1" -e "$1" version >/dev/null 2>&1; }

power_on(){ # vmpath
  local st; st=$(govc object.collect -s "$1" runtime.powerState 2>/dev/null || true)
  if [ "$st" = "poweredOn" ]; then echo "  $(basename "$1"): already poweredOn — skip"; return 0; fi
  run govc vm.power -on "$1"
}
wait_api(){ # ip
  [ "$DRY" = 1 ] && { echo "  [dry-run] would wait for Talos API at $1"; return 0; }
  for i in $(seq 1 90); do node_up "$1" && { echo "  $1: Talos API up"; return 0; }; sleep 10; done
  echo "  TIMEOUT: Talos API at $1"; return 1
}

# ---------------------------------------------------------------- 1. power on CPs
say "Power on control planes"
for nv in "${CP_NODES[@]}"; do power_on "$VMDIR/${nv%%:*}"; done
for nv in "${CP_NODES[@]}"; do wait_api "${nv##*:}"; done

# ---------------------------------------------------------------- 2. etcd + API
say "Wait for etcd quorum (3 members) + kube API"
if [ "$DRY" = 1 ]; then
  echo "  [dry-run] would poll talosctl etcd members == 3 and kubectl /readyz"
else
  for i in $(seq 1 60); do
    m=$(talosctl --talosconfig "$TC" -n "$VIP_NODE" -e "$VIP_NODE" etcd members 2>/dev/null | grep -c '172\.16\.23\.' || true)
    echo "  [$i] etcd members: $m"; [ "$m" -ge 3 ] && break; sleep 10
  done
  for i in $(seq 1 60); do
    kubectl get --raw=/readyz >/dev/null 2>&1 && { echo "  kube API ready"; break; }
    echo "  [$i] waiting kube API (VIP)"; sleep 10
  done
fi

# ---------------------------------------------------------------- 3. power on workers
say "Power on workers"
for nv in "${WK_NODES[@]}"; do power_on "$VMDIR/${nv%%:*}"; done
for nv in "${WK_NODES[@]}"; do wait_api "${nv##*:}"; done

# ---------------------------------------------------------------- 4. wait Ready
say "Wait for all 6 nodes Ready"
if [ "$DRY" = 1 ]; then
  echo "  [dry-run] would poll kubectl get nodes until 6 Ready"
else
  for i in $(seq 1 60); do
    ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || true)
    echo "  [$i] nodes Ready: $ready/6"; [ "$ready" -eq 6 ] && break; sleep 10
  done
fi

# ---------------------------------------------------------------- 5. uncordon
say "Uncordon all nodes"
for nv in "${CP_NODES[@]}" "${WK_NODES[@]}"; do run kubectl uncordon "${nv%%:*}"; done

# ---------------------------------------------------------------- 6. resume CNPG
say "Resume CNPG ($CNPG_NS/$CNPG_CLUSTER) — clear hibernation"
run kubectl annotate cluster "$CNPG_CLUSTER" -n "$CNPG_NS" cnpg.io/hibernation=off --overwrite
if [ "$DRY" = 1 ]; then
  echo "  [dry-run] would poll CNPG readyInstances == 3"
else
  for i in $(seq 1 60); do
    r=$(kubectl get cluster "$CNPG_CLUSTER" -n "$CNPG_NS" -o jsonpath='{.status.readyInstances}' 2>/dev/null || true)
    echo "  [$i] CNPG readyInstances: ${r:-0}/3"; [ "${r:-0}" = "3" ] && break; sleep 10
  done
fi

# ---------------------------------------------------------------- 7. verify
say "Verify"
if [ "$DRY" = 1 ]; then
  echo "  [dry-run] would print nodes, Argo apps, etcd members, Longhorn volumes"
else
  kubectl get nodes -o wide
  echo "--- etcd members ---"; talosctl --talosconfig "$TC" -n "$VIP_NODE" -e "$VIP_NODE" etcd members 2>/dev/null || true
  echo "--- Argo apps ---"; kubectl get applications -n argocd -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' 2>/dev/null || true
  echo "--- Longhorn volumes ---"; kubectl get volumes.longhorn.io -n longhorn-system 2>/dev/null || true
fi

say "DONE — cluster back up."
