local addonName, FB = ...

FB.Notifications = {}

local notifiedThisSession = false
local eventCheckDone = false

-- Check if today is weekly reset day (Tuesday US, Wednesday EU)
function FB.Notifications:IsResetDay()
    -- Get current server day of week (1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat)
    local serverTime = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if not serverTime then return false end

    local weekday = serverTime.weekday
    -- US realms reset Tuesday (3), EU realms reset Wednesday (4)
    -- GetCurrentRegion: 1=US, 2=Korea, 3=Europe, 4=Taiwan, 5=China
    local region = GetCurrentRegion and GetCurrentRegion() or 1
    local resetDay = (region == 3) and 4 or 3  -- EU=Wednesday, rest=Tuesday

    return weekday == resetDay
end

-- Show weekly reset notification with available mount count
function FB.Notifications:ShowResetNotification()
    if notifiedThisSession then return end

    -- Check if we already notified today
    if FB.db and FB.db.lastResetNotification then
        local now = time()
        if now - FB.db.lastResetNotification < 43200 then  -- 12 hours
            return
        end
    end

    -- Count available mounts for current character
    local availCount = 0
    if FB.MinimapButton and FB.MinimapButton.GetAvailableCount then
        availCount = FB.MinimapButton:GetAvailableCount()
    end

    if availCount > 0 then
        local msg = string.format(
            FB.ADDON_COLOR .. "FarmBuddy|r: Weekly reset! You have |cFF00FF00%d|r mounts to farm this week.",
            availCount
        )
        -- Print to chat
        print(msg)

        -- Show a brief on-screen alert if UIErrorsFrame is available
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(
                string.format("FarmBuddy: %d weekly mounts available!", availCount),
                0.0, 0.8, 1.0, 1.0, 3
            )
        end
    end

    notifiedThisSession = true
    if FB.db then
        FB.db.lastResetNotification = time()
    end
end

-- Check for active holiday events that have yearly mounts
function FB.Notifications:CheckHolidayEvents()
    if eventCheckDone then return end
    eventCheckDone = true

    if not C_Calendar or not C_Calendar.GetNumDayEvents then return end

    local today = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if not today then return end

    -- Check today's calendar events (wrapped in pcall to guard against API errors)
    local setOk = pcall(C_Calendar.SetAbsMonth, today.month, today.year)
    if not setOk then return end

    local numOk, numEvents = pcall(C_Calendar.GetNumDayEvents, 0, today.monthDay)
    if not numOk or not numEvents then return end

    local eventKeywords = {
        ["hallow"] = "Hallow's End",
        ["love is in the air"] = "Love is in the Air",
        ["brewfest"] = "Brewfest",
        ["midsummer"] = "Midsummer Fire Festival",
        ["feast of winter veil"] = "Feast of Winter Veil",
        ["lunar festival"] = "Lunar Festival",
        ["noblegarden"] = "Noblegarden",
    }

    for i = 1, numEvents do
        local evOk, event = pcall(C_Calendar.GetDayEvent, 0, today.monthDay, i)
        if not evOk then event = nil end
        if event and event.title then
            local titleLower = event.title:lower()
            for keyword, displayName in pairs(eventKeywords) do
                if titleLower:find(keyword) then
                    -- Check if we already notified for this event
                    local eventKey = "event_" .. keyword
                    if not (FB.db and FB.db.eventNotifications and FB.db.eventNotifications[eventKey]) then
                        print(string.format(
                            FB.ADDON_COLOR .. "FarmBuddy|r: Holiday event |cFFFFD200%s|r is active! Check your yearly mounts.",
                            displayName
                        ))
                        -- Store that we notified
                        if FB.db then
                            FB.db.eventNotifications = FB.db.eventNotifications or {}
                            FB.db.eventNotifications[eventKey] = time()
                        end
                    end
                    break
                end
            end
        end
    end
end

-- Clean up old event notifications (older than 30 days)
function FB.Notifications:CleanupOldNotifications()
    if not FB.db or not FB.db.eventNotifications then return end
    local now = time()
    for key, timestamp in pairs(FB.db.eventNotifications) do
        if now - timestamp > 2592000 then  -- 30 days
            FB.db.eventNotifications[key] = nil
        end
    end
end

-- Register for login events
FB:RegisterEvent("PLAYER_ENTERING_WORLD", FB.Notifications, function(self, event, isLogin, isReload)
    if not isLogin and not isReload then return end

    -- Delay notifications to let data load
    C_Timer.After(8, function()
        FB.Notifications:CleanupOldNotifications()

        -- Weekly reset notification
        if FB.Notifications:IsResetDay() then
            FB.Notifications:ShowResetNotification()
        end

        -- Holiday event check
        FB.Notifications:CheckHolidayEvents()
    end)
end)
