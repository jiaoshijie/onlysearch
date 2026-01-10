local _M = {}

-- NOTE: `grep` refers to gnu_grep

_M.buf_name = "[OnlySearch]"

_M.common = {
    engine = "rg",
    search_leave_insert = true,
    keyword = "48-57,-,a-z,A-Z,.,_,=",
    handle_sys_clipboard_paste = true,
}

_M.ui_cfg = {
    sep_extmark_lnum = 3,  -- 0-based index
    header_lines = 4,  -- TODO: maybe it should not be here
    header = {
        search_path = {
            lnum = 1,  -- 0-based index
            text = " Search Path: ",
            hl = "OnlysearchHeaderPaths",
        },
        extra_flags = {
            lnum = 2,
            text = " Flags(%s): ",
            hl = "OnlysearchHeaderFlags",
            fmt = true,
        },
        filters = {
            lnum = 3,
            text = " Filters: ",
            hl = "OnlysearchHeaderFilters",
        }
    }
}

_M.keymaps_cfg = {
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
}

_M.engines_cfg = {
    rg = {
        args = nil,
        complete = nil,
    },
    grep = {
        args = nil,
        complete = nil,
    },
}

--- @param cfg table { common = {}, engine = {}, keymaps = {} }
_M.setup = function(cfg)
    _M.common = vim.tbl_extend('force', _M.common, cfg.common or {})
    _M.keymaps_cfg = vim.tbl_extend('force', _M.keymaps_cfg, cfg.keymaps or {})
    _M.engines_cfg[_M.common.engine] = cfg.engine or {}
end

return _M
