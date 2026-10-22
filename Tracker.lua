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
-- Compact: the space above and below the icons (a row is the icon size plus
-- this twice: 30 at the default 22), and a name line above or below them.
local ROW_PADDING = 4
local NAME_LINE = 14
-- Bar theme: the name line, then one line per spell: an icon and a bar with
-- the spell's name and time left.
local BAR_HEADER = 18
local BAR_LINE_GAP = 2
-- Mob health (author-approved): the line with the mob's name is its health
-- bar, filled in the panel's color (Panel colors, DoT Colors page), at least
-- as wide as the DoTs; the text after the name takes
-- these widths (at 100% text size) from the name's room.
local HEALTH_ALPHA = 0.8
-- Inside the row's border, for a health line beside the icons, and its gap
-- to the nearest icon.
local HEALTH_INSET = 3
local HEALTH_ICON_GAP = 2
local HEALTH_TEXT_WIDTH = {number = 34, percent = 30, both = 70}
local BAR_BACKGROUND = {0.1, 0.1, 0.1, 0.6}
-- The pinned rows' outline: a solid line this thick, this far outside the
-- row, and the extra space below each pinned row that keeps it clear of the next.
local OUTLINE = 3
local OUTLINE_GAP = 2
local PINNED_SPACING = OUTLINE + OUTLINE_GAP + 2
local SLOT_GAP = 6
local PADDING = 6
-- Seconds a list row stays without a unit to bind (its nameplate out of
-- sight), out of combat. In combat it stays until combat ends (player
-- feedback: nameplates off and on, or a mob out of plate range, lost its row).
local UNSEEN_SECONDS = 10
local MAX_NAMEPLATE_UNITS = 40
local AURA_FILTER = "HARMFUL|PLAYER"
local CONTAINER_TEMPLATE = "CustomAuraContainerTemplate"
local BROWN = {0.28, 0.16, 0.07, 0.85}
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
-- The default display order (author-approved): Curse, Bane, the other DoTs,
-- then control. The DoT Order page changes it (tracker.order).
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
local SLOT_INDEX = {}
for index, slot in ipairs(SLOTS) do
    SLOT_INDEX[slot.key] = index
end

local tracker = {rows = {}, pinned = {}, casts = {}, spellSlots = {}, known = {}, slotKnown = {},
    dead = {}, plates = {}, available = false}

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

-- A row's panel opacity (Target, Focus, or Other mobs panel opacity).
local function PanelAlpha(row)
    return WTF.db.tracker.panelOpacity[row.panelKey or "list"] / 100
end

-- A DoT bar as it is built, inside the engine's initializer: its slot color
-- with the panel's opacity in it, also on its texts. Found in client: the
-- engine-driven duration bars did not fade with their panel's frame, so each
-- bar ignores its parent's opacity and carries the panel's itself, exactly
-- the panel's look, never faded twice. Only here: once WTF hands a bar or
-- text to the engine (SetDurationBar, SetSpellName, SetDurationText) it is
-- the engine's, and touching it later raised "Attempt to access forbidden
-- object from code tainted by an AddOn" (found in client, 13x, from the
-- opacity slider). So a new color or panel opacity rebuilds the rows.
local function PrepareBar(row, index, bar, ...)
    if type(bar.IsForbidden) == "function" and bar:IsForbidden() then
        return
    end
    if type(bar.SetIgnoreParentAlpha) == "function" then
        bar:SetIgnoreParentAlpha(true)
    end
    local r, g, b = WTF.SlotColor(SLOTS[index].key)
    local alpha = PanelAlpha(row)
    bar:SetStatusBarColor(r, g, b, alpha)
    for index2 = 1, select("#", ...) do
        select(index2, ...):SetAlpha(alpha)
    end
    row.bars[index] = bar
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

function WTF.TrackerSlotIcon(key)
    return SlotIcon(SLOTS[SLOT_INDEX[key]])
end

local function IsCompact()
    return tracker.theme ~= "bars"
end

-- The slots a row shows, as SLOTS indexes in the saved DoT order (DoT Order
-- page): one for each spell family you know, in both themes (author-
-- approved), or all of them while you know none.
local function ShownSlots()
    local shown, all = {}, {}
    for _, key in ipairs(WTF.db.tracker.order) do
        all[#all + 1] = SLOT_INDEX[key]
        if tracker.slotKnown[key] then
            shown[#shown + 1] = SLOT_INDEX[key]
        end
    end
    return #shown > 0 and shown or all
end

-- The current theme's sizes (settings; the defaults are the constants above).
local function Sizes()
    return WTF.db.tracker.sizes[IsCompact() and "compact" or "bars"]
end

local function TextScale()
    return Sizes().textScale / 100
end

-- One line, cut with "..." only when it does not fit (found in client: long
-- names wrapped onto 2-3 lines and spilled out of the row).
local function OneLine(text)
    if type(text.SetWordWrap) == "function" then
        text:SetWordWrap(false)
    end
    if type(text.SetMaxLines) == "function" then
        text:SetMaxLines(1)
    end
    return text
end

-- A font string at the text size: a share of its font's own size.
local function ScaleFont(text)
    local font, size, flags = text:GetFont()
    if font and type(size) == "number" then
        text:SetFont(font, size * TextScale(), flags)
    end
    return text
end

local function HealthTextWidth()
    local settings = WTF.db.tracker
    if not settings.health or settings.healthText == "none" then
        return 0
    end
    return math.floor(HEALTH_TEXT_WIDTH[settings.healthText] * TextScale() + 0.5)
end

local function NameAround()
    local position = Sizes().namePosition
    return position == "above" or position == "below"
end

-- Compact: the space a name line takes above or below the icons.
local function NameLine()
    return math.floor(NAME_LINE * TextScale() + 0.5)
end

local function SlotSize()
    return IsCompact() and Sizes().iconSize or Sizes().lineHeight
end

-- Bars: the icon in front of each line, and the name line.
local function BarIcon()
    return Sizes().lineHeight - 2
end

local function BarHeader()
    return math.floor(BAR_HEADER * TextScale() + 0.5)
end

local function SlotsWidth()
    return #tracker.shown * (SlotSize() + SLOT_GAP)
end

local function RowWidth()
    if not IsCompact() then
        return Sizes().barWidth
    end
    if NameAround() then
        return PADDING * 2 + math.max(Sizes().nameWidth, SlotsWidth())
    end
    return PADDING * 2 + Sizes().nameWidth + SlotsWidth()
end

local function RowHeight()
    if IsCompact() then
        return SlotSize() + ROW_PADDING * 2 + (NameAround() and NameLine() or 0)
    end
    return BarHeader() + #tracker.shown * (SlotSize() + BAR_LINE_GAP) + PADDING
end

local function RowStep()
    return RowHeight() + 2
end

-- Places a slot's region at a display position in a row: an icon beside,
-- above, or below the name (compact), or a line under or above it (bars).
local function PlaceSlot(region, row, position)
    region:ClearAllPoints()
    local size, where = SlotSize(), Sizes().namePosition
    if IsCompact() then
        local x = PADDING + (position - 1) * (size + SLOT_GAP)
        if where == "left" then
            region:SetPoint("LEFT", row, "LEFT", x + Sizes().nameWidth, 0)
        elseif where == "right" then
            region:SetPoint("LEFT", row, "LEFT", x, 0)
        else
            region:SetPoint("TOPLEFT", row, "TOPLEFT", x, -(ROW_PADDING + (where == "above" and NameLine() or 0)))
        end
        region:SetSize(size, size)
    else
        local top = where == "below" and ROW_PADDING or BarHeader()
        region:SetPoint("TOPLEFT", row, "TOPLEFT", PADDING, -(top + (position - 1) * (size + BAR_LINE_GAP)))
        region:SetSize(RowWidth() - PADDING * 2, size)
    end
end

-- The mob's name, on one line: beside the icons it has the whole column from
-- the row's inner edge to the first icon (the name width setting, less a
-- small gap); above or below them, the row's whole width. The health text,
-- when shown, takes the end of that room, so the name is cut before it is.
local function PlaceName(row)
    local name, where = row.name, Sizes().namePosition
    OneLine(name)
    local reserve = HealthTextWidth()
    name:ClearAllPoints()
    if IsCompact() and where == "left" then
        name:SetPoint("LEFT", PADDING, 0)
        name:SetWidth(Sizes().nameWidth - 4 - reserve)
    elseif IsCompact() and where == "right" then
        name:SetPoint("LEFT", PADDING + SlotsWidth(), 0)
        name:SetWidth(Sizes().nameWidth - 4 - reserve)
    elseif where == "below" then
        name:SetPoint("BOTTOMLEFT", PADDING, ROW_PADDING)
        name:SetWidth(RowWidth() - PADDING * 2 - reserve)
    else
        name:SetPoint("TOPLEFT", PADDING, -ROW_PADDING)
        name:SetWidth(RowWidth() - PADDING * 2 - reserve)
    end
end

-- Mob health (author-approved, player request): the name line is the health
-- bar, and optional text follows the name. Enemy health is secret in combat: WTF never reads
-- it. A StatusBar and a FontString take secrets (SetMinMaxValues, SetValue,
-- SetText), as the shield display shows its absorb, and AbbreviateNumbers
-- gives the number. The percent comes from UnitHealthPercent(unit, true,
-- CurveConstants.ScaleTo100), formatted with "%d" (the path EllesmereUI's
-- unit frame text uses on this client, EUI_UnitFrames_Text.lua:421-424).
-- Number and percent are separate texts, so no secret string is formatted.
-- The name line: its own line across the row (Bars, or a Compact name above
-- or below the icons), or the name's column beside the icons.
local function PlaceHealth(row)
    local bar, where = row.health, Sizes().namePosition
    bar:ClearAllPoints()
    -- Beside the icons (player request): only the name's column, from the
    -- row's inner edge to the icons, less a small gap.
    if IsCompact() and where == "left" then
        bar:SetPoint("TOPLEFT", row, "TOPLEFT", HEALTH_INSET, -HEALTH_INSET)
        bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", PADDING + Sizes().nameWidth - HEALTH_ICON_GAP, HEALTH_INSET)
        return
    elseif IsCompact() and where == "right" then
        bar:SetPoint("TOPLEFT", row, "TOPLEFT", PADDING + SlotsWidth() - SLOT_GAP + HEALTH_ICON_GAP, -HEALTH_INSET)
        bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -HEALTH_INSET, HEALTH_INSET)
        return
    end
    local height = IsCompact() and NameLine() + 2 or BarHeader() - 2
    local edge, y = where == "below" and "BOTTOM" or "TOP", where == "below" and 2 or -2
    bar:SetPoint(edge .. "LEFT", row, edge .. "LEFT", PADDING, y)
    bar:SetPoint(edge .. "RIGHT", row, edge .. "RIGHT", -PADDING, y)
    bar:SetHeight(height)
end

-- The bar in the panel's color; the name, its text, and the dim icons go on a
-- layer above it (a child frame draws over its parent's own regions), and the
-- engine's slots above that. Returns the frame those regions belong to.
local function CreateHealth(row, unit)
    if not WTF.db.tracker.health then
        return row
    end
    local level = row:GetFrameLevel()
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetFrameLevel(level)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, 1)
    bar:Hide()
    row.health = bar
    PlaceHealth(row)
    local layer = CreateFrame("Frame", nil, row)
    layer:SetAllPoints(row)
    layer:SetFrameLevel(level + 1)
    row.layer = layer
    return layer
end

local function CreateHealthText(row, regions)
    local mode = WTF.db.tracker.healthText
    if not row.health or mode == "none" then
        return
    end
    local after = row.name
    if mode == "percent" or mode == "both" then
        row.healthPercent = OneLine(ScaleFont(regions:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")))
        row.healthPercent:SetPoint("LEFT", after, "RIGHT", 2, 0)
        after = row.healthPercent
    end
    if mode == "number" or mode == "both" then
        row.healthNumber = OneLine(ScaleFont(regions:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")))
        row.healthNumber:SetPoint("LEFT", after, "RIGHT", 2, 0)
    end
end

local function PercentText(unit, both)
    if type(UnitHealthPercent) ~= "function" or type(CurveConstants) ~= "table" or not CurveConstants.ScaleTo100 then
        return ""
    end
    local percent = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
    if not WTF.IsSecret(percent) and type(percent) ~= "number" then
        return ""
    end
    return string.format(both and "%d%% |" or "%d%%", percent)
end

local function UpdateHealth(row)
    local bar = row.health
    if not bar then
        return
    end
    local unit = row.boundUnit
    if not unit or unit == "none" or not UnitExists(unit) or type(UnitHealth) ~= "function"
        or type(UnitHealthMax) ~= "function" then
        bar:Hide()
        if row.healthPercent then
            row.healthPercent:SetText("")
        end
        if row.healthNumber then
            row.healthNumber:SetText("")
        end
        return
    end
    bar:SetMinMaxValues(0, UnitHealthMax(unit))
    bar:SetValue(UnitHealth(unit))
    bar:Show()
    if row.healthPercent then
        row.healthPercent:SetText(PercentText(unit, row.healthNumber ~= nil))
    end
    if row.healthNumber then
        row.healthNumber:SetText(type(AbbreviateNumbers) == "function" and AbbreviateNumbers(UnitHealth(unit)) or "")
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
        icon:SetSize(BarIcon(), BarIcon())
        icon:SetPoint("LEFT", 1, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local bar = CreateFrame("StatusBar", nil, button)
        bar:SetPoint("TOPLEFT", button, "TOPLEFT", BarIcon() + 4, 0)
        bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local spellName = ScaleFont(bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
        spellName:SetPoint("LEFT", 4, 0)
        spellName:SetJustifyH("LEFT")
        local timeLeft = ScaleFont(bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
        timeLeft:SetPoint("RIGHT", -4, 0)
        PrepareBar(row, index, bar, spellName, timeLeft)
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
        PrepareBar(row, index, bar)
        local textHolder = CreateFrame("Frame", nil, button)
        textHolder:SetAllPoints(button)
        textHolder:SetFrameLevel(cooldown:GetFrameLevel() + 1)
        local text = ScaleFont(textHolder:CreateFontString(nil, "OVERLAY", "NumberFontNormal"))
        text:SetPoint("CENTER", 0, 0)
        button:SetIcon(icon)
        button:SetDurationCooldown(cooldown)
        local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
        button:SetDurationBar(bar, {direction = direction})
        button:SetDurationText(text, {})
    end
end

-- A row in its panel's color (Core's TRACKER_PANEL_COLORS): the row border,
-- the target's or focus's outline, and the health fill. All are WTF's own.
local function ColorPanel(row)
    local r, g, b = WTF.PanelColor(row.panelKey or "list")
    row:SetBackdropBorderColor(r, g, b)
    if row.outline then
        row.outline:SetBackdropBorderColor(r, g, b)
    end
    if row.health then
        row.health:SetStatusBarColor(r, g, b, HEALTH_ALPHA)
    end
end

local function CreateRow(parent, unit)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    -- Which panel's opacity its DoT bars carry.
    row.panelKey = unit or "list"
    row:SetSize(RowWidth(), RowHeight())
    row:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2}})
    row:SetBackdropColor(BROWN[1], BROWN[2], BROWN[3], BROWN[4])
    local regions = CreateHealth(row, unit)
    ColorPanel(row)
    row.name = ScaleFont(regions:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    PlaceName(row)
    row.name:SetJustifyH("LEFT")
    CreateHealthText(row, regions)
    row.bars = {}
    -- Behind each live slot: a dim icon (compact), or a dim line with the
    -- icon and the spell family's name (bars), so a missing spell shows.
    for position, slotIndex in ipairs(tracker.shown) do
        local slot = SLOTS[slotIndex]
        local placeholder = regions:CreateTexture(nil, "BACKGROUND", nil, 1)
        placeholder:SetTexture(SlotIcon(slot))
        placeholder:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        placeholder:SetDesaturated(true)
        placeholder:SetAlpha(PLACEHOLDER_ALPHA)
        if IsCompact() then
            PlaceSlot(placeholder, row, position)
        else
            local line = regions:CreateTexture(nil, "BACKGROUND")
            PlaceSlot(line, row, position)
            line:SetColorTexture(BAR_BACKGROUND[1], BAR_BACKGROUND[2], BAR_BACKGROUND[3], BAR_BACKGROUND[4])
            placeholder:SetSize(BarIcon(), BarIcon())
            placeholder:SetPoint("LEFT", line, "LEFT", 1, 0)
            local label = ScaleFont(regions:CreateFontString(nil, "BORDER", "GameFontDisableSmall"))
            label:SetPoint("LEFT", line, "LEFT", BarIcon() + 8, 0)
            label:SetText(SlotLabel(slot.key))
        end
    end
    local container = CreateFrame("AuraContainer", nil, row, CONTAINER_TEMPLATE)
    if row.layer then
        container:SetFrameLevel(row:GetFrameLevel() + 2)
    end
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
    UpdateHealth(row)
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

-- Sections (author-approved, player request): the target row, the focus row,
-- and the list of other mobs are three frames, each dragged, snapped, and
-- saved on its own. A section not yet dragged hangs from an invisible stack
-- frame where the one tracker frame was (its saved place, or the default), at
-- the offsets the rows had there, so nothing moves for players who placed the
-- tracker before: the target on top, the focus below it past the target's
-- outline, the list below both. A section stays where it is put; the list no
-- longer moves up when a pinned row hides.
local SECTION_KEYS = {"target", "focus", "list"}

local function StackOffset(key)
    local step = RowStep() + PINNED_SPACING
    return key == "target" and 0 or key == "focus" and step or step * 2
end

-- Dragging and snapping (Layout.lua, or Dyre's Toolkit): a row drags its section.
-- Locked, the rows let clicks through to the world. While Ctrl is held (out
-- of combat, with Dyre's Toolkit) they take the mouse, so a Ctrl-drag moves
-- a panel freely, as on every Dyre's AddOn's frames (the toolkit's
-- BeginDrag rule, author-approved; player report: the panels did not move,
-- as no part of a locked panel took the mouse to start the drag). Event
-- driven (MODIFIER_STATE_CHANGED), and never changed during a drag, so its
-- drop always arrives. The pinned rows are secure: out of combat only, and
-- turned off as combat starts (PLAYER_REGEN_DISABLED comes before the
-- lockdown).
local function RowsTakeMouse()
    return not WTF.db.locked or tracker.ctrlMove == true
end

local function ApplyRowMouse()
    if InCombatLockdown() then
        return
    end
    local take = RowsTakeMouse()
    for _, row in pairs(tracker.pinned) do
        row:EnableMouse(take)
    end
    for _, row in ipairs(tracker.rows) do
        row:EnableMouse(take)
    end
end

local function UpdateCtrlMove(entering)
    if tracker.dragging then
        return
    end
    local ctrl = not entering and WTF.toolkit ~= nil and WTF.db.locked and not InCombatLockdown()
        and type(IsControlKeyDown) == "function" and IsControlKeyDown() == true
    if ctrl ~= (tracker.ctrlMove == true) then
        tracker.ctrlMove = ctrl or nil
        ApplyRowMouse()
    end
end

local function DragScripts(frame, key)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        tracker.dragging = true
        WTF.BeginDrag(tracker.sections[key])
    end)
    frame:SetScript("OnDragStop", function()
        tracker.dragging = nil
        WTF.EndDrag(tracker.sections[key])
        UpdateCtrlMove()
    end)
end

local function CreatePinnedRow(key)
    local pinned = PINNED[key]
    local section = tracker.sections[key]
    local row = CreateRow(section, pinned.unit)
    row:SetPoint("TOPLEFT", section, "TOPLEFT")
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
    DragScripts(row, key)
    local outline = CreateFrame("Frame", nil, row, "BackdropTemplate")
    local inset = OUTLINE + OUTLINE_GAP
    outline:SetPoint("TOPLEFT", -inset, inset)
    outline:SetPoint("BOTTOMRIGHT", inset, -inset)
    outline:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = OUTLINE})
    outline:EnableMouse(false)
    row.outline = outline
    ColorPanel(row)
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
        row:EnableMouse(RowsTakeMouse())
        UnregisterStateDriver(row, "visibility")
        if settings.placeholders then
            row:Show()
            row.name:SetText(SAMPLE_NAMES[key])
        else
            RegisterStateDriver(row, "visibility", PINNED[key].driver)
        end
    end
    for _, key in ipairs({"target", "focus"}) do
        tracker.sections[key]:SetShown(settings.enabled)
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
-- Which mob each nameplate token shows, for plates whose GUID cannot be read
-- (secret, as the client may give in combat; player report: a dotted target
-- you tabbed away from stayed unbound beside its own plate). Learned from the
-- plate's GUID when readable, else from UnitIsUnit with your target or focus,
-- whose GUIDs are readable; a token shows one mob until its plate goes.
local function LearnPlate(unit)
    if not UnitExists(unit) then
        return
    end
    local guid = ReadGUID(unit)
    if guid then
        tracker.plates[unit] = guid
        return
    end
    for _, known in ipairs({"target", "focus"}) do
        local same = UnitIsUnit(unit, known)
        if not WTF.IsSecret(same) and same == true then
            tracker.plates[unit] = ReadGUID(known) or tracker.plates[unit]
            return
        end
    end
end

local function LearnPlates()
    for index = 1, MAX_NAMEPLATE_UNITS do
        LearnPlate("nameplate" .. index)
    end
end

local function FindUnit(guid)
    for index = 1, MAX_NAMEPLATE_UNITS do
        local unit = "nameplate" .. index
        if UnitExists(unit) and ReadGUID(unit) == guid then
            return unit
        end
    end
    for unit, known in pairs(tracker.plates) do
        if known == guid and UnitExists(unit) then
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
    if unit then
        row.held = nil
    end
    row.container:SetUnit(wanted)
    row.container:UpdateAllAuras()
    UpdateHealth(row)
end

local function IsDead(unit)
    local dead = UnitIsDead(unit)
    return not WTF.IsSecret(dead) and dead == true
end

local Layout

local function RemoveRow(row)
    row.guid, row.mobName, row.unseenSince, row.held = nil, nil, nil, nil
    Bind(row, nil)
    Layout()
end

-- A mob seen dead on any unit (target, focus, mouseover, or a nameplate,
-- also as its plate goes) loses its row at once, and its GUID is kept until
-- combat ends, so nothing lists it again (player report: a dying target
-- showed for a moment as another mob, as its row was bound to its plate).
local function NoteDeath(unit)
    if not IsDead(unit) then
        return
    end
    local guid = ReadGUID(unit)
    if not guid then
        return
    end
    tracker.dead[guid] = true
    for _, row in ipairs(tracker.rows) do
        if row.guid == guid then
            RemoveRow(row)
        end
    end
end

local function ScheduleUnseenCheck()
    C_Timer.After(UNSEEN_SECONDS + 0.1, function()
        if InCombatLockdown() then
            return
        end
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

-- A list not yet dragged hangs below the lowest stacked pinned row the game
-- shows, as before the panels moved separately (author-approved, player
-- feedback: an empty focus panel left a row-sized gap); a pinned row that was
-- dragged away does not count, and a hidden target row keeps its space when
-- the focus row shows, as the secure focus row cannot move in combat. The list
-- is a plain frame, so it moves also in combat. While frames are unlocked
-- every sample shows, so it sits below both; it moves only when its place
-- changes, so a drag is never broken. Once dragged, it stays where it was put.
local function FollowPinnedRows()
    local settings = WTF.db.tracker
    if settings.sections.list then
        return
    end
    local listTop = 0
    if not WTF.db.locked then
        listTop = StackOffset("list")
    else
        for _, key in ipairs({"target", "focus"}) do
            if not settings.sections[key] and IsLiveHostile(PINNED[key].unit) then
                listTop = math.max(listTop, StackOffset(key) + RowStep() + PINNED_SPACING)
            end
        end
    end
    if tracker.listTop == listTop then
        return
    end
    tracker.listTop = listTop
    tracker.list:ClearAllPoints()
    tracker.list:SetPoint("TOPLEFT", tracker.stack, "TOPLEFT", 0, -listTop)
end

-- The list leaves out your target and focus, which have pinned rows. Its
-- frame is one row tall (it snaps by its first row); the other rows hang below.
function Layout()
    local settings = WTF.db.tracker
    local samples = settings.placeholders
    for key, row in pairs(tracker.pinned) do
        if not samples then
            row.name:SetText(ReadName(PINNED[key].unit))
        end
    end
    local target, focus = ReadGUID("target"), ReadGUID("focus")
    -- What the pinned rows showed, for the next target or focus change.
    tracker.shownTarget, tracker.shownFocus = target, focus
    local listed = {}
    for _, row in ipairs(tracker.rows) do
        row.sample = nil
        if row.guid and row.guid ~= target and row.guid ~= focus and not row.held then
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
        row:EnableMouse(RowsTakeMouse())
        if not used[row] then
            row:Hide()
            if row.sample then
                row.mobName, row.sample = nil, nil
            end
        end
    end
    list:SetShown(settings.enabled and #listed > 0)
    FollowPinnedRows()
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
    if tracker.dead[guid] then
        return
    end
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
    LearnPlates()
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

-- The mob a cast lands on is the one it was aimed at as it started (player
-- feedback, found in client): with same-named mobs and a tab before a cast
-- with a cast time landed, reading the name at success took the new target,
-- and the mob really dotted got no row. Only this cast's entry goes.
local function OnCastSucceeded(castGUID)
    if WTF.IsSecret(castGUID) then
        return
    end
    local cast = tracker.casts[castGUID]
    tracker.casts[castGUID] = nil
    if not cast then
        return
    end
    RememberLastUsed(cast.spellID)
    if cast.guid then
        Track(cast.guid, cast.target)
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
        -- The mob now, while the cast starts: target first, as a cast at a name
        -- usually goes to your target.
        local unit = FindCastUnit(target)
        local guid = unit and ReadGUID(unit)
        local hostile = unit and UnitCanAttack("player", unit)
        tracker.casts[castGUID] = {target = target, spellID = spellID,
            guid = guid and not WTF.IsSecret(hostile) and hostile == true and guid or nil}
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
            row.guid, row.mobName, row.unseenSince, row.held = nil, nil, nil, nil
            Bind(row, nil)
        end
    end
    tracker.dead = {}
    Layout()
end

local Place

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
    for _, frame in pairs(tracker.sections) do
        frame:SetSize(RowWidth(), RowHeight())
    end
    -- The rows' size moves the stacked sections' offsets.
    Place()
    tracker.pinned = {target = CreatePinnedRow("target"), focus = CreatePinnedRow("focus")}
    tracker.rows = {}
    for index = 1, MAX_ROWS do
        local row = CreateRow(tracker.list)
        row:EnableMouse(true)
        DragScripts(row, "list")
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

-- A new DoT order (DoT Order page): the engine places slots only as the rows
-- are built, so they are rebuilt (out of combat; in combat, when it ends).
function WTF.ApplyDotOrder()
    if tracker.available then
        BuildRows()
    end
end

-- New panel colors (DoT Colors page): WTF's own border, outline, and health
-- bar, so every row follows at once, also in combat.
function WTF.ApplyPanelColors()
    for _, row in ipairs(tracker.rows) do
        ColorPanel(row)
    end
    for _, row in pairs(tracker.pinned) do
        ColorPanel(row)
    end
end

-- New slot colors (DoT Colors page): the bars take a color only as they are
-- built, so the rows are rebuilt (out of combat; in combat, when it ends).
function WTF.ApplyTrackerColors()
    if tracker.available then
        BuildRows()
    end
end

-- Mob health on or off, or its text (Core's TRACKER_HEALTH_TEXTS): the rows
-- are rebuilt (out of combat), since the name's room changes.
function WTF.SetTrackerHealth(key, value)
    local settings = WTF.db.tracker
    if key == "health" then
        settings.health = value == true
    elseif key == "healthText" then
        settings.healthText = WTF.SanitizeHealthText(value)
    end
    if tracker.available then
        BuildRows()
    end
end

-- A size for a theme (Core's TRACKER_SIZE_SPECS) or the name position; nil
-- value: that theme's defaults. The rows are rebuilt (out of combat).
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
    if tracker.available then
        BuildRows()
    end
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
    elseif event == "MODIFIER_STATE_CHANGED" then
        UpdateCtrlMove()
    elseif event == "PLAYER_REGEN_DISABLED" then
        UpdateCtrlMove(true)
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if event == "UNIT_HEALTH" and not WTF.IsSecret(unit) then
            NoteDeath(unit)
        end
        for _, row in ipairs(tracker.rows) do
            if row.guid and row.boundUnit == unit then
                if event == "UNIT_HEALTH" and IsDead(unit) then
                    RemoveRow(row)
                else
                    UpdateHealth(row)
                end
            end
        end
        local pinned = tracker.pinned[unit]
        if pinned then
            UpdateHealth(pinned)
            Layout()
        end
    else
        -- No pinned rows yet after a reload in combat; they come when it ends.
        if event == "PLAYER_TARGET_CHANGED" and tracker.pinned.target then
            tracker.pinned.target.container:UpdateAllAuras()
            UpdateHealth(tracker.pinned.target)
        elseif event == "PLAYER_FOCUS_CHANGED" and tracker.pinned.focus then
            tracker.pinned.focus.container:UpdateAllAuras()
            UpdateHealth(tracker.pinned.focus)
        end
        local oldTarget, oldFocus = tracker.shownTarget, tracker.shownFocus
        if event == "NAME_PLATE_UNIT_REMOVED" and not WTF.IsSecret(unit) then
            NoteDeath(unit)
            tracker.plates[unit] = nil
        elseif event == "NAME_PLATE_UNIT_ADDED" and not WTF.IsSecret(unit) then
            tracker.plates[unit] = nil
            LearnPlate(unit)
        else
            LearnPlates()
        end
        RefreshBindings()
        -- Your target or focus just left with no unit showing the mob: as a
        -- dead mob's plate goes, most likely dead, so it is not listed until
        -- a unit shows it again (player report).
        local target, focus = ReadGUID("target"), ReadGUID("focus")
        for _, row in ipairs(tracker.rows) do
            if row.guid and (row.guid == oldTarget or row.guid == oldFocus) and row.guid ~= target
                    and row.guid ~= focus and row.boundUnit == "none" then
                row.held = true
            end
        end
        Layout()
    end
end)

-- Placement and settings ----------------------------------------------------

-- Out of combat only: the sections hold secure rows.
function Place()
    local stack, position = tracker.stack, WTF.db.tracker.position
    stack:SetSize(RowWidth(), (RowStep() + PINNED_SPACING) * 2)
    stack:ClearAllPoints()
    if position then
        stack:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else
        stack:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
    end
    for _, key in ipairs(SECTION_KEYS) do
        local frame, saved = tracker.sections[key], WTF.db.tracker.sections[key]
        frame:ClearAllPoints()
        if saved then
            frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
        else
            frame:SetPoint("TOPLEFT", stack, "TOPLEFT", 0, -StackOffset(key))
        end
    end
    tracker.listTop = not WTF.db.tracker.sections.list and StackOffset("list") or nil
end

-- A panel's opacity (a setting per panel): the whole section frame, rows and
-- all. SetAlpha is no protected action, so it applies at once, also in
-- combat, and WTF never touches the engine's buttons for it.
local function ApplyPanelOpacity()
    for key, frame in pairs(tracker.sections) do
        frame:SetAlpha(WTF.db.tracker.panelOpacity[key] / 100)
    end
end

-- The panel fades at once, also in combat; its DoT bars carry the opacity
-- from when they are built, so they follow with a rebuild (out of combat;
-- in combat, when it ends).
function WTF.SetTrackerPanelOpacity(key, percent)
    WTF.db.tracker.panelOpacity[key] = WTF.SanitizeWhole(percent, WTF.PANEL_OPACITY_MIN, WTF.PANEL_OPACITY_MAX,
        WTF.DEFAULT_PANEL_OPACITY)
    if tracker.available then
        ApplyPanelOpacity()
        BuildRows()
    end
end

-- /wtf reset: the three sections stacked at the default place again.
function WTF.ResetTrackerPosition()
    WTF.db.tracker.position = nil
    WTF.db.tracker.sections = {}
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
    -- Where the one tracker frame was: sections not yet dragged hang from it.
    tracker.stack = CreateFrame("Frame", nil, UIParent)
    tracker.stack:EnableMouse(false)
    -- One frame per section, each its own movable; the target and focus ones
    -- hold the secure pinned rows. They take no mouse input themselves.
    local names = {target = "WarlockToolsForeverTracker", focus = "WarlockToolsForeverTrackerFocus",
        list = "WarlockToolsForeverTrackerList"}
    tracker.sections = {}
    for _, key in ipairs(SECTION_KEYS) do
        local frame = CreateFrame("Frame", names[key], UIParent)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame:EnableMouse(false)
        tracker.sections[key] = frame
        WTF.RegisterMovable(frame, function(position) WTF.db.tracker.sections[key] = position end)
    end
    tracker.anchor, tracker.list = tracker.sections.target, tracker.sections.list
    ApplyPanelOpacity()
    tracker.theme = WTF.db.tracker.theme
    tracker.shown = ShownSlots()
    tracker.available = true
    for _, event in ipairs({"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED",
        "PLAYER_FOCUS_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "SPELLS_CHANGED",
        "UNIT_HEALTH", "UNIT_MAXHEALTH", "MODIFIER_STATE_CHANGED"}) do
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
    local placed = {}
    for _, key in ipairs(SECTION_KEYS) do
        placed[#placed + 1] = key .. "=" .. (WTF.db.tracker.sections[key] and "moved" or "stacked")
    end
    WTF.Report("debug_tracker sections " .. table.concat(placed, " ")
        .. (WTF.db.tracker.position and " (stack moved)" or ""))
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
    -- Plates: how many show, how many have a readable GUID, how many WTF knows
    -- the mob of, and which shows your target.
    local shown, readable, known, targetPlate = 0, 0, 0, "none"
    for index = 1, MAX_NAMEPLATE_UNITS do
        local unit = "nameplate" .. index
        if UnitExists(unit) then
            shown = shown + 1
            readable = readable + (ReadGUID(unit) and 1 or 0)
            known = known + (tracker.plates[unit] and 1 or 0)
            local same = UnitIsUnit(unit, "target")
            if not WTF.IsSecret(same) and same == true then
                targetPlate = unit
            end
        end
    end
    WTF.Report(string.format("debug_tracker plates shown=%d readableGUID=%d known=%d targetPlate=%s targetGUID=%s",
        shown, readable, known, targetPlate, tostring(ReadGUID("target") ~= nil)))
    for index, row in ipairs(tracker.rows) do
        if row.guid then
            WTF.Report(string.format("debug_tracker row %d name=%s unit=%s unseen=%s held=%s", index,
                tostring(row.mobName), tostring(row.boundUnit), tostring(row.unseenSince ~= nil),
                tostring(row.held == true)))
        end
    end
end
