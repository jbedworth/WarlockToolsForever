local _, WTF = ...

-- Magnetic frames (author-approved, as MTF's buff reminders, improved): while
-- frames are unlocked, a frame dropped near another snaps beside it, GAP apart,
-- lined up by their tops, centers, or bottoms (or lefts, centers, or rights
-- when stacked), whichever is nearest. Frames that far apart and lined up are
-- snapped; Shift-dragging one moves every frame snapped to it, and the group
-- snaps as one to the frames outside it. Each module registers its frame with
-- a function that saves the frame's position; positions save as the frame's
-- center from UIParent's bottom left. Dragging happens only out of combat.

local GAP = 20
local SNAP_RANGE = 24
local SNAP_TOLERANCE = 1.5

local layout = {saves = {}, order = {}, dragging = {}}

function WTF.RegisterMovable(frame, save)
    if not layout.saves[frame] then
        layout.order[#layout.order + 1] = frame
    end
    layout.saves[frame] = save
end

-- A frame's center and half size in UIParent units.
local function Box(frame)
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x, y = frame:GetCenter()
    return x * ratio, y * ratio, frame:GetWidth() * ratio / 2, frame:GetHeight() * ratio / 2
end

local function MoveTo(frame, x, y)
    local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    local position = {point = "CENTER", relativePoint = "BOTTOMLEFT", x = x * ratio, y = y * ratio}
    frame:ClearAllPoints()
    frame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    layout.saves[frame](position)
end

local function ShownFrames()
    local shown = {}
    for _, frame in ipairs(layout.order) do
        if frame:IsShown() then
            shown[#shown + 1] = frame
        end
    end
    return shown
end

-- Side by side (or stacked) the gap apart, and overlapping along the other axis.
local function Snapped(a, b)
    local ax, ay, aw, ah = Box(a)
    local bx, by, bw, bh = Box(b)
    local dx, dy = math.abs(ax - bx), math.abs(ay - by)
    return (math.abs(dx - (aw + bw + GAP)) <= SNAP_TOLERANCE and dy < ah + bh)
        or (math.abs(dy - (ah + bh + GAP)) <= SNAP_TOLERANCE and dx < aw + bw)
end

-- Every frame joined to this one through snapped neighbors.
local function SnappedGroup(frame)
    local group, seen, queue = {}, {[frame] = true}, {frame}
    local shown = ShownFrames()
    while #queue > 0 do
        local current = table.remove(queue, 1)
        group[#group + 1] = current
        for _, other in ipairs(shown) do
            if not seen[other] and Snapped(current, other) then
                seen[other] = true
                queue[#queue + 1] = other
            end
        end
    end
    return group
end

-- The nearest spot beside a frame outside skip, within reach, or nil.
local function SnapPoint(frame, skip)
    local x, y, width, height = Box(frame)
    local bestX, bestY, bestDistance
    local function Consider(spotX, spotY)
        local distance = math.sqrt((spotX - x) ^ 2 + (spotY - y) ^ 2)
        if distance <= SNAP_RANGE and (not bestDistance or distance < bestDistance) then
            bestX, bestY, bestDistance = spotX, spotY, distance
        end
    end
    for _, other in ipairs(ShownFrames()) do
        if not skip[other] then
            local ox, oy, otherWidth, otherHeight = Box(other)
            local alignY = {oy + otherHeight - height, oy, oy - otherHeight + height}
            local alignX = {ox - otherWidth + width, ox, ox + otherWidth - width}
            for _, side in ipairs({1, -1}) do
                for _, spotY in ipairs(alignY) do
                    Consider(ox + side * (otherWidth + width + GAP), spotY)
                end
                for _, spotX in ipairs(alignX) do
                    Consider(spotX, oy + side * (otherHeight + height + GAP))
                end
            end
        end
    end
    return bestX, bestY
end

-- Changes a frame's scale without moving its center, and saves it.
function WTF.ScaleKeepingCenter(frame, scale)
    local x, y = Box(frame)
    frame:SetScale(scale)
    MoveTo(frame, x, y)
end

function WTF.BeginDrag(frame)
    if WTF.db.locked or InCombatLockdown() then
        return
    end
    local group = {frame}
    -- Shift: the snapped group follows, anchored to the dragged frame.
    if IsShiftKeyDown() then
        group = SnappedGroup(frame)
        local scale = frame:GetEffectiveScale()
        local leadX, leadY = frame:GetCenter()
        for index = 2, #group do
            local follower = group[index]
            local followerScale = follower:GetEffectiveScale()
            local x, y = follower:GetCenter()
            follower:ClearAllPoints()
            follower:SetPoint("CENTER", frame, "CENTER", (x * followerScale - leadX * scale) / followerScale,
                (y * followerScale - leadY * scale) / followerScale)
        end
    end
    layout.dragging[frame] = group
    frame:StartMoving()
end

function WTF.EndDrag(frame)
    local group = layout.dragging[frame]
    if not group then
        return
    end
    layout.dragging[frame] = nil
    frame:StopMovingOrSizing()
    local inGroup = {}
    for _, member in ipairs(group) do
        inGroup[member] = true
    end
    local x, y = Box(frame)
    local snapX, snapY = SnapPoint(frame, inGroup)
    local shiftX, shiftY = (snapX or x) - x, (snapY or y) - y
    for _, member in ipairs(group) do
        local memberX, memberY = Box(member)
        MoveTo(member, memberX + shiftX, memberY + shiftY)
    end
end
