local MOD_NAME = "BETPlayerCap"
-- =====================  USER CONFIG (edit these)  =====================
-- TARGET_CAP: the lobby/session player cap the host can select in the menu.
--   Set to 16 — live-tested as the maximum that can still create a lobby. 17+
--   causes session-creation failure (EOS-level limit). The objective/generator
--   caps below are unchanged.
local TARGET_CAP = 16
-- OBJECTIVE_CAP: cap for player-presence pass gates (e.g. elevator "players needed").
local OBJECTIVE_CAP = 6
-- GENERATOR_CAP / GENERIC_OBJECTIVE_CAP: cap for player-scaled objective counts
--   (Level 1 generators, repairs, fuses, coins, doors, FUN tickets, and any
--   objective the game marks bScalesWithPlayers).
local GENERATOR_CAP = 10
local GENERIC_OBJECTIVE_CAP = 10
-- ALL_PLAYERS_GATE_CAP: when there are more than this many possessed players, force
--   bRequiresAllPlayers = false on teleporters (AInteractableTeleporter) and level
--   exits (ALevelExitBase), so a 7–16 player group is not blocked by geometry that
--   was built for ≤6.
local ALL_PLAYERS_GATE_CAP = 6
-- SUPPLY_BASE_PLAYERS: when there are more players than this, confirmed supply
--   fields are multiplied by possessed_players / SUPPLY_BASE_PLAYERS. This only
--   increases resource/supply counts; it never caps them down.
local SUPPLY_BASE_PLAYERS = 6
local ENABLE_SUPPLY_SCALING = true
-- ======================================================================
local VERSION = "2.19.3-summon-money-hotfix"

-- Feature toggles. Ctrl+K/L level switch is a normal user feature (kept ON).
-- ENABLE_PERIODIC_DIAG stays OFF for release (pure diagnostics / log spam).
local ENABLE_LEVEL_TEST_KEYS = true     -- Ctrl+K/L prev/next level
local ENABLE_PERIODIC_DIAG   = false    -- 30s player-position diagnostics after spawn fix
local ENABLE_OBJECTIVE_CAP   = true     -- keep player-scaled pass requirements at <= OBJECTIVE_CAP

-- UEHelpers ships with UE4SS (Mods/shared/UEHelpers). Used for host-pawn
-- resolution and GameState-based player enumeration (level-independent).
local UEHelpers = nil
pcall(function() UEHelpers = require("UEHelpers") end)


local function log(msg)
    print(string.format("[%s] %s", MOD_NAME, msg))
end

local function safe(label, fn)
    local ok, result = pcall(fn)
    if not ok then
        local err = tostring(result)
        if not string.find(err, "nullptr") then
            log(label .. " error: " .. err)
        end
        return nil
    end
    return result
end

---------------------------------------------------------------------------
-- CDO FILTERING
-- FindFirstOf/FindAllOf return Class Default Objects (CDOs) named
-- "Default__<Class>", which exist in memory even in the lobby. Accepting
-- them caused false "level detected" reports. Reject by name + IsValid.
---------------------------------------------------------------------------
local function is_real_instance(obj)
    if not obj then return false end
    local valid = safe("IsValid", function() return obj:IsValid() end)
    if not valid then return false end
    local full = safe("FullName", function() return obj:GetFullName() end)
    if not full then return false end
    -- plain (non-pattern) substring search; rejects CDOs and archetype templates
    if string.find(tostring(full), "Default__", 1, true) then return false end
    return true
end

-- Like FindFirstOf but skips CDOs/archetypes; returns first LIVE instance or nil.
local function find_first_instance(class_name)
    local list = safe("FindAll_" .. class_name, function()
        return FindAllOf(class_name)
    end)
    if not list then return nil end
    for _, obj in pairs(list) do
        if is_real_instance(obj) then return obj end
    end
    return nil
end

-- Robust "am I actually in a gameplay level?" check. Uses ONLY the gameplay-
-- specific GameMode class (never the generic GameModeBase/Character fallbacks,
-- which have real instances in the lobby). Secondary signal: a Survivor pawn
-- that is actually possessed (has a Controller) -- impossible in the lobby.
local GAMEPLAY_GAMEMODE_CLASSES = {"BP_Level0GameMode_C", "BETGameMode"}
local HOST_GAMEMODE_CLASSES = {
    "BP_LobbyGameMode_C", "LobbyGameMode", "BP_Level0GameMode_C", "BP_Level1_GameMode_C",
    "BP_Level2GameMode_C", "BP_Level3GameMode_C", "BP_Level4GameMode_C", "BP_Level6GameMode_C",
    "BP_Level37GameMode_C", "BP_Level232GameMode_C", "BP_LevelFUNGameMode_C",
    "BP_LevelRunGameMode_C", "BP_LevelHubGameMode_C", "BP_LevelNeg1GameMode_C",
    "BETGameMode", "GameModeBase",
}
local function is_host_authority()
    -- In Unreal networking, only the server/listen-host owns a live GameMode.
    -- Clients may have GameState/PlayerController but not GameMode. find_first_instance
    -- is CDO-safe, so Default__GameModeBase does not produce a false host signal.
    for _, name in ipairs(HOST_GAMEMODE_CLASSES) do
        if find_first_instance(name) then return true end
    end
    return false
end
local function require_host(action)
    if is_host_authority() then return true end
    log("[HOST] " .. action .. " ignored: this mod's host tools only work on the listen-server host")
    return false
end
local function in_gameplay_level()
    for _, name in ipairs(GAMEPLAY_GAMEMODE_CLASSES) do
        if find_first_instance(name) then return true, name end
    end
    local char = find_first_instance("BP_Survivor_Character_C")
    if char then
        local ctrl = safe("CharCtrl", function()
            local c = char.Controller
            if c and c:IsValid() then return c end
            return nil
        end)
        if ctrl then return true, "BP_Survivor_Character_C(possessed)" end
    end
    return false, nil
end

-- Try multiple methods to get actor position (GetActorLocation fails on this build)
local pos_method = nil
local function get_actor_pos(actor, label)
    -- Method 1: GetActorLocation (standard UE API)
    if pos_method == nil or pos_method == 1 then
        local loc = safe(label .. "_GAL", function()
            return actor:GetActorLocation()
        end)
        if loc and loc.Z then
            if pos_method == nil then
                pos_method = 1
                log("[ADAPT] Position method: GetActorLocation")
            end
            return loc
        end
    end

    -- Method 2: K2_GetActorLocation (Blueprint-exposed variant)
    if pos_method == nil or pos_method == 2 then
        local loc = safe(label .. "_K2GAL", function()
            return actor:K2_GetActorLocation()
        end)
        if loc and loc.Z then
            if pos_method == nil then
                pos_method = 2
                log("[ADAPT] Position method: K2_GetActorLocation")
            end
            return loc
        end
    end

    -- Method 3: RootComponent.RelativeLocation property access
    if pos_method == nil or pos_method == 3 then
        local loc = safe(label .. "_RC", function()
            local rc = actor.RootComponent
            if rc then
                local rl = rc.RelativeLocation
                if rl and rl.Z then return rl end
            end
            return nil
        end)
        if loc and loc.Z then
            if pos_method == nil then
                pos_method = 3
                log("[ADAPT] Position method: RootComponent.RelativeLocation")
            end
            return loc
        end
    end

    -- Method 4: Direct property access on common location fields
    if pos_method == nil or pos_method == 4 then
        local loc = safe(label .. "_DP", function()
            local rc = actor.RootComponent
            if rc then
                local x = rc.X or rc.x
                local y = rc.Y or rc.y
                local z = rc.Z or rc.z
                if z then return {X = x or 0, Y = y or 0, Z = z} end
            end
            return nil
        end)
        if loc and loc.Z then
            if pos_method == nil then
                pos_method = 4
                log("[ADAPT] Position method: RootComponent.X/Y/Z")
            end
            return loc
        end
    end

    -- Method 5: Try GetTransform
    if pos_method == nil or pos_method == 5 then
        local loc = safe(label .. "_GT", function()
            local t = actor:GetTransform()
            if t and t.Translation then
                return t.Translation
            end
            return nil
        end)
        if loc and loc.Z then
            if pos_method == nil then
                pos_method = 5
                log("[ADAPT] Position method: GetTransform().Translation")
            end
            return loc
        end
    end

    return nil
end

-- Best-effort player display name for a Survivor character, so diagnostics can
-- say WHO is on the wrong floor. Walks Character -> Controller -> PlayerState.
local function get_player_name(char, label)
    return safe(label .. "_name", function()
        local ctrl = char.Controller
        if not ctrl or not ctrl:IsValid() then return nil end
        local ps = ctrl.PlayerState
        if not ps or not ps:IsValid() then return nil end
        -- PlayerName is an FString/FName property on APlayerState
        local n = ps.PlayerNamePrivate or ps.PlayerName
        if n == nil then return nil end
        local s = tostring(n)
        if s == "" then return nil end
        return s
    end)
end

log("v" .. VERSION .. " loaded - target cap: " .. TARGET_CAP .. ", objective cap: " .. OBJECTIVE_CAP .. ", generator cap: " .. GENERATOR_CAP)

---------------------------------------------------------------------------
-- ADAPTIVE CLASS DETECTION
-- Try exact names first, fall back to parent classes if game updates
---------------------------------------------------------------------------
local CLASS_NAMES = {
    widget = {"BETMultiplayerSettingsWidget"},
    gamemode = {"BP_Level0GameMode_C", "BETGameMode", "GameModeBase"},
}

local resolved_classes = {}

local function resolve_class(key)
    if resolved_classes[key] then return resolved_classes[key] end
    for _, name in ipairs(CLASS_NAMES[key]) do
        local obj = find_first_instance(name)
        if obj then
            resolved_classes[key] = name
            log("[ADAPT] Resolved " .. key .. " -> " .. name)
            return name
        end
    end
    return CLASS_NAMES[key][1]
end

---------------------------------------------------------------------------
-- WIDGET OVERRIDE (player cap)
--
-- v2.16.2: a 2026-06-03 game update changed the multiplayer settings menu so a
-- one-time/5s write to MaxSelectablePlayers was being clamped back to the game's
-- own range (hosts saw max 6 / default 4). The widget class + fields are byte-name
-- identical in the new exe (verified by string scan), so this is a TIMING/CLAMP
-- change, not a signature break. Fix: keep widening MaxSelectablePlayers, and also
-- re-assert it right AFTER the widget's own InitializeSelection / ClampMaxPlayers
-- run, so the game can't leave the range pinned below TARGET_CAP.
---------------------------------------------------------------------------
local widget_props = {
    "MaxSelectablePlayers", "DefaultMaxPlayers", "SelectedMaxPlayers"
}
local ENABLE_WIDGET_DIAG = false  -- per-click Min/Max/Default/Selected spam; off for release.
                                  -- The one-time before-override line below still logs each
                                  -- launch so a future range change is still visible.
local widget_state_logged = false

local function log_widget_state(widget, tag)
    if not widget then return end
    safe("wdiag", function()
        log(string.format("[CAPDIAG] %s Min=%s Max=%s Default=%s Selected=%s",
            tag,
            tostring(widget.MinSelectablePlayers),
            tostring(widget.MaxSelectablePlayers),
            tostring(widget.DefaultMaxPlayers),
            tostring(widget.SelectedMaxPlayers)))
    end)
end

-- Widen the selectable range so the increase button can reach TARGET_CAP. Does NOT
-- force the host's actual SelectedMaxPlayers up — only raises the ceiling fields.
local function widen_widget_cap(widget, reason)
    if not widget or not is_real_instance(widget) then return end
    safe("wcap_max", function()
        if widget.MaxSelectablePlayers ~= TARGET_CAP then
            widget.MaxSelectablePlayers = TARGET_CAP
            log("[CAP] MaxSelectablePlayers -> " .. TARGET_CAP .. " (" .. tostring(reason) .. ")")
        end
    end)
end

local function apply_overrides()
    local wclass = resolve_class("widget")
    -- MUST be CDO-safe: FindFirstOf can return Default__ widgets. Use the same
    -- live-instance filter as level detection, otherwise the cap override may
    -- write only to an archetype/stale object and not the live UI instance.
    local widget = find_first_instance(wclass)
    if not widget then return end

    if not widget_state_logged then
        widget_state_logged = true
        log_widget_state(widget, "before-override")
    end

    for _, prop in ipairs(widget_props) do
        safe("Set_" .. prop, function()
            local v = widget[prop]
            if type(v) == "number" and v ~= TARGET_CAP then
                if prop == "SelectedMaxPlayers" and v ~= 0 and v <= TARGET_CAP then
                    return
                end
                widget[prop] = TARGET_CAP
                log(prop .. " -> " .. TARGET_CAP)
            end
        end)
    end
end

-- net.MaxPlayersOverride DISABLED — causes spawn assignment to put players on wrong floor
-- The widget override + session cap is sufficient for allowing >6 players to connect
-- pcall(function()
--     if ExecuteConsoleCommand then
--         ExecuteConsoleCommand("net.MaxPlayersOverride " .. TARGET_CAP)
--     end
-- end)

ExecuteInGameThread(apply_overrides)

LoopAsync(5000, function()
    pcall(apply_overrides)
    return false
end)

-- v2.16.2: re-assert the player-cap ceiling right after the widget's own selection
-- setup / clamp runs. The 2026-06-03 update made these reset the range, so a one-shot
-- write was getting clamped back to 6/4. Post-hooking the game's own functions means
-- we always win the last write. Guarded by pcall; if a name is unhookable on a future
-- build, the 5s LoopAsync above still applies the override.
local widget_hooks_registered = false
local function register_widget_cap_hooks()
    if widget_hooks_registered then return end
    widget_hooks_registered = true
    local function post(path)
        local ok = pcall(function()
            RegisterHook(path, function(self)
                local w = self and self:get()
                if not w then return end
                ExecuteInGameThread(function()
                    if ENABLE_WIDGET_DIAG then log_widget_state(w, "after " .. path) end
                    widen_widget_cap(w, path)
                end)
            end)
        end)
        if ok then log("[CAP] widget hook registered: " .. path)
        else log("[CAP] widget hook unavailable: " .. path) end
    end
    post("/Script/BETGame.BETMultiplayerSettingsWidget:InitializeSelection")
    post("/Script/BETGame.BETMultiplayerSettingsWidget:ClampMaxPlayers")
    post("/Script/BETGame.BETMultiplayerSettingsWidget:IncreaseMaxPlayers")
end
ExecuteInGameThread(function() pcall(register_widget_cap_hooks) end)

---------------------------------------------------------------------------
-- OBJECTIVE REQUIREMENT / SUPPLY HANDLING
--
-- Design principle: same difficulty as ≤6 players. When a player-count-scaled
-- field or "all players" gate exceeds the vanilla-supported range, cap or disable
-- it. Never change current/progress/completed, never force completion, never
-- override GetNumPlayers().
---------------------------------------------------------------------------
local objective_cap_changed = {}
local objective_cap_hooks_registered = false
local objective_cap_hook_fired = {}
local supply_scaled_original = {}
-- Forward declarations for helpers defined later in the file but used by cap logic.
local collect_players

-- == Elevator presence gate ==
local ELEVATOR_CLASSES = {
    "Elevator_Base", "Level0Elevator", "Level2Elevator", "Level4_Elevator",
    "BP_ElevatorFinal_C", "BP_ElevatorFinal_Level2_C", "BP_Elevator_Level4_C",
}
local ELEVATOR_PROPS = {
    PlayersNeededToStartElevator = OBJECTIVE_CAP,
}

-- == "All players must be present" gates — force false when > ALL_PLAYERS_GATE_CAP ==
local ALL_PLAYERS_GATE_CLASSES = {
    "InteractableTeleporter", "LevelExitBase",
}
local ALL_PLAYERS_GATE_PROPS = {
    bRequiresAllPlayers = false,  -- cap_requirement_prop sets bools to target when true
}

-- == Level 232: prevent the player-scaled price discount from making items too cheap ==
local S232_PRICE_CLASSES = {
    "Level232GameState",
}

-- == Generator count (Level 1) ==
local GENERATOR_CAP_CLASSES = {
    "Level1ChunkManager", "Level1ChunkManagerDebug",
}
local GENERATOR_CAP_PROPS = {
    NumberOfGenerators = GENERATOR_CAP,
}

-- == Per-class numeric caps for player-scaled objective requirements ==
local NUMERIC_CAP_CLASSES = {
    "RepairableElectricalBox",     -- RequiredFuseAmount (no player-count curve exposed)
    "CoinGate",                    -- CoinsRequired
    "InteractableDoor",            -- ItemAmountRequired
    "LevelFunExitDoor",            -- RequiredTicketMilestone
    "LevelFunExitPinger",          -- ItemAmountRequired
    "PartyCelebrationSpeaker",     -- RequiredTicketMilestone
}
local NUMERIC_CAP_PROPS = {
    RequiredFuseAmount = GENERIC_OBJECTIVE_CAP,
    CoinsRequired = GENERIC_OBJECTIVE_CAP,
    ItemAmountRequired = GENERIC_OBJECTIVE_CAP,
    RequiredTicketMilestone = GENERIC_OBJECTIVE_CAP,
}

-- == Per-class requirement arrays ==
-- These are requirements, not supply spawns. Cap them down. Do not cap item/loot
-- spawn arrays such as Level232 ItemSpawnRates or Level3 wire repair-item spawns.
local INT_ARRAY_CAP_CLASSES = {
    "LevelFUNChunkManager",         -- WarehouseRequiredCoinsTotals
}
local INT_ARRAY_CAP_PROPS = {
    WarehouseRequiredCoinsTotals = GENERIC_OBJECTIVE_CAP,
}

-- == Confirmed supply/resource fields ==
-- These are not objective requirements. For >6 players, scale them UP from their
-- original runtime value so larger groups get more supplies instead of less per head.
-- Each object/field is scaled from the first value we observe, not repeatedly multiplied.
local SUPPLY_SCALE_CLASSES = {
    "Level1ChunkManager",            -- NumberOfAlmondWater
    "Level1ChunkManagerDebug",
    "Level3ChunkManager",            -- repair supplies / lootbox contents
    "Level232ChunkManager",          -- ItemSpawnRates FIntPoint ranges (handled specially)
    "LevelNeg1ChunkManager",         -- LootSpawnRatio (loot density)
}
local SUPPLY_SCALE_PROPS = {
    NumberOfAlmondWater = true,
    SingleFuseLootboxWireSpawnCount = true,
    SingleFuseLootboxTapeSpawnCount = true,
    MultiFuseLootboxWireSpawnCount = true,
    MultiFuseLootboxTapeSpawnCount = true,
    RepairItemMultiplier = true,       -- Level 3: multiplier for repair item spawns (supply)
    LootSpawnRatio = true,            -- Level Neg1: loot density ratio (supply)
}

-- Curve-backed requirement fields where the authored curve can tell us the 6-player cap.
local CURVE_REQUIREMENT_CLASSES = {
    "FuseBoard",
}

local CURVE_REQUIREMENT_SPECS = {
    {
        amountProp = "RequiredFuseAmount",
        curveProp = "PlayerCountFuseCurve",
        fallbackCap = GENERIC_OBJECTIVE_CAP,
    },
}

-- == GameState-scoped generic "bScalesWithPlayers" objective array ==
local GENERIC_OBJECTIVE_CLASSES = {
    "MultiplayerGameState", "Level0GameState", "Level1GameState", "Level3GameState",
    "Level37GameState", "Level232GameState", "LevelFUNGameState", "LevelNeg1GameState",
}
local GENERIC_OBJECTIVE_ARRAY_PROPS = {
    "CurrentObjectives",
}

local function unwrap_param(v)
    if not v then return nil end
    local got = safe("unwrap", function()
        if type(v) == "userdata" and v.get then return v:get() end
        return nil
    end)
    if got then return got end
    return v
end

local function object_label(obj)
    return safe("ObjFullName", function() return tostring(obj:GetFullName()) end) or tostring(obj)
end

local function cap_requirement_prop(obj, prop, cap, label)
    if not ENABLE_OBJECTIVE_CAP or not obj or not is_real_instance(obj) then return false end
    cap = cap or OBJECTIVE_CAP
    local old = safe("objcap_read_" .. prop, function() return obj[prop] end)
    if type(old) ~= "number" then return false end
    if old <= cap then return false end
    safe("objcap_write_" .. prop, function() obj[prop] = cap return true end)
    local now = safe("objcap_verify_" .. prop, function() return obj[prop] end)
    if type(now) ~= "number" or now > cap then
        log(string.format("[OBJCAP] %s.%s write did not stick (old=%s now=%s cap=%d)",
            label, prop, tostring(old), tostring(now), cap))
        return false
    end
    local key = object_label(obj) .. ":" .. prop
    if objective_cap_changed[key] ~= old then
        objective_cap_changed[key] = old
        log(string.format("[OBJCAP] %s.%s %s -> %d (%s)",
            label, prop, tostring(old), cap, object_label(obj)))
    end
    safe("objcap_fnu", function() obj:ForceNetUpdate() return true end)
    return true
end

local function cap_props_on_classes(classes, props, reason)
    if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return 0 end
    local total = 0
    for _, class_name in ipairs(classes) do
        local list = safe("ObjCapFind_" .. class_name, function() return FindAllOf(class_name) end)
        if list then
            for _, obj in pairs(list) do
                if is_real_instance(obj) then
                    for prop, cap in pairs(props) do
                        if cap_requirement_prop(obj, prop, cap, reason or class_name) then
                            total = total + 1
                        end
                    end
                end
            end
        end
    end
    return total
end

local function effective_player_count()
    local players = collect_players and collect_players() or {}
    local n = #players
    if n < 1 then n = 1 end
    return n
end

local function ceil_int(v)
    return math.floor(v + 0.999999)
end

local function curve_value_at(curve, x, label)
    if not curve then return nil end
    return safe("CurveGet_" .. tostring(label), function()
        if curve.GetFloatValue then return curve:GetFloatValue(x) end
        return nil
    end)
end

local function cap_curve_requirement_object(obj, spec, label)
    if not ENABLE_OBJECTIVE_CAP or not obj or not is_real_instance(obj) then return false end
    local old = safe("CurveReqAmount_" .. spec.amountProp, function() return obj[spec.amountProp] end)
    if type(old) ~= "number" then return false end
    local curve = safe("CurveReqCurve_" .. spec.curveProp, function() return obj[spec.curveProp] end)
    local cap = curve_value_at(curve, ALL_PLAYERS_GATE_CAP, spec.curveProp) or spec.fallbackCap or GENERIC_OBJECTIVE_CAP
    if type(cap) ~= "number" then cap = spec.fallbackCap or GENERIC_OBJECTIVE_CAP end
    cap = ceil_int(cap)
    if cap < 1 then cap = 1 end
    if old <= cap then return false end
    return cap_requirement_prop(obj, spec.amountProp, cap, label or "curve")
end

local function cap_curve_requirements(reason)
    if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return 0 end
    local total = 0
    for _, class_name in ipairs(CURVE_REQUIREMENT_CLASSES) do
        local list = safe("CurveReqFind_" .. class_name, function() return FindAllOf(class_name) end)
        if list then
            for _, obj in pairs(list) do
                if is_real_instance(obj) then
                    for _, spec in ipairs(CURVE_REQUIREMENT_SPECS) do
                        if cap_curve_requirement_object(obj, spec, reason or class_name) then total = total + 1 end
                    end
                end
            end
        end
    end
    return total
end

local function supply_original_key(obj, prop)
    return object_label(obj) .. ":" .. prop
end

local function scale_supply_number(obj, prop, factor, reason)
    if not ENABLE_SUPPLY_SCALING or not obj or not is_real_instance(obj) then return false end
    local old = safe("SupplyRead_" .. prop, function() return obj[prop] end)
    if type(old) ~= "number" or old <= 0 then return false end
    local key = supply_original_key(obj, prop)
    local base = supply_scaled_original[key] or old
    supply_scaled_original[key] = base
    local target = ceil_int(base * factor)
    if target <= old then return false end
    safe("SupplyWrite_" .. prop, function() obj[prop] = target return true end)
    local now = safe("SupplyVerify_" .. prop, function() return obj[prop] end)
    if type(now) == "number" and now >= target then
        log(string.format("[SUPPLY] %s.%s %s -> %d (base=%s factor=%.2f %s)",
            reason or "supply", prop, tostring(old), target, tostring(base), factor, object_label(obj)))
        safe("supply_fnu", function() obj:ForceNetUpdate() return true end)
        return true
    end
    log(string.format("[SUPPLY] %s.%s write did not stick (old=%s target=%d actual=%s)",
        reason or "supply", prop, tostring(old), target, tostring(now)))
    return false
end

local function scale_fintpoint_range(owner, rangeProp, factor, reason, key_owner, key_prefix)
    local r = safe("SupplyRangeRead_" .. rangeProp, function() return owner[rangeProp] end)
    if not r then return false end
    local x = safe("SupplyRangeX_" .. rangeProp, function() return r.X or r.x end)
    local y = safe("SupplyRangeY_" .. rangeProp, function() return r.Y or r.y end)
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    key_owner = key_owner or owner
    key_prefix = key_prefix or rangeProp
    local keyx = supply_original_key(key_owner, key_prefix .. ".X")
    local keyy = supply_original_key(key_owner, key_prefix .. ".Y")
    local basex = supply_scaled_original[keyx] or x
    local basey = supply_scaled_original[keyy] or y
    supply_scaled_original[keyx] = basex
    supply_scaled_original[keyy] = basey
    local tx = ceil_int(basex * factor)
    local ty = ceil_int(basey * factor)
    if tx <= x and ty <= y then return false end
    local ok = safe("SupplyRangeWrite_" .. rangeProp, function()
        if r.X ~= nil then r.X = tx else r.x = tx end
        if r.Y ~= nil then r.Y = ty else r.y = ty end
        return true
    end)
    if ok then
        log(string.format("[SUPPLY] %s.%s (%s,%s) -> (%d,%d) (factor=%.2f %s)",
            reason or "supply", key_prefix, tostring(x), tostring(y), tx, ty, factor, object_label(key_owner)))
        safe("supply_range_fnu", function() key_owner:ForceNetUpdate() return true end)
        return true
    end
    return false
end

local function scale_level232_item_spawn_rates(obj, factor, reason)
    local rates = safe("Supply232Rates", function() return obj.ItemSpawnRates end)
    if not rates then return 0 end
    local changed = 0
    if scale_fintpoint_range(rates, "PickupSpawnRange", factor, reason or "Level232ItemSpawnRates", obj, "ItemSpawnRates.PickupSpawnRange") then changed = changed + 1 end
    if scale_fintpoint_range(rates, "GrabbableSpawnRange", factor, reason or "Level232ItemSpawnRates", obj, "ItemSpawnRates.GrabbableSpawnRange") then changed = changed + 1 end
    return changed
end

local function scale_supply_for_more_players(reason)
    if not ENABLE_SUPPLY_SCALING or not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return 0 end
    local players = effective_player_count()
    if players <= SUPPLY_BASE_PLAYERS then return 0 end
    local factor = players / SUPPLY_BASE_PLAYERS
    local total = 0
    for _, class_name in ipairs(SUPPLY_SCALE_CLASSES) do
        local list = safe("SupplyFind_" .. class_name, function() return FindAllOf(class_name) end)
        if list then
            for _, obj in pairs(list) do
                if is_real_instance(obj) then
                    if class_name == "Level232ChunkManager" then
                        total = total + scale_level232_item_spawn_rates(obj, factor, reason or class_name)
                    else
                        for prop, _ in pairs(SUPPLY_SCALE_PROPS) do
                            if scale_supply_number(obj, prop, factor, reason or class_name) then total = total + 1 end
                        end
                    end
                end
            end
        end
    end
    return total
end

-- Level 6: ALevel6PuzzleManager has bScaleWithPlayers=true, which makes the
-- museum puzzle harder (more buttons / harder sequence) with more players.
-- Force it false so the puzzle stays at ≤6-player difficulty.
local l6_scale_logged = false
local function cap_level6_puzzle_scale(reason)
    if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return 0 end
    if effective_player_count() <= ALL_PLAYERS_GATE_CAP then return 0 end
    local list = safe("L6Puzzle", function() return FindAllOf("ALevel6PuzzleManager") end)
    if not list then return 0 end
    local total = 0
    for _, obj in pairs(list) do
        if is_real_instance(obj) then
            local v = safe("L6Scale", function() return obj.bScaleWithPlayers end)
            if v == true then
                safe("L6ScaleW", function() obj.bScaleWithPlayers = false return true end)
                local nb = safe("L6Buttons", function() return obj.NumButtons end)
                log(string.format("[OBJCAP] ALevel6PuzzleManager.bScaleWithPlayers = true -> false (NumButtons=%s %s)",
                    tostring(nb), reason or "monitor"))
                total = total + 1
            elseif not l6_scale_logged then
                local nb = safe("L6Buttons2", function() return obj.NumButtons end)
                log(string.format("[OBJCAP] ALevel6PuzzleManager.bScaleWithPlayers=%s NumButtons=%s (%s)",
                    tostring(v), tostring(nb), reason or "monitor"))
                l6_scale_logged = true
            end
        end
    end
    return total
end

local function cap_known_objective_requirements(reason)
    return cap_props_on_classes(ELEVATOR_CLASSES, ELEVATOR_PROPS, reason)
end

local function cap_generator_requirements(reason)
    return cap_props_on_classes(GENERATOR_CAP_CLASSES, GENERATOR_CAP_PROPS, reason)
end

local function cap_numeric_requirements(reason)
    return cap_props_on_classes(NUMERIC_CAP_CLASSES, NUMERIC_CAP_PROPS, reason)
end

local function read_array_num(arr)
    return safe("ArrayNum", function()
        if arr.GetArrayNum then return arr:GetArrayNum() end
        return #arr
    end) or 0
end

local function cap_int_array_prop(owner, prop, cap, reason)
    if not ENABLE_OBJECTIVE_CAP or not owner or not is_real_instance(owner) then return 0 end
    cap = cap or GENERIC_OBJECTIVE_CAP
    local arr = safe("IntArrayRead_" .. prop, function() return owner[prop] end)
    if not arr then return 0 end
    local n = read_array_num(arr)
    if n <= 0 then return 0 end
    local changed = 0
    local label = reason or prop

    local function cap_entry(idx, value)
        local v = unwrap_param(value)
        if type(v) ~= "number" then return end
        if v <= cap then return end
        local ok = safe("IntArrayWrite_" .. prop, function() arr[idx] = cap return true end)
        if not ok then return end
        local now = safe("IntArrayVerify_" .. prop, function()
            local reread = owner[prop]
            local rv = reread and reread[idx]
            rv = unwrap_param(rv)
            return rv
        end)
        if type(now) == "number" and now <= cap then
            changed = changed + 1
            log(string.format("[OBJCAP] %s.%s[%s] %s -> %d (%s)",
                label, prop, tostring(idx), tostring(v), cap, object_label(owner)))
        else
            log(string.format("[OBJCAP] %s.%s[%s] write did not stick (old=%s actual=%s cap=%d)",
                label, prop, tostring(idx), tostring(v), tostring(now), cap))
        end
    end

    local iter_ok = safe("IntArrayEach_" .. prop, function()
        if arr.ForEach then
            arr:ForEach(function(Index, Elem) cap_entry(Index, Elem) end)
            return true
        end
        return false
    end)
    if not iter_ok then
        for i = 1, n do
            safe("IntArrayIdx_" .. prop, function() cap_entry(i, arr[i]) return true end)
        end
    end
    if changed > 0 then
        safe("intarray_fnu", function() owner:ForceNetUpdate() return true end)
    end
    return changed
end

local function cap_int_array_requirements(reason)
    if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return 0 end
    local total = 0
    for _, class_name in ipairs(INT_ARRAY_CAP_CLASSES) do
        local list = safe("IntArrayFind_" .. class_name, function() return FindAllOf(class_name) end)
        if list then
            for _, obj in pairs(list) do
                if is_real_instance(obj) then
                    for prop, cap in pairs(INT_ARRAY_CAP_PROPS) do
                        total = total + cap_int_array_prop(obj, prop, cap, reason or class_name)
                    end
                end
            end
        end
    end
    return total
end

-- Force bRequiresAllPlayers=false on teleporters and level exits when there are
-- more than ALL_PLAYERS_GATE_CAP possessed players. The boolean gate was built
-- for ≤6; at 7–16 the geometry can't fit everyone and the gate prevents progress.
local function cap_all_players_gates(reason)
    if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return 0 end
    local players = (collect_players and collect_players()) or {}
    if #players <= ALL_PLAYERS_GATE_CAP then return 0 end
    local total = 0
    for _, class_name in ipairs(ALL_PLAYERS_GATE_CLASSES) do
        local list = safe("APGF_" .. class_name, function() return FindAllOf(class_name) end)
        if list then
            for _, obj in pairs(list) do
                if is_real_instance(obj) then
                    local v = safe("APGR_" .. class_name, function() return obj.bRequiresAllPlayers end)
                    if v == true then
                        safe("APGW_" .. class_name, function() obj.bRequiresAllPlayers = false return true end)
                        total = total + 1
                        log(string.format("[GATE] %s.bRequiresAllPlayers true->false — %d possessed > %d (%s)",
                            class_name, #players, ALL_PLAYERS_GATE_CAP, object_label(obj)))
                    end
                end
            end
        end
    end
    return total
end

-- Level 232: improve the sell-price chain for >6 players. BET 0.14.6's own
-- patch notes confirm price scaling is an earned-percentage mechanic, so for
-- larger groups we scale the global ScaledPricePercent plus per-lane multipliers
-- upward from first observed runtime values. This remains a no-op at <=6.
local s232_price_logged = false
local function cap_s232_price(reason)
    if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return 0 end
    local players = effective_player_count()
    local factor = players / SUPPLY_BASE_PLAYERS
    local total = 0
    local s232_live = false
    for _, class_name in ipairs(S232_PRICE_CLASSES) do
        local list = safe("S232F_" .. class_name, function() return FindAllOf(class_name) end)
        if list then
            for _, obj in pairs(list) do
                if is_real_instance(obj) then
                    s232_live = true
                    local sp = safe("S232R_SP", function() return obj.ScaledPricePercent end)
                    if players > SUPPLY_BASE_PLAYERS and type(sp) == "number" and sp > 0 then
                        local key = supply_original_key(obj, "ScaledPricePercent")
                        local base = supply_scaled_original[key] or sp
                        supply_scaled_original[key] = base
                        local target = ceil_int(base * factor * 100) / 100
                        if target > sp then
                            if safe("S232R_SP_W", function() obj.ScaledPricePercent = target return true end) then
                                total = total + 1
                                log(string.format("[S232] GameState.ScaledPricePercent %.2f -> %.2f (base=%.2f factor=%.2f %s)",
                                    sp, target, base, factor, object_label(obj)))
                                safe("S232R_SP_FNU", function() obj:ForceNetUpdate() return true end)
                            end
                        end
                    end
                    if not s232_price_logged then
                        local rq = safe("S232R_RQ", function() return obj.RequiredQuota end)
                        local cq = safe("S232R_CQ", function() return obj.CurrentQuota end)
                        local maxp = safe("S232R_MXP", function() return obj.MaxNumberOfItemsForPurchase end)
                        local cold = safe("S232R_CLD", function() return obj.ColdItemMultiplier end)
                        log(string.format("[S232] diagnostics (%s): ScaledPricePercent=%.4f RequiredQuota=%.0f CurrentQuota=%.0f MaxPurchaseItems=%s ColdMult=%s players=%d",
                            reason or "monitor", sp or -1, rq or -1, cq or -1, tostring(maxp), tostring(cold), players))
                        s232_price_logged = true
                    end
                end
            end
        end
    end
    if not s232_live then return 0 end
    -- Scale up checkout-lane multipliers for >6 players.
    -- Higher multipliers = better sell prices = easier to meet quota.
    if players > SUPPLY_BASE_PLAYERS then
        local lanes = safe("S232Lanes", function() return FindAllOf("AALevel232CheckoutLane") end)
        if lanes then
            for _, lane in pairs(lanes) do
                if is_real_instance(lane) then
                    local cm = safe("S232Coupon", function() return lane.CouponMultiplier end)
                    if type(cm) == "number" and cm > 0 then
                        local key = supply_original_key(lane, "CouponMultiplier")
                        local base = supply_scaled_original[key] or cm
                        supply_scaled_original[key] = base
                        local target = ceil_int(base * factor * 100) / 100
                        if target > cm then
                            if safe("S232CouponW", function() lane.CouponMultiplier = target return true end) then
                                total = total + 1
                                log(string.format("[S232] CheckoutLane.CouponMultiplier %.2f -> %.2f (base=%.2f factor=%.2f %s)",
                                    cm, target, base, factor, object_label(lane)))
                            end
                        end
                    end
                    -- Also scale LaneMultiplier (per-lane base price multiplier)
                    local lm = safe("S232Lane", function() return lane.LaneMultiplier end)
                    if type(lm) == "number" and lm > 0 then
                        local key = supply_original_key(lane, "LaneMultiplier")
                        local base = supply_scaled_original[key] or lm
                        supply_scaled_original[key] = base
                        local target = ceil_int(base * factor * 100) / 100
                        if target > lm then
                            if safe("S232LaneW", function() lane.LaneMultiplier = target return true end) then
                                total = total + 1
                                log(string.format("[S232] CheckoutLane.LaneMultiplier %.2f -> %.2f (base=%.2f factor=%.2f %s)",
                                    lm, target, base, factor, object_label(lane)))
                            end
                        end
                    end
                end
            end
        end
    end
    return total
end

local function cap_level_objective_array(owner, prop, reason)
    if not ENABLE_OBJECTIVE_CAP or not owner or not is_real_instance(owner) then return 0 end
    local arr = safe("ObjArray_" .. prop, function() return owner[prop] end)
    if not arr then return 0 end
    local n = safe("ObjArrayNum_" .. prop, function()
        if arr.GetArrayNum then return arr:GetArrayNum() end
        return #arr
    end) or 0
    if n <= 0 then return 0 end
    local changed = 0
    local label = reason or prop
    local function read_entry_amount_at(target_idx)
        local reread = safe("ObjArrayReread_" .. prop, function() return owner[prop] end)
        if not reread then return nil end
        local found = nil
        safe("ObjArrayRereadEach_" .. prop, function()
            if reread.ForEach then
                reread:ForEach(function(Index, Elem)
                    if tostring(Index) == tostring(target_idx) then
                        local e = unwrap_param(Elem)
                        if e then found = e.ObjectiveAmount end
                    end
                end)
                return true
            end
            return false
        end)
        if found ~= nil then return found end
        return safe("ObjArrayRereadIdx_" .. prop, function()
            local e = reread[target_idx]
            e = unwrap_param(e)
            if e then return e.ObjectiveAmount end
            return nil
        end)
    end
    local function cap_entry(idx, entry)
        local obj = unwrap_param(entry)
        if not obj then return end
        local scales = safe("ObjScale", function() return obj.bScalesWithPlayers end)
        if scales ~= true then return end
        local old = safe("ObjAmount", function() return obj.ObjectiveAmount end)
        if type(old) ~= "number" or old <= GENERIC_OBJECTIVE_CAP then return end
        safe("ObjAmountWrite", function() obj.ObjectiveAmount = GENERIC_OBJECTIVE_CAP return true end)
        local now = read_entry_amount_at(idx)
        if type(now) == "number" and now <= GENERIC_OBJECTIVE_CAP then
            changed = changed + 1
            log(string.format("[OBJCAP] %s.%s[%s].ObjectiveAmount %s -> %d (%s)",
                label, prop, tostring(idx), tostring(old), GENERIC_OBJECTIVE_CAP, object_label(owner)))
        else
            log(string.format("[OBJCAP] %s.%s[%s].ObjectiveAmount write did not stick (old=%s actual=%s)",
                label, prop, tostring(idx), tostring(old), tostring(now)))
        end
    end
    local iter_ok = safe("ObjArrayForEach_" .. prop, function()
        if arr.ForEach then
            arr:ForEach(function(Index, Elem) cap_entry(Index, Elem) end)
            return true
        end
        return false
    end)
    if not iter_ok then
        for i = 1, n do
            safe("ObjArrayIdx_" .. prop, function() cap_entry(i, arr[i]) return true end)
        end
    end
    if changed > 0 then
        safe("objarray_fnu", function() owner:ForceNetUpdate() return true end)
    end
    return changed
end

local function cap_generic_scaled_objectives(reason)
    if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return 0 end
    local total = 0
    for _, class_name in ipairs(GENERIC_OBJECTIVE_CLASSES) do
        local list = safe("ObjScaledFind_" .. class_name, function() return FindAllOf(class_name) end)
        if list then
            for _, obj in pairs(list) do
                if is_real_instance(obj) then
                    for _, prop in ipairs(GENERIC_OBJECTIVE_ARRAY_PROPS) do
                        total = total + cap_level_objective_array(obj, prop, reason or class_name)
                    end
                end
            end
        end
    end
    return total
end

local function register_cap_hook(path, props)
    local ok = safe("ObjCapHook_" .. path, function()
        RegisterHook(path, function(self, ...)
            -- UE4SS hook params are RemoteUnrealParam-style wrappers; unwrap them
            -- synchronously inside the hook callback, before the wrapper can go stale.
            local obj = unwrap_param(self)
            if not obj or not is_real_instance(obj) then return end
            ExecuteInGameThread(function()
                if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return end
                if not is_real_instance(obj) then return end
                if not objective_cap_hook_fired[path] then
                    objective_cap_hook_fired[path] = true
                    log("[OBJCAP] hook fired: " .. path .. " on " .. object_label(obj))
                end
                for prop, cap in pairs(props) do
                    cap_requirement_prop(obj, prop, cap, path)
                end
            end)
        end)
        return true
    end)
    if ok then
        log("[OBJCAP] hook registered: " .. path)
    else
        log("[OBJCAP] hook unavailable: " .. path)
    end
end

local function register_objective_cap_hook(path)
    register_cap_hook(path, ELEVATOR_PROPS)
end

local function register_generic_objective_hook(path)
    local ok = safe("ObjCapHook_" .. path, function()
        RegisterHook(path, function(self, ...)
            local obj = unwrap_param(self)
            if not obj or not is_real_instance(obj) then return end
            ExecuteInGameThread(function()
                if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return end
                if not is_real_instance(obj) then return end
                if not objective_cap_hook_fired[path] then
                    objective_cap_hook_fired[path] = true
                    log("[OBJCAP] hook fired: " .. path .. " on " .. object_label(obj))
                end
                cap_level_objective_array(obj, "CurrentObjectives", path)
            end)
        end)
        return true
    end)
    if ok then
        log("[OBJCAP] hook registered: " .. path)
    else
        log("[OBJCAP] hook unavailable: " .. path)
    end
end

local function register_int_array_cap_hook(path, prop)
    local ok = safe("ObjCapHook_" .. path, function()
        RegisterHook(path, function(self, ...)
            local obj = unwrap_param(self)
            if not obj or not is_real_instance(obj) then return end
            ExecuteInGameThread(function()
                if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return end
                if not is_real_instance(obj) then return end
                if not objective_cap_hook_fired[path] then
                    objective_cap_hook_fired[path] = true
                    log("[OBJCAP] hook fired: " .. path .. " on " .. object_label(obj))
                end
                cap_int_array_prop(obj, prop, GENERIC_OBJECTIVE_CAP, path)
            end)
        end)
        return true
    end)
    if ok then
        log("[OBJCAP] hook registered: " .. path)
    else
        log("[OBJCAP] hook unavailable: " .. path)
    end
end

local function register_curve_requirement_hook(path)
    local ok = safe("CurveReqHook_" .. path, function()
        RegisterHook(path, function(self, ...)
            local obj = unwrap_param(self)
            if not obj or not is_real_instance(obj) then return end
            ExecuteInGameThread(function()
                if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return end
                if not is_real_instance(obj) then return end
                if not objective_cap_hook_fired[path] then
                    objective_cap_hook_fired[path] = true
                    log("[OBJCAP] hook fired: " .. path .. " on " .. object_label(obj))
                end
                for _, spec in ipairs(CURVE_REQUIREMENT_SPECS) do
                    cap_curve_requirement_object(obj, spec, path)
                end
            end)
        end)
        return true
    end)
    if ok then
        log("[OBJCAP] hook registered: " .. path)
    else
        log("[OBJCAP] hook unavailable: " .. path)
    end
end

local function register_supply_scale_hook(path)
    local ok = safe("SupplyHook_" .. path, function()
        RegisterHook(path, function(self, ...)
            ExecuteInGameThread(function()
                if not ENABLE_SUPPLY_SCALING or not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return end
                if not objective_cap_hook_fired[path] then
                    objective_cap_hook_fired[path] = true
                    log("[SUPPLY] hook fired: " .. path)
                end
                scale_supply_for_more_players(path)
            end)
        end)
        return true
    end)
    if ok then
        log("[SUPPLY] hook registered: " .. path)
    else
        log("[SUPPLY] hook unavailable: " .. path)
    end
end

local function register_all_players_gate_hook(path)
    local ok = safe("GateHook_" .. path, function()
        RegisterHook(path, function(self, ...)
            ExecuteInGameThread(function()
                if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return end
                if not objective_cap_hook_fired[path] then
                    objective_cap_hook_fired[path] = true
                    log("[GATE] hook fired: " .. path)
                end
                cap_all_players_gates(path)
            end)
        end)
        return true
    end)
    if ok then
        log("[GATE] hook registered: " .. path)
    else
        log("[GATE] hook unavailable: " .. path)
    end
end

local function ensure_objective_cap_hooks()
    if objective_cap_hooks_registered or not ENABLE_OBJECTIVE_CAP then return end
    objective_cap_hooks_registered = true
    -- Only hook functions that are real, hookable UFunctions on this build (verified
    -- against UE4SS.log 2026-06-03 after a game update). Excluded on purpose:
    --   * Elevator_Base:StartElevator / OnAllPlayersJoined — BlueprintImplementableEvents
    --     (FUNC_Native:0, ProcessInternal:0x0) → not hookable; the periodic scan and the
    --     CheckForPlayersInElevator/OnObjectiveCompleted hooks already cover the cap.
    --   * Level1ChunkManager:GenerateChunks — defined on base BETChunkManagerBase, not the
    --     subclass; the base hook below covers it.
    --   * MultiplayerGameState:OnCurrentObjectivesUpdated — a delegate signature, not a real
    --     UFunction; OnRep_CurrentObjectives is the hookable replication entry point.
    register_objective_cap_hook("/Script/BETGame.Elevator_Base:CheckForPlayersInElevator")
    register_objective_cap_hook("/Script/BETGame.Elevator_Base:OnObjectiveCompleted")
    register_cap_hook("/Script/BETGame.BETChunkManagerBase:GenerateChunks", GENERATOR_CAP_PROPS)
    register_supply_scale_hook("/Script/BETGame.BETChunkManagerBase:GenerateChunks")
    register_generic_objective_hook("/Script/BETGame.MultiplayerGameState:OnRep_CurrentObjectives")
    -- The following hooks re-assert caps at points where the game re-initializes
    -- or re-evaluates these values during gameplay (not just at level start).
    register_curve_requirement_hook("/Script/BETGame.FuseBoard:OnFuseBoardInitialized")
    register_generic_objective_hook("/Script/BETGame.Level232GameState:OnRep_CurrentQuota")
    register_int_array_cap_hook("/Script/BETGame.LevelFUNChunkManager:AddWarehouseRequiredCoins", "WarehouseRequiredCoinsTotals")
    register_all_players_gate_hook("/Script/BETGame.LevelExitBase:OnSurvivorOverlap")
    register_all_players_gate_hook("/Script/BETGame.LevelExitBase:OnAllPlayersPresent")
    register_all_players_gate_hook("/Script/BETGame.InteractableTeleporter:OnActivationStateChange")
    register_all_players_gate_hook("/Script/BETGame.InteractableTeleporter:AreAllPlayersPresent")
end

ExecuteInGameThread(function()
    pcall(ensure_objective_cap_hooks)
    pcall(cap_known_objective_requirements, "startup")
    pcall(cap_generator_requirements, "startup")
    pcall(cap_curve_requirements, "startup")
    pcall(cap_level6_puzzle_scale, "startup")
    pcall(cap_numeric_requirements, "startup")
    pcall(cap_int_array_requirements, "startup")
    pcall(scale_supply_for_more_players, "startup")
    pcall(cap_all_players_gates, "startup")
    pcall(cap_s232_price, "startup")
    pcall(cap_generic_scaled_objectives, "startup")
end)

---------------------------------------------------------------------------
-- SPAWN FIX: Dynamic coordinate detection + delayed teleport
---------------------------------------------------------------------------
local spawn_fix_applied = false
local level_detected = false
local level_detect_time = 0
local diag_tick = 0

-- v2.4 cluster-fix tunables (RELATIVE detection — no absolute floor constants).
-- CONFIRMED model: correct players spawn in an elevator + ride a cutscene down,
-- ending tightly CLUSTERED. A mis-spawned player is dropped at a Neg1 PlayerStart
-- ~one floor-gap (~8000u) away. Runtime coords are in a DIFFERENT frame than
-- PlayerStart coords (~+8500 offset), so absolute-Z thresholds are useless.
local CLUSTER_GAP   = 2500   -- |Z-median| beyond this = outlier (jitter ~100s; floor gap ~8000)
local SETTLE_TOL    = 300    -- median Z must move < this between reads to count as "settled"
local TP_XY_SPREAD  = 120    -- per-outlier XY offset so teleported players don't stack
local MIN_CLUSTER   = 2      -- majority must have at least this many to be trusted
local FIX_MAX_TICKS = 8      -- only attempt fix within this many ticks of level detect
                             -- (after that, a far player likely WENT to Neg1 legitimately)
local last_median_z = nil
local settled_reads = 0

-- v2.14 host noclip-nudge: step size per Ctrl+Arrow / Ctrl+PageUp-Down keypress.
-- teleport_pawn snaps with bSweep=false,bTeleport=true (no collision sweep), so a
-- nudge can push the host THROUGH geometry — used to work around a spot where a
-- 7+ player count can't progress normally. Horizontal is CAMERA-RELATIVE (forward =
-- where you look), computed from control-rotation yaw. Keep small to stay on-tile.
local NUDGE_STEP   = 100   -- horizontal world units per Ctrl+Arrow
local NUDGE_STEP_Z = 100   -- vertical world units per Ctrl+PageUp/PageDown

-- v2.8 post-travel summon timing. The 2026-05-31 7-player level-switch test showed
-- the OLD post-travel summon firing too early: right after a forced level switch it tried to gather
-- while the host pawn wasn't re-resolved yet ("Could not resolve host pawn — aborting"
-- on Level 3/4) and while stuck players hadn't possessed (only 5 of 7 readable on
-- Level 1). So instead of a fixed "2 ticks after detect", we now WAIT for the group to
-- actually be present + the host pawn resolvable, retrying for a bounded window, then
-- summon ONCE. This avoids yanking a half-loaded group around.
local SUMMON_WAIT_TICKS = 6     -- give the new level up to this many ticks to settle
local summon_wait_count = 0     -- ticks waited so far for the current armed summon

-- v2.6 LEVEL-SWITCH (test tool). BET travels between levels via ProcessServerTravel
-- (seamless), confirmed in BET.log. We use the same path so all clients are carried
-- along (no drop). Ctrl+K/L step through the map list below.
--
-- IMPORTANT (verified 2026-05-31 against the game's own BETGame.hpp class dump):
-- THIS LIST IS *NOT* THE CANONICAL LEVEL ORDER. BET has no fixed numeric sequence.
-- Progression is a runtime, branching "ending path": each level EXIT
-- (ALevelExitBase.NextLevel : UBETLevel) points to a next-level data asset, levels
-- are keyed by GameplayTag (UBETGameInstance.GetCachedLevels : TMap<FGameplayTag,
-- UBETLevel>), the candidate set is a WEIGHTED pool (UBETLevelOptions.Levels :
-- TMap<UBETLevel,float>), and players literally pick their route on the
-- UEndingPathBoardWidget (SelectLevel / EndingPathData.VisitedLevels). So the real
-- "next level" is data-driven and player-chosen, not L_Level_<N+1>.
-- The list below is just a convenient TEST TRAVERSAL (every path is a confirmed-valid
-- map, ordered Level 0 first = the real StartLevel). Jumping straight to a map also
-- skip normal lobby start + elevator + ending-path setup, so OBJECTIVES may not init.
-- This is a SPAWN/travel TEST AID only — see docs/research/level_structure.md.
local LEVEL_MAPS = {
    "/Game/Maps/MainLevels/Level_0/L_Level_0",      -- real StartLevel
    "/Game/Maps/MainLevels/Level_1/L_Level_1",
    "/Game/Maps/MainLevels/Level_2/L_Level_2",
    "/Game/Maps/MainLevels/Level_3/L_Level_3",
    "/Game/Maps/MainLevels/Level_4/L_Level_4",
    "/Game/Maps/MainLevels/Level_6/L_Level_6",
    "/Game/Maps/MainLevels/Level_37/L_Level_37",
    "/Game/Maps/MainLevels/Level_232/L_Level_232",
    "/Game/Maps/MainLevels/Level_FUN/L_Level_FUN",
    "/Game/Maps/MainLevels/Level_Run/L_Level_Run",
    "/Game/Maps/MainLevels/Level_Hub/L_Level_Hub",
    "/Game/Maps/MainLevels/Level_Neg1/L_Level_Neg1",
}
local level_cycle_idx = 0          -- 0 = before first press; advances each Ctrl+K/L level switch
local summon_after_travel = false  -- set true on travel so post-load we auto-gather
local travel_arm_tick = 0          -- tick when we armed the post-travel summon

-- Self no-collision toggle: optional per-player tool for clients who also install
-- the mod. It affects only the local player's pawn; monster actors are never scanned
-- or modified. Ctrl+N toggles it. Host tools remain host-gated separately.
local SELF_NO_COLLISION_KEY_LABEL = "Ctrl+N"

local function median(vals)
    local n = #vals
    if n == 0 then return nil end
    local s = {}
    for i = 1, n do s[i] = vals[i] end
    table.sort(s)
    if n % 2 == 1 then return s[math.floor((n + 1) / 2)] end
    local h = math.floor(n / 2)
    return (s[h] + s[h + 1]) / 2
end

-- Exact player-pawn classes only. Do not include generic Character here: broad
-- Character scans can include AI/monster pawns and Ctrl+G must never move them.
local PLAYER_CHARACTER_CLASSES = {
    "BP_Survivor_Character_C",
    "SurvivorCharacter",
}
local PLAYER_CHARACTER_FALLBACK_CLASSES = {
    "Character",
}

local function get_valid_player_state(ctrl, label)
    if not ctrl or not is_real_instance(ctrl) then return nil end
    return safe((label or "Player") .. "PS", function()
        local ps = ctrl.PlayerState
        if ps and ps:IsValid() then return ps end
        return nil
    end)
end

local function is_player_controlled_character(char, label)
    if not char or not is_real_instance(char) then return nil, nil end
    local ctrl = safe((label or "Player") .. "Ctrl", function()
        local c = char.Controller
        if c and c:IsValid() then return c end
        return nil
    end)
    if not ctrl then return nil, nil end
    local ps = get_valid_player_state(ctrl, label or "Player")
    if not ps then return nil, nil end
    return ctrl, ps
end

local function looks_like_survivor_actor(char)
    local full = object_label(char)
    return string.find(full, "Survivor", 1, true) ~= nil
        or string.find(full, "BP_Survivor", 1, true) ~= nil
end

-- Collect every real, player-controlled in-level survivor with a readable position.
-- Eligibility is intentionally stricter than "has any Controller": Ctrl+G and the
-- spawn fix teleport these actors, so require an exact survivor class plus a valid
-- Controller->PlayerState chain. This excludes AI/monster pawns even if they are
-- possessed by AI controllers, and avoids UE4SS wrapper equality hazards elsewhere.
collect_players = function()
    local out = {}
    for _, charclass in ipairs(PLAYER_CHARACTER_CLASSES) do
        local chars = safe("CollectFind_" .. charclass, function() return FindAllOf(charclass) end)
        if chars then
            for _, char in pairs(chars) do
                local ctrl, ps = is_player_controlled_character(char, "Coll")
                if ctrl and ps then
                    local loc = get_actor_pos(char, "Coll")
                    if loc and loc.Z and not (loc.Z == 0 and (loc.X or 0) == 0 and (loc.Y or 0) == 0) then
                        out[#out + 1] = {
                            char = char,
                            name = get_player_name(char, "Coll") or "?",
                            X = loc.X or 0, Y = loc.Y or 0, Z = loc.Z,
                        }
                    end
                end
            end
        end
        -- Prefer the exact BP survivor class. Only try the native survivor fallback
        -- if no valid player pawns were readable under the exact class name.
        if #out > 0 then break end
    end
    if #out == 0 then
        for _, charclass in ipairs(PLAYER_CHARACTER_FALLBACK_CLASSES) do
            local chars = safe("CollectFindFallback_" .. charclass, function() return FindAllOf(charclass) end)
            if chars then
                for _, char in pairs(chars) do
                    if looks_like_survivor_actor(char) then
                        local ctrl, ps = is_player_controlled_character(char, "CollFB")
                        if ctrl and ps then
                            local loc = get_actor_pos(char, "CollFB")
                            if loc and loc.Z and not (loc.Z == 0 and (loc.X or 0) == 0 and (loc.Y or 0) == 0) then
                                out[#out + 1] = {
                                    char = char,
                                    name = get_player_name(char, "CollFB") or "?",
                                    X = loc.X or 0, Y = loc.Y or 0, Z = loc.Z,
                                }
                            end
                        end
                    end
                end
            end
            if #out > 0 then break end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- HOST ANCHOR + SHARED TELEPORT (v2.5)
-- Level-INDEPENDENT: the host (listen-server authority) always spawns with
-- the group on any level, standing in valid walkable geometry. Their live
-- runtime position is the gather target — no per-level coords, no PlayerStart
-- frame offset. Confirmed primitives on THIS build: K2_GetActorLocation reads,
-- K2_SetActorLocation writes+replicates to remote clients (v2.4 live test),
-- RegisterKeyBind + K2_SetActorLocationAndRotation (shipped SplitScreenMod).
---------------------------------------------------------------------------

-- Resolve the local player's pawn. On the host this is the listen-server host pawn;
-- on a client this is that client's own pawn. Re-resolve every time because pawns are
-- recreated across travel/respawn.
local function get_local_pawn()
    if not UEHelpers then return nil end
    local pc = safe("LocalPC", function() return UEHelpers.GetPlayerController() end)
    if not pc or not is_real_instance(pc) then return nil end
    local pawn = safe("LocalPawn", function()
        local p = pc.Pawn
        if p and p:IsValid() then return p end
        return nil
    end)
    return pawn
end

-- Resolve the host pawn (local PlayerController's Pawn). Re-resolve every time
-- (pawns are recreated across travel/respawn — never cache).
local function get_host_pawn()
    return get_local_pawn()
end

-- Robust UObject identity. UE4SS wraps each access in a NEW Lua object, so the
-- SAME actor obtained two different ways (get_host_pawn() vs FindAllOf) compares
-- UNEQUAL under '~='. The 7-player log proved this: Ctrl+G "gathered 6 players"
-- with 6 possessed and moved the host itself (Host Z=63 -> first move Z=63->113),
-- because `char ~= host` never matched. Compare the underlying address instead
-- (GetFullName fallback if GetAddress is unavailable on this build).
local function actor_id(a)
    if not a then return nil end
    local addr = safe("aid_addr", function() return a:GetAddress() end)
    if addr then return addr end
    return safe("aid_name", function() return a:GetFullName() end)
end
local function same_actor(a, b)
    if a == b then return true end
    local ia, ib = actor_id(a), actor_id(b)
    if ia and ib then return ia == ib end
    return false
end

-- Teleport one pawn to dest with a ring offset. Uses bTeleport=TRUE so the
-- client SNAPS (no interpolation/sweep). Verifies the move by re-reading pos.
-- Returns true if the pawn ended up near dest.
local function teleport_pawn(pawn, dest, label)
    -- Discontinuous move: bSweep=false, bTeleport=true (the 4th/last arg).
    local ok = safe(label .. "_SAL", function()
        pawn:K2_SetActorLocation({X = dest.X, Y = dest.Y, Z = dest.Z}, false, {}, true)
        return true
    end)
    if not ok then
        ok = safe(label .. "_TTO", function()
            pawn:K2_TeleportTo({X = dest.X, Y = dest.Y, Z = dest.Z},
                {Pitch = 0, Yaw = 0, Roll = 0})
            return true
        end)
    end
    safe(label .. "_FNU", function() pawn:ForceNetUpdate() return true end)
    local after = get_actor_pos(pawn, label .. "_chk")
    if after and after.Z
        and math.abs(after.X - dest.X) <= 400
        and math.abs(after.Y - dest.Y) <= 400
        and math.abs(after.Z - dest.Z) <= CLUSTER_GAP then
        return true, after
    end
    return false, after
end

-- Ring offset around an anchor so N pawns don't stack on one exact point.
-- TIGHT footprint by design: the 7-player test proved a 150u ring reaches PAST
-- the spawn-platform edge and drops players into the void (3 players fell to
-- Z=-18853/-12257/-19473 after a 150u summon on Level 1). Player capsules
-- interpenetrate and the engine nudges them apart, so heavy overlap is SAFE
-- (no telefrag death in this game) whereas a wide ring is NOT. So we keep the
-- whole cluster well inside one floor tile: first pawn on the anchor, the rest
-- in a small ring whose radius is capped low and grows only slightly with N.
local function ring_dest(anchor, i, n)
    if n <= 1 then
        return {X = anchor.X, Y = anchor.Y, Z = anchor.Z + 50}
    end
    if i == 1 then
        -- anchor-center pawn: same spot as the host, lifted to drop onto floor.
        return {X = anchor.X, Y = anchor.Y, Z = anchor.Z + 50}
    end
    -- Remaining n-1 pawns in a ring. Radius capped at 80u (≈ half the old 150u)
    -- so even 12 players stay within a ~160u footprint — comfortably on-tile.
    local R = math.min(45 + (n - 1) * 4, 80)
    local theta = (i - 2) * (2 * math.pi / (n - 1))
    return {
        X = anchor.X + math.cos(theta) * R,
        Y = anchor.Y + math.sin(theta) * R,
        Z = anchor.Z + 50,
    }
end

-- HOST "SUMMON ALL": gather every OTHER possessed player to the host pawn.
-- Manual, host-only (only the host runs this mod), one-shot per press. This is
-- the level-independent escape hatch for ANY separation, not just Z-axis.
local function summon_all_to_host()
    if not require_host("Ctrl+G summon") then return end
    local host = get_host_pawn()
    if not host then
        log("[SUMMON] Could not resolve host pawn — aborting")
        return
    end
    local anchor = get_actor_pos(host, "SummonAnchor")
    if not anchor or not anchor.Z then
        log("[SUMMON] Could not read host position — aborting")
        return
    end

    local players = collect_players()
    -- Exclude the host pawn itself from the move list. MUST use address identity:
    -- '~=' on UE4SS wrappers fails (see same_actor) and the host would teleport
    -- itself, appearing to "lag" to where it stood a tick ago.
    local others = {}
    local host_in_list = false
    for i = 1, #players do
        if same_actor(players[i].char, host) then
            host_in_list = true
        else
            others[#others + 1] = players[i]
        end
    end
    local n = #others
    log(string.format("[SUMMON] Host @ (%.0f,%.0f,%.0f); gathering %d players%s",
        anchor.X, anchor.Y, anchor.Z, n,
        host_in_list and "" or " (warn: host not in possessed list)"))
    if n == 0 then return end

    local moved = 0
    for i = 1, n do
        local p = others[i]
        local dest = ring_dest(anchor, i, n)
        local ok, after = teleport_pawn(p.char, dest, "SUM" .. i)
        local az = (after and after.Z) or -999999
        if ok then
            moved = moved + 1
            log(string.format("[SUMMON] OK '%s' Z=%.0f -> %.0f (verified)",
                p.name, p.Z, az))
        else
            log(string.format("[SUMMON] FAILED/UNVERIFIED '%s' now Z=%.0f", p.name, az))
        end
    end
    log(string.format("[SUMMON] Done: %d/%d moved", moved, n))
end

-- Register the host summon keybind (Ctrl+G). Guarded: RegisterKeyBind support
-- is verified on this build (SplitScreenMod uses it). Runs work in game thread.
local summon_bound = false
local function ensure_summon_keybind()
    if summon_bound then return end
    local ok = pcall(function()
        RegisterKeyBind(Key.G, {ModifierKey.CONTROL}, function()
            ExecuteInGameThread(function()
                pcall(summon_all_to_host)
            end)
        end)
    end)
    if ok then
        summon_bound = true
        log("[SUMMON] Host keybind registered: Ctrl+G = gather all players to host")
    else
        log("[SUMMON] RegisterKeyBind failed — summon keybind unavailable")
    end
end

-- Detect the currently-loaded main level by matching a live GameMode instance
-- against the per-level gamemode names. Returns the LEVEL_MAPS index or nil.
-- Lets Ctrl+K/L "step from where we actually are" rather than from a stale counter.
-- MUST stay parallel (same order) with LEVEL_MAPS above. Gamemode class names
-- confirmed from BETGame.hpp / docs/research/level_structure.md.
local LEVEL_GM_BY_INDEX = {
    "BP_Level0GameMode_C", "BP_Level1_GameMode_C", "BP_Level2GameMode_C",
    "BP_Level3GameMode_C", "BP_Level4GameMode_C", "BP_Level6GameMode_C",
    "BP_Level37GameMode_C", "BP_Level232GameMode_C", "BP_LevelFUNGameMode_C",
    "BP_LevelRunGameMode_C", "BP_LevelHubGameMode_C", "BP_LevelNeg1GameMode_C",
}
local function detect_current_level_idx()
    for i, gm in ipairs(LEVEL_GM_BY_INDEX) do
        if find_first_instance(gm) then return i end
    end
    return nil
end

-- Seamless ServerTravel to a map (same mechanism BET uses: ProcessServerTravel).
-- Carries all connected clients along — nobody is dropped. ?listen keeps the
-- listen-server net driver. Host authority required (host runs this mod).
local function server_travel(map_path)
    local cmd = "servertravel " .. map_path .. "?listen"
    local ok = pcall(function()
        if ExecuteConsoleCommand then ExecuteConsoleCommand(cmd) end
    end)
    if not ok or not ExecuteConsoleCommand then
        -- Fallback: KismetSystemLibrary.ExecuteConsoleCommand via a PlayerController
        local pc = UEHelpers and safe("TravelPC", function()
            return UEHelpers.GetPlayerController()
        end)
        if pc then
            safe("TravelKSL", function()
                local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
                ksl:ExecuteConsoleCommand(pc:GetWorld(), cmd, pc)
                return true
            end)
        end
    end
    log("[LEVELSW] ServerTravel -> " .. map_path)
end

-- Step to an adjacent level (delta=+1 next, -1 prev), relative to the level we're
-- actually in (if detectable; else our own counter). Wraps around the list.
-- Arms the post-travel state (auto-gather itself is disabled since v2.10; this
-- just re-arms the spawn-fix + logs a "press Ctrl+G" reminder on arrival).
local function do_level_step(delta, tag)
    if not require_host(tag) then return end
    local cur = detect_current_level_idx() or level_cycle_idx
    local nxt = ((cur - 1 + delta) % #LEVEL_MAPS) + 1
    level_cycle_idx = nxt
    summon_after_travel = true
    summon_wait_count = 0
    travel_arm_tick = diag_tick
    -- reset spawn-fix state so the auto-fix re-arms in the new level
    spawn_fix_applied = false
    level_detected = false
    last_median_z = nil
    settled_reads = 0
    log(string.format("[LEVELSW] %s: level %d -> %d (%s)",
        tag, cur, nxt, LEVEL_MAPS[nxt]))
    server_travel(LEVEL_MAPS[nxt])
end
local function cycle_next_level() do_level_step(1, "Ctrl+L next") end
local function cycle_prev_level() do_level_step(-1, "Ctrl+K prev") end

local levelsw_bound = false
local function ensure_levelsw_keybind()
    if levelsw_bound or not ENABLE_LEVEL_TEST_KEYS then
        if not levelsw_bound and not ENABLE_LEVEL_TEST_KEYS then
            levelsw_bound = true
            log("[LEVELSW] Ctrl+K/L level test keys disabled in release config")
        end
        return
    end
    local ok = pcall(function()
        RegisterKeyBind(Key.L, {ModifierKey.CONTROL}, function()
            ExecuteInGameThread(function() pcall(cycle_next_level) end)
        end)
        RegisterKeyBind(Key.K, {ModifierKey.CONTROL}, function()
            ExecuteInGameThread(function() pcall(cycle_prev_level) end)
        end)
    end)
    if ok then
        levelsw_bound = true
        log("[LEVELSW] Host keybinds: Ctrl+L = next level, Ctrl+K = prev level (test tool)")
    else
        log("[LEVELSW] RegisterKeyBind failed — level-switch keybinds unavailable")
    end
end

-- Resolve the FULL map path of the level we're actually in right now. Prefers the
-- live GameMode match (works for the 12 main levels incl. Neg1). Falls back to
-- reading the live world's short map name and matching a LEVEL_MAPS entry by suffix
-- (covers maps reached via normal in-game progression). Returns path or nil.
local function get_current_map_path()
    local idx = detect_current_level_idx()
    if idx then return LEVEL_MAPS[idx] end
    -- Fallback: read the live world name (e.g. "L_Level_0") and match by suffix.
    local short = nil
    if UEHelpers then
        short = safe("CurMapName", function()
            local w = UEHelpers.GetWorld()
            if w and w:IsValid() then return w:GetName() end
            return nil
        end)
    end
    if short and short ~= "" then
        for _, path in ipairs(LEVEL_MAPS) do
            -- path tail after the last '/' is the umap object name
            local tail = path:match("([^/]+)$")
            if tail and tail == short then return path end
        end
        -- Unknown map (e.g. HubPuzzle / a map not in our list): reconstruct a best-
        -- effort path so reload still works. MainLevels convention: Level_<X>/L_Level_<X>.
        local x = short:match("^L_Level_(.+)$")
        if x then
            return "/Game/Maps/MainLevels/Level_" .. x .. "/" .. short
        end
    end
    return nil
end

-- Ctrl+J: RELOAD the current level (re-travel to the SAME map). This re-runs BET's
-- IrisGate Disallow->Allow replication pass for everyone, giving players who got
-- STUCK ON THE LOADING SCREEN (skipped by the no-retry Allow loop — see
-- bet_irisgate_diagnosis) a fresh chance to load in. It's the escape hatch for the
-- "some players stuck loading after travel" case observed in the 7-player test.
-- Like Ctrl+K/L it carries all clients via seamless ProcessServerTravel; it also arms
-- the same post-travel auto-summon so the group re-gathers on reload.
local function reload_current_level()
    if not require_host("Ctrl+J reload") then return end
    local path = get_current_map_path()
    if not path then
        log("[RELOAD] Could not determine current map — reload aborted")
        return
    end
    summon_after_travel = true
    summon_wait_count = 0
    travel_arm_tick = diag_tick
    -- re-arm per-level state so spawn-fix + detection run again on reload
    spawn_fix_applied = false
    level_detected = false
    last_median_z = nil
    settled_reads = 0
    log("[RELOAD] Ctrl+J: reloading current level -> " .. path)
    server_travel(path)
end

local reload_bound = false
local function ensure_reload_keybind()
    if reload_bound then return end
    local ok = pcall(function()
        RegisterKeyBind(Key.J, {ModifierKey.CONTROL}, function()
            ExecuteInGameThread(function() pcall(reload_current_level) end)
        end)
    end)
    if ok then
        reload_bound = true
        log("[RELOAD] Host keybind registered: Ctrl+J = reload current level (un-stick)")
    else
        log("[RELOAD] RegisterKeyBind failed — reload keybind unavailable")
    end
end

---------------------------------------------------------------------------
-- ELEVATOR BOARDING (v2.9) -- let 7+ players advance to the next level.
--
-- KEY INSIGHT (verified from BETGame.hpp + adversarial multi-agent review,
-- 2026-05-31): the elevator gate is a COUNT check, NOT a physical-capacity
-- limit. AElevator_Base has a single UBoxComponent trigger (CollisionBox), an
-- int PlayersInElevator, an int PlayersNeededToStartElevator, and the predicate
-- CheckForPlayersInElevator(). A UBoxComponent is an OVERLAP volume, not a
-- blocker -- capsules interpenetrate, so ANY number of pawns can register inside
-- it regardless of how crowded it looks. Physical fit and the count are
-- DECOUPLED. So we do NOT need to disable collision or make anyone suicide:
-- teleport every player into the box and let the game's OWN authoritative code
-- (host = listen-server) run StartElevator -> move -> ServerTravel, exactly as
-- it already does for <=6. Reuses ONLY the verified position-replicating
-- teleport; makes NO new replication/authority assumptions. Plan 2 (host writes
-- PlayersInElevator / forces StartElevator) was REFUTED unsafe and is NOT done.
---------------------------------------------------------------------------

-- Live elevators are BP subclasses of A(Level*)Elevator : AElevator_Base.
local ELEVATOR_CLASS_NAMES = {
    "Elevator_Base", "Level0Elevator", "Level2Elevator", "Level4_Elevator",
    "BP_ElevatorFinal_C", "BP_ElevatorFinal_Level2_C", "BP_Elevator_Level4_C",
}
local function find_elevator()
    for _, n in ipairs(ELEVATOR_CLASS_NAMES) do
        local e = find_first_instance(n)
        if e then return e, n end
    end
    return nil
end

-- Read a component's world position (fallback to component-space).
local function get_component_pos(comp, label)
    local loc = safe(label .. "_KGCL", function()
        return comp:K2_GetComponentLocation()
    end)
    if loc and loc.Z then return loc end
    loc = safe(label .. "_RL", function() return comp.RelativeLocation end)
    if loc and loc.Z then return loc end
    return nil
end

local function get_elevator_target(elevator)
    local box = safe("ElevBox", function()
        local b = elevator.CollisionBox
        if b and b:IsValid() then return b end
        return nil
    end)
    if box then
        local p = get_component_pos(box, "ElevBox")
        if p and p.Z then return p, box end
    end
    return get_actor_pos(elevator, "ElevActor"), box
end

-- Ctrl+O: READ-ONLY probe/detect. Logs the live elevator's real gate values + box
-- geometry so we confirm the count-gate model BEFORE cramming. No side effects
-- beyond the (read-only) predicate call.
local function probe_elevator()
    if not require_host("Ctrl+O probe") then return end
    local e, cls = find_elevator()
    if not e then log("[PROBE] No live elevator found"); return end
    local need = safe("p_need", function() return e.PlayersNeededToStartElevator end)
    local have = safe("p_have", function() return e.PlayersInElevator end)
    log(string.format("[PROBE] Elevator '%s'  In=%s  Needed=%s",
        cls, tostring(have), tostring(need)))
    local box = safe("p_box", function()
        local b = e.CollisionBox
        if b and b:IsValid() then return b end
        return nil
    end)
    if box then
        local wl = get_component_pos(box, "p_boxpos")
        local ext = safe("p_ext", function() return box.BoxExtent end)
        if wl then log(string.format("[PROBE] BoxWorld=(%.0f,%.0f,%.0f)",
            wl.X, wl.Y, wl.Z)) end
        if ext and ext.X then log(string.format(
            "[PROBE] BoxExtent(half)=(%.0f,%.0f,%.0f)", ext.X, ext.Y, ext.Z)) end
    else
        log("[PROBE] CollisionBox not readable")
    end
    local r = safe("p_check", function() return e:CheckForPlayersInElevator() end)
    local players = (collect_players and collect_players()) or {}
    log("[PROBE] CheckForPlayersInElevator() -> " .. tostring(r)
        .. " ; possessed=" .. tostring(#players))
end

-- Ctrl+P: cram EVERY possessed player (incl. host) into the elevator trigger box
-- in a tight ring, then ask the game's own gate to re-evaluate. Never forces
-- StartElevator or writes the counter -- the game's authoritative code decides.
local function board_elevator()
    if not require_host("Ctrl+P board elevator") then return end
    local e, cls = find_elevator()
    if not e then log("[BOARD] No live elevator found - aborting"); return end
    local target, box = get_elevator_target(e)
    if not target or not target.Z then
        log("[BOARD] No elevator target pos - aborting"); return
    end
    local need = safe("b_need", function() return e.PlayersNeededToStartElevator end)
    local have0 = safe("b_have0", function() return e.PlayersInElevator end)
    log(string.format("[BOARD] '%s' @ (%.0f,%.0f,%.0f) In=%s Need=%s",
        cls, target.X, target.Y, target.Z, tostring(have0), tostring(need)))
    -- CRITICAL FIX (v2.10): the trigger box is TINY. The 7-player test probe read
    -- BoxExtent(half)=(32,32,32) -> a 64u cube. The old 120u ring put everyone
    -- OUTSIDE the box, so CheckForPlayersInElevator() returned FALSE despite a
    -- stale In=7, AND the wide ring shoved edge players off the platform. Now we
    -- read the live half-extent and cram everyone WELL INSIDE it. Capsules
    -- interpenetrate, so stacking near the box center is exactly what registers
    -- the overlap and is physically safe.
    local half = safe("b_ext", function() return box and box.BoxExtent end)
    local hx = (half and half.X) or 32
    local hy = (half and half.Y) or 32
    -- Keep the ring radius to ~40% of the smaller half-extent so every capsule
    -- center sits comfortably inside the trigger volume (min 0 -> pure center).
    local R = math.max(0, math.min(hx, hy) * 0.4)
    local players = collect_players()
    local n = #players
    local moved = 0
    for i = 1, n do
        local dest
        if n <= 1 or R < 1 then
            dest = {X = target.X, Y = target.Y, Z = target.Z + 10}
        else
            local theta = (i - 1) * (2 * math.pi / n)
            dest = {
                X = target.X + math.cos(theta) * R,
                Y = target.Y + math.sin(theta) * R,
                Z = target.Z + 10,
            }
        end
        if teleport_pawn(players[i].char, dest, "BOARD" .. i) then
            moved = moved + 1
        end
    end
    log(string.format("[BOARD] Crammed %d/%d players into box (R=%.0f, half=%.0f)",
        moved, n, R, math.min(hx, hy)))
    -- Ask the game's OWN gate to re-evaluate (host-side). NOT a forced start.
    local rechk = safe("b_check", function() return e:CheckForPlayersInElevator() end)
    local have1 = safe("b_have1", function() return e.PlayersInElevator end)
    log(string.format("[BOARD] After cram+recheck In=%s (need %s) Check=%s - watch "
        .. "BET.log for ProcessServerTravel", tostring(have1), tostring(need),
        tostring(rechk)))
end

local probe_bound = false
local function ensure_probe_keybind()
    if probe_bound then return end
    local ok = pcall(function()
        RegisterKeyBind(Key.O, {ModifierKey.CONTROL}, function()
            ExecuteInGameThread(function() pcall(probe_elevator) end)
        end)
    end)
    if ok then
        probe_bound = true
        log("[PROBE] Host keybind registered: Ctrl+O = read elevator gate (probe/detect)")
    else
        log("[PROBE] RegisterKeyBind failed — probe keybind unavailable")
    end
end

local board_bound = false
local function ensure_board_keybind()
    if board_bound then return end
    local ok = pcall(function()
        RegisterKeyBind(Key.P, {ModifierKey.CONTROL}, function()
            ExecuteInGameThread(function() pcall(board_elevator) end)
        end)
    end)
    if ok then
        board_bound = true
        log("[BOARD] Host keybind registered: Ctrl+P = teleport all players into elevator")
    else
        log("[BOARD] RegisterKeyBind failed — board keybind unavailable")
    end
end

local self_no_collision_enabled = false
local self_no_collision_bound = false

local function set_actor_collision_enabled(actor, enabled, label)
    if not actor or not is_real_instance(actor) then return false end
    local ok = safe((label or "Collision") .. "_SetActorEnableCollision", function()
        if actor.SetActorEnableCollision then
            actor:SetActorEnableCollision(enabled)
            return true
        end
        if actor.K2_SetActorEnableCollision then
            actor:K2_SetActorEnableCollision(enabled)
            return true
        end
        return nil
    end)
    if ok then return true end
    return safe((label or "Collision") .. "_prop", function()
        actor.bActorEnableCollision = enabled
        return true
    end) and true or false
end

local function reapply_self_no_collision(reason)
    if not self_no_collision_enabled then return end
    local pawn = get_local_pawn()
    if not pawn then return end
    if set_actor_collision_enabled(pawn, false, "SelfNoCollisionReapply") then
        safe("SelfNoCollisionFNU", function() pawn:ForceNetUpdate() return true end)
        log("[NOCLIP] Self no-collision re-applied (" .. tostring(reason or "monitor") .. ")")
    end
end

local function toggle_self_no_collision()
    local pawn = get_local_pawn()
    if not pawn then
        log("[NOCLIP] Could not resolve local pawn — toggle ignored")
        return
    end
    local target = not self_no_collision_enabled
    if set_actor_collision_enabled(pawn, not target, "SelfNoCollision") then
        self_no_collision_enabled = target
        safe("SelfNoCollisionFNU", function() pawn:ForceNetUpdate() return true end)
        log("[NOCLIP] " .. SELF_NO_COLLISION_KEY_LABEL .. ": self pawn collision " .. (target and "OFF" or "ON"))
    else
        log("[NOCLIP] " .. SELF_NO_COLLISION_KEY_LABEL .. ": SetActorEnableCollision unavailable on local pawn")
    end
end

local function ensure_self_no_collision_keybind()
    if self_no_collision_bound then return end
    local ok = pcall(function()
        RegisterKeyBind(Key.N, {ModifierKey.CONTROL}, function()
            ExecuteInGameThread(function()
                pcall(toggle_self_no_collision)
            end)
        end)
    end)
    if ok then
        self_no_collision_bound = true
        log("[NOCLIP] Optional local keybind registered: " .. SELF_NO_COLLISION_KEY_LABEL .. " = toggle self pawn collision")
    else
        log("[NOCLIP] RegisterKeyBind failed — self no-collision keybind unavailable")
    end
end

-- HOST NOCLIP NUDGE (v2.14): snap the HOST pawn a small step to work around a spot
-- where a 7+ player count can't progress (stuck geometry, an objective gated on
-- fewer players, etc). Reuses the verified replicating teleport (bSweep=false,
-- bTeleport=true + ForceNetUpdate) so it ignores collision (noclip) and the new
-- spot reaches clients exactly like Ctrl+G / Ctrl+P. Host-only.
--   forward/right are CAMERA-RELATIVE: computed from the controller's yaw so
--   "forward" is where the host is looking (flattened to horizontal). Z is world.
-- Read the host's control yaw (degrees). Falls back to actor yaw, then 0.
local function get_host_yaw()
    local pawn = get_host_pawn()
    if not pawn then return nil, nil end
    local yaw = safe("NudgeYaw_ctrl", function()
        local c = pawn.Controller
        if c and c:IsValid() then
            local r = c:GetControlRotation()
            if r and r.Yaw then return r.Yaw end
        end
        return nil
    end)
    if not yaw then
        yaw = safe("NudgeYaw_actor", function()
            local r = pawn:K2_GetActorRotation()
            if r and r.Yaw then return r.Yaw end
            return nil
        end)
    end
    return pawn, yaw
end

-- diry/dirx in {-1,0,1}: forward(+1)/back(-1) and right(+1)/left(-1); dz world units.
local function nudge_host(forward, right, dz)
    if not require_host("Ctrl+Arrow nudge") then return end
    local pawn, yaw = get_host_yaw()
    if not pawn then log("[NUDGE] Could not resolve host pawn - aborting"); return end
    local cur = get_actor_pos(pawn, "NudgeCur")
    if not cur or not cur.Z then log("[NUDGE] Could not read host position - aborting"); return end
    local dx, dy = 0, 0
    if (forward ~= 0 or right ~= 0) then
        local rad = (yaw or 0) * math.pi / 180.0
        local fx, fy = math.cos(rad), math.sin(rad)   -- horizontal forward unit
        -- right = forward rotated +90deg in UE's left-handed yaw
        local rx, ry = -math.sin(rad), math.cos(rad)
        dx = (fx * forward + rx * right) * NUDGE_STEP
        dy = (fy * forward + ry * right) * NUDGE_STEP
    end
    local dest = {X = cur.X + dx, Y = cur.Y + dy, Z = cur.Z + (dz or 0)}
    local ok = teleport_pawn(pawn, dest, "NUDGE")
    log(string.format("[NUDGE] fwd=%d right=%d dz=%d -> (%.0f,%.0f,%.0f) %s",
        forward, right, dz or 0, dest.X, dest.Y, dest.Z, ok and "ok" or "UNVERIFIED"))
end

local nudge_bound = false
local function ensure_nudge_keybind()
    if nudge_bound then return end
    local ok = pcall(function()
        RegisterKeyBind(Key.UP_ARROW,    {ModifierKey.CONTROL}, function() ExecuteInGameThread(function() pcall(nudge_host,  1, 0, 0) end) end)
        RegisterKeyBind(Key.DOWN_ARROW,  {ModifierKey.CONTROL}, function() ExecuteInGameThread(function() pcall(nudge_host, -1, 0, 0) end) end)
        RegisterKeyBind(Key.RIGHT_ARROW, {ModifierKey.CONTROL}, function() ExecuteInGameThread(function() pcall(nudge_host, 0,  1, 0) end) end)
        RegisterKeyBind(Key.LEFT_ARROW,  {ModifierKey.CONTROL}, function() ExecuteInGameThread(function() pcall(nudge_host, 0, -1, 0) end) end)
        RegisterKeyBind(Key.PAGE_UP,     {ModifierKey.CONTROL}, function() ExecuteInGameThread(function() pcall(nudge_host, 0, 0,  NUDGE_STEP_Z) end) end)
        RegisterKeyBind(Key.PAGE_DOWN,   {ModifierKey.CONTROL}, function() ExecuteInGameThread(function() pcall(nudge_host, 0, 0, -NUDGE_STEP_Z) end) end)
    end)
    if ok then
        nudge_bound = true
        log("[NUDGE] Host keybinds: Ctrl+Arrows = noclip move " .. NUDGE_STEP
            .. "u (camera-relative), Ctrl+PageUp/Down = " .. NUDGE_STEP_Z .. "u (Z)")
    else
        log("[NUDGE] RegisterKeyBind failed — nudge keybinds unavailable")
    end
end

-- RELATIVE cluster-outlier teleport. Target = the HOST pawn's live position
-- (level-independent), falling back to the majority-cluster median only if the
-- host can't be resolved or the host is itself the outlier.
local function try_spawn_fix()
    if spawn_fix_applied then return end

    local players = collect_players()
    local total = #players
    if total < (MIN_CLUSTER + 1) then
        log(string.format("[SPAWN] Need >=%d possessed players, have %d - wait",
            MIN_CLUSTER + 1, total))
        return
    end

    -- Settling gate: median Z must be stable across two consecutive reads
    -- (round-1 readings catch players mid-elevator-cutscene).
    local zs = {}
    for i = 1, total do zs[i] = players[i].Z end
    local med = median(zs)
    if last_median_z and math.abs(med - last_median_z) < SETTLE_TOL then
        settled_reads = settled_reads + 1
    else
        settled_reads = 0
    end
    last_median_z = med
    if settled_reads < 1 then
        log(string.format("[SPAWN] Cluster not settled yet (medianZ=%.0f) - wait", med))
        return
    end

    -- Partition: majority cluster (|Z-median| <= gap) vs outliers.
    local cluster = {}
    local outliers = {}
    for i = 1, total do
        if math.abs(players[i].Z - med) <= CLUSTER_GAP then
            cluster[#cluster + 1] = players[i]
        else
            outliers[#outliers + 1] = players[i]
        end
    end

    if #cluster < MIN_CLUSTER then
        log(string.format("[SPAWN] No trustworthy majority (cluster=%d) - skip",
            #cluster))
        return
    end
    if #outliers == 0 then
        log(string.format("[SPAWN] All %d players clustered at Z=%.0f - nothing to fix",
            #cluster, med))
        spawn_fix_applied = true
        return
    end

    -- TARGET = host pawn's live position (level-independent). Fall back to the
    -- cluster median only if the host can't be resolved OR the host is itself an
    -- outlier (don't gather everyone onto a misplaced host).
    local cxs, cys, czs = {}, {}, {}
    for i = 1, #cluster do
        cxs[i] = cluster[i].X; cys[i] = cluster[i].Y; czs[i] = cluster[i].Z
    end
    local tx, ty, tz = median(cxs), median(cys), median(czs)
    local anchor_src = "cluster-median"

    local host = get_host_pawn()
    if host then
        local hloc = get_actor_pos(host, "HostAnchor")
        if hloc and hloc.Z and math.abs(hloc.Z - med) <= CLUSTER_GAP then
            -- host is in the majority -> trust it as the anchor
            tx, ty, tz = hloc.X, hloc.Y, hloc.Z
            anchor_src = "host-pawn"
        end
    end
    local anchor = {X = tx, Y = ty, Z = tz}
    log(string.format("[SPAWN] Anchor(%s)=(%.0f,%.0f,%.0f); cluster=%d outliers=%d",
        anchor_src, tx, ty, tz, #cluster, #outliers))

    local fixed = 0
    for i = 1, #outliers do
        local o = outliers[i]
        local dest = ring_dest(anchor, i, #outliers)
        log(string.format("[SPAWN] Outlier '%s' at Z=%.0f -> (%.0f,%.0f,%.0f)",
            o.name, o.Z, dest.X, dest.Y, dest.Z))
        local ok, after = teleport_pawn(o.char, dest, "SF" .. i)
        local az = (after and after.Z) or -999999
        if ok then
            fixed = fixed + 1
            log(string.format("[SPAWN] OK '%s' now Z=%.0f (verified)", o.name, az))
        else
            log(string.format("[SPAWN] WRITE FAILED/UNVERIFIED '%s' Z=%.0f", o.name, az))
        end
    end

    log(string.format("[SPAWN] Done: total=%d cluster=%d outliers=%d fixed=%d",
        total, #cluster, #outliers, fixed))

    -- Mark applied once we successfully moved every outlier. If a write failed,
    -- leave it unset so the next tick retries (within FIX_MAX_TICKS window).
    if fixed == #outliers then
        spawn_fix_applied = true
    end
end

---------------------------------------------------------------------------
-- MAIN MONITOR LOOP
---------------------------------------------------------------------------
local function run_monitor()
    diag_tick = diag_tick + 1

    -- Phase 1: Detect game level (CDO-filtered, gameplay-specific signal only)
    if not level_detected then
        local detected, via = in_gameplay_level()
        if detected then
            level_detected = true
            level_detect_time = diag_tick
            log("[DIAG] Game level detected via " .. tostring(via) .. " at tick " .. diag_tick)
            -- Register host keybinds now that we're in a real level.
            ensure_objective_cap_hooks()
            cap_known_objective_requirements("level-detect")
            cap_generator_requirements("level-detect")
            cap_curve_requirements("level-detect")
            cap_level6_puzzle_scale("level-detect")
            cap_numeric_requirements("level-detect")
            cap_int_array_requirements("level-detect")
            scale_supply_for_more_players("level-detect")
            cap_all_players_gates("level-detect")
            cap_s232_price("level-detect")
            cap_generic_scaled_objectives("level-detect")
            ensure_summon_keybind()
            ensure_levelsw_keybind()
            ensure_reload_keybind()
            ensure_probe_keybind()
            ensure_board_keybind()
            ensure_nudge_keybind()
            ensure_self_no_collision_keybind()
        else
            return
        end
    end

    -- Phase 3: Spawn fix ENABLED (v2.4) — RELATIVE cluster-outlier teleport.
    -- SPAWN-TIME ONLY: only attempt within FIX_MAX_TICKS of level detection. After
    -- that window a far-away player most likely WENT to Neg1 legitimately (it's an
    -- explorable area), so we must NOT teleport them. The fix self-disables once it
    -- has moved all outliers (spawn_fix_applied) or the window closes.
    local since_detect = diag_tick - level_detect_time
    if not spawn_fix_applied and since_detect >= 1 and since_detect <= FIX_MAX_TICKS then
        log("[SPAWN] Attempting cluster fix (tick " .. diag_tick
            .. ", window " .. since_detect .. "/" .. FIX_MAX_TICKS .. ")")
        try_spawn_fix()
    elseif not spawn_fix_applied and since_detect == (FIX_MAX_TICKS + 1) then
        log("[SPAWN] Fix window closed — leaving positions as-is (Neg1 may be intentional now)")
        spawn_fix_applied = true
    end

    -- Phase 3b: post-travel auto-summon REMOVED (v2.10).
    -- The 7-player test proved this was the main thing flinging players off the
    -- map: it fired DURING the elevator-descent cutscene (host read Z=23120 /
    -- 21202 mid-drop) and gathered everyone to that mid-air point, and its wide
    -- ring dropped edge players past the platform (3 players fell to
    -- Z=-18853/-12257/-19473 on Level 1 right after a post-travel summon).
    -- Auto-gather can't know when the descent/spawn has actually settled, so it
    -- is inherently unreliable. Gathering is now MANUAL: press Ctrl+G once the
    -- group has visibly settled. The settling-gated, outlier-only Phase 3 spawn
    -- fix above still runs to rescue a genuinely wrong-floor player automatically.
    if summon_after_travel then
        summon_after_travel = false  -- consume the flag; do not auto-gather.
        log("[LEVELSW] Arrived — auto-gather disabled. Press Ctrl+G to gather when settled.")
    end

    -- Phase 4: Keep known and generic player-scaled requirements capped. This uses
    -- exact class/property scans plus the game's replicated FLevelObjective array:
    --   * Elevator_Base subclasses: PlayersNeededToStartElevator <= 6
    --   * Level1ChunkManager: NumberOfGenerators <= 10
    --   * MultiplayerGameState.CurrentObjectives entries with bScalesWithPlayers:
    --     ObjectiveAmount <= 10
    -- It does not scan arbitrary UObjects or touch current/progress/completed fields.
    if ENABLE_OBJECTIVE_CAP then
        cap_known_objective_requirements("monitor")
        cap_generator_requirements("monitor")
        cap_curve_requirements("monitor")
        cap_level6_puzzle_scale("monitor")
        cap_numeric_requirements("monitor")
        cap_int_array_requirements("monitor")
        scale_supply_for_more_players("monitor")
        cap_all_players_gates("monitor")
        cap_s232_price("monitor")
        cap_generic_scaled_objectives("monitor")
    end

    -- Keep optional client-side self no-collision across respawn/travel.
    reapply_self_no_collision("monitor")

    -- Phase 5: Periodic diagnostics (every 30s = every 3rd tick).
    -- Cluster-RELATIVE classification: the old absolute -8150 threshold is
    -- meaningless (runtime frame differs from PlayerStart frame). We report each
    -- player's Z plus its distance from the group median.
    if ENABLE_PERIODIC_DIAG and diag_tick % 3 == 0 then
        local players = collect_players()
        local count = #players
        if count > 0 then
            local zs = {}
            for i = 1, count do zs[i] = players[i].Z end
            local med = median(zs)
            for i = 1, count do
                local p = players[i]
                local d = p.Z - med
                local tag = (math.abs(d) > CLUSTER_GAP) and "OUTLIER(wrong-floor?)" or "cluster(ok)"
                log(string.format("[DIAG] Player#%d '%s' Z=%.0f (med%+.0f) -> %s",
                    i, p.name, p.Z, d, tag))
            end
            log(string.format("[DIAG] Possessed players: %d  medianZ=%.0f  gap=%.0f",
                count, med, CLUSTER_GAP))
        else
            log("[DIAG] No possessed players readable this tick")
        end
    end
end

LoopAsync(10000, function()
    pcall(run_monitor)
    return false
end)

log("init complete - adaptive v" .. VERSION)
log("[ADAPT] Position detection: will try 5 methods (GetActorLocation, K2_GetActorLocation, RootComponent.RelativeLocation, RootComponent.XYZ, GetTransform)")
log("[SUMMON] Host keybind Ctrl+G (gather all players to host) will arm once in a real level")
log("[LEVELSW] Ctrl+K/L previous/next level keybinds are enabled by default")
log("[RELOAD] Host keybind Ctrl+J (reload current level, un-stick loading) will arm once in a real level")
log("[PROBE] Host keybind Ctrl+O (read elevator gate, READ-ONLY probe/detect) will arm once in a real level")
log("[BOARD] Host keybind Ctrl+P (teleport all players into elevator) will arm once in a real level")
log("[NUDGE] Host keybinds Ctrl+Arrows (noclip move) / Ctrl+PageUp-Down (Z) will arm once in a real level")
log("[NOCLIP] Optional local keybind " .. SELF_NO_COLLISION_KEY_LABEL .. " (toggle self pawn collision) will arm once in a real level if this mod is installed")
log("[OBJCAP] Player-scaled requirements are capped at " .. OBJECTIVE_CAP .. " (generators " .. GENERATOR_CAP .. ", session cap remains " .. TARGET_CAP .. ")")
log("[ADAPT] UEHelpers " .. (UEHelpers and "loaded" or "NOT FOUND — host-anchor disabled, will use cluster median"))
