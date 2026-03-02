local addonName, FB = ...

FB.Async = {}

-- Target frame time budget (ms) for batch processing
-- 16ms = 60fps, we aim to use ~8ms per tick (half a frame)
local TARGET_FRAME_BUDGET_MS = 8

-- Run a batched async operation using coroutines + C_Timer
-- Supports adaptive batch sizing: if batchSize is "auto", dynamically adjusts
-- based on measured work time to stay within frame budget.
--
-- @param items       table   - Array of items to process
-- @param workFunc    function(item) -> result or nil
-- @param batchSize   number|"auto" - Items per frame tick (default 5, "auto" for adaptive)
-- @param onProgress  function(current, total) - Progress callback
-- @param onComplete  function(results) - Completion callback
-- @return handle     table   - { Cancel(), IsRunning(), GetProgress() }
function FB.Async:RunBatched(items, workFunc, batchSize, onProgress, onComplete)
    local adaptive = (batchSize == "auto")
    local currentBatchSize = adaptive and 5 or (batchSize or 5)
    local results = {}
    local cancelled = false
    local total = #items
    local current = 0

    -- Timing function: GetTimePreciseSec is always available in retail WoW (returns seconds).
    -- API-2: prefer it over debugprofile (which returns ms and may be nil in retail).
    local getTime = GetTimePreciseSec or debugprofile or function() return 0 end
    local isMs = (GetTimePreciseSec == nil and debugprofile ~= nil)  -- only ms when falling back to debugprofile

    local co = coroutine.create(function()
        local batchStart = getTime()
        local batchCount = 0

        for i = 1, total do
            if cancelled then return end

            -- LOW-9: When workFunc returns nil, the item is filtered out of results.
            -- onProgress reports the raw item index (i), not the count of accepted results.
            -- So onProgress(current, total) may show 100% even if many items were filtered.
            local ok, result = pcall(workFunc, items[i])
            if ok and result then
                results[#results + 1] = result
            elseif not ok then
                FB:Debug("Async error on item " .. tostring(i) .. ": " .. tostring(result))
            end
            current = i
            batchCount = batchCount + 1

            -- Check if we should yield
            local shouldYield = false
            if adaptive then
                -- Measure elapsed time and yield if over budget
                local elapsed = getTime() - batchStart
                if not isMs then elapsed = elapsed * 1000 end  -- Convert to ms
                if elapsed >= TARGET_FRAME_BUDGET_MS or batchCount >= 50 then
                    -- Adapt batch size based on throughput
                    if elapsed > 0 then
                        local itemsPerMs = batchCount / elapsed
                        currentBatchSize = math.max(2, math.min(50,
                            math.floor(itemsPerMs * TARGET_FRAME_BUDGET_MS * 0.9)
                        ))
                    end
                    shouldYield = true
                end
            else
                shouldYield = (i % currentBatchSize == 0)
            end

            if shouldYield then
                coroutine.yield()
                batchStart = getTime()
                batchCount = 0
            end
        end
    end)

    local ticker
    local completed = false
    ticker = C_Timer.NewTicker(0.01, function()
        if cancelled or coroutine.status(co) == "dead" then
            if ticker then ticker:Cancel() end
            if not cancelled and not completed and onComplete then
                completed = true
                if onProgress then onProgress(total, total) end
                onComplete(results)
            end
            return
        end
        local ok, err = coroutine.resume(co)
        if not ok then
            FB:Debug("Async coroutine error: " .. tostring(err))
            if ticker then ticker:Cancel() end
            return
        end
        if onProgress then
            onProgress(current, total)
        end
    end)

    local handle = {
        Cancel = function(self)
            cancelled = true
            if ticker then ticker:Cancel() end
        end,
        IsRunning = function(self)
            return not cancelled and coroutine.status(co) ~= "dead"
        end,
        GetProgress = function(self)
            return current, total
        end,
    }

    return handle
end
