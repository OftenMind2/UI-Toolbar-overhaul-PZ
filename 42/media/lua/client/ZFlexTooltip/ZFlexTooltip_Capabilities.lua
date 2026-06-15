ZFlexTooltip = ZFlexTooltip or {}
ZFlexTooltip.Capabilities = ZFlexTooltip.Capabilities or {}

local Caps = ZFlexTooltip.Capabilities

-- Core reflection helper
function Caps.hasMethod(obj, name)
    return obj ~= nil and type(obj[name]) == "function"
end

function Caps.safeInvoke(obj, method, ...)
    if Caps.hasMethod(obj, method) then
        return obj[method](obj, ...)
    end
    return nil
end

-- 1. Capability: Condition (Durability)
function Caps.supportsCondition(item)
    return Caps.hasMethod(item, "getCondition") and Caps.hasMethod(item, "getConditionMax")
end

function Caps.getConditionRatio(item)
    if not Caps.supportsCondition(item) then return 0, 0, 0 end
    local cond = item:getCondition() or 0
    local max = item:getConditionMax() or 1
    if max <= 0 then max = 1 end
    return cond, max, cond / max
end

-- 2. Capability: Fluid Container (B42)
function Caps.supportsFluid(item)
    return Caps.hasMethod(item, "getFluidContainer")
end

function Caps.getFluidData(item)
    if not Caps.supportsFluid(item) then return nil end
    local container = item:getFluidContainer()
    if not container then return nil end
    
    local isEmpty = Caps.safeInvoke(container, "isEmpty")
    if isEmpty == nil then isEmpty = true end
    
    return {
        container = container,
        isEmpty = isEmpty,
        amount = Caps.safeInvoke(container, "getFluidAmount") or 0,
        capacity = Caps.safeInvoke(container, "getCapacity") or 1,
        primaryFluid = Caps.safeInvoke(container, "getPrimaryFluid")
    }
end

-- 3. Capability: Tags (List/Set iteration)
function Caps.supportsTags(item)
    return Caps.hasMethod(item, "getTags") or Caps.hasMethod(item, "getModData")
end

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

-- 4. Capability: Weapon Sockets (Attachments)
function Caps.supportsSockets(item)
    return Caps.hasMethod(item, "isRanged") and item:isRanged()
end

function Caps.getSockets(item)
    local parts = {}
    if not Caps.supportsSockets(item) then return parts end
    
    local methods = { "getScope", "getSling", "getCanon", "getClip", "getRecoilpad", "getStock" }
    for _, method in ipairs(methods) do
        local part = Caps.safeInvoke(item, method)
        if part then
            table.insert(parts, part)
        end
    end
    return parts
end

-- 5. Capability: Weight
function Caps.supportsWeight(item)
    return Caps.hasMethod(item, "getActualWeight") or Caps.hasMethod(item, "getWeight")
end

function Caps.getWeight(item)
    if Caps.hasMethod(item, "getActualWeight") then
        return item:getActualWeight()
    elseif Caps.hasMethod(item, "getWeight") then
        return item:getWeight()
    end
    return 0
end
