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
-- rank's base damage plus spell power. Where the combat log is restricted
-- (Forever), a predictor is not made at all and registers nothing.
--
-- The learned ticks are the one store an engine keeps (lead decision 1):
-- DyresToolkitDB.ticks[rank spell ID] = {tick, power}, shared by every
-- Dyre's AddOn, with a one-time copy of an owner's older table
-- (spec.legacyTicks: WTF's WarlockToolsForeverAccountDB.ticks).

local LOW_LEVEL = 20
local LOW_LEVEL_PENALTY = 0.0375
local MAX_NAMEPLATE_UNITS = 40
local TICKS = {SPELL_PERIODIC_DAMAGE = true, SPELL_PERIODIC_LEECH = true}
local MISSED = "SPELL_PERIODIC_MISSED"
local DEBUFF = "DEBUFF"
local APPLIED = {SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true}
local DEATHS = {UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true}
local EXPIRY_GRACE = 0.5

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

-- Every rank any class table knows, so a saved tick of a rank no table
-- lists any more is dropped.
local function AllRanks()
    local all = {}
    for _, data in pairs(DyresToolkit.ClassData) do
        for id in pairs(data.ranks or {}) do
            all[id] = true
        end
    end
    return all
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
        local ranks = AllRanks()
        for id, entry in pairs(saved) do
            if type(id) ~= "number" or not ranks[id] or type(entry) ~= "table" or type(entry.tick) ~= "number"
                    or entry.tick <= 0 or type(entry.power) ~= "number" or entry.power < 0 then
                saved[id] = nil
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
        if ticks[id] == nil and ranks[id] and type(entry) == "table" and type(entry.tick) == "number"
                and entry.tick > 0 and type(entry.power) == "number" and entry.power >= 0 then
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
-- Returns the predictor, else nil and why (no combat log, as on Forever).
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
    if not DyresToolkit.CombatLogUsable() then
        return nil, "the combat log"
    end
    if type(C_NamePlate) ~= "table" or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then
        return nil, "C_NamePlate.GetNamePlateForUnit"
    end
    local store = spec.store
    local api = DyresToolkit.HealthBars
    local predict = {mobs = {}, byName = {}, lastCast = {}, plates = {}, units = {}, read = EventInfoReader(),
        player = UnitGUID("player")}
    local events = CreateFrame("Frame")
    ImportTicks(spec.addon, spec.legacyTicks)

    local function Weight(family, tick)
        return DyresToolkit.TickWeight(FAMILIES[family], tick)
    end

    local function SpellPower(family)
        local power = type(GetSpellBonusDamage) == "function" and GetSpellBonusDamage(FAMILIES[family].school) or 0
        if DyresToolkit.IsSecret(power) or type(power) ~= "number" or power < 0 then
            return 0
        end
        return power
    end

    -- The first guess for the whole DoT: base damage plus spell power, a
    -- share of it by duration / 15 (at most 1) or the family's coefficient,
    -- less 3.75% per level for ranks learned below 20.
    local function GuessTotal(rankID, power)
        local rank = RANKS[rankID]
        local share = FAMILIES[rank[1]].coefficient or math.min(1, rank[3] / 15)
        if rank[4] < LOW_LEVEL then
            share = share * (1 - (LOW_LEVEL - rank[4]) * LOW_LEVEL_PENALTY)
        end
        return rank[2] + power * share
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
            total = total + DotRemaining(dot, now)
        end
        return math.floor(total + 0.5)
    end

    -- Drawing ------------------------------------------------------------------

    local function Look()
        local color = spec.color and spec.color() or {0.6, 0.2, 0.9}
        return {fill = store.fill, color = color, opacity = store.opacity, outline = store.outline, dies = store.dies}
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

    local function Draw(unit, bar, kind, info)
        if not bar then
            return
        end
        local guid = UnitGUID(unit)
        local canAttack = UnitCanAttack("player", unit)
        if not store.enabled or DyresToolkit.IsSecret(guid) or type(guid) ~= "string"
                or DyresToolkit.IsSecret(canAttack) or canAttack ~= true then
            HideOverlay(bar)
            return
        end
        DyresToolkit.DrawPrediction(bar, kind, predict:PredictedDamage(guid), UnitHealth(unit), Look(), info)
    end

    -- A DoT tracker row's health bar: the row's mob and the health the bar
    -- shows. Returns whether DIES shows, so the row can make room.
    function predict:DrawRow(bar, guid, health, place)
        if not bar then
            return false
        end
        if not store.enabled or type(guid) ~= "string" then
            HideOverlay(bar)
            return false
        end
        local dies = DyresToolkit.DrawPrediction(bar, "row", RowDamage(guid), health, Look())
        DyresToolkit.MoveDies(bar, place)
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
        local shown = UnitGUID(unit)
        return not DyresToolkit.IsSecret(shown) and shown == guid
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
        RefreshRows(guid)
        api.NotifyChanged(spec.addon, nil, guid)
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

    local function Apply(guid, name, family, rankID)
        local rank = rankID and RANKS[rankID]
        if not rank then
            return
        end
        local mob = predict.mobs[guid] or {dots = {}}
        mob.name = name or mob.name
        predict.mobs[guid] = mob
        local interval = FAMILIES[family].interval
        local ticks = math.floor(rank[3] / interval + 0.5)
        local old = mob.dots[family]
        local power = SpellPower(family)
        local dot = {family = family, rank = rankID, applied = GetTime(), interval = interval, ticks = ticks,
            seen = 0, duration = rank[3], base = rank[2] / ticks, power = power, sum = 0, count = 0}
        local saved = DyresToolkit.LearnedTicks()[rankID]
        -- The same rank on the same mob ticks the same: keep what was learned.
        if old and old.rank == rankID and old.source == "learned" then
            dot.average, dot.source = old.average, "learned"
        elseif saved then
            dot.average, dot.source = Rescale(saved, dot.base, power), "saved"
        else
            dot.average, dot.source = GuessTotal(rankID, power) / ticks, "guessed"
        end
        mob.dots[family] = dot
        C_Timer.After(dot.duration + EXPIRY_GRACE, function()
            local current = predict.mobs[guid]
            if current and current.dots[family] == dot then
                Forget(guid, family)
                DrawGUID(guid)
            end
        end)
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
        DyresToolkit.LearnedTicks()[dot.rank] = {tick = math.floor(dot.average * 10 + 0.5) / 10, power = dot.power}
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

    local function IsShownUnit(unit)
        return unit == "target" or unit == "focus" or (type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil)
    end

    events:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            OnCombatLog()
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- Which rank you cast, for a combat log that names the spell only.
            local rank = not DyresToolkit.IsSecret(spellID) and RANKS[spellID]
            if rank then
                predict.lastCast[rank[1]] = spellID
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
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
            guid = DyresToolkit.ReadGUID(unitOrGUID)
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
        local lines = {string.format("enabled=%s plates=%s dies=%s active=%s", tostring(store.enabled),
            tostring(store.plates), tostring(store.dies), tostring(Mine()))}
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
                    lines[#lines + 1] = string.format("  %s (spell %d): tick %d of %d, %s %.1f, %d to come", family,
                        dot.rank, TicksDone(dot, now), dot.ticks, dot.source, dot.average,
                        math.floor(DotRemaining(dot, now) + 0.5))
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
    for _, event in ipairs({"COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH", "UNIT_MAXHEALTH"}) do
        events:RegisterEvent(event)
    end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
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
