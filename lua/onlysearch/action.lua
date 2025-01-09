local search = require("onlysearch.search")
local action = {}

---@return number window_id
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

local open_file = function(winid, abs_path, lnum)
    vim.fn.win_gotoid(chose_window(winid))
    vim.cmd('edit ' .. abs_path)
    if lnum then
        pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
    else
        pcall(vim.api.nvim_win_set_cursor, 0, { 1, 0 })
    end
end

local gen_abs_path = function(cwd, filename)
    local abs_path = nil
    if string.sub(filename, 1, 1) == '/' then
        abs_path = '' .. filename  -- deepcopy the string
    else
        cwd = cwd and cwd or vim.fn.getcwd()
        abs_path = vim.fn.expand(cwd) .. '/' .. filename
    end

    return vim.fn.fnameescape(abs_path)
end

action.is_editable = function(coll)
    return vim.fn.line('.') <= coll.ui_lines_number
end

action.search = function(coll)
    if not coll.finder then
        local finder_gen = search.setup(coll.config.engine)
        coll.finder = finder_gen:new(coll.config.engine_config, coll:handler())
    end
    coll.cwd = vim.fn.getcwd(coll.winid)

    local query = {}
    query.cwd = coll.cwd
    local lines = vim.api.nvim_buf_get_lines(coll.bufnr, 0, coll.ui_lines_number, false)
    query.text = lines[1]
    query.paths = vim.fn.trim(lines[2])
    query.flags = vim.fn.trim(lines[3])
    query.filters = vim.fn.trim(lines[4])

    if #query.text > 2 then
        coll.finder:search(query)
    end
end

action.select_entry = function(coll)
    if coll.lookup_table then
        local clnum = vim.fn.line('.')
        local entry = coll.lookup_table[clnum]
        if entry then
            local abs_path = gen_abs_path(coll.target_winid, entry.f)
            open_file(coll.target_winid, abs_path, entry.l)
        end
    end
end

action.on_insert_enter = function(coll)
    if not action.is_editable(coll) then
        local key = vim.api.nvim_replace_termcodes('<esc>', true, false, true)
        vim.api.nvim_feedkeys(key, 'n', false)
        print("WARNING: You can't make changes in results.")
    end
end

action.on_insert_leave = function(coll)
    if action.is_editable(coll) then
        action.search(coll)
    end
end

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

action.foldexpr = function(coll, lnum)
    assert(coll ~= nil)

    if lnum <= coll.ui_lines_number or coll.lookup_table == nil then
        return '0'
    end

    local entry = coll.lookup_table[lnum]

    if entry == nil or entry.l == nil then
        return '0'
    end

    local next_entry = coll.lookup_table[lnum + 1]
    if next_entry == nil then
        return '<1'
    end

    local prev_entry = coll.lookup_table[lnum - 1]
    if prev_entry and prev_entry.l == nil then
        return '>1'
    end

    return '1'
end

return action
