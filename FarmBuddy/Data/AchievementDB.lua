local addonName, FB = ...

FB.AchievementDB = {}

-- Category-level scoring defaults
-- Key is the category name pattern (matched against achievement category names)
-- This avoids relying on categoryIDs which can change
FB.AchievementDB.categoryDefaults = {
    -- Pattern matching on category name
    -- Most dungeon/raid achievements are from legacy content and soloable
    ["Exploration"] = {
        timePerCriterion = 3,
        groupRequirement = "solo",
        timeGate = "none",
    },
    ["Quests"] = {
        timePerCriterion = 10,
        groupRequirement = "solo",
        timeGate = "none",
    },
    ["Dungeons"] = {
        timePerCriterion = 12,
        groupRequirement = "solo",
        timeGate = "none",
    },
    ["Raids"] = {
        timePerCriterion = 15,
        groupRequirement = "solo",
        timeGate = "weekly",
    },
    ["Reputation"] = {
        timePerCriterion = 60,
        groupRequirement = "solo",
        timeGate = "daily",
    },
    ["PvP"] = {
        timePerCriterion = 20,
        groupRequirement = "solo",
        timeGate = "none",
    },
    ["Professions"] = {
        timePerCriterion = 10,
        groupRequirement = "solo",
        timeGate = "none",
    },
    ["Pet Battles"] = {
        timePerCriterion = 10,
        groupRequirement = "solo",
        timeGate = "none",
    },
    ["Collections"] = {
        timePerCriterion = 30,
        groupRequirement = "solo",
        timeGate = "none",
    },
    ["Feats of Strength"] = {
        timePerCriterion = 30,
        groupRequirement = "solo",
        timeGate = "none",
    },
    ["General"] = {
        timePerCriterion = 10,
        groupRequirement = "solo",
        timeGate = "none",
    },
    ["World Events"] = {
        timePerCriterion = 15,
        groupRequirement = "solo",
        timeGate = "yearly",
    },
    ["Expansion Features"] = {
        timePerCriterion = 15,
        groupRequirement = "solo",
        timeGate = "weekly",
    },
    ["Legacy"] = {
        timePerCriterion = 10,
        groupRequirement = "solo",
        timeGate = "none",
    },
}

-- Fallback for unknown categories
FB.AchievementDB.defaultScoring = {
    timePerCriterion = 10,
    groupRequirement = "solo",
    timeGate = "none",
}

-- Per-achievement overrides for special scoring
-- Use these when category defaults are too generic
FB.AchievementDB.overrides = {
    -- Glory meta-achievements (raid): weekly gated, requires specific boss kills
    [2136]  = { timePerCriterion = 20, groupRequirement = "solo", timeGate = "none", expansion = "WOTLK" },
    [2137]  = { timePerCriterion = 30, groupRequirement = "solo", timeGate = "weekly", expansion = "WOTLK" },
    [2138]  = { timePerCriterion = 30, groupRequirement = "solo", timeGate = "weekly", expansion = "WOTLK" },
    [4602]  = { timePerCriterion = 15, groupRequirement = "solo", timeGate = "weekly", expansion = "WOTLK" },
    [4603]  = { timePerCriterion = 15, groupRequirement = "solo", timeGate = "weekly", expansion = "WOTLK" },
    [5828]  = { timePerCriterion = 12, groupRequirement = "solo", timeGate = "weekly", expansion = "CATA" },
    [6169]  = { timePerCriterion = 15, groupRequirement = "solo", timeGate = "weekly", expansion = "CATA" },
    [8124]  = { timePerCriterion = 20, groupRequirement = "solo", timeGate = "weekly", expansion = "MOP" },
    [8454]  = { timePerCriterion = 25, groupRequirement = "solo", timeGate = "weekly", expansion = "MOP" },
    [8845]  = { timePerCriterion = 10, groupRequirement = "solo", timeGate = "none", expansion = "WOD" },
    [9838]  = { timePerCriterion = 25, groupRequirement = "solo", timeGate = "weekly", expansion = "WOD" },
    [11180] = { timePerCriterion = 12, groupRequirement = "solo", timeGate = "none", expansion = "LEGION" },
    [11987] = { timePerCriterion = 20, groupRequirement = "solo", timeGate = "weekly", expansion = "LEGION" },
    [12806] = { timePerCriterion = 20, groupRequirement = "small", timeGate = "weekly", expansion = "BFA" },
    [13315] = { timePerCriterion = 25, groupRequirement = "small", timeGate = "weekly", expansion = "BFA" },
    -- Newer glory achievements (may need groups)
    [13687] = { timePerCriterion = 20, groupRequirement = "small", timeGate = "weekly", expansion = "BFA" },   -- Glory of the Eternal Raider
    [14355] = { timePerCriterion = 25, groupRequirement = "small", timeGate = "weekly", expansion = "SL" },    -- Glory of the Nathria Raider
    [15126] = { timePerCriterion = 25, groupRequirement = "small", timeGate = "weekly", expansion = "SL" },    -- Glory of the Dominant Raider
    [15478] = { timePerCriterion = 25, groupRequirement = "small", timeGate = "weekly", expansion = "SL" },    -- Glory of the Sepulcher Raider
    [16354] = { timePerCriterion = 25, groupRequirement = "small", timeGate = "weekly", expansion = "DF" },    -- Glory of the Vault Raider
    [17879] = { timePerCriterion = 25, groupRequirement = "small", timeGate = "weekly", expansion = "DF" },    -- Glory of the Aberrus Raider
    -- Dungeon glory: no weekly lockout, just need to do each dungeon once
    [14322] = { timePerCriterion = 15, groupRequirement = "solo", timeGate = "none", expansion = "SL" },       -- Glory of the Shadowlands Hero
    [16647] = { timePerCriterion = 12, groupRequirement = "solo", timeGate = "none", expansion = "DF" },       -- Glory of the Dragonflight Hero
    -- Collection milestones
    [2143]  = { timePerCriterion = 0, groupRequirement = "solo", timeGate = "none", expansion = "WOTLK" },     -- Leading the Cavalry (100 mounts)
    [7860]  = { timePerCriterion = 0, groupRequirement = "solo", timeGate = "none", expansion = "MOP" },       -- We're Going to Need More Saddles (200 mounts)
    [12933] = { timePerCriterion = 0, groupRequirement = "solo", timeGate = "none", expansion = "BFA" },       -- No Stable Big Enough (300 mounts)
    [15917] = { timePerCriterion = 0, groupRequirement = "solo", timeGate = "none", expansion = "SL" },        -- Mount Parade (400 mounts)
    [17739] = { timePerCriterion = 0, groupRequirement = "solo", timeGate = "none", expansion = "DF" },        -- Lord of the Reins (500 mounts)
    -- World event meta-achievements (yearly events)
    [2144]  = { timePerCriterion = 15, groupRequirement = "solo", timeGate = "yearly", expansion = "WOTLK" },  -- What A Long, Strange Trip It's Been
}

-- Known achievements that reward mounts, titles, pets, etc.
-- Pre-populated for reliability (runtime scanning adds more)
FB.AchievementDB.knownRewards = {
    -- [achievementID] = rewardType

    -- WotLK Glory achievements (mount rewards)
    [2136]  = "mount",  -- Glory of the Hero → Red Proto-Drake
    [2137]  = "mount",  -- Glory of the Raider (10) → Plagued Proto-Drake
    [2138]  = "mount",  -- Glory of the Raider (25) → Black Proto-Drake
    [4602]  = "mount",  -- Glory of the Icecrown Raider (10)
    [4603]  = "mount",  -- Glory of the Icecrown Raider (25)

    -- Cataclysm
    [5828]  = "mount",  -- Glory of the Firelands Raider → Corrupted Fire Hawk
    [6169]  = "mount",  -- Glory of the Dragon Soul Raider → Life-Binder's Handmaiden
    [4845]  = "mount",  -- Glory of the Cataclysm Hero → Volcanic Stone Drake

    -- Mists of Pandaria
    [8124]  = "mount",  -- Glory of the Thundering Raider → Armored Skyscreamer
    [8454]  = "mount",  -- Glory of the Orgrimmar Raider → Kor'kron War Wolf
    [6927]  = "mount",  -- Glory of the Pandaria Hero → Crimson Pandaren Phoenix

    -- Warlords of Draenor
    [8845]  = "mount",  -- Glory of the Draenor Hero → Frostplains Battleboar
    [9838]  = "mount",  -- Glory of the Hellfire Raider
    [9396]  = "mount",  -- Glory of the Draenor Raider → Iron Warhorse

    -- Legion
    [11180] = "mount",  -- Glory of the Legion Hero → Leyfeather Hippogryph
    [11987] = "mount",  -- Glory of the Argus Raider
    [11164] = "mount",  -- Glory of the Tomb Raider

    -- Battle for Azeroth
    [12806] = "mount",  -- Glory of the Uldir Raider
    [13315] = "mount",  -- Glory of the Dazar'alor Raider
    [13687] = "mount",  -- Glory of the Eternal Raider → Azshari Bloatray
    [14068] = "mount",  -- Glory of the Ny'alotha Raider
    [12932] = "mount",  -- Glory of the Wartorn Hero

    -- Shadowlands
    [14355] = "mount",  -- Glory of the Nathria Raider → Rampart Screecher
    [15126] = "mount",  -- Glory of the Dominant Raider
    [15478] = "mount",  -- Glory of the Sepulcher Raider
    [14322] = "mount",  -- Glory of the Shadowlands Hero

    -- Dragonflight
    [16354] = "mount",  -- Glory of the Vault Raider
    [17879] = "mount",  -- Glory of the Aberrus Raider
    [19393] = "mount",  -- Glory of the Dream Raider
    [16647] = "mount",  -- Glory of the Dragonflight Hero

    -- Collection milestones (mounts)
    [2143]  = "mount",  -- Leading the Cavalry (100 mounts) → Blue Dragonhawk
    [7860]  = "mount",  -- We're Going to Need More Saddles (200 mounts)
    [12933] = "mount",  -- No Stable Big Enough (300 mounts) → Frenzied Feltalon
    [15917] = "mount",  -- Mount Parade (400 mounts) → Otterworldly Ottuk Carrier
    [17739] = "mount",  -- Lord of the Reins (500 mounts)

    -- World event meta
    [2144]  = "mount",  -- What A Long, Strange Trip It's Been → Violet Proto-Drake

    -- Titles
    [2186]  = "title",  -- The Loremaster
    [6924]  = "title",  -- Pandaren Ambassador
    [7520]  = "title",  -- The Beloved

    -- Pets
    [12930] = "pet",    -- Battle on Two Fronts
}

function FB.AchievementDB:Get(achievementID)
    return self.overrides[achievementID]
end

function FB.AchievementDB:GetCategoryDefaults(categoryName)
    -- Try exact match first
    if self.categoryDefaults[categoryName] then
        return self.categoryDefaults[categoryName]
    end
    -- Try pattern matching
    for pattern, defaults in pairs(self.categoryDefaults) do
        if categoryName and categoryName:find(pattern) then
            return defaults
        end
    end
    return self.defaultScoring
end

function FB.AchievementDB:GetRewardType(achievementID)
    return self.knownRewards[achievementID]
end

-- Try to parse reward type from achievement reward text
function FB.AchievementDB:ParseRewardType(rewardText)
    if not rewardText or rewardText == "" then return "none" end
    local lower = rewardText:lower()
    if lower:find("mount") then return "mount" end
    if lower:find("title") then return "title" end
    if lower:find("pet") then return "pet" end
    if lower:find("transmog") or lower:find("appearance") then return "transmog" end
    if lower:find("toy") then return "toy" end
    return "none"
end
