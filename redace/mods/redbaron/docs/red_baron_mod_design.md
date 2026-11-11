# Der Rote Kampfflieger — Red Baron Mod Design

Design reference for implementation · 2026-11-05

## Overview

A 12-mission campaign for redace_re in which the player flies as Manfred von Richthofen for the Central Powers, from his duel with Lanoe Hawker in November 1916 to his death on 21 April 1918. It reuses two existing maps, country and trenches, and inverts the original game, where the player hunts a red-plane villain.

The story turns on three rescues:

| Mission | Who saves whom | Meaning |
| --- | --- | --- |
| 2. First Sortie | The Baron pulls the wingman out of a reckless chase | Teacher and student |
| 11. Formation | Brenner takes a Camel off the Baron's tail and is lost while the Baron escorts a damaged two-seater home | The student repays the debt |
| 12. The Last Patrol | The Baron covers the rookies' escape, then dies alone against overwhelming odds | The teacher pays it forward |

Tone: restrained and respectful. Victories are professional, not triumphant. The Allies are capable opponents, not villains, which sets up the final note: his enemies bury him with honours.

Terminology: use "Central Powers" or "German Air Service" in all text, never "Axis" (a WWII term).

## Characters

**Manfred von Richthofen (player).** Starts as a Leutnant, ends as Rittmeister commanding Jagdgeschwader 1. Cool, methodical, a teacher of tactics. His rule, stated in mission 2: never chase alone, never fight low over enemy lines. He breaks it once, deliberately, in the finale to save the rookies.

**Leutnant Karl Brenner (wingman, fictional).** Arrives at Jasta 11 aged 19 in mission 2. Brave, impatient, chases kills. Over the campaign he learns discipline. In mission 11 he takes a Camel off the Baron's tail and is shot down out of sight while the Baron escorts a damaged two-seater home. Fictional so his arc and death need not misrepresent a real pilot.

**Recurring voices (briefing text only).** The adjutant who writes the briefings, and the rookie pilots of 1918. One rookie flies as Brenner's second in mission 11 and returns in the finale, so bringing him home carries weight. Keep them unnamed so the finale stays about the Baron and Brenner's absence.

| Mission | Brenner's state |
| --- | --- |
| 2. First Sortie | Reckless. Chases a decoy toward AA; the player pulls him out. |
| 3–10 | Flies with the player in missions 4 and 8; the other briefings note his growing tally. |
| 8. Wounded | Escorts the wounded Baron home. First time he protects the player. |
| 11. Formation | Takes a Camel off the Baron's tail; shot down out of sight while the Baron escorts the two-seater. |
| 12. The Last Patrol | Absent. The Baron's tail is unguarded. |

**Paint schemes.** Richthofen painted his Albatros red in January 1917, when he took over Jasta 11, and the squadron followed with red plus personal colours, usually on the fuselage ([Jagdstaffel](https://en.wikipedia.org/wiki/Jagdstaffel)).

| Pilot | Scheme | Missions |
| --- | --- | --- |
| The Baron | Factory finish | 1 (before Jasta 11) |
| The Baron | All red | 2–12 |
| Brenner | Red with a white tail band, so the player can spot him | 2–11 |
| 1918 rookies | Red with one accent each: yellow, blue, green, black tail | 11–12 |

Wings may keep their camouflage, as many Jasta 11 machines did; this also saves texture work.

## Aircraft and maps

Most airframes exist in `game_data/objects/planes`, but the stock Albatros is the game's weakest fighter and cannot carry nine missions. The mod adds tuned player folders with the red paint, and three new models: a British two-seater, an observation balloon and the Handley Page O/100.

| Role | Side | Folder | Status | Missions |
| --- | --- | --- | --- | --- |
| Albatros D.II, factory finish | Player | `albatros_player` | New folder: tuned stats, stock model | 1 |
| Albatros D.III / D.V, red | Player | `albatros_red` | New folder: tuned stats, red paint | 2–9 |
| Fokker Dr.I, red | Player | `fokker_red` | New folder: stock flight values, endurance 125, red paint | 10–12 |
| Brenner | Player side | `albatros_brenner`, `fokker_brenner` | Red with white tail band, tuned stats | 2–11 |
| 1918 rookies | Player side | `fokker_rookie` | Red with accent colours (texture variants) | 11–12 |
| Halberstadt two-seater | Player side | `halberstadt` | Exists | 7, 11 |
| Airco DH.2 | Allies | `aircodh2` | Exists | 1 (Hawker); 8 (stand-in for the F.E.2d, also a pusher) |
| Nieuport 17, Bristol Scout | Allies | `nieuport17`, `bristolscout` | Exists | 2–8 |
| S.E.5a, Sopwith Camel | Allies | `se5a`, `sopwithcamel` | Exists | 4–12 |
| RE8 two-seater | Allies | `re8` | **New model** | 3, 5 |
| Observation balloon | Allies (ground object) | `balloon` | **New model** | 6 |
| Handley Page O/100 | Allies | `handleypage` | **New model** (confirmed) | 9 |

**Player plane stats.** Mission files can override only `endurance` and `highspeed`, so the tuned values go in the new folders' `plane.ini`. The player Albatros is slightly better than the 1917 British scouts, as the real one was, and clearly worse than the Camel, which motivates the switch to the Dr.I in mission 10.

| Stat | Stock Albatros | Player Albatros (new) | Nieuport / S.E.5a | Camel | Dr.I (stock, kept) |
| --- | --- | --- | --- | --- | --- |
| highspeed | 90 | 110 | 105 | 118 | 120 |
| climbspeed | 70 | 85 | 80 | 108 | 110 |
| highroll | 60 | 80 | 75 | 105 | 112 |
| highpitch | 70 | 90 | 85 | 110 | 117 |
| firerate | 10 | 25 | 25 | 50 | 40 |
| accel | 7 | 10 | 10 | 20 | 9 |
| endurance | 35 | 125 | 45 | 130 (override to 50) | 1000 (set to 125) |

Groups are bits, not nations, so the engine needs no side swap. Put German planes in group 8 (`groups = 256`) and Allied planes in group 9 (`groups = 512`). Allied AA keeps `targetgroup = 8` and shoots the Germans unchanged.

| Map | Represents | Missions |
| --- | --- | --- |
| `country` | German aerodromes behind the lines (Douai, Roucourt) | 2, 4, 8, 9 |
| `trenches` | Arras, Cambrai and the Somme front | 1, 3, 5, 6, 7, 10, 11, 12 |
| `desert` | Optional Palestine side campaign | none in the main 12 |

Copy an existing mission on the same map as the starting point for each new one, so ground object positions already sit on the terrain.

## Campaign

Twelve missions, November 1916 to April 1918. Difficulty rises from 2 to 5, with a breather at mission 8 and peaks at 9 and 12. Five missions need scripts (2, 7, 8, 11, 12); seven run on stock rules.

| # | Title | Date | Map | Player plane | Win | Lose | Difficulty (1–5) | Script |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Hawker | 23 Nov 1916 | trenches | `albatros_player` | Destroy the DH.2 | He escapes (time) | 2.5 | No |
| 2 | First Sortie | Jan 1917 | country | `albatros_red` | Brenner rejoins and both reach the aerodrome | Brenner dies | 2 | Yes |
| 3 | Bloody April | Apr 1917 | trenches | `albatros_red` | Destroy 3 spotters | Out of time | 2.5 | No |
| 4 | Scramble | May 1917 | country | `albatros_red` | Destroy the raiders | Hangars below 60 % | 3 | No |
| 5 | The Plates | May 1917 | trenches | `albatros_red` | Destroy the recon plane | It reaches its lines (time) | 3 | No |
| 6 | Balloon Busting | Jun 1917 | trenches | `albatros_red` | Burn 3 balloons | Shot down | 3.5 | No |
| 7 | The Other Side | Jun 1917 | trenches | `albatros_red` | Photo plane completes its run and returns | Photo plane lost | 3.5 | Yes |
| 8 | Wounded | 6 Jul 1917 | country | `albatros_red` | Land at the aerodrome | Crash | 2 | Yes |
| 9 | Dusk Raiders | Sep 1917 | country | `albatros_red` | Destroy the bombers | Rail yard below 60 % | 4 | No |
| 10 | Cambrai | 20 Nov 1917 | trenches | `fokker_red` | Destroy 75 % of tanks | Out of time (tanks reach the village) | 3.5 | No |
| 11 | Formation | Mar 1918 | trenches | `fokker_red` | Two-seater lands, Brenner's attackers destroyed | Two-seater lost | 3 | Yes |
| 12 | The Last Patrol | 21 Apr 1918 | trenches | `fokker_red` | All 4 rookies escape, then the pursuit is destroyed | Any rookie lost | 5 | Yes |

**INI conventions used below.** Decimal goal types: 16 take off, 32 waypoint, 48 formation, 112 gun attack, 144 bombing run, 256 start airborne, 288 reveal when near, 304 / 320 retaliate on / off (304's `real` is also the attack time limit), 352 reveal after N s, 368 hide. Group bits: 16 (group 4), 64 AA (6), 128 mission target (7), 256 player side (8), 512 enemy (9); add 4 (group 2) or 8 (group 3) for protect groups. `pos` values come from the template mission. Comments after `;` are notes for this doc; strip them unless the parser accepts them.

**Hidden planes.** The stock rules count hidden planes as lost, which can win a mission before its ambush appears (mission 7 would be won at time zero). Every mission with hidden planes sets `requireshotdown = 1`, the Britain mission's existing switch.

**Endurance and AI safety.** Player planes get 125 from their folders. Allied fighters stay in the 45 class; override the Camel to `endurance = 50`. Protected AI planes (missions 2, 4, 7, 11, 12) get 60–80, waypoints routed clear of AA, and retaliate off, so an AI mistake rarely fails the mission. Expect these to need tuning in playtesting.

### 1. Hawker

> 23 November 1916. A British DH.2 has crossed the lines, flown by a pilot who will not run until he must. Engage him. Patience wins this fight, not speed.

A turning duel against Major Lanoe Hawker, Britain's first fighter ace. Richthofen flew an Albatros D.II, so the plane is unpainted. The DH.2 out-turns it; the player wins by staying above and waiting for an opening. After 4 minutes Hawker breaks for his lines, low, as he did historically. If he crosses them, the mission fails.

No script: the attack goal's 240 s limit ends the duel, the next goal sends him home, and `timelimit` covers his flight time. Hawker sits in group 4, not 9, so escaping does not count as a kill.

```ini
[mission]
Group7 = -100
timelimit = 300       ; 240 s duel + ~60 s dash home

[air0]
name = albatros_player
groups = 256
player = 1

[air1]                ; Hawker
name = aircodh2
groups = 144          ; group 4 + target
endurance = 60
highspeed = 105
[air1goal0]
type = 256
[air1goal1]
type = 304            ; retaliate on, 240 s attack limit
real = 240
[air1goal2]
type = 112
targetid = <player id>
[air1goal3]
type = 32             ; dash for the British map edge
```

### 2. First Sortie

> January 1917. You take command of Jasta 11. Leutnant Brenner flies on your wing today. Teach him the first rule: we never chase alone.

A lone Bristol Scout trails low toward the British AA belt. Brenner breaks off after it. Catch him, bring him back into formation, and lead him home. The decoy and the two Nieuports that spring the ambush are optional kills: the lesson is breaking off, not winning the chase.

```ini
[mission]
Group2 = 100          ; Brenner must survive
requireshotdown = 1
; win set by script

[air0]
name = albatros_red
groups = 256
player = 1

[air1]                ; Brenner
name = albatros_brenner
groups = 260          ; player side + group 2
endurance = 80
[air1goal0]
type = 256
[air1goal1]
type = 112            ; chases the decoy
targetid = <decoy id>

[air2]                ; decoy
name = bristolscout
groups = 512
endurance = 45
[air2goal0]
type = 256
[air2goal1]
type = 320
[air2goal2]
type = 32             ; waypoints over the AA belt

[air3]                ; ambusher (x2)
name = nieuport17
groups = 512
[air3goal0]
type = 368
[air3goal1]
type = 288            ; appears when Brenner nears the AA belt
targetid = <Brenner id>
real = 200
[air3goal2]
type = 112
targetid = <Brenner id>
```

Script: when the player is within 150 of Brenner, replace his goals with formation on the player (48) and show "Brenner rejoins". Win when both are within 300 of the aerodrome. The script owns the win, overriding the stock "all enemies destroyed" win.

### 3. Bloody April

> April 1917. Three British spotters are directing artillery onto our batteries. Every minute they stay up costs lives. Bring them down before the next barrage.

The spotters carry rear gunners (Engine changes, item 3), so attacking from directly behind is costly.

```ini
[mission]
Group7 = -100
timelimit = 240

[air0]
name = albatros_red
groups = 256
player = 1

[air2]                ; spotter (x3)
name = re8
groups = 640          ; enemy + target
endurance = 40
[air2goal0]
type = 256
[air2goal1]
type = 32             ; slow circuit over the front

[air5]                ; escort (x2)
name = nieuport17
groups = 512
[air5goal0]
type = 256
[air5goal1]
type = 112
targetid = -8         ; attacks the player side
```

### 4. Scramble

> May 1917. Enemy scouts are over the aerodrome. Get airborne. Save the hangars.

The player starts parked. The S.E.5as strafe the hangars first, not the player, so the takeoff is tense but fair. German AA defends with `targetgroup = 9`. Six hangars and sheds form the protect group, so losses are gradual rather than all-or-nothing.

```ini
[mission]
Group3 = 60           ; fail below 60 % of the 6 buildings
Group9 = -100

[air0]                ; player, parked: no goals
name = albatros_red
groups = 256
player = 1

[air1]                ; Brenner
name = albatros_brenner
groups = 256
[air1goal0]
type = 16             ; take off
[air1goal1]
type = 112
targetid = -9

[ground17]            ; hangar, bighanger, tent (x6)
name = hanger
groups = 8            ; group 3: protect

[vehicle0]
name = aagun
groups = 64
targetgroup = 9       ; German AA shoots the raiders

[air4]                ; raider (x4)
name = se5a
groups = 512
[air4goal0]
type = 256
[air4goal1]
type = 112
targetid = -3         ; strafe the hangars
[air4goal2]
type = 112
targetid = -8         ; then the defenders
```

### 5. The Plates

> May 1917. A British reconnaissance crew has photographed your aerodrome. If those plates reach their lines, the bombers come tomorrow. Stop them from getting the plates home.

The recon plane runs flat out for the lines with two S.E.5as behind it and an observer firing back. The clock is its flight time to the edge.

The recon plane sits in group 4, not group 9: bullets still hit planes in groups 4, 8 and 9, but escaping no longer counts as a kill. `timelimit` then gives the fail with no script; tune it to the plane's flight time.

```ini
[mission]
Group7 = -100
timelimit = 150       ; = recon flight time to the lines

[air0]
name = albatros_red
groups = 256
player = 1

[air2]                ; recon plane
name = re8
groups = 144          ; group 4 + target, NOT group 9
endurance = 40
[air2goal0]
type = 256
[air2goal1]
type = 320            ; retaliate off: it only runs
[air2goal2]
type = 32             ; straight to the map edge

[air3]                ; escort (x2)
name = se5a
groups = 512
[air3goal0]
type = 48             ; formation on the recon plane
targetid = <recon id>
[air3goal1]
type = 304
```

Optional: a custom fail line, "The plates got through", instead of "Out of Time".

### 6. Balloon Busting

> June 1917, dawn. High Command has ordered every fighter squadron to burn the British observation balloons before the offensive. Three hang over their lines, ringed by guns. Burn them before the light is full.

Richthofen was not a balloon specialist, so the briefing frames this as an emergency order. Dive in, burn, get out: the AA ring is the threat, and a two-plane patrol arrives after 60 s.

```ini
[mission]
Group7 = -100
requireshotdown = 1

[air0]
name = albatros_red
groups = 256
player = 1

[ground100]           ; balloon (x3)
name = balloon        ; new model
groups = 128

[vehicle0]            ; AA ring (x6-8)
name = aagun
groups = 64
targetgroup = 8
range = 540

[air3]                ; balloon defence patrol (x2)
name = nieuport17
groups = 512
[air3goal0]
type = 368
[air3goal1]
type = 352            ; arrive after 60 s
real = 60
[air3goal2]
type = 112
targetid = -8
```

Needs a dawn fog colour and sky box (Engine changes, item 5). Optional script: the balloons winch down over 3 minutes, sinking deeper into the AA.

### 7. The Other Side

> June 1917. A Halberstadt crew will photograph the British lines today. You are their escort. The pictures are worthless if the crew does not come home.

The mirror of mission 5. Camels appear as the photo plane nears the British lines. Victory comes when the photo plane completes its run and returns past the home waypoint, not when the interceptors die.

```ini
[mission]
Group3 = 100          ; photo plane must survive
requireshotdown = 1
; win set by script

[air0]
name = albatros_red
groups = 256
player = 1

[air2]                ; photo plane
name = halberstadt
groups = 264          ; player side + group 3
endurance = 80
[air2goal0]
type = 256
[air2goal1]
type = 320            ; retaliate off: never breaks to fight
[air2goal2]
type = 32             ; over the lines and back, clear of AA

[air4]                ; interceptor (x3)
name = sopwithcamel
groups = 512
endurance = 50
[air4goal0]
type = 368
[air4goal1]
type = 288            ; appear near the photo plane
targetid = <photo plane id>
real = 250
[air4goal2]
type = 112
targetid = <photo plane id>
```

Script: win when the photo plane reaches its final waypoint over German lines.

### 8. Wounded

> 6 July 1917. A flight of F.E.2d two-seaters is over our lines. Attack. Their observers can shoot.

The briefing is ordinary. The wound comes from an observer's burst during the player's own attack pass, so the player sees it coming: the screen dims and blurs, the throttle drops to half and the guns stop. Brenner forms up and fights off pursuers. One gets through, so the player must jink a crippled plane while gliding home to land. Keep it under 3 minutes after the wound.

Historically Richthofen flew an Albatros D.V here; the red Albatros stands in and the briefing names the D.V. The F.E.2d was a pusher, so the `aircodh2` model is the closest existing stand-in.

```ini
[mission]
requireshotdown = 1
; win set by script

[air0]
name = albatros_red
groups = 256
player = 1

[air1]                ; Brenner
name = albatros_brenner
groups = 256
endurance = 80
[air1goal0]
type = 256
[air1goal1]
type = 48             ; formation on the player
targetid = <player id>
[air1goal2]
type = 304

[air2]                ; F.E.2d stand-in (x4), with rear gunners
name = aircodh2
groups = 512
endurance = 45
[air2goal0]
type = 256
[air2goal1]
type = 304

[air6]                ; pursuer, revealed by the script after the wound
name = nieuport17
groups = 512
[air6goal0]
type = 368
```

Script: apply the wound on the first observer hit after 30 s while the player is within 150 of an F.E.2d. Then reveal the pursuer with a gun attack on the player. Win when the player lands within 300 of the aerodrome; lose on a crash.

### 9. Dusk Raiders

> September 1917, dusk. High Command has pulled the fighter squadrons back to defend the rail yards. Handley Page bombers are coming for the yard that feeds the front. They are slow and they are big. Do not let their size fool you about their guns.

Six yard objects (station, sheds, wagons) form the protect group, so losses are gradual. Bomber endurance 90 each keeps the fight tense rather than a grind against three 150-endurance targets.

```ini
[mission]
Group3 = 60           ; fail below 60 % of the 6 yard objects
Group7 = -100

[air0]
name = albatros_red
groups = 256
player = 1

[ground50]            ; station, hanger, van (x6)
name = station
groups = 8            ; group 3: protect

[air2]                ; bomber (x3), with gunners
name = handleypage    ; O/100, new model
groups = 640
endurance = 90
ordinancetype = 1
numordinance = 6
[air2goal0]
type = 256
[air2goal1]
type = 320            ; holds course
[air2goal2]
type = 144            ; level bombing run on the yard
targetid = -3
```

Needs a dusk fog colour and sky box. The bomber model is a confirmed new build (see Aircraft and maps).

### 10. Cambrai

> 20 November 1917. British tanks have broken through at Cambrai and our guns cannot see them through the smoke. The ground-attack squadrons cannot stop them alone. Get down there. You have until they reach the village.

The first Fokker Dr.I mission. Ground attack was normally the Schlachtstaffeln's work, so the briefing frames this as an emergency. The tanks are static turrets that fire back; `timelimit` stands for their arrival at the village, so no movement script is needed. Camels cover the tanks and attack the player.

```ini
[mission]
Group7 = -75
timelimit = 300       ; tanks reach the village

[air0]
name = fokker_red
groups = 256
player = 1

[vehicle10]           ; British tank (x8)
name = tank
groups = 128
targetgroup = 8       ; fires at German planes
range = 250

[air3]                ; Camel (x4)
name = sopwithcamel
groups = 512
endurance = 50
[air3goal0]
type = 256
[air3goal1]
type = 112
targetid = -8
```

Optional later: a script that moves the tanks toward the village, replacing the timer.

### 11. Formation

> March 1918. The Spring Offensive. A damaged two-seater is limping home from a reconnaissance over the advance. Bring it in. Brenner and his new second will cover you.

The player escorts a fragile two-seater. At 60 s two Camels dive on the Baron. Brenner takes one off his tail and chases the other away, out of sight. The two-seater cannot survive alone, so the player must stay with it; this is the player's own duty, not a scripted inability.

When the two-seater is safe near the aerodrome, the HUD shows Brenner's position, far off. The player arrives to find him going down under three Camels. Brenner's second, a rookie, survives; he flies again in mission 12. The mission ends when the player destroys the three Camels.

The distance is the design: reaching Brenner in time means abandoning the two-seater, which fails the mission. The player's choice stays honest and Brenner's death needs no visible cheat.

```ini
[mission]
Group3 = 100          ; two-seater must survive
requireshotdown = 1
; win set by script

[air0]
name = fokker_red
groups = 256
player = 1

[air1]                ; Brenner
name = fokker_brenner
groups = 256
endurance = 80
[air1goal0]
type = 256
[air1goal1]
type = 48
targetid = <player id>

[air2]                ; rookie, Brenner's second
name = fokker_rookie
groups = 256
endurance = 80
[air2goal0]
type = 256
[air2goal1]
type = 48
targetid = <Brenner id>

[air3]                ; damaged two-seater
name = halberstadt
groups = 264          ; player side + group 3
endurance = 30        ; already damaged
[air3goal0]
type = 256
[air3goal1]
type = 320
[air3goal2]
type = 32             ; home to the aerodrome

[air5]                ; Camel A and B, on the Baron (x2)
name = sopwithcamel
groups = 512
endurance = 50
[air5goal0]
type = 368
[air5goal1]
type = 352
real = 60
[air5goal2]
type = 112
targetid = <player id>

[air7]                ; Camel C-E, Brenner's attackers (x3)
name = sopwithcamel
groups = 512
endurance = 50
[air7goal0]
type = 368            ; revealed by the script
```

Script:

1. At 60 s, switch Brenner and the rookie to a gun attack on Camel A, then send them and Camel B away from the two-seater's route, about 1500 off.
2. When the two-seater is within 300 of the aerodrome, reveal Camels C–E around Brenner and show his position on the HUD.
3. Let C–E wear Brenner down; make the hit that downs him land as the player closes within 400. Show "Lt. Brenner is down." The rookie breaks for home.
4. Win when the two-seater has landed and C–E are destroyed.

Debrief, replacing the promotion page: a short letter to his mother.

> *Madam, it is my duty to tell you that your son fell today. He died saving my life. He was the finest pilot I have trained, and I will not forget him. — Rittmeister Manfred Freiherr von Richthofen*

### 12. The Last Patrol

> 21 April 1918. Most of the Jasta are new boys. Bring them home.

Three phases, one mission. The player wins two objectives before the death.

1. **Escort.** Four rookies, including Brenner's former second, fly for the German edge of the map while six Camels attack them. Objective: all four get out. Campaign completion is saved on the fourth crossing, before anything else happens.
2. **Stop the pursuit.** The Baron turns back so the Camels cannot follow. Objective: destroy all six pursuers. A HUD counter shows kills.
3. **The ridge.** Waves of three Camels arrive every 40 s. Damage and attacks push him low over the Morlancourt ridge, where AA and machine guns wait. He falls to the fighters or the ground fire. After 4 minutes, a scripted ground-fire burst ends it for players who survive.

```ini
[mission]
Group3 = 100          ; all four rookies
requireshotdown = 1
; win and end set by script

[air0]
name = fokker_red
groups = 256
player = 1

[air1]                ; rookie (x4)
name = fokker_rookie
groups = 264          ; player side + group 3
endurance = 80
[air1goal0]
type = 256
[air1goal1]
type = 320            ; retaliate off: they run
[air1goal2]
type = 32             ; to the German map edge

[air5]                ; pursuer (x6)
name = sopwithcamel
groups = 512
endurance = 50
[air5goal0]
type = 256
[air5goal1]
type = 112
targetid = -3         ; attack the rookies

[air11]               ; wave member (x18)
name = sopwithcamel
groups = 512
endurance = 50
[air11goal0]
type = 368            ; revealed by the script, 3 every 40 s

[vehicle20]           ; ridge guns (x8)
name = aagun
groups = 64
targetgroup = 8
range = 300
```

Script: a rookie that crosses the German edge counts as saved, not lost. On the fourth crossing, save campaign completion and retarget the six pursuers at the player. When all six are down, start the waves and steer them to press the player low toward the ridge. On the player's death, skip "Plane Destroyed" and the defeat page; fade out and open the epilogue.

## Engine changes

Follow the Britain bonus mission's pattern: mission-specific runtime scripts plus overrides, so the stock 28 missions stay untouched.

| # | Change | Missions | Size |
| --- | --- | --- | --- |
| 1 | **Mission script hook.** Timers, proximity checks, goal-list replacement, forced damage, HUD messages, and script-owned win/lose that overrides the stock "all enemies destroyed" win | 2, 7, 8, 11, 12 | Medium |
| 2 | **Player plane folders.** `albatros_player`, `albatros_red`, `albatros_brenner`, `fokker_red`, `fokker_brenner`, `fokker_rookie`: tuned `plane.ini` plus paint | all | Small–medium |
| 3 | **Defensive gunners on two-seaters and bombers.** Stock AI never fires outside an attack goal; reuse the Britain bomber gunners | 3, 5, 7, 8, 9, 11 | Small (exists) |
| 4 | **requireshotdown = 1** in every mission with hidden planes | 2, 6, 7, 8, 11, 12 | None (exists) |
| 5 | **Per-mission fog and sky.** Dawn, dusk, overcast, without editing the shared map files. The cheapest way to make two maps feel like twelve battles | 6, 9, any | Small |
| 6 | **Custom end flow.** Letter debrief in place of promotion (11); epilogue in place of the defeat page (12); campaign completion saved before the death sequence | 11, 12 | Small |
| 7 | **HUD kill counter** for phase 2, not shown on the epilogue | 12 | Small |
| 8 | **Wound effect.** Screen dim and blur, throttle cap, guns disabled | 8 | Small |
| 9 | **New models.** `re8`, `balloon`, `handleypage` (O/100) | 3, 5, 6, 9 | Large |
| 10 | **Campaign wiring.** Separate campaign list and pilot progress so the mod's 12 missions do not overwrite the original 25; ranks Leutnant to Rittmeister | all | Medium |
| 11 | **Moving vehicles** (optional). Drive group 7 tanks toward the village, replacing the timer | 10 | Medium |

Build order:

1. Script hook (1) and prototypes of missions 2 and 8 with stock models and placeholder paint. They test whether rescuing Brenner, and later relying on him, works in play.
2. Player plane folders (2) and per-mission fog and sky (5).
3. Stock-rule missions 1, 3, 4, 5, 6, 10, using placeholder models where new ones are pending.
4. New models (9), then missions 7, 9, 11, 12 with the end flow (6, 7).

## Epilogue

Shown after mission 12 in place of the defeat page, on a black page with a single illustration of the funeral. No kill tally and no closing slogan: the page stays solemn.

> *Rittmeister Manfred Freiherr von Richthofen fell on 21 April 1918 near Vaux-sur-Somme. His young pilots reached home.*
>
> *He was buried the next day at Bertangles by his enemies, No. 3 Squadron of the Australian Flying Corps, with full military honours. A wreath from the Allied airmen read: "To our gallant and worthy foe."*

## Historical notes

| Fact used | Status | Source |
| --- | --- | --- |
| Burial at Bertangles, 22 April 1918, by No. 3 Squadron AFC, full military honours | Confirmed | [Anzac Portal](https://anzacportal.dva.gov.au/node/545) |
| Wreath inscription "To our gallant and worthy foe" | Secondary source only; confirm before release | [Today in History](https://todayinhistory.blog/2018/04/22/) |
| Last flight in Fokker Dr.I 425/17, chasing Lt. Wilfrid May (209 Sqn); came down near Vaux-sur-Somme; 80 credited victories | Confirmed | [This Day in Aviation](https://www.thisdayinaviation.com/21-april-1918/) |
| Fatal shot most likely Australian ground fire (Sgt. Cedric Popkin the leading candidate), though Capt. Roy Brown was credited | Debated; the mod blends fighters and ground fire, which fits | [This Day in Aviation](https://www.thisdayinaviation.com/21-april-1918/) |
| Red Albatros from January 1917, when he took over Jasta 11; squadron red with personal colours | Confirmed | [Jagdstaffel](https://en.wikipedia.org/wiki/Jagdstaffel) |
| Hawker shot down 23 Nov 1916 after a long dogfight; Richthofen flew an Albatros D.II | Confirmed | [Albatros D.II](https://en.wikipedia.org/wiki/Albatros_D.II) |
| Wounded 6 July 1917 in an Albatros D.V, by an F.E.2d of No. 20 Squadron | Confirmed | [Donald Cunnell](https://en.wikipedia.org/wiki/Donald_Cunnell) |
| O/100 in France from late 1916, night bombing from spring 1917; O/400 entered service April 1918 | Confirmed | [Handley Page Type O](https://en.wikipedia.org/wiki/Handley_Page_Type_O) |
| Richthofen not a balloon specialist; Schlachtstaffeln did ground attack at Cambrai | Unverified; affects briefing tone only | none |
| Lt. Karl Brenner, the rookies, the letter | Fiction | none |
