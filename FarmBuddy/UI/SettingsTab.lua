local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.SettingsTab = {}

local panel
local sliders = {}
local previewLines = {}
local previewStatusLine = nil
local rescanBtn = nil
local isScanning = false

-- ARCH-4: Debounce preview updates so rapid slider drags don't re-score all cached
-- mounts on every tick. Only the final resting position triggers a rescore.
local previewDirty = false
local previewTimer = nil

local function SchedulePreviewUpdate(self)
    previewDirty = true
    if previewTimer then previewTimer:Cancel() end
    previewTimer = C_Timer.NewTimer(0.2, function()
        if previewDirty then
            previewDirty = false
            FB.UI.SettingsTab:UpdatePreview()
        end
    end)
end

function FB.UI.SettingsTab:Init(parentPanel)
    panel = parentPanel

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 5, -5)
    title:SetText("Settings")

    local yOffset = -35

    -- Scoring Weights Section
    local weightsHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    weightsHeader:SetPoint("TOPLEFT", 10, yOffset)
    weightsHeader:SetText(FB.COLORS.GOLD .. "Scoring Weights|r")
    yOffset = yOffset - 10

    local weightsDesc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    weightsDesc:SetPoint("TOPLEFT", 10, yOffset)
    weightsDesc:SetTextColor(0.6, 0.6, 0.6)
    weightsDesc:SetText("Adjust how much each factor affects the difficulty score. Higher = more impact.")
    yOffset = yOffset - 25

    local weightDefs = {
        { key = "progressRemaining", label = "Progress Remaining",  desc = "Weight of incomplete progress (rep, criteria, etc.)" },
        { key = "timePerAttempt",    label = "Time Per Attempt",    desc = "Weight of how long each attempt takes" },
        { key = "timeGate",          label = "Time-Gating Penalty", desc = "Weight of lockout restrictions (weekly, daily)" },
        { key = "groupRequirement",  label = "Group Requirement",   desc = "Weight of needing other players" },
        { key = "effort",            label = "RNG / Total Effort",  desc = "Weight of expected total time (drop rates)" },
    }

    for _, def in ipairs(weightDefs) do
        local slider = self:CreateWeightSlider(panel, def.key, def.label, def.desc, yOffset)
        sliders[def.key] = slider
        yOffset = yOffset - 55
    end

    -- Weight Preview Section (shows top 5 mounts with current weights)
    yOffset = yOffset - 5
    local previewHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewHeader:SetPoint("TOPLEFT", 430, -45)
    previewHeader:SetText(FB.COLORS.GOLD .. "Preview (Top 5)|r")

    local previewDesc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewDesc:SetPoint("TOPLEFT", 430, -58)
    previewDesc:SetTextColor(0.5, 0.5, 0.5)
    previewDesc:SetText("Shows how weights affect recommendations")

    -- Create 5 preview lines
    for i = 1, 5 do
        local line = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        line:SetPoint("TOPLEFT", 430, -68 - (i * 16))
        line:SetWidth(370)
        line:SetJustifyH("LEFT")
        line:SetText("")
        previewLines[i] = line
    end

    -- #20: Status line showing cached mount count
    previewStatusLine = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewStatusLine:SetPoint("TOPLEFT", 430, -68 - (6 * 16))
    previewStatusLine:SetWidth(370)
    previewStatusLine:SetJustifyH("LEFT")
    previewStatusLine:SetTextColor(0.5, 0.5, 0.5)
    previewStatusLine:SetText("")

    -- #20: Re-scan Now button
    rescanBtn = CreateFrame("Button", "FarmBuddySettingsRescanBtn", panel, "UIPanelButtonTemplate")
    rescanBtn:SetSize(110, 22)
    rescanBtn:SetPoint("TOPLEFT", 430, -68 - (7 * 16) - 4)
    rescanBtn:SetText("Re-scan Now")
    rescanBtn:SetScript("OnClick", function()
        if isScanning then return end
        isScanning = true
        rescanBtn:SetText("Scanning...")
        rescanBtn:SetEnabled(false)
        if previewStatusLine then
            previewStatusLine:SetText("|cFFFFAA00Scanning mounts...|r")
        end

        FB.Mounts.Scanner:StartScan(nil, function(results)
            isScanning = false
            if rescanBtn then
                rescanBtn:SetText("Re-scan Now")
                rescanBtn:SetEnabled(true)
            end
            -- UpdatePreview will pick up the freshly cached results
            FB.UI.SettingsTab:UpdatePreview()
        end)
    end)

    -- FIX-6: Playtime assumption section
    yOffset = yOffset - 15
    local playtimeHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playtimeHeader:SetPoint("TOPLEFT", 10, yOffset)
    playtimeHeader:SetText(FB.COLORS.GOLD .. "Playtime Assumption|r")
    yOffset = yOffset - 10

    local playtimeDesc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playtimeDesc:SetPoint("TOPLEFT", 10, yOffset)
    playtimeDesc:SetTextColor(0.6, 0.6, 0.6)
    playtimeDesc:SetText("How many hours per day you expect to play. Affects all time estimates.")
    yOffset = yOffset - 25

    local hoursSlider = self:CreateSlider(panel, "hoursPerDay", "Hours Per Day",
        "Average daily playtime for mount farming (shown in all estimates).",
        yOffset, 0.5, 8, 0.5,
        (FB.db and FB.db.settings and FB.db.settings.hoursPerDay) or 2,
        function(value)
            if FB.db and FB.db.settings then
                FB.db.settings.hoursPerDay = value
            end
            -- ARCH-4: debounce preview update so slider drags don't re-score every tick
            SchedulePreviewUpdate()
        end)
    sliders["hoursPerDay"] = hoursSlider
    yOffset = yOffset - 55

    -- Scan Settings Section
    yOffset = yOffset - 15
    local scanHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scanHeader:SetPoint("TOPLEFT", 10, yOffset)
    scanHeader:SetText(FB.COLORS.GOLD .. "Scan Settings|r")
    yOffset = yOffset - 25

    local batchSlider = self:CreateSlider(panel, "batchSize", "Batch Size",
        "Items per frame tick (0 = auto-adaptive). Higher = faster scan, more CPU.",
        yOffset, 0, 20, 1,
        (FB.db and FB.db.settings and FB.db.settings.scan and FB.db.settings.scan.batchSize) or 5,
        function(value)
            if FB.db and FB.db.settings and FB.db.settings.scan then
                FB.db.settings.scan.batchSize = math.floor(value)
            end
        end)
    sliders["batchSize"] = batchSlider
    yOffset = yOffset - 55

    -- Recommendations Section
    yOffset = yOffset - 15
    local recoHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    recoHeader:SetPoint("TOPLEFT", 10, yOffset)
    recoHeader:SetText(FB.COLORS.GOLD .. "Recommendations|r")
    yOffset = yOffset - 25

    local maxResultsSlider = self:CreateSlider(panel, "maxResults", "Default Results Count",
        "Default number of recommendations to show (0 = show all).",
        yOffset, 0, 100, 5,
        (FB.db and FB.db.settings and FB.db.settings.recommendations and FB.db.settings.recommendations.maxResults) or 20,
        function(value)
            if FB.db and FB.db.settings then
                FB.db.settings.recommendations = FB.db.settings.recommendations or {}
                FB.db.settings.recommendations.maxResults = math.floor(value)
            end
        end)
    sliders["maxResults"] = maxResultsSlider
    yOffset = yOffset - 55

    -- UI Section
    yOffset = yOffset - 15
    local uiHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    uiHeader:SetPoint("TOPLEFT", 10, yOffset)
    uiHeader:SetText(FB.COLORS.GOLD .. "UI Options|r")
    yOffset = yOffset - 25

    -- Minimap button toggle
    local minimapCB = CreateFrame("CheckButton", "FarmBuddySettingsCB_minimap", panel, "UICheckButtonTemplate")
    minimapCB:SetSize(22, 22)
    minimapCB:SetPoint("TOPLEFT", 10, yOffset)
    local minimapHidden = FB.db and FB.db.settings and FB.db.settings.ui and FB.db.settings.ui.hideMinimapButton
    minimapCB:SetChecked(not minimapHidden)

    local minimapLabel = minimapCB:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    minimapLabel:SetPoint("LEFT", minimapCB, "RIGHT", 4, 0)
    minimapLabel:SetText("Show Minimap Button")

    minimapCB:SetScript("OnClick", function(self)
        local show = self:GetChecked()
        if FB.db and FB.db.settings and FB.db.settings.ui then
            FB.db.settings.ui.hideMinimapButton = not show
        end
        if FB.MinimapButton then
            if show then
                FB.MinimapButton:Create()
            else
                -- Use Hide() directly if available to unconditionally hide the button;
                -- Toggle() could re-show it if the button is already hidden.
                if FB.MinimapButton.Hide then
                    FB.MinimapButton:Hide()
                elseif FB.MinimapButton.button and FB.MinimapButton.button:IsShown() then
                    FB.MinimapButton:Toggle()
                end
            end
        end
    end)
    yOffset = yOffset - 30

    -- Reset button
    yOffset = yOffset - 10
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(150, 28)
    resetBtn:SetPoint("TOPLEFT", 10, yOffset)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        FB.Storage:ResetSettings()
        FB.UI.SettingsTab:RefreshSliders()
    end)
end

function FB.UI.SettingsTab:OnShow()
    self:RefreshSliders()
    self:UpdatePreview()
end

function FB.UI.SettingsTab:CreateWeightSlider(parent, key, label, desc, yOffset)
    local currentValue = 1.0
    if FB.db and FB.db.settings and FB.db.settings.weights then
        -- Support both new 'effort' key and legacy 'dropChance' key
        currentValue = FB.db.settings.weights[key] or FB.db.settings.weights["dropChance"] or 1.0
    end

    return self:CreateSlider(parent, key, label, desc, yOffset, 0, 3, 0.1, currentValue, function(value)
        if FB.db and FB.db.settings and FB.db.settings.weights then
            FB.db.settings.weights[key] = value
        end
        -- ARCH-4: debounce preview update so slider drags don't re-score every tick
        SchedulePreviewUpdate()
    end)
end

function FB.UI.SettingsTab:CreateSlider(parent, key, label, desc, yOffset, minVal, maxVal, step, defaultVal, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", 10, yOffset)
    container:SetSize(400, 50)

    -- Determine display format: integers for step >= 1, decimals for fractional steps
    local displayFmt = step >= 1 and "%d" or "%.1f"
    local isAutoEnabled = (key == "batchSize")

    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOPLEFT", 0, 0)
    labelText:SetText(label)

    local descText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descText:SetPoint("TOPLEFT", 0, -14)
    descText:SetTextColor(0.5, 0.5, 0.5)
    descText:SetText(desc)

    -- Build slider manually (no template dependency)
    local slider = CreateFrame("Slider", "FarmBuddySlider_" .. key, container, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", 0, -34)
    slider:SetSize(300, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouse(true)
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })

    -- Thumb texture
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(16, 24)
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetThumbTexture(thumb)

    -- Min/Max labels
    local lowText = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, 0)
    lowText:SetText(isAutoEnabled and "Auto" or tostring(minVal))
    lowText:SetTextColor(0.5, 0.5, 0.5)

    local highText = slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, 0)
    highText:SetText(tostring(maxVal))
    highText:SetTextColor(0.5, 0.5, 0.5)

    -- Value display
    local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    valueText:SetWidth(50)

    local currentValue = defaultVal or minVal
    slider:SetValue(currentValue)

    local function FormatValue(value)
        if isAutoEnabled and value == 0 then
            return "Auto"
        end
        return string.format(displayFmt, value)
    end

    valueText:SetText(FormatValue(currentValue))

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        valueText:SetText(FormatValue(value))
        if onChange then
            onChange(value)
        end
    end)

    container.slider = slider
    container.valueText = valueText
    container.key = key
    container.onChange = onChange

    return container
end

function FB.UI.SettingsTab:RefreshSliders()
    if not FB.db or not FB.db.settings then return end

    local weights = FB.db.settings.weights
    for key, container in pairs(sliders) do
        if container.slider then
            -- Check weight sliders first
            if weights and weights[key] then
                container.slider:SetValue(weights[key])
            -- Support legacy dropChance key mapped to effort
            elseif key == "effort" and weights and weights["dropChance"] then
                container.slider:SetValue(weights["dropChance"])
            -- Check hoursPerDay
            elseif key == "hoursPerDay" and FB.db.settings.hoursPerDay then
                container.slider:SetValue(FB.db.settings.hoursPerDay)
            -- Check scan settings
            elseif key == "batchSize" and FB.db.settings.scan then
                container.slider:SetValue(FB.db.settings.scan.batchSize or 5)
            -- Check recommendations settings
            elseif key == "maxResults" and FB.db.settings.recommendations then
                container.slider:SetValue(FB.db.settings.recommendations.maxResults or 20)
            end
        end
    end
end

-- Update the live weight preview panel
function FB.UI.SettingsTab:UpdatePreview()
    if not FB.db or not FB.db.cachedMountScores or #FB.db.cachedMountScores == 0 then
        for i = 1, 5 do
            if previewLines[i] then
                previewLines[i]:SetText(i == 1 and "|cFF888888Run a scan first to see preview|r" or "")
            end
        end
        if previewStatusLine then
            previewStatusLine:SetText("|cFF888888No cached mounts — click Re-scan Now|r")
        end
        return
    end

    -- #20: Update cached mount count status line
    if previewStatusLine and not isScanning then
        local count = #FB.db.cachedMountScores
        previewStatusLine:SetText("|cFF888888Based on " .. count .. " cached mounts|r")
    end

    -- Re-score top cached mounts with current weights
    local weights = FB.Scoring:GetWeights()
    local scored = {}

    for _, cached in ipairs(FB.db.cachedMountScores) do
        -- Build minimal input from cached data
        local result = FB.Scoring:Score({
            progressRemaining = cached.progressRemaining or 1.0,
            timePerAttempt = cached.timePerAttempt or 10,
            timeGate = cached.timeGate or "none",
            attemptsRemaining = cached.immediatelyAvailable and 1 or 0,
            groupRequirement = cached.groupRequirement or "solo",
            dropChance = cached.dropChance,
            dropChanceSource = cached.dropChanceSource,
            expectedAttempts = cached.expectedAttempts,
        }, weights)

        scored[#scored + 1] = {
            name = cached.name,
            score = result.score,
            effectiveDays = result.effectiveDays,
        }
    end

    -- Sort by new score
    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return (a.name or "") < (b.name or "")
    end)

    -- Show top 5
    for i = 1, 5 do
        if previewLines[i] then
            if scored[i] then
                local s = scored[i]
                local scoreColor = FB.Utils:ColorByScore(
                    string.format("%.0f", s.score), s.score, 300
                )
                local timeStr = s.effectiveDays and FB.Utils:FormatDays(s.effectiveDays) or "?"
                previewLines[i]:SetText(string.format(
                    "%d. %s  %s  |cFF888888%s|r",
                    i, FB.Utils:Truncate(s.name or "?", 25), scoreColor, timeStr
                ))
            else
                previewLines[i]:SetText("")
            end
        end
    end
end
