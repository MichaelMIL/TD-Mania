# TD Mania — improvement backlog

Where to take the game next, ordered by what returns the most for the
effort. Every item names the code it touches so it can be picked up cold.
What has already shipped is listed at the bottom.

State at time of writing (2026-10-23): 30 maps in 5 areas, 18 towers, 14
enemy kinds, 3 save slots, account levels and a coin tech tree, objectives
and clears per map, twelve graded challenges and a daily, a live balance
editor, iOS and Android builds, 715 assertions in `dev/dev_verify.tscn`
plus the touch, air, smoke, report, balance, map, challenge, progression
and art harnesses.

## Do these first

- [ ] **Play it yourself and say where the difficulty actually sits.**
      Every number in the game is now tuned against `dev/proxy_player.gd`,
      which builds anywhere beside the road and never defends a chokepoint.
      It has underrated you twice: Last Stand was set where even the
      fully-upgraded harness barely finished and you beat it comfortably,
      and the old level curve looked slow on paper while handing over every
      tower by run 15. The harnesses can say what is impossible and what is
      trivially easy; they cannot say what is *fun*. Run the three Brutal
      challenges and a dozen fresh-account runs and write the real numbers
      down — that is the only input nothing here can simulate.

- [ ] **A build that outlives the week.** The iOS build is signed with a
      personal team, so it stops opening after seven days and nobody else
      can install it at all. TestFlight needs a paid Apple developer
      account and `application/export_method_release` switched off
      `app-store` in `export_presets.cfg`; Android needs a release keystore
      in `keystore/release` and `gradle_build/export_format` set to AAB.
      Until then every play session needs a Mac and a cable. This is the
      difference between a game you can show someone and one you can only
      demo.

- [x] **A first run that teaches itself.** *Implemented 2026-09-11.*
      `scripts/tutorial.gd`: eight lines in a banner under the top bar,
      each waiting for the player to place a tower, call a wave, spend the
      gold, click a tower — rather than for a timer. Runs once on an
      account with no runs, never on a resumed one, skippable, and every
      step is a condition on the match itself so it cannot disagree with
      the game.
- [x] **Anyone else can play it.** *Implemented 2026-09-11.* Export
      presets for Web and macOS are committed (`dev/` excluded, web forced
      onto `gl_compatibility` since Forward+ cannot run on WebGL2), and
      `.github/workflows/checks.yml` runs `dev/run_checks.sh` on every push
      then builds the web export and keeps it as an artifact. The web build
      was produced and checked locally; the workflow itself is unverified
      until GitHub runs it.
- [x] **Runs on phones and tablets.** *Implemented 2026-10-21.* Android
      and iOS export presets (`export_presets.cfg`), the `mobile` renderer
      and landscape lock in `project.godot`, and a touch pass: a dragged
      tower floats above the finger (`game.gd` `drag_point`), a second tap
      on an armed card puts it away (`hud.gd` `_palette_input`), the Android
      back button is replayed as Escape (`app.gd`), and backgrounding the
      app parks the run (`game.gd` `_notification`). An APK and an Xcode
      project were built and the Xcode project linked for a device locally;
      CI builds the APK. Installed and played on an iPhone 13 Pro Max the
      same day, which led to the handheld layout (`hud.gd`
      `_layout_handheld`: full-width top bar, the board scaled to fit, the
      palette and tower panel sharing a column, text sized from the
      screen's DPI via `app.gd` `ui_scale`) and to a built tower no longer
      leaving its card armed. A second pass on 2026-10-22 added touch
      scrolling for every list (`scripts/touch_scroll.gd`), the safe area
      (`app.gd` `safe_margins`), flyers drawn above towers, and one clearer
      button look. Not done: a real icon, store signing, and the cheats and
      tuning panels, which stay desktop-sized.
- [x] **Continuing a parked run kept the towers but lost their upgrades.**
      *Fixed 2026-10-22.* `game.gd` `_capture_run` never wrote a tower's
      ranks, so every tower came back plain while its sale price still
      counted what had been spent on it. Ranks are saved and restored now;
      save version 6 refunds the upgrade gold of towers in runs parked
      before the fix, since which ranks they had is gone.
- [x] **The three water towers looked alike.** *2026-10-23.* One square
      deck each and three shades of cyan, one of them the Gunner's exact
      blue. Each now has its own colour, footing and turret in `tower.gd`
      and its own palette icon in `tower_icon.gd`: a cyan basin and spout,
      an indigo slipway with tubes, a navy breakwater with a crest.
- [x] **The three water towers were two of the same thing.** *2026-10-23.*
      Tide Caller and Wave Cannon both splashed and slowed. Now the Tide
      Caller is the chill (a long, strong slow, the only water tower that
      reaches flyers, little damage), the Wave Cannon is the shove (no slow
      at all, more damage and knockback) and the Torpedo Battery is the long
      gun (longest reach, hardest shot, no splash or slow). The verify suite
      checks the three stay apart.
- [x] **Two Wave Cannons could pin a lane.** *Fixed 2026-10-23.* Shove
      fatigue only shortened each push, so two cannons firing together
      landed two full shoves on the same creep at once. A creep now cannot
      be shoved again for 200 ms (`Enemy.PUSH_IMMUNE`); the second cannon
      adds damage rather than distance.
- [x] **Challenges without anti-air are played without flyers.**
      *2026-10-23.* A kit with nothing that shoots upwards would have
      watched Cinder Moths sail past, so rather than forbidding such a
      challenge each flyer arrives as its counterpart on the ground
      (`Challenges.GROUND_SWAP`) — same wave size, answerable kit. Siege
      Line (Cannon and Mortar only) is the first of them.
- [x] **Rushing a wave.** *Implemented 2026-10-23.* The Start Wave button
      stays live during a wave as Rush, merging the next wave into the
      queue already playing (`game.gd` `rush_wave`) for a bonus at the same
      rate and ceiling as the between-waves early call. Every merged wave
      still pays its own clear bonus. Records count waves cleared rather
      than the counter, since a rush advances it before the waves are
      fought, and a challenge now ends at its goal instead of letting waves
      be called in past it.
- [x] **The cheat panel and the Quit buttons are gone.** *2026-10-23.* The
      panel was a developer tool one keypress from every player and useless
      on a phone; `scripts/cheats.gd` is now just the toggles the harnesses
      set. Quit went from the title, main menu and level select: an iOS app
      does not quit itself, and on desktop the window close button already
      does it.
- [x] **Save slots were sharing the tech tree.** *Fixed 2026-10-23.*
      `Progress.load_state` returned early when a slot had no file yet, so
      the previous account's tower ranks, stars, clears, challenges and
      lifetime stats stayed in memory and the new slot's first save wrote
      them in. Every reset now goes through `Progress.blank_tables`, which
      is the one place that knows the whole list. Erasing a slot also
      deletes its `.bak`, which used to restore the account on the next
      read. `load_slot_file` was split out so a test can point at a path
      instead of the player's own saves; the regression test names every
      table that leaks.
- [x] **Progression paced for a campaign, not an evening.**
      *Rebalanced 2026-10-23.* `dev/dev_progress.tscn` measures where every
      unlock lands; it showed run 1 paying three towers and two maps, every
      tower out by run 15 and the tech tree bought by run 20. The level
      curve went from 300/100 to 1000/150 (`Progress.XP_LEVEL_*`), tower,
      map and upgrade-track gates were stretched across it, coin income was
      cut and doctrine costs doubled. Cheated runs now bank nothing, which
      is what let a save reach the cap in four maps. Save version 8 restates
      an old save's XP at the same level on the new curve, so no account
      loses what it earned.
- [x] **Challenges and a daily challenge.** *Implemented 2026-10-22.*
      `scripts/challenges.gd` holds twelve fixed challenges and deals the
      daily from the date; `scripts/challenges_screen.gd` lists them; the
      match enforces the rules through `game.gd` `rule` and keeps challenge
      results off the map's records. Save version 7 adds [challenges] and
      [daily]. Goals were tuned with `dev/dev_challenges.tscn` against a
      beginner and a veteran harness player, and graded Easy to Brutal
      after the first "hardest" one was beaten easily by hand; checks in
      `dev/suites/suite_challenges.gd`. Not done: online leaderboards
      (the daily is the same everywhere only because it is dealt the same
      way), and challenge results on the Stats screen.
- [x] **A picture for every upgrade.** *Implemented 2026-10-22.*
      `scripts/upgrade_icon.gd` draws a symbol per kind of upgrade in the
      tower's colour and uses `assets/upgrade_<tower>_<track>.png` when it
      exists; 59 prompts are at the end of `assets/PROMPTS.md`, and
      `dev/dev_icons.tscn` shows them all at once. The upgrade buttons
      (`scripts/track_button.gd`) carry the picture, trim long names instead
      of widening the panel, and colour the price line by what it means.
- [~] **Generate the art.** *Everything but the images is done; the run is
      yours.* `assets/PROMPTS.md` carries a prompt for all 116 sprites the
      game looks for, `scripts/art.gd` uses a PNG the moment it appears and
      keeps drawing the rest by hand, and
      `godot --headless --quit-after 100 dev/dev_art.tscn` says how far
      along you are ("12 of 116 sprites in place"). Drop them in a few at a
      time; nothing needs reimporting and nothing breaks half-way.

## Depth

- [ ] **The Stats screen has never heard of challenges.** `scripts/stats.gd`
      still reports only maps, towers and the bestiary, while
      `Progress.challenges` and `Progress.daily` now hold which challenges
      are beaten, the deepest wave in each, the daily streak and how many
      dailies have been done. A column for it is most of an afternoon, and
      without it a streak is a number that exists only on the challenges
      screen.

- [ ] **Eight daily twists is about three weeks before it repeats.**
      `Challenges.TWISTS` is the whole variety budget of the daily, and the
      kit generator already does the interesting half of the work. Worth
      adding twists that change *how* you play rather than how much you
      have: one lane only, no selling after wave 10, towers cost double but
      upgrades are free, every creep is a flyer. The harness
      (`dev/dev_challenges.tscn -- --only-daily --days 30`) will say which
      of them are impossible before anyone sees them.

- [ ] **Endless is unmeasured past the finish line.** Waves keep scaling
      with `pow(1.125, n)` forever and nothing has ever checked what that
      feels like at wave 40 or 60 — whether it stops being winnable at a
      wall or just gets slowly sillier. `dev/dev_progress.tscn` already
      plays runs to death; pointing it at a cleared map and printing where
      the curve turns would answer it.

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

- [ ] **The cheats and tuning panels are still desktop-sized.**
      `scripts/cheats.gd` and `scripts/tuning_panel.gd` draw at the design
      resolution with fixed 600x460 panels, so on a phone they are a wall of
      6pt text. They are developer tools, so the cheap answer is to hide
      them on a touch build; the better one is to scale them the way the
      HUD does (`hud.gd` `_layout_handheld`).

- [ ] **The app icon is a placeholder I drew in code.** `assets/icon.png` is
      a grey tower on a gold ring, standing in so the iOS and Android
      exports had something to sign. The Gemini prompt for the real one is
      at the end of `assets/PROMPTS.md`; dropping the file in place is the
      whole job, and it is the first thing anyone sees.

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

- [ ] **Nothing has ever run the Android build on a phone.** CI builds the
      APK on every push and the export is signed and installable, but it has
      only been proved to *build*. Touch, the back button, the safe area and
      the audio pool are all things iOS confirmed and Android has not. One
      afternoon with a cable would turn a plausible build into a tested one.

- [ ] **Performance on the phone is unmeasured.** `dev/dev_perf.tscn` prices
      a frame on a desktop, where the answer was 113 fps on a full board.
      A phone has a tenth of the power and the handheld layout adds a
      scaled canvas on top. Nobody knows what a full board at wave 30 costs
      on the 13 Pro Max, and the frame cap would hide a problem until it
      does not.

- [x] **Split `dev/dev_verify.gd`.** *Implemented 2026-09-11.* The checks
      live in `dev/suites/` — basics, towers, combat, maps, waves, account
      — behind a `VerifySuite` base that hands each one the match and a
      `check()` funnelling back to a 60-line runner, which prints a
      per-suite tally. The split immediately turned up a test that had been
      relying on running first.

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
- Progression and challenge difficulty are measured the same way balance
  is: `dev/dev_progress.tscn` says which run every unlock lands on, and
  `dev/dev_challenges.tscn -- --depth [--tech]` says how deep the harness
  gets with and without a finished account. Both are floors, not verdicts,
  for the same reason the balance report is — and the gap is wider than it
  looks, because the proxy never builds a chokepoint.
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
