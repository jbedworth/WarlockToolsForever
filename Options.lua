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

local function RefreshStones()
    if WTF.RefreshStones then
        WTF.RefreshStones()
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
end

local function AddStonesPage(parent)
    local page = Settings.RegisterVerticalLayoutSubcategory(parent, STONES_TITLE)
    Flag(page, "WTF_STONES_SHOWN", "Show the Stones bar", "stones", "shown", true,
        "The bar with the Soulstone and Healthstone buttons. Changes in combat apply when combat ends.",
        RefreshStones)
    Flag(page, "WTF_STONES_LOCKED", "Lock the Stones bar", "stones", "locked", false,
        "Stop the bar from being dragged. /wtf reset moves it back to its default place.")
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
    Flag(page, "WTF_TRACKER_PLACEHOLDERS", "Show placeholders", "tracker", "placeholders", false,
        "Show sample rows while nothing is tracked, so you can drag the tracker into place. Turn it off when done.",
        RefreshTracker)
    Flag(page, "WTF_TRACKER_LOCKED", "Lock the tracker", "tracker", "locked", false,
        "Stop the tracker from being dragged. /wtf reset moves it back to its default place.")
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
    local nightfall = Flag(page, "WTF_ALERTS_NIGHTFALL", "Nightfall sound", "alerts", "nightfall", false,
        "Play a sound when Nightfall procs (Shadow Trance: your next Shadow Bolt is instant), also in combat.",
        WTF.ApplyNightfallSound)
    if type(nightfall.AddModifyPredicate) == "function" then
        nightfall:AddModifyPredicate(function() return WTF.HasNightfallSound() end)
    end
    local sound = Proxy(page, "WTF_ALERTS_NIGHTFALL_SOUND", Settings.VarType.String, "Sound",
        WTF.DEFAULT_NIGHTFALL_SOUND,
        function() return WTF.db.alerts.nightfallSound end,
        function(value)
            for _, choice in ipairs(WTF.NIGHTFALL_SOUNDS) do
                if choice.key == value then
                    WTF.db.alerts.nightfallSound = value
                    WTF.ApplyNightfallSound()
                    WTF.PreviewNightfallSound()
                end
            end
        end)
    local function Choices()
        local container = Settings.CreateControlTextContainer()
        for _, choice in ipairs(WTF.NIGHTFALL_SOUNDS) do
            container:Add(choice.key, choice.label)
        end
        return container:GetData()
    end
    local soundInitializer = Settings.CreateDropdown(page, sound, Choices,
        "The sound to play. Choosing one plays it once.")
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
        "%T is the target's full name and %Z your zone. Press Enter to keep an edit, Escape to undo it. "
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
    AddShardPage(category)
    AddStonesPage(category)
    AddTrackerPage(category)
    AddColorsPage(category)
    AddAlertsPage(category)
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
