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

## Phase 2: prototype missions 2 (id 102) and 8 (id 108)

Built by `tools/build_missions.py` from `tools/missions/m02.ini`, `m08.ini` (+ `.html` briefing bodies)
with the scenery of stock mission 6 (country). Mod object ids start at 3001.

Map facts (country): world box x 4679..9358, z 4684..9368. The stock German aerodrome (where the stock
missions park enemy Albatros, hangars at x 6047, z 7414..7478) is the mod's aerodrome, centre
(6200, 7450); the British side is east (stock Allied starts at x 7400..8800).

Mission 2:
- Stand-ins: the Baron and Brenner fly `albertross` with mission overrides `highspeed = 110`,
  `endurance = 125` / `80` until Phase 3's folders exist.
- Decoy Bristol Scout trails low east over five British AA guns (x 8200..8550, z 7500..8000); two
  Nieuports appear (0x120) when Brenner is within 500 of (8000, 7700) and attack him. Reveal goals
  are followed by `type = 256` (see the plan).
- Rejoin arms when Brenner is more than 300 from the Baron or after 20 s, so the start (70 apart)
  does not count; then within 150 = formation on the Baron + "Brenner rejoins".
- Win: rejoined, and both within 300 (flat) of the aerodrome. The start is within 300 of the
  aerodrome, so the win can only come after the rejoin.
- Brenner lost: stock Group2 = 100 ("Mission Critical Object Destroyed" line).

Mission 8:
- Four `aircodh2` F.E.2d stand-ins with `gunners = 1`, `gunnerrate = 2.5` (half Britain's rate:
  at 5 rounds/s four observers took a hovering player from 125 to 15 in 10 s), retaliate on, one
  waypoint west over the German side. Design had no waypoint; added so they cross "our lines".
- Brenner: `304` before `48` (formation never ends).
- Wound: first F.E.2d hit after 30 s within 150. **Fallback (not in the design):** if all four fall
  before any qualifying hit, the wound comes with the last one, so the mission can still be finished.
  Effect: overlay (blur, grey, darker edges, slow pulse), throttle held at 0.5, guns and bombs off.
  First try at full strength made the ground unreadable; toned down (blur 0.5 + 1.5 px steps).
- After the wound the Nieuport is revealed 450 behind and 60 above the Baron, attacking him; Brenner
  attacks F.E.2ds within 800 of the Baron (re-checked every 2 s), else holds formation.
- Win: on the ground within 300 (flat) of the aerodrome. A landing elsewhere does not end the
  mission; the Baron can take off again at half throttle. Crash: stock "Plane Destroyed".
- Headless autopilot runs are not representative (the autopilot never attacks); the F.E.2ds'
  retaliation plus gunners make a passive player lose quickly. Tune after playtest.

## Campaign wiring (Phase 7 core, done early at the user's request)

- Generic: `ModLauncher.campaigns()` reads `res://mods/*/campaign.ini`; `Game` keeps a mod campaign's
  progress in `pilot.campaigns[id] = {won: [mission ids], score, rank}`; the original fields are never
  written by a mod campaign. Progress is by mission id, so missions added to the manifest later (101,
  103..) slot in without moving anyone's progress: the next mission is the first of the list not won.
- `bonus.html` gets `^bonuscampaigns^` (font size 4: size 5 wrapped "Der Rote Kampfflieger" out of the
  button). New placeholders `^campaigntitle^`, `^campaigncontinue^`, `^campaignstatus^`; `^rank^`,
  `^mission^`, `^score^` follow the active campaign. Links `campaign:<id>`. Entering the original
  menus (main, play, roster, goodies, bonus, Intro) leaves the mod campaign.
- Pages: `game_data/language/english/campaigns/redbaron/intro.html`, `complete.html` (the completion
  page is a placeholder until Phase 6's epilogue flow). Content kept between y 70 and 420: in a 16:9
  window the 640x480 page is filled to the width and loses about 60 px top and bottom.
- Manifest lists only the missions built so far (102, 108).
- Briefing GO BACK goes to `campaign:redbaron`.
- Found while testing: stock option tests overwrote the real `user://pilots.cfg` / `settings.cfg`;
  fixed with `Game.save_path` / `Game.settings_path` (commit db1d2f7). The Red Baron test uses the
  same scratch paths.

## Phase 3 (part): tuned Albatros folders

- `albatros_red` (the Baron) and `albatros_brenner`: design stats (highspeed 110, climb 85, highroll 80,
  highpitch 90, accel 10, firerate 25; endurance 125 / 80). Not in the design table, chosen to sit just
  above the Nieuport 17 / S.E.5a: divespeed 116, cruise 105, stall 60, lowroll 65, lowpitch 65.
- Guns: user playtest found the stand-in's fire far too slow (stock albertross 4.4 rounds/s sustained:
  firerate 10, 0.8 s on, 1.0 s off; Nieuport / S.E.5a 20.8). User chose to match the British scouts:
  firerate 25, fireon 1.0, fireoff 0.2 = 20.8 rounds/s. The design gave only firerate 25.
- Sources: `overrides/redbaron/objects/planes/<folder>/plane.ini`; `tools/build_planes.py` copies the
  stock albertross model in (paint comes later), then `godot --import`.

## Difficulty pass after the first playtest (user: "very hard")

- Comparison: original mission 1 gives the player the DH.2 (23.3 rounds/s) against stock Albatroses
  (4.4/s), about 5:1. With the sides swapped the British planes kept their strong guns (20.8..25.7/s)
  against the Baron's 20.8, about 1:1.
- Mod key `[airN] firerate / fireon / fireoff` (init.gd `configure_aircraft`, no engine change).
- Starting values: British scouts and the F.E.2d front gun at 8 rounds/s sustained in missions 1-8
  (Nieuport / S.E.5a firerate 9.6, Bristol Scout 9.33, aircodh2 8.57 with their stock bursts); planned
  12/s for missions 9-12. F.E.2d observers stay at 2.5/s.
- Mission 8: F.E.2ds retaliate off (`320` in place of `304`): they hold course, observers shoot back.
- User: raise the Baron's and Brenner's guns to the original mission 1 player's (aircodh2: firerate 25,
  1.4 s on, 0.1 s off = 23.3 rounds/s); Brenner "gets killed fast": endurance 80 -> 125 (as the Baron)
  in `albatros_brenner` and in missions 2 and 8. Design had 80 for Brenner.

## Playtest 2 (user: "winnable now"; rejoin unclear, no way to find base)

- Generic HUD hook: `World.map_markers` ({pos, icon}), drawn by `Hud._draw_map` with the other icons
  (held at the rim when far), cleared on mission load. Script API `mark_on_map(pos, icon)` / `unmark`.
  Icon `mods/redbaron/aerodrome_icon.png` (8x8 hangar, scaled 8x like the stock icons).
- Missions 2 and 8 mark the aerodrome from the start.
- Mission 2: Brenner "breaks off" when 250 from the Baron or after 10 s (was 300 / 20 s); the HUD then
  says "Brenner breaks off after the Scout! Fly close to him to call him back." Rejoin range 200 (was
  150). Message on rejoin "Brenner joins. Return to base." (user's wording). Briefing says how.
- Mission 8: "You are wounded! Land at the aerodrome." on the wound.

## Replay Missions (user request)

- Generic: manifest keys `replay` (page) and `replayall`; placeholders `^campaignreplay^` (one row per
  mission, named by its briefing's `<title>`) and `^campaignreplaylink^`; `campaigns\...` links open the
  campaign's own pages. Listed: missions won + the next, all once complete, or all with `replayall = 1`.
  A replayed mission flies outside the campaign (no progress), like the original's level selector.
- Path: Goodies → Bonus Missions → Der Rote Kampfflieger → Replay Missions. Page uses the original's
  replay art (`Menus\goodiesreplay.jpg`).
- **`replayall = 1` in `campaign.ini` while the campaign is built and tested; set it to 0 for release.**

## Playtest 3: Brenner never ran away in mission 2

- Cause: he started beside the Baron, both heading east toward the decoy at the same top speed, so he
  flew alongside; at 10 s the rejoin rule fired at once and "Brenner joins" replaced the break-off line.
- Now: the Baron and Brenner start heading north on patrol, Brenner in formation (`48` on the Baron).
  At 6 s the script sends him after the decoy (east, now starting at 7200, 7700) with the HUD line
  "Brenner breaks off after a Scout! Catch him to call him back." Brenner flies `highspeed = 118`
  (the Baron 110) so he really pulls away (about 420 away 4 s after the break with the Baron flying
  straight on). Catching him (within 200) counts once he has been 300 away, or 15 s after the break.

## Playtest 4: story steps could fire together in mission 2; return interception

- Steps now each have a HUD line and at least 4 s between them: break-off (6 s) → "Brenner is over the
  British guns! Get him out of there." when Brenner is within 300 of the Scout or the Scout is down
  (new intermediate step; the 300-away / 15 s rule is gone) → rejoin within 200.
- Not in the design: two more Nieuports (ids 3006, 3007, 8 rounds/s), hidden until the flat distance to
  the aerodrome is half what it was at the rejoin; they appear 500 ahead and 350 to the side, facing
  their targets, one attacking the Baron and one Brenner ("Enemy scouts ahead! Protect Brenner.").
- Script API: `reveal(plane, pos, then, face)` can set the heading.

## Playtest 5: home aerodrome bombed

- Stock mission 6's scenery shows the aerodrome burnt (`bighangerburn` x3, `Factory_burned`). Build key
  `[build] intact = x z r` swaps burnt / wrecked scenery for the standing model within r (bighangerburn
  -> bighanger, hangerburned -> hanger, factory_burned -> factory, tree1_burned -> tree1, housestumps
  -> house1). Missions 2 and 8: `intact = 6200 7450 700` (4 objects restored).

## Playtest 6: mission 8, shot down on the way home after the wound

- Cause: the F.E.2ds' waypoint led west over the aerodrome, so they flew home alongside the wounded
  Baron with their observers firing, and the Nieuport attacked until killed.
- Now, at the wound: the F.E.2ds turn east off the map (retaliate off, waypoint x 9600); the Nieuport
  is revealed 450 behind facing the Baron with `0x130` limit 25 s, attacks, then turns east; Brenner
  holds formation and goes for the Nieuport 12 s after the wound (6 s let him kill it before it ever
  fired). Simulated (wound 1300 from base, Baron flying straight home): the Nieuport closes to about
  140 by the aerodrome while Brenner engages it; no damage taken in that straight run.

## Playtest 7: mission 8 reworked (user's flow)

User asked for: first objective = shoot down the observers (F.E.2ds) before they leave the map; then
"Return to base"; on the way back the Baron is ambushed and takes the hit, so Brenner is beside him to
deal with it; the F.E.2d formation must be well away from the base. **Deviation from the design**, where
the wound came from an observer during the attack pass.

- F.E.2ds start about 3000 north-east of the aerodrome, fly south-west to about 1700 short of it, south
  along our lines (about 1600 out), then east to x 10000. They leave the map (150 past x 9358) at about
  38 s; their waypoint lies beyond that point, or the AI turns back at the edge when the goal is done.
  HUD counter "F.E.2d down n / 4   escaped n".
- When none is left in the air: "Return to base." (or "n got away. Return to base."), Brenner forms up.
- Halfway home (flat distance down to half of that at the return): two Nieuports (3020, 3021) appear
  250 behind and 80 above; the Baron takes a 20-point hit (never the last 10 of his endurance) and is
  wounded ("Ambush! You are hit. Land at the aerodrome."). Brenner attacks the first at once, then forms
  up; the second attacks 25 s (0x130 limit), then flies east.
- Observer hits no longer wound; the "last F.E.2d" fallback is gone.

## Playtest 8: mission 8 timing, rockets, surviving the ambush

- The Baron carries 10 rockets (`ordinancetype = 2`, `numordinance = 10`).
- F.E.2d route lengthened (all 1550+ from the aerodrome): south-west to 1700 short of it, south along
  our lines, a loop south and east, back north, then east. Simulated: they leave the map at about
  89 s, about 75 s after the Baron meets them (the user asked for 60+).
- Ambush survival (simulated with the Baron flying level for home: he was crashing into the ground
  with no input, and with the old values ambushers then shot him down): after the 20-point wound hit he
  keeps at least half his endurance and takes a quarter of each hit (mod `Aircraft.damage_scale`);
  Brenner attacks both Nieuports in turn; the second's attack limit is 20 s. Result over three runs:
  both Nieuports down about 10 s after the ambush, the Baron home with 40..46 of 125.
- Ambushers appear 250 / 310 behind, 120 either side, 80 / 110 above (they spawned on top of each
  other and collided before).

## Playtest 9: success line, minimap edge marker, debriefings

- Mission 8: "The F.E.2d flight is destroyed. Well done! Return to base." (or "3 F.E.2ds down, 1 got
  away. Return to base." / "The F.E.2ds got away. Return to base.").
- Minimap markers (generic `World.map_markers`): drawn after the aircraft icons, at full strength when
  held at the rim (other far icons are half alpha), optional `size` (Red Baron 1.5x). At half alpha on
  the rim, behind Brenner's icon, the aerodrome was hard to see.
- Debriefings (generic): `language/english/missions/<id>/debrief.html` replaces the victory message
  after a win (`^victoryurl^`); `^promotionnote^` names a promotion there, so a mod mission with a
  debriefing shows victory → debriefing instead of the promotion page; after the last mission the
  debriefing's Next Mission leads to the completion page. Original missions have none.
- Debriefing texts for missions 1-11 in `tools/missions/mNN_debrief.html` (11 is the letter from the
  design); the build tool writes them for built missions. Each closes on the next mission's setting.
  Mission 1 notes Hawker as "a brave man and a fine pilot"; nothing claimed about his burial.
- User: any F.E.2d that leaves the map fails mission 8. Script result `"escaped"`, end line "An F.E.2d
  Got Away", then the defeat page and the mission's own failure message. Generic: Game's `^defeaturl^`
  uses `language/english/missions/<id>/failed_<result>.html` when a mission has one (original missions
  have none). Build tool writes it from `tools/missions/mNN_failed_<result>.html`.

## Phase 3: plane folders, paint, dawn and dusk

- Folders (sources `overrides/redbaron/objects/planes/<folder>/`, built by `tools/paint_planes.py` then
  `tools/build_planes.py`, then `godot --import`):
  - `albatros_player` (mission 1): the tuned Albatros stats, stock factory paint.
  - `albatros_red`, `albatros_brenner`: fuselage, tail surfaces and wheel covers repainted in the stock
    Dr.I's red (186, 42, 0), shading kept; wings keep the camouflage (design). Brenner adds a white
    band between the fuselage cross and the tail.
  - `fokker_red`: the stock Dr.I is already all red (the original game's Red Baron), so its atlas is a
    copy. `fokker_brenner`: white band ahead of the tail. Stock Dr.I flight values and guns (33.3
    rounds/s), endurance 125 (Brenner 125 too, after the mission 2 playtest).
  - Rookies: **four folders** `fokker_rookie` (yellow rudder), `fokker_rookie_blue`, `_green`, `_black`,
    endurance 80. Deviation: the design names one folder with texture variants; a folder per variant
    needs no engine change (the model's atlas is chosen by folder).
  - Paint is done on the 1024 atlases by pixel boxes (recorded in paint_planes.py); checked in a
    lineup screenshot next to the stock Albatros, Dr.I and Camel (same models, so same scale).
- Dawn (mission 6): `mods/redbaron/skies/dawn/sky_*.jpg` made by `tools/make_skies.py` from the
  trenches sunset sky (brighter, less saturated, cooler). Dusk (mission 9): the trenches sky as is.
- Generic: global shader parameter `ra_light_tint` (default (1,1,1), reset on every mission load)
  multiplies lit terrain and objects; the terrain is unlit in the original, so without it a dusk sky
  sat over a daylight landscape. Mod keys `[environment] light = r g b`, and `sky` accepts .jpg faces.
- Planned values (for the mission specs): dawn `fogcolour 170 160 175`, `ambient 220 210 215`,
  `light 215 205 210`; dusk `sky = res://game_data/maps/trenches/`, `fogcolour 58 52 66`,
  `ambient 150 140 140`, `light 150 125 120`. To be judged in playtest.

## Phase 4: missions 1, 3, 4, 5, 6, 10 (ids 101, 103, 104, 105, 106, 110)

Common:
- Trenches map has no aerodromes or ground targets in the stock missions (only viaducts, a church, houses):
  the mod places what it needs. The river (z about 9300..9800, "the Somme") is the front: German side
  north, British side south. Trenches scenery template: stock mission 21. Stock trenches houses "outside
  map" in the audit are the template's (also flagged for missions 21-24).
- `missions/objective.gd`: for the missions on the original rules, optional `[mod]` keys `intro`,
  `mark`, `counter = group|label`, `escape = ids`, `escapeline`; the win and other losses stay with the
  original rules. Brings in the playtest lessons (intro line, HUD counter, aerodrome marker, immediate
  failure when an escaping plane leaves the map, with its own failure page).
- Enemy guns: 8 rounds/s in missions 1-8, 12 in 9-12 (Camels firerate 14.4).
- Placeholders until Phase 5: `re8` = aircodh2 model with RE8 stats (highspeed 92, cruise 88, stall 50,
  endurance 40, front gun 8/s, gunners on by folder); `balloon` = the tent model (ground.ini points at
  tent.dff), placed 270 above the ground and scaled 3x by the mission matrix, endurance 20, soft.

Per mission (deviations from the design's INI in **bold**):
- 1 Hawker: **Hawker endurance 120** (design 60: in simulation a head-on pass ended the duel in under 10 s);
  **leaving the map fails at once** ("Hawker Got Away"), the 300 s time limit stays as a cap. Hawker starts
  south-east of the Baron, not head-on.
- 3 Bloody April: three RE8 spotters circle a 2200 x 600 box over the British side three times (enough
  for the 240 s limit), two Nieuports attack the player side. Counter "Spotters down".
- 4 Scramble (country): the Baron parked at a stock parking spot (5966, 7729) heading east; **Brenner
  beside him** (the stock spot at 6430, 7378 sent him into the trees); `regroup` makes the six hangars
  and the tent group 3 (Group3 = 60). **Raiders start 2400 east, 350 apart, strafe 12 s (0x130 limit)
  before attacking the defenders**: a tight formation piled into Brenner, and long strafing flew them
  into the hangars. Three German AA guns (targetgroup 9). Counter "Raiders down".
- 5 The Plates: **escape detection instead of a time limit**: the RE8 runs straight for the south edge
  (about 75 s); leaving the map fails ("The Plates Got Through"). Escorts `304` before `48`.
- 6 Balloon Busting: dawn (sky, fog, ambient, light from Phase 3). Three balloons over the British side,
  three AA guns each (range 540); two Nieuports appear after 60 s. Counter "Balloons burned".
- 10 Cambrai: eight tanks in two rows south of the river (vehicles: turret AI, range 250); four Camels;
  **the Baron carries 10 rockets** (not in the design; ground attack, as asked for mission 8).
- Campaign manifest lists 101-106, 108, 110 (built so far).

## Playtest 10

- Mission 1 debriefing rewritten to fit the mission (the old text claimed a half-hour fight ending when
  Hawker's fuel ran out; the flight is five minutes and he may fall during the duel).
- Albatros wings red too (user; the design allowed camouflage): upper surfaces painted, undersides cream.
- Mission 2: Brenner still looked as fast as the Baron: a gun attack matches the target's speed, so he
  flew at the Scout's pace. He now chases a waypoint on the Scout (renewed every step) at full
  throttle with `highspeed = 125` (was 118), and attacks once he is within 300 of it.
  Measured: 125 against the Baron's 111, 400 away 4 s after the break.

## Playtest 11: paint from a reference model; Scramble take-off

- User reference (a model of the Baron's red Albatros D.III): dull red fuselage and tail, wings in pale
  green and brown camouflage. Paint now: `DULL_RED (165, 42, 34)` on the Albatros fuselage and tail and
  on every strong red of the Dr.I atlas (fokker_red, Brenner's and the rookies'); Albatros wing upper
  surfaces in large green (130, 150, 112) / brown (110, 84, 72) patches across the span (the red wings
  of playtest 10 are gone); `albatros_player` (mission 1) gets the same camouflaged wings with its stock
  fuselage. Bright stock oranges are held to the same dull level.
- Scramble: Brenner parked on the runway 60 behind the Baron with no goals; `missions/m04.gd` (extends
  objective.gd) sends him off (take off, then the raiders) once the Baron is 15 above the ground.

## Playtest 12: target planes on the minimap; escorts in The Plates

- The minimap draws aircraft only for groups 8 and 9, so Hawker and the recon RE8 (group 4 + 7) were
  invisible. Script API `track_on_map(plane, icon)` / `track_markers()`: a map marker that follows a
  plane and goes when it leaves the world. objective.gd gives every plane in a destroy group (other than
  9) the original target icon; the spotters (group 9 + 7) get it over their enemy icon.
- The Plates: `missions/m05.gd` (extends objective.gd): the S.E.5a escorts turn on the Baron when he
  comes within 700 of the recon plane or it is hit, and form up on it again if he falls back past 1500.

## Playtest 13: bombers, persistent attackers, balloon guns

- Original AI (as ported): when hit, a plane dodges for 0.5 s toward a random point (or, with retaliation
  on, turns on the attacker); gun attacks break off at 80 % damage or after the 0x130 time limit, and a
  target behind makes the attacker commit to a hard turn. Hence attackers that "circle away and come
  back". Mod change: **persistent pilots** (aircraft.gd `is_persistent`): no dodge when hit; with
  retaliation on they still turn on the attacker. Default for group 9 single-seaters; `[airN]
  persistent = 0 / 1` overrides. Two-seaters and bombers (gunners) keep the original dodge.
- Scramble: the S.E.5a raiders now carry one bomb each and fly a level bombing run (0x90) on the hangars
  with retaliation off, then attack the defenders with guns. In simulation one bomb can take a hangar and
  the tent beside it; letting two raiders through can lose the mission.
- AA: placed guns only fire inside `angle` about their facing (stock default 1.57 = 90 degrees) and the
  mod's guns all faced +z (south), so guns south of the approach never fired. Every mod AA gun and tank
  now has `angle = 6.28` (all round). Balloon Busting: five guns per balloon in a ring 450 out (the
  Baron is under fire before he reaches a balloon), range 600, new folder `aagun_rapid` (stock aagun at
  14 rounds/s instead of 10). Simulated loitering autopilot: 117 damage in 25 s near the balloons.

## Playtest 14: Scramble in waves

- User: each wave = 4 bombers flying straight at the target + 3 fighters well ahead engaging the Baron
  and Brenner, spawned further out. Now two waves (`missions/m04.gd`): wave 1 starts about 3000 east
  (bombers at x 9150..9270, fighters at x 8450..8550, about 700 ahead); wave 2 waits hidden and comes from
  the same place when wave 1 is down or at 150 s ("A second wave is coming in from the east!").
  Bombers: `re8` (placeholder, gunners), one bomb each, retaliate off, `persistent = 1` (no dodge), level
  run (0x90) on the hangars, then guns on the defenders. Fighters: S.E.5a, 8 rounds/s. 14 raiders
  in group 9 (counter "Raiders down n / 14").
- **German AA removed from Scramble** (design had it): AA rounds hit any plane on their path, and the
  all-round guns at the field shot down Brenner and wore down the Baron.

## Playtest 15

- 10 rockets for the Baron also in missions 2, 4, 5, 6 (with 8 and 10: every Albatros/Dr.I mission but
  1 and 3).
- Persistent pilots are **off by default** again (original AI); only Scramble's bombers set
  `persistent = 1`. Massed, never-dodging attackers caused trouble.
- Scramble: the map ends 3150 east of the aerodrome, so the waves cannot start twice as far out in a
  straight line. Bombers now start in the north-east corner (about 4100 out, 850 high: the ground there
  is about 550) and come round by the east, each through its own dogleg point near (9100, 7250..7700)
  (a shared point made them collide): about 60 s to the hangars (was about 33). Fighters start about
  2900 out, about 30 s (was about 20), so the gap is about 30 s (was about 13). Wave 2 is parked hidden on
  flat ground (on the north-east slope a hidden plane crashed at once) and appears at wave 1's starting
  places. Simulated: fighters arrive at about 25 s, bombers over the hangars at about 61 s.

## Playtest 16: Balloon Busting escorts, Scramble wingmen, tempered gunners

- Balloon Busting (not in the design): three Halberstadt CL.II (`halberstadt`, gunners) with 20 bombs
  each, one over each balloon ring, endurance 250, `bombsight = 1`, bombing the AA guns (target -6).
  Found and fixed on the mod side:
  - their own bomb blasts killed them (the engine gives the firer 5 % of a blast; a big bomb is
    hundreds of points): mod aircraft ignore damage from themselves when AI-flown;
  - together they collided and caught each other's blasts: now one per ring;
  - the original bombing run releases on an estimate that lands bombs long, and after a pass pushes a
    40-radius go-round point that a two-seater circles for ever: `bombsight` aims with the real fall
    (gravity 60 from the plane's velocity) at 150 above the target and, after overflying, flies on 700
    and comes back (m06.gd also resets a CL stuck 10 s on a waypoint). Simulated with the Baron away:
    3 guns at 30 s, 11 at 60 s, all 15 by 105 s.
- Scramble: Brenner (3002) and a second Jasta 11 pilot (`albatros_red`, 3003) start in the air over the
  field going for the raiders; the Baron still takes off.
- Rear gunners tempered (user: "too persistent"): 3 rounds/s (was 5) in bursts of 6, then 1.5 s, out to
  380 (was 450). `DefensiveGunners.burst/pause` are new optional fields (0 = Britain's behaviour).

## Playtest 17

- Scramble: one wave only (4 bombers + 3 fighters, counter "Raiders down n / 7"); m04.gd removed, the
  mission runs on objective.gd again.
- Cambrai: Brenner (`fokker_brenner`) and a rookie (`fokker_rookie_blue`) fly with the Baron and attack
  the Camels (not in the design: alone it was impossible); the Baron carries 30 rockets.

## Phase 5: models (RE8, Handley Page O/100, Caquot balloon)

- `tools/redbaron_textures.py` (procedural fabric, scorched fabric, wicker), `tools/blender_redbaron.py`
  (run `blender --background --factory-startup --python ...`; also works through the MCP bridge, in a
  scene of its own). Background Blender chosen so the build never touches the user's open Blender
  session; the .blend is saved to `overrides/redbaron/redbaron.blend`. Then `tools/build_planes.py`
  copies the folders into game_data, then `godot --import`. `tools/test_redbaron_assets.py` checks them.
- Scale 2.5 units per metre (stock Albatros 22.5 for 9.0 m, Camel 21.3 for 8.5 m). RE8 span 32.5,
  O/100 span 76 (He 111 is 40), balloon 70 long. Lineup screenshot next to the DH.2, Camel and He 111.
- Triangles: RE8 756, O/100 1180, balloon 524 (stock planes 132..210; Britain's 10..18 k): low poly
  with flat colours on a fabric texture, roundels and rudder stripes as geometry like the stock planes.
- Propellers: separate objects pivoting at the hub, material `soppropeller_rb` (the first build named it
  `RB_soppropeller_rb` and the game would not have spun it; the asset test caught it).
- Planes: damaged1 / damaged2 / wreck (scorched paint, rigid airframe) and a flat shadow clump; the mod
  aircraft now swaps damage stages like the Britain aircraft (35 %, 70 %, shot down). Balloon: scorched
  and sagging stage, then a wreck of tatters on the rigging; a tether cable hangs 110 m.
- The RE8 and balloon placeholders are replaced (missions 3, 4, 5 and 6 pick them up by folder). The
  O/100 is ready for mission 9.

## Phase 6: missions 7, 9, 11, 12 and the ending

Trenches German aerodrome for 7 and 11: scenery placed at (8400, 7750) (three hangars, two tents, a big
hangar), marked on the minimap.

- 7 The Other Side (`m07.gd`): Halberstadt photo plane (gunners, retaliate off) flies over the British
  side and home; three Camels appear (0x120) ahead of it when it is deep over their side (spawned behind
  it, they never caught it). Win: back within 400 of the aerodrome after its photo run ("Photographs
  taken. Bring them home!"). **Photo plane endurance 150** (design 80: three Camels at 8/s took 80 in
  about 10 s in simulation). Lost: failed_defence.html.
- 9 Dusk Raiders (objective.gd): dusk environment; a rail yard (two stations, two sheds, two wagons) at
  (7500, 6500), Group3 = 60; three O/100s (endurance 90, 6 bombs, bombsight, nose gun 12/s) from the
  north-east corner round a dogleg in the south-east: about 60 s to the yard (straight in, 25 s).
  Simulated: first bomb on the yard at about 65 s.
- 11 Formation (`m11.gd`), design's sequence: Camels A/B at 60 s; Brenner takes A, his second B; A down
  (or 15 s) -> Brenner chases B 1500 east ("Stay with the two-seater."). Leaving the two-seater more than
  900 away for 5 s before it is home brings two Camels on it. The two-seater's route is about 110 s
  (on the first, short route it was home at 35 s, before the Camels). Home within 300 = it lands
  (hidden, safe); then C-E come for Brenner, far off, marked on the minimap; Brenner and C-E take no
  damage until the Baron is within 400 (C-E collided and fell before he arrived otherwise); then "Lt.
  Brenner is down.", his second flies home, C-E turn on the Baron. Win: C-E down. Debriefing: the letter.
- 12 The Last Patrol (`m12.gd`): rookies run north (about 55 s; the pursuers start 500 behind them);
  each one off the map is home ("n of 4 are home."); on the fourth `secure_progress()` and the pursuers
  turn on the Baron; all six down -> waves of three every 40 s near the Baron; ridge guns along the
  river (8 AA, range 300, all round). After 240 s of the ridge the Baron is shot down by script (whatever
  the cheats: the story's end). Death after the rookies are home: result `epilogue`, no end line, then
  `campaigns/redbaron/epilogue.html` (design text verbatim, black page, no tally, no slogan; Continue
  goes to the campaign page, which then shows the completion page). Not done: steering the waves to push
  the Baron low over the ridge (the AI cannot be told where to herd the player).
- Failure pages for scripts' results: 7 / 9 / 11 / 12 `failed_defence.html`.
- Campaign manifest: all twelve missions, 101-112.

## Phase 7: wiring check and builds

- Campaign wiring was done early (see above); ranks, briefings, Replay Missions, debriefings, the letter,
  the epilogue and the completion page are in place. No in-game text says "Axis" (grep of the missions,
  campaign pages and scripts).
- `./build.sh` (Web, Linux, Windows) succeeds; the pck holds `mods/redbaron/campaign.ini`, the mod's
  compiled scripts and missions 101-112, and leaves out `docs/`, `tools/`, `tests/` and fixture mission
  199. The exported Linux build runs missions 102 and 112 headless without script errors. Android was not
  built here (no SDK set up in this session).
- Before release: `replayall = 0` in `campaign.ini`; confirm the wreath inscription (the design marks it
  "secondary source only").

## Playtest 18: trenches minimap, bombed scenery

- The trenches minimap was the wrong image (build_assets took `map.jpg`, another landscape with a river
  and a coast, over `map.bmp`, which matches the terrain and is what the exe loads). Fixed in
  tools/build_assets.py and game_data (also corrects stock missions 21-25). **The real trenches layout:**
  trench systems in the north (z < about 9100, the mod's German side), a muddy no man's land band from
  z about 9200 to 11700 (two trench lines in it), open country south (British side). Earlier notes
  calling a "river at z 9300..9800" the front came from the wrong image; the placements still fit
  except the balloons, now moved behind the British lines (z 12150..12450) with their AA rings.
- Country missions (2, 4, 8, 9): `intact` now covers the whole map: every bombed hangar, factory, burnt
  tree, wrecked bridge and AA ruin of the template stands (30 objects; the country map is behind German
  lines). Test: no burn / wreck / ruin scenery in the country missions.

## Playtest 19: Dusk Raiders fights back; wingmen paint; friendly fire

- O/100 gun stations (historical positions): nose (Scarff ring, forward arc), dorsal (behind the wings,
  upper rear) and ventral trap-door gun (lower rear), each 4 rounds/s in bursts of 8, then 1 s, out to
  450 (`GUN_STATIONS`; new `DefensiveGunners.station_shot`, Britain untouched).
- Heavy bombers (O/100) turn like Britain's He 111: bank at most 18 degrees, rolled in at 10 deg/s, pitch
  within 8 degrees, no dodge when hit; the flight step's per-frame pitch-rate decay is cancelled as in
  Britain (without it they dived into the hills on the way in).
- Five Camel escorts in formation on the bombers (`m09.gd`): they turn on a German within 800 of a bomber
  (or when one is hit) and form up again when none is within 1600. Two wingmen: Brenner and another
  Jasta 11 pilot. Bomber endurance 150 (design 90).
- Wingmen never fly the Baron's own paint (user): new `albatros_wingman` (red, yellow band) for the second
  pilot in Scramble and Dusk Raiders. Check: no non-player `albatros_red` / `fokker_red` in any mission.
- AI fire no longer hurts its own side in mod missions (mod aircraft `take_damage`): the engine's rounds
  hit any plane, and bomber gunners and wingmen were shooting down their own formation.
