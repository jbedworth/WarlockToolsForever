local addonName, WTF = ...

-- Alerts: a sound when Nightfall procs. Forever's Nightfall talent gives
-- Corruption, Drain Soul, Drain Life, and Wrack a chance to grant Shadow
-- Trance, an instant Shadow Bolt. WTF cannot read your buffs in combat, so it
-- asks the game to play the sound when the buff appears
-- (C_UnitAuras.AddAuraSound, as BigWigs does). Off by default
-- (author-approved): many players use it, others find it noisy.

-- Shadow Trance, the Nightfall buff (Classic ID).
local SHADOW_TRANCE_SPELL_ID = 17941
-- At most one sound per this many seconds (the API allows 0 to 5).
local SOUND_THROTTLE = 1

-- The sound choices, WTF.NIGHTFALL_SOUNDS, live in Core with the saved settings.

local alerts = {soundID = nil, deferred = false, available = false}

local SOUND_FOLDER = "Interface\\AddOns\\" .. addonName .. "\\Sounds\\"

-- A file ID (a number), or the path of one of WTF's own sounds.
local function SoundFile(key)
    for _, sound in ipairs(WTF.NIGHTFALL_SOUNDS) do
        if sound.key == key then
            return sound.pick and SOUND_FOLDER .. sound.pick or sound.file
        end
    end
end

-- The game refuses aura sound changes during a boss encounter.
local function Restricted()
    if type(C_RestrictedActions) ~= "table" or type(C_RestrictedActions.IsAddOnRestrictionActive) ~= "function"
        or type(Enum) ~= "table" or type(Enum.AddOnRestrictionType) ~= "table" then
        return false
    end
    return C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Encounter) == true
end

function WTF.HasNightfallSound()
    return alerts.available
end

-- Registers the chosen sound, or removes it; waits out an encounter.
function WTF.ApplyNightfallSound()
    if not alerts.available then
        return
    end
    if Restricted() then
        alerts.deferred = true
        return
    end
    alerts.deferred = false
    if alerts.soundID then
        C_UnitAuras.RemoveAuraSound(alerts.soundID)
        alerts.soundID = nil
    end
    local settings = WTF.db.alerts
    if not settings.nightfall then
        return
    end
    local trigger = Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added or 0
    local file = SoundFile(settings.nightfallSound)
    local info = {
        spellID = SHADOW_TRANCE_SPELL_ID,
        unitToken = "player",
        outputChannel = "master",
        throttleSeconds = SOUND_THROTTLE,
    }
    if type(file) == "number" then
        info.soundFileID = file
    else
        info.soundFileName = file
    end
    alerts.soundID = C_UnitAuras.AddAuraSound(trigger, info)
end

-- Plays the chosen sound once, so the settings page can preview it.
function WTF.PreviewNightfallSound()
    PlaySoundFile(SoundFile(WTF.db.alerts.nightfallSound), "Master")
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    if alerts.deferred and not Restricted() then
        WTF.ApplyNightfallSound()
    end
end)

function WTF.InitializeAlerts()
    if type(C_UnitAuras) ~= "table" or type(C_UnitAuras.AddAuraSound) ~= "function"
        or type(C_UnitAuras.RemoveAuraSound) ~= "function" then
        return
    end
    alerts.available = true
    events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    WTF.ApplyNightfallSound()
end
