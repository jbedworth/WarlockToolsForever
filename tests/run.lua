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

local RUNTIME_FILES = {"Commands.lua", "Core.lua", "Layout.lua", "Shards.lua", "Stones.lua", "Announce.lua", "Tracker.lua",
    "Dots.lua", "Control.lua", "Alerts.lua", "Shield.lua", "Chimes.lua", "Reminders.lua", "Probe.lua", "Options.lua"}
local SHARD = 6265
local SPELLS = {[1120] = "Drain Soul", [11675] = "Drain Soul", [686] = "Shadow Bolt", [172] = "Corruption",
    [6222] = "Corruption", [980] = "Curse of Agony", [698] = "Ritual of Summoning",
    [20707] = "Soulstone Resurrection", [20762] = "Soulstone Resurrection",
    [693] = "Create Soulstone", [20752] = "Create Soulstone",
    [17877] = "Shadowburn", [18871] = "Shadowburn",
    [348] = "Immolate", [18265] = "Siphon Life", [5782] = "Fear", [702] = "Curse of Weakness",
    [6201] = "Create Healthstone", [6202] = "Create Healthstone", [5699] = "Create Healthstone",
    [6789] = "Death Coil", [5484] = "Howl of Terror", [6229] = "Shadow Ward", [18708] = "Fel Domination",
    [710] = "Banish", [1098] = "Enslave Demon",
    [687] = "Demon Skin", [706] = "Demon Armor", [11735] = "Demon Armor",
    [17962] = "Conflagrate", [18288] = "Amplify Curse", [1122] = "Inferno", [603] = "Bane of Doom"}
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
    -- Absorbs: always secret, as the client's UnitGetTotalAbsorbs is.
    state.absorb = secret()
    state.secrets[state.absorb] = true
    env.UnitGetTotalAbsorbs = function(unit) equal(unit, "player") return state.absorb end
    env.UnitHealthMax = function(unit) equal(unit, "player") return 1500 end
    env.AbbreviateNumbers = function(value) return {abbreviated = value} end
    -- The red text at the top of the screen.
    state.errors = {}
    env.UIErrorsFrame = {AddMessage = function(_, message, r, g, b)
        state.errors[#state.errors + 1] = {text = message, r = r, g = g, b = b}
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
    env.C_SpellBook = {}
    if not options.noSpellBook then
        env.C_SpellBook.IsSpellKnown = function(id) return state.known[id] == true end
    end
    state.timers = {}
    env.C_Timer = {After = function(seconds, callback)
        state.timers[#state.timers + 1] = {at = state.now + seconds, callback = callback}
    end}
    function state.runTimers()
        local due = {}
        for index = #state.timers, 1, -1 do
            if state.timers[index].at <= state.now then
                due[#due + 1] = table.remove(state.timers, index)
            end
        end
        for _, timer in ipairs(due) do timer.callback() end
    end
    env.C_XMLUtil = {GetTemplateInfo = function(name)
        if name == "CustomAuraContainerTemplate" and not options.noAuraContainer then return {} end
    end}
    env.C_AddOns.IsAddOnLoaded = function(name) return state.loadedAddOns and state.loadedAddOns[name] end
    env.C_AddOns.LoadAddOn = function(name)
        state.loadedAddOns = state.loadedAddOns or {}
        state.loadedAddOns[name] = true
    end
    env.C_Spell.GetSpellTexture = function(id) return 2000 + id end
    -- As on Forever, stone spells have numeric ranks.
    local RANKS = {[6201] = 1, [6202] = 2, [5699] = 3, [693] = 1, [20752] = 2}
    env.C_Spell.GetSpellSubtext = function(id) if RANKS[id] then return "Rank " .. RANKS[id] end end
    -- The spellbook: one skill line holding state.spellbook entries {spellID, name}.
    state.spellbook = options.spellbook or {}
    env.C_SpellBook = env.C_SpellBook or {}
    env.C_SpellBook.GetNumSpellBookSkillLines = function() return 1 end
    env.C_SpellBook.GetSpellBookSkillLineInfo = function()
        return {itemIndexOffset = 0, numSpellBookItems = #state.spellbook}
    end
    -- As in client, each item has a type: 1 learned, 2 learned later (FutureSpell).
    env.C_SpellBook.GetSpellBookItemInfo = function(index)
        local item = state.spellbook[index]
        if item then
            return {spellID = item.spellID, name = item.name, itemType = item.itemType or 1}
        end
    end
    env.Enum = env.Enum or {}
    env.Enum.SpellBookSpellBank = {Player = 0}
    env.Enum.SpellBookItemType = {None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4}
    env.Enum.StatusBarTimerDirection = {ElapsedTime = 0, RemainingTime = 1}
    env.C_ClassColor = {GetClassColor = function(class)
        equal(class, "WARLOCK")
        return {r = 0.53, g = 0.53, b = 0.93}
    end}
    env.UnitIsDead = function(unit) return state.units[unit] ~= nil and state.units[unit].dead == true end
    -- Raid markers, by the unit's GUID.
    state.marks = {}
    -- As on Forever, the marker index is secret in combat.
    env.GetRaidTargetIndex = function(unit)
        if state.combat then
            local value = secret()
            state.secrets[value] = true
            return value
        end
        local data = state.units[unit]
        return data and state.marks[data.guid or data.name]
    end
    -- As in client, setting the marker a unit already has clears it.
    env.SetRaidTarget = function(unit, index)
        local data = state.units[unit]
        local key = data.guid or data.name
        if state.marks[key] == index then index = nil end
        state.marks[key] = index
        state.markCount = (state.markCount or 0) + 1
        state.markedUnit = unit
    end
    env.UnitIsDeadOrGhost = function(unit) return state.units[unit] ~= nil and state.units[unit].dead == true end
    -- State drivers: "[@unit,harm,nodead] show; hide", evaluated by the game.
    state.drivers = {}
    function state.applyDrivers()
        for frame, driver in pairs(state.drivers) do
            local unit = driver:match("@(%a+)")
            local data = state.units[unit]
            if driver == "[combat] hide; show" then
                frame.shown = not state.combat
            else
                frame.shown = data ~= nil and not data.friend and not data.dead
            end
        end
    end
    env.RegisterStateDriver = function(frame, kind, driver)
        equal(kind, "visibility")
        if state.combat then error("RegisterStateDriver in combat") end
        state.drivers[frame] = driver
        state.applyDrivers()
    end
    env.UnregisterStateDriver = function(frame, kind)
        equal(kind, "visibility")
        if state.combat then error("UnregisterStateDriver in combat") end
        state.drivers[frame] = nil
    end
    -- The trade window: six slots; placing an item may need a key press or click.
    state.tradeSlots = {}
    env.InitiateTrade = function(unit) state.tradeWith = unit end
    env.GetTradePlayerItemLink = function(slot)
        if state.tradeSlots[slot] then return "item:" .. state.tradeSlots[slot] end
    end
    env.ClickTradeButton = function(slot)
        if state.tradeNeedsHardware and not state.hardware then
            state.emit("ADDON_ACTION_BLOCKED", "WarlockToolsForever", "UNKNOWN()")
            return
        end
        if state.cursor then
            state.tradeSlots[slot] = state.cursor.itemID
            state.cursor = nil
        end
    end
    env.IsInInstance = function() return state.inInstance == true end
    state.macros = options.macros or {}
    -- As in client, the global exists only once the Macro window has loaded.
    env.Constants = {MacroConsts = {MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30}}
    local function macroIndex(name)
        for index, macro in ipairs(state.macros) do
            if macro.name == name then return 120 + index end
        end
        return 0
    end
    env.GetMacroIndexByName = macroIndex
    env.GetNumMacros = function() return 0, #state.macros end
    env.GetMacroBody = function(index) return state.macros[index - 120].body end
    env.CreateMacro = function(name, icon, body, perCharacter)
        if state.combat then error("CreateMacro in combat") end
        equal(perCharacter, true, "a character macro")
        state.macros[#state.macros + 1] = {name = name, icon = icon, body = body}
        return 120 + #state.macros
    end
    env.EditMacro = function(index, name, icon, body)
        if state.combat then error("EditMacro in combat") end
        state.macros[index - 120] = {name = name, icon = icon, body = body}
        state.macroEdits = (state.macroEdits or 0) + 1
    end
    env.DeleteMacro = function(index)
        if state.combat then error("DeleteMacro in combat") end
        table.remove(state.macros, index - 120)
    end
    env.PlaySoundFile = function(file, channel) state.played = {file = file, channel = channel} end
    -- Sound kits: a few SOUNDKIT names, and every kit played.
    state.sounds = {}
    env.SOUNDKIT = {UI_ORDERHALL_TALENT_READY_TOAST = 73281, RAID_WARNING = 8959, READY_CHECK = 8960}
    env.PlaySound = function(kit, channel) state.sounds[#state.sounds + 1] = {kit = kit, channel = channel} end
    -- Cooldowns: readable out of combat, secret in it, as on Forever.
    state.cooldowns = {}
    env.C_Spell.GetSpellCooldown = function(id)
        local cooldown = state.cooldowns[id]
        if not cooldown then return {startTime = 0, duration = 0, isEnabled = true} end
        if state.combat then
            local start, duration = secret(), secret()
            state.secrets[start], state.secrets[duration] = true, true
            return {startTime = start, duration = duration, isEnabled = true}
        end
        return {startTime = cooldown.start, duration = cooldown.duration, isEnabled = true}
    end
    -- Wall-clock seconds, as WoW's time().
    env.time = function() return 1000000 + math.floor(state.now) end
    env.IsInRaid = function() return state.group == "raid" end
    env.IsInGroup = function() return state.group ~= nil end
    env.GetZoneText = function() return state.zone or "Redridge Mountains" end
    env.C_ChatInfo = {SendChatMessage = function(message, chatType, _, target)
        -- As in client, an emote outside a key press or click is blocked.
        if (chatType == "SAY" and state.sayBlocked) or (chatType == "EMOTE" and not state.hardware) then
            state.emit("ADDON_ACTION_BLOCKED", "WarlockToolsForever", "UNKNOWN()")
            return
        end
        state.sent[#state.sent + 1] = {message = message, chatType = chatType, target = target}
    end}
    env.hooksecurefunc = function(target, name, hook)
        local original = target[name]
        target[name] = function(...)
            local result = original(...)
            hook(...)
            return result
        end
    end
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
    env.UnitFullName = function(unit)
        local data = state.units[unit]
        if data then return data.name, data.surname or (unit == "player" and "Maebryn" or nil) end
    end
    env.UnitIsPlayer = function(unit) return state.units[unit] ~= nil and state.units[unit].player == true end
    env.UnitIsFriend = function(_, unit) return state.units[unit] ~= nil and state.units[unit].friend == true end
    env.UnitLevel = function(unit) return state.units[unit] and state.units[unit].level or 0 end
    -- As in client, UnitName returns the first and the last name (Forever full names).
    env.UnitName = function(unit)
        local data = state.units[unit]
        if data then return data.name, data.surname end
    end
    env.UnitGUID = function(unit) return state.units[unit] and state.units[unit].guid end
    env.UnitCanAttack = function(_, unit) return state.units[unit] ~= nil and not state.units[unit].friend end
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
        -- As in client, aura sound changes are refused during an encounter.
        AddAuraSound = function(trigger, info)
            if state.encounter then error("AddAuraSound during an encounter") end
            state.auraSoundCount = (state.auraSoundCount or 0) + 1
            state.auraSounds = state.auraSounds or {}
            state.auraSounds[state.auraSoundCount] = {trigger = trigger, info = info}
            return state.auraSoundCount
        end,
        RemoveAuraSound = function(id)
            if state.encounter then error("RemoveAuraSound during an encounter") end
            state.auraSounds[id] = nil
        end,
        -- In client these may answer in combat: nothing for a secret aura.
        GetAuraDataBySpellName = function(unit, name, filter)
            -- Your buffs (state.buffs, or a unit's own): unreadable in combat.
            if filter == "HELPFUL" then
                if state.combat then error("Auras cannot be accessed when secret while tainted") end
                if unit ~= "player" then
                    return ((state.units[unit] or {}).buffs or {})[name]
                end
                return (state.buffs or {})[name]
            end
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
    -- Blizzard's plate frame per nameplate unit; forbidden plates are other players' or protected.
    state.plates = {}
    env.C_NamePlate = {
        GetNamePlates = function() return state.nameplates or {} end,
        GetNamePlateForUnit = function(unit)
            if not state.units[unit] then return end
            if not state.plates[unit] then
                state.plates[unit] = env.CreateFrame("Frame", nil, nil)
                state.plates[unit].forbidden = state.units[unit].forbidden
            end
            return state.plates[unit]
        end,
    }
    env.UnitAffectingCombat = function(unit) return unit == "player" and state.combat end
    if not options.noRestrictionAPI then
        env.Enum = env.Enum or {}
        env.Enum.AddOnRestrictionType = {Combat = 0, Encounter = 1, Chat = 5}
        env.Enum.UnitAuraSoundTrigger = {Added = 0, ApplicationsIncreased = 1, Removed = 2}
        env.C_RestrictedActions = {GetAddOnRestrictionState = function(kind)
            return (state.restrictions or {})[kind] or 0
        end}
        env.C_CombatLog = {IsCombatLogRestricted = function() return state.combatLogRestricted == true end}
        env.C_RestrictedActions.IsAddOnRestrictionActive = function(kind)
            return kind == 1 and state.encounter == true
        end
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
            object.modifyPredicates = {}
            function object:InitFrame(frame) frame.initializedWith = self end
            function object:AddModifyPredicate(predicate)
                self.modifyPredicates[#self.modifyPredicates + 1] = predicate
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
            CreateControlTextContainer = function()
                local container = {data = {}}
                function container:Add(value, label) self.data[#self.data + 1] = {value = value, label = label} end
                function container:GetData() return self.data end
                return container
            end,
            CreateDropdown = function(category, setting, choices, tooltip)
                local object = initializer(category, setting)
                object.tooltip, object.choices = tooltip, choices
                return object
            end,
            CreateColorSwatch = function(category, setting, tooltip)
                local object = initializer(category, setting)
                object.tooltip, object.swatch = tooltip, true
                return object
            end,
            CreateSliderOptions = function(minValue, maxValue, step)
                local object = {minValue = minValue, maxValue = maxValue, step = step}
                function object:SetLabelFormatter(label) self.label = label end
                return object
            end,
            OpenToCategory = function(id) state.opened = id end,
            InitDropdown = function(dropdown, setting, inserter)
                dropdown.setting, dropdown.inserter = setting, inserter
            end,
            NotifyUpdate = function(variable) state.notified[#state.notified + 1] = variable end,
        }
    end

    state.worldHooks = {}
    -- A 1000 x 800 screen.
    env.UIParent = {GetWidth = function() return 1000 end, GetHeight = function() return 800 end,
        GetEffectiveScale = function() return 1 end}
    env.IsShiftKeyDown = function() return state.shift == true end
    local SPOTS = {CENTER = {0.5, 0.5}, BOTTOMLEFT = {0, 0}, BOTTOM = {0.5, 0}, BOTTOMRIGHT = {1, 0},
        LEFT = {0, 0.5}, RIGHT = {1, 0.5}, TOPLEFT = {0, 1}, TOP = {0.5, 1}, TOPRIGHT = {1, 1}}
    -- Screen position of a frame's center, from its last point.
    function state.absCenter(frame)
        if frame == env.UIParent or frame == nil then return 500, 400 end
        local point = frame.points[#frame.points]
        if not point then return 500, 400 end
        local relative = point[2] or env.UIParent
        if type(relative) ~= "table" then relative = env.UIParent end
        local relativeScale = relative.GetEffectiveScale and relative:GetEffectiveScale() or 1
        local rx, ry = state.absCenter(relative)
        local rw = relative == env.UIParent and 1000 or (relative.width or 0) * relativeScale
        local rh = relative == env.UIParent and 800 or (relative.height or 0) * relativeScale
        local spot, own = SPOTS[point[3]] or SPOTS.CENTER, SPOTS[point[1]] or SPOTS.CENTER
        local scale = frame:GetEffectiveScale()
        local width, height = (frame.width or 0) * scale, (frame.height or 0) * scale
        return rx + (spot[1] - 0.5) * rw - (own[1] - 0.5) * width + (point[4] or 0) * scale,
            ry + (spot[2] - 0.5) * rh - (own[2] - 0.5) * height + (point[5] or 0) * scale
    end
    env.WorldFrame = {HookScript = function(_, script, callback) state.worldHooks[script] = callback end}
    local function widget(kind, name, parent, template)
        local object = {kind = kind, name = name, parent = parent, template = template, events = {},
            unitEvents = {}, scripts = {}, attributes = {}, points = {}, shown = true, text = "", children = {}}
        if parent and parent.children then parent.children[#parent.children + 1] = object end
        function object:SetBackdropBorderColor(...) self.backdropBorder = {...} end
        function object:SetBackdrop(backdrop) self.backdrop = backdrop end
        function object:SetStatusBarColor(...) self.barColor = {...} end
        function object:SetStatusBarTexture(texture) self.statusBarTexture = texture end
        function object:SetColorTexture(...) self.color = {...} end
        function object:SetWidth(width) self.width = width end
        function object:EnableMouse(value) self.mouseDisabled = value == false end
        function object:SetHeight(height) self.height = height end
        function object:SetSize(width, height) self.width, self.height = width, height end
        -- As in client, secure frames refuse layout changes in combat.
        function object:SetScale(value)
            if state.combat and self.protected then error("SetScale in combat") end
            self.scale = value
        end
        function object:GetWidth() return self.width or 0 end
        function object:GetHeight() return self.height or 0 end
        function object:GetEffectiveScale()
            local parentScale = 1
            if self.parent and self.parent.GetEffectiveScale then parentScale = self.parent:GetEffectiveScale() end
            return (self.scale or 1) * parentScale
        end
        -- As in client, in the frame's own units.
        function object:GetCenter()
            local x, y = state.absCenter(self)
            local scale = self:GetEffectiveScale()
            return x / scale, y / scale
        end
        function object:SetFrameLevel(level) self.level = level end
        function object:SetParent(newParent) self.parent = newParent end
        function object:IsForbidden() return self.forbidden == true end
        function object:CreateMaskTexture() return widget("MaskTexture", nil, self) end
        function object:GetFrameLevel() return self.level or 1 end
        function object:SetShown(value)
            if value then self:Show() else self:Hide() end
        end
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
        function object:SetPoint(...)
            if state.combat and self.protected then error("SetPoint in combat") end
            self.points[#self.points + 1] = {...}
        end
        function object:ClearAllPoints()
            if state.combat and self.protected then error("ClearAllPoints in combat") end
            self.points = {}
        end
        function object:GetPoint()
            -- As in client, a frame with no points returns nothing.
            local point = self.points[#self.points]
            if not point then return end
            return point[1], point[2], point[3], point[4], point[5]
        end
        function object:StartMoving() self.moving = true end
        function object:StopMovingOrSizing() self.moving = false end
        function object:SetText(text) self.text = text end
        function object:SetTextColor(...) self.textColor = {...} end
        function object:GetText() return self.text end
        function object:SetTexture(texture) self.texture = texture end
        function object:SetChecked(value) self.checked = value == true end
        function object:GetChecked() return self.checked end
        function object:CreateTexture() return widget("Texture", nil, self) end
        function object:CreateAnimationGroup()
            local group = {playing = false}
            function group:SetLooping(looping) self.looping = looping end
            function group:CreateAnimation(kind)
                return setmetatable({kind = kind}, {__index = function() return function() end end})
            end
            function group:Play() self.playing = true end
            function group:Stop() self.playing = false end
            function group:IsPlaying() return self.playing end
            self.animation = group
            return group
        end
        function object:EnableMouseWheel(value) self.wheel = value == true end
        function object:AddAuraSlot(key, filter, slotOptions)
            self.slots = self.slots or {}
            local button = widget("Button", nil, self)
            button.display = {}
            function button:SetIcon(region) self.display.icon = region end
            function button:SetDurationCooldown(region) self.display.cooldown = region end
            function button:SetDurationBar(region, barOptions) self.display.bar, self.display.barOptions = region, barOptions end
            function button:SetDurationText(region) self.display.text = region end
            function button:SetMouseClickEnabled(value) self.clicks = value end
            slotOptions.initializeFrame(button)
            self.slots[#self.slots + 1] = {key = key, filter = filter, button = button,
                ids = slotOptions.candidateFilters.includeSpellIDs, candidates = slotOptions.candidateFilters}
            return button
        end
        function object:SetAuraSlotCandidateFilters(key, filters)
            for _, slot in ipairs(self.slots) do
                if slot.key == key then slot.ids, slot.candidates = filters.includeSpellIDs, filters end
            end
        end
        function object:SetUnit(unit) self.unit = unit end
        function object:UpdateAllAuras() self.updates = (self.updates or 0) + 1 end
        function object:CreateFontString() return widget("FontString", nil, self) end
        -- Unknown methods (layout, colors, and so on) do nothing here.
        return setmetatable(object, {__index = function(_, key)
            if type(key) == "string" and key:match("^%u") then return function() end end
        end})
    end
    -- UIParent can hold text, as the shield display's debug writes on it.
    env.UIParent.CreateFontString = function(self) return widget("FontString", nil, self) end
    env.CreateFrame = function(kind, name, parent, template)
        local frame = widget(kind, name, parent, template)
        if name then env[name] = frame end
        if kind == "AuraContainer" then
            equal(template, "CustomAuraContainerTemplate")
            equal(state.loadedAddOns and state.loadedAddOns.Blizzard_AuraContainer, true, "container AddOn loaded")
        end
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
    -- Other AddOns shipping Shield.lua, as MTF does: {addon, version, before};
    -- each gets its own namespace, and a test initializes it or not.
    state.copies = {}
    local function loadShieldCopy(spec)
        local source = assert(io.open("Shield.lua")):read("*a")
        source = source:gsub("local VERSION = %d+", "local VERSION = " .. spec.version)
        local chunk = assert(loadstring(source, "=" .. spec.addon .. "/Shield.lua"))
        setfenv(chunk, env)
        local namespace = {}
        chunk(spec.addon, namespace)
        state.copies[spec.addon] = namespace
    end
    for _, spec in ipairs(options.shieldCopies or {}) do
        if spec.before then loadShieldCopy(spec) end
    end
    state.wtf = {}
    for _, path in ipairs(options.files or RUNTIME_FILES) do
        local chunk, message = loadfile(path)
        if not chunk then error(message) end
        setfenv(chunk, env)
        chunk("WarlockToolsForever", state.wtf)
    end
    for _, spec in ipairs(options.shieldCopies or {}) do
        if not spec.before then loadShieldCopy(spec) end
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
        local suffix = mouseButton == "RightButton" and "2" or mouseButton == "MiddleButton" and "3" or "1"
        hardware(function()
            state.used = {type = button.attributes["type" .. suffix], item = button.attributes["item" .. suffix],
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
    local state = fixture({files = {"Commands.lua", "Core.lua", "Layout.lua", "Shards.lua", "Stones.lua", "Announce.lua",
        "Tracker.lua", "Dots.lua", "Control.lua", "Alerts.lua", "Shield.lua", "Chimes.lua", "Reminders.lua", "Options.lua"}})
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
test("a shard within 8 seconds of Shadowburn counts as created", function()
    -- Forever's Shadowburn gives a shard when the target dies within 8 seconds.
    local state = fixture()
    state.fill(6)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 18871)
    state.now = state.now + 7.5
    state.gain(1, 1)
    equal(state.count(), 6)
    state.now = state.now + 10
    state.gain(1, 2)
    equal(state.count(), 7, "after the window")
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
    contains(state.messages[2], "source spell=1120 name=Drain Soul window=3s")
    contains(state.messages[3], "source spell=17877 name=Shadowburn window=9s")
    contains(state.messages[4], "NUM_BAG_SLOTS=4 NUM_TOTAL_EQUIPPED_BAG_SLOTS=nil itemCount=0")
    contains(state.messages[6], "bag=1 slots=12 family=4 soul=true items=1 shards=1 shardSlotsByID=1 noInfo=0")
    contains(state.messages[10], "count=3 limit=12 source=soul bag")
    contains(state.messages[11], "gain 0.0s ago +1 count=3 created=true combat=false last=UNIT_SPELLCAST_CHANNEL_START 11675 1.0s before")
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
    reported(state, "target byName checked=9 found=2")
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
    equal(health.attributes.type1, "item")
    equal(health.attributes.item1, "item:5511")
    equal(health.attributes.spell2, 5699, "no player target: the best known rank")
    equal(soul.count.text, 3)
    equal(health.count.text, 1)
    equal(soul.icon.texture, 1000 + 16892)
end)
test("right-click creates the best Healthstone a friendly player target can use", function()
    local state = stonesFixture({carried = {}, units = {target = {name = "Lowbie", player = true, friend = true, level = 20}}})
    equal(state.env[HEALTH].attributes.spell2, 6202, "Healthstone needs level 24")
    state.units.target.level = 30
    state.emit("PLAYER_TARGET_CHANGED")
    equal(state.env[HEALTH].attributes.spell2, 5699)
    state.units.target = {name = "Boar", level = 5}
    state.emit("PLAYER_TARGET_CHANGED")
    equal(state.env[HEALTH].attributes.spell2, 5699, "a mob target does not limit the rank")
end)
test("an uncached level requirement skips that rank until item data arrives", function()
    local state = stonesFixture({carried = {}, units = {target = {name = "Lowbie", player = true, friend = true, level = 40}}})
    equal(state.requested, 5, "level requirements are requested at login")
    ITEMS[5509][2] = nil
    state.emit("PLAYER_TARGET_CHANGED")
    equal(state.env[HEALTH].attributes.spell2, 6202)
    ITEMS[5509][2] = 24
    state.emit("GET_ITEM_INFO_RECEIVED")
    equal(state.env[HEALTH].attributes.spell2, 5699)
end)
test("debug_click shows each button's actions and the key-down setting", function()
    local state = stonesFixture()
    state.env.GetCVarBool = function(name) return name == "ActionButtonUseKeyDown" end
    state.clear()
    state.slash("debug_click")
    equal(state.messages[1], "WTF: debug_click ActionButtonUseKeyDown=true combat=false healthstoneMode=use")
    contains(state.messages[2], "WarlockToolsForeverHealthstone useOnKeyDown=false")
    contains(state.messages[3], "button1 type=item item=item:5511")
    contains(state.messages[5], "button3 type=item item=item:5511")
end)
test("a failed stone click is said in chat and in red at the top of the screen", function()
    local state = fixture({known = {[6201] = true}})
    state.clickButton("WarlockToolsForeverHealthstone", "MiddleButton")
    contains(state.last(), "No Healthstone in your bags")
    equal(#state.errors, 1)
    contains(state.errors[1].text, "WTF: No Healthstone in your bags")
    equal(state.errors[1].r, 1)
    equal(state.errors[1].g, 0.1, "red")
end)

local function macroBody(state, name)
    for _, macro in ipairs(state.macros) do
        if macro.name == name then return macro.body end
    end
end

test("WTF writes Healthstone and Soulstone macros in the character tab", function()
    local state = stonesFixture()
    equal(macroBody(state, "! Healthstone"), table.concat({
        "#showtooltip item:5511",
        "/cast [btn:2] Create Healthstone(Rank 3)",
        "/stopmacro [btn:2]",
        "/use item:9421", "/use item:5510", "/use item:5509", "/use item:5511", "/use item:5512"}, "\n"))
    equal(macroBody(state, "! Soulstone"), table.concat({
        "#showtooltip item:16892",
        "/cast [btn:2] Create Soulstone",
        "/stopmacro [btn:2]",
        "/use [@target,help,nodead][@player] item:16892"}, "\n"))
    equal(state.macros[1].icon, 134400, "the question mark, so #showtooltip shows the stone")
end)
test("the macros follow your bags and downranking, out of combat only", function()
    local state = stonesFixture()
    state.carried[5509] = 1
    state.emit("BAG_UPDATE_DELAYED")
    contains(macroBody(state, "! Healthstone"), "/cast [btn:2] Create Healthstone(Rank 1)")
    local edits = state.macroEdits
    state.combat = true
    state.carried[5509] = 0
    state.emit("BAG_UPDATE_DELAYED")
    equal(state.macroEdits, edits, "no change in combat")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    contains(macroBody(state, "! Healthstone"), "Create Healthstone(Rank 3)")
    state.emit("BAG_UPDATE_DELAYED")
    equal(state.macroEdits, edits + 1, "an unchanged body is not rewritten")
end)
test("macros work without the Macro window's global, and report what is missing", function()
    local state = stonesFixture()
    equal(state.env.MAX_CHARACTER_MACROS, nil)
    equal(#state.macros, 2)
    state.clear()
    state.slash("debug_stones")
    contains(table.concat(state.messages, "|"), "macros enabled=true available=true missing=nil limit=30 used=2")
    local bare = stonesFixture({remove = {"CreateMacro"}})
    contains(table.concat(bare.messages, "|"), "Stone macros stay off: this client lacks CreateMacro.")
end)
test("macros made under the old names are renamed in place", function()
    local state = stonesFixture({macros = {{name = "WTF Healthstone", body = "old"}, {name = "Mine", body = ""},
        {name = "!WTF Soulstone", body = "old"}}})
    equal(state.macros[1].name, "! Healthstone", "the same slot, so action bars keep it")
    equal(#state.macros, 3, "both renamed, none added")
    equal(state.macros[3].name, "! Soulstone")
end)
test("macros need a known rank and a free slot, and turning them off deletes them", function()
    local novice = fixture()
    equal(#novice.macros, 0)
    local full = {}
    for index = 1, 28 do full[index] = {name = "Mine" .. index, body = ""} end
    local crowded = stonesFixture({macros = full})
    equal(#crowded.macros, 28, "the last two slots stay yours")
    contains(crowded.messages[#crowded.messages], "No free character macro slot")
    local state = stonesFixture()
    equal(#state.macros, 2)
    state.settings.WTF_STONES_MACROS:SetValue(false)
    equal(#state.macros, 0)
    state.settings.WTF_STONES_MACROS:SetValue(true)
    equal(#state.macros, 2)
end)
test("stone buttons act on the release, so /click works", function()
    -- In client, /click sends only a release and did nothing while the
    -- buttons acted on the press (ActionButtonUseKeyDown).
    local state = stonesFixture()
    equal(state.env[HEALTH].attributes.useOnKeyDown, false)
    equal(state.env[SOUL].attributes.useOnKeyDown, false)
end)
test("middle-click always uses your best Healthstone, whatever the target", function()
    local state = stonesFixture({carried = {[5511] = 1, [5509] = 1},
        units = {target = {name = "Lowbie", player = true, friend = true, level = 20}}})
    local health = state.env[HEALTH]
    equal(health.mode, "trade", "left-click trades to the friend")
    equal(health.attributes.type3, "item")
    equal(health.attributes.item3, "item:5509", "middle-click uses your best")
    state.clickButton(HEALTH, "MiddleButton")
    equal(state.used.item, "item:5509")
    equal(state.tradeWith, nil, "no trade")
    health.scripts.OnEnter(health)
    local text = table.concat(state.tooltip, "|")
    contains(text, "Middle-click: use your best Healthstone on yourself.")
    contains(text, "the \"! Healthstone\" macro in your character macros")
    local empty = fixture({known = {[6201] = true}})
    empty.clear()
    empty.clickButton(HEALTH, "MiddleButton")
    equal(empty.last(), "WTF: No Healthstone in your bags. Right-click to create one.")
end)
test("a Healthstone rank you already carry is skipped for the one below it", function()
    -- Each rank is unique in your bags, so creating it again would fail.
    local state = stonesFixture({carried = {[5509] = 1}})
    equal(state.env[HEALTH].attributes.spell2, 6202, "Healthstone carried: make a Lesser")
    state.carried[5511] = 1
    state.emit("BAG_UPDATE_DELAYED")
    equal(state.env[HEALTH].attributes.spell2, 6201, "Lesser carried too: make a Minor")
    state.carried[5512] = 1
    state.emit("BAG_UPDATE_DELAYED")
    equal(state.env[HEALTH].attributes.type2, nil, "every rank carried")
    state.clear()
    state.clickButton(HEALTH, "RightButton")
    equal(state.last(), "WTF: You already carry every Healthstone rank you can make here.")
end)
test("downranking also respects a friendly target's level", function()
    local state = stonesFixture({carried = {[5511] = 1},
        units = {target = {name = "Lowbie", player = true, friend = true, level = 20}}})
    equal(state.env[HEALTH].attributes.spell2, 6201, "Lesser carried, Healthstone too high: a Minor")
    equal(state.env[HEALTH].mode, "trade", "left-click trades the Lesser one they can use")
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
    state.slash("unlock")
    local bar, soul = state.env.WarlockToolsForeverStones, state.env[SOUL]
    soul.scripts.OnDragStart(soul)
    equal(bar.moving, true)
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", nil, "BOTTOMLEFT", 110, 220)
    soul.scripts.OnDragStop(soul)
    equal(state.wtf.db.stones.position.relativePoint, "BOTTOMLEFT")
    equal(state.wtf.db.stones.position.x, 110)
    state.slash("lock")
    soul.scripts.OnDragStart(soul)
    equal(bar.moving, false)
    state.slash("unlock")
    state.combat = true
    bar.scripts.OnDragStart(bar)
    equal(bar.moving, false)
end)
test("the shard counter shows your count, red when low, green at the limit, and can be turned off", function()
    local state = fixture()
    local counter = state.wtf.shardCounter
    equal(counter.shown, true, "on by default")
    equal(counter.count.text, 0)
    equal(counter.count.textColor[2], 0.2, "red with none")
    state.fill(2)
    equal(counter.count.text, 2)
    equal(counter.count.textColor[2], 0.2, "red at two")
    state.fill(3)
    equal(counter.count.text, 3)
    equal(counter.count.textColor[3], 1, "white between")
    state.fill(6)
    equal(counter.count.text, 6)
    equal(counter.count.textColor[1], 0.3, "green at the limit")
    equal(counter.count.textColor[2], 1)
    counter.scripts.OnEnter(counter)
    contains(table.concat(state.tooltip, "|"), "6 of 6 (default limit)")
    state.settings.WTF_SHARDS_COUNTER:SetValue(false)
    equal(counter.shown, false)
    state.settings.WTF_SHARDS_COUNTER:SetValue(true)
    equal(counter.shown, true)
end)
test("the low shard warning is a setting, 2 by default", function()
    local state = fixture()
    local counter = state.wtf.shardCounter
    equal(state.wtf.db.shards.counterLow, 2)
    state.fill(3)
    equal(counter.count.textColor[3], 1, "white at three")
    state.settings.WTF_SHARDS_COUNTER_LOW:SetValue(3)
    equal(state.wtf.db.shards.counterLow, 3)
    equal(counter.count.textColor[2], 0.2, "red at three once the warning is 3")
    state.settings.WTF_SHARDS_COUNTER_LOW:SetValue(99)
    equal(state.wtf.db.shards.counterLow, 10, "kept within 0 to 10")
    local saved = fixture({db = {shards = {counterLow = "lots"}}})
    equal(saved.wtf.db.shards.counterLow, 2, "a bad saved value becomes the default")
end)
test("the shard counter drags unless locked, saves its place, and resets", function()
    local state = fixture()
    local counter = state.wtf.shardCounter
    state.slash("unlock")
    counter.scripts.OnDragStart(counter)
    equal(counter.moving, true)
    counter:ClearAllPoints()
    counter:SetPoint("CENTER", state.env.UIParent, "BOTTOMLEFT", 90, 700)
    counter.scripts.OnDragStop(counter)
    equal(state.wtf.db.shards.counterPosition.point, "CENTER")
    equal(state.wtf.db.shards.counterPosition.y, 700)
    state.slash("lock")
    counter.scripts.OnDragStart(counter)
    equal(counter.moving, false, "locked")
    state.slash("reset")
    equal(state.wtf.db.shards.counterPosition, nil)
    equal(counter.points[1][1], "CENTER")
    local saved = fixture({db = {shards = {counterPosition = {point = "TOP", relativePoint = "TOP", x = 1, y = 2}}}})
    equal(saved.wtf.shardCounter.points[1][1], "TOP", "the place survives a reload")
end)
-- Control bar --------------------------------------------------------------------------

local FEAR, BANISH, ENSLAVE, HOWL = 5782, 710, 1098, 5484

local function controlFixture(extra)
    local options = {known = {[FEAR] = true, [BANISH] = true}, units = {
        target = {name = "Boar", guid = "Creature-1"},
        nameplate3 = {name = "Boar", guid = "Creature-1"},
        nameplate4 = {name = "Imp", guid = "Creature-2"},
    }}
    for key, value in pairs(extra or {}) do options[key] = value end
    return fixture(options)
end

local function castAt(state, spellID, unit)
    state.units.target = state.units[unit]
    local name = state.units[unit].name
    state.emit("UNIT_SPELLCAST_SENT", "player", name, "cast-" .. spellID .. unit, spellID)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-" .. spellID .. unit, spellID)
end

local function controlRow(state, index)
    return state.env["WarlockToolsForeverControlRow" .. index]
end

test("each mob you Fear or Banish gets its own bar, bound to its unit", function()
    local state = controlFixture()
    castAt(state, FEAR, "nameplate3")
    castAt(state, BANISH, "nameplate4")
    local first, second = controlRow(state, 1), controlRow(state, 2)
    equal(first.shown, true)
    equal(first.name.text, "Boar")
    equal(first.container.unit, "nameplate3")
    equal(second.name.text, "Imp")
    equal(second.container.unit, "nameplate4")
    equal(first.container.slots[1].ids[FEAR], true, "the slot takes Fear")
    equal(first.container.slots[1].ids[BANISH], true, "and Banish")
    equal(first.container.slots[1].filter, "HARMFUL|PLAYER")
    equal(controlRow(state, 3).shown, false)
    castAt(state, FEAR, "nameplate3")
    equal(controlRow(state, 3).shown, false, "a recast on the same mob keeps its row")
    state.units.nameplate4.dead = true
    state.emit("UNIT_HEALTH", "nameplate4")
    equal(second.shown, false, "gone when the mob dies")
    state.now = state.now + 26
    state.runTimers()
    equal(first.shown, false, "gone once the longest Fear is over")
end)
test("a landed Banish gets the moon; Fear never marks, so WTF takes one marker slot", function()
    local state = controlFixture()
    castAt(state, BANISH, "nameplate4")
    equal(state.marks["Creature-2"], 5, "the moon")
    castAt(state, FEAR, "nameplate3")
    equal(state.marks["Creature-1"], nil)
    equal(state.settings.WTF_CONTROL_MARKER_FEAR, nil, "no marker setting for Fear")
    castAt(state, BANISH, "nameplate4")
    equal(state.markCount, 1, "an existing marker is left alone")
    local old = fixture({db = {control = {markers = {banish = 3}}}})
    equal(old.wtf.db.control.markers.banish, 5, "the old diamond default becomes the moon")
    local chosen = fixture({db = {control = {markers = {banish = 8}, markersVersion = 2}}})
    equal(chosen.wtf.db.control.markers.banish, 8, "a marker you chose stays")
end)
test("a Banish that lands in combat still gets its marker, on your target", function()
    local state = controlFixture()
    state.units.target = state.units.nameplate4
    state.emit("UNIT_SPELLCAST_SENT", "player", "Imp", "cast-b", BANISH)
    state.combat = true
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-b", BANISH)
    equal(state.marks["Creature-2"], 5, "marked although the marker cannot be read in combat")
    equal(state.markedUnit, "target")
    -- A recast in combat on the same mob must not toggle the marker off.
    state.emit("UNIT_SPELLCAST_SENT", "player", "Imp", "cast-b2", BANISH)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-b2", BANISH)
    equal(state.marks["Creature-2"], 5, "still the moon after a recast")
end)
test("control spells tell the group as the cast starts, with the marker in chat", function()
    local state = controlFixture({group = "party", known = {[FEAR] = true, [BANISH] = true, [ENSLAVE] = true}})
    castAt(state, BANISH, "nameplate4")
    equal(state.sent[1].chatType, "PARTY")
    equal(state.sent[1].message, "Banishing >> Imp << {moon} to the Twisting Nether. Hands off until it comes back"
        .. " - via Warlock Tools Forever (WTF)")
    castAt(state, FEAR, "nameplate3")
    equal(state.sent[2].message, "Fearing >> Boar <<. Let it run; chase it and you bring friends"
        .. " - via Warlock Tools Forever (WTF)")
    castAt(state, ENSLAVE, "nameplate4")
    contains(state.sent[3].message, "Enslaving >> Imp <<")
    state.emit("UNIT_SPELLCAST_SENT", "player", "", "cast-howl", HOWL)
    contains(state.sent[4].message, "Howl of Terror! Everything nearby")
    castAt(state, FEAR, "nameplate3")
    equal(#state.sent, 4, "not again within a few seconds")
    state.wtf.db.announce.banishGroup = false
    state.now = state.now + 5
    castAt(state, BANISH, "nameplate4")
    equal(#state.sent, 4, "its switch")
    local alone = controlFixture()
    castAt(alone, FEAR, "nameplate3")
    equal(#alone.sent, 0, "nothing when alone")
end)
test("clicking a row recasts its spell on its mob; a click begun in combat follows after", function()
    local state = controlFixture()
    castAt(state, FEAR, "nameplate3")
    local click = state.env.WarlockToolsForeverControlClick1
    equal(click.protected, true, "a secure button")
    equal(click.shown, true)
    equal(click.attributes.macrotext1, "/cleartarget\n/targetexact Boar\n/cast [@target,harm,nodead] Fear"
        .. "\n/targetlasttarget")
    -- A pull: the cast starts out of combat and lands in it.
    state.units.target = state.units.nameplate4
    state.emit("UNIT_SPELLCAST_SENT", "player", "Imp", "cast-banish", BANISH)
    state.combat = true
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-banish", BANISH)
    contains(state.env.WarlockToolsForeverControlClick2.attributes.macrotext1, "Banish", "ready for the fight")
    -- Started in combat: the click waits for combat to end.
    state.units.nameplate5 = {name = "Wolf", guid = "Creature-3"}
    castAt(state, FEAR, "nameplate5")
    equal(controlRow(state, 3).name.text, "Wolf", "the bar shows in combat")
    equal(state.env.WarlockToolsForeverControlClick3.attributes.macrotext1, nil)
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    contains(state.env.WarlockToolsForeverControlClick3.attributes.macrotext1, "/targetexact Wolf")
    equal(state.env.WarlockToolsForeverControlClick4.shown, false, "no click area without a mob")
end)
test("a row whose click is set keeps its slot until combat ends, so no click casts on the wrong mob", function()
    local state = controlFixture()
    castAt(state, FEAR, "nameplate3")
    local click1 = state.env.WarlockToolsForeverControlClick1
    contains(click1.attributes.macrotext1, "/targetexact Boar")
    state.combat = true
    state.units.nameplate3.dead = true
    state.emit("UNIT_HEALTH", "nameplate3")
    equal(controlRow(state, 1).shown, false, "the Boar is gone")
    castAt(state, FEAR, "nameplate4")
    equal(controlRow(state, 1).shown, false, "its row is not reused while its click still names the Boar")
    equal(controlRow(state, 2).name.text, "Imp")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(click1.attributes.macrotext1, nil, "cleared after combat")
    equal(click1.shown, false)
    state.units.nameplate5 = {name = "Wolf", guid = "Creature-3"}
    castAt(state, FEAR, "nameplate5")
    equal(controlRow(state, 1).name.text, "Wolf", "then free again")
end)
test("a cast that fails out of combat gives back its row and click", function()
    local state = controlFixture()
    state.units.target = state.units.nameplate3
    state.emit("UNIT_SPELLCAST_SENT", "player", "Boar", "cast-a", FEAR)
    local click1 = state.env.WarlockToolsForeverControlClick1
    equal(click1.shown, true, "set as the cast starts")
    state.emit("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-a", FEAR)
    equal(click1.shown, false)
    equal(click1.attributes.macrotext1, nil)
    for index = 1, 5 do
        state.units["nameplate" .. (10 + index)] = {name = "Mob" .. index, guid = "Creature-1" .. index}
        state.units.target = state.units["nameplate" .. (10 + index)]
        state.emit("UNIT_SPELLCAST_SENT", "player", "Mob" .. index, "cast-f" .. index, FEAR)
        state.emit("UNIT_SPELLCAST_FAILED", "player", "cast-f" .. index, FEAR)
    end
    castAt(state, FEAR, "nameplate4")
    equal(controlRow(state, 1).name.text, "Imp", "failed casts never use up the rows")
end)
test("a size change in combat waits for combat, so rows stay on their click slots", function()
    local state = controlFixture()
    castAt(state, FEAR, "nameplate3")
    state.combat = true
    state.settings.WTF_CONTROL_SCALE:SetValue(80)
    equal(controlRow(state, 1).scale, 1, "unchanged in combat")
    equal(state.env.WarlockToolsForeverControl.scale, 1)
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(controlRow(state, 1).scale, 0.8)
    equal(state.env.WarlockToolsForeverControl.scale, 0.8, "together")
end)
test("a row never binds to mouseover, which changes with the pointer", function()
    local state = controlFixture()
    state.units.mouseover = {name = "Ghoul", guid = "Creature-9"}
    state.emit("UNIT_SPELLCAST_SENT", "player", "Ghoul", "cast-m", FEAR)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-m", FEAR)
    equal(controlRow(state, 1).shown, false, "a mob seen only under the pointer is not tracked")
    state.units.nameplate6 = state.units.mouseover
    state.emit("UNIT_SPELLCAST_SENT", "player", "Ghoul", "cast-n", FEAR)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-n", FEAR)
    equal(controlRow(state, 1).container.unit, "nameplate6", "its nameplate instead")
end)
test("unlocked, the control bar shows samples to drag; debug_control reports the rows", function()
    local state = controlFixture()
    state.slash("unlock")
    equal(controlRow(state, 1).name.text, "Fear (sample)")
    equal(controlRow(state, 2).name.text, "Banish (sample)")
    equal(state.env.WarlockToolsForeverControl.mover.shown, true)
    state.slash("lock")
    equal(controlRow(state, 1).shown, false)
    state.settings.WTF_CONTROL_ENABLED:SetValue(false)
    castAt(state, FEAR, "nameplate3")
    equal(controlRow(state, 1).shown, false, "its switch")
    state.clear()
    state.slash("debug_control")
    contains(state.messages[1], "debug_control available=true known=true")
end)

-- Demon Armor reminder ---------------------------------------------------------------

local DEMON_SKIN, DEMON_ARMOR = 687, 706

test("the Demon Armor icon pulses while it is missing; a click casts your armor", function()
    local state = fixture({known = {[DEMON_SKIN] = true, [DEMON_ARMOR] = true}})
    local icon = state.env.WarlockToolsForeverReminder_armor
    equal(icon.shown, true)
    equal(icon.glow.animation.playing, true, "the border pulses")
    equal(icon.protected, true, "a secure button")
    equal(icon.attributes.type1, "spell")
    equal(icon.attributes.spell1, "Demon Armor", "your best")
    equal(icon.attributes.unit1, "player")
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", DEMON_SKIN)
    state.emit("UNIT_AURA", "player")
    equal(icon.attributes.spell1, "Demon Skin", "the armor you used last")
    equal(state.wtf.db.reminders.last.armor, "Demon Skin")
    state.buffs = {["Demon Skin"] = {name = "Demon Skin"}}
    state.emit("UNIT_AURA", "player")
    equal(icon.shown, false, "Demon Skin counts")
    equal(icon.attributes.type1, nil)
end)
test("the reminder hides for combat, reads no buffs then, and follows its switch", function()
    local state = fixture({known = {[DEMON_ARMOR] = true}})
    local icon, holder = state.env.WarlockToolsForeverReminder_armor, state.env.WarlockToolsForeverReminders
    equal(state.drivers[holder], "[combat] hide; show")
    state.combat = true
    state.applyDrivers()
    equal(holder.shown, false)
    state.emit("UNIT_AURA", "player")
    state.combat = false
    state.applyDrivers()
    state.emit("PLAYER_REGEN_ENABLED")
    equal(holder.shown, true)
    state.settings.WTF_REMINDERS_ENABLED:SetValue(false)
    equal(icon.shown, false)
    local unknown = fixture()
    equal(unknown.env.WarlockToolsForeverReminder_armor.shown, false, "not before you learn Demon Skin")
end)
test("unlocked, the reminder drags, snaps, and resizes with the mouse wheel", function()
    local state = fixture()
    state.slash("unlock")
    local icon = state.env.WarlockToolsForeverReminder_armor
    equal(icon.shown, true, "a sample to place")
    equal(icon.attributes.type1, nil, "dragging never casts")
    local x, y = state.absCenter(icon)
    icon.scripts.OnMouseWheel(icon, 1)
    equal(state.wtf.db.reminders.icons.armor.scale, 110)
    local nx, ny = state.absCenter(icon)
    equal(math.floor(nx + 0.5), math.floor(x + 0.5), "resizing keeps the center")
    equal(math.floor(ny + 0.5), math.floor(y + 0.5))
    state.slash("lock")
    icon.scripts.OnMouseWheel(icon, 1)
    equal(state.wtf.db.reminders.icons.armor.scale, 110, "locked icons do not resize")
    state.slash("reset")
    equal(state.wtf.db.reminders.icons.armor.scale, 100)
    state.clear()
    state.slash("debug_reminders")
    contains(state.messages[1], "debug_reminders armor on=true known=false")
end)

-- Magnetic frames -------------------------------------------------------------------

local function centerOf(state, frame)
    local x, y = state.absCenter(frame)
    return math.floor(x + 0.5), math.floor(y + 0.5)
end

local function dropAt(state, frame, x, y, handle)
    handle = handle or frame
    handle.scripts.OnDragStart(handle)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", nil, "BOTTOMLEFT", x / frame:GetEffectiveScale(), y / frame:GetEffectiveScale())
    handle.scripts.OnDragStop(handle)
end

test("WTF ships the shield display: it follows its switch and the lock", function()
    local state = fixture()
    local ring = state.wtf.ShieldDisplay.frame
    equal(state.settings.WTF_SHIELD_ENABLED:GetValue(), true, "on by default")
    state.slash("unlock")
    equal(ring.shown, true, "a sample to drag")
    equal(state.wtf.db.shield.locked, false)
    state.slash("lock")
    equal(state.wtf.db.shield.locked, true)
    state.settings.WTF_SHIELD_ENABLED:SetValue(false)
    equal(state.wtf.db.shield.enabled, false)
    state.clear()
    state.slash("debug_shield")
    contains(state.messages[1], "debug_shield UnitGetTotalAbsorbs=function")
end)

-- Cooldown chimes ----------------------------------------------------------------

local DEATH_COIL = 6789

local function wait(state, seconds)
    state.now = state.now + seconds
    state.runTimers()
end

test("a chime plays just before Death Coil is ready again, also in combat", function()
    local state = fixture()
    state.combat = true
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", DEATH_COIL)
    wait(state, 0.1)
    wait(state, 119)
    equal(#state.sounds, 0, "not yet")
    wait(state, 0.5)
    equal(#state.sounds, 1, "half a second early")
    equal(state.sounds[1].kit, 73281, "Talent ready by default")
    equal(state.sounds[1].channel, "Master")
end)
test("out of combat the real cooldown is read and learned; switches turn chimes off", function()
    local state = fixture()
    state.cooldowns[DEATH_COIL] = {start = state.now, duration = 90}
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", DEATH_COIL)
    wait(state, 0.1)
    equal(state.wtf.db.chimes.learned.deathcoil, 90, "Forever's own cooldown")
    wait(state, 89.5)
    equal(#state.sounds, 1)
    state.settings.WTF_CHIME_DEATHCOIL:SetValue(false)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", DEATH_COIL)
    wait(state, 100)
    equal(#state.sounds, 1, "its switch")
    state.settings.WTF_CHIME_DEATHCOIL:SetValue(true)
    state.settings.WTF_CHIMES_ENABLED:SetValue(false)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", DEATH_COIL)
    wait(state, 100)
    equal(#state.sounds, 1, "the module switch")
end)
test("each chime has its own sound from the Cooldown Manager's catalog, and choosing one plays it", function()
    local state = fixture()
    local sound = state.settings.WTF_CHIME_SOUND_HOWL
    equal(sound:GetValue(), "talent")
    sound:SetValue("impactspopclick")
    equal(state.wtf.db.chimes.sounds.howl, "impactspopclick")
    equal(state.sounds[#state.sounds].kit, 316434, "previewed: the Cooldown Manager's Pop click")
    equal(state.wtf.db.chimes.sounds.deathcoil, "talent", "Death Coil keeps its own")
    sound:SetValue("nonsense")
    equal(state.wtf.db.chimes.sounds.howl, "impactspopclick", "unknown keys are ignored")
    local saved = fixture({db = {chimes = {sounds = {howl = "bogus"}, lead = 7, spells = {inferno = true}}}})
    equal(saved.wtf.db.chimes.sounds.howl, "talent")
    equal(saved.wtf.db.chimes.lead, 3, "clamped")
    equal(saved.wtf.db.chimes.spells.inferno, true)
    state.clear()
    state.slash("debug_chimes")
    contains(state.messages[1], "debug_chimes deathcoil name=Death Coil")
end)

test("a copy registered first whose AddOn stays off does not keep WTF's display away", function()
    -- MTF loads first (folder order) but stays off on a Warlock.
    local state = fixture({shieldCopies = {{addon = "MageToolsForever", version = 3, before = true}}})
    equal(state.wtf.ShieldDisplay.IsOwner(), true, "only running copies take part")
    equal(state.wtf.ShieldDisplay.frame ~= nil, true, "WTF draws the ring")
    state.clear()
    state.slash("debug_shield")
    contains(table.concat(state.messages, "|"),
        "owner=WarlockToolsForever copies=MageToolsForever v3, WarlockToolsForever v3 (running)")
    equal(table.concat(state.messages, "|"):find("failed", 1, true), nil, "every debug step ran")
end)
test("a newer running copy takes over, and WTF says which AddOn shows the display", function()
    local state = fixture({shieldCopies = {{addon = "ShieldForever", version = 4}}})
    equal(state.wtf.ShieldDisplay.frame ~= nil, true, "drawing while it is the only one running")
    local other = state.copies.ShieldForever.ShieldDisplay
    other.Initialize({settings = function() return other.Sanitize({}) end, report = function() end})
    equal(state.wtf.ShieldDisplay.frame, nil, "WTF stood down")
    equal(other.frame ~= nil, true, "the newer copy draws")
    contains(state.last(), "The shield display is shown by ShieldForever")
end)
test("a Warlock's icon row holds Shadow Ward, Sacrifice, and Power Word: Shield, one spot each", function()
    local state = fixture()
    local ring = state.wtf.ShieldDisplay.frame
    local keys = {}
    for _, slot in ipairs(ring.icons.slots) do keys[#keys + 1] = slot.key end
    table.sort(keys)
    equal(table.concat(keys, ","), "blessingofprotection,powerwordshield,sacrifice,shadowward",
        "no Mage or Paladin-only shields")
    local ward, sacrifice, shield = ring.iconButtons.shadowward, ring.iconButtons.sacrifice,
        ring.iconButtons.powerwordshield
    local x1, x2, x3 = ward.points[1][4], sacrifice.points[1][4], shield.points[1][4]
    equal(x2 - x1, x3 - x2, "evenly spaced")
    equal(x1 < x2, true, "never on top of each other; your own shields first")
end)

test("a bubble drains in the innermost crescent; in combat the display stays up for one", function()
    local state = fixture({spellbook = {}})
    local ring = state.wtf.ShieldDisplay.frame
    local bubble = ring.iconButtons.blessingofprotection
    local bar = bubble.display.bar
    contains(bar.statusBarTexture, "ShieldArcInnermost")
    equal(bar.barColor[1], 1, "gold")
    equal(bubble.display.barOptions.direction, 1, "drains with its time left")
    equal(ring.timedBars.blessingofprotection, bar)
    equal(ring.shown, false, "nothing up out of combat")
    -- In combat, a Blessing of Protection from a Paladin cannot be read, so
    -- the display stays shown and the engine draws the bubble when it is up.
    state.combat = true
    state.emit("PLAYER_REGEN_DISABLED")
    equal(ring.shown, true)
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(ring.shown, false, "hidden again once buffs can be read")
    state.slash("unlock")
    contains(ring.sample.children[2].texture, "ShieldArcInnermost", "the sample shows it too")
end)

test("a frame dropped near another snaps beside it, 20 apart and lined up", function()
    local state = stonesFixture()
    state.slash("unlock")
    local bar, counter = state.env.WarlockToolsForeverStones, state.wtf.shardCounter
    dropAt(state, bar, 400, 300)
    local barX, barY = centerOf(state, bar)
    local barHalfW, barHalfH = bar.width / 2, bar.height / 2
    local half = counter.width / 2
    -- Dropped a little right of the bar, near its top edge: tops line up.
    dropAt(state, counter, barX + barHalfW + 20 + half + 6, barY + barHalfH - (counter.height / 2) + 5)
    local x, y = centerOf(state, counter)
    equal(x, barX + barHalfW + 20 + half, "20 past the bar's right edge")
    equal(y + counter.height / 2, barY + barHalfH, "tops aligned")
    -- Under the bar, near its left edge: lefts line up.
    dropAt(state, counter, barX - barHalfW + half + 4, barY - barHalfH - 20 - counter.height / 2 - 7)
    x, y = centerOf(state, counter)
    equal(x - half, barX - barHalfW, "lefts aligned")
    equal(y + counter.height / 2, barY - barHalfH - 20, "20 below")
    -- Far away: it stays where it lands.
    dropAt(state, counter, 900, 100)
    equal(select(1, centerOf(state, counter)), 900)
end)
test("Shift-dragging a frame moves every frame snapped to it", function()
    local state = stonesFixture()
    state.slash("unlock")
    local bar, counter = state.env.WarlockToolsForeverStones, state.wtf.shardCounter
    dropAt(state, bar, 400, 300)
    local barX, barY = centerOf(state, bar)
    dropAt(state, counter, barX + bar.width / 2 + 20 + counter.width / 2 + 3, barY)
    local counterX, counterY = centerOf(state, counter)
    state.shift = true
    dropAt(state, bar, 150, 760)
    local newBarX, newBarY = centerOf(state, bar)
    local movedX, movedY = centerOf(state, counter)
    equal(movedX - newBarX, counterX - barX, "the counter came along, the same distance away")
    equal(movedY - newBarY, counterY - barY)
    equal(state.wtf.db.shards.counterPosition.relativePoint, "BOTTOMLEFT", "each saved on its own")
    state.shift = false
    dropAt(state, bar, 600, 600)
    equal(select(1, centerOf(state, counter)), movedX, "without Shift the bar leaves alone")
end)
test("a Shift-dragged group that snaps keeps its spacing", function()
    local state = stonesFixture()
    state.slash("unlock")
    local bar, counter = state.env.WarlockToolsForeverStones, state.wtf.shardCounter
    local tracker = state.env.WarlockToolsForeverTracker
    dropAt(state, bar, 400, 300)
    local barX, barY = centerOf(state, bar)
    dropAt(state, counter, barX + bar.width / 2 + 20 + counter.width / 2, barY)
    local gapX = select(1, centerOf(state, counter)) - barX
    -- Drop the group just off a spot beside the tracker, so it snaps.
    local trackerX, trackerY = centerOf(state, tracker)
    local spotY = trackerY - tracker.height / 2 - 20 - bar.height / 2
    state.shift = true
    dropAt(state, bar, trackerX - tracker.width / 2 + bar.width / 2 + 5, spotY - 6)
    local newBarX, newBarY = centerOf(state, bar)
    equal(newBarY, math.floor(spotY + 0.5), "the group snapped")
    equal(select(1, centerOf(state, counter)) - newBarX, gapX, "the counter kept its place beside the bar")
    equal(select(2, centerOf(state, counter)), newBarY)
end)
test("frames do not drag in combat or while locked", function()
    local state = stonesFixture()
    local bar = state.env.WarlockToolsForeverStones
    bar.scripts.OnDragStart(bar)
    equal(bar.moving, nil, "locked by default")
    state.slash("unlock")
    state.combat = true
    bar.scripts.OnDragStart(bar)
    equal(bar.moving, nil, "not in combat")
    local before = state.wtf.db.stones.position
    bar.scripts.OnDragStop(bar)
    equal(state.wtf.db.stones.position, before, "a drop without a drag saves nothing")
end)

test("one lock for every WTF frame, locked by default, with no per-frame switches", function()
    local state = fixture({db = {stones = {locked = false}, tracker = {locked = false, placeholders = true}}})
    local db = state.wtf.db
    equal(db.locked, true)
    equal(db.stones.locked, true, "older per-frame locks give way to the one lock")
    equal(db.tracker.locked, true)
    equal(db.tracker.placeholders, false)
    equal(db.shards.counterLocked, true)
    for _, variable in ipairs({"WTF_STONES_LOCKED", "WTF_TRACKER_LOCKED", "WTF_SHARDS_COUNTER_LOCKED",
        "WTF_TRACKER_PLACEHOLDERS"}) do
        equal(state.settings[variable], nil, variable .. " is gone")
    end
    state.settings.WTF_UNLOCKED:SetValue(true)
    equal(db.locked, false)
    equal(db.tracker.placeholders, true, "sample rows while unlocked")
end)
test("/wtf unlock and /wtf lock move every WTF frame together", function()
    local state = fixture()
    state.slash("unlock")
    local db = state.wtf.db
    equal(db.stones.locked, false)
    equal(db.tracker.locked, false)
    equal(db.tracker.placeholders, true, "sample rows to drag the tracker by")
    equal(db.shards.counterLocked, false)
    contains(state.last(), "All WTF frames unlocked: drag them where you want")
    equal(state.env.WarlockToolsForeverStones.mover.shown, true, "outlined")
    equal(state.wtf.shardCounter.mover.shown, true)
    equal(state.settings.WTF_UNLOCKED:GetValue(), true, "the main page's switch follows")
    state.slash("lock")
    equal(state.env.WarlockToolsForeverStones.mover.shown, false)
    equal(state.wtf.shardCounter.mover.shown, false)
    equal(db.stones.locked, true)
    equal(db.tracker.locked, true)
    equal(db.tracker.placeholders, false)
    equal(db.shards.counterLocked, true)
    equal(state.last(), "WTF: All WTF frames locked.")
end)
test("unlocked, a grid shows the screen's center; it follows its switch and the lock", function()
    local state = fixture()
    equal(state.wtf.grid, nil, "nothing built while locked")
    state.slash("unlock")
    local grid = state.wtf.grid
    equal(grid.shown, true)
    equal(grid.mouseDisabled, true, "never takes clicks")
    -- A 1000 x 800 screen, lines every 32 from the center: 15 + 15 + 12 + 12, then the two center lines.
    equal(#grid.lines, 56)
    local center = grid.lines[#grid.lines]
    equal(center.color[2], 0.2, "the center lines are red")
    equal(center.height, 2)
    state.settings.WTF_GRID:SetValue(false)
    equal(grid.shown, false)
    state.settings.WTF_GRID:SetValue(true)
    equal(grid.shown, true)
    state.slash("lock")
    equal(grid.shown, false)
end)
test("/wtf reset moves the Stones bar back, after combat if needed", function()
    local state = stonesFixture({db = {stones = {position = {point = "TOP", relativePoint = "TOP", x = 1, y = 2}}}})
    local bar = state.env.WarlockToolsForeverStones
    equal(bar.points[1][1], "TOP")
    state.combat = true
    state.slash("reset")
    equal(state.wtf.db.stones.position, nil)
    equal(state.last(), "WTF: WTF frames move back to their default places after combat.")
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
    contains(state.tooltip[5], "the \"! Soulstone\" macro")
end)
test("Spellstone and Firestone show as greyed-out Coming soon switches", function()
    local state = fixture()
    for _, variable in ipairs({"WTF_STONES_SPELLSTONE", "WTF_STONES_FIRESTONE", "WTF_STONES_REMIND_SPELLSTONE",
        "WTF_STONES_REMIND_FIRESTONE"}) do
        local setting = state.settings[variable]
        contains(setting.name, "(Coming soon)")
        equal(setting:GetValue(), false)
        setting:SetValue(true)
        equal(setting:GetValue(), false, "never turns on")
    end
    local disabled = 0
    for _, initializer in ipairs(state.categories.Stones.initializers) do
        local predicate = initializer.modifyPredicates[1]
        if predicate and predicate() == false then disabled = disabled + 1 end
    end
    equal(disabled, 4)
    equal(state.wtf.db.stones.spellstone, nil, "nothing saved")
end)
test("debug_stones lists ranks, carried stones, and level requirements", function()
    local state = stonesFixture()
    state.clear()
    state.slash("debug_stones")
    contains(state.messages[2], "soulstone spell=20752 name=Create Soulstone known=true items=16892x1 minLevel=30")
    contains(state.messages[6], "healthstone spell=6201 name=Create Healthstone known=true items=5512x0 minLevel=1")
    contains(table.concat(state.messages, "|"), "targetLevel=nil healthstoneRank=5699 pending=false")
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

-- Healthstone trading and stone status ---------------------------------------

local function bagWith(itemID, count)
    return {[0] = {size = 16, family = 0, items = {[1] = {itemID = itemID, stackCount = count or 1}}},
        [1] = {size = 0, family = 0, items = {}}, [2] = {size = 0, family = 0, items = {}},
        [3] = {size = 0, family = 0, items = {}}, [4] = {size = 0, family = 0, items = {}}}
end

test("with a friend targeted, left-click trades a Healthstone they can use", function()
    local state = stonesFixture({carried = {[5511] = 1}, bags = bagWith(5511),
        units = {target = {name = "Lowbie", player = true, friend = true, level = 20}}})
    local health = state.env[HEALTH]
    equal(health.mode, "trade")
    equal(health.attributes.type1, nil, "no secure action: WTF opens the trade")
    state.clickButton(HEALTH, "LeftButton")
    equal(state.tradeWith, "target")
    state.clear()
    state.emit("TRADE_SHOW")
    equal(state.tradeSlots[1], 5511)
    equal(state.cursor, nil)
    equal(state.last(), "WTF: Healthstone in the trade window. Press Trade to give it.")
end)
test("without a Healthstone they can use, left-click creates one for them", function()
    local state = stonesFixture({carried = {[5509] = 1},
        units = {target = {name = "Lowbie", player = true, friend = true, level = 20}}})
    local health = state.env[HEALTH]
    equal(health.mode, "create", "Healthstone needs level 24")
    equal(health.attributes.type1, "spell")
    equal(health.attributes.spell1, 6202, "the Lesser rank, for level 20")
    health.scripts.OnEnter(health)
    contains(state.tooltip[2], "then left-click again to trade it")
end)
test("the Healthstone gift whisper goes when the trade window opens", function()
    local state = stonesFixture({carried = {[5511] = 1}, bags = bagWith(5511),
        units = {target = {name = "Meatrod", surname = "Theog", player = true, friend = true, level = 20}}})
    state.clickButton(HEALTH, "LeftButton")
    equal(#state.sent, 0, "nothing before the window opens")
    state.emit("TRADE_SHOW")
    equal(#state.sent, 1)
    equal(state.sent[1].chatType, "WHISPER")
    equal(state.sent[1].target, "Meatrod-Theog")
    equal(state.sent[1].message, "Here, have a Healthstone. Some poor creature's essence gives you more health! Courtesy of Warlock Tools Forever (WTF)")
    state.emit("TRADE_CLOSED")
    state.emit("TRADE_SHOW")
    equal(#state.sent, 1, "a later trade WTF did not start gets none")
    state.clear()
    state.slash("debug_stones")
    local text = table.concat(state.messages, "|")
    contains(text, "lastGiftWhisper=Meatrod-Theog")
    contains(text, "TRADE_SHOW")
end)
test("no gift whisper for a late window, or with it off", function()
    local options = {carried = {[5511] = 1}, bags = bagWith(5511),
        units = {target = {name = "Lowbie", player = true, friend = true, level = 20}}}
    local late = stonesFixture(options)
    late.clickButton(HEALTH, "LeftButton")
    late.now = late.now + 30
    late.emit("TRADE_SHOW")
    equal(#late.sent, 0)
    local off = stonesFixture(options)
    off.wtf.db.announce.healthstoneWhisper = false
    off.clickButton(HEALTH, "LeftButton")
    off.emit("TRADE_SHOW")
    equal(#off.sent, 0)
    equal(off.tradeSlots[1], 5511, "the stone still goes in")
end)
test("saved texts that match an old default gain the credit; edited ones do not", function()
    local state = fixture({db = {announce = {summonGroupText = "Summoning >> %T << click please",
        soulstoneGroupText = "Stone on %T", soulstoneWhisperText = "I've applied a soulstone to you, this means if you die, you can revive yourself where you fell. So, if you're going to die, die in a good spot. - via Warlock Tools Forever (WTF)"}}})
    local settings = state.wtf.db.announce
    equal(settings.summonGroupText, "The ritual hungers! Click the portal to drag >> %T << through the Twisting Nether - via Warlock Tools Forever (WTF)")
    equal(settings.soulstoneGroupText, "Stone on %T")
    equal(settings.soulstoneWhisperText, state.wtf.ANNOUNCE_DEFAULTS.soulstoneWhisperText)
    equal(settings.healthstoneWhisper, true)
    for key, text in pairs(state.wtf.ANNOUNCE_DEFAULTS) do
        if #text > state.wtf.ANNOUNCE_MAX_LENGTH then error(key .. " is over the chat limit") end
    end
end)
test("a refused trade placement waits for the next key press, once", function()
    local state = stonesFixture({carried = {[5511] = 1}, bags = bagWith(5511),
        units = {target = {name = "Lowbie", player = true, friend = true, level = 20}}})
    state.tradeNeedsHardware = true
    state.clickButton(HEALTH, "LeftButton")
    state.emit("TRADE_SHOW")
    equal(state.tradeSlots[1], nil)
    equal(state.cursor, nil, "the stone is back in the bag")
    state.press()
    equal(state.tradeSlots[1], 5511, "placed on the key press")
end)
test("a trade window long after the click, or from someone else, gets nothing", function()
    local state = stonesFixture({carried = {[5511] = 1}, bags = bagWith(5511),
        units = {target = {name = "Lowbie", player = true, friend = true, level = 20}}})
    state.clickButton(HEALTH, "LeftButton")
    state.now = state.now + 30
    state.emit("TRADE_SHOW")
    equal(state.tradeSlots[1], nil)
    state.emit("TRADE_SHOW")
    equal(state.tradeSlots[1], nil, "no request pending")
end)
test("a Soulstone on someone is remembered, reported, and announced when it ends", function()
    local state = stonesFixture()
    state.emit("UNIT_SPELLCAST_SENT", "player", "Meatrod-Theog", "ss", 20707)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "ss", 20707)
    equal(state.wtf.db.stones.soulstone.name, "Meatrod Theog")
    state.clear()
    state.slash("stones")
    equal(state.messages[1], "WTF: Soulstone on Meatrod Theog, 30 min left.")
    contains(state.messages[2], "You carry 3 Soulstone(s) and 1 Healthstone(s).")
    state.now = state.now + 30 * 60 + 2
    state.clear()
    state.runTimers()
    equal(state.messages[1], "WTF: Your Soulstone on Meatrod Theog has ended.")
    contains(state.messages[2], "No Soulstone is up. Left-click the Soulstone button to apply one.")
    equal(state.wtf.db.stones.soulstone, nil)
end)
test("a Soulstone on yourself is remembered as on you", function()
    local state = stonesFixture()
    state.emit("UNIT_SPELLCAST_SENT", "player", "Dyre-Maebryn", "ss", 20707)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "ss", 20707)
    equal(state.wtf.db.stones.soulstone.name, "you")
end)
test("a remembered Soulstone survives a reload until it ends", function()
    local state = stonesFixture({db = {stones = {soulstone = {name = "Tank", ends = 1000000 + 100 + 600}}}})
    state.clear()
    state.slash("stones")
    equal(state.messages[1], "WTF: Soulstone on Tank, 10 min left.")
end)
test("reminders come after a fight, in an instance, or in a new group, at most every 10 minutes", function()
    local state = stonesFixture({carried = {}})
    state.clear()
    state.emit("PLAYER_REGEN_ENABLED")
    equal(#state.messages, 2)
    contains(state.messages[1], "No Soulstone is up. Right-click the Soulstone button to create one.")
    contains(state.messages[2], "You carry no Healthstone.")
    state.clear()
    state.emit("GROUP_JOINED")
    equal(#state.messages, 0, "throttled")
    state.now = state.now + 601
    state.inInstance = true
    state.emit("PLAYER_ENTERING_WORLD")
    equal(#state.messages, 2)
end)
test("reminders can be turned off, and need a known rank", function()
    local state = stonesFixture({carried = {}, db = {stones = {remindSoulstone = false}}})
    state.clear()
    state.emit("PLAYER_REGEN_ENABLED")
    equal(#state.messages, 1)
    contains(state.last(), "no Healthstone")
    local novice = fixture()
    novice.clear()
    novice.emit("PLAYER_REGEN_ENABLED")
    equal(#novice.messages, 0, "no rank known yet")
end)

-- Alerts: the Nightfall sound ------------------------------------------------------

local function liveSounds(state)
    local list = {}
    for _, sound in pairs(state.auraSounds or {}) do list[#list + 1] = sound end
    return list
end

test("the Nightfall sound is off by default", function()
    local state = fixture()
    equal(state.wtf.db.alerts.nightfall, false)
    equal(#liveSounds(state), 0)
end)
test("turned on, the game plays the chosen sound when Shadow Trance appears", function()
    local state = fixture()
    state.settings.WTF_ALERTS_NIGHTFALL:SetValue(true)
    local sounds = liveSounds(state)
    equal(#sounds, 1)
    equal(sounds[1].trigger, 0, "on the buff appearing")
    equal(sounds[1].info.spellID, 17941)
    equal(sounds[1].info.unitToken, "player")
    equal(sounds[1].info.soundFileID, 639156, "the Imp spell chirp by file ID")
    equal(sounds[1].info.soundFileName, nil)
    state.settings.WTF_ALERTS_NIGHTFALL_SOUND:SetValue("readycheck")
    sounds = liveSounds(state)
    equal(#sounds, 1, "the old sound is replaced")
    equal(sounds[1].info.soundFileName, "Sound\\Interface\\ReadyCheck.ogg")
    equal(state.played.file, "Sound\\Interface\\ReadyCheck.ogg", "choosing a sound previews it")
    state.settings.WTF_ALERTS_NIGHTFALL:SetValue(false)
    equal(#liveSounds(state), 0)
end)
test("a sound change during an encounter waits until it ends", function()
    local state = fixture()
    state.encounter = true
    state.settings.WTF_ALERTS_NIGHTFALL:SetValue(true)
    equal(#liveSounds(state), 0)
    state.encounter = false
    state.emit("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
    equal(#liveSounds(state), 1)
end)
test("the Nightfall setting survives a reload and bad saved values are repaired", function()
    local state = fixture({db = {alerts = {nightfall = true, nightfallSound = "alarm"}}})
    equal(liveSounds(state)[1].info.soundFileName, "Sound\\Interface\\AlarmClockWarning3.ogg")
    local repaired = fixture({db = {alerts = {nightfall = "yes", nightfallSound = "kazoo"}}})
    equal(repaired.wtf.db.alerts.nightfall, false)
    equal(repaired.wtf.db.alerts.nightfallSound, "impspell")
end)
test("the Alerts page has the switch and a sound dropdown under it", function()
    local state = fixture()
    local page = state.categories.Alerts
    equal(page.initializers[1].setting.variable, "WTF_ALERTS_NIGHTFALL")
    local dropdown = page.initializers[2]
    equal(dropdown.parentInitializer, page.initializers[1])
    local choices = dropdown.choices()
    equal(#choices, 16)
    equal(choices[1].label, "Imp: Laugh 1")
    equal(choices[14].label, "Interface: Raid warning")
end)

-- A menu description as the client's menu API builds it: buttons open submenus.
local function menuDescription()
    local description = {entries = {}}
    function description:CreateButton(text)
        local submenu = menuDescription()
        submenu.text = text
        self.entries[#self.entries + 1] = submenu
        return submenu
    end
    function description:CreateRadio(text, isSelected, setSelected, data)
        local radio = {text = text, data = data, isSelected = isSelected, setSelected = setSelected}
        self.entries[#self.entries + 1] = radio
        return radio
    end
    return description
end

-- Opens a dropdown as the client would: a pooled control, with Blizzard's
-- own builder, is initialized for it.
local function openMenu(dropdown, setting)
    dropdown.GetSetting = function() return setting end
    local control = {Dropdown = {}}
    function control:SetupDropdownMenu() self.blizzardMenu = true end
    function control:Init(initializer)
        self:SetupDropdownMenu(self.Dropdown, initializer.setting, nil, nil, initializer)
    end
    dropdown:InitFrame(control)
    control:Init(dropdown)
    local root = menuDescription()
    control.Dropdown.inserter(control.Dropdown.setting, root)
    return root, control
end

local function groupNames(root)
    local names = {}
    for _, entry in ipairs(root.entries) do names[#names + 1] = entry.text end
    return table.concat(names, ",")
end

test("the Nightfall sound is picked from a menu of submenus", function()
    local state = fixture()
    local page = state.categories.Alerts
    local dropdown, setting = page.initializers[2], state.settings.WTF_ALERTS_NIGHTFALL_SOUND
    equal(dropdown.data.forceSteppersHidden, true)
    local root = openMenu(dropdown, setting)
    equal(groupNames(root), "Imp,Hellish imp,Interface")
    local imp = root.entries[1]
    equal(imp.entries[1].text, "Laugh 1", "names inside their group")
    imp.entries[1].setSelected(imp.entries[1].data)
    equal(state.wtf.db.alerts.nightfallSound, "implaugh1")
    equal(state.played.file, 639142, "choosing one plays it")
    equal(dropdown.getSelectionTextFunc(), "Imp: Laugh 1")
end)
test("each chime's sound menu has the Cooldown Manager's groups; other dropdowns keep Blizzard's", function()
    local state = fixture()
    local page = state.categories["Cooldown Chimes"]
    local setting = state.settings.WTF_CHIME_SOUND_DEATHCOIL
    local dropdown
    for _, initializer in ipairs(page.initializers) do
        if initializer.setting == setting then dropdown = initializer end
    end
    local root, control = openMenu(dropdown, setting)
    equal(groupNames(root), "Interface,Animals,Devices,Impacts,Instruments,Short,Warcraft 2,Warcraft 3")
    equal(control.blizzardMenu, nil, "WTF's own menu")
    control.Dropdown.inserter = nil
    control:Init({setting = {}})
    equal(control.blizzardMenu, true, "another dropdown gets Blizzard's menu")
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
    equal(state.sent[1].message, "The ritual hungers! Click the portal to drag >> Friend << through the Twisting Nether - via Warlock Tools Forever (WTF)")
    equal(state.sent[1].chatType, "PARTY")
    equal(state.sent[2].chatType, "WHISPER")
    equal(state.sent[2].target, "Friend")
    equal(state.sent[2].message, "Summoning you to Redridge Mountains, since your sloth-like pace would get you there sometime next week. Accept the summon when it pops up (and tell me if it doesn't). Courtesy of Warlock Tools Forever (WTF)")
end)
test("a Soulstone use tells the raid and whispers the author's text", function()
    local state = fixture({group = "raid"})
    cast(state, 20762, "Tank")
    equal(state.sent[1].message, "A piece of >> Tank <<'s soul now rests in my keeping. Death is merely an inconvenience - via Warlock Tools Forever (WTF)")
    equal(state.sent[1].chatType, "RAID")
    equal(state.sent[2].message, "I've trapped a sliver of your soul in a stone. If you die, it drags you back to life right where you fell, so if you're going to die, die in a good spot. Courtesy of Warlock Tools Forever (WTF)")
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
    cast(state, 20707, "Friend", "UNIT_SPELLCAST_INTERRUPTED")
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-20707", 20707)
    cast(state, 20707, "Dyre")
    cast(state, 686, "Boar")
    local hidden = secret()
    state.secrets[hidden] = true
    cast(state, 698, hidden)
    equal(#state.sent, 0)
end)
test("a summon is announced when the ritual starts, once", function()
    local state = fixture({group = "raid"})
    state.emit("UNIT_SPELLCAST_SENT", "player", "Friend", "ritual", 698)
    equal(#state.sent, 0, "not yet: only sent")
    state.emit("UNIT_SPELLCAST_START", "player", "ritual", 698)
    equal(#state.sent, 2)
    equal(state.sent[1].message, "The ritual hungers! Click the portal to drag >> Friend << through the Twisting Nether - via Warlock Tools Forever (WTF)")
    equal(state.sent[1].chatType, "RAID")
    state.emit("UNIT_SPELLCAST_CHANNEL_START", "player", "ritual", 698)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "ritual", 698)
    equal(#state.sent, 2, "start, channel start, and success announce once")
    state.now = state.now + 30
    state.emit("UNIT_SPELLCAST_SENT", "player", "Friend", "ritual2", 698)
    state.emit("UNIT_SPELLCAST_CHANNEL_START", "player", "ritual2", 698)
    equal(#state.sent, 4, "the next ritual is announced again")
end)
test("a ritual that names no target uses your friendly player target", function()
    local state = fixture({group = "party", units = {target = {name = "Friend", player = true, friend = true}}})
    state.emit("UNIT_SPELLCAST_SENT", "player", "", "ritual", 698)
    state.emit("UNIT_SPELLCAST_CHANNEL_START", "player", "ritual", 698)
    equal(#state.sent, 2)
    equal(state.sent[1].message, "The ritual hungers! Click the portal to drag >> Friend << through the Twisting Nether - via Warlock Tools Forever (WTF)")
    equal(state.sent[2].target, "Friend")
    local alone = fixture({group = "party", units = {target = {name = "Boar"}}})
    alone.emit("UNIT_SPELLCAST_SENT", "player", "", "ritual", 698)
    alone.emit("UNIT_SPELLCAST_START", "player", "ritual", 698)
    equal(#alone.sent, 0, "no friendly player target, no announcement")
end)
test("creating a stone emotes on your next key press, at most once a minute per stone", function()
    local state = fixture()
    cast(state, 6202, "")
    equal(#state.sent, 0, "not from the cast event, which the game blocks")
    state.press()
    equal(#state.sent, 1)
    equal(state.sent[1].chatType, "EMOTE")
    equal(state.sent[1].message, "crushes a Soul Shard and forges a Healthstone from the screaming essence within. - via Warlock Tools Forever (WTF)")
    cast(state, 5699, "")
    state.press()
    equal(#state.sent, 1, "a second Healthstone within the minute stays quiet")
    cast(state, 693, "")
    state.press()
    equal(state.sent[2].message, "binds a captured soul into a Soulstone. Someone's afterlife just got an escape hatch. - via Warlock Tools Forever (WTF)")
    state.press()
    equal(#state.sent, 2, "sent once")
    state.now = state.now + 61
    cast(state, 6201, "")
    state.now = state.now + 31
    state.press()
    equal(#state.sent, 2, "dropped when no key press came soon")
    state.now = state.now + 61
    cast(state, 6201, "", "UNIT_SPELLCAST_FAILED")
    state.press()
    equal(#state.sent, 2, "a failed cast sends nothing")
    local off = fixture()
    off.wtf.db.announce.healthstoneEmote = false
    cast(off, 6201, "")
    off.press()
    equal(#off.sent, 0)
end)
test("debug_emote tries both chat functions from a timer and reports each", function()
    local state = fixture()
    state.env.SendChatMessage = function(message, chatType)
        state.sent[#state.sent + 1] = {message = message, chatType = chatType, global = true}
    end
    state.slash("debug_emote")
    state.clear()
    state.now = state.now + 3
    state.runTimers()
    local text = table.concat(state.messages, "|")
    contains(text, "debug_emote C_ChatInfo.SendChatMessage from a timer: blocked")
    contains(text, "debug_emote SendChatMessage from a timer: not blocked")
    equal(#state.sent, 1)
    equal(state.sent[1].global, true)
    equal(state.sent[1].chatType, "EMOTE")
end)
test("a blocked emote is reported once", function()
    local state = fixture()
    state.env.C_ChatInfo.SendChatMessage = function()
        state.emit("ADDON_ACTION_BLOCKED", "WarlockToolsForever", "UNKNOWN()")
    end
    cast(state, 6201, "")
    state.press()
    state.now = state.now + 61
    cast(state, 6201, "")
    state.press()
    local text = table.concat(state.messages, "|")
    contains(text, "The game blocked the emote message. Turn it off in the Announce settings.")
    local _, count = text:gsub("blocked the emote", "")
    equal(count, 1)
end)
test("whispers go to the full First-Last name", function()
    -- In client, "Meatrod Theog" got no whisper: "No player named 'Meatrod'".
    local state = fixture({group = "party",
        units = {target = {name = "Meatrod", surname = "Theog", player = true, friend = true}}})
    state.emit("UNIT_SPELLCAST_SENT", "player", nil, "ritual", 698)
    state.emit("UNIT_SPELLCAST_CHANNEL_START", "player", "ritual", 698)
    equal(state.sent[1].message, "The ritual hungers! Click the portal to drag >> Meatrod Theog << through the Twisting Nether - via Warlock Tools Forever (WTF)", "%T is the full name")
    equal(state.sent[2].target, "Meatrod-Theog")
    state.emit("UNIT_SPELLCAST_SENT", "player", "Meatrod", "stone", 20707)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "stone", 20707)
    equal(state.sent[4].target, "Meatrod-Theog", "a Soulstone on your target too")
    equal(state.sent[3].message, "A piece of >> Meatrod Theog <<'s soul now rests in my keeping. Death is merely an inconvenience - via Warlock Tools Forever (WTF)")
    state.units.target = nil
    state.emit("UNIT_SPELLCAST_SENT", "player", "Ryla-Stone", "stone2", 20707)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "stone2", 20707)
    equal(state.sent[5].message, "A piece of >> Ryla Stone <<'s soul now rests in my keeping. Death is merely an inconvenience - via Warlock Tools Forever (WTF)", "a First-Last cast name, not targeted")
    equal(state.sent[6].target, "Ryla-Stone")
    state.clear()
    state.slash("debug_announce")
    contains(state.messages[1], "lastWhisper=Ryla-Stone")
end)
test("a Soulstone on yourself announces nothing, with or without your last name", function()
    -- In client a Soulstone on yourself was whispered to you.
    local state = fixture({group = "party"})
    for index, name in ipairs({"Dyre", "Dyre-Maebryn", "Dyre-Mae bryn"}) do
        state.emit("UNIT_SPELLCAST_SENT", "player", name, "self" .. index, 20707)
        state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "self" .. index, 20707)
    end
    equal(#state.sent, 0)
    state.emit("UNIT_SPELLCAST_SENT", "player", "Dyre-Theog", "other", 20707)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "other", 20707)
    equal(#state.sent, 2, "someone with your first name and another last name is someone else")
end)
test("debug_announce shows the spell names and the latest cast events", function()
    local state = fixture({group = "party"})
    state.emit("UNIT_SPELLCAST_SENT", "player", "", "ritual", 698)
    state.emit("UNIT_SPELLCAST_START", "player", "ritual", 698)
    state.emit("UNIT_SPELLCAST_SENT", "player", "Boar", "bolt", 686)
    state.clear()
    state.slash("debug_announce")
    equal(state.messages[1],
        "WTF: debug_announce summon=Ritual of Summoning soulstone=Soulstone Resurrection enabled=true channel=group group=PARTY lastWhisper=nil")
    contains(state.messages[2], "UNIT_SPELLCAST_START spell=698 target=nil")
    contains(state.messages[3], "UNIT_SPELLCAST_SENT spell=698 target=")
    equal(#state.messages, 3, "other spells are not logged")
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
    state.now = state.now + 30
    cast(state, 698, "Friend")
    state.now = state.now + 30
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
    equal(row.edit.text, "The ritual hungers! Click the portal to drag >> %T << through the Twisting Nether - via Warlock Tools Forever (WTF)")
    row.edit.text = "  Port >> %T <<  "
    row.edit.scripts.OnEnterPressed(row.edit)
    equal(state.wtf.db.announce.summonGroupText, "Port >> %T <<")
    row.edit.text = "typing"
    row.edit.scripts.OnEscapePressed(row.edit)
    equal(row.edit.text, "Port >> %T <<", "Escape undoes the edit")
    row.edit.text = "Port >> %T <<\nnow"
    row.edit.scripts.OnEnterPressed(row.edit)
    equal(state.wtf.db.announce.summonGroupText, "Port >> %T << now", "a stray new line becomes a space")
    row.check.checked = false
    row.check.scripts.OnClick(row.check)
    equal(state.wtf.db.announce.summonGroup, false)
    page.channels[2].scripts.OnClick(page.channels[2])
    equal(state.wtf.db.announce.channel, "say")
    equal(page.channels[1].checked, false)
    page:OnDefault()
    equal(state.wtf.db.announce.channel, "group")
    equal(state.wtf.db.announce.summonGroup, true)
    equal(state.wtf.db.announce.summonGroupText, "The ritual hungers! Click the portal to drag >> %T << through the Twisting Nether - via Warlock Tools Forever (WTF)")
end)

-- DoT tracker -------------------------------------------------------------------

local ROW_STEP = 32
-- The target row's outline (3) and gap (2) plus 2 spare pixels.
local TARGET_SPACING = 7

local function trackerFixture(extra)
    local options = {units = {
        target = {name = "Boar", guid = "Creature-1"},
        nameplate3 = {name = "Boar", guid = "Creature-1"},
        nameplate4 = {name = "Wolf", guid = "Creature-2"},
    }, spellbook = {{spellID = 6222, name = "Corruption"}, {spellID = 348, name = "Immolate"},
        {spellID = 5782, name = "Fear"}, {spellID = 980, name = "Curse of Agony"},
        {spellID = 702, name = "Curse of Weakness"}}}
    for key, value in pairs(extra or {}) do options[key] = value end
    options.db = options.db or {}
    options.db.tracker = options.db.tracker or {}
    options.db.tracker.theme = options.db.tracker.theme or "compact"
    local state = fixture(options)
    state.anchor = state.env.WarlockToolsForeverTracker
    state.list = state.env.WarlockToolsForeverTrackerList
    for _, frame in ipairs(state.frames) do
        if frame.parent == state.anchor and frame.container then
            if frame.unit == "target" then state.targetRow = frame else state.focusRow = frame end
        end
    end
    return state
end

local function listRows(state)
    local rows = {}
    for _, frame in ipairs(state.frames) do
        if frame.parent == state.list and frame.container then rows[#rows + 1] = frame end
    end
    return rows
end

local function shownRows(state)
    local rows = {}
    for _, row in ipairs(listRows(state)) do
        if row.shown then rows[#rows + 1] = row end
    end
    table.sort(rows, function(a, b) return a.points[#a.points][5] > b.points[#b.points][5] end)
    return rows
end

-- The current rows: a rebuild leaves the old frames behind, hidden.
local function currentRows(state)
    local rows = listRows(state)
    local current = {}
    for index = #rows - 7, #rows do current[#current + 1] = rows[index] end
    return current
end

local function pinnedRow(state, unit)
    local found
    for _, frame in ipairs(state.frames) do
        if frame.parent == state.anchor and frame.container and frame.unit == unit then found = frame end
    end
    return found
end

local function slotByKey(container, key)
    for _, slot in ipairs(container.slots) do
        if slot.key == key then return slot end
    end
end

local function listOffset(state)
    return state.list.points[#state.list.points][5]
end

local function dot(state, spellID, target)
    state.emit("UNIT_SPELLCAST_SENT", "player", target, "dot-" .. spellID .. target, spellID)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "dot-" .. spellID .. target, spellID)
end

test("the tracker has pinned target and focus rows and eight list rows of engine slots", function()
    local state = trackerFixture()
    equal(state.targetRow.container.unit, "target")
    equal(state.focusRow.container.unit, "focus")
    equal(state.targetRow.backdropBorder[1], 0.53, "warlock purple")
    equal(state.targetRow.backdropBorder[3], 0.93)
    equal(state.focusRow.outline.backdrop.edgeSize, 3, "the focus row has the same outline")
    equal(state.focusRow.outline.backdropBorder[1], 0.9, "in red")
    equal(state.focusRow.outline.backdropBorder[2], 0.1)
    equal(state.focusRow.outline.points[1][2], -5)
    local outline = state.targetRow.outline
    equal(outline.backdrop.edgeSize, 3, "a solid 3-pixel target outline")
    equal(outline.backdrop.edgeFile, "Interface\\Buttons\\WHITE8X8")
    equal(outline.backdropBorder[1], 0.53)
    equal(outline.points[1][2], -5, "drawn outside the row")
    equal(state.focusRow.points[1][5], -(ROW_STEP + TARGET_SPACING), "the focus row sits clear of it")
    local rows = listRows(state)
    equal(#rows, 8)
    local container = rows[1].container
    local keys = {}
    for index, slot in ipairs(container.slots) do
        keys[index] = slot.key
        equal(slot.filter, "HARMFUL|PLAYER")
        equal(slot.button.clicks, false, "engine slots never take clicks")
        equal(slot.button.display.barOptions.direction, 1, "the bar counts down")
    end
    equal(table.concat(keys, ","), "curse,bane,corruption,immolate,control", "no Siphon Life: not known")
    equal(container.slots[3].ids[6222], true)
    for _, id in ipairs({5782, 5484, 6789, 710}) do
        equal(slotByKey(container, "control").ids[id], true, "Fear, Howl of Terror, Death Coil, Banish")
    end
    equal(container.slots[2].ids[980], true, "Curse of Agony as a Bane")
    equal(container.unit, nil, "list rows start unbound")
    equal(state.list.shown, false, "the list hides until a mob is DoTed")
end)
test("the pinned rows show only while target or focus is a live hostile", function()
    local state = trackerFixture()
    equal(state.targetRow.shown, true)
    equal(state.focusRow.shown, false, "no focus")
    equal(state.drivers[state.focusRow], "[@focus,harm,nodead] show; hide")
    state.units.focus = {name = "Wolf", guid = "Creature-2"}
    state.applyDrivers()
    equal(state.focusRow.shown, true)
    state.units.target = {name = "Friend", guid = "Player-1", friend = true}
    state.applyDrivers()
    equal(state.targetRow.shown, false)
end)
test("pinned slots recast on target or focus by spell name", function()
    local state = trackerFixture()
    local casts = state.targetRow.casts
    equal(casts[3].template, "SecureActionButtonTemplate")
    equal(casts[3].attributes.macrotext1, "/cast [@target,harm,nodead] Corruption")
    equal(casts[4].attributes.macrotext1, "/cast [@target,harm,nodead] Immolate")
    equal(casts[5], nil, "no Siphon Life slot: not known")
    equal(casts[2].attributes.macrotext1, "/cast [@target,harm,nodead] Curse of Agony",
        "Agony until another Bane is used")
    equal(casts[1].attributes.type1, nil, "no Curse used yet")
    equal(casts[6].attributes.macrotext1, "/cast [@target,harm,nodead] Fear")
    equal(state.focusRow.casts[3].attributes.macrotext1, "/cast [@focus,harm,nodead] Corruption")
    casts[1].scripts.OnEnter(casts[1])
    contains(state.tooltip[1], "it recasts the last one you used")
end)
test("Bane and Curse slots recast the last one used, changed after combat", function()
    local state = trackerFixture()
    state.combat = true
    dot(state, 702, "Boar")
    equal(state.targetRow.casts[1].attributes.type1, nil, "no change in combat")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(state.targetRow.casts[1].attributes.macrotext1, "/cast [@target,harm,nodead] Curse of Weakness")
    dot(state, 980, "Boar")
    equal(state.focusRow.casts[2].attributes.macrotext1, "/cast [@focus,harm,nodead] Curse of Agony")
    equal(state.wtf.db.tracker.lastBane, "Curse of Agony")
    local reloaded = trackerFixture({db = {tracker = {lastCurse = "Curse of Weakness"}}})
    equal(reloaded.targetRow.casts[1].attributes.macrotext1, "/cast [@target,harm,nodead] Curse of Weakness")
end)
test("spellbook ranks with a tracked name join the slot, Banes by name", function()
    local state = trackerFixture({spellbook = {
        {spellID = 990001, name = "Bane of Agony"}, {spellID = 6223, name = "Corruption"},
        {spellID = 990002, name = "Corruption"}, {spellID = 686, name = "Shadow Bolt"}}})
    local container = listRows(state)[1].container
    equal(slotByKey(container, "bane").ids[990001], true)
    equal(slotByKey(container, "corruption").ids[990002], true)
    equal(slotByKey(state.targetRow.container, "corruption").ids[990002], true)
    state.clear()
    state.slash("debug_tracker")
    contains(state.messages[4], "slot=corruption recast=Corruption matches=ids ids=172,6222,6223,7648,11671,11672,25311,990002")
    state.emit("UNIT_SPELLCAST_SENT", "player", "Boar", "c1", 702)
    state.emit("UNIT_SPELLCAST_SENT", "player", "Boar", "c2", 990009)
    state.clear()
    state.slash("debug_tracker")
    equal(state.last(), "WTF: debug_tracker lastCast spell=990009 name=nil slot=nil")
end)
test("your target has the pinned row; other DoTed mobs are listed below it", function()
    local state = trackerFixture()
    dot(state, 6222, "Boar")
    equal(#shownRows(state), 0, "the target is not listed twice")
    dot(state, 6222, "Wolf")
    local rows = shownRows(state)
    equal(#rows, 1)
    equal(rows[1].name.text, "Wolf")
    equal(rows[1].container.unit, "nameplate4")
    equal(state.list.shown, true)
    equal(listOffset(state), -(ROW_STEP + TARGET_SPACING), "below the target row and its outline")
    equal(state.targetRow.name.text, "Boar")
end)
test("tabbing moves the pinned row; the old target joins the list", function()
    local state = trackerFixture()
    dot(state, 6222, "Boar")
    dot(state, 6222, "Wolf")
    state.units.target = state.units.nameplate4
    state.emit("PLAYER_TARGET_CHANGED")
    local rows = shownRows(state)
    equal(#rows, 1)
    equal(rows[1].name.text, "Boar")
    equal(state.targetRow.name.text, "Wolf")
    equal(state.targetRow.container.updates > 1, true, "the target row refreshes")
end)
test("a focus gets its pinned row and the list moves below both", function()
    local state = trackerFixture({units = {
        target = {name = "Boar", guid = "Creature-1"},
        nameplate3 = {name = "Boar", guid = "Creature-1"},
        nameplate4 = {name = "Wolf", guid = "Creature-2"},
        nameplate5 = {name = "Bear", guid = "Creature-3"},
    }})
    dot(state, 172, "Wolf")
    dot(state, 172, "Bear")
    equal(#shownRows(state), 2)
    state.units.focus = state.units.nameplate4
    state.emit("PLAYER_FOCUS_CHANGED")
    state.applyDrivers()
    local rows = shownRows(state)
    equal(#rows, 1)
    equal(rows[1].name.text, "Bear")
    equal(state.focusRow.name.text, "Wolf")
    equal(listOffset(state), -2 * (ROW_STEP + TARGET_SPACING))
    state.units.target = nil
    state.emit("PLAYER_TARGET_CHANGED")
    equal(listOffset(state), -2 * (ROW_STEP + TARGET_SPACING),
        "the secure focus row cannot move, so the list stays below it")
    state.units.focus = nil
    state.emit("PLAYER_FOCUS_CHANGED")
    equal(listOffset(state), 0, "with no pinned row the list moves to the top")
end)
test("list rows follow nameplates and fall back to target or focus", function()
    local state = trackerFixture()
    dot(state, 172, "Wolf")
    local row = shownRows(state)[1]
    equal(row.container.unit, "nameplate4")
    state.units.nameplate4 = nil
    state.units.nameplate7 = {name = "Wolf", guid = "Creature-2"}
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate7")
    equal(row.container.unit, "nameplate7")
end)
test("a mob out of sight for ten seconds leaves the list", function()
    local state = trackerFixture()
    dot(state, 172, "Wolf")
    state.units.nameplate4 = nil
    state.emit("NAME_PLATE_UNIT_REMOVED", "nameplate4")
    local row = shownRows(state)[1]
    equal(row.container.unit, "none")
    state.now = state.now + 5
    state.runTimers()
    equal(#shownRows(state), 1)
    state.now = state.now + 6
    state.runTimers()
    equal(#shownRows(state), 0)
    equal(state.list.shown, false)
end)
test("a dead mob leaves the list, and leaving combat clears it", function()
    local units = {target = {name = "Boar", guid = "Creature-1"}}
    for index = 4, 5 do units["nameplate" .. index] = {name = "Mob" .. index, guid = "Creature-" .. index} end
    local state = trackerFixture({units = units})
    dot(state, 172, "Mob4")
    dot(state, 172, "Mob5")
    state.units.nameplate4.dead = true
    state.emit("UNIT_HEALTH", "nameplate4")
    equal(#shownRows(state), 1)
    state.emit("PLAYER_REGEN_ENABLED")
    equal(#shownRows(state), 0)
    equal(listRows(state)[1].container.unit, "none")
end)
test("a ninth mob replaces the oldest list row", function()
    local units = {}
    for index = 1, 9 do
        units["nameplate" .. index] = {name = "Mob" .. index, guid = "Creature-" .. index}
    end
    local state = trackerFixture({units = units})
    for index = 1, 9 do
        state.now = state.now + 1
        dot(state, 172, "Mob" .. index)
    end
    local rows = shownRows(state)
    equal(#rows, 8)
    equal(rows[1].name.text, "Mob2")
    equal(rows[8].name.text, "Mob9")
end)
test("placeholders show sample rows for positioning, out of combat", function()
    local state = trackerFixture({units = {}})
    equal(state.targetRow.shown, false)
    state.settings.WTF_UNLOCKED:SetValue(true)
    equal(state.targetRow.shown, true)
    equal(state.focusRow.shown, true)
    equal(state.targetRow.name.text, "Target (sample)")
    equal(state.focusRow.name.text, "Focus (sample)")
    local rows = shownRows(state)
    equal(#rows, 2)
    equal(rows[1].name.text, "Another mob (sample)")
    equal(listOffset(state), -2 * (ROW_STEP + TARGET_SPACING))
    state.combat = true
    state.settings.WTF_UNLOCKED:SetValue(false)
    equal(state.targetRow.shown, true, "secure rows wait for combat to end")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(state.targetRow.shown, false)
    equal(state.drivers[state.targetRow], "[@target,harm,nodead] show; hide")
    equal(#shownRows(state), 0)
end)
test("the tracker drags by its rows unless locked, and /wtf reset moves it back", function()
    local state = trackerFixture()
    state.slash("unlock")
    state.targetRow.scripts.OnDragStart(state.targetRow)
    equal(state.anchor.moving, true)
    state.anchor:ClearAllPoints()
    state.anchor:SetPoint("CENTER", nil, "BOTTOMLEFT", 300, 600)
    state.targetRow.scripts.OnDragStop(state.targetRow)
    equal(state.wtf.db.tracker.position.x, 300)
    state.slash("lock")
    state.targetRow.scripts.OnDragStart(state.targetRow)
    equal(state.anchor.moving, false)
    state.slash("reset")
    equal(state.wtf.db.tracker.position, nil)
    equal(state.anchor.points[1][1], "CENTER")
    state.combat = true
    state.slash("reset")
    equal(state.last(), "WTF: WTF frames move back to their default places after combat.")
end)
test("the tracker module switch hides it", function()
    local state = trackerFixture()
    dot(state, 172, "Wolf")
    state.settings.WTF_TRACKER_ENABLED:SetValue(false)
    equal(state.anchor.shown, false)
    equal(state.list.shown, false)
end)
test("learning a rank in combat updates every row after combat", function()
    local state = trackerFixture()
    state.spellbook[#state.spellbook + 1] = {spellID = 990003, name = "Corruption"}
    state.spellbook[#state.spellbook + 1] = {spellID = 18265, name = "Siphon Life"}
    state.combat = true
    state.emit("SPELLS_CHANGED")
    equal(listRows(state)[1].container.slots[3].ids[990003], nil)
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    local row = currentRows(state)[1]
    equal(slotByKey(row.container, "corruption").ids[990003], true)
    equal(slotByKey(row.container, "siphon") ~= nil, true, "Siphon Life now has a slot")
    equal(slotByKey(pinnedRow(state, "focus").container, "corruption").ids[990003], true)
    equal(pinnedRow(state, "target").casts[5].attributes.macrotext1, "/cast [@target,harm,nodead] Siphon Life")
end)
test("without the aura container the tracker stays off and the rest runs", function()
    local state = fixture({noAuraContainer = true})
    equal(state.wtf.available, true)
    equal(state.env.WarlockToolsForeverTracker, nil)
    local found
    for _, message in ipairs(state.messages) do
        if message:find("The DoT tracker stays off: this client lacks CustomAuraContainerTemplate.", 1, true) then
            found = true
        end
    end
    equal(found, true)
end)

test("the Curse slot matches your Curse-type debuffs, not by ID and never your Bane", function()
    -- In client, a curse's debuff did not match the Classic or spellbook IDs.
    local state = trackerFixture({spellbook = {{spellID = 990001, name = "Bane of Agony"},
        {spellID = 702, name = "Curse of Weakness"}}})
    for _, row in ipairs({state.targetRow, listRows(state)[1]}) do
        local curse = row.container.slots[1]
        equal(curse.key, "curse")
        equal(curse.ids, nil, "no spell ID list")
        equal(curse.candidates.includeDispelTypes.Curse, true)
        equal(curse.candidates.excludeSpellIDs[990001], true, "the Bane stays in its own slot")
        equal(curse.candidates.excludeSpellIDs[980], true)
    end
    state.clear()
    state.slash("debug_tracker")
    contains(state.messages[2], "slot=curse recast=nil matches=Curse debuffs except bane")
    dot(state, 702, "Wolf")
    equal(#shownRows(state), 1, "casting a curse still adds the mob")
end)
test("spells you will learn later count as unknown everywhere", function()
    -- The spellbook lists spells learned later (FutureSpell); they must not show.
    local state = trackerFixture({db = {tracker = {plateDots = true}},
        units = {nameplate1 = {name = "Boar", guid = "Creature-1"}, target = {name = "Boar", guid = "Creature-1"}},
        spellbook = {{spellID = 6222, name = "Corruption"}, {spellID = 18265, name = "Siphon Life", itemType = 2}}})
    equal(state.wtf.TrackerKnowsSlot("siphon"), false)
    equal(slotByKey(state.targetRow.container, "siphon"), nil, "not in the compact view")
    local keys = {}
    for _, frame in ipairs(state.frames) do
        if frame.colored then
            for key in pairs(frame.colored) do keys[#keys + 1] = key end
        end
    end
    equal(table.concat(keys, ","), "corruption", "only a Corruption dot on the nameplate")
end)
test("Bars is the default theme", function()
    equal(fixture().wtf.db.tracker.theme, "bars")
end)
test("drains are not tracked: a Drain Life cast adds no row", function()
    local state = trackerFixture()
    dot(state, 689, "Wolf")
    equal(#shownRows(state), 0)
end)

-- Slot colors ----------------------------------------------------------------------

local function near3(actual, r, g, b, context)
    for index, expected in ipairs({r, g, b}) do
        if math.abs(actual[index] - expected) > 0.002 then
            error((context or "color") .. ": expected " .. r .. "," .. g .. "," .. b .. ", got "
                .. tostring(actual[1]) .. "," .. tostring(actual[2]) .. "," .. tostring(actual[3]), 2)
        end
    end
end

local function barColor(row, index)
    return row.container.slots[index].button.display.bar.barColor
end

test("each slot has a default color, used by the tracker's bars", function()
    local state = trackerFixture()
    local colors = state.wtf.db.tracker.colors
    equal(colors.corruption, "ffffffff")
    equal(colors.curse, "ff9e40d9")
    equal(colors.control, "ffffd91a")
    near3(barColor(state.targetRow, 3), 1, 1, 1, "Corruption white")
    near3(barColor(state.targetRow, 1), 0x9e / 255, 0x40 / 255, 0xd9 / 255, "Curse purple")
    near3(barColor(listRows(state)[1], 2), 0xe6 / 255, 0x26 / 255, 0x26 / 255, "Bane red")
end)
test("a new color applies at once to bars and nameplate dots", function()
    local state = trackerFixture({db = {tracker = {plateDots = true}},
        units = {nameplate1 = {name = "Boar", guid = "Creature-1"}}})
    state.settings.WTF_COLOR_CORRUPTION:SetValue("ff00ff00")
    equal(state.wtf.db.tracker.colors.corruption, "ff00ff00")
    near3(barColor(state.focusRow, 3), 0, 1, 0)
    near3(barColor(listRows(state)[8], 3), 0, 1, 0)
    local bubble
    for _, frame in ipairs(state.frames) do
        if frame.colored and frame.colored.corruption then bubble = frame end
    end
    near3(bubble.colored.corruption.color, 0, 1, 0, "the nameplate dot")
    state.settings.WTF_COLOR_CORRUPTION:SetValue("not a color")
    equal(state.wtf.db.tracker.colors.corruption, "ffffffff", "invalid values become the default")
end)
test("slots still on the old default colors move to the new ones, once", function()
    local old = trackerFixture({db = {tracker = {colors = {curse = "ff4d8cff", corruption = "ff9e40d9",
        immolate = "ff123456"}}}})
    equal(old.wtf.db.tracker.colors.curse, "ff9e40d9")
    equal(old.wtf.db.tracker.colors.corruption, "ffffffff")
    equal(old.wtf.db.tracker.colors.immolate, "ff123456", "a picked color stays")
    equal(old.wtf.db.tracker.colorsVersion, 2)
    local chosen = trackerFixture({db = {tracker = {colorsVersion = 2, colors = {curse = "ff4d8cff"}}}})
    equal(chosen.wtf.db.tracker.colors.curse, "ff4d8cff", "the old blue, picked after the change, stays")
end)
test("saved colors and nameplate choices are repaired on load", function()
    local state = trackerFixture({db = {tracker = {colors = {curse = "FF112233", bane = 7},
        onPlates = {control = true, curse = "yes"}}}})
    equal(state.wtf.db.tracker.colors.curse, "ff112233")
    equal(state.wtf.db.tracker.colors.bane, "ffe62626")
    equal(state.wtf.db.tracker.onPlates.control, true)
    equal(state.wtf.db.tracker.onPlates.curse, true, "not a boolean: the default")
    equal(state.wtf.db.tracker.onPlates.immolate, true)
end)
test("the DoT Colors page has a swatch and a nameplate switch per slot", function()
    local state = trackerFixture()
    local page = state.categories["DoT Colors"]
    equal(page.parent, state.categories["Warlock Tools Forever"])
    equal(#page.initializers, 12)
    equal(page.initializers[1].setting.variable, "WTF_COLOR_CURSE")
    equal(page.initializers[1].swatch, true)
    equal(page.initializers[5].setting.variable, "WTF_COLOR_CORRUPTION")
    equal(page.initializers[5].setting.default, "ffffffff")
    equal(page.initializers[6].setting.variable, "WTF_PLATE_CORRUPTION")
    equal(page.initializers[12].setting.variable, "WTF_PLATE_CONTROL")
    equal(page.initializers[12].setting.default, false, "crowd control is off on nameplates")
end)

-- Bar theme ----------------------------------------------------------------------

local function barsFixture(extra)
    local options = {db = {tracker = {theme = "bars"}}}
    for key, value in pairs(extra or {}) do options[key] = value end
    return trackerFixture(options)
end

test("the bar theme gives each mob a name line and a bar line per spell you know", function()
    local state = barsFixture()
    -- Known in the fixture: Corruption, Immolate, Fear, Curse of Agony (a Bane), Curse of Weakness.
    local row = listRows(state)[1]
    local keys = {}
    for index, slot in ipairs(row.container.slots) do keys[index] = slot.key end
    equal(table.concat(keys, ","), "curse,bane,corruption,immolate,control", "no Siphon Life line")
    local curse = row.container.slots[1].button
    equal(curse.points[1][1], "TOPLEFT")
    equal(curse.points[1][5], -18, "the first line under the name")
    equal(row.container.slots[2].button.points[1][5], -36)
    local display = curse.display
    equal(display.barOptions.direction, 1, "bars drain like the Cooldown Manager's")
    equal(row.height, 18 + 5 * 18 + 6)
    near3(display.bar.barColor, 0x9e / 255, 0x40 / 255, 0xd9 / 255, "Curse purple")
end)
test("pinned bar rows recast from each bar line", function()
    local state = barsFixture()
    local casts = state.targetRow.casts
    equal(casts[5], nil, "no Siphon Life line, so no button")
    equal(casts[3].attributes.macrotext1, "/cast [@target,harm,nodead] Corruption")
    equal(casts[3].points[1][1], "TOPLEFT")
    equal(casts[3].points[1][5], -(18 + 2 * 18), "over the Corruption line")
end)
test("pinned rows and the list are spaced by the taller bar blocks", function()
    local state = barsFixture()
    local step = 18 + 5 * 18 + 6 + 2
    equal(state.focusRow.points[1][5], -(step + TARGET_SPACING))
    dot(state, 172, "Wolf")
    equal(listOffset(state), -(step + TARGET_SPACING))
end)
test("switching the theme rebuilds the rows and keeps the tracked mobs", function()
    local state = trackerFixture()
    dot(state, 172, "Wolf")
    local before = listRows(state)
    state.settings.WTF_TRACKER_THEME:SetValue("bars")
    equal(state.wtf.db.tracker.theme, "bars")
    for _, row in ipairs(before) do equal(row.shown, false, "old rows hidden") end
    local rows = {}
    for _, row in ipairs(listRows(state)) do
        if row.shown then rows[#rows + 1] = row end
    end
    equal(#rows, 1)
    equal(rows[1].name.text, "Wolf")
    equal(rows[1].container.unit, "nameplate4")
    equal(#rows[1].container.slots, 5)
end)
test("a theme change in combat waits for combat to end", function()
    local state = trackerFixture()
    local before = state.targetRow
    state.combat = true
    state.settings.WTF_TRACKER_THEME:SetValue("bars")
    equal(state.wtf.db.tracker.theme, "bars")
    equal(before.shown, true, "secure rows untouched in combat")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(before.shown, false)
end)
test("learning a spell adds its bar line, after combat", function()
    local state = barsFixture()
    state.spellbook[#state.spellbook + 1] = {spellID = 18265, name = "Siphon Life"}
    state.emit("SPELLS_CHANGED")
    local row
    for _, frame in ipairs(listRows(state)) do row = frame end
    equal(#row.container.slots, 6)
end)

-- Nameplate DoT dots ---------------------------------------------------------------

local function dotsFixture(extra)
    local options = {units = {
        nameplate1 = {name = "Boar", guid = "Creature-1"},
        nameplate2 = {name = "Wolf", guid = "Creature-2"},
        nameplate3 = {name = "Guard", guid = "Creature-3", friend = true},
    }, spellbook = {{spellID = 6222, name = "Corruption"}, {spellID = 348, name = "Immolate"},
        {spellID = 980, name = "Curse of Agony"}, {spellID = 702, name = "Curse of Weakness"}},
        db = {tracker = {plateDots = true}}}
    for key, value in pairs(extra or {}) do options[key] = value end
    return fixture(options)
end

local function bubbleOn(state, unit)
    local plate = state.plates[unit]
    if not plate then return end
    for _, frame in ipairs(state.frames) do
        if frame.parent == plate and frame.backdropBorder then return frame end
    end
end

local function containerIn(bubble)
    for _, frame in ipairs(bubble.children) do
        if frame.kind == "AuraContainer" then return frame end
    end
end

test("nameplate dots are off by default", function()
    local state = dotsFixture({db = {}})
    equal(state.wtf.db.tracker.plateDots, false)
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate1")
    equal(bubbleOn(state, "nameplate1"), nil)
end)
test("each hostile plate gets a bubble with a dot per DoT you know", function()
    local state = dotsFixture()
    local bubble = bubbleOn(state, "nameplate1")
    local container = containerIn(bubble)
    local keys = {}
    for index, slot in ipairs(container.slots) do
        keys[index] = slot.key
        equal(slot.filter, "HARMFUL|PLAYER")
    end
    equal(table.concat(keys, ","), "curse,bane,corruption,immolate", "no Siphon Life: not known")
    equal(container.slots[3].ids[6222], true)
    equal(container.unit, "nameplate1")
    local point = bubble.points[#bubble.points]
    equal(point[1], "BOTTOM")
    equal(point[2], state.plates.nameplate1)
    equal(point[3], "TOP")
    equal(point[5], 50)
    equal(state.wtf.HasTrackableDots(), true)
end)
test("dots show only in combat, on live hostile mobs", function()
    local state = dotsFixture()
    local boar, guard = bubbleOn(state, "nameplate1"), bubbleOn(state, "nameplate3")
    equal(boar.shown, false, "out of combat")
    state.emit("PLAYER_REGEN_DISABLED")
    equal(boar.shown, true)
    equal(guard.shown, false, "friendly")
    state.units.nameplate1.dead = true
    state.emit("UNIT_HEALTH", "nameplate1")
    equal(boar.shown, false, "dead")
    state.emit("PLAYER_REGEN_ENABLED")
    equal(bubbleOn(state, "nameplate2").shown, false)
end)
test("a removed plate frees its bubble for the next plate", function()
    local state = dotsFixture()
    local bubble = bubbleOn(state, "nameplate2")
    state.emit("NAME_PLATE_UNIT_REMOVED", "nameplate2")
    equal(containerIn(bubble).unit, "none")
    equal(bubble.shown, false)
    equal(bubble.parent, state.env.UIParent)
    state.units.nameplate9 = {name = "Bear", guid = "Creature-9"}
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate9")
    equal(bubbleOn(state, "nameplate9"), bubble, "reused")
    equal(containerIn(bubble).unit, "nameplate9")
end)
test("forbidden plates get no bubble", function()
    local state = dotsFixture()
    state.units.nameplate8 = {name = "Rival", guid = "Player-8", forbidden = true}
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate8")
    equal(bubbleOn(state, "nameplate8"), nil)
end)
test("the dots switch and height setting apply at once", function()
    local state = dotsFixture({db = {}})
    state.settings.WTF_TRACKER_PLATE_DOTS:SetValue(true)
    local bubble = bubbleOn(state, "nameplate1")
    equal(bubble ~= nil, true)
    state.settings.WTF_TRACKER_PLATE_DOTS_OFFSET:SetValue(20)
    bubble = bubbleOn(state, "nameplate1")
    equal(bubble.points[#bubble.points][5], 20)
    state.settings.WTF_TRACKER_PLATE_DOTS:SetValue(false)
    equal(bubbleOn(state, "nameplate1"), nil)
    local page = state.categories["DoT Tracker"]
    equal(page.initializers[1].setting.variable, "WTF_TRACKER_THEME")
    equal(page.initializers[2].setting.variable, "WTF_TRACKER_PLATE_DOTS")
    equal(page.initializers[3].parentInitializer, page.initializers[2])
end)
test("the dot height slider has a gold mark at the default, hidden on reuse", function()
    local state = dotsFixture()
    local initializer = state.categories["DoT Tracker"].initializers[3]
    local frame = state.env.CreateFrame("Frame")
    local slider = state.env.CreateFrame("Slider")
    frame.SliderWithSteppers = {Slider = slider}
    function frame:Release() self.released = true end
    function slider:GetWidth() return 240 end
    function slider:GetThumbTexture() return {GetWidth = function() return 20 end} end
    initializer:InitFrame(frame)
    equal(frame.initializedWith, initializer, "Blizzard's setup still runs")
    local tick = slider.wtfDefaultTick
    equal(tick.shown, true)
    local point = tick.points[#tick.points]
    -- The thumb's center runs from 10 to 230; 50 of 0-120 is 5/12 of the way.
    equal(point[1], "CENTER")
    equal(point[3], "LEFT")
    equal(point[4], 10 + 5 / 12 * 220)
    frame:Release()
    equal(frame.released, true)
    equal(tick.shown, false, "hidden when the panel reuses the frame for another setting")
end)
test("without a known DoT the dots stay off and cannot be turned on", function()
    local state = dotsFixture({spellbook = {{spellID = 686, name = "Shadow Bolt"}}})
    equal(state.wtf.HasTrackableDots(), false)
    equal(bubbleOn(state, "nameplate1"), nil)
    equal(state.categories["DoT Tracker"].initializers[2].modifyPredicates[1](), false)
end)
test("nameplate dots follow the per-slot nameplate choices", function()
    local state = dotsFixture({db = {tracker = {plateDots = true, onPlates = {immolate = false}}},
        spellbook = {{spellID = 6222, name = "Corruption"}, {spellID = 348, name = "Immolate"},
            {spellID = 5782, name = "Fear"}}})
    local keys = {}
    for index, slot in ipairs(containerIn(bubbleOn(state, "nameplate1")).slots) do keys[index] = slot.key end
    equal(table.concat(keys, ","), "corruption", "no Immolate by choice, no Fear by default")
    local cursed = dotsFixture()
    local curseDot = containerIn(bubbleOn(cursed, "nameplate1")).slots[1]
    equal(curseDot.key, "curse")
    equal(curseDot.candidates.includeDispelTypes.Curse, true, "the dot uses the same Curse match")
    state.settings.WTF_PLATE_CONTROL:SetValue(true)
    keys = {}
    for index, slot in ipairs(containerIn(bubbleOn(state, "nameplate1")).slots) do keys[index] = slot.key end
    equal(table.concat(keys, ","), "corruption,control")
end)
test("learning a DoT rebuilds the bubbles", function()
    local state = dotsFixture()
    state.spellbook[#state.spellbook + 1] = {spellID = 18265, name = "Siphon Life"}
    state.emit("SPELLS_CHANGED")
    local container = containerIn(bubbleOn(state, "nameplate1"))
    equal(#container.slots, 5)
    equal(container.slots[5].key, "siphon")
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
    equal(main.initializers[4].setting.variable, "WTF_TRACKER_ENABLED")
    equal(state.categories["DoT Tracker"].parent, main)
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
