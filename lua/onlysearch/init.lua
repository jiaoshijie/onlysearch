local _M = {}

_M.setup = function(cfg)
    require('onlysearch.config').setup(cfg)
end

_M.open = function()
    require('onlysearch.runtime').open()
end

_M.close = function()
    require('onlysearch.runtime').close()
end

_M.toggle = function()
    local rt = require('onlysearch.runtime')
    if rt.is_visible_on_cur_tab() then
        rt.close()
    else
        if rt.is_opend() then rt.close() end
        rt.open()
    end
end

return _M
