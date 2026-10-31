kinetica = kinetica or {}

local CONFIG = {
    OUTPUT_FACES_PLAYER       = false,
    ALLOW_VERTICAL_PLACEMENT  = true,
    DEFAULT_SLIDER_INDEX      = 0,
    ALLOW_SPIN_REVERSE_BUTTON = true,
    REDSTONE_FORCES_NEUTRAL   = true,
    MIN_INPUT_RPM             = 1,
    FRICTION_FINE_KU          = 1,
    ALLOW_CHAINED_CONTROLLERS = false,
    TIMER_INTERVAL            = 0.25,
    ANIM_LEN_INPUT            = 0.40,

    TIERS = {
        [1] = {
            tier_num         = 1,
            base_name        = "kinetica:speed_controller",
            short_name       = "Tier 1",
            ui_title         = "VARIABLE SPEED CONTROLLER & CLUTCH [TIER 1]",
            desc             = "Variable Speed Controller [Tier 1] (Max 1,024 RPM | Max 10,240 KU | Back = In, Front = Out)",
            max_rpm          = 1024,
            max_ku           = 10240, -- Rated for up to 10,240 KU Input & Output
            friction_fine_ku = 1,
            badge_color      = "#F5B041",
            cap_bar_color    = "#3498DB",
            casing_tint      = "",
        },
        [2] = {
            tier_num         = 2,
            base_name        = "kinetica:speed_controller_tier2",
            short_name       = "Tier 2",
            ui_title         = "ADVANCED SPEED CONTROLLER & CLUTCH [TIER 2]",
            desc             = "Advanced Speed Controller [Tier 2] (Max 3,072 RPM | Unlimited KU | Back = In, Front = Out)",
            max_rpm          = 3072,
            max_ku           = nil,   -- nil = Unlimited KU capacity
            friction_fine_ku = 1,
            badge_color      = "#00E5FF",
            cap_bar_color    = "#00E5FF",
            casing_tint      = "^[colorize:#00E5FF:26",
        },
    },

    OUTPUT_ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    length = 0.85 },
        { name = "slow",   max_rpm = 15,   length = 0.48 },
        { name = "medium", max_rpm = 63,   length = 0.24 },
        { name = "fast",   max_rpm = 255,  length = 0.11 },
        { name = "hyper",  max_rpm = 1024, length = 0.05 },
        { name = "ultra",  max_rpm = 3072, length = 0.03 },
    },

    SLIDER_MIN_INDEX = -4,
    SLIDER_MAX_INDEX = 4,
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

local TIER1_BASE = CONFIG.TIERS[1].base_name
local TIER2_BASE = CONFIG.TIERS[2].base_name

local function get_controller_tier_def(name)
    if not name then return nil end
    if name == TIER2_BASE or string.sub(name, 1, #TIER2_BASE + 1) == (TIER2_BASE .. "_") then
        return CONFIG.TIERS[2]
    end
    if name == TIER1_BASE or string.sub(name, 1, #TIER1_BASE + 1) == (TIER1_BASE .. "_") then
        return CONFIG.TIERS[1]
    end
    return nil
end
kinetica.get_speed_controller_tier_def = get_controller_tier_def

local function is_speed_controller(name)
    return get_controller_tier_def(name) ~= nil
end
kinetica.is_speed_controller = is_speed_controller

local function format_int(n)
    if kinetica.format_int then
        return kinetica.format_int(n)
    end
    local num = math.floor((tonumber(n) or 0) + 0.5)
    local sign = ""
    if num < 0 then
        sign = "-"
        num = -num
    end
    local s = tostring(num)
    while true do
        local k
        s, k = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return sign .. s
end

local function format_ku_compact(n)
    local num = math.floor((tonumber(n) or 0) + 0.5)
    local abs_n = math.abs(num)
    if abs_n >= 1000000 then
        return string.format("%.2fM", num / 1000000)
    elseif abs_n >= 100000 then
        return string.format("%.1fk", num / 1000)
    end
    return format_int(num)
end

local function format_rpm(rpm)
    if kinetica.format_rpm then
        return kinetica.format_rpm(rpm)
    end
    local r = tonumber(rpm) or 0
    if math.abs(r - math.floor(r + 0.5)) < 0.05 then
        return format_int(math.floor(r + 0.5))
    end
    return string.format("%.1f", r)
end

-- Check if input supply KU or input RPM exceeds the controller tier's rated capacity
local function is_input_over_tier_rating(tier, in_supply_ku, in_rpm)
    local ku_over  = (tier.max_ku ~= nil) and (in_supply_ku or 0) > tier.max_ku
    local rpm_over = (tier.max_rpm ~= nil) and (in_rpm or 0) > tier.max_rpm
    return (ku_over or rpm_over), ku_over, rpm_over
end

-- Escape '^' and ':' for sub-textures embedded inside a Luanti [combine:...] modifier
local function escape_for_combine(modifier)
    if not modifier or modifier == "" then return "" end
    local s = string.gsub(modifier, "%^", "\\^")
    s = string.gsub(s, ":", "\\:")
    return s
end

local function make_idle_port_tex(bg_tex, tint)
    local esc_tint = escape_for_combine(tint)
    return "[combine:16x16:0,0=" .. bg_tex .. esc_tint .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY
end

local function make_input_port_anim(reverse, anim_length, tint)
    local casing = CONFIG.TEX_INPUT_BG .. escape_for_combine(tint)
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

local function make_output_port_anim(reverse, anim_length, tint)
    local gear     = CONFIG.TEX_OUTPUT_GEAR_ACTIVE
    local shaft    = CONFIG.TEX_SHAFT_OVERLAY
    local esc_tint = escape_for_combine(tint)

    local gear_strip
    local shaft_strip

    if reverse then
        gear_strip = "[combine:16x64" ..
            ":0,0="  .. gear .. "\\^[sheet\\:1x3\\:0,0" .. esc_tint ..
            ":0,16=" .. gear .. "\\^[sheet\\:1x3\\:0,2" .. esc_tint ..
            ":0,32=" .. gear .. "\\^[sheet\\:1x3\\:0,1" .. esc_tint ..
            ":0,48=" .. gear .. "\\^[sheet\\:1x3\\:0,2" .. esc_tint

        shaft_strip = "[combine:16x64" ..
            ":0,0="  .. shaft .. "\\^[sheet\\:1x4\\:0,0" ..
            ":0,16=" .. shaft .. "\\^[sheet\\:1x4\\:0,3" ..
            ":0,32=" .. shaft .. "\\^[sheet\\:1x4\\:0,2" ..
            ":0,48=" .. shaft .. "\\^[sheet\\:1x4\\:0,1"
    else
        gear_strip = "[combine:16x64" ..
            ":0,0="  .. gear .. "\\^[sheet\\:1x3\\:0,0" .. esc_tint ..
            ":0,16=" .. gear .. "\\^[sheet\\:1x3\\:0,1" .. esc_tint ..
            ":0,32=" .. gear .. "\\^[sheet\\:1x3\\:0,2" .. esc_tint ..
            ":0,48=" .. gear .. "\\^[sheet\\:1x3\\:0,1" .. esc_tint

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

local function get_target_controller_node_name(base_name, param2, in_active, in_spin, out_active, out_rpm, rev_out)
    if not in_active or in_spin == 0 then
        return base_name
    end

    local in_vis = get_visual_spin_sign(param2, in_spin)
    local in_tag = (in_vis == 1) and "cw" or "ccw"

    if not out_active or not out_rpm or out_rpm <= 0 then
        return base_name .. "_neutral_" .. in_tag
    end

    local tier_name = get_output_tier_name(out_rpm)
    local out_tag   = rev_out and ((in_vis == 1) and "ccw" or "cw") or in_tag
    return base_name .. "_" .. tier_name .. "_" .. in_tag .. "_" .. out_tag
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
function kinetica.is_source_node(name, pos)
    if orig_is_source_node and orig_is_source_node(name, pos) then
        return true
    end
    if active_relay_sc_hash ~= nil and is_speed_controller(name) then
        if pos then
            return core.hash_node_position(pos) == active_relay_sc_hash
        end
        return true
    end
    return false
end

local function is_real_generator_node(pos, node)
    if is_speed_controller(node.name) then
        return false
    end
    if (kinetica.is_water_wheel and kinetica.is_water_wheel(node.name)) or
       (kinetica.is_turbine and kinetica.is_turbine(node.name)) or
       (orig_is_source_node and orig_is_source_node(node.name, pos)) then
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
    elseif kinetica.has_axle_port and not kinetica.has_axle_port(cur_node, d, cur_pos) then
        if not (kinetica.is_chain_drive and kinetica.is_chain_drive(cur_node.name) and kinetica.is_chain_drive(nnode.name)) then
            return false
        end
    end

    if is_speed_controller(nnode.name) then
        local want_port = for_input_trace and get_out_dir(nnode.param2) or get_in_dir(nnode.param2)
        return (rev.x == want_port.x and rev.y == want_port.y and rev.z == want_port.z)
    end

    if kinetica.has_axle_port and kinetica.has_axle_port(nnode, rev, npos) then
        return true
    elseif kinetica.is_chain_drive and
           kinetica.is_chain_drive(cur_node.name) and
           kinetica.is_chain_drive(nnode.name) then
        local axA = kinetica.abs_axis(cur_node.param2)
        local axB = kinetica.abs_axis(nnode.param2)
        local on_axis = (math.abs(d.x) == axA.x and math.abs(d.y) == axA.y and math.abs(d.z) == axA.z)
        if axA.x == axB.x and axA.y == axB.y and axA.z == axB.z and not on_axis then
            return true
        end
    end

    return false
end

local function input_reaches_real_generator(sc_pos, sc_node, visited_sc)
    visited_sc = visited_sc or {}
    local my_hash = core.hash_node_position(sc_pos)
    if visited_sc[my_hash] then
        return false, {}
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
        return false, {}
    end

    local rev_in = {x = -in_dir.x, y = -in_dir.y, z = -in_dir.z}
    if is_speed_controller(in_node.name) then
        if not CONFIG.ALLOW_CHAINED_CONTROLLERS then
            return false, {}
        end
        local prev_out = get_out_dir(in_node.param2)
        if prev_out.x ~= rev_in.x or prev_out.y ~= rev_in.y or prev_out.z ~= rev_in.z then
            return false, {}
        end
        local pmeta = core.get_meta(in_pos)
        if pmeta:get_int("sc_out_active") == 1 and pmeta:get_int("sc_out_ku") > 0 then
            local ok, upstream = input_reaches_real_generator(in_pos, in_node, visited_sc)
            upstream[core.hash_node_position(in_pos)] = true
            return ok, upstream
        end
        return false, {}
    elseif kinetica.has_axle_port and not kinetica.has_axle_port(in_node, rev_in, in_pos) then
        return false, {}
    end

    local in_hash = core.hash_node_position(in_pos)
    local visited = {
        [my_hash] = true,
        [in_hash] = true,
    }
    local queue = {{
        pos       = in_pos,
        node      = in_node,
        shaft_run = (kinetica.is_shaft and kinetica.is_shaft(in_node.name)) and 1 or 0,
    }}
    local dirs       = kinetica.directions or ALL_6_DIRS
    local max_nodes  = kinetica.MAX_NETWORK_NODES or 512
    local max_s_run  = kinetica.MAX_SHAFT_RUN or 32
    local found_gen  = false
    local head       = 1

    while head <= #queue and #queue <= max_nodes do
        local cur = queue[head]
        head = head + 1

        if is_real_generator_node(cur.pos, cur.node) then
            found_gen = true
        end

        if is_speed_controller(cur.node.name) then
            if CONFIG.ALLOW_CHAINED_CONTROLLERS then
                local cmeta = core.get_meta(cur.pos)
                if cmeta:get_int("sc_out_active") == 1 and cmeta:get_int("sc_out_ku") > 0 then
                    local ok, sub_up = input_reaches_real_generator(cur.pos, cur.node, visited_sc)
                    if ok then
                        found_gen = true
                        for k, v in pairs(sub_up) do visited[k] = v end
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
                        local next_run = (kinetica.is_shaft and kinetica.is_shaft(nnode.name)) and (cur.shaft_run + 1) or 0
                        if next_run <= max_s_run and are_kinetic_nodes_coupled(cur.pos, cur.node, npos, nnode, d, true) then
                            visited[nk] = true
                            queue[#queue + 1] = {pos = npos, node = nnode, shaft_run = next_run}
                        end
                    end
                end
            end
        end
    end

    visited[my_hash] = nil
    return found_gen, visited
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

    if kinetica.is_gearbox and kinetica.is_gearbox(node.name) then
        return kinetica.GEARBOX_FINE_KU or 1
    end
    if kinetica.is_chain_drive and kinetica.is_chain_drive(node.name) then
        return kinetica.CHAIN_DRIVE_FINE_KU or 1
    end

    if kinetica.is_water_pump and kinetica.is_water_pump(node.name) then
        if kinetica.get_pump_demand_ku then
            return kinetica.get_pump_demand_ku(rpm)
        end
        return math.min(64, math.max(16, math.floor(rpm * 4)))
    end

    if kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(node.name) then
        if kinetica.get_piston_demand_ku then
            return kinetica.get_piston_demand_ku(rpm)
        end
        return math.min(64, math.max(16, math.floor(rpm * 4)))
    end

    if kinetica.get_machine_demand_ku then
        local d = kinetica.get_machine_demand_ku(rpm, pos, node)
        if type(d) == "number" then return math.max(0, d) end
    end
    if kinetica.get_demand_ku then
        local d = kinetica.get_demand_ku(rpm, pos, node)
        if type(d) == "number" then return math.max(0, d) end
    end

    local mdef = kinetica.get_machine_def and kinetica.get_machine_def(node.name)
    if mdef and mdef.get_demand_ku then
        return math.max(0, mdef.get_demand_ku(rpm, pos, node) or 0)
    end

    if type(kinetica.machines) == "table" then
        for prefix, def in pairs(kinetica.machines) do
            if node.name == prefix or string.sub(node.name, 1, #prefix + 1) == (prefix .. "_") then
                if def and def.get_demand_ku then
                    return math.max(0, def.get_demand_ku(rpm, pos, node) or 0)
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

local function compute_output_downstream_demand_ku(sc_pos, sc_node, out_rpm, visited, upstream_nodes)
    if not out_rpm or out_rpm <= 0 then
        return 0, false
    end

    visited = visited or {}
    local sc_hash = core.hash_node_position(sc_pos)
    visited[sc_hash] = true

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
        return 0, false
    end
    if not (kinetica.is_kinetic_node and kinetica.is_kinetic_node(first_node.name)) then
        return 0, false
    end

    local first_couples = false
    if is_speed_controller(first_node.name) then
        if not CONFIG.ALLOW_CHAINED_CONTROLLERS then
            return 0, false
        end
        local fin = get_in_dir(first_node.param2)
        first_couples = (fin.x == rev_out.x and fin.y == rev_out.y and fin.z == rev_out.z)
    elseif not kinetica.has_axle_port or kinetica.has_axle_port(first_node, rev_out, first_pos) then
        first_couples = true
    end

    if not first_couples then
        return 0, false
    end

    if upstream_nodes and upstream_nodes[first_key] then
        return 0, true
    end

    visited[first_key] = true
    local queue = {{
        pos       = first_pos,
        node      = first_node,
        shaft_run = (kinetica.is_shaft and kinetica.is_shaft(first_node.name)) and 1 or 0,
    }}
    local total_ku   = 0
    local loop_found = false
    local dirs       = kinetica.directions or ALL_6_DIRS
    local max_nodes  = kinetica.MAX_NETWORK_NODES or 512
    local max_s_run  = kinetica.MAX_SHAFT_RUN or 32
    local head       = 1

    while head <= #queue and #queue <= max_nodes do
        local cur = queue[head]
        head = head + 1

        if is_speed_controller(cur.node.name) then
            if CONFIG.ALLOW_CHAINED_CONTROLLERS then
                total_ku = total_ku + get_controller_total_input_demand_ku(cur.pos, cur.node, out_rpm, nil, visited)
            else
                local sub_tier = get_controller_tier_def(cur.node.name) or CONFIG.TIERS[1]
                total_ku = total_ku + (sub_tier.friction_fine_ku or CONFIG.FRICTION_FINE_KU)
            end
        else
            total_ku = total_ku + get_single_node_demand_ku(cur.pos, cur.node, out_rpm)

            for _, d in ipairs(dirs) do
                local npos = {x = cur.pos.x + d.x, y = cur.pos.y + d.y, z = cur.pos.z + d.z}
                local nk   = core.hash_node_position(npos)
                if nk == sc_hash then
                    local in_dir = get_in_dir(sc_node.param2)
                    if -d.x == in_dir.x and -d.y == in_dir.y and -d.z == in_dir.z then
                        loop_found = true
                    end
                elseif not visited[nk] then
                    local nnode = core.get_node(npos)
                    if kinetica.is_kinetic_node and kinetica.is_kinetic_node(nnode.name) then
                        local next_run = (kinetica.is_shaft and kinetica.is_shaft(nnode.name)) and (cur.shaft_run + 1) or 0
                        if next_run <= max_s_run and are_kinetic_nodes_coupled(cur.pos, cur.node, npos, nnode, d, false) then
                            if upstream_nodes and upstream_nodes[nk] then
                                loop_found = true
                            end
                            visited[nk] = true
                            queue[#queue + 1] = {pos = npos, node = nnode, shaft_run = next_run}
                        end
                    end
                end
            end
        end
    end
    return total_ku, loop_found
end

get_controller_total_input_demand_ku = function(pos, node, in_rpm, in_supply_ku, visited)
    node = node or (pos and core.get_node(pos))
    local tier = (node and get_controller_tier_def(node.name)) or CONFIG.TIERS[1]
    local fine = tier.friction_fine_ku or CONFIG.FRICTION_FINE_KU

    if not pos or not in_rpm or in_rpm < CONFIG.MIN_INPUT_RPM then
        return fine
    end

    visited = visited or {}
    local my_hash = core.hash_node_position(pos)
    if visited[my_hash] then
        return fine
    end

    local meta = core.get_meta(pos)
    local check_supply = in_supply_ku or meta:get_int("true_in_supply_ku")
    local over_rating, _, _ = is_input_over_tier_rating(tier, check_supply, in_rpm)
    if over_rating then
        -- When input exceeds the controller's rated KU or RPM, it forces Neutral and only draws the friction fine
        return fine
    end

    local step, _, _ = get_effective_step(pos, meta)
    if not step or step.rpm_mult <= 0 or step.ku_cost_mult <= 0 then
        meta:set_int("last_downstream_ku", 0)
        return fine
    end

    local out_rpm  = math.min(tier.max_rpm, in_rpm * step.rpm_mult)
    local eff_mult = out_rpm / in_rpm

    local sub_visited = table.copy(visited)
    local raw_downstream_ku, _ = compute_output_downstream_demand_ku(pos, node, out_rpm, sub_visited, nil)

    meta:set_int("last_downstream_ku", raw_downstream_ku)

    -- If downstream demand exceeds Tier 1's output KU cap, controller disengages to Neutral
    if tier.max_ku and raw_downstream_ku > tier.max_ku then
        return fine
    end

    local scaled_load = math.ceil(raw_downstream_ku * eff_mult)
    return fine + scaled_load
end

local function C(hex, text)
    return core.colorize(hex, tostring(text))
end

local function FLabel(x, y, text)
    return string.format("label[%.2f,%.2f;%s]", x, y, core.formspec_escape(text))
end

local function get_speed_controller_formspec(pos, node)
    node = node or core.get_node(pos)
    local tier = get_controller_tier_def(node.name) or CONFIG.TIERS[1]
    local fine = tier.friction_fine_ku or CONFIG.FRICTION_FINE_KU
    local meta = core.get_meta(pos)
    local U    = CONFIG.UI_COLORS

    local step, _, rs_clutched = get_effective_step(pos, meta)
    local raw_step, raw_idx    = get_step_info(meta)

    local in_rpm         = meta:get_float("true_in_rpm")
    local in_supply_ku   = meta:get_int("true_in_supply_ku")
    local in_avail_ku    = meta:get_int("true_in_avail_ku")
    local in_spin        = meta:get_int("true_in_spin")
    local rev_out        = (meta:get_int("reverse_output") == 1)
    local overstressed   = (meta:get_int("sc_overstressed") == 1) or (meta:get_int("network_overstressed") == 1)
    local input_exceeded = (meta:get_int("sc_input_exceeded") == 1)
    local cap_exceeded   = (meta:get_int("sc_cap_exceeded") == 1)
    local loop_fault     = (meta:get_int("sc_loop_fault") == 1)

    local _, ku_over, rpm_over = is_input_over_tier_rating(tier, in_supply_ku, in_rpm)
    local has_input     = (in_supply_ku > 0 and in_rpm >= CONFIG.MIN_INPUT_RPM)
    local is_powered_in = (has_input and not overstressed and not input_exceeded and not cap_exceeded and not loop_fault)

    local uncapped_rpm  = (has_input and step.rpm_mult > 0) and (in_rpm * step.rpm_mult) or 0
    local rpm_capped    = (uncapped_rpm > tier.max_rpm)
    local out_rpm       = (is_powered_in and step.rpm_mult > 0)
        and math.min(tier.max_rpm, uncapped_rpm)
        or  0
    local calc_out_rpm  = (has_input and step.rpm_mult > 0)
        and math.min(tier.max_rpm, uncapped_rpm)
        or  0
    local eff_mult      = (has_input and in_rpm > 0 and calc_out_rpm > 0)
        and (calc_out_rpm / in_rpm)
        or  step.ku_cost_mult

    local raw_down_ku   = meta:get_int("last_downstream_ku")
    local active_load   = (is_powered_in and eff_mult > 0) and math.ceil(raw_down_ku * eff_mult) or 0
    local total_in_load = fine + active_load

    local raw_out_cap   = 0
    local max_out_ku    = 0
    local ku_capped     = false
    if is_powered_in and eff_mult > 0 then
        local pool_before_sc = in_avail_ku + math.max(0, total_in_load - fine)
        raw_out_cap = math.max(0, math.floor(pool_before_sc / eff_mult))
        if tier.max_ku then
            ku_capped  = (raw_out_cap > tier.max_ku)
            max_out_ku = math.min(tier.max_ku, raw_out_cap)
        else
            max_out_ku = raw_out_cap
        end
    end

    local status_str
    if loop_fault then
        status_str = C(U.TEXT_ERR, "LOOP FAULT! Output Shaft is Connected Back to Input Network — Forced Neutral")
    elseif input_exceeded then
        if ku_over and rpm_over then
            status_str = C(U.TEXT_ERR, string.format(
                "INPUT LIMIT EXCEEDED! (In: %s KU @ %s RPM > Max %s KU / %s RPM) — Engaged Neutral",
                format_int(in_supply_ku), format_rpm(in_rpm), format_int(tier.max_ku), format_int(tier.max_rpm)
            ))
        elseif ku_over then
            status_str = C(U.TEXT_ERR, string.format(
                "INPUT KU LIMIT EXCEEDED! (Input: %s KU > %s Max %s KU) — Engaged Neutral",
                format_int(in_supply_ku), tier.short_name, format_int(tier.max_ku)
            ))
        else
            status_str = C(U.TEXT_ERR, string.format(
                "INPUT RPM LIMIT EXCEEDED! (Input: %s RPM > %s Max %s RPM) — Engaged Neutral",
                format_rpm(in_rpm), tier.short_name, format_int(tier.max_rpm)
            ))
        end
    elseif cap_exceeded then
        status_str = C(U.TEXT_ERR, string.format(
            "OUTPUT CAPACITY EXCEEDED! (Downstream: %s KU > %s Max %s KU) — Engaged Neutral",
            format_int(raw_down_ku), tier.short_name, format_int(tier.max_ku or 0)
        ))
    elseif overstressed then
        local req_load = fine + ((eff_mult > 0) and math.ceil(raw_down_ku * eff_mult) or 0)
        status_str = C(U.TEXT_ERR, string.format(
            "OVERSTRESSED! Needs %s Input KU (Supply: %s KU @ %s RPM)",
            format_int(req_load), format_int(in_supply_ku), format_rpm(in_rpm)
        ))
    elseif rs_clutched then
        status_str = C(U.TEXT_WARN, "REDSTONE CLUTCH ACTIVE — Output Disengaged (Neutral)")
    elseif not has_input then
        status_str = C(U.TEXT_SUBTITLE, "IDLE — Connect Rotating Shaft to Back Input Port")
    elseif step.zone == "neutral" then
        status_str = C(U.TEXT_WARN, string.format(
            "NEUTRAL — Input: %s RPM | Output Disengaged (0 RPM)",
            format_rpm(in_rpm)
        ))
    else
        local flags = {}
        if rpm_capped then flags[#flags + 1] = "MAX RPM CAP" end
        if ku_capped  then flags[#flags + 1] = "MAX 10,240 KU CAP" end
        local flag_str = (#flags > 0) and (" [" .. table.concat(flags, " & ") .. "]") or ""
        status_str = C(U.TEXT_OK, string.format(
            "ENGAGED — %s (Output: %s RPM | %s KU Cap%s)",
            step.title, format_rpm(out_rpm), format_int(max_out_ku), flag_str
        ))
    end

    local used_in_ku = has_input and math.max(0, in_supply_ku - in_avail_ku) or 0
    if overstressed then
        local req_load = fine + ((eff_mult > 0) and math.ceil(raw_down_ku * eff_mult) or 0)
        used_in_ku = math.max(used_in_ku, req_load)
    end
    local stress_pct = (in_supply_ku > 0) and math.min(100, math.floor((used_in_ku / in_supply_ku) * 100)) or 0
    if overstressed then stress_pct = 100 end

    local bar_color = U.STRESS_SAFE
    if stress_pct >= 95 or overstressed then
        bar_color = U.STRESS_DANGER
    elseif stress_pct >= 70 then
        bar_color = U.STRESS_WARN
    end
    local bar_fill_w = math.max(0.05, (stress_pct / 100) * 5.65)

    -- Right Progress Bar:
    --   Tier 1: Tracks KU against the 10,240 KU Rated Limit
    --   Tier 2: Tracks Speed against the 3,072 RPM Ceiling (since Tier 2 KU is Unlimited)
    local right_bar_label
    local cap_pct = 0
    if tier.max_ku then
        local peak_ku = has_input and math.max(in_supply_ku, raw_down_ku) or 0
        cap_pct = math.min(100, math.floor((peak_ku / tier.max_ku) * 100))
        if input_exceeded or cap_exceeded then cap_pct = 100 end
        right_bar_label = string.format(
            "%s Rated KU Limit: %d%% (%s / %s KU Max)",
            tier.short_name, cap_pct, format_ku_compact(peak_ku), format_ku_compact(tier.max_ku)
        )
    else
        local disp_rpm = math.max(in_rpm, out_rpm)
        cap_pct = math.min(100, math.floor((disp_rpm / tier.max_rpm) * 100))
        if input_exceeded then cap_pct = 100 end
        right_bar_label = string.format(
            "%s Speed Ceiling: %d%% (%s / %s RPM Max)",
            tier.short_name, cap_pct, format_rpm(disp_rpm), format_int(tier.max_rpm)
        )
    end

    local cap_color = tier.cap_bar_color
    if cap_pct >= 95 or input_exceeded or cap_exceeded then
        cap_color = U.STRESS_DANGER
    elseif cap_pct >= 75 then
        cap_color = U.STRESS_WARN
    end
    local cap_fill_w = math.max(0.05, (cap_pct / 100) * 5.65)

    local zone_color = U.NEUTRAL_ACCENT
    if input_exceeded or cap_exceeded or loop_fault then
        zone_color = U.TEXT_ERR
    elseif raw_step.zone == "speed" then
        zone_color = U.SPEED_ACCENT
    elseif raw_step.zone == "torque" then
        zone_color = U.TORQUE_ACCENT
    end

    local in_spin_lbl  = (in_spin == 1) and "CW" or ((in_spin == -1) and "CCW" or "Stopped")
    local out_spin_dir = rev_out and (-in_spin) or in_spin
    local out_spin_lbl = (out_rpm > 0 and out_spin_dir ~= 0)
        and ((out_spin_dir == 1) and "CW" or "CCW")
        or  "Stopped"

    local spd_mult_str
    local ku_mult_str
    if input_exceeded or cap_exceeded or loop_fault then
        spd_mult_str = "0x (FORCED NEUTRAL)"
        ku_mult_str  = "0x (CLUTCH OPEN)"
    elseif has_input and raw_step.rpm_mult > 0 and rpm_capped then
        spd_mult_str = string.format("%.3gx Eff (%gx Set)", eff_mult, raw_step.rpm_mult)
        ku_mult_str  = string.format("%.3gx Eff (RPM Capped)", eff_mult)
    else
        spd_mult_str = string.format("%.3gx RPM", raw_step.rpm_mult)
        ku_mult_str  = string.format("%.3gx KU Load", raw_step.ku_cost_mult)
    end

    local header_ku_str = tier.max_ku and ("MAX " .. format_int(tier.max_ku) .. " KU") or "UNLIMITED KU"
    local out_cap_str   = tier.max_ku
        and string.format("%s / %s KU", format_ku_compact(max_out_ku), format_ku_compact(tier.max_ku))
        or  string.format("%s KU (Unlimited)", format_ku_compact(max_out_ku))

    local fs = {
        "size[12.0,9.0]",
        "bgcolor[" .. U.BG_WINDOW .. ";false]",
        "box[0,0;12.0,1.08;" .. U.BG_HEADER .. "]",
        "box[0,1.04;12.0,0.05;" .. zone_color .. "]",
        FLabel(0.3, 0.12, C(tier.badge_color, string.format(
            "%s  (MAX %s RPM  |  %s)",
            tier.ui_title, format_int(tier.max_rpm), header_ku_str
        ))),
        FLabel(0.3, 0.54, status_str),

        -- Card 1: Input Shaft
        "box[0.2,1.25;3.7,2.40;" .. U.BG_CARD .. "]",
        "box[0.2,1.25;0.08,2.40;" .. U.SPEED_ACCENT .. "]",
        FLabel(0.42, 1.35, C(U.SPEED_ACCENT, "INPUT SHAFT (BACK)")),
        FLabel(0.42, 1.80, C(U.TEXT_LABEL, "Input Speed:") .. " " .. C(rpm_over and U.TEXT_ERR or U.TEXT_VALUE, string.format("%s RPM (%s)", format_rpm(in_rpm), in_spin_lbl))),
        FLabel(0.42, 2.22, C(U.TEXT_LABEL, "Network Pool:") .. " " .. C(ku_over and U.TEXT_ERR or U.TEXT_VALUE, string.format("%s / %s KU", format_ku_compact(in_avail_ku), format_ku_compact(in_supply_ku)))),
        FLabel(0.42, 2.64, C(U.TEXT_LABEL, "Controller Load:") .. " " .. C(U.TEXT_VALUE, string.format("-%s KU (%d fine)", format_ku_compact(has_input and total_in_load or 0), fine))),

        -- Card 2: Ratio & Gearing
        "box[4.05,1.25;3.9,2.40;" .. U.BG_CARD .. "]",
        "box[4.05,1.25;0.08,2.40;" .. zone_color .. "]",
        FLabel(4.27, 1.35, C(zone_color, (input_exceeded or cap_exceeded) and "AUTO-NEUTRAL (OVER LIMIT)" or raw_step.title)),
        FLabel(4.27, 1.80, C(U.TEXT_LABEL, "Speed Ratio:") .. " " .. C(U.TEXT_VALUE, spd_mult_str)),
        FLabel(4.27, 2.22, C(U.TEXT_LABEL, "KU Cost Ratio:") .. " " .. C(U.TEXT_VALUE, ku_mult_str)),
        FLabel(4.27, 2.64, C(U.TEXT_LABEL, "Notch / Tier:") .. " " .. C(zone_color, string.format("[%s%d] %s", raw_idx > 0 and "+" or "", raw_idx, raw_step.short_label)) .. " " .. C(tier.badge_color, "(" .. tier.short_name .. ")")),

        -- Card 3: Output Shaft
        "box[8.1,1.25;3.7,2.40;" .. U.BG_CARD .. "]",
        "box[8.1,1.25;0.08,2.40;" .. U.TORQUE_ACCENT .. "]",
        FLabel(8.32, 1.35, C(U.TORQUE_ACCENT, "OUTPUT SHAFT (FRONT)")),
        FLabel(8.32, 1.80, C(U.TEXT_LABEL, "Output Speed:") .. " " .. C(U.TEXT_VALUE, string.format("%s / %s RPM (%s)", format_rpm(out_rpm), format_int(tier.max_rpm), out_spin_lbl))),
        FLabel(8.32, 2.22, C(U.TEXT_LABEL, "Downstream Load:") .. " " .. C(cap_exceeded and U.TEXT_ERR or U.TEXT_VALUE, string.format("%s KU used", format_ku_compact(raw_down_ku)))),
        FLabel(8.32, 2.64, C(U.TEXT_LABEL, "Output Capacity:") .. " " .. C(U.TEXT_VALUE, out_cap_str)),

        -- Dual Progress Bars: Generator Stress (Left) & Tier Rating (Right)
        FLabel(0.2, 3.82, C(U.TEXT_LABEL, string.format("Generator Stress: %d%% (%s / %s KU)", stress_pct, format_ku_compact(used_in_ku), format_ku_compact(in_supply_ku)))),
        "box[0.2,4.18;5.65,0.32;" .. U.STRESS_BG .. "]",
        "box[0.2,4.18;" .. string.format("%.2f", bar_fill_w) .. ",0.32;" .. bar_color .. "]",

        FLabel(6.15, 3.82, C(U.TEXT_LABEL, right_bar_label)),
        "box[6.15,4.18;5.65,0.32;" .. U.STRESS_BG .. "]",
        "box[6.15,4.18;" .. string.format("%.2f", cap_fill_w) .. ",0.32;" .. cap_color .. "]",

        FLabel(0.2, 4.72, C(U.SPEED_ACCENT, "<<< LEFT: MORE RPM (COSTS MORE KU)")),
        FLabel(4.85, 4.72, C(U.NEUTRAL_ACCENT, "[ CENTER: NEUTRAL ]")),
        FLabel(8.05, 4.72, C(U.TORQUE_ACCENT, "RIGHT: MORE KU (LESS RPM) >>>")),
        "box[0.15,5.10;11.7,2.20;" .. U.BG_SLIDER_WELL .. "]",
    }

    local btn_w   = 1.24
    local start_x = 0.25
    for idx = CONFIG.SLIDER_MIN_INDEX, CONFIG.SLIDER_MAX_INDEX do
        local st = CONFIG.SLIDER_STEPS[idx]
        if st then
            local slot_num = idx - CONFIG.SLIDER_MIN_INDEX
            local bx       = start_x + slot_num * 1.28
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
                fs[#fs + 1] = string.format("box[%.2f,5.17;%.2f,0.88;%s]", bx - 0.04, btn_w + 0.08, txt_col)
                txt_col = U.ACTIVE_BTN_HIGHLIGHT
            end

            fs[#fs + 1] = string.format("style[%s;bgcolor=%s;textcolor=%s]", btn_name, bg_col, txt_col)
            local lbl = is_selected and ("[" .. st.short_label .. "]") or st.short_label
            fs[#fs + 1] = string.format("button[%.2f,5.23;%.2f,0.76;%s;%s]", bx, btn_w, btn_name, core.formspec_escape(lbl))
        end
    end

    local sb_val = idx_to_scrollbar_val(raw_idx)
    fs[#fs + 1] = "scrollbaroptions[min=1;max=9;smallstep=1;largestep=1;thumbsize=1]"
    fs[#fs + 1] = string.format("scrollbar[0.35,6.22;11.3,0.48;horizontal;ratio_slider;%d]", sb_val)

    fs[#fs + 1] = "button[0.2,7.50;2.8,0.78;step_left;"   .. core.formspec_escape(C(U.SPEED_ACCENT,   "<< Step Left (+RPM)")) .. "]"
    fs[#fs + 1] = "button[3.15,7.50;2.6,0.78;set_neutral;" .. core.formspec_escape(C(U.NEUTRAL_ACCENT, "Reset to Neutral"))    .. "]"
    fs[#fs + 1] = "button[5.9,7.50;2.8,0.78;step_right;"  .. core.formspec_escape(C(U.TORQUE_ACCENT,  "Step Right (+KU) >>")) .. "]"

    if CONFIG.ALLOW_SPIN_REVERSE_BUTTON then
        local rev_lbl = rev_out and "Output Spin: REVERSED" or "Output Spin: NORMAL"
        fs[#fs + 1] = "button[8.85,7.50;2.95,0.78;toggle_reverse;" .. core.formspec_escape(rev_lbl) .. "]"
    end

    return table.concat(fs)
end

local function update_sc_infotext_and_ui(pos, node)
    node = node or core.get_node(pos)
    local tier = get_controller_tier_def(node.name)
    if not tier then return end

    local fine = tier.friction_fine_ku or CONFIG.FRICTION_FINE_KU
    local meta = core.get_meta(pos)
    local step, _, rs_clutched = get_effective_step(pos, meta)
    local in_rpm         = meta:get_float("true_in_rpm")
    local in_supply_ku   = meta:get_int("true_in_supply_ku")
    local in_avail_ku    = meta:get_int("true_in_avail_ku")
    local overstressed   = (meta:get_int("sc_overstressed") == 1) or (meta:get_int("network_overstressed") == 1)
    local input_exceeded = (meta:get_int("sc_input_exceeded") == 1)
    local cap_exceeded   = (meta:get_int("sc_cap_exceeded") == 1)
    local loop_fault     = (meta:get_int("sc_loop_fault") == 1)

    local _, ku_over, rpm_over = is_input_over_tier_rating(tier, in_supply_ku, in_rpm)

    if loop_fault then
        meta:set_string("infotext", string.format(
            "Speed Controller %s [%s]: LOOP FAULT! (Output connected back to Input network — Forced Neutral)",
            tier.short_name, step.short_label
        ))
    elseif input_exceeded then
        if ku_over and rpm_over then
            meta:set_string("infotext", string.format(
                "Speed Controller %s: INPUT LIMIT EXCEEDED! (In: %s KU @ %s RPM > Max %s KU / %s RPM — Forced Neutral)",
                tier.short_name, format_int(in_supply_ku), format_rpm(in_rpm), format_int(tier.max_ku), format_int(tier.max_rpm)
            ))
        elseif ku_over then
            meta:set_string("infotext", string.format(
                "Speed Controller %s: INPUT LIMIT EXCEEDED! (Input Supply %s KU > Max %s KU Rating — Forced Neutral)",
                tier.short_name, format_int(in_supply_ku), format_int(tier.max_ku)
            ))
        else
            meta:set_string("infotext", string.format(
                "Speed Controller %s: INPUT LIMIT EXCEEDED! (Input Speed %s RPM > Max %s RPM Rating — Forced Neutral)",
                tier.short_name, format_rpm(in_rpm), format_int(tier.max_rpm)
            ))
        end
    elseif cap_exceeded then
        local down_ku = meta:get_int("last_downstream_ku")
        meta:set_string("infotext", string.format(
            "Speed Controller %s [%s]: OUTPUT CAPACITY EXCEEDED! (Downstream %s KU > Max %s KU — Forced Neutral)",
            tier.short_name, step.short_label, format_int(down_ku), format_int(tier.max_ku or 0)
        ))
    elseif overstressed then
        local down_ku  = meta:get_int("last_downstream_ku")
        local out_rpm  = (in_rpm > 0) and math.min(tier.max_rpm, in_rpm * step.rpm_mult) or 0
        local eff_mult = (in_rpm > 0 and out_rpm > 0) and (out_rpm / in_rpm) or step.ku_cost_mult
        local req_in   = fine + math.ceil(down_ku * eff_mult)
        meta:set_string("infotext", string.format(
            "Speed Controller %s [%s]: OVERSTRESSED! (Needs %s Input KU for %s Downstream KU @ %.3gx | Supply: %s KU)",
            tier.short_name, step.short_label, format_int(req_in), format_int(down_ku), eff_mult, format_int(in_supply_ku)
        ))
    elseif rs_clutched then
        meta:set_string("infotext", string.format(
            "Speed Controller %s: REDSTONE CLUTCH LOCKED (Output: 0 RPM)",
            tier.short_name
        ))
    elseif in_supply_ku <= 0 or in_rpm < CONFIG.MIN_INPUT_RPM then
        local cap_lbl = tier.max_ku and (format_int(tier.max_ku) .. " KU") or "Unlimited KU"
        meta:set_string("infotext", string.format(
            "Speed Controller %s [%s]: Idle (Max %s RPM / %s | Connect Shaft to Back Input Port)",
            tier.short_name, step.short_label, format_int(tier.max_rpm), cap_lbl
        ))
    elseif step.zone == "neutral" then
        meta:set_string("infotext", string.format(
            "Speed Controller %s [NEUTRAL]: Clutch Disengaged (In: %s RPM -> Out: 0 RPM | -%d KU fine)",
            tier.short_name, format_rpm(in_rpm), fine
        ))
    else
        local out_rpm  = math.min(tier.max_rpm, in_rpm * step.rpm_mult)
        local eff_mult = out_rpm / in_rpm
        local down_ku  = meta:get_int("last_downstream_ku")
        local in_load  = fine + math.ceil(down_ku * eff_mult)
        local out_cap  = meta:get_int("sc_out_ku")
        meta:set_string("infotext", string.format(
            "Speed Controller %s [%s]: In %s RPM (-%s KU) -> Out %s RPM (Load: %s / %s KU | Net Avail: %s/%s KU)",
            tier.short_name, step.short_label,
            format_rpm(in_rpm), format_int(in_load),
            format_rpm(out_rpm), format_int(down_ku), format_int(out_cap),
            format_int(in_avail_ku), format_int(in_supply_ku)
        ))
    end

    meta:set_string("formspec", get_speed_controller_formspec(pos, node))
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

local function deactivate_sc_output(pos, node, preserve_input_telemetry, keep_input_spinning)
    node = node or core.get_node(pos)
    local tier = get_controller_tier_def(node.name) or CONFIG.TIERS[1]
    local meta = core.get_meta(pos)

    if not preserve_input_telemetry then
        meta:set_float("true_in_rpm",      0)
        meta:set_int("true_in_spin",       0)
        meta:set_int("true_in_supply_ku",  0)
        meta:set_int("true_in_avail_ku",   0)
        meta:set_int("true_in_demand_ku",  0)
        meta:set_int("true_in_lit_until",  0)
        meta:set_int("sc_overstressed",    0)
        meta:set_int("sc_input_exceeded",  0)
        meta:set_int("sc_cap_exceeded",    0)
        meta:set_int("sc_loop_fault",      0)
    end
    restore_true_input_meta(meta)

    meta:set_int("sc_out_active", 0)
    meta:set_int("sc_out_ku",     0)
    meta:set_int("source_active", 0)
    meta:set_int("source_ku",     0)
    meta:set_float("source_rpm",  0)
    meta:set_int("source_spin",   0)
    meta:set_int("local_spin",    0)

    local in_spin = meta:get_int("true_in_spin")
    local target_name = get_target_controller_node_name(
        tier.base_name, node.param2, keep_input_spinning and (in_spin ~= 0), in_spin, false, 0, false
    )
    if node.name ~= target_name then
        core.swap_node(pos, {name = target_name, param2 = node.param2})
    end

    drive_output_network(pos, core.get_node(pos))
    update_sc_infotext_and_ui(pos, core.get_node(pos))
end

local function set_sc_idle(pos, node, reason_text)
    if active_relay_sc_hash ~= nil and core.hash_node_position(pos) == active_relay_sc_hash then
        restore_true_input_meta(core.get_meta(pos))
        return
    end
    deactivate_sc_output(pos, node, false, false)
end

local function on_sc_overstress(pos, node, shared_rpm, nspin, total_supply_ku, total_demand_ku, machine_demand_ku)
    if active_relay_sc_hash ~= nil and core.hash_node_position(pos) == active_relay_sc_hash then
        return
    end
    node = node or core.get_node(pos)
    local tier = get_controller_tier_def(node.name) or CONFIG.TIERS[1]
    local fine = tier.friction_fine_ku or CONFIG.FRICTION_FINE_KU
    local meta = core.get_meta(pos)
    local now  = math.floor(core.get_gametime())

    local over_rating, _, _ = is_input_over_tier_rating(tier, total_supply_ku, shared_rpm)
    if over_rating then
        meta:set_int("sc_input_exceeded",  1)
        meta:set_int("sc_overstressed",    0)
        meta:set_int("network_overstressed", 0)
        meta:set_float("true_in_rpm",      shared_rpm or 0)
        meta:set_int("true_in_spin",       nspin or 0)
        meta:set_int("true_in_supply_ku",  total_supply_ku or 0)
        meta:set_int("true_in_avail_ku",   math.max(0, (total_supply_ku or 0) - fine))
        meta:set_int("true_in_demand_ku",  fine)
        meta:set_int("true_in_lit_until",  now + 2)
        deactivate_sc_output(pos, node, true, true)
    else
        meta:set_int("sc_input_exceeded",  0)
        meta:set_int("sc_overstressed",    1)
        meta:set_float("true_in_rpm",      shared_rpm or 0)
        meta:set_int("true_in_spin",       nspin or 0)
        meta:set_int("true_in_supply_ku",  total_supply_ku or 0)
        meta:set_int("true_in_avail_ku",   0)
        meta:set_int("true_in_demand_ku",  machine_demand_ku or 0)
        meta:set_int("true_in_lit_until",  now + 2)
        deactivate_sc_output(pos, node, true, false)
    end

    local timer = core.get_node_timer(pos)
    if not timer:is_started() then
        timer:start(CONFIG.TIMER_INTERVAL)
    end
end

local function wake_sc(pos, node, rpm, spin_dir, demand_ku, avail_ku, supply_ku)
    if active_relay_sc_hash ~= nil and core.hash_node_position(pos) == active_relay_sc_hash then
        restore_true_input_meta(core.get_meta(pos))
        return
    end

    node = node or core.get_node(pos)
    local tier = get_controller_tier_def(node.name) or CONFIG.TIERS[1]
    local fine = tier.friction_fine_ku or CONFIG.FRICTION_FINE_KU
    local meta = core.get_meta(pos)
    local now  = math.floor(core.get_gametime())

    local has_gen, upstream_nodes = input_reaches_real_generator(pos, node)
    if not has_gen then
        set_sc_idle(pos, node)
        return
    end

    -- 1. Check Input Rated Capacity (KU & RPM): auto-engage Neutral if exceeded
    local over_rating, _, _ = is_input_over_tier_rating(tier, supply_ku, rpm)
    if over_rating then
        local reported_demand = demand_ku or 0
        local reclaimed_ku    = math.max(0, reported_demand - fine)
        meta:set_float("true_in_rpm",      rpm)
        meta:set_int("true_in_spin",       spin_dir)
        meta:set_int("true_in_supply_ku",  supply_ku)
        meta:set_int("true_in_avail_ku",   math.min(supply_ku, avail_ku + reclaimed_ku))
        meta:set_int("true_in_demand_ku",  fine)
        meta:set_int("true_in_lit_until",  now + 2)
        meta:set_int("sc_input_exceeded",  1)
        meta:set_int("sc_cap_exceeded",    0)
        meta:set_int("sc_overstressed",    0)
        meta:set_int("sc_loop_fault",      0)
        deactivate_sc_output(pos, node, true, true)

        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TIMER_INTERVAL)
        end
        return
    end

    local step, _, _ = get_effective_step(pos, meta)
    local out_active = (step.rpm_mult > 0 and step.ku_cost_mult > 0)
    local out_rpm    = out_active and math.min(tier.max_rpm, rpm * step.rpm_mult) or 0
    local eff_mult   = (out_active and rpm > 0 and out_rpm > 0) and (out_rpm / rpm) or 0

    local raw_down_ku, loop_found = 0, false
    if out_active then
        raw_down_ku, loop_found = compute_output_downstream_demand_ku(pos, node, out_rpm, nil, upstream_nodes)
    end
    meta:set_int("last_downstream_ku", raw_down_ku)

    -- 2. Check for Input-to-Output Loop Fault
    if loop_found then
        meta:set_float("true_in_rpm",      rpm)
        meta:set_int("true_in_spin",       spin_dir)
        meta:set_int("true_in_supply_ku",  supply_ku)
        meta:set_int("true_in_avail_ku",   avail_ku)
        meta:set_int("true_in_demand_ku",  fine)
        meta:set_int("true_in_lit_until",  now + 2)
        meta:set_int("sc_loop_fault",      1)
        meta:set_int("sc_input_exceeded",  0)
        meta:set_int("sc_cap_exceeded",    0)
        meta:set_int("sc_overstressed",    0)
        deactivate_sc_output(pos, node, true, true)
        return
    end

    -- 3. Check if Downstream Demand exceeds Tier's Max KU (10,240 KU on Tier 1)
    if out_active and tier.max_ku and raw_down_ku > tier.max_ku then
        local reported_demand = demand_ku or 0
        local reclaimed_ku    = math.max(0, reported_demand - fine)
        meta:set_float("true_in_rpm",      rpm)
        meta:set_int("true_in_spin",       spin_dir)
        meta:set_int("true_in_supply_ku",  supply_ku)
        meta:set_int("true_in_avail_ku",   math.min(supply_ku, avail_ku + reclaimed_ku))
        meta:set_int("true_in_demand_ku",  fine)
        meta:set_int("true_in_lit_until",  now + 2)
        meta:set_int("sc_loop_fault",      0)
        meta:set_int("sc_input_exceeded",  0)
        meta:set_int("sc_cap_exceeded",    1)
        meta:set_int("sc_overstressed",    0)
        deactivate_sc_output(pos, node, true, true)

        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TIMER_INTERVAL)
        end
        return
    end

    local scaled_load     = out_active and math.ceil(raw_down_ku * eff_mult) or 0
    local total_in_demand = fine + scaled_load
    local reported_demand = demand_ku or 0
    local extra_ku        = math.max(0, total_in_demand - reported_demand)
    local eff_in_avail_ku = avail_ku - extra_ku

    meta:set_float("true_in_rpm",      rpm)
    meta:set_int("true_in_spin",       spin_dir)
    meta:set_int("true_in_supply_ku",  supply_ku)
    meta:set_int("true_in_avail_ku",   math.max(0, eff_in_avail_ku))
    meta:set_int("true_in_demand_ku",  total_in_demand)
    meta:set_int("true_in_lit_until",  now + 2)

    if eff_in_avail_ku < 0 then
        meta:set_int("sc_loop_fault",      0)
        meta:set_int("sc_input_exceeded",  0)
        meta:set_int("sc_cap_exceeded",    0)
        meta:set_int("sc_overstressed",    1)
        deactivate_sc_output(pos, node, true, false)
        return
    end

    meta:set_int("sc_loop_fault",      0)
    meta:set_int("sc_input_exceeded",  0)
    meta:set_int("sc_cap_exceeded",    0)
    meta:set_int("sc_overstressed",    0)
    restore_true_input_meta(meta)

    local rev_out = (meta:get_int("reverse_output") == 1)

    if out_active then
        local out_spin        = rev_out and (-spin_dir) or spin_dir
        local extra_out_avail = math.floor(eff_in_avail_ku / eff_mult)
        local raw_out_supply  = math.max(1, raw_down_ku + extra_out_avail)
        local out_supply_ku   = tier.max_ku and math.min(tier.max_ku, raw_out_supply) or raw_out_supply

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

    local target_name = get_target_controller_node_name(
        tier.base_name, node.param2, true, spin_dir, out_active, out_rpm, rev_out
    )
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

    local rpm          = meta:get_float("true_in_rpm")
    local supply_ku    = meta:get_int("true_in_supply_ku")
    local lit_until    = meta:get_int("true_in_lit_until")
    local overstressed = (meta:get_int("sc_overstressed") == 1) or (meta:get_int("network_overstressed") == 1)

    if (supply_ku <= 0 or rpm < CONFIG.MIN_INPUT_RPM or now >= lit_until) and not overstressed then
        set_sc_idle(pos, node)
        return true
    end

    core.get_node_timer(pos):start(CONFIG.TIMER_INTERVAL)
    return false
end

for _, tier in pairs(CONFIG.TIERS) do
    if kinetica.register_kinetic_machine then
        kinetica.register_kinetic_machine(tier.base_name, {
            can_ride_piston = false,
            get_demand_ku   = function(rpm, pos, node, total_supply_ku)
                if active_relay_sc_hash and pos and core.hash_node_position(pos) == active_relay_sc_hash then
                    return 0
                end
                return get_controller_total_input_demand_ku(pos, node, rpm, total_supply_ku, nil)
            end,
            has_axle_port   = function(node, d, pos)
                local is_active_relay = (active_relay_sc_hash ~= nil) and
                    (pos == nil or core.hash_node_position(pos) == active_relay_sc_hash)
                if is_active_relay then
                    local out_dir = get_out_dir(node.param2)
                    return (d.x == out_dir.x and d.y == out_dir.y and d.z == out_dir.z)
                else
                    local in_dir = get_in_dir(node.param2)
                    return (d.x == in_dir.x and d.y == in_dir.y and d.z == in_dir.z)
                end
            end,
            set_idle      = set_sc_idle,
            wake          = wake_sc,
            on_overstress = on_sc_overstress,
        })
    end
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
    local best_ku  = 0
    for _, d in ipairs(ALL_6_DIRS) do
        local np = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
        local nnode = core.get_node(np)
        if kinetica.is_kinetic_node and kinetica.is_kinetic_node(nnode.name) then
            local rev = {x = -d.x, y = -d.y, z = -d.z}
            if kinetica.has_axle_port and kinetica.has_axle_port(nnode, rev, np) then
                local nmeta = core.get_meta(np)
                local avail = math.max(nmeta:get_int("rotational_power"), nmeta:get_int("source_ku"))
                if avail > best_ku then
                    best_ku  = avail
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
        if src_dir and src_ku > 0 then
            out_dir = {x = -src_dir.x, y = -src_dir.y, z = -src_dir.z}
            if not CONFIG.ALLOW_VERTICAL_PLACEMENT and out_dir.y ~= 0 then
                out_dir = nil
            end
        end
        if not out_dir then
            if (kinetica.has_axle_port and kinetica.has_axle_port(under_node, diff, under_pos)) or
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
        meta:set_int("sc_overstressed",   0)
        meta:set_int("sc_input_exceeded", 0)
        meta:set_int("sc_cap_exceeded",   0)
        meta:set_int("sc_loop_fault",     0)
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

local function register_controller_tier_nodes(tier)
    local base_name = tier.base_name
    local tint      = tier.casing_tint or ""
    local top_tex   = CONFIG.TEX_TOP_BOTTOM  .. tint
    local side_tex  = CONFIG.TEX_SIDE_CASING .. tint

    local in_face_idle  = make_idle_port_tex(CONFIG.TEX_INPUT_BG,         tint)
    local out_face_idle = make_idle_port_tex(CONFIG.TEX_OUTPUT_GEAR_IDLE, tint)
    local in_anim_cw    = make_input_port_anim(false, CONFIG.ANIM_LEN_INPUT, tint)
    local in_anim_ccw   = make_input_port_anim(true,  CONFIG.ANIM_LEN_INPUT, tint)

    local base_groups   = {handy = 1, pickaxey = 1, axey = 1, kinetic_receiver = 1, speed_controller = tier.tier_num}
    local active_groups = {handy = 1, pickaxey = 1, axey = 1, kinetic_receiver = 1, speed_controller = tier.tier_num, not_in_creative_inventory = 1}

    local function register_variant(node_name, desc, in_tile, out_tile, is_base)
        core.register_node(node_name, {
            description = desc,
            tiles = {
                top_tex,
                top_tex,
                side_tex,
                side_tex,
                in_tile,
                out_tile,
            },
            paramtype2 = "facedir",
            is_ground_content = false,
            on_place = is_base and place_speed_controller or nil,
            drop = base_name,
            groups = is_base and base_groups or active_groups,
            _mcl_hardness = 2.5 + (tier.tier_num - 1) * 0.5,
            _mcl_blast_resistance = 3.5 + (tier.tier_num - 1) * 1.0,
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

    register_variant(base_name, tier.desc, in_face_idle, out_face_idle, true)
    register_variant(base_name .. "_neutral_cw",  tier.short_name .. " Speed Controller (Neutral CW)",  in_anim_ccw, out_face_idle, false)
    register_variant(base_name .. "_neutral_ccw", tier.short_name .. " Speed Controller (Neutral CCW)", in_anim_cw,  out_face_idle, false)

    for _, anim_tier in ipairs(CONFIG.OUTPUT_ANIM_TIERS) do
        local out_cw  = make_output_port_anim(false, anim_tier.length, tint)
        local out_ccw = make_output_port_anim(true,  anim_tier.length, tint)

        for _, in_dir_tag in ipairs({"cw", "ccw"}) do
            local in_tile = (in_dir_tag == "cw") and in_anim_ccw or in_anim_cw
            for _, out_dir_tag in ipairs({"cw", "ccw"}) do
                local out_tile = (out_dir_tag == "cw") and out_cw or out_ccw
                local vname    = base_name .. "_" .. anim_tier.name .. "_" .. in_dir_tag .. "_" .. out_dir_tag
                register_variant(
                    vname,
                    string.format("%s Speed Controller (%s %s)", tier.short_name, string.upper(anim_tier.name), string.upper(out_dir_tag)),
                    in_tile,
                    out_tile,
                    false
                )
            end
        end
    end
end

register_controller_tier_nodes(CONFIG.TIERS[1])
register_controller_tier_nodes(CONFIG.TIERS[2])

core.register_alias("kinetica:speed_controller_active_cw",  TIER1_BASE .. "_medium_cw_cw")
core.register_alias("kinetica:speed_controller_active_ccw", TIER1_BASE .. "_medium_ccw_ccw")

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

-- Tier 1 Crafting Recipe
core.register_craft({
    output = TIER1_BASE,
    recipe = {
        {"mcl_core:iron_ingot", "mcl_core:gold_ingot",   "mcl_core:iron_ingot"},
        {"kinetica:shaft",      "kinetica:gearbox",      "kinetica:shaft"},
        {"mcl_core:iron_ingot", "mcl_redstone:redstone", "mcl_core:iron_ingot"},
    },
})

-- Tier 2 Upgrade Crafting Recipe
core.register_craft({
    output = TIER2_BASE,
    recipe = {
        {"mcl_core:gold_ingot", "mcl_core:diamond",                 "mcl_core:gold_ingot"},
        {"kinetica:gearbox",    TIER1_BASE,                         "kinetica:gearbox"},
        {"mcl_core:gold_ingot", "mcl_redstone_torch:redstoneblock", "mcl_core:gold_ingot"},
    },
})