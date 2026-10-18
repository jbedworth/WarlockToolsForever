local addonName, WTF = ...

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

-- Chime sounds: the client's own interface sounds, by SOUNDKIT name, from the
-- pinned SoundKitConstants. A name the client lacks is left out of the list.
WTF.CHIME_SOUNDS = {
    -- Dyre's Picks, first (author-approved): the AddOn's own sounds, shipped in
    -- Sounds/ with the shield display's break sounds and played by file.
    {key = "effectfadingslow", label = "Dyre's Picks: Fading slow disappear", file = "FadingSlowDisappear.mp3"},
    {key = "effectblowswoosh", label = "Dyre's Picks: Disappear blow swoosh", file = "DisappearBlowSwoosh.mp3"},
    {key = "effectcartoonvanish", label = "Dyre's Picks: Cartoon vanish", file = "CartoonVanish.mp3"},
    {key = "effectdisappear", label = "Dyre's Picks: Disappear", file = "Disappear.mp3"},
    {key = "effectmagical", label = "Dyre's Picks: Magical disappear", file = "MagicalDisappear.mp3"},
    {key = "effectdisappearshort", label = "Dyre's Picks: Disappear (short)", file = "DisappearShort.wav"},
    {key = "effectdisappearingswoosh", label = "Dyre's Picks: Disappearing swoosh", file = "DisappearingSwoosh.wav"},
    {key = "effectteleportvanish", label = "Dyre's Picks: Teleport warp vanish", file = "TeleportWarpVanish.wav"},
    {key = "effectslowswoosh", label = "Dyre's Picks: Slow swoosh", file = "SlowSwoosh.wav"},
    -- The client's interface sounds, by SOUNDKIT name.
    {key = "mapping", label = "Interface: Map ping", kit = "MAP_PING"},
    {key = "whisper", label = "Interface: Whisper", kit = "TELL_MESSAGE"},
    {key = "invite", label = "Interface: Group invite", kit = "IG_PLAYER_INVITE"},
    {key = "readycheck", label = "Interface: Ready check", kit = "READY_CHECK"},
    {key = "raidwarning", label = "Interface: Raid warning", kit = "RAID_WARNING"},
    {key = "toast", label = "Interface: Friend toast", kit = "UI_BNET_TOAST"},
    {key = "talent", label = "Interface: Talent ready", kit = "UI_ORDERHALL_TALENT_READY_TOAST"},
    {key = "click", label = "Interface: Soft click", kit = "UI_IG_STORE_PAGE_NAV_BUTTON"},
    {key = "auction", label = "Interface: Auction bell", kit = "AUCTION_WINDOW_OPEN"},
    {key = "alarm", label = "Interface: Alarm clock", kit = "ALARM_CLOCK_WARNING_2"},
    -- The Cooldown Manager's alert sounds, by sound kit ID and in its categories,
    -- generated from the pinned Blizzard_CooldownViewer/CooldownViewerSoundAlertData.lua
    -- (author-approved: the same scheme, both sets in every dropdown). Names as
    -- Blizzard's comments give them, "Guiter" corrected; categories as its menu
    -- names them (War2 and War3 show as "Warcraft 2" and "Warcraft 3").
    {key = "animalscat", label = "Animals: Cat", id = 316401},
    {key = "animalschicken", label = "Animals: Chicken", id = 316406},
    {key = "animalscow", label = "Animals: Cow", id = 316407},
    {key = "animalsgnoll", label = "Animals: Gnoll", id = 316409},
    {key = "animalsgoat", label = "Animals: Goat", id = 316715},
    {key = "animalslion", label = "Animals: Lion", id = 316411},
    {key = "animalspanther", label = "Animals: Panther", id = 316412},
    {key = "animalsrattlesnake", label = "Animals: Rattlesnake", id = 316413},
    {key = "animalssheep", label = "Animals: Sheep", id = 316414},
    {key = "animalswolf", label = "Animals: Wolf", id = 316415},
    {key = "devicesboathorn", label = "Devices: Boat Horn", id = 316442},
    {key = "devicesairhorn", label = "Devices: Air Horn", id = 316436},
    {key = "devicesbikehorn", label = "Devices: Bike Horn", id = 316713},
    {key = "devicescashregister", label = "Devices: Cash Register", id = 316446},
    {key = "devicesjackpotbell", label = "Devices: Jackpot Bell", id = 316717},
    {key = "devicesjackpotcoins", label = "Devices: Jackpot Coins", id = 316718},
    {key = "devicesjackpotfail", label = "Devices: Jackpot Fail", id = 316719},
    {key = "devicesrotaryphonedial", label = "Devices: Rotary Phone Dial", id = 316433},
    {key = "devicesrotaryphonering", label = "Devices: Rotary Phone Ring", id = 316492},
    {key = "devicesstovepipe", label = "Devices: Stove Pipe", id = 316425},
    {key = "devicestrashcanlid", label = "Devices: Trashcan Lid", id = 316430},
    {key = "impactsanvilstrike", label = "Impacts: Anvil Strike", id = 316528},
    {key = "impactsbubblesmash", label = "Impacts: Bubble Smash", id = 316419},
    {key = "impactslowthud", label = "Impacts: Low Thud", id = 316531},
    {key = "impactsmetalclanks", label = "Impacts: Metal Clanks", id = 316532},
    {key = "impactsmetalrattle", label = "Impacts: Metal Rattle", id = 316486},
    {key = "impactsmetalscrape", label = "Impacts: Metal Scrape", id = 316484},
    {key = "impactsmetalwarble", label = "Impacts: Metal Warble", id = 316536},
    {key = "impactspopclick", label = "Impacts: Pop Click", id = 316434},
    {key = "impactsstrangeclang", label = "Impacts: Strange Clang", id = 316453},
    {key = "impactsswordscrape", label = "Impacts: Sword Scrape", id = 316535},
    {key = "instrumentsbellring", label = "Instruments: Bell Ring", id = 316493},
    {key = "instrumentsbelltrill", label = "Instruments: Bell Trill", id = 316712},
    {key = "instrumentsbrass", label = "Instruments: Brass", id = 316722},
    {key = "instrumentschimeascending", label = "Instruments: Chime Ascending", id = 316447},
    {key = "instrumentsguitarchug", label = "Instruments: Guitar Chug", id = 316477},
    {key = "instrumentsguitarpinch", label = "Instruments: Guitar Pinch", id = 316482},
    {key = "instrumentspitchpipedistressed", label = "Instruments: Pitch Pipe Distressed", id = 316509},
    {key = "instrumentspitchpipenote", label = "Instruments: Pitch Pipe Note", id = 316501},
    {key = "instrumentssynthbig", label = "Instruments: Synth Big", id = 316540},
    {key = "instrumentssynthbuzz", label = "Instruments: Synth Buzz", id = 316476},
    {key = "instrumentssynthhigh", label = "Instruments: Synth High", id = 316460},
    {key = "instrumentswarhorn", label = "Instruments: Warhorn", id = 316723},
    {key = "shortbellstrike", label = "Short: Bell Strike", id = 353392},
    {key = "shortbelltree", label = "Short: Bell Tree", id = 353387},
    {key = "shortbigpot", label = "Short: Big Pot", id = 353388},
    {key = "shortblades", label = "Short: Blades", id = 353389},
    {key = "shortcoffeemug", label = "Short: Coffee Mug", id = 353424},
    {key = "shortcowbell", label = "Short: Cow Bell", id = 353393},
    {key = "shortfingersnap", label = "Short: Finger Snap", id = 353395},
    {key = "shortguitar", label = "Short: Guitar", id = 353404},
    {key = "shortkalimba", label = "Short: Kalimba", id = 353405},
    {key = "shortmetalbladedrop", label = "Short: Metal Blade Drop", id = 353406},
    {key = "shortmetalbladeonrod", label = "Short: Metal Blade On Rod", id = 353407},
    {key = "shortmetalimpact", label = "Short: Metal Impact", id = 353408},
    {key = "shortminiwoodxylophone", label = "Short: Mini Wood Xylophone", id = 353410},
    {key = "shortpapercup", label = "Short: Paper Cup", id = 353425},
    {key = "shortsheetmetal", label = "Short: Sheet Metal", id = 353417},
    {key = "shortstovepipe", label = "Short: Stove Pipe", id = 353419},
    {key = "shortstovepipeblade", label = "Short: Stove Pipe Blade", id = 353420},
    {key = "shortswordshing", label = "Short: Sword Shing", id = 353421},
    {key = "shortsynthbleep", label = "Short: Synth Bleep", id = 353402},
    {key = "shortsynthblurp", label = "Short: Synth Blurp", id = 353400},
    {key = "shortsyntherror", label = "Short: Synth Error", id = 353397},
    {key = "shortsynthhigh", label = "Short: Synth High", id = 353399},
    {key = "shorttriangle", label = "Short: Triangle", id = 353423},
    {key = "shortwaterdrop", label = "Short: Water Drop", id = 353426},
    {key = "shortwinebottle", label = "Short: Wine Bottle", id = 353427},
    {key = "shortwoodxylophone", label = "Short: Wood Xylophone", id = 353428},
    {key = "war2abstractwhoosh", label = "Warcraft 2: Abstract Whoosh", id = 316731},
    {key = "war2choir", label = "Warcraft 2: Choir", id = 316733},
    {key = "war2construction", label = "Warcraft 2: Construction", id = 316735},
    {key = "war2magicchimes", label = "Warcraft 2: Magic Chimes", id = 316736},
    {key = "war2pigsqueal", label = "Warcraft 2: Pig Squeal", id = 316745},
    {key = "war2saws", label = "Warcraft 2: Saws", id = 316738},
    {key = "war2seal", label = "Warcraft 2: Seal", id = 316746},
    {key = "war2slow", label = "Warcraft 2: Slow", id = 316748},
    {key = "war2smith", label = "Warcraft 2: Smith", id = 316749},
    {key = "war2synthstinger", label = "Warcraft 2: Synth Stinger", id = 316739},
    {key = "war2trumpetrally", label = "Warcraft 2: Trumpet Rally", id = 316740},
    {key = "war2zippymagic", label = "Warcraft 2: Zippy Magic", id = 316737},
    {key = "war3bell", label = "Warcraft 3: Bell", id = 316773},
    {key = "war3crunchybell", label = "Warcraft 3: Crunchy Bell", id = 316774},
    {key = "war3drumsplash", label = "Warcraft 3: Drum Splash", id = 316768},
    {key = "war3error", label = "Warcraft 3: Error", id = 316775},
    {key = "war3fanfare", label = "Warcraft 3: Fanfare", id = 316769},
    {key = "war3gateopen", label = "Warcraft 3: Gate Open", id = 316776},
    {key = "war3gold", label = "Warcraft 3: Gold", id = 316770},
    {key = "war3magicshimmer", label = "Warcraft 3: Magic Shimmer", id = 316778},
    {key = "war3ringout", label = "Warcraft 3: Ringout", id = 316771},
    {key = "war3rooster", label = "Warcraft 3: Rooster", id = 316765},
    {key = "war3shimmerbell", label = "Warcraft 3: Shimmer Bell", id = 316779},
    {key = "war3wolfhowl", label = "Warcraft 3: Wolf Howl", id = 316766},
    -- The game's text-to-speech says the spell, as a spoken alert does,
    -- last as in the Cooldown Manager's menu.
    {key = "voice", label = "Text to Speech", voice = true},
}
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

local function ValidSound(key)
    for _, sound in ipairs(WTF.CHIME_SOUNDS) do
        if sound.key == key then
            return key
        end
    end
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
        clean.sounds[chime.key] = ValidSound(sounds[chime.key]) or WTF.DEFAULT_CHIME_SOUND
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

-- The effect sounds ship with the AddOn; the client plays no game sound by
-- path, but plays an AddOn's own file.
local SOUND_FOLDER = "Interface\\AddOns\\" .. addonName .. "\\Sounds\\"

local function SoundFile(key)
    for _, sound in ipairs(WTF.CHIME_SOUNDS) do
        if sound.key == key and sound.file then
            return SOUND_FOLDER .. sound.file
        end
    end
end

local function SoundKit(key)
    for _, sound in ipairs(WTF.CHIME_SOUNDS) do
        if sound.key == key then
            if sound.id then
                return sound.id
            end
            if type(SOUNDKIT) == "table" and type(SOUNDKIT[sound.kit]) == "number" then
                return SOUNDKIT[sound.kit]
            end
        end
    end
end

-- The game's text-to-speech, with the voice, speed, and volume the player
-- set for it. C_VoiceChat.SpeakText accepts calls from AddOn code.
local DEFAULT_SPEECH_VOLUME = 100

local function SpeechVoice()
    if type(C_VoiceChat) ~= "table" or type(C_VoiceChat.SpeakText) ~= "function" then
        return nil
    end
    if type(C_TTSSettings) == "table" and type(C_TTSSettings.GetVoiceOptionID) == "function"
        and type(Enum) == "table" and type(Enum.TtsVoiceType) == "table" then
        local voiceID = C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard)
        if type(voiceID) == "number" then
            return voiceID
        end
    end
    local voices = type(C_VoiceChat.GetTtsVoices) == "function" and C_VoiceChat.GetTtsVoices()
    local first = type(voices) == "table" and voices[1]
    return type(first) == "table" and first.voiceID or nil
end

local function Speak(text)
    local voiceID = SpeechVoice()
    if not voiceID then
        return
    end
    local settings = type(C_TTSSettings) == "table" and C_TTSSettings
    local rate = settings and type(settings.GetSpeechRate) == "function" and settings.GetSpeechRate() or 0
    local volume = settings and type(settings.GetSpeechVolume) == "function" and settings.GetSpeechVolume()
        or DEFAULT_SPEECH_VOLUME
    C_VoiceChat.SpeakText(voiceID, text, rate, volume, true)
end

local function SoundAvailable(sound)
    if sound.file then
        return type(PlaySoundFile) == "function"
    end
    if sound.voice then
        return SpeechVoice() ~= nil
    end
    return SoundKit(sound.key) ~= nil
end

-- The sound choices this client has.
function WTF.AvailableChimeSounds()
    local available = {}
    for _, sound in ipairs(WTF.CHIME_SOUNDS) do
        if SoundAvailable(sound) then
            available[#available + 1] = sound
        end
    end
    return available
end

-- A sound's group and its name within it, from its label "Group: Name".
function WTF.ChimeSoundParts(sound)
    local group, name = sound.label:match("^(.-): (.+)$")
    return group, name or sound.label
end

-- The available sounds as ordered groups: {{name = "Interface", sounds = {...}}, ...}.
function WTF.ChimeSoundGroups()
    local groups, byName = {}, {}
    for _, sound in ipairs(WTF.AvailableChimeSounds()) do
        -- A sound without a group (Text to Speech) is a group of its own.
        local group = WTF.ChimeSoundParts(sound) or sound.label
        if not byName[group] then
            byName[group] = {name = group, sounds = {}}
            groups[#groups + 1] = byName[group]
        end
        local sounds = byName[group].sounds
        sounds[#sounds + 1] = sound
    end
    return groups
end

-- A saved sound key's full label, "Short: Bell Strike".
function WTF.ChimeSoundLabel(key)
    for _, sound in ipairs(WTF.CHIME_SOUNDS) do
        if sound.key == key then
            return sound.label
        end
    end
end

-- A chime's own sound: a client sound, or the spell said aloud.
local function Play(chime)
    local key = WTF.db.chimes.sounds[chime.key]
    if key == "voice" then
        Speak(chime.label .. " ready")
        return
    end
    local file = SoundFile(key)
    if file then
        if type(PlaySoundFile) == "function" then
            PlaySoundFile(file, "Master")
        end
        return
    end
    local kit = SoundKit(key) or SoundKit(WTF.DEFAULT_CHIME_SOUND)
    if kit and type(PlaySound) == "function" then
        PlaySound(kit, "Master")
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
    Report(string.format("voice=%s lead=%s lastCast=%s", tostring(SpeechVoice()),
        tostring(WTF.db and WTF.db.chimes.lead),
        last and string.format("%s %.1fs ago", last.key, now - last.time) or "none"))
    for _, entry in ipairs(chimes.log) do
        Report(string.format("log %.1fs ago %s", now - entry.time, entry.text))
    end
end
