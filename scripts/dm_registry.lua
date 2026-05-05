--
-- Distribution Manager - Registry
-- Global registry for tracking inbound flows to destinations
--

DistributionManagerRegistry = {}
DistributionManagerRegistry.data = {}

function DistributionManagerRegistry.init()
    if DistributionManager.debug then
        print("--- DistributionManagerRegistry.init()")
    end
    DistributionManagerRegistry.data = {}
end

function DistributionManagerRegistry.delete()
    DistributionManagerRegistry.data = {}
end

-- Register a source pushing to a destination
function DistributionManagerRegistry.registerInbound(sourcePoint, destPoint, fillTypeId)
    local destId = NetworkUtil.getObjectId(destPoint)
    local sourceId = NetworkUtil.getObjectId(sourcePoint)

    if DistributionManagerRegistry.data[destId] == nil then
        DistributionManagerRegistry.data[destId] = {}
    end
    if DistributionManagerRegistry.data[destId][fillTypeId] == nil then
        DistributionManagerRegistry.data[destId][fillTypeId] = {
            inboundSources = {},
            lastKnownFillLevel = 0,
            capacity = 0
        }
    end

    DistributionManagerRegistry.data[destId][fillTypeId].inboundSources[sourceId] = true
end

-- Unregister a source from a destination
function DistributionManagerRegistry.unregisterInbound(sourcePoint, destPoint, fillTypeId)
    local destId = NetworkUtil.getObjectId(destPoint)
    local sourceId = NetworkUtil.getObjectId(sourcePoint)

    if DistributionManagerRegistry.data[destId] ~= nil
        and DistributionManagerRegistry.data[destId][fillTypeId] ~= nil then
        DistributionManagerRegistry.data[destId][fillTypeId].inboundSources[sourceId] = nil
    end
end

-- Update fill level tracking for a destination
function DistributionManagerRegistry.updateDestinationLevel(destPoint, fillTypeId)
    local destId = NetworkUtil.getObjectId(destPoint)

    if DistributionManagerRegistry.data[destId] == nil
        or DistributionManagerRegistry.data[destId][fillTypeId] == nil then
        return
    end

    local entry = DistributionManagerRegistry.data[destId][fillTypeId]
    entry.lastKnownFillLevel = destPoint.storage:getFillLevel(fillTypeId)
    entry.capacity = destPoint.storage:getCapacity(fillTypeId)
end

-- Get registered inbound sources for a destination
function DistributionManagerRegistry.getInboundSources(destPoint, fillTypeId)
    local destId = NetworkUtil.getObjectId(destPoint)

    if DistributionManagerRegistry.data[destId] == nil
        or DistributionManagerRegistry.data[destId][fillTypeId] == nil then
        return {}
    end

    local sources = {}
    for sourceId, _ in pairs(DistributionManagerRegistry.data[destId][fillTypeId].inboundSources) do
        table.insert(sources, sourceId)
    end
    return sources
end
