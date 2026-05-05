--
-- Distribution Manager - Main
-- Core constants and initialization
--

DistributionManagerMain = {}

-- MANAGER is the new output mode (next after STORE=3 from ProductionStorageControl)
-- We use a high number to avoid conflicts with other mods
ProductionPoint.OUTPUT_MODE.MANAGER = 4

function DistributionManagerMain.init()
    if DistributionManager.debug then
        print("--- DistributionManagerMain.init()")
        print("--- MANAGER output mode registered as: " .. tostring(ProductionPoint.OUTPUT_MODE.MANAGER))
    end
end
