local utils = require('onlysearch.utils')

local ui = {
    ctx = {
        ns_id = nil,
        sep_extmark_id = nil,
    },
    vt = {
        ns_id = nil,
        header = {
            search = {
                lnum = 0,
                text = "Search:",
                hl = "OnlysearchHeaderSearch",
            },
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

ui.render_header = function(self, bufnr, name)
    if not self.vt.ns_id then
        self.vt.ns_id = vim.api.nvim_create_namespace("onlysearch_vt_ns")
    end
    local buf_line_number = vim.api.nvim_buf_line_count(bufnr)
    local header_number = utils.table_numbers(self.vt.header)
    if buf_line_number < header_number then
        local lines = {}
        for _ = 1, header_number - buf_line_number, 1 do
            table.insert(lines, "")
        end
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
    end

    local header_count = 0
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

ui.render_filename = function(self, bufnr, lnum, line)
    if not self.ctx.ns_id then
        self.ctx.ns_id = vim.api.nvim_create_namespace("onlysearch_ctx_ns")
    end
    vim.api.nvim_buf_set_lines(bufnr, lnum, lnum, false, { "", line })
    lnum = lnum + 1
    vim.api.nvim_buf_add_highlight(bufnr, self.ctx.ns_id, "OnlysearchFilename",
        lnum, 0, vim.api.nvim_strwidth(line))

    return lnum + 1
end

ui.render_match_line = function(self, bufnr, lnum, mlnum, line, subms)
    if not self.ctx.ns_id then
        self.ctx.ns_id = vim.api.nvim_create_namespace("onlysearch_ctx_ns")
    end
    -- NOTE: cut long line to 255 characters
    line = string.sub(line, 0, 255)
    vim.api.nvim_buf_set_lines(bufnr, lnum, lnum, false, { mlnum .. ':' .. line })
    local len = vim.api.nvim_strwidth('' .. mlnum)
    vim.api.nvim_buf_add_highlight(bufnr, self.ctx.ns_id, "OnlysearchMatchLNum",
        lnum, 0, len)
    len = len + 1  -- len(':')
    if subms then
        for _, val in ipairs(subms) do
            vim.api.nvim_buf_add_highlight(bufnr, self.ctx.ns_id, "OnlysearchMatchCtx",
                lnum, len + val.s, len + val.e)
        end
    end
    return lnum + 1
end

ui.render_message = function(self, bufnr, lnum, line)
    if not self.ctx.ns_id then
        self.ctx.ns_id = vim.api.nvim_create_namespace("onlysearch_ctx_ns")
    end
    vim.api.nvim_buf_set_lines(bufnr, lnum, lnum, false, { line })
    return lnum + 1
end

ui.render_error = function(self, bufnr, lnum, line)
    if not self.ctx.ns_id then
        self.ctx.ns_id = vim.api.nvim_create_namespace("onlysearch_ctx_ns")
    end
    vim.api.nvim_buf_set_lines(bufnr, lnum, lnum, false, { line })
    vim.api.nvim_buf_add_highlight(bufnr, self.ctx.ns_id, "OnlysearchError",
        lnum, 0, -1)

    return lnum + 1
end

ui.render_sep = function(self, bufnr, lnum, is_error, ctx)
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

ui.clear_ctx = function(self, bufnr, lnum)
    if self.ctx.ns_id then
        vim.api.nvim_buf_clear_namespace(bufnr, self.ctx.ns_id, 0, -1)
    end
    vim.api.nvim_buf_set_lines(bufnr, lnum, -1, false, {})
end

return ui
