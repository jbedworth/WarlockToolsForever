local _, WTF = ...

-- DoT tracker. Two pinned rows, your target (purple outline) and your focus
-- (red outline), each shown only while that unit is a live hostile; then a
-- list of the other mobs you DoTed. Each row has a slot per spell family:
-- Corruption, Immolate, Siphon Life, Bane, Curse, and Fear and control, with
-- bars in each family's color.
--
-- On Forever, AddOn code cannot read enemy auras in combat, so each row holds
-- a Blizzard AuraContainer: the engine reads the row's unit and draws the
-- icon, sweep, countdown, and bar into regions WTF provides. WTF never sees
-- the timers; it knows only which mobs you cast on, from your own (readable)
-- cast events. A dimmed icon sits behind each slot, so a missing or expired
-- spell shows dim.
--
-- Two themes (author-approved): Compact, a row with the name and an icon per
-- spell; and Bars, a block per mob with its name above one bar line per spell
-- you know, each draining like the Cooldown Manager's bars. Changing the theme
-- rebuilds the rows, out of combat.
--
-- The pinned rows' slots are secure buttons that recast on @target or @focus.
-- Secure buttons cannot change target in combat and secure code cannot tell
-- mobs apart, so list rows only display. Pinned rows sit in a secure anchor
-- the game shows and hides by state drivers; the list is an ordinary frame
-- below it, free to change in combat.

local MAX_ROWS = 8
local ROW_HEIGHT = 30
-- Bar theme: the name line, then one line per spell: an icon and a bar with
-- the spell's name and time left.
local BAR_HEADER = 18
local BAR_LINE = 16
local BAR_LINE_GAP = 2
local BAR_ICON = 14
local BAR_BACKGROUND = {0.1, 0.1, 0.1, 0.6}
-- The pinned rows' outline: a solid line this thick, this far outside the
-- row, and the extra space below each pinned row that keeps it clear of the next.
local OUTLINE = 3
local OUTLINE_GAP = 2
local PINNED_SPACING = OUTLINE + OUTLINE_GAP + 2
local NAME_WIDTH = 110
local SLOT_SIZE = 22
local SLOT_GAP = 6
local PADDING = 6
-- Seconds a list row stays without a unit to bind (its nameplate out of sight).
local UNSEEN_SECONDS = 10
local MAX_NAMEPLATE_UNITS = 40
local AURA_FILTER = "HARMFUL|PLAYER"
local CONTAINER_TEMPLATE = "CustomAuraContainerTemplate"
local BROWN = {0.28, 0.16, 0.07, 0.85}
local FOCUS_RED = {0.9, 0.1, 0.1}
local WARLOCK_FALLBACK = {0.53, 0.53, 0.93}
local IDLE_BORDER = {0.45, 0.35, 0.2}
local PLACEHOLDER_ALPHA = 0.3
local DEFAULT_POINT = {"CENTER", "CENTER", -260, 120}
local SAMPLE_NAMES = {target = "Target (sample)", focus = "Focus (sample)",
    list = {"Another mob (sample)", "One more mob (sample)"}}
local PINNED = {
    target = {unit = "target", driver = "[@target,harm,nodead] show; hide"},
    focus = {unit = "focus", driver = "[@focus,exists,harm,nodead] show; hide"},
}

-- Every Warlock spell family that leaves a debuff on an enemy, per Forever's
-- spell list and talents, except single-target channels (Drain Life, Drain
-- Soul, Drain Mana, Wrack; author-approved). Classic rank IDs; WTF adds every
-- spellbook spell with the same name, so Forever's own ranks count too. Banes
-- are new on Forever and are matched by name only. A pinned slot recasts "cast",
-- or for families with "lastUsed" the last one you cast (else "cast").
-- Display order (author-approved): Curse, Bane, the other DoTs, then control.
local SLOTS = {
    -- Weakness, Recklessness, Elements, Shadow, Tongues, and Exhaustion. In
    -- client the curse debuff did not match these IDs (Forever reworked
    -- curses), so the slot matches your Curse-type debuffs instead, without
    -- your Banes. The IDs still identify your curse casts.
    {key = "curse", lastUsed = "lastCurse", dispelType = "Curse", excludeSlot = "bane",
        ids = {702, 1108, 6205, 7646, 11707, 11708, 704, 7658, 7659, 11717, 1490, 11721, 11722, 17862, 17937,
            1714, 11719, 18223}},
    -- Agony, Doom, and Havoc: one Bane per target.
    {key = "bane", lastUsed = "lastBane", cast = 980, ids = {980, 1014, 6217, 11711, 11712, 11713, 603},
        names = {"Bane of Agony", "Bane of Doom", "Bane of Havoc"}},
    {key = "corruption", cast = 172, ids = {172, 6222, 6223, 7648, 11671, 11672, 25311}},
    {key = "immolate", cast = 348, ids = {348, 707, 1094, 2941, 11665, 11667, 11668, 25309}},
    {key = "siphon", cast = 18265, ids = {18265, 18879, 18880, 18881}},
    -- Fear, Howl of Terror, Death Coil, and Banish.
    {key = "control", lastUsed = "lastControl", cast = 5782, ids = {5782, 6213, 6215, 5484, 17928,
        6789, 17925, 17926, 710, 18647}},
}

local tracker = {rows = {}, pinned = {}, casts = {}, spellSlots = {}, known = {}, slotKnown = {},
    available = false}

local function ClassColor()
    if type(C_ClassColor) == "table" and type(C_ClassColor.GetClassColor) == "function" then
        local color = C_ClassColor.GetClassColor("WARLOCK")
        if color then
            return color.r, color.g, color.b
        end
    end
    return WARLOCK_FALLBACK[1], WARLOCK_FALLBACK[2], WARLOCK_FALLBACK[3]
end

function WTF.CheckTrackerCapabilities()
    if type(C_XMLUtil) ~= "table" or type(C_XMLUtil.GetTemplateInfo) ~= "function" then
        return false, "C_XMLUtil.GetTemplateInfo"
    end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    if not C_XMLUtil.GetTemplateInfo(CONTAINER_TEMPLATE) then
        return false, CONTAINER_TEMPLATE
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

-- Spellbook spells by name: every rank listed, and the names the player has
-- learned. The spellbook also lists spells learned later (FutureSpell), which
-- must not count as known.
local function SpellbookIDsByName()
    local byName, learned = {}, {}
    if type(C_SpellBook) ~= "table" or type(C_SpellBook.GetNumSpellBookSkillLines) ~= "function" then
        return byName, learned
    end
    local learnedType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if type(lineInfo) == "table" then
            for index = lineInfo.itemIndexOffset + 1, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
                if type(item) == "table" and type(item.spellID) == "number" and type(item.name) == "string" then
                    byName[item.name] = byName[item.name] or {}
                    byName[item.name][#byName[item.name] + 1] = item.spellID
                    if learnedType == nil or item.itemType == learnedType then
                        learned[item.name] = true
                    end
                end
            end
        end
    end
    return byName, learned
end

-- Spell ID sets per slot, which slot a cast spell ID belongs to, and which
-- spell names the player knows.
local function BuildSpellSets()
    local byName, learned = SpellbookIDsByName()
    local sets = {}
    tracker.spellSlots = {}
    tracker.known = learned
    for _, slot in ipairs(SLOTS) do
        local set, names = {}, {}
        for _, id in ipairs(slot.ids) do
            set[id] = true
            local name = C_Spell.GetSpellName(id)
            if name then
                names[name] = true
            end
        end
        for _, name in ipairs(slot.names or {}) do
            names[name] = true
        end
        for name in pairs(names) do
            for _, id in ipairs(byName[name] or {}) do
                set[id] = true
            end
        end
        for id in pairs(set) do
            tracker.spellSlots[id] = slot.key
        end
        sets[slot.key] = set
        local known = false
        for name in pairs(names) do
            known = known or tracker.known[name] == true
        end
        tracker.slotKnown[slot.key] = known
    end
    tracker.sets = sets
end

-- The bars are WTF's own regions, so they can change color at any time.
function WTF.ApplyTrackerColors()
    local function Recolor(row)
        for index, slot in ipairs(SLOTS) do
            if row.bars[index] then
                row.bars[index]:SetStatusBarColor(WTF.SlotColor(slot.key))
            end
        end
    end
    for _, row in ipairs(tracker.rows) do
        Recolor(row)
    end
    for _, row in pairs(tracker.pinned) do
        Recolor(row)
    end
end

-- The engine's candidate filter for a slot: its spell IDs, or for a slot
-- matched by debuff type, that type without another slot's spell IDs. Shared
-- with the nameplate dots.
function WTF.TrackerCandidateFilters(key)
    if not tracker.sets then
        return nil
    end
    for _, slot in ipairs(SLOTS) do
        if slot.key == key then
            if slot.dispelType then
                return {includeDispelTypes = {[slot.dispelType] = true},
                    excludeSpellIDs = tracker.sets[slot.excludeSlot]}
            end
            return {includeSpellIDs = tracker.sets[key]}
        end
    end
end

function WTF.TrackerKnowsSlot(key)
    return tracker.slotKnown[key] == true
end

local function SlotIcon(slot)
    for _, id in ipairs(slot.ids) do
        local texture = C_Spell.GetSpellTexture(id)
        if texture then
            return texture
        end
    end
end

local function IsCompact()
    return tracker.theme ~= "bars"
end

-- The slots a row shows, as SLOTS indexes: one for each spell family you
-- know, in both themes (author-approved), or all of them while you know none.
local function ShownSlots()
    local shown = {}
    for index, slot in ipairs(SLOTS) do
        if tracker.slotKnown[slot.key] then
            shown[#shown + 1] = index
        end
    end
    if #shown == 0 then
        for index in ipairs(SLOTS) do
            shown[index] = index
        end
    end
    return shown
end

local function RowWidth()
    if IsCompact() then
        return PADDING * 2 + NAME_WIDTH + #tracker.shown * (SLOT_SIZE + SLOT_GAP)
    end
    return PADDING * 2 + NAME_WIDTH + #SLOTS * (SLOT_SIZE + SLOT_GAP)
end

local function RowHeight()
    if IsCompact() then
        return ROW_HEIGHT
    end
    return BAR_HEADER + #tracker.shown * (BAR_LINE + BAR_LINE_GAP) + PADDING
end

local function RowStep()
    return RowHeight() + 2
end

-- Places a slot's region at a display position in a row: an icon right of
-- the name (compact), or a line under the name (bars).
local function PlaceSlot(region, row, position)
    region:ClearAllPoints()
    if IsCompact() then
        region:SetPoint("LEFT", row, "LEFT", PADDING + NAME_WIDTH + (position - 1) * (SLOT_SIZE + SLOT_GAP), 0)
        region:SetSize(SLOT_SIZE, SLOT_SIZE)
    else
        region:SetPoint("TOPLEFT", row, "TOPLEFT", PADDING, -(BAR_HEADER + (position - 1) * (BAR_LINE + BAR_LINE_GAP)))
        region:SetSize(RowWidth() - PADDING * 2, BAR_LINE)
    end
end

local function SlotLabel(key)
    for _, slot in ipairs(WTF.DOT_SLOTS) do
        if slot.key == key then
            return slot.label
        end
    end
end

-- Builds one engine slot button. Runs inside the engine's initializer, the
-- only time WTF may place or change the button: afterwards the engine denies
-- AddOn access while auras are secret.
local function BarInitializer(row, index, position)
    return function(button)
        PlaceSlot(button, row, position)
        button:SetMouseClickEnabled(false)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(BAR_ICON, BAR_ICON)
        icon:SetPoint("LEFT", 1, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local bar = CreateFrame("StatusBar", nil, button)
        bar:SetPoint("TOPLEFT", button, "TOPLEFT", BAR_ICON + 4, 0)
        bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetStatusBarColor(WTF.SlotColor(SLOTS[index].key))
        row.bars[index] = bar
        local spellName = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        spellName:SetPoint("LEFT", 4, 0)
        spellName:SetJustifyH("LEFT")
        local timeLeft = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timeLeft:SetPoint("RIGHT", -4, 0)
        button:SetIcon(icon)
        local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
        button:SetDurationBar(bar, {direction = direction})
        button:SetSpellName(spellName)
        button:SetDurationText(timeLeft, {})
    end
end

local function SlotInitializer(row, index, position)
    if not IsCompact() then
        return BarInitializer(row, index, position)
    end
    return function(button)
        PlaceSlot(button, row, position)
        button:SetMouseClickEnabled(false)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cooldown:SetAllPoints(button)
        cooldown:SetHideCountdownNumbers(true)
        local bar = CreateFrame("StatusBar", nil, button)
        bar:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -1)
        bar:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -1)
        bar:SetHeight(3)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetStatusBarColor(WTF.SlotColor(SLOTS[index].key))
        row.bars[index] = bar
        local textHolder = CreateFrame("Frame", nil, button)
        textHolder:SetAllPoints(button)
        textHolder:SetFrameLevel(cooldown:GetFrameLevel() + 1)
        local text = textHolder:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        text:SetPoint("CENTER", 0, 0)
        button:SetIcon(icon)
        button:SetDurationCooldown(cooldown)
        local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
        button:SetDurationBar(bar, {direction = direction})
        button:SetDurationText(text, {})
    end
end

local function CreateRow(parent, unit)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetSize(RowWidth(), RowHeight())
    row:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2}})
    row:SetBackdropColor(BROWN[1], BROWN[2], BROWN[3], BROWN[4])
    row:SetBackdropBorderColor(IDLE_BORDER[1], IDLE_BORDER[2], IDLE_BORDER[3])
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if IsCompact() then
        row.name:SetPoint("LEFT", PADDING, 0)
        row.name:SetWidth(NAME_WIDTH - 4)
    else
        row.name:SetPoint("TOPLEFT", PADDING, -4)
        row.name:SetWidth(RowWidth() - PADDING * 2)
    end
    row.name:SetJustifyH("LEFT")
    row.bars = {}
    -- Behind each live slot: a dim icon (compact), or a dim line with the
    -- icon and the spell family's name (bars), so a missing spell shows.
    for position, slotIndex in ipairs(tracker.shown) do
        local slot = SLOTS[slotIndex]
        local placeholder = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        placeholder:SetTexture(SlotIcon(slot))
        placeholder:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        placeholder:SetDesaturated(true)
        placeholder:SetAlpha(PLACEHOLDER_ALPHA)
        if IsCompact() then
            PlaceSlot(placeholder, row, position)
        else
            local line = row:CreateTexture(nil, "BACKGROUND")
            PlaceSlot(line, row, position)
            line:SetColorTexture(BAR_BACKGROUND[1], BAR_BACKGROUND[2], BAR_BACKGROUND[3], BAR_BACKGROUND[4])
            placeholder:SetSize(BAR_ICON, BAR_ICON)
            placeholder:SetPoint("LEFT", line, "LEFT", 1, 0)
            local label = row:CreateFontString(nil, "BORDER", "GameFontDisableSmall")
            label:SetPoint("LEFT", line, "LEFT", BAR_ICON + 8, 0)
            label:SetText(SlotLabel(slot.key))
        end
    end
    local container = CreateFrame("AuraContainer", nil, row, CONTAINER_TEMPLATE)
    container:SetPoint("TOPLEFT", row, "TOPLEFT")
    container:SetSize(1, 1)
    for position, slotIndex in ipairs(tracker.shown) do
        local slot = SLOTS[slotIndex]
        container:AddAuraSlot(slot.key, AURA_FILTER, {
            candidateFilters = WTF.TrackerCandidateFilters(slot.key),
            initializeFrame = SlotInitializer(row, slotIndex, position),
        })
    end
    row.container = container
    if unit then
        container:SetUnit(unit)
        container:UpdateAllAuras()
        row.boundUnit = unit
    end
    return row
end

-- Pinned rows -----------------------------------------------------------------

local function SlotSpellName(slot)
    local name = slot.lastUsed and WTF.db.tracker[slot.lastUsed]
    if not name and slot.cast then
        name = C_Spell.GetSpellName(slot.cast)
    end
    if name and tracker.known[name] then
        return name
    end
end

-- Pinned slot clicks cast by name, so the game uses the highest rank known.
-- Secure attributes change only out of combat.
local function ApplyCastButtons()
    if InCombatLockdown() then
        tracker.castsDirty = true
        return
    end
    tracker.castsDirty = false
    for _, pinned in pairs(tracker.pinned) do
        for slotIndex, button in pairs(pinned.casts) do
            local name = SlotSpellName(SLOTS[slotIndex])
            button:SetAttribute("type1", name and "macro" or nil)
            button:SetAttribute("macrotext1", name
                and ("/use [@" .. pinned.unit .. (pinned.unit == "focus" and ",exists" or "") .. ",harm,nodead] " .. name) or nil)
            button.spellName = name
        end
    end
end

local function ShowCastTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    if button.spellName then
        GameTooltip:SetText("Click: cast " .. button.spellName .. " on your " .. button.unit .. ".", 1, 1, 1)
    else
        GameTooltip:SetText("You know no spell for this slot yet; it recasts the last one you used.",
            0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

-- Dragging and snapping: Layout.lua. The rows drag the anchor.
local function StartDrag()
    WTF.BeginDrag(tracker.anchor)
end

local function StopDrag()
    WTF.EndDrag(tracker.anchor)
end

-- Pinned rows: the target on top, the focus below it past the target's outline.
local function PinnedOffset(key)
    return key == "target" and 0 or (RowStep() + PINNED_SPACING)
end

local function CreatePinnedRow(key)
    local pinned = PINNED[key]
    local row = CreateRow(tracker.anchor, pinned.unit)
    row:SetPoint("TOPLEFT", tracker.anchor, "TOPLEFT", 0, -PinnedOffset(key))
    row.unit = pinned.unit
    row.casts = {}
    for position, slotIndex in ipairs(tracker.shown) do
        local button = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
        PlaceSlot(button, row, position)
        button:SetFrameLevel(row.container:GetFrameLevel() + 10)
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("useOnKeyDown", false)
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button.unit = pinned.unit
        button:SetScript("OnEnter", ShowCastTooltip)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.casts[slotIndex] = button
    end
    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", StartDrag)
    row:SetScript("OnDragStop", StopDrag)
    -- Target: warlock purple; focus: red (author-approved), same outline.
    local r, g, b
    if key == "target" then
        r, g, b = ClassColor()
    else
        r, g, b = FOCUS_RED[1], FOCUS_RED[2], FOCUS_RED[3]
    end
    row:SetBackdropBorderColor(r, g, b)
    local outline = CreateFrame("Frame", nil, row, "BackdropTemplate")
    local inset = OUTLINE + OUTLINE_GAP
    outline:SetPoint("TOPLEFT", -inset, inset)
    outline:SetPoint("BOTTOMRIGHT", inset, -inset)
    outline:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = OUTLINE})
    outline:SetBackdropBorderColor(r, g, b)
    outline:EnableMouse(false)
    row.outline = outline
    return row
end

local function IsLiveHostile(unit)
    if not UnitExists(unit) then
        return false
    end
    local canAttack, dead = UnitCanAttack("player", unit), UnitIsDead(unit)
    return not WTF.IsSecret(canAttack) and canAttack == true and not (not WTF.IsSecret(dead) and dead == true)
end

local function ReadName(unit)
    local name = UnitName(unit)
    if WTF.IsSecret(name) then
        return ""
    end
    return name or ""
end

-- Out of combat only: placeholders replace the state drivers with plain Show,
-- and the module switch hides the anchor.
local function ApplyPinnedVisibility()
    if InCombatLockdown() then
        tracker.visibilityDirty = true
        return
    end
    tracker.visibilityDirty = false
    local settings = WTF.db.tracker
    for key, row in pairs(tracker.pinned) do
        -- The row itself takes the mouse only to be dragged; its slots always do.
        row:EnableMouse(not WTF.db.locked)
        UnregisterStateDriver(row, "visibility")
        if settings.placeholders then
            row:Show()
            row.name:SetText(SAMPLE_NAMES[key])
        else
            RegisterStateDriver(row, "visibility", PINNED[key].driver)
        end
    end
    if settings.enabled then
        tracker.anchor:Show()
    else
        tracker.anchor:Hide()
    end
end

-- Binding list rows -------------------------------------------------------------

local function ReadGUID(unit)
    local guid = UnitGUID(unit)
    if WTF.IsSecret(guid) or type(guid) ~= "string" then
        return nil
    end
    return guid
end

-- The unit token showing this mob now: its nameplate, else target or focus.
local function FindUnit(guid)
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

local function Bind(row, unit)
    local wanted = unit or "none"
    if row.boundUnit == wanted then
        return
    end
    row.boundUnit = wanted
    row.container:SetUnit(wanted)
    row.container:UpdateAllAuras()
end

local function IsDead(unit)
    local dead = UnitIsDead(unit)
    return not WTF.IsSecret(dead) and dead == true
end

local Layout

local function RemoveRow(row)
    row.guid, row.mobName, row.unseenSince = nil, nil, nil
    Bind(row, nil)
    Layout()
end

local function ScheduleUnseenCheck()
    C_Timer.After(UNSEEN_SECONDS + 0.1, function()
        local now = GetTime()
        for _, row in ipairs(tracker.rows) do
            if row.guid and row.unseenSince and now - row.unseenSince >= UNSEEN_SECONDS then
                RemoveRow(row)
            end
        end
    end)
end

-- Rebinds every list row; drops rows whose mob is dead.
local function RefreshBindings()
    for _, row in ipairs(tracker.rows) do
        if row.guid then
            local unit = FindUnit(row.guid)
            if unit and IsDead(unit) then
                RemoveRow(row)
            else
                Bind(row, unit)
                if unit then
                    row.unseenSince = nil
                elseif not row.unseenSince then
                    row.unseenSince = GetTime()
                    ScheduleUnseenCheck()
                end
            end
        end
    end
end

-- Layout -----------------------------------------------------------------------

-- The list sits below the pinned rows the game shows; its own rows leave out
-- your target and focus, which have pinned rows.
function Layout()
    local settings = WTF.db.tracker
    local samples = settings.placeholders
    -- The list starts below the lowest pinned row the game shows; a hidden
    -- target row keeps its space, as the secure focus row cannot move in combat.
    local listTop = 0
    for key, row in pairs(tracker.pinned) do
        if samples or IsLiveHostile(PINNED[key].unit) then
            listTop = math.max(listTop, PinnedOffset(key) + RowStep() + PINNED_SPACING)
        end
        if not samples then
            row.name:SetText(ReadName(PINNED[key].unit))
        end
    end
    local target, focus = ReadGUID("target"), ReadGUID("focus")
    local listed = {}
    for _, row in ipairs(tracker.rows) do
        row.sample = nil
        if row.guid and row.guid ~= target and row.guid ~= focus then
            listed[#listed + 1] = row
        end
    end
    table.sort(listed, function(a, b) return a.firstSeen < b.firstSeen end)
    if samples and #listed == 0 then
        for index, name in ipairs(SAMPLE_NAMES.list) do
            local row = tracker.rows[MAX_ROWS - index + 1]
            if not row.guid then
                row.mobName, row.sample = name, true
                listed[#listed + 1] = row
            end
        end
    end
    local list = tracker.list
    local used = {}
    for index, row in ipairs(listed) do
        used[row] = true
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * RowStep())
        row.name:SetText(row.mobName)
        row:Show()
    end
    for _, row in ipairs(tracker.rows) do
        -- List rows only display: they take the mouse only to be dragged.
        row:EnableMouse(not WTF.db.locked)
        if not used[row] then
            row:Hide()
            if row.sample then
                row.mobName, row.sample = nil, nil
            end
        end
    end
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", tracker.anchor, "TOPLEFT", 0, -listTop)
    list:SetShown(settings.enabled and #listed > 0)
end

-- Casts --------------------------------------------------------------------------

local function FindCastUnit(targetName)
    for _, unit in ipairs({"target", "focus", "mouseover"}) do
        local name = UnitName(unit)
        if UnitExists(unit) and not WTF.IsSecret(name) and name == targetName then
            return unit
        end
    end
    for index = 1, MAX_NAMEPLATE_UNITS do
        local unit = "nameplate" .. index
        local name = UnitName(unit)
        if UnitExists(unit) and not WTF.IsSecret(name) and name == targetName then
            return unit
        end
    end
end

local function Track(guid, mobName)
    for _, row in ipairs(tracker.rows) do
        if row.guid == guid then
            return
        end
    end
    local free, oldest
    for _, row in ipairs(tracker.rows) do
        if not row.guid then
            free = free or row
        elseif not oldest or row.firstSeen < oldest.firstSeen then
            oldest = row
        end
    end
    local row = free or oldest
    row.guid, row.mobName, row.firstSeen, row.unseenSince = guid, mobName, GetTime(), nil
    Bind(row, FindUnit(guid))
    Layout()
end

-- Remembers the Bane or Curse just cast, for the pinned slots to recast.
local function RememberLastUsed(spellID)
    local key = tracker.spellSlots[spellID]
    for _, slot in ipairs(SLOTS) do
        if slot.key == key and slot.lastUsed then
            local name = C_Spell.GetSpellName(spellID)
            if name and WTF.db.tracker[slot.lastUsed] ~= name then
                WTF.db.tracker[slot.lastUsed] = name
                ApplyCastButtons()
            end
        end
    end
end

local function OnCastSucceeded(castGUID)
    if WTF.IsSecret(castGUID) then
        return
    end
    local cast = tracker.casts[castGUID]
    tracker.casts = {}
    if not cast then
        return
    end
    RememberLastUsed(cast.spellID)
    local unit = FindCastUnit(cast.target)
    local guid = unit and ReadGUID(unit)
    if guid and UnitCanAttack("player", unit) then
        Track(guid, cast.target)
    end
end

local function OnCastSent(target, castGUID, spellID)
    if WTF.IsSecret(spellID) or WTF.IsSecret(target) or WTF.IsSecret(castGUID)
        or type(target) ~= "string" or target == "" then
        return
    end
    -- For /wtf debug_tracker: the last spell cast at a target, tracked or not.
    tracker.lastCast = {spellID = spellID, slot = tracker.spellSlots[spellID]}
    if tracker.spellSlots[spellID] then
        tracker.casts[castGUID] = {target = target, spellID = spellID}
    end
end

-- New ranks learned: every row's slots accept the new spell IDs.
local function ApplySpellSets()
    tracker.setsDirty = false
    BuildSpellSets()
    -- Only the slots the rows were built with: a spell family you do not know
    -- has no slot, and asking for one raises "aura slot ... was not found"
    -- (found in client, for Siphon Life). A newly learned family's slot comes
    -- with the rebuild that follows.
    local function Update(row)
        for _, slotIndex in ipairs(tracker.shown) do
            local key = SLOTS[slotIndex].key
            row.container:SetAuraSlotCandidateFilters(key, WTF.TrackerCandidateFilters(key))
        end
    end
    for _, row in ipairs(tracker.rows) do
        Update(row)
    end
    for _, row in pairs(tracker.pinned) do
        Update(row)
    end
    ApplyCastButtons()
    WTF.RefreshPlateDots()
end

local function ClearAll()
    for _, row in ipairs(tracker.rows) do
        if row.guid then
            row.guid, row.mobName, row.unseenSince = nil, nil, nil
            Bind(row, nil)
        end
    end
    Layout()
end

-- Builds the pinned rows and the list rows for the current theme, replacing
-- any old ones and keeping the mobs they tracked. Secure rows change only
-- out of combat, so a rebuild in combat waits.
local function BuildRows()
    if InCombatLockdown() then
        tracker.rebuildDirty = true
        return
    end
    tracker.rebuildDirty = false
    tracker.theme = WTF.db.tracker.theme
    tracker.shown = ShownSlots()
    local oldRows = tracker.rows
    for _, row in ipairs(oldRows) do
        row.container:SetUnit("none")
        row:Hide()
    end
    for _, row in pairs(tracker.pinned) do
        UnregisterStateDriver(row, "visibility")
        row.container:SetUnit("none")
        row:Hide()
    end
    tracker.anchor:SetSize(RowWidth(), (RowStep() + PINNED_SPACING) * 2)
    tracker.list:SetSize(RowWidth(), RowStep() * MAX_ROWS)
    tracker.pinned = {target = CreatePinnedRow("target"), focus = CreatePinnedRow("focus")}
    tracker.rows = {}
    for index = 1, MAX_ROWS do
        local row = CreateRow(tracker.list)
        row:EnableMouse(true)
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", StartDrag)
        row:SetScript("OnDragStop", StopDrag)
        row:Hide()
        local old = oldRows[index]
        if old and old.guid then
            row.guid, row.mobName, row.firstSeen, row.unseenSince = old.guid, old.mobName, old.firstSeen,
                old.unseenSince
            Bind(row, FindUnit(row.guid))
        end
        tracker.rows[index] = row
    end
    ApplyCastButtons()
    ApplyPinnedVisibility()
    Layout()
end

-- Rows show a slot per spell you know, so learning one rebuilds them.
local function KnownSlotsChanged()
    local shown = ShownSlots()
    if #shown ~= #tracker.shown then
        return true
    end
    for position, slotIndex in ipairs(shown) do
        if tracker.shown[position] ~= slotIndex then
            return true
        end
    end
    return false
end

function WTF.SetTrackerTheme(theme)
    WTF.db.tracker.theme = theme == "bars" and "bars" or "compact"
    if tracker.available then
        BuildRows()
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit, first, second, third)
    if not tracker.available then
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then
        OnCastSent(first, second, third)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnCastSucceeded(first)
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if not WTF.IsSecret(first) then
            tracker.casts[first] = nil
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Out of combat no DoT of yours is ticking on a live mob.
        ClearAll()
        if tracker.setsDirty then
            ApplySpellSets()
        elseif tracker.castsDirty then
            ApplyCastButtons()
        end
        if tracker.rebuildDirty or KnownSlotsChanged() then
            BuildRows()
        end
        if tracker.visibilityDirty then
            ApplyPinnedVisibility()
            Layout()
        end
    elseif event == "SPELLS_CHANGED" then
        if InCombatLockdown() then
            tracker.setsDirty = true
        else
            ApplySpellSets()
            if KnownSlotsChanged() then
                BuildRows()
            end
        end
    elseif event == "UNIT_HEALTH" then
        for _, row in ipairs(tracker.rows) do
            if row.guid and row.boundUnit == unit and IsDead(unit) then
                RemoveRow(row)
            end
        end
        if unit == "target" or unit == "focus" then
            Layout()
        end
    else
        -- No pinned rows yet after a reload in combat; they come when it ends.
        if event == "PLAYER_TARGET_CHANGED" and tracker.pinned.target then
            tracker.pinned.target.container:UpdateAllAuras()
        elseif event == "PLAYER_FOCUS_CHANGED" and tracker.pinned.focus then
            tracker.pinned.focus.container:UpdateAllAuras()
        end
        RefreshBindings()
        Layout()
    end
end)

-- Placement and settings ----------------------------------------------------

local function Place()
    local anchor, position = tracker.anchor, WTF.db.tracker.position
    anchor:ClearAllPoints()
    if position then
        anchor:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else
        anchor:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
    end
end

function WTF.ResetTrackerPosition()
    WTF.db.tracker.position = nil
    if not tracker.anchor then
        return
    end
    if InCombatLockdown() then
        tracker.placeDirty = true
        return
    end
    Place()
end

function WTF.RefreshTracker()
    if tracker.available then
        ApplyPinnedVisibility()
        Layout()
    end
end

function WTF.InitializeTracker()
    local available, missing = WTF.CheckTrackerCapabilities()
    if not available then
        WTF.Report("The DoT tracker stays off: this client lacks " .. missing .. ".")
        return
    end
    BuildSpellSets()
    -- The secure anchor holds the pinned rows; it takes no mouse input itself.
    local anchor = CreateFrame("Frame", "WarlockToolsForeverTracker", UIParent)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:EnableMouse(false)
    tracker.anchor = anchor
    WTF.RegisterMovable(anchor, function(position) WTF.db.tracker.position = position end)
    local list = CreateFrame("Frame", "WarlockToolsForeverTrackerList", UIParent)
    list:EnableMouse(false)
    tracker.list = list
    tracker.theme = WTF.db.tracker.theme
    tracker.shown = ShownSlots()
    Place()
    tracker.available = true
    for _, event in ipairs({"PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "SPELLS_CHANGED", "UNIT_HEALTH"}) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED"}) do
        events:RegisterUnitEvent(event, "player")
    end
    BuildRows()
end

-- After combat: a delayed /wtf reset.
local placeEvents = CreateFrame("Frame")
placeEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
placeEvents:SetScript("OnEvent", function()
    if tracker.placeDirty then
        tracker.placeDirty = false
        Place()
    end
end)

-- /wtf debug_tracker: the spell IDs each slot accepts, what pinned slots
-- recast, and the listed mobs.
function WTF.ReportTrackerDebug()
    local available, missing = WTF.CheckTrackerCapabilities()
    WTF.Report(string.format("debug_tracker available=%s%s", tostring(available and tracker.available),
        missing and (" missing=" .. missing) or ""))
    if not tracker.available then
        return
    end
    for slotIndex, slot in ipairs(SLOTS) do
        local ids = {}
        for id in pairs(tracker.sets[slot.key]) do
            ids[#ids + 1] = id
        end
        table.sort(ids)
        local matches = slot.dispelType and (slot.dispelType .. " debuffs except " .. slot.excludeSlot)
            or "ids"
        WTF.Report(string.format("debug_tracker slot=%s recast=%s matches=%s ids=%s", slot.key,
            tostring(tracker.pinned.target.casts[slotIndex] and tracker.pinned.target.casts[slotIndex].spellName),
            matches, table.concat(ids, ",")))
    end
    local last = tracker.lastCast
    if last then
        local name = C_Spell.GetSpellName(last.spellID)
        WTF.Report(string.format("debug_tracker lastCast spell=%d name=%s slot=%s", last.spellID,
            tostring(name), tostring(last.slot)))
    end
    for index, row in ipairs(tracker.rows) do
        if row.guid then
            WTF.Report(string.format("debug_tracker row %d name=%s unit=%s unseen=%s", index,
                tostring(row.mobName), tostring(row.boundUnit), tostring(row.unseenSince ~= nil)))
        end
    end
end
