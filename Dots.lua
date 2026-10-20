local _, WTF = ...

-- Nameplate DoT dots: a small bubble above each hostile nameplate in combat,
-- one dot per DoT you know and chose for nameplates (WTF.DOT_SLOTS), in the
-- same colors as the tracker's bars. A grey dot means the DoT is missing; your DoT's
-- color covers it while the DoT is up. As in the tracker, an engine
-- AuraContainer bound to the plate's unit decides which colored dots show;
-- WTF never reads the auras. Off by default (author-approved), as it can get
-- busy.

local DOT_SIZE = 8
local DOT_GAP = 3
local PADDING = 3
local GREY = {0.35, 0.35, 0.35}
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local AURA_FILTER = "HARMFUL|PLAYER"
local CONTAINER_TEMPLATE = "CustomAuraContainerTemplate"
local MAX_NAMEPLATE_UNITS = 40

local dots = {free = {}, byUnit = {}, all = {}, known = {}, inCombat = false, available = false}

-- The dots shown: slots whose spells you know and that you chose for nameplates.
local function KnownDots()
    local known = {}
    for _, slot in ipairs(WTF.DOT_SLOTS) do
        if WTF.TrackerKnowsSlot(slot.key) and WTF.db.tracker.onPlates[slot.key] then
            known[#known + 1] = slot
        end
    end
    return known
end

-- At least one DoT you know, whatever the nameplate choices.
function WTF.HasTrackableDots()
    if not dots.available then
        return false
    end
    for _, slot in ipairs(WTF.DOT_SLOTS) do
        if slot.plate and WTF.TrackerKnowsSlot(slot.key) then
            return true
        end
    end
    return false
end

-- The colored dots are WTF's own regions, so they can change color at any time.
function WTF.ApplyDotColors()
    for _, bubble in ipairs(dots.all) do
        for key, texture in pairs(bubble.colored) do
            texture:SetColorTexture(WTF.SlotColor(key))
        end
    end
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

-- Places the engine's dot button; the only time WTF may touch it.
local function DotInitializer(bubble, index, key)
    return function(button)
        button:ClearAllPoints()
        button:SetPoint("LEFT", bubble, "LEFT", DotOffset(index), 0)
        button:SetSize(DOT_SIZE, DOT_SIZE)
        button:SetMouseClickEnabled(false)
        button:SetMouseMotionEnabled(false)
        local dot = Circle(button, "ARTWORK", WTF.SlotColor(key))
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
    local container = CreateFrame("AuraContainer", nil, bubble, CONTAINER_TEMPLATE)
    container:SetPoint("TOPLEFT")
    container:SetSize(1, 1)
    for index, slot in ipairs(dots.known) do
        Circle(bubble, "BORDER", GREY[1], GREY[2], GREY[3]):SetPoint("LEFT", DotOffset(index), 0)
        container:AddAuraSlot(slot.key, AURA_FILTER, {
            candidateFilters = WTF.TrackerCandidateFilters(slot.key),
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
    return not WTF.IsSecret(canAttack) and canAttack == true and not (not WTF.IsSecret(dead) and dead == true)
end

-- The whole bubble's opacity (a setting): its background and both kinds of
-- dot. The bubble is WTF's own frame, so it changes at once, also in combat.
local function Opacity()
    return WTF.db.tracker.plateDotsOpacity / 100
end

function WTF.SetPlateDotsOpacity(percent)
    WTF.db.tracker.plateDotsOpacity = WTF.SanitizeWhole(percent, WTF.PLATE_DOTS_OPACITY_MIN,
        WTF.PLATE_DOTS_OPACITY_MAX, WTF.DEFAULT_PLATE_DOTS_OPACITY)
    for _, bubble in ipairs(dots.all) do
        bubble:SetAlpha(Opacity())
    end
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
    if not WTF.db.tracker.enabled or not WTF.db.tracker.plateDots or #dots.known == 0 then
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
    bubble:SetPoint("BOTTOM", plate, "TOP", 0, WTF.db.tracker.plateDotsOffset)
    bubble.unit = unit
    bubble:SetAlpha(Opacity())
    dots.byUnit[unit] = bubble
    bubble.container:SetUnit(unit)
    bubble.container:UpdateAllAuras()
    UpdateShown(bubble)
end

local function DetachAll()
    for unit in pairs(dots.byUnit) do
        Detach(unit)
    end
end

local function AttachAll()
    for index = 1, MAX_NAMEPLATE_UNITS do
        local unit = "nameplate" .. index
        if UnitExists(unit) then
            Attach(unit)
        end
    end
end

-- Settings changed, or new spells learned: rebuild the bubbles.
function WTF.RefreshPlateDots()
    if not dots.available then
        return
    end
    DetachAll()
    dots.known = KnownDots()
    dots.generation = (dots.generation or 0) + 1
    dots.free = {}
    dots.all = {}
    AttachAll()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        if not WTF.IsSecret(unit) then
            Attach(unit)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if not WTF.IsSecret(unit) then
            Detach(unit)
        end
    elseif event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
        local bubble = dots.byUnit[unit]
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

function WTF.InitializePlateDots()
    if type(WTF.TrackerCandidateFilters) ~= "function" or not WTF.TrackerCandidateFilters("corruption")
        or type(C_NamePlate) ~= "table" or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then
        return
    end
    dots.available = true
    local inCombat = UnitAffectingCombat("player")
    dots.inCombat = not WTF.IsSecret(inCombat) and inCombat == true
    for _, event in ipairs({"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED", "UNIT_HEALTH", "UNIT_FLAGS"}) do
        events:RegisterEvent(event)
    end
    WTF.RefreshPlateDots()
end
