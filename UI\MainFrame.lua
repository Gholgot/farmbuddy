local addonName, FB = ...

FB.UI = FB.UI or {}

local mainFrame = nil

-- Create the main addon window
function FB.UI:CreateMainFrame()
    if mainFrame then return mainFrame end

    -- Main frame
    mainFrame = CreateFrame("Frame", "FarmBuddyMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetFrameLevel(100)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMovable(true)
    mainFrame:SetResizable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")

    -- Resize bounds
    if mainFrame.SetResizeBounds then
        mainFrame:SetResizeBounds(700, 400, 1400, 900)
    elseif mainFrame.SetMinResize then
        mainFrame:SetMinResize(700, 400)
        mainFrame:SetMaxResize(1400, 900)
    end

    -- Restore saved size and position
    local ui = FB.db and FB.db.settings and FB.db.settings.ui
    local savedW = ui and ui.mainFrameW or 950
    local savedH = ui and ui.mainFrameH or 600
    mainFrame:SetSize(savedW, savedH)

    if ui then
        mainFrame:SetPoint(
            ui.mainFramePoint or "CENTER",
            UIParent,
            ui.mainFrameRelPoint or "CENTER",
            ui.mainFrameX or 0,
            ui.mainFrameY or 0
        )
    else
        mainFrame:SetPoint("CENTER")
    end

    -- Backdrop (use tooltip textures - reliable across all WoW versions)
    mainFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    mainFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)

    -- Dragging
    mainFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        local point, _, relPoint, x, y = self:GetPoint()
        if FB.db and FB.db.settings and FB.db.settings.ui then
            FB.db.settings.ui.mainFramePoint = point
            FB.db.settings.ui.mainFrameRelPoint = relPoint
            FB.db.settings.ui.mainFrameX = x
            FB.db.settings.ui.mainFrameY = y
        end
    end)

    -- Resize grip (bottom-right corner)
    local resizeGrip = CreateFrame("Button", nil, mainFrame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    resizeGrip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            mainFrame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeGrip:SetScript("OnMouseUp", function(self, button)
        mainFrame:StopMovingOrSizing()
        -- Save size
        local w, h = mainFrame:GetSize()
        if FB.db and FB.db.settings and FB.db.settings.ui then
            FB.db.settings.ui.mainFrameW = math.floor(w)
            FB.db.settings.ui.mainFrameH = math.floor(h)
        end
    end)

    -- Title
    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetText(FB.ADDON_COLOR .. "FarmBuddy|r")

    -- Close button: use standard WoW UIPanelCloseButton template for proper appearance
    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        mainFrame:Hide()
    end)

    -- ESC to close
    table.insert(UISpecialFrames, "FarmBuddyMainFrame")

    -- Store reference early so TabManager can access it
    FB.mainFrame = mainFrame

    -- Initialize tabs
    FB.TabManager:Init(mainFrame)

    -- Initialize tab content modules (pcall to catch errors and keep loading)
    local tabInits = {
        { name = "MountSearchTab",       module = FB.UI.MountSearchTab,       tab = FB.TABS.MOUNT_SEARCH },
        { name = "MountRecommendTab",    module = FB.UI.MountRecommendTab,    tab = FB.TABS.MOUNT_RECOMMEND },
        { name = "SessionTab",           module = FB.UI.SessionTab,           tab = FB.TABS.SESSION },
        { name = "AchievementTab",       module = FB.UI.AchievementTab,       tab = FB.TABS.ACHIEVEMENTS },
        { name = "WeeklyTab",            module = FB.UI.WeeklyTab,            tab = FB.TABS.WEEKLY },
        { name = "ExpansionProgressTab", module = FB.UI.ExpansionProgressTab, tab = FB.TABS.EXPANSION_PROGRESS },
        { name = "SettingsTab",          module = FB.UI.SettingsTab,          tab = FB.TABS.SETTINGS },
    }

    for _, info in ipairs(tabInits) do
        if info.module and info.module.Init then
            local panel = FB.TabManager:GetPanel(info.tab)
            if panel then
                local ok, err = pcall(info.module.Init, info.module, panel)
                if not ok then
                    -- Show error on the panel so it's visible
                    local errText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    errText:SetPoint("CENTER")
                    errText:SetText("|cFFFF0000Error loading " .. info.name .. ":|r\n" .. tostring(err))
                    errText:SetJustifyH("CENTER")
                    errText:SetWidth(500)
                    print("|cFFFF0000FarmBuddy:|r Error in " .. info.name .. ": " .. tostring(err))
                end
            end
        end
    end

    mainFrame:Hide()

    return mainFrame
end

-- Toggle main window visibility
function FB.UI:Toggle()
    if not mainFrame then
        self:CreateMainFrame()
    end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

-- Show the main window
function FB.UI:Show()
    if not mainFrame then
        self:CreateMainFrame()
    end
    mainFrame:Show()
end

-- Hide the main window
function FB.UI:Hide()
    if mainFrame then
        mainFrame:Hide()
    end
end

-- Reset window position to center
function FB.UI:ResetPosition()
    if mainFrame then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER")
        if FB.db and FB.db.settings and FB.db.settings.ui then
            FB.db.settings.ui.mainFramePoint = "CENTER"
            FB.db.settings.ui.mainFrameRelPoint = "CENTER"
            FB.db.settings.ui.mainFrameX = 0
            FB.db.settings.ui.mainFrameY = 0
        end
    end
end

-- Create the frame when player enters world (delayed init)
FB:RegisterEvent("PLAYER_ENTERING_WORLD", FB.UI, function(self, event, isLogin, isReload)
    -- Pre-create frame so it's ready when user types /fb
    if not mainFrame then
        C_Timer.After(1, function()
            FB.UI:CreateMainFrame()
        end)
    end
end)
