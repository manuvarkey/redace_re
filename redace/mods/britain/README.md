# Battle of Britain bonus mission

Open **Game menu → Goodies → Bonus Missions → Battle of Britain**, or launch with
`--mission=26`. Fly a Spitfire alongside three squadron mates over a new coastal
map. Destroy three raids of Bf 109 fighters and He 111 bombers while keeping the
aircraft factory intact. The raids arrive at 12, 97 and 182 seconds; future raids
remain part of the victory objective while hidden. Factory destruction loses the
mission, including when the final enemy is destroyed at the same time.

## What it contains

The detailed aircraft and port buildings were authored through Blender MCP, with
camouflage, panel seams, brick and slate textures. The Dover-inspired landscape
has coastal hills, an irregular shoreline, and 49.5% water. Britain-only runtime
scripts add translucent waves, clouds, sea-crash debris, bomber circuits, escort
formations, defensive gunners, and staged damage. AA batteries defend the port,
with five freighters and sixteen fishing boats offshore. Aircraft match the
original game's screen scale; bombers use a distinct radar icon.

References, asset sources and tuning values are in
[`overrides/britain/README.md`](../../../overrides/britain/README.md).

## Files

| What | Path |
| --- | --- |
| Runtime scripts | `redace/mods/britain/` (`init.gd`, `aircraft.gd`, `environment.gd`) |
| Mission | `redace/game_data/missions/26/mission.ini`, briefing `redace/game_data/language/english/missions/26/mission.html` |
| Menu entry | `redace/game_data/language/english/menus/bonus.html` |
| Source art and Blender file | `overrides/britain/` |
| Build scripts | `tools/build_britain.py`, `tools/blender_britain.py`, `tools/britain_textures.py`, `tools/britain_landscape.py`, `tools/configure_britain.py` |
| Tests | `redace/tools/test_britain.gd`, `redace/tools/test_britain_aircraft.gd`, `tools/test_britain_assets.py` |

## Rebuild and test

Rebuild with `python3 tools/build_britain.py` (Pillow, NumPy, and a running Blender
MCP addon). Validate the mission with Godot:
`godot --headless --path redace -s tools/test_britain.gd`.
