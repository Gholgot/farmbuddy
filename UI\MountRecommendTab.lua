local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.MountRecommendTab = {}

local panel
local scrollList
local progressBar
local filterBar
local scoreBar
local modelPreview
local scanResults = nil
local selectedMount = nil
local scanHandle = nil

function FB.UI.MountRecommendTab:Init(parentPanel)
    panel = parentPanel

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 5, -5)
    title:SetText("Mount Recommendations")

    -- Scan button
    local scanBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scanBtn:SetSize(100, 24)
    scanBtn:SetPoint("TOPRIGHT", -5, -5)
    scanBtn:SetText("Scan Mounts")
    scanBtn:SetScript("OnClick", function()
        FB.UI.MountRecommendTab:StartScan()
    end)
    self.scanBtn = scanBtn

    -- Progress bar
    progressBar = FB.UI.Widgets:CreateProgressBar(panel, "FarmBuddyMountScanProgress")
    progressBar.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -35)
    progressBar.frame:SetPoint("RIGHT", panel, "RIGHT", -5, 0)
    progressBar:SetOnCancel(function()
        FB.UI.MountRecommendTab:CancelScan()
    end)

    -- Filter bar
    filterBar = FB.UI.Widgets:CreateFilterBar(panel, "FarmBuddyMountRecommendFilters")
    filterBar.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -35)
    filterBar.frame:SetPoint("RIGHT", panel, "RIGHT", -5, 0)

    filterBar:AddCheckbox("showRaidDrop", "Raid", true)
    filterBar:AddCheckbox("showDungeonDrop", "Dung", true)
    filterBar:AddCheckbox("showWorldDrop", "World", true)
    filterBar:AddCheckbox("showReputation", "Rep", true)
    filterBar:AddCheckbox("showCurrency", "Cur", true)
    filterBar:AddCheckbox("showQuestChain", "Quest", true)
    filterBar:AddCheckbox("showAchievement", "Ach", true)
    filterBar:AddCheckbox("showVendor", "Vend", true)
    filterBar:AddCheckbox("showEvent", "Event", true)
    filterBar:AddCheckbox("showProfession", "Prof", true)
    filterBar:AddCheckbox("soloOnly", "Solo", false)
    filterBar:AddCheckbox("availableOnly", "Avail", false)
    -- Expansion filter dropdown
    filterBar:AddDropdown("expansion", "Exp", {
        ["MIDNIGHT"] = "Midnight",
        ["TWW"]     = "The War Within",
        ["DF"]      = "Dragonflight",
        ["SL"]      = "Shadowlands",
        ["BFA"]     = "Battle for Azeroth",
        ["LEGION"]  = "Legion",
        ["WOD"]     = "Warlords of Draenor",
        ["MOP"]     = "Mists of Pandaria",
        ["CATA"]    = "Cataclysm",
        ["WOTLK"]   = "Wrath of the Lich King",
        ["TBC"]     = "The Burning Crusade",
        ["CLASSIC"] = "Classic",
    }, nil)
    -- Number of results dropdown
    local maxDefault = (FB.db and FB.db.settings and FB.db.settings.recommendations
        and FB.db.settings.recommendations.maxResults) or 20
    filterBar:AddDropdown("maxResults", "Show", {
        ["10"]  = "Top 10",
        ["20"]  = "Top 20",
        ["50"]  = "Top 50",
        ["100"] = "Top 100",
        ["0"]   = "All",
    }, tostring(maxDefault))

    filterBar:SetOnChange(function()
        FB.UI.MountRecommendTab:ApplyFilters()
    end)

    -- Results area: left list + right details (anchored below filter bar)
    local contentFrame = CreateFrame("Frame", nil, panel)
    contentFrame:SetPoint("TOPLEFT", filterBar.frame, "BOTTOMLEFT", -5, -5)
    contentFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 5)

    -- Scroll list (left 60%)
    local leftFrame = CreateFrame("Frame", nil, contentFrame)
    leftFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    leftFrame:SetPoint("BOTTOM", contentFrame, "BOTTOM", 0, 0)
    leftFrame:SetWidth(500)

    scrollList = FB.UI.Widgets:CreateScrollList(leftFrame, "FarmBuddyMountRecommendList", 36)
    scrollList.frame:SetAllPoints()
    scrollList:SetOnClick(function(item)
        FB.UI.MountRecommendTab:SelectMount(item)
    end)
    scrollList:SetOnCtrlClick(function(item)
        if item and item.mountID then
            FB.Utils:OpenMountJournal(item.mountID)
        end
    end)

    -- Details panel (right)
    local rightFrame = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
    rightFrame:SetPoint("TOPLEFT", leftFrame, "TOPRIGHT", 10, 0)
    rightFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    rightFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    rightFrame:SetBackdropColor(0.05, 0.05, 0.1, 0.9)

    -- Score breakdown
    scoreBar = FB.UI.Widgets:CreateScoreBar(rightFrame, "FarmBuddyMountScoreBar")
    scoreBar.frame:SetPoint("TOPLEFT", 8, -8)
    scoreBar.frame:SetPoint("RIGHT", -8, 0)

    -- Model preview (between score bar and detail text)
    modelPreview = FB.UI.Widgets:CreateModelPreview(rightFrame, "FarmBuddyRecommendPreview")
    modelPreview.frame:SetPoint("TOPLEFT", scoreBar.frame, "BOTTOMLEFT", 0, -5)
    modelPreview.frame:SetPoint("RIGHT", rightFrame, "RIGHT", -8, 0)
    modelPreview.frame:SetHeight(180)

    -- Bottom button row: Pin + WoWHead
    local pinBtn = CreateFrame("Button", nil, rightFrame, "UIPanelButtonTemplate")
    pinBtn:SetSize(120, 24)
    pinBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    pinBtn:SetText("Pin to Tracker")
    pinBtn:SetScript("OnClick", function()
        if selectedMount and selectedMount.id then
            local steps = selectedMount._resolvedSteps or selectedMount.steps or {}
            FB.Tracker:Pin("mount", selectedMount.id, selectedMount.name, steps)
            FB:Print("Pinned: " .. selectedMount.name)
        end
    end)
    pinBtn:Hide()
    self.pinBtn = pinBtn

    -- WoWHead link button
    local wowheadBtn = CreateFrame("Button", nil, rightFrame, "UIPanelButtonTemplate")
    wowheadBtn:SetSize(100, 24)
    wowheadBtn:SetPoint("RIGHT", pinBtn, "LEFT", -6, 0)
    wowheadBtn:SetText("WoWHead")
    wowheadBtn:SetNormalFontObject("GameFontNormalSmall")
    wowheadBtn:SetScript("OnClick", function()
        if selectedMount and selectedMount.id then
            -- Copy URL to clipboard via an edit box (WoW can't open browser directly)
            local url = "https://www.wowhead.com/spell=" .. selectedMount.id
            -- Create or reuse a temporary edit box for clipboard copy
            if not FB._wowheadEditBox then
                local eb = CreateFrame("EditBox", "FarmBuddyWowheadCopy", UIParent, "BackdropTemplate")
                eb:SetSize(350, 28)
                eb:SetPoint("TOP", UIParent, "TOP", 0, -120)
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
                label:SetText(FB.COLORS.GOLD .. "Press Ctrl+C to copy, then Escape to close|r")
                eb.label = label

                eb:SetScript("OnEscapePressed", function(self) self:Hide() end)
                eb:SetScript("OnEnterPressed", function(self) self:Hide() end)
                FB._wowheadEditBox = eb
            end
            local eb = FB._wowheadEditBox
            eb:SetText(url)
            eb:Show()
            eb:HighlightText()
            eb:SetFocus()
        end
    end)
    wowheadBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("WoWHead Link")
        if selectedMount and selectedMount.id then
            GameTooltip:AddLine("wowhead.com/spell=" .. selectedMount.id, 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine("Click to copy link to clipboard", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    wowheadBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    wowheadBtn:Hide()
    self.wowheadBtn = wowheadBtn

    -- Scrollable detail text area (prevents overlap with buttons)
    local detailScroll = CreateFrame("ScrollFrame", "FarmBuddyRecommendDetailScroll", rightFrame)
    detailScroll:SetPoint("TOPLEFT", modelPreview.frame, "BOTTOMLEFT", 0, -5)
    detailScroll:SetPoint("RIGHT", rightFrame, "RIGHT", -24, 0)
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
    detailText:SetText(FB.COLORS.GRAY .. "Run a scan, then select a mount for details|r")
    self.detailText = detailText

    -- Scroll bar
    local detailScrollBar = CreateFrame("Slider", "FarmBuddyRecommendDetailScrollBar", rightFrame, "BackdropTemplate")
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

    -- Status label
    local statusLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 5, 5)
    statusLabel:SetTextColor(0.5, 0.5, 0.5)
    self.statusLabel = statusLabel

    -- Filter presets button (bottom-right of filter bar area)
    local presetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    presetBtn:SetSize(70, 20)
    presetBtn:SetPoint("TOPRIGHT", scanBtn, "TOPLEFT", -5, 0)
    presetBtn:SetText("Presets")
    presetBtn:SetNormalFontObject("GameFontNormalSmall")
    presetBtn:SetScript("OnClick", function(self)
        FB.UI.MountRecommendTab:ShowPresetMenu(self)
    end)
end

-- Built-in filter presets
local BUILT_IN_PRESETS = {
    {
        name = "Quick Wins (Solo, Available Now)",
        filters = {
            soloOnly = true,
            availableOnly = true,
            showRaidDrop = true, showDungeonDrop = true, showWorldDrop = true,
            showReputation = true, showCurrency = true, showQuestChain = true,
            showAchievement = true, showVendor = true, showEvent = true,
            showProfession = true,
        },
    },
    {
        name = "Raid Mounts Only",
        filters = {
            showRaidDrop = true, showDungeonDrop = false, showWorldDrop = false,
            showReputation = false, showCurrency = false, showQuestChain = false,
            showAchievement = false, showVendor = false, showEvent = false,
            showProfession = false, soloOnly = false, availableOnly = false,
        },
    },
    {
        name = "Solo Weekly Farm (Raids + Dungeons)",
        filters = {
            soloOnly = true, availableOnly = false,
            showRaidDrop = true, showDungeonDrop = true, showWorldDrop = false,
            showReputation = false, showCurrency = false, showQuestChain = false,
            showAchievement = false, showVendor = false, showEvent = false,
            showProfession = false,
        },
    },
    {
        name = "Rep + Currency Grinds",
        filters = {
            showRaidDrop = false, showDungeonDrop = false, showWorldDrop = false,
            showReputation = true, showCurrency = true, showQuestChain = false,
            showAchievement = false, showVendor = true, showEvent = false,
            showProfession = false, soloOnly = false, availableOnly = false,
        },
    },
    {
        name = "Show Everything",
        filters = {
            showRaidDrop = true, showDungeonDrop = true, showWorldDrop = true,
            showReputation = true, showCurrency = true, showQuestChain = true,
            showAchievement = true, showVendor = true, showEvent = true,
            showProfession = true, soloOnly = false, availableOnly = false,
        },
    },
}

function FB.UI.MountRecommendTab:ShowPresetMenu(anchor)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(anchor, function(ownerRegion, rootDescription)
            rootDescription:CreateTitle("Built-in Presets")
            for _, preset in ipairs(BUILT_IN_PRESETS) do
                rootDescription:CreateButton(preset.name, function()
                    FB.UI.MountRecommendTab:ApplyPreset(preset.filters)
                end)
            end

            -- User saved presets
            local saved = FB.db and FB.db.settings and FB.db.settings.filterPresets
            if saved and #saved > 0 then
                rootDescription:CreateDivider()
                rootDescription:CreateTitle("Saved Presets")
                for i, preset in ipairs(saved) do
                    rootDescription:CreateButton(preset.name, function()
                        FB.UI.MountRecommendTab:ApplyPreset(preset.filters)
                    end)
                end
            end

            rootDescription:CreateDivider()
            rootDescription:CreateButton("Save Current as Preset...", function()
                FB.UI.MountRecommendTab:SaveCurrentPreset()
            end)

            if saved and #saved > 0 then
                rootDescription:CreateButton("|cFFFF4444Clear Saved Presets|r", function()
                    if FB.db and FB.db.settings then
                        FB.db.settings.filterPresets = {}
                        FB:Print("Saved filter presets cleared.")
                    end
                end)
            end
        end)
    else
        -- Fallback: cycle through built-in presets
        if not self._presetIdx then self._presetIdx = 0 end
        self._presetIdx = (self._presetIdx % #BUILT_IN_PRESETS) + 1
        local preset = BUILT_IN_PRESETS[self._presetIdx]
        self:ApplyPreset(preset.filters)
        FB:Print("Filter preset: " .. preset.name)
    end
end

function FB.UI.MountRecommendTab:ApplyPreset(presetFilters)
    if not filterBar then return end
    -- Update filterBar's internal state and UI
    for key, value in pairs(presetFilters) do
        filterBar:SetFilter(key, value)
    end
    -- Re-apply filters to results
    self:ApplyFilters()
end

function FB.UI.MountRecommendTab:SaveCurrentPreset()
    if not filterBar then return end

    -- Prompt for name via a simple input dialog
    local dialog = CreateFrame("Frame", "FarmBuddyPresetDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(300, 100)
    dialog:SetPoint("CENTER")
    dialog:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    dialog:SetBackdropColor(0.1, 0.1, 0.15, 1.0)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetMovable(true)
    dialog:EnableMouse(true)

    local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", 0, -10)
    label:SetText("Save Filter Preset")

    local input = CreateFrame("EditBox", nil, dialog, "BackdropTemplate")
    input:SetSize(240, 24)
    input:SetPoint("CENTER", 0, -5)
    input:SetFontObject("ChatFontNormal")
    input:SetAutoFocus(true)
    input:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    input:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    input:SetTextInsets(4, 4, 0, 0)
    input:SetMaxLetters(30)
    input:SetText("My Preset")

    local saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    saveBtn:SetSize(80, 22)
    saveBtn:SetPoint("BOTTOMRIGHT", -10, 8)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        local name = input:GetText()
        if name and name ~= "" then
            if not FB.db.settings.filterPresets then
                FB.db.settings.filterPresets = {}
            end
            -- Deep copy current filters
            local currentFilters = FB.Utils:DeepCopy(filterBar:GetFilters())
            table.insert(FB.db.settings.filterPresets, {
                name = name,
                filters = currentFilters,
            })
            FB:Print("Saved preset: " .. name)
        end
        dialog:Hide()
    end)

    local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("BOTTOMLEFT", 10, 8)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        dialog:Hide()
    end)

    input:SetScript("OnEscapePressed", function()
        dialog:Hide()
    end)
    input:SetScript("OnEnterPressed", function()
        saveBtn:Click()
    end)

    dialog:Show()
end

function FB.UI.MountRecommendTab:OnShow()
    -- Check for cached results
    local cached = FB.Mounts.Scanner:GetCachedResults()
    if cached and #cached > 0 then
        scanResults = cached
        self:ApplyFilters()
        progressBar:Hide()
        filterBar.frame:Show()
        self.statusLabel:SetText(string.format("%d mounts scored | Last scan: this session", #cached))
    else
        filterBar.frame:Show()
        self.statusLabel:SetText("No scan results. Click 'Scan Mounts' to begin.")
    end
end

function FB.UI.MountRecommendTab:StartScan()
    self.scanBtn:Disable()
    progressBar:Show()
    filterBar.frame:Hide()
    scrollList:SetData({})
    scoreBar:SetScore(nil)
    self.detailText:SetText("")
    self.pinBtn:Hide()

    if modelPreview then modelPreview:Clear() end
    if self.wowheadBtn then self.wowheadBtn:Hide() end

    scanHandle = FB.Mounts.Scanner:StartScan(
        function(current, total)
            progressBar:SetProgress(current, total)
        end,
        function(results)
            scanResults = results
            progressBar:Hide()
            filterBar.frame:Show()
            self.scanBtn:Enable()
            scanHandle = nil

            self:ApplyFilters()
            self.statusLabel:SetText(string.format("%d mounts scored", #results))
        end
    )
end

function FB.UI.MountRecommendTab:CancelScan()
    if scanHandle then
        scanHandle:Cancel()
        scanHandle = nil
    end
    progressBar:Hide()
    filterBar.frame:Show()
    self.scanBtn:Enable()
end

function FB.UI.MountRecommendTab:ApplyFilters()
    if not scanResults then return end

    local filters = filterBar:GetFilters()
    local filtered = FB.Mounts.Scanner:FilterResults(scanResults, filters)

    -- Limit results based on maxResults setting
    local maxResults = tonumber(filters.maxResults) or 20
    if maxResults > 0 and #filtered > maxResults then
        local limited = {}
        for i = 1, maxResults do
            limited[i] = filtered[i]
        end
        scrollList:SetData(limited)
        self.statusLabel:SetText(string.format("Showing top %d of %d mounts (%d total scored)",
            maxResults, #filtered, #scanResults))
    else
        scrollList:SetData(filtered)
        self.statusLabel:SetText(string.format("Showing %d of %d mounts", #filtered, #scanResults))
    end

    -- Save preference
    if FB.db and FB.db.settings then
        FB.db.settings.recommendations = FB.db.settings.recommendations or {}
        FB.db.settings.recommendations.maxResults = maxResults
    end
end

function FB.UI.MountRecommendTab:SelectMount(item)
    if not item then return end
    selectedMount = item

    -- Update score breakdown
    scoreBar:SetScore({
        score = item.score,
        components = item.components,
    })

    -- Update model preview
    if item.creatureDisplayID and modelPreview then
        modelPreview:SetMount(item.creatureDisplayID, item.name)
    elseif item.mountID and modelPreview then
        modelPreview:SetMountByMountID(item.mountID)
    elseif modelPreview then
        modelPreview:Clear()
    end

    -- Show WoWHead button
    if self.wowheadBtn then
        self.wowheadBtn:Show()
    end

    -- Use shared detail builder (false = don't show collected status on recommend tab)
    local lines, steps = FB.Utils:BuildMountDetailLines(item, false)

    -- Store resolved steps for the pin button
    selectedMount._resolvedSteps = steps

    self.detailText:SetText(table.concat(lines, "\n"))

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

    -- Show pin button for any recommended mount
    self.pinBtn:Show()
end
