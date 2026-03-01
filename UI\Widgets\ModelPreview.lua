local addonName, FB = ...

FB.UI = FB.UI or {}
FB.UI.Widgets = FB.UI.Widgets or {}

--[[
    Create a 3D model preview widget for mounts.
    Uses the proper mount display system to show mount models.

    @param parent  frame
    @param name    string
    @return widget table - { frame, SetMount(mountID), SetMountByMountID(mountID), Clear() }
--]]
function FB.UI.Widgets:CreateModelPreview(parent, name)
    local widget = {}

    -- Container with border
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.1, 0.9)
    widget.frame = frame

    -- Use ModelScene for proper mount display (available in modern WoW)
    -- ModelScene handles mount models better than DressUpModel
    local model
    local useModelScene = false

    -- Try to create a PlayerModel (better for display IDs) or fallback to Model
    local ok, modelFrame = pcall(CreateFrame, "PlayerModel", name .. "Model", frame)
    if ok and modelFrame then
        model = modelFrame
    else
        model = CreateFrame("Model", name .. "Model", frame)
    end

    model:SetPoint("TOPLEFT", 4, -4)
    model:SetPoint("BOTTOMRIGHT", -4, 30)

    -- Mouse rotation (only set OnUpdate while actively dragging to save CPU)
    local function onRotateUpdate(self)
        if self.rotating then
            local x = GetCursorPosition()
            local diff = (x - (self.rotateStart or x)) * 0.01
            local facing = self.currentFacing or 0
            facing = facing + diff
            self:SetFacing(facing)
            self.currentFacing = facing
            self.rotateStart = x
        end
    end
    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.rotating = true
            self.rotateStart = GetCursorPosition()
            self:SetScript("OnUpdate", onRotateUpdate)
        end
    end)
    model:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self.rotating = false
            self:SetScript("OnUpdate", nil)  -- Stop running every frame
        end
    end)
    model.currentFacing = 0
    widget.model = model

    -- Mount name label
    local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("BOTTOMLEFT", 6, 8)
    nameLabel:SetPoint("BOTTOMRIGHT", -6, 8)
    nameLabel:SetJustifyH("CENTER")
    nameLabel:SetText("")
    widget.nameLabel = nameLabel

    -- Hint text
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("CENTER")
    hint:SetTextColor(0.5, 0.5, 0.5)
    hint:SetText("Select a mount to preview")
    widget.hint = hint

    -- Display a mount by creatureDisplayInfoID
    function widget:SetMount(creatureDisplayInfoID, mountName)
        if creatureDisplayInfoID and creatureDisplayInfoID > 0 then
            model:ClearModel()
            -- SetDisplayInfo is the correct method for display IDs
            -- SetCreature expects a creatureID (NPC ID), not a display ID
            if model.SetDisplayInfo then
                model:SetDisplayInfo(creatureDisplayInfoID)
            end
            -- Note: SetCreature expects a creatureID (NPC ID), NOT a displayInfoID
            -- so we intentionally skip it as a fallback since passing displayInfoID
            -- to SetCreature would show the wrong model
            model:SetFacing(0)
            model.currentFacing = 0
            -- Try to set a good camera angle
            if model.SetPosition then
                model:SetPosition(0, 0, 0)
            end
            if model.SetCamDistanceScale then
                model:SetCamDistanceScale(1.2)
            end
            nameLabel:SetText(mountName or "")
            hint:Hide()
            model:Show()
        else
            self:Clear()
        end
    end

    -- Display mount by mountID (C_MountJournal mountID)
    function widget:SetMountByMountID(mountID)
        if not mountID then
            self:Clear()
            return
        end

        local name, spellID, icon = C_MountJournal.GetMountInfoByID(mountID)
        if not name then
            self:Clear()
            return
        end

        local creatureDisplayInfoID, descriptionText, sourceText, isSelfMount, mountTypeID, uiModelSceneID =
            C_MountJournal.GetMountInfoExtraByID(mountID)

        if creatureDisplayInfoID and creatureDisplayInfoID > 0 then
            self:SetMount(creatureDisplayInfoID, name)
        else
            self:Clear()
        end
    end

    -- Display mount by spellID
    function widget:SetMountBySpellID(spellID)
        local mountIDs = C_MountJournal.GetMountIDs()
        if not mountIDs then
            self:Clear()
            return
        end

        for _, mountID in ipairs(mountIDs) do
            local mountName, spell = C_MountJournal.GetMountInfoByID(mountID)
            if spell == spellID then
                self:SetMountByMountID(mountID)
                return
            end
        end

        self:Clear()
    end

    -- Clear the preview
    function widget:Clear()
        model:ClearModel()
        model:Hide()
        nameLabel:SetText("")
        hint:Show()
    end

    return widget
end
