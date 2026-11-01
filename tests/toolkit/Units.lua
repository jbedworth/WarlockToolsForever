local _, ns = ...
local DyresToolkit = ns.toolkit

-- Which mob a unit token shows, for every Dyre's AddOn (Toolkit 2.4.0; Dyre's
-- Debuff Tracker phase 1, coordinator-approved 2026-10-30). Moved from
-- Warlock Tools Forever 1.4.0 (Core.lua's plate memory, Tracker.lua's and
-- Control.lua's cast lookups) and Mage Tools Forever (Polymorph.lua's cast
-- lock and focusWorks), which keep their own copies until each switches over.
--
-- Combat data can be a secret value on Forever: code may store and pass it
-- on, but never compare, concatenate, or print it. Every reader here gives
-- nil (or false) for a secret, so callers never touch one.

local MAX_NAMEPLATE_UNITS = 40

function DyresToolkit.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end

local IsSecret = DyresToolkit.IsSecret

-- Text for diagnostics that never touches a secret value's contents.
function DyresToolkit.Describe(value)
    if IsSecret(value) then
        return "secret"
    end
    return tostring(value)
end

function DyresToolkit.ReadGUID(unit)
    local guid = UnitGUID(unit)
    if IsSecret(guid) or type(guid) ~= "string" then
        return nil
    end
    return guid
end

function DyresToolkit.ReadName(unit)
    local name = UnitName(unit)
    if IsSecret(name) or type(name) ~= "string" then
        return nil
    end
    return name
end

-- A secret "dead" counts as alive.
function DyresToolkit.IsDead(unit)
    local dead = UnitIsDead(unit)
    return not IsSecret(dead) and dead == true
end

local ReadGUID, ReadName, IsDead = DyresToolkit.ReadGUID, DyresToolkit.ReadName, DyresToolkit.IsDead

-- Plate memory -------------------------------------------------------------------

-- Which mob each nameplate token shows, for plates whose GUID cannot be read
-- (secret, as the client may give in combat; WTF player report: a dotted
-- target you tabbed away from stayed unbound beside its own plate). Learned
-- from the plate's GUID when readable, else from UnitIsUnit with your target
-- or focus, whose GUIDs are readable; a token shows one mob until its plate
-- goes. One table for every AddOn. The toolkit registers no plate events:
-- each AddOn calls these from its own handlers, so handler order never
-- matters (as in WTF).
local plates = {}

function DyresToolkit.LearnPlate(unit)
    if not UnitExists(unit) then
        return
    end
    local guid = ReadGUID(unit)
    if guid then
        plates[unit] = guid
        return
    end
    for _, known in ipairs({"target", "focus"}) do
        local same = UnitIsUnit(unit, known)
        if not IsSecret(same) and same == true then
            plates[unit] = ReadGUID(known) or plates[unit]
            return
        end
    end
end

function DyresToolkit.LearnPlates()
    for index = 1, MAX_NAMEPLATE_UNITS do
        DyresToolkit.LearnPlate("nameplate" .. index)
    end
end

-- A plate came or went: its token may show another mob now.
function DyresToolkit.ForgetPlate(unit)
    plates[unit] = nil
end

-- The mob the plate memory says this token shows, else nil.
function DyresToolkit.PlateGUID(unit)
    return plates[unit]
end

-- The plate token known to show this mob, else nil.
function DyresToolkit.KnownPlate(guid)
    for unit, known in pairs(plates) do
        if known == guid and UnitExists(unit) then
            return unit
        end
    end
end

-- Finding a unit ------------------------------------------------------------------

-- The unit token showing this mob now, in the caller's order: unit tokens,
-- "plates" (nameplate1 to 40 by a readable GUID), and "memory" (the plate
-- memory, for plates whose GUID is secret). The default is WTF's Control bar
-- order: focus first (it stays on the mob when its nameplate drops), then
-- target, plates, memory. Never mouseover by default: it changes with the
-- pointer and has no event to rebind on.
local DEFAULT_FIND_ORDER = {"focus", "target", "plates", "memory"}

function DyresToolkit.FindUnit(guid, order)
    if type(guid) ~= "string" then
        return nil
    end
    for _, step in ipairs(order or DEFAULT_FIND_ORDER) do
        if step == "plates" then
            for index = 1, MAX_NAMEPLATE_UNITS do
                local unit = "nameplate" .. index
                if UnitExists(unit) and ReadGUID(unit) == guid then
                    return unit
                end
            end
        elseif step == "memory" then
            local known = DyresToolkit.KnownPlate(guid)
            if known then
                return known
            end
        elseif ReadGUID(step) == guid then
            return step
        end
    end
end

-- The cast lock -------------------------------------------------------------------

-- The mob a cast sent at targetName goes to, read as the cast starts
-- (UNIT_SPELLCAST_SENT gives only a name; WTF player reports: a mob found by
-- name at success time, after a tab, was the wrong one). The first unit in
-- opts.units with that name that passes the checks; "plates" is nameplate1
-- to 40. Options, so each caller keeps its own rules:
--   units          the order; default focus, mouseover, target, plates
--   memory         a nameplate whose GUID is secret may use the plate memory
--   secretHostile  a secret "can attack" counts as yes (WTF Control: a
--                  secret answer must not drop the cast); default no
--   allowDead      skip the "not dead" check (WTF's DoT tracker)
--   stopAtName     stop at the first unit with the name, locked or not
--                  (WTF's DoT tracker)
--   stopAt         {[unit] = true}: when that unit exists, the search ends
--                  there (MTF without a focus: mouseover, as its macro's
--                  chain casts there)
-- Returns the GUID and the unit, else nil, plus a list of what it looked at
-- for the AddOns' debug commands (never a secret's contents).
local DEFAULT_CAST_UNITS = {"focus", "mouseover", "target", "plates"}
local LOOK_LIMIT = 6

local function Expand(units)
    local list = {}
    for _, unit in ipairs(units) do
        if unit == "plates" then
            for index = 1, MAX_NAMEPLATE_UNITS do
                list[#list + 1] = "nameplate" .. index
            end
        else
            list[#list + 1] = unit
        end
    end
    return list
end

local function Hostile(unit, secretYes)
    local canAttack = UnitCanAttack("player", unit)
    if IsSecret(canAttack) then
        return secretYes == true, canAttack
    end
    return canAttack == true, canAttack
end

function DyresToolkit.LockCast(targetName, opts)
    opts = type(opts) == "table" and opts or {}
    local look = {}
    if IsSecret(targetName) or type(targetName) ~= "string" or targetName == "" then
        return nil, nil, look
    end
    for _, unit in ipairs(Expand(opts.units or DEFAULT_CAST_UNITS)) do
        if UnitExists(unit) then
            local plate = unit:match("^nameplate") ~= nil
            if ReadName(unit) == targetName then
                local guid = ReadGUID(unit) or (opts.memory and plate and plates[unit]) or nil
                local hostile, canAttack = Hostile(unit, opts.secretHostile)
                local alive = opts.allowDead or not IsDead(unit)
                look[#look + 1] = string.format("%s(attack=%s dead=%s guid=%s)", unit,
                    DyresToolkit.Describe(canAttack), DyresToolkit.Describe(UnitIsDead(unit)), tostring(guid ~= nil))
                if guid and hostile and alive then
                    return guid, unit, look
                end
                if opts.stopAtName then
                    return nil, nil, look
                end
            elseif #look < LOOK_LIMIT and not plate then
                look[#look + 1] = unit .. "(other name)"
            end
            if opts.stopAt and opts.stopAt[unit] then
                return nil, nil, look
            end
        end
    end
    return nil, nil, look
end

-- focusWorks ----------------------------------------------------------------------

-- Whether this client has a focus target (rule from WTF and MTF; John, WTF
-- 1.3.3: "@focus and /focus do not work in era"; in client on Era, /focus
-- leaves UnitExists("focus") false and [@focus,exists] false, with no error,
-- and no API tells). One flag for every Dyre's AddOn (coordinator-approved
-- 2026-10-30: it is a fact about the client, and each client install has its
-- own SavedVariables): DyresToolkitDB.focusWorks starts nil and becomes true
-- the first time PLAYER_FOCUS_CHANGED comes with a readable, not secret
-- UnitExists("focus") true. It never goes back on its own; a reset from any
-- AddOn resets it for all. Only true counts.
local listeners = {}

function DyresToolkit.FocusWorks()
    return ns.db.focusWorks == true
end

local function Tell(works)
    for _, callback in ipairs(listeners) do
        callback(works)
    end
end

-- callback(works): called every time the flag is learned (true) or reset
-- (false), as often as that happens. It may come in combat (learned at
-- PLAYER_FOCUS_CHANGED): a listener that changes macros or secure
-- attributes waits for PLAYER_REGEN_ENABLED itself.
function DyresToolkit.OnFocusWorks(callback)
    if type(callback) ~= "function" then
        return false
    end
    listeners[#listeners + 1] = callback
    return true
end

-- Learns the flag from your focus now; returns whether it is true.
function DyresToolkit.LearnFocusWorks()
    if DyresToolkit.FocusWorks() then
        return true
    end
    local exists = UnitExists("focus")
    if IsSecret(exists) or exists ~= true then
        return false
    end
    ns.db.focusWorks = true
    Tell(true)
    return true
end

-- An AddOn's own older flag was true: carry it over once.
function DyresToolkit.NoteFocusWorks()
    if not DyresToolkit.FocusWorks() then
        ns.db.focusWorks = true
        Tell(true)
    end
end

-- For an AddOn's reset command: one reset is for every Dyre's AddOn.
DyresToolkit.FOCUS_RESET_TEXT = "Focus detection reset for every Dyre's AddOn: it is learned again the first time you set a focus."

function DyresToolkit.ResetFocusWorks()
    ns.db.focusWorks = nil
    Tell(false)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_FOCUS_CHANGED")
events:SetScript("OnEvent", function()
    DyresToolkit.LearnFocusWorks()
end)
