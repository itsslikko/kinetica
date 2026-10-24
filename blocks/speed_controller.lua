kinetica = kinetica or {}

local CONFIG = {
    OUTPUT_FACES_PLAYER       = false,
    ALLOW_VERTICAL_PLACEMENT  = true,
    DEFAULT_SLIDER_INDEX      = 0,
    ALLOW_SPIN_REVERSE_BUTTON = true,
    REDSTONE_FORCES_NEUTRAL   = true,
    MIN_INPUT_RPM             = 1,
    FRICTION_FINE_KU          = 1,
    MAX_OUTPUT_RPM            = 1024,
    ALLOW_CHAINED_CONTROLLERS = false,
    TIMER_INTERVAL            = 0.25,
    ANIM_LEN_INPUT            = 0.40,
    OUTPUT_ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    length = 0.85 },
        { name = "slow",   max_rpm = 15,   length = 0.48 },
        { name = "medium", max_rpm = 63,   length = 0.24 },
        { name = "fast",   max_rpm = 255,  length = 0.11 },
        { name = "hyper",  max_rpm = 1024, length = 0.05 },
    },
    SLIDER_MIN_INDEX          = -4,
    SLIDER_MAX_INDEX          = 4,
    SLIDER_STEPS = {
        [-4] = {
            idx = -4, short_label = "16x SPD", title = "16x SPEED OVERDRIVE",
            rpm_mult = 16.0,  ku_cost_mult = 16.0,  zone = "speed",
        },
        [-3] = {
            idx = -3, short_label = "8x SPD",  title = "8x SPEED OVERDRIVE",
            rpm_mult = 8.0,   ku_cost_mult = 8.0,   zone = "speed",
        },
        [-2] = {
            idx = -2, short_label = "4x SPD",  title = "4x SPEED OVERDRIVE",
            rpm_mult = 4.0,   ku_cost_mult = 4.0,   zone = "speed",
        },
        [-1] = {
            idx = -1, short_label = "2x SPD",  title = "2x SPEED OVERDRIVE",
            rpm_mult = 2.0,   ku_cost_mult = 2.0,   zone = "speed",
        },
        [0]  = {
            idx = 0,  short_label = "NEUTRAL", title = "NEUTRAL (CLUTCH DISENGAGED)",
            rpm_mult = 0.0,   ku_cost_mult = 0.0,   zone = "neutral",
        },
        [1]  = {
            idx = 1,  short_label = "1x DIR",  title = "1:1 DIRECT DRIVE",
            rpm_mult = 1.0,   ku_cost_mult = 1.0,   zone = "torque",
        },
        [2]  = {
            idx = 2,  short_label = "2x TRQ",  title = "2x TORQUE (0.5x RPM)",
            rpm_mult = 0.5,   ku_cost_mult = 0.5,   zone = "torque",
        },
        [3]  = {
            idx = 3,  short_label = "4x TRQ",  title = "4x TORQUE (0.25x RPM)",
            rpm_mult = 0.25,  ku_cost_mult = 0.25,  zone = "torque",
        },
        [4]  = {
            idx = 4,  short_label = "8x TRQ",  title = "8x TORQUE (0.125x RPM)",
            rpm_mult = 0.125, ku_cost_mult = 0.125, zone = "torque",
        },
    },
    UI_COLORS = {
        BG_WINDOW            = "#14171D",
        BG_HEADER            = "#1F242D",
        BG_CARD              = "#1B2028",
        BG_SLIDER_WELL       = "#0E1015",
        SPEED_ACCENT         = "#00D4FF",
        SPEED_BTN_BG         = "#123A4F",
        NEUTRAL_ACCENT       = "#FFB300",
        NEUTRAL_BTN_BG       = "#4A3510",
        TORQUE_ACCENT        = "#00E676",
        TORQUE_BTN_BG        = "#144227",
        ACTIVE_BTN_HIGHLIGHT = "#FFFFFF",
        STRESS_BG            = "#101216",
        STRESS_SAFE          = "#2ECC71",
        STRESS_WARN          = "#F39C12",
        STRESS_DANGER        = "#E74C3C",
        TEXT_TITLE           = "#F5B041",
        TEXT_SUBTITLE        = "#95A5A6",
        TEXT_LABEL           = "#ABB2B9",
        TEXT_VALUE           = "#FFFFFF",
        TEXT_OK              = "#2ECC71",
        TEXT_WARN            = "#F1C40F",
        TEXT_ERR             = "#FF5252",
    },
    TEX_TOP_BOTTOM         = "kinetica_speed_var_side.png",
    TEX_SIDE_CASING        = "kinetica_speed_var_side.png",
    TEX_INPUT_BG           = "kinetica_speed_var_front_off.png",
    TEX_OUTPUT_GEAR_IDLE   = "kinetica_speed_var_front_off.png",
    TEX_OUTPUT_GEAR_ACTIVE = "kinetica_speed_var_front_on.png",
    TEX_SHAFT_OVERLAY      = "kinetica_shaft_connecting_overlay.png",
}

local IDLE_NAME = "kinetica:speed_controller"

local function is_speed_controller(name)
    if not name then return false end
    return name == IDLE_NAME or string.sub(name, 1, #IDLE_NAME + 1) == (IDLE_NAME .. "_")
end
kinetica.is_speed_controller = is_speed_controller

local in_face_idle  = "[combine:16x16:0,0=" .. CONFIG.TEX_INPUT_BG         .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY
local out_face_idle = "[combine:16x16:0,0=" .. CONFIG.TEX_OUTPUT_GEAR_IDLE .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY

local function make_input_port_anim(reverse, anim_length)
    local casing = CONFIG.TEX_INPUT_BG
    local shaft  = CONFIG.TEX_SHAFT_OVERLAY

    local casing_strip = "[combine:16x64:0,0=" .. casing ..
        ":0,16=" .. casing .. ":0,32=" .. casing .. ":0,48=" .. casing

    local shaft_strip
    if reverse then
        shaft_strip = "[combine:16x64" ..
            ":0,0="  .. shaft .. "\\^[sheet\\:1x4\\:0,0" ..
            ":0,16=" .. shaft .. "\\^[sheet\\:1x4\\:0,3" ..
            ":0,32=" .. shaft .. "\\^[sheet\\:1x4\\:0,2" ..
            ":0,48=" .. shaft .. "\\^[sheet\\:1x4\\:0,1"
    else
        shaft_strip = shaft
    end

    return {
        name = "(" .. casing_strip .. ")^(" .. shaft_strip .. ")",
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length or CONFIG.ANIM_LEN_INPUT,
        },
    }
end

local function make_output_port_anim(reverse, anim_length)
    local gear  = CONFIG.TEX_OUTPUT_GEAR_ACTIVE
    local shaft = CONFIG.TEX_SHAFT_OVERLAY

    local gear_strip
    local shaft_strip

    if reverse then
        gear_strip = "[combine:16x64" ..
            ":0,0="  .. gear .. "\\^[sheet\\:1x3\\:0,0" ..
            ":0,16=" .. gear .. "\\^[sheet\\:1x3\\:0,2" ..
            ":0,32=" .. gear .. "\\^[sheet\\:1x3\\:0,1" ..
            ":0,48=" .. gear .. "\\^[sheet\\:1x3\\:0,2"

        shaft_strip = "[combine:16x64" ..
            ":0,0="  .. shaft .. "\\^[sheet\\:1x4\\:0,0" ..
            ":0,16=" .. shaft .. "\\^[sheet\\:1x4\\:0,3" ..
            ":0,32=" .. shaft .. "\\^[sheet\\:1x4\\:0,2" ..
            ":0,48=" .. shaft .. "\\^[sheet\\:1x4\\:0,1"
    else
        gear_strip = "[combine:16x64" ..
            ":0,0="  .. gear .. "\\^[sheet\\:1x3\\:0,0" ..
            ":0,16=" .. gear .. "\\^[sheet\\:1x3\\:0,1" ..
            ":0,32=" .. gear .. "\\^[sheet\\:1x3\\:0,2" ..
            ":0,48=" .. gear .. "\\^[sheet\\:1x3\\:0,1"

        shaft_strip = shaft
    end

    return {
        name = "(" .. gear_strip .. ")^(" .. shaft_strip .. ")",
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length,
        },
    }
end

local in_anim_cw  = make_input_port_anim(false, CONFIG.ANIM_LEN_INPUT)
local in_anim_ccw = make_input_port_anim(true,  CONFIG.ANIM_LEN_INPUT)

local function get_output_tier_name(out_rpm)
    if not out_rpm or out_rpm <= 0 then
        return "neutral"
    end
    for _, tier in ipairs(CONFIG.OUTPUT_ANIM_TIERS) do
        if out_rpm <= tier.max_rpm then
            return tier.name
        end
    end
    return CONFIG.OUTPUT_ANIM_TIERS[#CONFIG.OUTPUT_ANIM_TIERS].name
end

local ALL_6_DIRS = {
    {x =  1, y =  0, z =  0},
    {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0},
    {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1},
    {x =  0, y =  0, z = -1},
}

local function get_in_dir(param2)
    local d = core.facedir_to_dir(param2 or 0) or {x = 0, y = 0, z = 1}
    return {x = d.x, y = d.y, z = d.z}
end

local function get_out_dir(param2)
    local b = get_in_dir(param2)
    return {x = -b.x, y = -b.y, z = -b.z}
end

local function get_visual_spin_sign(param2, spin_dir)
    local back = get_in_dir(param2)
    local axis_sign = back.x + back.y + back.z
    return ((spin_dir or 1) * axis_sign >= 0) and 1 or -1
end

local function get_target_controller_node_name(param2, in_active, in_spin, out_active, out_rpm, rev_out)
    if not in_active or in_spin == 0 then
        return IDLE_NAME
    end

    local in_vis = get_visual_spin_sign(param2, in_spin)
    local in_tag = (in_vis == 1) and "cw" or "ccw"

    if not out_active or not out_rpm or out_rpm <= 0 then
        return IDLE_NAME .. "_neutral_" .. in_tag
    end

    local tier_name = get_output_tier_name(out_rpm)
    local out_tag   = rev_out and ((in_vis == 1) and "ccw" or "cw") or in_tag
    return IDLE_NAME .. "_" .. tier_name .. "_" .. in_tag .. "_" .. out_tag
end

local function clamp_slider_idx(idx)
    idx = math.floor(tonumber(idx) or CONFIG.DEFAULT_SLIDER_INDEX)
    if idx < CONFIG.SLIDER_MIN_INDEX then idx = CONFIG.SLIDER_MIN_INDEX end
    if idx > CONFIG.SLIDER_MAX_INDEX then idx = CONFIG.SLIDER_MAX_INDEX end
    return idx
end

local function get_step_info(meta)
    local idx = clamp_slider_idx(meta:get_int("slider_idx"))
    return CONFIG.SLIDER_STEPS[idx] or CONFIG.SLIDER_STEPS[0], idx
end

local function is_redstone_clutched(pos)
    if not CONFIG.REDSTONE_FORCES_NEUTRAL then
        return false
    end
    if mcl_redstone and mcl_redstone.get_power then
        local ok, pwr = pcall(mcl_redstone.get_power, vector.new(pos.x, pos.y, pos.z))
        if ok and pwr and pwr > 0 then
            return true
        end
    end
    return false
end

local function get_effective_step(pos, meta)
    if is_redstone_clutched(pos) then
        return CONFIG.SLIDER_STEPS[0], 0, true
    end
    local step, idx = get_step_info(meta)
    return step, idx, false
end

local function idx_to_scrollbar_val(idx)
    return (clamp_slider_idx(idx) - CONFIG.SLIDER_MIN_INDEX) + 1
end

local function scrollbar_val_to_idx(val)
    local n = math.floor((tonumber(val) or 5) + 0.5)
    return clamp_slider_idx((n - 1) + CONFIG.SLIDER_MIN_INDEX)
end

local active_relay_sc_hash = nil
local sc_relay_depth       = 0

local orig_is_source_node = kinetica.is_source_node
function kinetica.is_source_node(name)
    if orig_is_source_node and orig_is_source_node(name) then
        return true
    end
    if active_relay_sc_hash ~= nil and is_speed_controller(name) then
        return true
    end
    return false
end

local function is_real_generator_node(pos, node)
    if is_speed_controller(node.name) then
        return false -- A Speed Controller is a transmission relay, NEVER a primary generator!
    end
    if (kinetica.is_water_wheel and kinetica.is_water_wheel(node.name)) or
       (kinetica.is_turbine and kinetica.is_turbine(node.name)) or
       (orig_is_source_node and orig_is_source_node(node.name)) then
        local smeta = core.get_meta(pos)
        if smeta:get_int("source_active") == 1 and smeta:get_int("source_ku") > 0 then
            return true
        end
    end
    return false
end

local function are_kinetic_nodes_coupled(cur_pos, cur_node, npos, nnode, d, for_input_trace)
    local rev = {x = -d.x, y = -d.y, z = -d.z}

    if is_speed_controller(cur_node.name) then
        local port_dir = for_input_trace and get_out_dir(cur_node.param2) or get_in_dir(cur_node.param2)
        if d.x ~= port_dir.x or d.y ~= port_dir.y or d.z ~= port_dir.z then
            return false
        end
    elseif kinetica.has_axle_port and not kinetica.has_axle_port(cur_node, d) then
        if not (kinetica.is_chain_drive and kinetica.is_chain_drive(cur_node.name) and kinetica.is_chain_drive(nnode.name)) then
            return false
        end
    end

    if is_speed_controller(nnode.name) then
        local want_port = for_input_trace and get_out_dir(nnode.param2) or get_in_dir(nnode.param2)
        return (rev.x == want_port.x and rev.y == want_port.y and rev.z == want_port.z)
    end

    if kinetica.has_axle_port and kinetica.has_axle_port(nnode, rev) then
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

local function input_reaches_real_generator(sc_pos, sc_node, visited_sc)
    visited_sc = visited_sc or {}
    local my_hash = core.hash_node_position(sc_pos)
    if visited_sc[my_hash] then
        return false
    end
    visited_sc[my_hash] = true

    local in_dir = get_in_dir(sc_node.param2)
    local in_pos = {
        x = sc_pos.x + in_dir.x,
        y = sc_pos.y + in_dir.y,
        z = sc_pos.z + in_dir.z,
    }
    local in_node = core.get_node(in_pos)
    if not (kinetica.is_kinetic_node and kinetica.is_kinetic_node(in_node.name)) then
        return false
    end

    local rev_in = {x = -in_dir.x, y = -in_dir.y, z = -in_dir.z}
    if is_speed_controller(in_node.name) then
        if not CONFIG.ALLOW_CHAINED_CONTROLLERS then
            return false
        end
        local prev_out = get_out_dir(in_node.param2)
        if prev_out.x ~= rev_in.x or prev_out.y ~= rev_in.y or prev_out.z ~= rev_in.z then
            return false
        end
        local pmeta = core.get_meta(in_pos)
        if pmeta:get_int("sc_out_active") == 1 and pmeta:get_int("sc_out_ku") > 0 then
            return input_reaches_real_generator(in_pos, in_node, visited_sc)
        end
        return false
    elseif kinetica.has_axle_port and not kinetica.has_axle_port(in_node, rev_in) then
        return false
    end

    local visited = {
        [my_hash] = true,
        [core.hash_node_position(in_pos)] = true,
    }
    local queue = {{pos = in_pos, node = in_node}}
    local dirs  = kinetica.directions or ALL_6_DIRS
    local head  = 1

    while head <= #queue and #queue <= 384 do
        local cur = queue[head]
        head = head + 1

        if is_real_generator_node(cur.pos, cur.node) then
            return true
        end

        if is_speed_controller(cur.node.name) then
            if CONFIG.ALLOW_CHAINED_CONTROLLERS then
                local cmeta = core.get_meta(cur.pos)
                if cmeta:get_int("sc_out_active") == 1 and cmeta:get_int("sc_out_ku") > 0 then
                    if input_reaches_real_generator(cur.pos, cur.node, visited_sc) then
                        return true
                    end
                end
            end
        else
            for _, d in ipairs(dirs) do
                local npos = {x = cur.pos.x + d.x, y = cur.pos.y + d.y, z = cur.pos.z + d.z}
                local nk   = core.hash_node_position(npos)
                if not visited[nk] then
                    local nnode = core.get_node(npos)
                    if kinetica.is_kinetic_node and kinetica.is_kinetic_node(nnode.name) then
                        if are_kinetic_nodes_coupled(cur.pos, cur.node, npos, nnode, d, true) then
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

local function get_single_node_demand_ku(pos, node, rpm)
    if not node or not node.name then return 0 end
    if kinetica.is_shaft and kinetica.is_shaft(node.name) then
        return 0
    end
    if (kinetica.is_water_wheel and kinetica.is_water_wheel(node.name)) or
       (kinetica.is_turbine and kinetica.is_turbine(node.name)) then
        return 0
    end

    if string.find(node.name, "kinetica:gearbox", 1, true) == 1 or
       string.find(node.name, "kinetica:chain_drive", 1, true) == 1 then
        return 1
    end

    if kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(node.name) then
        local pmeta = core.get_meta(pos)
        local pd = pmeta:get_int("piston_demand_ku")
        if pd > 0 then return pd end
        return math.min(128, math.max(32, math.floor(rpm * 4)))
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
    if md > 0 then return md end
    return 0
end

local get_controller_total_input_demand_ku -- forward declaration

local function compute_output_downstream_demand_ku(sc_pos, sc_node, out_rpm, visited)
    if not out_rpm or out_rpm <= 0 then
        return 0
    end

    visited = visited or {}
    visited[core.hash_node_position(sc_pos)] = true

    local out_dir   = get_out_dir(sc_node.param2)
    local first_pos = {
        x = sc_pos.x + out_dir.x,
        y = sc_pos.y + out_dir.y,
        z = sc_pos.z + out_dir.z,
    }
    local first_key  = core.hash_node_position(first_pos)
    local first_node = core.get_node(first_pos)
    local rev_out    = {x = -out_dir.x, y = -out_dir.y, z = -out_dir.z}

    if visited[first_key] then
        return 0
    end
    if not (kinetica.is_kinetic_node and kinetica.is_kinetic_node(first_node.name)) then
        return 0
    end

    local first_couples = false
    if is_speed_controller(first_node.name) then
        if not CONFIG.ALLOW_CHAINED_CONTROLLERS then
            return 0
        end
        local fin = get_in_dir(first_node.param2)
        first_couples = (fin.x == rev_out.x and fin.y == rev_out.y and fin.z == rev_out.z)
    elseif not kinetica.has_axle_port or kinetica.has_axle_port(first_node, rev_out) then
        first_couples = true
    end

    if not first_couples then
        return 0
    end

    visited[first_key] = true
    local queue    = {{pos = first_pos, node = first_node}}
    local total_ku = 0
    local dirs     = kinetica.directions or ALL_6_DIRS
    local head     = 1

    while head <= #queue and #queue <= 384 do
        local cur = queue[head]
        head = head + 1

        if is_speed_controller(cur.node.name) then
            if CONFIG.ALLOW_CHAINED_CONTROLLERS then
                total_ku = total_ku + get_controller_total_input_demand_ku(cur.pos, cur.node, out_rpm, visited)
            else
                total_ku = total_ku + CONFIG.FRICTION_FINE_KU
            end
        else
            total_ku = total_ku + get_single_node_demand_ku(cur.pos, cur.node, out_rpm)

            for _, d in ipairs(dirs) do
                local npos = {x = cur.pos.x + d.x, y = cur.pos.y + d.y, z = cur.pos.z + d.z}
                local nk   = core.hash_node_position(npos)
                if not visited[nk] then
                    local nnode = core.get_node(npos)
                    if kinetica.is_kinetic_node and kinetica.is_kinetic_node(nnode.name) then
                        if are_kinetic_nodes_coupled(cur.pos, cur.node, npos, nnode, d, false) then
                            visited[nk] = true
                            queue[#queue + 1] = {pos = npos, node = nnode}
                        end
                    end
                end
            end
        end
    end
    return total_ku
end

get_controller_total_input_demand_ku = function(pos, node, in_rpm, visited)
    local fine = CONFIG.FRICTION_FINE_KU
    if not pos or not in_rpm or in_rpm < CONFIG.MIN_INPUT_RPM then
        return fine
    end

    visited = visited or {}
    local my_hash = core.hash_node_position(pos)
    if visited[my_hash] then
        return fine
    end

    node = node or core.get_node(pos)
    local meta = core.get_meta(pos)
    local step, _, _ = get_effective_step(pos, meta)

    if not step or step.rpm_mult <= 0 or step.ku_cost_mult <= 0 then
        meta:set_int("last_downstream_ku", 0)
        return fine
    end

    local out_rpm  = math.min(CONFIG.MAX_OUTPUT_RPM, in_rpm * step.rpm_mult)
    local eff_mult = out_rpm / in_rpm

    local sub_visited = table.copy(visited)
    local raw_downstream_ku = compute_output_downstream_demand_ku(pos, node, out_rpm, sub_visited)

    meta:set_int("last_downstream_ku", raw_downstream_ku)
    local scaled_load = math.ceil(raw_downstream_ku * eff_mult)
    return fine + scaled_load
end

local function C(hex, text)
    return core.colorize(hex, tostring(text))
end

local function get_speed_controller_formspec(pos)
    local meta = core.get_meta(pos)
    local U    = CONFIG.UI_COLORS

    local step, _, rs_clutched = get_effective_step(pos, meta)
    local raw_step, raw_idx    = get_step_info(meta)

    local in_rpm        = meta:get_float("true_in_rpm")
    local in_supply_ku  = meta:get_int("true_in_supply_ku")
    local in_avail_ku   = meta:get_int("true_in_avail_ku")
    local in_spin       = meta:get_int("true_in_spin")
    local rev_out       = (meta:get_int("reverse_output") == 1)
    local overstressed  = (meta:get_int("sc_overstressed") == 1) or (meta:get_int("network_overstressed") == 1)

    local is_powered_in = (in_supply_ku > 0 and in_rpm >= CONFIG.MIN_INPUT_RPM and not overstressed)
    local out_rpm       = (is_powered_in and step.rpm_mult > 0)
        and math.min(CONFIG.MAX_OUTPUT_RPM, in_rpm * step.rpm_mult)
        or  0
    local eff_mult      = (is_powered_in and in_rpm > 0 and out_rpm > 0) and (out_rpm / in_rpm) or step.ku_cost_mult

    local raw_down_ku   = meta:get_int("last_downstream_ku")
    local total_in_load = CONFIG.FRICTION_FINE_KU + ((eff_mult > 0) and math.ceil(raw_down_ku * eff_mult) or 0)
    local max_out_ku    = 0
    if is_powered_in and eff_mult > 0 then
        local pool_before_sc = in_avail_ku + math.max(0, total_in_load - CONFIG.FRICTION_FINE_KU)
        max_out_ku = (eff_mult >= 1.0)
            and math.max(0, math.floor(pool_before_sc / eff_mult))
            or  math.max(0, pool_before_sc)
    end

    local status_str
    if overstressed then
        status_str = C(U.TEXT_ERR, "OVERSTRESSED! Reduce Speed Ratio or Add More Generators")
    elseif rs_clutched then
        status_str = C(U.TEXT_WARN, "REDSTONE CLUTCH ACTIVE — Output Disengaged (Neutral)")
    elseif not is_powered_in then
        status_str = C(U.TEXT_SUBTITLE, "IDLE — Connect Rotating Shaft to Back Input Port")
    elseif step.zone == "neutral" then
        status_str = C(U.TEXT_WARN, string.format("NEUTRAL — Input: %.1f RPM | Output Disengaged (0 RPM)", in_rpm))
    else
        local capped_note = (in_rpm * step.rpm_mult > CONFIG.MAX_OUTPUT_RPM) and " [MAX CAP]" or ""
        status_str = C(U.TEXT_OK, string.format("ENGAGED — %s (Output: %.1f RPM%s)", step.title, out_rpm, capped_note))
    end

    local used_in_ku = is_powered_in and math.max(0, in_supply_ku - in_avail_ku) or 0
    local stress_pct = (in_supply_ku > 0) and math.min(100, math.floor((used_in_ku / in_supply_ku) * 100)) or 0
    if overstressed then stress_pct = 100 end

    local bar_color = U.STRESS_SAFE
    if stress_pct >= 95 or overstressed then
        bar_color = U.STRESS_DANGER
    elseif stress_pct >= 70 then
        bar_color = U.STRESS_WARN
    end
    local bar_fill_w = math.max(0.05, (stress_pct / 100) * 10.4)

    local zone_color = U.NEUTRAL_ACCENT
    if raw_step.zone == "speed" then
        zone_color = U.SPEED_ACCENT
    elseif raw_step.zone == "torque" then
        zone_color = U.TORQUE_ACCENT
    end

    local in_spin_lbl  = (in_spin == 1) and "CW" or ((in_spin == -1) and "CCW" or "Stopped")
    local out_spin_dir = rev_out and (-in_spin) or in_spin
    local out_spin_lbl = (out_rpm > 0 and out_spin_dir ~= 0)
        and ((out_spin_dir == 1) and "CW" or "CCW")
        or  "Stopped"

    local fs = {
        "size[11.2,8.4]",
        "bgcolor[" .. U.BG_WINDOW .. ";false]",
        "box[0,0;11.2,1.05;" .. U.BG_HEADER .. "]",
        "box[0,1.02;11.2,0.05;" .. zone_color .. "]",
        "label[0.3,0.12;" .. C(U.TEXT_TITLE, "VARIABLE SPEED CONTROLLER & CLUTCH (MAX " .. CONFIG.MAX_OUTPUT_RPM .. " RPM)") .. "]",
        "label[0.3,0.52;" .. status_str .. "]",
        "box[0.2,1.25;3.4,2.35;" .. U.BG_CARD .. "]",
        "box[0.2,1.25;0.08,2.35;" .. U.SPEED_ACCENT .. "]",
        "label[0.42,1.35;" .. C(U.SPEED_ACCENT, "INPUT SHAFT (BACK)") .. "]",
        "label[0.42,1.80;" .. C(U.TEXT_LABEL, "Input Speed:") .. " " .. C(U.TEXT_VALUE, string.format("%.1f RPM (%s)", in_rpm, in_spin_lbl)) .. "]",
        "label[0.42,2.22;" .. C(U.TEXT_LABEL, "Network Pool:") .. " " .. C(U.TEXT_VALUE, string.format("%d / %d KU avail", in_avail_ku, in_supply_ku)) .. "]",
        "label[0.42,2.64;" .. C(U.TEXT_LABEL, "Controller Load:") .. " " .. C(U.TEXT_VALUE, string.format("-%d KU (incl. %d fine)", is_powered_in and total_in_load or 0, CONFIG.FRICTION_FINE_KU)) .. "]",
        "box[3.8,1.25;3.6,2.35;" .. U.BG_CARD .. "]",
        "box[3.8,1.25;0.08,2.35;" .. zone_color .. "]",
        "label[4.02,1.35;" .. C(zone_color, raw_step.title) .. "]",
        "label[4.02,1.80;" .. C(U.TEXT_LABEL, "Speed Multiplier:") .. " " .. C(U.TEXT_VALUE, string.format("%.3gx RPM", raw_step.rpm_mult)) .. "]",
        "label[4.02,2.22;" .. C(U.TEXT_LABEL, "KU Cost Multiplier:") .. " " .. C(U.TEXT_VALUE, string.format("%.3gx KU Load", raw_step.ku_cost_mult)) .. "]",
        "label[4.02,2.64;" .. C(U.TEXT_LABEL, "Slider Notch:") .. " " .. C(zone_color, string.format("[%s%d] (%s)", raw_idx > 0 and "+" or "", raw_idx, raw_step.short_label)) .. "]",
        "box[7.6,1.25;3.4,2.35;" .. U.BG_CARD .. "]",
        "box[7.6,1.25;0.08,2.35;" .. U.TORQUE_ACCENT .. "]",
        "label[7.82,1.35;" .. C(U.TORQUE_ACCENT, "OUTPUT SHAFT (FRONT)") .. "]",
        "label[7.82,1.80;" .. C(U.TEXT_LABEL, "Output Speed:") .. " " .. C(U.TEXT_VALUE, string.format("%.1f RPM (%s)", out_rpm, out_spin_lbl)) .. "]",
        "label[7.82,2.22;" .. C(U.TEXT_LABEL, "Downstream Load:") .. " " .. C(U.TEXT_VALUE, string.format("%d KU used", raw_down_ku)) .. "]",
        "label[7.82,2.64;" .. C(U.TEXT_LABEL, "Output Capacity:") .. " " .. C(U.TEXT_VALUE, string.format("%d KU max", max_out_ku)) .. "]",
        "label[0.2,3.72;" .. C(U.TEXT_LABEL, string.format("Main Generator Stress Load: %d%% (%d / %d KU Used)", stress_pct, used_in_ku, in_supply_ku)) .. "]",
        "box[0.2,4.08;10.4,0.32;" .. U.STRESS_BG .. "]",
        "box[0.2,4.08;" .. string.format("%.2f", bar_fill_w) .. ",0.32;" .. bar_color .. "]",
        "label[0.2,4.58;" .. C(U.SPEED_ACCENT, "<<< LEFT: MORE RPM (COSTS MORE KU)") .. "]",
        "label[4.55,4.58;" .. C(U.NEUTRAL_ACCENT, "[ CENTER: NEUTRAL ]") .. "]",
        "label[7.45,4.58;" .. C(U.TORQUE_ACCENT, "RIGHT: MORE KU (LESS RPM) >>>") .. "]",
        "box[0.15,4.95;10.9,2.15;" .. U.BG_SLIDER_WELL .. "]",
    }

    local btn_w   = 1.16
    local start_x = 0.25
    for idx = CONFIG.SLIDER_MIN_INDEX, CONFIG.SLIDER_MAX_INDEX do
        local st = CONFIG.SLIDER_STEPS[idx]
        if st then
            local slot_num = idx - CONFIG.SLIDER_MIN_INDEX
            local bx       = start_x + slot_num * 1.19
            local btn_name = "set_idx_" .. tostring(idx)

            local bg_col  = U.NEUTRAL_BTN_BG
            local txt_col = U.NEUTRAL_ACCENT
            if st.zone == "speed" then
                bg_col  = U.SPEED_BTN_BG
                txt_col = U.SPEED_ACCENT
            elseif st.zone == "torque" then
                bg_col  = U.TORQUE_BTN_BG
                txt_col = U.TORQUE_ACCENT
            end

            local is_selected = (idx == raw_idx)
            if is_selected then
                fs[#fs + 1] = string.format("box[%.2f,5.02;%.2f,0.86;%s]", bx - 0.04, btn_w + 0.08, txt_col)
                txt_col = U.ACTIVE_BTN_HIGHLIGHT
            end

            fs[#fs + 1] = string.format("style[%s;bgcolor=%s;textcolor=%s]", btn_name, bg_col, txt_col)
            local lbl = is_selected and ("[" .. st.short_label .. "]") or st.short_label
            fs[#fs + 1] = string.format("button[%.2f,5.08;%.2f,0.75;%s;%s]", bx, btn_w, btn_name, core.formspec_escape(lbl))
        end
    end

    local sb_val = idx_to_scrollbar_val(raw_idx)
    fs[#fs + 1] = "scrollbaroptions[min=1;max=9;smallstep=1;largestep=1;thumbsize=1]"
    fs[#fs + 1] = string.format("scrollbar[0.35,6.05;10.5,0.48;horizontal;ratio_slider;%d]", sb_val)

    fs[#fs + 1] = "button[0.2,7.30;2.6,0.75;step_left;"   .. core.formspec_escape(C(U.SPEED_ACCENT,   "<< Step Left (+RPM)")) .. "]"
    fs[#fs + 1] = "button[2.9,7.30;2.4,0.75;set_neutral;" .. core.formspec_escape(C(U.NEUTRAL_ACCENT, "Reset to Neutral"))    .. "]"
    fs[#fs + 1] = "button[5.4,7.30;2.6,0.75;step_right;"  .. core.formspec_escape(C(U.TORQUE_ACCENT,  "Step Right (+KU) >>")) .. "]"

    if CONFIG.ALLOW_SPIN_REVERSE_BUTTON then
        local rev_lbl = rev_out and "Output Spin: REVERSED" or "Output Spin: NORMAL"
        fs[#fs + 1] = "button[8.15,7.30;2.85,0.75;toggle_reverse;" .. core.formspec_escape(rev_lbl) .. "]"
    end

    return table.concat(fs)
end

local function update_sc_infotext_and_ui(pos, node)
    node = node or core.get_node(pos)
    if not is_speed_controller(node.name) then return end

    local meta = core.get_meta(pos)
    local step, _, rs_clutched = get_effective_step(pos, meta)
    local in_rpm       = meta:get_float("true_in_rpm")
    local in_supply_ku = meta:get_int("true_in_supply_ku")
    local in_avail_ku  = meta:get_int("true_in_avail_ku")
    local overstressed = (meta:get_int("sc_overstressed") == 1)

    if overstressed then
        local down_ku  = meta:get_int("last_downstream_ku")
        local out_rpm  = (in_rpm > 0) and math.min(CONFIG.MAX_OUTPUT_RPM, in_rpm * step.rpm_mult) or 0
        local eff_mult = (in_rpm > 0 and out_rpm > 0) and (out_rpm / in_rpm) or step.ku_cost_mult
        local req_in   = CONFIG.FRICTION_FINE_KU + math.ceil(down_ku * eff_mult)
        meta:set_string("infotext", string.format(
            "Speed Controller [%s]: OVERSTRESSED! (Needs %d Input KU for %d Downstream KU @ %.3gx)",
            step.short_label, req_in, down_ku, eff_mult
        ))
    elseif rs_clutched then
        meta:set_string("infotext", "Speed Controller: REDSTONE CLUTCH LOCKED (Output: 0 RPM)")
    elseif in_supply_ku <= 0 or in_rpm < CONFIG.MIN_INPUT_RPM then
        meta:set_string("infotext", string.format(
            "Speed Controller [%s]: Idle (Connect Shaft to Back Input Port | Right-Click to adjust slider)",
            step.short_label
        ))
    elseif step.zone == "neutral" then
        meta:set_string("infotext", string.format(
            "Speed Controller [NEUTRAL]: Clutch Disengaged (In: %.0f RPM -> Out: 0 RPM | -%d KU fine)",
            in_rpm, CONFIG.FRICTION_FINE_KU
        ))
    else
        local out_rpm  = math.min(CONFIG.MAX_OUTPUT_RPM, in_rpm * step.rpm_mult)
        local eff_mult = out_rpm / in_rpm
        local down_ku  = meta:get_int("last_downstream_ku")
        local in_load  = CONFIG.FRICTION_FINE_KU + math.ceil(down_ku * eff_mult)
        meta:set_string("infotext", string.format(
            "Speed Controller [%s]: In %.0f RPM (-%d KU) -> Out %.1f RPM (Downstream: %d KU | Net Avail: %d/%d KU)",
            step.short_label, in_rpm, in_load, out_rpm, down_ku, in_avail_ku, in_supply_ku
        ))
    end

    meta:set_string("formspec", get_speed_controller_formspec(pos))
end

local function restore_true_input_meta(meta)
    meta:set_float("rpm",             meta:get_float("true_in_rpm"))
    meta:set_int("spin_dir",          meta:get_int("true_in_spin"))
    meta:set_int("network_supply_ku", meta:get_int("true_in_supply_ku"))
    meta:set_int("rotational_power",  meta:get_int("true_in_avail_ku"))
    meta:set_int("machine_demand_ku", meta:get_int("true_in_demand_ku"))
    meta:set_int("lit_until",         meta:get_int("true_in_lit_until"))
end

local function drive_output_network(pos, node)
    if not kinetica.update_network or sc_relay_depth > 4 then
        return
    end
    node = node or core.get_node(pos)
    if not is_speed_controller(node.name) then return end

    local out_dir = get_out_dir(node.param2)
    local out_pos = {
        x = pos.x + out_dir.x,
        y = pos.y + out_dir.y,
        z = pos.z + out_dir.z,
    }
    local out_node = core.get_node(out_pos)
    if not (kinetica.is_kinetic_node and kinetica.is_kinetic_node(out_node.name)) then
        return
    end

    local meta       = core.get_meta(pos)
    local out_active = (meta:get_int("sc_out_active") == 1)

    local prev_hash = active_relay_sc_hash
    active_relay_sc_hash = out_active and core.hash_node_position(pos) or nil
    sc_relay_depth = sc_relay_depth + 1

    kinetica.update_network(out_pos)

    sc_relay_depth = sc_relay_depth - 1
    active_relay_sc_hash = prev_hash

    restore_true_input_meta(meta)
end

local function refresh_controller_networks(pos)
    if not kinetica.update_network or sc_relay_depth > 4 then
        return
    end
    local node = core.get_node(pos)
    if not is_speed_controller(node.name) then return end

    local in_dir = get_in_dir(node.param2)
    local in_pos = {
        x = pos.x + in_dir.x,
        y = pos.y + in_dir.y,
        z = pos.z + in_dir.z,
    }

    local saved_hash = active_relay_sc_hash
    active_relay_sc_hash = nil
    kinetica.update_network(in_pos)
    kinetica.update_network(pos)
    active_relay_sc_hash = saved_hash

    drive_output_network(pos, core.get_node(pos))
    update_sc_infotext_and_ui(pos, core.get_node(pos))
end

local function set_sc_idle(pos, node, reason_text)
    if active_relay_sc_hash ~= nil and core.hash_node_position(pos) == active_relay_sc_hash then
        restore_true_input_meta(core.get_meta(pos))
        return
    end

    node = node or core.get_node(pos)
    local meta = core.get_meta(pos)

    meta:set_float("true_in_rpm",     0)
    meta:set_int("true_in_spin",      0)
    meta:set_int("true_in_supply_ku", 0)
    meta:set_int("true_in_avail_ku",  0)
    meta:set_int("true_in_demand_ku", 0)
    meta:set_int("true_in_lit_until", 0)
    restore_true_input_meta(meta)

    meta:set_int("sc_out_active", 0)
    meta:set_int("sc_out_ku",     0)
    meta:set_int("source_active", 0)
    meta:set_int("source_ku",     0)
    meta:set_float("source_rpm",  0)
    meta:set_int("source_spin",   0)
    meta:set_int("local_spin",    0)

    if node.name ~= IDLE_NAME then
        core.swap_node(pos, {name = IDLE_NAME, param2 = node.param2})
    end

    drive_output_network(pos, core.get_node(pos))
    update_sc_infotext_and_ui(pos, core.get_node(pos))
    if reason_text then
        meta:set_string("infotext", reason_text)
    end
end

local function wake_sc(pos, node, rpm, spin_dir, demand_ku, avail_ku, supply_ku)
    if active_relay_sc_hash ~= nil and core.hash_node_position(pos) == active_relay_sc_hash then
        restore_true_input_meta(core.get_meta(pos))
        return
    end

    node = node or core.get_node(pos)
    local meta = core.get_meta(pos)
    local now  = math.floor(core.get_gametime())

    if not input_reaches_real_generator(pos, node) then
        set_sc_idle(pos, node)
        return
    end

    local total_in_demand = get_controller_total_input_demand_ku(pos, node, rpm)
    local reported_demand = demand_ku or 0
    local extra_ku        = math.max(0, total_in_demand - reported_demand)
    local eff_in_avail_ku = avail_ku - extra_ku

    if eff_in_avail_ku < 0 then
        meta:set_int("sc_overstressed", 1)
        set_sc_idle(pos, node)
        return
    end

    meta:set_int("sc_overstressed",   0)
    meta:set_float("true_in_rpm",     rpm)
    meta:set_int("true_in_spin",      spin_dir)
    meta:set_int("true_in_supply_ku", supply_ku)
    meta:set_int("true_in_avail_ku",  eff_in_avail_ku)
    meta:set_int("true_in_demand_ku", total_in_demand)
    meta:set_int("true_in_lit_until", now + 2)
    restore_true_input_meta(meta)

    local step, _, _ = get_effective_step(pos, meta)
    local out_active = (step.rpm_mult > 0 and step.ku_cost_mult > 0)
    local rev_out    = (meta:get_int("reverse_output") == 1)
    local out_rpm    = 0

    if out_active then
        out_rpm        = math.min(CONFIG.MAX_OUTPUT_RPM, rpm * step.rpm_mult)
        local eff_mult = out_rpm / rpm
        local out_spin = rev_out and (-spin_dir) or spin_dir

        local raw_down_ku = meta:get_int("last_downstream_ku")
        local extra_out_avail = (eff_mult >= 1.0)
            and math.floor(eff_in_avail_ku / eff_mult)
            or  eff_in_avail_ku
        local out_supply_ku = math.max(1, raw_down_ku + extra_out_avail)

        meta:set_int("sc_out_active", 1)
        meta:set_int("sc_out_ku",     out_supply_ku)
        meta:set_int("source_active", 1)
        meta:set_int("source_ku",     out_supply_ku)
        meta:set_float("source_rpm",  out_rpm)
        meta:set_int("source_spin",   out_spin)
        meta:set_int("local_spin",    out_spin)
    else
        meta:set_int("sc_out_active", 0)
        meta:set_int("sc_out_ku",     0)
        meta:set_int("source_active", 0)
        meta:set_int("source_ku",     0)
        meta:set_float("source_rpm",  0)
        meta:set_int("source_spin",   0)
        meta:set_int("local_spin",    0)
    end

    local target_name = get_target_controller_node_name(node.param2, true, spin_dir, out_active, out_rpm, rev_out)
    if node.name ~= target_name then
        core.swap_node(pos, {name = target_name, param2 = node.param2})
    end

    drive_output_network(pos, core.get_node(pos))
    update_sc_infotext_and_ui(pos, core.get_node(pos))

    local timer = core.get_node_timer(pos)
    if not timer:is_started() then
        timer:start(CONFIG.TIMER_INTERVAL)
    end
end

local function sc_timer(pos, elapsed)
    local now  = math.floor(core.get_gametime())
    local meta = core.get_meta(pos)

    refresh_controller_networks(pos)
    local node = core.get_node(pos)

    local rpm       = meta:get_float("true_in_rpm")
    local supply_ku = meta:get_int("true_in_supply_ku")
    local lit_until = meta:get_int("true_in_lit_until")

    if supply_ku <= 0 or rpm < CONFIG.MIN_INPUT_RPM or now >= lit_until then
        set_sc_idle(pos, node)
        return true
    end

    core.get_node_timer(pos):start(CONFIG.TIMER_INTERVAL)
    return false
end

if kinetica.register_kinetic_machine then
    kinetica.register_kinetic_machine(IDLE_NAME, {
        can_ride_piston = false,
        get_demand_ku   = function(rpm, pos, node)
            if active_relay_sc_hash and pos and core.hash_node_position(pos) == active_relay_sc_hash then
                return 0
            end
            return get_controller_total_input_demand_ku(pos, node, rpm)
        end,
        has_axle_port   = function(node, d)
            if active_relay_sc_hash ~= nil then
                local out_dir = get_out_dir(node.param2)
                return (d.x == out_dir.x and d.y == out_dir.y and d.z == out_dir.z)
            else
                local in_dir = get_in_dir(node.param2)
                return (d.x == in_dir.x and d.y == in_dir.y and d.z == in_dir.z)
            end
        end,
        set_idle = set_sc_idle,
        wake     = wake_sc,
    })
end

local function notify_nearby_speed_controllers(origin_pos)
    local found = core.find_nodes_in_area(
        {x = origin_pos.x - 16, y = origin_pos.y - 16, z = origin_pos.z - 16},
        {x = origin_pos.x + 16, y = origin_pos.y + 16, z = origin_pos.z + 16},
        {"group:speed_controller"}
    )
    for _, sc_pos in ipairs(found) do
        refresh_controller_networks(sc_pos)
    end
end

core.register_on_placenode(function(pos, newnode)
    if kinetica.is_kinetic_node and kinetica.is_kinetic_node(newnode.name) then
        core.after(0, function()
            notify_nearby_speed_controllers(pos)
        end)
    end
end)

core.register_on_dignode(function(pos, oldnode)
    if kinetica.is_kinetic_node and kinetica.is_kinetic_node(oldnode.name) then
        core.after(0, function()
            notify_nearby_speed_controllers(pos)
        end)
    end
end)

local function look_to_unit_dir(placer, allow_vertical)
    local look = placer and placer:get_look_dir() or {x = 0, y = 0, z = 1}
    local ax, ay, az = math.abs(look.x), math.abs(look.y), math.abs(look.z)
    if allow_vertical and ay > ax and ay > az then
        return {x = 0, y = (look.y > 0) and 1 or -1, z = 0}
    elseif ax >= az then
        return {x = (look.x > 0) and 1 or -1, y = 0, z = 0}
    else
        return {x = 0, y = 0, z = (look.z > 0) and 1 or -1}
    end
end

local function get_strongest_power_source(pos)
    local best_dir = nil
    local best_ku = -1
    for _, d in ipairs(ALL_6_DIRS) do
        local np = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
        local nnode = core.get_node(np)
        if kinetica.is_kinetic_node(nnode.name) then
            local rev = {x = -d.x, y = -d.y, z = -d.z}
            if kinetica.has_axle_port(nnode, rev) then
                local nmeta = core.get_meta(np)
                local avail = nmeta:get_int("rotational_power")
                if avail > best_ku then
                    best_ku = avail
                    best_dir = d
                end
            end
        end
    end
    return best_dir, best_ku
end

local function place_speed_controller(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then
        return itemstack
    end

    local under_pos  = pointed_thing.under
    local above_pos  = pointed_thing.above
    local under_node = core.get_node(under_pos)
    local under_def  = core.registered_nodes[under_node.name]
    local sneaking   = placer and placer:is_player() and placer:get_player_control().sneak

    if under_def and under_def.on_rightclick and not sneaking then
        return under_def.on_rightclick(under_pos, under_node, placer, itemstack, pointed_thing) or itemstack
    end

    local diff = {
        x = above_pos.x - under_pos.x,
        y = above_pos.y - under_pos.y,
        z = above_pos.z - under_pos.z,
    }

    local place_pos = pointed_thing.above
    if under_def and under_def.buildable_to then
        place_pos = pointed_thing.under
    end

    local out_dir = nil
    if not sneaking then
        local src_dir, src_ku = get_strongest_power_source(place_pos)
        if src_dir and src_ku >= 0 then
            out_dir = {x = -src_dir.x, y = -src_dir.y, z = -src_dir.z}
            if not CONFIG.ALLOW_VERTICAL_PLACEMENT and out_dir.y ~= 0 then
                out_dir = nil
            end
        end
        if not out_dir then
            if (kinetica.has_axle_port and kinetica.has_axle_port(under_node, diff)) or
               is_speed_controller(under_node.name) then
                if CONFIG.ALLOW_VERTICAL_PLACEMENT or diff.y == 0 then
                    out_dir = diff
                end
            end
        end
    end

    if not out_dir then
        local ldir = look_to_unit_dir(placer, CONFIG.ALLOW_VERTICAL_PLACEMENT)
        local invert = CONFIG.OUTPUT_FACES_PLAYER
        if sneaking then invert = not invert end
        if invert then
            out_dir = {x = -ldir.x, y = -ldir.y, z = -ldir.z}
        else
            out_dir = ldir
        end
    end

    local in_dir = {x = -out_dir.x, y = -out_dir.y, z = -out_dir.z}
    local param2 = core.dir_to_facedir(in_dir, CONFIG.ALLOW_VERTICAL_PLACEMENT)
    local placed_stack, final_pos = core.item_place_node(itemstack, placer, pointed_thing, param2)

    if final_pos then
        local meta = core.get_meta(final_pos)
        meta:set_int("slider_idx", CONFIG.DEFAULT_SLIDER_INDEX)
        meta:set_int("reverse_output", 0)
        update_sc_infotext_and_ui(final_pos, core.get_node(final_pos))
        core.get_node_timer(final_pos):start(CONFIG.TIMER_INTERVAL)
        core.after(0, function()
            refresh_controller_networks(final_pos)
        end)
    end
    return placed_stack
end

local function on_sc_receive_fields(pos, formname, fields, sender)
    if sender and sender:is_player() and core.is_protected(pos, sender:get_player_name()) then
        return
    end

    local meta    = core.get_meta(pos)
    local cur_idx = clamp_slider_idx(meta:get_int("slider_idx"))
    local new_idx = cur_idx
    local changed = false

    for idx = CONFIG.SLIDER_MIN_INDEX, CONFIG.SLIDER_MAX_INDEX do
        if fields["set_idx_" .. tostring(idx)] then
            new_idx = idx
            changed = true
            break
        end
    end

    if fields.step_left then
        new_idx = clamp_slider_idx(cur_idx - 1)
        changed = true
    elseif fields.step_right then
        new_idx = clamp_slider_idx(cur_idx + 1)
        changed = true
    elseif fields.set_neutral then
        new_idx = 0
        changed = true
    elseif fields.toggle_reverse and CONFIG.ALLOW_SPIN_REVERSE_BUTTON then
        local cur_rev = meta:get_int("reverse_output")
        meta:set_int("reverse_output", (cur_rev == 1) and 0 or 1)
        changed = true
    elseif fields.ratio_slider then
        local ev = core.explode_scrollbar_event(fields.ratio_slider)
        if ev and ev.type == "CHG" then
            local sb_idx = scrollbar_val_to_idx(ev.value)
            if sb_idx ~= cur_idx then
                new_idx = sb_idx
                changed = true
            end
        end
    end

    if changed then
        meta:set_int("slider_idx", new_idx)
        meta:set_int("sc_overstressed", 0)
        core.sound_play("default_place_node_hard", {pos = pos, max_hear_distance = 10, gain = 0.45}, true)
        refresh_controller_networks(pos)
    end
end

local function on_sc_after_dig(pos, oldnode)
    local out_dir = get_out_dir(oldnode.param2)
    local in_dir  = get_in_dir(oldnode.param2)
    if kinetica.schedule_network_update then
        kinetica.schedule_network_update({x = pos.x + in_dir.x,  y = pos.y + in_dir.y,  z = pos.z + in_dir.z})
        kinetica.schedule_network_update({x = pos.x + out_dir.x, y = pos.y + out_dir.y, z = pos.z + out_dir.z})
    end
end

local base_groups   = {handy = 1, pickaxey = 1, axey = 1, kinetic_receiver = 1, speed_controller = 1}
local active_groups = {handy = 1, pickaxey = 1, axey = 1, kinetic_receiver = 1, speed_controller = 1, not_in_creative_inventory = 1}

local function register_controller_variant(node_name, desc, in_tile, out_tile, is_base)
    core.register_node(node_name, {
        description = desc,
        tiles = {
            CONFIG.TEX_TOP_BOTTOM,
            CONFIG.TEX_TOP_BOTTOM,
            CONFIG.TEX_SIDE_CASING,
            CONFIG.TEX_SIDE_CASING,
            in_tile,
            out_tile,
        },
        paramtype2 = "facedir",
        is_ground_content = false,
        on_place = is_base and place_speed_controller or nil,
        drop = IDLE_NAME,
        groups = is_base and base_groups or active_groups,
        _mcl_hardness = 2.5,
        _mcl_blast_resistance = 3.5,
        sounds = mcl_sounds and mcl_sounds.node_sound_metal_defaults and mcl_sounds.node_sound_metal_defaults() or nil,

        on_construct = is_base and function(pos)
            local meta = core.get_meta(pos)
            meta:set_int("slider_idx", CONFIG.DEFAULT_SLIDER_INDEX)
            update_sc_infotext_and_ui(pos, core.get_node(pos))
            core.get_node_timer(pos):start(CONFIG.TIMER_INTERVAL)
        end or nil,

        on_receive_fields = on_sc_receive_fields,
        after_dig_node    = on_sc_after_dig,
        on_timer          = sc_timer,
    })
end

register_controller_variant(
    IDLE_NAME,
    "Variable Speed Controller & Clutch (Max 1024 RPM | Back = Input, Front = Output)",
    in_face_idle,
    out_face_idle,
    true
)

register_controller_variant(
    IDLE_NAME .. "_neutral_cw",
    "Variable Speed Controller (Neutral CW)",
    in_anim_ccw,
    out_face_idle,
    false
)

register_controller_variant(
    IDLE_NAME .. "_neutral_ccw",
    "Variable Speed Controller (Neutral CCW)",
    in_anim_cw,
    out_face_idle,
    false
)

for _, tier in ipairs(CONFIG.OUTPUT_ANIM_TIERS) do
    local out_cw  = make_output_port_anim(false, tier.length)
    local out_ccw = make_output_port_anim(true,  tier.length)

    for _, in_dir_tag in ipairs({"cw", "ccw"}) do
        local in_tile = (in_dir_tag == "cw") and in_anim_ccw or in_anim_cw
        for _, out_dir_tag in ipairs({"cw", "ccw"}) do
            local out_tile = (out_dir_tag == "cw") and out_cw or out_ccw
            local vname    = IDLE_NAME .. "_" .. tier.name .. "_" .. in_dir_tag .. "_" .. out_dir_tag
            register_controller_variant(
                vname,
                string.format("Variable Speed Controller (%s %s)", string.upper(tier.name), string.upper(out_dir_tag)),
                in_tile,
                out_tile,
                false
            )
        end
    end
end

core.register_alias("kinetica:speed_controller_active_cw",  IDLE_NAME .. "_medium_cw_cw")
core.register_alias("kinetica:speed_controller_active_ccw", IDLE_NAME .. "_medium_ccw_ccw")

core.register_lbm({
    label             = "Wake kinetica Speed Controllers on chunk load",
    name              = "kinetica:wake_speed_controllers_lbm",
    nodenames         = {"group:speed_controller"},
    run_at_every_load = true,
    action = function(pos, node)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TIMER_INTERVAL)
        end
    end,
})

core.register_craft({
    output = IDLE_NAME,
    recipe = {
        {"mcl_core:iron_ingot", "mcl_core:gold_ingot",   "mcl_core:iron_ingot"},
        {"kinetica:shaft",      "kinetica:gearbox",      "kinetica:shaft"},
        {"mcl_core:iron_ingot", "mcl_redstone:redstone", "mcl_core:iron_ingot"},
    },
})