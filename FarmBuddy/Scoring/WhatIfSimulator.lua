local addonName, FB = ...

FB.WhatIfSimulator = {}

--[[
    What-If Simulator: Preview how achieving a goal (e.g., Exalted with a faction)
    would change mount availability and scores.

    All results are clearly labeled as simulated.
    Uses real mount data with hypothetical progress overrides.
]]

-- Simulate what happens when a reputation reaches a target standing
-- @param factionID      number
-- @param targetStanding number (8 = Exalted)
-- @return table { unlockedMounts = {}, totalNew = N }
function FB.WhatIfSimulator:SimulateReputation(factionID, targetStanding)
    if not factionID or not FB.db or not FB.db.cachedMountScores then
        return { unlockedMounts = {}, totalNew = 0 }
    end

    targetStanding = targetStanding or 8
    local unlockedMounts = {}

    for _, r in ipairs(FB.db.cachedMountScores) do
        -- Check if this mount requires this faction
        if r.factionID and r.factionID == factionID then
            -- Check current progress
            if r.progressRemaining and r.progressRemaining > 0 then
                -- FIX-9: Use real progress for remaining non-rep requirements
                local simProgress = 0
                if r.currencyID or r.achievementID or r.goldCost then
                    -- Compute worst-of remaining requirements via ProgressResolver
                    local worstRemaining = 0
                    if r.currencyID and FB.ProgressResolver then
                        local ok, prog = pcall(FB.ProgressResolver.GetCurrencyProgress,
                            FB.ProgressResolver, r.currencyID, r.currencyRequired)
                        if ok and prog then worstRemaining = math.max(worstRemaining, prog) end
                    end
                    if r.achievementID and FB.ProgressResolver then
                        local ok, prog = pcall(FB.ProgressResolver.GetAchievementProgress,
                            FB.ProgressResolver, r.achievementID)
                        if ok and prog then worstRemaining = math.max(worstRemaining, prog) end
                    end
                    if r.goldCost and FB.ProgressResolver then
                        local ok, prog = pcall(FB.ProgressResolver.GetGoldProgress,
                            FB.ProgressResolver, r.goldCost)
                        if ok and prog then worstRemaining = math.max(worstRemaining, prog) end
                    end
                    simProgress = worstRemaining
                end

                if simProgress < r.progressRemaining then
                    unlockedMounts[#unlockedMounts + 1] = {
                        mount = r,
                        currentProgress = math.floor((1 - r.progressRemaining) * 100),
                        simulatedProgress = math.floor((1 - simProgress) * 100),
                    }
                end
            end
        end
    end

    return {
        unlockedMounts = unlockedMounts,
        totalNew = #unlockedMounts,
    }
end

-- Simulate what happens when the player reaches a mount count milestone
-- @param targetCount number (e.g., 500)
-- @return table { achievementsUnlocked = {} }
function FB.WhatIfSimulator:SimulateMountCount(targetCount)
    if not targetCount then return { achievementsUnlocked = {} } end

    local milestones = {
        { count = 100, achievementID = 2143, name = "Leading the Cavalry" },
        { count = 200, achievementID = 7860, name = "We're Going to Need More Saddles" },
        { count = 300, achievementID = 12933, name = "No Stable Big Enough" },
        { count = 400, achievementID = 15917, name = "Mount Parade" },
        { count = 500, achievementID = 17739, name = "Lord of the Reins" },
    }

    -- Use cachedMountScores to determine uncollected count (avoids iterating 1800+ mounts sync).
    -- cachedMountScores only contains uncollected, scoreable mounts.
    local uncollectedCount = FB.db and FB.db.cachedMountScores and #FB.db.cachedMountScores or 0

    -- Get total collected count: query once via C_MountJournal (collected flag only, no scoring loop)
    local currentCount = 0
    if C_MountJournal and C_MountJournal.GetMountIDs then
        local mountIDs = C_MountJournal.GetMountIDs()
        if mountIDs then
            for _, mid in ipairs(mountIDs) do
                local ok, _, _, _, _, _, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID, mid)
                if ok and isCollected then currentCount = currentCount + 1 end
            end
        end
    end

    local achievementsUnlocked = {}
    for _, ms in ipairs(milestones) do
        if currentCount < ms.count and targetCount >= ms.count then
            achievementsUnlocked[#achievementsUnlocked + 1] = {
                count = ms.count,
                achievementID = ms.achievementID,
                name = ms.name,
                mountsNeeded = ms.count - currentCount,
            }
        end
    end

    return {
        achievementsUnlocked = achievementsUnlocked,
        currentCount = currentCount,
        targetCount = targetCount,
    }
end

-- Format simulation results for display
function FB.WhatIfSimulator:FormatRepSimulation(result, factionName)
    if not result or result.totalNew == 0 then
        return string.format(
            "[Simulation] Reaching Exalted with %s:\nNo new mounts would become obtainable.",
            factionName or "this faction"
        )
    end

    local lines = {}
    lines[#lines + 1] = string.format(
        "[Simulation] Reaching Exalted with %s:",
        factionName or "this faction"
    )
    lines[#lines + 1] = string.format("%d mount(s) would become obtainable:", result.totalNew)
    lines[#lines + 1] = ""

    for _, um in ipairs(result.unlockedMounts) do
        lines[#lines + 1] = string.format(
            "  %s: %d%% -> %d%% progress",
            um.mount.name, um.currentProgress, um.simulatedProgress
        )
    end

    return table.concat(lines, "\n")
end
