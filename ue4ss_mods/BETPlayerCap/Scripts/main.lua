local MOD_NAME = "BETPlayerCap"
local TARGET_CAP = 12
local VERSION = "2.4-cluster-fix"

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

log("v" .. VERSION .. " loaded - target cap: " .. TARGET_CAP)

---------------------------------------------------------------------------
-- ADAPTIVE CLASS DETECTION
-- Try exact names first, fall back to parent classes if game updates
---------------------------------------------------------------------------
local CLASS_NAMES = {
    widget = {"BETMultiplayerSettingsWidget"},
    gamemode = {"BP_Level0GameMode_C", "BETGameMode", "GameModeBase"},
    character = {"BP_Survivor_Character_C", "SurvivorCharacter", "Character"},
    playerstart = {"BETPlayerStart", "PlayerStart"},
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
---------------------------------------------------------------------------
local widget_props = {
    "MaxSelectablePlayers", "DefaultMaxPlayers", "SelectedMaxPlayers"
}

local function apply_overrides()
    local wclass = resolve_class("widget")
    local widget = safe("FindWidget", function()
        return FindFirstOf(wclass)
    end)
    if not widget then return end

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

---------------------------------------------------------------------------
-- SPAWN FIX: Dynamic coordinate detection + delayed teleport
---------------------------------------------------------------------------
local spawn_fix_applied = false
local level_detected = false
local level_detect_time = 0
local diag_tick = 0
local scan_done = false

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

-- Dynamic spawn data (populated at runtime from actual PlayerStart objects)
local level0_spawns = {}
local level0_z = nil
local neg1_threshold_z = nil

-- Hardcoded fallback (only used if dynamic detection fails entirely)
local FALLBACK_SPAWNS = {
    {X = -333, Y = -333, Z = -8400},
    {X = -333, Y = 0,    Z = -8400},
    {X = -333, Y = 333,  Z = -8400},
    {X = 0,    Y = -333, Z = -8400},
    {X = 0,    Y = 0,    Z = -8400},
    {X = 0,    Y = 333,  Z = -8400},
    {X = 333,  Y = -333, Z = -8400},
    {X = 333,  Y = 0,    Z = -8400},
    {X = 333,  Y = 333,  Z = -8400},
}
local FALLBACK_LEVEL0_Z = -8400
local FALLBACK_THRESHOLD_Z = -8100

local next_spawn_idx = 1

local function get_next_spawn()
    local spawns = (#level0_spawns > 0) and level0_spawns or FALLBACK_SPAWNS
    local sp = spawns[next_spawn_idx]
    next_spawn_idx = (next_spawn_idx % #spawns) + 1
    return sp
end

local function scan_player_starts()
    local psclass = resolve_class("playerstart")
    local starts = safe("ScanStarts", function()
        return FindAllOf(psclass)
    end)
    if not starts then return false end

    local l0_positions = {}
    local neg1_positions = {}
    local l0_count = 0
    local neg1_count = 0

    for idx, ps in pairs(starts) do
        if is_real_instance(ps) then
        local name = safe("PSName", function()
            return ps:GetFullName()
        end)
        local loc = get_actor_pos(ps, "PSLoc")

        if name and loc and loc.Z then
            local name_str = tostring(name)
            if string.find(name_str, "Level0Checkpoint")
                or string.find(name_str, "Checkpoint") then
                l0_count = l0_count + 1
                l0_positions[#l0_positions + 1] = {
                    X = loc.X, Y = loc.Y, Z = loc.Z
                }
            elseif string.find(name_str, "Neg1")
                or string.find(name_str, "Neg") then
                neg1_count = neg1_count + 1
                neg1_positions[#neg1_positions + 1] = {
                    X = loc.X, Y = loc.Y, Z = loc.Z
                }
            end
        end
        end
    end

    log(string.format("[ADAPT] Scanned PlayerStarts: Level0=%d Neg1=%d",
        l0_count, neg1_count))

    if l0_count > 0 then
        level0_spawns = l0_positions
        -- Derive Z threshold dynamically:
        -- Level0 Z is the average Z of checkpoint spawns
        local z_sum = 0
        for _, pos in ipairs(l0_positions) do
            z_sum = z_sum + pos.Z
        end
        level0_z = z_sum / #l0_positions

        -- Threshold: midpoint between Level0 Z and the highest Neg1 Z
        if neg1_count > 0 then
            local max_neg1_z = -999999
            for _, pos in ipairs(neg1_positions) do
                if pos.Z > max_neg1_z then max_neg1_z = pos.Z end
            end
            neg1_threshold_z = (level0_z + max_neg1_z) / 2
        else
            -- No Neg1 found, use offset from Level0
            neg1_threshold_z = level0_z + 300
        end

        log(string.format("[ADAPT] Dynamic: Level0_Z=%.0f Threshold_Z=%.0f Spawns=%d",
            level0_z, neg1_threshold_z, #level0_spawns))
        return true
    end

    return false
end

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

-- Collect every real, POSSESSED in-level character with a readable position.
-- Possession (Controller present) is the gate that excludes lobby/CDO/spectator
-- pawns. Garbage reads (Z==0 sentinel, unreadable) are dropped.
local function collect_players()
    local charclass = resolve_class("character")
    local chars = safe("CollectFind", function() return FindAllOf(charclass) end)
    local out = {}
    if not chars then return out end
    for _, char in pairs(chars) do
        if is_real_instance(char) then
            local ctrl = safe("CollCtrl", function()
                local c = char.Controller
                if c and c:IsValid() then return c end
                return nil
            end)
            if ctrl then
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
    return out
end

-- RELATIVE cluster-outlier teleport. Target = the MAJORITY cluster's median
-- runtime position (NOT a PlayerStart constant — runtime frame differs by ~+8500).
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

    -- Cluster median XY/Z = the teleport target (same frame as the players).
    local cxs, cys, czs = {}, {}, {}
    for i = 1, #cluster do
        cxs[i] = cluster[i].X; cys[i] = cluster[i].Y; czs[i] = cluster[i].Z
    end
    local tx, ty, tz = median(cxs), median(cys), median(czs)
    log(string.format("[SPAWN] Cluster=%d @ (%.0f,%.0f,%.0f); outliers=%d",
        #cluster, tx, ty, tz, #outliers))

    local fixed = 0
    for i = 1, #outliers do
        local o = outliers[i]
        -- small spread so multiple outliers don't stack on one point
        local ox = tx + ((i - 1) % 3) * TP_XY_SPREAD
        local oy = ty + math.floor((i - 1) / 3) * TP_XY_SPREAD
        log(string.format("[SPAWN] Outlier '%s' at Z=%.0f -> target (%.0f,%.0f,%.0f)",
            o.name, o.Z, ox, oy, tz))
        local ok = safe("TP_" .. i, function()
            o.char:K2_SetActorLocation({X = ox, Y = oy, Z = tz}, false, {}, false)
            return true
        end)
        if not ok then
            ok = safe("TP2_" .. i, function()
                o.char:K2_TeleportTo({X = ox, Y = oy, Z = tz},
                    {Pitch = 0, Yaw = 0, Roll = 0})
                return true
            end)
        end
        -- Verify the write actually moved the actor (writes historically unverified)
        local after = get_actor_pos(o.char, "TPchk" .. i)
        if after and after.Z and math.abs(after.Z - tz) <= CLUSTER_GAP then
            fixed = fixed + 1
            log(string.format("[SPAWN] OK '%s' now Z=%.0f (verified)", o.name, after.Z))
        else
            local az = (after and after.Z) or -999999
            log(string.format("[SPAWN] WRITE FAILED/UNVERIFIED '%s' Z=%.0f (apply=%s)",
                o.name, az, tostring(ok)))
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
        else
            return
        end
    end

    -- Phase 2: Scan PlayerStarts — retry each tick until it succeeds
    -- (PlayerStart actors may not be fully replicated on the very first tick)
    if not scan_done then
        scan_done = scan_player_starts()
        if not scan_done then
            log("[ADAPT] PlayerStart scan not ready yet, will retry (fallback coords meanwhile)")
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

    -- Phase 4: Periodic diagnostics (every 30s = every 3rd tick).
    -- Cluster-RELATIVE classification: the old absolute -8150 threshold is
    -- meaningless (runtime frame differs from PlayerStart frame). We report each
    -- player's Z plus its distance from the group median.
    if diag_tick % 3 == 0 then
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
