local MOD_NAME = "BETPlayerCap"
local TARGET_CAP = 12
local VERSION = "2.6-levelswitch"

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

-- v2.6 LEVEL-SWITCH (test tool). BET travels between levels via ProcessServerTravel
-- (seamless), confirmed in BET.log. We use the same path so all clients are carried
-- along (no drop). Ctrl+H steps to the next map in LEVEL_MAPS below.
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
-- bypasses the lobby start + elevator + ending-path, so OBJECTIVES may not init.
-- This is a SPAWN/travel TEST AID only — see docs/level_structure.md.
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
local level_cycle_idx = 0          -- 0 = before first press; advances each Ctrl+H
local summon_after_travel = false  -- set true on travel so post-load we auto-gather
local travel_arm_tick = 0          -- tick when we armed the post-travel summon

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

---------------------------------------------------------------------------
-- HOST ANCHOR + SHARED TELEPORT (v2.5)
-- Level-INDEPENDENT: the host (listen-server authority) always spawns with
-- the group on any level, standing in valid walkable geometry. Their live
-- runtime position is the gather target — no per-level coords, no PlayerStart
-- frame offset. Confirmed primitives on THIS build: K2_GetActorLocation reads,
-- K2_SetActorLocation writes+replicates to remote clients (v2.4 live test),
-- RegisterKeyBind + K2_SetActorLocationAndRotation (shipped SplitScreenMod).
---------------------------------------------------------------------------

-- Resolve the host pawn (local PlayerController's Pawn). Re-resolve every time
-- (pawns are recreated across travel/respawn — never cache).
local function get_host_pawn()
    if not UEHelpers then return nil end
    local pc = safe("HostPC", function() return UEHelpers.GetPlayerController() end)
    if not pc or not is_real_instance(pc) then return nil end
    local pawn = safe("HostPawn", function()
        local p = pc.Pawn
        if p and p:IsValid() then return p end
        return nil
    end)
    return pawn
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

-- Ring offset around an anchor so N pawns don't stack on one point (telefrag).
local function ring_dest(anchor, i, n)
    if n <= 1 then
        return {X = anchor.X, Y = anchor.Y, Z = anchor.Z + 50}
    end
    local R = 150
    local theta = (i - 1) * (2 * math.pi / n)
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
    -- Exclude the host pawn itself from the move list.
    local others = {}
    for i = 1, #players do
        if players[i].char ~= host then others[#others + 1] = players[i] end
    end
    local n = #others
    log(string.format("[SUMMON] Host @ (%.0f,%.0f,%.0f); gathering %d players",
        anchor.X, anchor.Y, anchor.Z, n))
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
-- Lets Ctrl+H "step from where we actually are" rather than from a stale counter.
-- MUST stay parallel (same order) with LEVEL_MAPS above. Gamemode class names
-- confirmed from BETGame.hpp / docs/level_structure.md.
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

-- Ctrl+H: cycle to the NEXT level (relative to the one we're actually in, if
-- detectable; else relative to our own counter). Arms a post-travel summon so
-- everyone is gathered on arrival.
local function cycle_next_level()
    local cur = detect_current_level_idx() or level_cycle_idx
    local nxt = (cur % #LEVEL_MAPS) + 1
    level_cycle_idx = nxt
    summon_after_travel = true
    travel_arm_tick = diag_tick
    -- reset spawn-fix state so the auto-fix re-arms in the new level
    spawn_fix_applied = false
    level_detected = false
    scan_done = false
    last_median_z = nil
    settled_reads = 0
    log(string.format("[LEVELSW] Ctrl+H: level %d -> %d (%s)",
        cur, nxt, LEVEL_MAPS[nxt]))
    server_travel(LEVEL_MAPS[nxt])
end

local levelsw_bound = false
local function ensure_levelsw_keybind()
    if levelsw_bound then return end
    local ok = pcall(function()
        RegisterKeyBind(Key.H, {ModifierKey.CONTROL}, function()
            ExecuteInGameThread(function() pcall(cycle_next_level) end)
        end)
    end)
    if ok then
        levelsw_bound = true
        log("[LEVELSW] Host keybind registered: Ctrl+H = cycle to next level (test tool)")
    else
        log("[LEVELSW] RegisterKeyBind failed — level-switch keybind unavailable")
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
            ensure_summon_keybind()
            ensure_levelsw_keybind()
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

    -- Phase 3b: post-Ctrl+H travel auto-summon. After a level switch we arm a
    -- gather so everyone ends up together on arrival. Wait a few ticks after the
    -- new level is detected (let pawns possess + settle), then summon once.
    if summon_after_travel and level_detected and (diag_tick - level_detect_time) >= 2 then
        log("[LEVELSW] Post-travel auto-summon")
        pcall(summon_all_to_host)
        summon_after_travel = false
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
log("[SUMMON] Host keybind Ctrl+G (gather all players to host) will arm once in a real level")
log("[LEVELSW] Host keybind Ctrl+H (cycle to next level, TEST tool) will arm once in a real level")
log("[ADAPT] UEHelpers " .. (UEHelpers and "loaded" or "NOT FOUND — host-anchor disabled, will use cluster median"))
