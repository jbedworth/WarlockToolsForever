local _, ns = ...
local DyresToolkit = ns.toolkit

-- Character macros, for every Dyre's AddOn (Toolkit 2.5.0, engine stage A;
-- lead-approved plan, 2026-11-01). Moved from Warlock Tools Forever 1.4.1
-- (Stones.lua's writer and slot check, Control.lua's macro text) and Mage
-- Tools Forever 1.2.3 (Conjure.lua's writer, Polymorph.lua's macro text),
-- which keep their own copies until each switches over.
--
-- Rules every Dyre's AddOn keeps: macros change only out of combat; AddOn
-- code never calls SetRaidTarget, so a marker comes only from a macro's /tm,
-- which runs from your key press, untainted, also in combat; spells are cast
-- with /use. The focus macros' @focus clauses have no `exists` (John,
-- 2026-11-12: "exists is a no-op, drop it"): `harm` is false with no unit,
-- so `[@focus,harm,nodead]` already fails without a focus.

local MACRO_ICON = 134400
-- Leave the last character slots free for the player's own macros.
local MACRO_SLOT_CUSHION = 2
local MACRO_FUNCTIONS = {"GetMacroIndexByName", "GetNumMacros", "GetMacroBody", "CreateMacro", "EditMacro",
    "DeleteMacro", "InCombatLockdown"}

-- MAX_CHARACTER_MACROS is a global only once Blizzard's Macro window has
-- loaded; the constant table always has it (WTF, in client: the missing
-- global silently turned the macros off).
function DyresToolkit.CharacterMacroLimit()
    local constants = type(Constants) == "table" and Constants.MacroConsts
    if type(constants) == "table" and type(constants.MAX_CHARACTER_MACROS) == "number" then
        return constants.MAX_CHARACTER_MACROS
    end
    if type(MAX_CHARACTER_MACROS) == "number" then
        return MAX_CHARACTER_MACROS
    end
end

-- Whether this client can keep character macros, else the first thing missing.
function DyresToolkit.MacrosAvailable()
    for _, name in ipairs(MACRO_FUNCTIONS) do
        if type(_G[name]) ~= "function" then
            return false, name
        end
    end
    if not DyresToolkit.CharacterMacroLimit() then
        return false, "Constants.MacroConsts.MAX_CHARACTER_MACROS"
    end
    return true
end

-- Work that must wait for the end of combat: one entry per key, so a second
-- request in combat replaces the first. Runs on PLAYER_REGEN_ENABLED.
local pending, order = {}, {}
local regen

local function RunPending()
    regen:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local work, keys = pending, order
    pending, order = {}, {}
    for _, key in ipairs(keys) do
        -- A key run since (out of combat) is gone.
        local fn = work[key]
        work[key] = nil
        if fn then
            fn()
        end
    end
end

-- Runs fn now out of combat (true), else once combat ends (false).
function DyresToolkit.OutOfCombat(key, fn)
    if not InCombatLockdown() then
        pending[key] = nil
        fn()
        return true
    end
    if not pending[key] then
        order[#order + 1] = key
    end
    pending[key] = fn
    if not regen then
        regen = CreateFrame("Frame")
        regen:SetScript("OnEvent", RunPending)
    end
    regen:RegisterEvent("PLAYER_REGEN_ENABLED")
    return false
end

-- A macro keeper: writes, adopts, and deletes one AddOn's character macros.
-- spec: {owned = a table in the caller's saved variables (name -> true: the
-- macros this AddOn keeps, so ownership outlives a reload; the engine never
-- owns SavedVariables), warn = function(text) end (once, when no slot is
-- free), icon = texture (default the question mark, which #showtooltip
-- fills)}. Without `owned`, ownership lasts this session only.
-- keeper:Write(name, body, oldNames) gives what it did: "created", "adopted"
-- (a macro of that exact name was there and is not in `owned`: another
-- Dyre's AddOn's, which this one keeps now, never a second copy; once),
-- "renamed" (an old name, renamed in place so action bar slots keep it),
-- "edited", or "unchanged"; else nil and why: "combat", "unavailable", or
-- "full". Macros change only out of combat: wrap calls in OutOfCombat.
function DyresToolkit.CreateMacroKeeper(spec)
    spec = spec or {}
    local keeper = {written = spec.owned or {}, warned = false}
    local icon = spec.icon or MACRO_ICON

    function keeper:Available()
        return (DyresToolkit.MacrosAvailable())
    end

    -- Whether a character macro of this exact name exists.
    function keeper:Has(name)
        return self:Available() and GetMacroIndexByName(name) > 0
    end

    function keeper:Write(name, body, oldNames)
        if not self:Available() then
            return nil, "unavailable"
        end
        if InCombatLockdown() then
            return nil, "combat"
        end
        local index = GetMacroIndexByName(name)
        if index == 0 then
            for _, oldName in ipairs(oldNames or {}) do
                local oldIndex = GetMacroIndexByName(oldName)
                if oldIndex > 0 then
                    EditMacro(oldIndex, name, icon, body)
                    self.written[name] = true
                    return "renamed"
                end
            end
            local _, numCharacter = GetNumMacros()
            if DyresToolkit.CharacterMacroLimit() - numCharacter <= MACRO_SLOT_CUSHION then
                if not self.warned and spec.warn then
                    self.warned = true
                    spec.warn("No free character macro slot for \"" .. name .. "\"; free one and it is added.")
                end
                return nil, "full"
            end
            CreateMacro(name, icon, body, true)
            self.written[name] = true
            return "created"
        end
        local adopted = not self.written[name]
        self.written[name] = true
        if GetMacroBody(index) ~= body then
            EditMacro(index, name, icon, body)
            return adopted and "adopted" or "edited"
        end
        return adopted and "adopted" or "unchanged"
    end

    -- Deletes the macro of this name, out of combat; whether one was deleted.
    function keeper:Delete(name)
        if not self:Available() or InCombatLockdown() then
            return false
        end
        self.written[name] = nil
        local index = GetMacroIndexByName(name)
        if index > 0 then
            DeleteMacro(index)
            return true
        end
        return false
    end

    return keeper
end

-- Macro text -----------------------------------------------------------------

-- The game's /tm for a unit, or nothing for no marker. "!" keeps a second
-- press from toggling the marker off; "harm" keeps it from marking nothing
-- (false with no unit).
function DyresToolkit.MarkLine(unit, marker)
    if type(marker) ~= "number" or marker <= 0 then
        return nil
    end
    return "/tm [@" .. unit .. ",harm,nodead] !" .. marker
end

-- The focus lines (John, 2026-11-12, tested in client; from an MTF player:
-- "Once in battle, the polymorph macro doesn't work"). The game's /focus
-- (SlashCommands.lua, live 580, classic_era 576) runs FocusUnit(action) when
-- the clause's unit is "focus", and the action text is empty, so a @focus
-- clause focuses your target: it can never keep the focus. So the line
-- matches only when the focus must change, and no match keeps it:
--   the mob under the mouse; a missing or friendly focus (noharm is true with
--   no unit) or a dead focus: your target. A live enemy focus: no clause
--   matches, the focus stays ("Once focus is set, it's locked on").
-- CLEAR_LINE comes first (John: "someone can shift-click, clear and retarget
-- something"): Shift or a right-click (John, 2026-11-13: "make it so the
-- user can use shift or right-click to get the switching focus behavior";
-- [btn:2] is the action button's right mouse button; a key binding is
-- always button 1, so with a key only Shift clears) clears the focus;
-- /focus then takes the mouseover or target. No dead test (John: "Focus is auto-lost if the mob dies"). Only
-- while focus works: the chain's macros stay under 255 letters ("Polymorph:
-- Turtle" with the Era chain is 236; with this line, 267), and the chain
-- does not rely on the focus.
local CLEAR_LINE = "/clearfocus [mod:shift][btn:2]"
local FOCUS_LINE = "/focus [@mouseover,harm,nodead][@focus,noharm][@focus,dead]"
-- shift: without Shift, the mob under the mouse, else your target, becomes the focus.
local SHIFT_FOCUS_LINE = "/focus [nomod:shift,@mouseover,harm,nodead][nomod:shift,harm,nodead]"
local SHIFT_CAST = "[mod:shift,@mouseover,harm,nodead][mod:shift,harm,nodead]"
-- Until a focus is seen to work, each line falls back to the mob under the
-- mouse, then your target (the /focus line stays: on Forever it sets the
-- focus that teaches FocusWorks; on Era it does nothing).
local FALLBACK = "[@mouseover,harm,nodead%s][harm,nodead%s]"

-- A control spell's macro: keep a live enemy focus (Shift clears it), else
-- make the mob under the mouse, else your target, your focus, mark it, and cast on it. options:
--   spell      the spell ID or name (an ID with no name here gives nil)
--   marker     a raid marker index for the /tm line, or nil/0 for none
--   condition  extra macro conditions for the cast, such as ",pet:Succubus/Incubus"
--   chain      true: fall back to mouseover, then target (default: not FocusWorks())
--   shift      Fear's form: a plain press focuses and casts, Shift casts on
--              the mob under the mouse (else your target) and keeps your
--              focus; it takes no marker
--   untargeted a spell with no target (Howl of Terror, Psychic Scream,
--              Freezing Trap): only the cast line
function DyresToolkit.FocusCastMacro(options)
    local spell = options.spell
    if type(spell) == "number" then
        spell = DyresToolkit.SpellName(spell)
    end
    if type(spell) ~= "string" or spell == "" then
        return nil
    end
    local show = "#showtooltip " .. spell
    if options.untargeted then
        return show .. "\n/use " .. spell
    end
    local chain = options.chain
    if chain == nil then
        chain = not DyresToolkit.FocusWorks()
    end
    local condition = options.condition or ""
    local fallback = chain and FALLBACK:format(condition, condition) or ""
    if options.shift then
        return show .. "\n" .. SHIFT_FOCUS_LINE .. "\n/use " .. SHIFT_CAST
            .. "[@focus,harm,nodead" .. condition .. "]" .. fallback .. " " .. spell
    end
    local lines = {show}
    if not chain then
        lines[#lines + 1] = CLEAR_LINE
    end
    lines[#lines + 1] = FOCUS_LINE
    local mark = DyresToolkit.MarkLine("focus", options.marker)
    if mark and chain then
        mark = mark:gsub(" !", FALLBACK:format("", "") .. " !", 1)
    end
    lines[#lines + 1] = mark
    lines[#lines + 1] = "/use [@focus,harm,nodead" .. condition .. "]" .. fallback .. " " .. spell
    return table.concat(lines, "\n")
end
