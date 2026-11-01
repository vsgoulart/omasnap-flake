#!/usr/bin/env bash
# Pins the newest upstream Omasnap release in sources.json.
#
# Only release metadata is downloaded: GitHub publishes a SHA-256 digest for
# every release asset, so nothing large has to be fetched to compute hashes.
#
# Writes changed and version to $GITHUB_OUTPUT when running in GitHub Actions.
set -euo pipefail

sources=sources.json
repo=omacom/omasnap

[[ -f flake.nix ]] || { echo "Run from the repository root." >&2; exit 1; }
[[ -f "$sources" ]] || echo '{}' >"$sources"

# Nix system -> upstream artifact name (%s is the version).
declare -A assets=(
  [x86_64-linux]=omasnap-%s-archlinux-x86_64.tar.gz
)

sri() {
  printf 'sha256-%s' "$(printf '%s' "${1^^}" | basenc --base16 -d | base64 -w0)"
}

# Succeeds when $1 is newer than $2 (or $2 is empty).
is_newer() {
  [[ -z "$2" || ( "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" ) ]]
}

# Picks the highest stable vX.Y.Z release that already has every needed asset
# (assets are uploaded after the release is created).
releases="$(
  gh api "repos/$repo/releases?per_page=100" | jq -c '
    [ .[]
      | select(.draft | not)
      | select(.prerelease | not)
      | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
    ]'
)"
version=""
files=""
for tag in $(jq -r '.[].tag_name' <<<"$releases" | sort -Vr); do
  candidate="${tag#v}"
  release_files="$(jq -c --arg t "$tag" '
    .[] | select(.tag_name == $t) | .assets
    | map({ key: .name,
            value: { url: .browser_download_url,
                     sha256: ((.digest // "") | ltrimstr("sha256:")) } })
    | from_entries' <<<"$releases")"
  complete=true
  for system in "${!assets[@]}"; do
    # shellcheck disable=SC2059
    name="$(printf "${assets[$system]}" "$candidate")"
    jq -e --arg n "$name" '.[$n] != null' <<<"$release_files" >/dev/null || complete=false
  done
  if $complete; then
    version="$candidate"
    files="$release_files"
    break
  fi
  echo "Skipping $tag: assets not fully published yet." >&2
done
[[ -n "$version" ]] || { echo "No complete release found." >&2; exit 1; }

old="$(jq -r '.version // ""' "$sources")"
changed=false
if is_newer "$version" "$old"; then
  echo "omasnap: ${old:-none} -> $version"
  entry="$(jq -n --arg v "$version" '{version: $v}')"
  for system in "${!assets[@]}"; do
    # shellcheck disable=SC2059
    name="$(printf "${assets[$system]}" "$version")"
    url="$(jq -r --arg n "$name" '.[$n].url' <<<"$files")"
    hex="$(jq -r --arg n "$name" '.[$n].sha256' <<<"$files")"
    if [[ -z "$hex" ]]; then
      echo "No published digest for $name; prefetching." >&2
      hash="$(nix --extra-experimental-features nix-command store prefetch-file --json "$url" | jq -r .hash)"
    else
      hash="$(sri "$hex")"
    fi
    entry="$(jq --arg s "$system" --arg u "$url" --arg h "$hash" '.[$s] = {url: $u, hash: $h}' <<<"$entry")"
  done
  jq -S . <<<"$entry" >"$sources"
  changed=true
elif [[ "$version" != "$old" ]]; then
  echo "Ignoring $version: older than pinned $old." >&2
fi

pinned="$(jq -r .version "$sources")"
echo "Pinned $pinned (changed: $changed)."

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "changed=$changed"
    echo "version=$pinned"
  } >>"$GITHUB_OUTPUT"
fi
