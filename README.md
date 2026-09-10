# TD Mania

A wave-based tower defense game for **Godot 4.7**: twenty battlegrounds in
five areas across four difficulty tiers — including maps with several spawn
lanes and bases — three save slots, twelve towers (including water-only, aircraft-launching
and support ones), per-tower upgrade tracks, a drag-and-drop build palette,
account-level progression that unlocks the roster, a coin-funded tech tree, and
endless scaling waves. Everything — maps, HUD, towers, creeps, aircraft —
is built in code with vector drawing, so the project runs with no imported art.
Drop PNGs into `assets/` and they take over automatically (see [Art](#art)).

## Run it

```bash
godot --path .          # save slots -> level select -> play
godot -e --path .       # open in the editor
```

## Save slots

The title screen offers three independent slots. Each keeps its own account
level, XP, coins, tech tree and per-map records, and the game remembers which
one you last played. A slot card shows its level, coins, maps played, best
wave and tech ranks; erasing takes two clicks. A save from before slots
existed is migrated into slot 1 automatically. Switch slots any time with the
**Slot N** button on the menu.

## Sound

All audio is **synthesised at startup** — shots, explosions, creep deaths,
leaks, building, upgrading, selling, wave horns, boss growls, UI ticks, a
continuous beam hum and a looping ambient bed. Nothing ships as an asset file,
so the project still runs from a clean checkout with no downloads.

The **Vol** button in the top bar (or per-slot settings) cycles full → quiet →
muted, and the choice is saved with the slot. Beams are reference-counted, so
ten Teslas share one hum rather than ten, and repeated shots inside 35 ms are
dropped and pitch-jittered so a wall of Gunners does not turn into a buzzsaw.

To replace any sound with a real recording, drop `assets/audio/<name>.wav`
into the project — `scripts/audio.gd` prefers a file over its generated
version. The names are the keys in `Audio.bank`: `shot_gun`, `shot_cannon`,
`shot_light`, `explosion`, `death`, `leak`, `build`, `upgrade`, `sell`,
`wave_start`, `wave_clear`, `game_over`, `boss`, `click`, `beam`, `music`.

## Progression

Every run pays out **XP** and **coins**, scaled by waves survived, score and
the map's difficulty tier. Leaving to the menu banks the run too, so a good
attempt is never wasted — but a run only ever pays once.

**Account level** unlocks the roster. You start with the Gunner and Cannon;
the rest arrive as you level, and a handful of advanced upgrade tracks are
gated the same way:

| Level | Unlocks |
| --- | --- |
| 1 | Gunner, Cannon |
| 2 | Frost · Gunner's Long Barrel |
| 3 | Marksman |
| 4 | Tide Caller · Cannon's Rangefinder |
| 5 | Tesla · Marksman's Cycle Action |
| 6 | Flamethrower · Frost Cloud · Tsunami |
| 7 | Airfield · Arc Splitter |
| 8 | Torpedo Battery · Napalm |
| 9 | Mortar · Second Bomber · Spread Tubes |
| 10 | Helipad · Spotter Drone |
| 11 | Command Post |
| 12 | Wing Escort · Comms Array |

The menu shows your level, XP bar, coin balance and what unlocks next.

**Tech tree** (menu → Tech Tree) is where coins are spent. It has two parts,
picked from the rail on the left:

**Doctrine** — three branches of four nodes that apply to every tower you
build. Each node needs the one above it maxed before it opens:

| Firepower | Economy | Support |
| --- | --- | --- |
| Munitions — +6% damage | War Chest — +30 starting gold | Fortifications — +2 starting lives |
| Optics — +6% range | Bounty Hunter — +8% kill gold | Cryogenics — +5% slow |
| Drill Sergeant — +5% fire rate | Salvage Crew — +8% sell refund | Air Doctrine — +10% aircraft damage |
| Blast Engineering — +12% blast radius | Rapid Deployment — -6% build cost | Overtime — +30% early-wave bonus |

**Tower upgrades** — one page per tower holding that tower's upgrade tracks.
Coins here buy the *right* to install a rank; gold installs it on an
individual tower during a match. So a rank you have not unlocked shows
"unlock 14 c" in the match HUD, and one you have unlocked shows its gold
price. Unlocks are gated by account level and by the tower's own prerequisites
(Long Barrel needs Heavy Rounds 2, and so on).

Everything here is permanent and applies on every map. The screen also has a
two-step **Reset all progress** button.

## How to play

| Input | Action |
| --- | --- |
| **Drag a palette card onto the map** | Build there — the map shows every cell that tower accepts |
| Click a card | Arm a tower, then click a cell to build |
| Left click | Build the armed tower / select a placed tower |
| Right click, `Esc` | Cancel building or deselect |
| Upgrade buttons (bottom bar) | Install an unlocked rank on this tower with gold |
| `U` | Quick-install: the cheapest unlocked rank |
| `T` / Target button | Cycle the selected tower's targeting priority |
| Click a tower | See its stats, ranks, kills and damage dealt |
| `A` / Auto button | Toggle auto-start for waves |
| `X` | Sell the selected tower (70% refund of everything invested) |
| `Space` | Start the next wave early — the time left becomes bonus gold |
| `P` | Pause |
| `F` | Cycle game speed (1x / 2x / 3x) |
| `R` | Restart after a loss |
| `M` | Back to the level select menu |

Your starting gold and lives come from the map's difficulty tier. Creeps that
reach the base cost lives (a Tank costs 2, a Behemoth 6). Waves never stop —
the goal is to get as deep as possible, and your best wave is saved per map and
shown on the menu.

Enemy health grows about 12.5% per wave (plus a small extra ramp after wave 12)
scaled by the tier, while your income comes from kills, a wave-clear bonus, and
the bonus for starting a wave early.

### Areas

The twenty maps are grouped into five collapsible areas of four, each with its own
banner on the menu (click the +/- to fold one away). Maps unlock with account
level — Verdant Pass at level 1 through Convergence at 18 — and a locked card
shows the level it needs instead of a Play button. Areas whose maps are all
still locked start collapsed and show when they open: **The Greenlands** (forest, grassland, moor), **The Riverlands** (lakes,
autumn woods, the twin gates), **The Wastes** (dunes, lava fields, ruins),
**The Frozen Coast** (sea ice, cliff roads, the junction) and **The Iron
Delta** (mangrove swamp and foundry country). Each banner shows the area's
difficulty span and how many of its maps you have played on this save.

### Multi-lane maps

Three maps send creeps down more than one road:

| Map | Area | Lanes |
| --- | --- | --- |
| Twin Gates | Riverlands | 2 sources, 2 separate bases |
| Fork Junction | Frozen Coast | 2 sources whose lanes cross, 2 bases |
| Convergence | Iron Delta | 3 sources funnelling into one base |
| Pipeworks | Iron Delta | 2 sources of very different length, 2 bases |

Waves alternate between the lanes: roughly every other wave comes down a
single spawn (rotating which one), and the rest come down all of them at once.
Boss waves always use every lane. The status line names the spawn, and the
route preview only lights the lanes that wave will actually use.
Lanes are colour-coded — the spawn portal, the route preview line and the base
marker all share a colour. The single-road difficulty bands do not apply to
these maps (two short lanes are harder than one long road); instead the verify
suite requires every lane to be at least 18 cells long with at least 20 firing
positions of its own, so no lane is undefendable.

### Wave readout

The top strip of the bottom bar names what is coming during every build
phase:
`Wave 13 incoming · 19 Grunt · 8 Runner · 3 Tank · 2 Brood Mother · 2 Mender ·
1 Warden · 3 Bolt`, each chip carrying that creep's colour, with **BOSS WAVE**
called out in red. Underneath, the kinds that need a specific answer explain
themselves — "Mender: Heals every wounded creep around it. Kill it first."

The counts come from the same `_build_wave()` the spawner uses, so the readout
cannot drift from what actually arrives; the verify suite checks them against
the spawn list wave by wave.

### Route preview

At the start of every wave the roads light up: a flowing dashed line with
arrows runs along each active lane in that lane's colour, bright for about four
seconds and then settling to a quiet pulse during the build phase. On
multi-lane maps this is how you see which way the wave is coming.

### Levels and difficulty

Every map belongs to a difficulty tier, shown as a coloured chip on its menu
card and next to the map name in the top bar during play. The tier sets the
enemy scaling and your starting economy — and the **road itself gets harder**
with the tier: higher tiers have shorter routes (less time to shoot) and fewer
buildable cells beside the path (fewer places to shoot from).

| Tier | Road length | Firing positions |
| --- | --- | --- |
| Easy | 65-89 cells | 78-103 |
| Normal | 46-53 cells | 67-75 |
| Hard | 37-44 cells | 52-60 |
| Brutal | 20-35 cells | 24-49 |

`dev/dev_verify.tscn` measures both from the real terrain and fails if the
bands ever overlap, so a new map cannot quietly break the ladder.

| Tier | Enemy HP | Enemy speed | Starting gold | Lives |
| --- | --- | --- | --- | --- |
| Easy 1/4 | ×0.85 | ×0.96 | 250 | 25 |
| Normal 2/4 | ×1.00 | ×1.00 | 220 | 20 |
| Hard 3/4 | ×1.20 | ×1.04 | 210 | 18 |
| Brutal 4/4 | ×1.40 | ×1.08 | 200 | 16 |

Each map also has its own theme — palette plus scattered props (trees, grass
tufts, reeds, autumn leaves, lava cracks, snow, vines, foundry plates) — so no
two look alike:

| Level | Tier | Theme | Road shape | Surface | Ground | Water |
| --- | --- | --- | --- | --- | --- | --- |
| Verdant Pass | Easy | Forest | five-switchback serpentine | dirt | checker | calm |
| Meadow Loop | Easy | Savanna | inward spiral, 89 cells | gravel | dots | calm |
| Windward Highlands | Easy | Highlands | figure-eight that crosses itself | stone | stripes | calm |
| Riverfork | Normal | River Valley | loop right around the lake | mud | checker | surf |
| Crossroads | Normal | Autumn Wood | two diagonals crossing twice | brick | flat | calm |
| Desert Wash | Normal | Desert | dune chevrons | sand ripples | dunes | calm |
| Ashen Wastes | Hard | Volcanic | diagonal terrace descent | glowing embers | flat | murk |
| Frostbite Bay | Hard | Arctic | weave between frozen inlets | cracked ice | tiles | floes |
| Old Ruins | Hard | Ruins | labyrinth of collapsed walls | paved slabs | tiles | calm |
| Serpent Delta | Brutal | Swamp | one long diagonal S | boardwalk | dots | murk |
| Iron Comb | Brutal | Foundry | three switchback teeth | rails | tiles | murk |
| Coastal Cliffs | Brutal | Coast | single diagonal plunge, 20 cells | planks | flat | surf |
| Fernhollow | Easy | Fern Hollow | five switchbacks through a damp hollow | flagstone | dots | calm |
| Saltmarsh | Normal | Saltmarsh | duckboard zigzag over tidal flats | duckboard | stripes | surf |
| Obelisk Field | Hard | Obelisks | short diagonal cut between standing stones | clinker | flat | murk |
| Glacier Run | Brutal | Glacier | one long slide down the glacier face | crystal | tiles | floes |
| Pipeworks | Brutal | Pipeworks | **two lanes**, one long and one short | conduit | dunes | murk |

Roads may run straight **or at 45 degrees**, which is what makes the spirals,
chevrons, X-crossings and diagonal descents possible; the terrain builder
walks either kind cell by cell and the verify suite rejects any other angle.

No two maps share a road surface, and each has its own palette, prop set
(trees, grass, reeds, leaves, lava cracks, snow, vines, foundry plates,
heather, cacti, broken columns, driftwood) and colour wash, so they read as
different places at a glance.

Terrain decides what you can build where: **ground** takes land towers,
**water** takes only the Tide Caller and Torpedo Battery, and **rock** and the
**path** take nothing.

### Towers

Drag a card from the palette on the right onto the map. While a tower is armed,
every cell it can legally occupy is outlined — handy for the water-only ones.

| Tower | Cost | Lv | Placement | Role |
| --- | --- | --- | --- | --- |
| Gunner | 60 | 1 | Ground | Cheap, fast single-target damage |
| Cannon | 115 | 1 | Ground | Slow lobbed shells with splash — the answer to swarms |
| Frost | 95 | 2 | Ground | Light damage plus a strong slow in a small area |
| Tar Pit | 110 | 4 | Ground | Fires nothing; everything inside the pit wades and slows |
| Tesla | 175 | 5 | Ground | Continuous beam, damage per second, ignores armor |
| Marksman | 190 | 3 | Ground | Very long range, armor-piercing rounds that bore through a target |
| Flamethrower | 130 | 6 | Ground | Short cone; roasts several creeps at once and leaves them burning |
| Shockwave | 170 | 8 | Ground | Slams the ground on a timer, hitting everything around it — no aiming |
| Mortar | 260 | 9 | Ground | Map-wide artillery with a heavy blast and a dead zone up close |
| Ballista | 200 | 10 | Ground | Looses bolts at several creeps at once, each skewering the line behind it |
| Focus Laser | 230 | 12 | Ground | Beam that bores harder the longer it stays on one creep |
| Gold Mine | 150 | 6 | Ground | Fires nothing; pays gold at the end of every wave |
| Tide Caller | 150 | 4 | **Water only** | Long-range torrents that splash and slow |
| Torpedo Battery | 180 | 8 | **Water only** | Torpedoes run in a line and hit everything they pass |
| Wave Cannon | 190 | 14 | **Water only** | Breaks a wave that shoves creeps back down the road |
| Airfield | 210 | 7 | Ground | Launches a bomber that bombs the leaders and lands to rearm |
| Helipad | 240 | 10 | Ground | Sends a gunship that hovers and strafes until out of ammo |
| Command Post | 200 | 11 | Ground | Fires nothing; buffs damage and fire rate of towers in its radius |

Eighteen towers, so the build palette scrolls. Towers are placed by dragging a
card onto the map (or clicking the card, then a cell) — there are no tower
hotkeys.

Towers target the enemy furthest along the path. The Mortar cannot hit anything
inside its dead zone (drawn in red when selected), so it wants a spot back from
the action. Air towers ignore line of sight entirely: their aircraft take off,
attack anything inside a wide operating radius, then return to the pad, which
frees the squadron slot for the next sortie. Command Post auras deliberately do
**not** stack — the strongest post covering a tower wins.

### Targeting

Every attacking tower has its own targeting priority, cycled with the
**Target** button or `T`: **First** (closest to your base, the default),
**Last** (the newest arrival), **Weakest** / **Strongest** (smallest or largest
health pool), **Lowest HP** / **Highest HP** (most wounded or healthiest).
Chaining beams and aircraft follow their tower's choice too.

### Auto-start

The **Auto** button (or `A`) calls each wave in as soon as the previous one is
cleared, banking the early-start bonus gold automatically. It always starts
**off** at the beginning of a run, so every match is a fresh decision. The in-game top bar also shows your coin balance and what the current
run has earned so far.

### Upgrades

Each tower has its own set of **upgrade tracks**, bought rank by rank in the
tech tree with coins. Tracks are chosen to suit the tower: a Gunner tunes damage, feed
rate and barrel length, a Mortar tunes shell size, blast radius, loading speed
and its dead zone, a Helipad tunes gun, ammo, rotors and squadron size. Coin costs rise 60% per rank in a track. Selling a tower refunds 70% of its
build price — upgrades are account property, so they are never lost.

Tracks form a **small tree per tower**: two open immediately and the rest sit
behind ranks of another track (a Gunner's Long Barrel needs Heavy Rounds 2, an
Airfield's Second Bomber needs Ground Crew 2, and so on), on top of the
account-level gate. Both the tech tree and the match HUD say exactly what is
blocking a track.

A track marked `*` unlocks a **capstone** at its final rank — a behaviour
change, not just numbers. Hover any upgrade button and the bar spells out what
one rank does in words *and* in real numbers for that tower ("Heavy Rounds 1/4
— +22% damage per rank · This rank: Damage 13 -> 16 · Cost $42"), including
which capstone the last rank unlocks.

Upgrades are visible on the tower itself, not just in the numbers: barrels
lengthen and thicken, muzzles widen, extra tubes appear, coils and frost
crystals multiply, aircraft pads gain bombs, ammo boxes and a second machine,
Command Posts grow antenna masts, and the footing gains a plate, then bolts,
then an outer ring as the total investment rises.

| Tower | Tracks (ranks) | Capstones |
| --- | --- | --- |
| Gunner | Heavy Rounds (4), Feed System (4), Long Barrel (3) | Sabot Rounds — armor piercing; Twin Barrels — 2 shots per volley |
| Cannon | Heavy Shells (4), Wide Blast (4), Auto Rammer (3), Rangefinder (3) | Siege Charge — armor piercing; Cluster Munitions — secondary blasts |
| Frost | Cryo Core (4), Coolant Tanks (4), Chill Damage (3), Frost Cloud (3) | Deep Freeze — 75% slow; Shatter — +80% vs chilled |
| Tesla | Overcharge (4), Arc Splitter (3), Coil Array (3) | Ion Storm — hotter arcs |
| Marksman | Match Barrel (4), Scope (4), Cycle Action (3) | Armor Breaker — bores through one more enemy |
| Flamethrower | Fuel Mix (4), Wide Nozzle (3), Napalm (3) | Firestorm — longer cone |
| Mortar | Big Shells (4), Wide Blast (3), Auto Loader (3), Spotter Drone (2) | Bunker Buster — armor piercing |
| Tide Caller | Pressure Jets (4), Riptide (3), Tsunami (4) | Undertow — 65% slow |
| Torpedo Battery | Warheads (4), Spread Tubes (3), Loading Gear (3) | Sea Lance — armor piercing |
| Airfield | Ground Crew (4), Bomb Racks (3), Heavy Payload (3), Second Bomber (1) | Carpet Bombing — every bomb blasts wider |
| Helipad | Autocannon (4), Ammo Belts (3), Uprated Rotors (3), Wing Escort (1) | — |
| Command Post | Doctrine (3), Logistics (3), Comms Array (3) | — |

### Enemies

Twelve kinds walk the road, and most of them exist to punish a one-note
defence:

| Enemy | From | What it does |
| --- | --- | --- |
| Grunt | 1 | The baseline creep |
| Runner | 4 | Fast and fragile |
| Swarmling | 6 | Arrives in packs — splash food |
| Bolt | 6 | Sprints in bursts, crossing kill zones between volleys |
| Brood Mother | 7 | Bursts into three swarmlings when killed |
| Tank | 6 | 5 flat armor, slow |
| Ashwalker | 8 | Cannot be slowed or set alight — Frost and Tar Pits do nothing |
| Mender | 9 | Heals every wounded creep around it; kill it first |
| Cutpurse | 10 | Very fast, and steals gold if it reaches your base |
| Warden | 12 | 15 flat armor — only armor-piercing fire really hurts it |
| Behemoth | every 10th | Boss with an escort |
| Titan | 20, 40… | Late boss that breaks into two Wardens when it falls |

Enemy health scales ~12.5% per wave with a small extra ramp after wave 12, and
armor subtracts flat damage from every hit — which is why armor-piercing
capstones, Tesla and the Marksman matter later on.

## Art

All drawing falls back to vector primitives, but `scripts/art.gd` checks
`assets/` first for a matching `.png`, `.webp`, or `.jpg` and uses it instead.
Images are loaded straight off disk, so adding files needs no reimport — just
restart the game. Filenames it looks for:

```
assets/tile_grass.png          seamless buildable ground
assets/tile_path.png           seamless creep path
assets/tile_water.png          seamless water (replaces the animated surface)
assets/tile_rock.png           unbuildable rubble
assets/tower_gun_base.png      top-down tower base (transparent)
assets/tower_gun_gun.png       turret, barrel pointing RIGHT (rotated in code)
assets/tower_cannon_base.png   ... same _base / _gun pair for every tower:
assets/tower_cannon_gun.png    cannon, frost, tesla, marksman, flame, mortar,
                               tide, torpedo, airfield, helipad, command
assets/enemy_grunt.png         top-down creep, facing RIGHT, transparent
assets/enemy_runner.png
assets/enemy_swarm.png
assets/enemy_tank.png
assets/enemy_boss.png
assets/unit_plane.png          bomber seen from above, nose pointing RIGHT
assets/unit_heli.png           gunship seen from above, nose pointing RIGHT
assets/shot.png                small projectile blob
```

Tiles also accept a per-level variant that wins over the generic file:
`tile_grass_verdant.png`, `tile_water_frostbite.png`, `tile_path_ashen.png`,
and so on, using the level ids `verdant`, `meadow`, `riverfork`, `crossroads`,
`ashen`, `frostbite`, `delta`, `comb`. Per-level tiles replace that map's
procedural theme colours; the scattered props still draw on top.

Turret and aircraft sprites must point **right** (0°) because the code rotates
them to face the target. Enemy and tile sprites are drawn centred and scaled to fit, so
exact pixel sizes are flexible; square, power-of-two images look best.

## Layout

```
main.tscn                 the save-slot screen (main scene)
menu.tscn                 level select
game.tscn                 one Node2D with game.gd; every other node is code-built
tech.tscn                 the tech tree screen
scripts/menu.gd           title screen, account bar, level cards, per-map records
scripts/progress.gd       save slots, XP/level, coins, tech ranks, records, payouts
scripts/slots.gd          save-slot title screen
scripts/tech.gd           tech tree screen
scripts/level_preview.gd  map thumbnails drawn from the level data
scripts/game.gd           state, waves, terrain, placement, drag and drop, HUD, and
                          the service locator towers use (find_target,
                          find_targets, explode, aura_at, fx_*)
scripts/data.gd           grid metrics, level list, tower/enemy tables, upgrade tracks
scripts/tower.gd          targeting, firing, beams, upgrade tracks, auras, squadrons
scripts/tower_icon.gd     procedural tower portraits for the build palette
scripts/aircraft.gd       bomber and gunship flight, bomb runs, strafing runs
scripts/enemy.gd          path walking, armor/slow handling, health bars
scripts/projectile.gd     homing shots, line-piercing shots, splash, cluster, burn
scripts/map.gd            terrain tiles, theme props, path ribbon, spawn/base markers
scripts/water.gd          animated water surface and shorelines
scripts/cursor.gd         build preview (ghost tower, range, valid-cell hints)
scripts/fx.gd             rings, sparks, floating text
scripts/art.gd            optional sprite override loader
scripts/audio.gd          procedural sound bank, voice pool, music (autoloaded)
```

### Balance tuning (F2)

Tower numbers are not fixed in code any more. **F2** during a match opens the
balance editor: pick a tower on the left, nudge damage, fire rate, range,
cost, splash, slow, knockback and the rest with `−` / `+`, and the change
takes effect immediately — towers re-read their stats every frame and the
palette reprices itself.

The **Scope** button decides where a change is written: *all levels* or *this
level only*, so a tower that is fair on Easy and absurd on Brutal can be
pegged back where it actually misbehaves. Values that differ from the table
are shown in orange with the percentage change, and every row has its own
`reset`. **Save** writes `user://td_mania_tuning.cfg`; **Revert** reloads it;
**Reset all** empties both layers.

Overrides live in that one file, never in a save slot, and deleting it
restores the numbers in `data.gd`. The dev harnesses call
`Tuning.use_clean_state()`, so a simulation always measures stock balance.
Anything that reads a tower stat must go through `TDData.tower_def(id)` — the
raw `TDData.TOWERS` table bypasses the editor.

### Targeting grid

Creeps are bucketed into a 128 px grid (`GRID_CELL` in `scripts/game.gd`) so a
tower tests the handful of enemies near it instead of the whole roster.
`find_target`, `find_targets`, `explode`, the mender pass and piercing shots
all query it through `_buckets()` / `enemies_near()`; distance tests are
squared, so the hot loop takes no square roots.

The grid is rebuilt at most once a frame — creeps carry
`process_priority = -10` so they have all moved before anything queries — and
is patched in place as they spawn and die. It also rebuilds whenever the
roster size changed behind its back. **Anything that edits `game.enemies`
directly must call `invalidate_targeting_grid()`**, since a swap that leaves
the count unchanged is otherwise invisible.

This is a speed change only: `_check_targeting_grid()` in the verify suite
compares 150 random queries per mode against a full scan and fails on any
disagreement. On a saturated board (147 towers, 220 creeps) it measures about
2.3x faster targeting and 2x on the mender pass, which used to be quadratic.

### Tuning

Progression lives in `scripts/progress.gd` — the XP curve (`xp_for_level`),
payout weights, the `TECH` table, and the unlock queries the game and menu
call. Tower unlock levels are `unlock_level` in `TOWERS`; a track is gated by
adding `"level": N` to it. The dev harnesses call `Progress.use_clean_state()`,
which forces full unlocks, zero tech and read-only saving, so simulations can
never touch your real account file.

Balance lives entirely in `scripts/data.gd` — `TOWERS` (stats plus each
tower's `tracks`), `ENEMIES`, `LEVELS` (paths, terrain patches, palettes,
difficulty knobs) and `track_cost` — plus `_build_wave()` in `scripts/game.gd`.

A track's `mods` combine by key suffix: `_mult` multiplies once per rank,
`_add` sums per rank, and bare keys are set once. The keys the tower actually
reads are listed in `dev/dev_verify.gd` (`MOD_KEYS`), and the suite fails if a
track names an unknown key, if a track has no measurable effect, if a rank
does not change the tower's `visual_signature()`, or if its hover text is
missing the plain-language effect, the cost or the capstone — so an upgrade
cannot end up invisible, silent or unexplained.

`TDData.describe_mods()` turns mod keys into the words shown on hover; add a
`match` arm there when you introduce a new key.

To add a level, append an entry to `LEVELS` with a `tier` index into `TIERS`,
a unique `theme`, `decor` motif and `path_style`, plus a `ground_style`,
`water_style` and `tint`. The verify suite rejects unknown style names, a
repeated road surface, or a tint that is invisible or overpowering.
Keep path segments axis-aligned (the terrain builder walks them cell by cell),
start and end outside the grid, and include at least one water cell within a
Tide Caller's range of the path. Terrain patches are `[x, y, width, height]`
rects applied water -> rock -> ground, and the path always wins. A level may
override any tier stat (`gold`, `lives`, `hp_scale`, `speed_scale`) by naming
it directly. `dev/dev_verify.tscn` asserts all of those invariants, including
that the tiers stay ordered and that every tier is actually used.

### Developer cheats

Press **F1** during a match for a cheat panel (available in a debug build, or
with `--cheats` on an exported one):

*This run* — +$1000, +10 lives, kill all creeps, finish the wave, jump five
waves, spawn a boss, god mode, free building, 10x speed, maxed buildings
(every tower you place arrives fully upgraded, and the ones already standing
are brought up to match), and fill the map with random maxed towers.
*Account* — +1000 coins, +5000 XP, max level, unlock everything for the
session, buy every upgrade rank and doctrine node, wipe the slot.

Using any cheat marks the run: the game-over panel says "(cheats used)" and
the run cannot set a personal best. The toggles reset at the start of every
match.

### Dev harnesses

Three headless harnesses live in `dev/` and are not part of the game:

```bash
godot --headless dev/dev_verify.tscn    # 332 logic assertions (placement, economy,
                                        # upgrades, armor, slows, splash, waves)
godot --headless dev/dev_balance.tscn   # auto-plays with a crude builder AI and
                                        # prints the wave-by-wave difficulty curve
godot --headless dev/dev_balance.tscn -- --level 2   # simulate a specific map
godot --headless --quit-after 30 dev/dev_balance.tscn -- --perf   # targeting cost,
                                        # full scan vs the bucket grid; add
                                        # "--creeps 500" for a heavier roster
godot --headless dev/dev_air.tscn       # air-support cycle: launch, attack, land,
                                        # relaunch, against a stationary target
SHOT_PATH=/tmp/shot.png godot --quit-after 600 dev/dev_shot.tscn -- --panel tuning
                                        # windowed: saves one frame so a UI
                                        # change can be looked at; --fill and
                                        # --wave set the board up first
```
