# Red Baron plane figures and mission overrides

Reference for every aircraft the campaign flies: its figures, why they are what they are, and every
per-mission override with the mission-script reason for it. Updated 10 November 2026.

Sources: `overrides/redbaron/objects/planes/<folder>/plane.ini` (built into `game_data/objects/planes` by
`tools/build_planes.py`) and `tools/missions/mNN.ini` (built by `tools/build_missions.py`). Tests:
`tests/test_redbaron.gd` (`RATES` and the per-mission rule checks).

## Rules

1. **Stock planes stay stock.** The British fighters and the Halberstadt are original game folders shared
   with the stock missions. The campaign flies its own copies, `<stock>_rb` (stock model and paint, the
   mod's `plane.ini`). Nothing in the original folders changes.
2. **Defaults live in the plane file.** A mission overrides a figure only when its script needs it; each
   override carries its reason in the mission file and in the table below.
3. **Guns: about 1.5x for the player's side.** Sustained rate = `firerate * fireon / (fireon + fireoff)`.
   Every fighter of a type keeps its own burst rhythm; only `firerate` sets the rate.
   - German twin Spandau, Albatros D.II / D.III (the Baron and his wingmen, missions 1-9): **23.3**.
   - Fokker Dr.I (the Baron, Brenner, the rookies, missions 10-12): **32.7**, 1.4x the Albatros. The user's
     choice (7 November 2026): the player must feel the 1918 upgrade. Historically the Dr.I carried the
     same guns as the Albatros; its real edge was turn and climb.
   - British twin guns (Camel: two Vickers; S.E.5a: Vickers + Lewis): 23.3 / 1.5 = **15.6**.
   - Single guns fire half their side's twin rate: British (Nieuport 17, Bristol Scout, DH.2, the R.E.8
     and O/100 pilots) **7.8**; German (Halberstadt pilot) **11.7**.
   - Defensive gunners (two-seater observers, the O/100's three stations) are a separate, playtested
     system in `aircraft.gd` (3 and 4 rounds/s in bursts) and are not part of this scale.
4. **Endurance** is the player side's main edge and is unchanged from the playtests: the Baron, Brenner
   and the wingmen 125, rookies 80; British fighters 45-50. A round scores 1 on every tick it spends inside
   a plane's hit radius and flies on (the original's proximity test), so a well-aimed round scores several
   points: measured, a Camel holding 25-38 behind the Baron took his 125 in about 3 s. With rule 3 the
   Camel has to hold its aim (125 / 50) x 1.5 = 3.75 times as long as the Baron does to win the exchange.
5. **Flight figures follow history, relative to the plane they meet**, with no British fighter better than
   the player's in every respect. Speed scale: about 0.63 units/s per km/h (Albatros D.III, 175 km/h = 110).
   One exception, the user's choice (7 November 2026): the Camel's roll and pitch are 25% below the
   Albatros's, although historically it was the better turner. In the original campaign the player out-turned
   every ordinary enemy (only the Baron's boss Dr.I out-turned him), and the campaign keeps that feel.

## Player and allied aircraft

| Folder | Who | End. | Top / dive / cruise | Climb | Stall | Roll lo/hi | Pitch lo/hi | Accel | Guns (rounds/s) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `albatros_player` | Baron, mission 1 | 125 | 110 / 116 / 105 | 85 | 60 | 65 / 80 | 65 / 90 | 10 | 25 x 1.4/0.1 = 23.3 |
| `albatros_red` | Baron, 2-9 | 125 | 110 / 116 / 105 | 85 | 60 | 65 / 80 | 65 / 90 | 10 | 23.3 |
| `albatros_brenner`, `albatros_wingman` | wingmen, 2-9 | 125 | 110 / 116 / 105 | 85 | 60 | 65 / 80 | 65 / 90 | 10 | 23.3 |
| `fokker_red`, `fokker_brenner` | Baron, Brenner, 10-12 | 125 | 120 / 130 / 107 | 110 | 82 | 97 / 112 | 107 / 117 | 9 | 35 x 1.4/0.1 = 32.7 (stock 33.3) |
| `fokker_rookie` (+ `_blue`, `_green`, `_black`) | rookies, 10-12 | 80 | as above | 110 | 82 | 97 / 112 | 107 / 117 | 9 | 32.7 |
| `halberstadt_rb` | allied two-seater, 6 / 7 / 11 | 35 | 105 / 110 / 90 | 85 | 74 | 30 / 40 | 50 / 60 | 7 | 31.1 x 0.9/1.5 = 11.7 (stock 4.5) + observer |

The Dr.I fires 1.4x the Albatros so that the player feels the upgrade (historically the same twin
Spandau). Against the Camel that is 2.1x, with a far better turn and climb as well.

## British aircraft

| Folder | Plane | End. | Top / dive / cruise | Climb | Stall | Roll lo/hi | Pitch lo/hi | Accel | Guns (rounds/s) | Character |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `sopwithcamel_rb` | Sopwith Camel | 50 | 112 / 116 / 103 | 90 | 70 | 49 / 60 | 49 / 68 | 10 | 18.7 x 0.75/0.15 = 15.6 | A little faster than the Albatros; roll and pitch 25% below it, far below the Dr.I |
| `se5a_rb` | S.E.5a | 45 | 115 / 125 / 106 | 85 | 65 | 55 / 70 | 55 / 80 | 10 | 18.7 x 1.0/0.2 = 15.6 | Fast, strong dive, less agile |
| `nieuport17_rb` | Nieuport 17 | 45 | 104 / 108 / 96 | 88 | 55 | 70 / 85 | 70 / 90 | 10 | 9.33 x 1.0/0.2 = 7.8 | Out-turns and out-climbs the Albatros, slower |
| `bristolscout_rb` | Bristol Scout | 45 | 100 / 105 / 92 | 75 | 60 | 60 / 70 | 60 / 80 | 10 | 9.1 x 1.5/0.25 = 7.8 | Outdated by 1917 |
| `aircodh2_rb` | Airco DH.2 (also the F.E.2d stand-in) | 45 | 95 / 100 / 88 | 70 | 55 | 65 / 80 | 65 / 85 | 10 | 8.33 x 1.4/0.1 = 7.8 | Nimble but slow |
| `re8` | R.E.8 two-seater | 40 | 92 / 105 / 88 | 60 | 50 | 45 / 55 | 45 / 60 | 7 | 8.33 x 1.4/0.1 = 7.8 + observer | unchanged flight |
| `handleypage` | Handley Page O/100 | 150 | 88 / 100 / 84 | 50 | 45 | 22 / 30 | 25 / 35 | 5 | 7.8 + three gun stations | unchanged flight |

Stock figures for comparison: Camel 118 / 128, climb 108, stall 80, roll 90 / 105, pitch 100 / 110,
accel 20, endurance 130, 41.7 rounds/s (it was the original game's player plane); S.E.5a and Nieuport 17
105 / 111, roll 60 / 75, 20.8 rounds/s; Bristol Scout 115, 25.7 rounds/s; DH.2 105, 23.3 rounds/s.
R.E.8 and O/100 flight figures stay: their speeds set the timing of missions 3-5 and 9.

## Mission overrides

Everything else is the plane file's default. Loadouts (`ordinancetype` / `numordinance`: the Baron's
rockets, bombers' bombs) are part of each mission's design rather than plane figures; the Baron carries
10 rockets in missions 2-9, 11 and 12 and 30 in mission 10 (eight tanks).

| Mission | Plane | Override | Default | Reason (mission script) |
| --- | --- | --- | --- | --- |
| 1 Hawker | DH.2 (Hawker) | endurance 120 | 45 | The mission is a duel; at 45 a head-on pass ended it in seconds |
| 1 Hawker | DH.2 (Hawker) | highspeed 100 | 95 | Slower than the Baron's Albatros (110) in a straight line, so his retreat can be intercepted; leaving the map fails the mission at once ("Hawker Got Away"). Was 105 until 10 November 2026 |
| 1 Hawker | DH.2 (Hawker) | highroll 100, lowroll 85, highpitch 105, lowpitch 85 | 80 / 65 / 85 / 65 | He out-turns the Albatros (80 / 65 / 90 / 65): position and patience win, not turning with him (10 November 2026) |
| 2 First Sortie | Brenner | highspeed 125 | 110 | The script sends him after the decoy and the player must catch him to call him back; he has to pull away visibly (measured 400 away 4 s after the break) |
| 4 Scramble | R.E.8 bombers | persistent 1 | 0 | They must press their bombing run on the hangars; two-seaters otherwise dodge when hit |
| 6 Balloon Busting | Halberstadt x3 | endurance 700, bombsight 1 | 35 | Their bombing of their assigned AA guns is what opens a way to the balloons; they must live through the AA rings and hit the guns. 250 until 10 November 2026, when AA fire on planes started working again: two of three were shot down |
| 7 The Other Side | Halberstadt (photo plane) | endurance 290 | 35 | It must survive the three Camels until the Baron, escorting from behind, reaches them; 150 was set against Camels at 8 rounds/s (about 10 s to lose 80), scaled to their 15.6 |
| 8 Wounded | DH.2 x4 (as F.E.2d) | gunners 1 | 0 | They stand in for the two-seat F.E.2d (observer's gun); the DH.2 is a single-seater elsewhere |
| 8 Wounded | DH.2 x4 (as F.E.2d) | gunnerrate 2.5 | 3 | The script holds all four in formation (retaliate off), so four observers fire at once at the attacker |
| 9 Dusk Raiders | Camel x5 | keepstation 1 | 0 | The script keeps one escort on each bomber and two ahead, at the bombers' speed |
| 9 Dusk Raiders | O/100 x3 | bombsight 1 | 0 | The rail-yard objective needs bombs that land where aimed |
| 6 / 9 | bombers | bombsight 1 | 0 | as above |
| 11 Formation | Halberstadt (damaged two-seater) | endurance 360 (starts at 70 %, a quarter of each hit by script) | 35 | It must live through four attacks if the Baron fights them; one mistake must not end the mission (11 November 2026) |
| 11 Formation | Halberstadt | highspeed 84 | 105 | Damaged and slow (stall 74): the road home about 155 s, long enough for four attacks |

Removed (now the plane file's default, or equal to it): every British `firerate` and `endurance`
(missions 1-12), the O/100's `firerate 12.86` and `endurance 150`, R.E.8 `endurance 40`, and
`endurance` on Brenner, the second wingman and the rookies.

## Ground fire on aircraft (`[mod] aadamage`)

Until 10 November 2026 AA guns and tanks did **no damage to aircraft** in mod missions: the mod's `take_damage`
compared a ground gun (a World target dictionary) with the plane itself, which raised a script error and dropped
the hit (since the Balloon Busting bomber change of playtest 16). Fixed; the mission key `[mod] aadamage` scales
ground fire on aircraft where full strength was too much once it worked:

| Mission | aadamage | Reason |
| --- | --- | --- |
| 6 Balloon Busting | 0.6 (guns back to the stock 10 rounds/s, were 14) | A straight pass through an unbombed ring cost 55-125 of the Baron's 125; risky, but three balloons must stay possible |
| 10 Cambrai | 0.5 | An autopilot Baron loitering over the tanks took 100+ in two minutes at full strength |
| 12 The Last Patrol | 1 (unchanged) | The guns are silent (range 0) in play; they open only in the closing sequence, when nothing can be hurt |

## Run-time changes in mission scripts

| Mission | Plane | Change | Reason |
| --- | --- | --- | --- |
| 8 Wounded | Baron | after the ambush burst: health at least half, then 1/4 of every hit | The story wounds him; Brenner must have time to deal with the ambushers |
| 8 Wounded | Nieuports (ambush) | until the wound: highspeed 130, no damage, no dodging; they chase the Baron at full throttle and open fire inside 280 | They must close and fire visibly (a gun attack matches the target's speed and never caught a Baron flying home); afterwards stock figures |
| 1 Hawker | Hawker | evasive break when the Baron settles behind him, 7 s recovery; dive for the lines at 200 s (or badly hit after 90 s) | The duel's shape (m01.gd) |
| 11 Formation | Brenner, Hartwig | no damage until the story moment; then Brenner is killed by script, Hartwig set to 50 % and protected | Brenner's death is staged, never set off by the Baron's position; Hartwig must live to be the last objective |
| 11 Formation | two Camels of the cut-in | no damage until their scripted part | The scene needs both |
| 1-12 | the player's AI wingmen | roll at most 110 deg/s; proportional gun-attack steering while the target is ahead | The Dr.I's roll made the original bang-bang steering swirl (Cambrai playtest) |
| 12 The Last Patrol | the four young pilots | highspeed 92 (mission file); 0.3 of each hit; none once across the lines | The Baron (120) can lead, catch up and turn back; a missed interception is survivable |
| 12 The Last Patrol | Albers (the straggler) | from encounter 2: at most 55 %, highspeed 88, 0.2 of each hit | Hurt and alone; the last two attacks go for him (a pair took him from 42 to nothing in 4 s at 0.3) |
| 12 The Last Patrol | Camels | hit by the Baron while on a pilot: break off 6 s, then back on the Baron every other time | Defensive passes buy time; not every scout goes straight back for the pilots |
| 12 The Last Patrol | Baron, the force, the guns | no damage from the fourth crossing on; in the sequence the force and the Baron fire continuously (force_fire), the guns aim at a stand-in just above him | The ending is scripted; nothing in it can fail the mission |
