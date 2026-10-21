#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
repository=$(cd "$root/.." && pwd)
cd "$repository"
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
sdk=${1:-iphonesimulator}
case "$sdk" in
  iphoneos) target=aarch64-apple-ios; platform=ios ;;
  iphonesimulator) target=aarch64-apple-ios-sim; platform=ios-simulator ;;
  *) exit 2 ;;
esac
build=${CHUZZLE_NATIVE_BUILD:-"$repository/.build"}
export CARGO_TARGET_DIR="$build/rust"
export IPHONEOS_DEPLOYMENT_TARGET=15.0
export SDKROOT=$(xcrun --sdk "$sdk" --show-sdk-path)
sdl="$build/sdl/$sdk/install"
if [ ! -f "$sdl/lib/libSDL2.a" ]; then
  CHUZZLE_SDL_BUILD="$build/sdl" bash "$root/rebuild_sdl.sh" "$sdk"
fi
export CHUZZLE_SDL_LIBRARY="$sdl/lib/libSDL2.a"
unset RUSTFLAGS
rust_flags=(-L "native=$sdl/lib" --remap-path-prefix "$HOME=~" --remap-path-prefix "$repository=.")
frameworks=(UIKit Foundation OpenGLES OpenAL QuartzCore AVFoundation AudioToolbox CoreAudio CoreGraphics CoreMotion GameController CoreHaptics CoreBluetooth Metal Security)
link=()
for framework in "${frameworks[@]}"; do
  rust_flags+=(-C link-arg=-framework -C "link-arg=$framework")
  link+=(-framework "$framework")
done
printf -v CARGO_ENCODED_RUSTFLAGS '%s\x1f' "${rust_flags[@]}"
export CARGO_ENCODED_RUSTFLAGS=${CARGO_ENCODED_RUSTFLAGS%$'\x1f'}
if [ ! -f "$root/compatibility-core/src/cpu/interpreter/native_generated/mod.rs" ]; then
  python3 "$root/generate_native.py" "$root/Original/Chuzzle" --classes '*'
fi
if [ ! -f "$root/compatibility-core/src/cpu/interpreter/runtime_generated/mod.rs" ]; then
  python3 "$root/generate_runtime.py"
fi
cargo_args=(build)
if [ "${CHUZZLE_AOT_REFERENCE:-0}" = 1 ]; then
  cargo_args+=(--features aot-reference)
fi
cargo "${cargo_args[@]}" --manifest-path "$root/ios/rust-entry/Cargo.toml" --target "$target" --release --offline --locked
app="$build/$sdk/Chuzzle Original Port.app"
mkdir -p "$app"
# Rebuilding must not retain an old developer signature or provisioning profile.
rm -rf "$app/_CodeSignature"
rm -f "$app/embedded.mobileprovision"
xcrun --sdk "$sdk" clang -ffile-prefix-map="$HOME=~" -arch arm64 -isysroot "$SDKROOT" \
  -target "arm64-apple-$platform" -mios-version-min=15.0 \
  -I "$sdl/include/SDL2" "$root/ios/main.m" "$root/ios/frame_timing.m" \
  -Xlinker -force_load -Xlinker "$sdl/lib/libSDL2.a" \
  "$CARGO_TARGET_DIR/$target/release/libchuzzle_compatibility.a" \
  -L "$sdl/lib" -lSDL2main -lSDL2 -lc++ -liconv "${link[@]}" \
  -Wl,-no_adhoc_codesign -o "$app/ChuzzleCompatibility"
cp "$root/ios/Info.plist" "$app/Info.plist"
ditto --norsrc --noextattr "$root/ios/Settings.bundle" "$app/Settings.bundle"
if [ "$sdk" = iphonesimulator ]; then
  plutil -replace CFBundleSupportedPlatforms.0 -string iPhoneSimulator "$app/Info.plist"
fi
cp "$root/Original/Chuzzle.ipa" "$app/Chuzzle-1.0.ipa"
cp "$root/Original/Icon.png" "$app/Icon.png"
for resource in touchHLE_fonts touchHLE_dylibs; do
  ditto --norsrc --noextattr "$root/compatibility-core/$resource" "$app/$resource"
done
cp "$root/compatibility-core/touchHLE_default_options.txt" "$app/"
cp "$root/compatibility-core/LICENSE" "$app/touchHLE-LICENSE.txt"
cp "$root/compatibility-core/src/cpu/interpreter/LICENSE" "$app/ARM-runtime-LICENSE.txt"
cp "$root/native-manifest.json" "$app/"
cp "$root/runtime-manifest.json" "$app/"
python3 "$root/compile_icon.py" "$sdk" "$app"
mkdir -p "$app/ThirdPartyNotices"
ditto --norsrc --noextattr "$repository/Notices" "$app/ThirdPartyNotices"
if [ "$sdk" = iphonesimulator ]; then
  codesign --force --sign - "$app"
fi
printf '%s\n' "$app"
