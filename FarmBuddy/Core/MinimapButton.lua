local addonName, FB = ...

FB.MinimapButton = {}

local button = nil
local isDragging = false

-- Minimap button position (angle in degrees, saved)
local function GetPosition()
    if FB.db and FB.db.settings and FB.db.settings.ui then
        return FB.db.settings.ui.minimapAngle or 225
    end
    return 225
end

local function SavePosition(angle)
    if FB.db and FB.db.settings and FB.db.settings.ui then
        FB.db.settings.ui.minimapAngle = angle
    end
end

-- Update button position on minimap edge
local function UpdatePosition()
    if not button then return end
    local angle = math.rad(GetPosition())
    -- Dynamic radius from actual minimap size (handles zoom/shape changes)
    local radius = (Minimap:GetWidth() / 2) + 6
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Create the minimap button
function FB.MinimapButton:Create()
    if button then return end

    button = CreateFrame("Button", "FarmBuddyMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetMovable(true)
    button:SetClampedToScreen(true)

    -- Icon (positioned to align within the tracking border ring)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    bg:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Border overlay (standard minimap tracking ring, anchored at TOPLEFT)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Highlight
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(20, 20)
    highlight:SetPoint("TOPLEFT", 7, -5)
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Status text (small count badge)
    local badge = button:CreateFontString(nil, "OVERLAY")
    badge:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    badge:SetPoint("BOTTOMRIGHT", 2, -2)
    badge:SetTextColor(0.2, 1.0, 0.2)
    button.badge = badge

    -- Click handler
    button:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" then
            FB.UI:Toggle()
        elseif btn == "RightButton" then
            FB.Tracker:Toggle()
        end
    end)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(FB.ADDON_COLOR .. "FarmBuddy|r")
        -- Count available weekly mounts
        local availCount = FB.MinimapButton:GetAvailableCount()
        if availCount > 0 then
            GameTooltip:AddLine("|cFF00FF00" .. availCount .. " mounts available this reset|r")
        else
            GameTooltip:AddLine("|cFF888888No weekly mounts available|r")
        end
        local pinnedCount = FB.MinimapButton:GetPinnedCount()
        if pinnedCount > 0 then
            GameTooltip:AddLine("|cFFFFD200" .. pinnedCount .. " items pinned|r")
        end

        -- #17: Scan freshness line
        local lastScan = FB.charDB and FB.charDB.lastMountScan
        if lastScan and lastScan > 0 then
            local elapsed = time() - lastScan
            local scanLine
            if elapsed < 60 then
                scanLine = "Last scan: just now"
            elseif elapsed < 3600 then
                local mins = math.floor(elapsed / 60)
                scanLine = "Last scan: " .. mins .. (mins == 1 and " minute ago" or " minutes ago")
            elseif elapsed < 86400 then
                local hours = math.floor(elapsed / 3600)
                scanLine = "Last scan: " .. hours .. (hours == 1 and " hour ago" or " hours ago")
            else
                -- Format as "today at HH:MM" or "X days ago"
                local days = math.floor(elapsed / 86400)
                if days == 0 then
                    local scanDate = date("*t", lastScan)
                    scanLine = string.format("Last scan: today at %02d:%02d", scanDate.hour, scanDate.min)
                else
                    scanLine = "Last scan: " .. days .. (days == 1 and " day ago" or " days ago")
                end
            end
            GameTooltip:AddLine("|cFFCCCCCC" .. scanLine .. "|r")
        else
            GameTooltip:AddLine("|cFFFFAA00No scan this session|r")
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFFCCCCCCLeft-Click:|r Open FarmBuddy")
        GameTooltip:AddLine("|cFFCCCCCCRight-Click:|r Toggle Tracker")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Dragging around minimap edge
    button:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and IsShiftKeyDown() then
            isDragging = true
        end
    end)
    button:SetScript("OnMouseUp", function()
        isDragging = false
    end)
    button:SetScript("OnUpdate", function(self)
        if not isDragging then return end
        -- Auto-end drag if mouse button released (handles cursor leaving button)
        if not IsMouseButtonDown("LeftButton") then
            isDragging = false
            return
        end
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local angle = math.deg(math.atan2(cy - my, cx - mx))
        SavePosition(angle)
        UpdatePosition()
    end)

    UpdatePosition()

    -- Check if hidden by user preference
    if FB.db and FB.db.settings and FB.db.settings.ui and FB.db.settings.ui.hideMinimapButton then
        button:Hide()
    end
end

-- Get count of available (not locked) weekly mounts
function FB.MinimapButton:GetAvailableCount()
    local count = 0
    if not FB.WeeklyTracker or not FB.WeeklyTracker.GetWeeklyMounts then return 0 end

    local ok, mounts = pcall(FB.WeeklyTracker.GetWeeklyMounts, FB.WeeklyTracker)
    if not ok or not mounts then return 0 end

    local playerKey = FB.playerKey
    for _, mount in ipairs(mounts) do
        if mount.characters and mount.characters[playerKey] then
            if not mount.characters[playerKey].locked then
                count = count + 1
            end
        end
    end
    return count
end

-- Get count of pinned items
function FB.MinimapButton:GetPinnedCount()
    local count = 0
    if FB.db then
        if FB.db.pinnedMounts then
            for _ in pairs(FB.db.pinnedMounts) do count = count + 1 end
        end
        if FB.db.pinnedAchievements then
            for _ in pairs(FB.db.pinnedAchievements) do count = count + 1 end
        end
    end
    return count
end

-- Update the badge count display
function FB.MinimapButton:UpdateBadge()
    if not button or not button.badge then return end
    local count = self:GetAvailableCount()
    if count > 0 then
        button.badge:SetText(tostring(count))
    else
        button.badge:SetText("")
    end
end

-- Toggle visibility
function FB.MinimapButton:Toggle()
    if not button then return end
    if button:IsShown() then
        button:Hide()
        if FB.db and FB.db.settings and FB.db.settings.ui then
            FB.db.settings.ui.hideMinimapButton = true
        end
    else
        button:Show()
        if FB.db and FB.db.settings and FB.db.settings.ui then
            FB.db.settings.ui.hideMinimapButton = false
        end
    end
end

-- Initialize on login and reposition on world transitions (minimap may change shape/size)
FB:RegisterEvent("PLAYER_ENTERING_WORLD", FB.MinimapButton, function(self, event, isLogin, isReload)
    C_Timer.After(2, function()
        FB.MinimapButton:Create()   -- No-op if already created (guards with `if button then return end`)
        UpdatePosition()             -- Recalculate position for current minimap size
        FB.MinimapButton:UpdateBadge()
    end)
end)

-- Refresh badge when lockouts change
FB:RegisterEvent("UPDATE_INSTANCE_INFO", FB.MinimapButton, function()
    C_Timer.After(1, function()
        FB.MinimapButton:UpdateBadge()
    end)
end)
