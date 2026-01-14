local ui = require("onlysearch.ui")
local kit = require("onlysearch.kit")
local cfg = require("onlysearch.config")
local query_hist = require("onlysearch.query_hist")

local _M = { limit = {} }

--- @param winid number
--- @return boolean
local is_valid_target_winid = function(winid)
    if winid ~= 0 and vim.api.nvim_win_is_valid(winid) and kit.winid_in_tab(winid)
        and not vim.api.nvim_get_option_value('winfixbuf', { win = winid }) then
        return true
    end
    return false
end

--- @param winid number the window id that the user is in when open the onlysearch window
--- @return number the window id that the bufnr will be placed at
local chose_window = function(winid)
    -- 1. first try to use the last window to open the file
    local target_winid = vim.fn.win_getid(vim.fn.winnr('#'))
    if is_valid_target_winid(target_winid) then
        return target_winid
    end
    -- 2. try to use the `winid` provided by the caller to open the file
    if is_valid_target_winid(winid) then
        return winid
    end
    -- 3. if the first window is not the onlysearch window,
    --    use the first window(window number is 1) in the current tabpage to open the file
    -- 4. else try to use other window number to open the file
    if vim.fn.winnr() ~= 1 then
        winid =  vim.fn.win_getid(1)
    else
        target_winid = vim.fn.win_getid(2)
        if target_winid ~= 0 then
            winid = target_winid
        end
    end
    if is_valid_target_winid(winid) then
        return winid
    end

    -- 5. finally, creating a new window open the file
    --    the onlysearch window is the only window in this tabpage
    vim.cmd("silent keepalt vertical split")

    return vim.fn.win_getid()
end

--- @param winid number
--- @param abs_path string
--- @param lnum number
local open_file = function(winid, abs_path, lnum)
    vim.fn.win_gotoid(chose_window(winid))
    vim.cmd('edit ' .. vim.fn.fnameescape(abs_path))
    if lnum then
        pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
    else
        pcall(vim.api.nvim_win_set_cursor, 0, { 1, 0 })
    end
end

--- @param cwd string
--- @param filename string
--- @return string
local gen_abs_path = function(cwd, filename)
    local abs_path = nil
    if string.sub(filename, 1, 1) == '/' then
        abs_path = '' .. filename  -- deepcopy the string
    else
        cwd = cwd and cwd or vim.fn.getcwd()
        filename = string.sub(filename, 1, 2) == './' and string.sub(filename, 3) or filename

        abs_path = vim.fn.expand(cwd) .. '/' .. filename
    end

    return abs_path
end

--- @param lnum ?number
--- @return boolean
_M.is_editable = function(lnum)
    if lnum then
        return lnum <= cfg.ui_cfg.header_lines
    end
    return vim.fn.line('.') <= cfg.ui_cfg.header_lines
end

--- @param rt_ctx table runtime_ctx
_M.search = function(rt_ctx, lazy)
    local lines = vim.api.nvim_buf_get_lines(rt_ctx.bufnr, 0, cfg.ui_cfg.header_lines, false)
    if #lines[1] < 3 then return end

    local query = {
        text = lines[1],
        paths = vim.fn.trim(lines[2]),
        flags = vim.fn.trim(lines[3]),
        filters = vim.fn.trim(lines[4]),
    }

    if lazy and rt_ctx.query and query.text == rt_ctx.query.text
        and query.paths == rt_ctx.query.paths
        and query.flags == rt_ctx.query.flags
        and query.filters == rt_ctx.query.filters then
        return
    end

    -- Assign an new table object to rt_ctx.query
    rt_ctx.query = query
    rt_ctx.engine_search_fn(rt_ctx)
end

--- open a result item and put cursor on the matched line
--- @param rt_ctx table runtime_ctx
_M.select_entry = function(rt_ctx)
    if rt_ctx.lookup_table then
        local clnum = vim.fn.line('.')
        local entry = rt_ctx.lookup_table[clnum]
        if entry then
            local abs_path = gen_abs_path(rt_ctx.engine_ctx.cwd, entry.filename)
            open_file(rt_ctx.target_winid, abs_path, entry.lnum)
        end
    end
end

--- prevent user enter insert mode in result area
_M.limit.on_insert_enter = function()
    if not _M.is_editable() then
        local key = vim.api.nvim_replace_termcodes('<esc>', true, false, true)
        vim.api.nvim_feedkeys(key, 'n', false)
        kit.echo_info_msg("Making changes in results is not allowed")
    end
end

--- Do search when leave insert mode
--- @param rt_ctx table runtime_ctx
_M.on_insert_leave = function(rt_ctx)
    if _M.is_editable() then
        _M.search(rt_ctx, true)
    end
end

--- prevent user do change text operation in result area or change the window layout.
--- e.g. d D x X r R
--- @param key string
_M.limit.modify_text = function(key)
    if _M.is_editable() then
        vim.api.nvim_feedkeys(key, 'n', true)
    else
        kit.echo_info_msg("Making changes in results is not allowed")
    end
end

--- limit user do paste operation. `p` `P`
--- @param key string
_M.limit.paste = function(key)
    if _M.is_editable() then
        local clip = vim.api.nvim_get_option_value("clipboard", { scope = "global" })
        local reg = clip == "" and '"' or clip == "unnamedplus" and "+" or "*"
        local reg_content = vim.fn.getreg(reg)
        if vim.fn.match(reg_content, '\r\\|\n') == -1 then
            vim.api.nvim_feedkeys(key, 'n', true)
        else
            kit.echo_info_msg("Paste multiple lines are not allowed in onlysearch buffer")
        end
    else
        kit.echo_info_msg("Making changes in results is not allowed")
    end
end

--- limit user paste from system clipboard
--- @param rt_ctx table runtime_ctx
_M.limit.sys_clipboard_paste = function(rt_ctx)
    return function(lines, phase)
        if rt_ctx.bufnr and rt_ctx.bufnr == vim.fn.bufnr() then
            -- 1. if not editable canceling this operation
            if not _M.is_editable() then
                kit.echo_info_msg("Making changes in results is not allowed")
                return false
            end
            -- 2. if the content contain multiple lines canceling this operation
            if (phase ~= -1 or #lines > 1) then
                kit.echo_info_msg("Paste multiple lines are not allowed in onlysearch buffer")
                return false
            end
        end
        return rt_ctx.orignal_vim_dot_paste(lines, phase)
    end
end

--- @param rt_ctx table runtime_ctx
--- @param lnum number
--- @return string
_M.foldexpr = function(rt_ctx, lnum)
    assert(rt_ctx ~= nil)

    if _M.is_editable(lnum) or rt_ctx.lookup_table == nil then
        return '0'
    end

    local entry = rt_ctx.lookup_table[lnum]

    if entry == nil or entry.lnum == nil then
        return '0'
    end

    local next_entry = rt_ctx.lookup_table[lnum + 1]
    if next_entry == nil then
        return '<1'
    end

    local prev_entry = rt_ctx.lookup_table[lnum - 1]
    if prev_entry and prev_entry.lnum == nil then
        return '>1'
    end

    return '1'
end

--- @param rt_ctx table runtime_ctx
--- @param lnum number
local toggle_single_line = function(rt_ctx, lnum)
    assert(rt_ctx ~= nil)

    if _M.is_editable(lnum) then
        return
    end
    local is_sel = not rt_ctx.selected_items[lnum]
    ui.toggle_sel_line(rt_ctx, lnum - 1, is_sel)
    rt_ctx.selected_items[lnum] = is_sel and lnum or nil
end

--- @param rt_ctx table runtime_ctx
--- @param is_visual boolean
_M.toggle_lines = function(rt_ctx, is_visual)
    assert(rt_ctx ~= nil)
    if rt_ctx.lookup_table == nil then return end

    local slnum, elnum
    if is_visual then
        -- NOTE: quit visual mode, otherwise the < and > marks will be 0
        local esc = vim.api.nvim_replace_termcodes('<esc>', true, false, true)
        vim.api.nvim_feedkeys(esc, 'x', false)

        slnum = unpack(vim.api.nvim_buf_get_mark(0, '<'))
        elnum = unpack(vim.api.nvim_buf_get_mark(0, '>'))
    else
        slnum = vim.fn.line('.')
        elnum = slnum + vim.api.nvim_get_vvar('count1') - 1
    end
    local entry = nil

    if slnum == elnum then
        entry = rt_ctx.lookup_table[slnum]
        if entry then
            if entry.lnum then
                toggle_single_line(rt_ctx, slnum)
            else
                local lnum = slnum + 1
                while true do
                    entry = rt_ctx.lookup_table[lnum]
                    if not entry then
                        break
                    end

                    toggle_single_line(rt_ctx, lnum)
                    lnum = lnum + 1
                end
            end
        end
        return
    end

    for lnum = slnum, elnum, 1 do
        entry = rt_ctx.lookup_table[lnum]
        if entry and entry.lnum then
            toggle_single_line(rt_ctx, lnum)
        end
    end
end

--- @param rt_ctx table runtime_ctx
_M.clear_all_selected_items = function(rt_ctx)
    assert(rt_ctx ~= nil)

    if not rt_ctx.selected_items then return end

    rt_ctx.selected_items = {}
    local ns = rt_ctx.env_weak_ref.ns
    vim.api.nvim_buf_clear_namespace(rt_ctx.bufnr, ns.select_id, 0, -1)
end

--- @param rt_ctx table runtime_ctx
_M.send2qf = function(rt_ctx)
    assert(rt_ctx ~= nil)
    if not rt_ctx.lookup_table then
        return
    end

    local list = {}
    if type(rt_ctx.selected_items) == "table" and next(rt_ctx.selected_items) ~= nil then
        for lnum, _ in pairs(rt_ctx.selected_items) do
            local entry = rt_ctx.lookup_table[lnum]
            if entry and entry.lnum then
                table.insert(list, entry)
            end
        end
    else
        for _, entry in pairs(rt_ctx.lookup_table) do
            if entry and entry.lnum then
                table.insert(list, entry)
            end
        end
    end

    local list_len = #list;
    if list_len > 0 then
        vim.fn.setqflist(list, 'r')
        vim.fn.setqflist({}, 'r', {  -- set qflist title which will be shown in statusline
            title = "OnlySearch Result: " .. list_len .. " items",
        })
        vim.cmd('copen')
    end
end

--- @param rt_ctx table runtime_ctx
_M.recover_os_view = function(rt_ctx)
    assert(rt_ctx ~= nil)
    if rt_ctx.bufnr == nil then
        return
    end

    ui.render_query(rt_ctx, rt_ctx.query or {})

    if rt_ctx.query then
        -- NOTE: does not need to check the query.text, becasue the runtime only save valid search qeury
        rt_ctx.engine_search_fn(rt_ctx)
    end
end

-- NOTE: using omnifunc(C-x C-o) instead
-- --- @param rt_ctx table runtime_ctx
-- _M.omnifunc = function(rt_ctx)
--     local _ = rt_ctx
--
--     local engine = cfg.common.engine
--     local engine_cfg = cfg.engines_cfg[engine]
--
--     if not engine_cfg or not engine_cfg.complete or #engine_cfg.complete == 0 then
--         return
--     end
--
--     local cursor = vim.api.nvim_win_get_cursor(0)
--     if cursor[1] ~= cfg.ui_cfg.header.extra_flags.lnum + 1 then
--         kit.echo_info_msg("Only complete flags in line number 3")
--         return
--     end
--
--     local cursor_col = cursor[2] + 1  -- convert 0-based to 1-based column
--     local line = vim.api.nvim_get_current_line()
--     local line_to_cursor = line:sub(1, cursor_col)
--     local start_boundary = vim.fn.match(line_to_cursor, '\\k*$') + 1  -- `+1` convert to 1-based index
--     local prefix = line:sub(start_boundary, cursor_col)
--
--     local items = vim.tbl_filter(function(item)
--         return item.word and vim.startswith(item.word, prefix)
--     end, engine_cfg.complete)
--
--     vim.fn.complete(start_boundary, items)
-- end

--- @param rt_ctx table runtime_ctx
_M.query_hist_open = function(rt_ctx)
    query_hist.open(rt_ctx)
end

--- @param rt_ctx table runtime_ctx
_M.query_hist_add = function(rt_ctx)
    query_hist.add(rt_ctx)
end

--- @param rt_ctx table runtime_ctx
_M.query_hist_close = function(rt_ctx)
    query_hist.close(rt_ctx)
end

--- @param rt_ctx table runtime_ctx
_M.query_hist_win_switch = function(rt_ctx)
    query_hist.win_switch(rt_ctx)
end

return _M
