local _, ns = ...
local DyresToolkit = ns.toolkit

-- Health bars of other frame AddOns, and the damage-to-come block and DIES
-- badge drawn on them (Toolkit 2.4.0; Dyre's Debuff Tracker phase 1,
-- coordinator-approved 2026-10-30). Moved from Warlock Tools Forever 1.4.0's
-- Predict.lua, which keeps its own copy until its prediction moves to Dyre's
-- Debuff Tracker. The look comes from the caller (its own settings); the
-- toolkit keeps none. It only draws: the caller gives the damage and health,
-- and draws nothing with a secret health.
--
-- The block: from the bar's left edge to its fill's right edge, filled from
-- the right with the damage to come out of the health left, so it ends where
-- the health ends and grows left. A reverse-filled bar (Shadowed Unit Frames
-- can) gets the mirror image; a vertical bar gets none.
--
-- DIES (John, WTF 1.4.0, after his Era test: hard to read under a row's
-- texts, over a nameplate's name, and small on the target frame): a badge
-- with a red skull and "DIES" in red with a thick black outline, above every
-- text of the bar's frame. The skull is the game's level skull
-- (UI-TargetingFrame-Skull) tinted red, not the raid marker's: a mob marked
-- with the skull by /tm shows that marker on the same frames (Dyre's AddOns
-- never call SetRaidTarget), and the two must not look alike. The badge is
-- the same size on every frame: its scale undoes the bar's own (found in
-- client: Platynator scales its display down).
--
-- Where the badge goes, per kind of bar, unless the adapter or the caller
-- says otherwise:
--   target  unit frames: just left of the bar. Found in client: centered, it
--           ran into SUF's name; SUF writes on the bar's left and right
--           inside, Blizzard's frame above it and in its middle.
--   plate   nameplates: just right of the bar, clear of the name above it and
--           of Plater's raid marker on the left. Platynator: further right,
--           past its target arrows.
--   row     a tracker row: at the bar's right end, inside (the row can move
--           it with MoveDies).
-- A side another AddOn already uses is skipped, for the other side, then
-- inside the bar's right end (John's DIES screenshot, 2026-10-30: "DIESJuk'taz
-- ]" was Threat Plates' target-of-target text "[ name ]", 30 px right of the
-- bar; his Era profile has it on). A side is taken when:
--   - the adapter says so (`busy`, read in each AddOn's Era source below), or
--   - a shown text of the bar, or of its parent, is anchored just outside
--     that edge of the bar (GetPoint only: no layout reads, see Widgets.lua;
--     a secret anchor is never compared).
-- A caller may also pass a side ("left", "right", "inside") from its own
-- setting. The side is chosen again at each draw that shows DIES, so a text
-- that comes and goes (a target-of-target, a group's threat text) moves the
-- badge then.

local STRIPES = "Interface\\AddOns\\DyresToolkit\\Textures\\Stripes"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local OUTLINE = 1
-- A bar whose own fill is within this much of the block's color (red + green
-- + blue apart; a tracker row in a purple panel) gets a lighter block.
local SAME_COLOR = 0.15
local LIGHTEN = 0.5
local OUTLINE_LIGHTEN = 0.4
local OUTLINE_ALPHA = 0.3
local DIES_TEXT = "DIES"
local DIES_COLOR = {1, 0.1, 0.1}
local DIES_FONT = "Fonts\\FRIZQT__.TTF"
local DIES_SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local DIES_SIZE = {target = 14, plate = 11, row = 10}
local DIES_GAP = 2
local SIDES = {
    left = {"RIGHT", "LEFT", -3, 0},
    right = {"LEFT", "RIGHT", 3, 0},
    inside = {"RIGHT", "RIGHT", -2, 0},
}
local DEFAULT_SIDE = {target = "left", plate = "right", row = "inside"}
-- Above the bar's own texts: a tracker row's layer (+1) and slots (+2, their
-- buttons +10), and the target frame's text frame.
local DIES_LEVEL = 12
-- Frame levels above the bar: a tracker row's name and texts are on a layer
-- one above its health bar, so the block stays at the bar's own level there.
local OVERLAY_LEVEL = {target = 1, plate = 1, row = 0}
local IsSecret = DyresToolkit.IsSecret

local overlays = {}
-- The public API's, at the end of this file.
local Call, ResolveOutside, Suppressed

-- Frame adapters -----------------------------------------------------------------

-- One entry per frame AddOn: the StatusBar that shows a nameplate's or the
-- target or focus frame's health, else nil. The first match wins; Blizzard's
-- bar is the fallback. Every field is checked, so an AddOn that is not
-- loaded, or that changed its frames, gives nil and no error. Paths are from
-- each AddOn's own source (cited per entry); the toolkit never changes their
-- frames, it only puts its own block on their bars.
local function StatusBar(value)
    if type(value) == "table" and type(value.GetStatusBarTexture) == "function"
            and not (type(value.IsForbidden) == "function" and value:IsForbidden()) then
        return value
    end
end

-- value[key1][key2]..., or nil at the first step that is not a table.
local function Field(value, ...)
    for index = 1, select("#", ...) do
        if type(value) ~= "table" then
            return nil
        end
        value = value[select(index, ...)]
    end
    return value
end

-- Platynator 527 (John, WTF 1.4.0: the first nameplate AddOn of the Forever
-- beta; read in its source on Era). Its manager (Display/Initialize.lua)
-- keeps one display frame per Blizzard plate and style, installs it on the
-- plate in its own NAME_PLATE_UNIT_ADDED handler (SetParent(nameplate), then
-- SetUnit(unit), which sets .unit; Display/Nameplate.lua) and uninstalls it
-- on removal (SetUnit(nil), Hide). The display's .widgets holds the health
-- widget (details.kind "health") with its StatusBar at .statusBar
-- (Display/Widgets.lua). The manager is private, so the display is found
-- among the plate's own children at each draw: a handful of frames, on
-- events only. Room for its target arrows, which sit just outside the bar's
-- ends.
local PLATYNATOR_ARROW_ROOM = 22

local function IsPlatynatorDisplay(frame)
    return type(frame) == "table" and type(Field(frame, "widgets")) == "table"
        and type(Field(frame, "Install")) == "function" and type(Field(frame, "SetUnit")) == "function"
end

local function PlatynatorBar(plate, unit)
    if type(plate.GetChildren) ~= "function" then
        return nil
    end
    for _, display in ipairs({plate:GetChildren()}) do
        if IsPlatynatorDisplay(display) and Field(display, "unit") == unit and display:IsShown() then
            for _, widget in ipairs(display.widgets) do
                if Field(widget, "details", "kind") == "health" then
                    local bar = StatusBar(Field(widget, "statusBar"))
                    if bar then
                        return bar
                    end
                end
            end
        end
    end
end

-- Whether a frame or region is there and shown.
local function Shown(value)
    return type(value) == "table" and type(value.IsShown) == "function" and value:IsShown() == true
end

-- Plater's anchor sides (Plater.lua anchor_functions): 1-3 are outside the
-- left edge (topleft, left, bottomleft), 5-7 outside the right edge
-- (bottomright, right, topright).
local function PlaterOutside(anchor)
    local side = type(anchor) == "table" and anchor.side
    if side == 1 or side == 2 or side == 3 then
        return "left"
    elseif side == 5 or side == 6 or side == 7 then
        return "right"
    end
end

local PLATE_ADAPTERS = {
    -- Threat Plates 13.3.3: its own frame plate.TPFrame (Nameplate.lua
    -- HandlePlateCreated), drawing this unit while .Active is true
    -- (ShowBlizzardNameplate), with the bar at .visual.Healthbar
    -- (Elements/Healthbar.lua; .healthbar is its older name).
    -- Its side texts (13.3.4 on Era; Constants.lua defaults): right of the
    -- bar, the target-of-target text Healthbar.TargetUnit (+30, "[ name ]",
    -- in combat; Elements/Healthbar.lua ShowTargetUnit), the crowd control
    -- icons (widgets.Auras.CrowdControl with ActiveAuras, +10;
    -- Widgets/AurasWidget.lua), and the threat art
    -- (widgets.Threat.RightTexture, +4); left of it, the threat percentage
    -- and art (widgets.Threat, -6; Widgets/ThreatWidget.lua), in groups.
    {name = "Threat Plates", bar = function(plate)
        local frame = Field(plate, "TPFrame")
        if Field(frame, "Active") == true then
            return StatusBar(Field(frame, "visual", "Healthbar")) or StatusBar(Field(frame, "visual", "healthbar"))
        end
    end, busy = function(plate, bar)
        local widgets = Field(plate, "TPFrame", "widgets")
        local threat = Shown(Field(widgets, "Threat"))
        local crowd = Field(widgets, "Auras", "CrowdControl")
        local active = Field(crowd, "ActiveAuras")
        local controlled = Shown(crowd) and not IsSecret(active) and type(active) == "number" and active > 0
        return {
            right = Shown(Field(bar, "TargetUnit")) or controlled or threat,
            left = threat,
        }
    end},
    -- Plater: plate.unitFrame (lowercase; Blizzard's is .UnitFrame), also
    -- with its "use UIParent" option, whose DetailsFramework health bar is
    -- .healthBar (Plater.lua; libs/DF/unitframe.lua CreateHealthBar).
    -- Its side texts (v662 on Era): the cast's target name
    -- (castBar.FrameOverlay.TargetName; profile castbar_target_show, placed
    -- by castbar_target_anchor; John's Era profile: side 6, right of the cast
    -- bar under the health bar), read from the profile so the badge does not
    -- jump with each cast; and the raid marker (unitFrame.PlaterRaidTargetFrame,
    -- 15 px left of the bar by default, indicator_raidmark_anchor), while its
    -- icon shows.
    {name = "Plater", bar = function(plate)
        if type(rawget(_G, "Plater")) == "table" then
            return StatusBar(Field(plate, "unitFrame", "healthBar"))
        end
    end, busy = function(plate)
        local profile = Field(rawget(_G, "Plater"), "db", "profile")
        local busy = {}
        if Field(profile, "castbar_target_show") == true then
            local side = PlaterOutside(Field(profile, "castbar_target_anchor"))
            if side then
                busy[side] = true
            end
        end
        if Shown(Field(plate, "unitFrame", "PlaterRaidTargetFrame", "RaidTargetIcon")) then
            busy[PlaterOutside(Field(profile, "indicator_raidmark_anchor")) or "left"] = true
        end
        return busy
    end},
    -- EllesmereUI: its pooled plate for the unit, while that is on this
    -- Blizzard plate, with the bar at .health. From Does It Die's adapter
    -- only, not checked against EllesmereUI's source.
    {name = "EllesmereUI", bar = function(plate, unit)
        local own = Field(rawget(_G, "EllesmereNameplates_NS"), "plates", unit)
        if own ~= nil and Field(own, "nameplate") == plate then
            return StatusBar(Field(own, "health"))
        end
    end},
    {name = "Platynator", dies = {"LEFT", "RIGHT", PLATYNATOR_ARROW_ROOM, 0}, diesStrata = "LOW",
        bar = function(plate, unit)
        if type(rawget(_G, "Platynator")) == "table" then
            return PlatynatorBar(plate, unit)
        end
    end},
    -- Blizzard: Era's UnitFrame.HealthBarsContainer.healthBar
    -- (Blizzard_NamePlates.xml), else UnitFrame.healthBar.
    {name = "Blizzard", bar = function(plate)
        return StatusBar(Field(plate, "UnitFrame", "HealthBarsContainer", "healthBar"))
            or StatusBar(Field(plate, "UnitFrame", "healthBar"))
    end},
}

local UNIT_ADAPTERS = {
    -- Shadowed Unit Frames v4.3.9: ShadowUF.Units.unitFrames[unit], set while
    -- its frame for the unit is enabled (modules/units.lua), with the bar at
    -- .healthBar (modules/health.lua).
    {name = "Shadowed Unit Frames", bar = function(unit)
        return StatusBar(Field(rawget(_G, "ShadowUF"), "Units", "unitFrames", unit, "healthBar"))
    end},
    -- BetterBlizzFrames v2.1.8 restyles Blizzard's own frames: it moves,
    -- resizes, and re-textures TargetFrameHealthBar but keeps it (Blizzard's
    -- entry covers that). Its "smooth bars" option (shared/smoothBars.lua)
    -- hides that bar's fill and shows an eased StatusBar child of it,
    -- .bbfSmoothOverlay, which mirrors its values, color, and texture: the
    -- block goes on that one, so it follows the fill you see.
    {name = "BetterBlizzFrames", bar = function(unit)
        local name = unit == "target" and "TargetFrame" or "FocusFrame"
        local stock = StatusBar(Field(rawget(_G, name), "healthbar")) or StatusBar(rawget(_G, name .. "HealthBar"))
        return StatusBar(Field(stock, "bbfSmoothOverlay"))
    end},
    -- EllesmereUI's unit frames: from Does It Die's adapter only, as above.
    {name = "EllesmereUI", bar = function(unit)
        local frame = rawget(_G, unit == "target" and "EllesmereUIUnitFrames_Target" or "EllesmereUIUnitFrames_Focus")
        return StatusBar(Field(frame, "Health"))
    end},
    -- Blizzard: TargetFrame.healthbar on Era (TargetFrame.lua), FocusFrame's
    -- on clients with a focus.
    {name = "Blizzard", bar = function(unit)
        local name = unit == "target" and "TargetFrame" or "FocusFrame"
        local frame = rawget(_G, name)
        return StatusBar(Field(frame, "healthbar")) or StatusBar(Field(frame, "HealthBar"))
            or StatusBar(rawget(_G, name .. "HealthBar"))
    end},
}

local ADAPTERS = {plate = PLATE_ADAPTERS, unit = UNIT_ADAPTERS}

-- adapter = {name, bar = function(plate, unit) or function(unit), optional
-- dies = {point, relativePoint, x, y} and diesStrata}. It goes before
-- Blizzard's fallback, or before the adapter named `before`. One name once.
function DyresToolkit.RegisterBarAdapter(kind, adapter, before)
    local list = ADAPTERS[kind]
    if not list or type(adapter) ~= "table" or type(adapter.name) ~= "string" or type(adapter.bar) ~= "function" then
        return false
    end
    for _, known in ipairs(list) do
        if known.name == adapter.name then
            return false
        end
    end
    local at = #list
    for index, known in ipairs(list) do
        if known.name == (before or "Blizzard") then
            at = index
            break
        end
    end
    table.insert(list, at, adapter)
    return true
end

-- plate nil: a unit frame adapter, called with the unit only. Adapters from
-- HealthBars.RegisterAdapter come first.
local function Resolve(list, plate, unit)
    local own, ownInfo = ResolveOutside(plate, unit)
    if own then
        return own, ownInfo
    end
    for _, adapter in ipairs(list) do
        local bar
        if plate then
            bar = adapter.bar(plate, unit)
        else
            bar = adapter.bar(unit)
        end
        if bar then
            local busy = plate and adapter.busy and adapter.busy(plate, bar, unit)
            return bar, {name = adapter.name, place = adapter.dies, strata = adapter.diesStrata,
                busy = type(busy) == "table" and busy or nil}
        end
    end
end

-- The bar showing this nameplate's health, and {name, place, strata} for
-- DrawPrediction; nil for a forbidden or missing plate.
function DyresToolkit.FindPlateBar(unit)
    local plate = type(C_NamePlate) == "table" and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (type(plate.IsForbidden) == "function" and plate:IsForbidden()) then
        return nil
    end
    return Resolve(PLATE_ADAPTERS, plate, unit)
end

-- The bar of the target or focus frame, and its info.
function DyresToolkit.FindUnitBar(unit)
    return Resolve(UNIT_ADAPTERS, nil, unit)
end

-- Which bar shows each unit, in the caller's own table: a block on a bar the
-- unit left is hidden (Threat Plates letting a plate go, Platynator
-- uninstalling, a recycled plate, SUF's frame turned off). bar nil: the unit
-- has none now (its plate went).
function DyresToolkit.UseBar(shown, unit, bar, info)
    local old = shown[unit]
    if old and old.bar ~= bar then
        DyresToolkit.HidePrediction(old.bar)
    end
    shown[unit] = bar and {bar = bar, name = info and info.name, info = info} or nil
end

-- The badge's side --------------------------------------------------------------

-- Whether a shown text of the bar (or its parent) is anchored just outside
-- this edge of the bar: "right" is a text whose LEFT side is on the bar's
-- RIGHT, "left" the mirror. Read from anchors only.
local function TextOutside(owner, bar, side)
    if type(owner) ~= "table" or type(owner.GetRegions) ~= "function" then
        return false
    end
    local barEdge = side == "right" and "RIGHT$" or "LEFT$"
    local textEdge = side == "right" and "LEFT$" or "RIGHT$"
    for _, region in ipairs({owner:GetRegions()}) do
        if type(region) == "table" and type(region.GetObjectType) == "function"
                and region:GetObjectType() == "FontString" and region:IsShown() then
            local count = region:GetNumPoints()
            for index = 1, (not IsSecret(count) and type(count) == "number") and count or 0 do
                local point, relative, relativePoint = region:GetPoint(index)
                if not IsSecret(point) and not IsSecret(relative) and not IsSecret(relativePoint)
                        and relative == bar and type(point) == "string" and type(relativePoint) == "string"
                        and point:find(textEdge) and relativePoint:find(barEdge) then
                    return true
                end
            end
        end
    end
    return false
end

local function SideTaken(bar, side, info)
    if side == "inside" then
        return false
    end
    if info and info.busy and info.busy[side] then
        return true
    end
    local parent = type(bar.GetParent) == "function" and bar:GetParent() or nil
    return TextOutside(bar, bar, side) or TextOutside(parent, bar, side)
end

-- {point, relativePoint, x, y} and the side name used.
local function DiesPlace(bar, kind, info, side)
    if SIDES[side] then
        return SIDES[side], side
    end
    local first = DEFAULT_SIDE[kind]
    if kind == "row" then
        return SIDES.inside, "inside"
    end
    -- An outside adapter's own place.
    if info and info.exact then
        return info.place, info.side or "anchor"
    elseif info and SIDES[info.side] then
        return SIDES[info.side], info.side
    end
    local other = first == "right" and "left" or "right"
    local adapterPlace = info and info.place
    if not SideTaken(bar, first, info) then
        return adapterPlace or SIDES[first], first
    end
    if not SideTaken(bar, other, info) then
        return SIDES[other], other
    end
    return SIDES.inside, "inside"
end

-- Drawing -------------------------------------------------------------------------

local function Anchor(overlay, bar, kind, info)
    local fill = bar:GetStatusBarTexture()
    local reverse = type(bar.GetReverseFill) == "function" and bar:GetReverseFill() == true
    if overlay.anchoredFill ~= fill or overlay.reverse ~= reverse then
        overlay.anchoredFill, overlay.reverse = fill, reverse
        overlay:ClearAllPoints()
        if reverse then
            overlay:SetPoint("TOPLEFT", fill, "TOPLEFT")
            overlay:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
        else
            overlay:SetPoint("TOPLEFT", bar, "TOPLEFT")
            overlay:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
        end
        overlay:SetReverseFill(not reverse)
    end
    overlay:SetFrameLevel(bar:GetFrameLevel() + OVERLAY_LEVEL[kind])
    overlay.dies:SetFrameLevel(bar:GetFrameLevel() + (info and info.level or DIES_LEVEL))
    -- The badge's size in UI units, whatever the bar's own scale.
    local own, ui = overlay:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if type(own) == "number" and type(ui) == "number" and own > 0 and ui > 0 then
        overlay.dies:SetScale(ui / own)
    end
end

local function Vertical(bar)
    return type(bar.GetOrientation) == "function" and bar:GetOrientation() == "VERTICAL"
end

local function Lighter(r, g, b, share)
    return r + (1 - r) * share, g + (1 - g) * share, b + (1 - b) * share
end

-- The block's color, lighter on a bar whose own fill has the same color.
local function BlockColor(bar, color)
    local r, g, b = color[1], color[2], color[3]
    local br, bg, bb = bar:GetStatusBarColor()
    if type(br) == "number" and type(bg) == "number" and type(bb) == "number" and not IsSecret(br)
            and not IsSecret(bg) and not IsSecret(bb)
            and math.abs(br - r) + math.abs(bg - g) + math.abs(bb - b) < SAME_COLOR then
        return Lighter(r, g, b, LIGHTEN)
    end
    return r, g, b
end

-- The bar's own fill art: an atlas (Era's nameplates) or a texture file.
local function BarArt(bar)
    local fill = bar:GetStatusBarTexture()
    local atlas = type(fill.GetAtlas) == "function" and fill:GetAtlas() or nil
    if type(atlas) == "string" and atlas ~= "" then
        return "atlas", atlas
    end
    local texture = type(fill.GetTexture) == "function" and fill:GetTexture() or nil
    if texture ~= nil then
        return "file", texture
    end
end

-- The caller's look, repaired: fill "stripes", "solid", or "bar" (the bar's
-- own texture); color {r, g, b}; opacity 0-100; outline "none" or "solid";
-- dies true or false; side nil, "left", "right", or "inside".
local DEFAULT_COLOR = {0.6, 0.2, 0.9}

local function Look(style)
    style = type(style) == "table" and style or {}
    local color = style.color
    if type(color) ~= "table" or type(color[1]) ~= "number" or type(color[2]) ~= "number"
            or type(color[3]) ~= "number" then
        color = DEFAULT_COLOR
    end
    local opacity = tonumber(style.opacity) or 70
    return {
        fill = (style.fill == "solid" or style.fill == "bar") and style.fill or "stripes",
        color = color,
        alpha = math.max(0, math.min(100, opacity)) / 100,
        outline = style.outline == "solid" and "solid" or "none",
        dies = style.dies ~= false,
        side = SIDES[style.side] and style.side or nil,
    }
end

local function Style(overlay, bar, look)
    local r, g, b = BlockColor(bar, look.color)
    local art, source = nil, nil
    if look.fill == "bar" then
        art, source = BarArt(bar)
    end
    local key = table.concat({look.fill, look.outline, look.alpha, r, g, b, tostring(art), tostring(source)}, ":")
    if overlay.style == key then
        return
    end
    overlay.style = key
    local block = overlay.block
    block:SetHorizTile(false)
    block:SetVertTile(false)
    if look.fill == "stripes" then
        block:SetTexture(STRIPES, "REPEAT", "REPEAT")
        block:SetHorizTile(true)
        block:SetVertTile(true)
    elseif art == "atlas" then
        block:SetAtlas(source)
    else
        block:SetTexture(art == "file" and source or WHITE)
    end
    block:SetVertexColor(r, g, b, look.alpha)
    local er, eg, eb = Lighter(r, g, b, OUTLINE_LIGHTEN)
    for _, edge in ipairs(overlay.edges) do
        edge:SetColorTexture(er, eg, eb, math.min(1, look.alpha + OUTLINE_ALPHA))
        edge:SetShown(look.outline == "solid")
    end
end

-- The 1 px outline around the span: top, bottom, left, right.
local function Edges(overlay, span)
    local edges = {}
    for _, side in ipairs({{"TOPLEFT", "TOPRIGHT", true}, {"BOTTOMLEFT", "BOTTOMRIGHT", true},
        {"TOPLEFT", "BOTTOMLEFT", false}, {"TOPRIGHT", "BOTTOMRIGHT", false}}) do
        local edge = overlay:CreateTexture(nil, "OVERLAY")
        edge:SetPoint(side[1], span, side[1])
        edge:SetPoint(side[2], span, side[2])
        if side[3] then
            edge:SetHeight(OUTLINE)
        else
            edge:SetWidth(OUTLINE)
        end
        edges[#edges + 1] = edge
    end
    return edges
end

local function Overlay(bar, kind)
    local overlay = overlays[bar]
    if overlay then
        return overlay
    end
    overlay = CreateFrame("StatusBar", nil, bar)
    overlay:SetStatusBarTexture(WHITE)
    overlay:SetStatusBarColor(0, 0, 0, 0)
    overlay:EnableMouse(false)
    local span = overlay:GetStatusBarTexture()
    local block = overlay:CreateTexture(nil, "ARTWORK")
    block:SetPoint("TOPLEFT", span, "TOPLEFT")
    block:SetPoint("BOTTOMRIGHT", span, "BOTTOMRIGHT")
    overlay.block = block
    overlay.edges = Edges(overlay, span)
    local size = DIES_SIZE[kind]
    local dies = CreateFrame("Frame", nil, overlay)
    dies:EnableMouse(false)
    local skull = dies:CreateTexture(nil, "OVERLAY")
    skull:SetTexture(DIES_SKULL)
    skull:SetVertexColor(DIES_COLOR[1], DIES_COLOR[2], DIES_COLOR[3])
    skull:SetSize(size, size)
    skull:SetPoint("LEFT", dies, "LEFT")
    local label = dies:CreateFontString(nil, "OVERLAY")
    label:SetFont(DIES_FONT, size, "THICKOUTLINE")
    label:SetTextColor(DIES_COLOR[1], DIES_COLOR[2], DIES_COLOR[3])
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    label:SetPoint("LEFT", skull, "RIGHT", DIES_GAP, 0)
    label:SetText(DIES_TEXT)
    dies:SetSize(size + DIES_GAP + label:GetStringWidth(), size)
    dies.skull, dies.label = skull, label
    overlay.dies = dies
    overlay:Hide()
    overlays[bar] = overlay
    return overlay
end

-- Puts the badge at {point, relativePoint, x, y} from the bar, once per change.
local function PlaceDies(overlay, bar, place, strata)
    local key = table.concat({place[1], place[2], place[3], place[4], tostring(strata)}, ":")
    if overlay.diesKey == key then
        return
    end
    overlay.diesKey = key
    overlay.dies:ClearAllPoints()
    overlay.dies:SetPoint(place[1], bar, place[2], place[3], place[4])
    if strata then
        overlay.dies:SetFrameStrata(strata)
    end
end

-- Makes the block for a bar now, out of combat (WTF makes the target
-- frame's at login: that bar is a child of a secure unit button).
function DyresToolkit.PrepareBar(bar, kind)
    if not bar or not DIES_SIZE[kind] then
        return false
    end
    Overlay(bar, kind)
    return true
end

-- The caller redraws on its own events. After NAME_PLATE_UNIT_ADDED it draws
-- again on the next frame (C_Timer.After(0)): Threat Plates and Platynator
-- take the plate over in their own handlers for that event.

function DyresToolkit.HidePrediction(bar)
    local overlay = bar and overlays[bar]
    if overlay then
        overlay:Hide()
    end
end

-- Draws the block for `damage` still to come on a bar showing `health`:
-- kind "target", "plate", or "row"; style as Look above; info from
-- FindPlateBar or FindUnitBar (its place and strata), or nil. Hides it for
-- no damage, a secret or no health, or a vertical bar. Returns whether DIES
-- shows, and the side it went on.
function DyresToolkit.DrawPrediction(bar, kind, damage, health, style, info)
    if not bar or not DIES_SIZE[kind] then
        return false
    end
    if IsSecret(damage) or type(damage) ~= "number" or damage <= 0 or IsSecret(health)
            or type(health) ~= "number" or health <= 0 or Vertical(bar) or Suppressed(bar, info) then
        DyresToolkit.HidePrediction(bar)
        return false
    end
    local look = Look(style)
    local overlay = Overlay(bar, kind)
    Anchor(overlay, bar, kind, info)
    Style(overlay, bar, look)
    overlay:SetMinMaxValues(0, health)
    overlay:SetValue(math.min(damage, health))
    local dies = look.dies and damage >= health
    local side
    if dies and not overlay.moved then
        local place
        place, side = DiesPlace(bar, kind, info, look.side)
        PlaceDies(overlay, bar, place, info and info.strata)
    end
    overlay.dies:SetShown(dies)
    overlay:Show()
    return dies, side
end

-- A tracker row puts DIES where it wants it: place = {point, region,
-- relativePoint, x} (as WTF's rows), or nil for the bar's right end.
function DyresToolkit.MoveDies(bar, place)
    local overlay = bar and overlays[bar]
    if not overlay then
        return false
    end
    overlay.diesKey = nil
    overlay.dies:ClearAllPoints()
    if place then
        overlay.moved = true
        overlay.dies:SetPoint(place[1], place[2], place[3], place[4], 0)
    else
        overlay.moved = nil
        overlay.dies:SetPoint(SIDES.inside[1], bar, SIDES.inside[2], SIDES.inside[3], SIDES.inside[4])
    end
    return true
end

-- The public API (Toolkit 2.4.0; John, 2026-10-31) ---------------------------------

-- For other nameplate and unit frame AddOns: DyresToolkit.HealthBars, with
-- no new global. API_VERSION goes up only for a change a caller must know
-- about; additions keep it. Every function an outside AddOn gives runs in
-- pcall: one that fails is turned off until reload, and says so only in
-- debug mode (/dyre debug; John: players cannot fix it, and a line at every
-- login would look like our bug). The bar then falls through to the next
-- adapter, Blizzard's last.
local HealthBars = {API_VERSION = 1}
DyresToolkit.HealthBars = HealthBars

local problems = {}

-- Lines for /dyre debug: said at once in debug mode, and kept for when it
-- is turned on.
function ns.ReportProblems()
    if #problems == 0 then
        ns.Report("No health bar hooks have failed.")
    end
    for _, line in ipairs(problems) do
        ns.Report(line)
    end
end

-- owner[key](...), for one value; a hook that fails is turned off.
function Call(owner, key, ...)
    local hook = owner and owner[key]
    if not owner or owner.broken or type(hook) ~= "function" then
        return nil
    end
    local ok, value = pcall(hook, ...)
    if not ok then
        owner.broken = true
        local line = owner.label .. " failed and is off until you reload: " .. tostring(value)
        problems[#problems + 1] = line
        if ns.debug then
            ns.Report(line)
        end
        return nil
    end
    return value
end

-- RegisterAdapter(spec): spec.name (required; a second call with the same
-- name replaces the first), and at least one of spec.plate(plate, unit) and
-- spec.unit(unit), each returning the StatusBar that shows the unit's
-- health, or nil to let the next adapter look. Optional:
--   side      "left", "right", or "inside": where DIES goes (a player's own
--             side setting in a Dyre's AddOn still wins)
--   anchor    {point, relativePoint, x, y} from the bar: DIES goes exactly there
--   strata    DIES's frame strata
--   level     DIES's frame level above the bar (default 12)
--   avoid     function(plate or nil, bar, unit) -> {left = true, right =
--             true}: the sides your frame writes on, for DIES to skip
--   suppress  true, or function(bar, unit) -> true: draw nothing there
-- Registered adapters come before the built-in ones, in the order they
-- came. Returns true, or false and why.
local outside = {}

local function Invalid(spec)
    if type(spec) ~= "table" or type(spec.name) ~= "string" or not spec.name:find("%S") then
        return "spec.name must be a name"
    elseif type(spec.plate) ~= "function" and type(spec.unit) ~= "function" then
        return "spec.plate or spec.unit must be a function"
    elseif spec.side ~= nil and not SIDES[spec.side] then
        return "spec.side must be left, right, or inside"
    elseif spec.anchor ~= nil and (type(spec.anchor) ~= "table" or type(spec.anchor[1]) ~= "string"
            or type(spec.anchor[2]) ~= "string") then
        return "spec.anchor must be {point, relativePoint, x, y}"
    elseif spec.strata ~= nil and type(spec.strata) ~= "string" then
        return "spec.strata must be a strata name"
    elseif spec.level ~= nil and type(spec.level) ~= "number" then
        return "spec.level must be a number"
    elseif spec.avoid ~= nil and type(spec.avoid) ~= "function" then
        return "spec.avoid must be a function"
    elseif spec.suppress ~= nil and spec.suppress ~= true and type(spec.suppress) ~= "function" then
        return "spec.suppress must be true or a function"
    end
end

function HealthBars.RegisterAdapter(spec)
    local problem = Invalid(spec)
    if problem then
        return false, problem
    end
    local own = {name = spec.name, label = "The health bar adapter \"" .. spec.name .. "\"",
        plate = spec.plate, unit = spec.unit, side = spec.side, strata = spec.strata, level = spec.level,
        avoid = spec.avoid, suppress = spec.suppress}
    if spec.anchor then
        own.anchor = {spec.anchor[1], spec.anchor[2], tonumber(spec.anchor[3]) or 0, tonumber(spec.anchor[4]) or 0}
    end
    for index, known in ipairs(outside) do
        if known.name == own.name then
            outside[index] = own
            return true
        end
    end
    outside[#outside + 1] = own
    return true
end

function HealthBars.UnregisterAdapter(name)
    for index, known in ipairs(outside) do
        if known.name == name then
            table.remove(outside, index)
            return true
        end
    end
    return false
end

-- The first registered adapter with a bar for this plate (plate nil: a unit
-- frame), and its info.
function ResolveOutside(plate, unit)
    for _, spec in ipairs(outside) do
        local bar
        if plate then
            bar = StatusBar(Call(spec, "plate", plate, unit))
        else
            bar = StatusBar(Call(spec, "unit", unit))
        end
        if bar then
            local busy = spec.avoid and Call(spec, "avoid", plate, bar, unit)
            return bar, {name = spec.name, place = spec.anchor, exact = spec.anchor ~= nil, side = spec.side,
                strata = spec.strata, level = spec.level, busy = type(busy) == "table" and busy or nil,
                suppress = spec.suppress, spec = spec, unit = unit}
        end
    end
end

-- SetSuppressed(bar, on): nothing is drawn on this bar while on (a bar of
-- yours showing something else for now). Weak keys: a bar you drop goes.
local suppressed = setmetatable({}, {__mode = "k"})

function HealthBars.SetSuppressed(bar, on)
    if type(bar) ~= "table" then
        return false
    end
    suppressed[bar] = on and true or nil
    if on then
        DyresToolkit.HidePrediction(bar)
    end
    return true
end

function Suppressed(bar, info)
    if suppressed[bar] then
        return true
    end
    local rule = info and info.suppress
    if rule == true then
        return true
    end
    return type(rule) == "function" and Call(info.spec, "suppress", bar, info.unit) == true
end

-- Damage sources: Dyre's AddOns only (a TOC with `## Group: DyresToolkit`).
-- The highest priority wins, so a mob's damage to come is drawn and reported
-- once: a class Tools AddOn (Warlock Tools Forever, 10) wins over Dyre's
-- Debuff Tracker (5) for its own class (lead decision 7a, 2026-11-01).
-- source = {addon, priority, damage = function(unitOrGUID) -> number or
-- nil; optional willDie = function(unitOrGUID) -> true, false, or nil, and
-- refresh = function(unit or nil): draw again}.
local sources = {}

-- Whether an AddOn is a Dyre's AddOn: its TOC has `## Group: DyresToolkit`.
-- Shared with Owners.lua.
local function InFamily(addon)
    if type(addon) ~= "string" then
        return false
    end
    local read = type(C_AddOns) == "table" and C_AddOns.GetAddOnMetadata or rawget(_G, "GetAddOnMetadata")
    if type(read) ~= "function" then
        return false
    end
    local ok, group = pcall(read, addon, "Group")
    return ok and group == "DyresToolkit"
end

ns.InFamily = InFamily

function HealthBars.RegisterSource(source)
    if type(source) ~= "table" or type(source.addon) ~= "string" or type(source.priority) ~= "number"
            or type(source.damage) ~= "function" then
        return false, "a source needs addon, priority, and damage"
    end
    if not InFamily(source.addon) then
        return false, "damage sources are for Dyre's AddOns"
    end
    sources[source.addon] = {addon = source.addon, priority = source.priority, damage = source.damage,
        willDie = source.willDie, refresh = source.refresh, label = "The damage source " .. source.addon,
        enabled = true}
    return true
end

-- A source steps aside while its prediction is off, so the next one draws.
function HealthBars.SetSourceEnabled(addon, on)
    local source = sources[addon]
    if not source then
        return false
    end
    source.enabled = on and true or false
    return true
end

local function Active()
    local best
    for _, source in pairs(sources) do
        if source.enabled and not source.broken and (not best or source.priority > best.priority
                or (source.priority == best.priority and source.addon < best.addon)) then
            best = source
        end
    end
    return best
end

-- Whether this AddOn's prediction is the one to draw.
function HealthBars.IsActiveSource(addon)
    local source = Active()
    return source ~= nil and source.addon == addon
end

-- The damage still to come on a unit token or GUID, or nil when no Dyre's
-- AddOn knows.
function HealthBars.GetPredictedDamage(unitOrGUID)
    local source = Active()
    local damage = source and Call(source, "damage", unitOrGUID)
    if not IsSecret(damage) and type(damage) == "number" and damage >= 0 then
        return damage
    end
    return nil
end

-- Whether that damage kills: true or false; nil when the health is secret
-- (WoW: Forever) or the unit is not found.
function HealthBars.WillDie(unitOrGUID)
    local source = Active()
    if source and source.willDie then
        local verdict = Call(source, "willDie", unitOrGUID)
        if verdict == true or verdict == false then
            return verdict
        end
    end
    local damage = HealthBars.GetPredictedDamage(unitOrGUID)
    if not damage or damage == 0 then
        return false
    end
    local unit = unitOrGUID
    if type(unit) == "string" and unit:find("-", 1, true) then
        unit = DyresToolkit.FindUnit(unitOrGUID)
    end
    if type(unit) ~= "string" or type(UnitHealth) ~= "function" then
        return nil
    end
    local health = UnitHealth(unit)
    if IsSecret(health) or type(health) ~= "number" or health <= 0 then
        return nil
    end
    return damage >= health
end

-- RegisterCallback("PREDICTION_CHANGED", callback(event, unit, guid)): a
-- mob's damage to come changed (unit or guid may be nil). It comes on the
-- source's own events, also in combat.
local callbacks = {PREDICTION_CHANGED = {}}

function HealthBars.RegisterCallback(event, callback)
    local list = callbacks[event]
    if not list or type(callback) ~= "function" then
        return false
    end
    for _, known in ipairs(list) do
        if known.callback == callback then
            return true
        end
    end
    list[#list + 1] = {callback = callback, label = "A " .. event .. " callback"}
    return true
end

function HealthBars.UnregisterCallback(event, callback)
    for index, known in ipairs(callbacks[event] or {}) do
        if known.callback == callback then
            table.remove(callbacks[event], index)
            return true
        end
    end
    return false
end

-- For the active source only, so a change is told once.
function HealthBars.NotifyChanged(addon, unit, guid)
    if not HealthBars.IsActiveSource(addon) then
        return false
    end
    for _, known in ipairs(callbacks.PREDICTION_CHANGED) do
        Call(known, "callback", "PREDICTION_CHANGED", unit, guid)
    end
    return true
end

-- Refresh(unit): your frame changed (a new bar, a new layout): the active
-- source draws again on the next frame, once however often you ask. unit
-- nil: every unit.
local pending, everything, queued = {}, false, false

local function Flush()
    queued = false
    local units, all = pending, everything
    pending, everything = {}, false
    local source = Active()
    if not source or not source.refresh then
        return
    end
    if all then
        Call(source, "refresh", nil)
    else
        for unit in pairs(units) do
            Call(source, "refresh", unit)
        end
    end
end

function HealthBars.Refresh(unit)
    if unit == nil then
        everything = true
    elseif type(unit) == "string" then
        pending[unit] = true
    else
        return false
    end
    if not queued then
        queued = true
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(0, Flush)
        else
            Flush()
        end
    end
    return true
end
