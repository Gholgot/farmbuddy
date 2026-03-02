local addonName, FB = ...

FB.Achievements = FB.Achievements or {}
FB.Achievements.Scanner = {}

local GetCategoryList = GetCategoryList
local GetCategoryInfo = GetCategoryInfo
local GetCategoryNumAchievements = GetCategoryNumAchievements
local GetAchievementInfo = GetAchievementInfo

-- Scan achievements for a specific category (zone)
-- @param categoryID  number - Category to scan
-- @param onProgress  function(current, total)
-- @param onComplete  function(results)
function FB.Achievements.Scanner:ScanCategory(categoryID, onProgress, onComplete)
    if not categoryID then
        if onComplete then onComplete({}) end
        return nil
    end

    -- Collect all achievement IDs in this category (and subcategories)
    local achievementIDs = self:CollectAchievementIDs(categoryID)

    if #achievementIDs == 0 then
        FB:Debug("No achievements found in category " .. tostring(categoryID))
        if onComplete then onComplete({}) end
        return nil
    end

    local batchSize = (FB.db and FB.db.settings and FB.db.settings.scan and FB.db.settings.scan.batchSize) or 5
    local weights = FB.Scoring:GetWeights()

    FB:Debug("Scanning " .. #achievementIDs .. " achievements in category " .. tostring(categoryID))

    local handle = FB.Async:RunBatched(
        achievementIDs,
        function(achID)
            local input = FB.Achievements.Resolver:Resolve(achID)
            if not input then return nil end

            -- Score it
            local result = FB.Scoring:Score(input, weights)

            return {
                id = input.id,
                name = input.name,
                icon = input.icon,
                description = input.description,
                points = input.points,
                rewardText = input.rewardText,
                rewardType = input.rewardType,
                categoryID = input.categoryID,
                categoryName = input.categoryName,
                progressRemaining = input.progressRemaining,
                totalCriteria = input.totalCriteria,
                completedCriteria = input.completedCriteria,
                remainingCriteria = input.remainingCriteria,
                criteriaDetails = input.criteriaDetails,
                groupRequirement = input.groupRequirement,
                timeGate = input.timeGate,

                -- Score
                score = result.score,
                components = result.components,
                effectiveDays = result.effectiveDays,
                immediatelyAvailable = result.immediatelyAvailable,
                scoreExplanation = result.scoreExplanation,
            }
        end,
        batchSize,
        onProgress,
        function(results)
            -- Sort by score ascending (easiest first), name as tiebreaker
            table.sort(results, function(a, b)
                if a.score ~= b.score then
                    return a.score < b.score
                end
                return (a.name or "") < (b.name or "")
            end)

            FB:Debug("Achievement scan complete: " .. #results .. " scored achievements")

            if onComplete then
                onComplete(results)
            end
        end
    )

    return handle
end

-- Build a parent→children map from GetCategoryList (called once, not per recursion)
function FB.Achievements.Scanner:BuildCategoryChildMap()
    local ok, allCategories = pcall(GetCategoryList)
    if not ok or not allCategories then return {} end

    local childMap = {}  -- parentID → { childID, childID, ... }
    for _, catID in ipairs(allCategories) do
        local catOk, _, parentID = pcall(GetCategoryInfo, catID)
        if catOk and parentID then
            if not childMap[parentID] then
                childMap[parentID] = {}
            end
            childMap[parentID][#childMap[parentID] + 1] = catID
        end
    end
    return childMap
end

-- Collect all achievement IDs from a category and its subcategories
function FB.Achievements.Scanner:CollectAchievementIDs(categoryID)
    local ids = {}
    local seen = {}

    -- Build the child map once at the top level
    local childMap = self:BuildCategoryChildMap()

    -- Try modern API first: get ALL achievement IDs and filter by category
    local useModernAPI = false
    local categoryToAchievements = {}  -- catID -> { achID, ... }

    if C_AchievementInfo and C_AchievementInfo.GetAchievementIDs then
        local allOk, allIDs = pcall(C_AchievementInfo.GetAchievementIDs)
        if allOk and allIDs and #allIDs > 0 then
            useModernAPI = true
            -- Build category lookup table once
            for _, achID in ipairs(allIDs) do
                local catOk, catIDForAch = pcall(GetAchievementCategory, achID)
                if catOk and catIDForAch then
                    if not categoryToAchievements[catIDForAch] then
                        categoryToAchievements[catIDForAch] = {}
                    end
                    local t = categoryToAchievements[catIDForAch]
                    t[#t + 1] = achID
                end
            end
        end
    end

    -- Recursive helper with cycle protection and depth limit
    local visitedCats = {}
    local MAX_DEPTH = 10

    local function collectRecursive(catID, depth)
        if not catID or depth > MAX_DEPTH then return end
        if visitedCats[catID] then return end
        visitedCats[catID] = true

        if useModernAPI then
            -- Use pre-built category lookup
            local achIDs = categoryToAchievements[catID]
            if achIDs then
                for _, achID in ipairs(achIDs) do
                    if not seen[achID] then
                        seen[achID] = true
                        ids[#ids + 1] = achID
                    end
                end
            end
        else
            -- Fallback: two-arg GetAchievementInfo(catID, i)
            local numOk, numAchievements = pcall(GetCategoryNumAchievements, catID, false)
            if not numOk then numAchievements = 0 end
            numAchievements = numAchievements or 0

            for i = 1, numAchievements do
                local ok, achID = pcall(GetAchievementInfo, catID, i)
                if ok and achID then
                    if not seen[achID] then
                        seen[achID] = true
                        ids[#ids + 1] = achID
                    end
                end
            end
        end

        -- Recurse into child categories using pre-built map
        local children = childMap[catID]
        if children then
            for _, subCatID in ipairs(children) do
                collectRecursive(subCatID, depth + 1)
            end
        end
    end

    collectRecursive(categoryID, 0)
    return ids
end

-- Filter achievement results
function FB.Achievements.Scanner:FilterResults(results, filters)
    if not results then return {} end
    if not filters then return results end

    local filtered = {}
    for _, r in ipairs(results) do
        local pass = true

        -- Reward type filter
        if filters.rewardType and filters.rewardType ~= "all" then
            if r.rewardType ~= filters.rewardType then
                pass = false
            end
        end

        -- Solo only
        if filters.soloOnly and r.groupRequirement ~= "solo" then
            pass = false
        end

        -- Hide completed
        if filters.hideCompleted and r.progressRemaining ~= nil and r.progressRemaining <= 0 then
            pass = false
        end

        if pass then
            filtered[#filtered + 1] = r
        end
    end

    return filtered
end
