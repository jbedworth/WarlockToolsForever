local _, ns = ...
local DyresToolkit = ns.toolkit

-- Class spell tables, for every Dyre's AddOn (Toolkit 2.5.0, engine stage A;
-- lead-approved plan, 2026-11-01): the class AddOns (Warlock Tools Forever,
-- Mage Tools Forever, later ones) read their own class here, and Dyre's
-- Debuff Tracker reads every class. Data only; never change these tables at
-- run time.
--
-- Classic IDs. Every spellbook spell of the same name counts too
-- (Spells.lua), so each client's own ranks match. The Warlock IDs and Mage's
-- Polymorph come from WTF 1.4.1 and MTF 1.2.3, checked in client there.
--
-- The other classes and Mage's DoTs (the DDT class gate; lead, 2026-11-14, John:
-- "go with your recommendations") come from Dyre's Debuff Tracker's class
-- audit, each ID copied from a local file, none guessed, and NOT YET
-- CHECKED IN CLIENT (lead decision 7: build with the cited IDs, mark them,
-- John /dumps them; the list is the class's `checks` and DDT's TESTING.md):
--   LCD    LibClassicDurations classAbilities.lua, SpellTable 71 (Era IDs,
--          durations, the Rupture and Freezing Trap rules)
--   G2G-F  Good-to-Go 2026.11.12.A Data/Camelot (Forever trainer IDs)
--   TFB    TalentsForeverBook 0.38.25 Data.lua (Forever talents)
--   WT     WhatsTraining 11.4.6 Classes/Vanilla (Era levels) and
--          Classes/Camelot (Forever levels, rank groups)
--   DIDA   DoesItDieAdvanced 1.3.1 (tick intervals: KNOWN_TICK_INTERVALS,
--          else 3 s; projectile DoTs; the Frostfire mask; traps)
-- Durations are Era's (LCD); Forever's are assumed the same until checked.
-- Each over-time family has no base damage (false, option a): it counts
-- from its first tick (the combat log), a saved tick, or its tooltip
-- (Forever). Left out on purpose: channels (Wrack), short crowd control
-- (Gouge, Scatter Shot), and TBC-only spells (DDT has no TBC build).
--
-- dots: one slot per tracked debuff family, in the default display order.
--   key, label, color ("aarrggbb"), dot (false: shown, not a DoT), ids,
--   names (matched by name only), cast (the spell a pinned slot recasts),
--   lastUsed (recast the last one cast of the slot), dispelType and
--   excludeSlot (match your debuffs of that type, without that slot's).
-- ranks: [spellID] = {family, damage over time, duration, level learned},
--   base damage without spell power, for the first guess before ticks are
--   learned; false: no base (no first guess). A nil duration: only the
--   tooltip gives one (Forever). A nil level: not in the sources.
-- families: interval (seconds between ticks), school (for
--   GetSpellBonusDamage; its mask, for UNIT_COMBAT, is 2 ^ (school - 1)),
--   coefficient (share of spell power, default duration / 15 at most 1),
--   weights (each tick's share of the average, by tick; the last weight
--   holds after the list), direct (the spell also hits once), finisher
--   (combo points change it), pointDuration ({base, per point} seconds),
--   late (starts when the projectile lands), mask (UNIT_COMBAT's school
--   mask, for a mixed school), ground (a trap: no mob at the cast).
-- checks: what John checks in client: {ids, what}.
-- control: crowd-control spells. key, label, ids, longest (seconds), bar
--   (tracked on the control bar), marker (default raid marker), click (a
--   row click recasts on your focus), plateTimer (a timer under the mob's
--   nameplate), untargeted (no single target: announced only), single (only
--   one of yours can be up at a time: a new cast replaces the old mob's row).
-- macros: name (exact; adopted by name, never a second copy), spell (the ID
--   whose name is cast), known (the control key whose spells you must know),
--   pet (the spell is your pet's: Spells.PetKnows), petFamily (the cast
--   also needs the pet's family, read from the client: Control.MacroBody),
--   condition, shift, marker
--   (the control key whose marker setting the /tm uses). See
--   Macros.FocusCastMacro.

local AGONY_WEIGHTS = {0.5, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1.5}

-- Ranks with no base damage, from {family = {{id, duration, level}, ...}}
-- (built once at load; never changed after).
local function NoBase(families)
    local ranks = {}
    for family, list in pairs(families) do
        for _, entry in ipairs(list) do
            ranks[entry[1]] = {family, false, entry[2], entry[3]}
        end
    end
    return ranks
end

-- Every listed ID of each family, in order (a slot's or a control spell's ids).
local function IDs(...)
    local ids = {}
    for _, list in ipairs({...}) do
        for _, entry in ipairs(list) do
            ids[#ids + 1] = entry[1]
        end
    end
    return ids
end

-- {id, Era duration (LCD), level (WT)}; a nil level is not in WT.
local MOONFIRE = {{8921, 9, 4}, {8924, 12, 10}, {8925, 12, 16}, {8926, 12, 22}, {8927, 12, 28}, {8928, 12, 34},
    {8929, 12, 40}, {9833, 12, 46}, {9834, 12, 52}, {9835, 12, 58}}
-- 5570 is a talent (TFB on Forever).
local INSECT_SWARM = {{5570, 12, nil}, {24974, 12, 30}, {24975, 12, 40}, {24976, 12, 50}, {24977, 12, 60}}
local ROOTS = {{339, 12, 8}, {1062, 15, 18}, {5195, 18, 28}, {5196, 21, 38}, {9852, 24, 48}, {9853, 27, 58}}
local RAKE = {{1822, 9, 24}, {1823, 9, 34}, {1824, 9, 44}, {9904, 9, 54}}
local RIP = {{1079, 12, 20}, {9492, 12, 28}, {9493, 12, 36}, {9752, 12, 44}, {9894, 12, 52}, {9896, 12, 60}}
-- The casts, then the bleed's own debuff IDs (LCD: "Pounce Bleed").
local POUNCE = {{9005, 18, 36}, {9823, 18, 46}, {9827, 18, 56}, {9007, 18, 36}, {9824, 18, 46}, {9826, 18, 56}}
-- Forever only, UNCHECKED: G2G-F's trainer ranks 414644, 1235826, 1235827,
-- then the rest of WT Camelot's Lacerate group (1328617 is TFB's talent).
-- No duration: only the tooltip gives one.
local LACERATE = {{414644, nil, 42}, {1235826, nil, 50}, {1235827, nil, 58}, {1328616, nil, 34}, {1328617, nil, nil},
    {414647, nil, nil}}
-- 25295 is an Era book rank (not in WT).
local SERPENT_STING = {{1978, 15, 4}, {13549, 15, 10}, {13550, 15, 18}, {13551, 15, 26}, {13552, 15, 34},
    {13553, 15, 42}, {13554, 15, 50}, {13555, 15, 58}, {25295, 15, nil}}
-- The trap casts (G2G-F, LCD), then the debuffs they put on a mob (LCD).
local IMMOLATION_TRAP = {{13795, 15, 16}, {14302, 15, 26}, {14303, 15, 36}, {14304, 15, 46}, {14305, 15, 56},
    {13797, 15, 16}, {14298, 15, 26}, {14299, 15, 36}, {14300, 15, 46}, {14301, 15, 56}}
-- 133 is the first rank every Mage starts with; 25306 an Era book rank.
local FIREBALL = {{133, 4, nil}, {143, 6, 6}, {145, 6, 12}, {3140, 8, 18}, {8400, 8, 24}, {8401, 8, 30},
    {8402, 8, 36}, {10148, 8, 42}, {10149, 8, 48}, {10150, 8, 54}, {10151, 8, 60}, {25306, 8, nil}}
-- 11366 is a talent (TFB: "changed" on Forever).
local PYROBLAST = {{11366, 12, nil}, {12505, 12, 24}, {12522, 12, 30}, {12523, 12, 36}, {12524, 12, 42},
    {12525, 12, 48}, {12526, 12, 54}, {18809, 12, 60}}
-- Forever only, UNCHECKED (G2G-F): no duration, only the tooltip gives one.
local FROSTFIRE_BOLT = {{401502, nil, 40}, {1237312, nil, 50}, {1237313, nil, 60}}
-- LCD: +3 s per rank of Improved Shadow Word: Pain (the tracker reads it;
-- the prediction ends at 18, so it errs low).
local SHADOW_WORD_PAIN = {{589, 18, 4}, {594, 18, 10}, {970, 18, 18}, {992, 18, 26}, {2767, 18, 34}, {10892, 18, 42},
    {10893, 18, 50}, {10894, 18, 58}}
-- 2944: the Undead racial on Era, a trainer spell at 20 on Forever (WT Camelot).
local DEVOURING_PLAGUE = {{2944, 24, 20}, {19276, 24, 28}, {19277, 24, 36}, {19278, 24, 44}, {19279, 24, 52},
    {19280, 24, 60}}
local HOLY_FIRE = {{14914, 10, 20}, {15262, 10, 24}, {15263, 10, 30}, {15264, 10, 36}, {15265, 10, 42},
    {15266, 10, 48}, {15267, 10, 54}, {15261, 10, 60}}
-- The duration is by points (pointDuration); 16 is 5 points (LCD's other players' Rupture).
local RUPTURE = {{1943, 16, 20}, {8639, 16, 28}, {8640, 16, 36}, {11273, 16, 44}, {11274, 16, 52}, {11275, 16, 60}}
local GARROTE = {{703, 18, 14}, {8631, 18, 22}, {8632, 18, 30}, {8633, 18, 38}, {11289, 18, 46}, {11290, 18, 54}}
-- 29228 is an Era book rank.
local FLAME_SHOCK = {{8050, 12, 10}, {8052, 12, 18}, {8053, 12, 28}, {10447, 12, 40}, {10448, 12, 52}, {29228, 12, nil}}
local REND = {{772, 9, 4}, {6546, 12, 10}, {6547, 15, 20}, {6548, 18, 30}, {11572, 21, 40}, {11573, 21, 50},
    {11574, 21, 60}}

-- The Forever durations of every new spell are Era's until John checks them.
local FOREVER_DURATIONS = "Forever duration (Era's, from LibClassicDurations, is assumed)"

DyresToolkit.ClassData = {
    WARLOCK = {
        -- Every Warlock family that leaves a debuff on an enemy, except
        -- single-target channels (WTF 1.4.1, Tracker.lua; author-approved).
        dots = {
            -- Forever reworked curses: the slot matches your Curse-type
            -- debuffs, without your Banes; the IDs identify your curse casts.
            {key = "curse", label = "Curse", color = "ff9e40d9", dot = true, lastUsed = "lastCurse",
                dispelType = "Curse", excludeSlot = "bane",
                -- The smart curse (2.7.0): the first rank of each, cast by name.
                smart = {weakness = 702, tongues = 1714, elements = 1490, recklessness = 704},
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
            -- direct: it also hits, so the damage meter's total is not its
            -- ticks alone (DotPredict learns no tick from it on Forever).
            immolate = {interval = 3, school = 3, coefficient = 0.65, direct = true},
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
            -- petFamily: the pet's family in the client's language (2.11.1:
            -- the English "pet:Succubus/Incubus" matched nothing on a French
            -- client).
            {name = "! Seduction", spell = 6358, pet = true, petFamily = true},
        },
    },
    MAGE = {
        -- The over-time part of each; all three start as they land (DIDA).
        dots = {
            {key = "fireball", label = "Fireball", color = "ffff6633", dot = true, cast = 133, ids = IDs(FIREBALL)},
            {key = "pyroblast", label = "Pyroblast", color = "ffffb31a", dot = true, cast = 11366,
                ids = IDs(PYROBLAST)},
            {key = "frostfire", label = "Frostfire Bolt", color = "ffbf99ff", dot = true, cast = 401502,
                ids = IDs(FROSTFIRE_BOLT)},
        },
        ranks = NoBase({fireball = FIREBALL, pyroblast = PYROBLAST, frostfire = FROSTFIRE_BOLT}),
        families = {
            fireball = {interval = 2, school = 3, direct = true, late = true},
            pyroblast = {interval = 3, school = 3, direct = true, late = true},
            -- Fire for spell power; UNIT_COMBAT reports Fire + Frost (DIDA).
            frostfire = {interval = 3, school = 3, mask = 20, direct = true, late = true},
        },
        familyOrder = {"fireball", "pyroblast", "frostfire"},
        -- MTF 1.2.3, Polymorph.lua: Polymorph's ranks, then Pig, Turtle, and Cow.
        control = {
            {key = "polymorph", label = "Polymorph", ids = {118, 12824, 12825, 12826, 28272, 28271, 28270},
                longest = 50, bar = true, marker = 5, click = true, single = true},
        },
        macros = {
            {name = "! Polymorph", spell = 118, known = "polymorph", marker = "polymorph"},
        },
        checks = {
            {ids = {401502, 1237312, 1237313}, what = "Frostfire Bolt (Forever only): the name, the debuff ID, its "
                .. "duration, its tick interval (3 s assumed), and UNIT_COMBAT school 20"},
            {ids = {11366}, what = "Pyroblast on Forever (TalentsForeverBook: changed): the debuff ID and duration"},
            {ids = {133, 11366}, what = FOREVER_DURATIONS},
        },
    },
    DRUID = {
        dots = {
            {key = "moonfire", label = "Moonfire", color = "ff9966ff", dot = true, cast = 8921, ids = IDs(MOONFIRE)},
            {key = "insect", label = "Insect Swarm", color = "ff99cc33", dot = true, cast = 5570,
                ids = IDs(INSECT_SWARM)},
            -- Also on the crowd-control bar (lead decision 3: both).
            {key = "roots", label = "Entangling Roots", color = "ff33aa55", dot = true, cast = 339, ids = IDs(ROOTS)},
            {key = "rake", label = "Rake", color = "ffe6a633", dot = true, cast = 1822, ids = IDs(RAKE)},
            {key = "rip", label = "Rip", color = "ffd93333", dot = true, cast = 1079, ids = IDs(RIP)},
            {key = "pounce", label = "Pounce", color = "ffff8c66", dot = true, cast = 9005, ids = IDs(POUNCE)},
            {key = "lacerate", label = "Lacerate", color = "ffcc6633", dot = true, cast = 414644,
                ids = IDs(LACERATE)},
        },
        ranks = NoBase({moonfire = MOONFIRE, insect = INSECT_SWARM, roots = ROOTS, rake = RAKE, rip = RIP,
            pounce = POUNCE, lacerate = LACERATE}),
        -- 7 arcane, 4 nature, 1 physical. Insect Swarm and Rip tick every 2 s
        -- (DIDA), the rest every 3 s.
        families = {
            moonfire = {interval = 3, school = 7, direct = true},
            insect = {interval = 2, school = 4},
            roots = {interval = 3, school = 4},
            rake = {interval = 3, school = 1, direct = true},
            -- Rip lasts 12 s at any points (LCD); its damage grows with them.
            rip = {interval = 2, school = 1, finisher = true},
            pounce = {interval = 3, school = 1},
            lacerate = {interval = 3, school = 1, direct = true},
        },
        familyOrder = {"moonfire", "insect", "roots", "rake", "rip", "pounce", "lacerate"},
        control = {
            {key = "hibernate", label = "Hibernate", ids = {2637, 18657, 18658}, longest = 40, bar = true, marker = 5,
                click = true},
            {key = "roots", label = "Entangling Roots", ids = IDs(ROOTS), longest = 27, bar = true},
        },
        macros = {
            {name = "! Hibernate", spell = 2637, known = "hibernate", marker = "hibernate"},
        },
        checks = {
            {ids = IDs(LACERATE), what = "Lacerate (Forever only): which ID the debuff shows, its duration, and its "
                .. "tick interval (3 s assumed)"},
            {ids = {9007, 9824, 9826}, what = "Pounce Bleed's debuff IDs on Forever (Era's, from LCD, assumed)"},
            {ids = {8921, 5570, 339, 1822, 1079, 9005, 2637}, what = FOREVER_DURATIONS},
        },
    },
    HUNTER = {
        dots = {
            {key = "serpent", label = "Serpent Sting", color = "ff66cc33", dot = true, cast = 1978,
                ids = IDs(SERPENT_STING)},
            {key = "trap", label = "Immolation Trap", color = "ffff6619", dot = true, cast = 13795,
                ids = IDs(IMMOLATION_TRAP)},
        },
        ranks = NoBase({serpent = SERPENT_STING, trap = IMMOLATION_TRAP}),
        families = {
            -- Starts as the sting lands (DIDA).
            serpent = {interval = 3, school = 4, late = true},
            -- The trap springs later on whoever walks in (DIDA): the Era
            -- combat log starts it at its debuff; never from the cast.
            trap = {interval = 3, school = 3, ground = true},
        },
        familyOrder = {"serpent", "trap"},
        -- Freezing Trap has no mob at the cast: announced only.
        control = {
            {key = "scarebeast", label = "Scare Beast", ids = {1513, 14326, 14327}, longest = 20, bar = true},
            -- Era: a talent (LCD); 24335 is G2G-F's Forever ID.
            {key = "wyvern", label = "Wyvern Sting", ids = {19386, 24132, 24133, 24335}, longest = 12, bar = true},
            {key = "freezingtrap", label = "Freezing Trap", ids = {1499, 14310, 14311}, untargeted = true},
        },
        macros = {},
        checks = {
            {ids = {24335}, what = "Wyvern Sting on Forever: the name, the debuff ID, and its duration (12 s on Era)"},
            {ids = {13797, 14298, 14299, 14300, 14301}, what = "Immolation Trap's debuff IDs on Forever (Era's, "
                .. "from LCD, assumed)"},
            {ids = {1978, 13795, 1513}, what = FOREVER_DURATIONS},
        },
    },
    PRIEST = {
        dots = {
            {key = "pain", label = "Shadow Word: Pain", color = "ffb34dff", dot = true, cast = 589,
                ids = IDs(SHADOW_WORD_PAIN)},
            {key = "plague", label = "Devouring Plague", color = "ff80994d", dot = true, cast = 2944,
                ids = IDs(DEVOURING_PLAGUE)},
            {key = "holyfire", label = "Holy Fire", color = "ffffe680", dot = true, cast = 14914,
                ids = IDs(HOLY_FIRE)},
        },
        ranks = NoBase({pain = SHADOW_WORD_PAIN, plague = DEVOURING_PLAGUE, holyfire = HOLY_FIRE}),
        -- 6 shadow, 2 holy; Holy Fire ticks every 2 s (DIDA).
        families = {
            pain = {interval = 3, school = 6},
            plague = {interval = 3, school = 6},
            holyfire = {interval = 2, school = 2, direct = true},
        },
        familyOrder = {"pain", "plague", "holyfire"},
        control = {
            {key = "shackle", label = "Shackle Undead", ids = {9484, 9485, 10955}, longest = 50, bar = true,
                marker = 5, click = true},
            {key = "scream", label = "Psychic Scream", ids = {8122, 8124, 10888, 10890}, untargeted = true},
        },
        macros = {
            {name = "! Shackle", spell = 9484, known = "shackle", marker = "shackle"},
        },
        checks = {
            {ids = {2944}, what = "Devouring Plague: the Undead racial on Era, a trainer spell at 20 on Forever "
                .. "(WT Camelot)"},
            {ids = {589, 2944, 14914, 9484}, what = FOREVER_DURATIONS},
        },
    },
    ROGUE = {
        dots = {
            {key = "rupture", label = "Rupture", color = "ffcc1a1a", dot = true, cast = 1943, ids = IDs(RUPTURE)},
            {key = "garrote", label = "Garrote", color = "ffe64d4d", dot = true, cast = 703, ids = IDs(GARROTE)},
        },
        ranks = NoBase({rupture = RUPTURE, garrote = GARROTE}),
        families = {
            -- 6 s plus 2 s per point (LCD); ticks every 2 s (DIDA).
            rupture = {interval = 2, school = 1, finisher = true, pointDuration = {6, 2}},
            garrote = {interval = 3, school = 1},
        },
        familyOrder = {"rupture", "garrote"},
        control = {
            {key = "sap", label = "Sap", ids = {6770, 2070, 11297}, longest = 45, bar = true, marker = 5,
                click = true},
            {key = "blind", label = "Blind", ids = {2094}, longest = 10, bar = true},
        },
        macros = {
            {name = "! Sap", spell = 6770, known = "sap", marker = "sap"},
        },
        checks = {
            {ids = {2094}, what = "Blind on Forever: in Good-to-Go's class list, not a trainer spell there"},
            {ids = {1943, 703, 6770}, what = FOREVER_DURATIONS},
        },
    },
    SHAMAN = {
        -- No crowd control on either client (Hex is not there).
        dots = {
            {key = "flameshock", label = "Flame Shock", color = "ffff4d1a", dot = true, cast = 8050,
                ids = IDs(FLAME_SHOCK)},
        },
        ranks = NoBase({flameshock = FLAME_SHOCK}),
        families = {flameshock = {interval = 3, school = 3, direct = true}},
        familyOrder = {"flameshock"},
        control = {},
        macros = {},
        checks = {
            {ids = {8050}, what = FOREVER_DURATIONS},
        },
    },
    WARRIOR = {
        dots = {
            {key = "rend", label = "Rend", color = "ffb31a1a", dot = true, cast = 772, ids = IDs(REND)},
        },
        ranks = NoBase({rend = REND}),
        families = {rend = {interval = 3, school = 1}},
        familyOrder = {"rend"},
        -- Intimidating Shout has no single target: announced only. Hamstring
        -- (John, 2026-11-17: "add Warrior Hamstring to CC abilities that can
        -- be on more than one mob"): a slow, not single, so one bar per mob.
        -- IDs and 15 s: LCD; the same three ranks in G2G-F (trainer, levels
        -- 8, 32, 54) and WT (Era and Forever). No marker and no macro.
        control = {
            {key = "shout", label = "Intimidating Shout", ids = {5246}, untargeted = true},
            {key = "hamstring", label = "Hamstring", ids = {1715, 7372, 7373}, longest = 15, bar = true},
        },
        macros = {},
        checks = {
            {ids = {772, 1715}, what = FOREVER_DURATIONS},
        },
    },
    PALADIN = {
        -- No DoTs on the Does It Die list.
        dots = {},
        ranks = {},
        families = {},
        familyOrder = {},
        control = {
            -- LCD lists rank 3 as 5627 twice; G2G-F gives 10326.
            {key = "turnundead", label = "Turn Undead", ids = {2878, 5627, 10326}, longest = 20, bar = true},
            -- Era: a talent (LCD).
            {key = "repentance", label = "Repentance", ids = {20066}, longest = 6, bar = true, marker = 5},
        },
        macros = {
            {name = "! Repentance", spell = 20066, known = "repentance", marker = "repentance"},
        },
        checks = {
            {ids = {20066}, what = "Repentance on Forever (TalentsForeverBook: moved): the name and its duration"},
            {ids = {10326}, what = "Turn Undead rank 3's ID (G2G-F; LCD has a typo)"},
            {ids = {2878}, what = FOREVER_DURATIONS},
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
