local addonName, ns = ...

-- Main-hand weapon enchants (2.21.0; John, 2026-11-28, for Warlock Tools
-- Forever's Spellstone and Firestone, which are main-hand imbues on
-- Forever: "Once created and one is in your bag and it's not applied, we
-- show the 'glow' reminder around the icon in the bar"). Shared here so
-- Dyre's Buff Reminders can use it later for Rogue poisons and Shaman
-- weapon enchants. WEAPON_ENCHANT_VERSION is the feature test.
--
-- DyresToolkit.MainHandEnchant() -> state, enchantID, secondsLeft:
--   "on" with the enchant ID (nil if the client gives none) and the seconds
--   left; "off"; or "unknown" (no GetWeaponEnchantInfo, or a secret answer).
--   A secret value is never compared or indexed.
-- DyresToolkit.OnWeaponEnchantChanged(callback(state, enchantID, secondsLeft)):
--   called when the state or the enchant ID changes (never for "unknown",
--   which keeps the last known state). The toolkit registers its events
--   only after the first listener. A listener that fails is off until
--   reload, said only in debug mode.
--
-- Events only: UNIT_INVENTORY_CHANGED for the player (the enchant goes on or
-- comes off), PLAYER_EQUIPMENT_CHANGED (another weapon), PLAYER_ENTERING_WORLD,
-- and PLAYER_REGEN_ENABLED (a read in combat may be secret). An enchant that
-- runs out may fire no event, so one C_Timer.After at its end reads again
-- (one-shot, replaced at each read; no polling). Not checked in client yet:
-- /dyre weapon prints the raw read.

DyresToolkit.WEAPON_ENCHANT_VERSION = 1

local IsSecret = DyresToolkit.IsSecret
local Describe = DyresToolkit.Describe
-- A read a moment after the enchant's end, so the client has removed it.
local EXPIRY_SLACK = 0.5

local listeners = {}
local known = {state = nil, id = nil}
local timerToken = 0
local frame

function DyresToolkit.MainHandEnchant()
    if type(GetWeaponEnchantInfo) ~= "function" then
        return "unknown"
    end
    local has, expiration, _, id = GetWeaponEnchantInfo()
    if IsSecret(has) or IsSecret(expiration) or IsSecret(id) then
        return "unknown"
    end
    if not has then
        return "off"
    end
    local seconds = type(expiration) == "number" and expiration > 0 and expiration / 1000 or nil
    return "on", type(id) == "number" and id or nil, seconds
end

local function Notify(state, id, seconds)
    for index, listener in ipairs(listeners) do
        if not listener.failed then
            local ok, message = pcall(listener.callback, state, id, seconds)
            if not ok then
                listener.failed = true
                if ns.debug then
                    ns.Report("A weapon enchant listener failed: " .. tostring(message))
                end
            end
        end
    end
end

local Check

local function ScheduleExpiry(seconds)
    timerToken = timerToken + 1
    if type(seconds) ~= "number" or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        return
    end
    local token = timerToken
    C_Timer.After(seconds + EXPIRY_SLACK, function()
        if token == timerToken then
            Check()
        end
    end)
end

Check = function()
    local state, id, seconds = DyresToolkit.MainHandEnchant()
    if state == "unknown" then
        return
    end
    ScheduleExpiry(state == "on" and seconds or nil)
    if state ~= known.state or id ~= known.id then
        known.state, known.id = state, id
        Notify(state, id, seconds)
        return true
    end
end
ns.CheckWeaponEnchant = Check

local function Start()
    if frame then
        return
    end
    frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    if type(frame.RegisterUnitEvent) == "function" then
        frame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    else
        frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    end
    frame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then
            return
        end
        Check()
    end)
end

function DyresToolkit.OnWeaponEnchantChanged(callback)
    if type(callback) ~= "function" then
        return false
    end
    local listener = {callback = callback}
    listeners[#listeners + 1] = listener
    Start()
    -- The new listener hears the state now: from Check when it changed,
    -- else here.
    if not Check() and known.state then
        local _, _, seconds = DyresToolkit.MainHandEnchant()
        if not pcall(callback, known.state, known.id, seconds) then
            listener.failed = true
        end
    end
    return true
end

-- /dyre weapon: the raw main-hand read, for the in-client probe.
function ns.ReportWeaponEnchant()
    if type(GetWeaponEnchantInfo) ~= "function" then
        ns.Report("Weapon enchant: GetWeaponEnchantInfo is missing.")
        return
    end
    local has, expiration, charges, id, offHas, offExpiration, offCharges, offID = GetWeaponEnchantInfo()
    ns.Report("Weapon enchant: main hand " .. Describe(has) .. ", ms left " .. Describe(expiration)
        .. ", charges " .. Describe(charges) .. ", ID " .. Describe(id) .. "; off hand " .. Describe(offHas)
        .. ", ID " .. Describe(offID) .. "; combat " .. tostring(InCombatLockdown() and true or false) .. ".")
    local state, readID, seconds = DyresToolkit.MainHandEnchant()
    ns.Report("Weapon enchant: read as " .. state .. (readID and (", ID " .. readID) or "")
        .. (seconds and (", " .. math.floor(seconds) .. " s left") or "") .. ".")
end
