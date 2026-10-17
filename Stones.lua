local addonName, WTF = ...

-- Stones: one button each for Soulstones and Healthstones on a small movable
-- bar. Left-click uses the best stone you carry; right-click creates the best
-- rank you know (for a Healthstone, the best rank your friendly player target
-- can use). The buttons are secure, so they work in combat, but their actions
-- can change only out of combat; changes wait for combat to end.

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

-- The name /cast needs: on Forever each stone spell has numeric ranks, cast
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
        lines[#lines + 1] = "/cast [btn:2] " .. castName
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
                WTF.Report("No free character macro slot for \"" .. name .. "\"; free one and WTF adds it.")
            end
            return
        end
        CreateMacro(name, MACRO_ICON, body, true)
    elseif GetMacroBody(index) ~= body then
        EditMacro(index, name, MACRO_ICON, body)
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

local function ApplyActions()
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
    UpdateMacros(soulRank, healthRank)
end

local function UpdateVisibility()
    if InCombatLockdown() then
        stones.pending = true
        return
    end
    local settings = WTF.db.stones
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
    WTF.Report(message)
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
-- click. WTF never presses Trade for you.
local PlaceTradeStone
function PlaceTradeStone(retry)
    local trade = stones.pendingTrade
    if not trade or GetCursorInfo() then
        return
    end
    local bag, slot = FindItemSlot(trade.itemID)
    local tradeSlot = FreeTradeSlot()
    if not bag or not tradeSlot then
        stones.pendingTrade = nil
        return
    end
    C_Container.PickupContainerItem(bag, slot)
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or itemID ~= trade.itemID then
        ClearCursor()
        stones.pendingTrade = nil
        return
    end
    stones.placing, stones.refused = true, false
    ClickTradeButton(tradeSlot)
    stones.placing = false
    if stones.refused or GetCursorInfo() then
        ClearCursor()
        if retry then
            stones.pendingTrade = nil
            WTF.Report("The game did not let WTF put the Healthstone into the trade window; drag it in yourself.")
        else
            WTF.RunOnNextInput(function() PlaceTradeStone(true) end)
        end
        return
    end
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

local function ShowTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
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
    if soulstone then
        GameTooltip:AddLine("Soulstones cannot be applied in combat.", 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine("Middle-click: use your best Healthstone on yourself.", 1, 1, 1, true)
    end
    if WTF.db.stones.macros then
        GameTooltip:AddLine("For your action bars: the \"" .. WTF.STONE_MACROS[button.kind]
            .. "\" macro in your character macros does the same, also in combat.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function SavePosition(bar)
    local point, _, relativePoint, x, y = bar:GetPoint()
    WTF.db.stones.position = {point = point, relativePoint = relativePoint, x = x, y = y}
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

local function StartDrag()
    if WTF.db.stones.locked or InCombatLockdown() then
        return
    end
    buttons.bar:StartMoving()
end

local function StopDrag()
    buttons.bar:StopMovingOrSizing()
    SavePosition(buttons.bar)
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
    button:SetScript("PostClick", PostClick)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", StartDrag)
    button:SetScript("OnDragStop", StopDrag)
    return button
end

function WTF.RefreshStonesMover()
    if buttons.bar then
        buttons.bar.mover:SetShown(not WTF.db.locked)
    end
end

function WTF.ResetStonesPosition()
    WTF.db.stones.position = nil
    if InCombatLockdown() then
        WTF.Report("The Stones bar moves back after combat.")
        stones.resetPending = true
        return
    end
    PlaceBar(buttons.bar)
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
        if ... == addonName and stones.placing then
            stones.refused = true
        end
        return
    elseif event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        WTF.OnStoneCast(event, ...)
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if stones.resetPending then
            stones.resetPending = false
            PlaceBar(buttons.bar)
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
    local bar = CreateFrame("Frame", "WarlockToolsForeverStones", UIParent, "BackdropTemplate")
    bar:SetSize(PADDING * 2 + BUTTON_SIZE * 2 + BUTTON_GAP, PADDING * 2 + BUTTON_SIZE)
    bar:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}})
    bar:SetBackdropColor(BROWN[1], BROWN[2], BROWN[3], BROWN[4])
    bar:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3])
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", StartDrag)
    bar:SetScript("OnDragStop", StopDrag)
    bar.mover = WTF.CreateMover(bar)
    buttons.bar = bar
    buttons.soulstone = CreateStoneButton(bar, "WarlockToolsForeverSoulstone", "soulstone", 1)
    buttons.healthstone = CreateStoneButton(bar, "WarlockToolsForeverHealthstone", "healthstone", 2)
    PlaceBar(bar)
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
    for _, button in ipairs({buttons.healthstone, buttons.soulstone}) do
        local constrained = type(button.HasAccessConstraints) == "function" and button:HasAccessConstraints()
        local visible = button:IsVisible()
        Report(string.format("%s useOnKeyDown=%s constrained=%s shown=%s", button:GetName(),
            tostring(button:GetAttribute("useOnKeyDown")), tostring(constrained), tostring(visible)))
        for index = 1, 3 do
            Report(string.format("  button%d type=%s item=%s spell=%s macrotext=%s", index,
                tostring(button:GetAttribute("type" .. index)), tostring(button:GetAttribute("item" .. index)),
                tostring(button:GetAttribute("spell" .. index)), tostring(button:GetAttribute("macrotext" .. index))))
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
    for _, group in ipairs({{"soulstone", SOULSTONES}, {"healthstone", HEALTHSTONES}}) do
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
    local healthRank = WTF.HealthstoneRankForTarget()
    WTF.Report(string.format("debug_stones targetLevel=%s healthstoneRank=%s pending=%s",
        tostring(FriendlyPlayerLevel()), tostring(healthRank and healthRank.spell), tostring(stones.pending)))
    WTF.Report(string.format("debug_stones lastGiftWhisper=%s", tostring(stones.lastGift)))
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
