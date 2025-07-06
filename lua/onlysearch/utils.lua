local utils = {}

--- Get the table length
--- @param t table
--- @return number the table length
utils.table_numbers = function(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

--- Scan a path string and split it into multiple paths.
--- @param s_path string
--- @return string[]
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

--- @param str string
--- @param substr string
--- @return number?
utils.str_last_pos = function(str, substr)
  local pos = vim.fn.strridx(str, substr)
  if pos == -1 then
    return nil
  end

  return pos + 1  -- make it 1-based index
end


--- @param str string
--- @return string?, string?
utils.split_last_chunk = function(str)
    local pos  = utils.str_last_pos(str, '\n')
    if pos then
        -- The two string returned don't contain the last newline character
        return str:sub(1, pos - 1), #str:sub(pos + 1) > 0 and str:sub(pos + 1) or nil
    end

    return nil, str
end

--- @param msg string
utils.echo_err_msg = function(msg)
    vim.api.nvim_echo({ { msg } }, true, { err = true })
end

--- @param msg string
utils.echo_info_msg = function(msg)
    vim.api.nvim_echo({ { msg } }, true, { err = false })
end

return utils
