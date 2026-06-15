# ZFlexTooltip for Project Zomboid (Build 42)

![ZFlexTooltip Banner](poster.png)

**ZFlexTooltip** is a modern, modular, and universally compatible UI framework that replaces the standard Project Zomboid tooltips with a sleek **Tactical PDA** aesthetic. 

Built from the ground up for B42, it uses a component-based rendering pipeline that completely eliminates the notorious UI crashes (CTD) caused by custom modded items, and perfectly integrates with all major UI mods out of the box.

## 🌟 Features
* **Tactical PDA Aesthetic:** Smooth slide-in animations, dynamic height measurements, and a sleek dark-obsidian background with cyan/orange semantic accents.
* **100% Crash-Proof Architecture (Capabilities API):** ZFlexTooltip safely negotiates with items using Reflection (`Caps.hasMethod`) instead of blindly throwing `pcall()`, completely eliminating Java exceptions and Kahlua GC spikes.
* **Universal Context Wrapping:** The Tactical PDA frame applies to *everything*. Inventory items, crafting stations (`ISCraftRecipeTooltip`), ground objects (`IsoObject`), animals, and vehicle mechanic panels.
* **Mod Compatibility Matrix:** Flawless integration with UI-altering giants without needing hardcoded patches:
  * ✅ **Inventory Tetris:** Preserves grid anchors and properly defers to Tetris layout logic.
  * ✅ **Equipment UI:** Respects Drag & Drop events without leaving ghost tooltips.
  * ✅ **Wookiee Gamepad Support:** Controller `joyfocus` navigation natively supported.
  * ✅ **Arsenal / Brita / KI5:** Gracefully handles complex custom item data.
* **Symbiosis with TooltipLib:** Coexists peacefully with `TooltipLib` via append-only deferred rendering.

## 🛠️ Installation
Subscribe to the mod on the Steam Workshop, or download the latest release and extract it into your `C:\Users\YourName\Zomboid\mods\` folder.

## 📚 For Modders
ZFlexTooltip provides an open `ZFlexTooltip.Layout` API. You can easily add your own custom blocks:

```lua
local MyCustomBlock = {}
MyCustomBlock.__index = MyCustomBlock

function MyCustomBlock:shouldRender(item)
    return item:hasModData() and item:getModData().MyCoolStat ~= nil
end

function MyCustomBlock:measure(item, width)
    return 24, width -- Height, Width
end

function MyCustomBlock:render(item, x, y, width, renderQueue)
    table.insert(renderQueue, {
        type = "text",
        text = "My Cool Stat: " .. tostring(item:getModData().MyCoolStat),
        x = x,
        y = y,
        color = { r = 1, g = 0.5, b = 0, a = 1 },
        font = UIFont.Small
    })
end

-- Insert it into the layout pipeline
Events.OnGameBoot.Add(function()
    if ZFlexTooltip and ZFlexTooltip.Layout then
        table.insert(ZFlexTooltip.Layout.pipeline, 1, setmetatable({}, MyCustomBlock))
    end
end)
```

## 📜 License
MIT License. Feel free to use, modify, and distribute.
