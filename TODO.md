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

- [ ] **Bosses that do something.** The Behemoth and the Titan are just
      large: same walk, same nothing. Give each a behaviour — a shield that
      has to be broken before damage lands, a shockwave that stuns towers
      for a second, a call that drags its escort forward. Touches
      `enemy.gd` and the boss branch of `_build_wave()`.
- [ ] **Wave affixes.** Now that waves come from a table, an occasional
      modifier costs almost nothing and changes a lot: *armoured* (+50%
      armour), *swift* (+25% speed, −20% health), *shielded* (first hit
      absorbed). Announce it in the wave readout, which already has room.
      `TDData.WAVE_RULES` plus a few lines in `_build_wave()`.
- [ ] **Map hazards.** A per-map `hazard` entry that bends one rule: wind
      that pushes aircraft off course, ash that halves burn damage, fog
      that trims tower range, a tide that floods two cells every fifth
      wave. One field in `LEVELS`, read in `tower.gd` and `game.gd`. It
      would make thirty maps feel like thirty decisions rather than thirty
      shapes.
- [ ] **Chosen modifiers, for a reward.** The objectives already know how
      to judge "no water towers" and "a tower budget". Offer them as opt-in
      modifiers at the start of a run for an XP and coin multiplier.
      Nearly free given `objective_mask()`, and it gives a cleared map a
      reason to be played again.
- [ ] **Endless is not scored.** Past a map's clear wave the run continues
      but nothing records how far it went. Track the best endless wave per
      map separately from the clear and show it on the level card as a
      second line.

## Polish

- [ ] **Colour is doing too much work.** Routes, tiers, tower types and
      creep kinds are all told apart by hue, and roughly one man in twelve
      cannot separate some of those pairs. Shapes on route markers, a
      pattern on the tier pill, and a colourblind-safe palette in Options.
      The wave chips already carry silhouettes, so there is a pattern to
      copy.
- [ ] **Moving a tower.** Misplace a Command Post and the only remedy is
      selling it at 70%. Allow picking a tower up during the build phase
      and re-placing it free, once per wave. `game.gd` placement, plus a
      state on the cursor.
- [ ] **The palette does not say enough.** Hovering a card shows text but
      not the thing that decides the purchase: where it can shoot. Draw its
      range ring over the board on hover, before you commit to placing it —
      `cursor.gd` already draws exactly that for a held tower.
- [ ] **Per-area music.** One ambient pad plays everywhere. `audio.gd`
      synthesises its own sound, so an area-flavoured variant is a
      parameter change rather than new content: colder intervals for the
      Frozen Coast, a lower drone for the Delta.

## Robustness

- [ ] **Split `dev/dev_verify.gd`.** Past 3,400 lines, and every new
      feature lands in the same file. One script per area of the game
      (progress, combat, maps, UI) with a runner that loads them would make
      a failure easier to place and the file easier to add to.
- [ ] **Saves have no safety net.** A crash mid-write loses a slot
      outright. Write to a temporary file and rename, keep one previous
      copy, and refuse to load a file that does not parse rather than
      starting an account from a corrupt one. `progress.gd`.
- [ ] **Runs are not reproducible.** The balance report seeds every run,
      but a real run does not record its seed, so "look what happened"
      cannot be replayed. Store the seed in the run state and reuse it on
      resume.
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
