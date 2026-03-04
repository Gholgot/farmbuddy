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
    local base
    if FB.db and FB.db.settings and FB.db.settings.weights then
        base = FB.db.settings.weights
    else
        base = DEFAULT_WEIGHTS
    end
    if FB.BehaviorTracker and FB.BehaviorTracker.ApplyAdjustments then
        return FB.BehaviorTracker:ApplyAdjustments(base)
    end
    return base
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
        sourceType          (string: used for source-specific scoring adjustments)
        goldCost            (number: gold cost for vendor mounts, nil if not applicable)
        factionID           (number: faction ID for reputation mounts)
        currencyID          (number: currency ID for currency mounts)
        achievementID       (number: achievement ID for achievement mounts)
        rarity              (number: ownership % from Data for Azeroth, nil if unknown)
        repEstimatedDays    (number: estimated days to exalted, nil if unknown)

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
    -- SOURCE TYPE CLASSIFICATION — drives fundamental scoring logic
    -- ===================================================================

    local sourceType = input.sourceType or "unknown"
    local isDropType = FB.DROP_SOURCE_TYPES[sourceType] or false
    local isUnknownDrop = isDropType and not dropChance

    -- Detect "instant acquisition" mounts: available right now with no RNG.
    -- These are the best scoring mounts — the whole point of the recommendation tab.
    -- A mount is "instant" when:
    --   (a) No time gate (not locked to a reset period)
    --   (b) No RNG (guaranteed reward)
    --   (c) Progress is complete (or nearly so, within 5%), OR
    --   (d) SPECIAL CASE: vendor/TCG/RAF mounts with no tracked requirements
    --       (progressRemaining=1.0 default = "no barriers detected", not "100% blocked")
    --       Just go to the vendor and buy it.
    -- Vendor mounts with no tracked requirements: just go buy them.
    -- Profession mounts are NOT included because they require materials (not tracked).
    -- Trading post is also excluded (has monthly time gate, handled separately).
    local vendorNoRequirements = (sourceType == "vendor"
        or sourceType == "tcg" or sourceType == "recruit_a_friend")
        and not input.factionID and not input.currencyID and not input.achievementID
        and (not input.goldCost or input.goldCost == 0)
        and (input.timeGate == "none" or input.timeGate == nil)
    local isInstantAvailable = (not dropChance or dropChance >= 1.0)
        and (input.timeGate == "none" or input.timeGate == nil)
        and (progressRemaining <= 0.05 or vendorNoRequirements)
        and (input.attemptsRemaining or 1) > 0

    -- Source-type categories for scoring adjustments
    local isVendorType = (sourceType == "vendor" or sourceType == "trading_post"
        or sourceType == "tcg" or sourceType == "recruit_a_friend")
    local isQuestType = (sourceType == "quest_chain")
    local isAchievementType = (sourceType == "achievement")

    -- ===================================================================
    -- COMPUTE EFFORT FIRST — needed to scale progress for guaranteed mounts
    -- ===================================================================

    -- Component 5: Total Expected Effort (computed early, used by progressScore)
    local expectedAttempts
    if dropChance and dropChance > 0 and dropChance < 1 then
        -- Median attempts at 50% probability: ceil(log(0.5)/log(1-p))
        expectedAttempts = math.ceil(math.log(0.5) / math.log(1 - dropChance))
    elseif isUnknownDrop then
        -- Unknown drop rate — use nil for display, conservative placeholder for scoring
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

    -- Warband acceleration respects lockout scope
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

    -- ===================================================================
    -- EFFORT SCORE — primary "how hard is this to farm" signal
    -- ===================================================================
    -- Log scale for better spread across the full range:
    --   0 min   =  0 pts (instant: vendor, quest done)
    --   1 day   = ~10 pts
    --   7 days  = ~29 pts (weekly lockout, ~1% drop rate)
    --   30 days = ~51 pts (month of farming)
    --   100 days= ~69 pts (serious grind)
    --   365 days= ~89 pts (Ashes of Al'ar territory)
    --   1000d+  = 100 pts cap
    local effortScore = math.min(100, math.log(effectiveDays + 1) * 15)

    -- Drop chance amplification: for RNG mounts, weight by the variability risk.
    -- A 0.01% drop is far worse than a 1% drop even with the same "median" attempt count,
    -- because unlucky players can wait 10x longer. Use the 95th-percentile attempt count
    -- (instead of median 50th) as a secondary penalty for very low-rate mounts.
    if dropChance and dropChance > 0 and dropChance < 1 then
        -- 95th-percentile attempts: log(0.05)/log(1-p)
        local p95Attempts = math.ceil(math.log(0.05) / math.log(1 - dropChance))
        -- Variance factor: how much worse could the 95th-percentile be vs the median?
        -- For 1% drop: median=69, p95=299 → factor=4.3
        -- For 0.1% drop: median=693, p95=2995 → factor=4.3 (same, but absolute penalty is huge)
        -- We apply a small log-scaled variance penalty on top of the base effort score.
        local p95Days
        if gateMultiplier > 0 then
            p95Days = (p95Attempts * gateMultiplier) / math.max(1, warbandMultiplier)
        else
            p95Days = p95Attempts * timePerAttempt / (60 * hoursPerDay)
        end
        p95Days = math.min(p95Days, 99999)
        local p95Score = math.min(100, math.log(p95Days + 1) * 15)
        -- Blend: 75% median effort, 25% p95 effort — reflects expected experience
        effortScore = effortScore * 0.75 + p95Score * 0.25
        effortScore = math.min(100, effortScore)
    end

    -- Confidence penalty for unknown-drop mounts
    -- Rank lower than known-rate mounts with similar time/lockout
    if isUnknownDrop then
        effortScore = effortScore * 1.15  -- 15% penalty
    end

    -- Rep estimation bonus: if we have precise rep day estimates, use them
    -- to refine effectiveDays for display accuracy (scoring already uses expectedAttempts)
    if input.repEstimatedDays and input.repEstimatedDays > 0 then
        local repDays = input.repEstimatedDays
        -- Only update effectiveDays if the rep estimate is meaningful
        if repDays > effectiveDays * 0.5 then
            effectiveDays = math.max(effectiveDays, repDays)
        end
    end

    -- ===================================================================
    -- COMPUTE REMAINING COMPONENTS
    -- ===================================================================

    -- Component 1: Progress Remaining
    -- Fundamental philosophy:
    --   - Drop mounts: effortScore already captures RNG difficulty → progressScore = 0
    --     (unless there are pre-requisites that need completing first)
    --   - Guaranteed mounts (vendor, quest, achievement, rep): scale progress by effort
    --     so "haven't started a 30-min quest" ranks far better than "haven't started a
    --     30-day rep grind" — both at progressRemaining=1.0 but very different effort.
    local progressScore
    if dropChance and dropChance > 0 and dropChance < 1 then
        progressScore = 0  -- Drop-based: effort score covers RNG difficulty

        -- Prerequisite penalty: if the drop mount has unfulfilled gate requirements
        -- (reputation, currency, achievement unlock), surface that as progress cost.
        -- This prevents "you can't even attempt it yet" from being ignored.
        if progressRemaining > 0.05 and
           (input.factionID or input.currencyID or input.achievementID
            or (input.goldCost and input.goldCost > 0)) then
            -- Use a fixed penalty that scales with how incomplete the prerequisite is,
            -- but cap it so it doesn't dominate the effort score for hard mounts.
            progressScore = math.min(progressRemaining * 30, effortScore * 0.5)
        end
    else
        -- Guaranteed mount: progress is the main signal.
        -- Scale by effortScore so the magnitude reflects actual remaining work.
        -- progressRemaining=1.0 on a 0-day mount = 0 score addition (nothing to do)
        -- progressRemaining=1.0 on a 100-day rep grind = 69 score addition (huge work ahead)
        progressScore = progressRemaining * effortScore
    end

    -- Component 2: Time Per Attempt (0-25)
    -- timePerAttempt already feeds into effortScore via totalMinutes, so this component
    -- captures "session unpleasantness" — a 30-min dungeon run is more annoying than
    -- a 5-min loot trip even at the same total expected time.
    -- Kept at half-weight (25/60 ≈ 0.417/min) to avoid over-penalizing long content.
    local timeScore = math.min(timePerAttempt, 60) * (25 / 60)

    -- For instant-acquisition mounts (vendor, done quests), time to walk to the vendor
    -- is essentially 0 from a recommendation standpoint — don't penalize them.
    if isInstantAvailable then
        timeScore = 0
    end

    -- Component 3: Time Gate (0-100)
    -- Captures the frustration of "I can only try once per week/year".
    -- Being locked (attemptsRemaining=0) adds an extra penalty because you're
    -- currently blocked from attempting, not just limited in frequency.
    local immediatelyAvailable = (input.attemptsRemaining or 1) > 0
    local gateScore
    if immediatelyAvailable then
        -- Available: base gate penalty (the recurring wait is still a cost)
        gateScore = math.log(gateMultiplier + 1) * 5
    else
        -- Locked: triple the penalty — you can't even try right now
        gateScore = math.log(gateMultiplier + 1) * 15
    end
    gateScore = math.min(gateScore, 100)

    -- Component 4: Group Requirement (0-100)
    -- Reflect the real social friction of needing other players.
    -- Solo = 0 (no friction), mythic-20 = 100 (maximum friction).
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

    local preBonusScore = score

    -- ===================================================================
    -- BONUSES & PENALTIES (multiplicative to preserve relative ordering)
    -- ===================================================================
    -- All bonuses are multiplicative discounts (0.xx) rather than flat
    -- subtractions. This prevents low-score mounts from clamping to 0
    -- and ensures easy mounts remain differentiable from each other.

    -- ---------------------------------------------------------------
    -- INSTANT ACQUISITION MEGA-BONUS
    -- The most powerful bonus in the system. Mounts you can get RIGHT
    -- NOW with zero RNG get a massive score reduction so they float to
    -- the very top of recommendations. This directly implements the
    -- "user should see instant mounts first" requirement.
    -- ---------------------------------------------------------------
    if isInstantAvailable then
        -- 70% discount for truly instant mounts (can buy/claim right now)
        score = score * 0.30
    end

    -- ---------------------------------------------------------------
    -- AVAILABILITY BONUS — graduated by time gate type
    -- ---------------------------------------------------------------
    if immediatelyAvailable and not isInstantAvailable then
        local isDropMount = (dropChance and dropChance > 0 and dropChance < 1)

        -- Graduated bonus: ungated content gets a bigger reward for being available
        local availabilityDiscounts = {
            none = 0.25,    -- Unlimited farm: full discount
            daily = 0.15,   -- Daily gated: moderate discount
            biweekly = 0.12, -- Biweekly gated: between daily and weekly
            weekly = 0.10,  -- Weekly gated: smaller discount
            monthly = 0.09, -- Monthly rotation: small discount
            yearly = 0.08,  -- Yearly event: minimal discount
        }
        local discount = availabilityDiscounts[input.timeGate or "none"] or 0.15

        if isDropMount or progressRemaining <= 0 then
            score = score * (1 - discount)
        elseif progressRemaining < 0.50 then
            -- Graduated: closer to done = more discount
            local progressFactor = 1 - (progressRemaining / 0.50)
            score = score * (1 - discount * progressFactor)
        end
    end

    -- ---------------------------------------------------------------
    -- NEAR-COMPLETION BONUS
    -- A guaranteed mount that's 90%+ done should float above mounts
    -- at 50% completion. Distinct from the instant bonus (5% threshold)
    -- this covers the 5-30% remaining range.
    -- ---------------------------------------------------------------
    local isDropMount = (dropChance and dropChance > 0 and dropChance < 1)
    if not isDropMount and progressRemaining <= 0.30 and progressRemaining > 0.05
       and immediatelyAvailable then
        -- Scale: 5% remaining = 25% discount, 30% remaining = ~0% discount
        local nearCompleteDiscount = 0.25 * (1 - ((progressRemaining - 0.05) / 0.25))
        nearCompleteDiscount = math.max(0, math.min(0.25, nearCompleteDiscount))
        score = score * (1 - nearCompleteDiscount)
    end

    -- ---------------------------------------------------------------
    -- VENDOR / TRIVIALLY OBTAINABLE BONUS
    -- Vendor mounts, trading post mounts, and similar "just pay for it"
    -- sources deserve a significant bonus because there's no RNG and no
    -- time gate — just visit the vendor. This stacks with the instant
    -- bonus for mounts where progress=0.
    -- ---------------------------------------------------------------
    if isVendorType and not dropChance then
        -- Extra 20% discount on top of any other bonuses for "trivially buyable" mounts
        local vendorDiscount = 0.20
        -- If progress is complete (can buy right now), boost more
        if progressRemaining <= 0.05 then
            vendorDiscount = 0.30
        end
        score = score * (1 - vendorDiscount)
    end

    -- ---------------------------------------------------------------
    -- QUEST CHAIN BONUS
    -- Quest chains are deterministic — you follow the steps and get
    -- the mount at the end. Reward mounts with partial completion
    -- more than equivalently-progressed RNG mounts.
    -- ---------------------------------------------------------------
    if isQuestType and not dropChance then
        local questDiscount = 0.10
        -- Extra bonus for nearly-done quests
        if progressRemaining <= 0.20 and immediatelyAvailable then
            questDiscount = 0.20
        end
        score = score * (1 - questDiscount)
    end

    -- ---------------------------------------------------------------
    -- ACHIEVEMENT PROGRESS BONUS
    -- If the player is already meaningfully into an achievement,
    -- surface it higher. Progress >50% done gets a scaling bonus.
    -- ---------------------------------------------------------------
    if isAchievementType and input.achievementID and not dropChance then
        local achProgress = 1.0 - progressRemaining  -- 0=not started, 1=done
        if achProgress > 0.50 then
            -- Scale: 50% done = 0% bonus, 90% done = 20% bonus, 100% = 30% bonus
            local achDiscount = math.min(0.30, (achProgress - 0.50) / 0.50 * 0.30)
            score = score * (1 - achDiscount)
        end
    end

    -- ---------------------------------------------------------------
    -- WARBAND AVAILABILITY BONUS
    -- If current char is locked but alts are free, partial credit.
    -- 1 alt available = 15% off, 3+ alts = 20% off.
    -- ---------------------------------------------------------------
    if not immediatelyAvailable and warbandAvailable and warbandAvailable > 0 then
        local altDiscount = math.min(0.20, 0.10 + math.log(warbandAvailable + 1) * 0.05)
        score = score * (1 - altDiscount)
    end

    -- ---------------------------------------------------------------
    -- INSTANCE EFFICIENCY BONUS
    -- Multiple uncollected mounts from the same lockout instance = run is more efficient.
    -- ---------------------------------------------------------------
    local instanceGroupCount = input.instanceGroupCount
    if instanceGroupCount and instanceGroupCount > 1 then
        local efficiencyDiscount = math.min(0.25, math.log(instanceGroupCount) * 0.10)
        score = score * (1 - efficiencyDiscount)
    end

    -- ---------------------------------------------------------------
    -- STALENESS NUDGE
    -- Mounts not attempted recently bubble up slightly as a reminder.
    -- ---------------------------------------------------------------
    local staleDays = input.staleDays
    if staleDays and staleDays > 7 then
        local stalenessDiscount = math.min(0.20, math.log(staleDays / 7 + 1) * 0.06)
        score = score * (1 - stalenessDiscount)
    end

    -- ---------------------------------------------------------------
    -- RARITY BONUS (ownership %)
    -- Mounts owned by fewer players are harder to obtain — their rarity
    -- signals difficulty even if the drop rate isn't in our DB.
    -- High rarity (% owned) = common = small discount.
    -- Low rarity (% owned) = rare = larger discount (they should appear
    -- earlier since they're harder to get = more valuable recommendation).
    --
    -- Wait — rarity here means "% of players who OWN it". A low % means
    -- it's rare (hard to get), so it should score HIGHER (harder). But the
    -- user wants to see easy mounts first, not rare mounts first.
    -- So rarity discount should make rare mounts appear EARLIER only when
    -- the difficulty metrics can't distinguish them (e.g. two unknown-drop
    -- mounts — the rarer one is probably harder, score it higher/worse).
    -- For the recommendation use-case, rarity is a TIEBREAKER for desirability:
    -- between two equal-difficulty mounts, recommend the rarer (more impressive) one.
    -- We implement this as a small discount for rare mounts to surface them.
    -- ---------------------------------------------------------------
    local rarity = input.rarity
    if rarity and rarity > 0 then
        -- rarity = % owned. Low % = rare mount.
        -- Discount: 0.15 at 0% owned, 0% at 20%+ owned.
        local rarityDiscount = 0.15 * math.max(0, 1 - rarity / 20)
        if rarityDiscount > 0 then
            score = score * (1 - rarityDiscount)
        end
    end

    -- ---------------------------------------------------------------
    -- GOLD COST PENALTY
    -- Very expensive mounts (TCG, BMAH-priced items) should score worse
    -- than affordable ones even at same progress. Gold cost >500k is a
    -- meaningful barrier for most players.
    -- ---------------------------------------------------------------
    if input.goldCost and input.goldCost > 0 and not isInstantAvailable then
        -- Log scale: 0 gold=0, 100k=0.02, 500k=0.08, 1M=0.10 penalty
        local goldPenalty = math.min(0.10, math.log(input.goldCost / 10000 + 1) * 0.04)
        if goldPenalty > 0.001 then
            score = score * (1 + goldPenalty)  -- Penalty, not discount
        end
    end

    -- Cap total discount to maintain spread among non-instant mounts.
    -- Instant-available mounts intentionally bypass the cap (they should sit at the very top).
    -- For all others, prevent any combination of bonuses from reducing score below 20% of pre-bonus.
    if not isInstantAvailable then
        score = math.max(score, preBonusScore * 0.20)
    end

    -- Guard against NaN in final score, floor at 0 for UI sanity
    if score ~= score then score = 99999 end
    score = math.max(0, score)

    -- Build plain-English score explanation
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
        isInstantAvailable = isInstantAvailable,
        isVendorType = isVendorType,
        isQuestType = isQuestType,
        isAchievementType = isAchievementType,
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

-- Build a plain-English explanation of why a mount scored the way it did.
-- The explanation should clearly tell users WHY a mount is recommended and HOW to get it.
function FB.Scoring:BuildExplanation(input, data)
    local parts = {}

    local sourceType = input.sourceType or "unknown"
    local progressRemaining = input.progressRemaining or 1.0
    local isDropMount = (input.dropChance and input.dropChance > 0 and input.dropChance < 1)

    -- ---------------------------------------------------------------
    -- ACQUISITION METHOD — most important part of the explanation
    -- Tell the user exactly how to get this mount.
    -- ---------------------------------------------------------------
    if data.isInstantAvailable then
        -- The highest-priority label: this mount is obtainable right now with no RNG.
        if sourceType == "vendor" then
            parts[#parts + 1] = "|cFF00FF00BUY NOW|r - visit the vendor"
        elseif sourceType == "trading_post" then
            parts[#parts + 1] = "|cFF00FF00CLAIM NOW|r - Trading Post"
        elseif sourceType == "quest_chain" then
            parts[#parts + 1] = "|cFF00FF00COMPLETE QUEST|r"
        elseif sourceType == "achievement" then
            parts[#parts + 1] = "|cFF00FF00FINISH ACHIEVEMENT|r"
        elseif sourceType == "profession" then
            parts[#parts + 1] = "|cFF00FF00CRAFT NOW|r"
        elseif sourceType == "reputation" then
            parts[#parts + 1] = "|cFF00FF00REP DONE|r - visit vendor"
        elseif sourceType == "currency_grind" or sourceType == "currency" then
            parts[#parts + 1] = "|cFF00FF00CURRENCY READY|r - visit vendor"
        elseif sourceType == "recruit_a_friend" then
            parts[#parts + 1] = "|cFF00FF00CLAIM|r - Recruit-a-Friend"
        else
            parts[#parts + 1] = "|cFF00FF00GET NOW|r"
        end
    elseif sourceType == "vendor" or sourceType == "trading_post" then
        if progressRemaining <= 0.05 then
            parts[#parts + 1] = "|cFF00FF00BUY NOW|r"
        elseif progressRemaining <= 0.50 then
            parts[#parts + 1] = "almost ready to buy"
        else
            parts[#parts + 1] = "vendor purchase"
        end
    elseif sourceType == "reputation" then
        if progressRemaining <= 0.05 then
            parts[#parts + 1] = "rep done - visit vendor"
        elseif progressRemaining <= 0.30 then
            parts[#parts + 1] = "nearly exalted"
        else
            parts[#parts + 1] = "rep grind"
        end
    elseif sourceType == "quest_chain" then
        if progressRemaining <= 0.05 then
            parts[#parts + 1] = "last quest remaining"
        elseif progressRemaining <= 0.50 then
            parts[#parts + 1] = "halfway done"
        else
            parts[#parts + 1] = "quest chain"
        end
    elseif sourceType == "achievement" then
        if progressRemaining <= 0.05 then
            parts[#parts + 1] = "almost done"
        elseif progressRemaining < 0.50 then
            local pct = math.floor((1.0 - progressRemaining) * 100)
            parts[#parts + 1] = pct .. "% complete"
        else
            parts[#parts + 1] = "achievement"
        end
    elseif sourceType == "currency_grind" or sourceType == "currency" then
        if progressRemaining <= 0.05 then
            parts[#parts + 1] = "currency ready"
        else
            parts[#parts + 1] = "currency grind"
        end
    elseif sourceType == "profession" then
        parts[#parts + 1] = "crafted"
    elseif sourceType == "pvp" then
        parts[#parts + 1] = "PvP"
    elseif sourceType == "tcg" then
        parts[#parts + 1] = "TCG - buy on AH"
    elseif sourceType == "recruit_a_friend" then
        parts[#parts + 1] = "Recruit-a-Friend"
    end

    -- ---------------------------------------------------------------
    -- FIX-4: MULTI-REQUIREMENT BREAKDOWN
    -- When a mount has 2+ incomplete requirements, show each one individually
    -- so the user can see "Rep: Done | Currency: 10%" instead of just "90% complete"
    -- ---------------------------------------------------------------
    if input.requirementProgress and not data.isInstantAvailable then
        local REQ_LABELS = {
            rep      = "Rep",
            currency = "Currency",
            gold     = "Gold",
            achievement = "Ach",
            quest    = "Quest",
        }
        local reqParts = {}
        for reqType, prog in pairs(input.requirementProgress) do
            if prog ~= nil then
                local label = REQ_LABELS[reqType] or reqType
                if prog <= 0.01 then
                    reqParts[#reqParts + 1] = label .. ": |cFF00FF00Done|r"
                else
                    local pct = math.floor((1.0 - prog) * 100)
                    reqParts[#reqParts + 1] = string.format("%s: %d%%", label, pct)
                end
            end
        end
        if #reqParts >= 2 then
            table.sort(reqParts)  -- Deterministic order
            parts[#parts + 1] = table.concat(reqParts, " / ")
        end
    end

    -- ---------------------------------------------------------------
    -- SOLO / GROUP label
    -- ---------------------------------------------------------------
    local groupReq = input.groupRequirement or "solo"
    if groupReq == "solo" then
        parts[#parts + 1] = "solo"
    elseif groupReq == "duo" then
        parts[#parts + 1] = "2-player"
    elseif groupReq == "small" then
        parts[#parts + 1] = "small group"
    elseif groupReq == "full" or groupReq == "raid" then
        parts[#parts + 1] = "raid group"
    elseif groupReq == "mythic" then
        parts[#parts + 1] = "Mythic raid"
    end

    -- ---------------------------------------------------------------
    -- TIME GATE
    -- ---------------------------------------------------------------
    if input.timeGate == "none" or input.timeGate == nil then
        if not data.isInstantAvailable and not isDropMount then
            parts[#parts + 1] = "no lockout"
        end
    elseif input.timeGate == "weekly" then
        -- FIX-8: Show weekly reset countdown using WoW API
        local resetStr = nil
        if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
            local ok, secs = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
            if ok and secs and secs > 0 then
                local days = math.floor(secs / 86400)
                local hours = math.floor((secs % 86400) / 3600)
                if days > 0 then
                    resetStr = string.format("resets in %dd %dh", days, hours)
                else
                    resetStr = string.format("resets in %dh", hours)
                end
            end
        end
        if data.immediatelyAvailable then
            parts[#parts + 1] = "weekly (available)"
        else
            if resetStr then
                parts[#parts + 1] = "weekly (locked, " .. resetStr .. ")"
            else
                parts[#parts + 1] = "weekly (locked)"
            end
        end
    elseif input.timeGate == "daily" then
        if data.immediatelyAvailable then
            parts[#parts + 1] = "daily (available)"
        else
            -- Show time until daily reset (midnight server time is ~03:00-08:00 UTC depending on realm)
            -- C_DateAndTime.GetSecondsUntilDailyReset is not a standard API;
            -- we fall back to a simple "locked" label for daily resets.
            parts[#parts + 1] = "daily (locked)"
        end
    elseif input.timeGate == "yearly" then
        parts[#parts + 1] = "yearly event only"
    elseif input.timeGate == "monthly" then
        parts[#parts + 1] = "monthly rotation"
    elseif input.timeGate == "biweekly" then
        parts[#parts + 1] = "biweekly"
    end

    -- ---------------------------------------------------------------
    -- DROP CHANCE — with verified source tag
    -- ---------------------------------------------------------------
    if input.dropChance then
        local pct = input.dropChance * 100
        local sourceTag = ""
        if input.dropChanceSource == "curated" then
            sourceTag = " (verified)"
        elseif input.dropChanceSource == "rarity_db" then
            sourceTag = " (community)"
        end
        if pct >= 100 then
            parts[#parts + 1] = "guaranteed"
        elseif pct >= 5 then
            parts[#parts + 1] = string.format("%.0f%% drop%s", pct, sourceTag)
        elseif pct >= 1 then
            parts[#parts + 1] = string.format("%.1f%% drop%s", pct, sourceTag)
        else
            parts[#parts + 1] = string.format("%.2f%% drop%s", pct, sourceTag)
        end
    elseif data.isUnknownDrop then
        parts[#parts + 1] = "drop rate unknown"
    end

    -- ---------------------------------------------------------------
    -- LOCK STATUS (for drop mounts or currently-locked mounts)
    -- ---------------------------------------------------------------
    if not data.isInstantAvailable then
        if data.immediatelyAvailable then
            -- Only show "available now" for drop mounts — guaranteed mounts
            -- get the acquisition method label above instead
            if isDropMount then
                parts[#parts + 1] = "available now"
            end
        else
            if data.warbandAvailable and data.warbandAvailable > 0 then
                parts[#parts + 1] = "locked (alt available)"
            elseif isDropMount or (input.timeGate ~= "none" and input.timeGate) then
                -- Only show "locked" for gated content
                parts[#parts + 1] = "locked this reset"
            end
        end
    end

    -- ---------------------------------------------------------------
    -- INSTANCE EFFICIENCY
    -- ---------------------------------------------------------------
    if data.instanceGroupCount and data.instanceGroupCount > 1 then
        parts[#parts + 1] = data.instanceGroupCount .. " mounts this run"
    end

    -- ---------------------------------------------------------------
    -- RARITY (noteworthy when below 5% ownership)
    -- ---------------------------------------------------------------
    if input.rarity and input.rarity > 0 and input.rarity < 5 then
        parts[#parts + 1] = string.format("%.1f%% own this", input.rarity)
    end

    -- ---------------------------------------------------------------
    -- ESTIMATED TIME TO OBTAIN
    -- FIX-2: Rep mounts show calendar-aware estimates ("~3 weeks of dailies")
    --        Gold mounts show tier-aware label (trivial / moderate / significant / major)
    -- ---------------------------------------------------------------
    if data.effectiveDays and data.effectiveDays < 99999 then
        local hoursPerDay = data.hoursPerDay or 2
        if data.isInstantAvailable then
            -- No time estimate needed — it's instant
        elseif input.dropChance and input.dropChance > 0 and input.dropChance < 1 then
            -- RNG mount: show range (median to 95th percentile)
            local gateDays = FB.TIME_GATE_FACTORS[input.timeGate or "none"] or 0
            local attemptsPerDay = gateDays > 0 and (1 / gateDays) or
                math.max(1, math.floor(hoursPerDay * 60 / math.max(1, input.timePerAttempt or 10)))
            local rangeStr = FB.Utils:FormatDaysRange(input.dropChance, attemptsPerDay, hoursPerDay)
            if rangeStr then
                parts[#parts + 1] = rangeStr
            else
                parts[#parts + 1] = "~" .. FB.Utils:FormatDays(data.effectiveDays) .. " avg"
            end
        elseif input.repEstimatedDays and input.repEstimatedDays > 0 and not data.isInstantAvailable then
            -- FIX-2: Rep/renown: use calendar-day estimate, not farming hours
            local repDays = input.repEstimatedDays
            local repMethod = input.repMethod or "daily"
            local timeStr
            if repMethod == "renown" then
                -- Renown is weekly-capped
                local weeks = math.ceil(repDays / 7)
                if weeks <= 1 then
                    timeStr = "~" .. repDays .. " days (renown)"
                else
                    timeStr = string.format("~%d wks of renown (%d days)", weeks, repDays)
                end
            elseif repMethod == "tabard" then
                -- Tabard: can farm continuously, but estimate is still in calendar days
                timeStr = "~" .. FB.Utils:FormatDays(repDays) .. " (tabard)"
            else
                -- Mixed daily/weekly: show in calendar days and number of dailies
                if repDays <= 7 then
                    timeStr = "~" .. repDays .. " daily quests"
                elseif repDays <= 30 then
                    local weeks = math.ceil(repDays / 7)
                    timeStr = string.format("~%d daily quests (%d wks)", repDays, weeks)
                else
                    local months = math.ceil(repDays / 30)
                    timeStr = string.format("~%d days (%d mo) of dailies", repDays, months)
                end
                -- If this is the fallback (no curated data), say so
                if not input.repDataCurated then
                    timeStr = timeStr .. " (est.)"
                end
            end
            parts[#parts + 1] = timeStr
        elseif input.goldCost and input.goldCost > 0 and input.goldTier and not data.isInstantAvailable then
            -- FIX-1: Gold tier label for expensive mounts
            local tierLabels = {
                trivial    = "gold: trivial (<10k)",
                moderate   = "gold: moderate (10k-100k)",
                significant= string.format("gold: %.0fk (significant)", input.goldCost / 1000),
                major      = string.format("gold: %.0fk (major barrier)", input.goldCost / 1000),
            }
            local tierLabel = tierLabels[input.goldTier]
                or string.format("gold: %.0fk", input.goldCost / 1000)
            parts[#parts + 1] = tierLabel
        elseif data.effectiveDays >= 1 then
            -- Guaranteed: show single estimate
            parts[#parts + 1] = "~" .. FB.Utils:FormatDays(data.effectiveDays)
        end
    end

    -- ---------------------------------------------------------------
    -- FIX-3: FIRST ACTION STEP — pull from steps[1] if available
    -- Only shown for instant-available mounts (most actionable case)
    -- and for non-instant mounts when they have vendor/quest context.
    -- ---------------------------------------------------------------
    if input.steps and #input.steps > 0 then
        local firstStep = input.steps[1]
        if firstStep and firstStep ~= "" then
            -- Truncate to avoid tooltip overflow
            if #firstStep > 60 then
                firstStep = firstStep:sub(1, 57) .. "..."
            end
            if data.isInstantAvailable then
                parts[#parts + 1] = "|cFFFFD700Next:|r " .. firstStep
            elseif sourceType == "reputation" or sourceType == "quest_chain"
                   or sourceType == "currency_grind" or sourceType == "currency" then
                parts[#parts + 1] = firstStep
            end
        end
    end

    -- ---------------------------------------------------------------
    -- DOMINANT BOTTLENECK — shown when score is high and cause is clear
    -- ---------------------------------------------------------------
    local maxComp = 0
    local maxCompName = ""
    local compMap = {
        { name = "progress", val = data.progressScore or 0, label = "incomplete prerequisites" },
        { name = "gate", val = data.gateScore or 0, label = "time-gating" },
        { name = "group", val = data.groupScore or 0, label = "group requirement" },
        { name = "effort", val = data.effortScore or 0, label = "total expected effort" },
    }
    for _, comp in ipairs(compMap) do
        if comp.val > maxComp then
            maxComp = comp.val
            maxCompName = comp.label
        end
    end
    -- Only show bottleneck when it's clearly dominant (>35 pts) and
    -- the explanation doesn't already capture it implicitly
    if maxComp > 35 and not data.isInstantAvailable then
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
