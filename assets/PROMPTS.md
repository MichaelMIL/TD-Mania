# Gemini asset prompts for TD Mania

Save each result in this folder under the exact filename in its heading. PNG
with transparency, square canvas. The game picks them up on next launch — no
reimport needed. Any file you skip keeps its built-in vector art, so you can
add them one at a time.

## Shared style line (paste into every prompt)

> Clean top-down 2D game asset, orthographic straight-down view, flat vector
> shading with soft cel highlights, bold readable silhouette, dark-forest
> fantasy-tech palette, no text, no watermark, no drop shadow baked in,
> centered subject, transparent background, PNG.

---

## Ground tiles (seamless, 128x128, NO transparency needed)

Each tile also accepts a per-level variant that overrides the generic one:
add `_verdant`, `_riverfork`, `_ashen` or `_frostbite` before the extension
(e.g. `tile_grass_ashen.png` for ash-grey ground). The palette notes for each
map are in the level table in `README.md`.

**`tile_grass.png`**
> Seamless tileable 128x128 top-down grass tile for a tower defense map. Dark
> mossy green, subtle blade texture and a few tiny stones, low contrast so game
> pieces stay readable on top. Edges must tile seamlessly on all four sides. No
> lighting gradient, no vignette. Flat vector game-art style.

**`tile_path.png`**
> Seamless tileable 128x128 top-down dirt path tile for a tower defense map.
> Warm packed brown earth with faint wheel ruts and small pebbles, slightly
> lighter than surrounding grass. Edges tile seamlessly on all four sides. Flat
> vector game-art style, no lighting gradient.

**`tile_water.png`** (128x128)
> Seamless tileable 128x128 top-down water tile for a tower defense map. Deep
> teal-blue surface with soft lighter ripple crests, calm and readable, no
> shoreline or foam (the game draws shorelines itself). Edges tile seamlessly on
> all four sides. Flat vector game-art style.

**`tile_rock.png`** (128x128)
> Top-down 128x128 tile of impassable grey boulders and rubble for a tower
> defense map, two or three chunky rocks with flat cel shading, slightly raised
> look, dark ground visible around them. Reads clearly as "cannot build here".
> Flat vector game-art style.

---

## Towers

Each tower is TWO images: a static `_base` and a `_gun` turret. **The turret
must point RIGHT (toward 0°/3 o'clock)** — the game rotates it to aim — and
its rotation pivot is the image center, so keep the turret's pivot point in the
middle of the canvas with the barrel extending right.

**`tower_gun_base.png`** (256x256)
> Top-down straight-down view of a small machine-gun tower base for a tower
> defense game: circular armored steel platform with bolted rim, cyan energy
> accents, sandbag ring at the edge. No turret, no barrel — base only.
> Transparent background, centered, fills the canvas.

**`tower_gun_gun.png`** (256x256)
> Top-down straight-down view of a twin-barrel autocannon turret only, barrels
> pointing RIGHT toward the right edge of the frame, rotation pivot exactly at
> the image center, cyan and gunmetal, ammo drum on top. No base platform.
> Transparent background.

**`tower_cannon_base.png`** (256x256)
> Top-down straight-down view of a heavy mortar tower base: thick octagonal
> stone-and-iron platform with orange warning stripes and rivets, small shell
> crates at the rim. No turret. Transparent background, centered.

**`tower_cannon_gun.png`** (256x256)
> Top-down straight-down view of a stubby wide-bore mortar turret only, thick
> barrel pointing RIGHT, muzzle brake at the tip, rotation pivot at image
> center, burnt-orange and dark iron. No base. Transparent background.

**`tower_frost_base.png`** (256x256)
> Top-down straight-down view of a cryo tower base: circular pale-blue metal
> platform ringed with frost crystals and coolant pipes, thin ice rime on the
> edge. No turret. Transparent background, centered.

**`tower_frost_gun.png`** (256x256)
> Top-down straight-down view of a frost projector turret only, tapered nozzle
> with a glowing ice-blue crystal at the muzzle, pointing RIGHT, rotation pivot
> at image center, pale blue and white. No base. Transparent background.

**`tower_tesla_base.png`** (256x256)
> Top-down straight-down view of a tesla tower base: circular dark platform
> with violet glowing runes, copper coil windings and cable conduits around the
> rim. No emitter arm. Transparent background, centered.

**`tower_tesla_gun.png`** (256x256)
> Top-down straight-down view of a tesla emitter arm only, two prongs forming a
> spark gap at the RIGHT end with a violet electric arc between them, rotation
> pivot at image center, copper and violet. No base. Transparent background.

**`tower_tide_base.png`** (256x256)
> Top-down straight-down view of a tower base built ON WATER: square wooden and
> steel deck platform on stilts with a cyan railing, wet planks, small waves
> lapping at the corners. No turret. Transparent background, centered.

**`tower_tide_gun.png`** (256x256)
> Top-down straight-down view of a high-pressure water cannon turret only,
> wide-bore nozzle pointing RIGHT with a cyan glow at the muzzle, brass fittings
> and hoses, rotation pivot at image center. No base. Transparent background.

**`tower_airfield_base.png`** (256x256)
> Top-down straight-down view of a tiny military airfield pad for a tower
> defense game: square concrete apron with a short runway strip across it,
> dashed white centre line, threshold bars, olive-green markings and a fuel
> drum in one corner. Empty runway, no aircraft. Transparent background.

**`tower_airfield_gun.png`** (256x256)
> Optional: leave this file out to keep the drawn runway. If provided, a
> top-down parked bomber silhouette pointing RIGHT, rotation pivot at image
> center, transparent background.

**`tower_helipad_base.png`** (256x256)
> Top-down straight-down view of a small helipad: square concrete pad with a
> painted white circle and bold letter H, amber perimeter markings and a red
> corner beacon light. Empty pad, no helicopter. Transparent background.

**`tower_helipad_gun.png`** (256x256)
> Optional: leave this file out to keep the drawn pad markings. If provided, a
> top-down parked gunship silhouette pointing RIGHT, rotation pivot at image
> center, transparent background.

**`tower_marksman_base.png`** (256x256)
> Top-down straight-down view of a sniper nest tower base: circular sandbagged
> platform with a camouflage net edge and olive-green markings, ammo case in one
> corner. No rifle. Transparent background, centered.

**`tower_marksman_gun.png`** (256x256)
> Top-down straight-down view of a long anti-materiel rifle on a tripod, barrel
> pointing RIGHT with a muzzle brake and a scope on top, rotation pivot at image
> center, olive green and gunmetal. No base. Transparent background.

**`tower_flame_base.png`** (256x256)
> Top-down straight-down view of a flamethrower emplacement base: circular
> scorched steel platform with two fuel tanks and hose coils, orange hazard
> stripes. No nozzle. Transparent background, centered.

**`tower_flame_gun.png`** (256x256)
> Top-down straight-down view of a flame projector turret only, wide flared
> nozzle pointing RIGHT with a small pilot flame at the tip, fuel hose trailing
> back, rotation pivot at image center, burnt orange and soot black. No base.
> Transparent background.

**`tower_mortar_base.png`** (256x256)
> Top-down straight-down view of a heavy artillery emplacement base: square
> concrete pad with sandbag walls, shell crates and a range dial, brown and grey.
> No mortar tube. Transparent background, centered.

**`tower_mortar_gun.png`** (256x256)
> Top-down straight-down view of a short wide-bore mortar tube seen from above,
> muzzle pointing RIGHT, thick recoil collar and bipod, rotation pivot at image
> center, taupe brown steel. No base. Transparent background.

**`tower_torpedo_base.png`** (256x256)
> Top-down straight-down view of a torpedo battery built ON WATER: square steel
> deck on pontoons with a cyan railing and two torpedo cradles, wet metal. No
> launcher tubes. Transparent background, centered.

**`tower_torpedo_gun.png`** (256x256)
> Top-down straight-down view of a twin torpedo launcher, two parallel tubes
> pointing RIGHT with torpedo noses visible at the openings, rotation pivot at
> image center, pale cyan and steel. No base. Transparent background.

**`tower_command_base.png`** (256x256)
> Top-down straight-down view of a command post: circular concrete bunker roof
> with antenna masts around the rim, cable runs, a small landing light, white and
> pale grey with subtle blue glow accents. No radar dish. Transparent background.

**`tower_command_gun.png`** (256x256)
> Optional: leave this file out to keep the drawn radar sweep. If provided, a
> top-down radar dish pointing RIGHT, rotation pivot at image center,
> transparent background.

---

## Aircraft

Both fly nose-**RIGHT** and are rotated in code. Keep them clean and compact;
they are drawn about 45 px long and the game adds its own drop shadow.

**`unit_plane.png`** (192x192)
> Top-down straight-down view of a small twin-wing propeller bomber for a
> tower defense game, nose pointing RIGHT, olive-green fuselage with a glass
> canopy, straight wings with two bomb pylons, no shadow, no background.
> Flat vector game-art style, transparent PNG, centered.

**`unit_heli.png`** (192x192)
> Top-down straight-down view of a small attack helicopter, nose pointing
> RIGHT, amber-orange fuselage with a glass canopy, stub weapon wings, long
> tail boom with a tail rotor, MAIN ROTOR OMITTED (the game animates the
> blades), no shadow, no background. Flat vector game-art style, transparent
> PNG, centered.

---

## Enemies

All creeps are seen straight down and must **face RIGHT**. Keep them chunky and
color-coded — they are small on screen (roughly 20-50 px tall).

**`enemy_grunt.png`** (192x192)
> Top-down straight-down view of a small green goblin foot-soldier creep for a
> tower defense game, facing RIGHT, round hunched body, tiny helmet and rusty
> shoulder plate, stubby arms. Bright lime-green, chunky readable silhouette.
> Transparent background, centered.

**`enemy_runner.png`** (192x192)
> Top-down straight-down view of a fast lean scout creep, facing RIGHT, sleek
> yellow carapace, swept-back spines suggesting speed, long thin legs.
> Bright amber-yellow. Transparent background, centered.

**`enemy_swarm.png`** (192x192)
> Top-down straight-down view of a tiny insectoid swarmling creep, facing
> RIGHT, small round pink-magenta body, four thin legs, single glossy eye.
> Very simple and readable at small size. Transparent background, centered.

**`enemy_tank.png`** (192x192)
> Top-down straight-down view of a heavily armored slow brute creep, facing
> RIGHT, wide slate-grey riveted plate armor shell, thick stubby legs, small
> head sunk into the shoulders. Reads as armored and heavy. Transparent
> background, centered.

**`enemy_boss.png`** (256x256)
> Top-down straight-down view of a massive crimson behemoth boss creep for a
> tower defense game, facing RIGHT, cracked obsidian armor with glowing red
> lava seams, hulking shoulders, horned head, four heavy legs. Menacing and
> clearly larger than other creeps. Transparent background, centered.

---

## Projectile

**`shot.png`** (64x64)
> Small glowing round energy projectile for a top-down game, bright white-hot
> core with a soft colorless outer glow (the game tints it per tower), no
> motion trail, no background. Transparent PNG, centered.

---

## Towers added since the first pass

Same two-file pattern as the towers above: a `_base` that never rotates and a
`_gun` that the game turns to face its target. Leave the gun pointing right
(east) at 0°.

**`tower_tarpit_base.png`** (256x256)
> Top-down circular pit of black tar set in a stone kerb, viscous surface with
> slow glossy bubbles, a few reeds at the rim. No mechanism, no barrel — this
> tower has no gun.

**`tower_tarpit_gun.png`** (256x256)
> Top-down slow bubble rising from black tar, a single glossy dome with a thin
> highlight ring, centered, small. Reads as motion in the pit beneath it.

**`tower_mine_base.png`** (256x256)
> Top-down mine head: a square timber platform over a shaft, ore cart rails
> crossing it, small heap of gold ore glinting at one corner. Industrial, warm
> brown and brass.

**`tower_mine_gun.png`** (256x256)
> Top-down winch wheel with a taut cable, brass and dark iron, pointing right.

**`tower_shock_base.png`** (256x256)
> Top-down heavy iron drum sunk into a stone ring, thick rivets, concentric
> grooves in the ground around it as if the earth has been hammered.

**`tower_shock_gun.png`** (256x256)
> Top-down piston hammer head seen from above, blunt iron block on a short arm
> pointing right, glowing amber seam where it strikes.

**`tower_ballista_base.png`** (256x256)
> Top-down timber siege platform, cross-braced beams, a rack of spare bolts
> along one edge, iron fittings.

**`tower_ballista_gun.png`** (256x256)
> Top-down ballista arms and rail seen from above, two curved limbs with a
> drawn string and a loaded bolt pointing right, dark timber and steel.

**`tower_laser_base.png`** (256x256)
> Top-down white ceramic emitter housing with cooling fins and a cable coil,
> clean high-tech, faint magenta glow in the seams.

**`tower_laser_gun.png`** (256x256)
> Top-down focusing barrel with three lens rings, magenta core light, pointing
> right, thin and precise.

**`tower_wavegun_base.png`** (256x256)
> Top-down floating pontoon of riveted blue-grey metal, water sloshing over the
> rim, mooring cleats at the corners. Sits on water.

**`tower_wavegun_gun.png`** (256x256)
> Top-down wide-mouthed water cannon seen from above, flared nozzle pointing
> right, pale blue surge curling at the mouth.

---

## Enemies added since the first pass

All 192x192 unless noted, transparent, seen straight down, facing right.

**`enemy_brood.png`**
> Top-down bloated purple carrier creature, translucent sac on its back with
> smaller shapes visible inside, six short legs. Reads as "this will split".

**`enemy_mender.png`**
> Top-down pale green robed creature holding a glowing vial above itself, soft
> healing aura ring. Clearly a support unit, not a fighter.

**`enemy_warden.png`**
> Top-down heavily armoured walker, overlapping steel plates like a tortoise
> shell, narrow visor slit, slate grey with cold blue trim. Reads as slow and
> nearly impervious.

**`enemy_ashwalker.png`**
> Top-down creature made of cracked charcoal with molten orange fissures,
> smouldering shoulders, no visible eyes. Reads as already on fire.

**`enemy_bolt.png`**
> Top-down lean yellow sprinter, streamlined body with swept-back spines and
> crackling energy at its heels. Reads as very fast.

**`enemy_thief.png`**
> Top-down hunched violet figure in a hood with a bulging coin pouch, one hand
> clutching gold. Reads as a pickpocket.

**`enemy_moth.png`** (flying)
> Top-down pink-red moth with wide patterned wings and glowing ember specks
> along the body, seen from directly above with wings spread. Drawn as if
> airborne — no legs touching ground.

**`enemy_drake.png`** (flying, 224x224)
> Top-down armoured indigo drake seen from directly above, plated back, broad
> ribbed wings spread wide, short tail. Heavy and mechanical rather than
> organic.

**`enemy_titan.png`** (320x320)
> Top-down colossal armoured brute, dark iron plating with red glowing joints,
> four heavy limbs, deliberately larger and nastier than the Behemoth boss.

---

## Per-level tile variants

Every tile accepts a variant named after the level id, which wins over the
generic file: `tile_grass_<id>.png`, `tile_path_<id>.png`,
`tile_water_<id>.png`, `tile_rock_<id>.png`. The ids are in `TDData.LEVELS`
(`verdant`, `meadow`, `highlands`, `fernhollow`, `riverfork`, `crossroads`,
`saltmarsh`, `desert`, `ashen`, `obelisk`, `frostbite`, `glacier`, `coast`,
`twingates`, `junction`, `ruins`, `delta`, `comb`, `pipeworks`,
`convergence`), and each level's `palette` entry gives the colours its
vector art currently uses — a good brief for the sprite.
