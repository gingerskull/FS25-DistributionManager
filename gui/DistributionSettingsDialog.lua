--
-- Distribution Manager - Distribution Settings Dialog
-- Dialog for configuring distribution rules per output
--

DistributionSettingsDialog = {}
local DistributionSettingsDialog_mt = Class(DistributionSettingsDialog, MessageDialog)

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

function DistributionSettingsDialog:updateContent()
    self.destinations = {}
    self.selectedIndex = 1
    self.workingRule = nil

    if self.productionPoint == nil or self.fillTypeId == nil then
        return
    end

    if self.dialogTitleElement ~= nil then
        self.dialogTitleElement:setText(g_i18n:getText("dm_dialogTitle"))
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
                if NetworkUtil.getObjectId(point) == destId then
                    if point.inputFillTypeIds ~= nil and point.inputFillTypeIds[self.fillTypeId] ~= nil then
                        local currentFill = point.storage:getFillLevel(self.fillTypeId)
                        local capacity = point.storage:getCapacity(self.fillTypeId)
                        local fillPercent = 0
                        if capacity > 0 then
                            fillPercent = currentFill / capacity
                        end

                        table.insert(self.destinations, {
                            point = point,
                            id = destId,
                            enabled = destRule.enabled,
                            manualPercentage = destRule.manualPercentage,
                            manualAmount = destRule.manualAmount,
                            currentFill = currentFill,
                            capacity = capacity,
                            fillPercent = fillPercent
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

    -- Update mode display
    if self.modeText ~= nil then
        local modeStr = self.currentMode == "AUTO" and g_i18n:getText("dm_modeAuto") or g_i18n:getText("dm_modeManual")
        self.modeText:setText(string.format("%s: %s", g_i18n:getText("dm_modeLabel") or "Mode", modeStr))
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
            cell:getAttribute("name"):setText(dest.point:getName())

            local statusText = string.format("%.0f / %.0f (%.0f%%)",
                dest.currentFill, dest.capacity, dest.fillPercent * 100)
            cell:getAttribute("status"):setText(statusText)

            local enabledText = dest.enabled and g_i18n:getText("dm_destinationEnabled") or g_i18n:getText("dm_destinationDisabled")
            cell:getAttribute("enabled"):setText(enabledText)
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
        if self.modeText ~= nil then
            local modeStr = self.currentMode == "AUTO" and g_i18n:getText("dm_modeAuto") or g_i18n:getText("dm_modeManual")
            self.modeText:setText(string.format("%s: %s", g_i18n:getText("dm_modeLabel") or "Mode", modeStr))
        end
    end
end
