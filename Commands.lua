local _, WTF = ...

local USAGE = "Use /wtf, /wtf options, /wtf shards, /wtf stones, /wtf reset, /wtf debug_shards, /wtf debug_delete, "
    .. "/wtf debug_stones, /wtf debug_click, /wtf debug_tracker, /wtf debug_announce, /wtf debug_emote, or /wtf debug_restrictions."
local UNAVAILABLE = "Warlock Tools Forever is unavailable. Check the WTF login message."

-- Each command is one word; "" opens the settings. Handlers live in the other
-- files. Diagnostics also run when WTF is unavailable, to help explain why.
local COMMANDS = {
    [""] = {handler = "OpenSettings"},
    options = {handler = "OpenSettings"},
    shards = {handler = "ReportShardStatus"},
    debug_restrictions = {handler = "ReportRestrictions", always = true},
    debug_shards = {handler = "ReportShardDebug", always = true},
    debug_delete = {handler = "DebugDeleteShard"},
    reset = {handler = "ResetPositions"},
    stones = {handler = "ReportStoneStatus"},
    debug_stones = {handler = "ReportStoneDebug"},
    debug_click = {handler = "ReportClickDebug"},
    debug_tracker = {handler = "ReportTrackerDebug", always = true},
    debug_announce = {handler = "ReportAnnounceDebug"},
    debug_emote = {handler = "DebugEmote"},
}

function WTF.ParseCommand(message)
    if type(message) ~= "string" then
        return nil, USAGE
    end
    local command = message:match("^%s*(.-)%s*$"):lower()
    if command:find("%s") or not COMMANDS[command] then
        return nil, USAGE
    end
    return command
end

function WTF.HandleCommand(message)
    local command, usage = WTF.ParseCommand(message)
    if not command then
        WTF.Report(usage)
        return
    end
    local entry = COMMANDS[command]
    if not WTF.available and not entry.always then
        WTF.Report(UNAVAILABLE)
        return
    end
    WTF[entry.handler]()
end
