local ui = require("onlysearch.ui")
local action = require("onlysearch.action")
local search = require("onlysearch.search")

--- @class Query
--- @field cwd string working directory
--- @field text string search text
--- @field paths string search paths separated by space(' ')
--- @field flags string search flags separated by space(' '), e.g. -w, -i, etc.
--- @field filters string filters separated by space(' '), e.g. *.lua, !*.c, !target/, etc.

--- @class EngineCfg
--- @field mandatory_args string[] | nil  user should not using this item
--- @field args string[] | nil
--- @field complete table[] | nil

--- @class UserConfig
--- @field engine string external search tool, e.g. rg, grep
--- @field engine_config EngineCfg
--- @field open_cmd string
--- @field search_leave_insert boolean
--- @field keymaps table
    --- field normal table[]
    --- field insert table[]
    --- field visual table[]

--- @class Onlysearch
--- @field bufnr number | nil onlysearch buffer number
--- @field winid number | nil onlysearch window unique id
--- @field target_winid number | nil  the id of the window that open the onlysearch window
--- @field lookup_table table | nil
--- @field selected_items table | nil
--- @field query table  for resuming the last query
    --- field last Query  last searched query
    --- field current Query  current searched query
--- @field config UserConfig  user custom config
local coll = {
    bufnr = nil,
    winid = nil,
    target_winid = nil,
    lookup_table = nil,
    selected_items = nil,
    query = {
        last = nil,
        current = nil,
    },
    config = {
        engine = "rg",
        engine_config = {},
        open_cmd = "vnew",  -- `new` `vnew`, etc.
        search_leave_insert = false,
        keymaps = {
            normal = {
                ['<cr>'] = 'select_entry',
                ['='] = 'toggle_lines',
                ['<leader>='] = 'clear_all_selected_items',
                ['Q'] = 'send2qf',
                ['<leader>r'] = 'resume_last_query',
                ['S'] = 'search',
            },
            insert = {
                ['<C-f>'] = 'omnifunc',
            },
            visual = {
                ['='] = 'toggle_lines',
            },
        },
    },
}
coll.__index = coll

--- set custom options for onlysearch buffer and window
--- @param winid number onlysearch window's id(unique id)
--- @param bufnr number onlysearch buffer number
local set_option = function(winid, bufnr)
    local win_opt = { scope = "local", win = winid }
    local buf_opt = { buf = bufnr }
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
  vim.api.nvim_set_option_value('foldexpr', 'onlysearch#foldexpr()', win_opt)
  vim.api.nvim_set_option_value('foldmethod', 'expr', win_opt)
  vim.api.nvim_set_option_value('winfixbuf', true, win_opt)
  -- buf options --
  vim.api.nvim_set_option_value('bufhidden', 'wipe', buf_opt) -- NOTE: or 'delete'
  vim.api.nvim_set_option_value('buflisted', false, buf_opt)
  vim.api.nvim_set_option_value('buftype', 'nowrite', buf_opt)
  vim.api.nvim_set_option_value('swapfile', false, buf_opt)
  vim.api.nvim_set_option_value('filetype', 'nofile', buf_opt)
  -- vim.api.nvim_set_option_value('omnifunc', '', buf_opt)
end

--- For deleting onlysearch buffer, used by win_delete()
--- @param bufnr number
local buf_delete = function(bufnr)
  if bufnr == nil then
    return
  end

  -- Suppress the buffer deleted message for those with &report<2
  local start_report = vim.o.report
  if start_report < 2 then
    vim.o.report = 2
  end

  if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end

  if start_report < 2 then
    vim.o.report = start_report
  end
end

--- For closing onlysearch window and deleting the buffer, used by coll:close()
--- @param win_id number
--- @param force boolean see :h nvim_win_close
--- @param bdelete boolean delete the buffer or not
local win_delete = function(win_id, force, bdelete)
  if win_id == nil or not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  local bufnr = vim.api.nvim_win_get_buf(win_id)
  if bdelete then
    buf_delete(bufnr)
  end

  if not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  vim.api.nvim_win_close(win_id, force)
end


--- Create a new coll instance
--- @param opts table user config for onlysearch
--- @return Onlysearch a coll instance with user config
function coll:new(opts)
    opts = opts or {}
    coll.config = vim.tbl_deep_extend('force', coll.config, opts)

    return coll
end

--- Open onlysearch window
function coll:open()
    if self.bufnr == nil then
        vim.cmd("silent keepalt " .. self.config.open_cmd)
        self.bufnr = vim.fn.bufnr()
        self.winid = vim.fn.bufwinid(self.bufnr)
        _G.__jsj_onlysearch_foldexpr = function(lnum)
            return action.foldexpr(self, lnum)
        end
        set_option(self.winid, self.bufnr)

        coll.finder = search.construct_finder(self.config.engine,
            self.config.engine_config, self:handler())
    end

    self.ui_lines_number = ui:render_header(self.bufnr, self.config.engine)

    local os_group = vim.api.nvim_create_augroup("Undotree_collector", { clear = true })
    -- clear autocmd
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        buffer = self.bufnr,
        group = os_group,
        callback = function()
            self.winid = nil
            self.bufnr = nil
            self:resume_query()
        end,
    })
    -- search autocmd
    if self.config.search_leave_insert then
        vim.api.nvim_create_autocmd("InsertLeave", {
            buffer = self.bufnr,
            group = os_group,
            callback = function() action.on_insert_leave(self) end,
        })
    end
    -- limitation autocmds
    vim.api.nvim_create_autocmd("InsertEnter", {
        buffer = self.bufnr,
        group = os_group,
        callback = function() action.on_insert_enter(self) end,
    })
    self.prev_backspace = vim.api.nvim_get_option_value('backspace', { scope = "global" })
    vim.api.nvim_create_autocmd({ 'InsertEnter', 'CursorMovedI' }, {
        buffer = self.bufnr,
        group = os_group,
        callback = function()
            vim.opt.backspace = "indent,start"
            if not action.is_editable(self) then
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinLeave", {
        buffer = self.bufnr,
        group = os_group,
        callback = function()
            vim.opt.backspace = self.prev_backspace
        end
    })

    local map_opts = { noremap = true, silent = true, buffer = self.bufnr }
    -- NOTE: limatation keymaps
    vim.keymap.set('n', 'd', '<nop>', map_opts)
    vim.keymap.set('n', 'D', function() action.limit_delete(self, 'D') end, map_opts)
    vim.keymap.set('n', 'u', '<nop>', map_opts)
    vim.keymap.set('n', 'x', function() action.limit_delete(self, 'x') end, map_opts)
    vim.keymap.set('n', 'X', '<nop>', map_opts)
    vim.keymap.set('n', '<C-r>', '<nop>', map_opts)
    vim.keymap.set('n', 'o', 'ji', map_opts)
    vim.keymap.set('n', 'O', 'ki', map_opts)
    vim.keymap.set('n', 'C', '<nop>', map_opts)
    vim.keymap.set('n', 'c', '<nop>', map_opts)
    vim.keymap.set('n', 's', '<nop>', map_opts)
    vim.keymap.set('n', 'S', '<nop>', map_opts)
    vim.keymap.set('i', '<Cr>', '<nop>', map_opts)
    vim.keymap.set('i', '<C-j>', '<C-[>', map_opts)
    vim.keymap.set('n', 'p', function() action.limit_paste(self, 'p') end, map_opts)
    vim.keymap.set('n', 'P', function() action.limit_paste(self, 'P') end, map_opts)
    -- NOTE: action map
    for k, f in pairs(self.config.keymaps.normal) do
        vim.keymap.set("n", k, function() action[f](self) end, map_opts)
    end
    for k, f in pairs(self.config.keymaps.insert) do
        vim.keymap.set("i", k, function() action[f](self) end, map_opts)
    end
    for k, f in pairs(self.config.keymaps.visual) do
        vim.keymap.set("x", k, function() action[f](self, true) end, map_opts)
    end
end

--- Close onlysearch window
function coll:close()
    win_delete(self.winid, true, true)
    self.winid = nil
    self.bufnr = nil
end


--- handlers for searching process
function coll:handler()
    --- @class SearchCtx
    --- @field bufnr number
    --- @field last_p string | nil
    --- @field sep_lnum number
    --- @field clnum number
    --- @field c table
        --- field file number
        --- field match number
        --- field time number
    --- @field has_error boolean
    local h_ctx = nil
    return {
        on_start = function()
            self.lookup_table = {}
            self.selected_items = {}

            h_ctx = {
                bufnr = self.bufnr,
                last_p  = nil,
                sep_lnum = self.ui_lines_number - 1,
                clnum = self.ui_lines_number,
                c = { file = 0, match = 0, time = vim.uv.hrtime() },
                has_error = false,
            }

            ui:clear_ctx(h_ctx.bufnr, h_ctx.clnum)
            ui:render_sep(h_ctx.bufnr, h_ctx.sep_lnum)
        end,
        on_result = function(item)
            if h_ctx and not h_ctx.has_error and h_ctx.bufnr and item then
                if type(item) == "table" then
                    if h_ctx.last_p ~= item.p then
                        h_ctx.c.file = h_ctx.c.file + 1
                        h_ctx.last_p = item.p
                        h_ctx.clnum = ui:render_filename(h_ctx.bufnr, h_ctx.clnum, item.p)
                        self.lookup_table[h_ctx.clnum] = { filename = item.p }
                    end

                    if item.subm then
                        h_ctx.c.match = h_ctx.c.match + #item.subm
                    else
                        h_ctx.c.match = h_ctx.c.match + 1
                    end

                    h_ctx.clnum = ui:render_match_line(h_ctx.bufnr, h_ctx.clnum, item.l, item.c, item.subm)
                    -- NOTE: compatible with vim quickfix, but not showing any text.
                    --       I think I will only send result to quickfix, when i need to replace maybe
                    self.lookup_table[h_ctx.clnum] = { filename = item.p, lnum = item.l, text = "..." }
                elseif type(item) == "string" then
                    h_ctx.clnum = ui:render_message(h_ctx.bufnr, h_ctx.clnum, item)
                end
            end
        end,
        on_error = function(item)
            if h_ctx then
                if not h_ctx.has_error then
                    ui:clear_ctx(h_ctx.bufnr, h_ctx.clnum)
                    ui:render_sep(h_ctx.bufnr, h_ctx.sep_lnum, true)
                    h_ctx.has_error = true
                    self.lookup_table = nil
                end

                if type(item) == "table" then
                    for _, l in ipairs(item) do
                        h_ctx.clnum = ui:render_error(h_ctx.bufnr, h_ctx.clnum, l)
                    end
                else
                    h_ctx.clnum = ui:render_error(h_ctx.bufnr, h_ctx.clnum, item)
                end
            end
        end,
        on_finish = function()
            if h_ctx and not h_ctx.has_error then
                h_ctx.c.time = (vim.uv.hrtime() - h_ctx.c.time) / 1E9
                local res = nil
                if h_ctx.c.file > 0 and h_ctx.c.match > 0 then
                    res = string.format("(%d matches in %d files):(time: %.03fs)",
                        h_ctx.c.match, h_ctx.c.file, h_ctx.c.time)
                end
                ui:render_sep(h_ctx.bufnr, h_ctx.sep_lnum, false, res)
                -- NOTE: this is for making fold correct at the last match line
                h_ctx.clnum = ui:render_message(h_ctx.bufnr, h_ctx.clnum, "")
            end
        end
    }
end

--- backup last query
--- @param query Query
function coll:backup_query(query)
    if type(self.query) ~= "table" then
        self.query = {}
    end

    self.query.last = self.query.current
    -- NOTE: As i don't change the query, Do not need deepcopy
    self.query.current = query
end

--- resume last query
--- @return Query | nil
function coll:resume_query()
    if self.query then
        if self.query.last then
            local query = self.query.last
            self:backup_query(query)
        end
        return self.query.current
    end

    return nil
end

return coll
