local addonName, FB = ...

FB.Mounts = FB.Mounts or {}
FB.Mounts.Resolver = {}

local C_MountJournal = C_MountJournal

-- Blizzard's numeric sourceType values from GetMountInfoByID
-- Maps to our internal source type strings
local BLIZZ_SOURCE = {
    [0] = "unknown",       -- None / Unknown
    [1] = "raid_drop",     -- Drop (instances) -- could be dungeon or raid
    [2] = "quest_chain",   -- Quest
    [3] = "vendor",        -- Vendor
    [4] = "profession",    -- Profession
    [5] = "dungeon_drop",  -- Instance (often dungeon/raid loot)
    [6] = "achievement",   -- Achievement
    [7] = "event",         -- World Event
    [8] = "promotion",     -- Promotion (store, collectors, TCG)
    [9] = "pvp",           -- PvP
    [10] = "unknown",      -- Pet Battle
    [11] = "world_drop",   -- Discovery (rare spawn, treasures)
    [12] = "trading_post", -- Trading Post (bought with Trader's Tender, rotates monthly)
}

-- Reverse lookup: standing name → standing ID (for parsing sourceText)
local STANDING_NAME_TO_ID = {
    hated = 1, hostile = 2, unfriendly = 3, neutral = 4,
    friendly = 5, honored = 6, revered = 7, exalted = 8,
}

--[[
    Parse reputation requirement from mount sourceText.
    Handles patterns like:
      "Requires Exalted with Voldunai"
      "Sold by Tansa. Requires Revered with The Saberstalkers"
      "Exalted with Order of the Cloud Serpent"
      "Requires Renown 12 with Assembly of the Deeps"
      "Renown 25 with Council of Dornogal"
    @return factionName (string), standingID (number), renownLevel (number or nil)
--]]
function FB.Mounts.Resolver:ParseReputationFromText(sourceText)
    if not sourceText then return nil, nil, nil end

    -- Strip WoW UI color codes for cleaner parsing: |cFFXXXXXX...|r
    local clean = sourceText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    -- Strip texture/icon tags: |T...|t
    clean = clean:gsub("|T[^|]*|t", "")
    -- Strip hyperlinks but keep display text: |H...|h[text]|h -> [text]
    clean = clean:gsub("|H[^|]*|h", ""):gsub("|h", "")
    -- Normalize newlines: |n -> newline
    clean = clean:gsub("|n", "\n")

    local lower = clean:lower()

    -- =========================================================================
    -- Format 1: In-game structured sourceText
    -- "Faction: <FactionName> - <Standing>" (with optional color codes stripped)
    -- "Renown: <Level>" on a separate line
    -- =========================================================================

    -- Extract faction name and standing from "Faction: X - Exalted" format
    local factionLine = clean:match("[Ff]action:%s*(.-)[\n|]") or clean:match("[Ff]action:%s*(.-)$")
    if factionLine then
        factionLine = factionLine:match("^%s*(.-)%s*$")  -- trim
        -- Try "<FactionName> - <Standing>" pattern
        local factionName, standingStr = factionLine:match("^(.-)%s*%-%s*(.+)$")
        if factionName and standingStr then
            factionName = factionName:match("^%s*(.-)%s*$")
            standingStr = standingStr:match("^%s*(.-)%s*$")
            local standingID = STANDING_NAME_TO_ID[standingStr:lower()]

            -- Check for Renown line (separate from Faction line in structured text)
            local renownLevel = clean:match("[Rr]enown:%s*(%d+)")
            if renownLevel then
                renownLevel = tonumber(renownLevel)
                return factionName, standingID or 8, renownLevel
            end

            if standingID and #factionName > 0 then
                return factionName, standingID, nil
            end
        end
    end

    -- =========================================================================
    -- Format 2: "Renown X with <Faction>" (WoWHead / curated / some in-game text)
    -- =========================================================================
    local renownLevel, renownFaction = lower:match("renown (%d+) with (.+)")
    if renownLevel and renownFaction then
        renownLevel = tonumber(renownLevel)
        renownFaction = renownFaction:match("^(.-)%s*[%.;,\n]") or renownFaction
        renownFaction = renownFaction:match("^(.-)%s*$")

        -- Preserve original casing from clean text
        local _, startPos = lower:find("renown %d+ with ")
        if startPos then
            local originalFaction = clean:sub(startPos + 1)
            originalFaction = originalFaction:match("^(.-)%s*[%.;,\n]") or originalFaction
            originalFaction = originalFaction:match("^(.-)%s*$")
            if originalFaction and #originalFaction > 0 then
                return originalFaction, 8, renownLevel
            end
        end

        if #renownFaction > 0 then
            return renownFaction, 8, renownLevel
        end
    end

    -- =========================================================================
    -- Format 3: "<Standing> with <Faction>" (WoWHead / curated text)
    -- =========================================================================
    for standingName, standingID in pairs(STANDING_NAME_TO_ID) do
        local pattern = standingName .. " with (.+)"
        local factionMatch = lower:match(pattern)
        if factionMatch then
            factionMatch = factionMatch:match("^(.-)%s*[%.;,\n]") or factionMatch
            factionMatch = factionMatch:match("^(.-)%s*$")

            local _, startPos = lower:find(standingName .. " with ")
            if startPos then
                local originalFaction = clean:sub(startPos + 1)
                originalFaction = originalFaction:match("^(.-)%s*[%.;,\n]") or originalFaction
                originalFaction = originalFaction:match("^(.-)%s*$")
                if originalFaction and #originalFaction > 0 then
                    return originalFaction, standingID, nil
                end
            end

            if #factionMatch > 0 then
                return factionMatch, standingID, nil
            end
        end
    end

    return nil, nil, nil
end

--[[
    Parse currency requirement from mount sourceText.

    In-game sourceText uses WoW UI markup for currencies:
      "5,000|Hcurrency:823|h|TInterface\Icons\...:0|tTimewarped Badge|h"
      "150|Hcurrency:1885|h|TInterface\Icons\...:0|tPolished Pet Charm|h"
    The currency ID is embedded directly in the |Hcurrency:NNN|h hyperlink.

    Also handles clean/wowhead-style text:
      "Sold by Trev for 5,000 Timewarped Badges"
      "Costs 150 Polished Pet Charms"
      "Purchased with 300 Curious Coins"

    @return currencyName (string), amount (number), currencyID (number or nil)
--]]
function FB.Mounts.Resolver:ParseCurrencyFromText(sourceText)
    if not sourceText then return nil, nil, nil end

    -- =========================================================================
    -- Format 1: WoW UI hyperlink markup — currency ID embedded directly
    -- Pattern: "<amount>|Hcurrency:<ID>|h|T...|t<CurrencyName>|h"
    -- or:      "<amount> |Hcurrency:<ID>|h..."
    -- =========================================================================
    local amount1, currencyID1 = sourceText:match("([%d,]+)%s*|Hcurrency:(%d+)|h")
    if currencyID1 then
        local cid = tonumber(currencyID1)
        local amount = tonumber((amount1 or ""):gsub(",", ""))
        if cid and cid > 0 then
            -- Get the proper currency name from WoW API
            local cName = nil
            if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, cid)
                if ok and info and info.name then
                    cName = info.name
                end
            end
            return cName or ("Currency " .. cid), amount or 0, cid
        end
    end

    -- Also check for |Hcurrency:ID|h anywhere without a leading amount
    -- (amount might be on a separate line or structured differently)
    local currencyID2 = sourceText:match("|Hcurrency:(%d+)|h")
    if currencyID2 then
        local cid = tonumber(currencyID2)
        if cid and cid > 0 then
            -- Try to find an amount near the hyperlink
            -- Look for a number before or after the hyperlink on the same line
            local amount = nil
            -- Check for number immediately before: "5,000|Hcurrency:..."
            local preAmount = sourceText:match("([%d,]+)%s*|Hcurrency:" .. currencyID2)
            if preAmount then
                amount = tonumber(preAmount:gsub(",", ""))
            end
            -- Check for number after the hyperlink display text
            if not amount then
                local postAmount = sourceText:match("|Hcurrency:" .. currencyID2 .. "[^|]*|h[^%d]*([%d,]+)")
                if postAmount then
                    amount = tonumber(postAmount:gsub(",", ""))
                end
            end

            local cName = nil
            if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, cid)
                if ok and info and info.name then
                    cName = info.name
                end
            end
            return cName or ("Currency " .. cid), amount or 0, cid
        end
    end

    -- =========================================================================
    -- Format 2: Clean text (wowhead, curated, or stripped sourceText)
    -- "<number> <currency name>"
    -- =========================================================================
    -- Strip WoW markup first for clean matching
    local clean = sourceText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    clean = clean:gsub("|T[^|]*|t", "")
    clean = clean:gsub("|H[^|]*|h", ""):gsub("|h", "")
    clean = clean:gsub("|n", " ")
    clean = clean:match("^%s*(.-)%s*$") or clean

    local patterns = {
        "for ([%d,]+)%s+(.+)",           -- "for 5,000 Timewarped Badges"
        "costs? ([%d,]+)%s+(.+)",         -- "Costs 150 Polished Pet Charms"
        "with ([%d,]+)%s+(.+)",           -- "Purchased with 300 Curious Coins"
        "requires? ([%d,]+)%s+(.+)",      -- "Requires 2000 Valor"
        "([%d,]+)%s+(.+)",               -- Bare "5000 Garrison Resources" (last resort)
    }

    for _, pattern in ipairs(patterns) do
        local amountStr, currencyName = clean:match(pattern)
        if amountStr and currencyName then
            local amount = tonumber(amountStr:gsub(",", ""))
            if amount and amount > 0 then
                -- Clean up currency name: trim trailing punctuation and whitespace
                currencyName = currencyName:match("^(.-)%s*[%.;,]") or currencyName
                currencyName = currencyName:match("^(.-)%s*$")

                -- Filter out non-currency matches (gold amounts, etc.)
                local lowerCurrency = currencyName:lower()
                if lowerCurrency ~= "gold" and lowerCurrency ~= "silver"
                   and lowerCurrency ~= "copper" and #currencyName > 2 then
                    return currencyName, amount, nil
                end
            end
        end
    end

    return nil, nil, nil
end

-- Cached currency name → ID lookup (built once per session, lazy)
local currencyNameCache = nil

-- Build comprehensive currency name → ID cache by scanning known currency ID ranges
local function BuildCurrencyNameCache()
    if currencyNameCache then return currencyNameCache end
    currencyNameCache = {}

    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then
        return currencyNameCache
    end

    -- WoW currency IDs range roughly from 1 to ~3000
    -- Scan broadly to catch all currencies
    for cid = 1, 3000 do
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, cid)
        if ok and info and info.name and info.name ~= "" then
            currencyNameCache[info.name:lower()] = cid
        end
    end

    return currencyNameCache
end

--[[
    Look up a currency ID by name using a cached name→ID map.
    @param currencyName  string - The currency name to search for
    @return currencyID (number) or nil
--]]
function FB.Mounts.Resolver:FindCurrencyIDByName(currencyName)
    if not currencyName or currencyName == "" then return nil end

    local cache = BuildCurrencyNameCache()
    local searchName = currencyName:lower()

    -- Direct exact match
    if cache[searchName] then
        return cache[searchName]
    end

    -- Substring match (handles slight name variations, plurals, etc.)
    -- Require both names to be at least 5 characters to avoid false positives
    -- (e.g., "Honor" matching inside "Ancient Honor Token")
    if #searchName >= 5 then
        for cachedName, cachedID in pairs(cache) do
            if #cachedName >= 5 then
                if cachedName:find(searchName, 1, true) or searchName:find(cachedName, 1, true) then
                    return cachedID
                end
            end
        end
    end

    return nil
end

--[[
    Try to find an achievement ID for a mount.
    Uses multiple strategies:
      1. Parse achievement name from sourceText ("Achievement: Glory of the Raider")
      2. Scan known achievement ID ranges looking for a name match

    @param mountID     number  - mountID for API lookups
    @param sourceText  string  - Blizzard's source text for the mount
    @return achievementID (number) or nil
--]]
-- Cached achievement name → ID map (built once, lazy)
local achievementNameCache = nil

local function BuildAchievementNameCache()
    if achievementNameCache then return achievementNameCache end
    achievementNameCache = {}

    if not GetAchievementInfo then return achievementNameCache end

    -- Achievement IDs span a very wide range. Focus on categories most likely
    -- to reward mounts: raid meta-achievements, dungeon meta-achievements, etc.
    -- Scan ranges where mount-rewarding achievements are concentrated.
    local ACHIEVEMENT_RANGES = {
        { 1, 2000 },      -- Classic through WotLK (Glory of the Raider, etc.)
        { 4500, 7500 },   -- Cata through MoP
        { 8000, 12000 },  -- WoD through Legion
        { 12000, 16000 }, -- BFA through Shadowlands
        { 16000, 22000 }, -- Dragonflight through TWW
    }

    for _, range in ipairs(ACHIEVEMENT_RANGES) do
        for aid = range[1], range[2] do
            local ok, name = pcall(GetAchievementInfo, aid)
            if ok and name and name ~= "" then
                achievementNameCache[name:lower()] = aid
            end
        end
    end

    return achievementNameCache
end

function FB.Mounts.Resolver:FindAchievementIDForMount(mountID, sourceText)
    if not sourceText then return nil end

    -- Parse achievement name from sourceText
    -- Common patterns: "Achievement: Glory of the Raider", "Reward from Glory of the Hero"
    local achieveName = sourceText:match("[Aa]chievement:?%s*(.+)")
                     or sourceText:match("[Rr]eward from (.+)")
                     or sourceText:match("[Gg]lory of .+")

    if not achieveName then return nil end

    -- Clean up
    achieveName = achieveName:match("^(.-)%s*[%.;,]") or achieveName
    achieveName = achieveName:match("^(.-)%s*$")

    if not achieveName or #achieveName < 3 then return nil end

    local cache = BuildAchievementNameCache()
    local searchName = achieveName:lower()

    -- Direct match
    if cache[searchName] then
        return cache[searchName]
    end

    -- Substring match
    for cachedName, cachedID in pairs(cache) do
        if cachedName:find(searchName, 1, true) or searchName:find(cachedName, 1, true) then
            return cachedID
        end
    end

    return nil
end

-- Faction name → ID caches (built once per session, lazy)
local playerFactionCache = nil   -- From player's known faction list (fast, incomplete)
local globalFactionCache = nil   -- From brute-force ID scan (slow, comprehensive)

-- Known WoW faction ID ranges to scan. Covers all expansions through TWW.
-- Faction IDs are not contiguous; we scan broad ranges and skip gaps.
local FACTION_ID_RANGES = {
    { 1,    800  },   -- Classic / TBC factions
    { 900,  1200 },   -- WotLK / Cata factions
    { 1200, 1600 },   -- MoP / WoD factions
    { 1700, 2200 },   -- Legion / BFA factions
    { 2300, 2600 },   -- Shadowlands factions
    { 2600, 2950 },   -- Dragonflight / TWW factions
}

-- Build cache from player's discovered factions (fast — only factions visible in rep panel)
local function BuildPlayerFactionCache()
    if playerFactionCache then return playerFactionCache end
    playerFactionCache = {}

    -- Try modern API first (C_Reputation)
    if C_Reputation and C_Reputation.GetNumFactions then
        local ok, numFactions = pcall(C_Reputation.GetNumFactions)
        if ok and numFactions then
            for i = 1, numFactions do
                local fOk, fData = pcall(C_Reputation.GetFactionDataByIndex, i)
                if fOk and fData and fData.name and fData.factionID then
                    playerFactionCache[fData.name:lower()] = fData.factionID
                end
            end
        end
    end

    -- Also try legacy API for completeness
    if GetNumFactions and GetFactionInfo then
        local ok, numFactions = pcall(GetNumFactions)
        if ok and numFactions then
            for i = 1, numFactions do
                local fOk, name, _, _, _, _, _, _, _, _, _, _, _, factionID =
                    pcall(GetFactionInfo, i)
                if fOk and name and factionID then
                    local key = name:lower()
                    if not playerFactionCache[key] then
                        playerFactionCache[key] = factionID
                    end
                end
            end
        end
    end

    return playerFactionCache
end

-- Build comprehensive cache by scanning all known faction ID ranges (slow, thorough)
-- Uses C_Reputation.GetFactionDataByID which works for ANY faction, even undiscovered ones
local function BuildGlobalFactionCache()
    if globalFactionCache then return globalFactionCache end
    globalFactionCache = {}

    if not (C_Reputation and C_Reputation.GetFactionDataByID) then
        -- Modern API not available, try legacy GetFactionInfoByID as fallback
        if GetFactionInfoByID then
            for _, range in ipairs(FACTION_ID_RANGES) do
                for fid = range[1], range[2] do
                    local ok, name = pcall(GetFactionInfoByID, fid)
                    if ok and name and name ~= "" then
                        globalFactionCache[name:lower()] = fid
                    end
                end
            end
        end
        return globalFactionCache
    end

    for _, range in ipairs(FACTION_ID_RANGES) do
        for fid = range[1], range[2] do
            local ok, data = pcall(C_Reputation.GetFactionDataByID, fid)
            if ok and data and data.name and data.name ~= "" then
                globalFactionCache[data.name:lower()] = fid
            end
        end
    end

    return globalFactionCache
end

-- Search a cache table for a faction name with fuzzy matching
-- @param cache      table   - { [lowerName] = factionID }
-- @param searchName string  - lowercase faction name to find
-- @return factionID or nil
local function SearchCacheForFaction(cache, searchName)
    -- Direct exact match
    if cache[searchName] then
        return cache[searchName]
    end

    -- Try with/without "the " prefix
    if searchName:sub(1, 4) == "the " then
        local withoutThe = searchName:sub(5)
        if cache[withoutThe] then return cache[withoutThe] end
    else
        local withThe = "the " .. searchName
        if cache[withThe] then return cache[withThe] end
    end

    -- Substring match (handles "Voldunai" matching "Voldunai Reputation" or vice versa)
    -- Require both names to be at least 5 characters to avoid false positives
    if #searchName >= 5 then
        for cachedName, cachedID in pairs(cache) do
            if #cachedName >= 5 and (cachedName:find(searchName, 1, true) or searchName:find(cachedName, 1, true)) then
                return cachedID
            end
        end
    end

    return nil
end

--[[
    Look up a faction ID by name. Uses two-tier caching for accuracy:
      1. Fast lookup from player's discovered faction list
      2. Thorough brute-force scan of all WoW faction IDs (covers undiscovered factions)

    @param factionName  string - The faction name to search for
    @return factionID (number) or nil
--]]
function FB.Mounts.Resolver:FindFactionIDByName(factionName)
    if not factionName or factionName == "" then return nil end

    local searchName = factionName:lower()

    -- Tier 1: Check player's known faction list (instant)
    local playerCache = BuildPlayerFactionCache()
    local result = SearchCacheForFaction(playerCache, searchName)
    if result then return result end

    -- Tier 2: Full brute-force scan of all faction IDs (slow first time, cached after)
    -- This finds factions the player hasn't discovered yet
    local globalCache = BuildGlobalFactionCache()
    result = SearchCacheForFaction(globalCache, searchName)
    if result then return result end

    return nil
end

-- Invalidate all lookup caches (call on major game state changes)
function FB.Mounts.Resolver:InvalidateCaches()
    playerFactionCache = nil
    globalFactionCache = nil
    currencyNameCache = nil
    achievementNameCache = nil
end

-- Backwards compatibility alias
function FB.Mounts.Resolver:InvalidateFactionCache()
    self:InvalidateCaches()
end

--[[
    Detect if a mount is unobtainable based on multiple signals.
    Returns true if the mount should be excluded from recommendations.
--]]
function FB.Mounts.Resolver:IsUnobtainable(sourceType, sourceText, hideOnChar, name)
    -- Blizzard sourceType 11 = In-Game Store (real-money only)
    if sourceType == 11 then
        return true
    end

    local lower = sourceText and sourceText:lower() or ""
    local lowerName = name and name:lower() or ""

    -- Blizzard Shop / In-Game Store keyword detection
    if lower:find("blizzard shop") or lower:find("blizzard store")
       or lower:find("in%-game shop") or lower:find("in%-game store") then
        return true
    end

    -- Black Market Auction House only mounts (no deterministic farm path)
    if lower:find("black market") then
        return true
    end

    -- Removed / no longer obtainable keywords
    if lower:find("no longer") or lower:find("removed")
       or lower:find("unavailable") or lower:find("unobtainable") then
        return true
    end

    -- Past PvP seasonal rewards (Gladiator mounts from previous seasons)
    -- These have sourceType 9 (PvP) and contain specific season/expansion references
    -- Current season gladiator mounts are still obtainable
    if sourceType == 9 then
        -- Check for "Gladiator" mounts from specific past seasons
        if lowerName:find("gladiator") or lowerName:find("challenger") then
            -- Past season gladiator mounts reference old expansion names
            local pastExpansionKeywords = {
                "combatant", "season 1", "season 2", "season 3", "season 4",
                "vicious", "sinful", "unchained", "cosmic",  -- SL
                "corrupted", "notorious", "mindless",  -- BFA
                "demonic", "fearless", "fierce", "dominant", "cruel",  -- Legion
                "warmongering", "wild",  -- WoD
                "grievous", "prideful", "tyrannical",  -- MoP
                "cataclysmic", "ruthless",  -- Cata
                "wrathful", "relentless", "furious", "deadly",  -- WotLK
                "brutal", "vengeful", "merciless",  -- TBC
            }
            for _, keyword in ipairs(pastExpansionKeywords) do
                if lowerName:find(keyword) then
                    return true
                end
            end
        end
    end

    -- Collector's Edition / Deluxe Edition mounts
    if lower:find("collector") or lower:find("deluxe edition")
       or lower:find("epic edition") then
        return true
    end

    -- Recruit-A-Friend: NOT blocked — the program is periodically active
    -- These will flow through to scoring as "recruit_a_friend" source type

    -- WoW Anniversary / limited-time promotional
    if lower:find("anniversary gift") then
        return true
    end

    -- Remix events (MoP Remix, Legion Remix, etc.) — limited-time seasonal events
    if lower:find("remix") or lowerName:find("remix") then
        return true
    end

    -- Timerunning (the mechanic behind Remix events)
    if lower:find("timerunning") or lower:find("time running") then
        return true
    end

    return false
end

--[[
    Detect ALL requirements from sourceText and enrich the input with live progress.
    Checks reputation, currency, gold, and achievement independently — a mount can
    have multiple requirements (e.g., "Exalted with X" + "costs 5000 gold").

    The combined progressRemaining is the WORST (max) of all detected requirements,
    because the player must satisfy ALL of them to obtain the mount.

    @param input       table   - The scoring input being built (mutated in place)
    @param sourceText  string  - Blizzard's source description text
    @param skipTypes   table   - Optional set of types to skip (e.g., {reputation=true} if already resolved)
    @return progressValues table - { rep=N, currency=N, gold=N, achievement=N } for debugging
--]]
function FB.Mounts.Resolver:EnrichFromSourceText(input, sourceText, skipTypes)
    if not sourceText or sourceText == "" then return {} end
    skipTypes = skipTypes or {}

    local progressValues = {}

    -- 1. Reputation detection
    if not skipTypes.reputation and not input.factionID then
        local factionName, standingID, renownLevel = self:ParseReputationFromText(sourceText)
        if factionName then
            local factionID = self:FindFactionIDByName(factionName)
            if factionID then
                input.factionID = factionID
                input.targetStanding = standingID
                input.targetRenown = renownLevel
                progressValues.rep = FB.ProgressResolver:GetRepProgress(
                    factionID, standingID, renownLevel
                )
            end
        end
    elseif input.factionID then
        -- Already has faction data — get live progress if not yet resolved
        if not progressValues.rep then
            progressValues.rep = FB.ProgressResolver:GetRepProgress(
                input.factionID, input.targetStanding, input.targetRenown
            )
        end
    end

    -- 2. Currency detection
    if not skipTypes.currency and not input.currencyID then
        local currencyName, requiredAmount, directCurrencyID = self:ParseCurrencyFromText(sourceText)
        if currencyName then
            -- Use direct ID from hyperlink if available, otherwise name lookup
            local currencyID = directCurrencyID or self:FindCurrencyIDByName(currencyName)
            if currencyID then
                input.currencyID = currencyID
                input.currencyRequired = requiredAmount
                progressValues.currency = FB.ProgressResolver:GetCurrencyProgress(
                    currencyID, requiredAmount
                )
            end
        end
    elseif input.currencyID then
        progressValues.currency = FB.ProgressResolver:GetCurrencyProgress(
            input.currencyID, input.currencyRequired
        )
    end

    -- 3. Gold detection
    if not skipTypes.gold and not input.goldCost then
        local goldCost = FB.ProgressResolver:ParseGoldCost(sourceText)
        if goldCost then
            input.goldCost = goldCost
            progressValues.gold = FB.ProgressResolver:GetGoldProgress(goldCost)
        end
    elseif input.goldCost then
        progressValues.gold = FB.ProgressResolver:GetGoldProgress(input.goldCost)
    end

    -- 4. Item cost detection (|Hitem:NNN|h hyperlinks — event tokens, crafting materials)
    -- We store these for display; progress is not automatically trackable for items
    if not skipTypes.item and not input.itemCosts then
        local items = {}
        for amount, itemID in sourceText:gmatch("([%d,]+)%s*|Hitem:(%d+)|h") do
            local iid = tonumber(itemID)
            local amt = tonumber((amount or ""):gsub(",", "")) or 1
            if iid and iid > 0 then
                items[#items + 1] = { itemID = iid, amount = amt }
            end
        end
        if #items > 0 then
            input.itemCosts = items
        end
    end

    -- 5. Achievement detection (only for achievement-type mounts without an ID yet)
    -- Skip this for non-achievement mounts since achievement text is rarer in sourceText
    if not skipTypes.achievement and not input.achievementID
       and (input.sourceType == "achievement" or not input.sourceType) then
        local achievementID = self:FindAchievementIDForMount(input.mountID, sourceText)
        if achievementID then
            input.achievementID = achievementID
            progressValues.achievement = FB.ProgressResolver:GetAchievementProgress(
                achievementID
            )
        end
    elseif input.achievementID then
        progressValues.achievement = FB.ProgressResolver:GetAchievementProgress(
            input.achievementID
        )
    end

    -- Combined progress: worst (max) of all detected requirements
    -- The player must satisfy ALL requirements to get the mount
    -- Start from existing progressRemaining (e.g., quest chain already resolved)
    local worstProgress = input.progressRemaining
    for _, prog in pairs(progressValues) do
        if prog and (not worstProgress or prog > worstProgress) then
            worstProgress = prog
        end
    end

    if worstProgress then
        input.progressRemaining = worstProgress
    end

    return progressValues
end

--[[
    Resolve a mount into a ScoringInput table.
    Combines static metadata from MountDB with live API data.

    @param mountIndex  number  - mountID from C_MountJournal
    @return ScoringInput table or nil if mount should be skipped
--]]
function FB.Mounts.Resolver:Resolve(mountIndex)
    local name, spellID, icon, isActive, isUsable, sourceType, isFavorite,
          isFactionSpecific, faction, hideOnChar, isCollected, mountID =
          C_MountJournal.GetMountInfoByID(mountIndex)

    if not spellID then return nil end
    if isCollected then return nil end  -- Skip collected mounts

    -- Get extra info
    local creatureDisplayID, descriptionText, sourceText, isSelfMount, mountTypeID =
          C_MountJournal.GetMountInfoExtraByID(mountIndex)

    -- Check if mount is unobtainable
    if self:IsUnobtainable(sourceType, sourceText, hideOnChar, name) then
        return nil
    end

    -- Look up in our curated database (highest priority)
    local meta = FB.MountDB:Get(spellID)

    -- Look up in generated database (second priority, from build_mountdb.py)
    local generatedMeta = FB.MountDB_Generated and FB.MountDB_Generated[spellID]
    if not meta then
        meta = generatedMeta
    end

    -- Build scoring input
    local input = {
        id = spellID,
        mountID = mountIndex,
        name = name or "Unknown",
        icon = icon,
        sourceText = sourceText or "",
        creatureDisplayID = creatureDisplayID,
        isCollected = false,
        blizzSourceType = sourceType,  -- Keep numeric for reference
        isFactionSpecific = isFactionSpecific,
        faction = (isFactionSpecific and faction) or (generatedMeta and generatedMeta.faction) or nil,
    }

    if meta then
        -- We have curated data - use it for accurate scoring
        input.sourceType = meta.sourceType
        input.expansion = meta.expansion
        input.timePerAttempt = meta.timePerAttempt or 10
        input.timeGate = meta.timeGate or "none"
        input.groupRequirement = meta.groupRequirement or "solo"
        input.dropChance = meta.dropChance
        input.steps = meta.steps

        -- Pass through reputation/currency metadata for display
        input.factionID = meta.factionID
        input.targetStanding = meta.targetStanding
        input.currencyID = meta.currencyID
        input.currencyRequired = meta.currencyRequired
        input.rarity = meta.rarity or (generatedMeta and generatedMeta.rarity)
        input.lockoutInstanceName = meta.lockoutInstanceName
        input.difficultyID = meta.difficultyID
        input.achievementID = meta.achievementID

        -- Resolve live progress based on source type
        -- First: resolve the primary requirement from curated data
        local skipTypes = {}
        if meta.sourceType == "reputation" and meta.factionID then
            input.progressRemaining = FB.ProgressResolver:GetRepProgress(
                meta.factionID, meta.targetStanding, meta.targetRenown
            )
            skipTypes.reputation = true
        elseif meta.sourceType == "currency" and meta.currencyID then
            input.progressRemaining = FB.ProgressResolver:GetCurrencyProgress(
                meta.currencyID, meta.currencyRequired
            )
            skipTypes.currency = true
        elseif meta.sourceType == "quest_chain" and meta.questChain then
            input.progressRemaining = FB.ProgressResolver:GetQuestChainProgress(
                meta.questChain
            )
        elseif meta.sourceType == "achievement" and meta.achievementID then
            input.progressRemaining = FB.ProgressResolver:GetAchievementProgress(
                meta.achievementID
            )
            skipTypes.achievement = true
        end

        -- Second: detect ADDITIONAL requirements from sourceText
        -- A mount may need rep AND currency AND gold — enrich finds them all
        self:EnrichFromSourceText(input, sourceText, skipTypes)

        -- Fallback: if nothing was detected at all, default to 1.0
        if not input.progressRemaining then
            input.progressRemaining = 1.0
        end

        -- Resolve time-gate (lockout status)
        input.attemptsRemaining = FB.TimeGateResolver:GetAttemptsRemaining(meta)

        -- Fallback: for generated DB mounts without lockoutInstanceName, try matching sourceText
        if input.attemptsRemaining == 1 and not meta.lockoutInstanceName and sourceText then
            input.attemptsRemaining = FB.TimeGateResolver:CheckLockoutFromSourceText(
                sourceText, meta.timeGate or input.timeGate
            )
        end

        -- Calculate expected attempts
        -- Prefer curated expectedAttempts if provided (e.g. world camping mounts)
        if meta.expectedAttempts then
            input.expectedAttempts = meta.expectedAttempts
        elseif meta.dropChance and meta.dropChance > 0 then
            input.expectedAttempts = math.ceil(1 / meta.dropChance)
        elseif input.progressRemaining > 0 then
            input.expectedAttempts = math.max(1, math.ceil(input.progressRemaining * 10))
        else
            input.expectedAttempts = 1
        end

        input.hasCuratedData = true
    else
        -- No curated data - use Blizzard's sourceType enum + sourceText for better guesses
        local guessedType = self:ResolveSourceType(sourceType, sourceText)
        input.sourceType = guessedType

        -- Try to guess expansion from source text, then fall back to InstanceData (#7)
        input.expansion = self:GuessExpansion(sourceText, descriptionText)
        if not input.expansion then
            input.expansion = self:GuessExpansionFromInstanceData(sourceText)
        end

        -- Assign reasonable defaults based on guessed source type and expansion age
        local defaults = self:GetDefaultsForSourceType(guessedType, input.expansion)
        input.timePerAttempt = defaults.timePerAttempt
        input.timeGate = defaults.timeGate
        input.groupRequirement = defaults.groupRequirement
        input.progressRemaining = 1.0
        input.attemptsRemaining = 1
        input.expectedAttempts = defaults.expectedAttempts
        input.hasCuratedData = false

        -- Drop chance fallback chain (#5):
        -- 1. Generated DB (scraped from data mining) > 2. Defaults
        if generatedMeta and generatedMeta.dropChance then
            input.dropChance = generatedMeta.dropChance
            -- Also recalculate expected attempts from actual drop chance
            if input.dropChance > 0 then
                input.expectedAttempts = math.ceil(1 / input.dropChance)
            end
        else
            input.dropChance = defaults.dropChance
        end

        -- PvP mount differentiation (#9): detect Gladiator vs Vicious vs rated
        if guessedType == "pvp" then
            self:RefinePvPScoring(input, sourceText, name)
        end

        -- Try to detect lockout from sourceText for uncurated weekly mounts
        if sourceText and defaults.timeGate == "weekly" then
            input.attemptsRemaining = FB.TimeGateResolver:CheckLockoutFromSourceText(
                sourceText, "weekly"
            )
        end

        -- Auto-detect ALL requirements from sourceText for uncurated mounts
        -- EnrichFromSourceText checks rep, currency, gold, and achievement independently
        -- and sets progressRemaining to the worst (max) of all detected requirements
        self:EnrichFromSourceText(input, sourceText)

        -- Reclassify sourceType if we detected a primary requirement
        if input.factionID and guessedType ~= "reputation" then
            input.sourceType = "reputation"
        elseif input.currencyID and guessedType ~= "currency" and not input.factionID then
            input.sourceType = "currency"
        end

        -- Recalculate expected attempts based on actual progress
        if input.progressRemaining then
            if input.progressRemaining <= 0 then
                input.expectedAttempts = 1
            else
                input.expectedAttempts = math.max(1,
                    math.ceil(input.progressRemaining * defaults.expectedAttempts))
            end
        end

        -- Estimate gold farming effort for vendor mounts with gold cost
        if input.goldCost and input.goldCost > 0 then
            local goldProgress = FB.ProgressResolver:GetGoldProgress(input.goldCost)
            if goldProgress > 0 then
                local hoursNeeded = (input.goldCost * goldProgress) / 10000
                -- Only override timePerAttempt if gold is the main blocker
                if not input.factionID and not input.currencyID then
                    input.timePerAttempt = math.max(5, math.min(600, hoursNeeded * 60))
                end
            end
        end
    end

    return input
end

-- Resolve source type using Blizzard's enum first, text parsing as fallback
function FB.Mounts.Resolver:ResolveSourceType(blizzType, sourceText)
    -- Use Blizzard enum first (most reliable)
    local fromEnum = BLIZZ_SOURCE[blizzType]
    if fromEnum and fromEnum ~= "unknown" then
        -- Refine: Blizzard marks both dungeon and raid drops as type 1 or 5
        -- Try to distinguish via source text
        if (fromEnum == "raid_drop" or fromEnum == "dungeon_drop") and sourceText then
            local lower = sourceText:lower()

            -- Allied race mounts: these are achievement mounts, not drops
            if lower:find("allied race") or lower:find("heritage armor")
               or lower:find("heritage ") then
                return "achievement"
            end

            -- World boss detection: outdoor bosses, not instanced content
            if lower:find("world boss") or lower:find("outdoor boss")
               or lower:find("rare spawn") or lower:find("rare elite")
               or lower:find("rare in ") or lower:find("rare mob") then
                return "world_boss"
            end

            -- Known world boss names (common mounts that get misclassified)
            local worldBossNames = {
                "sha of anger", "galleon", "oondasta", "nalak",
                "rukhmar", "huolon", "salyis",
            }
            for _, bossName in ipairs(worldBossNames) do
                if lower:find(bossName, 1, true) then
                    return "world_boss"
                end
            end

            if lower:find("raid") then
                return "raid_drop"
            elseif lower:find("dungeon") then
                return "dungeon_drop"
            end
        end

        -- Refine: Blizzard marks many vendor mounts as type 3, including
        -- reputation vendors, currency vendors, and trading post items.
        -- Check sourceText to reclassify more accurately.
        if fromEnum == "vendor" and sourceText then
            local lower = sourceText:lower()
            -- Trading Post items sold for Trader's Tender (via vendor type 3, not just type 12)
            if lower:find("trader's tender") or lower:find("trading post") then
                return "trading_post"
            end
            -- Reputation vendor mounts: "Requires Exalted with <Faction>" or "Renown X with <Faction>"
            if lower:find("exalted") or lower:find("revered") or lower:find("honored")
               or lower:find("friendly with") or lower:find("reputation")
               or lower:find("renown %d+ with") then
                return "reputation"
            end
            -- Currency vendor mounts
            -- Use specific phrases to avoid false positives
            -- ("mark of" not "mark", "honor points" not "honor", etc.)
            if lower:find("renown") or lower:find("token") or lower:find("commendation")
               or lower:find("medal") or lower:find("mark of ") or lower:find("emblem")
               or lower:find("currency") or lower:find("badge") or lower:find("garrison resource")
               or lower:find("timewarped") or lower:find("honor point") or lower:find("conquest")
               or lower:find("polished pet charm") then
                return "currency"
            end
        end

        -- Refine: sub-classify promotions (Blizzard sourceType 8)
        if fromEnum == "promotion" and sourceText then
            local lower = sourceText:lower()
            if lower:find("blizzard shop") or lower:find("blizzard store")
               or lower:find("in%-game shop") or lower:find("in%-game store") then
                return "blizzard_shop"
            elseif lower:find("trading card") or lower:find("tcg")
               or lower:find("loot card") then
                return "tcg"
            elseif lower:find("recruit") then
                return "recruit_a_friend"
            end
        end

        return fromEnum
    end

    -- Fallback: parse source text
    return self:GuessSourceType(sourceText)
end

-- Guess source type from the sourceText provided by the API (fallback)
function FB.Mounts.Resolver:GuessSourceType(sourceText)
    if not sourceText then return "unknown" end
    local lower = sourceText:lower()

    -- Allied race mounts (must come first)
    if lower:find("allied race") or lower:find("heritage armor")
       or lower:find("heritage ") then
        return "achievement"
    end

    -- World boss (must come before generic "drop" catch-all)
    if lower:find("world boss") or lower:find("outdoor boss") then
        return "world_boss"
    end

    if lower:find("raid") then
        return "raid_drop"
    elseif lower:find("dungeon") or lower:find("instance") then
        return "dungeon_drop"
    elseif lower:find("reputation") or lower:find("exalted") or lower:find("renown") then
        return "reputation"
    elseif lower:find("vendor") or lower:find("purchase") or lower:find("gold") then
        return "vendor"
    elseif lower:find("quest") then
        return "quest_chain"
    elseif lower:find("achievement") or lower:find("glory") then
        return "achievement"
    elseif lower:find("profession") or lower:find("crafted") or lower:find("engineering") then
        return "profession"
    elseif lower:find("pvp") or lower:find("arena") or lower:find("battleground") or lower:find("rated") then
        return "pvp"
    elseif lower:find("event") or lower:find("holiday") or lower:find("brewfest")
           or lower:find("hallow") or lower:find("love is") then
        return "event"
    elseif lower:find("trading post") or lower:find("trader's tender") then
        return "trading_post"
    elseif lower:find("promotion") or lower:find("store") or lower:find("blizzard")
           or lower:find("collector") then
        return "promotion"
    elseif lower:find("rare") or lower:find("world") or lower:find("treasure") then
        return "world_drop"
    elseif lower:find("drop") then
        return "dungeon_drop"
    elseif lower:find("currency") or lower:find("token") then
        return "currency"
    end

    return "unknown"
end

-- Expansion index for age-based calculations (higher = newer)
local EXPANSION_INDEX = {
    CLASSIC = 0, TBC = 1, WOTLK = 2, CATA = 3, MOP = 4,
    WOD = 5, LEGION = 6, BFA = 7, SL = 8, DF = 9, TWW = 10,
}
local CURRENT_EXPANSION_INDEX = 10  -- TWW

-- Get a time multiplier based on content age (old content is trivially fast to clear)
function FB.Mounts.Resolver:GetLegacyMultiplier(expansion)
    if not expansion then return 0.5 end  -- Unknown expansion, assume moderate
    local idx = EXPANSION_INDEX[expansion]
    if not idx then return 0.5 end
    local age = CURRENT_EXPANSION_INDEX - idx
    if age <= 1 then return 1.0 end    -- Current or previous expansion: full time
    if age == 2 then return 0.5 end    -- 2 expansions old: half time
    return 0.2                          -- 3+ expansions old: trivially fast
end

-- Get reasonable scoring defaults based on source type
-- If expansion is known, adjusts time estimates and requirements for content age
function FB.Mounts.Resolver:GetDefaultsForSourceType(sourceType, expansion)
    local idx = expansion and EXPANSION_INDEX[expansion]
    local age = idx and (CURRENT_EXPANSION_INDEX - idx) or nil

    -- Base defaults (assume legacy/solo content unless we know otherwise)
    local defaults = {
        raid_drop        = { timePerAttempt = 20, timeGate = "weekly",  groupRequirement = "solo",  dropChance = 0.01,  expectedAttempts = 100 },
        dungeon_drop     = { timePerAttempt = 10, timeGate = "daily",   groupRequirement = "solo",  dropChance = 0.01,  expectedAttempts = 100 },
        world_drop       = { timePerAttempt = 5,  timeGate = "none",    groupRequirement = "solo",  dropChance = 0.005, expectedAttempts = 200 },
        world_boss       = { timePerAttempt = 5,  timeGate = "weekly",  groupRequirement = "solo",  dropChance = 0.005, expectedAttempts = 200 },
        reputation       = { timePerAttempt = 30, timeGate = "daily",   groupRequirement = "solo",  dropChance = nil,   expectedAttempts = 30 },
        currency         = { timePerAttempt = 30, timeGate = "weekly",  groupRequirement = "solo",  dropChance = nil,   expectedAttempts = 10 },
        quest_chain      = { timePerAttempt = 60, timeGate = "none",    groupRequirement = "solo",  dropChance = nil,   expectedAttempts = 5 },
        achievement      = { timePerAttempt = 30, timeGate = "none",    groupRequirement = "solo",  dropChance = nil,   expectedAttempts = 10 },
        profession       = { timePerAttempt = 30, timeGate = "daily",   groupRequirement = "solo",  dropChance = nil,   expectedAttempts = 7 },
        pvp              = { timePerAttempt = 20, timeGate = "weekly",  groupRequirement = "small", dropChance = nil,   expectedAttempts = 50 },
        event            = { timePerAttempt = 15, timeGate = "yearly",  groupRequirement = "solo",  dropChance = 0.03,  expectedAttempts = 33 },
        vendor           = { timePerAttempt = 5,  timeGate = "none",    groupRequirement = "solo",  dropChance = nil,   expectedAttempts = 1 },
        trading_post     = { timePerAttempt = 0,  timeGate = "monthly", groupRequirement = "solo",  dropChance = nil,   expectedAttempts = 0 },
        blizzard_shop    = { timePerAttempt = 0,  timeGate = "none",    groupRequirement = "solo",  dropChance = nil,   expectedAttempts = 0 },
        tcg              = { timePerAttempt = 0,  timeGate = "none",    groupRequirement = "solo",  dropChance = nil,   expectedAttempts = 1 },
        recruit_a_friend = { timePerAttempt = 0,  timeGate = "none",    groupRequirement = "solo",  dropChance = nil,   expectedAttempts = 1 },
        promotion        = { timePerAttempt = 0,  timeGate = "none",    groupRequirement = "solo",  dropChance = nil,   expectedAttempts = 0 },
    }
    local d = defaults[sourceType] or { timePerAttempt = 15, timeGate = "weekly", groupRequirement = "solo", dropChance = 0.01, expectedAttempts = 100 }

    -- Apply content-age adjustments for drops
    if sourceType == "raid_drop" then
        if age and age == 0 then
            -- Current expansion raid: requires a group, long clear times, mythic drops are ~1%
            d.timePerAttempt = 30
            d.groupRequirement = "raid"
            d.dropChance = 0.01
        elseif age and age == 1 then
            -- Previous expansion: still somewhat challenging to solo, smaller group possible
            d.timePerAttempt = 20
            d.groupRequirement = "small"
        elseif age and age == 2 then
            -- 2 expansions old: soloable but takes moderate time
            d.timePerAttempt = 12
        elseif age and age >= 3 then
            -- 3+ expansions old: trivially soloable, quick clears
            d.timePerAttempt = math.max(3, math.floor(20 * 0.2))
        else
            -- Unknown expansion: assume moderate
            d.timePerAttempt = 12
        end
    elseif sourceType == "dungeon_drop" then
        if age and age == 0 then
            -- Current expansion: requires proper group, daily lockout on Heroic/Mythic
            d.timePerAttempt = 15
            d.groupRequirement = "small"
            d.timeGate = "daily"
        elseif age and age == 1 then
            -- Previous expansion: soloable but Heroic has daily lockout
            d.timePerAttempt = 8
            d.timeGate = "daily"
        elseif age and age >= 2 then
            -- Old content: farmable on Normal with no lockout, quick runs
            d.timePerAttempt = math.max(2, math.floor(10 * 0.2))
            d.timeGate = "none"
        else
            d.timePerAttempt = 6
            d.timeGate = "none"
        end
    elseif sourceType == "world_drop" then
        if age and age <= 1 then
            -- Current/previous expansion rares: contested, may need camping
            d.timePerAttempt = 15
            d.dropChance = 0.003
            d.expectedAttempts = 333
        end
    elseif sourceType == "achievement" then
        if age and age <= 1 then
            -- Current expansion achievements may need groups
            d.groupRequirement = "small"
            d.timePerAttempt = 45
        elseif age and age >= 3 then
            -- Old achievements: soloable, faster
            d.timePerAttempt = 20
        end
    elseif sourceType == "reputation" then
        if age and age == 0 then
            -- Current expansion: renown-based, weekly-gated with lots of sources
            d.timeGate = "weekly"
            d.timePerAttempt = 20
            d.expectedAttempts = 15
        elseif age and age >= 3 then
            -- Very old rep grinds: often faster due to tabard/mob grinding
            d.timePerAttempt = 15
            d.expectedAttempts = 20
        end
    end

    return d
end

-- Guess expansion by matching sourceText against InstanceData entries (#7)
-- Falls back when keyword-based GuessExpansion fails (generic "Drop: Boss Name" text)
function FB.Mounts.Resolver:GuessExpansionFromInstanceData(sourceText)
    if not sourceText or not FB.InstanceData or not FB.InstanceData.instances then
        return nil
    end
    local lower = sourceText:lower()
    for instName, instData in pairs(FB.InstanceData.instances) do
        if lower:find(instName:lower(), 1, true) then
            return instData.expansion
        end
    end
    return nil
end

-- PvP mount scoring differentiation (#9)
-- Gladiator mounts require top 0.5% rating: near-impossible grind
-- Vicious saddle mounts require ~40 rated wins: moderate grind
-- Other rated PvP mounts: variable difficulty
function FB.Mounts.Resolver:RefinePvPScoring(input, sourceText, mountName)
    local lowerSource = (sourceText or ""):lower()
    local lowerName = (mountName or ""):lower()

    if lowerName:find("gladiator") or lowerSource:find("gladiator") then
        -- Gladiator mounts: top 0.5% rated players, extremely competitive
        input.groupRequirement = "mythic"  -- Equivalent difficulty to mythic raiding
        input.timePerAttempt = 25           -- Average arena match
        input.expectedAttempts = 500        -- Hundreds of matches at high rating
        input.timeGate = "weekly"           -- Season-based, effectively weekly gated
    elseif lowerName:find("vicious") or lowerSource:find("vicious") then
        -- Vicious saddle mounts: ~40 rated wins
        input.groupRequirement = "small"    -- Need arena partner or RBG group
        input.timePerAttempt = 15           -- Average rated match
        input.expectedAttempts = 40         -- ~40 wins needed
        input.timeGate = "none"             -- Can grind continuously
    elseif lowerSource:find("rated") or lowerSource:find("arena") then
        -- Generic rated PvP mount
        input.groupRequirement = "small"
        input.timePerAttempt = 15
        input.expectedAttempts = 100
        input.timeGate = "weekly"
    elseif lowerSource:find("battleground") or lowerSource:find("honor") then
        -- Honor-based PvP mounts (easier)
        input.groupRequirement = "solo"     -- Random BGs are solo-queue
        input.timePerAttempt = 20
        input.expectedAttempts = 30
        input.timeGate = "none"
    end
    -- else: keep defaults from GetDefaultsForSourceType
end

-- Try to guess expansion from source text
function FB.Mounts.Resolver:GuessExpansion(sourceText, descText)
    local text = ((sourceText or "") .. " " .. (descText or "")):lower()

    local expansionKeywords = {
        { keys = {"war within", "khaz algar", "hallowfall", "isle of dorn", "azj%-kahet"}, expansion = "TWW" },
        { keys = {"dragonflight", "dragon isles", "zaralek", "emerald dream", "valdrakken"}, expansion = "DF" },
        { keys = {"shadowlands", "maldraxxus", "bastion", "revendreth", "ardenweald", "zereth mortis", "korthia"}, expansion = "SL" },
        { keys = {"battle for azeroth", "nazjatar", "mechagon", "zandalar", "kul tiras", "voldun", "uldir"}, expansion = "BFA" },
        { keys = {"legion", "broken isles", "argus", "suramar", "dalaran"}, expansion = "LEGION" },
        { keys = {"draenor", "tanaan", "garrison", "highmaul", "blackrock foundry"}, expansion = "WOD" },
        { keys = {"pandaria", "timeless isle", "throne of thunder", "mogu"}, expansion = "MOP" },
        { keys = {"cataclysm", "deepholm", "firelands", "dragon soul", "vortex pinnacle"}, expansion = "CATA" },
        { keys = {"northrend", "ulduar", "icecrown", "naxxramas", "wyrmrest"}, expansion = "WOTLK" },
        { keys = {"outland", "tempest keep", "karazhan", "netherwing", "sha'tari"}, expansion = "TBC" },
        { keys = {"stratholme", "zul'gurub", "ahn'qiraj", "molten core"}, expansion = "CLASSIC" },
    }

    for _, entry in ipairs(expansionKeywords) do
        for _, keyword in ipairs(entry.keys) do
            if text:find(keyword) then
                return entry.expansion
            end
        end
    end

    return nil
end
