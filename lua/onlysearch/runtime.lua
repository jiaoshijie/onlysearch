local cfg = require("onlysearch.config")
local kit = require("onlysearch.kit")
local fmt = string.format

local _M = {}

--- @class Query
--- @field text string search text
--- @field paths string search paths separated by space(' ')
--- @field flags string search flags separated by space(' '), e.g. -w, -i, etc.
--- @field filters string filters separated by space(' '), e.g. *.lua, !*.c, !target/, etc.

-- { engine_checked }
local rt_env = {}

local ctx = {
    bufnr = nil,
    winid = nil,
    target_winid = nil,  -- TODO: check if this winid in the current tabpage

    ns = {
        header_id = nil,
        sep_extmark_id = nil,
        result_id = nil,
        select_id = nil,
    },

    lookup_table = nil,
    selected_items = nil,  -- table

    -- TODO: maybe make the query hist out of the ctx
    -- query_hist = nil,      -- a table of `Query`

    orignal_vim_dot_paste = nil,
}


--- @param reopen boolean
--- @return boolean
local validate_env = function(reopen)
    -- 1. check whether it is already opened
    if _M.is_opend() then
        if not reopen or kit.winid_in_tab(ctx.winid) then
            kit.echo_err_msg("Onlysearch has already opened")
            return false
        end
        _M.close()
    end

    -- 2. if the focused window is command line
    if vim.fn.win_gettype() == "command" then
        kit.echo_err_msg("Unable to open from command-line window: `:h E11`")
        return false
    end

    -- 3. if rg/grep version not match
    if rt_env.engine_checked then return true end

    if cfg.commen.engine == "rg" then
        local major, _ = kit.get_cmd_version('rg', '--version', '(%d+)%.(%d+)%.%d+')
        if major == nil or major < 13 then
            kit.echo_err_msg("ripgrep version is below 13.0.0")
            return false
        end
    elseif cfg.commen.engine == "grep" then
        local major, minor = kit.get_cmd_version('grep', '--version', '%(GNU grep%) (%d+)%.(%d+)')
        if major == nil or major < 3 or (major == 3 and minor < 7) then
            kit.echo_err_msg("grep is not GNU grep or version is below 3.7")
            return false
        end
    else
        kit.echo_err_msg(fmt("search engine `%s` is not supported!", cfg.commen.engine))
        return false
    end
    rt_env.engine_checked = true

    return true
end

--- @return boolean
_M.is_opend = function()
    return ctx.bufnr ~= nil
end

_M.open = function()
    if not validate_env(false) then return end
end

_M.close = function()
    -- TODO: engine clear should go first

    ctx.target_winid = nil
    kit.win_delete(ctx.winid, true)
    kit.buf_delete(ctx.bufnr)
    ctx.winid = nil
    ctx.bufnr = nil

    -- NOTE: Namespace does not need to be cleared
    -- All the highlights and marks are buf specific and the buf was deleted

    ctx.lookup_table = nil
    ctx.selected_items = nil

    -- TODO: query things

    if ctx.orignal_vim_dot_paste then
        vim.paste = ctx.orignal_vim_dot_paste
    end
end

_M.toggle = function()
    if not validate_env(true) then return end
end

return _M
