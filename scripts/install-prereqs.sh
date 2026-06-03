#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# DISPOSABLE prerequisite installer for the homeoffice-k8s (Talos on VMware)
# management server.  Ubuntu 24.04, amd64/arm64.  Run ONCE; not part of the repo
# (the repo will later carry its own pinned scripts/install-prereqs.sh).
#
#   bash /tmp/homeoffice-k8s-prereqs.sh            # install what's missing
#   FORCE=1 bash /tmp/homeoffice-k8s-prereqs.sh    # reinstall everything
#   TALOS_VERSION=v1.13.4 bash ...                 # pin talosctl explicitly
#
# Idempotent: anything already on PATH is skipped unless FORCE=1.
# Needs sudo for apt + writing /usr/local/bin (will prompt).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BINDIR="${BINDIR:-/usr/local/bin}"
FORCE="${FORCE:-0}"
CACHE="$(mktemp -d)"; trap 'rm -rf "$CACHE"' EXIT

# Talos minor this cluster targets (v1.13.x). talosctl is matched to the SERVER.
TALOS_MINOR="${TALOS_MINOR:-1.13}"

case "$(uname -m)" in
  x86_64|amd64)  ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "Unsupported arch: $(uname -m)"; exit 1 ;;
esac
SUDO=""; [ -w "$BINDIR" ] || SUDO="sudo"

have() { command -v "$1" >/dev/null 2>&1; }
need() { [ "$FORCE" = "1" ] || ! have "$1"; }

gh_latest() { # owner/repo -> latest tag via the /releases/latest redirect (no token)
  local repo="$1" tag
  tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
          "https://github.com/${repo}/releases/latest" | sed -n 's#.*/tag/##p' | tr -d '[:space:]')"
  [ -n "$tag" ] || { echo "ERROR: cannot resolve latest tag for $repo" >&2; return 1; }
  printf '%s' "$tag"
}
gh_latest_minor() { # owner/repo X.Y -> newest vX.Y.Z release tag
  local repo="$1" minor="$2" tag
  tag="$(curl -fsSL "https://api.github.com/repos/${repo}/releases?per_page=100" \
          | grep -oE "\"tag_name\": \"v${minor//./\\.}\.[0-9]+\"" \
          | head -1 | cut -d'"' -f4)"
  [ -n "$tag" ] || { echo "ERROR: cannot resolve latest v${minor}.x for $repo" >&2; return 1; }
  printf '%s' "$tag"
}
dl()  { echo "  fetch $1"; curl -fL --retry 3 --retry-delay 2 -o "$2" "$1"; }
bin() { chmod +x "$1"; $SUDO install -m 0755 "$1" "$BINDIR/$2"; echo "  installed $2"; }

# ── base apt packages ────────────────────────────────────────────────────────
echo "== base packages =="
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq \
  curl ca-certificates git gnupg lsb-release jq unzip tar gzip \
  python3 python3-pip pipx age apt-transport-https software-properties-common

# ── Terraform (HashiCorp apt repo) ───────────────────────────────────────────
if need terraform; then
  echo "== terraform =="
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  $SUDO apt-get update -qq && $SUDO apt-get install -y -qq terraform
else echo "terraform present, skip"; fi

# ── kubectl (matched to cluster k8s minor later; install current stable now) ──
if need kubectl; then
  echo "== kubectl =="
  KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  dl "https://dl.k8s.io/release/${KVER}/bin/linux/${ARCH}/kubectl" "$CACHE/kubectl"
  bin "$CACHE/kubectl" kubectl
else echo "kubectl present, skip"; fi

# ── helm ─────────────────────────────────────────────────────────────────────
if need helm; then
  echo "== helm =="
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    | USE_SUDO="$([ -n "$SUDO" ] && echo true || echo false)" HELM_INSTALL_DIR="$BINDIR" bash
else echo "helm present, skip"; fi

# ── talosctl (matched to cluster Talos v1.13.x) ──────────────────────────────
if need talosctl; then
  echo "== talosctl =="
  TV="${TALOS_VERSION:-$(gh_latest_minor siderolabs/talos "$TALOS_MINOR")}"
  echo "  using $TV"
  dl "https://github.com/siderolabs/talos/releases/download/${TV}/talosctl-linux-${ARCH}" "$CACHE/talosctl"
  bin "$CACHE/talosctl" talosctl
else echo "talosctl present, skip"; fi

# ── argocd CLI ───────────────────────────────────────────────────────────────
if need argocd; then
  echo "== argocd =="
  t="$(gh_latest argoproj/argo-cd)"
  dl "https://github.com/argoproj/argo-cd/releases/download/${t}/argocd-linux-${ARCH}" "$CACHE/argocd"
  bin "$CACHE/argocd" argocd
else echo "argocd present, skip"; fi

# ── cilium CLI (cluster mgmt; distinct from the in-cluster agent) ────────────
if need cilium; then
  echo "== cilium-cli =="
  t="$(gh_latest cilium/cilium-cli)"
  dl "https://github.com/cilium/cilium-cli/releases/download/${t}/cilium-linux-${ARCH}.tar.gz" "$CACHE/cilium.tgz"
  tar -xzf "$CACHE/cilium.tgz" -C "$CACHE" cilium
  bin "$CACHE/cilium" cilium
else echo "cilium present, skip"; fi

# ── sops ─────────────────────────────────────────────────────────────────────
if need sops; then
  echo "== sops =="
  t="$(gh_latest getsops/sops)"
  dl "https://github.com/getsops/sops/releases/download/${t}/sops-${t}.linux.${ARCH}" "$CACHE/sops"
  bin "$CACHE/sops" sops
else echo "sops present, skip"; fi

# age + age-keygen come from the apt 'age' package above. Verify.
have age && have age-keygen || { echo "WARN: age/age-keygen missing — apt 'age' failed?"; }

# ── velero CLI ───────────────────────────────────────────────────────────────
if need velero; then
  echo "== velero =="
  t="$(gh_latest vmware-tanzu/velero)"
  dl "https://github.com/vmware-tanzu/velero/releases/download/${t}/velero-${t}-linux-${ARCH}.tar.gz" "$CACHE/velero.tgz"
  tar -xzf "$CACHE/velero.tgz" -C "$CACHE"
  bin "$CACHE/velero-${t}-linux-${ARCH}/velero" velero
else echo "velero present, skip"; fi

# ── yq (mikefarah) ───────────────────────────────────────────────────────────
if need yq; then
  echo "== yq =="
  t="$(gh_latest mikefarah/yq)"
  dl "https://github.com/mikefarah/yq/releases/download/${t}/yq_linux_${ARCH}" "$CACHE/yq"
  bin "$CACHE/yq" yq
else echo "yq present, skip"; fi

# ── kustomize (standalone — needed for KSOPS exec plugin / local lint) ───────
if need kustomize; then
  echo "== kustomize =="
  curl -fsSL https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh \
    | bash -s -- "$CACHE"
  bin "$CACHE/kustomize" kustomize
else echo "kustomize present, skip"; fi

# ── kubeconform (manifest lint) ──────────────────────────────────────────────
if need kubeconform; then
  echo "== kubeconform =="
  t="$(gh_latest yannh/kubeconform)"
  dl "https://github.com/yannh/kubeconform/releases/download/${t}/kubeconform-linux-${ARCH}.tar.gz" "$CACHE/kc.tgz"
  tar -xzf "$CACHE/kc.tgz" -C "$CACHE" kubeconform
  bin "$CACHE/kubeconform" kubeconform
else echo "kubeconform present, skip"; fi

# ── govc (VMware CLI — OVA/template import, datastore/network discovery) ─────
if need govc; then
  echo "== govc =="
  t="$(gh_latest vmware/govmomi)"
  dl "https://github.com/vmware/govmomi/releases/download/${t}/govc_Linux_${ARCH/amd64/x86_64}.tar.gz" "$CACHE/govc.tgz"
  tar -xzf "$CACHE/govc.tgz" -C "$CACHE" govc
  bin "$CACHE/govc" govc
else echo "govc present, skip"; fi

# ── go-task (Taskfile runner, used by the repo's phased targets) ─────────────
if need task; then
  echo "== task =="
  t="$(gh_latest go-task/task)"
  dl "https://github.com/go-task/task/releases/download/${t}/task_linux_${ARCH}.tar.gz" "$CACHE/task.tgz"
  tar -xzf "$CACHE/task.tgz" -C "$CACHE" task
  bin "$CACHE/task" task
else echo "task present, skip"; fi

# ── Ansible (pipx — Ubuntu 24.04 is PEP 668 externally-managed) ──────────────
if need ansible; then
  echo "== ansible =="
  pipx install --include-deps ansible
  # VMware modules (community.vmware) import pyvmomi; vSphere REST modules want the SDK.
  pipx inject ansible pyvmomi requests
  pipx ensurepath >/dev/null 2>&1 || true
  export PATH="$HOME/.local/bin:$PATH"
else echo "ansible present, skip"; fi

if command -v ansible-galaxy >/dev/null 2>&1; then
  echo "== ansible collections =="
  ansible-galaxy collection install community.vmware community.general ansible.posix
else
  echo "WARN: ansible-galaxy not on PATH yet — open a new shell then:"
  echo "      ansible-galaxy collection install community.vmware community.general ansible.posix"
fi

# ── verification ─────────────────────────────────────────────────────────────
echo; echo "== versions =="
for t in terraform kubectl helm talosctl argocd cilium sops age velero jq yq kustomize kubeconform govc task ansible; do
  if have "$t"; then printf '  %-12s %s\n' "$t" "$("$t" version 2>/dev/null | head -1 || "$t" --version 2>/dev/null | head -1)"; else printf '  %-12s MISSING\n' "$t"; fi
done
echo
echo "Done. NOTE: Renovate is NOT a local CLI — it runs as a bot/app against the git host (configured later)."
echo "kubectl/talosctl should be re-aligned to the cluster's exact k8s/Talos versions once those are pinned in the repo."
