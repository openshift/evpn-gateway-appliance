#!/usr/bin/env bash
# Assert the built collection tarball ships only approved paths; prints the MANIFEST.json digest to record (ci-bootstrap-spec.md).
# Usage: tools/check-collection-tarball.sh <path-to-tarball>
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <tarball>" >&2
  exit 2
fi

tarball=$1
files=$(tar tzf "$tarball")

# Keep in sync with build_ignore in galaxy.yml.
allowed='^(MANIFEST\.json|FILES\.json|README\.md|LICENSE|galaxy\.yml|bindep\.txt|requirements\.txt|meta/|roles/|plugins/|playbooks/|docs/|changelogs/)'

if grep -Ev "$allowed" <<<"$files"; then
  echo "error: unapproved paths in tarball (see above)" >&2
  exit 1
fi

for need in meta/runtime.yml README.md; do
  grep -qx "$need" <<<"$files" || { echo "error: missing required $need" >&2; exit 1; }
done

tar xzOf "$tarball" MANIFEST.json | sha256sum | cut -d' ' -f1
