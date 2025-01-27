local ui = require("onlysearch.ui")
local action = {}

--- @param winid number the window id that the user is in when open the onlysearch window
--- @return number the window id that the bufnr will be placed at
local chose_window = function(winid)
    -- 1. first try to use the last window to open the file
    local lwinid = vim.fn.win_getid()
    local target_winid = vim.fn.win_getid(vim.fn.winnr('#'))
    if target_winid ~= 0 and target_winid ~= lwinid then
        return target_winid
    end
    -- 2. try to use the `winid` provided by the caller to open the file
    if winid and vim.fn.win_id2win(winid) ~= 0 then
        return winid
    end
    -- 3. if the first window is not the onlysearch window,
    --    use the first window(window number is 1) in the current tabpage to open the file
    -- 4. else try to use other window number to open the file
    target_winid = vim.fn.win_getid(1)
    if vim.fn.winnr() ~= 1 then
        return vim.fn.win_getid(1)
    else
        target_winid = vim.fn.win_getid(2)
        if target_winid ~= 0 then
            return target_winid
        end
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
    vim.cmd('edit ' .. abs_path)
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

    return vim.fn.fnameescape(abs_path)
end

--- @param coll Onlysearch
--- @param lnum number | nil
--- @return boolean
action.is_editable = function(coll, lnum)
    if lnum then
        return lnum <= coll.ui_lines_number
    end
    return vim.fn.line('.') <= coll.ui_lines_number
end

--- @param coll Onlysearch
action.search = function(coll)
    if not coll.finder then
        vim.api.nvim_err_writeln("ERROR: Onlysearch Finder can't be found")
        return
    end

    local query = {}
    query.cwd = vim.fn.getcwd(coll.winid)
    local lines = vim.api.nvim_buf_get_lines(coll.bufnr, 0, coll.ui_lines_number, false)
    query.text = lines[1]
    query.paths = vim.fn.trim(lines[2])
    query.flags = vim.fn.trim(lines[3])
    query.filters = vim.fn.trim(lines[4])

    if #query.text > 2 then
        -- Save the last query, and only save the last query
        coll:backup_query(query)
        coll.finder:search(query)
    end
end

--- open a result item and put cursor on the matched line
--- @param coll Onlysearch
action.select_entry = function(coll)
    if coll.lookup_table then
        assert(coll.query ~= nil and coll.query.current ~= nil)
        local clnum = vim.fn.line('.')
        local entry = coll.lookup_table[clnum]
        if entry then
            local abs_path = gen_abs_path(coll.query.current.cwd, entry.filename)
            open_file(coll.target_winid, abs_path, entry.lnum)
        end
    end
end

--- prevent user enter insert mode in result area
--- @param coll Onlysearch
action.on_insert_enter = function(coll)
    if not action.is_editable(coll) then
        local key = vim.api.nvim_replace_termcodes('<esc>', true, false, true)
        vim.api.nvim_feedkeys(key, 'n', false)
        print("WARNING: You can't make changes in results.")
    end
end

--- Do search when leave insert mode
--- @param coll Onlysearch
action.on_insert_leave = function(coll)
    if action.is_editable(coll) then
        action.search(coll)
    end
end

--- prevent user do deletion operation. e.g. d D x X in result area
--- @param coll Onlysearch
--- @param key string
action.limit_delete = function(coll, key)
    if action.is_editable(coll) then
        vim.api.nvim_feedkeys(key, 'n', true)
    else
        print("WARNING: You can't make changes in results.")
    end
end

--- limit user do paste operation. `p` `P`
--- @param coll Onlysearch
--- @param key string
action.limit_paste = function(coll, key)
    if action.is_editable(coll) then
        local clip = vim.api.nvim_get_option_value("clipboard", { scope = "global" })
        local reg = clip == "" and '"' or clip == "unnamedplus" and "+" or "*"
        local reg_content = vim.fn.getreg(reg)
        if vim.fn.match(reg_content, '\r\\|\n') == -1 then
            vim.api.nvim_feedkeys(key, 'n', true)
        else
            print("WARNING: Paste multiple lines are not allowed in onlysearch buffer")
        end
    else
        print("WARNING: You can't make changes in results.")
    end
end

--- @param coll Onlysearch
--- @param lnum number
--- @return string
action.foldexpr = function(coll, lnum)
    assert(coll ~= nil)

    if action.is_editable(coll, lnum) or coll.lookup_table == nil then
        return '0'
    end

    local entry = coll.lookup_table[lnum]

    if entry == nil or entry.lnum == nil then
        return '0'
    end

    local next_entry = coll.lookup_table[lnum + 1]
    if next_entry == nil then
        return '<1'
    end

    local prev_entry = coll.lookup_table[lnum - 1]
    if prev_entry and prev_entry.lnum == nil then
        return '>1'
    end

    return '1'
end

--- @param coll Onlysearch
--- @param lnum number
local toggle_single_line = function(coll, lnum)
    assert(coll ~= nil)

    if action.is_editable(coll, lnum) then
        return
    end
    local is_sel = not coll.selected_items[lnum]
    ui:toggle_sel_line(coll.bufnr, lnum - 1, is_sel)
    coll.selected_items[lnum] = is_sel and lnum or nil
end

--- @param coll Onlysearch
--- @param is_visual boolean
action.toggle_lines = function(coll, is_visual)
    assert(coll ~= nil)
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
        entry = coll.lookup_table[slnum]
        if entry then
            if entry.lnum then
                toggle_single_line(coll, slnum)
            else
                local lnum = slnum + 1
                while true do
                    entry = coll.lookup_table[lnum]
                    if not entry then
                        break
                    end

                    toggle_single_line(coll, lnum)
                    lnum = lnum + 1
                end
            end
        end
        return
    end

    for lnum = slnum, elnum, 1 do
        entry = coll.lookup_table[lnum]
        if entry and entry.lnum then
            toggle_single_line(coll, lnum)
        end
    end
end

--- @param coll Onlysearch
action.clear_all_selected_items = function(coll)
    assert(coll ~= nil)

    if coll.selected_items then
        local lnums = {}
        -- NOTE: Maybe deleting while iterating is not a problem in lua, but i don't want do it
        for lnum, _ in pairs(coll.selected_items) do
            table.insert(lnums, lnum)
        end

        for _, lnum in ipairs(lnums) do
            toggle_single_line(coll, lnum)
        end
    end
end

--- @param coll Onlysearch
action.send2qf = function(coll)
    assert(coll ~= nil)
    if not coll.lookup_table then
        return
    end

    local list = {}
    if type(coll.selected_items) == "table" and next(coll.selected_items) ~= nil then
        for lnum, _ in pairs(coll.selected_items) do
            local entry = coll.lookup_table[lnum]
            if entry and entry.lnum then
                table.insert(list, entry)
            end
        end
    else
        for _, entry in pairs(coll.lookup_table) do
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

-- TODO: maybe using 'omnifunc' option instead of remap a keymap
--- @param coll Onlysearch
action.omnifunc = function(coll)
    assert(coll ~= nil)
    if not coll.finder or not coll.finder.config
        or not coll.finder.config.complete then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    if cursor[1] ~= ui.vt.header.extra_flags.lnum + 1 then
        print("WARNING: Only complete flags in line number 3")
        return
    end

    local cflags = coll.finder.config.complete
    local cursor_col = cursor[2] + 1  -- convert 0-based to 1-based column
    local line = vim.api.nvim_get_current_line()
    local line_to_cursor = line:sub(1, cursor_col)
    local start_boundary = vim.fn.match(line_to_cursor, '\\k*$') + 1  -- `+1` convert to 1-based index
    local prefix = line:sub(start_boundary, cursor_col)

    local items = vim.tbl_filter(function(item)
        return item.word and vim.startswith(item.word, prefix)
    end, cflags)

    vim.fn.complete(start_boundary, items)
end

--- @param coll Onlysearch
action.resume_last_query = function(coll)
    assert(coll ~= nil)
    local query = coll:resume_query()
    if not query then
        print("No pervious query available, do nothing")
        return
    end

    ui:resume_query(coll.bufnr, coll.config.engine, query)
    coll.finder:search(query)
end

return action
