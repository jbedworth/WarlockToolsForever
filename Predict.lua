local _, WTF = ...

-- DoT damage prediction (John, 1.4.0: phase 1, Classic Era only): a purple
-- block on the health bar of your target (Blizzard's target frame), of each
-- hostile Blizzard nameplate, and of each DoT tracker row with mob health on,
-- the size of the damage your Corruption,
-- Curse of Agony, Immolate (its over-time part), and Siphon Life still have
-- to deal, ending at the health bar's fill; and "DIES" when that damage is at
-- least the mob's health.
--
-- It needs the combat log: COMBAT_LOG_EVENT_UNFILTERED by mob GUID, also for
-- mobs no unit shows. Each DoT's tick is learned from its ticks (exact:
-- talents, spell power, and resists included) and saved account-wide per rank
-- with the spell power it was learned at; the next cast of that rank starts
-- from it, rescaled to your spell power then. With nothing saved, the rank's
-- base damage plus spell power. On Forever the combat log is restricted (found in
-- client), so this file registers nothing there (phase 2, an estimate, comes
-- later). Health is readable on Era (found in client: 328, 328); a secret
-- health draws nothing.

-- Classic ranks (Era tooltips; base damage without spell power): the family,
-- the over-time damage, its duration, and the level the rank is learned at.
local RANKS = {
    [172] = {"corruption", 40, 12, 4}, [6222] = {"corruption", 90, 15, 14}, [6223] = {"corruption", 222, 18, 24},
    [7648] = {"corruption", 324, 18, 34}, [11671] = {"corruption", 486, 18, 44},
    [11672] = {"corruption", 666, 18, 54}, [25311] = {"corruption", 822, 18, 60},
    [980] = {"agony", 84, 24, 8}, [1014] = {"agony", 180, 24, 18}, [6217] = {"agony", 324, 24, 28},
    [11711] = {"agony", 504, 24, 38}, [11712] = {"agony", 780, 24, 48}, [11713] = {"agony", 1044, 24, 58},
    [348] = {"immolate", 20, 15, 1}, [707] = {"immolate", 40, 15, 10}, [1094] = {"immolate", 90, 15, 20},
    [2941] = {"immolate", 165, 15, 30}, [11665] = {"immolate", 255, 15, 40}, [11667] = {"immolate", 365, 15, 50},
    [11668] = {"immolate", 485, 15, 60}, [25309] = {"immolate", 510, 15, 60},
    [18265] = {"siphon", 150, 30, 30}, [18879] = {"siphon", 220, 30, 38}, [18880] = {"siphon", 330, 30, 48},
    [18881] = {"siphon", 450, 30, 58},
}
-- Seconds between ticks, the spell school for GetSpellBonusDamage (3 fire,
-- 6 shadow), and the share of spell power over the whole DoT: Classic's
-- duration / 15, at most 1; Immolate's over-time part 0.65 (it also hits),
-- Siphon Life half (it heals). Only the first guess uses these.
local FAMILIES = {
    corruption = {interval = 3, school = 6},
    agony = {interval = 2, school = 6, ramp = true},
    immolate = {interval = 3, school = 3, coefficient = 0.65},
    siphon = {interval = 3, school = 6, coefficient = 0.5},
}
local FAMILY_ORDER = {"corruption", "agony", "immolate", "siphon"}
-- Spells learned below level 20 get less spell power: 3.75% per level below.
local LOW_LEVEL = 20
local LOW_LEVEL_PENALTY = 0.0375
local MAX_NAMEPLATE_UNITS = 40
-- The tick events (Siphon Life's is a leech) and the end events.
local TICKS = {SPELL_PERIODIC_DAMAGE = true, SPELL_PERIODIC_LEECH = true}
-- A resisted, absorbed, or immune tick: it happened, with no amount to learn.
local MISSED = "SPELL_PERIODIC_MISSED"
local DEBUFF = "DEBUFF"
local APPLIED = {SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true}
local DEATHS = {UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true}
-- A timer per DoT drops it just after its last tick, should the end event
-- be out of combat log range.
local EXPIRY_GRACE = 0.5
local predict = {available = false, mobs = {}, byName = {}, lastCast = {}, overlays = {}, plates = {}, units = {}}

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

local function CombatLogUsable()
    if type(C_CombatLog) == "table" and type(C_CombatLog.IsCombatLogRestricted) == "function" then
        local restricted = C_CombatLog.IsCombatLogRestricted()
        if WTF.IsSecret(restricted) or restricted then
            return false
        end
    end
    return EventInfoReader() ~= nil
end

function WTF.PredictAvailable()
    return predict.available
end

local function Weight(family, tick)
    if not FAMILIES[family].ramp then
        return 1
    end
    -- Curse of Agony: the first four ticks half the average, the last four
    -- one and a half times it.
    if tick <= 4 then
        return 0.5
    elseif tick <= 8 then
        return 1
    end
    return 1.5
end

-- Your spell power for the family's school, else 0.
local function SpellPower(family)
    local power = type(GetSpellBonusDamage) == "function" and GetSpellBonusDamage(FAMILIES[family].school) or 0
    if WTF.IsSecret(power) or type(power) ~= "number" or power < 0 then
        return 0
    end
    return power
end

-- The first guess for the whole DoT: base damage plus spell power.
local function GuessTotal(rankID, power)
    local rank = RANKS[rankID]
    local share = FAMILIES[rank[1]].coefficient or math.min(1, rank[3] / 15)
    if rank[4] < LOW_LEVEL then
        share = share * (1 - (LOW_LEVEL - rank[4]) * LOW_LEVEL_PENALTY)
    end
    return rank[2] + power * share
end

-- A tick is the average tick, except Curse of Agony's: its ramp applies to
-- the rank's base damage only, and the rest (spell power) is spread evenly
-- over the ticks (Does It Die's TBC port, seen in game; to check on Era).
local function TickAmount(dot, tick)
    local weight = Weight(dot.family, tick)
    if weight == 1 then
        return dot.average
    end
    return math.max(0, dot.base * weight + dot.average - dot.base)
end

-- The average tick a tick of this amount stands for.
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

local function Now()
    return GetTime()
end

-- Ticks done: those seen, or those due by now when some were missed.
local function TicksDone(dot, now)
    local due = math.floor((now - dot.applied) / dot.interval)
    return math.min(dot.ticks, math.max(dot.seen, due))
end

-- One DoT's damage still to come.
local function DotRemaining(dot, now)
    local remaining = 0
    for tick = TicksDone(dot, now) + 1, dot.ticks do
        remaining = remaining + TickAmount(dot, tick)
    end
    return remaining
end

function WTF.PredictedDamage(guid)
    local mob = predict.mobs[guid]
    if not mob then
        return 0
    end
    local now, total = Now(), 0
    for _, dot in pairs(mob.dots) do
        total = total + DotRemaining(dot, now)
    end
    return math.floor(total + 0.5)
end

-- The health bars --------------------------------------------------------------

-- Since 1.4.1 the frame adapters (Threat Plates, Plater, EllesmereUI,
-- Platynator, Shadowed Unit Frames, BetterBlizzFrames, Blizzard), the block,
-- and the DIES badge are Dyre's Toolkit's (HealthBars.lua, 2.4.0, moved from
-- here with the same numbers; it also keeps DIES clear of Threat Plates'
-- target-of-target text, Plater's cast target and raid marker). WTF keeps
-- the combat log model, the ticks, the settings, and when to draw.

local function Readable(value)
    return not WTF.IsSecret(value) and type(value) == "number"
end

-- The block's look from the settings (Core's PREDICT_* choices).
local function Look()
    local settings = WTF.db.predict
    local color
    for _, preset in ipairs(WTF.PREDICT_COLORS) do
        if preset.key == settings.color then
            color = preset.color
        end
    end
    return {fill = settings.fill, color = color, opacity = settings.opacity, outline = settings.outline,
        dies = settings.dies}
end

local function HideOverlay(bar)
    if bar then
        WTF.shared.HidePrediction(bar)
    end
end

-- Dyre's Toolkit's damage sources (HealthBars, 2.4.0; John, 2026-10-31):
-- each Dyre's AddOn that predicts damage registers, and only the highest
-- priority draws on the health bars (Dyre's Debuff Tracker, 20, above WTF),
-- so a mob is never drawn twice. predict.sources is DyresToolkit.HealthBars
-- once WTF is registered; without it (an older Toolkit) WTF draws as before.
local SOURCE = "WarlockToolsForever"
local SOURCE_PRIORITY = 10
local SOURCE_FUNCTIONS = {"RegisterSource", "SetSourceEnabled", "IsActiveSource", "NotifyChanged",
    "GetPredictedDamage"}

-- Whether WTF draws on the target frame and the nameplates.
local function Mine()
    local api = predict.sources
    return not api or api.IsActiveSource(SOURCE) == true
end

-- A tracker row is WTF's own bar, so it always draws: WTF's damage, or the
-- active source's while another one is (the number its nameplate shows).
local function RowDamage(guid)
    if Mine() then
        return WTF.PredictedDamage(guid)
    end
    return predict.sources.GetPredictedDamage(guid) or 0
end

local function Draw(unit, bar, kind, info)
    if not bar then
        return
    end
    local settings = WTF.db.predict
    local guid = UnitGUID(unit)
    local canAttack = UnitCanAttack("player", unit)
    if not settings.enabled or WTF.IsSecret(guid) or type(guid) ~= "string"
            or WTF.IsSecret(canAttack) or canAttack ~= true then
        HideOverlay(bar)
        return
    end
    WTF.shared.DrawPrediction(bar, kind, WTF.PredictedDamage(guid), UnitHealth(unit), Look(), info)
end

-- A DoT tracker row's health bar (Tracker.lua's UpdateHealth): the row's mob
-- and the health the bar shows, which a row with no unit keeps from when it
-- had one. Rows have a health bar only with "Show mob health" on, so the
-- block shows there when both it and "Show Predictive DoT Damage" are on
-- (John, 1.4.0: no switch of its own). place: where the row wants DIES,
-- {point, region, relativePoint, x}, else the bar's right end. Returns
-- whether DIES shows, so the row can make room.
function WTF.DrawRowPrediction(bar, guid, health, place)
    if not predict.available or not bar then
        return false
    end
    if not WTF.db.predict.enabled or type(guid) ~= "string" then
        HideOverlay(bar)
        return false
    end
    local dies = WTF.shared.DrawPrediction(bar, "row", RowDamage(guid), health, Look())
    WTF.shared.MoveDies(bar, place)
    return dies == true
end

-- The target or focus frame.
local function DrawUnitFrame(unit)
    if not Mine() then
        return
    end
    local bar, info = WTF.shared.FindUnitBar(unit)
    WTF.shared.UseBar(predict.units, unit, bar, info)
    Draw(unit, bar, "target", info)
end

local function DrawPlate(unit)
    if not Mine() then
        return
    end
    local bar, info = WTF.shared.FindPlateBar(unit)
    WTF.shared.UseBar(predict.plates, unit, bar, info)
    if WTF.db.predict.plates then
        Draw(unit, bar, "plate", info)
    else
        HideOverlay(bar)
    end
end

local function IsGUID(unit, guid)
    local shown = UnitGUID(unit)
    return not WTF.IsSecret(shown) and shown == guid
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
    WTF.RefreshTrackerPrediction(guid)
    if predict.sources then
        predict.sources.NotifyChanged(SOURCE, nil, guid)
    end
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
    WTF.RefreshTrackerPrediction()
end

-- Settings changed. "Show Predictive DoT Damage" off steps WTF aside as a
-- source, after it hides its own blocks, so the next source draws.
function WTF.RefreshPredict()
    if not predict.available then
        return
    end
    local api = predict.sources
    local on = WTF.db.predict.enabled
    if api and on then
        api.SetSourceEnabled(SOURCE, true)
    end
    DrawAll()
    if api and not on then
        api.SetSourceEnabled(SOURCE, false)
        if type(api.Refresh) == "function" then
            api.Refresh(nil)
        end
    end
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
    local dot = {family = family, rank = rankID, applied = Now(), interval = interval, ticks = ticks,
        seen = 0, duration = rank[3], base = rank[2] / ticks, power = power, sum = 0, count = 0}
    local saved = WTF.accountDB.ticks[rankID]
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

-- A tick seen, and with an amount, learned: the average of this cast's ticks,
-- saved for the rank with the spell power it was cast at (one decimal).
local function Tick(guid, family, amount)
    local mob = predict.mobs[guid]
    local dot = mob and mob.dots[family]
    if not dot then
        return
    end
    local due = math.floor((Now() - dot.applied) / dot.interval + 0.5)
    local tick = math.min(dot.ticks, math.max(dot.seen + 1, due))
    dot.seen = tick
    if not Readable(amount) then
        return
    end
    dot.sum, dot.count = dot.sum + AverageFrom(dot, tick, amount), dot.count + 1
    dot.average, dot.source = dot.sum / dot.count, "learned"
    WTF.accountDB.ticks[dot.rank] = {tick = math.floor(dot.average * 10 + 0.5) / 10, power = dot.power}
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

local function OnEvent(_, event, unit, _, spellID)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Which rank you cast, for a combat log that names the spell only.
        local rank = not WTF.IsSecret(spellID) and RANKS[spellID]
        if rank then
            predict.lastCast[rank[1]] = spellID
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        DrawUnitFrame("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        DrawUnitFrame("focus")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if not WTF.IsSecret(unit) then
            DrawPlate(unit)
            -- Again once every AddOn's handler for this event has run: a
            -- nameplate AddOn may only now take the plate over (Threat
            -- Plates sets .Active in its own handler). One timer, no polling.
            C_Timer.After(0, function()
                if UnitExists(unit) then
                    DrawPlate(unit)
                end
            end)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if not WTF.IsSecret(unit) then
            WTF.shared.UseBar(predict.plates, unit, nil)
        end
    elseif not WTF.IsSecret(unit) and IsShownUnit(unit) then
        if unit == "target" or unit == "focus" then
            DrawUnitFrame(unit)
        else
            DrawPlate(unit)
        end
    end
end

-- The damage to come for a unit token or GUID, or nil for a mob WTF has no
-- DoT on.
local function SourceDamage(unitOrGUID)
    if WTF.IsSecret(unitOrGUID) or type(unitOrGUID) ~= "string" then
        return nil
    end
    local guid = unitOrGUID
    if not guid:find("-", 1, true) then
        guid = WTF.shared.ReadGUID(unitOrGUID)
    end
    if not guid or not predict.mobs[guid] then
        return nil
    end
    return WTF.PredictedDamage(guid)
end

-- The Toolkit asks WTF to draw again: one unit's frames and rows, or all.
local function SourceRefresh(unit)
    if unit == nil then
        DrawAll()
        return
    end
    if WTF.IsSecret(unit) or not IsShownUnit(unit) then
        return
    end
    if unit == "target" or unit == "focus" then
        DrawUnitFrame(unit)
    elseif UnitExists(unit) then
        DrawPlate(unit)
    end
    local guid = WTF.shared.ReadGUID(unit)
    if guid then
        WTF.RefreshTrackerPrediction(guid)
    end
end

-- Another source's change, for the tracker rows only (WTF's own changes
-- redraw them in DrawGUID).
local function OnPredictionChanged(_, unit, guid)
    if Mine() then
        return
    end
    if WTF.IsSecret(guid) or type(guid) ~= "string" then
        guid = nil
        if not WTF.IsSecret(unit) and type(unit) == "string" then
            guid = WTF.shared.ReadGUID(unit)
        end
        if unit ~= nil and not guid then
            return
        end
    end
    WTF.RefreshTrackerPrediction(guid)
end

local function RegisterSource()
    local api = WTF.shared.HealthBars
    if type(api) ~= "table" then
        return
    end
    for _, name in ipairs(SOURCE_FUNCTIONS) do
        if type(api[name]) ~= "function" then
            return
        end
    end
    if not api.RegisterSource({addon = SOURCE, priority = SOURCE_PRIORITY, damage = SourceDamage,
            refresh = SourceRefresh}) then
        return
    end
    api.SetSourceEnabled(SOURCE, WTF.db.predict.enabled)
    if type(api.RegisterCallback) == "function" then
        api.RegisterCallback("PREDICTION_CHANGED", OnPredictionChanged)
    end
    predict.sources = api
end

function WTF.InitializePredict()
    if not CombatLogUsable() or type(C_NamePlate) ~= "table"
            or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then
        return
    end
    predict.available = true
    predict.read = EventInfoReader()
    predict.player = UnitGUID("player")
    -- Saved ticks of ranks this file no longer knows are dropped.
    for id in pairs(WTF.accountDB.ticks) do
        if not RANKS[id] then
            WTF.accountDB.ticks[id] = nil
        end
    end
    for id, rank in pairs(RANKS) do
        local name = C_Spell.GetSpellName(id)
        if type(name) == "string" then
            predict.byName[name] = rank[1]
        end
    end
    -- Made only here, past the class gate and on a client with the combat log.
    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", OnEvent)
    for _, event in ipairs({"COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "NAME_PLATE_UNIT_ADDED",
        "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH", "UNIT_MAXHEALTH"}) do
        events:RegisterEvent(event)
    end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    RegisterSource()
    -- The target frame's block is made at login, out of combat.
    local bar = WTF.shared.FindUnitBar("target")
    if bar then
        WTF.shared.PrepareBar(bar, "target")
    end
    DrawAll()
end

-- /wtf debug_predict: each mob's DoTs, ticks, the average tick and where it
-- came from (learned, saved, or guessed), and the damage to come.
function WTF.ReportPredictDebug()
    if not predict.available then
        WTF.Report("DoT prediction: off on this client (it needs the combat log, as on Classic Era).")
        return
    end
    local settings = WTF.db.predict
    WTF.Report(string.format("DoT prediction: enabled=%s plates=%s dies=%s", tostring(settings.enabled),
        tostring(settings.plates), tostring(settings.dies)))
    -- Which AddOn's bar each unit is drawn on.
    local frames = {}
    for _, unit in ipairs({"target", "focus"}) do
        local _, info = WTF.shared.FindUnitBar(unit)
        frames[#frames + 1] = unit .. "=" .. tostring(info and info.name or "none")
    end
    for index = 1, MAX_NAMEPLATE_UNITS do
        local shown = predict.plates["nameplate" .. index]
        if shown then
            frames[#frames + 1] = "nameplate" .. index .. "=" .. shown.name
        end
    end
    WTF.Report("Frames: " .. table.concat(frames, ", "))
    local now, any = Now(), false
    for guid, mob in pairs(predict.mobs) do
        any = true
        WTF.Report(string.format("%s: %d to come", tostring(mob.name), WTF.PredictedDamage(guid)))
        for _, family in ipairs(FAMILY_ORDER) do
            local dot = mob.dots[family]
            if dot then
                WTF.Report(string.format("  %s (spell %d): tick %d of %d, %s %.1f, %d to come", family, dot.rank,
                    TicksDone(dot, now), dot.ticks, dot.source, dot.average,
                    math.floor(DotRemaining(dot, now) + 0.5)))
            end
        end
    end
    if not any then
        WTF.Report("No DoTs of yours on any mob.")
    end
end
