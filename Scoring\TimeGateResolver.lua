local addonName, FB = ...

FB.TimeGateResolver = {}

local GetNumSavedInstances = GetNumSavedInstances
local GetSavedInstanceInfo = GetSavedInstanceInfo
local C_QuestLog = C_QuestLog

-- Check if current character is locked to an instance
-- Returns: isLocked, secondsRemaining
function FB.TimeGateResolver:IsInstanceLocked(instanceName, difficultyID)
    if not instanceName then return false, 0 end

    local numInstances = GetNumSavedInstances()
    for i = 1, numInstances do
        local name, _, reset, difficulty, locked = GetSavedInstanceInfo(i)
        if name == instanceName and locked and reset and reset > 0 then
            if not difficultyID or difficulty == difficultyID then
                return true, reset
            end
        end
    end

    return false, 0
end

-- Check if current character has used their daily Heroic dungeon lockout
-- Legacy heroic dungeons (TBC/WotLK/Cata) use a per-instance daily lockout
-- that resets on the daily reset timer, not via GetSavedInstanceInfo for some cases.
-- Uses GetDifficultyInfo + saved instance data for heroic-specific detection.
function FB.TimeGateResolver:IsHeroicDailyLocked(instanceName)
    if not instanceName then return false end

    -- Check saved instances for heroic difficulty IDs (2 = Heroic 5-man)
    local numInstances = GetNumSavedInstances()
    for i = 1, numInstances do
        local name, _, reset, difficulty, locked = GetSavedInstanceInfo(i)
        if name == instanceName and locked and reset and reset > 0 then
            -- Heroic 5-man difficulty IDs: 2 (Heroic dungeon, legacy), 23 (Heroic dungeon, modern)
            if difficulty == 2 or difficulty == 23 then
                return true
            end
        end
    end

    -- Also check the per-character daily lockout tracking (for dungeon resets that
    -- don't appear in GetSavedInstanceInfo on some clients)
    if FB.charDB and FB.charDB.heroicLockouts then
        local lockout = FB.charDB.heroicLockouts[instanceName]
        if lockout and lockout > time() then
            return true
        end
    end

    return false
end

-- Check if a daily quest is completed today
function FB.TimeGateResolver:IsDailyDone(questID)
    if not questID then return false end
    local ok, result = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
    if ok then return result end
    return false
end

-- Determine how many attempts remain in the current reset period
-- Returns: attemptsRemaining (0 if locked, 1 if available)
function FB.TimeGateResolver:GetAttemptsRemaining(mountMeta)
    if not mountMeta then return 1 end

    local timeGate = mountMeta.timeGate or "none"

    if timeGate == "weekly" and mountMeta.lockoutInstanceName then
        local locked = self:IsInstanceLocked(
            mountMeta.lockoutInstanceName,
            mountMeta.difficultyID
        )
        return locked and 0 or 1

    elseif timeGate == "daily" then
        if mountMeta.dailyQuestID then
            local done = self:IsDailyDone(mountMeta.dailyQuestID)
            return done and 0 or 1
        end
        -- For dungeons with daily heroic lockout, check both standard and heroic detection
        if mountMeta.lockoutInstanceName then
            -- First check standard instance lockout
            local locked = self:IsInstanceLocked(
                mountMeta.lockoutInstanceName,
                mountMeta.difficultyID
            )
            if locked then return 0 end
            -- Also check heroic daily lockout (legacy dungeons)
            if self:IsHeroicDailyLocked(mountMeta.lockoutInstanceName) then
                return 0
            end
            return 1
        end

    elseif timeGate == "yearly" then
        -- Yearly events: check if the event is active via C_Calendar
        if self:IsHolidayEventActive(mountMeta) then
            -- Event is active, check daily quest if available
            if mountMeta.dailyQuestID then
                local done = self:IsDailyDone(mountMeta.dailyQuestID)
                return done and 0 or 1
            end
            return 1  -- Event active, no daily quest tracked
        else
            return 0  -- Event not active
        end

    elseif timeGate == "none" then
        return 1  -- Always available (spammable)
    end

    return 1  -- Default: assume available
end

-- Check if a holiday event is currently active using C_Calendar
function FB.TimeGateResolver:IsHolidayEventActive(mountMeta)
    if not C_Calendar or not C_Calendar.GetNumDayEvents then
        return true  -- API unavailable, assume active
    end

    -- Build search text from mount metadata
    local searchText = ""
    if mountMeta.name then searchText = mountMeta.name:lower() end
    if mountMeta.sourceText then searchText = searchText .. " " .. mountMeta.sourceText:lower() end

    -- Map mount keywords to event names
    local eventKeywords = {
        { mount = "horseman", event = "hallow" },
        { mount = "hallow", event = "hallow" },
        { mount = "love rocket", event = "love is in the air" },
        { mount = "big love", event = "love is in the air" },
        { mount = "brewfest", event = "brewfest" },
        { mount = "kodo", event = "brewfest" },
        { mount = "midsummer", event = "midsummer" },
        { mount = "winter veil", event = "feast of winter veil" },
        { mount = "lunar", event = "lunar festival" },
        { mount = "noblegarden", event = "noblegarden" },
    }

    local eventName = nil
    for _, kw in ipairs(eventKeywords) do
        if searchText:find(kw.mount) then
            eventName = kw.event
            break
        end
    end

    if not eventName then
        return true  -- Unknown event, assume active
    end

    -- Check today and nearby days for active events (±1 day range to handle
    -- edge cases where event starts tomorrow or the calendar hasn't refreshed)
    local ok, currentDate = pcall(C_DateAndTime.GetCurrentCalendarTime)
    if not ok or not currentDate then return true end

    local setOk = pcall(C_Calendar.SetAbsMonth, currentDate.month, currentDate.year)
    if not setOk then return true end

    -- Scan a 3-day window: yesterday, today, tomorrow
    local daysInMonth = 31  -- Safe upper bound
    for dayOffset = -1, 1 do
        local checkDay = currentDate.monthDay + dayOffset
        if checkDay >= 1 and checkDay <= daysInMonth then
            local numOk, numEvents = pcall(C_Calendar.GetNumDayEvents, 0, checkDay)
            if numOk and numEvents then
                for i = 1, numEvents do
                    local evOk, eventInfo = pcall(C_Calendar.GetDayEvent, 0, checkDay, i)
                    if evOk and eventInfo and eventInfo.title then
                        if eventInfo.title:lower():find(eventName) then
                            return true  -- Event is active or starting very soon
                        end
                    end
                end
            end
        end
    end

    -- Also check next month if we're at the end of the current month (event might span months)
    if currentDate.monthDay >= 28 then
        local nextMonth = currentDate.month + 1
        local nextYear = currentDate.year
        if nextMonth > 12 then nextMonth = 1; nextYear = nextYear + 1 end
        local nmOk = pcall(C_Calendar.SetAbsMonth, nextMonth, nextYear)
        if nmOk then
            for checkDay = 1, 3 do
                local numOk, numEvents = pcall(C_Calendar.GetNumDayEvents, 0, checkDay)
                if numOk and numEvents then
                    for i = 1, numEvents do
                        local evOk, eventInfo = pcall(C_Calendar.GetDayEvent, 0, checkDay, i)
                        if evOk and eventInfo and eventInfo.title then
                            if eventInfo.title:lower():find(eventName) then
                                -- Restore original month view before returning
                                pcall(C_Calendar.SetAbsMonth, currentDate.month, currentDate.year)
                                return true
                            end
                        end
                    end
                end
            end
            -- Restore original month view
            pcall(C_Calendar.SetAbsMonth, currentDate.month, currentDate.year)
        end
    end

    return false  -- Event not found in nearby days
end

-- Try to detect instance lockout from sourceText for generated DB mounts
function FB.TimeGateResolver:CheckLockoutFromSourceText(sourceText, timeGate)
    if not sourceText or timeGate ~= "weekly" then return 1 end

    -- Try to match the instance name in saved lockouts via substring matching
    local lower = sourceText:lower()
    local numInstances = GetNumSavedInstances()
    for i = 1, numInstances do
        local name, _, reset, _, locked = GetSavedInstanceInfo(i)
        if name and locked and reset and reset > 0 then
            local instanceLower = name:lower()
            if lower:find(instanceLower, 1, true) then
                return 0  -- Locked
            end
        end
    end

    return 1  -- Not locked
end
