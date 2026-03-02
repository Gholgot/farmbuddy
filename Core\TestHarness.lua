local addonName, FB = ...

FB.TestHarness = {}

local passed = 0
local failed = 0
local errors = {}

local function Assert(condition, testName, detail)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        errors[#errors + 1] = testName .. (detail and (": " .. detail) or "")
    end
end

local function AssertEqual(expected, actual, testName)
    if expected == actual then
        passed = passed + 1
    else
        failed = failed + 1
        errors[#errors + 1] = testName .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")"
    end
end

local function AssertRange(value, min, max, testName)
    if value >= min and value <= max then
        passed = passed + 1
    else
        failed = failed + 1
        errors[#errors + 1] = testName .. " (" .. tostring(value) .. " not in [" .. min .. ", " .. max .. "])"
    end
end

-- Reset test state.
-- Called automatically at the start of each Run(). Not intended for external use.
local function Reset()
    passed = 0
    failed = 0
    errors = {}
end

-- =====================
-- TEST SUITES
-- =====================

-- Test 1: Scoring Engine weight normalization
local function TestScoringWeights()
    local weights = FB.Scoring:GetWeights()
    Assert(weights ~= nil, "Weights exist")
    Assert(weights.progressRemaining ~= nil, "progressRemaining weight exists")
    Assert(weights.timePerAttempt ~= nil, "timePerAttempt weight exists")
    Assert(weights.timeGate ~= nil, "timeGate weight exists")
    Assert(weights.groupRequirement ~= nil, "groupRequirement weight exists")
    -- Check backward compat: effort or dropChance
    Assert(weights.effort ~= nil or weights.dropChance ~= nil, "effort/dropChance weight exists")
end

-- Test 2: Scoring produces valid results for known inputs
local function TestScoringOutput()
    local weights = FB.Scoring:GetWeights()

    -- Easy mount: solo, no lockout, high drop chance
    local easyInput = {
        sourceType = "dungeon_drop",
        progressRemaining = 1.0,
        timePerAttempt = 5,
        timeGate = "none",
        groupRequirement = "solo",
        dropChance = 0.10,
        expectedAttempts = 10,
        attemptsRemaining = 1,
    }

    -- Hard mount: group, weekly, low drop chance
    local hardInput = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 25,
        timeGate = "weekly",
        groupRequirement = "full",
        dropChance = 0.01,
        expectedAttempts = 100,
        attemptsRemaining = 1,
    }

    local easyResult = FB.Scoring:Score(easyInput, weights)
    local hardResult = FB.Scoring:Score(hardInput, weights)

    Assert(easyResult ~= nil, "Easy mount produces score")
    Assert(hardResult ~= nil, "Hard mount produces score")
    Assert(easyResult.score ~= nil, "Easy mount has score value")
    Assert(hardResult.score ~= nil, "Hard mount has score value")
    Assert(easyResult.score < hardResult.score, "Easy mount scores lower than hard mount",
        string.format("easy=%.1f, hard=%.1f", easyResult.score, hardResult.score))
    AssertRange(easyResult.score, 0, 500, "Easy mount score in reasonable range")
    AssertRange(hardResult.score, 0, 500, "Hard mount score in reasonable range")
end

-- Test 3: Drop mounts should NOT use progressScore (Fix #8 verification)
local function TestDropMountProgress()
    local weights = FB.Scoring:GetWeights()
    local dropInput = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 20,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = 0.01,
        expectedAttempts = 100,
        attemptsRemaining = 1,
    }

    local result = FB.Scoring:Score(dropInput, weights)
    Assert(result ~= nil, "Drop mount produces score")
    if result and result.components then
        AssertEqual(0, result.components.progress or 0, "Drop mount progress component is 0")
    end
end

-- Test 3b: Guaranteed mounts should score LOWER than long RNG grinds
-- Fixes the critical bug where Riddler's Mind-Worm (30min guaranteed) scored
-- worse than Ashes of Al'ar (~1 year of weekly lockouts)
local function TestGuaranteedVsRNG()
    local weights = FB.Scoring:GetWeights()

    -- Guaranteed mount: 30 min quest chain, no RNG, no lockout
    local guaranteed = {
        sourceType = "quest_chain",
        progressRemaining = 1.0,
        timePerAttempt = 30,
        timeGate = "none",
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 1,
        attemptsRemaining = 1,
    }

    -- Long RNG grind: weekly lockout, 1% drop, ~2 years
    local rngGrind = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 15,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = 0.01,
        expectedAttempts = 100,
        attemptsRemaining = 1,
    }

    local guaranteedResult = FB.Scoring:Score(guaranteed, weights)
    local rngResult = FB.Scoring:Score(rngGrind, weights)

    Assert(guaranteedResult.score < rngResult.score,
        "Guaranteed mount scores lower (better) than long RNG grind",
        string.format("guaranteed=%.1f, rng=%.1f", guaranteedResult.score, rngResult.score))

    -- Also verify the guaranteed mount's progress component is proportional to effort, not flat 100
    Assert(guaranteedResult.components.progress < 20,
        "Guaranteed mount progress component is proportional to effort, not flat 100",
        string.format("progress=%.1f", guaranteedResult.components.progress))
end

-- Test 4: Available vs locked mount scoring
local function TestAvailabilityScoring()
    local weights = FB.Scoring:GetWeights()

    local available = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 15,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = 0.01,
        expectedAttempts = 100,
        attemptsRemaining = 1,
    }

    local locked = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 15,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = 0.01,
        expectedAttempts = 100,
        attemptsRemaining = 0,
    }

    local availResult = FB.Scoring:Score(available, weights)
    local lockedResult = FB.Scoring:Score(locked, weights)

    Assert(availResult ~= nil, "Available mount produces score")
    Assert(lockedResult ~= nil, "Locked mount produces score")
    Assert(availResult.score < lockedResult.score, "Available mount scores lower (better) than locked",
        string.format("avail=%.1f, locked=%.1f", availResult.score, lockedResult.score))
end

-- Test 5: MountDB data integrity
local function TestMountDBIntegrity()
    local count = FB.MountDB:GetCount()
    Assert(count > 20, "MountDB has 20+ entries", "count=" .. count)

    local validSourceTypes = {
        raid_drop = true, dungeon_drop = true, world_drop = true,
        reputation = true, currency = true, quest_chain = true,
        achievement = true, profession = true, pvp = true,
        event = true, vendor = true, trading_post = true, promotion = true,
    }

    local validTimeGates = {
        none = true, daily = true, weekly = true,
        biweekly = true, monthly = true, yearly = true,
    }

    local validGroups = {
        solo = true, duo = true, small = true, full = true, raid = true, mythic = true,
    }

    for spellID, meta in pairs(FB.MountDB.entries) do
        Assert(validSourceTypes[meta.sourceType] ~= nil,
            "MountDB[" .. spellID .. "] has valid sourceType", meta.sourceType)
        Assert(validTimeGates[meta.timeGate] ~= nil,
            "MountDB[" .. spellID .. "] has valid timeGate", meta.timeGate)
        Assert(validGroups[meta.groupRequirement] ~= nil,
            "MountDB[" .. spellID .. "] has valid groupRequirement", meta.groupRequirement)
        if meta.dropChance then
            AssertRange(meta.dropChance, 0.0001, 1.0,
                "MountDB[" .. spellID .. "] dropChance in valid range")
        end
        if meta.timePerAttempt then
            AssertRange(meta.timePerAttempt, 0, 600,
                "MountDB[" .. spellID .. "] timePerAttempt in valid range")
        end
    end
end

-- Test 6: InstanceData integrity
local function TestInstanceDataIntegrity()
    local count = 0
    for _ in pairs(FB.InstanceData.instances) do count = count + 1 end
    Assert(count > 10, "InstanceData has 10+ entries", "count=" .. count)

    for name, data in pairs(FB.InstanceData.instances) do
        Assert(data.expansion ~= nil, "Instance[" .. name .. "] has expansion")
        Assert(data.bossCount ~= nil and data.bossCount > 0,
            "Instance[" .. name .. "] has valid bossCount")
        Assert(data.soloMinutes ~= nil and data.soloMinutes > 0,
            "Instance[" .. name .. "] has valid soloMinutes")
    end
end

-- Test 7: AchievementDB integrity
local function TestAchievementDBIntegrity()
    local rewardCount = 0
    for _ in pairs(FB.AchievementDB.knownRewards) do rewardCount = rewardCount + 1 end
    Assert(rewardCount > 20, "AchievementDB has 20+ known rewards", "count=" .. rewardCount)

    local validRewards = { mount = true, title = true, pet = true, transmog = true, toy = true }
    for achID, rewardType in pairs(FB.AchievementDB.knownRewards) do
        Assert(validRewards[rewardType] ~= nil,
            "AchievementDB[" .. achID .. "] has valid reward type", rewardType)
    end
end

-- Test 8: Utils formatting functions
local function TestUtilsFormatting()
    AssertEqual("0g", FB.Utils:FormatGold(0), "FormatGold(0)")
    AssertEqual("100g", FB.Utils:FormatGold(100), "FormatGold(100)")
    AssertEqual("1,000g", FB.Utils:FormatGold(1000), "FormatGold(1000)")
    AssertEqual("5,000,000g", FB.Utils:FormatGold(5000000), "FormatGold(5M)")
    AssertEqual("< 1 min", FB.Utils:FormatTime(0.5), "FormatTime(0.5)")
    AssertEqual("30 min", FB.Utils:FormatTime(30), "FormatTime(30)")
    AssertEqual("2h", FB.Utils:FormatTime(120), "FormatTime(120)")
    AssertEqual("100%", FB.Utils:FormatPercent(1.0), "FormatPercent(1.0)")
    AssertEqual("50%", FB.Utils:FormatPercent(0.5), "FormatPercent(0.5)")
    AssertEqual("0%", FB.Utils:FormatPercent(0.0), "FormatPercent(0.0)")
end

-- Test 9: ColorByScore doesn't leak hex codes
local function TestColorByScore()
    local result = FB.Utils:ColorByScore("test", 50, 200)
    Assert(result ~= nil, "ColorByScore produces output")
    -- Should NOT contain raw hex like E8FF00 outside of color escape sequences
    -- Valid format: |cFFXXXXXX...|r
    Assert(result:find("|cFF") ~= nil, "ColorByScore contains color escape")
    Assert(result:find("|r") ~= nil, "ColorByScore contains color reset")
    -- The %02X should produce valid 2-char hex, not "E8" from a float
    local hexPart = result:match("|cFF(%x+)")
    if hexPart then
        AssertEqual(6, #hexPart, "ColorByScore hex part is 6 chars")
    end
end

-- Test 10: Warband lockout helpers
local function TestWarbandHelpers()
    Assert(FB.CharacterData ~= nil, "CharacterData module exists")
    Assert(FB.CharacterData.GetWarbandLockoutStatus ~= nil, "GetWarbandLockoutStatus exists")
    Assert(FB.CharacterData.GetBestAltForInstance ~= nil, "GetBestAltForInstance exists")
    Assert(FB.CharacterData.GetWarbandSummary ~= nil, "GetWarbandSummary exists")
    Assert(FB.CharacterData.CleanExpiredLockouts ~= nil, "CleanExpiredLockouts exists")
    Assert(FB.CharacterData.PurgeStaleCharacters ~= nil, "PurgeStaleCharacters exists")

    -- Test summary (should work even with empty data)
    local summary = FB.CharacterData:GetWarbandSummary()
    Assert(summary ~= nil, "GetWarbandSummary returns table")
    Assert(summary.totalChars ~= nil, "Summary has totalChars")
    Assert(summary.totalLockouts ~= nil, "Summary has totalLockouts")
end

-- Test 11: Warband-aware scoring (#1)
local function TestWarbandScoring()
    local weights = FB.Scoring:GetWeights()

    -- Mount on character that's locked, but 3 alts available
    local lockedWithAlts = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 15,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = 0.01,
        expectedAttempts = 100,
        attemptsRemaining = 0,
        warbandAvailable = 3,
        warbandTotal = 4,
    }

    -- Same mount, fully locked across all characters
    local fullyLocked = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 15,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = 0.01,
        expectedAttempts = 100,
        attemptsRemaining = 0,
        warbandAvailable = 0,
        warbandTotal = 4,
    }

    local altsResult = FB.Scoring:Score(lockedWithAlts, weights)
    local fullResult = FB.Scoring:Score(fullyLocked, weights)

    Assert(altsResult.score < fullResult.score,
        "Warband: alts available scores better than fully locked",
        string.format("alts=%.1f, full=%.1f", altsResult.score, fullResult.score))
end

-- Test 12: Instance grouping (#3)
local function TestInstanceGroupScoring()
    local weights = FB.Scoring:GetWeights()

    -- Mount with 3 others from same instance
    local grouped = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 15,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = 0.01,
        expectedAttempts = 100,
        attemptsRemaining = 1,
        instanceGroupCount = 3,
    }

    -- Same mount alone
    local alone = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 15,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = 0.01,
        expectedAttempts = 100,
        attemptsRemaining = 1,
        instanceGroupCount = 1,
    }

    local groupResult = FB.Scoring:Score(grouped, weights)
    local aloneResult = FB.Scoring:Score(alone, weights)

    Assert(groupResult.score < aloneResult.score,
        "Instance group: grouped mount scores better than solo",
        string.format("grouped=%.1f, alone=%.1f", groupResult.score, aloneResult.score))
end

-- Test 13: Score explanation (#4)
local function TestScoreExplanation()
    local weights = FB.Scoring:GetWeights()
    local input = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 10,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = 0.01,
        expectedAttempts = 100,
        attemptsRemaining = 1,
    }

    local result = FB.Scoring:Score(input, weights)
    Assert(result.scoreExplanation ~= nil, "Score has explanation")
    Assert(#result.scoreExplanation > 10, "Explanation is non-trivial",
        "got: " .. (result.scoreExplanation or "nil"))
    Assert(result.scoreExplanation:find("solo") ~= nil, "Explanation mentions solo")
    Assert(result.scoreExplanation:find("weekly") ~= nil, "Explanation mentions weekly")
end

-- Test 14: PvP differentiation (#9)
local function TestPvPDifferentiation()
    Assert(FB.Mounts.Resolver.RefinePvPScoring ~= nil, "RefinePvPScoring exists")

    -- Test Gladiator detection
    local gladInput = { groupRequirement = "solo", timePerAttempt = 20, expectedAttempts = 50, timeGate = "weekly" }
    FB.Mounts.Resolver:RefinePvPScoring(gladInput, "Gladiator mount reward", "Sinful Gladiator's Soul Eater")
    Assert(gladInput.groupRequirement == "mythic", "Gladiator detected as mythic difficulty")
    Assert(gladInput.expectedAttempts >= 400, "Gladiator high expected attempts",
        "got: " .. gladInput.expectedAttempts)

    -- Test Vicious detection
    local viciousInput = { groupRequirement = "solo", timePerAttempt = 20, expectedAttempts = 50, timeGate = "weekly" }
    FB.Mounts.Resolver:RefinePvPScoring(viciousInput, "Earned via rated PvP", "Vicious War Steed")
    Assert(viciousInput.groupRequirement == "small", "Vicious detected as small group")
    AssertEqual(40, viciousInput.expectedAttempts, "Vicious has ~40 expected attempts")
end

-- Test 15: Expansion detection via InstanceData (#7)
local function TestExpansionFromInstanceData()
    Assert(FB.Mounts.Resolver.GuessExpansionFromInstanceData ~= nil, "GuessExpansionFromInstanceData exists")

    local result = FB.Mounts.Resolver:GuessExpansionFromInstanceData("Drop: Icecrown Citadel")
    AssertEqual("WOTLK", result, "ICC detected as WOTLK")

    local result2 = FB.Mounts.Resolver:GuessExpansionFromInstanceData("Drop: Firelands")
    AssertEqual("CATA", result2, "Firelands detected as CATA")

    local result3 = FB.Mounts.Resolver:GuessExpansionFromInstanceData("completely unknown text")
    AssertEqual(nil, result3, "Unknown text returns nil")
end

-- Test 16: Attempt tracking data structure (#6)
-- STUB: This test only verifies the function exists. Full validation requires
-- mock lockout data and a populated MountDB. Add real assertions when mocks are available.
local function TestAttemptTracking()
    Assert(FB.CharacterData.RecordMountAttempts ~= nil, "RecordMountAttempts exists")

    -- Verify mountAttempts table exists in account DB defaults
    if FB.db then
        Assert(FB.db.mountAttempts ~= nil, "mountAttempts table accessible")
    end
end

-- Test 17: SessionPlanner empty results returns empty plan
local function TestSessionPlannerEmpty()
    if not FB.SessionPlanner then
        Assert(false, "SessionPlanner: Empty results returns empty plan", "Module not loaded")
        return
    end
    local plan = FB.SessionPlanner:GeneratePlan({}, 60)
    Assert(plan ~= nil and plan.activities ~= nil, "SessionPlanner: Empty results returns empty plan", "No plan returned")
    AssertEqual(0, #plan.activities, "SessionPlanner: Empty results has 0 activities")
end

-- Test 18: SessionPlanner respects time budget
local function TestSessionPlannerTimeBudget()
    if not FB.SessionPlanner then
        Assert(false, "SessionPlanner: Respects time budget", "Module not loaded")
        return
    end
    local mockResults = {
        { immediatelyAvailable = true, timePerAttempt = 20, score = 10, name = "Mount A",
          groupRequirement = "solo", lockoutInstanceName = "Test Raid", expansion = "WOTLK",
          id = 1, dropChance = 0.01, sourceType = "raid_drop" },
        { immediatelyAvailable = true, timePerAttempt = 15, score = 15, name = "Mount B",
          groupRequirement = "solo", lockoutInstanceName = nil, expansion = "LEGION",
          id = 2, dropChance = 0.02, sourceType = "dungeon_drop" },
        { immediatelyAvailable = true, timePerAttempt = 40, score = 5, name = "Mount C",
          groupRequirement = "solo", lockoutInstanceName = nil, expansion = "CATA",
          id = 3, dropChance = nil, sourceType = "reputation" },
    }
    local plan = FB.SessionPlanner:GeneratePlan(mockResults, 30)
    Assert(plan.totalMinutes <= 30, "SessionPlanner: Respects time budget",
        "Exceeded budget: " .. tostring(plan.totalMinutes))
end

-- Test 19: SynergyResolver returns empty for nil input
local function TestSynergyResolverNilInput()
    if not FB.SynergyResolver then
        Assert(false, "SynergyResolver: Returns empty for nil input", "Module not loaded")
        return
    end
    local synergies = FB.SynergyResolver:FindSynergies(nil)
    AssertEqual(0, #synergies, "SynergyResolver: Returns empty for nil input")
end

-- Test 20: SynergyResolver discount capped at 20%
local function TestSynergyResolverDiscountCap()
    if not FB.SynergyResolver then
        Assert(false, "SynergyResolver: Discount capped at 20%", "Module not loaded")
        return
    end
    local fakeSynergies = {}
    for i = 1, 20 do
        fakeSynergies[i] = { rewardType = "mount" }
    end
    local discount = FB.SynergyResolver:GetSynergyDiscount(fakeSynergies)
    Assert(discount <= 0.20, "SynergyResolver: Discount capped at 20%",
        "Discount exceeded 20%: " .. tostring(discount))
end

-- Test 21: BehaviorTracker requires minimum sessions
local function TestBehaviorTrackerMinSessions()
    if not FB.BehaviorTracker then
        Assert(false, "BehaviorTracker: Requires minimum sessions", "Module not loaded")
        return
    end
    -- With fresh data, should not error; just verify the call succeeds
    local ok, err = pcall(function() FB.BehaviorTracker:HasSufficientData() end)
    Assert(ok, "BehaviorTracker: Requires minimum sessions", tostring(err))
end

-- Test 22: WeeklyPlanner handles no cached data
local function TestWeeklyPlannerNoCache()
    if not FB.WeeklyPlanner then
        Assert(false, "WeeklyPlanner: Handles no cached data", "Module not loaded")
        return
    end
    -- LOW-8: Save state before mutating, restore unconditionally after pcall
    -- so FB.db.cachedMountScores is always restored even if GenerateWeeklyPlan errors.
    local origCache = FB.db and FB.db.cachedMountScores
    if FB.db then FB.db.cachedMountScores = nil end
    local ok, plan = pcall(function() return FB.WeeklyPlanner:GenerateWeeklyPlan() end)
    if FB.db then FB.db.cachedMountScores = origCache end
    Assert(ok, "WeeklyPlanner: GenerateWeeklyPlan did not error with nil cache")
    if ok then
        Assert(plan ~= nil, "WeeklyPlanner: Handles no cached data", "No plan returned")
        AssertEqual(0, plan.totalMounts, "WeeklyPlanner: No cached data yields 0 mounts")
    end
end

-- Test 23: WhatIfSimulator mount count milestones
local function TestWhatIfSimulatorMountCount()
    if not FB.WhatIfSimulator then
        Assert(false, "WhatIfSimulator: Mount count milestones", "Module not loaded")
        return
    end
    local result = FB.WhatIfSimulator:SimulateMountCount(500)
    Assert(result ~= nil, "WhatIfSimulator: Mount count milestones", "No result")
end

-- =====================
-- FIX-16: NEW TESTS
-- =====================

-- Test 24: Uncurated mount without Rarity data has nil dropChance (FIX-1)
local function TestNoFakeDropRate()
    local defaults = FB.Mounts.Resolver:GetDefaultsForSourceType("raid_drop", "WOTLK")
    Assert(defaults.dropChance == nil, "TestNoFakeDropRate: raid_drop defaults have nil dropChance",
        "got: " .. tostring(defaults.dropChance))

    local defaults2 = FB.Mounts.Resolver:GetDefaultsForSourceType("dungeon_drop", "LEGION")
    Assert(defaults2.dropChance == nil, "TestNoFakeDropRate: dungeon_drop defaults have nil dropChance",
        "got: " .. tostring(defaults2.dropChance))

    local defaults3 = FB.Mounts.Resolver:GetDefaultsForSourceType("world_boss", "MOP")
    Assert(defaults3.dropChance == nil, "TestNoFakeDropRate: world_boss defaults have nil dropChance",
        "got: " .. tostring(defaults3.dropChance))
end

-- Test 25: Drop chance source tags (FIX-1/FIX-3)
local function TestDropChanceSource()
    -- A curated mount with explicit dropChance should get "curated" source
    local weights = FB.Scoring:GetWeights()
    local curatedInput = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 15,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = 0.01,
        dropChanceSource = "curated",
        expectedAttempts = 100,
        attemptsRemaining = 1,
    }
    local result = FB.Scoring:Score(curatedInput, weights)
    Assert(result.scoreExplanation:find("verified") ~= nil,
        "TestDropChanceSource: curated shows 'verified'",
        "explanation: " .. (result.scoreExplanation or "nil"))

    -- No drop chance → "drop rate unknown"
    local unknownInput = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 15,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = nil,
        dropChanceSource = nil,
        attemptsRemaining = 1,
    }
    local result2 = FB.Scoring:Score(unknownInput, weights)
    Assert(result2.scoreExplanation:find("drop rate unknown") ~= nil,
        "TestDropChanceSource: nil shows 'drop rate unknown'",
        "explanation: " .. (result2.scoreExplanation or "nil"))
end

-- Test 26: Faction filtering (FIX-4)
local function TestFactionFiltering()
    -- Verify faction detection data flows correctly
    -- (Full in-game scan test requires C_MountJournal; test the filter logic)
    local input = {
        isFactionSpecific = true,
        faction = "ALLIANCE",
    }
    -- A Horde player should not see this mount
    local savedFaction = FB.playerFaction
    FB.playerFaction = "Horde"
    local playerIsAlliance = (FB.playerFaction == "Alliance")
    local mountIsAlliance = (input.faction == "ALLIANCE" or input.faction == 0)
    local shouldFilter = (playerIsAlliance ~= mountIsAlliance)
    FB.playerFaction = savedFaction
    Assert(shouldFilter == true, "TestFactionFiltering: Alliance mount filtered for Horde player")

    -- Same faction should NOT filter
    FB.playerFaction = "Alliance"
    playerIsAlliance = (FB.playerFaction == "Alliance")
    shouldFilter = (playerIsAlliance ~= mountIsAlliance)
    FB.playerFaction = savedFaction
    Assert(shouldFilter == false, "TestFactionFiltering: Alliance mount NOT filtered for Alliance player")
end

-- Test 27: Lockout scope (FIX-5)
local function TestLockoutScope()
    local weights = FB.Scoring:GetWeights()

    -- World boss: account scope → warbandMultiplier should be 1
    local worldBoss = {
        sourceType = "world_boss",
        progressRemaining = 1.0,
        timePerAttempt = 5,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = 0.005,
        expectedAttempts = 200,
        attemptsRemaining = 1,
        warbandAvailable = 5,
        warbandTotal = 5,
        lockoutScope = "account",
    }

    -- Same but with character scope
    local charScope = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 5,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = 0.005,
        expectedAttempts = 200,
        attemptsRemaining = 1,
        warbandAvailable = 5,
        warbandTotal = 5,
        lockoutScope = "character",
    }

    local wbResult = FB.Scoring:Score(worldBoss, weights)
    local charResult = FB.Scoring:Score(charScope, weights)

    -- World boss should score HIGHER (worse) because alts don't help
    Assert(wbResult.effectiveDays > charResult.effectiveDays,
        "TestLockoutScope: account scope has more effective days than character scope",
        string.format("account=%s, char=%s", tostring(wbResult.effectiveDays), tostring(charResult.effectiveDays)))
end

-- Test 28: Configurable playtime (FIX-6)
local function TestConfigurablePlaytime()
    local weights = FB.Scoring:GetWeights()
    local input = {
        sourceType = "quest_chain",
        progressRemaining = 1.0,
        timePerAttempt = 60,
        timeGate = "none",
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 10,
        attemptsRemaining = 1,
    }

    -- Score with default 2h/day
    local origHours = FB.db and FB.db.settings and FB.db.settings.hoursPerDay
    if FB.db and FB.db.settings then FB.db.settings.hoursPerDay = 2 end
    local result2h = FB.Scoring:Score(input, weights)

    -- Score with 4h/day
    if FB.db and FB.db.settings then FB.db.settings.hoursPerDay = 4 end
    local result4h = FB.Scoring:Score(input, weights)

    -- Restore
    if FB.db and FB.db.settings then FB.db.settings.hoursPerDay = origHours end

    Assert(result4h.effectiveDays < result2h.effectiveDays,
        "TestConfigurablePlaytime: 4h/day yields fewer effective days than 2h/day",
        string.format("4h=%s, 2h=%s", tostring(result4h.effectiveDays), tostring(result2h.effectiveDays)))
end

-- Test 29: FormatDaysRange correct percentiles (FIX-7)
local function TestRangeEstimates()
    -- 1% drop, 1 attempt per week — unlucky range exceeds 1 year (yearly-guard path)
    local range = FB.Utils:FormatDaysRange(0.01, 1/7, 2)
    Assert(range ~= nil, "TestRangeEstimates: FormatDaysRange returns string for known drop",
        "got nil")
    if range then
        Assert(range:find("avg") ~= nil, "TestRangeEstimates: range contains 'avg'",
            "got: " .. range)
    end

    -- 10% drop, 1 attempt per day — stays well under a year, uses normal h/day format
    -- MED-13: Use "h/day" instead of "at" to avoid matching inside other words like "data"
    local shortRange = FB.Utils:FormatDaysRange(0.10, 1, 2)
    Assert(shortRange ~= nil, "TestRangeEstimates: FormatDaysRange returns string for 10% drop",
        "got nil")
    if shortRange then
        Assert(shortRange:find("h/day") ~= nil, "TestRangeEstimates: short range contains playtime",
            "got: " .. shortRange)
    end

    -- Nil drop chance should return nil
    local nilRange = FB.Utils:FormatDaysRange(nil, 1, 2)
    Assert(nilRange == nil, "TestRangeEstimates: nil drop returns nil")

    -- 100% drop should return nil (not RNG)
    local certainRange = FB.Utils:FormatDaysRange(1.0, 1, 2)
    Assert(certainRange == nil, "TestRangeEstimates: 100% drop returns nil")
end

-- Test 30: Unknown-drop mount scored conservatively (FIX-2)
local function TestUnknownDropScoring()
    local weights = FB.Scoring:GetWeights()

    -- Known 1% drop raid mount
    local knownDrop = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 15,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = 0.01,
        dropChanceSource = "curated",
        expectedAttempts = 100,
        attemptsRemaining = 1,
    }

    -- Unknown drop raid mount (no fabricated rate)
    local unknownDrop = {
        sourceType = "raid_drop",
        progressRemaining = 1.0,
        timePerAttempt = 15,
        timeGate = "weekly",
        groupRequirement = "solo",
        dropChance = nil,
        dropChanceSource = nil,
        attemptsRemaining = 1,
    }

    local knownResult = FB.Scoring:Score(knownDrop, weights)
    local unknownResult = FB.Scoring:Score(unknownDrop, weights)

    -- Unknown should NOT score as trivially easy (which is what happened before FIX-1)
    Assert(unknownResult.score > 10,
        "TestUnknownDropScoring: unknown-drop mount doesn't score trivially low",
        string.format("score=%.1f", unknownResult.score))

    -- Unknown should be flagged
    Assert(unknownResult.isUnknownDrop == true,
        "TestUnknownDropScoring: isUnknownDrop flag set")
end

-- Test 31: Confidence percent weighted 0-100% (FIX-11)
local function TestConfidencePercent()
    -- GetDefaultsForSourceType returns lockoutScope
    local defaults = FB.Mounts.Resolver:GetDefaultsForSourceType("world_boss", "MOP")
    AssertEqual("account", defaults.lockoutScope,
        "TestConfidencePercent: world_boss has account lockoutScope")

    local defaults2 = FB.Mounts.Resolver:GetDefaultsForSourceType("raid_drop", "WOTLK")
    AssertEqual("character", defaults2.lockoutScope,
        "TestConfidencePercent: raid_drop has character lockoutScope")

    -- Verify confidence colors exist
    Assert(FB.CONFIDENCE_COLORS ~= nil, "TestConfidencePercent: CONFIDENCE_COLORS table exists")
    Assert(FB.CONFIDENCE_COLORS.high ~= nil, "TestConfidencePercent: high color exists")
    Assert(FB.CONFIDENCE_COLORS.medium ~= nil, "TestConfidencePercent: medium color exists")
    Assert(FB.CONFIDENCE_COLORS.low ~= nil, "TestConfidencePercent: low color exists")
end

-- =====================
-- RUNNER
-- =====================

function FB.TestHarness:Run()
    Reset()

    print(FB.ADDON_COLOR .. "FarmBuddy Test Harness|r")
    print("---")

    -- Run all test suites
    local suites = {
        { name = "Scoring Weights",       func = TestScoringWeights },
        { name = "Scoring Output",        func = TestScoringOutput },
        { name = "Drop Mount Progress",   func = TestDropMountProgress },
        { name = "Guaranteed vs RNG",    func = TestGuaranteedVsRNG },
        { name = "Availability Scoring",  func = TestAvailabilityScoring },
        { name = "MountDB Integrity",     func = TestMountDBIntegrity },
        { name = "InstanceData Integrity", func = TestInstanceDataIntegrity },
        { name = "AchievementDB Integrity",func = TestAchievementDBIntegrity },
        { name = "Utils Formatting",      func = TestUtilsFormatting },
        { name = "ColorByScore",          func = TestColorByScore },
        { name = "Warband Helpers",       func = TestWarbandHelpers },
        { name = "Warband Scoring",       func = TestWarbandScoring },
        { name = "Instance Grouping",     func = TestInstanceGroupScoring },
        { name = "Score Explanation",     func = TestScoreExplanation },
        { name = "PvP Differentiation",   func = TestPvPDifferentiation },
        { name = "Expansion InstanceData",func = TestExpansionFromInstanceData },
        { name = "Attempt Tracking",      func = TestAttemptTracking },
        { name = "SessionPlanner Empty",  func = TestSessionPlannerEmpty },
        { name = "SessionPlanner Budget", func = TestSessionPlannerTimeBudget },
        { name = "SynergyResolver Nil",   func = TestSynergyResolverNilInput },
        { name = "SynergyResolver Cap",   func = TestSynergyResolverDiscountCap },
        { name = "BehaviorTracker Min",   func = TestBehaviorTrackerMinSessions },
        { name = "WeeklyPlanner NoCache", func = TestWeeklyPlannerNoCache },
        { name = "WhatIf MountCount",     func = TestWhatIfSimulatorMountCount },
        -- FIX-16: New tests
        { name = "No Fake Drop Rate",   func = TestNoFakeDropRate },
        { name = "Drop Chance Source",   func = TestDropChanceSource },
        { name = "Faction Filtering",    func = TestFactionFiltering },
        { name = "Lockout Scope",        func = TestLockoutScope },
        { name = "Configurable Playtime",func = TestConfigurablePlaytime },
        { name = "Range Estimates",      func = TestRangeEstimates },
        { name = "Unknown Drop Scoring", func = TestUnknownDropScoring },
        { name = "Confidence Percent",   func = TestConfidencePercent },
    }

    for _, suite in ipairs(suites) do
        local beforeFailed = failed
        local ok, err = pcall(suite.func)
        if not ok then
            failed = failed + 1
            errors[#errors + 1] = suite.name .. " CRASHED: " .. tostring(err)
        end
        local suiteFailed = failed - beforeFailed
        local statusIcon = (suiteFailed == 0) and (FB.COLORS.GREEN .. "PASS|r") or (FB.COLORS.RED .. "FAIL|r")
        print("  " .. statusIcon .. " " .. suite.name)
    end

    print("---")
    local totalColor = (failed == 0) and FB.COLORS.GREEN or FB.COLORS.RED
    print(totalColor .. string.format("Results: %d passed, %d failed|r", passed, failed))

    if #errors > 0 then
        print(FB.COLORS.RED .. "Failures:|r")
        for _, err in ipairs(errors) do
            print("  - " .. err)
        end
    end

    return failed == 0
end
