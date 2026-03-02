local addonName, FB = ...

FB.Mounts = FB.Mounts or {}
FB.Mounts.Scanner = {}

local C_MountJournal = C_MountJournal

-- Scan all mounts and score them
-- @param onProgress  function(current, total)
-- @param onComplete  function(results)
-- @return async handle
function FB.Mounts.Scanner:StartScan(onProgress, onComplete)
    -- Cancel any existing scan
    if FB.scanHandle and FB.scanHandle.IsRunning and FB.scanHandle:IsRunning() then
        FB.scanHandle:Cancel()
    end

    -- Build list of all mount IDs
    local mountIDs = C_MountJournal.GetMountIDs()
    if not mountIDs or #mountIDs == 0 then
        FB:Print("No mounts found to scan.")
        if onComplete then onComplete({}) end
        return nil
    end

    -- Use adaptive batching by default, or fixed size from settings
    local configBatchSize = (FB.db and FB.db.settings and FB.db.settings.scan and FB.db.settings.scan.batchSize) or 5
    local batchSize = (configBatchSize == 0) and "auto" or configBatchSize
    local weights = FB.Scoring:GetWeights()

    -- Start profiling
    if FB.Profiler then FB.Profiler:Start("MountScan") end

    FB:Debug("Starting mount scan: " .. #mountIDs .. " mounts, batch " .. tostring(batchSize))

    -- Pre-compute warband summary once for the whole scan
    local warbandSummary = FB.CharacterData and FB.CharacterData.GetWarbandSummary
        and FB.CharacterData:GetWarbandSummary() or { totalChars = 1, totalLockouts = 0 }
    local warbandTotal = warbandSummary.totalChars

    -- Pre-load attempt history for staleness tracking
    local attemptHistory = (FB.db and FB.db.mountAttempts) or {}

    local handle = FB.Async:RunBatched(
        mountIDs,
        function(mountID)
            -- Resolve mount data
            local input = FB.Mounts.Resolver:Resolve(mountID)
            if not input then return nil end

            -- Skip unobtainable
            if not FB.Scoring:IsScoreable(input.sourceType) then return nil end

            -- FIX-4: Filter faction-specific mounts at scan time
            if input.isFactionSpecific and input.faction and FB.playerFaction then
                local playerIsAlliance = (FB.playerFaction == "Alliance")
                local mountIsAlliance = (input.faction == "ALLIANCE" or input.faction == 0)
                if playerIsAlliance ~= mountIsAlliance then
                    return nil  -- Wrong faction, don't recommend
                end
            end

            -- Enrich with warband availability for time-gated mounts (#1)
            if input.lockoutInstanceName and input.timeGate == "weekly" and FB.CharacterData
               and FB.CharacterData.GetWarbandLockoutStatus then
                local _, availChars = FB.CharacterData:GetWarbandLockoutStatus(
                    input.lockoutInstanceName, input.difficultyID
                )
                input.warbandAvailable = #availChars
                input.warbandTotal = warbandTotal
            end

            -- Enrich with staleness data (#6)
            local lastAttempt = attemptHistory[input.id]
            if lastAttempt and lastAttempt > 0 then
                input.staleDays = math.floor((time() - lastAttempt) / 86400)
            end

            -- Score it
            local result = FB.Scoring:Score(input, weights)

            -- Combine input + score into a single result
            return {
                -- Mount info
                id = input.id,
                mountID = input.mountID,
                name = input.name,
                icon = input.icon,
                sourceText = input.sourceText,
                sourceType = input.sourceType,
                expansion = input.expansion,
                creatureDisplayID = input.creatureDisplayID,
                groupRequirement = input.groupRequirement,
                timeGate = input.timeGate,
                timePerAttempt = input.timePerAttempt,
                dropChance = input.dropChance,
                dropChanceSource = input.dropChanceSource,
                lockoutScope = input.lockoutScope,
                steps = input.steps,
                hasCuratedData = input.hasCuratedData,
                confidence = input.confidence,
                confidencePercent = input.confidencePercent,
                dataQuality = input.dataQuality,
                progressRemaining = input.progressRemaining,

                -- Reputation/currency metadata (for detail display)
                factionID = input.factionID,
                targetStanding = input.targetStanding,
                targetRenown = input.targetRenown,
                currencyID = input.currencyID,
                currencyRequired = input.currencyRequired,
                achievementID = input.achievementID,
                goldCost = input.goldCost,
                itemCosts = input.itemCosts,
                faction = input.faction,
                isFactionSpecific = input.isFactionSpecific,
                lockoutInstanceName = input.lockoutInstanceName,
                difficultyID = input.difficultyID,
                attemptsRemaining = input.attemptsRemaining,
                rarity = input.rarity,
                warbandAvailable = input.warbandAvailable,
                warbandTotal = input.warbandTotal,
                staleDays = input.staleDays,
                synergies = FB.SynergyResolver and FB.SynergyResolver.FindSynergies
                    and FB.SynergyResolver:FindSynergies({
                        expansion = input.expansion,
                        achievementID = input.achievementID,
                        lockoutInstanceName = input.lockoutInstanceName,
                        groupRequirement = input.groupRequirement,
                    }) or {},
                attemptCount = (FB.db and FB.db.mountAttemptCounts and FB.db.mountAttemptCounts[input.id])
                    and FB.db.mountAttemptCounts[input.id].total or nil,

                -- Score
                score = result.score,
                components = result.components,
                effectiveDays = result.effectiveDays,
                expectedAttempts = result.expectedAttempts,
                immediatelyAvailable = result.immediatelyAvailable,
                scoreExplanation = result.scoreExplanation
                    .. (input.confidence == "low" and " | (data: estimated)" or
                        input.confidence == "medium" and " | (data: partial)" or ""),
                isUnknownDrop = result.isUnknownDrop,
            }
        end,
        batchSize,
        onProgress,
        function(results)
            -- Post-scan pass: compute instance grouping (#3)
            -- Count how many scored mounts share the same lockoutInstanceName
            local instanceCounts = {}
            for _, r in ipairs(results) do
                if r.lockoutInstanceName then
                    local key = r.lockoutInstanceName
                    instanceCounts[key] = (instanceCounts[key] or 0) + 1
                end
            end
            -- Apply instance efficiency bonus: re-score mounts that share an instance
            for _, r in ipairs(results) do
                if r.lockoutInstanceName and instanceCounts[r.lockoutInstanceName]
                   and instanceCounts[r.lockoutInstanceName] > 1 then
                    r.instanceGroupCount = instanceCounts[r.lockoutInstanceName]
                    -- Re-score with the instance group data
                    local rescore = FB.Scoring:Score({
                        progressRemaining = r.progressRemaining,
                        timePerAttempt = r.timePerAttempt,
                        timeGate = r.timeGate,
                        attemptsRemaining = r.attemptsRemaining,
                        groupRequirement = r.groupRequirement,
                        dropChance = r.dropChance,
                        dropChanceSource = r.dropChanceSource,
                        lockoutScope = r.lockoutScope,
                        expectedAttempts = r.expectedAttempts,
                        warbandAvailable = r.warbandAvailable,
                        warbandTotal = r.warbandTotal,
                        instanceGroupCount = r.instanceGroupCount,
                        staleDays = r.staleDays,
                        sourceType = r.sourceType,
                    }, weights)
                    r.score = rescore.score
                    r.components = rescore.components
                    r.effectiveDays = rescore.effectiveDays
                    r.immediatelyAvailable = rescore.immediatelyAvailable
                    -- Re-apply confidence suffix that was added in the initial score pass
                    r.scoreExplanation = rescore.scoreExplanation
                        .. (r.confidence == "low" and " | (data: estimated)" or
                            r.confidence == "medium" and " | (data: partial)" or "")
                end
            end

            -- Apply synergy discount: mounts with achievement synergies get a bonus
            if FB.SynergyResolver then
                for _, r in ipairs(results) do
                    if r.synergies and #r.synergies > 0 then
                        local discount = FB.SynergyResolver:GetSynergyDiscount(r.synergies)
                        if discount > 0 then
                            r.score = r.score * (1 - discount)
                            -- Append synergy info to explanation
                            local mountSynCount = 0
                            for _, s in ipairs(r.synergies) do
                                if s.rewardType == "mount" then mountSynCount = mountSynCount + 1 end
                            end
                            if mountSynCount > 0 then
                                r.scoreExplanation = r.scoreExplanation .. " | +" .. mountSynCount .. " achievement mount(s)"
                            else
                                r.scoreExplanation = r.scoreExplanation .. " | +" .. #r.synergies .. " achievement(s)"
                            end
                        end
                    end
                end
            end

            -- Diminishing returns: annotate mounts with high attempt counts
            if FB.db and FB.db.mountAttemptCounts then
                for _, r in ipairs(results) do
                    if r.attemptCount and r.dropChance and r.dropChance > 0 then
                        local expected = math.ceil(1 / r.dropChance)
                        if r.attemptCount > expected then
                            local ratio = r.attemptCount / expected
                            local pUnlucky = math.pow(1 - r.dropChance, r.attemptCount) * 100
                            r.luckPercentile = pUnlucky
                            r.scoreExplanation = r.scoreExplanation .. string.format(
                                " | %d/%d attempts (unluckiest %.0f%%)",
                                r.attemptCount, expected, pUnlucky
                            )
                        elseif r.attemptCount > 0 then
                            r.scoreExplanation = r.scoreExplanation .. string.format(
                                " | %d/%d attempts",
                                r.attemptCount, expected
                            )
                        end
                    end
                end
            end

            -- Sort by score ascending (easiest first), name as tiebreaker for stability
            table.sort(results, function(a, b)
                if a.score ~= b.score then
                    return a.score < b.score
                end
                return (a.name or "") < (b.name or "")
            end)

            -- Cache results
            if FB.db then
                FB.db.cachedMountScores = results
            end
            if FB.charDB then
                FB.charDB.lastMountScan = time()
            end

            -- Stop profiling
            if FB.Profiler then
                local elapsed = FB.Profiler:Stop("MountScan")
                FB:Debug(string.format("Mount scan complete: %d scored mounts in %.0fms", #results, elapsed))
            else
                FB:Debug("Mount scan complete: " .. #results .. " scored mounts")
            end

            if onComplete then
                onComplete(results)
            end
        end
    )

    FB.scanHandle = handle
    return handle
end

-- Get cached results (from last scan)
function FB.Mounts.Scanner:GetCachedResults()
    return FB.db and FB.db.cachedMountScores
end

-- Filter results by criteria
function FB.Mounts.Scanner:FilterResults(results, filters)
    if not results then return {} end
    if not filters then return results end

    local filtered = {}
    for _, r in ipairs(results) do
        local pass = true

        -- Source type filters
        if filters.sourceType and r.sourceType ~= filters.sourceType then
            pass = false
        end

        -- Solo only filter
        if filters.soloOnly and r.groupRequirement ~= "solo" then
            pass = false
        end

        -- Expansion filter
        if filters.expansion and r.expansion ~= filters.expansion then
            pass = false
        end

        -- Source type category filters
        if filters.showRaidDrop == false and r.sourceType == "raid_drop" then pass = false end
        if filters.showDungeonDrop == false and r.sourceType == "dungeon_drop" then pass = false end
        if filters.showReputation == false and r.sourceType == "reputation" then pass = false end
        if filters.showCurrency == false and r.sourceType == "currency" then pass = false end
        if filters.showQuestChain == false and r.sourceType == "quest_chain" then pass = false end
        if filters.showEvent == false and r.sourceType == "event" then pass = false end
        if filters.showWorldDrop == false and (r.sourceType == "world_drop" or r.sourceType == "world_boss") then pass = false end
        if filters.showPvP == false and r.sourceType == "pvp" then pass = false end
        if filters.showTradingPost == false and r.sourceType == "trading_post" then pass = false end
        if filters.showProfession == false and r.sourceType == "profession" then pass = false end
        if filters.showAchievement == false and r.sourceType == "achievement" then pass = false end
        if filters.showVendor == false and r.sourceType == "vendor" then pass = false end

        -- Immediately available only
        if filters.availableOnly and not r.immediatelyAvailable then pass = false end

        if pass then
            filtered[#filtered + 1] = r
        end
    end

    return filtered
end

-- Cancel running scan
function FB.Mounts.Scanner:CancelScan()
    if FB.scanHandle and FB.scanHandle.IsRunning and FB.scanHandle:IsRunning() then
        FB.scanHandle:Cancel()
        FB.scanHandle = nil
        FB:Debug("Mount scan cancelled")
    end
end
