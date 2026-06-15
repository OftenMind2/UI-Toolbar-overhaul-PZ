ZFlexTooltip = ZFlexTooltip or {}
ZFlexTooltip.Layout = ZFlexTooltip.Layout or {}

local Config = ZFlexTooltip.Config
local Layout = ZFlexTooltip.Layout

local Caps = ZFlexTooltip.Capabilities
local safeCall = Caps.safeInvoke
-- Font helper mapping string tokens to PZ UIFont enums
local function getUIFont(fontToken)
    local f = Config.Fonts[fontToken] or "Small"
    if f == "Medium" then return UIFont.Medium end
    if f == "Large" then return UIFont.Large end
    if f == "Code" then return UIFont.Code end
    return UIFont.Small
end

----------------------------------------------------
-- VBOX LAYOUT CONTAINER
----------------------------------------------------
local VBox = {}
VBox.__index = VBox

function Layout.createVBox(width)
    local box = {}
    setmetatable(box, VBox)
    box.width = width or Config.Grid.MinWidth
    box.blocks = {}
    return box
end

function VBox:addBlock(block)
    table.insert(self.blocks, block)
end

-- Pass 1: Measure blocks and determine final width
function VBox:measure(item)
    local width = self.width
    local totalHeight = Config.Grid.Padding
    
    for _, block in ipairs(self.blocks) do
        if block:shouldRender(item) then
            local h, prefWidth = block:measure(item, width)
            if prefWidth and prefWidth > width then
                width = math.min(Config.Grid.MaxWidth, prefWidth)
            end
        end
    end
    
    self.width = width
    return width
end

-- Pass 2: Layout blocks and generate render queue
function VBox:generateQueue(item, renderQueue)
    local y = Config.Grid.Padding
    local width = self.width
    local padding = Config.Grid.Padding
    local blockGap = Config.Grid.BlockGap
    
    local activeCount = 0
    for _, block in ipairs(self.blocks) do
        if block:shouldRender(item) then
            if activeCount > 0 then
                y = y + blockGap
            end
            local h = block:render(item, padding, y, width - padding * 2, renderQueue)
            y = y + h
            activeCount = activeCount + 1
        end
    end
    
    return y + padding
end

----------------------------------------------------
-- INDIVIDUAL LAYOUT BLOCKS
----------------------------------------------------

-- BLOCK 1: HEADER (Icon, Name, Category, Weight)
local Block_Header = {}
Block_Header.__index = Block_Header

function Layout.createHeaderBlock()
    return setmetatable({}, Block_Header)
end

function Block_Header:shouldRender(item)
    return item ~= nil
end

function Block_Header:measure(item, width)
    local name = item:getName() or "Unknown Item"
    local font = getUIFont("Title")
    local textWidth = getTextManager():MeasureStringX(font, name)
    -- Padding (16*2) + Icon Space (48) + Name
    local preferredWidth = textWidth + 32 + 48
    return 48, preferredWidth
end

function Block_Header:render(item, x, y, width, renderQueue)
    local name = item:getName() or "Unknown Item"
    local category = item:getDisplayCategory() or "Item"
    
    -- Category fallback translation from config
    local rawCategory = item:getCategory()
    if rawCategory and Config.CategoryNames[rawCategory] then
        category = Config.CategoryNames[rawCategory]
    end
    
    local weight = Caps.getWeight(item)
    local weightText = string.format("Weight: %.2f", weight)
    
    -- Fetch rarity color from item mod data or default to Common
    local rarity = "Common"
    local modData = safeCall(item, "getModData")
    if modData and type(modData.AttachmentSystem) == "table" then
        rarity = modData.AttachmentSystem.displayRarity or modData.AttachmentSystem.rarity or "Common"
    elseif safeCall(item, "getRarity") then
        rarity = safeCall(item, "getRarity")
    end
    local nameColor = Config.RarityColors[rarity] or Config.Colors.TextHero
    
    -- Icon retrieval & color tint
    local tex = item:getTex()
    local iconR, iconG, iconB = 1.0, 1.0, 1.0
    if item:getVisual() and instanceof(item, "Clothing") and item:getClothingItem() then
        local tint = item:getVisual():getTint(item:getClothingItem())
        if tint then
            iconR = tint:getRedFloat()
            iconG = tint:getGreenFloat()
            iconB = tint:getBlueFloat()
        end
    end
    
    -- Draw texture command
    if tex then
        table.insert(renderQueue, {
            type = "texture",
            texture = tex,
            x = x,
            y = y,
            w = 40,
            h = 40,
            r = iconR,
            g = iconG,
            b = iconB,
            a = 1.0
        })
    end
    
    -- Draw Name command
    table.insert(renderQueue, {
        type = "text",
        text = name,
        x = x + 48,
        y = y,
        font = getUIFont("Title"),
        r = nameColor.r,
        g = nameColor.g,
        b = nameColor.b,
        a = 1.0
    })
    
    -- Subtitle (Category & Weight)
    local subText = category .. " | " .. weightText
    table.insert(renderQueue, {
        type = "text",
        text = subText,
        x = x + 48,
        y = y + 22,
        font = getUIFont("Text"),
        r = Config.Colors.TextLabel.r,
        g = Config.Colors.TextLabel.g,
        b = Config.Colors.TextLabel.b,
        a = 1.0
    })
    
    -- Header separator line
    table.insert(renderQueue, {
        type = "rect",
        x = x,
        y = y + 48,
        w = width,
        h = 1,
        color = Config.Colors.BorderBase
    })
    
    return 54 -- height including separator
end


-- BLOCK 2: HERO STAT (Destiny style main stat with Shift-Compare)
local Block_HeroStat = {}
Block_HeroStat.__index = Block_HeroStat

function Layout.createHeroStatBlock()
    return setmetatable({}, Block_HeroStat)
end

-- Helper to extract primary stat value
local function getPrimaryStat(item)
    if not item then return nil, nil end
    if instanceof(item, "HandWeapon") then
        local minDmg = item:getMinDamage()
        local maxDmg = item:getMaxDamage()
        return (minDmg + maxDmg) / 2, "DAMAGE"
    elseif instanceof(item, "Clothing") then
        local scratch = item:getScratchDefense()
        local bite = item:getBiteDefense()
        return (scratch + bite) / 2, "DEFENSE"
    elseif instanceof(item, "InventoryContainer") then
        return item:getCapacity(), "CAPACITY"
    end
    return nil, nil
end

-- Helper to get player equipped item in slot for comparison
local function getEquippedItem(item, player)
    if not player or not item then return nil end
    if instanceof(item, "HandWeapon") then
        local pri = player:getPrimaryHandItem()
        if pri and instanceof(pri, "HandWeapon") then return pri end
    elseif instanceof(item, "Clothing") then
        -- Find clothing worn in matching body location
        local loc = item:getBodyLocation()
        if loc then
            local worn = player:getWornItems()
            if worn then
                local equipped = worn:getItem(loc)
                if equipped then return equipped end
            end
        end
    elseif instanceof(item, "InventoryContainer") then
        local back = player:getClothingItem_Back()
        if back then return back end
    end
    return nil
end

function Block_HeroStat:shouldRender(item)
    local val, label = getPrimaryStat(item)
    return val ~= nil
end

function Block_HeroStat:measure(item, width)
    return 48, width
end

function Block_HeroStat:render(item, x, y, width, renderQueue)
    local val, label = getPrimaryStat(item)
    local valText = string.format("%.1f", val)
    if val % 1 == 0 then
        valText = string.format("%d", val)
    end
    
    -- Draw Value (Huge text)
    table.insert(renderQueue, {
        type = "text",
        text = valText,
        x = x,
        y = y - 4,
        font = getUIFont("Hero"),
        r = Config.Colors.TextHero.r,
        g = Config.Colors.TextHero.g,
        b = Config.Colors.TextHero.b,
        a = 1.0
    })
    
    -- Measure value width to place label
    local valWidth = getTextManager():MeasureStringX(getUIFont("Hero"), valText)
    
    -- Draw Label
    table.insert(renderQueue, {
        type = "text",
        text = label,
        x = x + valWidth + 8,
        y = y + 8,
        font = getUIFont("Text"),
        r = Config.Colors.TextLabel.r,
        g = Config.Colors.TextLabel.g,
        b = Config.Colors.TextLabel.b,
        a = 1.0
    })
    
    -- Progressive Disclosure (Shift Compare)
    local isShiftDown = isShiftKeyDown()
    local player = getPlayer()
    local height = 36
    
    if isShiftDown and player then
        local equipped = getEquippedItem(item, player)
        if equipped and equipped ~= item then
            local eqVal, _ = getPrimaryStat(equipped)
            if eqVal then
                local diff = val - eqVal
                local diffText = string.format("%.1f", diff)
                if diff % 1 == 0 then
                    diffText = string.format("%d", diff)
                end
                
                local diffR, diffG, diffB = 0.8, 0.8, 0.8
                if diff > 0 then
                    diffText = "+" .. diffText
                    diffR, diffG, diffB = Config.Colors.State.Perfect.r, Config.Colors.State.Perfect.g, Config.Colors.State.Perfect.b
                elseif diff < 0 then
                    diffR, diffG, diffB = Config.Colors.State.Critical.r, Config.Colors.State.Critical.g, Config.Colors.State.Critical.b
                end
                
                local compText = string.format("(VS equipped: %s)", diffText)
                table.insert(renderQueue, {
                    type = "text",
                    text = compText,
                    x = x + valWidth + 8 + getTextManager():MeasureStringX(getUIFont("Text"), label) + 8,
                    y = y + 8,
                    font = getUIFont("Text"),
                    r = diffR,
                    g = diffG,
                    b = diffB,
                    a = 1.0
                })
            end
        end
    end
    
    return height
end


-- BLOCK 3: PROGRESS BARS (Condition/Durability & Ammunition)
local Block_ProgressBars = {}
Block_ProgressBars.__index = Block_ProgressBars

function Layout.createProgressBarsBlock()
    return setmetatable({}, Block_ProgressBars)
end

function Block_ProgressBars:shouldRender(item)
    if not item then return false end
    local isWeapon = instanceof(item, "HandWeapon")
    local isClothing = instanceof(item, "Clothing")
    if isWeapon or isClothing then
        local maxCond = safeCall(item, "getConditionMax")
        return maxCond and maxCond > 0
    end
    return false
end

function Block_ProgressBars:measure(item, width)
    return 22, width
end

function Block_ProgressBars:render(item, x, y, width, renderQueue)
    local cond = safeCall(item, "getCondition") or 0
    local maxCond = safeCall(item, "getConditionMax") or 1
    local ratio = cond / math.max(1, maxCond)
    
    -- State color selection
    local barColor = Config.Colors.State.Perfect
    if ratio < 0.25 then
        barColor = Config.Colors.State.Critical
    elseif ratio < 0.75 then
        barColor = Config.Colors.State.Warning
    end
    
    -- Draw Durability label
    table.insert(renderQueue, {
        type = "text",
        text = "DURABILITY",
        x = x,
        y = y,
        font = getUIFont("Text"),
        r = Config.Colors.TextLabel.r,
        g = Config.Colors.TextLabel.g,
        b = Config.Colors.TextLabel.b,
        a = 1.0
    })
    
    -- Draw Durability value (e.g. 10/10)
    local valText = cond .. " / " .. maxCond
    local valWidth = getTextManager():MeasureStringX(getUIFont("Value"), valText)
    table.insert(renderQueue, {
        type = "text",
        text = valText,
        x = x + width - valWidth,
        y = y,
        font = getUIFont("Value"),
        r = Config.Colors.TextHero.r,
        g = Config.Colors.TextHero.g,
        b = Config.Colors.TextHero.b,
        a = 1.0
    })
    
    -- Draw bar background
    table.insert(renderQueue, {
        type = "rect",
        x = x,
        y = y + 14,
        w = width,
        h = 4,
        color = { r = 0.1, g = 0.1, b = 0.12, a = 0.6 }
    })
    
    -- Draw bar fill
    if ratio > 0 then
        table.insert(renderQueue, {
            type = "rect",
            x = x,
            y = y + 14,
            w = math.floor(width * ratio),
            h = 4,
            color = { r = barColor.r, g = barColor.g, b = barColor.b, a = 1.0 }
        })
    end
    
    return 22
end


-- BLOCK 4: FLUID FLASK (Build 42.19 Liquid displays)
local Block_FluidFlask = {}
Block_FluidFlask.__index = Block_FluidFlask

function Layout.createFluidFlaskBlock()
    return setmetatable({}, Block_FluidFlask)
end

function Block_FluidFlask:shouldRender(item)
    return item and safeCall(item, "getFluidContainer") ~= nil
end

function Block_FluidFlask:measure(item, width)
    return 36, width
end

function Block_FluidFlask:render(item, x, y, width, renderQueue)
    local container = item:getFluidContainer()
    local amount = container:getFluidAmount()
    local capacity = container:getCapacity()
    local ratio = amount / math.max(0.01, capacity)
    
    local fluidName = "Empty"
    local fillR, fillG, fillB = 0.3, 0.3, 0.3
    
    if not container:isEmpty() then
        local fluid = container:getPrimaryFluid()
        if fluid then
            fluidName = fluid:getDisplayName() or "Unknown Liquid"
            local color = fluid:getColor()
            if color then
                fillR = color:getRedFloat()
                fillG = color:getGreenFloat()
                fillB = color:getBlueFloat()
            end
        end
    end
    
    -- Header Label
    table.insert(renderQueue, {
        type = "text",
        text = "CONTAINED LIQUID",
        x = x,
        y = y,
        font = getUIFont("Text"),
        r = Config.Colors.TextLabel.r,
        g = Config.Colors.TextLabel.g,
        b = Config.Colors.TextLabel.b,
        a = 1.0
    })
    
    -- Volume Text
    local volText = string.format("%.1f / %.1f L", amount, capacity)
    local valWidth = getTextManager():MeasureStringX(getUIFont("Value"), volText)
    table.insert(renderQueue, {
        type = "text",
        text = volText,
        x = x + width - valWidth,
        y = y,
        font = getUIFont("Value"),
        r = Config.Colors.TextHero.r,
        g = Config.Colors.TextHero.g,
        b = Config.Colors.TextHero.b,
        a = 1.0
    })
    
    -- Fluid Display Name
    table.insert(renderQueue, {
        type = "text",
        text = fluidName,
        x = x,
        y = y + 16,
        font = getUIFont("Text"),
        r = fillR,
        g = fillG,
        b = fillB,
        a = 1.0
    })
    
    -- Custom flask filling level bar
    table.insert(renderQueue, {
        type = "rect",
        x = x + width - 100,
        y = y + 20,
        w = 100,
        h = 6,
        color = { r = 0.1, g = 0.1, b = 0.12, a = 0.6 }
    })
    if ratio > 0 then
        table.insert(renderQueue, {
            type = "rect",
            x = x + width - 100,
            y = y + 20,
            w = math.floor(100 * ratio),
            h = 6,
            color = { r = fillR, g = fillG, b = fillB, a = 0.9 }
        })
    end
    
    return 30
end


-- BLOCK 5: SOCKETS (Weapon attachment slots - Cyberpunk style)
local Block_Sockets = {}
Block_Sockets.__index = Block_Sockets

function Layout.createSocketsBlock()
    return setmetatable({}, Block_Sockets)
end

function Block_Sockets:shouldRender(item)
    return item and instanceof(item, "HandWeapon")
end

function Block_Sockets:measure(item, width)
    return 44, width
end

function Block_Sockets:render(item, x, y, width, renderQueue)
    -- Standard slots on B42/B41 weapons
    local partMethods = { "getScope", "getSling", "getCanon", "getClip", "getRecoilpad", "getStock" }
    local activeParts = {}
    
    for _, method in ipairs(partMethods) do
        local part = safeCall(item, method)
        if part then
            table.insert(activeParts, { name = part:getName(), tex = part:getTex() })
        end
    end
    
    -- Label
    table.insert(renderQueue, {
        type = "text",
        text = "MODS",
        x = x,
        y = y + 10,
        font = getUIFont("Text"),
        r = Config.Colors.TextLabel.r,
        g = Config.Colors.TextLabel.g,
        b = Config.Colors.TextLabel.b,
        a = 1.0
    })
    
    -- Draw 4 slots horizontally on the right
    local slotSize = 28
    local gap = 4
    local startX = x + width - (slotSize * 4 + gap * 3)
    
    for i = 1, 4 do
        local slotX = startX + (i - 1) * (slotSize + gap)
        local part = activeParts[i]
        
        -- Draw empty slot with dashed border look (represented by alpha border rect)
        table.insert(renderQueue, {
            type = "rect_border",
            x = slotX,
            y = y + 2,
            w = slotSize,
            h = slotSize,
            color = Config.Colors.BorderBase
        })
        
        -- Draw attachment icon inside if present
        if part and part.tex then
            table.insert(renderQueue, {
                type = "texture",
                texture = part.tex,
                x = slotX + 2,
                y = y + 4,
                w = slotSize - 4,
                h = slotSize - 4,
                r = 1, g = 1, b = 1, a = 1
            })
        end
    end
    
    return 32
end


-- BLOCK 6: TAGS (Badges wrapped dynamically)
local Block_Tags = {}
Block_Tags.__index = Block_Tags

function Layout.createTagsBlock()
    return setmetatable({}, Block_Tags)
end

function Block_Tags:shouldRender(item)
    local modData = safeCall(item, "getModData")
    if modData and type(modData) == "table" then
        return true
    end
    
    if Caps.supportsTags(item) then
        local hasTags = false
        Caps.iterateTags(safeCall(item, "getTags"), function() hasTags = true end)
        return hasTags
    end
    
    return false
end

function Block_Tags:measure(item, width)
    -- Tags block wraps, we return a base height of 24, dynamically calculated during render
    return 24, width
end

function Block_Tags:render(item, x, y, width, renderQueue)
    local drawY = y
    local tagList = {}
    
    -- Extract tags from custom attachment system mod data first
    local modData = safeCall(item, "getModData")
    if modData and type(modData.AttachmentSystem) == "table" and modData.AttachmentSystem.visibleTags then
        local tags = modData.AttachmentSystem.visibleTags
        local tagsDef = ZFlexTooltip.TagsDef or {}
        
        for _, tagKey in ipairs(tags) do
            local tagDef = tagsDef[tagKey]
            local displayName = tagKey
            local kind = "neutral"
            
            -- Look up definitions from attachment system config if loaded
            if AttachmentSystem and AttachmentSystem.Tags and AttachmentSystem.Tags.get then
                local def = AttachmentSystem.Tags.get(tagKey)
                if def then
                    displayName = AttachmentSystem.Tags.display(tagKey)
                    kind = def.kind or "neutral"
                end
            end
            
            table.insert(tagList, { name = displayName, kind = kind })
        end
    end
    
    -- Extract standard Java tags using Capability API
    if #tagList == 0 and Caps.supportsTags(item) then
        Caps.iterateTags(safeCall(item, "getTags"), function(tag)
            table.insert(tagList, { name = "#" .. tostring(tag), kind = "neutral" })
        end)
    end
    
    -- If no tags found, exit height 0
    if #tagList == 0 then return 0 end
    
    -- Render badge capsules
    local badgeX = x
    local badgeY = y
    local rowHeight = 16
    local totalHeight = 16
    local font = getUIFont("Text")
    
    for _, tag in ipairs(tagList) do
        local strWidth = getTextManager():MeasureStringX(font, tag.name)
        local badgeWidth = strWidth + 10
        
        -- Wrap row
        if badgeX + badgeWidth > x + width then
            badgeX = x
            badgeY = badgeY + rowHeight + 4
            totalHeight = totalHeight + rowHeight + 4
        end
        
        -- Style badges
        local bgR, bgG, bgB = 0.15, 0.16, 0.18
        local textR, textG, textB = 0.8, 0.8, 0.8
        
        if tag.kind == "good" then
            bgR, bgG, bgB = 0.1, 0.35, 0.1
            textR, textG, textB = Config.Colors.State.Perfect.r, Config.Colors.State.Perfect.g, Config.Colors.State.Perfect.b
        elseif tag.kind == "bad" then
            bgR, bgG, bgB = 0.35, 0.1, 0.1
            textR, textG, textB = Config.Colors.State.Critical.r, Config.Colors.State.Critical.g, Config.Colors.State.Critical.b
        elseif tag.kind == "earned" then
            bgR, bgG, bgB = 0.1, 0.2, 0.4
            textR, textG, textB = 0.4, 0.7, 1.0
        end
        
        -- Draw capsule background
        table.insert(renderQueue, {
            type = "rect",
            x = badgeX,
            y = badgeY,
            w = badgeWidth,
            h = 14,
            color = { r = bgR, g = bgG, b = bgB, a = 0.8 }
        })
        table.insert(renderQueue, {
            type = "rect_border",
            x = badgeX,
            y = badgeY,
            w = badgeWidth,
            h = 14,
            color = { r = bgR * 1.5, g = bgG * 1.5, b = bgB * 1.5, a = 0.5 }
        })
        
        -- Draw badge text
        table.insert(renderQueue, {
            type = "text",
            text = tag.name,
            x = badgeX + 5,
            y = badgeY + 1,
            font = font,
            r = textR,
            g = textG,
            b = textB,
            a = 1.0
        })
        
        badgeX = badgeX + badgeWidth + 4
    end
    
    return totalHeight + 4
end


-- BLOCK 7: LEGACY MOD (Render third-party draw calls elegantly)
local Block_LegacyMod = {}
Block_LegacyMod.__index = Block_LegacyMod

function Layout.createLegacyModBlock()
    return setmetatable({}, Block_LegacyMod)
end

function Block_LegacyMod:shouldRender(item)
    return ZFlexTooltip.CapturedDrawCalls and #ZFlexTooltip.CapturedDrawCalls > 0
end

function Block_LegacyMod:measure(item, width)
    local calls = ZFlexTooltip.CapturedDrawCalls or {}
    local lineCount = 0
    local maxW = width
    local font = getUIFont("Text")
    
    for _, call in ipairs(calls) do
        if call.textLine then
            lineCount = lineCount + 1
            local textW = getTextManager():MeasureStringX(font, call.textLine)
            maxW = math.max(maxW, textW + 32)
        end
    end
    
    -- Separator(1) + margin(6) + lines * spacing(13) + margin(4)
    local totalH = 1 + 6 + (lineCount * 13) + 4
    return totalH, maxW
end

function Block_LegacyMod:render(item, x, y, width, renderQueue)
    local calls = ZFlexTooltip.CapturedDrawCalls or {}
    local textLineCount = 0
    local spacing = 13
    local font = getUIFont("Text")
    
    -- Draw separator above legacy mods section
    table.insert(renderQueue, {
        type = "rect",
        x = x,
        y = y,
        w = width,
        h = 1,
        color = Config.Colors.BorderBase
    })
    
    y = y + 6
    
    for _, call in ipairs(calls) do
        if call.textLine then
            table.insert(renderQueue, {
                type = "text",
                text = call.textLine,
                x = x + 4,
                y = y + textLineCount * spacing,
                font = font,
                r = call.color.r,
                g = call.color.g,
                b = call.color.b,
                a = call.color.a
            })
            textLineCount = textLineCount + 1
        end
    end
    
    return textLineCount * spacing + 10
end-- BLOCK 7.5: ATTACHMENT SYSTEM (Modular attachments display)
local Block_AttachmentSystem = {}
Block_AttachmentSystem.__index = Block_AttachmentSystem

function Layout.createAttachmentSystemBlock()
    return setmetatable({}, Block_AttachmentSystem)
end

function Block_AttachmentSystem:shouldRender(item)
    if not (AttachmentSystem and AttachmentSystem.Tooltip and AttachmentSystem.Tooltip.linesForItem) then
        return false
    end
    local lines = AttachmentSystem.Tooltip.linesForItem(item)
    return lines and #lines > 0
end

function Block_AttachmentSystem:measure(item, width)
    local lines = AttachmentSystem.Tooltip.linesForItem(item)
    if not lines or #lines == 0 then return 0, width end
    
    local lineCount = 0
    local maxW = width
    local fontText = getUIFont("Text")
    local fontValue = getUIFont("Value")
    
    for _, line in ipairs(lines) do
        -- Skip tags since Block_Tags already renders them
        if line.type ~= "tags" then
            lineCount = lineCount + 1
            local labelW = 0
            local valueW = 0
            if line.label then
                labelW = getTextManager():MeasureStringX(fontText, line.label)
            end
            if line.value then
                valueW = getTextManager():MeasureStringX(fontValue, line.value)
            end
            
            if line.type == "header" then
                local textW = getTextManager():MeasureStringX(fontText, line.text or "")
                maxW = math.max(maxW, textW + 32)
            elseif line.type == "separator" then
                -- Separators don't need width checks
            else
                maxW = math.max(maxW, labelW + valueW + 48)
            end
        end
    end
    
    return lineCount * 15 + 10, maxW
end

function Block_AttachmentSystem:render(item, x, y, width, renderQueue)
    local lines = AttachmentSystem.Tooltip.linesForItem(item)
    if not lines or #lines == 0 then return 0 end
    
    local spacing = 15
    local fontText = getUIFont("Text")
    local fontValue = getUIFont("Value")
    
    -- Top line separator to visually isolate this section
    table.insert(renderQueue, {
        type = "rect",
        x = x,
        y = y,
        w = width,
        h = 1,
        color = Config.Colors.BorderBase
    })
    
    local currentY = y + 8
    
    for _, line in ipairs(lines) do
        if line.type ~= "tags" then
            if line.type == "header" then
                table.insert(renderQueue, {
                    type = "text",
                    text = line.text,
                    x = x + 4,
                    y = currentY,
                    font = fontText,
                    r = 0.40, g = 0.75, b = 1.0, a = 1.0
                })
                currentY = currentY + spacing
                
            elseif line.type == "separator" then
                table.insert(renderQueue, {
                    type = "rect",
                    x = x + 8,
                    y = currentY + 6,
                    w = width - 16,
                    h = 1,
                    color = { r = Config.Colors.BorderBase.r, g = Config.Colors.BorderBase.g, b = Config.Colors.BorderBase.b, a = 0.3 }
                })
                currentY = currentY + 12
                
            elseif line.type == "quality" then
                table.insert(renderQueue, {
                    type = "text",
                    text = line.label .. ":",
                    x = x + 8,
                    y = currentY,
                    font = fontText,
                    r = Config.Colors.TextMuted.r,
                    g = Config.Colors.TextMuted.g,
                    b = Config.Colors.TextMuted.b,
                    a = 1.0
                })
                
                local rarityColor = Config.RarityColors[line.rarity] or Config.RarityColors.Common
                local labelW = getTextManager():MeasureStringX(fontText, line.label .. ":")
                
                table.insert(renderQueue, {
                    type = "text",
                    text = line.value,
                    x = x + 8 + labelW + 4,
                    y = currentY,
                    font = fontValue,
                    r = rarityColor.r,
                    g = rarityColor.g,
                    b = rarityColor.b,
                    a = 1.0
                })
                currentY = currentY + spacing
                
            elseif line.type == "stat" then
                table.insert(renderQueue, {
                    type = "text",
                    text = "• " .. line.label,
                    x = x + 8,
                    y = currentY,
                    font = fontText,
                    r = Config.Colors.TextLabel.r,
                    g = Config.Colors.TextLabel.g,
                    b = Config.Colors.TextLabel.b,
                    a = 1.0
                })
                
                local valR, valG, valB = 0.85, 0.85, 0.85
                if line.isPositive then
                    valR, valG, valB = Config.Colors.State.Perfect.r, Config.Colors.State.Perfect.g, Config.Colors.State.Perfect.b
                elseif line.isNegative then
                    valR, valG, valB = Config.Colors.State.Critical.r, Config.Colors.State.Critical.g, Config.Colors.State.Critical.b
                end
                
                local valW = getTextManager():MeasureStringX(fontValue, line.value)
                table.insert(renderQueue, {
                    type = "text",
                    text = line.value,
                    x = x + width - 8 - valW,
                    y = currentY,
                    font = fontValue,
                    r = valR,
                    g = valG,
                    b = valB,
                    a = 1.0
                })
                currentY = currentY + spacing
                
            elseif line.type == "title" then
                table.insert(renderQueue, {
                    type = "text",
                    text = line.text,
                    x = x + 8,
                    y = currentY,
                    font = fontText,
                    r = Config.Colors.TextHero.r,
                    g = Config.Colors.TextHero.g,
                    b = Config.Colors.TextHero.b,
                    a = 1.0
                })
                currentY = currentY + spacing
                
            elseif line.type == "knowledge" then
                table.insert(renderQueue, {
                    type = "text",
                    text = line.label .. ":",
                    x = x + 8,
                    y = currentY,
                    font = fontText,
                    r = Config.Colors.TextMuted.r,
                    g = Config.Colors.TextMuted.g,
                    b = Config.Colors.TextMuted.b,
                    a = 1.0
                })
                
                local valR, valG, valB = 0.85, 0.85, 0.85
                if line.state == "Proven" then
                    valR, valG, valB = Config.Colors.State.Perfect.r, Config.Colors.State.Perfect.g, Config.Colors.State.Perfect.b
                elseif line.state == "FieldTested" or line.state == "Inspected" then
                    valR, valG, valB = 0.40, 0.75, 1.0
                elseif line.state == "LookedOver" then
                    valR, valG, valB = Config.Colors.State.Warning.r, Config.Colors.State.Warning.g, Config.Colors.State.Warning.b
                elseif line.state == "Unknown" then
                    valR, valG, valB = Config.Colors.State.Critical.r, Config.Colors.State.Critical.g, Config.Colors.State.Critical.b
                end
                
                local labelW = getTextManager():MeasureStringX(fontText, line.label .. ":")
                table.insert(renderQueue, {
                    type = "text",
                    text = line.value,
                    x = x + 8 + labelW + 4,
                    y = currentY,
                    font = fontValue,
                    r = valR,
                    g = valG,
                    b = valB,
                    a = 1.0
                })
                currentY = currentY + spacing
                
            elseif line.type == "desc" then
                table.insert(renderQueue, {
                    type = "text",
                    text = line.label .. ": " .. line.value,
                    x = x + 8,
                    y = currentY,
                    font = fontText,
                    r = 0.55, g = 0.75, b = 0.95, a = 1.0
                })
                currentY = currentY + spacing
                
            else
                local lbl = line.label and (line.label .. ": ") or ""
                local val = line.value or ""
                table.insert(renderQueue, {
                    type = "text",
                    text = lbl .. val,
                    x = x + 8,
                    y = currentY,
                    font = fontText,
                    r = Config.Colors.TextLabel.r,
                    g = Config.Colors.TextLabel.g,
                    b = Config.Colors.TextLabel.b,
                    a = 1.0
                })
                currentY = currentY + spacing
            end
        end
    end
    
    return currentY - y
end


-- BLOCK 8: FOOTER (Tips and Description)
local Block_Footer = {}
Block_Footer.__index = Block_Footer

function Layout.createFooterBlock()
    return setmetatable({}, Block_Footer)
end

function Block_Footer:shouldRender(item)
    return true
end

function Block_Footer:measure(item, width)
    return 16, width
end

function Block_Footer:render(item, x, y, width, renderQueue)
    -- Bottom hint / tutorial instruction
    local isShiftDown = isShiftKeyDown()
    local text = "Hold [SHIFT] to compare"
    if isShiftDown then
        text = "Release [SHIFT] to inspect details"
    end
    
    table.insert(renderQueue, {
        type = "text",
        text = text,
        x = x,
        y = y,
        font = getUIFont("Text"),
        r = Config.Colors.TextMuted.r,
        g = Config.Colors.TextMuted.g,
        b = Config.Colors.TextMuted.b,
        a = 0.8
    })
    
    return 14
end
local Block_ClothingStats = {}
Block_ClothingStats.__index = Block_ClothingStats

function Layout.createClothingStatsBlock()
    return setmetatable({}, Block_ClothingStats)
end

function Block_ClothingStats:shouldRender(item)
    return item and instanceof(item, "Clothing")
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
            type = "text", text = label, x = x, y = currentY, font = getUIFont("Text"),
            r = Config.Colors.TextLabel.r, g = Config.Colors.TextLabel.g, b = Config.Colors.TextLabel.b, a = 1.0
        })
        local valWidth = getTextManager():MeasureStringX(getUIFont("Value"), valText)
        table.insert(renderQueue, {
            type = "text", text = valText, x = x + width - valWidth, y = currentY, font = getUIFont("Value"),
            r = r, g = g, b = b, a = 1.0
        })
        currentY = currentY + 18
    end

    if item:getInsulation() > 0 then
        addStat("Insulation", string.format("%.2f", item:getInsulation()), 0.4, 0.8, 0.4)
    end
    if item:getWindresistance() > 0 then
        addStat("Wind Resist", string.format("%.2f", item:getWindresistance()), 0.4, 0.8, 0.8)
    end
    if item:getWaterResistance() > 0 then
        addStat("Water Resist", string.format("%.2f", item:getWaterResistance()), 0.3, 0.5, 0.9)
    end
    if item:getRunSpeedModifier() ~= 1.0 then
        local mod = (item:getRunSpeedModifier() - 1.0) * 100
        addStat("Run Speed", string.format("%+.0f%%", mod), mod < 0 and 0.8 or 0.4, mod < 0 and 0.3 or 0.8, 0.3)
    end
    if item:getCombatSpeedModifier() ~= 1.0 then
        local mod = (item:getCombatSpeedModifier() - 1.0) * 100
        addStat("Combat Speed", string.format("%+.0f%%", mod), mod < 0 and 0.8 or 0.4, mod < 0 and 0.3 or 0.8, 0.3)
    end
    
    return currentY - y
end
