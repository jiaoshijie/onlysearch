local job = require('plenary.job')
local utils = require('onlysearch.utils')

---@interface
local _M = {}
local base = {
    job = nil,
    not_first_error = nil,
}
base.__index = base

---@desc: extract the search tool output to standard format
---       this function should be implemented by all the child class
---@return table
--- table:
--- {
---     p = string,
---     c = string,
---     l = number,
---     subm = {
---         {
---             s = number,
---             e = number
---         }
---     }
--- }
-- base.parse_output = function(self)
--     -- NOTE: finders implement their own parse_output
-- end

base.parse_filters = function(_, _)
    vim.api.nvim_out_write("WARNING: filters not supported, will search without filters\n")
end

---@desc: Start a search job
---@param query table { text="", paths="", flags="", filters="", cwd="" }
function base:search(query)
    local args = vim.deepcopy(self.config.args)

    -- 1. add flags
    if query.flags and #query.flags > 0 then
        for flag in vim.gsplit(query.flags, ' ') do
            if #flag > 0 then table.insert(args, flag) end
        end
    end
    -- 2. add filter
    if query.filters and #query.filters > 0 then
        self.parse_filters(args, query.filters)
    end

    table.insert(args, "--")
    -- 3. add query text
    table.insert(args, query.text)
    -- 4. add path
    if query.paths and #query.paths > 0 then
        local paths = utils.scan_paths(query.paths)
        for _, dir in ipairs(paths) do
            table.insert(args, dir)
        end
    else
        table.insert(args, '.')
    end
    self:stop()  -- try to stop previous search if have and not yet finished

    self.handler.on_start()
    self.job = job:new({
        enable_recording = true,
        command = self.config.cmd,
        args = args,
        cwd = query.cwd,
        on_stdout = function(_, data) self:on_stdout(data) end,
        on_stderr = function(_, data) self:on_stderr(data) end,
        on_exit = function(_, data) self:on_exit(data) end,
    })
    self.job:sync()
end

---@desc: Stop a not finished search job:
---       1. new search job are coming
---       2. the onlysearch window closed
function base:stop()
    if self.job ~= nil and self.job.is_shutdown == nil then
        self.job:shutdown()
    end
    self.job = nil
    self.not_first_error = false
end

---@desc: used for job on_stdout
function base:on_stdout(value)
    pcall(vim.schedule_wrap(function()
        local t = self.parse_output(value)
        self.handler.on_result(t)
    end))
end

---@desc: used for job on_stderr
function base:on_stderr(value)
    pcall(vim.schedule_wrap(function()
        if not self.not_first_error then
            self.not_first_error = true
            value = { "", self.job.command .. ' ' .. table.concat(self.job.args, ' '), "", value }
        end
        self.handler.on_error(value)
    end))
end

---@desc: used for job on_exit
function base:on_exit(_)
    pcall(vim.schedule_wrap(function()
        self.handler.on_finish()
    end))
end

function base:setup(child)
    local finder_generator = {}
    finder_generator.__index = finder_generator

    ---@param handler table { on_start, on_result, on_error, on_finish }
    function finder_generator:new(config, handler)
        assert(handler ~= nil, "handler must not be empty")
        local finder = {
            config = child.config(config),
            handler = handler,
        }

        local meta = {}
        meta.__index = vim.tbl_extend('force', base, child)
        return setmetatable(finder, meta)
    end

    return finder_generator
end

_M.setup = function(key)
    local ok, finder = pcall(require, "onlysearch.search." .. key)
    if not ok then
        print("onlysearch: " .. key .. " not supported, using grep search instead")
        finder = require("onlysearch.search.grep")  -- TODO: maybe just quit, ui render need after this init
    end
    -- finder.name = key

    return base:setup(finder)
end

return _M
