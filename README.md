# Level Caps

No Pokémon may out-level the next thing standing in your way. A party member
that reaches the cap stops gaining experience entirely, and optionally the
next trainer refuses to fight you until you are legal again.

**Persona: the Mechanic Designer.** Both rows default to the permissive
setting, so installing this and changing nothing leaves the game as it was.

## Try it

```sh
python3 tools/modkit.py validate mods/level_caps
```

```sh
python3 tools/modkit.py lint mods/level_caps
```

```sh
luajit mods/level_caps/tests/level_caps_test.lua
```

## The caps are read, not written

Nothing here hard-codes a level. Each milestone names a trainer and the save
flag that marks them beaten; the cap is `max(level)` over that trainer's
**actual roster**, read through the merged registry at the moment it is
needed.

On vanilla data that resolves to exactly the classic table:

| Milestone | Cap | | Milestone | Cap |
|---|---|---|---|---|
| Brock | 14 | | Giovanni | 50 |
| Misty | 21 | | Lorelei | 56 |
| Lt. Surge | 24 | | Bruno | 58 |
| Erika | 29 | | Agatha | 60 |
| Koga | 43 | | Lance | 62 |
| Sabrina | 43 | | Champion | 65 |
| Blaine | 47 | | | |

**Load a mod that raises the gym curve and every cap moves with it**, with no
change here. That is why the test suite injects rosters that exist nowhere in
vanilla — if the numbers above were baked in, every assertion would fail.

Two details the table hides. Giovanni's gym fight is his *third* roster (the
first two are the Rocket hideout and Silph), and the Champion fields three
teams picked by your starter — so his cap is the maximum across all three, and
never depends on which one you will actually meet.

## Koga and Sabrina, in either order

The cap is **the lowest top level among the milestones still unbeaten** — not
"the next one in list order".

That one rule is the whole answer to the either-order pair: while both Koga
and Sabrina are unbeaten the cap is the lower of the two, and beating either
leaves the other governing. No ordering assumption, no special case, and it
generalises to any pair a mod unlocks together.

## Gold

The Gold ladder is the same idea with a longer table: the eight Johto gyms,
**all seven rival fights**, each Elite Four member separately, the Champion,
Blue, and Red. On vanilla Gold it resolves to

```
7 → 9 → 16 → 20 → 22 → 25 → 30 → 31 → 35 → 38 → 40
  → 42 → 44 → 46 → 47 → 50 → 58 → 81
```

Three things are worth knowing.

**The rival counts, and his fights nest oddly.** Gold stores each of the seven
as *three* rosters, one per starter he took — `RIVAL1_3_TOTODILE` is the third
fight against the boy who took Totodile. One milestone spans all three and
reads the highest, so whichever you meet is the same step.

**Cherrygrove gets +2.** His roster there is a single level-5 starter, and a
strict reading would cap you at 5 before you had fought anything. It is the
only milestone carrying a bonus.

**Only Blue is kept from Kanto.** Janine tops at 39 and Blaine at 50 — every
Kanto gym but Viridian sits *below* the Champion you just beat, so putting
them in the pool could only ever pull the cap back down. Their badges still
open Viridian, so nothing is skippable.

## How Gold knows what you beat

Gold has no `EVENT_BEAT_<LEADER>` flag, and nothing at all for the rival. A
gym win hands you a **badge**, and that badge is the only record — which is
enough to know a gym fell, but cannot tell Will from Karen, and says nothing
about the rival.

So the mod keeps its own. `battle.ended` names the trainer it just ended on
**both** engines, and `mod.save` persists under `save.modData[level_caps]` on
both too, so a win against a roster some milestone named is written down as it
happens:

| | class | encounter |
|---|---|---|
| Gen 1 | `battle.oppClass` | `battle.partyIndex` |
| Gold | `trainer.classId` | `trainer.memberId` |

Only rosters a milestone asked for are recorded — a Gold run walks past some
390 trainers and the other 370-odd have no business in a save file. A loss, a
refused battle and a wild fight all record nothing.

The engine's own signals stay as the fallback, so a save made before the mod
ever watched a battle still knows where it is: badges for the Johto gyms, the
Hall of Fame for the league, the Kanto badges for Viridian, and Red's own
spawn flag.

### Installing mid-run

The rival is the awkward case: he awards nothing, so an unrecorded fight is
*unbeaten, lowest and unreachable*, and it would pin the cap there forever.

So the first time the mod can see any confirmed progress — a badge on a loaded
save, or its first recorded win — every signal-less milestone below it is
written off as behind you. Once, and never again. On a fresh save that first
confirmation is the Cherrygrove rival himself, nothing sits below him, and
none of it runs.

One-shot on purpose: level order is not play order. The Goldenrod Underground
rival tops at 32 and is fought *after* Jasmine's 35, so a standing rule would
keep writing off fights that are still ahead of you.

## With the Nuzlocke mod

`mods/nuzlocke` keeps a capability-based provider registry, and this mod
publishes a `level_caps` provider into it. Two things follow, both by that
mod's own design:

- its tracker, Trainer Card and Gym Guide read **this** mod's cap and
  milestone name, because one calculation feeds all of its cap displays;
- its own `exp.gain` wrapper steps aside while a provider is active, so the
  two never compound — one ladder, enforced once.

Set `LEVEL CAP` to `OFF` and the provider goes inactive, which hands the
mechanic straight back to the Nuzlocke ladder. Nothing here claims exclusivity
over the Nuzlocke ruleset itself, and the whole thing is inert when the mod is
not installed.

## The two rows

**LEVEL CAP** — `OFF` (default) / `STRICT` / `MILD UP2` / `SOFT UP5` /
`EASY UP10`.

The bonus is spelled `UP<n>` rather than `+<n>` because the Gen 1 font has no
`+` glyph — it is simply not in the extracted charmap, and the old labels
printed a hole and logged a warning on every draw.

A Pokémon *at* the cap keeps the level it earned and stops there; only levels
strictly above it are out of reach. The block is per-Pokémon, so an
under-levelled reserve keeps growing while your lead sits at the ceiling.

Elite Four caps unlock on the **first win** against each member, on both
games — Gen 1 through the engine's own victory flag, Gold through the record
above.

**ALLOW OVER LVL** — `YES` (default) / `NO`.

`NO` refuses any **trainer** battle while a party member is over the cap. Wild
battles are never refused. Outside the league you fix it at any Poké Center
PC; inside the league, where there is no walking it off, the refusal offers to
send the offenders to the PC for you — and declines rather than leave you with
an empty party.

## UP TO CAP

Open a Pokémon in the party menu and, whenever it is below the current cap,
there is an **UP TO CAP** entry beside `STATS` and `SWITCH`. It walks that
Pokémon up to the cap — **one level at a time**.

The one-at-a-time part is the whole point. Level-up moves are matched on an
*exact* level, so jumping straight to the cap would silently skip every move in
between, and Gen 1 has no move relearner to get them back. Each level runs the
same sequence a Rare Candy does:

1. `X grew to level N!`
2. the stats window
3. every move learned at that level, with the usual four-move prompt
4. an evolution check

The evolution check runs **per level**, not once at the end, so a two-stage
line walked through both thresholds evolves twice — and the next level re-reads
the species, so the new learnset applies immediately.

It is free and instant by design: it exists so a fresh catch can join the team
without grinding, not as a reward. The engine's own level ceiling still wins,
so a generous `EASY UP10` near level 100 stops at 100.

## When would anything even be over the cap?

The cap blocks experience, so normally nothing is. It happens when you turn the
row on mid-run, tighten `EASY UP10` to `STRICT`, receive a trade or gift above
the cap, or use Rare Candy — which is **not** blocked, because it raises a
level without ever going through the experience path.

## Why `engine_internals`

No hook among the engine's 45 can veto a battle: they are all either
observational or fire too late. Both callers that start a trainer battle — the
overworld's sight lines and `Commands.start_battle` — go through
`BattleState.newTrainer`, so that one function is patched, the way
`mods/nuzlocke` patches `throwBall`.

The refusal is wrapped in `pcall` on purpose: if it ever throws, the error is
reported and **the battle goes ahead**. A broken guard must not strand you in
front of a leader you can never fight.

## Known limits

- Rare Candy bypasses the cap (see above).
- Stat exp still accrues at the cap: `Experience.apply` credits it before
  `exp.gain` is consulted.
- The milestone-to-trainer map is fixed (`OPP_BROCK` … `OPP_RIVAL3` on Gen 1,
  `FALKNER` … `RED` on Gold). A total conversion with different leaders gets
  **no** caps rather than wrong ones.
- **`ALLOW OVER LVL` is Gen 1 only.** Refusing a battle needs a battle factory
  to wrap, and Gold's `World:startBattle` constructs and pushes in one call.
  The row says so and stays off; `LEVEL CAP` itself rides `exp.gain`, which
  Gold raises, so the mod's main job is unaffected.
- Gold's Elite Four has no rematch rosters — every boss class carries exactly
  one team — so re-clearing the league changes no cap. The upgraded teams are
  an HGSS feature.

## Composing with `modern_qol`

They stack cleanly. `battle.exp_award` decides *who* is paid, `exp.gain`
decides *how much* — so the cap applies to benched Pokémon too, which is what a
level-capped run wants.

## Credits

- pret/pokered — the trainer rosters and victory flags the caps are derived
  from.
