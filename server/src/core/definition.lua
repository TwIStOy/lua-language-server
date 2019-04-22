local findSource = require 'core.find_source'
local Mode

local function parseValueSimily(callback, vm, source)
    local key = source[1]
    if not key then
        return nil
    end
    vm:eachSource(function (other)
        if other == source then
            goto CONTINUE
        end
        if      other[1] == key
            and not other:bindLocal()
            and other:bindValue()
            and other:action() == 'set'
            and source:bindValue() ~= other:bindValue()
        then
            callback(other)
        end
        :: CONTINUE ::
    end)
end

local function parseLocal(callback, vm, source)
    local loc = source:bindLocal()
    local locSource = loc:getSource()
    callback(locSource)
end

local function parseValueByValue(callback, vm, source, value, isGlobal)
    value:eachInfo(function (info, src)
        if info.type == 'set' or info.type == 'local' or info.type == 'return' then
            if Mode == 'definition' then
                if vm.uri == src:getUri() then
                    if isGlobal or source.id > src.id then
                        callback(src)
                    end
                elseif value.uri == src:getUri() then
                    callback(src)
                end
            elseif Mode == 'reference' then
                callback(src)
            end
        end
    end)
end

local function parseValue(callback, vm, source)
    local value = source:bindValue()
    local isGlobal
    if value then
        isGlobal = value:isGlobal()
        parseValueByValue(callback, vm, source, value, isGlobal)
        local emmy = value:getEmmy()
        if emmy and emmy.type == 'emmy.type' then
            local class = emmy:getClass()
            if class and class:getValue() then
                parseValueByValue(callback, vm, source, class:getValue(), isGlobal)
            end
        end
    end
    local parent = source:get 'parent'
    for _ = 1, 3 do
        if parent then
            local ok = parent:eachInfo(function (info, src)
                if Mode == 'definition' then
                    if info.type == 'set child' and info[1] == source[1] then
                        callback(src)
                        return true
                    end
                elseif Mode == 'reference' then
                    if (info.type == 'set child' or info.type == 'get child') and info[1] == source[1] then
                        callback(src)
                        return true
                    end
                end
            end)
            if ok then
                break
            end
            parent = parent:getMetaMethod('__index')
        end
    end
    return isGlobal
end

local function parseLabel(callback, vm, label)
    label:eachInfo(function (info, src)
        if Mode == 'definition' then
            if info.type == 'set' then
                callback(src)
            end
        elseif Mode == 'reference' then
            if info.type == 'set' or info.type == 'get' then
                callback(src)
            end
        end
    end)
end

local function jumpUri(callback, vm, source)
    local uri = source:get 'target uri'
    callback {
        start = 0,
        finish = 0,
        uri = uri
    }
end

local function parseClass(callback, vm, source)
    local className = source:get 'target class'
    vm.emmyMgr:eachClass(className, function (class)
        if class.type == 'emmy.class' then
            local src = class:getSource()
            callback(src)
        end
    end)
end

local function makeList(source)
    local list = {}
    local mark = {}
    return list, function (src)
        if source == src then
            return
        end
        if mark[src] then
            return
        end
        mark[src] = true
        local uri = src.uri
        if uri == '' then
            uri = nil
        end
        list[#list+1] = {
            src.start,
            src.finish,
            src.uri
        }
    end
end

return function (vm, pos, mode)
    local source = findSource(vm, pos)
    if not source then
        return nil
    end
    Mode = mode
    local list, callback = makeList(source)
    local isGlobal
    if source:bindLocal() then
        parseLocal(callback, vm, source)
    end
    if source:bindValue() then
        isGlobal = parseValue(callback, vm, source)
        --parseValueSimily(callback, vm, source)
    end
    if source:bindLabel() then
        parseLabel(callback, vm, source:bindLabel())
    end
    if source:get 'target uri' then
        jumpUri(callback, vm, source)
    end
    if source:get 'in index' then
        isGlobal = parseValue(callback, vm, source)
        --parseValueSimily(callback, vm, source)
    end
    if source:get 'target class' then
        parseClass(callback, vm, source)
    end
    return list, isGlobal
end
