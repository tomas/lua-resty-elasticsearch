local cjson = require "cjson"
local http = require "resty.http"

local es_utils = require "resty.es.utils"
local es_cat = require "resty.es.cat"
local es_cluster = require "resty.es.cluster"
local es_indices = require "resty.es.indices"
local es_nodes = require "resty.es.nodes"
local es_snapshot = require "resty.es.snapshot"

local str_find = string.find
local str_sub = string.sub
local math_random = math.random
local make_path = es_utils.make_path
local get_err_str = es_utils.get_err_str
local deal_params = es_utils.deal_params


local _M = {
    _VERSION = '0.01'
}


local mt = { __index = _M }


function _M.new(self, hosts)
    if not hosts then
        hosts = {'http://localhost:9200'}
    end

    local es = {
        hosts_len = #hosts,
        hosts = hosts,
    }
    es.cat = es_cat:new(es)
    es.cluster = es_cluster:new(es)
    es.indices = es_indices:new(es)
    es.nodes = es_nodes:new(es)
    es.snapshot = es_snapshot:new(es)

    return setmetatable(es, mt)
end


function _M._perform_request(self, http_method, url, params, body)
    local temp_index = math_random(self.hosts_len)
    local full_host = self.hosts[temp_index]
    local http_c = http.new()

    ip_port = string.gsub(full_host, 'http://', '')
    host = ip_port:gsub(":.*", '')
    port = ip_port:gsub(".*:", '')

    -- url = host .. url
    if params then
        url = url .. ngx.encode_args(params)
    end

    local headers = {}
    if body then
        body = cjson.encode(body)
        headers['Content-Type'] = 'application/json'
    else
        body = ''
    end

    http_c:set_timeout(1000)
    http_c:connect(host, port)

    local res, err = http_c:request({
        path = url,
        method = http_method,
        body = body,
        headers = headers
    })

    if not res then
        return nil, err
    end

    if not ((200 <= res.status) and (res.status < 300)) then
        return nil, get_err_str(res.status, res.body)
    end

    local response_body = res:read_body()
    local temp_index, _, _ = str_find(res.headers['content-type'], ';')
    local mimetype = str_sub(res.headers['content-type'], 1, temp_index - 1)
    if mimetype == 'application/json' then
       response_body = cjson.decode(response_body)
    elseif mimetype == 'text/plain' then
        -- do nothing
    else
        return nil, 'Unknown mimetype, unable to deserialize: ' .. mimetype
    end

    local ok, err = http_c:set_keepalive()
    if not ok then
      -- ngx.say("failed to set keepalive: ", err)
      return
    end

    return response_body, ''
end


------------------------------------------------------------------------------
-- Get the basic info from the current cluster.
--
------------------------------------------------------------------------------
function _M.info(self, params)
    local _, query_params = deal_params(s_params)
    local data, err = self:_perform_request('GET', '/', query_params)

    return data, err
end


------------------------------------------------------------------------------
-- Returns True if the cluster is up, False otherwise.
--
------------------------------------------------------------------------------
function _M.ping(self, params)
    local _, query_params = deal_params(s_params)
    local data, err = self:_perform_request('HEAD', '/', query_params)
    if not data then
        return false, err
    end
    return true, ''
end


------------------------------------------------------------------------------
-- Execute a search query and get back search hits that match the query.
--
------------------------------------------------------------------------------

function _M.search(self, s_params)
    local basic_params, query_params = deal_params(s_params, { 'index', 'doc_type', 'body' })

    if basic_params.doc_type and not basic_params.index then
        basic_params.index = '_all'
    end

    local data, err = self:_perform_request(
        'GET', make_path(basic_params.index, basic_params.doc_type, '_search'),
        query_params, basic_params.body
    )

    return data, err
end


------------------------------------------------------------------------------
-- A query that accepts a query template.
--
------------------------------------------------------------------------------
function _M.search_template(self, s_params)
    local basic_params, query_params = deal_params(s_params, { 'index', 'doc_type', 'body' })
    local data, err = self:_perform_request(
        'GET',
        make_path(basic_params.index, basic_params.doc_type, { '_search', 'template' }),
        query_params, basic_params.body
    )

    return data, err
end


function _M.search_shards(self, s_params)
    local basic_params, query_params = deal_params(s_params, { 'index', 'doc_type' })
    local data, err = self:_perform_request(
        'GET', make_path(basic_params.index, basic_params.doc_type, '_search_shards'),
        query_params
    )

    return data, err
end


function _M.explain(self, s_params)
    local basic_params, query_params = deal_params(s_params, { 'index', 'doc_type', 'id', 'body' })
    if not basic_params.index then
        return nil, 'the index parameter is a required argument.'
    end
    if not basic_params.doc_type then
        return nil, 'the doc_type parameter is a required argument.'
    end
    if not basic_params.id then
        return nil, 'the id parameter is a required argument.'
    end

    local data, err = self:_perform_request(
        'GET',
        make_path(basic_params.index, basic_params.doc_type, basic_params.id, '_explain'),
        query_params, basic_params.body
    )

    return data, err
end


function _M.delete(self, s_params)
    local basic_params, query_params = deal_params(s_params, { 'index', 'doc_type', 'id' })
    if not basic_params.index then
        return nil, 'the index parameter is a required argument.'
    end
    if not basic_params.doc_type then
        return nil, 'the doc_type parameter is a required argument.'
    end
    if not basic_params.id then
        return nil, 'the id parameter is a required argument.'
    end

    local data, err = self:_perform_request(
        'DELETE', make_path(basic_params.index, basic_params.doc_type, basic_params.id),
        query_params
    )

    return data, err
end


function _M.count(self, s_params)
    local basic_params, query_params = deal_params(s_params, { 'index', 'doc_type', 'body' })
    if basic_params.doc_type and not basic_params.index then
        basic_params.index = '_all'
    end

    local data, err = self:_perform_request(
        'GET', make_path(basic_params.index, basic_params.doc_type, '_count'),
        query_params, basic_params.body
    )

    return data, err
end


function _M.suggest(self, s_params)
    local basic_params, query_params = deal_params(s_params, { 'index', 'body' })
    if not basic_params.body then
        return nil, 'the body parameter is a required argument.'
    end

    local data, err = self:_perform_request(
        'POST', make_path(basic_params.index, '_suggest'),
        query_params, basic_params.body
    )

    return data, err
end


return _M
