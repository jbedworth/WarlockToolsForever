local addonName, WTF = ...

-- Stones: one button each for Soulstones, Healthstones, Spellstones, and
-- Firestones on a small movable bar. Left-click uses the best stone you carry
-- (a Spellstone or Firestone on your main-hand weapon); right-click creates
-- the best rank you know (for a Healthstone, the best rank your friendly
-- player target can use). The buttons are secure, so they work in combat, but
-- their actions can change only out of combat; changes wait for combat to end.

-- Ranks from lowest to highest: the create spell and the item it makes.
-- Classic's IDs, which Consumable Connoisseur's Forever data confirms in
-- client; Forever removed the Improved Healthstone talent and its stone
-- copies. /wtf debug_stones shows what the client knows.
local SOULSTONES = {
    {spell = 693, items = {5232}},     -- Minor
    {spell = 20752, items = {16892}},  -- Lesser
    {spell = 20755, items = {16893}},  -- Soulstone
    {spell = 20756, items = {16895}},  -- Greater
    {spell = 20757, items = {16896}},  -- Major
}
local HEALTHSTONES = {
    {spell = 6201, items = {5512}},   -- Minor, level 1
    {spell = 6202, items = {5511}},   -- Lesser, level 12
    {spell = 5699, items = {5509}},   -- Healthstone, level 24
    {spell = 11729, items = {5510}},  -- Greater, level 36
    {spell = 11730, items = {9421}},  -- Major, level 48
}
-- On Forever, Spellstones and Firestones are weapon imbues on the main hand
-- that last 60 minutes (Blizzard's Rogue and Warlock class deep dive), not
-- Classic's off-hand items: using the stone applies it to the weapon. Classic's
-- spell and item IDs, which this client's tables keep (Good-to-Go's Forever
-- data, from wago.tools). level: the level the first rank is learned at.
local SPELLSTONES = {
    {spell = 2362, items = {5522}},    -- Spellstone, level 36
    {spell = 17727, items = {13602}},  -- Greater, level 48
    {spell = 17728, items = {13603}},  -- Major, level 60
}
local FIRESTONES = {
    {spell = 6366, items = {1254}},    -- Lesser, level 28
    {spell = 17951, items = {13699}},  -- Firestone, level 36
    {spell = 17952, items = {13700}},  -- Greater, level 46
    {spell = 17953, items = {13701}},  -- Major, level 56
}
-- setting: the db.stones flag that puts the button on the bar.
local WEAPON_STONES = {
    spellstone = {ranks = SPELLSTONES, title = "Spellstone", create = "Create Spellstone", level = 36,
        setting = "showSpellstone", icon = "Interface\\Icons\\INV_Misc_Gem_Sapphire_01"},
    firestone = {ranks = FIRESTONES, title = "Firestone", create = "Create Firestone", level = 28,
        setting = "showFirestone", icon = "Interface\\Icons\\INV_Ammo_FireTar"},
}
local WEAPON_KINDS = {"spellstone", "firestone"}
-- The enchant each stone puts on the weapon, by its ID (Good-to-Go's Forever
-- data: this client's SpellEffect ENCHANT_ITEM_TEMPORARY values). /dyre
-- weapon shows the ID in client; they may change, so they live here only.
local STONE_ENCHANTS = {
    [8059] = "spellstone", [8060] = "spellstone", [8061] = "spellstone",
    [1803] = "firestone", [1823] = "firestone", [1824] = "firestone", [1825] = "firestone",
}
local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local GLOW_SCALE = 1.8
local GLOW_PULSE_SECONDS = 0.8
local GLOW_LOW_ALPHA = 0.35
-- The secure item action's target-slot puts the stone on this slot once the
-- item asks for a target (SecureTemplates.lua, SpellCanTargetItem).
local MAIN_HAND_SLOT = 16
local SOULSTONE_ICON = "Interface\\Icons\\INV_Misc_Orb_04"
local HEALTHSTONE_ICON = "Interface\\Icons\\INV_Stone_04"
local BUTTON_SIZE = 36
local BUTTON_GAP = 6
local PADDING = 6
local GOLD = {1, 0.82, 0}
local BROWN = {0.28, 0.16, 0.07, 0.85}
local DEFAULT_POINT = {"CENTER", "CENTER", 260, -140}
-- Secure buttons run PostClick for both the press and the release.
local REPEAT_MESSAGE_SECONDS = 0.3
-- Seconds a requested trade waits for the trade window to open.
local TRADE_WAIT = 10
local TRADE_SLOT_COUNT = 6
local TRADE_LOG_SIZE = 8

local REQUIRED = {
    {"C_SpellBook", "IsSpellKnown"}, {"C_Item", "GetItemCount"}, {"C_Item", "GetItemInfo"},
    {"_G", "InitiateTrade"}, {"_G", "ClickTradeButton"}, {"_G", "GetTradePlayerItemLink"},
}

local stones = {pending = false, lastMessage = nil, lastMessageTime = 0, tradeLog = {}}

function WTF.CheckStoneCapabilities()
    for _, entry in ipairs(REQUIRED) do
        local namespace = entry[1] == "_G" and _G or _G[entry[1]]
        if type(namespace) ~= "table" or type(namespace[entry[2]]) ~= "function" then
            return false, entry[1] == "_G" and entry[2] or (entry[1] .. "." .. entry[2])
        end
    end
    return true
end

local function Known(spellID)
    return C_SpellBook.IsSpellKnown(spellID) == true
end

local function Carried(itemID)
    return C_Item.GetItemCount(itemID) or 0
end

-- The highest rank whose create spell you know.
local function BestKnownRank(ranks)
    for index = #ranks, 1, -1 do
        if Known(ranks[index].spell) then
            return ranks[index]
        end
    end
end

-- The best stone in your bags: highest rank first, talent versions before base.
local function BestCarriedItem(ranks)
    for index = #ranks, 1, -1 do
        local items = ranks[index].items
        for item = #items, 1, -1 do
            if Carried(items[item]) > 0 then
                return items[item]
            end
        end
    end
end

local function CountCarried(ranks)
    local total = 0
    for _, rank in ipairs(ranks) do
        for _, itemID in ipairs(rank.items) do
            total = total + Carried(itemID)
        end
    end
    return total
end

local function MinLevel(itemID)
    local _, _, _, _, minLevel = C_Item.GetItemInfo(itemID)
    return minLevel
end

-- A friendly player target other than you, by level; nil otherwise.
local function FriendlyPlayerLevel()
    if not UnitExists("target") or not UnitIsPlayer("target") or UnitIsUnit("target", "player")
        or not UnitIsFriend("player", "target") then
        return nil
    end
    local level = UnitLevel("target")
    if WTF.IsSecret(level) or type(level) ~= "number" or level < 1 then
        return nil
    end
    return level
end

-- The best Healthstone you carry that a player of this level can use.
local function BestCarriedItemFor(level)
    for index = #HEALTHSTONES, 1, -1 do
        local items = HEALTHSTONES[index].items
        for item = #items, 1, -1 do
            local required = MinLevel(items[item])
            if Carried(items[item]) > 0 and type(required) == "number" and required <= level then
                return items[item]
            end
        end
    end
end

-- The Healthstone rank to create: the best you know that a friendly player
-- target can use (item level requirement), else the best you know. Each rank
-- is unique in your bags, so a rank you already carry is skipped for the one
-- below it (author-approved, as Consumable Connoisseur does), and creating
-- again makes a second, lower stone instead of failing. Nil when you carry
-- every rank that fits.
function WTF.HealthstoneRankForTarget()
    local level = FriendlyPlayerLevel()
    for index = #HEALTHSTONES, 1, -1 do
        local rank = HEALTHSTONES[index]
        if Known(rank.spell) and Carried(rank.items[1]) == 0 then
            local required = MinLevel(rank.items[1])
            if not level or (type(required) == "number" and required <= level) then
                return rank
            end
        end
    end
end

local buttons = {}

-- The Stones bar as a Dyre's Toolkit widget (1.14.0; John, 2026-11-27: button
-- bars horizontal or vertical, a Toolkit feature; the family plan, 2026-10-20:
-- "all the widget layout, snapping, modifier key move rules, etc., centralized
-- in Dyre's Tools"). Needs Toolkit 2.18.0 (BAR_LAYOUT_VERSION 1): the toolkit
-- places, drags, snaps, scales, and outlines the bar, and lays its buttons out
-- in a row or a column. It reads WTF's saved db.stones.position and
-- db.stones.scale in place: the same {point, relativePoint, x, y} from
-- UIParent, scale first, so the bar loads where it was. Without it (no
-- toolkit, or an older one), the bar is WTF's own frame, as before.
local function BarToolkit()
    local toolkit = WTF.toolkit
    if type(toolkit) == "table" and type(toolkit.CreateWidget) == "function"
            and type(toolkit.AddBarLayoutSetting) == "function"
            and (tonumber(toolkit.BAR_LAYOUT_VERSION) or 0) >= 1 then
        return toolkit
    end
    return nil
end

-- The widget, or nil on the old path (Options adds the Layout row with it).
function WTF.StonesWidget()
    return buttons.widget
end

-- The buttons on the bar, in order: Soulstone and Healthstone always, then
-- each weapon stone whose switch is on (shown greyed until you learn it).
local function ShownButtons()
    local list = {buttons.soulstone, buttons.healthstone}
    for _, kind in ipairs(WEAPON_KINDS) do
        if WTF.db.stones[WEAPON_STONES[kind].setting] then
            list[#list + 1] = buttons[kind]
        end
    end
    return list
end

local function BarWidth(count)
    return PADDING * 2 + BUTTON_SIZE * count + BUTTON_GAP * (count - 1)
end

-- Which weapon stone buttons are on, as text, to lay out again on a change.
local function LayoutKey()
    local key = ""
    for _, kind in ipairs(WEAPON_KINDS) do
        key = key .. (WTF.db.stones[WEAPON_STONES[kind].setting] and "1" or "0")
    end
    return key
end

-- Out of combat only: the buttons are secure.
local function LayoutStoneButtons()
    local list = ShownButtons()
    for _, kind in ipairs(WEAPON_KINDS) do
        buttons[kind]:SetShown(WTF.db.stones[WEAPON_STONES[kind].setting] == true)
    end
    buttons.layoutKey = LayoutKey()
    if buttons.widget then
        buttons.widget:LayoutButtons(list, {size = BUTTON_SIZE, gap = BUTTON_GAP, padding = PADDING})
        return
    end
    buttons.bar:SetSize(BarWidth(#list), PADDING * 2 + BUTTON_SIZE)
    for index, button in ipairs(list) do
        button:ClearAllPoints()
        button:SetPoint("LEFT", buttons.bar, "LEFT", PADDING + (index - 1) * (BUTTON_SIZE + BUTTON_GAP), 0)
    end
end

-- Character macros "WTF Healthstone" and "WTF Soulstone". On Forever, /click
-- does not press AddOn buttons (verified in client), and AddOn code cannot use
-- items, but a macro you own is secure. So WTF writes these macros, as
-- Consumable Connoisseur does, and keeps them current out of combat: left-click
-- uses your best stone, right-click creates the rank the button would. They
-- live in the character tab (WTF is per character) with the question-mark
-- icon, so #showtooltip shows the stone. Creation leaves your last free
-- character slots alone.
local MACRO_ICON = 134400
local MACRO_SLOT_CUSHION = 2
-- Names (author-approved): Consumable Connoisseur's "- Healthstone" style,
-- with "!" to sort before its "-"; macro names hold at most 16 letters.
WTF.STONE_MACROS = {healthstone = "! Healthstone", soulstone = "! Soulstone"}
-- Earlier names, renamed in place so action bar slots keep them.
local OLD_MACRO_NAMES = {
    healthstone = {"!WTF Healthstone", "WTF Healthstone"},
    soulstone = {"!WTF Soulstone", "WTF Soulstone"},
}

local macros = {warned = false}

-- MAX_CHARACTER_MACROS is a global only once Blizzard's Macro window has
-- loaded; the constant table always has it (in client, the missing global
-- silently turned the macros off).
local function CharacterMacroLimit()
    local constants = type(Constants) == "table" and Constants.MacroConsts
    if type(constants) == "table" and type(constants.MAX_CHARACTER_MACROS) == "number" then
        return constants.MAX_CHARACTER_MACROS
    end
    if type(MAX_CHARACTER_MACROS) == "number" then
        return MAX_CHARACTER_MACROS
    end
end

-- The spell name /use (as /cast) needs: on Forever each stone spell has numeric ranks, cast
-- as "Create Healthstone(Rank 2)".
local function CastName(spellID)
    local name = C_Spell.GetSpellName(spellID)
    local subtext = type(C_Spell.GetSpellSubtext) == "function" and C_Spell.GetSpellSubtext(spellID)
    if name and type(subtext) == "string" and subtext ~= "" then
        return name .. "(" .. subtext .. ")"
    end
    return name
end

-- Right-click creates: a Healthstone by its exact rank (for downranking); a
-- Soulstone by its bare name, which casts the best rank known, as
-- Connoisseur's Forever data does.
local function CreateLines(lines, castName)
    if castName then
        lines[#lines + 1] = "/use [btn:2] " .. castName
        lines[#lines + 1] = "/stopmacro [btn:2]"
    end
end

function WTF.HealthstoneMacroBody(rank)
    local best = BestCarriedItem(HEALTHSTONES)
    local shown = best or (rank and rank.items[1]) or HEALTHSTONES[#HEALTHSTONES].items[1]
    local lines = {"#showtooltip item:" .. shown}
    CreateLines(lines, rank and CastName(rank.spell))
    -- Every rank, best first: the first one you carry fires; they share a cooldown.
    for index = #HEALTHSTONES, 1, -1 do
        lines[#lines + 1] = "/use item:" .. HEALTHSTONES[index].items[1]
    end
    return table.concat(lines, "\n")
end

function WTF.SoulstoneMacroBody(rank)
    local best = BestCarriedItem(SOULSTONES)
    local shown = best or (rank and rank.items[1]) or SOULSTONES[#SOULSTONES].items[1]
    local lines = {"#showtooltip item:" .. shown}
    CreateLines(lines, rank and C_Spell.GetSpellName(rank.spell))
    if best then
        lines[#lines + 1] = "/use [@target,help,nodead][@player] item:" .. best
    end
    return table.concat(lines, "\n")
end

local function WriteMacro(name, body, oldNames)
    local index = GetMacroIndexByName(name)
    if index == 0 then
        for _, oldName in ipairs(oldNames) do
            local oldIndex = GetMacroIndexByName(oldName)
            if oldIndex > 0 then
                EditMacro(oldIndex, name, MACRO_ICON, body)
                return
            end
        end
    end
    if index == 0 then
        local _, numCharacter = GetNumMacros()
        if CharacterMacroLimit() - numCharacter <= MACRO_SLOT_CUSHION then
            if not macros.warned then
                macros.warned = true
                WTF.Warn("No free character macro slot for \"" .. name .. "\"; free one and WTF adds it.")
            end
            return
        end
        CreateMacro(name, MACRO_ICON, body, true)
    elseif GetMacroBody(index) ~= body then
        EditMacro(index, name, MACRO_ICON, body)
    end
end

-- The same writer and slot check for other macros (the Control bar's, before
-- its macros moved to the Toolkit in 1.5.0 and to Dyre's Debuff Tracker in 1.11.0).
-- Out of combat only.
function WTF.CharacterMacrosAvailable()
    return macros.available == true
end

function WTF.WriteCharacterMacro(name, body)
    WriteMacro(name, body, {})
end

function WTF.DeleteCharacterMacro(name)
    local index = GetMacroIndexByName(name)
    if index > 0 then
        DeleteMacro(index)
    end
end

-- Macros change only out of combat; ApplyActions runs then.
local function UpdateMacros(soulRank, healthRank)
    if not WTF.db.stones.macros or not macros.available then
        return
    end
    if BestKnownRank(HEALTHSTONES) then
        WriteMacro(WTF.STONE_MACROS.healthstone, WTF.HealthstoneMacroBody(healthRank), OLD_MACRO_NAMES.healthstone)
    end
    if soulRank then
        WriteMacro(WTF.STONE_MACROS.soulstone, WTF.SoulstoneMacroBody(soulRank), OLD_MACRO_NAMES.soulstone)
    end
end

-- Turning the macros off deletes them, out of combat.
function WTF.ApplyStoneMacros()
    if InCombatLockdown() then
        stones.pending = true
        return
    end
    if WTF.db.stones.macros then
        stones.pending = true
        WTF.RefreshStones()
        return
    end
    for kind, name in pairs(WTF.STONE_MACROS) do
        local names = {name}
        for _, oldName in ipairs(OLD_MACRO_NAMES[kind]) do
            names[#names + 1] = oldName
        end
        for _, macroName in ipairs(names) do
            local index = GetMacroIndexByName(macroName)
            if index > 0 then
                DeleteMacro(index)
            end
        end
    end
end

-- The ready glow (John, 2026-11-28: "Once created and one is in your bag and
-- it's not applied, we show the 'glow' reminder around the icon in the bar"):
-- a Spellstone or Firestone button glows while you carry that stone, know it,
-- and your main hand has neither stone on. Another enchant (an oil) is not a
-- stone. The main hand comes from Dyre's Toolkit (WEAPON_ENCHANT_VERSION 1);
-- without it, or before its first read, nothing glows. The glow is a plain
-- texture, not secure, so it changes in combat too.
local weapon = {known = false, stone = nil, id = nil}

local function SetGlow(button, on)
    if not button.glow then
        return
    end
    if on then
        button.glow:Show()
        button.glow.pulse:Play()
    else
        button.glow.pulse:Stop()
        button.glow:Hide()
    end
    button.glowing = on
end

local function UpdateGlows()
    if not buttons.bar then
        return
    end
    local settings = WTF.db.stones
    for _, kind in ipairs(WEAPON_KINDS) do
        local ranks = WEAPON_STONES[kind].ranks
        SetGlow(buttons[kind], settings.enabled and settings.glowStones and weapon.known and not weapon.stone
            and BestKnownRank(ranks) ~= nil and CountCarried(ranks) > 0 or false)
    end
end
WTF.RefreshStoneGlows = UpdateGlows

-- The toolkit's listener: never called for "unknown", so the last glow stays.
local function OnWeaponEnchant(state, id)
    weapon.known = true
    weapon.id = state == "on" and id or nil
    weapon.stone = state == "on" and type(id) == "number" and STONE_ENCHANTS[id] or nil
    UpdateGlows()
end

local function WatchWeapon()
    local toolkit = WTF.toolkit
    if type(toolkit) == "table" and (tonumber(toolkit.WEAPON_ENCHANT_VERSION) or 0) >= 1
            and type(toolkit.OnWeaponEnchantChanged) == "function" then
        toolkit.OnWeaponEnchantChanged(OnWeaponEnchant)
    end
end

local function ApplyActions()
    -- Bags change in combat too; the glow can follow, the actions cannot.
    UpdateGlows()
    if InCombatLockdown() then
        stones.pending = true
        return
    end
    stones.pending = false
    local soulItem = BestCarriedItem(SOULSTONES)
    local soulRank = BestKnownRank(SOULSTONES)
    local healthItem = BestCarriedItem(HEALTHSTONES)
    local healthRank = WTF.HealthstoneRankForTarget()
    -- With a friendly player targeted, left-click gives them a Healthstone:
    -- trade one they can use, or create one for them to trade next.
    local friendLevel = FriendlyPlayerLevel()
    local tradeItem = friendLevel and BestCarriedItemFor(friendLevel)

    local soul, health = buttons.soulstone, buttons.healthstone
    soul:SetAttribute("type1", soulItem and "macro" or nil)
    soul:SetAttribute("macrotext1", soulItem and ("/use [@target,help,nodead][@player] item:" .. soulItem) or nil)
    soul:SetAttribute("type2", soulRank and "spell" or nil)
    soul:SetAttribute("spell2", soulRank and soulRank.spell or nil)
    if friendLevel then
        health.mode = tradeItem and "trade" or "create"
        health:SetAttribute("type1", not tradeItem and healthRank and "spell" or nil)
        health:SetAttribute("spell1", not tradeItem and healthRank and healthRank.spell or nil)
        health:SetAttribute("item1", nil)
    else
        health.mode = "use"
        -- The plain item action, not macro text.
        health:SetAttribute("type1", healthItem and "item" or nil)
        health:SetAttribute("spell1", nil)
        health:SetAttribute("item1", healthItem and ("item:" .. healthItem) or nil)
    end
    health.tradeItem = tradeItem
    -- Middle-click always uses your best Healthstone on yourself, whatever
    -- your target, so a macro can rely on it in combat (author-approved).
    health:SetAttribute("type3", healthItem and "item" or nil)
    health:SetAttribute("item3", healthItem and ("item:" .. healthItem) or nil)
    health:SetAttribute("type2", healthRank and "spell" or nil)
    health:SetAttribute("spell2", healthRank and healthRank.spell or nil)

    soul.itemID, soul.rank = soulItem, soulRank
    health.itemID, health.rank = healthItem, healthRank
    local soulIcon = soulItem or (soulRank and soulRank.items[1])
    local healthIcon = healthItem or (healthRank and healthRank.items[1])
    soul.icon:SetTexture(soulIcon and C_Item.GetItemIconByID(soulIcon) or SOULSTONE_ICON)
    health.icon:SetTexture(healthIcon and C_Item.GetItemIconByID(healthIcon) or HEALTHSTONE_ICON)
    soul.count:SetText(CountCarried(SOULSTONES))
    health.count:SetText(CountCarried(HEALTHSTONES))
    for _, kind in ipairs(WEAPON_KINDS) do
        local line, button = WEAPON_STONES[kind], buttons[kind]
        local item, rank = BestCarriedItem(line.ranks), BestKnownRank(line.ranks)
        button:SetAttribute("type1", item and "item" or nil)
        button:SetAttribute("item1", item and ("item:" .. item) or nil)
        button:SetAttribute("target-slot1", item and MAIN_HAND_SLOT or nil)
        button:SetAttribute("type2", rank and "spell" or nil)
        button:SetAttribute("spell2", rank and rank.spell or nil)
        button.itemID, button.rank = item, rank
        local icon = item or (rank and rank.items[1])
        button.icon:SetTexture(icon and C_Item.GetItemIconByID(icon) or line.icon)
        -- Listed and greyed, never hidden: a stone you have not learned yet.
        button.icon:SetDesaturated(not item and not rank)
        button.count:SetText(CountCarried(line.ranks))
    end
    UpdateMacros(soulRank, healthRank)
end

local function UpdateVisibility()
    if InCombatLockdown() then
        stones.pending = true
        return
    end
    local settings = WTF.db.stones
    if LayoutKey() ~= buttons.layoutKey then
        LayoutStoneButtons()
    end
    if settings.enabled and settings.shown then
        buttons.bar:Show()
    else
        buttons.bar:Hide()
    end
end

local function Refresh()
    ApplyActions()
    UpdateVisibility()
end
WTF.RefreshStones = Refresh

local function Say(message)
    local now = GetTime()
    if message == stones.lastMessage and now - stones.lastMessageTime < REPEAT_MESSAGE_SECONDS then
        return
    end
    stones.lastMessage, stones.lastMessageTime = message, now
    WTF.Warn(message)
end

local function FindItemSlot(itemID)
    local lastBag = type(NUM_TOTAL_EQUIPPED_BAG_SLOTS) == "number" and NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if type(info) == "table" and info.itemID == itemID and not info.isLocked then
                return bag, slot
            end
        end
    end
end

-- The latest trade events, for /wtf debug_stones.
local function LogTrade(event, ...)
    local first, second = ...
    table.insert(stones.tradeLog, 1, {time = GetTime(), event = event, first = WTF.Describe(first),
        second = WTF.Describe(second)})
    stones.tradeLog[TRADE_LOG_SIZE + 1] = nil
end

-- The gift whisper goes when the trade window opens for a trade the
-- Healthstone button started (author's choice), not on completion.
local function WhisperGift(trade)
    stones.lastGift = trade.whisperTo or trade.target or "nobody (no target name)"
    WTF.WhisperHealthstoneGift(trade.target, trade.whisperTo)
end

local function FreeTradeSlot()
    for slot = 1, TRADE_SLOT_COUNT do
        if not GetTradePlayerItemLink(slot) then
            return slot
        end
    end
end

-- Puts the requested Healthstone into the trade window. The client may allow
-- moving items only during a key press or click, as with deleting them; a
-- refused move is put back and tried once more at the next key press or
-- click. While item moves are restricted (WTF.MoveRestricted: combat or an
-- AddOn restriction) WTF picks up nothing and clicks nothing; it tries at the
-- next key press, and if that is restricted too, or too late, it says once to
-- drag the stone in yourself. WTF never presses Trade for you. No stop is
-- silent (1.7.1, John: the trade opened with nothing in it): each tries
-- again or warns, and the trade log of /wtf debug_stones names the reason
-- ("place <reason> <detail>").
local DRAG_YOURSELF = "The game did not let WTF put the Healthstone into the trade window; drag it in yourself."
local PlaceTradeStone

local function LogPlace(reason, detail)
    LogTrade("place", reason, detail)
end

local function GiveUp(reason, detail)
    LogPlace(reason, detail)
    stones.pendingTrade = nil
    WTF.Warn(DRAG_YOURSELF)
end

-- One more try at the next key press or click, or the warning on the retry.
local function RetryOrGiveUp(retry, reason, detail)
    if retry then
        GiveUp(reason, detail)
    else
        LogPlace(reason, detail or "retry")
        WTF.RunOnNextInput(function() PlaceTradeStone(true) end)
    end
end

function PlaceTradeStone(retry)
    local trade = stones.pendingTrade
    if not trade then
        return
    end
    if retry and GetTime() - trade.time > TRADE_WAIT then
        GiveUp("late")
        return
    end
    -- What you hold on the cursor stays yours: wait for the next input.
    local held = GetCursorInfo()
    if held then
        RetryOrGiveUp(retry, "cursorBusy", WTF.Describe(held))
        return
    end
    if WTF.MoveRestricted() then
        stones.lastRestricted = GetTime()
        RetryOrGiveUp(retry, "restricted")
        return
    end
    local bag, slot = FindItemSlot(trade.itemID)
    if not bag then
        GiveUp("noStone", trade.itemID)
        return
    end
    local tradeSlot = FreeTradeSlot()
    if not tradeSlot then
        GiveUp("noFreeSlot")
        return
    end
    C_Container.PickupContainerItem(bag, slot)
    local kind, itemID = GetCursorInfo()
    if kind == nil then
        -- The pickup took nothing (refused, or the item is still settling).
        RetryOrGiveUp(retry, "pickupEmpty")
        return
    end
    if kind ~= "item" or itemID ~= trade.itemID then
        ClearCursor()
        GiveUp("wrongCursor", WTF.Describe(kind) .. ":" .. WTF.Describe(itemID))
        return
    end
    if WTF.MoveRestricted() then
        ClearCursor()
        stones.lastRestricted = GetTime()
        RetryOrGiveUp(retry, "restricted")
        return
    end
    stones.placing, stones.refused = true, false
    ClickTradeButton(tradeSlot)
    stones.placing = false
    if stones.refused or GetCursorInfo() then
        ClearCursor()
        RetryOrGiveUp(retry, stones.refused and "refused" or "stillOnCursor")
        return
    end
    LogPlace("placed", tradeSlot)
    stones.pendingTrade = nil
    WTF.Report("Healthstone in the trade window. Press Trade to give it.")
end

-- Explains a click that did nothing, and starts a Healthstone trade; the
-- secure action itself already ran.
local function PostClick(button, mouseButton, down)
    local kind = button.kind
    if kind == "healthstone" and mouseButton == "LeftButton" and button.mode == "trade" then
        -- The press and the release both arrive here; trade once.
        if not down and button.tradeItem then
            local target, whisperTo = WTF.FriendlyTargetNames()
            stones.pendingTrade = {itemID = button.tradeItem, time = GetTime(), target = target,
                whisperTo = whisperTo}
            InitiateTrade("target")
        end
        return
    end
    local line = WEAPON_STONES[kind]
    if line then
        if mouseButton == "RightButton" and not button.rank then
            Say("You do not know " .. line.create .. " yet.")
        elseif mouseButton == "LeftButton" and not button.itemID then
            Say("No " .. line.title .. " in your bags. Right-click to create one.")
        end
        return
    end
    if mouseButton == "MiddleButton" then
        if kind == "healthstone" and not button.itemID then
            Say("No Healthstone in your bags. Right-click to create one.")
        end
        return
    end
    if mouseButton == "RightButton" then
        if not button.rank then
            if kind == "soulstone" then
                Say("You do not know Create Soulstone yet.")
            elseif BestKnownRank(HEALTHSTONES) then
                Say("You already carry every Healthstone rank you can make here.")
            else
                Say("You do not know Create Healthstone yet.")
            end
        end
    elseif kind == "soulstone" and InCombatLockdown() then
        Say("Soulstones cannot be applied in combat.")
    elseif not button.itemID then
        Say(kind == "soulstone" and "No Soulstone in your bags. Right-click to create one."
            or "No Healthstone in your bags. Right-click to create one.")
    end
end

local function ItemName(itemID)
    local name = itemID and C_Item.GetItemInfo(itemID)
    return name or "a stone"
end

local function ShowWeaponStoneTooltip(button, line)
    GameTooltip:SetText(line.title, GOLD[1], GOLD[2], GOLD[3])
    if button.itemID then
        GameTooltip:AddLine("Left-click: put " .. ItemName(button.itemID) .. " on your main-hand weapon.",
            1, 1, 1, true)
    else
        GameTooltip:AddLine("Left-click: you carry none.", 0.7, 0.7, 0.7, true)
    end
    if button.rank then
        GameTooltip:AddLine("Right-click: create " .. ItemName(button.rank.items[1]) .. ".", 1, 1, 1, true)
    else
        GameTooltip:AddLine("Right-click: you learn " .. line.create .. " at level " .. line.level .. ".",
            0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function ShowTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    local line = WEAPON_STONES[button.kind]
    if line then
        ShowWeaponStoneTooltip(button, line)
        return
    end
    local soulstone = button.kind == "soulstone"
    GameTooltip:SetText(soulstone and "Soulstone" or "Healthstone", GOLD[1], GOLD[2], GOLD[3])
    if not soulstone and button.mode == "trade" then
        GameTooltip:AddLine("Left-click: trade " .. ItemName(button.tradeItem) .. " to your target.", 1, 1, 1, true)
    elseif not soulstone and button.mode == "create" then
        GameTooltip:AddLine("Left-click: create a Healthstone your target can use, then left-click again to "
            .. "trade it.", 1, 1, 1, true)
    elseif button.itemID then
        GameTooltip:AddLine(soulstone and ("Left-click: use " .. ItemName(button.itemID)
            .. " on your friendly target, or on yourself.")
            or ("Left-click: use " .. ItemName(button.itemID) .. "."), 1, 1, 1, true)
    else
        GameTooltip:AddLine("Left-click: you carry none.", 0.7, 0.7, 0.7, true)
    end
    if button.rank then
        GameTooltip:AddLine("Right-click: create " .. ItemName(button.rank.items[1])
            .. (soulstone and "." or ", the best your friendly player target can use."), 1, 1, 1, true)
    elseif not soulstone and BestKnownRank(HEALTHSTONES) then
        GameTooltip:AddLine("Right-click: you already carry every rank you can make here.", 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine("Right-click: you know no rank yet.", 0.7, 0.7, 0.7, true)
    end
    -- Click hints only (John, 2026-11-27: no follow-on text). A Soulstone
    -- click in combat says in chat that it cannot be applied.
    if not soulstone then
        GameTooltip:AddLine("Middle-click: use your best Healthstone on yourself.", 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function PlaceBar(bar)
    local position = WTF.db.stones.position
    bar:ClearAllPoints()
    if position then
        bar:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else
        bar:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
    end
end

-- Dragging and snapping: Layout.lua.
local function StartDrag()
    WTF.BeginDrag(buttons.bar)
end

local function StopDrag()
    WTF.EndDrag(buttons.bar)
end

local function CreateStoneButton(bar, name, kind, index)
    local button = CreateFrame("Button", name, bar, "SecureActionButtonTemplate")
    button.kind = kind
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetPoint("LEFT", bar, "LEFT", PADDING + (index - 1) * (BUTTON_SIZE + BUTTON_GAP), 0)
    button:RegisterForClicks("AnyUp", "AnyDown")
    -- Act on the release, as RestedXP does, so a release-only press (/click,
    -- where a client allows it) works with ActionButtonUseKeyDown on; mouse
    -- clicks are unaffected.
    button:SetAttribute("useOnKeyDown", false)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -3, 3)
    border:SetPoint("BOTTOMRIGHT", 3, -3)
    border:SetBackdrop({edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10})
    border:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3])
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    if WEAPON_STONES[kind] then
        local glow = button:CreateTexture(nil, "OVERLAY")
        glow:SetTexture(GLOW_TEXTURE)
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
        glow:SetPoint("CENTER", button, "CENTER", 0, 0)
        glow:SetSize(BUTTON_SIZE * GLOW_SCALE, BUTTON_SIZE * GLOW_SCALE)
        glow:Hide()
        -- An animation, not an OnUpdate script: it fades and returns.
        glow.pulse = glow:CreateAnimationGroup()
        glow.pulse:SetLooping("BOUNCE")
        local fade = glow.pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(GLOW_LOW_ALPHA)
        fade:SetDuration(GLOW_PULSE_SECONDS)
        button.glow = glow
    end
    button:SetScript("PostClick", PostClick)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", StartDrag)
    button:SetScript("OnDragStop", StopDrag)
    return button
end

function WTF.RefreshStonesMover()
    if buttons.bar and buttons.bar.mover then
        buttons.bar.mover:SetShown(not WTF.db.locked)
    end
end

-- The bar holds secure buttons, so its size changes only out of combat; it
-- keeps its center (and saves it).
local function ApplyBarScale()
    if not buttons.bar then
        return
    end
    if InCombatLockdown() then
        stones.scalePending = true
        return
    end
    stones.scalePending = false
    WTF.ScaleKeepingCenter(buttons.bar, WTF.db.stones.scale / 100)
end

function WTF.SetStonesScale(percent)
    if buttons.widget then
        -- Clamped, saved, and applied from the center; out of combat.
        buttons.widget:SetSetting("scale", WTF.SanitizeFrameScale(percent))
        return
    end
    WTF.db.stones.scale = WTF.SanitizeFrameScale(percent)
    ApplyBarScale()
end

function WTF.ResetStonesPosition()
    if buttons.widget then
        buttons.widget:ResetPosition()
        return
    end
    WTF.db.stones.position = nil
    if InCombatLockdown() then
        stones.resetPending = true
        return
    end
    PlaceBar(buttons.bar)
end

-- A profile copy or import (Core's ApplyProfile): the bar's size and place
-- from the settings, scale first (the place is in the bar's own scale), out of
-- combat (secure buttons); in combat, when it ends. Then the macros, and with
-- them the buttons and the bar's visibility.
local function ApplyBarProfile()
    stones.profilePending = false
    stones.scalePending = false
    stones.resetPending = false
    buttons.bar:SetScale(WTF.db.stones.scale / 100)
    PlaceBar(buttons.bar)
end

function WTF.ApplyStonesProfile()
    if buttons.widget then
        -- The place and scale first (the saved center), then the buttons in
        -- the profile's orientation, resized from that center.
        WTF.toolkit.ReapplyWidgets(addonName)
        LayoutStoneButtons()
    elseif buttons.bar then
        if InCombatLockdown() then
            stones.profilePending = true
        else
            ApplyBarProfile()
        end
        WTF.RefreshStonesMover()
    end
    WTF.ApplyStoneMacros()
end

-- Stone status ----------------------------------------------------------------
-- WTF remembers who has your Soulstone from your own cast (Soulstone
-- Resurrection), saved per character with the time it ends, and reminds you in
-- chat when it ends or when no Soulstone is up, and when you carry no
-- Healthstone: on entering an instance, on joining a group, and after a fight,
-- at most once per REMIND_INTERVAL for each.

-- Soulstone Resurrection, the Soulstone item's spell, by name; and how long it
-- lasts in Classic.
local SOULSTONE_SPELL_ID = 20707
local SOULSTONE_SECONDS = 30 * 60
local REMIND_INTERVAL = 10 * 60

local status = {casts = {}, reminded = {}}

-- Turns a cast's "First-Last" target name into "First Last".
local function DisplayName(castName)
    return (castName:gsub("%-", " "))
end

local function IsYou(castName)
    local name = castName:match("^([^%-]+)")
    return name == UnitName("player")
end

function WTF.OnStoneCast(event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        local _, target, castGUID, spellID = ...
        if WTF.IsSecret(spellID) or WTF.IsSecret(castGUID) or WTF.IsSecret(target) then
            return
        end
        if C_Spell.GetSpellName(spellID) == status.soulstoneName then
            status.casts[castGUID] = type(target) == "string" and target or ""
        end
        return
    end
    local _, castGUID = ...
    if WTF.IsSecret(castGUID) then
        return
    end
    local target = status.casts[castGUID]
    status.casts = {}
    if not target then
        return
    end
    local name = (target == "" or IsYou(target)) and "you" or DisplayName(target)
    WTF.db.stones.soulstone = {name = name, ends = time() + SOULSTONE_SECONDS}
    WTF.ScheduleSoulstoneEnd()
end

local function SoulstoneUp()
    local soulstone = WTF.db.stones.soulstone
    return soulstone and soulstone.ends > time() and soulstone or nil
end

-- One reminder line per kind, at most once per REMIND_INTERVAL.
local function Remind(kind, message)
    local now = GetTime()
    if status.reminded[kind] and now - status.reminded[kind] < REMIND_INTERVAL then
        return
    end
    status.reminded[kind] = now
    WTF.Report(message)
end

function WTF.RemindStones()
    local settings = WTF.db.stones
    if not settings.enabled then
        return
    end
    if settings.remindSoulstone and BestKnownRank(SOULSTONES) and not SoulstoneUp() then
        Remind("soulstone", CountCarried(SOULSTONES) > 0
            and "No Soulstone is up. Left-click the Soulstone button to apply one."
            or "No Soulstone is up. Right-click the Soulstone button to create one.")
    end
    if settings.remindHealthstone and BestKnownRank(HEALTHSTONES) and CountCarried(HEALTHSTONES) == 0 then
        Remind("healthstone", "You carry no Healthstone. Right-click the Healthstone button to create one.")
    end
end

local function OnSoulstoneEnd()
    local soulstone = WTF.db.stones.soulstone
    if not soulstone or soulstone.ends > time() then
        return
    end
    WTF.db.stones.soulstone = nil
    if WTF.db.stones.enabled and WTF.db.stones.remindSoulstone then
        WTF.Report("Your Soulstone on " .. soulstone.name .. " has ended.")
        status.reminded.soulstone = nil
        WTF.RemindStones()
    end
end

function WTF.ScheduleSoulstoneEnd()
    local soulstone = WTF.db.stones.soulstone
    if soulstone and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(math.max(0, soulstone.ends - time()) + 1, OnSoulstoneEnd)
    end
end

function WTF.StartStoneStatus()
    status.soulstoneName = C_Spell.GetSpellName(SOULSTONE_SPELL_ID)
    OnSoulstoneEnd()
    WTF.ScheduleSoulstoneEnd()
end

-- /wtf stones: who has your Soulstone, and the stones you carry.
function WTF.ReportStoneStatus()
    local soulstone = SoulstoneUp()
    if soulstone then
        WTF.Report(string.format("Soulstone on %s, %d min left.", soulstone.name,
            math.ceil((soulstone.ends - time()) / 60)))
    else
        WTF.Report("No Soulstone is up.")
    end
    WTF.Report(string.format("You carry %d Soulstone(s) and %d Healthstone(s).",
        CountCarried(SOULSTONES), CountCarried(HEALTHSTONES)))
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "TRADE_SHOW" or event == "TRADE_CLOSED" then
        LogTrade(event, ...)
    end
    if event == "TRADE_SHOW" then
        local trade = stones.pendingTrade
        if trade and GetTime() - trade.time <= TRADE_WAIT then
            WhisperGift(trade)
            PlaceTradeStone(false)
        else
            stones.pendingTrade = nil
        end
        return
    elseif event == "TRADE_CLOSED" then
        stones.pendingTrade = nil
        return
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if stones.placing then
            -- Logged by name: a refusal may name another AddOn.
            local blocked, call = ...
            LogTrade(event, blocked, call)
            if blocked == addonName then
                stones.refused = true
            end
        end
        return
    elseif event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        WTF.OnStoneCast(event, ...)
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if stones.profilePending then
            ApplyBarProfile()
        end
        if stones.resetPending then
            stones.resetPending = false
            PlaceBar(buttons.bar)
        end
        if stones.scalePending then
            ApplyBarScale()
        end
        if stones.pending then
            Refresh()
        end
        WTF.RemindStones()
    elseif event == "GROUP_JOINED" then
        WTF.RemindStones()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Refresh()
        if IsInInstance() then
            WTF.RemindStones()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "PLAYER_TARGET_CHANGED" then
        ApplyActions()
    else
        Refresh()
    end
end)

function WTF.InitializeStones()
    local available, missing = WTF.CheckStoneCapabilities()
    if not available then
        WTF.Report("Stones stay off: this client lacks " .. missing .. ".")
        return
    end
    macros.missing = nil
    for _, name in ipairs({"GetMacroIndexByName", "GetNumMacros", "GetMacroBody", "CreateMacro", "EditMacro",
        "DeleteMacro"}) do
        if type(_G[name]) ~= "function" then
            macros.missing = macros.missing or name
        end
    end
    if not CharacterMacroLimit() then
        macros.missing = macros.missing or "Constants.MacroConsts.MAX_CHARACTER_MACROS"
    end
    macros.available = macros.missing == nil
    if not macros.available and WTF.db.stones.macros then
        WTF.Report("Stone macros stay off: this client lacks " .. macros.missing .. ".")
    end
    local height = PADDING * 2 + BUTTON_SIZE
    local bar = CreateFrame("Frame", "WarlockToolsForeverStones", UIParent, "BackdropTemplate")
    bar:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}})
    bar:SetBackdropColor(BROWN[1], BROWN[2], BROWN[3], BROWN[4])
    bar:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3])
    buttons.bar = bar
    buttons.soulstone = CreateStoneButton(bar, "WarlockToolsForeverSoulstone", "soulstone", 1)
    buttons.healthstone = CreateStoneButton(bar, "WarlockToolsForeverHealthstone", "healthstone", 2)
    buttons.spellstone = CreateStoneButton(bar, "WarlockToolsForeverSpellstone", "spellstone", 3)
    buttons.firestone = CreateStoneButton(bar, "WarlockToolsForeverFirestone", "firestone", 4)
    -- Sized for the buttons it shows, so the toolkit places it at that size.
    local width = BarWidth(#ShownButtons())
    bar:SetSize(width, height)
    local toolkit = BarToolkit()
    if toolkit then
        -- A visible bar of buttons: it takes clicks also while locked. Its
        -- buttons start a drag through WTF.BeginDrag, the toolkit's.
        buttons.widget = toolkit.CreateWidget({
            addon = addonName, key = "stones", title = "Stones", frame = bar, store = WTF.db.stones,
            width = width, height = height, point = DEFAULT_POINT, mouse = "always",
            keys = {position = "position", scale = "scale"},
            sizes = {scale = {min = WTF.FRAME_SCALE_MIN, max = WTF.FRAME_SCALE_MAX, step = WTF.FRAME_SCALE_STEP,
                default = WTF.DEFAULT_FRAME_SCALE}},
        })
    else
        bar:SetMovable(true)
        bar:SetClampedToScreen(true)
        bar:EnableMouse(true)
        bar:RegisterForDrag("LeftButton")
        bar:SetScript("OnDragStart", StartDrag)
        bar:SetScript("OnDragStop", StopDrag)
        bar.mover = WTF.CreateMover(bar, "Stones")
        WTF.RegisterMovable(bar, function(position) WTF.db.stones.position = position end)
        -- The saved place is in the bar's own scale, so the scale comes first.
        bar:SetScale(WTF.db.stones.scale / 100)
        PlaceBar(bar)
    end
    LayoutStoneButtons()
    -- Level requirements need item data, which arrives later on first use.
    if type(C_Item.RequestLoadItemDataByID) == "function" then
        for _, rank in ipairs(HEALTHSTONES) do
            C_Item.RequestLoadItemDataByID(rank.items[1])
        end
    end
    for _, event in ipairs({"BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "PLAYER_TARGET_CHANGED",
        "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED", "PLAYER_LEVEL_UP", "TRADE_SHOW", "TRADE_CLOSED",
        "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_ENTERING_WORLD", "GROUP_JOINED"}) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED"}) do
        events:RegisterUnitEvent(event, "player")
    end
    Refresh()
    WatchWeapon()
    WTF.StartStoneStatus()
end

-- /wtf debug_click: what each Stones button does for each mouse button, and
-- the client settings /click depends on.
function WTF.ReportClickDebug()
    local function Report(text)
        WTF.Report("debug_click " .. text)
    end
    if not buttons.healthstone then
        Report("the Stones buttons do not exist (Stones is off)")
        return
    end
    local keyDown = type(GetCVarBool) == "function" and GetCVarBool("ActionButtonUseKeyDown")
    Report(string.format("ActionButtonUseKeyDown=%s combat=%s healthstoneMode=%s",
        tostring(keyDown), tostring(InCombatLockdown()), tostring(buttons.healthstone.mode)))
    for _, button in ipairs({buttons.healthstone, buttons.soulstone, buttons.spellstone, buttons.firestone}) do
        local constrained = type(button.HasAccessConstraints) == "function" and button:HasAccessConstraints()
        local visible = button:IsVisible()
        Report(string.format("%s useOnKeyDown=%s constrained=%s shown=%s", button:GetName(),
            tostring(button:GetAttribute("useOnKeyDown")), tostring(constrained), tostring(visible)))
        for index = 1, 3 do
            Report(string.format("  button%d type=%s item=%s spell=%s macrotext=%s targetSlot=%s", index,
                tostring(button:GetAttribute("type" .. index)), tostring(button:GetAttribute("item" .. index)),
                tostring(button:GetAttribute("spell" .. index)), tostring(button:GetAttribute("macrotext" .. index)),
                tostring(button:GetAttribute("target-slot" .. index))))
        end
    end
end

-- /wtf debug_stones: which create spells you know, which stones you carry,
-- and each Healthstone's level requirement, to confirm Forever's IDs.
function WTF.ReportStoneDebug()
    local available, missing = WTF.CheckStoneCapabilities()
    if not available then
        WTF.Report("debug_stones missing " .. missing)
        return
    end
    for _, group in ipairs({{"soulstone", SOULSTONES}, {"healthstone", HEALTHSTONES},
        {"spellstone", SPELLSTONES}, {"firestone", FIRESTONES}}) do
        for _, rank in ipairs(group[2]) do
            local carried = {}
            for _, itemID in ipairs(rank.items) do
                carried[#carried + 1] = itemID .. "x" .. Carried(itemID)
            end
            local name = C_Spell.GetSpellName(rank.spell)
            WTF.Report(string.format("debug_stones %s spell=%d name=%s known=%s items=%s minLevel=%s",
                group[1], rank.spell, tostring(name), tostring(Known(rank.spell)),
                table.concat(carried, ","), tostring(MinLevel(rank.items[1]))))
        end
    end
    WTF.Report(string.format("debug_stones weapon known=%s enchant=%s stone=%s glow spellstone=%s firestone=%s",
        tostring(weapon.known), tostring(weapon.id), tostring(weapon.stone),
        tostring(buttons.spellstone and buttons.spellstone.glowing), tostring(buttons.firestone and buttons.firestone.glowing)))
    local healthRank = WTF.HealthstoneRankForTarget()
    WTF.Report(string.format("debug_stones targetLevel=%s healthstoneRank=%s pending=%s",
        tostring(FriendlyPlayerLevel()), tostring(healthRank and healthRank.spell), tostring(stones.pending)))
    WTF.Report(string.format("debug_stones lastGiftWhisper=%s moveRestricted=%s lastRestricted=%s keyHook=%s",
        tostring(stones.lastGift), tostring(WTF.MoveRestricted()),
        stones.lastRestricted and string.format("%.1fs ago", GetTime() - stones.lastRestricted) or "never",
        tostring(WTF.keyInputHooked == true)))
    local now = GetTime()
    for _, entry in ipairs(stones.tradeLog) do
        WTF.Report(string.format("debug_stones trade %.1fs ago %s %s %s", now - entry.time, entry.event,
            entry.first, entry.second))
    end
    local _, numCharacter = GetNumMacros()
    WTF.Report(string.format("debug_stones macros enabled=%s available=%s missing=%s limit=%s used=%s",
        tostring(WTF.db.stones.macros), tostring(macros.available), tostring(macros.missing),
        tostring(CharacterMacroLimit()), tostring(numCharacter)))
    for _, name in pairs(WTF.STONE_MACROS) do
        WTF.Report(string.format("debug_stones macro %q index=%d", name, GetMacroIndexByName(name)))
    end
end
