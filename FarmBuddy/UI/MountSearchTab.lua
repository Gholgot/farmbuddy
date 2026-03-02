local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.MountSearchTab = {}

local panel
local scrollList
local modelPreview
local filterBar
local searchBox
local scoreBar
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

    -- Right panel: Model preview + details
    local rightFrame = CreateFrame("Frame", nil, panel)
    rightFrame:SetPoint("TOPLEFT", leftFrame, "TOPRIGHT", 10, 0)
    rightFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 5)

    modelPreview = FB.UI.Widgets:CreateModelPreview(rightFrame, "FarmBuddyMountPreview")
    modelPreview.frame:SetPoint("TOPLEFT", rightFrame, "TOPLEFT", 0, 0)
    modelPreview.frame:SetPoint("RIGHT", rightFrame, "RIGHT", 0, 0)
    modelPreview.frame:SetHeight(220)

    -- Details frame below model
    local detailsFrame = CreateFrame("Frame", nil, rightFrame, "BackdropTemplate")
    detailsFrame:SetPoint("TOPLEFT", modelPreview.frame, "BOTTOMLEFT", 0, -5)
    detailsFrame:SetPoint("BOTTOMRIGHT", rightFrame, "BOTTOMRIGHT", 0, 0)
    detailsFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    detailsFrame:SetBackdropColor(0.05, 0.05, 0.1, 0.9)

    -- Score breakdown bar (hidden until a mount is selected)
    scoreBar = FB.UI.Widgets:CreateScoreBar(detailsFrame, "FarmBuddyMountSearchScoreBar")
    scoreBar.frame:SetPoint("TOPLEFT", 8, -8)
    scoreBar.frame:SetPoint("RIGHT", -8, 0)

    -- #11: WoWHead button (left of pin button)
    local wowheadBtn = CreateFrame("Button", nil, detailsFrame, "UIPanelButtonTemplate")
    wowheadBtn:SetSize(100, 24)
    wowheadBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    wowheadBtn:SetText("WoWHead")
    wowheadBtn:SetNormalFontObject("GameFontNormalSmall")
    wowheadBtn:SetScript("OnClick", function(self)
        if selectedMount then
            local spellID = selectedMount.id or selectedMount.spellID or selectedMount.mountID
            if spellID then
                local url = "https://www.wowhead.com/spell=" .. spellID
                local eb = _G["FarmBuddyWowheadCopyFrame"]
                if not eb then
                    eb = CreateFrame("EditBox", "FarmBuddyWowheadCopyFrame", UIParent, "BackdropTemplate")
                    eb:SetSize(350, 28)
                    eb:SetFontObject("ChatFontNormal")
                    eb:SetAutoFocus(true)
                    eb:SetBackdrop({
                        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 12,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 },
                    })
                    eb:SetBackdropColor(0.1, 0.1, 0.15, 1.0)
                    eb:SetTextInsets(4, 4, 0, 0)
                    eb:SetFrameStrata("DIALOG")
                    local label = eb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    label:SetPoint("BOTTOM", eb, "TOP", 0, 2)
                    label:SetText(FB.COLORS.GOLD .. "Ctrl+C to copy, Enter or Escape to close|r")
                    eb.label = label
                    eb:SetScript("OnEscapePressed", function(f) f:Hide() end)
                    eb:SetScript("OnEnterPressed", function(f) f:Hide() end)
                end
                eb:ClearAllPoints()
                eb:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
                eb:SetText(url)
                eb:Show()
                eb:HighlightText()
                eb:SetFocus()
            end
        end
    end)
    wowheadBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("WoWHead Link")
        if selectedMount then
            local spellID = selectedMount.id or selectedMount.spellID or selectedMount.mountID
            if spellID then
                GameTooltip:AddLine("wowhead.com/spell=" .. spellID, 0.7, 0.7, 0.7)
            end
        end
        GameTooltip:AddLine("Click to copy link to clipboard", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    wowheadBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    wowheadBtn:Hide()
    self.wowheadBtn = wowheadBtn

    -- Pin button (left of WoWHead button)
    local pinBtn = CreateFrame("Button", nil, detailsFrame, "UIPanelButtonTemplate")
    pinBtn:SetSize(120, 24)
    pinBtn:SetPoint("RIGHT", wowheadBtn, "LEFT", -6, 0)
    pinBtn:SetText("Pin to Tracker")
    pinBtn:SetScript("OnClick", function()
        if selectedMount and selectedMount.id then
            local steps = selectedMount._resolvedSteps or selectedMount.steps or {}
            if #steps == 0 then
                steps = FB.Utils:BuildMountAutoSteps(selectedMount)
            end
            FB.Tracker:Pin("mount", selectedMount.id, selectedMount.name, steps)
            FB:Print("Pinned: " .. selectedMount.name)
        end
    end)
    pinBtn:Hide()
    self.pinBtn = pinBtn

    -- #8: Structured detail header (name + subtitle + separator), anchored above scroll
    local detailHeader = detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detailHeader:SetPoint("TOPLEFT", scoreBar.frame, "BOTTOMLEFT", 0, -6)
    detailHeader:SetPoint("RIGHT", detailsFrame, "RIGHT", -8, 0)
    detailHeader:SetJustifyH("LEFT")
    detailHeader:SetWordWrap(false)
    detailHeader:SetText("")
    self.detailHeader = detailHeader

    local detailSubtitle = detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailSubtitle:SetPoint("TOPLEFT", detailHeader, "BOTTOMLEFT", 0, -2)
    detailSubtitle:SetPoint("RIGHT", detailsFrame, "RIGHT", -8, 0)
    detailSubtitle:SetJustifyH("LEFT")
    detailSubtitle:SetTextColor(0.6, 0.6, 0.6)
    detailSubtitle:SetText("")
    self.detailSubtitle = detailSubtitle

    local detailSeparator = detailsFrame:CreateTexture(nil, "ARTWORK")
    detailSeparator:SetHeight(1)
    detailSeparator:SetPoint("TOPLEFT", detailSubtitle, "BOTTOMLEFT", 0, -4)
    detailSeparator:SetPoint("RIGHT", detailsFrame, "RIGHT", -8, 0)
    detailSeparator:SetColorTexture(0.35, 0.35, 0.35, 0.8)
    self.detailSeparator = detailSeparator

    -- Scrollable detail text area (prevents overlap with pin button)
    local detailScroll = CreateFrame("ScrollFrame", "FarmBuddySearchDetailScroll", detailsFrame)
    detailScroll:SetPoint("TOPLEFT", detailSeparator, "BOTTOMLEFT", 0, -4)
    detailScroll:SetPoint("RIGHT", detailsFrame, "RIGHT", -24, 0)
    detailScroll:SetPoint("BOTTOM", pinBtn, "TOP", 0, 4)
    detailScroll:EnableMouseWheel(true)

    local detailChild = CreateFrame("Frame", nil, detailScroll)
    detailChild:SetSize(300, 1)  -- Width will be updated on size change
    detailScroll:SetScrollChild(detailChild)

    local detailText = detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailText:SetPoint("TOPLEFT", 0, 0)
    detailText:SetWidth(300)  -- Will be updated on size change
    detailText:SetJustifyH("LEFT")
    detailText:SetWordWrap(true)
    detailText:SetText(FB.COLORS.GRAY .. "Select a mount for details|r")
    self.detailText = detailText

    -- Scroll bar (thin track on the right)
    local detailScrollBar = CreateFrame("Slider", "FarmBuddySearchDetailScrollBar", detailsFrame, "BackdropTemplate")
    detailScrollBar:SetPoint("TOPLEFT", detailScroll, "TOPRIGHT", 4, 0)
    detailScrollBar:SetPoint("BOTTOMLEFT", detailScroll, "BOTTOMRIGHT", 4, 0)
    detailScrollBar:SetWidth(12)
    detailScrollBar:SetOrientation("VERTICAL")
    detailScrollBar:SetMinMaxValues(0, 1)
    detailScrollBar:SetValue(0)
    detailScrollBar:SetValueStep(20)
    detailScrollBar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    detailScrollBar:SetBackdropColor(0.05, 0.05, 0.05, 0.5)
    local detailThumb = detailScrollBar:CreateTexture(nil, "OVERLAY")
    detailThumb:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    detailThumb:SetSize(8, 30)
    detailScrollBar:SetThumbTexture(detailThumb)
    detailScrollBar:Hide()

    detailScrollBar:SetScript("OnValueChanged", function(self, value)
        detailScroll:SetVerticalScroll(value)
    end)

    -- Mouse wheel scrolling
    detailScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = math.max(0, detailChild:GetHeight() - self:GetHeight())
        local newScroll = math.max(0, math.min(maxScroll, current - (delta * 30)))
        self:SetVerticalScroll(newScroll)
        detailScrollBar:SetValue(newScroll)
    end)

    -- Keep child width in sync with scroll frame width
    detailScroll:SetScript("OnSizeChanged", function(self, w, h)
        if w and w > 10 then
            detailChild:SetWidth(w)
            detailText:SetWidth(w)
        end
    end)

    self.detailScroll = detailScroll
    self.detailChild = detailChild
    self.detailScrollBar = detailScrollBar

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

    -- Update model preview
    if item.creatureDisplayID then
        modelPreview:SetMount(item.creatureDisplayID, item.name)
    else
        modelPreview:Clear()
    end

    -- Update score bar (show for uncollected mounts with score data)
    if not item.isCollected and item.components then
        scoreBar:SetScore({
            score = item.score,
            components = item.components,
        })
    else
        scoreBar:SetScore(nil)
    end

    -- #8: Use structured detail data to populate header, subtitle, and body separately
    local detailData = FB.Utils:BuildMountDetailData(item, true)

    if self.detailHeader then
        self.detailHeader:SetText(detailData.name)
    end
    if self.detailSubtitle then
        self.detailSubtitle:SetText(detailData.subtitle)
    end

    -- Store resolved steps for the pin button
    selectedMount._resolvedSteps = detailData.steps

    self.detailText:SetText(detailData.detailText)

    -- Resize scroll child to fit text and reset scroll position
    C_Timer.After(0, function()
        if self.detailText and self.detailChild and self.detailScroll then
            local scrollWidth = self.detailScroll:GetWidth()
            if scrollWidth and scrollWidth > 10 then
                self.detailChild:SetWidth(scrollWidth)
                self.detailText:SetWidth(scrollWidth)
            end
            local textHeight = self.detailText:GetStringHeight() or 100
            self.detailChild:SetHeight(textHeight + 8)
            self.detailScroll:SetVerticalScroll(0)

            -- Update scrollbar
            local maxScroll = math.max(0, textHeight + 8 - self.detailScroll:GetHeight())
            if self.detailScrollBar then
                if maxScroll > 0 then
                    self.detailScrollBar:SetMinMaxValues(0, maxScroll)
                    self.detailScrollBar:SetValue(0)
                    self.detailScrollBar:Show()
                else
                    self.detailScrollBar:Hide()
                end
            end
        end
    end)

    -- #11: Show pin button for all mounts (collected or not — users may want to track them)
    self.pinBtn:Show()

    -- #11: Show WoWHead button for any selected mount
    if self.wowheadBtn then
        self.wowheadBtn:Show()
    end
end
