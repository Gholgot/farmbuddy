local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.AchievementTab = {}

local panel
local scrollList
local progressBar
local filterBar
local scoreBar
local categoryDropdown
local scanResults = nil
local scanHandle = nil
local selectedAch = nil
local currentCategoryID = nil

function FB.UI.AchievementTab:Init(parentPanel)
    panel = parentPanel

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 5, -5)
    title:SetText("Achievement Recommendations")

    -- Category selector
    local catLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catLabel:SetPoint("TOPLEFT", 5, -30)
    catLabel:SetText("Category:")

    local catBtn = CreateFrame("Button", "FarmBuddyAchCategoryBtn", panel, "BackdropTemplate")
    catBtn:SetSize(250, 24)
    catBtn:SetPoint("LEFT", catLabel, "RIGHT", 8, 0)
    catBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    catBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

    local catText = catBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    catText:SetPoint("LEFT", 6, 0)
    catText:SetPoint("RIGHT", -16, 0)
    catText:SetJustifyH("LEFT")
    catText:SetText("Select a category...")
    self.catText = catText

    local catArrow = catBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    catArrow:SetPoint("RIGHT", -4, 0)
    catArrow:SetText("v")

    catBtn:SetScript("OnClick", function()
        FB.UI.AchievementTab:ShowCategoryMenu()
    end)

    -- Current zone button
    local zoneBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    zoneBtn:SetSize(110, 24)
    zoneBtn:SetPoint("LEFT", catBtn, "RIGHT", 8, 0)
    zoneBtn:SetText("Current Zone")
    zoneBtn:SetScript("OnClick", function()
        local catID, zoneName = FB.ZoneGrouper:GetCurrentZoneCategory()
        if catID then
            currentCategoryID = catID
            catText:SetText(zoneName or ("Category " .. catID))
            FB.UI.AchievementTab:StartScan()
        else
            FB:Print("Could not find an achievement category for your current zone.")
        end
    end)

    -- Scan button
    local scanBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scanBtn:SetSize(80, 24)
    scanBtn:SetPoint("TOPRIGHT", -5, -28)
    scanBtn:SetText("Scan")
    scanBtn:SetScript("OnClick", function()
        if currentCategoryID then
            FB.UI.AchievementTab:StartScan()
        else
            FB:Print("Please select a category first.")
        end
    end)
    self.scanBtn = scanBtn

    -- Progress bar
    progressBar = FB.UI.Widgets:CreateProgressBar(panel, "FarmBuddyAchScanProgress")
    progressBar.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -58)
    progressBar.frame:SetPoint("RIGHT", panel, "RIGHT", -5, 0)
    progressBar:SetOnCancel(function()
        FB.UI.AchievementTab:CancelScan()
    end)

    -- Filter bar
    filterBar = FB.UI.Widgets:CreateFilterBar(panel, "FarmBuddyAchFilters")
    filterBar.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -58)
    filterBar.frame:SetPoint("RIGHT", panel, "RIGHT", -5, 0)

    filterBar:AddCheckbox("soloOnly", "Solo Only", false)
    filterBar:AddCheckbox("hideCompleted", "Hide Done", true)
    filterBar:AddDropdown("rewardType", "Reward", {
        mount = "Mount",
        title = "Title",
        pet = "Pet",
        transmog = "Transmog",
        toy = "Toy",
    })

    filterBar:SetOnChange(function()
        FB.UI.AchievementTab:ApplyFilters()
    end)

    -- Content area
    local contentFrame = CreateFrame("Frame", nil, panel)
    contentFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -92)
    contentFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 5)

    -- Scroll list (left)
    local leftFrame = CreateFrame("Frame", nil, contentFrame)
    leftFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    leftFrame:SetPoint("BOTTOM", contentFrame, "BOTTOM", 0, 0)
    leftFrame:SetWidth(500)

    scrollList = FB.UI.Widgets:CreateScrollList(leftFrame, "FarmBuddyAchList", 36)
    scrollList.frame:SetAllPoints()
    scrollList:SetOnClick(function(item)
        FB.UI.AchievementTab:SelectAchievement(item)
    end)
    scrollList:SetOnCtrlClick(function(item)
        if item and item.id then
            -- Open Blizzard Achievement UI to this achievement
            if not IsAddOnLoaded("Blizzard_AchievementUI") then
                pcall(LoadAddOn, "Blizzard_AchievementUI")
            end
            if OpenAchievement then
                pcall(OpenAchievement, item.id)
            elseif AchievementFrame_SelectAchievement then
                pcall(AchievementFrame_SelectAchievement, item.id)
            end
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

    -- Score breakdown (consistent with MountRecommendTab)
    local scoreBar = FB.UI.Widgets:CreateScoreBar(rightFrame, "FarmBuddyAchScoreBar")
    scoreBar.frame:SetPoint("TOPLEFT", 8, -8)
    scoreBar.frame:SetPoint("RIGHT", -8, 0)
    self.scoreBar = scoreBar

    -- Pin button (anchor first so detail text can stop above it)
    local pinBtn = CreateFrame("Button", nil, rightFrame, "UIPanelButtonTemplate")
    pinBtn:SetSize(120, 24)
    pinBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    pinBtn:SetText("Pin to Tracker")
    pinBtn:SetScript("OnClick", function()
        if selectedAch then
            local steps = {}
            if selectedAch.criteriaDetails then
                for _, c in ipairs(selectedAch.criteriaDetails) do
                    if not c.completed then
                        steps[#steps + 1] = c.name
                    end
                end
            end
            FB.Tracker:Pin("achievement", selectedAch.id, selectedAch.name, steps)
            FB:Print("Pinned: " .. selectedAch.name)
        end
    end)
    pinBtn:Hide()
    self.pinBtn = pinBtn

    -- Scrollable detail text area (prevents overlap with pin button)
    local detailScroll = CreateFrame("ScrollFrame", "FarmBuddyAchDetailScroll", rightFrame)
    detailScroll:SetPoint("TOPLEFT", scoreBar.frame, "BOTTOMLEFT", 0, -10)
    detailScroll:SetPoint("RIGHT", rightFrame, "RIGHT", -24, 0)
    detailScroll:SetPoint("BOTTOM", pinBtn, "TOP", 0, 4)
    detailScroll:EnableMouseWheel(true)

    local detailChild = CreateFrame("Frame", nil, detailScroll)
    detailChild:SetSize(300, 1)
    detailScroll:SetScrollChild(detailChild)

    local detailText = detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailText:SetPoint("TOPLEFT", 0, 0)
    detailText:SetWidth(300)
    detailText:SetJustifyH("LEFT")
    detailText:SetWordWrap(true)
    detailText:SetText(FB.COLORS.GRAY .. "Select an achievement for details|r")
    self.detailText = detailText

    -- Scroll bar
    local detailScrollBar = CreateFrame("Slider", "FarmBuddyAchDetailScrollBar", rightFrame, "BackdropTemplate")
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

    detailScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = math.max(0, detailChild:GetHeight() - self:GetHeight())
        local newScroll = math.max(0, math.min(maxScroll, current - (delta * 30)))
        self:SetVerticalScroll(newScroll)
        detailScrollBar:SetValue(newScroll)
    end)

    detailScroll:SetScript("OnSizeChanged", function(self, w, h)
        if w and w > 10 then
            detailChild:SetWidth(w)
            detailText:SetWidth(w)
        end
    end)

    self.detailScroll = detailScroll
    self.detailChild = detailChild
    self.detailScrollBar = detailScrollBar

    -- Status
    local statusLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 5, 5)
    statusLabel:SetTextColor(0.5, 0.5, 0.5)
    self.statusLabel = statusLabel
end

function FB.UI.AchievementTab:OnShow()
    if scanResults then
        progressBar:Hide()
        filterBar.frame:Show()
    end
end

function FB.UI.AchievementTab:ShowCategoryMenu()
    local roots, catMap = FB.ZoneGrouper:GetCategoryTree()
    local catBtn = FarmBuddyAchCategoryBtn

    -- Helper to select a category
    local function selectCategory(id, name)
        currentCategoryID = id
        self.catText:SetText(name)
    end

    if MenuUtil and MenuUtil.CreateContextMenu then
        local ok, err = pcall(function()
            MenuUtil.CreateContextMenu(catBtn, function(ownerRegion, rootDescription)
                -- Build hierarchical menu
                -- WoW 12.0 API: CreateButton(text) without callback returns an element
                -- description. Adding children to it makes it a submenu automatically.
                for _, root in ipairs(roots) do
                    if root.children and #root.children > 0 then
                        -- Create submenu: no callback = returns element description
                        local submenu = rootDescription:CreateButton(root.name)

                        -- "All of [root]" option at top of submenu
                        submenu:CreateButton("|cFFFFD200All " .. root.name .. "|r", function()
                            selectCategory(root.id, root.name)
                        end)

                        -- Subcategories
                        for _, child in ipairs(root.children) do
                            if child.children and #child.children > 0 then
                                -- Nested submenu (3rd level)
                                local childSubmenu = submenu:CreateButton(child.name)
                                childSubmenu:CreateButton("|cFFFFD200All " .. child.name .. "|r", function()
                                    selectCategory(child.id, child.name)
                                end)
                                for _, grandchild in ipairs(child.children) do
                                    childSubmenu:CreateButton(grandchild.name, function()
                                        selectCategory(grandchild.id, grandchild.name)
                                    end)
                                end
                            else
                                -- Leaf button in submenu
                                submenu:CreateButton(child.name, function()
                                    selectCategory(child.id, child.name)
                                end)
                            end
                        end
                    else
                        -- No children - direct clickable button
                        rootDescription:CreateButton(root.name, function()
                            selectCategory(root.id, root.name)
                        end)
                    end
                end
            end)
        end)

        if not ok then
            FB:Debug("MenuUtil error: " .. tostring(err) .. " - using fallback menu")
            self:ShowCategoryMenuFallback(roots)
        end
    else
        -- Fallback: scrollable panel-based menu
        self:ShowCategoryMenuFallback(roots)
    end
end

-- Fallback category menu for clients without MenuUtil
function FB.UI.AchievementTab:ShowCategoryMenuFallback(roots)
    local catBtn = FarmBuddyAchCategoryBtn

    -- Reuse existing frame or create once (avoids frame leak)
    if self.fallbackMenu then
        if self.fallbackMenu:IsShown() then
            self.fallbackMenu:Hide()
            return
        end
        -- Clear old children
        if self.fallbackScrollContent then
            local children = { self.fallbackScrollContent:GetChildren() }
            for _, child in ipairs(children) do
                child:Hide()
                child:ClearAllPoints()
            end
        end
    end

    local listFrame = self.fallbackMenu
    if not listFrame then
        listFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        listFrame:SetSize(300, 400)
        listFrame:SetFrameStrata("DIALOG")
        listFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        listFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
        self.fallbackMenu = listFrame

        -- Clear OnUpdate when hidden to avoid wasting CPU
        listFrame:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)
    end
    listFrame:ClearAllPoints()
    listFrame:SetPoint("TOPLEFT", catBtn, "BOTTOMLEFT", 0, -2)

    -- Scrollable content (reuse or create)
    local scrollFrame = self.fallbackScrollFrame
    if not scrollFrame then
        scrollFrame = CreateFrame("ScrollFrame", nil, listFrame)
        scrollFrame:SetPoint("TOPLEFT", 4, -4)
        scrollFrame:SetPoint("BOTTOMRIGHT", -4, 4)
        scrollFrame:EnableMouseWheel(true)
        self.fallbackScrollFrame = scrollFrame
    end

    local content = self.fallbackScrollContent
    if not content then
        content = CreateFrame("Frame", nil, scrollFrame)
        content:SetWidth(280)
        scrollFrame:SetScrollChild(content)
        self.fallbackScrollContent = content
    end

    local yOff = 0
    local function AddCategoryButton(cat, depth)
        local btn = CreateFrame("Button", nil, content)
        btn:SetHeight(20)
        btn:SetPoint("TOPLEFT", depth * 16, yOff)
        btn:SetPoint("RIGHT", -4, 0)

        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.3, 0.5, 1.0, 0.2)

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetAllPoints()
        text:SetJustifyH("LEFT")

        -- Color root categories gold, subcategories white
        if depth == 0 then
            text:SetText(FB.COLORS.GOLD .. cat.name .. "|r")
        elseif depth == 1 then
            text:SetText(FB.COLORS.WHITE .. cat.name .. "|r")
        else
            text:SetText(FB.COLORS.GRAY .. cat.name .. "|r")
        end

        btn:SetScript("OnClick", function()
            currentCategoryID = cat.id
            self.catText:SetText(cat.name)
            listFrame:Hide()
        end)

        yOff = yOff - 20
    end

    -- Build the list with hierarchy
    for _, root in ipairs(roots) do
        AddCategoryButton(root, 0)
        if root.children then
            for _, child in ipairs(root.children) do
                AddCategoryButton(child, 1)
                if child.children then
                    for _, grandchild in ipairs(child.children) do
                        AddCategoryButton(grandchild, 2)
                    end
                end
            end
        end
    end

    content:SetHeight(math.abs(yOff) + 4)

    -- Mouse wheel scroll
    local scrollAmount = 0
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        scrollAmount = scrollAmount - delta * 40
        scrollAmount = math.max(0, math.min(scrollAmount, math.abs(yOff) - 350))
        scrollFrame:SetVerticalScroll(scrollAmount)
    end)

    -- Auto-close when clicking elsewhere
    listFrame:SetScript("OnShow", function(frame)
        frame:SetScript("OnUpdate", function(frame)
            if not MouseIsOver(frame) and not MouseIsOver(catBtn) then
                if IsMouseButtonDown() then
                    frame:Hide()
                end
            end
        end)
    end)

    listFrame:Show()
end

function FB.UI.AchievementTab:StartScan()
    if not currentCategoryID then return end

    self.scanBtn:Disable()
    progressBar:Show()
    filterBar.frame:Hide()
    scrollList:SetData({})
    if self.scoreBar then self.scoreBar:SetScore(nil) end
    self.detailText:SetText("")
    self.pinBtn:Hide()

    scanHandle = FB.Achievements.Scanner:ScanCategory(
        currentCategoryID,
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
            self.statusLabel:SetText(string.format("%d achievements found", #results))
        end
    )
end

function FB.UI.AchievementTab:CancelScan()
    if scanHandle then
        scanHandle:Cancel()
        scanHandle = nil
    end
    progressBar:Hide()
    filterBar.frame:Show()
    self.scanBtn:Enable()
end

function FB.UI.AchievementTab:ApplyFilters()
    if not scanResults then return end
    local filters = filterBar:GetFilters()
    local filtered = FB.Achievements.Scanner:FilterResults(scanResults, filters)
    scrollList:SetData(filtered)
    self.statusLabel:SetText(string.format("Showing %d of %d achievements", #filtered, #scanResults))
end

function FB.UI.AchievementTab:SelectAchievement(item)
    if not item then return end
    selectedAch = item

    -- Update score breakdown bar (consistent with MountRecommendTab)
    if self.scoreBar then
        self.scoreBar:SetScore({
            score = item.score,
            components = item.components,
        })
    end

    local lines = {}
    lines[#lines + 1] = FB.COLORS.GOLD .. item.name .. "|r"
    lines[#lines + 1] = item.description or ""
    lines[#lines + 1] = ""

    if item.rewardText and item.rewardText ~= "" then
        lines[#lines + 1] = FB.COLORS.GREEN .. "Reward: " .. item.rewardText .. "|r"
    end

    lines[#lines + 1] = string.format("Points: %d | Progress: %d/%d criteria",
        item.points or 0, item.completedCriteria or 0, item.totalCriteria or 0)

    if item.effectiveDays then
        lines[#lines + 1] = FB.COLORS.YELLOW .. "Est. Time: ~" .. FB.Utils:FormatDays(item.effectiveDays) .. "|r"
    end

    if item.immediatelyAvailable then
        lines[#lines + 1] = FB.COLORS.GREEN .. "Available right now!|r"
    end

    -- Criteria list
    if item.criteriaDetails and #item.criteriaDetails > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = FB.COLORS.YELLOW .. "Criteria:|r"
        for _, c in ipairs(item.criteriaDetails) do
            local status = c.completed and (FB.COLORS.GREEN .. "Done|r") or (FB.COLORS.RED .. "Incomplete|r")
            local progress = ""
            if c.reqQuantity and c.reqQuantity > 1 then
                progress = string.format(" (%d/%d)", c.quantity or 0, c.reqQuantity)
            end
            lines[#lines + 1] = "  " .. status .. " " .. c.name .. progress
        end
    end

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

    self.pinBtn:Show()
end
