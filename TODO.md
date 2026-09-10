# TD Mania — improvement backlog

Suggestions for where to take the game next, ordered by what I think returns
the most for the effort. Every item notes the code it touches so it can be
picked up cold.

State at time of writing: 20 maps in 5 areas, 18 towers, 12 enemy kinds,
3 save slots, account levels + coin tech tree, 292 passing assertions in
`dev/dev_verify.tscn` plus the air and balance harnesses.

## Do these first

- [x] **Sound.** *Done — approved 2026-09-10.* `scripts/audio.gd` (autoloaded
      as `Audio`) synthesises 16 sounds at startup: three weapon types, a
      continuous beam hum, explosions, creep deaths, leaks, building,
      upgrading, selling, wave horn, wave-clear arpeggio, boss growl, defeat
      tone, UI ticks and a looping ambient pad. Voice pool of 20 with pitch
      jitter and a 35 ms repeat filter; beams are reference counted. A **Vol**
      button cycles full/quiet/muted, saved per slot. Dropping
      `assets/audio/<name>.wav` overrides any generated sound.
- [x] **"Next wave" composition readout.** *Done — approved 2026-09-10.* The
      top strip of the bottom bar lists the upcoming wave's makeup during the
      build phase — "Wave 13 incoming · ● 19 Grunt · ● 8 Runner · ● 3 Tank …"
      — each chip drawn with that kind's silhouette and colour
      (`scripts/enemy_dot.gd`). `wave_composition(n)` in `scripts/game.gd`
      counts `_build_wave()` in roster order; `_refresh_wave_preview()`
      rebuilds it only when the wave key changes and shows a muted
      "Wave N in progress" while a wave runs so the bar never resizes. A
      right-aligned note calls out the counter the wave demands. Bar height
      112 → 134 px, window 902 tall.
- [x] **Water Cannon is too strong, and tuning is guesswork.** *Implemented
      2026-09-10.* **F2** in a match opens a balance editor: every tunable
      stat of every tower, `−`/`+` live, scoped to all levels or to the level
      being played, saved to `user://td_mania_tuning.cfg`
      (`scripts/tuning.gd`, `scripts/tuning_panel.gd`). Stats now flow
      through `TDData.tower_def()` so edits land on the next frame with no
      restart. The Wave Cannon was its first customer: knockback 46 -> 32,
      Storm Surge +16 -> +10 a rank, damage 26 -> 23, cost 190 -> 205, and
      creeps now build shove-resistance (`push_fatigue` in `enemy.gd`) so
      stacked cannons can no longer hold a lane still forever.
- [x] **Spatial partitioning for targeting.** *Implemented 2026-09-10.*
      Creeps are bucketed into a 128 px grid (`GRID_CELL` in `game.gd`);
      `find_target`, `find_targets`, `explode`, the mender pass and piercing
      shots query it through `_buckets()` / `enemies_near()`, with squared
      distance tests. Rebuilt once a frame (creeps carry
      `process_priority = -10` so they have all moved first) and patched as
      they spawn and die. About 2.3x faster targeting on a saturated board,
      2x on the mender pass, and proven identical to a full scan by 150
      random queries per targeting mode in `_check_targeting_grid()`.

## Depth

- [x] **Flying enemies.** *Implemented 2026-09-10.* Cinder Moth (fast,
      fireproof, packs from wave 5) and Iron Drake (armoured, slow-immune,
      from wave 14) fly straight from spawn to base — `flying` in `ENEMIES`
      swaps the road for a two-point line, so lanes, slows, progress and
      leaks all still work. Towers need `hits_air` to touch them (9 of 18,
      plus the aircraft pads), and splash inherits the firer's reach, so a
      mortar shell under a Drake does nothing. Flyers are drawn lifted with
      wings over a hard shadow, their readout chips are winged, and the
      palette marks ground-only towers.
- [x] **Per-map objectives and stars.** *Implemented 2026-09-10.* Three per
      map, a star each: clear a target wave (eased by tier), reach a wave
      without losing a life, and the map's own `goal` — no water towers, a
      tower budget, a kill count, no selling, or holding a sum of gold.
      `TDData.objectives_for()` builds them, `Game.objective_mask()` judges
      the run from what it actually did, stars are banked per map in
      `Progress.stars` (union across attempts, nothing for a cheated run),
      and they show on the level cards, in the account bar, on the in-match
      info panel and on the defeat card.
- [x] **Tech respec.** *Implemented 2026-09-10.* A **Respec** button on the
      tech screen quotes what it will pay — 80% of everything spent, at the
      prices actually paid, doctrine and tower ranks together — and a second
      press clears every rank and banks the refund
      (`Progress.spent_on_tech()` / `respec()`). Tested to never mint coins
      by repeating it and to leave nothing behind that it refunded.

## Robustness

- [x] **Save versioning.** *Implemented 2026-09-10.* Saves carry
      `[meta] version` (`Progress.SAVE_VERSION`, now 3). `detect_version()`
      infers a version for files written before the field existed,
      `migrate_config()` walks a save forward one step at a time (v1's single
      parked run becomes per-map runs; v2's run stats gain the per-kind
      tallies whose absence caused the `enemy_kills` crash), and a slot from
      a *newer* build is read but never overwritten. Reading a slot now also
      clears the previous slot's tech, records, stats and ranks, which used
      to bleed between accounts.
- [x] **Full-speed smoke test.** *Implemented 2026-09-10.*
      `dev/dev_smoke.tscn` plays waves at `time_scale` 1 under
      `--fixed-fps 60`, so every frame advances the delta a real machine
      produces. A watchdog runs every frame — no freed creep left on the
      roster, no freed tower on the board, no dead creep with health, no
      negative lives or gold — while the harness builds, upgrades and sells,
      takes a boss wave and an air wave (picked by reading the wave table),
      and round-trips a parked run. `dev/run_checks.sh` runs every harness
      and fails on engine errors as well as assertions, since a Godot
      runtime error is a log line, not an exit code.
- [x] **Split `scripts/game.gd`.** *Implemented 2026-09-10.* The HUD moved
      to `scripts/hud.gd` (`GameHUD`, ~930 lines): top bar, palette, wave
      readout, info bar, creep card, defeat panel and their refreshes.
      `game.gd` is down from 2,223 lines to ~1,310 and keeps the state, the
      board and the service locator. The HUD owns no game state — it reads
      the match through `game` and calls back for anything that changes the
      world, so a bare name is a widget and a `game.` name is the match.

## Polish

- [x] **Options screen.** *Implemented 2026-09-10.* Reached from the menu:
      effects and music sliders that take effect (and play a sample) as they
      move, window size at 75/100/125/150% of the design resolution plus
      fullscreen, and every match key rebindable — click a binding, press a
      key. Taking a key another action holds swaps the two rather than
      double-binding, and the game looks keys up by action
      (`Progress.action_for()`), so the HUD prompts follow whatever is bound.
- [~] **Generate the art.** *Ready for you, 2026-09-10 — needs your Gemini
      run.* `assets/PROMPTS.md` now covers every sprite the game actually
      looks for: the six towers and nine creeps added since the first pass
      (including the two flyers), plus the per-level tile variants and the
      naming rule for them. The verify suite fails if a tower or creep is
      ever added without a prompt, and asserts the loader falls back to
      vector art when a file is absent. Drop the PNGs into `assets/` and
      they appear on the next launch — no reimport, no code change.
- [x] **Board tooltips.** *Implemented 2026-09-10.* Hovering a creep pops a
      card by the cursor: name, current and maximum health, armour, speed,
      and every trait that decides how to answer it — flying, slow- or
      fire-immune, heals, steals, splits, sprints, or costs more than one
      life — plus the roster note. `enemy_at()` picks what is under the
      pointer (aiming at where a flyer is drawn, not its shadow) and the
      card is re-checked every frame, since creeps walk out from under a
      still cursor.

## Do last

- [x] **Cut what the game costs the machine.** *Implemented 2026-09-10.*
      Profiled first with the new `dev/dev_perf.tscn` (vsync off, cap
      lifted, `--off towers,draw,hud,water,enemies` to attribute the cost).
      A saturated board ran at **20 fps / 48.8 ms a frame**, and hiding the
      tower layer took it to 4.3 ms — so the cost was rebuilding ~5,900 draw
      commands every frame, not the GPU and not the logic. Fixes: towers
      redraw only when the turret actually turned, fired or changed state;
      idle animations (support rings, mines, tar, creep bob, water ripples)
      run at 12 Hz instead of 60; tech bonuses and merged track mods are
      cached against a hash instead of recomputed several times per tower
      per frame; aura lookups walk a list of Command Posts instead of every
      tower. Same board now runs at **113 fps / 8.9 ms**, display-bound. The
      game also ships capped at 60 fps (`application/run/max_fps`, and a
      Frame cap row in Options) and drops to 10 fps whenever the window is
      in the background, via the new `App` autoload.

## Notes

- Balance is currently measured ad hoc: the proxy player in
  `dev/dev_balance.tscn` caps at wave 30 and does not adapt its build to
  counter Menders or Wardens, so its numbers are a floor, not a verdict.
  Raising the cap and sampling several runs per map would make the difficulty
  ladder measurable rather than anecdotal.
- The structural difficulty ladder (road length and firing positions per tier)
  *is* enforced by the verify suite and should stay that way when new maps are
  added.
