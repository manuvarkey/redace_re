# Mission 12 design brief (user, 11 November 2026)

Verbatim from the user. Implemented 11 November 2026 (IMPLEMENTATION_NOTES, "Mission 12 rework").

### Briefing

The squadron is short of experienced pilots. Today, four young men follow you over the front. Among them is Brenner’s surviving second.

An enemy formation is approaching your patrol. More aircraft have been sighted beyond the lines.

Keep the young pilots together. Bring them home.

**Primary objective:** Bring all four pilots safely across the friendly lines.

**Target duration:** Approximately 6–8 minutes of active gameplay, followed by a 20–30-second closing sequence. These are playtesting targets.

### Opening — The last formation

**Approximate duration: 20–30 seconds.**

Begin airborne, with the four pilots close enough to recognise individually. Retain Brenner’s second’s name and aircraft markings from Mission 11.

The player leads; Brenner’s second flies at the rear.

**HUD:** “Lead the patrol. Keep your pilots together.”

Ahead, a small enemy formation crosses the patrol’s course. Farther away, additional aircraft are visible against the horizon.

**HUD:** “Enemy scouts ahead. More aircraft beyond them.”

Move into the first encounter before formation flying becomes idle travel.

### Encounter 1 — Break the interception

**Enemies: Three scouts approaching from ahead and above.**

One attacks the player. Two dive toward the young pilots.

The rookies defend themselves but struggle to maintain formation. Brenner’s second helps keep them together.

**HUD:** “They are coming through the formation! Protect your pilots.”

The player must break the attackers’ firing opportunities. Damaging an attacker or forcing it into evasive manoeuvres should create useful breathing room.

After the first attack is broken, reveal a larger formation approaching from the battlefield.

**HUD:** “Too many coming. Take the patrol home.”

**Updated objective:** “Cover the withdrawal to friendly lines.”

The rookies turn toward the marked escape route. Surviving enemies remain active, but destroying all three is unnecessary.

### Encounter 2 — Clear the route

**Enemies: Three fresh scouts—two crossing the withdrawal route and one approaching from the rear quarter.**

The crossing pair threatens to intercept the rookies before they reach the next safe stretch. The third tries to occupy the player from behind.

**HUD:** “Two scouts across their path. Clear the way!”

This encounter creates a deliberate choice: fight the immediate threat behind you, or break away to protect the formation ahead.

Brenner’s second guards the rear but cannot hold the attacker indefinitely. Show his situation clearly through a brief warning and his aircraft marker.

**HUD:** “Brenner’s second is holding the rear. Help the others through.”

Place the crossing pair far enough ahead for the player to intercept. Avoid allowing them an unavoidable opening burst against the protected aircraft.

Once the route opens, three rookies move through together. The fourth has become separated while evading an attack and is falling behind. Use combat damage he has suffered and show him displaced from the formation after a defensive turn.

**HUD:** “One pilot is falling behind!”

### Encounter 3 — Return for the straggler

**Enemies: Two fresh scouts converging on the separated pilot.**

Brenner’s second leads the other two rookies toward friendly lines. Their route remains visible, with a progress marker showing their approach to safety.

The player must turn back for the fourth pilot.

**HUD:** “The main group is nearly through. Bring the last man back.”

One attacker settles behind the straggler while the other approaches from the side. Their attacks should be staggered, giving the player a chance to interrupt both through positioning and accurate passes.

The straggler continues toward home instead of circling in the combat area.

**HUD, after the immediate threat is broken:** “He is clear. Stay with him!”

Allow a short regrouping interval. The pilot steadies his aircraft and follows the escape route.

Meanwhile, announce the progress of the leading group individually.

**HUD:** “First pilot across.”

**HUD:** “Second pilot across.”

**HUD:** “Brenner’s second is safe. One still to bring home.”

The player now sees exactly what remains to be achieved.

### Encounter 4 — The final crossing

**Enemies: Four fresh scouts arriving in two separated pairs.**

The last rookie approaches friendly lines. The first pair comes across his route; the second follows from the battlefield.

**HUD:** “Another flight! Keep them off him until he crosses.”

The first pair threatens the rookie directly. The second pressures the player and attempts to follow through if left unopposed.

Separate their arrival sufficiently to give the player an opening to act. The challenge should come from successive threats, rather than four aircraft firing at the protected pilot simultaneously.

The player must:

- Interrupt attacks on the rookie.
- Avoid becoming trapped in a prolonged turning fight.
- Stay close enough to cover his progress.
- Preserve enough health to survive until he reaches safety.

Show the rookie’s remaining distance to the safe boundary. Provide a clear final warning as he approaches it.

**HUD:** “Almost across. Hold them a little longer!”

Once he crosses, he leaves combat and cannot be killed by a stray shot.

**HUD:** “All four are clear.”

**Primary objective complete. Secure campaign completion immediately.**

There is no further kill quota, return flight or survival timer.

### Scripted ending — The turn

**Approximate duration: 20–30 seconds.**

Clearly transition from gameplay into a cinematic: fade the combat HUD and move the camera smoothly. From this point, combat damage cannot produce a failure screen.

**1. The survivors**

Show the four pilots continuing toward their aerodrome. The last rookie catches sight of the others ahead.

A short message appears:

**“All four are clear. Come home.”**

**2. The approaching force**

The camera returns to the Baron.

Beyond him, another formation approaches the withdrawal corridor. Ground positions along the battlefield begin firing.

Establish that these aircraft are approaching from the direction the rookies have just escaped—not appearing suddenly around the player.

**3. The decision**

The Baron banks back toward the battlefield.

Hold the camera behind and slightly above the red aircraft as it turns away from the distant friendly formation.

His turn takes him across the approaching enemy’s path. The nearest scouts turn toward him.

**4. Into the fire**

The camera settles behind the aircraft.

Several enemy aircraft approach at different heights and distances. The nearest make firing passes; others remain silhouettes beyond them. Tracers cross ahead, while ground fire rises from visible positions below.

Build the intensity through movement, sound and depth. Avoid filling the entire screen with indistinguishable aircraft and explosions.

The red aircraft continues into the attack.

**5. The final image**

Incoming fire flashes past. A brief impact jolts the view.

The image gradually blurs; engine and gunfire sounds become muffled. Keep the red aircraft recognisable for a moment before fading to black.

Display:

**“He turned back.”**

Then:

**“They made it home.”**

Do not display “Mission failed,” a death counter or a score penalty.

### Epilogue

The four pilots returned to the aerodrome.

Brenner’s second waited beside his aircraft until the others had landed.

Their commander did not return.

Follow this with the existing burial epilogue. Present the rescue and final turn as the campaign’s fictional conclusion, separately from historical information.

### Encounter and difficulty rules

- Plan for **twelve playable enemy aircraft across four encounters: 3 + 3 + 2 + 4**.
- Keep roughly three enemies applying close pressure at once. In the final encounter, stagger the two pairs.
- Trigger encounters through route progress and combat state. Delay fresh arrivals if surviving enemies already create sufficient pressure.
- Give every group a visible approach and a brief warning.
- Keep all enemies vulnerable during gameplay.
- Make defensive actions useful: interrupted attackers must spend time evading or repositioning before attacking again.
- Avoid making every enemy immediately switch back to the escorted aircraft.
- Keep the rookies moving toward safety. Use route length and encounter spacing to create the intended duration without holding patterns.
- Preserve damage between encounters, while giving protected aircraft enough resilience for the player to recover from a missed interception.
- Show all four pilots’ condition and identify the one currently under attack.
- Failure occurs if the player or any protected pilot is lost before the final crossing.
- Tune difficulty through attack angles, timing and coordination before increasing health or enemy numbers.
- Keep the cinematic force separate from the playable encounter budget. Distant aircraft and ground-fire effects can provide scale without simulating a large additional battle.

**The player earns the ending by completing a difficult rescue. The scripted sequence then closes the Baron’s story without taking that achievement away.**
