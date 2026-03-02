local addonName, FB = ...

FB.SessionPlanner = {}

--[[
    Session Planner: Given a time budget, builds an optimal farming plan.
    Uses a greedy knapsack approach: pick mounts by value density (score / time),
    group instance mounts together, and respect lockouts.

    All recommendations are based on real scored data from the last scan.
    No fabricated estimates -- if data is missing, the mount is excluded.
]]

-- Generate a session plan from scored mount results
-- @param results       table   - Scored mount results from MountScanner
-- @param timeBudget    number  - Available time in minutes
-- @param filters       table   - Optional filter overrides
-- @return plan         table   - Ordered list of activities
function FB.SessionPlanner:GeneratePlan(results, timeBudget, filters)
    if not results or #results == 0 or not timeBudget or timeBudget <= 0 then
        return { activities = {}, totalMinutes = 0, expectedMounts = 0 }
    end

    -- Step 1: Filter to only immediately available mounts with known time estimates
    local candidates = {}
    for _, r in ipairs(results) do
        if r.immediatelyAvailable and r.timePerAttempt and r.timePerAttempt > 0 then
            local pass = true

            -- Apply optional filters
            if filters then
                if filters.soloOnly and r.groupRequirement ~= "solo" then pass = false end
                if filters.expansion and r.expansion ~= filters.expansion then pass = false end
            end

            if pass then
                candidates[#candidates + 1] = r
            end
        end
    end

    -- Step 2: Group by instance (mounts from the same run cost zero extra time)
    local instanceGroups = {}   -- instanceName -> { mounts = {}, timePerAttempt }
    local standalone = {}       -- mounts without a shared instance

    for _, mount in ipairs(candidates) do
        if mount.lockoutInstanceName then
            local key = mount.lockoutInstanceName
            if not instanceGroups[key] then
                instanceGroups[key] = {
                    instanceName = key,
                    mounts = {},
                    timePerAttempt = mount.timePerAttempt,
                    expansion = mount.expansion,
                    bestScore = mount.score,
                }
            end
            instanceGroups[key].mounts[#instanceGroups[key].mounts + 1] = mount
            -- Use the shortest time estimate for the instance
            if mount.timePerAttempt < instanceGroups[key].timePerAttempt then
                instanceGroups[key].timePerAttempt = mount.timePerAttempt
            end
            -- Track best score for sorting
            if mount.score < instanceGroups[key].bestScore then
                instanceGroups[key].bestScore = mount.score
            end
        else
            standalone[#standalone + 1] = mount
        end
    end

    -- Step 3: Convert to activity list with value density
    local activities = {}

    for _, group in pairs(instanceGroups) do
        local mountCount = #group.mounts
        -- Use best-mount score as the primary density driver, with a small
        -- bonus per extra mount (5% each, capped at 50%). This prevents
        -- 1 great mount + 9 trash from tying with 1 great mount alone.
        local bestInvertedScore = 0
        for _, m in ipairs(group.mounts) do
            local inv = math.max(1, 1000 - (m.score or 1000))
            if inv > bestInvertedScore then bestInvertedScore = inv end
        end
        local extraMountBonus = 1 + math.min(0.50, (mountCount - 1) * 0.05)
        local density = (bestInvertedScore * extraMountBonus) / math.max(1, group.timePerAttempt)
        activities[#activities + 1] = {
            type = "instance",
            instanceName = group.instanceName,
            mounts = group.mounts,
            mountCount = mountCount,
            timeMinutes = group.timePerAttempt,
            density = density,
            bestScore = group.bestScore,
            expansion = group.expansion,
        }
    end

    for _, mount in ipairs(standalone) do
        -- MED-6: Invert score for single mounts so high-priority mounts rank first
        local invertedScore = math.max(1, 1000 - (mount.score or 1000))
        local density = invertedScore / math.max(1, mount.timePerAttempt)
        activities[#activities + 1] = {
            type = "single",
            mounts = { mount },
            mountCount = 1,
            timeMinutes = mount.timePerAttempt,
            density = density,
            bestScore = mount.score,
            expansion = mount.expansion,
            instanceName = mount.sourceText,
        }
    end

    -- Step 4: Sort by value density (highest first), then by score (lowest first)
    table.sort(activities, function(a, b)
        if a.density ~= b.density then
            return a.density > b.density
        end
        return a.bestScore < b.bestScore
    end)

    -- Step 5: Greedy knapsack - pick activities until time budget is exhausted
    local plan = {}
    local totalMinutes = 0
    local totalMounts = 0
    local skipped = {}

    for _, activity in ipairs(activities) do
        if totalMinutes + activity.timeMinutes <= timeBudget then
            plan[#plan + 1] = activity
            totalMinutes = totalMinutes + activity.timeMinutes
            totalMounts = totalMounts + activity.mountCount
        else
            skipped[#skipped + 1] = activity
        end
    end

    -- Second pass: try to fill remaining time with skipped activities
    for _, activity in ipairs(skipped) do
        if totalMinutes + activity.timeMinutes <= timeBudget then
            plan[#plan + 1] = activity
            totalMinutes = totalMinutes + activity.timeMinutes
            totalMounts = totalMounts + activity.mountCount
        end
    end

    return {
        activities = plan,
        totalMinutes = totalMinutes,
        expectedMounts = totalMounts,
        timeBudget = timeBudget,
        candidateCount = #candidates,
    }
end

-- Generate a text summary of the session plan
function FB.SessionPlanner:FormatPlan(plan)
    if not plan or not plan.activities or #plan.activities == 0 then
        return "No activities fit the time budget. Try increasing the time or running a mount scan first."
    end

    local lines = {}
    lines[#lines + 1] = string.format(
        "Session Plan: %d activities, ~%d min (%d mount chances)",
        #plan.activities, plan.totalMinutes, plan.expectedMounts
    )
    lines[#lines + 1] = ""

    for i, activity in ipairs(plan.activities) do
        local header
        if activity.type == "instance" then
            header = string.format(
                "%d. %s (~%d min, %d mount%s)",
                i, activity.instanceName, activity.timeMinutes,
                activity.mountCount, activity.mountCount > 1 and "s" or ""
            )
        else
            local mount = activity.mounts[1]
            header = string.format(
                "%d. %s (~%d min)",
                i, mount.name, activity.timeMinutes
            )
        end
        lines[#lines + 1] = header

        -- List individual mounts in this activity
        for _, mount in ipairs(activity.mounts) do
            local dropInfo = ""
            if mount.dropChance then
                dropInfo = string.format(" (%.1f%% drop)", mount.dropChance * 100)
            end
            local confTag = ""
            if mount.confidence == "low" then confTag = " [est.]"
            elseif mount.confidence == "medium" then confTag = " [~est.]"
            end
            lines[#lines + 1] = string.format(
                "   - %s%s%s", mount.name, dropInfo, confTag
            )
        end
    end

    local remaining = plan.timeBudget - plan.totalMinutes
    if remaining > 5 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("~%d min remaining in budget", remaining)
    end

    return table.concat(lines, "\n")
end

-- Get the best character for an activity (warband optimization)
function FB.SessionPlanner:GetBestCharForActivity(activity)
    if not FB.CharacterData or not FB.CharacterData.GetBestAltForInstance then
        return nil
    end
    if activity.type == "instance" and activity.instanceName then
        local mount = activity.mounts[1]
        local difficultyID = mount and mount.difficultyID
        local faction = mount and mount.faction
        return FB.CharacterData:GetBestAltForInstance(
            activity.instanceName, difficultyID, faction
        )
    end
    return FB.playerKey
end
