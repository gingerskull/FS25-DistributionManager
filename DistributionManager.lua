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

    self.dmHasLoaded = false
end

function DistributionManager:deleteMap()
    if DistributionManager.debug then
        print("--- DistributionManager: deleteMap()")
    end
    DistributionManagerRegistry.delete()
    DistributionManagerEngine.delete()
    self.dmHasLoaded = false
end

function DistributionManager:update(dt)
    -- Main update loop if needed
    DistributionManagerEngine.update(dt)

    -- Load custom XML after production points are available (PalletSpawnStore pattern)
    if g_server ~= nil and not self.dmHasLoaded then
        local mission = g_currentMission
        if mission ~= nil
            and mission.productionChainManager ~= nil
            and mission.missionInfo ~= nil then

            local points = mission.productionChainManager.productionPoints
            if points ~= nil then
                local hasAny = false
                for _ in pairs(points) do
                    hasAny = true
                    break
                end

                if hasAny then
                    self.dmHasLoaded = true
                    DistributionManagerProductionHooks.loadFromCustomXML()
                end
            end
        end
    end
end

addModEventListener(DistributionManager)
