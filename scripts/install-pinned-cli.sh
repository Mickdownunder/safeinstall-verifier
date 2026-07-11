#!/usr/bin/env bash
# Install the integrity-pinned safeinstall-cli verifier.
#
# The pin (exact version + sha512 of the registry tarball) lives in pin.json —
# the single source of truth shared by action.yml and the adversarial suite.
# A registry that serves different bytes for the same version fails here
# instead of silently swapping the verification logic (RFC-001 §13 K1(b)).
#
# Usage:
#   install-pinned-cli.sh [--tarball <path>] [--prefix <dir>]
#     --tarball  verify+install this local file instead of downloading
#                (used by the adversarial suite's corrupt-tarball case)
#     --prefix   pass --prefix to npm install -g (local testing without
#                touching the machine's real global install)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pin="$here/../pin.json"

tarball=""
prefix=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tarball) tarball="$2"; shift 2 ;;
    --prefix) prefix="$2"; shift 2 ;;
    *) echo "install-pinned-cli.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

name=$(jq -r .name "$pin")
version=$(jq -r .version "$pin")
url=$(jq -r .tarballUrl "$pin")
sha512=$(jq -r .sha512 "$pin")

if [[ -z "$tarball" ]]; then
  tmpdir="${RUNNER_TEMP:-$(mktemp -d)}"
  tarball="$tmpdir/${name}-${version}.tgz"
  curl -fsSL "$url" -o "$tarball"
fi

# Content-hash gate: this line IS the guarantee. Everything after it runs
# only over bytes that match the recorded digest.
if command -v sha512sum >/dev/null 2>&1; then
  echo "$sha512  $tarball" | sha512sum -c -
else
  echo "$sha512  $tarball" | shasum -a 512 -c -
fi

if [[ -n "$prefix" ]]; then
  npm install -g --prefix "$prefix" "$tarball"
else
  npm install -g "$tarball"
fi
