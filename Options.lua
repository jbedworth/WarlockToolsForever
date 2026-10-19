local _, WTF = ...

-- The AddOn settings: a main page with one switch per module, and a subpage
-- per module for its details. Shards and Stones use Blizzard's vertical layout
-- with proxy settings that read and write WarlockToolsForeverDB directly;
-- Announce needs text fields, so it is a canvas page.
local TITLE = "Warlock Tools Forever"
local SHARDS_TITLE = "Soul Shards"
local STONES_TITLE = "Stones"
local ANNOUNCE_TITLE = "Announce"
local TRACKER_TITLE = "DoT Tracker"
local COLORS_TITLE = "DoT Colors"
local ALERTS_TITLE = "Alerts"
local SHIELD_TITLE = "Shield"
local CHIMES_TITLE = "Cooldown Chimes"
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
local SOUNDS_MISSING_TIP = " Install Dyre's Sounds to hear it and to choose its sound."
local REMINDERS_ELSEWHERE_TIP = "Dyre's Buff Reminders shows your buff reminders now, so WTF's "
    .. "Demon Armor icon stays hidden. Type /dbr to change it. WTF keeps its own setting as it is."
-- by: the WTF.CHIMES_ADDONS entry that plays the chimes.
local function ChimesElsewhereTip(by)
    return by.title .. " plays your cooldown chimes now, so WTF plays none. Type " .. by.slash
        .. " to change them. WTF keeps its own chime settings as they are."
end

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

local function RefreshShield()
    WTF.RefreshShield()
end

local function SliderOptions(minValue, maxValue, step)
    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    if type(MinimalSliderWithSteppersMixin) == "table" and type(options.SetLabelFormatter) == "function" then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    end
    return options
end

-- A page whose feature a stand-alone Dyre's AddOn now runs (author-approved rule)
-- says so twice: its name in the settings list names that AddOn, and a heading
-- with a tooltip tops the page. Headings as Blizzard's Controls page adds them
-- (Blizzard_SettingControls.lua: CreateSettingsListSectionHeaderInitializer).
local function ManagedTitle(title, addonTitle, managed)
    return managed and (title .. " (" .. addonTitle .. ")") or title
end

local function ManagedHeading(layout, managed, heading, tooltip)
    if managed and type(CreateSettingsListSectionHeaderInitializer) == "function" and type(layout) == "table"
            and type(layout.AddInitializer) == "function" then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(heading, tooltip))
    end
end

-- The shield display draws in one AddOn only (Shield.lua's election); in the
-- others its settings do nothing, so they are greyed out (author-approved) with
-- a note naming the AddOn that draws it. Checked each time the page shows.
local SHIELD_ELSEWHERE = " Dyre's Shields Up shows the shield display now, so these settings do nothing "
    .. "here. Type /dsu to change it. WTF keeps its own shield settings as they are."

local function ShieldOwnerNote(display)
    if WTF.ShieldStandAside() then
        return SHIELD_ELSEWHERE
    end
    if display.IsOwner() then
        return ""
    end
    local owner = display.OwnerAddOn()
    local title = owner and type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function"
        and C_AddOns.GetAddOnMetadata(owner, "Title")
    if type(title) ~= "string" or title == "" then
        title = tostring(owner)
    end
    return " " .. title .. " draws the shield display, so use its settings for it."
end

local function GreyUnlessOwner(initializer, display)
    if type(initializer) == "table" and type(initializer.AddModifyPredicate) == "function" then
        initializer:AddModifyPredicate(function() return not WTF.ShieldStandAside() and display.IsOwner() end)
    end
    return initializer
end

local function AddShieldPage(parent)
    local aside = WTF.ShieldStandAside()
    local page, layout = Settings.RegisterVerticalLayoutSubcategory(parent,
        ManagedTitle(SHIELD_TITLE, "Dyre's Shields Up", aside))
    ManagedHeading(layout, aside, "Shields are now managed by Dyre's Shields Up",
        "Use /dsu to change the shield display. "
            .. "WTF keeps its own settings as they are, and uses them again if you remove Dyre's Shields Up.")
    local display = WTF.ShieldDisplay
    local note = ShieldOwnerNote(display)
    GreyUnlessOwner(Flag(page, "WTF_SHIELD_NUMBER", "Show the absorb amount", "shield", "number", true,
        "Show your remaining absorb as a number beside the ring." .. note, RefreshShield), display)
    local soundSwitch = GreyUnlessOwner(Flag(page, "WTF_SHIELD_BREAK_SOUND", "Sound when a shield ends",
        "shield", "breakSound", false,
        "Play a sound when your Shadow Ward, your Voidwalker's Sacrifice, or another shield on you ends or "
            .. "breaks, also in combat." .. note, RefreshShield), display)
    -- Which sound, under its switch (author-approved: a default you can change).
    local sound = Proxy(page, "WTF_SHIELD_BREAK_SOUND_CHOICE", Settings.VarType.String, "Sound",
        display.DEFAULT_BREAK_SOUND,
        function() return WTF.db.shield.breakSoundKey end,
        function(value)
            WTF.db.shield.breakSoundKey = display.SanitizeBreakSound(value)
            RefreshShield()
            display.PreviewBreakSound()
        end)
    -- The sounds come from Dyre's Sounds; without it the list is empty.
    local dropdown = Settings.CreateDropdown(page, sound, display.SoundChoices,
        "The sound when a shield ends. Choosing one plays it once. The sounds come from Dyre's Sounds." .. note)
    display.SetupSoundMenu(dropdown)
    GreyUnlessOwner(dropdown, display)
    dropdown:SetParentInitializer(soundSwitch, function() return WTF.db.shield.breakSound end)
    local scale = Proxy(page, "WTF_SHIELD_SCALE", Settings.VarType.Number, "Display size (%)", display.DEFAULT_SCALE,
        function() return WTF.db.shield.scale end,
        function(value)
            WTF.db.shield.scale = display.SanitizeScale(value)
            RefreshShield()
        end)
    GreyUnlessOwner(Settings.CreateSlider(page, scale,
        SliderOptions(display.SCALE_MIN, display.SCALE_MAX, display.SCALE_STEP),
        "How big the shield display is, in percent." .. note), display)
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

-- Each spell's switch, and under it its sound from Dyre's Sounds (the nested
-- menu, author-approved as in MTF). With Dyre's Buff Reminders installed the
-- page only says that it plays the chimes.
local function AddChimesPage(parent)
    local by = WTF.ChimesStandAside()
    local aside = by ~= nil
    local page, layout = Settings.RegisterVerticalLayoutSubcategory(parent,
        ManagedTitle(CHIMES_TITLE, by and by.title, aside))
    if aside then
        ManagedHeading(layout, true, "Cooldown chimes are now managed by " .. by.title,
            "Use " .. by.slash .. " to change them. "
                .. "WTF keeps its own settings as they are, and uses them again if you remove " .. by.title .. ".")
        Notice(page, "WTF_CHIMES_ELSEWHERE", "Played by " .. by.title, ChimesElsewhereTip(by))
        return
    end
    local library = WTF.SoundLibrary()
    local lead = Proxy(page, "WTF_CHIMES_LEAD", Settings.VarType.Number, "Chime early (seconds)",
        WTF.DEFAULT_CHIME_LEAD,
        function() return WTF.db.chimes.lead end,
        function(value)
            WTF.db.chimes.lead = WTF.SanitizeChimeLead(value)
        end)
    Settings.CreateSlider(page, lead, SliderOptions(WTF.CHIME_LEAD_MIN, WTF.CHIME_LEAD_MAX, WTF.CHIME_LEAD_STEP),
        "How long before a cooldown ends the chime plays, so you can act the moment it is ready.")
    for _, chime in ipairs(WTF.CHIME_SPELLS) do
        local setting = Proxy(page, "WTF_CHIME_" .. chime.key:upper(), Settings.VarType.Boolean, chime.label,
            chime.on,
            function() return WTF.db.chimes.spells[chime.key] end,
            function(value) WTF.db.chimes.spells[chime.key] = value == true end)
        local switch = Settings.CreateCheckbox(page, setting, "Chime when " .. chime.label .. " is ready again."
            .. (library and "" or SOUNDS_MISSING_TIP))
        -- Without the library there are no sounds to choose; saved choices stay.
        if library then
            local sound = Proxy(page, "WTF_CHIME_SOUND_" .. chime.key:upper(), Settings.VarType.String, "Sound",
                WTF.DEFAULT_CHIME_SOUND,
                function() return WTF.db.chimes.sounds[chime.key] end,
                function(value)
                    local key = library.Resolve(value)
                    if key then
                        WTF.db.chimes.sounds[chime.key] = key
                        WTF.PreviewChime(chime.key)
                    end
                end)
            local dropdown = Settings.CreateDropdown(page, sound, library.Choices(),
                "The sound for " .. chime.label .. ". Choosing one plays it once. The sounds come from Dyre's Sounds.")
            library.SetupMenu(dropdown)
            dropdown:SetParentInitializer(switch, function() return WTF.db.chimes.spells[chime.key] end)
        end
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
                end)
            Settings.CreateDropdown(page, marker, MarkerChoices, "The raid marker WTF puts on a mob when your "
                .. spell.label .. " lands, and %M in its message. In a raid only the leader and assistants mark.")
        end
    end
    Flag(page, "WTF_CONTROL_MACROS", "Keep control macros", "control", "macros", true,
        "Keep \"! Fear\", \"! Banish\", and \"! Seduction\" in your character macros for your action bars, "
            .. "each once you know its spell. \"! Fear\" Fears the mob under your mouse (a feared mob's nameplate "
            .. "as its timer runs out), else your target. The others focus the hostile mob under your mouse (or "
            .. "your target, out of combat) and cast on your focus. \"! Seduction\" appears once your Succubus "
            .. "or Incubus has learned Seduction from its Grimoire, and casts only while one is your pet. Turning "
            .. "this off deletes them.", function() WTF.ApplyControlMacros() end)
    Flag(page, "WTF_CONTROL_PLATE_TIMERS", "Fear timers on nameplates", "control", "plateTimers", true,
        "A thin bar under each feared mob's nameplate that drains with your Fear's time left, so you see which "
            .. "one is about to break; click its nameplate to target it.", RefreshControl)
    local scale = Proxy(page, "WTF_CONTROL_SCALE", Settings.VarType.Number, "Bar size (%)",
        WTF.DEFAULT_CONTROL_SCALE,
        function() return WTF.db.control.scale end,
        function(value)
            WTF.db.control.scale = WTF.SanitizeControlScale(value)
            RefreshControl()
        end)
    Settings.CreateSlider(page, scale,
        SliderOptions(WTF.CONTROL_SCALE_MIN, WTF.CONTROL_SCALE_MAX, WTF.CONTROL_SCALE_STEP),
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

local function AddTrackerPage(parent)
    local page = Settings.RegisterVerticalLayoutSubcategory(parent, TRACKER_TITLE)
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
            .. "grey while it is missing. Needs at least one DoT you know.",
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
    local options = Settings.CreateSliderOptions(WTF.PLATE_DOTS_OFFSET_MIN, WTF.PLATE_DOTS_OFFSET_MAX, 1)
    if type(MinimalSliderWithSteppersMixin) == "table" and type(options.SetLabelFormatter) == "function" then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    end
    local offsetInitializer = Settings.CreateSlider(page, offset, options,
        "How far above the nameplate the dots sit, to clear other nameplate AddOns.")
    offsetInitializer:SetParentInitializer(dotsInitializer, function()
        return WTF.db.tracker.plateDots and WTF.HasTrackableDots()
    end)
    AddDefaultTick(offsetInitializer, WTF.PLATE_DOTS_OFFSET_MIN, WTF.PLATE_DOTS_OFFSET_MAX,
        WTF.DEFAULT_PLATE_DOTS_OFFSET)
end

-- One color per slot, shared by the tracker's bars and the nameplate dots, and
-- whether the slot shows as a nameplate dot. Colors apply at once.
local function ApplyColors()
    if WTF.ApplyTrackerColors then
        WTF.ApplyTrackerColors()
    end
    if WTF.ApplyDotColors then
        WTF.ApplyDotColors()
    end
end

local function AddColorsPage(parent)
    local page = Settings.RegisterVerticalLayoutSubcategory(parent, COLORS_TITLE)
    for _, slot in ipairs(WTF.DOT_SLOTS) do
        local key = slot.key
        local color = Proxy(page, "WTF_COLOR_" .. key:upper(), Settings.VarType.String, slot.label, slot.color,
            function() return WTF.db.tracker.colors[key] end,
            function(value)
                WTF.db.tracker.colors[key] = WTF.SanitizeColor(value, slot.color)
                ApplyColors()
            end)
        Settings.CreateColorSwatch(page, color, "The color of " .. slot.label
            .. " on the tracker's bars and on nameplate dots.")
        local plate = Proxy(page, "WTF_PLATE_" .. key:upper(), Settings.VarType.Boolean,
            slot.label .. " on nameplates", slot.plate,
            function() return WTF.db.tracker.onPlates[key] end,
            function(value)
                WTF.db.tracker.onPlates[key] = value == true
                RefreshPlateDots()
            end)
        Settings.CreateCheckbox(page, plate, "Show a " .. slot.label .. " dot in the nameplate bubble.")
    end
end

local function AddAlertsPage(parent)
    local page = Settings.RegisterVerticalLayoutSubcategory(parent, ALERTS_TITLE)
    local library = WTF.SoundLibrary()
    local nightfall = Flag(page, "WTF_ALERTS_NIGHTFALL", "Nightfall sound", "alerts", "nightfall", false,
        "Play a sound when Nightfall procs (Shadow Trance: your next Shadow Bolt is instant), also in combat."
            .. (library and "" or SOUNDS_MISSING_TIP),
        WTF.ApplyNightfallSound)
    if type(nightfall.AddModifyPredicate) == "function" then
        nightfall:AddModifyPredicate(function() return WTF.HasNightfallSound() end)
    end
    -- Without the library there are no sounds to choose; the saved choice stays.
    if not library then
        return
    end
    local sound = Proxy(page, "WTF_ALERTS_NIGHTFALL_SOUND", Settings.VarType.String, "Sound",
        WTF.DEFAULT_NIGHTFALL_SOUND,
        function() return WTF.db.alerts.nightfallSound end,
        function(value)
            -- Only aura sounds: the game plays a sound file on a buff, not a sound kit.
            local key = library.Resolve(value)
            if key and library.AuraSound(key) then
                WTF.db.alerts.nightfallSound = key
                WTF.ApplyNightfallSound()
                WTF.PreviewNightfallSound()
            end
        end)
    local soundInitializer = Settings.CreateDropdown(page, sound, library.Choices("aura"),
        "The sound to play. Choosing one plays it once. The sounds come from Dyre's Sounds.")
    library.SetupMenu(soundInitializer, "aura")
    soundInitializer:SetParentInitializer(nightfall, function()
        return WTF.db.alerts.nightfall and WTF.HasNightfallSound()
    end)
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
    {switch = "banishGroup", label = "Banish: tell the group as you start casting (%M: its moon)"},
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
            .. "marker. Press Enter to keep an edit, Escape to undo it. "
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

function WTF.InitializeOptions()
    if not HasSettingsAPI() then
        return
    end
    category = Settings.RegisterVerticalLayoutCategory(TITLE)
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
    GreyUnlessOwner(Flag(category, "WTF_SHIELD_ENABLED", "Shield display", "shield", "enabled", true,
        "A crescent beside your character that fills with your remaining shield: Shadow Ward, your "
            .. "Voidwalker's Sacrifice, or a shield another player puts on you, like Power Word: Shield."
            .. ShieldOwnerNote(WTF.ShieldDisplay), RefreshShield), WTF.ShieldDisplay)
    Flag(category, "WTF_CONTROL_ENABLED", "Control bar", "control", "enabled", true,
        "A bar per mob you Fear or Banish with its time left; click one to cast it again.", RefreshControl)
    if WTF.RemindersStandAside() then
        -- Dyre's Buff Reminders shows it; the saved switch stays as it is.
        Notice(category, "WTF_REMINDERS_ENABLED", "Demon Armor reminder (shown by Dyre's Buff Reminders)",
            REMINDERS_ELSEWHERE_TIP)
    else
        Flag(category, "WTF_REMINDERS_ENABLED", "Demon Armor reminder", "reminders", "enabled", true,
            "An icon with a pulsing border while you lack Demon Armor (or Demon Skin), out of combat. Click it "
                .. "to cast your armor.", function() WTF.RefreshReminders() end)
    end
    local chimesBy = WTF.ChimesStandAside()
    if chimesBy then
        -- Dyre's Buff Reminders plays them; the saved switch stays as it is.
        Notice(category, "WTF_CHIMES_ENABLED", "Cooldown chimes (played by " .. chimesBy.title .. ")",
            ChimesElsewhereTip(chimesBy))
    else
        Flag(category, "WTF_CHIMES_ENABLED", "Cooldown chimes", "chimes", "enabled", true,
            "A sound just before Death Coil, Howl of Terror, and your other chosen spells are ready again."
                .. (WTF.SoundLibrary() and "" or " Install Dyre's Sounds to hear them."))
    end
    local unlocked = Proxy(category, "WTF_UNLOCKED", Settings.VarType.Boolean, "Unlock frames to move them", false,
        function() return not WTF.db.locked end,
        function(value) WTF.SetFramesLocked(value ~= true) end)
    Settings.CreateCheckbox(category, unlocked,
        "Outline the Stones bar and the shard counter, and show sample DoT tracker rows, so you can drag them; "
            .. "untick to lock them again. /wtf unlock and /wtf lock do the same, and /wtf reset moves them back.")
    local grid = Proxy(category, "WTF_GRID", Settings.VarType.Boolean, "Show a grid while unlocked", true,
        function() return WTF.db.grid end,
        function(value)
            WTF.db.grid = value == true
            WTF.RefreshGrid()
        end)
    Settings.CreateCheckbox(category, grid, "While frames are unlocked, draw a faint grid over the screen with "
        .. "the center lines in red, so you can line frames up.")
    AddShardPage(category)
    AddStonesPage(category)
    AddTrackerPage(category)
    AddColorsPage(category)
    AddAlertsPage(category)
    AddShieldPage(category)
    AddChimesPage(category)
    AddControlPage(category)
    local announcePage = CreateAnnouncePage()
    WTF.announcePage = announcePage
    Settings.RegisterCanvasLayoutSubcategory(category, announcePage, ANNOUNCE_TITLE)
    Settings.RegisterAddOnCategory(category)
end

function WTF.OpenSettings()
    if not category then
        WTF.Report(UNAVAILABLE)
        return
    end
    Settings.OpenToCategory(category:GetID())
end
