# TD Mania — improvement backlog

Where to take the game next, ordered by what returns the most for the
effort. Every item names the code it touches so it can be picked up cold.
What has already shipped is listed at the bottom.

State at time of writing (2026-09-11): 30 maps in 5 areas, 18 towers, 14
enemy kinds, 3 save slots, account levels and a coin tech tree, objectives
and clears per map, a live balance editor, 554 assertions in
`dev/dev_verify.tscn` plus the air, smoke, report, balance and map
harnesses.

## Do these first

- [ ] **A first run that teaches itself.** The game now has towers, ranks,
      coins, tech, objectives, targeting modes, flyers, water, aircraft and
      auras — and it explains none of it until you already know where to
      look. Verdant Pass should run a scripted first three waves: place
      this here, watch it shoot, this is what a rank does, this is what got
      through and why. Gate it on `Progress.stat_int("runs") == 0` with a
      skip button. Touches `game.gd` (a small script runner), `hud.gd` (a
      pointer and a caption) and `progress.gd` (a "seen it" flag).
      *The biggest gap between the game being good and being playable by
      someone who is not you.*
- [ ] **Anyone else can play it.** There is no export preset, so the game
      runs from the CLI or the editor and nowhere else. Add a web export
      plus a GitHub Actions workflow running `dev/run_checks.sh` on push,
      and the repo becomes a link you can send. *Cheap, and it changes what
      the project is.*
- [ ] **Generate the art.** *Waiting on you.* `assets/PROMPTS.md` covers
      every sprite the game looks for — including the ten new road surfaces
      and decor motifs — and `scripts/art.gd` picks PNGs up off disk with no
      reimport. One Gemini run and the whole game changes complexion.

## Depth

- [x] **Bosses that do something.** *Implemented 2026-09-11.* The Behemoth
rallies every nine seconds (everything near it runs 40% faster for three);
the Titan quakes every eight, stunning towers within reach for 1.6 s. Driven
from `game.gd`, announced on the board, and described in their bestiary
      notes.

- [x] **Wave affixes.** *Implemented 2026-09-11.* From wave 7, every third
wave carries Armoured, Swift, Shielded or Hardy; boss waves are left alone.
Shields are a hit counter on the creep, drawn as a ring. The readout names
the affix and says how to answer it.
- [x] **Map hazards.** *Implemented 2026-09-11.* Eight maps run under Fog,
Ashfall, Gale or Brine (`TDData.HAZARDS`, `game.hazard_mult()`), named and
explained on the level card and the info panel.
- [x] **Chosen modifiers, for a reward.** *Implemented 2026-09-11.* Dry
feet, Skeleton crew, No refunds and Thin line sit under every unlocked level
card, stack, and multiply the payout. Enforced by the match rather than
judged afterwards.
- [x] **Endless is not scored.** *Implemented 2026-09-11.*
`Progress.endless_best()` reports the waves past the finish line, shown on
the level card and the defeat card.
## Polish

- [x] **Colour is doing too much work.** *Implemented 2026-09-11.* Lane
shapes and tier marks are always on, the build cursor draws a tick or a
cross, and Options carries a colour-blind palette chosen by simulating
protanopia and deuteranopia — a simulation the suite runs as a test.
- [x] **Moving a tower.** *Implemented 2026-09-11.* Move lifts a tower
between waves, keeping its ranks and kills; anywhere it could have been
built is fair, once per wave, free.
- [x] **The palette does not say enough.** *Implemented 2026-09-11.*
Hovering a card draws the tower's range and dead zone at the last hovered
cell and tints every cell it could stand on.
- [x] **Per-area music.** *Implemented 2026-09-11.* `Audio.AREA_MUSIC` tunes
the same loop per area; a match plays its area's pad, the menus play the
plain one.
## Robustness

- [ ] **Split `dev/dev_verify.gd`.** Past 3,400 lines, and every new
      feature lands in the same file. One script per area of the game
      (progress, combat, maps, UI) with a runner that loads them would make
      a failure easier to place and the file easier to add to.
- [x] **Saves have no safety net.** *Implemented 2026-09-11.* Writes land by
rename with the previous copy kept as `.bak`; reads fall back to it and
refuse a file that is not a save.
- [x] **Runs are not reproducible.** *Implemented 2026-09-11.* A run draws
one seed, carries it in the parked state with its handicaps, and shows it in
the pause menu.
- [x] **Creeps are allocated and freed every wave.** *Measured 2026-09-11,
      and left alone.* `dev/dev_perf.tscn -- --churn` creates, sets up and
      frees 200 creeps: 0.95 ms to make them, 0.27 ms to free them. A heavy
      wave spawns about 70 creeps over 45 seconds, which works out at
      **0.009 ms per second of play** — nothing. Pooling would buy that
      back in exchange for reusing nodes with stale state, which is the
      exact class of bug that produced the freed-object crashes. Not worth
      it; the benchmark stays so the decision can be re-checked if creep
      counts ever change by an order of magnitude.

## Notes

- Balance is measured, not guessed: `dev/dev_report.tscn` plays every map
  and asserts the ladder. As of 2026-09-11, across 60 runs: Easy 16.8,
  Normal 14.2, Hard 12.3, Brutal 10.3 waves, no outliers. The proxy player
  does not counter Menders or Wardens, so those numbers are a floor rather
  than a verdict — what they measure well is maps against each other.
- No proxy run has ever *cleared* a map: the finish lines are wave 20–25
  and the proxy dies around 10–17. That is expected of a deliberately crude
  player, but it does mean the clear waves themselves are untested by
  anything except you.
- The structural difficulty ladder — road length and firing positions per
  tier — is enforced by the verify suite. `dev/dev_maps.tscn` prints both
  numbers per map; design new maps against it rather than adjusting them
  afterwards.

## Shipped

*2026-09-10 to 2026-09-11, in order.*

- Sound: 16 synthesised effects, music, per-slot volume.
- Next-wave composition readout in the bottom bar.
- Live balance tuning (F2), later extended to upgrade ranks and creeps,
  with per-rank prices, typed fields, explanations and export/import.
- Spatial partitioning for targeting (2.3x), and the Wave Cannon reined in.
- Save versioning with migrations; slots no longer bleed into each other.
- Data-driven waves with per-area flavour.
- Flying enemies, and towers that cannot reach them.
- Board tooltips: hover a creep to see what it is.
- Per-map objectives and stars.
- Tech respec (80% back).
- Options screen: sound, window size, rebindable keys.
- Full-speed smoke test, and `dev/run_checks.sh`.
- The HUD split out of `game.gd`.
- Maps can be won, then continued into endless.
- A post-wave report saying what got through and why.
- The balance report, and funding for multi-lane maps.
- Frame cost cut from 20 fps to 113 on a full board; a 60 fps cap; idle
  throttling in the background.
- Main menu, pause menu, Escape as a ladder, volume on sliders, and game
  speed earned in the tech tree.
- Both top bars rebuilt so they cannot overflow.
- Ten more maps: two in every area, each with its own road and decor.
