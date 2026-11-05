# Video resolution options

Options → Video Options offers Very Low (360p), Low (480p), Medium (540p),
Standard (720p), High (1080p) and Native (the default, including old saves).
Presets are vertical pixel ceilings: a smaller output stays at Native instead
of supersampling. The width follows the current window/device aspect ratio.
Godot rounds internal buffer dimensions to whole pixels.

The root viewport uses bilinear `scaling_3d_scale`, supported by this project's
Godot 4.7 GLES3 Compatibility renderer (see the [GLES3 buffer implementation](https://github.com/godotengine/godot/blob/4.6/drivers/gles3/storage/render_scene_buffers_gles3.cpp)). Only the 3D color/depth buffers shrink;
`canvas_items` / `expand` in project.godot stays unchanged. Menus, HUD, touch
controls, camera projection and input coordinates retain their existing output
space. Window resizes reapply the scale. No simulation, physics, projectile,
AI or control code changes. Video previews do not change Engine.time_scale.

Desktop builds offer windowed/fullscreen and window sizes derived from the
current screen's aspect ratio, filtered to fit its usable area. Saved sizes
are clamped to fit a smaller screen. Default window size is 720 lines (clamped
when selected); existing installations keep their current startup window size.
Fullscreen uses the native desktop mode; there is no exclusive monitor mode or
refresh-rate switching. Internal resolution remains independently selectable.
Android stays fullscreen at the device's physical resolution. Web retains the
browser's dimensions. Both use the same internal scaling presets.

All mode, window-size and rendering changes use the existing five-second
confirmation page. Yes saves them; No or timeout restores the previous settings
and, for desktop display changes, window size and position. The timer works
while paused and ignores game speed. Previews are not saved until confirmed,
even if an unrelated save runs. Settings use video/render_height (0 = Native)
and video/window_height (0 = Default) in user://settings.cfg. Unknown values
fall back to defaults. View Distance and Effects Detail remain on Graphics Options.

## Verification

Run with a fresh data directory so settings tests do not touch player saves:

```sh
XDG_DATA_HOME=/tmp/redace-video-test godot --headless --path redace -s res://tools/test_video_options.gd
```

The headless suite checks 4:3, 16:9, 16:10 and ultrawide scaling, every preset,
old/invalid settings, persistence, preview rollback, stale timers, pause/game
speed independence, and menu link bounds/overlaps with all window sizes visible.

Omit `--headless` on a desktop with a working graphical display to additionally
check window sizing/fullscreen rollback, capture `/tmp/redace-video-options.png`,
and compare Native/360p pixel patterns rendered through GLES3 at three aspect
ratios. The fragment shader alternates pixels using FRAGCOORD, so filtering of
that pattern verifies a smaller internal 3D buffer, beyond reading the property.
Use another fresh XDG_DATA_HOME for this run.

The implementation environment passed the headless suite and existing collision
damage/management and Extra Options regression suites. A forced headless startup/exit
also ran, with ObjectDB/resource cleanup warnings at shutdown. Graphical tests could not run because no
accessible X11/Wayland display was available. Windows, Android and Web device
checks, touch/controller interaction and GPU performance measurements remain
manual verification steps; no measured frame-rate improvement is claimed.
