local kit = require('onlysearch.kit')
local _M = {}

local parse_grep_output = function(data)
    local b, e = string.find(data, '\0')
    if b == nil then return nil end

    local p = string.sub(data, 1, b - 1)
    local l, c = string.match(string.sub(data, e + 1), "(%d+):(.*)")
    return p, l, c
end

local parse_subm = function(data)
    local subm = {}
    local p, c = 0, 1

    while true do
        local b1, e1 = string.find(data, '\27[0m', p + 1, true)
        if b1 == nil then break end
        local b2, e2 = string.find(data, '\27[m', e1 + 1, true)
        if b2 == nil then break end  -- Must be impossible

        table.insert(subm, { s = b1 - c, e = b2 - c - 4 })

        --- @diagnostic disable-next-line: cast-local-type
        p = e2
        c = c + 7
    end

    return #subm == 0 and nil or subm
end

-- NOTE: GNU grep --help/--version will never output a ASCII NUL char
-- 'main.c\012:abcdhjkl'
_M.parse_output = function(data)
    local p, l, c = parse_grep_output(data)

    if p ~= nil then
        -- `-C number` option, just return nil
        -- 'main.c\012-abcdhjkl'
        if l == nil then return nil end
        return {
            p = p,
            l = tonumber(l),
            --- @diagnostic disable-next-line: param-type-mismatch
            c = string.gsub(c, "\27%[0-m", ""),
            subm = parse_subm(c),
        }
    end

    -- p == nil
    -- `-C number` option, just return nil
    if data == "--" then return nil end

    -- raw data
    return data
end

_M.parse_filters = function(args, filters)
    if filters and #filters > 0 then
        filters = kit.scan_paths(filters)
        for _, filter in ipairs(filters) do
            if string.sub(filter, 1, 1) ~= '!' then
                table.insert(args, '--include=' .. filter)
            else
                filter = string.sub(filter, 2)  -- remove '!'
                if string.sub(filter, -1) == '/' then
                    table.insert(args, '--exclude-dir=' .. filter)
                else
                    table.insert(args, '--exclude=' .. filter)
                end
            end
        end
    end
end

return _M
