-- Level Caps: no Pokemon may out-level the next thing standing in your way.
--
-- The caps are never hard-coded.  Each milestone names a trainer and the
-- flag that marks it beaten; the cap is read out of that trainer's ACTUAL
-- roster at the moment it is needed, so a mod that raises the gym curve --
-- or a total conversion with entirely different leaders -- shifts every cap
-- with it and this mod needs no update.  On vanilla data the table below
-- resolves to 14 / 21 / 24 / 29 / 43 / 43 / 47 / 50 / 56 / 58 / 60 / 62 / 65,
-- which is exactly max(party levels) for each of them.
--
--   LEVEL CAP       OFF | STRICT (the next milestone top level) | SOFT UP5 | EASY UP10
--   ALLOW OVER LVL  YES | NO (refuses the battle; at the league, offers the PC)
--
-- Both default to the permissive setting, so installing this mod and
-- changing nothing leaves the game exactly as it was.

local MOD_ID = "level_caps"

-- Milestones in progression order.  `trainer` + `party` locate the roster,
-- `flag` is the save flag the engine sets on the first win (data/scripts/
-- victories.lua for the gyms and the Elite Four, EVENT_BEAT_CHAMPION_RIVAL
-- for the Champion).  A nil `party` means "the highest level across every
-- one of that trainer's rosters" -- the Champion fields three teams picked
-- by your starter, and the cap must not depend on which one you will meet.
local MILESTONES = {
  { key = "boulder",  label = "BROCK",    trainer = "OPP_BROCK",    party = 1,
    flag = "EVENT_BEAT_BROCK" },
  { key = "cascade",  label = "MISTY",    trainer = "OPP_MISTY",    party = 1,
    flag = "EVENT_BEAT_MISTY" },
  { key = "thunder",  label = "LT.SURGE", trainer = "OPP_LT_SURGE", party = 1,
    flag = "EVENT_BEAT_LT_SURGE" },
  { key = "rainbow",  label = "ERIKA",    trainer = "OPP_ERIKA",    party = 1,
    flag = "EVENT_BEAT_ERIKA" },
  -- Koga and Sabrina can be beaten in either order; see nextCap below.
  { key = "soul",     label = "KOGA",     trainer = "OPP_KOGA",     party = 1,
    flag = "EVENT_BEAT_KOGA" },
  { key = "marsh",    label = "SABRINA",  trainer = "OPP_SABRINA",  party = 1,
    flag = "EVENT_BEAT_SABRINA" },
  { key = "volcano",  label = "BLAINE",   trainer = "OPP_BLAINE",   party = 1,
    flag = "EVENT_BEAT_BLAINE" },
  -- Giovanni's gym fight is his third roster; the first two are Rocket
  -- hideout and Silph (data/scripts/victories.lua OPP_GIOVANNI#3).
  { key = "earth",    label = "GIOVANNI", trainer = "OPP_GIOVANNI", party = 3,
    flag = "EVENT_BEAT_GIOVANNI" },
  { key = "lorelei",  label = "LORELEI",  trainer = "OPP_LORELEI",  party = 1,
    flag = "EVENT_BEAT_LORELEIS_ROOM_TRAINER_0" },
  { key = "bruno",    label = "BRUNO",    trainer = "OPP_BRUNO",    party = 1,
    flag = "EVENT_BEAT_BRUNOS_ROOM_TRAINER_0" },
  { key = "agatha",   label = "AGATHA",   trainer = "OPP_AGATHA",   party = 1,
    flag = "EVENT_BEAT_AGATHAS_ROOM_TRAINER_0" },
  { key = "lance",    label = "LANCE",    trainer = "OPP_LANCE",    party = 1,
    flag = "EVENT_BEAT_LANCE" },
  { key = "champion", label = "CHAMPION", trainer = "OPP_RIVAL3",   party = nil,
    flag = "EVENT_BEAT_CHAMPION_RIVAL" },
}

-- Johto, in progression order. Same rule as Kanto: the cap is read out of the
-- named trainer's real roster, so these are ids and flags only -- no levels.
--
-- On vanilla Gold that resolves to 9 / 16 / 20 / 25 / 30 / 35 / 31 / 40 for
-- the gyms, 42 / 44 / 46 / 47 for the Elite Four and 50 for Lance, which is
-- the ladder the Nuzlocke mod publishes. Deriving rather than copying is the
-- point: a mod that rebalances Whitney moves her cap with her.
--
-- Note the ladder is NOT monotonic -- Jasmine's Steelix is 35 and Pryce's
-- Piloswine 31, and the two gyms open in that order. The "lowest top level
-- among the unbeaten" rule handles it without a special case, exactly as it
-- handles Koga and Sabrina in Kanto.
local GEN2_MILESTONES = {
  { key = "zephyr",   label = "FALKNER",  trainer = "FALKNER",  party = 1,
    flag = "EVENT_BEAT_FALKNER" },
  { key = "hive",     label = "BUGSY",    trainer = "BUGSY",    party = 1,
    flag = "EVENT_BEAT_BUGSY" },
  { key = "plain",    label = "WHITNEY",  trainer = "WHITNEY",  party = 1,
    flag = "EVENT_BEAT_WHITNEY" },
  { key = "fog",      label = "MORTY",    trainer = "MORTY",    party = 1,
    flag = "EVENT_BEAT_MORTY" },
  { key = "storm",    label = "CHUCK",    trainer = "CHUCK",    party = 1,
    flag = "EVENT_BEAT_CHUCK" },
  { key = "mineral",  label = "JASMINE",  trainer = "JASMINE",  party = 1,
    flag = "EVENT_BEAT_JASMINE" },
  { key = "glacier",  label = "PRYCE",    trainer = "PRYCE",    party = 1,
    flag = "EVENT_BEAT_PRYCE" },
  { key = "rising",   label = "CLAIR",    trainer = "CLAIR",    party = 1,
    flag = "EVENT_BEAT_CLAIR" },
  { key = "will",     label = "WILL",     trainer = "WILL",     party = 1,
    flag = "EVENT_BEAT_WILL" },
  { key = "koga2",    label = "KOGA",     trainer = "KOGA",     party = 1,
    flag = "EVENT_BEAT_KOGA" },
  { key = "bruno2",   label = "BRUNO",    trainer = "BRUNO",    party = 1,
    flag = "EVENT_BEAT_BRUNO" },
  { key = "karen",    label = "KAREN",    trainer = "KAREN",    party = 1,
    flag = "EVENT_BEAT_KAREN" },
  { key = "champion", label = "LANCE",    trainer = "CHAMPION", party = nil,
    flag = "EVENT_BEAT_ELITE_FOUR" },
}

local OFFSETS = { strict = 0, soft = 5, easy = 10 }

-- Where a refused battle can offer the PC instead of just saying no: inside
-- the league you cannot walk back to a Pokemon Center between rooms, so a
-- bare refusal would strand the run.
local LEAGUE_MAPS = {
  INDIGO_PLATEAU_LOBBY = true, LORELEIS_ROOM = true, BRUNOS_ROOM = true,
  AGATHAS_ROOM = true, LANCES_ROOM = true, CHAMPIONS_ROOM = true,
}

return function(mod)

  -- One definition feeds both surfaces: the MODS pane renders this schema
  -- itself, and the OPTIONS rows further down cycle the same choice lists,
  -- so the two can never drift apart.
  local ROWS = {
    { key = "level_cap", label = "LEVEL CAP", type = "choice", default = "off",
      choices = { { "OFF", "off" }, { "STRICT", "strict" },
                  -- No '+' in the Gen 1 font: it is simply not in the
                  -- extracted charmap, so "SOFT +5" logged a missing-glyph
                  -- warning on every draw and printed a hole. UP says the
                  -- same thing with letters the font actually has.
                  { "SOFT UP5", "soft" }, { "EASY UP10", "easy" } } },
    { key = "allow_over", label = "ALLOW OVER LVL", type = "choice", default = "yes",
      choices = { { "YES", "yes" }, { "NO", "no" } } },
  }
  mod.options:define(ROWS)

  -- exp.gain's ctx carries no game object, so the live one is captured from
  -- game.ready -- the sanctioned way to reach it (Reference-Events).
  local game

  -- ------------------------------------------------------------------
  -- Reading the caps out of the real rosters

  -- The two carts nest a roster differently, and neither is guessable from
  -- the other:
  --
  --   Gen 1  class.parties[i]          -- a list of rosters
  --   Gold   class.trainers[i].party   -- a list of TRAINERS, each with one
  --
  -- Same meaning, so this normalises to "a list of rosters" and everything
  -- downstream -- including the party index that picks Giovanni's third team
  -- -- keeps working untouched.
  local function rostersOf(trainer)
    if type(trainer) ~= "table" then return nil end
    if type(trainer.parties) == "table" and trainer.parties[1] then
      return trainer.parties
    end
    if type(trainer.trainers) == "table" then
      local out = {}
      for _, entry in ipairs(trainer.trainers) do
        if type(entry) == "table" and type(entry.party) == "table" then
          out[#out + 1] = entry.party
        end
      end
      if out[1] then return out end
    end
    return nil
  end

  local function maxRosterLevel(trainer, partyIndex)
    local rosters = rostersOf(trainer)
    if not rosters then return nil end
    if partyIndex then
      local one = rosters[partyIndex]
      if not one then return nil end
      rosters = { one }
    end
    local best
    for _, roster in ipairs(rosters) do
      for _, slot in ipairs(roster or {}) do
        local level = type(slot) == "table" and slot.level
        if type(level) == "number" and (not best or level > best) then
          best = level
        end
      end
    end
    return best
  end

  -- Which ladder is this cart running? Asked of the trainer registry, because
  -- that is the very table the caps are read from: if BROCK is not there under
  -- his Gen 1 id, no Kanto milestone could resolve a level anyway.
  --
  -- Memoised, because nextMilestone runs on every exp payout.
  local ladder
  local function milestones()
    if ladder then return ladder end
    if mod.content.trainers:get("OPP_BROCK") then
      ladder = MILESTONES
    elseif mod.content.trainers:get("FALKNER")
        or mod.content.trainers:get("WHITNEY") then
      ladder = GEN2_MILESTONES
    else
      -- A fixture or a conversion with neither: the Gen 1 table is the
      -- historical default, and every milestone in it will simply fail to
      -- resolve a level, which currentCap already reads as "no cap".
      ladder = MILESTONES
    end
    return ladder
  end

  -- Read through the merged registry, so another mod's rebalance of a gym
  -- leader is what this sees -- that is the whole point of not hard-coding.
  local function milestoneLevel(milestone)
    return maxRosterLevel(mod.content.trainers:get(milestone.trainer),
                          milestone.party)
  end

  -- The cap is the LOWEST top-level among the milestones still unbeaten.
  --
  -- That single rule is also the answer to Koga and Sabrina being available
  -- in either order: while both are unbeaten the cap is the lower of the two
  -- (43 and 43 in vanilla, whatever a mod makes them otherwise), and beating
  -- either one leaves the other still governing. No ordering assumption, no
  -- special case, and it generalises to any milestone pair a mod unlocks
  -- together.
  local function nextMilestone(save)
    local flags = (save and save.flags) or {}
    local best, bestLevel
    for _, milestone in ipairs(milestones()) do
      if not flags[milestone.flag] then
        local level = milestoneLevel(milestone)
        if level and (not bestLevel or level < bestLevel) then
          best, bestLevel = milestone, level
        end
      end
    end
    return best, bestLevel
  end

  -- nil means "no cap": the row is OFF, or every milestone is beaten, or the
  -- dataset has no roster to read (a fixture, a stripped conversion).
  local function currentCap(g)
    local offset = OFFSETS[mod.options:get("level_cap")]
    if not offset then return nil end
    local milestone, level = nextMilestone(g and g.save)
    if not level then return nil end
    return level + offset, milestone
  end

  -- ------------------------------------------------------------------
  -- Blocking the experience

  -- exp.gain replaces gainFor outright, so returning 0 is a real block --
  -- the max(1, exp) floor lives inside gainFor and never applies here.
  -- A mon exactly AT the cap keeps the level it earned and stops there;
  -- only levels strictly above it are out of reach.
  mod.hooks:wrap("exp.gain", function(next, ctx)
    local cap = currentCap(game)
    if not cap then return next(ctx) end
    local mon = ctx and ctx.mon
    if not mon or (mon.level or 1) < cap then return next(ctx) end
    return 0
  end)

  -- ------------------------------------------------------------------
  -- Refusing a fight the party has outgrown

  local function overLevelled(g, cap)
    local out = {}
    for index, mon in ipairs((g and g.save and g.save.party) or {}) do
      if (mon.level or 1) > cap then
        out[#out + 1] = { index = index, mon = mon }
      end
    end
    return out
  end

  local function atLeague(g)
    local id = (g and g.overworld and g.overworld.map and g.overworld.map.id)
      or (g and g.save and g.save.player and g.save.player.map)
    return id ~= nil and LEAGUE_MAPS[id] == true
  end

  -- Returns true when the party was moved.  Refuses to empty the party: a
  -- player with every mon over the cap would otherwise be left with nothing
  -- to send out, which blacks out on the next step.
  local function depositOver(g, over)
    local save = g and g.save
    local party = save and save.party
    if not party or (#party - #over) < 1 then return false end
    local Boxes = require("src.pokemon.Boxes")
    -- descending, so an earlier removal cannot shift a later index
    for i = #over, 1, -1 do
      local entry = over[i]
      if Boxes.deposit(save, entry.mon) then
        table.remove(party, entry.index)
      end
    end
    return true
  end

  -- Runs on a freshly built trainer battle, before it is pushed.  Ending a
  -- battle early is the engine's own idiom -- set result, point afterQueue
  -- at finish, and say why (mods/nuzlocke does the same on its game over).
  local function refuse(battle, g)
    if mod.options:get("allow_over") ~= "no" then return end
    local cap = currentCap(g)
    if not cap then return end
    local over = overLevelled(g, cap)
    if #over == 0 then return end

    -- Leaving a battle takes FOUR fields, not three.  The engine's own
    -- precedent is the Safari with no Balls left (BattleState.lua:1502):
    --
    --   self:say(...)  self.phase = "messages"
    --   self.result = "run"  self.afterQueue = "finish"
    --
    -- `phase` is the load-bearing one: the drain that reads afterQueue and
    -- calls finish() sits inside `if self.phase == "messages"`, so without it
    -- the queue empties, nothing ends the battle, and the player is stuck in
    -- a fight they were told they cannot have.  `result` must also be a value
    -- the engine actually uses -- "run" leaves the trainer undefeated, which
    -- is exactly what a refused battle means; an invented "skipped" matches
    -- no branch anywhere.
    battle.queue = {}
    battle:say(("Your POKéMON are\nabove the LV.%d cap!"):format(cap))
    if atLeague(g) then
      -- Inside the league there is no walking it off, so offer the way out.
      battle:sayChoice("Send the over-LV.\nones to the PC?", function(yes)
        if not yes then return end
        if depositOver(g, over) then
          battle:say("They were sent\nto the PC!")
        else
          battle:say("But you would have\nno POKéMON left!")
        end
      end)
    end
    battle.phase = "messages"
    battle.result = "run"
    battle.afterQueue = "finish"
  end

  -- ------------------------------------------------------------------
  -- UP TO CAP: walk a Pokemon up to the cap, one level at a time
  --
  -- One at a time is the entire point.  Level-up moves are matched on an
  -- exact level (Experience.movesLearnedAt tests entry.level == level), so
  -- jumping straight to the cap would silently skip every move in between --
  -- and Gen 1 has no move relearner to get them back.
  --
  -- Each level mirrors the Rare Candy sequence exactly
  -- (src/inventory/ItemEffects.lua RARE_CANDY, then src/ui/BagMenu.lua):
  -- bump, re-seat exp, recalc stats, carry the HP delta, then the level
  -- text, the stats window, the move prompts and an evolution check.

  local function say(g, text, done)
    g.stack:push(mod.ui.TextBox.new(g, text, done))
  end

  local function bumpOneLevel(g, mon)
    local Growth = require("src.pokemon.Growth")
    local Stats = require("src.pokemon.Stats")
    local def = g.data.pokemon[mon.species]
    mon.level = (mon.level or 1) + 1
    -- Re-seating exp is not cosmetic.  Experience.apply derives the level
    -- from exp and only climbs while mon.level < that; a level raised
    -- without moving exp would sit frozen until exp caught up on its own.
    -- ItemEffects omits data.growth_rates on this call; passing it keeps a
    -- mod-registered curve honoured, the way Experience.apply does.
    mon.exp = Growth.expForLevel(def.growthRate, mon.level, g.data.growth_rates)
    local old = mon.stats
    mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
    mon.hp = math.min(mon.stats.hp, mon.hp + (mon.stats.hp - old.hp))
    -- Gold's follower has no modifyHappiness (the adapter says so), and a
    -- nil call raises rather than no-ops, so this is a presence test and not
    -- just a pcall.
    pcall(function()
      local Follower = require("src.world.PikachuFollower")
      if type(Follower.modifyHappiness) == "function" then
        Follower.modifyHappiness(g.save, "LEVELUP", mon)
      end
    end)
    return def
  end

  local function learnMovesFor(g, mon, def, level, done)
    local Experience = require("src.battle.Experience")
    local moves = Experience.movesLearnedAt(def, level)
    local index = 0
    local function nextMove()
      index = index + 1
      local moveId = moves[index]
      if not moveId then return done() end
      for _, slot in ipairs(mon.moves or {}) do
        if slot.id == moveId then return nextMove() end
      end
      local moveDef = g.data.moves[moveId]
      if not moveDef then return nextMove() end
      if #(mon.moves or {}) < 4 then
        mon.moves = mon.moves or {}
        table.insert(mon.moves, { id = moveId, pp = moveDef.pp })
        say(g, ("%s learned\n%s!"):format(mon.nickname or def.name, moveDef.name),
            nextMove)
      else
        mod.ui.push(g, "MoveLearnMenu", mon, moveId, nextMove)
      end
    end
    nextMove()
  end

  local function walkToCap(g, mon)
    local cap = currentCap(g)
    if not cap then return end
    local hardCap = ((g.data and g.data.constants) or {}).levelCap or 100
    local ceiling = math.min(cap, hardCap)

    local function step()
      if (mon.level or 1) >= ceiling then return end
      local def = bumpOneLevel(g, mon)
      local name = mon.nickname or def.name
      say(g, ("%s grew\nto level %d!"):format(name, mon.level), function()
        -- Gold builds its stats window elsewhere; without one, the walk
        -- still levels the mon and still offers its moves, it just does not
        -- show the box.
        local StatBox = require("src.battle.BattleState").StatBox
        if not StatBox then return learnMovesFor(g, mon, def, mon.level, done) end
        g.stack:push(StatBox.new(g, mon, function()
          learnMovesFor(g, mon, def, mon.level, function()
            -- Checked per level rather than once at the end, so a two-stage
            -- line walked through both thresholds evolves twice.  evolve
            -- takes a continuation, so the walk resumes after the screen --
            -- and the next bump re-reads the species, which has changed.
            local Evolution = require("src.pokemon.Evolution")
            local evoTo, evo = Evolution.pendingFor(g, mon, { kind = "levelup" })
            if not evoTo then return step() end
            Evolution.evolve(g, mon, evoTo, step, evo and evo.method)
          end)
        end))
      end)
    end
    step()
  end

  mod.hooks:wrap("ui.party.submenu", function(next, g, items, mon, ctx)
    local out = next(g, items, mon, ctx)
    if type(out) ~= "table" or type(mon) ~= "table" then return out end
    -- Not mid-battle, and not on a mon that is already there or past it.
    if ctx and ctx.battle then return out end
    local cap = currentCap(g)
    if not cap or (mon.level or 1) >= cap then return out end
    -- CANCEL exists only in the battle submenu; out of battle the anchor is
    -- missing and insertBefore appends, which is where this belongs anyway.
    return mod.ui.insertBefore(out, "CANCEL", {
      label = "UP TO CAP",
      onSelect = function(target, selectedGame)
        walkToCap(selectedGame or g, target)
      end,
    })
  end)

  local patched = false
  local capsOnly = false
  mod.events:on("game.ready", function(ev)
    game = ev and ev.game
    if patched then return end
    patched = true
    -- No hook can veto a battle -- the 45 the engine calls are all either
    -- observational or too late -- and both callers of newTrainer
    -- (OverworldController's sight lines and Commands.start_battle) go
    -- through this one function, so it is the single honest choke point.
    local BattleState = require("src.battle.BattleState")
    -- Gold has no newTrainer: "World:startBattle constructs and pushes in one
    -- call", so the adapter publishes it absent rather than lie. Wrapping it
    -- anyway would write onto a name nothing reads -- the write would even
    -- read back as ours, which is what makes this failure silent. ALLOW OVER
    -- LVL therefore says it is off rather than appearing to work; the cap
    -- itself rides exp.gain, which Gold raises, so the mod's main job is
    -- unaffected.
    if BattleState.newTrainer == nil then
      capsOnly = true
      mod.log:info("ALLOW OVER LVL needs a battle factory this game does not "
        .. "have, so it stays off; LEVEL CAP itself works normally")
      return
    end
    local vanillaNewTrainer = BattleState.newTrainer
    BattleState.newTrainer = function(g, class, partyIndex)
      local battle = vanillaNewTrainer(g, class, partyIndex)
      -- Fail-safe on purpose: a refusal that throws must leave the battle
      -- playable rather than strand the player in front of a leader they
      -- can never fight.  The error is reported, the fight goes ahead.
      local ok, err = pcall(refuse, battle, g)
      if not ok then
        mod.log:error("over-level refusal failed, letting the battle run: %s",
                      tostring(err))
      end
      return battle
    end
  end)

  -- ------------------------------------------------------------------
  -- The two rows in the game's OPTIONS menu
  --
  -- Mirrors ManagerState:setOption: save.options.modOptions is what
  -- Game:writeOptions persists, loader.modOptions is what mod.options:get
  -- reads, and they are different tables.  Returning true makes
  -- OptionsMenu:update call writeOptions.
  local function setOption(g, key, value)
    local loader = g and g.mods
    if not loader then
      mod.log:warn("no mod loader on the OPTIONS game object; change %s from "
        .. "OPTIONS > MODS instead", key)
      return false
    end
    local save = g.save
    if save and save.options then
      local stored = save.options.modOptions or {}
      save.options.modOptions = stored
      stored[MOD_ID] = stored[MOD_ID] or {}
      stored[MOD_ID][key] = value
    end
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[MOD_ID] = loader.modOptions[MOD_ID] or {}
    loader.modOptions[MOD_ID][key] = value
    return true
  end

  local function cycle(row, dir)
    local current = mod.options:get(row.key)
    local index = 1
    for i, choice in ipairs(row.choices) do
      if choice[2] == current then index = i break end
    end
    index = ((index - 1 + (dir or 1)) % #row.choices) + 1
    return row.choices[index][2]
  end

  local function labelFor(row)
    local current = mod.options:get(row.key)
    for _, choice in ipairs(row.choices) do
      if choice[2] == current then return choice[1] end
    end
    return row.choices[1][1]
  end

  -- next() first, then decorate, so another mod's rows survive this one
  mod.hooks:wrap("ui.options.rows", function(next, g, rows)
    local out = next(g, rows)
    if type(out) ~= "table" then return out end
    for _, row in ipairs(ROWS) do
      out[#out + 1] = {
        id = MOD_ID .. "." .. row.key,
        label = row.label,
        value = function() return labelFor(row) end,
        step = function(target, dir)
          return setOption(target, row.key, cycle(row, dir))
        end,
      }
    end
    return out
  end)

  -- ------------------------------------------------------------------
  -- For other mods: a badge overlay, a tracker, a HUD readout.

  mod.exports.currentCap = function(g) return (currentCap(g or game)) end
  mod.exports.nextMilestone = function(g)
    local milestone, level = nextMilestone((g or game) and (g or game).save)
    if not milestone then return nil end
    return { key = milestone.key, label = milestone.label,
             trainer = milestone.trainer, level = level }
  end
  mod.exports.milestoneLevels = function()
    local out = {}
    for _, milestone in ipairs(milestones()) do
      out[milestone.key] = milestoneLevel(milestone)
    end
    return out
  end
  mod.exports.overLevelled = function(g)
    local target = g or game
    local cap = currentCap(target)
    if not cap then return {} end
    return overLevelled(target, cap)
  end
end
