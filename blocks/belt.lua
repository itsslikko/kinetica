kinetica = kinetica or {}

local CONFIG = {
    MAX_BELT_LENGTH               = 16,
    BELT_HALF_THICKNESS           = 4 / 16,
    MIN_RPM                       = 6,
    KU_PER_RPM                    = 1,
    MIN_KU                        = 1,
    MAX_KU                        = 32,
    MAX_RPM_CAP                   = 1024,
    ANIM_TIERS = {
        { name = "crawl",  max_rpm = 10,   length = 0.75 },
        { name = "slow",   max_rpm = 24,   length = 0.48 },
        { name = "medium", max_rpm = 96,   length = 0.24 },
        { name = "fast",   max_rpm = 255,  length = 0.11 },
        { name = "hyper",  max_rpm = 1024, length = 0.05 },
    },
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    TIMER_INTERVAL                = 0.20,
    MIN_ITEM_SPEED                = 0.85,
    MAX_ITEM_SPEED                = 6.50,
    SPEED_AT_MIN_RPM              = 0.85,
    MOB_SPEED_MULT                = 1.15,
    ITEM_SURFACE_OFFSET           = 0.06,
    CENTER_PULL_STRENGTH          = 12.0,
    SURFACE_SNAP_STRENGTH         = 22.0,
    LAY_ITEMS_FLAT                = true,
    TILT_ITEMS_ON_SLOPE           = true,
    MOVE_MOBS_AND_ANIMALS         = true,
    MOVE_PLAYERS                  = true,
    INVERT_BELT_DIRECTION         = false,
    INVERT_TOP_TEX_SCROLL         = false,
    TEX_BELT_TOP                  = "kinetica_belt_top.png",
    TEX_BELT_SIDE                 = "kinetica_belt_side.png",
    TEX_SHAFT_OVERLAY             = "kinetica_shaft_connecting_overlay.png",
}

local IDLE_NAME = "kinetica:belt"
local BELT_ITEM = "kinetica:belt_item"

local HT = CONFIG.BELT_HALF_THICKNESS
local player_selections = {}
local is_dismantling_belt = false
local belt_relay_depth    = 0
local belt_demand_guard   = false

local active_conveyor_nodes = {}
local active_belt_spans     = {}
local active_belt_items     = {}

local function is_belt_node(name)
    if not name then return false end
    return name == IDLE_NAME or string.sub(name, 1, #IDLE_NAME + 1) == (IDLE_NAME .. "_")
end
kinetica.is_belt = is_belt_node

local function is_no_shaft_belt_name(name)
    return string.sub(name or "", -3) == "_ns"
end

local function is_belt_relay_name(name)
    return string.sub(name or "", -6) == "_relay"
end

local function is_idle_belt_name(name)
    if not name then return true end
    if name == IDLE_NAME or name == (IDLE_NAME .. "_ns") then
        return true
    end
    return string.find(name, "_idle", 1, true) ~= nil
end

local function is_reverse_belt_name(name)
    if not name then return false end
    return string.find(name, "_rev", 1, true) ~= nil
end

local orig_is_source_node = kinetica.is_source_node
function kinetica.is_source_node(name)
    if orig_is_source_node and orig_is_source_node(name) then
        return true
    end
    return is_belt_relay_name(name)
end

local function get_belt_span_demand_ku(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then
        return CONFIG.MIN_KU
    end
    if CONFIG.KU_PER_RPM <= 0 and CONFIG.MIN_KU <= 0 then
        return 0
    end
    return math.min(CONFIG.MAX_KU, math.max(CONFIG.MIN_KU, math.floor(rpm * CONFIG.KU_PER_RPM)))
end

local function get_belt_tier_name(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then
        return "idle"
    end
    local clamped = math.min(CONFIG.MAX_RPM_CAP, math.max(0, rpm))
    for _, tier in ipairs(CONFIG.ANIM_TIERS) do
        if clamped <= tier.max_rpm then
            return tier.name
        end
    end
    return CONFIG.ANIM_TIERS[#CONFIG.ANIM_TIERS].name
end

local function get_item_glide_speed(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then return 0 end
    local t = math.min(1.0, math.max(0.0, (rpm - CONFIG.MIN_RPM) / (512 - CONFIG.MIN_RPM)))
    local spd = CONFIG.SPEED_AT_MIN_RPM + t * (CONFIG.MAX_ITEM_SPEED - CONFIG.SPEED_AT_MIN_RPM)
    return math.min(CONFIG.MAX_ITEM_SPEED, math.max(CONFIG.MIN_ITEM_SPEED, spd))
end

local ALL_SHAPES = {"slope_bot", "slope_top", "slope_mid", "vert", "sideways"}

local function get_belt_shape(node_name, meta)
    for _, sh in ipairs(ALL_SHAPES) do
        if string.find(node_name or "", sh, 1, true) then
            return sh
        end
    end
    if meta then
        local sh = meta:get_string("belt_shape")
        if sh ~= "" then return sh end
    end
    return "flat"
end

local function get_back_dir(param2)
    local d = core.facedir_to_dir((param2 or 0) % 4) or {x = 0, y = 0, z = 1}
    return {x = d.x, y = 0, z = d.z}
end

local function get_fwd_dir(param2)
    local b = get_back_dir(param2)
    return {x = -b.x, y = 0, z = -b.z}
end

local function get_belt_axle_axis(node_name, param2)
    local shape = get_belt_shape(node_name, nil)
    if shape == "sideways" then
        return {x = 0, y = 1, z = 0}
    end
    local b = get_back_dir(param2)
    return {x = math.abs(b.z), y = 0, z = math.abs(b.x)}
end

local function get_belt_axle_dirs(node_name, param2)
    local ax = get_belt_axle_axis(node_name, param2)
    if ax.y ~= 0 then
        return {{x = 0, y = 1, z = 0}, {x = 0, y = -1, z = 0}}
    elseif ax.x ~= 0 then
        return {{x = 1, y = 0, z = 0}, {x = -1, y = 0, z = 0}}
    else
        return {{x = 0, y = 0, z = 1}, {x = 0, y = 0, z = -1}}
    end
end

local function get_travel_sign(param2, spin_dir, node_name)
    if not spin_dir or spin_dir == 0 then
        if node_name and not is_idle_belt_name(node_name) then
            return is_reverse_belt_name(node_name) and -1 or 1
        end
        return 0
    end
    local f = get_fwd_dir(param2)
    local natural_dir = (f.x ~= 0) and f.x or (-f.z)
    local sign = (spin_dir * natural_dir >= 0) and 1 or -1
    if CONFIG.INVERT_BELT_DIRECTION then
        sign = -sign
    end
    return sign
end

local function get_belt_move_dir(param2, spin_dir, node_name)
    local tsign = get_travel_sign(param2, spin_dir, node_name)
    if tsign == 0 then return {x = 0, y = 0, z = 0}, 0 end
    local f = get_fwd_dir(param2)
    return {x = f.x * tsign, y = 0, z = f.z * tsign}, tsign
end

local function get_target_belt_node_name(shape, has_shaft, is_relay, rpm, param2, spin_dir)
    shape = shape or "flat"
    local tier  = get_belt_tier_name(rpm)
    local tsign = get_travel_sign(param2, spin_dir)

    if tier == "idle" or tsign == 0 then
        local ns_suffix = has_shaft and "" or "_ns"
        if shape == "flat" then
            return IDLE_NAME .. ns_suffix
        else
            return IDLE_NAME .. "_" .. shape .. "_idle" .. ns_suffix
        end
    end

    local rev_suffix  = (tsign == 1) and "" or "_rev"
    local role_suffix = ""
    if not has_shaft then
        role_suffix = "_ns"
    elseif is_relay then
        role_suffix = "_relay"
    end

    if shape == "flat" then
        return IDLE_NAME .. "_" .. tier .. rev_suffix .. role_suffix
    else
        return IDLE_NAME .. "_" .. shape .. "_" .. tier .. rev_suffix .. role_suffix
    end
end

local function get_interpolated_belt_pos(sx, sy, sz, ex, ey, ez, seg_len, i)
    if seg_len <= 0 then
        return {x = sx, y = sy, z = sz}
    end
    local t = i / seg_len
    return {
        x = math.floor(sx + (ex - sx) * t + 0.5),
        y = math.floor(sy + (ey - sy) * t + 0.5),
        z = math.floor(sz + (ez - sz) * t + 0.5),
    }
end

local function get_span_start_key(pos, meta)
    meta = meta or core.get_meta(pos)
    if meta:get_int("seg_len") > 0 then
        return core.hash_node_position({
            x = meta:get_int("start_x"),
            y = meta:get_int("start_y"),
            z = meta:get_int("start_z"),
        })
    end
    return core.hash_node_position(pos)
end

local function get_belt_span_positions(pos, meta)
    meta = meta or core.get_meta(pos)
    local seg_len = meta:get_int("seg_len")
    if seg_len <= 0 then
        return {pos}
    end

    local sx = meta:get_int("start_x")
    local sy = meta:get_int("start_y")
    local sz = meta:get_int("start_z")

    if meta:get_int("has_end_pos") == 1 then
        local ex   = meta:get_int("end_x")
        local ey   = meta:get_int("end_y")
        local ez   = meta:get_int("end_z")
        local list = {}
        local seen = {}
        for i = 0, seg_len do
            local p  = get_interpolated_belt_pos(sx, sy, sz, ex, ey, ez, seg_len, i)
            local hk = core.hash_node_position(p)
            if not seen[hk] then
                seen[hk] = true
                list[#list + 1] = p
            end
        end
        return list
    end

    local step_x = meta:get_int("step_x")
    local step_y = meta:get_int("step_y")
    local step_z = meta:get_int("step_z")
    if step_x == 0 and step_y == 0 and step_z == 0 then
        return {pos}
    end

    local list = {}
    for i = 0, seg_len do
        list[#list + 1] = {
            x = sx + step_x * i,
            y = sy + step_y * i,
            z = sz + step_z * i,
        }
    end
    return list
end

local function get_effective_belt_power(bpos, meta, bnode)
    meta  = meta  or core.get_meta(bpos)
    bnode = bnode or core.get_node(bpos)

    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local spin_dir  = meta:get_int("spin_dir")

    if supply_ku > 0 and rpm >= CONFIG.MIN_RPM and spin_dir ~= 0 then
        return true, rpm, spin_dir, supply_ku
    end

    local span_key = get_span_start_key(bpos, meta)
    local sp_state = active_belt_spans[span_key]
    if sp_state and sp_state.supply_ku > 0 and sp_state.rpm >= CONFIG.MIN_RPM and sp_state.spin_dir ~= 0 then
        meta:set_float("rpm", sp_state.rpm)
        meta:set_int("spin_dir", sp_state.spin_dir)
        meta:set_int("network_supply_ku", sp_state.supply_ku)
        meta:set_int("rotational_power", sp_state.avail_ku or sp_state.supply_ku)
        return true, sp_state.rpm, sp_state.spin_dir, sp_state.supply_ku
    end

    if meta:get_int("seg_len") > 0 then
        local span = get_belt_span_positions(bpos, meta)
        for _, spos in ipairs(span) do
            local smeta = core.get_meta(spos)
            local srpm  = smeta:get_float("rpm")
            local ssup  = smeta:get_int("network_supply_ku")
            local sspin = smeta:get_int("spin_dir")
            if ssup > 0 and srpm >= CONFIG.MIN_RPM and sspin ~= 0 then
                active_belt_spans[span_key] = {
                    rpm       = srpm,
                    spin_dir  = sspin,
                    supply_ku = ssup,
                    avail_ku  = smeta:get_int("rotational_power"),
                }
                meta:set_float("rpm", srpm)
                meta:set_int("spin_dir", sspin)
                meta:set_int("network_supply_ku", ssup)
                return true, srpm, sspin, ssup
            end
        end
    end

    if bnode and is_belt_node(bnode.name) and not is_idle_belt_name(bnode.name) then
        local fallback_rpm = CONFIG.MIN_RPM
        if string.find(bnode.name, "_hyper", 1, true) then
            fallback_rpm = 256
        elseif string.find(bnode.name, "_fast", 1, true) then
            fallback_rpm = 128
        elseif string.find(bnode.name, "_medium", 1, true) then
            fallback_rpm = 32
        elseif string.find(bnode.name, "_slow", 1, true) then
            fallback_rpm = 16
        else
            fallback_rpm = 8
        end
        local f = get_fwd_dir(bnode.param2)
        local natural_dir = (f.x ~= 0) and f.x or (-f.z)
        local want_sign = is_reverse_belt_name(bnode.name) and -1 or 1
        if CONFIG.INVERT_BELT_DIRECTION then
            want_sign = -want_sign
        end
        local inferred_spin = (natural_dir >= 0) and want_sign or -want_sign
        return true, fallback_rpm, inferred_spin, 16
    end
    return false, 0, 0, 0
end

local function get_belt_surface_y_and_slope(pos, node, wx, wz)
    local shape = get_belt_shape(node.name, nil)
    if shape == "sideways" then
        return nil, 0
    end
    if shape == "vert" then
        local meta = core.get_meta(pos)
        if meta:get_int("has_end_pos") == 1 then
            local sx, sz = meta:get_int("start_x"), meta:get_int("start_z")
            local ex, ez = meta:get_int("end_x"),   meta:get_int("end_z")
            if sx == ex and sz == ez then
                return nil, 0
            end
        else
            return nil, 0
        end
    end

    local base_top = pos.y + HT + CONFIG.ITEM_SURFACE_OFFSET
    local f        = get_fwd_dir(node.param2)
    local u        = (wx - pos.x) * f.x + (wz - pos.z) * f.z
    if u < -0.5 then u = -0.5 end
    if u >  0.5 then u =  0.5 end

    if shape == "flat" then
        return base_top, 0
    elseif shape == "slope_bot" then
        return base_top + (u + 0.5) * 0.5, 0.5
    elseif shape == "slope_mid" or shape == "vert" then
        return base_top + u, 1.0
    elseif shape == "slope_top" then
        return base_top + (u - 0.5) * 0.5, 0.5
    end
    return base_top, 0
end

local function find_supporting_belt(epos, y_min_margin, y_max_margin, preferred_pos)
    y_min_margin = y_min_margin or -1.10
    y_max_margin = y_max_margin or  1.35

    if preferred_pos and
       math.abs(epos.x - preferred_pos.x) <= 0.50 and
       math.abs(epos.z - preferred_pos.z) <= 0.50 then
        local pnode = core.get_node(preferred_pos)
        if is_belt_node(pnode.name) then
            local py, pslope = get_belt_surface_y_and_slope(preferred_pos, pnode, epos.x, epos.z)
            if py then
                local diff = epos.y - py
                if diff >= y_min_margin and diff <= y_max_margin then
                    return preferred_pos, pnode, py, pslope
                end
            end
        end
    end

    local rx = math.floor(epos.x + 0.5)
    local ry = math.floor(epos.y + 0.5)
    local rz = math.floor(epos.z + 0.5)

    local best_pos, best_node, best_surf_y, best_slope = nil, nil, nil, 0
    local best_score = math.huge

    for dy = -2, 2 do
        for dx = -1, 1 do
            for dz = -1, 1 do
                local cpos = {x = rx + dx, y = ry + dy, z = rz + dz}
                local adx  = math.abs(epos.x - cpos.x)
                local adz  = math.abs(epos.z - cpos.z)
                if adx <= 0.56 and adz <= 0.56 then
                    local cnode = core.get_node(cpos)
                    if is_belt_node(cnode.name) then
                        local surf_y, slope_dz = get_belt_surface_y_and_slope(cpos, cnode, epos.x, epos.z)
                        if surf_y then
                            local y_diff = epos.y - surf_y
                            if y_diff >= y_min_margin and y_diff <= y_max_margin then
                                local inside_penalty = (adx <= 0.501 and adz <= 0.501) and 0 or 0.65
                                local horiz_dist     = adx + adz
                                local score          = math.abs(y_diff) + horiz_dist * 0.30 + inside_penalty
                                if score < best_score then
                                    best_score  = score
                                    best_pos    = cpos
                                    best_node   = cnode
                                    best_surf_y = surf_y
                                    best_slope  = slope_dz
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best_pos, best_node, best_surf_y, best_slope
end

local function find_next_belt_ahead(bpos, bnode, move_dir, tsign)
    local shape = get_belt_shape(bnode.name, nil)
    local dy_order
    if shape ~= "flat" and tsign and tsign > 0 then
        dy_order = {1, 0, -1, 2, -2}
    elseif shape ~= "flat" and tsign and tsign < 0 then
        dy_order = {-1, 0, 1, -2, 2}
    else
        dy_order = {0, 1, -1, 2, -2}
    end

    for _, dy in ipairs(dy_order) do
        local npos = {
            x = bpos.x + move_dir.x,
            y = bpos.y + dy,
            z = bpos.z + move_dir.z,
        }
        local nnode = core.get_node(npos)
        if is_belt_node(nnode.name) and get_belt_shape(nnode.name, nil) ~= "sideways" then
            return true, npos, nnode
        end
    end
    return false, nil, nil
end

local function is_item_receiver_ahead(node_name)
    if not node_name or node_name == "air" then
        return true
    end
    if node_name == "kinetica:depot" or
       node_name == "kinetica:chute" or
       node_name == "kinetica:smart_chute" or
       core.get_item_group(node_name, "kinetica_depot") > 0 or
       core.get_item_group(node_name, "kinetica_chute") > 0 then
        return true
    end
    local def = core.registered_nodes[node_name]
    return (def and def.walkable == false) or false
end

local function release_belt_item(obj, luaent, exit_vel)
    active_belt_items[obj] = nil
    if not luaent then return end
    luaent._kinetica_on_belt = false

    if obj and obj:get_pos() then
        local saved_rot = luaent._kinetica_saved_auto_rot or (math.pi * 0.5)
        obj:set_properties({
            physical         = true,
            automatic_rotate = saved_rot,
        })
        if obj.set_rotation then
            obj:set_rotation({x = 0, y = 0, z = 0})
        end
        luaent.physical_state = true
        luaent.Moving         = true
        obj:set_acceleration({x = 0, y = -9.81, z = 0})
        if exit_vel then
            obj:set_velocity(exit_vel)
        end
    end
end

local function step_belt_item(obj, luaent, bpos, bnode, ipos, dtime)
    local meta = core.get_meta(bpos)
    local is_active, rpm, spin_dir, _ = get_effective_belt_power(bpos, meta, bnode)

    local surf_y, local_slope = get_belt_surface_y_and_slope(bpos, bnode, ipos.x, ipos.z)
    if not surf_y then return end

    if not luaent._kinetica_on_belt or luaent.physical_state ~= false then
        local props = obj:get_properties() or {}
        if not luaent._kinetica_on_belt then
            luaent._kinetica_saved_auto_rot = props.automatic_rotate
            luaent._kinetica_on_belt = true
        end
        obj:set_properties({
            physical             = false,
            collide_with_objects = false,
            automatic_rotate     = CONFIG.LAY_ITEMS_FLAT and 0 or props.automatic_rotate,
        })
    end

    luaent.physical_state = false
    luaent.Moving         = true
    luaent.age            = math.min(luaent.age or 0, 10)
    obj:set_acceleration({x = 0, y = 0, z = 0})

    local prev_info = active_belt_items[obj]
    if prev_info and prev_info.last_pos and dtime and dtime > 0 then
        local drift = vector.distance(ipos, prev_info.last_pos)
        if drift < 0.35 then
            ipos = prev_info.last_pos
        end
    end

    active_belt_items[obj] = {
        luaent        = luaent,
        bpos          = {x = bpos.x, y = bpos.y, z = bpos.z},
        last_pos      = {x = ipos.x, y = ipos.y, z = ipos.z},
        missing_ticks = 0,
    }

    local move_dir, tsign = get_belt_move_dir(bnode.param2, is_active and spin_dir or 0, bnode.name)
    local orient_dir      = (tsign ~= 0) and move_dir or get_fwd_dir(bnode.param2)

    if CONFIG.LAY_ITEMS_FLAT and obj.set_rotation then
        local yaw   = math.atan2(-orient_dir.x, orient_dir.z)
        local pitch = math.pi / 2
        if CONFIG.TILT_ITEMS_ON_SLOPE and local_slope ~= 0 then
            local slope_sign = (tsign ~= 0) and tsign or 1
            pitch = (math.pi / 2) - (slope_sign * math.atan(local_slope))
        end
        obj:set_rotation({x = pitch, y = yaw, z = 0})
    end

    if not is_active or tsign == 0 then
        obj:set_velocity({x = 0, y = 0, z = 0})
        local rest_pos = {x = ipos.x, y = surf_y, z = ipos.z}
        active_belt_items[obj].last_pos = rest_pos
        if math.abs(ipos.y - surf_y) > 0.01 then
            obj:set_pos(rest_pos)
        end
        return
    end

    local speed = get_item_glide_speed(rpm)
    local f     = get_fwd_dir(bnode.param2)
    local u     = (ipos.x - bpos.x) * move_dir.x + (ipos.z - bpos.z) * move_dir.z

    local has_next, next_pos, next_node = find_next_belt_ahead(bpos, bnode, move_dir, tsign)

    if u > 0.32 and not has_next and local_slope == 0 then
        local ahead_pos = {
            x = bpos.x + move_dir.x,
            y = bpos.y,
            z = bpos.z + move_dir.z,
        }
        local ahead_node = core.get_node(ahead_pos)

        if ahead_node.name == "kinetica:depot" or
           ahead_node.name == "kinetica:chute" or
           ahead_node.name == "kinetica:smart_chute" then
            local rt = core.get_node_timer(ahead_pos)
            if rt and not rt:is_started() then
                rt:start(0.15)
            end
        elseif not is_item_receiver_ahead(ahead_node.name) and
               not is_belt_node(ahead_node.name) then
            local stop_pos = {x = ipos.x, y = surf_y, z = ipos.z}
            active_belt_items[obj].last_pos = stop_pos
            obj:set_velocity({x = 0, y = 0, z = 0})
            obj:set_pos(stop_pos)
            return
        end
    end

    local dt = math.min(0.10, math.max(0.0, dtime or 0))
    local nx = ipos.x
    local nz = ipos.z
    local vx, vz

    if f.x ~= 0 then
        vx = move_dir.x * speed
        vz = (bpos.z - ipos.z) * CONFIG.CENTER_PULL_STRENGTH
        if dt > 0 then
            nx = ipos.x + vx * dt
            nz = ipos.z + (bpos.z - ipos.z) * math.min(1.0, dt * CONFIG.CENTER_PULL_STRENGTH)
        end
    else
        vz = move_dir.z * speed
        vx = (bpos.x - ipos.x) * CONFIG.CENTER_PULL_STRENGTH
        if dt > 0 then
            nz = ipos.z + vz * dt
            nx = ipos.x + (bpos.x - ipos.x) * math.min(1.0, dt * CONFIG.CENTER_PULL_STRENGTH)
        end
    end

    local target_bpos  = bpos
    local target_bnode = bnode
    local crossed_seam = (math.abs(nx - bpos.x) > 0.50 or math.abs(nz - bpos.z) > 0.50)

    if crossed_seam and has_next and next_pos and next_node then
        target_bpos  = next_pos
        target_bnode = next_node
        active_belt_items[obj].bpos = {x = next_pos.x, y = next_pos.y, z = next_pos.z}
    end

    local target_surf_y, target_slope = get_belt_surface_y_and_slope(target_bpos, target_bnode, nx, nz)
    target_surf_y = target_surf_y or surf_y
    target_slope  = target_slope  or local_slope

    local slope_vy = (target_slope ~= 0) and (tsign * speed * target_slope) or 0
    local new_pos  = {x = nx, y = target_surf_y, z = nz}
    active_belt_items[obj].last_pos = new_pos

    if dt > 0 then
        obj:set_pos(new_pos)
    elseif math.abs(ipos.y - target_surf_y) > 0.02 then
        obj:set_pos({x = ipos.x, y = target_surf_y, z = ipos.z})
    end

    obj:set_velocity({x = vx, y = slope_vy, z = vz})
end

local function is_movable_living_entity(obj)
    if not obj then return false, false end
    if obj:is_player() then
        if not CONFIG.MOVE_PLAYERS then return false, false end
        if obj:get_player_control().sneak then return false, false end
        return true, true
    end

    if not CONFIG.MOVE_MOBS_AND_ANIMALS then
        return false, false
    end

    local luaent = obj:get_luaentity()
    if not luaent then return false, false end
    if luaent.name == "__builtin:item" or
       luaent.name == "kinetica:water_wheel_big_mesh" or
       luaent.name == "kinetica:depot_item_visual" or
       luaent.name == "kinetica:mechanical_saw_blade" then
        return false, false
    end

    if luaent.is_mob or luaent._cmi_is_mob or luaent.health or
       string.sub(luaent.name or "", 1, 8) == "mobs_mc:" then
        return true, false
    end
    return false, false
end

local function apply_belt_motion_to_living(obj, is_player, bpos, bnode, epos, dtime)
    local meta = core.get_meta(bpos)
    local is_active, rpm, spin_dir, _ = get_effective_belt_power(bpos, meta, bnode)
    if not is_active then return end

    local move_dir, tsign = get_belt_move_dir(bnode.param2, spin_dir, bnode.name)
    if tsign == 0 then return end

    local surf_y, local_slope = get_belt_surface_y_and_slope(bpos, bnode, epos.x, epos.z)
    if not surf_y then return end

    local speed = get_item_glide_speed(rpm) * CONFIG.MOB_SPEED_MULT
    local f     = get_fwd_dir(bnode.param2)

    if is_player then
        if obj.add_velocity then
            local cur_v     = obj:get_velocity() or {x = 0, y = 0, z = 0}
            local target_vx = move_dir.x * speed
            local target_vz = move_dir.z * speed
            local dvx       = (target_vx - cur_v.x) * 0.45
            local dvz       = (target_vz - cur_v.z) * 0.45
            local dvy       = 0
            if local_slope ~= 0 and tsign > 0 then
                local want_vy = speed * local_slope + 1.25
                if cur_v.y < want_vy then
                    dvy = (want_vy - cur_v.y) * 0.55
                end
            end
            obj:add_velocity({x = dvx, y = dvy, z = dvz})
        end
    else
        local cur_v = obj:get_velocity() or {x = 0, y = 0, z = 0}
        local vx, vz
        if f.x ~= 0 then
            vx = move_dir.x * speed
            vz = cur_v.z * 0.25 + (bpos.z - epos.z) * 4.0
        else
            vz = move_dir.z * speed
            vx = cur_v.x * 0.25 + (bpos.x - epos.x) * 4.0
        end

        local vy = cur_v.y
        if local_slope ~= 0 and tsign > 0 then
            vy = math.max(cur_v.y, speed * local_slope + 1.35)
            if epos.y < surf_y + 0.02 then
                obj:set_pos({x = epos.x, y = surf_y + 0.06, z = epos.z})
            end
        elseif local_slope ~= 0 and tsign < 0 then
            vy = math.min(cur_v.y, -speed * local_slope - 0.25)
        end
        obj:set_velocity({x = vx, y = vy, z = vz})
    end
end

local function scan_and_move_entities_on_belt(pos, node)
    local shape = get_belt_shape(node.name, nil)
    if shape == "sideways" then return end

    local scan_center = {x = pos.x, y = pos.y + 0.35, z = pos.z}
    local objs = core.get_objects_inside_radius(scan_center, 1.45)

    for _, obj in ipairs(objs) do
        local epos = obj:get_pos()
        if epos then
            local luaent = obj:get_luaentity()
            if luaent and luaent.name == "__builtin:item" and not luaent._kinetica_vacuumed then
                if not active_belt_items[obj] then
                    if math.abs(epos.x - pos.x) <= 0.60 and
                       math.abs(epos.z - pos.z) <= 0.60 and
                       epos.y >= (pos.y - 0.90) and epos.y <= (pos.y + 1.25) then
                        step_belt_item(obj, luaent, pos, node, epos, 0)
                    end
                end
            else
                local is_liv, is_plr = is_movable_living_entity(obj)
                if is_liv and not is_plr then
                    if math.abs(epos.x - pos.x) <= 0.65 and
                       math.abs(epos.z - pos.z) <= 0.65 and
                       epos.y >= (pos.y - 0.90) and epos.y <= (pos.y + 1.35) then
                        apply_belt_motion_to_living(obj, false, pos, node, epos, 0.08)
                    end
                end
            end
        end
    end
end

local function spawn_belt_particles(pos, mode)
    local tex = CONFIG.TEX_SHAFT_OVERLAY .. "^[sheet:1x4:0,0"
    if mode == "select" then
        core.add_particlespawner({
            amount     = 18,
            time       = 0.15,
            minpos     = {x = pos.x - 0.35, y = pos.y - 0.35, z = pos.z - 0.35},
            maxpos     = {x = pos.x + 0.35, y = pos.y + 0.35, z = pos.z + 0.35},
            minvel     = {x = -0.6, y =  0.3, z = -0.6},
            maxvel     = {x =  0.6, y =  1.1, z =  0.6},
            minexptime = 0.35,
            maxexptime = 0.70,
            minsize    = 1.2,
            maxsize    = 2.2,
            glow       = 12,
            texture    = tex,
        })
    elseif mode == "pulse" then
        core.add_particlespawner({
            amount     = 4,
            time       = 0.25,
            minpos     = {x = pos.x - 0.30, y = pos.y - 0.30, z = pos.z - 0.30},
            maxpos     = {x = pos.x + 0.30, y = pos.y + 0.30, z = pos.z + 0.30},
            minvel     = {x = -0.2, y =  0.2, z = -0.2},
            maxvel     = {x =  0.2, y =  0.5, z =  0.2},
            minexptime = 0.25,
            maxexptime = 0.45,
            minsize    = 1.0,
            maxsize    = 1.8,
            glow       = 12,
            texture    = tex,
        })
    elseif mode == "connect" then
        core.add_particlespawner({
            amount     = 10,
            time       = 0.12,
            minpos     = {x = pos.x - 0.40, y = pos.y - 0.25, z = pos.z - 0.40},
            maxpos     = {x = pos.x + 0.40, y = pos.y + 0.35, z = pos.z + 0.40},
            minvel     = {x = -0.8, y =  0.4, z = -0.8},
            maxvel     = {x =  0.8, y =  1.2, z =  0.8},
            minexptime = 0.30,
            maxexptime = 0.65,
            minsize    = 1.4,
            maxsize    = 2.4,
            glow       = 11,
            texture    = CONFIG.TEX_BELT_SIDE,
        })
    end
end

local scan_accum  = 0
local pulse_accum = 0
core.register_globalstep(function(dtime)
    if next(active_belt_items) then
        for obj, info in pairs(active_belt_items) do
            local ipos   = obj and obj:get_pos()
            local luaent = info.luaent
            if not ipos or not luaent or luaent._kinetica_vacuumed then
                active_belt_items[obj] = nil
            else
                local search_pos = info.last_pos or ipos
                local bpos, bnode, _, _ = find_supporting_belt(
                    search_pos, -1.10, 1.35, info.bpos
                )
                if bpos and bnode then
                    info.bpos          = {x = bpos.x, y = bpos.y, z = bpos.z}
                    info.missing_ticks = 0
                    step_belt_item(obj, luaent, bpos, bnode, search_pos, dtime)
                elseif (info.missing_ticks or 0) < 4 then
                    info.missing_ticks = (info.missing_ticks or 0) + 1
                else
                    local cur_vel = obj:get_velocity() or {x = 0, y = 0, z = 0}
                    release_belt_item(obj, luaent, {
                        x = cur_vel.x,
                        y = math.min(0.4, cur_vel.y),
                        z = cur_vel.z,
                    })
                end
            end
        end
    end

    scan_accum = scan_accum + dtime
    if scan_accum >= 0.08 then
        scan_accum = 0
        for hkey, entry in pairs(active_conveyor_nodes) do
            local bnode = core.get_node(entry.pos)
            if is_belt_node(bnode.name) then
                scan_and_move_entities_on_belt(entry.pos, bnode)
            else
                active_conveyor_nodes[hkey] = nil
            end
        end
    end

    pulse_accum = pulse_accum + dtime
    if pulse_accum >= 0.45 then
        pulse_accum = 0
        for pname, sel in pairs(player_selections) do
            local p = core.get_player_by_name(pname)
            if p and sel and sel.pos then
                local wstack = p:get_wielded_item()
                if wstack and wstack:get_name() == BELT_ITEM then
                    spawn_belt_particles(sel.pos, "pulse")
                else
                    player_selections[pname] = nil
                end
            else
                player_selections[pname] = nil
            end
        end
    end

    if CONFIG.MOVE_PLAYERS then
        for _, player in ipairs(core.get_connected_players()) do
            if not player:get_player_control().sneak then
                local ppos = player:get_pos()
                if ppos then
                    local bpos, bnode, _, _ = find_supporting_belt(ppos, -0.95, 0.95)
                    if bpos and bnode then
                        apply_belt_motion_to_living(player, true, bpos, bnode, ppos, dtime)
                    end
                end
            end
        end
    end
end)

local ALL_6_DIRS = {
    {x =  1, y =  0, z =  0},
    {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0},
    {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1},
    {x =  0, y =  0, z = -1},
}

local function format_belt_mode_label(shape)
    if shape == "vert" then
        return "90° Vertical"
    elseif shape == "sideways" then
        return "Sideways Vertical-Shaft"
    elseif shape ~= "flat" then
        return "Sloped Slide"
    end
    return "Flat"
end

kinetica._glasses_formatters = kinetica._glasses_formatters or {}

local function format_belt_glasses_info(pos, node)
    local meta      = core.get_meta(pos)
    local shape     = get_belt_shape(node.name, meta)
    local mode_lbl  = format_belt_mode_label(shape)
    local has_shaft = (meta:get_int("has_shaft") == 1)
    local is_relay  = (meta:get_int("source_active") == 1)
    local seg_len   = meta:get_int("seg_len")
    local b_idx     = meta:get_int("belt_index")
    local is_active, rpm, _, supply_ku = get_effective_belt_power(pos, meta, node)
    local avail_ku  = meta:get_int("rotational_power")
    local demand_ku = meta:get_int("machine_demand_ku")
    if demand_ku <= 0 then demand_ku = get_belt_span_demand_ku(rpm) end
    local glide_spd = is_active and get_item_glide_speed(rpm) or 0
    local role_str  = has_shaft and (is_relay and "Relay Pulley (Outputs Shaft Power)" or "Driven Shaft Pulley") or "Belt Span Segment"
    local state_str = is_active and ("ACTIVE (" .. string.upper(get_belt_tier_name(rpm)) .. ")") or "IDLE"

    return table.concat({
        "=== KINETIC GLASSES TELEMETRY ===",
        string.format("Block:  Mechanical Belt (%s)", mode_lbl),
        "State:  " .. state_str,
        string.format("Speed:  %.1f RPM (Glide: %.2f blk/s | Min %d RPM)", is_active and rpm or 0, glide_spd, CONFIG.MIN_RPM),
        string.format("Power:  %d / %d KU Avail (-%d KU Load)", is_active and avail_ku or 0, supply_ku, is_active and demand_ku or 0),
        string.format("Role:   %s [%d/%d]", role_str, b_idx + 1, seg_len + 1),
    }, "\n")
end

kinetica._glasses_formatters[IDLE_NAME] = format_belt_glasses_info

if not kinetica.get_glasses_info then
    function kinetica.get_glasses_info(pos, node)
        node = node or core.get_node(pos)
        for prefix, fn in pairs(kinetica._glasses_formatters) do
            if node.name == prefix or string.sub(node.name or "", 1, #prefix + 1) == (prefix .. "_") then
                return fn(pos, node)
            end
        end
        return core.get_meta(pos):get_string("glasses_info")
    end
end

local function update_single_belt_visual_and_timer(bpos, bnode, rpm, spin_dir, is_relay)
    bnode = bnode or core.get_node(bpos)
    if not is_belt_node(bnode.name) then return end

    local bmeta     = core.get_meta(bpos)
    local shape     = get_belt_shape(bnode.name, bmeta)
    local has_shaft = (bmeta:get_int("has_shaft") == 1)
    local target    = get_target_belt_node_name(shape, has_shaft, is_relay, rpm, bnode.param2, spin_dir)

    if bnode.name ~= target then
        core.swap_node(bpos, {name = target, param2 = bnode.param2})
    end

    local hkey = core.hash_node_position(bpos)
    if rpm and rpm >= CONFIG.MIN_RPM and spin_dir ~= 0 then
        if shape ~= "sideways" then
            active_conveyor_nodes[hkey] = {pos = {x = bpos.x, y = bpos.y, z = bpos.z}}
        end
        local timer = core.get_node_timer(bpos)
        if not timer:is_started() then
            timer:start(CONFIG.TIMER_INTERVAL)
        end
    else
        active_conveyor_nodes[hkey] = nil
    end
end

local function clear_belt_virtual_sources(span)
    for _, bpos in ipairs(span) do
        local bnode = core.get_node(bpos)
        if is_belt_node(bnode.name) then
            local bmeta = core.get_meta(bpos)
            bmeta:set_int("source_active", 0)
            bmeta:set_int("source_ku", 0)
            bmeta:set_float("source_rpm", 0)
            bmeta:set_int("source_spin", 0)
        end
    end
end

local function get_connected_axle_neighbors(bpos, bnode)
    local neighbors = {}
    for _, d in ipairs(get_belt_axle_dirs(bnode.name, bnode.param2)) do
        local npos  = {x = bpos.x + d.x, y = bpos.y + d.y, z = bpos.z + d.z}
        local nnode = core.get_node(npos)
        local rev   = {x = -d.x, y = -d.y, z = -d.z}
        if kinetica.is_kinetic_node and kinetica.is_kinetic_node(nnode.name) then
            if kinetica.is_speed_controller and kinetica.is_speed_controller(nnode.name) then
                local sc_in = core.facedir_to_dir(nnode.param2 or 0) or {x = 0, y = 0, z = 1}
                if math.abs(rev.x) == math.abs(sc_in.x) and
                   math.abs(rev.y) == math.abs(sc_in.y) and
                   math.abs(rev.z) == math.abs(sc_in.z) then
                    neighbors[#neighbors + 1] = {pos = npos, node = nnode}
                end
            elseif not kinetica.has_axle_port or kinetica.has_axle_port(nnode, rev) then
                neighbors[#neighbors + 1] = {pos = npos, node = nnode}
            end
        end
    end
    return neighbors
end

local function are_kinetic_nodes_coupled(cur_node, nnode, d, for_gen_trace)
    local rev = {x = -d.x, y = -d.y, z = -d.z}

    if kinetica.is_speed_controller and kinetica.is_speed_controller(nnode.name) then
        local sc_in  = core.facedir_to_dir(nnode.param2 or 0) or {x = 0, y = 0, z = 1}
        local sc_out = {x = -sc_in.x, y = -sc_in.y, z = -sc_in.z}
        local want   = for_gen_trace and sc_out or sc_in
        if rev.x == want.x and rev.y == want.y and rev.z == want.z then
            if not kinetica.has_axle_port or kinetica.has_axle_port(cur_node, d) then
                return true
            end
        end
        return false
    end

    if kinetica.has_axle_port and
       kinetica.has_axle_port(cur_node, d) and
       kinetica.has_axle_port(nnode, rev) then
        return true
    elseif kinetica.is_chain_drive and
           kinetica.is_chain_drive(cur_node.name) and
           kinetica.is_chain_drive(nnode.name) then
        local axA = kinetica.abs_axis(cur_node.param2)
        local axB = kinetica.abs_axis(nnode.param2)
        if axA.x == axB.x and axA.y == axB.y and axA.z == axB.z then
            return true
        end
    end
    return false
end

local function is_real_generator_node(pos, node)
    if (kinetica.is_water_wheel and kinetica.is_water_wheel(node.name)) or
       (kinetica.is_turbine and kinetica.is_turbine(node.name)) or
       (orig_is_source_node and orig_is_source_node(node.name) and not is_belt_node(node.name)) then
        local smeta = core.get_meta(pos)
        if smeta:get_int("source_active") == 1 and smeta:get_int("source_ku") > 0 then
            return true
        end
    end
    if kinetica.is_speed_controller and kinetica.is_speed_controller(node.name) then
        local smeta = core.get_meta(pos)
        if smeta:get_int("sc_out_active") == 1 and smeta:get_int("sc_out_ku") > 0 then
            return true
        end
    end
    return false
end

local function pulley_reaches_real_generator(pulley_pos, pulley_node, own_span_hashes)
    local visited = {}
    for hk, _ in pairs(own_span_hashes or {}) do
        visited[hk] = true
    end
    visited[core.hash_node_position(pulley_pos)] = true

    local queue = {}
    for _, nb in ipairs(get_connected_axle_neighbors(pulley_pos, pulley_node)) do
        local nk = core.hash_node_position(nb.pos)
        if not visited[nk] then
            if kinetica.is_speed_controller and kinetica.is_speed_controller(nb.node.name) then
                local sc_in  = core.facedir_to_dir(nb.node.param2 or 0) or {x = 0, y = 0, z = 1}
                local sc_out = {x = -sc_in.x, y = -sc_in.y, z = -sc_in.z}
                local d      = vector.subtract(nb.pos, pulley_pos)
                if sc_out.x == -d.x and sc_out.y == -d.y and sc_out.z == -d.z then
                    visited[nk] = true
                    queue[#queue + 1] = nb
                end
            else
                visited[nk] = true
                queue[#queue + 1] = nb
            end
        end
    end

    local dirs = kinetica.directions or ALL_6_DIRS
    local head = 1
    while head <= #queue and #queue <= 384 do
        local cur = queue[head]
        head = head + 1

        if is_real_generator_node(cur.pos, cur.node) then
            return true
        end

        if is_belt_node(cur.node.name) then
            local cmeta = core.get_meta(cur.pos)
            if cmeta:get_int("has_shaft") == 1 then
                local other_span = get_belt_span_positions(cur.pos, cmeta)
                for _, obpos in ipairs(other_span) do
                    local ohk = core.hash_node_position(obpos)
                    if not visited[ohk] then
                        local obnode = core.get_node(obpos)
                        if is_belt_node(obnode.name) and core.get_meta(obpos):get_int("has_shaft") == 1 then
                            visited[ohk] = true
                            queue[#queue + 1] = {pos = obpos, node = obnode}
                        end
                    end
                end
            end
        end

        if not (kinetica.is_speed_controller and kinetica.is_speed_controller(cur.node.name)) then
            for _, d in ipairs(dirs) do
                local npos = {x = cur.pos.x + d.x, y = cur.pos.y + d.y, z = cur.pos.z + d.z}
                local nk   = core.hash_node_position(npos)
                if not visited[nk] then
                    local nnode = core.get_node(npos)
                    if kinetica.is_kinetic_node and kinetica.is_kinetic_node(nnode.name) then
                        if are_kinetic_nodes_coupled(cur.node, nnode, d, true) then
                            visited[nk] = true
                            queue[#queue + 1] = {pos = npos, node = nnode}
                        end
                    end
                end
            end
        end
    end
    return false
end

local function get_single_node_machine_demand(pos, node, rpm)
    if not node or not node.name or is_belt_node(node.name) then
        return 0
    end
    if kinetica.is_shaft and kinetica.is_shaft(node.name) then
        return 0
    end
    if (kinetica.is_water_wheel and kinetica.is_water_wheel(node.name)) or
       (kinetica.is_turbine and kinetica.is_turbine(node.name)) then
        return 0
    end

    if kinetica.is_gearbox and kinetica.is_gearbox(node.name) then
        return 1
    end
    if kinetica.is_chain_drive and kinetica.is_chain_drive(node.name) then
        return 1
    end
    if kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(node.name) then
        if kinetica.get_piston_demand_ku then
            return kinetica.get_piston_demand_ku(rpm)
        end
        return 32
    end

    if kinetica.get_machine_demand_ku then
        local d = kinetica.get_machine_demand_ku(rpm, pos, node)
        if type(d) == "number" then return math.max(0, d) end
    end
    if kinetica.get_demand_ku then
        local d = kinetica.get_demand_ku(rpm, pos, node)
        if type(d) == "number" then return math.max(0, d) end
    end
    if type(kinetica.registered_machines) == "table" then
        for prefix, mdef in pairs(kinetica.registered_machines) do
            if node.name == prefix or string.sub(node.name, 1, #prefix + 1) == (prefix .. "_") then
                if mdef and mdef.get_demand_ku then
                    return math.max(0, mdef.get_demand_ku(rpm, pos, node) or 0)
                end
            end
        end
    end
    if type(kinetica.machines) == "table" then
        for prefix, mdef in pairs(kinetica.machines) do
            if node.name == prefix or string.sub(node.name, 1, #prefix + 1) == (prefix .. "_") then
                if mdef and mdef.get_demand_ku then
                    return math.max(0, mdef.get_demand_ku(rpm, pos, node) or 0)
                end
            end
        end
    end

    local meta = core.get_meta(pos)
    local md   = meta:get_int("machine_demand_ku")
    if md > 0 then
        return md
    end
    return 0
end

local function compute_relay_pulley_downstream_demand_ku(pulley_pos, pulley_node, rpm, visited)
    local total_ku = 0
    local queue    = {}

    for _, nb in ipairs(get_connected_axle_neighbors(pulley_pos, pulley_node)) do
        local nk = core.hash_node_position(nb.pos)
        if not visited[nk] then
            visited[nk] = true
            queue[#queue + 1] = nb
        end
    end

    local dirs = kinetica.directions or ALL_6_DIRS
    local head = 1
    while head <= #queue and #queue <= 384 do
        local cur = queue[head]
        head = head + 1

        if is_belt_node(cur.node.name) then
            local cmeta = core.get_meta(cur.pos)
            local cspan = get_belt_span_positions(cur.pos, cmeta)
            local c_own = {}
            for _, obpos in ipairs(cspan) do
                local ohk = core.hash_node_position(obpos)
                c_own[ohk] = true
                visited[ohk] = true
            end
            total_ku = total_ku + get_belt_span_demand_ku(rpm)
            for _, obpos in ipairs(cspan) do
                local obnode = core.get_node(obpos)
                if is_belt_node(obnode.name) and core.get_meta(obpos):get_int("has_shaft") == 1 then
                    if not pulley_reaches_real_generator(obpos, obnode, c_own) then
                        for _, nb in ipairs(get_connected_axle_neighbors(obpos, obnode)) do
                            local nk = core.hash_node_position(nb.pos)
                            if not visited[nk] then
                                visited[nk] = true
                                queue[#queue + 1] = nb
                            end
                        end
                    end
                end
            end
        else
            total_ku = total_ku + get_single_node_machine_demand(cur.pos, cur.node, rpm)
            if not (kinetica.is_speed_controller and kinetica.is_speed_controller(cur.node.name)) then
                for _, d in ipairs(dirs) do
                    local npos = {x = cur.pos.x + d.x, y = cur.pos.y + d.y, z = cur.pos.z + d.z}
                    local nk   = core.hash_node_position(npos)
                    if not visited[nk] then
                        local nnode = core.get_node(npos)
                        if kinetica.is_kinetic_node and kinetica.is_kinetic_node(nnode.name) then
                            if are_kinetic_nodes_coupled(cur.node, nnode, d, false) then
                                visited[nk] = true
                                queue[#queue + 1] = {pos = npos, node = nnode}
                            end
                        end
                    end
                end
            end
        end
    end
    return total_ku
end

local function get_belt_span_total_demand_ku(pos, rpm)
    local base_ku = get_belt_span_demand_ku(rpm)
    if not pos or belt_demand_guard or not rpm or rpm < CONFIG.MIN_RPM then
        return base_ku
    end

    belt_demand_guard = true
    local meta = core.get_meta(pos)
    local span = get_belt_span_positions(pos, meta)

    local own_span_hashes = {}
    local visited         = {}
    for _, bpos in ipairs(span) do
        local hk = core.hash_node_position(bpos)
        own_span_hashes[hk] = true
        visited[hk]         = true
    end

    local downstream_ku = 0
    for _, bpos in ipairs(span) do
        local bnode = core.get_node(bpos)
        if is_belt_node(bnode.name) and core.get_meta(bpos):get_int("has_shaft") == 1 then
            if not pulley_reaches_real_generator(bpos, bnode, own_span_hashes) then
                downstream_ku = downstream_ku + compute_relay_pulley_downstream_demand_ku(
                    bpos, bnode, rpm, visited
                )
            end
        end
    end

    belt_demand_guard = false
    return base_ku + downstream_ku
end

local function notify_pulley_and_axle_neighbors(bpos, bnode)
    if not kinetica.update_network then return end
    bnode = bnode or core.get_node(bpos)
    kinetica.update_network(bpos)
    for _, nb in ipairs(get_connected_axle_neighbors(bpos, bnode)) do
        kinetica.update_network(nb.pos)
    end
end

local function set_belt_idle(pos, node, reason_text)
    if belt_relay_depth > 4 then return end
    node = node or core.get_node(pos)
    local meta     = core.get_meta(pos)
    local span     = get_belt_span_positions(pos, meta)
    local span_key = get_span_start_key(pos, meta)

    local own_span_hashes = {}
    for _, bpos in ipairs(span) do
        own_span_hashes[core.hash_node_position(bpos)] = true
    end

    for _, bpos in ipairs(span) do
        local bnode = core.get_node(bpos)
        if is_belt_node(bnode.name) and core.get_meta(bpos):get_int("has_shaft") == 1 then
            if pulley_reaches_real_generator(bpos, bnode, own_span_hashes) then
                belt_relay_depth = belt_relay_depth + 1
                notify_pulley_and_axle_neighbors(bpos, bnode)
                belt_relay_depth = belt_relay_depth - 1
                return
            end
        end
    end

    active_belt_spans[span_key] = nil
    clear_belt_virtual_sources(span)

    for _, bpos in ipairs(span) do
        local bnode = core.get_node(bpos)
        if is_belt_node(bnode.name) then
            local bmeta     = core.get_meta(bpos)
            local shape     = get_belt_shape(bnode.name, bmeta)
            local has_shaft = (bmeta:get_int("has_shaft") == 1)
            local target    = get_target_belt_node_name(shape, has_shaft, false, 0, bnode.param2, 0)
            if bnode.name ~= target then
                core.swap_node(bpos, {name = target, param2 = bnode.param2})
            end
            active_conveyor_nodes[core.hash_node_position(bpos)] = nil

            bmeta:set_float("rpm", 0)
            bmeta:set_int("spin_dir", 0)
            bmeta:set_int("network_supply_ku", 0)
            bmeta:set_int("rotational_power", 0)
            bmeta:set_int("machine_demand_ku", 0)
            bmeta:set_int("lit_until", 0)

            local mode_lbl  = format_belt_mode_label(shape)
            local shaft_lbl = has_shaft and "Shaft Pulley" or "Right-click with Shaft to add Pulley"
            if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
                bmeta:set_string("infotext", "")
            else
                bmeta:set_string("infotext", reason_text or string.format(
                    "Mechanical Belt (%s | %s): Idle (Min %d RPM)",
                    mode_lbl, shaft_lbl, CONFIG.MIN_RPM
                ))
            end
            bmeta:set_string("glasses_info", format_belt_glasses_info(bpos, core.get_node(bpos)))
        end
    end

    belt_relay_depth = belt_relay_depth + 1
    for _, bpos in ipairs(span) do
        local bnode = core.get_node(bpos)
        if is_belt_node(bnode.name) and core.get_meta(bpos):get_int("has_shaft") == 1 then
            for _, nb in ipairs(get_connected_axle_neighbors(bpos, bnode)) do
                if kinetica.update_network then
                    kinetica.update_network(nb.pos)
                end
            end
        end
    end
    belt_relay_depth = belt_relay_depth - 1
end

local function wake_belt(pos, node, rpm, spin_dir, demand_ku, avail_ku, supply_ku)
    node = node or core.get_node(pos)
    local meta     = core.get_meta(pos)
    local now      = math.floor(core.get_gametime())
    local span     = get_belt_span_positions(pos, meta)
    local span_key = get_span_start_key(pos, meta)

    if rpm < CONFIG.MIN_RPM then
        set_belt_idle(pos, node, string.format(
            "Mechanical Belt: Too Slow (%.0f RPM / Min %d RPM required!)",
            rpm, CONFIG.MIN_RPM
        ))
        return
    end

    local tier_lbl = string.upper(get_belt_tier_name(rpm))
    local own_span_hashes = {}
    for _, bpos in ipairs(span) do
        own_span_hashes[core.hash_node_position(bpos)] = true
    end

    local pulley_has_gen     = {}
    local any_real_generator = false
    local conflict_shaft_pos = nil

    for _, bpos in ipairs(span) do
        local bnode = core.get_node(bpos)
        local hk    = core.hash_node_position(bpos)
        if is_belt_node(bnode.name) and core.get_meta(bpos):get_int("has_shaft") == 1 then
            local reaches_gen = pulley_reaches_real_generator(bpos, bnode, own_span_hashes)
            pulley_has_gen[hk] = reaches_gen
            if reaches_gen then
                any_real_generator = true
                for _, nb in ipairs(get_connected_axle_neighbors(bpos, bnode)) do
                    local nmeta = core.get_meta(nb.pos)
                    local nrpm  = nmeta:get_float("rpm")
                    local nspin = nmeta:get_int("spin_dir")
                    if nrpm > 0 and nmeta:get_int("lit_until") > now then
                        if math.abs(nrpm - rpm) > 0.01 or (nspin ~= 0 and nspin ~= spin_dir) then
                            conflict_shaft_pos = nb.pos
                        end
                    end
                end
            end
        end
    end

    if not any_real_generator then
        set_belt_idle(pos, node)
        return
    end

    if conflict_shaft_pos and kinetica.break_conflicting_shaft then
        if kinetica.break_conflicting_shaft(conflict_shaft_pos) then
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
            return
        end
    end

    local total_span_demand_ku = get_belt_span_total_demand_ku(pos, rpm)
    local reported_demand      = demand_ku or 0
    local extra_unaccounted_ku = math.max(0, total_span_demand_ku - reported_demand)
    local effective_avail_ku   = avail_ku - extra_unaccounted_ku

    if effective_avail_ku < 0 then
        set_belt_idle(pos, node, string.format(
            "Mechanical Belt: OVERSTRESSED! (%d KU needed / %d KU avail)",
            total_span_demand_ku, avail_ku + reported_demand
        ))
        return
    end

    local relay_supply_ku = effective_avail_ku + math.max(0, total_span_demand_ku - get_belt_span_demand_ku(rpm))

    active_belt_spans[span_key] = {
        rpm       = rpm,
        spin_dir  = spin_dir,
        supply_ku = supply_ku,
        avail_ku  = effective_avail_ku,
    }

    local relay_pulleys = {}
    for _, bpos in ipairs(span) do
        local bnode = core.get_node(bpos)
        if is_belt_node(bnode.name) then
            local hk        = core.hash_node_position(bpos)
            local bmeta     = core.get_meta(bpos)
            local shape     = get_belt_shape(bnode.name, bmeta)
            local has_shaft = (bmeta:get_int("has_shaft") == 1)
            local mode_lbl  = format_belt_mode_label(shape)

            local is_relay = has_shaft and (not pulley_has_gen[hk])
            update_single_belt_visual_and_timer(bpos, bnode, rpm, spin_dir, is_relay)
            bnode = core.get_node(bpos)

            if is_relay then
                bmeta:set_int("source_active", 1)
                bmeta:set_int("source_ku", math.max(1, relay_supply_ku))
                bmeta:set_float("source_rpm", rpm)
                bmeta:set_int("source_spin", spin_dir)
                bmeta:set_int("local_spin", spin_dir)
                relay_pulleys[#relay_pulleys + 1] = {pos = bpos, node = bnode}
            else
                bmeta:set_int("source_active", 0)
                bmeta:set_int("source_ku", 0)
                bmeta:set_float("source_rpm", 0)
                bmeta:set_int("source_spin", 0)
            end

            bmeta:set_float("rpm", rpm)
            bmeta:set_int("spin_dir", spin_dir)
            bmeta:set_int("rotational_power", effective_avail_ku)
            bmeta:set_int("network_supply_ku", supply_ku)
            bmeta:set_int("machine_demand_ku", pulley_has_gen[hk] and total_span_demand_ku or 0)
            bmeta:set_int("lit_until", now + 2)

            if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
                bmeta:set_string("infotext", "")
            else
                bmeta:set_string("infotext", string.format(
                    "Mechanical Belt (%s | %s): ACTIVE (%d KU avail / %d KU total | %d KU belt load | %.0f RPM)",
                    mode_lbl, tier_lbl, effective_avail_ku, supply_ku, total_span_demand_ku, rpm
                ))
            end
            bmeta:set_string("glasses_info", format_belt_glasses_info(bpos, bnode))
        end
    end

    if belt_relay_depth < 4 and #relay_pulleys > 0 then
        belt_relay_depth = belt_relay_depth + 1
        for _, rp in ipairs(relay_pulleys) do
            notify_pulley_and_axle_neighbors(rp.pos, rp.node)
        end
        belt_relay_depth = belt_relay_depth - 1
    end
end

local function refresh_entire_belt_span(pos)
    local meta = core.get_meta(pos)
    local span = get_belt_span_positions(pos, meta)
    local own_span_hashes = {}
    for _, bpos in ipairs(span) do
        own_span_hashes[core.hash_node_position(bpos)] = true
    end

    local gen_pulleys   = {}
    local relay_pulleys = {}
    for _, bpos in ipairs(span) do
        local bnode = core.get_node(bpos)
        if is_belt_node(bnode.name) and core.get_meta(bpos):get_int("has_shaft") == 1 then
            if pulley_reaches_real_generator(bpos, bnode, own_span_hashes) then
                gen_pulleys[#gen_pulleys + 1] = {pos = bpos, node = bnode}
            else
                relay_pulleys[#relay_pulleys + 1] = {pos = bpos, node = bnode}
            end
        end
    end

    if #gen_pulleys > 0 then
        for _, gp in ipairs(gen_pulleys) do
            notify_pulley_and_axle_neighbors(gp.pos, gp.node)
        end
        for _, rp in ipairs(relay_pulleys) do
            notify_pulley_and_axle_neighbors(rp.pos, core.get_node(rp.pos))
        end
    else
        set_belt_idle(pos, core.get_node(pos))
    end
end

local function belt_timer(pos, elapsed)
    local now  = math.floor(core.get_gametime())
    local meta = core.get_meta(pos)
    local node = core.get_node(pos)

    if kinetica.update_network then
        if now >= meta:get_int("lit_until") then
            refresh_entire_belt_span(pos)
            node = core.get_node(pos)
        elseif meta:get_int("has_shaft") == 1 and meta:get_int("source_active") == 1 then
            for _, nb in ipairs(get_connected_axle_neighbors(pos, node)) do
                local nmeta = core.get_meta(nb.pos)
                if nmeta:get_float("rpm") <= 0 or nmeta:get_int("lit_until") <= now then
                    refresh_entire_belt_span(pos)
                    node = core.get_node(pos)
                    break
                end
            end
        end
    end

    local is_active, rpm, spin_dir, _ = get_effective_belt_power(pos, meta, node)
    if not is_active then
        set_belt_idle(pos, node)
        return false
    end

    local is_relay = (meta:get_int("source_active") == 1)
    update_single_belt_visual_and_timer(pos, node, rpm, spin_dir, is_relay)
    scan_and_move_entities_on_belt(pos, core.get_node(pos))
    meta:set_string("glasses_info", format_belt_glasses_info(pos, core.get_node(pos)))

    core.get_node_timer(pos):start(CONFIG.TIMER_INTERVAL)
    return false
end

if kinetica.register_kinetic_machine then
    kinetica.register_kinetic_machine("kinetica:belt", {
        can_ride_piston = false,
        get_demand_ku   = function(rpm, pos, node)
            if not pos then
                return get_belt_span_demand_ku(rpm)
            end
            local meta = core.get_meta(pos)
            if meta:get_int("has_shaft") == 0 or meta:get_int("source_active") == 1 then
                return 0
            end
            local span = get_belt_span_positions(pos, meta)
            local own_span_hashes = {}
            for _, bpos in ipairs(span) do
                own_span_hashes[core.hash_node_position(bpos)] = true
            end
            for _, bpos in ipairs(span) do
                local bnode = core.get_node(bpos)
                if is_belt_node(bnode.name) and core.get_meta(bpos):get_int("has_shaft") == 1 then
                    if pulley_reaches_real_generator(bpos, bnode, own_span_hashes) then
                        if bpos.x == pos.x and bpos.y == pos.y and bpos.z == pos.z then
                            return get_belt_span_total_demand_ku(pos, rpm)
                        else
                            return 0
                        end
                    end
                end
            end
            return get_belt_span_total_demand_ku(pos, rpm)
        end,
        has_axle_port   = function(node, d)
            if is_no_shaft_belt_name(node.name) then
                return false
            end
            local axle = get_belt_axle_axis(node.name, node.param2)
            return (math.abs(d.x) == axle.x) and
                   (math.abs(d.y) == axle.y) and
                   (math.abs(d.z) == axle.z)
        end,
        set_idle = set_belt_idle,
        wake     = wake_belt,
    })
end

local function build_16slice_slope_nodebox(y_start, y_end)
    local half_t = HT or (4 / 16)
    local boxes  = {}
    local slices = 16
    for s = 0, slices - 1 do
        local z1 = -0.5 + (s / slices)
        local z2 = -0.5 + ((s + 1) / slices)
        local z_mid = (z1 + z2) * 0.5
        local t = 0.5 - z_mid
        local y_center = y_start + (y_end - y_start) * t
        boxes[#boxes + 1] = {-0.5, y_center - half_t, z1, 0.5, y_center + half_t, z2}
    end
    return {
        type  = "fixed",
        fixed = boxes,
    }
end

local FLAT_BOX = {
    type  = "fixed",
    fixed = {
        {-8/16, -HT, -8/16, 8/16, HT, 8/16},
    },
}

local VERT_BOX = {
    type  = "fixed",
    fixed = {
        {-8/16, -8/16, -HT, 8/16, 8/16, HT},
    },
}

local SIDEWAYS_BOX = {
    type  = "fixed",
    fixed = {
        {-HT, -8/16, -8/16, HT, 8/16, 8/16},
    },
}

local SLOPE_BOT_BOX = build_16slice_slope_nodebox( 0.0,  0.5)
local SLOPE_MID_BOX = build_16slice_slope_nodebox(-0.5,  0.5)
local SLOPE_TOP_BOX = build_16slice_slope_nodebox(-0.5,  0.0)

local SHAPE_GEOM = {
    flat      = {box = FLAT_BOX,      col = FLAT_BOX},
    slope_bot = {box = SLOPE_BOT_BOX, col = SLOPE_BOT_BOX},
    slope_mid = {box = SLOPE_MID_BOX, col = SLOPE_MID_BOX},
    slope_top = {box = SLOPE_TOP_BOX, col = SLOPE_TOP_BOX},
    vert      = {box = VERT_BOX,      col = VERT_BOX},
    sideways  = {box = SIDEWAYS_BOX,  col = SIDEWAYS_BOX},
}

local top_idle            = CONFIG.TEX_BELT_TOP .. "^[sheet:1x4:0,0"
local side_with_shaft     = "[combine:16x16:0,0=" .. CONFIG.TEX_BELT_SIDE .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY
local side_with_shaft_r90 = "[combine:16x16:0,0=" .. CONFIG.TEX_BELT_SIDE .. "\\^[transformR90:0,0=" .. CONFIG.TEX_SHAFT_OVERLAY
local side_no_shaft       = CONFIG.TEX_BELT_SIDE
local side_no_shaft_r90   = CONFIG.TEX_BELT_SIDE .. "^[transformR90"

local function make_belt_top_anim(reverse_scroll, anim_length, frame_transform)
    frame_transform = frame_transform or ""
    if CONFIG.INVERT_TOP_TEX_SCROLL then
        reverse_scroll = not reverse_scroll
    end

    local top = CONFIG.TEX_BELT_TOP
    local f0, f1, f2, f3
    if reverse_scroll then
        f0, f1, f2, f3 = "0", "3", "2", "1"
    else
        f0, f1, f2, f3 = "0", "1", "2", "3"
    end

    local final_tex
    if frame_transform == "" and not reverse_scroll then
        final_tex = top
    else
        local escaped_tf = string.gsub(frame_transform, "%^", "\\^")
        final_tex = "[combine:16x64" ..
            ":0,0="  .. top .. "\\^[sheet\\:1x4\\:0," .. f0 .. escaped_tf ..
            ":0,16=" .. top .. "\\^[sheet\\:1x4\\:0," .. f1 .. escaped_tf ..
            ":0,32=" .. top .. "\\^[sheet\\:1x4\\:0," .. f2 .. escaped_tf ..
            ":0,48=" .. top .. "\\^[sheet\\:1x4\\:0," .. f3 .. escaped_tf
    end
    return {
        name = final_tex,
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length,
        },
    }
end

local function make_belt_side_anim(reverse_spin, anim_length, rotate_bg_90)
    local bg = rotate_bg_90 and (CONFIG.TEX_BELT_SIDE .. "\\^[transformR90") or CONFIG.TEX_BELT_SIDE
    local ov = CONFIG.TEX_SHAFT_OVERLAY

    local bg_strip = "[combine:16x64:0,0=" .. bg .. ":0,16=" .. bg .. ":0,32=" .. bg .. ":0,48=" .. bg
    local ov_strip = ov
    if reverse_spin then
        ov_strip = "[combine:16x64" ..
            ":0,0="  .. ov .. "\\^[sheet\\:1x4\\:0,0" ..
            ":0,16=" .. ov .. "\\^[sheet\\:1x4\\:0,3" ..
            ":0,32=" .. ov .. "\\^[sheet\\:1x4\\:0,2" ..
            ":0,48=" .. ov .. "\\^[sheet\\:1x4\\:0,1"
    end
    return {
        name = "(" .. bg_strip .. ")^(" .. ov_strip .. ")",
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length,
        },
    }
end

local function build_belt_tiles(shape, is_idle, is_reverse_travel, anim_len, has_shaft)
    if shape == "sideways" then
        if is_idle then
            local shaft_face = has_shaft and side_with_shaft_r90 or side_no_shaft_r90
            local tread_idle = top_idle .. "^[transformR90"
            return {
                shaft_face,
                shaft_face,
                tread_idle,
                tread_idle,
                tread_idle,
                tread_idle,
            }
        end

        local top_shaft  = has_shaft and make_belt_side_anim(not is_reverse_travel, anim_len, true) or side_no_shaft_r90
        local bot_shaft  = has_shaft and make_belt_side_anim(is_reverse_travel,     anim_len, true) or side_no_shaft_r90
        local right_anim = make_belt_top_anim(not is_reverse_travel, anim_len, "^[transformR90")
        local left_anim  = make_belt_top_anim(is_reverse_travel,     anim_len, "^[transformR90")
        local back_anim  = make_belt_top_anim(is_reverse_travel,     anim_len, "^[transformR90")
        local front_anim = make_belt_top_anim(not is_reverse_travel, anim_len, "^[transformR90")

        return {
            top_shaft,
            bot_shaft,
            right_anim,
            left_anim,
            back_anim,
            front_anim,
        }
    end

    local rot_side_bg = (shape == "vert")
    if is_idle then
        local side_tex
        if rot_side_bg then
            side_tex = has_shaft and side_with_shaft_r90 or side_no_shaft_r90
        else
            side_tex = has_shaft and side_with_shaft or side_no_shaft
        end
        return {
            top_idle,
            top_idle,
            side_tex,
            side_tex,
            top_idle .. "^[transformR180",
            top_idle,
        }
    end

    local idle_side_no_shaft = rot_side_bg and side_no_shaft_r90 or side_no_shaft
    local top_anim   = make_belt_top_anim(not is_reverse_travel, anim_len, "")
    local bot_anim   = make_belt_top_anim(is_reverse_travel,     anim_len, "")
    local right_anim = has_shaft and make_belt_side_anim(not is_reverse_travel, anim_len, rot_side_bg) or idle_side_no_shaft
    local left_anim  = has_shaft and make_belt_side_anim(is_reverse_travel,     anim_len, rot_side_bg) or idle_side_no_shaft
    local back_anim  = make_belt_top_anim(is_reverse_travel,     anim_len, "")
    local front_anim = make_belt_top_anim(not is_reverse_travel, anim_len, "")

    return {
        top_anim,
        bot_anim,
        right_anim,
        left_anim,
        back_anim,
        front_anim,
    }
end

local function on_belt_after_dig(pos, oldnode, oldmetadata, digger)
    active_conveyor_nodes[core.hash_node_position(pos)] = nil
    if is_dismantling_belt then return end

    local fields      = oldmetadata and oldmetadata.fields or {}
    local seg_len     = tonumber(fields.seg_len) or 0
    local has_end_pos = (tonumber(fields.has_end_pos) == 1)

    local span_positions = {}
    if seg_len > 0 then
        local sx = tonumber(fields.start_x) or pos.x
        local sy = tonumber(fields.start_y) or pos.y
        local sz = tonumber(fields.start_z) or pos.z

        local span_key = core.hash_node_position({x = sx, y = sy, z = sz})
        active_belt_spans[span_key] = nil

        if has_end_pos then
            local ex = tonumber(fields.end_x) or pos.x
            local ey = tonumber(fields.end_y) or pos.y
            local ez = tonumber(fields.end_z) or pos.z
            local seen = {}
            for i = 0, seg_len do
                local p  = get_interpolated_belt_pos(sx, sy, sz, ex, ey, ez, seg_len, i)
                local hk = core.hash_node_position(p)
                if not seen[hk] then
                    seen[hk] = true
                    span_positions[#span_positions + 1] = p
                end
            end
        else
            local step_x = tonumber(fields.step_x) or 0
            local step_y = tonumber(fields.step_y) or 0
            local step_z = tonumber(fields.step_z) or 0
            for i = 0, seg_len do
                span_positions[#span_positions + 1] = {
                    x = sx + step_x * i,
                    y = sy + step_y * i,
                    z = sz + step_z * i,
                }
            end
        end
    else
        span_positions = {pos}
        active_belt_spans[core.hash_node_position(pos)] = nil
    end

    is_dismantling_belt = true

    local restored_shafts = {}
    for _, bpos in ipairs(span_positions) do
        local is_dug_pos = (bpos.x == pos.x and bpos.y == pos.y and bpos.z == pos.z)
        local has_shaft  = false
        local shaft_p2   = 0

        if is_dug_pos then
            has_shaft = (tonumber(fields.has_shaft) == 1)
            shaft_p2  = tonumber(fields.shaft_param2) or 0
        else
            local bnode = core.get_node(bpos)
            if is_belt_node(bnode.name) then
                local bmeta = core.get_meta(bpos)
                has_shaft = (bmeta:get_int("has_shaft") == 1)
                shaft_p2  = bmeta:get_int("shaft_param2")
            end
        end

        active_conveyor_nodes[core.hash_node_position(bpos)] = nil

        if has_shaft then
            core.set_node(bpos, {name = "kinetica:shaft", param2 = shaft_p2})
            restored_shafts[#restored_shafts + 1] = bpos
        elseif not is_dug_pos then
            local bnode = core.get_node(bpos)
            if is_belt_node(bnode.name) then
                core.remove_node(bpos)
            end
        end
    end

    is_dismantling_belt = false

    for _, spos in ipairs(restored_shafts) do
        if kinetica.update_network then
            kinetica.update_network(spos)
        end
    end
end

local function is_shaft_item_name(name)
    if not name or name == "" then return false end
    if name == "kinetica:shaft" then return true end
    if kinetica.is_shaft and kinetica.is_shaft(name) then return true end
    if string.find(name, "kinetica:shaft", 1, true) == 1 then return true end
    return false
end

local function insert_shaft_into_belt(pos, node, player, itemstack)
    node = node or core.get_node(pos)
    if not is_belt_node(node.name) then
        return false
    end

    local meta      = core.get_meta(pos)
    local has_shaft = (meta:get_int("has_shaft") == 1) and not is_no_shaft_belt_name(node.name)
    if has_shaft then
        return false
    end

    local axle = get_belt_axle_axis(node.name, node.param2)
    local shaft_p2 = 0
    if axle.y ~= 0 then
        shaft_p2 = 4
    elseif axle.x ~= 0 then
        shaft_p2 = 1
    else
        shaft_p2 = 0
    end

    meta:set_int("has_shaft", 1)
    meta:set_int("shaft_param2", shaft_p2)

    local is_active, rpm, spin_dir, _ = get_effective_belt_power(pos, meta, node)
    local own_span_hashes = {}
    for _, bpos in ipairs(get_belt_span_positions(pos, meta)) do
        own_span_hashes[core.hash_node_position(bpos)] = true
    end
    local reaches_gen = pulley_reaches_real_generator(pos, node, own_span_hashes)
    local is_relay    = is_active and (not reaches_gen)

    update_single_belt_visual_and_timer(pos, node, is_active and rpm or 0, is_active and spin_dir or 0, is_relay)
    spawn_belt_particles(pos, "select")

    if player and not core.is_creative_enabled(player:get_player_name()) and itemstack then
        itemstack:take_item(1)
    end

    refresh_entire_belt_span(pos)
    return true
end

local function try_extend_or_insert_shaft_on_belt(pos, node, clicker, itemstack, pointed_thing)
    node = node or core.get_node(pos)
    local meta      = core.get_meta(pos)
    local has_shaft = (meta:get_int("has_shaft") == 1) and not is_no_shaft_belt_name(node.name)

    if not has_shaft then
        insert_shaft_into_belt(pos, node, clicker, itemstack)
        return true
    end

    local pname    = clicker and clicker:is_player() and clicker:get_player_name() or ""
    local shaft_p2 = meta:get_int("shaft_param2")
    local axle     = get_belt_axle_axis(node.name, node.param2)

    if pointed_thing and pointed_thing.above then
        local d = vector.subtract(pointed_thing.above, pos)
        if math.abs(d.x) == axle.x and math.abs(d.y) == axle.y and math.abs(d.z) == axle.z then
            local anode = core.get_node(pointed_thing.above)
            local adef  = core.registered_nodes[anode.name]
            if anode.name == "air" or (adef and adef.buildable_to) then
                core.set_node(pointed_thing.above, {name = "kinetica:shaft", param2 = shaft_p2})
                if pname ~= "" and not core.is_creative_enabled(pname) then
                    itemstack:take_item(1)
                end
                refresh_entire_belt_span(pos)
                if kinetica.update_network then
                    kinetica.update_network(pointed_thing.above)
                end
                return true
            end
        end
    end

    for _, d in ipairs(get_belt_axle_dirs(node.name, node.param2)) do
        local npos  = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
        local nnode = core.get_node(npos)
        local ndef  = core.registered_nodes[nnode.name]
        if nnode.name == "air" or (ndef and ndef.buildable_to) then
            core.set_node(npos, {name = "kinetica:shaft", param2 = shaft_p2})
            if pname ~= "" and not core.is_creative_enabled(pname) then
                itemstack:take_item(1)
            end
            refresh_entire_belt_span(pos)
            if kinetica.update_network then
                kinetica.update_network(npos)
            end
            return true
        end
    end

    return true
end

local function try_pickup_item_from_belt(pos, clicker)
    local inv = clicker:get_inventory()
    if not inv then return false end

    local objs = core.get_objects_inside_radius({x = pos.x, y = pos.y + 0.35, z = pos.z}, 1.15)
    for _, obj in ipairs(objs) do
        local luaent = obj:get_luaentity()
        if luaent and luaent.name == "__builtin:item" and luaent.itemstring and luaent.itemstring ~= "" then
            local stack = ItemStack(luaent.itemstring)
            if inv:room_for_item("main", stack) then
                inv:add_item("main", stack)
                active_belt_items[obj] = nil
                obj:remove()
                return true
            end
        end
    end
    return false
end

local function on_belt_rightclick(pos, node, clicker, itemstack, pointed_thing)
    if not clicker or not clicker:is_player() then return itemstack end
    local pname      = clicker:get_player_name()
    local wield_name = itemstack and itemstack:get_name() or ""
    local meta       = core.get_meta(pos)
    local has_shaft  = (meta:get_int("has_shaft") == 1) and not is_no_shaft_belt_name(node.name)
    local shape      = get_belt_shape(node.name, meta)

    if is_shaft_item_name(wield_name) then
        try_extend_or_insert_shaft_on_belt(pos, node, clicker, itemstack, pointed_thing)
        return itemstack
    end

    if wield_name == BELT_ITEM then
        return itemstack
    end

    if not itemstack or itemstack:is_empty() then
        local seg_len = meta:get_int("seg_len")
        local b_idx   = meta:get_int("belt_index")
        if clicker:get_player_control().sneak and has_shaft and seg_len > 0 and b_idx > 0 and b_idx < seg_len then
            meta:set_int("has_shaft", 0)
            meta:set_int("source_active", 0)
            meta:set_int("source_ku", 0)
            meta:set_float("source_rpm", 0)
            meta:set_int("source_spin", 0)

            local is_active, rpm, spin_dir, _ = get_effective_belt_power(pos, meta, node)
            update_single_belt_visual_and_timer(pos, node, is_active and rpm or 0, is_active and spin_dir or 0, false)

            local inv = clicker:get_inventory()
            if inv and not core.is_creative_enabled(pname) then
                local leftover = inv:add_item("main", "kinetica:shaft")
                if not leftover:is_empty() then
                    core.add_item(pos, leftover)
                end
            end

            for _, nb in ipairs(get_connected_axle_neighbors(pos, node)) do
                if kinetica.update_network then
                    kinetica.update_network(nb.pos)
                end
            end
            refresh_entire_belt_span(pos)
            return itemstack
        end

        try_pickup_item_from_belt(pos, clicker)
        return itemstack
    end

    if shape ~= "sideways" then
        local surf_y, _ = get_belt_surface_y_and_slope(pos, node, pos.x, pos.z)
        if surf_y then
            local drop_stack = itemstack:peek_item(1)
            local spawn_pos  = {x = pos.x, y = surf_y + 0.02, z = pos.z}
            local obj        = core.add_item(spawn_pos, drop_stack)
            if obj then
                local luaent = obj:get_luaentity()
                if luaent then
                    step_belt_item(obj, luaent, pos, node, spawn_pos, 0)
                end
                local hkey = core.hash_node_position(pos)
                active_conveyor_nodes[hkey] = {pos = {x = pos.x, y = pos.y, z = pos.z}}
                local timer = core.get_node_timer(pos)
                if not timer:is_started() then
                    timer:start(CONFIG.TIMER_INTERVAL)
                end
                if not core.is_creative_enabled(pname) then
                    itemstack:take_item(1)
                end
                return itemstack
            end
        end
    end
    return itemstack
end

local orig_item_place = core.item_place
function core.item_place(itemstack, placer, pointed_thing, param2)
    if pointed_thing and pointed_thing.type == "node" and pointed_thing.under and itemstack then
        local wname = itemstack:get_name()
        if is_shaft_item_name(wname) then
            local unode = core.get_node(pointed_thing.under)
            if is_belt_node(unode.name) then
                try_extend_or_insert_shaft_on_belt(pointed_thing.under, unode, placer, itemstack, pointed_thing)
                return itemstack, nil
            end
        end
    end
    return orig_item_place(itemstack, placer, pointed_thing, param2)
end

core.register_on_mods_loaded(function()
    for name, def in pairs(core.registered_nodes) do
        if is_shaft_item_name(name) and def.on_place then
            local orig_shaft_on_place = def.on_place
            core.override_item(name, {
                on_place = function(itemstack, placer, pointed_thing, param2)
                    if pointed_thing and pointed_thing.type == "node" and pointed_thing.under then
                        local unode = core.get_node(pointed_thing.under)
                        if is_belt_node(unode.name) then
                            try_extend_or_insert_shaft_on_belt(
                                pointed_thing.under, unode, placer, itemstack, pointed_thing
                            )
                            return itemstack
                        end
                    end
                    return orig_shaft_on_place(itemstack, placer, pointed_thing, param2)
                end,
            })
        end
    end
end)

core.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
    if not kinetica.is_kinetic_node or not kinetica.is_kinetic_node(newnode.name) then
        return
    end
    for _, d in ipairs(ALL_6_DIRS) do
        local npos  = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
        local nnode = core.get_node(npos)
        if is_belt_node(nnode.name) and core.get_meta(npos):get_int("has_shaft") == 1 then
            core.after(0, function()
                if is_belt_node(core.get_node(npos).name) then
                    refresh_entire_belt_span(npos)
                end
            end)
        end
    end
end)

core.register_on_dignode(function(pos, oldnode, digger)
    if not kinetica.is_kinetic_node or not kinetica.is_kinetic_node(oldnode.name) then
        return
    end
    for _, d in ipairs(ALL_6_DIRS) do
        local npos  = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
        local nnode = core.get_node(npos)
        if is_belt_node(nnode.name) and core.get_meta(npos):get_int("has_shaft") == 1 then
            core.after(0, function()
                if is_belt_node(core.get_node(npos).name) then
                    refresh_entire_belt_span(npos)
                end
            end)
        end
    end
end)

local function register_belt_variant(node_name, shape, is_idle, is_rev, anim_len, has_shaft)
    local geom  = SHAPE_GEOM[shape] or SHAPE_GEOM.flat
    local tiles = build_belt_tiles(shape, is_idle, is_rev, anim_len, has_shaft)

    core.register_node(node_name, {
        description           = "Mechanical Belt",
        drawtype              = "nodebox",
        tiles                 = tiles,
        use_texture_alpha     = "clip",
        paramtype             = "light",
        paramtype2            = "facedir",
        sunlight_propagates   = true,
        is_ground_content     = false,
        node_box              = geom.box,
        selection_box         = geom.box,
        collision_box         = geom.col,
        drop                  = BELT_ITEM,
        groups = {
            handy                     = 1,
            axey                      = 1,
            pickaxey                  = 1,
            not_in_creative_inventory = 1,
            kinetic_machine           = 1,
            mechanical_belt           = 1,
        },
        _mcl_hardness         = 1.5,
        _mcl_blast_resistance = 3.0,
        on_construct = function(pos)
            core.get_node_timer(pos):start(CONFIG.TIMER_INTERVAL)
        end,
        on_timer       = belt_timer,
        after_dig_node = on_belt_after_dig,
        on_rightclick  = on_belt_rightclick,
    })
end

local SHAPES_TO_REGISTER = {"flat", "slope_bot", "slope_mid", "slope_top", "vert", "sideways"}

for _, shape in ipairs(SHAPES_TO_REGISTER) do
    for _, has_shaft in ipairs({true, false}) do
        local ns_suffix = has_shaft and "" or "_ns"
        local idle_name = (shape == "flat")
            and (IDLE_NAME .. ns_suffix)
            or  (IDLE_NAME .. "_" .. shape .. "_idle" .. ns_suffix)
        register_belt_variant(idle_name, shape, true, false, 0.48, has_shaft)
    end

    for _, tinfo in ipairs(CONFIG.ANIM_TIERS) do
        for _, is_rev in ipairs({false, true}) do
            local rev_suffix = is_rev and "_rev" or ""
            for _, role in ipairs({"", "_ns", "_relay"}) do
                local has_shaft = (role ~= "_ns")
                local prefix    = (shape == "flat") and IDLE_NAME or (IDLE_NAME .. "_" .. shape)
                local full_name = prefix .. "_" .. tinfo.name .. rev_suffix .. role
                register_belt_variant(full_name, shape, false, is_rev, tinfo.length, has_shaft)
            end
        end
    end
end

core.register_lbm({
    label             = "Wake Mechanical Belts on chunk load",
    name              = "kinetica:wake_belts_lbm",
    nodenames         = {"group:mechanical_belt"},
    run_at_every_load = true,
    action = function(pos, node)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TIMER_INTERVAL)
        end
        if not is_idle_belt_name(node.name) and get_belt_shape(node.name, nil) ~= "sideways" then
            active_conveyor_nodes[core.hash_node_position(pos)] = {
                pos = {x = pos.x, y = pos.y, z = pos.z},
            }
        end
    end,
})

local function get_shaft_axis_vec(param2)
    if kinetica.abs_axis then
        return kinetica.abs_axis(param2)
    end
    local axis_idx = math.floor((param2 or 0) / 4)
    if axis_idx == 0 or axis_idx == 5 then
        return {x = 0, y = 1, z = 0}
    elseif axis_idx == 1 or axis_idx == 2 then
        return {x = 0, y = 0, z = 1}
    else
        return {x = 1, y = 0, z = 0}
    end
end

local function dir_to_belt_param2(dx, dz, shaft_axis)
    if dx > 0 then
        return 3
    elseif dx < 0 then
        return 1
    elseif dz > 0 then
        return 2
    elseif dz < 0 then
        return 0
    end
    if shaft_axis and shaft_axis.x ~= 0 then
        return 2
    end
    return 3
end

local function compute_span_block_shape(span_nodes, k, ax1, adx, ady, adz)
    if ax1.y ~= 0 then
        return "sideways"
    elseif adx == 0 and adz == 0 and ady > 0 then
        return "vert"
    elseif ady == 0 then
        return "flat"
    end

    local total  = #span_nodes
    local cur_y  = span_nodes[k].pos.y
    local prev_y = (k > 1)     and span_nodes[k - 1].pos.y or cur_y
    local next_y = (k < total) and span_nodes[k + 1].pos.y or cur_y
    local rises_from_prev = (cur_y > prev_y)
    local rises_to_next   = (next_y > cur_y)

    if rises_from_prev and rises_to_next then
        return "slope_mid"
    elseif not rises_from_prev and rises_to_next then
        return "slope_bot"
    elseif rises_from_prev and not rises_to_next then
        return "slope_top"
    else
        return "flat"
    end
end

local function try_place_belt_span(player, pos1, pos2)
    local pname = player:get_player_name()
    local node1 = core.get_node(pos1)
    local node2 = core.get_node(pos2)

    if not (kinetica.is_shaft and kinetica.is_shaft(node1.name)) or
       not (kinetica.is_shaft and kinetica.is_shaft(node2.name)) then
        core.chat_send_player(pname, "[Kinetica] Both endpoints must be Shafts!")
        return false
    end

    local ax1 = get_shaft_axis_vec(node1.param2)
    local ax2 = get_shaft_axis_vec(node2.param2)
    if ax1.x ~= ax2.x or ax1.y ~= ax2.y or ax1.z ~= ax2.z then
        core.chat_send_player(pname, "[Kinetica] Both shafts must face the same axis!")
        return false
    end

    local dx  = pos2.x - pos1.x
    local dy  = pos2.y - pos1.y
    local dz  = pos2.z - pos1.z
    local adx = math.abs(dx)
    local ady = math.abs(dy)
    local adz = math.abs(dz)

    if adx == 0 and ady == 0 and adz == 0 then
        return false
    end

    if (ax1.x ~= 0 and adx ~= 0) or
       (ax1.y ~= 0 and ady ~= 0) or
       (ax1.z ~= 0 and adz ~= 0) then
        core.chat_send_player(pname, "[Kinetica] Belt path must be perpendicular to the shaft axis!")
        return false
    end

    if adx > 0 and adz > 0 then
        core.chat_send_player(pname, "[Kinetica] Belts must align along the X or Z axis!")
        return false
    end

    local horiz_len = math.max(adx, adz)
    if horiz_len > 0 and ady > horiz_len then
        core.chat_send_player(pname, "[Kinetica] Slope is too steep (vertical rise cannot exceed horizontal run)!")
        return false
    end

    local seg_len = math.max(adx, ady, adz)
    if seg_len > CONFIG.MAX_BELT_LENGTH then
        core.chat_send_player(pname, string.format(
            "[Kinetica] Belt span too long (%d blocks; max is %d)!",
            seg_len, CONFIG.MAX_BELT_LENGTH
        ))
        return false
    end

    local sx, sy, sz = pos1.x, pos1.y, pos1.z
    local ex, ey, ez = pos2.x, pos2.y, pos2.z
    if ey < sy then
        sx, sy, sz, ex, ey, ez = ex, ey, ez, sx, sy, sz
        dx, dy, dz = -dx, -dy, -dz
    end

    local param2 = dir_to_belt_param2(dx, dz, ax1)
    local span_nodes = {}
    local seen       = {}
    for i = 0, seg_len do
        local p  = get_interpolated_belt_pos(sx, sy, sz, ex, ey, ez, seg_len, i)
        local hk = core.hash_node_position(p)
        if not seen[hk] then
            seen[hk] = true
            local cnode = core.get_node(p)
            local cdef  = core.registered_nodes[cnode.name]
            local is_sh = (kinetica.is_shaft and kinetica.is_shaft(cnode.name))
            if is_sh then
                local cax = get_shaft_axis_vec(cnode.param2)
                if cax.x ~= ax1.x or cax.y ~= ax1.y or cax.z ~= ax1.z then
                    core.chat_send_player(pname, "[Kinetica] A misaligned shaft is blocking the belt path!")
                    return false
                end
            elseif cnode.name ~= "air" and not (cdef and cdef.buildable_to) then
                core.chat_send_player(pname, "[Kinetica] The belt path is obstructed!")
                return false
            end
            span_nodes[#span_nodes + 1] = {
                pos          = p,
                idx          = i,
                has_shaft    = is_sh,
                shaft_param2 = is_sh and cnode.param2 or node1.param2,
            }
        end
    end

    for k, info in ipairs(span_nodes) do
        local shape     = compute_span_block_shape(span_nodes, k, ax1, adx, ady, adz)
        local node_name = get_target_belt_node_name(shape, info.has_shaft, false, 0, param2, 0)
        core.set_node(info.pos, {name = node_name, param2 = param2})

        local bmeta = core.get_meta(info.pos)
        bmeta:set_string("belt_shape", shape)
        bmeta:set_int("has_shaft", info.has_shaft and 1 or 0)
        bmeta:set_int("shaft_param2", info.shaft_param2)
        bmeta:set_int("seg_len", seg_len)
        bmeta:set_int("belt_index", info.idx)
        bmeta:set_int("start_x", sx)
        bmeta:set_int("start_y", sy)
        bmeta:set_int("start_z", sz)
        bmeta:set_int("has_end_pos", 1)
        bmeta:set_int("end_x", ex)
        bmeta:set_int("end_y", ey)
        bmeta:set_int("end_z", ez)

        core.get_node_timer(info.pos):start(CONFIG.TIMER_INTERVAL)
        spawn_belt_particles(info.pos, "connect")
    end

    set_belt_idle(span_nodes[1].pos, core.get_node(span_nodes[1].pos))
    refresh_entire_belt_span(span_nodes[1].pos)

    return true
end

core.register_craftitem(BELT_ITEM, {
    description     = string.format("Mechanical Belt (Min %d RPM)\nRight-click two aligned Shafts to connect them with a conveyor belt.", CONFIG.MIN_RPM),
    inventory_image = CONFIG.TEX_BELT_SIDE,
    wield_image     = CONFIG.TEX_BELT_SIDE,
    on_place = function(itemstack, placer, pointed_thing)
        if not placer or not placer:is_player() then return itemstack end
        if pointed_thing.type ~= "node" then return itemstack end

        local pos   = pointed_thing.under
        local node  = core.get_node(pos)
        local pname = placer:get_player_name()

        if not (kinetica.is_shaft and kinetica.is_shaft(node.name)) then
            if player_selections[pname] then
                player_selections[pname] = nil
                core.chat_send_player(pname, "[Kinetica] Belt selection cleared.")
            end
            return itemstack
        end

        local sel = player_selections[pname]
        if not sel then
            player_selections[pname] = {
                pos  = {x = pos.x, y = pos.y, z = pos.z},
                axis = get_shaft_axis_vec(node.param2),
            }
            spawn_belt_particles(pos, "select")
            core.chat_send_player(pname, string.format(
                "[Kinetica] First shaft selected at (%d, %d, %d). Right-click a second shaft to connect!",
                pos.x, pos.y, pos.z
            ))
            return itemstack
        end

        if sel.pos.x == pos.x and sel.pos.y == pos.y and sel.pos.z == pos.z then
            player_selections[pname] = nil
            core.chat_send_player(pname, "[Kinetica] Belt selection cancelled.")
            return itemstack
        end

        player_selections[pname] = nil
        if try_place_belt_span(placer, sel.pos, pos) then
            if not core.is_creative_enabled(pname) then
                itemstack:take_item(1)
            end
        end
        return itemstack
    end,
})

core.register_craft({
    output = "kinetica:belt_item 2",
    recipe = {
        {"mcl_ocean:dried_kelp", "mcl_ocean:dried_kelp", "mcl_ocean:dried_kelp"},
        {"mcl_ocean:dried_kelp", "kinetica:andesite_alloy", "mcl_ocean:dried_kelp"},
    },
})