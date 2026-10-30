local _, WTF = ...

-- DoT damage prediction (John, 1.4.0: phase 1, Classic Era only): a purple
-- block on the health bar of your target (Blizzard's target frame), of each
-- hostile Blizzard nameplate, and of each DoT tracker row with mob health on,
-- the size of the damage your Corruption,
-- Curse of Agony, Immolate (its over-time part), and Siphon Life still have
-- to deal, ending at the health bar's fill; and "DIES" when that damage is at
-- least the mob's health.
--
-- It needs the combat log: COMBAT_LOG_EVENT_UNFILTERED by mob GUID, also for
-- mobs no unit shows. Each DoT's tick is learned from its ticks (exact:
-- talents, spell power, and resists included) and saved account-wide per rank
-- with the spell power it was learned at; the next cast of that rank starts
-- from it, rescaled to your spell power then. With nothing saved, the rank's
-- base damage plus spell power. On Forever the combat log is restricted (found in
-- client), so this file registers nothing there (phase 2, an estimate, comes
-- later). Health is readable on Era (found in client: 328, 328); a secret
-- health draws nothing.

-- Classic ranks (Era tooltips; base damage without spell power): the family,
-- the over-time damage, its duration, and the level the rank is learned at.
local RANKS = {
    [172] = {"corruption", 40, 12, 4}, [6222] = {"corruption", 90, 15, 14}, [6223] = {"corruption", 222, 18, 24},
    [7648] = {"corruption", 324, 18, 34}, [11671] = {"corruption", 486, 18, 44},
    [11672] = {"corruption", 666, 18, 54}, [25311] = {"corruption", 822, 18, 60},
    [980] = {"agony", 84, 24, 8}, [1014] = {"agony", 180, 24, 18}, [6217] = {"agony", 324, 24, 28},
    [11711] = {"agony", 504, 24, 38}, [11712] = {"agony", 780, 24, 48}, [11713] = {"agony", 1044, 24, 58},
    [348] = {"immolate", 20, 15, 1}, [707] = {"immolate", 40, 15, 10}, [1094] = {"immolate", 90, 15, 20},
    [2941] = {"immolate", 165, 15, 30}, [11665] = {"immolate", 255, 15, 40}, [11667] = {"immolate", 365, 15, 50},
    [11668] = {"immolate", 485, 15, 60}, [25309] = {"immolate", 510, 15, 60},
    [18265] = {"siphon", 150, 30, 30}, [18879] = {"siphon", 220, 30, 38}, [18880] = {"siphon", 330, 30, 48},
    [18881] = {"siphon", 450, 30, 58},
}
-- Seconds between ticks, the spell school for GetSpellBonusDamage (3 fire,
-- 6 shadow), and the share of spell power over the whole DoT: Classic's
-- duration / 15, at most 1; Immolate's over-time part 0.65 (it also hits),
-- Siphon Life half (it heals). Only the first guess uses these.
local FAMILIES = {
    corruption = {interval = 3, school = 6},
    agony = {interval = 2, school = 6, ramp = true},
    immolate = {interval = 3, school = 3, coefficient = 0.65},
    siphon = {interval = 3, school = 6, coefficient = 0.5},
}
local FAMILY_ORDER = {"corruption", "agony", "immolate", "siphon"}
-- Spells learned below level 20 get less spell power: 3.75% per level below.
local LOW_LEVEL = 20
local LOW_LEVEL_PENALTY = 0.0375
local MAX_NAMEPLATE_UNITS = 40
-- The tick events (Siphon Life's is a leech) and the end events.
local TICKS = {SPELL_PERIODIC_DAMAGE = true, SPELL_PERIODIC_LEECH = true}
-- A resisted, absorbed, or immune tick: it happened, with no amount to learn.
local MISSED = "SPELL_PERIODIC_MISSED"
local DEBUFF = "DEBUFF"
local APPLIED = {SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true}
local DEATHS = {UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true}
-- A timer per DoT drops it just after its last tick, should the end event
-- be out of combat log range.
local EXPIRY_GRACE = 0.5
-- The block's look (Core's PREDICT_FILLS, PREDICT_COLORS, and so on): WTF's
-- own stripes (Textures\\Stripes.tga, white, tinted by the color), a plain
-- fill, or the bar's own texture. The overlay's own fill only measures the
-- span; a texture over that span is the block, with a 1 px outline.
local STRIPES = "Interface\\AddOns\\WarlockToolsForever\\Textures\\Stripes"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local OUTLINE = 1
-- A bar whose own fill is within this much of the block's color (red + green
-- + blue apart; a DoT tracker row in the panel's purple) gets a lighter block.
local SAME_COLOR = 0.15
local LIGHTEN = 0.5
local OUTLINE_LIGHTEN = 0.4
local OUTLINE_ALPHA = 0.3
-- DIES (John, 1.4.0, after his Era test: hard to read under a row's texts,
-- over a nameplate's name, and small on the target frame): a badge with a
-- red skull and "DIES" in red with a thick black outline, above every text of
-- the bar's frame. The skull is the game's level skull
-- (UI-TargetingFrame-Skull) tinted red, not the raid marker's: a mob marked
-- with the skull by /tm shows that marker on the same frames (WTF never calls
-- SetRaidTarget), and the two must not look alike. The badge is the same size
-- on every frame: its scale undoes the bar's own (found in client: Platynator
-- scales its display down, and the badge was a few pixels tall). Its place per kind of bar, for every frame AddOn's bar of
-- that kind, unless the adapter gives its own:
--   target  unit frames: just left of the bar, vertically centered. Found in
--           client: centered, it ran into SUF's name ("Great Gore[skull]DIES").
--           SUF puts the name on the bar's left and the health on its right;
--           Blizzard's frame (and BetterBlizzFrames, which restyles it) puts
--           the name above the bar and the health text in its middle; the
--           mana bar is below. Left of the bar is the one side none of them
--           writes on (Blizzard's frame has only border art there; SUF's a
--           left portrait, if set, which the badge then covers);
--   plate   nameplates: just right of the bar, clear of the name above it and
--           of Plater's raid marker on the left. Platynator: further right,
--           past its target arrows beside the bar (found in client: above
--           the bar, it ran under its centered name), in a strata above its
--           display's, which is BACKGROUND;
--   row     DoT tracker rows: in place of the health number (Tracker.lua's
--           RowDiesPlace; found in client: at the bar's right end it covered
--           "| 137" and left a stray digit), else at the bar's right end.
local DIES_TEXT = "DIES"
local DIES_COLOR = {1, 0.1, 0.1}
local DIES_FONT = "Fonts\\FRIZQT__.TTF"
local DIES_SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local DIES_SIZE = {target = 14, plate = 11, row = 10}
local DIES_GAP = 2
local DIES_PLACE = {
    target = {"RIGHT", "LEFT", -3, 0},
    plate = {"LEFT", "RIGHT", 3, 0},
    row = {"RIGHT", "RIGHT", -2, 0},
}
-- Above the bar's own texts: a tracker row's layer (+1) and slots (+2, their
-- buttons +10), and the target frame's text frame.
local DIES_LEVEL = 12
-- Frame levels above the bar: a tracker row's name and texts are on a layer
-- one above its health bar, so the block stays at the bar's own level there.
local OVERLAY_LEVEL = {target = 1, plate = 1, row = 0}

local predict = {available = false, mobs = {}, byName = {}, lastCast = {}, overlays = {}, plates = {}, units = {}}

-- The combat log's reader, else nil (CombatLogGetCurrentEventInfo is only a
-- deprecation fallback on Era); the same gate as Dyre's Crit Mayhem.
local function EventInfoReader()
    if type(C_CombatLog) == "table" and type(C_CombatLog.GetCurrentEventInfo) == "function" then
        return C_CombatLog.GetCurrentEventInfo
    end
    if type(CombatLogGetCurrentEventInfo) == "function" then
        return CombatLogGetCurrentEventInfo
    end
end

local function CombatLogUsable()
    if type(C_CombatLog) == "table" and type(C_CombatLog.IsCombatLogRestricted) == "function" then
        local restricted = C_CombatLog.IsCombatLogRestricted()
        if WTF.IsSecret(restricted) or restricted then
            return false
        end
    end
    return EventInfoReader() ~= nil
end

function WTF.PredictAvailable()
    return predict.available
end

local function Weight(family, tick)
    if not FAMILIES[family].ramp then
        return 1
    end
    -- Curse of Agony: the first four ticks half the average, the last four
    -- one and a half times it.
    if tick <= 4 then
        return 0.5
    elseif tick <= 8 then
        return 1
    end
    return 1.5
end

-- Your spell power for the family's school, else 0.
local function SpellPower(family)
    local power = type(GetSpellBonusDamage) == "function" and GetSpellBonusDamage(FAMILIES[family].school) or 0
    if WTF.IsSecret(power) or type(power) ~= "number" or power < 0 then
        return 0
    end
    return power
end

-- The first guess for the whole DoT: base damage plus spell power.
local function GuessTotal(rankID, power)
    local rank = RANKS[rankID]
    local share = FAMILIES[rank[1]].coefficient or math.min(1, rank[3] / 15)
    if rank[4] < LOW_LEVEL then
        share = share * (1 - (LOW_LEVEL - rank[4]) * LOW_LEVEL_PENALTY)
    end
    return rank[2] + power * share
end

-- A tick is the average tick, except Curse of Agony's: its ramp applies to
-- the rank's base damage only, and the rest (spell power) is spread evenly
-- over the ticks (Does It Die's TBC port, seen in game; to check on Era).
local function TickAmount(dot, tick)
    local weight = Weight(dot.family, tick)
    if weight == 1 then
        return dot.average
    end
    return math.max(0, dot.base * weight + dot.average - dot.base)
end

-- The average tick a tick of this amount stands for.
local function AverageFrom(dot, tick, amount)
    return amount - dot.base * Weight(dot.family, tick) + dot.base
end

-- A saved tick rescaled to your spell power now: only the part above the
-- rank's base grows with spell power.
local function Rescale(saved, base, power)
    local bonus = saved.tick - base
    if saved.power > 0 and bonus > 0 then
        return base + bonus * power / saved.power
    end
    return saved.tick
end

local function Now()
    return GetTime()
end

-- Ticks done: those seen, or those due by now when some were missed.
local function TicksDone(dot, now)
    local due = math.floor((now - dot.applied) / dot.interval)
    return math.min(dot.ticks, math.max(dot.seen, due))
end

-- One DoT's damage still to come.
local function DotRemaining(dot, now)
    local remaining = 0
    for tick = TicksDone(dot, now) + 1, dot.ticks do
        remaining = remaining + TickAmount(dot, tick)
    end
    return remaining
end

function WTF.PredictedDamage(guid)
    local mob = predict.mobs[guid]
    if not mob then
        return 0
    end
    local now, total = Now(), 0
    for _, dot in pairs(mob.dots) do
        total = total + DotRemaining(dot, now)
    end
    return math.floor(total + 0.5)
end

-- Frame adapters -----------------------------------------------------------------

-- One entry per frame AddOn (John, 1.4.0: ThreatPlates, Plater, then
-- EllesmereUI; Shadowed Unit Frames next; then Platynator): the StatusBar that shows a
-- nameplate's or the target or focus frame's health, else nil. The first
-- match wins; Blizzard's bar is the fallback. Every field is checked, so an
-- AddOn that is not loaded, or that changed its frames, gives nil and no
-- error. Paths are from each AddOn's own source (cited per entry); WTF never
-- changes their frames, it only puts its own block on their bars.
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

-- Platynator 527 (John, 1.4.0: the first nameplate AddOn of the Forever
-- beta; read in its source on Era). Its manager (Display/Initialize.lua)
-- keeps one display frame per Blizzard plate and style, installs it on the
-- plate in its own NAME_PLATE_UNIT_ADDED handler (SetParent(nameplate), then
-- SetUnit(unit), which sets .unit; Display/Nameplate.lua) and uninstalls it
-- on removal (SetUnit(nil), Hide). The display's .widgets holds the health
-- widget (details.kind "health") with its StatusBar at .statusBar
-- (Display/Widgets.lua). The manager and its callbacks are private (no
-- global or event to hook), so the display is found among the plate's own
-- children at each draw: a handful of frames, on events only.
-- Room for its target arrows ("wide/arrows" and others, Design.lua), which
-- sit just outside the bar's ends; its crowd-control icons start further out.
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

local PLATE_ADAPTERS = {
    -- Threat Plates 13.3.3: its own frame plate.TPFrame (Nameplate.lua
    -- HandlePlateCreated), drawing this unit while .Active is true
    -- (ShowBlizzardNameplate), with the bar at .visual.Healthbar
    -- (Elements/Healthbar.lua; .healthbar is its older name).
    {name = "Threat Plates", bar = function(plate)
        local frame = Field(plate, "TPFrame")
        if Field(frame, "Active") == true then
            return StatusBar(Field(frame, "visual", "Healthbar")) or StatusBar(Field(frame, "visual", "healthbar"))
        end
    end},
    -- Plater: plate.unitFrame (lowercase; Blizzard's is .UnitFrame), also
    -- with its "use UIParent" option, whose DetailsFramework health bar is
    -- .healthBar (Plater.lua; libs/DF/unitframe.lua CreateHealthBar).
    {name = "Plater", bar = function(plate)
        if type(rawget(_G, "Plater")) == "table" then
            return StatusBar(Field(plate, "unitFrame", "healthBar"))
        end
    end},
    -- EllesmereUI: its pooled plate for the unit, while that is on this
    -- Blizzard plate, with the bar at .health. Not installed here: from Does
    -- It Die's adapter only, not checked against EllesmereUI's source.
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

local function Resolve(adapters, ...)
    for _, adapter in ipairs(adapters) do
        local bar = adapter.bar(...)
        if bar then
            return bar, adapter.name, adapter.dies, adapter.diesStrata
        end
    end
end

-- The health bars --------------------------------------------------------------

-- A block from the bar's left edge to its fill's right edge, filled from the
-- right with the damage to come out of the health left: it ends where the
-- health ends and grows left, and the bar's own size and fill place it. A
-- reverse-filled bar (Shadowed Unit Frames can) gets the mirror image. Each
-- draw checks the fill texture and frame level, as frame AddOns change both.
local function Anchor(overlay, bar, kind)
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
    overlay.dies:SetFrameLevel(bar:GetFrameLevel() + DIES_LEVEL)
    -- The badge's size in UI units, whatever the bar's own scale.
    local own, ui = overlay:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if type(own) == "number" and type(ui) == "number" and own > 0 and ui > 0 then
        overlay.dies:SetScale(ui / own)
    end
end

-- A vertical bar (an option in some unit frame AddOns) gets no block.
local function Vertical(bar)
    return type(bar.GetOrientation) == "function" and bar:GetOrientation() == "VERTICAL"
end

local function Lighter(r, g, b, share)
    return r + (1 - r) * share, g + (1 - g) * share, b + (1 - b) * share
end

local function PresetColor(key)
    for _, preset in ipairs(WTF.PREDICT_COLORS) do
        if preset.key == key then
            return preset.color[1], preset.color[2], preset.color[3]
        end
    end
end

-- The block's color, lighter on a bar whose own fill has the same color.
local function BlockColor(bar)
    local r, g, b = PresetColor(WTF.db.predict.color)
    local br, bg, bb = bar:GetStatusBarColor()
    if type(br) == "number" and type(bg) == "number" and type(bb) == "number" and not WTF.IsSecret(br)
            and not WTF.IsSecret(bg) and not WTF.IsSecret(bb)
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

-- One look for every block, on every frame AddOn's bar and the tracker rows;
-- set again only when a setting or the bar's own color or art changed.
local function Style(overlay, bar)
    local settings = WTF.db.predict
    local r, g, b = BlockColor(bar)
    local alpha = settings.opacity / 100
    local art, source = nil, nil
    if settings.fill == "bar" then
        art, source = BarArt(bar)
    end
    local key = table.concat({settings.fill, settings.outline, alpha, r, g, b, tostring(art), tostring(source)}, ":")
    if overlay.style == key then
        return
    end
    overlay.style = key
    local block = overlay.block
    block:SetHorizTile(false)
    block:SetVertTile(false)
    if settings.fill == "stripes" then
        block:SetTexture(STRIPES, "REPEAT", "REPEAT")
        block:SetHorizTile(true)
        block:SetVertTile(true)
    elseif art == "atlas" then
        block:SetAtlas(source)
    else
        block:SetTexture(art == "file" and source or WHITE)
    end
    block:SetVertexColor(r, g, b, alpha)
    local er, eg, eb = Lighter(r, g, b, OUTLINE_LIGHTEN)
    for _, edge in ipairs(overlay.edges) do
        edge:SetColorTexture(er, eg, eb, math.min(1, alpha + OUTLINE_ALPHA))
        edge:SetShown(settings.outline == "solid")
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

local function Overlay(bar, kind, place, strata)
    local overlay = predict.overlays[bar]
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
    place = place or DIES_PLACE[kind]
    local dies = CreateFrame("Frame", nil, overlay)
    dies:EnableMouse(false)
    dies:SetPoint(place[1], bar, place[2], place[3], place[4])
    if strata then
        dies:SetFrameStrata(strata)
    end
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
    predict.overlays[bar] = overlay
    return overlay
end

local function Readable(value)
    return not WTF.IsSecret(value) and type(value) == "number"
end

local function HideOverlay(bar)
    local overlay = bar and predict.overlays[bar]
    if overlay then
        overlay:Hide()
    end
end

-- Returns whether DIES shows.
local function DrawAmount(bar, kind, damage, health, place, strata)
    if damage <= 0 or not Readable(health) or health <= 0 or Vertical(bar) then
        HideOverlay(bar)
        return false
    end
    local overlay = Overlay(bar, kind, place, strata)
    Anchor(overlay, bar, kind)
    Style(overlay, bar)
    overlay:SetMinMaxValues(0, health)
    overlay:SetValue(math.min(damage, health))
    local dies = WTF.db.predict.dies and damage >= health
    overlay.dies:SetShown(dies)
    overlay:Show()
    return dies
end

local function Draw(unit, bar, kind, place, strata)
    if not bar then
        return
    end
    local settings = WTF.db.predict
    local guid = UnitGUID(unit)
    local canAttack = UnitCanAttack("player", unit)
    if not settings.enabled or WTF.IsSecret(guid) or type(guid) ~= "string"
            or WTF.IsSecret(canAttack) or canAttack ~= true then
        HideOverlay(bar)
        return
    end
    DrawAmount(bar, kind, WTF.PredictedDamage(guid), UnitHealth(unit), place, strata)
end

-- A DoT tracker row's health bar (Tracker.lua's UpdateHealth): the row's mob
-- and the health the bar shows, which a row with no unit keeps from when it
-- had one. Rows have a health bar only with "Show mob health" on, so the
-- block shows there when both it and "Show Predictive DoT Damage" are on
-- (John, 1.4.0: no switch of its own).
-- place: where the row wants DIES, {point, region, relativePoint, x}, else
-- the bar's right end. Returns whether DIES shows, so the row can make room.
function WTF.DrawRowPrediction(bar, guid, health, place)
    if not predict.available or not bar then
        return false
    end
    local settings = WTF.db.predict
    if not settings.enabled or type(guid) ~= "string" then
        HideOverlay(bar)
        return false
    end
    local dies = DrawAmount(bar, "row", WTF.PredictedDamage(guid), health)
    local overlay = predict.overlays[bar]
    if overlay then
        overlay.dies:ClearAllPoints()
        if place then
            overlay.dies:SetPoint(place[1], place[2], place[3], place[4], 0)
        else
            local default = DIES_PLACE.row
            overlay.dies:SetPoint(default[1], bar, default[2], default[3], default[4])
        end
    end
    return dies
end

-- Remembers which bar shows a unit (the frame AddOn can change: Threat Plates
-- turns itself off for some mobs, a plate is recycled), hiding the block on
-- the bar it leaves.
local function UseBar(shown, unit, bar, name)
    local old = shown[unit]
    if old and old.bar ~= bar then
        HideOverlay(old.bar)
    end
    shown[unit] = bar and {bar = bar, name = name} or nil
end

-- The target or focus frame.
local function DrawUnitFrame(unit)
    local bar, name, place = Resolve(UNIT_ADAPTERS, unit)
    UseBar(predict.units, unit, bar, name)
    Draw(unit, bar, "target", place)
end

local function DrawPlate(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local bar, name, place, strata
    if plate and not plate:IsForbidden() then
        bar, name, place, strata = Resolve(PLATE_ADAPTERS, plate, unit)
    end
    UseBar(predict.plates, unit, bar, name)
    if WTF.db.predict.plates then
        Draw(unit, bar, "plate", place, strata)
    else
        HideOverlay(bar)
    end
end

local function IsGUID(unit, guid)
    local shown = UnitGUID(unit)
    return not WTF.IsSecret(shown) and shown == guid
end

local function DrawGUID(guid)
    for _, unit in ipairs({"target", "focus"}) do
        if IsGUID(unit, guid) then
            DrawUnitFrame(unit)
        end
    end
    for unit in pairs(predict.plates) do
        if IsGUID(unit, guid) then
            DrawPlate(unit)
        end
    end
    WTF.RefreshTrackerPrediction(guid)
end

local function DrawAll()
    DrawUnitFrame("target")
    DrawUnitFrame("focus")
    for index = 1, MAX_NAMEPLATE_UNITS do
        local unit = "nameplate" .. index
        if UnitExists(unit) then
            DrawPlate(unit)
        end
    end
    WTF.RefreshTrackerPrediction()
end

-- Settings changed.
function WTF.RefreshPredict()
    if predict.available then
        DrawAll()
    end
end

-- The combat log ---------------------------------------------------------------

local function Family(spellID, spellName)
    local rank = type(spellID) == "number" and RANKS[spellID]
    if rank then
        return rank[1], spellID
    end
    local family = predict.byName[spellName]
    if family then
        return family, predict.lastCast[family]
    end
end

local function Forget(guid, family)
    local mob = predict.mobs[guid]
    if not mob then
        return
    end
    if family then
        mob.dots[family] = nil
        if next(mob.dots) then
            return
        end
    end
    predict.mobs[guid] = nil
end

local function Apply(guid, name, family, rankID)
    local rank = rankID and RANKS[rankID]
    if not rank then
        return
    end
    local mob = predict.mobs[guid] or {dots = {}}
    mob.name = name or mob.name
    predict.mobs[guid] = mob
    local interval = FAMILIES[family].interval
    local ticks = math.floor(rank[3] / interval + 0.5)
    local old = mob.dots[family]
    local power = SpellPower(family)
    local dot = {family = family, rank = rankID, applied = Now(), interval = interval, ticks = ticks,
        seen = 0, duration = rank[3], base = rank[2] / ticks, power = power, sum = 0, count = 0}
    local saved = WTF.accountDB.ticks[rankID]
    -- The same rank on the same mob ticks the same: keep what was learned.
    if old and old.rank == rankID and old.source == "learned" then
        dot.average, dot.source = old.average, "learned"
    elseif saved then
        dot.average, dot.source = Rescale(saved, dot.base, power), "saved"
    else
        dot.average, dot.source = GuessTotal(rankID, power) / ticks, "guessed"
    end
    mob.dots[family] = dot
    C_Timer.After(dot.duration + EXPIRY_GRACE, function()
        local current = predict.mobs[guid]
        if current and current.dots[family] == dot then
            Forget(guid, family)
            DrawGUID(guid)
        end
    end)
end

-- A tick seen, and with an amount, learned: the average of this cast's ticks,
-- saved for the rank with the spell power it was cast at (one decimal).
local function Tick(guid, family, amount)
    local mob = predict.mobs[guid]
    local dot = mob and mob.dots[family]
    if not dot then
        return
    end
    local due = math.floor((Now() - dot.applied) / dot.interval + 0.5)
    local tick = math.min(dot.ticks, math.max(dot.seen + 1, due))
    dot.seen = tick
    if not Readable(amount) then
        return
    end
    dot.sum, dot.count = dot.sum + AverageFrom(dot, tick, amount), dot.count + 1
    dot.average, dot.source = dot.sum / dot.count, "learned"
    WTF.accountDB.ticks[dot.rank] = {tick = math.floor(dot.average * 10 + 0.5) / 10, power = dot.power}
end

local function OnCombatLog()
    -- The 15th field is a tick's amount, or an aura event's type.
    local _, subevent, _, sourceGUID, _, _, _, destGUID, destName, _, _, spellID, spellName, _, amount =
        predict.read()
    if DEATHS[subevent] then
        if predict.mobs[destGUID] then
            Forget(destGUID)
            DrawGUID(destGUID)
        end
        return
    end
    if sourceGUID ~= predict.player then
        return
    end
    local family, rankID = Family(spellID, spellName)
    if not family then
        return
    end
    if APPLIED[subevent] then
        if amount ~= DEBUFF then
            return
        end
        Apply(destGUID, destName, family, rankID)
    elseif TICKS[subevent] then
        Tick(destGUID, family, amount)
    elseif subevent == MISSED then
        Tick(destGUID, family, nil)
    elseif subevent == "SPELL_AURA_REMOVED" then
        if amount ~= DEBUFF then
            return
        end
        Forget(destGUID, family)
    else
        return
    end
    DrawGUID(destGUID)
end

local function IsShownUnit(unit)
    return unit == "target" or unit == "focus" or (type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil)
end

local function OnEvent(_, event, unit, _, spellID)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Which rank you cast, for a combat log that names the spell only.
        local rank = not WTF.IsSecret(spellID) and RANKS[spellID]
        if rank then
            predict.lastCast[rank[1]] = spellID
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        DrawUnitFrame("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        DrawUnitFrame("focus")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if not WTF.IsSecret(unit) then
            DrawPlate(unit)
            -- Again once every AddOn's handler for this event has run: a
            -- nameplate AddOn may only now take the plate over (Threat
            -- Plates sets .Active in its own handler). One timer, no polling.
            C_Timer.After(0, function()
                if UnitExists(unit) then
                    DrawPlate(unit)
                end
            end)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if not WTF.IsSecret(unit) then
            UseBar(predict.plates, unit, nil)
        end
    elseif not WTF.IsSecret(unit) and IsShownUnit(unit) then
        if unit == "target" or unit == "focus" then
            DrawUnitFrame(unit)
        else
            DrawPlate(unit)
        end
    end
end

function WTF.InitializePredict()
    if not CombatLogUsable() or type(C_NamePlate) ~= "table"
            or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then
        return
    end
    predict.available = true
    predict.read = EventInfoReader()
    predict.player = UnitGUID("player")
    -- Saved ticks of ranks this file no longer knows are dropped.
    for id in pairs(WTF.accountDB.ticks) do
        if not RANKS[id] then
            WTF.accountDB.ticks[id] = nil
        end
    end
    for id, rank in pairs(RANKS) do
        local name = C_Spell.GetSpellName(id)
        if type(name) == "string" then
            predict.byName[name] = rank[1]
        end
    end
    -- Made only here, past the class gate and on a client with the combat log.
    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", OnEvent)
    for _, event in ipairs({"COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "NAME_PLATE_UNIT_ADDED",
        "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH", "UNIT_MAXHEALTH"}) do
        events:RegisterEvent(event)
    end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    -- The target frame's block is made at login, out of combat.
    local bar = Resolve(UNIT_ADAPTERS, "target")
    if bar then
        Overlay(bar, "target")
    end
    DrawAll()
end

-- /wtf debug_predict: each mob's DoTs, ticks, the average tick and where it
-- came from (learned, saved, or guessed), and the damage to come.
function WTF.ReportPredictDebug()
    if not predict.available then
        WTF.Report("DoT prediction: off on this client (it needs the combat log, as on Classic Era).")
        return
    end
    local settings = WTF.db.predict
    WTF.Report(string.format("DoT prediction: enabled=%s plates=%s dies=%s", tostring(settings.enabled),
        tostring(settings.plates), tostring(settings.dies)))
    -- Which AddOn's bar each unit is drawn on.
    local frames = {}
    for _, unit in ipairs({"target", "focus"}) do
        local _, name = Resolve(UNIT_ADAPTERS, unit)
        frames[#frames + 1] = unit .. "=" .. tostring(name or "none")
    end
    for index = 1, MAX_NAMEPLATE_UNITS do
        local shown = predict.plates["nameplate" .. index]
        if shown then
            frames[#frames + 1] = "nameplate" .. index .. "=" .. shown.name
        end
    end
    WTF.Report("Frames: " .. table.concat(frames, ", "))
    local now, any = Now(), false
    for guid, mob in pairs(predict.mobs) do
        any = true
        WTF.Report(string.format("%s: %d to come", tostring(mob.name), WTF.PredictedDamage(guid)))
        for _, family in ipairs(FAMILY_ORDER) do
            local dot = mob.dots[family]
            if dot then
                WTF.Report(string.format("  %s (spell %d): tick %d of %d, %s %.1f, %d to come", family, dot.rank,
                    TicksDone(dot, now), dot.ticks, dot.source, dot.average,
                    math.floor(DotRemaining(dot, now) + 0.5)))
            end
        end
    end
    if not any then
        WTF.Report("No DoTs of yours on any mob.")
    end
end
