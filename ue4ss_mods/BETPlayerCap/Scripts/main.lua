local MOD_NAME = "BETPlayerCap"
local TARGET_CAP = 12
local VERSION = "2.10-gather-fix"

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

-- v2.8 post-travel summon timing. The 2026-05-31 7-player level-switch test showed
-- the OLD post-travel summon firing too early: right after Ctrl+H it tried to gather
-- while the host pawn wasn't re-resolved yet ("Could not resolve host pawn — aborting"
-- on Level 3/4) and while stuck players hadn't possessed (only 5 of 7 readable on
-- Level 1). So instead of a fixed "2 ticks after detect", we now WAIT for the group to
-- actually be present + the host pawn resolvable, retrying for a bounded window, then
-- summon ONCE. This avoids yanking a half-loaded group around.
local SUMMON_WAIT_TICKS = 6     -- give the new level up to this many ticks to settle
local summon_wait_count = 0     -- ticks waited so far for the current armed summon

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
    summon_wait_count = 0
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
-- Like Ctrl+H it carries all clients via seamless ProcessServerTravel; it also arms
-- the same post-travel auto-summon so the group re-gathers on reload.
local function reload_current_level()
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
    scan_done = false
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

-- Ctrl+P: READ-ONLY probe. Logs the live elevator's real gate values + box
-- geometry so we confirm the count-gate model BEFORE cramming. No side effects
-- beyond the (read-only) predicate call.
local function probe_elevator()
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
    log("[PROBE] CheckForPlayersInElevator() -> " .. tostring(r)
        .. " ; possessed=" .. tostring(#collect_players()))
end

-- Ctrl+K: cram EVERY possessed player (incl. host) into the elevator trigger box
-- in a tight ring, then ask the game's own gate to re-evaluate. Never forces
-- StartElevator or writes the counter -- the game's authoritative code decides.
local function board_elevator()
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
        RegisterKeyBind(Key.P, {ModifierKey.CONTROL}, function()
            ExecuteInGameThread(function() pcall(probe_elevator) end)
        end)
    end)
    if ok then
        probe_bound = true
        log("[PROBE] Host keybind registered: Ctrl+P = read elevator gate (probe)")
    else
        log("[PROBE] RegisterKeyBind failed — probe keybind unavailable")
    end
end

local board_bound = false
local function ensure_board_keybind()
    if board_bound then return end
    local ok = pcall(function()
        RegisterKeyBind(Key.K, {ModifierKey.CONTROL}, function()
            ExecuteInGameThread(function() pcall(board_elevator) end)
        end)
    end)
    if ok then
        board_bound = true
        log("[BOARD] Host keybind registered: Ctrl+K = cram all players into elevator")
    else
        log("[BOARD] RegisterKeyBind failed — board keybind unavailable")
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
            ensure_reload_keybind()
            ensure_probe_keybind()
            ensure_board_keybind()
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
log("[RELOAD] Host keybind Ctrl+J (reload current level, un-stick loading) will arm once in a real level")
log("[PROBE] Host keybind Ctrl+P (read elevator gate, READ-ONLY probe) will arm once in a real level")
log("[BOARD] Host keybind Ctrl+K (cram all players into elevator) will arm once in a real level")
log("[ADAPT] UEHelpers " .. (UEHelpers and "loaded" or "NOT FOUND — host-anchor disabled, will use cluster median"))
