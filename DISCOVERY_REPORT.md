# FarmBuddy Discovery Report

> Generated: 2026-03-01 | Version analyzed: 1.2.0 | Interface: 120001 (The War Within 12.0.1)

## Goal

Make the **"Next Easy Mount"** recommendation tab and the **Achievement recommendation tab** the best on the market. This report documents the full codebase analysis, confirmed bugs, improvement opportunities, and prioritized action plan.

---

## Architecture Overview

**Stack**: Lua (WoW addon API) + Python (offline data generator)

**Pattern**: Modular namespace using `FB` as root table. Each `.lua` file self-registers via `local addonName, FB = ...`. Dependencies flow downward:

```
UI (tabs, widgets)
  -> Scoring (engine, resolvers)
  -> Mounts / Achievements (resolvers, scanners)
  -> Data (MountDB, AchievementDB, InstanceData)
  -> Storage (SavedVars, CharacterData)
  -> Core (Events, Utils, Async, Constants)
```

### Project Structure

```
FarmBuddy/
  FarmBuddy.toc               -- Addon manifest (load order, saved vars)
  Core/
    Init.lua                   -- Namespace creation, player info cache
    Constants.lua              -- Source types, time gates, group sizes, expansions, tabs, colors
    Events.lua                 -- Central event bus, lifecycle
    Utils.lua                  -- Formatting, mount detail builder, UI helpers (1042 lines)
    Async.lua                  -- Coroutine-based batched async runner
    Profiler.lua               -- Performance profiler
    Localization.lua           -- L10n framework (English-only currently)
    SlashCommands.lua          -- /fb, /farmbuddy commands
    MinimapButton.lua          -- Minimap icon
    Tooltips.lua               -- Tooltip hooks
    Notifications.lua          -- In-game notifications
    Export.lua                 -- Data export feature
    TestHarness.lua            -- In-game unit test framework (19KB)
  Data/
    ExpansionData.lua          -- Expansion names/order table
    InstanceData.lua           -- Instance clear time estimates (raids/dungeons)
    MountDB.lua                -- Curated mount database (~80 entries, 1004 lines)
    MountDB_Generated.lua      -- Auto-generated mount DB (~800+ entries, 11823 lines)
    AchievementDB.lua          -- Achievement category defaults + overrides + reward map
  Scoring/
    ProgressResolver.lua       -- Live progress queries (rep, currency, gold, achievement, quest)
    TimeGateResolver.lua       -- Lockout status, daily quest, holiday detection
    ScoringEngine.lua          -- Weighted scoring algorithm (337 lines)
  Mounts/
    MountResolver.lua          -- Resolves mount data from API + databases (1293 lines)
    MountScanner.lua           -- Async mount scanning + filtering
    WeeklyTracker.lua          -- Weekly lockout tracking
  Achievements/
    AchievementResolver.lua    -- Resolves achievement data from API + AchievementDB
    AchievementScanner.lua     -- Async achievement scanning + filtering
    ZoneGrouper.lua            -- Achievement category tree builder + zone mapping
  Storage/
    SavedVars.lua              -- Account/character saved variable management
    CharacterData.lua          -- Lockout tracking, warband sync, alt management
  UI/
    TabManager.lua             -- Tab switching logic
    MainFrame.lua              -- Main addon window (resizable, draggable)
    MountSearchTab.lua         -- Mount search/browse tab
    MountRecommendTab.lua      -- "Next Easy Mount" recommendation tab (PRIMARY)
    AchievementTab.lua         -- Achievement recommendation tab (PRIMARY)
    WeeklyTab.lua              -- Weekly lockout overview
    ExpansionProgressTab.lua   -- Per-expansion mount progress
    SettingsTab.lua            -- User settings
    Tracker.lua                -- Floating pin/tracker widget
    Widgets/
      ScrollList.lua           -- Virtual scroll with rank/icon/name/score/status columns
      ProgressBar.lua          -- Scan progress bar with cancel
      FilterBar.lua            -- Checkbox/dropdown filter bar
      ModelPreview.lua         -- 3D mount model preview
      ScoreBar.lua             -- Score breakdown visualization
  tools/
    build_mountdb.py           -- Python script to generate MountDB_Generated.lua
    .cache/                    -- Blizzard API response cache
```

---

## How the Systems Work

### Mount Recommendation Flow

```
User clicks "Scan Mounts"
  -> MountScanner:StartScan()
  -> Iterates all C_MountJournal.GetMountIDs()
  -> For each: MountResolver:Resolve(mountID) enriches data
  -> ScoringEngine:Score(input) computes score
  -> Results sorted ascending (lower = easier)
  -> Displayed in MountRecommendTab ScrollList
```

**Scoring Algorithm** (ScoringEngine.lua:50-241) — 5 weighted components:

| Component | Range | Description |
|-----------|-------|-------------|
| `progressRemaining` | 0-100 | For guaranteed mounts, scaled by effort. For RNG drops, forced to 0. |
| `timeScore` | 0-25 | Session unpleasantness (long clear = worse). Capped at 60 min. |
| `gateScore` | 0-100 | Time-gating penalty. Log-scaled. Tripled if currently locked. |
| `groupScore` | 0-100 | Group requirement penalty. `(factor - 1) * 25`. |
| `effortScore` | 0-100 | Total expected effort in calendar days. Log-scaled. |

**Weighted sum** with configurable weights (default: progress=1.0, time=1.0, gate=1.5, group=1.2, effort=1.0).

**Multiplicative bonuses**: Available now (25% discount), warband alt (10-20%), instance efficiency (up to 15%), staleness nudge (up to 10%).

**Data Enrichment** (MountResolver:Resolve(), lines 758-955):
1. Get raw Blizzard data via C_MountJournal
2. Check unobtainability (shop, removed, past PvP, collectors edition, BMAH, remix)
3. Look up curated MountDB (priority) then MountDB_Generated (fallback)
4. Resolve live progress for requirements
5. Resolve time-gate status
6. Calculate expected attempts

### Achievement Recommendation Flow

```
User selects category from tree -> clicks "Scan"
  -> AchievementScanner:ScanCategory(categoryID)
  -> Recursively collects achievement IDs from category + subcategories
  -> For each: AchievementResolver:Resolve(achievementID)
  -> ScoringEngine:Score(input)
  -> Sorted by score ascending
  -> Displayed in AchievementTab
```

**Key differences from mount system**:
- Category-scoped (not global) — user must select a category first
- Criteria-based progress via GetAchievementCriteriaInfo()
- Simpler enrichment (no rep/currency/gold parsing)
- Much less curated data (~40 overrides vs ~80 curated + 800+ generated mounts)
- No caching (mount results cached to savedvars with 1-hour staleness)
- No warband awareness or staleness tracking
- Fewer filters (only solo-only, hide-completed, reward-type)

---

## Confirmed Bugs

### BUG-1: Missing PvP filter checkbox
**File**: `UI/MountRecommendTab.lua` lines 47-57
**Problem**: The filter bar adds checkboxes for raid, dungeon, world, rep, currency, quest, achievement, vendor, event, profession — but NOT PvP. However, `MountScanner:FilterResults()` (line 231) checks `filters.showPvP == false`. Since the checkbox is never created, PvP mounts are always shown with no way to hide them. Also missing: Trading Post filter.
**Fix**: Add `showPvP` and `showTradingPost` checkbox items to the filter bar creation in MountRecommendTab.

### BUG-2: Staleness tracking ignores generated DB mounts
**File**: `Storage/CharacterData.lua` lines 246-267
**Problem**: `RecordMountAttempts` only iterates `FB.MountDB.entries` (curated ~80 entries), not `FB.MountDB_Generated`. The vast majority of mounts (~800+) never get staleness tracking, making the staleness nudge in the scoring engine ineffective for most mounts.
**Fix**: Also iterate `FB.MountDB_Generated` entries, or iterate all mount IDs from the scan results.

### BUG-3: Achievement scanner doesn't pass score explanation
**File**: `Achievements/AchievementScanner.lua` line ~134 (compare with `Mounts/MountScanner.lua` line 117)
**Problem**: The AchievementScanner does not include `scoreExplanation` in the result table. Users see no explanation for why an achievement scored as it did, unlike the mount tab which shows a plain-English explanation.
**Fix**: Add `scoreExplanation = scoreResult.scoreExplanation` to the result table construction in AchievementScanner.

### BUG-4: AchievementScanner GetAchievementInfo overload risk
**File**: `Achievements/AchievementScanner.lua` line 134
**Problem**: Uses `GetAchievementInfo(catID, i)` (category+index overload). The fallback to `C_AchievementInfo.GetAchievementIDs` (lines 146-158) only triggers under a narrow condition (`#ids == 0` AND `numAchievements > 0` AND `depth == 0`), which means if the primary method fails silently for some categories, achievements could be missed.
**Fix**: Review and possibly prefer `C_AchievementInfo.GetAchievementIDs` as the primary method, with `GetAchievementInfo(catID, i)` as fallback.

### BUG-5: Async handle methods lack self parameter (latent)
**File**: `Core/Async.lua` lines 97-107
**Problem**: `Cancel`, `IsRunning`, and `GetProgress` are defined as regular functions but called with method syntax (`handle:Cancel()`). This accidentally works because the functions don't use arguments, but is technically incorrect and will break if the implementation ever needs `self`.
**Fix**: Change function definitions to use `self` parameter or change call sites to use `.` syntax.

---

## Issues & Technical Debt

### ISSUE-1: No TWW raid instances in InstanceData
**File**: `Data/InstanceData.lua`
**Impact**: TWW mount clear times and expansion detection fail. Missing: Nerub-ar Palace, Liberation of Undermine, all TWW dungeons.
**Fix**: Add TWW instance entries with boss counts and solo clear time estimates.

### ISSUE-2: Currency/faction/achievement name cache scans thousands of IDs
**File**: `Mounts/MountResolver.lua` lines 268-276
**Impact**: Brute-force scanning currency IDs 1-3000, faction IDs up to 2950, achievement IDs up to 22000 causes noticeable hitch on first resolve.
**Mitigation**: Low priority — only runs once per session.

### ISSUE-3: Achievement detail view far behind mount detail
**File**: `UI/AchievementTab.lua` lines 505-580 vs `Core/Utils.lua:BuildMountDetailLines`
**Impact**: Achievement detail panel is much simpler — no model preview, no warband status, no WoWHead link, no "How to Get" steps, no live progress display.
**Fix**: Enrich achievement detail to match mount detail quality.

### ISSUE-4: No Midnight expansion support
**Files**: `Core/Constants.lua` (has MIDNIGHT), `Data/ExpansionData.lua` (missing), `Data/InstanceData.lua` (missing), `Mounts/MountResolver.lua:GuessExpansion()` (missing keywords)
**Fix**: Add Midnight expansion data, zones, instances, keywords.

### ISSUE-5: Utils.lua is 1042 lines
**File**: `Core/Utils.lua`
**Impact**: `BuildMountDetailLines` and `BuildMountAutoSteps` account for ~600 lines. Should be extracted to `UI/MountDetailBuilder.lua`.

### ISSUE-6: Hardcoded English strings
**Files**: All UI files
**Impact**: `Localization.lua` exists but is unused. Blocks future translation.

### ISSUE-7: No text search in MountRecommendTab
**Impact**: Mount search tab has a search box but recommendation tab only has category filters. Users can't search for a specific mount name within recommendations.

### ISSUE-8: Achievement scanner has no caching
**Impact**: Mount scanner caches to `FB.db.cachedMountScores` with 1-hour staleness. Achievement scanner requires full re-scan every time user switches categories or tabs.

### ISSUE-9: MountResolver:Resolve() returns nil for collected mounts
**File**: `Mounts/MountResolver.lua` line 764
**Impact**: Scoring system can't show "you already have this" context.

### ISSUE-10: ExpansionData.lua missing MIDNIGHT order
**File**: `Data/ExpansionData.lua` line 16 (stops at TWW order=11)

---

## Improvement Opportunities

### Mount Recommendation Tab

| # | Improvement | Impact | Risk | Files Affected |
|---|------------|--------|------|----------------|
| M1 | Auto-scan on tab open (use cached results, fresh if stale) | High | Medium | MountRecommendTab.lua |
| M2 | Add mount name text search filter | High | Low | MountRecommendTab.lua, MountScanner.lua |
| M3 | Add PvP + Trading Post filter toggles (fix BUG-1) | Medium | Low | MountRecommendTab.lua |
| M4 | "Most Efficient Farm Route" — group by instance | Very High | Medium | MountRecommendTab.lua (new section) |
| M5 | "This Week's Priority" view — weekly-locked available mounts only | Very High | Medium | MountRecommendTab.lua (new preset) |
| M6 | Progress bars in scroll list per mount | Medium | Low | ScrollList.lua or MountRecommendTab.lua |
| M7 | Warband awareness for non-raid mounts (daily dungeons, rep, currency) | High | High | CharacterData.lua, MountResolver.lua |
| M8 | Better expansion coverage in curated MountDB | Medium | Low | Data/MountDB.lua |

### Achievement Tab

| # | Improvement | Impact | Risk | Files Affected |
|---|------------|--------|------|----------------|
| A1 | "All Achievements" global scan mode (biggest single improvement) | Very High | Medium | AchievementScanner.lua, AchievementTab.lua |
| A2 | Achievement reward icons in scroll list (mount/title/pet/toy) | High | Low | AchievementTab.lua, ScrollList.lua |
| A3 | Score explanation display (fix BUG-3) | Medium | Low | AchievementScanner.lua, AchievementTab.lua |
| A4 | "Mount-Rewarding Achievements" preset filter | High | Low | AchievementTab.lua, AchievementDB.lua |
| A5 | WoWHead link button (copy from mount tab pattern) | Medium | Low | AchievementTab.lua |
| A6 | Model preview for mount-rewarding achievements | Medium | Low | AchievementTab.lua |
| A7 | Cache achievement scan results to savedvars | High | Medium | AchievementScanner.lua, SavedVars.lua |
| A8 | Enrich detail panel to match mount detail quality | High | Medium | AchievementTab.lua |
| A9 | More curated achievement data (TWW/DF content) | Medium | Low | Data/AchievementDB.lua |

### Scoring Engine

| # | Improvement | Impact | Risk | Files Affected |
|---|------------|--------|------|----------------|
| S1 | "Completability today" score component (surface quick wins) | Very High | Medium | ScoringEngine.lua |
| S2 | Collection milestone proximity bonus (e.g., 498/500 mounts) | High | Medium | ScoringEngine.lua, MountScanner.lua |
| S3 | User-defined exclusion list ("not interested") | High | Medium | SavedVars.lua, MountScanner.lua, AchievementScanner.lua, UI |

### Data Quality

| # | Improvement | Impact | Risk | Files Affected |
|---|------------|--------|------|----------------|
| D1 | Add TWW instances to InstanceData.lua | High | Low | Data/InstanceData.lua |
| D2 | Add Midnight expansion support | Medium | Low | Data/ExpansionData.lua, Data/InstanceData.lua, Constants.lua |
| D3 | Expand curated MountDB (TWW/DF/SL mounts) | Medium | Low | Data/MountDB.lua |
| D4 | Re-run build_mountdb.py with latest data | Low | Low | tools/build_mountdb.py |

---

## Prioritized Action Plan

### Phase 1: Quick Wins (Low Risk, High Impact)

These can be done independently in any order:

1. **Fix BUG-1**: Add PvP + Trading Post filter checkboxes to MountRecommendTab
2. **Fix BUG-2**: Extend staleness tracking to MountDB_Generated entries
3. **Fix BUG-3**: Pass scoreExplanation through AchievementScanner results
4. **Fix BUG-5**: Fix Async handle method signatures
5. **D1**: Add TWW instances to InstanceData.lua
6. **D2**: Add Midnight expansion data
7. **A4**: Add "Mount-Rewarding Achievements" quick filter
8. **A5**: Add WoWHead link button to AchievementTab

### Phase 2: Core Feature Improvements (Medium Risk)

Split into two parallel tracks:

**Track A — Mount Tab:**
- **M1**: Auto-scan on tab open with cached results
- **M2**: Add text search filter to recommendations
- **M5**: "This Week's Priority" view/preset

**Track B — Achievement Tab:**
- **A1**: "All Achievements" global scan mode
- **A3**: Score explanation display
- **A7**: Cache achievement scan results
- **A8**: Enrich detail panel to match mount detail

### Phase 3: Differentiators (Higher Risk, Game Changers)

These make FarmBuddy truly best-in-class:

- **M4**: "Most Efficient Farm Route" grouping by instance
- **S1**: "Completability today" scoring component
- **S2**: Collection milestone proximity bonus
- **S3**: User exclusion list ("not interested")
- **A2**: Achievement reward icons in scroll list
- **A6**: Model preview for mount-rewarding achievements

---

## Key Files Reference

| File | Lines | Role | Risk Level |
|------|-------|------|------------|
| `Scoring/ScoringEngine.lua` | 337 | Core scoring algorithm | **High** — affects all scores |
| `Mounts/MountResolver.lua` | 1293 | Mount data enrichment | **High** — text parsing, hundreds of mounts |
| `Core/Utils.lua` | 1042 | Shared detail builders | **Medium** — shared by multiple tabs |
| `UI/Widgets/ScrollList.lua` | ~300 | Virtual scroll list | **Medium** — used by all tabs |
| `UI/MountRecommendTab.lua` | 616 | Mount recommendation UI | **Low** — isolated tab |
| `UI/AchievementTab.lua` | 581 | Achievement recommendation UI | **Low** — isolated tab |
| `Mounts/MountScanner.lua` | 255 | Mount scan coordinator | **Low** — isolated |
| `Achievements/AchievementScanner.lua` | 207 | Achievement scan coordinator | **Low** — isolated |
| `Data/MountDB.lua` | 1004 | Curated mount data | **Very Low** — lookup only |
| `Data/AchievementDB.lua` | 232 | Achievement metadata | **Very Low** — lookup only |
| `Data/InstanceData.lua` | 203 | Instance clear times | **Very Low** — lookup only |
| `Storage/CharacterData.lua` | ~300 | Lockout/warband tracking | **Medium** — saves data |
| `Storage/SavedVars.lua` | ~200 | Saved variables schema | **Medium** — schema changes need migration |

## Conventions

- **Naming**: PascalCase for modules/methods, camelCase for locals/params, SCREAMING_SNAKE for constants
- **Module pattern**: `FB.Module = {}` with methods as `function FB.Module:Method()`
- **Error handling**: Defensive pcall wrapping of all WoW API calls, nil checks throughout
- **Event system**: Central event bus in Events.lua
- **Async**: Coroutine-based batched processing with adaptive frame budget (8ms target)
- **Data flow**: Resolver -> Scorer -> Scanner -> UI

## Parallel Development Notes

Mount and achievement improvements can be developed simultaneously — they touch different files:
- Mount track: MountRecommendTab.lua, MountScanner.lua, MountResolver.lua, CharacterData.lua
- Achievement track: AchievementTab.lua, AchievementScanner.lua, AchievementResolver.lua, AchievementDB.lua
- Shared (serialize changes): ScoringEngine.lua, ScrollList.lua, SavedVars.lua
