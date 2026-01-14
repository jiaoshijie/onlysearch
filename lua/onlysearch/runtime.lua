local cfg = require("onlysearch.config")
local kit = require("onlysearch.kit")
local action = require("onlysearch.action")
local ui = require("onlysearch.ui")
local engine = require("onlysearch.engine")
local fmt = string.format

local _M = {}

--- @class Query
--- @field text string search text
--- @field paths string search paths separated by space(' ')
--- @field flags string search flags separated by space(' '), e.g. -w, -i, etc.
--- @field filters string filters separated by space(' '), e.g. *.lua, !*.c, !target/, etc.

--- @class MatchRange
--- @field s number the start position of matched item(zero-based)
--- @field e number the end postion of matched item(excluded)

--- @class MatchedItem
--- @field p string the file path of matched item
--- @field c string the line content of matched item
--- @field l number the line number of matched item in the file
--- @field subm ?MatchRange[]

-- { engine_checked }
local rt_env = {
    engine_checked = false,
    ns = {
        header_id = nil,
        result_id = nil,
        select_id = nil,
    },
}

-- { on_start, on_finish, on_result, on_error }
local rt_callbacks = {}

--- @type Query[]
local query_hist_array = {}

local ctx = {
    env_weak_ref = nil,
    cbs_weak_ref = nil,
    query_hist_array_ref = nil,
    engine_search_fn = nil,  -- fn(rt_ctx)

    bufnr = nil,
    winid = nil,
    target_winid = nil,
    sep_extmark_id = nil,

    query = nil,  -- Query
    lookup_table = nil,
    selected_items = nil,  -- table

    progress_ctx = {
        has_error = nil,
        cur_lnum = nil,  -- 0-based index
        cur_file_path = nil,
        match_info = {
            files = nil,
            matches = nil,
            time = nil,
        },
    },
    engine_ctx = {
        id = nil,
        cmd = nil,
        args = nil,
        cwd = nil,
        is_raw_data = nil,        -- boolean
        stdout_last_chunk = nil,  -- string?
        stderr_last_chunk = nil,  -- string?

        -- uv
        uv_ctx = {
            pid = nil, -- number
            handle = nil, -- uv_process_t
            stdout = nil, -- uv_pipe_t
            stderr = nil, -- uv_pipe_t
            shutdown_check = nil, -- uv_check_t
        }
    },

    query_hist_ctx = {
        last_cur_lnum = 0,
        bufnr = nil,
        winid = nil,
        p_bufnr = nil,
        p_winid = nil,
    },

    orignal_vim_dot_paste = nil,
    prev_backspace_opt = nil,
}

rt_callbacks.on_start = function()
    ctx.lookup_table = {}
    ctx.selected_items = {}

    ctx.progress_ctx = {
        has_error = false,
        cur_lnum = cfg.ui_cfg.header_lines,  -- 0-based index
        cur_file_path = nil,
        match_info = {
            files = 0,
            matches = 0,
            time = vim.uv.hrtime(),
        },
    }

    ui.clear_result(ctx)
    ui.render_sep(ctx, false)
end

--- @param item MatchedItem | string  string when the cmd has --version/--help flag
rt_callbacks.on_result = function(item)
    local pctx = ctx.progress_ctx
    if not pctx or pctx.has_error or not item then return end

    if type(item) == "table" then
        if pctx.cur_file_path ~= item.p then
            pctx.cur_file_path = item.p
            pctx.match_info.files = pctx.match_info.files + 1
            pctx.cur_lnum = ui.render_filename(ctx, pctx.cur_lnum, item.p)
            ctx.lookup_table[pctx.cur_lnum] = { filename = item.p }
        end

        if item.subm then
            pctx.match_info.matches = pctx.match_info.matches + #item.subm
        else
            pctx.match_info.matches = pctx.match_info.matches + 1
        end
        pctx.cur_lnum = ui.render_match_line(ctx, pctx.cur_lnum, item.l, item.c, item.subm)

        -- NOTE: compatible with vim quickfix, but not showing any text.
        --       I think I will only send result to quickfix, when i need to replace maybe
        ctx.lookup_table[pctx.cur_lnum] = { filename = item.p, lnum = item.l, text = "..." }
    elseif type(item) == "string" then
        pctx.cur_lnum = ui.render_message(ctx, pctx.cur_lnum, item)
    end
end

--- @param item string
rt_callbacks.on_error = function(item)
    local pctx = ctx.progress_ctx
    if not pctx then return end
    if not pctx.has_error then
        -- NOTE: set the clnum to the begin of result line number,
        -- and clear the stdout result only showing the error message
        pctx.has_error = true
        ctx.lookup_table = nil
        ctx.selected_items = nil
        pctx.cur_lnum = cfg.ui_cfg.header_lines

        ui.clear_result(ctx)
        ui.render_sep(ctx, true)

        pctx.cur_lnum = ui.render_error(ctx, pctx.cur_lnum, "")
        pctx.cur_lnum = ui.render_error(ctx, pctx.cur_lnum,
            ctx.engine_ctx.cmd .. ' ' .. table.concat(ctx.engine_ctx.args, ' '))
        pctx.cur_lnum = ui.render_error(ctx, pctx.cur_lnum, "")
    end

    pctx.cur_lnum = ui.render_error(ctx, pctx.cur_lnum, item)
end

rt_callbacks.on_finish = function()
    local pctx = ctx.progress_ctx
    if not pctx or pctx.has_error then return end

    local stats = nil
    if pctx.match_info.matches > 0 then
        stats = string.format("(%d matches in %d files):(time: %.03fs)",
                pctx.match_info.matches, pctx.match_info.files,
                (vim.uv.hrtime() - pctx.match_info.time) / 1E9)
    else
        stats = string.format("(no matches)")
    end
    ui.render_sep(ctx, false, stats)
    -- append an empty line at the end of result
    -- for making fold correct at the last match line
    pctx.cur_lnum = ui.render_message(ctx, pctx.cur_lnum, "")
end

--- @return boolean
local validate_env = function()
    -- 1. check whether it is already opened
    if _M.is_opend() then
        kit.echo_err_msg("Onlysearch has already opened")
        return false
    end

    -- 2. if the focused window is command line
    if vim.fn.win_gettype() == "command" then
        kit.echo_err_msg("Unable to open from command-line window: `:h E11`")
        return false
    end

    -- 3. get the namespace ids
    -- Suppose the nvim_create_namespace will always success
    if rt_env.ns.header_id == nil then
        rt_env.ns.header_id = vim.api.nvim_create_namespace("onlysearch_header_ns")
    end
    if rt_env.ns.result_id == nil then
        rt_env.ns.result_id = vim.api.nvim_create_namespace("onlysearch_result_ns")
    end
    if rt_env.ns.select_id == nil then
        rt_env.ns.select_id = vim.api.nvim_create_namespace("onlysearch_select_ns")
    end

    -- 4. if rg/grep version not match
    if rt_env.engine_checked then return true end

    if cfg.common.engine == "rg" then
        local major, _ = kit.get_cmd_version('rg', '--version', '(%d+)%.(%d+)%.%d+')
        if major == nil or major < 13 then
            kit.echo_err_msg("ripgrep version is below 13.0.0")
            return false
        end
    elseif cfg.common.engine == "grep" then
        local major, minor = kit.get_cmd_version('grep', '--version', '%(GNU grep%) (%d+)%.(%d+)')
        if major == nil or major < 3 or (major == 3 and minor < 7) then
            kit.echo_err_msg("grep is not GNU grep or version is below 3.7")
            return false
        end
    else
        kit.echo_err_msg(fmt("search engine `%s` is not supported!", cfg.common.engine))
        return false
    end
    rt_env.engine_checked = true

    return true
end

local set_target_winid = function()
    ctx.target_winid = vim.fn.win_getid()
end

local set_option = function()
    local win_opt = { win = ctx.winid }
    local buf_opt = { buf = ctx.bufnr }
    -- set buffer name --
    vim.api.nvim_buf_set_name(ctx.bufnr, cfg.buf_name)
    -- window options --
    vim.api.nvim_set_option_value('number', false, win_opt)
    vim.api.nvim_set_option_value('relativenumber', false, win_opt)
    vim.api.nvim_set_option_value('winfixwidth', true, win_opt)
    vim.api.nvim_set_option_value('wrap', false, win_opt)
    vim.api.nvim_set_option_value('spell', false, win_opt)
    vim.api.nvim_set_option_value('cursorline', true, win_opt)
    vim.api.nvim_set_option_value('signcolumn', 'no', win_opt)
    vim.api.nvim_set_option_value('colorcolumn', '0', win_opt)
    vim.api.nvim_set_option_value('foldenable', false, win_opt)
    vim.api.nvim_set_option_value('foldexpr', [[v:lua.require('onlysearch.runtime').foldexpr(v:lnum)]], win_opt)
    vim.api.nvim_set_option_value('foldmethod', 'expr', win_opt)
    vim.api.nvim_set_option_value('winfixbuf', true, win_opt)
    -- buf options --
    vim.api.nvim_set_option_value('bufhidden', 'wipe', buf_opt) -- NOTE: or 'delete'
    vim.api.nvim_set_option_value('buflisted', false, buf_opt)
    vim.api.nvim_set_option_value('buftype', 'nofile', buf_opt)
    vim.api.nvim_set_option_value('swapfile', false, buf_opt)
    vim.api.nvim_set_option_value('filetype', 'onlysearch', buf_opt)
    vim.api.nvim_set_option_value('iskeyword', cfg.common.keyword, buf_opt)
    vim.api.nvim_set_option_value('omnifunc', [[v:lua.onlysearch_custom_omnifunc]], buf_opt)
end

local set_events = function(ev_group)
    vim.api.nvim_create_autocmd("WinClosed", {
        buffer = ctx.bufnr,
        group = ev_group,
        callback = function(ev)
            -- Both <amatch> and <afile> are set to the |window-ID|
            if tonumber(ev.match) == ctx.winid then
                _M.close()
            end
        end,
    })
    if cfg.common.search_leave_insert then
        vim.api.nvim_create_autocmd("InsertLeave", {
            buffer = ctx.bufnr,
            group = ev_group,
            callback = function() action.on_insert_leave(ctx) end,
        })
    end
end

local set_keymaps = function()
    local map_opts = { noremap = true, silent = true, buffer = ctx.bufnr }

    for k, f in pairs(cfg.keymaps_cfg.normal) do
        vim.keymap.set("n", k, function() action[f](ctx) end, map_opts)
    end
    for k, f in pairs(cfg.keymaps_cfg.visual) do
        vim.keymap.set("x", k, function() action[f](ctx, true) end, map_opts)
    end
end

local set_limitation = function(ev_group)
    ctx.prev_backspace_opt = vim.api.nvim_get_option_value('backspace', { scope = "global" })
    vim.opt.backspace = "indent,start"

    vim.api.nvim_create_autocmd("InsertEnter", {
        buffer = ctx.bufnr,
        group = ev_group,
        callback = function() action.limit.on_insert_enter() end,
    })
    vim.api.nvim_create_autocmd({ 'CursorMovedI' }, {
        buffer = ctx.bufnr,
        group = ev_group,
        callback = function()
            if not action.is_editable() then
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinEnter", {
        buffer = ctx.bufnr,
        group = ev_group,
        callback = function() vim.opt.backspace = "indent,start" end
    })
    vim.api.nvim_create_autocmd("WinLeave", {
        buffer = ctx.bufnr,
        group = ev_group,
        callback = function() vim.opt.backspace = ctx.prev_backspace_opt end
    })

    local map_opts = { noremap = true, silent = true, buffer = ctx.bufnr }
    -- NOTE: limatation keymaps
    vim.keymap.set('n', 'dd', '<nop>', map_opts)
    vim.keymap.set('n', 'd', function() action.limit.modify_text('d') end, map_opts)
    vim.keymap.set('v', 'd', '<nop>', map_opts)
    vim.keymap.set('n', 'x', function() action.limit.modify_text('x') end, map_opts)
    vim.keymap.set('v', 'x', '<nop>', map_opts)
    vim.keymap.set({'n', 'v'}, 'X', '<nop>', map_opts)
    vim.keymap.set('n', 'r', function() action.limit.modify_text('r') end, map_opts)
    vim.keymap.set('v', 'r', '<nop>', map_opts)
    vim.keymap.set('n', 'R', function() action.limit.modify_text('R') end, map_opts)
    vim.keymap.set('v', 'R', '<nop>', map_opts)
    vim.keymap.set('n', 'u', '<nop>', map_opts)
    vim.keymap.set('n', '<C-r>', '<nop>', map_opts)
    vim.keymap.set('n', 'o', 'ji', map_opts)
    vim.keymap.set('n', 'O', 'ki', map_opts)
    vim.keymap.set({'n', 'v'}, 'C', '<nop>', map_opts)
    vim.keymap.set({'n', 'v'}, 'c', '<nop>', map_opts)
    vim.keymap.set({'n', 'v'}, 's', '<nop>', map_opts)
    vim.keymap.set({'n', 'v'}, 'S', '<nop>', map_opts)
    vim.keymap.set('i', '<Cr>', '<nop>', map_opts)
    vim.keymap.set('i', '<C-j>', '<C-[>', map_opts)
    -- NOTE: insert mode <C-r> {register_name}: this is not handled
    vim.keymap.set({'n', 'v'}, 'p', function() action.limit.paste('p') end, map_opts)
    vim.keymap.set({'n', 'v'}, 'P', function() action.limit.paste('P') end, map_opts)
    vim.keymap.set({'n', 'v'}, 'J', 'j', map_opts)
    vim.keymap.set({'n', 'v'}, 'gJ', 'j', map_opts)
    if cfg.common.handle_sys_clipboard_paste then
        ctx.orignal_vim_dot_paste = vim.paste
        vim.paste = action.limit.sys_clipboard_paste(ctx)
    end
end

--- @return boolean
_M.is_opend = function()
    return ctx.bufnr ~= nil
end

_M.open = function(open_cmd, query)
    if not validate_env() then return end
    ctx.env_weak_ref = rt_env
    ctx.cbs_weak_ref = rt_callbacks
    ctx.query_hist_array_ref = query_hist_array
    set_target_winid()

    vim.cmd(fmt("silent keepalt %s", open_cmd or "vnew"))
    ctx.bufnr = vim.fn.bufnr()
    ctx.winid = vim.fn.bufwinid(ctx.bufnr)
    set_option()

    local ev_group = vim.api.nvim_create_augroup("onlysearch_rt_event", { clear = true })
    set_events(ev_group)
    set_limitation(ev_group)
    -- NOTE: set_keymaps must below set_limitation, otherwise the set_limitation may override the user defined keymaps
    set_keymaps()

    ctx.engine_search_fn = engine.search
    if not query then
        ui.render_header(ctx)
    else
        ui.render_query(ctx, query)
        if query.text and #query.text >= 3 then
            ctx.query = query
            engine.search(ctx)
        end
    end
end

_M.close = function()
    if not _M.is_opend() then return end

    engine.close(ctx)

    ctx.env_weak_ref = nil
    ctx.query_hist_array_ref = nil
    ctx.cbs_weak_ref = nil
    ctx.target_winid = nil

    action.query_hist_close(ctx)
    kit.win_delete(ctx.winid, true)
    kit.buf_delete(ctx.bufnr)
    ctx.winid = nil
    ctx.bufnr = nil

    -- NOTE: Namespace does not need to be cleared
    -- All the highlights and marks are buf specific and the buf was deleted

    ctx.query = nil
    ctx.lookup_table = nil
    ctx.selected_items = nil

    if ctx.prev_backspace_opt then
        vim.opt.backspace = ctx.prev_backspace_opt
    end

    if ctx.orignal_vim_dot_paste then
        vim.paste = ctx.orignal_vim_dot_paste
    end
end

--- @return boolean
_M.is_visible_on_cur_tab = function()
    if not _M.is_opend() then return false end
    return kit.winid_in_tab(ctx.winid)
end

_M.foldexpr = function(lnum)
    return action.foldexpr(ctx, lnum)
end

_G.onlysearch_custom_omnifunc = function(findstart, base)
    local engine_cfg = cfg.engines_cfg[cfg.common.engine]

    if not engine_cfg or not engine_cfg.complete or #engine_cfg.complete == 0 then
        return -3
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    if cursor[1] ~= cfg.ui_cfg.header.extra_flags.lnum + 1 then
        kit.echo_err_msg("Only complete flags in line number 3")
        return -3
    end

    if findstart == 1 then
        local cursor_col = cursor[2] + 1  -- convert 0-based to 1-based column
        local line = vim.api.nvim_get_current_line()
        return vim.fn.match(line:sub(1, cursor_col), '\\k*$')
    end

    return vim.tbl_filter(function(item)
        return item.word and vim.startswith(item.word, base)
    end, engine_cfg.complete)
end

return _M
