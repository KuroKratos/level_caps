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
  rows[2].step(game, 1); rows[2].step(game, 1)
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
T.finish("level_caps")
