local _M = {}

_M.setup = function(cfg)
    require('onlysearch.config').setup(cfg)
end

_M.open = function(open_cmd, query)
    require('onlysearch.runtime').open(open_cmd, query)
end

_M.close = function()
    require('onlysearch.runtime').close()
end

_M.toggle = function(open_cmd, query)
    local rt = require('onlysearch.runtime')
    if rt.is_visible_on_cur_tab() then
        rt.close()
    else
        if rt.is_opend() then rt.close() end
        rt.open(open_cmd, query)
    end
end

return _M
