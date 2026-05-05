--
-- Distribution Manager - Events
-- Multiplayer events for syncing output mode changes and rule updates
--

DistributionManagerEvents = {}

function DistributionManagerEvents.init()
    if DistributionManager.debug then
        print("--- DistributionManagerEvents.init()")
    end

    -- Register the output mode event
    DistributionManagerOutputModeEvent.register()
end

--
-- DistributionManagerOutputModeEvent
-- Sent when output mode is changed to/from MANAGER
--
DistributionManagerOutputModeEvent = {}
local DistributionManagerOutputModeEvent_mt = Class(DistributionManagerOutputModeEvent, Event)

InitEventClass(DistributionManagerOutputModeEvent, "DistributionManagerOutputModeEvent")

function DistributionManagerOutputModeEvent.register()
    -- Event is auto-registered by InitEventClass
end

function DistributionManagerOutputModeEvent.emptyNew()
    local self = Event.new(DistributionManagerOutputModeEvent_mt)
    return self
end

function DistributionManagerOutputModeEvent.new(productionPoint, outputFillTypeId, outputMode)
    local self = DistributionManagerOutputModeEvent.emptyNew()
    self.productionPoint = productionPoint
    self.outputFillTypeId = outputFillTypeId
    self.outputMode = outputMode
    return self
end

function DistributionManagerOutputModeEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.productionPoint)
    streamWriteUIntN(streamId, self.outputFillTypeId, FillTypeManager.SEND_NUM_BITS)
    -- Use 3 bits to support modes 0-4 (MANAGER)
    streamWriteUIntN(streamId, self.outputMode, 3)
end

function DistributionManagerOutputModeEvent:readStream(streamId, connection)
    self.productionPoint = NetworkUtil.readNodeObject(streamId)
    self.outputFillTypeId = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    -- Use 3 bits to support modes 0-4 (MANAGER)
    self.outputMode = streamReadUIntN(streamId, 3)
    self:run(connection)
end

function DistributionManagerOutputModeEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(self, false, connection)
    end

    if self.productionPoint ~= nil then
        self.productionPoint:setOutputDistributionMode(self.outputFillTypeId, self.outputMode, true)
    end
end

function DistributionManagerOutputModeEvent.sendEvent(productionPoint, outputFillTypeId, outputMode, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            g_server:broadcastEvent(DistributionManagerOutputModeEvent.new(productionPoint, outputFillTypeId, outputMode))
        else
            g_client:getServerConnection():sendEvent(DistributionManagerOutputModeEvent.new(productionPoint, outputFillTypeId, outputMode))
        end
    end
end

--
-- DistributionManagerRuleUpdateEvent
-- Sent when distribution rules are modified via UI
--
DistributionManagerRuleUpdateEvent = {}
local DistributionManagerRuleUpdateEvent_mt = Class(DistributionManagerRuleUpdateEvent, Event)

InitEventClass(DistributionManagerRuleUpdateEvent, "DistributionManagerRuleUpdateEvent")

function DistributionManagerRuleUpdateEvent.emptyNew()
    local self = Event.new(DistributionManagerRuleUpdateEvent_mt)
    return self
end

function DistributionManagerRuleUpdateEvent.new(productionPoint, fillTypeId, rule)
    local self = DistributionManagerRuleUpdateEvent.emptyNew()
    self.productionPoint = productionPoint
    self.fillTypeId = fillTypeId
    self.rule = rule
    return self
end

function DistributionManagerRuleUpdateEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.productionPoint)
    streamWriteUIntN(streamId, self.fillTypeId, FillTypeManager.SEND_NUM_BITS)
    streamWriteBool(streamId, self.rule.managerMode == true)
    streamWriteBool(streamId, self.rule.active == true)
    streamWriteString(streamId, self.rule.mode or "AUTO")
    streamWriteFloat32(streamId, self.rule.tolerance or 0.05)
    local destStr = DistributionManagerProductionHooks.serializeDestinations(self.rule.destinations or {})
    streamWriteString(streamId, destStr)
end

function DistributionManagerRuleUpdateEvent:readStream(streamId, connection)
    self.productionPoint = NetworkUtil.readNodeObject(streamId)
    self.fillTypeId = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    local managerMode = streamReadBool(streamId)
    local active = streamReadBool(streamId)
    local mode = streamReadString(streamId)
    local tolerance = streamReadFloat32(streamId)
    local destStr = streamReadString(streamId)

    self.rule = {
        managerMode = managerMode,
        active = active,
        mode = mode,
        tolerance = tolerance,
        destinations = DistributionManagerProductionHooks.deserializeDestinations(destStr)
    }

    self:run(connection)
end

function DistributionManagerRuleUpdateEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(self, false, connection)
    end

    if self.productionPoint ~= nil and self.productionPoint.dmDistributionRules ~= nil then
        self.productionPoint.dmDistributionRules[self.fillTypeId] = self.rule
    end
end

function DistributionManagerRuleUpdateEvent.sendEvent(productionPoint, fillTypeId, rule)
    if g_server ~= nil then
        g_server:broadcastEvent(DistributionManagerRuleUpdateEvent.new(productionPoint, fillTypeId, rule))
    else
        g_client:getServerConnection():sendEvent(DistributionManagerRuleUpdateEvent.new(productionPoint, fillTypeId, rule))
    end
end
