# Dover-inspired Battle of Britain assets

Original Blender models with procedural paint and CC0 photographic surface textures.
`britain.blend` preserves the editable models. Blender uses game coordinates (+Y up,
+Z aircraft nose); glTF exports deliberately disable Blender's axis conversion.
Rebuild with `python3 tools/build_britain.py`, with the Blender MCP addon listening
on localhost:9876. The script creates a separate scene and preserves other scenes.

Geography is a fictional interpretation, not an accurate reconstruction of Dover.
References:
- https://www.dovermuseum.co.uk/Information-Resources/Articles--Factsheets/White-Cliffs-of-Dover.aspx
- https://www.nationaltrust.org.uk/visit/kent/the-white-cliffs-of-dover/d2-battery---a-brief-history
- https://www.dovermuseum.co.uk/Information-Resources/The-Collection/Cross-Channel-Shelling%2C-World-War-Two.aspx

D2's concrete emplacements were in service in June 1940. The port, chalk downs,
coastal gun positions and sheltered works use that period's visual vocabulary.
The factory and town layout are fictional. Later Fan Bay/Wanstone installations
are not presented as exact September 1940 reconstructions.

Online aircraft listings were investigated; no third-party aircraft download with
verified redistribution rights was obtained. Aircraft are authored here, with
modeled airfoil wings, fuselage sections, framed canopies, exhausts, gun barrels,
radiators, aerials, animated propellers, camouflage, panel seams and rivets.
Photographic surfaces from Poly Haven (CC0, https://polyhaven.com/license):
- Rock Face 03, Dario Barresi / Rico Cilliers: https://polyhaven.com/a/rock_face_03
- Red Brick 03, Rob Tuytel: https://polyhaven.com/a/red_brick_03
- Leafy Grass: https://polyhaven.com/a/leafy_grass
- Concrete Wall 006: https://polyhaven.com/a/concrete_wall_006
Source JPEGs are retained here; chalk is recolored from the rock texture. Aircraft
camouflage, rivets and weathering remain original procedural art. Existing game
trees and audio are reused under the project's existing terms.

Runtime logic lives in `redace/mods/britain/`: mission `init.gd` registers the
environment and aircraft through the generic `redace/mods/launcher.gd`. The
mission INI declares its init path; stock missions load without a mod. Aircraft subclass (bombing, escorts,
gunners, ceiling correction, staged damage, sea loss) and environment (wave water,
cloud sky, collision surface and sinking crash debris). Core Aircraft is unchanged;
World has narrow generic mod creation/sea/camera hooks. All new damageable models
have two damaged variants and a wreck; terrain and harbour foundations stay static.
AA placements use the original turret system and target only enemy group 9.
The sea uses analytical waves/Fresnel/foam and opacity, not ray-traced reflections.
Chase distance is 65% of the original; held camera views retain their distances.

Validation: `tools/test_britain.gd`, `tools/test_britain_aircraft.gd`, and
`MS=26 godot --headless --path redace -s tools/audit_missions.gd`.
Sea bounds and quay exclusions are checked by the mission test; visually inspect
the shader with the Compatibility renderer.

Map: 6000 x 6000 units, 49.5% water, irregular coast, height-field hills and valley.
Spitfire wingspan: 22 units, against Bristol Scout's 21.64. Bf 109: 22; He 111: 40.
Arcade top/cruise/climb/dive/stall parameters: Spitfire 143.85/122/110/152.25/70;
Bf 109 143.85/122/110/152.25/72; He 111 107.8875/91.5/82.5/114.1875/60.
Both fighters use the stock SPAD XIII's 137 top and 145 dive settings plus 5%.
The bomber uses 75% of the fighter top, cruise, climb and dive settings; its roll rates
are 12–16 deg/s and its bank is limited to 18 degrees. Bomber endurance is 150 versus
the fighters' 100 in the plane defaults, and 67.5 versus the escorts' 45 in the mission.
These are gameplay settings. Representative published maxima considered when creating the models:
- Spitfire Mk I R6774: 355 mph, A&AEE report of 30 July 1940, reproduced at
  https://wwiiaircraftperformance.com/org/spitcom/mk1/spitmk1.html
- Bf 109E-3: 354 mph, Museum of Flight:
  https://www.museumofflight.org/exhibits-and-events/aircraft/messerschmitt-bf-109e-3
- He 111H: 270 mph, Kent Battle of Britain Museum:
  https://www.kbobm.org/heinkel_project.html
The Heinkel museum table describes a later H-series engine fit; these are representative
family maxima, not equal-altitude September 1940 loaded-performance measurements.
Inherited forward motion is
speed squared / highspeed: bomber level mission cruise is about 77.6 units/s.
Escorts use that physical speed with station-error correction and bearing lookahead,
then recover fighter speed when engaging. Their spawn slots are relative to the bomber.
Bombing retry circuits include a longer straight alignment leg for the reduced speed.

RAF wing roundels are baked into paint UVs, removing the former hovering discs.
Both damage stages use cumulative bullet punctures, chipped metal and soot textures;
all three aircraft keep identical vertex positions even when shot down. Existing
progressive smoke accompanies damage; destroyed aircraft retain scorched wreck paint.

Vessels use the aircraft's approximate 2-units/metre scale: cargo hull 210 units
(about 107 m using the Spitfire span reference), fishing trawler 41.6 units (21 m).
Five freighters and sixteen fishing boats occupy the harbor and offshore waters.
These are generic period vessels, not reconstructions of named ships. All retain
progressive damage models. `python3 tools/test_britain_assets.py` checks geometry,
scale, vessel counts and placement clear of land, quays and other vessels.

Allied Spitfires preview terrain 2, 4 and 6 seconds ahead and climb when a
cliff would intersect their projected path. `test_britain_aircraft.gd` includes
a direct 180-unit cliff crossing and full bomber formation checks.


### Performance and flight limits

Options → Graphics offers Low/Standard Water and Cloud Detail for this mission,
and Low/Standard Scenery Detail plus the existing Effects Detail slider. Standard
retains the original shaders; Low water/clouds simplify fine shading while retaining
broad waves and moving cloud coverage. These settings do not change collision
geometry. See [graphics options](../../docs/graphics-options.md) for measurements.

The map follows the global View Distance setting; its generator no longer inserts
a minimum visibility override. Britain Spitfires, Bf 109s and He 111s have a soft
stall ceiling at 1,000 world units above sea level. Speed limiting fades in from
800 units and caps the flight target below stall speed at the ceiling, including
boost/dive bonuses. Remaining thrust fades to zero by 1,100 units to prevent
a perfectly vertical stalled fighter from climbing indefinitely. The usual stall motion remains and descending permits recovery;
there is no altitude teleport or hard wall. Ground/falling states and stock aircraft
retain their previous rules. `tools/test_britain_aircraft.gd` covers this transition,
recovery, very high altitude and the stock altitude-penalty path.
