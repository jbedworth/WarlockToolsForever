local _, WTF = ...

-- Control bar (author-approved, after MTF's Polymorph bar): a block per mob you
-- Fear or Banish, in WTF's Bars format, the Focus box above it for your
-- focus's Fear, Fear timers under nameplates, the "! Fear", "! Banish", and
-- "! Seduction" macros, and the cast announcements. Since 1.5.0 the engine is
-- Dyre's Toolkit's (Control.lua's CreateControlTracker, 2.5.0, moved from
-- here; its header holds the rules). WTF keeps its settings (db.control and
-- the announce texts), its frame names, the bar's place and mover, its
-- Options page, and its tooltips; it claims the Warlock's control bar,
-- macros, and announcements at priority 10, so Dyre's Debuff Tracker (5)
-- steps aside for them.

local CONTROL_PRIORITY = 10
local DEFAULT_POINT = {"CENTER", "CENTER", -260, -60}
local SAMPLES = {"Fear (sample)", "Banish (sample)"}
local FOCUS_RED = {0.9, 0.1, 0.1}
-- The engine's default look (WTF's Bars theme): the bar's size for its mover.
local ROW_WIDTH, ROW_HEIGHT, ROW_GAP, ROWS = 200, 40, 4, 5
local MARKERS_VERSION = 2
local OLD_BANISH_MARKER = 3
local MAX_MARKER = 8
WTF.CONTROL_SCALE_MIN = 50
WTF.CONTROL_SCALE_MAX = 150
WTF.CONTROL_SCALE_STEP = 5
WTF.DEFAULT_CONTROL_SCALE = 100

-- The settings page and the sanitizer read the spells and markers at load,
-- from the Toolkit's tables (it loads first, OptionalDeps); without Dyre's
-- Toolkit 2.5 the bar is off and there are none to set.
local toolkit = rawget(_G, "DyresToolkit")
local classData = type(toolkit) == "table" and type(toolkit.ClassData) == "table" and toolkit.ClassData.WARLOCK
WTF.CONTROL_SPELLS = classData and classData.control or {}
WTF.RAID_MARKERS = type(toolkit) == "table" and toolkit.RAID_MARKERS or {{index = 0, label = "None"}}

local control = {available = false}
local anchor

local function IsWholeNumber(value)
    return type(value) == "number" and value == math.floor(value)
end

function WTF.SanitizeControlScale(value)
    if not IsWholeNumber(value) then
        return WTF.DEFAULT_CONTROL_SCALE
    end
    local stepped = math.floor(value / WTF.CONTROL_SCALE_STEP + 0.5) * WTF.CONTROL_SCALE_STEP
    return math.max(WTF.CONTROL_SCALE_MIN, math.min(WTF.CONTROL_SCALE_MAX, stepped))
end

local function ValidMarker(index)
    return IsWholeNumber(index) and index >= 0 and index <= MAX_MARKER
end

-- The saved control settings, repaired; Core calls this from SanitizeDB.
-- Saved markers of spells the Toolkit does not list (none without it) stay.
function WTF.SanitizeControl(saved, sanitizePosition)
    saved = type(saved) == "table" and saved or {}
    local markers = type(saved.markers) == "table" and saved.markers or {}
    local clean = {enabled = saved.enabled ~= false, position = sanitizePosition(saved.position),
        scale = WTF.SanitizeControlScale(saved.scale), markers = {}, markersVersion = MARKERS_VERSION,
        plateTimers = saved.plateTimers ~= false, macros = saved.macros ~= false}
    for key, marker in pairs(markers) do
        if type(key) == "string" and ValidMarker(marker) then
            clean.markers[key] = marker
        end
    end
    for _, spell in ipairs(WTF.CONTROL_SPELLS) do
        if spell.marker then
            local marker = ValidMarker(markers[spell.key]) and markers[spell.key] or spell.marker
            -- Banish's first default was the diamond; it moves to the moon once.
            if (saved.markersVersion or 1) < MARKERS_VERSION and marker == OLD_BANISH_MARKER
                and spell.key == "banish" then
                marker = spell.marker
            end
            clean.markers[spell.key] = marker
        end
    end
    return clean
end

-- Whether this client's focus has been seen to work: the Toolkit's one flag
-- for every Dyre's AddOn (Units.lua), else WTF's own from before 1.4.1.
function WTF.FocusWorks()
    if WTF.shared then
        return WTF.shared.FocusWorks()
    end
    return WTF.accountDB.focusWorks == true
end

-- A macro's text for one of ClassData's macro defs (the Toolkit's
-- FocusCastMacro with WTF's marker settings).
function WTF.ControlMacroBody(def)
    if not control.available then
        return nil
    end
    return control.tracker:MacroBody(def)
end

-- Out of combat only (the Toolkit waits for it); turning the macros off
-- deletes them.
function WTF.ApplyControlMacros()
    if control.available then
        control.tracker:ApplyMacros()
    end
    -- "! Curse" (Tracker.lua) follows the same switch.
    WTF.ApplyCurseMacro()
end

-- Display ----------------------------------------------------------------------

local function Place()
    local position = WTF.db.control.position
    anchor:ClearAllPoints()
    if position then
        anchor:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else
        anchor:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
    end
end

-- The bar holds the secure click slots and the Focus box, so it scales and
-- shows only out of combat; its scale reaches the Focus box once, and the
-- rows (plain frames on UIParent) take the same scale from the engine.
local function ApplyAnchor()
    local tracker = control.tracker
    local settings = WTF.db.control
    local scale = settings.scale / 100
    anchor:SetScale(scale)
    if tracker.scale ~= scale then
        tracker:SetScale(scale)
    end
    anchor:SetShown(settings.enabled and tracker:IsOwner("control") and (tracker:KnowsAny() or not WTF.db.locked))
end

local function OnChange()
    anchor.mover:SetShown(not WTF.db.locked)
    WTF.shared.OutOfCombat(control, ApplyAnchor)
end

local function ShowTooltip(holder)
    GameTooltip:SetOwner(holder, "ANCHOR_TOP")
    if holder.spellName then
        GameTooltip:SetText("Click: " .. holder.spellName .. " your focus again.", 1, 1, 1)
        GameTooltip:AddLine("No marker and no target change. With no focus it does nothing.", 0.7, 0.7, 0.7,
            true)
    elseif WTF.FocusWorks() then
        GameTooltip:SetText("Banish your focus (\"! Banish\"), then click its row to cast it again.", 0.7, 0.7,
            0.7)
    else
        GameTooltip:SetText("Your Fears and Banishes show here with their time left.", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

-- The cast announcements (author-approved): each spell's switch and text
-- from the announce settings, while Announce is on, to the group or Say.
local function AnnounceText(key)
    local settings = WTF.db.announce
    return settings[key .. "Group"] and settings[key .. "GroupText"] or nil
end

function WTF.RefreshControl()
    if control.available then
        control.tracker:Refresh()
        OnChange()
    end
end

function WTF.ResetControlPosition()
    WTF.db.control.position = nil
    if control.available then
        WTF.shared.OutOfCombat(Place, Place)
    end
end

function WTF.InitializeControl()
    if not WTF.shared.AuraEngineKind() then
        WTF.Report("The control bar stays off: this client lacks " .. WTF.AURA_ENGINE_MISSING .. ".")
        return
    end
    anchor = CreateFrame("Frame", "WarlockToolsForeverControl", UIParent)
    anchor:SetSize(ROW_WIDTH, ROWS * (ROW_HEIGHT + ROW_GAP) - ROW_GAP)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:EnableMouse(false)
    anchor.mover = WTF.CreateMover(anchor)
    WTF.RegisterMovable(anchor, function(position) WTF.db.control.position = position end)
    Place()
    local color = FOCUS_RED
    if WTF.db.tracker and WTF.db.tracker.panelColors then
        color = {WTF.PanelColor("focus")}
    end
    local tracker, missing = WTF.shared.CreateControlTracker({
        addon = "WarlockToolsForever",
        priority = CONTROL_PRIORITY,
        class = "WARLOCK",
        store = WTF.db.control,
        names = {row = "WarlockToolsForeverControlRow", click = "WarlockToolsForeverControlClick",
            focus = "WarlockToolsForeverControlFocus"},
        parent = anchor,
        rows = ROWS,
        locked = function() return WTF.db.locked ~= false end,
        samples = SAMPLES,
        focusBox = {key = "fear", color = color},
        announce = {text = AnnounceText, enabled = function() return WTF.db.announce.enabled == true end,
            say = function() return WTF.db.announce.channel == "say" end},
        keeper = {warn = WTF.Warn},
        tooltip = ShowTooltip,
        onDragStart = function() WTF.BeginDrag(anchor) end,
        onDragStop = function() WTF.EndDrag(anchor) end,
        onChange = function()
            if control.available then
                OnChange()
            end
        end,
    })
    if not tracker then
        WTF.Report("The control bar stays off: this client lacks " .. tostring(missing) .. ".")
        return
    end
    control.tracker = tracker
    WTF.controlRows = tracker.rows
    WTF.controlFocusBox = tracker.focusBox
    WTF.fearPlateTimers = tracker.plateTimers
    control.available = true
    WTF.RefreshControl()
end

-- /wtf reset_focus: forget that this client's focus works, so the macros fall
-- back again until a focus is seen (out of combat; in combat, after it). The
-- Toolkit's flag is one for every Dyre's AddOn, so this resets them all.
local RESET_FALLBACK = "WTF's macros try your focus, then the mob under the mouse, then your target, "
    .. "until a focus is seen to work."

function WTF.ResetFocusWorks()
    if not WTF.shared then
        WTF.accountDB.focusWorks = nil
        WTF.Report("Focus check reset. " .. RESET_FALLBACK)
        return
    end
    WTF.shared.ResetFocusWorks()
    WTF.Report(WTF.shared.FOCUS_RESET_TEXT or "Focus check reset for every Dyre's AddOn.")
    WTF.Report(RESET_FALLBACK)
end

-- /wtf debug_control: the IDs, each row's mob and click, and the last cast.
function WTF.ReportControlDebug()
    WTF.Report(string.format("debug_control available=%s focusWorks=%s", tostring(control.available),
        tostring(WTF.FocusWorks())))
    if not control.available then
        return
    end
    for _, line in ipairs(control.tracker:DebugLines()) do
        WTF.Report("debug_control " .. line)
    end
    -- For the Seduction macro: your demon's family and whether it knows Seduction.
    local family = type(UnitCreatureFamily) == "function" and UnitCreatureFamily("pet")
    WTF.Report(string.format("debug_control pet=%s seduction=%s", tostring(family),
        tostring(WTF.shared.PetKnows(6358))))
end
