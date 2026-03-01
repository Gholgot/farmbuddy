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

-- Calculate the most recent weekly reset timestamp
-- US resets Tuesday 15:00 UTC, EU resets Wednesday 07:00 UTC
-- Use Tuesday 15:00 UTC as a safe universal approximation
local function GetWeeklyResetTimestamp()
    local now = GetServerTime and GetServerTime() or time()
    local dateInfo = date("!*t", now)
    -- Lua os.date wday: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
    local daysSinceTuesday = (dateInfo.wday - 3) % 7
    if daysSinceTuesday == 0 then
        -- It IS Tuesday: check if we're past reset hour (15:00 UTC)
        local todayResetSec = now - (dateInfo.hour * 3600 + dateInfo.min * 60 + dateInfo.sec) + (15 * 3600)
        if now >= todayResetSec then
            return todayResetSec
        else
            daysSinceTuesday = 7  -- Before reset hour, use last Tuesday
        end
    end
    -- Calculate last Tuesday 15:00 UTC
    local lastTuesday = now - (daysSinceTuesday * 86400)
    local ltd = date("!*t", lastTuesday)
    return lastTuesday - (ltd.hour * 3600 + ltd.min * 60 + ltd.sec) + (15 * 3600)
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
    gridRows = {}
    headerLabels = {}
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
    -- With icons instead of text, columns can be narrower
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

        -- Mount name + instance
        local mountLabel = AcquireFontString(gridFrame)
        mountLabel:SetPoint("TOPLEFT", startX, y)
        mountLabel:SetWidth(MOUNT_COL_WIDTH)
        mountLabel:SetJustifyH("LEFT")

        local icon = mount.icon and ("|T" .. mount.icon .. ":14:14|t ") or ""
        mountLabel:SetText(icon .. FB.Utils:Truncate(mount.name, 25))
        row.mountLabel = mountLabel

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
