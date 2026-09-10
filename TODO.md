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
- [ ] **Water Cannon is too strong, and tuning is guesswork.** *Reported
      2026-09-10.* Balance lives as literals in the `TOWERS` and `LEVELS`
      tables in `scripts/data.gd`, so trying a number means editing code and
      relaunching. Build a live tuning screen: pick a tower, scrub its damage,
      rate, range and cost, see the change in the running match, and save the
      set as an override file the tables read at startup — per level as well
      as globally, since a tower can be fair on Easy and absurd on Brutal.
      Fix the Water Cannon's numbers with it as the first customer.
- [ ] **Spatial partitioning for targeting.** `find_target()`,
      `find_targets()` and `_process_menders()` in `scripts/game.gd` scan the
      whole enemy list every frame, and the mender pass is O(enemies²). With
      ~150 towers (fill-map cheat) against a late wave that is tens of
      thousands of distance checks per frame. Bucket enemies into a grid keyed
      by cell. Measure before/after with `dev/dev_balance.tscn`.

## Depth

- [ ] **Flying enemies.** The classic counter-mechanic the game lacks: ignore
      the road, fly straight at the base. Makes Airfield/Helipad and
      long-range towers matter and forces a diversified build. Touches
      `enemy.gd` (movement), `game.gd` (targeting/leaks) and wave tables.
- [ ] **Per-map objectives and stars.** All 20 maps currently say "go as deep
      as you can". Add goals like *survive 15 waves*, *lose no lives*, *clear
      it without water towers*, stored per map in `progress.gd` alongside the
      best-wave record.
- [ ] **Data-driven waves.** `_build_wave()` is 13 hardcoded
      `if n >= X and n % Y == Z` rules. Move to a table, optionally per area,
      so the Wastes can feel different from the Greenlands and tuning stops
      being surgery.
- [ ] **Tech respec.** Coins are spent permanently with no way to experiment.
      A paid respec button on the tech screen would encourage trying builds.

## Robustness

- [ ] **Save versioning.** `scripts/progress.gd` has no `version` field. The
      `enemy_kills` crash was exactly this class of bug — an old save meeting
      new code. Add a version number and explicit migration steps so the next
      schema change is safe by construction.
- [ ] **Full-speed smoke test.** Every harness runs at accelerated
      `time_scale`; nothing plays a wave at 1× and asserts no runtime errors.
      That gap is how the freed-object crashes slipped past 292 assertions.
- [ ] **Split `scripts/game.gd`** (1,782 lines: state, waves, placement, HUD
      and the service locator in one file). The HUD alone is ~700 lines and
      lifts out cleanly.

## Polish

- [ ] **Options screen.** Volume (once audio exists), window scale, key
      rebinding — none of these exist today.
- [ ] **Generate the art.** `assets/PROMPTS.md` is written and the loader in
      `scripts/art.gd` picks files up with no reimport; dropping in real
      sprites is a one-evening visual overhaul.
- [ ] **Board tooltips.** Hovering a creep to see its armour, immunities and
      speed would teach the roster without a wiki.

## Notes

- Balance is currently measured ad hoc: the proxy player in
  `dev/dev_balance.tscn` caps at wave 30 and does not adapt its build to
  counter Menders or Wardens, so its numbers are a floor, not a verdict.
  Raising the cap and sampling several runs per map would make the difficulty
  ladder measurable rather than anecdotal.
- The structural difficulty ladder (road length and firing positions per tier)
  *is* enforced by the verify suite and should stay that way when new maps are
  added.
