local _, ns = ...
local DyresToolkit = ns.toolkit

-- Nameplate DoT dots, for every Dyre's AddOn (Toolkit 2.5.0, engine stage C;
-- lead-approved plan, 2026-11-01). Moved from Warlock Tools Forever 1.4.1's
-- Dots.lua, which keeps its own copy until it switches over. In combat, a
-- small bubble above each live hostile nameplate with one dot per DoT you
-- know and chose for nameplates, in the tracker's colors. A grey dot means
-- the DoT is missing; your DoT's color covers it while the DoT is up. An
-- AuraContainer bound to the plate's unit decides which colored dots show;
-- nothing here reads the auras.

local DOT_SIZE = 8
local DOT_GAP = 3
local PADDING = 3
local GREY = {0.35, 0.35, 0.35}
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local AURA_FILTER = "HARMFUL|PLAYER"
local MAX_NAMEPLATE_UNITS = 40

-- spec (required: tracker, store):
--   tracker   a DotTracker: its slots' filters and which you know; the dots
--             show only while it owns its class's DoTs
--   store     the owner's saved table, read live: enabled, plateDots (on),
--             plateDotsOffset (height above the plate), plateDotsOpacity
--             (percent), onPlates ({[key] = true})
--   slots     function() -> the slots in display order (default the
--             tracker's class slots, in store.order)
--   color     function(key) -> r, g, b (default the slot's color)
-- Returns the dots, else nil and what is missing.
function DyresToolkit.CreatePlateDots(spec)
    if type(spec) ~= "table" or type(spec.tracker) ~= "table" or type(spec.store) ~= "table" then
        return nil, "spec"
    end
    if type(C_NamePlate) ~= "table" or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then
        return nil, "C_NamePlate.GetNamePlateForUnit"
    end
    local tracker, store = spec.tracker, spec.store
    local dots = {free = {}, byUnit = {}, all = {}, known = {}, inCombat = false, generation = 0}
    local events = CreateFrame("Frame")
    local Slots = spec.slots or function() return tracker:OrderedSlots() end
    local Color = spec.color or function(key) return tracker:SlotColor(key) end

    -- The dots shown, in order: slots whose spells you know and that you
    -- chose for nameplates.
    local function KnownDots()
        local known = {}
        local onPlates = type(store.onPlates) == "table" and store.onPlates or {}
        for _, slot in ipairs(Slots()) do
            if tracker:KnowsSlot(slot.key) and onPlates[slot.key] then
                known[#known + 1] = slot
            end
        end
        return known
    end

    local function Circle(parent, layer, r, g, b)
        local texture = parent:CreateTexture(nil, layer)
        texture:SetSize(DOT_SIZE, DOT_SIZE)
        texture:SetColorTexture(r, g, b)
        local mask = parent:CreateMaskTexture()
        mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(texture)
        texture:AddMaskTexture(mask)
        return texture
    end

    local function DotOffset(index)
        return PADDING + (index - 1) * (DOT_SIZE + DOT_GAP)
    end

    -- Places the engine's dot button; the only time it may be touched.
    local function DotInitializer(bubble, index, key)
        return function(button)
            button:ClearAllPoints()
            button:SetPoint("LEFT", bubble, "LEFT", DotOffset(index), 0)
            button:SetSize(DOT_SIZE, DOT_SIZE)
            button:SetMouseClickEnabled(false)
            button:SetMouseMotionEnabled(false)
            local dot = Circle(button, "ARTWORK", Color(key))
            dot:SetPoint("CENTER")
            bubble.colored[key] = dot
        end
    end

    local function CreateBubble()
        local bubble = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        bubble:SetSize(PADDING * 2 + #dots.known * DOT_SIZE + (#dots.known - 1) * DOT_GAP, DOT_SIZE + PADDING * 2)
        bubble:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2}})
        bubble:SetBackdropColor(0, 0, 0, 0.7)
        bubble:SetBackdropBorderColor(0.6, 0.5, 0.3)
        bubble:EnableMouse(false)
        bubble.colored = {}
        local container = DyresToolkit.CreateAuraContainer(bubble)
        container:SetPoint("TOPLEFT")
        container:SetSize(1, 1)
        for index, slot in ipairs(dots.known) do
            Circle(bubble, "BORDER", GREY[1], GREY[2], GREY[3]):SetPoint("LEFT", DotOffset(index), 0)
            container:AddAuraSlot(slot.key, AURA_FILTER, {
                candidateFilters = tracker:CandidateFilters(slot.key),
                initializeFrame = DotInitializer(bubble, index, slot.key),
            })
        end
        bubble.container = container
        bubble.generation = dots.generation
        dots.all[#dots.all + 1] = bubble
        bubble:Hide()
        return bubble
    end

    local function IsLiveHostile(unit)
        local canAttack, dead = UnitCanAttack("player", unit), UnitIsDead(unit)
        return not DyresToolkit.IsSecret(canAttack) and canAttack == true
            and not (not DyresToolkit.IsSecret(dead) and dead == true)
    end

    local function Opacity()
        local opacity = store.plateDotsOpacity
        return (type(opacity) == "number" and opacity or 100) / 100
    end

    local function UpdateShown(bubble)
        bubble:SetShown(dots.inCombat and IsLiveHostile(bubble.unit))
    end

    local function Detach(unit)
        local bubble = dots.byUnit[unit]
        if not bubble then
            return
        end
        dots.byUnit[unit] = nil
        bubble.container:SetUnit("none")
        bubble.unit = nil
        bubble:Hide()
        bubble:SetParent(UIParent)
        if bubble.generation == dots.generation then
            dots.free[#dots.free + 1] = bubble
        end
    end

    local function Attach(unit)
        if store.enabled == false or not store.plateDots or #dots.known == 0 or not tracker:IsOwner() then
            return
        end
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if not plate or plate:IsForbidden() then
            return
        end
        Detach(unit)
        local bubble = table.remove(dots.free) or CreateBubble()
        bubble:SetParent(plate)
        bubble:ClearAllPoints()
        bubble:SetPoint("BOTTOM", plate, "TOP", 0, type(store.plateDotsOffset) == "number" and store.plateDotsOffset or 50)
        bubble.unit = unit
        bubble:SetAlpha(Opacity())
        dots.byUnit[unit] = bubble
        bubble.container:SetUnit(unit)
        bubble.container:UpdateAllAuras()
        UpdateShown(bubble)
    end

    -- Settings changed, new spells learned, or another owner: rebuild the bubbles.
    function dots:Refresh()
        for unit in pairs(self.byUnit) do
            Detach(unit)
        end
        self.known = KnownDots()
        self.generation = self.generation + 1
        self.free, self.all = {}, {}
        for index = 1, MAX_NAMEPLATE_UNITS do
            local unit = "nameplate" .. index
            if UnitExists(unit) then
                Attach(unit)
            end
        end
    end

    -- The colored dots are the bubbles' own regions: a new color applies at once.
    function dots:ApplyColors()
        for _, bubble in ipairs(self.all) do
            for key, texture in pairs(bubble.colored) do
                texture:SetColorTexture(Color(key))
            end
        end
    end

    -- The whole bubble's opacity, at once, also in combat.
    function dots:ApplyOpacity()
        for _, bubble in ipairs(self.all) do
            bubble:SetAlpha(Opacity())
        end
    end

    events:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then
            if not DyresToolkit.IsSecret(unit) then
                Attach(unit)
            end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            if not DyresToolkit.IsSecret(unit) then
                Detach(unit)
            end
        elseif event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
            local bubble = not DyresToolkit.IsSecret(unit) and dots.byUnit[unit]
            if bubble then
                UpdateShown(bubble)
            end
        else
            dots.inCombat = event == "PLAYER_REGEN_DISABLED"
            for _, bubble in pairs(dots.byUnit) do
                UpdateShown(bubble)
            end
        end
    end)

    local inCombat = UnitAffectingCombat("player")
    dots.inCombat = not DyresToolkit.IsSecret(inCombat) and inCombat == true
    for _, event in ipairs({"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED", "UNIT_HEALTH", "UNIT_FLAGS"}) do
        events:RegisterEvent(event)
    end
    DyresToolkit.OnOwnerChanged(tracker.ownerKind, function()
        dots:Refresh()
    end)
    dots:Refresh()
    return dots
end
