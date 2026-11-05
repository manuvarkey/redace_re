# Der Rote Kampfflieger (Red Baron campaign mod)

A 12-mission campaign flown as Manfred von Richthofen, November 1916 to April 1918, on the
country and trenches maps. Work in progress; see `docs/IMPLEMENTATION_PLAN.md` for the phases and
`docs/red_baron_mod_design.md` for the design.

## Play

Not yet in the menus (Phase 7 adds the campaign under Goodies → Bonus Missions). Debug launch:
`godot --path redace -- --mission=<id>` with ids 101–112 (mission N = 100 + N) as they are added.

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
