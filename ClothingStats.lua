local Block_ClothingStats = {}
Block_ClothingStats.__index = Block_ClothingStats

function Layout.createClothingStatsBlock()
    return setmetatable({}, Block_ClothingStats)
end

function Block_ClothingStats:shouldRender(item)
    return item and instanceof(item, ""Clothing"")
end

function Block_ClothingStats:measure(item, width)
    local h = 0
    if item:getInsulation() > 0 then h = h + 18 end
    if item:getWindresistance() > 0 then h = h + 18 end
    if item:getWaterResistance() > 0 then h = h + 18 end
    if item:getRunSpeedModifier() ~= 1.0 then h = h + 18 end
    if item:getCombatSpeedModifier() ~= 1.0 then h = h + 18 end
    if h > 0 then h = h + 8 end -- padding
    return h, width
end

function Block_ClothingStats:render(item, x, y, width, renderQueue)
    local currentY = y
    local function addStat(label, valText, r, g, b)
        table.insert(renderQueue, {
            type = ""text"", text = label, x = x, y = currentY, font = getUIFont(""Text""),
            r = Config.Colors.TextLabel.r, g = Config.Colors.TextLabel.g, b = Config.Colors.TextLabel.b, a = 1.0
        })
        local valWidth = getTextManager():MeasureStringX(getUIFont(""Value""), valText)
        table.insert(renderQueue, {
            type = ""text"", text = valText, x = x + width - valWidth, y = currentY, font = getUIFont(""Value""),
            r = r, g = g, b = b, a = 1.0
        })
        currentY = currentY + 18
    end

    if item:getInsulation() > 0 then
        addStat(""Insulation"", string.format(""%.2f"", item:getInsulation()), 0.4, 0.8, 0.4)
    end
    if item:getWindresistance() > 0 then
        addStat(""Wind Resist"", string.format(""%.2f"", item:getWindresistance()), 0.4, 0.8, 0.8)
    end
    if item:getWaterResistance() > 0 then
        addStat(""Water Resist"", string.format(""%.2f"", item:getWaterResistance()), 0.3, 0.5, 0.9)
    end
    if item:getRunSpeedModifier() ~= 1.0 then
        local mod = (item:getRunSpeedModifier() - 1.0) * 100
        addStat(""Run Speed"", string.format(""%+.0f%%"", mod), mod < 0 and 0.8 or 0.4, mod < 0 and 0.3 or 0.8, 0.3)
    end
    if item:getCombatSpeedModifier() ~= 1.0 then
        local mod = (item:getCombatSpeedModifier() - 1.0) * 100
        addStat(""Combat Speed"", string.format(""%+.0f%%"", mod), mod < 0 and 0.8 or 0.4, mod < 0 and 0.3 or 0.8, 0.3)
    end
    
    return currentY - y
end
