local addonName, FB = ...

FB.ProgressResolver = {}

local C_MountJournal = C_MountJournal
local C_CurrencyInfo = C_CurrencyInfo
local C_QuestLog = C_QuestLog
local GetAchievementCriteriaInfo = GetAchievementCriteriaInfo
local GetAchievementNumCriteria = GetAchievementNumCriteria

-- Resolve reputation progress toward a target standing
-- Returns 0.0 (done) to 1.0 (not started)
-- @param targetStanding  number - Traditional standing ID (8=Exalted) or renown level for renown factions
function FB.ProgressResolver:GetRepProgress(factionID, targetStanding, targetRenown)
    targetStanding = targetStanding or 8  -- 8 = Exalted
    if not factionID then return 1.0 end

    -- Try C_Reputation (modern WoW 10.1+)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, data = pcall(C_Reputation.GetFactionDataByID, factionID)
        if ok and data then
            -- Check for Renown system (TWW, DF, SL factions)
            if data.isRenownReputation or data.renownLevel then
                return self:GetRenownProgress(data, factionID, targetRenown)
            end

            -- Check for Paragon reputation
            if C_Reputation.IsFactionParagon then
                local parOk, isParagoned = pcall(C_Reputation.IsFactionParagon, factionID)
                if parOk and isParagoned then
                    return 0.0  -- Already at Paragon, consider "done"
                end
            end

            local currentReaction = data.reaction or 4  -- default Neutral
            if currentReaction >= targetStanding then
                return 0.0
            end

            -- Calculate progress using the faction's actual minimum standing as base
            -- Most factions start at Neutral (4), but some start at Hated (1)
            -- e.g., Netherwing starts at Hated, Bloodsail Buccaneers start at Hated
            -- Use min(currentReaction, 4) as the floor: if player is below Neutral,
            -- we know the faction started below Neutral; otherwise assume Neutral start
            local baseStanding = math.min(currentReaction, 4)
            local standingsToGo = targetStanding - baseStanding
            if standingsToGo <= 0 then return 0.0 end

            local completedStandings = math.max(0, currentReaction - baseStanding)
            local barProgress = 0
            if data.nextReactionThreshold and data.currentReactionThreshold
               and data.nextReactionThreshold > data.currentReactionThreshold then
                local maxInStanding = data.nextReactionThreshold - data.currentReactionThreshold
                local currentInStanding = (data.currentStanding or 0) - data.currentReactionThreshold
                if maxInStanding > 0 then
                    barProgress = math.max(0, math.min(1, currentInStanding / maxInStanding))
                end
            end

            local totalProgress = (completedStandings + barProgress) / standingsToGo
            return math.max(0, math.min(1.0, 1.0 - totalProgress))
        end
    end

    -- Fallback: try old GetFactionInfoByID
    if GetFactionInfoByID then
        local ok, name, _, standingID, barMin, barMax, barValue = pcall(GetFactionInfoByID, factionID)
        if ok and standingID then
            if standingID >= targetStanding then return 0.0 end

            local baseStanding = math.min(standingID, 4)
            local standingsToGo = targetStanding - baseStanding
            if standingsToGo <= 0 then return 0.0 end

            local completedStandings = math.max(0, standingID - baseStanding)
            local barProgress = 0
            if barMax and barMin and barMax > barMin then
                barProgress = ((barValue or 0) - barMin) / (barMax - barMin)
            end

            local totalProgress = (completedStandings + barProgress) / standingsToGo
            return math.max(0, math.min(1.0, 1.0 - totalProgress))
        end
    end

    return 1.0
end

-- Handle Renown-based reputation progress
-- @param data         table   - Faction data from C_Reputation
-- @param factionID    number  - Faction ID
-- @param targetRenown number  - (optional) Required renown level for the mount; nil = use max
function FB.ProgressResolver:GetRenownProgress(data, factionID, targetRenown)
    if not C_MajorFactions or not C_MajorFactions.GetMajorFactionData then
        -- No Renown API, treat as partially done
        return 0.5
    end

    local ok, majorData = pcall(C_MajorFactions.GetMajorFactionData, factionID)
    if ok and majorData then
        local currentRenown = majorData.renownLevel or 0
        -- Use targetRenown if provided, otherwise fall back to maxRenownLevel
        local goalRenown = targetRenown or majorData.maxRenownLevel or 40
        -- Sanity check: renown levels are small integers (typically 1-80)
        -- If value > 200, it's likely a rep amount, not a level
        if goalRenown > 200 then goalRenown = 40 end
        if currentRenown > 200 then currentRenown = 0 end

        if goalRenown <= 0 then return 0.0 end
        if currentRenown >= goalRenown then return 0.0 end

        -- Sub-level progress: how far through the current renown level
        local subLevelProgress = 0
        if majorData.renownReputationEarned and majorData.renownLevelThreshold
           and majorData.renownLevelThreshold > 0 then
            subLevelProgress = math.max(0, math.min(1,
                majorData.renownReputationEarned / majorData.renownLevelThreshold
            ))
        end

        -- Total fractional progress: (completedLevels + partial) / goalLevels
        local fractionalLevel = currentRenown + subLevelProgress
        return math.max(0, math.min(1.0, (goalRenown - fractionalLevel) / goalRenown))
    end

    -- Fallback: use basic reaction data
    if data.reaction and data.reaction >= 8 then return 0.0 end
    return 0.5
end

-- Resolve currency progress
-- Returns 0.0 (have enough) to 1.0 (none)
function FB.ProgressResolver:GetCurrencyProgress(currencyID, requiredAmount)
    if not currencyID then return 0.0 end
    -- If we know the currency but couldn't parse the required amount,
    -- assume "not started" rather than "complete" to avoid false positives
    if not requiredAmount or requiredAmount <= 0 then return 1.0 end

    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    if not ok or not info then return 1.0 end

    local current = info.quantity or 0
    if current >= requiredAmount then return 0.0 end

    return (requiredAmount - current) / requiredAmount
end

-- Resolve quest chain progress
-- Returns 0.0 (all done) to 1.0 (none done)
function FB.ProgressResolver:GetQuestChainProgress(questIDs)
    if not questIDs or #questIDs == 0 then return 1.0 end  -- No data = assume not started

    local total = #questIDs
    local completed = 0
    for _, qid in ipairs(questIDs) do
        local ok, isDone = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
        if ok and isDone then
            completed = completed + 1
        end
    end

    if completed >= total then return 0.0 end
    return (total - completed) / total
end

-- Resolve achievement criteria progress
-- Returns 0.0 (completed) to 1.0 (not started)
function FB.ProgressResolver:GetAchievementProgress(achievementID)
    if not achievementID then return 1.0 end

    local numOk, numCriteria = pcall(GetAchievementNumCriteria, achievementID)
    if not numOk then numCriteria = 0 end
    numCriteria = numCriteria or 0

    if numCriteria == 0 then
        -- Check if the achievement itself is complete
        local ok, _, _, _, completed = pcall(GetAchievementInfo, achievementID)
        if ok then
            return completed and 0.0 or 1.0
        end
        return 1.0
    end

    -- Weight each criterion equally (1 point each) with fractional progress
    -- for quantity-based criteria. This prevents a "kill 200 enemies" criterion
    -- from dominating 9 binary yes/no criteria in the same achievement.
    local totalWeight = 0
    local completedWeight = 0

    for i = 1, numCriteria do
        local ok, _, _, completed, quantity, reqQuantity = pcall(GetAchievementCriteriaInfo, achievementID, i)
        if ok then
            totalWeight = totalWeight + 1
            if completed then
                completedWeight = completedWeight + 1
            elseif reqQuantity and reqQuantity > 0 then
                completedWeight = completedWeight + math.min(1, (quantity or 0) / reqQuantity)
            end
        end
    end

    if totalWeight == 0 then return 1.0 end
    if completedWeight >= totalWeight then return 0.0 end

    return (totalWeight - completedWeight) / totalWeight
end

-- Resolve gold cost progress
-- Returns 0.0 (can afford) to 1.0 (have none)
function FB.ProgressResolver:GetGoldProgress(goldCost)
    if not goldCost or goldCost <= 0 then return 0.0 end

    local ok, currentGold = pcall(GetMoney)
    if not ok or not currentGold then return 1.0 end

    -- GetMoney returns copper; goldCost is in gold
    local currentGoldAmount = math.floor(currentGold / 10000)
    if currentGoldAmount >= goldCost then return 0.0 end

    return (goldCost - currentGoldAmount) / goldCost
end

--[[
    Parse gold cost from sourceText.

    In-game sourceText uses WoW UI icon markup for gold:
      "200|TInterface\MoneyFrame\UI-GoldIcon:0|t"
      "5,000|TINTERFACE\MONEYFRAME\UI-GOLDICON.BLP:0|t"
    The gold icon texture path varies in case and may/may not have .BLP extension.

    Silver/copper use similar patterns:
      "50|TInterface\MoneyFrame\UI-SilverIcon:0|t"
      "99|TInterface\MoneyFrame\UI-CopperIcon:0|t"

    Also handles clean text:
      "for 5,000 gold", "costs 20,000 gold", "500000 gold"

    @return gold amount (number) or nil
--]]
function FB.ProgressResolver:ParseGoldCost(sourceText)
    if not sourceText then return nil end

    -- =========================================================================
    -- Format 1: WoW UI gold icon markup
    -- "<amount>|TInterface\MoneyFrame\UI-GoldIcon...|t"
    -- Case-insensitive match on the texture path
    -- =========================================================================
    local goldAmount = sourceText:match("([%d,]+)%s*|T[^|]*[Gg]old[Ii]con[^|]*|t")
    if goldAmount then
        local amount = tonumber(goldAmount:gsub(",", ""))
        if amount and amount > 0 then
            -- Check for silver/copper components to add fractional gold
            -- (rarely matters for mount costs, but be precise)
            local silverAmount = sourceText:match("([%d,]+)%s*|T[^|]*[Ss]ilver[Ii]con[^|]*|t")
            local copperAmount = sourceText:match("([%d,]+)%s*|T[^|]*[Cc]opper[Ii]con[^|]*|t")
            local silver = silverAmount and tonumber(silverAmount:gsub(",", "")) or 0
            local copper = copperAmount and tonumber(copperAmount:gsub(",", "")) or 0
            -- Convert to gold (silver and copper are fractional, but we store as whole gold)
            -- 1 gold = 100 silver = 10000 copper
            -- For mount costs, round up to the nearest gold
            if silver > 0 or copper > 0 then
                amount = amount + math.ceil((silver * 100 + copper) / 10000)
            end
            return amount
        end
    end

    -- =========================================================================
    -- Format 2: Clean text — "X gold", "Xg"
    -- =========================================================================
    local lower = sourceText:lower()
    local patterns = {
        "([%d,]+)%s*gold",
        "([%d,]+)%s*g[^a-z]",
    }

    for _, pattern in ipairs(patterns) do
        local amountStr = lower:match(pattern)
        if amountStr then
            local amount = tonumber(amountStr:gsub(",", ""))
            if amount and amount > 0 then
                return amount
            end
        end
    end

    return nil
end

-- Get remaining criteria count for an achievement
function FB.ProgressResolver:GetRemainingCriteria(achievementID)
    if not achievementID then return 0, 0 end

    local numOk, numCriteria = pcall(GetAchievementNumCriteria, achievementID)
    if not numOk or not numCriteria or numCriteria == 0 then return 0, 0 end

    local remaining = 0
    for i = 1, numCriteria do
        local ok, _, _, completed = pcall(GetAchievementCriteriaInfo, achievementID, i)
        if ok and not completed then
            remaining = remaining + 1
        end
    end

    return remaining, numCriteria
end
