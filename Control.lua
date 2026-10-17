local _, WTF = ...

-- Control bar (author-approved, after MTF's Polymorph bar): a block per mob you
-- Fear or Banish, in WTF's Bars format: the mob's name above a bar that
-- drains with the spell's time left. Unlike Polymorph, several mobs can be
-- controlled at once, so there are up to MAX_ROWS rows.
--
-- AddOn code cannot read enemy auras in combat, so each row is a Blizzard
-- AuraContainer slot, as in the DoT tracker: the engine draws the bar; WTF
-- knows only which mobs you cast on, from your own cast events. A row binds
-- to its mob's nameplate, target, focus, or mouseover, and goes when the mob
-- dies or the longest such spell could have ended. A dim line stays behind
-- each bar, so a spell that broke early shows as gone.
--
-- On cast, WTF can tell the group (Announce) and, when a single-target
-- control spell (Banish) succeeds, mark the mob with the moon (author-approved:
-- the marker tells the group the mob is out of the fight, and one marker slot
-- is all WTF should take in a group, so Fear, often on several mobs, marks
-- nothing). The combat log is closed,
-- so a resist cannot be seen; a successful cast counts as landed.
--
-- Clicking a row recasts its spell on its mob: a secure macro targets the mob
-- by name, casts, and goes back to your target. Secure buttons change only
-- out of combat, so each row's click sits in a fixed slot under its row and
-- is set as the cast starts (a pull's Fear or Banish starts before combat);
-- a row begun in combat gets its click when combat ends.

-- Classic IDs; every spellbook spell of the same name counts too. Enslave
-- Demon and Howl of Terror only announce: an enslaved demon is your pet, and
-- Howl of Terror has no single target.
WTF.CONTROL_SPELLS = {
    {key = "fear", label = "Fear", ids = {5782, 6213, 6215}, longest = 20, bar = true},
    {key = "banish", label = "Banish", ids = {710, 18647}, longest = 30, bar = true, marker = 5},
    {key = "enslave", label = "Enslave Demon", ids = {1098, 11725, 11726}},
    {key = "howl", label = "Howl of Terror", ids = {5484, 17928}, untargeted = true},
}
-- Raid markers by index, as SetRaidTarget numbers them, and their chat codes.
WTF.RAID_MARKERS = {
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
local MARKERS_VERSION = 2
local OLD_BANISH_MARKER = 3
WTF.CONTROL_SCALE_MIN = 50
WTF.CONTROL_SCALE_MAX = 150
WTF.CONTROL_SCALE_STEP = 5
WTF.DEFAULT_CONTROL_SCALE = 100

local MAX_ROWS = 5
local FORGET_SLACK = 5
local ANNOUNCE_REPEAT_SECONDS = 3
local MAX_NAMEPLATE_UNITS = 40
local AURA_FILTER = "HARMFUL|PLAYER"
local CONTAINER_TEMPLATE = "CustomAuraContainerTemplate"

-- WTF's Bars theme: the name line, then a bar line with an icon.
local WIDTH = 200
local HEADER = 18
local LINE = 16
local ICON = 14
local PADDING = 6
local ROW_HEIGHT = HEADER + LINE + PADDING
local ROW_GAP = 4
local BROWN = {0.28, 0.16, 0.07, 0.85}
local IDLE_BORDER = {0.45, 0.35, 0.2}
local LINE_BACKGROUND = {0.1, 0.1, 0.1, 0.6}
local BAR_COLOR = {1, 0.85, 0.1}
local PLACEHOLDER_ALPHA = 0.3
local DEFAULT_POINT = {"CENTER", "CENTER", -260, -60}
local SAMPLES = {"Fear (sample)", "Banish (sample)"}

local control = {available = false, casts = {}, ids = {}, kinds = {}, rows = {}, lastAnnounce = {}}
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
    for _, marker in ipairs(WTF.RAID_MARKERS) do
        if marker.index == index then
            return true
        end
    end
    return false
end

-- The saved control settings, repaired; Core calls this from SanitizeDB.
function WTF.SanitizeControl(saved, sanitizePosition)
    saved = type(saved) == "table" and saved or {}
    local markers = type(saved.markers) == "table" and saved.markers or {}
    local clean = {enabled = saved.enabled ~= false, position = sanitizePosition(saved.position),
        scale = WTF.SanitizeControlScale(saved.scale), markers = {}, markersVersion = MARKERS_VERSION}
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

local function ReadGUID(unit)
    local guid = UnitGUID(unit)
    if WTF.IsSecret(guid) or type(guid) ~= "string" then
        return nil
    end
    return guid
end

local function ReadName(unit)
    local name = UnitName(unit)
    if WTF.IsSecret(name) or type(name) ~= "string" then
        return nil
    end
    return name
end

local function IsDead(unit)
    local dead = UnitIsDead(unit)
    return not WTF.IsSecret(dead) and dead == true
end

local function HasAuraContainer()
    if type(C_XMLUtil) ~= "table" or type(C_XMLUtil.GetTemplateInfo) ~= "function" then
        return false
    end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    return C_XMLUtil.GetTemplateInfo(CONTAINER_TEMPLATE) ~= nil
end

-- Spell IDs by kind: the Classic ones and the spellbook's of the same names.
local function BuildSpellSets()
    local byName = {}
    for _, spell in ipairs(WTF.CONTROL_SPELLS) do
        for _, id in ipairs(spell.ids) do
            control.kinds[id] = spell
            local name = C_Spell.GetSpellName(id)
            if name then
                byName[name] = spell
            end
        end
    end
    if type(C_SpellBook) == "table" and type(C_SpellBook.GetNumSpellBookSkillLines) == "function" then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if type(lineInfo) == "table" then
                for index = lineInfo.itemIndexOffset + 1, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
                    if type(item) == "table" and type(item.spellID) == "number" and byName[item.name] then
                        control.kinds[item.spellID] = byName[item.name]
                    end
                end
            end
        end
    end
    control.ids = {}
    for id, spell in pairs(control.kinds) do
        if spell.bar then
            control.ids[id] = true
        end
    end
end

local function KnowsAny()
    if type(C_SpellBook) ~= "table" or type(C_SpellBook.IsSpellKnown) ~= "function" then
        return false
    end
    for id in pairs(control.ids) do
        if C_SpellBook.IsSpellKnown(id) == true then
            return true
        end
    end
    return false
end

-- The unit showing this mob now: its nameplate, else target or focus. Not
-- mouseover: it changes with the pointer and has no event WTF rebinds on.
local function FindUnit(guid)
    if not guid then
        return nil
    end
    for index = 1, MAX_NAMEPLATE_UNITS do
        local unit = "nameplate" .. index
        if UnitExists(unit) and ReadGUID(unit) == guid then
            return unit
        end
    end
    for _, unit in ipairs({"target", "focus"}) do
        if ReadGUID(unit) == guid then
            return unit
        end
    end
end

-- The unit a cast sent at targetName went to: the first that matches by name.
local function FindCastUnit(targetName)
    for _, unit in ipairs({"target", "focus", "mouseover"}) do
        if UnitExists(unit) and ReadName(unit) == targetName then
            return unit
        end
    end
    for index = 1, MAX_NAMEPLATE_UNITS do
        local unit = "nameplate" .. index
        if UnitExists(unit) and ReadName(unit) == targetName then
            return unit
        end
    end
end

local function Bind(row, unit)
    local wanted = unit or "none"
    if row.boundUnit == wanted then
        return
    end
    row.boundUnit = wanted
    row.container:SetUnit(wanted)
    row.container:UpdateAllAuras()
end

-- Display ----------------------------------------------------------------------

local function Layout()
    local settings = WTF.db.control
    local sample = not WTF.db.locked
    anchor.mover:SetShown(sample)
    for index, row in ipairs(control.rows) do
        if not settings.enabled then
            row:Hide()
        elseif row.guid then
            row.name:SetText(row.mobName)
            row:Show()
        elseif sample and SAMPLES[index] then
            row.name:SetText(SAMPLES[index])
            row:Show()
        else
            row:Hide()
        end
    end
end

-- Out of combat only: each row's secure click, and whether it is there.
local function ApplyClicks()
    if InCombatLockdown() then
        control.clickDirty = true
        return
    end
    control.clickDirty = false
    local settings = WTF.db.control
    -- Rows scale with their click slots, so they never drift apart in combat.
    anchor:SetScale(settings.scale / 100)
    anchor:SetShown(settings.enabled and (KnowsAny() or not WTF.db.locked))
    for _, row in ipairs(control.rows) do
        row:SetScale(settings.scale / 100)
        local holder, name, spell = row.holder, row.clickName, row.clickSpell
        if name and spell then
            -- A missing mob leaves no target, so nothing else is cast on.
            holder:SetAttribute("type1", "macro")
            holder:SetAttribute("macrotext1", "/cleartarget\n/targetexact " .. name
                .. "\n/cast [@target,harm,nodead] " .. spell .. "\n/targetlasttarget")
        else
            holder:SetAttribute("type1", nil)
            holder:SetAttribute("macrotext1", nil)
        end
        holder.mobName, holder.spellName = name, spell
        -- A click area only where there is something to recast, or to drag by.
        holder:SetShown((name ~= nil and spell ~= nil) or not WTF.db.locked)
    end
end

local function Forget(row)
    row.guid, row.mobName, row.clickName, row.clickSpell, row.token = nil, nil, nil, nil, nil
    Bind(row, nil)
    Layout()
    ApplyClicks()
end

local function RowFor(guid, name)
    for _, row in ipairs(control.rows) do
        if (guid and row.guid == guid) or (not row.guid and row.clickName == name) then
            return row
        end
    end
    -- A row is free once its click slot is empty too: a slot's action can be
    -- cleared only out of combat, so a mob forgotten in combat keeps its
    -- slot until then, and no other mob gets a click that casts on it.
    for _, row in ipairs(control.rows) do
        if not row.guid and not row.clickName and not row.holder.mobName then
            return row
        end
    end
end

local function Track(row, guid, mobName, spell, spellName)
    row.guid, row.mobName = guid, mobName
    row.clickName, row.clickSpell = mobName, spellName
    local token = {}
    row.token = token
    Bind(row, FindUnit(guid))
    Layout()
    ApplyClicks()
    C_Timer.After(spell.longest + FORGET_SLACK, function()
        if row.token == token then
            Forget(row)
        end
    end)
end

local function ShowTooltip(holder)
    GameTooltip:SetOwner(holder, "ANCHOR_TOP")
    if holder.mobName then
        GameTooltip:SetText("Click: " .. holder.spellName .. " " .. holder.mobName .. " again.", 1, 1, 1)
        GameTooltip:AddLine("Targets it by name, then goes back to your target.", 0.7, 0.7, 0.7, true)
    else
        GameTooltip:SetText("Fear or Banish a mob, then click its row to cast it again.", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

local function StartDrag()
    WTF.BeginDrag(anchor)
end

local function StopDrag()
    WTF.EndDrag(anchor)
end

local function Place()
    local position = WTF.db.control.position
    anchor:ClearAllPoints()
    if position then
        anchor:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else
        anchor:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
    end
end

-- The engine slot's regions; only here may WTF place the engine's button.
local function SlotInitializer(row)
    return function(button)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", row, "TOPLEFT", PADDING, -HEADER)
        button:SetSize(WIDTH - PADDING * 2, LINE)
        button:SetMouseClickEnabled(false)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON, ICON)
        icon:SetPoint("LEFT", 1, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local status = CreateFrame("StatusBar", nil, button)
        status:SetPoint("TOPLEFT", button, "TOPLEFT", ICON + 4, 0)
        status:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        status:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        status:SetStatusBarColor(BAR_COLOR[1], BAR_COLOR[2], BAR_COLOR[3])
        local spellName = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        spellName:SetPoint("LEFT", 4, 0)
        spellName:SetJustifyH("LEFT")
        local timeLeft = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timeLeft:SetPoint("RIGHT", -4, 0)
        button:SetIcon(icon)
        local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
        button:SetDurationBar(status, {direction = direction})
        button:SetSpellName(spellName)
        button:SetDurationText(timeLeft, {})
    end
end

local function CreateRow(index)
    local offset = -(index - 1) * (ROW_HEIGHT + ROW_GAP)
    -- The click slot: a secure button at a fixed place under the row.
    local holder = CreateFrame("Button", "WarlockToolsForeverControlClick" .. index, anchor,
        "SecureActionButtonTemplate")
    holder:SetSize(WIDTH, ROW_HEIGHT)
    holder:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, offset)
    holder:RegisterForClicks("AnyUp", "AnyDown")
    holder:SetAttribute("useOnKeyDown", false)
    holder:RegisterForDrag("LeftButton")
    holder:SetScript("OnDragStart", StartDrag)
    holder:SetScript("OnDragStop", StopDrag)
    holder:SetScript("OnEnter", ShowTooltip)
    holder:SetScript("OnLeave", function() GameTooltip:Hide() end)
    holder:Hide()
    -- The row an ordinary frame on top, taking no mouse, so it shows in combat.
    local row = CreateFrame("Frame", "WarlockToolsForeverControlRow" .. index, UIParent, "BackdropTemplate")
    row:SetSize(WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", holder, "TOPLEFT")
    row:EnableMouse(false)
    row:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2}})
    row:SetBackdropColor(BROWN[1], BROWN[2], BROWN[3], BROWN[4])
    row:SetBackdropBorderColor(IDLE_BORDER[1], IDLE_BORDER[2], IDLE_BORDER[3])
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", PADDING, -4)
    row.name:SetWidth(WIDTH - PADDING * 2)
    row.name:SetJustifyH("LEFT")
    local line = row:CreateTexture(nil, "BACKGROUND")
    line:SetPoint("TOPLEFT", row, "TOPLEFT", PADDING, -HEADER)
    line:SetSize(WIDTH - PADDING * 2, LINE)
    line:SetColorTexture(LINE_BACKGROUND[1], LINE_BACKGROUND[2], LINE_BACKGROUND[3], LINE_BACKGROUND[4])
    local placeholder = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    placeholder:SetTexture(C_Spell.GetSpellTexture(WTF.CONTROL_SPELLS[1].ids[1]))
    placeholder:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    placeholder:SetDesaturated(true)
    placeholder:SetAlpha(PLACEHOLDER_ALPHA)
    placeholder:SetSize(ICON, ICON)
    placeholder:SetPoint("LEFT", line, "LEFT", 1, 0)
    local container = CreateFrame("AuraContainer", nil, row, CONTAINER_TEMPLATE)
    container:SetPoint("TOPLEFT", row, "TOPLEFT")
    container:SetSize(1, 1)
    container:AddAuraSlot("control", AURA_FILTER, {
        candidateFilters = {includeSpellIDs = control.ids},
        initializeFrame = SlotInitializer(row),
    })
    row.container, row.holder = container, holder
    row:Hide()
    return row
end

-- Casts --------------------------------------------------------------------------

local function MarkerCode(spell)
    local index = spell.marker and WTF.db.control.markers[spell.key] or 0
    for _, marker in ipairs(WTF.RAID_MARKERS) do
        if marker.index == index then
            return marker.code or ""
        end
    end
    return ""
end

-- At the start of a cast (author-approved), as the other group messages go.
local function AnnounceCast(spell, targetName)
    local settings = WTF.db.announce
    local now = GetTime()
    local last = control.lastAnnounce[spell.key]
    if not settings[spell.key .. "Group"] or (last and now - last < ANNOUNCE_REPEAT_SECONDS) then
        return
    end
    -- With no marker, %M goes with the space before it.
    local code = MarkerCode(spell)
    local text = settings[spell.key .. "GroupText"]
    if code == "" then
        text = text:gsub(" ?%%M", "")
    else
        text = text:gsub("%%M", code)
    end
    if WTF.SendGroupAnnouncement(WTF.FormatAnnouncement(text, targetName or "")) then
        control.lastAnnounce[spell.key] = now
    end
end

local function OnCastSent(target, castGUID, spellID)
    if WTF.IsSecret(spellID) or WTF.IsSecret(target) or WTF.IsSecret(castGUID) then
        return
    end
    local spell = control.kinds[spellID]
    if not spell then
        return
    end
    if spell.untargeted then
        AnnounceCast(spell)
        return
    end
    if type(target) ~= "string" or target == "" then
        return
    end
    AnnounceCast(spell, target)
    if not spell.bar or not WTF.db.control.enabled then
        return
    end
    local unit = FindCastUnit(target)
    local guid = unit and ReadGUID(unit)
    control.casts[castGUID] = {target = target, spellID = spellID, guid = guid}
    control.lastCast = {spellID = spellID, target = target}
    -- A pull's Fear or Banish starts out of combat and lands in it: set the
    -- click now, while the game still allows it.
    if not InCombatLockdown() then
        local row = RowFor(guid, target)
        if row and not row.guid then
            row.clickName, row.clickSpell = target, C_Spell.GetSpellName(spellID)
            control.casts[castGUID].row = row
            ApplyClicks()
        end
    end
end

-- The unit to mark: your target or focus when it is this mob (as TankHelper
-- marks your target), else the unit that shows it. SetRaidTarget toggles: a
-- unit that already has the marker loses it (the pinned /tm code's "!" prefix
-- exists to skip that). GetRaidTargetIndex returns a secret to AddOn code in
-- combat (pinned RaidMarkersDocumentation: SecretReturns), so WTF cannot
-- always ask. It skips the mark when the index is readable and already
-- equal, or, when it is not, when it marked this mob with it before.
local function Mark(spell, guid, unit)
    local index = WTF.db.control.markers[spell.key]
    if not index or index == 0 or type(SetRaidTarget) ~= "function" then
        return
    end
    for _, candidate in ipairs({"target", "focus"}) do
        if ReadGUID(candidate) == guid then
            unit = candidate
            break
        end
    end
    local current = GetRaidTargetIndex(unit)
    local unreadable = WTF.IsSecret(current)
    control.marked = control.marked or {}
    if (not unreadable and current == index) or (unreadable and control.marked[guid] == index) then
        control.marked[guid] = index
        return
    end
    SetRaidTarget(unit, index)
    control.marked[guid] = index
    control.lastMark = unit .. (unreadable and " (marker unreadable)" or "")
end

local function OnCastSucceeded(castGUID)
    if WTF.IsSecret(castGUID) then
        return
    end
    local cast = control.casts[castGUID]
    control.casts[castGUID] = nil
    if not cast or not WTF.db.control.enabled then
        return
    end
    local guid = cast.guid
    if not guid then
        local unit = FindCastUnit(cast.target)
        guid = unit and ReadGUID(unit)
    end
    local unit = FindUnit(guid)
    if not unit or not UnitCanAttack("player", unit) then
        return
    end
    local spell = control.kinds[cast.spellID]
    Mark(spell, guid, unit)
    local row = RowFor(guid, cast.target)
    if row then
        Track(row, guid, cast.target, spell, C_Spell.GetSpellName(cast.spellID))
    end
end

local function Rebind()
    for _, row in ipairs(control.rows) do
        if row.guid then
            local unit = FindUnit(row.guid)
            if unit and IsDead(unit) then
                Forget(row)
            else
                Bind(row, unit)
            end
        end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit, first, second, third)
    if event == "UNIT_SPELLCAST_SENT" then
        OnCastSent(first, second, third)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnCastSucceeded(first)
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if not WTF.IsSecret(first) then
            local cast = control.casts[first]
            control.casts[first] = nil
            -- A cast that never landed gives back the row it reserved.
            local row = cast and cast.row
            if row and not row.guid then
                row.clickName, row.clickSpell = nil, nil
                ApplyClicks()
            end
        end
    elseif event == "UNIT_HEALTH" then
        for _, row in ipairs(control.rows) do
            if row.guid and row.boundUnit == unit and IsDead(unit) then
                Forget(row)
            end
        end
    elseif event == "SPELLS_CHANGED" then
        BuildSpellSets()
        for _, row in ipairs(control.rows) do
            row.container:SetAuraSlotCandidateFilters("control", {includeSpellIDs = control.ids})
        end
        ApplyClicks()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if control.placeDirty then
            control.placeDirty = false
            Place()
        end
        -- A click set as a cast started, for a cast that never landed, goes.
        for _, row in ipairs(control.rows) do
            if not row.guid then
                row.clickName, row.clickSpell = nil, nil
            end
        end
        ApplyClicks()
    else
        Rebind()
    end
end)

function WTF.RefreshControl()
    if not control.available then
        return
    end
    Layout()
    ApplyClicks()
end

function WTF.ResetControlPosition()
    WTF.db.control.position = nil
    if not control.available then
        return
    end
    if InCombatLockdown() then
        control.placeDirty = true
        return
    end
    Place()
end

function WTF.InitializeControl()
    if not HasAuraContainer() then
        WTF.Report("The control bar stays off: this client lacks " .. CONTAINER_TEMPLATE .. ".")
        return
    end
    BuildSpellSets()
    anchor = CreateFrame("Frame", "WarlockToolsForeverControl", UIParent)
    anchor:SetSize(WIDTH, MAX_ROWS * (ROW_HEIGHT + ROW_GAP) - ROW_GAP)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:EnableMouse(false)
    anchor.mover = WTF.CreateMover(anchor)
    WTF.RegisterMovable(anchor, function(position) WTF.db.control.position = position end)
    for index = 1, MAX_ROWS do
        control.rows[index] = CreateRow(index)
    end
    WTF.controlRows = control.rows
    Place()
    control.available = true
    for _, event in ipairs({"PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "SPELLS_CHANGED", "UNIT_HEALTH"}) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED"}) do
        events:RegisterUnitEvent(event, "player")
    end
    Layout()
    ApplyClicks()
end

-- /wtf debug_control: the IDs, each row's mob and click, and the last mark.
function WTF.ReportControlDebug()
    WTF.Report(string.format("debug_control available=%s known=%s", tostring(control.available),
        tostring(control.available and KnowsAny())))
    if not control.available then
        return
    end
    local ids = {}
    for id in pairs(control.ids) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    WTF.Report("debug_control ids=" .. table.concat(ids, ","))
    local last = control.lastCast
    if last then
        WTF.Report(string.format("debug_control lastCast spell=%d target=%s", last.spellID, last.target))
    end
    for index, row in ipairs(control.rows) do
        WTF.Report(string.format("debug_control row %d mob=%s unit=%s click=%s macro=%s", index,
            tostring(row.mobName), tostring(row.boundUnit), tostring(row.holder:IsShown()),
            (tostring(row.holder:GetAttribute("macrotext1")):gsub("\n", " | "))))
    end
    WTF.Report("debug_control marked=" .. tostring(control.lastMark))
end
