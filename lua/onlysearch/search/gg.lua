-- Just For Fun
-- grip-grab
-- https://github.com/alexpasmantier/grip-grab

local gg = {}

gg.config = function(user_config)
    local config = vim.tbl_extend('force', {
        mandatory_args = {
            '--json',
        },
        args = {},
    }, user_config or {})

    config.cmd = 'gg'
    vim.list_extend(config.args, config.mandatory_args)

    return config
end

---@desc: NOTE: the gg parse_output is different to rg and grep
---@return table
--- table:
--- {
---     p = string,
---     m = {
---         {
---             l = number,
---             c = string,
---             subm = {
---                 s = number,
---                 e = number,
---             }
---         },
---         {
---             ...
---         },
---         ...
---     }
--- }
gg.parse_output = function(data)
    local ok, root = pcall(vim.json.decode, data)
    if not ok then -- Maybe flags contain --help --version
        return data
    end
    local m = {}

    -- root.results should not be empty
    for _, match in ipairs(root.results) do
        local c = vim.fn.trim(match.line, '\r\n', 2)
        local subm = {}
        for _, val in ipairs(match.matches) do
            table.insert(subm, { s = val['start'], e = val['end'] })
        end
        table.insert(m, {
            l = match.line_number,
            c = c,
            subm = subm
        })
    end

    return { p = root.path, m = m }
end

gg.on_stdout = function(self, value)
    pcall(vim.schedule_wrap(function()
        local ts = self.parse_output(value)
        if type(ts) == "table" then
            local t = { p = ts.p }
            for _, val in ipairs(ts.m) do
                self.handler.on_result(vim.tbl_extend('force', t, val))
            end
        elseif type(ts) == "string" then
            self.handler.on_result(value)
        end
    end))
end

return gg
