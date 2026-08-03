# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

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
