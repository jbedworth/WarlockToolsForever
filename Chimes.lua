local _, WTF = ...

-- Seconds before a cooldown ends that its chime plays, so you can act the
-- moment it is ready.
WTF.CHIME_LEAD_MIN = 0
WTF.CHIME_LEAD_MAX = 3
WTF.CHIME_LEAD_STEP = 0.5
WTF.DEFAULT_CHIME_LEAD = 0.5

-- Spells that can chime when ready again: Classic IDs, matched by name so every
-- rank counts. cooldown is the Classic length in seconds, used until WTF reads
-- the real one out of combat. Soulstone Resurrection is the Soulstone's use.
-- Forever names Curse of Doom Bane of Doom. Every spell starts on Talent
-- ready; players change any of them.
WTF.CHIME_SPELLS = {
    {key = "deathcoil", spell = 6789, label = "Death Coil", cooldown = 120, on = true},
    {key = "howl", spell = 5484, label = "Howl of Terror", cooldown = 40, on = true},
    {key = "shadowward", spell = 6229, label = "Shadow Ward", cooldown = 30, on = true},
    {key = "soulstone", spell = 20707, label = "Soulstone Resurrection", cooldown = 1800, on = true},
    {key = "feldomination", spell = 18708, label = "Fel Domination", cooldown = 900, on = true},
    {key = "shadowburn", spell = 17877, label = "Shadowburn", cooldown = 15, on = false},
    {key = "conflagrate", spell = 17962, label = "Conflagrate", cooldown = 10, on = false},
    {key = "amplifycurse", spell = 18288, label = "Amplify Curse", cooldown = 180, on = false},
    {key = "doom", spell = 603, label = "Bane of Doom", cooldown = 60, on = false},
    {key = "inferno", spell = 1122, label = "Inferno", cooldown = 3600, on = false},
}

-- Chime sounds come from Dyre's Sounds, by its keys (Interface: Talent ready).
WTF.DEFAULT_CHIME_SOUND = "talent"

-- A cooldown WTF read in client, kept only when plausible.
local LEARNED_MIN = 1.5
local LEARNED_MAX = 3600

function WTF.SanitizeChimeLead(value)
    if type(value) ~= "number" or value ~= value then
        return WTF.DEFAULT_CHIME_LEAD
    end
    local stepped = math.floor(value / WTF.CHIME_LEAD_STEP + 0.5) * WTF.CHIME_LEAD_STEP
    return math.max(WTF.CHIME_LEAD_MIN, math.min(WTF.CHIME_LEAD_MAX, stepped))
end

-- A saved chime sound in the library's spelling (it maps the "effect..." and
-- other keys WTF saved), else the default. Without the library a saved key is
-- kept, so a missing library never resets a choice.
function WTF.SanitizeChimeSound(key)
    if type(key) ~= "string" then
        return WTF.DEFAULT_CHIME_SOUND
    end
    local library = WTF.SoundLibrary()
    if not library then
        return key
    end
    return library.Resolve(key) or WTF.DEFAULT_CHIME_SOUND
end

-- The saved chime settings, repaired; Core calls this from SanitizeDB.
function WTF.SanitizeChimes(chimes)
    chimes = type(chimes) == "table" and chimes or {}
    local spells = type(chimes.spells) == "table" and chimes.spells or {}
    local learned = type(chimes.learned) == "table" and chimes.learned or {}
    local sounds = type(chimes.sounds) == "table" and chimes.sounds or {}
    local clean = {
        enabled = chimes.enabled ~= false,
        lead = WTF.SanitizeChimeLead(chimes.lead),
        spells = {},
        sounds = {},
        learned = {},
    }
    for _, chime in ipairs(WTF.CHIME_SPELLS) do
        if type(spells[chime.key]) == "boolean" then
            clean.spells[chime.key] = spells[chime.key]
        else
            clean.spells[chime.key] = chime.on
        end
        clean.sounds[chime.key] = WTF.SanitizeChimeSound(sounds[chime.key])
        local seconds = learned[chime.key]
        if type(seconds) == "number" and seconds >= LEARNED_MIN and seconds <= LEARNED_MAX then
            clean.learned[chime.key] = seconds
        end
    end
    return clean
end

-- Cooldown chimes (author-approved, as MTF's): a sound just before Death Coil,
-- Howl of Terror, and your other chosen spells are ready again, also in
-- combat. The client hides cooldown details from AddOns in combat and offers
-- no event when a cooldown ends, and the combat log is closed to AddOns. So
-- WTF times each cooldown itself from your own cast, which stays readable in
-- combat: it uses the length it last read for that spell out of combat, else
-- Classic's, and right after an out-of-combat cast it reads the real time left.

-- Seconds after a cast before WTF reads its cooldown, once the client has set it.
local READ_DELAY = 0.1
-- Shorter cooldowns are the global cooldown, not the spell's own.
local GLOBAL_COOLDOWN = 1.5

local chimes = {byName = {}, generation = {}, readyAt = {}, lastCast = nil, log = {}}
-- The latest casts, schedules, and chimes, for /wtf debug_chimes.
local LOG_SIZE = 12

local function Log(text)
    table.insert(chimes.log, 1, {time = GetTime(), text = text})
    chimes.log[LOG_SIZE + 1] = nil
end

local function Timers()
    return type(C_Timer) == "table" and type(C_Timer.After) == "function"
end

-- A chime's own sound through Dyre's Sounds; Text to Speech says
-- "<Spell> ready". A sound that cannot play (no text-to-speech voice) falls
-- back to the default. Without the library nothing plays, and WTF says once
-- what to install. With Dyre's Cooldown Chimes installed, it plays the chimes.
local function Play(chime)
    if WTF.ChimesStandAside() then
        return
    end
    local library = WTF.SoundLibrary()
    if not library then
        WTF.ReportMissingSounds()
        return
    end
    local speech = chime.label .. " ready"
    if not library.Play(WTF.db.chimes.sounds[chime.key], speech) then
        library.Play(WTF.DEFAULT_CHIME_SOUND, speech)
    end
end

-- Plays a chime's sound once, so the settings page can preview it.
function WTF.PreviewChime(key)
    for _, chime in ipairs(WTF.CHIME_SPELLS) do
        if chime.key == key then
            Play(chime)
        end
    end
end

local function Cancel(chime)
    chimes.generation[chime.key] = (chimes.generation[chime.key] or 0) + 1
    chimes.readyAt[chime.key] = nil
end

-- Chimes `lead` seconds before a cooldown of this many seconds ends; a newer
-- schedule for the same spell replaces this one.
local function Schedule(chime, seconds, source)
    Cancel(chime)
    local generation = chimes.generation[chime.key]
    chimes.readyAt[chime.key] = GetTime() + seconds
    Log(string.format("scheduled %s #%d in %.1fs (%s)", chime.key, generation, seconds, source))
    C_Timer.After(math.max(0, seconds - WTF.db.chimes.lead), function()
        if chimes.generation[chime.key] ~= generation then
            return
        end
        chimes.readyAt[chime.key] = nil
        if WTF.db.chimes.enabled and WTF.db.chimes.spells[chime.key] then
            Log(string.format("played %s #%d", chime.key, generation))
            Play(chime)
        end
    end)
end

-- The cooldown as the client reports it, or nil while it is secret or idle.
local function ReadCooldown(spellID)
    if type(C_Spell.GetSpellCooldown) ~= "function" then
        return nil
    end
    local info = C_Spell.GetSpellCooldown(spellID)
    if type(info) ~= "table" then
        return nil
    end
    local start, duration = info.startTime, info.duration
    if WTF.IsSecret(start) or WTF.IsSecret(duration) or type(start) ~= "number" or type(duration) ~= "number"
        or duration <= GLOBAL_COOLDOWN then
        return nil
    end
    return duration, start + duration - GetTime()
end

-- Right after a cast, the real cooldown: learned for next time, and the
-- chime rescheduled to it.
local function Refine(chime, spellID)
    local duration, left = ReadCooldown(spellID)
    if not duration then
        return
    end
    WTF.db.chimes.learned[chime.key] = math.floor(duration * 10 + 0.5) / 10
    if left > 0 then
        Schedule(chime, left, "read")
    end
end

local function OnCast(spellID)
    if WTF.IsSecret(spellID) or type(spellID) ~= "number" then
        return
    end
    local chime = chimes.byName[C_Spell.GetSpellName(spellID)]
    if not chime then
        return
    end
    chimes.lastCast = {key = chime.key, spell = spellID, time = GetTime()}
    Log(string.format("cast %s spell=%d", chime.key, spellID))
    local seconds = WTF.db.chimes.learned[chime.key] or chime.cooldown
    if seconds then
        Schedule(chime, seconds, WTF.db.chimes.learned[chime.key] and "learned" or "classic")
    end
    C_Timer.After(READ_DELAY, function() Refine(chime, spellID) end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, _, _, _, spellID)
    OnCast(spellID)
end)

function WTF.InitializeChimes()
    -- Dyre's Cooldown Chimes plays them; WTF times nothing and keeps its settings.
    if WTF.ChimesStandAside() then
        return
    end
    if not Timers() then
        WTF.Report("Cooldown chimes stay off: this client lacks C_Timer.After.")
        return
    end
    for _, chime in ipairs(WTF.CHIME_SPELLS) do
        local name = C_Spell.GetSpellName(chime.spell)
        if name then
            chimes.byName[name] = chime
        end
    end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
end

local SOUNDS_STATES = {ok = "installed", missing = "missing", old = "too old"}

-- /wtf debug_chimes: each chime spell as the client knows it, whether its
-- cooldown is readable now, the length WTF uses, and the sound.
function WTF.ReportChimesDebug()
    local function Report(text)
        WTF.Report("debug_chimes " .. text)
    end
    local secrecy = type(C_Secrets) == "table" and type(C_Secrets.GetSpellCooldownSecrecy) == "function"
    local now = GetTime()
    for _, chime in ipairs(WTF.CHIME_SPELLS) do
        local known = type(C_SpellBook) == "table" and type(C_SpellBook.IsSpellKnown) == "function"
            and C_SpellBook.IsSpellKnown(chime.spell)
        local readAt = WTF.db and WTF.db.chimes.learned[chime.key]
        local duration = ReadCooldown(chime.spell)
        -- The client returns no value for an unknown spell; tostring needs one.
        local name = C_Spell.GetSpellName(chime.spell)
        Report(string.format("%s name=%s known=%s on=%s sound=%s classic=%s learned=%s readNow=%s secrecy=%s readyIn=%s",
            chime.key, tostring(name), tostring(known),
            tostring(WTF.db and WTF.db.chimes.spells[chime.key]), tostring(WTF.db and WTF.db.chimes.sounds[chime.key]),
            tostring(chime.cooldown), tostring(readAt),
            tostring(duration), secrecy and WTF.Describe(C_Secrets.GetSpellCooldownSecrecy(chime.spell)) or "n/a",
            chimes.readyAt[chime.key] and string.format("%.1fs", chimes.readyAt[chime.key] - now) or "-"))
    end
    local last = chimes.lastCast
    local _, sounds = WTF.SoundLibrary()
    Report(string.format("sounds=%s dyresCooldownChimes=%s lead=%s lastCast=%s", SOUNDS_STATES[sounds],
        tostring(WTF.ChimesStandAside()), tostring(WTF.db and WTF.db.chimes.lead),
        last and string.format("%s %.1fs ago", last.key, now - last.time) or "none"))
    for _, entry in ipairs(chimes.log) do
        Report(string.format("log %.1fs ago %s", now - entry.time, entry.text))
    end
end
