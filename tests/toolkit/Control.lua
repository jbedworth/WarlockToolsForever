local _, ns = ...
local DyresToolkit = ns.toolkit

-- The crowd-control tracker, for every Dyre's AddOn (Toolkit 2.5.0, engine
-- stage B; lead-approved plan, 2026-11-01). Merged from Warlock Tools Forever
-- 1.4.1's Control.lua (rows for many mobs, Banish's focus-only rows and
-- clicks, the Focus box, Fear's nameplate timers) and Mage Tools Forever
-- 1.2.3's Polymorph.lua (one bar, the click-through holder, the time-left
-- text while no unit shows the mob), which keep their own copies until each
-- switches over. Their rules are this file's spec:
--
-- AddOn code cannot read enemy auras in combat on Forever, so each row is an
-- AuraContainer slot (Auras.lua): the engine draws the bar; the tracker knows
-- only which mobs you cast on, from your own cast events. The mob is locked as
-- the cast starts (UNIT_SPELLCAST_SENT names it) and its GUID used when the
-- cast lands, never a new lookup by name. A row binds to its mob through a
-- unit (never mouseover) and goes when the mob dies, after the spell's
-- longest time plus 5 s, or, for a focus-only row, when your focus becomes
-- another mob or none. A dim line stays behind each bar, so a spell that
-- broke early shows as gone. A spell with `click` (Banish, Polymorph), cast
-- while focus works, counts only at your focus and its row clicks to cast it
-- on your focus again; secure attributes change only out of combat, so a
-- row's click sits in a fixed secure slot under it and is set as the cast
-- starts (a pull's cast starts before combat).
--
-- The engine never owns SavedVariables: the owning AddOn passes `store` (its
-- saved table, read live) and keeps its sanitizers, reset, lock, and
-- migrations. Frame names are passed in. Markers come only from the macros'
-- /tm (Macros.lua); nothing here calls SetRaidTarget.

local FORGET_SLACK = 5
local AURA_FILTER = "HARMFUL|PLAYER"
local MAX_NAMEPLATE_UNITS = 40
local MAX_AURAS = 40
-- A row whose mob is gone while its secure click slot still shows (a slot
-- changes only out of combat) stays, dimmed, so no click area is invisible.
local SPENT_ALPHA = 0.45
local PLACEHOLDER_ALPHA = 0.3
-- The time-left text, while no unit shows the mob, redraws this often.
local TEXT_TICK = 1
local PLATE_TIMER_WIDTH = 60
local PLATE_TIMER_HEIGHT = 5
local PLATE_TIMER_GAP = 2
local BROWN = {0.28, 0.16, 0.07, 0.85}
local IDLE_BORDER = {0.45, 0.35, 0.2}
local LINE_BACKGROUND = {0.1, 0.1, 0.1, 0.6}
local FOCUS_RED = {0.9, 0.1, 0.1}
-- WTF's Bars theme: the name line, then a bar line with an icon.
local DEFAULT_LOOK = {width = 200, header = 18, line = 16, icon = 14, padding = 6, gap = 4, text = 1, alpha = 1,
    color = {1, 0.85, 0.1}}
-- WTF Control's orders (lead decision 2a): a cast is locked on the first live
-- hostile unit with its name in the order your own casts aim (focus, the mob
-- under the mouse, your target, then a nameplate, with the plate memory for
-- secret plate GUIDs); a focus-only spell on your focus alone.
local DEFAULT_LOCK = {units = {"focus", "mouseover", "target", "plates"}, memory = true, secretHostile = true,
    plateKey = true}
local DEFAULT_FOCUS_LOCK = {units = {"focus"}, secretHostile = true, plateKey = true}

-- A row click: the same spell on your focus, and nothing else (no marker, no
-- targeting); with no focus it does nothing.
function DyresToolkit.FocusRecastMacro(spell)
    return "/use [@focus,exists,harm,nodead] " .. spell
end

local function Named(names, index)
    if type(names) == "table" then
        return names[index]
    end
    if type(names) == "string" then
        return names .. index
    end
end

local function Union(sets, defs, test)
    local ids = {}
    for _, def in ipairs(defs) do
        if test(def) then
            for id in pairs(sets[def.key] or {}) do
                ids[id] = true
            end
        end
    end
    return ids
end

-- spec (required: addon, store, spells or class, names.row and names.click):
--   addon      the owning AddOn's folder name (owner claims and debug)
--   priority   owner priority: 10 for a class Tools AddOn, 5 for Dyre's
--              Debuff Tracker (Owners.lua)
--   class      "WARLOCK": the owner kinds' class, and the default spells
--              and macros from ClassData
--   spells     control spell defs (ClassData's `control`)
--   macros     macro defs (ClassData's `macros`), or false for none
--   store      the owner's saved table: enabled, plateTimers, macros (false
--              turns each off), markers ({[key] = index})
--   markerFor  function(key) -> marker index, instead of store.markers
--   names      {row = prefix or {exact names}, click = prefix or {...},
--              focus = the Focus box's name (optional)}
--   parent     the frame the click slots sit in, top down (the owner places
--              and moves it); without one, the owner places each slot
--   rows       how many rows (default 5)
--   look       a table or function() -> {width, header, line, icon,
--              padding, gap, text (font scale), alpha, color, label}
--   locked     function() -> true while frames are locked (else samples)
--   samples    sample names per row while unlocked
--   find       FindUnit order for a row's mob (default focus, target,
--              plates, memory)
--   lock       LockCast options for a cast (default WTF Control's)
--   focusLock  LockCast options for a focus-only cast (default WTF's)
--   focusBox   {key = "fear", color = {r, g, b}}: a box above the rows with
--              that spell on your focus, its click casting it there again
--   countdown  true: while focus does not work and no unit shows a row's
--              mob, its name shows the time left as text (MTF's)
--   clickThrough true: a slot is always there while the bar is, taking the
--              mouse only with a click to make or while unlocked (MTF's)
--   announce   {text = function(key) -> text or nil (off), enabled =
--              function, say = function}: tokens %T mob, %M marker, %Z zone
--   keeper     {owned = saved name -> true table, warn = function(text)}
--   onAdopt    function(name): a macro of another Dyre's AddOn's adopted
--   tooltip    function(holder, row): a slot's tooltip
--   onDragStart, onDragStop  for the slots, when the owner drags by them
--   onChange   function(): after rows change (the owner's own layout)
-- Returns the tracker, else nil and what is missing.
function DyresToolkit.CreateControlTracker(spec)
    if type(spec) ~= "table" or type(spec.addon) ~= "string" or type(spec.store) ~= "table"
        or type(spec.names) ~= "table" or not spec.names.row or not spec.names.click then
        return nil, "spec"
    end
    if not DyresToolkit.AuraEngineKind() then
        return nil, DyresToolkit.AURA_ENGINE_MISSING
    end
    local classData = spec.class and DyresToolkit.ClassSpells(spec.class) or {}
    local spells = spec.spells or classData.control
    if type(spells) ~= "table" or #spells == 0 then
        return nil, "spells"
    end
    local macroDefs = spec.macros
    if macroDefs == nil then
        macroDefs = classData.macros
    end
    local store = spec.store
    local class = spec.class or spec.addon
    local tracker = {rows = {}, casts = {}, kinds = {}, ids = {}, sets = {}, plateTimers = {},
        ownerKinds = {control = "control:" .. class, macros = "macros:" .. class, announce = "announce:" .. class}}
    local owner = tracker.ownerKinds
    local plates = {byUnit = tracker.plateTimers, free = {}, all = {}}
    local keeper = DyresToolkit.CreateMacroKeeper(spec.keeper)
    local announce = spec.announce or {}
    local announcer = DyresToolkit.CreateAnnouncer({enabled = announce.enabled, say = announce.say})
    local events = CreateFrame("Frame")
    local focusBox

    local function Look()
        local look = type(spec.look) == "function" and spec.look() or spec.look or {}
        local merged = {}
        for key, value in pairs(DEFAULT_LOOK) do
            merged[key] = value
        end
        for key, value in pairs(look) do
            merged[key] = value
        end
        merged.height = merged.header + merged.line + merged.padding
        return merged
    end

    local function Locked()
        return not spec.locked or spec.locked() ~= false
    end

    local function Owns(what)
        return DyresToolkit.IsOwner(owner[what], spec.addon)
    end

    local function Enabled()
        return store.enabled ~= false and Owns("control")
    end

    local function Marker(key)
        if spec.markerFor then
            return spec.markerFor(key)
        end
        return type(store.markers) == "table" and store.markers[key] or nil
    end

    -- Spell sets -------------------------------------------------------------------

    local function BuildSpellSets()
        local byID, sets = DyresToolkit.IndexSpells(spells)
        tracker.kinds, tracker.sets = byID, sets
        tracker.ids = Union(sets, spells, function(def) return def.bar end)
    end

    function tracker:KnowsAny()
        return DyresToolkit.KnowsAny(self.ids)
    end

    -- A control spell by ID, else by name (a rank the sets do not list yet).
    local function KindOf(spellID)
        local spell = tracker.kinds[spellID]
        if spell then
            return spell
        end
        local name = DyresToolkit.SpellName(spellID)
        if not name then
            return nil
        end
        for _, def in ipairs(spells) do
            for _, id in ipairs(def.ids) do
                if DyresToolkit.SpellName(id) == name then
                    tracker.kinds[spellID] = def
                    tracker.sets[def.key][spellID] = true
                    if def.bar then
                        tracker.ids[spellID] = true
                    end
                    return def
                end
            end
        end
    end

    local function IDsWhere(test)
        return Union(tracker.sets, spells, test)
    end

    local function FirstBar()
        for _, def in ipairs(spells) do
            if def.bar then
                return def
            end
        end
        return spells[1]
    end

    -- Rows -------------------------------------------------------------------------

    local function FindUnit(guid)
        if not guid then
            return nil
        end
        return DyresToolkit.FindUnit(guid, spec.find)
    end

    local function Bind(row, unit)
        local wanted = unit or "none"
        if row.boundUnit == wanted then
            return
        end
        row.boundUnit = wanted
        if row.container then
            row.container:SetUnit(wanted)
            row.container:UpdateAllAuras()
        end
    end

    local function TimeText(row)
        if not row.expires or row.boundUnit ~= "none" then
            return nil
        end
        local remaining = row.expires - GetTime()
        if remaining <= 0 then
            return nil
        end
        return "  |cff999999" .. math.ceil(remaining) .. " s|r"
    end

    local function Layout()
        local look = Look()
        local enabled = Enabled()
        local sample = not Locked()
        -- A focusBox spell on your focus shows in the box, not twice.
        local focusGUID = focusBox and DyresToolkit.FocusWorks() and DyresToolkit.MobKey("focus")
        if focusBox then
            local name = DyresToolkit.ReadName("focus")
            focusBox.display.name:SetText(sample and not name and "Focus (sample)" or ("Focus: " .. (name or "")))
        end
        for index, row in ipairs(tracker.rows) do
            local holder = row.holder
            local spent = not row.guid and holder:IsVisible() and holder.mobName ~= nil
            row:SetAlpha((spent and SPENT_ALPHA or 1) * look.alpha)
            if not enabled and not spent then
                row:Hide()
            elseif row.guid and not row.focusOnly and focusGUID and row.key == focusBox.key and row.guid == focusGUID then
                row:Hide()
            elseif row.guid then
                row.name:SetText(row.mobName .. (spec.countdown and TimeText(row) or ""))
                row:Show()
            elseif spent then
                row.name:SetText(holder.mobName)
                row:Show()
            elseif sample and spec.samples and spec.samples[index] then
                row.name:SetText(spec.samples[index])
                row:Show()
            else
                row:Hide()
            end
        end
        if spec.onChange then
            spec.onChange()
        end
    end

    -- Out of combat only: each slot's secure click, whether it is there, and
    -- the rows' scale, so rows and slots never drift apart in combat.
    local function ApplyClicks()
        DyresToolkit.OutOfCombat(tracker, function()
            local enabled = Enabled()
            local locked = Locked()
            local works = DyresToolkit.FocusWorks()
            local known = tracker:KnowsAny()
            if tracker.scale then
                for _, row in ipairs(tracker.rows) do
                    row:SetScale(tracker.scale)
                end
            end
            if focusBox then
                local def = tracker.focusDef
                local spell = def and DyresToolkit.SpellName(def.ids[1])
                -- No box on a client whose focus has not been seen to work.
                local shown = enabled and spell and known and works
                focusBox:SetAttribute("type1", shown and "macro" or nil)
                focusBox:SetAttribute("macrotext1", shown and DyresToolkit.FocusRecastMacro(spell) or nil)
                -- Only unit conditions decide a secure frame's visibility in
                -- combat: while you have a live hostile focus, or always while
                -- frames are unlocked, to drag by.
                UnregisterStateDriver(focusBox, "visibility")
                RegisterStateDriver(focusBox, "visibility", not shown and "hide"
                    or not locked and "show" or "[@focus,exists,harm,nodead] show; hide")
            end
            for _, row in ipairs(tracker.rows) do
                local holder = row.holder
                local name = row.clickName
                local spell = works and enabled and row.clickSpell or nil
                holder:SetAttribute("type1", name and spell and "macro" or nil)
                holder:SetAttribute("macrotext1", name and spell and DyresToolkit.FocusRecastMacro(spell) or nil)
                holder.mobName, holder.spellName = spell and name or nil, spell
                if spec.clickThrough then
                    holder:SetShown(enabled and (known or not locked))
                    holder:EnableMouse(not locked or spell ~= nil)
                else
                    -- A click area only where there is something to recast, or to drag by.
                    holder:SetShown(enabled and ((name ~= nil and spell ~= nil) or not locked))
                end
            end
            Layout()
        end)
    end

    local function Forget(row)
        row.guid, row.mobName, row.clickName, row.clickSpell, row.token = nil, nil, nil, nil, nil
        row.focusOnly, row.key, row.expires = nil, nil, nil
        Bind(row, nil)
        Layout()
        ApplyClicks()
    end

    local function RowFor(guid, name, spell)
        if spell and spell.single then
            for _, row in ipairs(tracker.rows) do
                if row.key == spell.key or (not row.guid and row.clickKey == spell.key) then
                    return row
                end
            end
        end
        for _, row in ipairs(tracker.rows) do
            if (guid and row.guid == guid) or (not row.guid and row.clickName == name) then
                return row
            end
        end
        -- A row is free once its click slot is empty too: a slot's action can
        -- be cleared only out of combat, so a mob forgotten in combat keeps
        -- its slot until then, and no other mob gets a click that casts on it.
        for _, row in ipairs(tracker.rows) do
            if not row.guid and not row.clickName and not row.holder.mobName then
                return row
            end
        end
    end

    -- Without a known focus: the mob's own spell, read where a unit shows it
    -- (nothing is secret on the clients without focus), for the time-left text.
    local function ReadAura(row, unit)
        if not spec.countdown or DyresToolkit.FocusWorks() or not unit or type(C_UnitAuras) ~= "table"
            or type(C_UnitAuras.GetAuraDataByIndex) ~= "function" then
            return
        end
        local set = tracker.sets[row.key] or {}
        for index = 1, MAX_AURAS do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, AURA_FILTER)
            if not aura then
                break
            end
            local id, expires = aura.spellId, aura.expirationTime
            if not DyresToolkit.IsSecret(id) and set[id] and not DyresToolkit.IsSecret(expires)
                and type(expires) == "number" then
                row.expires = expires > 0 and expires or nil
                return
            end
        end
        row.expires = nil
    end

    -- While no unit shows a counted-down mob, its text redraws; it stops on its own.
    local function TickText()
        if tracker.ticking then
            return
        end
        local function Step()
            local any = false
            for _, row in ipairs(tracker.rows) do
                any = any or (row.guid ~= nil and TimeText(row) ~= nil)
            end
            Layout()
            if any then
                C_Timer.After(TEXT_TICK, Step)
            else
                tracker.ticking = false
            end
        end
        tracker.ticking = true
        Step()
    end

    -- focusChanged: PLAYER_FOCUS_CHANGED, not a plate event. A mob locked by
    -- its plate key has no GUID to compare, and its focus can lose and regain
    -- a plate under another token, so only a new focus ends that row.
    local function Rebind(focusChanged)
        for _, row in ipairs(tracker.rows) do
            if row.focusOnly then
                -- Your focus is no longer the mob: another mob, or none. A
                -- focus whose GUID is secret stays (it cannot be told apart).
                local guid = DyresToolkit.ReadGUID("focus")
                if not UnitExists("focus") or (guid and guid ~= row.guid) or DyresToolkit.IsDead("focus")
                    or (focusChanged and DyresToolkit.KeyPlate(row.guid)) then
                    Forget(row)
                end
            elseif row.guid then
                local unit = FindUnit(row.guid)
                if unit and DyresToolkit.IsDead(unit) then
                    Forget(row)
                else
                    if unit then
                        ReadAura(row, unit)
                    end
                    Bind(row, unit)
                    if not unit and spec.countdown and row.expires then
                        TickText()
                    end
                end
            end
        end
    end

    local function Track(row, guid, mobName, spell, spellName)
        row.guid, row.mobName, row.key, row.expires = guid, mobName, spell.key, nil
        row.focusOnly = nil
        if spell.click and DyresToolkit.FocusWorks() then
            row.clickName, row.clickSpell, row.clickKey = mobName, spellName, spell.key
            row.focusOnly = true
        end
        local token = {}
        row.token = token
        if row.focusOnly then
            Bind(row, "focus")
        else
            local unit = FindUnit(guid)
            ReadAura(row, unit)
            Bind(row, unit)
            if not unit and spec.countdown then
                TickText()
            end
        end
        Layout()
        ApplyClicks()
        C_Timer.After((spell.longest or 0) + FORGET_SLACK, function()
            if row.token == token then
                Forget(row)
            end
        end)
    end

    -- Frames -------------------------------------------------------------------

    local function ScaleFont(text, scale)
        local base = text.dyreBaseFont
        if not base then
            local font, size, flags = text:GetFont()
            base = {font = font, size = size, flags = flags}
            text.dyreBaseFont = base
        end
        if base.font and type(base.size) == "number" then
            text:SetFont(base.font, base.size * scale, base.flags)
        end
    end

    -- The engine slot's regions; only here may the tracker touch what it
    -- hands the engine (afterwards each is the engine's: a later call raised
    -- "Attempt to access forbidden object from code tainted by an AddOn" in
    -- WTF). With look.alpha below 1, the bar ignores its parent's opacity and
    -- carries it in its color and texts (the engine's bar did not fade with
    -- its parent, found in client).
    local function SlotInitializer(row, look)
        return function(button)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", row, "TOPLEFT", look.padding, -look.header)
            button:SetSize(look.width - look.padding * 2, look.line)
            button:SetMouseClickEnabled(false)
            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetSize(look.icon, look.icon)
            icon:SetPoint("LEFT", 1, 0)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local status = CreateFrame("StatusBar", nil, button)
            status:SetPoint("TOPLEFT", button, "TOPLEFT", look.icon + 4, 0)
            status:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
            status:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            local alpha = look.alpha < 1 and look.alpha or nil
            if alpha and type(status.SetIgnoreParentAlpha) == "function" then
                status:SetIgnoreParentAlpha(true)
            end
            status:SetStatusBarColor(look.color[1], look.color[2], look.color[3], alpha)
            local spellName = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            ScaleFont(spellName, look.text)
            spellName:SetPoint("LEFT", 4, 0)
            spellName:SetJustifyH("LEFT")
            local timeLeft = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            ScaleFont(timeLeft, look.text)
            timeLeft:SetPoint("RIGHT", -4, 0)
            if alpha then
                spellName:SetAlpha(alpha)
                timeLeft:SetAlpha(alpha)
            end
            button:SetIcon(icon)
            local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
            button:SetDurationBar(status, {direction = direction})
            button:SetSpellName(spellName)
            button:SetDurationText(timeLeft, {})
        end
    end

    local function Backdrop(frame, border)
        frame:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2}})
        frame:SetBackdropColor(BROWN[1], BROWN[2], BROWN[3], BROWN[4])
        frame:SetBackdropBorderColor(border[1], border[2], border[3])
    end

    -- The row's own regions at the look's sizes: plain frames, at once.
    local function ApplyLook(frame, look)
        frame:SetSize(look.width, look.height)
        ScaleFont(frame.name, look.text)
        frame.name:SetWidth(look.width - look.padding * 2)
        frame.line:ClearAllPoints()
        frame.line:SetPoint("TOPLEFT", frame, "TOPLEFT", look.padding, -look.header)
        frame.line:SetSize(look.width - look.padding * 2, look.line)
        frame.placeholder:SetSize(look.icon, look.icon)
        if frame.label then
            ScaleFont(frame.label, look.text)
            frame.label:ClearAllPoints()
            frame.label:SetPoint("LEFT", frame.line, "LEFT", look.icon + 8, 0)
        end
    end

    local function CreateDisplay(frame, look, nameFont, def)
        Backdrop(frame, IDLE_BORDER)
        frame.name = frame:CreateFontString(nil, "OVERLAY", nameFont or "GameFontHighlightSmall")
        frame.name:SetPoint("TOPLEFT", look.padding, -4)
        frame.name:SetJustifyH("LEFT")
        frame.line = frame:CreateTexture(nil, "BACKGROUND")
        frame.line:SetColorTexture(LINE_BACKGROUND[1], LINE_BACKGROUND[2], LINE_BACKGROUND[3], LINE_BACKGROUND[4])
        def = def or FirstBar()
        local first = def.ids[1]
        frame.placeholder = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        frame.placeholder:SetTexture(C_Spell.GetSpellTexture(first))
        frame.placeholder:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        frame.placeholder:SetDesaturated(true)
        frame.placeholder:SetAlpha(PLACEHOLDER_ALPHA)
        frame.placeholder:SetPoint("LEFT", frame.line, "LEFT", 1, 0)
        if look.label then
            frame.label = frame:CreateFontString(nil, "BORDER", "GameFontDisableSmall")
            frame.label:SetText(DyresToolkit.SpellName(first) or def.label)
        end
        ApplyLook(frame, look)
    end

    -- A new container for a row at the look's sizes (the old one lets its mob
    -- go and hides), bound again to the row's mob.
    local function BuildContainer(row, look)
        if row.container then
            row.container:SetUnit("none")
            row.container:Hide()
        end
        local container = DyresToolkit.CreateAuraContainer(row)
        container:SetPoint("TOPLEFT", row, "TOPLEFT")
        container:SetSize(1, 1)
        container:AddAuraSlot("control", AURA_FILTER, {
            candidateFilters = {includeSpellIDs = tracker.ids},
            initializeFrame = SlotInitializer(row, look),
        })
        row.container = container
        local unit = row.boundUnit
        row.boundUnit = nil
        Bind(row, unit ~= "none" and unit or nil)
    end

    local function ShowTooltip(holder)
        if spec.tooltip then
            spec.tooltip(holder, holder.row)
            return
        end
        GameTooltip:SetOwner(holder, "ANCHOR_TOP")
        if holder.spellName then
            GameTooltip:SetText("Click: " .. holder.spellName .. " your focus again.", 1, 1, 1)
            GameTooltip:AddLine("No marker and no target change. With no focus it does nothing.", 0.7, 0.7, 0.7,
                true)
        else
            GameTooltip:SetText("Your crowd control shows here with its time left.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end

    local function Draggable(frame)
        if spec.onDragStart then
            frame:RegisterForDrag("LeftButton")
            frame:SetScript("OnDragStart", spec.onDragStart)
            frame:SetScript("OnDragStop", spec.onDragStop)
        end
    end

    local function CreateRow(index, look)
        -- The click slot: a secure button at a fixed place under the row.
        local holder = CreateFrame("Button", Named(spec.names.click, index), spec.parent or UIParent,
            "SecureActionButtonTemplate")
        holder:SetSize(look.width, look.height)
        if spec.parent then
            holder:SetPoint("TOPLEFT", spec.parent, "TOPLEFT", 0, -(index - 1) * (look.height + look.gap))
        end
        holder:RegisterForClicks("AnyUp", "AnyDown")
        holder:SetAttribute("useOnKeyDown", false)
        Draggable(holder)
        holder:SetScript("OnEnter", ShowTooltip)
        holder:SetScript("OnLeave", function() GameTooltip:Hide() end)
        holder:Hide()
        -- The row: an ordinary frame on top, taking no mouse, so it shows and
        -- hides in combat (a secure parent would stop that).
        local row = CreateFrame("Frame", Named(spec.names.row, index), UIParent, "BackdropTemplate")
        row:SetPoint("CENTER", holder, "CENTER")
        row:EnableMouse(false)
        CreateDisplay(row, look)
        row.holder, holder.row = holder, row
        BuildContainer(row, look)
        row:Hide()
        return row
    end

    -- The Focus box (WTF, John 1.3.1): a fixed secure button above the rows
    -- whose only click casts its spell on your focus, so it can never cast on
    -- another mob, also when your focus changes in combat. A secure frame's
    -- visibility can follow only unit conditions, so it shows while you have
    -- a live hostile focus; its dim line fills while your spell is on it.
    local function CreateFocusBox(look)
        local box = CreateFrame("Button", spec.names.focus, spec.parent or UIParent, "SecureActionButtonTemplate")
        box:SetSize(look.width, look.height)
        if spec.parent then
            box:SetPoint("BOTTOMLEFT", spec.parent, "TOPLEFT", 0, look.gap)
        end
        box:RegisterForClicks("AnyUp", "AnyDown")
        box:SetAttribute("useOnKeyDown", false)
        Draggable(box)
        local def = tracker.focusDef
        box:SetScript("OnEnter", function(self)
            local spell = DyresToolkit.SpellName(def.ids[1]) or def.label
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Click: " .. spell .. " your focus again.", 1, 1, 1)
            GameTooltip:AddLine("Only your focus; with no focus it does nothing.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        box:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local display = CreateFrame("Frame", nil, box, "BackdropTemplate")
        display:SetAllPoints(box)
        display:EnableMouse(false)
        CreateDisplay(display, look, "GameFontNormalSmall", def)
        local color = spec.focusBox.color or FOCUS_RED
        display:SetBackdropBorderColor(color[1], color[2], color[3])
        local container = DyresToolkit.CreateAuraContainer(display)
        container:SetPoint("TOPLEFT", display, "TOPLEFT")
        container:SetSize(1, 1)
        container:AddAuraSlot(def.key, AURA_FILTER, {
            candidateFilters = {includeSpellIDs = tracker.sets[def.key]},
            initializeFrame = SlotInitializer(display, look),
        })
        container:SetUnit("focus")
        box.display, box.container, box.key = display, container, def.key
        return box
    end

    -- Timers on nameplates (WTF's Fear timers, for every spell with
    -- plateTimer): a thin bar under each nameplate, an AuraContainer slot
    -- bound to the plate's unit, only while your spell is up. Plates are
    -- pooled: a mob back in plate range may get another plate and token, so a
    -- timer attaches on NAME_PLATE_UNIT_ADDED and shows the real time left.
    local function PlateTimerInitializer(timer, look)
        return function(button)
            button:ClearAllPoints()
            button:SetAllPoints(timer)
            button:SetMouseClickEnabled(false)
            button:SetMouseMotionEnabled(false)
            local background = button:CreateTexture(nil, "BACKGROUND")
            background:SetAllPoints()
            background:SetColorTexture(0, 0, 0, 0.7)
            local bar = CreateFrame("StatusBar", nil, button)
            bar:SetAllPoints()
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            bar:SetStatusBarColor(look.color[1], look.color[2], look.color[3])
            local timeLeft = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            timeLeft:SetPoint("LEFT", bar, "RIGHT", 3, 0)
            local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
            button:SetDurationBar(bar, {direction = direction})
            button:SetDurationText(timeLeft, {})
            timer.bar = bar
        end
    end

    local function PlateIDs()
        return IDsWhere(function(def) return def.plateTimer end)
    end

    local function CreatePlateTimer()
        local timer = CreateFrame("Frame", nil, UIParent)
        timer:SetSize(PLATE_TIMER_WIDTH, PLATE_TIMER_HEIGHT)
        timer:EnableMouse(false)
        local container = DyresToolkit.CreateAuraContainer(timer)
        container:SetPoint("TOPLEFT")
        container:SetSize(1, 1)
        container:AddAuraSlot("plate", AURA_FILTER, {
            candidateFilters = {includeSpellIDs = PlateIDs()},
            initializeFrame = PlateTimerInitializer(timer, Look()),
        })
        timer.container = container
        plates.all[#plates.all + 1] = timer
        return timer
    end

    local function DetachTimer(unit)
        local timer = plates.byUnit[unit]
        if not timer then
            return
        end
        plates.byUnit[unit] = nil
        timer.container:SetUnit("none")
        timer:Hide()
        timer:SetParent(UIParent)
        plates.free[#plates.free + 1] = timer
    end

    local function AttachTimer(unit)
        if not tracker.hasPlateTimers or not Enabled() or store.plateTimers == false or type(C_NamePlate) ~= "table" then
            return
        end
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if not plate or plate:IsForbidden() then
            return
        end
        DetachTimer(unit)
        local timer = table.remove(plates.free) or CreatePlateTimer()
        timer:SetParent(plate)
        timer:ClearAllPoints()
        timer:SetPoint("TOP", plate, "BOTTOM", 0, -PLATE_TIMER_GAP)
        plates.byUnit[unit] = timer
        timer.container:SetUnit(unit)
        timer.container:UpdateAllAuras()
        timer:Show()
    end

    local function RefreshPlateTimers()
        for unit in pairs(plates.byUnit) do
            DetachTimer(unit)
        end
        for index = 1, MAX_NAMEPLATE_UNITS do
            local unit = "nameplate" .. index
            if UnitExists(unit) then
                AttachTimer(unit)
            end
        end
    end

    -- Casts --------------------------------------------------------------------

    -- At the start of a cast (author-approved), as the other group messages
    -- go; %M is the marker's code for a cast at the mob the macro marks.
    local function AnnounceCast(spell, targetName, atFocus)
        if not Owns("announce") or not announce.text then
            return
        end
        local text = announce.text(spell.key)
        if type(text) ~= "string" or text == "" then
            return
        end
        local marker = atFocus and spell.marker and Marker(spell.key) or 0
        announcer:SendGroup(spell.key, DyresToolkit.FormatAnnouncement(text,
            {T = targetName or "", M = DyresToolkit.MarkerCode(marker), Z = GetZoneText() or ""}))
    end

    local function OnCastSent(target, castGUID, spellID)
        if DyresToolkit.IsSecret(spellID) or DyresToolkit.IsSecret(target) or DyresToolkit.IsSecret(castGUID) then
            return
        end
        local spell = KindOf(spellID)
        if not spell then
            return
        end
        if spell.untargeted then
            AnnounceCast(spell)
            return
        end
        if type(target) ~= "string" or target == "" then
            return
        end
        local guid, unit, look
        local focusOnly = spell.click and DyresToolkit.FocusWorks()
        if focusOnly then
            guid = DyresToolkit.LockCast(target, spec.focusLock or DEFAULT_FOCUS_LOCK)
            unit = guid and "focus"
            look = {"focus only"}
        else
            guid, unit, look = DyresToolkit.LockCast(target, spec.lock or DEFAULT_LOCK)
        end
        tracker.lastSent = {spellID = spellID, target = target, unit = unit, locked = guid ~= nil,
            look = table.concat(look or {}, " ")}
        AnnounceCast(spell, target, spell.click and guid ~= nil)
        if not spell.bar or not Enabled() then
            return
        end
        -- The mob's plate, while it is your focus or target, for later binding.
        DyresToolkit.LearnPlates()
        tracker.casts[castGUID] = {target = target, spellID = spellID, guid = guid}
        -- A pull's cast starts out of combat and lands in it: set the click
        -- now, while the game still allows it.
        if focusOnly and guid and not InCombatLockdown() then
            local row = RowFor(guid, target, spell)
            if row and (not row.guid or spell.single) then
                -- A single spell's new cast replaces the click of the mob up
                -- there, which a failed cast gives back.
                tracker.casts[castGUID].before = row.guid and {row.clickName, row.clickSpell} or nil
                row.clickName, row.clickSpell, row.clickKey = target, DyresToolkit.SpellName(spellID), spell.key
                tracker.casts[castGUID].row = row
                ApplyClicks()
            end
        end
    end

    local function OnCastSucceeded(castGUID)
        if DyresToolkit.IsSecret(castGUID) then
            return
        end
        local cast = tracker.casts[castGUID]
        tracker.casts[castGUID] = nil
        if not cast or not Enabled() then
            return
        end
        -- Only the mob locked as the cast started; never one found by name
        -- now, which after a tab or a mouse move may be another mob.
        local guid = cast.guid
        if not guid then
            tracker.lastLanded = "no mob locked as it started"
            return
        end
        local unit = FindUnit(guid)
        if unit and DyresToolkit.IsDead(unit) then
            tracker.lastLanded = "the mob was dead"
            return
        end
        local spell = tracker.kinds[cast.spellID]
        if not unit and DyresToolkit.KeyPlate(guid) and not (spell.click and DyresToolkit.FocusWorks()) then
            tracker.lastLanded = "its nameplate went"
            return
        end
        local row = RowFor(guid, cast.target, spell)
        if row then
            Track(row, guid, cast.target, spell, DyresToolkit.SpellName(cast.spellID))
            for index, each in ipairs(tracker.rows) do
                if each == row then
                    tracker.lastLanded = "row " .. index .. " bound to " .. tostring(row.boundUnit)
                end
            end
        else
            tracker.lastLanded = "no free row"
        end
    end

    local function OnCastFailed(castGUID)
        if DyresToolkit.IsSecret(castGUID) then
            return
        end
        local cast = tracker.casts[castGUID]
        tracker.casts[castGUID] = nil
        -- A cast that never landed gives back the row it reserved, or the
        -- click of the mob still up there.
        local row = cast and cast.row
        if row then
            if cast.before and row.guid then
                row.clickName, row.clickSpell = cast.before[1], cast.before[2]
            elseif not row.guid then
                row.clickName, row.clickSpell = nil, nil
            end
            ApplyClicks()
        end
    end

    -- Macros -------------------------------------------------------------------

    local function MacroKnown(def)
        if def.pet then
            return DyresToolkit.PetKnows(def.spell)
        end
        return DyresToolkit.KnowsAny(tracker.sets[def.known] or {def.spell})
    end

    function tracker:MacroBody(def)
        local control
        for _, each in ipairs(spells) do
            if each.key == def.known then
                control = each
            end
        end
        return DyresToolkit.FocusCastMacro({spell = def.spell, marker = def.marker and Marker(def.marker) or nil,
            condition = def.condition, shift = def.shift, untargeted = control and control.untargeted})
    end

    -- Out of combat only, and only while this AddOn owns the class's macros
    -- (another owner keeps them: nothing is deleted). Off deletes ours.
    function tracker:ApplyMacros()
        if not macroDefs or not Owns("macros") then
            return
        end
        DyresToolkit.OutOfCombat(keeper, function()
            if not keeper:Available() then
                return
            end
            for _, def in ipairs(macroDefs) do
                if store.macros == false then
                    keeper:Delete(def.name)
                else
                    local body = tracker:MacroBody(def)
                    if body and MacroKnown(def) then
                        local result = keeper:Write(def.name, body)
                        if result == "adopted" and spec.onAdopt then
                            spec.onAdopt(def.name)
                        end
                    end
                end
            end
        end)
    end

    -- Events -------------------------------------------------------------------

    events:SetScript("OnEvent", function(_, event, unit, first, second, third)
        if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
            if not DyresToolkit.IsSecret(unit) then
                -- Its token may show another mob next, so a row or a cast
                -- keyed by it goes now (your focus's row stays on "focus").
                if event == "NAME_PLATE_UNIT_REMOVED" then
                    local key = "plate:" .. unit
                    for _, cast in pairs(tracker.casts) do
                        if cast.guid == key then
                            cast.guid = nil
                        end
                    end
                    for _, row in ipairs(tracker.rows) do
                        if row.guid == key and not row.focusOnly then
                            Forget(row)
                        end
                    end
                end
                DyresToolkit.ForgetPlate(unit)
            end
            if event == "NAME_PLATE_UNIT_ADDED" then
                AttachTimer(unit)
                if not DyresToolkit.IsSecret(unit) then
                    DyresToolkit.LearnPlate(unit)
                end
            else
                DetachTimer(unit)
            end
            -- Layout too: a row bound to the plate just now drops its
            -- countdown text at once, not on the next tick.
            Rebind()
            Layout()
            return
        end
        if event == "UNIT_PET" then
            -- A pet summoned: its spells (Seduction) can be read now.
            tracker:ApplyMacros()
        elseif event == "UNIT_SPELLCAST_SENT" then
            OnCastSent(first, second, third)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            OnCastSucceeded(first)
        elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
            OnCastFailed(first)
        elseif event == "UNIT_HEALTH" then
            -- By GUID: the death can come through any unit that shows the mob.
            local guid = not DyresToolkit.IsSecret(unit) and DyresToolkit.ReadGUID(unit)
            for _, row in ipairs(tracker.rows) do
                local same = (guid and row.guid == guid)
                    or (DyresToolkit.KeyPlate(row.guid) and row.boundUnit == unit)
                if same and DyresToolkit.IsDead(unit) then
                    Forget(row)
                end
            end
        elseif event == "UNIT_AURA" then
            if not DyresToolkit.IsSecret(unit) then
                for _, row in ipairs(tracker.rows) do
                    if row.guid and row.boundUnit == unit then
                        ReadAura(row, unit)
                    end
                end
            end
        elseif event == "SPELLS_CHANGED" then
            BuildSpellSets()
            for _, row in ipairs(tracker.rows) do
                row.container:SetAuraSlotCandidateFilters("control", {includeSpellIDs = tracker.ids})
            end
            for _, timer in ipairs(plates.all) do
                timer.container:SetAuraSlotCandidateFilters("plate", {includeSpellIDs = PlateIDs()})
            end
            if focusBox then
                focusBox.container:SetAuraSlotCandidateFilters(focusBox.key,
                    {includeSpellIDs = tracker.sets[focusBox.key]})
            end
            ApplyClicks()
            tracker:ApplyMacros()
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- A click set as a cast started, for a cast that never landed, goes.
            for _, row in ipairs(tracker.rows) do
                if not row.guid then
                    row.clickName, row.clickSpell = nil, nil
                end
            end
            ApplyClicks()
        else
            -- The Toolkit learns the flag in its own handler; asked here too,
            -- so the macros and clicks change before this rebind, whatever
            -- the handler order.
            if event == "PLAYER_FOCUS_CHANGED" then
                DyresToolkit.LearnFocusWorks()
            end
            -- Your target or focus changed: learn its plate before rebinding.
            DyresToolkit.LearnPlates()
            Rebind(event == "PLAYER_FOCUS_CHANGED")
            Layout()
        end
    end)

    -- Public -------------------------------------------------------------------

    -- Settings changed (store, markers, lock): claims, rows, clicks, plate
    -- timers, and macros follow, each out of combat where it must.
    function tracker:Refresh()
        DyresToolkit.SetOwnerEnabled(owner.control, spec.addon, store.enabled ~= false)
        DyresToolkit.SetOwnerEnabled(owner.macros, spec.addon, macroDefs and true or false)
        Layout()
        ApplyClicks()
        RefreshPlateTimers()
        self:ApplyMacros()
    end

    -- The rows' scale (plain frames over the slots), applied out of combat
    -- with the slots' own, so they never drift apart.
    function tracker:SetScale(scale)
        self.scale = scale
        ApplyClicks()
    end

    -- A new look on the rows' regions only, at once, also in combat; no
    -- engine slot is rebuilt. For a settings slider's every step: call
    -- Rebuild once the slider stops.
    function tracker:ApplyLook()
        local look = Look()
        for _, row in ipairs(self.rows) do
            ApplyLook(row, look)
        end
        Layout()
    end

    -- A new look (sizes, text size, opacity): the rows' regions at once, the
    -- engine slots rebuilt out of combat (in combat, when it ends).
    function tracker:Rebuild()
        self:ApplyLook()
        DyresToolkit.OutOfCombat(self.rows, function()
            local current = Look()
            for _, row in ipairs(self.rows) do
                if spec.parent then
                    row.holder:SetSize(current.width, current.height)
                end
                BuildContainer(row, current)
            end
            Layout()
        end)
    end

    function tracker:IsOwner(what)
        return Owns(what)
    end

    function tracker:Owner(what)
        return DyresToolkit.KindOwner(owner[what])
    end

    -- Lines for the owner's debug command (it adds its own prefix).
    function tracker:DebugLines()
        local lines = {}
        local ids = {}
        for id in pairs(self.ids) do
            ids[#ids + 1] = id
        end
        table.sort(ids)
        lines[#lines + 1] = string.format("known=%s focusWorks=%s owner=%s macros=%s announce=%s",
            tostring(self:KnowsAny()), tostring(DyresToolkit.FocusWorks()), tostring(self:Owner("control")),
            tostring(self:Owner("macros")), tostring(self:Owner("announce")))
        lines[#lines + 1] = "ids=" .. table.concat(ids, ",")
        local sent = self.lastSent
        if sent then
            lines[#lines + 1] = string.format("lastSent spell=%d target=%s unit=%s locked=%s looked=%s",
                sent.spellID, sent.target, tostring(sent.unit), tostring(sent.locked), sent.look)
        end
        lines[#lines + 1] = "lastLanded " .. tostring(self.lastLanded or "nothing yet")
        for index, row in ipairs(self.rows) do
            lines[#lines + 1] = string.format("row %d mob=%s unit=%s click=%s macro=%s", index,
                tostring(row.mobName), tostring(row.boundUnit), tostring(row.holder:IsShown()),
                (tostring(row.holder:GetAttribute("macrotext1")):gsub("\n", " | ")))
        end
        local attached = 0
        for _ in pairs(plates.byUnit) do
            attached = attached + 1
        end
        lines[#lines + 1] = string.format("plateTimers=%s attached=%d", tostring(store.plateTimers ~= false), attached)
        return lines
    end

    -- Build --------------------------------------------------------------------

    BuildSpellSets()
    for _, def in ipairs(spells) do
        tracker.hasPlateTimers = tracker.hasPlateTimers or def.plateTimer == true
        if spec.focusBox and def.key == spec.focusBox.key then
            tracker.focusDef = def
        end
    end
    DyresToolkit.ClaimOwner(owner.control, spec.addon, spec.priority)
    DyresToolkit.ClaimOwner(owner.macros, spec.addon, spec.priority)
    if spec.announce then
        DyresToolkit.ClaimOwner(owner.announce, spec.addon, spec.priority)
    end
    local look = Look()
    for index = 1, spec.rows or 5 do
        tracker.rows[index] = CreateRow(index, look)
    end
    if tracker.focusDef and spec.names.focus then
        focusBox = CreateFocusBox(look)
        tracker.focusBox = focusBox
    end
    for _, event in ipairs({"PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "SPELLS_CHANGED", "UNIT_HEALTH"}) do
        events:RegisterEvent(event)
    end
    if spec.countdown then
        events:RegisterEvent("UNIT_AURA")
    end
    for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_PET"}) do
        events:RegisterUnitEvent(event, "player")
    end
    -- Learned or reset (by any Dyre's AddOn): the macros, the Focus box, and
    -- the row clicks follow, out of combat.
    DyresToolkit.OnFocusWorks(function()
        tracker:ApplyMacros()
        ApplyClicks()
    end)
    for _, what in ipairs({"control", "macros", "announce"}) do
        DyresToolkit.OnOwnerChanged(owner[what], function()
            Layout()
            ApplyClicks()
            if what == "control" then
                RefreshPlateTimers()
            elseif what == "macros" then
                tracker:ApplyMacros()
            end
        end)
    end
    tracker:Refresh()
    return tracker
end
