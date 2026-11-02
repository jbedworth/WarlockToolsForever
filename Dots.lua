local _, WTF = ...

-- Nameplate DoT dots: a small bubble above each hostile nameplate in combat,
-- one dot per DoT you know and chose for nameplates, in the tracker's colors;
-- a grey dot means the DoT is missing. Off by default (author-approved), as
-- it can get busy. Since 1.5.0 the engine is Dyre's Toolkit's (PlateDots.lua's
-- CreatePlateDots, 2.5.0, moved from here), on the DoT tracker's engine and
-- WTF's db.tracker settings.

local dots = {available = false}

-- At least one DoT you know, whatever the nameplate choices.
function WTF.HasTrackableDots()
    if not dots.available then
        return false
    end
    for _, slot in ipairs(WTF.DOT_SLOTS) do
        if slot.dot and WTF.TrackerKnowsSlot(slot.key) then
            return true
        end
    end
    return false
end

-- The colored dots are the bubbles' own regions, so they change color at once.
function WTF.ApplyDotColors()
    if dots.available then
        dots.engine:ApplyColors()
    end
end

function WTF.SetPlateDotsOpacity(percent)
    WTF.db.tracker.plateDotsOpacity = WTF.SanitizeWhole(percent, WTF.PLATE_DOTS_OPACITY_MIN,
        WTF.PLATE_DOTS_OPACITY_MAX, WTF.DEFAULT_PLATE_DOTS_OPACITY)
    if dots.available then
        dots.engine:ApplyOpacity()
    end
end

function WTF.RefreshPlateDots()
    if dots.available then
        dots.engine:Refresh()
    end
end

function WTF.InitializePlateDots()
    local tracker = WTF.DotTracker()
    if not tracker then
        return
    end
    local engine = WTF.shared.CreatePlateDots({tracker = tracker, store = WTF.db.tracker})
    if not engine then
        return
    end
    dots.engine = engine
    dots.available = true
end
