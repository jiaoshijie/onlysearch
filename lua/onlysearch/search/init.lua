local utils = require('onlysearch.utils')
local task = require('onlysearch.task')

--- @class CompleteCtx
--- @field word string  `:h complete-items`
--- @field kind string

--- @class EngineCfg
--- @field cmd string  only used internally, user should not using this item
--- @field mandatory_args string[]  only used internally, user should not using this item
--- @field args string[]  user custom default search config
--- @field complete CompleteCtx[]  user defined complete flags for easy using

--- base class for searching
--- @class SearchInterface
--- @field task ?Task
--- @field not_first_error ?boolean
--- @field config EngineCfg
--- @field handler Handler
--- method
--- @field parse_output function
--- @field parse_filters function
--- @field search function
--- @field stop function
--- @field on_stdout function
--- @field on_stderr function
--- @field on_exit function
local base = {
    task = nil,
    not_first_error = nil,
}
base.__index = base

--- @class MatchRange
--- @field s number the start position of matched item(zero-based)
--- @field e number the end postion of matched item(excluded)

--- @class MatchedItem
--- @field p string the file path of matched item
--- @field c string the line content of matched item
--- @field l number the line number of matched item in the file
--- @field subm ?MatchRange[]

--- extract the search tool output to standard format
---        this function should be implemented by all the child class
--- @param data string the raw output of external search tool
--- @return MatchedItem | string | nil
--- @diagnostic disable-next-line: unused-local
base.parse_output = function(data)
    -- NOTE: finders implement their own parse_output
    return nil
end

--- @param args string[]
--- @param filters string separated by space
--- @diagnostic disable-next-line: unused-local
base.parse_filters = function(args, filters)
    print("WARNING: filters not supported, will search without filters")
end

--- Start a search task
---@param query Query
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

    self.task = task:new({
        command = self.config.cmd,
        args = args,
        on_stdout = function(id, data) self:on_stdout(id, data) end,
        on_stderr = function(id, data) self:on_stderr(id, data) end,
        on_exit = function(id) self:on_exit(id) end,
    })
    self.task:start()
end

--- Stop a not finished search task, called when:
---   1. new search task are coming
---   2. the onlysearch window closed
function base:stop()
    if self.task ~= nil and not self.task.is_shutdown then
        self.task:shutdown(true)
    end
    self.task = nil
    self.not_first_error = false
end

--- @param task_obj Task
--- @param id number
--- @return boolean
local is_task_invalid = function(task_obj, id)
    return task_obj == nil or type(id) ~= "number" or task_obj.id ~= id
end

--- used for task on_stdout
--- @param values string[]
function base:on_stdout(id, values)
    pcall(vim.schedule_wrap(function()
        if is_task_invalid(self.task, id) then return end
        for _, value in ipairs(values) do
            local t = self.parse_output(value)
            self.handler.on_result(t)
        end
    end))
end

--- used for task on_stderr
--- @param values string[]
function base:on_stderr(id, values)
    pcall(vim.schedule_wrap(function()
        if is_task_invalid(self.task, id) then return end
        for _, value in ipairs(values) do
            if not self.not_first_error then
                self.not_first_error = true
                self.handler.on_error({ "", self.task.cfg.command .. ' ' .. table.concat(self.task.cfg.args, ' '), "", value })
            else
                self.handler.on_error(value)
            end
        end
    end))
end

--- used for task on_exit
function base:on_exit(id)
    pcall(vim.schedule_wrap(function()
        if is_task_invalid(self.task, id) then return end
        self.handler.on_finish()
    end))
end

--- construct a finder instance
--- @param engine string finder engine for communicate with external search tools
--- @param engine_config EngineCfg
--- @param handler Handler
local construct_finder = function(engine, engine_config, handler)
    assert(handler ~= nil, "handler must not be empty")

    local ok, finder = pcall(require, "onlysearch.search." .. engine)
    if not ok then
        print("onlysearch: " .. engine .. " not supported, using grep search instead")
        finder = require("onlysearch.search.grep")  -- TODO: maybe just quit, ui render need after this init
    end

    finder.config = finder.setup(engine_config)
    finder.handler = handler

    finder.__index = vim.tbl_extend('force', base, finder)

    return setmetatable(finder, finder)
end

return construct_finder
