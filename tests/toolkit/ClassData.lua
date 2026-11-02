local _, ns = ...
local DyresToolkit = ns.toolkit

-- Class spell tables, for every Dyre's AddOn (Toolkit 2.5.0, engine stage A;
-- lead-approved plan, 2026-11-01): the class AddOns (Warlock Tools Forever,
-- Mage Tools Forever, later ones) read their own class here, and Dyre's
-- Debuff Tracker reads every class. Data only; never change these tables at
-- run time.
--
-- Classic IDs. Every spellbook spell of the same name counts too
-- (Spells.lua), so each client's own ranks match. Every ID here comes from
-- WTF 1.4.1 or MTF 1.2.3, checked in client there; an ID for any other
-- class or spell must be checked on each client (Era 1.15.9 and Forever)
-- before it is added.
--
-- dots: one slot per tracked debuff family, in the default display order.
--   key, label, color ("aarrggbb"), dot (false: shown, not a DoT), ids,
--   names (matched by name only), cast (the spell a pinned slot recasts),
--   lastUsed (recast the last one cast of the slot), dispelType and
--   excludeSlot (match your debuffs of that type, without that slot's).
-- ranks: [spellID] = {family, damage over time, duration, level learned},
--   base damage without spell power, for the first guess before ticks are
--   learned.
-- families: interval (seconds between ticks), school (for
--   GetSpellBonusDamage), coefficient (share of spell power, default
--   duration / 15 at most 1), weights (each tick's share of the average, by
--   tick; the last weight holds after the list).
-- control: crowd-control spells. key, label, ids, longest (seconds), bar
--   (tracked on the control bar), marker (default raid marker), click (a
--   row click recasts on your focus), plateTimer (a timer under the mob's
--   nameplate), untargeted (no single target: announced only), single (only
--   one of yours can be up at a time: a new cast replaces the old mob's row).
-- macros: name (exact; adopted by name, never a second copy), spell (the ID
--   whose name is cast), known (the control key whose spells you must know),
--   pet (the spell is your pet's: Spells.PetKnows), condition, shift, marker
--   (the control key whose marker setting the /tm uses). See
--   Macros.FocusCastMacro.

local AGONY_WEIGHTS = {0.5, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1.5}

DyresToolkit.ClassData = {
    WARLOCK = {
        -- Every Warlock family that leaves a debuff on an enemy, except
        -- single-target channels (WTF 1.4.1, Tracker.lua; author-approved).
        dots = {
            -- Forever reworked curses: the slot matches your Curse-type
            -- debuffs, without your Banes; the IDs identify your curse casts.
            {key = "curse", label = "Curse", color = "ff9e40d9", dot = true, lastUsed = "lastCurse",
                dispelType = "Curse", excludeSlot = "bane",
                ids = {702, 1108, 6205, 7646, 11707, 11708, 704, 7658, 7659, 11717, 1490, 11721, 11722, 17862,
                    17937, 1714, 11719, 18223}},
            -- Agony, Doom, and Havoc: one Bane per target.
            {key = "bane", label = "Bane", color = "ffe62626", dot = true, lastUsed = "lastBane", cast = 980,
                ids = {980, 1014, 6217, 11711, 11712, 11713, 603},
                names = {"Bane of Agony", "Bane of Doom", "Bane of Havoc"}},
            {key = "corruption", label = "Corruption", color = "ffffffff", dot = true, cast = 172,
                ids = {172, 6222, 6223, 7648, 11671, 11672, 25311}},
            {key = "immolate", label = "Immolate", color = "ffff8019", dot = true, cast = 348,
                ids = {348, 707, 1094, 2941, 11665, 11667, 11668, 25309}},
            {key = "siphon", label = "Siphon Life", color = "ff4dd94d", dot = true, cast = 18265,
                ids = {18265, 18879, 18880, 18881}},
            -- Fear, Howl of Terror, Death Coil, and Banish.
            {key = "control", label = "Fear and control", color = "ffffd91a", dot = false,
                lastUsed = "lastControl", cast = 5782,
                ids = {5782, 6213, 6215, 5484, 17928, 6789, 17925, 17926, 710, 18647}},
        },
        -- Era tooltips (WTF 1.4.1, Predict.lua).
        ranks = {
            [172] = {"corruption", 40, 12, 4}, [6222] = {"corruption", 90, 15, 14},
            [6223] = {"corruption", 222, 18, 24}, [7648] = {"corruption", 324, 18, 34},
            [11671] = {"corruption", 486, 18, 44}, [11672] = {"corruption", 666, 18, 54},
            [25311] = {"corruption", 822, 18, 60},
            [980] = {"agony", 84, 24, 8}, [1014] = {"agony", 180, 24, 18}, [6217] = {"agony", 324, 24, 28},
            [11711] = {"agony", 504, 24, 38}, [11712] = {"agony", 780, 24, 48}, [11713] = {"agony", 1044, 24, 58},
            [348] = {"immolate", 20, 15, 1}, [707] = {"immolate", 40, 15, 10}, [1094] = {"immolate", 90, 15, 20},
            [2941] = {"immolate", 165, 15, 30}, [11665] = {"immolate", 255, 15, 40},
            [11667] = {"immolate", 365, 15, 50}, [11668] = {"immolate", 485, 15, 60},
            [25309] = {"immolate", 510, 15, 60},
            [18265] = {"siphon", 150, 30, 30}, [18879] = {"siphon", 220, 30, 38},
            [18880] = {"siphon", 330, 30, 48}, [18881] = {"siphon", 450, 30, 58},
        },
        -- 3 fire, 6 shadow. Immolate's over-time part takes 0.65 (it also
        -- hits), Siphon Life half (it heals). Curse of Agony: the first four
        -- ticks half the average, the next four the average, the last four
        -- one and a half times it.
        families = {
            corruption = {interval = 3, school = 6},
            agony = {interval = 2, school = 6, weights = AGONY_WEIGHTS},
            immolate = {interval = 3, school = 3, coefficient = 0.65},
            siphon = {interval = 3, school = 6, coefficient = 0.5},
        },
        familyOrder = {"corruption", "agony", "immolate", "siphon"},
        -- WTF 1.4.1, Control.lua. Enslave Demon and Howl of Terror only
        -- announce: an enslaved demon is your pet, and Howl of Terror has no
        -- single target.
        control = {
            {key = "fear", label = "Fear", ids = {5782, 6213, 6215}, longest = 20, bar = true, plateTimer = true},
            {key = "banish", label = "Banish", ids = {710, 18647}, longest = 30, bar = true, marker = 5,
                click = true},
            {key = "enslave", label = "Enslave Demon", ids = {1098, 11725, 11726}},
            {key = "howl", label = "Howl of Terror", ids = {5484, 17928}, untargeted = true},
        },
        macros = {
            {name = "! Fear", spell = 5782, known = "fear", shift = true},
            {name = "! Banish", spell = 710, known = "banish", marker = "banish"},
            -- Only with a Succubus or Incubus that knows it.
            {name = "! Seduction", spell = 6358, pet = true, condition = ",pet:Succubus/Incubus"},
        },
    },
    MAGE = {
        dots = {},
        ranks = {},
        families = {},
        familyOrder = {},
        -- MTF 1.2.3, Polymorph.lua: Polymorph's ranks, then Pig, Turtle, and Cow.
        control = {
            {key = "polymorph", label = "Polymorph", ids = {118, 12824, 12825, 12826, 28272, 28271, 28270},
                longest = 50, bar = true, marker = 5, click = true, single = true},
        },
        macros = {
            {name = "! Polymorph", spell = 118, known = "polymorph", marker = "polymorph"},
        },
    },
}

-- One class's table by its class file name ("WARLOCK"), else nil.
function DyresToolkit.ClassSpells(classFile)
    return DyresToolkit.ClassData[classFile]
end

-- A family's tick weight: its share of the average tick, 1 without weights.
function DyresToolkit.TickWeight(family, tick)
    local weights = family and family.weights
    if not weights or #weights == 0 then
        return 1
    end
    return weights[math.min(tick, #weights)]
end
