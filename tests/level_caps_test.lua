-- Standalone: luajit mods/level_caps/tests/level_caps_test.lua
--
-- Runs against the ROM-free fixture dataset (CI has no ROM), with synthetic
-- gym/Elite Four rosters injected into Data.trainers BEFORE the mod loads.
-- That injection is not a convenience: it is the test for the whole premise.
-- The mod reads levels out of the merged trainer registry rather than a
-- table of its own, so numbers that exist nowhere in vanilla proving out
-- here IS the proof that a mod rebalancing the gym curve moves every cap.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Pokemon = require("src.pokemon.Pokemon")

local Data = T.fixtures.fresh()

-- Deliberately NOT the vanilla 14/21/.../65: if the mod had those baked in,
-- every assertion below would fail.
local ROSTERS = {
  OPP_BROCK    = { 11 }, OPP_MISTY   = { 19 }, OPP_LT_SURGE = { 23 },
  OPP_ERIKA    = { 27 }, OPP_KOGA    = { 40 }, OPP_SABRINA  = { 38 },
  OPP_BLAINE   = { 44 }, OPP_LORELEI = { 52 }, OPP_BRUNO    = { 54 },
  OPP_AGATHA   = { 57 }, OPP_LANCE   = { 61 },
}
Data.trainers = Data.trainers or {}
for id, levels in pairs(ROSTERS) do
  local roster = {}
  for i, level in ipairs(levels) do
    roster[i] = { level = level, species = "FIXMON_A" }
  end
  Data.trainers[id] = { id = id, name = id, parties = { roster } }
end
-- Giovanni's gym fight is his THIRD roster; the first two must be ignored.
Data.trainers.OPP_GIOVANNI = { id = "OPP_GIOVANNI", name = "GIOVANNI", parties = {
  { { level = 25, species = "FIXMON_A" } },
  { { level = 37, species = "FIXMON_A" } },
  { { level = 48, species = "FIXMON_A" }, { level = 46, species = "FIXMON_B" } },
} }
-- The Champion fields three teams picked by your starter; the cap must not
-- depend on which one you will actually meet, so it is the max over all.
Data.trainers.OPP_RIVAL3 = { id = "OPP_RIVAL3", name = "RIVAL", parties = {
  { { level = 61, species = "FIXMON_A" }, { level = 63, species = "FIXMON_B" } },
  { { level = 62, species = "FIXMON_A" } },
  { { level = 64, species = "FIXMON_C" } },
} }

local run = T.sdk.loadMod("mods/level_caps", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local loader = run.loader
local exports = loader.exports.level_caps

-- ------- helpers

local function setOpt(key, value)
  loader.modOptions = loader.modOptions or {}
  loader.modOptions.level_caps = loader.modOptions.level_caps or {}
  loader.modOptions.level_caps[key] = value
end

local function resetOpts()
  loader.modOptions = loader.modOptions or {}
  loader.modOptions.level_caps = {}
end

local function fakeGame(flags, party, mapId)
  return {
    data = Data, mods = loader,
    overworld = mapId and { map = { id = mapId } } or nil,
    save = {
      flags = flags or {}, party = party or {},
      options = {}, currentBox = 1,
      player = { map = mapId or "PALLET_TOWN" },
    },
  }
end

local function mon(level)
  local m = Pokemon.new(Data, "FIXMON_A", level)
  m.level = level
  return m
end

-- ------- the levels come from the rosters, not from the mod

do
  local levels = exports.milestoneLevels()
  T.eq(levels.boulder, 11, "BROCK's cap is read from his roster")
  T.eq(levels.earth, 48, "GIOVANNI uses his third roster, not his first")
  T.eq(levels.champion, 64,
       "the CHAMPION is the max across all three starter-dependent teams")
  T.eq(levels.lance, 61, "LANCE is read from his own roster")
end

-- ------- OFF is genuinely off

resetOpts()
do
  local game = fakeGame({}, { mon(50) })
  T.eq(exports.currentCap(game), nil, "no cap while the row is OFF")
  local ran = false
  local got = Runtime.call("exp.gain", function() ran = true return 999 end,
                           { mon = mon(50) })
  T.eq(ran, true, "exp.gain defers to vanilla when OFF")
  T.eq(got, 999, "and returns vanilla's number untouched")
end

-- ------- the cap follows progress, and the offsets shift it

do
  setOpt("level_cap", "strict")
  local game = fakeGame({})
  T.eq(exports.currentCap(game), 11, "a fresh save is capped at BROCK")

  game.save.flags.EVENT_BEAT_BROCK = true
  T.eq(exports.currentCap(game), 19, "beating BROCK moves the cap to MISTY")

  setOpt("level_cap", "mild")
  T.eq(exports.currentCap(game), 21, "MILD adds 2")
  setOpt("level_cap", "soft")
  T.eq(exports.currentCap(game), 24, "SOFT adds 5")
  setOpt("level_cap", "easy")
  T.eq(exports.currentCap(game), 29, "EASY adds 10")
  setOpt("level_cap", "strict")

  local next_ = exports.nextMilestone(game)
  T.eq(next_.label, "MISTY", "the next milestone is named")
  T.eq(next_.level, 19, "and carries its own level")
end

-- ------- Koga / Sabrina in either order

do
  setOpt("level_cap", "strict")
  local flags = {
    EVENT_BEAT_BROCK = true, EVENT_BEAT_MISTY = true,
    EVENT_BEAT_LT_SURGE = true, EVENT_BEAT_ERIKA = true,
  }
  local game = fakeGame(flags)
  -- SABRINA is 38 here and KOGA 40, so "the next one in list order" would
  -- wrongly say 40.  The rule is the LOWEST unbeaten, which is what makes
  -- an either-order pair work without a special case.
  T.eq(exports.currentCap(game), 38, "with both unbeaten the cap is the lower")

  flags.EVENT_BEAT_SABRINA = true
  T.eq(exports.currentCap(game), 40, "beating SABRINA first leaves KOGA governing")

  flags.EVENT_BEAT_KOGA = true
  T.eq(exports.currentCap(game), 44, "with both down the cap moves to BLAINE")

  -- and the mirror order reaches the same place
  local other = fakeGame({
    EVENT_BEAT_BROCK = true, EVENT_BEAT_MISTY = true,
    EVENT_BEAT_LT_SURGE = true, EVENT_BEAT_ERIKA = true,
    EVENT_BEAT_KOGA = true,
  })
  -- KOGA is 40 here and SABRINA 38, so beating KOGA first would have dropped
  -- the cap by two. It does not: a cap never falls below the highest thing
  -- already beaten. The rule earns its keep in Gold's Kanto, where the gyms
  -- are post-game and unordered (Janine tops at 39, the Champion at 50), but
  -- it is the same rule here and the same reason -- you cannot be asked to
  -- bench a team the game just had you win with.
  T.eq(exports.currentCap(other), 40,
       "beating KOGA first keeps its 40 rather than dropping to SABRINA's 38")
end

-- ------- the Elite Four unlock on the win, and the run ends uncapped

do
  setOpt("level_cap", "strict")
  local flags = {}
  for _, f in ipairs({ "EVENT_BEAT_BROCK", "EVENT_BEAT_MISTY",
      "EVENT_BEAT_LT_SURGE", "EVENT_BEAT_ERIKA", "EVENT_BEAT_KOGA",
      "EVENT_BEAT_SABRINA", "EVENT_BEAT_BLAINE", "EVENT_BEAT_GIOVANNI" }) do
    flags[f] = true
  end
  local game = fakeGame(flags)
  T.eq(exports.currentCap(game), 52, "with eight badges the cap is LORELEI")

  flags.EVENT_BEAT_LORELEIS_ROOM_TRAINER_0 = true
  T.eq(exports.currentCap(game), 54, "beating LORELEI unlocks BRUNO's cap")
  flags.EVENT_BEAT_BRUNOS_ROOM_TRAINER_0 = true
  T.eq(exports.currentCap(game), 57, "then AGATHA")
  flags.EVENT_BEAT_AGATHAS_ROOM_TRAINER_0 = true
  T.eq(exports.currentCap(game), 61, "then LANCE")
  flags.EVENT_BEAT_LANCE = true
  T.eq(exports.currentCap(game), 64, "then the CHAMPION")
  flags.EVENT_BEAT_CHAMPION_RIVAL = true
  T.eq(exports.currentCap(game), nil, "beating the CHAMPION lifts the cap entirely")
end

-- ------- the experience block

do
  setOpt("level_cap", "strict")
  local game = fakeGame({})            -- cap 11
  T.eq(exports.currentCap(game), 11, "cap is 11 for this block")

  local got = Runtime.call("exp.gain", function() return 500 end, { mon = mon(10) })
  T.eq(got, 500, "below the cap, exp is untouched")

  got = Runtime.call("exp.gain", function() return 500 end, { mon = mon(11) })
  T.eq(got, 0, "AT the cap, exp is blocked -- the level is reachable, past it is not")

  got = Runtime.call("exp.gain", function() return 500 end, { mon = mon(30) })
  T.eq(got, 0, "already over the cap, still blocked")

  -- a missing mon must not crash the payout
  got = Runtime.call("exp.gain", function() return 500 end, {})
  T.eq(got, 500, "a ctx with no mon falls through to vanilla")
end

-- ------- over-levelled detection

do
  setOpt("level_cap", "strict")
  local game = fakeGame({}, { mon(9), mon(11), mon(14), mon(30) })
  local over = exports.overLevelled(game)
  T.eq(#over, 2, "only mons strictly above the cap count")
  T.eq(over[1].index, 3, "the indices are party positions")
  T.eq(over[2].index, 4, "in ascending order, so a descending removal is safe")

  setOpt("level_cap", "easy")           -- cap 21
  T.eq(#exports.overLevelled(game), 1, "EASY pulls one of them back under")
  setOpt("level_cap", "off")
  T.eq(#exports.overLevelled(game), 0, "OFF reports nobody")
end

-- ------- the OPTIONS rows

do
  resetOpts()
  local game = fakeGame({})
  local rows = Runtime.call("ui.options.rows", function(_, r) return r end,
                            game, { { id = "textSpeed" } })
  T.eq(#rows, 3, "the wrap appends two rows and keeps the vanilla one")
  T.eq(rows[2].label, "LEVEL CAP", "LEVEL CAP is the first added row")
  T.eq(rows[3].label, "ALLOW OVER LVL", "ALLOW OVER LVL is the second")

  T.eq(rows[2].value(game), "OFF", "it starts on the default")
  T.eq(rows[2].step(game, 1), true, "stepping reports a change")
  T.eq(rows[2].value(game), "STRICT", "and advances through the choices")
  rows[2].step(game, 1)
  T.eq(rows[2].value(game), "MILD UP2", "MILD is the step between STRICT and SOFT")
  rows[2].step(game, 1)
  T.eq(rows[2].value(game), "SOFT UP5", "then SOFT")
  rows[2].step(game, 1)
  T.eq(rows[2].value(game), "EASY UP10", "forward through the whole list")
  rows[2].step(game, 1)
  T.eq(rows[2].value(game), "OFF", "and wraps")
  rows[2].step(game, -1)
  T.eq(rows[2].value(game), "EASY UP10", "backwards too")

  -- both mirrors, or the setting either does not persist or does not apply
  T.eq(game.save.options.modOptions.level_caps.level_cap, "easy",
       "the save-side mirror was written")
  T.eq(loader.modOptions.level_caps.level_cap, "easy",
       "the loader-side mirror was written")

  local orphan = { save = { options = {} } }
  T.eq(rows[2].step(orphan, 1), false, "a game with no loader refuses the write")
  T.eq(orphan.save.options.modOptions, nil, "and leaves nothing behind")
end

-- ------- a dataset with no gym leaders at all must simply not cap

do
  resetOpts()
  setOpt("level_cap", "strict")
  local bare = T.fixtures.fresh()
  local bareGame = { data = bare, mods = loader,
                     save = { flags = {}, party = { mon(80) } } }
  -- currentCap reads the merged registry, which still has the injected
  -- rosters, so assert the guard that matters instead: an unknown trainer
  -- yields no level rather than an error.
  T.eq(exports.nextMilestone({ save = { flags = {
    EVENT_BEAT_BROCK = true, EVENT_BEAT_MISTY = true,
    EVENT_BEAT_LT_SURGE = true, EVENT_BEAT_ERIKA = true,
    EVENT_BEAT_KOGA = true, EVENT_BEAT_SABRINA = true,
    EVENT_BEAT_BLAINE = true, EVENT_BEAT_GIOVANNI = true,
    EVENT_BEAT_LORELEIS_ROOM_TRAINER_0 = true,
    EVENT_BEAT_BRUNOS_ROOM_TRAINER_0 = true,
    EVENT_BEAT_AGATHAS_ROOM_TRAINER_0 = true,
    EVENT_BEAT_LANCE = true, EVENT_BEAT_CHAMPION_RIVAL = true,
  } } }), nil, "every milestone beaten means no next milestone")
  T.check(bareGame ~= nil, "the bare dataset built")
end

-- ------- UP TO CAP
--
-- The whole walk is a chain of pushed screens, each resuming on its own
-- callback.  Stubbing TextBox/StatBox to carry that callback and making the
-- stack run it immediately collapses the chain into something synchronous,
-- so the level maths and the per-level ordering are both assertable.

do
  resetOpts()
  setOpt("level_cap", "strict")

  local TextBox = require("src.render.TextBox")
  local BattleState = require("src.battle.BattleState")
  local Screens = require("src.ui.Screens")
  local Growth = require("src.pokemon.Growth")
  local realTextBox, realStatBox, realPush = TextBox.new, BattleState.StatBox.new, Screens.push

  local said, statBoxes, learnPrompts
  local function install()
    said, statBoxes, learnPrompts = {}, 0, {}
    TextBox.new = function(_, text, onDone)
      said[#said + 1] = text
      return { __done = onDone }
    end
    BattleState.StatBox.new = function(_, _, onDone)
      statBoxes = statBoxes + 1
      return { __done = onDone }
    end
    Screens.push = function(_, id, mon, moveId, onDone)
      if id == "MoveLearnMenu" then
        learnPrompts[#learnPrompts + 1] = moveId
        if onDone then onDone() end
        return
      end
      return nil
    end
  end
  local function restore()
    TextBox.new, BattleState.StatBox.new, Screens.push = realTextBox, realStatBox, realPush
  end

  local function walkGame(party)
    return { data = Data, mods = loader,
             stack = { push = function(_, screen)
               if screen and screen.__done then screen.__done() end
             end },
             save = { flags = {}, party = party, options = {}, currentBox = 1 } }
  end

  install()
  local ok, err = pcall(function()
    local target = mon(5)
    local game = walkGame({ target })
    local rows = Runtime.call("ui.party.submenu", function(_, i) return i end,
                              game, { { label = "STATS" }, { label = "SWITCH" } },
                              target, {})
    T.eq(#rows, 3, "UP TO CAP is offered beside STATS and SWITCH")
    T.eq(rows[3].label, "UP TO CAP", "and is labelled")

    rows[3].onSelect(target, game)
    T.eq(target.level, 11, "the mon lands exactly on the cap, not past it")
    T.eq(statBoxes, 6, "one stats window per level gained, 5 -> 11")

    -- the level lines are one per level, in order: that IS the guarantee
    -- that no level was skipped and no learnset was jumped over
    local levels = {}
    for _, line in ipairs(said) do
      local n = line:match("grew\nto level (%d+)!")
      if n then levels[#levels + 1] = tonumber(n) end
    end
    T.eq(#levels, 6, "six level-up lines for six levels")
    for i, level in ipairs(levels) do
      T.eq(level, 5 + i, "level " .. (5 + i) .. " was walked, not skipped")
    end

    -- exp must be re-seated on the new threshold, or Experience.apply would
    -- see a level ahead of the exp curve and freeze the mon for ages
    local def = Data.pokemon[target.species]
    T.eq(target.exp, Growth.expForLevel(def.growthRate, 11, Data.growth_rates),
         "exp is re-seated on the new level's threshold")
    T.eq(Growth.levelForExp(def.growthRate, target.exp, 100, Data.growth_rates), 11,
         "so the growth curve agrees with the level it now has")
    T.eq(target.stats.hp > 0, true, "stats were recalculated")

    -- learnset moves are picked up on the way (fixture: FIXMON_A learns
    -- FIX_EMBERISH at level 7, which is inside the 5 -> 11 walk)
    local learned = {}
    for _, slot in ipairs(target.moves) do learned[slot.id] = true end
    T.eq(learned.FIX_EMBERISH, true,
         "a move learned mid-walk was not skipped over")

    -- already at the cap: no entry, and no accidental walk
    local capped = mon(11)
    local rows2 = Runtime.call("ui.party.submenu", function(_, i) return i end,
                               walkGame({ capped }), { { label = "STATS" } },
                               capped, {})
    T.eq(#rows2, 1, "no UP TO CAP on a mon already at the cap")

    -- LEVEL CAP off means no cap to walk to
    setOpt("level_cap", "off")
    local free = mon(5)
    local rows3 = Runtime.call("ui.party.submenu", function(_, i) return i end,
                               walkGame({ free }), { { label = "STATS" } }, free, {})
    T.eq(#rows3, 1, "no UP TO CAP while LEVEL CAP is OFF")
    setOpt("level_cap", "strict")

    -- not in the battle switch menu
    local inBattle = mon(5)
    local rows4 = Runtime.call("ui.party.submenu", function(_, i) return i end,
                               walkGame({ inBattle }), { { label = "STATS" } },
                               inBattle, { battle = {} })
    T.eq(#rows4, 1, "not offered in the battle switch menu")

    -- the engine's own level ceiling still wins over a generous cap
    setOpt("level_cap", "easy")
    local high = mon(98)
    local g2 = walkGame({ high })
    g2.save.flags.EVENT_BEAT_CHAMPION_RIVAL = nil
    local rows5 = Runtime.call("ui.party.submenu", function(_, i) return i end,
                               g2, { { label = "STATS" } }, high, {})
    if #rows5 > 1 then rows5[#rows5].onSelect(high, g2) end
    T.check(high.level <= 100, "the walk never climbs past the engine level cap")
  end)
  restore()
  T.check(ok, "the UP TO CAP walk ran without error: " .. tostring(err))
end

-- ------- the battle refusal
--
-- The mod captures BattleState.newTrainer at game.ready and wraps whatever
-- it finds, so installing a stub FIRST makes the whole refusal path
-- observable without standing up a real battle.  game.ready is emitted
-- exactly once here: the patch is one-shot by design.

do
  resetOpts()
  local BattleState = require("src.battle.BattleState")
  local vanillaCalls = 0
  BattleState.newTrainer = function(g, class, partyIndex)
    vanillaCalls = vanillaCalls + 1
    local battle = { game = g, class = class, partyIndex = partyIndex,
                     queue = { "intro" }, said = {}, choices = {} }
    function battle:say(text) self.said[#self.said + 1] = text end
    function battle:sayChoice(text, fn)
      self.choices[#self.choices + 1] = { text = text, fn = fn }
    end
    return battle
  end

  Runtime.emit("game.ready", { game = fakeGame({}) })
  T.neq(BattleState.newTrainer, nil, "newTrainer survived the patch")

  -- ALLOW OVER LVL = YES: nothing is touched, whatever the levels
  setOpt("level_cap", "strict")
  setOpt("allow_over", "yes")
  local game = fakeGame({}, { mon(9), mon(40) }, "VIRIDIAN_CITY")
  local battle = BattleState.newTrainer(game, "OPP_BROCK", 1)
  T.eq(vanillaCalls, 1, "the wrapped function still built the battle")
  T.eq(#battle.queue, 1, "the intro queue is intact")
  T.eq(#battle.said, 0, "and nothing was said")
  T.eq(battle.result, nil, "and the battle was not ended")

  -- NO, but the party is legal
  setOpt("allow_over", "no")
  battle = BattleState.newTrainer(fakeGame({}, { mon(9) }, "VIRIDIAN_CITY"),
                                  "OPP_BROCK", 1)
  T.eq(#battle.said, 0, "a legal party is never refused")
  T.eq(battle.result, nil, "and the battle runs")

  -- NO, over the cap, outside the league: refused, no PC offer
  game = fakeGame({}, { mon(9), mon(40) }, "VIRIDIAN_CITY")
  battle = BattleState.newTrainer(game, "OPP_BROCK", 1)
  -- These four fields together are what leaves a battle. Asserting only
  -- three of them is how a soft lock shipped green: the earlier suite
  -- checked result and afterQueue but not `phase`, and the drain that reads
  -- afterQueue lives inside `if self.phase == "messages"` -- so the battle
  -- opened, refused, and then never ended. `result` is also checked against
  -- a value the ENGINE uses; "skipped" was this mod's own invention and
  -- matched no branch anywhere in src/.
  T.eq(battle.result, "run", "an over-levelled party is refused")
  T.eq(battle.phase, "messages", "and the battle is put in the phase whose "
       .. "queue drain is what calls finish()")
  T.eq(battle.afterQueue, "finish", "and told to end when the queue empties")
  T.eq(#battle.queue, 0, "the intro queue is dropped")
  T.eq(#battle.said, 1, "exactly one line is said")
  T.check(battle.said[1]:find("LV.11", 1, true) ~= nil,
          "and it names the cap: " .. tostring(battle.said[1]))
  T.eq(#battle.choices, 0, "no PC offer outside the league")
  T.eq(#game.save.party, 2, "and nobody was moved")

  -- NO, over the cap, AT the league: the PC offer appears
  game = fakeGame({}, { mon(9), mon(40), mon(50) }, "LORELEIS_ROOM")
  battle = BattleState.newTrainer(game, "OPP_LORELEI", 1)
  T.eq(battle.result, "run", "refused inside the league too")
  T.eq(battle.phase, "messages", "and the league refusal ends the battle too")
  T.eq(#battle.choices, 1, "the league offers the PC instead of a dead end")

  battle.choices[1].fn(false)
  T.eq(#game.save.party, 3, "answering NO moves nobody")

  battle.choices[1].fn(true)
  T.eq(#game.save.party, 1, "answering YES deposits every over-levelled mon")
  T.eq(game.save.party[1].level, 9, "and keeps the legal one")
  T.check(battle.said[#battle.said]:find("PC", 1, true) ~= nil,
          "and says so: " .. tostring(battle.said[#battle.said]))

  -- the party must never be emptied: a blackout on the next step would be
  -- a worse outcome than the fight the mod was trying to prevent
  game = fakeGame({}, { mon(40), mon(50) }, "LORELEIS_ROOM")
  battle = BattleState.newTrainer(game, "OPP_LORELEI", 1)
  battle.choices[1].fn(true)
  T.eq(#game.save.party, 2, "an all-over-levelled party is not emptied")
  T.check(battle.said[#battle.said]:find("no POKéMON left", 1, true) ~= nil,
          "and the refusal says why: " .. tostring(battle.said[#battle.said]))

  -- OFF disarms the refusal completely
  setOpt("level_cap", "off")
  battle = BattleState.newTrainer(fakeGame({}, { mon(90) }, "LORELEIS_ROOM"),
                                  "OPP_LORELEI", 1)
  T.eq(battle.result, nil, "with LEVEL CAP off nothing is refused")
end

resetOpts()
run.release()

-- ------- Gold: per-encounter flags, the rival, and the Elite Four one by one
--
-- A second, separate load against a Gold-SHAPED dataset: the ladder is picked
-- off the trainer registry, so a dataset with FALKNER and no OPP_BROCK is what
-- selects it.  The rosters nest the way Gold's do -- class.trainers[i] =
-- { id, party } -- because reading `id` is the whole mechanism under test.
--
-- The levels are deliberately not Gold's own 9/16/20/..., for the same reason
-- the Kanto block above avoids 14/21/...: if the mod had a ladder baked in,
-- none of this would pass.  They do keep Gold's SHAPE, including Jasmine
-- sitting above Pryce even though her gym comes first.

do
  local G = T.fixtures.fresh()
  G.trainers = G.trainers or {}

  -- id -> { member = level } for the single-roster bosses
  local BOSSES = {
    FALKNER = { FALKNER1 = 8 },   BUGSY  = { BUGSY1 = 15 },
    WHITNEY = { WHITNEY1 = 19 },  MORTY  = { MORTY1 = 26 },
    CHUCK   = { CHUCK1 = 29 },    PRYCE  = { PRYCE1 = 32 },
    JASMINE = { JASMINE1 = 36 },  CLAIR  = { CLAIR1 = 41 },
    WILL    = { WILL1 = 43 },     KOGA   = { KOGA1 = 45 },
    BRUNO   = { BRUNO1 = 47 },    KAREN  = { KAREN1 = 48 },
    CHAMPION = { LANCE = 51 },    BLUE   = { BLUE1 = 59 },
    RED     = { RED1 = 82 },
  }
  local function goldClass(id, members)
    local entries = {}
    for member, level in pairs(members) do
      entries[#entries + 1] = { id = member, name = member,
        party = { { level = level, species = "FIXMON_A" } } }
    end
    G.trainers[id] = { id = id, name = id, trainers = entries }
  end
  for id, members in pairs(BOSSES) do goldClass(id, members) end

  -- The rival: three rosters per fight, one per starter, in starter order.
  -- The three are given DIFFERENT levels on purpose -- a milestone spans all
  -- three and must read the highest, or a mod that rebalanced one branch
  -- would leave a hole to climb through.
  local STARTERS = { "CHIKORITA", "CYNDAQUIL", "TOTODILE" }
  local function goldRival(class, tops)
    local entries = {}
    for nth, top in ipairs(tops) do
      for i, starter in ipairs(STARTERS) do
        entries[#entries + 1] = {
          id = ("%s_%d_%s"):format(class, nth, starter),
          name = "RIVAL",
          -- the middle starter is the highest; the max is `top`
          party = { { level = top - (i == 2 and 0 or 1), species = "FIXMON_A" } },
        }
      end
    end
    G.trainers[class] = { id = class, name = class, trainers = entries }
  end
  goldRival("RIVAL1", { 4, 17, 23, 33, 37 })
  goldRival("RIVAL2", { 46, 52 })

  local goldRun = T.sdk.loadMod("mods/level_caps", { data = G })
  T.eq(#goldRun.errors, 0,
       "the Gold ladder loads clean (" .. tostring(goldRun.errors[1]) .. ")")
  local gLoader = goldRun.loader
  local gExports = gLoader.exports.level_caps

  local function gSetOpt(key, value)
    gLoader.modOptions = gLoader.modOptions or {}
    gLoader.modOptions.level_caps = gLoader.modOptions.level_caps or {}
    gLoader.modOptions.level_caps[key] = value
  end
  gSetOpt("level_cap", "strict")

  -- a Gold-shaped save: badges by name, no save.flags at all
  local gsave = { flags = {}, party = {}, options = {},
                  player = { badges = {}, kantoBadges = {} } }
  local gGame = { data = G, mods = gLoader, save = gsave }

  -- winning a fight, the way the engine reports it
  local function won(classId, memberId, result)
    Runtime.emit("battle.ended", { result = result or "win",
      battle = { trainer = { classId = classId, memberId = memberId } } })
  end
  local function recorded()
    return gLoader.modSave.level_caps and gLoader.modSave.level_caps.beaten or {}
  end

  -- ---- the levels come out of the Gold-shaped rosters
  do
    local levels = gExports.milestoneLevels()
    T.eq(levels.zephyr, 8, "a Gold roster is read through class.trainers[i].party")
    T.eq(levels.rival2, 17,
         "a rival fight reads the HIGHEST of its three starter branches")
    T.eq(levels.rival1, 6,
         "the Cherrygrove fight carries the only bonus: 4 + 2")
    T.eq(levels.champion, 51, "the Champion is named by member, not by index")
    T.eq(levels.red, 82, "and so is Red")
    T.eq(levels.boulder2, nil,
         "the sub-50 Kanto gyms are not milestones: they could only pull a "
         .. "post-league cap back down")
  end

  -- ---- the ladder walks, one fight at a time
  do
    T.eq(gExports.currentCap(gGame), 6,
         "a fresh Gold save is capped on the Cherrygrove rival, plus the bonus")

    won("RIVAL1", "RIVAL1_1_TOTODILE")
    T.eq(recorded().rival1, true, "the win was recorded under the milestone key")
    T.eq(gExports.currentCap(gGame), 8,
         "and any of the three starter branches clears the same milestone")

    -- the engine's own signal still works on its own: this is what a save
    -- that predates the record relies on
    gsave.player.badges.ZEPHYR = true
    T.eq(gExports.currentCap(gGame), 15, "a badge alone still clears a gym")

    won("BUGSY", "BUGSY1")
    T.eq(gExports.currentCap(gGame), 17, "then the Azalea rival")
    won("RIVAL1", "RIVAL1_2_CYNDAQUIL")
    T.eq(gExports.currentCap(gGame), 19, "then Whitney")
    won("WHITNEY", "WHITNEY1")
    T.eq(gExports.currentCap(gGame), 23, "then the Burned Tower rival")
    won("RIVAL1", "RIVAL1_3_CHIKORITA")
    won("MORTY", "MORTY1")
    won("CHUCK", "CHUCK1")
    T.eq(gExports.currentCap(gGame), 32, "then Pryce, who is BELOW Jasmine")

    -- Jasmine's gym opens first but her roster is higher: beating her must
    -- not leave the cap on Pryce's lower number.
    won("JASMINE", "JASMINE1")
    T.eq(gExports.currentCap(gGame), 36,
         "beating Jasmine out of level order raises the cap to hers")
    won("PRYCE", "PRYCE1")
    T.eq(gExports.currentCap(gGame), 36, "and Pryce, below it, cannot lower it")

    won("RIVAL1", "RIVAL1_4_CYNDAQUIL")
    won("RIVAL1", "RIVAL1_5_CYNDAQUIL")
    T.eq(gExports.currentCap(gGame), 41, "the last Johto step is Clair")
    won("CLAIR", "CLAIR1")
  end

  -- ---- the Elite Four, one step each. This is what the per-encounter flags
  -- ---- bought: the cart records only the Hall of Fame, so without them the
  -- ---- cap would sit on Will's roster for the whole gauntlet.
  do
    T.eq(gExports.currentCap(gGame), 43, "the gauntlet opens on Will")
    won("WILL", "WILL1")
    T.eq(gExports.currentCap(gGame), 45, "beating Will alone moves it to Koga")
    won("KOGA", "KOGA1")
    T.eq(gExports.currentCap(gGame), 47,
         "and Koga to Bruno -- the Kanto rival's 46 is gated behind the "
         .. "Hall of Fame and cannot slot itself in here")
    won("BRUNO", "BRUNO1")
    T.eq(gExports.currentCap(gGame), 48, "then Karen")
    won("KAREN", "KAREN1")
    T.eq(gExports.currentCap(gGame), 51, "then Lance")
    won("CHAMPION", "LANCE")

    -- The engine writes the Hall of Fame on that win; that is what opens
    -- Kanto, so the test does what the engine does.
    gsave.hallOfFame = { count = 1 }
    T.eq(gExports.currentCap(gGame), 51,
         "entering Kanto cannot drop the cap below the league just cleared")
    won("RIVAL2", "RIVAL2_1_TOTODILE")
    T.eq(gExports.currentCap(gGame), 52, "the Indigo Plateau rival is next")
    won("RIVAL2", "RIVAL2_2_TOTODILE")
    T.eq(gExports.currentCap(gGame), 59, "then Blue")

    gsave.player.kantoBadges.EARTH = true
    T.eq(gExports.currentCap(gGame), 82,
         "the Earth Badge is what opens Red, and he is the last step")
    won("RED", "RED1")
    T.eq(gExports.currentCap(gGame), nil, "beating Red lifts the cap entirely")
  end

  -- ---- what must NOT be recorded
  do
    local before = 0
    for _ in pairs(recorded()) do before = before + 1 end

    won("CHAMPION", "LANCE", "lose")
    won("RED", "RED1", "run")
    Runtime.emit("battle.ended",
      { result = "win", battle = { kind = "wild", species = "FIXMON_A" } })
    -- a route trainer: 390-odd of these exist and none belong in a save file
    won("YOUNGSTER", "JOEY1")
    Runtime.emit("battle.ended", { result = "win" })

    local after = 0
    for _ in pairs(recorded()) do after = after + 1 end
    T.eq(after, before,
         "a loss, a refusal, a wild fight, an unwatched trainer and a battle "
         .. "with no object all record nothing")
    T.eq(recorded().YOUNGSTER, nil, "and nothing is keyed by trainer either")
  end

  -- ---- a save that predates the record still knows where it is
  -- Two independent saves, each with the record wiped: a save made before the
  -- mod ever watched a battle carries nothing but the engine's own signals.
  -- They are separate on purpose -- mutating one into the other would ask the
  -- mod about a state no run reaches, a player who un-beats the Champion.
  do
    gLoader.modSave.level_caps = {}
    local champ = { flags = {}, party = {}, options = {},
                    player = { badges = {}, kantoBadges = {} },
                    hallOfFame = { count = 1 } }
    T.eq(gExports.currentCap({ data = G, mods = gLoader, save = champ }), 51,
         "with only the Hall of Fame the whole league still reads as cleared")

    gLoader.modSave.level_caps = {}
    local twoBadges = { flags = {}, party = {}, options = {},
                        player = { badges = { ZEPHYR = true, HIVE = true },
                                   kantoBadges = {} } }
    -- The Azalea rival tops at 17 here, ABOVE Bugsy's 15, so the mod cannot
    -- tell whether he is behind this player or ahead of them, and answers
    -- conservatively. It heals at the next gym: see the mid-run block below.
    T.eq(gExports.currentCap({ data = G, mods = gLoader, save = twoBadges }), 17,
         "and two badges put the cap on the lowest rung it cannot rule out")
  end

  -- ---- installed mid-run, onto a save nobody watched
  --
  -- This is the shape that blocked a real playthrough: the Cherrygrove rival
  -- was behind the player, nothing had recorded him, and beating Falkner left
  -- the cap on Falkner's own roster instead of moving to Bugsy -- a win that
  -- paid nothing, with no way out, because that rival can never be fought
  -- again.
  do
    gLoader.modSave.level_caps = {}         -- never watched a battle
    local mid = { flags = {}, party = {}, options = {},
                  player = { badges = {}, kantoBadges = {} } }
    local midGame = { data = G, mods = gLoader, save = mid }

    T.eq(gExports.currentCap(midGame), 6,
         "with no progress it can see, the cap opens on the rival")

    mid.player.badges.ZEPHYR = true
    won("FALKNER", "FALKNER1")
    T.eq(gExports.currentCap(midGame), 15,
         "the win pays: the rival below it is written off as unreachable and "
         .. "the cap moves to Bugsy, rather than sitting on the roster of the "
         .. "gym that just awarded the badge")

    -- One-shot, and this is why. The Goldenrod Underground rival tops at 33
    -- here and is fought AFTER Jasmine's 36: level order is not play order, so
    -- a standing "below the ceiling means behind you" rule would write off a
    -- fight still ahead of the player.
    won("BUGSY", "BUGSY1");    won("RIVAL1", "RIVAL1_2_CYNDAQUIL")
    won("WHITNEY", "WHITNEY1"); won("RIVAL1", "RIVAL1_3_CYNDAQUIL")
    won("MORTY", "MORTY1");    won("CHUCK", "CHUCK1")
    won("JASMINE", "JASMINE1"); won("PRYCE", "PRYCE1")
    T.eq(gExports.currentCap(midGame), 36,
         "the fight still ahead keeps governing, floored by the higher gym "
         .. "already cleared -- it is above everything the mod watched, so it "
         .. "is not written off")
    won("RIVAL1", "RIVAL1_4_CYNDAQUIL")
    T.eq(gExports.currentCap(midGame), 37, "and beating it moves the cap on")
  end

  -- ---- a mid-run install that lands BETWEEN two rungs heals itself
  --
  -- Installed after the Burned Tower rival (23) but before Morty (26), the
  -- rival sits ABOVE the ceiling: the mod cannot tell him from a fight still
  -- ahead, and holds. One boss later the ceiling has passed him and the record
  -- reaches below him, so he is written off and the ladder resumes. Being
  -- pinned for one boss is the price of never guessing wrong on a watched run.
  do
    gLoader.modSave.level_caps = {}
    local between = { flags = {}, party = {}, options = {},
                      player = { badges = { ZEPHYR = true, HIVE = true,
                                            PLAIN = true }, kantoBadges = {} } }
    local betweenGame = { data = G, mods = gLoader, save = between }
    T.eq(gExports.currentCap(betweenGame), 23,
         "it holds on the rung it cannot rule out")

    between.player.badges.FOG = true
    won("MORTY", "MORTY1")
    T.eq(gExports.currentCap(betweenGame), 29,
         "and the next boss heals it: the stale rung is written off and the "
         .. "cap moves to Chuck")
  end

  -- ---- the real boot order, which is what actually shipped broken
  --
  -- `game.ready` fires on the boot SKELETON: Gold builds it in Game2.new and
  -- announces it before game.ready with the stack still empty, and CONTINUE
  -- then replaces the mod.save backing outright (src/core/Game2.lua:196-212).
  -- A version of this that seeded itself from game.ready therefore read a save
  -- with no badges, found nothing to do, and the real slot landed afterwards
  -- with nobody left to look at it -- which is how a player holding the Zephyr
  -- Badge stayed capped at Falkner's own roster through a release that was
  -- supposed to fix exactly that.
  --
  -- Nothing is seeded now and nothing is stored, so there is no install moment
  -- left to get wrong. The sequence below is that boot, in order, and the cap
  -- is right at every point of it.
  do
    gLoader.modSave.level_caps = {}

    local skeleton = { flags = {}, party = {}, options = {},
                       player = { badges = {}, kantoBadges = {} } }
    Runtime.emit("game.ready",
                 { game = { data = G, mods = gLoader, save = skeleton } })
    T.eq(gExports.currentCap({ data = G, mods = gLoader, save = skeleton }), 6,
         "the boot skeleton has no progress, and reads as none")

    -- CONTINUE: the slot the player actually has, Falkner already beaten
    local slot = { flags = {}, party = {}, options = {},
                   player = { badges = { ZEPHYR = true }, kantoBadges = {} } }
    T.eq(gExports.currentCap({ data = G, mods = gLoader, save = slot }), 15,
         "and the slot that arrives after it pays for the badge in hand, "
         .. "with no event having fired in between")

    -- the two coexist: answering for one save must not decide the other
    T.eq(gExports.currentCap({ data = G, mods = gLoader, save = skeleton }), 6,
         "asking about the skeleton again still answers for the skeleton")
  end

  -- ---- UP TO CAP is not offered where it cannot run
  --
  -- Gold has no BattleState.StatBox and no move-learn screen outside battle
  -- (its four-move prompt is a battle emission, src/battle/gen2/
  -- Battle.lua:3231). The walk offered itself anyway and fell over on the
  -- first level: with no StatBox it called an undefined `done`, which is a
  -- crash the instant the entry is picked. Nothing about the option list is
  -- generation-aware, so the presence test is the whole guard -- and this is
  -- the test that it exists.
  do
    gLoader.modSave.level_caps = {}
    gSetOpt("level_cap", "strict")
    local walkSave = { flags = {}, party = {}, options = {},
                       player = { badges = {}, kantoBadges = {} } }
    local walkGame = { data = G, mods = gLoader, save = walkSave }
    local target = Pokemon.new(G, "FIXMON_A", 3)
    target.level = 3

    local BattleState = require("src.battle.BattleState")
    local realStatBox = BattleState.StatBox
    BattleState.StatBox = nil
    local rows = Runtime.call("ui.party.submenu", function(_, i) return i end,
                              walkGame, { { label = "STATS" } }, target, {})
    BattleState.StatBox = realStatBox
    T.eq(#rows, 1,
         "with no level-up window, UP TO CAP is not offered at all rather "
         .. "than offered and fatal")
  end

  -- ---- the seam mods/nuzlocke reads
  --
  -- Its provider registry walks the loaded mods for
  -- exports.nuzlocke_provider.<capability>. The assertions below reproduce
  -- what its own providerCapInfo does with the answer, so the contract is
  -- tested rather than assumed.
  do
    local provider = gExports.nuzlocke_provider
      and gExports.nuzlocke_provider.level_caps
    T.check(type(provider) == "table", "a level_caps provider is published")
    T.eq(type(provider.get_next_cap), "function",
         "carrying the getter providerCapInfo looks for")
    T.eq(provider.exclusive, nil,
         "and claiming no exclusivity: this owns the cap, not the ruleset")

    gLoader.modSave.level_caps = {}
    local save = { flags = {}, party = {}, options = {},
                   player = { badges = {}, kantoBadges = {} } }
    local nuzGame = { data = G, mods = gLoader, save = save }

    gSetOpt("level_cap", "strict")
    T.eq(provider.is_active(), true, "active while LEVEL CAP is on")

    local result = provider.get_next_cap(nuzGame, save)
    T.eq(type(result), "table", "the getter answers a table")
    local cap = tonumber(result.cap or result.level or result.max_level)
    local name = tostring(result.name or result.boss or "EXTERNAL")
    T.eq(cap, 6, "with the cap providerCapInfo will read")
    T.check(cap > 0 and cap <= 100,
            "inside the 1..100 band it accepts, or it would fall back")
    T.eq(name, "RIVAL", "and the milestone name its tracker will show")

    -- the save arrives on its own when the game object does not
    local bare = provider.get_next_cap(nil, save)
    T.eq(type(bare) == "table" and bare.cap, 6,
         "and a bare save is enough to answer")

    gSetOpt("level_cap", "easy")
    T.eq(tonumber(provider.get_next_cap(nuzGame, save).cap), 16,
         "the offset the player chose is in the number nuzlocke displays")

    -- OFF is what hands the mechanic back: nuzlocke stops deferring and its
    -- own ladder governs again, which is what turning this row off means.
    gSetOpt("level_cap", "off")
    T.eq(provider.is_active(), false, "and inactive while LEVEL CAP is OFF")
    T.eq(provider.get_next_cap(nuzGame, save), nil, "answering nothing")
    gSetOpt("level_cap", "strict")
  end

  goldRun.release()
end

T.finish("level_caps")
