# Red Baron mod: implementation plan

Phase 0 output. Source of truth for content: `red_baron_mod_design.md`. This file covers how the
mod plugs into the engine, the hooks that must be added, and where the design's INI cannot run as
written. Deviations found later go to `IMPLEMENTATION_NOTES.md`.

## Baseline (before any engine change)

Run on branch `redbaron-mod` at `1ff6844` (Phase 0 notes commit), Godot 4.7.2 headless.

| Suite | Result |
| --- | --- |
| `tools/audit_missions.gd` (28 stock missions) | 17 distinct issues, all pre-existing (missing ricochet sounds, ignored goal types 0x0/0x21/0x7b/0x102, trenches houses outside map, `aagu_light`) |
| `MS=26 tools/audit_missions.gd` | 0 issues |
| `test_britain`, `test_britain_aircraft` (149 checks), `test_britain_assets.py` | pass |
| `test_avoidance`, `test_bullets` (31), `test_collision_damage`, `test_collision_management` (32), `test_environment_quality` (306), `test_extra_options` (91), `test_graphics_options` (7990), `test_probe_detection`, `test_replay_menu` (211) | pass |
| `test_video_options` | 391 checks, **1 failure before any change** ("all rendering, window size, mode, vsync and Back links fit"); treated as baseline, must not get worse |

Every phase reruns the same set and compares against these logs.

## What the engine already gives the mod

- `[mod] init = res://mods/<name>/init.gd`: `ModLauncher.for_mission` instances the node, World adds it
  under the level **before** map, objects and planes, and calls the optional hooks `setup_map(world, env,
  level)`, `create_aircraft()`, `configure_aircraft(plane, section)`, `counts_as_lost(plane)`, `is_sea`,
  `sea_crash`, `apply_graphics_quality`, plus the `camera_distance_scale` property.
- `setup_map` receives the map's `Environment` and the World, so per-mission fog colour, sky textures and
  ambient light can be set by the mod without a core change (sky shader parameters `sky_*`, `fog_color`;
  global shader parameter `ra_fog_colour`; `env.fog_light_color`).
- Aircraft state is public enough to script from a mod: `goals`, `goal_index`, `_set_hidden()`,
  `take_damage()`, `health`, `throttle`, `fire_input`, `present()`, `left_map`.
- `World.message_label` (HUD message line), `World.planes`, `objects_by_id`, `mission_time`.
- The minimap already shows group 8 allies and clamps far ones to the rim at half alpha, which is a
  usable "Brenner is over there" indicator for mission 11.

What is missing: a deterministic per-frame call, a way to own the win/lose decision, custom end text and
result pages, saving campaign progress before the flight ends, and any campaign other than the stock 25.
`[mission] requireshotdown` is read into `World.require_shot_down` but only Britain's aircraft use it
(edge behaviour); it does not change the rules.

## New generic hooks

All optional (`_mod.has_method(...)` / signal unused = stock behaviour), named for what they do, documented
in `mods/launcher.gd`, none mentioning this mod. Britain defines none of them and runs unchanged.

| # | Hook | Where | Stock behaviour when absent |
| --- | --- | --- | --- |
| H1 | `mission_step(world, dt)` | `World._physics_process`, after player input and before `_check_rules`. A mod may override the player's controls here (throttle cap, guns off) before the plane's own physics step runs | not called |
| H2 | `mission_outcome(world, stock: String) -> String` | end of `_check_rules`. `stock` is what the original rules decided this step: `""` (continue), `"won"`, `"death"`, `"time"`, `"defence"`. The mod returns the final result; `"won"` is a win, any other non-empty string a loss (a mod may use its own names, e.g. `"epilogue"`) | stock result used |
| H3 | `end_message(world, result) -> Variant` | `_start_end_fade` / standalone print. A String replaces the fade line (`""` = no line); `null` keeps the stock line | stock strings.ini line |
| H4 | `result_page(world, result, campaign: bool) -> String` | `Game._on_finished`, asked through `World.result_page(result)` before the world is freed. Non-empty = page opened instead of victory / promotion / defeat; campaign bookkeeping still runs | stock pages |
| H5 | `World.secure_progress()` method + `progress_secured` signal | a mod calls it when a flight has earned its campaign credit before it ends (mission 12). `Game` applies the win bookkeeping (next mission, score, rank) at once and does not apply it twice | never emitted |
| H6 | `World.show_message(text, seconds)` | small public helper around `message_label` + timer (already done inline in three places) | n/a (new helper, existing code untouched) |
| H7 | Campaign manifests | `ModLauncher.campaigns()` lists `res://mods/*/campaign.ini`; `Game` reads them (see Campaign wiring) | no manifests = only the stock campaign |

Backward compatibility: H1–H4 are guarded `has_method` calls; H5/H6 are new members nobody else uses; H7
returns an empty list when no manifest exists, and the stock campaign's code path keeps its constants.
The existing `[mod] init` key and Britain's hooks are not touched.

No hook is needed for fog/sky (existing `setup_map`), HUD overlays (the mod adds its own `CanvasLayer`:
kill counter, wound dim/blur, Brenner marker), goal replacement, reveal/hide or forced damage (Aircraft
members). These live in the mod's script API.

## Mod layout

| What | Path |
| --- | --- |
| Entry | `redace/mods/redbaron/init.gd`: existing hooks + H1–H4; loads `missions/mNN.gd` for the flown mission |
| Script API | `redace/mods/redbaron/mission_script.gd` (base of `missions/m01.gd` … `m12.gd`): timers, `near(a, b, d)`, `set_goals(plane, goals)`, `reveal(plane, pos)`, `hide(plane)`, `damage(plane, amount)`, `attack(plane, target)`, `message(text, s)`, `win()`, `lose(result)`, `result_page`, fog/sky |
| Aircraft | `redace/mods/redbaron/aircraft.gd`: `Aircraft` subclass with defensive gunners for `re8`, `handleypage`, `aircodh2`, `halberstadt` |
| Overlay | `redace/mods/redbaron/overlay.gd`: wound dim/blur, kill counter |
| Campaign manifest | `redace/mods/redbaron/campaign.ini` |
| Missions | `redace/game_data/missions/101` … `112/mission.ini`; briefings `redace/game_data/language/english/missions/101` … `112/mission.html` (same split as Britain's 26) |
| Campaign pages | `redace/game_data/language/english/campaigns/redbaron/` (intro, letter, epilogue, completion) |
| Planes, ground | `redace/game_data/objects/planes/{albatros_player,albatros_red,albatros_brenner,fokker_red,fokker_brenner,fokker_rookie,re8,handleypage}/`, `.../objects/ground/balloon/` |
| Dawn / dusk skies | `redace/mods/redbaron/skies/{dawn,dusk}/sky_*.png` (generated from the trenches / country skies) |
| Sources, credits | `overrides/redbaron/` (+ `CREDITS.md`, `README.md` for references) |
| Build | `redace/mods/redbaron/tools/build_redbaron.py` (+ Blender scripts beside it, calling `tools/run_blender_mcp.py` by path) |
| Tests | `redace/mods/redbaron/tests/test_redbaron.gd`, `redace/mods/redbaron/tools/test_redbaron_assets.py` |
| Notes | `redace/mods/redbaron/README.md`, `docs/` |

Game data under `game_data/` follows Britain's precedent (missions, briefings and objects must be where
`Ini.data_path` finds them). Export: `include_filter` already packs `game_data/*.ini|*.html`; add
`mods/*/campaign.ini` to it and `*.md, *.blend, *.blend1, mods/*/docs/*, mods/*/tools/*, mods/*/tests/*`
to `exclude_filter` in all four presets (`.md` is not a resource today, so this only guards the future).

## Mission ids

`ModLauncher.mission_sequence` takes every integer folder in `game_data/missions/` whose ini has `[mod]`;
`Game` and `World` use the id only in paths (`missions\%d\...`, `play:%d`); the stock campaign is capped by
`LAST_MISSION = 25` and the replay selector lists 1..25. **Ids 101–112** (mission N = 100 + N) cannot
collide with stock (−3…25), Britain (26) or later bonus missions, and keep the debug `N` key order.

## Campaign wiring (Phase 7, outline)

- `campaign.ini`: `id = redbaron`, title, mission list `101..112`, ranks `Leutnant, Oberleutnant,
  Rittmeister` (short `Lt., Oblt., Rittm.`), promotion scores, intro / completion page paths, and the
  pages that replace victory pages (mission 11 letter, mission 12 epilogue come from H4 instead).
- `Game` gets a "campaign definition" (`missions`, `ranks`, `promotion`, `last`, pages): the stock one built
  from today's constants, mod ones from manifests. Functions that use `LAST_MISSION`, `RANKS`,
  `PROMOTION_SCORE` read the active definition; stock flow unchanged (checked by `test_replay_menu` and a
  new stock-campaign test).
- Pilot progress per campaign: `pilot.campaigns = {"redbaron": {mission, score, rank}}`. Stock fields
  (`mission`, `score`, `rank`, ...) are never written by a mod campaign. Extra key is ignored by older
  builds and kept by `_save`.
- Menu: Goodies → Bonus Missions. `bonus.html` (already a remake-only page) gets a `^bonuscampaigns^`
  placeholder filled from the manifests (`campaign:<id>` links), next to the existing Battle of Britain
  link. `campaign:<id>` opens the manifest's intro page with Start / Continue for the current pilot.
- Briefing `^rank^` uses the active campaign's rank list.
- Promotions: history has Oberleutnant on 22 Mar and Rittmeister on 6 Apr 1917, i.e. after missions 2 and
  3. A win scores at least 500, so thresholds **1000 and 1500** promote exactly there; the letter (11)
  is signed Rittmeister, consistent with that.

## Where the design's INI cannot run as written

| Mission | Design | Engine behaviour | Plan |
| --- | --- | --- | --- |
| all with hidden planes | `requireshotdown = 1` fixes hidden planes counting as lost | key does not change the rules | keep the key (harmless, documents intent); the fix is the mod's `counts_as_lost` |
| 2, 6, 7, 11 | reveal goals `368 → 288/352 → 112` | after 0x120/0x160 the plane reappears **parked where it was placed** (state ground). Every stock reinforcement is `368, 288/352, 256, ...` | insert `type = 256` (with the spawn `pos`) after each reveal goal |
| 5, 8 | escorts `48` (formation) then `304` | 0x30 never finishes while the leader lives, so later goals never run | put `304` before `48` |
| 1, 5 | escaping plane in group 4 | correct; it hides after flying 150 past the map edge and the `timelimit` fails the mission (player waits until the clock runs out) | as designed; optional script can end early with "The plates got through" (mission 5 has a fail line in the design) |
| 4, 9, 10, 3 | `Group9 = -100` etc. with dead-only `counts_as_lost` | Britain's dead-only rule would let a **group 9 raider that flies off the map** block a destroy-all mission forever (stock counts it as lost, 0x439046) | mod rule: lost = dead, or group 9 and `left_map`. Hidden-not-yet-revealed planes are never lost; a group 8 rookie that leaves the map (mission 12) is saved |
| 12 | "rookie crossing the German edge counts as saved" | AI planes 150 past the map box are hidden for good (`left_map`) | follows from the rule above; the script counts crossings via `left_map` and waypoints point at the German side |
| 1–12 | `pos` values | taken from the template mission on the same map | country: stock 1–10; trenches: stock 21–25 (German side = the stock enemy side) |
| 8 | "F.E.2d stand-in with rear gunners" | stock AI never fires outside 0x70/0x80/0x90 | mod aircraft subclass (gunners) |
| 6 | dawn fog and sky | map fog only | `setup_map` override from the mission's own `[environment]` keys (mod-read, optional) |
| 9 | dusk | terrain is unlit (texture × baked colour), so fog + sky alone may look like day with an orange haze | try fog + sky + ambient first; if it is not enough, propose a generic optional terrain tint (would need your OK, Phase 3) |
| 12 | "on the player's death skip Plane Destroyed" | `_check_rules` ends the flight the step the player dies | H2 returns `"epilogue"`, H3 returns `""`, H4 opens the epilogue page |

## Phase sequence (as the prompt, with checks)

0. Britain notes moved (done, `1ff6844`), this plan. **Stop for review.**
1. Hooks H1–H6 + launcher docs; mod skeleton (`init.gd`, script API, test mission `game_data/missions/199`
   used only by tests, not in the campaign) and `tests/test_redbaron.gd` proving every API call headless.
2. Missions 102 and 108 with `albertross` stand-ins; headless tests (rejoin, aerodrome win, wound on observer
   hit, land = win, crash = lose). **Stop for feel check.**
3. Plane folders + paint, dawn / dusk.
4. Missions 101, 103, 104, 105, 106, 110 (placeholder `aircodh2` for `re8`, a ground object for `balloon`).
5. `re8`, `balloon`, `handleypage` in Blender (MCP on 9876 or `blender --background`).
6. Missions 107, 109, 111, 112, letter and epilogue.
7. Campaign manifest, menus, ranks, builds.

## Decisions (user, 2026-11-05)

1. Gunners: shared helper `redace/mods/shared/defensive_gunners.gd`, and Britain switched to it too.
2. Epilogue: black page, text only.
3. Promotions: Oberleutnant after mission 2, Rittmeister after mission 3 (thresholds 1000 / 1500).
4. `bonus.html` gets a `^bonuscampaigns^` placeholder.
5. `counts_as_lost`: dead, or group 9 that left the map.
