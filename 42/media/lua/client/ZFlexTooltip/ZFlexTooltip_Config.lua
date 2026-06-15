ZFlexTooltip = ZFlexTooltip or {}
ZFlexTooltip.Config = ZFlexTooltip.Config or {}

local Config = ZFlexTooltip.Config

-- 1. Spatial Grid System
Config.Grid = {
    MinWidth = 320,
    MaxWidth = 480,
    Padding = 16,
    BlockGap = 12,
    LineGap = 4
}

-- 1b. Animation tokens
Config.Animation = {
    SlidePixels = 20,    -- vertical slide-in distance in px
    DurationMs = 120.0,  -- slide+fade duration in milliseconds
}

-- 1c. Per-block sizing tokens (replaces magic numbers scattered in Layout)
-- NOTE: Layout currently uses literal numbers; migrate incrementally.
-- Defining the tokens here first lets new code reference them immediately.
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

-- 2. Semantic Color Palette (0.0 to 1.0 floats for PZ API)
Config.Colors = {
    BgBase = { r = 0.05, g = 0.06, b = 0.08, a = 0.95 }, -- Deep obsidian/navy
    BorderBase = { r = 0.4, g = 0.5, b = 0.7, a = 0.25 }, -- Sleek blue-tinted border
    
    TextHero = { r = 0.98, g = 0.98, b = 0.98, a = 1.0 },
    TextLabel = { r = 0.55, g = 0.60, b = 0.65, a = 1.0 },
    TextMuted = { r = 0.35, g = 0.40, b = 0.45, a = 1.0 },
    
    -- Durability & State Indicators
    State = {
        Perfect = { r = 0.18, g = 0.80, b = 0.44 },  -- Bright Mint Green
        Warning = { r = 0.95, g = 0.61, b = 0.07 },  -- Vivid Amber
        Critical = { r = 0.90, g = 0.29, b = 0.23 }   -- Vibrant Crimson
    }
}

-- 3. Rarity Colors (Sleek dark-themed overrides)
Config.RarityColors = {
    Worn = { r = 0.65, g = 0.45, b = 0.35, a = 1.0 },        -- Rust brown
    Common = { r = 0.85, g = 0.85, b = 0.85, a = 1.0 },      -- Light gray
    Good = { r = 0.18, g = 0.80, b = 0.44, a = 1.0 },        -- Neon Green
    Rare = { r = 0.20, g = 0.60, b = 1.00, a = 1.0 },        -- Bright Blue
    Exceptional = { r = 0.68, g = 0.28, b = 0.92, a = 1.0 },  -- Epic Purple
    Unique = { r = 1.00, g = 0.75, b = 0.00, a = 1.0 },       -- Gold/Legendary
    Risky = { r = 0.90, g = 0.40, b = 0.10, a = 1.0 }         -- Amber
}

-- 4. Font tokens mapped to PZ fonts (UIFont is a global enum in PZ)
Config.Fonts = {
    Title    = "Medium",  -- maps to UIFont.Medium
    Text     = "Small",   -- maps to UIFont.Small
    Value    = "Code",    -- maps to UIFont.Code
    Hero     = "Large",   -- maps to UIFont.Large
    -- Extended (resolved by getUIFont in Layout; listed here so Layout can be
    -- extended without touching Config):
    Tiny     = "NewSmall",
    Subtitle = "Breadcrumb",
    Heading  = "Heading",
}

-- Fallback categories if getCategory() is not clear
Config.CategoryNames = {
    weapon_melee = "Melee Weapon",
    weapon_firearm = "Firearm",
    container_bag = "Container",
    clothing_outer = "Outerwear",
    clothing_inner = "Clothing",
    clothing_shoes = "Footwear",
    clothing_gloves = "Gloves",
    clothing_head = "Headwear",
    tool = "Tool",
    food = "Food",
    junk = "Misc Item",
    generic = "Item"
}
