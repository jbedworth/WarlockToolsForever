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
    "DebugDeleteShard",
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

local function IsWholeNumber(value)
    return type(value) == "number" and value == math.floor(value)
end

function WTF.SanitizeShardLimit(value)
    if not IsWholeNumber(value) then
        return WTF.DEFAULT_SHARD_LIMIT
    end
    return math.max(WTF.SHARD_LIMIT_MIN, math.min(WTF.SHARD_LIMIT_MAX, value))
end

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
    }
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
    WTF.InitializeShards()
    WTF.InitializeOptions()
end)
