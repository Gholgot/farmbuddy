local addonName, FB = ...

FB.Achievements = FB.Achievements or {}
FB.Achievements.Resolver = {}

local GetAchievementInfo = GetAchievementInfo
local GetAchievementNumCriteria = GetAchievementNumCriteria
local GetAchievementCriteriaInfo = GetAchievementCriteriaInfo

-- Walk up the category tree to check if any ancestor matches a name
function FB.Achievements.Resolver:IsCategoryOrAncestor(categoryID, targetName)
    if not categoryID or not GetCategoryInfo then return false end
    local visited = {}
    local currentID = categoryID
    while currentID and currentID ~= -1 and not visited[currentID] do
        visited[currentID] = true
        local catOk, catName, parentID = pcall(GetCategoryInfo, currentID)
        if catOk and catName and catName:find(targetName) then
            return true
        end
        currentID = catOk and parentID or nil
    end
    return false
end

--[[
    Detect if an achievement is unobtainable.
    Checks multiple signals:
      - Feats of Strength (entire category tree)
      - Legacy category (entire category tree)
      - Known removed/legacy achievement patterns
      - Past PvP season achievements
--]]
function FB.Achievements.Resolver:IsUnobtainable(achievementID, name, description, flags, categoryID, categoryName)
    local lowerName = name and name:lower() or ""
    local lowerDesc = description and description:lower() or ""

    -- Check direct name and ancestor tree for Feats of Strength
    local isFeatsOfStrength = (categoryName and categoryName:find("Feats of Strength"))
        or self:IsCategoryOrAncestor(categoryID, "Feats of Strength")

    -- Feats of Strength are almost always unobtainable (past content, removed, etc.)
    -- Exception: some FoS are still earnable (e.g., current Ahead of the Curve)
    if isFeatsOfStrength then
        -- Allow current-tier FoS: Ahead of the Curve, Cutting Edge, Keystone Hero
        local currentFoS = {
            "ahead of the curve",
            "cutting edge",
            "keystone hero",
            "keystone master",
            "keystone conqueror",
            "keystone explorer",
        }
        for _, pattern in ipairs(currentFoS) do
            if lowerName:find(pattern) then
                -- Still might be from a past tier — check for current expansion keywords
                if lowerDesc:find("war within") or lowerDesc:find("khaz algar")
                   or lowerDesc:find("nerub%-ar") or lowerDesc:find("liberation of undermine") then
                    return false  -- Current tier FoS, keep
                end
            end
        end
        return true  -- All other Feats of Strength are unobtainable
    end

    -- Legacy category achievements (check direct and ancestor tree)
    local isLegacy = (categoryName and categoryName:find("Legacy"))
        or self:IsCategoryOrAncestor(categoryID, "Legacy")
    if isLegacy then
        return true
    end

    -- Specific unobtainable keywords in description
    if lowerDesc:find("no longer") or lowerDesc:find("removed")
       or lowerDesc:find("unavailable") or lowerDesc:find("unobtainable")
       or lowerDesc:find("feat of strength") then
        return true
    end

    -- Past PvP season achievements (Arena Master, Gladiator titles from old seasons)
    if lowerName:find("gladiator:") or lowerName:find("gladiator's") then
        -- Only current season gladiator is obtainable
        if not (lowerDesc:find("war within") or (lowerDesc:find("season") and lowerDesc:find("current"))) then
            -- Check for expansion-specific keywords indicating past content
            local pastKeywords = {
                "shadowlands", "battle for azeroth", "legion", "draenor",
                "pandaria", "cataclysm", "northrend", "outland",
                "sinful", "unchained", "cosmic", "corrupted", "notorious",
                "demonic", "fearless", "fierce", "dominant", "cruel",
            }
            for _, keyword in ipairs(pastKeywords) do
                if lowerName:find(keyword) or lowerDesc:find(keyword) then
                    return true
                end
            end
        end
    end

    return false
end

--[[
    Resolve an achievement into a ScoringInput table.
    Uses the criteria API heavily since achievement progress is well-exposed.

    @param achievementID  number
    @return ScoringInput table or nil if should be skipped
--]]
function FB.Achievements.Resolver:Resolve(achievementID)
    local ok, id, name, points, completed, month, day, year, description,
          flags, icon, rewardText, isGuild, wasEarnedByMe, earnedBy,
          isStatistic = pcall(GetAchievementInfo, achievementID)

    if not ok or not id then return nil end
    if completed then return nil end  -- Skip completed
    if isGuild then return nil end    -- Skip guild achievements
    if isStatistic then return nil end -- Skip statistics

    -- Get criteria progress (with safety)
    local numOk, numCriteria = pcall(GetAchievementNumCriteria, achievementID)
    if not numOk then numCriteria = 0 end
    numCriteria = numCriteria or 0

    local completedCriteria = 0
    local totalCriteria = numCriteria
    local criteriaDetails = {}

    for i = 1, totalCriteria do
        local cOk, cName, cType, cCompleted, cQuantity, cReqQuantity,
              cCharName, cFlags, cAssetID = pcall(GetAchievementCriteriaInfo, achievementID, i)
        if cOk then
            if cCompleted then
                completedCriteria = completedCriteria + 1
            end
            criteriaDetails[#criteriaDetails + 1] = {
                name = cName or "",
                completed = cCompleted or false,
                quantity = cQuantity or 0,
                reqQuantity = cReqQuantity or 0,
            }
        end
    end

    -- Calculate progress using quantity-weighted approach for accuracy
    -- This ensures "Kill 500 enemies (450/500)" counts as nearly done,
    -- not 100% remaining just because the criterion isn't flagged complete
    local progressRemaining
    if totalCriteria > 0 then
        local weightedTotal = 0
        local weightedDone = 0
        for _, crit in ipairs(criteriaDetails) do
            if crit.reqQuantity and crit.reqQuantity > 1 then
                weightedTotal = weightedTotal + crit.reqQuantity
                weightedDone = weightedDone + math.min(crit.quantity, crit.reqQuantity)
            else
                weightedTotal = weightedTotal + 1
                weightedDone = weightedDone + (crit.completed and 1 or 0)
            end
        end
        if weightedTotal > 0 then
            progressRemaining = math.max(0, (weightedTotal - weightedDone) / weightedTotal)
        else
            progressRemaining = (totalCriteria - completedCriteria) / totalCriteria
        end
    else
        -- 0-criteria achievements: progress is unmeasurable
        -- Use conservative estimate to avoid ranking them too highly
        progressRemaining = 0.75
    end

    -- Get category-based defaults (with safety for GetAchievementCategory)
    local categoryID = nil
    if GetAchievementCategory then
        local catOk, catID = pcall(GetAchievementCategory, achievementID)
        if catOk then categoryID = catID end
    end

    local categoryName = ""
    if categoryID and GetCategoryInfo then
        local catNameOk, catName = pcall(GetCategoryInfo, categoryID)
        if catNameOk and catName then categoryName = catName end
    end

    -- Check if achievement is unobtainable before continuing
    if self:IsUnobtainable(achievementID, name, description, flags, categoryID, categoryName) then
        return nil
    end

    local categoryDefaults = FB.AchievementDB:GetCategoryDefaults(categoryName)

    -- Check for per-achievement override
    local override = FB.AchievementDB:Get(achievementID)
    local meta = override or categoryDefaults

    -- Skip 0-criteria achievements without overrides (progress unmeasurable)
    if totalCriteria == 0 and not override then
        return nil
    end

    -- Determine reward type
    local rewardType = FB.AchievementDB:GetRewardType(achievementID)
    if not rewardType and rewardText then
        rewardType = FB.AchievementDB:ParseRewardType(rewardText)
    end
    rewardType = rewardType or "none"

    -- Build scoring input
    local remainingCriteria = totalCriteria - completedCriteria
    local timePerCriterion = meta.timePerCriterion or 10

    -- Calculate quantity-weighted expected attempts for more accurate effort
    -- Boolean criteria count as 1 attempt each
    -- Quantity criteria (e.g. "Kill 500 enemies") scale by remaining work
    local weightedAttempts = 0
    for _, crit in ipairs(criteriaDetails) do
        if not crit.completed then
            if crit.reqQuantity and crit.reqQuantity > 1 then
                local remaining = math.max(0, crit.reqQuantity - crit.quantity)
                local fraction = remaining / crit.reqQuantity
                -- Scale: full remaining = 5 attempts worth, cap at 10
                weightedAttempts = weightedAttempts + math.min(10, math.max(1, math.ceil(fraction * 5)))
            else
                weightedAttempts = weightedAttempts + 1
            end
        end
    end
    if weightedAttempts == 0 then
        weightedAttempts = math.max(1, remainingCriteria)
    end

    local input = {
        id = achievementID,
        name = name or "Unknown",
        icon = icon,
        description = description or "",
        points = points or 0,
        rewardText = rewardText or "",
        rewardType = rewardType,
        categoryID = categoryID,
        categoryName = categoryName,

        -- Scoring inputs
        sourceType = "achievement",
        progressRemaining = progressRemaining,
        timePerAttempt = timePerCriterion,
        timeGate = meta.timeGate or "none",
        groupRequirement = meta.groupRequirement or "solo",
        dropChance = nil,  -- Achievements are not RNG-based
        attemptsRemaining = 1,
        expectedAttempts = weightedAttempts,

        -- Achievement-specific
        totalCriteria = totalCriteria,
        completedCriteria = completedCriteria,
        remainingCriteria = remainingCriteria,
        criteriaDetails = criteriaDetails,
    }

    return input
end
