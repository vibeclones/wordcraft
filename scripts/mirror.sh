#!/usr/bin/env bash
# Mirror an upstream project's web builds into v<version>/ folders, then refresh latest/ and versions.json.
# Mirrors every stable release that has a web zip, newest first, and stops when the next one would not fit under the
# size cap (the oldest versions are the ones left out).
# Env: UPSTREAM (owner/repo), NAME (app name, e.g. photocraft)
#      TAG (optional: mirror just this release), LIMIT (how many recent releases to look at, default 40),
#      CAP_MB (published-site size cap, default 800)
set -euo pipefail

: "${UPSTREAM:?}" "${NAME:?}"
LIMIT="${LIMIT:-40}"
CAP_MB="${CAP_MB:-800}"

if [ -n "${TAG:-}" ]; then
  tags="$TAG"
else
  tags=$(gh release list -R "$UPSTREAM" --limit "$LIMIT" --exclude-drafts --exclude-pre-releases --json tagName -q '.[].tagName')
fi

for tag in $tags; do
  ver="${tag#v}"
  if [ -d "v$ver" ]; then continue; fi
  asset="$NAME-web-$ver.zip"
  zip_bytes=$(gh api "repos/$UPSTREAM/releases/tags/$tag" --jq ".assets[] | select(.name == \"$asset\") | .size" 2>/dev/null || true)
  if [ -z "$zip_bytes" ]; then echo "No web zip on $tag, skipping"; continue; fi
  # Unpacked, a web build is about 2.4 times its zip. Stop once the next one would not fit.
  size=$(du -sm --exclude=.git . | cut -f1)
  need=$(( zip_bytes * 24 / 10 / 1048576 ))
  if [ $((size + need)) -gt "$CAP_MB" ] && [ -n "$(find . -maxdepth 1 -type d -name 'v[0-9]*' | head -n1)" ]; then
    echo "Stopping at $tag: ${size} MB now + about ${need} MB would pass the ${CAP_MB} MB cap"
    break
  fi
  tmp="$(mktemp -d)"
  if ! gh release download "$tag" -R "$UPSTREAM" -p "$asset" -D "$tmp"; then echo "Download failed for $tag, skipping"; rm -rf "$tmp"; continue; fi
  unzip -q "$tmp/$asset" -d "$tmp/x"
  # The zip wraps everything in one top-level folder.
  src="$tmp/x"
  if [ "$(find "$tmp/x" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ] && [ -d "$(find "$tmp/x" -mindepth 1 -maxdepth 1)" ]; then
    src="$(find "$tmp/x" -mindepth 1 -maxdepth 1)"
  fi
  if [ ! -f "$src/index.html" ]; then echo "$asset has no index.html, skipping"; rm -rf "$tmp"; continue; fi
  mkdir "v$ver"
  cp -a "$src/." "v$ver/"
  rm -rf "$tmp"
  echo "Mirrored $tag"
done

# Newest first.
versions=$(find . -maxdepth 1 -type d -name 'v[0-9]*' -printf '%f\n' | sed 's/^v//' | sort -rV)
[ -n "$versions" ] || { echo "No versions"; exit 0; }
latest=$(echo "$versions" | head -n1)

mkdir -p latest
cat > latest/index.html <<EOF
<!doctype html><meta charset="utf-8"><title>$NAME</title><meta http-equiv="refresh" content="0; url=../v$latest/"><link rel="canonical" href="../v$latest/"><a href="../v$latest/">Open $NAME $latest</a>
EOF

echo "$versions" | jq -R . | jq -s --arg latest "$latest" '{latest: $latest, versions: .}' > versions.json

# A new release can push an old one over the cap; drop the oldest until it fits.
bash scripts/prune.sh
cat versions.json
