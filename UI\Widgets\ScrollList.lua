local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.Widgets = FB.UI.Widgets or {}

--[[
    Create a scrollable list widget that displays scored items.
    Each row shows: icon, name, score, source info, and optional details.

    @param parent   frame   - Parent frame to attach to
    @param name     string  - Unique name for this widget
    @param rowHeight number  - Height per row (default 36)
    @return widget  table   - { frame, SetData(data), SetOnClick(func), Refresh() }
--]]
function FB.UI.Widgets:CreateScrollList(parent, name, rowHeight)
    rowHeight = rowHeight or 36
    local widget = {}
    widget.data = {}
    widget.filteredData = {}
    widget.onClick = nil
    widget.onCtrlClick = nil
    widget.rows = {}
    widget.scrollOffset = 0

    -- Main container
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -24, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
    widget.frame = frame

    -- Scroll bar (manual - no template dependency)
    local scrollBar = CreateFrame("Slider", name .. "ScrollBar", frame, "BackdropTemplate")
    scrollBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4)
    scrollBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 4)
    scrollBar:SetWidth(16)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    scrollBar:SetValue(0)
    scrollBar:EnableMouse(true)
    scrollBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    local scrollThumb = scrollBar:CreateTexture(nil, "ARTWORK")
    scrollThumb:SetSize(14, 24)
    scrollThumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    scrollBar:SetThumbTexture(scrollThumb)
    scrollBar:SetScript("OnValueChanged", function(self, value)
        widget.scrollOffset = math.floor(value)
        widget:Refresh()
    end)
    widget.scrollBar = scrollBar

    -- Mouse wheel scrolling
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollBar:GetValue()
        scrollBar:SetValue(current - delta * 3)
    end)

    -- Calculate visible rows
    local function GetVisibleRows()
        local h = frame:GetHeight() - 4
        return math.max(1, math.floor(h / rowHeight))
    end

    -- Create a row frame
    local function CreateRow(index)
        local row = CreateFrame("Button", name .. "Row" .. index, frame)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -(rowHeight * (index - 1)) - 2)
        row:SetPoint("RIGHT", frame, "RIGHT", -4, 0)

        -- Highlight
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(0.3, 0.6, 1.0, 0.15)

        -- Selected highlight
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(0.2, 0.4, 0.8, 0.2)
        row.selected:Hide()

        -- Rank number
        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.rank:SetPoint("LEFT", 4, 0)
        row.rank:SetWidth(20)
        row.rank:SetJustifyH("RIGHT")

        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(rowHeight - 4, rowHeight - 4)
        row.icon:SetPoint("LEFT", 28, 0)

        -- Name
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 6)
        row.nameText:SetWidth(200)
        row.nameText:SetJustifyH("LEFT")

        -- Sub text (source info)
        row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.subText:SetPoint("LEFT", row.icon, "RIGHT", 6, -6)
        row.subText:SetWidth(200)
        row.subText:SetJustifyH("LEFT")
        row.subText:SetTextColor(0.6, 0.6, 0.6)

        -- Status (available/locked) — rightmost column
        row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.statusText:SetPoint("RIGHT", -10, 0)
        row.statusText:SetWidth(70)
        row.statusText:SetJustifyH("CENTER")

        -- Score — left of status
        row.scoreText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.scoreText:SetPoint("RIGHT", row.statusText, "LEFT", -4, 6)
        row.scoreText:SetWidth(50)
        row.scoreText:SetJustifyH("RIGHT")
        row.scoreText:SetNonSpaceWrap(false)
        row.scoreText:SetWordWrap(false)

        -- Time estimate — below score
        row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.timeText:SetPoint("RIGHT", row.statusText, "LEFT", -4, -6)
        row.timeText:SetWidth(70)
        row.timeText:SetJustifyH("RIGHT")
        row.timeText:SetTextColor(0.6, 0.6, 0.6)

        row:SetScript("OnClick", function(self)
            if self.dataIndex then
                local item = widget.filteredData[self.dataIndex]
                if IsControlKeyDown() and widget.onCtrlClick then
                    widget.onCtrlClick(item)
                elseif widget.onClick then
                    widget.onClick(item)
                end
            end
        end)

        -- Tooltip hint for Ctrl+Click
        row:SetScript("OnEnter", function(self)
            self.highlight:Show()
            if widget.onCtrlClick and self.dataIndex then
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetText("Ctrl+Click to open in Mount Journal", 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        return row
    end

    -- Refresh the display
    function widget:Refresh()
        local visibleRows = GetVisibleRows()

        -- Create rows as needed
        while #self.rows < visibleRows do
            self.rows[#self.rows + 1] = CreateRow(#self.rows + 1)
        end

        -- Update scroll bar
        local maxScroll = math.max(0, #self.filteredData - visibleRows)
        scrollBar:SetMinMaxValues(0, maxScroll)
        if self.scrollOffset > maxScroll then
            self.scrollOffset = maxScroll
        end

        -- Update rows
        for i = 1, #self.rows do
            local row = self.rows[i]
            local dataIdx = i + self.scrollOffset

            if dataIdx <= #self.filteredData then
                local item = self.filteredData[dataIdx]
                row.dataIndex = dataIdx

                row.rank:SetText(FB.COLORS.GRAY .. dataIdx .. "|r")
                row.icon:SetTexture(item.icon)
                row.nameText:SetText(item.name or "Unknown")

                -- Sub text varies by context
                local sourceLabel = FB.SOURCE_TYPE_NAMES[item.sourceType] or item.sourceType or ""
                local expansionLabel = item.expansion and FB:GetExpansionName(item.expansion) or ""
                if expansionLabel ~= "" then
                    sourceLabel = sourceLabel .. " - " .. expansionLabel
                end
                row.subText:SetText(sourceLabel)

                -- Score (color-coded via SetTextColor to avoid escape sequence truncation)
                local scoreStr = FB.Utils:FormatScore(item.score or 0)
                row.scoreText:SetText(scoreStr)
                local sr, sg, sb = FB.Utils:GetScoreColor(item.score or 0, 300)
                row.scoreText:SetTextColor(sr, sg, sb)

                -- Time estimate
                if item.effectiveDays then
                    row.timeText:SetText("~" .. FB.Utils:FormatDays(item.effectiveDays))
                else
                    row.timeText:SetText("")
                end

                -- Status
                if item.immediatelyAvailable then
                    row.statusText:SetText(FB.COLORS.GREEN .. "Available|r")
                else
                    row.statusText:SetText(FB.COLORS.RED .. "Locked|r")
                end

                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Set data
    function widget:SetData(data)
        self.data = data or {}
        self.filteredData = self.data
        self.scrollOffset = 0
        self:Refresh()
    end

    -- Set filtered data (subset of data)
    function widget:SetFilteredData(data)
        self.filteredData = data or {}
        self.scrollOffset = 0
        self:Refresh()
    end

    -- Set click handler
    function widget:SetOnClick(func)
        self.onClick = func
    end

    -- Set ctrl+click handler
    function widget:SetOnCtrlClick(func)
        self.onCtrlClick = func
    end

    -- Handle resize
    frame:SetScript("OnSizeChanged", function()
        widget:Refresh()
    end)

    return widget
end
