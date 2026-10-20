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

-- Sounds come from the library AddOn Dyre's Sounds (author-approved: one copy
-- of the sound files for all of Dyre's AddOns). The TOC lists it as
-- OptionalDeps, so it loads first when installed, and WTF still loads and
-- works without it, playing no sounds.
local SOUNDS_CONTRACT = 1
local SOUNDS_FUNCTIONS = {"Resolve", "Label", "List", "Groups", "Play", "AuraSound", "Choices", "SetupMenu"}
-- Dyre's Sounds is unlisted on CurseForge, so the message says where to get it.
local SOUNDS_WHERE = " Get it from CurseForge."
local SOUNDS_MESSAGES = {
    missing = "Install Dyre's Sounds to hear WTF's sounds (the chimes, the Nightfall sound, and the shield "
        .. "sound)." .. SOUNDS_WHERE,
    old = "Update Dyre's Sounds to hear WTF's sounds. This version is too old for WTF."
        .. SOUNDS_WHERE,
}

-- Dyre's Sounds with the contract and functions WTF uses, else nil and why.
function WTF.SoundLibrary()
    local library = rawget(_G, "DyresSounds")
    if type(library) ~= "table" or type(library.RequireContract) ~= "function" then
        return nil, "missing"
    end
    library = library.RequireContract(SOUNDS_CONTRACT)
    if type(library) ~= "table" then
        return nil, "old"
    end
    for _, name in ipairs(SOUNDS_FUNCTIONS) do
        if type(library[name]) ~= "function" then
            return nil, "old"
        end
    end
    return library, "ok"
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

-- Says once per session what to install when a sound is wanted but missing.
local soundsReported = false

function WTF.ReportMissingSounds()
    local library, state = WTF.SoundLibrary()
    if library or soundsReported then
        return
    end
    soundsReported = true
    WTF.Report(SOUNDS_MESSAGES[state])
end

-- Dyre's Buff Reminders plays the chimes when it is installed (author-
-- approved; it took in Dyre's Cooldown Chimes, never released, which then
-- plays them instead while still installed), so WTF plays none; WTF's chime
-- settings stay as they are, since the other AddOn copies them on its first
-- run. The first one loaded is the one that plays.
WTF.CHIMES_ADDONS = {
    {addon = "DyresCooldownChimes", title = "Dyre's Cooldown Chimes", slash = "/dcc"},
    {addon = "DyresBuffReminders", title = "Dyre's Buff Reminders", slash = "/dbr"},
}

-- Dyre's Buff Reminders shows buff reminders for every class (author-approved
-- two-step move): while it is loaded, WTF's own reminder icons stay hidden and
-- WTF's saved reminder settings stay as they are.
function WTF.RemindersStandAside()
    if type(C_AddOns) ~= "table" or type(C_AddOns.IsAddOnLoaded) ~= "function" then
        return false
    end
    local loaded = C_AddOns.IsAddOnLoaded("DyresBuffReminders")
    return loaded == true
end

-- The stand-alone Dyre's AddOn wins when it is installed (author-approved rule
-- for every shared feature): while Dyre's Shields Up is loaded, WTF starts no
-- shield display of its own and its shield settings stay as they are.
function WTF.ShieldStandAside()
    if type(C_AddOns) ~= "table" or type(C_AddOns.IsAddOnLoaded) ~= "function" then
        return false
    end
    local loaded = C_AddOns.IsAddOnLoaded("DyresShieldsUp")
    return loaded == true
end

-- The entry of WTF.CHIMES_ADDONS that plays the chimes, or nil when WTF does.
function WTF.ChimesStandAside()
    if type(C_AddOns) ~= "table" or type(C_AddOns.IsAddOnLoaded) ~= "function" then
        return nil
    end
    for _, other in ipairs(WTF.CHIMES_ADDONS) do
        if C_AddOns.IsAddOnLoaded(other.addon) == true then
            return other
        end
    end
end

-- Dyre's Buff Reminders plays the Nightfall sound from 0.3.0 on (its Proc
-- Sounds; author-approved), so WTF registers none; WTF's Nightfall settings
-- stay as they are, since DBR copies them on its first run. Older DBR has no
-- Nightfall sound, so its version is checked.
WTF.NIGHTFALL_ADDON = {addon = "DyresBuffReminders", title = "Dyre's Buff Reminders", slash = "/dbr",
    from = {0, 3, 0}}

-- Whether another AddOn's TOC version (major.minor.patch) is at least `from`.
-- A version that cannot be read counts as older.
local function VersionAtLeast(addon, from)
    if type(C_AddOns.GetAddOnMetadata) ~= "function" then
        return false
    end
    local version = C_AddOns.GetAddOnMetadata(addon, "Version")
    local major, minor, patch = (type(version) == "string" and version or ""):match("^(%d+)%.(%d+)%.(%d+)")
    if not major then
        return false
    end
    local found = {tonumber(major), tonumber(minor), tonumber(patch)}
    for index = 1, 3 do
        if found[index] ~= from[index] then
            return found[index] > from[index]
        end
    end
    return true
end

-- WTF.NIGHTFALL_ADDON when it is loaded and plays the Nightfall sound, else nil.
function WTF.NightfallStandAside()
    local other = WTF.NIGHTFALL_ADDON
    if type(C_AddOns) ~= "table" or type(C_AddOns.IsAddOnLoaded) ~= "function"
        or C_AddOns.IsAddOnLoaded(other.addon) ~= true then
        return nil
    end
    return VersionAtLeast(other.addon, other.from) and other or nil
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
    "InitializeReminders", "RefreshReminders", "ResetRemindersPosition", "ReportRemindersDebug",
    "SanitizeReminders", "SendGroupAnnouncement", "CharacterMacrosAvailable", "WriteCharacterMacro",
    "DeleteCharacterMacro", "ApplyControlMacros",
    "InitializeControl", "RefreshControl", "ResetControlPosition", "ReportControlDebug", "SanitizeControl", "InitializeAnnounce", "FormatAnnouncement", "ReportAnnounceDebug", "DebugEmote", "FriendlyTargetNames",
    "WhisperHealthstoneGift",
    "CheckTrackerCapabilities", "InitializeTracker", "ResetTrackerPosition", "RefreshTracker",
    "ReportTrackerDebug", "TrackerCandidateFilters", "TrackerKnowsSlot", "SetTrackerTheme",
    "InitializePlateDots", "RefreshPlateDots", "HasTrackableDots", "ApplyTrackerColors", "ApplyDotColors",
    "InitializeAlerts", "ApplyNightfallSound", "PreviewNightfallSound", "HasNightfallSound",
    "InitializeChimes", "PreviewChime", "ReportChimesDebug", "SanitizeChimes", "SanitizeChimeSound",
    "ReportRestrictions", "InitializeShield", "RefreshShield", "ResetShieldPosition", "ReportShieldDebug",
    "InitializeOptions", "OpenSettings",
}

local function CheckInstalledFiles()
    if type(WTF.ShieldDisplay) ~= "table" or type(WTF.ShieldDisplay.Initialize) ~= "function" then
        return false, "AddOn files are from different versions (missing Shield.lua). Reinstall every "
            .. "Warlock Tools Forever file, then restart the client."
    end
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

-- The Nightfall sound (Alerts) is one of Dyre's Sounds' aura sounds: a file
-- (Dyre's Picks) or a game sound by file ID (the imp chirps). The game's aura
-- sounds take only sound files, not sound kits. The default is the author's
-- pick after auditioning, Imp: Spell chirp.
WTF.DEFAULT_NIGHTFALL_SOUND = "impspell"

-- A saved Nightfall sound in the library's spelling when it can be an aura
-- sound (the library maps the "pick..." keys WTF saved), else the default.
-- Without the library a saved key is kept, so a missing library never resets
-- a choice.
function WTF.SanitizeNightfallSound(key)
    if type(key) ~= "string" then
        return WTF.DEFAULT_NIGHTFALL_SOUND
    end
    local library = WTF.SoundLibrary()
    if not library then
        return key
    end
    local resolved = library.Resolve(key)
    return resolved and library.AuraSound(resolved) and resolved or WTF.DEFAULT_NIGHTFALL_SOUND
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
    db.alerts = {nightfall = alerts.nightfall == true,
        nightfallSound = WTF.SanitizeNightfallSound(alerts.nightfallSound)}
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
    if WTF.SanitizeChimes then
        db.chimes = WTF.SanitizeChimes(db.chimes)
    end
    if WTF.SanitizeReminders then
        db.reminders = WTF.SanitizeReminders(db.reminders, SanitizePosition)
    end
    if WTF.SanitizeControl then
        db.control = WTF.SanitizeControl(db.control, SanitizePosition)
    end
    -- The shield display is a self-contained component; it owns its defaults.
    if WTF.ShieldDisplay then
        db.shield = WTF.ShieldDisplay.Sanitize(db.shield)
    end
    db.locked = db.locked ~= false
    db.grid = db.grid ~= false
    if type(db.shield) == "table" then
        db.shield.locked = db.locked
    end
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
-- The shield display (Shield.lua) is a component MTF ships too; WTF hands it
-- WTF's settings and chat, and it decides whether this copy draws. With both
-- AddOns installed, one display shows, from the newest copy.
function WTF.InitializeShield()
    -- Not even a candidate in the display's election: Dyre's Shields Up draws it.
    if WTF.ShieldStandAside() then
        return
    end
    -- With Dyre's Toolkit the ring drags, snaps, and saves through its layout;
    -- without it the ring moves freely, as before.
    local toolkit = WTF.toolkit
    WTF.ShieldDisplay.Initialize({settings = function() return WTF.db.shield end, report = WTF.Report,
        unlockHint = "Drag to move · /wtf lock when done", missingSounds = WTF.ReportMissingSounds,
        layout = toolkit and {register = toolkit.RegisterMovable, beginDrag = toolkit.BeginDrag,
            endDrag = toolkit.EndDrag} or nil})
end

function WTF.RefreshShield()
    WTF.ShieldDisplay.Refresh()
    WTF.ShieldDisplay.ApplyBreakSound()
end

function WTF.ResetShieldPosition()
    WTF.ShieldDisplay.ResetPosition()
end

function WTF.ReportShieldDebug()
    WTF.ShieldDisplay.ReportDebug(WTF.Report)
end

local function SetLockFlags(locked)
    WTF.db.locked = locked
    WTF.db.stones.locked = locked
    WTF.db.tracker.locked = locked
    WTF.db.tracker.placeholders = not locked
    WTF.db.shards.counterLocked = locked
    WTF.db.shield.locked = locked
end

-- quiet: Dyre's Toolkit locks every Dyre's AddOn and says one line for all.
function WTF.SetFramesLocked(locked, quiet)
    SetLockFlags(locked)
    WTF.RefreshTracker()
    WTF.RefreshStonesMover()
    WTF.RefreshShardCounter()
    WTF.RefreshShield()
    WTF.RefreshReminders()
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
    WTF.ResetShieldPosition()
    WTF.ResetRemindersPosition()
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
    if (WTF.db.chimes.enabled and not WTF.ChimesStandAside())
            or (WTF.db.alerts.nightfall and not WTF.NightfallStandAside()) then
        WTF.ReportMissingSounds()
    end
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
    WTF.InitializeAlerts()
    WTF.InitializeShield()
    WTF.InitializeChimes()
    WTF.InitializeReminders()
    WTF.InitializeOptions()
    JoinToolkit()
    WTF.RefreshGrid()
end)
