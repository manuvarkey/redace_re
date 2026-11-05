# Der Rote Kampfflieger (Red Baron campaign mod)

A 12-mission campaign flown as Manfred von Richthofen, November 1916 to April 1918, on the
country and trenches maps. Work in progress; see `docs/IMPLEMENTATION_PLAN.md` for the phases and
`docs/red_baron_mod_design.md` for the design.

## Play

Main menu → Goodies → Bonus Missions → **Der Rote Kampfflieger**, then Start / Continue Campaign with the
current pilot (choose one in the roster first). Progress is saved per pilot, apart from the original
campaign. Built so far: 102 (First Sortie), 108 (Wounded); `campaign.ini` lists the playable missions.
Debug launch without progress: `godot --path redace -- --mission=<id>` (mission N = id 100 + N).

## Rebuild missions

Mission files are generated: edit `tools/missions/mNN.ini` / `mNN.html`, then
`python3 redace/mods/redbaron/tools/build_missions.py [NN ...]`.

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
MS=199 godot --headless --path redace -s tools/audit_missions.gd
```
