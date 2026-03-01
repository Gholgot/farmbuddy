local addonName, FB = ...

FB.CharacterData = {}

local GetNumSavedInstances = GetNumSavedInstances
local GetSavedInstanceInfo = GetSavedInstanceInfo

-- Update lockout snapshots for current character
function FB.CharacterData:UpdateLockouts()
    if not FB.charDB then return end

    local lockouts = {}
    local numInstances = GetNumSavedInstances()

    for i = 1, numInstances do
        local name, _, reset, difficultyID, locked, _, _, isRaid, maxPlayers,
              difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)

        if locked and reset and reset > 0 then
            local key = name .. "-" .. difficultyID
            lockouts[key] = {
                name = name,
                difficultyID = difficultyID,
                difficultyName = difficultyName or "",
                locked = true,
                resetTime = time() + reset,
                bossesKilled = encounterProgress or 0,
                bossesTotal = numEncounters or 0,
                isRaid = isRaid,
                maxPlayers = maxPlayers,
            }
        end
    end

    FB.charDB.lockouts = lockouts

    -- Also update in account-wide character registry
    if FB.db and FB.db.characters and FB.playerKey then
        local charInfo = FB.db.characters[FB.playerKey]
        if charInfo then
            charInfo.lockouts = lockouts
            charInfo.lastSeen = time()
            charInfo.level = FB.playerLevel
        end
    end
end

-- Check if current character is locked to a specific instance/difficulty
function FB.CharacterData:IsLocked(instanceName, difficultyID)
    if not FB.charDB or not FB.charDB.lockouts then return false end

    local key = instanceName .. "-" .. (difficultyID or 0)
    local lockout = FB.charDB.lockouts[key]

    if lockout and lockout.locked then
        -- Check if the lockout has expired
        if lockout.resetTime and lockout.resetTime > time() then
            return true, lockout.resetTime - time()
        end
    end

    return false, 0
end

-- Get all lockouts for current character
function FB.CharacterData:GetLockouts()
    if not FB.charDB then return {} end
    return FB.charDB.lockouts or {}
end

-- Get lockouts for all characters (from account DB)
function FB.CharacterData:GetAllCharacterLockouts()
    if not FB.db or not FB.db.characters then return {} end

    local result = {}
    for charKey, charInfo in pairs(FB.db.characters) do
        result[charKey] = {
            class = charInfo.class,
            level = charInfo.level,
            faction = charInfo.faction,
            lastSeen = charInfo.lastSeen,
            lockouts = charInfo.lockouts or {},
        }
    end
    return result
end

--[[
    Warband (Account-Wide) Lockout Sync

    In TWW (12.0+), WoW provides warband features for cross-character play.
    This module enriches the existing per-character lockout system with:
    1. Cross-character lockout visibility (which alts have run what this week)
    2. "Best alt" recommendation (which character has fewest lockouts)
    3. Stale data cleanup and expired lockout purging

    The approach is SavedVariables-based:
    - Each character logs its own lockouts on login (already done above)
    - The account-wide DB aggregates all characters' lockouts
    - Any character can read the full picture from FB.db.characters
--]]

-- Purge stale character data (characters not seen in 30+ days)
function FB.CharacterData:PurgeStaleCharacters()
    if not FB.db or not FB.db.characters then return 0 end
    local cutoff = time() - (30 * 24 * 3600)
    local purged = 0
    for charKey, charInfo in pairs(FB.db.characters) do
        if charKey ~= FB.playerKey and (charInfo.lastSeen or 0) < cutoff then
            FB.db.characters[charKey] = nil
            purged = purged + 1
        end
    end
    if purged > 0 then
        FB:Debug("Purged " .. purged .. " stale character(s) from account DB")
    end
    return purged
end

-- Check if an instance is locked across ALL characters (warband-wide)
-- Returns: isFullyLocked, availableChars (charKey list), lockedChars (charKey list)
function FB.CharacterData:GetWarbandLockoutStatus(instanceName, difficultyID)
    if not FB.db or not FB.db.characters then
        return false, {}, {}
    end

    local available = {}
    local locked = {}

    for charKey, charInfo in pairs(FB.db.characters) do
        local charLockouts = charInfo.lockouts or {}
        local isLocked = false

        -- Exact key match
        if instanceName then
            local key = instanceName .. "-" .. (difficultyID or 0)
            local lockout = charLockouts[key]
            if lockout and lockout.locked and lockout.resetTime and lockout.resetTime > time() then
                isLocked = true
            end
        end

        -- Fuzzy match if exact didn't find it
        if not isLocked and instanceName then
            local lowerInst = instanceName:lower()
            for _, lockout in pairs(charLockouts) do
                if lockout.locked and lockout.resetTime and lockout.resetTime > time() then
                    local lockName = (lockout.name or ""):lower()
                    if lockName ~= "" and (lockName:find(lowerInst, 1, true) or lowerInst:find(lockName, 1, true)) then
                        isLocked = true
                        break
                    end
                end
            end
        end

        if isLocked then
            locked[#locked + 1] = charKey
        else
            available[#available + 1] = charKey
        end
    end

    return (#available == 0), available, locked
end

-- Find the "best alt" for farming a specific instance
-- Returns the charKey with fewest total lockouts (most free to farm)
-- Optionally filters by faction if the mount is faction-specific
function FB.CharacterData:GetBestAltForInstance(instanceName, difficultyID, requiredFaction)
    if not FB.db or not FB.db.characters then return nil end

    local _, available = self:GetWarbandLockoutStatus(instanceName, difficultyID)
    if #available == 0 then return nil end

    local best = nil
    local bestScore = 999

    for _, charKey in ipairs(available) do
        local charInfo = FB.db.characters[charKey]
        if charInfo then
            -- Check faction requirement
            local factionOk = true
            if requiredFaction then
                local charFaction = charInfo.faction
                if charFaction and charFaction ~= requiredFaction and charFaction ~= "Neutral" then
                    factionOk = false
                end
            end

            if factionOk then
                -- Count active lockouts for this character
                local lockoutCount = 0
                local lockouts = charInfo.lockouts or {}
                for _, lockout in pairs(lockouts) do
                    if lockout.locked and lockout.resetTime and lockout.resetTime > time() then
                        lockoutCount = lockoutCount + 1
                    end
                end

                -- Prefer current character if tied
                local score = lockoutCount
                if charKey == FB.playerKey then
                    score = score - 0.1
                end

                if score < bestScore then
                    bestScore = score
                    best = charKey
                end
            end
        end
    end

    return best
end

-- Get a summary of warband farming capacity
function FB.CharacterData:GetWarbandSummary()
    if not FB.db or not FB.db.characters then
        return { totalChars = 0, totalLockouts = 0 }
    end

    local totalChars = 0
    local totalLockouts = 0

    for _, charInfo in pairs(FB.db.characters) do
        totalChars = totalChars + 1
        local lockouts = charInfo.lockouts or {}
        for _, lockout in pairs(lockouts) do
            if lockout.locked and lockout.resetTime and lockout.resetTime > time() then
                totalLockouts = totalLockouts + 1
            end
        end
    end

    return {
        totalChars = totalChars,
        totalLockouts = totalLockouts,
    }
end

-- Record mount attempt timestamps for staleness tracking (#6)
-- Called when lockouts change: any mount associated with the newly-locked instances
-- gets its "lastAttempt" timestamp updated in the account-wide DB.
function FB.CharacterData:RecordMountAttempts()
    if not FB.db or not FB.charDB or not FB.charDB.lockouts then return end
    if not FB.db.mountAttempts then FB.db.mountAttempts = {} end
    if not FB.MountDB or not FB.MountDB.entries then return end

    local now = time()

    -- For each active lockout, find mounts in MountDB that reference that instance
    for _, lockout in pairs(FB.charDB.lockouts) do
        if lockout.locked and lockout.name then
            local lockName = lockout.name:lower()
            for spellID, meta in pairs(FB.MountDB.entries) do
                if meta.lockoutInstanceName then
                    local metaInst = meta.lockoutInstanceName:lower()
                    if metaInst == lockName or lockName:find(metaInst, 1, true) or metaInst:find(lockName, 1, true) then
                        FB.db.mountAttempts[spellID] = now
                    end
                end
            end
        end
    end
end

-- Expire old lockout entries that have passed their reset time
function FB.CharacterData:CleanExpiredLockouts()
    if not FB.db or not FB.db.characters then return end
    local now = time()
    for _, charInfo in pairs(FB.db.characters) do
        local lockouts = charInfo.lockouts
        if lockouts then
            for key, lockout in pairs(lockouts) do
                if lockout.resetTime and lockout.resetTime <= now then
                    lockouts[key] = nil
                end
            end
        end
    end
end
