kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

-- ============================================================================
-- SOUND CUSTOMIZATION (Plays ONLY when Mechanical Saw is actively running)
-- ============================================================================
local SOUND_CONFIG = {
    ENABLE_SOUND            = true,
    SOUND_NAME              = "saw",       
    SOUND_FALLBACK          = "default_dig_cracky", 
    SOUND_GAIN              = 0.25,                 
    CUTTING_GAIN_MULT       = 1.35,                 
    SOUND_PITCH             = 0.80,                 
    SCALE_PITCH_WITH_RPM    = true,                 
    MIN_PITCH               = 0.70,                 
    MAX_PITCH               = 1.40,                 
    SOUND_INTERVAL          = 34.0,                 
    MAX_HEAR_DISTANCE       = 12,                   
    SOUND_ONLY_WHEN_CUTTING = false,                
    ENABLE_CUT_FINISH_SOUND = true,                 
    CUT_FINISH_SOUND        = "default_dig_choppy", 
    CUT_FINISH_GAIN         = 0.80,                 
}

local CONFIG = {
    BLADE_FACES_PLAYER            = true,
    MIN_RPM                       = 32,
    KU_PER_RPM                    = 4,
    MIN_KU                        = 16,
    MAX_KU                        = 128,
    MAX_RPM_CAP                   = 3072,
    ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    shaft_len = 0.85, blade_len = 0.55 },
        { name = "slow",   max_rpm = 15,   shaft_len = 0.48, blade_len = 0.34 },
        { name = "medium", max_rpm = 63,   shaft_len = 0.24, blade_len = 0.20 },
        { name = "fast",   max_rpm = 255,  shaft_len = 0.11, blade_len = 0.10 },
        { name = "hyper",  max_rpm = 1024, shaft_len = 0.05, blade_len = 0.05 },
        { name = "ultra",  max_rpm = 3072, shaft_len = 0.03, blade_len = 0.03 },
    },
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    TICK_INTERVAL                 = 0.20,
    CUT_TIME_AT_5_RPM             = 0.80,
    CUT_TIME_AT_512_RPM           = 0.20,
    MAX_TREE_FELL_BLOCKS          = 256,
    TREE_LEAF_RADIUS              = 5,
    DAMAGE_HP                     = 2,
    DAMAGE_INTERVAL_SEC           = 1.0,
    DAMAGE_RADIUS                 = 0.75,
    TEX_STONECUTTER_TOP           = "mcl_stonecutter_top.png",
    TEX_STONECUTTER_BOT           = "mcl_stonecutter_bottom.png",
    TEX_STONECUTTER_SIDE          = "mcl_stonecutter_side.png",
    TEX_STONECUTTER_SAW           = "mcl_stonecutter_saw.png",
    TEX_SHAFT_OVERLAY             = "kinetica_shaft_connecting_overlay.png",
}

local IDLE_NAME = "kinetica:mechanical_saw"
local ACT_CW    = "kinetica:mechanical_saw_active_cw"
local ACT_CCW   = "kinetica:mechanical_saw_active_ccw"

local function resolve_sound_name(cfg)
    if cfg.SOUND_NAME and cfg.SOUND_NAME ~= "" then
        local f = io.open(modpath .. "/sounds/" .. cfg.SOUND_NAME .. ".ogg", "r")
        if f then f:close(); return cfg.SOUND_NAME end
    end
    if cfg.SOUND_FALLBACK and cfg.SOUND_FALLBACK ~= "" then return cfg.SOUND_FALLBACK end
    return cfg.SOUND_NAME
end

local RESOLVED_SOUND = resolve_sound_name(SOUND_CONFIG)

local function play_saw_active_sound(pos, meta, rpm, is_cutting, dt)
    if not SOUND_CONFIG.ENABLE_SOUND or not RESOLVED_SOUND or RESOLVED_SOUND == "" then return end
    if SOUND_CONFIG.SOUND_ONLY_WHEN_CUTTING and not is_cutting then return end

    local acc = meta:get_float("sfx_timer") + (dt or CONFIG.TICK_INTERVAL)
    if acc < (SOUND_CONFIG.SOUND_INTERVAL or 1.00) then
        meta:set_float("sfx_timer", acc)
        return
    end
    meta:set_float("sfx_timer", 0)

    local pitch = SOUND_CONFIG.SOUND_PITCH or 0.80
    if SOUND_CONFIG.SCALE_PITCH_WITH_RPM then
        local t = kinetica.api and kinetica.api.math.rpm_factor(rpm, CONFIG.MIN_RPM, 512) or 0
        local min_p, max_p = SOUND_CONFIG.MIN_PITCH or 0.70, SOUND_CONFIG.MAX_PITCH or 1.40
        pitch = min_p + t * (max_p - min_p)
    end

    local gain = SOUND_CONFIG.SOUND_GAIN or 0.25
    if is_cutting and SOUND_CONFIG.CUTTING_GAIN_MULT then gain = math.min(1.0, gain * SOUND_CONFIG.CUTTING_GAIN_MULT) end

    core.sound_play(RESOLVED_SOUND, { pos = pos, gain = gain, pitch = pitch, max_hear_distance = SOUND_CONFIG.MAX_HEAR_DISTANCE or 12 }, true)
end

local function is_saw_node(name)
    if not name then return false end
    return name == IDLE_NAME or string.sub(name, 1, #IDLE_NAME + 1) == (IDLE_NAME .. "_")
end
kinetica.is_mechanical_saw = is_saw_node

local function get_saw_demand_ku(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then return CONFIG.MIN_KU end
    return math.min(CONFIG.MAX_KU, math.max(CONFIG.MIN_KU, math.floor(rpm * CONFIG.KU_PER_RPM)))
end

local function get_required_cut_seconds(rpm)
    if not rpm or rpm <= 0 then return CONFIG.CUT_TIME_AT_5_RPM end
    local rfactor = kinetica.api and kinetica.api.math.rpm_factor(rpm, 5, 512) or 0
    return CONFIG.CUT_TIME_AT_5_RPM - rfactor * (CONFIG.CUT_TIME_AT_5_RPM - CONFIG.CUT_TIME_AT_512_RPM)
end

local function get_anim_tier_name(rpm)
    local clamped = math.min(CONFIG.MAX_RPM_CAP, math.max(0, rpm or 0))
    for _, tier in ipairs(CONFIG.ANIM_TIERS) do
        if clamped <= tier.max_rpm then return tier.name end
    end
    return CONFIG.ANIM_TIERS[#CONFIG.ANIM_TIERS].name
end

local function get_active_saw_node_name(rpm, spin_dir)
    local tier_name = get_anim_tier_name(rpm)
    local dir_tag   = (spin_dir == 1) and "cw" or "ccw"
    local candidate = IDLE_NAME .. "_" .. tier_name .. "_" .. dir_tag
    return core.registered_nodes[candidate] and candidate or ((spin_dir == 1) and ACT_CW or ACT_CCW)
end

local function cleanup_legacy_blade_entities(pos)
    for _, obj in ipairs(core.get_objects_inside_radius(pos, 1.0)) do
        local luaent = obj:get_luaentity()
        if luaent and luaent.name == "kinetica:mechanical_saw_blade" then obj:remove() end
    end
end

local AXIS_TO_BLADE_DIR = { [0] = {x = 0, y = 1, z = 0}, [1] = {x = 0, y = 0, z = 1}, [2] = {x = 0, y = 0, z = -1}, [3] = {x = 1, y = 0, z = 0}, [4] = {x = -1, y = 0, z = 0}, [5] = {x = 0, y = -1, z = 0} }

local function get_blade_dir(param2)
    return AXIS_TO_BLADE_DIR[math.floor(((param2 or 0) % 24) / 4)] or AXIS_TO_BLADE_DIR[0]
end

local function get_back_dir(param2)
    local b = get_blade_dir(param2)
    return {x = -b.x, y = -b.y, z = -b.z}
end

local function get_flipped_stonecutter_param2(blade_dir)
    local axisdir = 0
    if blade_dir.y > 0 then axisdir = 0 elseif blade_dir.y < 0 then axisdir = 5 elseif blade_dir.z > 0 then axisdir = 1 elseif blade_dir.z < 0 then axisdir = 2 elseif blade_dir.x > 0 then axisdir = 3 elseif blade_dir.x < 0 then axisdir = 4 end
    if axisdir >= 1 and axisdir <= 4 then
        for rot = 0, 3 do
            local p2 = axisdir * 4 + rot
            local zdir = core.facedir_to_dir(p2)
            if zdir and zdir.y == 1 then return p2 end
        end
        for rot = 0, 3 do
            local p2 = axisdir * 4 + rot
            local zdir = core.facedir_to_dir(p2)
            if zdir and zdir.y ~= 0 then return p2 end
        end
    end
    return axisdir * 4
end

local function look_to_unit_dir(placer)
    local look = placer and placer:get_look_dir() or {x = 0, y = 0, z = 1}
    local ax, ay, az = math.abs(look.x), math.abs(look.y), math.abs(look.z)
    if ay > ax and ay > az then return {x = 0, y = (look.y > 0) and 1 or -1, z = 0}
    elseif ax >= az then return {x = (look.x > 0) and 1 or -1, y = 0, z = 0}
    else return {x = 0, y = 0, z = (look.z > 0) and 1 or -1} end
end

local function place_mechanical_saw(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then return itemstack end

    local under_pos  = pointed_thing.under
    local under_node = core.get_node(under_pos)
    local under_def  = core.registered_nodes[under_node.name]
    local sneaking   = placer and placer:is_player() and placer:get_player_control().sneak

    if under_def and under_def.on_rightclick and not sneaking then
        return under_def.on_rightclick(under_pos, under_node, placer, itemstack, pointed_thing) or itemstack
    end

    local diff = {x = pointed_thing.above.x - under_pos.x, y = pointed_thing.above.y - under_pos.y, z = pointed_thing.above.z - under_pos.z}
    local blade_dir = nil

    if not sneaking then
        if (kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(under_node.name)) or under_node.name == "kinetica:piston_head" or under_node.name == "kinetica:piston_head_sticky" or (kinetica.is_sticky_contraption_frame and kinetica.is_sticky_contraption_frame(under_node.name)) or (kinetica.has_axle_port and kinetica.has_axle_port(under_node, diff, under_pos)) then
            blade_dir = diff
        end
    end

    if not blade_dir then
        local ldir = look_to_unit_dir(placer)
        local invert = CONFIG.BLADE_FACES_PLAYER
        if sneaking then invert = not invert end
        blade_dir = invert and {x = -ldir.x, y = -ldir.y, z = -ldir.z} or ldir
    end

    local placed_stack, place_pos = core.item_place_node(itemstack, placer, pointed_thing, get_flipped_stonecutter_param2(blade_dir))

    if place_pos then
        local meta = core.get_meta(place_pos)
        meta:set_string("owner", (placer and placer.get_player_name and placer:get_player_name() or "$unknown"))
        meta:set_float("sfx_timer", 0)
    end
    return placed_stack
end

local function is_non_muddy_mangrove_root(name)
    if string.find(name, "muddy") then return false end
    return name == "mcl_mangrove:mangrove_roots" or name == "mcl_mangrove:water_logged_mangrove_roots" or (string.find(name, "mangrove_roots") ~= nil)
end

local function is_log_or_stem(name)
    if core.get_item_group(name, "tree") > 0 then return true end
    if string.find(name, "_log") or string.find(name, "_bark") or string.find(name, "_hyphae") or string.find(name, "_stem") or string.find(name, "mushroom_stem") then return true end
    return false
end

local function is_wood_block(name)
    if string.find(name, "slab") or string.find(name, "stair") or string.find(name, "fence") or string.find(name, "door") or string.find(name, "trapdoor") or string.find(name, "button") or string.find(name, "pressure_plate") or string.find(name, "sign") or string.find(name, "chest") or string.find(name, "piston") or string.find(name, "chain_drive") or string.find(name, "water_wheel") then return false end
    if core.get_item_group(name, "wood") > 0 or string.find(name, "_wood") or string.find(name, "_planks") then return true end
    return false
end

local function is_leaves_or_wart(name) return core.get_item_group(name, "leaves") > 0 or string.find(name, "leaves") ~= nil or string.find(name, "wart_block") ~= nil or name == "mcl_Mushroom:shroomlight" or string.find(name, "shroomlight") ~= nil end
local function is_mushroom_block(name) return core.get_item_group(name, "huge_mushroom") > 0 or string.find(name, "mushroom_block") ~= nil or string.find(name, "mushroom_brown") ~= nil or string.find(name, "mushroom_red") ~= nil end
local function is_cactus_or_bamboo(name) return name == "mcl_core:cactus" or core.get_item_group(name, "bamboo") > 0 or string.find(name, "cactus") ~= nil or string.find(name, "bamboo") ~= nil end
local function is_pumpkin_or_melon(name)
    if string.find(name, "stem") or string.find(name, "pie") or string.find(name, "seeds") then return false end
    return core.get_item_group(name, "pumpkin") > 0 or string.find(name, "pumpkin") ~= nil or string.find(name, "melon") ~= nil
end

local function classify_saw_target(name)
    if not name or name == "air" or name == "ignore" then return false, nil end
    if is_log_or_stem(name) or is_non_muddy_mangrove_root(name) or is_mushroom_block(name) then return true, "tree"
    elseif is_cactus_or_bamboo(name) then return true, "column"
    elseif is_wood_block(name) or is_leaves_or_wart(name) or is_pumpkin_or_melon(name) then return true, "single" end
    return false, nil
end

local function harvest_and_drop_node(target_pos, drop_pos, owner)
    if core.is_protected(target_pos, owner or "") then return false end
    local node = core.get_node(target_pos)
    if node.name == "air" or node.name == "ignore" then return false end

    local drops = core.get_node_drops(node, "mcl_tools:axe_diamond")
    core.remove_node(target_pos)
    core.check_for_falling(target_pos)

    for _, item in ipairs(drops) do
        core.add_item(drop_pos or target_pos, item)
    end
    return true
end

local NEIGHBOR_26 = {}
for dx = -1, 1 do for dy = -1, 1 do for dz = -1, 1 do if dx ~= 0 or dy ~= 0 or dz ~= 0 then table.insert(NEIGHBOR_26, {x = dx, y = dy, z = dz}) end end end end

local function is_tree_trunk_part(name) return is_log_or_stem(name) or is_non_muddy_mangrove_root(name) or is_mushroom_block(name) end
local function is_ground_support(name)
    if name == "air" or name == "ignore" or is_tree_trunk_part(name) or is_leaves_or_wart(name) then return false end
    local def = core.registered_nodes[name]
    return (def and def.walkable) or false
end

local function fell_vertical_column(start_pos, owner)
    for dy = 0, 32 do
        local cpos = {x = start_pos.x, y = start_pos.y + dy, z = start_pos.z}
        if is_cactus_or_bamboo(core.get_node(cpos).name) then harvest_and_drop_node(cpos, start_pos, owner) else break end
    end
end

local function fell_whole_tree(start_pos, owner)
    local visited, trunk_q, has_other_ground_anchor = {[core.hash_node_position(start_pos)] = true}, {start_pos}, false
    local head = 1

    while head <= #trunk_q and #trunk_q < CONFIG.MAX_TREE_FELL_BLOCKS do
        local cur = trunk_q[head]
        head = head + 1
        for _, d in ipairs(NEIGHBOR_26) do
            local np = {x = cur.x + d.x, y = cur.y + d.y, z = cur.z + d.z}
            if np.y >= start_pos.y then
                local nk = core.hash_node_position(np)
                if not visited[nk] and is_tree_trunk_part(core.get_node(np).name) then
                    visited[nk] = true
                    trunk_q[#trunk_q + 1] = np
                    if np.y <= start_pos.y and is_ground_support(core.get_node({x = np.x, y = np.y - 1, z = np.z}).name) then
                        has_other_ground_anchor = true
                    end
                end
            end
        end
    end

    if has_other_ground_anchor then harvest_and_drop_node(start_pos, start_pos, owner); return 1 end

    local leaf_q = {}
    for _, tpos in ipairs(trunk_q) do
        for _, d in ipairs(NEIGHBOR_26) do
            local lp = {x = tpos.x + d.x, y = tpos.y + d.y, z = tpos.z + d.z}
            local lk = core.hash_node_position(lp)
            if not visited[lk] and is_leaves_or_wart(core.get_node(lp).name) then
                visited[lk] = true
                leaf_q[#leaf_q + 1] = {pos = lp, dist = 1}
            end
        end
    end

    local lhead = 1
    while lhead <= #leaf_q and (#trunk_q + #leaf_q) < (CONFIG.MAX_TREE_FELL_BLOCKS * 2) do
        local cur_l = leaf_q[lhead]
        lhead = lhead + 1
        if cur_l.dist < CONFIG.TREE_LEAF_RADIUS then
            for _, d in ipairs(kinetica.directions or ALL_6_DIRS) do
                local np = {x = cur_l.pos.x + d.x, y = cur_l.pos.y + d.y, z = cur_l.pos.z + d.z}
                local nk = core.hash_node_position(np)
                if not visited[nk] and is_leaves_or_wart(core.get_node(np).name) then
                    visited[nk] = true
                    leaf_q[#leaf_q + 1] = {pos = np, dist = cur_l.dist + 1}
                end
            end
        end
    end

    local felled_count = 0
    for _, tpos in ipairs(trunk_q) do if harvest_and_drop_node(tpos, start_pos, owner) then felled_count = felled_count + 1 end end
    for _, linfo in ipairs(leaf_q) do harvest_and_drop_node(linfo.pos, start_pos, owner) end
    return felled_count
end

local function deal_saw_blade_damage(pos, blade_pos)
    local meta = core.get_meta(pos)
    local dmg_acc = meta:get_float("dmg_timer") + CONFIG.TICK_INTERVAL
    if dmg_acc < CONFIG.DAMAGE_INTERVAL_SEC then meta:set_float("dmg_timer", dmg_acc); return end
    meta:set_float("dmg_timer", 0)

    local check_center = {x = (pos.x + blade_pos.x) * 0.5, y = (pos.y + blade_pos.y) * 0.5, z = (pos.z + blade_pos.z) * 0.5}
    local hit_seen = {}
    for _, scan_pt in ipairs({check_center, blade_pos}) do
        for _, obj in ipairs(core.get_objects_inside_radius(scan_pt, CONFIG.DAMAGE_RADIUS)) do
            if not hit_seen[obj] then
                hit_seen[obj] = true
                local luaent = obj:get_luaentity()
                if obj:is_player() or (luaent and (luaent.is_mob or luaent._cmi_is_mob or luaent.health)) then
                    obj:punch(obj, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = CONFIG.DAMAGE_HP}}, nil)
                end
            end
        end
    end
end

local function make_saw_back_anim(reverse, anim_length)
    local bg, ov = CONFIG.TEX_STONECUTTER_BOT, CONFIG.TEX_SHAFT_OVERLAY
    local bg_strip = "[combine:16x64:0,0=" .. bg .. ":0,16=" .. bg .. ":0,32=" .. bg .. ":0,48=" .. bg
    local ov_strip = ov
    if reverse then
        ov_strip = "[combine:16x64:0,0=" .. ov .. "\\^[sheet\\:1x4\\:0,0:0,16=" .. ov .. "\\^[sheet\\:1x4\\:0,3:0,32=" .. ov .. "\\^[sheet\\:1x4\\:0,2:0,48=" .. ov .. "\\^[sheet\\:1x4\\:0,1"
    end
    return { name = "(" .. bg_strip .. ")^(" .. ov_strip .. ")", animation = { type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = anim_length or 0.4 } }
end

local function make_saw_z_anim(reverse, blade_length)
    local side, blade = CONFIG.TEX_STONECUTTER_SIDE, CONFIG.TEX_STONECUTTER_SAW
    local side_strip = "[combine:16x64:0,0=" .. side .. ":0,16=" .. side .. ":0,32=" .. side .. ":0,48=" .. side
    local f1, f2 = reverse and "2" or "1", reverse and "1" or "2"
    local blade_strip = "[combine:16x64:0,0=" .. blade .. "\\^[sheet\\:1x3\\:0,0:0,16=" .. blade .. "\\^[sheet\\:1x3\\:0," .. f1 .. ":0,32=" .. blade .. "\\^[sheet\\:1x3\\:0," .. f2 .. ":0,48=" .. blade .. "\\^[sheet\\:1x3\\:0," .. f1
    return { name = "(" .. side_strip .. ")^(" .. blade_strip .. ")", animation = { type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = blade_length or 0.25 } }
end

local function format_saw_glasses_info(pos, node)
    local meta      = core.get_meta(pos)
    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local demand_ku = meta:get_int("machine_demand_ku")
    if demand_ku <= 0 then demand_ku = get_saw_demand_ku(rpm) end
    local now       = math.floor(core.get_gametime())
    local is_active = (node.name ~= IDLE_NAME) and (supply_ku > 0 and rpm >= CONFIG.MIN_RPM and now < meta:get_int("lit_until"))
    local low_rpm   = (supply_ku > 0 and rpm > 0 and rpm < CONFIG.MIN_RPM and now < meta:get_int("lit_until"))

    local target_nm = meta:get_string("cut_target_name")
    local progress  = meta:get_float("cut_progress")
    local req_time  = get_required_cut_seconds(rpm)
    local pct       = (target_nm ~= "" and req_time > 0) and math.min(100, math.floor((progress / req_time) * 100)) or 0

    local state_str = "IDLE"
    if is_active then state_str = (target_nm ~= "") and string.format("CUTTING (%d%%)", pct) or "ACTIVE (Spinning)"
    elseif low_rpm then state_str = string.format("TOO SLOW (Needs >= %d RPM)", CONFIG.MIN_RPM) end

    local T = kinetica.api and kinetica.api.telemetry
    if not T then return "" end

    return table.concat({
        "┌─ ENGINEER'S GLASSES ──────────────",
        "│  Machine: Mechanical Saw",
        "│  ● STATE: " .. state_str,
        "├─ KINETIC NETWORK ─────────────────",
        T.kv_row("Speed",   string.format("%.1f RPM (Min %d RPM)", rpm, CONFIG.MIN_RPM)),
        T.kv_row("Stress",  string.format("-%d KU Load (%d / %d KU Avail)", is_active and demand_ku or 0, avail_ku, supply_ku)),
        "├─ MACHINE DETAILS ─────────────────",
        T.kv_row("Target",  (target_nm ~= "") and target_nm or "None"),
        "└───────────────────────────────────",
    }, "\n")
end

if kinetica.api and kinetica.api.telemetry then
    kinetica.api.telemetry.register_formatter(IDLE_NAME, format_saw_glasses_info)
end

local function set_saw_idle(pos, node, reason_text)
    node = node or core.get_node(pos)
    cleanup_legacy_blade_entities(pos)
    local meta = core.get_meta(pos)
    meta:set_float("cut_progress", 0); meta:set_string("cut_target_name", ""); meta:set_float("sfx_timer", 0)

    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
    else
        meta:set_string("infotext", reason_text or string.format("Mechanical Saw: Idle (Min %d RPM | Connect Shaft to Back or attach to Mechanical Piston)", CONFIG.MIN_RPM))
    end
    meta:set_string("glasses_info", format_saw_glasses_info(pos, core.get_node(pos)))
end

local function wake_saw(pos, node, rpm, spin_dir, demand_ku, avail_ku, supply_ku)
    node = node or core.get_node(pos)
    cleanup_legacy_blade_entities(pos)
    if rpm < CONFIG.MIN_RPM then set_saw_idle(pos, node, string.format("Mechanical Saw: Too Slow (%.0f RPM / Min %d RPM required!)", rpm, CONFIG.MIN_RPM)); return end
    
    local meta = core.get_meta(pos)
    meta:set_float("rpm", rpm)
    meta:set_int("spin_dir", spin_dir == 0 and 1 or spin_dir)
    if avail_ku then meta:set_int("rotational_power", avail_ku) end
    if supply_ku and supply_ku > 0 then meta:set_int("network_supply_ku", supply_ku) end
    if demand_ku and demand_ku > 0 then meta:set_int("machine_demand_ku", demand_ku) end
    meta:set_int("lit_until", math.floor(core.get_gametime()) + 4)

    local timer = core.get_node_timer(pos)
    if not timer:is_started() then timer:start(CONFIG.TICK_INTERVAL) end
end

local function saw_timer(pos, elapsed)
    local now  = math.floor(core.get_gametime())
    local meta = core.get_meta(pos)
    local node = core.get_node(pos)

    if now >= meta:get_int("lit_until") then
        if kinetica.api and kinetica.api.network.update then
            kinetica.api.network.update(pos)
        elseif kinetica.update_network then
            kinetica.update_network(pos)
        end
        node = core.get_node(pos)
    end

    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local demand_ku = meta:get_int("machine_demand_ku")
    if demand_ku <= 0 then demand_ku = get_saw_demand_ku(rpm) end
    local spin_dir  = meta:get_int("spin_dir")

    local is_powered, uni_rpm, uni_sup, uni_ava, uni_spin = kinetica.get_node_power(pos, meta)
    if not is_powered or uni_rpm < CONFIG.MIN_RPM then
        set_saw_idle(pos, node)
        return false
    end
    -- Use the unified power values
    rpm = uni_rpm
    supply_ku = uni_sup
    avail_ku = uni_ava
    spin_dir = uni_spin
    
    local target_active = get_active_saw_node_name(rpm, spin_dir)
    if node.name ~= target_active then
        core.swap_node(pos, {name = target_active, param2 = node.param2})
        node.name = target_active
    end

    local blade_dir  = get_blade_dir(node.param2)
    local target_pos = {x = pos.x + blade_dir.x, y = pos.y + blade_dir.y, z = pos.z + blade_dir.z}
    deal_saw_blade_damage(pos, target_pos)

    local target_node = core.get_node(target_pos)
    local can_cut, cut_cat = classify_saw_target(target_node.name)
    play_saw_active_sound(pos, meta, rpm, can_cut, CONFIG.TICK_INTERVAL)

    if can_cut then
        local prev_target = meta:get_string("cut_target_name")
        local progress    = meta:get_float("cut_progress")
        if prev_target ~= target_node.name then
            progress = 0
            meta:set_string("cut_target_name", target_node.name)
        end

        progress = progress + CONFIG.TICK_INTERVAL
        local req_time = get_required_cut_seconds(rpm)

        core.add_particlespawner({
            amount = 5, time = CONFIG.TICK_INTERVAL, minpos = {x = target_pos.x - 0.25, y = target_pos.y - 0.25, z = target_pos.z - 0.25},
            maxpos = {x = target_pos.x + 0.25, y = target_pos.y + 0.25, z = target_pos.z + 0.25}, minvel = {x = -0.8, y = 0.3, z = -0.8},
            maxvel = {x = 0.8, y = 1.4, z = 0.8}, minexptime = 0.2, maxexptime = 0.5, minsize = 1.0, maxsize = 2.0, texture = CONFIG.TEX_STONECUTTER_BOT,
        })

        if progress >= req_time then
            meta:set_float("cut_progress", 0); meta:set_string("cut_target_name", "")
            local owner = meta:get_string("owner")

            if cut_cat == "tree" then fell_whole_tree(target_pos, owner)
            elseif cut_cat == "column" then fell_vertical_column(target_pos, owner)
            else harvest_and_drop_node(target_pos, target_pos, owner) end

            if SOUND_CONFIG.ENABLE_CUT_FINISH_SOUND and SOUND_CONFIG.CUT_FINISH_SOUND ~= "" then
                core.sound_play(SOUND_CONFIG.CUT_FINISH_SOUND, { pos = pos, max_hear_distance = SOUND_CONFIG.MAX_HEAR_DISTANCE or 16, gain = SOUND_CONFIG.CUT_FINISH_GAIN or 0.8 }, true)
            end
        else
            meta:set_float("cut_progress", progress)
        end

        if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then meta:set_string("infotext", "") else
            meta:set_string("infotext", string.format("Mechanical Saw: CUTTING %d%% (-%d KU used | %d KU avail | %.0f RPM)", math.min(100, math.floor((progress / math.max(0.05, req_time)) * 100)), demand_ku, avail_ku, rpm))
        end
    else
        meta:set_float("cut_progress", 0); meta:set_string("cut_target_name", "")
        if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then meta:set_string("infotext", "") else
            meta:set_string("infotext", string.format("Mechanical Saw: ACTIVE (-%d KU used | %d KU avail | %.0f RPM)", demand_ku, avail_ku, rpm))
        end
    end

    meta:set_string("glasses_info", format_saw_glasses_info(pos, node))
    core.get_node_timer(pos):start(CONFIG.TICK_INTERVAL)
    return false
end

if kinetica.api and kinetica.api.registration then
    local saw_z_idle = CONFIG.TEX_STONECUTTER_SIDE .. "^(" .. CONFIG.TEX_STONECUTTER_SAW .. "^[sheet:1x3:0,0)"
    
    local machine_def = {
        description = string.format("Mechanical Saw (Min %d RPM | Fells Trees, Cuts Wood)", CONFIG.MIN_RPM),
        description_active = "Mechanical Saw",
        drawtype = "nodebox",
        node_box = { type = "fixed", fixed = {{-8/16, -8/16, -8/16, 8/16, 1/16, 8/16}, {-8/16, 1/16, 0, 8/16, 8/16, 0}} },
        collision_box = { type = "fixed", fixed = {{-8/16, -8/16, -8/16, 8/16, 1/16, 8/16}} },
        selection_box = { type = "fixed", fixed = {-8/16, -8/16, -8/16, 8/16, 8/16, 8/16} },
        paramtype2 = "facedir",
        tiles_idle = {CONFIG.TEX_STONECUTTER_TOP, "[combine:16x16:0,0=" .. CONFIG.TEX_STONECUTTER_BOT .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY, CONFIG.TEX_STONECUTTER_SIDE, CONFIG.TEX_STONECUTTER_SIDE, saw_z_idle, saw_z_idle},
        tiles_active_cw = {CONFIG.TEX_STONECUTTER_TOP, make_saw_back_anim(true, 0.24), CONFIG.TEX_STONECUTTER_SIDE, CONFIG.TEX_STONECUTTER_SIDE, make_saw_z_anim(false, 0.20), make_saw_z_anim(true, 0.20)},
        tiles_active_ccw = {CONFIG.TEX_STONECUTTER_TOP, make_saw_back_anim(false, 0.24), CONFIG.TEX_STONECUTTER_SIDE, CONFIG.TEX_STONECUTTER_SIDE, make_saw_z_anim(true, 0.20), make_saw_z_anim(false, 0.20)},
        
        build_tier_tiles = function(tier, is_ccw)
            local b_cw  = make_saw_back_anim(false, tier.shaft_len)
            local b_ccw = make_saw_back_anim(true,  tier.shaft_len)
            local s_cw  = make_saw_z_anim(false,    tier.blade_len)
            local s_ccw = make_saw_z_anim(true,     tier.blade_len)
            if is_ccw then return {CONFIG.TEX_STONECUTTER_TOP, b_cw, CONFIG.TEX_STONECUTTER_SIDE, CONFIG.TEX_STONECUTTER_SIDE, s_ccw, s_cw}
            else return {CONFIG.TEX_STONECUTTER_TOP, b_ccw, CONFIG.TEX_STONECUTTER_SIDE, CONFIG.TEX_STONECUTTER_SIDE, s_cw, s_ccw} end
        end,
        
        hardness = 2.5,
        sounds = mcl_sounds and mcl_sounds.node_sound_stone_defaults() or nil,
        groups_idle = {handy=1, pickaxey=1, axey=1, kinetic_receiver=1, kinetica_saw=1},
        
        on_place = place_mechanical_saw,
        on_construct = function(pos)
            local meta = core.get_meta(pos); meta:set_float("sfx_timer", 0)
            set_saw_idle(pos, core.get_node(pos))
            if kinetica.api and kinetica.api.network.schedule_update then kinetica.api.network.schedule_update(pos) end
        end,
        after_dig_node = function(pos)
            cleanup_legacy_blade_entities(pos)
            if kinetica.api and kinetica.api.network.schedule_update then kinetica.api.network.schedule_update(pos) end
        end,
        on_timer = saw_timer,
        get_demand_ku = function(rpm, pos, node) return get_saw_demand_ku(rpm) end,
        has_axle_port = function(node, d)
            local back_dir = get_back_dir(node.param2)
            return (d.x == back_dir.x and d.y == back_dir.y and d.z == back_dir.z)
        end,
        set_idle = set_saw_idle,
        wake = wake_saw,
        should_pause_contraption = function(pos, node, move_dir)
            local blade_dir = get_blade_dir(node.param2)
            local can_cut, _ = classify_saw_target(core.get_node({x = pos.x + blade_dir.x, y = pos.y + blade_dir.y, z = pos.z + blade_dir.z}).name)
            if can_cut then return true, "Waiting for Mechanical Saw to cut" end
            return false, nil
        end,
    }
    kinetica.api.registration.register_rotary_machine(IDLE_NAME, machine_def)
end

local saw_tier_nodes = {IDLE_NAME, ACT_CW, ACT_CCW}
for _, tier in ipairs(CONFIG.ANIM_TIERS) do
    saw_tier_nodes[#saw_tier_nodes + 1] = IDLE_NAME .. "_" .. tier.name .. "_cw"
    saw_tier_nodes[#saw_tier_nodes + 1] = IDLE_NAME .. "_" .. tier.name .. "_ccw"
end

core.register_on_mods_loaded(function()
    local sc = core.registered_nodes["mcl_stonecutter:stonecutter"]
    if not sc then return end

    local function adapt_sc_tiles(base_tiles)
        if not sc.tiles then return nil end
        local new_tiles = {}
        local saw_idx = 5
        for i, t in ipairs(sc.tiles) do
            local tname = type(t) == "table" and t.name or t
            if i == 2 or (type(tname) == "string" and string.find(tname, "bottom")) then
                new_tiles[i] = base_tiles[2]
            elseif type(tname) == "string" and string.find(tname, "saw") then
                new_tiles[i] = base_tiles[saw_idx]
                saw_idx = 6
            else
                new_tiles[i] = t
            end
        end
        return new_tiles
    end

    local common_geom = { drawtype = sc.drawtype, mesh = sc.mesh, node_box = sc.node_box, use_texture_alpha = sc.use_texture_alpha or "clip" }
    
    for _, node_name in ipairs(saw_tier_nodes) do
        local def = core.registered_nodes[node_name]
        if def and def.tiles then
            local adapted = adapt_sc_tiles(def.tiles)
            if adapted then
                core.override_item(node_name, {
                    drawtype = common_geom.drawtype, mesh = common_geom.mesh, node_box = common_geom.node_box,
                    use_texture_alpha = common_geom.use_texture_alpha, tiles = adapted,
                })
            end
        end
    end
end)

core.register_lbm({
    label             = "Wake kinetica Mechanical Saws on chunk load",
    name              = "kinetica:wake_saws_lbm",
    nodenames         = {"group:kinetica_saw"},
    run_at_every_load = true,
    action = function(pos, node)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then timer:start(CONFIG.TICK_INTERVAL) end
    end,
})

core.register_craft({
    output = "kinetica:mechanical_saw",
    recipe = {
        {"",               "kinetica:sheet_iron",      ""},
        {"",               "mcl_core:iron_ingot",      ""},
        {"kinetica:shaft", "kinetica:andesite_casing", ""},
    },
})