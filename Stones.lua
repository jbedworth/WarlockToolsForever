local _, WTF = ...

-- Stones: one button each for Soulstones and Healthstones on a small movable
-- bar. Left-click uses the best stone you carry; right-click creates the best
-- rank you know (for a Healthstone, the best rank your friendly player target
-- can use). The buttons are secure, so they work in combat, but their actions
-- can change only out of combat; changes wait for combat to end.

-- Ranks from lowest to highest: the create spell and the items it can make
-- (Healthstones also come in the Improved Healthstone talent versions). These
-- are Classic's IDs; /wtf debug_stones shows what the client knows.
local SOULSTONES = {
    {spell = 693, items = {5232}},     -- Minor
    {spell = 20752, items = {16892}},  -- Lesser
    {spell = 20755, items = {16893}},  -- Soulstone
    {spell = 20756, items = {16895}},  -- Greater
    {spell = 20757, items = {16896}},  -- Major
}
local HEALTHSTONES = {
    {spell = 6201, items = {5512, 19004, 19005}},   -- Minor
    {spell = 6202, items = {5511, 19006, 19007}},   -- Lesser
    {spell = 5699, items = {5509, 19008, 19009}},   -- Healthstone
    {spell = 11729, items = {5510, 19010, 19011}},  -- Greater
    {spell = 11730, items = {9421, 19012, 19013}},  -- Major
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

local REQUIRED = {
    {"C_SpellBook", "IsSpellKnown"}, {"C_Item", "GetItemCount"}, {"C_Item", "GetItemInfo"},
}

local stones = {pending = false, lastMessage = nil, lastMessageTime = 0}

function WTF.CheckStoneCapabilities()
    for _, entry in ipairs(REQUIRED) do
        local namespace = _G[entry[1]]
        if type(namespace) ~= "table" or type(namespace[entry[2]]) ~= "function" then
            return false, entry[1] .. "." .. entry[2]
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

-- The Healthstone rank to create: the best you know that a friendly player
-- target can use (item level requirement), else the best you know.
function WTF.HealthstoneRankForTarget()
    local level = FriendlyPlayerLevel()
    for index = #HEALTHSTONES, 1, -1 do
        local rank = HEALTHSTONES[index]
        if Known(rank.spell) then
            local required = MinLevel(rank.items[1])
            if not level or (type(required) == "number" and required <= level) then
                return rank
            end
        end
    end
end

local buttons = {}

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

    local soul, health = buttons.soulstone, buttons.healthstone
    soul:SetAttribute("type1", soulItem and "macro" or nil)
    soul:SetAttribute("macrotext1", soulItem and ("/use [@target,help,nodead][@player] item:" .. soulItem) or nil)
    soul:SetAttribute("type2", soulRank and "spell" or nil)
    soul:SetAttribute("spell2", soulRank and soulRank.spell or nil)
    health:SetAttribute("type1", healthItem and "macro" or nil)
    health:SetAttribute("macrotext1", healthItem and ("/use item:" .. healthItem) or nil)
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

-- Explains a click that did nothing; the secure action itself already ran.
local function PostClick(button, mouseButton)
    local kind = button.kind
    if mouseButton == "RightButton" then
        if not button.rank then
            Say(kind == "soulstone" and "You do not know Create Soulstone yet."
                or "You do not know Create Healthstone yet.")
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
    if button.itemID then
        GameTooltip:AddLine(soulstone and ("Left-click: use " .. ItemName(button.itemID)
            .. " on your friendly target, or on yourself.")
            or ("Left-click: use " .. ItemName(button.itemID) .. "."), 1, 1, 1, true)
    else
        GameTooltip:AddLine("Left-click: you carry none.", 0.7, 0.7, 0.7, true)
    end
    if button.rank then
        GameTooltip:AddLine("Right-click: create " .. ItemName(button.rank.items[1])
            .. (soulstone and "." or ", the best your friendly player target can use."), 1, 1, 1, true)
    else
        GameTooltip:AddLine("Right-click: you know no rank yet.", 0.7, 0.7, 0.7, true)
    end
    if soulstone then
        GameTooltip:AddLine("Soulstones cannot be applied in combat.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine("/click " .. button:GetName() .. " (or RightButton) works in macros.", 0.7, 0.7, 0.7, true)
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

function WTF.ResetStonesPosition()
    WTF.db.stones.position = nil
    if InCombatLockdown() then
        WTF.Report("The Stones bar moves back after combat.")
        stones.resetPending = true
        return
    end
    PlaceBar(buttons.bar)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if stones.resetPending then
            stones.resetPending = false
            PlaceBar(buttons.bar)
        end
        if stones.pending then
            Refresh()
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
        "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED", "PLAYER_LEVEL_UP"}) do
        events:RegisterEvent(event)
    end
    Refresh()
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
end
