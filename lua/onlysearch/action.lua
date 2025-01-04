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

    if #query.text > 0 then
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

return action
