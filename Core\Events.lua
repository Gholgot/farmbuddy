local addonName, FB = ...

-- Create the central event frame
local EventFrame = CreateFrame("Frame")
FB.EventFrame = EventFrame

-- Handler registry: event -> { {module, func}, ... }
local eventHandlers = {}

-- Register a handler for an event
-- Usage: FB:RegisterEvent("PLAYER_LOGIN", self, self.OnLogin)
--   or:  FB:RegisterEvent("PLAYER_LOGIN", nil, function(event, ...) end)
function FB:RegisterEvent(event, module, func)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        EventFrame:RegisterEvent(event)
    end
    table.insert(eventHandlers[event], { module = module, func = func })
end

-- Unregister all handlers for a module from a specific event
function FB:UnregisterEvent(event, module)
    if not eventHandlers[event] then return end
    for i = #eventHandlers[event], 1, -1 do
        if eventHandlers[event][i].module == module then
            table.remove(eventHandlers[event], i)
        end
    end
    if #eventHandlers[event] == 0 then
        eventHandlers[event] = nil
        EventFrame:UnregisterEvent(event)
    end
end

-- Unregister all handlers for a module from all events
function FB:UnregisterAllEvents(module)
    for event in pairs(eventHandlers) do
        self:UnregisterEvent(event, module)
    end
end

-- Central event dispatcher
EventFrame:SetScript("OnEvent", function(self, event, ...)
    local handlers = eventHandlers[event]
    if not handlers then return end
    for _, handler in ipairs(handlers) do
        if handler.module then
            handler.func(handler.module, event, ...)
        else
            handler.func(event, ...)
        end
    end
end)

-- Register core addon lifecycle events
FB:RegisterEvent("ADDON_LOADED", FB, function(self, event, loadedAddon)
    if loadedAddon ~= addonName then return end

    -- Initialize saved variables
    FB.Storage:Init()

    -- Cache player info
    FB:CachePlayerInfo()

    -- Register/update character in account DB (preserve existing data like lockouts)
    if FB.db and FB.db.characters then
        local existing = FB.db.characters[FB.playerKey] or {}
        existing.class = FB.playerClass
        existing.level = FB.playerLevel
        existing.faction = FB.playerFaction
        existing.lastSeen = time()
        existing.lockouts = existing.lockouts or {}
        FB.db.characters[FB.playerKey] = existing
    end

    FB:Print("v" .. FB.version .. " loaded. Type " .. FB.ADDON_COLOR .. "/fb|r to open.")

    -- Unregister ADDON_LOADED since we only need it once
    FB:UnregisterEvent("ADDON_LOADED", FB)
end)

-- Player entering world (good time to refresh data)
FB:RegisterEvent("PLAYER_ENTERING_WORLD", FB, function(self, event, isLogin, isReload)
    -- Update player info
    FB:CachePlayerInfo()

    -- Update character data (delay slightly to let instance info load)
    C_Timer.After(2, function()
        if FB.CharacterData and FB.CharacterData.UpdateLockouts then
            FB.CharacterData:UpdateLockouts()
        end
        -- Warband housekeeping: clean expired lockouts and purge stale characters
        if FB.CharacterData.CleanExpiredLockouts then
            FB.CharacterData:CleanExpiredLockouts()
        end
        if FB.CharacterData.PurgeStaleCharacters then
            FB.CharacterData:PurgeStaleCharacters()
        end
    end)

    -- Auto-invalidate stale scan cache (older than 1 hour)
    if FB.db and FB.db.cachedMountScores and FB.charDB then
        local lastScan = FB.charDB.lastMountScan or 0
        if time() - lastScan > 3600 then
            FB.db.cachedMountScores = nil
            FB:Debug("Cleared stale mount scan cache (older than 1 hour)")
        end
    end
end)

-- Instance lockout changes
FB:RegisterEvent("UPDATE_INSTANCE_INFO", FB, function(self, event)
    if FB.CharacterData and FB.CharacterData.UpdateLockouts then
        FB.CharacterData:UpdateLockouts()
    end
    -- Record mount attempts for staleness tracking (#6)
    if FB.CharacterData and FB.CharacterData.RecordMountAttempts then
        FB.CharacterData:RecordMountAttempts()
    end
end)

-- Boss kill tracking: detect when player kills a boss (for attempt timestamp accuracy)
-- ENCOUNTER_END fires when a boss encounter ends with success (kill=1)
FB:RegisterEvent("ENCOUNTER_END", FB, function(self, event, encounterID, encounterName, difficultyID, groupSize, success)
    if success ~= 1 then return end  -- Only track kills, not wipes

    -- After a boss kill, delay slightly then update lockouts + record attempts
    C_Timer.After(1, function()
        if FB.CharacterData and FB.CharacterData.UpdateLockouts then
            FB.CharacterData:UpdateLockouts()
        end
        if FB.CharacterData and FB.CharacterData.RecordMountAttempts then
            FB.CharacterData:RecordMountAttempts()
        end
    end)
end)

-- Mount collected: celebrate and update recommendations
FB:RegisterEvent("NEW_MOUNT_ADDED", FB, function(self, event, mountID)
    if not mountID then return end

    local name = C_MountJournal and C_MountJournal.GetMountInfoByID and
        select(1, C_MountJournal.GetMountInfoByID(mountID))

    if name then
        FB:Print(FB.COLORS.GREEN .. "Mount collected: " .. name .. "!|r")
    end

    -- Invalidate scan cache so next view shows updated results
    if FB.db then
        FB.db.cachedMountScores = nil
    end

    -- Record in session history if tracking
    if FB.db and FB.db.sessionHistory then
        local history = FB.db.sessionHistory
        if #history > 0 then
            local lastSession = history[#history]
            if not lastSession.mountsObtained then
                lastSession.mountsObtained = {}
            end
            lastSession.mountsObtained[#lastSession.mountsObtained + 1] = {
                mountID = mountID,
                name = name,
                timestamp = time(),
            }
        end
    end

    -- Refresh tracker if visible
    if FB.Tracker and FB.Tracker.Refresh then
        C_Timer.After(0.5, function()
            FB.Tracker:Refresh()
        end)
    end
end)

-- Zone change: could be useful for "while you're here" suggestions
FB:RegisterEvent("ZONE_CHANGED_NEW_AREA", FB, function(self, event)
    -- Placeholder for future "while you're here" feature
    -- Currently just invalidates synergy cache when entering a new zone
    if FB.SynergyResolver and FB.SynergyResolver.InvalidateCache then
        -- Don't invalidate on every zone change, too expensive
        -- Only invalidate if we enter an instance
        if IsInInstance and IsInInstance() then
            FB.SynergyResolver:InvalidateCache()
        end
    end
end)
