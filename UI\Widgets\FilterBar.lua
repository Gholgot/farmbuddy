local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.Widgets = FB.UI.Widgets or {}

--[[
    Create a filter bar with checkboxes and dropdowns.
    Supports row wrapping when elements exceed available width.

    @param parent  frame
    @param name    string
    @return widget table
--]]
function FB.UI.Widgets:CreateFilterBar(parent, name)
    local widget = {}
    widget.filters = {}
    widget.onChange = nil

    local frame = CreateFrame("Frame", name, parent)
    frame:SetHeight(30)
    widget.frame = frame

    local elements = {}
    local xOffset = 0
    local yOffset = 0
    local ROW_HEIGHT = 26
    local MAX_ROW_WIDTH = 820  -- Wrap to next row beyond this

    -- Add a checkbox filter
    function widget:AddCheckbox(key, label, default)
        local cb = CreateFrame("CheckButton", name .. "CB_" .. key, frame, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetChecked(default ~= false)
        self.filters[key] = default ~= false

        local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        text:SetText(label)

        cb:SetScript("OnClick", function(self)
            widget.filters[key] = self:GetChecked()
            if widget.onChange then widget.onChange(widget.filters) end
        end)

        local textWidth = text:GetStringWidth()
        local itemWidth = 22 + textWidth + 12

        -- Wrap to next row if needed
        if xOffset > 0 and xOffset + itemWidth > MAX_ROW_WIDTH then
            xOffset = 0
            yOffset = yOffset - ROW_HEIGHT
            frame:SetHeight(math.abs(yOffset) + 30)
        end

        cb:SetPoint("LEFT", xOffset, yOffset)
        xOffset = xOffset + itemWidth
        elements[#elements + 1] = { cb = cb, text = text, key = key }

        return cb
    end

    -- Add a dropdown filter using the new MenuUtil system (12.0 compatible)
    function widget:AddDropdown(key, label, options, default)
        local dropLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        local labelWidth = 0

        -- Temporarily place to measure
        dropLabel:SetText(label .. ":")
        labelWidth = dropLabel:GetStringWidth() + 4
        local itemWidth = labelWidth + 128

        -- Wrap to next row if needed
        if xOffset > 0 and xOffset + itemWidth > MAX_ROW_WIDTH then
            xOffset = 0
            yOffset = yOffset - ROW_HEIGHT
            frame:SetHeight(math.abs(yOffset) + 30)
        end

        dropLabel:SetPoint("LEFT", frame, "LEFT", xOffset, yOffset)
        xOffset = xOffset + labelWidth

        local btn = CreateFrame("Button", name .. "DD_" .. key, frame, "BackdropTemplate")
        btn:SetSize(120, 22)
        btn:SetPoint("LEFT", xOffset, yOffset)
        btn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

        local selectedText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        selectedText:SetPoint("LEFT", 6, 0)
        selectedText:SetPoint("RIGHT", -16, 0)
        selectedText:SetJustifyH("LEFT")
        selectedText:SetText(default and options[default] or "All")

        local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        arrow:SetPoint("RIGHT", -4, 0)
        arrow:SetText("v")

        self.filters[key] = default

        btn:SetScript("OnClick", function(self)
            -- Use new MenuUtil if available (12.0+), fallback to custom menu
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
                    rootDescription:CreateButton("All", function()
                        widget.filters[key] = nil
                        selectedText:SetText("All")
                        if widget.onChange then widget.onChange(widget.filters) end
                    end)
                    -- Sort options alphabetically by display name for consistent ordering
                    local sortedKeys = {}
                    for value in pairs(options) do
                        sortedKeys[#sortedKeys + 1] = value
                    end
                    table.sort(sortedKeys, function(a, b)
                        return (options[a] or "") < (options[b] or "")
                    end)
                    for _, value in ipairs(sortedKeys) do
                        local displayName = options[value]
                        rootDescription:CreateButton(displayName, function()
                            widget.filters[key] = value
                            selectedText:SetText(displayName)
                            if widget.onChange then widget.onChange(widget.filters) end
                        end)
                    end
                end)
            else
                -- Fallback: simple toggle cycle through options (sorted)
                local keys = {"__all__"}
                local names = {["__all__"] = "All"}
                local sortedOptionKeys = {}
                for value in pairs(options) do
                    sortedOptionKeys[#sortedOptionKeys + 1] = value
                end
                table.sort(sortedOptionKeys, function(a, b)
                    return (options[a] or "") < (options[b] or "")
                end)
                for _, value in ipairs(sortedOptionKeys) do
                    keys[#keys + 1] = value
                    names[value] = options[value]
                end
                local currentIdx = 1
                for i, k in ipairs(keys) do
                    if (k == "__all__" and widget.filters[key] == nil) or k == widget.filters[key] then
                        currentIdx = i
                        break
                    end
                end
                currentIdx = (currentIdx % #keys) + 1
                local newKey = keys[currentIdx]
                if newKey == "__all__" then
                    widget.filters[key] = nil
                    selectedText:SetText("All")
                else
                    widget.filters[key] = newKey
                    selectedText:SetText(names[newKey])
                end
                if widget.onChange then widget.onChange(widget.filters) end
            end
        end)

        xOffset = xOffset + 128
        elements[#elements + 1] = { btn = btn, key = key }

        return btn
    end

    -- Set change handler
    function widget:SetOnChange(func)
        self.onChange = func
    end

    -- Get current filters
    function widget:GetFilters()
        return self.filters
    end

    -- Set a specific filter value
    function widget:SetFilter(key, value)
        self.filters[key] = value
    end

    return widget
end
