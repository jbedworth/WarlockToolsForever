local _, WTF = ...

-- DoT tracker. Two pinned rows, your target (purple outline) and your focus
-- (red outline), each shown only while that unit is a live hostile; then a
-- list of the other mobs you DoTed, with a slot per spell family in its own
-- color, in the Compact or Bars theme (author-approved). Since 1.5.0 the
-- engine is Dyre's Toolkit's (DotTracker.lua's CreateDotTracker, 2.5.0, moved
-- from here; its header holds the rules) with ClassData.WARLOCK's slots. WTF
-- keeps its settings (db.tracker, repaired in Core), its three frame names,
-- the default place, its colors, and its Options page, and claims the
-- Warlock's DoTs at priority 10.

local TRACKER_PRIORITY = 10
local DEFAULT_POINT = {"CENTER", "CENTER", -260, 120}
local NAMES = {target = "WarlockToolsForeverTracker", focus = "WarlockToolsForeverTrackerFocus",
    list = "WarlockToolsForeverTrackerList"}

-- The smart curse (John, 2026-11-10, from a player comment; Toolkit 2.7.0):
-- the engine's hidden secure button for a key binding (Bindings.xml), and
-- the "! Curse" macro with the same text.
local SMART_CURSE_BUTTON = "WarlockToolsForeverSmartCurse"
local CURSE_MACRO = "! Curse"
BINDING_HEADER_WARLOCKTOOLSFOREVER = "Warlock Tools Forever"
_G["BINDING_NAME_CLICK " .. SMART_CURSE_BUTTON .. ":LeftButton"] = "Smart curse"

local tracker = {available = false}

function WTF.CheckTrackerCapabilities()
    -- Forever's engine aura slots, else the Toolkit's plain-Lua ones (Auras.lua).
    if not WTF.AuraEngineKind() then
        return false, WTF.AURA_ENGINE_MISSING
    end
    for _, name in ipairs({"RegisterStateDriver", "UnregisterStateDriver"}) do
        if type(_G[name]) ~= "function" then
            return false, name
        end
    end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        return false, "C_Timer.After"
    end
    return true
end

-- The engine's tracker, once made; Dots.lua and Predict.lua use it too.
function WTF.DotTracker()
    return tracker.available and tracker.engine or nil
end

function WTF.TrackerCandidateFilters(key)
    return tracker.available and tracker.engine:CandidateFilters(key) or nil
end

function WTF.TrackerKnowsSlot(key)
    return tracker.available and tracker.engine:KnowsSlot(key) or false
end

function WTF.TrackerSlotIcon(key)
    return tracker.available and tracker.engine:SlotIcon(key) or nil
end

local function Rebuild()
    if tracker.available then
        tracker.engine:Rebuild()
    end
end

WTF.ApplyDotOrder = Rebuild
WTF.ApplyTrackerColors = Rebuild

function WTF.ApplyPanelColors()
    if tracker.available then
        tracker.engine:ApplyPanelColors()
    end
end

function WTF.RefreshTrackerPrediction(guid)
    if tracker.available then
        tracker.engine:RefreshPrediction(guid)
    end
end

function WTF.SetTrackerHealth(key, value)
    local settings = WTF.db.tracker
    if key == "health" then
        settings.health = value == true
    elseif key == "healthText" then
        settings.healthText = WTF.SanitizeHealthText(value)
    end
    Rebuild()
end

function WTF.SetTrackerSize(theme, key, value)
    local sizes = WTF.db.tracker.sizes
    if key then
        local saved = {}
        for name, current in pairs(sizes[theme]) do
            saved[name] = current
        end
        saved[key] = value
        sizes[theme] = WTF.SanitizeTrackerSizes(theme, saved)
    else
        sizes[theme] = WTF.SanitizeTrackerSizes(theme, nil)
    end
    Rebuild()
end

function WTF.SetTrackerTheme(theme)
    WTF.db.tracker.theme = theme == "bars" and "bars" or "compact"
    Rebuild()
end

function WTF.SetTrackerPanelOpacity(key, percent)
    WTF.db.tracker.panelOpacity[key] = WTF.SanitizeWhole(percent, WTF.PANEL_OPACITY_MIN, WTF.PANEL_OPACITY_MAX,
        WTF.DEFAULT_PANEL_OPACITY)
    if tracker.available then
        tracker.engine:ApplyPanelOpacity()
    end
end

-- Whether the Toolkit has the smart curse (2.7.0 or later).
function WTF.SmartCurseAvailable()
    return tracker.available and type(tracker.engine.ApplySmartCurse) == "function"
end

-- "! Curse": written while the control macros are on and you know Curse of
-- Weakness; deleted when they are off, and when you lose Weakness (only one
-- this session wrote). Out of combat (in combat, when it ends).
local function WriteCurseMacro(body)
    local keeper = tracker.keeper
    if not keeper then
        return
    end
    WTF.shared.OutOfCombat(keeper, function()
        if WTF.db.control.macros == false then
            keeper:Delete(CURSE_MACRO)
        elseif body then
            keeper:Write(CURSE_MACRO, body)
        elseif keeper.written[CURSE_MACRO] then
            keeper:Delete(CURSE_MACRO)
        end
    end)
end

function WTF.ApplyCurseMacro()
    if WTF.SmartCurseAvailable() then
        WriteCurseMacro(tracker.engine:SmartCurseBody())
    end
end

function WTF.SetCurseMode(mode)
    WTF.db.tracker.curseMode = mode == "smart" and "smart" or "last"
    if WTF.SmartCurseAvailable() then
        tracker.engine:ApplySmartCurse()
    end
end

function WTF.SetCurseMarker(on)
    WTF.db.tracker.curseMarker = on ~= false
    if WTF.SmartCurseAvailable() then
        tracker.engine:ApplySmartCurse()
    end
end

function WTF.ResetTrackerPosition()
    WTF.db.tracker.position = nil
    WTF.db.tracker.sections = {}
    if tracker.available then
        tracker.engine:ResetPosition()
    end
end

function WTF.RefreshTracker()
    if tracker.available then
        tracker.engine:Refresh()
    end
end

function WTF.InitializeTracker()
    local available, missing = WTF.CheckTrackerCapabilities()
    if not available then
        WTF.Report("The DoT tracker stays off: this client lacks " .. missing .. ".")
        return
    end
    local engine, why = WTF.shared.CreateDotTracker({
        addon = "WarlockToolsForever",
        priority = TRACKER_PRIORITY,
        class = "WARLOCK",
        store = WTF.db.tracker,
        names = {target = NAMES.target, focus = NAMES.focus, list = NAMES.list, smartCurse = SMART_CURSE_BUTTON},
        point = DEFAULT_POINT,
        slotColor = WTF.SlotColor,
        panelColor = WTF.PanelColor,
        movable = {register = WTF.RegisterMovable, beginDrag = WTF.BeginDrag, endDrag = WTF.EndDrag},
        locked = function() return WTF.db.locked ~= false end,
        -- The toolkit's Ctrl-drag of a locked frame (Layout.lua has none).
        ctrlMove = WTF.toolkit ~= nil,
        predictor = WTF.predictor,
        onSpellsChanged = function() WTF.RefreshPlateDots() end,
        onSmartCurse = function(body) WriteCurseMacro(body) end,
    })
    if not engine then
        WTF.Report("The DoT tracker stays off: this client lacks " .. tostring(why) .. ".")
        return
    end
    tracker.engine = engine
    tracker.available = true
    if WTF.SmartCurseAvailable() then
        tracker.keeper = WTF.shared.CreateMacroKeeper({warn = WTF.Warn})
        WTF.ApplyCurseMacro()
    end
end

function WTF.ReportTrackerDebug()
    local available, missing = WTF.CheckTrackerCapabilities()
    WTF.Report(string.format("debug_tracker available=%s%s", tostring(available and tracker.available),
        missing and (" missing=" .. missing) or ""))
    if not tracker.available then
        return
    end
    for _, line in ipairs(tracker.engine:DebugLines()) do
        WTF.Report("debug_tracker " .. line)
    end
end
