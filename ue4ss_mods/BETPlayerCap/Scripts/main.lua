local MOD_NAME = "BETPlayerCap"
-- =====================  USER CONFIG (edit these)  =====================
-- TARGET_CAP: the lobby/session player cap the host can select in the menu.
--   Set to 16 — live-tested as the maximum that can still create a lobby. 17+
--   causes session-creation failure (EOS-level limit). The objective/generator
--   caps below are unchanged.
local TARGET_CAP = 16
-- OBJECTIVE_CAP: cap for player-presence pass gates (e.g. elevator "players needed").
local OBJECTIVE_CAP = 6
-- GENERIC_OBJECTIVE_CAP: cap for player-scaled objective counts the game marks
--   bScalesWithPlayers (the actual per-player requirement, e.g. "repair N generators").
--   (The old GENERATOR_CAP on Level1ChunkManager.NumberOfGenerators was removed in
--   v2.19.11: that field is the SCENE spawn count, not the requirement — the requirement
--   is this bScalesWithPlayers ObjectiveAmount, and capping the spawn count could under-
--   spawn below the repair goal.)
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
local VERSION = "2.19.11-hazard-6p-cap"

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

log("v" .. VERSION .. " loaded - target cap: " .. TARGET_CAP .. ", objective cap: " .. OBJECTIVE_CAP .. ", generic objective cap: " .. GENERIC_OBJECTIVE_CAP)

---------------------------------------------------------------------------
-- ADAPTIVE CLASS DETECTION
-- Try exact names first, fall back to parent classes if game updates
---------------------------------------------------------------------------
local CLASS_NAMES = {
    widget = {"BETMultiplayerSettingsWidget"},
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
-- First-observed value per object:prop for the proportional "6-player-equivalent" guard
-- (see cap_proportional_requirements). Like supply_scaled_original it anchors to the
-- FIRST value seen so re-applying the cap is idempotent (never compounds downward), and
-- it is likewise preserved across reset_per_level_state.
local requirement_cap_original = {}
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
-- cap_all_players_gates() reads/writes bRequiresAllPlayers directly on these classes.
local ALL_PLAYERS_GATE_CLASSES = {
    "InteractableTeleporter", "LevelExitBase",
}

-- == Level 232: scale the global player-scaled sell-price percentage UP for >6 players ==
-- (no-op at <=6). cap_s232_price scales ONLY GameState.ScaledPricePercent (linear, one
-- lever). Per-lane LaneMultiplier / CouponMultiplier are left at vanilla — scaling all
-- three multiplicative levers compounded income to factor^2..factor^3 (removed v2.19.6).
local S232_PRICE_CLASSES = {
    "Level232GameState",
}

-- == Generator count (Level 1) — cap REMOVED in v2.19.11 ==
-- Level1ChunkManager.NumberOfGenerators is the SCENE spawn count (how many generators
-- exist, ~10 by design), NOT the player-scaled requirement. The requirement (how many to
-- repair) is a bScalesWithPlayers FLevelObjective.ObjectiveAmount, already capped to the
-- 6-player baseline via cap_level_objective_array. Capping the spawn count to a magic 10
-- (with no ≤6 guard) broke "pure vanilla at ≤6" and could under-spawn below the repair
-- goal. So the spawn count is left vanilla; difficulty stays ≤6p via the objective cap.

-- == REMOVED in v2.19.8: the "numeric requirement" + "int-array requirement" caps ==
-- These capped RequiredFuseAmount / CoinsRequired / ItemAmountRequired /
-- RequiredTicketMilestone / WarehouseRequiredCoinsTotals to GENERIC_OBJECTIVE_CAP,
-- ASSUMING they scale up with player count. A live ≥7-player 0.14.6 session proved
-- otherwise — they are FIXED or PROCEDURAL level-design goals, not player-scaled:
--   * RequiredTicketMilestone = fixed 1500 (cap -> 10 trivialized Level FUN's exit/celebration);
--   * WarehouseRequiredCoinsTotals = per-generation procedural (164/138/227 vs 124/150/155
--     at the SAME 9 players) (cap -> 10 trivialized the warehouses);
--   * RequiredFuseAmount = fixed/seeded 9 at 7, 8 AND 9 players (and the FuseBoard curve
--     cap mis-read GetFloatValue(6) ≈ 1, slashing 9 -> 1).
-- None has a PlayerCount* curve / *PerPlayer field, and these caps had NO ≤6 guard, so
-- they deviated from the 6-player baseline at every count. Because the authored value is
-- identical at 6 and >6 players, NOT capping keeps ">6 = same difficulty as 6" and cannot
-- make >6 harder. Genuinely player-scaled requirements remain capped via the
-- bScalesWithPlayers objective array, the elevator presence gate, and the generator cap.

-- == "Never harder than 6" guard for UNOBSERVED scalar requirements (v2.19.9) ==
-- These four fields were never seen in a live session, so unlike the confirmed-fixed
-- fields above we cannot be 100% sure they don't scale up with player count. Instead of
-- the old magic-number cap (to 10, which trivialized fixed goals), scale each DOWN to its
-- 6-player-PROPORTIONAL equivalent: target = ceil(first_observed * 6 / players). This is a
-- no-op at ≤6, only ever LOWERS (players>6 ⇒ target<first_observed), and is anchored to the
-- first-observed value so it never compounds. If a field is fixed, this makes >6 slightly
-- easier (acceptable: ">6 ≤ 6 difficulty"); if it actually scales up, it correctly clamps
-- it to the 6-player level — so it can never make >6 harder than 6. RequiredTicketMilestone
-- is intentionally NOT here (confirmed fixed 1500 — left fully vanilla).
local PROPORTIONAL_CAP_CLASSES = {
    "RepairableElectricalBox",   -- RequiredFuseAmount (bRandomizeFuseAmount; never observed)
    "CoinGate",                  -- CoinsRequired (never observed)
    "InteractableDoor",          -- ItemAmountRequired (never observed)
    "LevelFunExitPinger",        -- ItemAmountRequired (never observed)
}
local PROPORTIONAL_CAP_PROPS = {
    "RequiredFuseAmount", "CoinsRequired", "ItemAmountRequired",
}

-- == Confirmed supply/resource fields ==
-- These are not objective requirements. For >6 players, scale them UP from their
-- original runtime value so larger groups get more supplies instead of less per head.
-- Each object/field is scaled from the first value we observe, not repeatedly multiplied.
local SUPPLY_SCALE_CLASSES = {
    "Level1ChunkManager",            -- NumberOfAlmondWater
    "Level1ChunkManagerDebug",
    "Level3ChunkManager",            -- lootbox wire/tape spawn COUNTS (flat int config)
    -- v2.19.6: Level232ChunkManager removed — 0.14.6 spawns Level 232 loot per-sector
    -- AND per-player, so scaling ItemSpawnRates by players/6 double-counts. LevelNeg1-
    -- ChunkManager removed too: its only scaled field (LootSpawnRatio) is a clamped
    -- float that was being integer-rounded; loot density is left to the game.
}
-- Only INTEGER count fields are scaled here (scale_supply_number uses ceil_int, which is
-- correct for counts, wrong for floats). FLOAT multiplier/ratio fields are intentionally
-- NOT scaled:
--   * RepairItemMultiplier (float) — the game already derives it per player via
--     ALevel3ChunkManager.PlayerCountToRepairItemMultiplier (a UCurveFloat); scaling it
--     too would double-count and fight the game's own curve.
--   * LootSpawnRatio (float) — clamped by LootSpawnRatioMin/Max; integer-rounding it was
--     wrong, and loot density is left to the game.
local SUPPLY_SCALE_PROPS = {
    NumberOfAlmondWater = true,
    SingleFuseLootboxWireSpawnCount = true,
    SingleFuseLootboxTapeSpawnCount = true,
    MultiFuseLootboxWireSpawnCount = true,
    MultiFuseLootboxTapeSpawnCount = true,
}

-- (Removed v2.19.8: the FuseBoard PlayerCountFuseCurve cap — see the removal note above.
--  GetFloatValue(6) returned ~1, slashing a fixed/seeded 9-fuse board to 1 fuse.)

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
                    for prop, _ in pairs(SUPPLY_SCALE_PROPS) do
                        if scale_supply_number(obj, prop, factor, reason or class_name) then total = total + 1 end
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

-- Cap one unobserved scalar requirement DOWN to its 6-player-proportional equivalent
-- (ceil(first_observed * 6 / players)). Anchored to the first observed value so it is
-- idempotent and never compounds; only ever lowers. See PROPORTIONAL_CAP_CLASSES.
local function cap_proportional_requirement(obj, prop, players, label)
    if not ENABLE_OBJECTIVE_CAP or not obj or not is_real_instance(obj) then return false end
    local old = safe("PropReqRead_" .. prop, function() return obj[prop] end)
    if type(old) ~= "number" or old <= 0 then return false end
    local key = object_label(obj) .. ":" .. prop
    local base = requirement_cap_original[key] or old
    requirement_cap_original[key] = base
    local target = ceil_int(base * SUPPLY_BASE_PLAYERS / players)
    if target < 1 then target = 1 end
    if old <= target then return false end   -- already at/below the 6-player equivalent
    safe("PropReqWrite_" .. prop, function() obj[prop] = target return true end)
    local now = safe("PropReqVerify_" .. prop, function() return obj[prop] end)
    if type(now) ~= "number" or now > target then
        log(string.format("[OBJCAP] %s.%s write did not stick (old=%s now=%s target=%d)",
            label, prop, tostring(old), tostring(now), target))
        return false
    end
    if objective_cap_changed[key] ~= old then
        objective_cap_changed[key] = old
        log(string.format("[OBJCAP] %s.%s %d -> %d (6p-equiv, base=%d players=%d %s)",
            label, prop, old, target, base, players, object_label(obj)))
    end
    safe("PropReq_fnu", function() obj:ForceNetUpdate() return true end)
    return true
end

-- "Never harder than 6" guard: only runs for >6 possessed players (no-op at ≤6).
local function cap_proportional_requirements(reason)
    if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return 0 end
    local players = effective_player_count()
    if players <= SUPPLY_BASE_PLAYERS then return 0 end
    local total = 0
    for _, class_name in ipairs(PROPORTIONAL_CAP_CLASSES) do
        local list = safe("PropFind_" .. class_name, function() return FindAllOf(class_name) end)
        if list then
            for _, obj in pairs(list) do
                if is_real_instance(obj) then
                    for _, prop in ipairs(PROPORTIONAL_CAP_PROPS) do
                        if cap_proportional_requirement(obj, prop, players, reason or class_name) then total = total + 1 end
                    end
                end
            end
        end
    end
    return total
end

-- v2.19.11: neutralize player-scaled MONSTER/HAZARD rates to the 6-player level.
-- Per user direction ("difficulty must never scale above the 6-player level"), the one
-- monster field that provably makes >6 harder — LevelNeg1Manager.EntitySpawnChancePerPlayer
-- (shadow spawn chance the game multiplies by player count) — is scaled DOWN to its
-- 6-player-equivalent: target = base * 6 / players. So cumulative shadow pressure at N>6
-- ≈ a 6-player game (and is still bounded by the game's own MaxShadowSpawnAmount ceiling).
-- FLOAT-safe (no integer rounding), anchored to the first-observed base (idempotent, never
-- compounds), only ever LOWERS, no-op at ≤6. It can only reduce monster pressure — never
-- make >6 harder. This is the mod's first monster-field write (was "leave monsters alone").
local HAZARD_SCALE_CLASSES = {
    "LevelNeg1Manager",   -- EntitySpawnChancePerPlayer
}
local HAZARD_SCALE_PROPS = {
    "EntitySpawnChancePerPlayer",
}
local function neutralize_hazard_field(obj, prop, players, label)
    local old = safe("HazRead_" .. prop, function() return obj[prop] end)
    if type(old) ~= "number" or old <= 0 then return false end
    local key = object_label(obj) .. ":" .. prop
    local base = requirement_cap_original[key] or old
    requirement_cap_original[key] = base
    -- 6-player-equivalent per-player rate (float; players>6 => target<base). Round to 4 dp.
    local target = math.floor((base * SUPPLY_BASE_PLAYERS / players) * 10000 + 0.5) / 10000
    if old <= target then return false end
    safe("HazWrite_" .. prop, function() obj[prop] = target return true end)
    local now = safe("HazVerify_" .. prop, function() return obj[prop] end)
    if type(now) == "number" and now <= target + 0.00001 then
        if objective_cap_changed[key] ~= old then
            objective_cap_changed[key] = old
            log(string.format("[HAZARD] %s.%s %.4f -> %.4f (6p-equiv, base=%.4f players=%d %s)",
                label, prop, old, target, base, players, object_label(obj)))
        end
        safe("Haz_fnu", function() obj:ForceNetUpdate() return true end)
        return true
    end
    return false
end

local function neutralize_player_scaled_hazards(reason)
    if not ENABLE_OBJECTIVE_CAP or not is_host_authority() then return 0 end
    local players = effective_player_count()
    if players <= SUPPLY_BASE_PLAYERS then return 0 end
    local total = 0
    for _, class_name in ipairs(HAZARD_SCALE_CLASSES) do
        local list = safe("HazFind_" .. class_name, function() return FindAllOf(class_name) end)
        if list then
            for _, obj in pairs(list) do
                if is_real_instance(obj) then
                    for _, prop in ipairs(HAZARD_SCALE_PROPS) do
                        if neutralize_hazard_field(obj, prop, players, reason or class_name) then total = total + 1 end
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

-- Level 232: improve the sell-price chain for >6 players. BET 0.14.6's own patch
-- notes confirm price scaling is an earned-percentage mechanic, so for larger groups
-- we scale ONLY the global ScaledPricePercent upward from its first observed runtime
-- value, linearly by players/6. This remains a no-op at <=6.
--
-- v2.19.6: scale a SINGLE lever, not three. The sell price multiplies
-- LaneMultiplier x CouponMultiplier x ScaledPricePercent, so scaling all three by
-- players/6 (as v2.19.3-2.19.5 did) compounded to factor^2..factor^3 income — a
-- 4x-8x over-compensation at 12 players that violated "same difficulty as 6 players".
-- LaneMultiplier / CouponMultiplier are now left at their vanilla per-lane values.
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
                            safe("S232R_SP_W", function() obj.ScaledPricePercent = target return true end)
                            -- Verify the write stuck (the game may clamp ScaledPricePercent),
                            -- mirroring scale_supply_number / cap_requirement_prop.
                            local now = safe("S232R_SP_V", function() return obj.ScaledPricePercent end)
                            if type(now) == "number" and now >= target then
                                total = total + 1
                                log(string.format("[S232] GameState.ScaledPricePercent %.2f -> %.2f (base=%.2f factor=%.2f %s)",
                                    sp, target, base, factor, object_label(obj)))
                                safe("S232R_SP_FNU", function() obj:ForceNetUpdate() return true end)
                            else
                                log(string.format("[S232] GameState.ScaledPricePercent write did not stick (sp=%.2f target=%.2f actual=%s)",
                                    sp, target, tostring(now)))
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
                        -- v2.19.10: READ-ONLY difficulty probe. Level 232 has NO player-count
                        -- scaling field, so any big-group relief must be calibrated from these
                        -- runtime values (time/throughput/monsters), never guessed blind.
                        local dn = find_first_instance("Level232DayNightManager")
                        if dn then
                            log(string.format("[S232] timer: TimeLimit=%s TimeRemaining=%s DayAmount=%s CurrentDay=%s WarnTime=%s",
                                tostring(safe("S232_TL", function() return dn.TimeLimit end)),
                                tostring(safe("S232_TR", function() return dn:GetTimeRemaining() end)),
                                tostring(safe("S232_DA", function() return dn.DayAmount end)),
                                tostring(safe("S232_DI", function() return dn.CurrentDayIndex end)),
                                tostring(safe("S232_WT", function() return dn.DayCycleWarningTime end))))
                        end
                        local lanes = safe("S232_LF", function() return FindAllOf("AALevel232CheckoutLane") end)
                        if lanes then
                            local nlanes, sample = 0, nil
                            for _, ln in pairs(lanes) do
                                if is_real_instance(ln) then
                                    nlanes = nlanes + 1
                                    if not sample then
                                        sample = string.format("SellDuration=%s LaneMult=%s Coupon=%s",
                                            tostring(safe("S232_SD", function() return ln.SellDuration end)),
                                            tostring(safe("S232_LM", function() return ln.LaneMultiplier end)),
                                            tostring(safe("S232_CM", function() return ln.CouponMultiplier end)))
                                    end
                                end
                            end
                            log(string.format("[S232] checkout: lanes=%d (%s)", nlanes, sample or "n/a"))
                        end
                        local cm232 = find_first_instance("Level232ChunkManager")
                        if cm232 then
                            log(string.format("[S232] monsters: FacelingChunkInterval=%s FacelingTargetPerChunk=%s GroceryRobots=%s",
                                tostring(safe("S232_FCI", function() return cm232.FacelingSpawnChunkInterval end)),
                                tostring(safe("S232_FTP", function() return cm232.FacelingMarkerTargetCountPerChunk end)),
                                tostring(safe("S232_GR", function() return cm232.NumGroceryStoreRobots end))))
                        end
                        s232_price_logged = true
                    end
                end
            end
        end
    end
    if not s232_live then return 0 end
    return total
end

-- v2.19.10: READ-ONLY probe of Level -1 shadow-spawn scaling. EntitySpawnChancePerPlayer
-- scales monster pressure UP with player count (bounded by MaxShadowSpawnAmount) — the one
-- monster field that provably makes >6 harder than 6. Logged once per level so we can decide
-- whether to neutralize it to the 6-player level and whether MaxShadowSpawnAmount already
-- saturates at <=6 (which would make a cap a near-no-op). No writes — diagnostics only.
local neg1_diag_logged = false
local function probe_neg1_difficulty(reason)
    if neg1_diag_logged or not is_host_authority() then return 0 end
    local mgr = find_first_instance("LevelNeg1Manager")
    if not mgr then return 0 end
    neg1_diag_logged = true
    log(string.format("[NEG1] diagnostics (%s): EntitySpawnChancePerPlayer=%s MaxShadowSpawnAmount=%s MinSpawnDist=%s MaxSpawnDist=%s players=%d",
        reason or "monitor",
        tostring(safe("Neg1_ESC", function() return mgr.EntitySpawnChancePerPlayer end)),
        tostring(safe("Neg1_MAX", function() return mgr.MaxShadowSpawnAmount end)),
        tostring(safe("Neg1_MIN", function() return mgr.MinSpawnDistance end)),
        tostring(safe("Neg1_MAXD", function() return mgr.MaxSpawnDistance end)),
        effective_player_count()))
    return 0
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

-- Shared skeleton for the "self-based" objective-cap hooks: unwrap the hooked
-- object from `self`, then on the game thread (host-only, ENABLE_OBJECTIVE_CAP)
-- run `body(obj, path)`. `label` is only the safe()/error-log prefix. The four
-- callers below differ ONLY in that prefix and `body`, so this collapses what used
-- to be four character-for-character identical boilerplate blocks into one.
local function register_self_obj_hook(path, label, body)
    local ok = safe(label .. path, function()
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
                body(obj, path)
            end)
        end)
        return true
    end)
    log(ok and ("[OBJCAP] hook registered: " .. path) or ("[OBJCAP] hook unavailable: " .. path))
end

local function register_cap_hook(path, props)
    register_self_obj_hook(path, "ObjCapHook_", function(obj)
        for prop, cap in pairs(props) do
            cap_requirement_prop(obj, prop, cap, path)
        end
    end)
end

local function register_objective_cap_hook(path)
    register_cap_hook(path, ELEVATOR_PROPS)
end

local function register_generic_objective_hook(path)
    register_self_obj_hook(path, "ObjCapHook_", function(obj)
        cap_level_objective_array(obj, "CurrentObjectives", path)
    end)
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
    register_supply_scale_hook("/Script/BETGame.BETChunkManagerBase:GenerateChunks")
    register_generic_objective_hook("/Script/BETGame.MultiplayerGameState:OnRep_CurrentObjectives")
    -- Re-assert the generic objective cap when the game re-evaluates quota mid-level.
    register_generic_objective_hook("/Script/BETGame.Level232GameState:OnRep_CurrentQuota")
    register_all_players_gate_hook("/Script/BETGame.LevelExitBase:OnSurvivorOverlap")
    register_all_players_gate_hook("/Script/BETGame.LevelExitBase:OnAllPlayersPresent")
    register_all_players_gate_hook("/Script/BETGame.InteractableTeleporter:OnActivationStateChange")
    register_all_players_gate_hook("/Script/BETGame.InteractableTeleporter:AreAllPlayersPresent")
end

ExecuteInGameThread(function()
    pcall(ensure_objective_cap_hooks)
    pcall(cap_known_objective_requirements, "startup")
    pcall(cap_proportional_requirements, "startup")
    pcall(neutralize_player_scaled_hazards, "startup")
    pcall(cap_level6_puzzle_scale, "startup")
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
-- Cluster-settling state for the spawn fix. MUST be declared HERE, before
-- reset_per_level_state() below, so that function's `last_median_z = nil` /
-- `settled_reads = 0` bind to these file-scope upvalues. If they were declared
-- only after the function (as they used to be), those assignments would leak to
-- GLOBALS while try_spawn_fix kept reading the locals — so the settling gate
-- never reset across a level/world transition. try_spawn_fix is defined far
-- below and captures these same upvalues.
local last_median_z = nil
local settled_reads = 0

-- Live world identity, used to detect GAME-DRIVEN level transitions (the in-game
-- elevator, a lobby return, or a fresh run from a cleared save) — not just the
-- mod's own Ctrl+K/L/J. Without this, level_detected latches true on the first
-- gameplay level and the immediate full cap/scale pass (Phase 1) plus the
-- per-level base maps never re-arm. A second playthrough could then leave a
-- freshly spawned level's requirements uncapped and reuse stale supply bases
-- keyed by a re-used object name. See docs/research/known_issues.md.
local last_world_name = nil
local function current_world_name()
    if not UEHelpers then return nil end
    return safe("CurWorldName", function()
        local w = UEHelpers.GetWorld()
        if w and w:IsValid() then return w:GetName() end
        return nil
    end)
end

-- Re-arm per-level state so the next monitor tick re-detects the level and
-- re-runs the full immediate cap/scale pass. Clears only the per-level *log-dedup*
-- maps (so a re-detected level re-logs its caps) and the spawn/settle state.
--
-- IMPORTANT: does NOT clear `supply_scaled_original` (or `requirement_cap_original`).
-- Both hold the FIRST-OBSERVED runtime value per object (keyed by full object path) and
-- are the anchors that keep scaling/capping idempotent — `scale_supply_number` always
-- scales `base * factor` and `cap_proportional_requirement` always caps `base * 6/players`,
-- never the already-modified value. Wiping them here would let a re-detect re-capture an
-- already-modified value as the new base and compound (supply: factor² up; requirement:
-- (6/players)² down). Stale entries for unloaded objects are harmless: new objects get new
-- paths, and if an object genuinely persists across a reset its true first-observed base is
-- exactly what we want to keep.
-- Safe: this only ever forces caps/scales to be re-applied; it never removes a cap.
local function reset_per_level_state(reason)
    spawn_fix_applied = false
    level_detected = false
    last_median_z = nil
    settled_reads = 0
    objective_cap_changed = {}
    objective_cap_hook_fired = {}
    s232_price_logged = false
    neg1_diag_logged = false
    l6_scale_logged = false
    log("[STATE] per-level state re-armed (" .. tostring(reason) .. ")")
end

-- v2.4 cluster-fix tunables (RELATIVE detection — no absolute floor constants).
-- CONFIRMED model: correct players spawn in an elevator + ride a cutscene down,
-- ending tightly CLUSTERED. A mis-spawned player is dropped at a Neg1 PlayerStart
-- ~one floor-gap (~8000u) away. Runtime coords are in a DIFFERENT frame than
-- PlayerStart coords (~+8500 offset), so absolute-Z thresholds are useless.
local CLUSTER_GAP   = 2500   -- |Z-median| beyond this = outlier (jitter ~100s; floor gap ~8000)
local SETTLE_TOL    = 300    -- median Z must move < this between reads to count as "settled"
local MIN_CLUSTER   = 2      -- majority must have at least this many to be trusted
local FIX_MAX_TICKS = 8      -- only attempt fix within this many ticks of level detect
                             -- (after that, a far player likely WENT to Neg1 legitimately)
-- (last_median_z / settled_reads are declared above, before reset_per_level_state,
--  so the reset binds to them as upvalues instead of creating stray globals.)

-- v2.14 host noclip-nudge: step size per Ctrl+Arrow / Ctrl+PageUp-Down keypress.
-- teleport_pawn snaps with bSweep=false,bTeleport=true (no collision sweep), so a
-- nudge can push the host THROUGH geometry — used to work around a spot where a
-- 7+ player count can't progress normally. Horizontal is CAMERA-RELATIVE (forward =
-- where you look), computed from control-rotation yaw. Keep small to stay on-tile.
local NUDGE_STEP   = 100   -- horizontal world units per Ctrl+Arrow
local NUDGE_STEP_Z = 100   -- vertical world units per Ctrl+PageUp/PageDown

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
local summon_after_travel = false  -- set true on travel so post-load we log a "press Ctrl+G" hint

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
    -- reset spawn-fix state so the auto-fix re-arms in the new level
    reset_per_level_state(tag)
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
    -- re-arm per-level state so spawn-fix + detection run again on reload
    reset_per_level_state("Ctrl+J reload")
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
-- Reuses ELEVATOR_CLASSES (defined above for the presence-gate cap) — same class list.
local function find_elevator()
    for _, n in ipairs(ELEVATOR_CLASSES) do
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

    -- Phase 0: Detect a GAME-DRIVEN level transition. The mod's own Ctrl+K/L/J
    -- re-arm per-level state, but a level finished through the in-game elevator,
    -- a return to the lobby, or a fresh run from a cleared save does not. Without
    -- this, level_detected stays latched and the immediate full cap/scale pass
    -- never re-fires on a second playthrough, leaving the new level's
    -- requirements uncapped and reusing stale supply bases. Watch the live world
    -- name and re-arm when it changes. See docs/research/known_issues.md.
    local wname = current_world_name()
    if wname and wname ~= "" then
        if last_world_name == nil then
            last_world_name = wname
        elseif wname ~= last_world_name then
            log("[STATE] world changed: " .. tostring(last_world_name) .. " -> " .. tostring(wname))
            last_world_name = wname
            if level_detected then reset_per_level_state("world-change") end
        end
    end

    -- Phase 1: Detect game level (CDO-filtered, gameplay-specific signal only)
    if not level_detected then
        local detected, via = in_gameplay_level()
        if detected then
            level_detected = true
            level_detect_time = diag_tick
            log("[DIAG] Game level detected via " .. tostring(via) .. " at tick " .. diag_tick)
            -- We're in a real level: (re)register objective-cap hooks, run one immediate
            -- cap/scale pass, then arm the host keybinds.
            ensure_objective_cap_hooks()
            cap_known_objective_requirements("level-detect")
            cap_proportional_requirements("level-detect")
            neutralize_player_scaled_hazards("level-detect")
            cap_level6_puzzle_scale("level-detect")
            scale_supply_for_more_players("level-detect")
            cap_all_players_gates("level-detect")
            cap_s232_price("level-detect")
            probe_neg1_difficulty("level-detect")
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
    -- (No "Phase 2": that was the pre-detect post-travel summon-arm, removed in v2.10.)
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
        cap_proportional_requirements("monitor")
        neutralize_player_scaled_hazards("monitor")
        cap_level6_puzzle_scale("monitor")
        scale_supply_for_more_players("monitor")
        cap_all_players_gates("monitor")
        cap_s232_price("monitor")
        probe_neg1_difficulty("monitor")
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
log("[OBJCAP] Player-scaled requirements are capped at " .. OBJECTIVE_CAP .. " (generic objectives " .. GENERIC_OBJECTIVE_CAP .. ", session cap remains " .. TARGET_CAP .. ")")
log("[ADAPT] UEHelpers " .. (UEHelpers and "loaded" or "NOT FOUND — host-anchor disabled, will use cluster median"))
