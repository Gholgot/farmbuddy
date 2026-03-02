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

-- Clickable activity rows (improvement #12)
local activityRows = {}

-- Scan-Now button and progress label (improvement #4)
local scanNowBtn
local scanProgressLabel

local function ClearActivityRows()
    for _, row in ipairs(activityRows) do
        if row.frame then row.frame:Hide() end
    end
    activityRows = {}
end

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

    -- Improvement #4: "Scan Now" button shown when no scan data is available
    scanNowBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    scanNowBtn:SetSize(160, 28)
    scanNowBtn:SetPoint("TOP", scrollChild, "TOP", 0, -80)
    scanNowBtn:SetText("Scan Mounts Now")
    scanNowBtn:Hide()
    scanNowBtn:SetScript("OnClick", function()
        scanNowBtn:Hide()
        if scanProgressLabel then
            scanProgressLabel:SetText(FB.COLORS.YELLOW .. "Scanning mounts... 0 / ?|r")
            scanProgressLabel:Show()
        end
        if contentText then contentText:Hide() end
        if FB.Mounts and FB.Mounts.Scanner then
            FB.Mounts.Scanner:StartScan(
                function(current, total)
                    if scanProgressLabel then
                        scanProgressLabel:SetText(FB.COLORS.YELLOW .. string.format("Scanning mounts... %d / %d|r", current, total))
                    end
                end,
                function(results)
                    if scanProgressLabel then scanProgressLabel:Hide() end
                    if contentText then contentText:Show() end
                    -- Cache results
                    if FB.db then
                        FB.db.cachedMountScores = results
                    end
                    -- Auto-populate the plan
                    FB.UI.SessionTab:GenerateSessionPlan()
                end
            )
        else
            if scanProgressLabel then scanProgressLabel:Hide() end
            if contentText then
                contentText:Show()
                contentText:SetText(FB.COLORS.RED .. "Mount Scanner module not loaded.|r")
            end
        end
    end)
    self.scanNowBtn = scanNowBtn

    -- Progress label shown during scan
    scanProgressLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scanProgressLabel:SetPoint("TOP", scanNowBtn, "BOTTOM", 0, -8)
    scanProgressLabel:SetWidth(400)
    scanProgressLabel:SetJustifyH("CENTER")
    scanProgressLabel:Hide()
    self.scanProgressLabel = scanProgressLabel

    -- Main content FontString (used for summary header and fallback text)
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
            -- Resize any existing activity rows to new width
            for _, row in ipairs(activityRows) do
                if row.frame then row.frame:SetWidth(w - 4) end
            end
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

-- Improvement #12: render structured activity rows instead of a single text blob
local function BuildActivityRows(plan, availableWidth)
    ClearActivityRows()
    if not plan or not plan.activities or #plan.activities == 0 then return end

    local ROW_HEIGHT = 28
    local yOff = 0
    -- Push rows below the summary header text
    local headerHeight = contentText:GetStringHeight() or 30
    yOff = -(headerHeight + 12)

    local rowWidth = (availableWidth and availableWidth > 10) and (availableWidth - 4) or 700

    for i, activity in ipairs(plan.activities) do
        -- Row container
        local rowFrame = CreateFrame("Button", nil, scrollChild)
        rowFrame:SetSize(rowWidth, ROW_HEIGHT)
        rowFrame:SetPoint("TOPLEFT", 0, yOff)

        -- Subtle background texture for hover
        local bgTex = rowFrame:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints()
        bgTex:SetColorTexture(0.3, 0.5, 1.0, 0)  -- alpha 0 = invisible by default

        -- Highlight on hover
        rowFrame:SetScript("OnEnter", function(self2)
            bgTex:SetColorTexture(0.3, 0.5, 1.0, 0.12)
        end)
        rowFrame:SetScript("OnLeave", function(self2)
            bgTex:SetColorTexture(0.3, 0.5, 1.0, 0)
            GameTooltip:Hide()
        end)

        -- Activity label (left side)
        local actLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        actLabel:SetPoint("LEFT", 4, 0)
        actLabel:SetWidth(math.floor(rowWidth * 0.55))
        actLabel:SetJustifyH("LEFT")
        actLabel:SetWordWrap(false)

        local timeLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeLabel:SetPoint("RIGHT", -4, 0)
        timeLabel:SetWidth(math.floor(rowWidth * 0.15))
        timeLabel:SetJustifyH("RIGHT")
        timeLabel:SetTextColor(0.7, 0.7, 0.7)

        local mountCountLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mountCountLabel:SetPoint("RIGHT", timeLabel, "LEFT", -8, 0)
        mountCountLabel:SetWidth(math.floor(rowWidth * 0.25))
        mountCountLabel:SetJustifyH("RIGHT")
        mountCountLabel:SetTextColor(0.8, 0.8, 0.4)

        -- Separator line
        local sep = rowFrame:CreateTexture(nil, "BACKGROUND")
        sep:SetPoint("BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", 0, 0)
        sep:SetHeight(1)
        sep:SetColorTexture(0.3, 0.3, 0.3, 0.4)

        if activity.type == "instance" then
            actLabel:SetText(string.format("%d. %s", i, activity.instanceName or "Unknown Instance"))
            local mStr = activity.mountCount == 1 and "1 mount" or (activity.mountCount .. " mounts")
            mountCountLabel:SetText(FB.COLORS.GOLD .. mStr .. "|r")
        else
            local mount = activity.mounts[1]
            actLabel:SetText(string.format("%d. %s", i, mount and mount.name or "Unknown"))
            mountCountLabel:SetText(FB.COLORS.GOLD .. "1 mount|r")
        end
        timeLabel:SetText(string.format("~%d min", activity.timeMinutes))

        -- Click: show tooltip with individual mounts and scores
        local act = activity  -- capture
        rowFrame:SetScript("OnClick", function(self2)
            GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
            if act.type == "instance" then
                GameTooltip:SetText(act.instanceName or "Instance", 1, 0.82, 0, true)
            else
                local m = act.mounts[1]
                GameTooltip:SetText(m and m.name or "Mount", 1, 0.82, 0, true)
            end
            GameTooltip:AddLine(string.format("~%d min | %d mount chance%s",
                act.timeMinutes, act.mountCount, act.mountCount ~= 1 and "s" or ""), 0.8, 0.8, 0.8, false)
            GameTooltip:AddLine(" ", 1, 1, 1)
            for _, m in ipairs(act.mounts) do
                local scoreStr = m.score and string.format("[Score: %d]", m.score) or ""
                local dropStr = ""
                if m.dropChance then
                    dropStr = string.format("  %.1f%%", m.dropChance * 100)
                end
                GameTooltip:AddDoubleLine(
                    (m.name or "?") .. dropStr,
                    scoreStr,
                    1, 1, 1, 0.7, 0.7, 0.4
                )
            end
            GameTooltip:Show()
        end)

        activityRows[#activityRows + 1] = {
            frame = rowFrame,
            bgTex = bgTex,
            activity = activity,
        }

        yOff = yOff - ROW_HEIGHT
    end

    -- Return total content height
    return math.abs(yOff) + 8
end

function FB.UI.SessionTab:GenerateSessionPlan()
    local cached = FB.db and FB.db.cachedMountScores
    if not cached or #cached == 0 then
        -- Improvement #4: show inline Scan Now button instead of plain text
        contentText:Hide()
        ClearActivityRows()
        scanProgressLabel:Hide()
        scanNowBtn:Show()
        -- Show explanatory text near the button
        contentText:SetText(FB.COLORS.YELLOW .. "No mount scan data available.\n\nClick the button below to scan mounts now, or visit the Recommendations tab first.|r")
        contentText:Show()
        self.statusLabel:SetText("")
        if self.pinBtn then self.pinBtn:Hide() end
        -- Resize scroll content
        C_Timer.After(0, function()
            if scrollChild and scrollFrame then
                local h = math.max(200, contentText:GetStringHeight() + 140)
                scrollChild:SetHeight(h)
            end
        end)
        return
    end

    -- Hide scan controls if visible
    scanNowBtn:Hide()
    scanProgressLabel:Hide()
    contentText:Show()

    if not FB.SessionPlanner then
        contentText:SetText(FB.COLORS.RED .. "Session Planner module not loaded.|r")
        ClearActivityRows()
        return
    end

    local filters = {}
    if self.soloOnly then filters.soloOnly = true end

    lastPlan = FB.SessionPlanner:GeneratePlan(cached, timeBudget, filters)

    -- Add character recommendations to summary header
    local headerLines = {}
    headerLines[#headerLines + 1] = string.format(
        FB.COLORS.GOLD .. "Session Plan: %d activities, ~%d min (%d mount chances)|r",
        lastPlan and #lastPlan.activities or 0,
        lastPlan and lastPlan.totalMinutes or 0,
        lastPlan and lastPlan.expectedMounts or 0
    )

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
            headerLines[#headerLines + 1] = FB.COLORS.GRAY .. "Alt Recommendations:|r"
            for _, l in ipairs(charLines) do
                headerLines[#headerLines + 1] = FB.COLORS.GRAY .. l .. "|r"
            end
        end
    end

    contentText:SetText(table.concat(headerLines, "\n"))

    -- Improvement #12: build clickable activity rows
    C_Timer.After(0, function()
        if contentText and scrollChild and scrollFrame then
            local scrollWidth = scrollFrame:GetWidth()
            if scrollWidth and scrollWidth > 10 then
                scrollChild:SetWidth(scrollWidth)
                contentText:SetWidth(scrollWidth)
            end

            local rowsContentHeight = BuildActivityRows(lastPlan, scrollWidth)
            local headerHeight = contentText:GetStringHeight() or 30
            local totalHeight = headerHeight + (rowsContentHeight or 0) + 20
            scrollChild:SetHeight(totalHeight)
            scrollFrame:SetVerticalScroll(0)

            local maxScroll = math.max(0, totalHeight - scrollFrame:GetHeight())
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

    -- Hide scan controls
    scanNowBtn:Hide()
    scanProgressLabel:Hide()
    contentText:Show()
    ClearActivityRows()

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
