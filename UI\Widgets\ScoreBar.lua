local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.Widgets = FB.UI.Widgets or {}

--[[
    Create a visual score breakdown bar showing component contributions.

    @param parent  frame
    @param name    string
    @return widget table - { frame, SetScore(scoreResult) }
--]]
function FB.UI.Widgets:CreateScoreBar(parent, name)
    local widget = {}

    local frame = CreateFrame("Frame", name, parent)
    frame:SetHeight(50)
    widget.frame = frame

    -- Component colors
    local COMPONENT_COLORS = {
        progress = { 0.2, 0.8, 0.2 },  -- Green
        time     = { 0.8, 0.8, 0.2 },  -- Yellow
        gate     = { 0.8, 0.4, 0.2 },  -- Orange
        group    = { 0.8, 0.2, 0.2 },  -- Red
        effort   = { 0.6, 0.2, 0.8 },  -- Purple
    }

    local COMPONENT_LABELS = {
        progress = "Progress",
        time     = "Time/Attempt",
        gate     = "Time-Gating",
        group    = "Group Req",
        effort   = "Total Effort",
    }

    -- Score text
    local scoreLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    scoreLabel:SetPoint("TOPLEFT", 0, 0)
    widget.scoreLabel = scoreLabel

    -- Component bars
    local bars = {}
    local barY = -22

    for _, key in ipairs({"progress", "time", "gate", "group", "effort"}) do
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 0, barY)
        label:SetWidth(80)
        label:SetJustifyH("LEFT")
        label:SetText(COMPONENT_LABELS[key])
        label:SetTextColor(0.7, 0.7, 0.7)

        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("LEFT", label, "RIGHT", 4, 0)
        bg:SetSize(150, 8)
        bg:SetColorTexture(0.15, 0.15, 0.15, 1)

        local fill = frame:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("LEFT", bg, "LEFT", 0, 0)
        fill:SetHeight(8)
        fill:SetWidth(1)
        local c = COMPONENT_COLORS[key]
        fill:SetColorTexture(c[1], c[2], c[3], 0.9)

        local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valueText:SetPoint("LEFT", bg, "RIGHT", 4, 0)
        valueText:SetWidth(40)
        valueText:SetJustifyH("LEFT")

        bars[key] = { label = label, bg = bg, fill = fill, valueText = valueText }
        barY = barY - 14
    end
    widget.bars = bars

    -- Adjust frame height
    frame:SetHeight(math.abs(barY) + 4)

    -- Update display
    function widget:SetScore(scoreResult)
        if not scoreResult then
            scoreLabel:SetText("")
            for _, bar in pairs(bars) do
                bar.fill:SetWidth(1)
                bar.valueText:SetText("")
            end
            return
        end

        local totalScore = scoreResult.score or 0
        scoreLabel:SetText("Score: " .. FB.Utils:ColorByScore(
            FB.Utils:FormatScore(totalScore), totalScore, 300
        ))

        local components = scoreResult.components or {}
        -- LOW-5: Use 150 as the normalization cap instead of 100.
        -- effortScore can reach ~115 (with the 15% unknown-drop penalty),
        -- so a cap of 100 would clip legitimate high values.
        local SCORE_BAR_MAX = 150
        for key, bar in pairs(bars) do
            local value = components[key] or 0
            local ratio = math.min(value / SCORE_BAR_MAX, 1.0)
            bar.fill:SetWidth(math.max(1, 150 * ratio))
            bar.valueText:SetText(string.format("%.0f", value))
        end
    end

    return widget
end
