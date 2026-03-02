local addonName, FB = ...

FB.TabManager = {}

local tabs = {}
local tabPanels = {}
local activeTab = nil

-- Color constants for tab states
local TAB_ACTIVE_BG = { 0.15, 0.15, 0.15, 1.0 }
local TAB_INACTIVE_BG = { 0.05, 0.05, 0.05, 0.8 }
local TAB_HOVER_BG = { 0.2, 0.2, 0.2, 0.9 }
local TAB_ACTIVE_TEXT = { 1.0, 0.82, 0.0 }      -- Gold
local TAB_INACTIVE_TEXT = { 0.7, 0.7, 0.7 }      -- Gray

-- Minimum tab width before text gets truncated
local TAB_MIN_WIDTH = 60
-- Gap between tab buttons
local TAB_GAP = 4

-- Brief descriptions shown in tab tooltips
local TAB_DESCRIPTIONS = {
    "Search and filter all mounts by source, expansion, and status",
    "AI-scored mount farming priorities",
    "Plan your farming activities for today",
    "Track mount-rewarding achievements",
    "Track weekly lockouts across characters",
    "Mount collection progress by expansion",
    "Configure scoring weights and display options",
}

-- Calculate dynamic tab width based on frame width and tab count
local function CalcTabWidth(frameWidth, numTabs)
    -- Account for: 12px left margin, 12px right margin, (numTabs-1) gaps between tabs
    local margins = 12 + 12
    local totalGap = (numTabs - 1) * TAB_GAP
    local width = math.floor((frameWidth - margins - totalGap) / numTabs)
    return math.max(TAB_MIN_WIDTH, width)
end

-- Apply a new width to all existing tab buttons
local function ApplyTabWidths(width)
    for _, tab in ipairs(tabs) do
        tab:SetWidth(width)
    end
end

-- Create a fully manual tab button (no template dependency)
local function CreateTabButton(parent, index, text)
    local tab = CreateFrame("Button", "FarmBuddyTab" .. index, parent, "BackdropTemplate")
    -- Initial width calculated later in Init; use 100 as placeholder
    tab:SetSize(100, 28)
    tab:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    tab:SetBackdropColor(unpack(TAB_INACTIVE_BG))
    tab:SetID(index)

    local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", 0, 1)
    label:SetText(text)
    label:SetTextColor(unpack(TAB_INACTIVE_TEXT))
    tab.label = label

    -- Active indicator (bottom highlight bar)
    local indicator = tab:CreateTexture(nil, "OVERLAY")
    indicator:SetHeight(2)
    indicator:SetPoint("BOTTOMLEFT", 3, 2)
    indicator:SetPoint("BOTTOMRIGHT", -3, 2)
    indicator:SetColorTexture(0.0, 0.6, 1.0, 1.0)
    indicator:Hide()
    tab.indicator = indicator

    -- Tooltip description for this tab
    local tooltipDesc = TAB_DESCRIPTIONS[index] or ""

    -- Hover effects
    tab:SetScript("OnEnter", function(self)
        if activeTab ~= index then
            self:SetBackdropColor(unpack(TAB_HOVER_BG))
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(text)
        if tooltipDesc ~= "" then
            GameTooltip:AddLine(tooltipDesc, 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function(self)
        if activeTab ~= index then
            self:SetBackdropColor(unpack(TAB_INACTIVE_BG))
        end
        GameTooltip:Hide()
    end)

    tab:SetScript("OnClick", function(self)
        FB.TabManager:SelectTab(self:GetID())
    end)

    -- Position: horizontal row at top of the frame, below title
    if index == 1 then
        tab:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -28)
    else
        tab:SetPoint("LEFT", tabs[index - 1], "RIGHT", TAB_GAP, 0)
    end

    return tab
end

-- Update visual state of tab buttons
local function UpdateTabVisuals(selectedIndex)
    for i, tab in ipairs(tabs) do
        if i == selectedIndex then
            tab:SetBackdropColor(unpack(TAB_ACTIVE_BG))
            tab.label:SetTextColor(unpack(TAB_ACTIVE_TEXT))
            tab.indicator:Show()
        else
            tab:SetBackdropColor(unpack(TAB_INACTIVE_BG))
            tab.label:SetTextColor(unpack(TAB_INACTIVE_TEXT))
            tab.indicator:Hide()
        end
    end
end

-- Initialize tabs on the main frame
function FB.TabManager:Init(parent)
    self.parentFrame = parent

    for i, name in ipairs(FB.TAB_NAMES) do
        -- Create tab button
        tabs[i] = CreateTabButton(parent, i, name)

        -- Create content panel
        local panel = CreateFrame("Frame", "FarmBuddyPanel" .. i, parent)
        panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -60)
        panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 12)
        panel:Hide()
        tabPanels[i] = panel
    end

    -- #14: Apply dynamic tab widths based on current frame width
    local frameWidth = parent:GetWidth() or 950
    local tabWidth = CalcTabWidth(frameWidth, #FB.TAB_NAMES)
    ApplyTabWidths(tabWidth)

    -- #14: Recalculate tab widths when the frame is resized
    parent:HookScript("OnSizeChanged", function(self, newWidth, newHeight)
        local newTabWidth = CalcTabWidth(newWidth, #FB.TAB_NAMES)
        ApplyTabWidths(newTabWidth)
    end)

    -- Select last used tab or default to 1
    local lastTab = FB.db and FB.db.settings and FB.db.settings.ui and FB.db.settings.ui.lastTab or 1
    if lastTab < 1 or lastTab > #FB.TAB_NAMES then lastTab = 1 end
    self:SelectTab(lastTab)
end

-- Switch to a tab
function FB.TabManager:SelectTab(index)
    if index < 1 or index > #FB.TAB_NAMES then return end

    -- Hide all panels
    for _, panel in pairs(tabPanels) do
        panel:Hide()
    end

    -- Show selected panel
    if tabPanels[index] then
        tabPanels[index]:Show()
    end
    activeTab = index

    -- Update tab button visuals
    UpdateTabVisuals(index)

    -- Save preference
    if FB.db and FB.db.settings and FB.db.settings.ui then
        FB.db.settings.ui.lastTab = index
    end

    -- Notify tab modules that they're now visible
    local tabCallbacks = {
        [FB.TABS.MOUNT_SEARCH]       = FB.UI.MountSearchTab,
        [FB.TABS.MOUNT_RECOMMEND]    = FB.UI.MountRecommendTab,
        [FB.TABS.SESSION]            = FB.UI.SessionTab,
        [FB.TABS.ACHIEVEMENTS]       = FB.UI.AchievementTab,
        [FB.TABS.WEEKLY]             = FB.UI.WeeklyTab,
        [FB.TABS.EXPANSION_PROGRESS] = FB.UI.ExpansionProgressTab,
        [FB.TABS.SETTINGS]           = FB.UI.SettingsTab,
    }

    local module = tabCallbacks[index]
    if module and module.OnShow then
        local ok, err = pcall(module.OnShow, module)
        if not ok then
            FB:Debug("Tab OnShow error: " .. tostring(err))
        end
    end
end

-- Get a tab's content panel
function FB.TabManager:GetPanel(index)
    return tabPanels[index]
end

-- Get active tab index
function FB.TabManager:GetActiveTab()
    return activeTab
end
