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

-- Dyre's Toolkit's shared files and engines (2.5.0): every fixture loads them onto its
-- DyresToolkit table, as the client loads the Toolkit before WTF. From the
-- real Dyre's Toolkit beside this repository when it is there; else (as in
-- CI, which has only this repository, or with WTF_TOOLKIT_COPY=1) from the
-- copy in tests/toolkit.
local TOOLKIT_FILES = {"Auras.lua", "Units.lua", "HealthBars.lua", "Spells.lua", "Macros.lua", "Announce.lua",
    "ClassData.lua", "Owners.lua", "Control.lua", "DotTracker.lua", "PlateDots.lua", "DotPredict.lua"}
local TOOLKIT_DIR = "tests/toolkit/"
if os.getenv("WTF_TOOLKIT_COPY") ~= "1" then
    local probe = io.open("../DyresToolkit/Units.lua", "rb")
    if probe then
        probe:close()
        TOOLKIT_DIR = "../DyresToolkit/"
    end
end
print("Dyre's Toolkit from " .. TOOLKIT_DIR)
local RUNTIME_FILES = {"Commands.lua", "Core.lua", "Layout.lua", "Shards.lua", "Stones.lua", "Announce.lua",
    "Probe.lua", "Options.lua"}
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
    -- options.era: readable mob health, also in combat, as on Classic Era
    -- (found in client: 328, 328); a unit with secretHealth is secret anyway.
    local function mobHealth(unit, field, default)
        local data = state.units[unit]
        local value = data and data[field] or default
        if (state.combat and unit ~= "player" and not options.era) or (data and data.secretHealth) then
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
    -- options.familyAddOns: other Dyre's AddOns ({DyresDebuffTracker = true}),
    -- whose TOC Group the Toolkit reads for a damage source.
    env.C_AddOns = {GetAddOnMetadata = function(name, field)
        if name ~= "WarlockToolsForever" and field == "Group" then
            return (options.familyAddOns or {})[name] and "DyresToolkit" or nil
        end
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
        local initializer = {name = name, buttonText = buttonText, buttonClick = buttonClick, tooltip = tooltip,
            shownPredicates = {}}
        if not options.linkNoShown then
            function initializer:AddShownPredicate(predicate)
                self.shownPredicates[#self.shownPredicates + 1] = predicate
            end
        end
        return initializer
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
    -- options.installedAddOns: installed but not loaded, as {DyresShieldsUp = "DISABLED"}.
    env.C_AddOns.GetAddOnInfo = function(name)
        local reason = (options.installedAddOns or {})[name]
        if reason then return name, name, "", false, reason end
        return name, nil, nil, false, "MISSING"
    end
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
            elseif driver == "show" or driver == "hide" then
                frame.shown = driver == "show"
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
        -- Toolkit 2.3.0: a button that opens another AddOn's settings.
        toolkit.links = {}
        function toolkit.AddSettingsLink(category, layout, opts)
            local initializer = {name = opts.name, buttonText = opts.button, tooltip = opts.tooltip,
                shownPredicates = {}}
            if not options.linkNoShown then
                function initializer:AddShownPredicate(predicate)
                    self.shownPredicates[#self.shownPredicates + 1] = predicate
                end
            end
            toolkit.links[#toolkit.links + 1] = {category = category, opts = opts, initializer = initializer}
            layout:AddInitializer(initializer)
            return initializer
        end
        -- The AddOns that joined the toolkit; options.members adds others.
        function toolkit.AddOns()
            local list = {}
            if toolkit.info then list[#list + 1] = toolkit.info end
            for _, member in ipairs(options.members or {}) do list[#list + 1] = member end
            return list
        end
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
                -- Era's plate health bar (Blizzard_NamePlates.xml).
                if options.era then
                    local unitFrame = env.CreateFrame("Button", nil, state.plates[unit])
                    unitFrame.HealthBarsContainer = {healthBar = env.CreateFrame("StatusBar", nil, unitFrame)}
                    state.plates[unit].UnitFrame = unitFrame
                end
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
        function object:SetFrameStrata(value) self.strata = value end
        function object:GetFrameStrata() return self.strata or "MEDIUM" end
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
        function object:SetTexture(texture, wrapH, wrapV) self.texture, self.atlas, self.wrap = texture, nil, wrapH end
        function object:GetTexture() return self.texture end
        function object:SetAtlas(atlas) self.atlas, self.texture = atlas, nil end
        function object:GetAtlas() return self.atlas end
        function object:SetVertexColor(...) self.vertex = {...} end
        function object:SetHorizTile(value) self.horizTile = value end
        function object:SetVertTile(value) self.vertTile = value end
        function object:GetStatusBarColor() if self.barColor then return unpack(self.barColor) end end
        function object:GetChildren() return unpack(self.children) end
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
            -- About as wide as the client draws it.
            function text:GetStringWidth() return #(self.text or "") * self.fontSize * 0.6 end
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

    -- options.era: the combat log, as on Classic Era (state.log fires one
    -- event), the target frame's health bar, and spell power by school.
    -- options.combatLogRestricted: IsCombatLogRestricted is true, as on Forever.
    state.combatLogRestricted = options.combatLogRestricted
    state.spellPower = {}
    env.GetSpellBonusDamage = function(school) return state.spellPower[school] or 0 end
    if options.era then
        env.C_CombatLog = env.C_CombatLog or {}
        env.C_CombatLog.GetCurrentEventInfo = function() return unpack(state.combatLogEvent) end
        env.TargetFrame = {healthbar = env.CreateFrame("StatusBar", "TargetFrameHealthBar")}
    end
    for _, name in ipairs(options.remove or {}) do env[name] = nil end
    -- options.classicSpellBook: Classic Era and Anniversary's spellbook API,
    -- with no C_SpellBook skill lines or item info, and the legacy
    -- GetSpellBookItemName(index, "pet"). options.petSpellbook: your demon's.
    -- Its IsSpellKnown takes only a SpellBookSpellBank enum, as Classic Era's
    -- (player report: "bad argument #2 to 'IsSpellKnown'" for `true`).
    -- options.noSpellBank: no Enum.SpellBookSpellBank, only the legacy
    -- IsSpellKnown(spellID, isPet).
    state.petSpellbook = options.petSpellbook or state.petSpellbook
    if options.classicSpellBook then
        env.C_SpellBook.IsSpellKnown = function(id, bank)
            if bank ~= nil and bank ~= 0 and bank ~= 1 then
                error("bad argument #2 to 'IsSpellKnown' (Usage: local isKnown = "
                    .. "C_SpellBook.IsSpellKnown(spellID [, spellBank]))")
            end
            if bank == 1 then return (state.petKnown or {})[id] == true end
            return state.known[id] == true
        end
        env.C_SpellBook.GetNumSpellBookSkillLines = nil
        env.C_SpellBook.GetSpellBookSkillLineInfo = nil
        env.C_SpellBook.GetSpellBookItemInfo = nil
        env.GetSpellBookItemName = function(index, book)
            local item = book == "pet" and (state.petSpellbook or {})[index]
            if item then return item.name, "", item.spellID end
        end
    end
    if options.noSpellBank then
        env.Enum.SpellBookSpellBank = nil
        env.IsSpellKnown = function(id, isPet)
            if isPet then return (state.petKnown or {})[id] == true end
            return state.known[id] == true
        end
    end
    -- The Toolkit's shared files and engines (2.5.0) on env.DyresToolkit: the fake toolkit
    -- (options.toolkit), else a table with only them (no RequireContract, so
    -- WTF's layout still finds no toolkit). options.noSharedToolkit: an
    -- older Toolkit, without them. options.toolkitDB: DyresToolkitDB.
    state.toolkitDB = options.toolkitDB or {}
    -- The Toolkit's own frames (its PLAYER_FOCUS_CHANGED learner, the aura
    -- dispatcher), which are not WTF's.
    state.sharedFrames = {}
    local before = #state.frames
    if not options.noSharedToolkit then
        local shared = env.DyresToolkit or {}
        env.DyresToolkit = shared
        state.shared = shared
        -- One namespace for every file, as the client gives an AddOn's files.
        local toolkitNS = {toolkit = shared, db = state.toolkitDB, Report = function(message)
            state.messages[#state.messages + 1] = "Dyre: " .. tostring(message)
        end}
        for _, name in ipairs(TOOLKIT_FILES) do
            local chunk, message = loadfile(TOOLKIT_DIR .. name)
            if not chunk then error(message) end
            setfenv(chunk, env)
            chunk("DyresToolkit", toolkitNS)
        end
        -- options.profiles: the Toolkit's profile engine (Profiles.lua, 2.10.0)
        -- on the same table, with this character "Dyre - Forever".
        if options.profiles then
            state.units.player = state.units.player or {name = "Dyre"}
            env.GetRealmName = env.GetRealmName or function() return "Forever" end
            env.StaticPopupDialogs = env.StaticPopupDialogs or {}
            local chunk, message = loadfile(TOOLKIT_DIR .. "Profiles.lua")
            if not chunk then error(message) end
            setfenv(chunk, env)
            chunk("DyresToolkit", toolkitNS)
            state.toolkitNS = toolkitNS
        end
        -- options.nightfallOwner: the owner of the Toolkit kind "proc:nightfall"
        -- (false: no claim), read live from state.nightfallOwner.
        if options.nightfallOwner ~= nil then
            state.nightfallOwner = options.nightfallOwner or nil
            shared.PROC_KIND_PREFIX = shared.PROC_KIND_PREFIX or "proc:"
            local kindOwner = shared.KindOwner
            shared.KindOwner = function(kind)
                if kind == "proc:nightfall" then return state.nightfallOwner end
                return kindOwner and kindOwner(kind) or nil
            end
        end
        -- options.procPrefix: the Toolkit's proc kinds (2.11), with its real owners.
        if options.procPrefix then shared.PROC_KIND_PREFIX = shared.PROC_KIND_PREFIX or "proc:" end
        -- options.sharedMissing: a function an older Toolkit lacks.
        if options.sharedMissing then shared[options.sharedMissing] = nil end
        -- options.noHiddenTicks: no predictor where the combat log is restricted.
        if options.noHiddenTicks then shared.HiddenTicksUsable = function() return false end end
        -- options.noSmartCurse: a DoT tracker before Toolkit 2.7 (no smart curse).
        if options.noSmartCurse then
            local create = shared.CreateDotTracker
            shared.CreateDotTracker = function(spec)
                local made, why = create(spec)
                if made then made.ApplySmartCurse, made.SmartCurseBody = nil, nil end
                return made, why
            end
        end
    end
    for index = before + 1, #state.frames do
        state.sharedFrames[state.frames[index]] = true
    end
    state.wtf = {}
    for _, path in ipairs(options.files or RUNTIME_FILES) do
        local chunk, message = loadfile(path)
        if not chunk then error(message) end
        setfenv(chunk, env)
        chunk("WarlockToolsForever", state.wtf)
    end
    -- A client whose focus works, as Forever, unless options.focusWorks is
    -- false (Classic Era: the macros fall back and rows take no clicks).
    -- options.accountDB: the account-wide saved table, as another character left it.
    local accountDB = options.accountDB
    if accountDB == nil and options.focusWorks ~= false then
        accountDB = {focusWorks = true}
    end
    env.WarlockToolsForeverAccountDB = accountDB
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
    -- One combat log event: the 11 common fields (as in client; the time and
    -- flags unused), then spellID, name, school, and amount.
    function state.log(subevent, sourceGUID, destGUID, destName, spellID, spellName, amount)
        state.combatLogEvent = {state.now, subevent, false, sourceGUID, "Dyre", 0, 0, destGUID, destName, 0, 0,
            spellID, spellName, 32, amount}
        state.emit("COMBAT_LOG_EVENT_UNFILTERED")
    end
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
test("debug_shards says whether the shard counter was made, shown, and where (Classic report)", function()
    -- As on Classic Era and Anniversary: no aura engine, no skill-line spellbook API.
    local state = fixture({noAuraContainer = true})
    state.env.C_SpellBook.GetNumSpellBookSkillLines = nil
    state.clear()
    state.slash("debug_shards")
    local all = table.concat(state.messages, "\n")
    contains(all, "debug_shards counter setting=true shown=true visible=true point=CENTER BOTTOMLEFT 550 336")
    local counter = state.wtf.shardCounter
    equal(counter.points[#counter.points][4], 1000 * 0.55, "55% across the screen, at any width")
    equal(counter.points[#counter.points][5], 800 * 0.42, "a little below the middle")
    equal(counter.mover.strata, counter:GetFrameStrata(), "the gold outline is on the counter's strata, never under it")
    contains(all, "strata=MEDIUM level=1")
    equal(state.wtf.shardCounter.strata, nil, "UIParent's strata, so dialogs and the Settings panel stay above it")
    equal(state.env.WarlockToolsForeverStones.strata, nil, "the Stones bar too")
    contains(all, "text=0")
    state.settings.WTF_SHARDS_COUNTER:SetValue(false)
    state.clear()
    state.slash("debug_shards")
    contains(table.concat(state.messages, "\n"), "debug_shards counter setting=false shown=false")
end)
test("diagnostics still run when WTF is unavailable", function()
    local state = fixture({class = "MAGE"})
    state.clear()
    state.slash("debug_shards")
    contains(state.messages[1], "debug_shards item=6265 name=Soul Shard")
    contains(table.concat(state.messages, "\n"),
        "debug_shards counter not created: startup did not reach the shard counter (WTF available=false)")
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
    local state = fixture({files = {"Commands.lua", "Core.lua", "Layout.lua", "Shards.lua",
        "Stones.lua", "Announce.lua", "Options.lua"}})
    equal(state.wtf.available, false)
    contains(state.last(), "missing ReportRestrictions")
end)

-- Features that moved out in 1.3.0 and 1.11.0 ---------------------------------

local MOVED_LINES = {
    shield = "Install Dyre's Shields Up from CurseForge for the shield display: it moved there from WTF.",
    reminders = "Install Dyre's Buff Reminders from CurseForge for the cooldown chimes, the Nightfall sound, "
        .. "and the Demon Armor reminder: it moved there from WTF.",
    ddt = "Install Dyre's Debuff Tracker from CurseForge for the DoT tracker, DoT colors, nameplate DoT dots, "
        .. "DoT damage prediction, the smart curse, and the Control bar with its macros and announcements: it "
        .. "moved there from WTF.",
}
local ALL_MOVED_LOADED = {DyresShieldsUp = true, DyresBuffReminders = true, DyresDebuffTracker = true}

test("without Dyre's Shields Up, Dyre's Buff Reminders, or Dyre's Debuff Tracker, login says once to install them", function()
    local state = fixture()
    contains(table.concat(state.messages, "\n"), "WTF: " .. MOVED_LINES.shield)
    contains(table.concat(state.messages, "\n"), "WTF: " .. MOVED_LINES.reminders)
    contains(table.concat(state.messages, "\n"), "WTF: " .. MOVED_LINES.ddt)
    local count = #state.messages
    state.slash("shards")
    state.emit("PLAYER_ENTERING_WORLD")
    for index = count + 1, #state.messages do
        equal(state.messages[index]:find("moved there from WTF", 1, true), nil, "once per session")
    end
end)
test("an installed but disabled AddOn is to be enabled; a loaded one says nothing", function()
    local state = fixture({installedAddOns = {DyresShieldsUp = "DISABLED"},
        loadedAddOns = {DyresBuffReminders = true}})
    local all = table.concat(state.messages, "\n")
    contains(all, "WTF: Enable Dyre's Shields Up in the AddOn list for the shield display: it moved there from WTF.")
    equal(all:find("Install Dyre's Shields Up", 1, true), nil, "nothing to install")
    equal(all:find("Dyre's Buff Reminders", 1, true), nil, "Dyre's Buff Reminders is loaded")
    local quiet = fixture({loadedAddOns = ALL_MOVED_LOADED})
    equal(table.concat(quiet.messages, "\n"):find("moved there from WTF", 1, true), nil)
end)
test("other classes get no moved-feature lines", function()
    local state = fixture({class = "MAGE"})
    equal(table.concat(state.messages, "\n"):find("moved there from WTF", 1, true), nil)
end)
test("the old shield, chime, Nightfall, and reminder settings stay exactly as saved", function()
    local shield = {enabled = false, scale = 80, position = {point = "LEFT", relativePoint = "LEFT", x = 3, y = 4},
        breakSoundKey = "pickglass", extra = "kept"}
    local chimes = {enabled = false, lead = 7, spells = {deathcoil = false}, sounds = {howl = "tts"}}
    local alerts = {nightfall = true, nightfallSound = "not a sound"}
    local reminders = {enabled = false, spells = {armor = false}, last = {armor = 706}}
    local state = fixture({db = {shield = shield, chimes = chimes, alerts = alerts, reminders = reminders}})
    local db = state.wtf.db
    equal(db.shield, shield, "the same tables, for the new AddOns to copy")
    equal(db.chimes, chimes)
    equal(db.alerts, alerts)
    equal(db.reminders, reminders)
    equal(db.shield.scale, 80)
    equal(db.shield.extra, "kept")
    equal(db.shield.locked, nil, "no lock flag added")
    equal(db.alerts.nightfallSound, "not a sound", "not repaired: WTF no longer reads it")
    equal(db.chimes.lead, 7)
    equal(db.reminders.last.armor, 706)
    state.slash("unlock")
    state.slash("lock")
    equal(db.shield.locked, nil, "the lock leaves them alone too")
    local fresh = fixture()
    equal(fresh.wtf.db.shield, nil, "nothing new is saved")
    equal(fresh.wtf.db.chimes, nil)
    equal(fresh.wtf.db.alerts, nil)
    equal(fresh.wtf.db.reminders, nil)
end)
test("WTF draws no shield, plays no sounds, and shows no Demon Armor icon of its own", function()
    local state = fixture()
    equal(state.wtf.ShieldDisplay, nil)
    equal(state.env.WarlockToolsForeverReminder_armor, nil)
    for _, variable in ipairs({"WTF_SHIELD_ENABLED", "WTF_CHIMES_ENABLED", "WTF_REMINDERS_ENABLED",
        "WTF_ALERTS_NIGHTFALL", "WTF_SHIELD_SCALE", "WTF_CHIMES_LEAD"}) do
        equal(state.settings[variable], nil, variable .. " is gone")
    end
    for _, command in ipairs({"debug_shield", "debug_chimes", "debug_reminders"}) do
        state.clear()
        state.slash(command)
        contains(state.last(), "WTF: Use /wtf", command .. " is gone")
    end
    state.units.player.auras = {{name = "Shadow Trance", spellId = 17941}}
    state.emit("UNIT_AURA", "player")
    equal(state.auraSounds, nil, "no Nightfall sound registered")
    equal(state.played, nil, "no sound played")
end)
test("the Shield, Cooldown Chimes, Alerts, and Demon Armor pages link to the AddOns that have them", function()
    local state = fixture({toolkit = true})
    local cases = {
        {"Shield", "DyresShieldsUp", "Shield display", "Open Shield settings",
            "Install Dyre's Shields Up from CurseForge for the shield display."},
        {"Cooldown Chimes", "DyresBuffReminders", "Cooldown chimes", "Open Chime settings",
            "Install Dyre's Buff Reminders from CurseForge for the cooldown chimes."},
        {"Alerts", "DyresBuffReminders", "Nightfall sound", "Open Proc settings",
            "Install Dyre's Buff Reminders from CurseForge for the Nightfall sound (Proc Sounds)."},
        {"Demon Armor", "DyresBuffReminders", "Demon Armor reminder", "Open Reminder settings",
            "Install Dyre's Buff Reminders from CurseForge for the Demon Armor reminder."},
    }
    equal(#state.toolkit.links, #cases + 3, "and the three Dyre's Debuff Tracker pages")
    for _, case in ipairs(cases) do
        local page = state.categories[case[1]]
        local link
        for _, each in ipairs(state.toolkit.links) do
            if each.category == page then link = each end
        end
        equal(page.parent, state.categories["Warlock Tools Forever"], case[1] .. " is under WTF's page")
        equal(link.category, page, case[1] .. ": the link is on its page")
        equal(link.opts.addon, case[2])
        equal(link.opts.name, case[3])
        equal(link.opts.button, case[4])
        equal(link.opts.missing, case[5])
        contains(link.opts.tooltip, "moved to")
        equal(#page.initializers, 0, case[1] .. ": nothing but the link")
        equal(page.headings[1].buttonText, case[4])
    end
end)

-- The move to Dyre's Debuff Tracker (1.11.0; John, 2026-11-20: "Yes, full move").
test("the DoT Tracker, DoTs, and Control pages each open Dyre's Debuff Tracker, in their old places", function()
    local opened = {}
    local state = fixture({toolkit = true, members = {{addon = "DyresDebuffTracker", title = "Dyre's Debuff Tracker",
        openSettings = function() opened[#opened + 1] = "DDT" end}}})
    local main = state.categories["Warlock Tools Forever"]
    local cases = {
        {"DoT Tracker", "DoT tracker and damage prediction",
            "Install Dyre's Debuff Tracker from CurseForge for the DoT tracker, DoT damage prediction, and the "
                .. "smart curse."},
        {"DoTs", "DoT colors, order, and nameplate dots",
            "Install Dyre's Debuff Tracker from CurseForge for the DoT colors, order, and nameplate DoT dots."},
        {"Control", "Control bar, macros, and announcements",
            "Install Dyre's Debuff Tracker from CurseForge for the Control bar, \"! Fear\", \"! Banish\", "
                .. "\"! Seduction\", and the Fear and Banish announcements."},
    }
    for index, case in ipairs(cases) do
        local page = state.categories[case[1]]
        local link = state.toolkit.links[index]
        equal(page.parent, main, case[1] .. " is under WTF's page")
        equal(link.category, page, case[1] .. ": its first link, before the Announce page's neighbors")
        equal(link.opts.addon, "DyresDebuffTracker")
        equal(link.opts.name, case[2])
        equal(link.opts.button, "Open Debuff Tracker settings")
        equal(link.opts.missing, case[3])
        contains(link.opts.tooltip, "moved to Dyre's Debuff Tracker in WTF 1.11.0. This opens its settings.")
        equal(#page.initializers, 0, case[1] .. ": nothing but the link")
        equal(#page.headings, 1, case[1] .. ": one row")
    end
    for _, variable in ipairs({"WTF_TRACKER_ENABLED", "WTF_CONTROL_ENABLED", "WTF_CONTROL_MACROS",
        "WTF_CONTROL_SCALE", "WTF_PREDICT_ENABLED", "WTF_TRACKER_CURSE_MODE", "WTF_TRACKER_THEME"}) do
        equal(state.settings[variable], nil, variable .. " is gone")
    end
    for _, row in ipairs(state.wtf.announcePage and state.wtf.announcePage.rows or {}) do
        equal(row.switch:find("^fear") or row.switch:find("^banish") or row.switch:find("^enslave")
            or row.switch:find("^howl"), nil, row.switch .. ": the crowd-control texts moved")
    end
    local plain = fixture()
    equal(plain.categories["DoT Tracker"].parent, plain.categories["Warlock Tools Forever"],
        "without the toolkit's link, a page that says where it went")
    equal(plain.settings.WTF_MOVED_TRACKER:GetValue(), true)
end)
test("WTF makes no DoT tracker, dots, prediction, Control bar, smart curse, or macros of its own", function()
    local state = fixture({toolkit = true, familyAddOns = {DyresDebuffTracker = true}})
    local shared = state.env.DyresToolkit
    for _, name in ipairs({"WarlockToolsForeverTracker", "WarlockToolsForeverTrackerFocus",
        "WarlockToolsForeverTrackerList", "WarlockToolsForeverControl", "WarlockToolsForeverSmartCurse"}) do
        equal(state.env[name], nil, name)
    end
    if type(shared.KindOwner) == "function" then
        for _, kind in ipairs({"control:WARLOCK", "macros:WARLOCK", "announce:WARLOCK", "dots:WARLOCK"}) do
            equal(shared.KindOwner(kind), nil, kind .. ": WTF claims nothing")
        end
    end
    for _, macro in ipairs(state.macros or {}) do
        for _, name in ipairs({"! Fear", "! Banish", "! Seduction", "! Curse"}) do
            equal(macro.name == name, false, name .. " is not WTF's")
        end
    end
    for _, command in ipairs({"debug_tracker", "debug_predict", "debug_control", "reset_focus"}) do
        state.clear()
        state.slash(command)
        contains(state.last(), "WTF: Use /wtf", command .. " is gone")
    end
end)
test("the Bindings.xml shim keeps only the old smart curse command, with no button behind it", function()
    local file = assert(io.open("Bindings.xml", "rb"))
    local text = file:read("*a")
    file:close()
    local names = {}
    for name in text:gmatch('<Binding%s+name="([^"]+)"') do names[#names + 1] = name end
    equal(#names, 1, "one binding")
    equal(names[1], "CLICK WarlockToolsForeverSmartCurse:LeftButton")
    contains(text, 'header="WARLOCKTOOLSFOREVER"')
    contains(text, "A later WTF release removes this file")
    local state = fixture({toolkit = true})
    equal(state.env.BINDING_HEADER_WARLOCKTOOLSFOREVER, "Warlock Tools Forever")
    equal(state.env["BINDING_NAME_CLICK WarlockToolsForeverSmartCurse:LeftButton"],
        "Smart curse (moved to Dyre's Debuff Tracker)")
    equal(state.env.WarlockToolsForeverSmartCurse, nil, "no button")
    for _, frame in ipairs(state.frames) do
        equal(frame.name == "WarlockToolsForeverSmartCurse", false, "no frame of that name")
    end
    -- No runtime file names the button outside the binding's label line.
    for _, name in ipairs(RUNTIME_FILES) do
        local source = assert(io.open(name, "rb"))
        local code = source:read("*a")
        source:close()
        for line in code:gmatch("[^\n]+") do
            if line:find("WarlockToolsForeverSmartCurse", 1, true) then
                contains(line, "BINDING_NAME_CLICK WarlockToolsForeverSmartCurse:LeftButton", name)
            end
        end
    end
end)
test("the moved settings stay exactly as saved, for Dyre's Debuff Tracker to copy", function()
    local tracker = {enabled = true, theme = "not a theme", colors = {curse = "bad"}, lastCurse = "Curse of Agony",
        locked = "old", extra = {kept = 1}}
    local predict = {enabled = false, color = "plaid", opacity = 9999}
    local control = {enabled = true, scale = 3, markers = {banish = 99}, macros = false}
    local ticks = {[980] = {tick = "bad"}, [172] = {tick = 40, power = 100}}
    local state = fixture({db = {tracker = tracker, predict = predict, control = control,
        announce = {fearGroup = false, fearGroupText = "", banishGroupText = "Banishing %T %M", howlGroup = "x",
            summonGroupText = ""}},
        accountDB = {ticks = ticks}})
    local db = state.wtf.db
    equal(db.tracker, tracker, "the same tables")
    equal(db.predict, predict)
    equal(db.control, control)
    equal(db.tracker.theme, "not a theme", "never repaired")
    equal(db.tracker.colors.curse, "bad")
    equal(db.tracker.locked, "old", "no lock flag written")
    equal(db.tracker.placeholders, nil)
    equal(db.predict.opacity, 9999)
    equal(db.control.scale, 3)
    equal(db.control.markers.banish, 99)
    equal(db.announce.fearGroup, false)
    equal(db.announce.fearGroupText, "", "the crowd-control texts are not repaired")
    equal(db.announce.banishGroupText, "Banishing %T %M")
    equal(db.announce.howlGroup, "x")
    equal(db.announce.enslaveGroupText, nil, "nothing added")
    equal(db.announce.summonGroupText, state.wtf.ANNOUNCE_DEFAULTS.summonGroupText, "WTF's own texts still are")
    equal(state.wtf.accountDB.ticks, ticks, "the learned ticks too")
    equal(state.wtf.accountDB.ticks[980].tick, "bad")
    state.slash("unlock")
    state.slash("lock")
    state.slash("reset")
    equal(db.tracker.locked, "old", "the lock and reset leave them alone")
    equal(db.tracker.placeholders, nil)
    local fresh = fixture()
    equal(fresh.wtf.db.tracker, nil, "nothing new is saved")
    equal(fresh.wtf.db.predict, nil)
    equal(fresh.wtf.db.control, nil)
    equal(fresh.wtf.db.announce.fearGroupText, nil)
end)
test("one chat line only: with Dyre's Debuff Tracker loaded WTF says nothing about the move", function()
    local function ddtLines(state)
        local found = {}
        for _, message in ipairs(state.messages) do
            if message:find("Dyre's Debuff Tracker", 1, true) or message:find("/ddt", 1, true) then
                found[#found + 1] = message
            end
        end
        return found
    end
    for _, saved in ipairs({{tracker = {}}, {tracker = {enabled = false}, control = {enabled = true}},
        {tracker = {enabled = false}, predict = {}}, {}}) do
        local state = fixture({db = saved, loadedAddOns = ALL_MOVED_LOADED})
        equal(#ddtLines(state), 0, "Dyre's Debuff Tracker says what it copied; WTF adds nothing")
        equal(state.wtf.db.ddtNotice, nil, "nothing saved for it")
        -- Without it: only the install line, also for a character that used the features.
        local missing = fixture({db = saved, loadedAddOns = {DyresShieldsUp = true, DyresBuffReminders = true}})
        local lines = ddtLines(missing)
        equal(#lines, 1, "one line")
        equal(lines[1], "WTF: " .. MOVED_LINES.ddt)
    end
    local disabled = fixture({db = {tracker = {}}, installedAddOns = {DyresDebuffTracker = "DISABLED"},
        loadedAddOns = {DyresShieldsUp = true, DyresBuffReminders = true}})
    local lines = ddtLines(disabled)
    equal(#lines, 1)
    contains(lines[1], "WTF: Enable Dyre's Debuff Tracker in the AddOn list for the DoT tracker")
end)

-- Nightfall's owner (1.10.1): the AddOn that owns the Toolkit kind
-- "proc:nightfall" (any one), else Dyre's Buff Reminders' Proc Sounds.
local function nightfallRows(state)
    local rows = {}
    for _, row in ipairs(state.categories.Alerts.headings) do
        local shown = true
        for _, predicate in ipairs(row.shownPredicates or {}) do
            shown = shown and predicate()
        end
        rows[#rows + 1] = {row = row, shown = shown}
    end
    return rows
end
local function shownNightfall(state)
    local found
    for _, each in ipairs(nightfallRows(state)) do
        if each.shown then
            equal(found, nil, "one row shows")
            found = each.row
        end
    end
    return found
end
local function members(opened)
    return {
        {addon = "DyresShieldsUp", title = "Dyre's Shields Up", openSettings = function() opened[#opened + 1] = "DSU" end},
        {addon = "DyresBuffReminders", title = "Dyre's Buff Reminders",
            openSettings = function() opened[#opened + 1] = "DBR" end},
    }
end
test("Nightfall: the Alerts page follows whichever AddOn owns proc:nightfall", function()
    local opened = {}
    local state = fixture({toolkit = true, nightfallOwner = false, members = members(opened)})
    equal(state.wtf.ProcOwner("nightfall"), nil, "no claim yet")
    local row = shownNightfall(state)
    equal(row.name, "Nightfall sound", "no owner: Dyre's Buff Reminders' Proc Sounds, as before")
    equal(row.buttonText, "Open Proc settings")
    -- An owner claims at its PLAYER_LOGIN, after WTF built the page.
    for _, case in ipairs({{"DyresShieldsUp", "Dyre's Shields Up", "DSU"},
            {"DyresBuffReminders", "Dyre's Buff Reminders", "DBR"}}) do
        state.nightfallOwner = case[1]
        row = shownNightfall(state)
        equal(row.name, "Nightfall arcs and sound", case[1] .. ": asked again when the page draws")
        equal(row.buttonText, "Open settings")
        row.buttonClick()
        equal(opened[#opened], case[3], case[1] .. ": the click opens the owner's settings")
        equal(state.wtf.ProcOwnerTitle(case[1]), case[2], "the title it joined with")
    end
    state.combat = true
    local count = #opened
    row.buttonClick()
    equal(#opened, count, "not in combat")
    contains(state.last(), "The settings open out of combat.")
    state.combat = false
    -- It steps aside (for SpellActivationOverlay): no claim, the old row again.
    state.nightfallOwner = nil
    equal(shownNightfall(state).name, "Nightfall sound")
end)
test("Nightfall: the owner's row names it in its tooltip; an unknown owner by its folder", function()
    local state = fixture({toolkit = true, nightfallOwner = "DyresBuffReminders", members = members({})})
    local row = shownNightfall(state)
    equal(row.tooltip, "Dyre's Buff Reminders plays it with its proc arcs. This opens its settings.")
    equal(state.wtf.ProcOwnerTitle("SomeAddOn"), "SomeAddOn")
    state.nightfallOwner = "SomeAddOn"
    row.buttonClick()
    contains(state.last(), "No Dyre's AddOn plays it with proc arcs now.")
end)
test("Nightfall: a real claim and release change the row and its tooltip", function()
    local state = fixture({toolkit = true, procPrefix = true, members = members({}),
        familyAddOns = {DyresBuffReminders = true}})
    local shared = state.env.DyresToolkit
    equal(shownNightfall(state).name, "Nightfall sound")
    local owner = nightfallRows(state)[2].row
    equal(owner.tooltip, "No AddOn plays it with proc arcs now.")
    equal(shared.ClaimOwner("proc:nightfall", "DyresBuffReminders", 10), true)
    equal(shownNightfall(state), owner)
    equal(owner.tooltip, "Dyre's Buff Reminders plays it with its proc arcs. This opens its settings.",
        "the owner change renames it")
    shared.SetOwnerEnabled("proc:nightfall", "DyresBuffReminders", false)
    equal(shownNightfall(state).name, "Nightfall sound")
    equal(owner.tooltip, "No AddOn plays it with proc arcs now.")
end)
test("Nightfall: an owner at build time comes first; without shown predicates, only its row", function()
    local state = fixture({toolkit = true, nightfallOwner = "DyresShieldsUp", members = members({})})
    local rows = nightfallRows(state)
    equal(#rows, 2)
    equal(rows[1].row.name, "Nightfall arcs and sound", "the owner's row first")
    equal(shownNightfall(state), rows[1].row)
    local plain = fixture({toolkit = true, nightfallOwner = "DyresShieldsUp", linkNoShown = true})
    rows = nightfallRows(plain)
    equal(#rows, 1, "one row, no shown predicates")
    equal(rows[1].row.name, "Nightfall arcs and sound")
    local before = fixture({toolkit = true, nightfallOwner = false, linkNoShown = true})
    rows = nightfallRows(before)
    equal(#rows, 1)
    equal(rows[1].row.name, "Nightfall sound")
end)
test("Nightfall: an older Toolkit (no PROC_KIND_PREFIX or KindOwner) keeps Dyre's Buff Reminders", function()
    for _, missing in ipairs({"PROC_KIND_PREFIX", "KindOwner"}) do
        local state = fixture({toolkit = true, nightfallOwner = "DyresShieldsUp", sharedMissing = missing})
        equal(state.wtf.ProcOwner("nightfall"), nil, missing)
        equal(shownNightfall(state).name, "Nightfall sound", missing)
    end
    local none = fixture({nightfallOwner = false, noSharedToolkit = true})
    equal(none.wtf.ProcOwner("nightfall"), nil, "no Toolkit")
end)
test("without the toolkit's link, each moved page says where its feature went", function()
    for _, options in ipairs({{}, {toolkit = true, toolkitMissing = "AddSettingsLink"}}) do
        local state = fixture(options)
        local page = state.categories.Shield
        equal(#page.initializers, 1)
        local note = page.initializers[1]
        equal(note.setting.name, "Shield display (moved to Dyre's Shields Up)")
        contains(note.tooltip, "Install Dyre's Shields Up from CurseForge")
        equal(note.modifyPredicates[1](), false, "greyed: it only says something")
    end
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
-- John, 2026-11-15: a player kept extra shards from a dungeon; leaving one
-- trims what was gained inside, and keeps what was brought in.
local function enterInstance(state, inside)
    state.inInstance = inside
    state.emit("PLAYER_ENTERING_WORLD")
end
test("shards gained in a dungeon and kept go as you leave it", function()
    local state = fullSoulBagWith({})
    enterInstance(state, true)
    equal(state.wtf.db.shards.instanceKeep, 14, "the keep count as you enter is saved")
    -- Gains WTF did not see as created (for any reason) raise the keep count.
    state.arrive(3, 1)
    state.arrive(3, 2)
    state.press()
    equal(state.count(), 16, "kept inside")
    enterInstance(state, false)
    equal(state.wtf.db.shards.instanceKeep, nil, "cleared as you leave")
    for _ = 1, 3 do state.press() end
    equal(state.count(), 14, "trimmed to the limit on the next key presses")
end)
test("shards brought into a dungeon stay as you leave, less the ones used", function()
    local state = fullSoulBagWith({})
    for slot = 1, 3 do state.arrive(3, slot) end
    equal(state.count(), 17, "from the bank, for a raid: kept")
    enterInstance(state, true)
    equal(state.wtf.db.shards.instanceKeep, 17)
    state.bags[5].items[1] = nil
    state.emit("BAG_UPDATE_DELAYED")
    equal(state.wtf.db.shards.instanceKeep, 16, "a shard used inside lowers it")
    state.arrive(3, 4)
    state.arrive(3, 5)
    equal(state.count(), 18)
    enterInstance(state, false)
    for _ = 1, 4 do state.press() end
    equal(state.count(), 16, "the two gained inside go; the ones brought in stay")
end)
test("the keep count as you entered survives a reload inside the dungeon", function()
    local state = fullSoulBagWith({db = {shards = {instanceKeep = 14}}})
    state.inInstance = true
    state.arrive(3, 1)
    state.arrive(3, 2)
    enterInstance(state, true)
    equal(state.wtf.db.shards.instanceKeep, 14, "the saved value stays")
    state.slash("debug_shards")
    contains(table.concat(state.messages, "|"), "inInstance=true instanceKeep=14")
    enterInstance(state, false)
    for _ = 1, 3 do state.press() end
    equal(state.count(), 14)
end)
test("with shard deletion off, entering and leaving a dungeon deletes nothing", function()
    local state = fullSoulBagWith({db = {shards = {enabled = false}}})
    enterInstance(state, true)
    equal(state.wtf.db.shards.instanceKeep, nil, "nothing saved")
    state.arrive(3, 1)
    enterInstance(state, false)
    state.wtf.db.shards.enabled = true
    state.press()
    equal(state.count(), 15, "the shard stays")
end)
test("a damaged saved instance keep count is repaired on load", function()
    for _, value in ipairs({-1, 2.5, "14", 5000}) do
        local state = fullSoulBagWith({db = {shards = {instanceKeep = value}}})
        equal(state.wtf.db.shards.instanceKeep, nil, tostring(value))
    end
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

-- Trim on request (1.12.0; John: "Yes, build it"): a right-click on the
-- shard counter deletes every shard above the limit, the first in the click.
local function rightClickCounter(state, button)
    local counter = state.wtf.shardCounter
    state.hardware = true
    counter.scripts.OnMouseUp(counter, button or "RightButton")
    state.hardware = false
end
local function lineCount(state, text)
    local found = 0
    for _, message in ipairs(state.messages) do
        if message:find(text, 1, true) then found = found + 1 end
    end
    return found
end
test("trim: a right-click on the counter deletes one shard now and the rest on the next inputs, bank shards too", function()
    local state = fullSoulBagWith({})
    for slot = 1, 3 do state.arrive(3, slot) end
    state.press()
    equal(state.count(), 17, "brought in from the bank: kept, as always")
    rightClickCounter(state)
    equal(state.count(), 16, "the first goes in the click itself")
    contains(state.messages[#state.messages - 1], "WTF: Deleting 3 Soul Shards above your limit of 14, one per key "
        .. "press or click.")
    state.press()
    state.click()
    equal(state.count(), 14, "one per input, down to the limit")
    for _ = 1, 3 do state.press() end
    equal(state.count(), 14, "never below the limit")
    state.channel(8288)
    state.gain(3, 1)
    state.stopChannel(8288)
    equal(state.count(), 14, "automatic deletion goes on as before")
    state.now = state.now + 10
    state.arrive(3, 2)
    state.press()
    equal(state.count(), 15, "a shard moved in after the trim is kept again")
end)
test("trim: the left button does not trim; the plain counter still drags with it", function()
    local state = fullSoulBagWith({})
    state.arrive(3, 1)
    rightClickCounter(state, "LeftButton")
    equal(state.count(), 15, "a left click deletes nothing")
    local counter = state.wtf.shardCounter
    equal(type(counter.scripts.OnDragStart), "function", "dragging is still wired")
    equal(type(counter.scripts.OnDragStop), "function")
    equal(counter.template, nil, "a plain frame, not a secure one")
end)
test("trim: the tooltip says how many go; with none above the limit the click says so and does nothing", function()
    local state = fullSoulBagWith({})
    local counter = state.wtf.shardCounter
    counter.scripts.OnEnter(counter)
    contains(table.concat(state.tooltip, "|"), "Right-click: delete shards above your limit (0)")
    state.clear()
    rightClickCounter(state)
    equal(state.count(), 14)
    equal(state.messages[#state.messages], "WTF: No Soul Shards above your limit of 14.")
    equal(#state.messages, 1, "one line")
    state.arrive(3, 1)
    state.arrive(3, 2)
    counter.scripts.OnEnter(counter)
    contains(table.concat(state.tooltip, "|"), "Right-click: delete shards above your limit (2)")
end)
test("trim: in combat the click is taken, nothing is picked up, and the shards go on the first inputs after", function()
    local state = fullSoulBagWith({})
    for slot = 1, 3 do state.arrive(3, slot) end
    state.combat = true
    state.clear()
    rightClickCounter(state)
    equal(state.count(), 17, "nothing deleted in combat")
    equal(state.cursor, nil, "nothing picked up")
    equal(state.restrictedCalls, nil, "no restricted call")
    equal(#state.messages, 1)
    equal(state.messages[1], "WTF: Soul Shards above your limit go after combat.")
    state.press()
    equal(state.count(), 17, "not on inputs in combat either")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(state.count(), 17, "no event-driven deletion")
    for _ = 1, 3 do state.press() end
    equal(state.count(), 14, "one per input after combat")
    -- Another restriction (an encounter) holds it the same way.
    state.arrive(3, 1)
    state.encounter = true
    rightClickCounter(state)
    equal(state.count(), 15)
    state.encounter = false
    state.press()
    equal(state.count(), 14)
end)
test("trim: with automatic deletion off the trim still finishes, and new shards after it stay", function()
    local state = fullSoulBagWith({db = {shards = {enabled = false}}})
    for slot = 1, 3 do state.arrive(3, slot) end
    rightClickCounter(state)
    equal(state.count(), 16)
    -- A shard Drain Soul creates while the trim runs stays: the trim ends at the limit plus it.
    state.channel(8288)
    state.gain(3, 4)
    state.stopChannel(8288)
    equal(state.count(), 16, "the key press goes on with the trim; the new shard raised the keep count")
    for _ = 1, 5 do state.press() end
    equal(state.count(), 15, "the trim ends at the limit plus the new shard")
    state.channel(8288)
    state.gain(3, 5)
    state.stopChannel(8288)
    for _ = 1, 3 do state.press() end
    equal(state.count(), 16, "after the trim, new shards stay while deletion is off")
    equal(state.wtf.db.shards.enabled, false, "the switch is not changed")
end)
test("trim: inside an instance it trims too, and leaving deletes nothing more", function()
    local state = fullSoulBagWith({})
    for slot = 1, 3 do state.arrive(3, slot) end
    enterInstance(state, true)
    equal(state.wtf.db.shards.instanceKeep, 17, "brought in for a raid")
    rightClickCounter(state)
    equal(state.wtf.db.shards.instanceKeep, 14, "the saved instance keep goes down to the limit")
    for _ = 1, 3 do state.press() end
    equal(state.count(), 14)
    enterInstance(state, false)
    equal(state.wtf.db.shards.instanceKeep, nil)
    for _ = 1, 3 do state.press() end
    equal(state.count(), 14, "leaving neither raises nor deletes anything more")
end)
test("trim: after deletion stopped, the click says so and does nothing", function()
    local state = fullSoulBagWith({})
    state.arrive(3, 1)
    state.arrive(3, 2)
    state.deleteBlocked = true
    rightClickCounter(state)
    equal(state.count(), 16, "the client refused: the shard is back")
    contains(table.concat(state.messages, "|"), "Soul Shard deletion stopped")
    state.deleteBlocked = false
    state.clear()
    rightClickCounter(state)
    equal(state.count(), 16)
    equal(#state.messages, 1)
    contains(state.messages[1], "WTF: Soul Shard deletion stopped: the client blocked it. It stays off until you /reload.")
end)
test("trim: debug_shards shows the trim while it runs", function()
    local state = fullSoulBagWith({noBagUpdateOnDelete = true})
    state.arrive(3, 1)
    state.arrive(3, 2)
    rightClickCounter(state)
    state.slash("debug_shards")
    contains(table.concat(state.messages, "|"), "keep=14 source=soul bag enabled=true trimming=true")
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
    contains(state.messages[11], "debug_shards counter setting=true shown=true")
    contains(state.messages[12], "debug_shards stopped=nil lastAttempt=none")
    contains(state.messages[13], "gain 0.0s ago +1 count=3 keep=3 created=true combat=false last=UNIT_SPELLCAST_CHANNEL_START 11675 1.0s before")
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

-- The "! Seduction" pet condition: Toolkit 2.11.1 names the pet's family from
-- UnitCreatureFamily("pet") in the client's language; an older Toolkit (the CI
-- copy) writes the English "pet:Succubus/Incubus".
local function seductionPet(state, family)
    if type(state.env.DyresToolkit.PetFamilyCondition) == "function" then
        return ",pet:" .. family
    end
    return ",pet:Succubus/Incubus"
end

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
    for _, frame in ipairs({state.wtf.shardCounter, state.env.WarlockToolsForeverStones}) do
        equal(registeredMovable(state, frame), true, "every movable frame snaps through the toolkit")
    end
    state.clear()
    state.slash("unlock")
    equal(toolkit.locked, false, "/wtf unlock unlocks every Dyre's AddOn")
    equal(db.locked, false)
    equal(state.env.WarlockToolsForeverStones.mover.shown, true, "outlined")
    equal(state.wtf.shardCounter.mover.shown, true)
    equal(countMessages(state, "All WTF frames"), 0, "the toolkit says one line for all")
    equal(state.last(), "Dyre: Frames unlocked.")
    equal(state.wtf.grid, nil, "the toolkit draws the grid")
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

local function initializerFor(page, variable)
    for _, initializer in ipairs(page.initializers) do
        if initializer.setting.variable == variable then return initializer end
    end
end

test("size sliders are labeled without (%): their values show the % sign", function()
    local state = fixture()
    for _, case in ipairs({{"Stones", "WTF_STONES_SCALE", "Stones bar size"},
        {"Soul Shards", "WTF_SHARDS_COUNTER_SCALE", "Shard counter size"}}) do
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
local function wait(state, seconds)
    state.now = state.now + seconds
    state.runTimers()
end

-- The registered Nightfall aura sounds.
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
    -- A third movable frame to snap to (the DoT tracker was one before 1.11.0).
    local tracker = state.env.CreateFrame("Frame", "WarlockToolsForeverTestPanel", state.env.UIParent)
    tracker:SetSize(200, 100)
    tracker:SetPoint("CENTER", state.env.UIParent, "CENTER", 0, 200)
    state.wtf.RegisterMovable(tracker, function() end)
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
    local state = fixture({db = {stones = {locked = false}}})
    local db = state.wtf.db
    equal(db.locked, true)
    equal(db.stones.locked, true, "older per-frame locks give way to the one lock")
    equal(db.shards.counterLocked, true)
    for _, variable in ipairs({"WTF_STONES_LOCKED", "WTF_TRACKER_LOCKED", "WTF_SHARDS_COUNTER_LOCKED",
        "WTF_TRACKER_PLACEHOLDERS"}) do
        equal(state.settings[variable], nil, variable .. " is gone")
    end
    state.settings.WTF_UNLOCKED:SetValue(true)
    equal(db.locked, false)
end)
test("/wtf unlock and /wtf lock move every WTF frame together", function()
    local state = fixture()
    state.slash("unlock")
    local db = state.wtf.db
    equal(db.stones.locked, false)
    equal(db.shards.counterLocked, false)
    contains(state.last(), "All WTF frames unlocked: drag them where you want")
    equal(state.env.WarlockToolsForeverStones.mover.shown, true, "outlined")
    equal(state.wtf.shardCounter.mover.shown, true)
    equal(state.settings.WTF_UNLOCKED:GetValue(), true, "the main page's switch follows")
    state.slash("lock")
    equal(state.env.WarlockToolsForeverStones.mover.shown, false)
    equal(state.wtf.shardCounter.mover.shown, false)
    equal(db.stones.locked, true)
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
-- 1.7.1 (John: the trade opened, and nothing went in, with no word): no stop
-- is silent, and /wtf debug_stones names each reason.
local function tradeDebug(state)
    state.clear()
    state.slash("debug_stones")
    return table.concat(state.messages, "|")
end
test("a trade placement says why it stops: no free slot, no stone", function()
    local full = tradeFixture()
    for slot = 1, 6 do full.tradeSlots[slot] = 2589 end
    full.clickButton(HEALTH, "LeftButton")
    full.clear()
    full.emit("TRADE_SHOW")
    contains(full.last(), "drag it in yourself")
    contains(tradeDebug(full), "place noFreeSlot")
    local gone = tradeFixture()
    gone.clickButton(HEALTH, "LeftButton")
    gone.bags[0].items[1] = nil
    gone.clear()
    gone.emit("TRADE_SHOW")
    contains(gone.last(), "drag it in yourself")
    contains(tradeDebug(gone), "place noStone 5511")
end)
test("a busy cursor or an empty pickup waits for the next key press", function()
    local busy = tradeFixture()
    busy.clickButton(HEALTH, "LeftButton")
    busy.cursor = {itemID = 2589, count = 1, bag = 0, slot = 2}
    busy.emit("TRADE_SHOW")
    equal(busy.tradeSlots[1], nil)
    equal(busy.cursor.itemID, 2589, "what you hold stays on the cursor")
    busy.cursor = nil
    busy.press()
    equal(busy.tradeSlots[1], 5511, "placed at the key press")
    local text = tradeDebug(busy)
    contains(text, "place cursorBusy item")
    contains(text, "place placed 1")
    contains(text, "keyHook=true")
    local settling = tradeFixture()
    settling.clickButton(HEALTH, "LeftButton")
    settling.pickupMisses = 1
    settling.emit("TRADE_SHOW")
    equal(settling.tradeSlots[1], nil)
    settling.press()
    equal(settling.tradeSlots[1], 5511, "placed at the key press")
    contains(tradeDebug(settling), "place pickupEmpty retry")
end)
test("a refusal is logged with the AddOn the game named", function()
    local state = tradeFixture()
    state.tradeNeedsHardware = true
    state.clickButton(HEALTH, "LeftButton")
    state.emit("TRADE_SHOW")
    local text = tradeDebug(state)
    contains(text, "ADDON_ACTION_BLOCKED WarlockToolsForever UNKNOWN()")
    contains(text, "place refused retry")
end)
-- Dyre's Toolkit Profile (John, 2026-11-17): WTF's part of each character's profile.
local PROFILE_KEY = "Dyre - Forever"
local function profileFixture(extra)
    local options = {toolkit = true, profiles = true}
    for key, value in pairs(extra or {}) do options[key] = value end
    return fixture(options)
end
local function sameTable(actual, expected, path)
    path = path or "settings"
    equal(type(actual), type(expected), path)
    if type(expected) ~= "table" then
        equal(actual, expected, path)
        return
    end
    for key, value in pairs(expected) do sameTable(actual[key], value, path .. "." .. tostring(key)) end
    for key in pairs(actual) do
        if expected[key] == nil then equal(actual[key], nil, path .. "." .. tostring(key) .. " is extra") end
    end
end
local function otherProfile(state, part)
    state.toolkitDB.profiles = state.toolkitDB.profiles or {}
    state.toolkitDB.profiles["Alt - Forever"] = {class = "Warlock", seen = 1, parts = {WarlockToolsForever = part}}
end
test("profile: without Toolkit 2.10's RegisterProfilePart, WTF works as before", function()
    local state = fixture({toolkit = true})
    equal(state.wtf.profileRegistered, false)
    equal(state.toolkitDB.profiles, nil, "nothing saved for a profile")
    equal(state.wtf.db.shards.limit ~= nil, true, "settings load as before")
end)
test("profile: WTF registers its part, without its per-character keys", function()
    local state = profileFixture({db = {chimes = {old = true}}})
    equal(state.wtf.profileRegistered, true)
    local parts = state.shared.ProfileParts()
    equal(parts[#parts], "WarlockToolsForever")
    local part = state.toolkitDB.profiles[PROFILE_KEY].parts.WarlockToolsForever
    equal(type(part.shards), "table", "settings are in the profile")
    for _, key in ipairs({"locked", "shield", "chimes", "alerts", "reminders", "tracker", "predict", "control"}) do
        equal(part[key], nil, key .. " stays on this character")
    end
end)
test("profile: sanitize turns an empty table into WTF's defaults", function()
    local state = profileFixture()
    sameTable(state.wtf.SanitizeProfile({}), state.wtf.SanitizeDB({}))
    sameTable(state.wtf.SanitizeProfile("junk"), state.wtf.SanitizeDB({}))
    local partial = state.wtf.SanitizeProfile({shards = {limit = 999}, stones = "bad", future = {x = 1}})
    equal(partial.shards.limit, 60, "repaired")
    equal(partial.stones.scale, 100, "a bad section gets its defaults")
end)
test("profile: a copy from another character applies live and keeps this character's state", function()
    local state = profileFixture({db = {chimes = {mine = true}, shards = {instanceKeep = 14}}})
    local db = state.wtf.db
    db.stones.soulstone = {name = "Healer", ends = 2000000}
    local shardsTable = db.shards
    otherProfile(state, {
        shards = {limit = 30, autoLimit = false, counterScale = 80, instanceKeep = 3,
            counterPosition = {point = "CENTER", relativePoint = "CENTER", x = 40, y = -20}},
        stones = {scale = 120, soulstone = {name = "Someone", ends = 5},
            position = {point = "TOP", relativePoint = "TOP", x = 10, y = -50}},
        locked = false, chimes = {theirs = true},
    })
    local ok, reload = state.toolkitNS.profile:CopyFrom("Alt - Forever")
    equal(ok, true)
    equal(#reload, 0, "no reload: WTF applies live")
    equal(db.shards.limit, 30)
    equal(db.shards.autoLimit, false)
    equal(db.shards, shardsTable, "written in place")
    equal(db.shards.instanceKeep, 14, "this character's instance count stays")
    equal(db.stones.soulstone.name, "Healer", "this character's Soulstone stays")
    equal(db.locked, true, "the lock stays")
    equal(db.chimes.mine, true, "old data stays")
    equal(db.chimes.theirs, nil)
    local counter = state.wtf.shardCounter
    equal(counter:GetScale(), 0.8, "the counter takes its new size at once")
    local point, _, _, x = counter:GetPoint()
    equal(point, "CENTER")
    equal(x, 40, "and its new place")
    local bar = state.env.WarlockToolsForeverStones
    equal(bar:GetScale(), 1.2, "the Stones bar too")
    point, _, _, x = bar:GetPoint()
    equal(point, "TOP")
    equal(x, 10)
    local saved = state.toolkitDB.profiles[PROFILE_KEY].parts.WarlockToolsForever
    equal(saved.shards.limit, 30, "this character's copy follows")
end)
test("profile: the moved settings and the notice stay with the character", function()
    local state = profileFixture({db = {tracker = {theme = "compact"}, predict = {color = "red"},
        control = {scale = 80}, announce = {fearGroupText = "Mine %T"}}})
    local db = state.wtf.db
    local part = state.toolkitDB.profiles[PROFILE_KEY].parts.WarlockToolsForever
    for _, key in ipairs({"tracker", "predict", "control"}) do
        equal(part[key], nil, key .. " is not in the profile")
    end
    local trackerTable = db.tracker
    otherProfile(state, {tracker = {theme = "bars"}, predict = {color = "white"}, control = {scale = 120},
        announce = {fearGroupText = "Theirs %T", summonGroupText = "Summoning %T"}})
    local ok = state.toolkitNS.profile:CopyFrom("Alt - Forever")
    equal(ok, true)
    equal(db.tracker, trackerTable)
    equal(db.tracker.theme, "compact", "this character's own")
    equal(db.predict.color, "red")
    equal(db.control.scale, 80)
    equal(db.announce.fearGroupText, "Mine %T", "the crowd-control texts stay too")
    equal(db.announce.summonGroupText, "Summoning %T", "WTF's own texts copy")
end)
test("profile: the Defaults reset the settings and keep this character's state", function()
    local state = profileFixture({db = {shards = {limit = 40, autoLimit = false, instanceKeep = 9},
        stones = {scale = 70}}})
    local ok = state.toolkitNS.profile:CopyFrom(state.shared.PROFILE_DEFAULTS)
    equal(ok, true)
    equal(state.wtf.db.shards.autoLimit, true)
    equal(state.wtf.db.stones.scale, 100)
    equal(state.wtf.db.shards.instanceKeep, 9)
    equal(state.env.WarlockToolsForeverStones:GetScale(), 1)
end)
test("profile: export and import carry WTF's settings", function()
    local state = profileFixture({db = {shards = {limit = 25, autoLimit = false}}})
    local line = state.toolkitNS.profile:Export()
    contains(line, "WarlockToolsForever")
    state.wtf.db.shards.limit = 12
    local ok = state.toolkitNS.profile:Import(line)
    equal(ok, true)
    equal(state.wtf.db.shards.limit, 25)
end)
test("profile: a bad part or a bad line changes nothing", function()
    local state = profileFixture({db = {shards = {limit = 22, autoLimit = false}}})
    state.shared.RegisterProfilePart({addon = "BrokenAddOn", current = function() return {} end,
        sanitize = function() error("broken") end})
    otherProfile(state, {shards = {limit = 50, autoLimit = false}})
    state.toolkitDB.profiles["Alt - Forever"].parts.BrokenAddOn = {}
    local ok = state.toolkitNS.profile:CopyFrom("Alt - Forever")
    equal(ok, nil, "all or nothing")
    equal(state.wtf.db.shards.limit, 22)
    ok = state.toolkitNS.profile:Import("DYRE2:profile:garbage:0")
    equal(ok, nil)
    equal(state.wtf.db.shards.limit, 22)
    state.combat = true
    otherProfile(state, {shards = {limit = 50, autoLimit = false}})
    ok = state.toolkitNS.profile:CopyFrom("Alt - Forever")
    equal(ok, nil, "never in combat")
    equal(state.wtf.db.shards.limit, 22)
end)
-- Hide empty DoT slots (John, 2026-11-17; Toolkit TRACKER_HIDE_EMPTY).
-- Sizes (John, 2026-11-12, from a player comment): percent, 50-150, step 5.
test("the Stones bar and shard counter sizes are repaired and start at the saved size", function()
    for saved, expected in pairs({[73] = 75, [999] = 150, [10] = 50, [2.5] = 100, junk = 100}) do
        local state = fixture({db = {stones = {scale = saved}, shards = {counterScale = saved}}})
        equal(state.wtf.db.stones.scale, expected, "stones " .. tostring(saved))
        equal(state.wtf.db.shards.counterScale, expected, "counter " .. tostring(saved))
    end
    local state = fixture()
    equal(state.wtf.db.stones.scale, 100, "today's size by default")
    equal(state.env.WarlockToolsForeverStones:GetScale(), 1)
    local sized = fixture({db = {stones = {scale = 80}, shards = {counterScale = 120}}})
    equal(sized.env.WarlockToolsForeverStones:GetScale(), 0.8)
    equal(sized.wtf.shardCounter:GetScale(), 1.2)
end)
test("the Stones bar size waits for combat to end and keeps the bar's center", function()
    local state = fixture()
    local bar = state.env.WarlockToolsForeverStones
    bar.protected = true -- its secure buttons make it protected in client
    local x, y = state.absCenter(bar)
    state.combat = true
    state.settings.WTF_STONES_SCALE:SetValue(70)
    equal(state.wtf.db.stones.scale, 70, "saved at once")
    equal(bar:GetScale(), 1, "no change in combat")
    state.combat = false
    state.emit("PLAYER_REGEN_ENABLED")
    equal(bar:GetScale(), 0.7, "applied when combat ends")
    local newX, newY = state.absCenter(bar)
    equal(math.floor(newX + 0.5), math.floor(x + 0.5), "same center")
    equal(math.floor(newY + 0.5), math.floor(y + 0.5))
    equal(state.wtf.db.stones.position ~= nil, true, "the kept place is saved")
end)
test("the shard counter size changes at once, also in combat", function()
    local state = fixture()
    local counter = state.wtf.shardCounter
    local x, y = state.absCenter(counter)
    state.combat = true
    state.settings.WTF_SHARDS_COUNTER_SCALE:SetValue(130)
    equal(counter:GetScale(), 1.3)
    local newX, newY = state.absCenter(counter)
    equal(math.floor(newX + 0.5), math.floor(x + 0.5), "same center")
    equal(math.floor(newY + 0.5), math.floor(y + 0.5))
    equal(state.wtf.db.shards.counterScale, 130)
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
    equal(main.initializers[4].setting.variable, "WTF_UNLOCKED", "no DoT tracker or Control bar switch")
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

test("an older Toolkit that lacks one shared function counts as none", function()
    local state = fixture({toolkit = true, sharedMissing = "FormatAnnouncement"})
    equal(state.wtf.shared, nil)
    equal(state.wtf.FormatAnnouncement("Summoning %T to %Z", "Dyre"), "Summoning Dyre to Redridge Mountains",
        "WTF's own fill")
    local other = fixture({toolkit = true, sharedMissing = "LockCast"})
    equal(type(other.wtf.shared), "table", "functions only the moved engines used do not count")
end)
test("announcements fill %Z with your zone and drop an empty %T with its space (Toolkit)", function()
    local state = fixture({toolkit = true})
    equal(type(state.wtf.shared), "table")
    equal(state.wtf.FormatAnnouncement("Summoning %T now", ""), "Summoning now", "an empty %T")
    equal(state.wtf.FormatAnnouncement("Summoning %T to %Z", "Dyre"), "Summoning Dyre to Redridge Mountains")
end)
test("without Dyre's Toolkit WTF's own focus flag waits for a later login", function()
    local state = fixture({noSharedToolkit = true, accountDB = {focusWorks = true}})
    equal(state.wtf.available, true)
    equal(state.wtf.shared, nil)
    equal(state.wtf.accountDB.focusWorks, true)
    equal(countMessages(state, "Dyre's Toolkit (2.5 or later)"), 0, "no line about the moved engines")
    local shared = fixture({toolkit = true, accountDB = {focusWorks = true}})
    equal(shared.wtf.accountDB.focusWorks, nil, "handed to the Toolkit's one flag")
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
