kinetica = kinetica or {}

local CONFIG = {
    MAX_SHAFT_RUN                 = 32,
    MAX_WATER_WHEELS              = 10,
    GEARBOX_FINE_KU               = 1,
    CHAIN_DRIVE_FINE_KU           = 1,
    MAX_NETWORK_NODES             = 512,
    WATCHDOG_SECONDS              = 2.0,
    MAX_RPM_CAP                   = 3072,
    ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    length = 0.85 },
        { name = "slow",   max_rpm = 15,   length = 0.48 },
        { name = "medium", max_rpm = 63,   length = 0.24 },
        { name = "fast",   max_rpm = 255,  length = 0.11 },
        { name = "hyper",  max_rpm = 1024, length = 0.05 },
        { name = "ultra",  max_rpm = 3072, length = 0.03 },
    },
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    PUMP_MIN_RPM                  = 4,
    PUMP_KU_PER_RPM               = 4,
    PUMP_MIN_KU                   = 16,
    PUMP_MAX_KU                   = 64,
    MAX_PUMP_CHAIN                = 5,
    PISTON_MIN_RPM                = 1,
    PISTON_KU_PER_RPM             = 4,
    PISTON_MIN_KU                 = 16,
    PISTON_MAX_KU                 = 64,
    MAX_PISTON_POLES              = 16,
    TEX_SIDE_TOP_BOT              = "kinetica_shaft_side_side.png",
    TEX_SIDE_OFF                  = "kinetica_shaft_side_off.png",
    TEX_SIDE_ON                   = "kinetica_shaft_side_on.png",
    TEX_SHAFT_OVERLAY             = "kinetica_shaft_connecting_overlay.png",
}

local MAX_SHAFT_RUN       = CONFIG.MAX_SHAFT_RUN
local MAX_WATER_WHEELS    = CONFIG.MAX_WATER_WHEELS
local GEARBOX_FINE_KU     = CONFIG.GEARBOX_FINE_KU
local CHAIN_DRIVE_FINE_KU = CONFIG.CHAIN_DRIVE_FINE_KU
local PUMP_MIN_RPM        = CONFIG.PUMP_MIN_RPM
local PUMP_KU_PER_RPM     = CONFIG.PUMP_KU_PER_RPM
local PUMP_MIN_KU         = CONFIG.PUMP_MIN_KU
local PUMP_MAX_KU         = CONFIG.PUMP_MAX_KU
local MAX_PUMP_CHAIN      = CONFIG.MAX_PUMP_CHAIN
local PISTON_MIN_RPM      = CONFIG.PISTON_MIN_RPM
local PISTON_KU_PER_RPM   = CONFIG.PISTON_KU_PER_RPM
local PISTON_MIN_KU       = CONFIG.PISTON_MIN_KU
local PISTON_MAX_KU       = CONFIG.PISTON_MAX_KU
local MAX_PISTON_POLES    = CONFIG.MAX_PISTON_POLES
local MAX_NETWORK_NODES   = CONFIG.MAX_NETWORK_NODES
local WATCHDOG_SECONDS    = CONFIG.WATCHDOG_SECONDS

kinetica.MAX_SHAFT_RUN       = MAX_SHAFT_RUN
kinetica.MAX_WATER_WHEELS    = MAX_WATER_WHEELS
kinetica.GEARBOX_FINE_KU     = GEARBOX_FINE_KU
kinetica.CHAIN_DRIVE_FINE_KU = CHAIN_DRIVE_FINE_KU
kinetica.PUMP_MIN_RPM        = PUMP_MIN_RPM
kinetica.MAX_PUMP_CHAIN      = MAX_PUMP_CHAIN
kinetica.PISTON_MIN_RPM      = PISTON_MIN_RPM
kinetica.MAX_PISTON_POLES    = MAX_PISTON_POLES
kinetica.MAX_NETWORK_NODES   = MAX_NETWORK_NODES
kinetica.MAX_RPM_CAP         = CONFIG.MAX_RPM_CAP

local IDLE_SHAFT = "kinetica:shaft"
local ACT_CW     = "kinetica:shaft_active_cw"
local ACT_CCW    = "kinetica:shaft_active_ccw"

local function format_int(n)
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
kinetica.format_int = format_int

local function format_rpm(rpm)
    local r = tonumber(rpm) or 0
    if math.abs(r - math.floor(r + 0.5)) < 0.05 then
        return format_int(math.floor(r + 0.5))
    end
    return string.format("%.1f", r)
end
kinetica.format_rpm = format_rpm

local function get_anim_tier_name(rpm)
    local clamped = math.min(CONFIG.MAX_RPM_CAP, math.max(0, rpm or 0))
    for _, tier in ipairs(CONFIG.ANIM_TIERS) do
        if clamped <= tier.max_rpm then
            return tier.name
        end
    end
    return CONFIG.ANIM_TIERS[#CONFIG.ANIM_TIERS].name
end

function kinetica.get_pump_demand_ku(rpm)
    if not rpm or rpm < PUMP_MIN_RPM then
        return PUMP_MIN_KU
    end
    return math.min(PUMP_MAX_KU, math.max(PUMP_MIN_KU, math.floor(rpm * PUMP_KU_PER_RPM)))
end

function kinetica.get_pump_water_rate(rpm)
    if not rpm or rpm < PUMP_MIN_RPM then
        return 0
    end
    local rate = 19 + math.floor((rpm / 512) * 81)
    return math.min(100, math.max(15, rate))
end

function kinetica.get_piston_demand_ku(rpm)
    if not rpm or rpm < PISTON_MIN_RPM then
        return PISTON_MIN_KU
    end
    return math.min(PISTON_MAX_KU, math.max(PISTON_MIN_KU, math.floor(rpm * PISTON_KU_PER_RPM)))
end

local ALL_DIRS = {
    {x =  1, y =  0, z =  0},
    {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0},
    {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1},
    {x =  0, y =  0, z = -1},
}
kinetica.directions = kinetica.directions or ALL_DIRS

kinetica.registered_machines = kinetica.registered_machines or {}

function kinetica.register_kinetic_machine(prefix, def)
    def = def or {}
    def.prefix = prefix
    kinetica.registered_machines[prefix] = def
end

function kinetica.get_machine_def(node_name)
    if not node_name then return nil end
    local best_def = nil
    local best_len = -1
    for prefix, def in pairs(kinetica.registered_machines) do
        if node_name == prefix or string.sub(node_name, 1, #prefix + 1) == (prefix .. "_") then
            if #prefix > best_len then
                best_len = #prefix
                best_def = def
            end
        end
    end
    return best_def
end

function kinetica.is_registered_machine(node_name)
    return kinetica.get_machine_def(node_name) ~= nil
end

function kinetica.is_piston_pole_or_head(name)
    return name == "kinetica:piston_pole_extended" or
           name == "kinetica:piston_head" or
           name == "kinetica:piston_head_sticky"
end

function kinetica.is_sticky_contraption_frame(name)
    if name == "mcl_core:slimeblock" or name == "mcl_honey:honey_block" then
        return true
    end
    local def = core.registered_nodes[name]
    return (def and def._mcl_pistons_sticky ~= nil) or false
end

function kinetica.is_contraption_conductor(name)
    return kinetica.is_piston_pole_or_head(name) or
           kinetica.is_sticky_contraption_frame(name)
end

function kinetica.make_4frame_anim(tex_name, reverse_order, extra_transform, anim_length)
    extra_transform = extra_transform or ""
    local final_tex = tex_name .. extra_transform

    if reverse_order then
        final_tex = "[combine:16x64" ..
            ":0,0=("  .. tex_name .. "\\^[sheet\\:1x4\\:0,0)" ..
            ":0,16=(" .. tex_name .. "\\^[sheet\\:1x4\\:0,3)" ..
            ":0,32=(" .. tex_name .. "\\^[sheet\\:1x4\\:0,2)" ..
            ":0,48=(" .. tex_name .. "\\^[sheet\\:1x4\\:0,1)" ..
            extra_transform
    end

    return {
        name = final_tex,
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length or 0.4,
        },
    }
end

function kinetica.is_shaft(name)
    if not name then return false end
    return name == IDLE_SHAFT or string.sub(name, 1, #IDLE_SHAFT + 1) == (IDLE_SHAFT .. "_")
end

function kinetica.is_gearbox(name)
    if not name then return false end
    return name == "kinetica:gearbox" or
           string.sub(name, 1, 17) == "kinetica:gearbox_"
end

function kinetica.is_chain_drive(name)
    if not name then return false end
    return name == "kinetica:chain_drive" or
           string.sub(name, 1, 21) == "kinetica:chain_drive_"
end

function kinetica.is_water_pump(name)
    if not name then return false end
    return name == "kinetica:water_pump" or
           string.sub(name, 1, 20) == "kinetica:water_pump_"
end

function kinetica.is_mechanical_piston(name)
    if not name then return false end
    return string.sub(name, 1, 26) == "kinetica:mechanical_piston" or
           string.sub(name, 1, 33) == "kinetica:mechanical_sticky_piston"
end

function kinetica.is_water_wheel(name)
    return name == "kinetica:water_wheel_big"
end

function kinetica.is_turbine(name)
    if not name then return false end
    return name == "kinetica:turbine" or
           string.sub(name, 1, 17) == "kinetica:turbine_"
end

function kinetica.is_source_node(name, pos)
    return kinetica.is_water_wheel(name) or kinetica.is_turbine(name)
end

function kinetica.is_kinetic_node(name)
    return kinetica.is_shaft(name) or
           kinetica.is_gearbox(name) or
           kinetica.is_chain_drive(name) or
           kinetica.is_water_pump(name) or
           kinetica.is_mechanical_piston(name) or
           kinetica.is_contraption_conductor(name) or
           kinetica.is_registered_machine(name) or
           kinetica.is_source_node(name) or
           (core.get_item_group(name, "kinetic_receiver") > 0) or
           (core.get_item_group(name, "rotational_source") > 0)
end

function kinetica.is_Aligned_With_Dir(param2, dir)
    local sdir = core.facedir_to_dir(param2 or 0) or {x = 0, y = 0, z = 1}
    return (math.abs(sdir.x) == math.abs(dir.x)) and
           (math.abs(sdir.y) == math.abs(dir.y)) and
           (math.abs(sdir.z) == math.abs(dir.z))
end

local function abs_axis(param2)
    local d = core.facedir_to_dir(param2 or 0) or {x = 0, y = 0, z = 1}
    return {x = math.abs(d.x), y = math.abs(d.y), z = math.abs(d.z)}
end
kinetica.abs_axis = abs_axis

local function same_axis(a, b)
    return a.x == b.x and a.y == b.y and a.z == b.z
end

local function dir_on_axis(d, axis)
    return math.abs(d.x) == axis.x and math.abs(d.y) == axis.y and math.abs(d.z) == axis.z
end

local function get_canonical_shaft_param2(dir)
    if dir.y ~= 0 then
        return 4
    elseif dir.x ~= 0 then
        return 1
    else
        return 0
    end
end
kinetica.get_canonical_shaft_param2 = get_canonical_shaft_param2

local function get_active_shaft_node_name(rpm, spin_dir)
    local tier_name = get_anim_tier_name(rpm)
    local dir_tag   = (spin_dir == 1) and "cw" or "ccw"
    local candidate = IDLE_SHAFT .. "_" .. tier_name .. "_" .. dir_tag
    if core.registered_nodes[candidate] then
        return candidate
    end
    return (spin_dir == 1) and ACT_CW or ACT_CCW
end

kinetica._glasses_formatters = kinetica._glasses_formatters or {}

local function format_shaft_glasses_info(pos, node)
    local meta      = core.get_meta(pos)
    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local used_ku   = meta:get_int("network_used_ku")
    local sdist     = meta:get_int("shaft_dist")
    if sdist <= 0 then sdist = 1 end
    local now       = math.floor(core.get_gametime())
    local is_active = (node.name ~= IDLE_SHAFT) and (supply_ku > 0 and rpm > 0 and now < meta:get_int("lit_until"))

    local ax = abs_axis(node.param2)
    local axis_lbl = (ax.y ~= 0) and "Vertical (Y)" or ((ax.x ~= 0) and "East-West (X)" or "North-South (Z)")

    return table.concat({
        "=== KINETIC GLASSES TELEMETRY ===",
        string.format("Block:  Square Tube Shaft [%d/%d]", is_active and sdist or 0, MAX_SHAFT_RUN),
        "State:  " .. (is_active and "ACTIVE" or "IDLE"),
        string.format("Speed:  %s RPM", format_rpm(is_active and rpm or 0)),
        string.format("Power:  %s / %s KU Avail (%s KU Used)",
            format_int(is_active and avail_ku or 0),
            format_int(supply_ku),
            format_int(is_active and used_ku or 0)),
        "Axis:   " .. axis_lbl,
    }, "\n")
end

kinetica._glasses_formatters[IDLE_SHAFT] = format_shaft_glasses_info

if not kinetica.get_glasses_info then
    function kinetica.get_glasses_info(pos, node)
        node = node or core.get_node(pos)
        local best_fn = nil
        local best_len = -1
        for prefix, fn in pairs(kinetica._glasses_formatters) do
            if node.name == prefix or string.sub(node.name or "", 1, #prefix + 1) == (prefix .. "_") then
                if #prefix > best_len then
                    best_len = #prefix
                    best_fn = fn
                end
            end
        end
        if best_fn then
            return best_fn(pos, node)
        end
        return core.get_meta(pos):get_string("glasses_info")
    end
end

function kinetica.get_gearbox_dirs(node_name, param2)
    local is_vert = string.find(node_name, "vertical") ~= nil

    if not is_vert then
        return {
            {x =  1, y = 0, z =  0},
            {x = -1, y = 0, z =  0},
            {x =  0, y = 0, z =  1},
            {x =  0, y = 0, z = -1},
        }
    else
        local p2 = param2 or 0
        local axisdir = math.floor(p2 / 4)
        local rot = p2 % 4
        local front_dir, back_dir

        if axisdir == 0 or axisdir == 5 then
            local dirs = {
                {x =  0, y = 0, z = -1},
                {x = -1, y = 0, z =  0},
                {x =  0, y = 0, z =  1},
                {x =  1, y = 0, z =  0},
            }
            front_dir = dirs[rot + 1]
            back_dir = {x = -front_dir.x, y = 0, z = -front_dir.z}
        elseif axisdir == 1 or axisdir == 2 then
            front_dir = {x = 0, y = 0, z = (axisdir == 1) and 1 or -1}
            back_dir = {x = 0, y = 0, z = -front_dir.z}
        else
            front_dir = {x = (axisdir == 3) and 1 or -1, y = 0, z = 0}
            back_dir = {x = -front_dir.x, y = 0, z = 0}
        end

        return {
            {x = 0, y =  1, z = 0},
            {x = 0, y = -1, z = 0},
            front_dir,
            back_dir,
        }
    end
end

function kinetica.get_pump_axle_dirs(param2)
    local back_dir  = core.facedir_to_dir((param2 or 0) % 4)
    local right_dir = {x = back_dir.z, y = 0, z = -back_dir.x}
    local left_dir  = {x = -right_dir.x, y = 0, z = -right_dir.z}
    return {right_dir, left_dir}
end

function kinetica.has_axle_port(node, d, pos)
    local name = node.name
    if kinetica.is_shaft(name) then
        return kinetica.is_Aligned_With_Dir(node.param2, d)
    elseif kinetica.is_chain_drive(name) then
        return dir_on_axis(d, abs_axis(node.param2))
    elseif kinetica.is_gearbox(name) then
        for _, gd in ipairs(kinetica.get_gearbox_dirs(name, node.param2)) do
            if gd.x == d.x and gd.y == d.y and gd.z == d.z then
                return true
            end
        end
        return false
    elseif kinetica.is_water_pump(name) then
        local axles = kinetica.get_pump_axle_dirs(node.param2)
        return (math.abs(d.x) == math.abs(axles[1].x)) and
               (math.abs(d.y) == math.abs(axles[1].y)) and
               (math.abs(d.z) == math.abs(axles[1].z))
    elseif kinetica.is_mechanical_piston(name) then
        if kinetica.piston_has_axle_port then
            return kinetica.piston_has_axle_port(node, d, pos)
        end
        local back_dir = core.facedir_to_dir(node.param2 or 0) or {x = 0, y = 0, z = 1}
        return (d.x * back_dir.x + d.y * back_dir.y + d.z * back_dir.z) == 0
    elseif kinetica.is_water_wheel(name) or kinetica.is_turbine(name) then
        local back_dir = core.facedir_to_dir((node.param2 or 0) % 4)
        return (math.abs(d.x) == math.abs(back_dir.x)) and
               (d.y == 0) and
               (math.abs(d.z) == math.abs(back_dir.z))
    else
        local mdef = kinetica.get_machine_def(name)
        if mdef then
            if mdef.has_axle_port then
                return mdef.has_axle_port(node, d, pos)
            end
            local back_dir = core.facedir_to_dir(node.param2 or 0) or {x = 0, y = 0, z = 1}
            return (d.x == back_dir.x and d.y == back_dir.y and d.z == back_dir.z)
        elseif core.get_item_group(name, "kinetic_receiver") > 0 then
            return true
        end
    end
    return false
end

local function are_contraption_coupled(nodeA, nodeB, dir)
    local nameA, nameB = nodeA.name, nodeB.name

    if kinetica.is_mechanical_piston(nameA) and kinetica.is_piston_pole_or_head(nameB) then
        local backA = core.facedir_to_dir(nodeA.param2 or 0) or {x = 0, y = 0, z = 1}
        if dir.x == -backA.x and dir.y == -backA.y and dir.z == -backA.z and nodeA.param2 == nodeB.param2 then
            return true
        end
    end
    if kinetica.is_piston_pole_or_head(nameA) and kinetica.is_mechanical_piston(nameB) then
        local backB = core.facedir_to_dir(nodeB.param2 or 0) or {x = 0, y = 0, z = 1}
        if dir.x == backB.x and dir.y == backB.y and dir.z == backB.z and nodeA.param2 == nodeB.param2 then
            return true
        end
    end

    if kinetica.is_piston_pole_or_head(nameA) and kinetica.is_piston_pole_or_head(nameB) then
        local backA = core.facedir_to_dir(nodeA.param2 or 0) or {x = 0, y = 0, z = 1}
        if nodeA.param2 == nodeB.param2 and
           math.abs(dir.x) == math.abs(backA.x) and
           math.abs(dir.y) == math.abs(backA.y) and
           math.abs(dir.z) == math.abs(backA.z) then
            return true
        end
    end

    if kinetica.is_mechanical_piston(nameA) or
       nameA == "kinetica:piston_head" or
       nameA == "kinetica:piston_head_sticky" then
        local backA = core.facedir_to_dir(nodeA.param2 or 0) or {x = 0, y = 0, z = 1}
        if dir.x == -backA.x and dir.y == -backA.y and dir.z == -backA.z then
            local mdefB = kinetica.get_machine_def(nameB)
            if (mdefB and mdefB.can_ride_piston ~= false) or kinetica.is_sticky_contraption_frame(nameB) then
                return true
            end
        end
    end
    if kinetica.is_mechanical_piston(nameB) or
       nameB == "kinetica:piston_head" or
       nameB == "kinetica:piston_head_sticky" then
        local backB = core.facedir_to_dir(nodeB.param2 or 0) or {x = 0, y = 0, z = 1}
        if dir.x == backB.x and dir.y == backB.y and dir.z == backB.z then
            local mdefA = kinetica.get_machine_def(nameA)
            if (mdefA and mdefA.can_ride_piston ~= false) or kinetica.is_sticky_contraption_frame(nameA) then
                return true
            end
        end
    end

    local stickyA = kinetica.is_sticky_contraption_frame(nameA)
    local stickyB = kinetica.is_sticky_contraption_frame(nameB)
    local mdefA   = kinetica.get_machine_def(nameA)
    local mdefB   = kinetica.get_machine_def(nameB)

    if stickyA and stickyB then
        return true
    end
    if stickyA and (mdefB and mdefB.can_ride_piston ~= false) then
        return true
    end
    if stickyB and (mdefA and mdefA.can_ride_piston ~= false) then
        return true
    end

    if mdefA and mdefB and mdefA.prefix == mdefB.prefix and mdefA.can_ride_piston ~= false then
        return true
    end

    return false
end

local function are_nodes_coupled(nodeA, nodeB, dir, posA, posB)
    if kinetica.is_chain_drive(nodeA.name) and kinetica.is_chain_drive(nodeB.name) then
        local axA = abs_axis(nodeA.param2)
        local axB = abs_axis(nodeB.param2)
        if same_axis(axA, axB) and not dir_on_axis(dir, axA) then
            return true, "chain_side"
        end
    end

    local rev = {x = -dir.x, y = -dir.y, z = -dir.z}
    if kinetica.has_axle_port(nodeA, dir, posA) and kinetica.has_axle_port(nodeB, rev, posB) then
        return true, "axle"
    end

    if are_contraption_coupled(nodeA, nodeB, dir) then
        return true, "contraption"
    end

    return false, nil
end
kinetica.are_nodes_coupled = are_nodes_coupled

local function gearbox_port_alpha(node_name, p)
    local is_vert = string.find(node_name, "vertical") ~= nil
    if is_vert then
        return (p.y ~= 0) and 1 or -1
    else
        return (p.z ~= 0) and 1 or -1
    end
end

local function get_edge_spin_mult(nodeA, nodeB, dir)
    local mult = 1
    if kinetica.is_gearbox(nodeA.name) then
        local sigma_out = dir.x + dir.y + dir.z
        local alpha_out = gearbox_port_alpha(nodeA.name, dir)
        mult = mult * (-sigma_out * alpha_out)
    end
    if kinetica.is_gearbox(nodeB.name) then
        local in_port = {x = -dir.x, y = -dir.y, z = -dir.z}
        local sigma_in = in_port.x + in_port.y + in_port.z
        local alpha_in = gearbox_port_alpha(nodeB.name, in_port)
        mult = mult * (-sigma_in * alpha_in)
    end
    return mult
end

function kinetica.break_conflicting_shaft(cpos)
    local cnode = core.get_node(cpos)
    local drop_item = nil

    if kinetica.is_shaft(cnode.name) then
        drop_item = IDLE_SHAFT
    elseif kinetica.is_chain_drive(cnode.name) then
        drop_item = "kinetica:chain_drive"
    elseif kinetica.is_gearbox(cnode.name) then
        local is_vert = string.find(cnode.name, "vertical") ~= nil
        drop_item = is_vert and "kinetica:gearbox_vertical" or "kinetica:gearbox"
    else
        return false
    end

    core.remove_node(cpos)
    core.add_item(cpos, drop_item)
    core.sound_play("default_break_metal", {pos = cpos, max_hear_distance = 16, gain = 1.0}, true)
    core.add_particlespawner({
        amount = 18,
        time = 0.25,
        minpos = {x = cpos.x - 0.25, y = cpos.y - 0.25, z = cpos.z - 0.25},
        maxpos = {x = cpos.x + 0.25, y = cpos.y + 0.25, z = cpos.z + 0.25},
        minvel = {x = -1.3, y = 0.6, z = -1.3},
        maxvel = {x = 1.3, y = 2.4, z = 1.3},
        minexptime = 0.3,
        maxexptime = 0.8,
        minsize = 1.5,
        maxsize = 3.2,
        texture = "mcl_particles_smoke.png",
    })
    return true
end

local function find_conflict_shaft(k1, k2, parent, nodes_by_key)
    local ancestors1 = {}
    local cur = k1
    while cur do
        ancestors1[cur] = true
        cur = parent[cur]
    end

    local path2 = {}
    cur = k2
    while cur and not ancestors1[cur] do
        table.insert(path2, cur)
        cur = parent[cur]
    end
    local lca = cur

    local path = {}
    cur = k1
    while cur and cur ~= lca do
        table.insert(path, cur)
        cur = parent[cur]
    end
    if lca then table.insert(path, lca) end
    for i = #path2, 1, -1 do
        table.insert(path, path2[i])
    end

    local path_shafts = {}
    local path_relays = {}
    for _, k in ipairs(path) do
        local info = nodes_by_key[k]
        if info then
            if kinetica.is_shaft(info.node.name) then
                table.insert(path_shafts, info.pos)
            elseif kinetica.is_gearbox(info.node.name) or kinetica.is_chain_drive(info.node.name) then
                table.insert(path_relays, info.pos)
            end
        end
    end

    if #path_shafts > 0 then
        return path_shafts[math.ceil(#path_shafts / 2)]
    end

    for _, info in pairs(nodes_by_key) do
        if kinetica.is_shaft(info.node.name) then
            return info.pos
        end
    end

    if #path_relays > 0 then
        return path_relays[math.ceil(#path_relays / 2)]
    end

    return nil
end

function kinetica.set_node_idle(pos, node, reason_text)
    node = node or core.get_node(pos)
    local name = node.name
    if kinetica.is_contraption_conductor(name) then
        return
    end

    local meta = core.get_meta(pos)
    meta:set_int("rotational_power", 0)
    meta:set_int("network_supply_ku", 0)
    meta:set_int("network_used_ku", 0)
    meta:set_int("network_overstressed", 0)
    meta:set_float("rpm", 0)
    meta:set_int("overdrive_tier", 0)
    meta:set_int("spin_dir", 0)
    meta:set_int("lit_until", 0)
    meta:set_int("shaft_dist", 0)
    meta:set_string("source_pos", "")

    if kinetica.is_shaft(name) then
        if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
            meta:set_string("infotext", "")
        else
            meta:set_string("infotext", reason_text or "Square Tube Shaft: Idle (0 KU - Max 32 per run)")
        end
        if name ~= IDLE_SHAFT then
            core.swap_node(pos, {name = IDLE_SHAFT, param2 = node.param2})
        end
        meta:set_string("glasses_info", format_shaft_glasses_info(pos, core.get_node(pos)))

    elseif kinetica.is_gearbox(name) then
        local is_vert = string.find(name, "vertical") ~= nil
        local idle_gb = is_vert and "kinetica:gearbox_vertical" or "kinetica:gearbox"
        if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
            meta:set_string("infotext", "")
        else
            meta:set_string("infotext", reason_text or (is_vert
                and "Vertical Gearbox: Idle (1 KU Fine | Shares KU & RPM on Demand)"
                or "Gearbox: Idle (1 KU Fine | Shares KU & RPM on Demand)"))
        end
        if name ~= idle_gb then
            core.swap_node(pos, {name = idle_gb, param2 = node.param2})
        end

    elseif kinetica.is_chain_drive(name) then
        if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
            meta:set_string("infotext", "")
        else
            meta:set_string("infotext", reason_text or "Encased Chain Drive: Idle (1 KU Fine | Shares KU & RPM on Demand)")
        end
        if name ~= "kinetica:chain_drive" then
            core.swap_node(pos, {name = "kinetica:chain_drive", param2 = node.param2})
        end

    elseif kinetica.is_water_pump(name) then
        meta:set_string("infotext", reason_text or string.format("Water Pump: Idle (Min %d RPM | Uses 4x RPM KU)", PUMP_MIN_RPM))
        if name ~= "kinetica:water_pump" then
            core.swap_node(pos, {name = "kinetica:water_pump", param2 = node.param2})
        end

    elseif kinetica.is_mechanical_piston(name) then
        if kinetica.set_piston_idle then
            kinetica.set_piston_idle(pos, node, reason_text)
        end
    else
        local mdef = kinetica.get_machine_def(name)
        if mdef and mdef.set_idle then
            mdef.set_idle(pos, node, reason_text)
        end
    end
end

local function read_source_state(pos, node)
    if kinetica.is_water_wheel(node.name) and kinetica.refresh_water_wheel then
        kinetica.refresh_water_wheel(pos, node)
    elseif kinetica.is_turbine(node.name) and kinetica.refresh_turbine then
        kinetica.refresh_turbine(pos, node)
    end

    local meta   = core.get_meta(pos)
    local active = meta:get_int("source_active") == 1
    local ku     = meta:get_int("source_ku")
    local rpm    = meta:get_float("source_rpm")
    local spin   = meta:get_int("source_spin")
    if spin == 0 then spin = 1 end
    return active and (ku > 0) and (rpm > 0), ku, rpm, spin
end

local solver_depth = 0
local MAX_SOLVER_DEPTH = 8

local function run_post_solve_actions(actions)
    for i = 1, #actions do
        actions[i]()
    end
end

function kinetica.update_network(start_pos)
    if solver_depth >= MAX_SOLVER_DEPTH or not start_pos then return end
    local start_node = core.get_node(start_pos)
    if not kinetica.is_kinetic_node(start_node.name) then return end

    solver_depth = solver_depth + 1
    local now = math.floor(core.get_gametime())
    local post_actions = {}

    local start_key = core.hash_node_position(start_pos)
    local nodes_by_key = {}
    local parent = {}
    local queue = {start_key}

    nodes_by_key[start_key] = {
        key       = start_key,
        pos       = {x = start_pos.x, y = start_pos.y, z = start_pos.z},
        node      = start_node,
        pol       = 1,
        shaft_run = kinetica.is_shaft(start_node.name) and 1 or 0,
        in_dir    = {x = 0, y = 0, z = 0},
    }

    local self_loop_conflict = nil
    local head = 1

    while head <= #queue and #queue < MAX_NETWORK_NODES do
        local cur_key = queue[head]
        head = head + 1
        local cur = nodes_by_key[cur_key]

        for _, d in ipairs(ALL_DIRS) do
            local npos  = {x = cur.pos.x + d.x, y = cur.pos.y + d.y, z = cur.pos.z + d.z}
            local nnode = core.get_node(npos)

            if kinetica.is_kinetic_node(nnode.name) then
                local coupled, link_type = are_nodes_coupled(cur.node, nnode, d, cur.pos, npos)
                if coupled then
                    local next_run = kinetica.is_shaft(nnode.name) and (cur.shaft_run + 1) or 0
                    if next_run <= MAX_SHAFT_RUN then
                        local nkey = core.hash_node_position(npos)
                        local mult = (link_type == "contraption") and 1 or get_edge_spin_mult(cur.node, nnode, d)
                        local expected_pol = cur.pol * mult

                        if not nodes_by_key[nkey] then
                            parent[nkey] = cur_key
                            nodes_by_key[nkey] = {
                                key       = nkey,
                                pos       = npos,
                                node      = nnode,
                                pol       = expected_pol,
                                shaft_run = next_run,
                                in_dir    = d,
                            }
                            queue[#queue + 1] = nkey
                        else
                            if link_type ~= "contraption" and nodes_by_key[nkey].pol ~= expected_pol and not self_loop_conflict then
                                self_loop_conflict = {k1 = cur_key, k2 = nkey}
                            end
                        end
                    end
                end
            end
        end
    end

    local water_wheel_count = 0
    local active_sources    = {}

    for _, k in ipairs(queue) do
        local info = nodes_by_key[k]
        if kinetica.is_water_wheel(info.node.name) then
            water_wheel_count = water_wheel_count + 1
        end
        if kinetica.is_source_node(info.node.name, info.pos) then
            local is_act, ku, rpm, spin = read_source_state(info.pos, info.node)
            if is_act then
                table.insert(active_sources, {
                    key  = k,
                    pos  = info.pos,
                    node = info.node,
                    ku   = ku,
                    rpm  = rpm,
                    spin = spin,
                    pol  = info.pol,
                })
            end
        end
    end

    if water_wheel_count > MAX_WATER_WHEELS then
        local limit_msg = string.format(
            "OVERLOADED! (Max %d Water Wheels in series - %d connected!)",
            MAX_WATER_WHEELS, water_wheel_count
        )
        for _, k in ipairs(queue) do
            local info = nodes_by_key[k]
            if not kinetica.is_source_node(info.node.name, info.pos) then
                post_actions[#post_actions + 1] = function()
                    kinetica.set_node_idle(info.pos, info.node, limit_msg)
                    local m = core.get_meta(info.pos)
                    m:set_int("network_overstressed", 1)
                end
            else
                local smeta = core.get_meta(info.pos)
                smeta:set_int("network_overstressed", 1)
                smeta:set_int("network_supply_ku", 0)
                smeta:set_int("network_used_ku", 0)
                smeta:set_int("rotational_power", 0)
                smeta:set_string("infotext", limit_msg)
            end
        end
        solver_depth = solver_depth - 1
        run_post_solve_actions(post_actions)
        return
    end

    if #active_sources == 0 then
        for _, k in ipairs(queue) do
            local info = nodes_by_key[k]
            if not kinetica.is_source_node(info.node.name, info.pos) then
                post_actions[#post_actions + 1] = function()
                    kinetica.set_node_idle(info.pos, info.node)
                end
            else
                local smeta = core.get_meta(info.pos)
                smeta:set_int("network_overstressed", 0)
                smeta:set_int("network_supply_ku", 0)
                smeta:set_int("network_used_ku", 0)
                smeta:set_int("rotational_power", 0)
            end
        end
        solver_depth = solver_depth - 1
        run_post_solve_actions(post_actions)
        return
    end

    if self_loop_conflict then
        local break_pos = find_conflict_shaft(self_loop_conflict.k1, self_loop_conflict.k2, parent, nodes_by_key)
        solver_depth = solver_depth - 1
        if break_pos and kinetica.break_conflicting_shaft(break_pos) then
            for _, src in ipairs(active_sources) do
                kinetica.update_network(src.pos)
            end
        end
        return
    end

    local ref = active_sources[1]
    local base_spin = ref.spin * ref.pol
    local total_supply_ku = ref.ku
    local shared_rpm = ref.rpm

    for i = 2, #active_sources do
        local s = active_sources[i]
        local expected_s_spin = base_spin * s.pol
        local rpm_mismatch  = math.abs(s.rpm - shared_rpm) > 0.01
        local spin_mismatch = (s.spin ~= expected_s_spin)

        if rpm_mismatch or spin_mismatch then
            local break_pos = find_conflict_shaft(ref.key, s.key, parent, nodes_by_key)
            solver_depth = solver_depth - 1
            if break_pos and kinetica.break_conflicting_shaft(break_pos) then
                kinetica.update_network(ref.pos)
                kinetica.update_network(s.pos)
            else
                local reason = rpm_mismatch
                    and string.format("JAMMED: RPM Mismatch (%s RPM vs %s RPM)!", format_rpm(shared_rpm), format_rpm(s.rpm))
                    or "JAMMED: Conflicting Rotation Directions!"
                for _, k in ipairs(queue) do
                    local info = nodes_by_key[k]
                    if not kinetica.is_source_node(info.node.name, info.pos) then
                        kinetica.set_node_idle(info.pos, info.node, reason)
                    else
                        local smeta = core.get_meta(info.pos)
                        smeta:set_int("network_overstressed", 1)
                        smeta:set_string("infotext", reason)
                    end
                end
            end
            return
        end
        total_supply_ku = total_supply_ku + s.ku
    end

    local gearbox_count     = 0
    local chain_drive_count = 0
    local pump_count        = 0
    local piston_count      = 0
    local custom_machine_ku = 0
    local per_pump_ku       = kinetica.get_pump_demand_ku(shared_rpm)
    local per_piston_ku     = kinetica.get_piston_demand_ku(shared_rpm)

    for _, k in ipairs(queue) do
        local info  = nodes_by_key[k]
        local nname = info.node.name
        if not kinetica.is_source_node(nname, info.pos) then
            if kinetica.is_gearbox(nname) then
                gearbox_count = gearbox_count + 1
            elseif kinetica.is_chain_drive(nname) then
                chain_drive_count = chain_drive_count + 1
            elseif kinetica.is_water_pump(nname) then
                pump_count = pump_count + 1
            elseif kinetica.is_mechanical_piston(nname) then
                piston_count = piston_count + 1
            else
                local mdef = kinetica.get_machine_def(nname)
                if mdef then
                    local m_ku = mdef.get_demand_ku and mdef.get_demand_ku(shared_rpm, info.pos, info.node, total_supply_ku) or 16
                    info.machine_demand_ku = m_ku
                    custom_machine_ku = custom_machine_ku + m_ku
                end
            end
        end
    end

    local total_fines     = (gearbox_count * GEARBOX_FINE_KU) + (chain_drive_count * CHAIN_DRIVE_FINE_KU)
    local after_fines_ku  = math.max(0, total_supply_ku - total_fines)
    local total_demand_ku = total_fines
        + (pump_count * per_pump_ku)
        + (piston_count * per_piston_ku)
        + custom_machine_ku

    if total_supply_ku < total_demand_ku or (total_fines > 0 and after_fines_ku <= 0) then
        local over_msg = string.format(
            "OVERSTRESSED! (Network Demand: %s KU > Supply: %s KU @ %s RPM)",
            format_int(total_demand_ku), format_int(total_supply_ku), format_rpm(shared_rpm)
        )
        for _, k in ipairs(queue) do
            local info = nodes_by_key[k]
            local nspin = (base_spin * info.pol >= 0) and 1 or -1
            if not kinetica.is_source_node(info.node.name, info.pos) then
                local mdef = kinetica.get_machine_def(info.node.name)
                post_actions[#post_actions + 1] = function()
                    kinetica.set_node_idle(info.pos, info.node, over_msg)
                    local m = core.get_meta(info.pos)
                    m:set_int("network_overstressed", 1)
                    m:set_int("network_supply_ku", total_supply_ku)
                    m:set_int("network_used_ku", total_demand_ku)
                    if mdef and mdef.on_overstress then
                        mdef.on_overstress(
                            info.pos,
                            core.get_node(info.pos),
                            shared_rpm,
                            nspin,
                            total_supply_ku,
                            total_demand_ku,
                            info.machine_demand_ku or 0
                        )
                    end
                end
            else
                local smeta = core.get_meta(info.pos)
                smeta:set_int("network_overstressed", 1)
                smeta:set_int("network_supply_ku", total_supply_ku)
                smeta:set_int("network_used_ku", total_demand_ku)
                smeta:set_int("rotational_power", 0)
                smeta:set_string("infotext", over_msg)
            end
        end
        solver_depth = solver_depth - 1
        run_post_solve_actions(post_actions)
        return
    end

    local shared_avail_ku = math.max(0, total_supply_ku - total_demand_ku)

    local dist_map = {}
    local dqueue = {}
    for _, k in ipairs(queue) do
        local info = nodes_by_key[k]
        if not kinetica.is_shaft(info.node.name) then
            dist_map[k] = 0
            dqueue[#dqueue + 1] = k
        end
    end
    local dhead = 1
    while dhead <= #dqueue do
        local ck = dqueue[dhead]
        dhead = dhead + 1
        local cinfo = nodes_by_key[ck]
        local cdist = dist_map[ck]
        for _, d in ipairs(ALL_DIRS) do
            local npos = {x = cinfo.pos.x + d.x, y = cinfo.pos.y + d.y, z = cinfo.pos.z + d.z}
            local nkey = core.hash_node_position(npos)
            local ninfo = nodes_by_key[nkey]
            if ninfo and dist_map[nkey] == nil then
                local coupled, _ = are_nodes_coupled(cinfo.node, ninfo.node, d, cinfo.pos, ninfo.pos)
                if coupled then
                    dist_map[nkey] = cdist + 1
                    dqueue[#dqueue + 1] = nkey
                end
            end
        end
    end

    local tier_name = get_anim_tier_name(shared_rpm)

    for _, k in ipairs(queue) do
        local info  = nodes_by_key[k]
        local pos   = info.pos
        local node  = info.node
        local name  = node.name

        if not kinetica.is_contraption_conductor(name) then
            local meta  = core.get_meta(pos)
            local nspin = (base_spin * info.pol >= 0) and 1 or -1

            meta:set_int("rotational_power", shared_avail_ku)
            meta:set_int("network_supply_ku", total_supply_ku)
            meta:set_int("network_used_ku", total_demand_ku)
            meta:set_int("network_overstressed", 0)
            meta:set_float("rpm", shared_rpm)
            meta:set_int("spin_dir", nspin)
            meta:set_int("lit_until", now + 2)
            meta:set_int("in_dir_x", info.in_dir.x)
            meta:set_int("in_dir_y", info.in_dir.y)
            meta:set_int("in_dir_z", info.in_dir.z)

            if kinetica.is_shaft(name) then
                local sdist = math.min(MAX_SHAFT_RUN, dist_map[k] or 1)
                meta:set_int("shaft_dist", sdist)
                local axis     = abs_axis(node.param2)
                local canon_p2 = get_canonical_shaft_param2(axis)
                local target   = get_active_shaft_node_name(shared_rpm, nspin)

                if name ~= target or node.param2 ~= canon_p2 then
                    core.swap_node(pos, {name = target, param2 = canon_p2})
                end

                if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
                    meta:set_string("infotext", "")
                else
                    meta:set_string("infotext", string.format(
                        "Square Tube Shaft [%d/%d]: ACTIVE (%s KU avail / %s KU total | %s KU used | %s RPM)",
                        sdist, MAX_SHAFT_RUN,
                        format_int(shared_avail_ku), format_int(total_supply_ku),
                        format_int(total_demand_ku), format_rpm(shared_rpm)
                    ))
                end
                meta:set_string("glasses_info", format_shaft_glasses_info(pos, core.get_node(pos)))
                core.get_node_timer(pos):start(WATCHDOG_SECONDS)

            elseif kinetica.is_gearbox(name) then
                local is_vert   = string.find(name, "vertical") ~= nil
                local gb_base   = is_vert and "kinetica:gearbox_vertical" or "kinetica:gearbox"
                local dir_tag   = (nspin == 1) and "cw" or "ccw"
                local tier_cand = gb_base .. "_" .. tier_name .. "_" .. dir_tag
                local target    = core.registered_nodes[tier_cand] and tier_cand or (gb_base .. "_active_" .. dir_tag)

                if name ~= target then
                    core.swap_node(pos, {name = target, param2 = node.param2})
                end
                meta:set_string("infotext", string.format(
                    "%s: ACTIVE (%s KU avail / %s KU total | -%d KU Fine | %s RPM)",
                    is_vert and "Vertical Gearbox" or "Gearbox",
                    format_int(shared_avail_ku), format_int(total_supply_ku),
                    GEARBOX_FINE_KU, format_rpm(shared_rpm)
                ))
                core.get_node_timer(pos):start(WATCHDOG_SECONDS)

            elseif kinetica.is_chain_drive(name) then
                local back      = core.facedir_to_dir(node.param2) or {x = 0, y = 0, z = 1}
                local axis_sign = back.x + back.y + back.z
                local vis       = (nspin * axis_sign >= 0) and 1 or -1
                local dir_tag   = (vis == 1) and "cw" or "ccw"
                local tier_cand = "kinetica:chain_drive_" .. tier_name .. "_" .. dir_tag
                local target    = core.registered_nodes[tier_cand] and tier_cand or ("kinetica:chain_drive_active_" .. dir_tag)

                if name ~= target then
                    core.swap_node(pos, {name = target, param2 = node.param2})
                end
                meta:set_string("infotext", string.format(
                    "Encased Chain Drive: ACTIVE (%s KU avail / %s KU total | %d drives (-%d KU Fine) | %s RPM)",
                    format_int(shared_avail_ku), format_int(total_supply_ku),
                    chain_drive_count, chain_drive_count * CHAIN_DRIVE_FINE_KU, format_rpm(shared_rpm)
                ))
                core.get_node_timer(pos):start(WATCHDOG_SECONDS)

            elseif kinetica.is_water_pump(name) then
                meta:set_int("pump_demand_ku", per_pump_ku)
                local ptimer = core.get_node_timer(pos)
                if not ptimer:is_started() then
                    ptimer:start(1.0)
                end

            elseif kinetica.is_mechanical_piston(name) then
                meta:set_int("piston_demand_ku", per_piston_ku)
                if kinetica.wake_mechanical_piston then
                    post_actions[#post_actions + 1] = function()
                        kinetica.wake_mechanical_piston(pos, core.get_node(pos), shared_rpm, nspin, per_piston_ku, shared_avail_ku, total_supply_ku)
                    end
                else
                    local ptimer = core.get_node_timer(pos)
                    if not ptimer:is_started() then
                        ptimer:start(0.5)
                    end
                end

            elseif kinetica.is_source_node(name, pos) then
                local my_ku = meta:get_int("source_ku")
                if kinetica.is_water_wheel(name) then
                    meta:set_string("infotext", string.format(
                        "Big Water Wheel [%d/%d]: ACTIVE (+%s KU | Shared Network: %s KU avail / %s KU total | %s RPM)",
                        water_wheel_count, MAX_WATER_WHEELS,
                        format_int(my_ku), format_int(shared_avail_ku), format_int(total_supply_ku), format_rpm(shared_rpm)
                    ))
                elseif kinetica.is_turbine(name) then
                    local steam = meta:get_int("steam")
                    if my_ku > 0 then
                        meta:set_string("infotext", string.format(
                            "Steam Turbine: ACTIVE (+%s KU | Shared Network: %s KU avail / %s KU total | %s RPM | Steam: %d%%)",
                            format_int(my_ku), format_int(shared_avail_ku), format_int(total_supply_ku), format_rpm(shared_rpm), steam
                        ))
                    else
                        meta:set_string("infotext", string.format(
                            "Steam Turbine: PASSIVE AXLE (0 KU out | Network: %s KU avail / %s KU total | %s RPM)",
                            format_int(shared_avail_ku), format_int(total_supply_ku), format_rpm(shared_rpm)
                        ))
                    end
                end

            elseif kinetica.is_registered_machine(name) then
                local mdef = kinetica.get_machine_def(name)
                local m_ku = info.machine_demand_ku or 16
                meta:set_int("machine_demand_ku", m_ku)
                if mdef and mdef.wake then
                    post_actions[#post_actions + 1] = function()
                        mdef.wake(pos, core.get_node(pos), shared_rpm, nspin, m_ku, shared_avail_ku, total_supply_ku)
                    end
                else
                    local mtimer = core.get_node_timer(pos)
                    if not mtimer:is_started() then
                        mtimer:start(0.5)
                    end
                end

            elseif core.get_item_group(name, "kinetic_receiver") > 0 then
                local rtimer = core.get_node_timer(pos)
                if not rtimer:is_started() then
                    rtimer:start(1.0)
                end
            end
        end
    end

    solver_depth = solver_depth - 1
    run_post_solve_actions(post_actions)
end

function kinetica.schedule_network_update(pos)
    local p = {x = pos.x, y = pos.y, z = pos.z}
    core.after(0.05, function()
        if kinetica.is_kinetic_node(core.get_node(p).name) then
            kinetica.update_network(p)
        end
        for _, d in ipairs(ALL_DIRS) do
            local np = {x = p.x + d.x, y = p.y + d.y, z = p.z + d.z}
            if kinetica.is_kinetic_node(core.get_node(np).name) then
                kinetica.update_network(np)
            end
        end
    end)
end

function kinetica.push_rotation(start_pos, dir, power_ku, rpm, overdrive_tier, spin_dir)
    kinetica.update_network(start_pos)
end

local function place_shaft(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then
        return itemstack
    end

    local diff = {
        x = pointed_thing.above.x - pointed_thing.under.x,
        y = pointed_thing.above.y - pointed_thing.under.y,
        z = pointed_thing.above.z - pointed_thing.under.z,
    }

    local param2 = get_canonical_shaft_param2(diff)
    return core.item_place_node(itemstack, placer, pointed_thing, param2)
end

local function shaft_watchdog_timer(pos, elapsed)
    local now  = math.floor(core.get_gametime())
    local meta = core.get_meta(pos)
    if now < meta:get_int("lit_until") then
        meta:set_string("glasses_info", format_shaft_glasses_info(pos, core.get_node(pos)))
        return true
    end
    kinetica.update_network(pos)
    if math.floor(core.get_gametime()) < meta:get_int("lit_until") then
        meta:set_string("glasses_info", format_shaft_glasses_info(pos, core.get_node(pos)))
        return true
    end
    kinetica.set_node_idle(pos, core.get_node(pos))
    return false
end

local shaft_nodebox = {
    type = "fixed",
    fixed = {
        {-3/16, -3/16, -8/16, 3/16, 3/16, 8/16},
    },
}

local idle_end = "[combine:16x16:0,0=" .. CONFIG.TEX_SHAFT_OVERLAY

local base_groups   = {pickaxey = 1, kinetic_shaft = 1}
local active_groups = {pickaxey = 1, kinetic_shaft = 1, not_in_creative_inventory = 1}

local function register_shaft_variant(node_name, right_tile, left_tile, back_tile, front_tile, is_base)
    core.register_node(node_name, {
        description = is_base
            and "Square Tube Shaft (Max 32 blocks per run | Shares KU & RPM)"
            or  "Square Tube Shaft",
        drawtype = "nodebox",
        paramtype = "light",
        paramtype2 = "facedir",
        sunlight_propagates = true,
        tiles = {
            CONFIG.TEX_SIDE_TOP_BOT,
            CONFIG.TEX_SIDE_TOP_BOT,
            right_tile,
            left_tile,
            back_tile,
            front_tile,
        },
        node_box = shaft_nodebox,
        selection_box = shaft_nodebox,
        on_place = is_base and place_shaft or nil,
        drop = is_base and nil or IDLE_SHAFT,
        groups = is_base and base_groups or active_groups,
        _mcl_hardness = 2.0,
        _mcl_blast_resistance = 3.0,
        sounds = mcl_sounds and mcl_sounds.node_sound_metal_defaults and mcl_sounds.node_sound_metal_defaults() or nil,

        on_construct = is_base and function(pos)
            kinetica.set_node_idle(pos, core.get_node(pos))
            kinetica.schedule_network_update(pos)
        end or nil,

        after_dig_node = function(pos)
            kinetica.schedule_network_update(pos)
        end,

        on_timer = shaft_watchdog_timer,
    })
end

register_shaft_variant(
    IDLE_SHAFT,
    CONFIG.TEX_SIDE_OFF,
    CONFIG.TEX_SIDE_OFF,
    idle_end,
    idle_end,
    true
)

local med_side_up   = kinetica.make_4frame_anim(CONFIG.TEX_SIDE_ON,       false, "", 0.24)
local med_side_down = kinetica.make_4frame_anim(CONFIG.TEX_SIDE_ON,       true,  "", 0.24)
local med_end_cw    = kinetica.make_4frame_anim(CONFIG.TEX_SHAFT_OVERLAY, false, "", 0.24)
local med_end_ccw   = kinetica.make_4frame_anim(CONFIG.TEX_SHAFT_OVERLAY, true,  "", 0.24)

register_shaft_variant(ACT_CW,  med_side_down, med_side_up,   med_end_ccw, med_end_cw,  false)
register_shaft_variant(ACT_CCW, med_side_up,   med_side_down, med_end_cw,  med_end_ccw, false)

for _, tier in ipairs(CONFIG.ANIM_TIERS) do
    local s_up   = kinetica.make_4frame_anim(CONFIG.TEX_SIDE_ON,       false, "", tier.length)
    local s_down = kinetica.make_4frame_anim(CONFIG.TEX_SIDE_ON,       true,  "", tier.length)
    local e_cw   = kinetica.make_4frame_anim(CONFIG.TEX_SHAFT_OVERLAY, false, "", tier.length)
    local e_ccw  = kinetica.make_4frame_anim(CONFIG.TEX_SHAFT_OVERLAY, true,  "", tier.length)

    register_shaft_variant(IDLE_SHAFT .. "_" .. tier.name .. "_cw",  s_down, s_up,   e_ccw, e_cw,  false)
    register_shaft_variant(IDLE_SHAFT .. "_" .. tier.name .. "_ccw", s_up,   s_down, e_cw,  e_ccw, false)
end

core.register_alias("kinetica:shaft_active", ACT_CW)

core.register_lbm({
    label             = "Wake kinetica Shafts on chunk load",
    name              = "kinetica:wake_shafts_lbm",
    nodenames         = {"group:kinetic_shaft"},
    run_at_every_load = true,
    action = function(pos, node)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(WATCHDOG_SECONDS)
        end
    end,
})

core.register_craft({
    output = "kinetica:shaft 8",
    recipe = {
        {"mcl_core:iron_ingot", "mcl_core:iron_ingot", "mcl_core:iron_ingot"},
    },
})