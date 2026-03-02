local addonName, FB = ...

FB.Tooltips = {}

local hooked = false

-- Hook into the Mount Journal tooltip to show FarmBuddy scoring data
function FB.Tooltips:Init()
    if hooked then return end
    hooked = true

    -- Hook GameTooltip for mount display info
    -- When players hover over mounts in the Mount Journal, inject score data
    if GameTooltip and GameTooltip.HookScript then
        hooksecurefunc(GameTooltip, "SetMountBySpellID", function(tooltip, spellID)
            self:OnMountTooltip(tooltip, spellID)
        end)
    end

    -- Also hook the mount list display frame if available
    if MountJournal and MountJournal.ListScrollFrame then
        -- Hook mount list button tooltips
        self:HookMountListButtons()
    end
end

-- Inject FarmBuddy data into a mount tooltip
function FB.Tooltips:OnMountTooltip(tooltip, spellID)
    if not spellID or not tooltip then return end

    -- Check if mount is already collected
    local mountID = self:FindMountIDBySpellID(spellID)
    if not mountID then return end

    local ok, _, _, _, _, _, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID, mountID)
    if not ok then return end
    if isCollected then return end  -- Don't show for collected mounts

    -- Get cached score data
    local scoreData = self:GetCachedScore(mountID)
    if not scoreData then
        -- Try live resolution
        scoreData = self:QuickScore(mountID)
    end

    if not scoreData then return end

    -- Add FarmBuddy section to tooltip
    tooltip:AddLine(" ")
    tooltip:AddLine(FB.ADDON_COLOR .. "FarmBuddy|r")

    -- Score with color
    local scoreColor = FB.Utils:ColorByScore(
        string.format("%.0f", scoreData.score),
        scoreData.score, 300
    )
    tooltip:AddDoubleLine("Difficulty Score:", scoreColor, 0.8, 0.8, 0.8)

    -- Time estimate
    if scoreData.effectiveDays then
        local timeStr = FB.Utils:FormatDays(scoreData.effectiveDays)
        tooltip:AddDoubleLine("Est. Time:", timeStr, 0.8, 0.8, 0.8, 1, 1, 1)
    end

    -- Availability
    if scoreData.immediatelyAvailable then
        tooltip:AddDoubleLine("Status:", "|cFF00FF00Available Now|r", 0.8, 0.8, 0.8)
    else
        tooltip:AddDoubleLine("Status:", "|cFFFF4444Locked|r", 0.8, 0.8, 0.8)
    end

    -- Source type
    if scoreData.sourceType then
        local typeName = FB.SOURCE_TYPE_NAMES[scoreData.sourceType] or scoreData.sourceType
        tooltip:AddDoubleLine("Source:", typeName, 0.8, 0.8, 0.8, 1, 1, 1)
    end

    -- Drop chance
    if scoreData.dropChance and scoreData.dropChance > 0 then
        local pct = scoreData.dropChance * 100
        local dropStr
        if pct >= 1 then
            dropStr = string.format("%.0f%%", pct)
        else
            dropStr = string.format("%.2f%%", pct)
        end
        tooltip:AddDoubleLine("Drop Rate:", dropStr, 0.8, 0.8, 0.8, 1, 1, 1)
    end

    tooltip:Show()
end

-- Find mountID from spellID
function FB.Tooltips:FindMountIDBySpellID(spellID)
    local mountIDs = C_MountJournal.GetMountIDs()
    for _, id in ipairs(mountIDs) do
        local _, sid = C_MountJournal.GetMountInfoByID(id)
        if sid == spellID then
            return id
        end
    end
    return nil
end

-- Get score from cached scan results
function FB.Tooltips:GetCachedScore(mountID)
    if not FB.db or not FB.db.cachedMountScores then return nil end

    for _, result in ipairs(FB.db.cachedMountScores) do
        if result.mountID == mountID then
            return result
        end
    end
    return nil
end

-- Quick inline scoring for mounts not in cache
function FB.Tooltips:QuickScore(mountID)
    if not FB.Mounts or not FB.Mounts.Resolver or not FB.Scoring then
        return nil
    end

    local ok, input = pcall(FB.Mounts.Resolver.Resolve, FB.Mounts.Resolver, mountID)
    if not ok or not input then return nil end

    if not FB.Scoring:IsScoreable(input.sourceType) then return nil end

    local scoreOk, result = pcall(FB.Scoring.Score, FB.Scoring, input)
    if not scoreOk or not result then return nil end

    -- Merge input data into result for display
    result.sourceType = input.sourceType
    result.dropChance = input.dropChance
    result.mountID = mountID

    return result
end

-- Hook mount list buttons for hover tooltips
function FB.Tooltips:HookMountListButtons()
    -- Try hooking the MountJournal list display
    if not MountJournal then return end

    -- Hook MountJournal_UpdateMountList if it exists
    if MountJournal_UpdateMountList then
        hooksecurefunc("MountJournal_UpdateMountList", function()
            self:UpdateMountListOverlay()
        end)
    end
end

-- Add score overlays to mount list (lightweight)
function FB.Tooltips:UpdateMountListOverlay()
    -- This is called when the mount journal list refreshes
    -- We can add score badges to each visible mount row
    -- For now, tooltip-only approach is sufficient
end

-- Initialize when addon loads
FB:RegisterEvent("PLAYER_ENTERING_WORLD", FB.Tooltips, function(self, event, isLogin, isReload)
    if not isLogin and not isReload then return end
    C_Timer.After(3, function()
        FB.Tooltips:Init()
    end)
end)
