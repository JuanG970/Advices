#!/usr/bin/env bash
#
# install-wolfram-engine.sh -- install the Wolfram Engine from the official
# Docker image, without a Docker daemon.
#
# Why this route: the wolframresearch/wolframengine image is public and can be
# pinned by digest, and it is the exact build the repo's earlier CI used
# (git history: a66932c). We read its layers straight from the registry,
# verify every sha256 back to the pinned manifest digest, flatten them into a
# staging directory, and copy only the Engine files onto the host. The image's
# own /var/lib/dpkg, logs, and /tmp are deliberately left behind.
#
# Needs:    root, curl, jq, tar, gzip, ~12 GB free disk (peak), and HTTPS to
#           auth.docker.io, registry-1.docker.io, production.cloudfront.docker.com
# Secrets:  none.
# License:  not needed to install. This script never starts a kernel, so it
#           never spends Wolfram Service Credits.
# Re-runs:  no-op once the pinned digest is installed. A failed run keeps its
#           verified downloads, so a retry resumes instead of starting over.
#
# Overrides (environment):
#   WOLFRAM_IMAGE_DIGEST  manifest digest to install (default: the 14.3 pin below)
#   WOLFRAM_IMAGE_REPO    registry repository       (default: wolframresearch/wolframengine)
#   WOLFRAM_CACHE_DIR     layer download cache      (default: /var/cache/wolfram-engine)
#   WOLFRAM_KEEP_BLOBS=1  keep downloaded layers after a successful install
#   WOLFRAM_MIN_FREE_GB   preflight free-space check (default: 12)

set -euo pipefail

REPO="${WOLFRAM_IMAGE_REPO:-wolframresearch/wolframengine}"
# 14.3 -- identical to the digest in the old CI workflow, and to what the
# `14.3` / `14.3.0` tags resolved to on 2026-10-25. Only this digest has been
# tested; cloud-env/README.md says how to look up another release's digest.
DIGEST="${WOLFRAM_IMAGE_DIGEST:-sha256:ff018b403ca9095c6b339aac3d6e719ed5b8cf7a318bbe6521db52cb6d7c567a}"
CACHE_DIR="${WOLFRAM_CACHE_DIR:-/var/cache/wolfram-engine}"
KEEP_BLOBS="${WOLFRAM_KEEP_BLOBS:-0}"
MIN_FREE_GB="${WOLFRAM_MIN_FREE_GB:-12}"

ENGINE_PARENT=/usr/local/Wolfram/WolframEngine
MARKER=/usr/local/Wolfram/.installed-from-image

log() { printf '[wolfram-engine] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

sha_of() { printf 'sha256:%s' "$(sha256sum "$1" | cut -d' ' -f1)"; }

registry_token() {
  curl -fsS --retry 3 \
    "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${REPO}:pull" |
    jq -er .token
}

# fetch_blob DIGEST DEST SIZE -- download a layer (resuming a partial file) and
# verify it. Each pass re-checks the file, so a corrupt complete download is
# discarded rather than "resumed" into a 416.
fetch_blob() {
  local digest="$1" dest="$2" size="$3" attempt have token loc rc
  for attempt in 1 2 3 4 5; do
    have=0
    if [ -f "$dest" ]; then have="$(stat -c %s "$dest")"; fi
    if [ "$have" -ge "$size" ]; then
      if [ "$have" -eq "$size" ] && [ "$(sha_of "$dest")" = "$digest" ]; then
        return 0
      fi
      log "discarding bad download of ${digest:0:19} (attempt ${attempt})"
      rm -f "$dest"
    fi
    token="$(registry_token)" || { sleep $((attempt * 2)); continue; }
    # The registry answers 307 with a short-lived signed CDN URL; ask for a
    # fresh one every pass rather than reusing one that may have expired.
    loc="$(curl -fsS -H "Authorization: Bearer ${token}" -o /dev/null \
             -w '%{redirect_url}' \
             "https://registry-1.docker.io/v2/${REPO}/blobs/${digest}")" || loc=""
    rc=0
    if [ -n "$loc" ]; then
      curl -fsSL --retry 3 --retry-delay 2 -C - -o "$dest" "$loc" || rc=$?
    else
      rc=1
    fi
    # 33 = the CDN would not resume; start that file over rather than loop.
    if [ "$rc" -eq 33 ]; then rm -f "$dest"; fi
    if [ "$rc" -ne 0 ]; then sleep $((attempt * 2)); fi
  done
  die "could not download ${digest}"
}

# Register /usr/bin/wolframscript the way the image's own postinst does.
link_wolframscript() {
  local ws=/opt/Wolfram/WolframScript/bin/wolframscript
  local man=/opt/Wolfram/WolframScript/share/man/man1/wolframscript.1
  local slave=()
  [ -x "$ws" ] || return 0
  if [ -f "$man" ]; then
    slave=(--slave /usr/share/man/man1/wolframscript.1 wolframscript.1 "$man")
  fi
  update-alternatives --install /usr/bin/wolframscript wolframscript "$ws" 40 \
    "${slave[@]+"${slave[@]}"}" >/dev/null
}

already_installed() {
  [ -f "$MARKER" ] || return 1
  grep -qxF "digest=${DIGEST}" "$MARKER" || return 1
  [ -x /usr/local/bin/WolframKernel ] || return 1
}

# ---------------------------------------------------------------------------

[ "$(id -u)" -eq 0 ] || die "run as root (e.g. via sudo)"
for tool in curl jq tar gzip sha256sum update-alternatives; do
  command -v "$tool" >/dev/null || die "missing '${tool}' (apt-get install curl jq ca-certificates)"
done

if already_installed; then
  link_wolframscript
  log "already installed: $(grep -E '^(image|installed_at)=' "$MARKER" | paste -sd' ')"
  exit 0
fi

mkdir -p "$CACHE_DIR"
free_gb="$(df --output=avail -BG "$CACHE_DIR" | tail -1 | tr -dc '0-9')"
[ "${free_gb:-0}" -ge "$MIN_FREE_GB" ] ||
  die "only ${free_gb:-?} GB free; need ~${MIN_FREE_GB} GB (layers + staging)"

# A killed earlier run can leave a multi-GB staging dir behind.
rm -rf /usr/local/.wolfram-stage.*
stage="$(mktemp -d /usr/local/.wolfram-stage.XXXXXX)"
trap 'rm -rf "$stage"' EXIT

started=$SECONDS
log "installing ${REPO}@${DIGEST}"

# 1. Manifest -- must hash to the pinned digest; everything else hangs off it.
manifest="${CACHE_DIR}/manifest.json"
curl -fsS -H "Authorization: Bearer $(registry_token)" \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
  -o "$manifest" "https://registry-1.docker.io/v2/${REPO}/manifests/${DIGEST}"
[ "$(sha_of "$manifest")" = "$DIGEST" ] || die "manifest does not hash to ${DIGEST}"
jq -e '.mediaType == "application/vnd.docker.distribution.manifest.v2+json"
       and ([.layers[].mediaType] | all(. == "application/vnd.docker.image.rootfs.diff.tar.gzip"))' \
  "$manifest" >/dev/null ||
  die "unsupported image format (need a single-platform docker v2 manifest with gzip layers)"
mapfile -t layers < <(jq -r '.layers[] | "\(.digest) \(.size)"' "$manifest")
log "manifest verified; ${#layers[@]} layers, $(jq '[.layers[].size] | add / 1048576 | floor' "$manifest") MiB compressed"

# 2. Layers -- download, verify, apply in order into the staging dir.
for entry in "${layers[@]}"; do
  d="${entry% *}"; size="${entry#* }"
  blob="${CACHE_DIR}/${d#sha256:}.tar.gz"
  fetch_blob "$d" "$blob" "$size"
  tar -xzf "$blob" -C "$stage" --no-same-owner
  log "layer ${d:7:12} verified and unpacked"
done

# 3. Copy the Engine onto the host. Engine version dirs are replaced one by
#    one so releases can sit side by side; the small shared files are merged.
engine_versions=()
for v in "$stage${ENGINE_PARENT}"/*/; do
  if [ -d "$v" ]; then engine_versions+=("$(basename "$v")"); fi
done
[ "${#engine_versions[@]}" -gt 0 ] || die "no WolframEngine/<version> directory in the image"

for v in "${engine_versions[@]}"; do
  mkdir -p "$ENGINE_PARENT"
  rm -rf "${ENGINE_PARENT:?}/${v}"
  mv "$stage${ENGINE_PARENT}/${v}" "${ENGINE_PARENT}/${v}"
done

merge=(
  opt/Wolfram/WolframScript       # the wolframscript launcher
  usr/local/bin/WolframKernel     # symlink to the kernel
  usr/share/WolframEngine         # system-wide applications, incl. patched CURLLink
  usr/share/Mathematica           # installer metadata (.installdirs)
  etc/profile.d/Mathematica.sh    # exports MATHEMATICA_HOME
)
for p in "${merge[@]}"; do
  if [ -e "$stage/$p" ] || [ -L "$stage/$p" ]; then
    mkdir -p "/$(dirname "$p")"
    if [ -d "$stage/$p" ] && [ ! -L "$stage/$p" ]; then
      mkdir -p "/$p"
      cp -a --remove-destination "$stage/$p/." "/$p/"
    else
      cp -a --remove-destination "$stage/$p" "/$p"
    fi
  else
    log "note: ${p} not present in this image"
  fi
done

link_wolframscript

{
  echo "image=${REPO}@${DIGEST}"
  echo "digest=${DIGEST}"
  echo "versions=${engine_versions[*]}"
  echo "installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$MARKER"

# Success: the downloads are no longer needed (only touch files we created).
if [ "$KEEP_BLOBS" != "1" ]; then
  rm -f "$CACHE_DIR"/*.tar.gz "$manifest"
  rmdir "$CACHE_DIR" 2>/dev/null || true
fi

log "done in $((SECONDS - started))s: engine ${engine_versions[*]}, $(du -sh "$ENGINE_PARENT" | cut -f1) on disk"
