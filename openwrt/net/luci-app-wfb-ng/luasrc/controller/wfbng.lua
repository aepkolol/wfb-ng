module("luci.controller.wfbng", package.seeall)

function index()
    if not nixio.fs.access("/etc/wifibroadcast.cfg") then
        return
    end

    local page = entry({"admin", "services", "wfb-ng"}, firstchild(), _("WFB-ng"), 90)
    page.dependent = false

    entry({"admin", "services", "wfb-ng", "config"}, cbi("wfbng"), _("Configuration"), 1)
    entry({"admin", "services", "wfb-ng", "status"}, template("wfbng/status"), _("Status"), 2)
    entry({"admin", "services", "wfb-ng", "logs"}, template("wfbng/logs"), _("Logs"), 3)
    entry({"admin", "services", "wfb-ng", "stats"}, call("action_stats")).leaf = true
    entry({"admin", "services", "wfb-ng", "logdata"}, call("action_logdata")).leaf = true
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function read_config(path)
    local res = {}
    local section
    local fd = io.open(path)
    if not fd then return res end
    for line in fd:lines() do
        line = trim(line)
        if line:sub(1,1) ~= "#" and line ~= "" then
            local sec = line:match("^%[(.+)%]$")
            if sec then
                section = sec
                res[section] = res[section] or {}
            elseif section then
                local k, v = line:match("([^=]+)=(.+)")
                if k and v then
                    res[section][trim(k)] = trim(v)
                end
            end
        end
    end
    fd:close()
    return res
end

function action_stats()
    local http = require "luci.http"
    local nixio = require "nixio"
    local json = require "luci.jsonc"

    local cfg = read_config("/etc/wifibroadcast.cfg")
    local ports = {}
    for s, opts in pairs(cfg) do
        if s:match("^gs%d*") and opts.api_port then
            ports[#ports+1] = tonumber(opts.api_port)
        end
    end
    if #ports == 0 then
        ports = {8103}
    end

    local result = {}
    for _, p in ipairs(ports) do
        local sock = nixio.socket("inet", "stream")
        if sock and sock:connect("127.0.0.1", p) then
            local line = sock:recvline()
            sock:close()
            if line then
                local ok, obj = pcall(json.parse, line)
                if ok and obj then
                    result[tostring(p)] = obj
                end
            end
        end
    end

    if next(result) == nil then
        http.status(204, "no content")
        return
    end

    http.prepare_content("application/json")
    http.write(json.stringify(result))
end

function action_logdata()
    local http = require "luci.http"
    local util = require "luci.util"

    local log = util.exec("logread | tail -n 50")
    http.prepare_content("text/plain")
    http.write(log)
end
