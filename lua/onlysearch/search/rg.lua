local utils = require('onlysearch.utils')

-- ripgrep tool
-- https://github.com/BurntSushi/ripgrep

local rg = {}

rg.config = function(user_config)
    local config = vim.tbl_extend('force', {
        mandatory_args = {
            '--json',
        },
        args = {},
        complete = {}, -- complete flags
        -- NOTE(maybe don't use): invalid flags
    }, user_config or {})

    config.cmd = 'rg'
    vim.list_extend(config.args, config.mandatory_args)

    return config
end

rg.parse_output = function(data)
    local ok, root = pcall(vim.json.decode, data)
    if not ok then -- Maybe flags contain --help --version
        return data
    end
    if root.type == "begin" or root.type == "end"
        or root.type == "summary" or root.type == "context" then
        return nil
    end

    -- root.type == "match"
    local p = root.data.path.text
    local c = vim.fn.trim(root.data.lines.text, '\r\n', 2)  -- remove tralling newline characters
    local l = root.data.line_number

    local subm = {}
    for _, val in ipairs(root.data.submatches) do
        table.insert(subm, { s = val['start'], e = val['end'] })
    end

    return { p = p, c = c, l = l, subm = subm }
end

rg.parse_filters = function(args, filters)
    if filters and #filters > 0 then
        filters = utils.scan_paths(filters)
        for _, filter in ipairs(filters) do
            table.insert(args, '--glob=' .. filter)
        end
    end
end

return rg
