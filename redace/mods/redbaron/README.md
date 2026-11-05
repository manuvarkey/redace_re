# Der Rote Kampfflieger (Red Baron campaign mod)

A 12-mission campaign flown as Manfred von Richthofen, November 1916 to April 1918, on the
country and trenches maps, for the Central Powers. Design: `docs/red_baron_mod_design.md`; how it was
built and where it departs from the design: `docs/IMPLEMENTATION_NOTES.md`.

## Play

Main menu → Goodies → Bonus Missions → **Der Rote Kampfflieger**: Start / Continue Campaign with the current
pilot (choose one in the roster first), or **Replay Missions** to fly any mission on its own. Progress is
saved per pilot, apart from the original campaign; ranks Leutnant, Oberleutnant (after mission 2) and
Rittmeister (after mission 3). Debug launch without progress: `godot --path redace -- --mission=<id>`
(mission N = id 100 + N).

| # | Mission | Map | You fly |
| --- | --- | --- | --- |
| 1 | Hawker | trenches | Albatros D.II |
| 2 | First Sortie | country | red Albatros (Brenner with you) |
| 3 | Bloody April | trenches | red Albatros |
| 4 | Scramble | country | red Albatros, from the field |
| 5 | The Plates | trenches | red Albatros |
| 6 | Balloon Busting | trenches, dawn | red Albatros |
| 7 | The Other Side | trenches | red Albatros |
| 8 | Wounded | country | red Albatros |
| 9 | Dusk Raiders | country, dusk | red Albatros |
| 10 | Cambrai | trenches | Fokker Dr.I |
| 11 | Formation | trenches | Fokker Dr.I |
| 12 | The Last Patrol | trenches | Fokker Dr.I |

`campaign.ini` has `replayall = 1` (every mission in Replay Missions) while the campaign is tested; set 0 for
a release (then only missions the pilot has reached, all once the campaign is complete).

## Rebuild

```sh
python3 redace/mods/redbaron/tools/redbaron_textures.py             # procedural fabric / wicker textures
blender --background --factory-startup --python redace/mods/redbaron/tools/blender_redbaron.py  # RE8, O/100, balloon
python3 redace/mods/redbaron/tools/paint_planes.py                  # Albatros / Dr.I paint
python3 redace/mods/redbaron/tools/build_planes.py                  # plane and ground folders into game_data
python3 redace/mods/redbaron/tools/make_skies.py                    # dawn sky
python3 redace/mods/redbaron/tools/build_missions.py                # missions + briefings, debriefings, failure pages
godot --headless --path redace --import
```

Missions are generated from `tools/missions/mNN.ini` (+ `mNN.html` briefing, `mNN_debrief.html`,
`mNN_failed_<result>.html`); do not edit `game_data/missions/1NN` by hand.

## Files

| What | Path |
| --- | --- |
| Entry, hooks | `redace/mods/redbaron/init.gd` |
| Mission script API | `redace/mods/redbaron/mission_script.gd`; scripts in `missions/mNN.gd` |
| Aircraft (gunners) | `redace/mods/redbaron/aircraft.gd`, shared `redace/mods/shared/defensive_gunners.gd` |
| Missions | `redace/game_data/missions/101..112/`, briefings `redace/game_data/language/english/missions/101..112/` |
| Tests | `redace/mods/redbaron/tests/` (fixture mission `game_data/missions/199`) |
| Notes | `docs/` |

## Test

```sh
godot --headless --path redace -s res://mods/redbaron/tests/test_redbaron.gd
python3 redace/mods/redbaron/tools/test_redbaron_assets.py
MS=101,102,103,104,105,106,107,108,109,110,111,112,199 godot --headless --path redace -s tools/audit_missions.gd
```
