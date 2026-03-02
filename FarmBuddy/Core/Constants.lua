local addonName, FB = ...

FB.ADDON_COLOR = "|cFF00CCFF"
FB.ADDON_PREFIX = FB.ADDON_COLOR .. "FarmBuddy|r: "

-- Source types for mounts
FB.SOURCE_TYPES = {
    RAID_DROP       = "raid_drop",
    DUNGEON_DROP    = "dungeon_drop",
    WORLD_DROP      = "world_drop",
    WORLD_BOSS      = "world_boss",
    REPUTATION      = "reputation",
    CURRENCY        = "currency",
    QUEST_CHAIN     = "quest_chain",
    ACHIEVEMENT     = "achievement",
    PROFESSION      = "profession",
    PVP             = "pvp",
    EVENT           = "event",
    VENDOR          = "vendor",
    TRADING_POST    = "trading_post",
    BLIZZARD_SHOP   = "blizzard_shop",
    TCG             = "tcg",
    RECRUIT         = "recruit_a_friend",
    PROMOTION       = "promotion",
    UNKNOWN         = "unknown",
}

-- Display names for source types
FB.SOURCE_TYPE_NAMES = {
    raid_drop       = "Raid Drop",
    dungeon_drop    = "Dungeon Drop",
    world_drop      = "World Drop",
    world_boss      = "World Boss",
    reputation      = "Reputation",
    currency        = "Currency",
    quest_chain     = "Quest Chain",
    achievement     = "Achievement",
    profession      = "Profession",
    pvp             = "PvP",
    event           = "World Event",
    vendor          = "Vendor",
    trading_post    = "Trading Post",
    blizzard_shop   = "Blizzard Shop",
    tcg             = "Trading Card",
    recruit_a_friend = "Recruit-a-Friend",
    promotion       = "Promotion",
    unknown         = "Unknown",
}

-- Time-gate types
FB.TIME_GATES = {
    NONE    = "none",
    DAILY   = "daily",
    WEEKLY  = "weekly",
    BIWEEKLY = "biweekly",
    MONTHLY = "monthly",
    YEARLY  = "yearly",
}

-- Time-gate factors (days between attempts)
FB.TIME_GATE_FACTORS = {
    none     = 0,
    daily    = 1,
    weekly   = 7,
    biweekly = 14,
    monthly  = 30,
    yearly   = 365,
}

-- Group requirement levels
FB.GROUP_SIZES = {
    SOLO    = "solo",
    DUO     = "duo",
    SMALL   = "small",      -- 3-5 players
    FULL    = "full",       -- 10-20 players
    MYTHIC  = "mythic",     -- 20 organized
}

-- Group difficulty factors (multiplier)
FB.GROUP_FACTORS = {
    solo    = 1.0,
    duo     = 1.3,
    small   = 2.0,
    full    = 3.5,
    raid    = 3.5,   -- Same as full; used by generated DB for current-expansion raids
    mythic  = 5.0,
}

-- Group display names
FB.GROUP_NAMES = {
    solo    = "Solo",
    duo     = "2 Players",
    small   = "Small Group (3-5)",
    full    = "Full Group (10-20)",
    raid    = "Raid Group (10-20)",
    mythic  = "Mythic (20)",
}

-- Expansion keys
FB.EXPANSIONS = {
    CLASSIC  = "CLASSIC",
    TBC      = "TBC",
    WOTLK    = "WOTLK",
    CATA     = "CATA",
    MOP      = "MOP",
    WOD      = "WOD",
    LEGION   = "LEGION",
    BFA      = "BFA",
    SL       = "SL",
    DF       = "DF",
    TWW      = "TWW",
    MIDNIGHT = "MIDNIGHT",
}

FB.EXPANSION_NAMES = {
    CLASSIC  = "Classic",
    TBC      = "The Burning Crusade",
    WOTLK    = "Wrath of the Lich King",
    CATA     = "Cataclysm",
    MOP      = "Mists of Pandaria",
    WOD      = "Warlords of Draenor",
    LEGION   = "Legion",
    BFA      = "Battle for Azeroth",
    SL       = "Shadowlands",
    DF       = "Dragonflight",
    TWW      = "The War Within",
    MIDNIGHT = "Midnight",
}

-- Achievement reward types
FB.REWARD_TYPES = {
    MOUNT   = "mount",
    TITLE   = "title",
    PET     = "pet",
    TRANSMOG = "transmog",
    TOY     = "toy",
    NONE    = "none",
}

-- Tab indices
FB.TABS = {
    MOUNT_SEARCH       = 1,
    MOUNT_RECOMMEND    = 2,
    SESSION            = 3,
    ACHIEVEMENTS       = 4,
    WEEKLY             = 5,
    EXPANSION_PROGRESS = 6,
    SETTINGS           = 7,
}

FB.TAB_NAMES = {
    "Mount Search",
    "Recommendations",
    "Session Planner",
    "Achievements",
    "Weekly Tracker",
    "Expansion",
    "Settings",
}

-- Colors
FB.COLORS = {
    GREEN   = "|cFF00FF00",
    RED     = "|cFFFF0000",
    YELLOW  = "|cFFFFFF00",
    ORANGE  = "|cFFFF8800",
    BLUE    = "|cFF00CCFF",
    WHITE   = "|cFFFFFFFF",
    GRAY    = "|cFF888888",
    GOLD    = "|cFFFFD200",
}

-- FIX-14: Confidence level colors
-- Thresholds set in MountResolver.lua uncurated confidence block: >=70% high, >=40% medium, <40% low
FB.CONFIDENCE_COLORS = {
    high   = "|cFF00FF00",  -- Green (≥70%)
    medium = "|cFFFFFF00",  -- Yellow (≥40%)
    low    = "|cFFFF8800",  -- Orange (<40%)
}

-- Source types that involve random drops (used for scoring and display)
-- Defined here to avoid duplication between ScoringEngine.lua and Utils.lua
FB.DROP_SOURCE_TYPES = {
    raid_drop = true, dungeon_drop = true, world_drop = true,
    world_boss = true, event = true,
}

-- Class colors (for weekly tracker)
FB.CLASS_COLORS = {
    WARRIOR     = "C69B6D",
    PALADIN     = "F48CBA",
    HUNTER      = "AAD372",
    ROGUE       = "FFF468",
    PRIEST      = "FFFFFF",
    DEATHKNIGHT = "C41E3A",
    SHAMAN      = "0070DD",
    MAGE        = "3FC7EB",
    WARLOCK     = "8788EE",
    MONK        = "00FF98",
    DRUID       = "FF7C0A",
    DEMONHUNTER = "A330C9",
    EVOKER      = "33937F",
}
