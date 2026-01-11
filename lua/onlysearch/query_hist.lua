local ui = require("onlysearch.ui")
local kit = require("onlysearch.kit")
local cfg = require("onlysearch.config")
local fmt = string.format

--- keymaps (DO NOT support user define he's own keymaps)
---     query window
---         dd -> delete one item from history
---         q -> quit the query window(destroy the window and preview window)
---         enter -> apply the query under the cursor
---         p -> switch to preview window
---     query preview window
---         q -> quit the query window(destroy the window and preview window)
---         enter -> apply the query under the cursor
---         p -> switch to preview window
--- event
---     WinClosed: Listened to free resources
---     CursorMoved: when cursor moved refresh the preview window
---     VimResized is NOT listened toj, as it should be a one-shot window.
---        If vim resized as the window opened, the layout may not look good.

local _M = {}

local function gen_win_layout(winid)
    local round = math.ceil
    local max_col, max_line
    if not winid then
        max_col, max_line = vim.o.columns, vim.o.lines
    else
        max_col = vim.api.nvim_win_get_width(winid)
        max_line = vim.api.nvim_win_get_height(winid)
    end

    max_line = max_line - vim.o.cmdheight
    if vim.o.ls ~= 0 then max_line = max_line - 1 end
    if #vim.o.winbar ~= 0 then max_line = max_line - 1 end

    local rel = winid and "win" or "editor"
    local main = { relative = rel, win = winid }
    local preview = { relative = rel, win = winid }
    if max_line >= 25 and max_col >= 60 then
        main.width = round(max_col * 0.8)
        preview.width = main.width
        main.height = round(max_line * 0.8)
        preview.height = 4
        preview.row = round((max_line - (main.height + 4)) / 2)
        main.row = preview.row + preview.height + 2
        preview.col = round((max_col - main.width) / 2)
        main.col = preview.col
    elseif not winid then
        return nil
    else
        return gen_win_layout(nil)
    end

    return main, preview
end

--- @param rt_ctx table runtime_ctx
local qh_refresh = function(rt_ctx, only_preview)
    local qh_ctx = rt_ctx.query_hist_ctx
    local qh_arr = rt_ctx.query_hist_array_ref

    if not only_preview then
        local lines = {}
        for _, v in ipairs(qh_arr) do
            table.insert(lines, v.text)
        end
        vim.api.nvim_set_option_value("modifiable", true, { buf = qh_ctx.bufnr })
        vim.api.nvim_buf_set_lines(qh_ctx.bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value("modifiable", false, { buf = qh_ctx.bufnr })
    end

    local ok, pos = pcall(vim.api.nvim_win_get_cursor, qh_ctx.winid)
    if not ok then return end
    if only_preview and pos[1] == qh_ctx.last_cur_lnum then
        return
    end

    qh_ctx.last_cur_lnum = pos[1]
    local query = qh_arr[pos[1]]
    local lines = query and { query.text, query.paths, query.flags, query.filters } or {}
    vim.api.nvim_set_option_value("modifiable", true, { buf = qh_ctx.p_bufnr })
    vim.api.nvim_buf_set_lines(qh_ctx.p_bufnr, 0, 4, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = qh_ctx.p_bufnr })
end

--- @param rt_ctx table runtime_ctx
local set_keymaps = function(rt_ctx)
    local qh_ctx = rt_ctx.query_hist_ctx
    assert(qh_ctx.bufnr ~= nil)
    vim.keymap.set("n", "dd", function() _M.del(rt_ctx) end, { buffer = qh_ctx.bufnr })
    vim.keymap.set("n", "q", function() _M.close(rt_ctx) end, { buffer = qh_ctx.bufnr })
    vim.keymap.set("n", "<cr>", function() _M.apply(rt_ctx) end, { buffer = qh_ctx.bufnr })
    vim.keymap.set("n", "p", function() _M.win_switch(rt_ctx) end, { buffer = qh_ctx.bufnr })

    vim.keymap.set("n", "q", function() _M.close(rt_ctx) end, { buffer = qh_ctx.p_bufnr })
    vim.keymap.set("n", "<cr>", function() _M.apply(rt_ctx) end, { buffer = qh_ctx.p_bufnr })
    vim.keymap.set("n", "p", function() _M.win_switch(rt_ctx) end, { buffer = qh_ctx.p_bufnr })
end

--- @param rt_ctx table runtime_ctx
local set_event = function(rt_ctx)
    local qh_ctx = rt_ctx.query_hist_ctx
    assert(qh_ctx.bufnr ~= nil)

    local ev_group = vim.api.nvim_create_augroup("onlysearch_query_history_event", { clear = true })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = ev_group,
        buffer = qh_ctx.bufnr,
        callback = function()
            _M.close(rt_ctx)
        end
    })
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = ev_group,
        buffer = qh_ctx.bufnr,
        callback = function()
            qh_refresh(rt_ctx, true)
        end
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = ev_group,
        buffer = qh_ctx.q_bufnr,
        callback = function()
            _M.close(rt_ctx)
        end
    })
end

local set_options = function(qh_ctx)
    vim.api.nvim_set_option_value('cursorline', true, { win = qh_ctx.winid })
    vim.api.nvim_set_option_value('cursorlineopt', "both", { win = qh_ctx.winid })
    vim.api.nvim_set_option_value('number', true, { win = qh_ctx.winid })
    vim.api.nvim_set_option_value('relativenumber', false, { win = qh_ctx.winid })
    vim.api.nvim_set_option_value('wrap', false, { win = qh_ctx.winid })
    vim.api.nvim_set_option_value('spell', false, { win = qh_ctx.winid })
    vim.api.nvim_set_option_value('signcolumn', 'no', { win = qh_ctx.winid })
    vim.api.nvim_set_option_value('colorcolumn', '0', { win = qh_ctx.winid })
    vim.api.nvim_set_option_value('foldenable', false, { win = qh_ctx.winid })
    vim.api.nvim_set_option_value('list', false, { win = qh_ctx.winid })
    vim.api.nvim_set_option_value('scrolloff', 0, { win = qh_ctx.winid })
    vim.api.nvim_set_option_value('winbar', "", { win = qh_ctx.winid })

    vim.api.nvim_set_option_value('cursorline', false, { win = qh_ctx.p_winid })
    vim.api.nvim_set_option_value('number', false, { win = qh_ctx.p_winid })
    vim.api.nvim_set_option_value('relativenumber', false, { win = qh_ctx.p_winid })
    vim.api.nvim_set_option_value('wrap', false, { win = qh_ctx.p_winid })
    vim.api.nvim_set_option_value('spell', false, { win = qh_ctx.p_winid })
    vim.api.nvim_set_option_value('signcolumn', 'no', { win = qh_ctx.p_winid })
    vim.api.nvim_set_option_value('colorcolumn', '0', { win = qh_ctx.p_winid })
    vim.api.nvim_set_option_value('foldenable', false, { win = qh_ctx.p_winid })
    vim.api.nvim_set_option_value('list', false, { win = qh_ctx.p_winid })
    vim.api.nvim_set_option_value('scrolloff', 0, { win = qh_ctx.p_winid })
    vim.api.nvim_set_option_value('winbar', "", { win = qh_ctx.p_winid })
end

local qh_render = function(rt_ctx, main, preview)
    local qh_ctx = rt_ctx.query_hist_ctx
    assert(qh_ctx.bufnr ~= nil)
    qh_ctx.winid = vim.api.nvim_open_win(qh_ctx.bufnr, true, {
        relative = main.relative,
        win = main.win,
        col = main.col,
        row = main.row,
        width = main.width,
        height = main.height,
        style = "minimal",
        noautocmd = true,
        border = "rounded",
    })
    vim.api.nvim_set_option_value('winblend', 0, { win = qh_ctx.winid })
    qh_ctx.p_winid = vim.api.nvim_open_win(qh_ctx.p_bufnr, false, {
        relative = preview.relative,
        win = preview.win,
        col = preview.col,
        row = preview.row,
        width = preview.width,
        height = preview.height,
        style = "minimal",
        noautocmd = true,
        border = "rounded",
    })
    vim.api.nvim_set_option_value('winblend', 0, { win = qh_ctx.p_winid })
    set_options(qh_ctx)
end

--- This function can only be called in the main onlysearch window
--- @param rt_ctx table runtime_ctx
_M.open = function(rt_ctx)
    if vim.fn.win_getid() ~= rt_ctx.winid then
        kit.echo_err_msg("Not in main window")
        return
    end
    local qh_ctx = rt_ctx.query_hist_ctx
    local qh_arr = rt_ctx.query_hist_array_ref
    if qh_ctx.bufnr ~= nil then
        kit.echo_err_msg("query history window has already opened")
        return
    end
    if #qh_arr == 0 then
        kit.echo_info_msg("No query stores in history")
        return
    end

    local main, preview = gen_win_layout(rt_ctx.winid)
    if main == nil then
        kit.echo_info_msg("NeoVim view size is too small")
        return
    end
    qh_ctx.bufnr = vim.api.nvim_create_buf(false, true)
    qh_ctx.p_bufnr = vim.api.nvim_create_buf(false, true)
    set_keymaps(rt_ctx)
    set_event(rt_ctx)
    qh_render(rt_ctx, main, preview)
    qh_refresh(rt_ctx, false)
end

--- This function can only be called in the main onlysearch window
--- @param rt_ctx table runtime_ctx
_M.add = function(rt_ctx)
    if vim.fn.win_getid() ~= rt_ctx.winid then
        kit.echo_err_msg("Not in main window")
        return
    end

    if not rt_ctx.query then
        kit.echo_err_msg("No query need to add")
        return
    end
    local query = rt_ctx.query

    local qh_arr = rt_ctx.query_hist_array_ref
    if not qh_arr then
        kit.echo_err_msg("query history context is nil, do nothing")
        return
    end

    for i, q in ipairs(qh_arr) do
        if q.text == query.text and q.paths == query.paths
            and q.flags == query.flags and q.filters == query.filters then
            kit.echo_info_msg(fmt("query already in the histroy array at %d, do nothing", i))
            return
        end
    end

    if #qh_arr == cfg.common.query_history_size then
        table.remove(qh_arr, #qh_arr)
    end

    table.insert(qh_arr, 1, rt_ctx.query)
    kit.echo_info_msg(fmt("query `%s` added to history", rt_ctx.query.text))
end

--- This function can be called in any window
--- @param rt_ctx table runtime_ctx
_M.close = function(rt_ctx)
    local qh_ctx = rt_ctx.query_hist_ctx
    assert(qh_ctx ~= nil)
    if not qh_ctx.bufnr then
        return
    end
    kit.win_delete(qh_ctx.winid, true)
    qh_ctx.winid = nil
    kit.buf_delete(qh_ctx.bufnr)
    qh_ctx.bufnr = nil
    kit.win_delete(qh_ctx.p_winid, true)
    qh_ctx.p_winid = nil
    kit.buf_delete(qh_ctx.p_bufnr)
    qh_ctx.p_bufnr = nil
    qh_ctx.last_cur_lnum = 0

    if rt_ctx.winid and vim.api.nvim_win_is_valid(rt_ctx.winid) then
        vim.fn.win_gotoid(rt_ctx.winid)
    end
end

--- This function can only be called in the query window
--- @param rt_ctx table runtime_ctx
_M.del = function(rt_ctx)
    local qh_ctx = rt_ctx.query_hist_ctx
    local qh_arr = rt_ctx.query_hist_array_ref
    if vim.fn.win_getid() ~= qh_ctx.winid then
        kit.echo_err_msg("Not in query history window")
        return
    end

    local ok, pos = pcall(vim.api.nvim_win_get_cursor, qh_ctx.winid)
    if not ok then return end
    if qh_arr[pos[1]] then
        table.remove(qh_arr, pos[1])
        qh_refresh(rt_ctx, false)
    end
end

--- This function can be called in the query window or the query preview window
--- apply the query
--- @param rt_ctx table runtime_ctx
_M.apply = function(rt_ctx)
    local qh_ctx = rt_ctx.query_hist_ctx
    local qh_arr = rt_ctx.query_hist_array_ref
    local cur_winid = vim.fn.win_getid()
    if cur_winid ~= qh_ctx.winid and cur_winid ~= qh_ctx.p_winid then
        kit.echo_err_msg("Not in query history/preview window")
        return
    end

    local ok, pos = pcall(vim.api.nvim_win_get_cursor, qh_ctx.winid)
    if not ok then return end
    local query = qh_arr[pos[1]]
    if not query then return end

    _M.close(rt_ctx)
    rt_ctx.query = query
    ui.resume_query(rt_ctx, query)
    rt_ctx.engine_search_fn(rt_ctx)
end

--- This function can be called in any window
--- switch between query and preview window, if not in one of them(in main window), jump to query window
--- @param rt_ctx table runtime_ctx
_M.win_switch = function(rt_ctx)
    local qh_ctx = rt_ctx.query_hist_ctx
    if qh_ctx.bufnr == nil then
        kit.echo_err_msg("query hist window not opened")
        return
    end
    if vim.fn.win_getid() == qh_ctx.winid then
        vim.fn.win_gotoid(qh_ctx.p_winid)
    else
        vim.fn.win_gotoid(qh_ctx.winid)
    end
end

return _M
