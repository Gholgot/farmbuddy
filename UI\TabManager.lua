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

-- Create a fully manual tab button (no template dependency)
local function CreateTabButton(parent, index, text)
    local tab = CreateFrame("Button", "FarmBuddyTab" .. index, parent, "BackdropTemplate")
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

    -- Hover effects
    tab:SetScript("OnEnter", function(self)
        if activeTab ~= index then
            self:SetBackdropColor(unpack(TAB_HOVER_BG))
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(text)
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
        tab:SetPoint("LEFT", tabs[index - 1], "RIGHT", 4, 0)
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
