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

## The two rows

**LEVEL CAP** — `OFF` (default) / `STRICT` / `SOFT +5` / `EASY +10`.

A Pokémon *at* the cap keeps the level it earned and stops there; only levels
strictly above it are out of reach. The block is per-Pokémon, so an
under-levelled reserve keeps growing while your lead sits at the ceiling.

Elite Four caps unlock on the **first win** against each member — the engine
already sets a victory flag there, so it happens the moment the battle ends.

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
so a generous `EASY +10` near level 100 stops at 100.

## When would anything even be over the cap?

The cap blocks experience, so normally nothing is. It happens when you turn the
row on mid-run, tighten `EASY` to `STRICT`, receive a trade or gift above the
cap, or use Rare Candy — which is **not** blocked, because it raises a level
without ever going through the experience path.

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
- The milestone-to-trainer map is fixed (`OPP_BROCK` … `OPP_RIVAL3`). A total
  conversion with different leaders gets **no** caps rather than wrong ones.

## Composing with `modern_qol`

They stack cleanly. `battle.exp_award` decides *who* is paid, `exp.gain`
decides *how much* — so the cap applies to benched Pokémon too, which is what a
level-capped run wants.

## Credits

- pret/pokered — the trainer rosters and victory flags the caps are derived
  from.
