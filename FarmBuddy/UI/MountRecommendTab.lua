local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.MountRecommendTab = {}

local panel
local scrollList
local progressBar
local filterBar
local scanResults = nil
-- NOTE: selectedMount is intentionally module-level (not persisted). It is cleared
-- on tab switch, which is a known limitation — selection is not restored after switching tabs.
local selectedMount = nil
local scanHandle = nil
-- #3: Guard against auto-scan firing more than once per session
local autoScanned = false

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
    -- Hide by default to prevent overlap with filterBar (both anchor to the same point)
    progressBar.frame:Hide()

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
    filterBar:AddCheckbox("showPvP", "PvP", true)
    filterBar:AddCheckbox("showTradingPost", "TP", true)
    filterBar:AddCheckbox("showRAF", "RAF", true)
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

    -- #25: Goal progress display with inline progress bar
    local goalBarFrame = CreateFrame("Frame", nil, panel)
    goalBarFrame:SetPoint("TOPLEFT", filterBar.frame, "BOTTOMLEFT", 0, -3)
    goalBarFrame:SetPoint("RIGHT", filterBar.frame, "RIGHT", 0, 0)
    goalBarFrame:SetHeight(16)
    goalBarFrame:Hide()

    -- Background bar
    local goalBg = goalBarFrame:CreateTexture(nil, "BACKGROUND")
    goalBg:SetAllPoints()
    goalBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)

    -- Fill texture (width set dynamically in UpdateGoalProgress)
    local goalFill = goalBarFrame:CreateTexture(nil, "ARTWORK")
    goalFill:SetPoint("TOPLEFT", 1, -1)
    goalFill:SetPoint("BOTTOMLEFT", 1, 1)
    goalFill:SetWidth(1)
    goalFill:SetColorTexture(0.2, 0.6, 0.2, 0.8)

    -- Text label on top of the bar
    local goalText = goalBarFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goalText:SetPoint("TOPLEFT", 4, 0)
    goalText:SetPoint("BOTTOMRIGHT", -4, 0)
    goalText:SetJustifyH("LEFT")

    self.goalBar = goalBarFrame
    self.goalFill = goalFill
    self.goalText = goalText

    -- Results area: left list + right details (anchored below filter bar)
    local contentFrame = CreateFrame("Frame", nil, panel)
    contentFrame:SetPoint("TOPLEFT", filterBar.frame, "BOTTOMLEFT", -5, -5)
    contentFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 5)

    -- Scroll list (left 60%)
    local leftFrame = CreateFrame("Frame", nil, contentFrame)
    leftFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    leftFrame:SetPoint("BOTTOM", contentFrame, "BOTTOM", 0, 0)
    leftFrame:SetWidth(math.max(300, contentFrame:GetWidth() * 0.6))
    contentFrame:SetScript("OnSizeChanged", function(self)
        leftFrame:SetWidth(math.max(300, self:GetWidth() * 0.6))
    end)

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

    -- Details panel (right) — shared widget
    local rightFrame = CreateFrame("Frame", nil, contentFrame)
    rightFrame:SetPoint("TOPLEFT", leftFrame, "TOPRIGHT", 10, 0)
    rightFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)

    local detailPanel = FB.UI.Widgets:CreateMountDetailPanel(rightFrame, "FarmBuddyRecommendDetail")
    detailPanel.frame:SetAllPoints()
    self.detailPanel = detailPanel

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
            showProfession = true, showPvP = true, showTradingPost = true,
            showRAF = true,
        },
    },
    {
        name = "Raid Mounts Only",
        filters = {
            showRaidDrop = true, showDungeonDrop = false, showWorldDrop = false,
            showReputation = false, showCurrency = false, showQuestChain = false,
            showAchievement = false, showVendor = false, showEvent = false,
            showProfession = false, showPvP = false, showTradingPost = false,
            showRAF = false,
            soloOnly = false, availableOnly = false,
        },
    },
    {
        name = "Solo Weekly Farm (Raids + Dungeons)",
        filters = {
            soloOnly = true, availableOnly = false,
            showRaidDrop = true, showDungeonDrop = true, showWorldDrop = false,
            showReputation = false, showCurrency = false, showQuestChain = false,
            showAchievement = false, showVendor = false, showEvent = false,
            showProfession = false, showPvP = false, showTradingPost = false,
            showRAF = false,
        },
    },
    {
        name = "Rep + Currency Grinds",
        filters = {
            showRaidDrop = false, showDungeonDrop = false, showWorldDrop = false,
            showReputation = true, showCurrency = true, showQuestChain = false,
            showAchievement = false, showVendor = true, showEvent = false,
            showProfession = false, showPvP = false, showTradingPost = true,
            showRAF = false,
            soloOnly = false, availableOnly = false,
        },
    },
    {
        name = "Show Everything",
        filters = {
            showRaidDrop = true, showDungeonDrop = true, showWorldDrop = true,
            showReputation = true, showCurrency = true, showQuestChain = true,
            showAchievement = true, showVendor = true, showEvent = true,
            showProfession = true, showPvP = true, showTradingPost = true,
            showRAF = true,
            soloOnly = false, availableOnly = false,
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

    -- Reuse existing dialog frame if it was already created
    if _G["FarmBuddyPresetDialog"] then
        -- BUG-6: Clear stale name from EditBox before re-showing the dialog
        local existingDialog = _G["FarmBuddyPresetDialog"]
        if existingDialog.inputBox then
            existingDialog.inputBox:SetText("")
            existingDialog.inputBox:SetFocus()
        end
        existingDialog:Show()
        return
    end

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
    -- BUG-6: Store reference on dialog so re-show path can clear it
    dialog.inputBox = input

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
    elseif not autoScanned and not scanHandle then
        -- #3: Auto-scan on first open when no cached results exist
        autoScanned = true
        self.statusLabel:SetText("Scanning mounts...")
        self:StartScan()
    else
        filterBar.frame:Show()
        -- FEAT-2: Distinguish between "never scanned" and "cache expired after auto-scan"
        if autoScanned and not scanHandle then
            self.statusLabel:SetText("Scan cache expired — click 'Scan Mounts' to refresh.")
        else
            self.statusLabel:SetText("No scan results. Click 'Scan Mounts' to begin.")
        end
    end
end

function FB.UI.MountRecommendTab:StartScan()
    self.scanBtn:Disable()
    progressBar:Show()
    filterBar.frame:Hide()
    if scrollList then scrollList:SetData({}) end
    if self.detailPanel then self.detailPanel:Clear() end

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

    -- Update goal progress display
    self:UpdateGoalProgress(filtered)

    -- Limit results based on maxResults setting
    local maxResults = tonumber(filters.maxResults) or 20
    if not scrollList then return end
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

    -- Track click for behavior learning
    if FB.BehaviorTracker and FB.BehaviorTracker.RecordClick and item.sourceType then
        FB.BehaviorTracker:RecordClick(item.sourceType)
    end

    selectedMount = item

    self.detailPanel:SetMount(item, {
        showCollectionStatus = false,
        showSynergies = true,
        showDiminishingReturns = true,
    })
end

function FB.UI.MountRecommendTab:UpdateGoalProgress(filteredResults)
    if not self.goalBar then return end
    if not FB.db or not FB.db.goals then
        self.goalBar:Hide()
        return
    end

    local goals = FB.db.goals
    local text = nil
    local ratio = 0  -- 0..1 fill ratio for the progress bar

    if goals.targetExpansion then
        -- Count uncollected mounts for this expansion using cachedMountScores
        local remaining = 0
        if FB.db and FB.db.cachedMountScores then
            for _, r in ipairs(FB.db.cachedMountScores) do
                if r.expansion == goals.targetExpansion then
                    remaining = remaining + 1
                end
            end
        end
        local expName = FB.EXPANSION_NAMES[goals.targetExpansion] or goals.targetExpansion
        text = string.format(
            "%sGoal:|r %s - %d remaining",
            FB.COLORS.GOLD, expName, remaining
        )
        -- Estimate total from cached: collected + remaining
        local totalEstimate = remaining  -- We only have remaining here, ratio stays 0 unless we can derive total
        if FB.db.cachedMountScores then
            -- All scored mounts for this expansion = remaining (uncollected only scored)
            -- We can't easily derive collected count here, so leave ratio at 0 for expansion goal
            ratio = 0
        end
    elseif goals.targetMountCount then
        local currentCount = 0
        if C_MountJournal and C_MountJournal.GetMountIDs then
            local mountIDs = C_MountJournal.GetMountIDs()
            if mountIDs then
                for _, mid in ipairs(mountIDs) do
                    local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mid)
                    if isCollected then currentCount = currentCount + 1 end
                end
            end
        end
        local pct = goals.targetMountCount > 0
            and math.floor(currentCount / goals.targetMountCount * 100) or 0
        text = string.format(
            "%sGoal:|r %d / %d mounts (%d%%)",
            FB.COLORS.GOLD, currentCount, goals.targetMountCount, pct
        )
        ratio = goals.targetMountCount > 0 and (currentCount / goals.targetMountCount) or 0
        ratio = math.min(ratio, 1.0)
    end

    if text then
        -- #25: Update fill width proportional to progress
        if self.goalFill and self.goalBar:GetWidth() and self.goalBar:GetWidth() > 2 then
            local barW = self.goalBar:GetWidth() - 2
            local fillW = math.max(1, barW * ratio)
            self.goalFill:SetWidth(fillW)
            -- Color: green > 75%, yellow > 50%, orange otherwise
            if ratio > 0.75 then
                self.goalFill:SetColorTexture(0.2, 0.7, 0.2, 0.8)
            elseif ratio > 0.5 then
                self.goalFill:SetColorTexture(0.8, 0.8, 0.1, 0.8)
            else
                self.goalFill:SetColorTexture(0.9, 0.45, 0.1, 0.8)
            end
        end
        if self.goalText then
            self.goalText:SetText(text)
        end
        self.goalBar:Show()
    else
        self.goalBar:Hide()
    end
end
