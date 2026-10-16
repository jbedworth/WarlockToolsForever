local addonName, WTF = ...

-- Announce: tell your group (or say it) and whisper the target when your
-- Ritual of Summoning starts, or when a Soulstone use on someone succeeds;
-- whisper the player when a Healthstone trade from the Stones button opens;
-- emote when you create a Healthstone or a Soulstone.
-- The target's name comes from the cast's UNIT_SPELLCAST_SENT event; a summon
-- falls back to your friendly player target, since the ritual creates a portal
-- and may not name one. Nothing is sent for yourself, and a Soulstone cast
-- that fails sends nothing.

-- Spells by name, so every rank counts. Classic IDs: Ritual of Summoning and
-- Soulstone Resurrection, the Soulstone item's spell.
local SUMMON_SPELL_ID = 698
local SOULSTONE_SPELL_ID = 20707
-- Create Healthstone and Create Soulstone, any rank.
local CREATE_HEALTHSTONE_SPELL_ID = 6201
local CREATE_SOULSTONE_SPELL_ID = 693
-- At most one stone creation emote per stone type a minute, so handing out
-- stones stays quiet. In client an emote from the cast's success event was
-- blocked, like Say outdoors, so it waits for your next key press or world
-- click, as shard deletion does, and is dropped if none comes soon.
local EMOTE_REPEAT_SECONDS = 60
local EMOTE_INPUT_WAIT = 30
-- One summon announcement per ritual: its cast start and channel start can
-- both arrive, seconds apart.
local SUMMON_REPEAT_SECONDS = 10
local EVENT_LOG_SIZE = 8

local announce = {casts = {}, blocked = {}, sending = nil, names = {}, lastSummon = nil, log = {},
    lastEmote = {}}

local function SendChat(message, chatType, target)
    local send = type(C_ChatInfo) == "table" and C_ChatInfo.SendChatMessage or SendChatMessage
    announce.sending = chatType
    send(message, chatType, nil, target)
    announce.sending = nil
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

-- target is the name shown in messages; whisperTo is the full name. Every
-- Forever character has a first and a last name: in client a whisper to the
-- first name alone failed, while "First-Last" reached the player.
local function Announce(kind, target, whisperTo)
    local settings = WTF.db.announce
    local keys = KINDS[kind]
    if settings[keys.group] then
        local channel = GroupChannel()
        if channel then
            SendChat(WTF.FormatAnnouncement(settings[keys.group .. "Text"], target), channel)
        end
    end
    if settings[keys.whisper] then
        SendChat(WTF.FormatAnnouncement(settings[keys.whisper .. "Text"], target), "WHISPER", whisperTo or target)
        announce.lastWhisper = whisperTo or target
    end
end

-- Stones calls this when a trade holding the Healthstone WTF put in completes.
function WTF.WhisperHealthstoneGift(target, whisperTo)
    local settings = WTF.db.announce
    if not settings.enabled or not settings.healthstoneWhisper or not target then
        return
    end
    SendChat(WTF.FormatAnnouncement(settings.healthstoneWhisperText, target), "WHISPER", whisperTo or target)
    announce.lastWhisper = whisperTo or target
end

local EMOTE_KINDS = {healthstoneCreate = "healthstoneEmote", soulstoneCreate = "soulstoneEmote"}

local function Emote(kind)
    local settings = WTF.db.announce
    local switch = EMOTE_KINDS[kind]
    local now = GetTime()
    if not settings[switch] or (announce.lastEmote[kind] and now - announce.lastEmote[kind] < EMOTE_REPEAT_SECONDS) then
        return
    end
    announce.lastEmote[kind] = now
    local message = WTF.FormatAnnouncement(settings[switch .. "Text"], "")
    WTF.RunOnNextInput(function()
        if GetTime() - now <= EMOTE_INPUT_WAIT then
            SendChat(message, "EMOTE")
        end
    end)
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
    elseif name and name == announce.names.healthstoneCreate then
        return "healthstoneCreate"
    elseif name and name == announce.names.soulstoneCreate then
        return "soulstoneCreate"
    end
end

-- Whether a cast target name is you. In client a Soulstone on yourself was
-- whispered to you: the cast named you "First-Last", your full name.
local function IsSelf(target)
    local name, surname = target:match("^([^%-]+)%-?(.*)$")
    local myName, mySurname = UnitFullName("player")
    if WTF.IsSecret(myName) or name ~= myName then
        return false
    end
    return surname == "" or WTF.IsSecret(mySurname) or type(mySurname) ~= "string" or mySurname == ""
        or surname:gsub("%s", "") == mySurname:gsub("%s", "")
end

local function IsUsableTarget(target)
    if WTF.IsSecret(target) or type(target) ~= "string" or target == "" then
        return false
    end
    return not IsSelf(target)
end

-- A unit's names: "First Last" for messages (%T, as the game shows it) and
-- "First-Last" to whisper. On Forever, UnitName's second value, the realm on
-- other clients, is the character's last name.
local function UnitNames(unit)
    local name, surname = UnitName(unit)
    if WTF.IsSecret(name) or WTF.IsSecret(surname) or type(name) ~= "string" then
        return nil
    end
    if type(surname) == "string" and surname ~= "" then
        return name .. " " .. surname, name .. "-" .. surname
    end
    return name, name
end

-- Your target, if it is a friendly player other than you: its two names.
local function FriendlyPlayerTarget()
    if not UnitExists("target") or not UnitIsPlayer("target") or not UnitIsFriend("player", "target") then
        return nil
    end
    local name = UnitName("target")
    if IsUsableTarget(name) then
        return UnitNames("target")
    end
end

WTF.FriendlyTargetNames = FriendlyPlayerTarget

-- A name from a cast event ("First" or "First-Last"): both names, the last
-- name taken from your target when that is the player.
local function ResolveName(castName)
    local first, surname = castName:match("^([^%-]+)%-?(.*)$")
    if UnitExists("target") and UnitName("target") == first then
        return UnitNames("target")
    end
    if surname ~= "" then
        return first .. " " .. surname, castName
    end
    return castName, castName
end

local function Log(event, spellID, target)
    table.insert(announce.log, 1, {time = GetTime(), event = event, spell = WTF.Describe(spellID),
        target = WTF.Describe(target)})
    announce.log[EVENT_LOG_SIZE + 1] = nil
end

local function AnnounceSummon(castGUID)
    local now = GetTime()
    if announce.lastSummon and now - announce.lastSummon < SUMMON_REPEAT_SECONDS then
        return
    end
    local cast = not WTF.IsSecret(castGUID) and announce.casts[castGUID]
    local target, whisperTo
    if cast and cast.target then
        target, whisperTo = cast.target, cast.whisperTo
    else
        target, whisperTo = FriendlyPlayerTarget()
    end
    if not target then
        return
    end
    announce.lastSummon = now
    Announce("summon", target, whisperTo)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit, first, second, third)
    if event == "ADDON_ACTION_BLOCKED" then
        -- Saying something outdoors needs a key press or click; cast events
        -- are not one, so SAY can be refused.
        local chatType = announce.sending
        if unit == addonName and announce.probing then
            announce.probeBlocked = true
            return
        end
        if unit == addonName and chatType and not announce.blocked[chatType] then
            announce.blocked[chatType] = true
            if chatType == "SAY" then
                WTF.Report("The game blocked the Say announcement. Choose Group in the Announce settings.")
            else
                WTF.Report("The game blocked the " .. chatType:lower() .. " message. Turn it off in the Announce settings.")
            end
        end
        return
    end
    local spellID = event == "UNIT_SPELLCAST_SENT" and third or second
    local kind = KindOf(spellID)
    if kind then
        Log(event, spellID, event == "UNIT_SPELLCAST_SENT" and first or nil)
    end
    if not WTF.db.announce.enabled or not kind then
        return
    end
    if EMOTE_KINDS[kind] then
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            Emote(kind)
        end
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then
        local target, castGUID = first, second
        if not WTF.IsSecret(castGUID) then
            local name, whisperTo
            if IsUsableTarget(target) then
                name, whisperTo = ResolveName(target)
            elseif kind == "summon" then
                name, whisperTo = FriendlyPlayerTarget()
            end
            announce.casts[castGUID] = {kind = kind, target = name, whisperTo = whisperTo}
        end
    elseif kind == "summon" then
        -- At the start of the ritual; success also counts, in case no start
        -- event arrives.
        if event ~= "UNIT_SPELLCAST_FAILED" and event ~= "UNIT_SPELLCAST_INTERRUPTED" then
            AnnounceSummon(first)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local cast = not WTF.IsSecret(first) and announce.casts[first]
        if cast and cast.target then
            Announce("soulstone", cast.target, cast.whisperTo)
        end
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if not WTF.IsSecret(first) then
            announce.casts[first] = nil
        end
    end
end)

function WTF.InitializeAnnounce()
    announce.names.summon = C_Spell.GetSpellName(SUMMON_SPELL_ID)
    announce.names.soulstone = C_Spell.GetSpellName(SOULSTONE_SPELL_ID)
    announce.names.healthstoneCreate = C_Spell.GetSpellName(CREATE_HEALTHSTONE_SPELL_ID)
    announce.names.soulstoneCreate = C_Spell.GetSpellName(CREATE_SOULSTONE_SPELL_ID)
    for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED"}) do
        events:RegisterUnitEvent(event, "player")
    end
    events:RegisterEvent("ADDON_ACTION_BLOCKED")
end

-- /wtf debug_emote: a test emote from a timer (no key press) through
-- C_ChatInfo.SendChatMessage, then through the global SendChatMessage that
-- RestedXP uses for its level-up emote, reporting which the game blocks.
local PROBE_DELAYS = {1, 3}

local function ProbeEmote(label, send)
    announce.probing, announce.probeBlocked = true, false
    send("is testing an emote (WTF debug, " .. label .. ")", "EMOTE")
    announce.probing = false
    WTF.Report(string.format("debug_emote %s from a timer: %s", label,
        announce.probeBlocked and "blocked" or "not blocked"))
end

function WTF.DebugEmote()
    local probes = {}
    if type(C_ChatInfo) == "table" and type(C_ChatInfo.SendChatMessage) == "function" then
        probes[#probes + 1] = {"C_ChatInfo.SendChatMessage", C_ChatInfo.SendChatMessage}
    end
    if type(SendChatMessage) == "function" then
        probes[#probes + 1] = {"SendChatMessage", SendChatMessage}
    end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" or #probes == 0 then
        WTF.Report("debug_emote needs C_Timer.After and a chat send function.")
        return
    end
    for index, probe in ipairs(probes) do
        C_Timer.After(PROBE_DELAYS[index], function() ProbeEmote(probe[1], probe[2]) end)
    end
end

-- /wtf debug_announce: the spell names WTF listens for and the latest summon
-- and Soulstone cast events, with what each named as the target.
function WTF.ReportAnnounceDebug()
    WTF.Report(string.format("debug_announce summon=%s soulstone=%s enabled=%s channel=%s group=%s lastWhisper=%s",
        tostring(announce.names.summon), tostring(announce.names.soulstone),
        tostring(WTF.db.announce.enabled), WTF.db.announce.channel, tostring(GroupChannel()),
        tostring(announce.lastWhisper)))
    local now = GetTime()
    for _, entry in ipairs(announce.log) do
        WTF.Report(string.format("debug_announce %.1fs ago %s spell=%s target=%s", now - entry.time,
            entry.event, entry.spell, entry.target))
    end
end
