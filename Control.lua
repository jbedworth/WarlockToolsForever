local _, WTF = ...

-- Control bar (author-approved, after MTF's Polymorph bar): a block per mob you
-- Fear or Banish, in WTF's Bars format: the mob's name above a bar that
-- drains with the spell's time left. Unlike Polymorph, several mobs can be
-- controlled at once, so there are up to MAX_ROWS rows.
--
-- AddOn code cannot read enemy auras in combat, so each row is a Blizzard
-- AuraContainer slot, as in the DoT tracker: the engine draws the bar; WTF
-- knows only which mobs you cast on, from your own cast events. A row binds
-- to its mob through your focus, target, or its nameplate (a mob's nameplate
-- token can change as it leaves plate range and comes back; its GUID does
-- not), and goes when the mob dies or the longest such spell could have ended. A dim line stays behind
-- each bar, so a spell that broke early shows as gone.
--
-- On cast, WTF can tell the group (Announce) and, when a single-target
-- control spell (Banish) succeeds, mark the mob with the moon (author-approved:
-- the marker tells the group the mob is out of the fight, and one marker slot
-- is all WTF should take in a group, so Fear, often on several mobs, marks
-- nothing). The combat log is closed,
-- so a resist cannot be seen; a successful cast counts as landed.
--
-- Banish follows your focus only (John, 1.3.1, as MTF's Polymorph bar: "The
-- ! Banish macro should work exactly like the sheep one"): "! Banish" focuses
-- the mob, marks it, and banishes it; a Banish counts only when it is cast at
-- your focus, its row is bound to "focus", and it goes when your focus becomes
-- another mob or none. Clicking a Banish row banishes your focus again, with
-- no marker and no targeting; with no focus it does nothing. Secure buttons
-- change only out of combat, so each row's click sits
-- in a fixed slot under its row and is set as the cast starts (a pull's
-- Banish starts before combat); a row begun in combat gets its click when
-- combat ends. Fear rows have no click (author-approved): a secure macro can
-- aim only at a unit token or a name, never at one mob's GUID, and juggled
-- mobs share names, so a click could Fear the wrong one. Your focus's Fear
-- instead shows in the Focus box above the rows (John, 1.3.1: "put a special
-- box on the top if/when the focus target is feared"), whose click fears your
-- focus again. A countdown on each
-- feared mob's nameplate shows which one is about to break; clicking the
-- nameplate targets it.

-- Classic IDs; every spellbook spell of the same name counts too. Enslave
-- Demon and Howl of Terror only announce: an enslaved demon is your pet, and
-- Howl of Terror has no single target.
WTF.CONTROL_SPELLS = {
    {key = "fear", label = "Fear", ids = {5782, 6213, 6215}, longest = 20, bar = true},
    {key = "banish", label = "Banish", ids = {710, 18647}, longest = 30, bar = true, marker = 5, click = true},
    {key = "enslave", label = "Enslave Demon", ids = {1098, 11725, 11726}},
    {key = "howl", label = "Howl of Terror", ids = {5484, 17928}, untargeted = true},
}
-- Raid markers by index, as /tm numbers them, and their chat codes.
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
-- The Focus box: shown while you have a live hostile focus, in the focus
-- panel's color, with your Fear on your focus. The tracker's focus red when
-- the tracker has no panel colors.
local FOCUS_RED = {0.9, 0.1, 0.1}
local FOCUS_SAMPLE = "Focus (sample)"
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
        scale = WTF.SanitizeControlScale(saved.scale), markers = {}, markersVersion = MARKERS_VERSION,
        plateTimers = saved.plateTimers ~= false, macros = saved.macros ~= false}
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

-- The unit showing this mob now: your focus or target, else its nameplate
-- (by GUID, else Core's plate memory, for plates whose GUID is secret). Not
-- mouseover: it changes with the pointer and has no event WTF rebinds on.
local function FindUnit(guid)
    if not guid then
        return nil
    end
    -- Focus first: it stays on the mob when its nameplate drops.
    for _, unit in ipairs({"focus", "target"}) do
        if ReadGUID(unit) == guid then
            return unit
        end
    end
    for index = 1, MAX_NAMEPLATE_UNITS do
        local unit = "nameplate" .. index
        if UnitExists(unit) and ReadGUID(unit) == guid then
            return unit
        end
    end
    return WTF.KnownPlate(guid)
end

-- A live mob you can attack. An answer the client keeps secret counts as yes
-- (player report: in client a Fear could get no bar; a secret "can attack"
-- must not drop the cast), and a secret "dead" as alive.
local function IsLiveHostile(unit)
    local canAttack = UnitCanAttack("player", unit)
    return (WTF.IsSecret(canAttack) or canAttack == true) and not IsDead(unit)
end

-- For /wtf debug_control: a value as text, never a secret's contents.
local function Said(value)
    return WTF.Describe(value)
end

-- A Banish locks your focus as it starts, when the cast's name is your
-- focus's, its GUID is readable, and it is a live hostile mob; else nothing.
local function LockFocusGUID(targetName)
    local guid = ReadGUID("focus")
    if guid and ReadName("focus") == targetName and IsLiveHostile("focus") then
        return guid
    end
end

-- The mob a cast sent at targetName goes to, as the cast starts (player
-- report: the same class of bug as the DoT tracker's, a mob found by name at
-- success time or on the wrong unit). The send gives only a name, so the
-- first live hostile unit with it, in the order WTF's own casts aim: your
-- focus ("! Banish", "! Seduction", the Banish row, and "! Fear" with a
-- focus), the mob under the mouse ("! Fear" without one), then your target.
-- Known limit: a plain spell-button cast at your target, while your focus
-- or the mob under the mouse has the same name, counts on that one.
-- A unit whose GUID is secret is skipped, unless it is a nameplate whose mob
-- Core's plate memory knows. Returns the GUID and the unit, and notes each
-- unit it looked at for /wtf debug_control.
local CAST_UNITS = {"focus", "mouseover", "target"}
for index = 1, MAX_NAMEPLATE_UNITS do
    CAST_UNITS[#CAST_UNITS + 1] = "nameplate" .. index
end

local function FindCastGUID(targetName)
    local seen = {}
    control.lastLook = seen
    for _, unit in ipairs(CAST_UNITS) do
        if UnitExists(unit) then
            local name = ReadName(unit)
            if name == targetName then
                local guid = ReadGUID(unit) or (unit:match("^nameplate") and WTF.plates[unit])
                local canAttack, dead = UnitCanAttack("player", unit), UnitIsDead(unit)
                seen[#seen + 1] = string.format("%s(attack=%s dead=%s guid=%s)", unit, Said(canAttack),
                    Said(dead), tostring(guid ~= nil))
                if guid and IsLiveHostile(unit) then
                    return guid, unit
                end
            elseif #seen < 6 and not unit:match("^nameplate") then
                seen[#seen + 1] = unit .. "(other name)"
            end
        end
    end
end

-- A control spell by ID, else by name (a rank the spell sets do not list yet).
local function KindOf(spellID)
    local spell = control.kinds[spellID]
    if spell then
        return spell
    end
    local name = C_Spell.GetSpellName(spellID)
    if not name then
        return nil
    end
    for _, kind in ipairs(WTF.CONTROL_SPELLS) do
        for _, id in ipairs(kind.ids) do
            if C_Spell.GetSpellName(id) == name then
                control.kinds[spellID] = kind
                if kind.bar then
                    control.ids[spellID] = true
                end
                return kind
            end
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

-- A row whose mob is gone while its secure click slot still shows (a slot
-- changes only out of combat) stays, dimmed, so no click area is invisible.
local SPENT_ALPHA = 0.45

local function Layout()
    local settings = WTF.db.control
    local sample = not WTF.db.locked
    anchor.mover:SetShown(sample)
    -- A Fear on your focus shows in the Focus box, not twice.
    local focusGUID = control.focusBox and ReadGUID("focus")
    if control.focusBox then
        local name = ReadName("focus")
        control.focusBox.display.name:SetText(sample and not name and FOCUS_SAMPLE
            or ("Focus: " .. (name or "")))
    end
    for index, row in ipairs(control.rows) do
        local holder = row.holder
        local spent = not row.guid and holder:IsVisible() and holder.mobName ~= nil
        row:SetAlpha(spent and SPENT_ALPHA or 1)
        if row.guid and not row.focusOnly and focusGUID and row.guid == focusGUID then
            row:Hide()
        elseif row.guid then
            row.name:SetText(row.mobName)
            row:SetShown(settings.enabled)
        elseif spent then
            row.name:SetText(holder.mobName)
            row:Show()
        elseif settings.enabled and sample and SAMPLES[index] then
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
    local box = control.focusBox
    if box then
        box:SetScale(settings.scale / 100)
        local fear = C_Spell.GetSpellName(WTF.CONTROL_SPELLS[1].ids[1])
        local known = settings.enabled and fear and KnowsAny()
        box:SetAttribute("type1", known and "macro" or nil)
        box:SetAttribute("macrotext1", known and WTF.RecastMacro(fear) or nil)
        -- Only unit conditions decide a secure frame's visibility in combat:
        -- while you have a live hostile focus (a Fear on it fills the bar),
        -- or always while frames are unlocked, to drag by.
        UnregisterStateDriver(box, "visibility")
        RegisterStateDriver(box, "visibility", not known and "hide"
            or not WTF.db.locked and "show" or "[@focus,exists,harm,nodead] show; hide")
    end
    for _, row in ipairs(control.rows) do
        row:SetScale(settings.scale / 100)
        local holder, name, spell = row.holder, row.clickName, row.clickSpell
        if name and spell then
            holder:SetAttribute("type1", "macro")
            holder:SetAttribute("macrotext1", WTF.RecastMacro(spell))
        else
            holder:SetAttribute("type1", nil)
            holder:SetAttribute("macrotext1", nil)
        end
        holder.mobName, holder.spellName = name, spell
        -- A click area only where there is something to recast, or to drag by.
        holder:SetShown((name ~= nil and spell ~= nil) or not WTF.db.locked)
    end
    Layout()
end

local function Forget(row)
    row.guid, row.mobName, row.clickName, row.clickSpell, row.token = nil, nil, nil, nil, nil
    row.focusOnly = nil
    Bind(row, nil)
    Layout()
    ApplyClicks()
end

-- The game's /tm for a unit, or nothing for no marker. A macro's /tm runs
-- from your key press, untainted, so it marks also in combat; AddOn code may
-- not call SetRaidTarget at all. "!" keeps a second press from toggling the
-- marker off.
function WTF.MarkLine(unit, marker)
    if type(marker) ~= "number" or marker <= 0 then
        return nil
    end
    return "/tm [@" .. unit .. ",harm,nodead,exists] !" .. marker
end

-- A row click: the same spell on your focus, and nothing else (no marker,
-- no targeting); with no focus it does nothing.
function WTF.RecastMacro(spell)
    return "/use [@focus,exists,harm,nodead] " .. spell
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
    if spell.click then
        row.clickName, row.clickSpell, row.clickKey = mobName, spellName, spell.key
        row.focusOnly = true
    end
    local token = {}
    row.token = token
    Bind(row, row.focusOnly and "focus" or FindUnit(guid))
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
        GameTooltip:SetText("Click: " .. holder.spellName .. " your focus again.", 1, 1, 1)
        GameTooltip:AddLine("No marker and no target change. With no focus it does nothing.", 0.7, 0.7, 0.7,
            true)
    else
        GameTooltip:SetText("Banish your focus (\"! Banish\"), then click its row to cast it again.", 0.7, 0.7,
            0.7)
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

-- The Focus box (John, 1.3.1): a fixed secure button above the rows whose
-- only click is "/use [@focus,exists,harm,nodead] Fear", so it can never fear
-- another mob, also when your focus changes in combat; with no focus it does
-- nothing. AddOn code cannot read auras in combat and a secure frame's
-- visibility can follow only unit conditions, so the box shows while you have
-- a live hostile focus (a state driver), never as an invisible click area: its
-- dim Fear line fills with the engine's bar while your Fear is on the focus.
-- Your Fear's spell IDs (the box is built before the plate timers' list).
local function FearOnly()
    local ids = {}
    for id, spell in pairs(control.kinds) do
        if spell.key == "fear" then
            ids[id] = true
        end
    end
    return ids
end

local function CreateFocusBox()
    local box = CreateFrame("Button", "WarlockToolsForeverControlFocus", anchor, "SecureActionButtonTemplate")
    box:SetSize(WIDTH, ROW_HEIGHT)
    box:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, ROW_GAP)
    box:RegisterForClicks("AnyUp", "AnyDown")
    box:SetAttribute("useOnKeyDown", false)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", StartDrag)
    box:SetScript("OnDragStop", StopDrag)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Click: Fear your focus again.", 1, 1, 1)
        GameTooltip:AddLine("Only your focus; with no focus it does nothing.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- What it shows: a child, so it shows and hides with the box.
    local display = CreateFrame("Frame", nil, box, "BackdropTemplate")
    display:SetAllPoints(box)
    display:EnableMouse(false)
    display:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2}})
    display:SetBackdropColor(BROWN[1], BROWN[2], BROWN[3], BROWN[4])
    local r, g, b = FOCUS_RED[1], FOCUS_RED[2], FOCUS_RED[3]
    if WTF.PanelColor and WTF.db.tracker and WTF.db.tracker.panelColors then
        r, g, b = WTF.PanelColor("focus")
    end
    display:SetBackdropBorderColor(r, g, b)
    display.name = display:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    display.name:SetPoint("TOPLEFT", PADDING, -4)
    display.name:SetWidth(WIDTH - PADDING * 2)
    display.name:SetJustifyH("LEFT")
    local line = display:CreateTexture(nil, "BACKGROUND")
    line:SetPoint("TOPLEFT", display, "TOPLEFT", PADDING, -HEADER)
    line:SetSize(WIDTH - PADDING * 2, LINE)
    line:SetColorTexture(LINE_BACKGROUND[1], LINE_BACKGROUND[2], LINE_BACKGROUND[3], LINE_BACKGROUND[4])
    local placeholder = display:CreateTexture(nil, "BACKGROUND", nil, 1)
    placeholder:SetTexture(C_Spell.GetSpellTexture(WTF.CONTROL_SPELLS[1].ids[1]))
    placeholder:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    placeholder:SetDesaturated(true)
    placeholder:SetAlpha(PLACEHOLDER_ALPHA)
    placeholder:SetSize(ICON, ICON)
    placeholder:SetPoint("LEFT", line, "LEFT", 1, 0)
    local container = CreateFrame("AuraContainer", nil, display, CONTAINER_TEMPLATE)
    container:SetPoint("TOPLEFT", display, "TOPLEFT")
    container:SetSize(1, 1)
    container:AddAuraSlot("fear", AURA_FILTER, {
        candidateFilters = {includeSpellIDs = FearOnly()},
        initializeFrame = SlotInitializer(display),
    })
    container:SetUnit("focus")
    box.display, box.container = display, container
    return box
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

-- WTF never calls SetRaidTarget: in client it raised ADDON_ACTION_FORBIDDEN
-- for AddOn code also out of combat (MTF's same guarded call, BugGrabber and
-- the taint log), so the marker comes only from the game's /tm in "! Banish"
-- (WTF.MarkLine), which runs from your key press.

-- %M: the marker's chat code for a Banish at your focus (the mob "! Banish"
-- marks), else nothing.
local function MarkerCode(spell, atFocus)
    if not atFocus then
        return ""
    end
    local index = spell.marker and WTF.db.control.markers[spell.key] or 0
    for _, marker in ipairs(WTF.RAID_MARKERS) do
        if marker.index == index then
            return marker.code or ""
        end
    end
    return ""
end

-- At the start of a cast (author-approved), as the other group messages go.
local function AnnounceCast(spell, targetName, atFocus)
    local settings = WTF.db.announce
    local now = GetTime()
    local last = control.lastAnnounce[spell.key]
    if not settings[spell.key .. "Group"] or (last and now - last < ANNOUNCE_REPEAT_SECONDS) then
        return
    end
    -- With no marker, %M goes with the space before it.
    local code = MarkerCode(spell, atFocus)
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
    local spell = KindOf(spellID)
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
    local guid, unit
    if spell.click then
        guid = LockFocusGUID(target)
        unit = guid and "focus"
        control.lastLook = {"focus only"}
    else
        guid, unit = FindCastGUID(target)
    end
    control.lastSent = {spellID = spellID, target = target, unit = unit, locked = guid ~= nil,
        look = table.concat(control.lastLook or {}, " ")}
    AnnounceCast(spell, target, spell.click and guid ~= nil)
    if not spell.bar or not WTF.db.control.enabled then
        return
    end
    -- The mob's plate, while it is your focus or target, for later binding.
    WTF.LearnPlates()
    control.casts[castGUID] = {target = target, spellID = spellID, guid = guid}
    -- A pull's Fear or Banish starts out of combat and lands in it: set the
    -- click now, while the game still allows it.
    if spell.click and guid and not InCombatLockdown() then
        local row = RowFor(guid, target)
        if row and not row.guid then
            row.clickName, row.clickSpell, row.clickKey = target, C_Spell.GetSpellName(spellID), spell.key
            control.casts[castGUID].row = row
            ApplyClicks()
        end
    end
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
    -- Only the mob locked as the cast started (hostile then); never one found
    -- by name now, which after a tab or a mouse move may be another mob.
    local guid = cast.guid
    if not guid then
        control.lastLanded = "no mob locked as it started"
        return
    end
    local unit = FindUnit(guid)
    if unit and IsDead(unit) then
        control.lastLanded = "the mob was dead"
        return
    end
    local spell = control.kinds[cast.spellID]
    local row = RowFor(guid, cast.target)
    if row then
        Track(row, guid, cast.target, spell, C_Spell.GetSpellName(cast.spellID))
        for index, each in ipairs(control.rows) do
            if each == row then
                control.lastLanded = "row " .. index .. " bound to " .. tostring(row.boundUnit)
            end
        end
    else
        control.lastLanded = "no free row"
    end
end

local function Rebind()
    for _, row in ipairs(control.rows) do
        if row.focusOnly then
            -- Your focus is no longer the banished mob: another mob, or none.
            -- A focus whose GUID is secret stays (it cannot be told apart).
            local guid = ReadGUID("focus")
            if not UnitExists("focus") or (guid and guid ~= row.guid) or IsDead("focus") then
                Forget(row)
            end
        elseif row.guid then
            local unit = FindUnit(row.guid)
            if unit and IsDead(unit) then
                Forget(row)
            else
                Bind(row, unit)
            end
        end
    end
end

-- Macros ---------------------------------------------------------------------
-- (author-approved, after the author's own): for your action bars, a macro
-- per single-target control spell you know. It sets your focus to the hostile
-- mob under the mouse (or, out of combat, your target) and casts on your
-- focus, so the macro, the bar's click, and the moon all agree on one mob.
-- Seduction is your Succubus's or Incubus's, learned from a Grimoire: its
-- macro appears once your summoned demon knows it (the pet spellbook, by ID
-- or by name, so either demon counts), stays after you dismiss it, and does
-- nothing unless your pet is a Succubus or an Incubus.
-- "! Banish" marks its focus with the game's /tm before the cast (with "!",
-- so a second press never toggles it off): AddOn code may not call
-- SetRaidTarget, and a macro's /tm runs from your key press. Its marker is the
-- Banish marker setting; set to None, the line goes. "! Fear" is the author's
-- own juggling macro: it Fears your focus when you have one, else the mob
-- under the mouse (a feared mob's nameplate as its timer runs out), else your
-- target (author-approved). Inverted in 1.3.1 (John: "set focus by default,
-- shift fears a mob without changing focus"): a plain press makes the mob
-- under the mouse (else your target) your focus and fears it; with Shift it
-- fears the mob under the mouse (else your target) and keeps your focus.
-- Fear has no marker setting, so the macro has no /tm.

local CONTROL_MACROS = {
    {name = "! Fear", spell = 5782, known = {5782, 6213, 6215}, mouseover = true},
    {name = "! Banish", spell = 710, known = {710, 18647}, marker = "banish"},
    {name = "! Seduction", spell = 6358, pet = true, condition = ",pet:Succubus/Incubus"},
}
local FOCUS_LINE = "/focus [@mouseover,harm,nodead][nocombat,harm,nodead]"
-- "! Fear": without Shift, the mob under the mouse, else your target, becomes the focus.
local FEAR_FOCUS_LINE = "/focus [nomod:shift,@mouseover,harm,nodead][nomod:shift,harm,nodead]"
local FEAR_CAST = "/use [mod:shift,@mouseover,harm,nodead][mod:shift,harm,nodead][@focus,exists,harm,nodead] "

local function KnowsAnyOf(ids)
    if type(C_SpellBook) ~= "table" or type(C_SpellBook.IsSpellKnown) ~= "function" then
        return false
    end
    for _, id in ipairs(ids) do
        if C_SpellBook.IsSpellKnown(id) == true then
            return true
        end
    end
    return false
end

-- A pet spell your summoned demon knows: by ID, else by name in the pet
-- spellbook (Forever's Incubus may carry its own ID). Nothing without a pet.
local function PetKnows(spellID)
    if type(C_SpellBook) ~= "table" or type(C_SpellBook.IsSpellKnown) ~= "function" then
        return false
    end
    if C_SpellBook.IsSpellKnown(spellID, true) == true then
        return true
    end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    local name = C_Spell.GetSpellName(spellID)
    if not bank or not name or type(C_SpellBook.HasPetSpells) ~= "function" then
        return false
    end
    local count = C_SpellBook.HasPetSpells()
    for index = 1, (type(count) == "number" and count or 0) do
        local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
        if type(item) == "table" and item.name == name then
            return true
        end
    end
    return false
end

local function MacroKnown(macro)
    if macro.pet then
        return PetKnows(macro.spell)
    end
    return KnowsAnyOf(macro.known)
end

function WTF.ControlMacroBody(macro)
    local spell = C_Spell.GetSpellName(macro.spell)
    if not spell then
        return nil
    end
    if macro.mouseover then
        return "#showtooltip " .. spell .. "\n" .. FEAR_FOCUS_LINE .. "\n" .. FEAR_CAST .. spell
    end
    local lines = {"#showtooltip " .. spell, FOCUS_LINE}
    lines[#lines + 1] = WTF.MarkLine("focus", macro.marker and WTF.db.control.markers[macro.marker])
    lines[#lines + 1] = "/use [@focus,exists,harm,nodead" .. (macro.condition or "") .. "] " .. spell
    return table.concat(lines, "\n")
end

-- Out of combat only; turning the macros off deletes them.
function WTF.ApplyControlMacros()
    if InCombatLockdown() then
        control.macrosDirty = true
        return
    end
    control.macrosDirty = false
    if not WTF.CharacterMacrosAvailable() then
        return
    end
    for _, macro in ipairs(CONTROL_MACROS) do
        local body = WTF.ControlMacroBody(macro)
        if WTF.db.control.macros and body and MacroKnown(macro) then
            WTF.WriteCharacterMacro(macro.name, body)
        elseif not WTF.db.control.macros then
            WTF.DeleteCharacterMacro(macro.name)
        end
    end
end

-- Fear timers on nameplates ------------------------------------------------
-- (author-approved): a thin bar under each nameplate that drains with your
-- Fear's time left on that mob, so you see which feared mob is about to
-- break and can click its nameplate to target it. Like the DoT dots, an
-- engine AuraContainer bound to the plate's unit draws it, only while your
-- Fear is up, and WTF never reads the aura. Plates are pooled: a mob that
-- leaves plate range and comes back may get another plate and token, so a
-- timer attaches on NAME_PLATE_UNIT_ADDED and shows the real time left.

local PLATE_TIMER_WIDTH = 60
local PLATE_TIMER_HEIGHT = 5
local PLATE_TIMER_GAP = 2
local plates = {byUnit = {}, free = {}, all = {}}
WTF.fearPlateTimers = plates.byUnit

local function FearIDs()
    local ids = {}
    for id, spell in pairs(control.kinds) do
        if spell.key == "fear" then
            ids[id] = true
        end
    end
    return ids
end

local function PlateTimerInitializer(timer)
    return function(button)
        button:ClearAllPoints()
        button:SetAllPoints(timer)
        button:SetMouseClickEnabled(false)
        button:SetMouseMotionEnabled(false)
        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0, 0, 0, 0.7)
        local bar = CreateFrame("StatusBar", nil, button)
        bar:SetAllPoints()
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetStatusBarColor(BAR_COLOR[1], BAR_COLOR[2], BAR_COLOR[3])
        local timeLeft = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timeLeft:SetPoint("LEFT", bar, "RIGHT", 3, 0)
        local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
        button:SetDurationBar(bar, {direction = direction})
        button:SetDurationText(timeLeft, {})
        timer.bar = bar
    end
end

local function CreatePlateTimer()
    local timer = CreateFrame("Frame", nil, UIParent)
    timer:SetSize(PLATE_TIMER_WIDTH, PLATE_TIMER_HEIGHT)
    timer:EnableMouse(false)
    local container = CreateFrame("AuraContainer", nil, timer, CONTAINER_TEMPLATE)
    container:SetPoint("TOPLEFT")
    container:SetSize(1, 1)
    container:AddAuraSlot("fear", AURA_FILTER, {
        candidateFilters = {includeSpellIDs = FearIDs()},
        initializeFrame = PlateTimerInitializer(timer),
    })
    timer.container = container
    plates.all[#plates.all + 1] = timer
    return timer
end

local function DetachTimer(unit)
    local timer = plates.byUnit[unit]
    if not timer then
        return
    end
    plates.byUnit[unit] = nil
    timer.container:SetUnit("none")
    timer:Hide()
    timer:SetParent(UIParent)
    plates.free[#plates.free + 1] = timer
end

local function AttachTimer(unit)
    local settings = WTF.db.control
    if not settings.enabled or not settings.plateTimers or type(C_NamePlate) ~= "table" then
        return
    end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or plate:IsForbidden() then
        return
    end
    DetachTimer(unit)
    local timer = table.remove(plates.free) or CreatePlateTimer()
    timer:SetParent(plate)
    timer:ClearAllPoints()
    timer:SetPoint("TOP", plate, "BOTTOM", 0, -PLATE_TIMER_GAP)
    plates.byUnit[unit] = timer
    timer.container:SetUnit(unit)
    timer.container:UpdateAllAuras()
    timer:Show()
end

local function RefreshPlateTimers()
    for unit in pairs(plates.byUnit) do
        DetachTimer(unit)
    end
    for index = 1, MAX_NAMEPLATE_UNITS do
        local unit = "nameplate" .. index
        if UnitExists(unit) then
            AttachTimer(unit)
        end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit, first, second, third)
    if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        if not WTF.IsSecret(unit) then
            WTF.ForgetPlate(unit)
        end
        if event == "NAME_PLATE_UNIT_ADDED" then
            AttachTimer(unit)
            if not WTF.IsSecret(unit) then
                WTF.LearnPlate(unit)
            end
        else
            DetachTimer(unit)
        end
        Rebind()
        return
    end
    if event == "UNIT_PET" then
        -- A demon summoned: its spells, Seduction among them, can be read now.
        WTF.ApplyControlMacros()
        return
    end
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
        -- By GUID: the death can come through any unit that shows the mob.
        local guid = not WTF.IsSecret(unit) and ReadGUID(unit)
        for _, row in ipairs(control.rows) do
            if row.guid and row.guid == guid and IsDead(unit) then
                Forget(row)
            end
        end
    elseif event == "SPELLS_CHANGED" then
        BuildSpellSets()
        for _, row in ipairs(control.rows) do
            row.container:SetAuraSlotCandidateFilters("control", {includeSpellIDs = control.ids})
        end
        for _, timer in ipairs(plates.all) do
            timer.container:SetAuraSlotCandidateFilters("fear", {includeSpellIDs = FearIDs()})
        end
        if control.focusBox then
            control.focusBox.container:SetAuraSlotCandidateFilters("fear", {includeSpellIDs = FearIDs()})
        end
        ApplyClicks()
        WTF.ApplyControlMacros()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if control.placeDirty then
            control.placeDirty = false
            Place()
        end
        if control.macrosDirty then
            WTF.ApplyControlMacros()
        end
        -- A click set as a cast started, for a cast that never landed, goes.
        for _, row in ipairs(control.rows) do
            if not row.guid then
                row.clickName, row.clickSpell = nil, nil
            end
        end
        ApplyClicks()
    else
        -- Your target or focus changed: learn its plate before rebinding.
        WTF.LearnPlates()
        Rebind()
        Layout()
    end
end)

function WTF.RefreshControl()
    if not control.available then
        return
    end
    Layout()
    ApplyClicks()
    RefreshPlateTimers()
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
    control.focusBox = CreateFocusBox()
    WTF.controlRows = control.rows
    WTF.controlFocusBox = control.focusBox
    Place()
    control.available = true
    for _, event in ipairs({"PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "SPELLS_CHANGED", "UNIT_HEALTH"}) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_PET"}) do
        events:RegisterUnitEvent(event, "player")
    end
    Layout()
    ApplyClicks()
    RefreshPlateTimers()
    WTF.ApplyControlMacros()
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
    local sent = control.lastSent
    if sent then
        WTF.Report(string.format("debug_control lastSent spell=%d target=%s unit=%s locked=%s looked=%s",
            sent.spellID, sent.target, tostring(sent.unit), tostring(sent.locked), sent.look))
    end
    WTF.Report("debug_control lastLanded " .. tostring(control.lastLanded or "nothing yet"))
    for index, row in ipairs(control.rows) do
        WTF.Report(string.format("debug_control row %d mob=%s unit=%s click=%s macro=%s", index,
            tostring(row.mobName), tostring(row.boundUnit), tostring(row.holder:IsShown()),
            (tostring(row.holder:GetAttribute("macrotext1")):gsub("\n", " | "))))
    end
    local attached = 0
    for _ in pairs(plates.byUnit) do
        attached = attached + 1
    end
    WTF.Report(string.format("debug_control plateTimers=%s attached=%d", tostring(WTF.db.control.plateTimers),
        attached))
    -- For the Seduction macro: your demon's family and whether it knows Seduction.
    local family = type(UnitCreatureFamily) == "function" and UnitCreatureFamily("pet")
    WTF.Report(string.format("debug_control pet=%s seduction=%s", tostring(family), tostring(PetKnows(6358))))
end
