#!/usr/bin/env bash
# Talos node image: reproducible Image Factory schematic -> installer/OVA -> template.
# Makes P1.1 (previously manual) repeatable. The extension set lives in
# talos/image/schematic.yaml; everything here derives from it.
#
#   scripts/talos-image.sh id                 # POST schematic -> print ID + installer + OVA URL
#   scripts/talos-image.sh ova [outfile]      # download the VMware OVA for the schematic
#   scripts/talos-image.sh installer          # just print the installer image ref (for talosctl upgrade)
#   scripts/talos-image.sh import <ova-file>  # govc import.ova as a vCenter template (needs GOVC_*)
#
# The schematic ID is content-addressable: same schematic.yaml -> same ID, always.
# Pin the printed installer ref into talos/patches/common.yaml (machine.install.image).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$REPO"

FACTORY="https://factory.talos.dev"
SCHEMATIC="talos/image/schematic.yaml"
: "${TALOS_VERSION:=v1.13.3}"
# Template import targets (override via env; defaults match the documented P1.1 facts).
: "${TEMPLATE_NAME:=talos-${TALOS_VERSION}}"
: "${TEMPLATE_DATASTORE:=fs1-esxi-templates}"
: "${TEMPLATE_FOLDER:=/ap169home-dc/vm/Templates}"
: "${TEMPLATE_HOST:=esxi01.homeoffice.local}"
: "${TEMPLATE_NETWORK:=vds01_pg-Kubernetes}"

require() { command -v "$1" >/dev/null || { echo "MISSING: $1"; exit 1; }; }

schematic_id() { # POST is idempotent: same body -> same content-addressable id
  require curl; require jq
  [ -f "$SCHEMATIC" ] || { echo "missing $SCHEMATIC" >&2; exit 1; }
  curl -sS -X POST --data-binary "@$SCHEMATIC" "$FACTORY/schematics" | jq -er '.id'
}

cmd_id() {
  local id; id="$(schematic_id)"
  echo "schematic id : $id"
  echo "installer    : factory.talos.dev/installer/${id}:${TALOS_VERSION}"
  echo "ova          : $FACTORY/image/${id}/${TALOS_VERSION}/vmware-amd64.ova"
}

cmd_installer() { echo "factory.talos.dev/installer/$(schematic_id):${TALOS_VERSION}"; }

cmd_ova() {
  local id out; id="$(schematic_id)"; out="${1:-talos-${TALOS_VERSION}-vmware-amd64.ova}"
  echo ">> downloading OVA for $id ($TALOS_VERSION) -> $out"
  curl -fSL -o "$out" "$FACTORY/image/${id}/${TALOS_VERSION}/vmware-amd64.ova"
  echo "  wrote $out"
}

cmd_import() { # <ova-file>  — import as a vCenter template (does NOT delete an existing one)
  require govc
  local ova="${1:?usage: $0 import <ova-file>}"
  [ -f "$ova" ] || { echo "no such file: $ova"; exit 1; }
  [ -n "${GOVC_URL:-}" ] || { echo "ERROR: GOVC_URL unset — run: set -a; source ~/.credentials/api-tokens/vcenter-admin.creds; set +a"; exit 1; }
  echo ">> importing $ova as VM '$TEMPLATE_NAME' (ds=$TEMPLATE_DATASTORE folder=$TEMPLATE_FOLDER host=$TEMPLATE_HOST net=$TEMPLATE_NETWORK)"
  govc import.ova -name "$TEMPLATE_NAME" -ds "$TEMPLATE_DATASTORE" \
    -folder "$TEMPLATE_FOLDER" -host "$TEMPLATE_HOST" -net "$TEMPLATE_NETWORK" "$ova"
  echo ">> marking as template"
  govc vm.markastemplate "$TEMPLATE_FOLDER/$TEMPLATE_NAME"
  echo "  done. (If a template of this name already existed, remove it first — destructive, do manually.)"
}

case "${1:-}" in
  id|schematic) cmd_id ;;
  installer)    cmd_installer ;;
  ova)          shift; cmd_ova "$@" ;;
  import)       shift; cmd_import "$@" ;;
  *) echo "usage: $0 {id|installer|ova [outfile]|import <ova-file>}"; exit 1 ;;
esac
