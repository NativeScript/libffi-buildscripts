#!/bin/bash
set -euo pipefail
#
# Downloads the pinned upstream libffi release tarball, verifies it against
# LIBFFI_SHA256 and unpacks it into .libffi/libffi-<version>/.
#
# The release tarball, not a git checkout, is the input: it ships a generated
# configure, so building needs no autoconf/automake/libtool, and its checksum
# pins exactly what upstream released.
#
# Usage: fetch.sh [--src-root <path>]
#

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/config.env"

SRC_ROOT="$ROOT_DIR/.libffi"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--src-root <path>]

  --src-root <path>  Where to download and unpack (default: $SRC_ROOT)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --src-root)   SRC_ROOT="$2"; shift 2 ;;
        --src-root=*) SRC_ROOT="${1#*=}"; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

NAME="libffi-$LIBFFI_VERSION"
TARBALL="$SRC_ROOT/$NAME.tar.gz"
URL="https://github.com/libffi/libffi/releases/download/v$LIBFFI_VERSION/$NAME.tar.gz"

mkdir -p "$SRC_ROOT"

if [ ! -f "$TARBALL" ]; then
    echo "Downloading $URL"
    curl -fSL --retry 3 -o "$TARBALL.part" "$URL"
    mv "$TARBALL.part" "$TARBALL"
fi

if command -v sha256sum > /dev/null 2>&1; then
    actual="$(sha256sum "$TARBALL" | cut -d' ' -f1)"
else
    actual="$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)"
fi
if [ "$actual" != "$LIBFFI_SHA256" ]; then
    echo "Checksum mismatch for $TARBALL" >&2
    echo "  expected $LIBFFI_SHA256" >&2
    echo "  actual   $actual" >&2
    exit 1
fi

rm -rf "${SRC_ROOT:?}/$NAME"
tar -xzf "$TARBALL" -C "$SRC_ROOT"
echo "Sources in $SRC_ROOT/$NAME"
