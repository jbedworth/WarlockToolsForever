local _, ns = ...
local DyresToolkit = ns.toolkit

-- Group announcements, for every Dyre's AddOn (Toolkit 2.5.0, engine stage A;
-- lead-approved plan, 2026-11-01). Moved from Warlock Tools Forever 1.4.1
-- (Announce.lua's GroupChannel, SendGroupAnnouncement, FormatAnnouncement;
-- Control.lua's RAID_MARKERS and cast announce throttle) and Mage Tools
-- Forever 1.2.3 (Core.lua's FormatAnnouncement with a values table,
-- Polymorph.lua's announce), which keep their own copies until each switches
-- over. The owning AddOn keeps its switches and texts in its own saved
-- variables and passes them in.

-- Raid markers by index, as /tm numbers them, and their chat codes.
DyresToolkit.RAID_MARKERS = {
    {index = 0, label = "None"},
    {index = 1, label = "Star", code = "{star}"},
    {index = 2, label = "Circle", code = "{circle}"},
    {index = 3, label = "Diamond", code = "{diamond}"},
    {index = 4, label = "Triangle", code = "{triangle}"},
    {index = 5, label = "Moon", code = "{moon}"},
    {index = 6, label = "Square", code = "{square}"},
    {index = 7, label = "Cross", code = "{cross}"},
    {index = 8, label = "Skull", code = "{skull}"},
}

function DyresToolkit.ValidMarker(index)
    for _, marker in ipairs(DyresToolkit.RAID_MARKERS) do
        if marker.index == index then
            return true
        end
    end
    return false
end

-- A marker's chat code, such as "{moon}", else "" (none, or not a marker).
function DyresToolkit.MarkerCode(index)
    for _, marker in ipairs(DyresToolkit.RAID_MARKERS) do
        if marker.index == index then
            return marker.code or ""
        end
    end
    return ""
end

-- Raid or party, else nothing when you are alone; "SAY" when say is true.
function DyresToolkit.GroupChannel(say)
    if say then
        return "SAY"
    end
    if IsInRaid() then
        return "RAID"
    end
    if IsInGroup() then
        return "PARTY"
    end
end

function DyresToolkit.SendChat(message, chatType, target)
    local send = type(C_ChatInfo) == "table" and C_ChatInfo.SendChatMessage or SendChatMessage
    send(message, chatType, nil, target)
end

-- A message text with %X tokens filled from values ({T = target name, Z =
-- zone, M = marker code, ...}). A token with no value stays as it is; a value
-- of false or "" removes the token and the one space before it (a missing
-- marker: "Banished %T %M" says "Banished Grunt"). Secret values give "".
function DyresToolkit.FormatAnnouncement(text, values)
    values = values or {}
    local function Fill(space, token)
        local value = values[token]
        if DyresToolkit.IsSecret(value) then
            return ""
        end
        if value == nil then
            return nil
        end
        if value == false or value == "" then
            return ""
        end
        return space .. tostring(value)
    end
    return (text:gsub("( ?)%%(%a)", Fill))
end

-- An announcer: one AddOn's group messages, each kind (a key such as "fear")
-- at most once every repeatSeconds (default 3), so a recast or a second event
-- for one cast says it once. spec: {repeatSeconds, say = function() return
-- true to use Say end, enabled = function() return false to stay quiet end}.
-- announcer:SendGroup(key, message) gives whether it was sent.
function DyresToolkit.CreateAnnouncer(spec)
    spec = spec or {}
    local announcer = {last = {}}
    local repeatSeconds = spec.repeatSeconds or 3

    function announcer:SendGroup(key, message)
        if spec.enabled and not spec.enabled() then
            return false
        end
        local now = GetTime()
        local last = self.last[key]
        if last and now - last < repeatSeconds then
            return false
        end
        local channel = DyresToolkit.GroupChannel(spec.say and spec.say())
        if not channel or type(message) ~= "string" or message == "" then
            return false
        end
        DyresToolkit.SendChat(message, channel)
        self.last[key] = now
        return true
    end

    return announcer
end
