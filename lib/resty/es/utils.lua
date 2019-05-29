local cjson = require "cjson"

local t_insert = table.insert
local t_concat = table.concat
local str_format = string.format
local select = select


local _M = {
    _VERSION = '0.02'
}


function _M.make_path(...)
    local t = {}
    local num_args = select('#', ...)
    for i = 1, num_args do
        local arg = select(i, ...)
        if arg ~= nil and arg ~= '' then
            t_insert(t, arg)
        end
    end
    return '/' .. t_concat(t, '/')
end


local function json_decode(str)
    local json_value = nil
    pcall(function (str) json_value = json.decode(str) end, str)
    return json_value
end


function _M.get_err_str(http_response_code, http_response_data)
    return str_format(
        'Http response code: %s. and es response error info: %s',
        http_response_code, http_response_data
    )
end


-- usage: basic_params, query_params = deal_params(params, { 'foo', 'bar' })
function _M.deal_params(s_params, basic_params_list)
    if s_params == nil then
        return {}, {}
    end

    local basic = {}
    local query = {}

    for _, key in ipairs(basic_params_list or {} ) do
      basic[key] = 1
    end

    for key, val in pairs(s_params) do
      if basic[key] then
        basic[key] = val
      else
        query[key] = val
      end
    end

    return basic, query
end



return _M
