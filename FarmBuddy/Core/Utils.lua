local addonName, FB = ...

FB.Utils = {}

-- Deep copy a table
function FB.Utils:DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = self:DeepCopy(v)
    end
    return copy
end

-- Shallow copy
function FB.Utils:ShallowCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = v
    end
    return copy
end

-- Merge tables (source into dest, source wins)
function FB.Utils:Merge(dest, source)
    for k, v in pairs(source) do
        if type(v) == "table" and type(dest[k]) == "table" then
            self:Merge(dest[k], v)
        else
            dest[k] = v
        end
    end
    return dest
end

-- Format a number with one decimal
function FB.Utils:FormatScore(score)
    return string.format("%.1f", score)
end

-- Format minutes into a readable string
function FB.Utils:FormatTime(minutes)
    if minutes < 1 then
        return "< 1 min"
    elseif minutes < 60 then
        return string.format("%d min", minutes)
    elseif minutes < 1440 then
        local hours = math.floor(minutes / 60)
        local mins = minutes % 60
        if mins > 0 then
            return string.format("%dh %dm", hours, mins)
        end
        return string.format("%dh", hours)
    else
        local days = math.floor(minutes / 1440)
        return self:FormatDays(days)
    end
end

-- Format days into a player-friendly string (weeks, months, years)
function FB.Utils:FormatDays(days)
    if days < 1 then
        return "< 1 day"
    elseif days < 2 then
        return "1 day"
    elseif days < 14 then
        return string.format("%d days", math.floor(days))
    elseif days < 60 then
        local weeks = math.floor(days / 7)
        return weeks == 1 and "1 week" or string.format("%d weeks", weeks)
    elseif days < 365 then
        local months = math.floor(days / 30)
        return months == 1 and "1 month" or string.format("%d months", months)
    else
        local years = days / 365
        -- Show months only up to ~18 months; anything over shows as years.
        -- This avoids confusing output like "13 months" for ~400 days.
        if years < 1.5 then
            local months = math.floor(days / 30)
            return months == 1 and "1 month" or string.format("%d months", months)
        end
        return string.format("%.1f years", years)
    end
end

-- FIX-7: Format a range of days for RNG mounts (percentile-based)
-- Only for mounts with known drop rates.
-- @param dropChance    number (0-1)
-- @param attemptsPerDay number (how many attempts per day given lockout)
-- @param hoursPerDay   number (daily playtime hours)
-- @return string like "~3-15 days (avg 7)" or nil if inputs invalid
function FB.Utils:FormatDaysRange(dropChance, attemptsPerDay, hoursPerDay)
    if not dropChance or dropChance <= 0 or dropChance >= 1 then return nil end
    attemptsPerDay = attemptsPerDay or 1
    hoursPerDay = hoursPerDay or 2

    local logBase = math.log(1 - dropChance)
    if logBase >= 0 then return nil end  -- Avoid division by zero

    -- Percentile-based attempt counts
    local p25Attempts = math.ceil(math.log(0.75) / logBase)  -- 25th percentile (lucky)
    local p50Attempts = math.ceil(math.log(0.5) / logBase)   -- 50th percentile (median)
    local p90Attempts = math.ceil(math.log(0.1) / logBase)   -- 90th percentile (unlucky)

    -- Convert attempts to calendar days
    local luckyDays = math.max(1, math.ceil(p25Attempts / attemptsPerDay))
    local medianDays = math.max(1, math.ceil(p50Attempts / attemptsPerDay))
    local unluckyDays = math.max(1, math.ceil(p90Attempts / attemptsPerDay))

    -- MED-5: For yearly events, attemptsPerDay is a fraction (e.g., 14/365 ≈ 0.038).
    -- This causes unluckyDays to balloon into multi-year values.
    -- When the p90 unlucky estimate exceeds 1 year, format in years to avoid
    -- confusing output like "~10 years". Note: this reflects real calendar time
    -- including the many non-event days between annual occurrences.
    if unluckyDays > 365 then
        return string.format("~%s-%s (avg %s, calendar time incl. non-event days)",
            self:FormatDays(luckyDays),
            self:FormatDays(unluckyDays),
            self:FormatDays(medianDays))
    end

    return string.format("~%s-%s (avg %s) (at %sh/day)",
        self:FormatDays(luckyDays),
        self:FormatDays(unluckyDays),
        self:FormatDays(medianDays),
        tostring(hoursPerDay))
end

-- Format gold amount with commas (e.g., 5,000,000)
function FB.Utils:FormatGold(amount)
    if not amount then return "0" end
    local formatted = tostring(math.floor(amount))
    -- Add commas for thousands
    while true do
        local k
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted .. "g"
end

-- Format a percentage
function FB.Utils:FormatPercent(value)
    return string.format("%.0f%%", value * 100)
end

-- Color a string by score (green = easy, red = hard)
-- Uses SetTextColor approach via return values for FontString coloring,
-- or inline WoW escape sequences for concatenated strings.
function FB.Utils:ColorByScore(text, score, maxScore)
    maxScore = maxScore or 200
    local ratio = math.min(score / maxScore, 1.0)
    -- Green (0,255,0) to Yellow (255,255,0) to Red (255,0,0)
    local r, g
    if ratio < 0.5 then
        r = ratio * 2
        g = 1.0
    else
        r = 1.0
        g = 1.0 - ((ratio - 0.5) * 2)
    end
    local hexColor = string.format("|cFF%02X%02X00", math.floor(r * 255), math.floor(g * 255))
    return hexColor .. text .. "|r"
end

-- Get RGB values for score coloring (for SetTextColor on FontStrings)
-- Returns r, g, b as 0-1 floats
function FB.Utils:GetScoreColor(score, maxScore)
    maxScore = maxScore or 200
    local ratio = math.min(score / maxScore, 1.0)
    local r, g
    if ratio < 0.5 then
        r = ratio * 2
        g = 1.0
    else
        r = 1.0
        g = 1.0 - ((ratio - 0.5) * 2)
    end
    return r, g, 0
end

-- Truncate string with ellipsis
function FB.Utils:Truncate(str, maxLen)
    if not str then return "" end
    if #str <= maxLen then return str end
    return string.sub(str, 1, maxLen - 3) .. "..."
end

-- Create a button (safe, works across all WoW versions)
function FB.Utils:CreateButton(parent, name, width, height)
    -- Try UIPanelButtonTemplate first, fall back to manual
    local ok, btn = pcall(CreateFrame, "Button", name, parent, "UIPanelButtonTemplate")
    if ok and btn then
        btn:SetSize(width or 100, height or 24)
        return btn
    end

    -- Manual fallback
    btn = CreateFrame("Button", name, parent, "BackdropTemplate")
    btn:SetSize(width or 100, height or 24)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 1.0)
    btn:SetNormalFontObject("GameFontNormal")
    btn:SetHighlightFontObject("GameFontHighlight")

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.3, 0.5, 1.0, 0.2)

    local originalSetText = btn.SetText
    if not btn.GetFontString then
        local fontStr = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fontStr:SetPoint("CENTER")
        btn.SetText = function(self, text)
            fontStr:SetText(text)
        end
        btn.GetText = function(self)
            return fontStr:GetText()
        end
    end

    -- Disable/Enable visuals
    local origDisable = btn.Disable
    btn.Disable = function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        self:EnableMouse(false)
    end
    btn.Enable = function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 1.0)
        self:EnableMouse(true)
    end

    return btn
end

-- Open the Blizzard mount journal and select a specific mount
function FB.Utils:OpenMountJournal(mountID)
    if not mountID then return end

    -- Ensure Collections addon is loaded
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        if not C_AddOns.IsAddOnLoaded("Blizzard_Collections") then
            pcall(C_AddOns.LoadAddOn, "Blizzard_Collections")
        end
    elseif not CollectionsJournal then
        if LoadAddOn then pcall(LoadAddOn, "Blizzard_Collections") end
    end

    -- Open the Collections window to the mount tab
    -- If already shown, switch tab (don't toggle which would CLOSE it)
    if CollectionsJournal and CollectionsJournal:IsShown() then
        if CollectionsJournal_SetTab then
            pcall(CollectionsJournal_SetTab, CollectionsJournal, 1)
        end
    else
        pcall(ToggleCollectionsJournal, 1)  -- 1 = Mounts tab
    end

    -- Retry loop: attempt to select the mount up to 5 times
    local attempts = 0
    local maxAttempts = 5
    local function TrySelectMount()
        attempts = attempts + 1

        -- Bail if journal was closed
        if not CollectionsJournal or not CollectionsJournal:IsShown() then
            if attempts < maxAttempts then
                C_Timer.After(0.3, TrySelectMount)
            end
            return
        end

        -- Clear filters so the mount is visible
        pcall(function()
            if C_MountJournal.SetCollectedFilterSetting then
                C_MountJournal.SetCollectedFilterSetting(LE_MOUNT_JOURNAL_FILTER_COLLECTED or 1, true)
                C_MountJournal.SetCollectedFilterSetting(LE_MOUNT_JOURNAL_FILTER_NOT_COLLECTED or 2, true)
            end
            if C_MountJournal.SetAllSourceFilters then
                C_MountJournal.SetAllSourceFilters(true)
            end
            if C_MountJournal.SetSearch then
                C_MountJournal.SetSearch("")
            end
            if MountJournal and MountJournal.searchBox then
                MountJournal.searchBox:SetText("")
            end
        end)

        -- Primary selection: SetSelectedMount (modern WoW)
        if C_MountJournal.SetSelectedMount then
            pcall(C_MountJournal.SetSelectedMount, mountID)
        end

        -- Wait briefly for filters to apply, then find display index for UI highlight
        C_Timer.After(0.15, function()
            if MountJournal_UpdateMountList then
                pcall(MountJournal_UpdateMountList)
            end

            local numDisplayed = C_MountJournal.GetNumDisplayedMounts
                and C_MountJournal.GetNumDisplayedMounts() or 0
            local foundIndex = nil

            for i = 1, numDisplayed do
                local dispOk, _, _, _, _, _, _, _, _, _, _, _, displayMountID =
                    pcall(C_MountJournal.GetDisplayedMountInfo, i)
                if dispOk and displayMountID == mountID then
                    foundIndex = i
                    break
                end
            end

            if foundIndex then
                -- Select via display index for UI highlight + scrolling
                if MountJournal_Select then
                    pcall(MountJournal_Select, foundIndex)
                end
                if MountJournal and MountJournal.ListScrollFrame
                   and MountJournal.ListScrollFrame.update then
                    pcall(MountJournal.ListScrollFrame.update, MountJournal.ListScrollFrame)
                end
                return  -- Success
            end

            -- Mount not found in filtered list — retry
            if attempts < maxAttempts then
                C_Timer.After(0.3, TrySelectMount)
            end
        end)
    end

    -- Initial delay to let journal open
    C_Timer.After(0.3, TrySelectMount)
end

-- Print addon message
function FB:Print(msg)
    print(FB.ADDON_PREFIX .. msg)
end

-- Print debug message
function FB:Debug(msg)
    if FB.db and FB.db.settings and FB.db.settings.debug then
        print(FB.ADDON_COLOR .. "FarmBuddy Debug|r: " .. msg)
    end
end

-- Sort a table by a key, returns new sorted array
function FB.Utils:SortByKey(tbl, key, ascending)
    local sorted = {}
    for _, v in ipairs(tbl) do
        sorted[#sorted + 1] = v
    end
    table.sort(sorted, function(a, b)
        if ascending then
            return (a[key] or 0) < (b[key] or 0)
        else
            return (a[key] or 0) > (b[key] or 0)
        end
    end)
    return sorted
end

-- Count table entries (for non-sequential tables)
function FB.Utils:Count(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Check if table is empty
function FB.Utils:IsEmpty(tbl)
    if not tbl then return true end
    return next(tbl) == nil
end

-- =====================
-- MOUNT DISPLAY HELPERS
-- =====================
-- Shared by MountSearchTab, MountRecommendTab, and any future mount detail views.

-- Source types that involve random drops
-- Reference FB.DROP_SOURCE_TYPES defined in Core\Constants.lua (MED-2)
local DROP_SOURCE_TYPES = FB.DROP_SOURCE_TYPES

local STANDING_NAMES = {
    [1] = "Hated", [2] = "Hostile", [3] = "Unfriendly", [4] = "Neutral",
    [5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted",
}

-- Get live reputation info for a faction (for mount detail display)
-- @param factionID   number
-- @param targetStanding  number (default 8 = Exalted)
-- @return table { name, current, target, isRenown, renownLevel } or nil
function FB.Utils:GetLiveRepInfo(factionID, targetStanding)
    if not factionID then return nil end

    local TARGET_NAME = STANDING_NAMES[targetStanding or 8] or "Exalted"
    local factionName = "Unknown Faction"
    local currentStanding = "?"
    local isRenown = false
    local renownLevel = nil
    local currentValue = nil   -- Rep earned within current standing tier
    local maxValue = nil       -- Rep needed to fill current standing tier
    local renownMax = nil      -- Max renown level (for renown factions)

    -- Try modern API
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, data = pcall(C_Reputation.GetFactionDataByID, factionID)
        if ok and data then
            factionName = data.name or factionName
            if data.isRenownReputation or data.renownLevel then
                isRenown = true
                if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
                    local mOk, majorData = pcall(C_MajorFactions.GetMajorFactionData, factionID)
                    if mOk and majorData then
                        renownLevel = majorData.renownLevel
                        renownMax = majorData.renownLevelThreshold
                        currentStanding = "Renown " .. (renownLevel or "?")
                        -- Renown progress within current level
                        if majorData.renownReputationEarned ~= nil and majorData.renownLevelThreshold then
                            currentValue = majorData.renownReputationEarned
                            maxValue = majorData.renownLevelThreshold
                        end
                    end
                end
            else
                currentStanding = STANDING_NAMES[data.reaction] or ("Standing " .. (data.reaction or "?"))
                -- Traditional rep: progress within current standing tier
                if data.currentReactionThreshold ~= nil and data.nextReactionThreshold then
                    local tierMin = data.currentReactionThreshold
                    local tierMax = data.nextReactionThreshold
                    local tierCurrent = data.currentStanding or 0
                    currentValue = tierCurrent - tierMin
                    maxValue = tierMax - tierMin
                end
            end
        end
    elseif GetFactionInfoByID then
        local ok, name, _, standingID, barMin, barMax, barValue = pcall(GetFactionInfoByID, factionID)
        if ok and name then
            factionName = name
            currentStanding = STANDING_NAMES[standingID] or ("Standing " .. (standingID or "?"))
            if barMin and barMax and barValue then
                currentValue = barValue - barMin
                maxValue = barMax - barMin
            end
        end
    end

    return {
        name = factionName,
        current = currentStanding,
        target = isRenown and "Max Renown" or TARGET_NAME,
        isRenown = isRenown,
        renownLevel = renownLevel,
        renownMax = renownMax,
        currentValue = currentValue,
        maxValue = maxValue,
    }
end

-- Get live currency info for display
-- @param currencyID     number
-- @param requiredAmount number
-- @return table { name, current, required, icon } or nil
function FB.Utils:GetLiveCurrencyInfo(currencyID, requiredAmount)
    if not currencyID then return nil end
    local currencyName = "Unknown Currency"
    local currentAmount = 0
    local icon = nil

    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
        if ok and info then
            currencyName = info.name or currencyName
            currentAmount = info.quantity or 0
            icon = info.iconFileID
        end
    end

    return {
        name = currencyName,
        current = currentAmount,
        required = requiredAmount or 0,
        icon = icon,
    }
end

-- Build auto-generated steps for mounts without curated step data
-- @param item  table - mount data with sourceText, sourceType, expansion, groupRequirement, timeGate, dropChance, expectedAttempts
-- @return steps table (array of strings)
function FB.Utils:BuildMountAutoSteps(item)
    local steps = {}

    -- Special handling for Trading Post mounts
    if item.sourceType == "trading_post" then
        steps[#steps + 1] = "Visit the Trading Post in Stormwind or Orgrimmar"
        steps[#steps + 1] = "Purchase with Trader's Tender"
        steps[#steps + 1] = "Check current monthly rotation for availability"
        if item.sourceText and item.sourceText ~= "" then
            steps[#steps + 1] = item.sourceText
        end
        return steps
    end

    -- Step 1: Where to go / what to do
    if item.sourceText and item.sourceText ~= "" then
        -- Extract clean vendor/zone/location from structured sourceText
        local clean = item.sourceText
        -- Strip WoW UI markup for display
        clean = clean:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        clean = clean:gsub("|T[^|]*|t", "")
        clean = clean:gsub("|H[^|]*|h", ""):gsub("|h", "")
        clean = clean:gsub("|n", "\n")
        -- Extract vendor and zone/location from structured fields
        local vendor = clean:match("[Vv]endor:%s*(.-)[\n]")
        local zone = clean:match("[Zz]one:%s*(.-)[\n]") or clean:match("[Ll]ocation:%s*(.-)[\n]")
        if vendor and vendor:match("%S") and zone then
            steps[#steps + 1] = "Vendor: " .. vendor:match("^%s*(.-)%s*$") .. " in " .. zone:match("^%s*(.-)%s*$")
        elseif vendor and vendor:match("%S") then
            steps[#steps + 1] = "Vendor: " .. vendor:match("^%s*(.-)%s*$")
        elseif zone then
            steps[#steps + 1] = "Location: " .. zone:match("^%s*(.-)%s*$")
        else
            -- Fallback: show cleaned full text (first line only)
            local firstLine = clean:match("^(.-)[\n]") or clean
            firstLine = firstLine:match("^%s*(.-)%s*$")
            if firstLine and #firstLine > 0 then
                steps[#steps + 1] = firstLine
            end
        end
    else
        local src = FB.SOURCE_TYPE_NAMES[item.sourceType] or item.sourceType
        if src then
            steps[#steps + 1] = "Source: " .. src
        end
    end

    -- Step 2: Expansion / location context
    if item.expansion then
        local expName = FB.EXPANSION_NAMES[item.expansion] or item.expansion
        steps[#steps + 1] = "Expansion: " .. expName
    end

    -- Step 3: Group requirement
    if item.groupRequirement and item.groupRequirement ~= "solo" then
        steps[#steps + 1] = "Requires: " .. (FB.GROUP_NAMES[item.groupRequirement] or item.groupRequirement)
    end

    -- Step 4: Time gate info
    if item.timeGate and item.timeGate ~= "none" then
        local gateNames = {
            daily = "Resets daily",
            weekly = "Resets weekly (Tuesday)",
            biweekly = "Resets every 2 weeks",
            monthly = "Resets monthly",
            yearly = "Available during annual event only",
        }
        steps[#steps + 1] = gateNames[item.timeGate] or ("Reset: " .. item.timeGate)
    else
        steps[#steps + 1] = "Farmable: no lockout restriction"
    end

    -- Step 5: Reputation requirement
    if item.factionID then
        local repInfo = self:GetLiveRepInfo(item.factionID, item.targetStanding)
        if repInfo then
            steps[#steps + 1] = "Reach " .. repInfo.target .. " with " .. repInfo.name
        end
    end

    -- Step 6: Currency requirement
    if item.currencyID and item.currencyRequired then
        local currInfo = self:GetLiveCurrencyInfo(item.currencyID, item.currencyRequired)
        if currInfo then
            steps[#steps + 1] = "Collect " .. item.currencyRequired .. " " .. currInfo.name
        end
    end

    -- Step 7: Gold cost
    if item.goldCost then
        steps[#steps + 1] = "Costs " .. self:FormatGold(item.goldCost) .. " gold"
    end

    -- Step 8: Achievement requirement
    if item.achievementID then
        local ok, name = pcall(GetAchievementInfo, item.achievementID)
        if ok and name then
            steps[#steps + 1] = "Complete achievement: " .. name
        end
    end

    -- Step 9: Item costs (event tokens, crafting materials)
    if item.itemCosts then
        for _, itemCost in ipairs(item.itemCosts) do
            local iName = nil
            if C_Item and C_Item.GetItemInfo then
                local iOk, info = pcall(C_Item.GetItemInfo, itemCost.itemID)
                if iOk and info then iName = info end
            elseif GetItemInfo then
                local iOk, info = pcall(GetItemInfo, itemCost.itemID)
                if iOk and info then iName = info end
            end
            if iName then
                steps[#steps + 1] = "Requires " .. itemCost.amount .. "x " .. iName
            else
                steps[#steps + 1] = "Requires " .. itemCost.amount .. "x item #" .. itemCost.itemID
            end
        end
    end

    -- Step 10: Drop chance (with source transparency)
    if item.dropChance then
        local pct = item.dropChance * 100
        local sourceTag = ""
        if item.dropChanceSource == "curated" then
            sourceTag = " [verified]"
        elseif item.dropChanceSource == "rarity_db" then
            sourceTag = " [community data]"
        end
        local label
        if pct >= 5 then
            label = string.format("%.0f%% drop chance (decent odds)%s", pct, sourceTag)
        elseif pct >= 1 then
            label = string.format("%.1f%% drop chance (~%d attempts expected)%s", pct, item.expectedAttempts or math.ceil(math.log(0.5) / math.log(1 - item.dropChance)), sourceTag)
        else
            label = string.format("%.2f%% drop chance (~%d attempts expected)%s", pct, item.expectedAttempts or math.ceil(math.log(0.5) / math.log(1 - item.dropChance)), sourceTag)
        end
        steps[#steps + 1] = label
    elseif DROP_SOURCE_TYPES[item.sourceType] then
        steps[#steps + 1] = "Drop rate: unknown"
    end

    return steps
end

-- Build structured detail data for the detail panel header area.
-- Separates name, subtitle, and body text so tabs can display them in distinct FontStrings.
-- @param item  table - enriched mount data
-- @param showCollected bool - whether to include collected status in subtitle
-- @return table { name, subtitle, detailText, steps }
function FB.Utils:BuildMountDetailData(item, showCollected)
    local lines, steps = self:BuildMountDetailLines(item, showCollected)

    -- BuildMountDetailLines structure:
    --   [1] = gold-colored name line
    --   [2] = "" (blank spacer)
    --   [3] = (if showCollected) collected status line, otherwise info summary line
    --   [4] = (if showCollected) info summary line, otherwise faction/score/detail...
    -- We pull name and subtitle ourselves and skip those header lines in detailText.

    local name = item.name or ""

    -- Build subtitle: source type + expansion
    local subtitleParts = {}
    subtitleParts[#subtitleParts + 1] = FB.SOURCE_TYPE_NAMES[item.sourceType] or "Unknown"
    if item.expansion then
        subtitleParts[#subtitleParts + 1] = FB.EXPANSION_NAMES[item.expansion] or item.expansion
    end
    -- Append collected status to subtitle when requested
    if showCollected then
        if item.isCollected then
            subtitleParts[#subtitleParts + 1] = FB.COLORS.GREEN .. "Collected|r"
        else
            subtitleParts[#subtitleParts + 1] = FB.COLORS.RED .. "Not Collected|r"
        end
    end
    local subtitle = table.concat(subtitleParts, "  -  ")

    -- Determine how many leading lines to skip in the lines table:
    --   Always skip: [1] name, [2] blank, and the info summary line.
    --   When showCollected: also skip the collected status line (it's now in subtitle).
    -- The info summary line position:
    --   showCollected=true  -> [3]=collected, [4]=info summary -> skip first 4
    --   showCollected=false -> [3]=info summary -> skip first 3
    local skipCount = showCollected and 4 or 3

    local detailLines = {}
    for i = skipCount + 1, #lines do
        detailLines[#detailLines + 1] = lines[i]
    end

    return {
        name = name,
        subtitle = subtitle,
        detailText = table.concat(detailLines, "\n"),
        steps = steps,
    }
end

-- Build rich detail lines for a mount (shared between Search and Recommend tabs)
-- @param item  table - enriched mount data (from Resolver + Scorer)
-- @param showCollected bool - whether to show collected/not collected status
-- @return lines table (array of strings), steps table
function FB.Utils:BuildMountDetailLines(item, showCollected)
    local lines = {}
    lines[#lines + 1] = FB.COLORS.GOLD .. item.name .. "|r"
    lines[#lines + 1] = ""

    -- Collected status (for search tab)
    if showCollected then
        if item.isCollected then
            lines[#lines + 1] = FB.COLORS.GREEN .. "Collected!|r"
        else
            lines[#lines + 1] = FB.COLORS.RED .. "Not Collected|r"
        end
    end

    -- Info summary line
    local infoParts = {}
    infoParts[#infoParts + 1] = FB.SOURCE_TYPE_NAMES[item.sourceType] or "Unknown"
    if item.expansion then
        infoParts[#infoParts + 1] = FB.EXPANSION_NAMES[item.expansion] or item.expansion
    end
    if item.faction then
        local factionColor = (item.faction == "ALLIANCE" or item.faction == 0) and "|cFF0070DD" or "|cFFFF2020"
        local factionName = (item.faction == "ALLIANCE" or item.faction == 0) and "Alliance" or "Horde"
        infoParts[#infoParts + 1] = factionColor .. factionName .. "|r"
    end
    lines[#lines + 1] = table.concat(infoParts, " - ")

    -- Prominent faction indicator (Alliance/Horde-specific mounts)
    if item.faction then
        local factionColor, factionName, factionIcon
        if item.faction == "ALLIANCE" or item.faction == 0 then
            factionColor = "|cFF0070DD"
            factionName = "Alliance"
            factionIcon = "|TInterface\\PVPFrame\\PVP-Currency-Alliance:16:16|t "
        else
            factionColor = "|cFFFF2020"
            factionName = "Horde"
            factionIcon = "|TInterface\\PVPFrame\\PVP-Currency-Horde:16:16|t "
        end
        lines[#lines + 1] = factionIcon .. factionColor .. factionName .. " Only|r"
        -- Warn if player is the wrong faction
        if FB.playerFaction then
            local playerIsAlliance = (FB.playerFaction == "Alliance")
            local mountIsAlliance = (item.faction == "ALLIANCE" or item.faction == 0)
            if playerIsAlliance ~= mountIsAlliance then
                lines[#lines + 1] = FB.COLORS.RED
                    .. "  Warning: Requires a " .. factionName .. " character|r"
            end
        end
    end

    -- Score explanation (plain-English summary) (#4)
    if item.scoreExplanation and item.scoreExplanation ~= "" then
        lines[#lines + 1] = FB.COLORS.GRAY .. item.scoreExplanation .. "|r"
    end

    -- Enhanced Reputation info (shown prominently when present)
    if item.factionID then
        local repInfo = self:GetLiveRepInfo(item.factionID, item.targetStanding)
        if repInfo then
            lines[#lines + 1] = ""
            lines[#lines + 1] = FB.COLORS.GOLD .. "--- Reputation Requirement ---|r"
            lines[#lines + 1] = FB.COLORS.BLUE .. "  Faction: |r" .. FB.COLORS.WHITE .. repInfo.name .. "|r"
            -- Standing with color coding
            local standingColor = (repInfo.current == repInfo.target)
                and FB.COLORS.GREEN or FB.COLORS.ORANGE
            local standingLine = "  Standing: " .. standingColor .. repInfo.current .. "|r"
                .. "  ->  Required: " .. FB.COLORS.GOLD .. repInfo.target .. "|r"
            lines[#lines + 1] = standingLine
            -- FIX-8D: Precise rep remaining and time estimate
            if repInfo.currentValue and repInfo.maxValue and repInfo.maxValue > 0 then
                lines[#lines + 1] = "  " .. FB.COLORS.GRAY
                    .. "Tier progress: " .. repInfo.currentValue .. " / " .. repInfo.maxValue .. "|r"
            end
            -- Show precise points remaining and estimated days
            if item.factionID then
                local repRemaining, renownRemaining = nil, nil
                if FB.ProgressResolver and FB.ProgressResolver.GetRepPointsRemaining then
                    local ok
                    ok, repRemaining, renownRemaining = pcall(
                        FB.ProgressResolver.GetRepPointsRemaining, FB.ProgressResolver,
                        item.factionID, item.targetStanding, item.targetRenown
                    )
                    if not ok then repRemaining, renownRemaining = nil, nil end
                end

                local repData = FB.ReputationData and FB.ReputationData[item.factionID]
                if repInfo.isRenown and renownRemaining and renownRemaining > 0 then
                    local goalRenown = item.targetRenown or "max"
                    local currentRenown = repInfo.renownLevel or 0
                    local daysStr = ""
                    if repData and repData.method == "renown" and repData.weeklyRep > 0 then
                        local weeks = math.ceil(renownRemaining / repData.weeklyRep)
                        daysStr = string.format(" (~%d weeks at weekly cap)", weeks)
                    end
                    lines[#lines + 1] = "  " .. FB.COLORS.YELLOW
                        .. "Renown: " .. currentRenown .. " / " .. goalRenown .. daysStr .. "|r"
                elseif repRemaining and repRemaining > 0 then
                    local daysStr = ""
                    if repData then
                        local methodLabel = ""
                        if repData.method == "tabard" then
                            local days = math.ceil(repRemaining / math.max(1, repData.dailyRep))
                            daysStr = string.format(" (~%d days via tabard farming)", days)
                        elseif repData.method == "daily" then
                            local effectiveDaily = repData.dailyRep + (repData.weeklyRep / 7)
                            local days = math.ceil(repRemaining / math.max(1, effectiveDaily))
                            daysStr = string.format(" (~%d days via dailies)", days)
                        end
                    end
                    -- Format remaining rep with commas
                    local repStr = tostring(math.floor(repRemaining))
                    while true do
                        local k
                        repStr, k = repStr:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
                        if k == 0 then break end
                    end
                    lines[#lines + 1] = "  " .. FB.COLORS.YELLOW
                        .. "Rep: " .. repStr .. " remaining to " .. repInfo.target .. daysStr .. "|r"
                end
            end
            -- Text progress bar
            local repOk, repProgress = pcall(FB.ProgressResolver.GetRepProgress,
                FB.ProgressResolver,
                item.factionID, item.targetStanding, item.targetRenown
            )
            if not repOk then repProgress = nil end
            if repProgress ~= nil then
                local pct = math.floor((1 - repProgress) * 100)
                local barLength = 20
                local filled = math.floor(barLength * (pct / 100))
                local empty = barLength - filled
                local bar = string.rep("|", filled) .. string.rep(".", empty)
                if repProgress == 0 then
                    lines[#lines + 1] = "  " .. FB.COLORS.GREEN .. "[" .. bar .. "] 100% - Complete!|r"
                else
                    lines[#lines + 1] = "  " .. FB.COLORS.YELLOW .. "[" .. bar .. "] " .. pct .. "%|r"
                end
            end
            lines[#lines + 1] = FB.COLORS.GOLD .. "-------------------------------|r"
        end
    end

    -- Instance efficiency badge (#3)
    if item.instanceGroupCount and item.instanceGroupCount > 1 then
        lines[#lines + 1] = FB.COLORS.GREEN .. item.instanceGroupCount
            .. " mounts from same instance run!|r"
    end

    -- Staleness indicator (#6)
    if item.staleDays then
        if item.staleDays > 30 then
            lines[#lines + 1] = FB.COLORS.ORANGE .. "Last attempted: " .. math.floor(item.staleDays) .. " days ago|r"
        elseif item.staleDays > 7 then
            lines[#lines + 1] = FB.COLORS.YELLOW .. "Last attempted: " .. math.floor(item.staleDays) .. " days ago|r"
        end
    end

    -- Detail summary line (only for enriched mounts)
    if item.groupRequirement or item.timeGate or item.timePerAttempt then
        local detailParts = {}
        detailParts[#detailParts + 1] = FB.GROUP_NAMES[item.groupRequirement] or "Solo"
        if item.timeGate and item.timeGate ~= "none" then
            detailParts[#detailParts + 1] = item.timeGate .. " reset"
        else
            detailParts[#detailParts + 1] = "no lockout"
        end
        if item.timePerAttempt then
            detailParts[#detailParts + 1] = self:FormatTime(item.timePerAttempt) .. "/run"
        end
        lines[#lines + 1] = FB.COLORS.GRAY .. table.concat(detailParts, " | ") .. "|r"
    end

    -- FIX-15: Drop info line with source transparency
    if item.dropChance then
        local pct = item.dropChance * 100
        local dropStr
        if pct >= 1 then
            dropStr = string.format("%.1f%% drop", pct)
        else
            dropStr = string.format("%.2f%% drop", pct)
        end
        -- Add source tag
        if item.dropChanceSource == "curated" then
            dropStr = dropStr .. " (verified)"
        elseif item.dropChanceSource == "rarity_db" then
            dropStr = dropStr .. " (community data)"
        end
        lines[#lines + 1] = FB.COLORS.GRAY .. dropStr .. " | ~" .. (item.expectedAttempts or "?") .. " attempts expected|r"
    elseif DROP_SOURCE_TYPES[item.sourceType] then
        -- FIX-15: Unknown drop rate for drop-type mounts
        lines[#lines + 1] = FB.COLORS.ORANGE .. "Drop Rate: Unknown|r"
    end

    -- Player ownership rarity (from Data for Azeroth)
    if item.rarity then
        local rarityPct = item.rarity
        local rarityColor
        if rarityPct <= 5 then
            rarityColor = FB.COLORS.ORANGE  -- Very rare
        elseif rarityPct <= 20 then
            rarityColor = FB.COLORS.YELLOW  -- Uncommon
        else
            rarityColor = FB.COLORS.GRAY    -- Common
        end
        lines[#lines + 1] = rarityColor .. string.format("%.1f%% of players own this mount", rarityPct) .. "|r"
    end

    -- (Reputation info is now shown prominently above, after score explanation)

    -- Live Currency info
    if item.currencyID then
        local currInfo = self:GetLiveCurrencyInfo(item.currencyID, item.currencyRequired)
        if currInfo then
            lines[#lines + 1] = ""
            local iconStr = currInfo.icon and ("|T" .. currInfo.icon .. ":12:12|t ") or ""
            lines[#lines + 1] = FB.COLORS.BLUE .. "Currency: " .. iconStr .. currInfo.name .. "|r"
            local progressColor
            if currInfo.current >= currInfo.required then
                progressColor = FB.COLORS.GREEN
            elseif currInfo.current > 0 then
                progressColor = FB.COLORS.ORANGE
            else
                progressColor = FB.COLORS.RED
            end
            lines[#lines + 1] = "  Have: " .. progressColor .. currInfo.current .. "|r" ..
                " / Need: " .. FB.COLORS.WHITE .. currInfo.required .. "|r"
            if currInfo.current >= currInfo.required then
                lines[#lines + 1] = "  " .. FB.COLORS.GREEN .. "Ready to purchase!|r"
            else
                local remaining = currInfo.required - currInfo.current
                lines[#lines + 1] = "  " .. FB.COLORS.YELLOW .. remaining .. " more needed|r"
            end
        end
    end

    -- Live Achievement info
    if item.achievementID then
        local critOk, remaining, total = pcall(FB.ProgressResolver.GetRemainingCriteria, FB.ProgressResolver, item.achievementID)
        if not critOk then remaining, total = 0, 0 end
        if total > 0 then
            lines[#lines + 1] = ""
            -- Try to get achievement name
            local achieveName = "Achievement"
            if GetAchievementInfo then
                local ok, name = pcall(GetAchievementInfo, item.achievementID)
                if ok and name then achieveName = name end
            end
            lines[#lines + 1] = FB.COLORS.BLUE .. "Achievement: " .. achieveName .. "|r"
            local completed = total - remaining
            local progressColor
            if remaining == 0 then
                progressColor = FB.COLORS.GREEN
            elseif completed > 0 then
                progressColor = FB.COLORS.ORANGE
            else
                progressColor = FB.COLORS.RED
            end
            lines[#lines + 1] = "  Criteria: " .. progressColor .. completed .. "/" .. total .. "|r"
            if remaining == 0 then
                lines[#lines + 1] = "  " .. FB.COLORS.GREEN .. "Achievement complete!|r"
            else
                lines[#lines + 1] = "  " .. FB.COLORS.YELLOW .. remaining .. " criteria remaining|r"
            end
        end
    end

    -- Trading Post mount
    if item.sourceType == "trading_post" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = FB.COLORS.BLUE .. "Trading Post Mount|r"
        lines[#lines + 1] = "  Purchased with Trader's Tender"
        lines[#lines + 1] = "  " .. FB.COLORS.ORANGE .. "Availability depends on monthly rotation|r"
        if item.sourceText and item.sourceText ~= "" then
            lines[#lines + 1] = "  " .. item.sourceText
        end
    end

    -- Gold cost display (shown independently — a mount may need rep + gold + currency)
    if item.goldCost then
        lines[#lines + 1] = ""
        lines[#lines + 1] = FB.COLORS.BLUE .. "Gold Cost:|r"
        local ok, currentMoney = pcall(GetMoney)
        local currentGold = ok and math.floor(currentMoney / 10000) or 0
        local progressColor
        if currentGold >= item.goldCost then
            progressColor = FB.COLORS.GREEN
        elseif currentGold > 0 then
            progressColor = FB.COLORS.ORANGE
        else
            progressColor = FB.COLORS.RED
        end
        lines[#lines + 1] = "  Cost: " .. FB.COLORS.GOLD .. self:FormatGold(item.goldCost) .. "|r"
        lines[#lines + 1] = "  Have: " .. progressColor .. self:FormatGold(currentGold) .. "|r"
        if currentGold >= item.goldCost then
            lines[#lines + 1] = "  " .. FB.COLORS.GREEN .. "Can afford!|r"
        else
            lines[#lines + 1] = "  " .. FB.COLORS.YELLOW .. self:FormatGold(item.goldCost - currentGold) .. " more needed|r"
        end
    end

    -- Item costs display (event tokens, crafting materials from |Hitem:| hyperlinks)
    if item.itemCosts and #item.itemCosts > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = FB.COLORS.BLUE .. "Item Costs:|r"
        for _, itemCost in ipairs(item.itemCosts) do
            local iName = nil
            if GetItemInfo then
                local iOk, info = pcall(GetItemInfo, itemCost.itemID)
                if iOk and info then iName = info end
            end
            local displayName = iName or ("Item #" .. itemCost.itemID)
            -- Check player inventory for this item
            local haveCount = 0
            if C_Item and C_Item.GetItemCount then
                local cOk, cnt = pcall(C_Item.GetItemCount, itemCost.itemID, true) -- true = include bank
                if cOk and cnt then haveCount = cnt end
            elseif GetItemCount then
                local cOk, cnt = pcall(GetItemCount, itemCost.itemID, true)
                if cOk and cnt then haveCount = cnt end
            end
            local progressColor = haveCount >= itemCost.amount and FB.COLORS.GREEN or FB.COLORS.ORANGE
            lines[#lines + 1] = "  " .. progressColor .. itemCost.amount .. "x " .. displayName
                .. " (have " .. haveCount .. ")|r"
        end
    end

    -- Vendor mount fallback: show sourceText if no specific requirements detected
    if not item.factionID and not item.currencyID and not item.goldCost
       and not item.itemCosts
       and item.sourceType == "vendor" and item.sourceText and item.sourceText ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = FB.COLORS.BLUE .. "Vendor Mount|r"
        lines[#lines + 1] = "  " .. item.sourceText
    end

    -- Multi-requirement summary: when 2+ requirements are detected, show which is the bottleneck
    local reqCount = 0
    local reqNames = {}
    local reqProgress = {}
    if item.factionID then
        reqCount = reqCount + 1
        reqNames[#reqNames + 1] = "Reputation"
        local ok, prog = pcall(FB.ProgressResolver.GetRepProgress, FB.ProgressResolver,
            item.factionID, item.targetStanding, item.targetRenown)
        reqProgress[#reqProgress + 1] = { name = "Reputation", progress = ok and prog or nil }
    end
    if item.currencyID then
        reqCount = reqCount + 1
        reqNames[#reqNames + 1] = "Currency"
        local ok, prog = pcall(FB.ProgressResolver.GetCurrencyProgress, FB.ProgressResolver,
            item.currencyID, item.currencyRequired)
        reqProgress[#reqProgress + 1] = { name = "Currency", progress = ok and prog or nil }
    end
    if item.goldCost then
        reqCount = reqCount + 1
        reqNames[#reqNames + 1] = "Gold"
        local ok, prog = pcall(FB.ProgressResolver.GetGoldProgress, FB.ProgressResolver, item.goldCost)
        reqProgress[#reqProgress + 1] = { name = "Gold", progress = ok and prog or nil }
    end
    if item.achievementID then
        reqCount = reqCount + 1
        reqNames[#reqNames + 1] = "Achievement"
        local ok, prog = pcall(FB.ProgressResolver.GetAchievementProgress, FB.ProgressResolver,
            item.achievementID)
        reqProgress[#reqProgress + 1] = { name = "Achievement", progress = ok and prog or nil }
    end
    if item.itemCosts then
        reqCount = reqCount + 1
        reqNames[#reqNames + 1] = "Items"
    end

    if reqCount >= 2 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = FB.COLORS.YELLOW .. "Multiple requirements: " .. table.concat(reqNames, " + ") .. "|r"
        if item.progressRemaining and item.progressRemaining > 0 then
            local pct = math.floor((1 - item.progressRemaining) * 100)
            -- Find the bottleneck (highest remaining progress)
            local bottleneck = nil
            local worstProg = -1
            for _, rp in ipairs(reqProgress) do
                if rp.progress and rp.progress > worstProg then
                    worstProg = rp.progress
                    bottleneck = rp.name
                end
            end
            local bottleneckStr = ""
            if bottleneck then
                bottleneckStr = " — bottleneck: " .. bottleneck
            end
            lines[#lines + 1] = FB.COLORS.GRAY .. "Overall progress: " .. pct .. "%" .. bottleneckStr .. "|r"
        elseif item.progressRemaining == 0 then
            lines[#lines + 1] = FB.COLORS.GREEN .. "All requirements met!|r"
        end
    end

    -- Warband lockout status (cross-character visibility)
    if item.lockoutInstanceName or (item.timeGate == "weekly" and item.sourceType == "raid_drop") then
        local instName = item.lockoutInstanceName or item.instanceName
        if instName and FB.CharacterData and FB.CharacterData.GetWarbandLockoutStatus then
            local isFullyLocked, availChars, lockedChars = FB.CharacterData:GetWarbandLockoutStatus(
                instName, item.difficultyID
            )
            if #availChars > 0 or #lockedChars > 0 then
                lines[#lines + 1] = ""
                lines[#lines + 1] = FB.COLORS.BLUE .. "Warband Status:|r"

                if #availChars > 0 then
                    local charNames = {}
                    for _, charKey in ipairs(availChars) do
                        local shortName = charKey:match("^(.-)%s*-") or charKey
                        local charInfo = FB.db and FB.db.characters and FB.db.characters[charKey]
                        local classColor = charInfo and FB.CLASS_COLORS[charInfo.class] or "FFFFFF"
                        charNames[#charNames + 1] = "|cFF" .. classColor .. shortName .. "|r"
                    end
                    lines[#lines + 1] = "  " .. FB.COLORS.GREEN .. "Available:|r " .. table.concat(charNames, ", ")
                end

                if #lockedChars > 0 then
                    local charNames = {}
                    for _, charKey in ipairs(lockedChars) do
                        local shortName = charKey:match("^(.-)%s*-") or charKey
                        local charInfo = FB.db and FB.db.characters and FB.db.characters[charKey]
                        local classColor = charInfo and FB.CLASS_COLORS[charInfo.class] or "FFFFFF"
                        charNames[#charNames + 1] = "|cFF" .. classColor .. shortName .. "|r"
                    end
                    lines[#lines + 1] = "  " .. FB.COLORS.RED .. "Locked:|r " .. table.concat(charNames, ", ")
                end

                -- Best alt suggestion
                if isFullyLocked then
                    lines[#lines + 1] = "  " .. FB.COLORS.RED .. "All characters locked this reset|r"
                elseif #availChars > 0 and #lockedChars > 0 then
                    local bestAlt = FB.CharacterData:GetBestAltForInstance(
                        instName, item.difficultyID,
                        item.isFactionSpecific and item.faction or nil
                    )
                    if bestAlt and bestAlt ~= FB.playerKey then
                        local shortName = bestAlt:match("^(.-)%s*-") or bestAlt
                        local charInfo = FB.db.characters[bestAlt]
                        local classColor = charInfo and FB.CLASS_COLORS[charInfo.class] or "FFFFFF"
                        lines[#lines + 1] = "  Best alt: |cFF" .. classColor .. shortName .. "|r (fewest lockouts)"
                    end
                end
            end
        end
    end

    -- Instance info (from InstanceData)
    if item.lockoutInstanceName or item.instanceName then
        local instName = item.lockoutInstanceName or item.instanceName
        local instData = FB.InstanceData and FB.InstanceData:Get(instName)
        if instData then
            lines[#lines + 1] = ""
            lines[#lines + 1] = FB.COLORS.BLUE .. "Instance: " .. instName .. "|r"
            if instData.bossCount then
                lines[#lines + 1] = "  Bosses: " .. instData.bossCount
            end
            if instData.soloMinutes then
                lines[#lines + 1] = "  Solo clear: ~" .. self:FormatTime(instData.soloMinutes)
            end
            if instData.expansion then
                lines[#lines + 1] = "  Content: " .. (FB.EXPANSION_NAMES[instData.expansion] or instData.expansion)
            end
        end
    end

    -- FIX-7: Estimate section with range for RNG, single for guaranteed
    if item.effectiveDays and item.effectiveDays > 0 then
        lines[#lines + 1] = ""
        local hoursPerDay = (FB.db and FB.db.settings and FB.db.settings.hoursPerDay) or 2
        if item.dropChance and item.dropChance > 0 and item.dropChance < 1 then
            -- RNG: show range estimate
            local gateDays = FB.TIME_GATE_FACTORS[item.timeGate or "none"] or 0
            local attemptsPerDay = gateDays > 0 and (1 / gateDays) or
                math.max(1, math.floor(hoursPerDay * 60 / math.max(1, item.timePerAttempt or 10)))
            local rangeStr = self:FormatDaysRange(item.dropChance, attemptsPerDay, hoursPerDay)
            if rangeStr then
                lines[#lines + 1] = FB.COLORS.YELLOW .. "Est. Time to Get: " .. rangeStr .. "|r"
            else
                lines[#lines + 1] = FB.COLORS.YELLOW .. "Est. Time to Get: ~"
                    .. self:FormatDays(item.effectiveDays) .. " (at " .. hoursPerDay .. "h/day)|r"
            end
        elseif item.isUnknownDrop then
            lines[#lines + 1] = FB.COLORS.ORANGE .. "Est. Time to Get: unknown (drop rate not available)|r"
        else
            lines[#lines + 1] = FB.COLORS.YELLOW .. "Est. Time to Get: ~"
                .. self:FormatDays(item.effectiveDays) .. " (at " .. hoursPerDay .. "h/day)|r"
        end
    end

    if item.immediatelyAvailable ~= nil then
        if item.immediatelyAvailable then
            lines[#lines + 1] = FB.COLORS.GREEN .. "Available right now!|r"
        else
            lines[#lines + 1] = FB.COLORS.RED .. "Currently locked this reset|r"
        end
    end

    -- FIX-14: Confidence indicator
    if item.confidencePercent then
        local confColor = FB.CONFIDENCE_COLORS and
            FB.CONFIDENCE_COLORS[item.confidence or "low"] or FB.COLORS.GRAY
        lines[#lines + 1] = ""
        lines[#lines + 1] = confColor .. "Data Confidence: " .. item.confidencePercent .. "%|r"
        -- List estimated fields when not high confidence
        if item.confidence ~= "high" and item.dataQuality then
            local verified = table.concat(item.dataQuality, ", ")
            if verified ~= "" then
                lines[#lines + 1] = FB.COLORS.GRAY .. "  Verified: " .. verified .. "|r"
            end
            local missing = {}
            local allFields = { "drop rate", "instance", "expansion", "clear time" }
            local knownSet = {}
            for _, v in ipairs(item.dataQuality or {}) do knownSet[v] = true end
            for _, f in ipairs(allFields) do
                if not knownSet[f] then missing[#missing + 1] = f end
            end
            if #missing > 0 then
                lines[#lines + 1] = FB.COLORS.GRAY .. "  Estimated: " .. table.concat(missing, ", ") .. "|r"
            end
        end
    end

    -- WoWHead link hint
    if item.id then
        lines[#lines + 1] = ""
        lines[#lines + 1] = FB.COLORS.GRAY .. "WoWHead: wowhead.com/spell=" .. item.id .. "|r"
    end

    -- Steps section
    local steps = item.steps
    if not steps or #steps == 0 then
        steps = self:BuildMountAutoSteps(item)
    end

    if #steps > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = FB.COLORS.YELLOW .. "How to Get:|r"
        for i, step in ipairs(steps) do
            lines[#lines + 1] = "  " .. i .. ". " .. step
        end
    end

    return lines, steps
end
