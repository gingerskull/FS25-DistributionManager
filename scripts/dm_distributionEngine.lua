--
-- Distribution Manager - Distribution Engine
-- Handles the actual distribution logic (Auto Equalize and Manual modes)
--

DistributionManagerEngine = {}
DistributionManagerEngine.lastUpdateTime = 0
DistributionManagerEngine.updateInterval = 1000 -- ms between distribution checks

function DistributionManagerEngine.init()
    if DistributionManager.debug then
        print("--- DistributionManagerEngine.init()")
    end
end

function DistributionManagerEngine.delete()
end

function DistributionManagerEngine.update(dt)
    DistributionManagerEngine.lastUpdateTime = DistributionManagerEngine.lastUpdateTime + dt
    if DistributionManagerEngine.lastUpdateTime >= DistributionManagerEngine.updateInterval then
        DistributionManagerEngine.lastUpdateTime = 0
        DistributionManagerEngine.distributeAll()
    end
end

-- Distribute outputs for all owned production points with active MANAGER rules
function DistributionManagerEngine.distributeAll()
    if g_server == nil or g_currentMission == nil or g_currentMission.productionChainManager == nil then
        return
    end

    local farmId = g_currentMission:getFarmId()
    if farmId == nil then
        return
    end

    for _, point in ipairs(g_currentMission.productionChainManager.productionPoints) do
        if point:getOwnerFarmId() == farmId then
            if point.dmDistributionRules ~= nil then
                for fillTypeId, rule in pairs(point.dmDistributionRules) do
                    if rule.active then
                        local fillLevel = point.storage:getFillLevel(fillTypeId)
                        if fillLevel > 0 then
                            DistributionManagerEngine.distributeOutput(point, fillTypeId, rule, fillLevel)
                        end
                    end
                end
            end
        end
    end
end

-- Main distribution function called from updateProduction hook
function DistributionManagerEngine.distributeOutput(sourcePoint, fillTypeId, rule, availableAmount)
    if availableAmount <= 0 then
        return
    end

    local farmId = sourcePoint:getOwnerFarmId()
    if farmId == nil or farmId == AccessHandler.EVERYONE then
        return
    end

    -- Resolve destination production points from rule
    local destinations = DistributionManagerEngine.resolveDestinations(rule.destinations, farmId, fillTypeId)
    if #destinations == 0 then
        -- No valid destinations, keep in source (buffer)
        return
    end

    local distributedAmount = 0

    if rule.mode == "AUTO" then
        distributedAmount = DistributionManagerEngine.distributeAuto(sourcePoint, fillTypeId, rule, destinations, availableAmount)
    elseif rule.mode == "MANUAL" then
        distributedAmount = DistributionManagerEngine.distributeManual(sourcePoint, fillTypeId, rule, destinations, availableAmount)
    end

    -- Remove distributed amount from source storage
    if distributedAmount > 0 then
        sourcePoint.storage:setFillLevel(availableAmount - distributedAmount, fillTypeId)
    end
end

-- Resolve destination IDs to actual ProductionPoint objects
function DistributionManagerEngine.resolveDestinations(destRules, farmId, fillTypeId)
    local result = {}
    local allPoints = g_currentMission.productionChainManager.productionPoints
    if allPoints == nil then
        return result
    end

    for destId, destRule in pairs(destRules) do
        if destRule.enabled then
            for _, point in ipairs(allPoints) do
                if point:getOwnerFarmId() == farmId then
                    local pointId = NetworkUtil.getObjectId(point)
                    if pointId == destId then
                        -- Verify it still accepts this fill type
                        if point.inputFillTypeIds ~= nil and point.inputFillTypeIds[fillTypeId] ~= nil then
                            table.insert(result, {
                                point = point,
                                rule = destRule,
                                id = destId
                            })
                        end
                        break
                    end
                end
            end
        end
    end

    return result
end

-- Auto Equalize distribution
function DistributionManagerEngine.distributeAuto(sourcePoint, fillTypeId, rule, destinations, availableAmount)
    local tolerance = rule.tolerance or 0.05
    local totalDistributed = 0

    -- Gather fill percentages
    local destData = {}
    local totalCapacity = 0
    local totalFill = 0

    for _, dest in ipairs(destinations) do
        local point = dest.point
        local currentFill = point.storage:getFillLevel(fillTypeId)
        local capacity = point.storage:getCapacity(fillTypeId)
        local fillPercent = 0
        if capacity > 0 then
            fillPercent = currentFill / capacity
        end

        table.insert(destData, {
            dest = dest,
            currentFill = currentFill,
            capacity = capacity,
            fillPercent = fillPercent,
            freeSpace = math.max(0, capacity - currentFill)
        })

        totalCapacity = totalCapacity + capacity
        totalFill = totalFill + currentFill
    end

    if totalCapacity == 0 then
        return 0
    end

    local avgPercent = totalFill / totalCapacity

    -- Calculate how much each destination needs to reach average
    local totalDeficit = 0
    for _, data in ipairs(destData) do
        -- Only send if below average (with tolerance)
        local targetPercent = avgPercent
        local deficit = (targetPercent - data.fillPercent) * data.capacity
        if deficit > tolerance * data.capacity then
            data.deficit = math.min(deficit, data.freeSpace)
            totalDeficit = totalDeficit + data.deficit
        else
            data.deficit = 0
        end
    end

    if totalDeficit <= 0 then
        -- All destinations are balanced or full.
        -- If there's available output and free space, distribute proportionally to free space.
        local totalFreeSpace = 0
        for _, data in ipairs(destData) do
            totalFreeSpace = totalFreeSpace + data.freeSpace
        end

        if availableAmount > 0 and totalFreeSpace > 0 then
            for _, data in ipairs(destData) do
                if data.freeSpace > 0 then
                    local ratio = data.freeSpace / totalFreeSpace
                    local sendAmount = math.min(availableAmount * ratio, data.freeSpace)

                    if sendAmount > 0 then
                        DistributionManagerEngine.sendToDestination(data.dest.point, fillTypeId, sendAmount)
                        data.dest.rule.lastSentAmount = sendAmount
                        totalDistributed = totalDistributed + sendAmount
                    end
                end
            end
        end
        return totalDistributed
    end

    -- Distribute available amount proportionally to deficits
    local amountToDistribute = math.min(availableAmount, totalDeficit)

    for _, data in ipairs(destData) do
        if data.deficit > 0 then
            local ratio = data.deficit / totalDeficit
            local sendAmount = math.min(amountToDistribute * ratio, data.freeSpace)

            if sendAmount > 0 then
                DistributionManagerEngine.sendToDestination(data.dest.point, fillTypeId, sendAmount)
                data.dest.rule.lastSentAmount = sendAmount
                totalDistributed = totalDistributed + sendAmount
            end
        end
    end

    return totalDistributed
end

-- Manual distribution
function DistributionManagerEngine.distributeManual(sourcePoint, fillTypeId, rule, destinations, availableAmount)
    local totalDistributed = 0
    local remainingAmount = availableAmount

    -- First pass: allocate by manual amounts (caps)
    local allocations = {}
    local totalManualAmount = 0

    for _, dest in ipairs(destinations) do
        local manualAmount = dest.rule.manualAmount
        if manualAmount ~= nil and manualAmount > 0 then
            local currentFill = dest.point.storage:getFillLevel(fillTypeId)
            local remainingCap = math.max(0, manualAmount - currentFill)
            allocations[dest.id] = {
                dest = dest,
                amount = remainingCap,
                type = "amount"
            }
            totalManualAmount = totalManualAmount + remainingCap
        end
    end

    -- If no manual amounts set, fall back to percentages
    if totalManualAmount == 0 then
        local totalPercentage = 0
        for _, dest in ipairs(destinations) do
            local perc = dest.rule.manualPercentage or (1.0 / #destinations)
            totalPercentage = totalPercentage + perc
        end

        for _, dest in ipairs(destinations) do
            local perc = dest.rule.manualPercentage or (1.0 / #destinations)
            local normalizedPerc = perc / totalPercentage
            local sendAmount = availableAmount * normalizedPerc
            local freeSpace = math.max(0, dest.point.storage:getCapacity(fillTypeId) - dest.point.storage:getFillLevel(fillTypeId))
            allocations[dest.id] = {
                dest = dest,
                amount = math.min(sendAmount, freeSpace),
                type = "percentage"
            }
        end
    end

    -- Second pass: distribute
    for id, alloc in pairs(allocations) do
        local sendAmount = math.min(alloc.amount, remainingAmount)

        if sendAmount > 0 then
            DistributionManagerEngine.sendToDestination(alloc.dest.point, fillTypeId, sendAmount)
            alloc.dest.rule.lastSentAmount = sendAmount
            totalDistributed = totalDistributed + sendAmount
            remainingAmount = remainingAmount - sendAmount
        end
    end

    -- If all manual caps reached, buffer remains at source
    return totalDistributed
end

-- Send fill level to a destination production point
function DistributionManagerEngine.sendToDestination(destPoint, fillTypeId, amount)
    if destPoint == nil or destPoint.storage == nil then
        return
    end

    local currentFill = destPoint.storage:getFillLevel(fillTypeId)
    local capacity = destPoint.storage:getCapacity(fillTypeId)
    local freeSpace = capacity - currentFill

    if freeSpace <= 0 then
        return
    end

    local actualAmount = math.min(amount, freeSpace)
    destPoint.storage:setFillLevel(currentFill + actualAmount, fillTypeId)

    if DistributionManager.debug then
        print(string.format("--- DM: Sent %.0f liters of %s to %s",
            actualAmount,
            g_fillTypeManager:getFillTypeNameByIndex(fillTypeId),
            destPoint:getName()))
    end
end
