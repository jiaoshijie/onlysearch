local _M = {}
local fmt = string.format

--- @param msg string
_M.echo_err_msg = function(msg)
    vim.api.nvim_echo({ { fmt("OnlySearch: %s", msg) } }, true, { err = true })
end

_M.echo_info_msg = function(msg)
    vim.api.nvim_echo({ { fmt("OnlySearch: %s", msg) } }, true, { err = false })
end


--- @return number? major
--- @return number? minor
_M.get_cmd_version = function(cmd, ver_flag, ver_fmt)
    if vim.fn.executable(cmd) ~= 1 then
        return nil, nil
    end
    local obj = vim.system({ cmd, ver_flag }, {
        text = true,
        clear_env = true,
    }):wait()
    if obj.code ~= 0 or obj.signal ~= 0
        or #obj.stderr > 0 then
        return nil, nil
    end
    local major, minor = obj.stdout:match(ver_fmt)

    if not major or not minor then
        return nil, nil
    end

    return tonumber(major), tonumber(minor)
end

--- @param winid ?number
--- @return boolean
_M.winid_in_tab = function(winid)
    if winid == nil then return false end
    return vim.fn.tabpagenr() == vim.fn.win_id2tabwin(winid)[1]
end

--- @param bufnr number
_M.buf_delete = function(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    -- Suppress the buffer deleted message for those with &report<2
    local start_report = vim.o.report
    vim.o.report = 2

    vim.api.nvim_buf_delete(bufnr, { force = true })

    vim.o.report = start_report
end

--- @param win_id number
--- @param force boolean see :h nvim_win_close
_M.win_delete = function(win_id, force)
    if not win_id or not vim.api.nvim_win_is_valid(win_id) then
        return
    end

    local save_ei = vim.o.eventignore
    vim.o.eventignore = "all"
    vim.api.nvim_win_close(win_id, force)
    vim.o.eventignore = save_ei
end

--- Scan a path string and split it into multiple paths.
--- @param s_path string
--- @return string[]
_M.scan_paths = function(s_path)
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
--- @return string?, string?
_M.split_last_chunk = function(str)
    local pos = string.find(str, '\n', -1, true)
    if pos then
        -- The two string returned don't contain the last newline character
        return str:sub(1, pos - 1), #str:sub(pos + 1) > 0 and str:sub(pos + 1) or nil
    end

    return nil, str
end

return _M
