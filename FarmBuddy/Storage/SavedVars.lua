local addonName, FB = ...

FB.Storage = FB.Storage or {}

local DEFAULTS_ACCOUNT = {
    version = 2,
    settings = {
        debug = false,
        hoursPerDay = 2,  -- FIX-6: configurable playtime assumption (0.5-8h)
        weights = {
            progressRemaining = 1.0,
            timePerAttempt    = 1.0,
            timeGate          = 1.5,
            groupRequirement  = 1.2,
            effort            = 1.0,
        },
        ui = {
            mainFramePoint = "CENTER",
            mainFrameRelPoint = "CENTER",
            mainFrameX = 0,
            mainFrameY = 0,
            mainFrameW = 950,
            mainFrameH = 600,
            trackerPoint = "RIGHT",
            trackerRelPoint = "RIGHT",
            trackerX = -20,
            trackerY = 0,
            trackerLocked = false,
            trackerScale = 1.0,
            lastTab = 1,
        },
        scan = {
            batchSize = 5,
        },
        recommendations = {
            maxResults = 20,
        },
        filterPresets = {},
        filters = {
            mount = {
                showRaidDrop = true,
                showDungeonDrop = true,
                showReputation = true,
                showCurrency = true,
                showQuestChain = true,
                showEvent = true,
                showWorldDrop = true,
                showPvP = true,
                showProfession = true,
                showAchievement = true,
                soloOnly = false,
                expansionFilter = nil,
            },
            achievement = {
                rewardFilter = nil,
                zoneFilter = nil,
            },
        },
    },
    pinnedMounts = {},
    pinnedAchievements = {},
    cachedMountScores = nil,
    cachedAchievementScores = nil,
    characters = {},
    mountAttempts = {},  -- { [spellID] = lastAttemptTimestamp } for staleness tracking
    mountAttemptCounts = {},  -- { [spellID] = { total = N, first = timestamp, last = timestamp } }
    sessionHistory = {},      -- { { timestamp, durationMins, activitiesCompleted = N, mountsObtained = {} } }
    goals = {
        targetMountCount = nil,     -- e.g., 500
        targetExpansion = nil,      -- e.g., "BFA"
        customGoalMounts = {},      -- { [spellID] = true }
    },
    behaviorLog = {
        sourceTypeClicks = {},   -- { [sourceType] = count }
        sourceTypeSkips = {},    -- { [sourceType] = count }
        avgSessionMinutes = 0,
        totalSessions = 0,
    },
    lastResetNotification = 0,   -- Timestamp of last weekly reset notification
    eventNotifications = {},     -- { [eventKey] = timestamp } for holiday event deduplication
}

local DEFAULTS_CHAR = {
    version = 1,
    lockouts = {},
    heroicLockouts = {},  -- { [instanceName] = resetTimestamp } for daily heroic detection
    dailyQuests = {},
    dailyResetTime = 0,
    lastMountScan = 0,
    lastAchievementScan = 0,
}

function FB.Storage:Init()
    -- Account-wide
    if not FarmBuddyDB then
        FarmBuddyDB = FB.Utils:DeepCopy(DEFAULTS_ACCOUNT)
    else
        self:EnsureDefaults(FarmBuddyDB, DEFAULTS_ACCOUNT)
        self:MigrateAccount(FarmBuddyDB)
    end
    FB.db = FarmBuddyDB

    -- Per-character
    if not FarmBuddyCharDB then
        FarmBuddyCharDB = FB.Utils:DeepCopy(DEFAULTS_CHAR)
    else
        self:EnsureDefaults(FarmBuddyCharDB, DEFAULTS_CHAR)
        self:MigrateChar(FarmBuddyCharDB)
    end
    FB.charDB = FarmBuddyCharDB
end

-- Ensure all default keys exist (non-destructive merge)
function FB.Storage:EnsureDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if db[k] == nil then
            if type(v) == "table" then
                db[k] = FB.Utils:DeepCopy(v)
            else
                db[k] = v
            end
        elseif type(v) == "table" and type(db[k]) == "table" then
            self:EnsureDefaults(db[k], v)
        end
    end
end

-- Account data migration
function FB.Storage:MigrateAccount(db)
    if (db.version or 0) < 1 then
        db.version = 1
    end
    if (db.version or 0) < 2 then
        db.version = 2
        -- Migrate flat mountAttempts timestamps to mountAttemptCounts
        if db.mountAttempts then
            db.mountAttemptCounts = db.mountAttemptCounts or {}
            for spellID, timestamp in pairs(db.mountAttempts) do
                if type(timestamp) == "number" and not db.mountAttemptCounts[spellID] then
                    db.mountAttemptCounts[spellID] = { total = 1, first = timestamp, last = timestamp }
                end
            end
        end
    end
    -- Migrate old weight key: dropChance -> effort (only runs when old key is present)
    if db.settings and db.settings.weights then
        local w = db.settings.weights
        if w and w.dropChance ~= nil then
            if not w.effort then
                w.effort = w.dropChance
            end
            w.dropChance = nil
        end
    end
end

-- Character data migration
function FB.Storage:MigrateChar(db)
    if (db.version or 0) < 1 then
        db.version = 1
    end
end

-- Reset settings to defaults
function FB.Storage:ResetSettings()
    FarmBuddyDB.settings = FB.Utils:DeepCopy(DEFAULTS_ACCOUNT.settings)
    FB.db = FarmBuddyDB
    FB:Print("Settings reset to defaults.")
end
