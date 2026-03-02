local addonName, FB = ...

FB.InstanceData = {}

-- Instance metadata for clear time estimates and mount tracking
-- Key is the localized instance name as returned by GetSavedInstanceInfo
FB.InstanceData.instances = {
    -- WOTLK
    ["Icecrown Citadel"] = {
        expansion = "WOTLK",
        bossCount = 12,
        soloMinutes = 15,
    },
    ["Ulduar"] = {
        expansion = "WOTLK",
        bossCount = 14,
        soloMinutes = 20,
    },
    ["Vault of Archavon"] = {
        expansion = "WOTLK",
        bossCount = 4,
        soloMinutes = 5,
    },
    ["Obsidian Sanctum"] = {
        expansion = "WOTLK",
        bossCount = 1,
        soloMinutes = 3,
    },
    ["Eye of Eternity"] = {
        expansion = "WOTLK",
        bossCount = 1,
        soloMinutes = 5,
    },
    ["Naxxramas"] = {
        expansion = "WOTLK",
        bossCount = 15,
        soloMinutes = 25,
    },
    ["Trial of the Crusader"] = {
        expansion = "WOTLK",
        bossCount = 5,
        soloMinutes = 8,
    },
    -- TBC
    ["Tempest Keep"] = {
        expansion = "TBC",
        bossCount = 4,
        soloMinutes = 10,
    },
    ["Karazhan"] = {
        expansion = "TBC",
        bossCount = 12,
        soloMinutes = 15,
    },
    ["Black Temple"] = {
        expansion = "TBC",
        bossCount = 9,
        soloMinutes = 15,
    },
    -- CATA
    ["Firelands"] = {
        expansion = "CATA",
        bossCount = 7,
        soloMinutes = 12,
    },
    ["Dragon Soul"] = {
        expansion = "CATA",
        bossCount = 8,
        soloMinutes = 15,
    },
    ["Throne of the Four Winds"] = {
        expansion = "CATA",
        bossCount = 2,
        soloMinutes = 5,
    },
    -- MOP
    ["Throne of Thunder"] = {
        expansion = "MOP",
        bossCount = 13,
        soloMinutes = 20,
    },
    ["Siege of Orgrimmar"] = {
        expansion = "MOP",
        bossCount = 14,
        soloMinutes = 25,
    },
    ["Mogu'shan Vaults"] = {
        expansion = "MOP",
        bossCount = 6,
        soloMinutes = 10,
    },
    ["Heart of Fear"] = {
        expansion = "MOP",
        bossCount = 6,
        soloMinutes = 12,
    },
    -- WOD
    ["Blackrock Foundry"] = {
        expansion = "WOD",
        bossCount = 10,
        soloMinutes = 20,
    },
    ["Hellfire Citadel"] = {
        expansion = "WOD",
        bossCount = 13,
        soloMinutes = 25,
    },
    ["Highmaul"] = {
        expansion = "WOD",
        bossCount = 7,
        soloMinutes = 15,
    },
    -- LEGION
    ["Antorus, the Burning Throne"] = {
        expansion = "LEGION",
        bossCount = 11,
        soloMinutes = 20,
    },
    ["The Nighthold"] = {
        expansion = "LEGION",
        bossCount = 10,
        soloMinutes = 20,
    },
    ["Emerald Nightmare"] = {
        expansion = "LEGION",
        bossCount = 7,
        soloMinutes = 15,
    },
    ["Tomb of Sargeras"] = {
        expansion = "LEGION",
        bossCount = 9,
        soloMinutes = 18,
    },
    -- BFA
    ["Uldir"] = {
        expansion = "BFA",
        bossCount = 8,
        soloMinutes = 20,
    },
    ["Battle of Dazar'alor"] = {
        expansion = "BFA",
        bossCount = 9,
        soloMinutes = 25,
    },
    ["Ny'alotha, the Waking City"] = {
        expansion = "BFA",
        bossCount = 12,
        soloMinutes = 30,
    },
    -- SHADOWLANDS
    ["Castle Nathria"] = {
        expansion = "SL",
        bossCount = 10,
        soloMinutes = 25,
    },
    ["Sanctum of Domination"] = {
        expansion = "SL",
        bossCount = 10,
        soloMinutes = 25,
    },
    ["Sepulcher of the First Ones"] = {
        expansion = "SL",
        bossCount = 11,
        soloMinutes = 30,
    },
    -- DRAGONFLIGHT
    ["Vault of the Incarnates"] = {
        expansion = "DF",
        bossCount = 8,
        soloMinutes = 25,
    },
    ["Aberrus, the Shadowed Crucible"] = {
        expansion = "DF",
        bossCount = 9,
        soloMinutes = 25,
    },
    ["Amirdrassil, the Dream's Hope"] = {
        expansion = "DF",
        bossCount = 9,
        soloMinutes = 30,
    },
    -- THE WAR WITHIN
    ["Nerub-ar Palace"] = {
        expansion = "TWW",
        bossCount = 8,
        soloMinutes = 35,
    },
    ["Liberation of Undermine"] = {
        expansion = "TWW",
        bossCount = 8,
        soloMinutes = 40,
    },
    -- Dungeons
    ["Stratholme"] = {
        expansion = "CLASSIC",
        bossCount = 5,
        soloMinutes = 8,
    },
    ["Sethekk Halls"] = {
        expansion = "TBC",
        bossCount = 3,
        soloMinutes = 5,
    },
    ["Magisters' Terrace"] = {
        expansion = "TBC",
        bossCount = 4,
        soloMinutes = 5,
    },
    ["Utgarde Pinnacle"] = {
        expansion = "WOTLK",
        bossCount = 3,
        soloMinutes = 5,
    },
    ["Vortex Pinnacle"] = {
        expansion = "CATA",
        bossCount = 3,
        soloMinutes = 5,
    },
    ["Stonecore"] = {
        expansion = "CATA",
        bossCount = 4,
        soloMinutes = 6,
    },
    ["Return to Karazhan"] = {
        expansion = "LEGION",
        bossCount = 8,
        soloMinutes = 15,
    },
    ["Freehold"] = {
        expansion = "BFA",
        bossCount = 4,
        soloMinutes = 6,
    },
    ["Tazavesh, the Veiled Market"] = {
        expansion = "SL",
        bossCount = 8,
        soloMinutes = 12,
    },
    -- TWW Dungeons
    ["The Stonevault"] = {
        expansion = "TWW",
        bossCount = 4,
        soloMinutes = 8,
    },
    ["The Dawnbreaker"] = {
        expansion = "TWW",
        bossCount = 3,
        soloMinutes = 7,
    },
    ["Ara-Kara, City of Echoes"] = {
        expansion = "TWW",
        bossCount = 3,
        soloMinutes = 7,
    },
    ["City of Threads"] = {
        expansion = "TWW",
        bossCount = 4,
        soloMinutes = 8,
    },
    ["Cinderbrew Meadery"] = {
        expansion = "TWW",
        bossCount = 3,
        soloMinutes = 7,
    },
    ["Darkflame Cleft"] = {
        expansion = "TWW",
        bossCount = 4,
        soloMinutes = 8,
    },
    ["Priory of the Sacred Flame"] = {
        expansion = "TWW",
        bossCount = 3,
        soloMinutes = 7,
    },
    ["The Rookery"] = {
        expansion = "TWW",
        bossCount = 4,
        soloMinutes = 8,
    },
}

function FB.InstanceData:Get(instanceName)
    return self.instances[instanceName]
end

function FB.InstanceData:GetClearTime(instanceName)
    local data = self.instances[instanceName]
    return data and data.soloMinutes or 15
end
