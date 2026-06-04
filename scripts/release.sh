#!/usr/bin/env bash
# Cut a SemVer release for homeoffice-k8s.
#
# The platform version is a SINGLE pin Argo CD tracks, mirrored in three places:
#   VERSION, root-app.yaml `targetRevision`, platform-appset.yaml `targetRevision`.
# This script bumps all three in LOCKSTEP, promotes CHANGELOG.md's [Unreleased]
# section to the new version, commits, and tags vX.Y.Z. It does NOT push, and does
# NOT touch the live cluster — `git push` + `argocd app set root --revision vX.Y.Z`
# stay separate (gated) operator steps, printed at the end.
#
#   ./scripts/release.sh --dry-run minor    # preview only (no writes/commit/tag)
#   ./scripts/release.sh 0.2.0              # explicit target
#   ./scripts/release.sh patch              # 0.1.0 -> 0.1.1
#   task release -- 0.2.0
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$REPO"

VERSION_FILE="VERSION"
CHANGELOG="CHANGELOG.md"
PIN_FILES=(kubernetes/bootstrap/root-app.yaml kubernetes/apps/platform-appset.yaml)
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
PIN_RE='^[[:space:]]*targetRevision:[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$'

die() { echo "ERROR: $*" >&2; exit 1; }

dry=0
[ "${1:-}" = "--dry-run" ] && { dry=1; shift; }
spec="${1:-}"
[ -n "$spec" ] || die "usage: $0 [--dry-run] {major|minor|patch|X.Y.Z}"

# --- preconditions ---
command -v git >/dev/null || die "git not found"
[ -f "$VERSION_FILE" ] || die "$VERSION_FILE missing"
[ -f "$CHANGELOG" ]    || die "$CHANGELOG missing"
branch="$(git rev-parse --abbrev-ref HEAD)"
case "$branch" in main|master) die "refuse to release from default branch '$branch'";; esac

cur="$(tr -d '[:space:]' < "$VERSION_FILE")"
[[ "$cur" =~ $SEMVER_RE ]] || die "current VERSION '$cur' is not X.Y.Z"

# Single-pin discipline: exactly one targetRevision per file, all equal to vCUR.
for f in "${PIN_FILES[@]}"; do
  [ -f "$f" ] || die "$f missing"
  n="$(grep -cE "$PIN_RE" "$f" || true)"
  [ "$n" -eq 1 ] || die "$f: expected exactly 1 targetRevision pin, found $n"
  have="$(grep -oE "v?[0-9]+\.[0-9]+\.[0-9]+" <(grep -E "$PIN_RE" "$f"))"
  [ "${have#v}" = "$cur" ] || die "$f pin ($have) out of lockstep with VERSION ($cur)"
done

# --- compute new version ---
IFS=. read -r MA MI PA <<<"$cur"
case "$spec" in
  major) new="$((MA + 1)).0.0";;
  minor) new="$MA.$((MI + 1)).0";;
  patch) new="$MA.$MI.$((PA + 1))";;
  v*)    new="${spec#v}";;
  *)     new="$spec";;
esac
[[ "$new" =~ $SEMVER_RE ]] || die "target '$new' is not SemVer X.Y.Z"

# Monotonic: new must be strictly greater than current.
greater() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$1" ]; }
greater "$new" "$cur" || die "target $new must be greater than current $cur"

tag="v$new"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "tag $tag already exists"
today="$(date +%F)"

echo "Release $cur -> $new   (tag $tag, $today, branch $branch)"
echo "Pins (single-pin discipline — exactly ${#PIN_FILES[@]}):"
for f in "${PIN_FILES[@]}"; do
  ln="$(grep -nE "$PIN_RE" "$f")"
  echo "  $f (line ${ln%%:*}): ${ln#*:}  ->  targetRevision: $tag"
done
echo "  $VERSION_FILE: $cur -> $new"
echo "  $CHANGELOG: [Unreleased] -> [$new] - $today (+ fresh [Unreleased])"

if [ "$dry" -eq 1 ]; then
  echo "(dry-run — nothing written, no commit, no tag)"
  exit 0
fi

# --- apply ---
printf '%s\n' "$new" > "$VERSION_FILE"
for f in "${PIN_FILES[@]}"; do
  sed -E -i "s|^([[:space:]]*targetRevision:[[:space:]]*)v?[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*\$|\1$tag|" "$f"
  grep -qE "^[[:space:]]*targetRevision:[[:space:]]*${tag}[[:space:]]*\$" "$f" || die "$f did not update to $tag"
done

# Promote CHANGELOG: keep an empty [Unreleased] on top, insert the dated version below.
awk -v ver="$new" -v d="$today" '
  /^## \[Unreleased\]/ && !done { print; print ""; print "## [" ver "] - " d; done = 1; next }
  { print }
' "$CHANGELOG" > "$CHANGELOG.tmp" && mv "$CHANGELOG.tmp" "$CHANGELOG"
grep -q "^## \[$new\] - $today\$" "$CHANGELOG" || die "CHANGELOG promotion failed (no [Unreleased] header?)"

git add "$VERSION_FILE" "$CHANGELOG" "${PIN_FILES[@]}"
git commit -m "release: $tag" \
  -m "Bump platform pin $cur -> $new in lockstep (root-app + platform-appset), VERSION, CHANGELOG." >/dev/null
git tag -a "$tag" -m "Release $tag"

echo "Committed + tagged $tag on $branch."
echo "Next (operator/gated): git push && git push origin $tag ; argocd app set root --revision $tag"
