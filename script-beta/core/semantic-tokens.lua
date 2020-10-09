local files          = require 'files'
local guide          = require 'parser.guide'
local await          = require 'await'
local TokenTypes     = require 'define.TokenTypes'
local TokenModifiers = require 'define.TokenModifiers'
local vm             = require 'vm'

local Care = {}
Care['setglobal'] = function (source, results)
    results[#results+1] = {
        start      = source.start,
        finish     = source.finish,
        type       = TokenTypes.namespace,
        modifieres = TokenModifiers.deprecated,
    }
end
Care['getglobal'] = function (source, results)
    local lib = vm.getLibrary(source, 'simple')
    if lib then
        if source[1] == '_G' then
            return
        else
            results[#results+1] =  {
                start      = source.start,
                finish     = source.finish,
                type       = TokenTypes.namespace,
                modifieres = TokenModifiers.static,
            }
        end
    else
        results[#results+1] =  {
            start      = source.start,
            finish     = source.finish,
            type       = TokenTypes.namespace,
            modifieres = TokenModifiers.deprecated,
        }
    end
end
Care['tablefield'] = function (source, results)
    local field = source.field
    results[#results+1] = {
        start      = field.start,
        finish     = field.finish,
        type       = TokenTypes.property,
        modifieres = TokenModifiers.declaration,
    }
end
Care['getlocal'] = function (source, results)
    local loc = source.node
    -- 1. 函数的参数
    if loc.parent and loc.parent.type == 'funcargs' then
        results[#results+1] = {
            start      = source.start,
            finish     = source.finish,
            type       = TokenTypes.parameter,
            modifieres = TokenModifiers.declaration,
        }
        return
    end
    -- 2. 特殊变量
    if source[1] == '_ENV'
    or source[1] == 'self' then
        return
    end
    -- 3. 不是函数的局部变量
    local hasFunc
    for _, def in ipairs(vm.getDefs(loc, 'simple')) do
        if def.type == 'function'
        or (def.type == 'library' and def.value.type == 'function') then
            hasFunc = true
            break
        end
    end
    if hasFunc then
        results[#results+1] = {
            start      = source.start,
            finish     = source.finish,
            type       = TokenTypes.interface,
            modifieres = TokenModifiers.declaration,
        }
        return
    end
    -- 4. 其他
    results[#results+1] = {
        start      = source.start,
        finish     = source.finish,
        type       = TokenTypes.variable,
    }
end
Care['setlocal'] = Care['getlocal']

local function buildTokens(results, lines)
    local tokens = {}
    local lastLine = 0
    local lastStartChar = 0
    for i, source in ipairs(results) do
        local row, col = guide.positionOf(lines, source.start)
        local line = row - 1
        local startChar = col - 1
        local deltaLine = line - lastLine
        local deltaStartChar
        if deltaLine == 0 then
            deltaStartChar = startChar - lastStartChar
        else
            deltaStartChar = startChar
        end
        lastLine = line
        lastStartChar = startChar
        -- see https://microsoft.github.io/language-server-protocol/specifications/specification-3-16/#textDocument_semanticTokens
        local len = i * 5 - 5
        tokens[len + 1] = deltaLine
        tokens[len + 2] = deltaStartChar
        tokens[len + 3] = source.finish - source.start + 1 -- length
        tokens[len + 4] = source.type
        tokens[len + 5] = source.modifieres or 0
    end
    return tokens
end

return function (uri, start, finish)
    local ast   = files.getAst(uri)
    local lines = files.getLines(uri)
    if not ast then
        return nil
    end

    local results = {}
    local count = 0
    guide.eachSourceBetween(ast.ast, start, finish, function (source)
        local method = Care[source.type]
        if not method then
            return
        end
        method(source, results)
        count = count + 1
        if count % 100 == 0 then
            await.delay()
        end
    end)

    table.sort(results, function (a, b)
        return a.start < b.start
    end)

    local tokens = buildTokens(results, lines)

    return tokens
end
