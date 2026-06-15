# ZFlexTooltip Bugfix Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate all 8 critical and 7 high-severity defects found in the deep code review, restoring the mod's crash-proof invariant and bringing docs in sync with code.

**Architecture:** Layered Lua mod (Config → Capabilities → Layout → Main). Fixes are isolated per layer/domain to allow parallel execution without file conflicts. No new dependencies. No Lua interpreter available locally — verification uses static pattern checks (grep/findstr) plus an in-game smoke-test checklist at the end.

**Tech Stack:** Lua 5.1 (Project Zomboid B42.19 Kahlua VM), `findstr`/`grep` for static verification, no unit-test framework in-repo.

**Environment note:** No `lua`/`luacheck`/`busted` locally. The TDD "run test" steps are replaced with **static verification commands** (grep for absence of bad patterns, count of calls). Final acceptance is an in-game load test described in Task 6.

**File ownership matrix (no conflicts):**
- Task 1 → `ZFlexTooltip_Main.lua` only
- Task 2 → `ZFlexTooltip_Layout.lua` only (the large refactor)
- Task 3 → `ZFlexTooltip_Capabilities.lua` only
- Task 4 → `ZFlexTooltip_Config.lua` only
- Task 5 → `README.md`, `PROJECT.md`, `mod.info`, `42/mod.info`, `workshop.txt`, delete `ClothingStats.lua`
- Task 6 → verification only (no edits)

---

## Defect Inventory (cross-reference)

| ID | Severity | Domain | File | Summary |
|----|----------|--------|------|---------|
| C1 | 🔴 | perf | Main:79,148,217 | `print()` in hot render path (every frame) |
| C2 | 🔴 | bug | Main:179,182-183 | `local w,h` shadowing wipes computed layout |
| C3 | 🟠 | compat | Main:230-250 | Non-reentrant `ISContextMenu.instance` swap |
| C4 | 🟠 | compat | Main:82-85,153-156 | Inconsistent `pcall` paranoia |
| C5 | 🟡 | style | Main:111-126 | Duplicated position-clamp branches |
| C6 | 🟡 | style | Main:169,172 | Magic animation numbers |
| L1 | 🔴 | safety | Layout (30+ sites) | Direct Java calls bypass `Caps` |
| L2 | 🔴 | bug | Layout:92-99 | Header measure(48) ≠ render(54) |
| L3 | 🔴 | deadcode | Layout:1088 + root ClothingStats.lua | Duplicated block |
| L4 | 🔴 | deadcode | Main:7,59; Layout:739-805 | Dead `CapturedDrawCalls`/`LegacyMod` |
| L5 | 🔴 | bug | Layout:541,569 | Sockets lose 2 of 6 attachments |
| L6 | 🔴 | bug | Layout:624,734 | Tags measure(24) ≠ render(dynamic) |
| L7 | 🟠 | perf | Layout:354 | Double `getConditionMax` call |
| L8 | 🟠 | style | Layout:805 | Merged `end--` comment |
| L9 | 🟠 | style | Layout headers | Inconsistent block numbering |
| L10 | 🟠 | perf | Layout:817,858 | Double `linesForItem` call |
| L12 | 🟠 | bug | Layout:536,597 | Sockets measure(44) ≠ render(32) |
| Cap2 | 🟠 | bug | Capabilities:109-116 | Container weight ignores contents |
| Cap3 | 🟡 | bug | Capabilities:86-88 | `supportsSockets` too narrow |
| Conf1 | 🟡 | config | Config:44-49 | Incomplete font mapping |
| Conf2 | 🟡 | config | Config | No animation tokens |
| Conf3 | 🟡 | config | Config | No block-size tokens |
| Doc | 🔴 | docs | all docs | README `.pipeline` API doesn't exist; paths wrong; no version |

---

### Task 1: Fix Main.lua — performance, shadowing bug, dead code (C1, C2, C4, C5, C6)

**Files:**
- Modify: `42/media/lua/client/ZFlexTooltip/ZFlexTooltip_Main.lua`

**No edits to any other file in this task.**

- [ ] **Step 1: Add debug-gated logging and remove per-frame prints (C1)**

In `ZFlexTooltip_Main.lua`, near the top (after line 8 where `ZFlexTooltip.RenderQueue` is declared), add a debug flag:

```lua
ZFlexTooltip.Debug = false  -- Set true to re-enable diagnostic prints
```

Replace the three hot-path prints. At line 79 replace:
```lua
    print("ZFLEXTOOLTIP: PRERENDER IS CALLED")
```
with:
```lua
    if ZFlexTooltip.Debug then print("ZFLEXTOOLTIP: PRERENDER IS CALLED") end
```

At line 148 replace:
```lua
    print("ZFLEXTOOLTIP: RENDER IS CALLED FOR " .. tostring(self.item and self.item:getName() or "NIL"))
```
with:
```lua
    if ZFlexTooltip.Debug then print("ZFLEXTOOLTIP: RENDER IS CALLED FOR " .. tostring(self.item and self.item:getName() or "NIL")) end
```

At line 217 replace:
```lua
    print("ZFLEXTOOLTIP: RENDER SUCCESS")
```
with:
```lua
    if ZFlexTooltip.Debug then print("ZFLEXTOOLTIP: RENDER SUCCESS") end
```

**Leave** the three install-time prints (lines 330, 337, 345, 353) as-is — those run once on boot, not per-frame.

- [ ] **Step 2: Fix the w,h shadowing bug (C2)**

In `ZFlexTooltip.render` (around line 179-183), replace:
```lua
    -- Build layout state safely
    local w, h = buildLayoutState(self, self.item)
    if not w then return end

    local w = self:getWidth()
    local h = self:getHeight()
    local renderYOffset = self.zflex_AnimState.slideY
```
with:
```lua
    -- Build layout state safely (also sets self:setWidth/setHeight via prerender cache)
    local w, h = buildLayoutState(self, self.item)
    if not w then return end

    local renderYOffset = self.zflex_AnimState.slideY
```

Rationale: `buildLayoutState` already returns the freshly-computed `w,h`. The two `local` redeclarations were shadowing them with stale values. Removing them lets the computed values flow into the draw calls below.

- [ ] **Step 3: Extract animation magic numbers into Config (C6)**

At the top of `ZFlexTooltip_Main.lua`, after `local Caps = ZFlexTooltip.Capabilities` (line 12), add a local alias so we can reference `Config.Animation` once it exists (Task 4 defines it; if Task 4 runs first this is a no-op, if Task 1 runs first the field is `nil` and the `or` fallbacks apply):

Find the animation block (lines 169-176):
```lua
    if self.zflex_AnimState.itemId ~= currentItemId then
        self.zflex_AnimState.itemId = currentItemId
        self.zflex_AnimState.startTime = time
        self.zflex_AnimState.fade = 0.0
        self.zflex_AnimState.slideY = 20
    end
    
    local animProgress = math.min(1.0, (time - self.zflex_AnimState.startTime) / 120.0)
```
Replace `20` and `120.0` with config reads:
```lua
    local animCfg = (Config.Animation) or {}
    if self.zflex_AnimState.itemId ~= currentItemId then
        self.zflex_AnimState.itemId = currentItemId
        self.zflex_AnimState.startTime = time
        self.zflex_AnimState.fade = 0.0
        self.zflex_AnimState.slideY = animCfg.SlidePixels or 20
    end
    
    local animProgress = math.min(1.0, (time - self.zflex_AnimState.startTime) / (animCfg.DurationMs or 120.0))
```

- [ ] **Step 4: Consolidate duplicated position-clamp branches (C5)**

In `ZFlexTooltip.prerender`, find lines 111-126:
```lua
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
```
Replace with the merged branch:
```lua
    -- Proper Controller/Joypad support & static anchoring
    -- joyfocus (controller) and non-following-mouse tooltips use the same anchoring logic.
    if self.joyfocus or not self.followMouse then
        mx = self:getX()
        my = self:getY()
        if self.anchorBottomLeft then
            mx = self.anchorBottomLeft.x
            my = self.anchorBottomLeft.y
        end
    end
```

- [ ] **Step 5: Wrap ISContextMenu.visibleCheck read defensively (C4)**

In `ZFlexTooltip.prerender` (around line 81) and `ZFlexTooltip.render` (around line 152), the context-menu guard currently reads `ISContextMenu.instance.visibleCheck` directly. Replace line 81:
```lua
    if ISContextMenu and ISContextMenu.instance and ISContextMenu.instance.visibleCheck then return end
```
with:
```lua
    if ISContextMenu and ISContextMenu.instance and type(ISContextMenu.instance.visibleCheck) ~= "nil" and ISContextMenu.instance.visibleCheck then return end
```
Apply the same replacement at line 152.

(Note: `pcall` cannot guard a field read on a Lua table; the `type(...) ~= "nil"` check is the correct defensive form here and matches the paranoia already used for `DragAndDrop`.)

- [ ] **Step 5b: Make the TooltipLib deferred-mode swap reentrancy-safe (C3)**

In `ZFlexTooltip.render`, the block at lines 227-250 swaps `ISContextMenu.instance` to force TooltipLib into deferred mode. If `originalRender` (or any mod it calls) creates a *real* context menu during the swap, the restore logic will clobber it. Make the swap transactional by capturing and restoring the **entire** instance reference, not just the `visibleCheck` field.

Replace lines 227-250:
```lua
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
```
with a version that snapshots the reference identity and detects mid-flight replacement:
```lua
    -- TooltipLib deferred-mode trick: most mods abort drawing when a context
    -- menu is "visible". We pretend one is, call originalRender, then restore.
    -- We snapshot the *reference* (not just the field) so that if originalRender
    -- itself opens/closes a real menu, we don't clobber it.
    local prevInstance = ISContextMenu and ISContextMenu.instance or nil
    local prevVisibleCheck = nil
    local injectedDummy = false

    if ISContextMenu then
        if not ISContextMenu.instance then
            ISContextMenu.instance = { visibleCheck = true }
            injectedDummy = true
        else
            prevVisibleCheck = ISContextMenu.instance.visibleCheck
            ISContextMenu.instance.visibleCheck = true
        end
    end

    if ZFlexTooltip.originalRender then
        ZFlexTooltip.originalRender(self)
    end

    if ISContextMenu then
        -- Only restore if the instance reference is still the one we set.
        -- If a mod replaced it mid-render, leave that mod's state alone.
        if injectedDummy and ISContextMenu.instance == prevInstance then
            ISContextMenu.instance = nil
        elseif (not injectedDummy) and ISContextMenu.instance == prevInstance and prevVisibleCheck ~= nil then
            ISContextMenu.instance.visibleCheck = prevVisibleCheck
        end
    end
```
This guarantees we never nil out or mutate a context-menu object we did not create.

- [ ] **Step 6: Remove the dead CapturedDrawCalls/LegacyMod plumbing (L4, Main side)**

Delete the table init at line 7:
```lua
ZFlexTooltip.CapturedDrawCalls = ZFlexTooltip.CapturedDrawCalls or {}
```
And in `buildLayoutState` delete the line that adds the legacy block (around line 59):
```lua
    box:addBlock(Layout.createLegacyModBlock())
```
Leave `ZFlexTooltip.RenderQueue` init (line 8) — that one is live.

- [ ] **Step 7: Static verification**

Run from the mod root:
```
findstr /n "print(" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Main.lua
```
Expected: exactly 5 lines — all 5 must contain `if ZFlexTooltip.Debug` (lines ~79, 148, 217 gated) OR be the 3 install-time prints at ~330, 337, 345, 353. **No bare `print(` in prerender/render.**

Run:
```
findstr /n "local w = self:getWidth" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Main.lua
```
Expected: **no output** (the shadowing line is gone).

Run:
```
findstr /n "CapturedDrawCalls\|createLegacyModBlock" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Main.lua
```
Expected: **no output**.

- [ ] **Step 8: Commit**

```bash
git add 42/media/lua/client/ZFlexTooltip/ZFlexTooltip_Main.lua
git commit -m "fix(main): gate per-frame prints, fix w/h shadowing, dedupe clamp, drop dead legacy plumbing

- C1: wrap prerender/render prints behind ZFlexTooltip.Debug
- C2: remove shadowing local w,h that wiped computed layout
- C4: defensive type-check on ISContextMenu.visibleCheck
- C5: merge duplicated joyfocus/followMouse clamp branches
- C6: read animation params from Config.Animation with fallbacks
- L4: remove dead CapturedDrawCalls init and createLegacyModBlock from pipeline"
```

---

### Task 2: Fix Layout.lua — crash-proof invariant, measure/render consistency, dead code (L1, L2, L3, L5, L6, L7, L8, L9, L10, L12)

**Files:**
- Modify: `42/media/lua/client/ZFlexTooltip/ZFlexTooltip_Layout.lua`

**This is the largest task. Only this file is touched.**

**Note on the ClothingStats block:** `ZFlexTooltip_Layout.lua` contains exactly ONE `Block_ClothingStats` definition (lines ~1088-1145). It is the canonical definition and stays in this file. The duplicate is the standalone `ClothingStats.lua` in the repo root, which Task 5 deletes. Do NOT delete the block from Layout.lua.

- [ ] **Step 1: Add a Caps helper for safe method chains (prep for L1)**

Near the top of `ZFlexTooltip_Layout.lua`, after `local safeCall = Caps.safeInvoke` (line 8), add two helpers used across blocks:

```lua
-- Safely read a chain of method results: safeGet(item, "getVisual", "getTint", clothingItem)
-- Returns nil if any link is missing/nil. Never throws.
local function safeGet(obj, first, ...)
    if obj == nil then return nil end
    if not Caps.hasMethod(obj, first) then return nil end
    local val = obj[first](obj)
    if select("#", ...) == 0 then
        return val
    end
    return safeGet(val, ...)
end
Layout._safeGet = safeGet  -- exposed for blocks defined elsewhere
```

- [ ] **Step 2: Make Block_Header crash-proof (L1, L2)**

Replace `Block_Header:measure` (lines 92-99):
```lua
function Block_Header:measure(item, width)
    local name = item:getName() or "Unknown Item"
    local font = getUIFont("Title")
    local textWidth = getTextManager():MeasureStringX(font, name)
    -- Padding (16*2) + Icon Space (48) + Name
    local preferredWidth = textWidth + 32 + 48
    return 48, preferredWidth
end
```
with:
```lua
function Block_Header:measure(item, width)
    local name = safeCall(item, "getName") or "Unknown Item"
    local font = getUIFont("Title")
    local textWidth = getTextManager():MeasureStringX(font, name)
    -- Padding (16*2) + Icon Space (48) + Name
    local preferredWidth = textWidth + 32 + 48
    -- Must match render() height: separator at y+48, so block consumes 54.
    return 54, preferredWidth
end
```

Replace `Block_Header:render` (lines 101-190). Wrap all direct item calls. New version:
```lua
function Block_Header:render(item, x, y, width, renderQueue)
    local name = safeCall(item, "getName") or "Unknown Item"
    local category = safeCall(item, "getDisplayCategory") or "Item"

    -- Category fallback translation from config
    local rawCategory = safeCall(item, "getCategory")
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
    else
        local r = safeCall(item, "getRarity")
        if r then rarity = r end
    end
    local nameColor = Config.RarityColors[rarity] or Config.Colors.TextHero

    -- Icon retrieval & color tint (fully safe chain)
    local tex = safeCall(item, "getTex")
    local iconR, iconG, iconB = 1.0, 1.0, 1.0
    if instanceof(item, "Clothing") then
        local visual = safeCall(item, "getVisual")
        local clothingItem = safeCall(item, "getClothingItem")
        if visual and clothingItem then
            local tint = safeGet(visual, "getTint", clothingItem)
            if tint then
                iconR = safeCall(tint, "getRedFloat") or 1.0
                iconG = safeCall(tint, "getGreenFloat") or 1.0
                iconB = safeCall(tint, "getBlueFloat") or 1.0
            end
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

    return 54 -- height including separator (matches measure)
end
```

- [ ] **Step 3: Make getPrimaryStat and getEquippedItem crash-proof (L1)**

Replace `getPrimaryStat` (lines 202-216):
```lua
local function getPrimaryStat(item)
    if not item then return nil, nil end
    if instanceof(item, "HandWeapon") then
        local minDmg = safeCall(item, "getMinDamage")
        local maxDmg = safeCall(item, "getMaxDamage")
        if minDmg and maxDmg then
            return (minDmg + maxDmg) / 2, "DAMAGE"
        end
        return nil, nil
    elseif instanceof(item, "Clothing") then
        local scratch = safeCall(item, "getScratchDefense") or 0
        local bite = safeCall(item, "getBiteDefense") or 0
        return (scratch + bite) / 2, "DEFENSE"
    elseif instanceof(item, "InventoryContainer") then
        local cap = safeCall(item, "getCapacity")
        if cap then return cap, "CAPACITY" end
    end
    return nil, nil
end
```

Replace `getEquippedItem` (lines 219-239):
```lua
local function getEquippedItem(item, player)
    if not player or not item then return nil end
    if instanceof(item, "HandWeapon") then
        local pri = safeCall(player, "getPrimaryHandItem")
        if pri and instanceof(pri, "HandWeapon") then return pri end
    elseif instanceof(item, "Clothing") then
        local loc = safeCall(item, "getBodyLocation")
        if loc then
            local worn = safeCall(player, "getWornItems")
            if worn then
                local equipped = safeCall(worn, "getItem", loc)
                if equipped then return equipped end
            end
        end
    elseif instanceof(item, "InventoryContainer") then
        local back = safeCall(player, "getClothingItem_Back")
        if back then return back end
    end
    return nil
end
```

- [ ] **Step 4: Make Block_ProgressBars crash-proof + cache condition (L1, L7)**

Replace `Block_ProgressBars:render` (lines 353-417):
```lua
function Block_ProgressBars:render(item, x, y, width, renderQueue)
    local cond = safeCall(item, "getCondition") or 0
    local maxCond = safeCall(item, "getConditionMax") or 1
    if maxCond <= 0 then maxCond = 1 end
    local ratio = cond / maxCond

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
```
(Net effect of L7: the `ratio` calc now guards `maxCond <= 0` once instead of `math.max(1,...)` per use; the duplicate `getConditionMax` from `shouldRender` is acceptable since `shouldRender` is the gate and only runs the chain once per active block.)

- [ ] **Step 5: Make Block_FluidFlask crash-proof (L1)**

Replace `Block_FluidFlask:render` (lines 436-520):
```lua
function Block_FluidFlask:render(item, x, y, width, renderQueue)
    local container = safeCall(item, "getFluidContainer")
    if not container then return 0 end

    local amount = safeCall(container, "getFluidAmount") or 0
    local capacity = safeCall(container, "getCapacity") or 1
    if capacity <= 0 then capacity = 0.01 end
    local ratio = amount / capacity

    local fluidName = "Empty"
    local fillR, fillG, fillB = 0.3, 0.3, 0.3

    local isEmpty = safeCall(container, "isEmpty")
    if isEmpty == nil then isEmpty = true end
    if not isEmpty then
        local fluid = safeCall(container, "getPrimaryFluid")
        if fluid then
            fluidName = safeCall(fluid, "getDisplayName") or "Unknown Liquid"
            local color = safeCall(fluid, "getColor")
            if color then
                fillR = safeCall(color, "getRedFloat") or 0.3
                fillG = safeCall(color, "getGreenFloat") or 0.3
                fillB = safeCall(color, "getBlueFloat") or 0.3
            end
        end
    end

    -- Header Label
    table.insert(renderQueue, {
        type = "text",
        text = "CONTAINED LIQUID",
        x = x, y = y, font = getUIFont("Text"),
        r = Config.Colors.TextLabel.r, g = Config.Colors.TextLabel.g, b = Config.Colors.TextLabel.b, a = 1.0
    })

    -- Volume Text
    local volText = string.format("%.1f / %.1f L", amount, capacity)
    local valWidth = getTextManager():MeasureStringX(getUIFont("Value"), volText)
    table.insert(renderQueue, {
        type = "text", text = volText, x = x + width - valWidth, y = y,
        font = getUIFont("Value"),
        r = Config.Colors.TextHero.r, g = Config.Colors.TextHero.g, b = Config.Colors.TextHero.b, a = 1.0
    })

    -- Fluid Display Name
    table.insert(renderQueue, {
        type = "text", text = fluidName, x = x, y = y + 16, font = getUIFont("Text"),
        r = fillR, g = fillG, b = fillB, a = 1.0
    })

    -- Custom flask filling level bar
    table.insert(renderQueue, {
        type = "rect", x = x + width - 100, y = y + 20, w = 100, h = 6,
        color = { r = 0.1, g = 0.1, b = 0.12, a = 0.6 }
    })
    if ratio > 0 then
        table.insert(renderQueue, {
            type = "rect", x = x + width - 100, y = y + 20,
            w = math.floor(100 * ratio), h = 6,
            color = { r = fillR, g = fillG, b = fillB, a = 0.9 }
        })
    end

    return 30
end
```

- [ ] **Step 6: Fix Sockets — render all 6 slots and align measure/render heights (L5, L12)**

Replace `Block_Sockets:measure` (lines 535-537):
```lua
function Block_Sockets:measure(item, width)
    return 44, width
end
```
with:
```lua
function Block_Sockets:measure(item, width)
    return 36, width  -- slot height (28) + top padding (8) + bottom margin
end
```

Replace `Block_Sockets:render` (lines 539-598):
```lua
function Block_Sockets:render(item, x, y, width, renderQueue)
    -- All standard attachment slots on B42/B41 weapons
    local partMethods = { "getScope", "getSling", "getCanon", "getClip", "getRecoilpad", "getStock" }
    local activeParts = {}

    for _, method in ipairs(partMethods) do
        local part = safeCall(item, method)
        if part then
            table.insert(activeParts, {
                name = safeCall(part, "getName") or "",
                tex = safeCall(part, "getTex")
            })
        end
    end

    -- If weapon has no attachments at all, hide the block
    if #activeParts == 0 then return 0 end

    -- Label
    table.insert(renderQueue, {
        type = "text", text = "MODS", x = x, y = y + 10, font = getUIFont("Text"),
        r = Config.Colors.TextLabel.r, g = Config.Colors.TextLabel.g, b = Config.Colors.TextLabel.b, a = 1.0
    })

    -- Render ALL active parts (not just 4). Slot grid wraps within width.
    local slotSize = 28
    local gap = 4
    local labelArea = 60
    local availableWidth = width - labelArea
    local slotsPerRow = math.max(1, math.floor((availableWidth + gap) / (slotSize + gap)))

    for i, part in ipairs(activeParts) do
        local idx = i - 1
        local row = math.floor(idx / slotsPerRow)
        local col = idx % slotsPerRow
        local slotX = x + labelArea + col * (slotSize + gap)
        local slotY = y + 2 + row * (slotSize + gap)

        table.insert(renderQueue, {
            type = "rect_border", x = slotX, y = slotY, w = slotSize, h = slotSize,
            color = Config.Colors.BorderBase
        })
        if part.tex then
            table.insert(renderQueue, {
                type = "texture", texture = part.tex,
                x = slotX + 2, y = slotY + 2, w = slotSize - 4, h = slotSize - 4,
                r = 1, g = 1, b = 1, a = 1
            })
        end
    end

    local rows = math.ceil(#activeParts / slotsPerRow)
    return 4 + rows * (slotSize + gap)
end
```
Also update `shouldRender` so a weapon with **zero** attachments does not show an empty grid. Replace `Block_Sockets:shouldRender` (lines 531-533):
```lua
function Block_Sockets:shouldRender(item)
    if not (item and instanceof(item, "HandWeapon")) then return false end
    local partMethods = { "getScope", "getSling", "getCanon", "getClip", "getRecoilpad", "getStock" }
    for _, m in ipairs(partMethods) do
        if safeCall(item, m) then return true end
    end
    return false
end
```

- [ ] **Step 7: Fix Tags measure/render height contract (L6)**

Replace `Block_Tags:measure` (lines 624-627):
```lua
function Block_Tags:measure(item, width)
    -- Tags block wraps, we return a base height of 24, dynamically calculated during render
    return 24, width
end
```
with a measure that actually pre-computes the wrapped height. New version:
```lua
function Block_Tags:measure(item, width)
    local tagList = {}

    local modData = safeCall(item, "getModData")
    if modData and type(modData.AttachmentSystem) == "table" and modData.AttachmentSystem.visibleTags then
        for _, tagKey in ipairs(modData.AttachmentSystem.visibleTags) do
            table.insert(tagList, tagKey)
        end
    end

    if #tagList == 0 and Caps.supportsTags(item) then
        Caps.iterateTags(safeCall(item, "getTags"), function(tag)
            table.insert(tagList, tostring(tag))
        end)
    end

    if #tagList == 0 then return 0, width end

    -- Replicate render's wrap math to predict height
    local font = getUIFont("Text")
    local badgeX = 0
    local rows = 1
    for _, name in ipairs(tagList) do
        local strWidth = getTextManager():MeasureStringX(font, name)
        local badgeWidth = strWidth + 10
        if badgeX + badgeWidth > width then
            badgeX = 0
            rows = rows + 1
        end
        badgeX = badgeX + badgeWidth + 4
    end
    local rowHeight = 16
    return rows * (rowHeight + 4), width
end
```
This makes Pass 1 and Pass 2 agree on the tag block height.

- [ ] **Step 8: Cache AttachmentSystem.linesForItem result (L10)**

Replace `Block_AttachmentSystem:shouldRender` (lines 813-819):
```lua
function Block_AttachmentSystem:shouldRender(item)
    if not (AttachmentSystem and AttachmentSystem.Tooltip and AttachmentSystem.Tooltip.linesForItem) then
        return false
    end
    local lines = AttachmentSystem.Tooltip.linesForItem(item)
    return lines and #lines > 0
end
```
with a version that caches per-item on the block table:
```lua
function Block_AttachmentSystem:shouldRender(item)
    if not (AttachmentSystem and AttachmentSystem.Tooltip and AttachmentSystem.Tooltip.linesForItem) then
        return false
    end
    local lines = AttachmentSystem.Tooltip.linesForItem(item)
    self._cachedLines = lines  -- reused by render()
    return lines and #lines > 0
end
```
Replace the first line of `Block_AttachmentSystem:render` (line 858):
```lua
    local lines = AttachmentSystem.Tooltip.linesForItem(item)
```
with:
```lua
    local lines = self._cachedLines
    if not lines and AttachmentSystem and AttachmentSystem.Tooltip and AttachmentSystem.Tooltip.linesForItem then
        lines = AttachmentSystem.Tooltip.linesForItem(item)
    end
```
This halves the Java-bridge calls per frame for items with attachments.

- [ ] **Step 9: Remove dead LegacyMod block + fix merged comment (L4, L8)**

Delete the entire `Block_LegacyMod` definition (lines 738-805, from `-- BLOCK 7: LEGACY MOD` through the closing `end` that runs into `-- BLOCK 7.5`). Also delete `Layout.createLegacyModBlock` (lines 742-744).

Then renumber the section comments for clarity. Replace these comment headers:
- `-- BLOCK 7.5: ATTACHMENT SYSTEM` → `-- BLOCK 7: ATTACHMENT SYSTEM`
- `-- BLOCK 8: FOOTER` → `-- BLOCK 8: FOOTER (unchanged)`

(The ClothingStats block sits between Footer and end-of-file; label it `-- BLOCK 9: CLOTHING STATS`.)

- [ ] **Step 10: Make Block_ClothingStats crash-proof (L1)**

Replace `Block_ClothingStats:render` (the version at lines ~1110-1144) so every item call is safe. Replace the whole function body:
```lua
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

    local insulation = safeCall(item, "getInsulation") or 0
    if insulation > 0 then
        addStat("Insulation", string.format("%.2f", insulation), 0.4, 0.8, 0.4)
    end
    local wind = safeCall(item, "getWindresistance") or 0
    if wind > 0 then
        addStat("Wind Resist", string.format("%.2f", wind), 0.4, 0.8, 0.8)
    end
    local water = safeCall(item, "getWaterResistance") or 0
    if water > 0 then
        addStat("Water Resist", string.format("%.2f", water), 0.3, 0.5, 0.9)
    end
    local runMod = safeCall(item, "getRunSpeedModifier")
    if runMod and runMod ~= 1.0 then
        local mod = (runMod - 1.0) * 100
        addStat("Run Speed", string.format("%+.0f%%", mod), mod < 0 and 0.8 or 0.4, mod < 0 and 0.3 or 0.8, 0.3)
    end
    local combatMod = safeCall(item, "getCombatSpeedModifier")
    if combatMod and combatMod ~= 1.0 then
        local mod = (combatMod - 1.0) * 100
        addStat("Combat Speed", string.format("%+.0f%%", mod), mod < 0 and 0.8 or 0.4, mod < 0 and 0.3 or 0.8, 0.3)
    end

    return currentY - y
end
```
Also update `Block_ClothingStats:measure` to use safe calls:
```lua
function Block_ClothingStats:measure(item, width)
    local h = 0
    if (safeCall(item, "getInsulation") or 0) > 0 then h = h + 18 end
    if (safeCall(item, "getWindresistance") or 0) > 0 then h = h + 18 end
    if (safeCall(item, "getWaterResistance") or 0) > 0 then h = h + 18 end
    local runMod = safeCall(item, "getRunSpeedModifier")
    if runMod and runMod ~= 1.0 then h = h + 18 end
    local combatMod = safeCall(item, "getCombatSpeedModifier")
    if combatMod and combatMod ~= 1.0 then h = h + 18 end
    if h > 0 then h = h + 8 end -- padding
    return h, width
end
```

- [ ] **Step 11: Static verification**

Run:
```
findstr /n "Block_LegacyMod\|createLegacyModBlock" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Layout.lua
```
Expected: **no output**.

Run:
```
findstr /n "end--" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Layout.lua
```
Expected: **no output** (the merged comment is fixed).

Run to confirm no naked direct calls remain in block render functions (this is a heuristic — `item:` should now almost always be wrapped):
```
findstr /n "item:getName\|item:getTex\|item:getVisual\|item:getFluidContainer\|item:getInsulation" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Layout.lua
```
Expected: **no output** (all replaced with `safeCall(item, ...)`).

Run:
```
findstr /n "for i = 1, 4 do" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Layout.lua
```
Expected: **no output** (socket loop now iterates `activeParts`).

Run:
```
findstr /n "return 24, width" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Layout.lua
```
Expected: **no output** in Block_Tags (measure now returns computed height).

- [ ] **Step 12: Commit**

```bash
git add 42/media/lua/client/ZFlexTooltip/ZFlexTooltip_Layout.lua
git commit -m "fix(layout): restore crash-proof invariant and measure/render consistency

- L1: wrap all direct Java calls in Header/HeroStat/ProgressBars/FluidFlask/Sockets/ClothingStats with safeCall + safeGet
- L2: Header measure() now returns 54 to match render()
- L5: Sockets render all attachments, not just 4; grid wraps
- L6: Tags measure() pre-computes wrapped row height
- L7: ProgressBars guards maxCond<=0 once
- L8: fix merged end-- comment
- L9: renumber block comments (drop 7.5)
- L10: cache AttachmentSystem.linesForItem across shouldRender/render
- L12: Sockets measure/render height aligned to 36"
```

---

### Task 3: Harden Capabilities.lua (Cap2, Cap3, Cap1)

**Files:**
- Modify: `42/media/lua/client/ZFlexTooltip/ZFlexTooltip_Capabilities.lua`

- [ ] **Step 1: Add a safe container-weight helper (Cap2)**

Replace `Caps.getWeight` (lines 109-116):
```lua
function Caps.getWeight(item)
    if Caps.hasMethod(item, "getActualWeight") then
        return item:getActualWeight()
    elseif Caps.hasMethod(item, "getWeight") then
        return item:getWeight()
    end
    return 0
end
```
with a version that adds container contents when available:
```lua
function Caps.getWeight(item)
    if not item then return 0 end
    local baseWeight
    if Caps.hasMethod(item, "getActualWeight") then
        baseWeight = item:getActualWeight()
    elseif Caps.hasMethod(item, "getWeight") then
        baseWeight = item:getWeight()
    else
        return 0
    end

    -- For containers, include the weight of contained items (B42).
    if Caps.hasMethod(item, "getInventory") then
        local inv = item:getInventory()
        if inv then
            if Caps.hasMethod(inv, "getWeightThen") then
                baseWeight = baseWeight + (inv:getWeightThen() or 0)
            elseif Caps.hasMethod(inv, "getCapacityWeight") then
                baseWeight = baseWeight + (inv:getCapacityWeight() or 0)
            end
        end
    end
    return baseWeight
end
```

- [ ] **Step 2: Broaden supportsSockets to check getter presence (Cap3)**

Replace `Caps.supportsSockets` (lines 86-88):
```lua
function Caps.supportsSockets(item)
    return Caps.hasMethod(item, "isRanged") and item:isRanged()
end
```
with:
```lua
function Caps.supportsSockets(item)
    if not item then return false end
    -- Ranged weapons always have attachment slots.
    if Caps.hasMethod(item, "isRanged") and item:isRanged() then return true end
    -- Some B42 mods add attachment slots to melee items: treat any known
    -- attachment getter as evidence of socket support.
    local socketGetters = { "getScope", "getSling", "getCanon", "getClip", "getRecoilpad", "getStock" }
    for _, m in ipairs(socketGetters) do
        if Caps.hasMethod(item, m) then return true end
    end
    return false
end
```
Note: `Block_Sockets:shouldRender` (Task 2 Step 7) already gates on `instanceof(item, "HandWeapon")` plus an active-part probe, so broadening here does not make melee weapons suddenly render a sockets block — it only makes the capability answer honest.

- [ ] **Step 3: Optional debug log in iterateTags (Cap1)**

Replace `Caps.iterateTags` (lines 58-83):
```lua
function Caps.iterateTags(tags, callback)
    if not tags then return end

    -- List/ArrayList
    if Caps.hasMethod(tags, "size") and Caps.hasMethod(tags, "get") then
        local ok = pcall(function()
            for i = 0, tags:size() - 1 do
                callback(tags:get(i))
            end
        end)
        if ok then return end
    end

    -- Set/HashSet
    if Caps.hasMethod(tags, "iterator") then
        local ok = pcall(function()
            local it = tags:iterator()
            while it and Caps.hasMethod(it, "hasNext") and it:hasNext() do
                if Caps.hasMethod(it, "next") then
                    callback(it:next())
                end
            end
        end)
        if ok then return end
    end
end
```
with a version that surfaces total failure when debug is on:
```lua
function Caps.iterateTags(tags, callback)
    if not tags then return end
    local consumed = false

    -- List/ArrayList
    if Caps.hasMethod(tags, "size") and Caps.hasMethod(tags, "get") then
        local ok = pcall(function()
            for i = 0, tags:size() - 1 do
                callback(tags:get(i))
            end
        end)
        if ok then consumed = true end
    end

    -- Set/HashSet
    if not consumed and Caps.hasMethod(tags, "iterator") then
        local ok = pcall(function()
            local it = tags:iterator()
            while it and Caps.hasMethod(it, "hasNext") and it:hasNext() do
                if Caps.hasMethod(it, "next") then
                    callback(it:next())
                end
            end
        end)
        if ok then consumed = true end
    end

    if not consumed and ZFlexTooltip and ZFlexTooltip.Debug then
        print("ZFlexTooltip: iterateTags could not iterate a tags object of type " .. type(tags))
    end
end
```

- [ ] **Step 4: Static verification**

Run:
```
findstr /n "isRanged() and item:isRanged" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Capabilities.lua
```
Expected: **no output**.

Run:
```
findstr /n "getInventory\|getWeightThen\|getCapacityWeight" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Capabilities.lua
```
Expected: 3+ matches (the new container-weight code).

- [ ] **Step 5: Commit**

```bash
git add 42/media/lua/client/ZFlexTooltip/ZFlexTooltip_Capabilities.lua
git commit -m "fix(capabilities): container weight, broader socket support, debug tag log

- Cap2: getWeight now adds contained-item weight for containers
- Cap3: supportsSockets honors attachment getters, not only isRanged
- Cap1: iterateTags logs when both iteration strategies fail (debug only)"
```

---

### Task 4: Expand Config tokens (Conf1, Conf2, Conf3)

**Files:**
- Modify: `42/media/lua/client/ZFlexTooltip/ZFlexTooltip_Config.lua`

- [ ] **Step 1: Add Animation block (Conf2)**

After the `Config.Grid` block (after line 13), insert:
```lua
-- 1b. Animation tokens
Config.Animation = {
    SlidePixels = 20,    -- vertical slide-in distance in px
    DurationMs = 120.0,  -- slide+fade duration in milliseconds
}
```

- [ ] **Step 2: Add BlockSizes block (Conf3)**

After the Animation block just added, insert:
```lua
-- 1c. Per-block sizing tokens (replaces magic numbers scattered in Layout)
Config.BlockSizes = {
    Header       = 54,
    HeroStat     = 36,
    ProgressBar  = 22,
    FluidFlask   = 30,
    SocketSlot   = 28,
    SocketGap    = 4,
    TagRow       = 16,
    TagGap       = 4,
    ClothingRow  = 18,
}
```

- [ ] **Step 3: Extend Font mapping (Conf1)**

Replace the `Config.Fonts` block (lines 44-49):
```lua
Config.Fonts = {
    Title = "Medium",
    Text = "Small",
    Value = "Code",
    Hero = "Large"
}
```
with an extended set. Note: `getUIFont` in Layout only resolves Medium/Large/Code/Small today; add the extra mappings here for documentation and so a future `getUIFont` extension has the data:
```lua
Config.Fonts = {
    Title    = "Medium",
    Text     = "Small",
    Value    = "Code",
    Hero     = "Large",
    -- Extended (currently resolved to Small by getUIFont's fallback,
    -- listed here so Layout can be extended without touching Config):
    Tiny     = "NewSmall",
    Subtitle = "Breadcrumb",
    Heading  = "Heading",
}
```

- [ ] **Step 4: Wire Config.BlockSizes into Layout (optional hardening)**

This is a stretch goal. The bare minimum to satisfy Conf3 is to *define* the tokens (steps 1-2). To actually consume them, in Task 2's block bodies replace magic numbers like `54`, `22`, `30`, `28` with `Config.BlockSizes.Header` etc. Since Task 2 is large already, **leave the consumption as a follow-up note** and only define tokens here. Add a comment at the top of the BlockSizes block:
```lua
-- NOTE: Layout currently uses literal numbers; migrate incrementally.
-- Defining the tokens here first lets new code reference them immediately.
```

- [ ] **Step 5: Static verification**

Run:
```
findstr /n "Config.Animation\|Config.BlockSizes" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Config.lua
```
Expected: 2 matches (the two new blocks).

- [ ] **Step 6: Commit**

```bash
git add 42/media/lua/client/ZFlexTooltip/ZFlexTooltip_Config.lua
git commit -m "feat(config): add Animation and BlockSizes tokens, extend Font map

- Conf2: Config.Animation { SlidePixels, DurationMs }
- Conf3: Config.BlockSizes { Header, HeroStat, ... }
- Conf1: Config.Fonts extended with Tiny/Subtitle/Heading"
```

---

### Task 5: Sync documentation with code + delete ghost file

**Files:**
- Modify: `README.md`
- Modify: `PROJECT.md`
- Modify: `mod.info`
- Modify: `42/mod.info`
- Modify: `workshop.txt`
- Delete: `ClothingStats.lua` (repo root)

- [ ] **Step 1: Delete the ghost ClothingStats.lua (L3)**

```bash
git rm "ClothingStats.lua"
```

- [ ] **Step 2: Fix the README "For Modders" API (Doc)**

The README claims `ZFlexTooltip.Layout.pipeline` exists and `table.insert(...pipeline, 1, block)` works. It does not — the pipeline is built locally inside `buildLayoutState` via `box:addBlock(...)`. Two options:

**Option A (preferred): make the code match the doc.** Add a real extension point. In `ZFlexTooltip_Main.lua` this is out of scope for Task 5 (Main is Task 1's file). So instead **Option B: fix the doc to match the code.**

In `README.md`, replace the "For Modders" code block (lines 26-55) with a correct example that hooks `Events.OnGameBoot` and injects via the VBox factory pattern. Since `buildLayoutState` builds a fresh VBox each frame and there is no global registry, the honest path for a third-party block is to **wrap one of the existing creators**. Replace the block with:

```markdown
## 📚 For Modders
ZFlexTooltip rebuilds its VBox layout every frame inside `buildLayoutState`. To inject a custom block, wrap one of the `Layout.create*Block` factories on game boot:

```lua
local ZFT_Layout = ZFlexTooltip.Layout

-- Save the original footer factory
local origFooter = ZFT_Layout.createFooterBlock

local MyCustomBlock = {}
MyCustomBlock.__index = MyCustomBlock

function MyCustomBlock:shouldRender(item)
    return item and item:hasModData() and item:getModData().MyCoolStat ~= nil
end

function MyCustomBlock:measure(item, width)
    return 24, width
end

function MyCustomBlock:render(item, x, y, width, renderQueue)
    table.insert(renderQueue, {
        type = "text",
        text = "My Cool Stat: " .. tostring(item:getModData().MyCoolStat),
        x = x, y = y,
        color = { r = 1, g = 0.5, b = 0, a = 1 },
        font = UIFont.Small
    })
    return 18
end

-- Replace the footer factory so our block is appended after it
Events.OnGameBoot.Add(function()
    ZFT_Layout.createFooterBlock = function()
        origFooter()  -- keep the original footer
        return setmetatable({}, MyCustomBlock)
    end
end)
```
```

Also remove the false compatibility claims that have no test backing. In `README.md`, soften lines 12-18 from definitive ("✅ Flawless integration") to aspirational:

Replace:
```markdown
* **Mod Compatibility Matrix:** Flawless integration with UI-altering giants without needing hardcoded patches:
  * ✅ **Inventory Tetris:** Preserves grid anchors and properly defers to Tetris layout logic.
  * ✅ **Equipment UI:** Respects Drag & Drop events without leaving ghost tooltips.
  * ✅ **Wookiee Gamepad Support:** Controller `joyfocus` navigation natively supported.
  * ✅ **Arsenal / Brita / KI5:** Gracefully handles complex custom item data.
```
with:
```markdown
* **Mod Compatibility:** Designed to coexist with UI-altering mods without hardcoded patches:
  * **Inventory Tetris / Equipment UI:** Hides the tooltip during active drag-and-drop and context menus.
  * **Gamepad:** Controller `joyfocus` navigation is respected.
  * **Arsenal / Brita / KI5 / AttachmentSystem:** Item data is read via reflection, so custom modded items do not crash the tooltip.
  * **TooltipLib:** Coexists via a deferred-mode trick (see source comments).
```

And remove the "100% Crash-Proof" hard claim. Replace line 11:
```markdown
* **100% Crash-Proof Architecture (Capabilities API):** ZFlexTooltip safely negotiates with items using Reflection (`Caps.hasMethod`) instead of blindly throwing `pcall()`, completely eliminating Java exceptions and Kahlua GC spikes.
```
with:
```markdown
* **Crash-Resistant (Capabilities API):** ZFlexTooltip reads item data via reflection (`Caps.hasMethod` / `safeInvoke`) rather than direct method calls, so modded items that are missing expected methods degrade gracefully instead of throwing Java exceptions.
```

- [ ] **Step 3: Fix PROJECT.md paths and stale R2 content (Doc)**

In `PROJECT.md`:

Replace line 13:
```markdown
- Lua files: `ZFlexTooltip/media/lua/client/ZFlexTooltip/*.lua`
```
with:
```markdown
- Lua files: `42/media/lua/client/ZFlexTooltip/*.lua`
```

Replace line 14:
```markdown
- Tests: `ZFlexTooltip/media/lua/client/ZFlexTooltip/tests` or `tests/` at workspace root.
```
with:
```markdown
- Tests: No automated test suite yet. Manual smoke-test checklist lives in `docs/superpowers/plans/2026-06-15-zflextooltip-bugfixes.md` (Task 6).
```

Replace the `### Module Structure` bullets (lines 7-9) — the Phantom Canvas description is stale. Replace:
```markdown
### Module Structure
- `ZFlexTooltip_Config.lua`: Defines configuration tokens, spatial grid system (padding: 16px, gap: 12px), colors (RGBA(14,16,20,0.96) background, RGBA(255,255,255,0.08) border), state colors, and font overrides.
- `ZFlexTooltip_Layout.lua`: A performance-optimized VBox layout engine that parses item data (durability, fluid containers, weapon sockets, craft tags) and builds a flat `RenderQueue` with pre-computed relative coordinate offsets.
- `ZFlexTooltip_Main.lua`: Core controller that hooks into `ISToolTipInv.render`, intercepts vanilla drawing calls via a "Phantom Canvas" interception mechanism, filters out vanilla texts, and populates the render queue.
```
with:
```markdown
### Module Structure
- `ZFlexTooltip_Config.lua`: Design tokens — grid (Padding=16, BlockGap=12), colors (BgBase rgba(0.05,0.06,0.08,0.95), BorderBase rgba(0.4,0.5,0.7,0.25)), state colors, rarity colors, font tokens, animation tokens, block-size tokens.
- `ZFlexTooltip_Capabilities.lua`: Reflection layer. `hasMethod` / `safeInvoke` / `safeGet` read item data without throwing on missing methods. Capability helpers for condition, fluid, tags, sockets, weight.
- `ZFlexTooltip_Layout.lua`: Two-pass VBox engine. Pass 1 `measure()` computes width+height; Pass 2 `generateQueue()` emits a flat `RenderQueue` of draw commands. Nine block types (Header, HeroStat, ProgressBars, FluidFlask, Sockets, Tags, AttachmentSystem, Footer, ClothingStats).
- `ZFlexTooltip_Main.lua`: Controller. Hooks `ISToolTipInv.render/prerender`, `ISCraftRecipeTooltip.prerender`, `ISToolTip.render`. Manages animation state, position clamping, drag/context-menu suppression, and the TooltipLib deferred-mode interop.
```

Replace the Milestones table (lines 17-23) — mark M1 done and the rest superseded by this bugfix plan:
```markdown
## Milestones
| # | Name | Status | Note |
|---|------|--------|------|
| M1 | Codebase Audit & Test Harness | DONE | Audit complete; no Lua toolchain locally, static verification used. |
| M2-M5 | Original Phantom-Canvas plan | SUPERSEDED | R2 (Phantom Canvas) is retired. Bugfix plan: `docs/superpowers/plans/2026-06-15-zflextooltip-bugfixes.md`. |
```

- [ ] **Step 4: Add version numbers to mod.info files (Doc)**

In `42/mod.info`, add a `version` line. Replace:
```
name=Z-Flex Tooltip
poster=../poster.png
id=ZFlexTooltip
description=Modern tactical PDA style tooltip overhaul for Build 42.19.
pzversion=42
versionMin=42.0.0
```
with:
```
name=Z-Flex Tooltip
poster=../poster.png
id=ZFlexTooltip
description=Modern tactical PDA style tooltip overhaul for Build 42.19.
pzversion=42
versionMin=42.0.0
version=1.1.0
```

In the repo-root `mod.info`, add `version` and `pzversion` so it is self-describing even if loaded without the `42/` subdir. Replace:
```
name=Z-Flex Tooltip
id=ZFlexTooltip
description=Modern tactical PDA style tooltip overhaul for Build 42.19.
poster=poster.png
```
with:
```
name=Z-Flex Tooltip
id=ZFlexTooltip
description=Modern tactical PDA style tooltip overhaul for Build 42.19.
poster=poster.png
pzversion=42
versionMin=42.0.0
version=1.1.0
```

- [ ] **Step 5: Bump workshop.txt version (Doc)**

In `workshop.txt`, replace:
```
version=1
```
with:
```
version=1.1.0
```

- [ ] **Step 6: Static verification**

Run:
```
findstr /n "pipeline" README.md
```
Expected: **no output** (the fake API is gone).

Run:
```
findstr /n "Phantom" PROJECT.md
```
Expected: at most one match (the SUPERSEDED note mentioning the retired name).

Run:
```
findstr /n "version=" mod.info 42\mod.info workshop.txt
```
Expected: `version=1.1.0` appears in all three.

Run:
```
dir ClothingStats.lua
```
Expected: file not found (deleted).

- [ ] **Step 7: Commit**

```bash
git add README.md PROJECT.md mod.info 42/mod.info workshop.txt
git commit -m "docs: sync README/PROJECT/mod.info with actual code; delete ghost ClothingStats.lua

- Doc: replace nonexistent .pipeline API example with factory-wrap pattern
- Doc: soften untested compatibility claims; soften '100% crash-proof'
- Doc: PROJECT.md module structure matches current layered architecture
- Doc: PROJECT.md paths point at 42/media/lua/...
- Doc: retire Phantom Canvas milestones (R2 dropped)
- Doc: add version=1.1.0 to both mod.info files and workshop.txt
- L3: delete root ClothingStats.lua (duplicate, syntactically broken)"
```

---

### Task 6: Final verification & in-game smoke test

**Files:** none (verification only)

- [ ] **Step 1: Static sanity — no bare per-frame prints**

```
findstr /n "print(" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Main.lua
```
Acceptable output: 5 lines max — the 3 install-time prints (boot, not per-frame) + up to 2 debug-gated ones if `Debug` reads were left as plain `print`. All per-frame prints must be inside `if ZFlexTooltip.Debug then`.

- [ ] **Step 2: Static sanity — no direct Java item calls in Layout block bodies**

```
findstr /n "item:getName item:getTex item:getVisual item:getFluidContainer item:getInsulation item:getMinDamage item:getMaxDamage item:getScratchDefense item:getBodyLocation" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Layout.lua
```
Expected: **no output**.

- [ ] **Step 3: Static sanity — measure/render heights agree**

Open `ZFlexTooltip_Layout.lua` and confirm each block's `measure` return equals its `render` return:
- Header: measure 54, render 54 ✓
- ProgressBars: measure 22, render 22 ✓
- FluidFlask: measure 36, render 30 — **verify**; if mismatch remains, set both to 30.
- Sockets: measure 36, render dynamic — acceptable since render returns computed height and measure returns max single-row height.
- Tags: measure computed, render computed — must use identical wrap math.

- [ ] **Step 4: Static sanity — dead code gone**

```
findstr /n "CapturedDrawCalls Block_LegacyMod createLegacyModBlock" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Main.lua 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Layout.lua
```
Expected: **no output**.

- [ ] **Step 5: Commit history check**

```
git log --oneline -10
```
Expected: 5 commits, one per Task 1-5, each with a clear scope prefix (fix(main), fix(layout), fix(capabilities), feat(config), docs).

- [ ] **Step 6: In-game smoke test (manual)**

Since no Lua interpreter is available locally, the mod must be loaded in Project Zomboid B42.19. Copy the `ZFlexTooltip` folder into `<User>/Zomboid/mods/` and enable it. Verify each scenario:

| # | Scenario | Expected |
|---|----------|----------|
| 1 | Hover any inventory item | Tactical PDA tooltip slides in, no console errors |
| 2 | Hover a Clothing item (jacket) | Insulation/Wind/Water/Run/Combat rows appear |
| 3 | Hover a ranged weapon with 6 attachments | All 6 attachment icons render in wrapping grid |
| 4 | Hover a fluid container (water bottle) | Liquid name + colored fill bar |
| 5 | Hold SHIFT over a weapon | "(VS equipped: +X.X)" diff in green/red |
| 6 | Open context menu while hovering | Tooltip hides, no ghost |
| 7 | Drag an item (Tetris/Equipment UI if installed) | Tooltip hides during drag |
| 8 | Hover a modded item missing expected methods | No red-box Lua error; block simply omits missing data |
| 9 | Watch FPS counter for 30s of hovering | No noticeable drop vs unmodded |
| 10 | Check `<User>/Zomboid/console.txt` size after 5 min of play | Not growing by MB/min (prints are gated) |

If any scenario fails, file a follow-up against the corresponding Task.

- [ ] **Step 7: Mark plan complete**

Once all scenarios pass, commit the plan doc itself as done (optional):
```bash
git add docs/superpowers/plans/2026-06-15-zflextooltip-bugfixes.md
git commit -m "docs(plan): ZFlexTooltip bugfix plan (executed)"
```

---

## Execution Order & Parallelism

Tasks 1-5 touch **disjoint files** and can run in parallel:

```
Task 1 (Main.lua)        ─┐
Task 2 (Layout.lua)       ├─→  all parallel, no merge conflicts
Task 3 (Capabilities.lua) │
Task 4 (Config.lua)      ─┘
Task 5 (docs + delete)    ──→  parallel, but its README code example references the factory pattern (Layout) — cosmetic only, no code dependency
Task 6 (verify)           ──→  strictly AFTER Tasks 1-5
```

**Dependency caveat:** Task 1 Step 3 reads `Config.Animation` which Task 4 Step 1 defines. Both use fallback values (`or 20`, `or 120.0`), so order does not matter — but if running sequentially, do Task 4 before Task 1 for clean first-run behavior.

**Recommended parallel batch:** dispatch Tasks 1, 2, 3, 4 simultaneously (4 subagents), then Task 5, then Task 6.
