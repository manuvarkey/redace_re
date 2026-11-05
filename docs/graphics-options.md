# Graphics quality options

Options → Graphics retains View Distance and Effects Detail, and adds two
slash-separated lists in the same style as Extra Options → Collision Damage:

- Antialiasing (MSAA): Off / 2x / 4x / 8x.
- Anisotropic Filtering: Off / 2x / 4x / 8x / 16x.

Both default to Off for old and new saves. Selected choices are bracketed and
bold; other choices are links. MSAA applies to the root 3D viewport during a
flight, including when changed while paused. Menus without a flight keep MSAA
disabled because they contain only 2D content. Standalone --mission launches
also load the saved MSAA choice. No display, resolution, UI scaling, physics,
bullet or timing settings change when choosing either quality option.

Anisotropy takes effect after restarting the game. Godot 4.7.2's Compatibility
renderer caches its maximum anisotropy in the GLES3 Config constructor and ignores
the per-viewport runtime override. See the [engine implementation](https://github.com/godotengine/godot/blob/ed1daf0bf/drivers/gles3/storage/config.cpp).
The menu shows “Restart required to apply” when the selected and startup levels
differ. Available hardware/driver limits can cap the requested quality.

The existing user://settings.cfg stores graphics/msaa as an enum index (0..3),
and rendering/textures/default_filters/anisotropic_filtering_level (0..4).
project.godot names that same file as its startup project-settings override so
the renderer reads the anisotropy cap before scripts start. No second settings
file or manual synchronization is needed. Invalid choices loaded by the game
fall back to Off. The common terrain/aircraft/scenery shader now opts into the
anisotropic mipmapped sampler; with the default cap of 1 sample (Off), it retains
ordinary mipmapped filtering. The sky and 2D UI sampling are unchanged.

## Verification

With fresh isolated data directories:

```sh
XDG_DATA_HOME=/tmp/redace-quality-test godot --headless --path redace -s tools/test_graphics_options.gd
XDG_DATA_HOME=/tmp/redace-quality-gles godot --path redace -s tools/test_graphics_options.gd -- --snapshot
```

The suite checks all selections, persistence, selected labels, link visibility and
overlap, invalid values, menu/flight MSAA transitions, Back navigation, and
preservation of existing settings and time scale. The graphical run also checks
menu artwork over each MSAA level and writes /tmp/redace-graphics-options.png.
The live X11 menu was visually inspected. Root framebuffer image readback after
removing the last camera can differ from the live window, so the menu snapshot
is taken before the flight-transition checks.

Startup and actual anisotropic sampling were verified in separate GLES3 processes:

```sh
XDG_DATA_HOME=/tmp/redace-af-test godot --path redace -s tools/test_graphics_options.gd -- --expect-startup=0 --render-probe=/tmp/af-off.png
XDG_DATA_HOME=/tmp/redace-af-test godot --headless --path redace -s tools/test_graphics_options.gd -- --write-startup=4
XDG_DATA_HOME=/tmp/redace-af-test godot --path redace -s tools/test_graphics_options.gd -- --expect-startup=4 --render-probe=/tmp/af-16x.png
```

A shallow-angle mipmapped checker plane uses the actual game's shader. Off and
16x produced different rendered pixels, confirming the sampler and startup cap
have an effect. Android/Web device testing remains manual. Video Options,
Extra Options, bullet parity, collision damage and Britain/stock-isolation
regressions passed; the Britain fixture retains shutdown resource warnings.
