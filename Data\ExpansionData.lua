local addonName, FB = ...

FB.ExpansionData = {
    -- Expansion key -> { name, order (for sorting), maxLevel at time }
    CLASSIC = { name = "Classic",                   order = 1  },
    TBC     = { name = "The Burning Crusade",       order = 2  },
    WOTLK   = { name = "Wrath of the Lich King",   order = 3  },
    CATA    = { name = "Cataclysm",                 order = 4  },
    MOP     = { name = "Mists of Pandaria",         order = 5  },
    WOD     = { name = "Warlords of Draenor",       order = 6  },
    LEGION  = { name = "Legion",                    order = 7  },
    BFA     = { name = "Battle for Azeroth",        order = 8  },
    SL      = { name = "Shadowlands",               order = 9  },
    DF      = { name = "Dragonflight",              order = 10 },
    TWW     = { name = "The War Within",            order = 11 },
}

-- Get expansion display name
function FB:GetExpansionName(key)
    local data = FB.ExpansionData[key]
    return data and data.name or key
end

-- Get sorted expansion list for dropdowns
function FB:GetExpansionList()
    local list = {}
    for key, data in pairs(FB.ExpansionData) do
        list[#list + 1] = { key = key, name = data.name, order = data.order }
    end
    table.sort(list, function(a, b) return a.order < b.order end)
    return list
end
