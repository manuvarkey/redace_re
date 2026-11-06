# Der Rote Kampfflieger (Red Baron campaign mod)

A 12-mission campaign flown as Manfred von Richthofen, November 1916 to April 1918, on the
country and trenches maps, for the Central Powers. Current state, changes from the design and open items:
`docs/IMPLEMENTATION_NOTES.md` (see [Docs](#docs)).

## Play

Main menu → Goodies → Bonus Missions → **Der Rote Kampfflieger**: Start / Continue Campaign with the current
pilot (choose one in the roster first), or **Replay Missions** to fly any mission on its own. Progress is
saved per pilot, apart from the original campaign; ranks Leutnant, Oberleutnant (after mission 2) and
Rittmeister (after mission 3). Debug launch without progress: `godot --path redace -- --mission=<id>`
(mission N = id 100 + N).

| # | Mission | Map | You fly, with |
| --- | --- | --- | --- |
| 1 | Hawker | trenches | Albatros D.II |
| 2 | First Sortie | country | red Albatros, Brenner with you |
| 3 | Bloody April | trenches | red Albatros |
| 4 | Scramble | country | red Albatros, from the field; Brenner and a wingman already up |
| 5 | The Plates | trenches | red Albatros |
| 6 | Balloon Busting | trenches, dawn | red Albatros; three Halberstadts bomb the AA guns |
| 7 | The Other Side | trenches | red Albatros, escorting a Halberstadt photo plane |
| 8 | Wounded | country | red Albatros, Brenner with you |
| 9 | Dusk Raiders | country, dusk | red Albatros, Brenner and a wingman |
| 10 | Cambrai | trenches | Fokker Dr.I, Brenner and a rookie |
| 11 | Formation | trenches | Fokker Dr.I, Brenner and a rookie; a damaged Halberstadt to bring home |
| 12 | The Last Patrol | trenches | Fokker Dr.I, four rookies to get home |

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

Briefing and campaign pictures: save the PNGs listed in `docs/images_required.md` into
`redace/game_data/language/english/campaigns/redbaron/img/`, then run `build_missions.py` and the import.
Until a picture exists its page shows without it.

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

## Test

```sh
godot --headless --path redace -s res://mods/redbaron/tests/test_redbaron.gd
python3 redace/mods/redbaron/tools/test_redbaron_assets.py
MS=101,102,103,104,105,106,107,108,109,110,111,112,199 godot --headless --path redace -s tools/audit_missions.gd
```

## Docs

None of these ship: exports leave out `*.md` and `mods/*/docs/*`.

| File | What | Status |
| --- | --- | --- |
| `docs/IMPLEMENTATION_NOTES.md` | Development log: hooks added, every change from the design, playtests, open items (at the end) | **Current.** Read first; it wins where the design disagrees |
| `docs/red_baron_mod_design.md` | Original design: story, missions, planes, ranks, intended mission INI | Reference; out of date where the notes record a change |
| `docs/images_required.md` | Included campaign art: paths, sizes, prompts in the original menu-art style | All 14 included; generation record in `docs/art_generation.md` |
| `docs/history/IMPLEMENTATION_PROMPT.md` | Task brief the mod was built from | Done; its ground rules still apply to new work (stock game unchanged, generic opt-in engine hooks, no `redbaron` in core scripts, commit per step) |
| `docs/history/IMPLEMENTATION_PLAN.md` | Phase 0 plan: test baseline, hook plan, design INI problems | Done; kept for the baseline and the reasons behind the hooks |
