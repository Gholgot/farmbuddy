local addonName, FB = ...

FB.MountDB = {}

-- Mount database keyed by spellID (from C_MountJournal.GetMountInfoByID)
-- Curated entries with accurate scoring data for popular farmable mounts.
-- Mounts NOT in this list still appear via Blizzard API with estimated defaults.
FB.MountDB.entries = {

    -- =====================
    -- WOTLK RAID DROPS
    -- =====================
    [72286] = { -- Invincible's Reins
        sourceType = "raid_drop",
        expansion = "WOTLK",
        timeGate = "weekly",
        timePerAttempt = 22,
        groupRequirement = "solo",
        dropChance = 0.01,  -- ~1% confirmed via community data mining
        lockoutInstanceName = "Icecrown Citadel",
        difficultyID = 6,  -- 25H
        steps = {
            "Enter Icecrown Citadel on 25-player Heroic",
            "Clear through all bosses to The Lich King",
            "Defeat The Lich King - 1% drop chance",
        },
    },
    [63796] = { -- Mimiron's Head
        sourceType = "raid_drop",
        expansion = "WOTLK",
        timeGate = "weekly",
        timePerAttempt = 25,
        groupRequirement = "solo",
        dropChance = 0.01,  -- ~1% confirmed
        lockoutInstanceName = "Ulduar",
        difficultyID = 4,  -- 25N
        steps = {
            "Enter Ulduar 25-player",
            "Activate hard mode: press the big red button, talk to no keepers",
            "Defeat Yogg-Saron with 0 keepers - 1% drop chance",
        },
    },
    [59961] = { -- Red Proto-Drake (Glory of the Hero)
        sourceType = "achievement",
        expansion = "WOTLK",
        timeGate = "none",
        timePerAttempt = 20,
        groupRequirement = "solo",
        dropChance = nil,
        achievementID = 2136,
        steps = {
            "Complete all WotLK Heroic dungeon achievements",
            "Achievement: Glory of the Hero",
        },
    },
    [61465] = { -- Grand Black War Mammoth
        sourceType = "raid_drop",
        expansion = "WOTLK",
        timeGate = "weekly",
        timePerAttempt = 5,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Vault of Archavon",
        difficultyID = 4,
        steps = {
            "Enter Vault of Archavon (any difficulty)",
            "Kill any boss - all can drop the mount",
        },
    },
    [59567] = { -- Azure Drake
        sourceType = "raid_drop",
        expansion = "WOTLK",
        timeGate = "weekly",
        timePerAttempt = 5,
        groupRequirement = "solo",
        dropChance = 0.04,
        lockoutInstanceName = "Eye of Eternity",
        difficultyID = 4,
        steps = {
            "Enter Eye of Eternity",
            "Defeat Malygos - ~4% drop chance",
        },
    },
    [59568] = { -- Blue Drake
        sourceType = "raid_drop",
        expansion = "WOTLK",
        timeGate = "weekly",
        timePerAttempt = 5,
        groupRequirement = "solo",
        dropChance = 0.04,
        lockoutInstanceName = "Eye of Eternity",
        difficultyID = 4,
        steps = {
            "Enter Eye of Eternity",
            "Defeat Malygos - ~4% drop chance",
        },
    },
    [60021] = { -- Plagued Proto-Drake (Glory of the Raider 10)
        sourceType = "achievement",
        expansion = "WOTLK",
        timeGate = "weekly",
        timePerAttempt = 30,
        groupRequirement = "solo",
        dropChance = nil,
        achievementID = 2137,
        steps = {
            "Complete all Naxxramas/OS/EoE 10-player achievements",
            "Achievement: Glory of the Raider (10-player)",
        },
    },
    [69395] = { -- Onyxian Drake
        sourceType = "raid_drop",
        expansion = "WOTLK",
        timeGate = "weekly",
        timePerAttempt = 3,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Onyxia's Lair",
        difficultyID = 4,
        steps = {
            "Enter Onyxia's Lair",
            "Defeat Onyxia - ~1% drop chance",
        },
    },
    [60002] = { -- Time-Lost Proto-Drake
        sourceType = "world_drop",
        expansion = "WOTLK",
        timeGate = "none",
        timePerAttempt = 240,
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 50,  -- Extremely long camping sessions, realistic estimate
        steps = {
            "Camp TLPD spawn points in Storm Peaks",
            "Shares spawn timer with Vyragosa (6-24 hour respawn)",
            "Flies specific flight paths in Storm Peaks",
            "Guaranteed drop on kill - must tag first",
            "Extremely competitive, may take days of camping",
        },
    },

    -- =====================
    -- TBC RAID DROPS
    -- =====================
    [40192] = { -- Ashes of Al'ar
        sourceType = "raid_drop",
        expansion = "TBC",
        timeGate = "weekly",
        timePerAttempt = 10,
        groupRequirement = "solo",
        dropChance = 0.018,  -- ~1.8% confirmed via WoWHead/community data
        lockoutInstanceName = "Tempest Keep",
        difficultyID = 4,
        steps = {
            "Enter Tempest Keep: The Eye",
            "Clear to Kael'thas Sunstrider",
            "Defeat Kael'thas - ~1.7% drop chance",
        },
    },
    [36702] = { -- Fiery Warhorse
        sourceType = "raid_drop",
        expansion = "TBC",
        timeGate = "weekly",
        timePerAttempt = 2,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Karazhan",
        difficultyID = 4,
        steps = {
            "Enter Karazhan (original)",
            "Defeat Attumen the Huntsman (first boss) - ~1% drop",
        },
    },

    -- =====================
    -- CATA RAID DROPS
    -- =====================
    [97493] = { -- Pureblood Fire Hawk (Firelands Ragnaros)
        sourceType = "raid_drop",
        expansion = "CATA",
        timeGate = "weekly",
        timePerAttempt = 12,
        groupRequirement = "solo",
        dropChance = 0.02,
        lockoutInstanceName = "Firelands",
        difficultyID = 6,
        steps = {
            "Enter Firelands on Heroic (25 or 10)",
            "Clear to Ragnaros",
            "Defeat Ragnaros - ~2% drop chance",
        },
    },
    [101542] = { -- Flametalon of Alysrazor
        sourceType = "raid_drop",
        expansion = "CATA",
        timeGate = "weekly",
        timePerAttempt = 12,
        groupRequirement = "solo",
        dropChance = 0.02,
        lockoutInstanceName = "Firelands",
        difficultyID = 6,
        steps = {
            "Enter Firelands",
            "Defeat Alysrazor - ~2% drop chance",
        },
    },
    [110039] = { -- Experiment 12-B (Dragon Soul)
        sourceType = "raid_drop",
        expansion = "CATA",
        timeGate = "weekly",
        timePerAttempt = 15,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Dragon Soul",
        difficultyID = 6,
        steps = {
            "Enter Dragon Soul on Heroic 25",
            "Clear to Ultraxion",
            "Defeat Ultraxion - ~1% drop chance",
        },
    },
    [107845] = { -- Blazing Drake (Dragon Soul Deathwing)
        sourceType = "raid_drop",
        expansion = "CATA",
        timeGate = "weekly",
        timePerAttempt = 15,
        groupRequirement = "solo",
        dropChance = 0.02,
        lockoutInstanceName = "Dragon Soul",
        difficultyID = 6,
        steps = {
            "Enter Dragon Soul on any Heroic difficulty",
            "Clear to Madness of Deathwing",
            "Defeat Deathwing - ~2% drop chance",
        },
    },
    [88335] = { -- Drake of the North Wind
        sourceType = "dungeon_drop",
        expansion = "CATA",
        timeGate = "none",
        timePerAttempt = 5,
        groupRequirement = "solo",
        dropChance = 0.008,
        steps = {
            "Enter Vortex Pinnacle (Normal or Heroic)",
            "Defeat Altairus - ~0.8% drop chance",
            "Farmable: no lockout on Normal",
        },
    },
    [88331] = { -- Vitreous Stone Drake
        sourceType = "dungeon_drop",
        expansion = "CATA",
        timeGate = "none",
        timePerAttempt = 6,
        groupRequirement = "solo",
        dropChance = 0.008,
        steps = {
            "Enter Stonecore (Normal or Heroic)",
            "Defeat Slabhide - ~0.8% drop chance",
            "Farmable: no lockout on Normal",
        },
    },
    [97560] = { -- Corrupted Fire Hawk (Glory of the Firelands Raider)
        sourceType = "achievement",
        expansion = "CATA",
        timeGate = "weekly",
        timePerAttempt = 30,
        groupRequirement = "solo",
        dropChance = nil,
        achievementID = 5828,
        steps = {
            "Complete all Firelands raid achievements",
            "Achievement: Glory of the Firelands Raider",
        },
    },

    -- =====================
    -- MOP RAID DROPS
    -- =====================
    [136471] = { -- Spawn of Horridon
        sourceType = "raid_drop",
        expansion = "MOP",
        timeGate = "weekly",
        timePerAttempt = 20,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Throne of Thunder",
        difficultyID = 6,
        steps = {
            "Enter Throne of Thunder on Heroic 25",
            "Defeat Horridon (2nd boss) - ~1% drop chance",
        },
    },
    [148417] = { -- Kor'kron Juggernaut
        sourceType = "raid_drop",
        expansion = "MOP",
        timeGate = "weekly",
        timePerAttempt = 25,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Siege of Orgrimmar",
        difficultyID = 6,
        steps = {
            "Enter Siege of Orgrimmar on Mythic",
            "Clear to Garrosh Hellscream",
            "Defeat Garrosh - ~1% drop chance",
        },
    },
    [87771] = { -- Astral Cloud Serpent
        sourceType = "raid_drop",
        expansion = "MOP",
        timeGate = "weekly",
        timePerAttempt = 10,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Mogu'shan Vaults",
        difficultyID = 6,
        steps = {
            "Enter Mogu'shan Vaults on Heroic 25",
            "Defeat Elegon - ~1% drop chance",
        },
    },

    -- =====================
    -- DUNGEON DROPS
    -- =====================
    [48778] = { -- Deathcharger's Reins (Baron Rivendare)
        sourceType = "dungeon_drop",
        expansion = "CLASSIC",
        timeGate = "none",
        timePerAttempt = 8,
        groupRequirement = "solo",
        dropChance = 0.008,
        steps = {
            "Enter Stratholme (Service Entrance)",
            "Clear to Baron Rivendare",
            "Defeat Baron - ~0.8% drop chance",
            "Farmable: reset instance and repeat (10/hour limit)",
        },
    },
    [41252] = { -- Raven Lord
        sourceType = "dungeon_drop",
        expansion = "TBC",
        timeGate = "none",  -- Legacy dungeon, no lockout on Normal
        timePerAttempt = 5,
        groupRequirement = "solo",
        dropChance = 0.01,
        steps = {
            "Enter Sethekk Halls (Normal - farmable with resets)",
            "Clear to Anzu",
            "Defeat Anzu - ~1% drop chance",
            "Farmable: reset instance and repeat (10/hour limit)",
        },
    },

    -- =====================
    -- WOD RAID DROPS
    -- =====================
    [171851] = { -- Ironhoof Destroyer (Blackhand BRF)
        sourceType = "raid_drop",
        expansion = "WOD",
        timeGate = "weekly",
        timePerAttempt = 20,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Blackrock Foundry",
        difficultyID = 16,
        steps = {
            "Enter Blackrock Foundry on Mythic",
            "Clear to Blackhand",
            "Defeat Blackhand - ~1% drop chance",
        },
    },
    [186828] = { -- Felsteel Annihilator (Archimonde HFC)
        sourceType = "raid_drop",
        expansion = "WOD",
        timeGate = "weekly",
        timePerAttempt = 25,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Hellfire Citadel",
        difficultyID = 16,
        steps = {
            "Enter Hellfire Citadel on Mythic",
            "Clear to Archimonde",
            "Defeat Archimonde - ~1% drop chance",
        },
    },

    -- =====================
    -- LEGION RAID DROPS
    -- =====================
    [253639] = { -- Shackled Ur'zul (Antorus Argus)
        sourceType = "raid_drop",
        expansion = "LEGION",
        timeGate = "weekly",
        timePerAttempt = 20,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Antorus, the Burning Throne",
        difficultyID = 16,
        steps = {
            "Enter Antorus, the Burning Throne on Mythic",
            "Clear to Argus the Unmaker",
            "Defeat Argus - ~1% drop chance",
        },
    },
    [248888] = { -- Midnight (Return to Karazhan)
        sourceType = "dungeon_drop",
        expansion = "LEGION",
        timeGate = "none",
        timePerAttempt = 3,
        groupRequirement = "solo",
        dropChance = 0.01,
        steps = {
            "Enter Return to Karazhan (lower)",
            "Defeat Attumen the Huntsman - ~1% drop",
        },
    },

    -- =====================
    -- REPUTATION MOUNTS
    -- =====================
    [37015] = { -- Netherwing Drake (one of several colors)
        sourceType = "reputation",
        expansion = "TBC",
        timeGate = "daily",
        timePerAttempt = 20,
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 14,
        factionID = 1015,
        targetStanding = 8,
        steps = {
            "Reach Neutral with Netherwing (starting quest chain in Shadowmoon Valley)",
            "Complete daily quests at Netherwing Ledge each day",
            "Reach Exalted with Netherwing",
            "Purchase your chosen drake from the vendor",
        },
    },

    -- =====================
    -- CURRENCY MOUNTS
    -- =====================
    [171828] = { -- Mosshide Riverwallow (WoD Garrison)
        sourceType = "currency_grind",
        expansion = "WOD",
        timeGate = "none",
        timePerAttempt = 5,
        groupRequirement = "solo",
        dropChance = nil,
        currencyID = 824,
        currencyRequired = 5000,
        steps = {
            "Collect 5000 Garrison Resources",
            "Purchase from vendor in your Garrison",
        },
    },

    -- =====================
    -- EVENT MOUNTS
    -- =====================
    [48025] = { -- Headless Horseman's Mount
        sourceType = "event",
        expansion = "CLASSIC",
        timeGate = "yearly",
        timePerAttempt = 3,
        groupRequirement = "solo",
        dropChance = 0.005,
        steps = {
            "Queue for Headless Horseman during Hallow's End (October)",
            "Defeat the Headless Horseman",
            "~0.5% drop chance per daily kill",
        },
    },
    [71342] = { -- Big Love Rocket
        sourceType = "event",
        expansion = "CLASSIC",
        timeGate = "yearly",
        timePerAttempt = 3,
        groupRequirement = "solo",
        dropChance = 0.0003,
        steps = {
            "Queue for Crown Chemical Co. during Love is in the Air (February)",
            "Defeat the bosses",
            "~0.03% drop chance (extremely rare)",
        },
    },

    -- =====================
    -- TBC DUNGEON & WORLD DROPS
    -- =====================
    [46628] = { -- Swift White Hawkstrider (Kael'thas, MGT)
        sourceType = "dungeon_drop",
        expansion = "TBC",
        timeGate = "none",
        timePerAttempt = 3,
        groupRequirement = "solo",
        dropChance = 0.02,
        steps = {
            "Enter Magisters' Terrace (Heroic for higher drop rate)",
            "Clear to Kael'thas Sunstrider",
            "Defeat Kael'thas - ~2% drop chance on Heroic",
        },
    },

    -- =====================
    -- WOTLK ADDITIONAL
    -- =====================
    [59996] = { -- Blue Proto-Drake (Skadi, Utgarde Pinnacle)
        sourceType = "dungeon_drop",
        expansion = "WOTLK",
        timeGate = "none",
        timePerAttempt = 5,
        groupRequirement = "solo",
        dropChance = 0.008,
        steps = {
            "Enter Utgarde Pinnacle (Normal - farmable with resets)",
            "Clear to Skadi the Ruthless",
            "Defeat Skadi - ~0.8% drop chance",
        },
    },
    [60025] = { -- Plagued Proto-Drake (Glory of the Raider 25)
        sourceType = "achievement",
        expansion = "WOTLK",
        timeGate = "weekly",
        timePerAttempt = 30,
        groupRequirement = "solo",
        dropChance = nil,
        achievementID = 2138,
        steps = {
            "Complete all Naxxramas/OS/EoE 25-player achievements",
            "Achievement: Glory of the Raider (25-player)",
        },
    },

    -- =====================
    -- CATA ADDITIONAL
    -- =====================
    [97359] = { -- Flameward Hippogryph (Molten Front dailies)
        sourceType = "reputation",
        expansion = "CATA",
        timeGate = "daily",
        timePerAttempt = 25,
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 30,
        factionID = 1158,       -- Guardians of Hyjal
        targetStanding = 8,     -- Exalted (vendors unlock along the way)
        steps = {
            "Complete Hyjal quest chain to unlock Molten Front",
            "Complete Molten Front dailies each day",
            "Unlock all vendors via Mark of the World Tree",
            "Purchase mount from vendor",
        },
    },
    [107844] = { -- Life-Binder's Handmaiden (Glory of the Dragon Soul Raider)
        sourceType = "achievement",
        expansion = "CATA",
        timeGate = "weekly",
        timePerAttempt = 30,
        groupRequirement = "solo",
        dropChance = nil,
        achievementID = 6169,
        steps = {
            "Complete all Dragon Soul raid achievements",
            "Achievement: Glory of the Dragon Soul Raider",
        },
    },

    -- =====================
    -- MOP ADDITIONAL
    -- =====================
    [136163] = { -- Ji-Kun (Throne of Thunder)
        sourceType = "raid_drop",
        expansion = "MOP",
        timeGate = "weekly",
        timePerAttempt = 20,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Throne of Thunder",
        difficultyID = 6,
        steps = {
            "Enter Throne of Thunder on Heroic 25",
            "Defeat Ji-Kun - ~1% drop chance",
        },
    },
    [148428] = { -- Kor'kron War Wolf (SoO, Horde)
        sourceType = "achievement",
        expansion = "MOP",
        timeGate = "weekly",
        timePerAttempt = 25,
        groupRequirement = "solo",
        dropChance = nil,
        achievementID = 8454,
        steps = {
            "Complete all Siege of Orgrimmar achievements",
            "Achievement: Glory of the Orgrimmar Raider",
        },
    },
    [129552] = { -- Crimson Cloud Serpent (Glory of the Thundering Raider)
        sourceType = "achievement",
        expansion = "MOP",
        timeGate = "weekly",
        timePerAttempt = 30,
        groupRequirement = "solo",
        dropChance = nil,
        achievementID = 8124,
        steps = {
            "Complete all Throne of Thunder achievements",
            "Achievement: Glory of the Thundering Raider",
        },
    },
    [87773] = { -- Heavenly Onyx Cloud Serpent (Sha of Anger world boss)
        sourceType = "world_drop",
        expansion = "MOP",
        timeGate = "weekly",
        timePerAttempt = 5,
        groupRequirement = "solo",
        dropChance = 0.003,
        steps = {
            "Kill Sha of Anger in Kun-Lai Summit",
            "World boss, respawns every 15 minutes",
            "~0.3% drop chance, one chance per week per character",
        },
    },
    [90655] = { -- Thundering Ruby Cloud Serpent (Alani, world rare)
        sourceType = "world_drop",
        expansion = "MOP",
        timeGate = "none",
        timePerAttempt = 60,
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 10,
        steps = {
            "Collect 10 Skyshards from mobs in Vale of Eternal Blossoms",
            "Combine into Sky Crystal to force Alani to land",
            "Kill Alani - guaranteed drop",
            "Skyshards are ~1% drop from vale mobs",
        },
    },

    -- =====================
    -- WOD ADDITIONAL
    -- =====================
    [171617] = { -- Ironhoof Destroyer (Glory of the Draenor Raider)
        sourceType = "achievement",
        expansion = "WOD",
        timeGate = "weekly",
        timePerAttempt = 25,
        groupRequirement = "solo",
        dropChance = nil,
        achievementID = 9838,
        steps = {
            "Complete all Hellfire Citadel achievements",
            "Achievement: Glory of the Hellfire Raider",
        },
    },
    [171849] = { -- Void Talon of the Dark Star (WoD edge of reality portals)
        sourceType = "world_drop",
        expansion = "WOD",
        timeGate = "none",
        timePerAttempt = 120,
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 30,
        steps = {
            "Look for Edge of Reality portals in Draenor zones",
            "Portals spawn randomly, contested by other players",
            "Walk through portal when found - guaranteed mount",
            "Extremely rare spawn, requires camping or luck",
        },
    },

    [235764] = { -- Living Infernal Core (Gul'dan Mythic, Nighthold)
        sourceType = "raid_drop",
        expansion = "LEGION",
        timeGate = "weekly",
        timePerAttempt = 20,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "The Nighthold",
        difficultyID = 16,
        steps = {
            "Enter The Nighthold on Mythic",
            "Clear to Gul'dan",
            "Defeat Gul'dan - ~1% drop chance",
        },
    },
    [253058] = { -- Antoran Charhound (Antorus, Felhounds)
        sourceType = "raid_drop",
        expansion = "LEGION",
        timeGate = "weekly",
        timePerAttempt = 20,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Antorus, the Burning Throne",
        difficultyID = 16,
        steps = {
            "Enter Antorus, the Burning Throne on Mythic",
            "Defeat Felhounds of Sargeras - ~1% drop chance",
        },
    },
    [243025] = { -- Riddler's Mind-Worm (secret mount, Forgotten Grotto)
        sourceType = "quest_chain",
        expansion = "LEGION",
        timeGate = "none",
        timePerAttempt = 30,
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 1,
        steps = {
            "Find and read all pages of the 'Winding Path' riddle books",
            "Books are in specific locations across Broken Isles and Dalaran",
            "Follow the clues to Forgotten Grotto in Westfall",
            "Interact with the gift - guaranteed mount",
        },
    },
    [242882] = { -- Lucid Nightmare (secret mount, Endless Halls)
        sourceType = "quest_chain",
        expansion = "LEGION",
        timeGate = "none",
        timePerAttempt = 120,
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 1,
        steps = {
            "Complete a series of riddle/puzzle steps across Azeroth",
            "Navigate the Endless Halls maze (Forgotten Crypt)",
            "Match colored orbs to runes in the maze",
            "Guaranteed mount on completion, but maze is RNG-heavy",
        },
    },
    [229376] = { -- Fathom Dweller (Kosumoth world quest chain)
        sourceType = "quest_chain",
        expansion = "LEGION",
        timeGate = "none",
        timePerAttempt = 60,
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 1,
        steps = {
            "Find all 10 Hungering Orbs across Broken Isles",
            "Unlock the Kosumoth the Hungering world quest",
            "Complete Kosumoth world quest when mount is the reward (alternates weekly)",
        },
    },
    [230987] = { -- Arcanist's Manasaber (Suramar questline)
        sourceType = "quest_chain",
        expansion = "LEGION",
        timeGate = "none",
        timePerAttempt = 30,
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 1,
        steps = {
            "Progress Suramar campaign through Insurrection",
            "Complete the full Nightfallen storyline",
            "Reward at end of campaign",
        },
    },

    -- =====================
    -- BFA RAID & DUNGEON
    -- =====================
    [280730] = { -- Sharkbait's Favorite Crackers (Freehold dungeon)
        sourceType = "dungeon_drop",
        expansion = "BFA",
        timeGate = "none",
        timePerAttempt = 5,
        groupRequirement = "solo",
        dropChance = 0.005,
        steps = {
            "Enter Freehold dungeon",
            "Defeat Harlan Sweete (final boss)",
            "~0.5% drop chance, farmable on Normal",
        },
    },
    [294143] = { -- Glacial Tidestorm (Jaina Mythic, BoD)
        sourceType = "raid_drop",
        expansion = "BFA",
        timeGate = "weekly",
        timePerAttempt = 25,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Battle of Dazar'alor",
        difficultyID = 16,
        steps = {
            "Enter Battle of Dazar'alor on Mythic",
            "Clear to Lady Jaina Proudmoore",
            "Defeat Jaina - ~1% drop chance",
        },
    },
    [288722] = { -- Ny'alotha Allseer (N'Zoth, Ny'alotha)
        sourceType = "raid_drop",
        expansion = "BFA",
        timeGate = "weekly",
        timePerAttempt = 25,
        groupRequirement = "small",
        dropChance = 0.01,
        lockoutInstanceName = "Ny'alotha, the Waking City",
        difficultyID = 16,
        steps = {
            "Enter Ny'alotha on Mythic",
            "Clear to N'Zoth the Corruptor",
            "Defeat N'Zoth - ~1% drop (may need small group)",
        },
    },

    -- =====================
    -- SHADOWLANDS RAID & DUNGEON
    -- =====================
    [332905] = { -- Cartel Master's Gearglider (So'leah, Tazavesh)
        sourceType = "dungeon_drop",
        expansion = "SL",
        timeGate = "none",
        timePerAttempt = 8,
        groupRequirement = "solo",
        dropChance = 0.005,
        steps = {
            "Enter Tazavesh: So'leah's Gambit (Mythic/Heroic)",
            "Defeat So'leah - ~0.5% drop chance",
        },
    },
    [344228] = { -- Vengeance (Sire Denathrius Mythic, Castle Nathria)
        sourceType = "raid_drop",
        expansion = "SL",
        timeGate = "weekly",
        timePerAttempt = 25,
        groupRequirement = "small",
        dropChance = 0.01,
        lockoutInstanceName = "Castle Nathria",
        difficultyID = 16,
        steps = {
            "Enter Castle Nathria on Mythic",
            "Clear to Sire Denathrius",
            "Defeat Sire Denathrius - ~1% drop (may need group)",
        },
    },
    [354354] = { -- Carcinized Zerethsteed (Sepulcher of the First Ones)
        sourceType = "raid_drop",
        expansion = "SL",
        timeGate = "weekly",
        timePerAttempt = 25,
        groupRequirement = "small",
        dropChance = 0.01,
        lockoutInstanceName = "Sepulcher of the First Ones",
        difficultyID = 16,
        steps = {
            "Enter Sepulcher of the First Ones on Mythic",
            "Defeat The Jailer",
            "~1% drop chance",
        },
    },

    -- =====================
    -- DRAGONFLIGHT RAID & DUNGEON
    -- =====================
    [376878] = { -- Magmorax (Aberrus mount)
        sourceType = "raid_drop",
        expansion = "DF",
        timeGate = "weekly",
        timePerAttempt = 25,
        groupRequirement = "small",
        dropChance = 0.01,
        lockoutInstanceName = "Aberrus, the Shadowed Crucible",
        difficultyID = 16,
        steps = {
            "Enter Aberrus on Mythic",
            "Defeat Scalecommander Sarkareth",
            "~1% drop chance (current content, need group)",
        },
    },
    [394209] = { -- Renewed Proto-Drake: Embodiment of the Hellforged
        sourceType = "raid_drop",
        expansion = "DF",
        timeGate = "weekly",
        timePerAttempt = 30,
        groupRequirement = "small",
        dropChance = 0.01,
        lockoutInstanceName = "Amirdrassil, the Dream's Hope",
        difficultyID = 16,
        steps = {
            "Enter Amirdrassil on Mythic",
            "Defeat Fyrakk the Blazing",
            "~1% drop chance",
        },
    },

    -- =====================
    -- CLASSIC WORLD DROPS
    -- =====================
    [26656] = { -- Black Qiraji Battle Tank (AQ opening event)
        sourceType = "promotion",
        expansion = "CLASSIC",
        timeGate = "none",
        timePerAttempt = 0,
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 0,
        steps = {
            "No longer obtainable (AQ gate opening event, 2006)",
        },
    },

    -- =====================
    -- REPUTATION MOUNTS (POPULAR)
    -- =====================
    [61996] = { -- Blue Dragonhawk (100 mounts achievement)
        sourceType = "achievement",
        expansion = "WOTLK",
        timeGate = "none",
        timePerAttempt = 0,
        groupRequirement = "solo",
        dropChance = nil,
        achievementID = 2143,
        steps = {
            "Collect 100 mounts on one character",
            "Achievement: Leading the Cavalry",
        },
    },
    [44317] = { -- Cenarion War Hippogryph (Cenarion Expedition)
        sourceType = "reputation",
        expansion = "TBC",
        timeGate = "none",
        timePerAttempt = 30,
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 8,
        factionID = 942,
        targetStanding = 8,
        steps = {
            "Farm Cenarion Expedition reputation in TBC dungeons/quests",
            "Reach Exalted with Cenarion Expedition",
            "Purchase from vendor in Zangarmarsh",
        },
    },
    [93326] = { -- Sandstone Drake (Alchemy crafted)
        sourceType = "profession",
        expansion = "CATA",
        timeGate = "none",
        timePerAttempt = 300,
        groupRequirement = "solo",
        dropChance = nil,
        expectedAttempts = 1,
        steps = {
            "Learn Alchemy recipe from Canopic Jars (Archaeology)",
            "Craft Vial of the Sands (expensive materials)",
            "Or purchase from AH (~30-80k gold typically)",
        },
    },

    -- =====================
    -- ME-B: WELL-KNOWN GUARANTEED / HIGH-RATE DROP MOUNTS
    -- These are mechanically guaranteed (or near-so) but have no data from automated sources.
    -- =====================

    [43951] = { -- Bronze Drake (Culling of Stratholme timed run)
        sourceType = "dungeon_drop",
        expansion = "WOTLK",
        timeGate = "none",  -- Normal mode is farmable with resets
        timePerAttempt = 15,
        groupRequirement = "solo",
        dropChance = 1.0,   -- 100% guaranteed if you beat the timed run
        lockoutInstanceName = "Stratholme",
        steps = {
            "Enter The Culling of Stratholme (Caverns of Time) on any difficulty",
            "Complete the dungeon within the timed run (~25 min)",
            "Chromie rewards Bronze Drake — 100% guaranteed for completing timed run",
            "Farmable: reset Normal mode and repeat (up to 10/hour)",
        },
    },
    [59569] = { -- Twilight Drake (Obsidian Sanctum 3 Drakes alive, 25-man)
        sourceType = "raid_drop",
        expansion = "WOTLK",
        timeGate = "weekly",
        timePerAttempt = 5,
        groupRequirement = "solo",
        dropChance = 1.0,   -- 100% guaranteed when 3 drakes are left alive
        lockoutInstanceName = "Obsidian Sanctum",
        difficultyID = 4,
        steps = {
            "Enter Obsidian Sanctum 25-player Normal",
            "Leave all 3 drakes (Shadron, Tenebron, Vesperon) alive",
            "Defeat Sartharion with 3 drakes — Twilight Drake is guaranteed",
        },
    },
    [59650] = { -- Black Drake (Obsidian Sanctum 3 Drakes alive, 10-man)
        sourceType = "raid_drop",
        expansion = "WOTLK",
        timeGate = "weekly",
        timePerAttempt = 5,
        groupRequirement = "solo",
        dropChance = 1.0,   -- 100% guaranteed when 3 drakes are left alive
        lockoutInstanceName = "Obsidian Sanctum",
        difficultyID = 3,
        steps = {
            "Enter Obsidian Sanctum 10-player Normal",
            "Leave all 3 drakes (Shadron, Tenebron, Vesperon) alive",
            "Defeat Sartharion with 3 drakes — Black Drake is guaranteed",
        },
    },
    [98204] = { -- Amani Battle Bear (Zul'Aman timed run, Heroic)
        sourceType = "dungeon_drop",
        expansion = "CATA",
        timeGate = "daily",
        timePerAttempt = 20,
        groupRequirement = "solo",
        dropChance = 1.0,   -- 100% guaranteed if you rescue all 4 sacrifices before final boss
        lockoutInstanceName = "Zul'Aman",
        difficultyID = 2,
        steps = {
            "Enter Zul'Aman on Heroic difficulty",
            "Race through the timed rescue event",
            "Rescue all 4 captives before Zul'jin resets the timer",
            "Amani Battle Bear is guaranteed in the final chest",
        },
    },
    [171851] = { -- Garn Nighthowl (Nok-Karosh world boss, WoD)
        sourceType = "world_drop",
        expansion = "WOD",
        timeGate = "weekly",
        timePerAttempt = 5,
        groupRequirement = "solo",
        dropChance = 1.0,   -- 100% guaranteed drop from Nok-Karosh
        steps = {
            "Locate Nok-Karosh (rare wolf NPC) in Frostfire Ridge",
            "Defeat Nok-Karosh — Garn Nighthowl is a guaranteed drop",
            "Weekly lockout per character",
        },
    },

    -- =====================
    -- ME-B: POPULAR RAID DROPS WITH KNOWN RATES (from community data mining)
    -- =====================
    [107531] = { -- Clutch of Ji-Kun (Throne of Thunder)
        sourceType = "raid_drop",
        expansion = "MOP",
        timeGate = "weekly",
        timePerAttempt = 20,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Throne of Thunder",
        difficultyID = 6,
        steps = {
            "Enter Throne of Thunder on Heroic 25",
            "Defeat Ji-Kun — ~1% drop chance",
        },
    },
    [308786] = { -- Ny'alotha Allseer (N'Zoth Mythic, Ny'alotha)
        sourceType = "raid_drop",
        expansion = "BFA",
        timeGate = "weekly",
        timePerAttempt = 30,
        groupRequirement = "small",
        dropChance = 0.01,
        lockoutInstanceName = "Ny'alotha, the Waking City",
        difficultyID = 16,
        steps = {
            "Enter Ny'alotha, the Waking City on Mythic",
            "Clear to N'Zoth the Corruptor",
            "Defeat N'Zoth — ~1% drop chance (may need small group)",
        },
    },
    [335566] = { -- Marrowfang (Theater of Pain)
        sourceType = "dungeon_drop",
        expansion = "SL",
        timeGate = "none",
        timePerAttempt = 10,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Theater of Pain",
        steps = {
            "Enter Theater of Pain (Normal — farmable, no Heroic lockout restriction)",
            "Defeat An Affront of Challengers",
            "~1% drop chance",
        },
    },
    [413933] = { -- Anu'relos, Flame's Guidance (Amirdrassil Fyrakk Mythic)
        sourceType = "raid_drop",
        expansion = "DF",
        timeGate = "weekly",
        timePerAttempt = 30,
        groupRequirement = "small",
        dropChance = 0.01,
        lockoutInstanceName = "Amirdrassil, the Dream's Hope",
        difficultyID = 16,
        steps = {
            "Enter Amirdrassil, the Dream's Hope on Mythic",
            "Clear to Fyrakk the Blazing",
            "Defeat Fyrakk — ~1% drop chance",
        },
    },
    [451939] = { -- Sureki Skyrazor (Nerub-ar Palace Mythic)
        sourceType = "raid_drop",
        expansion = "TWW",
        timeGate = "weekly",
        timePerAttempt = 30,
        groupRequirement = "small",
        dropChance = 0.01,
        lockoutInstanceName = "Nerub-ar Palace",
        difficultyID = 16,
        steps = {
            "Enter Nerub-ar Palace on Mythic",
            "Clear to Queen Ansurek",
            "Defeat Queen Ansurek — ~1% drop chance",
        },
    },
    [267319] = { -- Underrot Crawg (Underrot dungeon)
        sourceType = "dungeon_drop",
        expansion = "BFA",
        timeGate = "none",
        timePerAttempt = 8,
        groupRequirement = "solo",
        dropChance = 0.03,
        lockoutInstanceName = "The Underrot",
        steps = {
            "Enter The Underrot on Normal (farmable with resets)",
            "Defeat Unbound Abomination (final boss) — ~3% drop chance",
        },
    },
    [273012] = { -- G.M.O.D. (King Mechagon / Operation Mechagon)
        sourceType = "dungeon_drop",
        expansion = "BFA",
        timeGate = "none",
        timePerAttempt = 20,
        groupRequirement = "solo",
        dropChance = 0.01,
        lockoutInstanceName = "Operation: Mechagon",
        steps = {
            "Enter Operation: Mechagon on Mythic (farmable — Mythic only, no weekly lockout on this dungeon)",
            "Defeat HK-8 Aerial Oppression Unit or King Mechagon",
            "~1% drop chance from HK-8 or final boss chest",
        },
    },
    [290467] = { -- Aerial Unit R-21/X (Mechagon workshop rare)
        sourceType = "world_drop",
        expansion = "BFA",
        timeGate = "none",
        timePerAttempt = 30,
        groupRequirement = "solo",
        dropChance = 0.01,
        steps = {
            "Farm rares in Mechagon (multiple unique rares drop this)",
            "Spawns on Mechagon Island — ~1% from rare mobs",
            "Check kill list on WoWHead for which rares can drop it",
        },
    },
}


-- Helper: get metadata for a mount by spellID
function FB.MountDB:Get(spellID)
    return self.entries[spellID]
end

-- Get all mount entries
function FB.MountDB:GetAll()
    return self.entries
end

-- Count entries
function FB.MountDB:GetCount()
    local count = 0
    for _ in pairs(self.entries) do
        count = count + 1
    end
    return count
end
