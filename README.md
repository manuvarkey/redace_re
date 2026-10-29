# Red Ace remake (Godot 4)

Port of abandoned "Master of the Skies - The Red Ace" windows game logic in Godot 4.7. The original engine (Dive5 + RenderWare) is not ported.

## Build

The converted game data is already in `redace/game_data/`. Build with Godot 4.7.2 and its export templates:

```sh
GODOT=~/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64 ./build.sh   # all presets
./build.sh Web                                                          # build/web/index.html
./build.sh Linux Windows                                                # build/linux, build/windows
scripts/build_linux.sh                                                  # same per platform: build_windows.sh, build_web.sh
```

`build.sh` first puts the Microsoft core fonts (Arial, Courier New, Times New Roman, Verdana, regular and
bold) into `redace/fonts/`: copied from `/usr/share/fonts/truetype/msttcorefonts` when installed, else
downloaded from the original corefonts cabinets on SourceForge (needs `curl` and `cabextract`). They are not
redistributable, so they are not in the repository. Then it imports, exports the presets and, for Web,
unpacks the help pages next to `index.html`.

To regenerate `redace/game_data/` from the original game (needs Python 3 + Pillow, ffmpeg for CD music):
`python3 tools/isextract.py <cd>/apps <game>` unpacks the installed game tree from the CD's InstallShield
cabinets, then `python3 tools/build_assets.py <game> <REDACE.CUE> redace` converts it.

## Tools

| Path | Contents |
| --- | --- |
| `tools/isextract.py` | Pure-Python InstallShield 5/6 cabinet extractor |
| `tools/build_assets.py` | Builds `redace/game_data` from the extracted game (models, maps, art, music, help) |
| `tools/rw2gltf.py` | RenderWare 3.1 `.dff`/`.bsp` to glTF 2.0 converter |
| `tools/rwdump.py` | RenderWare chunk tree dump |
| `tools/blender_tree.py` | Low-poly tree generator for the `overrides/` models (run inside Blender) |
| `tools/redace-wine.sh` | Runs the original game or the Windows export under Wine for comparison |
| `tools/ghidra_scripts/` | Ghidra headless scripts: `ExportAll`, `ImproveAnalysis`, `ApplyGuids` for the `RedAce.exe` decompilation |

Play online: https://manuvarkey.github.io/redace_re/ - `.github/workflows/pages.yml` builds the Web preset on
every push to `main` (Godot and the no-threads web template are downloaded and cached) and deploys `build/web`
to GitHub Pages. One-time setup: repository Settings > Pages > Source = GitHub Actions.

## Phones (web and Android)

Touch devices get on-screen controls (`scripts/touch.gd`, not in the original), shown from the first touch:
tilt steering (accelerometer; neutral = how the phone is held at mission start or on CAL) or, with STICK or
without a sensor, a virtual stick dragged on the left half; THR slider at the left edge; FIRE, BOMB and
BOOST (turbo cheat) buttons; VIEW pad (hold and swipe up / down / left / right for the held camera views);
PAUSE and OBJ. Steering goes through the joystick path, so the Controls page sensitivities apply. Phones
need landscape. On the web the first tap also goes fullscreen and locks landscape; tilt comes from
`devicemotion` (head script in the Web preset). The Android back button pauses and resumes a flight and
steps back through the menus; new pilot names open the on-screen keyboard.

Android APK: `scripts/build_android.sh` (debug-signed, arm64-v8a + x86_64) writes `build/android/redace.apk`;
CI uploads it as the `redace-apk` artifact. Tested on the Android 14 emulator (x86_64, host GPU; SwiftShader
fails the canvas shader) and in its Chrome for the web build.

Run the web build from any static web server, e.g. `python3 -m http.server -d build/web`,
then open `http://localhost:8000/` (or `?mission=N` to fly a mission directly). The web preset uses
the no-threads template, so no COOP/COEP headers are needed.

To embed in a web page (e.g. a Blogger post), upload `build/web` to any https static host and paste
`build/web/blogger-snippet.html` into the post's HTML view with `GAME_URL` set to the hosted
`index.html`. The snippet shows `poster.jpg` with a Play button and only then creates the iframe
(`allow="autoplay; fullscreen; gamepad; pointer-lock"`). Tested cross-origin in headless Chromium.

## Front end and campaign

The original HTML menu pages (`language/english/Menus`, `missions/*/mission.html`) are drawn by
`scripts/html_view.gd` on the original 640x480 page. Parsing and layout follow the exe's own HTML engine
(decomp `FUN_0040d648`/`FUN_0040df35` parser, `FUN_0040b0d8` line layout, `FUN_0040bd80`/`FUN_0040bf13`
tables, `FUN_0040c1b0` alignment): items sit at the top of their line and cells at the top of their box;
column widths and row heights are the declared or natural sizes scaled to the table size; content that
does not fit a cell's height is dropped; links run on across cells until `</a>`; spacing br 0, wrap 0,
paragraph 3, alignment 2. Checked pixel for pixel against the original under Wine (options, graphics,
video, sound, controls, cheats, play, roster, replay levels, pause, credits).
Deliberate deviations, each keeping every row where the original has it:
  - tables without a width draw their cells at natural width instead of squeezed ones (row heights still
    come from the squeezed layout), so the Controls page shows "Controller"/"Sensitivity" in full and
    "Fire Second Weapon" on one line, and the volume bars keep their right end cap (the exe cut words to the
    cell and moved a wrapped image out of sight); such a table may run a few pixels past its cell;
  - the Controls page's "Set to default for: Mouse / Joystick / Keyboard" row, which the exe drops for lack
    of room, goes into the empty Sensitivity cells of the Fire Guns to Camera Left rows (`game.gd`
    `_controls_defaults_row`).
`scripts/game.gd` fills the pages' `^placeholders^`
with the same HTML snippets the exe generated and handles their links (`command:`, `play:N`,
`characterplay:N`, ...):

- title screen (5 s), main menu, options (sensitivity, volumes, view distance, effects detail, vsync,
  window mode, control layout), credits, goodies (replay levels, demo levels, cheats after finishing).
- pilot roster with 6 slots (type a name, Enter), Start/Continue Campaign, briefings, Fly Mission,
  loading page, pause page (Esc: continue, restart, abort), result pages (victory, promotion,
  debriefings, defeat with the reason: plane destroyed, mission critical object lost, out of time),
  congratulations after mission 25.
- ranks Corporal..Colonel promoted at scores 700, 1800, 2800, 4000, 5400, 7000, 8800, 10800, 12600,
  14400 (exe tables at 0x51af4c / 0x51b1cc); mission score = 500 for a win + 100 - % surviving for each
  destroy group + % surviving for each protect group (`FUN_00446aa1`).
- Pilots and settings are saved in `user://pilots.cfg` and `user://settings.cfg`.
- Menu music is music.ini entry 2; missions use their `[music] track` entry (CD track N + 1).
- Cheats as in the original options page: turbo boost on Space, infinite bombs/rockets,
  invulnerability, game speed, enemy endurance.

## Controls

Bindings follow the original control files (`redace.ini` = `mousekeys.ini` by default; `keyboard.ini`,
`joystick.ini`): Options > Controls lists each action with its controller and value. Click an action, then
press a key, move the mouse (axes) or press a mouse/joystick button to rebind it; "Set to default for"
loads one of the three files. Sensitivity bars and "Reversed?" boxes as in the original.

| Action | Default (mouse) |
| --- | --- |
| Roll / pitch | mouse X / mouse Y (back = nose up) |
| Throttle | Right Shift / Right Ctrl |
| Guns / bombs | left / right mouse button |
| Special (turbo boost cheat) | Space |
| Views (held) | Up above, Left, Right, Down behind |

Esc (or P) in flight opens the pause page (Continue, Restart Mission, Abort Mission). On the web,
the browser's own Esc releases the mouse; that also opens the pause page.
In flight `[` `]` and `-` `=` nudge roll / pitch sensitivity; Tab shows objectives and a debug line.

Mission audit: `godot --headless --path redace -s tools/audit_missions.gd` loads every mission and
lists unplaced objects, missing models/sounds, bad goal targets, objects off the map or under the terrain.

Debug flags (desktop, after `--`): `--mission=N` (skip the menus), `--autopilot`, `--view=N` (hold camera
mode 1/4/6/7/8), `--perf`, `--pages=Menus\a.html,...` (show pages), `--clicks=href,key:esc,...` (follow links).

## What is implemented

- All 28 missions load from the original `mission.ini`: map, ground objects, vehicles, aircraft, music track.
- 3 maps (RenderWare `.bsp` worlds), 159 models (`.dff`), sky boxes, fog colour, briefings from `mission.html`.
- Flight model from the decompiled plane update (`decomp/RedAce.c:32540`): throttle/climb/dive target speed,
  acceleration, lift = speed^2 * mass * 10 / cruisespeed^2, gravity mass * 10, speed-dependent roll/pitch rates,
  stall, altitude ceiling at 400, runway take-off. Values come from each `plane.ini`.
- Guns as in the original (`RedAce.c:31605`): `firerate` rounds per second in bursts of `fireon` s
  with `fireoff` s pauses. Projectiles use `objects/ordinance/ordinance.ini`: bullet (damage 1, spread 0.04),
  bomb (damage 75, blast 30), rocket (damage 50, blast 20), AA fire (damage 2.5).
- Bombs (`ordinancetype = 1`) and rockets (`2`) with the mission's `numordinance` count.
- AA guns (`[ai] turret = antiaircraft`) fire leading bursts at opposing aircraft within 750.
- Mission rules from the decompiled check (`FUN_00446b7b`, `RedAce.c:40170`): object `groups` bitmask;
  `GroupN = -P` destroy P % of group N to win, `GroupN = +P` fail when fewer than P % survive (groups 0-9),
  `timelimit` in seconds.
- Starts and aircraft scripts (`[airNgoalK]`) follow the decompiled pilot code (`FUN_00436f41`, goal list
  built by exact type at `RedAce.c:34449`, run one at a time by `FUN_00438937`). Every aircraft, the
  player's too, is created parked (state 4, speed 0) at its mission position; then its goals run:
  0x100 moves it to the goal position in the air at full throttle and `highspeed` (Training 1/2, most
  missions), 0x170 hides it, 0x160 shows it after N s, 0x120 shows it when the group/object `targetid`
  member nearest to it is within N of the goal position (reinforcements), 0x130/0x140 switch "retaliate
  when hit" on/off, 0x10 take off, 0x20 waypoint, 0x30 formation on an object, 0x60 evade, 0x70 gun
  attack, 0x80 dive attack with rockets, 0x90 level bombing run (0x80/0x90 turn into gun attacks once the
  ordnance is spent). With no goals left a plane flies to random points of the battle area; it never
  shoots outside an attack goal. Other type values (mission 3's player has 0x102) are
  dropped like the original, so those planes start parked (verified against the original under Wine:
  Training 1 starts airborne, mission 3 on the runway). Hidden planes are not drawn, targeted or hit.
  `targetid <= 0` means group `-targetid` (bit of `groups`). Mission entries may override `endurance` and
  `highspeed`. On the ground a plane sits gear height + 0.05 above the terrain (along its slope) and nose-up
  by atan(gear / tail), resting on wheels and tail skid: gear = -min y and tail = -min z of the clump's
  vertices, the values the exe puts in place of plane.ini's [collision] lengths (`FUN_0042e91a`,
  RedAce.c:30730). Touch-down happens when the gear meets the ground: sinking slower than 5 and wings
  near level lands, faster crashes.
- Edge of the battle area: warning near the edge, flown back when outside (strings.ini messages).
  Aircraft on the ground stay parked until their script says take off.
- AI steering follows the goal handlers (`FUN_00439376` steer, `FUN_0043b2a8` terrain pull-up,
  `FUN_00439e6f` 0x70, `FUN_0043a825` 0x80, `FUN_0043ad4b` 0x90, `FUN_00439206` 0x30): bank = -90 * target
  direction . right (full bank toward its side when behind), pitch rate = 90 * direction . up, bank change
  limited to 3 * rollrate deg/s, commanded pitch rate decays when no goal sets it (waiting planes circle).
  Gun attack: leads aircraft by distance / 275 * speed, matches their speed (throttle 0.65..1), fires when
  the target is within 37 deg and 300, turns hard to a random side when it is behind, breaks off above 80 %
  damage or after the 0x130 time limit. Dive attack: approaches 350 above, dives inside 300, fires rockets
  lined up within 225, climbs away (+250) when low or overhead. Bombing run: 140..160 above the target,
  releases when the predicted impact is within 30, goes round after overflying. When hit (`FUN_00437af6`):
  evade for 0.5 s toward a random point beside, or with 0x130 on attack the attacker. Planes sidestep the
  nearest group-8 aircraft (player side) when about to collide (`FUN_004394df`), and turn back 500 from
  the battle edge when idle.
- AI fire only damages aircraft and the AI's assigned ground target, so stray fire does not fail "protect" missions.
- HUD with objectives and time left, minimap (`map.png`) with allied/enemy aircraft, objectives and AA guns.
- Engine, gun, hit and explosion sounds from each object's INI; CD music tracks.
- Controls, flight attitude, camera and HUD follow the decompiled code:
  - input `FUN_004322de`: mouse bank += (s * 0.25 + 0.025) * dt * highroll * mickeys, pitch rate +=
    (s * 2.5 + 0.25) * dt * highpitch * mickeys (dt fixed at the original 30 fps); keyboard bank +=
    (s + 0.1) * 7 * highroll * dt with auto-level at highroll deg/s.
  - attitude `FUN_00432a5f` (asm 0x4343a6-0x434440): unrolled flight frame, bank about forward for display,
    turn = sin(bank) * rollrate about world up, pitch rate decay 5 deg/s per frame, bank +-90 and roll-out flip.
  - camera `FUN_00435c19`/`FUN_0043572b`: chase/behind/left/right/above offsets, level horizon,
    90 deg vertical FOV, 4 * dt easing; views held on keys.
  - HUD `FUN_0042f026`/`FUN_0042f7db`/`FUN_0042fdc0`: status dial (throttle needle, bullet-hole damage,
    bomb/rocket count), heading-up map with compass ring and group 6-9 icons, timer.
- Propellers (atomics textured `soppropeller`) spin with the throttle.
- Damage and effects follow the decompiled code:
  - planes `FUN_0042eda0`: damage accumulates to `endurance` (bullet 1, AA 2.5); each hit adds smoke,
    plays `hitsound`/`althitsound` and throws a cloth particle; at endurance a mid-air burst, then the plane
    spins down trailing dark smoke and explodes on the ground (burst endurance * 0.1 + smoke column);
    damaged planes trail grey smoke at damage * 5 / endurance puffs per second (`RedAce.c:31878`);
    gentle ground contact lands instead of crashing.
  - ground objects `FUN_0042c00e`: model steps through `damagedff1..3` by damage fraction; destruction
    makes a burst (endurance * 0.03), a long smoke column (120..247 s) and the breakage sound.
  - bombs/rockets `FUN_0044cf81`: blast damage (radius - distance) * damage, 0.05x on own side.
  - bullet impacts `FUN_0044cd2a`: maroon puff on terrain, hit spark on objects.
  - particle textures `objects/particles` (smoke, cloth, hit, maroon, clod) as camera-facing sprites.
- Fonts: `morpheus.ttf` and `annifont.ttf` from the game; the pages' Courier New, Times New Roman, Arial and
  Verdana are the Microsoft core fonts, put into `redace/fonts/` by `build.sh` (not redistributable, so
  not in the repository). Sizes follow the original HTML
  engine: cell height = size * 2 + 12 px, default face Arial (`FUN_004025e2`). Glyphs are drawn without
  antialiasing at the whole-pixel GDI advances; the exe copies GDI glyphs setting every touched pixel
  (`FUN_00429758`), which thickens strokes, so outlines are emboldened (`GLYPH_EMBOLDEN_PX`, lightened for readability
  for the game's fonts, `CORE_EMBOLDEN_PX` for Arial/Courier/... to match the original's heavier small text).
- Roster shows the exe's short rank names (Cpl., Sgt., ... table at 0x51b08c) and "New Pilot" on every
  empty slot; the Controls page shows mouse axes as "axis N" like the exe.
- All game raster art is upscaled at build time with Real-ESRGAN x4plus (`build_hires` in
  tools/build_assets.py, batch run with tile size 128 - the automatic tile size returned partly black
  images on this GPU): menu pages and briefing art 4x (HtmlView.ART_SCALE divides natural image sizes,
  so layouts are unchanged), sky boxes 4x, map / ground-object / plane textures 4x then Lanczos to 2x,
  wrap-padded so tiling textures stay seamless; alpha masks are upscaled separately. Images import as
  lossy WebP (quality 0.85) with mipmaps (project importer defaults), so the pck stays ~47 MB. The
  help pages (opened in the system browser) keep their original images.
- HUD, particle and map bitmaps are upscaled at build time for high resolutions: HUD art (dial, compass
  ring, throttle needle, bomb/rocket icons) and the minimaps 4x with Real-ESRGAN x4plus (colour and mask
  separately; `REALESRGAN` = path to `realesrgan-ncnn-vulkan`, default `~/tools/realesrgan/`; falls back to
  Lanczos), particles 4x with Lanczos + unsharp mask; the 8x8 map icons 8x with
  Scale3x twice then Lanczos (crisp edges), keyed on their top-left colour like the original (their masks
  are all opaque; the dark corners are transparent in the original); the HUD samples them with mipmaps.
- Mouse cursor: the original's own (`Ui/cursor.ini`: `menucursor.bmp` + mask), frame 0 (arrow) on all
  pages including over links, hotspot at the tip, Real-ESRGAN-upscaled and shown at the page scale.
- Collisions (`FUN_00431607` probes, `FUN_00430199`): nose/tail/wingtip/top/underside segments from the
  previous position, against other planes' and ground objects' triangles (box test first), as the exe tests atomics.
  Deviation: the probes keep plane.ini's [collision] lengths; the exe's wingspan-sized ones made the
  remake's formations collide constantly. Hitting a
  plane or solid object destroys the prober (endurance + 1); the other takes 2 * dt * endurance * 0.2
  (planes) or * 15 (ground objects); `[physics] soft = 1` objects (trees) wear the plane down instead.
  Nose into terrain crashes; a wingtip into terrain sends the plane into its falling spin.
- Joystick: an axis on Throttle is an absolute lever like the exe (a self-centring axis returns to half);
  a joystick button (or gamepad trigger) pressed on a Throttle/Roll/Pitch row binds upbutton/downbutton,
  stepped like keys (exe control type 7).
  Deviation: "Joystick" defaults (joystick.ini, throttle on axis 3 = a flight stick's Z lever) put the
  throttle on the triggers when a known gamepad is connected, since its axis 3 is self-centring.
- Plane shadows: each plane's `shadow` clump from plane.ini, flattened onto the ground under it
  (`RedAce.c:31814`).
- Sounds as the exe assigns them: menu click on every link, bullet-into-ground (`bulletground1`), bomb
  blast `explosionmedium2`, rocket blast `explosionsmall`, rocket launch / bomb hatch from plane.ini;
  plane hit: `hitsound`/`althitsound` at random on every hit; ground object: `hitsound` at 0.75 volume
  (default `bulletbuilding1`), `breakage` on each damage-model change and `explosion` when destroyed
  (both default `explosionsmall`, RedAce.c:29418).
- Ground damage models as the exe loads them (0x42b412): `deaddff` = wreck as stage 1 of 2 (60 object
  types, most placed objects), `damagedff1..3` = further stages; stage = trunc(damage / endurance *
  (stages - 1)) (FUN_0042c00e), so the wreck shows only when destroyed. Four inis name a model from
  another object's folder (aagun2-4 -> aagunruin.dff, oildrum -> Oilrigburn.dff); it is looked up there.
- Mission `[vehicleN]` sections are vehicles with turret AI (all real AA guns, tanks, ship turrets);
  `[groundN]` sections are scenery. The 94 placed `aagunruin` wrecks (ground sections) therefore never
  fire, though their ini says `turret = antiaircraft`.
- Model overrides: `overrides/` mirrors `game_data/` paths and is copied over the converted files
  last (`build_overrides`); `overrides/blend/` keeps the Blender sources. First one: `tree1` (`tree2.gltf`,
  281 trees in mission 1), remodelled in Blender with a tapered trunk, six branches and a lobed crown
  of leaf cards (376 triangles vs the original's 4 crossed cards), same footprint (40.8 x 43.3), original
  `tree1top` and `bark` textures, crown normals pointing out of the crown so it shades as a volume.
  The other card trees followed, generated by `tools/blender_tree.py` (run inside Blender; sources in
  `overrides/blend/trees.blend`): `tree2` poplar (column of card rings, 422 tris), `tree3` autumn
  broadleaf (lobed crown, 382 tris), `tree4` fir (drooping card tiers on a cone, 186 tris), each scaled
  to its original footprint and using its original foliage texture plus `bark.png` (tinted
  0.42/0.36/0.30). After export the glTF image paths are pointed at `../textures/`.
  Desert vegetation too: `palmtree` / `palmtree2` (855 placed) get a curved ringed trunk and 13 / 11
  arched, folded fronds (488 / 440 tris, was 50 / 78 faces); `desertscrub` (5394 placed) a star of
  five tilted cards plus three top cards (16 tris, was 12). Its wreck (`deaddff`) in the original is a copy
  of the 11-high burnt trunk the poplar, fir and palms use; it is replaced by a burnt scrub (the same
  card build, 9 x 4.5, textures tinted 0.14/0.11/0.09) in `overrides/.../desertscrub/treestumpburn.gltf`,
  which only the scrub's folder resolves to. `forest` is never placed; burnt stumps are
  wreck models and stay.
- Hit flash (FUN_0042c2b6 / FUN_0044a1bc): a plane hit, or a hit mission target (group 7), is drawn
  through 50 % red fog for 0.25 s.
- Bullets as the exe draws them (FUN_0044c4fe): camera-facing ribbons of `bullet.bmp` 20 units long ahead
  of the round, half-width = ordinance size (0.3 guns, 0.5 AA), alpha 0xc4. Gun hits on planes only give
  the plane's own effects (cloth scrap, knock, flash); on objects a `hit` puff, on the ground a `maroon`
  puff 8 above the impact (FUN_0044cd2a). Bombs and rockets on planes burst at the plane (FUN_0044ced8).
- Bomb and rocket smoke trails (RedAce.c:43373): 20 puffs/s (bombs, size 0.1) or 30/s (rockets, size
  0.75), grey 0.9 at alpha 0.7 fading 0.3/s, growing 2/s, drifting up 15/s.
- End of a flight (RedAce.c:51041, FUN_0045db9e): the world runs on for 2.5 s while the screen fades to
  black and music/effects fade out, with one line 20 px above the centre (Mission Accomplished, Plane
  Destroyed, Mission Critical Object Destroyed, Out of Time, Mission Aborted); a key skips. Abort Mission
  on the pause page goes through the same fade to the defeat page; effects fade in over the first second
  of a flight; "Plane Destroyed" waits until a shot-down plane has reached the ground.
- Screen-mode change asks on `screentest.html` and reverts after 5 s without an answer.
- Help: the main menu's Help link opens the original help web pages in the system browser, as the original
  did (ShellExecute). They are kept untouched in `game_data/help.zip`; desktop builds unpack it to
  `user://help` on first use, the web build opens `help/...` next to `index.html` (see Build).
- Briefing control words are built like the exe (`RedAce.c:47380`): `'right Shift'`, `'Mouse Left'`,
  `'left mouse button'`, `Joystick 'POV Up'`.
- Exports: Web (WebAssembly/WebGL 2), Linux, Windows.

## Not done yet

- AI deviations from the exe: gun attacks and visible waits also use the general low-altitude pull-up
  (this flight model needs more room than the exe's 4 s look-ahead; without it AI planes flew into hills);
  the bombing run's +-1 deg/s altitude nudge uses the corrective sign (decompiled it reads inverted);
  formation speed matching slows down when faster than the leader (decompiled it reads inverted);
  enemies leaving the map by 150 are not removed; goals 0x110/0x150 (unused by the missions) are ignored.
- `splat.bmp` is loaded by the original but never drawn, so it is not used here either.
- Mission 17 names a non-existent object `aagu_light`; it is skipped (as the original could not load it).
