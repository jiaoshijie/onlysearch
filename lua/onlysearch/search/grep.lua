local utils = require('onlysearch.utils')

-- gnu-grep tool
local grep = {}

grep.config = function(user_config)
    local config = vim.tbl_extend('force', {
        mandatory_args = {
            '--color=never',
            '--recursive', -- `-r`
            '-I',  -- `--binary-files=without-match`
            '--line-number', -- `-n`
        },
        args = {},
    }, user_config or {})

    config.cmd = 'grep'
    vim.list_extend(config.args, config.mandatory_args)

    return config
end

grep.parse_output = function(data)
    if grep.is_raw then
        return data
    end
    -- NOTE: if has a filename like `main:12:34:ab.c`, this regexp will fail
    local _, _, p, l, c = string.find(data, [[([^:]+):(%d+):(.*)]])

    l = tonumber(l)
    if l == nil then
        -- Do not deal with `-C number` option
        -- Try to parse -C number content
        if data == "--" then
            return nil
        end
        local _, _, ll = string.find(data, [[[^-]+-(%d+)-.*]])
        ll = tonumber(ll)
        if ll ~= nil then
            return nil
        end

        grep.is_raw = true
        -- Now suppose data is raw content(grep --help)
        return data
    end

    if p == nil then
        return nil
    end

    return { p = p, c = c, l = l }
end

grep.parse_filters = function(args, filters)
    if filters and #filters > 0 then
        filters = utils.scan_paths(filters)
        for _, filter in ipairs(filters) do
            if string.sub(filter, 1, 1) ~= '!' then
                table.insert(args, '--include=' .. filter)
            else
                filter = string.sub(filter, 2)  -- remove '!'
                if string.sub(filter, -1) == '/' then
                    table.insert(args, '--exclude-dir=' .. filter)
                else
                    table.insert(args, '--exclude=' .. filter)
                end
            end
        end
    end
end


---@desc: OVERWRITE `base` on_exit function(used for job on_exit)
function grep:on_exit(_)
    pcall(vim.schedule_wrap(function()
        grep.is_raw = false
        self.handler.on_finish()
    end))
end

return grep
