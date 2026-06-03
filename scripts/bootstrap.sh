#!/usr/bin/env bash
# Talos cluster bring-up driver (run AFTER `terraform apply` created the VMs).
#
#   set -a; source ~/.credentials/api-tokens/vcenter-admin.creds; set +a   # EXPORT GOVC_* for govc
#   export SOPS_AGE_KEY_FILE=~/.credentials/age/homeoffice-k8s.agekey
#   ./scripts/bootstrap.sh talos      # inject config (guestinfo) -> bootstrap etcd -> kubeconfig
#
# NOTE the `set -a` — the cred file is KEY=VALUE without `export`, so a plain
# `source` would not pass GOVC_* into this child process.
#
# VLAN 23 has no DHCP and Talos maintenance mode runs no vmtools, so we cannot
# reach a node before it is configured. Instead we push each node's machine config
# via VMware guestinfo and reset; Talos boots straight to its STATIC IP. After that
# the nodes are reachable at .31-.36 and we bootstrap etcd + fetch kubeconfig.
#
# NOTE: `govc vm.change -e guestinfo.talos.config=<base64>` puts the (PKI-bearing)
# machine config on argv — a transient local `ps` exposure on the trusted mgmt host.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$REPO"
: "${SOPS_AGE_KEY_FILE:=$HOME/.credentials/age/homeoffice-k8s.agekey}"; export SOPS_AGE_KEY_FILE

CLUSTER="k8s-talos1"
VIP="172.16.23.30"
OUT="talos/clusterconfig"
TC="$OUT/talosconfig"
VMDIR="/ap169home-dc/vm/Kubernetes"
CP_NODES=(k8s-cp1:172.16.23.31 k8s-cp2:172.16.23.32 k8s-cp3:172.16.23.33)
WK_NODES=(k8s-worker1:172.16.23.34 k8s-worker2:172.16.23.35 k8s-worker3:172.16.23.36)
BOOTSTRAP_IP="172.16.23.31"

require() { command -v "$1" >/dev/null || { echo "MISSING: $1"; exit 1; }; }

ensure_rendered() {
  if [ ! -f "$TC" ] || ! ls "$OUT/${CLUSTER}-"*.yaml >/dev/null 2>&1; then
    echo ">> rendering Talos configs (scripts/talos-gen.sh gen)"
    ./scripts/talos-gen.sh gen
  fi
}

set_config() { # name
  local name="$1" cfg="$OUT/${CLUSTER}-$1.yaml" vmpath="$VMDIR/$1" b64
  [ -f "$cfg" ] || { echo "missing $cfg"; exit 1; }
  b64="$(base64 -w0 "$cfg")"
  govc vm.change -vm "$vmpath" \
    -e guestinfo.talos.config="$b64" \
    -e guestinfo.talos.config.encoding=base64 >/dev/null
  govc vm.power -reset "$vmpath" >/dev/null
  echo "  $name: guestinfo set + reset"
}

node_up() { timeout 5 talosctl --talosconfig "$TC" -n "$1" -e "$1" version >/dev/null 2>&1; }

wait_api() { # ip
  local ip="$1" n=0
  until node_up "$ip"; do
    n=$((n + 1)); [ "$n" -ge 90 ] && { echo "  TIMEOUT waiting on Talos API at $ip"; return 1; }
    sleep 10
  done
  echo "  $ip: Talos API up"
}

cmd_talos() {
  require govc; require talosctl
  [ -n "${GOVC_URL:-}" ] || { echo "ERROR: GOVC_URL unset — run: set -a; source ~/.credentials/api-tokens/vcenter-admin.creds; set +a"; exit 1; }
  ensure_rendered
  echo ">> Injecting machine config via guestinfo (skip already-up nodes) + resetting"
  for nv in "${CP_NODES[@]}" "${WK_NODES[@]}"; do
    nm="${nv%%:*}"; nip="${nv##*:}"
    if node_up "$nip"; then echo "  $nm ($nip): already configured/up — skipping"; else set_config "$nm"; fi
  done

  echo ">> Waiting for nodes to apply config and come up on their static IPs"
  for nv in "${CP_NODES[@]}" "${WK_NODES[@]}"; do wait_api "${nv##*:}"; done

  echo ">> Bootstrapping etcd (once, on $BOOTSTRAP_IP)"
  talosctl --talosconfig "$TC" -n "$BOOTSTRAP_IP" -e "$BOOTSTRAP_IP" bootstrap 2>&1 \
    | grep -vi 'already' || true

  echo ">> Waiting for Kubernetes API on the VIP ($VIP)"
  local n=0
  until talosctl --talosconfig "$TC" -n "$BOOTSTRAP_IP" -e "$BOOTSTRAP_IP" \
        etcd members >/dev/null 2>&1; do
    n=$((n + 1)); [ "$n" -ge 60 ] && { echo "  etcd not healthy yet"; break; }
    sleep 10
  done

  echo ">> Fetching kubeconfig -> $OUT/kubeconfig"
  # Talos apid lives on the node (:50000), not the k8s VIP — target a CP node.
  talosctl --talosconfig "$TC" -n "$BOOTSTRAP_IP" -e "$BOOTSTRAP_IP" kubeconfig "$OUT/kubeconfig" --force

  echo ">> Done. Verify:"
  echo "   talosctl --talosconfig $TC -n $BOOTSTRAP_IP etcd members   # expect 3"
  echo "   KUBECONFIG=$OUT/kubeconfig kubectl get nodes               # expect 6 (NotReady: no CNI yet)"
}

case "${1:-}" in
  talos) cmd_talos ;;
  *) echo "usage: $0 {talos}"; exit 1 ;;
esac
