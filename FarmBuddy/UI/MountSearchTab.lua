local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.MountSearchTab = {}

local panel
local scrollList
local filterBar
local searchBox
local progressBar = nil  -- #21: replaces loadingLabel
local allMountData = nil
local selectedMount = nil
local loadHandle = nil

function FB.UI.MountSearchTab:Init(parentPanel)
    panel = parentPanel

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 5, -5)
    title:SetText("Mount Search")

    -- Search box (manual editbox - no template dependency)
    searchBox = CreateFrame("EditBox", "FarmBuddyMountSearch", panel, "BackdropTemplate")
    searchBox:SetSize(200, 22)
    searchBox:SetPoint("TOPRIGHT", -5, -5)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("ChatFontNormal")
    searchBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    searchBox:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    searchBox:SetTextInsets(6, 6, 0, 0)

    -- Placeholder text
    local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    placeholder:SetPoint("LEFT", 6, 0)
    placeholder:SetText("|cFF888888Search mounts...|r")
    searchBox.placeholder = placeholder

    local searchTimer = nil
    searchBox:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then
            placeholder:Show()
        else
            placeholder:Hide()
        end
        -- Debounce: wait 0.3s after last keystroke
        if searchTimer then searchTimer:Cancel() end
        searchTimer = C_Timer.NewTimer(0.3, function()
            FB.UI.MountSearchTab:ApplyFilters()
        end)
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEditFocusGained", function(self) placeholder:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then placeholder:Show() end
    end)

    -- Filter bar
    filterBar = FB.UI.Widgets:CreateFilterBar(panel, "FarmBuddyMountSearchFilters")
    filterBar.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -30)
    filterBar.frame:SetPoint("RIGHT", panel, "RIGHT", -5, 0)

    -- Source type dropdown
    filterBar:AddDropdown("sourceType", "Source", FB.SOURCE_TYPE_NAMES)

    -- Expansion dropdown
    local expOptions = {}
    for key, data in pairs(FB.ExpansionData) do
        expOptions[key] = data.name
    end
    filterBar:AddDropdown("expansion", "Expansion", expOptions)

    -- Collected checkbox
    filterBar:AddCheckbox("showCollected", "Collected", false)

    filterBar:SetOnChange(function()
        FB.UI.MountSearchTab:ApplyFilters()
    end)

    -- Left panel: Scroll list (60% width)
    local leftFrame = CreateFrame("Frame", nil, panel)
    leftFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -65)
    leftFrame:SetPoint("BOTTOM", panel, "BOTTOM", 0, 5)
    leftFrame:SetWidth(math.max(300, panel:GetWidth() * 0.6))
    panel:HookScript("OnSizeChanged", function(self)
        leftFrame:SetWidth(math.max(300, self:GetWidth() * 0.6))
    end)

    scrollList = FB.UI.Widgets:CreateScrollList(leftFrame, "FarmBuddyMountSearchList", 34)
    scrollList.frame:SetAllPoints()
    scrollList:SetOnClick(function(item)
        FB.UI.MountSearchTab:SelectMount(item)
    end)
    scrollList:SetOnCtrlClick(function(item)
        if item and item.mountID then
            FB.Utils:OpenMountJournal(item.mountID)
        end
    end)

    -- Right panel: shared detail panel
    local rightFrame = CreateFrame("Frame", nil, panel)
    rightFrame:SetPoint("TOPLEFT", leftFrame, "TOPRIGHT", 10, 0)
    rightFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 5)

    local detailPanel = FB.UI.Widgets:CreateMountDetailPanel(rightFrame, "FarmBuddySearchDetail")
    detailPanel.frame:SetAllPoints()
    self.detailPanel = detailPanel

    -- #21: Progress bar replaces plain loadingLabel during async mount load
    progressBar = FB.UI.Widgets:CreateProgressBar(panel, "FBSearchProgress")
    progressBar.frame:SetPoint("TOPLEFT", filterBar.frame, "BOTTOMLEFT", 0, -5)
    progressBar.frame:SetPoint("RIGHT", panel, "RIGHT", -5, 0)
    progressBar.frame:Hide()
    -- No cancel callback needed for the load operation
end

function FB.UI.MountSearchTab:OnShow()
    if not allMountData and not loadHandle then
        self:LoadAllMounts()
    end
end

function FB.UI.MountSearchTab:LoadAllMounts()
    local mountIDs = C_MountJournal.GetMountIDs()
    if not mountIDs then return end

    local weights = FB.Scoring:GetWeights()

    -- Set immediately to prevent re-entry (async runs over multiple frames)
    allMountData = {}

    -- #21: Show progress bar during async load, hide filter bar to avoid overlap
    if progressBar then
        progressBar:SetProgress(0, #mountIDs)
        progressBar:SetText("Loading mounts... 0 / " .. #mountIDs)
        progressBar.frame:Show()
    end

    loadHandle = FB.Async:RunBatched(
        mountIDs,
        function(mountID)
            local name, spellID, icon, isActive, isUsable, sourceType, isFavorite,
                  isFactionSpecific, faction, hideOnChar, isCollected =
                  C_MountJournal.GetMountInfoByID(mountID)

            -- Skip mounts hidden from this character (wrong faction, class-locked, etc.)
            if hideOnChar then return nil end
            if not (name and spellID) then return nil end

            local creatureDisplayID, descriptionText, sourceText =
                  C_MountJournal.GetMountInfoExtraByID(mountID)

            local entry

            if not isCollected then
                -- Uncollected: run through Resolver + Scorer for full enrichment
                -- Wrap in pcall to prevent a single mount error from killing the entire list
                local resolveOk, input = pcall(FB.Mounts.Resolver.Resolve, FB.Mounts.Resolver, mountID)
                if not resolveOk then
                    FB:Debug("Search: Resolve error on mount " .. tostring(mountID) .. ": " .. tostring(input))
                    input = nil
                end

                if input then
                    -- Score it (only if scoreable source type)
                    local result
                    if FB.Scoring:IsScoreable(input.sourceType) then
                        local scoreOk, scoreResult = pcall(FB.Scoring.Score, FB.Scoring, input, weights)
                        if scoreOk then
                            result = scoreResult
                        else
                            FB:Debug("Search: Score error on mount " .. tostring(mountID) .. ": " .. tostring(scoreResult))
                        end
                    end

                    entry = {
                        id = input.id,
                        mountID = input.mountID,
                        name = input.name,
                        icon = input.icon,
                        sourceText = input.sourceText,
                        sourceType = input.sourceType,
                        expansion = input.expansion,
                        creatureDisplayID = input.creatureDisplayID,
                        isCollected = false,
                        steps = input.steps,
                        hasCuratedData = input.hasCuratedData,

                        -- Enriched fields from Resolver
                        groupRequirement = input.groupRequirement,
                        timeGate = input.timeGate,
                        timePerAttempt = input.timePerAttempt,
                        dropChance = input.dropChance,
                        progressRemaining = input.progressRemaining,
                        factionID = input.factionID,
                        targetStanding = input.targetStanding,
                        targetRenown = input.targetRenown,
                        currencyID = input.currencyID,
                        currencyRequired = input.currencyRequired,
                        expectedAttempts = input.expectedAttempts,
                        achievementID = input.achievementID,
                        goldCost = input.goldCost,
                        itemCosts = input.itemCosts,
                        faction = input.faction,
                        isFactionSpecific = input.isFactionSpecific,
                        lockoutInstanceName = input.lockoutInstanceName,
                        difficultyID = input.difficultyID,
                        rarity = input.rarity,

                        -- Score (if available)
                        score = result and result.score or 0,
                        scoreExplanation = result and result.scoreExplanation or nil,
                        components = result and result.components or nil,
                        effectiveDays = result and result.effectiveDays or 0,
                        immediatelyAvailable = (result ~= nil) and result.immediatelyAvailable or false,
                    }
                else
                    -- Resolver returned nil (unobtainable or error) - still show in search with basic data
                    local metaOk, meta = pcall(FB.MountDB.Get, FB.MountDB, spellID)
                    if not metaOk then meta = nil end
                    local resolvedSourceType = meta and meta.sourceType
                        or FB.Mounts.Resolver:ResolveSourceType(sourceType, sourceText)
                    local resolvedExpansion = meta and meta.expansion
                        or FB.Mounts.Resolver:GuessExpansion(sourceText, descriptionText) or ""

                    entry = {
                        id = spellID,
                        mountID = mountID,
                        name = name,
                        icon = icon,
                        sourceText = sourceText or "",
                        sourceType = resolvedSourceType,
                        expansion = resolvedExpansion,
                        creatureDisplayID = creatureDisplayID,
                        isCollected = false,
                        steps = meta and meta.steps,
                        score = 99999,
                        effectiveDays = 99999,
                        immediatelyAvailable = false,
                        hasCuratedData = meta ~= nil,
                        isUnobtainable = true,
                    }
                end
            else
                -- Collected: basic data only (no scoring needed)
                local meta = FB.MountDB:Get(spellID)
                local resolvedSourceType = meta and meta.sourceType
                    or FB.Mounts.Resolver:ResolveSourceType(sourceType, sourceText)
                local resolvedExpansion = meta and meta.expansion
                    or FB.Mounts.Resolver:GuessExpansion(sourceText, descriptionText) or ""

                entry = {
                    id = spellID,
                    mountID = mountID,
                    name = name,
                    icon = icon,
                    sourceText = sourceText or "",
                    sourceType = resolvedSourceType,
                    expansion = resolvedExpansion,
                    creatureDisplayID = creatureDisplayID,
                    isCollected = true,
                    steps = meta and meta.steps,
                    score = 0,
                    effectiveDays = 0,
                    immediatelyAvailable = true,
                    hasCuratedData = meta ~= nil,
                }
            end

            return entry
        end,
        "auto",
        function(current, total)
            -- #21: Update progress bar
            if progressBar then
                progressBar:SetProgress(current, total)
                progressBar:SetText("Loading mounts... " .. current .. " / " .. total)
            end
        end,
        function(results)
            loadHandle = nil

            -- #21: Hide progress bar when complete
            if progressBar then progressBar.frame:Hide() end

            -- Collect results and sort alphabetically
            allMountData = results
            table.sort(allMountData, function(a, b)
                return (a.name or "") < (b.name or "")
            end)

            self:ApplyFilters()
        end
    )
end

function FB.UI.MountSearchTab:ApplyFilters()
    if not allMountData then return end

    local filters = filterBar:GetFilters()
    local searchText = searchBox and searchBox:GetText():lower() or ""
    local filtered = {}

    for _, mount in ipairs(allMountData) do
        local pass = true

        -- Collected filter
        if not filters.showCollected and mount.isCollected then
            pass = false
        end

        -- Source type filter
        if filters.sourceType and mount.sourceType ~= filters.sourceType then
            pass = false
        end

        -- Expansion filter
        if filters.expansion and mount.expansion ~= filters.expansion then
            pass = false
        end

        -- Text search (matches name, source text, or expansion)
        if searchText ~= "" then
            local nameMatch = mount.name:lower():find(searchText, 1, true)
            local sourceMatch = mount.sourceText and mount.sourceText:lower():find(searchText, 1, true)
            local expMatch = mount.expansion and FB:GetExpansionName(mount.expansion)
                and FB:GetExpansionName(mount.expansion):lower():find(searchText, 1, true)
            if not (nameMatch or sourceMatch or expMatch) then
                pass = false
            end
        end

        if pass then
            filtered[#filtered + 1] = mount
        end
    end

    scrollList:SetData(filtered)
end

function FB.UI.MountSearchTab:SelectMount(item)
    if not item then return end
    selectedMount = item

    self.detailPanel:SetMount(item, {
        showCollectionStatus = true,
        showSynergies = false,
        showDiminishingReturns = false,
    })
end
