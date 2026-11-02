local _, ns = ...
local DyresToolkit = ns.toolkit

-- Spells by name, for every Dyre's AddOn (Toolkit 2.5.0, engine stage A;
-- lead-approved plan, 2026-11-01). Moved from Warlock Tools Forever 1.4.1
-- (Tracker.lua's and Control.lua's spellbook scans, Control.lua's PetKnows)
-- and Mage Tools Forever 1.2.3 (Polymorph.lua's spell set), which keep their
-- own copies until each switches over.
--
-- Class tables list Classic IDs; every spellbook spell of the same name counts
-- too, so each client's own ranks (Forever's among them) match.

local IsSecret = DyresToolkit.IsSecret

local function SpellName(id)
    if type(C_Spell) ~= "table" or type(C_Spell.GetSpellName) ~= "function" then
        return nil
    end
    local name = C_Spell.GetSpellName(id)
    if IsSecret(name) or type(name) ~= "string" then
        return nil
    end
    return name
end

DyresToolkit.SpellName = SpellName

-- Spellbook spells by name: every ID listed under each name, and the names the
-- player has learned. The spellbook also lists spells learned later
-- (FutureSpell), which must not count as learned. Empty where the client has
-- no C_SpellBook skill lines.
function DyresToolkit.SpellbookIDsByName()
    local byName, learned = {}, {}
    if type(C_SpellBook) ~= "table" or type(C_SpellBook.GetNumSpellBookSkillLines) ~= "function"
        or type(C_SpellBook.GetSpellBookItemInfo) ~= "function" then
        return byName, learned
    end
    local learnedType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if type(lineInfo) == "table" then
            for index = lineInfo.itemIndexOffset + 1, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
                if type(item) == "table" and type(item.spellID) == "number" and type(item.name) == "string" then
                    byName[item.name] = byName[item.name] or {}
                    byName[item.name][#byName[item.name] + 1] = item.spellID
                    if learnedType == nil or item.itemType == learnedType then
                        learned[item.name] = true
                    end
                end
            end
        end
    end
    return byName, learned
end

-- One spell family's IDs as a set ({[id] = true}): its Classic IDs, plus
-- every spellbook ID under their names and under extra `names` (spells
-- matched by name only, such as Forever's Banes). Also the names, and whether
-- the player has learned one of them. `book` is SpellbookIDsByName()'s two
-- results, to scan the spellbook once for many families.
function DyresToolkit.SpellSet(ids, names, book)
    local byName, learned
    if book then
        byName, learned = book[1], book[2]
    else
        byName, learned = DyresToolkit.SpellbookIDsByName()
    end
    local set, allNames = {}, {}
    for _, id in ipairs(ids or {}) do
        set[id] = true
        local name = SpellName(id)
        if name then
            allNames[name] = true
        end
    end
    for _, name in ipairs(names or {}) do
        allNames[name] = true
    end
    local known = false
    for name in pairs(allNames) do
        for _, id in ipairs(byName[name] or {}) do
            set[id] = true
        end
        known = known or learned[name] == true
    end
    return set, allNames, known
end

-- Many families at once, from a list of defs each with a `key`, `ids`, and
-- optional `names` (a class table's dots or control spells). Gives which def
-- each spell ID belongs to ({[id] = def}, the first def listing an ID wins),
-- each def's set by key, and whether each key's spell is learned.
function DyresToolkit.IndexSpells(defs)
    local book = {DyresToolkit.SpellbookIDsByName()}
    local byID, sets, known = {}, {}, {}
    for _, def in ipairs(defs) do
        local set, _, learned = DyresToolkit.SpellSet(def.ids, def.names, book)
        sets[def.key] = set
        known[def.key] = learned
        for id in pairs(set) do
            byID[id] = byID[id] or def
        end
    end
    return byID, sets, known
end

-- Whether the player knows one of these spells: a list of IDs, or a set
-- ({[id] = true}). False where the client has no C_SpellBook.IsSpellKnown.
function DyresToolkit.KnowsAny(ids)
    if type(ids) ~= "table" or type(C_SpellBook) ~= "table" or type(C_SpellBook.IsSpellKnown) ~= "function" then
        return false
    end
    for key, value in pairs(ids) do
        local id = value == true and key or value
        if type(id) == "number" and C_SpellBook.IsSpellKnown(id) == true then
            return true
        end
    end
    return false
end

-- A pet spell your pet knows: by ID, else by name in the pet spellbook
-- (Forever's Incubus may carry its own Seduction ID). Nothing without a pet.
function DyresToolkit.PetKnows(spellID)
    if type(C_SpellBook) ~= "table" or type(C_SpellBook.IsSpellKnown) ~= "function" then
        return false
    end
    -- The second argument is a SpellBookSpellBank enum (Pet = 1); Classic Era
    -- rejects `true` (WTF player report: "bad argument #2 to 'IsSpellKnown'").
    -- Without the enum, the legacy IsSpellKnown(spellID, isPet), else the scan.
    local bank = type(Enum) == "table" and type(Enum.SpellBookSpellBank) == "table"
        and Enum.SpellBookSpellBank.Pet or nil
    if bank ~= nil then
        if C_SpellBook.IsSpellKnown(spellID, bank) == true then
            return true
        end
    elseif type(IsSpellKnown) == "function" and IsSpellKnown(spellID, true) == true then
        return true
    end
    local name = SpellName(spellID)
    if not name or type(C_SpellBook.HasPetSpells) ~= "function" then
        return false
    end
    -- Classic Era and Anniversary have no C_SpellBook.GetSpellBookItemInfo,
    -- only GetSpellBookItemName(index, "pet") (WTF player report: with a
    -- demon out, the missing function stopped WTF's login).
    local count = C_SpellBook.HasPetSpells()
    for index = 1, (type(count) == "number" and count or 0) do
        local itemName
        if bank ~= nil and type(C_SpellBook.GetSpellBookItemInfo) == "function" then
            local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
            itemName = type(item) == "table" and item.name
        elseif type(GetSpellBookItemName) == "function" then
            itemName = GetSpellBookItemName(index, "pet")
        end
        if itemName == name then
            return true
        end
    end
    return false
end
