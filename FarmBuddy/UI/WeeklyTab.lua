local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.WeeklyTab = {}

local panel
local gridFrame
local scrollFrame
local scrollBar
local gridRows = {}
local headerLabels = {}
local fontStringPool = {}
local texturePool = {}

-- Improvement #5: hit-rect buttons for interactivity
local hitRectPool = {}
local activeHitRects = {}

-- Improvement #5: selected mount row index
local selectedRowIdx = nil

-- Filter state
local allWeeklyMounts = {}
local filteredMounts = {}
local searchBox
local filterAvailableOnly = false
local filterHideFullyLocked = false
local filterRaidOnly = false
local filterAttemptedThisWeek = false
local filterExpansion = nil
local searchText = ""

-- Calculate the most recent weekly reset timestamp.
-- BUG-9: Avoid date("!*t", ...) which may behave unexpectedly in WoW's sandboxed Lua.
-- Instead, compute purely from epoch arithmetic.
-- US resets Tuesday 15:00 UTC.  A known Tuesday 15:00 UTC anchor:
--   2024-01-02 15:00 UTC = epoch 1704207600.
-- Days since that anchor mod 7 gives offset to the most recent Tuesday reset.
local KNOWN_RESET_EPOCH = 1704207600  -- 2024-01-02 15:00 UTC (Tuesday)
local WEEK_SECONDS      = 7 * 86400

local function GetWeeklyResetTimestamp()
    local now = GetServerTime and GetServerTime() or time()
    -- How many whole weeks have elapsed since the known anchor?
    local elapsed = now - KNOWN_RESET_EPOCH
    local weeksPast = math.floor(elapsed / WEEK_SECONDS)
    local resetTS = KNOWN_RESET_EPOCH + (weeksPast * WEEK_SECONDS)
    -- If we're exactly on the boundary or before, step back one week
    if resetTS > now then
        resetTS = resetTS - WEEK_SECONDS
    end
    return resetTS
end

-- Check if a mount has been attempted since the most recent weekly reset
local function HasBeenAttemptedThisWeek(mount)
    local resetTS = GetWeeklyResetTimestamp()
    if not resetTS then return false end

    -- Check 1: Any character has an active lockout (resetTime is in the future = locked now)
    if mount.characters then
        for _, charData in pairs(mount.characters) do
            if charData.locked and charData.resetTime and charData.resetTime > time() then
                return true
            end
        end
    end

    -- Check 2: mountAttempts tracker (staleness log)
    if FB.db and FB.db.mountAttempts and mount.spellID then
        local lastAttempt = FB.db.mountAttempts[mount.spellID]
        if lastAttempt and lastAttempt > resetTS then
            return true
        end
    end

    return false
end

local function AcquireFontString(parent, template)
    local fs = table.remove(fontStringPool)
    if not fs then
        fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    else
        fs:SetFontObject(template or "GameFontNormalSmall")
        fs:SetParent(parent)
    end
    fs:Show()
    return fs
end

local function AcquireTexture(parent)
    local tex = table.remove(texturePool)
    if not tex then
        tex = parent:CreateTexture(nil, "BACKGROUND")
    else
        tex:SetParent(parent)
    end
    tex:Show()
    return tex
end

-- Improvement #5: hit-rect button pool
local function AcquireHitRect(parent)
    local btn = table.remove(hitRectPool)
    if not btn then
        btn = CreateFrame("Button", nil, parent)
    else
        btn:SetParent(parent)
    end
    btn:Show()
    return btn
end

local function ReleaseAll()
    for _, row in ipairs(gridRows) do
        for _, element in pairs(row) do
            if element.SetText then
                element:Hide()
                element:ClearAllPoints()
                fontStringPool[#fontStringPool + 1] = element
            elseif element.SetColorTexture then
                element:Hide()
                element:ClearAllPoints()
                texturePool[#texturePool + 1] = element
            end
        end
    end
    for _, label in ipairs(headerLabels) do
        label:Hide()
        label:ClearAllPoints()
        fontStringPool[#fontStringPool + 1] = label
    end
    -- Release hit-rects (improvement #5)
    for _, btn in ipairs(activeHitRects) do
        btn:Hide()
        btn:ClearAllPoints()
        btn:SetScript("OnEnter", nil)
        btn:SetScript("OnLeave", nil)
        btn:SetScript("OnClick", nil)
        hitRectPool[#hitRectPool + 1] = btn
    end
    gridRows = {}
    headerLabels = {}
    activeHitRects = {}
    selectedRowIdx = nil
end

-- Update the scrollbar range/value based on grid content
local function UpdateScrollBar()
    if not scrollBar or not scrollFrame or not gridFrame then return end
    local maxScroll = math.max(0, gridFrame:GetHeight() - scrollFrame:GetHeight())
    if maxScroll <= 0 then
        scrollBar:Hide()
    else
        scrollBar:Show()
        scrollBar:SetMinMaxValues(0, maxScroll)
        scrollBar:SetValue(math.min(scrollFrame:GetVerticalScroll(), maxScroll))
    end
end

-- Apply search and filter to the raw weekly mounts data
local function ApplyFilters()
    filteredMounts = {}
    local lowerSearch = searchText:lower()
    local characters = FB.WeeklyTracker:GetCharacterList()

    for _, mount in ipairs(allWeeklyMounts) do
        local pass = true

        -- Text search: match against mount name or instance name
        if lowerSearch ~= "" then
            local mountName = (mount.name or ""):lower()
            local instName = (mount.instanceName or ""):lower()
            if not mountName:find(lowerSearch, 1, true) and not instName:find(lowerSearch, 1, true) then
                pass = false
            end
        end

        -- Raid Only: only show raid drops (sourceType ~= dungeon)
        if pass and filterRaidOnly then
            local srcType = mount.sourceType or mount.guessedSourceType or ""
            if srcType == "dungeon_drop" then
                pass = false
            end
        end

        -- Expansion filter
        if pass and filterExpansion then
            if mount.expansion ~= filterExpansion then
                pass = false
            end
        end

        -- Available Only: at least one character must be NOT locked
        if pass and filterAvailableOnly and #characters > 0 then
            local anyAvailable = false
            for _, char in ipairs(characters) do
                local charData = mount.characters[char.key]
                if charData and not charData.locked then
                    anyAvailable = true
                    break
                elseif not charData then
                    anyAvailable = true
                    break
                end
            end
            if not anyAvailable then
                pass = false
            end
        end

        -- Hide Fully Locked: hide mounts where ALL characters are locked
        if pass and filterHideFullyLocked and #characters > 0 then
            local allLocked = true
            for _, char in ipairs(characters) do
                local charData = mount.characters[char.key]
                if not charData or not charData.locked then
                    allLocked = false
                    break
                end
            end
            if allLocked then
                pass = false
            end
        end

        -- Attempted This Week: only show mounts farmed during this reset period
        if pass and filterAttemptedThisWeek then
            if not HasBeenAttemptedThisWeek(mount) then
                pass = false
            end
        end

        if pass then
            filteredMounts[#filteredMounts + 1] = mount
        end
    end
end

function FB.UI.WeeklyTab:Init(parentPanel)
    panel = parentPanel

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 5, -5)
    title:SetText("Weekly Mount Tracker")

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 24)
    refreshBtn:SetPoint("TOPRIGHT", -5, -5)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        FB.CharacterData:UpdateLockouts()
        FB.UI.WeeklyTab:RefreshGrid()
    end)

    -- Improvement #22: "Clear Attempts" button next to Refresh
    local clearBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clearBtn:SetSize(110, 24)
    clearBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -6, 0)
    clearBtn:SetText("Clear Attempts")
    -- Orange/warning color tint via vertex color
    clearBtn:GetNormalTexture():SetVertexColor(1.0, 0.65, 0.1)
    clearBtn:GetHighlightTexture():SetVertexColor(1.0, 0.8, 0.3)
    clearBtn:SetScript("OnClick", function()
        -- Confirmation dialog
        StaticPopupDialogs["FARMBUDDY_CLEAR_ATTEMPTS"] = {
            text = "Clear all mount attempt tracking data for this character?\n\nThis resets the 'This Week' filter history.",
            button1 = "Clear",
            button2 = "Cancel",
            OnAccept = function()
                if FB.db then
                    FB.db.mountAttempts = {}
                end
                FB.UI.WeeklyTab:RefreshGrid()
                FB:Print("Mount attempt tracking cleared.")
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("FARMBUDDY_CLEAR_ATTEMPTS")
    end)
    clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Clear Attempts")
        GameTooltip:AddLine("Clears the mount attempt tracking data used\nby the 'This Week' filter for this character.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Filter row (y = -30)
    local filterRow = CreateFrame("Frame", nil, panel)
    filterRow:SetPoint("TOPLEFT", 5, -30)
    filterRow:SetPoint("RIGHT", -5, 0)
    filterRow:SetHeight(26)

    -- Search box
    local searchLabel = filterRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("LEFT", 0, 0)
    searchLabel:SetText("Search:")

    searchBox = CreateFrame("EditBox", "FarmBuddyWeeklySearch", filterRow, "BackdropTemplate")
    searchBox:SetSize(130, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 4, 0)
    searchBox:SetFontObject("ChatFontNormal")
    searchBox:SetAutoFocus(false)
    searchBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    searchBox:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    searchBox:SetTextInsets(4, 4, 0, 0)
    searchBox:SetMaxLetters(40)
    searchBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText() or ""
        ApplyFilters()
        FB.UI.WeeklyTab:RenderGrid()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    -- Raid Only checkbox
    local raidCB = CreateFrame("CheckButton", "FarmBuddyWeeklyCBRaid", filterRow, "UICheckButtonTemplate")
    raidCB:SetSize(22, 22)
    raidCB:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    raidCB:SetChecked(false)
    local raidLabel = raidCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidLabel:SetPoint("LEFT", raidCB, "RIGHT", 2, 0)
    raidLabel:SetText("Raid Only")
    raidCB:SetScript("OnClick", function(self)
        filterRaidOnly = self:GetChecked()
        ApplyFilters()
        FB.UI.WeeklyTab:RenderGrid()
    end)

    -- Available Only checkbox
    local availCB = CreateFrame("CheckButton", "FarmBuddyWeeklyCBAvail", filterRow, "UICheckButtonTemplate")
    availCB:SetSize(22, 22)
    availCB:SetPoint("LEFT", raidLabel, "RIGHT", 8, 0)
    availCB:SetChecked(false)
    local availLabel = availCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    availLabel:SetPoint("LEFT", availCB, "RIGHT", 2, 0)
    availLabel:SetText("Available")
    availCB:SetScript("OnClick", function(self)
        filterAvailableOnly = self:GetChecked()
        ApplyFilters()
        FB.UI.WeeklyTab:RenderGrid()
    end)

    -- Hide Fully Locked checkbox
    local lockedCB = CreateFrame("CheckButton", "FarmBuddyWeeklyCBLocked", filterRow, "UICheckButtonTemplate")
    lockedCB:SetSize(22, 22)
    lockedCB:SetPoint("LEFT", availLabel, "RIGHT", 8, 0)
    lockedCB:SetChecked(false)
    local lockedLabel = lockedCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockedLabel:SetPoint("LEFT", lockedCB, "RIGHT", 2, 0)
    lockedLabel:SetText("Hide Locked")
    lockedCB:SetScript("OnClick", function(self)
        filterHideFullyLocked = self:GetChecked()
        ApplyFilters()
        FB.UI.WeeklyTab:RenderGrid()
    end)

    -- Attempted This Week checkbox
    local attemptCB = CreateFrame("CheckButton", "FarmBuddyWeeklyCBAttempt", filterRow, "UICheckButtonTemplate")
    attemptCB:SetSize(22, 22)
    attemptCB:SetPoint("LEFT", lockedLabel, "RIGHT", 8, 0)
    attemptCB:SetChecked(false)
    local attemptLabel = attemptCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    attemptLabel:SetPoint("LEFT", attemptCB, "RIGHT", 2, 0)
    attemptLabel:SetText("This Week")
    attemptCB:SetScript("OnClick", function(self)
        filterAttemptedThisWeek = self:GetChecked()
        ApplyFilters()
        FB.UI.WeeklyTab:RenderGrid()
    end)
    attemptCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Attempted This Week")
        GameTooltip:AddLine("Show only mounts where at least one character\nhas attempted it during this reset period.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    attemptCB:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Expansion dropdown
    local expLabel = filterRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    expLabel:SetPoint("LEFT", attemptLabel, "RIGHT", 12, 0)
    expLabel:SetText("Expansion:")

    local expBtn = CreateFrame("Button", "FarmBuddyWeeklyExpDD", filterRow, "BackdropTemplate")
    expBtn:SetSize(110, 20)
    expBtn:SetPoint("LEFT", expLabel, "RIGHT", 4, 0)
    expBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    expBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

    local expText = expBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    expText:SetPoint("LEFT", 6, 0)
    expText:SetPoint("RIGHT", -16, 0)
    expText:SetJustifyH("LEFT")
    expText:SetText("All")

    local expArrow = expBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    expArrow:SetPoint("RIGHT", -4, 0)
    expArrow:SetText("v")

    expBtn:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
                rootDescription:CreateButton("All", function()
                    filterExpansion = nil
                    expText:SetText("All")
                    ApplyFilters()
                    FB.UI.WeeklyTab:RenderGrid()
                end)
                -- Ordered expansion list (newest first)
                local expansions = {"TWW","DF","SL","BFA","LEGION","WOD","MOP","CATA","WOTLK","TBC","CLASSIC"}
                for _, key in ipairs(expansions) do
                    local displayName = FB.EXPANSION_NAMES[key] or key
                    rootDescription:CreateButton(displayName, function()
                        filterExpansion = key
                        expText:SetText(displayName)
                        ApplyFilters()
                        FB.UI.WeeklyTab:RenderGrid()
                    end)
                end
            end)
        else
            -- Fallback: cycle through expansions
            local expansions = {nil, "TWW","DF","SL","BFA","LEGION","WOD","MOP","CATA","WOTLK","TBC","CLASSIC"}
            local currentIdx = 1
            for i, key in ipairs(expansions) do
                if key == filterExpansion then currentIdx = i; break end
            end
            currentIdx = (currentIdx % #expansions) + 1
            filterExpansion = expansions[currentIdx]
            expText:SetText(filterExpansion and (FB.EXPANSION_NAMES[filterExpansion] or filterExpansion) or "All")
            ApplyFilters()
            FB.UI.WeeklyTab:RenderGrid()
        end
    end)

    -- Legend (far right)
    local legend = filterRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend:SetPoint("RIGHT", filterRow, "RIGHT", 0, 0)
    legend:SetJustifyH("RIGHT")
    legend:SetText("|TInterface\\RAIDFRAME\\ReadyCheck-Ready:12:12|t Avail  |TInterface\\RAIDFRAME\\ReadyCheck-NotReady:12:12|t Locked  " .. FB.COLORS.GRAY .. "- N/A|r")

    -- Status label
    local statusLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 5, 5)
    statusLabel:SetTextColor(0.5, 0.5, 0.5)
    self.statusLabel = statusLabel

    -- Scrollable grid container
    scrollFrame = CreateFrame("ScrollFrame", "FarmBuddyWeeklyScroll", panel)
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -58)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 20)

    gridFrame = CreateFrame("Frame", "FarmBuddyWeeklyGrid", scrollFrame)
    gridFrame:SetSize(1, 1)
    scrollFrame:SetScrollChild(gridFrame)

    -- Visible scrollbar
    scrollBar = CreateFrame("Slider", "FarmBuddyWeeklyScrollBar", panel, "BackdropTemplate")
    scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -58)
    scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 20)
    scrollBar:SetWidth(16)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetMinMaxValues(0, 1)
    scrollBar:SetValue(0)
    scrollBar:SetValueStep(24)
    scrollBar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    scrollBar:SetBackdropColor(0.05, 0.05, 0.05, 0.7)

    local thumbTex = scrollBar:CreateTexture(nil, "OVERLAY")
    thumbTex:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    thumbTex:SetSize(12, 40)
    scrollBar:SetThumbTexture(thumbTex)

    scrollBar:SetScript("OnValueChanged", function(self, value)
        scrollFrame:SetVerticalScroll(value)
    end)
    scrollBar:Hide()

    -- Mouse wheel scrolling (Shift+scroll = horizontal)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown() then
            -- Horizontal scroll
            local current = self:GetHorizontalScroll()
            local maxScroll = math.max(0, gridFrame:GetWidth() - self:GetWidth())
            local newScroll = math.max(0, math.min(maxScroll, current - (delta * 60)))
            self:SetHorizontalScroll(newScroll)
        else
            -- Vertical scroll
            local current = self:GetVerticalScroll()
            local maxScroll = math.max(0, gridFrame:GetHeight() - self:GetHeight())
            local newScroll = math.max(0, math.min(maxScroll, current - (delta * 40)))
            self:SetVerticalScroll(newScroll)
            scrollBar:SetValue(newScroll)
        end
    end)

    self.scrollFrame = scrollFrame
end

function FB.UI.WeeklyTab:OnShow()
    self:RefreshGrid()
end

-- Fetch data, apply filters, render
function FB.UI.WeeklyTab:RefreshGrid()
    allWeeklyMounts = FB.WeeklyTracker:GetWeeklyMounts()
    ApplyFilters()
    self:RenderGrid()
end

-- Improvement #5: show row highlight on all cells in the same row
local function SetRowHighlight(rowHighlightTextures, active)
    for _, tex in ipairs(rowHighlightTextures) do
        if active then
            tex:SetColorTexture(0.3, 0.5, 1.0, 0.10)
        else
            tex:SetColorTexture(0.3, 0.5, 1.0, 0)
        end
    end
end

-- Render the filtered data to the grid
function FB.UI.WeeklyTab:RenderGrid()
    ReleaseAll()

    local characters = FB.WeeklyTracker:GetCharacterList()

    if #allWeeklyMounts == 0 then
        local noData = AcquireFontString(gridFrame, "GameFontNormal")
        noData:SetPoint("CENTER")
        noData:SetText("No weekly farmable mounts found in database,\nor all weekly mounts are already collected!")
        gridRows[1] = { noData = noData }
        self.statusLabel:SetText("")
        UpdateScrollBar()
        return
    end

    if #characters == 0 then
        local noChars = AcquireFontString(gridFrame, "GameFontNormal")
        noChars:SetPoint("CENTER")
        noChars:SetText("No character data yet.\nLog into your characters to populate.")
        gridRows[1] = { noChars = noChars }
        self.statusLabel:SetText("")
        UpdateScrollBar()
        return
    end

    if #filteredMounts == 0 then
        local noMatch = AcquireFontString(gridFrame, "GameFontNormal")
        noMatch:SetPoint("CENTER")
        noMatch:SetText("No mounts match the current filters.")
        gridRows[1] = { noMatch = noMatch }
        self.statusLabel:SetText(string.format("0 of %d mounts shown", #allWeeklyMounts))
        UpdateScrollBar()
        return
    end

    local ROW_HEIGHT = 24
    local MOUNT_COL_WIDTH = 220
    local startX = 5
    local startY = -5

    -- Auto-size character columns to fit available width
    local availableWidth = (scrollFrame:GetWidth() or 800) - MOUNT_COL_WIDTH - 20
    local numChars = math.max(1, #characters)
    local COL_WIDTH = math.max(40, math.min(120, math.floor(availableWidth / numChars)))

    -- Header row: character names (truncated to fit column width)
    for i, char in ipairs(characters) do
        local label = AcquireFontString(gridFrame)
        label:SetPoint("TOPLEFT", startX + MOUNT_COL_WIDTH + ((i - 1) * COL_WIDTH), startY)
        label:SetWidth(COL_WIDTH)
        label:SetJustifyH("CENTER")
        label:SetWordWrap(false)

        local classColor = FB.CLASS_COLORS[char.class] or "FFFFFF"
        local shortName = char.key:match("^(.-)%s*-") or char.key
        -- Truncate name if column is narrow
        local maxChars = math.max(3, math.floor(COL_WIDTH / 8))
        if #shortName > maxChars then
            shortName = shortName:sub(1, maxChars)
        end
        label:SetText("|cFF" .. classColor .. shortName .. "|r")

        headerLabels[#headerLabels + 1] = label
    end

    -- Mount rows
    for rowIdx, mount in ipairs(filteredMounts) do
        local row = {}
        local y = startY - (rowIdx * ROW_HEIGHT)

        -- Per-row highlight textures (one per cell) for coordinated highlight
        local rowHighlightTextures = {}

        -- Mount name cell highlight bg
        local mountHighlight = AcquireTexture(gridFrame)
        mountHighlight:SetPoint("TOPLEFT", startX, y)
        mountHighlight:SetSize(MOUNT_COL_WIDTH, ROW_HEIGHT)
        mountHighlight:SetColorTexture(0.3, 0.5, 1.0, 0)
        rowHighlightTextures[#rowHighlightTextures + 1] = mountHighlight

        -- Character cell highlight bgs
        local charHighlights = {}
        for i = 1, #characters do
            local ht = AcquireTexture(gridFrame)
            ht:SetPoint("TOPLEFT", startX + MOUNT_COL_WIDTH + ((i - 1) * COL_WIDTH), y)
            ht:SetSize(COL_WIDTH, ROW_HEIGHT)
            ht:SetColorTexture(0.3, 0.5, 1.0, 0)
            rowHighlightTextures[#rowHighlightTextures + 1] = ht
            charHighlights[i] = ht
        end

        -- Selection highlight (solid blue tint shown on click)
        local selHighlight = AcquireTexture(gridFrame)
        selHighlight:SetPoint("TOPLEFT", startX, y)
        selHighlight:SetSize(MOUNT_COL_WIDTH + (#characters * COL_WIDTH), ROW_HEIGHT)
        selHighlight:SetColorTexture(0.2, 0.4, 0.9, 0)
        row.selHighlight = selHighlight

        -- Mount name label
        local mountLabel = AcquireFontString(gridFrame)
        mountLabel:SetPoint("TOPLEFT", startX, y)
        mountLabel:SetWidth(MOUNT_COL_WIDTH)
        mountLabel:SetJustifyH("LEFT")

        local icon = mount.icon and ("|T" .. mount.icon .. ":14:14|t ") or ""
        mountLabel:SetText(icon .. FB.Utils:Truncate(mount.name, 25))
        row.mountLabel = mountLabel

        -- Improvement #5: hit-rect button over mount name cell
        local mountHit = AcquireHitRect(gridFrame)
        mountHit:SetPoint("TOPLEFT", startX, y)
        mountHit:SetSize(MOUNT_COL_WIDTH, ROW_HEIGHT)
        local mt = mount  -- capture
        local rIdx = rowIdx  -- capture
        local rHighlights = rowHighlightTextures  -- capture
        local rSelHL = selHighlight  -- capture

        mountHit:SetScript("OnEnter", function(self2)
            SetRowHighlight(rHighlights, true)
            -- Mount name tooltip
            GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
            GameTooltip:SetText(mt.name or "Unknown Mount", 1, 0.82, 0, true)
            local src = mt.instanceName or mt.sourceText or "Unknown Source"
            GameTooltip:AddLine("Source: " .. src, 0.8, 0.8, 0.8, false)
            if mt.dropChance then
                GameTooltip:AddLine(string.format("Drop Chance: %.1f%%", mt.dropChance * 100), 0.8, 0.9, 0.6, false)
            else
                GameTooltip:AddLine("Drop Chance: Unknown", 0.7, 0.7, 0.7, false)
            end
            local tgStr = mt.timeGate or "weekly"
            GameTooltip:AddLine("Time Gate: " .. tgStr:gsub("^%l", string.upper), 0.7, 0.9, 1.0, false)
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("Click to select  |  Ctrl+Click for Mount Journal", 0.5, 0.5, 0.5, true)
            GameTooltip:Show()
        end)
        mountHit:SetScript("OnLeave", function()
            SetRowHighlight(rHighlights, false)
            GameTooltip:Hide()
        end)
        mountHit:SetScript("OnClick", function(self2, button)
            if IsControlKeyDown() then
                -- Ctrl+Click: open Mount Journal
                if C_MountJournal then
                    if not IsAddOnLoaded("Blizzard_Collections") then
                        pcall(LoadAddOn, "Blizzard_Collections")
                    end
                    if MountJournal_LoadUI then pcall(MountJournal_LoadUI) end
                    if CollectionsJournal and not CollectionsJournal:IsShown() then
                        pcall(ShowUIPanel, CollectionsJournal)
                    end
                    if C_MountJournal.SetSearch then
                        C_MountJournal.SetSearch(mt.name or "")
                    end
                end
            else
                -- Regular click: select row (visual highlight)
                -- Clear previously selected row's selection highlight
                for _, r in ipairs(gridRows) do
                    if r.selHighlight then
                        r.selHighlight:SetColorTexture(0.2, 0.4, 0.9, 0)
                    end
                end
                selectedRowIdx = rIdx
                rSelHL:SetColorTexture(0.2, 0.4, 0.9, 0.15)
            end
        end)
        activeHitRects[#activeHitRects + 1] = mountHit

        -- Status per character
        for i, char in ipairs(characters) do
            local statusLabel = AcquireFontString(gridFrame)
            statusLabel:SetPoint("TOPLEFT", startX + MOUNT_COL_WIDTH + ((i - 1) * COL_WIDTH), y)
            statusLabel:SetWidth(COL_WIDTH)
            statusLabel:SetJustifyH("CENTER")

            local charData = mount.characters[char.key]
            if charData then
                if charData.locked then
                    -- Red cross icon for locked
                    statusLabel:SetText("|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:16:16|t")
                else
                    -- Green check icon for available
                    statusLabel:SetText("|TInterface\\RAIDFRAME\\ReadyCheck-Ready:16:16|t")
                end
            else
                statusLabel:SetText(FB.COLORS.GRAY .. "-|r")
            end

            row["char" .. i] = statusLabel

            -- Improvement #5: hit-rect over character lockout cell
            local charHit = AcquireHitRect(gridFrame)
            charHit:SetPoint("TOPLEFT", startX + MOUNT_COL_WIDTH + ((i - 1) * COL_WIDTH), y)
            charHit:SetSize(COL_WIDTH, ROW_HEIGHT)
            local cd = charData  -- capture
            local ch = char      -- capture
            local crHL = rHighlights -- capture

            charHit:SetScript("OnEnter", function(self2)
                SetRowHighlight(crHL, true)
                -- Character lockout tooltip
                GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
                local classColor = FB.CLASS_COLORS[ch.class] or "FFFFFF"
                local shortName = ch.key:match("^(.-)%s*-") or ch.key
                GameTooltip:SetText("|cFF" .. classColor .. shortName .. "|r", 1, 1, 1, false)
                if ch.class then
                    GameTooltip:AddLine(ch.class:gsub("^%l", string.upper), 0.7, 0.7, 0.7, false)
                end
                GameTooltip:AddLine(" ", 1, 1, 1)
                if cd then
                    if cd.locked then
                        local resetStr = "Unknown"
                        if cd.resetTime and cd.resetTime > 0 then
                            local remaining = cd.resetTime - time()
                            if remaining > 0 then
                                local days = math.floor(remaining / 86400)
                                local hours = math.floor((remaining % 86400) / 3600)
                                if days > 0 then
                                    resetStr = string.format("%dd %dh", days, hours)
                                else
                                    resetStr = string.format("%dh", hours)
                                end
                            else
                                resetStr = "Resetting soon"
                            end
                        end
                        GameTooltip:AddLine("|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:14:14|t Locked", 1, 0.4, 0.4, false)
                        GameTooltip:AddLine("Resets in: " .. resetStr, 0.8, 0.8, 0.8, false)
                    else
                        GameTooltip:AddLine("|TInterface\\RAIDFRAME\\ReadyCheck-Ready:14:14|t Available", 0.4, 1.0, 0.4, false)
                        GameTooltip:AddLine("Not attempted this reset.", 0.7, 0.7, 0.7, false)
                    end
                else
                    GameTooltip:AddLine(FB.COLORS.GRAY .. "No data for this character|r", 0.6, 0.6, 0.6, false)
                end
                GameTooltip:Show()
            end)
            charHit:SetScript("OnLeave", function()
                SetRowHighlight(crHL, false)
                GameTooltip:Hide()
            end)
            activeHitRects[#activeHitRects + 1] = charHit
        end

        -- Row separator
        local sep = AcquireTexture(gridFrame)
        sep:SetPoint("TOPLEFT", startX, y - ROW_HEIGHT + 2)
        sep:SetSize(MOUNT_COL_WIDTH + (#characters * COL_WIDTH), 1)
        sep:SetColorTexture(0.3, 0.3, 0.3, 0.3)
        row.sep = sep

        gridRows[#gridRows + 1] = row
    end

    -- Resize grid to fit content
    local totalWidth = MOUNT_COL_WIDTH + (#characters * COL_WIDTH) + 20
    local totalHeight = (#filteredMounts + 1) * ROW_HEIGHT + 20
    gridFrame:SetSize(totalWidth, totalHeight)

    -- Update status (include character count)
    local charCountStr = string.format(" | %d characters", #characters)
    if #characters > 0 and COL_WIDTH < 60 then
        charCountStr = charCountStr .. " (Shift+scroll for more)"
    end
    if #filteredMounts < #allWeeklyMounts then
        self.statusLabel:SetText(string.format("Showing %d of %d mounts", #filteredMounts, #allWeeklyMounts) .. charCountStr)
    else
        self.statusLabel:SetText(string.format("%d mounts", #allWeeklyMounts) .. charCountStr)
    end

    UpdateScrollBar()
end
