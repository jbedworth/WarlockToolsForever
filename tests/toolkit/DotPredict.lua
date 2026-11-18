local _, ns = ...
local DyresToolkit = ns.toolkit

-- DoT damage prediction, for every Dyre's AddOn (Toolkit 2.5.0, engine stage
-- C; lead-approved plan, 2026-11-01). Moved from Warlock Tools Forever
-- 1.4.1's Predict.lua, which keeps its own copy until it switches over; its
-- rules are this file's spec. The block on a health bar is the damage your
-- DoTs still have to deal, and DIES when that is at least the mob's health
-- (drawn by HealthBars.lua).
--
-- It needs the combat log: COMBAT_LOG_EVENT_UNFILTERED by mob GUID, also for
-- mobs no unit shows. Each DoT's tick is learned from its ticks (exact:
-- talents, spell power, and resists included) and saved per rank, account
-- wide, with the spell power it was learned at; the next cast of that rank
-- starts from it, rescaled to your spell power then. With nothing saved, the
-- rank's base damage plus spell power.
--
-- Where the combat log is restricted (WoW: Forever), the hidden-ticks path
-- (2.6.0; John, 2026-11-08: "Design it", "Yes, build it"; design in
-- docs/FOREVER_PREDICT.md). The method is Does It Die's (Joe Greive, v0.9.x,
-- which John checked in client on Forever); the code is our own:
--   - Your cast: UNIT_SPELLCAST_SENT names the mob (by name, at the target,
--     focus, soft enemy, or mouseover), SUCCEEDED starts the DoT. Its base
--     damage and duration come from its tooltip (C_Spell.GetSpellDescription,
--     without spell power), else ClassData's rank.
--   - A mob is its GUID, else the plate memory's, else "plate:nameplateN"
--     (GUIDs are secret in instances), else "target".
--   - UNIT_COMBAT: the first outcome on the mob within OUTCOME_WINDOW after
--     the cast says whether it landed (a spell avoid in its school drops it).
--     A WOUND or ABSORB in the DoT's school, within TICK_WINDOW of an open
--     tick slot (TICK_WINDOW_ANCHORED once its first tick is seen), is a
--     tick; its amount is secret in combat, so it counts without a size.
--   - One timer per DoT, at each tick slot's end: a missed tick while a unit
--     shows the mob counts (MISSES_TO_DROP drop it: resisted, removed, or the
--     mob died); a slot no unit shows marks it unseen. No OnUpdate.
--   - After combat, the damage meter (C_DamageMeter, readable a few seconds
--     later) gives each spell's total; with every DoT of one rank seen,
--     total over the ticks seen is the tick, saved as on Era. Not for a
--     family with a direct hit (Immolate).
--   - Health is secret: HealthBars draws with it (its DIES gate).
--
-- The learned ticks are the one store an engine keeps (lead decision 1):
-- DyresToolkitDB.ticks[rank spell ID] = {tick, power}, shared by every
-- Dyre's AddOn, with a one-time copy of an owner's older table
-- (spec.legacyTicks: WTF's WarlockToolsForeverAccountDB.ticks).
--
-- Every class (the DDT class gate; lead, 2026-11-14, John: "go with your
-- recommendations"; Dyre's Debuff Tracker's class audit):
--   - A rank may have no base damage (false; option a): no first guess, so
--     the DoT counts from its first tick with an amount (the combat log), a
--     saved tick, or its tooltip (Forever). A rank with no duration (nil:
--     Forever-only spells whose duration is not checked) counts only when
--     its tooltip gives one. A nil level is not in the sources.
--   - Finishers (family `finisher`; Rip, Rupture): the combo points are read
--     at UNIT_SPELLCAST_SENT, as Does It Die does (by SUCCEEDED they are
--     spent). `pointDuration` {base, per point} gives the duration (Rupture
--     6 + 2 per point, LibClassicDurations); the tooltip's "N points: X
--     damage over Y sec" line gives the damage (Does It Die's
--     parseFinisher, the method only). Unreadable points (secret in combat
--     on Forever): 1 point, so the guess errs low, and nothing is saved.
--     Saved ticks are per point: ticks[rank].points[n] = {tick, power}.
--   - Late starts (family `late`; Serpent Sting, Fireball, Pyroblast,
--     Frostfire Bolt): the DoT starts as the projectile lands, not at the
--     cast. On the hidden path a `direct` one starts at its own hit in its
--     school; until a landing or a first tick, each tick slot may come
--     PROJECTILE_TRAVEL later (Does It Die: Serpent Sting's first tick came
--     3.6-3.9 s after the cast). The Era combat log starts it at the aura.
--   - `mask` overrides the school's mask (Frostfire 4 + 16, Does It Die);
--     `ground` (Immolation Trap) never starts from a cast on the hidden path:
--     the trap has no mob at the cast.

local LOW_LEVEL = 20
local LOW_LEVEL_PENALTY = 0.0375
local MAX_NAMEPLATE_UNITS = 40
local TICKS = {SPELL_PERIODIC_DAMAGE = true, SPELL_PERIODIC_LEECH = true}
local MISSED = "SPELL_PERIODIC_MISSED"
local DEBUFF = "DEBUFF"
local APPLIED = {SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true}
local DEATHS = {UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true}
local EXPIRY_GRACE = 0.5
-- The hidden-ticks path (Forever). Timing from Does It Die's in-client
-- findings: a first tick lands within about 0.1 s of one interval after the
-- cast, later ones within about 0.1 s of the first tick's rhythm.
local TICK_WINDOW = 0.45
local TICK_WINDOW_ANCHORED = 0.25
local MISSES_TO_DROP = 2
local OUTCOME_WINDOW = 0.4
local SENT_EXPIRY = 10
local MIN_METER_TICKS = 2
local METER_SHARE_MIN, METER_SHARE_MAX = 0.5, 2.5
local METER_RETRY, METER_TRIES = 0.5, 20
-- A projectile's flight, at most (Does It Die's PROJECTILE_TRAVEL).
local PROJECTILE_TRAVEL = 1.5
local MAX_POINTS = 5

-- The combat log's reader, else nil (CombatLogGetCurrentEventInfo is only a
-- deprecation fallback on Era); the same gate as Dyre's Crit Mayhem.
local function EventInfoReader()
    if type(C_CombatLog) == "table" and type(C_CombatLog.GetCurrentEventInfo) == "function" then
        return C_CombatLog.GetCurrentEventInfo
    end
    if type(CombatLogGetCurrentEventInfo) == "function" then
        return CombatLogGetCurrentEventInfo
    end
end

function DyresToolkit.CombatLogUsable()
    if type(C_CombatLog) == "table" and type(C_CombatLog.IsCombatLogRestricted) == "function" then
        local restricted = C_CombatLog.IsCombatLogRestricted()
        if DyresToolkit.IsSecret(restricted) or restricted then
            return false
        end
    end
    return EventInfoReader() ~= nil
end

-- Without the combat log: what UNIT_COMBAT and the damage meter need.
function DyresToolkit.HiddenTicksUsable()
    return type(C_Timer) == "table" and type(C_Timer.After) == "function" and type(GetTime) == "function"
end

-- Every rank any class table knows, so a saved tick of a rank no table
-- lists any more is dropped; and every family, for a client's own spell ID
-- learned on Forever (saved with its family).
local function AllRanks()
    local all, families = {}, {}
    for _, data in pairs(DyresToolkit.ClassData) do
        for id in pairs(data.ranks or {}) do
            all[id] = true
        end
        for name in pairs(data.families or {}) do
            families[name] = true
        end
    end
    return all, families
end

local function GoodTick(entry)
    return type(entry) == "table" and type(entry.tick) == "number" and entry.tick > 0
        and type(entry.power) == "number" and entry.power >= 0
end

local function KnownTick(id, entry, ranks, families)
    return type(id) == "number" and type(entry) == "table" and (ranks[id] or families[entry.family] == true)
        and GoodTick(entry)
end

-- A finisher's ticks per combo point: only whole points 1-5 with a good tick.
local function RepairPoints(entry)
    if entry.points == nil then
        return
    end
    if type(entry.points) ~= "table" then
        entry.points = nil
        return
    end
    for points, each in pairs(entry.points) do
        if type(points) ~= "number" or points < 1 or points > MAX_POINTS or points % 1 ~= 0 or not GoodTick(each) then
            entry.points[points] = nil
        end
    end
end

-- The table repaired this session (SavedVariables replace ns.db at load).
local repaired

-- The saved ticks, repaired once a session: only {tick > 0, power >= 0}
-- entries of known ranks stay (WTF Core's LoadTicks rule).
function DyresToolkit.LearnedTicks()
    local saved = ns.db.ticks
    if type(saved) ~= "table" then
        saved = {}
        ns.db.ticks = saved
    end
    if repaired ~= saved then
        repaired = saved
        local ranks, families = AllRanks()
        for id, entry in pairs(saved) do
            if not KnownTick(id, entry, ranks, families) then
                saved[id] = nil
            else
                RepairPoints(entry)
            end
        end
    end
    return saved
end

-- An owner's older ticks, copied once per owner: only ranks not yet saved,
-- so a newer learned tick is never overwritten.
local function ImportTicks(addon, legacy)
    if type(legacy) ~= "table" then
        return
    end
    if type(ns.db.ticksImported) ~= "table" then
        ns.db.ticksImported = {}
    end
    if ns.db.ticksImported[addon] then
        return
    end
    ns.db.ticksImported[addon] = true
    local ticks = DyresToolkit.LearnedTicks()
    local ranks = AllRanks()
    for id, entry in pairs(legacy) do
        if ticks[id] == nil and ranks[id] and KnownTick(id, entry, ranks, {}) then
            ticks[id] = {tick = entry.tick, power = entry.power}
        end
    end
end

-- spec (required: addon, store, ranks and families or class):
--   addon       the owning AddOn's folder name (its HealthBars source)
--   priority    HealthBars source priority (10 class AddOn, 5 DDT)
--   class       "WARLOCK": ranks, families, familyOrder from ClassData
--   store       the owner's saved table, read live: enabled, plates, dies,
--               fill, opacity, outline
--   color       function() -> {r, g, b}: the block's color
--   legacyTicks the owner's older saved ticks, copied once
-- Returns the predictor, else nil and why. Without the combat log (Forever)
-- it reads hidden ticks (predictor.hidden is true); with neither, nil and
-- "the combat log".
function DyresToolkit.CreateDotPredictor(spec)
    if type(spec) ~= "table" or type(spec.addon) ~= "string" or type(spec.store) ~= "table" then
        return nil, "spec"
    end
    local classData = spec.class and DyresToolkit.ClassSpells(spec.class) or {}
    local RANKS = spec.ranks or classData.ranks
    local FAMILIES = spec.families or classData.families
    local FAMILY_ORDER = spec.familyOrder or classData.familyOrder or {}
    if type(RANKS) ~= "table" or next(RANKS) == nil or type(FAMILIES) ~= "table" then
        return nil, "ranks"
    end
    local hidden = not DyresToolkit.CombatLogUsable()
    if hidden and not DyresToolkit.HiddenTicksUsable() then
        return nil, "the combat log"
    end
    if type(C_NamePlate) ~= "table" or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then
        return nil, "C_NamePlate.GetNamePlateForUnit"
    end
    local store = spec.store
    local api = DyresToolkit.HealthBars
    local predict = {mobs = {}, byName = {}, lastCast = {}, plates = {}, units = {}, read = EventInfoReader(),
        player = UnitGUID("player"), hidden = hidden, sent = {}, power = {}, spells = {}, tally = {}, points = {}}
    local events = CreateFrame("Frame")
    ImportTicks(spec.addon, spec.legacyTicks)

    local function Weight(family, tick)
        return DyresToolkit.TickWeight(FAMILIES[family], tick)
    end

    -- Spell power can be secret in combat (Forever): the last readable value
    -- of that school counts then.
    local function SpellPower(family)
        local school = FAMILIES[family].school
        local power = type(GetSpellBonusDamage) == "function" and GetSpellBonusDamage(school) or 0
        if DyresToolkit.IsSecret(power) or type(power) ~= "number" or power < 0 then
            return predict.power[school] or 0
        end
        predict.power[school] = power
        return power
    end

    -- The first guess for the whole DoT: base damage plus spell power, a
    -- share of it by duration / 15 (at most 1) or the family's coefficient,
    -- less 3.75% per level for ranks learned below 20.
    -- A rank: {family, damage over time, duration, level}; on the hidden path
    -- from the cast's own tooltip when it reads (predict.spells).
    local function RankOf(rankID)
        return predict.spells[rankID] or RANKS[rankID]
    end

    -- Nil for a rank with no base damage (option a): no first guess.
    local function GuessTotal(rank, duration, power)
        if type(rank[2]) ~= "number" then
            return nil
        end
        local share = FAMILIES[rank[1]].coefficient or math.min(1, duration / 15)
        if type(rank[4]) == "number" and rank[4] < LOW_LEVEL then
            share = share * (1 - (LOW_LEVEL - rank[4]) * LOW_LEVEL_PENALTY)
        end
        return rank[2] + power * share
    end

    -- Combo points ----------------------------------------------------------------

    -- Your combo points now, else nil (secret, unreadable, or none): the most
    -- any readable API says (Does It Die's readComboPoints, the method only).
    local function ComboPoints()
        local best
        local function Consider(ok, points)
            if ok and not DyresToolkit.IsSecret(points) and type(points) == "number" and points > 0 then
                best = math.max(best or 0, points)
            end
        end
        if type(GetComboPoints) == "function" then
            Consider(pcall(GetComboPoints, "player", "target"))
        end
        local kind = type(Enum) == "table" and type(Enum.PowerType) == "table" and Enum.PowerType.ComboPoints
        if kind and type(UnitPower) == "function" then
            Consider(pcall(UnitPower, "player", kind))
        end
        return best and math.min(best, MAX_POINTS) or nil
    end

    local function FamilyOfSpell(spellID)
        if DyresToolkit.IsSecret(spellID) or type(spellID) ~= "number" then
            return nil
        end
        local rank = RANKS[spellID]
        return rank and rank[1] or predict.byName[DyresToolkit.SpellName(spellID) or ""]
    end

    -- A finisher's points as it is sent (nil: unreadable).
    local function NotePoints(spellID)
        local family = FamilyOfSpell(spellID)
        if family and FAMILIES[family].finisher then
            predict.points[family] = {points = ComboPoints(), at = GetTime()}
        end
    end

    -- The points of the family's last send, if recent.
    local function SentPoints(family)
        local sent = predict.points[family]
        if sent and GetTime() - sent.at <= SENT_EXPIRY then
            return sent.points
        end
    end

    -- The DoT's duration: by points for a finisher with `pointDuration`
    -- (unknown points: 1, so it errs low), else the rank's.
    local function Duration(family, rank, points)
        local per = FAMILIES[family].pointDuration
        if type(per) == "table" then
            return per[1] + per[2] * (points or 1)
        end
        return rank[3]
    end

    -- The saved tick for this rank (and points, for a finisher); nil when
    -- a finisher's points are unknown.
    local function SavedTick(rankID, family, points)
        local saved = DyresToolkit.LearnedTicks()[rankID]
        if not FAMILIES[family].finisher then
            return saved
        end
        local each = points and saved and type(saved.points) == "table" and saved.points[points]
        return GoodTick(each) and each or nil
    end

    local function SaveTick(dot, family)
        local tick = math.floor(dot.average * 10 + 0.5) / 10
        local ticks = DyresToolkit.LearnedTicks()
        if FAMILIES[dot.family].finisher then
            if not dot.points then
                return
            end
            local entry = ticks[dot.rank]
            if type(entry) ~= "table" then
                entry = {}
            end
            entry.tick, entry.power, entry.family = tick, dot.power, family
            entry.points = type(entry.points) == "table" and entry.points or {}
            entry.points[dot.points] = {tick = tick, power = dot.power}
            ticks[dot.rank] = entry
            return
        end
        ticks[dot.rank] = {tick = tick, power = dot.power, family = family}
    end

    -- A tick is the average tick, except with weights (Curse of Agony): the
    -- ramp applies to the rank's base damage only, the rest (spell power) is
    -- spread evenly over the ticks.
    local function TickAmount(dot, tick)
        local weight = Weight(dot.family, tick)
        if weight == 1 then
            return dot.average
        end
        return math.max(0, dot.base * weight + dot.average - dot.base)
    end

    local function AverageFrom(dot, tick, amount)
        return amount - dot.base * Weight(dot.family, tick) + dot.base
    end

    -- A saved tick rescaled to your spell power now: only the part above the
    -- rank's base grows with spell power.
    local function Rescale(saved, base, power)
        local bonus = saved.tick - base
        if saved.power > 0 and bonus > 0 then
            return base + bonus * power / saved.power
        end
        return saved.tick
    end

    local function TicksDone(dot, now)
        local due = math.floor((now - dot.applied) / dot.interval)
        return math.min(dot.ticks, math.max(dot.seen, due))
    end

    local function DotRemaining(dot, now)
        -- No base damage and nothing learned yet: nothing to count.
        if not dot.average then
            return 0
        end
        local remaining = 0
        for tick = TicksDone(dot, now) + 1, dot.ticks do
            remaining = remaining + TickAmount(dot, tick)
        end
        return remaining
    end

    function predict:Available()
        return true
    end

    function predict:PredictedDamage(guid)
        local mob = self.mobs[guid]
        if not mob then
            return 0
        end
        local now, total = GetTime(), 0
        for _, dot in pairs(mob.dots) do
            -- A doubtful DoT (an avoid it may not own) counts from its first tick.
            if not dot.doubtful then
                total = total + DotRemaining(dot, now)
            end
        end
        return math.floor(total + 0.5)
    end

    -- Drawing ------------------------------------------------------------------

    -- The owner's DIES place and offsets per kind (John, 2026-11-09): store
    -- diesPlace, diesX, diesY for the target and focus frames, and
    -- plateDiesPlace, plateDiesX, plateDiesY for nameplates. "auto" or nil is
    -- the toolkit's own choice. Rows keep theirs.
    local DIES_KEYS = {target = {"diesPlace", "diesX", "diesY"}, plate = {"plateDiesPlace", "plateDiesX", "plateDiesY"}}

    local function Look(kind)
        local color = spec.color and spec.color() or {0.6, 0.2, 0.9}
        local look = {fill = store.fill, color = color, opacity = store.opacity, outline = store.outline,
            dies = store.dies}
        local keys = DIES_KEYS[kind]
        if keys then
            local place = store[keys[1]]
            look.side = place ~= "auto" and place or nil
            look.x, look.y = store[keys[2]], store[keys[3]]
        end
        return look
    end

    local function HideOverlay(bar)
        if bar then
            DyresToolkit.HidePrediction(bar)
        end
    end

    -- Whether this owner draws on the target frame and the nameplates.
    local function Mine()
        return api.IsActiveSource(spec.addon) == true
    end

    -- A tracker row is the owner's own bar, so it always draws: this damage,
    -- or the active source's while another one is.
    local function RowDamage(guid)
        if Mine() then
            return predict:PredictedDamage(guid)
        end
        return api.GetPredictedDamage(guid) or 0
    end

    local function Same(a, b)
        local same = UnitIsUnit(a, b)
        return not DyresToolkit.IsSecret(same) and same == true
    end

    -- The mob a unit shows: its GUID; on the hidden path, where GUIDs are
    -- secret (instances), the plate memory's, else its nameplate's token
    -- key, else "target". Nil when unknown.
    local function Key(unit)
        if DyresToolkit.IsSecret(unit) or type(unit) ~= "string" then
            return nil
        end
        local guid = DyresToolkit.ReadGUID(unit)
        if guid or not hidden then
            return guid
        end
        local token = DyresToolkit.PlateToken(unit)
        if token then
            return DyresToolkit.PlateKey(token)
        end
        if unit == "target" or Same(unit, "target") then
            return "target"
        end
    end
    predict.Key = Key

    local function Draw(unit, bar, kind, info)
        if not bar then
            return
        end
        local key = Key(unit)
        local canAttack = UnitCanAttack("player", unit)
        -- A secret "can attack" (Forever) counts for a mob we track.
        local hostile
        if DyresToolkit.IsSecret(canAttack) then
            hostile = hidden
        else
            hostile = canAttack == true
        end
        if not store.enabled or not key or not hostile or DyresToolkit.IsDead(unit) then
            HideOverlay(bar)
            return
        end
        DyresToolkit.DrawPrediction(bar, kind, predict:PredictedDamage(key), UnitHealth(unit), Look(kind), info)
    end

    -- A DoT tracker row's health bar: the row's mob and the health the bar
    -- shows. Returns whether DIES shows, so the row can make room.
    -- place: where DIES goes while the health reads (in place of the number);
    -- secretPlace: where it goes while the health is secret, when the row
    -- keeps its numbers (John's screenshot, 2026-11-09: "43% |4DIES", DIES at
    -- the bar's end on top of the number); nil is the bar's right end.
    function predict:DrawRow(bar, guid, health, place, secretPlace)
        if not bar then
            return false
        end
        if not store.enabled or type(guid) ~= "string" then
            HideOverlay(bar)
            return false
        end
        local dies = DyresToolkit.DrawPrediction(bar, "row", RowDamage(guid), health, Look())
        -- With a secret health no one knows whether DIES shows, so the row
        -- keeps its numbers and DIES goes beside them, not on them.
        if DyresToolkit.IsSecret(health) then
            DyresToolkit.MoveDies(bar, secretPlace)
        else
            DyresToolkit.MoveDies(bar, place)
        end
        return dies == true
    end

    local function RefreshRows(guid)
        if predict.tracker then
            predict.tracker:RefreshPrediction(guid)
        end
    end

    local function DrawUnitFrame(unit)
        if not Mine() then
            return
        end
        local bar, info = DyresToolkit.FindUnitBar(unit)
        DyresToolkit.UseBar(predict.units, unit, bar, info)
        Draw(unit, bar, "target", info)
    end

    local function DrawPlate(unit)
        if not Mine() then
            return
        end
        local bar, info = DyresToolkit.FindPlateBar(unit)
        DyresToolkit.UseBar(predict.plates, unit, bar, info)
        if store.plates then
            Draw(unit, bar, "plate", info)
        else
            HideOverlay(bar)
        end
    end

    local function IsGUID(unit, guid)
        return Key(unit) == guid
    end

    local function DrawGUID(guid)
        for _, unit in ipairs({"target", "focus"}) do
            if IsGUID(unit, guid) then
                DrawUnitFrame(unit)
            end
        end
        for unit in pairs(predict.plates) do
            if IsGUID(unit, guid) then
                DrawPlate(unit)
            end
        end
        -- A token key ("plate:nameplate3", "target") is not a GUID for others.
        local real = guid:find("-", 1, true) and guid or nil
        RefreshRows(real)
        api.NotifyChanged(spec.addon, nil, real)
    end

    local function DrawAll()
        DrawUnitFrame("target")
        DrawUnitFrame("focus")
        for index = 1, MAX_NAMEPLATE_UNITS do
            local unit = "nameplate" .. index
            if UnitExists(unit) then
                DrawPlate(unit)
            end
        end
        RefreshRows(nil)
    end

    -- Settings changed. Off steps this source aside, after it hides its own
    -- blocks, so the next source draws.
    function predict:Refresh()
        local on = store.enabled == true
        if on then
            api.SetSourceEnabled(spec.addon, true)
        end
        DrawAll()
        if not on then
            api.SetSourceEnabled(spec.addon, false)
            api.Refresh(nil)
        end
    end

    -- The DoT tracker whose rows show this damage (DotTracker calls this).
    function predict:SetTracker(tracker)
        self.tracker = tracker
    end

    -- The combat log ---------------------------------------------------------------

    local function Family(spellID, spellName)
        local rank = type(spellID) == "number" and RANKS[spellID]
        if rank then
            return rank[1], spellID
        end
        local family = predict.byName[spellName]
        if family then
            return family, predict.lastCast[family]
        end
    end

    local function Forget(guid, family)
        local mob = predict.mobs[guid]
        if not mob then
            return
        end
        if family then
            mob.dots[family] = nil
            if next(mob.dots) then
                return
            end
        end
        predict.mobs[guid] = nil
    end

    -- The DoT ends at its duration from `applied` (which the hidden path moves
    -- to its first tick), else it is checked again then.
    local function Expire(guid, family, dot)
        local wait = dot.applied + dot.duration + EXPIRY_GRACE - GetTime()
        C_Timer.After(math.max(0, wait), function()
            local current = predict.mobs[guid]
            if not current or current.dots[family] ~= dot then
                return
            end
            if GetTime() < dot.applied + dot.duration + EXPIRY_GRACE - 0.01 then
                Expire(guid, family, dot)
                return
            end
            Forget(guid, family)
            DrawGUID(guid)
        end)
    end

    local function Apply(guid, name, family, rankID)
        local rank = rankID and RankOf(rankID)
        if not rank then
            return
        end
        local finisher = FAMILIES[family].finisher
        local points = finisher and SentPoints(family) or nil
        local duration = Duration(family, rank, points)
        local interval = FAMILIES[family].interval
        if type(duration) ~= "number" or duration < interval then
            return
        end
        predict.points[family] = nil
        local mob = predict.mobs[guid] or {dots = {}}
        mob.name = name or mob.name
        predict.mobs[guid] = mob
        local ticks = math.floor(duration / interval + 0.5)
        local old = mob.dots[family]
        local power = SpellPower(family)
        local hasBase = type(rank[2]) == "number"
        local dot = {family = family, rank = rankID, applied = GetTime(), interval = interval, ticks = ticks,
            seen = 0, duration = duration, base = hasBase and rank[2] / ticks or 0, power = power, sum = 0, count = 0,
            points = points, late = FAMILIES[family].late}
        local saved = SavedTick(rankID, family, points)
        -- The same rank on the same mob ticks the same: keep what was learned
        -- (a finisher only at the same points).
        if old and old.rank == rankID and old.source == "learned" and old.points == points then
            dot.average, dot.source = old.average, "learned"
        elseif saved then
            -- With no base, the part spell power adds is not known: the tick as saved.
            dot.average, dot.source = hasBase and Rescale(saved, dot.base, power) or saved.tick, "saved"
        else
            local total = GuessTotal(rank, duration, power)
            dot.average, dot.source = total and total / ticks, total and "guessed" or "waiting"
        end
        mob.dots[family] = dot
        Expire(guid, family, dot)
        return dot, old
    end

    -- A tick seen, and with an amount, learned: the average of this cast's
    -- ticks, saved for the rank with the spell power it was cast at.
    local function Tick(guid, family, amount)
        local mob = predict.mobs[guid]
        local dot = mob and mob.dots[family]
        if not dot then
            return
        end
        local due = math.floor((GetTime() - dot.applied) / dot.interval + 0.5)
        local tick = math.min(dot.ticks, math.max(dot.seen + 1, due))
        dot.seen = tick
        if DyresToolkit.IsSecret(amount) or type(amount) ~= "number" then
            return
        end
        dot.sum, dot.count = dot.sum + AverageFrom(dot, tick, amount), dot.count + 1
        dot.average, dot.source = dot.sum / dot.count, "learned"
        SaveTick(dot, nil)
    end

    local function OnCombatLog()
        -- The 15th field is a tick's amount, or an aura event's type.
        local _, subevent, _, sourceGUID, _, _, _, destGUID, destName, _, _, spellID, spellName, _, amount =
            predict.read()
        if DEATHS[subevent] then
            if predict.mobs[destGUID] then
                Forget(destGUID)
                DrawGUID(destGUID)
            end
            return
        end
        if sourceGUID ~= predict.player then
            return
        end
        local family, rankID = Family(spellID, spellName)
        if not family then
            return
        end
        if APPLIED[subevent] then
            if amount ~= DEBUFF then
                return
            end
            Apply(destGUID, destName, family, rankID)
        elseif TICKS[subevent] then
            Tick(destGUID, family, amount)
        elseif subevent == MISSED then
            Tick(destGUID, family, nil)
        elseif subevent == "SPELL_AURA_REMOVED" then
            if amount ~= DEBUFF then
                return
            end
            Forget(destGUID, family)
        else
            return
        end
        DrawGUID(destGUID)
    end

    -- Hidden ticks (Forever) ------------------------------------------------------

    -- The school as UNIT_COMBAT gives it: a mask, 2 ^ (school - 1).
    local function Mask(family)
        return FAMILIES[family].mask or 2 ^ (FAMILIES[family].school - 1)
    end

    -- How much later than its slot a late DoT's tick may come: its flight,
    -- until its landing or a first tick fixes the rhythm.
    local function Extra(dot)
        return (dot.late and not dot.anchored and not dot.landed) and PROJECTILE_TRAVEL or 0
    end

    -- A cast's outcome comes when it lands: later for a projectile.
    local function OutcomeWindow(dot)
        return OUTCOME_WINDOW + (dot.late and PROJECTILE_TRAVEL or 0)
    end

    -- "... 10 Shadow damage over 15 sec." (the last such clause: Immolate's
    -- periodic part), or Siphon Life's "... 15 health ... every 3 sec. Lasts
    -- 30 sec.": the base damage and duration, without spell power. English
    -- tooltips only; else nil (ClassData's rank then).
    -- A finisher's "1 point: 40 damage over 8 secs ... 5 points: ..." (Does
    -- It Die's parseFinisher pattern: any words, or none, before "over"):
    -- the line for these points, else the lowest (errs low).
    local function ReadFinisher(text, points)
        local byPoints, lowest = {}, nil
        for count, amount, seconds in text:gmatch("(%d+) points?%s*:%s*(%d+)%s*[%a ]-over (%d+) sec") do
            count = tonumber(count)
            byPoints[count] = {tonumber(amount), tonumber(seconds)}
            lowest = math.min(lowest or count, count)
        end
        if not lowest then
            return nil
        end
        local entry = points and byPoints[points] or byPoints[lowest]
        return entry[1], entry[2]
    end

    local function ReadTooltip(spellID, family, points)
        local read = type(C_Spell) == "table" and C_Spell.GetSpellDescription or rawget(_G, "GetSpellDescription")
        if type(read) ~= "function" then
            return nil
        end
        local text = read(spellID)
        if DyresToolkit.IsSecret(text) or type(text) ~= "string" or text == "" then
            return nil
        end
        text = text:gsub("(%d),(%d)", "%1%2")
        local total, duration
        if FAMILIES[family].finisher then
            total, duration = ReadFinisher(text, points)
            -- A finisher's duration comes from its points when the family says how.
            if total and FAMILIES[family].pointDuration then
                duration = FAMILIES[family].pointDuration[1] + FAMILIES[family].pointDuration[2] * (points or 1)
            end
        else
            -- A school word, or none ("bleed for 15 damage over 9 sec").
            for amount, seconds in text:gmatch("(%d+)%s*[%a ]-%s*damage over (%d+) sec") do
                total, duration = tonumber(amount), tonumber(seconds)
            end
        end
        if not total then
            local each, every = text:match("(%d+) health.- every (%d+) sec")
            local lasts = text:match("[Ll]asts (%d+) sec")
            each, every, lasts = tonumber(each), tonumber(every), tonumber(lasts)
            if each and every and lasts and every > 0 then
                total, duration = each * math.floor(lasts / every + 0.5), lasts
            end
        end
        -- Under one tick is not a DoT's duration (a misread): ClassData then.
        if total and duration and total > 0 and duration >= FAMILIES[family].interval then
            return {family, total, duration, LOW_LEVEL}
        end
    end

    -- A cast's family and rank key: a ClassData rank, else a spell of a
    -- family's name (the client's own ID). Its tooltip, when it reads, gives
    -- the rank's numbers.
    local function Resolve(spellID)
        if DyresToolkit.IsSecret(spellID) or type(spellID) ~= "number" then
            return nil
        end
        local rank = RANKS[spellID]
        local family = FamilyOfSpell(spellID)
        -- A trap has no mob at the cast: the hidden path never starts one.
        if not family or FAMILIES[family].ground then
            return nil
        end
        local read = ReadTooltip(spellID, family, SentPoints(family))
        if read then
            -- A ClassData rank keeps its level (the low-level penalty).
            read[4] = rank and rank[4] or read[4]
            predict.spells[spellID] = read
        elseif not rank then
            -- No tooltip and no ClassData rank: the family's highest rank
            -- for your level (a nil level counts as 0).
            local level, best = UnitLevel("player"), nil
            for id, entry in pairs(RANKS) do
                local need = entry[4] or 0
                if entry[1] == family and (DyresToolkit.IsSecret(level) or need <= level)
                        and (not best or need > (RANKS[best][4] or 0)) then
                    best = id
                end
            end
            if not best then
                return nil
            end
            predict.spells[spellID] = RANKS[best]
        end
        return family, spellID
    end

    -- Whether a unit shows the mob now (UNIT_COMBAT reports only units).
    local function Observable(key)
        for _, unit in ipairs({"target", "focus"}) do
            if UnitExists(unit) and Key(unit) == key then
                return true
            end
        end
        for index = 1, MAX_NAMEPLATE_UNITS do
            local unit = "nameplate" .. index
            if UnitExists(unit) and Key(unit) == key then
                return true
            end
        end
        return false
    end

    -- The fight's tally for the damage meter: per rank, the ticks seen and
    -- their weights; clean while every DoT of it was seen whole.
    local function Tally(dot)
        local entry = predict.tally[dot.rank]
        if not entry then
            entry = {family = dot.family, count = 0, weights = 0, base = dot.base, power = dot.power, clean = true,
                guess = dot.average or 0}
            predict.tally[dot.rank] = entry
        end
        return entry
    end

    local function Unclean(dot)
        if InCombatLockdown() then
            Tally(dot).clean = false
        end
    end

    -- When tick slot n is due: the first from the cast, later ones from the
    -- first tick seen.
    local function SlotTime(dot, n)
        return dot.applied + n * dot.interval
    end

    -- The slot timer: at the end of the next open slot's window, a missed
    -- tick counts (a unit shows the mob) or the DoT is marked unseen.
    local function WatchSlot(key, dot)
        local slot = dot.seen + 1
        if slot > dot.ticks then
            return
        end
        local window = dot.anchored and TICK_WINDOW_ANCHORED or TICK_WINDOW
        local wait = SlotTime(dot, slot) + window + Extra(dot) - GetTime()
        C_Timer.After(math.max(0, wait), function()
            local mob = predict.mobs[key]
            if not mob or mob.dots[dot.family] ~= dot or dot.seen >= slot then
                return
            end
            -- The rhythm moved later since (a projectile landed): wait again.
            local close = SlotTime(dot, slot) + (dot.anchored and TICK_WINDOW_ANCHORED or TICK_WINDOW) + Extra(dot)
            if GetTime() < close - 0.01 then
                WatchSlot(key, dot)
                return
            end
            if Observable(key) then
                dot.missed = dot.missed + 1
                if dot.missed >= MISSES_TO_DROP then
                    Unclean(dot)
                    Forget(key, dot.family)
                    DrawGUID(key)
                    return
                end
            else
                dot.unseen = true
                Unclean(dot)
            end
            -- The slot is gone either way: its tick happened or not.
            dot.seen = slot
            WatchSlot(key, dot)
        end)
    end

    local function Started(key, name, family, rankID)
        local dot, old = Apply(key, name, family, rankID)
        if not dot then
            return
        end
        dot.missed, dot.ticked = 0, 0
        dot.previous = old
        if InCombatLockdown() then
            local entry = Tally(dot)
            if key:find("-", 1, true) == nil then
                entry.clean = false
            end
        end
        predict.cast = {key = key, dot = dot, at = GetTime()}
        WatchSlot(key, dot)
        DrawGUID(key)
    end

    -- The mob a cast at targetName goes to, read as it starts (Does It Die
    -- v0.9.3's sentTargetKey, the method only). A cast with no mob of that
    -- name goes to the default: your target, else the soft enemy when the
    -- target is friendly or a corpse (action targeting: a corpse cannot be
    -- cast at). A named mob that has no key (a secret GUID and no plate) gives
    -- false: the cast is skipped, never put on your target.
    local SENT_UNITS = {"target", "focus", "softenemy", "mouseover"}

    local function DefaultKey()
        local canAttack = UnitCanAttack("player", "target")
        -- No target counts as "cannot attack", as in Does It Die.
        local cannot = not DyresToolkit.IsSecret(canAttack) and canAttack == false
        if cannot or DyresToolkit.IsDead("target") then
            return Key("softenemy")
        end
        return Key("target")
    end

    local function SentKey(targetName)
        if DyresToolkit.IsSecret(targetName) or type(targetName) ~= "string" or targetName == "" then
            return DefaultKey()
        end
        for _, unit in ipairs(SENT_UNITS) do
            if UnitExists(unit) and DyresToolkit.ReadName(unit) == targetName and not DyresToolkit.IsDead(unit) then
                local canAttack = UnitCanAttack("player", unit)
                if DyresToolkit.IsSecret(canAttack) or canAttack == true then
                    return Key(unit) or false
                end
            end
        end
        return DefaultKey()
    end

    local function OnSent(targetName, castGUID, spellID)
        -- A finisher's points first: by SUCCEEDED they are spent.
        NotePoints(spellID)
        if not hidden then
            return
        end
        if not Resolve(spellID) or DyresToolkit.IsSecret(castGUID) or type(castGUID) ~= "string" then
            return
        end
        local now = GetTime()
        for guid, entry in pairs(predict.sent) do
            if now - entry.at > SENT_EXPIRY then
                predict.sent[guid] = nil
            end
        end
        predict.sent[castGUID] = {key = SentKey(targetName), at = now}
    end

    local function OnSucceeded(castGUID, spellID)
        local family, rankID = Resolve(spellID)
        if not family then
            return
        end
        local sent = not DyresToolkit.IsSecret(castGUID) and predict.sent[castGUID]
        local key
        if sent then
            -- false: the cast went to a mob we cannot key; nil: no mob at all.
            key = sent.key
            predict.sent[castGUID] = nil
        else
            key = Key("target")
        end
        if key then
            Started(key, nil, family, rankID)
        end
    end

    -- An avoid right after your cast, in its school: it did not land.
    local SPELL_AVOIDS = {MISS = true, RESIST = true, IMMUNE = true, EVADE = true, REFLECT = true}
    local MELEE_AVOIDS = {DODGE = true, PARRY = true, BLOCK = true, DEFLECT = true}

    local function OnAvoid(key, school, now)
        local cast = predict.cast
        if not cast or cast.key ~= key or cast.landed then
            return
        end
        local dot = cast.dot
        local mob = predict.mobs[key]
        if not mob or mob.dots[dot.family] ~= dot then
            return
        end
        if now - cast.at > OutcomeWindow(dot) then
            return
        end
        if DyresToolkit.IsSecret(school) or type(school) ~= "number" then
            -- Maybe someone else's: show it once it ticks.
            dot.doubtful = true
        elseif school == Mask(dot.family) then
            predict.cast = nil
            mob.dots[dot.family] = dot.previous
            if not dot.previous then
                Forget(key, dot.family)
            end
            DrawGUID(key)
            return
        end
        -- Another school: not ours.
    end

    -- A hit in a DoT's school, at an open tick slot: a tick.
    local function OnHit(key, school, amount, now)
        local cast = predict.cast
        local mob = predict.mobs[key]
        if cast and cast.key == key and now - cast.at <= OutcomeWindow(cast.dot) and school == Mask(cast.dot.family)
                and not cast.landed then
            cast.landed = true
            local dot = cast.dot
            -- A projectile with a direct part: its hit is the landing, and the
            -- DoT's rhythm starts there. Not a tick.
            if dot.late and FAMILIES[dot.family].direct and not dot.landed and mob and mob.dots[dot.family] == dot then
                dot.landed, dot.applied = true, now
                DrawGUID(key)
                return
            end
        end
        if not mob then
            return
        end
        if predict.frameAt ~= now then
            predict.frameAt, predict.fed = now, {}
        end
        local best, bestSlot, bestDistance
        for family, dot in pairs(mob.dots) do
            if Mask(family) == school and not predict.fed[dot] then
                local window = dot.anchored and TICK_WINDOW_ANCHORED or TICK_WINDOW
                local extra = Extra(dot)
                for slot = dot.seen + 1, math.min(dot.ticks, dot.seen + 2) do
                    -- Early by the window, late by the window plus a flight.
                    local due = SlotTime(dot, slot)
                    local distance = now < due and due - now or math.max(0, now - due - extra)
                    if distance <= window and (not bestDistance or distance < bestDistance) then
                        best, bestSlot, bestDistance = dot, slot, distance
                    end
                end
            end
        end
        if not best then
            return
        end
        predict.fed[best] = true
        if not best.anchored then
            -- The rhythm from the first tick seen (a slot's real time).
            best.applied = now - bestSlot * best.interval
            best.anchored = true
        end
        best.seen, best.missed, best.doubtful = bestSlot, 0, nil
        best.ticked = best.ticked + 1
        if InCombatLockdown() then
            local entry = Tally(best)
            entry.count = entry.count + 1
            entry.weights = entry.weights + Weight(best.family, bestSlot)
        end
        if not DyresToolkit.IsSecret(amount) and type(amount) == "number" and amount > 0 then
            best.sum, best.count = best.sum + AverageFrom(best, bestSlot, amount), best.count + 1
            best.average, best.source = best.sum / best.count, "learned"
            SaveTick(best, best.family)
        end
        WatchSlot(key, best)
        DrawGUID(key)
    end

    local function OnUnitCombat(unit, action, amount, school)
        if DyresToolkit.IsSecret(action) or type(action) ~= "string" then
            return
        end
        local avoid = SPELL_AVOIDS[action]
        if not avoid and action ~= "WOUND" and action ~= "ABSORB" then
            return
        end
        if MELEE_AVOIDS[action] then
            return
        end
        local key = Key(unit)
        if not key then
            return
        end
        local now = GetTime()
        if avoid then
            OnAvoid(key, school, now)
            return
        end
        if DyresToolkit.IsSecret(school) or type(school) ~= "number" then
            return
        end
        OnHit(key, school, amount, now)
    end

    -- The damage meter, after combat: each clean rank's tick from its
    -- spell's total. Every table is checked; the totals turn readable a few
    -- seconds after combat, so it waits for them.
    local function Readable(value)
        if DyresToolkit.IsSecret(value) or type(value) ~= "table" then
            return false
        end
        local check = rawget(_G, "canaccesstable")
        return type(check) ~= "function" or check(value) == true
    end

    local function MeterTotals()
        local meter = rawget(_G, "C_DamageMeter")
        if type(meter) ~= "table" or type(meter.GetCombatSessionSourceFromType) ~= "function" then
            return nil, "none"
        end
        if type(meter.IsDamageMeterAvailable) == "function" and meter.IsDamageMeterAvailable() == false then
            return nil, "none"
        end
        local kind = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
        local session = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
        local source = meter.GetCombatSessionSourceFromType(session, kind, predict.player)
        if not Readable(source) or not Readable(source.combatSpells) then
            return nil, "wait"
        end
        local totals = {}
        for _, spell in ipairs(source.combatSpells) do
            if Readable(spell) then
                if DyresToolkit.IsSecret(spell.spellID) or DyresToolkit.IsSecret(spell.totalAmount) then
                    return nil, "wait"
                end
                if type(spell.spellID) == "number" and type(spell.totalAmount) == "number" then
                    totals[spell.spellID] = (totals[spell.spellID] or 0) + spell.totalAmount
                end
            end
        end
        return totals
    end

    local function Learn(tally, totals)
        local ranksOf = {}
        for rankID, entry in pairs(tally) do
            ranksOf[entry.family] = (ranksOf[entry.family] or 0) + 1
        end
        for rankID, entry in pairs(tally) do
            local total = totals[rankID]
            -- One rank of the family this fight, every DoT seen whole, 2 ticks
            -- or more, and no direct hit in the total.
            -- Not a finisher: its casts this fight may differ by points.
            if total and entry.clean and ranksOf[entry.family] == 1 and entry.count >= MIN_METER_TICKS
                    and not FAMILIES[entry.family].direct and not FAMILIES[entry.family].finisher then
                -- sum of ticks = base * sum of weights + count * (average - base)
                local average = (total - entry.base * entry.weights) / entry.count + entry.base
                -- With no guess (no base damage), any tick above 0 is the first word.
                local share = entry.guess > 0 and average / entry.guess or (average > 0 and 1 or 0)
                if share >= METER_SHARE_MIN and share <= METER_SHARE_MAX then
                    DyresToolkit.LearnedTicks()[rankID] = {tick = math.floor(average * 10 + 0.5) / 10,
                        power = entry.power, family = entry.family}
                end
            end
        end
    end

    local function ReadMeter(tally, tries)
        if InCombatLockdown() then
            return
        end
        local totals, why = MeterTotals()
        if not totals then
            if why == "wait" and tries > 0 then
                C_Timer.After(METER_RETRY, function() ReadMeter(tally, tries - 1) end)
            end
            return
        end
        Learn(tally, totals)
    end

    local function CombatEnded()
        for family in pairs(FAMILIES) do
            SpellPower(family)
        end
        local tally = predict.tally
        predict.tally = {}
        if next(tally) then
            C_Timer.After(METER_RETRY, function() ReadMeter(tally, METER_TRIES) end)
        end
    end

    local function IsShownUnit(unit)
        return unit == "target" or unit == "focus" or (type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil)
    end

    events:SetScript("OnEvent", function(_, event, unit, second, third, fourth, fifth)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            OnCombatLog()
        elseif event == "UNIT_COMBAT" then
            OnUnitCombat(unit, second, fourth, fifth)
        elseif event == "UNIT_SPELLCAST_SENT" then
            OnSent(second, third, fourth)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" and hidden then
            OnSucceeded(second, third)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- Which rank you cast, for a combat log that names the spell only.
            local spellID = third
            local rank = not DyresToolkit.IsSecret(spellID) and RANKS[spellID]
            if rank then
                predict.lastCast[rank[1]] = spellID
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            CombatEnded()
        elseif event == "PLAYER_TARGET_CHANGED" then
            -- "target" as a key is the mob the target showed until now.
            predict.mobs.target = nil
            DrawUnitFrame("target")
        elseif event == "PLAYER_FOCUS_CHANGED" then
            DrawUnitFrame("focus")
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            if not DyresToolkit.IsSecret(unit) then
                DrawPlate(unit)
                -- Again once every AddOn's handler for this event has run: a
                -- nameplate AddOn may only now take the plate over.
                C_Timer.After(0, function()
                    if UnitExists(unit) then
                        DrawPlate(unit)
                    end
                end)
            end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            if not DyresToolkit.IsSecret(unit) then
                DyresToolkit.UseBar(predict.plates, unit, nil)
                -- A token key belongs to that plate only.
                if hidden and type(unit) == "string" then
                    predict.mobs["plate:" .. unit] = nil
                end
            end
        elseif not DyresToolkit.IsSecret(unit) and IsShownUnit(unit) then
            if unit == "target" or unit == "focus" then
                DrawUnitFrame(unit)
            else
                DrawPlate(unit)
            end
        end
    end)

    -- The HealthBars source ------------------------------------------------------

    local function SourceDamage(unitOrGUID)
        if DyresToolkit.IsSecret(unitOrGUID) or type(unitOrGUID) ~= "string" then
            return nil
        end
        local guid = unitOrGUID
        if not guid:find("-", 1, true) then
            guid = Key(unitOrGUID)
        end
        if not guid or not predict.mobs[guid] then
            return nil
        end
        return predict:PredictedDamage(guid)
    end

    local function SourceRefresh(unit)
        if unit == nil then
            DrawAll()
            return
        end
        if DyresToolkit.IsSecret(unit) or not IsShownUnit(unit) then
            return
        end
        if unit == "target" or unit == "focus" then
            DrawUnitFrame(unit)
        elseif UnitExists(unit) then
            DrawPlate(unit)
        end
        local guid = DyresToolkit.ReadGUID(unit)
        if guid then
            RefreshRows(guid)
        end
    end

    -- Another source's change, for the tracker rows only.
    local function OnPredictionChanged(_, unit, guid)
        if Mine() then
            return
        end
        if DyresToolkit.IsSecret(guid) or type(guid) ~= "string" then
            guid = nil
            if not DyresToolkit.IsSecret(unit) and type(unit) == "string" then
                guid = DyresToolkit.ReadGUID(unit)
            end
            if unit ~= nil and not guid then
                return
            end
        end
        RefreshRows(guid)
    end

    -- /debug lines: each mob's DoTs, the tick, where the average came from,
    -- and the damage to come (the owner adds its prefix).
    function predict:DebugLines()
        local lines = {string.format("enabled=%s plates=%s dies=%s active=%s input=%s", tostring(store.enabled),
            tostring(store.plates), tostring(store.dies), tostring(Mine()),
            hidden and "hidden ticks (no combat log)" or "combat log")}
        local frames = {}
        for _, unit in ipairs({"target", "focus"}) do
            local _, info = DyresToolkit.FindUnitBar(unit)
            frames[#frames + 1] = unit .. "=" .. tostring(info and info.name or "none")
        end
        for index = 1, MAX_NAMEPLATE_UNITS do
            local shown = self.plates["nameplate" .. index]
            if shown then
                frames[#frames + 1] = "nameplate" .. index .. "=" .. tostring(shown.name)
            end
        end
        lines[#lines + 1] = "Frames: " .. table.concat(frames, ", ")
        local now, any = GetTime(), false
        for guid, mob in pairs(self.mobs) do
            any = true
            lines[#lines + 1] = string.format("%s: %d to come", tostring(mob.name), self:PredictedDamage(guid))
            for _, family in ipairs(FAMILY_ORDER) do
                local dot = mob.dots[family]
                if dot then
                    lines[#lines + 1] = string.format("  %s (spell %d): tick %d of %d, %s %s, %d to come%s", family,
                        dot.rank, TicksDone(dot, now), dot.ticks, dot.source,
                        dot.average and string.format("%.1f", dot.average) or "-",
                        math.floor(DotRemaining(dot, now) + 0.5),
                        FAMILIES[family].finisher and (", points " .. tostring(dot.points or "unknown")) or "")
                end
            end
        end
        if not any then
            lines[#lines + 1] = "No DoTs of yours on any mob."
        end
        return lines
    end

    -- Build --------------------------------------------------------------------

    for id, rank in pairs(RANKS) do
        local name = DyresToolkit.SpellName(id)
        if name then
            predict.byName[name] = rank[1]
        end
    end
    -- Never the combat log where it is restricted: registering it there
    -- shows the client's "blocked" popup.
    local list = {"PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
        "UNIT_HEALTH", "UNIT_MAXHEALTH"}
    if hidden then
        list[#list + 1] = "UNIT_COMBAT"
        list[#list + 1] = "PLAYER_REGEN_ENABLED"
    else
        list[#list + 1] = "COMBAT_LOG_EVENT_UNFILTERED"
    end
    for _, event in ipairs(list) do
        events:RegisterEvent(event)
    end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    local finishers = false
    for _, family in pairs(FAMILIES) do
        finishers = finishers or family.finisher == true
    end
    -- The send: the mob (hidden path) and a finisher's points (both).
    if hidden or finishers then
        events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    end
    if hidden then
        for family in pairs(FAMILIES) do
            SpellPower(family)
        end
    end
    local registered, why = api.RegisterSource({addon = spec.addon, priority = spec.priority or 0,
        damage = SourceDamage, refresh = SourceRefresh})
    if not registered then
        events:UnregisterAllEvents()
        return nil, why
    end
    api.SetSourceEnabled(spec.addon, store.enabled == true)
    api.RegisterCallback("PREDICTION_CHANGED", OnPredictionChanged)
    -- The target frame's block is made now, out of combat.
    local bar = DyresToolkit.FindUnitBar("target")
    if bar then
        DyresToolkit.PrepareBar(bar, "target")
    end
    DrawAll()
    return predict
end
