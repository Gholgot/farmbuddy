local addonName, FB = ...

FB.ZoneGrouper = FB.ZoneGrouper or {}

local GetCategoryList = GetCategoryList
local GetCategoryInfo = GetCategoryInfo

-- Build a tree of achievement categories for the zone dropdown
-- Returns: { { id, name, parentID, children = {} }, ... }
function FB.ZoneGrouper:GetCategoryTree()
    local ok, categories = pcall(GetCategoryList)
    if not ok or not categories then return {}, {} end

    local catMap = {}
    local roots = {}

    -- Build flat map
    for _, catID in ipairs(categories) do
        local catOk, name, parentID, flags = pcall(GetCategoryInfo, catID)
        if catOk then
            catMap[catID] = {
                id = catID,
                name = name or ("Category " .. catID),
                parentID = parentID or -1,
                children = {},
            }
        end
    end

    -- Build tree
    for catID, cat in pairs(catMap) do
        if cat.parentID == -1 or not catMap[cat.parentID] then
            roots[#roots + 1] = cat
        else
            local parent = catMap[cat.parentID]
            parent.children[#parent.children + 1] = cat
        end
    end

    -- Sort roots and children
    local function sortByName(a, b) return a.name < b.name end
    table.sort(roots, sortByName)
    for _, cat in pairs(catMap) do
        table.sort(cat.children, sortByName)
    end

    return roots, catMap
end

-- Get a flat list of all zone/expansion categories suitable for a dropdown
-- Filters to categories that actually have achievements
function FB.ZoneGrouper:GetZoneDropdownList()
    local roots, catMap = self:GetCategoryTree()
    local list = {}

    -- We want expansion-level categories and their zone subcategories
    for _, root in ipairs(roots) do
        -- Add root category
        list[#list + 1] = {
            id = root.id,
            name = root.name,
            depth = 0,
        }
        -- Add children (zones within expansion)
        for _, child in ipairs(root.children) do
            list[#list + 1] = {
                id = child.id,
                name = "  " .. child.name,
                depth = 1,
            }
            -- And grandchildren if any
            for _, grandchild in ipairs(child.children) do
                list[#list + 1] = {
                    id = grandchild.id,
                    name = "    " .. grandchild.name,
                    depth = 2,
                }
            end
        end
    end

    return list
end

-- Get the current player's zone and find matching achievement category
-- Walks up the map hierarchy to find a matching achievement category
function FB.ZoneGrouper:GetCurrentZoneCategory()
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end

    local ok, categories = pcall(GetCategoryList)
    if not ok or not categories then return nil end

    -- Build a name→catID lookup
    local catByName = {}
    for _, catID in ipairs(categories) do
        local catOk, catName = pcall(GetCategoryInfo, catID)
        if catOk and catName then
            catByName[catName] = catID
        end
    end

    -- Walk up the map hierarchy until we find a matching achievement category
    local currentMapID = mapID
    local visited = {}
    while currentMapID and not visited[currentMapID] do
        visited[currentMapID] = true
        local mapInfo = C_Map.GetMapInfo(currentMapID)
        if mapInfo and mapInfo.name then
            local matchID = catByName[mapInfo.name]
            if matchID then
                return matchID, mapInfo.name
            end
            -- Walk up to parent map
            currentMapID = mapInfo.parentMapID
        else
            break
        end
    end

    -- Return zone name even if no category found
    local mapInfo = C_Map.GetMapInfo(mapID)
    return nil, mapInfo and mapInfo.name or nil
end
