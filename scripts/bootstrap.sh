#!/usr/bin/env bash
# Talos cluster bring-up driver (run AFTER `terraform apply` created the VMs).
#
#   set -a; source ~/.credentials/api-tokens/vcenter-admin.creds; set +a   # EXPORT GOVC_* for govc
#   export SOPS_AGE_KEY_FILE=~/.credentials/age/homeoffice-k8s.agekey
#   ./scripts/bootstrap.sh talos      # inject config (guestinfo) -> bootstrap etcd -> kubeconfig
#   ./scripts/bootstrap.sh cluster    # P3.2 Gateway API CRDs + Cilium -> P4.2 secrets + Argo CD + root-app
#
# `cluster` runs AFTER `talos` (needs the kubeconfig it writes). It is pure
# kubectl/kustomize/helm/sops — no govc — so it does NOT need GOVC_* exported.
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
GWAPI_VER="v1.4.1"                  # Gateway API CRDs (standard channel) required by Cilium 1.19.x
CILIUM_DIR="kubernetes/apps/cilium"
ARGOCD_DIR="kubernetes/bootstrap/argocd"

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

# Wait for a CRD to exist (cilium-operator registers some at runtime, after it is Ready,
# so `kubectl wait` alone would hit NotFound), then for it to be Established.
wait_crd() { # crd-name
  local crd="$1" n=0
  until kubectl get crd "$crd" >/dev/null 2>&1; do
    n=$((n + 1)); [ "$n" -ge 60 ] && { echo "  TIMEOUT: CRD $crd never appeared"; exit 1; }
    sleep 3
  done
  kubectl wait --for=condition=established --timeout=60s "crd/$crd"
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

cmd_cluster() {
  require kubectl; require kustomize; require helm; require sops
  [ -f "$OUT/kubeconfig" ] || { echo "ERROR: $OUT/kubeconfig missing — run '$0 talos' first"; exit 1; }
  [ -f "$SOPS_AGE_KEY_FILE" ] || { echo "ERROR: age key $SOPS_AGE_KEY_FILE missing"; exit 1; }
  export KUBECONFIG="$REPO/$OUT/kubeconfig"
  kubectl get --raw='/readyz' >/dev/null 2>&1 \
    || { echo "ERROR: Kubernetes API not reachable via $OUT/kubeconfig (is etcd bootstrapped?)"; exit 1; }

  echo "== P3.2: Gateway API CRDs + Cilium =="

  echo ">> Gateway API $GWAPI_VER CRDs (standard + experimental TLSRoute) — must precede Cilium gatewayAPI"
  kubectl apply --server-side \
    -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/$GWAPI_VER/standard-install.yaml"
  # cilium-operator 1.19 registers v1alpha2.TLSRoute in its scheme + watches it unconditionally;
  # without this experimental CRD present AT OPERATOR STARTUP it error-loops on every gateway
  # reconcile. Applied here (before Cilium) so a fresh run never hits that. Upstream lists it
  # under the Cilium Gateway API prerequisites (experimental channel).
  kubectl apply --server-side \
    -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/$GWAPI_VER/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml"
  for c in gatewayclasses gateways httproutes grpcroutes referencegrants tlsroutes; do
    wait_crd "$c.gateway.networking.k8s.io"
  done

  echo ">> Cilium — same 'kustomize build --enable-helm $CILIUM_DIR' Argo uses (clean adoption at P7.9)"
  local render; render="$(kustomize build --enable-helm "$CILIUM_DIR")"
  # Pass 1: the chart objects. The two cilium.io CRs (LB pool + L2 policy) need CRDs the
  # cilium-operator only registers once it is running, so they are EXPECTED to fail here
  # and are applied in pass 2. Tolerate ONLY those two "no matches for kind" errors.
  local out rc=0
  out="$(printf '%s' "$render" | kubectl apply --server-side -f - 2>&1)" || rc=$?
  printf '%s\n' "$out"
  if [ "$rc" -ne 0 ]; then
    local unexpected
    unexpected="$(printf '%s\n' "$out" | grep -iE 'error|unable|fail' \
      | grep -viE 'no matches for kind "(CiliumLoadBalancerIPPool|CiliumL2AnnouncementPolicy)"' || true)"
    [ -z "$unexpected" ] || { echo "ABORT: unexpected errors from the Cilium apply (above)"; exit 1; }
    echo "  (LB pool + L2 policy deferred to pass 2 — operator CRDs not registered yet; expected)"
  fi

  echo ">> Waiting for Cilium + cilium-operator, then its runtime-registered CRDs"
  kubectl -n kube-system rollout status ds/cilium --timeout=300s
  kubectl -n kube-system rollout status deploy/cilium-operator --timeout=300s
  wait_crd ciliumloadbalancerippools.cilium.io
  wait_crd ciliuml2announcementpolicies.cilium.io

  echo ">> Re-applying Cilium render — LB pool + L2 policy now resolve (idempotent for the rest)"
  printf '%s' "$render" | kubectl apply --server-side -f -

  echo ">> Waiting for all nodes Ready"
  kubectl wait --for=condition=Ready nodes --all --timeout=300s

  echo "== P4.2: secrets + Argo CD + root-app =="

  echo ">> namespace argocd"
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

  echo ">> secret sops-age (age key for KSOPS; value read from file path, never printed)"
  kubectl -n argocd create secret generic sops-age \
    --from-file=keys.txt="$SOPS_AGE_KEY_FILE" --dry-run=client -o yaml | kubectl apply -f -

  echo ">> secret repo-ssh (Argo deploy key; decrypted in-memory via SOPS, piped to apply)"
  sops -d "$ARGOCD_DIR/repo-ssh.sops.yaml" | kubectl apply -f -

  echo ">> Argo CD 9.5.17 (helm; installs argoproj CRDs + waits for rollout)"
  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
  helm repo update argo >/dev/null
  helm upgrade --install argocd argo/argo-cd \
    -n argocd --version 9.5.17 -f "$ARGOCD_DIR/values.yaml" --wait --timeout 10m

  echo ">> Argo CD HTTPRoute (attaches the UI host to the Cilium Gateway; the chart creates none)"
  # Stays un-Accepted until the gateway app syncs the 'main' Gateway, then Cilium reconciles it.
  kubectl apply -f "$ARGOCD_DIR/httproute.yaml"

  echo ">> root app-of-apps"
  # root-app + platform-appset pin targetRevision v0.1.0, which is not cut until P7.9.
  # Until then Argo reports 'revision v0.1.0 not found' for root — EXPECTED. P4.2 only
  # requires the 'root' Application to exist; the platform actually syncs at P7.9.
  kubectl apply -f kubernetes/bootstrap/root-app.yaml

  echo "== Done. Verify (KUBECONFIG=$OUT/kubeconfig): =="
  echo "   kubectl get nodes                                # 6 Ready"
  echo "   kubectl -n kube-system get pods -l k8s-app=cilium # cilium DS Running"
  echo "   kubectl get ciliumloadbalancerippool default-pool # .120-.139"
  echo "   kubectl -n argocd get pods                       # repo-server 1/1 (KSOPS init ok)"
  echo "   kubectl -n argocd get applications               # 'root' present (v0.1.0 unresolved until P7.9 — expected)"
}

case "${1:-}" in
  talos) cmd_talos ;;
  cluster) cmd_cluster ;;
  *) echo "usage: $0 {talos|cluster}"; exit 1 ;;
esac
