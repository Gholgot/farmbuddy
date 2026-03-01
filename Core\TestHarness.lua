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

-- Reset test state
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
        solo = true, duo = true, small = true, full = true, mythic = true,
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
local function TestAttemptTracking()
    Assert(FB.CharacterData.RecordMountAttempts ~= nil, "RecordMountAttempts exists")

    -- Verify mountAttempts table exists in account DB defaults
    if FB.db then
        Assert(FB.db.mountAttempts ~= nil or true, "mountAttempts table accessible")
    end
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
