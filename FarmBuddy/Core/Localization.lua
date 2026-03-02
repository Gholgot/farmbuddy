local addonName, FB = ...

-- NOTE: Localization stubs. These are not yet wired to UI code. All UI strings are currently hardcoded.

-- Localization framework
-- Usage: FB.L["string"] or FB:L("string")
-- Falls back to the key itself if no translation found

FB.L = FB.L or {}

local L = FB.L
local locale = GetLocale()

-- Set a localization string
function FB:SetLocale(key, value)
    L[key] = value
end

-- Get a localized string (returns key as fallback)
function FB:Localize(key)
    return L[key] or key
end

-- Allow FB.L["key"] access via metatable
setmetatable(L, {
    __index = function(t, key)
        return key  -- Return the key itself as fallback (English default)
    end,
})

-- ============================================================
-- English (default) strings
-- ============================================================

-- UI Labels
L["Mount Search"] = "Mount Search"
L["Recommendations"] = "Recommendations"
L["Achievements"] = "Achievements"
L["Weekly Tracker"] = "Weekly Tracker"
L["Settings"] = "Settings"

-- Source Types
L["Raid Drop"] = "Raid Drop"
L["Dungeon Drop"] = "Dungeon Drop"
L["World Drop"] = "World Drop"
L["Reputation"] = "Reputation"
L["Currency"] = "Currency"
L["Quest Chain"] = "Quest Chain"
L["Achievement"] = "Achievement"
L["Profession"] = "Profession"
L["PvP"] = "PvP"
L["World Event"] = "World Event"
L["Vendor"] = "Vendor"
L["Trading Post"] = "Trading Post"
L["Promotion"] = "Promotion"
L["Unknown"] = "Unknown"

-- Filter Labels
L["Raid"] = "Raid"
L["Dung"] = "Dung"
L["World"] = "World"
L["Rep"] = "Rep"
L["Cur"] = "Cur"
L["Quest"] = "Quest"
L["Ach"] = "Ach"
L["Vend"] = "Vend"
L["Event"] = "Event"
L["Prof"] = "Prof"
L["Solo"] = "Solo"
L["Avail"] = "Avail"

-- Status
L["Available"] = "Available"
L["Locked"] = "Locked"
L["Collected"] = "Collected"
L["Not Collected"] = "Not Collected"
L["Available Now"] = "Available Now"

-- Scoring
L["Score"] = "Score"
L["Progress"] = "Progress"
L["Time"] = "Time"
L["Gate"] = "Gate"
L["Group"] = "Group"
L["Effort"] = "Effort"

-- Settings
L["Scoring Weights"] = "Scoring Weights"
L["Scan Settings"] = "Scan Settings"
L["Reset to Defaults"] = "Reset to Defaults"
L["Progress Remaining"] = "Progress Remaining"
L["Time Per Attempt"] = "Time Per Attempt"
L["Time-Gating Penalty"] = "Time-Gating Penalty"
L["Group Requirement"] = "Group Requirement"
L["RNG / Total Effort"] = "RNG / Total Effort"

-- Notifications
L["Weekly reset! You have %d mounts to farm across your characters."] = "Weekly reset! You have %d mounts to farm across your characters."
L["Holiday event '%s' is now active! Check your yearly mounts."] = "Holiday event '%s' is now active! Check your yearly mounts."
L["%s loaded. Type %s/fb|r to open."] = "%s loaded. Type %s/fb|r to open."

-- Tracker
L["FarmBuddy Tracker"] = "FarmBuddy Tracker"
L["Unpin this item"] = "Unpin this item"
L["No items pinned."] = "No items pinned."
L["Pin items from FarmBuddy."] = "Pin items from FarmBuddy."

-- Export
L["FarmBuddy: Top %d mounts to farm"] = "FarmBuddy: Top %d mounts to farm"

-- Mount Detail
L["Cost"] = "Cost"
L["Have"] = "Have"
L["Ready!"] = "Ready!"
L["Needed"] = "Needed"
L["Est. %s to complete"] = "Est. %s to complete"
L["Ctrl+Click to open in Mount Journal"] = "Ctrl+Click to open in Mount Journal"
