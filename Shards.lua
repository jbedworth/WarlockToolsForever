local addonName, WTF = ...

-- Soul Shard management: deletes shards that Drain Soul creates above the
-- carried limit. Shards the user moves in (from the bank, mail, or trade) are
-- never deleted, because they arrive outside a creation window.
local SOUL_SHARD_ITEM_ID = 6265
-- Bit in GetContainerNumFreeSlots' bagFamily that marks a soul bag.
local SOUL_BAG_FAMILY = 4
local BACKPACK = 0
-- Spells that create shards, matched by name so every rank counts.
-- Window: seconds after the spell ends during which a new shard counts as
-- created. Drain Soul's shard arrives as the target dies while channeling.
-- Forever's Shadowburn (a talent) gives a shard if the target dies within 8
-- seconds of the hit, so its window covers that plus the bag update.
local SHARD_SOURCES = {
    {id = 1120, window = 3},   -- Drain Soul
    {id = 17877, window = 9},  -- Shadowburn
}
local GAIN_LOG_SIZE = 10
-- The shard counter: a movable Soul Shard icon with your count.
local COUNTER_SIZE = 40
-- The icon is dimmed and the number enlarged so red and green read on the
-- bright shard (in client, red on the magenta icon was hard to read).
local COUNTER_ICON_SHADE = 0.45
local COUNTER_FONT_GROWTH = 2
local COUNTER_DEFAULT_POINT = {"CENTER", "CENTER", -260, -160}
local COUNTER_ICON = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"
local GOLD = {1, 0.82, 0}
local WHITE = {1, 1, 1}
local RED = {1, 0.2, 0.2}
local GREEN = {0.3, 1, 0.3}

local REQUIRED_CONTAINER = {
    "GetContainerNumSlots", "GetContainerNumFreeSlots", "GetContainerItemInfo",
    "PickupContainerItem", "SplitContainerItem",
}
local REQUIRED_GLOBALS = {"GetCursorInfo", "ClearCursor", "DeleteCursorItem", "GetTime", "InCombatLockdown"}

local state = {
    slots = {},
    sourceWindows = {},
    channeling = false,
    windowEnd = 0,
    pending = {},
    blocked = false,
    combatBlocked = false,
    deleting = false,
    refused = false,
    processing = false,
    secretCasts = false,
    gains = {},
    lastSpell = nil,
}

function WTF.CheckShardCapabilities()
    local missing = {}
    for _, name in ipairs(REQUIRED_CONTAINER) do
        if type(C_Container) ~= "table" or type(C_Container[name]) ~= "function" then
            missing[#missing + 1] = "C_Container." .. name
        end
    end
    for _, name in ipairs(REQUIRED_GLOBALS) do
        if type(_G[name]) ~= "function" then
            missing[#missing + 1] = name
        end
    end
    if type(C_Spell) ~= "table" or type(C_Spell.GetSpellName) ~= "function" then
        missing[#missing + 1] = "C_Spell.GetSpellName"
    end
    if type(WorldFrame) ~= "table" or type(WorldFrame.HookScript) ~= "function" then
        missing[#missing + 1] = "WorldFrame:HookScript"
    end
    if type(NUM_BAG_SLOTS) ~= "number" then
        missing[#missing + 1] = "NUM_BAG_SLOTS"
    end
    if #missing > 0 then
        return false, "This client lacks " .. table.concat(missing, ", ")
            .. ", so Warlock Tools Forever stays off."
    end
    return true
end

-- Carried bags run from the backpack to the last equipped bag, including a
-- reagent bag where the client has one; bank bags come after them.
local function LastCarriedBag()
    if type(NUM_TOTAL_EQUIPPED_BAG_SLOTS) == "number" then
        return NUM_TOTAL_EQUIPPED_BAG_SLOTS
    end
    return NUM_BAG_SLOTS
end

local function ShardStack(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if type(info) == "table" and info.itemID == SOUL_SHARD_ITEM_ID then
        return info
    end
end

-- Shard stacks in carried bags only, keyed by "bag:slot".
local function Scan()
    local slots, count = {}, 0
    for bag = BACKPACK, LastCarriedBag() do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = ShardStack(bag, slot)
            if info then
                slots[bag .. ":" .. slot] = {bag = bag, slot = slot, count = info.stackCount}
                count = count + info.stackCount
            end
        end
    end
    return slots, count
end

local function SoulBagFamily(bag)
    local _, family = C_Container.GetContainerNumFreeSlots(bag)
    return type(family) == "number" and math.floor(family / SOUL_BAG_FAMILY) % 2 == 1
end

-- Total slots of equipped soul bags; the backpack is never one. On Forever a
-- soul bag can sit in the reagent bag slot.
function WTF.SoulBagSlots()
    local total = 0
    for bag = BACKPACK + 1, LastCarriedBag() do
        if SoulBagFamily(bag) then
            total = total + C_Container.GetContainerNumSlots(bag)
        end
    end
    return total
end

-- The limit and where it comes from: "soul bag", "default", or "manual".
function WTF.GetShardLimit()
    local settings = WTF.db.shards
    if not settings.autoLimit then
        return settings.limit, "manual"
    end
    local soulSlots = WTF.SoulBagSlots()
    if soulSlots > 0 then
        return soulSlots, "soul bag"
    end
    return WTF.DEFAULT_SHARD_LIMIT, "default"
end

function WTF.CountShards()
    local _, count = Scan()
    return count
end

-- The creation window of a shard source spell, or nil for other spells.
local function SourceWindow(spellID)
    if WTF.IsSecret(spellID) then
        state.secretCasts = true
        return nil
    end
    if type(spellID) ~= "number" then
        return nil
    end
    local name = C_Spell.GetSpellName(spellID)
    return name and state.sourceWindows[name]
end

local function InCreationWindow()
    return state.channeling or GetTime() <= state.windowEnd
end

-- New shards per slot, comparing the last scan with this one.
local function FindGains(before, after)
    local gains = {}
    for key, stack in pairs(after) do
        local previous = before[key] and before[key].count or 0
        if stack.count > previous then
            gains[#gains + 1] = {bag = stack.bag, slot = stack.slot, amount = stack.count - previous}
        end
    end
    table.sort(gains, function(a, b)
        if a.bag ~= b.bag then
            return a.bag < b.bag
        end
        return a.slot < b.slot
    end)
    return gains
end

local function LogGain(amount, count, created)
    local entry = {time = GetTime(), amount = amount, count = count, created = created,
        combat = InCombatLockdown(),
        spell = state.lastSpell}
    table.insert(state.gains, 1, entry)
    state.gains[GAIN_LOG_SIZE + 1] = nil
end

local function StopDeleting(reason)
    if state.blocked then
        return
    end
    state.blocked = true
    state.pending = {}
    WTF.Warn("Soul Shard deletion stopped: " .. reason
        .. ". It stays off until you /reload.")
end

local function CursorEmpty()
    return GetCursorInfo() == nil
end

-- Deletes one shard from a slot. Picks up exactly one, checks the cursor holds
-- a shard, and puts anything unexpected back. Returns "deleted", "blocked"
-- (the client refused; the shard is back), or "unexpected".
local function DeleteOne(bag, slot)
    local info = ShardStack(bag, slot)
    if info.stackCount > 1 then
        C_Container.SplitContainerItem(bag, slot, 1)
    else
        C_Container.PickupContainerItem(bag, slot)
    end
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or itemID ~= SOUL_SHARD_ITEM_ID then
        ClearCursor()
        return "unexpected"
    end
    -- Blocked-action events name WTF for any blocked call, so only those raised
    -- during the deletion itself count against it.
    state.deleting, state.refused = true, false
    DeleteCursorItem()
    state.deleting = false
    if state.refused or not CursorEmpty() then
        ClearCursor()
        return "blocked"
    end
    return "deleted"
end

-- Works through queued deletions while the carried count is above the limit.
-- The client deletes items only during a hardware event (a key press or a
-- click), so this runs from WTF's input hooks, never from game events. It waits
-- for an empty cursor and unlocked items. If the client refuses in combat, the
-- rest waits for input after combat; a refusal out of combat stops deletion.
-- Cursor events fire while a deletion is under way, so calls never nest.
local function ProcessPending()
    if state.processing or state.blocked or (state.combatBlocked and InCombatLockdown()) then
        return
    end
    state.processing = true
    while #state.pending > 0 do
        local entry = state.pending[1]
        local info = ShardStack(entry.bag, entry.slot)
        if not info or WTF.CountShards() <= WTF.GetShardLimit() then
            table.remove(state.pending, 1)
        elseif info.isLocked or not CursorEmpty() then
            break
        else
            local result = DeleteOne(entry.bag, entry.slot)
            if result == "deleted" then
                table.remove(state.pending, 1)
                if WTF.db.shards.report then
                    WTF.Report(string.format("Deleted a Soul Shard above your limit of %d.",
                        WTF.GetShardLimit()))
                end
            elseif result == "blocked" and InCombatLockdown() then
                state.combatBlocked = true
                break
            else
                StopDeleting(result == "blocked" and "the client blocked it"
                    or "the cursor did not hold one Soul Shard, so nothing was deleted")
                break
            end
        end
    end
    state.processing = false
end

local function OnInput()
    if #state.pending > 0 then
        ProcessPending()
    end
end

local counter

local function CounterColor(count)
    if count >= WTF.GetShardLimit() then
        return GREEN
    elseif count <= WTF.db.shards.counterLow then
        return RED
    end
    return WHITE
end

-- Green at or above your limit, red at or below the low setting, white between.
function WTF.RefreshShardCounter()
    if not counter then
        return
    end
    counter.mover:SetShown(not WTF.db.locked)
    if not WTF.db.shards.counter then
        counter:Hide()
        return
    end
    local count = WTF.CountShards()
    local color = CounterColor(count)
    counter.count:SetText(count)
    counter.count:SetTextColor(color[1], color[2], color[3])
    counter:Show()
end

local function PlaceCounter()
    local position = WTF.db.shards.counterPosition
    counter:ClearAllPoints()
    if position then
        counter:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else
        local point = COUNTER_DEFAULT_POINT
        counter:SetPoint(point[1], UIParent, point[2], point[3], point[4])
    end
end

local function ShowCounterTooltip(frame)
    local limit, source = WTF.GetShardLimit()
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText("Soul Shards")
    GameTooltip:AddLine(string.format("%d of %d (%s limit)", WTF.CountShards(), limit, source), 1, 1, 1)
    if not WTF.db.shards.counterLocked then
        GameTooltip:AddLine("Drag to move. /wtf reset moves it back.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

-- A plain frame, not a secure one, so it moves and updates in combat too.
local function CreateCounter()
    counter = CreateFrame("Frame", nil, UIParent)
    WTF.shardCounter = counter
    counter:SetSize(COUNTER_SIZE, COUNTER_SIZE)
    counter:SetClampedToScreen(true)
    counter:SetMovable(true)
    counter:EnableMouse(true)
    counter:RegisterForDrag("LeftButton")
    counter.icon = counter:CreateTexture(nil, "ARTWORK")
    counter.icon:SetAllPoints()
    counter.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local icon = type(C_Item.GetItemIconByID) == "function" and C_Item.GetItemIconByID(SOUL_SHARD_ITEM_ID)
    counter.icon:SetTexture(icon or COUNTER_ICON)
    counter.icon:SetVertexColor(COUNTER_ICON_SHADE, COUNTER_ICON_SHADE, COUNTER_ICON_SHADE)
    local border = CreateFrame("Frame", nil, counter, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -3, 3)
    border:SetPoint("BOTTOMRIGHT", 3, -3)
    border:SetBackdrop({edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10})
    border:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3])
    counter.count = counter:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
    counter.count:SetPoint("CENTER", 0, 0)
    -- A thick outline and a shadow keep red and green legible on the icon.
    local font, size = counter.count:GetFont()
    if font then
        counter.count:SetFont(font, size + COUNTER_FONT_GROWTH, "THICKOUTLINE")
    end
    counter.count:SetShadowColor(0, 0, 0, 1)
    counter.count:SetShadowOffset(1, -1)
    counter:SetScript("OnDragStart", function(self)
        if not WTF.db.shards.counterLocked then
            self:StartMoving()
        end
    end)
    counter:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        WTF.db.shards.counterPosition = {point = point, relativePoint = relativePoint, x = x, y = y}
    end)
    counter:SetScript("OnEnter", ShowCounterTooltip)
    counter:SetScript("OnLeave", function() GameTooltip:Hide() end)
    counter.mover = WTF.CreateMover(counter)
    PlaceCounter()
end

function WTF.ResetShardCounterPosition()
    WTF.db.shards.counterPosition = nil
    if counter then
        PlaceCounter()
    end
end

local function OnBagsChanged()
    local slots, count = Scan()
    local gains = FindGains(state.slots, slots)
    state.slots = slots
    WTF.RefreshShardCounter()
    if #gains > 0 then
        local created = InCreationWindow()
        local amount = 0
        for _, gain in ipairs(gains) do
            amount = amount + gain.amount
        end
        LogGain(amount, count, created)
        local excess = count - WTF.GetShardLimit()
        if created and WTF.db.shards.enabled and not state.blocked and excess > 0 then
            -- Newest slots first; never more deletions than shards just created.
            -- They go on the next key press or click.
            for index = #gains, 1, -1 do
                for _ = 1, gains[index].amount do
                    if excess > 0 then
                        state.pending[#state.pending + 1] = {bag = gains[index].bag,
                            slot = gains[index].slot}
                        excess = excess - 1
                    end
                end
            end
        end
    end
end

local function OnSpellEvent(event, spellID)
    state.lastSpell = {time = GetTime(), id = WTF.Describe(spellID), event = event}
    local window = SourceWindow(spellID)
    if not window then
        return
    end
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        state.channeling = true
        return
    end
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        state.channeling = false
    end
    state.windowEnd = math.max(state.windowEnd, GetTime() + window)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" then
        OnBagsChanged()
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local blockedAddon = ...
        if blockedAddon == addonName and state.deleting then
            state.refused = true
        end
    else
        local _, _, spellID = ...
        OnSpellEvent(event, spellID)
    end
end)

function WTF.InitializeShards()
    for _, source in ipairs(SHARD_SOURCES) do
        local name = C_Spell.GetSpellName(source.id)
        if name then
            state.sourceWindows[name] = source.window
        end
    end
    if next(state.sourceWindows) == nil then
        WTF.Report("Drain Soul was not found, so Soul Shard deletion stays off. Run /wtf debug_shards.")
    end
    state.slots = Scan()
    CreateCounter()
    WTF.RefreshShardCounter()
    WTF.AddInputHandler(OnInput)
    for _, event in ipairs({"BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD",
        "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN"}) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_SUCCEEDED"}) do
        events:RegisterUnitEvent(event, "player")
    end
end

-- /wtf debug_delete: deletes one shard above the limit, from the last shard
-- slot. A slash command runs on the Enter key press, a hardware event.
function WTF.DebugDeleteShard()
    local function Report(text)
        WTF.Report("debug_delete " .. text)
    end
    if InCombatLockdown() then
        Report("works out of combat only.")
        return
    end
    if not CursorEmpty() then
        Report("empty your cursor first.")
        return
    end
    local count, limit = WTF.CountShards(), WTF.GetShardLimit()
    if count <= limit then
        Report(string.format("nothing to delete: %d carried, limit %d.", count, limit))
        return
    end
    local last
    for bag = BACKPACK, LastCarriedBag() do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if ShardStack(bag, slot) then
                last = {bag = bag, slot = slot}
            end
        end
    end
    local result = DeleteOne(last.bag, last.slot)
    if result == "deleted" then
        Report(string.format("deleted one shard from bag %d slot %d; %d carried now.",
            last.bag, last.slot, WTF.CountShards()))
    elseif result == "blocked" then
        Report("the client blocked it; the shard is back in bag " .. last.bag .. ".")
    else
        Report("the cursor did not hold one Soul Shard; nothing was deleted.")
    end
end

local LIMIT_SOURCES = {
    ["soul bag"] = "your soul bag size",
    default = "the default without a soul bag",
    manual = "set by you",
}

function WTF.ReportShardStatus()
    local limit, source = WTF.GetShardLimit()
    local deletion = WTF.db.shards.enabled and "on" or "off"
    if state.blocked then
        deletion = "stopped until /reload"
    end
    WTF.Report(string.format("Soul Shards: %d carried, limit %d (%s). Deletion is %s.",
        WTF.CountShards(), limit, LIMIT_SOURCES[source], deletion))
end

-- /wtf debug_shards: bags, families, the source spells, and recent gains with
-- the spell event just before each one, to find other shard sources in play.
function WTF.ReportShardDebug()
    local available, message = WTF.CheckShardCapabilities()
    if not available then
        WTF.Report("debug_shards " .. message)
        return
    end
    local itemName = type(C_Item) == "table" and type(C_Item.GetItemNameByID) == "function"
        and C_Item.GetItemNameByID(SOUL_SHARD_ITEM_ID)
    WTF.Report(string.format("debug_shards item=%d name=%s", SOUL_SHARD_ITEM_ID, tostring(itemName)))
    for _, source in ipairs(SHARD_SOURCES) do
        local spellName = C_Spell.GetSpellName(source.id)
        WTF.Report(string.format("debug_shards source spell=%d name=%s window=%ds", source.id,
            tostring(spellName), source.window))
    end
    local carried = "n/a"
    if type(C_Item) == "table" and type(C_Item.GetItemCount) == "function" then
        carried = tostring(C_Item.GetItemCount(SOUL_SHARD_ITEM_ID))
    end
    WTF.Report(string.format("debug_shards NUM_BAG_SLOTS=%s NUM_TOTAL_EQUIPPED_BAG_SLOTS=%s itemCount=%s",
        tostring(NUM_BAG_SLOTS), tostring(NUM_TOTAL_EQUIPPED_BAG_SLOTS), carried))
    for bag = BACKPACK, LastCarriedBag() do
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        local items, shards, byID, noInfo = 0, 0, 0, 0
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = type(C_Container.GetContainerItemID) == "function"
                and C_Container.GetContainerItemID(bag, slot)
            if type(info) == "table" then
                items = items + 1
                if info.itemID == SOUL_SHARD_ITEM_ID then
                    shards = shards + info.stackCount
                end
            elseif itemID then
                noInfo = noInfo + 1
            end
            if itemID == SOUL_SHARD_ITEM_ID then
                byID = byID + 1
            end
        end
        WTF.Report(string.format(
            "debug_shards bag=%d slots=%d family=%s soul=%s items=%d shards=%d shardSlotsByID=%d noInfo=%d",
            bag, C_Container.GetContainerNumSlots(bag), tostring(family),
            tostring(bag ~= BACKPACK and SoulBagFamily(bag)), items, shards, byID, noInfo))
    end
    local limit, source = WTF.GetShardLimit()
    WTF.Report(string.format(
        "debug_shards count=%d limit=%d source=%s enabled=%s blocked=%s combatBlocked=%s channeling=%s secretCasts=%s pending=%d",
        WTF.CountShards(), limit, source, tostring(WTF.db and WTF.db.shards.enabled),
        tostring(state.blocked), tostring(state.combatBlocked), tostring(state.channeling),
        tostring(state.secretCasts), #state.pending))
    local now = GetTime()
    for _, gain in ipairs(state.gains) do
        local spell = gain.spell
        WTF.Report(string.format("debug_shards gain %.1fs ago +%d count=%d created=%s combat=%s last=%s %s %.1fs before",
            now - gain.time, gain.amount, gain.count, tostring(gain.created), tostring(gain.combat),
            spell and spell.event or "none", spell and spell.id or "-",
            spell and gain.time - spell.time or 0))
    end
end
