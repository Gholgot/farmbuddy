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
        }

        if (i + 1) % 100 == 0:
            print(f"  Processed {i + 1}/{len(mount_ids)} mounts...")

    print(f"  Got source types for {len(blizzard_data)} mounts")
    return blizzard_data


# ---------------------------------------------------------------------------
# Source 3: Rarity Addon Database
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

        # Extract fields
        for field, pattern in [
            ("chance", r'chance\s*=\s*(\d+)'),
            ("spellId", r'spellId\s*=\s*(\d+)'),
            ("itemId", r'itemId\s*=\s*(\d+)'),
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

        # Check for instance difficulties (mythic raid etc.)
        if "MYTHIC_RAID" in body:
            entry["mythicOnly"] = True

        # wasGuaranteed flag (100% drop that was later nerfed)
        if "wasGuaranteed" in body:
            entry["wasGuaranteed"] = True

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
# Merger
# ---------------------------------------------------------------------------

def merge_data(wago_mounts, blizzard_data, rarity_data, rarity_stats):
    """Merge all sources into a unified mount database."""
    print("\n[Merge] Combining all sources...")

    # Build blizzard lookup by name (since mount IDs differ from spellIDs)
    blizzard_by_name = {}
    for mid, data in blizzard_data.items():
        name_lower = data["name"].lower()
        blizzard_by_name[name_lower] = data

    merged = {}

    for spell_id, wago in wago_mounts.items():
        entry = {
            "spellID": spell_id,
            "name": wago["name"],
        }

        # ---- Rarity data (drop rates, NPC IDs) ----
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

        # ---- Expansion from wago.tools SourceText if not from Rarity ----
        if "expansion" not in entry:
            entry["expansion"] = guess_expansion_from_text(wago.get("sourceText", ""))

        # ---- Source type from wago.tools enum if still missing ----
        if "sourceType" not in entry:
            wago_source_map = {
                0: "unknown", 1: "raid_drop", 2: "quest_chain", 3: "vendor",
                4: "profession", 5: "dungeon_drop", 6: "achievement",
                7: "event", 8: "promotion", 9: "pvp", 10: "unknown",
                11: "world_drop", 12: "trading_post",
            }
            entry["sourceType"] = wago_source_map.get(
                wago.get("blizzSourceType", 0), "unknown"
            )

        # ---- Player rarity from Data for Azeroth ----
        mount_id = wago.get("mountID", 0)
        if mount_id in rarity_stats:
            entry["rarity"] = round(rarity_stats[mount_id], 1)

        # ---- Derived fields ----
        src = entry.get("sourceType", "unknown")
        exp = entry.get("expansion")

        entry["timePerAttempt"] = get_time_per_attempt(src, exp)
        entry["timeGate"] = get_time_gate(src, exp)
        entry["groupRequirement"] = get_group_requirement(src, exp)

        # Calculate expected attempts from drop chance
        dc = entry.get("dropChance")
        if dc and dc > 0:
            entry["expectedAttempts"] = min(10000, round(1.0 / dc))

        # Skip mounts with no useful data
        if entry.get("sourceType") in ("unknown", "promotion", "trading_post"):
            continue

        merged[spell_id] = entry

    print(f"  Merged database: {len(merged)} mounts")
    return merged


def guess_expansion_from_text(text):
    """Guess expansion from sourceText keywords."""
    if not text:
        return None
    lower = text.lower()
    keywords = [
        (["midnight", "quel'thalas", "silvermoon", "gilneas", "lordaeron", "tirisfal", "ghostlands", "eversong"], "MIDNIGHT"),
        (["war within", "khaz algar", "hallowfall", "isle of dorn"], "TWW"),
        (["dragonflight", "dragon isles", "zaralek", "valdrakken"], "DF"),
        (["shadowlands", "maldraxxus", "bastion", "revendreth"], "SL"),
        (["battle for azeroth", "nazjatar", "mechagon", "zandalar"], "BFA"),
        (["legion", "broken isles", "argus", "suramar"], "LEGION"),
        (["draenor", "tanaan", "garrison"], "WOD"),
        (["pandaria", "timeless isle", "throne of thunder"], "MOP"),
        (["cataclysm", "firelands", "dragon soul"], "CATA"),
        (["northrend", "ulduar", "icecrown"], "WOTLK"),
        (["outland", "tempest keep", "karazhan"], "TBC"),
    ]
    for keys, expansion in keywords:
        for key in keys:
            if key in lower:
                return expansion
    return None


# ---------------------------------------------------------------------------
# Lua Generator
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

        lines.append("}")
        lines.append("")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines), encoding="utf-8")

    print(f"  Generated {len(merged)} mount entries")
    print(f"  Output: {output_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("FarmBuddy Mount Database Generator")
    print("=" * 60)

    # Step 1: wago.tools
    wago_mounts = fetch_wago_mounts()

    # Step 2: Blizzard API
    token = get_blizzard_token()
    blizzard_data = fetch_blizzard_mounts(token)

    # Step 3: Rarity addon
    rarity_data = fetch_rarity_data()

    # Step 4: Data for Azeroth
    rarity_stats = fetch_rarity_stats()

    # Step 5: Merge
    merged = merge_data(wago_mounts, blizzard_data, rarity_data, rarity_stats)

    # Step 6: Generate Lua
    generate_lua(merged, OUTPUT_FILE)

    print("\n" + "=" * 60)
    print("DONE!")
    print(f"  Total mounts: {len(merged)}")
    print(f"  With drop rates: {sum(1 for m in merged.values() if m.get('dropChance'))}")
    print(f"  With rarity data: {sum(1 for m in merged.values() if m.get('rarity') is not None)}")
    print(f"  Output file: {OUTPUT_FILE}")
    print("=" * 60)


if __name__ == "__main__":
    main()
