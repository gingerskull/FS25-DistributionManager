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
    -- Use appendedFunction so our data is written AFTER vanilla/PSC stream data.
    ProductionPoint.writeStream = Utils.appendedFunction(
        ProductionPoint.writeStream,
        DistributionManagerProductionHooks.writeStream
    )

    -- Hook readStream (instance method, colon syntax)
    -- Use appendedFunction so our data is read AFTER vanilla/PSC stream data.
    ProductionPoint.readStream = Utils.appendedFunction(
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

    -- Hook career save to trigger custom XML save (proven pattern from PalletSpawnStore)
    if FSCareerMissionInfo ~= nil then
        FSCareerMissionInfo.saveToXMLFile = Utils.overwrittenFunction(
            FSCareerMissionInfo.saveToXMLFile,
            DistributionManagerProductionHooks.onCareerSaveToXMLFile
        )
    end
end

-- Clear vanilla output mode flags for a fill type so that getOutputDistributionMode
-- returns MANAGER correctly. Must be called whenever managerMode is set to true.
function DistributionManagerProductionHooks.clearVanillaModeFlags(productionPoint, fillTypeId)
    productionPoint.outputFillTypeIdsDirectSell[fillTypeId] = nil
    productionPoint.outputFillTypeIdsAutoDeliver[fillTypeId] = nil
    if productionPoint.outputFillTypeIdsStorage ~= nil then
        productionPoint.outputFillTypeIdsStorage[fillTypeId] = nil
    end
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

-- Custom XML save/load (proven PalletSpawnStore pattern)
-- Saves DM rules to distributionManager.xml in the savegame folder.
function DistributionManagerProductionHooks.saveToCustomXML()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return
    end

    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory
    if savegameFolderPath == nil then
        return
    end

    local path = savegameFolderPath .. "/distributionManager.xml"
    local key = "distributionManager"

    local xmlFile = XMLFile.create(key, path, key)
    if xmlFile == nil then
        print("DM ERROR: Failed to create custom XML file at " .. path)
        return
    end

    local index = 0
    local points = g_currentMission.productionChainManager.productionPoints
    if points ~= nil then
        for _, productionPoint in pairs(points) do
            if productionPoint.dmDistributionRules ~= nil then
                local owningPlaceable = productionPoint.owningPlaceable
                local uniqueId = owningPlaceable and owningPlaceable.uniqueId
                if uniqueId ~= nil then
                    for fillTypeId, rule in pairs(productionPoint.dmDistributionRules) do
                        local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillTypeId)
                        if fillTypeName ~= nil then
                            local subKey = string.format(".rule(%d)", index)
                            xmlFile:setString(key .. subKey .. "#placeableUniqueId", tostring(uniqueId))
                            xmlFile:setString(key .. subKey .. "#fillType", fillTypeName)
                            xmlFile:setBool(key .. subKey .. "#managerMode", rule.managerMode == true)
                            xmlFile:setBool(key .. subKey .. "#active", rule.active == true)
                            xmlFile:setString(key .. subKey .. "#mode", rule.mode or "AUTO")
                            xmlFile:setFloat(key .. subKey .. "#tolerance", rule.tolerance or 0.05)
                            if rule.destinations ~= nil then
                                local destStr = DistributionManagerProductionHooks.serializeDestinations(rule.destinations)
                                xmlFile:setString(key .. subKey .. "#destinations", destStr)
                            end
                            index = index + 1
                        end
                    end
                end
            end
        end
    end

    xmlFile:save()
    xmlFile:delete()

    if DistributionManager.debug then
        print(string.format("DM: Saved %d rules to custom XML (%s)", index, path))
    end
end

function DistributionManagerProductionHooks.loadFromCustomXML()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return
    end

    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory
    if savegameFolderPath == nil then
        return
    end

    local path = savegameFolderPath .. "/distributionManager.xml"
    local key = "distributionManager"

    if not fileExists(path) then
        if DistributionManager.debug then
            print("DM: No custom XML file found at " .. path)
        end
        return
    end

    local xmlFile = XMLFile.load(key, path, key)
    if xmlFile == nil then
        print("DM ERROR: Failed to load custom XML file at " .. path)
        return
    end

    local loadedCount = 0
    xmlFile:iterate(key .. ".rule", function(_, entryKey)
        local uniqueId = xmlFile:getString(entryKey .. "#placeableUniqueId")
        local fillTypeName = xmlFile:getString(entryKey .. "#fillType")
        local managerMode = xmlFile:getBool(entryKey .. "#managerMode", false)
        local active = xmlFile:getBool(entryKey .. "#active", false)
        local mode = xmlFile:getString(entryKey .. "#mode", "AUTO")
        local tolerance = xmlFile:getFloat(entryKey .. "#tolerance", 0.05)
        local destinationsStr = xmlFile:getString(entryKey .. "#destinations", "")

        if uniqueId ~= nil and fillTypeName ~= nil then
            local fillTypeId = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
            if fillTypeId ~= nil then
                local productionPoint = DistributionManagerProductionHooks.getProductionPointByUniqueId(uniqueId)
                if productionPoint ~= nil then
                    if productionPoint.dmDistributionRules == nil then
                        productionPoint.dmDistributionRules = {}
                    end
                    productionPoint.dmDistributionRules[fillTypeId] = {
                        managerMode = managerMode,
                        active = active,
                        mode = mode,
                        tolerance = tolerance,
                        destinations = DistributionManagerProductionHooks.deserializeDestinations(destinationsStr)
                    }

                    -- Clear vanilla mode flags so getOutputDistributionMode returns MANAGER
                    if managerMode then
                        DistributionManagerProductionHooks.clearVanillaModeFlags(productionPoint, fillTypeId)
                    end

                    loadedCount = loadedCount + 1
                else
                    if DistributionManager.debug then
                        print("DM WARNING: Could not find production point with uniqueId " .. tostring(uniqueId))
                    end
                end
            end
        end
    end)

    xmlFile:delete()

    if DistributionManager.debug then
        print(string.format("DM: Loaded %d rules from custom XML (%s)", loadedCount, path))
    end
end

function DistributionManagerProductionHooks.getProductionPointByUniqueId(wantedUniqueId)
    if wantedUniqueId == nil then
        return nil
    end
    local wanted = tostring(wantedUniqueId)
    local points = g_currentMission.productionChainManager.productionPoints
    if points == nil then
        return nil
    end
    for _, productionPoint in pairs(points) do
        local owningPlaceable = productionPoint.owningPlaceable
        local uniqueId = owningPlaceable and owningPlaceable.uniqueId
        if uniqueId ~= nil and tostring(uniqueId) == wanted then
            return productionPoint
        end
    end
    return nil
end

function DistributionManagerProductionHooks.onCareerSaveToXMLFile(missionInfo, superFunc, xmlFile, key)
    superFunc(missionInfo, xmlFile, key)
    if g_server ~= nil and g_currentMission ~= nil and g_currentMission.missionInfo == missionInfo then
        DistributionManagerProductionHooks.saveToCustomXML()
    end
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

    -- After loading rules, clear vanilla mode flags for any MANAGER-mode outputs
    -- so that getOutputDistributionMode returns MANAGER correctly even if other
    -- mods (e.g. ProductionStorageControl) defaulted them during load.
    for fillTypeId, rule in pairs(self.dmDistributionRules) do
        if rule.managerMode then
            DistributionManagerProductionHooks.clearVanillaModeFlags(self, fillTypeId)
        end
    end

    return success
end

-- Serialize destinations table to string
function DistributionManagerProductionHooks.serializeDestinations(destinations)
    local parts = {}
    for destId, destInfo in pairs(destinations) do
        local part = string.format("%s:%d:%s:%s:%s",
            tostring(destId),
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
        local destId, enabled, manualPerc, manualAmt, lastSent = string.match(part, "([^:]+):(%d):([^:]*):([^:]*):([^:]*)")
        if destId ~= nil then
            destinations[destId] = {
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
-- appendedFunction: vanilla/PSC data is already written; we only append our extra data.
function DistributionManagerProductionHooks:writeStream(streamId, connection)
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
-- appendedFunction: vanilla/PSC data is already read; we only read our extra data.
function DistributionManagerProductionHooks:readStream(streamId, connection)
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

        -- After stream sync, clear vanilla mode flags for any MANAGER-mode outputs
        -- so that getOutputDistributionMode returns MANAGER correctly.
        for fillTypeId, rule in pairs(self.dmDistributionRules) do
            if rule.managerMode then
                DistributionManagerProductionHooks.clearVanillaModeFlags(self, fillTypeId)
            end
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
        DistributionManagerProductionHooks.clearVanillaModeFlags(self, outputFillTypeId)

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
                local destUniqueId = destPoint.owningPlaceable and destPoint.owningPlaceable.uniqueId
                if destUniqueId ~= nil then
                    local destKey = tostring(destUniqueId)
                    if rule.destinations[destKey] == nil then
                        rule.destinations[destKey] = {
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
end
