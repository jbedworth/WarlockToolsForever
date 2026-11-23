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
--
-- 1.12.2 (John: "Try delete under Map"): the hard part (combat and the first
-- four) and the Map part are separate, because a dungeon may set Map for the
-- whole visit and it is not known whether Map blocks DeleteCursorItem. Only the
-- right-click trim tries under Map alone; everything else waits as before.
local HARD_RESTRICTIONS = {"Combat", "Encounter", "ChallengeMode", "PvPMatch"}

local function RestrictionActive(name)
    local kinds = type(Enum) == "table" and Enum.AddOnRestrictionType
    if type(C_RestrictedActions) ~= "table" or type(C_RestrictedActions.IsAddOnRestrictionActive) ~= "function"
        or type(kinds) ~= "table" or kinds[name] == nil then
        return false
    end
    return C_RestrictedActions.IsAddOnRestrictionActive(kinds[name]) == true
end

function WTF.HardRestricted()
    if InCombatLockdown() then
        return true
    end
    if type(UnitAffectingCombat) == "function" then
        local affecting = UnitAffectingCombat("player")
        if WTF.IsSecret(affecting) or affecting then
            return true
        end
    end
    for _, name in ipairs(HARD_RESTRICTIONS) do
        if RestrictionActive(name) then
            return true
        end
    end
    return false
end

function WTF.MapRestricted()
    return RestrictionActive("Map")
end

function WTF.MoveRestricted()
    return WTF.HardRestricted() or WTF.MapRestricted()
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

-- Features that moved out of WTF (author-approved): in 1.3.0 the shield
-- display to Dyre's Shields Up, and the cooldown chimes, the Nightfall sound,
-- and the Demon Armor reminder to Dyre's Buff Reminders; in 1.11.0 (John,
-- 2026-11-20: "Yes, full move") the DoT tracker, the nameplate DoT dots, DoT
-- damage prediction, the smart curse, and the Control bar with its macros
-- and announcements to Dyre's Debuff Tracker. CurseForge lists them as
-- required, so the app installs them; the TOC keeps them optional, so WTF
-- loads without them and says once per session, at login, what to install
-- or enable (CurseForge only).
WTF.DDT_FEATURES = "the DoT tracker, DoT colors, nameplate DoT dots, DoT damage prediction, the smart curse, "
    .. "and the Control bar with its macros and announcements"
WTF.MOVED_TO = {
    {addon = "DyresShieldsUp", title = "Dyre's Shields Up", what = "the shield display"},
    {addon = "DyresBuffReminders", title = "Dyre's Buff Reminders",
        what = "the cooldown chimes, the Nightfall sound, and the Demon Armor reminder"},
    {addon = "DyresDebuffTracker", title = "Dyre's Debuff Tracker", what = WTF.DDT_FEATURES},
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

-- Dyre's Toolkit 2.14.0's "Welcome messages at login" (John, 2026-11-23: "A:
-- one Toolkit switch"): false hides the banner and the ready line only; errors
-- and problems always show. Without the function (an older Toolkit, or none),
-- the banner shows as before.
local function WelcomeHidden()
    local toolkit = rawget(_G, "DyresToolkit")
    return type(toolkit) == "table" and type(toolkit.ShowWelcome) == "function" and toolkit.ShowWelcome() == false
end

local function ReportLoaded(available)
    if WelcomeHidden() then
        return
    end
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
    "CharacterMacrosAvailable", "WriteCharacterMacro", "DeleteCharacterMacro",
    "InitializeAnnounce", "FormatAnnouncement", "ReportAnnounceDebug", "DebugEmote", "FriendlyTargetNames",
    "WhisperHealthstoneGift",
    "SetStonesScale", "SetShardCounterScale",
    "ReportRestrictions", "InitializeProbe", "InitializeOptions", "OpenSettings",
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

-- More shards than any bags can carry: a larger saved value is damaged.
local INSTANCE_KEEP_MAX = 1000

local function IsWholeNumber(value)
    return type(value) == "number" and value == math.floor(value)
end

function WTF.SanitizeShardLimit(value)
    if not IsWholeNumber(value) then
        return WTF.DEFAULT_SHARD_LIMIT
    end
    return math.max(WTF.SHARD_LIMIT_MIN, math.min(WTF.SHARD_LIMIT_MAX, value))
end

-- The shards kept when you entered an instance (Shards.lua), or nil outside one.
function WTF.SanitizeInstanceKeep(value)
    if not IsWholeNumber(value) or value < 0 or value > INSTANCE_KEEP_MAX then
        return nil
    end
    return value
end

function WTF.SanitizeShardLow(value)
    if not IsWholeNumber(value) then
        return WTF.DEFAULT_SHARD_LOW
    end
    return math.max(WTF.SHARD_LOW_MIN, math.min(WTF.SHARD_LOW_MAX, value))
end

-- The Stones bar's and the shard counter's size, in percent (John,
-- 2026-11-12, from a player comment; as the control bar's Bar size).
WTF.FRAME_SCALE_MIN = 50
WTF.FRAME_SCALE_MAX = 150
WTF.FRAME_SCALE_STEP = 5
WTF.DEFAULT_FRAME_SCALE = 100

function WTF.SanitizeFrameScale(value)
    if not IsWholeNumber(value) then
        return WTF.DEFAULT_FRAME_SCALE
    end
    local stepped = math.floor(value / WTF.FRAME_SCALE_STEP + 0.5) * WTF.FRAME_SCALE_STEP
    return math.max(WTF.FRAME_SCALE_MIN, math.min(WTF.FRAME_SCALE_MAX, stepped))
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

local ANNOUNCE_SWITCHES = {"summonGroup", "summonWhisper", "soulstoneGroup", "soulstoneWhisper",
    "healthstoneWhisper", "healthstoneEmote", "soulstoneEmote"}

-- Saved settings of the features that moved to Dyre's Debuff Tracker in
-- 1.11.0: WTF keeps them exactly as the last login before 1.11.0 left them,
-- and never repairs, writes, or deletes them, for Dyre's Debuff Tracker to
-- copy once (it never writes them either) and for a downgrade. Whole tables
-- (DDT_TABLES) and the crowd-control announcement switches and texts inside
-- db.announce (DDT_ANNOUNCE_KEYS; WTF's own announce keys stay live).
WTF.DDT_TABLES = {"tracker", "predict", "control"}
WTF.DDT_ANNOUNCE_KEYS = {"fearGroup", "banishGroup", "enslaveGroup", "howlGroup", "fearGroupText",
    "banishGroupText", "enslaveGroupText", "howlGroupText"}

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
        counterScale = WTF.SanitizeFrameScale(shards.counterScale),
        instanceKeep = WTF.SanitizeInstanceKeep(shards.instanceKeep),
    }
    local stones = type(db.stones) == "table" and db.stones or {}
    local soulstone = type(stones.soulstone) == "table" and stones.soulstone or nil
    db.stones = {
        enabled = stones.enabled ~= false,
        shown = stones.shown ~= false,
        position = SanitizePosition(stones.position),
        scale = WTF.SanitizeFrameScale(stones.scale),
        macros = stones.macros ~= false,
        remindSoulstone = stones.remindSoulstone ~= false,
        remindHealthstone = stones.remindHealthstone ~= false,
        soulstone = soulstone and type(soulstone.name) == "string" and type(soulstone.ends) == "number"
            and {name = soulstone.name, ends = soulstone.ends} or nil,
    }
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
    for _, key in ipairs(WTF.DDT_ANNOUNCE_KEYS) do
        cleanAnnounce[key] = announce[key]
    end
    db.announce = cleanAnnounce
    -- One lock for every frame (author-approved, as MTF), locked by default;
    -- each frame reads its own copy.
    -- db.shield, db.chimes, db.alerts, and db.reminders stay exactly as saved
    -- (author-approved): Dyre's Shields Up and Dyre's Buff Reminders copy them
    -- once, and a downgrade still finds them. So do db.tracker, db.predict,
    -- and db.control (WTF.DDT_TABLES), for Dyre's Debuff Tracker.
    db.locked = db.locked ~= false
    db.grid = db.grid ~= false
    db.stones.locked = db.locked
    db.shards.counterLocked = db.locked
    return db
end

-- Dyre's Toolkit Profile (Toolkit 2.10.0; John, 2026-11-17: "one place to go
-- to persist your profile"). WTF keeps its live settings in
-- WarlockToolsForeverDB; the Toolkit keeps this character's copy, copies from
-- another character or the Defaults, and exports and imports it. Not in the
-- profile (characterKeys, top-level keys only): locked, a copy of the
-- Toolkit's account-wide lock; shield, chimes, alerts, and reminders, old WTF
-- data that Dyre's Shields Up and Dyre's Buff Reminders copy once per
-- character; tracker, predict, and control, the same for Dyre's Debuff
-- Tracker (1.11.0). WarlockToolsForeverAccountDB (focusWorks, learned ticks) is account-wide,
-- so it is not in it. No macro names are saved: they are fixed.
WTF.PROFILE_CHARACTER_KEYS = {"locked", "shield", "chimes", "alerts", "reminders", "tracker", "predict", "control"}

-- This character's live state inside the settings tables. The engine skips
-- only top-level keys, so a copy, an import, or the Defaults keep these:
-- the shards kept since entering an instance, who has your Soulstone and
-- until when, and the crowd-control announcement settings kept for Dyre's
-- Debuff Tracker.
local PROFILE_STATE = {
    {"shards", "instanceKeep"},
    {"stones", "soulstone"},
}
for _, key in ipairs(WTF.DDT_ANNOUNCE_KEYS) do
    PROFILE_STATE[#PROFILE_STATE + 1] = {"announce", key}
end

local function CopyValue(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, inner in pairs(value) do
        copy[key] = CopyValue(inner)
    end
    return copy
end

-- The profile's sanitize: any table (empty, partial, older, newer, another
-- character's) becomes full, repaired settings, with this character's state.
function WTF.SanitizeProfile(settings)
    local clean = WTF.SanitizeDB(type(settings) == "table" and settings or {})
    local live = WTF.db
    for _, path in ipairs(PROFILE_STATE) do
        local section, key = path[1], path[2]
        local value = type(live) == "table" and type(live[section]) == "table" and live[section][key] or nil
        clean[section][key] = CopyValue(value)
    end
    return clean
end

-- After a copy or import, out of combat (the Toolkit refuses one in combat):
-- the engine wrote the new values into WTF.db in place. Each part reads them
-- again; a secure frame waits out combat.
function WTF.ApplyProfile()
    WTF.ApplyShardsProfile()
    WTF.ApplyStonesProfile()
    WTF.RefreshGrid()
end

-- Once, at login, before the modules build their frames, so a part copied
-- while WTF was not loaded is written first. With a Toolkit older than 2.10.0
-- (or none) nothing changes.
local function RegisterProfilePart()
    local register = WTF.toolkit and WTF.toolkit.RegisterProfilePart
    if type(register) ~= "function" then
        return false
    end
    return register({
        addon = addonName,
        title = DEFAULT_TITLE,
        current = function() return WTF.db end,
        sanitize = function(settings) return WTF.SanitizeProfile(settings) end,
        characterKeys = WTF.PROFILE_CHARACTER_KEYS,
        refresh = function() WTF.ApplyProfile() end,
    }) == true
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
            -- For /wtf debug_stones: whether a key press can run waiting work.
            WTF.keyInputHooked = true
        end
    end
    WorldFrame:HookScript("OnMouseDown", OnInput)
end

-- While unlocked, a frame shows a gold outline and a hint (author-approved).
-- A plain child, so it can show and hide also in combat.
function WTF.CreateMover(frame)
    local mover = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    -- On its frame's strata, so the outline is never under what covers it.
    mover:SetFrameStrata(frame:GetFrameStrata())
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
    WTF.db.shards.counterLocked = locked
end

-- quiet: Dyre's Toolkit locks every Dyre's AddOn and says one line for all.
function WTF.SetFramesLocked(locked, quiet)
    SetLockFlags(locked)
    WTF.RefreshStonesMover()
    WTF.RefreshShardCounter()
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
-- Dyre's Toolkit's shared files (WTF 1.4.1): since 1.11.0 WTF uses only
-- its announcement fill (Announce.lua; without it, WTF's own) and hands a
-- true focusWorks flag to its one flag for every Dyre's AddOn, once. The
-- engines that needed the rest moved to Dyre's Debuff Tracker. Only true
-- function fields count, as the Toolkit keeps contract 2 and has no version
-- string.
local SHARED_FUNCTIONS = {"FormatAnnouncement", "NoteFocusWorks"}

function WTF.SharedToolkit()
    local toolkit = rawget(_G, "DyresToolkit")
    if type(toolkit) == "table" and type(toolkit.RequireContract) == "function" then
        toolkit = toolkit.RequireContract(TOOLKIT_CONTRACT)
    end
    if type(toolkit) ~= "table" then
        return nil
    end
    for _, name in ipairs(SHARED_FUNCTIONS) do
        if type(toolkit[name]) ~= "function" then
            return nil
        end
    end
    return toolkit
end

-- Without the Toolkit, WTF's own flag stays for a later login.
local function UseShared()
    local shared = WTF.SharedToolkit()
    WTF.shared = shared
    if not shared then
        return
    end
    if WTF.accountDB.focusWorks == true then
        shared.NoteFocusWorks()
    end
    WTF.accountDB.focusWorks = nil
end

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

-- /wtf reset: the Stones bar and the shard counter back to their default places.
function WTF.ResetPositions()
    WTF.ResetShardCounterPosition()
    WTF.ResetStonesPosition()
    if InCombatLockdown() then
        WTF.Report("WTF frames move back to their default places after combat.")
    end
end

-- The Bindings.xml shim (1.11.0, one release; lead-approved): the old smart
-- curse binding stays defined, with no button behind it, so the game keeps a
-- player's key until Dyre's Debuff Tracker moves it to its own command. These
-- are its Key Bindings header and label. A later release removes all three.
BINDING_HEADER_WARLOCKTOOLSFOREVER = DEFAULT_TITLE
_G["BINDING_NAME_CLICK WarlockToolsForeverSmartCurse:LeftButton"] = "Smart curse (moved to Dyre's Debuff Tracker)"

SLASH_WARLOCKTOOLSFOREVER1 = PRIMARY_SLASH
SLASH_WARLOCKTOOLSFOREVER2 = BACKUP_SLASH
SlashCmdList[SLASH_KEY] = WTF.HandleCommand

-- Account-wide settings, one set per client install (shared with MTF):
-- focusWorks, which only true survives. A 1.3.3 test build kept it per
-- character in db.control; a true one is carried over once.
-- ticks: DoT prediction's learned ticks, {[rank spell ID] = {tick = average,
-- power = spell power it was learned at}}, handed to the Toolkit since 1.5.0;
-- since 1.11.0 kept exactly as saved, for Dyre's Debuff Tracker.
local function LoadAccountDB(saved, character)
    saved = type(saved) == "table" and saved or {}
    local old = type(character) == "table" and type(character.control) == "table"
        and character.control.focusWorks == true
    return {focusWorks = (saved.focusWorks == true or old) or nil, ticks = saved.ticks}
end

local function LoadDB()
    WarlockToolsForeverAccountDB = LoadAccountDB(WarlockToolsForeverAccountDB, WarlockToolsForeverDB)
    WTF.accountDB = WarlockToolsForeverAccountDB
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
    -- Dyre's Debuff Tracker says in chat what it copied from WTF; WTF says
    -- nothing more about the 1.11.0 move (one line only, as MTF). Without it,
    -- ReportMovedFeatures says to install it.
    WTF.ReportMovedFeatures()
    -- Called directly rather than from each file's own PLAYER_LOGIN handler,
    -- so startup never depends on event handler order.
    UseToolkit()
    UseShared()
    InstallInputHooks()
    WTF.profileRegistered = RegisterProfilePart()
    WTF.InitializeShards()
    WTF.InitializeStones()
    WTF.InitializeAnnounce()
    WTF.InitializeProbe()
    WTF.InitializeOptions()
    JoinToolkit()
    WTF.RefreshGrid()
end)
