#!/usr/bin/env python3
"""
FarmBuddy Mount Database Generator

Fetches mount data from 4 sources and generates a comprehensive Lua data file:
1. wago.tools    - Complete mount index (CSV, no auth)
2. Blizzard API  - Authoritative source types per mount
3. Rarity Addon  - Drop rates, NPC IDs, item IDs (open source)
4. Data for Azeroth - Player ownership rarity %

Usage:
    pip install -r requirements.txt
    python build_mountdb.py

Output:
    ../Data/MountDB_Generated.lua
"""

import csv
import io
import json
import math
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import requests
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

load_dotenv(Path(__file__).parent / ".env")

BLIZZARD_CLIENT_ID = os.getenv("BLIZZARD_CLIENT_ID", "")
BLIZZARD_CLIENT_SECRET = os.getenv("BLIZZARD_CLIENT_SECRET", "")
BLIZZARD_REGION = os.getenv("BLIZZARD_REGION", "eu")

CACHE_DIR = Path(__file__).parent / ".cache"
OUTPUT_FILE = Path(__file__).parent.parent / "Data" / "MountDB_Generated.lua"

# Rarity addon mount DB files on GitHub (raw)
RARITY_BASE_URL = "https://raw.githubusercontent.com/WowRarity/Rarity/master/DB/Mounts"
RARITY_FILES = [
    "Classic.lua",
    "TheBurningCrusade.lua",
    "WrathOfTheLichKing.lua",
    "Cataclysm.lua",
    "MistsOfPandaria.lua",
    "WarlordsOfDraenor.lua",
    "Legion.lua",
    "BattleForAzeroth.lua",
    "Shadowlands.lua",
    "Dragonflight.lua",
    "TheWarWithin.lua",
    "Midnight.lua",
    "HolidayEvents_TheBurningCrusade.lua",
    "HolidayEvents_WrathOfTheLichKing.lua",
    "HolidayEvents_WarlordsOfDraenor.lua",
    "HolidayEvents_Dragonflight.lua",
    "HolidayEvents_TheWarWithin.lua",
]

# Map Rarity file names to FarmBuddy expansion codes
RARITY_FILE_TO_EXPANSION = {
    "Classic.lua": "CLASSIC",
    "TheBurningCrusade.lua": "TBC",
    "WrathOfTheLichKing.lua": "WOTLK",
    "Cataclysm.lua": "CATA",
    "MistsOfPandaria.lua": "MOP",
    "WarlordsOfDraenor.lua": "WOD",
    "Legion.lua": "LEGION",
    "BattleForAzeroth.lua": "BFA",
    "Shadowlands.lua": "SL",
    "Dragonflight.lua": "DF",
    "TheWarWithin.lua": "TWW",
    "Midnight.lua": "MIDNIGHT",
    # Holiday events inherit expansion from their file name
    "HolidayEvents_TheBurningCrusade.lua": "TBC",
    "HolidayEvents_WrathOfTheLichKing.lua": "WOTLK",
    "HolidayEvents_WarlordsOfDraenor.lua": "WOD",
    "HolidayEvents_Dragonflight.lua": "DF",
    "HolidayEvents_TheWarWithin.lua": "TWW",
}

# Map Blizzard API source.type to FarmBuddy internal sourceType
BLIZZARD_SOURCE_MAP = {
    "DROP": "raid_drop",  # refined later by instance type
    "QUEST": "quest_chain",
    "VENDOR": "vendor",
    "PROFESSION": "profession",
    "ACHIEVEMENT": "achievement",
    "WORLD_EVENT": "event",
    "DISCOVERY": "world_drop",
    "TRADING_POST": "trading_post",
    "PROMOTION": "promotion",
    "PET_STORE": "promotion",
    "IN_GAME_SHOP": "promotion",
    "TCG": "promotion",
}

# Map Rarity method constants to FarmBuddy types
RARITY_METHOD_MAP = {
    "NPC": "world_drop",
    "BOSS": "raid_drop",
    "ZONE": "world_drop",
    "USE": "world_drop",
    "FISHING": "profession",
    "SPECIAL": "world_drop",
    "COLLECTION": "achievement",
}

# Expansion age for time-per-attempt estimates
EXPANSION_INDEX = {
    "CLASSIC": 0, "TBC": 1, "WOTLK": 2, "CATA": 3, "MOP": 4,
    "WOD": 5, "LEGION": 6, "BFA": 7, "SL": 8, "DF": 9, "TWW": 10,
    "MIDNIGHT": 11,
}
CURRENT_EXPANSION = 11  # Midnight

# Map Rarity CONSTANTS.INSTANCE_DIFFICULTIES keys to numeric IDs
RARITY_DIFFICULTY_MAP = {
    "HEROIC_DUNGEON": 2,
    "RAID_10_NORMAL": 3,
    "RAID_25_NORMAL": 4,
    "RAID_10_HEROIC": 5,
    "RAID_25_HEROIC": 6,
    "NORMAL_RAID": 14,
    "HEROIC_RAID": 15,
    "MYTHIC_RAID": 16,
    "LFR": 17,
    "MYTHIC_DUNGEON": 23,
    "TIMEWALKING_DUNGEON": 24,
    "NONE": 0,
}

# SpellID ranges for expansion inference (monotonically increasing)
SPELL_ID_EXPANSION_RANGES = [
    (0, 18000, "CLASSIC"),
    (18000, 35000, "TBC"),
    (35000, 75000, "WOTLK"),
    (75000, 125000, "CATA"),
    (125000, 175000, "MOP"),
    (175000, 230000, "WOD"),
    (230000, 275000, "LEGION"),
    (275000, 350000, "BFA"),
    (350000, 380000, "SL"),
    (380000, 420000, "DF"),
    (420000, 500000, "TWW"),
    (500000, 9999999, "MIDNIGHT"),  # Midnight uses high spell IDs (1218xxx+)
]

# Well-known boss → instance name mapping
BOSS_TO_INSTANCE = {
    "The Lich King": "Icecrown Citadel",
    "Arthas": "Icecrown Citadel",
    "Yogg-Saron": "Ulduar",
    "Malygos": "Eye of Eternity",
    "Sartharion": "Obsidian Sanctum",
    "Archavon the Stone Watcher": "Vault of Archavon",
    "Kael'thas Sunstrider": "Tempest Keep",
    "Illidan": "Black Temple",
    "Attumen the Huntsman": "Karazhan",
    "Midnight": "Karazhan",
    "Ragnaros": "Firelands",
    "Alysrazor": "Firelands",
    "Ultraxion": "Dragon Soul",
    "Deathwing": "Dragon Soul",
    "Madness of Deathwing": "Dragon Soul",
    "Al'Akir": "Throne of the Four Winds",
    "Horridon": "Throne of Thunder",
    "Ji-Kun": "Throne of Thunder",
    "Elegon": "Mogu'shan Vaults",
    "Sha of Fear": "Terrace of Endless Spring",
    "Garrosh Hellscream": "Siege of Orgrimmar",
    "Blackhand": "Blackrock Foundry",
    "Archimonde": "Hellfire Citadel",
    "Gul'dan": "The Nighthold",
    "Argus the Unmaker": "Antorus, the Burning Throne",
    "Kil'jaeden": "Tomb of Sargeras",
    "G'huun": "Uldir",
    "Jaina Proudmoore": "Battle of Dazar'alor",
    "Lady Jaina Proudmoore": "Battle of Dazar'alor",
    "N'Zoth the Corruptor": "Ny'alotha, the Waking City",
    "Sire Denathrius": "Castle Nathria",
    "Sylvanas Windrunner": "Sanctum of Domination",
    "The Jailer": "Sepulcher of the First Ones",
    "Raszageth": "Vault of the Incarnates",
    "Sarkareth": "Aberrus, the Shadowed Crucible",
    "Scalecommander Sarkareth": "Aberrus, the Shadowed Crucible",
    "Fyrakk": "Amirdrassil, the Dream's Hope",
    "Queen Ansurek": "Nerub-ar Palace",
    "Skadi the Ruthless": "Utgarde Pinnacle",
    "Anzu": "Sethekk Halls",
    "Baron Rivendare": "Stratholme",
    "Altairus": "Vortex Pinnacle",
    "Slabhide": "Stonecore",
    "Gallywix": "Liberation of Undermine",
    "Mekkatorque": "Battle of Dazar'alor",
    "Nightbane": "Return to Karazhan",
    "HK-8 Aerial Oppression Unit": "Operation: Mechagon",
    "King Mechagon": "Operation: Mechagon",
    "An Affront of Challengers": "Theater of Pain",
    "Bloodlord Mandokir": "Zul'Gurub",
    "Chrome King Gallywix": "Liberation of Undermine",
    "Dimensius": "Liberation of Undermine",
    "High Priestess Kilnara": "Zul'Gurub",
    "Onyxia": "Onyxia's Lair",
    # WOTLK small raids
    "Sartharion": "Obsidian Sanctum",
    "Emalon the Storm Watcher": "Vault of Archavon",
    "Koralon the Flame Watcher": "Vault of Archavon",
    "Toravon the Ice Watcher": "Vault of Archavon",
    "Malygos the Spell-Weaver": "Eye of Eternity",
    # CLASSIC small raids / dungeons
    "Razorgore the Untamed": "Blackwing Lair",
    "Nefarian": "Blackwing Lair",
    "Ragnaros (Molten Core)": "Molten Core",
    "Onyxia (Classic)": "Onyxia's Lair",
    # TBC dungeons / raids
    "Zereketh the Unbound": "Sethekk Halls",
    "Talon King Ikiss": "Sethekk Halls",
    "Kael'thas Sunstrider (MgT)": "Magisters' Terrace",
    "Selin Fireheart": "Magisters' Terrace",
    "Vexallus": "Magisters' Terrace",
    "Priestess Delrissa": "Magisters' Terrace",
    "Gruul": "Gruul's Lair",
    "Maulgar": "Gruul's Lair",
    "Magtheridon": "Magtheridon's Lair",
    # CATA
    "Altairus (Vortex Pinnacle)": "Vortex Pinnacle",
    "Al'Akir (Throne)": "Throne of the Four Winds",
    "Conclave of Wind": "Throne of the Four Winds",
    "Corborus": "Stonecore",
    "Ozruk": "Stonecore",
    "High Priestess Azil": "Stonecore",
    "Occu'thar": "Baradin Hold",
    "Alizabal": "Baradin Hold",
    # MOP
    "Sha of Anger": None,   # world boss, no instance
    "Galleon": None,        # world boss, no instance
    "Nalak": None,          # world boss, no instance
    "Oondasta": None,       # world boss, no instance
    "Elegon (Vaults)": "Mogu'shan Vaults",
    "Will of the Emperor": "Mogu'shan Vaults",
    "Feng the Accursed": "Mogu'shan Vaults",
    "Gara'jal the Spiritbinder": "Mogu'shan Vaults",
    "Imperial Vizier Zor'lok": "Heart of Fear",
    "Blade Lord Ta'yak": "Heart of Fear",
    "Garalon": "Heart of Fear",
    "Wind Lord Mel'jarak": "Heart of Fear",
    "Amber-Shaper Un'sok": "Heart of Fear",
    "Grand Empress Shek'zeer": "Heart of Fear",
    "Protectors of the Endless": "Terrace of Endless Spring",
    "Tsulong": "Terrace of Endless Spring",
    "Lei Shi": "Terrace of Endless Spring",
    # WOD world bosses
    "Rukhmar": None,        # world boss, no instance
    "Drov the Ruiner": None,
    "Tarlna the Ageless": None,
    "Kazzak": None,         # LEGION world boss area but no instance
    # LEGION
    "Xavius": "Emerald Nightmare",
    "Cenarius": "Emerald Nightmare",
    "Il'gynoth, Heart of Corruption": "Emerald Nightmare",
    "Elerethe Renferal": "Emerald Nightmare",
    "Nythendra": "Emerald Nightmare",
    "Ursoc": "Emerald Nightmare",
    "Dragons of Nightmare": "Emerald Nightmare",
    "Skorpyron": "The Nighthold",
    "Chronomatic Anomaly": "The Nighthold",
    "Trilliax": "The Nighthold",
    "Spellblade Aluriel": "The Nighthold",
    "Tichondrius": "The Nighthold",
    "High Botanist Tel'arn": "The Nighthold",
    "Krosus": "The Nighthold",
    "Star Augur Etraeus": "The Nighthold",
    "Grand Magistrix Elisande": "The Nighthold",
    "Goroth": "Tomb of Sargeras",
    "Demonic Inquisition": "Tomb of Sargeras",
    "Harjatan": "Tomb of Sargeras",
    "Mistress Sassz'ine": "Tomb of Sargeras",
    "Sisters of the Moon": "Tomb of Sargeras",
    "The Desolate Host": "Tomb of Sargeras",
    "Maiden of Vigilance": "Tomb of Sargeras",
    "Fallen Avatar": "Tomb of Sargeras",
    "Avatar of Sargeras": "Tomb of Sargeras",
    "Garothi Worldbreaker": "Antorus, the Burning Throne",
    "Felhounds of Sargeras": "Antorus, the Burning Throne",
    "Antoran High Command": "Antorus, the Burning Throne",
    "Portal Keeper Hasabel": "Antorus, the Burning Throne",
    "Eonar the Life-Binder": "Antorus, the Burning Throne",
    "Imonar the Soulhunter": "Antorus, the Burning Throne",
    "Kin'garoth": "Antorus, the Burning Throne",
    "Varimathras": "Antorus, the Burning Throne",
    "The Coven of Shivarra": "Antorus, the Burning Throne",
    "Aggramar": "Antorus, the Burning Throne",
    # BFA
    "MOTHER": "Uldir",
    "Taloc": "Uldir",
    "Vectis": "Uldir",
    "Fetid Devourer": "Uldir",
    "Zek'voz, Herald of N'Zoth": "Uldir",
    "Mythrax the Unraveler": "Uldir",
    "Champion of the Light": "Battle of Dazar'alor",
    "Frida Ironbellows": "Battle of Dazar'alor",
    "Grong, the Jungle Lord": "Battle of Dazar'alor",
    "Jadefire Masters": "Battle of Dazar'alor",
    "High Tinker Mekkatorque": "Battle of Dazar'alor",
    "Stormwall Blockade": "Battle of Dazar'alor",
    "King Rastakhan": "Battle of Dazar'alor",
    "Uu'nat, Harbinger of the Void": "Crucible of Storms",
    "Za'qul, Harbinger of Ny'alotha": "The Eternal Palace",
    "Queen Azshara": "The Eternal Palace",
    "Ra-den the Despoiled": "Ny'alotha, the Waking City",
    "Wrathion, the Black Emperor": "Ny'alotha, the Waking City",
    "Maut": "Ny'alotha, the Waking City",
    "The Prophet Skitra": "Ny'alotha, the Waking City",
    "Dark Inquisitor Xanesh": "Ny'alotha, the Waking City",
    "The Hivemind": "Ny'alotha, the Waking City",
    "Shad'har the Insatiable": "Ny'alotha, the Waking City",
    "Drest'agath": "Ny'alotha, the Waking City",
    "Vexiona": "Ny'alotha, the Waking City",
    "Il'gynoth, Corruption Reborn": "Ny'alotha, the Waking City",
    "Carapace of N'Zoth": "Ny'alotha, the Waking City",
    # SL
    "Shriekwing": "Castle Nathria",
    "Huntsman Altimor": "Castle Nathria",
    "Sun King's Salvation": "Castle Nathria",
    "Artificer Xy'mox": "Castle Nathria",
    "Hungering Destroyer": "Castle Nathria",
    "Lady Inerva Darkvein": "Castle Nathria",
    "The Council of Blood": "Castle Nathria",
    "Sludgefist": "Castle Nathria",
    "Stone Legion Generals": "Castle Nathria",
    "The Tarragrue": "Sanctum of Domination",
    "The Eye of the Jailer": "Sanctum of Domination",
    "The Nine": "Sanctum of Domination",
    "Remnant of Ner'zhul": "Sanctum of Domination",
    "Soulrender Dormazain": "Sanctum of Domination",
    "Painsmith Raznal": "Sanctum of Domination",
    "Guardian of the First Ones": "Sanctum of Domination",
    "Fatescribe Roh-Kalo": "Sanctum of Domination",
    "Kel'Thuzad": "Sanctum of Domination",
    "Vigilant Guardian": "Sepulcher of the First Ones",
    "Skolex, the Insatiable Ravener": "Sepulcher of the First Ones",
    "Artificer Xy'mox (SotFO)": "Sepulcher of the First Ones",
    "Dausegne, the Fallen Oracle": "Sepulcher of the First Ones",
    "Prototype Pantheon": "Sepulcher of the First Ones",
    "Lihuvim, Principal Architect": "Sepulcher of the First Ones",
    "Halondrus the Reclaimer": "Sepulcher of the First Ones",
    "Anduin Wrynn": "Sepulcher of the First Ones",
    "Lords of Dread": "Sepulcher of the First Ones",
    "Rygelon": "Sepulcher of the First Ones",
    # DF
    "Eranog": "Vault of the Incarnates",
    "Terros": "Vault of the Incarnates",
    "The Primal Council": "Vault of the Incarnates",
    "Sennarth, the Cold Breath": "Vault of the Incarnates",
    "Dathea, Ascended": "Vault of the Incarnates",
    "Kurog Grimtotem": "Vault of the Incarnates",
    "Broodkeeper Diurna": "Vault of the Incarnates",
    "Kazzara, the Hellforged": "Aberrus, the Shadowed Crucible",
    "The Amalgamation Chamber": "Aberrus, the Shadowed Crucible",
    "The Forgotten Experiments": "Aberrus, the Shadowed Crucible",
    "Assault of the Zaqali": "Aberrus, the Shadowed Crucible",
    "Rashok, the Elder": "Aberrus, the Shadowed Crucible",
    "The Vigilant Steward, Zskarn": "Aberrus, the Shadowed Crucible",
    "Magmorax": "Aberrus, the Shadowed Crucible",
    "Echo of Neltharion": "Aberrus, the Shadowed Crucible",
    "Gnarlroot": "Amirdrassil, the Dream's Hope",
    "Igira the Cruel": "Amirdrassil, the Dream's Hope",
    "Volcoross": "Amirdrassil, the Dream's Hope",
    "Council of Dreams": "Amirdrassil, the Dream's Hope",
    "Larodar, Keeper of the Flame": "Amirdrassil, the Dream's Hope",
    "Nymue, Weaver of the Cycle": "Amirdrassil, the Dream's Hope",
    "Smolderon": "Amirdrassil, the Dream's Hope",
    "Tindral Sageswift, Seer of the Flame": "Amirdrassil, the Dream's Hope",
    # TWW
    "Ulgrax the Devourer": "Nerub-ar Palace",
    "The Bloodbound Horror": "Nerub-ar Palace",
    "Sikran, Captain of the Sureki": "Nerub-ar Palace",
    "Rasha'nan": "Nerub-ar Palace",
    "Eggtender Ovi'nax": "Nerub-ar Palace",
    "Nexus-Princess Ky'veza": "Nerub-ar Palace",
    "The Silken Court": "Nerub-ar Palace",
    "Vexie and the Geargrinders": "Liberation of Undermine",
    "Cauldron of Carnage": "Liberation of Undermine",
    "Rik Reverb": "Liberation of Undermine",
    "Stix Bunkjunker": "Liberation of Undermine",
    "Sprocketmonger Lockenstock": "Liberation of Undermine",
    "The One-Armed Bandit": "Liberation of Undermine",
    "Mug'Zee, Heads of Security": "Liberation of Undermine",
}

# Curated overrides for well-known mount mechanics that data sources can't capture.
# Applied LAST in merge_data, after all source merging.
# Only specified fields are overridden — the full entry is NOT replaced.
CURATED_OVERRIDES = {
    # Guaranteed drops (100% or former 100%)
    59569: {"dropChance": 1.0, "lockoutInstanceName": "Obsidian Sanctum", "expansion": "WOTLK"},   # Twilight Drake (OS 3D 25)
    59571: {"dropChance": 1.0},                                                                     # Twilight Drake (alt spellID — guaranteed OS 3D 25)
    59568: {"dropChance": 1.0, "lockoutInstanceName": "Obsidian Sanctum", "expansion": "WOTLK"},   # Black Drake (OS 3D 10)
    59996: {"lockoutInstanceName": "Utgarde Pinnacle", "expansion": "WOTLK"},                       # Blue Proto-Drake
    43951: {"dropChance": 1.0, "lockoutInstanceName": "Stratholme", "expansion": "WOTLK"},          # Bronze Drake (CoT Strat timed)
    69395: {"lockoutInstanceName": "Onyxia's Lair", "expansion": "CATA", "difficultyID": 4},         # Onyxian Drake (Onyxia's Lair 25-man, WOTLK re-release)
    97493: {"lockoutInstanceName": "Dragon Soul", "expansion": "CATA"},                             # Experiment 12-B
    6898:  {"lockoutInstanceName": "Stratholme", "expansion": "CLASSIC"},                           # Deathcharger (Baron Rivendare)
    63796: {"lockoutInstanceName": "Ulduar", "expansion": "WOTLK"},                                 # Mimiron's Head
    72286: {"lockoutInstanceName": "Icecrown Citadel", "expansion": "WOTLK"},                       # Invincible
    32458: {"lockoutInstanceName": "Tempest Keep", "expansion": "TBC"},                             # Ashes of Al'ar
    88746: {"lockoutInstanceName": "Throne of the Four Winds", "expansion": "CATA", "difficultyID": 6},  # Drake of the South Wind

    # World bosses — known drop chance, per-character weekly lockout
    127154: {"dropChance": 0.0067, "expansion": "MOP", "sourceType": "world_drop", "timeGate": "weekly"},  # Thundering Cobalt Cloud Serpent (Nalak)
    127158: {"dropChance": 0.01,   "expansion": "MOP", "sourceType": "world_drop", "timeGate": "weekly"},  # Cobalt Primordial Direhorn (Oondasta)
    148417: {"dropChance": 0.01,   "expansion": "MOP", "sourceType": "world_drop", "timeGate": "weekly"},  # Thundering Onyx Cloud Serpent (Huolon)
    87771:  {"dropChance": 0.01,   "expansion": "MOP", "sourceType": "world_drop", "timeGate": "weekly"},  # Heavenly Onyx Cloud Serpent (Sha of Anger)
    87773:  {"dropChance": 0.01,   "expansion": "MOP", "sourceType": "world_drop", "timeGate": "weekly"},  # Son of Galleon (Galleon)
    171828: {"dropChance": 0.03,   "expansion": "WOD", "sourceType": "world_drop", "timeGate": "weekly"},  # Solar Spirehawk (Rukhmar)

    # Missing lockout instances for well-known raid mounts
    136471: {"lockoutInstanceName": "Throne of Thunder", "expansion": "MOP"},       # Clutch of Ji-Kun (Horridon)
    139448: {"lockoutInstanceName": "Throne of Thunder", "expansion": "MOP"},       # Clutch of Ji-Kun
    104253: {"lockoutInstanceName": "Siege of Orgrimmar", "expansion": "MOP"},      # Kor'kron Juggernaut
    171621: {"lockoutInstanceName": "Blackrock Foundry", "expansion": "WOD", "difficultyID": 16},  # Ironhoof Destroyer (Mythic)

    # --- TBC ---
    40192: {"lockoutInstanceName": "Tempest Keep"},                              # Ashes of Al'ar (alternate spellID)

    # --- WOTLK ---
    59567: {"lockoutInstanceName": "Eye of Eternity", "difficultyID": 3},        # Azure Drake (Eye of Eternity 10-man)
    61465: {"lockoutInstanceName": "Vault of Archavon", "difficultyID": 4},      # Grand Black War Mammoth (Alliance) — VoA 25N
    61467: {"lockoutInstanceName": "Vault of Archavon", "difficultyID": 4},      # Grand Black War Mammoth (Horde) — VoA 25N

    # --- CATA ---
    88744: {"lockoutInstanceName": "Throne of the Four Winds", "difficultyID": 6},  # Drake of the South Wind (alt spellID, 25H Al'Akir)
    96491: {"lockoutInstanceName": "Zul'Gurub", "difficultyID": 2},             # Armored Razzashi Raptor (Heroic dungeon)
    96499: {"lockoutInstanceName": "Zul'Gurub", "difficultyID": 2},             # Swift Zulian Panther (Heroic dungeon)
    # 97493 already exists above (Experiment 12-B, Dragon Soul) — Pureblood Fire Hawk uses a different spellID
    101542: {"lockoutInstanceName": "Firelands", "difficultyID": 6},            # Flametalon of Alysrazor (alt spellID, 25H)
    107842: {"lockoutInstanceName": "Dragon Soul", "difficultyID": 6},          # Blazing Drake (any diff, originally 25H)
    107845: {"lockoutInstanceName": "Dragon Soul", "difficultyID": 6},          # Life-Binder's Handmaiden (25H Heroic Deathwing)
    110039: {"lockoutInstanceName": "Dragon Soul", "difficultyID": 6},          # Experiment 12-B (alt spellID, any diff)

    # --- MOP ---
    127170: {"lockoutInstanceName": "Mogu'shan Vaults"},                         # Astral Cloud Serpent

    # --- WOD ---
    182912: {"lockoutInstanceName": "Hellfire Citadel", "difficultyID": 16},    # Felsteel Annihilator (Mythic)
    171827: {"lockoutInstanceName": "Hellfire Citadel"},                         # Hellfire Infernal

    # --- LEGION ---
    213134: {"lockoutInstanceName": "Antorus, the Burning Throne"},              # Felblaze Infernal
    229499: {"lockoutInstanceName": "Return to Karazhan"},                       # Midnight
    231428: {"lockoutInstanceName": "Return to Karazhan"},                       # Smoldering Ember Wyrm
    232519: {"lockoutInstanceName": "Tomb of Sargeras", "difficultyID": 16},     # Abyss Worm (Mythic — Mistress Sass'zine)
    243651: {"lockoutInstanceName": "Antorus, the Burning Throne"},              # Shackled Ur'zul
    253088: {"lockoutInstanceName": "Antorus, the Burning Throne", "difficultyID": 16},  # Antoran Charhound (Mythic — Felhounds)

    # --- BFA ---
    266058: {"lockoutInstanceName": "Uldir"},                                    # Tomb Stalker
    273541: {"lockoutInstanceName": "Underrot"},                                 # Underrot Crawg
    289083: {"lockoutInstanceName": "Battle of Dazar'alor"},                     # G.M.O.D.
    289555: {"lockoutInstanceName": "Battle of Dazar'alor"},                     # Glacial Tidestorm
    308814: {"lockoutInstanceName": "Ny'alotha, the Waking City"},               # Ny'alotha Allseer

    # --- SL ---
    336036: {"lockoutInstanceName": "Theater of Pain", "sourceType": "dungeon_drop"},  # Marrowfang
    339957: {"expansion": "SL", "dropChance": 0.01, "difficultyID": 16,
             "lockoutInstanceName": "Sanctum of Domination"},                    # Hand of Hrestimorak (SL Mythic; was incorrectly BFA)
    351195: {"lockoutInstanceName": "Sanctum of Domination"},                    # Vengeance
    354351: {"lockoutInstanceName": "Sanctum of Domination"},                    # Sanctum Gloomcharger
    368158: {"lockoutInstanceName": "Sepulcher of the First Ones"},              # Zereth Overseer

    # --- DF ---
    413922: {"dropChance": 0.01},                                                # Valiance (DF Naxxramas Remix limited-time event)
    424484: {"lockoutInstanceName": "Amirdrassil, the Dream's Hope"},            # Anu'relos

    # --- TWW ---
    451486: {"lockoutInstanceName": "Nerub-ar Palace", "difficultyID": 16},     # Sureki Skyrazor (Mythic — Queen Ansurek)
    451491: {"lockoutInstanceName": "Nerub-ar Palace"},                          # Ascendant Skyrazor

    # --- Source type corrections: world drops misclassified as raid_drop ---
    60002:  {"sourceType": "world_drop"},    # Time-Lost Proto-Drake
    88718:  {"sourceType": "world_drop"},    # Phosphorescent Stone Drake
    179478: {"sourceType": "world_drop"},    # Voidtalon of the Dark Star
    171620: {"sourceType": "world_drop"},    # Bloodhoof Bull (WOD rare)
    171622: {"sourceType": "world_drop"},    # Mottled Meadowstomper (WOD rare)
    171636: {"sourceType": "world_drop"},    # Great Greytusk (WOD rare)
    171824: {"sourceType": "world_drop"},    # Sapphire Riverbeast (WOD rare)
    171830: {"sourceType": "world_drop"},    # Swift Breezestrider (WOD rare)
    171849: {"sourceType": "world_drop"},    # Sunhide Gronnling (WOD rare)
    213350: {"sourceType": "world_drop"},    # Frostshard Infernal

    # --- Source type corrections: quest chains misclassified as raid_drop ---
    98718:  {"sourceType": "quest_chain"},   # Subdued Seahorse
    223018: {"sourceType": "quest_chain"},   # Fathom Dweller
    238454: {"sourceType": "quest_chain"},   # Netherlord's Accursed Wrathsteed
    247402: {"sourceType": "quest_chain"},   # Lucid Nightmare
    312765: {"sourceType": "quest_chain"},   # Sundancer
    315014: {"sourceType": "quest_chain"},   # Ivory Cloud Serpent
    374194: {"sourceType": "quest_chain"},   # Mossy Mammoth
    374278: {"sourceType": "quest_chain"},   # Renewed Magmammoth

    # --- Source type corrections: vendor mounts misclassified as raid_drop ---
    32245:  {"sourceType": "vendor"},        # Green Wind Rider
    138641: {"sourceType": "vendor"},        # Red Primal Raptor
    138642: {"sourceType": "vendor"},        # Black Primal Raptor
    138643: {"sourceType": "vendor"},        # Green Primal Raptor

    # --- Source type corrections: Vicious PvP mounts (Vicious Saddle currency, not achievement) ---
    100332: {"sourceType": "pvp"},           # Vicious War Steed
    100333: {"sourceType": "pvp"},           # Vicious War Wolf
    # SL Vicious mounts
    327407: {"sourceType": "pvp"},           # Vicious War Spider (A)
    327408: {"sourceType": "pvp"},           # Vicious War Spider (H)
    347255: {"sourceType": "pvp"},           # Vicious War Croaker (A)
    347256: {"sourceType": "pvp"},           # Vicious War Croaker (H)
    348769: {"sourceType": "pvp"},           # Vicious War Gorm (A)
    348770: {"sourceType": "pvp"},           # Vicious War Gorm (H)
    349823: {"sourceType": "pvp"},           # Vicious Warstalker (A)
    349824: {"sourceType": "pvp"},           # Vicious Warstalker (H)
    # DF Vicious mounts
    394737: {"sourceType": "pvp"},           # Vicious Sabertooth (A)
    394738: {"sourceType": "pvp"},           # Vicious Sabertooth (H)
    409032: {"sourceType": "pvp"},           # Vicious War Snail (A)
    409034: {"sourceType": "pvp"},           # Vicious War Snail (H)
    424534: {"sourceType": "pvp"},           # Vicious Moonbeast (A)
    424535: {"sourceType": "pvp"},           # Vicious Moonbeast (H)
    434470: {"sourceType": "pvp"},           # Vicious Dreamtalon (A)
    434477: {"sourceType": "pvp"},           # Vicious Dreamtalon (H)
    # TWW Vicious mounts
    447405: {"sourceType": "pvp"},           # Vicious Skyflayer (A)
    449325: {"sourceType": "pvp"},           # Vicious Skyflayer (H)
    466145: {"sourceType": "pvp"},           # Vicious Electro Eel (A)
    466146: {"sourceType": "pvp"},           # Vicious Electro Eel (H)
    1234820: {"sourceType": "pvp"},          # Vicious Void Creeper (A)
    1234821: {"sourceType": "pvp"},          # Vicious Void Creeper (H)
    # MIDNIGHT Vicious mounts
    1261629: {"sourceType": "pvp"},          # Vicious Snaplizard (A)
    1261648: {"sourceType": "pvp"},          # Vicious Snaplizard (H)

    # --- Achievement ID overrides: mount name != achievement reward name ---
    61996:  {"achievementID": 2536},         # Blue Dragonhawk (Mountain o' Mounts - Alliance)
    61997:  {"achievementID": 2537},         # Red Dragonhawk (Mountain o' Mounts - Horde)
    97560:  {"achievementID": 5828},         # Corrupted Fire Hawk (Glory of the Firelands Raider)
    138640: {"achievementID": 8092},         # Bone-White Primal Raptor (A Bone to Pick, Isle of Giants)
    148392: {"achievementID": 8454},         # Spawn of Galakras (Glory of the Orgrimmar Raider)
    171627: {"achievementID": 9669},         # Blacksteel Battleboar (Guild Glory of the Draenor Raider)
    171629: {"achievementID": 9540},         # Armored Frostboar (Warlords Dungeon Hero, Alliance)
    171838: {"achievementID": 9539},         # Armored Frostwolf (Warlords Dungeon Hero, Horde)
    127271: {"sourceType": "reputation", "achievementID": None},  # Crimson Water Strider (Anglers rep, not achievement)
    190690: {"achievementID": 10355},        # Bristling Hellboar (Hellbane, Tanaan rare kills)
    193695: {"achievementID": 10994},        # Prestigious War Steed (Prestige 2, Honor system)
    204166: {"achievementID": 10995},        # Prestigious War Wolf (Prestige 2, Horde)
    294039: {"achievementID": 13638},        # Snapback Scuttler (Undersea Usurper)
    295386: {"achievementID": 13517},        # Ironclad Frostclaw (Two Sides to Every Tale)
    295387: {"achievementID": 13517},        # Bloodflank Charger (Two Sides to Every Tale)
    296788: {"achievementID": 13541},        # Mechacycle Model W (Mecha-Done, Mechagon meta)
    306421: {"achievementID": 13707},        # Frostwolf Snarler (Hero of the Horde: Battle for Alterac Valley)
    308250: {"achievementID": 13706},        # Stormpike Battle Ram (Hero of the Alliance: Battle for Alterac Valley)
    332460: {"achievementID": 14468},        # Chosen Tauralus (Twisting Corridors: Layer 8)
    332467: {"achievementID": 15322},        # Armored Chosen Tauralus (The Jailer's Gauntlet: Layer 8)
    354358: {"achievementID": 15417},        # Darkmaul (SL achievement)
    354361: {"achievementID": 15418},        # Dusklight Razorwing (SL achievement)
    359318: {"achievementID": 15648},        # Soaring Spelltome (Completing the Codex, Zereth Mortis)
    374157: {"achievementID": 16462},        # Gooey Snailemental (Oozing with Character, DF)
    418078: {"achievementID": 18646},        # Pattie (Whodunnit?)
    424607: {"achievementID": 19458},        # Taivan (A World Awoken)
    447160: {"achievementID": 40798},        # Raging Cinderbee (TWW achievement)
    447213: {"achievementID": 40624},        # Alunira (TWW achievement)
    449415: {"achievementID": 40781},        # Slatestone Ramolith (TWW achievement)
    # --- Chauffeured mounts: auto-granted at level 1, not traditional achievements ---
    179244: {"sourceType": "quest_chain"},   # Chauffeured Mechano-Hog
    179245: {"sourceType": "quest_chain"},   # Chauffeured Mekgineer's Chopper

    # --- Shadowlands covenant reward mounts (reclassified from generic DROP) ---
    312754: {"sourceType": "quest_chain"},   # Battle Gargon Vrednic
    312759: {"sourceType": "quest_chain"},   # Dreamlight Runestag
    312761: {"sourceType": "quest_chain"},   # Enchanted Dreamlight Runestag
    312763: {"sourceType": "quest_chain"},   # Darkwarren Hardshell
    312776: {"sourceType": "quest_chain"},   # Chittering Animite
    332243: {"sourceType": "quest_chain"},   # Shadeleaf Runestag
    332244: {"sourceType": "quest_chain"},   # Wakener's Runestag
    332245: {"sourceType": "quest_chain"},   # Winterborn Runestag
    332246: {"sourceType": "quest_chain"},   # Enchanted Shadeleaf Runestag
    332247: {"sourceType": "quest_chain"},   # Enchanted Wakener's Runestag
    332248: {"sourceType": "quest_chain"},   # Enchanted Winterborn Runestag
    332252: {"sourceType": "quest_chain"},   # Shimmermist Runner
    332455: {"sourceType": "quest_chain"},   # War-Bred Tauralus
    332456: {"sourceType": "quest_chain"},   # Plaguerot Tauralus
    332462: {"sourceType": "quest_chain"},   # Armored War-Bred Tauralus
    332923: {"sourceType": "quest_chain"},   # Inquisition Gargon
    332927: {"sourceType": "quest_chain"},   # Sinfall Gargon
    332949: {"sourceType": "quest_chain"},   # Desire's Battle Gargon
    333021: {"sourceType": "quest_chain"},   # Gravestone Battle Gargon
    334352: {"sourceType": "quest_chain"},   # Wildseed Cradle
    334364: {"sourceType": "quest_chain"},   # Spinemaw Gladechewer
    334382: {"sourceType": "quest_chain"},   # Phalynx of Loyalty
    334391: {"sourceType": "quest_chain"},   # Phalynx of Courage
    334398: {"sourceType": "quest_chain"},   # Phalynx of Purity
    334403: {"sourceType": "quest_chain"},   # Eternal Phalynx of Purity
    334406: {"sourceType": "quest_chain"},   # Eternal Phalynx of Courage
    334408: {"sourceType": "quest_chain"},   # Eternal Phalynx of Loyalty
    334409: {"sourceType": "quest_chain"},   # Eternal Phalynx of Humility
    334433: {"sourceType": "quest_chain"},   # Silverwind Larion
    336038: {"sourceType": "quest_chain"},   # Callow Flayedwing
    339588: {"sourceType": "quest_chain"},   # Sinrunner Blanchy
    339632: {"sourceType": "quest_chain"},   # Arboreal Gulper
    341766: {"sourceType": "quest_chain"},   # Warstitched Darkhound
    341776: {"sourceType": "quest_chain"},   # Highwind Darkmane
    347250: {"sourceType": "quest_chain"},   # Lord of the Corpseflies
    353856: {"sourceType": "quest_chain"},   # Ardenweald Wilderling
    353859: {"sourceType": "quest_chain"},   # Summer Wilderling
    353872: {"sourceType": "quest_chain"},   # Sinfall Gravewing
    353875: {"sourceType": "quest_chain"},   # Elysian Aquilon
    353877: {"sourceType": "quest_chain"},   # Forsworn Aquilon
    353883: {"sourceType": "quest_chain"},   # Maldraxxian Corpsefly
    354354: {"sourceType": "quest_chain"},   # Hand of Nilganihmaht
    354355: {"sourceType": "quest_chain"},   # Hand of Salaranga

    # --- Additional lockoutInstanceName overrides (Gap 2) ---
    # CLASSIC
    17481:  {"lockoutInstanceName": "Onyxia's Lair", "expansion": "CLASSIC"},         # Onyxia's Scale Cloak -> Onyxia (classic)
    # TBC
    25953:  {"lockoutInstanceName": "Temple of Ahn'Qiraj", "expansion": "CLASSIC"},    # Blue Qiraji Battle Tank (AQ40 trash drop)
    # WOTLK
    50818:  {"lockoutInstanceName": "Naxxramas", "expansion": "WOTLK"},               # Horseman's Reins (Headless Horseman... actually event, skip)
    # Trial of the Crusader drops
    66063:  {"lockoutInstanceName": "Trial of the Crusader", "expansion": "WOTLK"},   # Crusader's Black Warhorse
    # CATA — Ruby Sanctum
    74918:  {"lockoutInstanceName": "Ruby Sanctum", "expansion": "CATA"},             # Reins of the Onyxian Drake (if present)
    # MOP — Throne of Thunder additional
    136471: {"lockoutInstanceName": "Throne of Thunder", "expansion": "MOP"},         # already exists, no change
    # Heart of Fear
    139450: {"lockoutInstanceName": "Heart of Fear", "expansion": "MOP"},             # Grand Empress Shek'zeer mount
    # Terrace of Endless Spring
    139449: {"lockoutInstanceName": "Terrace of Endless Spring", "expansion": "MOP"},
    # WOD — Highmaul
    178229: {"lockoutInstanceName": "Highmaul", "expansion": "WOD"},                  # Tundra Icehoof
    178230: {"lockoutInstanceName": "Highmaul", "expansion": "WOD"},                  # Mottled Meadowstomper (Highmaul variant)

    # --- Expansion overrides for mounts missing expansion (Gap 3) ---
    # World bosses — full entries already above; these are covered there
    # Dungeon / misc drops missing expansion
    6899:   {"expansion": "CLASSIC"}, # Deathcharger's Reins (Baron Rivendare - Stratholme)
    # TBC dungeon drops
    35513:  {"expansion": "TBC"},     # Fiery Warhorse (Karazhan - already covered)
    # WOTLK dungeon drops
    59996:  {"expansion": "WOTLK"},   # Blue Proto-Drake (Utgarde Pinnacle)
    # Achievement mounts missing expansion (common ones)
    29151:  {"expansion": "CLASSIC"}, # Black War Bear? or similar classic achievement
    # BFA misc
    302800: {"expansion": "BFA"},     # Clutch of Ha-Li (Operation: Mechagon)
    302802: {"expansion": "BFA"},     # Mechacycle Model W (Operation: Mechagon)

    # --- Additional achievement ID overrides (Gap 4) ---
    # Glory of the Raider achievements
    43959:  {"achievementID": 2572},         # Plagued Proto-Drake (Glory of the Raider 10)
    59323:  {"achievementID": 2573},         # rusted proto-drake? -> Glory of the Ulduar Raider 10
    59324:  {"achievementID": 2590},         # rusted proto-drake 25
    48954:  {"achievementID": 2918},         # Glory of the Hero (Red Proto-Drake)
    60424:  {"achievementID": 4057},         # Glory of the Icecrown Raider 10 -> Icebound Frostbrood Vanquisher
    60425:  {"achievementID": 4058},         # Glory of the Icecrown Raider 25 -> Bloodbathed Frostbrood Vanquisher
    # CATA glory mounts
    72807:  {"achievementID": 5122},         # Drake of the East Wind (Glory of the Cataclysm Raider)
    # MOP glory mounts
    130985: {"achievementID": 7533},         # Reins of the Thundering Jade Cloud Serpent (Glory of the Pandaria Raider)
    130986: {"achievementID": 8397},         # Reins of the Kor'kron War Wolf (Glory of the Orgrimmar Raider)?
    # WOD glory
    174872: {"achievementID": 9578},         # Infernal Direwolf (Glory of the Hellfire Raider)
    # LEGION glory
    241706: {"achievementID": 10669},        # Felwing (Glory of the Legion Raider)?
    # BFA glory
    293060: {"achievementID": 13283},        # Expedition Bloodswarmer (Glory of the Dazar'alor Raider)
    295857: {"achievementID": 13516},        # Dune Scavenger (Glory of the Eternal Palace Raider)
    # SL glory
    360780: {"achievementID": 15066},        # Sanctum Gloomcharger (Glory of the Sanctum Raider)?

    # ---------------------------------------------------------------------------
    # Reclassified raid_drop mounts (were misclassified due to Blizzard "DROP" type)
    # ---------------------------------------------------------------------------

    # --- BFA world drops / rares ---
    275623: {"sourceType": "world_drop",  "expansion": "BFA"},   # Nazjatar Blood Serpent (rare in Nazjatar)
    288499: {"sourceType": "world_drop",  "expansion": "BFA"},   # Frightened Kodo (rare in Stormsong Valley)
    290718: {"sourceType": "world_drop",  "expansion": "BFA"},   # Aerial Unit R-21/X (Mechagon rare)
    300150: {"sourceType": "world_drop",  "expansion": "BFA"},   # Fabious (rare spawn Nazjatar)

    # --- BFA vendor mounts (Island Expeditions / Nazjatar currency) ---
    280729: {"sourceType": "vendor",      "expansion": "BFA"},   # Frenzied Feltalon (Island Expeditions vendor)
    280730: {"sourceType": "vendor",      "expansion": "BFA"},   # Pureheart Courser (Island Expeditions vendor)
    300154: {"sourceType": "vendor",      "expansion": "BFA"},   # Silver Tidestallion (Nazjatar currency vendor)

    # --- BFA quest / achievement ---
    278966: {"sourceType": "promotion",   "expansion": "BFA"},   # Fiery Hearthsteed (Hearthstone cross-promo)
    294143: {"sourceType": "quest_chain", "expansion": "BFA"},   # X-995 Mechanocat (Mechagon questline)
    346141: {"sourceType": "achievement", "expansion": "BFA", "achievementID": 14143},   # Slime Serpent (Horrific Visions full clear)

    # --- CATA dungeon drop ---
    98204:  {"sourceType": "dungeon_drop", "expansion": "CATA", "timeGate": "daily",
             "lockoutInstanceName": "Zul'Aman", "dropChance": 1.0, "difficultyID": 2},  # Amani Battle Bear (Zul'Aman timed run, guaranteed, Heroic)

    # --- CLASSIC unobtainable ---
    16081:  {"shouldExclude": True},                              # Arctic Wolf (removed PvP mount)

    # --- DF world drops (Zaralek Cavern / Thaldraszus rares) ---
    350219: {"sourceType": "world_drop",  "expansion": "DF"},    # Magmashell
    374138: {"sourceType": "world_drop",  "expansion": "DF"},    # Seething Slug
    385266: {"sourceType": "world_drop",  "expansion": "DF"},    # Zenet Hatchling

    # --- DF vendor ---
    376898: {"sourceType": "vendor",      "expansion": "DF"},    # Bestowed Ottuk Vanguard (DF vendor, spell in DF range)

    # --- LEGION quest chains / vendor ---
    243025: {"sourceType": "quest_chain", "expansion": "LEGION"},  # Riddler's Mind-Worm (secret puzzle)
    254812: {"sourceType": "vendor",      "expansion": "LEGION"},  # Royal Seafeather (Argussian Reach paragon)
    261395: {"sourceType": "quest_chain", "expansion": "LEGION"},  # The Hivemind (secret puzzle, group req)

    # --- MOP world drops / world bosses (additional entries not already covered) ---
    130965: {"sourceType": "world_drop",  "expansion": "MOP", "timeGate": "weekly"},   # Son of Galleon (Galleon world boss)
    132036: {"sourceType": "world_drop",  "expansion": "MOP"},                          # Thundering Ruby Cloud Serpent (Alani/Skyshards)
    138423: {"sourceType": "world_drop",  "expansion": "MOP", "timeGate": "weekly"},   # Cobalt Primordial Direhorn alt spellID? (Oondasta)
    139442: {"sourceType": "world_drop",  "expansion": "MOP", "timeGate": "weekly"},   # Thundering Cobalt Cloud Serpent alt spellID? (Nalak)
    171840: {"sourceType": "world_drop",  "expansion": "MOP"},                          # Coldflame Infernal (Timeless Isle rare)

    # --- SL world drops / vendor ---
    312767: {"sourceType": "world_drop",  "expansion": "SL"},    # Swift Gloomhoof (Ardenweald rare)
    332482: {"sourceType": "world_drop",  "expansion": "SL"},    # Bonecleaver's Skullboar (Maldraxxus rare)
    215545: {"sourceType": "vendor",      "expansion": "SL"},    # Mastercraft Gravewing (Venthyr upgrade vendor)

    # --- TBC / CLASSIC unobtainable ---
    24242:  {"shouldExclude": True},   # Swift Razzashi Raptor (removed, original ZG)
    24252:  {"shouldExclude": True},   # Swift Zulian Tiger (removed, original ZG)
    25863:  {"shouldExclude": True},   # Black Qiraji Battle Tank (AQ opening event, unobtainable)
    26655:  {"shouldExclude": True},   # Black Qiraji Battle Tank duplicate
    26656:  {"shouldExclude": True},   # Black Qiraji Battle Tank duplicate

    # --- CLASSIC AQ40 trash drops ---
    26055:  {"sourceType": "world_drop", "expansion": "CLASSIC",
             "lockoutInstanceName": "Temple of Ahn'Qiraj"},       # Yellow Qiraji Battle Tank
    26056:  {"sourceType": "world_drop", "expansion": "CLASSIC",
             "lockoutInstanceName": "Temple of Ahn'Qiraj"},       # Green Qiraji Battle Tank

    # --- TWW world drops / vendor ---
    420097:  {"sourceType": "world_drop",  "expansion": "TWW"},   # Azure Worldchiller
    437162:  {"sourceType": "world_drop",  "expansion": "TWW"},   # Polly Roger
    466021:  {"sourceType": "vendor",      "expansion": "TWW"},   # Violet Goblin Shredder (Undermine patch)
    471696:  {"sourceType": "world_drop",  "expansion": "TWW"},   # Hooktalon
    1250578: {"sourceType": "world_drop",  "expansion": "TWW"},   # Phase-Lost Slateback

    # --- MIDNIGHT mounts (spell IDs 1218xxx+) ---
    1218229: {"expansion": "MIDNIGHT"},   # Void-Scarred Gryphon
    1218305: {"expansion": "MIDNIGHT"},   # Void-Forged Stallion
    1218306: {"expansion": "MIDNIGHT"},   # Void-Scarred Pack Mother
    1218307: {"expansion": "MIDNIGHT"},   # Void-Scarred Windrider
    1241070: {"expansion": "MIDNIGHT"},   # Translocated Gorger
    1253938: {"expansion": "MIDNIGHT"},   # Ruddy Sporeglider
    1260354: {"expansion": "MIDNIGHT"},   # Untainted Grove Crawler
    1260356: {"expansion": "MIDNIGHT"},   # Echo of Aln'sharan
    1261332: {"expansion": "MIDNIGHT"},   # Duskbrute Harrower
    1261360: {"expansion": "MIDNIGHT"},   # Ancestral War Bear
    1261576: {"expansion": "MIDNIGHT"},   # Hexed Vilefeather Eagle
    1261583: {"expansion": "MIDNIGHT"},   # Insatiable Shredclaw
    1261668: {"expansion": "MIDNIGHT"},   # Bronze Wilderling
    1261671: {"expansion": "MIDNIGHT"},   # Bronze Aquilon
    1263635: {"expansion": "MIDNIGHT"},   # Spectral Hawkstrider

    # --- WOD world drops ---
    171851: {"sourceType": "world_drop",  "expansion": "WOD", "dropChance": 1.0},   # Garn Nighthowl (Nok-Karosh, guaranteed)
    189364: {"sourceType": "world_drop",  "expansion": "WOD"},                       # Coalfist Gronnling (garrison invasion rare)

    # --- WOTLK ---
    43688:  {"shouldExclude": True},                                                  # Amani War Bear (removed, original timed run)
    59650:  {"sourceType": "raid_drop",   "expansion": "WOTLK", "dropChance": 1.0,
             "lockoutInstanceName": "Obsidian Sanctum"},          # Black Drake (OS 3D 10-man, guaranteed)
    # 62048 Illidari Doomhawk: keep as raid_drop WOTLK pending further research
    62048:  {"expansion": "WOTLK"},                                                   # Illidari Doomhawk (unconfirmed, keeping raid_drop)
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def ensure_cache_dir():
    CACHE_DIR.mkdir(parents=True, exist_ok=True)


def cached_get(url, cache_key, max_age_hours=24):
    """HTTP GET with file-based caching."""
    ensure_cache_dir()
    cache_file = CACHE_DIR / cache_key
    if cache_file.exists():
        age = time.time() - cache_file.stat().st_mtime
        if age < max_age_hours * 3600:
            return cache_file.read_text(encoding="utf-8")

    print(f"  Fetching {url[:80]}...")
    resp = requests.get(url, timeout=30)
    resp.raise_for_status()
    text = resp.text
    cache_file.write_text(text, encoding="utf-8")
    return text


def get_time_per_attempt(source_type, expansion):
    """Estimate minutes per attempt based on source type and content age."""
    idx = EXPANSION_INDEX.get(expansion)
    age = (CURRENT_EXPANSION - idx) if idx is not None else 5

    if source_type in ("raid_drop", "dungeon_drop"):
        if age == 0:
            return 30
        elif age == 1:
            return 20
        elif age == 2:
            return 12
        elif age >= 3:
            return 4
    elif source_type == "world_drop":
        return 15 if age <= 1 else 5
    elif source_type == "reputation":
        return 30
    elif source_type == "event":
        return 15
    elif source_type == "achievement":
        return 30 if age <= 1 else 20
    return 10


def get_time_gate(source_type, expansion):
    """Estimate time gate based on source type."""
    idx = EXPANSION_INDEX.get(expansion)
    age = (CURRENT_EXPANSION - idx) if idx is not None else 5

    gates = {
        "raid_drop": "weekly",
        "dungeon_drop": "daily" if age <= 1 else "none",
        "world_drop": "none",
        "reputation": "daily",
        "currency": "weekly",
        "quest_chain": "none",
        "achievement": "none",
        "profession": "daily",
        "pvp": "weekly",
        "event": "yearly",
        "vendor": "none",
        "trading_post": "monthly",
        "promotion": "none",
    }
    return gates.get(source_type, "weekly")


def get_group_requirement(source_type, expansion):
    """Estimate group requirement based on source type and age."""
    idx = EXPANSION_INDEX.get(expansion)
    age = (CURRENT_EXPANSION - idx) if idx is not None else 5

    if source_type == "raid_drop":
        if age == 0:
            return "raid"
        elif age == 1:
            return "small"
        return "solo"
    elif source_type == "dungeon_drop":
        return "small" if age == 0 else "solo"
    elif source_type == "pvp":
        return "small"
    return "solo"


def refine_source_type_from_text(current_type, source_text):
    """Use wago sourceText hints to correct sourceType when possible.

    Only overrides generic/ambiguous types (raid_drop, world_drop, unknown).
    Never overrides specific Rarity BOSS classifications.
    """
    if not source_text:
        return current_type
    lower = source_text.lower()

    # Strong signals that override generic "raid_drop", "world_drop", or "unknown"
    if current_type in ("raid_drop", "world_drop", "unknown"):
        if lower.startswith("vendor") or "sold by" in lower:
            return "vendor"
        if "world event" in lower or "holiday" in lower:
            return "event"
        if "pvp" in lower or "gladiator" in lower or "arena" in lower or "rated" in lower:
            return "pvp"
        if "profession" in lower or "engineering" in lower or "tailoring" in lower:
            return "profession"

    # Don't override Rarity's specific classifications (raid_drop from BOSS method, etc.)
    return current_type


# ---------------------------------------------------------------------------
# Source 1: wago.tools Mount Index
# ---------------------------------------------------------------------------

def fetch_wago_mounts():
    """Fetch complete mount list from wago.tools DB2 CSV export."""
    print("\n[1/4] Fetching wago.tools mount index...")
    csv_text = cached_get(
        "https://wago.tools/db2/Mount/csv",
        "wago_mount.csv",
        max_age_hours=72,
    )

    mounts = {}
    reader = csv.DictReader(io.StringIO(csv_text))
    for row in reader:
        spell_id = row.get("SourceSpellID") or row.get("SourceSpellId")
        if not spell_id:
            continue
        spell_id = int(spell_id)
        if spell_id == 0:
            continue

        mount_id = int(row.get("ID", 0))
        name = row.get("Name_lang", "").strip()
        source_text = row.get("SourceText_lang", "").strip()
        source_type_enum = int(row.get("SourceTypeEnum", 0))

        mounts[spell_id] = {
            "mountID": mount_id,
            "name": name,
            "sourceText": source_text,
            "blizzSourceType": source_type_enum,
            "spellID": spell_id,
        }

    print(f"  Found {len(mounts)} mounts from wago.tools")
    return mounts


# ---------------------------------------------------------------------------
# Source 2: Blizzard API
# ---------------------------------------------------------------------------

def get_blizzard_token():
    """Get OAuth access token using client credentials."""
    if not BLIZZARD_CLIENT_ID or not BLIZZARD_CLIENT_SECRET:
        print("  WARNING: No Blizzard API credentials found, skipping")
        return None

    print("  Authenticating with Blizzard API...")
    resp = requests.post(
        "https://oauth.battle.net/token",
        data={"grant_type": "client_credentials"},
        auth=(BLIZZARD_CLIENT_ID, BLIZZARD_CLIENT_SECRET),
        timeout=15,
    )
    resp.raise_for_status()
    token = resp.json()["access_token"]
    print("  Authentication successful")
    return token


def fetch_blizzard_mounts(token):
    """Fetch mount source types from Blizzard Game Data API."""
    print("\n[2/4] Fetching Blizzard API mount data...")
    if not token:
        print("  Skipped (no credentials)")
        return {}

    region = BLIZZARD_REGION
    namespace = f"static-{region}"
    base = f"https://{region}.api.blizzard.com"
    headers = {"Authorization": f"Bearer {token}"}

    # Fetch mount index
    index_cache = CACHE_DIR / "blizzard_mount_index.json"
    if index_cache.exists() and (time.time() - index_cache.stat().st_mtime) < 72 * 3600:
        index_data = json.loads(index_cache.read_text(encoding="utf-8"))
    else:
        resp = requests.get(
            f"{base}/data/wow/mount/index",
            params={"namespace": namespace, "locale": "en_US"},
            headers=headers,
            timeout=30,
        )
        resp.raise_for_status()
        index_data = resp.json()
        ensure_cache_dir()
        index_cache.write_text(json.dumps(index_data), encoding="utf-8")

    mount_ids = [m["id"] for m in index_data.get("mounts", [])]
    print(f"  Found {len(mount_ids)} mounts in Blizzard index")

    # Fetch details for each mount (with caching and rate limiting)
    blizzard_data = {}
    detail_cache_dir = CACHE_DIR / "blizzard_mounts"
    detail_cache_dir.mkdir(parents=True, exist_ok=True)

    batch_count = 0
    for i, mid in enumerate(mount_ids):
        cache_file = detail_cache_dir / f"{mid}.json"
        if cache_file.exists() and (time.time() - cache_file.stat().st_mtime) < 72 * 3600:
            data = json.loads(cache_file.read_text(encoding="utf-8"))
        else:
            try:
                resp = requests.get(
                    f"{base}/data/wow/mount/{mid}",
                    params={"namespace": namespace, "locale": "en_US"},
                    headers=headers,
                    timeout=15,
                )
                if resp.status_code == 429:
                    print(f"  Rate limited, waiting 2s...")
                    time.sleep(2)
                    resp = requests.get(
                        f"{base}/data/wow/mount/{mid}",
                        params={"namespace": namespace, "locale": "en_US"},
                        headers=headers,
                        timeout=15,
                    )
                resp.raise_for_status()
                data = resp.json()
                cache_file.write_text(json.dumps(data), encoding="utf-8")
                batch_count += 1
                # Rate limit: ~10 req/sec
                if batch_count % 10 == 0:
                    time.sleep(1)
            except Exception as e:
                print(f"  Error fetching mount {mid}: {e}")
                continue

        source = data.get("source", {})
        source_type = source.get("type", "")
        blizzard_data[mid] = {
            "blizzardID": mid,
            "name": data.get("name", ""),
            "sourceType": BLIZZARD_SOURCE_MAP.get(source_type, "unknown"),
            "blizzardSourceType": source_type,
            "faction": data.get("faction", {}).get("type"),
            # Step 2: should_exclude_if_uncollected
            "shouldExclude": data.get("should_exclude_if_uncollected", False),
        }

        # Step 2: Extract class/race restrictions from requirements
        requirements = data.get("requirements", {})
        if requirements:
            classes = requirements.get("classes", [])
            if classes:
                blizzard_data[mid]["classRestrictions"] = [
                    c.get("name", "") for c in classes if c.get("name")
                ]
            races = requirements.get("races", [])
            if races:
                blizzard_data[mid]["raceRestrictions"] = [
                    r.get("name", "") for r in races if r.get("name")
                ]

        if (i + 1) % 100 == 0:
            print(f"  Processed {i + 1}/{len(mount_ids)} mounts...")

    print(f"  Got source types for {len(blizzard_data)} mounts")
    return blizzard_data


# ---------------------------------------------------------------------------
# Source 2B: wago.tools Achievement DB2  (Step 3)
# ---------------------------------------------------------------------------

def _normalize_mount_name(name):
    """Strip common mount name prefixes for fuzzy matching."""
    lower = name.lower().strip()
    for prefix in ("reins of the ", "reins of ", "the "):
        if lower.startswith(prefix):
            lower = lower[len(prefix):]
            break
    return lower


def fetch_blizzard_achievements():
    """Fetch achievement reward names from wago.tools Achievement DB2 CSV.

    Returns a dict mapping reward_mount_name_lowercase -> achievement_id
    for all achievements whose Reward_lang field mentions a mount.
    """
    print("\n[2B] Fetching wago.tools Achievement DB2...")
    csv_text = cached_get(
        "https://wago.tools/db2/Achievement/csv",
        "wago_achievement.csv",
        max_age_hours=72,
    )

    # Maps: exact_lower -> id, normalized_lower -> id
    reward_map = {}
    reward_map_normalized = {}

    reader = csv.DictReader(io.StringIO(csv_text))
    for row in reader:
        reward = row.get("Reward_lang", "").strip()
        if not reward:
            continue
        if "mount" not in reward.lower():
            continue

        aid_str = row.get("ID", "").strip()
        if not aid_str:
            continue
        try:
            aid = int(aid_str)
        except ValueError:
            continue

        # Strip "Mount: " / "Reward: " prefix to get bare mount name
        mount_name = re.sub(r'^(?:Mount|Reward):\s*', '', reward, flags=re.IGNORECASE).strip()
        if not mount_name:
            continue

        exact_lower = mount_name.lower()
        reward_map[exact_lower] = aid
        reward_map_normalized[_normalize_mount_name(mount_name)] = aid

    print(f"  Found {len(reward_map)} achievement mount rewards")
    return reward_map, reward_map_normalized


# ---------------------------------------------------------------------------
# Step 4: Achievement ID Resolution
# ---------------------------------------------------------------------------

def resolve_achievement_ids(wago_mounts, achievement_reward_map):
    """Resolve achievement IDs for achievement-sourced mounts by matching mount names.

    achievement_reward_map is a tuple (exact_map, normalized_map) as returned by
    fetch_blizzard_achievements().
    """
    print("\n[Resolve] Matching achievement mounts to achievement IDs...")
    if not achievement_reward_map or not achievement_reward_map[0]:
        print("  Skipped (no achievement data)")
        return {}

    exact_map, norm_map = achievement_reward_map

    resolved = {}
    unresolved = []

    for spell_id, wago in wago_mounts.items():
        if wago.get("blizzSourceType") != 6:  # 6 = achievement in wago enum
            continue

        mount_name = wago.get("name", "").strip()
        if not mount_name:
            unresolved.append((spell_id, "", "no name"))
            continue

        # 1. Exact match: mount name == reward name (case-insensitive)
        aid = exact_map.get(mount_name.lower())
        if aid:
            resolved[spell_id] = aid
            continue

        # 2. Normalized match: strip "Reins of the / Reins of / the " from both sides
        norm_name = _normalize_mount_name(mount_name)
        aid = norm_map.get(norm_name)
        if aid:
            resolved[spell_id] = aid
            continue

        # 3. Fuzzy: check if normalized mount name is a substring of any reward name
        found = False
        for reward_norm, lookup_id in norm_map.items():
            if norm_name and (norm_name in reward_norm or reward_norm in norm_name):
                resolved[spell_id] = lookup_id
                found = True
                break

        if not found:
            unresolved.append((spell_id, mount_name, norm_name))

    print(f"  Resolved {len(resolved)}/{len(resolved) + len(unresolved)} achievement mounts")
    if unresolved:
        print(f"  Unresolved: {len(unresolved)} (first 5: {[u[1] for u in unresolved[:5]]})")
    return resolved


# ---------------------------------------------------------------------------
# Source 3: Rarity Addon Database  (Step 1: Enhanced extraction)
# ---------------------------------------------------------------------------

def parse_rarity_lua(lua_text):
    """Parse mount entries from a Rarity addon Lua file."""
    mounts = []

    # Match entries like: ["Mount Name"] = { ... }
    # The body may contain nested tables (npcs, coords, etc.)
    # Use a smarter approach: find each entry start, then brace-match
    entry_starts = list(re.finditer(r'\["([^"]+)"\]\s*=\s*\{', lua_text))

    for idx, match in enumerate(entry_starts):
        name = match.group(1)
        start = match.end()

        # Find matching closing brace (handle nesting)
        depth = 1
        pos = start
        while pos < len(lua_text) and depth > 0:
            if lua_text[pos] == '{':
                depth += 1
            elif lua_text[pos] == '}':
                depth -= 1
            pos += 1

        body = lua_text[start:pos - 1]

        entry = {"name": name}

        # --- Step 1: Extended numeric field extraction ---
        for field, pattern in [
            ("chance", r'chance\s*=\s*(\d+)'),
            ("spellId", r'spellId\s*=\s*(\d+)'),
            ("itemId", r'itemId\s*=\s*(\d+)'),
            ("groupSize", r'groupSize\s*=\s*(\d+)'),
            ("lockDungeonId", r'lockDungeonId\s*=\s*(\d+)'),
        ]:
            m = re.search(pattern, body)
            if m:
                entry[field] = int(m.group(1))

        # Extract NPC IDs
        npcs_match = re.search(r'npcs\s*=\s*\{([^}]+)\}', body)
        if npcs_match:
            npc_ids = [int(x) for x in re.findall(r'(\d+)', npcs_match.group(1))]
            if npc_ids:
                entry["npcs"] = npc_ids

        # Extract method
        method_match = re.search(r'method\s*=\s*CONSTANTS\.DETECTION_METHODS\.(\w+)', body)
        if method_match:
            entry["method"] = method_match.group(1)

        # lockBossName — plain string (NOT localized)
        lock_boss = re.search(r'lockBossName\s*=\s*"([^"]+)"', body)
        if lock_boss:
            entry["lockBossName"] = lock_boss.group(1)

        # Boolean fields
        for flag in ["requiresAlliance", "requiresHorde", "blackMarket", "worldBossFactionless", "equalOdds"]:
            if re.search(rf'{flag}\s*=\s*true', body):
                entry[flag] = True

        # Check for instance difficulties / mythic (legacy check preserved + new extraction)
        if "MYTHIC_RAID" in body:
            entry["mythicOnly"] = True

        # wasGuaranteed flag (100% drop that was later nerfed)
        if "wasGuaranteed" in body:
            entry["wasGuaranteed"] = True

        # questId — can be single number or table
        quest_match = re.search(r'questId\s*=\s*\{([^}]+)\}', body)
        if quest_match:
            entry["questIds"] = [int(x) for x in re.findall(r'(\d+)', quest_match.group(1))]
        else:
            quest_match = re.search(r'questId\s*=\s*(\d+)', body)
            if quest_match:
                entry["questIds"] = [int(quest_match.group(1))]

        # statisticId — always a table
        stat_match = re.search(r'statisticId\s*=\s*\{([^}]+)\}', body)
        if stat_match:
            entry["statisticIds"] = [int(x) for x in re.findall(r'(\d+)', stat_match.group(1))]

        # tooltipNpcs
        tip_match = re.search(r'tooltipNpcs\s*=\s*\{([^}]+)\}', body)
        if tip_match:
            entry["tooltipNpcs"] = [int(x) for x in re.findall(r'(\d+)', tip_match.group(1))]

        # instanceDifficulties — parse constants to numeric IDs
        diff_matches = re.findall(r'CONSTANTS\.INSTANCE_DIFFICULTIES\.(\w+)', body)
        if diff_matches:
            entry["difficulties"] = [
                RARITY_DIFFICULTY_MAP[d]
                for d in diff_matches
                if d in RARITY_DIFFICULTY_MAP
            ]

        # coords — extract mapIDs from m = NUMBER or m = CONSTANTS.UIMAPIDS.XXX
        map_ids = set()
        for m in re.findall(r'\bm\s*=\s*(\d+)', body):
            map_ids.add(int(m))
        map_constants = re.findall(r'CONSTANTS\.UIMAPIDS\.(\w+)', body)
        if map_ids or map_constants:
            entry["mapIDs"] = sorted(map_ids)
            entry["mapConstants"] = map_constants

        # encounterName from lockoutDetails sub-entries
        encounter_names = re.findall(r'encounterName\s*=\s*"([^"]+)"', body)
        if encounter_names:
            entry["encounterNames"] = encounter_names

        if "spellId" in entry:
            mounts.append(entry)

    return mounts


def fetch_rarity_data():
    """Fetch and parse all Rarity addon mount database files."""
    print("\n[3/4] Fetching Rarity addon mount database...")
    all_mounts = {}

    for filename in RARITY_FILES:
        url = f"{RARITY_BASE_URL}/{filename}"
        try:
            lua_text = cached_get(url, f"rarity_{filename}", max_age_hours=168)
            mounts = parse_rarity_lua(lua_text)
            expansion = RARITY_FILE_TO_EXPANSION.get(filename, "UNKNOWN")

            for mount in mounts:
                spell_id = mount["spellId"]
                chance = mount.get("chance", 0)
                drop_chance = (1.0 / chance) if chance > 0 else None

                method = mount.get("method", "")
                source_type = RARITY_METHOD_MAP.get(method, "world_drop")

                # Refine: BOSS method in holiday file = event
                if "HolidayEvents" in filename:
                    source_type = "event"

                all_mounts[spell_id] = {
                    "name": mount["name"],
                    "dropChance": drop_chance,
                    "chance_denom": chance,
                    "expansion": expansion,
                    "sourceType": source_type,
                    "itemID": mount.get("itemId"),
                    "npcIDs": mount.get("npcs", []),
                    "method": method,
                    "mythicOnly": mount.get("mythicOnly", False),
                    "wasGuaranteed": mount.get("wasGuaranteed", False),
                    # Step 1: new fields
                    "lockBossName": mount.get("lockBossName"),
                    "lockDungeonId": mount.get("lockDungeonId"),
                    "questIds": mount.get("questIds"),
                    "groupSize": mount.get("groupSize"),
                    "requiresAlliance": mount.get("requiresAlliance", False),
                    "requiresHorde": mount.get("requiresHorde", False),
                    "blackMarket": mount.get("blackMarket", False),
                    "worldBossFactionless": mount.get("worldBossFactionless", False),
                    "equalOdds": mount.get("equalOdds", False),
                    "statisticIds": mount.get("statisticIds"),
                    "tooltipNpcs": mount.get("tooltipNpcs"),
                    "difficulties": mount.get("difficulties"),
                    "mapIDs": mount.get("mapIDs"),
                    "mapConstants": mount.get("mapConstants"),
                    "encounterNames": mount.get("encounterNames"),
                }

            print(f"  {filename}: {len(mounts)} mounts")
        except Exception as e:
            print(f"  Error fetching {filename}: {e}")

    print(f"  Total from Rarity: {len(all_mounts)} mounts with drop data")
    return all_mounts


# ---------------------------------------------------------------------------
# Source 4: Data for Azeroth (Player Rarity)
# ---------------------------------------------------------------------------

def fetch_rarity_stats():
    """Fetch player mount ownership rarity from MountsRarity addon (Data for Azeroth)."""
    print("\n[4/4] Fetching Data for Azeroth rarity stats...")
    try:
        lua_text = cached_get(
            "https://raw.githubusercontent.com/sgade/MountsRarity/main/MountsRarity.lua",
            "mounts_rarity.lua",
            max_age_hours=168,
        )

        # Data is after the comment "Everything after this line gets automatically replaced"
        # Format: lazyLoadData = function() return { [id] = val, ... } end
        marker = "Everything after this line"
        marker_pos = lua_text.find(marker)
        if marker_pos == -1:
            print("  WARNING: Could not find data marker in MountsRarity.lua")
            return {}
        data_section = lua_text[marker_pos:]
        match = re.search(r'lazyLoadData\s*=\s*function\(\)\s*return\s*\{(.*)\}\s*end',
                          data_section, re.DOTALL)
        if not match:
            print("  WARNING: Could not parse lazyLoadData table in MountsRarity.lua")
            return {}

        table_body = match.group(1)
        rarity_data = {}
        # Pattern: [mountID] = rarityValue  (0-100)
        for m in re.finditer(r'\[(\d+)\]\s*=\s*([0-9.]+)', table_body):
            mount_id = int(m.group(1))
            rarity = float(m.group(2))
            rarity_data[mount_id] = rarity

        print(f"  Found rarity data for {len(rarity_data)} mounts")
        return rarity_data
    except Exception as e:
        print(f"  Error fetching rarity data: {e}")
        return {}


# ---------------------------------------------------------------------------
# Reference: InstanceData.lua  (Step 6)
# ---------------------------------------------------------------------------

def parse_instance_data():
    """Parse InstanceData.lua into a Python dict."""
    instance_data_path = Path(__file__).parent.parent / "FarmBuddy" / "Data" / "InstanceData.lua"
    if not instance_data_path.exists():
        print("  WARNING: InstanceData.lua not found")
        return {}

    lua_text = instance_data_path.read_text(encoding="utf-8")
    instances = {}

    # Match entries like: ["Instance Name"] = { expansion = "XXX", ... }
    for m in re.finditer(r'\["([^"]+)"\]\s*=\s*\{([^}]+)\}', lua_text):
        name = m.group(1)
        body = m.group(2)
        exp_match = re.search(r'expansion\s*=\s*"(\w+)"', body)
        boss_match = re.search(r'bossCount\s*=\s*(\d+)', body)
        solo_match = re.search(r'soloMinutes\s*=\s*(\d+)', body)
        instances[name] = {
            "expansion": exp_match.group(1) if exp_match else None,
            "bossCount": int(boss_match.group(1)) if boss_match else 0,
            "soloMinutes": int(solo_match.group(1)) if solo_match else 15,
        }

    print(f"  Parsed {len(instances)} instances from InstanceData.lua")
    return instances


# ---------------------------------------------------------------------------
# Expansion Inference  (Step 6)
# ---------------------------------------------------------------------------

def guess_expansion_from_spell_id(spell_id):
    """Fallback: guess expansion from spell ID range (monotonically increasing)."""
    for low, high, exp in SPELL_ID_EXPANSION_RANGES:
        if low <= spell_id < high:
            return exp
    return None


def guess_expansion_from_text(text):
    """Guess expansion from sourceText keywords (enhanced with more zones/factions)."""
    if not text:
        return None
    lower = text.lower()
    keywords = [
        # Most specific first — longer/newer expansions at top
        (["midnight", "quel'thalas", "silvermoon", "gilneas", "lordaeron", "tirisfal", "ghostlands", "eversong"], "MIDNIGHT"),
        (["war within", "khaz algar", "hallowfall", "isle of dorn", "the ringing deeps", "azj-kahet", "nerub-ar", "undermine"], "TWW"),
        (["dragonflight", "dragon isles", "zaralek", "valdrakken", "ohnahran", "waking shores", "forbidden reach", "zaralek cavern", "emerald dream", "thaldraszus", "azure span"], "DF"),
        (["shadowlands", "maldraxxus", "bastion", "revendreth", "oribos", "zereth mortis", "korthia", "ardenweald", "the maw"], "SL"),
        (["battle for azeroth", "nazjatar", "mechagon", "zandalar", "drustvar", "stormsong", "tiragarde", "vol'dun", "nazmir", "zuldazar", "ny'alotha"], "BFA"),
        (["legion", "broken isles", "argus", "suramar", "val'sharah", "azsuna", "highmountain", "stormheim", "broken shore", "antoran", "mac'aree", "krokuun"], "LEGION"),
        (["draenor", "tanaan", "garrison", "gorgrond", "spires of arak", "talador", "frostfire"], "WOD"),
        (["pandaria", "timeless isle", "throne of thunder", "jade forest", "valley of the four winds", "kun-lai summit", "townlong steppes", "dread wastes", "vale of eternal blossoms", "isle of giants", "isle of thunder"], "MOP"),
        (["cataclysm", "firelands", "dragon soul", "deepholm", "twilight highlands", "hyjal", "uldum", "tol barad", "vashj'ir"], "CATA"),
        (["northrend", "ulduar", "icecrown", "dalaran", "storm peaks", "howling fjord", "borean tundra", "dragonblight", "grizzly hills", "sholazar", "zul'drak", "wintergrasp", "argent tournament"], "WOTLK"),
        (["outland", "tempest keep", "karazhan", "netherwing", "sha'tari", "ogri'la", "auchindoun", "zangarmarsh", "nagrand", "netherstorm", "hellfire peninsula", "shadowmoon valley", "blade's edge", "terokkar", "shattrath"], "TBC"),
        (["stratholme", "blackrock", "molten core", "onyxia", "scholomance"], "CLASSIC"),
    ]
    for keys, expansion in keywords:
        for key in keys:
            if key in lower:
                return expansion
    return None


def infer_expansion(spell_id, rarity_entry, wago_entry, instance_data):
    """
    Infer expansion using a 3-layer strategy:
    1. Instance data cross-reference (lockBossName/encounterName -> InstanceData)
    2. Enhanced text parsing (sourceText keywords)
    3. SpellID range heuristic (lowest priority fallback)
    """
    # Layer 1: Instance data cross-reference via boss name
    if rarity_entry:
        boss_name = rarity_entry.get("lockBossName")
        encounter_names = rarity_entry.get("encounterNames") or []

        # Check lockBossName against BOSS_TO_INSTANCE then InstanceData
        if boss_name:
            instance_name = BOSS_TO_INSTANCE.get(boss_name)
            if instance_name and instance_name in instance_data:
                exp = instance_data[instance_name].get("expansion")
                if exp:
                    return exp

        # Check encounterNames against BOSS_TO_INSTANCE then InstanceData
        for enc_name in encounter_names:
            instance_name = BOSS_TO_INSTANCE.get(enc_name)
            if instance_name and instance_name in instance_data:
                exp = instance_data[instance_name].get("expansion")
                if exp:
                    return exp

        # Also check encounterNames directly against InstanceData keys
        for enc_name in encounter_names:
            if enc_name in instance_data:
                exp = instance_data[enc_name].get("expansion")
                if exp:
                    return exp

    # Layer 2: Text keyword parsing
    source_text = (wago_entry or {}).get("sourceText", "")
    exp = guess_expansion_from_text(source_text)
    if exp:
        return exp

    # Also try rarity name if available
    if rarity_entry:
        exp = guess_expansion_from_text(rarity_entry.get("name", ""))
        if exp:
            return exp

    # Layer 3: SpellID range heuristic
    return guess_expansion_from_spell_id(spell_id)


# ---------------------------------------------------------------------------
# Step 8: DifficultyID Derivation
# ---------------------------------------------------------------------------

def derive_difficulty_id(difficulties, expansion, mythic_only=False):
    """Derive the primary difficultyID from Rarity difficulties list."""
    if not difficulties and not mythic_only:
        return None

    if mythic_only:
        return 16  # MYTHIC_RAID

    # Priority: Mythic > Mythic Dungeon > Heroic Raid > Heroic 25 > Heroic 10 > Normal Raid > Normal 25 > Normal 10 > Heroic Dungeon > LFR > None
    priority = [16, 23, 15, 6, 5, 14, 4, 3, 2, 17, 0]
    for did in priority:
        if did in difficulties:
            return did

    # Fallback by expansion era
    if expansion:
        idx = EXPANSION_INDEX.get(expansion, 5)
        if idx <= 5:  # Classic through WoD
            if 6 in difficulties or 5 in difficulties:
                return 6  # 25H
            return 4  # 25N
        else:  # Legion+
            return 16  # Mythic

    return difficulties[0] if difficulties else None


# ---------------------------------------------------------------------------
# Merger  (Steps 5-9)
# ---------------------------------------------------------------------------

def merge_data(wago_mounts, blizzard_data, rarity_data, rarity_stats,
               resolved_achievements, instance_data, achievement_reward_map=None):
    """Merge all sources into a unified mount database."""
    print("\n[Merge] Combining all sources...")
    # Unpack achievement reward maps for fallback name-based lookup
    _ach_exact = {}
    _ach_norm = {}
    if achievement_reward_map:
        _ach_exact, _ach_norm = achievement_reward_map

    # Build blizzard lookup by name (since mount IDs differ from spellIDs)
    blizzard_by_name = {}
    for mid, data in blizzard_data.items():
        name_lower = data["name"].lower()
        blizzard_by_name[name_lower] = data

    # Build lowercase instance name set for source text matching
    instance_names_lower = {k.lower(): k for k in instance_data.keys()}

    # Pre-compute the set of all instance names that appear as raid targets in
    # BOSS_TO_INSTANCE.  These are known raid instances and must never be
    # downgraded to dungeon_drop even if their boss count is low.
    RAID_INSTANCE_NAMES = {v for v in BOSS_TO_INSTANCE.values() if v is not None}

    merged = {}

    for spell_id, wago in wago_mounts.items():
        entry = {
            "spellID": spell_id,
            "name": wago["name"],
        }

        # ---- Rarity data (drop rates, NPC IDs, + new fields) ----
        rarity = rarity_data.get(spell_id)
        if rarity:
            entry["dropChance"] = rarity["dropChance"]
            entry["sourceType"] = rarity["sourceType"]
            entry["expansion"] = rarity["expansion"]
            if rarity["npcIDs"]:
                entry["npcIDs"] = rarity["npcIDs"]
            if rarity["itemID"]:
                entry["itemID"] = rarity["itemID"]
            if rarity["mythicOnly"]:
                entry["mythicOnly"] = True

            # Step 1 new fields from Rarity
            if rarity.get("lockBossName"):
                entry["lockBossName"] = rarity["lockBossName"]
            if rarity.get("difficulties"):
                entry["difficulties"] = rarity["difficulties"]
            if rarity.get("mapIDs"):
                entry["mapIDs"] = rarity["mapIDs"]
            if rarity.get("encounterNames"):
                entry["encounterNames"] = rarity["encounterNames"]

        # ---- Blizzard API data (authoritative source type) ----
        blizz = blizzard_by_name.get(wago["name"].lower())
        if blizz:
            blizz_type = blizz["sourceType"]
            # If we have Rarity data with a more specific type, keep it
            # Otherwise use Blizzard's authoritative type
            if "sourceType" not in entry or entry["sourceType"] == "unknown":
                entry["sourceType"] = blizz_type
            # For DROP mounts, Blizzard says DROP but doesn't say raid vs dungeon
            # Keep Rarity's more specific classification if available
            if blizz.get("faction"):
                entry["faction"] = blizz["faction"]

            # Step 2: class/race restrictions and shouldExclude
            if blizz.get("classRestrictions"):
                entry["classRestrictions"] = blizz["classRestrictions"]
            if blizz.get("raceRestrictions"):
                entry["raceRestrictions"] = blizz["raceRestrictions"]
            if blizz.get("shouldExclude"):
                entry["shouldExclude"] = True

        # Distinguish dungeon_drop from raid_drop using instance data.
        # Blizzard API says "DROP" for both; Rarity says "BOSS" for both.
        # Only reclassify as dungeon_drop when the resolved instance is confirmed to
        # be a 5-man dungeon: bossCount <= 5 AND the instance is NOT a raid instance.
        # Raids like Eye of Eternity (1 boss) or Vault of Archavon (4 bosses) must
        # keep their "raid_drop" type so time-gate stays "weekly".
        #
        # Strategy: only downgrade to dungeon_drop when the resolved instance
        # is NOT reachable via BOSS_TO_INSTANCE (i.e. no raid boss maps to it) AND
        # the boss count is <= 5.  This keeps small raids (Eye of Eternity,
        # Vault of Archavon, etc.) as raid_drop with "weekly" time-gate.
        if entry.get("sourceType") == "raid_drop":
            lock_inst = entry.get("lockoutInstanceName")
            boss_name = (rarity or {}).get("lockBossName")
            if not lock_inst and boss_name:
                lock_inst = BOSS_TO_INSTANCE.get(boss_name)
            if lock_inst and lock_inst in instance_data:
                is_known_raid = lock_inst in RAID_INSTANCE_NAMES
                if not is_known_raid and instance_data[lock_inst].get("bossCount", 99) <= 5:
                    entry["sourceType"] = "dungeon_drop"

        # ---- Step 4: Achievement ID resolution ----
        ach_id = resolved_achievements.get(spell_id)
        if not ach_id and blizz and blizz.get("sourceType") == "achievement":
            # Blizzard API confirms this is an achievement mount but wago blizzSourceType
            # may differ — try a direct name lookup against the achievement reward map.
            mount_name = wago.get("name", "").strip()
            if mount_name and _ach_exact:
                ach_id = _ach_exact.get(mount_name.lower())
                if not ach_id:
                    norm = _normalize_mount_name(mount_name)
                    ach_id = _ach_norm.get(norm)
        if ach_id:
            entry["achievementID"] = ach_id

        # ---- Expansion: use Rarity's file-based expansion if present,
        #      otherwise use the 3-layer infer_expansion strategy ----
        if "expansion" not in entry or entry["expansion"] is None:
            entry["expansion"] = infer_expansion(spell_id, rarity, wago, instance_data)

        # ---- Source type from wago.tools enum if still missing ----
        # Wago SourceTypeEnum: 0=drop/unknown, 1=quest/class, 2=vendor,
        # 3=profession, 5=achievement, 6=event, 7=promotion, 8=TCG,
        # 9=store, 10=rare, 11=misc/promo
        if "sourceType" not in entry:
            wago_source_map = {
                0: "world_drop", 1: "quest_chain", 2: "vendor",
                3: "profession", 5: "achievement", 6: "event",
                7: "promotion", 8: "promotion", 9: "promotion", 10: "world_drop",
                11: "promotion",
            }
            entry["sourceType"] = wago_source_map.get(
                wago.get("blizzSourceType", 0), "unknown"
            )

        # ---- Step 7: Resolve lockoutInstanceName ----
        if not entry.get("lockoutInstanceName"):
            # 1. Match rarity lockBossName against BOSS_TO_INSTANCE
            boss_name = entry.get("lockBossName") or (rarity or {}).get("lockBossName")
            if boss_name:
                inst = BOSS_TO_INSTANCE.get(boss_name)
                if inst:
                    entry["lockoutInstanceName"] = inst
                    # Inherit expansion from InstanceData if not already set
                    if not entry.get("expansion") and inst in instance_data:
                        entry["expansion"] = instance_data[inst].get("expansion")

            # 2. Match encounterNames against BOSS_TO_INSTANCE
            if not entry.get("lockoutInstanceName"):
                enc_names = entry.get("encounterNames") or (rarity or {}).get("encounterNames") or []
                for enc in enc_names:
                    inst = BOSS_TO_INSTANCE.get(enc)
                    if inst:
                        entry["lockoutInstanceName"] = inst
                        if not entry.get("expansion") and inst in instance_data:
                            entry["expansion"] = instance_data[inst].get("expansion")
                        break

            # 3. Match wago sourceText against known instance names from InstanceData
            if not entry.get("lockoutInstanceName"):
                src_text_lower = wago.get("sourceText", "").lower()
                if src_text_lower:
                    for inst_lower, inst_name in instance_names_lower.items():
                        if inst_lower in src_text_lower:
                            entry["lockoutInstanceName"] = inst_name
                            if not entry.get("expansion") and inst_name in instance_data:
                                entry["expansion"] = instance_data[inst_name].get("expansion")
                            break

        # ---- Step 8: Derive difficultyID ----
        difficulties = entry.get("difficulties") or (rarity or {}).get("difficulties") or []
        mythic_only = entry.get("mythicOnly", False)
        diff_id = derive_difficulty_id(difficulties, entry.get("expansion"), mythic_only)
        if diff_id is not None:
            entry["difficultyID"] = diff_id

        # ---- Player rarity from Data for Azeroth ----
        mount_id = wago.get("mountID", 0)
        if mount_id in rarity_stats:
            entry["rarity"] = round(rarity_stats[mount_id], 1)

        # ---- Refine source type using wago sourceText hints ----
        # Applied after all source merging but before derived fields and skip filter
        entry["sourceType"] = refine_source_type_from_text(
            entry.get("sourceType", "unknown"),
            wago.get("sourceText", ""),
        )

        # ---- Derived fields ----
        src = entry.get("sourceType", "unknown")
        exp = entry.get("expansion")

        # Bug 2 fix: Use InstanceData soloMinutes when available; fall back to
        # the generic expansion-age formula only when no instance match exists.
        lock_inst = entry.get("lockoutInstanceName")
        if lock_inst and lock_inst in instance_data:
            entry["timePerAttempt"] = instance_data[lock_inst].get(
                "soloMinutes", get_time_per_attempt(src, exp)
            )
        else:
            entry["timePerAttempt"] = get_time_per_attempt(src, exp)

        entry["timeGate"] = get_time_gate(src, exp)
        entry["groupRequirement"] = get_group_requirement(src, exp)

        # Bug 3 fix: Use median formula for expectedAttempts (matches ScoringEngine).
        # Median = ceil(log(0.5) / log(1 - p)), not mean (1/p).
        dc = entry.get("dropChance")
        if dc and 0 < dc < 1:
            entry["expectedAttempts"] = min(
                10000, math.ceil(math.log(0.5) / math.log(1 - dc))
            )
        elif dc and dc >= 1.0:
            entry["expectedAttempts"] = 1

        # Skip mounts with no useful data
        if entry.get("sourceType") in ("unknown", "promotion", "trading_post"):
            continue

        merged[spell_id] = entry

    # ---- Step 5: Apply curated overrides LAST (highest priority) ----
    for spell_id, overrides in CURATED_OVERRIDES.items():
        if spell_id in merged:
            for key, value in overrides.items():
                if value is None:
                    # Explicit None = remove the field
                    merged[spell_id].pop(key, None)
                else:
                    merged[spell_id][key] = value
            # Re-derive expectedAttempts if dropChance was overridden.
            # Use median formula (matches ScoringEngine).
            dc = merged[spell_id].get("dropChance")
            if dc and 0 < dc < 1:
                merged[spell_id]["expectedAttempts"] = min(
                    10000, math.ceil(math.log(0.5) / math.log(1 - dc))
                )
            elif dc and dc >= 1.0:
                merged[spell_id]["expectedAttempts"] = 1
            # Also re-derive timePerAttempt using InstanceData soloMinutes when
            # lockoutInstanceName was set via a curated override.
            lock_inst = merged[spell_id].get("lockoutInstanceName")
            src = merged[spell_id].get("sourceType", "unknown")
            exp = merged[spell_id].get("expansion")
            if lock_inst and lock_inst in instance_data:
                merged[spell_id]["timePerAttempt"] = instance_data[lock_inst].get(
                    "soloMinutes", get_time_per_attempt(src, exp)
                )
            # Re-derive timeGate and groupRequirement to pick up updated sourceType,
            # but only if the override did NOT explicitly set them.
            if "timeGate" not in overrides:
                merged[spell_id]["timeGate"] = get_time_gate(src, exp)
            if "groupRequirement" not in overrides:
                merged[spell_id]["groupRequirement"] = get_group_requirement(src, exp)

    print(f"  Merged database: {len(merged)} mounts")
    return merged


# ---------------------------------------------------------------------------
# Lua Generator  (Step 9: Enhanced output)
# ---------------------------------------------------------------------------

def generate_lua(merged, output_path):
    """Generate the MountDB_Generated.lua file."""
    print(f"\n[Generate] Writing {output_path}...")

    lines = []
    lines.append("-- Auto-generated by tools/build_mountdb.py")
    lines.append(f"-- Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    lines.append("-- Sources: Blizzard API, Rarity addon DB, wago.tools, Data for Azeroth")
    lines.append("-- DO NOT EDIT MANUALLY - re-run build_mountdb.py to update")
    lines.append("")
    lines.append("local addonName, FB = ...")
    lines.append("FB.MountDB_Generated = {}")
    lines.append("")
    lines.append("local db = FB.MountDB_Generated")
    lines.append("")

    # Sort by spellID for stable output
    for spell_id in sorted(merged.keys()):
        entry = merged[spell_id]
        name = entry.get("name", "Unknown")

        lines.append(f"db[{spell_id}] = {{ -- {name}")

        # sourceType (required)
        src = entry.get("sourceType", "unknown")
        lines.append(f'    sourceType = "{src}",')

        # dropChance
        dc = entry.get("dropChance")
        if dc is not None:
            if dc >= 0.01:
                lines.append(f"    dropChance = {dc:.4f},")
            else:
                lines.append(f"    dropChance = {dc:.6f},")

        # expansion
        exp = entry.get("expansion")
        if exp:
            lines.append(f'    expansion = "{exp}",')

        # timeGate
        tg = entry.get("timeGate", "none")
        lines.append(f'    timeGate = "{tg}",')

        # groupRequirement
        gr = entry.get("groupRequirement", "solo")
        lines.append(f'    groupRequirement = "{gr}",')

        # timePerAttempt
        tpa = entry.get("timePerAttempt", 10)
        lines.append(f"    timePerAttempt = {tpa},")

        # expectedAttempts
        ea = entry.get("expectedAttempts")
        if ea:
            lines.append(f"    expectedAttempts = {ea},")

        # npcIDs
        npcs = entry.get("npcIDs", [])
        if npcs:
            npc_str = ", ".join(str(n) for n in npcs)
            lines.append(f"    npcIDs = {{ {npc_str} }},")

        # itemID
        item_id = entry.get("itemID")
        if item_id:
            lines.append(f"    itemID = {item_id},")

        # rarity (player ownership %)
        rarity = entry.get("rarity")
        if rarity is not None:
            lines.append(f"    rarity = {rarity},")

        # faction restriction
        faction = entry.get("faction")
        if faction:
            lines.append(f'    faction = "{faction}",')

        # mythicOnly flag
        if entry.get("mythicOnly"):
            lines.append("    mythicOnly = true,")

        # Step 9: New fields

        # achievementID
        ach_id = entry.get("achievementID")
        if ach_id:
            lines.append(f"    achievementID = {ach_id},")

        # lockoutInstanceName
        lock_inst = entry.get("lockoutInstanceName")
        if lock_inst:
            lines.append(f'    lockoutInstanceName = "{lock_inst}",')

        # difficultyID
        diff_id = entry.get("difficultyID")
        if diff_id is not None:
            lines.append(f"    difficultyID = {diff_id},")

        # lockoutScope (only if not "character" — character is the default)
        lock_scope = entry.get("lockoutScope")
        if lock_scope and lock_scope != "character":
            lines.append(f'    lockoutScope = "{lock_scope}",')

        # classRestrictions
        class_restrict = entry.get("classRestrictions")
        if class_restrict:
            classes_str = ", ".join(f'"{c}"' for c in class_restrict)
            lines.append(f"    classRestrictions = {{ {classes_str} }},")

        # raceRestrictions
        race_restrict = entry.get("raceRestrictions")
        if race_restrict:
            races_str = ", ".join(f'"{r}"' for r in race_restrict)
            lines.append(f"    raceRestrictions = {{ {races_str} }},")

        # mapIDs
        map_ids = entry.get("mapIDs")
        if map_ids:
            maps_str = ", ".join(str(m) for m in map_ids)
            lines.append(f"    mapIDs = {{ {maps_str} }},")

        # shouldExclude
        if entry.get("shouldExclude"):
            lines.append("    shouldExclude = true,")

        lines.append("}")
        lines.append("")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines), encoding="utf-8")

    print(f"  Generated {len(merged)} mount entries")
    print(f"  Output: {output_path}")


# ---------------------------------------------------------------------------
# Step 10: Quality Report
# ---------------------------------------------------------------------------

def print_quality_report(merged):
    """Print data quality report."""
    total = len(merged)
    print("\n" + "=" * 60)
    print("DATA QUALITY REPORT")
    print("=" * 60)

    # Farmable subset: exclude mounts flagged as unobtainable/excluded
    farmable = {k: v for k, v in merged.items() if not v.get("shouldExclude")}
    excluded_count = total - len(farmable)
    print(f"\nFarmable mounts (excluding unobtainable): {len(farmable)}/{total}")
    if excluded_count:
        print(f"  (shouldExclude mounts: {excluded_count} — removed/store/unobtainable)")

    fields = [
        ("sourceType", lambda e: e.get("sourceType") not in (None, "unknown")),
        ("expansion", lambda e: e.get("expansion") is not None),
        ("dropChance", lambda e: e.get("dropChance") is not None),
        ("rarity", lambda e: e.get("rarity") is not None),
        ("npcIDs", lambda e: bool(e.get("npcIDs"))),
        ("itemID", lambda e: e.get("itemID") is not None),
        ("achievementID", lambda e: e.get("achievementID") is not None),
        ("lockoutInstanceName", lambda e: e.get("lockoutInstanceName") is not None),
        ("difficultyID", lambda e: e.get("difficultyID") is not None),
        ("mapIDs", lambda e: bool(e.get("mapIDs"))),
    ]

    print(f"\n{'Field':<25} {'Count':>6} {'%':>6}")
    print("-" * 40)
    for name, check in fields:
        count = sum(1 for e in merged.values() if check(e))
        pct = (count / total * 100) if total else 0
        print(f"{name:<25} {count:>6} {pct:>5.1f}%")

    # Gap analysis (uses farmable subset for meaningful denominators)
    print("\n--- Gap Analysis (farmable mounts only) ---")

    # Achievement mounts without ID
    ach_mounts = [e for e in farmable.values() if e.get("sourceType") == "achievement"]
    ach_with_id = [e for e in ach_mounts if e.get("achievementID")]
    print(f"Achievement mounts with ID: {len(ach_with_id)}/{len(ach_mounts)}")

    # Raid/dungeon drops without dropChance/lockout
    raid_drops = [e for e in farmable.values() if e.get("sourceType") in ("raid_drop", "dungeon_drop")]
    raid_with_dc = [e for e in raid_drops if e.get("dropChance")]
    raid_with_lock = [e for e in raid_drops if e.get("lockoutInstanceName")]
    raid_with_diff = [e for e in raid_drops if e.get("difficultyID")]
    print(f"Raid/dungeon drops with dropChance: {len(raid_with_dc)}/{len(raid_drops)}")
    print(f"Raid/dungeon drops with lockoutInstanceName: {len(raid_with_lock)}/{len(raid_drops)}")
    print(f"Raid/dungeon drops with difficultyID: {len(raid_with_diff)}/{len(raid_drops)}")

    # Source type breakdown for farmable mounts
    print("\n--- Source type breakdown (farmable) ---")
    by_source = {}
    for e in farmable.values():
        st = e.get("sourceType", "unknown")
        by_source[st] = by_source.get(st, 0) + 1
    for st, cnt in sorted(by_source.items(), key=lambda x: -x[1]):
        print(f"  {st}: {cnt}")

    # Mounts without expansion by sourceType
    no_exp = [e for e in farmable.values() if not e.get("expansion")]
    if no_exp:
        by_type = {}
        for e in no_exp:
            st = e.get("sourceType", "unknown")
            by_type[st] = by_type.get(st, 0) + 1
        print(f"\nFarmable mounts without expansion ({len(no_exp)} total):")
        for st, cnt in sorted(by_type.items(), key=lambda x: -x[1]):
            print(f"  {st}: {cnt}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("FarmBuddy Mount Database Generator")
    print("=" * 60)

    # Source 1: wago.tools mount index
    wago_mounts = fetch_wago_mounts()

    # Source 2B: wago.tools Achievement DB2 (independent of Blizzard API)
    achievement_reward_map = fetch_blizzard_achievements()

    # Source 2: Blizzard API
    token = get_blizzard_token()
    blizzard_data = fetch_blizzard_mounts(token)

    # Source 3: Rarity addon
    rarity_data = fetch_rarity_data()

    # Source 4: Data for Azeroth
    rarity_stats = fetch_rarity_stats()

    # Reference: InstanceData.lua (Step 6)
    instance_data = parse_instance_data()

    # Resolve achievement IDs (Step 4)
    resolved_achievements = resolve_achievement_ids(wago_mounts, achievement_reward_map)

    # Merge (Steps 5-9)
    merged = merge_data(wago_mounts, blizzard_data, rarity_data, rarity_stats,
                        resolved_achievements, instance_data,
                        achievement_reward_map=achievement_reward_map)

    # Generate Lua (Step 9)
    generate_lua(merged, OUTPUT_FILE)

    # Quality report (Step 10)
    print_quality_report(merged)

    print("\n" + "=" * 60)
    print("DONE!")
    print(f"  Total mounts: {len(merged)}")
    print(f"  With drop rates: {sum(1 for m in merged.values() if m.get('dropChance'))}")
    print(f"  With rarity data: {sum(1 for m in merged.values() if m.get('rarity') is not None)}")
    print(f"  Output file: {OUTPUT_FILE}")
    print("=" * 60)


if __name__ == "__main__":
    main()
