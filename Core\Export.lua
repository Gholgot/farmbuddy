local addonName, FB = ...

FB.Export = {}

-- Export top N mounts to chat
function FB.Export:ToChat(count)
    count = count or 10

    if not FB.db or not FB.db.cachedMountScores then
        FB:Print("No scan results available. Run a scan first with /fb scan")
        return
    end

    local results = FB.db.cachedMountScores
    local limit = math.min(count, #results)

    if limit == 0 then
        FB:Print("No mounts to export.")
        return
    end

    print(FB.ADDON_COLOR .. string.format("FarmBuddy: Top %d mounts to farm|r", limit))
    print("---")

    for i = 1, limit do
        local r = results[i]
        local typeName = FB.SOURCE_TYPE_NAMES[r.sourceType] or r.sourceType or "?"
        local timeStr = r.effectiveDays and FB.Utils:FormatDays(r.effectiveDays) or "?"
        local available = r.immediatelyAvailable and "|cFF00FF00Avail|r" or "|cFFFF4444Locked|r"
        local scoreStr = string.format("%.0f", r.score or 0)

        print(string.format(
            "  %d. %s — %s — Score: %s — Est: %s — %s",
            i, r.name or "?", typeName, scoreStr, timeStr, available
        ))
    end
end

-- Export to an editable text frame (for copy/paste)
function FB.Export:ToFrame(count)
    count = count or 20

    if not FB.db or not FB.db.cachedMountScores then
        FB:Print("No scan results available. Run a scan first with /fb scan")
        return
    end

    local results = FB.db.cachedMountScores
    local limit = math.min(count, #results)
    if limit == 0 then
        FB:Print("No mounts to export.")
        return
    end

    -- Build text
    local lines = {}
    lines[#lines + 1] = string.format("FarmBuddy: Top %d Mounts to Farm", limit)
    lines[#lines + 1] = string.rep("-", 50)

    for i = 1, limit do
        local r = results[i]
        local typeName = FB.SOURCE_TYPE_NAMES[r.sourceType] or r.sourceType or "?"
        local timeStr = r.effectiveDays and FB.Utils:FormatDays(r.effectiveDays) or "?"
        local available = r.immediatelyAvailable and "Available" or "Locked"
        local scoreStr = string.format("%.0f", r.score or 0)

        local dropStr = ""
        if r.dropChance and r.dropChance > 0 then
            dropStr = string.format(" (%.1f%%)", r.dropChance * 100)
        end

        lines[#lines + 1] = string.format(
            "%d. %s — %s%s — Score: %s — Est: %s — %s",
            i, r.name or "?", typeName, dropStr, scoreStr, timeStr, available
        )
    end

    local text = table.concat(lines, "\n")

    -- Create copy frame
    self:ShowCopyFrame(text)
end

-- Create a simple copy/paste frame
function FB.Export:ShowCopyFrame(text)
    if not self.copyFrame then
        local frame = CreateFrame("Frame", "FarmBuddyExportFrame", UIParent, "BackdropTemplate")
        frame:SetSize(500, 350)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)

        -- Title
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 12, -8)
        title:SetText(FB.ADDON_COLOR .. "FarmBuddy Export|r")

        -- Close button
        local closeBtn = CreateFrame("Button", nil, frame)
        closeBtn:SetSize(24, 24)
        closeBtn:SetPoint("TOPRIGHT", -8, -8)
        closeBtn:SetNormalFontObject("GameFontNormalLarge")
        closeBtn:SetText("X")
        local closeBg = closeBtn:CreateTexture(nil, "HIGHLIGHT")
        closeBg:SetAllPoints()
        closeBg:SetColorTexture(1.0, 0.0, 0.0, 0.3)
        closeBtn:SetScript("OnClick", function() frame:Hide() end)

        -- Hint
        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", 12, -28)
        hint:SetTextColor(0.6, 0.6, 0.6)
        hint:SetText("Press Ctrl+A to select all, then Ctrl+C to copy")

        -- ScrollFrame with EditBox
        local scrollFrame = CreateFrame("ScrollFrame", "FarmBuddyExportScroll", frame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 12, -46)
        scrollFrame:SetPoint("BOTTOMRIGHT", -30, 12)

        local editBox = CreateFrame("EditBox", "FarmBuddyExportEditBox", scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(true)
        editBox:SetFontObject("ChatFontNormal")
        editBox:SetWidth(440)
        editBox:SetScript("OnEscapePressed", function() frame:Hide() end)

        scrollFrame:SetScrollChild(editBox)

        frame.editBox = editBox
        self.copyFrame = frame

        table.insert(UISpecialFrames, "FarmBuddyExportFrame")
    end

    self.copyFrame.editBox:SetText(text)
    self.copyFrame:Show()
    self.copyFrame.editBox:HighlightText()
    self.copyFrame.editBox:SetFocus()
end
