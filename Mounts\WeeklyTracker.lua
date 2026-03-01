local addonName, FB = ...

FB.WeeklyTracker = {}

-- Cache of spellID -> mountID lookups (expensive to compute)
local mountIDCache = {}

-- Extract a useful location label from Blizzard's sourceText
-- Handles many formats: "Drop: Instance", "Dropped by Boss", plain text, etc.
local function ParseSourceLabel(sourceText)
    if not sourceText or sourceText == "" then return nil end
    -- Try to extract after common prefixes
    local label = sourceText:match("^Drop:%s*(.+)")
        or sourceText:match("^Dropped by:%s*(.+)")
        or sourceText:match("^Contained in:%s*(.+)")
        or sourceText:match("^Reward from:%s*(.+)")
    -- Fall back to raw text, but skip obviously non-instance strings
    if not label then
        local lower = sourceText:lower()
        if lower:find("promotion") or lower:find("trading post")
           or lower:find("blizzard shop") or lower:find("no longer") then
            return nil
        end
        label = sourceText
    end
    return label
end

-- Populate lockout data for an entry across all known characters
local function PopulateLockouts(entry)
    if not FB.db or not FB.db.characters then return end
    for charKey, charInfo in pairs(FB.db.characters) do
        local lockouts = charInfo.lockouts or {}
        local found = false

        -- Exact key match (curated mounts with known difficultyID)
        if entry.instanceName then
            local lockoutKey = entry.instanceName .. "-" .. (entry.difficultyID or 0)
            local lockout = lockouts[lockoutKey]
            if lockout and lockout.locked and lockout.resetTime and lockout.resetTime > time() then
                entry.characters[charKey] = {
                    locked = true,
                    resetTime = lockout.resetTime,
                    class = charInfo.class,
                }
                found = true
            end
        end

        -- Fuzzy match: any lockout whose name contains our instance name
        if not found and entry.instanceName then
            local lowerInst = entry.instanceName:lower()
            for _, lockout in pairs(lockouts) do
                if lockout.locked and lockout.resetTime and lockout.resetTime > time() then
                    local lockName = (lockout.name or ""):lower()
                    if lockName ~= "" and (lockName:find(lowerInst, 1, true) or lowerInst:find(lockName, 1, true)) then
                        entry.characters[charKey] = {
                            locked = true,
                            resetTime = lockout.resetTime,
                            class = charInfo.class,
                        }
                        found = true
                        break
                    end
                end
            end
        end

        if not found then
            entry.characters[charKey] = {
                locked = false,
                class = charInfo.class,
            }
        end
    end
end

-- Get a structured list of weekly-farmable mounts and their lockout status per character
-- Combines curated MountDB entries with ALL uncollected raid/dungeon mounts from Blizzard API
-- Returns: { { mountName, instanceName, difficultyID, characters = { [charKey] = locked } }, ... }
function FB.WeeklyTracker:GetWeeklyMounts()
    local weeklyMounts = {}
    local seenSpells = {}

    -- Phase 1: Curated mounts from MountDB (most accurate metadata)
    if FB.MountDB and FB.MountDB.entries then
        for spellID, meta in pairs(FB.MountDB.entries) do
            if meta.timeGate == "weekly" and meta.lockoutInstanceName then
                local mountID = self:FindMountIDBySpellID(spellID)
                if mountID then
                    local ok, name, _, icon, _, _, _, _, _, _, _, isCollected =
                        pcall(C_MountJournal.GetMountInfoByID, mountID)

                    if ok and name and not isCollected then
                        seenSpells[spellID] = true
                        local entry = {
                            spellID = spellID,
                            name = name,
                            icon = icon,
                            instanceName = meta.lockoutInstanceName,
                            difficultyID = meta.difficultyID,
                            expansion = meta.expansion,
                            dropChance = meta.dropChance,
                            characters = {},
                        }
                        PopulateLockouts(entry)
                        weeklyMounts[#weeklyMounts + 1] = entry
                    end
                end
            end
        end
    end

    -- Phase 2: Scan ALL uncollected mounts from Blizzard API
    -- Include raid/dungeon drops (sourceType 1=Drop, 5=Instance) not already curated
    local allMountIDs = C_MountJournal.GetMountIDs()
    if allMountIDs then
        for _, mountID in ipairs(allMountIDs) do
            local ok, name, spellID, icon, _, _, sourceType, _, _, _, _, isCollected =
                pcall(C_MountJournal.GetMountInfoByID, mountID)

            if ok and spellID and not isCollected and not seenSpells[spellID] then
                -- sourceType 1 = Drop (raid/dungeon), 5 = Instance
                if sourceType == 1 or sourceType == 5 then
                    local extraOk, _, _, sourceText = pcall(C_MountJournal.GetMountInfoExtraByID, mountID)
                    local instanceName = extraOk and ParseSourceLabel(sourceText)

                    if instanceName then
                        seenSpells[spellID] = true
                        -- Try to guess expansion and source type from source text
                        local _, descText = nil, nil
                        if extraOk then
                            descText = select(2, pcall(C_MountJournal.GetMountInfoExtraByID, mountID))
                        end
                        local guessedExpansion = FB.Mounts.Resolver and FB.Mounts.Resolver.GuessExpansion
                            and FB.Mounts.Resolver:GuessExpansion(sourceText, descText) or nil
                        -- Blizzard sourceType 1=Drop (usually raid), 5=Instance (dungeon/raid)
                        local guessedSourceType = (sourceType == 5) and "dungeon_drop" or "raid_drop"
                        local entry = {
                            spellID = spellID,
                            name = name,
                            icon = icon,
                            instanceName = instanceName,
                            difficultyID = nil,
                            expansion = guessedExpansion,
                            dropChance = 0.01,
                            blizzSourceType = sourceType,
                            guessedSourceType = guessedSourceType,
                            characters = {},
                        }
                        PopulateLockouts(entry)
                        weeklyMounts[#weeklyMounts + 1] = entry
                    end
                end
            end
        end
    end

    -- Sort by instance name, then mount name
    table.sort(weeklyMounts, function(a, b)
        local instA = a.instanceName or ""
        local instB = b.instanceName or ""
        if instA ~= instB then return instA < instB end
        return (a.name or "") < (b.name or "")
    end)

    return weeklyMounts
end

-- Find a mountID (for C_MountJournal) by spellID
-- Returns mountID or nil if not found
function FB.WeeklyTracker:FindMountIDBySpellID(spellID)
    -- Check cache first
    if mountIDCache[spellID] then
        return mountIDCache[spellID]
    end

    local mountIDs = C_MountJournal.GetMountIDs()
    if not mountIDs then return nil end

    for _, mountID in ipairs(mountIDs) do
        local ok, _, spell = pcall(C_MountJournal.GetMountInfoByID, mountID)
        if ok and spell == spellID then
            mountIDCache[spellID] = mountID
            return mountID
        end
    end

    return nil  -- Not found in mount journal
end

-- Get sorted list of character keys
function FB.WeeklyTracker:GetCharacterList()
    if not FB.db or not FB.db.characters then return {} end

    local chars = {}
    for charKey, info in pairs(FB.db.characters) do
        chars[#chars + 1] = {
            key = charKey,
            class = info.class,
            level = info.level,
            lastSeen = info.lastSeen,
        }
    end

    -- Sort: current character first, then by last seen
    table.sort(chars, function(a, b)
        if a.key == FB.playerKey then return true end
        if b.key == FB.playerKey then return false end
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)

    return chars
end
