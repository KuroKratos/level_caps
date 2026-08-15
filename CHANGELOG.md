# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 1.7.0

### Fixed

- **Installing the mod mid-run could stop the cap from ever moving again.**
  With the Cherrygrove rival already behind you but unrecorded, beating
  Falkner left the cap on Falkner's own roster — 9 — instead of moving to
  Bugsy's 16. The win paid nothing, and there was no way out: that rival
  cannot be fought a second time.

  1.6.x added milestones with no engine signal of their own — the seven rival
  fights award neither badge nor flag — so only this mod's own record can know
  one is beaten. An unrecorded one is unbeaten, lowest, and unreachable, and
  it pins the cap there. The floor cannot rescue it either: the floor lifts
  the cap to what you have already *cleared*, never to the next thing ahead.

  The first time the mod can see any confirmed progress at all — a badge on a
  loaded save, or its first recorded win — every signal-less milestone below
  it is written off as behind you. **Once**, and never again.

  One-shot on purpose, because level order is not play order: the Goldenrod
  Underground rival tops at 32 and is fought *after* Jasmine's 35, so a
  standing "below the ceiling means behind you" rule would keep writing off
  fights still ahead of you. On a fresh save the first confirmation is the
  Cherrygrove rival himself, nothing sits below him, and none of this runs.

### Added

- **The cap now shows up in the Nuzlocke mod's tracker.** `mods/nuzlocke`
  keeps a capability-based provider registry; this mod now publishes
  `exports.nuzlocke_provider.level_caps`, and its own comments say what that
  buys: `nextLevelCapInfo` prefers the provider over its internal ladder, and
  that one calculation feeds "enforcement, tracker, Trainer Card, Gym Guide
  text, and any other cap display". So the tracker shows this mod's number and
  the milestone name behind it.

  Its `exp.gain` wrapper also returns straight to vanilla while a provider is
  active, so the two mods cannot compound: one ladder, enforced once.

  `is_active` is what keeps that honest — with `LEVEL CAP` on `OFF` this mod
  claims nothing and the Nuzlocke ladder governs again. No exclusivity is
  claimed: this owns the cap, not the Nuzlocke ruleset. All of it is inert
  when the mod is absent, and a disabled or failed install drops out of the
  registry on its own.

## 1.6.2

*1.6.0 and 1.6.1 carry this same change. The release workflow cuts its own tag
from the manifest version; pushing one by hand alongside it sent the workflow
down its "newest tag plus a patch" fallback instead. Install this one.*

### Added

- **`MILD UP2`**, between `STRICT` and `SOFT UP5`. The row now reads
  `OFF / STRICT / MILD UP2 / SOFT UP5 / EASY UP10`. `UP<n>` rather than `+<n>`
  because the Gen 1 font has no `+` glyph.

- **The mod records its own milestones.** Gold has no `EVENT_BEAT_<LEADER>`
  flag and nothing whatsoever for the rival, so half this ladder could not
  exist while the mod only read what the cart writes.

  It does not have to. `battle.ended` names the trainer it just ended on
  **both** engines, and `mod.save` persists under `save.modData[level_caps]`
  on both too — `src/core/Game.lua:1046` and `src/core/Game2.lua:204` wire the
  same bucket, and Gold's `Save.normalize` keeps keys it does not know. So a
  win against a roster some milestone named is written down as it happens:
  `battle.oppClass` + `partyIndex` on Gen 1, `trainer.classId` +
  `trainer.memberId` on Gold.

  Only rosters a milestone asked for are recorded — a Gold run walks past some
  390 trainers. A loss, a refused battle (`result` is `"run"`) and a wild
  fight all record nothing.

- **The seven rival fights are milestones**, from Cherrygrove to the Indigo
  Plateau Center. Gold stores each as three rosters, one per starter he took
  (`RIVAL1_3_TOTODILE`); one milestone spans all three and reads the highest,
  so whichever you meet is the same step and a rebalance of one starter's
  branch leaves no hole to climb through.

- **The Elite Four now steps member by member** — 42 → 44 → 46 → 47 — which
  1.5.0 could not do. The cart records only the Hall of Fame, so the cap used
  to sit on Will's roster for the whole gauntlet.

  On vanilla Gold the ladder is now
  **7 → 9 → 16 → 20 → 22 → 25 → 30 → 31 → 35 → 38 → 40 → 42 → 44 → 46 → 47 →
  50 → 58 → 81**, verified by walking the mod against the extracted Gold
  rosters.

### Changed

- **The Cherrygrove rival carries a +2 bonus**, so the game opens at 7 rather
  than 5. His roster there is a single level-5 starter and a strict reading
  would cap you before you had fought anything. It is the only milestone with
  a bonus.
- **The seven sub-50 Kanto gyms are no longer milestones.** Janine tops at 39
  and Blaine at 50 — every Kanto gym but Viridian sits *below* the Champion
  you just beat, so they could only ever pull a post-league cap back down.
  Their badges still open Viridian, so nothing became skippable, and the
  hand-written gate 1.5.0 needed to keep Janine's 39 out of a Johto run is
  gone with them.
- Both Kanto rival fights are gated on the Hall of Fame. Ungated, Mt. Moon's
  45 would slot itself between Koga and Bruno and cap the middle of the Elite
  Four on a fight nobody can reach.
- Milestones may name the rosters they span instead of indexing them. Gold
  names every roster — `class.trainers[i].id` is the member constant, the very
  string `battle.ended` returns — so the table reads `WILL1` and `LANCE`
  rather than `party = 1`. The index stays as the fallback for a dataset that
  carries no names, which is Gen 1 and every fixture.

### Fixed

- The README still documented `SOFT +5` / `EASY +10`, which 1.2.0 renamed, and
  said nothing about Gold at all.

### Migration

A save made before this version carries no record. It does not need one: the
engine's own signals stay as the fallback — badges for the Johto gyms, the
Hall of Fame for the league, the Kanto badges for Viridian, Red's own spawn
flag. Such a save reads the *rival* milestones as unbeaten, but a cap never
falls below the highest milestone already cleared, so it lands on the right
step regardless, and the next rival fight records itself.

## 1.5.0

### Fixed

- **The cap never moved on Gold.** Beating Falkner left you locked at 9, so
  the first cave south of Goldenrod was unsurvivable.

  Gold has no `EVENT_BEAT_<LEADER>` flag. A gym win hands you a **badge**, and
  the badge *is* the record — `ENGINE_ZEPHYRBADGE` is bit 0 of `wJohtoBadges`,
  which the port stores in `save.player.badges`. This mod was reading
  `save.flags` for a name nothing ever writes.

  Four signals now, one per phase: `save.player.badges` for the Johto gyms,
  `save.hallOfFame.count` for the Elite Four and the Champion,
  `save.player.kantoBadges` for Kanto, and `spawnAfterChampion` for Red.

### Added

- **Kanto and Red join the ladder**, so the full progression is gyms → Elite
  Four → Champion → Kanto → Red. On vanilla Gold the cap walks
  **9 → 16 → 20 → 25 → 30 → 31 → 35 → 40 → 42 → 50 → 58 → 81**.

  The Elite Four does not step member by member: Gold records only the Hall of
  Fame, not each fight, so the cap holds at Will's 42 for the whole gauntlet
  and lifts to 50 after. Nothing is lost by it — the run cannot be left
  half-finished to train.

### Changed

- **Kanto is gated on the Hall of Fame, Red on the Earth Badge.** Without it
  Janine's 39 was the lowest unbeaten roster in the entire game from the first
  step, which capped a Johto run at 39 before Clair's 40 ever applied.
- **A cap never drops below the highest milestone already beaten.** Kanto's
  gyms are unordered and run from 39 to 58, so clearing the Champion at 50 and
  then walking into Kanto used to take the cap *down* to 39. This also changes
  Gen 1: beating Koga at 40 no longer sends you back to Sabrina's 38.

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
