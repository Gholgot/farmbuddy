local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.Widgets = FB.UI.Widgets or {}

--[[
    Create a progress bar widget for scan operations.

    @param parent  frame
    @param name    string
    @return widget table - { frame, SetProgress(current, total), SetText(text), Show(), Hide() }
--]]
function FB.UI.Widgets:CreateProgressBar(parent, name)
    local widget = {}

    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:SetHeight(30)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    widget.frame = frame

    -- Progress fill
    local fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMLEFT", 3, 3)
    fill:SetWidth(1)
    fill:SetColorTexture(0.0, 0.6, 1.0, 0.7)
    widget.fill = fill

    -- Text overlay
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetText("Scanning...")
    widget.text = text

    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(60, 22)
    cancelBtn:SetPoint("RIGHT", -4, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn.onCancel = nil
    cancelBtn:SetScript("OnClick", function()
        if cancelBtn.onCancel then
            cancelBtn.onCancel()
        end
    end)
    widget.cancelBtn = cancelBtn

    function widget:SetProgress(current, total)
        if total and total > 0 then
            local ratio = math.min(current / total, 1.0)
            local maxWidth = frame:GetWidth() - 70  -- Leave room for cancel button
            fill:SetWidth(math.max(1, maxWidth * ratio))
            local pct = math.floor(ratio * 100)
            text:SetText(string.format("Scanning... %d/%d (%d%%)", current, total, pct))
        end
    end

    function widget:SetText(str)
        text:SetText(str)
    end

    function widget:SetOnCancel(func)
        cancelBtn.onCancel = func
    end

    function widget:Show()
        frame:Show()
        fill:SetWidth(1)
        text:SetText("Starting scan...")
    end

    function widget:Hide()
        frame:Hide()
    end

    frame:Hide()
    return widget
end
