--
-- Distribution Manager - InGameMenu Distribution Manager Page
-- Central overview and management screen
--

InGameMenuDistributionManager = {}
InGameMenuDistributionManager._mt = Class(InGameMenuDistributionManager, TabbedMenuFrameElement)

function InGameMenuDistributionManager.new(i18n, messageCenter)
    local self = InGameMenuDistributionManager:superClass().new(nil, InGameMenuDistributionManager._mt)
    self.name = "InGameMenuDistributionManager"
    self.i18n = i18n
    self.messageCenter = messageCenter
    self.data = {}

    self.backButtonInfo = {
        inputAction = InputAction.MENU_BACK
    }
    self.configureButtonInfo = {
        inputAction = InputAction.MENU_ACTIVATE,
        text = i18n:getText("dm_buttonConfigureDistribution"),
        disabled = true,
        callback = function()
            self:onClickConfigure()
        end
    }

    self:setMenuButtonInfo({
        self.backButtonInfo,
        self.configureButtonInfo
    })

    return self
end

function InGameMenuDistributionManager:delete()
    InGameMenuDistributionManager:superClass().delete(self)
end

function InGameMenuDistributionManager:copyAttributes(src)
    InGameMenuDistributionManager:superClass().copyAttributes(self, src)
    self.i18n = src.i18n
    self.messageCenter = src.messageCenter
end

function InGameMenuDistributionManager:onGuiSetupFinished()
    InGameMenuDistributionManager:superClass().onGuiSetupFinished(self)
    self.distributionTable:setDataSource(self)
    self.distributionTable:setDelegate(self)
end

function InGameMenuDistributionManager:onFrameOpen()
    InGameMenuDistributionManager:superClass().onFrameOpen(self)
    self:updateContent()
    FocusManager:setFocus(self.distributionTable)
end

function InGameMenuDistributionManager:onFrameClose()
    InGameMenuDistributionManager:superClass().onFrameClose(self)
end

function InGameMenuDistributionManager:updateContent()
    self.data = {}

    local farmId = g_currentMission:getFarmId()
    local allPoints = g_currentMission.productionChainManager.productionPoints
    if allPoints == nil then
        return
    end

    for _, point in ipairs(allPoints) do
        if point:getOwnerFarmId() == farmId and point.dmDistributionRules ~= nil then
            for fillTypeId, rule in pairs(point.dmDistributionRules) do
                if rule.active then
                    local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeId)
                    local fillTypeName = fillType ~= nil and fillType.title or "Unknown"
                    local fillTypeIcon = fillType ~= nil and fillType.hudOverlayFilename or ""

                    local numEnabled = 0
                    local numTotal = 0
                    for _, destRule in pairs(rule.destinations) do
                        numTotal = numTotal + 1
                        if destRule.enabled then
                            numEnabled = numEnabled + 1
                        end
                    end

                    table.insert(self.data, {
                        productionPoint = point,
                        productionName = point:getName(),
                        fillTypeId = fillTypeId,
                        fillTypeName = fillTypeName,
                        fillTypeIcon = fillTypeIcon,
                        mode = rule.mode,
                        tolerance = rule.tolerance,
                        numEnabled = numEnabled,
                        numTotal = numTotal
                    })
                end
            end
        end
    end

    -- Sort by production name then fill type name
    table.sort(self.data, function(a, b)
        if a.productionName == b.productionName then
            return a.fillTypeName < b.fillTypeName
        end
        return a.productionName < b.productionName
    end)

    self.distributionTable:reloadData()
    self:updateMenuButtons()
end

function InGameMenuDistributionManager:updateMenuButtons()
    local selected = self.data[self.distributionTable:getSelectedIndexInSection()] ~= nil
    self.configureButtonInfo.disabled = not selected
end

function InGameMenuDistributionManager:onClickConfigure()
    local index = self.distributionTable:getSelectedIndexInSection()
    local item = self.data[index]
    if item ~= nil then
        DistributionSettingsDialog.show(item.productionPoint, item.fillTypeId)
    end
end

function InGameMenuDistributionManager:onListSelectionChanged(list, section, index)
    self:updateMenuButtons()
end

-- SmoothList data source
function InGameMenuDistributionManager:getNumberOfItemsInSection(list, section)
    if list == self.distributionTable then
        return #self.data
    end
    return 0
end

function InGameMenuDistributionManager:populateCellForItemInSection(list, section, index, cell)
    if list == self.distributionTable then
        local item = self.data[index]
        if item ~= nil then
            cell:getAttribute("icon"):setImageFilename(item.fillTypeIcon)
            cell:getAttribute("production"):setText(item.productionName)
            cell:getAttribute("product"):setText(item.fillTypeName)
            cell:getAttribute("mode"):setText(item.mode)
            cell:getAttribute("destinations"):setText(string.format("%d / %d", item.numEnabled, item.numTotal))
        end
    end
end
