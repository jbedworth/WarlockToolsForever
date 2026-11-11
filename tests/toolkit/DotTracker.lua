local _, ns = ...
local DyresToolkit = ns.toolkit

-- The DoT tracker, for every Dyre's AddOn (Toolkit 2.5.0, engine stage C;
-- lead-approved plan, 2026-11-01). Moved from Warlock Tools Forever 1.4.1's
-- Tracker.lua, which keeps its own copy until it switches over; its rules are
-- this file's spec. Two pinned rows, your target and your focus, each shown
-- only while that unit is a live hostile; then a list of the other mobs you
-- DoTed. Each row has a slot per spell family you know (the class's `dots`
-- from ClassData), with bars in each family's color.
--
-- On Forever, AddOn code cannot read enemy auras in combat, so each row holds
-- an AuraContainer (Auras.lua): the engine reads the row's unit and draws the
-- icon, sweep, countdown, and bar into regions made here; the tracker never
-- sees the timers. It knows only which mobs you cast on, from your own cast
-- events: the mob is locked as the cast starts (target first) and listed when
-- it lands. A dimmed icon sits behind each slot, so a missing spell shows dim.
-- A row's `guid` is the mob's key: its GUID, else "plate:nameplateN" where GUIDs
-- are secret (instances), so there the list needs enemy nameplates, and a row
-- goes with its plate.
--
-- Two themes: Compact (a row with the name and an icon per spell) and Bars (a
-- block per mob, its name above one bar line per spell). Pinned rows' slots
-- are secure buttons that recast on @target or @focus; secure frames change
-- only out of combat, so a rebuild in combat waits. List rows only display.
--
-- The engine never owns SavedVariables: `store` is the owner's saved table
-- (WTF's db.tracker), read live, repaired by the owner. The tracker writes
-- only the keys the owner gave it: the last Bane or Curse cast (each slot's
-- `lastUsed`) and the sections' places, through the owner's movable `save`.

local MAX_ROWS = 8
local ROW_PADDING = 4
local NAME_LINE = 14
local BAR_HEADER = 18
local BAR_LINE_GAP = 2
local HEALTH_ALPHA = 0.8
local HEALTH_INSET = 3
local HEALTH_ICON_GAP = 2
local HEALTH_TEXT_WIDTH = {number = 34, percent = 30, both = 70}
local BAR_BACKGROUND = {0.1, 0.1, 0.1, 0.6}
-- The pinned rows' solid outline: store.outlineWidth, whole pixels (2.8.0;
-- John, 2026-11-11, from a player asking to hide it); 0 draws none.
local OUTLINE_GAP = 2
DyresToolkit.TRACKER_OUTLINE = {min = 0, max = 20, default = 3}
local SLOT_GAP = 6
local PADDING = 6
-- Seconds a list row stays without a unit to bind, out of combat; in combat
-- it stays until combat ends (WTF player feedback).
local UNSEEN_SECONDS = 10
local MAX_NAMEPLATE_UNITS = 40
local AURA_FILTER = "HARMFUL|PLAYER"
local BROWN = {0.28, 0.16, 0.07, 0.85}
local PLACEHOLDER_ALPHA = 0.3
local DEFAULT_POINT = {"CENTER", "CENTER", -260, 120}
local SAMPLE_NAMES = {target = "Target (sample)", focus = "Focus (sample)",
    list = {"Another mob (sample)", "One more mob (sample)"}}
local PINNED = {
    target = {unit = "target", driver = "[@target,harm,nodead] show; hide"},
    focus = {unit = "focus", driver = "[@focus,exists,harm,nodead] show; hide"},
}
local SECTION_KEYS = {"target", "focus", "list"}
-- Panel colors before a setting: the warlock class color, the focus red,
-- the others' dark grey (WTF's TRACKER_PANEL_COLORS defaults).
local PANEL_COLORS = {target = "ff8787ed", focus = "ffe61a1a", list = "ff545454"}
-- WTF Tracker's orders (lead decision 2a): a list row's mob through its
-- nameplate first; a cast locked on the first unit with its name, target
-- first, stopping at the first unit of that name, alive or dead.
local DEFAULT_FIND = {"plates", "memory", "target", "focus"}
-- A secret GUID locks by the plate key, and a secret "can attack" is yes: a
-- DoT cast goes only to a mob you can attack (instances; WTF player reports).
local DEFAULT_LOCK = {units = {"target", "focus", "mouseover", "plates"}, stopAtName = true, allowDead = true,
    plateKey = true, secretHostile = true}

-- "aarrggbb" to r, g, b (0-1); white for anything else.
function DyresToolkit.HexColor(hex)
    if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x%x%x$") then
        return 1, 1, 1
    end
    return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

-- The smart curse (2.7.0; John, 2026-11-10, on a WTF player comment). A
-- secure click cannot read the mob in combat (no macro condition tests mana
-- or class, and attributes are locked), so modifiers choose: Alt
-- Recklessness, Shift Weakness, Ctrl Tongues (else Weakness), and no
-- modifier the smart pick, set out of combat from the mob. The marker reads
-- the mob at any time, so it still shows the best curse in combat.
local SMART_MARKS = {tongues = "T", elements = "E", weakness = "W"}

-- True for a mob with a mana bar, false for one without, nil when unknown
-- (no unit, no API, or a secret value).
function DyresToolkit.UnitHasMana(unit)
    if type(UnitPowerType) ~= "function" or type(UnitPowerMax) ~= "function" or not UnitExists(unit) then
        return nil
    end
    local power = UnitPowerType(unit)
    if DyresToolkit.IsSecret(power) or type(power) ~= "number" then
        return nil
    end
    if power ~= 0 then
        return false
    end
    local most = UnitPowerMax(unit, 0)
    if DyresToolkit.IsSecret(most) or type(most) ~= "number" then
        return nil
    end
    return most > 0
end

-- names: the known spell names {weakness, tongues, elements, recklessness}.
-- The no-modifier curse and its key: Tongues on a mob with mana (if known),
-- else Elements (if known), else Weakness; nil without Weakness.
function DyresToolkit.SmartCursePick(names, unit)
    if type(names) ~= "table" or not names.weakness then
        return nil
    end
    if unit and names.tongues and DyresToolkit.UnitHasMana(unit) == true then
        return names.tongues, "tongues"
    end
    if names.elements then
        return names.elements, "elements"
    end
    return names.weakness, "weakness"
end

-- The macro text. With a unit, every clause aims there (a pinned slot);
-- without, the game's own aim (the "! Curse" macro and the keybind).
function DyresToolkit.SmartCurseMacro(names, pick, unit)
    if type(names) ~= "table" or not names.weakness then
        return nil
    end
    pick = pick or DyresToolkit.SmartCursePick(names)
    local aim = unit and ("@" .. unit .. (unit == "focus" and ",exists" or "") .. ",harm,nodead") or nil
    local function When(modifier)
        return "[" .. (aim and (aim .. ",") or "") .. "mod:" .. modifier .. "] "
    end
    local clauses = {}
    if names.recklessness then
        clauses[#clauses + 1] = When("alt") .. names.recklessness
    end
    clauses[#clauses + 1] = When("shift") .. names.weakness
    clauses[#clauses + 1] = When("ctrl") .. (names.tongues or names.weakness)
    clauses[#clauses + 1] = (aim and ("[" .. aim .. "] ") or "") .. pick
    return "/use " .. table.concat(clauses, "; ")
end

-- spec (required: addon, store, slots or class, names):
--   addon       the owning AddOn's folder name
--   priority    owner priority for "dots:<CLASS>" (10 class AddOn, 5 DDT)
--   class       "WARLOCK": the owner kind's class and the default slots
--   slots       the class's dots (ClassData), in their default order
--   store       the owner's saved table, read live: enabled, theme
--               ("compact" or "bars"), sizes.compact {iconSize, nameWidth,
--               textScale, namePosition} and sizes.bars {barWidth,
--               lineHeight, textScale, namePosition}, order (slot keys),
--               health, healthText ("none", "number", "percent", "both"),
--               panelOpacity {target, focus, list}, outlineWidth (the
--               pinned rows' outline, TRACKER_OUTLINE: 0-20 px, default 3,
--               0 none; a change needs Rebuild), position, sections
--               {target, focus, list}, and each slot's lastUsed key;
--               curseMode ("last", the default, or "smart": the slot with
--               `smart` data casts the smart curse) and curseMarker (false:
--               no smart marker)
--   names       {target, focus, list}: the three section frames' names;
--               optional smartCurse: a hidden secure button with the smart
--               curse, for a CLICK keybind (made only with this name)
--   onSmartCurse  function(body): the "! Curse" macro body, or nil without
--               Curse of Weakness; out of combat, when it changes
--   point       the default place {point, relativePoint, x, y}
--   slotColor   function(key) -> r, g, b (default the slot's color)
--   panelColor  function(key) -> r, g, b (default WTF's panel colors)
--   movable     {register = function(frame, save), beginDrag = function(frame),
--               endDrag = function(frame)}: the owner's layout
--   locked      function() -> true while frames are locked (else samples)
--   ctrlMove    true: a locked row takes the mouse while Ctrl is held, out
--               of combat, for the toolkit's Ctrl-drag
--   predictor   a DotPredict predictor: the rows' damage to come
--   find, lock  FindUnit order and LockCast options (default WTF's)
--   onSpellsChanged  function(): new spells known (the plate dots follow)
-- Returns the tracker, else nil and what is missing.
function DyresToolkit.CreateDotTracker(spec)
    if type(spec) ~= "table" or type(spec.addon) ~= "string" or type(spec.store) ~= "table"
        or type(spec.names) ~= "table" then
        return nil, "spec"
    end
    if not DyresToolkit.AuraEngineKind() then
        return nil, DyresToolkit.AURA_ENGINE_MISSING
    end
    for _, name in ipairs({"RegisterStateDriver", "UnregisterStateDriver"}) do
        if type(_G[name]) ~= "function" then
            return nil, name
        end
    end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        return nil, "C_Timer.After"
    end
    local classData = spec.class and DyresToolkit.ClassSpells(spec.class) or {}
    local SLOTS = spec.slots or classData.dots
    if type(SLOTS) ~= "table" or #SLOTS == 0 then
        return nil, "slots"
    end
    local SLOT_INDEX = {}
    for index, slot in ipairs(SLOTS) do
        SLOT_INDEX[slot.key] = index
    end
    local store = spec.store
    local kind = "dots:" .. (spec.class or spec.addon)
    local movable = spec.movable or {}
    local tracker = {rows = {}, pinned = {}, casts = {}, spellSlots = {}, known = {}, slotKnown = {},
        dead = {}, sections = {}, ownerKind = kind}
    local events = CreateFrame("Frame")
    local Layout, Place, BuildRows, KnownSlotsChanged

    local function Locked()
        return not spec.locked or spec.locked() ~= false
    end

    local function Owned()
        return DyresToolkit.IsOwner(kind, spec.addon)
    end

    local function Enabled()
        return store.enabled ~= false and Owned()
    end

    local function SlotColor(key)
        if spec.slotColor then
            return spec.slotColor(key)
        end
        return DyresToolkit.HexColor(SLOTS[SLOT_INDEX[key]].color)
    end

    local function PanelColor(key)
        if spec.panelColor then
            return spec.panelColor(key)
        end
        return DyresToolkit.HexColor(PANEL_COLORS[key])
    end

    local function Order()
        local order, seen = {}, {}
        for _, key in ipairs(type(store.order) == "table" and store.order or {}) do
            if SLOT_INDEX[key] and not seen[key] then
                seen[key] = true
                order[#order + 1] = key
            end
        end
        for _, slot in ipairs(SLOTS) do
            if not seen[slot.key] then
                order[#order + 1] = slot.key
            end
        end
        return order
    end

    -- Spell sets ---------------------------------------------------------------

    -- Spell ID sets per slot, which slot a cast spell ID belongs to, and which
    -- slots the player knows (learned, not FutureSpell).
    local function BuildSpellSets()
        local byID, sets, known = DyresToolkit.IndexSpells(SLOTS)
        tracker.spellSlots = {}
        for id, slot in pairs(byID) do
            tracker.spellSlots[id] = slot.key
        end
        tracker.sets, tracker.slotKnown = sets, known
        local _, learned = DyresToolkit.SpellbookIDsByName()
        tracker.known = learned
    end

    -- The engine's candidate filter for a slot: its spell IDs, or for a slot
    -- matched by debuff type, that type without another slot's spell IDs.
    function tracker:CandidateFilters(key)
        local slot = SLOTS[SLOT_INDEX[key]]
        if not slot or not self.sets then
            return nil
        end
        if slot.dispelType then
            return {includeDispelTypes = {[slot.dispelType] = true}, excludeSpellIDs = self.sets[slot.excludeSlot]}
        end
        return {includeSpellIDs = self.sets[key]}
    end

    function tracker:KnowsSlot(key)
        return self.slotKnown[key] == true
    end

    -- The class's slots in the saved order, and a slot's color.
    function tracker:OrderedSlots()
        local slots = {}
        for _, key in ipairs(Order()) do
            slots[#slots + 1] = SLOTS[SLOT_INDEX[key]]
        end
        return slots
    end

    function tracker:SlotColor(key)
        return SlotColor(key)
    end

    local function SlotIcon(slot)
        for _, id in ipairs(slot.ids) do
            local texture = C_Spell.GetSpellTexture(id)
            if texture then
                return texture
            end
        end
    end

    function tracker:SlotIcon(key)
        local slot = SLOTS[SLOT_INDEX[key]]
        return slot and SlotIcon(slot)
    end

    -- Sizes ----------------------------------------------------------------------

    local function PanelAlpha(row)
        local opacity = type(store.panelOpacity) == "table" and store.panelOpacity[row.panelKey or "list"]
        return (type(opacity) == "number" and opacity or 100) / 100
    end

    local function IsCompact()
        return tracker.theme ~= "bars"
    end

    -- The slots a row shows, as SLOTS indexes in the saved order: one for
    -- each spell family you know, or all of them while you know none.
    local function ShownSlots()
        local shown, all = {}, {}
        for _, key in ipairs(Order()) do
            all[#all + 1] = SLOT_INDEX[key]
            if tracker.slotKnown[key] then
                shown[#shown + 1] = SLOT_INDEX[key]
            end
        end
        return #shown > 0 and shown or all
    end

    local function Sizes()
        return store.sizes[IsCompact() and "compact" or "bars"]
    end

    local function OutlineWidth()
        local spec, width = DyresToolkit.TRACKER_OUTLINE, tonumber(store.outlineWidth)
        if not width or width ~= width then
            return spec.default
        end
        return math.max(spec.min, math.min(spec.max, math.floor(width + 0.5)))
    end

    -- The stacked pinned rows' step keeps the outlines clear of each other.
    local function PinnedSpacing()
        return OutlineWidth() + OUTLINE_GAP + 2
    end

    local function TextScale()
        return Sizes().textScale / 100
    end

    local function OneLine(text)
        if type(text.SetWordWrap) == "function" then
            text:SetWordWrap(false)
        end
        if type(text.SetMaxLines) == "function" then
            text:SetMaxLines(1)
        end
        return text
    end

    local function ScaleFont(text)
        local font, size, flags = text:GetFont()
        if font and type(size) == "number" then
            text:SetFont(font, size * TextScale(), flags)
        end
        return text
    end

    local function HealthTextWidth()
        if not store.health or store.healthText == "none" or not HEALTH_TEXT_WIDTH[store.healthText] then
            return 0
        end
        return math.floor(HEALTH_TEXT_WIDTH[store.healthText] * TextScale() + 0.5)
    end

    local function NameAround()
        local position = Sizes().namePosition
        return position == "above" or position == "below"
    end

    local function NameLine()
        return math.floor(NAME_LINE * TextScale() + 0.5)
    end

    local function SlotSize()
        return IsCompact() and Sizes().iconSize or Sizes().lineHeight
    end

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

    -- Mob health -----------------------------------------------------------------

    -- Enemy health is secret in combat on Forever: it is never read here. A
    -- StatusBar and a FontString take secrets (SetMinMaxValues, SetValue,
    -- SetText); the number comes from AbbreviateNumbers, the percent from
    -- UnitHealthPercent(unit, true, CurveConstants.ScaleTo100) with "%d"
    -- (EllesmereUI's path on Forever). Number and percent are separate texts,
    -- so no secret string is formatted.
    local function PlaceHealth(row)
        local bar, where = row.health, Sizes().namePosition
        bar:ClearAllPoints()
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

    local function CreateHealth(row)
        if not store.health then
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
        local mode = store.healthText
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
        if not DyresToolkit.IsSecret(percent) and type(percent) ~= "number" then
            return ""
        end
        return string.format(both and "%d%% |" or "%d%%", percent)
    end

    local predictor = spec.predictor

    local function PredictAvailable()
        return predictor ~= nil and predictor:Available()
    end

    local function DrawRow(bar, guid, health, place, secretPlace)
        if not predictor then
            return false
        end
        return predictor:DrawRow(bar, guid, health, place, secretPlace)
    end

    -- The health a row's bar last showed, when readable (Classic Era): a list
    -- row that loses its unit keeps its bar and its prediction (John, WTF
    -- 1.4.0). Only where the prediction runs.
    local function KnownHealth(row)
        local known = row.knownHealth
        if known and row.guid and known.guid == row.guid then
            return known
        end
    end

    -- Where DIES goes on a row: in place of the health number (hidden while
    -- DIES shows); with the percent only, just left of it; else the bar's end.
    -- Then where it goes while the health is secret (WoW: Forever in combat):
    -- the numbers stay, so DIES goes just left of the first of them, in the
    -- room between the name and its texts (John's screenshot, 2026-11-09:
    -- "43% |4DIES"); without texts, the bar's end.
    local function RowDiesPlace(row)
        local first = row.healthPercent or row.healthNumber
        local secret = first and {"RIGHT", first, "LEFT", -2} or nil
        if row.healthNumber then
            return {"LEFT", row.healthNumber, "LEFT", 0}, secret
        elseif row.healthPercent then
            return {"RIGHT", row.healthPercent, "LEFT", -2}, secret
        end
    end

    local function UpdateHealth(row)
        local bar = row.health
        if not bar then
            return
        end
        local unit = row.boundUnit
        if not unit or unit == "none" or not UnitExists(unit) or type(UnitHealth) ~= "function"
            or type(UnitHealthMax) ~= "function" then
            if row.healthPercent then
                row.healthPercent:SetText("")
            end
            if row.healthNumber then
                row.healthNumber:SetText("")
            end
            local known = KnownHealth(row)
            if not known then
                bar:Hide()
                DrawRow(bar, nil)
                return
            end
            bar:SetMinMaxValues(0, known.max)
            bar:SetValue(known.health)
            bar:Show()
            local place, secretPlace = RowDiesPlace(row)
            DrawRow(bar, row.guid, known.health, place, secretPlace)
            return
        end
        local health, maxHealth = UnitHealth(unit), UnitHealthMax(unit)
        local guid = row.guid or (predictor and predictor.Key and predictor.Key(unit)) or DyresToolkit.ReadGUID(unit)
        if guid and PredictAvailable() and not DyresToolkit.IsSecret(health) and type(health) == "number"
                and not DyresToolkit.IsSecret(maxHealth) and type(maxHealth) == "number" then
            row.knownHealth = {guid = guid, health = health, max = maxHealth}
        else
            row.knownHealth = nil
        end
        bar:SetMinMaxValues(0, maxHealth)
        bar:SetValue(health)
        bar:Show()
        local place, secretPlace = RowDiesPlace(row)
        local dies = DrawRow(bar, guid, health, place, secretPlace)
        if row.healthPercent then
            row.healthPercent:SetText(PercentText(unit, row.healthNumber ~= nil and not dies))
        end
        if row.healthNumber then
            row.healthNumber:SetText((not dies and type(AbbreviateNumbers) == "function")
                and AbbreviateNumbers(UnitHealth(unit)) or "")
        end
    end

    -- Rows -------------------------------------------------------------------

    -- A DoT bar as it is built, inside the engine's initializer: its slot
    -- color with the panel's opacity in it, also on its texts. The engine's
    -- bars did not fade with their panel (found in client), so each ignores
    -- its parent's opacity and carries the panel's. Only here: once handed to
    -- the engine, touching it raised "Attempt to access forbidden object"
    -- (found in client, 13x). A new color or opacity rebuilds the rows.
    local function PrepareBar(row, index, bar, ...)
        if type(bar.IsForbidden) == "function" and bar:IsForbidden() then
            return
        end
        if type(bar.SetIgnoreParentAlpha) == "function" then
            bar:SetIgnoreParentAlpha(true)
        end
        local r, g, b = SlotColor(SLOTS[index].key)
        local alpha = PanelAlpha(row)
        bar:SetStatusBarColor(r, g, b, alpha)
        for index2 = 1, select("#", ...) do
            select(index2, ...):SetAlpha(alpha)
        end
        row.bars[index] = bar
    end

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

    -- A row in its panel's color: the border, the pinned outline, the health
    -- fill. All are the tracker's own, so they change at once, also in combat.
    local function ColorPanel(row)
        local r, g, b = PanelColor(row.panelKey or "list")
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
        row.panelKey = unit or "list"
        row:SetSize(RowWidth(), RowHeight())
        row:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2}})
        row:SetBackdropColor(BROWN[1], BROWN[2], BROWN[3], BROWN[4])
        local regions = CreateHealth(row)
        ColorPanel(row)
        row.name = ScaleFont(regions:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
        PlaceName(row)
        row.name:SetJustifyH("LEFT")
        CreateHealthText(row, regions)
        row.bars = {}
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
                label:SetText(slot.label)
            end
        end
        local container = DyresToolkit.CreateAuraContainer(row)
        if row.layer then
            container:SetFrameLevel(row:GetFrameLevel() + 2)
        end
        container:SetPoint("TOPLEFT", row, "TOPLEFT")
        container:SetSize(1, 1)
        for position, slotIndex in ipairs(tracker.shown) do
            local slot = SLOTS[slotIndex]
            container:AddAuraSlot(slot.key, AURA_FILTER, {
                candidateFilters = tracker:CandidateFilters(slot.key),
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

    -- Pinned rows ----------------------------------------------------------------

    local function SlotSpellName(slot)
        local name = slot.lastUsed and store[slot.lastUsed]
        if not name and slot.cast then
            name = DyresToolkit.SpellName(slot.cast)
        end
        if name and tracker.known[name] then
            return name
        end
    end

    -- The smart curse's known names, or nil without Curse of Weakness.
    local SMART_SLOT
    for _, slot in ipairs(SLOTS) do
        if type(slot.smart) == "table" then
            SMART_SLOT = slot
        end
    end

    local function SmartNames()
        if not SMART_SLOT then
            return nil
        end
        local names = {}
        for key, id in pairs(SMART_SLOT.smart) do
            local name = DyresToolkit.SpellName(id)
            names[key] = name and tracker.known[name] and name or nil
        end
        return names.weakness and names or nil
    end

    local function SmartMode()
        return store.curseMode == "smart"
    end

    -- The smart pick each place's click was last set to ("macro" is the
    -- unit-less one), so a target change rewrites only what changed.
    local function SmartPicks(names)
        local picks = {macro = DyresToolkit.SmartCursePick(names, "target") or false}
        for key, pinned in pairs(tracker.pinned) do
            picks[key] = DyresToolkit.SmartCursePick(names, pinned.unit) or false
        end
        return picks
    end

    -- Pinned slot clicks cast by name, so the game uses the highest rank known.
    local function ApplyCastButtons()
        DyresToolkit.OutOfCombat(tracker.pinned, function()
            local names = SmartNames()
            local picks = names and SmartPicks(names) or {}
            for key, pinned in pairs(tracker.pinned) do
                for slotIndex, button in pairs(pinned.casts) do
                    local slot = SLOTS[slotIndex]
                    local smart = names and slot == SMART_SLOT and SmartMode()
                    local name = smart and picks[key] or SlotSpellName(slot)
                    local text = name and (smart and DyresToolkit.SmartCurseMacro(names, name, pinned.unit)
                        or ("/use [@" .. pinned.unit .. (pinned.unit == "focus" and ",exists" or "")
                            .. ",harm,nodead] " .. name))
                    button:SetAttribute("type1", text and "macro" or nil)
                    button:SetAttribute("macrotext1", text or nil)
                    button.spellName, button.smart = name, smart and names or nil
                end
            end
            local body = names and ("#showtooltip\n" .. DyresToolkit.SmartCurseMacro(names, picks.macro)) or nil
            if tracker.smartButton then
                tracker.smartButton:SetAttribute("type1", body and "macro" or nil)
                tracker.smartButton:SetAttribute("macrotext1", body)
            end
            tracker.smartPicks = picks
            if body ~= tracker.smartBody then
                tracker.smartBody = body
                if spec.onSmartCurse then
                    spec.onSmartCurse(body)
                end
            end
        end)
    end

    -- The marker: the best curse for each pinned row's mob, also in combat.
    local function UpdateSmartMarks()
        local names = SmartMode() and store.curseMarker ~= false and SmartNames()
        for _, pinned in pairs(tracker.pinned) do
            local button = SMART_SLOT and pinned.casts[SLOT_INDEX[SMART_SLOT.key]]
            if button and button.mark then
                local key = names and UnitExists(pinned.unit) and select(2, DyresToolkit.SmartCursePick(names, pinned.unit))
                button.mark:SetText(key and SMART_MARKS[key] or "")
            end
        end
    end

    -- The mob changed: the marker at once; the clicks out of combat, only
    -- when a pick changed (in combat, once it ends).
    local function SmartTargetChanged()
        UpdateSmartMarks()
        local names = SmartNames()
        if not names then
            return
        end
        local picks, old = SmartPicks(names), tracker.smartPicks or {}
        for key, pick in pairs(picks) do
            if old[key] ~= pick then
                ApplyCastButtons()
                return
            end
        end
    end

    local function ShowCastTooltip(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        local names = button.smart
        if names then
            GameTooltip:SetText("Smart curse on your " .. button.unit .. ".", 1, 1, 1)
            GameTooltip:AddLine("Click: " .. button.spellName .. " (picked out of combat)", 1, 1, 1)
            GameTooltip:AddLine("Ctrl-click: " .. (names.tongues or names.weakness), 1, 1, 1)
            GameTooltip:AddLine("Shift-click: " .. names.weakness, 1, 1, 1)
            if names.recklessness then
                GameTooltip:AddLine("Alt-click: " .. names.recklessness, 1, 1, 1)
            end
            GameTooltip:AddLine("The letter shows the best curse for this mob: T Tongues for a caster, "
                .. "else E Elements or W Weakness.", 0.7, 0.7, 0.7, true)
        elseif button.spellName then
            GameTooltip:SetText("Click: cast " .. button.spellName .. " on your " .. button.unit .. ".", 1, 1, 1)
        else
            GameTooltip:SetText("You know no spell for this slot yet; it recasts the last one you used.",
                0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end

    local function StackOffset(key)
        local step = RowStep() + PinnedSpacing()
        return key == "target" and 0 or key == "focus" and step or step * 2
    end

    -- Locked, rows let clicks through to the world. While Ctrl is held (out
    -- of combat, with spec.ctrlMove) they take the mouse, so a Ctrl-drag moves
    -- a panel freely. Never changed during a drag, so its drop arrives; off as
    -- combat starts (PLAYER_REGEN_DISABLED comes before the lockdown).
    local function RowsTakeMouse()
        return not Locked() or tracker.ctrlMove == true
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
        local ctrl = not entering and spec.ctrlMove == true and Locked() and not InCombatLockdown()
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
            if movable.beginDrag then
                movable.beginDrag(tracker.sections[key])
            end
        end)
        frame:SetScript("OnDragStop", function()
            tracker.dragging = nil
            if movable.endDrag then
                movable.endDrag(tracker.sections[key])
            end
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
            if SLOTS[slotIndex] == SMART_SLOT then
                -- The smart marker: on the icon's lower right corner.
                local mark = ScaleFont(button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall"))
                if IsCompact() then
                    mark:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
                else
                    mark:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", BarIcon() + 2, -1)
                end
                mark:SetTextColor(1, 0.82, 0)
                button.mark = mark
            end
            button:SetScript("OnEnter", ShowCastTooltip)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.casts[slotIndex] = button
        end
        row:EnableMouse(true)
        DragScripts(row, key)
        local width = OutlineWidth()
        if width > 0 then
            local outline = CreateFrame("Frame", nil, row, "BackdropTemplate")
            local inset = width + OUTLINE_GAP
            outline:SetPoint("TOPLEFT", -inset, inset)
            outline:SetPoint("BOTTOMRIGHT", inset, -inset)
            outline:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = width})
            outline:EnableMouse(false)
            row.outline = outline
        end
        ColorPanel(row)
        return row
    end

    local function IsLiveHostile(unit)
        if not UnitExists(unit) then
            return false
        end
        local canAttack, dead = UnitCanAttack("player", unit), UnitIsDead(unit)
        return not DyresToolkit.IsSecret(canAttack) and canAttack == true
            and not (not DyresToolkit.IsSecret(dead) and dead == true)
    end

    -- A secret or missing name is "" (WTF's tracker rule).
    local function ReadName(unit)
        return DyresToolkit.ReadName(unit) or ""
    end

    -- Out of combat only: samples replace the state drivers with plain Show,
    -- and the switch (or another owner) hides the sections.
    local function ApplyPinnedVisibility()
        DyresToolkit.OutOfCombat(tracker.sections, function()
            local samples = not Locked()
            for key, row in pairs(tracker.pinned) do
                row:EnableMouse(RowsTakeMouse())
                UnregisterStateDriver(row, "visibility")
                if samples then
                    row:Show()
                    row.name:SetText(SAMPLE_NAMES[key])
                else
                    RegisterStateDriver(row, "visibility", PINNED[key].driver)
                end
            end
            for _, key in ipairs({"target", "focus"}) do
                tracker.sections[key]:SetShown(Enabled())
            end
        end)
    end

    -- Binding list rows ----------------------------------------------------------

    local function FindUnit(guid)
        return DyresToolkit.FindUnit(guid, spec.find or DEFAULT_FIND)
    end

    local function Bind(row, unit)
        local wanted = unit or "none"
        -- Still the same unit, maybe for another mob: only the health changes.
        if row.boundUnit == wanted then
            UpdateHealth(row)
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

    local function RemoveRow(row)
        row.guid, row.mobName, row.unseenSince, row.held = nil, nil, nil, nil
        Bind(row, nil)
        Layout()
    end

    -- A mob seen dead on any unit loses its row at once, and its GUID is kept
    -- until combat ends, so nothing lists it again (WTF player report).
    local function NoteDeath(unit)
        if not DyresToolkit.IsDead(unit) then
            return
        end
        local guid = DyresToolkit.ReadGUID(unit)
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

    -- A plate went: its token may show another mob next, so a row or a cast
    -- keyed by it goes now.
    local function DropPlateKey(unit)
        local key = "plate:" .. unit
        for _, cast in pairs(tracker.casts) do
            if cast.guid == key then
                cast.guid = nil
            end
        end
        for _, row in ipairs(tracker.rows) do
            if row.guid == key then
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

    local function RefreshBindings()
        for _, row in ipairs(tracker.rows) do
            if row.guid then
                local unit = FindUnit(row.guid)
                if unit and DyresToolkit.IsDead(unit) then
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

    -- Layout -------------------------------------------------------------------

    -- A list not yet dragged hangs below the lowest stacked pinned row the
    -- game shows (WTF player feedback); a dragged pinned row does not count,
    -- and a hidden target row keeps its space when the focus row shows.
    local function FollowPinnedRows()
        local sections = type(store.sections) == "table" and store.sections or {}
        if sections.list then
            return
        end
        local listTop = 0
        if not Locked() then
            listTop = StackOffset("list")
        else
            for _, key in ipairs({"target", "focus"}) do
                if not sections[key] and IsLiveHostile(PINNED[key].unit) then
                    listTop = math.max(listTop, StackOffset(key) + RowStep() + PinnedSpacing())
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

    -- The list leaves out your target and focus, which have pinned rows.
    function Layout()
        local samples = not Locked()
        for key, row in pairs(tracker.pinned) do
            if not samples then
                row.name:SetText(ReadName(PINNED[key].unit))
            end
        end
        local target, focus = DyresToolkit.MobKey("target"), DyresToolkit.MobKey("focus")
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
                if row and not row.guid then
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
            row:EnableMouse(RowsTakeMouse())
            if not used[row] then
                row:Hide()
                if row.sample then
                    row.mobName, row.sample = nil, nil
                end
            end
        end
        list:SetShown(Enabled() and #listed > 0)
        FollowPinnedRows()
    end

    -- Casts --------------------------------------------------------------------

    local function Track(guid, mobName)
        if tracker.dead[guid] or not Enabled() then
            return
        end
        local token = DyresToolkit.KeyPlate(guid)
        if token and not UnitExists(token) then
            return
        end
        for _, row in ipairs(tracker.rows) do
            if row.guid == guid or (token and row.guid and row.boundUnit == token) then
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
        DyresToolkit.LearnPlates()
        row.guid, row.mobName, row.firstSeen, row.unseenSince = guid, mobName, GetTime(), nil
        Bind(row, FindUnit(guid))
        Layout()
    end

    -- Remembers the Bane or Curse just cast, for the pinned slots to recast
    -- (the slot's `lastUsed` key in the owner's store).
    local function RememberLastUsed(spellID)
        local key = tracker.spellSlots[spellID]
        local slot = key and SLOTS[SLOT_INDEX[key]]
        if slot and slot.lastUsed then
            local name = DyresToolkit.SpellName(spellID)
            if name and store[slot.lastUsed] ~= name then
                store[slot.lastUsed] = name
                ApplyCastButtons()
            end
        end
    end

    -- The mob a cast lands on is the one it was aimed at as it started (WTF
    -- player feedback): only this cast's entry goes.
    local function OnCastSucceeded(castGUID)
        if DyresToolkit.IsSecret(castGUID) then
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

    -- The mob and name a cast goes to. A secret name on either side cannot
    -- decide, so your target it is (a row's text takes a secret name).
    local function LockMob(target)
        local guid = DyresToolkit.LockCast(target, spec.lock or DEFAULT_LOCK)
        if guid then
            return guid, target
        end
        local targetName = UnitName("target")
        if DyresToolkit.IsSecret(target) or DyresToolkit.IsSecret(targetName) then
            return DyresToolkit.MobKey("target"), targetName
        end
    end

    local function OnCastSent(target, castGUID, spellID)
        if DyresToolkit.IsSecret(spellID) or DyresToolkit.IsSecret(castGUID)
            or (not DyresToolkit.IsSecret(target) and (type(target) ~= "string" or target == "")) then
            return
        end
        tracker.lastCast = {spellID = spellID, slot = tracker.spellSlots[spellID]}
        if tracker.spellSlots[spellID] then
            local guid, mobName = LockMob(target)
            tracker.lastCast.key = guid and (DyresToolkit.KeyPlate(guid) and "plate" or "guid") or "none"
            tracker.casts[castGUID] = {target = mobName, spellID = spellID, guid = guid}
        end
    end

    -- New ranks learned: every row's slots accept the new spell IDs. Only the
    -- slots the rows were built with: asking for one a row lacks raises "aura
    -- slot ... was not found" (found in client, for Siphon Life).
    local function ApplySpellSets()
        DyresToolkit.OutOfCombat(tracker.spellSlots, function()
            BuildSpellSets()
            local function Update(row)
                for _, slotIndex in ipairs(tracker.shown) do
                    local key = SLOTS[slotIndex].key
                    row.container:SetAuraSlotCandidateFilters(key, tracker:CandidateFilters(key))
                end
            end
            for _, row in ipairs(tracker.rows) do
                Update(row)
            end
            for _, row in pairs(tracker.pinned) do
                Update(row)
            end
            ApplyCastButtons()
            -- A newly learned family's slot comes with a rebuild.
            if KnownSlotsChanged() then
                BuildRows()
            end
            if spec.onSpellsChanged then
                spec.onSpellsChanged()
            end
        end)
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

    -- Builds the pinned rows and the list rows for the current theme,
    -- keeping the mobs they tracked; out of combat (secure rows).
    function BuildRows()
        DyresToolkit.OutOfCombat(tracker.rows, function()
            tracker.theme = store.theme
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
            Place()
            tracker.pinned = {target = CreatePinnedRow("target"), focus = CreatePinnedRow("focus")}
            local rows = {}
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
                rows[index] = row
            end
            -- The same table, so OutOfCombat's key stays this tracker's.
            for index = #tracker.rows, 1, -1 do
                tracker.rows[index] = nil
            end
            for index, row in ipairs(rows) do
                tracker.rows[index] = row
            end
            ApplyCastButtons()
            UpdateSmartMarks()
            ApplyPinnedVisibility()
            Layout()
        end)
    end

    function KnownSlotsChanged()
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

    -- Placement ------------------------------------------------------------------

    -- Out of combat only: the sections hold secure rows. A section not yet
    -- dragged hangs from the stack frame, where the one tracker frame was.
    function Place()
        local stack, position, point = tracker.stack, store.position, spec.point
        local sections = type(store.sections) == "table" and store.sections or {}
        stack:SetSize(RowWidth(), (RowStep() + PinnedSpacing()) * 2)
        stack:ClearAllPoints()
        if position then
            stack:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
        elseif point then
            stack:SetPoint(point[1], UIParent, point[2], point[3], point[4])
        else
            stack:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
        end
        for _, key in ipairs(SECTION_KEYS) do
            local frame, saved = tracker.sections[key], sections[key]
            frame:ClearAllPoints()
            if saved then
                frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
            else
                frame:SetPoint("TOPLEFT", stack, "TOPLEFT", 0, -StackOffset(key))
            end
        end
        tracker.listTop = not sections.list and StackOffset("list") or nil
    end

    -- A panel's opacity: the whole section frame, at once, also in combat.
    local function ApplyPanelOpacity()
        for key, frame in pairs(tracker.sections) do
            local opacity = type(store.panelOpacity) == "table" and store.panelOpacity[key]
            frame:SetAlpha((type(opacity) == "number" and opacity or 100) / 100)
        end
    end

    -- Events -------------------------------------------------------------------

    events:SetScript("OnEvent", function(_, event, unit, first, second, third)
        if event == "UNIT_SPELLCAST_SENT" then
            OnCastSent(first, second, third)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            OnCastSucceeded(first)
        elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
            if not DyresToolkit.IsSecret(first) then
                tracker.casts[first] = nil
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Out of combat no DoT of yours is ticking on a live mob.
            ClearAll()
            if KnownSlotsChanged() then
                BuildRows()
            end
        elseif event == "SPELLS_CHANGED" then
            ApplySpellSets()
        elseif event == "MODIFIER_STATE_CHANGED" then
            UpdateCtrlMove()
        elseif event == "UNIT_DISPLAYPOWER" or event == "UNIT_MAXPOWER" then
            if unit == "target" or unit == "focus" then
                SmartTargetChanged()
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            UpdateCtrlMove(true)
        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            if DyresToolkit.IsSecret(unit) then
                return
            end
            if event == "UNIT_HEALTH" then
                NoteDeath(unit)
            end
            for _, row in ipairs(tracker.rows) do
                if row.guid and row.boundUnit == unit then
                    if event == "UNIT_HEALTH" and DyresToolkit.IsDead(unit) then
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
            if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
                SmartTargetChanged()
            end
            local oldTarget, oldFocus = tracker.shownTarget, tracker.shownFocus
            if event == "NAME_PLATE_UNIT_REMOVED" and not DyresToolkit.IsSecret(unit) then
                NoteDeath(unit)
                DropPlateKey(unit)
                DyresToolkit.ForgetPlate(unit)
            elseif event == "NAME_PLATE_UNIT_ADDED" and not DyresToolkit.IsSecret(unit) then
                DyresToolkit.ForgetPlate(unit)
                DyresToolkit.LearnPlate(unit)
            else
                DyresToolkit.LearnPlates()
            end
            RefreshBindings()
            -- Your target or focus just left with no unit showing the mob:
            -- most likely dead, so it is not listed until a unit shows it.
            local target, focus = DyresToolkit.MobKey("target"), DyresToolkit.MobKey("focus")
            for _, row in ipairs(tracker.rows) do
                if row.guid and (row.guid == oldTarget or row.guid == oldFocus) and row.guid ~= target
                        and row.guid ~= focus and row.boundUnit == "none" then
                    row.held = true
                end
            end
            Layout()
        end
    end)

    -- Public -------------------------------------------------------------------

    -- The lock, the switch, or the owner changed: visibility and layout.
    function tracker:Refresh()
        DyresToolkit.SetOwnerEnabled(kind, spec.addon, store.enabled ~= false)
        ApplyPinnedVisibility()
        Layout()
    end

    -- A theme, size, health, order, slot color, or panel opacity change: the
    -- engine places slots only as rows are built, so they are rebuilt (out of
    -- combat; in combat, when it ends), keeping the tracked mobs.
    function tracker:Rebuild()
        ApplyPanelOpacity()
        BuildRows()
    end

    -- New panel colors: the tracker's own regions, at once, also in combat.
    function tracker:ApplyPanelColors()
        for _, row in ipairs(self.rows) do
            ColorPanel(row)
        end
        for _, row in pairs(self.pinned) do
            ColorPanel(row)
        end
    end

    -- A panel's opacity: the panel fades at once; its bars follow with the rebuild.
    function tracker:ApplyPanelOpacity()
        ApplyPanelOpacity()
        BuildRows()
    end

    -- The owner cleared its saved places: the sections stack again.
    function tracker:ResetPosition()
        DyresToolkit.OutOfCombat(self.stack, Place)
    end

    -- The damage to come changed for one mob, or every mob (nil).
    function tracker:RefreshPrediction(guid)
        for _, row in ipairs(self.rows) do
            if row.guid and (guid == nil or row.guid == guid) then
                UpdateHealth(row)
            end
        end
        for _, pinned in pairs(self.pinned) do
            if guid == nil or DyresToolkit.ReadGUID(pinned.unit) == guid then
                UpdateHealth(pinned)
            end
        end
    end

    function tracker:IsOwner()
        return Owned()
    end

    -- The owner changed curseMode or curseMarker: the clicks (out of
    -- combat) and the marker (at once).
    function tracker:ApplySmartCurse()
        ApplyCastButtons()
        UpdateSmartMarks()
    end

    -- The "! Curse" macro body, or nil without Curse of Weakness.
    function tracker:SmartCurseBody()
        local names = SmartNames()
        return names and ("#showtooltip\n" .. DyresToolkit.SmartCurseMacro(names,
            (DyresToolkit.SmartCursePick(names, "target"))))
    end

    -- Lines for the owner's debug command (it adds its own prefix).
    function tracker:DebugLines()
        local lines = {}
        local placed = {}
        local sections = type(store.sections) == "table" and store.sections or {}
        for _, key in ipairs(SECTION_KEYS) do
            placed[#placed + 1] = key .. "=" .. (sections[key] and "moved" or "stacked")
        end
        lines[#lines + 1] = "sections " .. table.concat(placed, " ") .. (store.position and " (stack moved)" or "")
            .. " owner=" .. tostring(DyresToolkit.KindOwner(kind))
        for slotIndex, slot in ipairs(SLOTS) do
            local ids = {}
            for id in pairs(self.sets[slot.key]) do
                ids[#ids + 1] = id
            end
            table.sort(ids)
            local matches = slot.dispelType and (slot.dispelType .. " debuffs except " .. slot.excludeSlot) or "ids"
            local cast = self.pinned.target and self.pinned.target.casts[slotIndex]
            lines[#lines + 1] = string.format("slot=%s recast=%s matches=%s ids=%s", slot.key,
                tostring(cast and cast.spellName), matches, table.concat(ids, ","))
        end
        if SMART_SLOT then
            local picks = self.smartPicks or {}
            lines[#lines + 1] = string.format("smart mode=%s weakness=%s mana target=%s focus=%s click target=%s "
                .. "focus=%s macro=%s", tostring(store.curseMode or "last"), tostring(SmartNames() ~= nil),
                tostring(DyresToolkit.UnitHasMana("target")), tostring(DyresToolkit.UnitHasMana("focus")),
                tostring(picks.target), tostring(picks.focus), tostring(picks.macro))
            for _, key in ipairs({"target", "focus"}) do
                local pinned = self.pinned[key]
                local button = pinned and pinned.casts[SLOT_INDEX[SMART_SLOT.key]]
                local mark = button and button.mark
                if mark then
                    lines[#lines + 1] = string.format("smart mark %s text=%q shown=%s visible=%s level=%s "
                        .. "container=%s rowShown=%s marker=%s", key, tostring(mark:GetText()),
                        tostring(mark:IsShown()), tostring(mark:IsVisible()), tostring(button:GetFrameLevel()),
                        tostring(pinned.container:GetFrameLevel()), tostring(pinned:IsShown()),
                        tostring(store.curseMarker))
                else
                    lines[#lines + 1] = "smart mark " .. key .. " none (no Curse slot button on this row)"
                end
            end
        end
        local last = self.lastCast
        if last then
            lines[#lines + 1] = string.format("lastCast spell=%d name=%s slot=%s%s", last.spellID,
                tostring(DyresToolkit.SpellName(last.spellID)), tostring(last.slot),
                last.key and (" mob=" .. last.key) or "")
        end
        local shown, readable, known, targetPlate = 0, 0, 0, "none"
        for index = 1, MAX_NAMEPLATE_UNITS do
            local unit = "nameplate" .. index
            if UnitExists(unit) then
                shown = shown + 1
                readable = readable + (DyresToolkit.ReadGUID(unit) and 1 or 0)
                known = known + (DyresToolkit.PlateGUID(unit) and 1 or 0)
                local same = UnitIsUnit(unit, "target")
                if not DyresToolkit.IsSecret(same) and same == true then
                    targetPlate = unit
                end
            end
        end
        lines[#lines + 1] = string.format("plates shown=%d readableGUID=%d known=%d targetPlate=%s targetGUID=%s",
            shown, readable, known, targetPlate, tostring(DyresToolkit.ReadGUID("target") ~= nil))
        for index, row in ipairs(self.rows) do
            if row.guid then
                lines[#lines + 1] = string.format("row %d name=%s key=%s unit=%s unseen=%s held=%s", index,
                    DyresToolkit.Describe(row.mobName), DyresToolkit.KeyPlate(row.guid) and "plate" or "guid",
                    tostring(row.boundUnit), tostring(row.unseenSince ~= nil), tostring(row.held == true))
            end
        end
        return lines
    end

    -- Build --------------------------------------------------------------------

    BuildSpellSets()
    DyresToolkit.ClaimOwner(kind, spec.addon, spec.priority)
    tracker.stack = CreateFrame("Frame", nil, UIParent)
    tracker.stack:EnableMouse(false)
    for _, key in ipairs(SECTION_KEYS) do
        local frame = CreateFrame("Frame", spec.names[key], UIParent)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame:EnableMouse(false)
        tracker.sections[key] = frame
        if movable.register then
            movable.register(frame, function(position)
                if type(store.sections) ~= "table" then
                    store.sections = {}
                end
                store.sections[key] = position
            end)
        end
    end
    tracker.anchor, tracker.list = tracker.sections.target, tracker.sections.list
    ApplyPanelOpacity()
    tracker.theme = store.theme
    tracker.shown = ShownSlots()
    for _, event in ipairs({"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED",
        "PLAYER_FOCUS_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "SPELLS_CHANGED",
        "UNIT_HEALTH", "UNIT_MAXHEALTH", "MODIFIER_STATE_CHANGED", "UNIT_DISPLAYPOWER", "UNIT_MAXPOWER"}) do
        events:RegisterEvent(event)
    end
    if type(spec.names.smartCurse) == "string" then
        -- The keybind's button: never shown; a CLICK binding clicks it.
        local button = CreateFrame("Button", spec.names.smartCurse, UIParent, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("useOnKeyDown", false)
        button:Hide()
        tracker.smartButton = button
    end
    for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED"}) do
        events:RegisterUnitEvent(event, "player")
    end
    DyresToolkit.OnOwnerChanged(kind, function()
        ApplyPinnedVisibility()
        Layout()
    end)
    if predictor and predictor.SetTracker then
        predictor:SetTracker(tracker)
    end
    BuildRows()
    return tracker
end
