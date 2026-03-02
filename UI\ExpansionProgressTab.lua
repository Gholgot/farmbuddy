local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.ExpansionProgressTab = {}

local panel
local scrollFrame
local scrollBar
local contentFrame
local allRows = {}           -- Array of created frame rows for cleanup
local expandedExpansions = {} -- { [expansionKey] = true } for expanded state

-- Filter state
local filterShowCollected = true
local filterShowUncollected = true
local filterSourceType = nil
local searchText = ""

-- Cached scan data: { [key] = { name, order, total, collected, mounts = {...} } }
local expansionData = nil

-- ============================================================================
-- Data Scanning
-- ============================================================================

-- Scan all mounts and group by expansion
local function ScanMountsByExpansion()
    local data = {}

    -- Initialize expansion buckets from constants
    for key, name in pairs(FB.EXPANSION_NAMES) do
        data[key] = {
            name = name,
            order = FB.Data and FB.Data.ExpansionOrder and FB.Data.ExpansionOrder[key] or 0,
            total = 0,
            collected = 0,
            mounts = {},
        }
    end
    data["UNKNOWN"] = { name = "Unknown", order = -1, total = 0, collected = 0, mounts = {} }

    -- Assign order based on known expansion sequence
    local EXPANSION_ORDER = {
        CLASSIC = 0, TBC = 1, WOTLK = 2, CATA = 3, MOP = 4,
        WOD = 5, LEGION = 6, BFA = 7, SL = 8, DF = 9, TWW = 10, MIDNIGHT = 11,
    }
    for key, expData in pairs(data) do
        if EXPANSION_ORDER[key] then
            expData.order = EXPANSION_ORDER[key]
        end
    end

    -- Scan all mounts from the journal
    local allMountIDs = C_MountJournal.GetMountIDs()
    if not allMountIDs then return data end

    for _, mountID in ipairs(allMountIDs) do
        local ok, name, spellID, icon, _, _, blizzSourceType, _, isFactionSpecific,
              faction, hideOnChar, isCollected = pcall(C_MountJournal.GetMountInfoByID, mountID)

        if ok and spellID then
            -- Determine expansion from generated DB or curated DB
            local expansion = nil
            local resolvedSourceType = nil

            local genMeta = FB.MountDB_Generated and FB.MountDB_Generated[spellID]
            if genMeta then
                expansion = genMeta.expansion
                resolvedSourceType = genMeta.sourceType
            end
            if not expansion then
                local curMeta = FB.MountDB and FB.MountDB.entries and FB.MountDB.entries[spellID]
                if curMeta then
                    expansion = expansion or curMeta.expansion
                    resolvedSourceType = resolvedSourceType or curMeta.sourceType
                end
            end
            if not resolvedSourceType then
                resolvedSourceType = "unknown"
            end

            -- Get sourceText for unobtainable check
            local extraOk, _, _, sourceText = pcall(C_MountJournal.GetMountInfoExtraByID, mountID)
            if not extraOk then sourceText = "" end

            -- Check if unobtainable
            local isUnobtainable = false
            if FB.Mounts and FB.Mounts.Resolver and FB.Mounts.Resolver.IsUnobtainable then
                local uOk, uResult = pcall(FB.Mounts.Resolver.IsUnobtainable,
                    FB.Mounts.Resolver, blizzSourceType, sourceText or "", hideOnChar, name)
                if uOk then isUnobtainable = uResult end
            end

            -- Check if scoreable
            local scoreable = FB.Scoring and FB.Scoring.IsScoreable
                and FB.Scoring:IsScoreable(resolvedSourceType)

            -- Include obtainable mounts (scoreable and not explicitly unobtainable)
            if scoreable and not isUnobtainable then
                local bucket = expansion and data[expansion] or data["UNKNOWN"]
                if bucket then
                    bucket.total = bucket.total + 1
                    if isCollected then
                        bucket.collected = bucket.collected + 1
                    end
                    bucket.mounts[#bucket.mounts + 1] = {
                        mountID = mountID,
                        spellID = spellID,
                        name = name or "Unknown",
                        icon = icon,
                        isCollected = isCollected or false,
                        sourceType = resolvedSourceType,
                        faction = isFactionSpecific and faction or nil,
                    }
                end
            end
        end
    end

    -- Sort mounts within each expansion: uncollected first, then alphabetically
    for _, expData in pairs(data) do
        table.sort(expData.mounts, function(a, b)
            if a.isCollected ~= b.isCollected then
                return not a.isCollected
            end
            return (a.name or "") < (b.name or "")
        end)
    end

    return data
end

-- ============================================================================
-- Rendering
-- ============================================================================

-- Clean up all dynamically created frames
local function ClearRows()
    for _, row in ipairs(allRows) do
        if row and row.Hide then
            row:Hide()
            row:ClearAllPoints()
        end
    end
    allRows = {}
end

-- Check if a mount passes current filters
local function PassesFilter(mount)
    -- Collected / uncollected toggle
    if mount.isCollected and not filterShowCollected then return false end
    if not mount.isCollected and not filterShowUncollected then return false end

    -- Source type filter
    if filterSourceType and mount.sourceType ~= filterSourceType then return false end

    -- Search text
    if searchText and searchText ~= "" then
        local lower = (mount.name or ""):lower()
        if not lower:find(searchText:lower(), 1, true) then return false end
    end

    return true
end

function FB.UI.ExpansionProgressTab:Render()
    if not expansionData or not contentFrame then return end

    -- #16: Save scroll position before clearing rows
    local savedScroll = scrollFrame and scrollFrame:GetVerticalScroll() or 0

    ClearRows()

    local y = -5
    local ROW_HEIGHT = 30
    local MOUNT_ROW_HEIGHT = 22
    local contentWidth = scrollFrame:GetWidth() or 800

    -- Sort expansions by order (newest first)
    local sortedExpansions = {}
    for key, expData in pairs(expansionData) do
        if expData.total > 0 then
            sortedExpansions[#sortedExpansions + 1] = { key = key, data = expData }
        end
    end
    table.sort(sortedExpansions, function(a, b)
        return (a.data.order or 0) > (b.data.order or 0)
    end)

    for _, entry in ipairs(sortedExpansions) do
        local key = entry.key
        local expData = entry.data

        -- Count filtered mounts (for display totals)
        local filteredTotal = 0
        local filteredCollected = 0
        for _, mount in ipairs(expData.mounts) do
            if PassesFilter(mount) then
                filteredTotal = filteredTotal + 1
                if mount.isCollected then
                    filteredCollected = filteredCollected + 1
                end
            end
        end

        -- Skip empty expansions after filtering
        if filteredTotal == 0 and not expandedExpansions[key] then
            -- Still show header for context, but only if unfiltered total > 0
            if expData.total > 0 then
                filteredTotal = expData.total
                filteredCollected = expData.collected
            else
                -- skip
            end
        end

        if filteredTotal > 0 or expandedExpansions[key] then
            local pct = filteredTotal > 0
                and math.floor((filteredCollected / filteredTotal) * 100) or 0

            -- === Expansion header row ===
            local headerFrame = CreateFrame("Button", nil, contentFrame)
            headerFrame:SetPoint("TOPLEFT", 0, y)
            headerFrame:SetSize(contentWidth, ROW_HEIGHT)
            allRows[#allRows + 1] = headerFrame

            -- Background
            local bg = headerFrame:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.12, 0.12, 0.15, 0.9)

            -- Expand/collapse arrow
            local arrow = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            arrow:SetPoint("LEFT", 8, 0)
            arrow:SetText(expandedExpansions[key] and "v" or ">")
            arrow:SetTextColor(0.7, 0.7, 0.7)

            -- Expansion name
            local nameLabel = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameLabel:SetPoint("LEFT", 28, 0)
            nameLabel:SetText(FB.COLORS.GOLD .. expData.name .. "|r")

            -- Count: "X / Y"
            local countLabel = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            countLabel:SetPoint("RIGHT", -160, 0)
            local countColor = pct == 100 and FB.COLORS.GREEN or FB.COLORS.WHITE
            countLabel:SetText(countColor .. filteredCollected .. " / " .. filteredTotal .. "|r")

            -- Percentage
            local pctLabel = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            pctLabel:SetPoint("RIGHT", -110, 0)
            local pctColor
            if pct >= 100 then pctColor = FB.COLORS.GREEN
            elseif pct >= 75 then pctColor = FB.COLORS.YELLOW
            elseif pct >= 50 then pctColor = FB.COLORS.ORANGE
            else pctColor = FB.COLORS.RED end
            pctLabel:SetText(pctColor .. pct .. "%|r")

            -- Mini progress bar background
            local barBg = headerFrame:CreateTexture(nil, "ARTWORK")
            barBg:SetPoint("RIGHT", -5, 0)
            barBg:SetSize(95, 14)
            barBg:SetColorTexture(0.1, 0.1, 0.1, 1)

            -- Progress bar fill
            local fillWidth = math.max(1, 93 * (pct / 100))
            local barFill = headerFrame:CreateTexture(nil, "OVERLAY")
            barFill:SetPoint("LEFT", barBg, "LEFT", 1, 0)
            barFill:SetSize(fillWidth, 12)
            -- Color gradient: red → orange → yellow → green
            local r, g = 1.0, 0.0
            if pct < 50 then
                r = 1.0; g = pct / 50
            else
                r = 1.0 - ((pct - 50) / 50); g = 1.0
            end
            barFill:SetColorTexture(r, g, 0.0, 0.8)

            -- Click to expand/collapse
            headerFrame:SetScript("OnClick", function()
                expandedExpansions[key] = not expandedExpansions[key]
                FB.UI.ExpansionProgressTab:Render()
            end)

            -- Highlight on hover
            local hl = headerFrame:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.3, 0.6, 1.0, 0.12)

            y = y - ROW_HEIGHT

            -- === Expanded mount rows ===
            if expandedExpansions[key] then
                for _, mount in ipairs(expData.mounts) do
                    if PassesFilter(mount) then
                        local mountRow = CreateFrame("Button", nil, contentFrame)
                        mountRow:SetPoint("TOPLEFT", 20, y)
                        mountRow:SetSize(contentWidth - 20, MOUNT_ROW_HEIGHT)
                        allRows[#allRows + 1] = mountRow

                        -- Alternating row background
                        local rowBg = mountRow:CreateTexture(nil, "BACKGROUND")
                        rowBg:SetAllPoints()
                        rowBg:SetColorTexture(0.08, 0.08, 0.10, 0.5)

                        -- Mount icon
                        local iconTex = mountRow:CreateTexture(nil, "ARTWORK")
                        iconTex:SetSize(18, 18)
                        iconTex:SetPoint("LEFT", 5, 0)
                        iconTex:SetTexture(mount.icon)
                        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                        -- Mount name (green = collected, white = missing)
                        local nameStr = mountRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        nameStr:SetPoint("LEFT", iconTex, "RIGHT", 5, 0)
                        nameStr:SetWidth(260)
                        nameStr:SetJustifyH("LEFT")
                        nameStr:SetWordWrap(false)
                        if mount.isCollected then
                            nameStr:SetText(FB.COLORS.GREEN .. mount.name .. "|r")
                        else
                            nameStr:SetText(FB.COLORS.WHITE .. mount.name .. "|r")
                        end

                        -- Source type label
                        local srcStr = mountRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        srcStr:SetPoint("LEFT", nameStr, "RIGHT", 10, 0)
                        srcStr:SetWidth(120)
                        srcStr:SetJustifyH("LEFT")
                        srcStr:SetText(FB.COLORS.GRAY
                            .. (FB.SOURCE_TYPE_NAMES[mount.sourceType] or "Unknown") .. "|r")

                        -- Collected status
                        local statusStr = mountRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        statusStr:SetPoint("RIGHT", -10, 0)
                        if mount.isCollected then
                            statusStr:SetText("|TInterface\\RAIDFRAME\\ReadyCheck-Ready:14:14|t")
                        else
                            statusStr:SetText(FB.COLORS.RED .. "Missing|r")
                        end

                        -- Faction indicator (if faction-specific)
                        if mount.faction then
                            local factionStr = mountRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            factionStr:SetPoint("RIGHT", statusStr, "LEFT", -8, 0)
                            if mount.faction == "ALLIANCE" or mount.faction == 0 then
                                factionStr:SetText("|cFF0070DDA|r")
                            else
                                factionStr:SetText("|cFFFF2020H|r")
                            end
                        end

                        -- Click: show tooltip with rich info; Ctrl+Click: open Mount Journal
                        mountRow:SetScript("OnClick", function()
                            if IsControlKeyDown() then
                                FB.Utils:OpenMountJournal(mount.mountID)
                            end
                            -- Regular click: tooltip already visible via OnEnter, no extra action needed
                        end)

                        -- Rich tooltip on hover
                        mountRow:SetScript("OnEnter", function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            -- Mount name as header
                            if mount.isCollected then
                                GameTooltip:SetText(FB.COLORS.GREEN .. mount.name .. "|r")
                            else
                                GameTooltip:SetText(mount.name)
                            end

                            -- Source type
                            local srcName = FB.SOURCE_TYPE_NAMES[mount.sourceType] or "Unknown"
                            GameTooltip:AddLine("Source: " .. srcName, 0.8, 0.8, 0.8)

                            -- Drop chance (for drop-type sources)
                            if FB.DROP_SOURCE_TYPES and FB.DROP_SOURCE_TYPES[mount.sourceType] then
                                -- Look up cached score data for drop chance
                                local dropChanceStr = nil
                                if FB.db and FB.db.cachedMountScores then
                                    for _, cached in ipairs(FB.db.cachedMountScores) do
                                        if cached.mountID == mount.mountID then
                                            if cached.dropChance and cached.dropChance > 0 then
                                                dropChanceStr = string.format("%.2f%%", cached.dropChance * 100)
                                            end
                                            break
                                        end
                                    end
                                end
                                if dropChanceStr then
                                    GameTooltip:AddLine("Drop Chance: " .. dropChanceStr, 0.7, 0.9, 1.0)
                                end
                            end

                            -- Group requirement (from cached score data)
                            if FB.db and FB.db.cachedMountScores then
                                for _, cached in ipairs(FB.db.cachedMountScores) do
                                    if cached.mountID == mount.mountID then
                                        if cached.groupRequirement and cached.groupRequirement ~= "solo" then
                                            local grpName = FB.GROUP_NAMES and FB.GROUP_NAMES[cached.groupRequirement]
                                                or cached.groupRequirement
                                            GameTooltip:AddLine("Requires: " .. grpName, 1.0, 0.6, 0.2)
                                        end
                                        break
                                    end
                                end
                            end

                            -- Faction restriction
                            if mount.faction then
                                if mount.faction == "ALLIANCE" or mount.faction == 0 then
                                    GameTooltip:AddLine("Alliance Only", 0.0, 0.44, 0.87)
                                else
                                    GameTooltip:AddLine("Horde Only", 0.87, 0.13, 0.13)
                                end
                            end

                            -- Collection status
                            GameTooltip:AddLine(" ")
                            if mount.isCollected then
                                GameTooltip:AddLine("|TInterface\\RAIDFRAME\\ReadyCheck-Ready:14:14|t Collected", 0, 1, 0)
                            else
                                GameTooltip:AddLine("|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:14:14|t Not Collected", 1, 0.2, 0.2)
                            end

                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine("Click to focus  |  Ctrl+Click: Mount Journal", 0.5, 0.5, 0.5)
                            GameTooltip:Show()
                        end)
                        mountRow:SetScript("OnLeave", function()
                            GameTooltip:Hide()
                        end)

                        -- Row highlight
                        local mhl = mountRow:CreateTexture(nil, "HIGHLIGHT")
                        mhl:SetAllPoints()
                        mhl:SetColorTexture(0.2, 0.4, 0.8, 0.08)

                        y = y - MOUNT_ROW_HEIGHT
                    end
                end
            end
        end
    end

    -- Set content frame size for scrolling
    contentFrame:SetSize(contentWidth, math.abs(y) + 20)

    -- Update scrollbar
    local maxScroll = math.max(0, contentFrame:GetHeight() - scrollFrame:GetHeight())
    if maxScroll <= 0 then
        scrollBar:Hide()
        scrollFrame:SetVerticalScroll(0)
    else
        scrollBar:Show()
        scrollBar:SetMinMaxValues(0, maxScroll)
        -- #16: Restore previous scroll position (clamped to new max)
        local restoredScroll = math.min(savedScroll, maxScroll)
        scrollFrame:SetVerticalScroll(restoredScroll)
        scrollBar:SetValue(restoredScroll)
    end
end

-- ============================================================================
-- Initialization
-- ============================================================================

function FB.UI.ExpansionProgressTab:Init(parentPanel)
    panel = parentPanel

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 5, -5)
    title:SetText("Expansion Mount Progress")

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 24)
    refreshBtn:SetPoint("TOPRIGHT", -5, -5)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        expansionData = nil
        FB.UI.ExpansionProgressTab:OnShow()
    end)

    -- Filter row
    local filterRow = CreateFrame("Frame", nil, panel)
    filterRow:SetPoint("TOPLEFT", 5, -30)
    filterRow:SetPoint("RIGHT", -5, 0)
    filterRow:SetHeight(26)

    -- Search box
    local searchLabel = filterRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("LEFT", 0, 0)
    searchLabel:SetText("Search:")

    local searchBoxFrame = CreateFrame("EditBox", "FarmBuddyExpSearch", filterRow, "BackdropTemplate")
    searchBoxFrame:SetSize(130, 20)
    searchBoxFrame:SetPoint("LEFT", searchLabel, "RIGHT", 4, 0)
    searchBoxFrame:SetFontObject("ChatFontNormal")
    searchBoxFrame:SetAutoFocus(false)
    searchBoxFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    searchBoxFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    searchBoxFrame:SetTextInsets(4, 4, 0, 0)
    searchBoxFrame:SetMaxLetters(40)
    searchBoxFrame:SetScript("OnTextChanged", function(self)
        searchText = self:GetText() or ""
        FB.UI.ExpansionProgressTab:Render()
    end)
    searchBoxFrame:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBoxFrame:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Show Collected checkbox
    local collectedCB = CreateFrame("CheckButton", "FarmBuddyExpCBCollected", filterRow, "UICheckButtonTemplate")
    collectedCB:SetSize(22, 22)
    collectedCB:SetPoint("LEFT", searchBoxFrame, "RIGHT", 8, 0)
    collectedCB:SetChecked(true)
    local collectedLabel = collectedCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    collectedLabel:SetPoint("LEFT", collectedCB, "RIGHT", 2, 0)
    collectedLabel:SetText("Collected")
    collectedCB:SetScript("OnClick", function(self)
        filterShowCollected = self:GetChecked()
        FB.UI.ExpansionProgressTab:Render()
    end)

    -- Show Uncollected checkbox
    local uncollectedCB = CreateFrame("CheckButton", "FarmBuddyExpCBUncollected", filterRow, "UICheckButtonTemplate")
    uncollectedCB:SetSize(22, 22)
    uncollectedCB:SetPoint("LEFT", collectedLabel, "RIGHT", 8, 0)
    uncollectedCB:SetChecked(true)
    local uncollectedLabel = uncollectedCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    uncollectedLabel:SetPoint("LEFT", uncollectedCB, "RIGHT", 2, 0)
    uncollectedLabel:SetText("Uncollected")
    uncollectedCB:SetScript("OnClick", function(self)
        filterShowUncollected = self:GetChecked()
        FB.UI.ExpansionProgressTab:Render()
    end)

    -- Source Type dropdown
    local srcLabel = filterRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    srcLabel:SetPoint("LEFT", uncollectedLabel, "RIGHT", 12, 0)
    srcLabel:SetText("Source:")

    local srcBtn = CreateFrame("Button", "FarmBuddyExpSrcDD", filterRow, "BackdropTemplate")
    srcBtn:SetSize(110, 20)
    srcBtn:SetPoint("LEFT", srcLabel, "RIGHT", 4, 0)
    srcBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    srcBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

    local srcText = srcBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    srcText:SetPoint("LEFT", 6, 0)
    srcText:SetPoint("RIGHT", -16, 0)
    srcText:SetJustifyH("LEFT")
    srcText:SetText("All")

    local srcArrow = srcBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    srcArrow:SetPoint("RIGHT", -4, 0)
    srcArrow:SetText("v")

    srcBtn:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
                rootDescription:CreateButton("All Sources", function()
                    filterSourceType = nil
                    srcText:SetText("All")
                    FB.UI.ExpansionProgressTab:Render()
                end)
                -- Source types to show
                local sourceTypes = {
                    "raid_drop", "dungeon_drop", "world_drop", "world_boss",
                    "reputation", "currency", "quest_chain", "achievement",
                    "vendor", "profession", "pvp", "event", "trading_post",
                }
                for _, st in ipairs(sourceTypes) do
                    local displayName = FB.SOURCE_TYPE_NAMES[st] or st
                    rootDescription:CreateButton(displayName, function()
                        filterSourceType = st
                        srcText:SetText(displayName)
                        FB.UI.ExpansionProgressTab:Render()
                    end)
                end
            end)
        else
            -- Fallback: cycle through common source types
            local types = { nil, "raid_drop", "dungeon_drop", "world_drop", "reputation",
                            "currency", "achievement", "vendor" }
            local currentIdx = 1
            for i, t in ipairs(types) do
                if t == filterSourceType then currentIdx = i; break end
            end
            currentIdx = (currentIdx % #types) + 1
            filterSourceType = types[currentIdx]
            srcText:SetText(filterSourceType and (FB.SOURCE_TYPE_NAMES[filterSourceType] or filterSourceType) or "All")
            FB.UI.ExpansionProgressTab:Render()
        end
    end)

    -- Scroll frame
    scrollFrame = CreateFrame("ScrollFrame", "FarmBuddyExpProgressScroll", panel)
    scrollFrame:SetPoint("TOPLEFT", 5, -58)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 12)

    contentFrame = CreateFrame("Frame", "FarmBuddyExpProgressContent", scrollFrame)
    contentFrame:SetSize(1, 1)
    scrollFrame:SetScrollChild(contentFrame)

    -- Scrollbar
    scrollBar = CreateFrame("Slider", "FarmBuddyExpProgressScrollBar", panel, "BackdropTemplate")
    scrollBar:SetPoint("TOPRIGHT", -6, -58)
    scrollBar:SetPoint("BOTTOMRIGHT", -6, 12)
    scrollBar:SetWidth(16)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    scrollBar:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
    scrollBar:SetMinMaxValues(0, 1)
    scrollBar:SetValue(0)
    scrollBar:SetValueStep(20)

    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    thumb:SetSize(12, 40)
    scrollBar:SetThumbTexture(thumb)

    scrollBar:SetScript("OnValueChanged", function(self, value)
        if scrollFrame then
            scrollFrame:SetVerticalScroll(value)
        end
    end)
    scrollBar:Hide()

    -- Mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = math.max(0, contentFrame:GetHeight() - self:GetHeight())
        local newScroll = math.max(0, math.min(maxScroll, current - (delta * 40)))
        self:SetVerticalScroll(newScroll)
        scrollBar:SetValue(newScroll)
    end)
end

function FB.UI.ExpansionProgressTab:OnShow()
    if not expansionData then
        expansionData = ScanMountsByExpansion()
    end
    self:Render()
end
