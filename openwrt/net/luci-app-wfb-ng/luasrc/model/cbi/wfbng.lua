local fs = require "nixio.fs"

local cfgfile = "/etc/wifibroadcast.cfg"

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

local function write_config(path, cfg)
    local lines = {}
    for s, opts in pairs(cfg) do
        lines[#lines+1] = "["..s.."]"
        for k,v in pairs(opts) do
            lines[#lines+1] = k .. " = " .. v
        end
        lines[#lines+1] = ""
    end
    fs.writefile(path, table.concat(lines, "\n"))
end

m = SimpleForm("wfbng", "WFB-ng Configuration")
m.reset = false
m.cfg = read_config(cfgfile)

local wifi_channel = m:field(ListValue, "wifi_channel", "WiFi Channel")
wifi_channel.default = m.cfg.common and m.cfg.common.wifi_channel or ""
wifi_channel:value("36", "36 (5GHz)")
wifi_channel:value("40", "40 (5GHz)")
wifi_channel:value("44", "44 (5GHz)")
wifi_channel:value("48", "48 (5GHz)")
wifi_channel:value("149", "149 (5GHz)")
wifi_channel:value("153", "153 (5GHz)")
wifi_channel:value("157", "157 (5GHz)")
wifi_channel:value("161", "161 (5GHz)")
wifi_channel:value("165", "165 (5GHz)")

local wifi_region = m:field(ListValue, "wifi_region", "WiFi Region")
wifi_region.default = m.cfg.common and m.cfg.common.wifi_region or ""

local function load_wifi_regions()
    local regions = {}
    local fd = io.open("/usr/share/wfb-ng/wifi_regions")
    if fd then
        for line in fd:lines() do
            line = trim(line)
            if line ~= "" and line:sub(1,1) ~= "#" then
                regions[#regions+1] = line
            end
        end
        fd:close()
    end
    if #regions == 0 then
        regions = {"US", "EU", "JP", "CN", "BO"}
    end
    return regions
end

for _, r in ipairs(load_wifi_regions()) do
    wifi_region:value(r, r)
end


local gs_mavlink_peer = m:field(Value, "gs_mavlink_peer", "GS Mavlink Peer")
gs_mavlink_peer.default = m.cfg.gs_mavlink and m.cfg.gs_mavlink.peer or ""

local gs_video_peer = m:field(Value, "gs_video_peer", "GS Video Peer")
gs_video_peer.default = m.cfg.gs_video and m.cfg.gs_video.peer or ""

function m.on_commit(self)
    local cfg = read_config(cfgfile)
    cfg.common = cfg.common or {}
    cfg.common.wifi_channel = wifi_channel:formvalue("")
    cfg.common.wifi_region = wifi_region:formvalue("")
    cfg.gs_mavlink = cfg.gs_mavlink or {}
    cfg.gs_mavlink.peer = gs_mavlink_peer:formvalue("")
    cfg.gs_video = cfg.gs_video or {}
    cfg.gs_video.peer = gs_video_peer:formvalue("")
    write_config(cfgfile, cfg)
end

return m
