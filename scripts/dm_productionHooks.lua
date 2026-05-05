--
-- Distribution Manager - Production Hooks
-- Hooks into ProductionPoint for output mode, save/load, and distribution
--

DistributionManagerProductionHooks = {}

function DistributionManagerProductionHooks.init()
    if DistributionManager.debug then
        print("--- DistributionManagerProductionHooks.init()")
    end

    -- Hook savegame XML paths (static method, dot syntax)
    ProductionPoint.registerSavegameXMLPaths = Utils.prependedFunction(
        ProductionPoint.registerSavegameXMLPaths,
        DistributionManagerProductionHooks.registerSavegameXMLPaths
    )

    -- Hook save (instance method, colon syntax)
    ProductionPoint.saveToXMLFile = Utils.appendedFunction(
        ProductionPoint.saveToXMLFile,
        DistributionManagerProductionHooks.saveToXMLFile
    )

    -- Hook load (instance method, colon syntax)
    ProductionPoint.loadFromXMLFile = Utils.overwrittenFunction(
        ProductionPoint.loadFromXMLFile,
        DistributionManagerProductionHooks.loadFromXMLFile
    )

    -- Hook writeStream (instance method, colon syntax)
    ProductionPoint.writeStream = Utils.prependedFunction(
        ProductionPoint.writeStream,
        DistributionManagerProductionHooks.writeStream
    )

    -- Hook readStream (instance method, colon syntax)
    ProductionPoint.readStream = Utils.prependedFunction(
        ProductionPoint.readStream,
        DistributionManagerProductionHooks.readStream
    )

    -- Hook getOutputDistributionMode (instance method, colon syntax)
    ProductionPoint.getOutputDistributionMode = Utils.overwrittenFunction(
        ProductionPoint.getOutputDistributionMode,
        DistributionManagerProductionHooks.getOutputDistributionMode
    )

    -- Hook setOutputDistributionMode (instance method, colon syntax)
    ProductionPoint.setOutputDistributionMode = Utils.overwrittenFunction(
        ProductionPoint.setOutputDistributionMode,
        DistributionManagerProductionHooks.setOutputDistributionMode
    )

    -- Hook updateProduction (instance method, colon syntax)
    ProductionPoint.updateProduction = Utils.overwrittenFunction(
        ProductionPoint.updateProduction,
        DistributionManagerProductionHooks.updateProduction
    )
end

-- Register XML paths for savegame (static method)
function DistributionManagerProductionHooks.registerSavegameXMLPaths(schema, basePath)
    schema:register(XMLValueType.STRING, basePath .. ".dmDistributionRule(?)#fillType", "fillType for distribution rule")
    schema:register(XMLValueType.BOOL, basePath .. ".dmDistributionRule(?)#managerMode", "output is set to manager mode", false)
    schema:register(XMLValueType.BOOL, basePath .. ".dmDistributionRule(?)#active", "distribution is active", false)
    schema:register(XMLValueType.STRING, basePath .. ".dmDistributionRule(?)#mode", "distribution mode (AUTO or MANUAL)")
    schema:register(XMLValueType.FLOAT, basePath .. ".dmDistributionRule(?)#tolerance", "tolerance for auto equalize", 0.05)
    schema:register(XMLValueType.STRING, basePath .. ".dmDistributionRule(?)#destinations", "serialized destinations table")
end

-- Save distribution rules to savegame
-- Colon syntax: self = ProductionPoint instance, xmlFile = xmlFile, key = key
function DistributionManagerProductionHooks:saveToXMLFile(xmlFile, key, usedModNames)
    if self.dmDistributionRules == nil then
        return
    end

    local i = 0
    for fillTypeId, rule in pairs(self.dmDistributionRules) do
        local ruleKey = string.format("%s.dmDistributionRule(%d)", key, i)
        local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillTypeId)
        if fillTypeName ~= nil then
            xmlFile:setValue(ruleKey .. "#fillType", fillTypeName)
            xmlFile:setValue(ruleKey .. "#managerMode", rule.managerMode or false)
            xmlFile:setValue(ruleKey .. "#active", rule.active or false)
            xmlFile:setValue(ruleKey .. "#mode", rule.mode or "AUTO")
            xmlFile:setValue(ruleKey .. "#tolerance", rule.tolerance or 0.05)
            if rule.destinations ~= nil then
                local destStr = DistributionManagerProductionHooks.serializeDestinations(rule.destinations)
                xmlFile:setValue(ruleKey .. "#destinations", destStr)
            end
            i = i + 1
        end
    end
end

-- Load distribution rules from savegame
-- Colon syntax: self = ProductionPoint instance, superFunc = original function
function DistributionManagerProductionHooks:loadFromXMLFile(superFunc, xmlFile, key)
    -- Initialize data structures first
    self.dmDistributionRules = {}

    -- Call original
    local success = superFunc(self, xmlFile, key)

    -- Load our rules
    xmlFile:iterate(key .. ".dmDistributionRule", function(index, ruleKey)
        local fillTypeName = xmlFile:getValue(ruleKey .. "#fillType")
        local managerMode = xmlFile:getValue(ruleKey .. "#managerMode", false)
        local active = xmlFile:getValue(ruleKey .. "#active", false)
        local mode = xmlFile:getValue(ruleKey .. "#mode", "AUTO")
        local tolerance = xmlFile:getValue(ruleKey .. "#tolerance", 0.05)
        local destinationsStr = xmlFile:getValue(ruleKey .. "#destinations", "")

        local fillTypeId = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
        if fillTypeId ~= nil then
            self.dmDistributionRules[fillTypeId] = {
                managerMode = managerMode,
                active = active,
                mode = mode,
                tolerance = tolerance,
                destinations = DistributionManagerProductionHooks.deserializeDestinations(destinationsStr)
            }
        end
    end)

    return success
end

-- Serialize destinations table to string
function DistributionManagerProductionHooks.serializeDestinations(destinations)
    local parts = {}
    for destId, destInfo in pairs(destinations) do
        local part = string.format("%d:%d:%s:%s:%s",
            destId,
            destInfo.enabled and 1 or 0,
            tostring(destInfo.manualPercentage or ""),
            tostring(destInfo.manualAmount or ""),
            tostring(destInfo.lastSentAmount or "")
        )
        table.insert(parts, part)
    end
    return table.concat(parts, ";")
end

-- Deserialize destinations string to table
function DistributionManagerProductionHooks.deserializeDestinations(str)
    local destinations = {}
    if str == nil or str == "" then
        return destinations
    end

    for part in string.gmatch(str, "([^;]+)") do
        local destId, enabled, manualPerc, manualAmt, lastSent = string.match(part, "(%d+):(%d):([^:]*):([^:]*):([^:]*)")
        if destId ~= nil then
            destinations[tonumber(destId)] = {
                enabled = enabled == "1",
                manualPercentage = manualPerc ~= "" and tonumber(manualPerc) or nil,
                manualAmount = manualAmt ~= "" and tonumber(manualAmt) or nil,
                lastSentAmount = lastSent ~= "" and tonumber(lastSent) or 0
            }
        end
    end
    return destinations
end

-- MP: Write stream
-- Colon syntax: self = ProductionPoint instance, streamId = streamId, connection = connection
function DistributionManagerProductionHooks:writeStream(streamId, connection)
    ProductionPoint:superClass().writeStream(self, streamId, connection)
    if not connection:getIsServer() then
        if self.dmDistributionRules ~= nil then
            streamWriteUInt8(streamId, table.size(self.dmDistributionRules))
            for fillTypeId, rule in pairs(self.dmDistributionRules) do
                streamWriteUIntN(streamId, fillTypeId, FillTypeManager.SEND_NUM_BITS)
                streamWriteBool(streamId, rule.managerMode or false)
                streamWriteBool(streamId, rule.active or false)
                streamWriteString(streamId, rule.mode or "AUTO")
                streamWriteFloat32(streamId, rule.tolerance or 0.05)
                local destStr = DistributionManagerProductionHooks.serializeDestinations(rule.destinations or {})
                streamWriteString(streamId, destStr)
            end
        else
            streamWriteUInt8(streamId, 0)
        end
    end
end

-- MP: Read stream
-- Colon syntax: self = ProductionPoint instance, streamId = streamId, connection = connection
function DistributionManagerProductionHooks:readStream(streamId, connection)
    ProductionPoint:superClass().readStream(self, streamId, connection)
    if connection:getIsServer() then
        self.dmDistributionRules = {}
        local numRules = streamReadUInt8(streamId)
        for i = 1, numRules do
            local fillTypeId = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
            local managerMode = streamReadBool(streamId)
            local active = streamReadBool(streamId)
            local mode = streamReadString(streamId)
            local tolerance = streamReadFloat32(streamId)
            local destStr = streamReadString(streamId)
            self.dmDistributionRules[fillTypeId] = {
                managerMode = managerMode,
                active = active,
                mode = mode,
                tolerance = tolerance,
                destinations = DistributionManagerProductionHooks.deserializeDestinations(destStr)
            }
        end
    end
end

-- Overwrite getOutputDistributionMode
-- Colon syntax: self = ProductionPoint instance, superFunc = original function
function DistributionManagerProductionHooks:getOutputDistributionMode(superFunc, outputFillTypeId)
    if self.dmDistributionRules ~= nil and self.dmDistributionRules[outputFillTypeId] ~= nil then
        local rule = self.dmDistributionRules[outputFillTypeId]
        if rule.managerMode then
            return ProductionPoint.OUTPUT_MODE.MANAGER
        end
    end
    return superFunc(self, outputFillTypeId)
end

-- Overwrite setOutputDistributionMode
-- Colon syntax: self = ProductionPoint instance, superFunc = original function
function DistributionManagerProductionHooks:setOutputDistributionMode(superFunc, outputFillTypeId, mode, noEventSend)
    local modeNum = tonumber(mode)

    if modeNum == ProductionPoint.OUTPUT_MODE.MANAGER then
        -- Initialize rule if not exists
        if self.dmDistributionRules == nil then
            self.dmDistributionRules = {}
        end
        local rule = self.dmDistributionRules[outputFillTypeId]
        if rule == nil then
            rule = {
                managerMode = true,
                active = false,
                mode = "AUTO",
                tolerance = 0.05,
                destinations = {}
            }
            self.dmDistributionRules[outputFillTypeId] = rule
        else
            rule.managerMode = true
            rule.active = true
        end
        -- Clear other mode flags for this fill type
        self.outputFillTypeIdsDirectSell[outputFillTypeId] = nil
        self.outputFillTypeIdsAutoDeliver[outputFillTypeId] = nil
        if self.outputFillTypeIdsStorage ~= nil then
            self.outputFillTypeIdsStorage[outputFillTypeId] = nil
        end

        -- Send event
        DistributionManagerOutputModeEvent.sendEvent(self, outputFillTypeId, ProductionPoint.OUTPUT_MODE.MANAGER, noEventSend)
    else
        -- If switching away from MANAGER, keep the rule but mark it dormant
        if self.dmDistributionRules ~= nil and self.dmDistributionRules[outputFillTypeId] ~= nil then
            self.dmDistributionRules[outputFillTypeId].managerMode = false
            self.dmDistributionRules[outputFillTypeId].active = false
        end
        superFunc(self, outputFillTypeId, mode, noEventSend)
    end
end

-- Auto-populate destinations when MANAGER mode is first set
function DistributionManagerProductionHooks.autoPopulateDestinations(self, outputFillTypeId)
    local farmId = self:getOwnerFarmId()
    if farmId == nil or farmId == AccessHandler.EVERYONE then
        return
    end

    local rule = self.dmDistributionRules[outputFillTypeId]
    if rule == nil then
        return
    end

    -- Find all owned production points that accept this fill type as input
    local allPoints = g_currentMission.productionChainManager.productionPoints
    if allPoints == nil then
        return
    end
    for _, destPoint in ipairs(allPoints) do
        if destPoint ~= self and destPoint:getOwnerFarmId() == farmId then
            if destPoint.inputFillTypeIds ~= nil and destPoint.inputFillTypeIds[outputFillTypeId] ~= nil then
                local destId = NetworkUtil.getObjectId(destPoint)
                if destId ~= nil and rule.destinations[destId] == nil then
                    rule.destinations[destId] = {
                        enabled = false,
                        manualPercentage = nil,
                        manualAmount = nil,
                        lastSentAmount = 0
                    }
                end
            end
        end
    end
end

-- Overwrite updateProduction to intercept MANAGER mode outputs
-- Colon syntax: self = ProductionPoint instance, superFunc = original function
function DistributionManagerProductionHooks:updateProduction(superFunc)
    -- Call original update first (produces output into storage)
    superFunc(self)
end
