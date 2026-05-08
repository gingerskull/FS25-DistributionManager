--
-- Distribution Manager - Distribution Settings Dialog
-- Dialog for configuring distribution rules per output
--

DistributionSettingsDialog = {}
local DistributionSettingsDialog_mt = Class(DistributionSettingsDialog, MessageDialog)

DistributionSettingsDialog.BAR_COLOR_ENABLED = {0.0227, 0.5346, 0.8519, 0.95}
DistributionSettingsDialog.BAR_COLOR_FULL = {0.62, 0.76, 0.12, 0.95}
DistributionSettingsDialog.BAR_COLOR_DISABLED = {0.35, 0.35, 0.35, 0.65}
DistributionSettingsDialog.BAR_COLOR_DISABLED_CAP = {0.24, 0.24, 0.24, 0.48}
DistributionSettingsDialog.TEXT_COLOR_ENABLED = {0.82, 0.92, 1.0, 1.0}
DistributionSettingsDialog.TEXT_COLOR_DISABLED = {0.55, 0.55, 0.55, 1.0}
DistributionSettingsDialog.ICON_COLOR = {1, 1, 1, 1}
DistributionSettingsDialog.ROW_ALPHA_ENABLED = 1.0
DistributionSettingsDialog.ROW_ALPHA_DISABLED = 0.42
DistributionSettingsDialog.VISIBLE_ROW_COUNT = 7

function DistributionSettingsDialog.register()
    local dialog = DistributionSettingsDialog.new()
    local path = Utils.getFilename("gui/DistributionSettingsDialog.xml", DistributionManager.dir)
    g_gui:loadGui(path, "DistributionSettingsDialog", dialog)
    DistributionSettingsDialog.INSTANCE = dialog
end

function DistributionSettingsDialog.show(productionPoint, fillTypeId)
    if DistributionSettingsDialog.INSTANCE ~= nil then
        local dialog = DistributionSettingsDialog.INSTANCE
        dialog.productionPoint = productionPoint
        dialog.fillTypeId = fillTypeId
        dialog:updateContent()
        g_gui:showDialog("DistributionSettingsDialog")
    end
end

function DistributionSettingsDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or DistributionSettingsDialog_mt)
    self.productionPoint = nil
    self.fillTypeId = nil
    self.destinations = {}
    self.selectedIndex = 1
    self.workingRule = nil
    return self
end

function DistributionSettingsDialog:onOpen()
    DistributionSettingsDialog:superClass().onOpen(self)

    if self.toggleEnabledButton ~= nil then
        self.toggleEnabledButton:setInputAction(InputAction.MENU_EXTRA_1)
    end
    if self.toggleModeButton ~= nil then
        self.toggleModeButton:setInputAction(InputAction.MENU_EXTRA_2)
    end
end

function DistributionSettingsDialog.clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value or 0))
end

function DistributionSettingsDialog:getSafeText(key, fallback)
    if g_i18n ~= nil and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end

    return fallback
end

function DistributionSettingsDialog:getPointImageFilename(point)
    if point ~= nil and point.owningPlaceable ~= nil and point.owningPlaceable.getImageFilename ~= nil then
        local filename = point.owningPlaceable:getImageFilename()
        if filename ~= nil and filename ~= "" then
            return filename
        end
    end

    return Utils.getFilename("images/menuIcon.dds", DistributionManager.dir)
end

function DistributionSettingsDialog:formatPercent(percent)
    return string.format("%d%%", math.floor((percent or 0) * 100 + 0.5))
end

function DistributionSettingsDialog:formatVolumeText(currentFill, capacity)
    currentFill = currentFill or 0
    capacity = capacity or 0

    if g_i18n ~= nil and g_i18n.formatVolume ~= nil then
        return string.format("%s / %s", g_i18n:formatVolume(currentFill, 0), g_i18n:formatVolume(capacity, 0))
    end

    return string.format("%.0f L / %.0f L", currentFill, capacity)
end

function DistributionSettingsDialog:formatManualText(dest)
    if self.currentMode ~= "MANUAL" then
        return "-"
    end

    if dest.manualAmount ~= nil and dest.manualAmount > 0 then
        return self:formatVolumeText(dest.manualAmount, dest.capacity):match("^[^/]+") or string.format("%.0f L", dest.manualAmount)
    end

    if dest.manualPercentage ~= nil and dest.manualPercentage > 0 then
        return self:formatPercent(dest.manualPercentage)
    end

    return self:getSafeText("dm_manualEqual", "Equal")
end

function DistributionSettingsDialog:setTextColor(element, color)
    if element ~= nil and element.setTextColor ~= nil then
        element:setTextColor(color[1], color[2], color[3], color[4])
    end
end

function DistributionSettingsDialog:setBitmapColor(element, color)
    if element ~= nil and element.setImageColor ~= nil then
        element:setImageColor(nil, color[1], color[2], color[3], color[4])
        if GuiOverlay ~= nil then
            local function applyStateColor(state)
                if state ~= nil then
                    element:setImageColor(state, color[1], color[2], color[3], color[4])
                end
            end

            applyStateColor(GuiOverlay.STATE_NORMAL)
            applyStateColor(GuiOverlay.STATE_SELECTED)
            applyStateColor(GuiOverlay.STATE_FOCUSED)
            applyStateColor(GuiOverlay.STATE_HIGHLIGHTED)
            applyStateColor(GuiOverlay.STATE_PRESSED)
            applyStateColor(GuiOverlay.STATE_DISABLED)
        end
    elseif element ~= nil and element.color ~= nil then
        element.color = {color[1], color[2], color[3], color[4]}
    end
end

function DistributionSettingsDialog:setOverlayColor(overlay, state, color)
    if GuiOverlay ~= nil and overlay ~= nil then
        local overlayColor = GuiOverlay.getOverlayColor(overlay, state)
        if overlayColor ~= nil then
            overlayColor[1] = color[1]
            overlayColor[2] = color[2]
            overlayColor[3] = color[3]
            overlayColor[4] = color[4]
        end
    end
end

function DistributionSettingsDialog:applyOverlayColorStates(overlay, color)
    DistributionSettingsDialog:setOverlayColor(overlay, nil, color)

    if GuiOverlay ~= nil then
        DistributionSettingsDialog:setOverlayColor(overlay, GuiOverlay.STATE_NORMAL, color)
        DistributionSettingsDialog:setOverlayColor(overlay, GuiOverlay.STATE_SELECTED, color)
        DistributionSettingsDialog:setOverlayColor(overlay, GuiOverlay.STATE_FOCUSED, color)
        DistributionSettingsDialog:setOverlayColor(overlay, GuiOverlay.STATE_HIGHLIGHTED, color)
        DistributionSettingsDialog:setOverlayColor(overlay, GuiOverlay.STATE_PRESSED, color)
        DistributionSettingsDialog:setOverlayColor(overlay, GuiOverlay.STATE_DISABLED, color)
    end
end

function DistributionSettingsDialog:setThreePartCapColor(element, color)
    if element ~= nil then
        DistributionSettingsDialog:applyOverlayColorStates(element.startOverlay, color)
        DistributionSettingsDialog:applyOverlayColorStates(element.endOverlay, color)
    end
end

function DistributionSettingsDialog:setElementAlpha(element, alpha)
    if element ~= nil and element.setAlpha ~= nil then
        element:setAlpha(alpha)
    end
end

function DistributionSettingsDialog:updateFillBar(cell, dest)
    local barBg = cell:getAttribute("fillBarBg")
    local bar = cell:getAttribute("fillBar")
    if barBg == nil or bar == nil then
        return
    end

    local percent = DistributionSettingsDialog.clamp(dest.fillPercent, 0, 1)
    local maxWidth = barBg.size ~= nil and barBg.size[1] or bar.size[1]
    local height = bar.size ~= nil and bar.size[2] or 0
    local fillWidth = math.max(0, maxWidth * percent)

    if percent > 0 and fillWidth < height then
        fillWidth = height
    end

    bar:setSize(fillWidth, height)
    bar:setVisible(percent > 0)

    local bgColor = {0, 0, 0, dest.enabled and 0.55 or 0.35}
    DistributionSettingsDialog:setBitmapColor(barBg, bgColor)

    local fillColor
    if not dest.enabled then
        fillColor = DistributionSettingsDialog.BAR_COLOR_DISABLED
    elseif percent >= 0.95 then
        fillColor = DistributionSettingsDialog.BAR_COLOR_FULL
    else
        fillColor = DistributionSettingsDialog.BAR_COLOR_ENABLED
    end

    DistributionSettingsDialog:setBitmapColor(bar, fillColor)
    if not dest.enabled then
        DistributionSettingsDialog:setThreePartCapColor(bar, DistributionSettingsDialog.BAR_COLOR_DISABLED_CAP)
    end
end

function DistributionSettingsDialog:updateContent()
    self.destinations = {}
    self.selectedIndex = 1
    self.workingRule = nil

    if self.productionPoint == nil or self.fillTypeId == nil then
        return
    end

    if self.productionPoint.dmDistributionRules == nil then
        self.productionPoint.dmDistributionRules = {}
    end

    local fillType = g_fillTypeManager:getFillTypeByIndex(self.fillTypeId)
    if self.dialogTitleElement ~= nil then
        local title = g_i18n:getText("dm_dialogTitleProduct")
        if fillType ~= nil then
            self.dialogTitleElement:setText(string.format(title, fillType.title))
        else
            self.dialogTitleElement:setText(g_i18n:getText("dm_dialogTitle"))
        end
    end

    if self.fillTypeIcon ~= nil then
        if fillType ~= nil and fillType.hudOverlayFilename ~= nil and fillType.hudOverlayFilename ~= "" then
            self.fillTypeIcon:setImageFilename(fillType.hudOverlayFilename)
            DistributionSettingsDialog:setBitmapColor(self.fillTypeIcon, DistributionSettingsDialog.ICON_COLOR)
            self.fillTypeIcon:setVisible(true)
        else
            self.fillTypeIcon:setVisible(false)
        end
    end

    if self.productionIcon ~= nil then
        self.productionIcon:setImageFilename(DistributionSettingsDialog:getPointImageFilename(self.productionPoint))
        DistributionSettingsDialog:setBitmapColor(self.productionIcon, DistributionSettingsDialog.ICON_COLOR)
        self.productionIcon:setVisible(true)
    end

    local liveRule = self.productionPoint.dmDistributionRules[self.fillTypeId]
    if liveRule == nil then
        liveRule = {
            active = true,
            mode = "AUTO",
            tolerance = 0.05,
            destinations = {}
        }
        self.productionPoint.dmDistributionRules[self.fillTypeId] = liveRule
    end

    -- Refresh destinations to catch newly bought production points
    DistributionManagerProductionHooks.autoPopulateDestinations(self.productionPoint, self.fillTypeId)

    -- Create a working copy so dialog changes don't affect live state until OK
    self.workingRule = {
        managerMode = liveRule.managerMode,
        active = liveRule.active,
        mode = liveRule.mode,
        tolerance = liveRule.tolerance,
        destinations = {}
    }
    for destId, destInfo in pairs(liveRule.destinations) do
        self.workingRule.destinations[destId] = {
            enabled = destInfo.enabled,
            manualPercentage = destInfo.manualPercentage,
            manualAmount = destInfo.manualAmount,
            lastSentAmount = destInfo.lastSentAmount
        }
    end

    self.currentMode = self.workingRule.mode

    -- Build destination list from working copy
    local farmId = self.productionPoint:getOwnerFarmId()
    local allPoints = g_currentMission.productionChainManager.productionPoints
    if allPoints == nil then
        allPoints = {}
    end

    for destId, destRule in pairs(self.workingRule.destinations) do
        for _, point in ipairs(allPoints) do
            if point:getOwnerFarmId() == farmId then
                local pointUniqueId = point.owningPlaceable and point.owningPlaceable.uniqueId
                if pointUniqueId ~= nil and tostring(pointUniqueId) == tostring(destId) then
                    if point.inputFillTypeIds ~= nil and point.inputFillTypeIds[self.fillTypeId] ~= nil then
                        local currentFill = point.storage:getFillLevel(self.fillTypeId) or 0
                        local capacity = point.storage:getCapacity(self.fillTypeId) or 0
                        local fillPercent = 0
                        if capacity > 0 then
                            fillPercent = DistributionSettingsDialog.clamp(currentFill / capacity, 0, 1)
                        end

                        table.insert(self.destinations, {
                            point = point,
                            id = destId,
                            enabled = destRule.enabled,
                            manualPercentage = destRule.manualPercentage,
                            manualAmount = destRule.manualAmount,
                            currentFill = currentFill,
                            capacity = capacity,
                            fillPercent = fillPercent,
                            imageFilename = DistributionSettingsDialog:getPointImageFilename(point)
                        })
                    end
                    break
                end
            end
        end
    end

    -- Sort by name
    table.sort(self.destinations, function(a, b)
        return a.point:getName() < b.point:getName()
    end)

    self.destinationsList:setDataSource(self)
    self.destinationsList:reloadData()

    if self.noDestinationsText ~= nil then
        self.noDestinationsText:setVisible(#self.destinations == 0)
    end

    if self.destinationsSliderBox ~= nil then
        self.destinationsSliderBox:setVisible(#self.destinations > DistributionSettingsDialog.VISIBLE_ROW_COUNT)
    end

    -- Update mode display
    self:updateModeDisplay()
end

function DistributionSettingsDialog:updateModeDisplay()
    if self.modeText ~= nil then
        local modeStr = self.currentMode == "AUTO" and g_i18n:getText("dm_modeAuto") or g_i18n:getText("dm_modeManual")
        self.modeText:setText(string.format("%s: %s", g_i18n:getText("dm_modeLabel"), modeStr))
    end
end

function DistributionSettingsDialog:onClickOk()
    -- Save working copy back to live rule
    if self.productionPoint ~= nil and self.fillTypeId ~= nil and self.workingRule ~= nil then
        local liveRule = self.productionPoint.dmDistributionRules[self.fillTypeId]
        if liveRule ~= nil then
            liveRule.managerMode = true
            liveRule.active = true
            liveRule.mode = self.workingRule.mode
            liveRule.tolerance = self.workingRule.tolerance

            for _, dest in ipairs(self.destinations) do
                if liveRule.destinations[dest.id] ~= nil then
                    liveRule.destinations[dest.id].enabled = dest.enabled
                    liveRule.destinations[dest.id].manualPercentage = dest.manualPercentage
                    liveRule.destinations[dest.id].manualAmount = dest.manualAmount
                end
            end

            -- Sync to other players in MP
            if g_server ~= nil or g_client ~= nil then
                DistributionManagerRuleUpdateEvent.sendEvent(self.productionPoint, self.fillTypeId, liveRule)
            end
        end
    end

    self.workingRule = nil
    self:close()
end

function DistributionSettingsDialog:onClickBack()
    self.workingRule = nil
    self:close()
end

-- SmoothList data source methods
function DistributionSettingsDialog:getNumberOfItemsInSection(list, section)
    if list == self.destinationsList then
        return #self.destinations
    end
    return 0
end

function DistributionSettingsDialog:populateCellForItemInSection(list, section, index, cell)
    if list == self.destinationsList then
        local dest = self.destinations[index]
        if dest ~= nil then
            local rowAlpha = dest.enabled and DistributionSettingsDialog.ROW_ALPHA_ENABLED or DistributionSettingsDialog.ROW_ALPHA_DISABLED
            DistributionSettingsDialog:setElementAlpha(cell, rowAlpha)

            local icon = cell:getAttribute("icon")
            if icon ~= nil then
                icon:setImageFilename(dest.imageFilename)
                DistributionSettingsDialog:setBitmapColor(icon, DistributionSettingsDialog.ICON_COLOR)
                DistributionSettingsDialog:setElementAlpha(icon, rowAlpha)
                icon:setVisible(dest.imageFilename ~= nil and dest.imageFilename ~= "")
            end

            cell:getAttribute("name"):setText(dest.point:getName())
            cell:getAttribute("volume"):setText(self:formatVolumeText(dest.currentFill, dest.capacity))
            cell:getAttribute("percent"):setText(self:formatPercent(dest.fillPercent))
            cell:getAttribute("manual"):setText(self:formatManualText(dest))

            local enabledText = dest.enabled and g_i18n:getText("dm_destinationEnabled") or g_i18n:getText("dm_destinationDisabled")
            cell:getAttribute("enabled"):setText(enabledText)

            local textColor = dest.enabled and DistributionSettingsDialog.TEXT_COLOR_ENABLED or DistributionSettingsDialog.TEXT_COLOR_DISABLED
            DistributionSettingsDialog:setTextColor(cell:getAttribute("name"), textColor)
            DistributionSettingsDialog:setTextColor(cell:getAttribute("volume"), textColor)
            DistributionSettingsDialog:setTextColor(cell:getAttribute("percent"), textColor)
            DistributionSettingsDialog:setTextColor(cell:getAttribute("enabled"), textColor)
            DistributionSettingsDialog:setTextColor(cell:getAttribute("manual"), textColor)

            self:updateFillBar(cell, dest)
        end
    end
end

function DistributionSettingsDialog:onListSelectionChanged(list, section, index)
    if list == self.destinationsList then
        self.selectedIndex = index
    end
end

function DistributionSettingsDialog:onClickToggleEnabled()
    local dest = self.destinations[self.selectedIndex]
    if dest ~= nil then
        dest.enabled = not dest.enabled
        self.destinationsList:reloadData()
    end
end

function DistributionSettingsDialog:onClickToggleMode()
    if self.workingRule ~= nil then
        self.workingRule.mode = self.workingRule.mode == "AUTO" and "MANUAL" or "AUTO"
        self.currentMode = self.workingRule.mode
        self:updateModeDisplay()
    end
end
