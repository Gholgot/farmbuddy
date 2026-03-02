local addonName, FB = ...

FB.Scoring = {}

-- Default scoring weights
local DEFAULT_WEIGHTS = {
    progressRemaining = 1.0,
    timePerAttempt    = 1.0,
    timeGate          = 1.5,
    groupRequirement  = 1.2,
    effort            = 1.0,
}

-- Get current weights (from saved vars or defaults)
function FB.Scoring:GetWeights()
    if FB.db and FB.db.settings and FB.db.settings.weights then
        return FB.db.settings.weights
    end
    return DEFAULT_WEIGHTS
end

function FB.Scoring:GetDefaultWeights()
    return FB.Utils:DeepCopy(DEFAULT_WEIGHTS)
end

--[[
    Score a mount or achievement based on remaining effort.
    Lower score = easier to obtain.

    @param input table:
        progressRemaining   (0.0 to 1.0, 0 = done)
        timePerAttempt      (minutes per attempt)
        timeGate            ("none", "daily", "weekly", "yearly")
        attemptsRemaining   (0 = locked this period, 1+ = available)
        groupRequirement    ("solo", "duo", "small", "full", "mythic")
        dropChance          (0.0 to 1.0, nil if guaranteed)
        expectedAttempts    (derived: for RNG items)
        warbandAvailable    (number: how many alts can still attempt, nil = ignore)
        warbandTotal        (number: total tracked characters, nil = ignore)
        instanceGroupCount  (number: other mounts obtainable from same instance run)
        staleDays           (number: days since last attempt, nil = never tracked)

    @return table:
        score               (final weighted score, lower = easier)
        components          (individual component scores)
        effectiveDays       (estimated calendar days to completion)
        immediatelyAvailable (bool: can you attempt right now?)
        scoreExplanation    (string: plain-English summary of why this score)
--]]
function FB.Scoring:Score(input, weights)
    weights = weights or self:GetWeights()

    if not input then
        return { score = 99999, components = {}, effectiveDays = 99999, immediatelyAvailable = false, scoreExplanation = "No data" }
    end

    -- Clamp and validate inputs
    local progressRemaining = math.max(0, math.min(1, input.progressRemaining or 1.0))
    local timePerAttempt = math.max(0, math.min(600, input.timePerAttempt or 10))
    local dropChance = input.dropChance
    if dropChance then
        dropChance = math.max(0.0001, math.min(1, dropChance))
    end

    -- ===================================================================
    -- COMPUTE EFFORT FIRST — needed to scale progress for guaranteed mounts
    -- ===================================================================

    -- FIX-2: Detect unknown-drop mounts (drop types without verified rates)
    -- Uses FB.DROP_SOURCE_TYPES defined in Core\Constants.lua (MED-2)
    local isDropType = FB.DROP_SOURCE_TYPES[input.sourceType or ""] or false
    local isUnknownDrop = isDropType and not dropChance

    -- Component 5: Total Expected Effort (computed early, used by progressScore)
    local expectedAttempts
    if dropChance and dropChance > 0 and dropChance < 1 then
        expectedAttempts = math.ceil(1 / dropChance)
    elseif isUnknownDrop then
        -- FIX-2: Unknown drop rate — use nil for display, conservative placeholder for scoring
        expectedAttempts = nil  -- Will use placeholder below for effort calc
    else
        expectedAttempts = math.max(1, input.expectedAttempts or 1)
    end

    -- FIX-6: Configurable playtime assumption
    local hoursPerDay = (FB.db and FB.db.settings and FB.db.settings.hoursPerDay) or 2
    hoursPerDay = math.max(0.5, math.min(8, hoursPerDay))

    -- For unknown drops, use conservative placeholder (50 runs) for effort scoring
    local effortAttempts = expectedAttempts or 50
    local totalMinutes = effortAttempts * timePerAttempt
    local totalDays = totalMinutes / (60 * hoursPerDay)

    -- Calendar time: how many real days must pass due to time-gating
    local calendarDays
    local gateMultiplier = FB.TIME_GATE_FACTORS[input.timeGate or "none"] or 0
    local timeGate = input.timeGate or "none"
    -- FIX-5: Warband acceleration respects lockout scope
    -- Per-account lockouts (world bosses) don't benefit from alts
    local warbandAvailable = input.warbandAvailable
    local warbandTotal = input.warbandTotal
    local lockoutScope = input.lockoutScope or "character"
    local warbandMultiplier
    if lockoutScope == "account" then
        warbandMultiplier = 1  -- Per-account: alts don't help
    else
        warbandMultiplier = (warbandAvailable and warbandAvailable > 1 and gateMultiplier > 0)
            and warbandAvailable or 1
    end

    if timeGate == "yearly" then
        -- Yearly events give ~14 daily attempts during a 2-week window
        -- With warband: each alt adds 14 more attempts per event
        local attemptsPerEvent = 14 * warbandMultiplier
        if dropChance and dropChance > 0 and dropChance < 1 then
            local pPerEvent = 1 - (1 - dropChance) ^ attemptsPerEvent
            if pPerEvent > 0 then
                local eventsNeeded = math.ceil(1 / pPerEvent)
                calendarDays = eventsNeeded * 365
            else
                calendarDays = 99999
            end
        else
            local eventsNeeded = math.ceil(effortAttempts / attemptsPerEvent)
            calendarDays = eventsNeeded * 365
        end
    elseif gateMultiplier > 0 then
        -- Non-yearly gated: warband divides calendar days (more alts = faster)
        calendarDays = (effortAttempts * gateMultiplier) / warbandMultiplier
    else
        calendarDays = totalDays
    end

    -- Effective days = the larger of play time needed vs calendar time
    local effectiveDays = math.max(totalDays, calendarDays)

    -- Guard against infinity/NaN
    if effectiveDays ~= effectiveDays or effectiveDays == math.huge then
        effectiveDays = 99999
    end

    -- Normalize effort score (0-100) using log scale for better spread
    -- log scale: 1d=0, 7d=30, 30d=51, 100d=69, 365d=89
    local effortScore = math.min(100, math.log(effectiveDays + 1) * 15)

    -- FIX-2: Confidence penalty for unknown-drop mounts
    -- Rank lower than known-rate mounts with similar time/lockout
    if isUnknownDrop then
        effortScore = effortScore * 1.15  -- 15% penalty
    end

    -- ===================================================================
    -- COMPUTE REMAINING COMPONENTS
    -- ===================================================================

    -- Component 1: Progress Remaining
    -- For RNG drop mounts: effort score already covers difficulty, so progressScore=0.
    -- For guaranteed mounts: scale progress by effort so "haven't started a 30min task"
    -- isn't penalized the same as "haven't started a 30-day grind".
    -- Without this fix, Riddler's Mind-Worm (guaranteed, 30min) would score worse
    -- than Ashes of Al'ar (~1 year of weekly lockouts).
    local progressScore
    if dropChance and dropChance > 0 and dropChance < 1 then
        progressScore = 0  -- Drop-based: effort score covers difficulty
    else
        -- Scale progress by effort: "1.0 remaining on a 3-point effort" = 3, not 100
        -- This makes guaranteed mounts rank by their actual remaining work
        progressScore = progressRemaining * effortScore
    end

    -- Component 2: Time Per Attempt (0-25, halved to reduce double-counting with effort)
    -- timePerAttempt already feeds into effortScore via totalMinutes, so this component
    -- captures "session unpleasantness" (a 25min run is worse than 5min even at same total)
    -- but at half weight to avoid over-penalizing long-clear-time guaranteed mounts.
    -- Previously (50/60) ≈ 0.833 per minute which was NOT half; now (25/60) ≈ 0.417.
    local timeScore = math.min(timePerAttempt, 60) * (25 / 60)

    -- Component 3: Time Gate (0-100)
    local immediatelyAvailable = (input.attemptsRemaining or 1) > 0
    local gateScore
    if immediatelyAvailable then
        gateScore = math.log(gateMultiplier + 1) * 5
    else
        gateScore = math.log(gateMultiplier + 1) * 15
    end
    gateScore = math.min(gateScore, 100)

    -- Component 4: Group Requirement (0-100)
    local groupFactor = FB.GROUP_FACTORS[input.groupRequirement or "solo"] or 1.0
    local groupScore = (groupFactor - 1.0) * 25
    groupScore = math.min(groupScore, 100)

    -- ===================================================================
    -- WEIGHTED SUM
    -- ===================================================================

    local score = (progressScore   * math.max(0, weights.progressRemaining or 1.0))
                + (timeScore       * math.max(0, weights.timePerAttempt or 1.0))
                + (gateScore       * math.max(0, weights.timeGate or 1.5))
                + (groupScore      * math.max(0, weights.groupRequirement or 1.2))
                + (effortScore     * math.max(0, weights.effort or 1.0))

    -- ===================================================================
    -- BONUSES & PENALTIES (multiplicative to preserve relative ordering)
    -- ===================================================================
    -- All bonuses are multiplicative discounts (0.xx) rather than flat
    -- subtractions. This prevents low-score mounts from clamping to 0
    -- and ensures easy mounts remain differentiable from each other.

    -- Availability bonus: scaled by time gate and prerequisite status
    -- S1: Only apply full discount for drop mounts or mounts with met prerequisites
    -- S2: Scale discount by time gate instead of flat 25%
    if immediatelyAvailable then
        local isDropMount = (dropChance and dropChance > 0 and dropChance < 1)
        local prerequisiteMet = (progressRemaining <= 0) or isDropMount

        if prerequisiteMet then
            -- S2: Graduated bonus by time gate
            local availabilityDiscounts = {
                none = 0.25,    -- Unlimited farm: full discount
                daily = 0.15,   -- Daily gated: moderate discount
                biweekly = 0.12, -- Biweekly gated: between daily and weekly
                weekly = 0.10,  -- Weekly gated: smaller discount
                monthly = 0.09, -- Monthly rotation: small discount
                yearly = 0.08,  -- Yearly event: minimal discount
            }
            local discount = availabilityDiscounts[input.timeGate or "none"] or 0.15
            score = score * (1 - discount)
        end
        -- S1: Non-drop mounts with incomplete progress get NO availability bonus
        -- (e.g., vendor mount needing Exalted when player is at Friendly)
    end

    -- Warband availability bonus: if current char is locked but alts are free,
    -- give a scaled discount based on how many alts can still run it.
    -- 1 alt = 15% off, 2 alts = 18%, 3+ alts = 20% (approaches the 25% "available" discount)
    if not immediatelyAvailable and warbandAvailable and warbandAvailable > 0 then
        local altDiscount = math.min(0.20, 0.10 + math.log(warbandAvailable + 1) * 0.05)
        score = score * (1 - altDiscount)
    end

    -- Instance efficiency bonus: multiple mounts from the same instance run
    local instanceGroupCount = input.instanceGroupCount
    if instanceGroupCount and instanceGroupCount > 1 then
        local efficiencyDiscount = math.min(0.15, math.log(instanceGroupCount) * 0.08)
        score = score * (1 - efficiencyDiscount)
    end

    -- Staleness nudge: mounts not attempted recently get a small boost
    local staleDays = input.staleDays
    if staleDays and staleDays > 7 then
        local stalenessDiscount = math.min(0.10, math.log(staleDays / 7 + 1) * 0.03)
        score = score * (1 - stalenessDiscount)
    end

    -- "Completable today" bonus: guaranteed mounts nearly done get extra discount
    -- S3: Mount at 99% completion (1 more quest) should surface above mount at 50%
    local isDropMount = (dropChance and dropChance > 0 and dropChance < 1)
    if not isDropMount and progressRemaining <= 0.05 and immediatelyAvailable then
        -- Scale: 0% remaining = 20% discount, 5% remaining = 4% discount
        local completionDiscount = 0.20 * (1 - (progressRemaining / 0.05))
        score = score * (1 - completionDiscount)
    end

    -- Guard against NaN in final score, floor at 0 for UI sanity
    if score ~= score then score = 99999 end
    score = math.max(0, score)

    -- Build plain-English score explanation (Fix #4)
    local explanation = self:BuildExplanation(input, {
        progressScore = progressScore,
        timeScore = timeScore,
        gateScore = gateScore,
        groupScore = groupScore,
        effortScore = effortScore,
        effectiveDays = effectiveDays,
        immediatelyAvailable = immediatelyAvailable,
        warbandAvailable = warbandAvailable,
        instanceGroupCount = instanceGroupCount,
        staleDays = staleDays,
        isUnknownDrop = isUnknownDrop,
        hoursPerDay = hoursPerDay,
    })

    return {
        score = score,
        components = {
            progress = progressScore,
            time = timeScore,
            gate = gateScore,
            group = groupScore,
            effort = effortScore,
        },
        effectiveDays = effectiveDays,
        expectedAttempts = expectedAttempts,  -- nil for unknown-drop mounts
        immediatelyAvailable = immediatelyAvailable,
        scoreExplanation = explanation,
        isUnknownDrop = isUnknownDrop or false,
    }
end

-- Build a plain-English explanation of why a mount scored the way it did
function FB.Scoring:BuildExplanation(input, data)
    local parts = {}

    -- Dominant factor analysis: find which component contributed most
    local maxComp = 0
    local maxCompName = ""
    local compMap = {
        { name = "progress", val = data.progressScore, label = "incomplete progress" },
        { name = "time", val = data.timeScore, label = "long clear time" },
        { name = "gate", val = data.gateScore, label = "time-gating" },
        { name = "group", val = data.groupScore, label = "group requirement" },
        { name = "effort", val = data.effortScore, label = "total expected effort" },
    }
    for _, comp in ipairs(compMap) do
        if comp.val > maxComp then
            maxComp = comp.val
            maxCompName = comp.label
        end
    end

    -- Quick summary of positives
    if input.groupRequirement == "solo" or input.groupRequirement == nil then
        parts[#parts + 1] = "solo"
    end
    if input.timePerAttempt and input.timePerAttempt <= 10 then
        parts[#parts + 1] = "quick run"
    end
    if input.timeGate == "none" then
        parts[#parts + 1] = "no lockout"
    elseif input.timeGate == "weekly" then
        parts[#parts + 1] = "weekly lockout"
    elseif input.timeGate == "daily" then
        parts[#parts + 1] = "daily lockout"
    elseif input.timeGate == "yearly" then
        parts[#parts + 1] = "yearly event only"
    elseif input.timeGate == "monthly" then
        parts[#parts + 1] = "monthly rotation"
    elseif input.timeGate == "biweekly" then
        parts[#parts + 1] = "biweekly lockout"
    end

    -- FIX-3: Drop chance source transparency
    if input.dropChance then
        local pct = input.dropChance * 100
        local sourceTag = ""
        if input.dropChanceSource == "curated" then
            sourceTag = " (verified)"
        elseif input.dropChanceSource == "rarity_db" then
            sourceTag = " (community data)"
        end
        if pct >= 5 then
            parts[#parts + 1] = string.format("%.0f%% drop%s", pct, sourceTag)
        elseif pct >= 1 then
            parts[#parts + 1] = string.format("%.1f%% drop%s", pct, sourceTag)
        else
            parts[#parts + 1] = string.format("%.2f%% drop%s", pct, sourceTag)
        end
    elseif data.isUnknownDrop then
        parts[#parts + 1] = "drop rate unknown"
    end

    -- Availability
    if data.immediatelyAvailable then
        parts[#parts + 1] = "available now"
    else
        if data.warbandAvailable and data.warbandAvailable > 0 then
            parts[#parts + 1] = "locked (alt available)"
        else
            parts[#parts + 1] = "locked this reset"
        end
    end

    -- Instance efficiency
    if data.instanceGroupCount and data.instanceGroupCount > 1 then
        parts[#parts + 1] = data.instanceGroupCount .. " mounts from same run"
    end

    -- FIX-7: Estimated time — range for RNG, single for guaranteed
    if data.effectiveDays and data.effectiveDays < 99999 then
        local hoursPerDay = data.hoursPerDay or 2
        if input.dropChance and input.dropChance > 0 and input.dropChance < 1 then
            -- RNG mount: compute attempts per day from time gate
            local gateDays = FB.TIME_GATE_FACTORS[input.timeGate or "none"] or 0
            local attemptsPerDay = gateDays > 0 and (1 / gateDays) or
                math.max(1, math.floor(hoursPerDay * 60 / math.max(1, input.timePerAttempt or 10)))
            local rangeStr = FB.Utils:FormatDaysRange(input.dropChance, attemptsPerDay, hoursPerDay)
            if rangeStr then
                parts[#parts + 1] = rangeStr
            else
                parts[#parts + 1] = "~" .. FB.Utils:FormatDays(data.effectiveDays) .. " (at " .. hoursPerDay .. "h/day)"
            end
        else
            parts[#parts + 1] = "~" .. FB.Utils:FormatDays(data.effectiveDays) .. " (at " .. hoursPerDay .. "h/day)"
        end
    end

    -- Main bottleneck
    if maxComp > 30 then
        parts[#parts + 1] = "bottleneck: " .. maxCompName
    end

    return table.concat(parts, " | ")
end

-- Quick score check: is this mount/achievement worth scanning in detail?
-- Returns false for unobtainable items (real-money purchases, etc.)
function FB.Scoring:IsScoreable(sourceType)
    local excluded = {
        blizzard_shop = true,  -- Real-money only, not farmable in-game
        promotion = true,      -- Catch-all promo (Blizzcon, CE, etc.) — not farmable
                               -- Obtainable subtypes (tcg, recruit_a_friend) are already
                               -- sub-classified by ResolveSourceType and won't hit this
        unknown = true,        -- Unresolvable source — often removed/promo
    }
    -- Note: trading_post is scoreable (obtainable with Trader's Tender)
    -- Note: tcg is scoreable (obtainable via AH for gold)
    -- Note: recruit_a_friend is scoreable (program is periodically active)
    return not excluded[sourceType]
end
