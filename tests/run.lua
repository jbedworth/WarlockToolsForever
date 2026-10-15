-- Run from the repository root: lua tests/run.lua
-- These mocks test AddOn logic, not Forever compatibility, protected actions,
-- secret-value behavior, layout, or taint.
-- Every test gets its own globals, bags, cursor, clock, event frames, and namespace.
if _VERSION ~= "Lua 5.1" then
    io.stderr:write("This suite requires Lua 5.1; found " .. tostring(_VERSION) .. "\n")
    os.exit(1)
end

local tests = {}
local function test(name, body)
    tests[#tests + 1] = {name = name, body = body}
end
local function equal(actual, expected, context)
    if actual ~= expected then
        error((context or "value") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end
local function contains(actual, fragment, context)
    if type(actual) ~= "string" or not actual:find(fragment, 1, true) then
        error((context or "text") .. ": expected text containing " .. fragment
            .. ", got " .. tostring(actual), 2)
    end
end

local RUNTIME_FILES = {"Commands.lua", "Core.lua", "Shards.lua", "Stones.lua", "Announce.lua", "Probe.lua",
    "Options.lua"}
local SHARD = 6265
local SPELLS = {[1120] = "Drain Soul", [11675] = "Drain Soul", [686] = "Shadow Bolt", [172] = "Corruption",
    [6222] = "Corruption", [980] = "Curse of Agony", [698] = "Ritual of Summoning",
    [20707] = "Soulstone Resurrection", [20762] = "Soulstone Resurrection",
    [693] = "Create Soulstone (Minor)", [20752] = "Create Soulstone (Lesser)",
    [6201] = "Create Healthstone (Minor)", [6202] = "Create Healthstone (Lesser)", [5699] = "Create Healthstone"}
local ITEMS = {[5232] = {"Minor Soulstone", 18}, [16892] = {"Lesser Soulstone", 30},
    [5512] = {"Minor Healthstone", 1}, [5511] = {"Lesser Healthstone", 12}, [5509] = {"Healthstone", 24}}
local DRAIN_SOUL_RANK_4 = 11675
local SHADOW_BOLT = 686

-- A secret stands in for the client's opaque combat values; tests mark them with
-- issecretvalue, and any comparison or concatenation with one raises an error.
local function secret()
    return setmetatable({}, {
        __eq = function() error("compared a secret value") end,
        __lt = function() error("compared a secret value") end,
        __le = function() error("compared a secret value") end,
        __concat = function() error("concatenated a secret value") end,
        __tostring = function() error("printed a secret value") end,
        __index = function() error("indexed a secret value") end,
    })
end

local function fixture(options)
    options = options or {}
    local state = {frames = {}, messages = {}, now = 100, combat = false, cursor = nil,
        deleteBlocked = false, secrets = {}, settings = {}, categories = {}, opened = nil,
        notified = {}, known = options.known or {}, carried = options.carried or {}, sent = {},
        group = options.group, tooltip = {}}
    -- bags[bag] = {size, family, items = {[slot] = {itemID, stackCount, isLocked}}}
    state.bags = options.bags or {
        [0] = {size = 16, family = 0, items = {}},
        [1] = {size = 10, family = 0, items = {}},
        [2] = {size = 0, family = 0, items = {}},
        [3] = {size = 0, family = 0, items = {}},
        [4] = {size = 0, family = 0, items = {}},
    }
    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.SlashCmdList = options.slashCmdList or {}
    for key, value in pairs(options.globals or {}) do env[key] = value end
    env.DEFAULT_CHAT_FRAME = {AddMessage = function(_, message)
        state.messages[#state.messages + 1] = message
    end}
    state.toc = {}
    for text in io.lines("WarlockToolsForever.toc") do
        local key, value = text:match("^##%s*([^:]+):%s*(.-)%s*$")
        if key then state.toc[key] = value end
    end
    env.C_AddOns = {GetAddOnMetadata = function(name, field)
        equal(name, "WarlockToolsForever", "metadata uses the AddOn folder name")
        return state.toc[field] or ""
    end}
    env.UnitClass = function(unit)
        equal(unit, "player")
        local class = options.class or "WARLOCK"
        return class:sub(1, 1) .. class:sub(2):lower(), class
    end
    env.GetTime = function() return state.now end
    env.InCombatLockdown = function() return state.combat end
    env.NUM_BAG_SLOTS = 4
    if options.reagentBag then
        env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
    end
    env.issecretvalue = function(value) return state.secrets[value] == true end
    env.C_Spell = {GetSpellName = function(id)
        if SPELLS[id] then return SPELLS[id] end
    end}
    env.C_Item = {
        GetItemNameByID = function(id)
            if id == SHARD then return "Soul Shard" end
        end,
        GetItemCount = function(id) return state.carried[id] or 0 end,
        -- As in client, uncached item data returns nothing.
        GetItemInfo = function(id)
            local info = ITEMS[id]
            if info then return info[1], "link", 1, 10, info[2] end
        end,
        GetItemIconByID = function(id) return 1000 + id end,
        RequestLoadItemDataByID = function(id) state.requested = (state.requested or 0) + 1 end,
    }
    if not options.noSpellBook then
        env.C_SpellBook = {IsSpellKnown = function(id) return state.known[id] == true end}
    end
    env.IsInRaid = function() return state.group == "raid" end
    env.IsInGroup = function() return state.group ~= nil end
    env.GetZoneText = function() return state.zone or "Redridge Mountains" end
    env.C_ChatInfo = {SendChatMessage = function(message, chatType, _, target)
        if chatType == "SAY" and state.sayBlocked then
            state.emit("ADDON_ACTION_BLOCKED", "WarlockToolsForever", "UNKNOWN()")
            return
        end
        state.sent[#state.sent + 1] = {message = message, chatType = chatType, target = target}
    end}
    env.GameTooltip = {
        SetOwner = function() state.tooltip = {} end,
        SetText = function(_, text) state.tooltip[#state.tooltip + 1] = text end,
        AddLine = function(_, text) state.tooltip[#state.tooltip + 1] = text end,
        Show = function() end,
        Hide = function() end,
    }

    -- Containers and the cursor. As in client, an empty slot reports nothing.
    local function item(bag, slot)
        local container = state.bags[bag]
        return container and container.items[slot]
    end
    env.C_Container = {
        GetContainerNumSlots = function(bag) return state.bags[bag] and state.bags[bag].size or 0 end,
        GetContainerNumFreeSlots = function(bag)
            local container = state.bags[bag]
            local used = 0
            for _ in pairs(container.items) do used = used + 1 end
            return container.size - used, container.family
        end,
        GetContainerItemID = function(bag, slot)
            local entry = item(bag, slot)
            if entry then return entry.itemID end
        end,
        GetContainerItemInfo = function(bag, slot)
            local entry = item(bag, slot)
            if not entry then return end
            return {itemID = entry.itemID, stackCount = entry.stackCount, isLocked = entry.isLocked == true}
        end,
        PickupContainerItem = function(bag, slot)
            local entry = item(bag, slot)
            if state.cursor or not entry then return end
            state.bags[bag].items[slot] = nil
            state.cursor = {itemID = entry.itemID, count = entry.stackCount, bag = bag, slot = slot}
            state.emit("CURSOR_CHANGED")
        end,
        SplitContainerItem = function(bag, slot, amount)
            local entry = item(bag, slot)
            equal(amount, 1, "splits exactly one")
            if state.cursor or not entry or entry.stackCount <= amount then return end
            entry.stackCount = entry.stackCount - amount
            state.cursor = {itemID = entry.itemID, count = amount, bag = bag, slot = slot}
            state.emit("CURSOR_CHANGED")
        end,
    }
    env.GetCursorInfo = function()
        if state.cursor then return "item", state.cursor.itemID end
    end
    env.ClearCursor = function()
        local cursor = state.cursor
        if not cursor then return end
        local entry = item(cursor.bag, cursor.slot)
        if entry then
            entry.stackCount = entry.stackCount + cursor.count
        else
            state.bags[cursor.bag].items[cursor.slot] = {itemID = cursor.itemID, stackCount = cursor.count}
        end
        state.cursor = nil
        state.emit("CURSOR_CHANGED")
    end
    -- In client, DeleteCursorItem outside a key press or click raised
    -- ADDON_ACTION_BLOCKED (UNKNOWN()) and left the item on the cursor.
    env.DeleteCursorItem = function()
        if state.deleteBlocked or not state.hardware or (state.combat and state.combatDeleteBlocked) then
            state.emit("ADDON_ACTION_BLOCKED", "WarlockToolsForever", "UNKNOWN()")
            return
        end
        if not state.cursor then return end
        state.deleted = (state.deleted or 0) + state.cursor.count
        state.cursor = nil
        state.emit("CURSOR_CHANGED")
    end

    -- Units, auras, and restrictions for the probe.
    state.units = options.units or {}
    state.units.player = state.units.player or {name = "Dyre", player = true, friend = true, level = 20}
    env.UnitExists = function(unit) return state.units[unit] ~= nil end
    env.UnitIsPlayer = function(unit) return state.units[unit] ~= nil and state.units[unit].player == true end
    env.UnitIsFriend = function(_, unit) return state.units[unit] ~= nil and state.units[unit].friend == true end
    env.UnitLevel = function(unit) return state.units[unit] and state.units[unit].level or 0 end
    env.UnitName = function(unit) return state.units[unit] and state.units[unit].name end
    env.UnitGUID = function(unit) return state.units[unit] and state.units[unit].guid end
    env.UnitCanAttack = function(_, unit) return state.units[unit] ~= nil end
    env.UnitIsUnit = function(a, b) return state.units[a] == state.units[b] end
    -- In client, combat makes index access raise an error for AddOn code.
    local function auras(unit, filter)
        equal(filter, "HARMFUL|PLAYER")
        local data = state.units[unit]
        return data and data.auras or {}
    end
    local function byInstance(unit, id)
        for _, aura in ipairs(auras(unit, "HARMFUL|PLAYER")) do
            if aura.auraInstanceID == id then return aura end
        end
    end
    env.C_UnitAuras = {
        GetAuraDataByIndex = function(unit, index, filter)
            if state.auraIndexRefused then
                error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'WarlockToolsForever'")
            end
            return auras(unit, filter)[index]
        end,
        GetUnitAuraInstanceIDs = function(unit, filter)
            local ids = {}
            for index, aura in ipairs(auras(unit, filter)) do ids[index] = aura.auraInstanceID end
            return ids
        end,
        GetAuraDataByAuraInstanceID = byInstance,
        GetAuraDuration = function(unit, id)
            local aura = byInstance(unit, id)
            if not aura then return end
            return {
                HasSecretValues = function() return state.secrets[aura.expirationTime] == true end,
                GetRemainingDuration = function() return aura.remaining end,
            }
        end,
        GetUnitAuras = function(unit, filter) return auras(unit, filter) end,
        -- In client these may answer in combat: nothing for a secret aura.
        GetAuraDataBySpellName = function(unit, name, filter)
            for _, aura in ipairs(auras(unit, filter)) do
                if aura.name == name then return aura end
            end
        end,
        GetUnitAuraBySpellID = function(unit, spellID)
            for _, aura in ipairs(auras(unit, "HARMFUL|PLAYER")) do
                if aura.spellId == spellID then return aura end
            end
        end,
    }
    env.C_NamePlate = {GetNamePlates = function() return state.nameplates or {} end}
    if not options.noRestrictionAPI then
        env.Enum = {AddOnRestrictionType = {Combat = 0, Encounter = 1, Chat = 5}}
        env.C_RestrictedActions = {GetAddOnRestrictionState = function(kind)
            return (state.restrictions or {})[kind] or 0
        end}
        env.C_CombatLog = {IsCombatLogRestricted = function() return state.combatLogRestricted == true end}
    end

    -- Settings: proxy settings with getters and setters, as the client builds them.
    if not options.noSettings then
        local function newCategory(name, parent)
            local category = {name = name, parent = parent, initializers = {}}
            function category:GetID() return "id:" .. name end
            state.categories[name] = category
            return category
        end
        local function initializer(category, setting, extra)
            local object = {setting = setting, options = extra}
            function object:SetParentInitializer(parent, predicate)
                self.parentInitializer, self.predicate = parent, predicate
            end
            category.initializers[#category.initializers + 1] = object
            return object
        end
        env.MinimalSliderWithSteppersMixin = {Label = {Right = "right"}}
        env.Settings = {
            VarType = {Boolean = "boolean", Number = "number", String = "string"},
            RegisterVerticalLayoutCategory = function(name) return newCategory(name) end,
            RegisterVerticalLayoutSubcategory = function(parent, name) return newCategory(name, parent) end,
            RegisterCanvasLayoutSubcategory = function(parent, frame, name)
                local page = newCategory(name, parent)
                page.frame = frame
                return page
            end,
            RegisterProxySetting = function(category, variable, variableType, name, default, getValue, setValue)
                equal(state.settings[variable], nil, "setting variables are unique")
                local setting = {category = category, variable = variable, type = variableType, name = name,
                    default = default}
                function setting:GetValue() return getValue() end
                function setting:SetValue(value) setValue(value) end
                state.settings[variable] = setting
                return setting
            end,
            RegisterAddOnCategory = function(category) state.registered = category end,
            CreateCheckbox = function(category, setting, tooltip)
                local object = initializer(category, setting)
                object.tooltip = tooltip
                return object
            end,
            CreateSlider = function(category, setting, sliderOptions, tooltip)
                local object = initializer(category, setting, sliderOptions)
                object.tooltip = tooltip
                return object
            end,
            CreateSliderOptions = function(minValue, maxValue, step)
                local object = {minValue = minValue, maxValue = maxValue, step = step}
                function object:SetLabelFormatter(label) self.label = label end
                return object
            end,
            OpenToCategory = function(id) state.opened = id end,
            NotifyUpdate = function(variable) state.notified[#state.notified + 1] = variable end,
        }
    end

    state.worldHooks = {}
    env.UIParent = {}
    env.WorldFrame = {HookScript = function(_, script, callback) state.worldHooks[script] = callback end}
    local function widget(kind, name, parent, template)
        local object = {kind = kind, name = name, parent = parent, template = template, events = {},
            unitEvents = {}, scripts = {}, attributes = {}, points = {}, shown = true, text = ""}
        function object:SetPropagateKeyboardInput(value)
            if not options.noPropagate then self.propagate = value end
        end
        function object:GetPropagateKeyboardInput() return self.propagate == true end
        function object:EnableKeyboard(value) self.keyboard = value end
        function object:RegisterEvent(event)
            if options.restrictCombatLog and event == "COMBAT_LOG_EVENT_UNFILTERED" then
                error("COMBAT_LOG_EVENT_UNFILTERED is restricted")
            end
            self.events[event] = true
            return true
        end
        function object:RegisterUnitEvent(event, unit) self.unitEvents[event] = unit end
        function object:UnregisterEvent(event) self.events[event] = nil end
        function object:SetScript(script, callback) self.scripts[script] = callback end
        function object:GetScript(script) return self.scripts[script] end
        function object:GetName() return self.name end
        -- As in client, secure frames refuse changes in combat.
        function object:SetAttribute(key, value)
            if state.combat then error("SetAttribute in combat") end
            self.attributes[key] = value
        end
        function object:GetAttribute(key) return self.attributes[key] end
        function object:Show()
            if state.combat and self.protected then error("Show in combat") end
            self.shown = true
        end
        function object:Hide()
            if state.combat and self.protected then error("Hide in combat") end
            self.shown = false
        end
        function object:IsShown() return self.shown end
        function object:SetPoint(...) self.points[#self.points + 1] = {...} end
        function object:ClearAllPoints() self.points = {} end
        function object:GetPoint()
            local point = self.points[#self.points]
            return point[1], point[2], point[3], point[4], point[5]
        end
        function object:StartMoving() self.moving = true end
        function object:StopMovingOrSizing() self.moving = false end
        function object:SetText(text) self.text = text end
        function object:GetText() return self.text end
        function object:SetTexture(texture) self.texture = texture end
        function object:SetChecked(value) self.checked = value == true end
        function object:GetChecked() return self.checked end
        function object:CreateTexture() return widget("Texture", nil, self) end
        function object:CreateFontString() return widget("FontString", nil, self) end
        -- Unknown methods (layout, colors, and so on) do nothing here.
        return setmetatable(object, {__index = function(_, key)
            if type(key) == "string" and key:match("^%u") then return function() end end
        end})
    end
    env.CreateFrame = function(kind, name, parent, template)
        local frame = widget(kind, name, parent, template)
        if name then env[name] = frame end
        if template == "SecureActionButtonTemplate" then
            frame.protected = true
            if parent then parent.protected = true end
        end
        state.frames[#state.frames + 1] = frame
        return frame
    end
    function state.emit(event, ...)
        for _, frame in ipairs(state.frames) do
            local unit = frame.unitEvents[event]
            local first = ...
            if frame.events[event] or (unit and unit == first) then
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
    end

    for _, name in ipairs(options.remove or {}) do env[name] = nil end
    state.wtf = {}
    for _, path in ipairs(options.files or RUNTIME_FILES) do
        local chunk, message = loadfile(path)
        if not chunk then error(message) end
        setfenv(chunk, env)
        chunk("WarlockToolsForever", state.wtf)
    end
    env.WarlockToolsForeverDB = options.db
    state.env = env
    state.emit("ADDON_LOADED", "WarlockToolsForever")
    state.emit("PLAYER_LOGIN")

    -- Slash commands, key presses, and world clicks are hardware events.
    local function hardware(action)
        state.hardware = true
        action()
        state.hardware = false
    end
    function state.slash(text) hardware(function() env.SlashCmdList.WARLOCKTOOLSFOREVER(text) end) end
    function state.press()
        hardware(function()
            for _, frame in ipairs(state.frames) do
                if frame.keyboard and frame.scripts.OnKeyDown then frame.scripts.OnKeyDown(frame, "1") end
            end
        end)
    end
    function state.clickButton(name, mouseButton)
        local button = env[name]
        local suffix = mouseButton == "RightButton" and "2" or "1"
        hardware(function()
            state.used = {type = button.attributes["type" .. suffix],
                macrotext = button.attributes["macrotext" .. suffix], spell = button.attributes["spell" .. suffix]}
            -- Secure buttons run PostClick for the press and the release.
            button.scripts.PostClick(button, mouseButton, true)
            button.scripts.PostClick(button, mouseButton, false)
        end)
    end
    function state.click()
        hardware(function() state.worldHooks.OnMouseDown(env.WorldFrame, "RightButton") end)
    end
    function state.put(bag, slot, count, extra)
        local entry = {itemID = SHARD, stackCount = count or 1}
        for key, value in pairs(extra or {}) do entry[key] = value end
        state.bags[bag].items[slot] = entry
    end
    function state.count()
        local total = 0
        for bag = 0, options.reagentBag and 5 or 4 do
            for _, entry in pairs(state.bags[bag].items) do
                if entry.itemID == SHARD then total = total + entry.stackCount end
            end
        end
        return total
    end
    function state.fill(count)
        for slot = 1, count do state.put(0, slot) end
        state.emit("BAG_UPDATE_DELAYED")
    end
    function state.channel(spellID)
        state.emit("UNIT_SPELLCAST_CHANNEL_START", "player", "cast", spellID or DRAIN_SOUL_RANK_4)
    end
    function state.stopChannel(spellID)
        state.emit("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast", spellID or DRAIN_SOUL_RANK_4)
    end
    -- A new shard lands in a slot and the client reports bags settled; gain
    -- then has the player press a key, as play goes on.
    function state.arrive(bag, slot, count)
        state.put(bag, slot, count)
        state.emit("BAG_UPDATE_DELAYED")
    end
    function state.gain(bag, slot, count)
        state.arrive(bag, slot, count)
        state.press()
    end
    function state.last() return state.messages[#state.messages] end
    function state.clear() state.messages = {} end
    return state
end

local function soulBag(size)
    return {
        [0] = {size = 16, family = 0, items = {}},
        [1] = {size = size, family = 4, items = {}},
        [2] = {size = 0, family = 0, items = {}},
        [3] = {size = 0, family = 0, items = {}},
        [4] = {size = 0, family = 0, items = {}},
    }
end

-- Commands ----------------------------------------------------------------------

test("commands are one word; extra words and unknown commands show usage", function()
    local state = fixture()
    local parse = state.wtf.ParseCommand
    equal(parse(""), "")
    equal(parse("  OPTIONS "), "options")
    equal(parse("shards"), "shards")
    equal(parse("debug_restrictions"), "debug_restrictions")
    equal(parse("debug_shards"), "debug_shards")
    local command, usage = parse("shards 10")
    equal(command, nil)
    contains(usage, "/wtf debug_shards")
    equal(parse("dance"), nil)
    equal(parse(nil), nil)
end)
test("/wtf and /wtf options open the settings page", function()
    local state = fixture()
    state.slash("")
    equal(state.opened, "id:Warlock Tools Forever")
    state.opened = nil
    state.slash("options")
    equal(state.opened, "id:Warlock Tools Forever")
end)
test("/warlocktools is a backup slash command", function()
    local state = fixture()
    equal(state.env.SLASH_WARLOCKTOOLSFOREVER1, "/wtf")
    equal(state.env.SLASH_WARLOCKTOOLSFOREVER2, "/warlocktools")
end)
test("another AddOn registering /wtf is reported once at login", function()
    local state = fixture({slashCmdList = {OTHERADDON = function() end},
        globals = {SLASH_OTHERADDON1 = "/other", SLASH_OTHERADDON2 = "/WTF"}})
    local found = 0
    for _, message in ipairs(state.messages) do
        if message:find("Another AddOn (OTHERADDON) also uses /wtf. Use /warlocktools instead.", 1, true) then
            found = found + 1
        end
    end
    equal(found, 1)
end)

-- Login and availability --------------------------------------------------------

test("login prints the banner from the TOC and the ready hint", function()
    local state = fixture()
    equal(state.messages[1], "WTF: Warlock Tools Forever " .. state.toc.Version .. " by Dyre")
    contains(state.messages[2], "Type /wtf to open the settings.")
    equal(state.wtf.available, true)
end)
test("other classes get one message and commands are refused", function()
    local state = fixture({class = "MAGE"})
    equal(state.wtf.available, false)
    contains(state.last(), "is for Warlocks")
    state.clear()
    state.slash("shards")
    contains(state.last(), "Warlock Tools Forever is unavailable")
    equal(state.categories["Warlock Tools Forever"], nil, "no settings page")
end)
test("diagnostics still run when WTF is unavailable", function()
    local state = fixture({class = "MAGE"})
    state.clear()
    state.slash("debug_shards")
    contains(state.messages[1], "debug_shards item=6265 name=Soul Shard")
    state.clear()
    state.slash("debug_restrictions")
    contains(state.messages[1], "debug_restrictions combat=false")
end)
test("a missing client API disables WTF with one message naming it", function()
    local state = fixture({remove = {"DeleteCursorItem"}})
    equal(state.wtf.available, false)
    contains(state.last(), "This client lacks DeleteCursorItem")
    equal(state.categories["Warlock Tools Forever"], nil, "no settings page")
end)
test("a mixed install of old and new files is reported at login", function()
    local state = fixture({files = {"Commands.lua", "Core.lua", "Shards.lua", "Stones.lua", "Announce.lua",
        "Options.lua"}})
    equal(state.wtf.available, false)
    contains(state.last(), "missing ReportRestrictions")
end)

-- Saved settings ---------------------------------------------------------------

test("saved settings get defaults and are repaired on load", function()
    local state = fixture()
    local shards = state.wtf.db.shards
    equal(shards.enabled, true)
    equal(shards.autoLimit, true)
    equal(shards.limit, 6)
    equal(shards.report, true)
    local repaired = fixture({db = {shards = {enabled = false, autoLimit = false, limit = 900, report = "x"}}})
    equal(repaired.wtf.db.shards.enabled, false)
    equal(repaired.wtf.db.shards.limit, 60)
    equal(repaired.wtf.db.shards.report, true)
    equal(fixture({db = {shards = {limit = 2.5}}}).wtf.db.shards.limit, 6)
    equal(fixture({db = {shards = {limit = 0}}}).wtf.db.shards.limit, 1)
    equal(fixture({db = "broken"}).wtf.db.shards.enabled, true)
end)

-- Shard limit ------------------------------------------------------------------

test("the limit matches the soul bag size, or 6 without a soul bag", function()
    local state = fixture()
    local limit, source = state.wtf.GetShardLimit()
    equal(limit, 6)
    equal(source, "default")
    local bagged = fixture({bags = soulBag(20)})
    limit, source = bagged.wtf.GetShardLimit()
    equal(limit, 20)
    equal(source, "soul bag")
end)
test("several soul bags add up, and other bag families are ignored", function()
    local bags = soulBag(20)
    bags[2] = {size = 16, family = 4 + 1, items = {}}
    bags[3] = {size = 18, family = 1, items = {}}
    local state = fixture({bags = bags})
    equal(state.wtf.GetShardLimit(), 36)
end)
test("a manual limit replaces the soul bag size", function()
    local state = fixture({bags = soulBag(20), db = {shards = {autoLimit = false, limit = 4}}})
    local limit, source = state.wtf.GetShardLimit()
    equal(limit, 4)
    equal(source, "manual")
end)

-- Deleting created shards ------------------------------------------------------

test("a created shard waits for the next key press, then is deleted", function()
    local state = fixture()
    state.fill(6)
    state.channel()
    state.arrive(1, 3)
    equal(state.count(), 7, "game events cannot delete")
    equal(state.cursor, nil)
    state.press()
    equal(state.count(), 6)
end)
test("a click on the game world also deletes a waiting shard", function()
    local state = fixture()
    state.fill(6)
    state.channel()
    state.arrive(1, 3)
    state.click()
    equal(state.count(), 6)
end)
test("the key hook passes every key on to the game", function()
    local state = fixture()
    local hooked
    for _, frame in ipairs(state.frames) do
        if frame.keyboard then hooked = frame end
    end
    equal(hooked.propagate, true)
    equal(type(hooked.scripts.OnKeyDown), "function")
end)
test("without confirmed key propagation the keyboard is never captured", function()
    local state = fixture({noPropagate = true})
    for _, frame in ipairs(state.frames) do
        equal(frame.keyboard, nil, "no keyboard frame")
    end
    state.fill(6)
    state.channel()
    state.arrive(1, 1)
    state.click()
    equal(state.count(), 6, "clicks still work")
end)
test("a shard Drain Soul creates above the limit is deleted", function()
    local state = fixture()
    state.fill(6)
    state.clear()
    state.channel()
    state.gain(1, 3)
    equal(state.count(), 6)
    equal(state.deleted, 1)
    equal(state.bags[1].items[3], nil, "the new shard went")
    equal(state.cursor, nil)
    equal(state.last(), "WTF: Deleted a Soul Shard above your limit of 6.")
end)
test("shards in a reagent bag are carried shards", function()
    local bags = soulBag(0)
    bags[5] = {size = 12, family = 0, items = {}}
    local state = fixture({bags = bags, reagentBag = true})
    for slot = 1, 6 do state.put(5, slot) end
    state.emit("BAG_UPDATE_DELAYED")
    equal(state.wtf.CountShards(), 6)
    state.channel()
    state.gain(5, 7)
    equal(state.count(), 6)
    equal(state.bags[5].items[7], nil)
end)
test("every Drain Soul rank counts as a source", function()
    local state = fixture()
    state.fill(6)
    state.channel(1120)
    state.gain(1, 1)
    equal(state.count(), 6)
end)
test("a created shard within the limit is kept", function()
    local state = fixture()
    state.fill(5)
    state.channel()
    state.gain(1, 1)
    equal(state.count(), 6)
    equal(state.deleted, nil)
end)
test("a shard arriving just after the channel ends still counts as created", function()
    local state = fixture()
    state.fill(6)
    state.channel()
    state.stopChannel()
    state.now = state.now + 2.5
    state.gain(1, 1)
    equal(state.count(), 6)
end)
test("a shard arriving after the creation window is kept", function()
    local state = fixture()
    state.fill(6)
    state.channel()
    state.stopChannel()
    state.now = state.now + 4
    state.gain(1, 1)
    equal(state.count(), 7)
end)
test("shards moved in from the bank are never deleted, even above the limit", function()
    local state = fixture()
    state.fill(6)
    state.put(1, 1)
    state.put(1, 2)
    state.emit("BAG_UPDATE_DELAYED")
    equal(state.count(), 8)
    equal(state.deleted, nil)
end)
test("above the limit by hand, only the newly created shard is deleted", function()
    local state = fixture()
    state.fill(10)
    state.channel()
    state.gain(1, 4)
    equal(state.count(), 10, "the ten moved in stay")
    equal(state.bags[1].items[4], nil)
    for slot = 1, 10 do
        equal(state.bags[0].items[slot] ~= nil, true, "old shard in slot " .. slot)
    end
end)
test("other spells open no creation window", function()
    local state = fixture()
    state.fill(6)
    state.channel(SHADOW_BOLT)
    state.gain(1, 1)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", SHADOW_BOLT)
    state.gain(1, 2)
    equal(state.count(), 8)
end)
test("spell events for other units are ignored", function()
    local state = fixture()
    state.fill(6)
    state.emit("UNIT_SPELLCAST_CHANNEL_START", "party1", "cast", DRAIN_SOUL_RANK_4)
    state.gain(1, 1)
    equal(state.count(), 7)
end)
test("nothing is deleted while Soul Shard management is off", function()
    local state = fixture({db = {shards = {enabled = false}}})
    state.fill(6)
    state.channel()
    state.gain(1, 1)
    equal(state.count(), 7)
end)
test("debug_delete deletes one shard above the limit, from the last shard slot", function()
    local state = fixture({db = {shards = {autoLimit = false, limit = 2}}})
    state.fill(3)
    state.put(1, 4)
    state.emit("BAG_UPDATE_DELAYED")
    state.clear()
    state.slash("debug_delete")
    equal(state.count(), 3)
    equal(state.bags[1].items[4], nil)
    equal(state.last(), "WTF: debug_delete deleted one shard from bag 1 slot 4; 3 carried now.")
end)
test("debug_delete refuses in combat, with a busy cursor, or within the limit", function()
    local state = fixture()
    state.fill(3)
    state.clear()
    state.slash("debug_delete")
    equal(state.last(), "WTF: debug_delete nothing to delete: 3 carried, limit 6.")
    state.combat = true
    state.slash("debug_delete")
    equal(state.last(), "WTF: debug_delete works out of combat only.")
    state.combat = false
    state.cursor = {itemID = 4306, count = 1, bag = 1, slot = 9}
    state.slash("debug_delete")
    equal(state.last(), "WTF: debug_delete empty your cursor first.")
    equal(state.count(), 3)
end)
test("debug_delete reports a blocked deletion and keeps the shard", function()
    local state = fixture({db = {shards = {autoLimit = false, limit = 2}}})
    state.fill(3)
    state.deleteBlocked = true
    state.clear()
    state.slash("debug_delete")
    equal(state.count(), 3)
    equal(state.cursor, nil)
    contains(state.last(), "debug_delete the client blocked it; the shard is back in bag 0.")
end)
test("a soul bag in the reagent bag slot sets the limit", function()
    -- In client, a 14-slot soul bag sat in bag 5, the reagent slot.
    local bags = soulBag(0)
    bags[1].family = 0
    bags[5] = {size = 14, family = 4, items = {}}
    local state = fixture({bags = bags, reagentBag = true})
    local limit, source = state.wtf.GetShardLimit()
    equal(limit, 14)
    equal(source, "soul bag")
end)
test("the soul bag size is the limit when matching it", function()
    local state = fixture({bags = soulBag(8)})
    for slot = 1, 8 do state.put(1, slot) end
    state.emit("BAG_UPDATE_DELAYED")
    state.channel()
    state.gain(0, 1)
    equal(state.count(), 8)
end)
test("one shard from a stack is split off and deleted", function()
    local state = fixture()
    state.put(0, 1, 6)
    state.emit("BAG_UPDATE_DELAYED")
    state.channel()
    state.bags[0].items[1].stackCount = 7
    state.emit("BAG_UPDATE_DELAYED")
    state.press()
    equal(state.bags[0].items[1].stackCount, 6)
    equal(state.deleted, 1)
end)
test("a deletion waits while the cursor holds something", function()
    local state = fixture()
    state.fill(6)
    state.channel()
    state.cursor = {itemID = 4306, count = 1, bag = 1, slot = 9}
    state.gain(1, 1)
    equal(state.count(), 7, "kept while the cursor is busy")
    equal(state.cursor.itemID, 4306, "the user's item stays on the cursor")
    state.cursor = nil
    state.press()
    equal(state.count(), 6)
end)
test("a deletion waits for a locked shard to unlock", function()
    local state = fixture()
    state.fill(6)
    state.channel()
    state.put(1, 1, 1, {isLocked = true})
    state.emit("BAG_UPDATE_DELAYED")
    state.press()
    equal(state.count(), 7)
    state.bags[1].items[1].isLocked = false
    state.press()
    equal(state.count(), 6)
end)
test("a queued deletion waits for input however long it takes", function()
    local state = fixture()
    state.fill(6)
    state.channel()
    state.arrive(1, 1)
    state.now = state.now + 600
    state.press()
    equal(state.count(), 6)
end)
test("a queued deletion is dropped once the count is back within the limit", function()
    local state = fixture()
    state.fill(6)
    state.channel()
    state.arrive(1, 1)
    state.bags[0].items[1] = nil
    state.press()
    equal(state.count(), 6)
    equal(state.deleted, nil)
end)
test("shards created in combat are deleted on a key press in combat", function()
    local state = fixture()
    state.fill(6)
    state.combat = true
    state.channel()
    state.gain(1, 1)
    equal(state.count(), 6)
end)
test("if the client refuses in combat, shards wait for input after combat", function()
    local state = fixture()
    state.fill(6)
    state.combat = true
    state.combatDeleteBlocked = true
    state.channel()
    state.clear()
    state.gain(1, 1)
    state.gain(1, 2)
    equal(state.count(), 8)
    equal(state.cursor, nil, "the shard is back in the bag")
    equal(#state.messages, 0, "no message for a refusal in combat")
    state.press()
    equal(state.count(), 8, "no retry in combat")
    state.combat = false
    state.press()
    equal(state.count(), 6, "both go on the first key press after combat")
    equal(state.bags[1].items[1], nil)
    equal(state.bags[1].items[2], nil)
end)
test("a deletion blocked out of combat puts the shard back, reports once, and stops", function()
    local state = fixture()
    state.fill(6)
    state.deleteBlocked = true
    state.channel()
    state.clear()
    state.gain(1, 1)
    equal(state.count(), 7)
    equal(state.cursor, nil, "the shard is back in the bag")
    equal(state.bags[1].items[1].itemID, SHARD)
    equal(#state.messages, 1)
    contains(state.last(), "Soul Shard deletion stopped: the client blocked it.")
    state.deleteBlocked = false
    state.gain(1, 2)
    equal(state.count(), 8, "no more deletions until /reload")
    equal(#state.messages, 1)
end)
test("a blocked-action event outside a deletion never stops deletion", function()
    -- In client, the probe's old combat log registration raised
    -- ADDON_ACTION_BLOCKED for WTF with function UNKNOWN().
    local state = fixture()
    state.emit("ADDON_ACTION_BLOCKED", "WarlockToolsForever", "UNKNOWN()")
    state.emit("ADDON_ACTION_FORBIDDEN", "SomeOtherAddOn", "DeleteCursorItem()")
    state.fill(6)
    state.channel()
    state.clear()
    state.gain(1, 1)
    equal(state.count(), 6)
    equal(state.last(), "WTF: Deleted a Soul Shard above your limit of 6.")
end)
test("a blocked-action event raised by the deletion stops deletion", function()
    local state = fixture()
    state.env.DeleteCursorItem = function()
        state.emit("ADDON_ACTION_FORBIDDEN", "WarlockToolsForever", "DeleteCursorItem()")
        state.cursor = nil
    end
    state.fill(6)
    state.channel()
    state.clear()
    state.gain(1, 1)
    equal(#state.messages, 1)
    contains(state.last(), "Soul Shard deletion stopped: the client blocked it.")
end)
test("a secret spell ID opens no window and is shown in debug_shards", function()
    local state = fixture()
    state.fill(6)
    local hidden = secret()
    state.secrets[hidden] = true
    state.channel(hidden)
    state.gain(1, 1)
    equal(state.count(), 7)
    state.clear()
    state.slash("debug_shards")
    local status, newest
    for _, message in ipairs(state.messages) do
        if message:find("secretCasts=", 1, true) then status = message end
        if not newest and message:find("gain ", 1, true) then newest = message end
    end
    contains(status, "secretCasts=true")
    contains(newest, "created=false combat=false last=UNIT_SPELLCAST_CHANNEL_START secret")
end)
test("the login scan is a baseline, not a gain", function()
    local state = fixture()
    state.put(0, 1)
    state.put(0, 2)
    state.emit("PLAYER_ENTERING_WORLD")
    state.channel()
    state.emit("BAG_UPDATE_DELAYED")
    equal(state.count(), 2)
end)
test("deletion reports can be turned off", function()
    local state = fixture({db = {shards = {report = false}}})
    state.fill(6)
    state.channel()
    state.clear()
    state.gain(1, 1)
    equal(state.count(), 6)
    equal(#state.messages, 0)
end)

-- Status and diagnostics -------------------------------------------------------

test("/wtf shards reports the count, limit, source, and deletion state", function()
    local state = fixture({bags = soulBag(20)})
    state.fill(3)
    state.slash("shards")
    equal(state.last(), "WTF: Soul Shards: 3 carried, limit 20 (your soul bag size). Deletion is on.")
    local manual = fixture({db = {shards = {autoLimit = false, limit = 4, enabled = false}}})
    manual.slash("shards")
    equal(manual.last(), "WTF: Soul Shards: 0 carried, limit 4 (set by you). Deletion is off.")
end)
test("debug_shards lists bags, the source spell, and recent gains", function()
    local state = fixture({bags = soulBag(12)})
    state.fill(2)
    state.channel()
    state.now = state.now + 1
    state.gain(1, 1)
    state.clear()
    state.slash("debug_shards")
    contains(state.messages[1], "debug_shards item=6265 name=Soul Shard")
    contains(state.messages[2], "source spell=1120 name=Drain Soul")
    contains(state.messages[3], "NUM_BAG_SLOTS=4 NUM_TOTAL_EQUIPPED_BAG_SLOTS=nil itemCount=0")
    contains(state.messages[5], "bag=1 slots=12 family=4 soul=true items=1 shards=1 shardSlotsByID=1 noInfo=0")
    contains(state.messages[9], "count=3 limit=12 source=soul bag")
    contains(state.messages[10], "gain 0.0s ago +1 count=3 created=true combat=false last=UNIT_SPELLCAST_CHANNEL_START 11675 1.0s before")
end)
local function reported(state, fragment)
    for _, message in ipairs(state.messages) do
        if message:find(fragment, 1, true) then return message end
    end
    error("no message containing " .. fragment .. " in:\n" .. table.concat(state.messages, "\n"), 2)
end

test("debug_restrictions reports states and never reads secret contents", function()
    local hiddenName, hiddenSpell, hiddenTime, hiddenLeft = secret(), secret(), secret(), secret()
    local state = fixture({units = {target = {name = hiddenName, guid = "Creature-1",
        auras = {{name = "Corruption", spellId = hiddenSpell, icon = 136118, duration = 18,
            expirationTime = hiddenTime, remaining = hiddenLeft, applications = 0, auraInstanceID = 7}}}}})
    for _, value in ipairs({hiddenName, hiddenSpell, hiddenTime, hiddenLeft}) do state.secrets[value] = true end
    state.restrictions = {[0] = 2}
    state.combat = true
    state.clear()
    state.slash("debug_restrictions")
    equal(state.messages[1], "WTF: debug_restrictions combat=true secretAPI=true")
    contains(state.messages[2], "states Combat=active Encounter=inactive Chat=inactive")
    equal(state.messages[3], "WTF: debug_restrictions combatLog restricted=false")
    reported(state, "target name=secret guid=Creature-1 canAttack=true")
    reported(state, "target byIndex 1: name=Corruption spellId=secret icon=136118 duration=18 expires=secret")
    reported(state, "target instanceIDs count=1")
    reported(state, "target instance 7: name=Corruption spellId=secret")
    reported(state, "duration object secretValues=true remaining=secret")
    reported(state, "target getUnitAuras count=1")
    reported(state, "focus none")
    reported(state, "nameplates frames=0 units=0")
    for _, message in ipairs(state.messages) do
        equal(message:find("failed", 1, true), nil, "no probe failure")
    end
end)
test("a refused aura API is reported and the other checks still run", function()
    local state = fixture({units = {target = {name = "Great Goretusk", guid = "Creature-2",
        auras = {{name = "Corruption", spellId = 172, auraInstanceID = 3, remaining = 12}}}}})
    state.auraIndexRefused = true
    state.combat = true
    state.clear()
    state.slash("debug_restrictions")
    contains(reported(state, "target byIndex failed:"), "Auras cannot be accessed when secret")
    reported(state, "target instance 3: name=Corruption spellId=172")
    reported(state, "duration object secretValues=false remaining=12")
    reported(state, "focus none")
    reported(state, "nameplates frames=0 units=0")
end)
test("debug_restrictions reports the player's last cast and its target", function()
    local state = fixture()
    local hiddenTarget = secret()
    state.secrets[hiddenTarget] = true
    state.emit("UNIT_SPELLCAST_SENT", "player", hiddenTarget, "cast", 172)
    state.now = state.now + 0.5
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 172)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast", 686)
    state.clear()
    state.slash("debug_restrictions")
    equal(state.messages[4],
        "WTF: debug_restrictions lastCast sent=0.5s ago target=secret spell=172; succeeded=0.0s ago spell=172")
end)
test("debug_restrictions looks up auras by spell name, Banes included, and by the last cast", function()
    local state = fixture({units = {target = {name = "Boar", guid = "Creature-4", auras = {
        {name = "Corruption", spellId = 6222, auraInstanceID = 1},
        {name = "Bane of Agony", spellId = 99999, auraInstanceID = 2}}}}})
    state.auraIndexRefused = true
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 6222)
    state.clear()
    state.slash("debug_restrictions")
    reported(state, "target byName Corruption: name=Corruption spellId=6222")
    reported(state, "target byName Bane of Agony: name=Bane of Agony spellId=99999")
    reported(state, "target byName checked=5 found=2")
    reported(state, "target bySpellID 6222: name=Corruption spellId=6222")
end)
test("a secret last cast is not used for a spell ID lookup", function()
    local state = fixture({units = {target = {name = "Boar", guid = "Creature-5"}}})
    local hidden = secret()
    state.secrets[hidden] = true
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", hidden)
    state.clear()
    state.slash("debug_restrictions")
    reported(state, "target bySpellID: no readable last cast")
end)
test("debug_restrictions never registers for the combat log", function()
    local state = fixture({restrictCombatLog = true})
    state.combatLogRestricted = true
    state.clear()
    state.slash("debug_restrictions")
    equal(state.messages[3], "WTF: debug_restrictions combatLog restricted=true")
    for _, message in ipairs(state.messages) do
        equal(message:find("failed", 1, true), nil, "no probe failure")
    end
end)
test("debug_restrictions works without the restriction API", function()
    local state = fixture({noRestrictionAPI = true})
    state.clear()
    state.slash("debug_restrictions")
    contains(state.messages[2], "restriction API missing")
    contains(state.messages[3], "combatLog restricted=n/a")
end)
test("debug_restrictions finds nameplate units by token, not from plate frames", function()
    local state = fixture({units = {nameplate3 = {name = "Wolf", guid = "Creature-3", auras = {}}}})
    state.nameplates = {{}, {}}
    state.clear()
    state.slash("debug_restrictions")
    reported(state, "nameplates frames=2 units=1")
    reported(state, "nameplate3 name=Wolf")
    reported(state, "nameplate3 byIndex: none of yours")
    reported(state, "nameplate3 instanceIDs count=0")
end)

-- Stones -----------------------------------------------------------------------

local SOUL = "WarlockToolsForeverSoulstone"
local HEALTH = "WarlockToolsForeverHealthstone"

local function stonesFixture(extra)
    local options = {known = {[693] = true, [20752] = true, [6201] = true, [6202] = true, [5699] = true},
        carried = {[16892] = 1, [5232] = 2, [5511] = 1}}
    for key, value in pairs(extra or {}) do options[key] = value end
    return fixture(options)
end

test("stone buttons use the best stone carried and create the best rank known", function()
    local state = stonesFixture()
    local soul, health = state.env[SOUL], state.env[HEALTH]
    equal(soul.attributes.type1, "macro")
    equal(soul.attributes.macrotext1, "/use [@target,help,nodead][@player] item:16892")
    equal(soul.attributes.type2, "spell")
    equal(soul.attributes.spell2, 20752)
    equal(health.attributes.macrotext1, "/use item:5511")
    equal(health.attributes.spell2, 5699, "no player target: the best known rank")
    equal(soul.count.text, 3)
    equal(health.count.text, 1)
    equal(soul.icon.texture, 1000 + 16892)
end)
test("right-click creates the best Healthstone a friendly player target can use", function()
    local state = stonesFixture({units = {target = {name = "Lowbie", player = true, friend = true, level = 20}}})
    equal(state.env[HEALTH].attributes.spell2, 6202, "Healthstone needs level 24")
    state.units.target.level = 30
    state.emit("PLAYER_TARGET_CHANGED")
    equal(state.env[HEALTH].attributes.spell2, 5699)
    state.units.target = {name = "Boar", level = 5}
    state.emit("PLAYER_TARGET_CHANGED")
    equal(state.env[HEALTH].attributes.spell2, 5699, "a mob target does not limit the rank")
end)
test("an uncached level requirement skips that rank until item data arrives", function()
    local state = stonesFixture({units = {target = {name = "Lowbie", player = true, friend = true, level = 40}}})
    equal(state.requested, 5, "level requirements are requested at login")
    ITEMS[5509][2] = nil
    state.emit("PLAYER_TARGET_CHANGED")
    equal(state.env[HEALTH].attributes.spell2, 6202)
    ITEMS[5509][2] = 24
    state.emit("GET_ITEM_INFO_RECEIVED")
    equal(state.env[HEALTH].attributes.spell2, 5699)
end)
test("with no stones or ranks, clicks explain what is missing, once per click", function()
    local state = fixture()
    local soul = state.env[SOUL]
    equal(soul.attributes.type1, nil)
    equal(soul.attributes.type2, nil)
    state.clear()
    state.clickButton(SOUL, "LeftButton")
    equal(#state.messages, 1)
    equal(state.last(), "WTF: No Soulstone in your bags. Right-click to create one.")
    state.now = state.now + 1
    state.clickButton(HEALTH, "RightButton")
    equal(state.last(), "WTF: You do not know Create Healthstone yet.")
end)
test("a Soulstone click in combat explains that it cannot be applied", function()
    local state = stonesFixture()
    state.combat = true
    state.clear()
    state.clickButton(SOUL, "LeftButton")
    equal(#state.messages, 1)
    equal(state.last(), "WTF: Soulstones cannot be applied in combat.")
    equal(state.used.macrotext, "/use [@target,help,nodead][@player] item:16892")
end)
test("stone button changes in combat wait for combat to end", function()
    local state = stonesFixture()
    state.combat = true
    state.carried[16892] = 0
    state.emit("BAG_UPDATE_DELAYED")
    equal(state.env[SOUL].attributes.macrotext1, "/use [@target,help,nodead][@player] item:16892")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(state.env[SOUL].attributes.macrotext1, "/use [@target,help,nodead][@player] item:5232")
end)
test("the Stones bar follows the module and show settings, after combat if needed", function()
    local state = stonesFixture()
    local bar = state.env.WarlockToolsForeverStones
    equal(bar.shown, true)
    state.settings.WTF_STONES_SHOWN:SetValue(false)
    equal(bar.shown, false)
    state.settings.WTF_STONES_SHOWN:SetValue(true)
    state.combat = true
    state.settings.WTF_STONES_ENABLED:SetValue(false)
    equal(bar.shown, true, "unchanged in combat")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(bar.shown, false)
end)
test("the Stones bar drags unless locked or in combat, and remembers its place", function()
    local state = stonesFixture()
    local bar, soul = state.env.WarlockToolsForeverStones, state.env[SOUL]
    soul.scripts.OnDragStart(soul)
    equal(bar.moving, true)
    bar:SetPoint("TOPLEFT", nil, "TOPLEFT", 10, -20)
    soul.scripts.OnDragStop(soul)
    equal(state.wtf.db.stones.position.x, 10)
    state.wtf.db.stones.locked = true
    soul.scripts.OnDragStart(soul)
    equal(bar.moving, false)
    state.wtf.db.stones.locked = false
    state.combat = true
    bar.scripts.OnDragStart(bar)
    equal(bar.moving, false)
end)
test("/wtf reset moves the Stones bar back, after combat if needed", function()
    local state = stonesFixture({db = {stones = {position = {point = "TOP", relativePoint = "TOP", x = 1, y = 2}}}})
    local bar = state.env.WarlockToolsForeverStones
    equal(bar.points[1][1], "TOP")
    state.combat = true
    state.slash("reset")
    equal(state.wtf.db.stones.position, nil)
    contains(state.last(), "moves back after combat")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(bar.points[1][1], "CENTER")
end)
test("the stone tooltip explains both clicks and the macro name", function()
    local state = stonesFixture()
    local soul = state.env[SOUL]
    soul.scripts.OnEnter(soul)
    equal(state.tooltip[1], "Soulstone")
    contains(state.tooltip[2], "Left-click: use Lesser Soulstone on your friendly target, or on yourself.")
    contains(state.tooltip[3], "Right-click: create Lesser Soulstone.")
    contains(state.tooltip[5], "/click WarlockToolsForeverSoulstone")
end)
test("debug_stones lists ranks, carried stones, and level requirements", function()
    local state = stonesFixture()
    state.clear()
    state.slash("debug_stones")
    contains(state.messages[2], "soulstone spell=20752 name=Create Soulstone (Lesser) known=true items=16892x1 minLevel=30")
    contains(state.messages[6], "healthstone spell=6201 name=Create Healthstone (Minor) known=true items=5512x0,19004x0,19005x0 minLevel=1")
    contains(state.last(), "targetLevel=nil healthstoneRank=5699 pending=false")
end)
test("without the spellbook API, Stones stay off and the rest of WTF runs", function()
    local state = fixture({noSpellBook = true})
    equal(state.wtf.available, true)
    equal(state.env.WarlockToolsForeverStones, nil)
    local found
    for _, message in ipairs(state.messages) do
        if message:find("Stones stay off: this client lacks C_SpellBook.IsSpellKnown.", 1, true) then found = true end
    end
    equal(found, true)
end)

-- Announce ---------------------------------------------------------------------

local function cast(state, spellID, target, outcome)
    state.emit("UNIT_SPELLCAST_SENT", "player", target, "cast-" .. spellID, spellID)
    state.emit(outcome or "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-" .. spellID, spellID)
end

test("a summon tells the party and whispers the target", function()
    local state = fixture({group = "party"})
    cast(state, 698, "Friend")
    equal(#state.sent, 2)
    equal(state.sent[1].message, "Summoning >> Friend << click please")
    equal(state.sent[1].chatType, "PARTY")
    equal(state.sent[2].chatType, "WHISPER")
    equal(state.sent[2].target, "Friend")
    contains(state.sent[2].message, "Summoning you to Redridge Mountains now.")
end)
test("a Soulstone use tells the raid and whispers the author's text", function()
    local state = fixture({group = "raid"})
    cast(state, 20762, "Tank")
    equal(state.sent[1].message, "Soulstone on >> Tank <<")
    equal(state.sent[1].chatType, "RAID")
    contains(state.sent[2].message, "die in a good spot")
end)
test("alone, only the whisper goes out", function()
    local state = fixture()
    cast(state, 698, "Friend")
    equal(#state.sent, 1)
    equal(state.sent[1].chatType, "WHISPER")
end)
test("failed casts, yourself, other spells, and secret targets announce nothing", function()
    local state = fixture({group = "party"})
    cast(state, 698, "Friend", "UNIT_SPELLCAST_FAILED")
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-698", 698)
    cast(state, 20707, "Dyre")
    cast(state, 686, "Boar")
    local hidden = secret()
    state.secrets[hidden] = true
    cast(state, 698, hidden)
    equal(#state.sent, 0)
end)
test("each message has its own switch, and the module switch silences all", function()
    local state = fixture({group = "party", db = {announce = {summonWhisper = false}}})
    cast(state, 698, "Friend")
    equal(#state.sent, 1)
    equal(state.sent[1].chatType, "PARTY")
    state.settings.WTF_ANNOUNCE_ENABLED:SetValue(false)
    cast(state, 20707, "Friend")
    equal(#state.sent, 1)
end)
test("Say sends to SAY, and a blocked Say is reported once", function()
    local state = fixture({db = {announce = {channel = "say"}}})
    cast(state, 698, "Friend")
    equal(state.sent[1].chatType, "SAY")
    state.sayBlocked = true
    state.clear()
    cast(state, 698, "Friend")
    cast(state, 698, "Friend")
    equal(#state.messages, 1)
    contains(state.last(), "blocked the Say announcement")
end)
test("names and zones with percent signs are inserted literally", function()
    local state = fixture()
    state.zone = "100% Zone"
    equal(state.wtf.FormatAnnouncement("%T in %Z (%T)", "A%1b"), "A%1b in 100% Zone (A%1b)")
end)
test("announcement texts are repaired on load", function()
    local state = fixture({db = {announce = {summonGroupText = "  Come >> %T <<  ",
        summonWhisperText = "", soulstoneGroupText = string.rep("x", 256), soulstoneWhisperText = "a\nb",
        channel = "shout"}}})
    local settings = state.wtf.db.announce
    equal(settings.summonGroupText, "Come >> %T <<")
    equal(settings.summonWhisperText, state.wtf.ANNOUNCE_DEFAULTS.summonWhisperText)
    equal(settings.soulstoneGroupText, state.wtf.ANNOUNCE_DEFAULTS.soulstoneGroupText)
    equal(settings.soulstoneWhisperText, state.wtf.ANNOUNCE_DEFAULTS.soulstoneWhisperText)
    equal(settings.channel, "group")
end)
test("the Announce page edits texts, switches, and the channel", function()
    local state = fixture()
    local page = state.categories.Announce.frame
    page:OnRefresh()
    local row = page.rows[1]
    equal(row.edit.text, "Summoning >> %T << click please")
    row.edit.text = "  Port >> %T <<  "
    row.edit.scripts.OnEnterPressed(row.edit)
    equal(state.wtf.db.announce.summonGroupText, "Port >> %T <<")
    row.edit.text = "typing"
    row.edit.scripts.OnEscapePressed(row.edit)
    equal(row.edit.text, "Port >> %T <<", "Escape undoes the edit")
    row.check.checked = false
    row.check.scripts.OnClick(row.check)
    equal(state.wtf.db.announce.summonGroup, false)
    page.channels[2].scripts.OnClick(page.channels[2])
    equal(state.wtf.db.announce.channel, "say")
    equal(page.channels[1].checked, false)
    page:OnDefault()
    equal(state.wtf.db.announce.channel, "group")
    equal(state.wtf.db.announce.summonGroup, true)
    equal(state.wtf.db.announce.summonGroupText, "Summoning >> %T << click please")
end)

-- Settings page ----------------------------------------------------------------

test("the settings page has a module switch and a Soul Shards subpage", function()
    local state = fixture()
    local main = state.categories["Warlock Tools Forever"]
    local page = state.categories["Soul Shards"]
    equal(state.registered, main)
    equal(page.parent, main)
    equal(main.initializers[1].setting.variable, "WTF_SHARDS_ENABLED")
    equal(main.initializers[2].setting.variable, "WTF_STONES_ENABLED")
    equal(main.initializers[3].setting.variable, "WTF_ANNOUNCE_ENABLED")
    equal(state.categories.Stones.parent, main)
    equal(state.categories.Announce.parent, main)
    equal(page.initializers[1].setting.variable, "WTF_SHARDS_AUTO_LIMIT")
    equal(page.initializers[2].setting.variable, "WTF_SHARDS_LIMIT")
    equal(page.initializers[3].setting.variable, "WTF_SHARDS_REPORT")
    local slider = page.initializers[2].options
    equal(slider.minValue, 1)
    equal(slider.maxValue, 60)
    equal(slider.step, 1)
    equal(slider.label, "right")
end)
test("settings read and write the saved shard settings", function()
    local state = fixture()
    state.settings.WTF_SHARDS_ENABLED:SetValue(false)
    equal(state.wtf.db.shards.enabled, false)
    state.settings.WTF_SHARDS_REPORT:SetValue(false)
    equal(state.wtf.db.shards.report, false)
    equal(state.settings.WTF_SHARDS_REPORT:GetValue(), false)
end)
test("the limit slider shows the soul bag size and is disabled while matching it", function()
    local state = fixture({bags = soulBag(16)})
    local page = state.categories["Soul Shards"]
    local slider = page.initializers[2]
    equal(state.settings.WTF_SHARDS_LIMIT:GetValue(), 16)
    equal(slider.parentInitializer, page.initializers[1])
    equal(slider.predicate(), false)
    state.settings.WTF_SHARDS_LIMIT:SetValue(3)
    equal(state.wtf.GetShardLimit(), 16, "ignored while matching the soul bag")
end)
test("turning off the soul bag match keeps the current limit as the manual one", function()
    local state = fixture({bags = soulBag(16)})
    state.settings.WTF_SHARDS_AUTO_LIMIT:SetValue(false)
    equal(state.wtf.db.shards.autoLimit, false)
    equal(state.wtf.db.shards.limit, 16)
    equal(state.notified[#state.notified], "WTF_SHARDS_LIMIT")
    equal(state.categories["Soul Shards"].initializers[2].predicate(), true)
    state.settings.WTF_SHARDS_LIMIT:SetValue(9)
    equal(state.wtf.GetShardLimit(), 9)
end)
test("without the Settings API WTF runs and /wtf explains", function()
    local state = fixture({noSettings = true})
    equal(state.wtf.available, true)
    state.slash("")
    contains(state.last(), "settings page is unavailable")
end)

local failed = 0
for index, entry in ipairs(tests) do
    local ok, message = xpcall(entry.body, debug.traceback)
    if ok then
        io.write("ok ", index, " - ", entry.name, "\n")
    else
        failed = failed + 1
        io.write("not ok ", index, " - ", entry.name, "\n", tostring(message), "\n")
    end
end
io.write(string.format("\n%d tests: %d passed, %d failed\n", #tests, #tests - failed, failed))
io.write("Mock results do not establish in-client compatibility.\n")
os.exit(failed == 0 and 0 or 1)
