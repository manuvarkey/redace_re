# Images required for the Red Baron campaign pages

Fourteen pictures for the briefings and campaign pages, in the style of the original game's menu art.
All fourteen are now included in `game_data/language/english/campaigns/redbaron/img/`.
See [art_generation.md](art_generation.md) for generation prompts and image processing details.
The pages still work without optional artwork (see "Putting them in" for replacements).

## Style of the original art

Look at these files before generating (all in `redace/game_data/language/english/menus/`):

| Kind | Originals to match | Look |
| --- | --- | --- |
| Briefing photo (left slot) | `bristolscoutbck.png`, `aircodh2bck.png`, `spadbck.png`, `soppybck.png` | A small square **sepia photograph** pinned to a board: one aircraft in a three-quarter view from slightly above, flying left to right, on a plain pale stained card; a pin hole near the top centre; soft vignette, worn paper, no text |
| Briefing target (right slot) | `albatrosstarget.png`, `fokkertarget.png`, `junkerstarget.png`, `aaguntarget.png` | The same **sepia rendering** of the target inside a **pale cream disc** with a thin dark ring, two thin dark diagonal lines crossing behind the disc like a gun-sight, all on **dark reddish-brown wood**; no text |
| Full page | `intro.png`, `victory.png`, `congrats.png` | Painted, softly lit late-1990s CGI look: warm sepia and amber, soft focus, gentle bloom; wooden frame or panel where text sits |

All pictures are period-accurate First World War (1916-1918) subjects. No modern objects, no lettering,
no logos, no swastikas or other later symbols. German aircraft carry the straight-armed cross
(Cross pattée / Eisernes Kreuz, black with white border; plain Latin cross on the 1918 Fokker); British
aircraft carry red-white-blue roundels and rudder stripes.

## Sizes and format

The menus are 640 x 480 pages stored at 4x for high resolutions:

| Kind | Shown at | File size |
| --- | --- | --- |
| Briefing photo, briefing target | 128 x 128 | **512 x 512** PNG |
| Full page | 640 x 480 | **2560 x 1920** PNG (4:3) |

RGB PNG, no transparency. If the generator cannot make 2560 x 1920, generate 4:3 as large as it can and
upscale (e.g. Real-ESRGAN, as the build does for the original art); 512 x 512 squares likewise.

## Putting them in

1. Save each file as `redace/game_data/language/english/campaigns/redbaron/img/<name>.png` (create the
   `img` folder; names below).
2. Run `python3 redace/mods/redbaron/tools/build_missions.py` (puts the briefing pictures and the letter
   paper into the pages) and `godot --headless --path redace --import`.
3. The campaign intro and completion pages already reference `intro` and `complete`; they appear on the
   next start.

## The list

### Briefing photos (left slot, 512 x 512)

| Name | Missions | Prompt |
| --- | --- | --- |
| `albatros_d2_photo` | 1 | Sepia First World War photograph pinned to a pale stained card: an Albatros D.II German biplane fighter in factory finish (pale green and brown camouflage wings, varnished plywood fuselage, black crosses on white squares), three-quarter view from slightly above, flying left to right, propeller blurred; pin hole at top centre, soft vignette, worn paper, no text |
| `red_albatros_photo` | 2-9 | Sepia First World War photograph pinned to a pale stained card: an Albatros D.III biplane fighter painted dull red on fuselage and tail, wings in green and brown camouflage, black crosses with white borders, three-quarter view from slightly above, flying left to right, propeller blurred; pin hole at top centre, soft vignette, worn paper, no text |
| `red_fokker_photo` | 10-12 | Sepia First World War photograph pinned to a pale stained card: a Fokker Dr.I triplane painted all dull red with black crosses with white outlines, three-quarter view from slightly above, flying left to right, rotary engine and propeller blurred; pin hole at top centre, soft vignette, worn paper, no text |

### Briefing targets (right slot, 512 x 512)

Common part of every prompt: *"...rendered in warm sepia, centred inside a pale cream circular disc with a
thin dark outer ring, two thin dark diagonal lines crossing behind the disc like a gun-sight, the whole on
dark reddish-brown wood grain; soft lighting, late-1990s game menu art, no text."*

| Name | Missions | Subject (put in front of the common part) |
| --- | --- | --- |
| `dh2_target` | 1 | An Airco DH.2 single-seat pusher biplane (engine and propeller behind the pilot, open tail booms), British roundels, three-quarter view |
| `bristolscout_target` | 2 | A Bristol Scout single-seat biplane, British roundels, three-quarter view |
| `re8_target` | 3, 4, 5 | An R.E.8 two-seat biplane (long upper wing, tall fin, observer's ring-mounted Lewis gun behind the pilot), British roundels and rudder stripes, three-quarter view |
| `balloon_target` | 6 | A British Caquot observation balloon: a large grey sausage-shaped gas bag with three inflated tail lobes, a wicker basket hanging below on rigging, a tether cable running down, side view |
| `camel_target` | 7, 11, 12 | A Sopwith Camel single-seat biplane, British roundels, three-quarter view |
| `fe2d_target` | 8 | A Royal Aircraft Factory F.E.2d two-seat pusher biplane (observer in the nose with a Lewis gun, engine behind the crew, open tail booms), British roundels, three-quarter view |
| `handleypage_target` | 9 | A Handley Page O/100 twin-engine biplane bomber (very large wings, two engines between the wings, box tail with twin fins, nose and dorsal gunners), British roundels, three-quarter view from below |
| `tank_target` | 10 | A British Mark IV rhomboid tank with tracks running round the hull and side gun sponsons, crossing churned mud, three-quarter view |

### Pages (2560 x 1920)

| Name | Where | Prompt |
| --- | --- | --- |
| `intro` | Campaign page (Bonus Missions → Der Rote Kampfflieger) | Dark, low-contrast painted scene for a menu background, warm sepia and deep red: a First World War German airfield at dawn, a row of red Albatros and Fokker fighters in front of canvas hangars, mist, a lone pilot in a leather coat walking towards them; the middle two thirds of the picture dark and calm so white text can sit on it; a thin carved wooden frame round the edge; soft focus, gentle bloom, late-1990s game menu art, no text |
| `complete` | Completion page after the campaign | Painted close-up, late-1990s game menu art: a gloved hand holding a Pour le Mérite (blue enamel Maltese cross with gold eagles) on its black and white ribbon, soft window light, warm sepia background of a wooden table with a folded flying helmet; the middle of the picture dark and calm so white text can sit on it; no text |
| `letter` | Mission 11 debriefing (the letter to Brenner's mother) | An aged sheet of writing paper on a dark wooden desk lit by an oil lamp, a fountain pen and an Iron Cross ribbon beside it; the paper blank (the game writes the letter on it in white type, so keep the paper fairly dark, sepia brown rather than white); late-1990s game menu art, no text |

| `epilogue` | Campaign epilogue (after mission 12) | Painted, softly lit late-1990s game menu art, warm sepia and dusk rose: a First World War military cemetery at sunset, rows of plain pale wooden and stone crosses running away into evening mist, tall poplars beyond, a gravel path; in the near left foreground a laurel wreath leaning on a cross with a Pour le Merite (blue enamel Maltese cross with gold eagles between the arms) on its black and white ribbon resting on it; the middle and upper middle of the picture dark and calm so light text can sit on it; no text |

The epilogue picture in place was generated by the user from the prompt above (11 November 2026). The Blender
stand-in script, tools/redbaron_epilogue_art.py, remains as a fallback.
