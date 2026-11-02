local _, WTF = ...

-- DoT damage prediction (John, 1.4.0: phase 1, Classic Era only): a purple
-- block on the health bar of your target, of each hostile nameplate, and of
-- each DoT tracker row with mob health on, the size of the damage your DoTs
-- still have to deal, and "DIES" when that is at least the mob's health. It
-- needs the combat log, so on Forever (restricted) nothing is made. Since
-- 1.5.0 the engine is Dyre's Toolkit's (DotPredict.lua's CreateDotPredictor,
-- 2.5.0, moved from here; its header holds the rules), a HealthBars damage
-- source at priority 10 (Dyre's Debuff Tracker draws above it). WTF keeps its
-- settings (db.predict, repaired in Core), its colors, and its Options; its
-- learned ticks (WarlockToolsForeverAccountDB.ticks) are copied once to the
-- Toolkit's one store for every Dyre's AddOn.

local PREDICT_PRIORITY = 10

local predict = {available = false}

local function Color()
    for _, preset in ipairs(WTF.PREDICT_COLORS) do
        if preset.key == WTF.db.predict.color then
            return preset.color
        end
    end
end

function WTF.PredictAvailable()
    return predict.available
end

function WTF.PredictedDamage(guid)
    if not predict.available then
        return 0
    end
    return WTF.predictor:PredictedDamage(guid)
end

-- Settings changed.
function WTF.RefreshPredict()
    if predict.available then
        WTF.predictor:Refresh()
    end
end

-- Before the DoT tracker (Core), whose rows draw the predictor's damage.
function WTF.InitializePredict()
    local predictor = WTF.shared.CreateDotPredictor({
        addon = "WarlockToolsForever",
        priority = PREDICT_PRIORITY,
        class = "WARLOCK",
        store = WTF.db.predict,
        color = Color,
        legacyTicks = WTF.accountDB.ticks,
    })
    if not predictor then
        return
    end
    WTF.predictor = predictor
    predict.available = true
end

-- /wtf debug_predict: each mob's DoTs, ticks, the average tick and where it
-- came from (learned, saved, or guessed), and the damage to come.
function WTF.ReportPredictDebug()
    if not predict.available then
        WTF.Report("DoT prediction: off on this client (it needs the combat log, as on Classic Era).")
        return
    end
    for index, line in ipairs(WTF.predictor:DebugLines()) do
        WTF.Report(index == 1 and ("DoT prediction: " .. line) or line)
    end
end
