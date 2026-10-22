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
local SPELLS = {[1120] = "Drain Soul", [11675] = "Drain Soul", [8288] = "Drain Soul", [686] = "Shadow Bolt", [172] = "Corruption",
    [6222] = "Corruption", [980] = "Curse of Agony", [698] = "Ritual of Summoning",
    [20707] = "Soulstone Resurrection", [20762] = "Soulstone Resurrection",
    [693] = "Create Soulstone", [20752] = "Create Soulstone",
    [17877] = "Shadowburn", [18871] = "Shadowburn",
    [348] = "Immolate", [18265] = "Siphon Life", [5782] = "Fear", [702] = "Curse of Weakness",
    [6201] = "Create Healthstone", [6202] = "Create Healthstone", [5699] = "Create Healthstone",
    [6789] = "Death Coil", [5484] = "Howl of Terror", [6229] = "Shadow Ward", [18708] = "Fel Domination",
    [710] = "Banish", [1098] = "Enslave Demon", [6358] = "Seduction", [712] = "Summon Succubus",
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
    -- Health: the player's is readable; a mob's (state.units[unit].health and
    -- maxHealth) is secret in combat, as on Forever.
    local function mobHealth(unit, field, default)
        local data = state.units[unit]
        local value = data and data[field] or default
        if state.combat and unit ~= "player" then
            local hidden = secret()
            state.secrets[hidden] = true
            state.hiddenValues = state.hiddenValues or {}
            state.hiddenValues[hidden] = value
            return hidden
        end
        return value
    end
    env.UnitHealthMax = function(unit)
        if unit == "player" then return 1500 end
        return mobHealth(unit, "maxHealth", 1000)
    end
    env.UnitHealth = function(unit) return mobHealth(unit, "health", 1000) end
    if not options.noHealthPercent then
        env.CurveConstants = {ScaleTo100 = {}}
        env.UnitHealthPercent = function(unit, predicted, curve)
            equal(curve, env.CurveConstants.ScaleTo100, "scaled to 0-100")
            local data = state.units[unit] or {}
            return mobHealth(unit, "percent", math.floor(100 * (data.health or 1000) / (data.maxHealth or 1000)))
        end
    end
    -- As in client, string.format takes a secret and gives a secret back.
    env.string = setmetatable({format = function(pattern, ...)
        for index = 1, select("#", ...) do
            if state.secrets[select(index, ...)] then
                local text = secret()
                state.secrets[text] = true
                state.formatted = {pattern = pattern}
                return text
            end
        end
        return string.format(pattern, ...)
    end}, {__index = string})
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
    -- options.addOnVersions: other AddOns' TOC versions, as {DyresBuffReminders = "0.3.0-beta"}.
    env.C_AddOns = {GetAddOnMetadata = function(name, field)
        if name ~= "WarlockToolsForever" then
            equal(field, "Version", "only another AddOn's version is read")
            return (options.addOnVersions or {})[name]
        end
        return state.toc[field] or ""
    end}
    env.CreateSettingsListSectionHeaderInitializer = function(name, tooltip)
        return {heading = name, tooltip = tooltip}
    end
    env.CreateSettingsButtonInitializer = function(name, buttonText, buttonClick, tooltip, addSearchTags)
        return {name = name, buttonText = buttonText, buttonClick = buttonClick, tooltip = tooltip}
    end
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
        -- isPet asks your summoned demon's spellbook.
        env.C_SpellBook.IsSpellKnown = function(id, isPet)
            if isPet then return (state.petKnown or {})[id] == true end
            return state.known[id] == true
        end
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
    -- options.loadedAddOns: other AddOns already loaded, as {DyresBuffReminders = true}.
    state.loadedAddOns = options.loadedAddOns
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
    -- The pet spellbook: state.petSpellbook entries {spellID, name}.
    env.C_SpellBook.HasPetSpells = function() return #(state.petSpellbook or {}), "DEMON" end
    env.UnitCreatureFamily = function(unit) return state.petFamily end
    env.C_SpellBook.GetSpellBookItemInfo = function(index, bank)
        if bank == 1 then
            local petItem = (state.petSpellbook or {})[index]
            return petItem and {spellID = petItem.spellID, name = petItem.name, itemType = 1}
        end
        local item = state.spellbook[index]
        if item then
            return {spellID = item.spellID, name = item.name, itemType = item.itemType or 1}
        end
    end
    env.Enum = env.Enum or {}
    env.Enum.SpellBookSpellBank = {Player = 0, Pet = 1}
    env.Enum.SpellBookItemType = {None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4}
    env.Enum.StatusBarTimerDirection = {ElapsedTime = 0, RemainingTime = 1}
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
    -- As in client (MTF's guarded call, BugGrabber and the taint log), AddOn
    -- code may never call SetRaidTarget: it raises ADDON_ACTION_FORBIDDEN, also
    -- out of combat. Markers come from the game's /tm in a macro.
    env.SetRaidTarget = function()
        state.markCalls = (state.markCalls or 0) + 1
        state.emit("ADDON_ACTION_FORBIDDEN", "WarlockToolsForever", "SetRaidTarget()")
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
    -- As in client, item moves are refused in combat and under AddOn restrictions.
    env.ClickTradeButton = function(slot)
        if state.deletionRestricted() then
            state.restrictedCalls = (state.restrictedCalls or 0) + 1
            state.emit("ADDON_ACTION_BLOCKED", "WarlockToolsForever", "UNKNOWN()")
            return
        end
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
    -- Dyre's Sounds, faked with a few sounds of each kind (the library has its
    -- own suite): files, file IDs, sound kits, and Text to Speech. Every Play is
    -- recorded in state.soundsPlayed as {key, speech}. options.noSounds leaves
    -- it out, options.oldSounds offers only an older contract.
    state.soundsPlayed = {}
    if not options.noSounds then
        local FOLDER = "Interface\\AddOns\\DyresSounds\\Sounds\\"
        local catalog = {
            fadingslow = {label = "Dyre's Picks: Fading slow disappear", file = "FadingSlowDisappear.mp3"},
            blowswoosh = {label = "Dyre's Picks: Disappear blow swoosh", file = "DisappearBlowSwoosh.mp3"},
            cartoonvanish = {label = "Dyre's Picks: Cartoon vanish", file = "CartoonVanish.mp3"},
            magical = {label = "Dyre's Picks: Magical disappear", file = "MagicalDisappear.mp3"},
            slowswoosh = {label = "Dyre's Picks: Slow swoosh", file = "SlowSwoosh.wav"},
            talent = {label = "Interface: Talent ready", kit = 73281},
            impactspopclick = {label = "Impacts: Pop Click", kit = 316434},
            implaugh1 = {label = "Imp: Laugh 1", id = 639142},
            impspell = {label = "Imp: Spell chirp", id = 639156},
            voice = {label = "Text to Speech", voice = true},
        }
        local order = {"fadingslow", "blowswoosh", "cartoonvanish", "magical", "slowswoosh", "talent",
            "impactspopclick", "implaugh1", "impspell", "voice"}
        local aliases = {popclick = "impactspopclick", effectcartoonvanish = "cartoonvanish",
            effectmagical = "magical", pickmagical = "magical", pickslowswoosh = "slowswoosh"}
        local library = {}
        function library.RequireContract(minimum)
            if minimum <= (options.oldSounds and 0 or 1) then return library end
        end
        function library.Resolve(key)
            key = aliases[key] or key
            return catalog[key] and key or nil
        end
        function library.Label(key)
            local sound = catalog[library.Resolve(key) or ""]
            return sound and sound.label
        end
        function library.AuraSound(key)
            local sound = catalog[library.Resolve(key) or ""]
            if sound and sound.file then
                return {soundFileName = FOLDER .. sound.file}
            elseif sound and sound.id then
                return {soundFileID = sound.id}
            end
        end
        function library.List(filter)
            local list = {}
            for _, key in ipairs(order) do
                if filter ~= "aura" or library.AuraSound(key) then
                    list[#list + 1] = {key = key, label = catalog[key].label}
                end
            end
            return list
        end
        function library.Groups(filter)
            local groups, byName = {}, {}
            for _, sound in ipairs(library.List(filter)) do
                local name = sound.label:match("^(.-): ") or sound.label
                if not byName[name] then
                    byName[name] = {name = name, sounds = {}}
                    groups[#groups + 1] = byName[name]
                end
                byName[name].sounds[#byName[name].sounds + 1] = sound
            end
            return groups
        end
        -- As the library does: false when Text to Speech has no voice or text.
        function library.Play(key, speech)
            local sound = catalog[library.Resolve(key) or ""]
            if not sound or (sound.voice and (state.noVoice or type(speech) ~= "string")) then
                return false
            end
            state.soundsPlayed[#state.soundsPlayed + 1] = {key = library.Resolve(key), speech = speech}
            return true
        end
        function library.Choices(filter)
            return function()
                local list = {}
                for _, sound in ipairs(library.List(filter)) do
                    list[#list + 1] = {value = sound.key, label = sound.label}
                end
                return list
            end
        end
        function library.SetupMenu(initializer, filter) initializer.soundMenu = filter or "all" end
        env.DyresSounds = library
    end
    -- The last sound played through Dyre's Sounds.
    function state.lastSound() return state.soundsPlayed[#state.soundsPlayed] end
    -- Dyre's Toolkit, faked (it has its own suite): options.toolkit = true offers
    -- contract 1, "old" no contract WTF can use; options.toolkitMissing names a
    -- function it lacks; options.toolkitNoSettings has no settings home. It
    -- records what WTF registers and asks for.
    if options.toolkit then
        local toolkit = {locked = true, movables = {}, calls = {}, opened = {}}
        function toolkit.RequireContract(contract)
            if options.toolkit ~= "old" and contract == 1 then return toolkit end
        end
        function toolkit.RegisterAddOn(info) toolkit.info = info; return true end
        function toolkit.RegisterSettingsCategory(name)
            if options.toolkitNoSettings then return nil end
            toolkit.home = toolkit.home or env.Settings.RegisterVerticalLayoutCategory("Dyre's AddOns")
            return env.Settings.RegisterVerticalLayoutSubcategory(toolkit.home, name)
        end
        function toolkit.RegisterMovable(frame, save)
            toolkit.movables[#toolkit.movables + 1] = frame
            return true
        end
        function toolkit.BeginDrag(frame) toolkit.calls[#toolkit.calls + 1] = {"BeginDrag", frame} end
        function toolkit.EndDrag(frame) toolkit.calls[#toolkit.calls + 1] = {"EndDrag", frame} end
        function toolkit.ScaleKeepingCenter(frame, scale)
            toolkit.calls[#toolkit.calls + 1] = {"ScaleKeepingCenter", frame, scale}
            frame:SetScale(scale)
        end
        function toolkit.IsLocked() return toolkit.locked end
        function toolkit.SetLocked(locked)
            toolkit.locked = locked
            if toolkit.info and toolkit.info.setLocked then toolkit.info.setLocked(locked) end
            env.DEFAULT_CHAT_FRAME:AddMessage("Dyre: Frames " .. (locked and "locked." or "unlocked."))
        end
        function toolkit.Lock() toolkit.SetLocked(true) end
        function toolkit.Unlock() toolkit.SetLocked(false) end
        function toolkit.OpenSettings(category) toolkit.opened[#toolkit.opened + 1] = category; return true end
        if options.toolkitMissing then toolkit[options.toolkitMissing] = nil end
        env.DyresToolkit = toolkit
        state.toolkit = toolkit
    end
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
        -- state.pickupMisses: pickups that take nothing, as for an item still settling.
        PickupContainerItem = function(bag, slot)
            if state.deletionRestricted() then state.restrictedCalls = (state.restrictedCalls or 0) + 1 end
            local entry = item(bag, slot)
            if state.cursor or not entry then return end
            if (state.pickupMisses or 0) > 0 then
                state.pickupMisses = state.pickupMisses - 1
                return
            end
            state.bags[bag].items[slot] = nil
            state.cursor = {itemID = entry.itemID, count = entry.stackCount, bag = bag, slot = slot}
            state.emit("CURSOR_CHANGED")
        end,
        SplitContainerItem = function(bag, slot, amount)
            if state.deletionRestricted() then state.restrictedCalls = (state.restrictedCalls or 0) + 1 end
            local entry = item(bag, slot)
            equal(amount, 1, "splits exactly one")
            if state.cursor or not entry or entry.stackCount <= amount then return end
            entry.stackCount = entry.stackCount - amount
            state.cursor = {itemID = entry.itemID, count = amount, bag = bag, slot = slot}
            state.emit("CURSOR_CHANGED")
        end,
    }
    -- As in client (BugGrabber: ADDON_ACTION_BLOCKED from DeleteCursorItem in a
    -- dungeon, on a key press), the client refuses AddOn item deletion in combat,
    -- while the player affects combat, or under an AddOn restriction.
    function state.deletionRestricted()
        if state.combat or state.encounter or (state.units and state.units.player
            and state.units.player.affectingCombat) then
            return true
        end
        for kind = 0, 4 do
            if (state.restrictions or {})[kind] == 2 then return true end
        end
        return false
    end
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
        if state.deletionRestricted() then state.restrictedCalls = (state.restrictedCalls or 0) + 1 end
        if state.deleteBlocked or not state.hardware or state.deletionRestricted() then
            state.emit("ADDON_ACTION_BLOCKED", "WarlockToolsForever", "UNKNOWN()")
            return
        end
        if not state.cursor then return end
        state.deleted = (state.deleted or 0) + state.cursor.count
        state.cursor = nil
        state.emit("CURSOR_CHANGED")
        -- The client reports the bags after a deletion; options.noBagUpdateOnDelete
        -- leaves that out, as a slow report would.
        if not options.noBagUpdateOnDelete then state.emit("BAG_UPDATE_DELAYED") end
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
    -- A unit with secretPlateGUID has a secret GUID on its nameplate token only,
    -- as the client may give in combat; its target or focus GUID stays readable.
    env.UnitGUID = function(unit)
        local data = state.units[unit]
        if data and data.secretPlateGUID and unit:match("^nameplate") then
            local hidden = secret()
            state.secrets[hidden] = true
            return hidden
        end
        return data and data.guid
    end
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
    env.UnitAffectingCombat = function(unit)
        if unit == "player" and state.affectingSecret then
            local value = secret()
            state.secrets[value] = true
            return value
        end
        return unit == "player" and (state.combat or state.units.player.affectingCombat == true)
    end
    if not options.noRestrictionAPI then
        env.Enum = env.Enum or {}
        env.Enum.AddOnRestrictionType = {Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5}
        env.Enum.UnitAuraSoundTrigger = {Added = 0, ApplicationsIncreased = 1, Removed = 2}
        env.C_RestrictedActions = {GetAddOnRestrictionState = function(kind)
            return (state.restrictions or {})[kind] or 0
        end}
        env.C_CombatLog = {IsCombatLogRestricted = function() return state.combatLogRestricted == true end}
        env.C_RestrictedActions.IsAddOnRestrictionActive = function(kind)
            return (kind == 1 and state.encounter == true) or (state.restrictions or {})[kind] == 2
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
            object.shownPredicates = {}
            function object:AddShownPredicate(predicate)
                self.shownPredicates[#self.shownPredicates + 1] = predicate
            end
            category.initializers[#category.initializers + 1] = object
            return object
        end
        env.MinimalSliderWithSteppersMixin = {Label = {Right = "right"}}
        env.Settings = {
            VarType = {Boolean = "boolean", Number = "number", String = "string"},
            RegisterVerticalLayoutCategory = function(name) return newCategory(name) end,
            -- Returns the page and its layout, as the client does; a heading the
            -- layout gets is kept on the page.
            RegisterVerticalLayoutSubcategory = function(parent, name)
                local page = newCategory(name, parent)
                page.headings = {}
                local layout = {}
                function layout:AddInitializer(heading)
                    heading.position = #page.initializers
                    page.headings[#page.headings + 1] = heading
                end
                return page, layout
            end,
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
                function object:SetLabelFormatter(label, formatter)
                    self.label, self.formatter = label, formatter
                end
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
    env.IsControlKeyDown = function() return state.ctrl == true end
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
        function object:SetMinMaxValues(minValue, maxValue) self.minValue, self.maxValue = minValue, maxValue end
        function object:SetValue(value) self.value = value end
        function object:GetStatusBarTexture()
            self.fill = self.fill or widget("Texture", nil, self)
            return self.fill
        end
        function object:SetClipsChildren(value) self.clips = value end
        function object:SetColorTexture(...) self.color = {...} end
        function object:SetWidth(width) self.width = width end
        -- As in client, secure frames refuse mouse changes in combat.
        function object:EnableMouse(value)
            if state.combat and self.protected then error("EnableMouse in combat") end
            self.mouseDisabled = value == false
        end
        function object:SetHeight(height) self.height = height end
        function object:SetSize(width, height) self.width, self.height = width, height end
        -- As in client, secure frames refuse layout changes in combat.
        function object:SetScale(value)
            if state.combat and self.protected then error("SetScale in combat") end
            self.scale = value
        end
        function object:GetScale() return self.scale or 1 end
        function object:GetNumPoints() return #self.points end
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
        function object:SetAlpha(value) self.alpha = value end
        function object:SetIgnoreParentAlpha(value) self.ignoreParentAlpha = value == true end
        function object:IsShown() return self.shown end
        function object:IsVisible()
            if not self.shown then return false end
            local parent = self.parent
            if type(parent) == "table" and type(parent.IsVisible) == "function" then return parent:IsVisible() end
            return true
        end
        function object:IsProtected() return self.protected == true end
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
        function object:SetEnabled(value) self.enabled = value == true end
        function object:GetChecked() return self.checked end
        function object:CreateTexture() return widget("Texture", nil, self) end
        function object:SetDesaturated(value) self.desaturated = value == true end
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
            function button:SetSpellName(region) self.display.spellName = region end
            function button:SetMouseClickEnabled(value) self.clicks = value end
            slotOptions.initializeFrame(button)
            -- As in client (13x: "Attempt to access forbidden object from code
            -- tainted by an AddOn"), what WTF hands the engine is the engine's
            -- once the initializer returns: every call on it from WTF raises.
            for _, handed in pairs({button.display.bar, button.display.text, button.display.spellName}) do
                handed.forbidden = true
                for _, method in ipairs({"SetStatusBarColor", "SetAlpha", "SetIgnoreParentAlpha", "SetValue",
                    "SetMinMaxValues", "SetText", "SetPoint", "SetSize", "ClearAllPoints", "Show", "Hide"}) do
                    handed[method] = function()
                        error("calling '" .. method .. "' on bad self (Attempt to access forbidden object from "
                            .. "code tainted by an AddOn)")
                    end
                end
            end
            self.slots[#self.slots + 1] = {key = key, filter = filter, button = button,
                ids = slotOptions.candidateFilters.includeSpellIDs, candidates = slotOptions.candidateFilters}
            return button
        end
        -- As in client (ErrorUtil: "aura slot 'siphon' was not found with this
        -- key."), a key the container has no slot for is an error.
        function object:SetAuraSlotCandidateFilters(key, filters)
            for _, slot in ipairs(self.slots or {}) do
                if slot.key == key then
                    slot.ids, slot.candidates = filters.includeSpellIDs, filters
                    return
                end
            end
            error("aura slot '" .. tostring(key) .. "' was not found with this key.")
        end
        function object:SetUnit(unit) self.unit = unit end
        function object:UpdateAllAuras() self.updates = (self.updates or 0) + 1 end
        -- Font strings start at a 10-point font, as the small game fonts are.
        function object:CreateFontString()
            local text = widget("FontString", nil, self)
            text.font, text.fontSize = "Fonts\\FRIZQT__.TTF", 10
            function text:GetFont() return self.font, self.fontSize, self.fontFlags end
            function text:SetFont(font, size, flags) self.font, self.fontSize, self.fontFlags = font, size, flags end
            function text:SetWordWrap(value) self.wordWrap = value end
            function text:SetMaxLines(value) self.maxLines = value end
            return text
        end
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
            -- Secure buttons run PreClick and PostClick for the press and the release.
            for _, down in ipairs({true, false}) do
                if button.scripts.PreClick then button.scripts.PreClick(button, mouseButton, down) end
                if button.scripts.PostClick then button.scripts.PostClick(button, mouseButton, down) end
            end
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
    equal(state.last(), "WTF: debug_delete works out of combat and outside AddOn restrictions only.")
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
test("a locked shard is never picked up: another shard goes, or the deletion waits", function()
    local state = fixture()
    state.fill(6)
    state.channel()
    state.put(1, 1, 1, {isLocked = true})
    state.emit("BAG_UPDATE_DELAYED")
    state.press()
    equal(state.count(), 6, "an unlocked shard goes instead")
    equal(state.bags[1].items[1].itemID, SHARD, "the locked one stays")
    local alone = fixture()
    alone.channel()
    alone.put(0, 1, 7, {isLocked = true})
    alone.emit("BAG_UPDATE_DELAYED")
    alone.press()
    equal(alone.count(), 7, "every shard is locked: wait")
    alone.bags[0].items[1].isLocked = false
    alone.press()
    equal(alone.count(), 6)
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
test("shards created in combat wait for the first key press after combat", function()
    local state = fixture()
    state.fill(6)
    state.combat = true
    state.channel()
    state.gain(1, 1)
    equal(state.count(), 7, "nothing is picked up or deleted in combat")
    equal(state.restrictedCalls, nil)
    state.combat = false
    state.press()
    equal(state.count(), 6)
end)
test("no shard is picked up or deleted while the client restricts AddOns", function()
    -- In client DeleteCursorItem raised ADDON_ACTION_BLOCKED in a dungeon, on a
    -- key press (BugGrabber, 6x).
    local cases = {
        {"in combat", function(state) state.combat = true end},
        {"affecting combat", function(state) state.units.player.affectingCombat = true end},
        {"a secret combat state", function(state) state.affectingSecret = true end},
        {"an encounter", function(state) state.encounter = true end},
        {"the Combat restriction", function(state) state.restrictions = {[0] = 2} end},
        {"the ChallengeMode restriction", function(state) state.restrictions = {[2] = 2} end},
        {"the PvPMatch restriction", function(state) state.restrictions = {[3] = 2} end},
        {"the Map restriction", function(state) state.restrictions = {[4] = 2} end},
    }
    for _, case in ipairs(cases) do
        local state = fixture()
        state.fill(6)
        state.channel()
        case[2](state)
        state.clear()
        state.gain(1, 1)
        state.click()
        equal(state.count(), 7, case[1] .. ": the shard waits")
        equal(state.restrictedCalls, nil, case[1] .. ": no pickup or delete")
        equal(state.cursor, nil, case[1])
        equal(#state.messages, 0, case[1] .. ": nothing to say")
        state.combat, state.encounter, state.restrictions, state.affectingSecret = false, nil, nil, nil
        state.units.player.affectingCombat = nil
        state.press()
        equal(state.count(), 6, case[1] .. ": deleted on the first key press after")
        equal(state.wtf.db.shards.enabled, true)
    end
end)
test("if the client refuses in combat, shards wait for input after combat", function()
    local state = fixture()
    state.fill(6)
    state.combat = true
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
    equal(state.count(), 7, "one on the first key press after combat")
    state.press()
    equal(state.count(), 6, "the other on the next")
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
-- John's bags in client: a full 14-slot soul bag in the reagent slot (bag 5),
-- so new shards land in an ordinary bag (bag 3).
local function fullSoulBag()
    local bags = {
        [0] = {size = 16, family = 0, items = {}},
        [1] = {size = 8, family = 0, items = {}},
        [2] = {size = 8, family = 0, items = {}},
        [3] = {size = 8, family = 0, items = {}},
        [4] = {size = 8, family = 0, items = {}},
        [5] = {size = 14, family = 4, items = {}},
    }
    local state = fixture({bags = bags, reagentBag = true})
    for slot = 1, 14 do state.put(5, slot) end
    state.emit("BAG_UPDATE_DELAYED")
    equal(state.wtf.GetShardLimit(), 14)
    return state
end

test("with a full soul bag, shards created in another bag are deleted there", function()
    local state = fullSoulBag()
    state.combat = true
    state.channel(8288)
    state.clear()
    state.arrive(3, 1)
    state.arrive(3, 2)
    equal(state.count(), 16)
    state.combat = false
    state.stopChannel(8288)
    state.press()
    state.press()
    equal(state.count(), 14, "both, from bag 3, one per key press")
    equal(state.bags[3].items[1], nil)
    equal(state.bags[3].items[2], nil)
    equal(#state.bags[5].items, 14, "the soul bag is untouched")
end)
-- John's second test: one Drain Soul kill created two shards at once above a
-- full soul bag, and only one was deleted.
local function twoShardKill(arrive)
    local state = fullSoulBag()
    state.combat = true
    state.channel(8288)
    state.clear()
    arrive(state)
    state.stopChannel(8288)
    state.combat = false
    for _ = 1, 3 do state.press() end
    equal(state.count(), 14, "both new shards are deleted")
    equal(state.deleted, 2)
    equal(#state.bags[5].items, 14, "the soul bag is untouched")
    return state
end
test("two shards created in one bag update, in two slots, are both deleted", function()
    twoShardKill(function(state)
        state.put(3, 1)
        state.put(3, 2)
        state.emit("BAG_UPDATE_DELAYED")
    end)
end)
test("two shards created in one bag update, in one stack, are both deleted", function()
    twoShardKill(function(state)
        state.put(3, 1, 2)
        state.emit("BAG_UPDATE_DELAYED")
    end)
end)
test("two shards created in two bag updates close together are both deleted", function()
    twoShardKill(function(state)
        state.arrive(3, 1)
        state.arrive(3, 2)
    end)
end)
test("a second shard that lands after the first is deleted is deleted too", function()
    twoShardKill(function(state)
        state.combat = false
        state.gain(3, 1)
        equal(state.count(), 14)
        state.arrive(3, 1)
    end)
end)
test("a second shard reported with the first one's deletion is deleted too", function()
    twoShardKill(function(state)
        state.arrive(3, 1)
        state.press()
        state.arrive(3, 2)
    end)
end)
-- The keep count ------------------------------------------------------------------

local function fullSoulBagWith(options)
    local bags = {
        [0] = {size = 16, family = 0, items = {}},
        [1] = {size = 8, family = 0, items = {}},
        [2] = {size = 8, family = 0, items = {}},
        [3] = {size = 8, family = 0, items = {}},
        [4] = {size = 8, family = 0, items = {}},
        [5] = {size = 14, family = 4, items = {}},
    }
    options.bags, options.reagentBag = bags, true
    local state = fixture(options)
    for slot = 1, 14 do state.put(5, slot) end
    state.emit("BAG_UPDATE_DELAYED")
    return state
end

test("a created shard the bag reports hid is still deleted on a later key press", function()
    -- The client may report a deletion and a new shard in one bag update, so the
    -- count does not rise: the keep count still says the new shard is extra.
    local state = fullSoulBagWith({noBagUpdateOnDelete = true})
    state.channel(8288)
    state.gain(3, 1)
    equal(state.count(), 14, "the first goes")
    state.put(3, 2)
    state.emit("BAG_UPDATE_DELAYED")
    state.stopChannel(8288)
    state.now = state.now + 60
    state.press()
    equal(state.count(), 14, "the second goes on a key press a minute later")
end)
test("after a deletion the next waits until the bags show it, so none goes below the limit", function()
    local state = fullSoulBagWith({noBagUpdateOnDelete = true})
    state.channel(8288)
    state.put(3, 1)
    state.put(3, 2)
    state.emit("BAG_UPDATE_DELAYED")
    state.press()
    equal(state.count(), 15)
    state.press()
    equal(state.count(), 15, "waits for the bags to show the first deletion")
    state.emit("BAG_UPDATE_DELAYED")
    state.press()
    equal(state.count(), 14)
    state.press()
    state.now = state.now + 10
    state.press()
    equal(state.count(), 14, "never below the limit")
end)
test("a deletion the bags never show waits at most two seconds before the next", function()
    local state = fullSoulBagWith({noBagUpdateOnDelete = true})
    state.channel(8288)
    state.put(3, 1)
    state.put(3, 2)
    state.emit("BAG_UPDATE_DELAYED")
    state.press()
    state.now = state.now + 1
    state.press()
    equal(state.count(), 15)
    state.now = state.now + 1.5
    state.press()
    equal(state.count(), 14)
end)
test("shards from the bank above the limit are kept, and only new ones go", function()
    local state = fullSoulBagWith({})
    state.arrive(3, 1)
    state.arrive(3, 2)
    state.press()
    equal(state.count(), 16, "moved in by hand: kept")
    state.channel(8288)
    state.gain(3, 3)
    state.stopChannel(8288)
    state.press()
    equal(state.count(), 16, "only the created one went")
    state.slash("debug_shards")
    contains(table.concat(state.messages, "|"), "count=16 limit=14 keep=16")
end)
test("using shards lowers the keep count, so new ones above the limit go", function()
    local state = fullSoulBagWith({})
    state.arrive(3, 1)
    state.arrive(3, 2)
    for slot = 1, 3 do state.bags[5].items[slot] = nil end
    state.emit("BAG_UPDATE_DELAYED")
    equal(state.count(), 13)
    state.channel(8288)
    state.put(3, 3)
    state.put(3, 4)
    state.emit("BAG_UPDATE_DELAYED")
    state.stopChannel(8288)
    for _ = 1, 3 do state.press() end
    equal(state.count(), 14, "one of the two is within the limit")
end)
test("lowering the limit deletes no shard", function()
    local state = fullSoulBagWith({})
    state.settings.WTF_SHARDS_AUTO_LIMIT:SetValue(false)
    state.settings.WTF_SHARDS_LIMIT:SetValue(6)
    state.press()
    equal(state.count(), 14)
    state.channel(8288)
    state.gain(3, 1)
    equal(state.count(), 14, "a new shard still goes")
end)
test("shards created while deletion is off stay when it is turned on", function()
    local state = fullSoulBagWith({db = {shards = {enabled = false}}})
    state.channel(8288)
    state.gain(3, 1)
    state.stopChannel(8288)
    state.settings.WTF_SHARDS_ENABLED:SetValue(true)
    state.press()
    equal(state.count(), 15)
end)
test("debug_shards shows each deletion with the count and keep count before it", function()
    local state = fullSoulBagWith({})
    state.channel(8288)
    state.gain(3, 1)
    state.clear()
    state.slash("debug_shards")
    local text = table.concat(state.messages, "|")
    contains(text, "lastAttempt=deleted 0.0s ago count=15 keep=14")
    contains(text, "debug_shards deleted 0.0s ago bag=3 slot=1 count=15 keep=14 limit=14")
    contains(text, "gain 0.0s ago +1 count=15 keep=14 created=true")
end)
test("a pickup that takes nothing waits for the next input instead of stopping deletion", function()
    -- John's test: two shards created above a full soul bag, none deleted,
    -- and debug_shards said blocked=true combatBlocked=false.
    local state = fullSoulBag()
    state.channel(8288)
    state.clear()
    state.pickupMisses = 1
    state.gain(3, 1)
    equal(state.count(), 15, "the shard was still settling")
    equal(#state.messages, 0, "nothing to say")
    state.press()
    equal(state.count(), 14, "deleted on the next key press")
    state.gain(3, 2)
    equal(state.count(), 14, "and deletion still runs")
    state.clear()
    state.slash("debug_shards")
    contains(table.concat(state.messages, "|"), "blocked=false")
    contains(table.concat(state.messages, "|"), "stopped=nil lastAttempt=deleted")
end)
test("a slot whose pickup keeps taking nothing is given up, and the shard stays", function()
    local state = fullSoulBag()
    state.channel(8288)
    state.clear()
    state.pickupMisses = 3
    state.gain(3, 1)
    state.press()
    state.press()
    equal(state.count(), 15, "three tries took nothing")
    equal(state.cursor, nil)
    equal(#state.messages, 0)
    state.press()
    equal(state.count(), 14, "then another shard goes")
    equal(state.bags[3].items[1].itemID, SHARD, "the stuck slot is left alone")
    state.gain(3, 2)
    equal(state.count(), 14, "a new shard is still deleted")
end)
test("a shard moved to another slot is no new shard, even while Drain Soul channels", function()
    local state = fullSoulBag()
    state.arrive(3, 1)
    equal(state.count(), 15, "a shard from outside a creation window stays")
    state.channel(8288)
    state.clear()
    state.bags[5].items[1] = nil
    state.put(3, 4)
    state.emit("BAG_UPDATE_DELAYED")
    state.press()
    equal(state.count(), 15, "a move deletes nothing")
    equal(state.deleted, nil)
    state.slash("debug_shards")
    equal(table.concat(state.messages, "|"):find("+1 count=15 created=true", 1, true), nil, "and logs no gain")
end)
test("a refusal under the combat restriction just after combat waits, as one in combat", function()
    local state = fullSoulBag()
    state.restrictions = {[0] = 2}
    state.channel(8288)
    state.clear()
    state.gain(3, 1)
    equal(state.count(), 15)
    equal(state.cursor, nil, "the shard is back")
    equal(#state.messages, 0, "no stop, no message")
    state.press()
    equal(state.count(), 15, "no retry while restricted")
    state.restrictions = nil
    state.press()
    equal(state.count(), 14, "deleted once the restriction ends")
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
    contains(state.messages[10], "count=3 limit=12 keep=3 source=soul bag")
    contains(state.messages[11], "debug_shards stopped=nil lastAttempt=none")
    contains(state.messages[12], "gain 0.0s ago +1 count=3 keep=3 created=true combat=false last=UNIT_SPELLCAST_CHANNEL_START 11675 1.0s before")
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
    contains(state.messages[2], "states Combat=active Encounter=inactive ChallengeMode=inactive PvPMatch=inactive Map=inactive Chat=inactive")
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
        "/use [btn:2] Create Healthstone(Rank 3)",
        "/stopmacro [btn:2]",
        "/use item:9421", "/use item:5510", "/use item:5509", "/use item:5511", "/use item:5512"}, "\n"))
    equal(macroBody(state, "! Soulstone"), table.concat({
        "#showtooltip item:16892",
        "/use [btn:2] Create Soulstone",
        "/stopmacro [btn:2]",
        "/use [@target,help,nodead][@player] item:16892"}, "\n"))
    equal(state.macros[1].icon, 134400, "the question mark, so #showtooltip shows the stone")
end)
test("the macros follow your bags and downranking, out of combat only", function()
    local state = stonesFixture()
    state.carried[5509] = 1
    state.emit("BAG_UPDATE_DELAYED")
    contains(macroBody(state, "! Healthstone"), "/use [btn:2] Create Healthstone(Rank 1)")
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
    state.emit("PLAYER_TARGET_CHANGED")
    local first, second = controlRow(state, 1), controlRow(state, 2)
    equal(first.shown, true)
    equal(first.name.text, "Boar")
    equal(first.container.unit, "nameplate3", "its nameplate once you target another mob")
    equal(second.name.text, "Imp")
    equal(second.container.unit, "target", "your target first")
    state.units.focus = state.units.nameplate4
    state.emit("PLAYER_FOCUS_CHANGED")
    equal(second.container.unit, "focus", "your focus before anything, as it never drops")
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
test("WTF never calls SetRaidTarget: markers come only from the game's /tm in a macro", function()
    -- In client the call raised ADDON_ACTION_FORBIDDEN for AddOn code, also out
    -- of combat (MTF's same guarded call).
    local state = controlFixture()
    state.units.target = state.units.nameplate4
    castAt(state, BANISH, "nameplate4")
    castAt(state, FEAR, "nameplate3")
    state.combat = true
    castAt(state, BANISH, "nameplate4")
    state.combat = false
    state.units.target = nil
    state.units.mouseover = {name = "Felguard", guid = "Creature-8"}
    state.emit("UNIT_SPELLCAST_SENT", "player", "Felguard", "cast-mo", BANISH)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-mo", BANISH)
    equal(state.markCalls, nil, "never called")
    equal(controlRow(state, 1).name.text, "Imp", "the rows still track")
    contains(state.env.WarlockToolsForeverControlClick1.attributes.macrotext1, "/tm [@target,harm,nodead,exists] !5",
        "the row click marks with /tm")
    equal(state.settings.WTF_CONTROL_MARKER_FEAR, nil, "no marker setting for Fear")
    state.clear()
    state.slash("debug_control")
    equal(table.concat(state.messages, "|"):find("marked=", 1, true), nil, "no marked= in debug_control")
    local old = fixture({db = {control = {markers = {banish = 3}}}})
    equal(old.wtf.db.control.markers.banish, 5, "the old diamond default becomes the moon")
    local chosen = fixture({db = {control = {markers = {banish = 8}, markersVersion = 2}}})
    equal(chosen.wtf.db.control.markers.banish, 8, "a marker you chose stays")
end)
test("a Banish cast on the mob under the mouse is tracked", function()
    local state = controlFixture()
    state.units.target = nil
    state.units.mouseover = {name = "Felguard", guid = "Creature-8"}
    state.emit("UNIT_SPELLCAST_SENT", "player", "Felguard", "cast-mo", BANISH)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-mo", BANISH)
    equal(controlRow(state, 1).name.text, "Felguard", "tracked")
    equal(controlRow(state, 1).container.unit, "none", "rows never bind to mouseover")
end)
test("the group message names the marker only after a Banish row click", function()
    local state = controlFixture({group = "party", known = {[FEAR] = true, [BANISH] = true, [ENSLAVE] = true}})
    castAt(state, BANISH, "nameplate4")
    equal(state.sent[1].message, "Banishing >> Imp << to the Twisting Nether. Hands off until it comes back"
        .. " - via Warlock Tools Forever (WTF)", "a plain cast: WTF cannot know it was marked")
    state.now = state.now + 10
    state.clickButton("WarlockToolsForeverControlClick1", "LeftButton")
    castAt(state, BANISH, "nameplate4")
    equal(state.sent[2].message, "Banishing >> Imp << {moon} to the Twisting Nether. Hands off until it comes back"
        .. " - via Warlock Tools Forever (WTF)", "the click's /tm marked it")
    state.now = state.now + 10
    castAt(state, BANISH, "nameplate4")
    equal(state.sent[3].message:find("{moon}", 1, true), nil, "a later plain cast names none again")
end)
test("control spells tell the group as the cast starts, with the marker in chat", function()
    local state = controlFixture({group = "party", known = {[FEAR] = true, [BANISH] = true, [ENSLAVE] = true}})
    castAt(state, BANISH, "nameplate4")
    equal(state.sent[1].chatType, "PARTY")
    equal(state.sent[1].message, "Banishing >> Imp << to the Twisting Nether. Hands off until it comes back"
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
-- Each cast marks its mob first with the game's /tm, which works in combat.
local RECAST_BANISH_IMP = "/tm [@focus,harm,nodead,exists] !5\n/use [@focus,exists,harm,nodead] Banish"
    .. "\n/stopmacro [@focus,exists]\n/cleartarget\n/targetexact Imp\n/tm [@target,harm,nodead,exists] !5"
    .. "\n/use [@target,harm,nodead] Banish\n/targetlasttarget"

test("clicking a Banish row recasts on your focus, or with none on the mob by name", function()
    local state = controlFixture()
    castAt(state, BANISH, "nameplate4")
    local click = state.env.WarlockToolsForeverControlClick1
    equal(click.protected, true, "a secure button")
    equal(click.shown, true)
    equal(click.attributes.macrotext1, RECAST_BANISH_IMP)
    state.combat = true
    -- Started in combat: the click waits for combat to end.
    state.units.nameplate5 = {name = "Voidwalker", guid = "Creature-3"}
    castAt(state, BANISH, "nameplate5")
    equal(controlRow(state, 2).name.text, "Voidwalker", "the bar shows in combat")
    equal(state.env.WarlockToolsForeverControlClick2.attributes.macrotext1, nil)
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    contains(state.env.WarlockToolsForeverControlClick2.attributes.macrotext1, "/targetexact Voidwalker")
    equal(state.env.WarlockToolsForeverControlClick3.shown, false, "no click area without a mob")
end)
-- A shown click slot under a hidden row is an invisible area that takes
-- clicks (MTF had one). Every slot that can be clicked has its row on screen.
local function noHiddenClickArea(state, label)
    for index = 1, 5 do
        local holder = state.env["WarlockToolsForeverControlClick" .. index]
        if holder:IsVisible() then
            equal(controlRow(state, index).shown, true, label .. ": slot " .. index .. " has its row on screen")
        end
    end
end
test("a Banish mob that dies in combat leaves its click slot visible, dimmed, until combat ends", function()
    local state = controlFixture()
    castAt(state, BANISH, "nameplate4")
    local row = controlRow(state, 1)
    noHiddenClickArea(state, "out of combat")
    state.combat = true
    state.units.nameplate4.dead = true
    state.emit("UNIT_HEALTH", "nameplate4")
    equal(state.env.WarlockToolsForeverControlClick1.shown, true, "a secure slot cannot hide in combat")
    equal(row.shown, true, "so its row stays on screen")
    equal(row.alpha, 0.45, "dimmed")
    equal(row.name.text, "Imp")
    noHiddenClickArea(state, "in combat")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(state.env.WarlockToolsForeverControlClick1.shown, false)
    equal(row.shown, false, "both go after combat")
    equal(row.alpha, 1)
end)
test("Fear rows show the timer but have no click, so no click Fears the wrong mob", function()
    local state = controlFixture()
    castAt(state, FEAR, "nameplate3")
    equal(controlRow(state, 1).name.text, "Boar")
    local click = state.env.WarlockToolsForeverControlClick1
    equal(click.shown, false)
    equal(click.attributes.macrotext1, nil)
end)
test("a Banish row whose click is set keeps its slot until combat ends", function()
    local state = controlFixture()
    castAt(state, BANISH, "nameplate4")
    local click1 = state.env.WarlockToolsForeverControlClick1
    contains(click1.attributes.macrotext1, "/targetexact Imp")
    state.combat = true
    state.units.nameplate4.dead = true
    state.emit("UNIT_HEALTH", "nameplate4")
    equal(controlRow(state, 1).shown, true, "the Imp is gone, but its click slot shows: the row stays, dimmed")
    equal(controlRow(state, 1).alpha, 0.45)
    castAt(state, FEAR, "nameplate3")
    equal(controlRow(state, 1).name.text, "Imp", "its row is not reused while its click still names the Imp")
    equal(controlRow(state, 2).name.text, "Boar")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(click1.attributes.macrotext1, nil, "cleared after combat")
    equal(click1.shown, false)
    state.units.nameplate5 = {name = "Wolf", guid = "Creature-3"}
    castAt(state, FEAR, "nameplate5")
    equal(controlRow(state, 1).name.text, "Wolf", "then free again")
end)
test("a Banish that fails out of combat gives back its row and click", function()
    local state = controlFixture()
    state.units.target = state.units.nameplate4
    state.emit("UNIT_SPELLCAST_SENT", "player", "Imp", "cast-a", BANISH)
    local click1 = state.env.WarlockToolsForeverControlClick1
    equal(click1.shown, true, "set as the cast starts")
    state.emit("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-a", BANISH)
    equal(click1.shown, false)
    equal(click1.attributes.macrotext1, nil)
    for index = 1, 5 do
        state.units["nameplate" .. (10 + index)] = {name = "Mob" .. index, guid = "Creature-1" .. index}
        state.units.target = state.units["nameplate" .. (10 + index)]
        state.emit("UNIT_SPELLCAST_SENT", "player", "Mob" .. index, "cast-f" .. index, BANISH)
        state.emit("UNIT_SPELLCAST_FAILED", "player", "cast-f" .. index, BANISH)
    end
    castAt(state, FEAR, "nameplate3")
    equal(controlRow(state, 1).name.text, "Boar", "failed casts never use up the rows")
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
    equal(controlRow(state, 1).name.text, "Ghoul", "a Fear cast through mouseover is tracked")
    equal(controlRow(state, 1).container.unit, "none", "but the row does not bind to the pointer's unit")
    state.units.nameplate6 = state.units.mouseover
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate6")
    equal(controlRow(state, 1).container.unit, "nameplate6", "its nameplate instead")
end)
test("a feared mob's nameplate shows a Fear countdown, also after its plate comes back", function()
    local state = controlFixture()
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate3")
    local plate = state.plates.nameplate3
    local timer = state.wtf.fearPlateTimers.nameplate3
    equal(timer.parent, plate, "a timer under the nameplate")
    equal(timer.points[1][1], "TOP")
    equal(timer.points[1][2], plate)
    equal(timer.container.unit, "nameplate3")
    local slot = timer.container.slots[1]
    equal(slot.key, "fear")
    equal(slot.filter, "HARMFUL|PLAYER", "only your Fear")
    equal(slot.ids[FEAR], true)
    equal(slot.ids[BANISH], nil, "Fear only")
    equal(slot.button.display.barOptions.direction, 1, "drains with the time left")
    -- Out of plate range and back, on another plate: the timer follows.
    state.emit("NAME_PLATE_UNIT_REMOVED", "nameplate3")
    equal(timer.container.unit, "none")
    state.units.nameplate8 = state.units.nameplate3
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate8")
    equal(timer.container.unit, "nameplate8", "the same timer, reused, on the new plate")
    state.settings.WTF_CONTROL_PLATE_TIMERS:SetValue(false)
    equal(timer.container.unit, "none", "its switch")
    state.clear()
    state.slash("debug_control")
    contains(table.concat(state.messages, "|"), "plateTimers=false attached=0")
end)
test("control macros appear only for the spells you know; Seduction needs your Succubus", function()
    local state = controlFixture({known = {[FEAR] = true}})
    local fear = "#showtooltip Fear\n/focus [mod:shift,@mouseover,harm,nodead][mod:shift,harm,nodead]"
        .. "\n/use [@focus,exists,harm,nodead][@mouseover,harm,nodead][harm,nodead] Fear"
    equal(macroBody(state, "! Fear"), fear,
        "Shift sets the focus; then your focus first, else the mob under the mouse, else your target")
    equal(#fear, 157, "the body's length")
    equal(macroBody(state, "! Banish"), nil, "no Banish before you learn it")
    equal(macroBody(state, "! Seduction"), nil, "no Seduction before Summon Succubus")
    state.known[BANISH] = true
    state.emit("SPELLS_CHANGED")
    equal(macroBody(state, "! Banish"), "#showtooltip Banish\n/focus [@mouseover,harm,nodead][nocombat,harm,nodead]"
        .. "\n/tm [@focus,harm,nodead,exists] !5\n/use [@focus,exists,harm,nodead] Banish",
        "the moon by the game's /tm, also in combat")
    state.known[712] = true
    state.emit("SPELLS_CHANGED")
    equal(macroBody(state, "! Seduction"), nil, "Summon Succubus alone is not enough: no Grimoire yet")
    -- The Succubus learns Seduction from its Grimoire.
    state.petKnown = {[6358] = true}
    state.emit("UNIT_PET", "player")
    contains(macroBody(state, "! Seduction"), "/use [@focus,exists,harm,nodead,pet:Succubus/Incubus] Seduction",
        "does nothing unless your pet is a Succubus or an Incubus")
    state.combat = true
    state.settings.WTF_CONTROL_MACROS:SetValue(false)
    equal(macroBody(state, "! Banish") ~= nil, true, "macros change only out of combat")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(macroBody(state, "! Banish"), nil, "turning them off deletes them")
    equal(macroBody(state, "! Seduction"), nil)
    equal(macroBody(state, "! Fear"), nil)
end)
test("the Banish marker setting goes into the macro and the row click, rebuilt out of combat", function()
    local state = controlFixture({known = {[FEAR] = true, [BANISH] = true}})
    castAt(state, BANISH, "nameplate4")
    local click = state.env.WarlockToolsForeverControlClick1
    state.settings.WTF_CONTROL_MARKER_BANISH:SetValue(8)
    contains(macroBody(state, "! Banish"), "/tm [@focus,harm,nodead,exists] !8")
    contains(click.attributes.macrotext1, "/tm [@target,harm,nodead,exists] !8")
    state.combat = true
    state.settings.WTF_CONTROL_MARKER_BANISH:SetValue(0)
    contains(macroBody(state, "! Banish"), "!8", "a macro changes only out of combat")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(macroBody(state, "! Banish"):find("/tm", 1, true), nil, "None: no /tm line")
    equal(click.attributes.macrotext1:find("/tm", 1, true), nil)
    contains(click.attributes.macrotext1, "/targetexact Imp", "the click still recasts")
    equal(macroBody(state, "! Fear"):find("/tm", 1, true), nil, "Fear never marks")
end)
test("Seduction has no marker setting, so its macro has no /tm", function()
    local state = controlFixture({known = {[712] = true}})
    state.petKnown = {[6358] = true}
    state.emit("UNIT_PET", "player")
    equal(macroBody(state, "! Seduction"):find("/tm", 1, true), nil)
end)
test("an Incubus that knows Seduction by its own ID gets the macro too; one that does not, none", function()
    local state = controlFixture({known = {[FEAR] = true, [713] = true}})
    -- An Incubus out, before its Grimoire.
    state.petFamily = "Incubus"
    state.petSpellbook = {{spellID = 99001, name = "Lash of Pain"}}
    state.emit("UNIT_PET", "player")
    equal(macroBody(state, "! Seduction"), nil, "no Seduction yet")
    -- Its Grimoire teaches Seduction under another ID: found by name.
    state.petSpellbook[2] = {spellID = 99002, name = "Seduction"}
    state.emit("SPELLS_CHANGED")
    contains(macroBody(state, "! Seduction"), "pet:Succubus/Incubus")
    -- Dismissed: the macro stays, and does nothing without the demon.
    state.petSpellbook, state.petFamily = nil, nil
    state.emit("UNIT_PET", "player")
    equal(macroBody(state, "! Seduction") ~= nil, true)
    state.clear()
    state.slash("debug_control")
    contains(table.concat(state.messages, "|"), "debug_control pet=nil seduction=false")
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

test("with Dyre's Buff Reminders loaded, WTF's Demon Armor icon stays hidden and keeps its setting", function()
    local state = fixture({known = {[DEMON_SKIN] = true, [DEMON_ARMOR] = true},
        loadedAddOns = {DyresBuffReminders = true}})
    local icon = state.env.WarlockToolsForeverReminder_armor
    equal(icon.shown, false, "no second icon beside Dyre's Buff Reminders'")
    state.slash("unlock")
    equal(icon.shown, false, "not even to drag")
    equal(state.wtf.db.reminders.enabled, true, "the saved switch is untouched")
    equal(state.settings.WTF_REMINDERS_ENABLED.name, "Demon Armor reminder (shown by Dyre's Buff Reminders)")
end)
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

-- Dyre's Toolkit ----------------------------------------------------------------------

local TOOLKIT_INSTALL = "WTF: Install Dyre's Toolkit from CurseForge for one layout mode and settings home for "
    .. "all Dyre's AddOns."

local function countMessages(state, text)
    local found = 0
    for _, message in ipairs(state.messages) do
        if message:find(text, 1, true) then found = found + 1 end
    end
    return found
end

local function registeredMovable(state, frame)
    for _, movable in ipairs(state.toolkit.movables) do
        if movable == frame then return true end
    end
    return false
end

test("with Dyre's Toolkit WTF joins its layout mode, quietly, and starts locked", function()
    local state = fixture({toolkit = true, db = {locked = false}})
    local toolkit, db = state.toolkit, state.wtf.db
    equal(toolkit.info.addon, "WarlockToolsForever")
    equal(toolkit.info.title, "Warlock Tools Forever")
    equal(db.locked, true, "frames start locked, as the toolkit's do")
    equal(countMessages(state, "Dyre's Toolkit"), 0, "nothing to install")
    for _, frame in ipairs({state.wtf.shardCounter, state.env.WarlockToolsForeverStones,
        state.env.WarlockToolsForeverTracker, state.env.WarlockToolsForeverControl,
        state.env.WarlockToolsForeverReminder_armor}) do
        equal(registeredMovable(state, frame), true, "every movable frame snaps through the toolkit")
    end
    state.clear()
    state.slash("unlock")
    equal(toolkit.locked, false, "/wtf unlock unlocks every Dyre's AddOn")
    equal(db.locked, false)
    equal(db.tracker.placeholders, true, "sample rows to drag the tracker by")
    equal(state.env.WarlockToolsForeverStones.mover.shown, true, "outlined")
    equal(state.wtf.shardCounter.mover.shown, true)
    equal(countMessages(state, "All WTF frames"), 0, "the toolkit says one line for all")
    equal(state.last(), "Dyre: Frames unlocked.")
    equal(state.wtf.grid, nil, "the toolkit draws the grid")
    local icon = state.env.WarlockToolsForeverReminder_armor
    icon.scripts.OnDragStart(icon)
    icon.scripts.OnDragStop(icon)
    equal(toolkit.calls[#toolkit.calls - 1][1], "BeginDrag")
    equal(toolkit.calls[#toolkit.calls - 1][2], icon)
    equal(toolkit.calls[#toolkit.calls][1], "EndDrag")
    icon.scripts.OnMouseWheel(icon, 1)
    equal(toolkit.calls[#toolkit.calls][1], "ScaleKeepingCenter", "resizing goes through the toolkit")
    equal(state.wtf.db.reminders.icons.armor.scale, 110)
    state.slash("lock")
    equal(toolkit.locked, true, "/wtf lock locks every Dyre's AddOn")
    equal(db.locked, true)
    equal(state.env.WarlockToolsForeverStones.mover.shown, false)
    toolkit.Unlock()
    equal(db.locked, false, "the toolkit's own unlock reaches WTF's frames")
    state.slash("lock")
    equal(toolkit.locked, true)
    equal(db.locked, true)
end)
test("with Dyre's Toolkit WTF's settings sit under Dyre's AddOns, three levels deep", function()
    local state = fixture({toolkit = true})
    local home = state.categories["Dyre's AddOns"]
    local page = state.categories["Warlock Tools Forever"]
    equal(page.parent, home)
    equal(state.registered, nil, "no top-level page of its own")
    for _, name in ipairs({"Soul Shards", "Stones", "DoT Tracker", "DoTs", "Alerts", "Shield",
        "Cooldown Chimes", "Control", "Announce"}) do
        equal(state.categories[name].parent, page, name .. " is under WTF's page")
    end
    equal(state.settings.WTF_GRID, nil, "the toolkit's page has the grid")
    equal(state.settings.WTF_UNLOCKED, nil, "and the one unlock switch for every Dyre's AddOn")
    for _, category in pairs(state.categories) do
        for _, initializer in ipairs(category.initializers) do
            equal((initializer.setting.name or ""):find("Unlock", 1, true), nil,
                "no unlock switch on " .. category.name)
        end
    end
    state.slash("options")
    equal(state.toolkit.opened[1], page, "opened through the toolkit, which waits out combat")
    state.toolkit.info.openSettings()
    equal(state.toolkit.opened[2], page)
end)
test("without Dyre's Toolkit WTF keeps its own layout and pages and says once to install it", function()
    local state = fixture()
    equal(countMessages(state, TOOLKIT_INSTALL), 1)
    local page = state.categories["Warlock Tools Forever"]
    equal(state.registered, page, "WTF's own top-level page")
    equal(page.parent, nil)
    equal(state.categories["Soul Shards"].parent, page)
    equal(state.settings.WTF_GRID:GetValue(), true, "WTF's own grid switch")
    equal(state.settings.WTF_UNLOCKED.category, page, "WTF's own unlock switch, the only one here")
    state.settings.WTF_UNLOCKED:SetValue(true)
    equal(state.wtf.db.locked, false)
    state.settings.WTF_UNLOCKED:SetValue(false)
    equal(state.wtf.db.locked, true)
    state.slash("unlock")
    contains(state.last(), "All WTF frames unlocked")
    equal(state.wtf.grid.shown, true, "WTF's own grid")
    state.slash("lock")
    equal(countMessages(state, TOOLKIT_INSTALL), 1, "once")
end)
test("with Dyre's Toolkit the shield ring drags and snaps through its layout", function()
    local state = fixture({toolkit = true})
    local toolkit, ring = state.toolkit, state.wtf.ShieldDisplay.frame
    equal(registeredMovable(state, ring), true, "the ring is one of the toolkit's frames")
    ring.scripts.OnDragStart(ring)
    equal(#toolkit.calls, 0, "locked: no drag")
    state.slash("unlock")
    ring.scripts.OnDragStart(ring)
    ring.scripts.OnDragStop(ring)
    equal(toolkit.calls[#toolkit.calls - 1][1], "BeginDrag")
    equal(toolkit.calls[#toolkit.calls - 1][2], ring)
    equal(toolkit.calls[#toolkit.calls][1], "EndDrag")
    equal(ring.moving, nil, "the toolkit moves it, not the ring itself")
end)
test("without Dyre's Toolkit the shield ring drags itself, as before", function()
    local state = fixture()
    local ring = state.wtf.ShieldDisplay.frame
    state.slash("unlock")
    ring.scripts.OnDragStart(ring)
    equal(ring.moving, true)
    ring.scripts.OnDragStop(ring)
    equal(ring.moving, false)
    equal(type(state.wtf.db.shield.position), "table", "its place is saved")
end)
test("an unusable Dyre's Toolkit leaves WTF on its own layout", function()
    for _, options in ipairs({{toolkit = "old"}, {toolkit = true, toolkitMissing = "ScaleKeepingCenter"}}) do
        local state = fixture(options)
        equal(state.toolkit.info, nil, "not registered")
        equal(countMessages(state, "WTF: Update Dyre's Toolkit from CurseForge"), 1)
        equal(state.registered, state.categories["Warlock Tools Forever"])
        equal(#state.toolkit.movables, 0)
        state.slash("unlock")
        equal(state.toolkit.locked, true, "the toolkit is not asked")
        contains(state.last(), "All WTF frames unlocked")
    end
    local homeless = fixture({toolkit = true, toolkitNoSettings = true})
    equal(homeless.registered, homeless.categories["Warlock Tools Forever"], "no home: WTF's own top-level page")
    equal(homeless.toolkit.info.addon, "WarlockToolsForever", "the layout mode still applies")
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

test("a tiny absorb stays hidden: a gate bar ending at the minimum clips the ring", function()
    local state = fixture()
    local ring = state.wtf.ShieldDisplay.frame
    state.emit("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    equal(ring.gate.value, state.absorb, "the secret absorb, passed on unread")
    equal(ring.gate.minValue, 74, "one point wide, so the fill is empty or full")
    equal(ring.gate.maxValue, 75, "5% of 1500 health beats 25 points")
    equal(ring.gated.clips, true)
    equal(ring.gated.points[2][2], ring.gate:GetStatusBarTexture(), "the clip ends where the gate's fill ends")
    equal(ring.bar.parent, ring.gated)
    equal(ring.gated.parent, ring.visible, "the opacity still follows the absorb")
    state.slash("unlock")
    equal(ring.gate.value, 1, "unlocked, the gate is open for the sample")
end)
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
local function initializerFor(page, variable)
    for _, initializer in ipairs(page.initializers) do
        if initializer.setting.variable == variable then return initializer end
    end
end

test("size sliders are labeled without (%): their values show the % sign", function()
    local state = fixture()
    for _, case in ipairs({{"Shield", "WTF_SHIELD_SCALE", "Display size"},
        {"Control", "WTF_CONTROL_SCALE", "Bar size"}}) do
        local slider = initializerFor(state.categories[case[1]], case[2])
        equal(slider.setting.name, case[3])
        equal(slider.options.label, "right")
        equal(slider.options.formatter(80), "80%", case[3] .. ": the value shows its % sign")
    end
    for _, category in pairs(state.categories) do
        for _, initializer in ipairs(category.initializers) do
            local name = initializer.setting and initializer.setting.name
            if type(name) == "string" then
                equal(name:find("(%)", 1, true), nil, name .. ": no (%) in a label")
            end
        end
    end
end)
test("the shield break sound comes from Dyre's Sounds, chosen under its switch", function()
    local state = fixture()
    equal(state.wtf.db.shield.breakSoundKey, "fadingslow", "the default")
    local dropdown = initializerFor(state.categories.Shield, "WTF_SHIELD_BREAK_SOUND_CHOICE")
    equal(dropdown.parentInitializer.setting.variable, "WTF_SHIELD_BREAK_SOUND", "under the sound switch")
    equal(dropdown.soundMenu, "aura", "Dyre's Sounds' nested menu of aura sounds")
    local labels = {}
    for _, choice in ipairs(dropdown.choices()) do labels[#labels + 1] = choice.label end
    equal(table.concat(labels, ", "), "Dyre's Picks: Fading slow disappear, Dyre's Picks: Disappear blow swoosh, "
        .. "Dyre's Picks: Cartoon vanish, Dyre's Picks: Magical disappear, Dyre's Picks: Slow swoosh, "
        .. "Imp: Laugh 1, Imp: Spell chirp", "no sound kits or Text to Speech")
    state.settings.WTF_SHIELD_BREAK_SOUND:SetValue(true)
    equal(state.lastSound().key, "fadingslow", "turning it on plays it once")
    local live
    for _, sound in pairs(state.auraSounds) do live = sound end
    equal(live.info.soundFileName, "Interface\\AddOns\\DyresSounds\\Sounds\\FadingSlowDisappear.mp3",
        "Dyre's Sounds' file: WTF ships no sounds")
    state.settings.WTF_SHIELD_BREAK_SOUND_CHOICE:SetValue("blowswoosh")
    equal(state.lastSound().key, "blowswoosh", "previewed")
    equal(state.wtf.db.shield.breakSoundKey, "blowswoosh")
    state.settings.WTF_SHIELD_BREAK_SOUND_CHOICE:SetValue("talent")
    equal(state.wtf.db.shield.breakSoundKey, "fadingslow", "a sound kit cannot be an aura sound")
end)
test("without Dyre's Sounds the shield display keeps its sound choice and says what to install", function()
    local state = fixture({noSounds = true, db = {shield = {breakSoundKey = "magical", breakSound = true}}})
    equal(state.wtf.db.shield.breakSoundKey, "magical", "a missing library never resets a choice")
    equal(state.auraSoundCount, nil, "no sound to register")
    local found = 0
    for _, message in ipairs(state.messages) do
        if message:find("Install Dyre's Sounds", 1, true) then
            found = found + 1
            contains(message, "the shield sound", "WTF's one line covers the shield sound")
        end
    end
    equal(found, 1, "one line for all of WTF's sounds")
    equal(#initializerFor(state.categories.Shield, "WTF_SHIELD_BREAK_SOUND_CHOICE").choices(), 0, "an empty list")
end)

-- Cooldown chimes ----------------------------------------------------------------

local DEATH_COIL = 6789
local SHADOW_TRANCE = 17941

local function wait(state, seconds)
    state.now = state.now + seconds
    state.runTimers()
end

-- The registered Nightfall aura sounds.
local function liveNightfall(state)
    local list = {}
    for _, sound in pairs(state.auraSounds or {}) do
        if sound.info.spellID == SHADOW_TRANCE then list[#list + 1] = sound end
    end
    return list
end

test("a chime plays just before Death Coil is ready again, also in combat", function()
    local state = fixture()
    state.combat = true
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", DEATH_COIL)
    wait(state, 0.1)
    wait(state, 119)
    equal(#state.sounds, 0, "not yet")
    wait(state, 0.5)
    equal(#state.soundsPlayed, 1, "half a second early")
    equal(state.soundsPlayed[1].key, "talent", "Talent ready by default, through Dyre's Sounds")
    equal(state.soundsPlayed[1].speech, "Death Coil ready", "the text Text to Speech would say")
    equal(state.played, nil, "WTF plays no file of its own")
    equal(#state.sounds, 0, "and no sound kit of its own")
end)
test("a chime can use one of Dyre's Picks; an old WTF key is mapped by Dyre's Sounds", function()
    local state = fixture()
    state.settings.WTF_CHIME_SOUND_DEATHCOIL:SetValue("effectcartoonvanish")
    equal(state.wtf.db.chimes.sounds.deathcoil, "cartoonvanish", "saved in the library's spelling")
    equal(state.lastSound().key, "cartoonvanish", "previewed")
    state.combat = true
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", DEATH_COIL)
    wait(state, 0.1)
    wait(state, 120)
    equal(#state.soundsPlayed, 2, "the chime plays, also in combat")
    equal(state.lastSound().key, "cartoonvanish")
end)
test("Text to Speech says the spell; without a voice the chime falls back to the default", function()
    local state = fixture()
    state.settings.WTF_CHIME_SOUND_HOWL:SetValue("voice")
    equal(state.lastSound().key, "voice")
    equal(state.lastSound().speech, "Howl of Terror ready", "the preview says it too")
    state.noVoice = true
    state.wtf.PreviewChime("howl")
    equal(state.lastSound().key, "talent", "no voice: the default plays instead")
    equal(state.lastSound().speech, "Howl of Terror ready")
    equal(state.wtf.db.chimes.sounds.howl, "voice", "the choice stays")
end)
test("saved chime and Nightfall keys: mapped with Dyre's Sounds, kept without it", function()
    local db = {chimes = {sounds = {deathcoil = "effectmagical", howl = "popclick", shadowward = "bogus",
        soulstone = 5}}, alerts = {nightfall = false, nightfallSound = "pickslowswoosh"}}
    local mapped = fixture({db = db})
    equal(mapped.wtf.db.chimes.sounds.deathcoil, "magical")
    equal(mapped.wtf.db.chimes.sounds.howl, "impactspopclick")
    equal(mapped.wtf.db.chimes.sounds.shadowward, "talent", "an unknown key: the default")
    equal(mapped.wtf.db.chimes.sounds.soulstone, "talent", "a damaged value: the default")
    equal(mapped.wtf.db.alerts.nightfallSound, "slowswoosh")
    db = {chimes = {sounds = {deathcoil = "effectmagical", howl = "bogus", soulstone = 5}},
        alerts = {nightfallSound = "pickslowswoosh"}}
    local kept = fixture({noSounds = true, db = db})
    equal(kept.wtf.db.chimes.sounds.deathcoil, "effectmagical", "kept as saved")
    equal(kept.wtf.db.chimes.sounds.howl, "bogus", "the library decides later what it means")
    equal(kept.wtf.db.chimes.sounds.soulstone, "talent", "a damaged value still is repaired")
    equal(kept.wtf.db.alerts.nightfallSound, "pickslowswoosh")
    local old = fixture({oldSounds = true, db = {chimes = {sounds = {deathcoil = "effectmagical"}}}})
    equal(old.wtf.db.chimes.sounds.deathcoil, "effectmagical", "an older library counts as missing")
end)
test("without Dyre's Sounds chimes still time, play nothing, and WTF says once what to install", function()
    local state = fixture({noSounds = true})
    local function count()
        local found = 0
        for _, message in ipairs(state.messages) do
            if message == "WTF: Install Dyre's Sounds to hear WTF's sounds (the chimes, the Nightfall sound, and "
                .. "the shield sound). Get it from CurseForge." then
                found = found + 1
            end
        end
        return found
    end
    equal(count(), 1, "said at login, since the chimes are on")
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", DEATH_COIL)
    wait(state, 0.1)
    equal(state.wtf.db.chimes.learned.deathcoil, nil)
    wait(state, 120)
    equal(#state.sounds, 0, "nothing plays")
    equal(state.played, nil)
    state.settings.WTF_ALERTS_NIGHTFALL:SetValue(true)
    equal(count(), 1, "once per session")
    equal(state.settings.WTF_CHIME_SOUND_DEATHCOIL, nil, "no sound menus without sounds")
    equal(state.settings.WTF_ALERTS_NIGHTFALL_SOUND, nil)
    contains(initializerFor(state.categories["Cooldown Chimes"], "WTF_CHIME_DEATHCOIL").tooltip,
        "Install Dyre's Sounds")
    local old = fixture({oldSounds = true})
    contains(table.concat(old.messages, "|"), "Update Dyre's Sounds")
    local quiet = fixture({noSounds = true, db = {chimes = {enabled = false}}})
    equal(table.concat(quiet.messages, "|"):find("Dyre's Sounds", 1, true), nil, "nothing wants a sound")
end)
-- Plays no chime, keeps the saved settings, and names `title` and `slash` in the settings.
local function checkChimesStandAside(loaded, addon, title, slash)
    local saved = {chimes = {enabled = true, lead = 1, spells = {inferno = true}, sounds = {howl = "voice"},
        learned = {deathcoil = 90}}}
    local state = fixture({loadedAddOns = loaded, db = saved})
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", DEATH_COIL)
    wait(state, 200)
    equal(#state.soundsPlayed, 0, "no chime")
    state.wtf.PreviewChime("deathcoil")
    equal(#state.soundsPlayed, 0, "not even a preview")
    local db = state.wtf.db.chimes
    equal(db.enabled, true)
    equal(db.lead, 1)
    equal(db.spells.inferno, true)
    equal(db.sounds.howl, "voice")
    equal(db.learned.deathcoil, 90, "kept for the other AddOn to copy")
    equal(state.categories["Cooldown Chimes"], nil, "the list name says who runs them")
    local page = state.categories["Cooldown Chimes (" .. title .. ")"]
    equal(page.headings[1].heading, "Cooldown chimes are now managed by " .. title)
    contains(page.headings[1].tooltip, slash)
    equal(#page.initializers, 1, "the page only says who plays them")
    equal(page.initializers[1].setting.name, "Played by " .. title)
    contains(page.initializers[1].tooltip, slash)
    equal(page.initializers[1].modifyPredicates[1](), false, "greyed out")
    local main = initializerFor(state.categories["Warlock Tools Forever"], "WTF_CHIMES_ENABLED")
    equal(main.setting.name, "Cooldown chimes (played by " .. title .. ")")
    contains(main.tooltip, title .. " plays your cooldown chimes")
    main.setting:SetValue(false)
    equal(state.wtf.db.chimes.enabled, true, "the main page's switch changes nothing")
    state.settings.WTF_ALERTS_NIGHTFALL:SetValue(true)
    equal(#liveNightfall(state), 1, "the Nightfall sound stays in WTF")
    state.clear()
    state.slash("debug_chimes")
    contains(table.concat(state.messages, "|"), "playedBy=" .. addon)
end
test("with Dyre's Buff Reminders installed WTF plays no chimes and keeps its settings", function()
    checkChimesStandAside({DyresBuffReminders = true}, "DyresBuffReminders", "Dyre's Buff Reminders", "/dbr")
end)
test("Dyre's Cooldown Chimes, while still installed, plays the chimes instead of WTF and DBR", function()
    checkChimesStandAside({DyresCooldownChimes = true}, "DyresCooldownChimes", "Dyre's Cooldown Chimes", "/dcc")
    checkChimesStandAside({DyresCooldownChimes = true, DyresBuffReminders = true}, "DyresCooldownChimes",
        "Dyre's Cooldown Chimes", "/dcc")
end)
test("without a chimes AddOn WTF plays its own chimes", function()
    local state = fixture()
    equal(state.wtf.ChimesStandAside(), nil)
    state.slash("debug_chimes")
    contains(table.concat(state.messages, "|"), "playedBy=WTF")
end)
test("out of combat the real cooldown is read and learned; switches turn chimes off", function()
    local state = fixture()
    state.cooldowns[DEATH_COIL] = {start = state.now, duration = 90}
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", DEATH_COIL)
    wait(state, 0.1)
    equal(state.wtf.db.chimes.learned.deathcoil, 90, "Forever's own cooldown")
    wait(state, 89.5)
    equal(#state.soundsPlayed, 1)
    state.settings.WTF_CHIME_DEATHCOIL:SetValue(false)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", DEATH_COIL)
    wait(state, 100)
    equal(#state.soundsPlayed, 1, "its switch")
    state.settings.WTF_CHIME_DEATHCOIL:SetValue(true)
    state.settings.WTF_CHIMES_ENABLED:SetValue(false)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", DEATH_COIL)
    wait(state, 100)
    equal(#state.soundsPlayed, 1, "the module switch")
end)
test("each chime has its own sound from Dyre's Sounds, and choosing one plays it", function()
    local state = fixture()
    local sound = state.settings.WTF_CHIME_SOUND_HOWL
    equal(sound:GetValue(), "talent")
    sound:SetValue("impactspopclick")
    equal(state.wtf.db.chimes.sounds.howl, "impactspopclick")
    equal(state.lastSound().key, "impactspopclick", "previewed: the Cooldown Manager's Pop click")
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
    local state = fixture({shieldCopies = {{addon = "MageToolsForever", version = 11, before = true}}})
    equal(state.wtf.ShieldDisplay.IsOwner(), true, "only running copies take part")
    equal(state.wtf.ShieldDisplay.frame ~= nil, true, "WTF draws the ring")
    state.clear()
    state.slash("debug_shield")
    contains(table.concat(state.messages, "|"),
        "owner=WarlockToolsForever copies=MageToolsForever v11, WarlockToolsForever v11 (running)")
    equal(table.concat(state.messages, "|"):find("failed", 1, true), nil, "every debug step ran")
end)
test("with Dyre's Shields Up loaded, WTF draws no shield and greys out its shield settings", function()
    local state = fixture({loadedAddOns = {DyresShieldsUp = true}, db = {shield = {scale = 80, breakSound = true}}})
    equal(state.wtf.ShieldDisplay.frame, nil, "no ring of its own: Dyre's Shields Up draws it")
    equal(state.wtf.ShieldDisplay.IsOwner(), false, "not even a candidate")
    state.emit("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    state.slash("unlock")
    state.slash("lock")
    for _, message in ipairs(state.messages) do
        equal(message:find("shown by", 1, true), nil, "no election message")
    end
    equal(state.wtf.db.shield.scale, 80, "its saved shield settings stay as they are")
    equal(state.wtf.db.shield.breakSound, true)
    local seen = 0
    for _, page in pairs(state.categories) do
        for _, initializer in ipairs(page.initializers) do
            local variable = initializer.setting and initializer.setting.variable or ""
            if variable:find("^WTF_SHIELD_") then
                seen = seen + 1
                equal(initializer.modifyPredicates[1](), false, variable .. " is greyed out")
                contains(initializer.tooltip, "Dyre's Shields Up shows the shield display now")
            end
        end
    end
    equal(seen, 5, "the switch, number, sound, its choice, and the size")
    equal(state.categories.Shield, nil, "the list name says who runs it")
    local page = state.categories["Shield (Dyre's Shields Up)"]
    equal(page.headings[1].heading, "Shields are now managed by Dyre's Shields Up")
    contains(page.headings[1].tooltip, "/dsu")
    equal(#fixture().categories.Shield.headings, 0, "no heading without Dyre's Shields Up")
end)
test("a newer running copy takes over, and WTF says which AddOn shows the display", function()
    local state = fixture({shieldCopies = {{addon = "ShieldForever", version = 12}}})
    equal(state.wtf.ShieldDisplay.frame ~= nil, true, "drawing while it is the only one running")
    local function shieldGreyed(want)
        local seen = 0
        for _, page in pairs(state.categories) do
            for _, initializer in ipairs(page.initializers) do
                local variable = initializer.setting and initializer.setting.variable or ""
                if variable:find("^WTF_SHIELD_") then
                    seen = seen + 1
                    equal(initializer.modifyPredicates[1](), not want, variable .. (want and " is greyed out" or " is not greyed"))
                end
            end
        end
        equal(seen, 5, "the switch, number, sound, its choice, and the size")
    end
    shieldGreyed(false)
    local other = state.copies.ShieldForever.ShieldDisplay
    other.Initialize({settings = function() return other.Sanitize({}) end, report = function() end})
    equal(state.wtf.ShieldDisplay.frame, nil, "WTF stood down")
    shieldGreyed(true)
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
    -- Shield v11: the timed crescent is a slot of its own container.
    local bubble
    for _, slot in ipairs(ring.crescents.slots) do
        if slot.key == "blessingofprotection" then bubble = slot.button end
    end
    local bar = bubble.display.bar
    contains(bar.statusBarTexture, "ShieldArcInnermost")
    equal(bar.barColor[1], 1, "gold")
    equal(bubble.display.barOptions.direction, 1, "drains with its time left")
    equal(ring.iconButtons.blessingofprotection.display.icon ~= nil, true, "its icon in the icon row")
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
test("a drop after combat began waits, then snaps and saves the group when combat ends", function()
    local state = stonesFixture()
    state.slash("unlock")
    local bar, counter = state.env.WarlockToolsForeverStones, state.wtf.shardCounter
    dropAt(state, bar, 400, 300)
    local barX, barY = centerOf(state, bar)
    dropAt(state, counter, barX + bar.width / 2 + 20 + counter.width / 2, barY)
    local gapX = select(1, centerOf(state, counter)) - barX
    local saved = state.wtf.db.shards.counterPosition
    state.shift = true
    bar.scripts.OnDragStart(bar)
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", nil, "BOTTOMLEFT", 200, 600)
    state.combat = true
    bar.scripts.OnDragStop(bar)
    equal(state.wtf.db.shards.counterPosition, saved, "nothing saved in combat")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(state.wtf.db.shards.counterPosition.relativePoint, "BOTTOMLEFT", "saved once combat ends")
    equal(select(1, centerOf(state, counter)) - select(1, centerOf(state, bar)), gapX, "the group kept together")
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
local function tradeFixture()
    return stonesFixture({carried = {[5511] = 1}, bags = bagWith(5511),
        units = {target = {name = "Lowbie", player = true, friend = true, level = 20}}})
end
test("a trade that opens while item moves are restricted is placed at the first free key press", function()
    local state = tradeFixture()
    state.clickButton(HEALTH, "LeftButton")
    state.encounter = true
    state.clear()
    state.emit("TRADE_SHOW")
    equal(state.restrictedCalls, nil, "no pickup or click while restricted")
    equal(state.tradeSlots[1], nil)
    equal(state.cursor, nil)
    equal(#state.messages, 0, "no warning")
    state.encounter = nil
    state.press()
    equal(state.tradeSlots[1], 5511, "placed at the first key press without a restriction")
    equal(state.last(), "WTF: Healthstone in the trade window. Press Trade to give it.")
    state.clear()
    state.slash("debug_stones")
    contains(table.concat(state.messages, "|"), "moveRestricted=false lastRestricted=")
end)
test("a trade still restricted at the next key press warns once and makes no call", function()
    local state = tradeFixture()
    state.clickButton(HEALTH, "LeftButton")
    state.restrictions = {[4] = 2}
    state.emit("TRADE_SHOW")
    state.clear()
    state.press()
    state.press()
    equal(state.restrictedCalls, nil, "never a pickup or click")
    equal(state.tradeSlots[1], nil)
    equal(#state.messages, 1, "one warning")
    contains(state.messages[1], "drag it in yourself")
    state.restrictions = nil
    state.press()
    equal(state.tradeSlots[1], nil, "given up: you drag it in")
end)
test("a trade retry later than the wait window gives up with the warning", function()
    local state = tradeFixture()
    state.clickButton(HEALTH, "LeftButton")
    state.combat = true
    state.emit("TRADE_SHOW")
    state.combat = false
    state.now = state.now + 30
    state.clear()
    state.press()
    equal(state.tradeSlots[1], nil)
    contains(state.last(), "drag it in yourself")
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
test("turned on, the game plays the chosen sound from Dyre's Sounds when Shadow Trance appears", function()
    local state = fixture()
    state.settings.WTF_ALERTS_NIGHTFALL:SetValue(true)
    local sounds = liveSounds(state)
    equal(#sounds, 1)
    equal(sounds[1].trigger, 0, "on the buff appearing")
    equal(sounds[1].info.spellID, 17941)
    equal(sounds[1].info.unitToken, "player")
    equal(sounds[1].info.outputChannel, "master")
    equal(sounds[1].info.soundFileID, 639156, "the Imp spell chirp by file ID")
    equal(sounds[1].info.soundFileName, nil)
    state.settings.WTF_ALERTS_NIGHTFALL_SOUND:SetValue("magical")
    sounds = liveSounds(state)
    equal(#sounds, 1, "the old sound is replaced")
    equal(sounds[1].info.soundFileName, "Interface\\AddOns\\DyresSounds\\Sounds\\MagicalDisappear.mp3",
        "one of Dyre's Picks, Dyre's Sounds' file")
    equal(sounds[1].info.soundFileID, nil)
    equal(state.lastSound().key, "magical", "choosing a sound previews it")
    equal(state.played, nil, "WTF plays no file of its own")
    state.settings.WTF_ALERTS_NIGHTFALL_SOUND:SetValue("talent")
    equal(state.wtf.db.alerts.nightfallSound, "magical", "a sound kit cannot be an aura sound")
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
    local state = fixture({db = {alerts = {nightfall = true, nightfallSound = "pickslowswoosh"}}})
    equal(state.wtf.db.alerts.nightfallSound, "slowswoosh", "an old WTF key, mapped by Dyre's Sounds")
    equal(liveSounds(state)[1].info.soundFileName, "Interface\\AddOns\\DyresSounds\\Sounds\\SlowSwoosh.wav")
    local former = fixture({db = {alerts = {nightfall = true, nightfallSound = "talent"}}})
    equal(former.wtf.db.alerts.nightfallSound, "impspell", "a sound kit falls back to the default")
    local repaired = fixture({db = {alerts = {nightfall = "yes", nightfallSound = "kazoo"}}})
    equal(repaired.wtf.db.alerts.nightfall, false)
    equal(repaired.wtf.db.alerts.nightfallSound, "impspell")
end)
test("without Dyre's Sounds the Nightfall sound registers nothing and keeps its choice", function()
    local state = fixture({noSounds = true, db = {chimes = {enabled = false},
        alerts = {nightfall = true, nightfallSound = "implaugh1"}}})
    equal(#liveSounds(state), 0)
    equal(state.wtf.db.alerts.nightfallSound, "implaugh1")
    contains(table.concat(state.messages, "|"), "Install Dyre's Sounds to hear WTF's sounds")
    local page = state.categories.Alerts
    equal(#page.initializers, 1, "the switch, without a sound menu")
    contains(page.initializers[1].tooltip, "Install Dyre's Sounds")
    state.wtf.PreviewNightfallSound()
    equal(state.played, nil)
end)
test("with Dyre's Buff Reminders 0.3.0 or later WTF plays no Nightfall sound and keeps its settings", function()
    local saved = {chimes = {enabled = false}, alerts = {nightfall = true, nightfallSound = "implaugh1"}}
    for _, version in ipairs({"0.3.0-beta", "0.3.1", "0.10.0-beta", "1.0.0"}) do
        local state = fixture({loadedAddOns = {DyresBuffReminders = true},
            addOnVersions = {DyresBuffReminders = version}, db = saved})
        equal(#liveSounds(state), 0, "no aura sound with DBR " .. version)
        state.wtf.ApplyNightfallSound()
        equal(#liveSounds(state), 0, "nothing registers later either")
        state.wtf.PreviewNightfallSound()
        equal(#state.soundsPlayed, 0, "no preview")
        equal(state.wtf.db.alerts.nightfall, true, "kept for DBR to copy")
        equal(state.wtf.db.alerts.nightfallSound, "implaugh1")
        equal(state.categories.Alerts, nil, "the list name says who plays it")
        local page = state.categories["Alerts (Dyre's Buff Reminders)"]
        equal(page.headings[1].heading, "The Nightfall sound is now managed by Dyre's Buff Reminders")
        contains(page.headings[1].tooltip, "/dbr")
        equal(#page.initializers, 1, "the page only says who plays it")
        local notice = page.initializers[1]
        equal(notice.setting.name, "Nightfall sound (played by Dyre's Buff Reminders)")
        contains(notice.tooltip, "Dyre's Buff Reminders plays your Nightfall sound")
        contains(notice.tooltip, "/dbr")
        equal(notice.modifyPredicates[1](), false, "greyed out")
        notice.setting:SetValue(false)
        equal(state.wtf.db.alerts.nightfall, true, "the greyed switch changes nothing")
    end
end)
test("with an older or unreadable Dyre's Buff Reminders version WTF still plays Nightfall", function()
    local saved = {chimes = {enabled = false}, alerts = {nightfall = true}}
    for _, version in ipairs({"0.2.0-beta", "0.2.9", "beta", "", false}) do
        local state = fixture({loadedAddOns = {DyresBuffReminders = true},
            addOnVersions = {DyresBuffReminders = version or nil}, db = saved})
        equal(#liveSounds(state), 1, "WTF plays it with DBR " .. tostring(version))
        equal(state.categories["Alerts (Dyre's Buff Reminders)"], nil)
        equal(state.categories.Alerts.initializers[1].setting.variable, "WTF_ALERTS_NIGHTFALL")
    end
    local alone = fixture({addOnVersions = {DyresBuffReminders = "0.3.0-beta"}, db = saved})
    equal(#liveSounds(alone), 1, "a version alone, without DBR loaded, changes nothing")
end)
test("the missing-sounds line leaves out a Nightfall sound that DBR plays", function()
    local state = fixture({noSounds = true, loadedAddOns = {DyresBuffReminders = true},
        addOnVersions = {DyresBuffReminders = "0.3.0-beta"},
        db = {chimes = {enabled = false}, alerts = {nightfall = true}}})
    equal(table.concat(state.messages, "|"):find("Dyre's Sounds", 1, true), nil, "nothing WTF plays wants a sound")
end)
test("the Alerts page has the switch and Dyre's Sounds' aura sounds under it", function()
    local state = fixture()
    local page = state.categories.Alerts
    equal(page.initializers[1].setting.variable, "WTF_ALERTS_NIGHTFALL")
    local dropdown = page.initializers[2]
    equal(dropdown.parentInitializer, page.initializers[1])
    equal(dropdown.soundMenu, "aura", "Dyre's Sounds' nested menu, aura sounds only")
    local labels = {}
    for _, choice in ipairs(dropdown.choices()) do labels[#labels + 1] = choice.label end
    equal(table.concat(labels, ", "), "Dyre's Picks: Fading slow disappear, Dyre's Picks: Disappear blow swoosh, "
        .. "Dyre's Picks: Cartoon vanish, Dyre's Picks: Magical disappear, Dyre's Picks: Slow swoosh, "
        .. "Imp: Laugh 1, Imp: Spell chirp", "no sound kits or Text to Speech")
end)
test("each chime's sound dropdown uses Dyre's Sounds' full menu; WTF builds no menu of its own", function()
    local state = fixture()
    local page = state.categories["Cooldown Chimes"]
    local dropdown = initializerFor(page, "WTF_CHIME_SOUND_DEATHCOIL")
    equal(dropdown.soundMenu, "all", "every sound, also sound kits and Text to Speech")
    equal(dropdown.parentInitializer.setting.variable, "WTF_CHIME_DEATHCOIL", "under its switch")
    local values = {}
    for _, choice in ipairs(dropdown.choices()) do values[#values + 1] = choice.value end
    contains(table.concat(values, ","), "talent,impactspopclick")
    contains(table.concat(values, ","), "voice")
    equal(initializerFor(state.categories["DoT Tracker"], "WTF_TRACKER_THEME").soundMenu, nil,
        "other dropdowns are left alone")
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
    state.focusAnchor = state.env.WarlockToolsForeverTrackerFocus
    state.list = state.env.WarlockToolsForeverTrackerList
    for _, frame in ipairs(state.frames) do
        if (frame.parent == state.anchor or frame.parent == state.focusAnchor) and frame.container then
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
        if (frame.parent == state.anchor or frame.parent == state.focusAnchor) and frame.container
            and frame.unit == unit then found = frame end
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

local function near3(actual, r, g, b, context)
    for index, expected in ipairs({r, g, b}) do
        if math.abs(actual[index] - expected) > 0.002 then
            error((context or "color") .. ": expected " .. r .. "," .. g .. "," .. b .. ", got "
                .. tostring(actual[1]) .. "," .. tostring(actual[2]) .. "," .. tostring(actual[3]), 2)
        end
    end
end

test("the tracker has pinned target and focus rows and eight list rows of engine slots", function()
    local state = trackerFixture()
    equal(state.targetRow.container.unit, "target")
    equal(state.focusRow.container.unit, "focus")
    near3(state.targetRow.backdropBorder, 0x87 / 255, 0x87 / 255, 0xed / 255, "warlock purple")
    equal(state.focusRow.outline.backdrop.edgeSize, 3, "the focus row has the same outline")
    near3(state.focusRow.outline.backdropBorder, 0xe6 / 255, 0x1a / 255, 0x1a / 255, "in red")
    equal(state.focusRow.outline.points[1][2], -5)
    local outline = state.targetRow.outline
    equal(outline.backdrop.edgeSize, 3, "a solid 3-pixel target outline")
    equal(outline.backdrop.edgeFile, "Interface\\Buttons\\WHITE8X8")
    near3(outline.backdropBorder, 0x87 / 255, 0x87 / 255, 0xed / 255)
    equal(outline.points[1][2], -5, "drawn outside the row")
    equal(state.focusRow.points[1][5], nil, "the focus row tops its own section")
    equal(state.focusAnchor.points[#state.focusAnchor.points][5], -(ROW_STEP + TARGET_SPACING),
        "which stacks clear of the target row")
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
    equal(state.drivers[state.focusRow], "[@focus,exists,harm,nodead] show; hide")
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
    equal(casts[3].attributes.macrotext1, "/use [@target,harm,nodead] Corruption")
    equal(casts[4].attributes.macrotext1, "/use [@target,harm,nodead] Immolate")
    equal(casts[5], nil, "no Siphon Life slot: not known")
    equal(casts[2].attributes.macrotext1, "/use [@target,harm,nodead] Curse of Agony",
        "Agony until another Bane is used")
    equal(casts[1].attributes.type1, nil, "no Curse used yet")
    equal(casts[6].attributes.macrotext1, "/use [@target,harm,nodead] Fear")
    equal(state.focusRow.casts[3].attributes.macrotext1, "/use [@focus,exists,harm,nodead] Corruption")
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
    equal(state.targetRow.casts[1].attributes.macrotext1, "/use [@target,harm,nodead] Curse of Weakness")
    dot(state, 980, "Boar")
    equal(state.focusRow.casts[2].attributes.macrotext1, "/use [@focus,exists,harm,nodead] Curse of Agony")
    equal(state.wtf.db.tracker.lastBane, "Curse of Agony")
    local reloaded = trackerFixture({db = {tracker = {lastCurse = "Curse of Weakness"}}})
    equal(reloaded.targetRow.casts[1].attributes.macrotext1, "/use [@target,harm,nodead] Curse of Weakness")
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
    contains(state.messages[5], "slot=corruption recast=Corruption matches=ids ids=172,6222,6223,7648,11671,11672,25311,990002")
    state.emit("UNIT_SPELLCAST_SENT", "player", "Boar", "c1", 702)
    state.emit("UNIT_SPELLCAST_SENT", "player", "Boar", "c2", 990009)
    state.clear()
    state.slash("debug_tracker")
    equal(state.messages[#state.messages - 1], "WTF: debug_tracker lastCast spell=990009 name=nil slot=nil")
    equal(state.last(), "WTF: debug_tracker plates shown=2 readableGUID=2 known=0 targetPlate=none targetGUID=true",
        "then the plates: shown, readable, known, and your target's")
end)
test("a cast lands on the mob it started on, also with same-named mobs and a tab mid-cast", function()
    -- Player feedback: with several Thistle Bears, a dotted bear got no row.
    local state = trackerFixture({units = {
        target = {name = "Thistle Bear", guid = "Creature-5"},
        nameplate5 = {name = "Thistle Bear", guid = "Creature-5"},
        nameplate6 = {name = "Thistle Bear", guid = "Creature-6"},
    }})
    state.emit("UNIT_SPELLCAST_SENT", "player", "Thistle Bear", "cast-imm", 348)
    -- Immolate is still casting: tab to the other bear.
    state.units.target = state.units.nameplate6
    state.emit("PLAYER_TARGET_CHANGED")
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-imm", 348)
    local rows = shownRows(state)
    equal(#rows, 1, "the first bear is listed")
    equal(rows[1].guid, "Creature-5", "the bear the cast started on")
    equal(rows[1].container.unit, "nameplate5")
    -- Now an instant on the new target.
    state.emit("UNIT_SPELLCAST_SENT", "player", "Thistle Bear", "cast-cor", 172)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-cor", 172)
    state.units.target = state.units.nameplate5
    state.emit("PLAYER_TARGET_CHANGED")
    rows = shownRows(state)
    equal(#rows, 1)
    equal(rows[1].guid, "Creature-6", "the second bear, once it is no longer your target")
end)
test("a cast's success drops only its own pending cast", function()
    local state = trackerFixture()
    state.emit("UNIT_SPELLCAST_SENT", "player", "Wolf", "cast-a", 172)
    state.emit("UNIT_SPELLCAST_SENT", "player", "Boar", "cast-b", 348)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-b", 348)
    state.emit("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 172)
    local rows = shownRows(state)
    equal(#rows, 1)
    equal(rows[1].name.text, "Wolf", "the earlier cast still landed")
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
test("a focus gets its pinned row; a list not yet dragged follows the pinned rows", function()
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
    equal(listOffset(state), 0, "with no pinned row the list moves to the top: no gap")
    state.wtf.db.tracker.sections.list = {point = "CENTER", relativePoint = "BOTTOMLEFT", x = 400, y = 300}
    state.units.focus = state.units.nameplate4
    state.emit("PLAYER_FOCUS_CHANGED")
    equal(listOffset(state), 0, "a list you dragged stays where you put it")
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
test("in combat, a mob with no nameplate keeps its row until combat ends", function()
    local state = trackerFixture()
    state.units.nameplate5 = {name = "Bear", guid = "Creature-5"}
    dot(state, 172, "Wolf")
    dot(state, 172, "Bear")
    state.combat = true
    -- Nameplates off (V): every plate goes.
    local wolf, bear = state.units.nameplate4, state.units.nameplate5
    state.units.nameplate4, state.units.nameplate5 = nil, nil
    state.emit("NAME_PLATE_UNIT_REMOVED", "nameplate4")
    state.emit("NAME_PLATE_UNIT_REMOVED", "nameplate5")
    equal(#shownRows(state), 2)
    equal(shownRows(state)[1].container.unit, "none", "no unit: no auras to show")
    state.now = state.now + 60
    state.runTimers()
    equal(#shownRows(state), 2, "both rows stay in combat")
    -- Nameplates on again: each row binds back by its mob.
    state.units.nameplate6, state.units.nameplate7 = bear, wolf
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate6")
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate7")
    local bound = {}
    for _, row in ipairs(shownRows(state)) do bound[row.container.unit] = row.mobName end
    equal(bound.nameplate6, "Bear")
    equal(bound.nameplate7, "Wolf")
    -- A plate out of range, then combat ends: the list clears as before.
    state.units.nameplate6 = nil
    state.emit("NAME_PLATE_UNIT_REMOVED", "nameplate6")
    state.now = state.now + 30
    state.runTimers()
    equal(#shownRows(state), 2, "out of plate range in combat: kept")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(#shownRows(state), 0, "combat ended: cleared")
end)
test("a dotted target you tab away from binds to its nameplate, also when plate GUIDs are secret", function()
    for _, hidden in ipairs({false, true}) do
        local state = trackerFixture({db = {tracker = {health = true}}})
        local ravager = {name = "Young Black Ravager", guid = "Creature-7", secretPlateGUID = hidden,
            health = 300, maxHealth = 1000}
        local blade = {name = "Defias Night Blade", guid = "Creature-8", secretPlateGUID = hidden}
        state.units.nameplate5, state.units.nameplate6 = ravager, blade
        state.emit("NAME_PLATE_UNIT_ADDED", "nameplate5")
        state.emit("NAME_PLATE_UNIT_ADDED", "nameplate6")
        state.units.target = ravager
        state.emit("PLAYER_TARGET_CHANGED")
        state.combat = true
        dot(state, 172, "Young Black Ravager")
        state.units.target = blade
        state.emit("PLAYER_TARGET_CHANGED")
        local rows = shownRows(state)
        local context = hidden and "secret plate GUIDs" or "readable plate GUIDs"
        equal(#rows, 1, context .. ": the Ravager is listed")
        equal(rows[1].mobName, "Young Black Ravager")
        equal(rows[1].container.unit, "nameplate5", context .. ": bound to its own plate, with its timers")
        equal(rows[1].health.shown, true, context .. ": and its health")
        state.units.nameplate5 = nil
        state.emit("NAME_PLATE_UNIT_REMOVED", "nameplate5")
        state.units.nameplate5 = blade
        state.emit("NAME_PLATE_UNIT_ADDED", "nameplate5")
        equal(shownRows(state)[1].container.unit, "none", context .. ": a reused token is not the Ravager's")
    end
end)
test("a target that dies and is cleared never shows as another mob, even for a moment", function()
    local state = trackerFixture()
    dot(state, 172, "Boar")
    equal(#shownRows(state), 0, "your target is not listed")
    local shows = 0
    for _, row in ipairs(listRows(state)) do
        local show = row.Show
        row.Show = function(self) shows = shows + 1; show(self) end
    end
    -- Its plate does not say it is dead (or says it too late); the target does.
    state.units.target.dead = true
    state.emit("UNIT_HEALTH", "target")
    state.units.target = nil
    state.emit("PLAYER_TARGET_CHANGED")
    equal(#shownRows(state), 0, "no Other row")
    equal(shows, 0, "not even for a frame")
    state.units.target = {name = "Boar", guid = "Creature-1"}
    dot(state, 172, "Boar")
    state.units.target = nil
    state.emit("PLAYER_TARGET_CHANGED")
    equal(#shownRows(state), 0, "a late cast on the dead mob does not list it again")
    state.emit("PLAYER_REGEN_ENABLED")
    state.units.target = {name = "Boar", guid = "Creature-1"}
    dot(state, 172, "Boar")
    state.units.target = nil
    state.emit("PLAYER_TARGET_CHANGED")
    equal(#shownRows(state), 1, "after combat the GUID is forgotten")
end)
test("a target whose plate went before it was cleared is not listed until a unit shows it", function()
    local state = trackerFixture()
    dot(state, 172, "Boar")
    local plate = state.units.nameplate3
    state.units.nameplate3 = nil
    state.emit("NAME_PLATE_UNIT_REMOVED", "nameplate3")
    equal(#shownRows(state), 0, "still your target")
    state.units.target = nil
    state.emit("PLAYER_TARGET_CHANGED")
    equal(#shownRows(state), 0, "its plate went with it, most likely dead: not listed")
    state.units.nameplate5 = plate
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate5")
    equal(#shownRows(state), 1, "alive after all: listed once a plate shows it")
    equal(shownRows(state)[1].container.unit, "nameplate5")
end)
test("a mob seen dead as its plate goes leaves the list at once", function()
    local state = trackerFixture()
    dot(state, 172, "Wolf")
    equal(#shownRows(state), 1)
    state.units.nameplate4.dead = true
    state.emit("NAME_PLATE_UNIT_REMOVED", "nameplate4")
    state.units.nameplate4 = nil
    equal(#shownRows(state), 0)
    state.units.mouseover = {name = "Wolf", guid = "Creature-2"}
    dot(state, 172, "Wolf")
    equal(#shownRows(state), 0, "a late cast on it: remembered as dead until combat ends")
end)
test("with Dyre's Toolkit, locked panels take the mouse only while Ctrl is held, out of combat", function()
    local state = trackerFixture({toolkit = true})
    dot(state, 172, "Wolf")
    local target, focus, list = pinnedRow(state, "target"), pinnedRow(state, "focus"), shownRows(state)[1]
    local function mouse()
        return not target.mouseDisabled, not focus.mouseDisabled, not list.mouseDisabled
    end
    equal(state.wtf.db.locked, true)
    equal(select(1, mouse()) or select(2, mouse()) or select(3, mouse()), false, "locked: clicks pass through")
    state.ctrl = true
    state.emit("MODIFIER_STATE_CHANGED", "LCTRL", 1)
    local a, b, c = mouse()
    equal(a and b and c, true, "Ctrl held: every panel takes the mouse")
    target.scripts.OnDragStart(target)
    local call = state.toolkit.calls[#state.toolkit.calls]
    equal(call[1], "BeginDrag")
    equal(call[2], state.anchor, "the toolkit moves the target panel (its free move while locked)")
    state.ctrl = false
    state.emit("MODIFIER_STATE_CHANGED", "LCTRL", 0)
    equal(not target.mouseDisabled, true, "a drag keeps the mouse until its drop")
    target.scripts.OnDragStop(target)
    equal(state.toolkit.calls[#state.toolkit.calls][1], "EndDrag")
    equal(target.mouseDisabled, true, "then clicks pass through again")
    -- Combat starts with Ctrl held: the secure rows let go first.
    state.ctrl = true
    state.emit("MODIFIER_STATE_CHANGED", "LCTRL", 1)
    state.emit("PLAYER_REGEN_DISABLED")
    state.combat = true
    equal(target.mouseDisabled, true, "off as combat starts")
    state.emit("MODIFIER_STATE_CHANGED", "LCTRL", 1)
    equal(target.mouseDisabled, true, "never in combat")
    equal(list.mouseDisabled, true)
end)
test("without Dyre's Toolkit, Ctrl does not change the locked panels", function()
    local state = trackerFixture()
    equal(state.wtf.db.locked, true)
    state.ctrl = true
    state.emit("MODIFIER_STATE_CHANGED", "LCTRL", 1)
    equal(pinnedRow(state, "target").mouseDisabled, true)
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
test("locked tracker rows let clicks through; unlocked they take the mouse to be dragged", function()
    local state = trackerFixture()
    dot(state, 6222, "Wolf")
    local rows = shownRows(state)
    equal(#rows, 1)
    equal(rows[1].mouseDisabled, true, "a list row while locked")
    equal(state.targetRow.mouseDisabled, true, "the target row while locked")
    equal(state.focusRow.mouseDisabled, true)
    state.slash("unlock")
    equal(state.targetRow.mouseDisabled, false, "unlocked: drag by it")
    equal(rows[1].mouseDisabled, false)
    state.slash("lock")
    equal(state.targetRow.mouseDisabled, true)
    equal(rows[1].mouseDisabled, true)
    state.combat = true
    state.slash("unlock")
    equal(state.targetRow.mouseDisabled, true, "a secure row waits for combat to end")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(state.targetRow.mouseDisabled, false)
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
test("each tracker section drags by its rows unless locked, and /wtf reset stacks them again", function()
    local state = trackerFixture({db = {tracker = {position = {point = "CENTER", relativePoint = "BOTTOMLEFT",
        x = 200, y = 300}}}})
    state.slash("unlock")
    state.targetRow.scripts.OnDragStart(state.targetRow)
    equal(state.anchor.moving, true)
    state.anchor:ClearAllPoints()
    state.anchor:SetPoint("CENTER", nil, "BOTTOMLEFT", 300, 600)
    state.targetRow.scripts.OnDragStop(state.targetRow)
    equal(state.wtf.db.tracker.sections.target.x, 300, "the target section saves its own place")
    equal(state.wtf.db.tracker.sections.focus, nil, "the others stay stacked")
    local listRow = shownRows(state)[1]
    listRow.scripts.OnDragStart(listRow)
    equal(state.list.moving, true, "a list row drags the list")
    state.list:ClearAllPoints()
    state.list:SetPoint("CENTER", nil, "BOTTOMLEFT", 700, 200)
    listRow.scripts.OnDragStop(listRow)
    equal(state.wtf.db.tracker.sections.list.x, 700)
    state.focusRow.scripts.OnDragStart(state.focusRow)
    equal(state.focusAnchor.moving, true, "the focus row drags the focus section")
    state.focusRow.scripts.OnDragStop(state.focusRow)
    state.slash("lock")
    state.targetRow.scripts.OnDragStart(state.targetRow)
    equal(state.anchor.moving, false)
    state.slash("reset")
    equal(state.wtf.db.tracker.position, nil)
    equal(next(state.wtf.db.tracker.sections), nil, "every section stacked again")
    equal(state.anchor.points[#state.anchor.points][1], "TOPLEFT")
    equal(state.anchor.points[#state.anchor.points][3], "TOPLEFT", "hanging from the stack")
    state.combat = true
    state.slash("reset")
    equal(state.last(), "WTF: WTF frames move back to their default places after combat.")
end)
test("the three sections stack where the one tracker frame was, so nothing moves", function()
    -- Today's layout: the target row at the frame's top, the focus row one row
    -- and outline below, the list below both.
    for _, saved in ipairs({false, true}) do
        local position = saved and {point = "CENTER", relativePoint = "BOTTOMLEFT", x = 640, y = 420} or nil
        local state = trackerFixture({db = {tracker = {position = position}}})
        local stack = state.anchor.points[#state.anchor.points][2]
        equal(state.anchor.points[#state.anchor.points][5], 0, "the target on top")
        equal(state.focusAnchor.points[#state.focusAnchor.points][2], stack, "the same stack")
        equal(listOffset(state), -(ROW_STEP + TARGET_SPACING), "the list below your target's row")
        local x, y = state.absCenter(stack)
        if saved then
            equal(x, 640, "an old saved tracker place becomes the stack")
            equal(y, 420)
        else
            equal(x, 500 - 260, "the default place")
            equal(y, 400 + 120)
        end
        equal(stack.height, 2 * (ROW_STEP + TARGET_SPACING), "the old frame's height")
    end
end)
test("with Dyre's Toolkit each tracker section is its own movable frame", function()
    local state = trackerFixture({toolkit = true})
    for _, frame in ipairs({state.anchor, state.focusAnchor, state.list}) do
        local found = false
        for _, movable in ipairs(state.toolkit.movables) do
            if movable == frame then found = true end
        end
        equal(found, true, tostring(frame.name))
    end
    state.slash("unlock")
    state.focusRow.scripts.OnDragStart(state.focusRow)
    equal(state.toolkit.calls[#state.toolkit.calls][1], "BeginDrag")
    equal(state.toolkit.calls[#state.toolkit.calls][2], state.focusAnchor)
end)
test("saved section places are repaired on load", function()
    local state = fixture({db = {tracker = {sections = {target = {point = "CENTER", relativePoint = "BOTTOMLEFT",
        x = 1, y = 2}, focus = "broken", list = {x = 3}}}}})
    equal(state.wtf.db.tracker.sections.target.x, 1)
    equal(state.wtf.db.tracker.sections.focus, nil)
    equal(state.wtf.db.tracker.sections.list, nil)
    equal(fixture({db = {tracker = {sections = "x"}}}).wtf.db.tracker.sections.target, nil)
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
    equal(pinnedRow(state, "target").casts[5].attributes.macrotext1, "/use [@target,harm,nodead] Siphon Life")
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
    contains(state.messages[3], "slot=curse recast=nil matches=Curse debuffs except bane")
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

local function barColor(row, index)
    return row.container.slots[index].button.display.bar.barColor
end

-- The DoTs page, refreshed as when it shows, and its row for a slot.
local function dotsPage(state)
    local page = state.categories.DoTs.frame
    page:OnRefresh()
    return page
end

local function dotsRow(page, key)
    for _, row in ipairs(page.rows) do
        if row.key == key then return row end
    end
end

-- The game's color picker: a click on a row's swatch opens it, then the
-- player picks a color (or cancels).
local function pickColor(state, row, r, g, b, cancel)
    local picker = {}
    function picker:SetupColorPickerAndShow(info) self.info = info end
    function picker:GetColorRGB() return r, g, b end
    function picker:GetPreviousValues() return self.info.r, self.info.g, self.info.b end
    state.env.ColorPickerFrame = picker
    row.swatch.scripts.OnClick(row.swatch)
    if cancel then picker.info.cancelFunc() else picker.info.swatchFunc() end
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
    state.combat = true
    local row = dotsRow(dotsPage(state), "corruption")
    pickColor(state, row, 0, 1, 0)
    equal(state.wtf.db.tracker.colors.corruption, "ff00ff00", "the DoTs page's swatch")
    near3(barColor(pinnedRow(state, "focus"), 3), 1, 1, 1, "the engine's bars change only as the rows are built")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    near3(barColor(pinnedRow(state, "focus"), 3), 0, 1, 0, "rebuilt after combat")
    near3(barColor(currentRows(state)[8], 3), 0, 1, 0)
    local bubble
    for _, frame in ipairs(state.frames) do
        if frame.colored and frame.colored.corruption then bubble = frame end
    end
    near3(bubble.colored.corruption.color, 0, 1, 0, "the nameplate dot")
    dotsPage(state)
    near3(row.swatch.color.color, 0, 1, 0, "the swatch shows it")
    pickColor(state, row, 1, 0, 0, true)
    equal(state.wtf.db.tracker.colors.corruption, "ff00ff00", "Cancel puts the old color back")
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
    local fresh = trackerFixture()
    for _, slot in ipairs(fresh.wtf.DOT_SLOTS) do
        equal(fresh.wtf.db.tracker.onPlates[slot.key], true, slot.key .. ": on nameplates by default")
    end
end)
test("the DoT Tracker page: General, then a section per panel with its color and opacity", function()
    local state = trackerFixture()
    local page = state.categories["DoT Tracker"]
    local headings, names = {}, {}
    for _, heading in ipairs(page.headings) do
        if heading.heading then
            headings[#headings + 1] = heading
            names[#names + 1] = heading.heading
        end
    end
    equal(table.concat(names, ","), "General,Target,Focus,Others")
    equal(headings[1].position, 0, "General first")
    equal(page.initializers[1].setting.variable, "WTF_TRACKER_THEME", "the shared settings under General")
    for index, case in ipairs({{"TARGET", "ff8787ed"}, {"FOCUS", "ffe61a1a"}, {"LIST", "ff545454"}}) do
        local at = headings[index + 1].position
        local color, opacity = page.initializers[at + 1], page.initializers[at + 2]
        equal(color.setting.variable, "WTF_PANEL_COLOR_" .. case[1], case[1] .. ": its color in its section")
        equal(color.swatch, true)
        equal(color.setting.default, case[2], case[1] .. ": the color before 1.2.0")
        equal(opacity.setting.variable, "WTF_TRACKER_OPACITY_" .. case[1], case[1] .. ": then its opacity")
        local nextHeading = headings[index + 2]
        equal(nextHeading and nextHeading.position or #page.initializers, at + 2, "nothing else in the section")
    end
    equal(state.categories["DoT Colors"], nil, "no DoT Colors page")
    equal(state.categories["DoT Order"], nil, "no DoT Order page")
end)
test("a panel color recolors its outline, border, and health fill at once, also in combat", function()
    local state = trackerFixture({db = {tracker = {health = true}}})
    dot(state, 6222, "Wolf")
    local list = shownRows(state)[1]
    near3(list.backdropBorder, 0x54 / 255, 0x54 / 255, 0x54 / 255, "the others' border: dark grey, not brown")
    state.combat = true
    state.settings.WTF_PANEL_COLOR_TARGET:SetValue("ff00ff00")
    state.settings.WTF_PANEL_COLOR_FOCUS:SetValue("ff0000ff")
    state.settings.WTF_PANEL_COLOR_LIST:SetValue("ffff0000")
    equal(state.wtf.db.tracker.panelColors.target, "ff00ff00")
    local target, focus = pinnedRow(state, "target"), pinnedRow(state, "focus")
    near3(target.outline.backdropBorder, 0, 1, 0, "the target outline, in combat")
    near3(target.backdropBorder, 0, 1, 0, "and its border")
    near3(target.health.barColor, 0, 1, 0, "and its health fill")
    equal(target.health.barColor[4], 0.8, "the health fill keeps its own opacity")
    near3(focus.outline.backdropBorder, 0, 0, 1, "the focus outline")
    near3(focus.health.barColor, 0, 0, 1)
    near3(list.backdropBorder, 1, 0, 0, "the others' row border")
    near3(list.health.barColor, 1, 0, 0, "and health fill")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    pickColor(state, dotsRow(dotsPage(state), "corruption"), 0, 1, 0)
    dot(state, 6222, "Wolf")
    near3(shownRows(state)[1].backdropBorder, 1, 0, 0, "rows built later take it too")
    near3(pinnedRow(state, "target").outline.backdropBorder, 0, 1, 0)
    state.settings.WTF_PANEL_COLOR_LIST:SetValue("red")
    equal(state.wtf.db.tracker.panelColors.list, "ff545454", "an invalid value becomes the default")
end)
test("saved panel colors are repaired on load", function()
    local state = trackerFixture({db = {tracker = {panelColors = {target = "FF112233", focus = 7}}}})
    equal(state.wtf.db.tracker.panelColors.target, "ff112233")
    equal(state.wtf.db.tracker.panelColors.focus, "ffe61a1a")
    equal(state.wtf.db.tracker.panelColors.list, "ff545454")
    local broken = trackerFixture({db = {tracker = {panelColors = "purple"}}})
    equal(broken.wtf.db.tracker.panelColors.target, "ff8787ed")
end)

-- DoT order -----------------------------------------------------------------------

local function slotKeys(container)
    local keys = {}
    for index, slot in ipairs(container.slots) do keys[index] = slot.key end
    return table.concat(keys, ",")
end

-- The newest nameplate bubble's dots, in order.
local function bubbleKeys(state)
    local newest
    for _, frame in ipairs(state.frames) do
        if frame.colored and frame.container then newest = frame end
    end
    return slotKeys(newest.container)
end

local function orderFixture()
    local state = trackerFixture({db = {tracker = {plateDots = true}}})
    state.combat = true
    state.emit("PLAYER_REGEN_DISABLED")
    state.combat = false
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate4")
    dot(state, 172, "Wolf")
    return state, dotsPage(state)
end

-- Drags a DoTs row and drops it with the cursor at (x, y). The page spans 0
-- to 600 both ways; row 1's top is at 500, each row 30 tall.
local function dragRow(state, page, position, x, y)
    function page:GetLeft() return 0 end
    function page:GetRight() return 600 end
    function page:GetTop() return 600 end
    function page:GetBottom() return 0 end
    for index, row in ipairs(page.rows) do
        function row:GetTop() return 500 - (index - 1) * 30 end
    end
    state.env.GetCursorPosition = function() return x, y end
    local row = page.rows[position]
    row.scripts.OnDragStart(row)
    equal(row.alpha, 0.5, "the dragged row dims")
    row.scripts.OnUpdate(row)
    local shown = page.insert.shown
    row.scripts.OnDragStop(row)
    equal(row.scripts.OnUpdate, nil, "no OnUpdate once the drag stops")
    equal(row.alpha, 1)
    equal(page.insert.shown, false)
    return shown
end

test("the DoT order defaults to the rotation order, and bad saved orders are repaired", function()
    local state = trackerFixture()
    equal(table.concat(state.wtf.db.tracker.order, ","), "curse,bane,corruption,immolate,siphon,control")
    equal(slotKeys(pinnedRow(state, "target").container), "curse,bane,corruption,immolate,control",
        "the rows as before: the DoTs you know, in the default order")
    for _, case in ipairs({
        {{"immolate", "bogus", "immolate", 5, "curse"}, "immolate,curse,bane,corruption,siphon,control",
            "unknown and doubled keys dropped, missing ones added"},
        {"curse", "curse,bane,corruption,immolate,siphon,control", "not a list: the default"},
        {{"control", "siphon", "immolate", "corruption", "bane", "curse"},
            "control,siphon,immolate,corruption,bane,curse", "a whole order stays"},
    }) do
        local repaired = trackerFixture({db = {tracker = {order = case[1]}}})
        equal(table.concat(repaired.wtf.db.tracker.order, ","), case[2], case[3])
    end
end)
test("the DoTs page reorders by drag and drop; rows and nameplate dots follow", function()
    local state, page = orderFixture()
    equal(page.rows[1].key, "curse")
    equal(page.rows[4].key, "immolate")
    equal(page.rows[4].label.text, "Immolate")
    equal(bubbleKeys(state), "curse,bane,corruption,immolate,control", "the dots in the default order")
    equal(dragRow(state, page, 4, 100, 440), true, "a gold line shows the drop place")
    equal(table.concat(state.wtf.db.tracker.order, ","), "curse,bane,immolate,corruption,siphon,control")
    equal(page.rows[3].key, "immolate", "the page shows the new order")
    equal(slotKeys(pinnedRow(state, "target").container), "curse,bane,immolate,corruption,control",
        "the target row")
    equal(slotKeys(pinnedRow(state, "focus").container), "curse,bane,immolate,corruption,control")
    equal(slotKeys(currentRows(state)[1].container), "curse,bane,immolate,corruption,control", "the list rows")
    near3(barColor(pinnedRow(state, "target"), 3), 1, 0x80 / 255, 0x19 / 255, "Immolate's bar third")
    equal(bubbleKeys(state), "curse,bane,immolate,corruption,control", "the nameplate dots")
    dragRow(state, page, 1, 100, 440)
    equal(table.concat(state.wtf.db.tracker.order, ","), "bane,curse,immolate,corruption,siphon,control",
        "dragged down one")
    dragRow(state, page, 3, 100, 410)
    equal(table.concat(state.wtf.db.tracker.order, ","), "bane,curse,immolate,corruption,siphon,control",
        "dropped right under itself: nothing moves")
    equal(dragRow(state, page, 2, -5, 300), false, "outside the page: no line")
    equal(table.concat(state.wtf.db.tracker.order, ","), "bane,curse,immolate,corruption,siphon,control",
        "and a drop there cancels")
    dragRow(state, page, 6, 100, 590)
    equal(state.wtf.db.tracker.order[1], "control", "above the first row: first")
    dragRow(state, page, 1, 100, 10)
    equal(state.wtf.db.tracker.order[6], "control", "below the last row: last")
    page.reset.scripts.OnClick()
    equal(table.concat(state.wtf.db.tracker.order, ","), "curse,bane,corruption,immolate,siphon,control",
        "Reset order")
    equal(slotKeys(pinnedRow(state, "target").container), "curse,bane,corruption,immolate,control")
    dragRow(state, page, 6, 100, 590)
    pickColor(state, dotsRow(page, "bane"), 0, 0, 1)
    dotsRow(page, "immolate").plate:SetChecked(false)
    dotsRow(page, "immolate").plate.scripts.OnClick(dotsRow(page, "immolate").plate)
    page:OnDefault()
    equal(table.concat(state.wtf.db.tracker.order, ","), "curse,bane,corruption,immolate,siphon,control",
        "the Settings panel's Defaults button: the order")
    equal(state.wtf.db.tracker.colors.bane, "ffe62626", "the colors")
    equal(state.wtf.db.tracker.onPlates.immolate, true, "and the nameplate dots")
end)
test("the DoTs page's nameplate switches choose the dots, greyed while the dots are off", function()
    local state, page = orderFixture()
    local immolate = dotsRow(page, "immolate")
    equal(immolate.plate.checked, true)
    equal(immolate.plate.enabled, true, "the dots are on")
    immolate.plate:SetChecked(false)
    immolate.plate.scripts.OnClick(immolate.plate)
    equal(state.wtf.db.tracker.onPlates.immolate, false)
    equal(bubbleKeys(state), "curse,bane,corruption,control", "no Immolate dot")
    state.settings.WTF_TRACKER_PLATE_DOTS:SetValue(false)
    page = dotsPage(state)
    equal(dotsRow(page, "curse").plate.enabled, false, "Show DoT dots on nameplates is off: greyed")
    local tip
    state.env.GameTooltip = {SetOwner = function() end, Show = function() end, Hide = function() end,
        SetText = function(_, text) tip = text end}
    dotsRow(page, "curse").plate.scripts.OnEnter(dotsRow(page, "curse").plate)
    contains(tip, "Turn on Show DoT dots on nameplates", "its tooltip says why")
    equal(state.wtf.db.tracker.onPlates.curse, true, "the choice stays as it is")
end)
test("a DoT order changed in combat reaches the rows when combat ends", function()
    local state, page = orderFixture()
    state.combat = true
    dragRow(state, page, 4, 100, 440)
    equal(table.concat(state.wtf.db.tracker.order, ","), "curse,bane,immolate,corruption,siphon,control")
    equal(slotKeys(pinnedRow(state, "target").container), "curse,bane,corruption,immolate,control",
        "the engine's slots are placed only as the rows are built")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(slotKeys(pinnedRow(state, "target").container), "curse,bane,immolate,corruption,control",
        "rebuilt after combat")
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
    equal(casts[3].attributes.macrotext1, "/use [@target,harm,nodead] Corruption")
    equal(casts[3].points[1][1], "TOPLEFT")
    equal(casts[3].points[1][5], -(18 + 2 * 18), "over the Corruption line")
end)
test("pinned rows and the list are spaced by the taller bar blocks", function()
    local state = barsFixture()
    local step = 18 + 5 * 18 + 6 + 2
    local focusPoint = state.focusAnchor.points[#state.focusAnchor.points]
    equal(focusPoint[5], -(step + TARGET_SPACING))
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
test("a Warlock without Siphon Life and other optional DoTs can learn ranks with no slot error", function()
    -- In client: "aura slot 'siphon' was not found with this key." (x69) when a
    -- spellbook change updated every slot, also ones the rows never had.
    for _, theme in ipairs({"compact", "bars"}) do
        local state = trackerFixture({db = {tracker = {theme = theme}},
            spellbook = {{spellID = 172, name = "Corruption"}, {spellID = 348, name = "Immolate"}}})
        local row = currentRows(state)[1]
        equal(slotByKey(row.container, "siphon"), nil, theme .. ": no Siphon Life slot")
        equal(slotByKey(row.container, "curse"), nil, theme .. ": no Curse slot")
        state.spellbook[#state.spellbook + 1] = {spellID = 990003, name = "Corruption"}
        state.emit("SPELLS_CHANGED")
        equal(slotByKey(currentRows(state)[1].container, "corruption").ids[990003], true, theme .. ": the new rank")
        state.spellbook[#state.spellbook + 1] = {spellID = 990004, name = "Immolate"}
        state.combat = true
        state.emit("SPELLS_CHANGED")
        state.combat = false
        state.emit("PLAYER_REGEN_ENABLED")
        equal(slotByKey(currentRows(state)[1].container, "immolate").ids[990004], true, theme .. ": after combat")
        equal(slotByKey(pinnedRow(state, "target").container, "siphon"), nil)
    end
end)
-- The dim icons behind a row's slots: its desaturated textures.
local function placeholders(row)
    local found = {}
    for _, child in ipairs(row.children) do
        if child.kind == "Texture" and child.desaturated then found[#found + 1] = child end
    end
    return found
end
test("each DoT tracker panel has its own opacity, applied at once, also in combat", function()
    local state = trackerFixture()
    for _, frame in ipairs({state.anchor, state.focusAnchor, state.list}) do
        equal(frame.alpha, 1, tostring(frame.name) .. ": solid by default")
    end
    state.settings.WTF_TRACKER_OPACITY_TARGET:SetValue(60)
    equal(state.anchor.alpha, 0.6, "the target panel")
    equal(state.focusAnchor.alpha, 1, "the others stay")
    state.combat = true
    state.settings.WTF_TRACKER_OPACITY_LIST:SetValue(30)
    equal(state.list.alpha, 0.3, "also in combat")
    state.settings.WTF_TRACKER_OPACITY_FOCUS:SetValue(45)
    equal(state.focusAnchor.alpha, 0.45)
    state.combat = false
    state.settings.WTF_TRACKER_THEME:SetValue("bars")
    equal(state.anchor.alpha, 0.6, "a rebuild keeps it")
    equal(slotByKey(pinnedRow(state, "target").container, "corruption").button.alpha, nil,
        "the engine's buttons are never touched for it")
    local saved = fixture({db = {tracker = {panelOpacity = {target = 5, focus = "x", list = 70}}}})
    equal(saved.wtf.db.tracker.panelOpacity.target, 10)
    equal(saved.wtf.db.tracker.panelOpacity.focus, 100)
    equal(saved.wtf.db.tracker.panelOpacity.list, 70)
    equal(fixture({db = {tracker = {panelOpacity = "broken"}}}).wtf.db.tracker.panelOpacity.target, 100)
end)
test("a panel's opacity reaches its DoT bars as they are built, never touching the engine's objects", function()
    -- Found in client: the engine-driven duration bars did not fade with the
    -- panel's frame, and touching them after they were handed to the engine
    -- raised "Attempt to access forbidden object" (the mock raises too).
    for _, theme in ipairs({"compact", "bars"}) do
        local state = trackerFixture({db = {tracker = {theme = theme}}})
        dot(state, 6222, "Wolf")
        local bar = barColor(pinnedRow(state, "target"), 3)
        equal(bar[4], 1, theme .. ": solid by default")
        equal(pinnedRow(state, "target").container.slots[3].button.display.bar.ignoreParentAlpha, true,
            theme .. ": a bar ignores its parent's opacity")
        for _, case in ipairs({{"TARGET", "target"}, {"FOCUS", "focus"}, {"LIST", "list"}}) do
            local function row()
                return case[2] == "list" and shownRows(state)[1] or pinnedRow(state, case[2])
            end
            local section = case[2] == "target" and state.anchor or case[2] == "focus" and state.focusAnchor
                or state.list
            state.settings["WTF_TRACKER_OPACITY_" .. case[1]]:SetValue(40)
            equal(section.alpha, 0.4, theme .. " " .. case[2] .. ": the panel at once")
            equal(barColor(row(), 3)[4], 0.4, theme .. " " .. case[2] .. ": its DoT bars, rebuilt")
            if theme == "bars" then
                equal(row().container.slots[3].button.display.spellName.alpha, 0.4, "the spell name on a bar")
                equal(row().container.slots[3].button.display.text.alpha, 0.4, "and its time left")
            end
            state.combat = true
            state.settings["WTF_TRACKER_OPACITY_" .. case[1]]:SetValue(70)
            equal(section.alpha, 0.7, theme .. " " .. case[2] .. ": the panel at once, in combat")
            equal(barColor(row(), 3)[4], 0.4, theme .. " " .. case[2] .. ": its bars wait for combat to end")
            state.combat = false
            state.emit("PLAYER_REGEN_ENABLED")
            dot(state, 6222, "Wolf")
            equal(barColor(row(), 3)[4], 0.7, theme .. " " .. case[2] .. ": then follow")
        end
        equal(barColor(pinnedRow(state, "focus"), 1)[4], 0.7, theme .. ": each panel keeps its own")
    end
end)
test("the DoT tracker rows stay fully solid: the opacity is the nameplate dots'", function()
    local state = trackerFixture()
    local row = pinnedRow(state, "target")
    equal(slotByKey(row.container, "corruption").button.alpha, nil, "the engine's buttons are left alone")
    equal(placeholders(row)[1].alpha, 0.3, "the dim icons as before")
    equal(state.settings.WTF_TRACKER_OPACITY, nil, "no tracker opacity setting")
end)
-- The tracker's size settings ---------------------------------------------------

local function settingsPage(state, name)
    return state.categories[name]
end
test("tracker sizes default to today's look, per theme", function()
    local compact = trackerFixture()
    local row = pinnedRow(compact, "target")
    local slots = #row.container.slots
    equal(row.width, 6 * 2 + 110 + slots * (22 + 6), "compact width as before")
    equal(row.height, 30, "compact height as before")
    equal(slotByKey(row.container, "corruption").button.width, 22)
    local bars = trackerFixture({db = {tracker = {theme = "bars"}}})
    equal(pinnedRow(bars, "target").width, 290, "bars width as before")
    equal(slotByKey(pinnedRow(bars, "target").container, "corruption").button.height, 16)
    equal(compact.wtf.db.tracker.sizes.compact.namePosition, "left")
    equal(compact.wtf.db.tracker.sizes.bars.namePosition, "above")
end)
test("compact sizes: icon size, name width, and the name beside, above, or below", function()
    local state = trackerFixture()
    local slots = #pinnedRow(state, "target").container.slots
    state.settings.WTF_TRACKER_COMPACT_ICONSIZE:SetValue(30)
    state.settings.WTF_TRACKER_COMPACT_NAMEWIDTH:SetValue(150)
    local row = pinnedRow(state, "target")
    equal(row.height, 30 + 8)
    equal(row.width, 12 + 150 + slots * (30 + 6))
    local button = slotByKey(row.container, "corruption").button
    equal(button.width, 30)
    local firstSlot = row.container.slots[1].button
    equal(firstSlot.points[#firstSlot.points][4], 6 + 150, "the first icon after the name")
    state.settings.WTF_TRACKER_COMPACT_NAMEPOSITION:SetValue("above")
    row = pinnedRow(state, "target")
    equal(row.height, 30 + 8 + 14, "a name line above the icons")
    equal(row.width, 12 + math.max(150, slots * 36))
    equal(row.name.points[#row.name.points][1], "TOPLEFT")
    local first = row.container.slots[1].button
    equal(first.points[#first.points][4], 6, "icons start at the left edge")
    equal(first.points[#first.points][5], -(4 + 14), "below the name line")
    state.settings.WTF_TRACKER_COMPACT_NAMEPOSITION:SetValue("right")
    row = pinnedRow(state, "target")
    equal(row.name.points[#row.name.points][2], 6 + slots * 36, "the name after the icons")
    state.settings.WTF_TRACKER_COMPACT_NAMEPOSITION:SetValue("below")
    row = pinnedRow(state, "target")
    equal(row.name.points[#row.name.points][1], "BOTTOMLEFT")
    equal(state.focusAnchor.points[#state.focusAnchor.points][5], -(row.height + 2 + 7),
        "the stacked focus section follows the new size")
end)
test("bars sizes: width, line height, and the name above or below", function()
    local state = trackerFixture({db = {tracker = {theme = "bars"}}})
    state.settings.WTF_TRACKER_BARS_BARWIDTH:SetValue(400)
    state.settings.WTF_TRACKER_BARS_LINEHEIGHT:SetValue(20)
    local row = pinnedRow(state, "target")
    local lines = #row.container.slots
    equal(row.width, 400)
    equal(row.height, 18 + lines * (20 + 2) + 6)
    local button = slotByKey(row.container, "corruption").button
    equal(button.height, 20)
    equal(button.width, 400 - 12)
    state.settings.WTF_TRACKER_BARS_NAMEPOSITION:SetValue("below")
    row = pinnedRow(state, "target")
    local first = row.container.slots[1].button
    equal(first.points[#first.points][5], -4, "the lines start at the top")
    equal(row.name.points[#row.name.points][1], "BOTTOMLEFT")
    equal(state.wtf.db.tracker.sizes.compact.iconSize, 22, "the other theme keeps its own sizes")
end)
test("text size scales every tracker font", function()
    local state = trackerFixture()
    state.settings.WTF_TRACKER_COMPACT_TEXTSCALE:SetValue(150)
    local row = pinnedRow(state, "target")
    equal(row.name.fontSize, 15, "the name")
    local bars = trackerFixture({db = {tracker = {theme = "bars", sizes = {bars = {textScale = 50}}}}})
    equal(pinnedRow(bars, "target").name.fontSize, 5)
    equal(pinnedRow(bars, "target").height, 9 + #pinnedRow(bars, "target").container.slots * 18 + 6,
        "a smaller name line")
end)
test("a size change in combat waits; Reset size restores the theme's own sizes", function()
    local state = trackerFixture()
    state.combat = true
    state.settings.WTF_TRACKER_COMPACT_ICONSIZE:SetValue(36)
    equal(pinnedRow(state, "target").height, 30, "the rows rebuild only out of combat")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(pinnedRow(state, "target").height, 44)
    local page = settingsPage(state, "DoT Tracker")
    local reset
    for _, heading in ipairs(page.headings) do
        if heading.buttonText == "Reset size" then reset = heading end
    end
    reset.buttonClick()
    equal(pinnedRow(state, "target").height, 30)
    equal(state.wtf.db.tracker.sizes.compact.iconSize, 22)
end)
test("tracker names stay on one line in their room, and rows never grow from a long name", function()
    -- Found in client: long Compact names wrapped onto 2-3 lines and spilled out of the row.
    local long = "Sleepless Soulgorger Champion of Nightfal"
    equal(#long, 41)
    local layouts = {{"compact", "left"}, {"compact", "right"}, {"compact", "above"}, {"compact", "below"},
        {"bars", "above"}, {"bars", "below"}}
    for _, layout in ipairs(layouts) do
        for _, scale in ipairs({50, 100, 200}) do
            for _, healthText in ipairs({"none", "both"}) do
                local theme, where = layout[1], layout[2]
                local label = theme .. " " .. where .. " " .. scale .. "% " .. healthText
                local sizes = {textScale = scale, namePosition = where}
                local state = trackerFixture({units = {
                    target = {name = long, guid = "Creature-1"},
                    nameplate3 = {name = long, guid = "Creature-1"},
                    nameplate4 = {name = "Wolf", guid = "Creature-2"},
                }, db = {tracker = {theme = theme, sizes = {[theme] = sizes}, health = healthText ~= "none",
                    healthText = healthText}}})
                state.slash("unlock")
                local rows = {pinnedRow(state, "target")}
                for _, row in ipairs(shownRows(state)) do rows[#rows + 1] = row end
                local width, height = rows[1].width, rows[1].height
                for _, row in ipairs(rows) do
                    equal(row.name.wordWrap, false, label .. ": one line")
                    equal(row.name.maxLines, 1, label)
                    equal(row.width, width, label .. ": every row the same width, whatever its name")
                    equal(row.height, height, label .. ": and height")
                    for _, text in ipairs({row.healthPercent, row.healthNumber}) do
                        equal(text.wordWrap, false, label .. ": the health text is one line too")
                    end
                end
                local name = rows[1].name
                local reserve = healthText == "both" and math.floor(70 * scale / 100 + 0.5) or 0
                if theme == "compact" and (where == "left" or where == "right") then
                    equal(name.width, 110 - 4 - reserve, label .. ": the column beside the icons")
                else
                    equal(name.width, width - 12 - reserve, label .. ": the row's whole width")
                end
                state.slash("lock")
                state.applyDrivers()
                equal(pinnedRow(state, "target").name.text, long, label .. ": a long target name")
                equal(pinnedRow(state, "target").width, width, label .. ": the row does not grow for it")
            end
        end
    end
end)
test("only the chosen theme's size settings show", function()
    local state = trackerFixture()
    local page = settingsPage(state, "DoT Tracker")
    local function shown(variable)
        for _, initializer in ipairs(page.initializers) do
            if initializer.setting.variable == variable then
                for _, predicate in ipairs(initializer.shownPredicates) do
                    if not predicate() then return false end
                end
                return true
            end
        end
    end
    equal(shown("WTF_TRACKER_COMPACT_ICONSIZE"), true)
    equal(shown("WTF_TRACKER_BARS_BARWIDTH"), false)
    state.settings.WTF_TRACKER_THEME:SetValue("bars")
    equal(shown("WTF_TRACKER_COMPACT_ICONSIZE"), false)
    equal(shown("WTF_TRACKER_BARS_LINEHEIGHT"), true)
    equal(shown("WTF_TRACKER_BARS_NAMEPOSITION"), true)
end)
test("saved tracker sizes are repaired on load", function()
    local state = fixture({db = {tracker = {sizes = {compact = {iconSize = 99, nameWidth = "x", namePosition = "middle"},
        bars = "broken"}}}})
    local sizes = state.wtf.db.tracker.sizes
    equal(sizes.compact.iconSize, 40)
    equal(sizes.compact.nameWidth, 110)
    equal(sizes.compact.namePosition, "left")
    equal(sizes.bars.barWidth, 290)
    equal(sizes.bars.namePosition, "above")
    state.settings.WTF_TRACKER_BARS_NAMEPOSITION:SetValue("left")
    equal(sizes.bars.namePosition, "above", "Bars has no name beside the lines")
end)
-- Mob health in the tracker --------------------------------------------------------

local function healthFixture(text, extra)
    local options = {db = {tracker = {health = true, healthText = text}}}
    for key, value in pairs(extra or {}) do options[key] = value end
    local state = trackerFixture(options)
    state.units.target.health, state.units.target.maxHealth = 500, 2000
    state.emit("UNIT_HEALTH", "target")
    return state
end
test("mob health: a Compact name on the right fills only its column, after the icons", function()
    local state = healthFixture("none")
    state.settings.WTF_TRACKER_COMPACT_NAMEPOSITION:SetValue("right")
    local row = pinnedRow(state, "target")
    local slots = row.container.slots
    local last = slots[#slots].button
    equal(row.health.points[1][1], "TOPLEFT")
    equal(row.health.points[1][4], last.points[1][4] + last.width + 2, "starts a small gap after the last icon")
    equal(row.health.points[1][5], -3, "inside the border")
    equal(row.health.points[2][1], "BOTTOMRIGHT")
    equal(row.health.points[2][3], "BOTTOMRIGHT", "to the row's inner right edge")
    equal(row.health.points[2][4], -3)
end)
test("mob health is off by default", function()
    local state = trackerFixture()
    equal(state.wtf.db.tracker.health, false)
    equal(state.wtf.db.tracker.healthText, "none")
    equal(pinnedRow(state, "target").health, nil)
end)
test("mob health: the name line is the health bar, with the number, percent, or both after the name", function()
    local state = healthFixture("none")
    local row = pinnedRow(state, "target")
    equal(row.health.shown, true)
    equal(row.health.points[1][1], "TOPLEFT", "a Compact name beside the icons: only the name's column")
    equal(row.health.points[1][4], 3, "inside the border")
    equal(row.health.points[1][5], -3)
    equal(row.health.points[2][1], "BOTTOMRIGHT")
    equal(row.health.points[2][3], "BOTTOMLEFT", "measured from the row's left edge")
    equal(row.health.points[2][4], 6 + 110 - 2, "up to the first icon, less a small gap")
    equal(row.health.points[2][5], 3)
    local firstIcon = row.container.slots[1].button.points[1]
    equal(firstIcon[4], 6 + 110, "the first icon starts just after the fill")
    equal(row.height, 30, "the row keeps its size")
    equal(row.name.parent, row.layer, "the name draws above the bar")
    equal(row.layer.level, row.health.level + 1)
    equal(row.container.level, row.health.level + 2, "the DoT icons above both")
    near3(row.health.barColor, 0x87 / 255, 0x87 / 255, 0xed / 255, "purple for your target")
    equal(row.health.barColor[4], 0.8)
    near3(pinnedRow(state, "focus").health.barColor, 0xe6 / 255, 0x1a / 255, 0x1a / 255, "red for your focus")
    dot(state, 6222, "Wolf")
    near3(shownRows(state)[1].health.barColor, 0x54 / 255, 0x54 / 255, 0x54 / 255, "dark grey for the others")
    state.settings.WTF_TRACKER_COMPACT_NAMEPOSITION:SetValue("above")
    row = pinnedRow(state, "target")
    equal(row.health.points[1][1], "TOPLEFT", "a name above the icons: its own line")
    equal(row.health.height, 14 + 2)
    equal(row.health.points[2][1], "TOPRIGHT")
    equal(row.health.points[2][4], -6)
    state.settings.WTF_TRACKER_COMPACT_NAMEPOSITION:SetValue("left")
    row = pinnedRow(state, "target")
    equal(row.health.maxValue, 2000)
    equal(row.health.value, 500)
    equal(row.healthPercent, nil, "no text")
    equal(row.name.width, 110 - 4, "the name keeps its room")
    local percent = pinnedRow(healthFixture("percent"), "target")
    equal(percent.healthPercent.text, "25%")
    equal(percent.healthNumber, nil)
    equal(percent.name.width, 110 - 4 - 30, "the text takes the end of the name's room")
    local number = pinnedRow(healthFixture("number"), "target")
    equal(number.healthNumber.text.abbreviated, 500)
    local both = healthFixture("both")
    local row2 = pinnedRow(both, "target")
    equal(row2.healthPercent.text, "25% |")
    equal(row2.healthNumber.text.abbreviated, 500)
    equal(row2.healthNumber.points[1][2], row2.healthPercent, "the number after the percent")
    both.units.target.health = 1500
    both.emit("UNIT_HEALTH", "target")
    equal(row2.health.value, 1500, "follows the mob's health")
    equal(row2.healthPercent.text, "75% |")
end)
test("in Bars the name line is the health bar, as wide as the DoT bars", function()
    local state = healthFixture("none", {db = {tracker = {theme = "bars", health = true, healthText = "none"}}})
    local row = pinnedRow(state, "target")
    local line = slotByKey(row.container, "corruption").button
    equal(line.width, row.width - 12, "a DoT bar's width")
    equal(row.health.points[1][1], "TOPLEFT", "the name line at the top")
    equal(row.health.points[1][4], 6, "the same left inset")
    equal(row.health.points[2][4], -6, "and right inset")
    equal(row.health.height, 18 - 2)
    equal(row.height, 18 + #row.container.slots * 18 + 6, "the row keeps its size")
    state.settings.WTF_TRACKER_BARS_NAMEPOSITION:SetValue("below")
    row = pinnedRow(state, "target")
    equal(row.health.points[1][1], "BOTTOMLEFT", "below: the name line at the bottom")
end)
test("in combat mob health is secret: WTF hands it on and never reads it", function()
    local state = healthFixture("both")
    state.combat = true
    state.emit("UNIT_HEALTH", "target")
    local row = pinnedRow(state, "target")
    equal(state.secrets[row.health.value], true, "the bar got the secret health")
    equal(state.secrets[row.health.maxValue], true)
    equal(state.secrets[row.healthPercent.text], true, "the percent text is the client's secret string")
    equal(state.formatted.pattern, "%d%% |")
    equal(state.secrets[row.healthNumber.text.abbreviated], true)
end)
test("list rows show their mob's health while bound, and hide it without a unit", function()
    local state = healthFixture("percent")
    state.units.nameplate4.health, state.units.nameplate4.maxHealth = 300, 600
    dot(state, 6222, "Wolf")
    local row = shownRows(state)[1]
    equal(row.health.shown, true)
    equal(row.health.value, 300)
    equal(row.healthPercent.text, "50%")
    state.units.nameplate4.health = 150
    state.emit("UNIT_HEALTH", "nameplate4")
    equal(row.healthPercent.text, "25%")
    state.units.nameplate4 = nil
    state.emit("NAME_PLATE_UNIT_REMOVED", "nameplate4")
    equal(row.health.shown, false, "no unit: no health")
    equal(row.healthPercent.text, "")
end)
test("without UnitHealthPercent the percent text stays empty", function()
    local state = healthFixture("percent", {noHealthPercent = true})
    equal(pinnedRow(state, "target").healthPercent.text, "")
    equal(pinnedRow(state, "target").health.value, 500, "the bar still works")
end)
test("health settings rebuild the rows out of combat and are repaired on load", function()
    local state = trackerFixture()
    state.combat = true
    state.settings.WTF_TRACKER_HEALTH:SetValue(true)
    equal(pinnedRow(state, "target").health, nil, "waits for combat to end")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(pinnedRow(state, "target").health ~= nil, true)
    state.settings.WTF_TRACKER_HEALTH_TEXT:SetValue("both")
    equal(pinnedRow(state, "target").healthNumber ~= nil, true)
    local repaired = fixture({db = {tracker = {health = "yes", healthText = "all"}}})
    equal(repaired.wtf.db.tracker.health, false)
    equal(repaired.wtf.db.tracker.healthText, "none")
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

test("nameplate dot opacity: solid by default, applied at once, also in combat, repaired on load", function()
    local state = dotsFixture()
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate1")
    local bubble = bubbleOn(state, "nameplate1")
    equal(state.wtf.db.tracker.plateDotsOpacity, 100)
    equal(bubble.alpha, 1, "solid by default")
    state.combat = true
    state.settings.WTF_TRACKER_PLATE_DOTS_OPACITY:SetValue(40)
    equal(bubble.alpha, 0.4, "the whole bubble, at once, also in combat")
    state.combat = false
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate2")
    equal(bubbleOn(state, "nameplate2").alpha, 0.4, "a new bubble takes it too")
    for _, case in ipairs({{5, 10}, {300, 100}, {"x", 100}, {65, 65}}) do
        local saved = fixture({db = {tracker = {plateDotsOpacity = case[1]}}})
        equal(saved.wtf.db.tracker.plateDotsOpacity, case[2], "saved " .. tostring(case[1]))
    end
end)

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
    equal(table.concat(keys, ","), "corruption,control", "no Immolate by choice; Fear on by default")
    local cursed = dotsFixture()
    local curseDot = containerIn(bubbleOn(cursed, "nameplate1")).slots[1]
    equal(curseDot.key, "curse")
    equal(curseDot.candidates.includeDispelTypes.Curse, true, "the dot uses the same Curse match")
    local row = dotsRow(dotsPage(state), "control")
    row.plate:SetChecked(false)
    row.plate.scripts.OnClick(row.plate)
    keys = {}
    for index, slot in ipairs(containerIn(bubbleOn(state, "nameplate1")).slots) do keys[index] = slot.key end
    equal(table.concat(keys, ","), "corruption", "the DoTs page's switch")
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
