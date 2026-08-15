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
--   LEVEL CAP       OFF | STRICT (the next milestone top level)
--                       | MILD UP2 | SOFT UP5 | EASY UP10
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

-- Gold, in ladder order. Same rule as Kanto: the cap is read out of the named
-- trainer's real roster, so these are ids only -- no levels.
--
-- Gold does NOT have EVENT_BEAT_<LEADER> flags, and has no flag whatsoever
-- for the rival. Beating a gym leader hands you a BADGE, and the badge IS the
-- record: constants/engine_flags.asm makes ENGINE_ZEPHYRBADGE bit 0 of
-- wJohtoBadges, and the port lands it in save.player.badges
-- (src/world/gen2/World.lua:1669). Reading save.flags for a name nothing
-- writes is why the cap sat at Falkner's 9 forever.
--
-- A badge is enough to know a gym fell, but not enough for the rest: it
-- cannot tell Will from Karen, and the rival awards nothing at all. So each
-- milestone also names the ROSTERS it spans, and the mod records its own flag
-- when battle.ended says one of them was beaten (see "Recording who has
-- actually been beaten" below). `members` are Gold's own member constants --
-- class.trainers[i].id, the very string battle.ended returns as
-- trainer.memberId.
--
-- The engine's four signals stay as the fallback, so a save that predates
-- this record still knows where it is:
--
--   Johto gym    save.player.badges[NAME]
--   E4/Champion  save.hallOfFame.count > 0   -- the count IS "times the
--                champion was beaten" (src/core/gen2/Save.lua:185)
--   Kanto gym    save.player.kantoBadges[NAME]
--   Red          save.spawnAfterChampion == SPAWN_RED
--                (HallOfFame.markRedCredits)
--
-- On vanilla Gold the whole table resolves to
--
--   7 -> 9 -> 16 -> 20 -> 22 -> 25 -> 30 -> 31 -> 35 -> 38 -> 40
--     -> 42 -> 44 -> 46 -> 47 -> 50 -> 58 -> 81
--
-- Deriving rather than copying is the point: a mod that rebalances Whitney
-- moves her cap with her.
--
-- Note the ladder is NOT monotonic in story order -- Jasmine's Steelix is 35
-- and Pryce's Piloswine 31, and the two gyms open in that order. The "lowest
-- top level among the unbeaten, floored by the highest already beaten" pair
-- handles it without a special case.
local function badge(store, name)
  return function(save)
    local owned = save and save.player and save.player[store]
    return type(owned) == "table" and owned[name] == true
  end
end

local function championBeaten(save)
  local hof = save and save.hallOfFame
  return type(hof) == "table"
     and ((tonumber(hof.count) or 0) > 0 or hof.entered == true)
end

local function redBeaten(save)
  if type(save) ~= "table" then return false end
  local ok, HallOfFame = pcall(require, "src.core.gen2.HallOfFame")
  local spawn = ok and type(HallOfFame) == "table" and HallOfFame.SPAWN_RED
  return spawn ~= nil and save.spawnAfterChampion == spawn
end

-- The rival is fought seven times, and Gold stores each fight as THREE
-- rosters, one per starter he took -- RIVAL1_3_TOTODILE is the third fight
-- against the boy who took Totodile. Whichever you meet is the same step of
-- the ladder, so one milestone spans all three, and the cap reads the highest
-- of them: a mod that rebalances only one starter's branch cannot be
-- out-levelled through the other two.
local RIVAL_STARTERS = { "CHIKORITA", "CYNDAQUIL", "TOTODILE" }
local function rivalFight(key, class, nth, extra)
  local members, parties = {}, {}
  for i, starter in ipairs(RIVAL_STARTERS) do
    members[i] = ("%s_%d_%s"):format(class, nth, starter)
    -- Index fallback only, for a dataset that carries no member names; the
    -- three variants of fight N sit together, in starter order.
    parties[i] = (nth - 1) * #RIVAL_STARTERS + i
  end
  local milestone = { key = key, label = "RIVAL", trainer = class,
                      members = members, parties = parties }
  for field, value in pairs(extra or {}) do milestone[field] = value end
  return milestone
end

local GEN2_MILESTONES = {
  -- ---- Johto: the eight gyms and the five rival fights, in ladder order
  --
  -- Cherrygrove opens the game and his roster is a single level-5 starter, so
  -- a strict reading would cap you at 5 before you have fought anything at
  -- all. `bonus` lifts that one step to 7 -- enough room to arrive with a
  -- second Pokemon rather than a coin flip. It is the only milestone that
  -- carries one.
  rivalFight("rival1", "RIVAL1", 1, { bonus = 2 }),
  { key = "zephyr",  label = "FALKNER",  trainer = "FALKNER",  party = 1,
    members = { "FALKNER1" }, done = badge("badges", "ZEPHYR") },
  { key = "hive",    label = "BUGSY",    trainer = "BUGSY",    party = 1,
    members = { "BUGSY1" },   done = badge("badges", "HIVE") },
  rivalFight("rival2", "RIVAL1", 2),
  { key = "plain",   label = "WHITNEY",  trainer = "WHITNEY",  party = 1,
    members = { "WHITNEY1" }, done = badge("badges", "PLAIN") },
  rivalFight("rival3", "RIVAL1", 3),
  { key = "fog",     label = "MORTY",    trainer = "MORTY",    party = 1,
    members = { "MORTY1" },   done = badge("badges", "FOG") },
  { key = "storm",   label = "CHUCK",    trainer = "CHUCK",    party = 1,
    members = { "CHUCK1" },   done = badge("badges", "STORM") },
  { key = "glacier", label = "PRYCE",    trainer = "PRYCE",    party = 1,
    members = { "PRYCE1" },   done = badge("badges", "GLACIER") },
  rivalFight("rival4", "RIVAL1", 4),
  { key = "mineral", label = "JASMINE",  trainer = "JASMINE",  party = 1,
    members = { "JASMINE1" }, done = badge("badges", "MINERAL") },
  rivalFight("rival5", "RIVAL1", 5),
  { key = "rising",  label = "CLAIR",    trainer = "CLAIR",    party = 1,
    members = { "CLAIR1" },   done = badge("badges", "RISING") },

  -- ---- the Elite Four, one step each, and the Champion.
  --
  -- The Hall of Fame is the fallback for all five because it is the only
  -- thing the cart records; the member flags above it are what let the cap
  -- actually walk 42 -> 44 -> 46 -> 47 through the gauntlet instead of
  -- sitting on Will's roster until Lance falls.
  { key = "will",     label = "WILL",     trainer = "WILL",     party = 1,
    members = { "WILL1" },  done = championBeaten },
  { key = "koga2",    label = "KOGA",     trainer = "KOGA",     party = 1,
    members = { "KOGA1" },  done = championBeaten },
  { key = "bruno2",   label = "BRUNO",    trainer = "BRUNO",    party = 1,
    members = { "BRUNO1" }, done = championBeaten },
  { key = "karen",    label = "KAREN",    trainer = "KAREN",    party = 1,
    members = { "KAREN1" }, done = championBeaten },
  { key = "champion", label = "LANCE",    trainer = "CHAMPION", party = nil,
    members = { "LANCE" },  done = championBeaten },

  -- ---- Kanto, the post-game half. Only what is ABOVE the Champion's 50
  -- ---- belongs here: Janine tops at 39 and Blaine at 50, so putting the
  -- ---- seven lesser gyms in the pool could only ever pull the cap back
  -- ---- down a run that had just cleared the league. Their badges are still
  -- ---- what opens Viridian, so nothing is skippable.
  --
  -- Both Kanto rival fights are post-Champion too (Mt. Moon, then the Indigo
  -- Plateau Center). Ungated, Mt. Moon's 45 would slot itself between Koga
  -- and Bruno and cap the middle of the gauntlet on a fight nobody can reach.
  rivalFight("rival6", "RIVAL2", 1, { available = championBeaten }),
  rivalFight("rival7", "RIVAL2", 2, { available = championBeaten }),
  { key = "earth2",   label = "BLUE",     trainer = "BLUE",     party = nil,
    members = { "BLUE1" },
    available = championBeaten, done = badge("kantoBadges", "EARTH") },

  -- ---- and the mountain
  { key = "red",      label = "RED",      trainer = "RED",      party = nil,
    members = { "RED1" },
    available = badge("kantoBadges", "EARTH"), done = redBeaten },
}

-- Milestones that name their rosters get a lookup set, built once: `beaten`
-- and the win recorder both key on it, on every experience payout.
for _, ladderTable in ipairs({ MILESTONES, GEN2_MILESTONES }) do
  for _, milestone in ipairs(ladderTable) do
    if milestone.members then
      local set = {}
      for _, id in ipairs(milestone.members) do set[id] = true end
      milestone.memberSet = set
    end
  end
end

-- MILD sits between STRICT and SOFT. The Gen 1 font has no '+' glyph, which
-- is why every label spells the bonus as UP<n> rather than +<n>.
local OFFSETS = { strict = 0, mild = 2, soft = 5, easy = 10 }

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
                  { "MILD UP2", "mild" },
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
  --   Gen 1  class.parties[i]                    -- a list of rosters
  --   Gold   class.trainers[i] = { id, party }   -- a list of NAMED trainers
  --
  -- Same meaning, so this normalises to one shape and everything downstream
  -- -- including the party index that picks Giovanni's third team -- keeps
  -- working untouched. Gold's names ride along: `id` is the member constant
  -- (FALKNER1, RIVAL1_3_TOTODILE), which is the same string battle.ended
  -- returns as trainer.memberId.
  local function rostersOf(trainer)
    if type(trainer) ~= "table" then return nil end
    local out = {}
    if type(trainer.parties) == "table" and trainer.parties[1] then
      for index, party in ipairs(trainer.parties) do
        out[#out + 1] = { index = index, party = party }
      end
    elseif type(trainer.trainers) == "table" then
      for index, entry in ipairs(trainer.trainers) do
        if type(entry) == "table" and type(entry.party) == "table" then
          out[#out + 1] = { index = index, id = entry.id, party = entry.party }
        end
      end
    end
    return out[1] and out or nil
  end

  -- Which rosters a milestone spans. Named member ids first: they say what
  -- they are and they survive the table being reordered. The index list is
  -- the fallback for a dataset carrying no names -- Gen 1, every fixture --
  -- and `party` is the single-index form the Kanto table has always used.
  -- Neither means "all of them", which is how the Champion's three
  -- starter-dependent teams resolve to one cap.
  local function spanned(milestone, rosters)
    if milestone.memberSet then
      local named = {}
      for _, entry in ipairs(rosters) do
        if entry.id ~= nil and milestone.memberSet[entry.id] then
          named[#named + 1] = entry
        end
      end
      if named[1] then return named end
    end
    local wanted = milestone.parties
      or (milestone.party and { milestone.party })
    if not wanted then return rosters end
    local out = {}
    for _, index in ipairs(wanted) do
      for _, entry in ipairs(rosters) do
        if entry.index == index then out[#out + 1] = entry end
      end
    end
    return out
  end

  local function maxRosterLevel(trainer, milestone)
    local rosters = rostersOf(trainer)
    if not rosters then return nil end
    local best
    for _, entry in ipairs(spanned(milestone, rosters)) do
      for _, slot in ipairs(entry.party or {}) do
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
  -- `bonus` is the one place a number is added, and only one milestone
  -- carries it (Cherrygrove; see the table).
  local function milestoneLevel(milestone)
    local level = maxRosterLevel(mod.content.trainers:get(milestone.trainer),
                                 milestone)
    if not level then return nil end
    return level + (milestone.bonus or 0)
  end

  -- The cap is the LOWEST top-level among the milestones still unbeaten.
  --
  -- That single rule is also the answer to Koga and Sabrina being available
  -- in either order: while both are unbeaten the cap is the lower of the two
  -- (43 and 43 in vanilla, whatever a mod makes them otherwise), and beating
  -- either one leaves the other still governing. No ordering assumption, no
  -- special case, and it generalises to any milestone pair a mod unlocks
  -- together.
  -- "Beaten" is a save FLAG on Red/Blue/Yellow, four different stores on
  -- Gold, and this mod's own record on top of both -- so a milestone may
  -- carry a predicate instead of a flag name, and either may be overtaken by
  -- a win we watched happen. The flag path is untouched, which is what keeps
  -- Gen 1 exactly as it was.
  --
  -- `own` is passed in rather than read here: this runs once per milestone
  -- per experience payout, and one read for the whole sweep is enough.
  local function beaten(milestone, save, own)
    if own and own[milestone.key] then return true end
    if milestone.done then return milestone.done(save) == true end
    return ((save and save.flags) or {})[milestone.flag] == true
  end

  -- A milestone that cannot be reached yet must not govern the cap. Kanto is
  -- post-game and its gyms are unordered, so Janine's 39 sits in the pool from
  -- the very first step -- and being the lowest unbeaten anywhere, it capped a
  -- Johto run at 39 before Clair's 40 ever applied. Gating on the Hall of Fame
  -- is what keeps the two halves of the game from arguing.
  local function available(milestone, save)
    if not milestone.available then return true end
    return milestone.available(save) == true
  end

  -- The highest level already beaten. Kanto's gyms are post-game and can be
  -- done in any order, so their tops run 39 to 58 with no progression to them
  -- -- and Janine's 39 sits BELOW the Champion's 50 you just went through.
  -- Without this floor the cap would drop the moment you entered Kanto,
  -- benching a team the game had just asked you to bring. Gen 1's ladder is
  -- monotonic, so this changes nothing there.
  -- This mod's own record of what it watched fall, out of save.modData.
  -- Never nil, so every caller can index it without a guard.
  local function ownWins()
    local stored = mod.save:get("beaten", nil)
    return type(stored) == "table" and stored or {}
  end

  local function beatenCeiling(save, own)
    own = own or ownWins()
    local best
    for _, milestone in ipairs(milestones()) do
      if available(milestone, save) and beaten(milestone, save, own) then
        local level = milestoneLevel(milestone)
        if level and (not best or level > best) then best = level end
      end
    end
    return best
  end

  -- A milestone with no engine signal of its own: the seven rival fights,
  -- which award neither badge nor flag. Only this mod's record can know one
  -- is beaten, which is what the rule in nextMilestone exists for.
  local function signalless(milestone)
    return milestone.done == nil and milestone.flag == nil
  end

  -- The lowest rung this mod actually watched fall. Everything at or below it
  -- happened while the mod was installed, so an unrecorded milestone down
  -- there was never fought; above it, the mod may simply not have been here.
  local function watchedFrom(own)
    local best
    for _, milestone in ipairs(milestones()) do
      if own[milestone.key] then
        local level = milestoneLevel(milestone)
        if level and (not best or level < best) then best = level end
      end
    end
    return best
  end

  -- Is this milestone behind you, unrecorded, and unreachable?
  --
  -- Only this mod's record can know a rival fight fell -- the cart writes
  -- nothing for one. So on a save the mod was installed onto, an unrecorded
  -- rival is unbeaten, lowest, and impossible to fight again, and it collapses
  -- `cap = max(lowest unbeaten, highest beaten)` into `highest beaten` for the
  -- rest of the run: every win then pays exactly the level of the boss you
  -- just beat and never the next one. A player holding the Zephyr Badge sat on
  -- Falkner's own 9.
  --
  -- Three conditions, and the third is what keeps a WATCHED run exact:
  --
  --   * no signal of its own, so the record is the only witness;
  --   * at or below what you have already cleared -- at OR below, because the
  --     two often tie (Bugsy and the Azalea rival both top at 16), and a
  --     milestone level with the ceiling contributes nothing the floor does
  --     not already give;
  --   * below everything the mod DID watch. On a run it has followed from the
  --     start the record reaches down to the first rung, so nothing is ever
  --     under it and nothing is ever written off -- which matters because
  --     level order is not play order: the Goldenrod Underground rival tops at
  --     32 and is fought after Jasmine's 35, and writing him off when Jasmine
  --     fell would quietly delete a rung.
  --
  -- Nothing is stored and nothing is seeded, so there is no install moment to
  -- get wrong: the answer is re-derived from the save in hand every time. A
  -- mid-run install that lands between two rungs is pinned for one more boss
  -- and then heals itself, because that win puts a record above the stale
  -- rung and the ceiling past it.
  local function strandedBehind(milestone, level, ceiling, watched)
    if not (level and ceiling) then return false end
    if not signalless(milestone) then return false end
    if level > ceiling then return false end
    return watched == nil or watched > level
  end

  local function nextMilestone(save, own)
    own = own or ownWins()
    local ceiling = beatenCeiling(save, own)
    local watched = watchedFrom(own)
    local best, bestLevel
    for _, milestone in ipairs(milestones()) do
      if available(milestone, save) and not beaten(milestone, save, own) then
        local level = milestoneLevel(milestone)
        if level and not strandedBehind(milestone, level, ceiling, watched)
           and (not bestLevel or level < bestLevel) then
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
    local save = g and g.save
    local own = ownWins()
    local milestone, level = nextMilestone(save, own)
    if not level then return nil end
    -- never below what has already been cleared
    local floor_ = beatenCeiling(save, own)
    if floor_ and floor_ > level then level = floor_ end
    return level + offset, milestone
  end

  -- ------------------------------------------------------------------
  -- Recording who has actually been beaten
  --
  -- Gold has no EVENT_BEAT_<LEADER> flag and nothing at all for the rival, so
  -- half this ladder's milestones simply do not exist in the save. They do
  -- not have to. `battle.ended` names the trainer it just ended, on BOTH
  -- engines, and mod.save persists under save.modData[level_caps] on both too
  -- (src/core/Game.lua:1046 and src/core/Game2.lua:204 wire the same bucket,
  -- and Gold's Save.normalize keeps keys it does not know, so it round-trips).
  -- So the mod writes its own flags.
  --
  --   Gen 1  battle.oppClass  + battle.partyIndex        class, roster index
  --   Gold   trainer.classId  + trainer.memberId         two named constants
  --
  -- Only keys a milestone asked for are written: a Gold run walks past some
  -- 390 trainers and the other 370-odd have no business in a save file.
  local function winKey(battle)
    if type(battle) ~= "table" then return nil end
    local trainer = battle.trainer
    if type(trainer) == "table" and trainer.classId and trainer.memberId then
      return tostring(trainer.classId) .. "/" .. tostring(trainer.memberId)
    end
    if battle.oppClass then
      return tostring(battle.oppClass) .. "/" .. tostring(battle.partyIndex or 1)
    end
    return nil
  end

  local watched
  local function watchedKeys()
    if watched then return watched end
    watched = {}
    for _, milestone in ipairs(milestones()) do
      for _, member in ipairs(milestone.members or {}) do
        watched[milestone.trainer .. "/" .. member] = milestone.key
      end
    end
    return watched
  end

  -- A refusal ends the battle with result "run", so a fight this mod turned
  -- away can never mark its own milestone beaten.
  mod.events:on("battle.ended", function(ev)
    if type(ev) ~= "table" or ev.result ~= "win" then return end
    local key = winKey(ev.battle)
    if not key then return end
    local milestoneKey = watchedKeys()[key]
    if not milestoneKey then return end
    local own = ownWins()
    if own[milestoneKey] then return end
    own[milestoneKey] = true
    mod.save:set("beaten", own)
    mod.log:info("milestone %s cleared (%s)", milestoneKey, key)
  end)

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
  -- `game.ready` fires on the boot SKELETON, not on your slot: Gold builds it
  -- in Game2.new and announces it "after the merge, before game.ready, stack
  -- still empty", and both NEW GAME and CONTINUE then "replace the backing
  -- outright" (src/core/Game2.lua:196-212). It is the right place to capture
  -- the live game object -- and the wrong place to read progress from, which
  -- is why nothing here does. The cap derives itself from whatever save is in
  -- hand at the moment it is asked for.
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

  -- ------------------------------------------------------------------
  -- The Nuzlocke mod's provider registry
  --
  -- mods/nuzlocke keeps a capability-based registry (its "INTER-MOD
  -- COMPATIBILITY / PROVIDER REGISTRY" block): it walks the loaded mods and
  -- reads `exports.nuzlocke_provider.<capability>` off each one. Publishing a
  -- `level_caps` provider does two things there, and its own comments say so:
  --
  --   * `nextLevelCapInfo` prefers the provider over its own ladder, and that
  --     one calculation feeds "enforcement, tracker, Trainer Card, Gym Guide
  --     text, and any other cap display" -- so the tracker shows OUR number
  --     and OUR milestone name;
  --   * its `exp.gain` wrapper returns straight to vanilla when a provider is
  --     active, so only one mod enforces and the two cannot compound.
  --
  -- `is_active` is what makes that safe: with LEVEL CAP on OFF we claim
  -- nothing and the Nuzlocke ladder governs again, which is what a player who
  -- turned this row off is asking for. `exclusive` is deliberately absent --
  -- we own the cap, not the Nuzlocke ruleset.
  --
  -- All of this is inert when the mod is absent: nobody reads the export.
  local function providerTarget(g, save)
    if type(g) == "table" and type(g.save) == "table" then return g end
    if type(save) == "table" then return { save = save } end
    return game
  end

  mod.exports.nuzlocke_provider = {
    level_caps = {
      is_active = function()
        return OFFSETS[mod.options:get("level_cap")] ~= nil
      end,
      get_next_cap = function(g, save)
        local cap, milestone = currentCap(providerTarget(g, save))
        if not cap then return nil end
        -- providerCapInfo drops anything over 100 and falls back to the
        -- Nuzlocke ladder; clamping keeps a generous offset near the top of
        -- the game from silently handing the cap back.
        return { cap = math.min(cap, 100),
                 name = milestone and milestone.label or "CAP" }
      end,
    },
  }
end
