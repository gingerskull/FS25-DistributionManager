--
-- Distribution Manager - InGameMenu Integration
-- Hooks into production menu and adds configure button
--

DistributionManagerIngameMenu = {}

function DistributionManagerIngameMenu.init()
    if DistributionManager.debug then
        print("--- DistributionManagerIngameMenu.init()")
    end

    -- Hook updateMenuButtons to add our configure button
    InGameMenuProductionFrame.updateMenuButtons = Utils.appendedFunction(
        InGameMenuProductionFrame.updateMenuButtons,
        DistributionManagerIngameMenu.updateMenuButtonsAppend
    )

    -- Hook populateCellForItemInSection to show "Manager" text
    InGameMenuProductionFrame.populateCellForItemInSection = Utils.appendedFunction(
        InGameMenuProductionFrame.populateCellForItemInSection,
        DistributionManagerIngameMenu.populateCellForItemInSection
    )

    -- Hook output mode toggle to include MANAGER in cycle
    InGameMenuProductionFrame.onButtonToggleOutputMode = Utils.overwrittenFunction(
        InGameMenuProductionFrame.onButtonToggleOutputMode,
        DistributionManagerIngameMenu.onButtonToggleOutputMode
    )

    -- Setup main menu page
    DistributionManagerIngameMenu.setupMainMenuPage()
end

function DistributionManagerIngameMenu.setupMainMenuPage()
    -- Left-bar menu entry disabled for now
    --[[
    local ui = g_currentMission.inGameMenu

    -- Load custom GUI profiles
    g_gui:loadProfiles(DistributionManager.dir .. "gui/dm_guiProfiles.xml")

    -- Load the distribution manager menu page
    local menuPage = InGameMenuDistributionManager.new(g_i18n, g_messageCenter)
    g_gui:loadGui(
        DistributionManager.dir .. "gui/InGameMenuDistributionManager.xml",
        "ingameMenuDistributionManager",
        menuPage,
        true
    )

    -- Insert into InGameMenu (above the Statistics tab, similar to TSStockCheck)
    DistributionManagerIngameMenu.fixInGameMenu(
        menuPage,
        "ingameMenuDistributionManager",
        {0, 0, 1024, 1024},
        2,
        function() return true end
    )
    --]]
end

-- From TSStockCheck / Courseplay - inject a page into the InGameMenu
function DistributionManagerIngameMenu.fixInGameMenu(frame, pageName, uvs, position, predicateFunc)
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    local abovePrices = 0

    -- Find position above statistics tab
    for i = 1, #inGameMenu.pagingElement.elements do
        local child = inGameMenu.pagingElement.elements[i]
        if child == inGameMenu.pageStatistics then
            abovePrices = i
            break
        end
    end

    if abovePrices == 0 then
        abovePrices = position
    end

    -- Remove any existing references to avoid warnings
    for k, v in pairs({pageName}) do
        inGameMenu.controlIDs[v] = nil
    end

    inGameMenu[pageName] = frame
    inGameMenu.pagingElement:addElement(inGameMenu[pageName])
    inGameMenu:exposeControlsAsFields(pageName)

    -- Reorder elements
    for i = 1, #inGameMenu.pagingElement.elements do
        local child = inGameMenu.pagingElement.elements[i]
        if child == inGameMenu[pageName] then
            table.remove(inGameMenu.pagingElement.elements, i)
            table.insert(inGameMenu.pagingElement.elements, abovePrices, child)
            break
        end
    end

    for i = 1, #inGameMenu.pagingElement.pages do
        local child = inGameMenu.pagingElement.pages[i]
        if child.element == inGameMenu[pageName] then
            table.remove(inGameMenu.pagingElement.pages, i)
            table.insert(inGameMenu.pagingElement.pages, abovePrices, child)
            break
        end
    end

    inGameMenu.pagingElement:updateAbsolutePosition()
    inGameMenu.pagingElement:updatePageMapping()

    inGameMenu:registerPage(inGameMenu[pageName], position, predicateFunc)
    local iconFileName = Utils.getFilename("images/menuIcon.dds", DistributionManager.dir)
    inGameMenu:addPageTab(inGameMenu[pageName], iconFileName, GuiUtils.getUVs(uvs))

    for i = 1, #inGameMenu.pageFrames do
        local child = inGameMenu.pageFrames[i]
        if child == inGameMenu[pageName] then
            table.remove(inGameMenu.pageFrames, i)
            table.insert(inGameMenu.pageFrames, abovePrices, child)
            break
        end
    end

    inGameMenu:rebuildTabList()
end

-- Core mode-cycle logic used by both the init() hook and the runtime hook guard.
-- Returns true if it handled the cycle, false if it should fall through to vanilla / another mod.
function DistributionManagerIngameMenu.handleModeCycle(self)
    if g_currentMission:getHasPlayerPermission("manageProductions") then
        local production, productionPoint = self:getSelectedProduction()
        if production ~= nil and productionPoint ~= nil then
            local fillType = production.primaryProductFillType
            if fillType ~= nil then
                local currentMode = productionPoint:getOutputDistributionMode(fillType)

                -- Build a sorted list of every numeric mode registered in OUTPUT_MODE.
                -- This keeps MANAGER in the cycle no matter what other mods have added.
                local modes = {}
                for _, value in pairs(ProductionPoint.OUTPUT_MODE) do
                    if type(value) == "number" and value >= 0 then
                        table.insert(modes, value)
                    end
                end
                table.sort(modes)

                local currentIndex = 1
                for i, mode in ipairs(modes) do
                    if mode == currentMode then
                        currentIndex = i
                        break
                    end
                end

                local nextIndex = (currentIndex % #modes) + 1
                local nextMode = modes[nextIndex]

                productionPoint:setOutputDistributionMode(fillType, nextMode)

                if self.productsList ~= nil then
                    self.productsList:reloadData()
                end
                self:updateMenuButtons()
                return true
            end
        end
    end
    return false
end

-- Re-apply our toggle hook every time the menu buttons refresh.
-- Another mod may have overwritten onButtonToggleOutputMode after DM init()
-- (e.g. Production Manager, Production Revamp, etc.).  By checking each
-- refresh we make sure our wrapper is always the one the button calls.
function DistributionManagerIngameMenu.ensureToggleHook()
    local current = InGameMenuProductionFrame.onButtonToggleOutputMode
    if current == DistributionManagerIngameMenu._dmToggleWrapper then
        return -- already our wrapper
    end

    DistributionManagerIngameMenu._dmOriginalToggle = current

    DistributionManagerIngameMenu._dmToggleWrapper = function(self)
        if not DistributionManagerIngameMenu.handleModeCycle(self) then
            -- Our conditions didn't match; hand off to whoever was there before.
            if DistributionManagerIngameMenu._dmOriginalToggle ~= nil then
                DistributionManagerIngameMenu._dmOriginalToggle(self)
            end
        end
    end

    InGameMenuProductionFrame.onButtonToggleOutputMode = DistributionManagerIngameMenu._dmToggleWrapper

    if DistributionManager.debug then
        print("--- DistributionManager: re-applied onButtonToggleOutputMode hook")
    end
end

-- Add configure distribution button when MANAGER mode is active
-- Note: defined with colon so Utils.appendedFunction passes the frame as self
function DistributionManagerIngameMenu:updateMenuButtonsAppend()
    -- Make sure our mode-toggle logic wins against late-loading mods.
    DistributionManagerIngameMenu.ensureToggleHook()

    if self.pointsSelector:getState() == InGameMenuProductionFrame.POINTS_OWNED then
        if g_currentMission:getHasPlayerPermission("manageProductions") then
            local production, productionPoint = self:getSelectedProduction()
            if production ~= nil and productionPoint ~= nil and productionPoint.dmDistributionRules ~= nil then
                local fillType = production.primaryProductFillType
                local rule = productionPoint.dmDistributionRules[fillType]
                if fillType ~= nil and rule ~= nil and rule.managerMode then
                    table.insert(self.menuButtonInfo, {
                        profile = "buttonOK",
                        inputAction = InputAction.ACTIVATE_OBJECT,
                        text = g_i18n:getText("dm_buttonConfigureDistribution"),
                        callback = function()
                            DistributionManagerIngameMenu.openDistributionDialog(productionPoint, fillType)
                        end
                    })
                end
            end
        end
    end
end

-- Show "Manager" text for outputs in MANAGER mode
-- Note: defined with colon so Utils.appendedFunction passes the frame as self
function DistributionManagerIngameMenu:populateCellForItemInSection(list, section, index, cell)
    if list == self.productsList then
        local _, productionPoint = self:getSelectedProduction()
        if productionPoint ~= nil then
            local production = productionPoint.sortedProductions[index]
            if production ~= nil then
                local fillType = production.primaryProductFillType
                if fillType ~= nil and productionPoint.dmDistributionRules ~= nil then
                    local rule = productionPoint.dmDistributionRules[fillType]
                    if rule ~= nil and rule.managerMode then
                        cell:getAttribute("activity"):setText(g_i18n:getText("dm_outputModeManager"))
                    end
                end
            end
        end
    end
end

-- Cycle output modes including MANAGER
-- Used by the init() overwrite as a fallback when no conflicting mod has taken over.
function DistributionManagerIngameMenu:onButtonToggleOutputMode(superFunc)
    if not DistributionManagerIngameMenu.handleModeCycle(self) then
        superFunc(self)
    end
end

-- Open the distribution configuration dialog
function DistributionManagerIngameMenu.openDistributionDialog(productionPoint, fillTypeId)
    DistributionSettingsDialog.show(productionPoint, fillTypeId)
end
