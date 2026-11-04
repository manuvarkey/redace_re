# Collision and avoidance behavior

This records the correction following the audit of commit `0fa315c`. That commit's tests encoded
incorrect interpretations of aircraft collision flags and matrix roles. The expectations have
been replaced with values traced through the constructor, property getters, callbacks and x86
assembly, rather than through the port's previous implementation.

## Source evidence

The original decompiled source lives outside this repository at `../decomp/RedAce.c`; the
executable used for disassembly is `../extract/game/RedAce.exe`.

| Rule | Original evidence | Shared implementation |
|---|---|---|
| Aircraft are soft collision targets | `FUN_0042cec1`, source line 30200; `OR al,1` at `0x42d267` and store at `0x42d26c`; template loader also sets bit 1 at line 30749 | Aircraft contacts apply fractional damage both ways |
| Flag getter | `FUN_0042eb3e` delegates to base `FUN_0042a6d2`; shifted base receiver makes property 9 return aircraft `+0x3c` | Constructor flag semantics are explicit in the aircraft branch |
| Aircraft damage | `FUN_00430199`: coefficient `0.2` from flag `0x400`; flag 1 selects gradual damage to prober | Target gets `2*dt*prober.endurance*0.2`; prober gets `2*dt*target.endurance*0.2` |
| Solid/soft scenery | Same callback: coefficient 15; flag 1 controls prober damage | Solid kills prober; soft gives `2*dt*object.endurance*15` damage |
| Control/render frames | Loader `FUN_0042d2de` stores RenderWare matrix at `+0x110`, allocates control matrix at `+0x08`; copy then bank rotation of `+0x110` at `0x4343c9`, control yaw at `0x434440` | `flight_basis` is control, `global_transform.basis` is render |
| Saved frame | `FUN_00430851` copies control matrix `+0x08` to `+0xd0` | Save previous `flight_basis` before movement |
| Probes and terrain ordering | `FUN_00431607`, source lines 32044–32306 | One ordered pass through terrain and object callbacks |
| Terrain avoidance | `FUN_0043b2a8` uses pilot `+0x0c`, equivalent to aircraft control matrix `+0x08` | Threshold `120-90*forward.y`; upright/inverted commands use control up |
| Aircraft avoidance | `FUN_004394df` reads unbanked matrices and property `0x1a` (plane `+0x16c`), offsets `+0x40`/`+0x38` | Strict squared distance below `starboard_length*back_length*2.5`; unnormalized cross product times 50; evade 1.5 seconds |
| Atomic callbacks | `FUN_00430295` queries each atomic; triangle callback `FUN_00430199` returns zero, and `FUN_004837c0` stops only that atomic's triangle loop | One callback per intersected MeshInstance3D; first triangle per mesh |
| Wreck collision | Object callback excludes self, not destroyed objects; `FUN_0042c00e` leaves wreck geometry in the world | Destroyed aircraft and scenery remain collision targets |

For equal endurance 100, one callback at dt=0.01 removes **0.4 health from each plane**.
Two such callbacks leave each at 99.2. Aircraft collisions can eventually kill a plane, but a
single contact is not automatically lethal. Each plane's own update can register further contacts.

## Ordered probes

Let `old` be the previous unbanked frame, `control` the current unbanked frame, `render` the
banked frame, `previous` the previous center and `origin` the center just after movement.
The original keeps both centers fixed for this pass, even if a lower contact changes position.

| Probe | Start | End | Terrain handling |
|---|---|---|---|
| Nose | previous | previous + old.forward * front | Terrain first; crash stops the pass; otherwise query objects |
| Upper | previous | origin + render.up * down | Same gate |
| Underside | previous - old.up * down | origin - control.up * down | Omitted in ground state; query terrain, then objects, then resolve terrain contact |
| Fourth | previous - old.up * back | origin - control.up * back | Original makes terrain query but ignores its result; still queries objects |
| Negative wing | previous | origin - render.left * port | Terrain adds 1 damage and enters falling state; objects still queried |
| Positive wing | previous | origin + render.left * port | Same |

The fourth probe's use of **back length along minus up** is deliberate: this follows the
actual callback code rather than inferring a conventional tail probe from the INI key name.
Both wings use the port extent, as the original does. Upper uses down extent.

Underside normal speed is `(endpoint-contact).dot(normal)/dt`:

- Below -10, above high speed, or already falling: crash and stop later probes.
- At least -5: place at `contact + normal*(down+0.05)`; flying state becomes ground state.
- Between -10 and -5: reflect the displacement about the normal, place at contact plus reflected
  displacement plus the normal offset, and steer toward the reflected direction.

Parked initialization projects the mission position onto the runway and adds wheel height before
the first saved probe origin, matching the original constructor. Scripted airborne appearances
run afterward and retain their specified altitude. Ground-state movement still projects vertically
onto the ground and adds down length, matching original state 4. The removed approximation was the airborne next-center height check: this
could snap a plane up a cliff before its swept probes had a chance to register a crash.

## Geometry and broad phase

The collision path visits a combined candidate list in scene order. A conservative swept-center
sphere envelope includes all probe offsets; it is filtered once per plane pass. Narrow phase
uses each mesh's current transform and triangles. Pivot-centered bounds enclose child rotations
such as turrets and propellers. Geometry/parts rebuild when a damage model changes. Wrecks remain
eligible, and long segments are not limited to grid cells near their endpoint.

The original RenderWare BSP/list traversal is not reproduced byte-for-byte in Godot. Scene order
is deterministic, but exact callback order across different objects can differ from native BSP
order. Imported meshes, engine intersection tolerances and the existing Godot physics step also
preclude claiming bit-identical replays. Arbitrary runtime mesh deformation or translation of
child parts beyond their cached pivot bounds would require refreshing the collision geometry;
the shipped rotating propellers/turrets are enclosed by those bounds.

## Preserved mod behavior

No Britain mod files are changed. Its bomber/escort steering, pitch caps, cliff preview, ceiling,
gunners, sea contact, staged models and falling-impact hook remain in place. The shared collision
pass marks terrain as processed so the base terrain hook does not run it twice; the mod's own
falling-impact override still runs.

## Verification

Run from repository root with Godot 4.7.2, replacing `godot` with the installed binary as needed:

```sh
godot --headless --path redace --log-file /tmp/collision-damage.log -s tools/test_collision_damage.gd
godot --headless --path redace --log-file /tmp/probes.log -s tools/test_probe_detection.gd
godot --headless --path redace --log-file /tmp/avoidance.log -s tools/test_avoidance.gd
godot --headless --path redace --log-file /tmp/collision-management.log -s tools/test_collision_management.gd
godot --headless --path redace --log-file /tmp/britain-aircraft.log -s tools/test_britain_aircraft.gd
godot --headless --path redace --log-file /tmp/britain-mission.log -s tools/test_britain.gd
```

The management suite checks ordered gates, underside landing/bounce/crash, slopes, taxiing,
duplicate loss suppression, multi-atomic contacts, live model transforms, replacement models,
soft/solid wrecks, long segments, unequal aircraft endurance and actual Godot terrain queries.
Its real cliff fixture verifies that movement does not teleport up the cliff before collision.
The other suites cover frame vectors, strict avoidance thresholds, falling contacts and mod
behavior. These are source-derived regressions, not a paired executable gameplay replay.

## Seeded Britain observation

The diagnostic `tools/audit_britain_collisions.gd` uses seed 12345, 1/60-second manual steps,
AI control for the player and disabled mission-ending checks, allowing 90 simulated seconds
regardless of factory loss. This diagnostic is not a gameplay acceptance gate; combat outcomes
can change with AI/random scheduling and it does not run the original executable.

Before these corrections, the same diagnostic reported eight aircraft losses during contact
checks and two from bullets. Afterward it reported five aircraft losses, all during bullet
processing, and no collision losses. The factory was destroyed by a bomber at about 57.8 seconds.
This supports the damage-flag diagnosis without claiming all collision/AI behavior is identical
across engines.

```sh
godot --headless --path redace --log-file /tmp/britain-loss-audit.log -s tools/audit_britain_collisions.gd
```
