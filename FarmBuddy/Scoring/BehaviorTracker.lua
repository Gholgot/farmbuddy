local addonName, FB = ...

FB.BehaviorTracker = {}

--[[
    Behavior Tracker: Learns from player actions to personalize recommendations.
    Only adjusts weights after sufficient data (10+ sessions).
    All adjustments are transparent and reversible.
]]

-- FIX-10: Anti-feedback-loop — more conservative thresholds
local MIN_SESSIONS_FOR_LEARNING = 20  -- Was 10: require more data before adjusting
local LEARNING_RATE = 0.05            -- Was 0.1: slower learning
local MAX_ADJUSTMENT = 0.2            -- Was 0.5: max ±20% instead of ±50%

-- Record that the player clicked on a mount in recommendations
function FB.BehaviorTracker:RecordClick(sourceType)
    if not sourceType or not FB.db or not FB.db.behaviorLog then return end
    local log = FB.db.behaviorLog
    log.sourceTypeClicks = log.sourceTypeClicks or {}
    log.sourceTypeClicks[sourceType] = (log.sourceTypeClicks[sourceType] or 0) + 1
end

-- Record that a mount was shown but the player scrolled past it
function FB.BehaviorTracker:RecordSkip(sourceType)
    if not sourceType or not FB.db or not FB.db.behaviorLog then return end
    local log = FB.db.behaviorLog
    log.sourceTypeSkips = log.sourceTypeSkips or {}
    log.sourceTypeSkips[sourceType] = (log.sourceTypeSkips[sourceType] or 0) + 1
end

-- Record session completion
function FB.BehaviorTracker:RecordSession(durationMinutes)
    if not FB.db or not FB.db.behaviorLog then return end
    local log = FB.db.behaviorLog

    log.totalSessions = (log.totalSessions or 0) + 1

    -- Rolling average session length
    local prev = log.avgSessionMinutes or 0
    local n = log.totalSessions
    log.avgSessionMinutes = prev + (durationMinutes - prev) / n

    -- Record in session history (cap at 50 entries)
    FB.db.sessionHistory = FB.db.sessionHistory or {}
    local history = FB.db.sessionHistory
    history[#history + 1] = {
        timestamp = time(),
        durationMins = durationMinutes,
    }
    -- Trim to 50
    while #history > 50 do
        table.remove(history, 1)
    end
end

-- Check if we have enough data to adjust weights
function FB.BehaviorTracker:HasSufficientData()
    if not FB.db or not FB.db.behaviorLog then return false end
    return (FB.db.behaviorLog.totalSessions or 0) >= MIN_SESSIONS_FOR_LEARNING
end

-- Get personalized weight adjustments based on behavior
-- Returns a table of multipliers: { [weightKey] = multiplier }
-- Multipliers are 0.5 to 1.5 (50% reduction to 50% increase)
function FB.BehaviorTracker:GetWeightAdjustments()
    if not self:HasSufficientData() then return nil end
    if not FB.db or not FB.db.behaviorLog then return nil end

    local log = FB.db.behaviorLog
    local clicks = log.sourceTypeClicks or {}
    local skips = log.sourceTypeSkips or {}
    local adjustments = {}

    -- Analyze source type preferences to adjust group/effort weights
    local totalClicks = 0
    local totalSkips = 0
    for _, count in pairs(clicks) do totalClicks = totalClicks + count end
    for _, count in pairs(skips) do totalSkips = totalSkips + count end

    if totalClicks + totalSkips < 20 then return nil end  -- Not enough interactions

    -- FIX-10: Temporal decay — recent sessions count more than old ones
    -- Apply exponential decay to click/skip counts based on session history
    local sessionAge = (log.totalSessions or 0) - MIN_SESSIONS_FOR_LEARNING
    -- FEAT-6: Gradual continuous decay instead of binary step.
    -- Smoothly reduces influence from 1.0 to 0.5 over 100 sessions past the threshold.
    local decayFactor = math.max(0.5, 1.0 - (sessionAge / 100) * 0.5)

    -- If player consistently skips group content, increase groupRequirement weight.
    -- Group detection is by source type ("pvp", "raid_drop"), not by group size labels.
    local groupClicks = 0
    local groupShown = 0
    for sourceType, count in pairs(clicks) do
        if sourceType == "pvp" or sourceType == "raid_drop" then
            groupClicks = groupClicks + count
        end
    end
    for sourceType, count in pairs(skips) do
        if sourceType == "pvp" or sourceType == "raid_drop" then
            groupShown = groupShown + count
        end
    end

    -- If they click group content less than average, penalize it
    local groupRatio = groupClicks / math.max(1, groupClicks + groupShown)
    local overallRatio = totalClicks / math.max(1, totalClicks + totalSkips)

    if groupRatio < overallRatio * 0.5 then
        -- Player avoids group content (scaled by decay)
        adjustments.groupRequirement = 1.0 + (MAX_ADJUSTMENT * decayFactor)
    elseif groupRatio > overallRatio * 1.5 then
        -- Player seeks group content (scaled by decay)
        adjustments.groupRequirement = 1.0 - (MAX_ADJUSTMENT * 0.5 * decayFactor)
    end

    -- Session length preference: if average session is short, weight time higher
    local avgSession = log.avgSessionMinutes or 60
    if avgSession < 30 then
        adjustments.timePerAttempt = 1.0 + (LEARNING_RATE * 2 * decayFactor)
    elseif avgSession > 120 then
        adjustments.timePerAttempt = 1.0 - (LEARNING_RATE * decayFactor)
    end

    return adjustments
end

-- Apply behavior adjustments to base weights
function FB.BehaviorTracker:ApplyAdjustments(baseWeights)
    local adjustments = self:GetWeightAdjustments()
    if not adjustments then return baseWeights end

    local adjusted = {}
    for key, value in pairs(baseWeights) do
        local multiplier = adjustments[key] or 1.0
        adjusted[key] = value * math.max(1.0 - MAX_ADJUSTMENT, math.min(1.0 + MAX_ADJUSTMENT, multiplier))
    end
    return adjusted
end

-- Get a summary of learned preferences (for Settings display)
function FB.BehaviorTracker:GetLearningSummary()
    if not FB.db or not FB.db.behaviorLog then
        return "No behavior data collected yet."
    end

    local log = FB.db.behaviorLog
    local parts = {}
    parts[#parts + 1] = string.format("Sessions: %d", log.totalSessions or 0)
    parts[#parts + 1] = string.format("Avg session: %.1f min", log.avgSessionMinutes or 0)

    if self:HasSufficientData() then
        parts[#parts + 1] = "Learning: ACTIVE"
        local adjustments = self:GetWeightAdjustments()
        if adjustments then
            for key, mult in pairs(adjustments) do
                local pct = math.floor((mult - 1.0) * 100)
                if pct ~= 0 then
                    parts[#parts + 1] = string.format("  %s: %+d%%", key, pct)
                end
            end
        end
    else
        parts[#parts + 1] = string.format(
            "Learning: needs %d more sessions",
            MIN_SESSIONS_FOR_LEARNING - (log.totalSessions or 0)
        )
    end

    return table.concat(parts, "\n")
end

-- Reset all learned behavior (user action from Settings)
function FB.BehaviorTracker:Reset()
    if not FB.db then return end
    FB.db.behaviorLog = {
        sourceTypeClicks = {},
        sourceTypeSkips = {},
        avgSessionMinutes = 0,
        totalSessions = 0,
    }
    FB.db.sessionHistory = {}
    FB:Print("Behavior learning data reset.")
end
