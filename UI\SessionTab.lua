local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.SessionTab = {}

local panel
local contentText
local scrollFrame
local scrollChild
local scrollBar
local timeBudget = 60  -- Default 60 minutes
local lastPlan = nil

function FB.UI.SessionTab:Init(parentPanel)
    panel = parentPanel

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 5, -5)
    title:SetText("Session Planner")

    -- Time budget controls
    local budgetLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    budgetLabel:SetPoint("TOPLEFT", 5, -30)
    budgetLabel:SetText("Time budget:")

    local budgetOptions = {
        { value = 30,  label = "30 min" },
        { value = 60,  label = "1 hour" },
        { value = 90,  label = "1.5 hours" },
        { value = 120, label = "2 hours" },
        { value = 180, label = "3 hours" },
    }

    local prevAnchor = budgetLabel
    self.budgetButtons = {}
    for i, opt in ipairs(budgetOptions) do
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(65, 22)
        if i == 1 then
            btn:SetPoint("LEFT", budgetLabel, "RIGHT", 8, 0)
        else
            btn:SetPoint("LEFT", self.budgetButtons[i - 1], "RIGHT", 4, 0)
        end
        btn:SetText(opt.label)
        btn:SetNormalFontObject("GameFontNormalSmall")

        btn:SetScript("OnClick", function()
            timeBudget = opt.value
            self:UpdateButtonHighlights()
            self:GenerateSessionPlan()
        end)

        self.budgetButtons[i] = btn
        btn._value = opt.value
    end

    -- Solo only checkbox
    local soloCB = CreateFrame("CheckButton", "FarmBuddySessionSoloCB", panel, "UICheckButtonTemplate")
    soloCB:SetSize(22, 22)
    soloCB:SetPoint("LEFT", self.budgetButtons[#self.budgetButtons], "RIGHT", 12, 0)
    soloCB:SetChecked(true)
    self.soloOnly = true
    local soloLabel = soloCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    soloLabel:SetPoint("LEFT", soloCB, "RIGHT", 2, 0)
    soloLabel:SetText("Solo Only")
    soloCB:SetScript("OnClick", function(self2)
        FB.UI.SessionTab.soloOnly = self2:GetChecked()
        FB.UI.SessionTab:GenerateSessionPlan()
    end)

    -- Generate button
    local genBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    genBtn:SetSize(120, 24)
    genBtn:SetPoint("TOPRIGHT", -5, -5)
    genBtn:SetText("Generate Plan")
    genBtn:SetScript("OnClick", function()
        FB.UI.SessionTab:GenerateSessionPlan()
    end)
    self.genBtn = genBtn

    -- Weekly plan button
    local weeklyBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    weeklyBtn:SetSize(120, 24)
    weeklyBtn:SetPoint("RIGHT", genBtn, "LEFT", -6, 0)
    weeklyBtn:SetText("Weekly Plan")
    weeklyBtn:SetScript("OnClick", function()
        FB.UI.SessionTab:ShowWeeklyPlan()
    end)

    -- Pin plan to tracker button
    local pinBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    pinBtn:SetSize(120, 24)
    pinBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
    pinBtn:SetText("Pin to Tracker")
    pinBtn:SetScript("OnClick", function()
        FB.UI.SessionTab:PinPlanToTracker()
    end)
    pinBtn:Hide()
    self.pinBtn = pinBtn

    -- Scrollable content area
    scrollFrame = CreateFrame("ScrollFrame", "FarmBuddySessionScroll", panel)
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -58)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 35)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)

    contentText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    contentText:SetPoint("TOPLEFT", 0, 0)
    contentText:SetWidth(700)
    contentText:SetJustifyH("LEFT")
    contentText:SetWordWrap(true)
    contentText:SetText(FB.COLORS.GRAY .. "Click 'Generate Plan' to build an optimized farming session.\nRequires a mount scan (run from Recommendations tab first).|r")

    -- Scrollbar
    scrollBar = CreateFrame("Slider", "FarmBuddySessionScrollBar", panel, "BackdropTemplate")
    scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -58)
    scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 35)
    scrollBar:SetWidth(14)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetMinMaxValues(0, 1)
    scrollBar:SetValue(0)
    scrollBar:SetValueStep(20)
    scrollBar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    scrollBar:SetBackdropColor(0.05, 0.05, 0.05, 0.5)
    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    thumb:SetSize(10, 30)
    scrollBar:SetThumbTexture(thumb)
    scrollBar:Hide()

    scrollBar:SetScript("OnValueChanged", function(self2, value)
        scrollFrame:SetVerticalScroll(value)
    end)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self2, delta)
        local current = self2:GetVerticalScroll()
        local maxScroll = math.max(0, scrollChild:GetHeight() - self2:GetHeight())
        local newScroll = math.max(0, math.min(maxScroll, current - (delta * 30)))
        self2:SetVerticalScroll(newScroll)
        scrollBar:SetValue(newScroll)
    end)

    scrollFrame:SetScript("OnSizeChanged", function(self2, w)
        if w and w > 10 then
            scrollChild:SetWidth(w)
            contentText:SetWidth(w)
        end
    end)

    -- Status label
    local statusLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 5, 10)
    statusLabel:SetTextColor(0.5, 0.5, 0.5)
    self.statusLabel = statusLabel

    self:UpdateButtonHighlights()
end

function FB.UI.SessionTab:UpdateButtonHighlights()
    for _, btn in ipairs(self.budgetButtons or {}) do
        if btn._value == timeBudget then
            btn:SetNormalFontObject("GameFontHighlightSmall")
        else
            btn:SetNormalFontObject("GameFontNormalSmall")
        end
    end
end

function FB.UI.SessionTab:OnShow()
    -- Auto-generate if we have cached results
    local cached = FB.db and FB.db.cachedMountScores
    if cached and #cached > 0 and not lastPlan then
        self:GenerateSessionPlan()
    end
end

function FB.UI.SessionTab:GenerateSessionPlan()
    local cached = FB.db and FB.db.cachedMountScores
    if not cached or #cached == 0 then
        contentText:SetText(FB.COLORS.YELLOW .. "No mount scan data available.\n\nPlease run a scan from the Recommendations tab first, then return here.|r")
        self.statusLabel:SetText("")
        if self.pinBtn then self.pinBtn:Hide() end
        return
    end

    if not FB.SessionPlanner then
        contentText:SetText(FB.COLORS.RED .. "Session Planner module not loaded.|r")
        return
    end

    local filters = {}
    if self.soloOnly then filters.soloOnly = true end

    lastPlan = FB.SessionPlanner:GeneratePlan(cached, timeBudget, filters)
    local text = FB.SessionPlanner:FormatPlan(lastPlan)

    -- Add character recommendations if available
    if lastPlan and lastPlan.activities and #lastPlan.activities > 0 then
        local charLines = {}
        for _, activity in ipairs(lastPlan.activities) do
            local bestChar = FB.SessionPlanner:GetBestCharForActivity(activity)
            if bestChar and bestChar ~= FB.playerKey then
                local shortName = bestChar:match("^(.-)%s*-") or bestChar
                charLines[#charLines + 1] = string.format(
                    "  %s -> %s",
                    activity.instanceName or activity.mounts[1].name,
                    shortName
                )
            end
        end
        if #charLines > 0 then
            text = text .. "\n\nAlt Recommendations:\n" .. table.concat(charLines, "\n")
        end
    end

    contentText:SetText(text)

    -- Update scroll
    C_Timer.After(0, function()
        if contentText and scrollChild and scrollFrame then
            local scrollWidth = scrollFrame:GetWidth()
            if scrollWidth and scrollWidth > 10 then
                scrollChild:SetWidth(scrollWidth)
                contentText:SetWidth(scrollWidth)
            end
            local textHeight = contentText:GetStringHeight() or 100
            scrollChild:SetHeight(textHeight + 8)
            scrollFrame:SetVerticalScroll(0)
            local maxScroll = math.max(0, textHeight + 8 - scrollFrame:GetHeight())
            if scrollBar then
                if maxScroll > 0 then
                    scrollBar:SetMinMaxValues(0, maxScroll)
                    scrollBar:SetValue(0)
                    scrollBar:Show()
                else
                    scrollBar:Hide()
                end
            end
        end
    end)

    self.statusLabel:SetText(string.format(
        "%d activities planned | %d min of %d min budget | %d mount chances",
        lastPlan and #lastPlan.activities or 0,
        lastPlan and lastPlan.totalMinutes or 0,
        timeBudget,
        lastPlan and lastPlan.expectedMounts or 0
    ))

    if lastPlan and #lastPlan.activities > 0 then
        self.pinBtn:Show()
    else
        self.pinBtn:Hide()
    end
end

function FB.UI.SessionTab:ShowWeeklyPlan()
    if not FB.WeeklyPlanner then
        contentText:SetText(FB.COLORS.RED .. "Weekly Planner module not loaded.|r")
        return
    end

    local plan = FB.WeeklyPlanner:GenerateWeeklyPlan()
    local text = FB.WeeklyPlanner:FormatPlan(plan)

    contentText:SetText(text)
    lastPlan = nil  -- Clear session plan reference
    if self.pinBtn then self.pinBtn:Hide() end

    self.statusLabel:SetText(string.format(
        "Weekly plan: %d mounts | %d near completion | %d active events",
        plan.totalMounts,
        plan.nearCompletions and #plan.nearCompletions or 0,
        plan.activeEvents and #plan.activeEvents or 0
    ))

    -- Update scroll
    C_Timer.After(0, function()
        if contentText and scrollChild and scrollFrame then
            local textHeight = contentText:GetStringHeight() or 100
            scrollChild:SetHeight(textHeight + 8)
            scrollFrame:SetVerticalScroll(0)
        end
    end)
end

function FB.UI.SessionTab:PinPlanToTracker()
    if not lastPlan or not lastPlan.activities or #lastPlan.activities == 0 then return end

    local steps = {}
    for i, activity in ipairs(lastPlan.activities) do
        if activity.type == "instance" then
            steps[#steps + 1] = string.format(
                "%s (~%dmin, %d mount%s)",
                activity.instanceName, activity.timeMinutes,
                activity.mountCount, activity.mountCount > 1 and "s" or ""
            )
        else
            local mount = activity.mounts[1]
            steps[#steps + 1] = string.format(
                "%s (~%dmin)", mount.name, activity.timeMinutes
            )
        end
    end

    FB.Tracker:Pin("mount", 0, string.format(
        "Session Plan (%dmin)", lastPlan.totalMinutes
    ), steps)
    FB:Print("Session plan pinned to tracker.")
end
