# ZFlexTooltip for Project Zomboid (Build 42)

![ZFlexTooltip Banner](poster.png)

**ZFlexTooltip** is a modern, modular, and universally compatible UI framework that replaces the standard Project Zomboid tooltips with a sleek **Tactical PDA** aesthetic.

Built from the ground up for B42, it uses a component-based rendering pipeline that reads item data via reflection, so modded items missing expected methods degrade gracefully instead of crashing the UI.

## 🌟 Features
* **Tactical PDA Aesthetic:** Smooth slide-in animations, dynamic height measurements, and a sleek dark-obsidian background with cyan/orange semantic accents.
* **Crash-Resistant (Capabilities API):** ZFlexTooltip reads item data via reflection (`Caps.hasMethod` / `safeInvoke`) rather than direct method calls, so modded items that are missing expected methods degrade gracefully instead of throwing Java exceptions.
* **Universal Context Wrapping:** The Tactical PDA frame applies to inventory items (`ISToolTipInv`), crafting recipes (`ISCraftRecipeTooltip`), and generic tooltips (`ISToolTip`).
* **Mod Compatibility:** Designed to coexist with UI-altering mods without hardcoded patches:
  * **Inventory Tetris / Equipment UI:** Hides the tooltip during active drag-and-drop and context menus.
  * **Gamepad:** Controller `joyfocus` navigation is respected.
  * **Arsenal / Brita / KI5 / AttachmentSystem:** Item data is read via reflection, so custom modded items do not crash the tooltip.
  * **TooltipLib:** Coexists via a deferred-mode trick (see source comments in `ZFlexTooltip_Main.lua`).

## 🛠️ Installation
Subscribe to the mod on the Steam Workshop, or download the latest release and extract it into your `C:\Users\YourName\Zomboid\mods\` folder.

## 📚 For Modders
ZFlexTooltip rebuilds its VBox layout every frame inside `buildLayoutState`. There is no global block registry yet, so to add a custom block you wrap one of the `Layout.create*Block` factories and return a **composite block** that renders the original content plus yours. Wrapping must preserve the original block — do not just return your own block or the original (e.g. the footer) will vanish.

```lua
local ZFT_Layout = ZFlexTooltip.Layout

local MyCustomBlock = {}
MyCustomBlock.__index = MyCustomBlock

function MyCustomBlock:shouldRender(item)
    return item and item:hasModData() and item:getModData().MyCoolStat ~= nil
end

function MyCustomBlock:measure(item, width)
    return 18, width
end

function MyCustomBlock:render(item, x, y, width, renderQueue)
    table.insert(renderQueue, {
        type = "text",
        text = "My Cool Stat: " .. tostring(item:getModData().MyCoolStat),
        x = x, y = y,
        font = UIFont.Small,
        r = 1, g = 0.5, b = 0, a = 1
    })
    return 18
end

-- Wrap the footer factory with a COMPOSITE that keeps the footer and appends ours.
Events.OnGameBoot.Add(function()
    if not (ZFT_Layout and ZFT_Layout.createFooterBlock) then return end
    local origCreateFooter = ZFT_Layout.createFooterBlock
    ZFT_Layout.createFooterBlock = function()
        local footerBlock = origCreateFooter()
        local customBlock = setmetatable({}, MyCustomBlock)
        -- Composite block: delegate shouldRender/measure, and in render draw
        -- the footer first then the custom block beneath it.
        return {
            shouldRender = function(self, item)
                return footerBlock:shouldRender(item) or customBlock:shouldRender(item)
            end,
            measure = function(self, item, width)
                local fh, fw = 0, width
                local ch, cw = 0, width
                if footerBlock:shouldRender(item) then fh, fw = footerBlock:measure(item, width) end
                if customBlock:shouldRender(item)  then ch, cw = customBlock:measure(item, width)  end
                return fh + ch, math.max(fw, cw)
            end,
            render = function(self, item, x, y, width, renderQueue)
                local dy = 0
                if footerBlock:shouldRender(item) then
                    dy = footerBlock:render(item, x, y, width, renderQueue)
                end
                if customBlock:shouldRender(item) then
                    dy = dy + customBlock:render(item, x, y + dy, width, renderQueue)
                end
                return dy
            end
        }
    end
end)
```

Note for modders: the composite must report a `measure` height equal to the sum of its parts, and its `render` must stack the sub-blocks vertically and return the total height — otherwise the VBox layout will mis-size the tooltip.

## 📜 License
MIT License. Feel free to use, modify, and distribute.
