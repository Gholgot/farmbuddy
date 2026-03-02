local addonName, FB = ...

--[[
    FIX-8B: Curated daily reputation rates per faction.
    Maps factionID → { dailyRep, weeklyRep, method, expansion }

    dailyRep:  average rep earnable per day from all available sources
    weeklyRep: bonus weekly rep (world quests, weekly quests, etc.)
    method:    "daily" (old rep), "renown" (modern), "tabard" (grindable in dungeons), "one-time" (quest chain only)
    expansion: expansion key for age-based fallbacks

    Covers factions that gate mount purchases (~80 factions).
]]

FB.ReputationData = {
    -- ===========================
    -- CLASSIC
    -- ===========================
    -- (No mount-gating factions in Classic that use standard rep)

    -- ===========================
    -- THE BURNING CRUSADE
    -- ===========================
    [932]  = { name = "The Aldor",              dailyRep = 1200, weeklyRep = 0,    method = "daily",  expansion = "TBC" },
    [934]  = { name = "The Scryers",            dailyRep = 1200, weeklyRep = 0,    method = "daily",  expansion = "TBC" },
    [933]  = { name = "The Consortium",         dailyRep = 1000, weeklyRep = 0,    method = "daily",  expansion = "TBC" },
    [942]  = { name = "Cenarion Expedition",    dailyRep = 2000, weeklyRep = 0,    method = "tabard", expansion = "TBC" },
    [946]  = { name = "Honor Hold",             dailyRep = 2000, weeklyRep = 0,    method = "tabard", expansion = "TBC" },
    [947]  = { name = "Thrallmar",              dailyRep = 2000, weeklyRep = 0,    method = "tabard", expansion = "TBC" },
    [978]  = { name = "Kurenai",                dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "TBC" },
    [941]  = { name = "The Mag'har",            dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "TBC" },
    [1031] = { name = "Sha'tari Skyguard",      dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "TBC" },
    [970]  = { name = "Sporeggar",              dailyRep = 750,  weeklyRep = 0,    method = "daily",  expansion = "TBC" },
    [967]  = { name = "The Violet Eye",         dailyRep = 2500, weeklyRep = 0,    method = "tabard", expansion = "TBC" },
    [1015] = { name = "Netherwing",             dailyRep = 2000, weeklyRep = 0,    method = "daily",  expansion = "TBC" },

    -- ===========================
    -- WRATH OF THE LICH KING
    -- ===========================
    [1090] = { name = "Kirin Tor",              dailyRep = 3000, weeklyRep = 0,    method = "tabard", expansion = "WOTLK" },
    [1091] = { name = "The Wyrmrest Accord",    dailyRep = 3000, weeklyRep = 0,    method = "tabard", expansion = "WOTLK" },
    [1098] = { name = "Knights of the Ebon Blade", dailyRep = 3000, weeklyRep = 0, method = "tabard", expansion = "WOTLK" },
    [1106] = { name = "Argent Crusade",         dailyRep = 3000, weeklyRep = 0,    method = "tabard", expansion = "WOTLK" },
    [1073] = { name = "The Kalu'ak",            dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "WOTLK" },
    [1105] = { name = "The Oracles",            dailyRep = 1200, weeklyRep = 0,    method = "daily",  expansion = "WOTLK" },
    [1119] = { name = "The Sons of Hodir",      dailyRep = 1800, weeklyRep = 0,    method = "daily",  expansion = "WOTLK" },
    [1156] = { name = "The Ashen Verdict",      dailyRep = 3500, weeklyRep = 0,    method = "tabard", expansion = "WOTLK" },

    -- ===========================
    -- CATACLYSM
    -- ===========================
    [1173] = { name = "Ramkahen",               dailyRep = 3000, weeklyRep = 0,    method = "tabard", expansion = "CATA" },
    [1171] = { name = "Therazane",              dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "CATA" },
    [1174] = { name = "Wildhammer Clan",        dailyRep = 3000, weeklyRep = 0,    method = "tabard", expansion = "CATA" },
    [1172] = { name = "Dragonmaw Clan",         dailyRep = 3000, weeklyRep = 0,    method = "tabard", expansion = "CATA" },
    [1177] = { name = "Baradin's Wardens",      dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "CATA" },
    [1178] = { name = "Hellscream's Reach",     dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "CATA" },

    -- ===========================
    -- MISTS OF PANDARIA
    -- ===========================
    [1302] = { name = "The Anglers",            dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "MOP" },
    [1281] = { name = "The Order of the Cloud Serpent", dailyRep = 2000, weeklyRep = 0, method = "daily", expansion = "MOP" },
    [1341] = { name = "The August Celestials",  dailyRep = 1100, weeklyRep = 0,    method = "daily",  expansion = "MOP" },
    [1269] = { name = "Golden Lotus",           dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "MOP" },
    [1337] = { name = "The Klaxxi",             dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "MOP" },
    [1271] = { name = "Shado-Pan",              dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "MOP" },
    [1345] = { name = "The Lorewalkers",        dailyRep = 0,    weeklyRep = 0,    method = "one-time", expansion = "MOP" },
    [1388] = { name = "Dominance Offensive",    dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "MOP" },
    [1387] = { name = "Operation: Shieldwall",  dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "MOP" },
    [1435] = { name = "Shado-Pan Assault",      dailyRep = 2000, weeklyRep = 0,    method = "tabard", expansion = "MOP" },
    [1492] = { name = "Emperor Shaohao",        dailyRep = 2000, weeklyRep = 0,    method = "daily",  expansion = "MOP" },

    -- ===========================
    -- WARLORDS OF DRAENOR
    -- ===========================
    [1708] = { name = "Laughing Skull Orcs",    dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "WOD" },
    [1710] = { name = "Sha'tari Defense",       dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "WOD" },
    [1711] = { name = "Steamwheedle Preservation Society", dailyRep = 1000, weeklyRep = 0, method = "daily", expansion = "WOD" },
    [1731] = { name = "Council of Exarchs",     dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "WOD" },
    [1445] = { name = "Frostwolf Orcs",         dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "WOD" },
    [1681] = { name = "Vol'jin's Spear",        dailyRep = 1000, weeklyRep = 0,    method = "daily",  expansion = "WOD" },
    [1682] = { name = "Wrynn's Vanguard",       dailyRep = 1000, weeklyRep = 0,    method = "daily",  expansion = "WOD" },
    [1849] = { name = "Order of the Awakened",  dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "WOD" },
    [1850] = { name = "The Saberstalkers",      dailyRep = 2000, weeklyRep = 0,    method = "daily",  expansion = "WOD" },

    -- ===========================
    -- LEGION
    -- ===========================
    [1859] = { name = "The Nightfallen",        dailyRep = 1200, weeklyRep = 0,    method = "daily",  expansion = "LEGION" },
    [1883] = { name = "Dreamweavers",           dailyRep = 2500, weeklyRep = 0,    method = "tabard", expansion = "LEGION" },
    [1828] = { name = "Highmountain Tribe",     dailyRep = 2500, weeklyRep = 0,    method = "tabard", expansion = "LEGION" },
    [1900] = { name = "Court of Farondis",      dailyRep = 2500, weeklyRep = 0,    method = "tabard", expansion = "LEGION" },
    [1948] = { name = "Valarjar",               dailyRep = 2500, weeklyRep = 0,    method = "tabard", expansion = "LEGION" },
    [2045] = { name = "Armies of Legionfall",   dailyRep = 1500, weeklyRep = 0,    method = "daily",  expansion = "LEGION" },
    [2165] = { name = "Army of the Light",      dailyRep = 1200, weeklyRep = 0,    method = "daily",  expansion = "LEGION" },
    [2170] = { name = "Argussian Reach",        dailyRep = 1200, weeklyRep = 0,    method = "daily",  expansion = "LEGION" },

    -- ===========================
    -- BATTLE FOR AZEROTH
    -- ===========================
    [2103] = { name = "Zandalari Empire",       dailyRep = 1000, weeklyRep = 1500, method = "daily",  expansion = "BFA" },
    [2156] = { name = "Talanji's Expedition",   dailyRep = 1000, weeklyRep = 1500, method = "daily",  expansion = "BFA" },
    [2157] = { name = "The Honorbound",         dailyRep = 1000, weeklyRep = 1500, method = "daily",  expansion = "BFA" },
    [2158] = { name = "Voldunai",               dailyRep = 1000, weeklyRep = 1500, method = "daily",  expansion = "BFA" },
    [2159] = { name = "7th Legion",             dailyRep = 1000, weeklyRep = 1500, method = "daily",  expansion = "BFA" },
    [2160] = { name = "Proudmoore Admiralty",   dailyRep = 1000, weeklyRep = 1500, method = "daily",  expansion = "BFA" },
    [2161] = { name = "Order of Embers",        dailyRep = 1000, weeklyRep = 1500, method = "daily",  expansion = "BFA" },
    [2162] = { name = "Storm's Wake",           dailyRep = 1000, weeklyRep = 1500, method = "daily",  expansion = "BFA" },
    [2163] = { name = "Tortollan Seekers",      dailyRep = 800,  weeklyRep = 1000, method = "daily",  expansion = "BFA" },
    [2400] = { name = "Waveblade Ankoan",       dailyRep = 800,  weeklyRep = 0,    method = "daily",  expansion = "BFA" },
    [2373] = { name = "The Unshackled",         dailyRep = 800,  weeklyRep = 0,    method = "daily",  expansion = "BFA" },
    [2415] = { name = "Rajani",                 dailyRep = 1200, weeklyRep = 0,    method = "daily",  expansion = "BFA" },
    [2417] = { name = "Uldum Accord",           dailyRep = 1200, weeklyRep = 0,    method = "daily",  expansion = "BFA" },

    -- ===========================
    -- SHADOWLANDS
    -- ===========================
    [2407] = { name = "The Ascended",           dailyRep = 800,  weeklyRep = 1500, method = "daily",  expansion = "SL" },
    [2410] = { name = "The Undying Army",       dailyRep = 800,  weeklyRep = 1500, method = "daily",  expansion = "SL" },
    [2413] = { name = "Court of Harvesters",    dailyRep = 800,  weeklyRep = 1500, method = "daily",  expansion = "SL" },
    [2432] = { name = "Ve'nari",                dailyRep = 600,  weeklyRep = 1000, method = "daily",  expansion = "SL" },
    [2465] = { name = "The Wild Hunt",          dailyRep = 800,  weeklyRep = 1500, method = "daily",  expansion = "SL" },
    [2470] = { name = "Death's Advance",        dailyRep = 1000, weeklyRep = 1500, method = "daily",  expansion = "SL" },
    [2472] = { name = "The Archivists' Codex",  dailyRep = 800,  weeklyRep = 1200, method = "daily",  expansion = "SL" },
    [2478] = { name = "The Enlightened",        dailyRep = 600,  weeklyRep = 1500, method = "daily",  expansion = "SL" },

    -- ===========================
    -- DRAGONFLIGHT (Renown-based)
    -- ===========================
    [2503] = { name = "Maruuk Centaur",         dailyRep = 500,  weeklyRep = 2500, method = "renown", expansion = "DF" },
    [2507] = { name = "Dragonscale Expedition", dailyRep = 500,  weeklyRep = 2500, method = "renown", expansion = "DF" },
    [2510] = { name = "Valdrakken Accord",      dailyRep = 500,  weeklyRep = 2500, method = "renown", expansion = "DF" },
    [2511] = { name = "Iskaara Tuskarr",        dailyRep = 500,  weeklyRep = 2500, method = "renown", expansion = "DF" },
    [2564] = { name = "Loamm Niffen",           dailyRep = 400,  weeklyRep = 2000, method = "renown", expansion = "DF" },
    [2574] = { name = "Dream Wardens",          dailyRep = 400,  weeklyRep = 2000, method = "renown", expansion = "DF" },

    -- ===========================
    -- THE WAR WITHIN (Renown-based)
    -- ===========================
    [2590] = { name = "Council of Dornogal",    dailyRep = 400,  weeklyRep = 2500, method = "renown", expansion = "TWW" },
    [2594] = { name = "The Assembly of the Deeps", dailyRep = 400, weeklyRep = 2500, method = "renown", expansion = "TWW" },
    [2600] = { name = "Hallowfall Arathi",      dailyRep = 400,  weeklyRep = 2500, method = "renown", expansion = "TWW" },
    [2601] = { name = "The Severed Threads",    dailyRep = 400,  weeklyRep = 2500, method = "renown", expansion = "TWW" },
    -- FEAT-8: TWW Season 2 — The Cartels of Undermine gate mount purchases in patch 11.1
    [2605] = { name = "The Cartels of Undermine", dailyRep = 400, weeklyRep = 2500, method = "renown", expansion = "TWW" },
}
