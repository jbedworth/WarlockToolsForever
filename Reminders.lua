local _, WTF = ...

-- Buff reminders (author-approved, as MTF's): an icon shown only while a buff
-- is missing, with a pulsing gold border that draws the eye. Only Demon Armor
-- (author-approved; the others are situational), which Demon Skin also
-- counts as before you learn it. Clicking the icon casts the armor you used
-- last, else your best. The icon moves (and snaps, Layout.lua) and resizes
-- with the mouse wheel while frames are unlocked, then locks with everything
-- else.
--
-- Aura APIs refuse AddOn code in combat on Forever, so WTF checks only out of
-- combat. The icon is a secure button, which changes only out of combat, so
-- it sits in a holder the game hides for combat with a state driver: a
-- reminder is for between pulls.

-- Classic IDs; a buff counts by name, so every rank does. prefer lists what a
-- click casts, best first, until you cast one yourself.
WTF.REMINDERS = {
    {key = "armor", label = "Demon Armor", on = true,
        spells = {687, 696, 706, 1086, 11733, 11734, 11735}, prefer = {706, 687}},
}
WTF.REMINDER_SCALE_MIN = 50
WTF.REMINDER_SCALE_MAX = 200
WTF.REMINDER_SCALE_STEP = 10
WTF.DEFAULT_REMINDER_SCALE = 100

local ICON_SIZE = 40
local BORDER = 3
local GOLD = {1, 0.82, 0}
local PULSE_SECONDS = 0.6
local PULSE_LOW_ALPHA = 0.15
local DEFAULT_POINT = {"CENTER", "CENTER", 0, 180}
local COMBAT_DRIVER = "[combat] hide; show"

local reminders = {icons = {}, spellKeys = {}}
local holder

function WTF.SanitizeReminderScale(value)
    if type(value) ~= "number" or value ~= math.floor(value) then
        return WTF.DEFAULT_REMINDER_SCALE
    end
    local stepped = math.floor(value / WTF.REMINDER_SCALE_STEP + 0.5) * WTF.REMINDER_SCALE_STEP
    return math.max(WTF.REMINDER_SCALE_MIN, math.min(WTF.REMINDER_SCALE_MAX, stepped))
end

-- The saved reminder settings, repaired; Core calls this from SanitizeDB.
function WTF.SanitizeReminders(saved, sanitizePosition)
    saved = type(saved) == "table" and saved or {}
    local spells = type(saved.spells) == "table" and saved.spells or {}
    local icons = type(saved.icons) == "table" and saved.icons or {}
    local last = type(saved.last) == "table" and saved.last or {}
    local clean = {enabled = saved.enabled ~= false, spells = {}, icons = {}, last = {}}
    for _, reminder in ipairs(WTF.REMINDERS) do
        if type(spells[reminder.key]) == "boolean" then
            clean.spells[reminder.key] = spells[reminder.key]
        else
            clean.spells[reminder.key] = reminder.on
        end
        local icon = type(icons[reminder.key]) == "table" and icons[reminder.key] or {}
        clean.icons[reminder.key] = {position = sanitizePosition(icon.position),
            scale = WTF.SanitizeReminderScale(icon.scale)}
        if type(last[reminder.key]) == "string" then
            clean.last[reminder.key] = last[reminder.key]
        end
    end
    return clean
end

-- Without the spellbook API nothing counts as known, so the reminder stays hidden.
local function Knows(id)
    return type(C_SpellBook) == "table" and type(C_SpellBook.IsSpellKnown) == "function"
        and C_SpellBook.IsSpellKnown(id) == true
end

local function Known(reminder)
    for _, id in ipairs(reminder.spells) do
        if Knows(id) then
            return true
        end
    end
    return false
end

local function BestTexture(reminder)
    for index = #reminder.spells, 1, -1 do
        if Knows(reminder.spells[index]) then
            return C_Spell.GetSpellTexture(reminder.spells[index])
        end
    end
    return C_Spell.GetSpellTexture(reminder.spells[#reminder.spells])
end

-- Out of combat only. A secret answer counts as buffed: WTF cannot tell.
local function HasBuff(reminder)
    for _, id in ipairs(reminder.spells) do
        local name = C_Spell.GetSpellName(id)
        if name and C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL") ~= nil then
            return true
        end
    end
    return false
end

-- The spell a click casts: the last one you cast, else your best known.
local function ClickSpell(reminder)
    local last = WTF.db.reminders.last[reminder.key]
    if last then
        for _, id in ipairs(reminder.spells) do
            if Knows(id) and C_Spell.GetSpellName(id) == last then
                return last
            end
        end
    end
    for _, id in ipairs(reminder.prefer) do
        if Knows(id) then
            return C_Spell.GetSpellName(id)
        end
    end
end

-- Out of combat only.
local function ApplyClick(icon, spell)
    icon.spell = spell
    icon:SetAttribute("type1", spell and "spell" or nil)
    icon:SetAttribute("spell1", spell)
    icon:SetAttribute("unit1", spell and "player" or nil)
end

local function Pulse(icon, on)
    if on and not icon.pulse:IsPlaying() then
        icon.pulse:Play()
    elseif not on then
        icon.pulse:Stop()
    end
end

local function ShowIcon(icon, shown)
    icon:SetShown(shown)
    Pulse(icon, shown)
end

function WTF.RefreshReminders()
    if not reminders.ready then
        return
    end
    -- The secure icon changes only out of combat; the holder hides it for combat.
    if InCombatLockdown() then
        reminders.dirty = true
        return
    end
    reminders.dirty = false
    local settings = WTF.db.reminders
    local unlocked = not WTF.db.locked
    local alive = UnitIsDeadOrGhost("player") ~= true
    for _, reminder in ipairs(WTF.REMINDERS) do
        local icon = reminders.icons[reminder.key]
        icon:SetScale(settings.icons[reminder.key].scale / 100)
        icon.texture:SetTexture(BestTexture(reminder))
        icon.mover:SetShown(unlocked)
        icon:EnableMouseWheel(unlocked)
        local wanted = settings.enabled and settings.spells[reminder.key]
        if unlocked then
            -- Dragging must not cast.
            ApplyClick(icon, nil)
            ShowIcon(icon, wanted)
        elseif wanted and alive and Known(reminder) and not HasBuff(reminder) then
            ApplyClick(icon, ClickSpell(reminder))
            ShowIcon(icon, true)
        else
            ApplyClick(icon, nil)
            ShowIcon(icon, false)
        end
    end
end

local function Place(icon)
    local position = WTF.db.reminders.icons[icon.key].position
    icon:ClearAllPoints()
    if position then
        icon:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else
        icon:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
    end
end

function WTF.ResetRemindersPosition()
    for _, reminder in ipairs(WTF.REMINDERS) do
        local saved = WTF.db.reminders.icons[reminder.key]
        saved.position, saved.scale = nil, WTF.DEFAULT_REMINDER_SCALE
    end
    if not reminders.ready then
        return
    end
    if InCombatLockdown() then
        reminders.placeDirty = true
        return
    end
    for _, icon in pairs(reminders.icons) do
        Place(icon)
    end
    WTF.RefreshReminders()
end

-- The mouse wheel resizes in 10% steps, keeping the icon's center.
local function Resize(icon, delta)
    if WTF.db.locked or InCombatLockdown() then
        return
    end
    local saved = WTF.db.reminders.icons[icon.key]
    local step = delta > 0 and WTF.REMINDER_SCALE_STEP or -WTF.REMINDER_SCALE_STEP
    saved.scale = WTF.SanitizeReminderScale(saved.scale + step)
    WTF.ScaleKeepingCenter(icon, saved.scale / 100)
end

local function ShowTooltip(icon)
    GameTooltip:SetOwner(icon, "ANCHOR_TOP")
    GameTooltip:SetText(icon.label, GOLD[1], GOLD[2], GOLD[3])
    if not WTF.db.locked then
        GameTooltip:AddLine("Drag to move; Shift-drag moves a snapped group; scroll to resize.", 1, 1, 1, true)
    elseif icon.spell then
        GameTooltip:AddLine("Missing. Click: " .. icon.spell .. ".", 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function CreateIcon(reminder)
    local icon = CreateFrame("Button", "WarlockToolsForeverReminder_" .. reminder.key, holder,
        "SecureActionButtonTemplate")
    icon.key, icon.label = reminder.key, reminder.label
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetMovable(true)
    icon:SetClampedToScreen(true)
    icon:RegisterForClicks("AnyUp", "AnyDown")
    icon:SetAttribute("useOnKeyDown", false)
    icon:RegisterForDrag("LeftButton")
    -- Dragging and snapping: Layout.lua.
    icon:SetScript("OnDragStart", WTF.BeginDrag)
    icon:SetScript("OnDragStop", WTF.EndDrag)
    icon:SetScript("OnMouseWheel", Resize)
    icon:SetScript("OnEnter", ShowTooltip)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    -- The attention border: a solid gold edge that pulses.
    local glow = CreateFrame("Frame", nil, icon, "BackdropTemplate")
    glow:SetPoint("TOPLEFT", -BORDER - 1, BORDER + 1)
    glow:SetPoint("BOTTOMRIGHT", BORDER + 1, -BORDER - 1)
    glow:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = BORDER})
    glow:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3])
    glow:EnableMouse(false)
    icon.glow = glow
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(PULSE_LOW_ALPHA)
    fade:SetDuration(PULSE_SECONDS)
    icon.pulse = pulse
    icon.mover = WTF.CreateMover(icon)
    icon.mover.hint:SetText("")
    WTF.RegisterMovable(icon, function(position) WTF.db.reminders.icons[reminder.key].position = position end)
    icon:Hide()
    return icon
end

-- The armor you cast is what a click recasts.
local function RememberCast(spellID)
    local key = not WTF.IsSecret(spellID) and reminders.spellKeys[spellID]
    if key then
        WTF.db.reminders.last[key] = C_Spell.GetSpellName(spellID)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        RememberCast(spellID)
        return
    end
    if InCombatLockdown() then
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if reminders.driverPending then
            reminders.driverPending = false
            RegisterStateDriver(holder, "visibility", COMBAT_DRIVER)
        end
        if reminders.placeDirty then
            reminders.placeDirty = false
            for _, icon in pairs(reminders.icons) do
                Place(icon)
            end
        end
    end
    WTF.RefreshReminders()
end)

function WTF.InitializeReminders()
    if type(RegisterStateDriver) ~= "function" then
        WTF.Report("The buff reminder stays off: this client lacks RegisterStateDriver.")
        return
    end
    for _, reminder in ipairs(WTF.REMINDERS) do
        for _, id in ipairs(reminder.spells) do
            reminders.spellKeys[id] = reminder.key
        end
    end
    holder = CreateFrame("Frame", "WarlockToolsForeverReminders", UIParent)
    holder:SetAllPoints(UIParent)
    holder:EnableMouse(false)
    for _, reminder in ipairs(WTF.REMINDERS) do
        local icon = CreateIcon(reminder)
        reminders.icons[reminder.key] = icon
        Place(icon)
    end
    reminders.ready = true
    WTF.reminderIcons = reminders.icons
    for _, event in ipairs({"UNIT_AURA", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED",
        "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST"}) do
        events:RegisterEvent(event)
    end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    -- After a reload in combat the driver waits for combat to end.
    if InCombatLockdown() then
        reminders.dirty = true
        reminders.driverPending = true
        return
    end
    RegisterStateDriver(holder, "visibility", COMBAT_DRIVER)
    WTF.RefreshReminders()
end

-- /wtf debug_reminders: each reminder, whether you know it and have it, and the click.
function WTF.ReportRemindersDebug()
    for _, reminder in ipairs(WTF.REMINDERS) do
        local icon = reminders.icons[reminder.key]
        local buffed = "not checked in combat"
        if not InCombatLockdown() then
            buffed = tostring(HasBuff(reminder))
        end
        WTF.Report(string.format("debug_reminders %s on=%s known=%s buffed=%s shown=%s click=%s", reminder.key,
            tostring(WTF.db.reminders.spells[reminder.key]), tostring(Known(reminder)), buffed,
            tostring(icon and icon:IsShown()), tostring(icon and icon.spell)))
    end
end
