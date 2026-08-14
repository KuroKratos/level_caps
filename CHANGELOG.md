# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 1.4.0

### Added

- **Gold support** (`"games": ["gen1", "gen2"]`), with the Johto ladder.
  Falkner through Clair, then Will, Koga, Bruno, Karen and Lance — read out of
  their real rosters exactly as the Kanto caps are, so on vanilla Gold they
  resolve to 9 / 16 / 20 / 25 / 30 / 35 / 31 / 40 / 42 / 44 / 46 / 47 / 50.
  That is the ladder the Nuzlocke mod publishes, derived rather than copied:
  a mod that rebalances Whitney moves her cap with her.

### Changed

- Rosters are read through one shape. Gen 1 nests them as `class.parties[i]`,
  Gold as `class.trainers[i].party`; the party index that picks Giovanni's
  third team still works on both.
- **`ALLOW OVER LVL` turns itself off on Gold and says so.** Refusing a battle
  needs `BattleState.newTrainer`, which Gold does not have — `World:startBattle`
  constructs and pushes in one call. `LEVEL CAP` itself rides `exp.gain`, which
  Gold raises, so the mod's main job is unaffected.
- The follower's happiness bump and the level-up stats box are presence-tested
  rather than assumed. Gold has neither; without them the walk still levels the
  Pokemon and still offers its moves.

## 1.3.0

### Fixed

- **`ALLOW OVER LVL = NO` soft-locked the game.** The battle opened, printed
  the refusal, and then never ended: you could not attack, switch or run.

  Leaving a battle takes four fields, and the refusal only set three. The
  drain that reads `afterQueue` and calls `finish()` lives inside
  `if self.phase == "messages"`, so without `battle.phase = "messages"` it
  was simply never reached. The engine's own equivalent — the Safari with no
  Balls left — sets all four, and the refusal now mirrors it exactly.
- `battle.result` is `"run"` instead of `"skipped"`. `"skipped"` was this
  mod's invention and matched no branch anywhere in the engine; `"run"` is a
  real value and correctly leaves the trainer undefeated.

### Changed

- The test suite now asserts `phase` alongside `result` and `afterQueue`, and
  checks `result` against a value the engine actually uses. The old suite
  passed while the game locked, because it asserted the mod's own fiction
  rather than the engine's contract.

## 1.2.0

### Fixed

- `SOFT +5` and `EASY +10` became **`SOFT UP5`** and **`EASY UP10`**. The
  Gen 1 font has no `+` glyph, so the old labels logged a missing-glyph
  warning on every draw and printed a hole.

## 1.1.0

### Added

- **UP TO CAP** in the party submenu: walks a Pokémon up to the current cap
  **one level at a time**, so every level-up move is offered on the way rather
  than skipped — Gen 1 has no move relearner to recover them. Each level runs
  the Rare Candy sequence: level text, stats window, move prompts, and an
  evolution check, so a two-stage line walked through both thresholds evolves
  twice. Offered only when a cap exists and the Pokémon is below it.

## 1.0.0

### Added

- **LEVEL CAP** (`OFF` / `STRICT` / `SOFT +5` / `EASY +10`): a Pokémon at or
  above the cap gains no experience. The cap is the top level of the next
  unbeaten milestone, read live from that trainer's roster.
- **ALLOW OVER LVL** (`YES` / `NO`): `NO` refuses a trainer battle while any
  party member is over the cap. Inside the league it offers to send the
  offenders to the PC instead, and never empties the party.
- Thirteen milestones: eight gym leaders, the four Elite Four members, and the
  Champion. Elite Four caps unlock on the first win, via the engine's own
  victory flags.
- `currentCap`, `nextMilestone`, `milestoneLevels` and `overLevelled` exports.
