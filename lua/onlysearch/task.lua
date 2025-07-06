local utils = require('onlysearch.utils')
local uv = vim.uv

local task_id = 0

--- @class TaskCtx
--- @field stdout ?uv_pipe_t
--- @field stderr ?uv_pipe_t
--- @field shutdown_check ?uv_check_t
--- @field handle ?uv_process_t
--- @field pid ?number

--- @class TaskCfg
--- @field command string
--- @field args string[]
--- @field on_stdout fun(id: number, data: string[])
--- @field on_stderr fun(id: number, data: string[])
--- @field on_exit fun(id: number)

--- @class Task
--- @field id number
--- @field ctx ?TaskCtx
--- @field cfg TaskCfg
--- @field is_start boolean
--- @field is_shutdown boolean
--- @field stdout_last_chunk ?string
--- @field stderr_last_chunk ?string
local task = {}
task.__index = task

--- @param handle uv_pipe_t | uv_process_t | uv_check_t
local close_handle = function(handle)
    if handle and not handle:is_closing() then
        handle:close()
    end
end

--- @param ctx TaskCtx
local close_handles = function(ctx)
    close_handle(ctx.stdout)
    ctx.stdout = nil
    close_handle(ctx.stderr)
    ctx.stderr = nil
    close_handle(ctx.handle)
    ctx.handle = nil
end

--- @param ctx TaskCtx
--- @return boolean
local is_handles_closed = function(ctx)
    if ctx.stdout and not ctx.stdout:is_closing() then
        return false
    end

    if ctx.stderr and not ctx.stderr:is_closing() then
        return false
    end

    return true
end

--- @param cfg TaskCfg
function task:new(cfg)
    local obj = {}

    local ok, is_exe = pcall(vim.fn.executable, cfg.command)
    if not ok or 1 ~= is_exe then
        error(cfg.command .. ": Executable not found")
    end

    obj.is_start = false
    obj.is_shutdown = false
    obj.cfg = cfg  -- NOTE: weak reference is ok

    return setmetatable(obj, task)
end

function task:start()
    if self.is_start then
        utils.echo_info_msg(
            string.format("INFO: Task(%s) already started", self.cfg.command))
        return
    end

    if self.ctx then
        close_handles(self.ctx)
    end
    self.id = task_id
    task_id = task_id + 1
    self.ctx = {}
    self.is_start = true

    self.ctx.stdout = uv.new_pipe(false)
    self.ctx.stderr = uv.new_pipe(false)
    self.ctx.shutdown_check = uv.new_check()

    self.ctx.handle, self.ctx.pid = uv.spawn(
        self.cfg.command, {
            stdio = { nil, self.ctx.stdout, self.ctx.stderr },
            args = self.cfg.args,
            cwd = vim.fn.getcwd(),
        }, vim.schedule_wrap(function(code, signal)
            if code ~= 0 or signal ~= 0 then
                utils.echo_info_msg(
                    string.format("INFO: Task(%s) exited with code %d and signal %d",
                    self.cfg.command, code, signal))
            end

            self:gracefully_shutdown()
        end))

    self.ctx.stdout:read_start(vim.schedule_wrap(function(err, data)
        if self.is_shutdown then
            return
        end

        if err then
            utils.echo_err_msg(
                string.format("ERROR: Task(%s) reading from stdout",
                self.cfg.command))
        elseif data then
            self:process_output(data, true, self.cfg.on_stdout)
        else
            -- Encounter EOF
            if self.stdout_last_chunk then
                self.cfg.on_stdout(self.id, { self.stdout_last_chunk })
            end
            close_handle(self.ctx.stdout)
        end
    end))

    self.ctx.stderr:read_start(vim.schedule_wrap(function(err, data)
        if self.is_shutdown then
            return
        end

        if err then
            utils.echo_err_msg(
                string.format("ERROR: Task(%s) reading from stderr",
                self.cfg.command))
        elseif data then
            self:process_output(data, false, self.cfg.on_stderr)
        else
            -- Encounter EOF
            if self.stderr_last_chunk then
                self.cfg.on_stderr(self.id, { self.stderr_last_chunk })
            end
            close_handle(self.ctx.stderr)
        end
    end))

end

--- @param raw_data string
--- @param is_stdout boolean
--- @param cb fun(id: number, data: string[])
function task:process_output(raw_data, is_stdout, cb)
    raw_data = raw_data:gsub("\r", "")
    local data, remained_chunk = utils.split_last_chunk(raw_data)
    local last_chunk = is_stdout and self.stdout_last_chunk or self.stderr_last_chunk
    if data then
        if last_chunk then
            data = last_chunk .. data
        end
        cb(self.id, vim.fn.split(data, '\n'))
        last_chunk = remained_chunk
    else
        if remained_chunk then
            last_chunk = last_chunk .. remained_chunk
        end
    end

    if is_stdout then
        self.stdout_last_chunk = last_chunk
    else
        self.stderr_last_chunk = last_chunk
    end
end

--- @param abort boolean
function task:shutdown(abort)
    if self.is_shutdown then
        return
    end

    self.is_shutdown = true

    if abort and self.ctx.handle then
      self.ctx.handle:kill(vim.uv.constants.SIGTERM)
    end

    if self.cfg.on_exit then
        vim.schedule(function() self.cfg.on_exit(self.id) end)
    end

    self.ctx.stdout:read_stop()
    self.ctx.stderr:read_stop()
    self.stdout_last_chunk = nil
    self.stderr_last_chunk = nil

    if abort then
        uv.check_stop(self.ctx.shutdown_check)
        close_handle(self.ctx.shutdown_check)
        self.ctx.shutdown_check = nil
    end

    close_handles(self.ctx)

    self.ctx = nil
end

function task:gracefully_shutdown()
    if not self.ctx then return end

    uv.check_start(self.ctx.shutdown_check, function()
        if not is_handles_closed(self.ctx) then
            return
        end

        -- Wait until all the pipes are closing.
        uv.check_stop(self.ctx.shutdown_check)
        close_handle(self.ctx.shutdown_check)
        self.ctx.shutdown_check = nil

        self:shutdown(false)
    end)
end

return task
