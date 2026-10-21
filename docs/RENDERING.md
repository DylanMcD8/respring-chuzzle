# Rendering and frame timing

The game retains its original 320×480 coordinates and centered 2:3 layout. At launch, the host selects an integer render scale large enough to cover the display-backed play area, with an 8× cap. Original sprites and bitmap fonts retain their original resolution.

On the tested 13-inch M4 iPad Pro with **More Space**, UIKit reports a 2400×3200 backing surface. The game renders into a 2240×3360 texture (7×) and presents into a centered 2133×3200 viewport. These backing dimensions can exceed the physical panel resolution because of display scaling.

The guest drawable is texture-backed. Presentation samples that texture directly instead of allocating or copying a full-screen image every frame. The modified SDL UIKit host enables Retina backing and the host build explicitly links the current SDL archive before the Rust archive, avoiding stale bundled SDL objects during incremental builds.

A 70-second device sample, excluding the first timing interval, measured **59.9 game updates and render submissions per second**, with **59.91 CADisplayLink callbacks per second**. The earlier copy-based high-resolution candidate measured approximately 27 FPS. These counters describe submissions, game updates, and OS callbacks; they are not a physical scanout or latency measurement and do not guarantee performance on every device.

The simulator's legacy OpenGL renderer is substantially slower than this physical iPad. Large Retina simulator configurations can also delay the original loading sequence. Physical hardware is the useful performance reference. `CHUZZLE_RENDER_SCALE=1` is available for comparison/debugging; it does not replace or upscale source assets.

Detailed metrics are disabled on ordinary launches. See [BUILDING.md](../BUILDING.md) for diagnostic environment variables. The default remains 60 FPS: requesting 120 display frames does not supply new intermediate animation poses to the original game logic.

## Version 0.5.4: Duo and optional cropped fill

Built with the iOS 27.1 SDK. Starting with iOS 27.1, the host ignores the legacy UIRequiresFullScreen compatibility request and supports native window rotation. The original game remains in portrait coordinates. Presentation refreshes the drawable from the active scene bounds after rotation or display changes. Older OS versions retain the portrait compatibility behavior.

Settings offers Use Full Resolution (on by default) and Fill Screen (Cropped) (off by default). The latter applies a uniform centered scale to the original 2:3 viewport. It can crop menus and game controls; it does not rearrange the game. UIKit converts touch coordinates through the view transform before SDL normalizes them. Force quit and reopen to apply either setting.

The crop factor is max(width/320, height/480) divided by min(width/320, height/480). Full-resolution target selection accounts for this larger extent, still capped at 8×. Backing texture scale is chosen at launch; folding can change the presentation size without reallocating the guest texture scale.

The port also keeps the screen awake while active, restoring normal sleep behavior when inactive. Build 11 disables SDL’s fullscreen Home gesture deferral, allowing the usual single swipe. Chuzzle retains its existing 60 FPS timing, save fixes and audio lifecycle implementation. Koi-specific ripple timing, vibration, artwork and 120 FPS simulation changes are not applicable.
