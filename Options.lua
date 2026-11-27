local _, WTF = ...

-- The AddOn settings: a main page with one switch per module, and a subpage
-- per module for its details. Shards and Stones use Blizzard's vertical layout
-- with proxy settings that read and write WarlockToolsForeverDB directly;
-- Announce needs text fields, so it is a canvas page. The pages of features
-- that moved to other Dyre's AddOns each hold one row that opens that AddOn.
local TITLE = "Warlock Tools Forever"
local SHARDS_TITLE = "Soul Shards"
local STONES_TITLE = "Stones"
local ANNOUNCE_TITLE = "Announce"
-- The moved pages' titles when the owner gives none (John, 2026-11-27: "let's
-- use the same name consistently everywhere"): the owner's section title
-- (SettingsSectionTitle) names the page, so its own heading, this page, and
-- the switch on WTF's top page read the same.
local TRACKER_TITLE = "DoT Tracker"
local DOTS_TITLE = "DoTs"
local PROCS_TITLE = "Procs"
local SHIELD_TITLE = "Shield display"
local CHIMES_TITLE = "Chimes"
local REMINDERS_TITLE = "Reminders"
local CONTROL_TITLE = "Control"
local UNAVAILABLE = "The AddOn settings page is unavailable on this client. Use /wtf shards for status."

local REQUIRED_SETTINGS = {
    "RegisterVerticalLayoutCategory", "RegisterVerticalLayoutSubcategory", "RegisterCanvasLayoutSubcategory",
    "RegisterProxySetting", "RegisterAddOnCategory", "CreateCheckbox", "CreateSlider", "CreateSliderOptions",
    "OpenToCategory", "NotifyUpdate",
}

local category

local function HasSettingsAPI()
    if type(Settings) ~= "table" or type(Settings.VarType) ~= "table" then
        return false
    end
    for _, name in ipairs(REQUIRED_SETTINGS) do
        if type(Settings[name]) ~= "function" then
            return false
        end
    end
    return true
end

local function Proxy(page, variable, variableType, name, default, getValue, setValue)
    return Settings.RegisterProxySetting(page, variable, variableType, name, default, getValue, setValue)
end

-- A checkbox for one saved flag; onChange runs after the value is stored.
local function Flag(page, variable, name, group, key, default, tooltip, onChange)
    local setting = Proxy(page, variable, Settings.VarType.Boolean, name, default,
        function() return WTF.db[group][key] end,
        function(value)
            WTF.db[group][key] = value == true
            if onChange then
                onChange()
            end
        end)
    return Settings.CreateCheckbox(page, setting, tooltip)
end

-- A greyed-out checkbox for a planned feature (author-approved): never on,
-- never saved.
local function ComingSoon(page, variable, name, tooltip)
    local setting = Proxy(page, variable, Settings.VarType.Boolean, name .. " (Coming soon)", false,
        function() return false end, function() end)
    local initializer = Settings.CreateCheckbox(page, setting, tooltip)
    if type(initializer.AddModifyPredicate) == "function" then
        initializer:AddModifyPredicate(function() return false end)
    end
    return initializer
end

local function RefreshShardCounter()
    if WTF.RefreshShardCounter then
        WTF.RefreshShardCounter()
    end
end

local function RefreshStones()
    if WTF.RefreshStones then
        WTF.RefreshStones()
    end
end

-- A percent slider's value shows its % sign, so its label has no "(%)".
local function Percent(value)
    return string.format("%d%%", value)
end

-- format: true for percent, or a function for the value's text.
local function SliderOptions(minValue, maxValue, step, format)
    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    if type(MinimalSliderWithSteppersMixin) == "table" and type(options.SetLabelFormatter) == "function" then
        local formatter = format == true and Percent or (type(format) == "function" and format or nil)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
    end
    return options
end

-- The Toolkit's gold mark at the slider's default (public since Toolkit
-- 2.2.0). Without the Toolkit, or an older one, no mark.
local function DefaultTick(initializer, minValue, maxValue, default)
    local toolkit = WTF.toolkit
    if toolkit and type(toolkit.AddDefaultTick) == "function" then
        toolkit.AddDefaultTick(initializer, {min = minValue, max = maxValue, default = default})
    end
end

-- A greyed-out checkbox that only says something; never saved.
local function Notice(page, variable, name, tooltip)
    local setting = Proxy(page, variable, Settings.VarType.Boolean, name, true,
        function() return true end, function() end)
    local initializer = Settings.CreateCheckbox(page, setting, tooltip)
    if type(initializer.AddModifyPredicate) == "function" then
        initializer:AddModifyPredicate(function() return false end)
    end
    return initializer
end

-- Pages for the features that moved out of WTF (author-approved): each links
-- to the AddOn that has it now (Dyre's Toolkit's AddSettingsLink, which opens
-- it through the openSettings it joined the Toolkit with; greyed while that
-- AddOn is missing, and a click then says what to install), instead of
-- mirroring its settings. In 1.11.0 (John, 2026-11-20: "The WTF DoT's
-- settings pages should simply redirect users to DDT") the DoT Tracker (with
-- the prediction and the smart curse), DoTs, and Control pages, in their old
-- places.
--
-- Since 1.13.0 (John, 2026-11-26: WTF "should surface every setting in the
-- wrapped addon's settings, and just pass-through the setting to the wrapped
-- addon"), each page asks Dyre's Toolkit 2.17.0's AddSettingsSection for the
-- owner's own rows (`section`, `filter`): they read and write the owner's live
-- settings, as its own page does. The toolkit draws the link above when the
-- owner, or its section, is missing; an older toolkit keeps the link as before.
-- `primer` (John, 2026-11-27: when the AddOn is missing, a box that tells
-- "people what they get if they install it"): the toolkit shows it above the
-- link only while the owner is not loaded. At most 400 characters; the box
-- does not grow, so each stays under 300.
local DDT = {addon = "DyresDebuffTracker", owner = "Dyre's Debuff Tracker", button = "Open Debuff Tracker settings"}
local DDT_PAGES = {
    {title = TRACKER_TITLE, variable = "WTF_MOVED_TRACKER", name = "DoT tracker and damage prediction",
        section = "tracker", what = "The DoT tracker, DoT damage prediction, and the smart curse",
        primer = "Dyre's Debuff Tracker adds the DoT tracker here: your DoTs and time left on every mob. "
            .. "A block on the health bar shows the damage your DoTs will still deal, and DIES when that is "
            .. "enough to kill. Also the smart curse, with its macro and key binding. Install Dyre's Debuff "
            .. "Tracker from CurseForge."},
    {title = DOTS_TITLE, variable = "WTF_MOVED_DOTS", name = "DoT colors, order, and nameplate dots",
        section = "dots", what = "The DoT colors, order, and nameplate DoT dots",
        primer = "Dyre's Debuff Tracker adds the DoT settings here: the color of each DoT on the bars, the "
            .. "order of your DoTs, and DoT dots on enemy nameplates, so you see which mobs still need a DoT. "
            .. "Install Dyre's Debuff Tracker from CurseForge."},
    {title = CONTROL_TITLE, variable = "WTF_MOVED_CONTROL", name = "Control bar, macros, and announcements",
        section = "control",
        primer = "Dyre's Debuff Tracker adds the Control bar here: Fear and Banish timers, a Focus box, "
            .. "Fear timers under nameplates, the \"! Fear\", \"! Banish\", and \"! Seduction\" macros, and "
            .. "messages to your group for Fear, Banish, Enslave Demon, and Howl of Terror. Install Dyre's Debuff "
            .. "Tracker from CurseForge.",
        what = "The Control bar, \"! Fear\", \"! Banish\", \"! Seduction\", and the Fear and Banish announcements"},
}
for _, moved in ipairs(DDT_PAGES) do
    for key, value in pairs(DDT) do
        moved[key] = value
    end
end
local MOVED_PAGES = {
    {title = SHIELD_TITLE, variable = "WTF_MOVED_SHIELD", addon = "DyresShieldsUp", owner = "Dyre's Shields Up",
        name = "Shield display", button = "Open Shield settings", what = "The shield display", section = "shield",
        primer = "Dyre's Shields Up adds the shield display here: a crescent that shows how much your Shadow "
            .. "Ward or your Voidwalker's Sacrifice can still absorb, and any other shield on you. Install "
            .. "Dyre's Shields Up from CurseForge."},
    {title = CHIMES_TITLE, variable = "WTF_MOVED_CHIMES", addon = "DyresBuffReminders",
        owner = "Dyre's Buff Reminders", name = "Chimes", button = "Open Chime settings",
        what = "Chimes", section = "chimes",
        primer = "Dyre's Buff Reminders adds the cooldown chimes here: a sound just before your chosen spells, "
            .. "such as Death Coil, are ready again, so you can act the moment they are, also in combat. "
            .. "Install Dyre's Buff Reminders from CurseForge."},
    -- Every Warlock proc (John, 2026-11-27: "Let's add all the Warlock
    -- procs/alerts and reminders"): no filter. `also`: Dyre's Debuff Tracker's
    -- "cues" (the Demonic Brand pentagram) after it, on the same page.
    {title = PROCS_TITLE, variable = "WTF_MOVED_NIGHTFALL", addon = "DyresBuffReminders",
        owner = "Dyre's Buff Reminders", name = "Procs", button = "Open Proc settings",
        what = "Procs", procKey = "nightfall", section = "procs",
        primer = "Dyre's Buff Reminders adds your procs here: a sound and arcs on screen when Nightfall makes "
            .. "your next Shadow Bolt instant, or when Decimation procs. Install Dyre's Buff Reminders from "
            .. "CurseForge.",
        also = {variable = "WTF_MOVED_CUES", addon = "DyresDebuffTracker", owner = "Dyre's Debuff Tracker",
            section = "cues", name = "Debuff Cues", button = "Open Debuff Tracker settings",
            what = "Debuff Cues",
            primer = "Dyre's Debuff Tracker adds a red pentagram above an enemy's nameplate while your Demonic "
                .. "Brand is on it, so you know when to recast it. Install Dyre's Debuff Tracker from "
                .. "CurseForge."}},
    {title = REMINDERS_TITLE, variable = "WTF_MOVED_REMINDER", addon = "DyresBuffReminders",
        owner = "Dyre's Buff Reminders", name = "Reminders", button = "Open Reminder settings",
        what = "Reminders", section = "reminders",
        primer = "Dyre's Buff Reminders adds your reminders here: an icon when Demon Armor is missing (a click "
            .. "casts it), a warning when you have no demon out, and one when your Voidwalker's Torment is on "
            .. "autocast in a group you don't tank. Install Dyre's Buff Reminders from CurseForge."},
}

-- The Dyre's AddOn that plays a proc with its arcs (1.10.1): the owner of the
-- Toolkit kind "proc:<key>" (Toolkit 2.11 procs), else nil, and Dyre's Buff
-- Reminders' Proc Sounds plays it as before. A feature test, as DBR's
-- ProcOwner: an older Toolkit, or an AddOn that steps aside (for
-- SpellActivationOverlay), makes no claim. No AddOn is named here.
function WTF.ProcOwner(key)
    local toolkit = rawget(_G, "DyresToolkit")
    if type(toolkit) ~= "table" or type(toolkit.PROC_KIND_PREFIX) ~= "string"
            or type(toolkit.KindOwner) ~= "function" then
        return nil
    end
    local owner = toolkit.KindOwner(toolkit.PROC_KIND_PREFIX .. key)
    return type(owner) == "string" and owner ~= "" and owner or nil
end

local function Member(addon)
    local toolkit = rawget(_G, "DyresToolkit")
    if type(toolkit) == "table" and type(toolkit.AddOns) == "function" then
        for _, info in ipairs(toolkit.AddOns()) do
            if type(info) == "table" and info.addon == addon then
                return info
            end
        end
    end
end

-- The title the owner joined Dyre's Toolkit with, else its folder name.
function WTF.ProcOwnerTitle(owner)
    local info = Member(owner)
    return info and type(info.title) == "string" and info.title or owner
end

-- Player words (2026-11-27): what the player sees, not who owns what.
-- "Dyre's Buff Reminders'", "Dyre's Shields Up's".
local function Possessive(name)
    return name .. (name:sub(-1) == "s" and "'" or "'s")
end

local function ProcName(key)
    return (key:gsub("^%l", string.upper))
end

local function ProcOwnerTooltip(key)
    local owner = WTF.ProcOwner(key)
    if not owner then
        return "No AddOn shows " .. ProcName(key) .. " arcs now."
    end
    return "Opens " .. Possessive(WTF.ProcOwnerTitle(owner)) .. " settings for the " .. ProcName(key) .. " arcs and sound."
end

-- The click asks for the owner again: one row for any owner.
local function OpenProcOwner(key)
    local owner = WTF.ProcOwner(key)
    local info = owner and Member(owner)
    if not info or type(info.openSettings) ~= "function" then
        WTF.Report("No Dyre's AddOn shows " .. ProcName(key) .. " arcs now.")
        return
    end
    if InCombatLockdown() then
        WTF.Report("The settings open out of combat.")
        return
    end
    info.openSettings()
end

-- The owner's row: "<proc> arcs and sound", a button that opens the owner's
-- settings. Its tooltip names the owner, again on each owner change.
local function AddProcOwnerRow(layout, moved)
    if type(CreateSettingsButtonInitializer) ~= "function" or type(layout) ~= "table"
            or type(layout.AddInitializer) ~= "function" then
        return nil
    end
    local key = moved.procKey
    local name = ProcName(key) .. " arcs and sound"
    local row = CreateSettingsButtonInitializer(name, "Open settings", function() OpenProcOwner(key) end,
        ProcOwnerTooltip(key), true)
    layout:AddInitializer(row)
    local toolkit = rawget(_G, "DyresToolkit")
    if type(toolkit) == "table" and type(toolkit.OnOwnerChanged) == "function"
            and type(toolkit.PROC_KIND_PREFIX) == "string" then
        toolkit.OnOwnerChanged(toolkit.PROC_KIND_PREFIX .. key, function()
            local data = type(row.GetData) == "function" and row:GetData() or row
            if type(data) == "table" then
                data.tooltip = ProcOwnerTooltip(key)
            end
        end)
    end
    return row
end

local function Missing(moved)
    return "Install " .. moved.owner .. " from CurseForge for " .. moved.what:gsub("^The", "the") .. "."
end

-- The Toolkit's AddSettingsLink options for a moved page.
local function LinkOptions(moved)
    return {addon = moved.addon, name = moved.name, button = moved.button, missing = Missing(moved),
        tooltip = "Opens " .. Possessive(moved.owner) .. " settings for " .. moved.what:gsub("^The", "the") .. "."}
end

-- One row: the Toolkit's link, else (without Dyre's Toolkit 2.3.0) the note only.
local function AddMovedRow(page, layout, moved)
    local link = WTF.toolkit and type(WTF.toolkit.AddSettingsLink) == "function"
        and WTF.toolkit.AddSettingsLink(page, layout, LinkOptions(moved))
    if link then
        return link
    end
    return Notice(page, moved.variable, moved.name .. " (in " .. moved.owner .. ")",
        Missing(moved))
end

local SECTION_HOST = "WarlockToolsForever"

local function HasSections()
    return WTF.toolkit and type(WTF.toolkit.AddSettingsSection) == "function"
end

-- Whether the owner registered the page's section. Owners register by their
-- ADDON_LOADED, before WTF's PLAYER_LOGIN builds this page. Without
-- SettingsSections the toolkit decides alone.
local function SectionRegistered(moved)
    local list = type(WTF.toolkit.SettingsSections) == "function" and WTF.toolkit.SettingsSections(moved.addon)
    if type(list) ~= "table" then
        return true
    end
    for _, key in ipairs(list) do
        if key == moved.section then
            return true
        end
    end
    return false
end

-- Toolkit 2.17.0's primer box (AddSettingsSection's `primer`, and
-- AddSettingsPrimer). An older toolkit ignores the field; WTF passes it only
-- with the function there.
local function HasPrimer()
    return WTF.toolkit and type(WTF.toolkit.AddSettingsPrimer) == "function"
end

-- Sections in parts (SETTINGS_SECTIONS_VERSION 3; John, 2026-11-27: "the
-- top-level disable for each section should be on the top-level MTF panel",
-- and "when the top-level is off, the settings that are controlling a
-- disabled feature should be disabled too"): each owner's top switch
-- ("master") on WTF's top page, the rest on the sub-page, greyed by the owner
-- while that switch is off. With less, every sub-page keeps its whole section.
local function HasParts()
    return HasSections() and (tonumber(WTF.toolkit.SETTINGS_SECTIONS_VERSION) or 0) >= 3
end

-- The owner's rows, else the toolkit's link (both drawn by the toolkit), else
-- nil when it drew nothing.
local function AddMovedSection(page, layout, moved)
    return WTF.toolkit.AddSettingsSection(page, layout, {addon = moved.addon, key = moved.section,
        host = SECTION_HOST, filter = moved.filter, link = LinkOptions(moved),
        primer = HasPrimer() and moved.primer or nil, part = HasParts() and "rest" or nil})
end

-- The owner's top switch on WTF's top page. With the owner missing, or a
-- section with no single top switch, the toolkit adds nothing: the sub-page
-- has the link and the primer. No filter: Dyre's Buff Reminders' "procs"
-- master is the proc engine's switch (John, 2026-11-27: "Add the Procs master
-- switch"), which turns every Warlock proc cue off. Its name is the one the
-- owner gives. The Procs page's second section (Demonic Brand) follows it.
local function AddMovedMaster(page, layout, moved)
    WTF.toolkit.AddSettingsSection(page, layout, {addon = moved.addon, key = moved.section,
        host = SECTION_HOST, part = "master"})
    if moved.also then
        AddMovedMaster(page, layout, moved.also)
    end
end

-- The page's title: the owner's section title, else WTF's word for it.
local function PageTitle(moved)
    local toolkit = WTF.toolkit
    local title = toolkit and type(toolkit.SettingsSectionTitle) == "function" and moved.section
        and toolkit.SettingsSectionTitle(moved.addon, moved.section)
    return type(title) == "string" and title ~= "" and title or moved.title
end

-- Whether an AddOn is loaded (joined the toolkit, or loaded by the client).
local function Loaded(addon)
    if Member(addon) then
        return true
    end
    local isLoaded = type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
    return type(isLoaded) == "function" and isLoaded(addon) == true
end

local function CanShow(row)
    return type(row) == "table" and type(row.AddShownPredicate) == "function"
end

local AddOwnerRows

local function AddMovedPage(parent, moved)
    local page, layout = Settings.RegisterVerticalLayoutSubcategory(parent, PageTitle(moved))
    AddOwnerRows(page, layout, moved)
    -- A second owner's section on the same page (the Procs page: Dyre's Debuff
    -- Tracker's Demonic Brand), with its own link and primer.
    if moved.also and HasSections() then
        if not AddMovedSection(page, layout, moved.also) then
            AddMovedRow(page, layout, moved.also)
        end
    end
end

AddOwnerRows = function(page, layout, moved)
    local key = moved.procKey
    -- The Nightfall page keeps its proc owner rows (below) while Dyre's Buff
    -- Reminders has no "procs" section: a plain link could not follow the owner.
    if HasSections() and moved.section and (not key or SectionRegistered(moved)) then
        if AddMovedSection(page, layout, moved) then
            return
        end
        AddMovedRow(page, layout, moved)
        return
    end
    if not key or not (WTF.toolkit and type(WTF.toolkit.AddSettingsLink) == "function") then
        AddMovedRow(page, layout, moved)
        return
    end
    -- The proc owner rows draw their own primer while Dyre's Buff Reminders is
    -- missing, shown only while no AddOn plays Nightfall with its arcs.
    if HasPrimer() and moved.primer and not Loaded(moved.addon) then
        local primer = WTF.toolkit.AddSettingsPrimer(page, layout, moved.primer)
        if CanShow(primer) then
            primer:AddShownPredicate(function() return WTF.ProcOwner(key) == nil end)
        end
    end
    -- A proc (Nightfall): two rows, one shown. With no owner, the old row to
    -- Dyre's Buff Reminders; with one, the owner's row. The owner is asked
    -- each time the page draws, since it claims at its PLAYER_LOGIN, which can
    -- come after this page is built. Without shown predicates, only the row
    -- for the owner at build time.
    local function Unowned() return WTF.ProcOwner(key) == nil end
    local function Owned() return WTF.ProcOwner(key) ~= nil end
    if Owned() then
        local row = AddProcOwnerRow(layout, moved)
        if not row then
            AddMovedRow(page, layout, moved)
        elseif CanShow(row) then
            row:AddShownPredicate(Owned)
            local old = AddMovedRow(page, layout, moved)
            if CanShow(old) then
                old:AddShownPredicate(Unowned)
            end
        end
        return
    end
    local old = AddMovedRow(page, layout, moved)
    if CanShow(old) then
        old:AddShownPredicate(Unowned)
        local row = AddProcOwnerRow(layout, moved)
        if CanShow(row) then
            row:AddShownPredicate(Owned)
        end
    end
end

local function AddShardPage(parent)
    local page = Settings.RegisterVerticalLayoutSubcategory(parent, SHARDS_TITLE)
    local auto = Proxy(page, "WTF_SHARDS_AUTO_LIMIT", Settings.VarType.Boolean,
        "Match soul bag size", true,
        function() return WTF.db.shards.autoLimit end,
        function(value)
            local shards = WTF.db.shards
            -- Turning the soul bag match off starts the manual limit where it was.
            if shards.autoLimit and value == false then
                shards.limit = WTF.SanitizeShardLimit(WTF.GetShardLimit())
            end
            shards.autoLimit = value == true
            Settings.NotifyUpdate("WTF_SHARDS_LIMIT")
            RefreshShardCounter()
        end)
    local autoInitializer = Settings.CreateCheckbox(page, auto,
        "Keep as many Soul Shards as your soul bags hold, or 6 without a soul bag.")

    -- Shows the limit in effect, including the soul bag size while matching it.
    local limit = Proxy(page, "WTF_SHARDS_LIMIT", Settings.VarType.Number,
        "Shard limit", WTF.DEFAULT_SHARD_LIMIT,
        function() return (WTF.GetShardLimit()) end,
        function(value)
            if not WTF.db.shards.autoLimit then
                WTF.db.shards.limit = WTF.SanitizeShardLimit(value)
            end
            RefreshShardCounter()
        end)
    local options = Settings.CreateSliderOptions(WTF.SHARD_LIMIT_MIN, WTF.SHARD_LIMIT_MAX, 1)
    if type(MinimalSliderWithSteppersMixin) == "table" and type(options.SetLabelFormatter) == "function" then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    end
    local limitInitializer = Settings.CreateSlider(page, limit, options,
        "How many Soul Shards to keep in your bags.")
    DefaultTick(limitInitializer, WTF.SHARD_LIMIT_MIN, WTF.SHARD_LIMIT_MAX, WTF.DEFAULT_SHARD_LIMIT)
    limitInitializer:SetParentInitializer(autoInitializer, function()
        return not WTF.db.shards.autoLimit
    end)

    Flag(page, "WTF_SHARDS_REPORT", "Report deletions in chat", "shards", "report", true,
        "Print one chat line for each Soul Shard WTF deletes.")
    local counterInitializer = Flag(page, "WTF_SHARDS_COUNTER", "Show the shard counter", "shards", "counter",
        true, "A Soul Shard icon with your shard count: red when low, green at your limit.",
        RefreshShardCounter)
    local low = Proxy(page, "WTF_SHARDS_COUNTER_LOW", Settings.VarType.Number, "Low shard warning",
        WTF.DEFAULT_SHARD_LOW,
        function() return WTF.db.shards.counterLow end,
        function(value)
            WTF.db.shards.counterLow = WTF.SanitizeShardLow(value)
            RefreshShardCounter()
        end)
    local lowOptions = Settings.CreateSliderOptions(WTF.SHARD_LOW_MIN, WTF.SHARD_LOW_MAX, 1)
    if type(MinimalSliderWithSteppersMixin) == "table" and type(lowOptions.SetLabelFormatter) == "function" then
        lowOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    end
    local lowInitializer = Settings.CreateSlider(page, low, lowOptions,
        "The counter turns red at this many Soul Shards or fewer.")
    DefaultTick(lowInitializer, WTF.SHARD_LOW_MIN, WTF.SHARD_LOW_MAX, WTF.DEFAULT_SHARD_LOW)
    lowInitializer:SetParentInitializer(counterInitializer, function() return WTF.db.shards.counter end)
    local counterScale = Proxy(page, "WTF_SHARDS_COUNTER_SCALE", Settings.VarType.Number, "Shard counter size",
        WTF.DEFAULT_FRAME_SCALE,
        function() return WTF.db.shards.counterScale end,
        function(value) WTF.SetShardCounterScale(value) end)
    local counterScaleInitializer = Settings.CreateSlider(page, counterScale,
        SliderOptions(WTF.FRAME_SCALE_MIN, WTF.FRAME_SCALE_MAX, WTF.FRAME_SCALE_STEP, true),
        "How big the shard counter is, in percent.")
    DefaultTick(counterScaleInitializer, WTF.FRAME_SCALE_MIN, WTF.FRAME_SCALE_MAX, WTF.DEFAULT_FRAME_SCALE)
    counterScaleInitializer:SetParentInitializer(counterInitializer, function() return WTF.db.shards.counter end)
end

-- Greyed while Stones (the top page's switch) is off (1.13.0; John: "when the
-- top-level is off, the settings that are controlling a disabled feature
-- should be disabled too"). Stones gates the bar and the reminders; the stone
-- macros work without it, so their row stays.
local function StonesOn()
    return WTF.db.stones.enabled == true
end

local function GreyUnless(initializer, predicate)
    if type(initializer) == "table" and type(initializer.AddModifyPredicate) == "function" then
        initializer:AddModifyPredicate(predicate)
    end
    return initializer
end

local function AddStonesPage(parent)
    local page = Settings.RegisterVerticalLayoutSubcategory(parent, STONES_TITLE)
    local shownInitializer = GreyUnless(Flag(page, "WTF_STONES_SHOWN", "Show the Stones bar", "stones", "shown",
        true, "The bar with the Soulstone and Healthstone buttons.",
        RefreshStones), StonesOn)
    local scale = Proxy(page, "WTF_STONES_SCALE", Settings.VarType.Number, "Stones bar size",
        WTF.DEFAULT_FRAME_SCALE,
        function() return WTF.db.stones.scale end,
        function(value) WTF.SetStonesScale(value) end)
    local scaleInitializer = Settings.CreateSlider(page, scale,
        SliderOptions(WTF.FRAME_SCALE_MIN, WTF.FRAME_SCALE_MAX, WTF.FRAME_SCALE_STEP, true),
        "How big the Stones bar is, in percent.")
    DefaultTick(scaleInitializer, WTF.FRAME_SCALE_MIN, WTF.FRAME_SCALE_MAX, WTF.DEFAULT_FRAME_SCALE)
    scaleInitializer:SetParentInitializer(shownInitializer, function() return WTF.db.stones.shown end)
    GreyUnless(scaleInitializer, StonesOn)
    Flag(page, "WTF_STONES_MACROS", "Keep stone macros", "stones", "macros", true,
        "Keep the \"! Healthstone\" and \"! Soulstone\" macros for your action bars: left-click uses your "
            .. "best stone, right-click creates one. Turning this off deletes them.",
        function() WTF.ApplyStoneMacros() end)
    ComingSoon(page, "WTF_STONES_SPELLSTONE", "Spellstone button",
        "A Spellstone button and macro: left-click uses it, right-click creates one.")
    ComingSoon(page, "WTF_STONES_FIRESTONE", "Firestone button",
        "A Firestone button and macro: left-click uses it, right-click creates one.")
    GreyUnless(Flag(page, "WTF_STONES_REMIND_SOULSTONE", "Soulstone reminders", "stones", "remindSoulstone", true,
        "Say in chat when your Soulstone ends or none is up."), StonesOn)
    GreyUnless(Flag(page, "WTF_STONES_REMIND_HEALTHSTONE", "Healthstone reminders", "stones", "remindHealthstone",
        true, "Say in chat when you carry no Healthstone."), StonesOn)
    ComingSoon(page, "WTF_STONES_REMIND_SPELLSTONE", "Spellstone reminders",
        "Say in chat when you carry no Spellstone.")
    ComingSoon(page, "WTF_STONES_REMIND_FIRESTONE", "Firestone reminders",
        "Say in chat when you carry no Firestone.")
end

-- Announce page --------------------------------------------------------------

local ANNOUNCE_ROWS = {
    {switch = "summonGroup", label = "Ritual of Summoning: tell the group"},
    {switch = "summonWhisper", label = "Ritual of Summoning: whisper the target"},
    {switch = "soulstoneGroup", label = "Soulstone: tell the group"},
    {switch = "soulstoneWhisper", label = "Soulstone: whisper the target"},
    {switch = "healthstoneWhisper", label = "Healthstone trade: whisper the player"},
    {switch = "healthstoneEmote", label = "Healthstone created: emote (starts with your name; once a minute)"},
    {switch = "soulstoneEmote", label = "Soulstone created: emote (starts with your name; once a minute)"},
}
local PAGE_LEFT = 16
local ROW_GAP = 10
local EDIT_INDENT = 8
local EDIT_WIDTH = 560
local PAGE_BOTTOM = 16
local SCROLL_BAR_SPACE = 28
-- Three lines show the longest default text whole (author's request).
local EDIT_LINES = 3
local EDIT_LINE_HEIGHT = 14
local EDIT_PADDING = 6
local EDIT_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3},
}

local function Text(parent, font, text)
    local label = parent:CreateFontString(nil, "ARTWORK", font)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

-- A control on the Announce page, greyed while Announce is off.
local function SetUsable(control, usable)
    if type(control.SetEnabled) == "function" then
        control:SetEnabled(usable)
    end
    if control.label and type(control.label.SetTextColor) == "function" then
        if usable then
            control.label:SetTextColor(1, 1, 1)
        else
            control.label:SetTextColor(0.5, 0.5, 0.5)
        end
    end
end

local function CheckButton(parent, template, label)
    local button = CreateFrame("CheckButton", nil, parent, template)
    button.label = Text(button, "GameFontHighlight", label)
    button.label:SetPoint("LEFT", button, "RIGHT", 4, 0)
    return button
end

local function CreateAnnouncePage()
    local page = CreateFrame("Frame")
    page.rows, page.channels = {}, {}
    -- The rows are taller than the Settings panel, so they scroll.
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLL_BAR_SPACE, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(EDIT_WIDTH + 2 * PAGE_LEFT, 1)
    scroll:SetScrollChild(content)
    page.scroll, page.content = scroll, content
    local title = Text(content, "GameFontHighlightHuge", ANNOUNCE_TITLE)
    title:SetPoint("TOPLEFT", PAGE_LEFT, -16)
    local help = Text(content, "GameFontHighlightSmall",
        "%T is the target's full name and %Z your zone. Press Enter to keep an edit, Escape to undo it. "
            .. "Nothing is sent for yourself or for a cast that fails. The Fear and Banish announcements are on "
            .. "the Control page, in Dyre's Debuff Tracker.")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    help:SetWidth(EDIT_WIDTH)

    local channelLabel = Text(content, "GameFontNormal", "Group messages go to")
    channelLabel:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -16)
    local previous = channelLabel
    for _, choice in ipairs({{value = "group", label = "Raid or party (nothing when alone)"},
        {value = "say", label = "Say (the game may block it outdoors)"}}) do
        local radio = CheckButton(content, "UIRadioButtonTemplate", choice.label)
        radio:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
        radio.value = choice.value
        radio:SetScript("OnClick", function(self)
            WTF.db.announce.channel = self.value
            page:OnRefresh()
        end)
        page.channels[#page.channels + 1] = radio
        previous = radio
    end

    for index, row in ipairs(ANNOUNCE_ROWS) do
        local check = CheckButton(content, "UICheckButtonTemplate", row.label)
        if index == 1 then
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -18)
        else
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", -EDIT_INDENT, -ROW_GAP)
        end
        check:SetScript("OnClick", function(self)
            WTF.db.announce[row.switch] = self:GetChecked() == true
        end)
        -- A wrapping box: messages are one chat line, so Enter keeps the
        -- edit instead of starting a new line.
        local box = CreateFrame("Frame", nil, content, "BackdropTemplate")
        box:SetSize(EDIT_WIDTH, EDIT_LINES * EDIT_LINE_HEIGHT + 2 * EDIT_PADDING)
        box:SetPoint("TOPLEFT", check, "BOTTOMLEFT", EDIT_INDENT, -2)
        box:SetBackdrop(EDIT_BACKDROP)
        box:SetBackdropColor(0, 0, 0, 0.6)
        box:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        local edit = CreateFrame("EditBox", nil, box)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(EDIT_WIDTH - 2 * EDIT_PADDING)
        edit:SetPoint("TOPLEFT", EDIT_PADDING, -EDIT_PADDING)
        edit:SetAutoFocus(false)
        edit:SetMaxBytes(WTF.ANNOUNCE_MAX_LENGTH + 1)
        box:EnableMouse(true)
        box:SetScript("OnMouseDown", function() edit:SetFocus() end)
        local key = row.switch .. "Text"
        local function Commit(self)
            local text = self:GetText():gsub("[\r\n]+", " ")
            WTF.db.announce[key] = WTF.SanitizeAnnouncement(text, WTF.ANNOUNCE_DEFAULTS[key])
            self:SetText(WTF.db.announce[key])
        end
        edit:SetScript("OnEnterPressed", function(self)
            Commit(self)
            self:ClearFocus()
        end)
        edit:SetScript("OnEditFocusLost", Commit)
        edit:SetScript("OnEscapePressed", function(self)
            self:SetText(WTF.db.announce[key])
            self:ClearFocus()
        end)
        page.rows[#page.rows + 1] = {check = check, edit = edit, switch = row.switch, key = key}
        previous = box
    end
    local last = previous

    -- The scroll range covers the rows once they are laid out.
    local function FitContent()
        local top, bottom = content:GetTop(), last:GetBottom()
        if type(top) == "number" and type(bottom) == "number" then
            content:SetHeight(top - bottom + PAGE_BOTTOM)
        end
    end

    function page:OnRefresh()
        FitContent()
        local settings = WTF.db.announce
        -- The Announce switch is on WTF's top page; this page reads it as it shows.
        local usable = settings.enabled == true
        for _, radio in ipairs(self.channels) do
            radio:SetChecked(settings.channel == radio.value)
            SetUsable(radio, usable)
        end
        for _, row in ipairs(self.rows) do
            row.check:SetChecked(settings[row.switch])
            row.edit:SetText(settings[row.key])
            row.edit:SetCursorPosition(0)
            SetUsable(row.check, usable)
            SetUsable(row.edit, usable)
        end
    end

    -- The Settings panel's Defaults button restores this page only.
    function page:OnDefault()
        local settings = WTF.db.announce
        settings.channel = "group"
        for _, row in ipairs(self.rows) do
            settings[row.switch] = true
            settings[row.key] = WTF.ANNOUNCE_DEFAULTS[row.key]
        end
        self:OnRefresh()
    end

    page:SetScript("OnShow", page.OnRefresh)
    return page
end

function WTF.InitializeOptions()
    if not HasSettingsAPI() then
        return
    end
    -- With Dyre's Toolkit, WTF's page sits under its "Dyre's AddOns" home and
    -- WTF's own pages under that; else WTF's page is top level.
    local home, homeLayout
    if WTF.toolkit then
        home, homeLayout = WTF.toolkit.RegisterSettingsCategory(TITLE)
    end
    category = home or Settings.RegisterVerticalLayoutCategory(TITLE)
    Flag(category, "WTF_SHARDS_ENABLED", "Soul Shard management", "shards", "enabled", true,
        "Delete Soul Shards that Drain Soul creates above your limit. Shards you move into your bags are never deleted.")
    Flag(category, "WTF_STONES_ENABLED", "Stones", "stones", "enabled", true,
        "A bar with Soulstone and Healthstone buttons: left-click uses one, right-click creates one.",
        RefreshStones)
    Flag(category, "WTF_ANNOUNCE_ENABLED", "Announce", "announce", "enabled", true,
        "Tell your group and whisper the target when your Ritual of Summoning or a Soulstone use succeeds, "
            .. "and whisper the player when a Healthstone trade opens.")
    -- With Dyre's Toolkit, its own page has the unlock switch and the grid, for
    -- every Dyre's AddOn (author-approved: no second switch here); /wtf unlock
    -- and /wtf lock still work.
    if not WTF.toolkit then
        local unlocked = Proxy(category, "WTF_UNLOCKED", Settings.VarType.Boolean, "Unlock frames to move them",
            false,
            function() return not WTF.db.locked end,
            function(value)
                if value == true then
                    WTF.Unlock()
                else
                    WTF.Lock()
                end
            end)
        Settings.CreateCheckbox(category, unlocked,
            "Outline the Stones bar and the shard counter, so you can drag them.")
        local grid = Proxy(category, "WTF_GRID", Settings.VarType.Boolean, "Show a grid while unlocked", true,
            function() return WTF.db.grid end,
            function(value)
                WTF.db.grid = value == true
                WTF.RefreshGrid()
            end)
        Settings.CreateCheckbox(category, grid, "While frames are unlocked, draw a faint grid over the screen "
            .. "with the center lines in red, so you can line frames up.")
    end
    -- After WTF's own switches, each moved section's top switch, in the
    -- sub-pages' order.
    if home and homeLayout and HasParts() then
        for _, list in ipairs({DDT_PAGES, MOVED_PAGES}) do
            for _, moved in ipairs(list) do
                AddMovedMaster(category, homeLayout, moved)
            end
        end
    end
    AddShardPage(category)
    AddStonesPage(category)
    for _, moved in ipairs(DDT_PAGES) do
        AddMovedPage(category, moved)
    end
    local announcePage = CreateAnnouncePage()
    WTF.announcePage = announcePage
    Settings.RegisterCanvasLayoutSubcategory(category, announcePage, ANNOUNCE_TITLE)
    for _, moved in ipairs(MOVED_PAGES) do
        AddMovedPage(category, moved)
    end
    if not home then
        Settings.RegisterAddOnCategory(category)
    end
end

function WTF.OpenSettings()
    if not category then
        WTF.Report(UNAVAILABLE)
        return
    end
    -- The toolkit opens it out of combat only, and says so.
    if WTF.toolkit then
        WTF.toolkit.OpenSettings(category)
        return
    end
    Settings.OpenToCategory(category:GetID())
end
