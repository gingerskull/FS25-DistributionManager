--
-- FS25 - Distribution Manager
--
-- @Interface: 1.0.0.0
-- @Author: DavidB
-- @Date: 05.05.2026
-- @Version: 0.1.0.0
--

DistributionManager = {}
DistributionManager.dir = g_currentModDirectory
DistributionManager.modName = g_currentModName
DistributionManager.debug = true

-- Source all module files
source(DistributionManager.dir .. "scripts/dm_main.lua")
source(DistributionManager.dir .. "scripts/dm_productionHooks.lua")
source(DistributionManager.dir .. "scripts/dm_distributionEngine.lua")
source(DistributionManager.dir .. "scripts/dm_registry.lua")
source(DistributionManager.dir .. "scripts/dm_events.lua")
source(DistributionManager.dir .. "scripts/dm_ingameMenu.lua")
source(DistributionManager.dir .. "gui/DistributionSettingsDialog.lua")
source(DistributionManager.dir .. "gui/InGameMenuDistributionManager.lua")

function DistributionManager:loadMap()
    if DistributionManager.debug then
        print("--- DistributionManager: loadMap()")
    end

    -- Initialize core systems
    DistributionManagerMain.init()
    DistributionManagerProductionHooks.init()
    DistributionManagerRegistry.init()
    DistributionManagerEngine.init()
    DistributionManagerEvents.init()
    DistributionManagerIngameMenu.init()

    -- Register GUI dialogs
    DistributionSettingsDialog.register()
end

function DistributionManager:deleteMap()
    if DistributionManager.debug then
        print("--- DistributionManager: deleteMap()")
    end
    DistributionManagerRegistry.delete()
    DistributionManagerEngine.delete()
end

function DistributionManager:update(dt)
    -- Main update loop if needed
    DistributionManagerEngine.update(dt)
end

addModEventListener(DistributionManager)
