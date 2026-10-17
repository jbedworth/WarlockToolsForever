local addonName, ns = ...

-- Shield display: a self-contained component any AddOn can ship (author-
-- approved: Mage Tools Forever now; a standalone AddOn or other class AddOns
-- later). It needs nothing from its host but a settings table and a report
-- function, given to ShieldDisplay.Initialize.
--
-- A segmented crescent to the right of your character fills from the bottom
-- with your remaining absorb from any source (your Ice Barrier, a Priest's
-- Power Word: Shield, a Voidwalker's Sacrifice, a trinket), measured against
-- the shield's size when it landed, in the shield's color, with the amount as
-- a number below (author-approved, after NaN Shield). The size is the absorb
-- total captured as the shield lands: stored and passed on, never read.
--
-- The client returns the absorb amount only as a secret value: AddOn code can
-- never read, compare, or do math on it, and curve objects refuse secrets from
-- AddOn code. The StatusBar and FontString methods that accept secrets from
-- AddOn code (SetValue, SetMinMaxValues, SetText) and AbbreviateNumbers show it
-- anyway; the ring tracks it live, also in combat. The ring's opacity is the
-- absorb itself (SetAlpha accepts secrets from AddOn code; opacity stops at 1),
-- so the moment a shield is used up the whole ring drops, in combat too, as
-- frame AddOns' absorb bars do (author-approved). When to show it comes from
-- your own shield casts and from absorb changes (both readable in combat), for
-- the shield's length; out of combat your buffs are read too, so a shield that
-- broke early hides then.
--
-- Shields with no absorb amount (Mana Shield) drain with time in the inner
-- crescent instead (see `timed` below).
--
-- Several shields can be up at once (Ice Barrier, Mana Shield, and a ward).
-- The client gives AddOns only the combined absorb, so the crescent shows the
-- total, refilled as each shield lands (author-approved). Under it, a row of
-- icons shows which shields are up: Blizzard's AuraContainer draws them and
-- removes each the moment its buff goes, also in combat, when AddOn code
-- cannot read buffs. The engine's shown state is secret to AddOn code (found
-- in client), so each shield has a fixed spot in the row. The row also shows
-- a shield the absorb total leaves out: Mana Shield, whose buff carries no
-- absorb points on Forever.
--
-- Several AddOns may ship this file. Each copy registers in the shared
-- ShieldForeverRegistry as its file loads, before any PLAYER_LOGIN; at login
-- the newest version wins, the first registered on a tie, and only that copy
-- draws the ring. The others stand down and say which AddOn shows it.

local VERSION = 1
local REGISTRY_NAME = "ShieldForeverRegistry"

local ARC_TEXTURE = "Interface\\AddOns\\" .. addonName .. "\\Textures\\ShieldArc"
-- The thinner crescent nested inside it, for shields that drain with time.
local INNER_ARC_TEXTURE = ARC_TEXTURE .. "Inner"
local ARC_SIZE = 160
-- The crescent sits in the right part of the square texture, so the frame
-- centered a little right of your character puts it beside you.
local DEFAULT_POINT = {"CENTER", "CENTER", 20, -20}
-- Where the number goes: under the crescent's foot, in texture fractions.
local TEXT_X = 0.8
local TEXT_Y = 0.02
local BACKGROUND_ALPHA = 0.35
-- Seconds after your shield cast during which an absorb change is that shield
-- landing, so its total is the shield's size.
local CAPTURE_SECONDS = 0.5
-- While unlocked the outer crescent shows full, with a label for the number,
-- so its shape and place are plain (a part-filled sample looked broken).
local SAMPLE_FILL = 1
local SAMPLE_TEXT = "drag me"
-- Seconds past a shield's end before the ring hides, for timing slack.
local END_SLACK = 0.2
-- How long an absorb MTF cannot name shows after it changes: the longest
-- Classic shield another player puts on you, Power Word: Shield, lasts 30 s.
local OTHER_SECONDS = 30
-- An absorb change this soon after a known shield ended is that shield going.
local ENDING_GRACE = 2
local OTHER_COLOR = {1, 0.85, 0.45}
local BREAK_SOUND = "Sound\\Interface\\RaidWarning.ogg"
-- At most one break sound per this many seconds (the API allows 0 to 5).
local BREAK_THROTTLE = 1
-- Seconds /mtf debug_shield shows the absorb total on screen.
local PROBE_SECONDS = 8
-- The icon row under the number.
local ICON_SIZE = 18
local ICON_GAP = 3
local ICON_Y = -16
local AURA_FILTER = "HELPFUL"
local CONTAINER_TEMPLATE = "CustomAuraContainerTemplate"

-- timed marks a shield with no absorb amount (Mana Shield: no points on its
-- buff, not in the absorb total on Forever): it gets the inner crescent,
-- draining with its time left (author-approved), instead of the absorb total.
-- Known shields by name, so every rank counts: Classic IDs (confirmed on
-- Forever for Mana Shield and Fire Ward), colors, lengths, and each one's spot
-- in the icon row. Shields from other players or classes share the last spot. ranks lists every Classic rank for the break sound, which needs
-- exact IDs. Paladins have no Classic absorb; any Forever adds shows as an
-- absorb MTF cannot name.
local SHIELDS = {
    {key = "icebarrier", spot = 1, spell = 11426, color = {0.45, 0.78, 1}, seconds = 60,
        ranks = {11426, 13031, 13032, 13033}},
    {key = "manashield", spot = 2, timed = true, spell = 1463, color = {0.68, 0.45, 1}, seconds = 60,
        ranks = {1463, 8494, 8495, 10191, 10192, 10193}},
    {key = "fireward", spot = 3, spell = 543, color = {1, 0.5, 0.15}, seconds = 30,
        ranks = {543, 8457, 8458, 10223, 10225}},
    {key = "frostward", spot = 4, spell = 6143, color = {0.6, 0.92, 1}, seconds = 30,
        ranks = {6143, 8461, 8462, 10177, 28609}},
    {key = "powerwordshield", spot = 5, spell = 17, color = {1, 1, 0.85}, seconds = 30,
        ranks = {17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901}},
    {key = "shadowward", spot = 5, spell = 6229, color = {0.55, 0.3, 0.85}, seconds = 30,
        ranks = {6229, 11739, 11740, 28610}},
    {key = "sacrifice", spot = 5, spell = 7812, color = {0.75, 0.4, 0.95}, seconds = 30,
        ranks = {7812, 19438, 19440, 19441, 19442, 19443}},
}

local ShieldDisplay = {}
ns.ShieldDisplay = ShieldDisplay

local registry = _G[REGISTRY_NAME]
if type(registry) ~= "table" then
    registry = {copies = {}}
    _G[REGISTRY_NAME] = registry
end
local copy = {version = VERSION, addon = addonName}
registry.copies[#registry.copies + 1] = copy

local host
local shield = {names = {}, ends = {}, latest = nil, otherEnds = nil, lastEnd = 0, soundIDs = {},
    deferred = false}
local frame

-- The copy that draws the ring: the newest version, the first registered on a tie.
local function Owner()
    local owner
    for _, entry in ipairs(registry.copies) do
        if not owner or entry.version > owner.version then
            owner = entry
        end
    end
    return owner
end

function ShieldDisplay.IsOwner()
    return Owner() == copy
end

function ShieldDisplay.OwnerAddOn()
    local owner = Owner()
    return owner and owner.addon
end

-- The display's size in percent of its default.
ShieldDisplay.SCALE_MIN = 50
ShieldDisplay.SCALE_MAX = 150
ShieldDisplay.SCALE_STEP = 5
ShieldDisplay.DEFAULT_SCALE = 100

function ShieldDisplay.SanitizeScale(value)
    if type(value) ~= "number" or value ~= math.floor(value) then
        return ShieldDisplay.DEFAULT_SCALE
    end
    local stepped = math.floor(value / ShieldDisplay.SCALE_STEP + 0.5) * ShieldDisplay.SCALE_STEP
    return math.max(ShieldDisplay.SCALE_MIN, math.min(ShieldDisplay.SCALE_MAX, stepped))
end

-- Settings with defaults, repaired so a damaged or older table cannot break it.
-- Locked by default: unlocked, the ring takes the mouse to be dragged.
function ShieldDisplay.Sanitize(settings)
    settings = type(settings) == "table" and settings or {}
    local position = settings.position
    if type(position) ~= "table" or type(position.point) ~= "string" or type(position.relativePoint) ~= "string"
        or type(position.x) ~= "number" or type(position.y) ~= "number" then
        position = nil
    end
    return {
        enabled = settings.enabled ~= false,
        locked = settings.locked ~= false,
        position = position and {point = position.point, relativePoint = position.relativePoint,
            x = position.x, y = position.y},
        number = settings.number ~= false,
        breakSound = settings.breakSound == true,
        scale = ShieldDisplay.SanitizeScale(settings.scale),
    }
end

local function Config()
    return host.settings()
end

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end

local function Describe(value)
    return IsSecret(value) and "secret" or tostring(value)
end

local function HasAbsorbAPI()
    return type(UnitGetTotalAbsorbs) == "function" and type(UnitHealthMax) == "function"
end

-- The client hands both values over as they are, secret or not.
local function UpdateFill()
    if not frame then
        return
    end
    if not Config().locked then
        frame.visible:SetAlpha(1)
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetValue(SAMPLE_FILL)
        frame.text:SetText(SAMPLE_TEXT)
        return
    end
    local absorb = UnitGetTotalAbsorbs("player")
    frame.visible:SetAlpha(absorb)
    -- Against the shield's size when it landed; your health until one is known.
    frame.bar:SetMinMaxValues(0, shield.size or UnitHealthMax("player"))
    frame.bar:SetValue(absorb)
    if Config().number then
        frame.text:SetText(type(AbbreviateNumbers) == "function" and AbbreviateNumbers(absorb) or absorb)
    else
        frame.text:SetText("")
    end
end

-- The color to show: the latest known shield still up, else any known shield
-- up, else an absorb MTF cannot name; nil when nothing is up.
-- Whether any shield is up, and the outer crescent's color: the latest
-- absorb shield still up, else any absorb shield up, else an absorb MTF cannot
-- name. A timed shield (Mana Shield) keeps the display up but never colors
-- the outer crescent; it has the inner one (in client, a Mana Shield cast
-- after a ward turned both purple).
local function ActiveShields()
    local now = GetTime()
    local anyUp, absorb = false, nil
    for _, entry in ipairs(SHIELDS) do
        local ends = shield.ends[entry.key]
        if ends and ends > now then
            anyUp = true
            if not entry.timed and (not absorb or entry.key == shield.latest) then
                absorb = entry
            end
        end
    end
    if absorb then
        return true, absorb.color
    end
    if shield.otherEnds and shield.otherEnds > now then
        return true, OTHER_COLOR
    end
    return anyUp, nil
end

function ShieldDisplay.Refresh()
    if not frame then
        return
    end
    local settings = Config()
    local up, color = ActiveShields()
    local shown = color or SHIELDS[1].color
    frame.bar:SetStatusBarColor(shown[1], shown[2], shown[3])
    -- A plain frame, so it can resize also in combat.
    frame:SetScale(settings.scale / 100)
    frame:EnableMouse(not settings.locked)
    frame.mover:SetShown(not settings.locked)
    if frame.sample then
        frame.sample:SetShown(not settings.locked)
    end
    if settings.enabled and (up or not settings.locked) then
        UpdateFill()
        frame:Show()
    else
        frame:Hide()
    end
end

local function ScheduleRefresh(seconds)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(math.max(0, seconds) + END_SLACK, ShieldDisplay.Refresh)
    end
end

local function KnownUp()
    local now = GetTime()
    for _, ends in pairs(shield.ends) do
        if ends > now then
            return true
        end
    end
    return false
end

local function EndShield(key)
    if shield.ends[key] then
        shield.ends[key] = nil
        shield.lastEnd = GetTime()
    end
end

local function OnShieldCast(spellID)
    if IsSecret(spellID) or type(spellID) ~= "number" then
        return
    end
    local entry = shield.names[C_Spell.GetSpellName(spellID)]
    if not entry then
        return
    end
    shield.ends[entry.key] = GetTime() + entry.seconds
    if not entry.timed then
        shield.latest = entry.key
    end
    shield.otherEnds = nil
    -- The absorb may land before or just after the cast event; both count.
    shield.size = UnitGetTotalAbsorbs("player")
    shield.captureUntil = GetTime() + CAPTURE_SECONDS
    ScheduleRefresh(entry.seconds)
    ShieldDisplay.Refresh()
end

-- Any absorb change: one MTF cannot name (another player's Power Word: Shield,
-- a trinket) shows for OTHER_SECONDS, unless it is a known shield going.
local function OnAbsorbChanged()
    local now = GetTime()
    if shield.captureUntil and now <= shield.captureUntil then
        shield.size = UnitGetTotalAbsorbs("player")
    elseif not KnownUp() and now - shield.lastEnd > ENDING_GRACE then
        -- The change that starts the window is that shield landing.
        if not shield.otherEnds or shield.otherEnds <= now then
            shield.size = UnitGetTotalAbsorbs("player")
        end
        shield.otherEnds = now + OTHER_SECONDS
        ScheduleRefresh(OTHER_SECONDS)
    end
    ShieldDisplay.Refresh()
end

-- Out of combat your buffs are readable: a known shield that broke early ends,
-- and one up after a reload, or put on you by another player, shows.
local function CheckBuffs()
    if InCombatLockdown() or type(C_UnitAuras) ~= "table"
        or type(C_UnitAuras.GetAuraDataBySpellName) ~= "function" then
        return
    end
    local anyKnown = false
    for _, entry in ipairs(SHIELDS) do
        local name = C_Spell.GetSpellName(entry.spell)
        local aura = name and C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
        if type(aura) ~= "table" then
            EndShield(entry.key)
        else
            anyKnown = true
            local expires = aura.expirationTime
            local ends = type(expires) == "number" and not IsSecret(expires) and expires > 0 and expires
                or shield.ends[entry.key] or GetTime() + entry.seconds
            if shield.ends[entry.key] ~= ends then
                shield.ends[entry.key] = ends
                if not entry.timed then
                    shield.latest = shield.latest or entry.key
                end
                ScheduleRefresh(ends - GetTime())
            end
        end
    end
    if anyKnown then
        shield.otherEnds = nil
    end
    ShieldDisplay.Refresh()
end

-- Break sound -----------------------------------------------------------------
-- The ring cannot see a shield end in combat, so it asks the game to play the
-- sound when the buff goes (C_UnitAuras.AddAuraSound). Off by default. The
-- game refuses changes during an encounter.

local function EncounterRestricted()
    if type(C_RestrictedActions) ~= "table" or type(C_RestrictedActions.IsAddOnRestrictionActive) ~= "function"
        or type(Enum) ~= "table" or type(Enum.AddOnRestrictionType) ~= "table" then
        return false
    end
    return C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Encounter) == true
end

local function HasAuraSounds()
    return type(C_UnitAuras) == "table" and type(C_UnitAuras.AddAuraSound) == "function"
        and type(C_UnitAuras.RemoveAuraSound) == "function"
end

function ShieldDisplay.ApplyBreakSound()
    if not frame or not HasAuraSounds() then
        return
    end
    if EncounterRestricted() then
        shield.deferred = true
        return
    end
    shield.deferred = false
    for _, id in ipairs(shield.soundIDs) do
        C_UnitAuras.RemoveAuraSound(id)
    end
    shield.soundIDs = {}
    if not Config().enabled or not Config().breakSound then
        return
    end
    local trigger = Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Removed or 2
    for _, entry in ipairs(SHIELDS) do
        for _, spellID in ipairs(entry.ranks) do
            shield.soundIDs[#shield.soundIDs + 1] = C_UnitAuras.AddAuraSound(trigger, {
                spellID = spellID, unitToken = "player", outputChannel = "master",
                throttleSeconds = BREAK_THROTTLE, soundFileName = BREAK_SOUND})
        end
    end
end

-- The ring -----------------------------------------------------------------------

local function PlaceRing()
    local position = Config().position
    frame:ClearAllPoints()
    if position then
        frame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else
        frame:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
    end
end

function ShieldDisplay.ResetPosition()
    Config().position = nil
    if frame then
        PlaceRing()
    end
end

-- The icon row ----------------------------------------------------------------

local function HasAuraContainer()
    if type(C_XMLUtil) ~= "table" or type(C_XMLUtil.GetTemplateInfo) ~= "function"
        or type(C_AddOns) ~= "table" or type(C_AddOns.LoadAddOn) ~= "function" then
        return false
    end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    return C_XMLUtil.GetTemplateInfo(CONTAINER_TEMPLATE) ~= nil
end

-- The row's spots, centered under the number.
local ICON_SPOTS = 5

local function PlaceIcon(button, spot)
    local width = ICON_SPOTS * ICON_SIZE + (ICON_SPOTS - 1) * ICON_GAP
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", frame.text, "BOTTOM", -width / 2 + (spot - 1) * (ICON_SIZE + ICON_GAP), ICON_Y)
end

local function NoMouse(region)
    for _, method in ipairs({"SetMouseClickEnabled", "SetMouseMotionEnabled"}) do
        if type(region[method]) == "function" then
            region[method](region, false)
        end
    end
    region:EnableMouse(false)
end

-- An icon in its spot, with a cooldown swipe for the time left.
local function AddIcon(button, parent, spot)
    local holder = CreateFrame("Frame", nil, button)
    holder:SetSize(ICON_SIZE, ICON_SIZE)
    PlaceIcon(holder, spot)
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local cooldown = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    cooldown:SetAllPoints(holder)
    cooldown:SetHideCountdownNumbers(true)
    button:SetIcon(icon)
    button:SetDurationCooldown(cooldown)
    return holder
end

-- The engine shows each slot's frame while its buff is up and hides it the
-- moment the buff goes. A timed shield's frame covers the whole display and
-- holds the inner crescent, which the engine drains with the buff's time
-- left; it never takes the mouse, so it cannot block clicks on the world.
local function IconInitializer(entry)
    return function(button)
        frame.iconButtons[entry.key] = button
        NoMouse(button)
        if entry.timed then
            button:SetAllPoints(frame)
            local track = button:CreateTexture(nil, "BACKGROUND")
            track:SetAllPoints()
            track:SetTexture(INNER_ARC_TEXTURE)
            track:SetVertexColor(0, 0, 0)
            track:SetAlpha(BACKGROUND_ALPHA)
            local bar = CreateFrame("StatusBar", nil, button)
            bar:SetAllPoints()
            bar:SetStatusBarTexture(INNER_ARC_TEXTURE)
            bar:SetOrientation("VERTICAL")
            bar:SetStatusBarColor(entry.color[1], entry.color[2], entry.color[3])
            local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
            button:SetDurationBar(bar, {direction = direction})
            frame.timedBars = frame.timedBars or {}
            frame.timedBars[entry.key] = bar
            AddIcon(button, frame, entry.spot)
        else
            button:SetSize(ICON_SIZE, ICON_SIZE)
            PlaceIcon(button, entry.spot)
            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cooldown:SetAllPoints(button)
            cooldown:SetHideCountdownNumbers(true)
            button:SetIcon(icon)
            button:SetDurationCooldown(cooldown)
        end
    end
end

-- Outside the opacity frame, so a shield the absorb total leaves out still
-- shows its icon.
local function CreateIcons()
    frame.iconButtons = {}
    if not HasAuraContainer() then
        return
    end
    local container = CreateFrame("AuraContainer", nil, frame, CONTAINER_TEMPLATE)
    container:SetPoint("TOPLEFT", frame, "TOPLEFT")
    container:SetSize(1, 1)
    for _, entry in ipairs(SHIELDS) do
        -- includeSpellIDs is a set, {[spellID] = true}, not a list: a list
        -- matched nothing in client.
        local ids = {}
        for _, spellID in ipairs(entry.ranks) do
            ids[spellID] = true
        end
        container:AddAuraSlot(entry.key, AURA_FILTER, {
            candidateFilters = {includeSpellIDs = ids},
            initializeFrame = IconInitializer(entry),
        })
    end
    container:SetUnit("player")
    container:UpdateAllAuras()
    frame.icons = container
end

-- While unlocked, a sample of every part: the inner crescent and an icon in
-- each spot, so the whole display can be lined up (author-approved).
local function CreateSample()
    frame.sample = CreateFrame("Frame", nil, frame)
    frame.sample:SetAllPoints()
    local inner = frame.sample:CreateTexture(nil, "ARTWORK")
    inner:SetAllPoints()
    inner:SetTexture(INNER_ARC_TEXTURE)
    local purple = SHIELDS[2].color
    inner:SetVertexColor(purple[1], purple[2], purple[3])
    local used = {}
    for _, entry in ipairs(SHIELDS) do
        if not used[entry.spot] then
            used[entry.spot] = true
            local icon = frame.sample:CreateTexture(nil, "ARTWORK")
            icon:SetSize(ICON_SIZE, ICON_SIZE)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local texture = type(C_Spell.GetSpellTexture) == "function" and C_Spell.GetSpellTexture(entry.spell)
            icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            PlaceIcon(icon, entry.spot)
        end
    end
    frame.sample:Hide()
end

-- A plain frame, not a secure one, so it updates and moves in combat. It takes
-- the mouse only while unlocked, so it never blocks clicks on the world.
local function CreateRing()
    frame = CreateFrame("Frame", nil, UIParent)
    ShieldDisplay.frame = frame
    frame:SetSize(ARC_SIZE, ARC_SIZE)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    -- Everything visible sits in one frame whose opacity follows the absorb.
    frame.visible = CreateFrame("Frame", nil, frame)
    frame.visible:SetAllPoints()
    frame.background = frame.visible:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints()
    frame.background:SetTexture(ARC_TEXTURE)
    frame.background:SetVertexColor(0, 0, 0)
    frame.background:SetAlpha(BACKGROUND_ALPHA)
    frame.bar = CreateFrame("StatusBar", nil, frame.visible)
    frame.bar:SetAllPoints()
    frame.bar:SetStatusBarTexture(ARC_TEXTURE)
    frame.bar:SetOrientation("VERTICAL")
    frame.text = frame.bar:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    frame.text:SetPoint("TOP", frame, "BOTTOMLEFT", ARC_SIZE * TEXT_X, ARC_SIZE * TEXT_Y)
    frame.text:SetShadowColor(0, 0, 0, 1)
    frame.text:SetShadowOffset(1, -1)
    frame:SetScript("OnDragStart", function(self)
        if not Config().locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        Config().position = {point = point, relativePoint = relativePoint, x = x, y = y}
    end)
    -- While unlocked: a gold outline and a hint, so the sample reads as movable.
    frame.mover = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.mover:SetAllPoints()
    frame.mover:SetBackdrop({edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12})
    frame.mover:SetBackdropBorderColor(1, 0.82, 0)
    frame.mover.hint = frame.mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.mover.hint:SetPoint("BOTTOM", frame.mover, "TOP", 0, 4)
    frame.mover.hint:SetText(host.unlockHint or "Drag to move")
    frame.mover:Hide()
    frame:Hide()
    PlaceRing()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        OnShieldCast(spellID)
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        OnAbsorbChanged()
    elseif event == "UNIT_MAXHEALTH" then
        UpdateFill()
    elseif event == "UNIT_AURA" or event == "PLAYER_ENTERING_WORLD" then
        CheckBuffs()
    elseif event == "PLAYER_REGEN_ENABLED" then
        CheckBuffs()
        if shield.deferred then
            ShieldDisplay.ApplyBreakSound()
        end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if shield.deferred and not EncounterRestricted() then
            ShieldDisplay.ApplyBreakSound()
        end
    end
end)

-- options: settings = function returning the host's saved settings table
-- (from ShieldDisplay.Sanitize); report = function(message) for chat;
-- unlockHint = optional text shown above the ring while it is unlocked.
function ShieldDisplay.Initialize(options)
    host = options
    if not ShieldDisplay.IsOwner() then
        host.report("The shield display is shown by " .. tostring(ShieldDisplay.OwnerAddOn())
            .. "; use its settings for it.")
        return
    end
    if not HasAbsorbAPI() then
        host.report("The shield display stays off: this client lacks UnitGetTotalAbsorbs or UnitHealthMax.")
        return
    end
    for _, entry in ipairs(SHIELDS) do
        local name = C_Spell.GetSpellName(entry.spell)
        if name then
            shield.names[name] = entry
        end
    end
    CreateRing()
    CreateIcons()
    CreateSample()
    for _, event in ipairs({"UNIT_SPELLCAST_SUCCEEDED", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH",
        "UNIT_AURA"}) do
        events:RegisterUnitEvent(event, "player")
    end
    for _, event in ipairs({"PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ADDON_RESTRICTION_STATE_CHANGED"}) do
        events:RegisterEvent(event)
    end
    CheckBuffs()
    ShieldDisplay.ApplyBreakSound()
end

-- Debug: which absorb APIs exist and whether their values are secret, the
-- owner, the shields tracked, and the ring's state. Each check runs on its own
-- and reports a failure in chat, since the client may hide Lua errors.
function ShieldDisplay.ReportDebug(report)
    local function Report(text)
        report("debug_shield " .. text)
    end
    local function Step(label, check)
        local ok, failure = pcall(check)
        if not ok then
            Report(label .. " failed: " .. tostring(failure))
        end
    end
    Report(string.format("UnitGetTotalAbsorbs=%s UnitHealthMax=%s AbbreviateNumbers=%s combat=%s",
        type(UnitGetTotalAbsorbs), type(UnitHealthMax), type(AbbreviateNumbers), tostring(InCombatLockdown())))
    local copies = {}
    for _, entry in ipairs(registry.copies) do
        copies[#copies + 1] = entry.addon .. " v" .. entry.version
    end
    Report(string.format("owner=%s copies=%s", tostring(ShieldDisplay.OwnerAddOn()), table.concat(copies, ", ")))
    Step("absorb", function()
        local absorb = UnitGetTotalAbsorbs("player")
        Report("absorb=" .. Describe(absorb) .. " secret=" .. tostring(IsSecret(absorb)))
    end)
    Step("alpha", function()
        -- The ring's opacity is the absorb; this shows what the client made of it.
        if frame then
            local alpha = frame.visible:GetAlpha()
            Report("ringAlpha=" .. Describe(alpha))
        end
    end)
    Step("maxHealth", function()
        local maxHealth = UnitHealthMax("player")
        Report("maxHealth=" .. Describe(maxHealth) .. " secret=" .. tostring(IsSecret(maxHealth)))
    end)
    -- The absorb is secret, so it cannot be printed; a FontString can show it.
    -- Shown on screen for a few seconds, it tells what the client counts.
    Step("showAbsorb", function()
        if not shield.probe then
            shield.probe = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
            shield.probe:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        end
        local absorb = UnitGetTotalAbsorbs("player")
        shield.probe:SetText(type(AbbreviateNumbers) == "function" and AbbreviateNumbers(absorb) or absorb)
        shield.probe:Show()
        Report("the absorb total shows above your character for " .. PROBE_SECONDS .. " seconds")
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(PROBE_SECONDS, function() shield.probe:Hide() end)
        end
    end)
    -- Out of combat a shield buff's own data is readable, including its points.
    Step("buffs", function()
        if InCombatLockdown() or type(C_UnitAuras) ~= "table"
            or type(C_UnitAuras.GetAuraDataBySpellName) ~= "function" then
            return
        end
        for _, entry in ipairs(SHIELDS) do
            local name = C_Spell.GetSpellName(entry.spell)
            local aura = name and C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
            if type(aura) == "table" then
                local points = {}
                for index, value in ipairs(type(aura.points) == "table" and aura.points or {}) do
                    points[index] = Describe(value)
                end
                Report(string.format("buff %s spellId=%s points=%s expires=%s", name, Describe(aura.spellId),
                    table.concat(points, ","), Describe(aura.expirationTime)))
            end
        end
    end)
    -- The icon row: whether it exists, and each icon's state as the engine set it.
    Step("icons", function()
        if not frame then
            return
        end
        Report(string.format("iconRow=%s template=%s", tostring(frame.icons ~= nil),
            tostring(HasAuraContainer())))
        for _, entry in ipairs(SHIELDS) do
            local button = frame.iconButtons and frame.iconButtons[entry.key]
            if button then
                local visible = button:IsShown()
                local point, _, _, x, y = button:GetPoint()
                Report(string.format("icon %s shown=%s at=%s %s,%s", entry.key, Describe(visible),
                    tostring(point), Describe(x), Describe(y)))
            else
                Report("icon " .. entry.key .. " not created")
            end
        end
    end)
    local now = GetTime()
    for _, entry in ipairs(SHIELDS) do
        local ends = shield.ends[entry.key]
        -- The client returns no value for an unknown spell; tostring needs one.
        local name = C_Spell.GetSpellName(entry.spell)
        Report(string.format("%s name=%s left=%s", entry.key, tostring(name),
            ends and string.format("%.1fs", ends - now) or "none"))
    end
    Report(string.format("other=%s ring=%s shown=%s breakSounds=%d",
        shield.otherEnds and string.format("%.1fs", shield.otherEnds - now) or "none",
        tostring(frame ~= nil), tostring(frame ~= nil and frame:IsShown()), #shield.soundIDs))
end
