local utils = {}

utils.table_numbers = function(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

---Scan a path string and split it into multiple paths.
---@param s_path string
---@return string[]
utils.scan_paths = function(s_path)
    local paths = {}
    local path = ''
    local escape_char = '\\'

    local i = 1
    while i <= #s_path do
        local char = s_path:sub(i, i)
        if char == escape_char then
            -- Escape next character
            if i < #s_path then
                i = i + 1
                path = path .. s_path:sub(i, i)
            end
        elseif char:match('%s') then
            -- Unescaped whitespace: split here.
            if path ~= '' then
                table.insert(paths, path)
            end
            path = ''
            i = i + s_path:sub(i, -1):match('^%s+()') - 2
        else
            path = path .. char
        end

        i = i + 1
    end

    if #path > 0 then
        table.insert(paths, path)
    end

    return paths
end

return utils
