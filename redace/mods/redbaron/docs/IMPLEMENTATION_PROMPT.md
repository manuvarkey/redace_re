# Implement the "Der Rote Kampfflieger" Red Baron mod for redace_re

You are implementing a 12-mission campaign mod for **redace_re**, a Godot 4.7 remake of *Master of the Skies: The Red Ace* (repo root = current directory). The full design is in `redace/mods/redbaron/docs/red_baron_mod_design.md`. **Read it completely before writing code.** It is the source of truth for story, missions, aircraft, stats, objectives, INI setups and historical constraints. If this prompt and the design disagree, the design wins; if the design is wrong about how the engine works, follow the engine and record the deviation (see "Reporting").

## Ground rules

1. **Stock game must not change.** The original 25 campaign missions, demos, replay levels and the Britain bonus mission (26) must play exactly as before. Engine changes go behind optional mod hooks that are inert unless a mission's mod uses them. Run `godot --headless --path redace -s tools/audit_missions.gd` and the existing `tools/test_*.gd` suites before your first change and after every phase; results must match the baseline.
2. **Follow the Britain mission's pattern.** It is the reference for everything this mod needs. Study these before designing anything:
   - `redace/mods/launcher.gd`: a mission opts in with `[mod] init = res://mods/<name>/init.gd`. `mission_sequence()` already appends mod missions.
   - `redace/mods/britain/init.gd`: hook methods (`setup_map`, `create_aircraft`, `configure_aircraft`, `counts_as_lost`, `is_sea`, `sea_crash`, `camera_distance_scale`), and where `scripts/main.gd` calls them (search `_mod`).
   - `redace/mods/britain/aircraft.gd`: an `Aircraft` subclass with defensive gunners, escorts, bomber circuits and damage stages. Reuse or generalise its gunner code rather than rewriting it.
   - `overrides/britain/`, `tools/build_britain.py`, `tools/blender_britain.py`, `tools/run_blender_mcp.py`, `tools/test_britain.gd`, `tools/test_britain_assets.py`: the asset pipeline and tests.
   - README "Technical notes": goal types, group bitmask rules, mission rules (`_count_rule_members`, `_check_rules` in `scripts/main.gd`), easing, scoring, end-of-flight flow.
3. **Hidden planes.** In stock rules a hidden plane counts as lost, which can win a mission before its ambush appears. The `requireshotdown = 1` key the design uses does nothing by itself for this: the Britain mod's `counts_as_lost` hook (dead only) is what fixes it. The Red Baron mod's `init.gd` must implement the same, plus the design's rule that a rookie crossing the German map edge in mission 12 counts as saved.
4. **Generic, backward-compatible engine hooks only.** If the existing hooks cannot express a feature (per-frame mission script, script-owned win/lose, custom end pages, HUD messages, wound effect, fog/sky override, a mod campaign entry), add the smallest new hook to the launcher or core scripts (`scripts/main.gd`, `hud.gd`, `game.gd`). Every hook is generic: named for what it does, never for the Red Baron mod, usable by any future mod, and documented in the launcher. Every hook is optional: called only when the mod defines it (`_mod.has_method(...)`), with the stock behaviour as the default. The existing `[mod] init = …` declaration and the Britain mod's hooks keep working unchanged, and Britain needs no edits to keep running. Any new `mission.ini` keys are optional with stock defaults. No core script may mention `redbaron` or test for this mod by name. Keep the codebase's decompiled-behaviour comment style.
5. **Keep the mod contained, like Battle of Britain.** Everything Red Baron lives in mod-owned paths (Layout table): its code, missions, plane and ground folders, source art, build and test scripts, credits and notes. Shared files get only the generic hooks of rule 4, plus at most a short pointer in the main `README.md`. Where Britain's own layout forces a shared location (e.g. game data under `game_data/`), follow Britain's precedent and record it. Keep the mod's notes out of the export: check the export presets' filters so `.md`, `.blend` and source art are not packed into `redace.pck`.
6. **Work in phases, commit per phase**, with a short message naming the phase. Do not start a phase until the previous one passes its checks.
7. **Ask before**: changing shared engine behaviour beyond an opt-in hook; deleting or rewriting existing files (other than the Britain notes move in Phase 0); downloading any asset whose licence is unclear; renumbering or moving existing missions.

## Layout

Use these paths unless the codebase gives a reason not to (record any change):

| What | Path |
| --- | --- |
| Mod code | `redace/mods/redbaron/` (`init.gd`, `aircraft.gd`, `missions/m01.gd` … `m12.gd` mission scripts) |
| Mod notes | `redace/mods/redbaron/docs/`: this prompt, the design doc, `IMPLEMENTATION_PLAN.md`, `IMPLEMENTATION_NOTES.md`; `redace/mods/redbaron/README.md` for how to play, rebuild and test |
| Missions | `redace/game_data/missions/<id>/mission.ini` + `mission.html` briefing. Choose an id range that cannot collide (e.g. 101–112) after reading how ids are parsed and listed |
| Planes | `redace/game_data/objects/planes/<folder>/` for the folders in the design (`albatros_player`, `albatros_red`, `albatros_brenner`, `fokker_red`, `fokker_brenner`, `fokker_rookie`, `re8`, `handleypage`) |
| Ground objects | `.../objects/ground/balloon/` |
| Source art and Blender files | `overrides/redbaron/` (mirrors `game_data/` paths, like `overrides/britain/`) |
| Build script | `redace/mods/redbaron/tools/build_redbaron.py` (reusing shared helpers such as `tools/run_blender_mcp.py` by path; put it in `tools/` only if the build cannot run from there, and record why) |
| Tests | `redace/mods/redbaron/tests/test_redbaron.gd`, run as `godot --headless --path redace -s res://mods/redbaron/tests/test_redbaron.gd` (+ an assets test beside the build script) |
| Credits | `overrides/redbaron/CREDITS.md` |

## Phases

### Phase 0: Study, separate the Britain notes, plan
**Britain notes.** Britain's notes are currently split: references and tuning in `overrides/britain/README.md`, but a full "Battle of Britain bonus mission" section (how to play, what it contains, rebuild and test commands) in the main `README.md`. Move that section's content, unchanged in substance, into a Britain README in Britain's mod directory (`redace/mods/britain/README.md`, linking to `overrides/britain/README.md` for references), and leave a two- or three-line pointer in the main README. Check `docs/` and other shared notes for further Britain-only material and treat it the same way; core engine notes that merely mention Britain (e.g. `docs/collision-parity.md`) stay where they are. Text only, no behaviour change, its own commit. The Red Baron mod then follows the same structure.

**Plan.** Read the design doc, README technical notes, `main.gd` (mission load, rules, end of flight), `aircraft.gd` (goals, AI, damage), `game.gd` (menus, campaign, pilots, pages), `hud.gd`, the launcher and the Britain mod. Then write `redace/mods/redbaron/docs/IMPLEMENTATION_PLAN.md`: the generic hook list you will add (with how each stays backward compatible), the mission id range, how the campaign will be wired (separate pilot progress so it never overwrites the original campaign), and any place where the design's INI cannot work as written. Stop and show me the plan.

### Phase 1: Mod skeleton and script hook
- `mods/redbaron/init.gd` implementing the existing hooks (`counts_as_lost` dead-only with the mission 12 exception).
- A per-mission script API used by `missions/mNN.gd`: timers; distance checks; replace a plane's goal list; reveal/hide planes; set or add damage; retarget AI; HUD message; per-mission fog colour and sky box; script-owned win/lose that overrides the stock "all enemies destroyed" win; choose the result page.
- Tests: a minimal test mission proves each API call works headless.

### Phase 2: Prototype missions 2 and 8 (stock models, placeholder paint)
These test the core story loop: rescuing Brenner, and later relying on him. Build them fully per the design (objectives, scripts, briefings) using existing models (`albertross` as a stand-in for the new player folders if Phase 3 isn't done). Add headless tests that drive the scripts with `--autopilot` or direct calls: Brenner rejoins on proximity; the win needs both near the aerodrome; the wound triggers on an observer hit; landing wins and crashing loses. Stop and tell me how to play them (`--mission=<id>`), so I can check the feel before you continue.

### Phase 3: Player planes and environment
- Plane folders with the tuned `plane.ini` values from the design's stats table; copy models from `albertross` and `fokkertriplane`.
- Paint schemes from the design: the Baron all red, Brenner red with a white tail band, rookies with accent colours, `albatros_player` in factory finish. Wings may keep camouflage. Repaint by editing copies of the existing textures (keep the 4x upscale pipeline and `tools/match_texture_means.py` in mind).
- Per-mission dawn and dusk fog and sky (missions 6 and 9).

### Phase 4: Stock-rule missions 1, 3, 4, 5, 6, 10
Build from the design's INI setups. Base each on an existing mission on the same map (`country` or `trenches`) so ground positions sit on the terrain. Use placeholder models where a new model isn't built yet (an existing two-seater or `aircodh2` for `re8`, a ground object for `balloon`), behind a clearly named folder so Phase 5 only swaps assets.

### Phase 5: New models with Blender
Models: RE8 two-seater, observation balloon (British Caquot type), Handley Page O/100 bomber.
- Use the local Blender MCP addon via `tools/run_blender_mcp.py` (port 9876), as `tools/blender_britain.py` does. If it isn't reachable, run the same scripts with `blender --background --python`.
- Match the game's art: low poly like the stock planes (check triangle counts of `albertross` and `sopwithcamel`), the stock texture size and style, the same scale as existing planes (compare with `sopwithcamel` and `he111`), propellers using the `soppropeller` texture convention so they spin, a `shadow` clump, and damage stages where the Britain models have them.
- Export to the format the build pipeline expects (glTF, as the overrides use) with the `plane.ini` fields the engine reads.
- **Downloaded assets:** only CC0 or CC-BY (or equivalent) textures and references; record every source, author and licence in `overrides/redbaron/CREDITS.md`. No ripped game assets. Reference photos of the real aircraft are fine for modelling but are not shipped.
- Defensive gunners on `re8`, `handleypage` and the `aircodh2` F.E.2d stand-in (reuse the Britain gunner code).

### Phase 6: Missions 7, 9, 11, 12 and the end flow
- Mission 11's script sequence and letter debrief page (in place of promotion), exactly as the design describes. The player must never be able to reach Brenner in time without abandoning the two-seater.
- Mission 12's three phases: escort (all four rookies; campaign completion saved on the fourth crossing), stop the pursuit (6 Camels, HUD kill counter), the ridge (waves every 40 s, ridge guns, scripted ground-fire burst after 4 minutes). On the player's death, skip "Plane Destroyed" and the defeat page; fade out and show the epilogue page.
- Epilogue page text verbatim from the design, black page, no kill tally, no slogan.

### Phase 7: Campaign wiring and polish
- A Red Baron campaign entry in the menus (see how Goodies → Bonus Missions lists mission 26). Drive it from a generic mechanism, e.g. a campaign manifest in the mod folder that the launcher discovers, so any future mod can add a campaign the same way; no hard-coded Red Baron menu entries in core pages or scripts. Separate pilot progress, ranks Leutnant → Rittmeister, missions in order, briefings in the game's HTML page format (`missions/<id>/mission.html`), with briefing text from the design.
- All in-game text says "Central Powers" or "German Air Service", never "Axis".
- Web, Linux, Windows and Android builds still succeed (`./build.sh`).

## Verification (every phase)

- `tools/audit_missions.gd` clean for the new missions; stock results unchanged.
- Britain mission 26 and its tests (`tools/test_britain.gd`, `tools/test_britain_aircraft.gd`) pass unchanged, proving the launcher changes are backward compatible.
- `grep -ri redbaron redace/scripts redace/mods/launcher.gd` finds nothing.
- `tools/test_redbaron.gd`, per mission: loads; groups and rules as designed; hidden planes do not count as lost; win and lose paths reachable by script; mission 12 saves completion before the death sequence.
- Screenshots of each mission start, via `--mission=<id> --view=N`, plus each new model next to a stock plane for scale. Look at them before claiming a phase is done.
- Difficulty targets from the design's campaign table (1–5) are for playtesting. Note anything that looks clearly off (e.g. the player can't catch Hawker, or bombers take more than about 60 s each to bring down), but tune only after my playtest.

## Reporting

At the end of each phase, report briefly: what was built, test results, deviations from the design (and why), open questions. Keep a running `redace/mods/redbaron/docs/IMPLEMENTATION_NOTES.md` with deviations and tuning values, so the design doc can be updated afterwards.
