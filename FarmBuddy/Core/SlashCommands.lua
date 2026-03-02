local addonName, FB = ...

SLASH_FARMBUDDY1 = "/fb"
SLASH_FARMBUDDY2 = "/farmbuddy"

SlashCmdList["FARMBUDDY"] = function(input)
    input = (input or ""):lower():trim()

    if input == "" or input == "toggle" then
        FB.UI:Toggle()
    elseif input == "scan" then
        if FB.Mounts and FB.Mounts.Scanner then
            FB:Print("Starting mount scan...")
            FB.Mounts.Scanner:StartScan(
                nil,  -- no progress callback for CLI
                function(results)
                    FB:Print("Scan complete: " .. #results .. " mounts scored.")
                end
            )
        end
    elseif input == "tracker" then
        FB.Tracker:Toggle()
    elseif input == "reset" then
        FB.UI:ResetPosition()
        FB:Print("Window position reset.")
    elseif input == "debug" then
        if FB.db and FB.db.settings then
            FB.db.settings.debug = not FB.db.settings.debug
            FB:Print("Debug mode: " .. (FB.db.settings.debug and "ON" or "OFF"))
        end
    elseif input == "minimap" then
        if FB.MinimapButton then
            FB.MinimapButton:Toggle()
            FB:Print("Minimap button toggled.")
        end
    elseif input:match("^export") then
        local countStr = input:match("^export%s+(%d+)")
        local count = tonumber(countStr) or 10
        if FB.Export then
            FB.Export:ToFrame(count)
        end
    elseif input:match("^chat") then
        local countStr = input:match("^chat%s+(%d+)")
        local count = tonumber(countStr) or 10
        if FB.Export then
            FB.Export:ToChat(count)
        end
    elseif input == "perf" or input == "profile" then
        if FB.Profiler then
            FB.Profiler:Report()
        else
            FB:Print("Profiler not available.")
        end
    elseif input == "test" then
        if FB.TestHarness then
            FB.TestHarness:Run()
        else
            FB:Print("Test harness not available.")
        end
    elseif input == "warband" then
        local summary = FB.CharacterData:GetWarbandSummary()
        FB:Print("Warband Summary:")
        print("  Characters: " .. summary.totalChars)
        print("  Active lockouts: " .. summary.totalLockouts)
        if FB.db and FB.db.characters then
            for charKey, charInfo in pairs(FB.db.characters) do
                local shortName = charKey:match("^(.-)%s*-") or charKey
                local classColor = FB.CLASS_COLORS[charInfo.class] or "FFFFFF"
                local lockoutCount = 0
                if charInfo.lockouts then
                    for _, lockout in pairs(charInfo.lockouts) do
                        if lockout.locked and lockout.resetTime and lockout.resetTime > time() then
                            lockoutCount = lockoutCount + 1
                        end
                    end
                end
                print("  |cFF" .. classColor .. shortName .. "|r: " .. lockoutCount .. " lockouts")
            end
        end
    elseif input == "help" then
        FB:Print("Commands:")
        print("  " .. FB.ADDON_COLOR .. "/fb|r - Toggle main window")
        print("  " .. FB.ADDON_COLOR .. "/fb scan|r - Run mount scan")
        print("  " .. FB.ADDON_COLOR .. "/fb tracker|r - Toggle tracker")
        print("  " .. FB.ADDON_COLOR .. "/fb minimap|r - Toggle minimap button")
        print("  " .. FB.ADDON_COLOR .. "/fb export [N]|r - Export top N mounts (copy/paste window)")
        print("  " .. FB.ADDON_COLOR .. "/fb chat [N]|r - Print top N mounts to chat")
        print("  " .. FB.ADDON_COLOR .. "/fb perf|r - Show performance report")
        print("  " .. FB.ADDON_COLOR .. "/fb warband|r - Show warband lockout summary")
        print("  " .. FB.ADDON_COLOR .. "/fb test|r - Run test harness")
        print("  " .. FB.ADDON_COLOR .. "/fb reset|r - Reset window position")
        print("  " .. FB.ADDON_COLOR .. "/fb debug|r - Toggle debug mode")
    else
        FB:Print("Unknown command. Type " .. FB.ADDON_COLOR .. "/fb help|r for options.")
    end
end
