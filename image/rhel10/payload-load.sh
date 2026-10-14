#!/bin/sh
set -eu
for dir in /usr/lib/containers-image-cache/*/; do
    [ -f "${dir}manifest.json" ] || continue
    name=$(basename "$dir")
    skopeo copy --preserve-digests "dir:${dir%/}" "containers-storage:${name}:embedded"
done
