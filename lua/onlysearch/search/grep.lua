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
    -- NOTE: if has a filename like `main:12:34:ab.c`, this regexp will fail
    local _, _, p, l, c = string.find(data, [[([^:]+):(%d+):(.*)]])

    local ok = false
    ok, l = pcall(tonumber, l)

    -- Do not deal with `-C number` option
    if p == nil or not ok then
        return nil
    end

    return { p = p, c = c, l = l }
end

return grep
