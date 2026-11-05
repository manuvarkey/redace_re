# Bullet performance and parity

The default game retains Classic bullet behaviour. There is no new Bullet Handling
menu setting: the optimizations are conservative broad phases and rendering-call
reductions, so maintaining two gameplay modes would add complexity without a benefit.
A frozen reference implementation exists only under tools/ for paired tests/benchmarks.

## Findings and implementation

On the real Britain map with 22 aircraft made present, 221 scenery targets and
4,096 active rounds, the original aircraft scan took about 25 ms and scenery plus
terrain about 20 ms per pass. Terrain ray queries alone took about 1 ms. Ribbon
preparation took about 4.5 ms. These measurements preceded implementation.

Changes in scripts/main.gd:

- Build a small 3D aircraft grid once per bullet update. Insert each hit sphere's
  enclosing box into every touched 100-unit cell, in original aircraft order.
  Each bullet queries its endpoint's cell. The original strict distance test,
  owner/presence/group checks, group multiplicity and take_damage calls remain.
  Presence is checked live, including when an earlier round kills a plane.
- Cache the existing nine-cell scenery candidate lookup for each visited endpoint
  cell during that update. Cache a conservative maximum world-space height of the
  same local AABBs the original narrow phase tests. Skip scenery only when BOTH
  segment endpoints are above every candidate box (with a roundoff margin).
  Descending/crossing segments still run the original box/triangle tests. Candidate
  order, dead scenery, damage-model geometry refresh and terrain ray queries remain.
- Share constant ribbon UV/index arrays and set the unchanged vertex colour once
  per surface instead of six times per bullet. Positions, direction, width, alpha,
  texture, topology, update frequency and ImmediateMesh rendering are unchanged.
- Extract _update_bullets for direct paired testing. --perf now also prints average
  bullet_update and bullet_draw CPU milliseconds per physics tick over each reporting
  interval. The update figure includes broad-phase construction, collisions and
  lifecycle work; draw measures CPU preparation, not GPU completion time.
  Timestamp calls run only with --perf. Separate collision timings come from the
  benchmark, avoiding per-bullet instrumentation overhead in normal play.

The caches last only for the synchronous bullet pass, after vehicle placement and
before subsequent aircraft updates. Shipped damage callbacks change health, presence
and damage models, without moving aircraft/scenery roots or changing hit radii during
that pass. Those live damage/presence/geometry checks still run. Movement between
physics ticks is reflected in the next pass; mission reload clears caches. A future
mod that moves roots or changes radii inside damage callbacks would need to invalidate
or rebuild the broad phase there.

The endpoint aircraft test deliberately remains an endpoint test, rather than a
swept segment collision. Bullets continue after aircraft hits and can damage the
same aircraft on subsequent ticks and other aircraft in the same tick. Terrain and
scenery stop ordinary rounds; AA skips them, as before. Expiration-before-collision,
reverse iteration, swap/pop removal, random draw order, velocities, lifetime, firing,
ammunition, existing projectile capacity and physics frequency remain unchanged.
No aircraft physics, AI, mission scripts, effects or graphics settings changed.

## Reproducible benchmark

Run from the repository root, substituting the Godot 4.7.2 executable:

```sh
XDG_DATA_HOME=/tmp/redace-bullet-reference godot --path redace -s tools/bench_bullets.gd -- --reference
XDG_DATA_HOME=/tmp/redace-bullet-optimized godot --path redace -s tools/bench_bullets.gd
```

Both runs load mission 26 and freeze aircraft, turrets and mission-end processing.
All 22 aircraft are present for collision checks. Fixed rounds occupy the same
formation near the harbour at y=360, with velocity (20, -2, 300). Each stage has
3 warmups and 20 samples. Full-step samples restore the same bullet positions and
lifetimes before each 1/60 s step. Cache-building costs are included. There are
no impacts in this fixture, so every round survives and both implementations do
identical observable work. The reference uses the four frozen bullet methods from
commit 4bb147d; shared narrow-phase and damage helpers remain the same.

Measured on Linux/X11, AMD Ryzen 5 8600G with Radeon 760M, Mesa 26.0.8,
Godot 4.7.2 Compatibility/OpenGL. Median CPU milliseconds:

| Work | Bullets | Reference | Optimized | Reduction |
|---|---:|---:|---:|---:|
| Collision pass | 1,024 | 11.347 | 1.424 | 87.5% |
| Scenery + terrain | 1,024 | 5.100 | 0.951 | 81.4% |
| Ribbon preparation | 1,024 | 1.096 | 0.869 | 20.7% |
| World physics step including ribbons | 1,024 | 13.238 | 2.817 | 78.7% |
| Collision pass | 4,096 | 46.731 | 5.575 | 88.1% |
| Scenery + terrain | 4,096 | 20.425 | 3.744 | 81.7% |
| Ribbon preparation | 4,096 | 4.495 | 3.507 | 22.0% |
| World physics step including ribbons | 4,096 | 54.235 | 11.147 | 79.4% |

The 4,096-round full-step p95 fell from 58.427 to 12.258 ms. Terrain-only ray time
stayed essentially unchanged (0.958 vs 0.954 ms). The benchmark's
reference_aircraft_scan line intentionally times the original all-plane scan in
both runs, as a diagnostic component; optimized candidate lookup is included in
the collision/full-step figures.

These are controlled CPU measurements, not full-game FPS or Android results.
AI, aircraft physics, GPU execution, actual raid timing and hit effects are outside
this benchmark. Gains depend on spatial distribution: aircraft all packed into
one cell or rounds near scenery require more narrow-phase work. Impact particles
and audio are deliberately unchanged and may matter during sustained impact storms.
Both graphical benchmark runs emitted the same four texture-cleanup warnings at
shutdown; no new runtime errors were observed in the paired bullet tests.

## Regression verification

```sh
XDG_DATA_HOME=/tmp/redace-bullet-tests godot --headless --path redace -s tools/test_bullets.gd
# Omit --headless to also exercise actual Compatibility mesh buffer generation.
```

The paired suite checks 31 assertions, including complete per-tick snapshots for
4,096 simultaneous rounds over 30 ticks. It compares positions, velocity, lifetime,
removal order, aircraft health/state, ordered damage calls, group multiplicity,
scenery health, effects, sounds and random draw ordering. Fixtures cover repeated
hits, overlapping aircraft, ownership, hidden/dead/group-zero exclusions, death
mid-pass, strict sphere boundaries, large spheres spanning cells, negative cells,
terrain rays from above/below, rotated/scaled scenery, wrecks, AA bypass, expiration,
map exit and root movement between ticks. Actual vertex/UV/colour buffers are
compared to the reference; both headless and graphical runs passed.

A 30-second simulated Britain autoplay smoke run with --perf also exercised the
new fields during combat (331 active bullets at the 27-second sample). This used
--fixed-fps 60 to advance the diagnostic and is not an FPS benchmark.

Existing collision-damage, collision-management (32 checks), probe detection,
avoidance, Britain aircraft (121 checks), Britain mission/stock isolation,
Extra Options (91), replay menu (211), and video options (526) all passed.
Britain's existing mission test still reports ObjectDB/resource cleanup warnings
at forced exit. These tests do not claim executable-identical replays; see
[collision-parity.md](collision-parity.md) for existing engine/traversal limits.

## Remaining opportunities

Terrain-ray skipping is not justified by this measurement: it was under 2% of the
original full-step cost, and a safe bound must also include mod-added collision
bodies such as Britain's sea. A persistent mesh buffer or instanced ribbon shader
could reduce the remaining rendering preparation, but is a larger rendering change.
Profile real impact-heavy fights and target Android hardware before pursuing either.
