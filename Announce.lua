local addonName, WTF = ...

-- Announce: when your Ritual of Summoning or a Soulstone use on someone
-- succeeds, tell your group (or say it), and whisper the target. The target's
-- name comes from the cast's UNIT_SPELLCAST_SENT event; nothing is sent for a
-- cast that fails or for yourself.

-- Spells by name, so every rank counts. Classic IDs: Ritual of Summoning and
-- Soulstone Resurrection, the Soulstone item's spell.
local SUMMON_SPELL_ID = 698
local SOULSTONE_SPELL_ID = 20707
local announce = {casts = {}, sayBlocked = false, sending = false, names = {}}

local function SendChat(message, chatType, target)
    local send = type(C_ChatInfo) == "table" and C_ChatInfo.SendChatMessage or SendChatMessage
    announce.sending = true
    send(message, chatType, nil, target)
    announce.sending = false
end

-- "group" sends to your raid or party and nothing when you are alone.
local function GroupChannel()
    if WTF.db.announce.channel == "say" then
        return "SAY"
    end
    if IsInRaid() then
        return "RAID"
    end
    if IsInGroup() then
        return "PARTY"
    end
end

function WTF.FormatAnnouncement(text, target)
    local zone = GetZoneText() or ""
    -- gsub replacement strings treat % specially, so escape names first.
    local safeTarget = target:gsub("%%", "%%%%")
    local safeZone = zone:gsub("%%", "%%%%")
    return (text:gsub("%%T", safeTarget):gsub("%%Z", safeZone))
end

local KINDS = {
    summon = {group = "summonGroup", whisper = "summonWhisper"},
    soulstone = {group = "soulstoneGroup", whisper = "soulstoneWhisper"},
}

local function Announce(kind, target)
    local settings = WTF.db.announce
    local keys = KINDS[kind]
    if settings[keys.group] then
        local channel = GroupChannel()
        if channel then
            SendChat(WTF.FormatAnnouncement(settings[keys.group .. "Text"], target), channel)
        end
    end
    if settings[keys.whisper] then
        SendChat(WTF.FormatAnnouncement(settings[keys.whisper .. "Text"], target), "WHISPER", target)
    end
end

local function KindOf(spellID)
    if WTF.IsSecret(spellID) or type(spellID) ~= "number" then
        return nil
    end
    local name = C_Spell.GetSpellName(spellID)
    if name and name == announce.names.summon then
        return "summon"
    elseif name and name == announce.names.soulstone then
        return "soulstone"
    end
end

local function IsUsableTarget(target)
    if WTF.IsSecret(target) or type(target) ~= "string" or target == "" then
        return false
    end
    local me = UnitName("player")
    return target ~= me
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit, first, second, third)
    if event == "ADDON_ACTION_BLOCKED" then
        -- Saying something outdoors needs a key press or click; the cast's
        -- success arrives later, so SAY can be refused.
        if unit == addonName and announce.sending and not announce.sayBlocked then
            announce.sayBlocked = true
            WTF.Report("The game blocked the Say announcement. Choose Group in the Announce settings.")
        end
        return
    end
    if not WTF.db.announce.enabled then
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then
        local target, castGUID, spellID = first, second, third
        local kind = KindOf(spellID)
        if kind and IsUsableTarget(target) and not WTF.IsSecret(castGUID) then
            announce.casts[castGUID] = {kind = kind, target = target}
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local castGUID = first
        if WTF.IsSecret(castGUID) then
            return
        end
        local cast = announce.casts[castGUID]
        announce.casts = {}
        if cast then
            Announce(cast.kind, cast.target)
        end
    else
        -- A failed or interrupted cast announces nothing.
        local castGUID = first
        if not WTF.IsSecret(castGUID) then
            announce.casts[castGUID] = nil
        end
    end
end)

function WTF.InitializeAnnounce()
    announce.names.summon = C_Spell.GetSpellName(SUMMON_SPELL_ID)
    announce.names.soulstone = C_Spell.GetSpellName(SOULSTONE_SPELL_ID)
    for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED"}) do
        events:RegisterUnitEvent(event, "player")
    end
    events:RegisterEvent("ADDON_ACTION_BLOCKED")
end
