local addonName, FB = ...
_G["FarmBuddy"] = FB

FB.version = "1.3.0"
FB.addonName = addonName

-- Module namespaces (populated by later files)
-- Use defensive pattern to avoid wiping methods if files load in unexpected order
FB.Scoring = FB.Scoring or {}
FB.Mounts = FB.Mounts or {}
FB.Achievements = FB.Achievements or {}
FB.Storage = FB.Storage or {}
FB.UI = FB.UI or {}
FB.Tracker = FB.Tracker or {}
FB.Async = FB.Async or {}
FB.ProgressResolver = FB.ProgressResolver or {}
FB.TimeGateResolver = FB.TimeGateResolver or {}
FB.MountDB = FB.MountDB or {}
FB.AchievementDB = FB.AchievementDB or {}
FB.InstanceData = FB.InstanceData or {}
FB.ExpansionData = FB.ExpansionData or {}
FB.WeeklyTracker = FB.WeeklyTracker or {}
FB.CharacterData = FB.CharacterData or {}
FB.ZoneGrouper = FB.ZoneGrouper or {}

-- Player info (cached at login)
FB.playerName = nil
FB.realmName = nil
FB.playerKey = nil      -- "PlayerName - RealmName"
FB.playerLevel = nil
FB.playerFaction = nil
FB.playerClass = nil

-- Runtime state
FB.db = nil             -- Reference to FarmBuddyDB (account-wide)
FB.charDB = nil         -- Reference to FarmBuddyCharDB (per-character)
FB.mainFrame = nil      -- Main UI frame reference
FB.scanHandle = nil     -- Current async scan handle

function FB:CachePlayerInfo()
    self.playerName = UnitName("player") or "Unknown"
    self.realmName = GetRealmName() or "Unknown"
    self.playerKey = self.playerName .. " - " .. self.realmName
    self.playerLevel = UnitLevel("player") or 1
    self.playerFaction = UnitFactionGroup("player") or "Neutral"
    local _, class = UnitClass("player")
    self.playerClass = class or "WARRIOR"
end
