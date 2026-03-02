local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.Widgets = FB.UI.Widgets or {}

--[[
    Shared mount detail panel used by both Recommend and Search tabs.
    Combines model preview, name/subtitle, collapsible score breakdown,
    scrollable detail text, and action buttons.

    @param parent  frame
    @param name    string
    @return widget table
--]]
function FB.UI.Widgets:CreateMountDetailPanel(parent, name)
    local widget = {}
    local selectedMount = nil

    -- Main container with backdrop
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.1, 0.9)
    widget.frame = frame

    -- 1. Model preview (top)
    local modelPreview = FB.UI.Widgets:CreateModelPreview(frame, name .. "Preview")
    modelPreview.frame:SetPoint("TOPLEFT", 0, 0)
    modelPreview.frame:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    modelPreview.frame:SetHeight(220)
    widget.modelPreview = modelPreview

    -- 2. Mount name header
    local detailHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detailHeader:SetPoint("TOPLEFT", modelPreview.frame, "BOTTOMLEFT", 8, -6)
    detailHeader:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    detailHeader:SetJustifyH("LEFT")
    detailHeader:SetWordWrap(false)
    detailHeader:SetText("")
    widget.detailHeader = detailHeader

    -- 3. Subtitle
    local detailSubtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailSubtitle:SetPoint("TOPLEFT", detailHeader, "BOTTOMLEFT", 0, -2)
    detailSubtitle:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    detailSubtitle:SetJustifyH("LEFT")
    detailSubtitle:SetTextColor(0.6, 0.6, 0.6)
    detailSubtitle:SetText("")
    widget.detailSubtitle = detailSubtitle

    -- 4. Separator
    local detailSeparator = frame:CreateTexture(nil, "ARTWORK")
    detailSeparator:SetHeight(1)
    detailSeparator:SetPoint("TOPLEFT", detailSubtitle, "BOTTOMLEFT", 0, -4)
    detailSeparator:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    detailSeparator:SetColorTexture(0.35, 0.35, 0.35, 0.8)

    -- 5. Collapsible score section
    local scoreToggle = CreateFrame("Button", nil, frame)
    scoreToggle:SetHeight(16)
    scoreToggle:SetPoint("TOPLEFT", detailSeparator, "BOTTOMLEFT", 0, -4)
    scoreToggle:SetPoint("RIGHT", frame, "RIGHT", -8, 0)

    local scoreArrow = scoreToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scoreArrow:SetPoint("LEFT", 0, 0)
    scoreArrow:SetTextColor(0.8, 0.8, 0.8)

    local scoreToggleLabel = scoreToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scoreToggleLabel:SetPoint("LEFT", scoreArrow, "RIGHT", 4, 0)
    scoreToggleLabel:SetTextColor(0.8, 0.8, 0.8)
    scoreToggleLabel:SetText("Score Breakdown")

    local scoreBar = FB.UI.Widgets:CreateScoreBar(frame, name .. "ScoreBar")
    scoreBar.frame:SetPoint("TOPLEFT", scoreToggle, "BOTTOMLEFT", 0, -2)
    scoreBar.frame:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    widget.scoreBar = scoreBar

    local hasScoreData = false

    local function UpdateLayout()
        local scoreExpanded = FB.db and FB.db.settings and FB.db.settings.ui
            and FB.db.settings.ui.scoreExpanded or false

        if not hasScoreData then
            -- No score data: hide entire section, anchor scroll below separator
            scoreToggle:Hide()
            scoreBar.frame:Hide()
            widget.detailScroll:SetPoint("TOPLEFT", detailSeparator, "BOTTOMLEFT", 0, -4)
        elseif scoreExpanded then
            scoreToggle:Show()
            scoreBar.frame:Show()
            scoreArrow:SetText("\226\150\190")  -- ▾
            widget.detailScroll:SetPoint("TOPLEFT", scoreBar.frame, "BOTTOMLEFT", 0, -4)
        else
            scoreToggle:Show()
            scoreBar.frame:Hide()
            scoreArrow:SetText("\226\150\184")  -- ▸
            widget.detailScroll:SetPoint("TOPLEFT", scoreToggle, "BOTTOMLEFT", 0, -4)
        end
    end
    widget.UpdateLayout = UpdateLayout

    scoreToggle:SetScript("OnClick", function()
        if FB.db and FB.db.settings and FB.db.settings.ui then
            FB.db.settings.ui.scoreExpanded = not FB.db.settings.ui.scoreExpanded
        end
        UpdateLayout()
    end)
    scoreToggle:SetScript("OnEnter", function(self)
        self:SetAlpha(0.8)
    end)
    scoreToggle:SetScript("OnLeave", function(self)
        self:SetAlpha(1.0)
    end)

    -- 6. Bottom buttons (created before scroll so scroll can anchor to them)
    local pinBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pinBtn:SetSize(120, 24)
    pinBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    pinBtn:SetText("Pin to Tracker")
    pinBtn:SetScript("OnClick", function()
        if selectedMount and selectedMount.id then
            local steps = selectedMount._resolvedSteps or selectedMount.steps or {}
            if #steps == 0 and FB.Utils.BuildMountAutoSteps then
                steps = FB.Utils:BuildMountAutoSteps(selectedMount)
            end
            FB.Tracker:Pin("mount", selectedMount.id, selectedMount.name, steps)
            FB:Print("Pinned: " .. selectedMount.name)
        end
    end)
    pinBtn:Hide()
    widget.pinBtn = pinBtn

    local wowheadBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    wowheadBtn:SetSize(100, 24)
    wowheadBtn:SetPoint("RIGHT", pinBtn, "LEFT", -6, 0)
    wowheadBtn:SetText("WoWHead")
    wowheadBtn:SetNormalFontObject("GameFontNormalSmall")
    wowheadBtn:SetScript("OnClick", function(self)
        if selectedMount then
            local spellID = selectedMount.id or selectedMount.spellID or selectedMount.mountID
            if spellID then
                local url = "https://www.wowhead.com/spell=" .. spellID
                local eb = _G["FarmBuddyWowheadCopyFrame"]
                if not eb then
                    eb = CreateFrame("EditBox", "FarmBuddyWowheadCopyFrame", UIParent, "BackdropTemplate")
                    eb:SetSize(350, 28)
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
                    label:SetText(FB.COLORS.GOLD .. "Ctrl+C to copy, Enter or Escape to close|r")
                    eb.label = label
                    eb:SetScript("OnEscapePressed", function(f) f:Hide() end)
                    eb:SetScript("OnEnterPressed", function(f) f:Hide() end)
                end
                eb:ClearAllPoints()
                eb:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
                eb:SetText(url)
                eb:Show()
                eb:HighlightText()
                eb:SetFocus()
            end
        end
    end)
    wowheadBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("WoWHead Link")
        if selectedMount then
            local spellID = selectedMount.id or selectedMount.spellID or selectedMount.mountID
            if spellID then
                GameTooltip:AddLine("wowhead.com/spell=" .. spellID, 0.7, 0.7, 0.7)
            end
        end
        GameTooltip:AddLine("Click to copy link to clipboard", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    wowheadBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    wowheadBtn:Hide()
    widget.wowheadBtn = wowheadBtn

    -- 7. Scrollable detail text
    local detailScroll = CreateFrame("ScrollFrame", name .. "DetailScroll", frame)
    detailScroll:SetPoint("TOPLEFT", detailSeparator, "BOTTOMLEFT", 0, -4) -- re-anchored by UpdateLayout
    detailScroll:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
    detailScroll:SetPoint("BOTTOM", pinBtn, "TOP", 0, 4)
    detailScroll:EnableMouseWheel(true)
    widget.detailScroll = detailScroll

    local detailChild = CreateFrame("Frame", nil, detailScroll)
    detailChild:SetSize(300, 1)
    detailScroll:SetScrollChild(detailChild)
    widget.detailChild = detailChild

    local detailText = detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailText:SetPoint("TOPLEFT", 0, 0)
    detailText:SetWidth(300)
    detailText:SetJustifyH("LEFT")
    detailText:SetWordWrap(true)
    detailText:SetText(FB.COLORS.GRAY .. "Select a mount for details|r")
    widget.detailText = detailText

    -- Scroll bar
    local detailScrollBar = CreateFrame("Slider", name .. "DetailScrollBar", frame, "BackdropTemplate")
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
    widget.detailScrollBar = detailScrollBar

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

    -- Initialize layout
    scoreToggle:Hide()
    scoreBar.frame:Hide()

    -- Callbacks
    local onPinCallback = nil

    --------------------------------------------------------------------------
    -- Public API
    --------------------------------------------------------------------------

    function widget:SetMount(item, opts)
        if not item then
            self:Clear()
            return
        end

        opts = opts or {}
        selectedMount = item

        -- Model preview
        if item.creatureDisplayID then
            modelPreview:SetMount(item.creatureDisplayID, item.name)
        elseif item.mountID then
            modelPreview:SetMountByMountID(item.mountID)
        else
            modelPreview:Clear()
        end

        -- Header and subtitle
        local detailData = FB.Utils:BuildMountDetailData(item, opts.showCollectionStatus or false)
        detailHeader:SetText(detailData.name)
        detailSubtitle:SetText(detailData.subtitle)

        -- Store resolved steps for pin button
        selectedMount._resolvedSteps = detailData.steps

        -- Score section
        if not item.isCollected and item.components then
            hasScoreData = true
            scoreBar:SetScore({
                score = item.score,
                components = item.components,
            })
        else
            hasScoreData = false
            scoreBar:SetScore(nil)
        end

        -- Build detail body text
        local extraLines = {}

        -- Synergies
        if opts.showSynergies and item.synergies and #item.synergies > 0 and FB.SynergyResolver then
            local synergyLines = FB.SynergyResolver:FormatSynergies(item.synergies)
            if synergyLines and #synergyLines > 0 then
                extraLines[#extraLines + 1] = ""
                extraLines[#extraLines + 1] = FB.COLORS.GREEN .. "Achievement Synergies:|r"
                for _, sl in ipairs(synergyLines) do
                    extraLines[#extraLines + 1] = "  " .. sl
                end
            end
        end

        -- Diminishing returns
        if opts.showDiminishingReturns and item.attemptCount and item.attemptCount > 0
                and item.dropChance and item.dropChance > 0 then
            local expected = math.ceil(math.log(0.5) / math.log(1 - item.dropChance))
            extraLines[#extraLines + 1] = ""
            if item.attemptCount > expected then
                local pUnlucky = (1 - item.dropChance) ^ item.attemptCount * 100
                extraLines[#extraLines + 1] = string.format(
                    "%sAttempts:|r %d / %d expected (unluckiest %.0f%% of players)",
                    FB.COLORS.ORANGE, item.attemptCount, expected, pUnlucky
                )
                if item.attemptCount > expected * 3 then
                    extraLines[#extraLines + 1] = FB.COLORS.YELLOW .. "Consider diversifying to other mounts.|r"
                end
            else
                extraLines[#extraLines + 1] = string.format(
                    "%sAttempts:|r %d / %d expected",
                    FB.COLORS.GOLD, item.attemptCount, expected
                )
            end
        end

        local bodyText = detailData.detailText
        if #extraLines > 0 then
            bodyText = bodyText .. "\n" .. table.concat(extraLines, "\n")
        end
        detailText:SetText(bodyText)

        -- Update layout (score section visibility)
        UpdateLayout()

        -- Show buttons
        pinBtn:Show()
        wowheadBtn:Show()

        -- Resize scroll child to fit text
        C_Timer.After(0, function()
            if not detailText or not detailChild or not detailScroll then return end
            local scrollWidth = detailScroll:GetWidth()
            if scrollWidth and scrollWidth > 10 then
                detailChild:SetWidth(scrollWidth)
                detailText:SetWidth(scrollWidth)
            end
            local textHeight = detailText:GetStringHeight() or 100
            detailChild:SetHeight(textHeight + 8)
            detailScroll:SetVerticalScroll(0)

            local maxScroll = math.max(0, textHeight + 8 - detailScroll:GetHeight())
            if maxScroll > 0 then
                detailScrollBar:SetMinMaxValues(0, maxScroll)
                detailScrollBar:SetValue(0)
                detailScrollBar:Show()
            else
                detailScrollBar:Hide()
            end
        end)

        -- Notify pin callback
        if onPinCallback then
            pinBtn:SetScript("OnClick", function()
                onPinCallback(selectedMount)
            end)
        end
    end

    function widget:Clear()
        selectedMount = nil
        modelPreview:Clear()
        detailHeader:SetText("")
        detailSubtitle:SetText("")
        detailText:SetText(FB.COLORS.GRAY .. "Select a mount for details|r")
        hasScoreData = false
        scoreBar:SetScore(nil)
        scoreToggle:Hide()
        scoreBar.frame:Hide()
        pinBtn:Hide()
        wowheadBtn:Hide()
        detailScrollBar:Hide()
    end

    function widget:SetOnPin(callback)
        onPinCallback = callback
    end

    function widget:GetSelectedMount()
        return selectedMount
    end

    return widget
end
