local addonName, FB = ...

FB.Profiler = {}

local timers = {}
local stats = {}

-- Start a named timer
function FB.Profiler:Start(name)
    timers[name] = debugprofile and debugprofile() or (GetTimePreciseSec and GetTimePreciseSec() or 0)
end

-- Stop a timer and record the duration
function FB.Profiler:Stop(name)
    local startTime = timers[name]
    if not startTime then return 0 end

    local usingPreciseSec = not debugprofile and GetTimePreciseSec
    local endTime = debugprofile and debugprofile() or (GetTimePreciseSec and GetTimePreciseSec() or 0)
    local elapsed = endTime - startTime
    -- debugprofile() returns milliseconds; GetTimePreciseSec() returns seconds — normalize to ms
    if usingPreciseSec then
        elapsed = elapsed * 1000
    end
    timers[name] = nil

    -- Record stats
    if not stats[name] then
        stats[name] = { count = 0, total = 0, min = 999999, max = 0 }
    end
    local s = stats[name]
    s.count = s.count + 1
    s.total = s.total + elapsed
    if elapsed < s.min then s.min = elapsed end
    if elapsed > s.max then s.max = elapsed end

    -- Auto-log if debug mode and elapsed is significant
    if elapsed > 100 then  -- > 100ms
        FB:Debug(string.format("Profiler: %s took %.1fms", name, elapsed))
    end

    return elapsed
end

-- Get stats for a named operation
function FB.Profiler:GetStats(name)
    return stats[name]
end

-- Print all stats to chat
function FB.Profiler:Report()
    print(FB.ADDON_COLOR .. "FarmBuddy Performance Report|r")
    print("---")

    -- Sort by total time descending
    local sorted = {}
    for name, s in pairs(stats) do
        sorted[#sorted + 1] = { name = name, stats = s }
    end
    table.sort(sorted, function(a, b) return a.stats.total > b.stats.total end)

    for _, entry in ipairs(sorted) do
        local s = entry.stats
        local avg = s.count > 0 and (s.total / s.count) or 0
        print(string.format(
            "  %s: %dx, avg %.1fms, total %.1fms (min %.1f, max %.1f)",
            entry.name, s.count, avg, s.total, s.min, s.max
        ))
    end

    if #sorted == 0 then
        print("  No profiling data collected.")
    end
end

-- Reset all stats
function FB.Profiler:Reset()
    stats = {}
    timers = {}
end

-- Convenience: wrap a function call with profiling
function FB.Profiler:Wrap(name, func, ...)
    self:Start(name)
    local results = { pcall(func, ...) }
    local elapsed = self:Stop(name)
    local ok = table.remove(results, 1)
    if not ok then
        FB:Debug("Profiler: " .. name .. " errored: " .. tostring(results[1]))
        return nil
    end
    return unpack(results)
end
