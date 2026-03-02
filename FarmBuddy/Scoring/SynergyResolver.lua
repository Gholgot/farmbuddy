local addonName, FB = ...

FB.SynergyResolver = {}

--[[
    Synergy Resolver: Cross-references mount farming instances against
    incomplete achievement criteria to find multi-benefit activities.

    Only reports verified connections from AchievementDB data.
    Never fabricates synergies -- if no data exists, returns empty.
]]

-- Build a mapping of instance/expansion -> achievement IDs that reward mounts
-- Called once per scan, cached for the session
local instanceToAchievements = nil

function FB.SynergyResolver:BuildSynergyMap()
    -- PERF-4: Early return if already built — avoids redundant iteration during scan
    if instanceToAchievements then return end
    instanceToAchievements = {}

    if not FB.AchievementDB or not FB.AchievementDB.overrides then return end

    -- Build expansion -> achievement list from overrides
    for achID, meta in pairs(FB.AchievementDB.overrides) do
        if meta.expansion then
            local key = meta.expansion
            if not instanceToAchievements[key] then
                instanceToAchievements[key] = {}
            end
            instanceToAchievements[key][#instanceToAchievements[key] + 1] = achID
        end
    end
end

-- PERF-4: Public method that ensures the synergy map is built before use.
-- Callers (e.g. MountScanner) can call this before beginning a batch scan so the
-- map is ready for every FindSynergies call without per-call lazy-build overhead.
function FB.SynergyResolver:EnsureBuilt()
    self:BuildSynergyMap()
end

-- Find synergies for a mount result
-- Returns a list of achievement synergies: { { id, name, progress, rewardType } }
function FB.SynergyResolver:FindSynergies(mountResult)
    if not mountResult then return {} end

    -- Lazy-build the map
    if not instanceToAchievements then
        self:BuildSynergyMap()
    end

    local synergies = {}
    local seen = {}

    -- Strategy 1: Match by expansion (mount's expansion matches achievement's expansion)
    if mountResult.expansion and instanceToAchievements[mountResult.expansion] then
        for _, achID in ipairs(instanceToAchievements[mountResult.expansion]) do
            if not seen[achID] then
                seen[achID] = true
                local synergy = self:CheckAchievementSynergy(achID, mountResult)
                if synergy then
                    synergies[#synergies + 1] = synergy
                end
            end
        end
    end

    -- Strategy 2: Check mount's own achievementID if it has one
    if mountResult.achievementID and not seen[mountResult.achievementID] then
        local synergy = self:CheckAchievementSynergy(mountResult.achievementID, mountResult)
        if synergy then
            synergies[#synergies + 1] = synergy
        end
    end

    return synergies
end

-- Check if a specific achievement has synergy with a mount
-- Returns nil if no synergy (already completed, no match, etc.)
function FB.SynergyResolver:CheckAchievementSynergy(achievementID, mountResult)
    if not GetAchievementInfo then return nil end

    local ok, id, name, _, completed = pcall(GetAchievementInfo, achievementID)
    if not ok or not id or completed then return nil end

    -- Check progress
    local progress = FB.ProgressResolver:GetAchievementProgress(achievementID)
    if not progress or progress <= 0 then return nil end  -- Already done

    -- FIX-12: Skip synergies for achievements player can't complete
    -- If achievement has zero progress AND zero criteria started, and it's marked
    -- as seasonal or group-required while the mount is solo
    if progress >= 1.0 then  -- Zero progress (1.0 = not started)
        local achMeta = FB.AchievementDB and FB.AchievementDB.overrides
            and FB.AchievementDB.overrides[achievementID]
        if achMeta then
            local isSeasonal = achMeta.seasonal
            local isGroupRequired = achMeta.groupRequired
            local mountIsSolo = not mountResult.groupRequirement
                or mountResult.groupRequirement == "solo"
            if (isSeasonal and mountIsSolo) or (isGroupRequired and mountIsSolo) then
                return nil  -- Skip: achievement is impractical alongside solo farming
            end
        end
    end

    -- Get reward type
    local rewardType = FB.AchievementDB:GetRewardType(achievementID) or "none"

    return {
        id = achievementID,
        name = name,
        progress = progress,
        rewardType = rewardType,
        progressPercent = math.floor((1 - progress) * 100),
    }
end

-- Compute synergy bonus for scoring (multiplicative discount)
-- More synergies = bigger discount, capped at 20%
function FB.SynergyResolver:GetSynergyDiscount(synergies)
    if not synergies or #synergies == 0 then return 0 end

    local mountSynergies = 0
    for _, s in ipairs(synergies) do
        if s.rewardType == "mount" then
            mountSynergies = mountSynergies + 1
        end
    end

    -- Mount-rewarding achievements get higher weight
    local effectiveCount = mountSynergies * 2 + (#synergies - mountSynergies)
    return math.min(0.20, math.log(effectiveCount + 1) * 0.10)
end

-- Format synergies for display in the detail panel
function FB.SynergyResolver:FormatSynergies(synergies)
    if not synergies or #synergies == 0 then return nil end

    local lines = {}
    for _, s in ipairs(synergies) do
        local rewardTag = ""
        if s.rewardType == "mount" then
            rewardTag = " [Mount!]"
        elseif s.rewardType == "title" then
            rewardTag = " [Title]"
        elseif s.rewardType ~= "none" then
            rewardTag = " [" .. s.rewardType .. "]"
        end
        lines[#lines + 1] = string.format(
            "%s (%d%%)%s",
            s.name, s.progressPercent, rewardTag
        )
    end
    return lines
end

-- Invalidate cache (call on new scan)
function FB.SynergyResolver:InvalidateCache()
    instanceToAchievements = nil
end
