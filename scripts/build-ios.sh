#!/bin/bash
set -euo pipefail
#
# Builds libffi for one Apple variant into dist/ios-<variant>/:
#
#   lib/libffi.a
#   include/ffi.h, include/ffitarget.h   (generated per architecture)
#   LICENSE                              (upstream's; MIT requires it to travel)
#
# Run scripts/fetch.sh first. Every build is checked afterwards: each archive
# member must carry the variant's architecture and platform, and
# tests/smoke.c must link against it with the default linker. Where the host
# can execute the result (Mac Catalyst), the smoke test also runs.
#
# Usage: build-ios.sh --variant <variant> [--src-dir <path>] [--jobs N]
#        build-ios.sh --list-variants
#

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/config.env"

SRC_DIR="$ROOT_DIR/.libffi/libffi-$LIBFFI_VERSION"
VARIANT=""
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

VARIANTS="arm64-device arm64-simulator x64-simulator arm64-catalyst x64-catalyst
arm64-tvdevice arm64-tvsimulator arm64-xrdevice arm64-xrsimulator"

usage() {
    cat <<EOF
Usage: $(basename "$0") --variant <variant> [--src-dir <path>] [--jobs N]
       $(basename "$0") --list-variants

  --variant        one of: $(echo $VARIANTS)
  --src-dir        unpacked libffi sources (default: $SRC_DIR)
  --jobs N         parallel make jobs (default: $JOBS)
  --list-variants  print every variant, one per line, and exit
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --variant)   VARIANT="$2"; shift 2 ;;
        --variant=*) VARIANT="${1#*=}"; shift ;;
        --src-dir)   SRC_DIR="$2"; shift 2 ;;
        --src-dir=*) SRC_DIR="${1#*=}"; shift ;;
        --jobs)      JOBS="$2"; shift 2 ;;
        --jobs=*)    JOBS="${1#*=}"; shift ;;
        --list-variants) printf '%s\n' $VARIANTS; exit 0 ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# PLATFORM is the LC_BUILD_VERSION platform number every object must carry.
case "$VARIANT" in
    arm64-device)      SDK=iphoneos;         ARCH=arm64;  PLATFORM=2;  TARGET="arm64-apple-ios$IOS_DEPLOYMENT_TARGET" ;;
    arm64-simulator)   SDK=iphonesimulator;  ARCH=arm64;  PLATFORM=7;  TARGET="arm64-apple-ios$IOS_DEPLOYMENT_TARGET-simulator" ;;
    x64-simulator)     SDK=iphonesimulator;  ARCH=x86_64; PLATFORM=7;  TARGET="x86_64-apple-ios$IOS_DEPLOYMENT_TARGET-simulator" ;;
    arm64-catalyst)    SDK=macosx;           ARCH=arm64;  PLATFORM=6;  TARGET="arm64-apple-ios$CATALYST_DEPLOYMENT_TARGET-macabi" ;;
    x64-catalyst)      SDK=macosx;           ARCH=x86_64; PLATFORM=6;  TARGET="x86_64-apple-ios$CATALYST_DEPLOYMENT_TARGET-macabi" ;;
    arm64-tvdevice)    SDK=appletvos;        ARCH=arm64;  PLATFORM=3;  TARGET="arm64-apple-tvos$TVOS_DEPLOYMENT_TARGET" ;;
    arm64-tvsimulator) SDK=appletvsimulator; ARCH=arm64;  PLATFORM=8;  TARGET="arm64-apple-tvos$TVOS_DEPLOYMENT_TARGET-simulator" ;;
    arm64-xrdevice)    SDK=xros;             ARCH=arm64;  PLATFORM=11; TARGET="arm64-apple-xros$VISIONOS_DEPLOYMENT_TARGET" ;;
    arm64-xrsimulator) SDK=xrsimulator;      ARCH=arm64;  PLATFORM=12; TARGET="arm64-apple-xros$VISIONOS_DEPLOYMENT_TARGET-simulator" ;;
    *) echo "Invalid --variant '$VARIANT'" >&2; usage >&2; exit 1 ;;
esac

[ "$(uname)" = "Darwin" ] || { echo "Apple variants require a macOS host." >&2; exit 1; }
[ -x "$SRC_DIR/configure" ] || { echo "No libffi sources in $SRC_DIR; run scripts/fetch.sh" >&2; exit 1; }

case "$ARCH" in
    arm64)  HOST=aarch64-apple-darwin ;;
    x86_64) HOST=x86_64-apple-darwin ;;
esac

SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"
CC_CMD="$(xcrun -f clang) -target $TARGET -isysroot $SDK_PATH"
BUILD_DIR="$ROOT_DIR/.build/ios-$VARIANT"
OUT_DIR="$ROOT_DIR/dist/ios-$VARIANT"

echo "==> ios-$VARIANT ($TARGET, $(basename "$SDK_PATH"))"

rm -rf "$BUILD_DIR" "$OUT_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR/lib" "$OUT_DIR/include"

(
    cd "$BUILD_DIR"
    CC="$CC_CMD" CCAS="$CC_CMD" CPP="$CC_CMD -E" \
        "$SRC_DIR/configure" --host="$HOST" \
        --enable-static --disable-shared --disable-docs \
        > configure.log 2>&1 || { cat configure.log; exit 1; }
    make -j"$JOBS" > make.log 2>&1 || { cat make.log; exit 1; }
)

cp "$BUILD_DIR/.libs/libffi.a" "$OUT_DIR/lib/"
cp "$BUILD_DIR/include/ffi.h" "$BUILD_DIR/include/ffitarget.h" "$OUT_DIR/include/"
cp "$SRC_DIR/LICENSE" "$OUT_DIR/LICENSE"

# --- verification ------------------------------------------------------------

LIB="$OUT_DIR/lib/libffi.a"

archs="$(lipo -archs "$LIB")"
[ "$archs" = "$ARCH" ] || { echo "Expected architecture $ARCH, got '$archs'" >&2; exit 1; }

# Every member must carry this variant's platform. The current linker rejects
# an object tagged for another platform (iOS objects in a visionOS image, for
# example), so a wrong tag here would only surface at an app's link.
platforms="$(otool -l "$LIB" | awk '/cmd LC_BUILD_VERSION/{f=1} f&&$1=="platform"{print $2; f=0}' | sort -u | tr '\n' ' ')"
[ "$platforms" = "$PLATFORM " ] || { echo "Expected platform $PLATFORM in every member, got '$platforms'" >&2; exit 1; }
minos="$(otool -l "$LIB" | awk '$1=="minos"{print $2}' | sort -u | paste -sd, -)"

SMOKE="$BUILD_DIR/smoke"
$CC_CMD -Werror -I"$OUT_DIR/include" "$ROOT_DIR/tests/smoke.c" "$LIB" -o "$SMOKE"

ran="linked"
if [ "$PLATFORM" = 6 ]; then
    if [ "$ARCH" = "$(uname -m)" ] || { [ "$ARCH" = x86_64 ] && arch -x86_64 /usr/bin/true 2>/dev/null; }; then
        "$SMOKE"
        ran="linked and ran"
    fi
fi

echo "    arch $archs, platform $PLATFORM, minos $minos, smoke test $ran"
echo "    -> $OUT_DIR"
