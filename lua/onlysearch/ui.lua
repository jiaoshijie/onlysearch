local cfg = require("onlysearch.config")
local fmt = string.format

local _M = {}

--- draw the virtual headers
--- @param rt_ctx table  runtime_ctx
function _M.render_header(rt_ctx)
    if not rt_ctx.bufnr or not vim.api.nvim_buf_is_loaded(rt_ctx.bufnr) then
        return
    end
    local ns = rt_ctx.env_weak_ref.ns

    local buf_line_number = vim.api.nvim_buf_line_count(rt_ctx.bufnr)
    local header_number = cfg.ui_cfg.header_lines

    if buf_line_number < header_number then
        local lines = {}
        for _ = 1, header_number - buf_line_number, 1 do
            table.insert(lines, "")
        end
        vim.api.nvim_buf_set_lines(rt_ctx.bufnr, -1, -1, false, lines)
    end

    for _, v in pairs(cfg.ui_cfg.header) do
        local text = v.fmt and fmt(v.text, cfg.common.engine) or v.text
        vim.api.nvim_buf_set_extmark(rt_ctx.bufnr, ns.header_id, v.lnum, 0, {
            virt_lines = { { { text, v.hl } } },
            virt_lines_leftcol = true,
            virt_lines_above = true,
            right_gravity = false,
        })
    end
end

--- render the file name of the result
--- @param rt_ctx table  runtime_ctx
--- @param lnum number the line number which the filename should be place at
--- @param line string the filename string
--- @return number the line number next content should be place at
function _M.render_filename(rt_ctx, lnum, line)
    if not rt_ctx.bufnr or not vim.api.nvim_buf_is_loaded(rt_ctx.bufnr) then
        return lnum
    end
    local ns = rt_ctx.env_weak_ref.ns

    vim.api.nvim_buf_set_lines(rt_ctx.bufnr, lnum, lnum, false, { "", line })
    lnum = lnum + 1
    vim.hl.range(rt_ctx.bufnr, ns.result_id, "OnlysearchFilename", { lnum, 0 },
        { lnum, vim.api.nvim_strwidth(line) }, { inclusive = false })

    return lnum + 1
end

--- render matched line of the result
--- @param rt_ctx table  runtime_ctx
--- @param lnum number the line number which the filename should be place at
--- @param mlnum number the line number of the match item in the file
--- @param line string
--- @param subms ?MatchRange[]
--- @return number the line number next content should be place at
function _M.render_match_line(rt_ctx, lnum, mlnum, line, subms)
    if not rt_ctx.bufnr or not vim.api.nvim_buf_is_loaded(rt_ctx.bufnr) then
        return lnum
    end
    local ns = rt_ctx.env_weak_ref.ns

    -- NOTE: cut long line to 255 characters
    line = string.sub(line, 0, 255)
    vim.api.nvim_buf_set_lines(rt_ctx.bufnr, lnum, lnum, false, { mlnum .. ':' .. line })
    local len = vim.api.nvim_strwidth('' .. mlnum)

    vim.hl.range(rt_ctx.bufnr, ns.result_id, "OnlysearchMatchLNum", { lnum, 0 },
        { lnum, len }, { inclusive = false })
    len = len + 1  -- len(':')

    if subms then
        for _, val in ipairs(subms) do
            if len + val.s < 255 and len + val.e < 255 then
                vim.hl.range(rt_ctx.bufnr, ns.result_id, "OnlysearchMatchCtx",
                    { lnum, len + val.s }, { lnum, len + val.e }, { inclusive = false })
            end
        end
    end
    return lnum + 1
end

--- draw the selected highlight or clear the selected highlight
--- @param rt_ctx table  runtime_ctx
--- @param lnum number the line number that selected or unseleted
--- @param is_sel boolean is select or not
function _M.toggle_sel_line(rt_ctx, lnum, is_sel)
    if not rt_ctx.bufnr or not vim.api.nvim_buf_is_loaded(rt_ctx.bufnr) then
        return
    end
    local ns = rt_ctx.env_weak_ref.ns

    if is_sel then
        -- FIXME(neovim): If `finish` is set to {lnum, -1}, there’s a bug:
        -- when two adjacent lines are highlighted, clearing the lower one also
        -- clears the upper one. So the `finish` must be set to { lnum + 1, 0 }.
        vim.hl.range(rt_ctx.bufnr, ns.select_id, "OnlysearchSelectedLine",
            { lnum, 0 }, { lnum + 1, 0 }, { inclusive = false })
    else
        vim.api.nvim_buf_clear_namespace(rt_ctx.bufnr, ns.select_id, lnum, lnum + 1)
    end
end

--- draw the raw text(e.g. rg --help)
--- @param rt_ctx table  runtime_ctx
--- @param lnum number
--- @param line string
--- @return number the line number next content should be place at
function _M.render_message(rt_ctx, lnum, line)
    if not rt_ctx.bufnr or not vim.api.nvim_buf_is_loaded(rt_ctx.bufnr) then
        return lnum
    end

    vim.api.nvim_buf_set_lines(rt_ctx.bufnr, lnum, lnum, false, { line })
    return lnum + 1
end

--- draw the error message
--- @param rt_ctx table  runtime_ctx
--- @param lnum number
--- @param line string
--- @return number the line number next content should be place at
function _M.render_error(rt_ctx, lnum, line)
    if not rt_ctx.bufnr or not vim.api.nvim_buf_is_loaded(rt_ctx.bufnr) then
        return lnum
    end
    local ns = rt_ctx.env_weak_ref.ns

    vim.api.nvim_buf_set_lines(rt_ctx.bufnr, lnum, lnum, false, { line })
    vim.hl.range(rt_ctx.bufnr, ns.result_id, "OnlysearchError", { lnum, 0 },
        { lnum, -1 }, { inclusive = false })

    return lnum + 1
end

--- draw the separating mark
--- @param rt_ctx table  runtime_ctx
--- @param is_error boolean
--- @param msg ?string
function _M.render_sep(rt_ctx, is_error, msg)
    if not rt_ctx.bufnr or not vim.api.nvim_buf_is_loaded(rt_ctx.bufnr) then
        return
    end
    local ns = rt_ctx.env_weak_ref.ns

    local sep_str = string.rep('-', 255)
    if is_error then
        sep_str = '--(ERROR)' .. sep_str
    elseif msg then
        sep_str = '--' .. msg .. sep_str
    end

    if rt_ctx.sep_extmark_id then
        vim.api.nvim_buf_del_extmark(rt_ctx.bufnr, ns.result_id,
            rt_ctx.sep_extmark_id)
    end

    rt_ctx.sep_extmark_id = vim.api.nvim_buf_set_extmark(
        rt_ctx.bufnr, ns.result_id, cfg.ui_cfg.header_lines - 1, 0, {
            virt_lines = { { { sep_str, is_error and "OnlysearchSepErr" or "OnlysearchSep" } } },
            virt_lines_leftcol = true,
            virt_lines_above = false,
            right_gravity = false,
        }
    )
end

--- clear the content from `lnum` to the end and remove namespace of result and separating mark
--- @param rt_ctx table  runtime_ctx
function _M.clear_result(rt_ctx)
    if not rt_ctx.bufnr or not vim.api.nvim_buf_is_loaded(rt_ctx.bufnr) then
        return
    end
    local ns = rt_ctx.env_weak_ref.ns

    vim.api.nvim_buf_clear_namespace(rt_ctx.bufnr, ns.result_id, 0, -1)
    vim.api.nvim_buf_clear_namespace(rt_ctx.bufnr, ns.select_id, 0, -1)
    vim.api.nvim_buf_set_lines(rt_ctx.bufnr, cfg.ui_cfg.header_lines, -1, false, {})
end

--- redraw the ui for given query
--- @param rt_ctx table  runtime_ctx
--- @param query Query
function _M.render_query(rt_ctx, query)
    if not rt_ctx.bufnr or not vim.api.nvim_buf_is_loaded(rt_ctx.bufnr) then
        return
    end
    local ns = rt_ctx.env_weak_ref.ns
    _M.clear_result(rt_ctx)

    vim.api.nvim_buf_clear_namespace(rt_ctx.bufnr, ns.header_id, 0, -1)

    -- set query lines
    vim.api.nvim_buf_set_lines(rt_ctx.bufnr, 0, -1, false, {
        query.text or "",
        query.paths or "",
        query.flags or "",
        query.filters or "",
    })

    _M.render_header(rt_ctx)
end

return _M
