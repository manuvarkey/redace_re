# Red Baron mod: implementation notes

Running log of deviations from `red_baron_mod_design.md` and tuning values, so the design can be
updated afterwards. Newest phase last.

## Phase 1: hooks and mission script API

Engine (generic, documented in `mods/launcher.gd`):
- `World`: `mission_step` and `mission_outcome` mod hooks; `end_message` (via `_mod_end_message`);
  `result_page(result, campaign)`; `secure_progress()` + `progress_secured` signal +
  `progress_was_secured`; `show_message(text, seconds)`. `_check_rules` now calls `_rules_result()`,
  which returns the original decision unchanged.
- `Game`: asks `world.result_page` before freeing the world; applies `progress_secured` at once
  (`_on_progress_secured`) so a later loss keeps the credit and a later win does not count twice.
  Phase 7 generalises this bookkeeping to mod campaigns.
- Export presets: exclude `*.md`, `*.blend*`, `mods/*/docs|tools|tests/*` and the test fixture
  mission 199; include `mods/*/campaign.ini` (for Phase 7).
- Gunners: `redace/mods/shared/defensive_gunners.gd` (Britain's algorithm, moved); Britain's He 111
  calls it (its tests unchanged and passing).

Mod:
- `init.gd`: optional mission keys `[mod] script`, `[environment] fogcolour / sky / ambient`,
  `[airN] gunners`. `counts_as_lost` = dead, or group 9 that left the map.
- `mission_script.gd`: script API (timers, distances, goals, reveal/hide, damage, attack, formation,
  messages, fog/sky, win/lose, result pages, end lines, secure_progress).
- `aircraft.gd`: gunners on `re8`, `handleypage`, `halberstadt` by default (`aircodh2` only with
  `gunners = 1`, as the DH.2 is a single-seater in mission 1); `damaged` signal for scripts.

Deviations / facts found:
- A mod node's `script` member clashes with `Object.script`; the init's member is `mission_script`.
- After `reveal` the plane can be in the stall state for a moment (the 0x100 appear goal keeps the nose
  at 0.196 up, as the exe); tests accept FLYING or STALL.
- Test fixture mission 199 lives in `game_data/missions/199` (World only loads missions from there).
  It has `[mod]`, so the debug `N` key cycles through it in editor runs; exports leave it out.
