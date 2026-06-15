require "ZFlexTooltip/ZFlexTooltip_Config"
require "ZFlexTooltip/ZFlexTooltip_Capabilities"
require "ZFlexTooltip/ZFlexTooltip_Layout"

ZFlexTooltip = ZFlexTooltip or {}
ZFlexTooltip.active = true
ZFlexTooltip.CapturedDrawCalls = ZFlexTooltip.CapturedDrawCalls or {}
ZFlexTooltip.RenderQueue = ZFlexTooltip.RenderQueue or {}

local Config = ZFlexTooltip.Config
local Layout = ZFlexTooltip.Layout
local Caps = ZFlexTooltip.Capabilities

-- Vanilla keyword filtering and phantom hooks have been entirely removed
-- to guarantee 100% stability and zero Java Bridge exceptions.

-- STATE MANAGEMENT & CACHING (Separation of State)
----------------------------------------------------
local function generateItemHash(item)
    if not item then return "none" end
    local hash = tostring(item:getID())
    
    local cond = Caps.safeInvoke(item, "getCondition")
    if cond then hash = hash .. "_" .. tostring(cond) end
    
    local uses = Caps.safeInvoke(item, "getCurrentUses")
    if uses then hash = hash .. "_" .. tostring(uses) end
    
    local fCont = Caps.safeInvoke(item, "getFluidContainer")
    if fCont then
        local amt = Caps.safeInvoke(fCont, "getFluidAmount")
        if amt then hash = hash .. "_" .. tostring(amt) end
    end
    
    hash = hash .. "_" .. tostring(isShiftKeyDown())
    return hash
end

local function buildLayoutState(self, item)
    -- Recalculate only if item mutable state or shift key comparison state flips
    local currentHash = generateItemHash(item)
    
    if self.zflex_lastHash == currentHash then
        return self.zflex_cachedWidth or Config.Grid.MinWidth, self.zflex_cachedHeight or 100
    end
    
    self.zflex_lastHash = currentHash
    self.zflex_RenderQueue = {}

    -- Initialize VBox Layout
    local box = Layout.createVBox(Config.Grid.MinWidth)
    box:addBlock(Layout.createHeaderBlock())
    box:addBlock(Layout.createHeroStatBlock())
    box:addBlock(Layout.createProgressBarsBlock())
    box:addBlock(Layout.createFluidFlaskBlock())
    box:addBlock(Layout.createSocketsBlock())
    box:addBlock(Layout.createClothingStatsBlock())
    box:addBlock(Layout.createTagsBlock())
    box:addBlock(Layout.createAttachmentSystemBlock())
    box:addBlock(Layout.createLegacyModBlock())
    box:addBlock(Layout.createFooterBlock())

    -- Pass 1: Measure
    local finalWidth = box:measure(item)
    
    -- Pass 2: Generate draw instructions queue
    local finalHeight = box:generateQueue(item, self.zflex_RenderQueue)
    
    self.zflex_cachedWidth = finalWidth
    self.zflex_cachedHeight = finalHeight
    
    return finalWidth, finalHeight
end

----------------------------------------------------
-- CORE TOOLTIP RENDER & PRERENDER FUNCTIONS
----------------------------------------------------
function ZFlexTooltip.prerender(self)
    print("ZFLEXTOOLTIP: PRERENDER IS CALLED")
    -- Hide tooltip if context menu is active or during DragAndDrop (Equipment UI / Tetris compatibility)
    if ISContextMenu and ISContextMenu.instance and ISContextMenu.instance.visibleCheck then return end
    if DragAndDrop and type(DragAndDrop.getDraggedItem) == "function" then
        local ok, dragged = pcall(DragAndDrop.getDraggedItem)
        if ok and dragged then return end
    end
    
    -- Temporarily disable drawRect and drawRectBorder to prevent the vanilla background from flashing
    local origRect = self.drawRect
    local origRectBorder = self.drawRectBorder
    self.drawRect = function() end
    self.drawRectBorder = function() end

    if ZFlexTooltip.originalPrerender then
        ZFlexTooltip.originalPrerender(self)
    end

    -- Restore drawing methods
    self.drawRect = origRect
    self.drawRectBorder = origRectBorder

    if not self.item then return end

    -- Build layout state safely without pcall overhead
    local w, h = buildLayoutState(self, self.item)
    if not w then return end

    -- Run position constraints and clamping to screen boundaries
    local mx = getMouseX() + 24
    local my = getMouseY() + 24
    
    -- Proper Controller/Joypad support & static anchoring
    if self.joyfocus then
        mx = self:getX()
        my = self:getY()
        if self.anchorBottomLeft then
            mx = self.anchorBottomLeft.x
            my = self.anchorBottomLeft.y
        end
    elseif not self.followMouse then
        mx = self:getX()
        my = self:getY()
        if self.anchorBottomLeft then
            mx = self.anchorBottomLeft.x
            my = self.anchorBottomLeft.y
        end
    end

    local myCore = getCore()
    local maxX = myCore:getScreenWidth()
    local maxY = myCore:getScreenHeight()

    self:setWidth(w)
    self:setHeight(h)

    -- Force round coordinates to prevent pixel jittering
    local newX = math.floor(math.max(0, math.min(mx, maxX - w - 1)))
    local newY = math.floor(math.max(0, math.min(my, maxY - h - 1)))
    
    if (not self.followMouse or self.joyfocus) and self.anchorBottomLeft then
        newY = math.floor(math.max(0, math.min(my - h, maxY - h - 1)))
    end
    
    self:setX(newX)
    self:setY(newY)
end

function ZFlexTooltip.render(self)
    print("ZFLEXTOOLTIP: RENDER IS CALLED FOR " .. tostring(self.item and self.item:getName() or "NIL"))
    if not self.item then return end
    
    -- Hide tooltip if context menu is active or during DragAndDrop (Equipment UI / Tetris compatibility)
    if ISContextMenu and ISContextMenu.instance and ISContextMenu.instance.visibleCheck then return end
    if DragAndDrop and type(DragAndDrop.getDraggedItem) == "function" then
        local ok, dragged = pcall(DragAndDrop.getDraggedItem)
        if ok and dragged then return end
    end
    
    self.zflexActive = true
    -- Animation State Updates
    local currentItemId = self.item:getID()
    local time = getTimeInMillis()
    
    self.zflex_AnimState = self.zflex_AnimState or { itemId = nil, startTime = 0, fade = 0.0, slideY = 0 }
    
    if self.zflex_AnimState.itemId ~= currentItemId then
        self.zflex_AnimState.itemId = currentItemId
        self.zflex_AnimState.startTime = time
        self.zflex_AnimState.fade = 0.0
        self.zflex_AnimState.slideY = 20
    end
    
    local animProgress = math.min(1.0, (time - self.zflex_AnimState.startTime) / 120.0)
    -- Ease out quad
    local easeOut = animProgress * (2 - animProgress)
    self.zflex_AnimState.fade = easeOut
    self.zflex_AnimState.slideY = math.floor(20 * (1 - easeOut))

    -- Build layout state safely
    local w, h = buildLayoutState(self, self.item)
    if not w then return end

    local w = self:getWidth()
    local h = self:getHeight()
    local renderYOffset = self.zflex_AnimState.slideY

    -- IMPORTANT: Sync native tooltip height so TooltipLib knows where our custom box ends!
    if self.tooltip then
        self.tooltip:setHeight(h)
        self.tooltip:setWidth(w)
    end

    -- 1. Draw Custom background Card (Tactical PDA Base)
    local bg = Config.Colors.BgBase
    local border = Config.Colors.BorderBase
    
    -- Apply global alpha fade
    local baseAlpha = bg.a * self.zflex_AnimState.fade
    local borderAlpha = border.a * self.zflex_AnimState.fade
    
    self:drawRect(0, renderYOffset, w, h, baseAlpha, bg.r, bg.g, bg.b)
    self:drawRectBorder(0, renderYOffset, w, h, borderAlpha, border.r, border.g, border.b)

    -- 2. Process Render Queue
    local renderQueue = self.zflex_RenderQueue or {}
    for _, cmd in ipairs(renderQueue) do
        local drawY = cmd.y + renderYOffset
        if cmd.type == "text" then
            self:drawText(cmd.text, cmd.x, drawY, cmd.r, cmd.g, cmd.b, cmd.a * self.zflex_AnimState.fade, cmd.font)
        elseif cmd.type == "texture" then
            self:drawTextureScaled(cmd.texture, cmd.x, drawY, cmd.w, cmd.h, cmd.a * self.zflex_AnimState.fade, cmd.r, cmd.g, cmd.b)
        elseif cmd.type == "rect" then
            self:drawRect(cmd.x, drawY, cmd.w, cmd.h, cmd.color.a * self.zflex_AnimState.fade, cmd.color.r, cmd.color.g, cmd.color.b)
        elseif cmd.type == "rect_border" then
            self:drawRectBorder(cmd.x, drawY, cmd.w, cmd.h, cmd.color.a * self.zflex_AnimState.fade, cmd.color.r, cmd.color.g, cmd.color.b)
        end
    end
    print("ZFLEXTOOLTIP: RENDER SUCCESS")
    
    -- =========================================================================
    -- TOOLTIPLIB DEFERRED MODE TRICK:
    -- We want TooltipLib to draw its stats at the bottom of our PDA.
    -- But we DO NOT want the vanilla tooltip to be drawn by other aggressive mods.
    -- Vanilla and most mods (like Tempo_PerfKit) check `ISContextMenu.instance.visibleCheck`.
    -- If it's true, they abort drawing completely. TooltipLib does NOT check this.
    -- So we set it to true, call TooltipLib, and it enters Deferred Mode perfectly!
    -- =========================================================================
    local contextWasVisible = nil
    local createdDummyContext = false
    
    if ISContextMenu then
        if not ISContextMenu.instance then
            ISContextMenu.instance = { visibleCheck = true }
            createdDummyContext = true
        else
            contextWasVisible = ISContextMenu.instance.visibleCheck
            ISContextMenu.instance.visibleCheck = true
        end
    end

    if ZFlexTooltip.originalRender then
        ZFlexTooltip.originalRender(self)
    end

    if ISContextMenu then
        if createdDummyContext then
            ISContextMenu.instance = nil
        elseif contextWasVisible ~= nil then
            ISContextMenu.instance.visibleCheck = contextWasVisible
        end
    end
end

----------------------------------------------------
-- CONTEXT: B42 CRAFTING & RECIPES (ISCraftRecipeTooltip)
----------------------------------------------------
function ZFlexTooltip.craftingPrerender(self)
    -- B42 Crafting UI relies on ISPanel's background drawing in prerender.
    -- We temporarily mute the vanilla background and draw our own Tactical PDA frame.
    local origA = self.backgroundColor.a
    local origBorderA = self.borderColor.a
    self.backgroundColor.a = 0
    self.borderColor.a = 0
    
    if ZFlexTooltip.originalCraftingPrerender then
        ZFlexTooltip.originalCraftingPrerender(self)
    end
    
    local w = self:getWidth()
    local h = self:getHeight()
    local bg = Config.Colors.BgBase
    local border = Config.Colors.BorderBase
    
    self:drawRect(0, 0, w, h, bg.a, bg.r, bg.g, bg.b)
    self:drawRectBorder(0, 0, w, h, border.a, border.r, border.g, border.b)
    
    self.backgroundColor.a = origA
    self.borderColor.a = origBorderA
end

----------------------------------------------------
-- CONTEXT: B41 LEGACY & GENERIC TOOLTIPS (ISToolTip)
----------------------------------------------------
function ZFlexTooltip.genericRender(self)
    -- ISToolTip hardcodes background draw calls in render().
    -- We intercept drawRect/drawRectBorder to inject our Tactical PDA frame dynamically.
    local origRect = self.drawRect
    local origRectBorder = self.drawRectBorder
    
    local w = self.width or self:getWidth()
    local h = self.height or self:getHeight()
    local bg = Config.Colors.BgBase
    local border = Config.Colors.BorderBase
    
    self.drawRect = function(s, x, y, w2, h2, a, r, g, b)
        if x == 0 and y == 0 and w2 == w and h2 == h then
            origRect(s, x, y, w2, h2, bg.a, bg.r, bg.g, bg.b)
        else
            origRect(s, x, y, w2, h2, a, r, g, b)
        end
    end
    
    self.drawRectBorder = function(s, x, y, w2, h2, a, r, g, b)
        if x == 0 and y == 0 and w2 == w and h2 == h then
            origRectBorder(s, x, y, w2, h2, border.a, border.r, border.g, border.b)
        else
            origRectBorder(s, x, y, w2, h2, a, r, g, b)
        end
    end
    
    if ZFlexTooltip.originalGenericRender then
        ZFlexTooltip.originalGenericRender(self)
    end
    
    self.drawRect = origRect
    self.drawRectBorder = origRectBorder
end

----------------------------------------------------
-- MOD HOOK INSTALLATION
----------------------------------------------------
function ZFlexTooltip.install()
    if ISToolTipInv and ISToolTipInv.render then
        if ISToolTipInv.render == ZFlexTooltip.render then return end
        
        ZFlexTooltip.originalRender = ISToolTipInv.render
        ISToolTipInv.render = ZFlexTooltip.render
        
        ZFlexTooltip.originalPrerender = ISToolTipInv.prerender
        ISToolTipInv.prerender = ZFlexTooltip.prerender
        print("ZFlexTooltip: Successfully hooked ISToolTipInv.render and prerender")
    end
        
    if ISCraftRecipeTooltip and ISCraftRecipeTooltip.prerender then
        if ISCraftRecipeTooltip.prerender ~= ZFlexTooltip.craftingPrerender then
            ZFlexTooltip.originalCraftingPrerender = ISCraftRecipeTooltip.prerender
            ISCraftRecipeTooltip.prerender = ZFlexTooltip.craftingPrerender
            print("ZFlexTooltip: Successfully hooked ISCraftRecipeTooltip.prerender")
        end
    end

    if ISToolTip and ISToolTip.render then
        if ISToolTip.render ~= ZFlexTooltip.genericRender then
            ZFlexTooltip.originalGenericRender = ISToolTip.render
            ISToolTip.render = ZFlexTooltip.genericRender
            print("ZFlexTooltip: Successfully hooked ISToolTip.render")
        end
    end
end

local function InstallOnTick()
    Events.OnTick.Remove(InstallOnTick)
    ZFlexTooltip.install()
    print("ZFLEXTOOLTIP: ONTICK INSTALL EXECUTED (BYPASSING AGGRESSIVE MODS)")
end

Events.OnTick.Add(InstallOnTick)

