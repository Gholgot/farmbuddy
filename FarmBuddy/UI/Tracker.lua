local addonName, FB = ...

FB.Tracker = {}

local trackerFrame = nil
local linePool = {}
local unpinBtnPool = {}
local activeLineCount = 0
local activeUnpinCount = 0

-- Initialize the tracker frame
function FB.Tracker:Init()
    if trackerFrame then return end

    trackerFrame = CreateFrame("Frame", "FarmBuddyTracker", UIParent, "BackdropTemplate")
    trackerFrame:SetSize(280, 80)
    trackerFrame:SetFrameStrata("MEDIUM")
    trackerFrame:SetFrameLevel(50)
    trackerFrame:SetClampedToScreen(true)
    trackerFrame:SetMovable(true)
    trackerFrame:EnableMouse(true)
    trackerFrame:RegisterForDrag("LeftButton")

    -- Position from saved vars
    local ui = FB.db and FB.db.settings and FB.db.settings.ui
    if ui and ui.trackerPoint then
        trackerFrame:SetPoint(
            ui.trackerPoint,
            UIParent,
            ui.trackerRelPoint or ui.trackerPoint,
            ui.trackerX or -20,
            ui.trackerY or 0
        )
    else
        trackerFrame:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
    end

    -- Backdrop
    trackerFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    trackerFrame:SetBackdropColor(0.0, 0.0, 0.05, 0.85)
    trackerFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    -- Dragging
    trackerFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    trackerFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if FB.db and FB.db.settings and FB.db.settings.ui then
            FB.db.settings.ui.trackerPoint = point
            FB.db.settings.ui.trackerRelPoint = relPoint
            FB.db.settings.ui.trackerX = x
            FB.db.settings.ui.trackerY = y
        end
    end)

    -- Header bar background
    local headerBg = trackerFrame:CreateTexture(nil, "ARTWORK")
    headerBg:SetPoint("TOPLEFT", 2, -2)
    headerBg:SetPoint("TOPRIGHT", -2, -2)
    headerBg:SetHeight(22)
    headerBg:SetColorTexture(0.0, 0.3, 0.5, 0.5)

    -- Title
    local titleText = trackerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("LEFT", headerBg, "LEFT", 6, 0)
    titleText:SetText(FB.ADDON_COLOR .. "FarmBuddy Tracker|r")

    -- Close button (manual text button)
    local closeBtn = CreateFrame("Button", nil, trackerFrame)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", headerBg, "RIGHT", -2, 0)

    local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    closeBg:SetColorTexture(0, 0, 0, 0)

    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeBtnText:SetPoint("CENTER", 0, 0)
    closeBtnText:SetText("|cFFFF6666X|r")

    local closeHighlight = closeBtn:CreateTexture(nil, "HIGHLIGHT")
    closeHighlight:SetAllPoints()
    closeHighlight:SetColorTexture(1.0, 0.0, 0.0, 0.25)

    closeBtn:SetScript("OnClick", function()
        trackerFrame:Hide()
    end)

    trackerFrame:Hide()
end

-- Pin an item to the tracker
function FB.Tracker:Pin(itemType, id, name, steps)
    if not trackerFrame then self:Init() end

    if FB.db then
        if itemType == "mount" then
            FB.db.pinnedMounts = FB.db.pinnedMounts or {}
            FB.db.pinnedMounts[id] = { name = name, steps = steps or {} }
        elseif itemType == "achievement" then
            FB.db.pinnedAchievements = FB.db.pinnedAchievements or {}
            FB.db.pinnedAchievements[id] = { name = name, steps = steps or {} }
        end
    end

    self:Refresh()
    trackerFrame:Show()
end

-- Unpin an item
function FB.Tracker:Unpin(itemType, id)
    if FB.db then
        if itemType == "mount" and FB.db.pinnedMounts then
            FB.db.pinnedMounts[id] = nil
        elseif itemType == "achievement" and FB.db.pinnedAchievements then
            FB.db.pinnedAchievements[id] = nil
        end
    end

    self:Refresh()

    -- Hide tracker if nothing left
    local hasPinned = false
    if FB.db then
        if FB.db.pinnedMounts and next(FB.db.pinnedMounts) then hasPinned = true end
        if FB.db.pinnedAchievements and next(FB.db.pinnedAchievements) then hasPinned = true end
    end
    if not hasPinned and trackerFrame then
        trackerFrame:Hide()
    end
end

-- Toggle tracker
function FB.Tracker:Toggle()
    if not trackerFrame then self:Init() end
    if trackerFrame:IsShown() then
        trackerFrame:Hide()
    else
        self:Refresh()
        trackerFrame:Show()
    end
end

-- Get or create a font string line from pool
local function AcquireLine(index)
    if not linePool[index] then
        local line = trackerFrame:CreateFontString(nil, "OVERLAY")
        line:SetJustifyH("LEFT")
        line:SetWordWrap(true)
        linePool[index] = line
    end
    local line = linePool[index]
    -- Reset all properties
    line:ClearAllPoints()
    line:SetWidth(240)
    line:SetTextColor(1, 1, 1, 1)
    line:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    line:SetText("")
    line:Show()
    return line
end

-- Get or create an unpin button from pool
local function AcquireUnpinBtn(index, itemType, itemID)
    if not unpinBtnPool[index] then
        local btn = CreateFrame("Button", nil, trackerFrame)
        btn:SetSize(14, 14)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.3, 0.0, 0.0, 0.3)

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", 0, 1)
        text:SetText("|cFFAA6666x|r")
        btn.label = text

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1.0, 0.2, 0.2, 0.4)

        btn:SetScript("OnEnter", function(self)
            self.label:SetText("|cFFFF4444x|r")
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Unpin this item")
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self.label:SetText("|cFFAA6666x|r")
            GameTooltip:Hide()
        end)

        unpinBtnPool[index] = btn
    end

    local btn = unpinBtnPool[index]
    btn:ClearAllPoints()
    btn:SetScript("OnClick", function()
        FB.Tracker:Unpin(itemType, itemID)
    end)
    btn:Show()
    return btn
end

-- Hide all pool items
local function HideAll()
    for i = 1, #linePool do
        linePool[i]:Hide()
        linePool[i]:ClearAllPoints()
    end
    for i = 1, #unpinBtnPool do
        unpinBtnPool[i]:Hide()
        unpinBtnPool[i]:ClearAllPoints()
    end
end

-- Refresh tracker content
function FB.Tracker:Refresh()
    if not trackerFrame then self:Init() end

    HideAll()

    local yOffset = -28  -- Below header
    local lineIdx = 0
    local unpinIdx = 0
    local hasContent = false

    -- Build a set of completed criteria descriptions for an achievement (for step matching)
    local function GetCompletedCriteriaForAchievement(achievementID)
        local completed = {}
        if not GetAchievementNumCriteria then return completed end
        local numCriteria = GetAchievementNumCriteria(achievementID)
        if not numCriteria then return completed end
        for i = 1, numCriteria do
            local ok, criteriaString, _, criteriaCompleted = pcall(
                GetAchievementCriteriaInfo, achievementID, i
            )
            if ok and criteriaCompleted and criteriaString then
                completed[criteriaString] = true
            end
        end
        return completed
    end

    -- Helper to add one pinned item
    local function AddPinnedItem(itemType, id, data, color)
        hasContent = true

        -- Unpin button
        unpinIdx = unpinIdx + 1
        local btn = AcquireUnpinBtn(unpinIdx, itemType, id)
        btn:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 6, yOffset)

        -- Name line
        lineIdx = lineIdx + 1
        local nameLine = AcquireLine(lineIdx)
        nameLine:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
        nameLine:SetWidth(240)
        nameLine:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 24, yOffset)
        nameLine:SetText(color .. (data.name or (itemType .. " " .. id)) .. "|r")
        yOffset = yOffset - 16

        -- Steps
        if data.steps and #data.steps > 0 then
            -- #13: For achievements, check live criteria completion to mark steps
            local completedCriteria = {}
            if itemType == "achievement" and id and id ~= 0 then
                completedCriteria = GetCompletedCriteriaForAchievement(id)
            end

            for _, step in ipairs(data.steps) do
                -- #13: Determine if this step is completed
                local isCompleted = completedCriteria[step] == true

                lineIdx = lineIdx + 1
                local stepLine = AcquireLine(lineIdx)
                stepLine:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
                stepLine:SetWidth(232)
                stepLine:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 28, yOffset)

                if isCompleted then
                    -- Green checkmark texture + grayed-out text
                    stepLine:SetTextColor(0.5, 0.5, 0.5, 1.0)
                    stepLine:SetText(
                        "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:10:10|t |cFF888888" .. step .. "|r"
                    )
                else
                    -- White bullet for pending steps
                    stepLine:SetTextColor(0.8, 0.8, 0.8, 1.0)
                    stepLine:SetText("|cFFFFFFFF\226\128\162|r " .. step)
                end

                -- Calculate the height of the step text
                local textHeight = stepLine:GetStringHeight()
                if textHeight and textHeight > 0 then
                    yOffset = yOffset - math.max(textHeight, 13)
                else
                    yOffset = yOffset - 13
                end
            end
        end
        yOffset = yOffset - 8  -- Spacing between items
    end

    -- Display pinned mounts
    if FB.db and FB.db.pinnedMounts then
        for id, data in pairs(FB.db.pinnedMounts) do
            AddPinnedItem("mount", id, data, FB.COLORS.GOLD)
        end
    end

    -- Display pinned achievements
    if FB.db and FB.db.pinnedAchievements then
        for id, data in pairs(FB.db.pinnedAchievements) do
            AddPinnedItem("achievement", id, data, FB.COLORS.BLUE)
        end
    end

    if not hasContent then
        lineIdx = lineIdx + 1
        local emptyLine = AcquireLine(lineIdx)
        emptyLine:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        emptyLine:SetTextColor(0.5, 0.5, 0.5, 1.0)
        emptyLine:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 10, yOffset)
        emptyLine:SetText("No items pinned.\nPin items from FarmBuddy.")
        yOffset = yOffset - 30
    end

    -- Resize frame to fit
    local height = math.abs(yOffset) + 6
    trackerFrame:SetHeight(math.max(60, height))
end

-- Show
function FB.Tracker:Show()
    if not trackerFrame then self:Init() end
    self:Refresh()
    trackerFrame:Show()
end

-- Hide
function FB.Tracker:Hide()
    if trackerFrame then trackerFrame:Hide() end
end

-- Auto-show on login if items pinned (only on initial login/reload, not zone transitions)
FB:RegisterEvent("PLAYER_ENTERING_WORLD", FB.Tracker, function(self, event, isLogin, isReload)
    -- Only auto-show on initial login or /reload, not zone transitions
    if not isLogin and not isReload then return end

    C_Timer.After(3, function()
        FB.Tracker:Init()
        if FB.db then
            local hasPinned = false
            if FB.db.pinnedMounts and next(FB.db.pinnedMounts) then hasPinned = true end
            if FB.db.pinnedAchievements and next(FB.db.pinnedAchievements) then hasPinned = true end
            if hasPinned then
                FB.Tracker:Refresh()
                trackerFrame:Show()
            end
        end
    end)
end)
