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
local TRACKER_TITLE = "DoT Tracker"
local DOTS_TITLE = "DoTs"
local ALERTS_TITLE = "Alerts"
local SHIELD_TITLE = "Shield"
local CHIMES_TITLE = "Cooldown Chimes"
local REMINDER_TITLE = "Demon Armor"
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
local DDT = {addon = "DyresDebuffTracker", owner = "Dyre's Debuff Tracker", button = "Open Debuff Tracker settings",
    since = "1.11.0"}
local DDT_PAGES = {
    {title = TRACKER_TITLE, variable = "WTF_MOVED_TRACKER", name = "DoT tracker and damage prediction",
        what = "The DoT tracker, DoT damage prediction, and the smart curse"},
    {title = DOTS_TITLE, variable = "WTF_MOVED_DOTS", name = "DoT colors, order, and nameplate dots",
        what = "The DoT colors, order, and nameplate DoT dots"},
    {title = CONTROL_TITLE, variable = "WTF_MOVED_CONTROL", name = "Control bar, macros, and announcements",
        what = "The Control bar, \"! Fear\", \"! Banish\", \"! Seduction\", and the Fear and Banish announcements"},
}
for _, moved in ipairs(DDT_PAGES) do
    for key, value in pairs(DDT) do
        moved[key] = value
    end
end
local MOVED_PAGES = {
    {title = SHIELD_TITLE, variable = "WTF_MOVED_SHIELD", addon = "DyresShieldsUp", owner = "Dyre's Shields Up",
        name = "Shield display", button = "Open Shield settings", what = "The shield display"},
    {title = CHIMES_TITLE, variable = "WTF_MOVED_CHIMES", addon = "DyresBuffReminders",
        owner = "Dyre's Buff Reminders", name = "Cooldown chimes", button = "Open Chime settings",
        what = "The cooldown chimes"},
    {title = ALERTS_TITLE, variable = "WTF_MOVED_NIGHTFALL", addon = "DyresBuffReminders",
        owner = "Dyre's Buff Reminders", name = "Nightfall sound", button = "Open Proc settings",
        what = "The Nightfall sound (Proc Sounds)", procKey = "nightfall"},
    {title = REMINDER_TITLE, variable = "WTF_MOVED_REMINDER", addon = "DyresBuffReminders",
        owner = "Dyre's Buff Reminders", name = "Demon Armor reminder", button = "Open Reminder settings",
        what = "The Demon Armor reminder"},
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

local function ProcOwnerTooltip(key)
    local owner = WTF.ProcOwner(key)
    if not owner then
        return "No AddOn plays it with proc arcs now."
    end
    return WTF.ProcOwnerTitle(owner) .. " plays it with its proc arcs. This opens its settings."
end

-- The click asks for the owner again: one row for any owner.
local function OpenProcOwner(key)
    local owner = WTF.ProcOwner(key)
    local info = owner and Member(owner)
    if not info or type(info.openSettings) ~= "function" then
        WTF.Report("No Dyre's AddOn plays it with proc arcs now.")
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
    local name = moved.name:gsub(" sound$", " arcs and sound")
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

-- One row: the Toolkit's link, else (without Dyre's Toolkit 2.3.0) the note only.
local function AddMovedRow(page, layout, moved)
    local missing = "Install " .. moved.owner .. " from CurseForge for " .. moved.what:gsub("^The", "the") .. "."
    local since = " in WTF " .. (moved.since or "1.3.0") .. "."
    local link = WTF.toolkit and type(WTF.toolkit.AddSettingsLink) == "function"
        and WTF.toolkit.AddSettingsLink(page, layout, {addon = moved.addon, name = moved.name,
            button = moved.button, missing = missing,
            tooltip = moved.what .. " moved to " .. moved.owner .. since .. " This opens its settings."})
    if link then
        return link
    end
    return Notice(page, moved.variable, moved.name .. " (moved to " .. moved.owner .. ")",
        moved.what .. " moved to " .. moved.owner .. since .. " " .. missing)
end

local function CanShow(row)
    return type(row) == "table" and type(row.AddShownPredicate) == "function"
end

local function AddMovedPage(parent, moved)
    local page, layout = Settings.RegisterVerticalLayoutSubcategory(parent, moved.title)
    local key = moved.procKey
    if not key or not (WTF.toolkit and type(WTF.toolkit.AddSettingsLink) == "function") then
        AddMovedRow(page, layout, moved)
        return
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
    local counterScale = Proxy(page, "WTF_SHARDS_COUNTER_SCALE", Settings.VarType.Number, "Shard counter size",
        WTF.DEFAULT_FRAME_SCALE,
        function() return WTF.db.shards.counterScale end,
        function(value) WTF.SetShardCounterScale(value) end)
    local counterScaleInitializer = Settings.CreateSlider(page, counterScale,
        SliderOptions(WTF.FRAME_SCALE_MIN, WTF.FRAME_SCALE_MAX, WTF.FRAME_SCALE_STEP, true),
        "How big the shard counter is, in percent. It keeps its center, and changes at once, also in combat.")
    counterScaleInitializer:SetParentInitializer(counterInitializer, function() return WTF.db.shards.counter end)
end

local function AddStonesPage(parent)
    local page = Settings.RegisterVerticalLayoutSubcategory(parent, STONES_TITLE)
    local shownInitializer = Flag(page, "WTF_STONES_SHOWN", "Show the Stones bar", "stones", "shown", true,
        "The bar with the Soulstone and Healthstone buttons. Changes in combat apply when combat ends.",
        RefreshStones)
    local scale = Proxy(page, "WTF_STONES_SCALE", Settings.VarType.Number, "Stones bar size",
        WTF.DEFAULT_FRAME_SCALE,
        function() return WTF.db.stones.scale end,
        function(value) WTF.SetStonesScale(value) end)
    local scaleInitializer = Settings.CreateSlider(page, scale,
        SliderOptions(WTF.FRAME_SCALE_MIN, WTF.FRAME_SCALE_MAX, WTF.FRAME_SCALE_STEP, true),
        "How big the Stones bar is, in percent. It keeps its center. A change in combat applies when combat ends.")
    scaleInitializer:SetParentInitializer(shownInitializer, function() return WTF.db.stones.shown end)
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
            .. "Nothing is sent for yourself or for a cast that fails. The Fear and Banish announcements moved "
            .. "to Dyre's Debuff Tracker (the Control page).")
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
            "Outline the Stones bar and the shard counter, so you can drag "
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
