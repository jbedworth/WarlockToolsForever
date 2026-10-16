local addonName, WTF = ...

local DEFAULT_TITLE = "Warlock Tools Forever"
local READY_MESSAGE = "  Ready. Type /wtf to open the settings."
local SLASH_KEY = "WARLOCKTOOLSFOREVER"
local PRIMARY_SLASH = "/wtf"
local BACKUP_SLASH = "/warlocktools"
local MAX_SLASH_ALIASES = 10
WTF.available = false

function WTF.Report(message)
    DEFAULT_CHAT_FRAME:AddMessage("WTF: " .. tostring(message))
end

-- Combat data can be a secret value on the target client: code may store and
-- pass it on, but never compare, concatenate, or print it.
function WTF.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end

-- Text for diagnostics that never touches a secret value's contents.
function WTF.Describe(value)
    if WTF.IsSecret(value) then
        return "secret"
    end
    return tostring(value)
end

-- Reads TOC fields so the banner follows the packaged version; never gates operations.
local function Metadata(field)
    if type(C_AddOns) ~= "table" or type(C_AddOns.GetAddOnMetadata) ~= "function" then
        return nil
    end
    local value = C_AddOns.GetAddOnMetadata(addonName, field)
    if type(value) == "string" and value:find("%S") then
        return value
    end
end

local function ReportLoaded(available)
    local banner = Metadata("Title") or DEFAULT_TITLE
    local version, author = Metadata("Version"), Metadata("Author")
    if version then
        banner = banner .. " " .. version
    end
    if author then
        banner = banner .. " by " .. author
    end
    WTF.Report(banner)
    if available then
        WTF.Report(READY_MESSAGE)
    end
end

-- Functions other runtime files must define. A mixed install of old and new
-- files otherwise fails silently, because the client hides Lua errors by default.
local REQUIRED_NAMESPACE = {
    "ParseCommand", "HandleCommand",
    "CheckShardCapabilities", "InitializeShards", "ReportShardStatus", "ReportShardDebug",
    "DebugDeleteShard", "RefreshShardCounter", "ResetShardCounterPosition",
    "CheckStoneCapabilities", "InitializeStones", "ResetStonesPosition", "ReportStoneDebug",
    "ReportStoneStatus", "RemindStones", "ApplyStoneMacros", "AddInputHandler", "RunOnNextInput", "ReportClickDebug",
    "InitializeAnnounce", "FormatAnnouncement", "ReportAnnounceDebug", "DebugEmote", "FriendlyTargetNames",
    "WhisperHealthstoneGift",
    "CheckTrackerCapabilities", "InitializeTracker", "ResetTrackerPosition", "RefreshTracker",
    "ReportTrackerDebug", "TrackerCandidateFilters", "TrackerKnowsSlot", "SetTrackerTheme",
    "InitializePlateDots", "RefreshPlateDots", "HasTrackableDots", "ApplyTrackerColors", "ApplyDotColors",
    "InitializeAlerts", "ApplyNightfallSound", "PreviewNightfallSound", "HasNightfallSound",
    "ReportRestrictions",
    "InitializeOptions", "OpenSettings",
}

local function CheckInstalledFiles()
    for _, name in ipairs(REQUIRED_NAMESPACE) do
        if type(WTF[name]) ~= "function" then
            return false, "AddOn files are from different versions (missing " .. name
                .. "). Reinstall every Warlock Tools Forever file, then restart the client."
        end
    end
    return true
end

local function CheckClass()
    local _, classFile = UnitClass("player")
    if classFile ~= "WARLOCK" then
        return false, "Warlock Tools Forever is for Warlocks, so it stays off on this character."
    end
    return true
end

-- Per-character settings in WarlockToolsForeverDB, repaired on load so a
-- damaged or older table can never break the AddOn.
WTF.SHARD_LIMIT_MIN = 1
WTF.SHARD_LIMIT_MAX = 60
WTF.DEFAULT_SHARD_LIMIT = 6
-- The shard counter turns red at or below this. Two by default: one
-- Soulstone, one Healthstone, and one summon take three shards.
WTF.SHARD_LOW_MIN = 0
WTF.SHARD_LOW_MAX = 10
WTF.DEFAULT_SHARD_LOW = 2

local function IsWholeNumber(value)
    return type(value) == "number" and value == math.floor(value)
end

function WTF.SanitizeShardLimit(value)
    if not IsWholeNumber(value) then
        return WTF.DEFAULT_SHARD_LIMIT
    end
    return math.max(WTF.SHARD_LIMIT_MIN, math.min(WTF.SHARD_LIMIT_MAX, value))
end

function WTF.SanitizeShardLow(value)
    if not IsWholeNumber(value) then
        return WTF.DEFAULT_SHARD_LOW
    end
    return math.max(WTF.SHARD_LOW_MIN, math.min(WTF.SHARD_LOW_MAX, value))
end

-- Chat messages longer than this are cut by the client.
WTF.ANNOUNCE_MAX_LENGTH = 255

-- The default texts credit WTF (author-approved), so players you group with
-- can find it; a text you edit says only what you wrote.
WTF.ANNOUNCE_CREDIT = " - via Warlock Tools Forever (WTF)"
WTF.ANNOUNCE_DEFAULTS = {
    summonGroupText = "The ritual hungers! Click the portal to drag >> %T << through the Twisting Nether" .. WTF.ANNOUNCE_CREDIT,
    soulstoneGroupText = "A piece of >> %T <<'s soul now rests in my keeping. Death is merely an inconvenience" .. WTF.ANNOUNCE_CREDIT,
    -- The author's texts, with their own credit; %Z leaves room for long zone names.
    summonWhisperText = "Summoning you to %Z, since your sloth-like pace would get you there sometime next week. Accept the summon when it pops up (and tell me if it doesn't). Courtesy of Warlock Tools Forever (WTF)",
    soulstoneWhisperText = "I've trapped a sliver of your soul in a stone. If you die, it drags you back to life right where you fell, so if you're going to die, die in a good spot. Courtesy of Warlock Tools Forever (WTF)",
    -- Emotes start with your name: "Dyre crushes a Soul Shard ...".
    healthstoneEmoteText = "crushes a Soul Shard and forges a Healthstone from the screaming essence within. - via Warlock Tools Forever (WTF)",
    soulstoneEmoteText = "binds a captured soul into a Soulstone. Someone's afterlife just got an escape hatch. - via Warlock Tools Forever (WTF)",
    healthstoneWhisperText = "Here, have a Healthstone. Some poor creature's essence gives you more health! Courtesy of Warlock Tools Forever (WTF)",
}
-- Saved copies of earlier defaults, never edited, become the new ones.
local OLD_ANNOUNCE_DEFAULTS = {
    summonGroupText = {"Summoning >> %T << click please", "Summoning >> %T << click please - via Warlock Tools Forever (WTF)"},
    summonWhisperText = {"Summoning you to %Z now. Watch for the summon prompt and accept it. If it doesn't appear, tell me.", "Summoning you to %Z now. Watch for the summon prompt and accept it. If it doesn't appear, tell me. - via Warlock Tools Forever (WTF)"},
    soulstoneGroupText = {"Soulstone on >> %T <<", "Soulstone on >> %T << - via Warlock Tools Forever (WTF)"},
    soulstoneWhisperText = {"I've applied a soulstone to you, this means if you die, you can revive yourself where you fell. So, if you're going to die, die in a good spot.", "I've applied a soulstone to you, this means if you die, you can revive yourself where you fell. So, if you're going to die, die in a good spot. - via Warlock Tools Forever (WTF)"},
    healthstoneWhisperText = {"Enjoy the Healthstone, %T! Use it when your health runs low. - via Warlock Tools Forever (WTF)"},
}

local function IsOldDefault(key, text)
    for _, old in ipairs(OLD_ANNOUNCE_DEFAULTS[key] or {}) do
        if text == old then
            return true
        end
    end
    return false
end

local function SanitizePosition(position)
    if type(position) ~= "table" or type(position.point) ~= "string"
        or type(position.relativePoint) ~= "string"
        or type(position.x) ~= "number" or type(position.y) ~= "number" then
        return nil
    end
    return {point = position.point, relativePoint = position.relativePoint,
        x = position.x, y = position.y}
end

-- Announcement text: a non-empty line within the chat limit, else the default.
function WTF.SanitizeAnnouncement(text, default)
    if type(text) ~= "string" then
        return default
    end
    text = text:match("^%s*(.-)%s*$")
    if text == "" or #text > WTF.ANNOUNCE_MAX_LENGTH or text:find("[\r\n]") then
        return default
    end
    return text
end

-- Tracker and nameplate slots, in display order, with default colors as the
-- Settings color swatch stores them (AARRGGBB) and whether each shows as a
-- nameplate dot by default. Crowd control is not a DoT to keep up.
WTF.DOT_SLOTS = {
    {key = "curse", label = "Curse", color = "ff9e40d9", plate = true},
    {key = "bane", label = "Bane", color = "ffe62626", plate = true},
    {key = "corruption", label = "Corruption", color = "ffffffff", plate = true},
    {key = "immolate", label = "Immolate", color = "ffff8019", plate = true},
    {key = "siphon", label = "Siphon Life", color = "ff4dd94d", plate = true},
    {key = "control", label = "Fear and control", color = "ffffd91a", plate = false},
}

-- Defaults that changed (author-approved): once, a slot still on its old
-- default moves to the new one; a color the user picked stays, also later.
local OLD_DEFAULT_COLORS = {curse = "ff4d8cff", corruption = "ff9e40d9"}
local COLORS_VERSION = 2

function WTF.SanitizeColor(value, default)
    if type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") then
        return value:lower()
    end
    return default
end

-- A slot's saved color as r, g, b from 0 to 1.
function WTF.SlotColor(key)
    local hex = WTF.db.tracker.colors[key]
    return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

WTF.PLATE_DOTS_OFFSET_MIN = 0
WTF.PLATE_DOTS_OFFSET_MAX = 120
-- Clears the name and EllesmereUI's debuff icons above it (author-tested in client:
-- 4 covered the name, 40 the icons, 50 cleared both).
WTF.DEFAULT_PLATE_DOTS_OFFSET = 50

function WTF.SanitizePlateDotsOffset(value)
    if not IsWholeNumber(value) then
        return WTF.DEFAULT_PLATE_DOTS_OFFSET
    end
    return math.max(WTF.PLATE_DOTS_OFFSET_MIN, math.min(WTF.PLATE_DOTS_OFFSET_MAX, value))
end

-- Nightfall sound choices (Alerts): demon chirps and laughs by file ID, from
-- the game's sound files as Leatrix Sounds lists them for this client
-- (sound/creature/demonfelimp and hellish_imp), and three interface sounds by
-- path. A number is a file ID, a string a file path.
WTF.NIGHTFALL_SOUNDS = {
    {key = "implaugh1", label = "Imp laugh 1", file = 639142},
    {key = "implaugh2", label = "Imp laugh 2", file = 639144},
    {key = "implaugh3", label = "Imp laugh 3", file = 639146},
    {key = "implaugh4", label = "Imp laugh 4", file = 639148},
    {key = "implaugh5", label = "Imp laugh 5", file = 639150},
    {key = "implaugh6", label = "Imp laugh 6", file = 639152},
    {key = "implaugh7", label = "Imp laugh 7", file = 639154},
    {key = "impfunny", label = "Imp chuckle", file = 639140},
    {key = "impattack1", label = "Imp attack chirp 1", file = 639100},
    {key = "impattack2", label = "Imp attack chirp 2", file = 639104},
    {key = "impspell", label = "Imp spell chirp", file = 639156},
    {key = "hellishimp1", label = "Hellish imp 1", file = 1281685},
    {key = "hellishimp2", label = "Hellish imp 2", file = 1281691},
    {key = "raidwarning", label = "Raid warning", file = "Sound\\Interface\\RaidWarning.ogg"},
    {key = "readycheck", label = "Ready check", file = "Sound\\Interface\\ReadyCheck.ogg"},
    {key = "alarm", label = "Alarm clock", file = "Sound\\Interface\\AlarmClockWarning3.ogg"},
}
-- The author's pick after auditioning; players audition the rest.
WTF.DEFAULT_NIGHTFALL_SOUND = "impspell"

local ANNOUNCE_SWITCHES = {"summonGroup", "summonWhisper", "soulstoneGroup", "soulstoneWhisper",
    "healthstoneWhisper", "healthstoneEmote", "soulstoneEmote"}

function WTF.SanitizeDB(db)
    if type(db) ~= "table" then
        db = {}
    end
    local shards = type(db.shards) == "table" and db.shards or {}
    db.shards = {
        enabled = shards.enabled ~= false,
        autoLimit = shards.autoLimit ~= false,
        limit = WTF.SanitizeShardLimit(shards.limit),
        report = shards.report ~= false,
        counter = shards.counter ~= false,
        counterLocked = shards.counterLocked == true,
        counterLow = WTF.SanitizeShardLow(shards.counterLow),
        counterPosition = SanitizePosition(shards.counterPosition),
    }
    local stones = type(db.stones) == "table" and db.stones or {}
    local soulstone = type(stones.soulstone) == "table" and stones.soulstone or nil
    db.stones = {
        enabled = stones.enabled ~= false,
        shown = stones.shown ~= false,
        locked = stones.locked == true,
        position = SanitizePosition(stones.position),
        macros = stones.macros ~= false,
        remindSoulstone = stones.remindSoulstone ~= false,
        remindHealthstone = stones.remindHealthstone ~= false,
        soulstone = soulstone and type(soulstone.name) == "string" and type(soulstone.ends) == "number"
            and {name = soulstone.name, ends = soulstone.ends} or nil,
    }
    local tracker = type(db.tracker) == "table" and db.tracker or {}
    db.tracker = {
        enabled = tracker.enabled ~= false,
        placeholders = tracker.placeholders == true,
        locked = tracker.locked == true,
        position = SanitizePosition(tracker.position),
        -- Bars by default (author-approved).
        theme = tracker.theme == "compact" and "compact" or "bars",
        plateDots = tracker.plateDots == true,
        plateDotsOffset = WTF.SanitizePlateDotsOffset(tracker.plateDotsOffset),
        colors = {},
        onPlates = {},
        colorsVersion = COLORS_VERSION,
    }
    for _, key in ipairs({"lastBane", "lastCurse", "lastControl"}) do
        db.tracker[key] = type(tracker[key]) == "string" and tracker[key] or nil
    end
    local colors = type(tracker.colors) == "table" and tracker.colors or {}
    local onPlates = type(tracker.onPlates) == "table" and tracker.onPlates or {}
    for _, slot in ipairs(WTF.DOT_SLOTS) do
        local color = WTF.SanitizeColor(colors[slot.key], slot.color)
        if (tracker.colorsVersion or 1) < COLORS_VERSION and color == OLD_DEFAULT_COLORS[slot.key] then
            color = slot.color
        end
        db.tracker.colors[slot.key] = color
        if type(onPlates[slot.key]) == "boolean" then
            db.tracker.onPlates[slot.key] = onPlates[slot.key]
        else
            db.tracker.onPlates[slot.key] = slot.plate
        end
    end
    local alerts = type(db.alerts) == "table" and db.alerts or {}
    local sound = WTF.DEFAULT_NIGHTFALL_SOUND
    for _, choice in ipairs(WTF.NIGHTFALL_SOUNDS) do
        if choice.key == alerts.nightfallSound then
            sound = choice.key
        end
    end
    db.alerts = {nightfall = alerts.nightfall == true, nightfallSound = sound}
    local announce = type(db.announce) == "table" and db.announce or {}
    local cleanAnnounce = {
        enabled = announce.enabled ~= false,
        channel = announce.channel == "say" and "say" or "group",
    }
    for _, key in ipairs(ANNOUNCE_SWITCHES) do
        cleanAnnounce[key] = announce[key] ~= false
    end
    for key, default in pairs(WTF.ANNOUNCE_DEFAULTS) do
        local text = announce[key]
        if IsOldDefault(key, text) then
            text = default
        end
        cleanAnnounce[key] = WTF.SanitizeAnnouncement(text, default)
    end
    db.announce = cleanAnnounce
    return db
end

-- Another AddOn can register the same slash command; the last one loaded wins.
-- Returns the other command key, or nil when /wtf is ours alone.
local function FindSlashConflict()
    for key in pairs(SlashCmdList) do
        if key ~= SLASH_KEY then
            for index = 1, MAX_SLASH_ALIASES do
                local alias = _G["SLASH_" .. key .. index]
                if type(alias) == "string" and alias:lower() == PRIMARY_SLASH then
                    return key
                end
            end
        end
    end
end

-- Hardware input. The client lets AddOns delete or move items only during a
-- key press or click, so such work waits for the next one. Core hooks every
-- key press and every click on the game world, as RestedXP does for its junk
-- deletion; the keyboard frame passes every key on to the game and is enabled
-- only after the client confirms that.
local inputHandlers, nextInput = {}, {}

function WTF.AddInputHandler(handler)
    inputHandlers[#inputHandlers + 1] = handler
end

-- Runs once, at the next key press or click.
function WTF.RunOnNextInput(action)
    nextInput[#nextInput + 1] = action
end

local function OnInput()
    for _, handler in ipairs(inputHandlers) do
        handler()
    end
    if #nextInput > 0 then
        local actions = nextInput
        nextInput = {}
        for _, action in ipairs(actions) do
            action()
        end
    end
end

local function InstallInputHooks()
    local keys = CreateFrame("Frame", nil, UIParent)
    if type(keys.SetPropagateKeyboardInput) == "function"
        and type(keys.GetPropagateKeyboardInput) == "function" then
        keys:SetPropagateKeyboardInput(true)
        if keys:GetPropagateKeyboardInput() then
            keys:SetScript("OnKeyDown", OnInput)
            keys:EnableKeyboard(true)
        end
    end
    WorldFrame:HookScript("OnMouseDown", OnInput)
end

-- /wtf reset: the Stones bar and the DoT tracker back to their default places.
function WTF.ResetPositions()
    WTF.ResetShardCounterPosition()
    WTF.ResetStonesPosition()
    WTF.ResetTrackerPosition()
end

SLASH_WARLOCKTOOLSFOREVER1 = PRIMARY_SLASH
SLASH_WARLOCKTOOLSFOREVER2 = BACKUP_SLASH
SlashCmdList[SLASH_KEY] = WTF.HandleCommand

local function LoadDB()
    WarlockToolsForeverDB = WTF.SanitizeDB(WarlockToolsForeverDB)
    WTF.db = WarlockToolsForeverDB
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, loadedName)
    if event == "ADDON_LOADED" then
        if loadedName == addonName then
            self:UnregisterEvent("ADDON_LOADED")
            LoadDB()
        end
        return
    end
    self:UnregisterEvent("PLAYER_LOGIN")
    if not WTF.db then
        LoadDB()
    end
    local available, message = CheckInstalledFiles()
    if available then
        available, message = CheckClass()
    end
    if available then
        available, message = WTF.CheckShardCapabilities()
    end
    WTF.available = available
    ReportLoaded(available)
    local conflict = FindSlashConflict()
    if conflict then
        WTF.Report("Another AddOn (" .. conflict .. ") also uses " .. PRIMARY_SLASH
            .. ". Use " .. BACKUP_SLASH .. " instead.")
    end
    if not available then
        WTF.Report(message)
        return
    end
    -- Called directly rather than from each file's own PLAYER_LOGIN handler,
    -- so startup never depends on event handler order.
    InstallInputHooks()
    WTF.InitializeShards()
    WTF.InitializeStones()
    WTF.InitializeAnnounce()
    WTF.InitializeTracker()
    WTF.InitializePlateDots()
    WTF.InitializeAlerts()
    WTF.InitializeOptions()
end)
