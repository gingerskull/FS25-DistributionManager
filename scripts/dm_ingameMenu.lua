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

    -- Hook output mode toggle to include MANAGER in cycle
    InGameMenuProductionFrame.onButtonToggleOutputMode = Utils.overwrittenFunction(
        InGameMenuProductionFrame.onButtonToggleOutputMode,
        DistributionManagerIngameMenu.onButtonToggleOutputMode
    )

    -- Register MANAGER mode display text in vanilla lookup tables (best-effort).
    -- If the game or another mod uses these tables, they'll naturally show "Manager".
    if ProductionPoint.OUTPUT_MODE_L10N ~= nil then
        ProductionPoint.OUTPUT_MODE_L10N[ProductionPoint.OUTPUT_MODE.MANAGER] = "dm_outputModeManager"
    end
    if ProductionPoint.OUTPUT_MODE_NAMES ~= nil then
        ProductionPoint.OUTPUT_MODE_NAMES[ProductionPoint.OUTPUT_MODE.MANAGER] = "dm_outputModeManager"
    end
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

-- Re-apply our populate hook every time the menu buttons refresh.
-- Another mod may have overwritten or appended to populateCellForItemInSection
-- after DM init().  We wrap whatever is currently there and apply our text
-- fix LAST so it always wins.
function DistributionManagerIngameMenu.ensurePopulateHook()
    local current = InGameMenuProductionFrame.populateCellForItemInSection
    if current == DistributionManagerIngameMenu._dmPopulateWrapper then
        return -- already our wrapper
    end

    DistributionManagerIngameMenu._dmPopulateWrapper = function(self, list, section, index, cell)
        -- Call the current chain (vanilla + other mods) first
        current(self, list, section, index, cell)
        -- Now apply our text fix so it overwrites anything set before
        DistributionManagerIngameMenu.populateCellForItemInSection(self, list, section, index, cell)
    end

    InGameMenuProductionFrame.populateCellForItemInSection = DistributionManagerIngameMenu._dmPopulateWrapper

    if DistributionManager.debug then
        print("--- DistributionManager: re-applied populateCellForItemInSection hook")
    end
end

-- Add configure distribution button when MANAGER mode is active
-- Note: defined with colon so Utils.appendedFunction passes the frame as self
function DistributionManagerIngameMenu:updateMenuButtonsAppend()
    -- Make sure our mode-toggle logic wins against late-loading mods.
    DistributionManagerIngameMenu.ensureToggleHook()
    -- Make sure our "Manager" label wins against late-loading mods too.
    DistributionManagerIngameMenu.ensurePopulateHook()

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
