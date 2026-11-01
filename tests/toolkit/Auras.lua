local _, ns = ...
local DyresToolkit = ns.toolkit

-- Moved from Warlock Tools Forever's AuraEngine.lua (1.4.0, sha256
-- 49853236f2ff...) for every Dyre's AddOn (Toolkit 2.4.0; Dyre's Debuff
-- Tracker phase 1, coordinator-approved 2026-10-30). Only its namespace and
-- these lines changed. MTF, DSU, and DBR still carry their own copies until
-- each switches over.
--
-- Aura slots for Dyre's AddOns (trackers, nameplate dots, timer bars).
-- On Forever they are Blizzard's engine AuraContainers
-- (CustomAuraContainerTemplate from Blizzard_AuraContainer): AddOn code cannot
-- read auras in combat there, so the engine reads them and draws into regions
-- the AddOn made. Classic Era and Anniversary have no such engine, but AddOn code may
-- read auras in combat and nothing is secret (John, WTF 1.3.2: "how can we get
-- those up and working on pre-forever?"). There this file gives the same
-- container in plain Lua: AddAuraSlot, SetUnit, UpdateAllAuras, and
-- SetAuraSlotCandidateFilters, each slot one hidden button whose initializer
-- the AddOn runs once, then shown with the first of your auras on the unit that
-- its candidate filters match, with the icon, cooldown sweep, draining bar,
-- spell name, and time left that the engine would draw. Forever keeps the
-- engine: this is used only when the template is missing.

local TEMPLATE = "CustomAuraContainerTemplate"
local MAX_AURAS = 40
-- Bars and times redraw this often while any slot shows a timed aura, and not
-- at all when none does.
local TICK = 0.1

local engineKind

local function EngineAvailable()
    if type(C_XMLUtil) ~= "table" or type(C_XMLUtil.GetTemplateInfo) ~= "function" then
        return false
    end
    if type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function"
            and type(C_AddOns.LoadAddOn) == "function" and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    return C_XMLUtil.GetTemplateInfo(TEMPLATE) ~= nil
end

-- "engine" (Forever), "lua" (Classic: plain aura reads), or nil (neither).
function DyresToolkit.AuraEngineKind()
    if engineKind == nil then
        if EngineAvailable() then
            engineKind = "engine"
        elseif type(C_UnitAuras) == "table" and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
            engineKind = "lua"
        else
            engineKind = false
        end
    end
    return engineKind or nil
end

-- What a client without either lacks, for the "stays off" lines.
DyresToolkit.AURA_ENGINE_MISSING = TEMPLATE .. " and C_UnitAuras.GetAuraDataByIndex"

local containers = {}
local ticking = {}
local ticker, dispatcher

local function TimeText(remaining)
    if remaining >= 60 then
        return string.format("%d m", math.ceil(remaining / 60))
    end
    return string.format("%d s", math.ceil(remaining))
end

local function Redraw(button, now)
    local display = button.display
    local remaining = button.expires - now
    if remaining < 0 then
        remaining = 0
    end
    if display.bar then
        display.bar:SetMinMaxValues(0, button.duration)
        local direction = display.barOptions and display.barOptions.direction
        local elapsedDirection = type(Enum) == "table" and Enum.StatusBarTimerDirection
            and direction == Enum.StatusBarTimerDirection.ElapsedTime
        display.bar:SetValue(elapsedDirection and button.duration - remaining or remaining)
    end
    if display.text then
        display.text:SetText(TimeText(remaining))
    end
end

local function Tick(self, elapsed)
    self.wait = (self.wait or 0) - elapsed
    if self.wait > 0 then
        return
    end
    self.wait = TICK
    local now = GetTime()
    for button in pairs(ticking) do
        Redraw(button, now)
    end
end

local function SetTicking(button, on)
    ticking[button] = on or nil
    if not ticker then
        ticker = CreateFrame("Frame")
    end
    ticker:SetScript("OnUpdate", next(ticking) and Tick or nil)
end

local function Matches(filters, aura)
    if type(filters) ~= "table" or type(aura.spellId) ~= "number" then
        return false
    end
    if filters.includeSpellIDs and filters.includeSpellIDs[aura.spellId] then
        return true
    end
    if filters.includeDispelTypes and aura.dispelName and filters.includeDispelTypes[aura.dispelName] then
        return not (filters.excludeSpellIDs and filters.excludeSpellIDs[aura.spellId])
    end
    return false
end

local function HideSlot(slot)
    slot.button:Hide()
    SetTicking(slot.button, false)
end

local function ShowSlot(slot, aura)
    local button, display = slot.button, slot.button.display
    if display.icon then
        display.icon:SetTexture(aura.icon)
    end
    if display.spellName then
        display.spellName:SetText(aura.name)
    end
    local duration = type(aura.duration) == "number" and aura.duration or 0
    local expires = type(aura.expirationTime) == "number" and aura.expirationTime or 0
    if display.cooldown then
        if duration > 0 then
            display.cooldown:SetCooldown(expires - duration, duration)
        else
            display.cooldown:Clear()
        end
    end
    button:Show()
    if duration > 0 and expires > 0 then
        button.duration, button.expires = duration, expires
        Redraw(button, GetTime())
        SetTicking(button, true)
    else
        SetTicking(button, false)
        if display.bar then
            display.bar:SetMinMaxValues(0, 1)
            display.bar:SetValue(1)
        end
        if display.text then
            display.text:SetText("")
        end
    end
end

local function Update(container)
    local unit = container.unit
    local read = {}
    local live = unit and unit ~= "none" and UnitExists(unit)
    for _, slot in ipairs(container.slots) do
        local found
        if live then
            local list = read[slot.filter]
            if not list then
                list = {}
                for index = 1, MAX_AURAS do
                    local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, slot.filter)
                    if not aura then
                        break
                    end
                    list[#list + 1] = aura
                end
                read[slot.filter] = list
            end
            for _, aura in ipairs(list) do
                if Matches(slot.filters, aura) then
                    found = aura
                    break
                end
            end
        end
        if found then
            ShowSlot(slot, found)
        else
            HideSlot(slot)
        end
    end
end

-- One frame follows the events that change what a unit shows, for every
-- plain-Lua container bound to that unit.
local DISPATCH_UNITS = {PLAYER_TARGET_CHANGED = "target", PLAYER_FOCUS_CHANGED = "focus"}

local function Dispatch(_, event, unit)
    unit = DISPATCH_UNITS[event] or unit
    for container in pairs(containers) do
        if container.unit == unit then
            Update(container)
        end
    end
end

local function StartDispatcher()
    if dispatcher then
        return
    end
    dispatcher = CreateFrame("Frame")
    for _, event in ipairs({"UNIT_AURA", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED"}) do
        dispatcher:RegisterEvent(event)
    end
    dispatcher:SetScript("OnEvent", Dispatch)
end

-- The engine slot's region setters, kept for the redraw.
local function NewSlotButton(container)
    local button = CreateFrame("Button", nil, container)
    button:EnableMouse(false)
    button:Hide()
    button.display = {}
    function button:SetIcon(region) self.display.icon = region end
    function button:SetDurationCooldown(region) self.display.cooldown = region end
    function button:SetDurationBar(region, options) self.display.bar, self.display.barOptions = region, options end
    function button:SetSpellName(region) self.display.spellName = region end
    function button:SetDurationText(region) self.display.text = region end
    function button:SetMouseClickEnabled(enabled) self:EnableMouse(enabled == true) end
    function button:SetMouseMotionEnabled() end
    return button
end

local function NewLuaContainer(parent)
    local container = CreateFrame("Frame", nil, parent)
    container.slots, container.byKey, container.unit = {}, {}, "none"
    function container:AddAuraSlot(key, filter, options)
        local button = NewSlotButton(self)
        local slot = {key = key, filter = filter, filters = options and options.candidateFilters, button = button}
        self.slots[#self.slots + 1] = slot
        self.byKey[key] = slot
        if options and options.initializeFrame then
            options.initializeFrame(button)
        end
    end
    function container:SetAuraSlotCandidateFilters(key, filters)
        local slot = self.byKey[key]
        if not slot then
            error("aura slot '" .. tostring(key) .. "' was not found with this key.")
        end
        slot.filters = filters
        Update(self)
    end
    function container:SetUnit(unit)
        self.unit = unit or "none"
        Update(self)
    end
    function container:UpdateAllAuras()
        Update(self)
    end
    containers[container] = true
    StartDispatcher()
    return container
end

-- An aura container on the parent: the engine's on Forever, else the plain-Lua one.
function DyresToolkit.CreateAuraContainer(parent)
    if DyresToolkit.AuraEngineKind() == "engine" then
        return CreateFrame("AuraContainer", nil, parent, TEMPLATE)
    end
    return NewLuaContainer(parent)
end
