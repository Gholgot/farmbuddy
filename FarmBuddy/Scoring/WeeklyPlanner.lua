local addonName, FB = ...

FB.WeeklyPlanner = {}

--[[
    Weekly Planner: Generates an optimized plan for the current reset period.
    Assigns weekly mounts to characters, integrates holiday events,
    and identifies near-completion gates.

    Only uses real lockout data and scored results.
]]

-- Generate a weekly plan from the current state
-- @return plan table with character assignments and priorities
function FB.WeeklyPlanner:GenerateWeeklyPlan()
    local results = FB.db and FB.db.cachedMountScores
    if not results or #results == 0 then
        return { assignments = {}, totalMounts = 0, nearCompletions = {} }
    end

    local characters = {}
    if FB.db and FB.db.characters then
        for charKey, charInfo in pairs(FB.db.characters) do
            characters[#characters + 1] = {
                key = charKey,
                class = charInfo.class,
                faction = charInfo.faction,
                lockouts = charInfo.lockouts or {},
            }
        end
    end

    -- Step 1: Collect all weekly-gated mounts that are farmable
    local weeklyMounts = {}
    for _, r in ipairs(results) do
        if r.timeGate == "weekly" and r.lockoutInstanceName then
            weeklyMounts[#weeklyMounts + 1] = r
        end
    end

    -- Sort by score (easiest first)
    table.sort(weeklyMounts, function(a, b) return a.score < b.score end)

    -- Step 2: Assign mounts to characters
    local assignments = {}  -- charKey -> { mounts }
    local mountAssigned = {}
    local pendingLockouts = {} -- charKey -> count of mounts assigned this planning pass

    for _, mount in ipairs(weeklyMounts) do
        if not mountAssigned[mount.id] then
            local bestChar = self:FindBestCharForMount(mount, characters, pendingLockouts)
            if bestChar then
                if not assignments[bestChar] then
                    assignments[bestChar] = {}
                end
                assignments[bestChar][#assignments[bestChar] + 1] = mount
                mountAssigned[mount.id] = bestChar
                pendingLockouts[bestChar] = (pendingLockouts[bestChar] or 0) + 1
            end
        end
    end

    -- Step 3: Identify near-completion gates
    local nearCompletions = {}
    for _, r in ipairs(results) do
        if r.progressRemaining and r.progressRemaining > 0 and r.progressRemaining <= 0.15 then
            local isGuaranteed = not r.dropChance or r.dropChance >= 1
            if isGuaranteed then
                nearCompletions[#nearCompletions + 1] = {
                    mount = r,
                    progressPercent = math.floor((1 - r.progressRemaining) * 100),
                }
            end
        end
    end

    -- Step 4: Check for active holiday events
    local activeEvents = {}
    for _, r in ipairs(results) do
        if r.timeGate == "yearly" and r.immediatelyAvailable then
            activeEvents[#activeEvents + 1] = r
        end
    end

    return {
        assignments = assignments,
        totalMounts = #weeklyMounts,
        nearCompletions = nearCompletions,
        activeEvents = activeEvents,
        characterCount = #characters,
    }
end

-- Find the best character for a specific mount
function FB.WeeklyPlanner:FindBestCharForMount(mount, characters, pendingLockouts)
    if not characters or #characters == 0 then return nil end

    local bestChar = nil
    local bestScore = 999

    for _, char in ipairs(characters) do
        -- Check if character is locked for this instance
        local isLocked = false
        local key = mount.lockoutInstanceName .. "-" .. (mount.difficultyID or 0)
        local lockout = char.lockouts[key]
        if lockout and lockout.locked and lockout.resetTime and lockout.resetTime > time() then
            isLocked = true
        end

        if not isLocked then
            -- Check faction compatibility
            if mount.isFactionSpecific and mount.faction then
                if char.faction and char.faction ~= mount.faction and char.faction ~= "Neutral" then
                    -- Skip: wrong faction
                else
                    -- Count active lockouts (fewer = better)
                    local lockoutCount = 0
                    for _, l in pairs(char.lockouts) do
                        if l.locked and l.resetTime and l.resetTime > time() then
                            lockoutCount = lockoutCount + 1
                        end
                    end
                    -- Prefer current character when tied
                    local score = lockoutCount + (pendingLockouts and pendingLockouts[char.key] or 0)
                    if char.key == FB.playerKey then score = score - 0.1 end
                    if score < bestScore then
                        bestScore = score
                        bestChar = char.key
                    end
                end
            else
                local lockoutCount = 0
                for _, l in pairs(char.lockouts) do
                    if l.locked and l.resetTime and l.resetTime > time() then
                        lockoutCount = lockoutCount + 1
                    end
                end
                local score = lockoutCount + (pendingLockouts and pendingLockouts[char.key] or 0)
                if char.key == FB.playerKey then score = score - 0.1 end
                if score < bestScore then
                    bestScore = score
                    bestChar = char.key
                end
            end
        end
    end

    return bestChar
end

-- Format the weekly plan for display
function FB.WeeklyPlanner:FormatPlan(plan)
    if not plan then return "No plan available. Run a mount scan first." end

    local lines = {}
    lines[#lines + 1] = string.format(
        "Weekly Plan: %d mounts across %d characters",
        plan.totalMounts, plan.characterCount
    )
    lines[#lines + 1] = ""

    -- Per-character assignments
    -- LOW-11: Sort character keys so output is deterministic across sessions.
    -- pairs() iteration order is non-deterministic in Lua; sort alphabetically.
    local sortedCharKeys = {}
    for charKey in pairs(plan.assignments) do
        sortedCharKeys[#sortedCharKeys + 1] = charKey
    end
    table.sort(sortedCharKeys)

    for _, charKey in ipairs(sortedCharKeys) do
        local mounts = plan.assignments[charKey]
        local shortName = charKey:match("^(.-)%s*-") or charKey
        local charInfo = FB.db and FB.db.characters and FB.db.characters[charKey]
        local classColor = charInfo and FB.CLASS_COLORS[charInfo.class] or "FFFFFF"
        lines[#lines + 1] = "|cFF" .. classColor .. shortName .. "|r:"

        -- Group by instance
        local byInstance = {}
        for _, m in ipairs(mounts) do
            local inst = m.lockoutInstanceName or "Other"
            if not byInstance[inst] then byInstance[inst] = {} end
            byInstance[inst][#byInstance[inst] + 1] = m
        end

        for inst, instMounts in pairs(byInstance) do
            local mountNames = {}
            for _, m in ipairs(instMounts) do
                mountNames[#mountNames + 1] = m.name
            end
            lines[#lines + 1] = string.format(
                "  %s (%d mount%s)",
                inst, #instMounts, #instMounts > 1 and "s" or ""
            )
        end
        lines[#lines + 1] = ""
    end

    -- Near completions
    if plan.nearCompletions and #plan.nearCompletions > 0 then
        lines[#lines + 1] = "Almost Done:"
        for _, nc in ipairs(plan.nearCompletions) do
            lines[#lines + 1] = string.format(
                "  %s (%d%% complete)", nc.mount.name, nc.progressPercent
            )
        end
        lines[#lines + 1] = ""
    end

    -- Active events
    if plan.activeEvents and #plan.activeEvents > 0 then
        lines[#lines + 1] = "Active Holiday Events:"
        for _, ev in ipairs(plan.activeEvents) do
            lines[#lines + 1] = "  " .. ev.name
        end
    end

    return table.concat(lines, "\n")
end
