#!/usr/bin/env bash
# Mirror an upstream release's web build into v<version>/, then refresh latest/ and versions.json.
# Env: UPSTREAM (owner/repo), NAME (app name, e.g. photocraft), TAG (optional release tag; default = latest release)
set -euo pipefail

: "${UPSTREAM:?}" "${NAME:?}"
TAG="${TAG:-$(gh release view -R "$UPSTREAM" --json tagName -q .tagName)}"
VER="${TAG#v}"

if [ -d "v$VER" ]; then
  echo "v$VER already mirrored"
else
  tmp="$(mktemp -d)"
  gh release download "$TAG" -R "$UPSTREAM" -p "$NAME-web-$VER.zip" -D "$tmp"
  unzip -q "$tmp/$NAME-web-$VER.zip" -d "$tmp/x"
  # The zip wraps everything in one top-level folder.
  src="$tmp/x"
  if [ "$(find "$tmp/x" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ] && [ -d "$(find "$tmp/x" -mindepth 1 -maxdepth 1)" ]; then
    src="$(find "$tmp/x" -mindepth 1 -maxdepth 1)"
  fi
  test -f "$src/index.html"
  mkdir "v$VER"
  cp -a "$src/." "v$VER/"
  rm -rf "$tmp"
fi

# Newest first.
versions=$(find . -maxdepth 1 -type d -name 'v[0-9]*' -printf '%f\n' | sed 's/^v//' | sort -rV)
latest=$(echo "$versions" | head -n1)

mkdir -p latest
cat > latest/index.html <<EOF
<!doctype html><meta charset="utf-8"><title>$NAME</title><meta http-equiv="refresh" content="0; url=../v$latest/"><link rel="canonical" href="../v$latest/"><a href="../v$latest/">Open $NAME $latest</a>
EOF

echo "$versions" | jq -R . | jq -s --arg latest "$latest" '{latest: $latest, versions: .}' > versions.json
cat versions.json
