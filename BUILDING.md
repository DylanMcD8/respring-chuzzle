# Building Chuzzle

## Tools

Use an Apple silicon Mac with full Xcode selected by `xcode-select`, Python 3, CMake on PATH, and Rust installed through rustup. Xcode 27.1 and CMake 4.3.5 were used for validation. Icon compilation uses Xcode's `actool` with the editable `Chuzzle.icon` document.

From this repository:

```sh
rustup toolchain install 1.99.0 --profile minimal
rustup target add --toolchain 1.99.0 aarch64-apple-ios aarch64-apple-ios-sim
```

The toolchain installation needs a network connection. Cargo dependencies are vendored and builds use `--offline --locked`; no private cache or local signing setup is needed. `Vendor/SDL2` includes the scene and display changes used by this app. CMake rebuilds it on the first build for each platform.

## Xcode

Open `Chuzzle.xcodeproj` and select the Chuzzle scheme. The shared scheme invokes the Rust/SDL build and produces an ordinary application product. Xcode handles signing for device builds. Set your own team and, if needed, a unique bundle identifier in target build settings. There is deliberately no saved team or profile. Xcode processes `OriginalPort/ios/Info.xcode.plist`, which expands your bundle identifier and preserves the compiled app icon metadata; direct script builds use `Info.plist`.

Both Debug and Release compile the translated Rust code with release optimizations: debug execution of hundreds of thousands of translated instructions is impractically slow. Diagnostics are controlled by launch environment variables.

Command-line simulator build:

```sh
xcodebuild -project Chuzzle.xcodeproj -scheme Chuzzle \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/chuzzle-xcode CODE_SIGNING_ALLOWED=NO
```

Command-line device build without signing:

```sh
xcodebuild -project Chuzzle.xcodeproj -scheme Chuzzle \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/chuzzle-xcode-device CODE_SIGNING_ALLOWED=NO
```

For Xcode's Run/Archive actions on a physical device, leave signing enabled and select your team. An unsigned device app cannot launch until signed.

## Direct builds and packaging

```sh
CHUZZLE_NATIVE_BUILD=/tmp/chuzzle-build bash OriginalPort/build.sh iphoneos
python3 Scripts/package_ipa.py \
  '/tmp/chuzzle-build/iphoneos/Chuzzle Original Port.app' \
  --output release-output/Chuzzle.ipa
```

Use `iphonesimulator` for an ARM64 simulator app. Never package a simulator app as a device release. `package_ipa.py` stages a copy, removes the local signature/profile and nested iTunes metadata, and leaves the input app untouched. The output requires re-signing by the recipient.

Prefer a local build directory outside iCloud/File Provider-managed Documents folders. Xcode's normal DerivedData is suitable. First builds can take tens of minutes. Incremental builds are much faster.

## Source layout

- `Chuzzle.xcodeproj`: build/run/archive entry point.
- `OriginalPort/ios`: Objective-C UIKit host, rendering-scale selection, Rust entry point, app metadata.
- `OriginalPort/compatibility-core`: modified touchHLE runtime, ARM semantics, generated translation, bundled runtime libraries and fonts.
- `OriginalPort/Original`: original executable, sanitized app archive, and legacy icon used by the loader.
- `Chuzzle.icon`: editable Icon Composer document.
- `Vendor`: pinned Rust dependencies and modified SDL2 source, including their licenses.
- `Scripts/package_ipa.py`: unsigned public IPA packaging.
- `Notices`: license texts included in the app.

The original input archive contains only its app payload; purchase/account metadata is excluded. It still contains original game content. The public source package must not be mistaken for a new open-source license to that content.

Regenerate the translation with the exact original executable and bundled libraries:

```sh
python3 OriginalPort/generate_native.py OriginalPort/Original/Chuzzle --classes '*'
python3 OriginalPort/generate_runtime.py
```

The manifests record original input hashes and translation coverage. Unexpected instructions stop a shipping build at runtime; there is no interpreter fallback. `CHUZZLE_AOT_REFERENCE=1` is a development-only build switch and must never be used for releases.

## Diagnostics and rendering

Xcode scheme → Run → Arguments → Environment Variables:

- `CHUZZLE_RUNTIME_DIAGNOSTICS=1`: frame and display timing logs.
- `CHUZZLE_AOT_STATS=1`: translation counters.
- `CHUZZLE_RENDER_SCALE=1`: original 320×480 framebuffer for comparisons. Leave unset for automatic display-resolution coverage; integer overrides 1–8 are accepted.

The automatic scale is selected at launch from the display bounds reported by iOS, including More Space scaling. The game retains portrait coordinates. On iOS 27.1 and later the native window can rotate and resize independently, including on Duo. The default centered 2:3 viewport can optionally be enlarged with Fill Screen (Cropped) in Settings. Artwork is not resampled or replaced in the source package.

Standalone render-scale checks:

```sh
xcrun clang Tests/render_scale.c -o /tmp/chuzzle-render-scale-test
/tmp/chuzzle-render-scale-test
```

Do not commit device data, private keys, provisioning profiles, build output, or personal Xcode settings. The provided `.gitignore` excludes common local artifacts.
