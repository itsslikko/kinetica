-- kinetica/shaft.lua
kinetica = kinetica or {}

-- ============================================================================
-- TOP CONFIGURATION SECTION
-- ============================================================================
local CONFIG = {
    MAX_SHAFT_RUN                 = 32,
    MAX_WATER_WHEELS              = 10,
    GEARBOX_FINE_KU               = 1,
    GEARSHIFT_FINE_KU             = 1,
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
local GEARSHIFT_FINE_KU   = CONFIG.GEARSHIFT_FINE_KU
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
kinetica.GEARSHIFT_FINE_KU   = kinetica.GEARSHIFT_FINE_KU or GEARSHIFT_FINE_KU
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
    if not rpm or rpm < PUMP_MIN_RPM then return PUMP_MIN_KU end
    return math.min(PUMP_MAX_KU, math.max(PUMP_MIN_KU, math.floor(rpm * PUMP_KU_PER_RPM)))
end

function kinetica.get_pump_water_rate(rpm)
    if not rpm or rpm < PUMP_MIN_RPM then return 0 end
    local rate = 19 + math.floor((rpm / 512) * 81)
    return math.min(100, math.max(15, rate))
end

function kinetica.get_piston_demand_ku(rpm)
    if not rpm or rpm < PISTON_MIN_RPM then return PISTON_MIN_KU end
    return math.min(PISTON_MAX_KU, math.max(PISTON_MIN_KU, math.floor(rpm * PISTON_KU_PER_RPM)))
end

local ALL_DIRS = {
    {x =  1, y =  0, z =  0}, {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0}, {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1}, {x =  0, y =  0, z = -1},
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
    return name == "kinetica:piston_pole_extended" or name == "kinetica:piston_head" or name == "kinetica:piston_head_sticky"
end

function kinetica.is_sticky_contraption_frame(name)
    if name == "mcl_core:slimeblock" or name == "mcl_honey:honey_block" then return true end
    local def = core.registered_nodes[name]
    return (def and def._mcl_pistons_sticky ~= nil) or false
end

function kinetica.is_contraption_conductor(name)
    return kinetica.is_piston_pole_or_head(name) or kinetica.is_sticky_contraption_frame(name)
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
        animation = { type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = anim_length or 0.4 },
    }
end

function kinetica.is_shaft(name)
    if not name then return false end
    return name == IDLE_SHAFT or string.sub(name, 1, #IDLE_SHAFT + 1) == (IDLE_SHAFT .. "_")
end

function kinetica.is_gearbox(name)
    if not name then return false end
    return name == "kinetica:gearbox" or string.sub(name, 1, 17) == "kinetica:gearbox_"
end

function kinetica.is_chain_drive(name)
    if not name then return false end
    return name == "kinetica:chain_drive" or string.sub(name, 1, 21) == "kinetica:chain_drive_"
end

function kinetica.is_water_pump(name)
    if not name then return false end
    return name == "kinetica:water_pump" or string.sub(name, 1, 20) == "kinetica:water_pump_"
end

function kinetica.is_mechanical_piston(name)
    if not name then return false end
    return string.sub(name, 1, 26) == "kinetica:mechanical_piston" or string.sub(name, 1, 33) == "kinetica:mechanical_sticky_piston"
end

function kinetica.is_water_wheel(name)
    return name == "kinetica:water_wheel_big"
end

function kinetica.is_turbine(name)
    if not name then return false end
    return name == "kinetica:turbine" or string.sub(name, 1, 17) == "kinetica:turbine_"
end

function kinetica.is_source_node(name, pos)
    return kinetica.is_water_wheel(name) or kinetica.is_turbine(name)
end

function kinetica.is_gearshift(name)
    if not name then return false end
    return name == "kinetica:gearshift" or string.sub(name, 1, 19) == "kinetica:gearshift_"
end

function kinetica.is_kinetic_node(name)
    return kinetica.is_shaft(name) or
           kinetica.is_gearbox(name) or
           kinetica.is_gearshift(name) or
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
    return (math.abs(sdir.x) == math.abs(dir.x)) and (math.abs(sdir.y) == math.abs(dir.y)) and (math.abs(sdir.z) == math.abs(dir.z))
end

local function abs_axis(param2)
    local d = core.facedir_to_dir(param2 or 0) or {x = 0, y = 0, z = 1}
    return {x = math.abs(d.x), y = math.abs(d.y), z = math.abs(d.z)}
end
kinetica.abs_axis = abs_axis

local function dir_on_axis(d, axis)
    return math.abs(d.x) == axis.x and math.abs(d.y) == axis.y and math.abs(d.z) == axis.z
end

local function get_canonical_shaft_param2(dir)
    if dir.y ~= 0 then return 4
    elseif dir.x ~= 0 then return 1
    else return 0 end
end
kinetica.get_canonical_shaft_param2 = get_canonical_shaft_param2

local function get_active_shaft_node_name(rpm, spin_dir)
    local tier_name = get_anim_tier_name(rpm)
    local dir_tag   = (spin_dir == 1) and "cw" or "ccw"
    local candidate = IDLE_SHAFT .. "_" .. tier_name .. "_" .. dir_tag
    if core.registered_nodes[candidate] then return candidate end
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

    return table.concat({
        "=== KINETIC GLASSES TELEMETRY ===",
        string.format("Block:  Square Tube Shaft [%d/%d]", is_active and sdist or 0, MAX_SHAFT_RUN),
        "State:  " .. (is_active and "ACTIVE" or "IDLE"),
        string.format("Speed:  %s RPM", format_rpm(is_active and rpm or 0)),
        string.format("Power:  %s / %s KU Avail (%s KU Used)",
            format_int(is_active and avail_ku or 0),
            format_int(supply_ku),
            format_int(is_active and used_ku or 0)),
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
        if best_fn then return best_fn(pos, node) end
        return core.get_meta(pos):get_string("glasses_info")
    end
end

function kinetica.get_gearbox_dirs(node_name, param2)
    local is_vert = string.find(node_name, "vertical") ~= nil
    if not is_vert then
        return {
            {x =  1, y = 0, z =  0}, {x = -1, y = 0, z =  0},
            {x =  0, y = 0, z =  1}, {x =  0, y = 0, z = -1},
        }
    else
        local p2 = param2 or 0
        local axisdir = math.floor(p2 / 4)
        local rot = p2 % 4
        local front_dir, back_dir
        if axisdir == 0 or axisdir == 5 then
            local dirs = {{x = 0, y = 0, z = -1}, {x = -1, y = 0, z = 0}, {x = 0, y = 0, z = 1}, {x = 1, y = 0, z = 0}}
            front_dir = dirs[rot + 1]
            back_dir = {x = -front_dir.x, y = 0, z = -front_dir.z}
        elseif axisdir == 1 or axisdir == 2 then
            front_dir = {x = 0, y = 0, z = (axisdir == 1) and 1 or -1}
            back_dir = {x = 0, y = 0, z = -front_dir.z}
        else
            front_dir = {x = (axisdir == 3) and 1 or -1, y = 0, z = 0}
            back_dir = {x = -front_dir.x, y = 0, z = 0}
        end
        return {{x = 0, y = 1, z = 0}, {x = 0, y = -1, z = 0}, front_dir, back_dir}
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
    if kinetica.is_shaft(name) or kinetica.is_gearshift(name) then return kinetica.is_Aligned_With_Dir(node.param2, d)
    elseif kinetica.is_chain_drive(name) then return dir_on_axis(d, abs_axis(node.param2))
    elseif kinetica.is_gearbox(name) then
        for _, gd in ipairs(kinetica.get_gearbox_dirs(name, node.param2)) do
            if gd.x == d.x and gd.y == d.y and gd.z == d.z then return true end
        end
        return false
    elseif kinetica.is_water_pump(name) then
        local axles = kinetica.get_pump_axle_dirs(node.param2)
        return (math.abs(d.x) == math.abs(axles[1].x)) and (math.abs(d.y) == math.abs(axles[1].y)) and (math.abs(d.z) == math.abs(axles[1].z))
    elseif kinetica.is_mechanical_piston(name) then
        if kinetica.piston_has_axle_port then return kinetica.piston_has_axle_port(node, d, pos) end
        local back_dir = core.facedir_to_dir(node.param2 or 0) or {x = 0, y = 0, z = 1}
        return (d.x * back_dir.x + d.y * back_dir.y + d.z * back_dir.z) == 0
    elseif kinetica.is_water_wheel(name) or kinetica.is_turbine(name) then
        local back_dir = core.facedir_to_dir((node.param2 or 0) % 4)
        return (math.abs(d.x) == math.abs(back_dir.x)) and (d.y == 0) and (math.abs(d.z) == math.abs(back_dir.z))
    else
        local mdef = kinetica.get_machine_def(name)
        if mdef then
            if mdef.has_axle_port then return mdef.has_axle_port(node, d, pos) end
            local back_dir = core.facedir_to_dir(node.param2 or 0) or {x = 0, y = 0, z = 1}
            return (d.x == back_dir.x and d.y == back_dir.y and d.z == back_dir.z)
        elseif core.get_item_group(name, "kinetic_receiver") > 0 then
            return true
        end
    end
    return false
end

-- ============================================================================
-- NOTE: The Network Solver logic has been moved to api.lua!
-- ============================================================================

function kinetica.set_node_idle(pos, node, reason_text)
    node = node or core.get_node(pos)
    local name = node.name
    if kinetica.is_contraption_conductor(name) then return end

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
        if name ~= idle_gb then core.swap_node(pos, {name = idle_gb, param2 = node.param2}) end

    elseif kinetica.is_gearshift(name) then
        if kinetica.update_gearshift_node then kinetica.update_gearshift_node(pos, reason_text) end

    elseif kinetica.is_chain_drive(name) then
        if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
            meta:set_string("infotext", "")
        else
            meta:set_string("infotext", reason_text or "Encased Chain Drive: Idle (1 KU Fine | Shares KU & RPM on Demand)")
        end
        if name ~= "kinetica:chain_drive" then core.swap_node(pos, {name = "kinetica:chain_drive", param2 = node.param2}) end

    elseif kinetica.is_water_pump(name) then
        meta:set_string("infotext", reason_text or string.format("Water Pump: Idle (Min %d RPM | Uses 4x RPM KU)", PUMP_MIN_RPM))
        if name ~= "kinetica:water_pump" then core.swap_node(pos, {name = "kinetica:water_pump", param2 = node.param2}) end

    elseif kinetica.is_mechanical_piston(name) then
        if kinetica.set_piston_idle then kinetica.set_piston_idle(pos, node, reason_text) end
    else
        local mdef = kinetica.get_machine_def(name)
        if mdef and mdef.set_idle then mdef.set_idle(pos, node, reason_text) end
    end
end

local function place_shaft(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then return itemstack end
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
    if kinetica.update_network then kinetica.update_network(pos) end
    if math.floor(core.get_gametime()) < meta:get_int("lit_until") then
        meta:set_string("glasses_info", format_shaft_glasses_info(pos, core.get_node(pos)))
        return true
    end
    kinetica.set_node_idle(pos, core.get_node(pos))
    return false
end

local shaft_nodebox = { type = "fixed", fixed = {{-3/16, -3/16, -8/16, 3/16, 3/16, 8/16}} }
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
            if kinetica.schedule_network_update then kinetica.schedule_network_update(pos) end
        end or nil,
        
        after_dig_node = function(pos)
            if kinetica.schedule_network_update then kinetica.schedule_network_update(pos) end
        end,
        
        on_timer = shaft_watchdog_timer,
    })
end

register_shaft_variant(IDLE_SHAFT, CONFIG.TEX_SIDE_OFF, CONFIG.TEX_SIDE_OFF, idle_end, idle_end, true)

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