[![Build libffi](https://github.com/NativeScript/libffi-buildscripts/actions/workflows/build.yml/badge.svg)](https://github.com/NativeScript/libffi-buildscripts/actions/workflows/build.yml)

# libffi build scripts for NativeScript

Builds the [libffi](https://github.com/libffi/libffi) static libraries the
NativeScript runtimes link and publishes them as GitHub release assets.
Consumers fetch a pinned release instead of carrying the binaries in git.

The input is upstream's release tarball, unmodified, checked against the
SHA-256 in [`config.env`](config.env). That file also pins the Xcode version
and the deployment targets. NativeScript carries no libffi patches, so there
is no fork to build from: `config.env` is the whole configuration.

Upstream publishes only Windows binaries, so Apple builds have to come from
somewhere. Building them in CI from a checksummed tarball means anyone can
reproduce a release and check where each library came from.

## Matrix

| Platform | Variants | Runner |
|---|---|---|
| Apple | `arm64-device`, `arm64-simulator`, `x64-simulator`, `arm64-catalyst`, `x64-catalyst`, `arm64-tvdevice`, `arm64-tvsimulator`, `arm64-xrdevice`, `arm64-xrsimulator` | `macos-15` |
| Android | planned | `ubuntu-24.04` |

The Apple variant names match
[v8-buildscripts](https://github.com/NativeScript/v8-buildscripts), plus the
two visionOS ones, so a consumer can map both releases onto its library
directories the same way.

Every Apple variant builds in about six seconds. One runner builds them all
in sequence, with no compiler cache: a cache would cost more to restore than
the compile does.

### visionOS gets real builds

The current Apple linker refuses to put an object built for iOS into a
visionOS image:

```
ld: building for 'visionOS', but linking in object file (libffi.a[2](prep_cif.o)) built for 'iOS'
```

The linker only accepts the mismatch when invoked as `-ld_classic`, and then
prints a warning per object. Apple has deprecated that flag. So
`arm64-xrdevice` and `arm64-xrsimulator` are compiled against the visionOS
SDKs, not copied from the iOS variants.

### What each build checks

`scripts/build-ios.sh` fails the build unless:

- the archive contains only the variant's architecture;
- every member's `LC_BUILD_VERSION` carries the variant's platform, since a
  wrong tag would otherwise surface only when an app links;
- [`tests/smoke.c`](tests/smoke.c) links against it with the default linker.

On Apple silicon the Mac Catalyst smoke binaries also run (`x64-catalyst`
under Rosetta). They exercise `ffi_call` with scalars, an all-double struct
and a SIMD vector, plus a closure from `ffi_closure_alloc`, which uses the
trampoline-table allocator on arm64 Apple targets.

## Release layout

Each release carries one archive per variant and a `SHA256SUMS`:

```
libffi-<version>-ios-<variant>.tar.gz
└── ios-<variant>/
    ├── lib/libffi.a
    ├── include/ffi.h
    ├── include/ffitarget.h
    └── LICENSE
```

The headers are generated per architecture, so each archive carries its own.
They are identical across variants of the same architecture.

`ffi.h` includes `<ffitarget.h>` with angle brackets. A consumer that keeps
more than one architecture's copy in a single Xcode project may want to
rewrite it to a quoted include, so that each `ffi.h` resolves the
`ffitarget.h` beside it.

## Releasing

The build runs on every push to `main` and on pull requests that touch the
build inputs, so a commit is verified before anyone tags it. Pushing a
`libffi-*` tag also runs the `release` job. That job collects the archives,
writes `SHA256SUMS` and creates the GitHub release.

```sh
git tag libffi-3.8.1-1
git push origin libffi-3.8.1-1
```

The tag is `libffi-<upstream version>-<build number>`. The build number lets
the same libffi be re-released when only the build configuration changes. The
release job rejects a tag whose version does not match `LIBFFI_VERSION`.

> **Do not tag a commit whose message contains `[skip ci]`.** GitHub applies
> the marker to tag pushes too, so the tag lands but nothing builds. To recover
> without retagging, dispatch the workflow with `--ref <tag>`.

### Bumping libffi

1. Set `LIBFFI_VERSION` and `LIBFFI_SHA256` in `config.env`. The tarball is
   `https://github.com/libffi/libffi/releases/download/v<version>/libffi-<version>.tar.gz`.
2. Push to `main` (or open a PR) and let the build pass.
3. Tag `libffi-<version>-1`.

## Building locally

```sh
scripts/fetch.sh
scripts/build-ios.sh --variant arm64-device

# or every variant
for v in $(scripts/build-ios.sh --list-variants); do scripts/build-ios.sh --variant "$v"; done
```

Sources are unpacked into `.libffi/`, objects are built in `.build/`, and the
output goes to `dist/ios-<variant>/`. Building needs only Xcode: the release
tarball ships a generated `configure`, so autotools are not required.

## Android

Not built yet. Android will get its own job on a Linux runner with the NDK
pinned in `config.env`, and its archives will be published in the same
release as `libffi-<version>-android-<abi>.tar.gz`.
