local utils = require('onlysearch.utils')

--- @class HeaderInfo
--- @field lnum number
--- @field text string  the text to be displayed
--- @field hl string  the highlight group name

--- @class Headers
--- @field search_path HeaderInfo
--- @field extra_flags HeaderInfo
--- @field filters HeaderInfo

--- @class VirtualTextCtx
--- @field ns_id ?number
--- @field header Headers

--- @class UiCtx
--- @field ns_id ?number
--- @field sel_ns_id ?number
--- @field sep_extmark_id ?number namespace id for separating mark that separate header and results

--- @class Ui
--- @field ctx UiCtx
--- @field vt VirtualTextCtx
local ui = {
    ctx = {
        ns_id = nil,
        sel_ns_id = nil,
        sep_extmark_id = nil,
    },
    vt = {
        ns_id = nil,
        header = {
            search_path = {
                lnum = 1,
                text = "Search Path:",
                hl = "OnlysearchHeaderPaths",
            },
            extra_flags = {
                lnum = 2,
                text = "Extra Flags:",
                hl = "OnlysearchHeaderFlags",
            },
            filters = {
                lnum = 3,
                text = "Filters:",
                hl = "OnlysearchHeaderFilters",
            }
        }
    }
}

--- draw the virtual headers
--- @param bufnr number
--- @param name string used for showing the search engine in the `extra_flags` virtual line
--- @return number the number of headers being drawn
function ui:render_header(bufnr, name)
    if not self.vt.ns_id then
        self.vt.ns_id = vim.api.nvim_create_namespace("onlysearch_vt_ns")
    end
    local buf_line_number = vim.api.nvim_buf_line_count(bufnr)
    local header_number = utils.table_numbers(self.vt.header) + 1  -- 1: search line
    if buf_line_number < header_number then
        local lines = {}
        for _ = 1, header_number - buf_line_number, 1 do
            table.insert(lines, "")
        end
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
    end

    local header_count = 1  -- 1: search line
    for _, v in pairs(self.vt.header) do
        header_count = header_count + 1
        if v.lnum == 2 and name then  -- NOTE: `extra flags` virtual text line number
            v.text = "Extra Flags(" .. name .. "):"
        end
        vim.api.nvim_buf_set_extmark(bufnr, self.vt.ns_id, v.lnum, 0, {
            virt_lines = { { { v.text, v.hl } } },
            virt_lines_leftcol = true,
            virt_lines_above = true,
            right_gravity = false,
        })
    end

    return header_count
end

--- render the file name of the result
--- @param bufnr number
--- @param lnum number the line number which the filename should be place at
--- @param line string the filename string
--- @return number the line number next content should be place at
function ui:render_filename(bufnr, lnum, line)
    if not self.ctx.ns_id then
        self.ctx.ns_id = vim.api.nvim_create_namespace("onlysearch_ctx_ns")
    end
    vim.api.nvim_buf_set_lines(bufnr, lnum, lnum, false, { "", line })
    lnum = lnum + 1
    vim.hl.range(bufnr, self.ctx.ns_id, "OnlysearchFilename", { lnum, 0 },
        { lnum, vim.api.nvim_strwidth(line) }, { inclusive = false })

    return lnum + 1
end

--- render matched line of the result
--- @param bufnr number
--- @param lnum number the line number which the filename should be place at
--- @param mlnum number the line number of the match item in the file
--- @param line string
--- @param subms ?MatchRange[]
--- @return number the line number next content should be place at
function ui:render_match_line(bufnr, lnum, mlnum, line, subms)
    if not self.ctx.ns_id then
        self.ctx.ns_id = vim.api.nvim_create_namespace("onlysearch_ctx_ns")
    end
    -- NOTE: cut long line to 255 characters
    line = string.sub(line, 0, 255)
    vim.api.nvim_buf_set_lines(bufnr, lnum, lnum, false, { mlnum .. ':' .. line })
    local len = vim.api.nvim_strwidth('' .. mlnum)

    vim.hl.range(bufnr, self.ctx.ns_id, "OnlysearchMatchLNum", { lnum, 0 },
        { lnum, len }, { inclusive = false })
    len = len + 1  -- len(':')

    if subms then
        for _, val in ipairs(subms) do
            if len + val.s < 255 and len + val.e < 255 then
                vim.hl.range(bufnr, self.ctx.ns_id, "OnlysearchMatchCtx",
                    { lnum, len + val.s }, { lnum, len + val.e }, { inclusive = false })
            end
        end
    end
    return lnum + 1
end

--- draw the selected highlight or clear the selected highlight
--- @param bufnr number
--- @param lnum number the line number that selected or unseleted
--- @param is_sel boolean is select or not
function ui:toggle_sel_line(bufnr, lnum, is_sel)
    if not self.ctx.sel_ns_id then
        self.ctx.sel_ns_id = vim.api.nvim_create_namespace("onlysearch_ctx_sel_ns")
    end
    if is_sel then
        -- FIXME(neovim): If `finish` is set to {lnum, -1}, there’s a bug:
        -- when two adjacent lines are highlighted, clearing the lower one also
        -- clears the upper one. So the `finish` must be set to { lnum + 1, 0 }.
        vim.hl.range(bufnr, self.ctx.sel_ns_id, "OnlysearchSelectedLine",
            { lnum, 0 }, { lnum + 1, 0 }, { inclusive = false })
    else
        vim.api.nvim_buf_clear_namespace(bufnr, self.ctx.sel_ns_id, lnum, lnum + 1)
    end
end

--- draw the raw text(e.g. rg --help)
--- @param bufnr number
--- @param lnum number
--- @param line string
--- @return number the line number next content should be place at
function ui:render_message(bufnr, lnum, line)
    if not self.ctx.ns_id then
        self.ctx.ns_id = vim.api.nvim_create_namespace("onlysearch_ctx_ns")
    end
    vim.api.nvim_buf_set_lines(bufnr, lnum, lnum, false, { line })
    return lnum + 1
end

--- draw the error message
--- @param bufnr number
--- @param lnum number
--- @param line string
--- @return number the line number next content should be place at
function ui:render_error(bufnr, lnum, line)
    if not self.ctx.ns_id then
        self.ctx.ns_id = vim.api.nvim_create_namespace("onlysearch_ctx_ns")
    end
    vim.api.nvim_buf_set_lines(bufnr, lnum, lnum, false, { line })
    vim.hl.range(bufnr, self.ctx.ns_id, "OnlysearchError", { lnum, 0 },
        { lnum, -1 }, { inclusive = false })

    return lnum + 1
end

--- draw the separating mark
--- @param bufnr number
--- @param lnum number
--- @param is_error boolean
--- @param ctx ?string
function ui:render_sep(bufnr, lnum, is_error, ctx)
    if not self.ctx.ns_id then
        self.ctx.ns_id = vim.api.nvim_create_namespace("onlysearch_ctx_ns")
    end
    local sep_str = string.rep('-', 255)
    if is_error then
        sep_str = '--(ERROR)' .. sep_str
    elseif ctx then
        sep_str = '--' .. ctx .. sep_str
    end

    if self.ctx.sep_extmark_id then
        vim.api.nvim_buf_del_extmark(bufnr, self.ctx.ns_id, self.ctx.sep_extmark_id)
    end

    self.ctx.sep_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, self.ctx.ns_id, lnum, 0, {
        virt_lines = { { { sep_str, is_error and "OnlysearchSepErr" or "OnlysearchSep" } } },
        virt_lines_leftcol = true,
        virt_lines_above = false,
        right_gravity = false,
    })
end

--- clear the content from `lnum` to the end and remove namespace of result and separating mark
--- @param bufnr number
--- @param lnum number
function ui:clear_ctx(bufnr, lnum)
    if self.ctx.ns_id then
        vim.api.nvim_buf_clear_namespace(bufnr, self.ctx.ns_id, 0, -1)
    end
    if self.ctx.sel_ns_id then
        vim.api.nvim_buf_clear_namespace(bufnr, self.ctx.sel_ns_id, 0, -1)
    end
    vim.api.nvim_buf_set_lines(bufnr, lnum, -1, false, {})
end

--- redraw the ui for last query
--- @param bufnr number
--- @param name string the used engine name(e.g. rg, grep)
--- @param query Query
function ui:resume_query(bufnr, name, query)
    -- clear buffer
    self:clear_ctx(bufnr, 0)
    if self.vt.ns_id then
        vim.api.nvim_buf_clear_namespace(bufnr, self.vt.ns_id, 0, -1)
    end

    -- set query lines
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        query.text,
        query.paths,
        query.flags,
        query.filters,
    })

    self:render_header(bufnr, name)
end

return ui
