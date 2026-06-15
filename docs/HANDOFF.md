# ZFlexTooltip — Agent Handoff Document

> **Цель документа:** дать другому AI-агенту полный контекст о состоянии мода ZFlexTooltip после багфикс-итерации, чтобы можно было продолжить работу без повторного аудита. Читать сверху вниз.

**Последнее обновление:** 2026-06-16
**Ветка/репо:** `main` @ `https://github.com/OftenMind2/UI-Toolbar-overhaul-PZ`
**HEAD commit:** `708fd95`
**Версия мода:** 1.1.0

---

## 1. Что это за мод

ZFlexTooltip — мод для **Project Zomboid Build 42.19**, заменяющий ванильные тултипы (`ISToolTipInv`, `ISCraftRecipeTooltip`, `ISToolTip`) кастомным UI в эстетике «Tactical PDA» (тёмный обсидиан, голубая рамка, slide-in анимация).

**Архитектура — 4 слоя:**

```
Config.lua        → design tokens (grid, colors, fonts, animation, blocksizes)
Capabilities.lua  → reflection layer (hasMethod / safeInvoke — crash-safe доступ к Java API)
Layout.lua        → two-pass VBox engine + 9 block types (measure → generateQueue → RenderQueue)
Main.lua          → controller (hooks, animation, position clamp, TooltipLib interop)
```

**Пути (важно — нестандартная структура):**
- Код: `42/media/lua/client/ZFlexTooltip/*.lua`
- Папка `42/` — изоляция под B42 (`mod.info` там же с `pzversion=42`)
- Корневой `mod.info` — самостоятельный (без `42/`)
- `poster.png` — баннер (~858 КБ)
- Git-репозиторий изолирован внутри `ZFlexTooltip/` (не путать с родительским `noble-hypatia/.git`)

---

## 2. Что было сделано в этой итерации

Полный цикл: **глубокий code review → план фиксов → параллельное ревью плана (3 агента) → inline исполнение всех 5 задач → verify + push.**

### 2.1 Процесс (по фазам)
1. **Code review** — найден 21 дефект (C1-C6, L1-L12, Cap1-3, Conf1-3, Doc).
2. **План** (`docs/superpowers/plans/2026-06-15-zflextooltip-bugfixes.md`) — 6 задач по доменам с disjoint-файлами.
3. **Self-review** — добавлен C3 reentrancy-фикс (Step 5b), выровнена нумерация.
4. **Parallel-agent review** (3 Explore-агента: Lua-correctness, API/Docs, Coverage/Refs) — пойманы 4 BLOCKER'а и ~12 warning'ов, все интегрированы в план.
5. **Исполнение** — 5 задач по коду, исполнены inline, закоммичены отдельно.

### 2.2 История коммитов (хронологически, снизу вверх)
```
6ce887b  Initial commit: ZFlexTooltip mod (baseline, 12 файлов)
9580b78  docs(plan): add ZFlexTooltip bugfix plan with self-review fixes
5823c27  plan(review): integrate parallel-agent review (4 blockers + 12 warnings)
abb3d36  feat(config): add Animation, BlockSizes tokens; extend Font map       ← Task 4
1bd4a1a  fix(main): gate per-frame prints, fix w/h shadowing, drop dead legacy  ← Task 1
452ccba  fix(layout): restore crash-proof invariant and measure/render consis.  ← Task 2
90b4025  fix(capabilities): container weight, broader socket support, debug log ← Task 3
708fd95  docs: sync README/mod.info with code; delete ghost file                ← Task 5
```

---

## 3. Полный список исправленных дефектов

### Main.lua (Task 1, commit `1bd4a1a`)
| ID | Что было | Что стало |
|----|----------|-----------|
| **C1** | `print()` в prerender/render каждый кадр (~180 строк/сек в лог) | Обёрнуты в `if ZFlexTooltip.Debug then` (по умолчанию `false`) |
| **C2** | `local w = self:getWidth()` / `local h = self:getHeight()` shadowing затирал вычисленный layout | Удалены; `w,h` из `buildLayoutState` течёт в draw-циклы |
| **C3** | `ISContextMenu.instance` swap не был reentrancy-safe (мог затереть чужой menu) | Snapshot reference-identity; restore только если instance не сменился |
| **C4** | `ISContextMenu.instance.visibleCheck` читался без защиты | `type(...) ~= "nil"` проверка |
| **C5** | Дублированные ветки `joyfocus` и `not followMouse` | Объединены в `if self.joyfocus or not self.followMouse` |
| **C6** | Магические числа анимации (20, 120.0) захардкожены | Читаются из `Config.Animation` с fallback'ами |
| **L4** | `CapturedDrawCalls` init + `createLegacyModBlock` в pipeline (мёртвый код) | Удалены |

### Layout.lua (Task 2, commit `452ccba`)
| ID | Что было | Что стало |
|----|----------|-----------|
| **L1** | 30+ прямых `item:getXxx()` вызовов в обход Caps (нарушение crash-proof инварианта) | Все обёрнуты в `safeCall`; итого 55 `safeCall`-сайтов |
| **L2** | Header measure=48, render=54 (расхождение 6px) | measure=54 |
| **L5** | Sockets рисовал только 4 из 6 attachment'ов (`for i=1,4`) | Рендерит все; grid wraps в пределах width; `shouldRender` gates на реальное наличие |
| **L6** | Tags measure=24, render=dynamic (расхождение) + measure/render считали разный текст | Общие хелперы `buildTagList` + `computeTagHeight`; единый текст и wrap-math |
| **L7** | `math.max(1, maxCond)` дублировался | Один guard `if maxCond <= 0 then maxCond = 1 end` |
| **L8** | Слитый комментарий `end-- BLOCK 7.5` | Разделён, блоки перенумерованы 1-9 |
| **L9** | Дублирующиеся/дробные номера блоков (два "7", "7.5") | Последовательная нумерация BLOCK 1-9 |
| **L10** | `AttachmentSystem.Tooltip.linesForItem` вызывался 2× за кадр | Кэш `self._cachedLines` в `shouldRender`, переиспользуется в `render` |
| **L11** | HeroStat measure=48, render=36 (найден в review, не было в inventory) | Добавлен в inventory; measure=36 |
| **L12** | Sockets measure=44, render=32 | measure=36 (single-row case) |
| **Conf1** | `getUIFont` не резолвил NewSmall/Breadcrumb/Heading | Расширен (все 6 UIFont-токенов) |

### Capabilities.lua (Task 3, commit `90b4025`)
| ID | Что было | Что стало |
|----|----------|-----------|
| **Cap1** | `iterateTags` молча возвращался при полном провале | Логирует в debug-режиме (`ZFlexTooltip.Debug`) |
| **Cap2** | `getWeight` не учитывал содержимое контейнеров | Добавляет `getInventory():getCapacityWeight()` |
| **Cap3** | `supportsSockets` узко проверял только `isRanged()` | Проверяет наличие attachment-getter'ов (для melee с модами) |

> ⚠️ **Важно про Cap2:** предыдущий draft плана использовал `getWeightThen()` — этого метода **НЕ существует** в PZ B42 API. Поймано в review. Правильный путь: `item:getInventory():getCapacityWeight()` (javadoc: `zombie/inventory/types/InventoryContainer.html#getInventory()`, `zombie/inventory/ItemContainer.html#getCapacityWeight()`).

### Config.lua (Task 4, commit `abb3d36`)
| ID | Что было | Что стало |
|----|----------|-----------|
| **Conf1** | Font map: только Title/Text/Value/Hero | + Tiny/Subtitle/Heading |
| **Conf2** | Нет animation tokens | `Config.Animation { SlidePixels=20, DurationMs=120.0 }` |
| **Conf3** | Нет block-size tokens | `Config.BlockSizes { Header=54, HeroStat=36, ... }` (определены, потребление в Layout — follow-up) |

### Docs (Task 5, commit `708fd95`)
- **README**: несуществующий `.pipeline` API → composite-block pattern (сохраняет footer); смягчены "100% crash-proof" и compat-claims.
- **PROJECT.md** *(в родительском `noble-hypatia/`, вне репо)*: пути `42/media/lua/...`; module structure под текущую архитектуру; milestones M2-M5 = SUPERSEDED.
- **mod.info** (оба): `version=1.1.0`, `pzversion=42`, `versionMin=42.0.0`.
- **workshop.txt**: `version=1.1.0`, смягчены claims.
- **Удалён** корневой `ClothingStats.lua` (дубликат, синтаксически битый: `""Clothing""`).

---

## 4. Текущее состояние кода (quick map)

```
42/media/lua/client/ZFlexTooltip/
├── ZFlexTooltip_Config.lua        (~85 строк)  — токены, НЕ трогать без правки Layout
├── ZFlexTooltip_Capabilities.lua  (~145 строк) — reflection layer, стабилен
├── ZFlexTooltip_Layout.lua        (~1150 строк) — VBox + 9 блоков, самый большой
└── ZFlexTooltip_Main.lua          (~360 строк)  — controller, хуки
```

### 9 блоков Layout (порядок в pipeline, `buildLayoutState` в Main.lua):
1. Header — иконка + имя (цвет по редкости) + категория + вес + разделитель
2. HeroStat — крупная цифра (Damage/Defense/Capacity) + Shift-Compare
3. ProgressBars — полоса прочности с state-цветом
4. FluidFlask — B42 жидкости (имя, объём, цветная полоса)
5. Sockets — все attachment'ы оружия (wrapping grid)
6. Tags — badge-капсулы (kind: good/bad/earned/neutral)
7. AttachmentSystem — интеграция с `AttachmentSystem.Tooltip.linesForItem()`
8. Footer — подсказка "Hold [SHIFT] to compare"
9. ClothingStats — Insulation/Wind/Water/RunSpeed/CombatSpeed

### Контракт блока (каждый должен реализовать):
```lua
Block:shouldRender(item) -> bool
Block:measure(item, width) -> (height, preferredWidth)   -- Pass 1
Block:render(item, x, y, width, renderQueue) -> height    -- Pass 2, добавляет draw-команды
```
**КРИТИЧНО:** `measure` и `render` должны возвращать **одинаковую высоту** (L2/L6/L11/L12 учат этому). Несовпадение → нахлёст блоков.

---

## 5. Известные ограничения и follow-up

### Не сделано (намеренно, отмечено в плане)
1. **Conf3 consumption** — `Config.BlockSizes` определены, но Layout всё ещё использует литералы (54, 22, 30, 28...). Миграция — отдельная задача. План: Task 4 Step 4.
2. **Нет automated test suite** — Lua-интерпретатора локально нет. Проверка через `findstr` + in-game smoke-test (Task 6 в плане, 10 сценариев).
3. **`worn:getItem(loc)` в `getEquippedItem`** — PZ `WornItems` не имеет метода `getItem(bodyLocation)`. Вызов обёрнут в `safeCall`, так что не крашит, но Shift-Compare для clothing **может не работать**. Нужно проверить реальный API (`getWornItems()` возвращает `BodyLocation`-маппинг; возможно нужен `isWearingItem(item)` или итерация). Это **предсуществующий баг**, не внесённый фиксом.

### Что НЕ покрыто (out of scope текущей итерации)
- R2 "Phantom Canvas" (перехват `getTextManager().DrawString`) — **retired**, не реализуется.
- Smoke-test сценарии для: Cap2 (заполненный контейнер), L6 (много-tag item), C3 reentrancy (menu во время originalRender) — отмечены как gap в review, но требуют in-game проверки.
- Vehicle mechanic panels / animals tooltips — README ранее заявлял, но хуки не реализованы (только inventory/crafting/generic).

### Риски
- **`Config.BlockSizes` не используется** — если кто-то добавит новый блок, он должен либо использовать токены, либо явно литерал. Несоответствие пройдёт незамеченным (нет статической проверки).
- **TooltipLib deferred-mode trick** (`ISContextMenu.instance.visibleCheck = true` вокруг `originalRender`) — хрупкий. Если TooltipLib или другой mod изменит поведение чтения `visibleCheck`, трюк сломается. Реализован reentrancy-safe (C3), но не future-proof.

---

## 6. Как проверять (без Lua locally)

Все verification-команды — Windows `findstr`. Примеры (отрицательные = ожидается пусто):

```cmd
:: per-frame prints должны быть gated
findstr /n "print(" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Main.lua

:: naked Java-вызовы в Layout должны отсутствовать (эвристика)
findstr /n "item:getName item:getTex item:getVisual item:getFluidContainer item:getInsulation" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Layout.lua

:: мёртвый код должен отсутствовать
findstr /n "CapturedDrawCalls Block_LegacyMod createLegacyModBlock" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Main.lua 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Layout.lua

:: фиктивный API должен отсутствовать
findstr /n /c:"getWeightThen" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Capabilities.lua

:: merged comment должен отсутствовать
findstr /n /c:"end--" 42\media\lua\client\ZFlexTooltip\ZFlexTooltip_Layout.lua
```

> ⚠️ **Windows findstr gotcha:** `\|` — НЕ оператор OR (это literal backslash-pipe). Multi-word строки требуют `/c:"..."`. Пробелы внутри строки = разделитель OR. Для regex-опасных символов (`()`) добавляйте `/l` (literal mode).

**In-game smoke-test (10 сценариев)** — см. план Task 6 Step 6. Кратко: hover item → PDA slide-in; clothing → insulation rows; weapon с 6 attachment'ами → все 6 иконок; fluid → цветная полоса; SHIFT → +/- diff; context menu → tooltip прячется; drag → прячется; modded item без методов → no red-box; FPS stable; console.txt не растёт.

---

## 7. Ключевые файлы и артефакты

| Файл | Назначение |
|------|------------|
| `docs/superpowers/plans/2026-06-15-zflextooltip-bugfixes.md` | Полный план фиксов (1521 строка), пройдший self-review + parallel-agent review. Содержит "Review history" в шапке. |
| `docs/HANDOFF.md` | Этот документ. |
| `README.md` | Пользовательская документация + composite-block pattern для моддеров. |
| `.gitignore` / `.gitattributes` | LF-нормализация для Lua, binary для PNG. |
| `PROJECT.md` *(в `noble-hypatia/`, вне репо)* | Контекстный документ оркестратора ZCode. |

---

## 8. Если продолжаешь работу — начни здесь

1. **Прочитай план** `docs/superpowers/plans/2026-06-15-zflextooltip-bugfixes.md` (особенно Task 6 — smoke-test, и раздел "Review history" в шапке).
2. **Проверь git log** — убедись, что HEAD = `708fd95` и remote синхронизирован (`git status`).
3. **Priorities для следующей итерации** (по убыванию):
   - (a) In-game smoke-test (нужен PZ B42.19) — подтвердить, что 10 сценариев из Task 6 проходят. Это единственный способ поймать runtime-регрессии.
   - (b) Починить `getEquippedItem` для clothing (см. §5 "Не сделано" п.3) — Shift-Compare для брони сейчас может не работать.
   - (c) Смигрировать Layout на `Config.BlockSizes` (Conf3 consumption).
   - (d) Добавить real extension API в Main.lua (вместо composite-block workaround в README) — `ZFlexTooltip.Layout.registerBlock(block, position)`.
4. **Не реинтродуциру** `getWeightThen` (фикция), `safeGet` helper (ломает varargs), `CapturedDrawCalls`/`Block_LegacyMod` (мёртвый код), `.pipeline` API (не существует).
5. **Стиль кода:** `safeCall(obj, "method", args...)` для любого Java-вызова; measure/render высоты обязаны совпадать; комментарии блоков `-- BLOCK N: NAME`.

---

*Документ сгенерирован после завершения багфикс-итерации. Все коммиты на `origin/main`.*
