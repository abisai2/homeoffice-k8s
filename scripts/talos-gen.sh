#!/usr/bin/env bash
# Native talosctl generation of Talos secrets + per-node machine configs.
#
#   scripts/talos-gen.sh secret   # generate + SOPS-encrypt the cluster PKI bundle (once)
#   scripts/talos-gen.sh gen      # render talos/clusterconfig/ from secrets + patches
#
# Single source of node networking is talos/patches/nodes/{controlplane,worker}/*.yaml.
# Needs: talosctl, sops, yq, age key (SOPS_AGE_KEY_FILE). gen is offline.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$REPO"
: "${SOPS_AGE_KEY_FILE:=$HOME/.credentials/age/homeoffice-k8s.agekey}"
export SOPS_AGE_KEY_FILE

CLUSTER="k8s-talos1"
VIP="172.16.23.30"
K8S="1.36.1"                         # Kubernetes shipped by Talos v1.13.3 (verified)
SECRETS="talos/secrets.sops.yaml"
OUT="talos/clusterconfig"
PATCHDIR="talos/patches"

cmd_secret() {
  if [ -f "$SECRETS" ]; then
    echo "$SECRETS already exists — NOT regenerating (would invalidate cluster PKI)."
    return 0
  fi
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  talosctl gen secrets -o "$tmp/secrets.yaml"
  # --filename-override makes SOPS match .sops.yaml rules against the repo path.
  sops --encrypt --filename-override "$SECRETS" "$tmp/secrets.yaml" > "$tmp/enc.yaml"
  mv "$tmp/enc.yaml" "$SECRETS"
  echo "wrote $SECRETS (encrypted). Commit it; the age key is its only decryptor."
}

# Talos v1.13.3 gen emits a trailing `kind: HostnameConfig` (auto) document that
# conflicts with the per-node static machine.network.hostname at validate time.
# Drop it so the per-node static hostname is the sole authoritative source.
strip_hostnameconfig() {
  local f="$1" cut
  cut="$(awk '/^---$/{sep=NR} /^kind: HostnameConfig$/{print sep; exit}' "$f")"
  if [ -n "$cut" ]; then
    head -n "$((cut - 1))" "$f" > "$f.trim" && mv "$f.trim" "$f"
  fi
}

ips=()
render() { # base rolepatch nodepatch
  local base="$1" role="$2" node="$3" host ip
  host="$(yq -r '.machine.network.hostname' "$node")"
  ip="$(yq -r '.machine.network.interfaces[0].addresses[0]' "$node" | cut -d/ -f1)"
  talosctl machineconfig patch "$base" --patch "@${role}" --patch "@${node}" \
    --output "$OUT/${CLUSTER}-${host}.yaml"
  talosctl validate --config "$OUT/${CLUSTER}-${host}.yaml" --mode metal
  echo "  generated + validated $OUT/${CLUSTER}-${host}.yaml ($host @ $ip)"
  ips+=("$ip")
}

cmd_gen() {
  [ -f "$SECRETS" ] || { echo "ERROR: $SECRETS missing — run '$0 secret' first"; exit 1; }
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  sops --decrypt "$SECRETS" > "$tmp/secrets.yaml"

  # Base control-plane + worker configs (common patch: install disk + factory image).
  talosctl gen config "$CLUSTER" "https://${VIP}:6443" \
    --with-secrets "$tmp/secrets.yaml" --kubernetes-version "$K8S" \
    --config-patch "@${PATCHDIR}/common.yaml" --additional-sans "$VIP" \
    --output-types controlplane,worker,talosconfig --output "$tmp" --force
  strip_hostnameconfig "$tmp/controlplane.yaml"
  strip_hostnameconfig "$tmp/worker.yaml"

  mkdir -p "$OUT"
  for np in "$PATCHDIR"/nodes/controlplane/*.yaml; do
    render "$tmp/controlplane.yaml" "$PATCHDIR/controlplane.yaml" "$np"
  done
  for np in "$PATCHDIR"/nodes/worker/*.yaml; do
    render "$tmp/worker.yaml" "$PATCHDIR/worker.yaml" "$np"
  done

  # Client talosconfig: endpoints = all node IPs, default node = VIP.
  cp "$tmp/talosconfig" "$OUT/talosconfig"
  talosctl --talosconfig "$OUT/talosconfig" config endpoint "${ips[@]}"
  talosctl --talosconfig "$OUT/talosconfig" config node "$VIP"
  echo "  wrote $OUT/talosconfig (endpoints: ${ips[*]})"
}

case "${1:-}" in
  secret) cmd_secret ;;
  gen)    cmd_gen ;;
  *) echo "usage: $0 {secret|gen}"; exit 1 ;;
esac
