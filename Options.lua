local _, WTF = ...

-- The AddOn settings: a main page with one switch per module, and a subpage
-- per module for its details. Shards and Stones use Blizzard's vertical layout
-- with proxy settings that read and write WarlockToolsForeverDB directly;
-- Announce needs text fields and DoTs rows you drag to reorder, so they are
-- canvas pages.
local TITLE = "Warlock Tools Forever"
local SHARDS_TITLE = "Soul Shards"
local STONES_TITLE = "Stones"
local ANNOUNCE_TITLE = "Announce"
local TRACKER_TITLE = "DoT Tracker"
local DOTS_TITLE = "DoTs"
local ALERTS_TITLE = "Alerts"
local SHIELD_TITLE = "Shield"
local CHIMES_TITLE = "Cooldown Chimes"
local REMINDER_TITLE = "Demon Armor"
local CONTROL_TITLE = "Control"
local UNAVAILABLE = "The AddOn settings page is unavailable on this client. Use /wtf shards for status."
local GOLD = {1, 0.82, 0}

local REQUIRED_SETTINGS = {
    "RegisterVerticalLayoutCategory", "RegisterVerticalLayoutSubcategory", "RegisterCanvasLayoutSubcategory",
    "RegisterProxySetting", "RegisterAddOnCategory", "CreateCheckbox", "CreateSlider", "CreateSliderOptions",
    "CreateColorSwatch", "CreateDropdown", "CreateControlTextContainer",
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

local function SliderOptions(minValue, maxValue, step, percent)
    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    if type(MinimalSliderWithSteppersMixin) == "table" and type(options.SetLabelFormatter) == "function" then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, percent and Percent or nil)
    end
    return options
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

-- Pages for the features that moved out of WTF in 1.3.0 (author-approved):
-- each links to the AddOn that has it now (Dyre's Toolkit's AddSettingsLink,
-- greyed while that AddOn is missing; a click then says what to install),
-- instead of mirroring its settings.
local MOVED_PAGES = {
    {title = SHIELD_TITLE, variable = "WTF_MOVED_SHIELD", addon = "DyresShieldsUp", owner = "Dyre's Shields Up",
        name = "Shield display", button = "Open Shield settings", what = "The shield display"},
    {title = CHIMES_TITLE, variable = "WTF_MOVED_CHIMES", addon = "DyresBuffReminders",
        owner = "Dyre's Buff Reminders", name = "Cooldown chimes", button = "Open Chime settings",
        what = "The cooldown chimes"},
    {title = ALERTS_TITLE, variable = "WTF_MOVED_NIGHTFALL", addon = "DyresBuffReminders",
        owner = "Dyre's Buff Reminders", name = "Nightfall sound", button = "Open Proc settings",
        what = "The Nightfall sound (Proc Sounds)"},
    {title = REMINDER_TITLE, variable = "WTF_MOVED_REMINDER", addon = "DyresBuffReminders",
        owner = "Dyre's Buff Reminders", name = "Demon Armor reminder", button = "Open Reminder settings",
        what = "The Demon Armor reminder"},
}

local function AddMovedPage(parent, moved)
    local page, layout = Settings.RegisterVerticalLayoutSubcategory(parent, moved.title)
    local missing = "Install " .. moved.owner .. " from CurseForge for " .. moved.what:gsub("^The", "the") .. "."
    local link = WTF.toolkit and type(WTF.toolkit.AddSettingsLink) == "function"
        and WTF.toolkit.AddSettingsLink(page, layout, {addon = moved.addon, name = moved.name,
            button = moved.button, missing = missing,
            tooltip = moved.what .. " moved to " .. moved.owner .. " in WTF 1.3.0. This opens its settings."})
    if not link then
        -- Without Dyre's Toolkit 2.3.0 or later: the note only.
        Notice(page, moved.variable, moved.name .. " (moved to " .. moved.owner .. ")",
            moved.what .. " moved to " .. moved.owner .. " in WTF 1.3.0. " .. missing)
    end
end

local function RefreshControl()
    WTF.RefreshControl()
end

local function AddControlPage(parent)
    local page = Settings.RegisterVerticalLayoutSubcategory(parent, CONTROL_TITLE)
    local function MarkerChoices()
        local container = Settings.CreateControlTextContainer()
        for _, marker in ipairs(WTF.RAID_MARKERS) do
            container:Add(marker.index, marker.label)
        end
        return container:GetData()
    end
    for _, spell in ipairs(WTF.CONTROL_SPELLS) do
        if spell.marker then
            local marker = Proxy(page, "WTF_CONTROL_MARKER_" .. spell.key:upper(), Settings.VarType.Number,
                spell.label .. " marker", spell.marker,
                function() return WTF.db.control.markers[spell.key] end,
                function(value)
                    for _, choice in ipairs(WTF.RAID_MARKERS) do
                        if choice.index == value then
                            WTF.db.control.markers[spell.key] = value
                        end
                    end
                    -- The macros and row clicks carry it; both change out of combat.
                    WTF.ApplyControlMacros()
                    WTF.RefreshControl()
                end)
            Settings.CreateDropdown(page, marker, MarkerChoices, "The raid marker for a mob you "
                .. spell.label .. ": the \"! " .. spell.label .. "\" macro and the row click mark it, also in "
                .. "combat. Banish from its plain spell button gets none: the game lets only your own key press "
                .. "or click set markers. After a row click, %M puts it in the message. In a raid only the leader "
                .. "and assistants mark.")
        end
    end
    Flag(page, "WTF_CONTROL_MACROS", "Keep control macros", "control", "macros", true,
        "Keep \"! Fear\", \"! Banish\", and \"! Seduction\" in your character macros for your action bars, "
            .. "each once you know its spell. \"! Fear\" Fears your focus (Shift-press it to focus the mob under your mouse, or your target, first), else the mob under your mouse (a feared mob's nameplate "
            .. "as its timer runs out), else your target. The others focus the hostile mob under your mouse (or "
            .. "your target, out of combat) and cast on your focus. \"! Seduction\" appears once your Succubus "
            .. "or Incubus has learned Seduction from its Grimoire, and casts only while one is your pet. Turning "
            .. "this off deletes them.", function() WTF.ApplyControlMacros() end)
    Flag(page, "WTF_CONTROL_PLATE_TIMERS", "Fear timers on nameplates", "control", "plateTimers", true,
        "A thin bar under each feared mob's nameplate that drains with your Fear's time left, so you see which "
            .. "one is about to break; click its nameplate to target it.", RefreshControl)
    local scale = Proxy(page, "WTF_CONTROL_SCALE", Settings.VarType.Number, "Bar size",
        WTF.DEFAULT_CONTROL_SCALE,
        function() return WTF.db.control.scale end,
        function(value)
            WTF.db.control.scale = WTF.SanitizeControlScale(value)
            RefreshControl()
        end)
    Settings.CreateSlider(page, scale,
        SliderOptions(WTF.CONTROL_SCALE_MIN, WTF.CONTROL_SCALE_MAX, WTF.CONTROL_SCALE_STEP, true),
        "How big the control bar is, in percent. A change in combat applies when combat ends.")
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
        "How many Soul Shards to keep in your bags. Turn off Match soul bag size to change it.")
    limitInitializer:SetParentInitializer(autoInitializer, function()
        return not WTF.db.shards.autoLimit
    end)

    Flag(page, "WTF_SHARDS_REPORT", "Report deletions in chat", "shards", "report", true,
        "Print one chat line for each Soul Shard WTF deletes.")
    local counterInitializer = Flag(page, "WTF_SHARDS_COUNTER", "Show the shard counter", "shards", "counter",
        true, "A Soul Shard icon with your shard count: red when low, green at your limit. Drag it to move it.",
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
    lowInitializer:SetParentInitializer(counterInitializer, function() return WTF.db.shards.counter end)
end

local function AddStonesPage(parent)
    local page = Settings.RegisterVerticalLayoutSubcategory(parent, STONES_TITLE)
    Flag(page, "WTF_STONES_SHOWN", "Show the Stones bar", "stones", "shown", true,
        "The bar with the Soulstone and Healthstone buttons. Changes in combat apply when combat ends.",
        RefreshStones)
    Flag(page, "WTF_STONES_MACROS", "Keep stone macros", "stones", "macros", true,
        "Keep \"! Healthstone\" and \"! Soulstone\" in your character macros for your action bars: "
            .. "left-click uses your best stone, right-click creates one. Turning this off deletes them.",
        function() WTF.ApplyStoneMacros() end)
    ComingSoon(page, "WTF_STONES_SPELLSTONE", "Spellstone button",
        "A Spellstone button and macro: left-click uses it, right-click creates one.")
    ComingSoon(page, "WTF_STONES_FIRESTONE", "Firestone button",
        "A Firestone button and macro: left-click uses it, right-click creates one.")
    Flag(page, "WTF_STONES_REMIND_SOULSTONE", "Soulstone reminders", "stones", "remindSoulstone", true,
        "Say in chat when your Soulstone ends, and when none is up: on entering an instance, joining a group, "
            .. "or after a fight, at most every 10 minutes.")
    Flag(page, "WTF_STONES_REMIND_HEALTHSTONE", "Healthstone reminders", "stones", "remindHealthstone", true,
        "Say in chat when you carry no Healthstone, at the same times.")
    ComingSoon(page, "WTF_STONES_REMIND_SPELLSTONE", "Spellstone reminders",
        "Say in chat when you carry no Spellstone, at the same times.")
    ComingSoon(page, "WTF_STONES_REMIND_FIRESTONE", "Firestone reminders",
        "Say in chat when you carry no Firestone, at the same times.")
end

local function RefreshTracker()
    if WTF.RefreshTracker then
        WTF.RefreshTracker()
    end
end

local function RefreshPlateDots()
    if WTF.RefreshPlateDots then
        WTF.RefreshPlateDots()
    end
end

-- A gold mark on a slider's track at its default value (author-approved), as a
-- point of reference. Blizzard's settings slider has none, and the panel
-- reuses its slider frames for other settings, so the mark is drawn when this
-- setting's frame is set up and hidden whenever Blizzard releases the frame.
local TICK_WIDTH = 2
local TICK_HEIGHT = 12

local function PlaceTick(slider)
    local tick = slider.wtfDefaultTick
    local info = tick.info
    local thumb = slider:GetThumbTexture()
    local half = thumb and thumb:GetWidth() / 2 or 0
    local fraction = (info.default - info.minValue) / (info.maxValue - info.minValue)
    tick:ClearAllPoints()
    tick:SetPoint("CENTER", slider, "LEFT", half + fraction * (slider:GetWidth() - 2 * half), 0)
end

local function AddDefaultTick(initializer, minValue, maxValue, default)
    local baseInitFrame = initializer.InitFrame
    if type(baseInitFrame) ~= "function" then
        return
    end
    initializer.InitFrame = function(self, frame)
        baseInitFrame(self, frame)
        local slider = frame.SliderWithSteppers and frame.SliderWithSteppers.Slider
        if not slider then
            return
        end
        local tick = slider.wtfDefaultTick
        if not tick then
            tick = slider:CreateTexture(nil, "BORDER")
            tick:SetSize(TICK_WIDTH, TICK_HEIGHT)
            tick:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
            slider.wtfDefaultTick = tick
            slider:HookScript("OnSizeChanged", function()
                if tick:IsShown() then
                    PlaceTick(slider)
                end
            end)
            hooksecurefunc(frame, "Release", function()
                tick:Hide()
            end)
        end
        tick.info = {minValue = minValue, maxValue = maxValue, default = default}
        PlaceTick(slider)
        tick:Show()
    end
end

-- The tracker's sizes for one theme (Core's TRACKER_SIZE_SPECS), shown only
-- while that theme is chosen: the settings list checks shown predicates again
-- on each setting change (pinned Blizzard_SettingsPanel.lua:788,
-- Blizzard_Settings.lua:96). A change rebuilds the rows, out of combat.
local function AddTrackerSizes(page, theme)
    local function ShowFor(initializer)
        if type(initializer.AddShownPredicate) == "function" then
            initializer:AddShownPredicate(function() return WTF.db.tracker.theme == theme end)
        end
    end
    local prefix = "WTF_TRACKER_" .. theme:upper() .. "_"
    for _, spec in ipairs(WTF.TRACKER_SIZE_SPECS[theme]) do
        local setting = Proxy(page, prefix .. spec.key:upper(), Settings.VarType.Number, spec.label, spec.default,
            function() return WTF.db.tracker.sizes[theme][spec.key] end,
            function(value) WTF.SetTrackerSize(theme, spec.key, value) end)
        local options = Settings.CreateSliderOptions(spec.min, spec.max, spec.step)
        if type(MinimalSliderWithSteppersMixin) == "table" and type(options.SetLabelFormatter) == "function" then
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, spec.percent
                and function(value) return string.format("%d%%", value) end or nil)
        end
        local initializer = Settings.CreateSlider(page, setting, options,
            (spec.tooltip or ("The DoT tracker's " .. spec.label:lower() .. " in the "
                .. (theme == "bars" and "Bars" or "Compact") .. " theme."))
                .. " A change in combat applies when combat ends.")
        AddDefaultTick(initializer, spec.min, spec.max, spec.default)
        ShowFor(initializer)
    end
    local position = Proxy(page, prefix .. "NAMEPOSITION", Settings.VarType.String, "Name position",
        WTF.TRACKER_NAME_POSITIONS[theme][1].key,
        function() return WTF.db.tracker.sizes[theme].namePosition end,
        function(value) WTF.SetTrackerSize(theme, "namePosition", value) end)
    ShowFor(Settings.CreateDropdown(page, position, function()
        local container = Settings.CreateControlTextContainer()
        for _, choice in ipairs(WTF.TRACKER_NAME_POSITIONS[theme]) do
            container:Add(choice.key, choice.label)
        end
        return container:GetData()
    end, "Where the mob's name sits in each row."))
end

-- A section heading, as Blizzard's Controls page adds them
-- (Blizzard_SettingControls.lua: CreateSettingsListSectionHeaderInitializer).
local function Heading(layout, name, tooltip)
    if type(CreateSettingsListSectionHeaderInitializer) == "function" and type(layout) == "table"
            and type(layout.AddInitializer) == "function" then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name, tooltip))
    end
end

-- A panel's own settings (author): its color, then its opacity.
local function AddPanelSection(page, layout, panel, colors)
    Heading(layout, panel.heading, "Settings for the DoT tracker's " .. panel.name .. " only.")
    local color = Proxy(page, "WTF_PANEL_COLOR_" .. panel.key:upper(), Settings.VarType.String, colors.label,
        colors.color,
        function() return WTF.db.tracker.panelColors[panel.key] end,
        function(value)
            WTF.db.tracker.panelColors[panel.key] = WTF.SanitizeColor(value, colors.color)
            if WTF.ApplyPanelColors then
                WTF.ApplyPanelColors()
            end
        end)
    Settings.CreateColorSwatch(page, color, panel.key == "list"
        and "The row border and health fill of the other mobs' rows. It changes at once, also in combat."
        or "The outline and health fill of the " .. panel.name .. ". It changes at once, also in combat.")
    local setting = Proxy(page, "WTF_TRACKER_OPACITY_" .. panel.key:upper(), Settings.VarType.Number,
        panel.label, WTF.DEFAULT_PANEL_OPACITY,
        function() return WTF.db.tracker.panelOpacity[panel.key] end,
        function(value) WTF.SetTrackerPanelOpacity(panel.key, value) end)
    local initializer = Settings.CreateSlider(page, setting,
        SliderOptions(WTF.PANEL_OPACITY_MIN, WTF.PANEL_OPACITY_MAX, 5, true),
        "How solid the " .. panel.name .. " is, rows and all, in percent. It changes at once, also in combat.")
    AddDefaultTick(initializer, WTF.PANEL_OPACITY_MIN, WTF.PANEL_OPACITY_MAX, WTF.DEFAULT_PANEL_OPACITY)
end

-- Sections (author): General (what every panel shares) first, then one per
-- panel: Target, Focus, and Others.
local function AddTrackerPage(parent)
    local page, layout = Settings.RegisterVerticalLayoutSubcategory(parent, TRACKER_TITLE)
    Heading(layout, "General", "Settings that every DoT tracker panel shares, and the nameplate dots.")
    local theme = Proxy(page, "WTF_TRACKER_THEME", Settings.VarType.String, "Theme", "bars",
        function() return WTF.db.tracker.theme end,
        function(value) WTF.SetTrackerTheme(value) end)
    Settings.CreateDropdown(page, theme, function()
        local container = Settings.CreateControlTextContainer()
        container:Add("compact", "Compact")
        container:Add("bars", "Bars")
        return container:GetData()
    end, "Compact: a row per mob with an icon per spell. Bars: a block per mob with a bar per spell you know, "
        .. "draining as its time runs out. A change in combat applies when combat ends.")
    local dotsInitializer = Flag(page, "WTF_TRACKER_PLATE_DOTS", "Show DoT dots on nameplates", "tracker",
        "plateDots", false,
        "In combat, a bubble above each hostile nameplate with a dot per DoT you know: colored while it is up, "
            .. "grey while it is missing. Needs at least one DoT you know. The DoTs page chooses the dots.",
        RefreshPlateDots)
    if type(dotsInitializer.AddModifyPredicate) == "function" then
        dotsInitializer:AddModifyPredicate(function() return WTF.HasTrackableDots() end)
    end
    local offset = Proxy(page, "WTF_TRACKER_PLATE_DOTS_OFFSET", Settings.VarType.Number,
        "Dot height above nameplates", WTF.DEFAULT_PLATE_DOTS_OFFSET,
        function() return WTF.db.tracker.plateDotsOffset end,
        function(value)
            WTF.db.tracker.plateDotsOffset = WTF.SanitizePlateDotsOffset(value)
            RefreshPlateDots()
        end)
    local offsetInitializer = Settings.CreateSlider(page, offset,
        SliderOptions(WTF.PLATE_DOTS_OFFSET_MIN, WTF.PLATE_DOTS_OFFSET_MAX, 1),
        "How far above the nameplate the dots sit, to clear other nameplate AddOns.")
    offsetInitializer:SetParentInitializer(dotsInitializer, function()
        return WTF.db.tracker.plateDots and WTF.HasTrackableDots()
    end)
    AddDefaultTick(offsetInitializer, WTF.PLATE_DOTS_OFFSET_MIN, WTF.PLATE_DOTS_OFFSET_MAX,
        WTF.DEFAULT_PLATE_DOTS_OFFSET)
    local opacity = Proxy(page, "WTF_TRACKER_PLATE_DOTS_OPACITY", Settings.VarType.Number, "Nameplate dot opacity",
        WTF.DEFAULT_PLATE_DOTS_OPACITY,
        function() return WTF.db.tracker.plateDotsOpacity end,
        function(value) WTF.SetPlateDotsOpacity(value) end)
    local opacityInitializer = Settings.CreateSlider(page, opacity,
        SliderOptions(WTF.PLATE_DOTS_OPACITY_MIN, WTF.PLATE_DOTS_OPACITY_MAX, 5, true),
        "How solid the bubble of DoT dots above each nameplate is, in percent. It changes at once, also in combat.")
    opacityInitializer:SetParentInitializer(dotsInitializer, function()
        return WTF.db.tracker.plateDots and WTF.HasTrackableDots()
    end)
    AddDefaultTick(opacityInitializer, WTF.PLATE_DOTS_OPACITY_MIN, WTF.PLATE_DOTS_OPACITY_MAX,
        WTF.DEFAULT_PLATE_DOTS_OPACITY)
    local health = Proxy(page, "WTF_TRACKER_HEALTH", Settings.VarType.Boolean, "Show mob health", false,
        function() return WTF.db.tracker.health end,
        function(value) WTF.SetTrackerHealth("health", value) end)
    local healthInitializer = Settings.CreateCheckbox(page, health,
        "Each mob's name line in the DoT tracker is its health bar, in the panel's color, also in combat. "
            .. "A change in combat applies when combat ends.")
    local healthText = Proxy(page, "WTF_TRACKER_HEALTH_TEXT", Settings.VarType.String, "Health text", "none",
        function() return WTF.db.tracker.healthText end,
        function(value) WTF.SetTrackerHealth("healthText", value) end)
    local textInitializer = Settings.CreateDropdown(page, healthText, function()
        local container = Settings.CreateControlTextContainer()
        for _, choice in ipairs(WTF.TRACKER_HEALTH_TEXTS) do
            container:Add(choice.key, choice.label)
        end
        return container:GetData()
    end, "The mob's health as text after its name: its number, its percent, or both.")
    textInitializer:SetParentInitializer(healthInitializer, function() return WTF.db.tracker.health end)
    AddTrackerSizes(page, "compact")
    AddTrackerSizes(page, "bars")
    -- Pinned Blizzard_SettingControls.lua:1014.
    if type(CreateSettingsButtonInitializer) == "function" and type(layout) == "table"
            and type(layout.AddInitializer) == "function" then
        layout:AddInitializer(CreateSettingsButtonInitializer("Tracker size", "Reset size", function()
            WTF.SetTrackerSize(WTF.db.tracker.theme, nil)
        end, "Back to the theme's own sizes and name position.", true))
    end
    local colors = {}
    for _, entry in ipairs(WTF.TRACKER_PANEL_COLORS) do
        colors[entry.key] = entry
    end
    for _, panel in ipairs(WTF.TRACKER_PANELS) do
        AddPanelSection(page, layout, panel, colors[panel.key])
    end
end

-- One color per slot, shared by the tracker's bars and the nameplate dots.
local function ApplyColors()
    if WTF.ApplyTrackerColors then
        WTF.ApplyTrackerColors()
    end
    if WTF.ApplyDotColors then
        WTF.ApplyDotColors()
    end
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
    {switch = "fearGroup", label = "Fear: tell the group as you start casting"},
    {switch = "banishGroup", label = "Banish: tell the group as you start casting (%M: its moon, after a row click)"},
    {switch = "enslaveGroup", label = "Enslave Demon: tell the group as you start casting"},
    {switch = "howlGroup", label = "Howl of Terror: tell the group"},
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
        "%T is the target's full name (for control spells, the mob), %Z your zone, and %M the mob's raid "
            .. "marker (after a Banish row click; else nothing). Press Enter to keep an edit, Escape to undo it. "
            .. "Nothing is sent for yourself or for a cast that fails.")
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
        for _, radio in ipairs(self.channels) do
            radio:SetChecked(settings.channel == radio.value)
        end
        for _, row in ipairs(self.rows) do
            row.check:SetChecked(settings[row.switch])
            row.edit:SetText(settings[row.key])
            row.edit:SetCursorPosition(0)
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

-- DoTs page ------------------------------------------------------------------

-- One row per DoT (author): its icon, its name, whether it shows as a
-- nameplate dot, and its color. Blizzard's Settings list has no control to
-- reorder a list, so this is a canvas page whose rows you drag up or down,
-- as Dyre's Quest Targeting reorders its hit list: a gold line shows where
-- the row would drop, placed by an OnUpdate set only for the drag.
local DOTS_ROW_HEIGHT = 30
local DOTS_ICON_SIZE = 22
local DOTS_ROW_WIDTH = 420
local DOTS_PLATE_LEFT = 220
local DOTS_SWATCH_LEFT = 380
local DOTS_SWATCH_SIZE = 20
local DOTS_BUTTON_WIDTH = 128
local DOTS_BUTTON_HEIGHT = 22
local DOTS_DRAG_ALPHA = 0.5
local DOTS_INSERT_HEIGHT = 2
local PLATES_OFF_TIP = "Turn on Show DoT dots on nameplates on the DoT Tracker page to choose the dots."

local function SetDotOrder(order)
    WTF.db.tracker.order = WTF.SanitizeDotOrder(order)
    if WTF.ApplyDotOrder then
        WTF.ApplyDotOrder()
    end
    RefreshPlateDots()
end

-- The plate switches work only while the dots can show.
local function PlatesOn()
    return WTF.db.tracker.plateDots == true and WTF.HasTrackableDots and WTF.HasTrackableDots()
end

local function Tooltip(owner, text)
    if type(GameTooltip) ~= "table" then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function HideTooltip()
    if type(GameTooltip) == "table" then
        GameTooltip:Hide()
    end
end

local function HexOf(r, g, b)
    return string.format("ff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5))
end

local function SetDotColor(key, value)
    local default
    for _, slot in ipairs(WTF.DOT_SLOTS) do
        if slot.key == key then
            default = slot.color
        end
    end
    WTF.db.tracker.colors[key] = WTF.SanitizeColor(value, default)
    ApplyColors()
end

-- The game's color picker, as the Settings color swatch opens it
-- (Blizzard_SettingControls.lua: SettingsColorSwatchMixin); Cancel puts the
-- old color back.
local function PickColor(row)
    if type(ColorPickerFrame) ~= "table" or type(ColorPickerFrame.SetupColorPickerAndShow) ~= "function" then
        return
    end
    local key = row.key
    local r, g, b = WTF.SlotColor(key)
    ColorPickerFrame:SetupColorPickerAndShow({
        swatch = row.swatch, r = r, g = g, b = b,
        swatchFunc = function() SetDotColor(key, HexOf(ColorPickerFrame:GetColorRGB())) end,
        cancelFunc = function() SetDotColor(key, HexOf(ColorPickerFrame:GetPreviousValues())) end,
    })
end

local function CreateDotsPage()
    local page = CreateFrame("Frame")
    page.rows = {}
    local title = Text(page, "GameFontHighlightHuge", DOTS_TITLE)
    title:SetPoint("TOPLEFT", PAGE_LEFT, -16)
    local help = Text(page, "GameFontHighlightSmall",
        "Your DoTs in the order the DoT tracker's rows and the nameplate dots show them, the first one on top "
            .. "or at the left. Drag a row up or down to move it. A change made in combat reaches the tracker "
            .. "when combat ends; colors change at once.")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    help:SetWidth(EDIT_WIDTH)
    local insert = page:CreateTexture(nil, "OVERLAY")
    insert:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
    insert:SetHeight(DOTS_INSERT_HEIGHT)
    insert:Hide()
    page.insert = insert

    -- The gap under the cursor: 0 above the first row to #rows below the
    -- last, or nil when the cursor leaves the page (a drop there cancels).
    local function DropSlot()
        local scale = page:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x, y = x / scale, y / scale
        local left, right, top, bottom = page:GetLeft(), page:GetRight(), page:GetTop(), page:GetBottom()
        if not (left and right and top and bottom) or x < left or x > right or y > top or y < bottom then
            return nil
        end
        local slot = 0
        for _, row in ipairs(page.rows) do
            local rowTop = row:GetTop()
            if rowTop and rowTop - DOTS_ROW_HEIGHT / 2 > y then
                slot = slot + 1
            end
        end
        return slot
    end

    local function PlaceInsertLine()
        local slot = DropSlot()
        if not slot then
            insert:Hide()
            return
        end
        local anchor = page.rows[math.max(slot, 1)]
        insert:ClearAllPoints()
        insert:SetPoint("LEFT", anchor, slot == 0 and "TOPLEFT" or "BOTTOMLEFT", 0, 0)
        insert:SetWidth(DOTS_ROW_WIDTH)
        insert:Show()
    end

    local function StartReorder(row)
        row.reordering = true
        row:SetAlpha(DOTS_DRAG_ALPHA)
        row:SetScript("OnUpdate", PlaceInsertLine)
    end

    -- The gap counts the dragged row itself; a drop next to it changes nothing.
    local function StopReorder(row)
        if not row.reordering then
            return
        end
        row.reordering = nil
        row:SetScript("OnUpdate", nil)
        row:SetAlpha(1)
        insert:Hide()
        local slot = DropSlot()
        if not slot then
            return
        end
        local from = row.position
        if slot >= from then
            slot = slot - 1
        end
        if slot + 1 ~= from then
            local order = {}
            for index, key in ipairs(WTF.db.tracker.order) do
                order[index] = key
            end
            table.insert(order, slot + 1, table.remove(order, from))
            SetDotOrder(order)
        end
        page:OnRefresh()
    end

    local previous = help
    for position = 1, #WTF.DOT_SLOTS do
        local row = CreateFrame("Button", nil, page)
        row:SetSize(DOTS_ROW_WIDTH, DOTS_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, position == 1 and -16 or 0)
        row.position = position
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", StartReorder)
        row:SetScript("OnDragStop", StopReorder)
        row:SetScript("OnEnter", function(self)
            Tooltip(self, "Drag up or down to move " .. self.label:GetText() .. ".")
        end)
        row:SetScript("OnLeave", HideTooltip)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(DOTS_ICON_SIZE, DOTS_ICON_SIZE)
        row.icon:SetPoint("LEFT", 0, 0)
        row.label = Text(row, "GameFontHighlight", "")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.plate = CheckButton(row, "UICheckButtonTemplate", "On nameplates")
        row.plate:SetPoint("LEFT", DOTS_PLATE_LEFT, 0)
        row.plate:SetScript("OnClick", function(self)
            WTF.db.tracker.onPlates[row.key] = self:GetChecked() == true
            RefreshPlateDots()
        end)
        -- A disabled button still shows its tooltip, which says why.
        row.plate:SetMotionScriptsWhileDisabled(true)
        row.plate:SetScript("OnEnter", function(self)
            Tooltip(self, PlatesOn() and ("Show a " .. row.label:GetText() .. " dot in the nameplate bubble.")
                or PLATES_OFF_TIP)
        end)
        row.plate:SetScript("OnLeave", HideTooltip)
        row.swatch = CreateFrame("Button", nil, row)
        row.swatch:SetSize(DOTS_SWATCH_SIZE, DOTS_SWATCH_SIZE)
        row.swatch:SetPoint("LEFT", DOTS_SWATCH_LEFT, 0)
        local edge = row.swatch:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints()
        edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
        row.swatch.color = row.swatch:CreateTexture(nil, "ARTWORK")
        row.swatch.color:SetPoint("TOPLEFT", 1, -1)
        row.swatch.color:SetPoint("BOTTOMRIGHT", -1, 1)
        row.swatch:SetScript("OnClick", function() PickColor(row) end)
        row.swatch:SetScript("OnEnter", function(self)
            Tooltip(self, "The color of " .. row.label:GetText() .. " on the tracker's bars and on nameplate dots. "
                .. "Click to change it.")
        end)
        row.swatch:SetScript("OnLeave", HideTooltip)
        page.rows[position] = row
        previous = row
    end
    local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    reset:SetSize(DOTS_BUTTON_WIDTH, DOTS_BUTTON_HEIGHT)
    reset:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -12)
    reset:SetText("Reset order")
    reset:SetScript("OnClick", function()
        SetDotOrder(nil)
        page:OnRefresh()
    end)
    page.reset = reset

    function page:OnRefresh()
        local platesOn = PlatesOn()
        for position, slot in ipairs(WTF.OrderedDotSlots()) do
            local row = self.rows[position]
            row.key = slot.key
            row.label:SetText(slot.label)
            local texture = WTF.TrackerSlotIcon and WTF.TrackerSlotIcon(slot.key)
            if texture then
                row.icon:SetTexture(texture)
            else
                row.icon:SetColorTexture(WTF.SlotColor(slot.key))
            end
            row.plate:SetChecked(WTF.db.tracker.onPlates[slot.key] == true)
            row.plate:SetEnabled(platesOn)
            row.plate.label:SetTextColor(platesOn and 1 or 0.5, platesOn and 1 or 0.5, platesOn and 1 or 0.5)
            row.swatch.color:SetColorTexture(WTF.SlotColor(slot.key))
        end
    end

    -- The Settings panel's Defaults button restores this page only: the
    -- order, the colors, and the nameplate dots.
    function page:OnDefault()
        for _, slot in ipairs(WTF.DOT_SLOTS) do
            WTF.db.tracker.colors[slot.key] = slot.color
            WTF.db.tracker.onPlates[slot.key] = true
        end
        ApplyColors()
        SetDotOrder(nil)
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
    local home = WTF.toolkit and WTF.toolkit.RegisterSettingsCategory(TITLE)
    category = home or Settings.RegisterVerticalLayoutCategory(TITLE)
    Flag(category, "WTF_SHARDS_ENABLED", "Soul Shard management", "shards", "enabled", true,
        "Delete Soul Shards that Drain Soul creates above your limit. Shards you move into your bags are never deleted.")
    Flag(category, "WTF_STONES_ENABLED", "Stones", "stones", "enabled", true,
        "A bar with Soulstone and Healthstone buttons: left-click uses one, right-click creates one.",
        RefreshStones)
    Flag(category, "WTF_ANNOUNCE_ENABLED", "Announce", "announce", "enabled", true,
        "Tell your group and whisper the target when your Ritual of Summoning or a Soulstone use succeeds, "
            .. "and whisper the player when a Healthstone trade opens.")
    Flag(category, "WTF_TRACKER_ENABLED", "DoT tracker", "tracker", "enabled", true,
        "A row per mob you DoT, with the time left on your DoTs, Bane, Curse, and Fear.",
        RefreshTracker)
    Flag(category, "WTF_CONTROL_ENABLED", "Control bar", "control", "enabled", true,
        "A bar per mob you Fear or Banish with its time left; click one to cast it again.", RefreshControl)
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
            "Outline the Stones bar and the shard counter, and show sample DoT tracker rows, so you can drag "
                .. "them; untick to lock them again. /wtf unlock and /wtf lock do the same, and /wtf reset moves "
                .. "them back.")
        local grid = Proxy(category, "WTF_GRID", Settings.VarType.Boolean, "Show a grid while unlocked", true,
            function() return WTF.db.grid end,
            function(value)
                WTF.db.grid = value == true
                WTF.RefreshGrid()
            end)
        Settings.CreateCheckbox(category, grid, "While frames are unlocked, draw a faint grid over the screen "
            .. "with the center lines in red, so you can line frames up.")
    end
    AddShardPage(category)
    AddStonesPage(category)
    AddTrackerPage(category)
    local dotsPage = CreateDotsPage()
    WTF.dotsPage = dotsPage
    Settings.RegisterCanvasLayoutSubcategory(category, dotsPage, DOTS_TITLE)
    AddControlPage(category)
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
