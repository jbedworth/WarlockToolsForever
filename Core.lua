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

-- An action that failed: said in chat and in red at the top of the screen,
-- so a click never fails silently (author-approved, as MTF does).
local WARNING_COLOR = {1, 0.1, 0.1}

function WTF.Warn(message)
    WTF.Report(message)
    if type(UIErrorsFrame) == "table" and type(UIErrorsFrame.AddMessage) == "function" then
        UIErrorsFrame:AddMessage("WTF: " .. tostring(message), WARNING_COLOR[1], WARNING_COLOR[2], WARNING_COLOR[3])
    end
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

-- When the client refuses AddOn item moves and deletion, also from a key
-- press (found in client: DeleteCursorItem raised ADDON_ACTION_BLOCKED in a
-- dungeon, BugGrabber 6x): in combat, while the player affects combat (a secret
-- answer counts), or under a Combat, Encounter, ChallengeMode, PvPMatch, or
-- Map AddOn restriction. Shard deletion and the Healthstone trade check it at
-- each call and wait instead.
local MOVE_RESTRICTIONS = {"Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map"}

function WTF.MoveRestricted()
    if InCombatLockdown() then
        return true
    end
    if type(UnitAffectingCombat) == "function" then
        local affecting = UnitAffectingCombat("player")
        if WTF.IsSecret(affecting) or affecting then
            return true
        end
    end
    local kinds = type(Enum) == "table" and Enum.AddOnRestrictionType
    if type(C_RestrictedActions) ~= "table" or type(C_RestrictedActions.IsAddOnRestrictionActive) ~= "function"
        or type(kinds) ~= "table" then
        return false
    end
    for _, name in ipairs(MOVE_RESTRICTIONS) do
        if kinds[name] ~= nil and C_RestrictedActions.IsAddOnRestrictionActive(kinds[name]) == true then
            return true
        end
    end
    return false
end

-- Dyre's Toolkit (author-approved, 2026-10-19): one layout mode, grid, and
-- settings home for every Dyre's AddOn, and frames that snap across AddOns.
-- The TOC lists it as OptionalDeps, so it loads first when installed; without
-- it WTF keeps its own Layout.lua, grid, and top-level settings page.
local TOOLKIT_CONTRACT = 1
local TOOLKIT_FUNCTIONS = {"RegisterAddOn", "RegisterSettingsCategory", "RegisterMovable", "BeginDrag",
    "EndDrag", "ScaleKeepingCenter", "IsLocked", "Lock", "Unlock", "OpenSettings"}
local TOOLKIT_MESSAGES = {
    missing = "Install Dyre's Toolkit from CurseForge for one layout mode and settings home for all Dyre's AddOns.",
    old = "Update Dyre's Toolkit from CurseForge: this version is too old for WTF, so WTF uses its own layout.",
}

-- Dyre's Toolkit with the contract and functions WTF uses, else nil and why.
function WTF.Toolkit()
    local toolkit = rawget(_G, "DyresToolkit")
    if type(toolkit) ~= "table" or type(toolkit.RequireContract) ~= "function" then
        return nil, "missing"
    end
    toolkit = toolkit.RequireContract(TOOLKIT_CONTRACT)
    if type(toolkit) ~= "table" then
        return nil, "old"
    end
    for _, name in ipairs(TOOLKIT_FUNCTIONS) do
        if type(toolkit[name]) ~= "function" then
            return nil, "old"
        end
    end
    return toolkit, "ok"
end

-- Features that moved out of WTF in 1.3.0 (author-approved): the shield
-- display to Dyre's Shields Up; the cooldown chimes, the Nightfall sound,
-- and the Demon Armor reminder to Dyre's Buff Reminders. CurseForge lists both
-- as required, so the app installs them; the TOC keeps them optional, so WTF
-- loads without them and says once per session, at login, what to install
-- or enable (CurseForge only).
WTF.MOVED_TO = {
    {addon = "DyresShieldsUp", title = "Dyre's Shields Up", what = "the shield display"},
    {addon = "DyresBuffReminders", title = "Dyre's Buff Reminders",
        what = "the cooldown chimes, the Nightfall sound, and the Demon Armor reminder"},
}

-- "loaded", "disabled" (installed but not enabled), or "missing".
local function AddOnState(addon)
    if type(C_AddOns) ~= "table" then
        return "missing"
    end
    if type(C_AddOns.IsAddOnLoaded) == "function" and C_AddOns.IsAddOnLoaded(addon) == true then
        return "loaded"
    end
    if type(C_AddOns.GetAddOnInfo) == "function" then
        local name, _, _, _, reason = C_AddOns.GetAddOnInfo(addon)
        if type(name) == "string" and reason ~= "MISSING" then
            return "disabled"
        end
    end
    return "missing"
end

function WTF.ReportMovedFeatures()
    for _, other in ipairs(WTF.MOVED_TO) do
        local state = AddOnState(other.addon)
        if state == "disabled" then
            WTF.Report("Enable " .. other.title .. " in the AddOn list for " .. other.what
                .. ": it moved there from WTF.")
        elseif state == "missing" then
            WTF.Report("Install " .. other.title .. " from CurseForge for " .. other.what
                .. ": it moved there from WTF.")
        end
    end
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
    "CheckStoneCapabilities", "InitializeStones", "ResetStonesPosition", "ReportStoneDebug", "RefreshStonesMover",
    "ReportStoneStatus", "RemindStones", "ApplyStoneMacros", "AddInputHandler", "RunOnNextInput", "ReportClickDebug",
    "Warn", "RegisterMovable", "BeginDrag", "EndDrag", "ScaleKeepingCenter",
    "SendGroupAnnouncement", "CharacterMacrosAvailable", "WriteCharacterMacro",
    "DeleteCharacterMacro", "ApplyControlMacros",
    "InitializeControl", "RefreshControl", "ResetControlPosition", "ReportControlDebug", "SanitizeControl", "InitializeAnnounce", "FormatAnnouncement", "ReportAnnounceDebug", "DebugEmote", "FriendlyTargetNames",
    "WhisperHealthstoneGift",
    "CheckTrackerCapabilities", "InitializeTracker", "ResetTrackerPosition", "RefreshTracker",
    "ReportTrackerDebug", "TrackerCandidateFilters", "TrackerKnowsSlot", "SetTrackerTheme",
    "InitializePlateDots", "RefreshPlateDots", "HasTrackableDots", "ApplyTrackerColors", "ApplyDotColors",
    "ReportRestrictions", "InitializeOptions", "OpenSettings",
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
    -- Control (author-approved): %T the mob, %M its raid marker in chat.
    fearGroupText = "Fearing >> %T <<. Let it run; chase it and you bring friends" .. WTF.ANNOUNCE_CREDIT,
    banishGroupText = "Banishing >> %T << %M to the Twisting Nether. Hands off until it comes back" .. WTF.ANNOUNCE_CREDIT,
    enslaveGroupText = "Enslaving >> %T <<. It works for me now; leave my new pet alone" .. WTF.ANNOUNCE_CREDIT,
    howlGroupText = "Howl of Terror! Everything nearby is about to run screaming" .. WTF.ANNOUNCE_CREDIT,
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
-- Settings color swatch stores them (AARRGGBB), and whether each is a DoT to
-- keep up (crowd control is not). Every slot shows as a nameplate dot by
-- default (author, 1.2.0).
WTF.DOT_SLOTS = {
    {key = "curse", label = "Curse", color = "ff9e40d9", dot = true},
    {key = "bane", label = "Bane", color = "ffe62626", dot = true},
    {key = "corruption", label = "Corruption", color = "ffffffff", dot = true},
    {key = "immolate", label = "Immolate", color = "ffff8019", dot = true},
    {key = "siphon", label = "Siphon Life", color = "ff4dd94d", dot = true},
    {key = "control", label = "Fear and control", color = "ffffd91a", dot = false},
}

-- The DoT order (author-approved, player request: configurable, with the
-- rotation order above as the default): every slot key once. Unknown or
-- doubled keys are dropped and missing ones added in the default order.
function WTF.SanitizeDotOrder(value)
    local valid, seen, order = {}, {}, {}
    for _, slot in ipairs(WTF.DOT_SLOTS) do
        valid[slot.key] = true
    end
    if type(value) == "table" then
        for _, key in ipairs(value) do
            if valid[key] and not seen[key] then
                seen[key] = true
                order[#order + 1] = key
            end
        end
    end
    for _, slot in ipairs(WTF.DOT_SLOTS) do
        if not seen[slot.key] then
            order[#order + 1] = slot.key
        end
    end
    return order
end

-- WTF.DOT_SLOTS in the saved order.
function WTF.OrderedDotSlots()
    local byKey, slots = {}, {}
    for _, slot in ipairs(WTF.DOT_SLOTS) do
        byKey[slot.key] = slot
    end
    for _, key in ipairs(WTF.db.tracker.order) do
        slots[#slots + 1] = byKey[key]
    end
    return slots
end

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

-- A saved AARRGGBB color as r, g, b from 0 to 1 (its alpha is not used).
local function HexColor(hex)
    return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

function WTF.SlotColor(key)
    return HexColor(WTF.db.tracker.colors[key])
end

-- DoT tracker panel colors (author-approved, player request): each colors its
-- panel's outline or row border and its health fill. Defaults are the colors
-- before 1.2.0: the warlock class color, red, and the others' dark grey.
WTF.TRACKER_PANEL_COLORS = {
    {key = "target", label = "Target panel color", color = "ff8787ed"},
    {key = "focus", label = "Focus panel color", color = "ffe61a1a"},
    {key = "list", label = "Other mobs panel color", color = "ff545454"},
}

function WTF.PanelColor(key)
    return HexColor(WTF.db.tracker.panelColors[key])
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

-- A whole number within min and max, else the default.
function WTF.SanitizeWhole(value, minValue, maxValue, default)
    if not IsWholeNumber(value) then
        return default
    end
    return math.max(minValue, math.min(maxValue, value))
end

-- DoT tracker panel opacity, per panel (author-approved: its own setting for
-- the target, focus, and other-mobs panels), in percent; 100 is today's look.
WTF.TRACKER_PANELS = {
    {key = "target", heading = "Target", name = "target panel", label = "Target panel opacity"},
    {key = "focus", heading = "Focus", name = "focus panel", label = "Focus panel opacity"},
    {key = "list", heading = "Others", name = "other mobs' panel", label = "Other mobs panel opacity"},
}
WTF.PANEL_OPACITY_MIN = 10
WTF.PANEL_OPACITY_MAX = 100
WTF.DEFAULT_PANEL_OPACITY = 100

-- Nameplate DoT dot opacity, in percent (author-approved: 100, today's look).
WTF.PLATE_DOTS_OPACITY_MIN = 10
WTF.PLATE_DOTS_OPACITY_MAX = 100
WTF.DEFAULT_PLATE_DOTS_OPACITY = 100

-- DoT tracker sizes per theme (author-approved, player request), saved per
-- theme; the defaults are the sizes the themes always had. Text size is a
-- percent of each font's own size. No free offsets: the name sits in one of a
-- few places, so every layout is a tested one.
WTF.TRACKER_SIZE_SPECS = {
    compact = {
        {key = "iconSize", label = "Icon size", min = 16, max = 40, step = 1, default = 22},
        {key = "nameWidth", label = "Name width", min = 60, max = 200, step = 5, default = 110,
            tooltip = "The room the name has beside the icons (name Left or Right): the row grows or shrinks with "
                .. "it. A longer name is cut with \"...\". Above or below the icons, the name spans the row."},
        {key = "textScale", label = "Text size", min = 50, max = 200, step = 5, default = 100, percent = true},
    },
    bars = {
        {key = "barWidth", label = "Bar width", min = 150, max = 500, step = 10, default = 290},
        {key = "lineHeight", label = "Line height", min = 12, max = 28, step = 1, default = 16},
        {key = "textScale", label = "Text size", min = 50, max = 200, step = 5, default = 100, percent = true},
    },
}
WTF.TRACKER_NAME_POSITIONS = {
    compact = {{key = "left", label = "Left"}, {key = "right", label = "Right"}, {key = "above", label = "Above"},
        {key = "below", label = "Below"}},
    bars = {{key = "above", label = "Above"}, {key = "below", label = "Below"}},
}

-- The tracker's health text choices; None by default.
WTF.TRACKER_HEALTH_TEXTS = {{key = "none", label = "None"}, {key = "number", label = "Number"},
    {key = "percent", label = "Percent"}, {key = "both", label = "Number and Percent"}}

function WTF.SanitizeHealthText(value)
    for _, choice in ipairs(WTF.TRACKER_HEALTH_TEXTS) do
        if value == choice.key then
            return value
        end
    end
    return "none"
end

function WTF.SanitizeTrackerSizes(theme, saved)
    saved = type(saved) == "table" and saved or {}
    local sizes = {}
    for _, spec in ipairs(WTF.TRACKER_SIZE_SPECS[theme]) do
        sizes[spec.key] = WTF.SanitizeWhole(saved[spec.key], spec.min, spec.max, spec.default)
    end
    local positions = WTF.TRACKER_NAME_POSITIONS[theme]
    sizes.namePosition = positions[1].key
    for _, position in ipairs(positions) do
        if saved.namePosition == position.key then
            sizes.namePosition = position.key
        end
    end
    return sizes
end

local ANNOUNCE_SWITCHES = {"summonGroup", "summonWhisper", "soulstoneGroup", "soulstoneWhisper",
    "healthstoneWhisper", "healthstoneEmote", "soulstoneEmote", "fearGroup", "banishGroup", "enslaveGroup",
    "howlGroup"}

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
        counterLow = WTF.SanitizeShardLow(shards.counterLow),
        counterPosition = SanitizePosition(shards.counterPosition),
    }
    local stones = type(db.stones) == "table" and db.stones or {}
    local soulstone = type(stones.soulstone) == "table" and stones.soulstone or nil
    db.stones = {
        enabled = stones.enabled ~= false,
        shown = stones.shown ~= false,
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
        -- Where the one tracker frame was: sections not yet dragged stack there.
        position = SanitizePosition(tracker.position),
        sections = {},
        -- Bars by default (author-approved).
        theme = tracker.theme == "compact" and "compact" or "bars",
        plateDots = tracker.plateDots == true,
        plateDotsOffset = WTF.SanitizePlateDotsOffset(tracker.plateDotsOffset),
        plateDotsOpacity = WTF.SanitizeWhole(tracker.plateDotsOpacity, WTF.PLATE_DOTS_OPACITY_MIN,
            WTF.PLATE_DOTS_OPACITY_MAX, WTF.DEFAULT_PLATE_DOTS_OPACITY),
        sizes = {},
        panelOpacity = {},
        -- Mob health (author-approved, player request): off by default.
        health = tracker.health == true,
        healthText = WTF.SanitizeHealthText(tracker.healthText),
        colors = {},
        onPlates = {},
        colorsVersion = COLORS_VERSION,
        panelColors = {},
        order = WTF.SanitizeDotOrder(tracker.order),
    }
    for _, key in ipairs({"lastBane", "lastCurse", "lastControl"}) do
        db.tracker[key] = type(tracker[key]) == "string" and tracker[key] or nil
    end
    local sizes = type(tracker.sizes) == "table" and tracker.sizes or {}
    for theme in pairs(WTF.TRACKER_SIZE_SPECS) do
        db.tracker.sizes[theme] = WTF.SanitizeTrackerSizes(theme, sizes[theme])
    end
    local panelOpacity = type(tracker.panelOpacity) == "table" and tracker.panelOpacity or {}
    for _, panel in ipairs(WTF.TRACKER_PANELS) do
        db.tracker.panelOpacity[panel.key] = WTF.SanitizeWhole(panelOpacity[panel.key], WTF.PANEL_OPACITY_MIN,
            WTF.PANEL_OPACITY_MAX, WTF.DEFAULT_PANEL_OPACITY)
    end
    local sections = type(tracker.sections) == "table" and tracker.sections or {}
    for _, key in ipairs({"target", "focus", "list"}) do
        db.tracker.sections[key] = SanitizePosition(sections[key])
    end
    local panelColors = type(tracker.panelColors) == "table" and tracker.panelColors or {}
    for _, panel in ipairs(WTF.TRACKER_PANEL_COLORS) do
        db.tracker.panelColors[panel.key] = WTF.SanitizeColor(panelColors[panel.key], panel.color)
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
            db.tracker.onPlates[slot.key] = true
        end
    end
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
    -- One lock for every frame (author-approved, as MTF), locked by default;
    -- each frame reads its own copy, and the tracker shows its sample rows
    -- while unlocked, since it can only be dragged while it shows.
    -- db.shield, db.chimes, db.alerts, and db.reminders stay exactly as saved
    -- for one release (author-approved): Dyre's Shields Up and Dyre's Buff
    -- Reminders copy them once, and a downgrade still finds them.
    if WTF.SanitizeControl then
        db.control = WTF.SanitizeControl(db.control, SanitizePosition)
    end
    db.locked = db.locked ~= false
    db.grid = db.grid ~= false
    db.stones.locked = db.locked
    db.tracker.locked = db.locked
    db.tracker.placeholders = not db.locked
    db.shards.counterLocked = db.locked
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

-- While unlocked, a frame shows a gold outline and a hint (author-approved).
-- A plain child, so it can show and hide also in combat.
function WTF.CreateMover(frame)
    local mover = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    mover:SetPoint("TOPLEFT", -4, 4)
    mover:SetPoint("BOTTOMRIGHT", 4, -4)
    mover:SetBackdrop({edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14})
    mover:SetBackdropBorderColor(1, 0.82, 0)
    mover.hint = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mover.hint:SetPoint("BOTTOM", mover, "TOP", 0, 2)
    mover.hint:SetText("Drag to move · /wtf lock when done")
    mover:SetShown(not WTF.db.locked)
    return mover
end

-- While unlocked, an alignment grid over the screen (author-approved, as
-- MTF's): faint lines every GRID_SPACING from the center out, and the center
-- lines in red, so frames line up with the middle of the screen. Under every
-- frame, it takes no mouse. Rebuilt when the screen size or UI scale changes.
local GRID_SPACING = 32
local GRID_LINE = {1, 1, 1, 0.12}
local GRID_CENTER = {1, 0.2, 0.2, 0.7}
local grid

local function GridLine(vertical, offset, color, thickness)
    local line = grid:CreateTexture(nil, "BACKGROUND")
    line:SetColorTexture(color[1], color[2], color[3], color[4])
    if vertical then
        line:SetPoint("TOP", grid, "TOP", offset, 0)
        line:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
        line:SetWidth(thickness)
    else
        line:SetPoint("LEFT", grid, "LEFT", 0, offset)
        line:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
        line:SetHeight(thickness)
    end
    grid.lines[#grid.lines + 1] = line
end

local function BuildGrid()
    for _, line in ipairs(grid.lines) do
        line:Hide()
    end
    grid.lines = {}
    local halfWidth, halfHeight = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    for step = 1, math.floor(halfWidth / GRID_SPACING) do
        GridLine(true, step * GRID_SPACING, GRID_LINE, 1)
        GridLine(true, -step * GRID_SPACING, GRID_LINE, 1)
    end
    for step = 1, math.floor(halfHeight / GRID_SPACING) do
        GridLine(false, step * GRID_SPACING, GRID_LINE, 1)
        GridLine(false, -step * GRID_SPACING, GRID_LINE, 1)
    end
    GridLine(true, 0, GRID_CENTER, 2)
    GridLine(false, 0, GRID_CENTER, 2)
    grid.built = true
end

function WTF.RefreshGrid()
    -- With Dyre's Toolkit, its grid shows for every Dyre's AddOn.
    local wanted = not WTF.toolkit and not WTF.db.locked and WTF.db.grid
    if not grid then
        if not wanted then
            return
        end
        grid = CreateFrame("Frame", nil, UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid:EnableMouse(false)
        grid.lines = {}
        grid:SetScript("OnEvent", function() grid.built = false; WTF.RefreshGrid() end)
        grid:RegisterEvent("DISPLAY_SIZE_CHANGED")
        grid:RegisterEvent("UI_SCALE_CHANGED")
    end
    if wanted and not grid.built then
        BuildGrid()
    end
    grid:SetShown(wanted)
    WTF.grid = grid
end

-- /wtf unlock and /wtf lock, and the main page's "Unlock frames to move them":
-- every movable WTF frame together (author-approved, as MTF does).
local function SetLockFlags(locked)
    WTF.db.locked = locked
    WTF.db.stones.locked = locked
    WTF.db.tracker.locked = locked
    WTF.db.tracker.placeholders = not locked
    WTF.db.shards.counterLocked = locked
end

-- quiet: Dyre's Toolkit locks every Dyre's AddOn and says one line for all.
function WTF.SetFramesLocked(locked, quiet)
    SetLockFlags(locked)
    WTF.RefreshTracker()
    WTF.RefreshStonesMover()
    WTF.RefreshShardCounter()
    WTF.RefreshControl()
    WTF.RefreshGrid()
    if quiet then
        return
    end
    if locked then
        WTF.Report("All WTF frames locked.")
    else
        WTF.Report("All WTF frames unlocked: drag them where you want (Shift-drag moves a snapped group), "
            .. "then type /wtf lock.")
    end
end

-- With Dyre's Toolkit, one layout mode for every Dyre's AddOn: the toolkit
-- calls WTF.SetFramesLocked back, quietly.
function WTF.Unlock()
    if WTF.toolkit then
        WTF.toolkit.Unlock()
    else
        WTF.SetFramesLocked(false)
    end
end

function WTF.Lock()
    if WTF.toolkit then
        WTF.toolkit.Lock()
    else
        WTF.SetFramesLocked(true)
    end
end

-- Before any module registers a frame: with Dyre's Toolkit, its layout moves
-- WTF's frames (they snap to other Dyre's AddOns' frames and to its grid),
-- and WTF's lock follows the toolkit's (locked at login). Else Layout.lua's.
local function UseToolkit()
    local toolkit, state = WTF.Toolkit()
    WTF.toolkit = toolkit
    if not toolkit then
        WTF.Report(TOOLKIT_MESSAGES[state])
        return
    end
    WTF.RegisterMovable = toolkit.RegisterMovable
    WTF.BeginDrag = toolkit.BeginDrag
    WTF.EndDrag = toolkit.EndDrag
    WTF.ScaleKeepingCenter = toolkit.ScaleKeepingCenter
    SetLockFlags(toolkit.IsLocked() ~= false)
end

-- After the settings exist, so the toolkit's menu can open them.
local function JoinToolkit()
    if not WTF.toolkit then
        return
    end
    WTF.toolkit.RegisterAddOn({addon = addonName, title = DEFAULT_TITLE,
        setLocked = function(locked) WTF.SetFramesLocked(locked == true, true) end,
        openSettings = WTF.OpenSettings})
end

-- /wtf reset: the Stones bar, the DoT tracker, and the shard counter back to their default places.
function WTF.ResetPositions()
    WTF.ResetShardCounterPosition()
    WTF.ResetStonesPosition()
    WTF.ResetTrackerPosition()
    WTF.ResetControlPosition()
    if InCombatLockdown() then
        WTF.Report("WTF frames move back to their default places after combat.")
    end
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
    WTF.ReportMovedFeatures()
    -- Called directly rather than from each file's own PLAYER_LOGIN handler,
    -- so startup never depends on event handler order.
    UseToolkit()
    InstallInputHooks()
    WTF.InitializeShards()
    WTF.InitializeStones()
    WTF.InitializeAnnounce()
    WTF.InitializeTracker()
    WTF.InitializeControl()
    WTF.InitializePlateDots()
    WTF.InitializeOptions()
    JoinToolkit()
    WTF.RefreshGrid()
end)
