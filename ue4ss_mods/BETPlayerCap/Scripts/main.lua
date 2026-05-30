local MOD_NAME = "BETPlayerCap"
local TARGET_CAP = 12

local function log(message)
    print(string.format("[%s] %s\n", MOD_NAME, message))
end

local watch_names = {
    "BETMultiplayerSettingsWidget",
    "UBETMultiplayerSettingsWidget",
    "DefaultMaxPlayers",
    "MinSelectablePlayers",
    "MaxSelectablePlayers",
    "SelectedMaxPlayers",
    "ClampMaxPlayers",
    "IncreaseMaxPlayers",
    "DecreaseMaxPlayers",
    "GetMaxPlayersText",
    "MaxPlayersValueText",
    "CreateGameBaseWidget",
    "PublicConnections",
    "NumPublicConnections",
    "MaxPublicConnections",
    "Session.MaxPlayers",
    "EOS_SessionModification_SetMaxPlayers",
}

local function safe_call(label, fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end

    log(label .. " failed: " .. tostring(result))
    return nil
end

local function try_static_find_object(name)
    if StaticFindObject == nil then
        return nil
    end

    return safe_call("StaticFindObject(" .. name .. ")", function()
        return StaticFindObject(name)
    end)
end

local function try_find_first(name)
    if FindFirstOf == nil then
        return nil
    end

    return safe_call("FindFirstOf(" .. name .. ")", function()
        return FindFirstOf(name)
    end)
end

local function describe_object(name, object)
    if object == nil then
        log("not found: " .. name)
        return
    end

    log("found: " .. name .. " -> " .. tostring(object))

    safe_call("GetFullName(" .. name .. ")", function()
        if object.GetFullName ~= nil then
            log("full name: " .. tostring(object:GetFullName()))
        end
    end)
end

local function probe_name(name)
    describe_object(name .. " via FindFirstOf", try_find_first(name))
    describe_object(name .. " via StaticFindObject", try_static_find_object(name))
end

local function probe_watch_names()
    log("probing runtime names")
    for _, name in ipairs(watch_names) do
        probe_name(name)
    end
end

log("loaded logging/discovery skeleton")
log("target cap: " .. tostring(TARGET_CAP))
log("this pass only probes names; it does not modify game state")

safe_call("ExecuteConsoleCommand net.MaxPlayersOverride", function()
    if ExecuteConsoleCommand ~= nil then
        ExecuteConsoleCommand("net.MaxPlayersOverride " .. tostring(TARGET_CAP))
        log("sent console command: net.MaxPlayersOverride " .. tostring(TARGET_CAP))
    else
        log("ExecuteConsoleCommand unavailable in this UE4SS environment")
    end
end)

probe_watch_names()

if RegisterHook ~= nil then
    for _, function_name in ipairs({"IncreaseMaxPlayers", "DecreaseMaxPlayers", "ClampMaxPlayers"}) do
        safe_call("RegisterHook(" .. function_name .. ")", function()
            RegisterHook(function_name, function(...)
                log("hook hit: " .. function_name)
            end)
            log("registered tentative hook: " .. function_name)
        end)
    end
else
    log("RegisterHook unavailable in this UE4SS environment")
end
