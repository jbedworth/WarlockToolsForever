local _, WTF = ...

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

-- The sound is one of Dyre's Sounds' aura sounds (Core sanitizes the key).

local alerts = {soundID = nil, deferred = false, available = false}

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
    local library = WTF.SoundLibrary()
    if not library then
        WTF.ReportMissingSounds()
        return
    end
    local sound = library.AuraSound(settings.nightfallSound) or library.AuraSound(WTF.DEFAULT_NIGHTFALL_SOUND)
    if not sound then
        return
    end
    local trigger = Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added or 0
    alerts.soundID = C_UnitAuras.AddAuraSound(trigger, {
        spellID = SHADOW_TRANCE_SPELL_ID,
        unitToken = "player",
        outputChannel = "master",
        throttleSeconds = SOUND_THROTTLE,
        soundFileName = sound.soundFileName,
        soundFileID = sound.soundFileID,
    })
end

-- Plays the chosen sound once, so the settings page can preview it.
function WTF.PreviewNightfallSound()
    if not alerts.available then
        return
    end
    local library = WTF.SoundLibrary()
    if library then
        library.Play(WTF.db.alerts.nightfallSound)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    if alerts.deferred and not Restricted() then
        WTF.ApplyNightfallSound()
    end
end)

function WTF.InitializeAlerts()
    -- Dyre's Buff Reminders plays it; WTF registers nothing and keeps its settings.
    if WTF.NightfallStandAside() then
        return
    end
    if type(C_UnitAuras) ~= "table" or type(C_UnitAuras.AddAuraSound) ~= "function"
        or type(C_UnitAuras.RemoveAuraSound) ~= "function" then
        return
    end
    alerts.available = true
    events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    WTF.ApplyNightfallSound()
end
