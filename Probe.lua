local _, WTF = ...

-- /wtf debug_restrictions reports which combat data this client hides from
-- AddOns. Run it out of combat, then in combat with a target that has your
-- DoTs on it. It reads and prints only; it never changes anything. It never
-- registers for the combat log: the client restricts it and reports the
-- attempt as a blocked action.
local MAX_AURAS = 40
-- Nameplate unit tokens run nameplate1 to nameplate40; the plate frames on
-- the target client do not carry their token.
local MAX_NAMEPLATE_UNITS = 40
local MAX_NAMEPLATES_SHOWN = 3
local MY_DEBUFFS = "HARMFUL|PLAYER"
local RESTRICTION_STATES = {[0] = "inactive", [1] = "activating", [2] = "active"}

local function Report(text)
    WTF.Report("debug_restrictions " .. text)
end

-- Each check runs on its own, so one refused API cannot hide the others.
-- The client may not show Lua errors, so a failure is printed in chat.
local function Step(label, check, ...)
    local ok, failure = pcall(check, ...)
    if not ok then
        Report(label .. " failed: " .. tostring(failure))
    end
end

-- The player's own recent casts, to learn whether spell IDs and cast targets
-- stay readable in combat. Values are kept only as already-safe text.
local casts = {}
local castFrame = CreateFrame("Frame")
castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castFrame:SetScript("OnEvent", function(_, event, _, first, second, third)
    if event == "UNIT_SPELLCAST_SENT" then
        casts.sent = {time = GetTime(), target = WTF.Describe(first), spell = WTF.Describe(third)}
    else
        casts.succeeded = {time = GetTime(), spell = WTF.Describe(second)}
        casts.succeededID = not WTF.IsSecret(second) and type(second) == "number" and second or nil
    end
end)

local function ReportRestrictionStates()
    if type(C_RestrictedActions) ~= "table" or type(C_RestrictedActions.GetAddOnRestrictionState) ~= "function"
        or type(Enum) ~= "table" or type(Enum.AddOnRestrictionType) ~= "table" then
        Report("restriction API missing")
        return
    end
    local types = {}
    for name, value in pairs(Enum.AddOnRestrictionType) do
        types[#types + 1] = {name = name, value = value}
    end
    table.sort(types, function(a, b) return a.value < b.value end)
    local parts = {}
    for _, restriction in ipairs(types) do
        local stateValue = C_RestrictedActions.GetAddOnRestrictionState(restriction.value)
        local stateName = WTF.IsSecret(stateValue) and "secret"
            or RESTRICTION_STATES[stateValue] or tostring(stateValue)
        parts[#parts + 1] = restriction.name .. "=" .. stateName
    end
    Report("states " .. table.concat(parts, " "))
end

local function ReportCombatLog()
    local restricted = "n/a"
    if type(C_CombatLog) == "table" and type(C_CombatLog.IsCombatLogRestricted) == "function" then
        restricted = WTF.Describe(C_CombatLog.IsCombatLogRestricted())
    end
    Report("combatLog restricted=" .. restricted)
end

local function ReportCasts()
    local now = GetTime()
    local sent, succeeded = casts.sent, casts.succeeded
    Report(string.format("lastCast sent=%s target=%s spell=%s; succeeded=%s spell=%s",
        sent and string.format("%.1fs ago", now - sent.time) or "none", sent and sent.target or "-",
        sent and sent.spell or "-",
        succeeded and string.format("%.1fs ago", now - succeeded.time) or "none",
        succeeded and succeeded.spell or "-"))
end

local function DescribeAura(aura)
    if WTF.IsSecret(aura) then
        return "whole table secret"
    end
    if type(aura) ~= "table" then
        return "no data (" .. type(aura) .. ")"
    end
    return string.format("name=%s spellId=%s icon=%s duration=%s expires=%s stacks=%s",
        WTF.Describe(aura.name), WTF.Describe(aura.spellId), WTF.Describe(aura.icon),
        WTF.Describe(aura.duration), WTF.Describe(aura.expirationTime), WTF.Describe(aura.applications))
end

local function HasAuraFunction(name)
    return type(C_UnitAuras) == "table" and type(C_UnitAuras[name]) == "function"
end

local function ReportByIndex(unit)
    if not HasAuraFunction("GetAuraDataByIndex") then
        Report(unit .. " byIndex: missing")
        return
    end
    for index = 1, MAX_AURAS do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, MY_DEBUFFS)
        if not WTF.IsSecret(aura) and type(aura) ~= "table" then
            if index == 1 then
                Report(unit .. " byIndex: none of yours")
            end
            return
        end
        Report(string.format("%s byIndex %d: %s", unit, index, DescribeAura(aura)))
    end
end

-- A duration object can drive Blizzard's timer widgets even when its values
-- are secret; report whether it exists and whether its values are readable.
local function DescribeDuration(unit, instanceID)
    if not HasAuraFunction("GetAuraDuration") then
        return "missing"
    end
    local duration = C_UnitAuras.GetAuraDuration(unit, instanceID)
    if WTF.IsSecret(duration) then
        return "secret object"
    end
    if duration == nil then
        return "none"
    end
    local secretValues = type(duration.HasSecretValues) == "function" and duration:HasSecretValues()
    local remaining = type(duration.GetRemainingDuration) == "function" and duration:GetRemainingDuration()
    return string.format("object secretValues=%s remaining=%s", tostring(secretValues), WTF.Describe(remaining))
end

local function ReportInstances(unit)
    if not HasAuraFunction("GetUnitAuraInstanceIDs") then
        Report(unit .. " instanceIDs: missing")
        return
    end
    local ids = C_UnitAuras.GetUnitAuraInstanceIDs(unit, MY_DEBUFFS)
    if WTF.IsSecret(ids) then
        Report(unit .. " instanceIDs: whole table secret")
        return
    end
    Report(string.format("%s instanceIDs count=%d", unit, #ids))
    for index = 1, math.min(#ids, MAX_AURAS) do
        local id = ids[index]
        local aura = HasAuraFunction("GetAuraDataByAuraInstanceID")
            and C_UnitAuras.GetAuraDataByAuraInstanceID(unit, id)
        Report(string.format("%s instance %s: %s; duration %s", unit, WTF.Describe(id),
            DescribeAura(aura), DescribeDuration(unit, id)))
    end
end

local function ReportUnitAuras(unit)
    if not HasAuraFunction("GetUnitAuras") then
        Report(unit .. " getUnitAuras: missing")
        return
    end
    local auras = C_UnitAuras.GetUnitAuras(unit, MY_DEBUFFS)
    if WTF.IsSecret(auras) then
        Report(unit .. " getUnitAuras: whole table secret")
        return
    end
    Report(string.format("%s getUnitAuras count=%d", unit, #auras))
    if #auras > 0 then
        Report(unit .. " getUnitAuras 1: " .. DescribeAura(auras[1]))
    end
end

-- Lookups by spell name or ID carry RequiresNonSecretAura instead of
-- RequiresUnitAuraAccess, so they may answer in combat where index access
-- refuses. Spell IDs are Classic's (confirmed for Corruption in client); Bane
-- IDs are unknown, so Banes are looked up by name.
local NAMED_SPELL_IDS = {172, 348, 18265, 980, 603, 702, 704, 1490, 17862, 1714, 5782}
local BANE_NAMES = {"Bane of Agony", "Bane of Doom", "Bane of Havoc"}

local function ReportByName(unit)
    if not HasAuraFunction("GetAuraDataBySpellName") then
        Report(unit .. " byName: missing")
        return
    end
    local names, seen = {}, {}
    for _, id in ipairs(NAMED_SPELL_IDS) do
        local name = C_Spell.GetSpellName(id)
        if name and not seen[name] then
            names[#names + 1], seen[name] = name, true
        end
    end
    for _, name in ipairs(BANE_NAMES) do
        if not seen[name] then
            names[#names + 1], seen[name] = name, true
        end
    end
    local found = 0
    for _, name in ipairs(names) do
        local aura = C_UnitAuras.GetAuraDataBySpellName(unit, name, MY_DEBUFFS)
        if WTF.IsSecret(aura) or aura ~= nil then
            found = found + 1
            Report(string.format("%s byName %s: %s", unit, name, DescribeAura(aura)))
        end
    end
    Report(string.format("%s byName checked=%d found=%d", unit, #names, found))
end

local function ReportBySpellID(unit)
    local spellID = casts.succeededID
    if not HasAuraFunction("GetUnitAuraBySpellID") or not spellID then
        Report(unit .. " bySpellID: " .. (spellID and "missing" or "no readable last cast"))
        return
    end
    Report(string.format("%s bySpellID %d: %s", unit, spellID,
        DescribeAura(C_UnitAuras.GetUnitAuraBySpellID(unit, spellID))))
end

local function ReportUnit(unit)
    if not UnitExists(unit) then
        Report(unit .. " none")
        return
    end
    Report(string.format("%s name=%s guid=%s canAttack=%s", unit, WTF.Describe(UnitName(unit)),
        WTF.Describe(UnitGUID(unit)), WTF.Describe(UnitCanAttack("player", unit))))
    Step(unit .. " byIndex", ReportByIndex, unit)
    Step(unit .. " instanceIDs", ReportInstances, unit)
    Step(unit .. " getUnitAuras", ReportUnitAuras, unit)
    Step(unit .. " byName", ReportByName, unit)
    Step(unit .. " bySpellID", ReportBySpellID, unit)
end

local function ReportNameplates()
    if type(C_NamePlate) ~= "table" or type(C_NamePlate.GetNamePlates) ~= "function" then
        Report("nameplates: C_NamePlate.GetNamePlates missing")
        return
    end
    local units = {}
    for index = 1, MAX_NAMEPLATE_UNITS do
        local unit = "nameplate" .. index
        if UnitExists(unit) then
            units[#units + 1] = unit
        end
    end
    Report(string.format("nameplates frames=%d units=%d", #C_NamePlate.GetNamePlates(), #units))
    for index = 1, math.min(#units, MAX_NAMEPLATES_SHOWN) do
        Step(units[index], ReportUnit, units[index])
    end
end

local function ReportTargetIsFocus()
    if UnitExists("target") and UnitExists("focus") then
        Report("targetIsFocus=" .. WTF.Describe(UnitIsUnit("target", "focus")))
    end
end

function WTF.ReportRestrictions()
    Report(string.format("combat=%s secretAPI=%s", tostring(InCombatLockdown()),
        tostring(type(issecretvalue) == "function")))
    Step("states", ReportRestrictionStates)
    Step("combatLog", ReportCombatLog)
    Step("lastCast", ReportCasts)
    Step("target", ReportUnit, "target")
    Step("focus", ReportUnit, "focus")
    Step("targetIsFocus", ReportTargetIsFocus)
    Step("nameplates", ReportNameplates)
end
