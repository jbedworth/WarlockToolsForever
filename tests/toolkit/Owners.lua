local _, ns = ...
local DyresToolkit = ns.toolkit

-- One owner per kind, for every Dyre's AddOn (Toolkit 2.5.0, engine stage B;
-- lead decision 7a, 2026-11-01). A kind is a feature for one class, such as
-- "control:WARLOCK" (the control bar), "macros:WARLOCK", or
-- "announce:WARLOCK": when two Dyre's AddOns could both do it (a class Tools
-- AddOn and Dyre's Debuff Tracker), only the owner does, so nothing shows,
-- writes, or says twice. The highest priority enabled claim owns a kind; on a
-- tie, the first to claim. A class Tools AddOn claims at 10 and wins for its
-- own class; the Debuff Tracker, the wrapper for classes with no Tools
-- AddOn yet, claims at 5. The HealthBars damage sources use the same rule,
-- and the same gate: only Dyre's AddOns (a TOC with `## Group:
-- DyresToolkit`) may claim, so no other AddOn can silence one.

local kinds = {}

local function Owner(kind)
    local best
    for _, claim in ipairs(kinds[kind] and kinds[kind].claims or {}) do
        if claim.enabled and (not best or claim.priority > best.priority) then
            best = claim
        end
    end
    return best and best.addon or nil
end

-- Listeners hear every change of owner. One that fails is off until reload,
-- and said only in debug mode (as the HealthBars hooks).
local function Tell(kind, before)
    local entry = kinds[kind]
    local now = Owner(kind)
    if now == before then
        return
    end
    for _, listener in ipairs(entry.listeners) do
        if not listener.broken then
            local ok, message = pcall(listener.callback, now, kind)
            if not ok then
                listener.broken = true
                if ns.debug then
                    ns.Report("An owner listener for " .. kind .. " failed and is off until you reload: "
                        .. tostring(message))
                end
            end
        end
    end
end

local function Entry(kind)
    kinds[kind] = kinds[kind] or {claims = {}, listeners = {}}
    return kinds[kind]
end

local function Valid(kind, addon)
    return type(kind) == "string" and kind ~= "" and type(addon) == "string" and addon ~= ""
end

-- Claims a kind for an AddOn at a priority (a number, default 0), enabled.
-- A second claim by the same AddOn changes its priority. Returns whether this
-- AddOn owns the kind now; false and why for a bad call or another AddOn.
function DyresToolkit.ClaimOwner(kind, addon, priority)
    if not Valid(kind, addon) then
        return false, "a claim needs a kind and an addon"
    end
    if not ns.InFamily(addon) then
        return false, "owner claims are for Dyre's AddOns"
    end
    local entry = Entry(kind)
    local before = Owner(kind)
    local claim
    for _, each in ipairs(entry.claims) do
        if each.addon == addon then
            claim = each
        end
    end
    if not claim then
        claim = {addon = addon, enabled = true}
        entry.claims[#entry.claims + 1] = claim
    end
    claim.priority = type(priority) == "number" and priority or 0
    Tell(kind, before)
    return Owner(kind) == addon
end

-- An AddOn's claim on or off (its feature switched off steps aside, so the
-- next one owns the kind). Returns false for a kind it never claimed.
function DyresToolkit.SetOwnerEnabled(kind, addon, enabled)
    local entry = Valid(kind, addon) and kinds[kind]
    if not entry then
        return false, "never claimed"
    end
    if not ns.InFamily(addon) then
        return false, "owner claims are for Dyre's AddOns"
    end
    local before = Owner(kind)
    for _, claim in ipairs(entry.claims) do
        if claim.addon == addon then
            claim.enabled = enabled and true or false
            Tell(kind, before)
            return true
        end
    end
    return false
end

-- The AddOn that owns a kind, else nil.
function DyresToolkit.KindOwner(kind)
    return type(kind) == "string" and Owner(kind) or nil
end

function DyresToolkit.IsOwner(kind, addon)
    return Valid(kind, addon) and Owner(kind) == addon
end

-- callback(owner, kind) on every change of a kind's owner (owner nil: none).
function DyresToolkit.OnOwnerChanged(kind, callback)
    if type(kind) ~= "string" or type(callback) ~= "function" then
        return false
    end
    local entry = Entry(kind)
    entry.listeners[#entry.listeners + 1] = {callback = callback}
    return true
end
