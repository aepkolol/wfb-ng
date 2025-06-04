module("luci.controller.wfbng", package.seeall)

function index()
    if not nixio.fs.access("/etc/wifibroadcast.cfg") then
        return
    end

    local page = entry({"admin", "services", "wfb-ng"}, firstchild(), _("WFB-ng"), 90)
    page.dependent = false

    entry({"admin", "services", "wfb-ng", "config"}, cbi("wfbng"), _("Configuration"), 1)
    entry({"admin", "services", "wfb-ng", "status"}, template("wfbng/status"), _("Status"), 2)
    entry({"admin", "services", "wfb-ng", "stats"}, call("action_stats")).leaf = true
end

function action_stats()
    local http = require "luci.http"
    local nixio = require "nixio"

    local sock = nixio.socket("inet", "stream")
    if not sock or not sock:connect("127.0.0.1", 8103) then
        http.status(500, "connect failed")
        return
    end
    local line = sock:recvline()
    sock:close()

    if not line then
        http.status(204, "no content")
        return
    end
    http.prepare_content("application/json")
    http.write(line)
end
