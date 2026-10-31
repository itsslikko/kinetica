kinetica = kinetica or {}

local CONFIG = {
    MIN_RPM                       = 8,
    BASE_KU_PER_RPM               = 2,
    MIN_BASE_KU                   = 16,
    MAX_BASE_KU                   = 128,
    KU_PER_POLE                   = 6,
    MAX_POLES                     = 32,
    MAX_CONTRAPTION_BLOCKS        = 64,
    MAX_RPM_CAP                   = 1024,
    ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    length = 0.85 },
        { name = "slow",   max_rpm = 15,   length = 0.48 },
        { name = "medium", max_rpm = 63,   length = 0.24 },
        { name = "fast",   max_rpm = 255,  length = 0.11 },
        { name = "hyper",  max_rpm = 1024, length = 0.05 },
    },
    SLIDER_MULTS = {
        [-4] = 16.0,
        [-3] = 8.0,
        [-2] = 4.0,
        [-1] = 2.0,
        [0]  = 0.0,
        [1]  = 1.0,
        [2]  = 0.5,
        [3]  = 0.25,
        [4]  = 0.125,
    },
    TICK_INTERVAL                 = 0.20,
    STEP_TIME_AT_MIN_RPM          = 0.75,
    STEP_TIME_AT_256_RPM          = 0.18,
    INVERT_SPIN_DIRECTION         = false,
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    TEX_SOLID_FACE                = "kinetica_andisite_casing.png",
    TEX_SHAFT_OVERLAY             = "kinetica_shaft_connecting_overlay.png",
}

local PISTON_STD    = "kinetica:mechanical_piston"
local PISTON_STICKY = "kinetica:sticky_mechanical_piston"
local HEAD_STD      = "kinetica:piston_head"
local HEAD_STICKY   = "kinetica:piston_head_sticky"
local POLE_NAME     = "kinetica:piston_pole"

local raw_get_node             = core.get_node
local raw_swap_node            = core.swap_node
local contraption_demand_guard = false
local idling_pistons           = {}
local waking_pistons           = {}

local ALL_6_DIRS = {
    {x =  1, y =  0, z =  0},
    {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0},
    {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1},
    {x =  0, y =  0, z = -1},
}

local AXIS_TO_PUSH_DIR = {
    [0] = {x =  0, y =  1, z =  0},
    [1] = {x =  0, y =  0, z =  1},
    [2] = {x =  0, y =  0, z = -1},
    [3] = {x =  1, y =  0, z =  0},
    [4] = {x = -1, y =  0, z =  0},
    [5] = {x =  0, y = -1, z =  0},
}

local function resolve_clean_tile(candidates, fallback)
    for _, node_name in ipairs(candidates) do
        local def = core.registered_nodes[node_name]
        if def and def.tiles and def.tiles[1] then
            local t = def.tiles[1]
            local name = (type(t) == "string" and t) or (type(t) == "table" and t.name) or nil
            if type(name) == "string" and name ~= "" and not string.find(name, "%[combine") then
                return name
            end
        end
    end
    return fallback
end

local WOOD_TEX  = resolve_clean_tile({"mcl_core:wood", "mcl_trees:wood_oak", "default:wood"}, "default_wood.png")
local SLIME_TEX = resolve_clean_tile({"mcl_slimeblock:slime_block", "mcl_core:slimeblock"}, "mcl_core_slime.png")

-- =========================================================
-- TEXTURES: STATIC ANDESITE CASING + SPINNING SHAFT OVERLAY
-- =========================================================
local SIDE_PORT_IDLE       = "[combine:16x16:0,0=" .. CONFIG.TEX_SOLID_FACE .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY
local BACK_POLE_SOCKET_TEX = "[combine:16x16:0,0=" .. CONFIG.TEX_SOLID_FACE .. ":4,4=" .. WOOD_TEX .. "\\^[sheet\\:2x2\\:0,0"
local HEAD_FRONT_STD       = "[combine:16x16:0,0=" .. CONFIG.TEX_SOLID_FACE .. ":1,1=" .. WOOD_TEX .. "\\^[resize\\:14x14"
local HEAD_FRONT_STK       = "[combine:16x16:0,0=" .. WOOD_TEX .. ":4,4=" .. SLIME_TEX .. "\\^[sheet\\:2x2\\:0,0"

local POLE_SIDE_TEX = "[combine:16x16" ..
    ":0,0="  .. WOOD_TEX ..
    ":0,0="  .. CONFIG.TEX_SOLID_FACE .. "\\^[sheet\\:1x8\\:0,0" ..
    ":0,14=" .. CONFIG.TEX_SOLID_FACE .. "\\^[sheet\\:1x8\\:0,0"
local POLE_END_TEX = BACK_POLE_SOCKET_TEX

local function make_piston_side_anim(reverse, anim_length)
    local casing = CONFIG.TEX_SOLID_FACE
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
            length   = anim_length or 0.24,
        },
    }
end

-- =========================================================
-- 3D NODEBOX SHAPES FOR PISTON, HEAD & POLE
-- =========================================================
local PISTON_RETRACTED_NODEBOX = {
    type = "fixed",
    fixed = {
        {-8/16, -8/16, -8/16,  8/16,  3/16,  8/16},
        {-6/16,  3/16, -6/16,  6/16,  5/16,  6/16},
        {-8/16,  5/16, -8/16,  8/16,  8/16,  8/16},
    },
}

local PISTON_EXTENDED_NODEBOX = {
    type = "fixed",
    fixed = {
        {-8/16, -8/16, -8/16,  8/16,  3/16,  8/16},
        {-6/16,  3/16, -6/16,  6/16,  5/16,  6/16},
        {-2/16,  5/16, -2/16,  2/16,  8/16,  2/16},
        {-3/16,  6/16, -3/16,  3/16,  8/16,  3/16},
    },
}

local PISTON_HEAD_NODEBOX = {
    type = "fixed",
    fixed = {
        {-8/16,  5/16, -8/16,  8/16,  8/16,  8/16},
        {-5/16,  2/16, -5/16,  5/16,  5/16,  5/16},
        {-2/16, -8/16, -2/16,  2/16,  2/16,  2/16},
        {-3/16, -8/16, -3/16,  3/16, -6/16,  3/16},
    },
}

local PISTON_POLE_NODEBOX = {
    type = "fixed",
    fixed = {
        {-2/16, -8/16, -2/16,  2/16,  8/16,  2/16},
        {-3/16, -8/16, -3/16,  3/16, -6/16,  3/16},
        {-3/16,  6/16, -3/16,  3/16,  8/16,  3/16},
    },
}

local FULL_SELECTION_BOX = {
    type  = "fixed",
    fixed = {-8/16, -8/16, -8/16, 8/16, 8/16, 8/16},
}

local POLE_SELECTION_BOX = {
    type  = "fixed",
    fixed = {-3.5/16, -8/16, -3.5/16, 3.5/16, 8/16, 3.5/16},
}

-- =========================================================
-- IDENTIFIERS & DIRECTION HELPERS
-- =========================================================
local function is_mechanical_piston(name)
    if not name then return false end
    return name == PISTON_STD or
           name == PISTON_STICKY or
           string.sub(name, 1, #PISTON_STD + 1) == (PISTON_STD .. "_") or
           string.sub(name, 1, #PISTON_STICKY + 1) == (PISTON_STICKY .. "_")
end
kinetica.is_mechanical_piston = is_mechanical_piston

local function is_sticky_piston_node(name)
    if not name then return false end
    return name == PISTON_STICKY or
           string.sub(name, 1, #PISTON_STICKY + 1) == (PISTON_STICKY .. "_")
end

local function is_piston_head_node(name)
    return name == HEAD_STD or name == HEAD_STICKY
end

local function is_piston_pole_node(name)
    return name == POLE_NAME or name == "kinetica:piston_extension_pole"
end
kinetica.is_piston_pole = is_piston_pole_node

local function is_sticky_contraption_frame(name)
    if not name or name == "air" then return false end
    if string.find(name, "slime") or string.find(name, "honey_block") then
        return true
    end
    return core.get_item_group(name, "sticky_contraption_frame") > 0
end
kinetica.is_sticky_contraption_frame = is_sticky_contraption_frame

local function get_anim_tier_name(rpm)
    local clamped = math.min(CONFIG.MAX_RPM_CAP, math.max(0, rpm or 0))
    for _, tier in ipairs(CONFIG.ANIM_TIERS) do
        if clamped <= tier.max_rpm then
            return tier.name
        end
    end
    return CONFIG.ANIM_TIERS[#CONFIG.ANIM_TIERS].name
end

local function get_push_dir(param2)
    local axisdir = math.floor(((param2 or 0) % 24) / 4)
    local d = AXIS_TO_PUSH_DIR[axisdir] or AXIS_TO_PUSH_DIR[0]
    return {x = d.x, y = d.y, z = d.z}
end

local function get_back_dir(param2)
    local d = get_push_dir(param2)
    return {x = -d.x, y = -d.y, z = -d.z}
end

local function is_same_axis(param2_a, param2_b)
    local da = get_push_dir(param2_a)
    local db = get_push_dir(param2_b)
    return math.abs(da.x) == math.abs(db.x) and
           math.abs(da.y) == math.abs(db.y) and
           math.abs(da.z) == math.abs(db.z)
end

local function dir_to_piston_param2(push_dir)
    local axisdir = 0
    if push_dir.y > 0 then
        axisdir = 0
    elseif push_dir.y < 0 then
        axisdir = 5
    elseif push_dir.z > 0 then
        axisdir = 1
    elseif push_dir.z < 0 then
        axisdir = 2
    elseif push_dir.x > 0 then
        axisdir = 3
    elseif push_dir.x < 0 then
        axisdir = 4
    end

    if axisdir >= 1 and axisdir <= 4 then
        for rot = 0, 3 do
            local p2 = axisdir * 4 + rot
            local zdir = core.facedir_to_dir(p2)
            if zdir and zdir.y == 1 then
                return p2
            end
        end
    end
    return axisdir * 4
end

local function look_to_unit_dir(placer)
    local look = placer and placer:get_look_dir() or {x = 0, y = 0, z = 1}
    local ax, ay, az = math.abs(look.x), math.abs(look.y), math.abs(look.z)
    if ay > ax and ay > az then
        return {x = 0, y = (look.y > 0) and 1 or -1, z = 0}
    elseif ax >= az then
        return {x = (look.x > 0) and 1 or -1, y = 0, z = 0}
    else
        return {x = 0, y = 0, z = (look.z > 0) and 1 or -1}
    end
end

local function get_step_interval_seconds(rpm)
    if not rpm or rpm <= CONFIG.MIN_RPM then
        return CONFIG.STEP_TIME_AT_MIN_RPM
    end
    local t = math.min(1.0, math.max(0.0, (rpm - CONFIG.MIN_RPM) / (256 - CONFIG.MIN_RPM)))
    return CONFIG.STEP_TIME_AT_MIN_RPM + t * (CONFIG.STEP_TIME_AT_256_RPM - CONFIG.STEP_TIME_AT_MIN_RPM)
end

-- =========================================================
-- POLE COUNTING & ASSEMBLY FINDERS
-- =========================================================
local function get_front_extension(pos, push_dir, piston_param2)
    local ext = 0
    for i = 1, CONFIG.MAX_POLES + 1 do
        local cpos  = {x = pos.x + push_dir.x * i, y = pos.y + push_dir.y * i, z = pos.z + push_dir.z * i}
        local cnode = raw_get_node(cpos)
        if is_piston_pole_node(cnode.name) and is_same_axis(cnode.param2, piston_param2) then
            ext = ext + 1
        elseif is_piston_head_node(cnode.name) then
            local hdir = get_push_dir(cnode.param2)
            if hdir.x == push_dir.x and hdir.y == push_dir.y and hdir.z == push_dir.z then
                return ext + 1, cpos, cnode
            else
                break
            end
        else
            break
        end
    end
    return 0, nil, nil
end

local function get_rear_pole_count(pos, push_dir, piston_param2)
    local poles = 0
    for i = 1, CONFIG.MAX_POLES do
        local bpos  = {x = pos.x - push_dir.x * i, y = pos.y - push_dir.y * i, z = pos.z - push_dir.z * i}
        local bnode = raw_get_node(bpos)
        if is_piston_pole_node(bnode.name) and is_same_axis(bnode.param2, piston_param2) then
            poles = poles + 1
        else
            break
        end
    end
    return poles
end

local function get_total_piston_poles(pos, node)
    node = node or raw_get_node(pos)
    local push_dir   = get_push_dir(node.param2)
    local front_ext  = get_front_extension(pos, push_dir, node.param2)
    local rear_poles = get_rear_pole_count(pos, push_dir, node.param2)
    local total      = math.min(CONFIG.MAX_POLES, front_ext + rear_poles)
    return total, front_ext, rear_poles
end

local function find_piston_from_pole_or_head(part_pos, part_param2)
    local d = get_push_dir(part_param2)
    for _, sign in ipairs({-1, 1}) do
        local step = {x = d.x * sign, y = d.y * sign, z = d.z * sign}
        for i = 1, CONFIG.MAX_POLES + 1 do
            local cpos  = {x = part_pos.x + step.x * i, y = part_pos.y + step.y * i, z = part_pos.z + step.z * i}
            local cnode = raw_get_node(cpos)
            if is_piston_pole_node(cnode.name) and is_same_axis(cnode.param2, part_param2) then
                -- Continue walking along the pole chain
            elseif is_mechanical_piston(cnode.name) and is_same_axis(cnode.param2, part_param2) then
                return cpos, cnode
            else
                break
            end
        end
    end
    return nil, nil
end

local function get_piston_assembly_positions(piston_pos, piston_node)
    piston_node = piston_node or raw_get_node(piston_pos)
    local list  = {{x = piston_pos.x, y = piston_pos.y, z = piston_pos.z}}
    if not is_mechanical_piston(piston_node.name) then
        return list
    end

    local push_dir   = get_push_dir(piston_node.param2)
    local rear_poles = get_rear_pole_count(piston_pos, push_dir, piston_node.param2)
    for i = 1, rear_poles do
        list[#list + 1] = {
            x = piston_pos.x - push_dir.x * i,
            y = piston_pos.y - push_dir.y * i,
            z = piston_pos.z - push_dir.z * i,
        }
    end

    local front_ext = get_front_extension(piston_pos, push_dir, piston_node.param2)
    for i = 1, front_ext do
        list[#list + 1] = {
            x = piston_pos.x + push_dir.x * i,
            y = piston_pos.y + push_dir.y * i,
            z = piston_pos.z + push_dir.z * i,
        }
    end
    return list
end

local function get_target_piston_node_name(is_sticky, is_extended, is_active, rpm, spin_dir)
    local base_name  = is_sticky and PISTON_STICKY or PISTON_STD
    local ext_suffix = is_extended and "_ext" or ""

    if not is_active or not rpm or rpm < CONFIG.MIN_RPM then
        local idle_cand = base_name .. ext_suffix
        if core.registered_nodes[idle_cand] then
            return idle_cand
        end
        return base_name
    end

    local tier_name = get_anim_tier_name(rpm)
    local dir_tag   = (spin_dir == -1) and "ccw" or "cw"
    local candidate = base_name .. ext_suffix .. "_" .. tier_name .. "_" .. dir_tag
    if core.registered_nodes[candidate] then
        return candidate
    end
    return base_name .. ext_suffix
end

-- =========================================================
-- SPEED CONTROLLER & DIRECTION CHANGER MODULATION
-- =========================================================
local function is_direction_changer_node(name)
    if not name or name == "air" then return false end
    if kinetica.is_gearshift and kinetica.is_gearshift(name) then return true end
    if kinetica.is_direction_controller and kinetica.is_direction_controller(name) then return true end
    if string.find(name, "kinetica:gearshift", 1, true) or
       string.find(name, "kinetica:direction", 1, true) or
       string.find(name, "kinetica:clutch", 1, true) then
        return true
    end
    return core.get_item_group(name, "kinetica_gearshift") > 0 or
           core.get_item_group(name, "direction_controller") > 0
end

local function is_contraption_controller_node(name)
    if not name or name == "air" then return false end
    if kinetica.is_speed_controller and kinetica.is_speed_controller(name) then
        return true
    end
    return is_direction_changer_node(name)
end

local function has_redstone_signal_at(pos)
    if mcl_redstone and mcl_redstone.get_power then
        local ok, pwr = pcall(mcl_redstone.get_power, vector.new(pos.x, pos.y, pos.z))
        if ok and pwr and pwr > 0 then
            return true
        end
    end
    return false
end

local function eval_controller_modulation(ctrl_pos, ctrl_node, in_rpm, in_spin, supply_ku, avail_ku, update_ui_meta)
    local cmeta = core.get_meta(ctrl_pos)
    local cname = ctrl_node.name
    local now   = math.floor(core.get_gametime())

    if kinetica.is_speed_controller and kinetica.is_speed_controller(cname) then
        if update_ui_meta and cmeta:get_int("true_in_lit_until") <= now then
            cmeta:set_float("true_in_rpm",     in_rpm)
            cmeta:set_int("true_in_spin",      in_spin)
            cmeta:set_int("true_in_supply_ku", math.max(32, supply_ku or 32))
            cmeta:set_int("true_in_avail_ku",  math.max(32, avail_ku or 32))
        end

        if has_redstone_signal_at(ctrl_pos) then
            return 0, in_spin, true, "Redstone Clutch Active", 0.0
        end

        local idx      = math.max(-4, math.min(4, cmeta:get_int("slider_idx")))
        local rpm_mult = CONFIG.SLIDER_MULTS[idx] or 0.0
        local rev_out  = (cmeta:get_int("reverse_output") == 1)
        local out_spin = rev_out and (-in_spin) or in_spin

        if rpm_mult <= 0 then
            return 0, out_spin, true, "Speed Controller in NEUTRAL (Right-Click Controller to Set Speed)", 0.0
        end

        local out_rpm  = math.min(CONFIG.MAX_RPM_CAP, in_rpm * rpm_mult)
        local eff_mult = (in_rpm > 0) and (out_rpm / in_rpm) or rpm_mult
        local lbl      = string.format("Speed Controller (%.3gx RPM%s)", rpm_mult, rev_out and ", Reversed" or "")
        return out_rpm, out_spin, false, lbl, eff_mult
    end

    if is_direction_changer_node(cname) then
        if kinetica.eval_gearshift_modulation then
            local orpm, ospin, cl, lbl = kinetica.eval_gearshift_modulation(ctrl_pos, ctrl_node, in_rpm, in_spin)
            return orpm, ospin, cl, lbl, cl and 0.0 or 1.0
        end
        local rs_active = has_redstone_signal_at(ctrl_pos)
        local meta_rev  = (cmeta:get_int("reverse_output") == 1) or
                          (cmeta:get_int("reversed") == 1) or
                          (string.find(cname, "_rev", 1, true) ~= nil)
        local is_rev    = rs_active or meta_rev
        local clutched  = (cmeta:get_int("clutched") == 1)
        local out_spin  = is_rev and (-in_spin) or in_spin
        return clutched and 0 or in_rpm, out_spin, clutched,
               is_rev and "Gearshift (Reversed)" or "Gearshift (Normal)",
               clutched and 0.0 or 1.0
    end

    return in_rpm, in_spin, false, nil, 1.0
end

local function find_controller_for_piston(piston_pos, piston_node, cluster_list)
    local push_dir = get_push_dir(piston_node.param2)

    for _, d in ipairs(ALL_6_DIRS) do
        if (d.x * push_dir.x + d.y * push_dir.y + d.z * push_dir.z) == 0 then
            local npos  = {x = piston_pos.x + d.x, y = piston_pos.y + d.y, z = piston_pos.z + d.z}
            local nnode = raw_get_node(npos)
            if is_contraption_controller_node(nnode.name) then
                return npos, nnode
            end
        end
    end

    if kinetica.get_glued_cluster_positions then
        local glued = kinetica.get_glued_cluster_positions(piston_pos)
        for _, gpos in ipairs(glued) do
            local gnode = raw_get_node(gpos)
            if is_contraption_controller_node(gnode.name) then
                return gpos, gnode
            end
        end
    end

    if cluster_list then
        for _, cpos in ipairs(cluster_list) do
            local cnode = raw_get_node(cpos)
            if is_contraption_controller_node(cnode.name) then
                return cpos, cnode
            end
        end
    end

    return nil, nil
end

-- =========================================================
-- CONTRAPTION BLOCK VALIDATION & GATHERING
-- =========================================================
local function is_replaceable_node(name)
    if not name or name == "air" then
        return true
    end
    if name == "ignore" then
        return false
    end
    local def = core.registered_nodes[name]
    if not def then
        return false
    end
    return (def.buildable_to == true)
end

local function can_block_be_moved(pos, name, owner)
    if not name or name == "air" or name == "ignore" then
        return false
    end
    if kinetica.is_belt and kinetica.is_belt(name) then
        return false
    end
    if kinetica.is_crushing_wheel and kinetica.is_crushing_wheel(name) then
        return false
    end

    local def = core.registered_nodes[name]
    if not def then
        return false
    end
    if def.liquidtype and def.liquidtype ~= "none" then
        return false
    end
    if core.get_item_group(name, "unbreakable") > 0 or
       core.get_item_group(name, "immovable") > 0 or
       string.find(name, "bedrock") or
       string.find(name, "barrier") or
       string.find(name, "portal") then
        return false
    end
    if def._mcl_hardness and def._mcl_hardness < 0 then
        return false
    end
    if owner and owner ~= "" and owner ~= "$unknown" and core.is_protected(pos, owner) then
        return false
    end
    return true
end

local function find_registered_machine_def(node_name)
    if not node_name or type(kinetica.registered_machines) ~= "table" then
        return nil
    end
    for prefix, mdef in pairs(kinetica.registered_machines) do
        if node_name == prefix or string.sub(node_name, 1, #prefix + 1) == (prefix .. "_") then
            return mdef
        end
    end
    return nil
end

-- Gathers all blocks & machines attached to the piston (via front contact, Super Glue, Slime/Honey, or secondary pistons).
local function collect_attached_contraption(piston_pos, piston_node)
    piston_node = piston_node or raw_get_node(piston_pos)
    local own_parts  = get_piston_assembly_positions(piston_pos, piston_node)
    local own_hashes = {}
    local visited    = {}
    for _, op in ipairs(own_parts) do
        local hk = core.hash_node_position(op)
        own_hashes[hk] = true
        visited[hk]    = true
    end

    local push_dir          = get_push_dir(piston_node.param2)
    local _, head_pos       = get_front_extension(piston_pos, push_dir, piston_node.param2)
    local front_contact_pos = head_pos
        and {x = head_pos.x + push_dir.x, y = head_pos.y + push_dir.y, z = head_pos.z + push_dir.z}
        or  {x = piston_pos.x + push_dir.x, y = piston_pos.y + push_dir.y, z = piston_pos.z + push_dir.z}

    local cluster = {}
    local queue   = {}

    local function try_add_single(p)
        local rp = vector.round(p)
        local hk = core.hash_node_position(rp)
        if visited[hk] then return end
        local nn = raw_get_node(rp).name
        if is_replaceable_node(nn) then return end
        if not can_block_be_moved(rp, nn, nil) then return end
        visited[hk]         = true
        cluster[#cluster+1] = rp
        queue[#queue+1]     = rp
    end

    local function try_add_with_piston_assembly(p)
        local rp = vector.round(p)
        local hk = core.hash_node_position(rp)
        if visited[hk] then return end
        local rnode = raw_get_node(rp)
        if is_replaceable_node(rnode.name) or not can_block_be_moved(rp, rnode.name, nil) then
            return
        end

        try_add_single(rp)

        local fp_pos, fp_node = nil, nil
        if is_mechanical_piston(rnode.name) then
            fp_pos, fp_node = rp, rnode
        elseif is_piston_pole_node(rnode.name) or is_piston_head_node(rnode.name) then
            fp_pos, fp_node = find_piston_from_pole_or_head(rp, rnode.param2)
        end

        if fp_pos and fp_node and not own_hashes[core.hash_node_position(fp_pos)] then
            for _, apart in ipairs(get_piston_assembly_positions(fp_pos, fp_node)) do
                try_add_single(apart)
            end
            local f_push    = get_push_dir(fp_node.param2)
            local _, f_head = get_front_extension(fp_pos, f_push, fp_node.param2)
            local f_front   = f_head
                and {x = f_head.x + f_push.x, y = f_head.y + f_push.y, z = f_head.z + f_push.z}
                or  {x = fp_pos.x + f_push.x, y = fp_pos.y + f_push.y, z = fp_pos.z + f_push.z}
            try_add_single(f_front)
        end
    end

    try_add_with_piston_assembly(front_contact_pos)

    if kinetica.get_glued_cluster_positions then
        if head_pos then
            for _, gpos in ipairs(kinetica.get_glued_cluster_positions(head_pos)) do
                try_add_with_piston_assembly(gpos)
            end
        end
        for _, gpos in ipairs(kinetica.get_glued_cluster_positions(front_contact_pos)) do
            try_add_with_piston_assembly(gpos)
        end
    end

    local head = 1
    while head <= #queue and #cluster < CONFIG.MAX_CONTRAPTION_BLOCKS do
        local cur   = queue[head]
        head        = head + 1
        local cnode = raw_get_node(cur)
        local cnam  = cnode.name

        -- 1. Pull in all blocks sharing a Super Glue cluster with `cur`
        if kinetica.get_glued_cluster_positions then
            for _, gpos in ipairs(kinetica.get_glued_cluster_positions(cur)) do
                try_add_with_piston_assembly(gpos)
            end
        end

        -- 2. If `cur` is a secondary piston head, include the block touching its front plate
        if is_piston_head_node(cnam) then
            local h_push = get_push_dir(cnode.param2)
            try_add_with_piston_assembly({x = cur.x + h_push.x, y = cur.y + h_push.y, z = cur.z + h_push.z})
        end

        -- 3. Check 6 neighbors for Slime/Honey frames or attached riding machines/controllers
        local cur_is_sticky = is_sticky_contraption_frame(cnam)
        local cur_is_piston = is_mechanical_piston(cnam)

        for _, d in ipairs(ALL_6_DIRS) do
            local np   = {x = cur.x + d.x, y = cur.y + d.y, z = cur.z + d.z}
            local np_h = core.hash_node_position(np)
            if not own_hashes[np_h] and not visited[np_h] then
                local nnode = raw_get_node(np)
                local nnam  = nnode.name
                if not is_replaceable_node(nnam) then
                    local bonded = cur_is_sticky or is_sticky_contraption_frame(nnam)

                    if not bonded then
                        local mdef = find_registered_machine_def(nnam)
                        if mdef and mdef.can_ride_piston and mdef.has_axle_port then
                            local rev = {x = -d.x, y = -d.y, z = -d.z}
                            if mdef.has_axle_port(nnode, rev) then
                                bonded = true
                            end
                        elseif cur_is_piston and is_contraption_controller_node(nnam) then
                            bonded = true
                        end
                    end

                    if bonded then
                        try_add_with_piston_assembly(np)
                    end
                end
            end
        end
    end

    return cluster
end

-- Gathers blocks to physically shift 1 block during an extension or retraction step
local function collect_contraption_blocks(piston_pos, anchor_pos, move_dir, is_pulling, is_sticky, owner)
    local piston_node = raw_get_node(piston_pos)
    local own_parts   = get_piston_assembly_positions(piston_pos, piston_node)
    local own_hashes  = {}
    for _, op in ipairs(own_parts) do
        own_hashes[core.hash_node_position(op)] = true
    end

    local anchor_hash = core.hash_node_position(vector.round(anchor_pos))
    if own_hashes[anchor_hash] then
        return {}, true, nil
    end

    local anchor_node = raw_get_node(anchor_pos)
    if is_replaceable_node(anchor_node.name) then
        return {}, true, nil
    end

    if is_pulling and not is_sticky then
        local head_pos = {
            x = anchor_pos.x - move_dir.x,
            y = anchor_pos.y - move_dir.y,
            z = anchor_pos.z - move_dir.z,
        }
        if not (kinetica.are_positions_glued and kinetica.are_positions_glued(head_pos, anchor_pos)) then
            return {}, true, nil
        end
    end

    if not can_block_be_moved(anchor_pos, anchor_node.name, owner) then
        if not is_pulling then
            return {}, false, "Path obstructed by immovable block"
        else
            return {}, true, nil
        end
    end

    local visited = {}
    for hk, _ in pairs(own_hashes) do
        visited[hk] = true
    end

    local cluster = {}
    local queue   = {}

    local function try_enqueue_single(p)
        local rp = vector.round(p)
        local hk = core.hash_node_position(rp)
        if visited[hk] then
            return true
        end
        local nn = raw_get_node(rp).name
        if is_replaceable_node(nn) then
            return true
        end
        if not can_block_be_moved(rp, nn, owner) then
            return false
        end
        visited[hk]         = true
        cluster[#cluster+1] = rp
        queue[#queue+1]     = rp
        return true
    end

    local function try_enqueue(p)
        local rp = vector.round(p)
        local hk = core.hash_node_position(rp)
        if visited[hk] then
            return true
        end
        if not try_enqueue_single(rp) then
            return false
        end

        local rnode = raw_get_node(rp)
        local foreign_piston_pos, foreign_piston_node = nil, nil
        if is_mechanical_piston(rnode.name) then
            foreign_piston_pos, foreign_piston_node = rp, rnode
        elseif is_piston_pole_node(rnode.name) or is_piston_head_node(rnode.name) then
            foreign_piston_pos, foreign_piston_node = find_piston_from_pole_or_head(rp, rnode.param2)
        end

        if foreign_piston_pos and foreign_piston_node then
            local f_hash = core.hash_node_position(foreign_piston_pos)
            if not own_hashes[f_hash] then
                for _, apart in ipairs(get_piston_assembly_positions(foreign_piston_pos, foreign_piston_node)) do
                    if not try_enqueue_single(apart) then
                        return false
                    end
                end
            end
        end

        return true
    end

    if not try_enqueue(anchor_pos) then
        return {}, false, "Anchor block cannot be moved"
    end

    local head = 1
    while head <= #queue do
        if #cluster > CONFIG.MAX_CONTRAPTION_BLOCKS then
            return {}, false, string.format("Contraption exceeds %d block limit", CONFIG.MAX_CONTRAPTION_BLOCKS)
        end

        local cur   = queue[head]
        head        = head + 1
        local cnode = raw_get_node(cur)
        local cnam  = cnode.name

        if kinetica.get_glued_cluster_positions then
            local glued_list = kinetica.get_glued_cluster_positions(cur)
            for _, gpos in ipairs(glued_list) do
                if not try_enqueue(gpos) then
                    return {}, false, "Glued block is immovable or protected"
                end
            end
        end

        if cnam == HEAD_STICKY then
            local h_push  = get_push_dir(cnode.param2)
            local h_front = {x = cur.x + h_push.x, y = cur.y + h_push.y, z = cur.z + h_push.z}
            if not try_enqueue(h_front) then
                return {}, false, "Block stuck to secondary piston cannot be moved"
            end
        end

        local cur_is_sticky = is_sticky_contraption_frame(cnam)
        for _, d in ipairs(ALL_6_DIRS) do
            local np   = {x = cur.x + d.x, y = cur.y + d.y, z = cur.z + d.z}
            local np_h = core.hash_node_position(np)
            if not own_hashes[np_h] and not visited[np_h] then
                local nnam = raw_get_node(np).name
                if not is_replaceable_node(nnam) then
                    local bonded = cur_is_sticky or is_sticky_contraption_frame(nnam)

                    if not bonded then
                        local mdef = find_registered_machine_def(nnam)
                        if mdef and mdef.can_ride_piston and mdef.has_axle_port then
                            local rev = {x = -d.x, y = -d.y, z = -d.z}
                            if mdef.has_axle_port(raw_get_node(np), rev) then
                                bonded = true
                            end
                        end
                    end

                    if bonded then
                        if not try_enqueue(np) then
                            return {}, false, "Attached block cannot be moved"
                        end
                    end
                end
            end
        end

        local front_pos  = {x = cur.x + move_dir.x, y = cur.y + move_dir.y, z = cur.z + move_dir.z}
        local front_hash = core.hash_node_position(front_pos)
        if own_hashes[front_hash] then
            if front_pos.x == piston_pos.x and front_pos.y == piston_pos.y and front_pos.z == piston_pos.z then
                return {}, false, "Blocked by piston base"
            end
        else
            local front_name = raw_get_node(front_pos).name
            if not is_replaceable_node(front_name) then
                if not try_enqueue(front_pos) then
                    return {}, false, "Destination obstructed by immovable block"
                end
            end
        end
    end

    return cluster, true, nil
end

-- =========================================================
-- CONTRAPTION KU DEMAND CALCULATOR (WITH ANTI-RECURSION GUARD)
-- =========================================================
local function get_own_piston_base_and_pole_ku(rpm, pos, node)
    local base_ku = CONFIG.MIN_BASE_KU
    if rpm and rpm >= CONFIG.MIN_RPM then
        base_ku = math.min(CONFIG.MAX_BASE_KU, math.max(CONFIG.MIN_BASE_KU, math.floor(rpm * CONFIG.BASE_KU_PER_RPM)))
    end

    local total_poles = 0
    if pos then
        node = node or raw_get_node(pos)
        if is_mechanical_piston(node.name) then
            total_poles = get_total_piston_poles(pos, node)
        end
    end
    return base_ku, (total_poles * CONFIG.KU_PER_POLE), total_poles
end

local function compute_attached_contraption_demand_ku(piston_pos, piston_node, rpm)
    if contraption_demand_guard or not piston_pos or not rpm or rpm < CONFIG.MIN_RPM then
        return 0
    end

    contraption_demand_guard = true
    local cluster = collect_attached_contraption(piston_pos, piston_node)
    local total_attached_ku = 0

    for _, bpos in ipairs(cluster) do
        local bnode = raw_get_node(bpos)
        local bname = bnode.name

        if is_mechanical_piston(bname) then
            local child_rpm  = rpm
            local clutched   = false
            local ctrl_pos, ctrl_node = find_controller_for_piston(bpos, bnode, cluster)
            if ctrl_pos and ctrl_node then
                child_rpm, _, clutched = eval_controller_modulation(ctrl_pos, ctrl_node, rpm, 1, 0, 0, false)
            end
            if not clutched and child_rpm >= CONFIG.MIN_RPM then
                local c_base, c_poles = get_own_piston_base_and_pole_ku(child_rpm, bpos, bnode)
                total_attached_ku = total_attached_ku + c_base + c_poles
            end

        elseif kinetica.is_speed_controller and kinetica.is_speed_controller(bname) then
            total_attached_ku = total_attached_ku + 1

        elseif (kinetica.is_gearbox and kinetica.is_gearbox(bname)) or
               (kinetica.is_chain_drive and kinetica.is_chain_drive(bname)) then
            total_attached_ku = total_attached_ku + 1

        else
            local mdef = find_registered_machine_def(bname)
            if mdef and mdef.can_ride_piston and mdef.get_demand_ku then
                local ok, d = pcall(mdef.get_demand_ku, rpm, bpos, bnode)
                if ok and type(d) == "number" and d > 0 then
                    total_attached_ku = total_attached_ku + math.floor(d)
                end
            end
        end
    end

    contraption_demand_guard = false
    return total_attached_ku
end

local function get_piston_demand_ku(rpm, pos, node)
    local base_ku, pole_ku = get_own_piston_base_and_pole_ku(rpm, pos, node)
    local own_ku           = base_ku + pole_ku

    if not pos or contraption_demand_guard then
        return own_ku
    end

    node = node or raw_get_node(pos)
    if not is_mechanical_piston(node.name) then
        return own_ku
    end

    local attached_ku = compute_attached_contraption_demand_ku(pos, node, rpm or CONFIG.MIN_RPM)
    return own_ku + attached_ku
end
kinetica.get_piston_demand_ku = get_piston_demand_ku

local set_piston_idle -- forward declaration
local wake_piston     -- forward declaration

-- Powers riding machines & secondary pistons without ever overwriting a parent network-driven piston!
local function power_and_check_contraption_machines(piston_pos, cluster, move_dir, rpm, spin_dir, avail_ku, supply_ku)
    local now         = math.floor(core.get_gametime())
    local should_wait = false
    local wait_reason = nil
    local parent_hash = core.hash_node_position(piston_pos)

    for _, bpos in ipairs(cluster) do
        local bnode = raw_get_node(bpos)
        if kinetica.is_speed_controller and kinetica.is_speed_controller(bnode.name) then
            eval_controller_modulation(bpos, bnode, rpm, spin_dir, supply_ku, avail_ku, true)
        end
    end

    for _, bpos in ipairs(cluster) do
        local bnode = raw_get_node(bpos)
        local bhash = core.hash_node_position(bpos)

        -- 1. Secondary Mechanical Piston riding on the contraption
        if is_mechanical_piston(bnode.name) and bhash ~= parent_hash and not waking_pistons[bhash] then
            local bmeta = core.get_meta(bpos)
            local is_direct_network_piston = (bmeta:get_int("lit_until") > now) and
                                             (bmeta:get_int("contraption_powered_until") <= now)

            if not is_direct_network_piston then
                local child_rpm  = rpm
                local child_spin = spin_dir ~= 0 and spin_dir or 1
                local clutched   = false
                local ctrl_label = nil

                local ctrl_pos, ctrl_node = find_controller_for_piston(bpos, bnode, cluster)
                if ctrl_pos and ctrl_node then
                    child_rpm, child_spin, clutched, ctrl_label = eval_controller_modulation(
                        ctrl_pos, ctrl_node, child_rpm, child_spin, supply_ku, avail_ku, true
                    )
                end

                bmeta:set_string("contraption_ctrl_info", ctrl_label or "Direct Contraption Power")

                if clutched or child_rpm < CONFIG.MIN_RPM then
                    bmeta:set_int("contraption_powered_until", 0)
                    set_piston_idle(bpos, bnode, string.format(
                        "%s: %s",
                        is_sticky_piston_node(bnode.name) and "Sticky Mechanical Piston" or "Mechanical Piston",
                        ctrl_label or "Clutched (0 RPM)"
                    ))
                else
                    local c_base, c_poles = get_own_piston_base_and_pole_ku(child_rpm, bpos, bnode)
                    local c_demand        = c_base + c_poles
                    bmeta:set_float("rpm", child_rpm)
                    bmeta:set_int("spin_dir", child_spin)
                    bmeta:set_int("rotational_power", math.max(0, avail_ku))
                    bmeta:set_int("network_supply_ku", math.max(c_demand, supply_ku))
                    bmeta:set_int("machine_demand_ku", c_demand)
                    bmeta:set_int("piston_demand_ku", c_demand)
                    bmeta:set_int("solver_demand_ku", c_demand)
                    bmeta:set_int("lit_until", now + 3)
                    bmeta:set_int("contraption_powered_until", now + 3)
                    wake_piston(bpos, bnode, child_rpm, child_spin, c_demand, math.max(0, avail_ku), math.max(c_demand, supply_ku))
                end
            end

        -- 2. Other riding machines (Drills, Saws, etc.)
        elseif not is_mechanical_piston(bnode.name) then
            local mdef = find_registered_machine_def(bnode.name)
            if mdef and mdef.can_ride_piston then
                local m_demand = 32
                if mdef.get_demand_ku then
                    local ok, d = pcall(mdef.get_demand_ku, rpm, bpos, bnode)
                    if ok and type(d) == "number" and d > 0 then
                        m_demand = math.floor(d)
                    end
                end

                local bmeta = core.get_meta(bpos)
                bmeta:set_float("rpm", rpm)
                bmeta:set_int("spin_dir", spin_dir ~= 0 and spin_dir or 1)
                bmeta:set_int("rotational_power", math.max(0, avail_ku))
                bmeta:set_int("network_supply_ku", math.max(m_demand, supply_ku))
                bmeta:set_int("machine_demand_ku", m_demand)
                bmeta:set_int("lit_until", now + 3)

                if mdef.wake then
                    pcall(mdef.wake, bpos, bnode, rpm, spin_dir, m_demand, math.max(0, avail_ku), math.max(m_demand, supply_ku))
                end

                if move_dir and mdef.should_pause_contraption then
                    local ok, pause, reason = pcall(mdef.should_pause_contraption, bpos, bnode, move_dir)
                    if ok and pause then
                        should_wait = true
                        wait_reason = reason or "Waiting for Contraption Machine"
                    end
                end
            end
        end
    end

    return should_wait, wait_reason
end

-- Shuts down attached contraption machines safely with `idling_pistons` recursion protection!
local function idle_attached_contraption_machines(piston_pos, piston_node)
    local cluster = collect_attached_contraption(piston_pos, piston_node)
    for _, bpos in ipairs(cluster) do
        local bhash = core.hash_node_position(bpos)
        if not idling_pistons[bhash] then
            local bnode = raw_get_node(bpos)
            local bmeta = core.get_meta(bpos)
            if is_mechanical_piston(bnode.name) then
                bmeta:set_int("contraption_powered_until", 0)
                bmeta:set_int("lit_until", 0)
                set_piston_idle(bpos, bnode, "Mechanical Piston: Idle")
            else
                local mdef = find_registered_machine_def(bnode.name)
                if mdef and mdef.can_ride_piston and mdef.set_idle then
                    bmeta:set_int("lit_until", 0)
                    pcall(mdef.set_idle, bpos, bnode)
                end
            end
        end
    end
end

local function shift_entities_with_contraption(positions_list, move_dir)
    local seen_objs = {}
    for _, bpos in ipairs(positions_list) do
        local scan_pt = {x = bpos.x + move_dir.x * 0.5, y = bpos.y + 0.5, z = bpos.z + move_dir.z * 0.5}
        for _, obj in ipairs(core.get_objects_inside_radius(scan_pt, 1.15)) do
            if not seen_objs[obj] then
                seen_objs[obj] = true
                local le = obj:get_luaentity()
                local is_static_vis = le and (
                    le.name == "kinetica:super_glue_box" or
                    le.name == "kinetica:super_glue_preview" or
                    le.name == "kinetica:mechanical_drill_bit" or
                    le.name == "kinetica:crushing_wheel_rotor" or
                    le.name == "kinetica:water_wheel_big_mesh"
                )
                if obj:is_player() or (le and not is_static_vis) then
                    local opos = obj:get_pos()
                    if opos then
                        obj:set_pos({
                            x = opos.x + move_dir.x,
                            y = opos.y + move_dir.y + (move_dir.y > 0 and 0.05 or 0),
                            z = opos.z + move_dir.z,
                        })
                    end
                end
            end
        end
    end
end

local function move_contraption_cluster(cluster, move_dir)
    if #cluster == 0 then return true end

    local cluster_set = {}
    for _, p in ipairs(cluster) do
        cluster_set[core.hash_node_position(p)] = true
    end

    for _, p in ipairs(cluster) do
        local dest = {x = p.x + move_dir.x, y = p.y + move_dir.y, z = p.z + move_dir.z}
        local dhk  = core.hash_node_position(dest)
        if not cluster_set[dhk] then
            local dnode = raw_get_node(dest)
            if not is_replaceable_node(dnode.name) then
                return false
            end
        end
    end

    table.sort(cluster, function(a, b)
        local da = a.x * move_dir.x + a.y * move_dir.y + a.z * move_dir.z
        local db = b.x * move_dir.x + b.y * move_dir.y + b.z * move_dir.z
        return da > db
    end)

    local snapshots = {}
    for i, p in ipairs(cluster) do
        local node  = raw_get_node(p)
        local meta  = core.get_meta(p):to_table()
        local timer = core.get_node_timer(p)
        local t_run = timer and timer:is_started() or false
        local t_to  = t_run and timer:get_timeout() or 0
        local t_el  = t_run and timer:get_elapsed() or 0

        snapshots[i] = {
            old_pos   = {x = p.x, y = p.y, z = p.z},
            new_pos   = {x = p.x + move_dir.x, y = p.y + move_dir.y, z = p.z + move_dir.z},
            node      = {name = node.name, param1 = node.param1, param2 = node.param2},
            meta      = meta,
            timer_run = t_run,
            timer_to  = t_to,
            timer_el  = t_el,
        }
    end

    shift_entities_with_contraption(cluster, move_dir)

    local dest_set = {}
    for _, snap in ipairs(snapshots) do
        dest_set[core.hash_node_position(snap.new_pos)] = true
    end

    for _, snap in ipairs(snapshots) do
        local old_hk = core.hash_node_position(snap.old_pos)
        if not dest_set[old_hk] then
            core.remove_node(snap.old_pos)
        end

        core.set_node(snap.new_pos, snap.node)
        if snap.meta then
            core.get_meta(snap.new_pos):from_table(snap.meta)
        end

        local nt = core.get_node_timer(snap.new_pos)
        if nt then
            if snap.timer_run and snap.timer_to > 0 then
                nt:set(snap.timer_to, snap.timer_el)
            elseif (kinetica.is_mechanical_drill and kinetica.is_mechanical_drill(snap.node.name)) or
                   is_mechanical_piston(snap.node.name) then
                nt:start(CONFIG.TICK_INTERVAL)
            end
        end
    end

    if kinetica.shift_glue_boxes_in_volume then
        pcall(kinetica.shift_glue_boxes_in_volume, cluster, move_dir)
    end

    return true
end

-- =========================================================
-- PISTON EXTENSION & RETRACTION
-- =========================================================
local function step_piston_extension(pos, node, meta, rpm, spin_dir, avail_ku, supply_ku, wait_for_drill, wait_msg)
    local push_dir  = get_push_dir(node.param2)
    local is_sticky = is_sticky_piston_node(node.name)
    local owner     = meta:get_string("owner")

    local cur_ext, head_pos = get_front_extension(pos, push_dir, node.param2)
    local rear_poles        = get_rear_pole_count(pos, push_dir, node.param2)
    local max_ext           = math.min(CONFIG.MAX_POLES, cur_ext + rear_poles)

    if rear_poles <= 0 or cur_ext >= CONFIG.MAX_POLES then
        if max_ext == 0 then
            meta:set_string("piston_state", "STATIONARY (0 Poles | Powering Attached Machines)")
        else
            meta:set_string("piston_state", string.format("FULLY EXTENDED (%d/%d Poles)", cur_ext, max_ext))
        end
        return false
    end

    if wait_for_drill then
        meta:set_string("piston_state", wait_msg or "DRILLING OBSTACLE...")
        return true
    end

    local front_pos = head_pos
        and {x = head_pos.x + push_dir.x, y = head_pos.y + push_dir.y, z = head_pos.z + push_dir.z}
        or  {x = pos.x + push_dir.x,      y = pos.y + push_dir.y,      z = pos.z + push_dir.z}

    local cluster, ok, err_reason = collect_contraption_blocks(
        pos, front_pos, push_dir, false, is_sticky, owner
    )

    if not ok then
        meta:set_string("piston_state", "BLOCKED (" .. (err_reason or "Obstructed") .. ")")
        return false
    end

    if #cluster > 0 then
        if not move_contraption_cluster(cluster, push_dir) then
            meta:set_string("piston_state", "BLOCKED (Destination Obstructed)")
            return false
        end
    end

    local tail_pole_pos = {
        x = pos.x - push_dir.x * rear_poles,
        y = pos.y - push_dir.y * rear_poles,
        z = pos.z - push_dir.z * rear_poles,
    }
    if is_piston_pole_node(raw_get_node(tail_pole_pos).name) then
        core.remove_node(tail_pole_pos)
    end

    local head_node_name = is_sticky and HEAD_STICKY or HEAD_STD
    if head_pos then
        core.set_node(head_pos,  {name = POLE_NAME,      param2 = node.param2})
        core.set_node(front_pos, {name = head_node_name, param2 = node.param2})
    else
        core.set_node(front_pos, {name = head_node_name, param2 = node.param2})
    end

    shift_entities_with_contraption({front_pos}, push_dir)
    core.sound_play("default_place_node_hard", {pos = pos, gain = 0.45, max_hear_distance = 16}, true)

    meta:set_int("extension", cur_ext + 1)
    meta:set_string("piston_state", string.format("EXTENDING (%d/%d Poles)", cur_ext + 1, max_ext))
    return true
end

local function step_piston_retraction(pos, node, meta, rpm, spin_dir, avail_ku, supply_ku, wait_for_drill, wait_msg)
    local push_dir  = get_push_dir(node.param2)
    local pull_dir  = {x = -push_dir.x, y = -push_dir.y, z = -push_dir.z}
    local is_sticky = is_sticky_piston_node(node.name)
    local owner     = meta:get_string("owner")

    local cur_ext, head_pos = get_front_extension(pos, push_dir, node.param2)
    local rear_poles        = get_rear_pole_count(pos, push_dir, node.param2)
    local max_ext           = math.min(CONFIG.MAX_POLES, cur_ext + rear_poles)

    if cur_ext <= 0 or not head_pos then
        meta:set_int("extension", 0)
        meta:set_string("piston_state", string.format("RETRACTED (0/%d Poles)", max_ext))
        return false
    end

    if wait_for_drill then
        meta:set_string("piston_state", wait_msg or "DRILLING ON RETRACT...")
        return true
    end

    local attached_pos = {
        x = head_pos.x + push_dir.x,
        y = head_pos.y + push_dir.y,
        z = head_pos.z + push_dir.z,
    }

    local cluster, ok = collect_contraption_blocks(
        pos, attached_pos, pull_dir, true, is_sticky, owner
    )

    local head_node_name = is_sticky and HEAD_STICKY or HEAD_STD
    if cur_ext == 1 then
        core.remove_node(head_pos)
    else
        local prev_pole_pos = {
            x = head_pos.x + pull_dir.x,
            y = head_pos.y + pull_dir.y,
            z = head_pos.z + pull_dir.z,
        }
        core.remove_node(head_pos)
        core.set_node(prev_pole_pos, {name = head_node_name, param2 = node.param2})
    end

    local new_rear_pos = {
        x = pos.x + pull_dir.x * (rear_poles + 1),
        y = pos.y + pull_dir.y * (rear_poles + 1),
        z = pos.z + pull_dir.z * (rear_poles + 1),
    }
    local new_rear_node = raw_get_node(new_rear_pos)
    if is_replaceable_node(new_rear_node.name) then
        core.set_node(new_rear_pos, {name = POLE_NAME, param2 = node.param2})
    else
        core.add_item(pos, POLE_NAME)
    end

    if ok and #cluster > 0 then
        move_contraption_cluster(cluster, pull_dir)
    end

    core.sound_play("default_place_node_hard", {pos = pos, gain = 0.40, pitch = 0.90, max_hear_distance = 16}, true)
    meta:set_int("extension", cur_ext - 1)
    meta:set_string("piston_state", string.format("RETRACTING (%d/%d Poles)", cur_ext - 1, max_ext))
    return true
end

-- =========================================================
-- ENGINEER'S GLASSES TELEMETRY
-- =========================================================
kinetica._glasses_formatters = kinetica._glasses_formatters or {}

local LINE_TOP = "┌─ ENGINEER'S GLASSES ──────────────"
local LINE_NET = "├─ KINETIC NETWORK ─────────────────"
local LINE_DET = "├─ MACHINE DETAILS ─────────────────"
local LINE_BOT = "└───────────────────────────────────"

local function kv_row(label, value)
    return string.format("│  %-11s: %s", label, tostring(value))
end

local function make_progress_bar(used, total)
    local slots = 10
    if not total or total <= 0 then
        return "[" .. string.rep("░", slots) .. "] 0%"
    end
    local ratio  = math.min(1.0, math.max(0.0, (used or 0) / total))
    local filled = math.floor(ratio * slots + 0.5)
    local pct    = math.min(100, math.floor(ratio * 100 + 0.5))
    return string.format("[%s%s] %d%%", string.rep("█", filled), string.rep("░", slots - filled), pct)
end

local function format_piston_glasses_info(pos, node)
    node = node or raw_get_node(pos)
    local meta      = core.get_meta(pos)
    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local now       = math.floor(core.get_gametime())
    local is_active = (supply_ku > 0 and rpm >= CONFIG.MIN_RPM and now < meta:get_int("lit_until"))

    local eff_rpm          = is_active and rpm or CONFIG.MIN_RPM
    local base_ku, pole_ku = get_own_piston_base_and_pole_ku(eff_rpm, pos, node)
    local attached_ku      = is_active and compute_attached_contraption_demand_ku(pos, node, eff_rpm) or 0
    local total_demand_ku  = base_ku + pole_ku + attached_ku
    local used_ku          = (supply_ku > 0) and math.max(0, supply_ku - avail_ku) or 0

    local spin_dir = meta:get_int("spin_dir")
    local inv_sign = CONFIG.INVERT_SPIN_DIRECTION and -1 or 1
    local eff_dir  = spin_dir * inv_sign

    local total_poles, cur_ext, rear_poles = get_total_piston_poles(pos, node)
    local p_state   = meta:get_string("piston_state")
    local ctrl_info = meta:get_string("contraption_ctrl_info")
    if p_state == "" then
        p_state = is_active and "ACTIVE" or "IDLE"
    end

    local mode_str = "IDLE (Power via 4 Side Ports)"
    if is_active then
        mode_str = (eff_dir >= 0) and "PUSHING (CW Rotation)" or "PULLING (CCW Rotation)"
    end

    local title = is_sticky_piston_node(node.name)
        and "Sticky Mechanical Piston"
        or  "Mechanical Piston"

    local lines = {
        LINE_TOP,
        "│  " .. title,
        "│  ● STATE    : " .. p_state,
        LINE_NET,
        kv_row("Speed",      string.format("%.1f RPM  (Min: %d)", is_active and rpm or 0, CONFIG.MIN_RPM)),
        kv_row("Total Load", string.format("-%d KU (Piston: %d | Poles: %d | Attached: %d)", is_active and total_demand_ku or 0, base_ku, pole_ku, attached_ku)),
        kv_row("Net Pool",   string.format("%d / %d KU Avail", is_active and avail_ku or 0, supply_ku)),
        kv_row("Net Stress", make_progress_bar(is_active and used_ku or 0, supply_ku)),
        LINE_DET,
        kv_row("Direction",  mode_str),
        kv_row("Extension",  string.format("%d / %d Poles (Max %d)", cur_ext, total_poles, CONFIG.MAX_POLES)),
        kv_row("Rear Poles", string.format("%d Attached Behind", rear_poles)),
        kv_row("Push Limit", string.format("%d / %d Blocks (by KU)", CONFIG.MAX_CONTRAPTION_BLOCKS, CONFIG.MAX_CONTRAPTION_BLOCKS)),
    }
    if ctrl_info ~= "" then
        lines[#lines + 1] = kv_row("Control", ctrl_info)
    end
    lines[#lines + 1] = LINE_BOT

    return table.concat(lines, "\n")
end

kinetica._glasses_formatters[PISTON_STD]    = format_piston_glasses_info
kinetica._glasses_formatters[PISTON_STICKY] = format_piston_glasses_info

-- =========================================================
-- PISTON WAKE, IDLE, TIER SYNC & TIMER CALLBACKS
-- =========================================================
local function sync_piston_visual_state(pos, force_active, force_rpm, force_spin)
    local node = raw_get_node(pos)
    if not is_mechanical_piston(node.name) then return end

    local meta      = core.get_meta(pos)
    local now       = math.floor(core.get_gametime())
    local rpm       = force_rpm  or meta:get_float("rpm")
    local spin_dir  = force_spin or meta:get_int("spin_dir")
    if spin_dir == 0 then spin_dir = 1 end

    local supply_ku = meta:get_int("network_supply_ku")
    local is_active = force_active
    if is_active == nil then
        is_active = (supply_ku > 0 and rpm >= CONFIG.MIN_RPM and now < meta:get_int("lit_until"))
    end

    local is_sticky   = is_sticky_piston_node(node.name)
    local push_dir    = get_push_dir(node.param2)
    local cur_ext     = get_front_extension(pos, push_dir, node.param2)
    local target_name = get_target_piston_node_name(is_sticky, cur_ext > 0, is_active, rpm, spin_dir)

    if node.name ~= target_name and core.registered_nodes[target_name] then
        raw_swap_node(pos, {name = target_name, param2 = node.param2})
        node.name = target_name
    end

    meta:set_string("glasses_info", format_piston_glasses_info(pos, node))
end

set_piston_idle = function(pos, node, reason_text)
    local hk = core.hash_node_position(pos)
    if idling_pistons[hk] then
        return
    end

    node = node or raw_get_node(pos)
    local meta = core.get_meta(pos)
    local now  = math.floor(core.get_gametime())

    if not reason_text and now < meta:get_int("contraption_powered_until") then
        return
    end

    idling_pistons[hk] = true

    meta:set_float("step_acc", 0)
    meta:set_string("piston_state", "IDLE")

    local is_sticky   = is_sticky_piston_node(node.name)
    local push_dir    = get_push_dir(node.param2)
    local cur_ext     = get_front_extension(pos, push_dir, node.param2)
    local target_idle = get_target_piston_node_name(is_sticky, cur_ext > 0, false, 0, 0)

    if node.name ~= target_idle then
        raw_swap_node(pos, {name = target_idle, param2 = node.param2})
        node.name = target_idle
    end

    idle_attached_contraption_machines(pos, node)

    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
    else
        local total_poles = get_total_piston_poles(pos, node)
        meta:set_string("infotext", reason_text or string.format(
            "%s: Idle (%d/%d Poles | Power Sides, Add Poles to Back)",
            is_sticky and "Sticky Mechanical Piston" or "Mechanical Piston",
            cur_ext, total_poles
        ))
    end
    meta:set_string("glasses_info", format_piston_glasses_info(pos, node))

    idling_pistons[hk] = nil
end

wake_piston = function(pos, node, rpm, spin_dir, demand_ku, avail_ku, supply_ku)
    local hk = core.hash_node_position(pos)
    if waking_pistons[hk] then
        return
    end

    node = node or raw_get_node(pos)
    local meta = core.get_meta(pos)
    local now  = math.floor(core.get_gametime())

    if rpm < CONFIG.MIN_RPM then
        set_piston_idle(pos, node, string.format(
            "Mechanical Piston: Too Slow (%.0f RPM / Min %d RPM required!)",
            rpm, CONFIG.MIN_RPM
        ))
        return
    end

    waking_pistons[hk] = true

    meta:set_float("rpm", rpm)
    meta:set_int("spin_dir", (spin_dir and spin_dir ~= 0) and spin_dir or 1)
    if supply_ku and supply_ku > 0 then
        meta:set_int("network_supply_ku", supply_ku)
    end
    if avail_ku then
        meta:set_int("rotational_power", avail_ku)
    end
    if demand_ku and demand_ku > 0 then
        meta:set_int("solver_demand_ku", demand_ku)
        meta:set_int("machine_demand_ku", demand_ku)
        meta:set_int("piston_demand_ku", demand_ku)
    end
    meta:set_int("lit_until", math.max(meta:get_int("lit_until"), now + 2))

    sync_piston_visual_state(pos, true, rpm, spin_dir)

    local timer = core.get_node_timer(pos)
    if not timer:is_started() then
        timer:start(CONFIG.TICK_INTERVAL)
    end

    waking_pistons[hk] = nil
end

local function piston_timer(pos, elapsed)
    local now  = math.floor(core.get_gametime())
    local meta = core.get_meta(pos)
    local node = raw_get_node(pos)
    local is_riding_piston = (now < meta:get_int("contraption_powered_until"))

    if now >= meta:get_int("lit_until") and not is_riding_piston and kinetica.update_network then
        kinetica.update_network(pos)
        node = raw_get_node(pos)
    end

    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local spin_dir  = meta:get_int("spin_dir")
    if spin_dir == 0 then spin_dir = 1 end

    if supply_ku <= 0 or rpm < CONFIG.MIN_RPM or now >= meta:get_int("lit_until") then
        set_piston_idle(pos, node)
        return false
    end

    local total_demand_ku = get_piston_demand_ku(rpm, pos, node)
    meta:set_int("machine_demand_ku", total_demand_ku)
    meta:set_int("piston_demand_ku",  total_demand_ku)

    if not is_riding_piston then
        local solver_ku = meta:get_int("solver_demand_ku")
        if solver_ku ~= total_demand_ku and kinetica.update_network then
            meta:set_int("solver_demand_ku", total_demand_ku)
            kinetica.update_network(pos)
            node      = raw_get_node(pos)
            rpm       = meta:get_float("rpm")
            supply_ku = meta:get_int("network_supply_ku")
            avail_ku  = meta:get_int("rotational_power")
            if supply_ku <= 0 or rpm < CONFIG.MIN_RPM or now >= meta:get_int("lit_until") then
                set_piston_idle(pos, node, string.format(
                    "Mechanical Piston: OVERSTRESSED! (%d KU needed by Piston + Attached Machines)",
                    total_demand_ku
                ))
                return false
            end
        end

        local unaccounted_ku = math.max(0, total_demand_ku - meta:get_int("solver_demand_ku"))
        if avail_ku - unaccounted_ku < 0 then
            set_piston_idle(pos, node, string.format(
                "Mechanical Piston: OVERSTRESSED! (%d KU needed / %d KU avail)",
                total_demand_ku, avail_ku + meta:get_int("solver_demand_ku")
            ))
            return false
        end
        avail_ku = avail_ku - unaccounted_ku
        meta:set_int("rotational_power", avail_ku)
    end

    if not is_riding_piston then
        local ctrl_pos, ctrl_node = find_controller_for_piston(pos, node, nil)
        if ctrl_pos and ctrl_node then
            local cmeta = core.get_meta(ctrl_pos)
            if cmeta:get_int("sc_out_active") == 0 then
                local mod_rpm, mod_spin, clutched, ctrl_lbl = eval_controller_modulation(
                    ctrl_pos, ctrl_node, rpm, spin_dir, supply_ku, avail_ku, true
                )
                meta:set_string("contraption_ctrl_info", ctrl_lbl or "")
                if clutched or mod_rpm < CONFIG.MIN_RPM then
                    set_piston_idle(pos, node, "Mechanical Piston: " .. (ctrl_lbl or "Clutched"))
                    core.get_node_timer(pos):start(CONFIG.TICK_INTERVAL)
                    return false
                end
                rpm      = mod_rpm
                spin_dir = mod_spin
            end
        else
            meta:set_string("contraption_ctrl_info", "")
        end
    end

    local inv_sign         = CONFIG.INVERT_SPIN_DIRECTION and -1 or 1
    local eff_dir          = spin_dir * inv_sign
    local push_dir         = get_push_dir(node.param2)
    local move_dir         = (eff_dir >= 0) and push_dir or {x = -push_dir.x, y = -push_dir.y, z = -push_dir.z}
    local attached_cluster = collect_attached_contraption(pos, node)
    local wait_for_drill   = false
    local wait_msg         = nil

    if #attached_cluster > 0 then
        wait_for_drill, wait_msg = power_and_check_contraption_machines(
            pos, attached_cluster, move_dir, rpm, spin_dir, avail_ku, supply_ku
        )
    end

    local step_acc = meta:get_float("step_acc") + CONFIG.TICK_INTERVAL
    local req_step = get_step_interval_seconds(rpm)

    if step_acc >= req_step then
        step_acc = 0
        if eff_dir >= 0 then
            step_piston_extension(pos, node, meta, rpm, spin_dir, avail_ku, supply_ku, wait_for_drill, wait_msg)
        else
            step_piston_retraction(pos, node, meta, rpm, spin_dir, avail_ku, supply_ku, wait_for_drill, wait_msg)
        end
    end
    meta:set_float("step_acc", step_acc)

    sync_piston_visual_state(pos, true, rpm, spin_dir)
    node = raw_get_node(pos)

    if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", string.format(
            "%s: %s (-%d KU | %d/%d KU avail | %.0f RPM)",
            is_sticky_piston_node(node.name) and "Sticky Mechanical Piston" or "Mechanical Piston",
            meta:get_string("piston_state"),
            total_demand_ku, avail_ku, supply_ku, rpm
        ))
    end

    meta:set_string("glasses_info", format_piston_glasses_info(pos, node))
    core.get_node_timer(pos):start(CONFIG.TICK_INTERVAL)
    return false
end

local function cleanup_extended_poles_and_head(pos, oldnode)
    local push_dir = get_push_dir(oldnode.param2)
    for i = 1, CONFIG.MAX_POLES + 1 do
        local cpos  = {x = pos.x + push_dir.x * i, y = pos.y + push_dir.y * i, z = pos.z + push_dir.z * i}
        local cnode = raw_get_node(cpos)
        if is_piston_pole_node(cnode.name) and is_same_axis(cnode.param2, oldnode.param2) then
            core.remove_node(cpos)
            core.add_item(cpos, POLE_NAME)
        elseif is_piston_head_node(cnode.name) then
            core.remove_node(cpos)
            core.add_item(cpos, POLE_NAME)
            break
        else
            break
        end
    end
end

-- =========================================================
-- PLACEMENT & EASY REAR POLE EXTENSION
-- =========================================================
local function try_append_pole_behind_piston(piston_pos, piston_node, player, itemstack)
    local pname    = player and player:is_player() and player:get_player_name() or ""
    local back_dir = get_back_dir(piston_node.param2)

    local total_poles, _, rear_poles = get_total_piston_poles(piston_pos, piston_node)
    if total_poles >= CONFIG.MAX_POLES then
        if pname ~= "" then
            core.chat_send_player(pname, string.format("[Kinetica] Maximum limit of %d Piston Poles reached!", CONFIG.MAX_POLES))
        end
        return false
    end

    local target_pos = {
        x = piston_pos.x + back_dir.x * (rear_poles + 1),
        y = piston_pos.y + back_dir.y * (rear_poles + 1),
        z = piston_pos.z + back_dir.z * (rear_poles + 1),
    }
    if pname ~= "" and core.is_protected(target_pos, pname) then
        core.record_protection_violation(target_pos, pname)
        return false
    end

    local tnode = raw_get_node(target_pos)
    if not is_replaceable_node(tnode.name) then
        if pname ~= "" then
            core.chat_send_player(pname, "[Kinetica] Rear pole path is obstructed!")
        end
        return false
    end

    core.set_node(target_pos, {name = POLE_NAME, param2 = piston_node.param2})
    core.sound_play("default_place_node_hard", {pos = target_pos, gain = 0.45, max_hear_distance = 12}, true)

    if pname ~= "" and not core.is_creative_enabled(pname) and itemstack then
        itemstack:take_item(1)
    end

    local meta      = core.get_meta(piston_pos)
    local demand_ku = get_piston_demand_ku(meta:get_float("rpm"), piston_pos, piston_node)
    meta:set_int("machine_demand_ku", demand_ku)
    meta:set_int("piston_demand_ku",  demand_ku)
    meta:set_string("glasses_info", format_piston_glasses_info(piston_pos, piston_node))
    if kinetica.schedule_network_update then
        kinetica.schedule_network_update(piston_pos)
    end
    return true
end

local function place_mechanical_piston(itemstack, placer, pointed_thing)
    if not pointed_thing or pointed_thing.type ~= "node" then
        return itemstack
    end
    local sneaking = placer and placer:is_player() and placer:get_player_control().sneak
    local ldir     = look_to_unit_dir(placer)
    local push_dir = sneaking and ldir or {x = -ldir.x, y = -ldir.y, z = -ldir.z}
    local param2   = dir_to_piston_param2(push_dir)

    local placed_stack, place_pos = core.item_place_node(itemstack, placer, pointed_thing, param2)
    if place_pos then
        local meta  = core.get_meta(place_pos)
        local owner = placer and placer:is_player() and placer:get_player_name() or ""
        meta:set_string("owner", (owner ~= "") and owner or "$unknown")
    end
    return placed_stack
end

local function place_piston_pole(itemstack, placer, pointed_thing)
    if not pointed_thing or pointed_thing.type ~= "node" then
        return itemstack
    end
    local under_pos  = pointed_thing.under
    local under_node = raw_get_node(under_pos)

    if is_mechanical_piston(under_node.name) then
        try_append_pole_behind_piston(under_pos, under_node, placer, itemstack)
        return itemstack
    elseif is_piston_pole_node(under_node.name) then
        local ppos, pnode = find_piston_from_pole_or_head(under_pos, under_node.param2)
        if ppos and pnode then
            try_append_pole_behind_piston(ppos, pnode, placer, itemstack)
            return itemstack
        end
        return core.item_place_node(itemstack, placer, pointed_thing, under_node.param2)
    end

    local diff   = vector.subtract(pointed_thing.above, pointed_thing.under)
    local param2 = dir_to_piston_param2(diff)
    return core.item_place_node(itemstack, placer, pointed_thing, param2)
end

local function on_piston_rightclick(pos, node, clicker, itemstack, pointed_thing)
    if not clicker or not clicker:is_player() or not itemstack or itemstack:is_empty() then
        return itemstack
    end
    local wname = itemstack:get_name()

    if kinetica.is_glue_tool and kinetica.is_glue_tool(wname) then
        return itemstack
    end

    if is_piston_pole_node(wname) then
        try_append_pole_behind_piston(pos, node, clicker, itemstack)
        return itemstack
    end

    if core.registered_nodes[wname] then
        return core.item_place_node(itemstack, clicker, pointed_thing)
    end
    return itemstack
end

-- =========================================================
-- NODE REGISTRATIONS (HEADS, POLES & PISTON TIER FAMILIES)
-- =========================================================
core.register_node(HEAD_STD, {
    description         = "Mechanical Piston Head",
    drawtype            = "nodebox",
    node_box            = PISTON_HEAD_NODEBOX,
    selection_box       = FULL_SELECTION_BOX,
    paramtype           = "light",
    paramtype2          = "facedir",
    sunlight_propagates = true,
    is_ground_content   = false,
    drop                = "",
    tiles = {
        HEAD_FRONT_STD,
        POLE_END_TEX,
        POLE_SIDE_TEX,
        POLE_SIDE_TEX,
        POLE_SIDE_TEX,
        POLE_SIDE_TEX,
    },
    groups = {not_in_creative_inventory = 1},
})

core.register_node(HEAD_STICKY, {
    description         = "Mechanical Sticky Piston Head",
    drawtype            = "nodebox",
    node_box            = PISTON_HEAD_NODEBOX,
    selection_box       = FULL_SELECTION_BOX,
    paramtype           = "light",
    paramtype2          = "facedir",
    sunlight_propagates = true,
    is_ground_content   = false,
    drop                = "",
    tiles = {
        HEAD_FRONT_STK,
        POLE_END_TEX,
        POLE_SIDE_TEX,
        POLE_SIDE_TEX,
        POLE_SIDE_TEX,
        POLE_SIDE_TEX,
    },
    groups = {not_in_creative_inventory = 1},
})

core.register_node(POLE_NAME, {
    description         = string.format("Piston Extension Pole (Attach up to %d behind a Mechanical Piston | +%d KU/Pole)", CONFIG.MAX_POLES, CONFIG.KU_PER_POLE),
    drawtype            = "nodebox",
    node_box            = PISTON_POLE_NODEBOX,
    selection_box       = POLE_SELECTION_BOX,
    collision_box       = POLE_SELECTION_BOX,
    paramtype           = "light",
    paramtype2          = "facedir",
    sunlight_propagates = true,
    is_ground_content   = false,
    tiles = {
        POLE_END_TEX,
        POLE_END_TEX,
        POLE_SIDE_TEX,
        POLE_SIDE_TEX,
        POLE_SIDE_TEX,
        POLE_SIDE_TEX,
    },
    groups                = {handy = 1, axey = 1, pickaxey = 1, piston_pole = 1},
    _mcl_hardness         = 1.5,
    _mcl_blast_resistance = 2.5,
    on_place              = place_piston_pole,
    after_place_node      = function(pos)
        local node = raw_get_node(pos)
        local ppos, pnode = find_piston_from_pole_or_head(pos, node.param2)
        if ppos and pnode then
            local meta      = core.get_meta(ppos)
            local demand_ku = get_piston_demand_ku(meta:get_float("rpm"), ppos, pnode)
            meta:set_int("machine_demand_ku", demand_ku)
            meta:set_int("piston_demand_ku",  demand_ku)
            meta:set_string("glasses_info", format_piston_glasses_info(ppos, pnode))
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(ppos)
            end
        end
    end,
    after_dig_node        = function(pos, oldnode)
        local ppos, pnode = find_piston_from_pole_or_head(pos, oldnode.param2)
        if ppos and pnode then
            local meta      = core.get_meta(ppos)
            local demand_ku = get_piston_demand_ku(meta:get_float("rpm"), ppos, pnode)
            meta:set_int("machine_demand_ku", demand_ku)
            meta:set_int("piston_demand_ku",  demand_ku)
            meta:set_string("glasses_info", format_piston_glasses_info(ppos, pnode))
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(ppos)
            end
        end
    end,
})

core.register_alias("kinetica:piston_extension_pole", POLE_NAME)

local base_groups   = {handy = 1, pickaxey = 1, axey = 1, kinetic_receiver = 1, kinetica_piston = 1}
local active_groups = {handy = 1, pickaxey = 1, axey = 1, kinetic_receiver = 1, kinetica_piston = 1, not_in_creative_inventory = 1}

local function register_piston_variant(node_name, base_name, desc, front_tex, side_tile_a, side_tile_b, nbox, is_base)
    core.register_node(node_name, {
        description           = is_base and desc or "Mechanical Piston",
        drawtype              = "nodebox",
        node_box              = nbox,
        selection_box         = FULL_SELECTION_BOX,
        collision_box         = FULL_SELECTION_BOX,
        paramtype             = "light",
        paramtype2            = "facedir",
        sunlight_propagates   = true,
        is_ground_content     = false,
        drop                  = is_base and nil or base_name,
        tiles = {
            front_tex,            -- +Y local: Front pushing face / throat
            BACK_POLE_SOCKET_TEX, -- -Y local: Back pole socket (NO shaft overlay!)
            side_tile_a,          -- +X local: Static Andesite casing + spinning shaft overlay
            side_tile_b,          -- -X local: Static Andesite casing + spinning shaft overlay
            side_tile_a,          -- +Z local: Static Andesite casing + spinning shaft overlay
            side_tile_b,          -- -Z local: Static Andesite casing + spinning shaft overlay
        },
        groups                = is_base and base_groups or active_groups,
        _mcl_hardness         = 2.5,
        _mcl_blast_resistance = 3.5,
        sounds                = mcl_sounds and mcl_sounds.node_sound_metal_defaults and mcl_sounds.node_sound_metal_defaults() or nil,
        on_place              = is_base and place_mechanical_piston or nil,
        on_rightclick         = on_piston_rightclick,
        on_construct          = is_base and function(pos)
            set_piston_idle(pos, raw_get_node(pos))
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end or nil,
        after_dig_node        = function(pos, oldnode)
            idle_attached_contraption_machines(pos, oldnode)
            cleanup_extended_poles_and_head(pos, oldnode)
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end,
        on_timer              = piston_timer,
    })
end

local function register_piston_family(base_name, desc, head_front_tex)
    local act_cw_canon  = base_name .. "_active_cw"
    local act_ccw_canon = base_name .. "_active_ccw"
    local med_cw        = make_piston_side_anim(false, 0.24)
    local med_ccw       = make_piston_side_anim(true,  0.24)

    register_piston_variant(base_name,           base_name, desc, head_front_tex,       SIDE_PORT_IDLE, SIDE_PORT_IDLE, PISTON_RETRACTED_NODEBOX, true)
    register_piston_variant(base_name .. "_ext", base_name, desc, BACK_POLE_SOCKET_TEX, SIDE_PORT_IDLE, SIDE_PORT_IDLE, PISTON_EXTENDED_NODEBOX,  false)

    register_piston_variant(act_cw_canon,  base_name, desc, head_front_tex, med_cw,  med_ccw, PISTON_RETRACTED_NODEBOX, false)
    register_piston_variant(act_ccw_canon, base_name, desc, head_front_tex, med_ccw, med_cw,  PISTON_RETRACTED_NODEBOX, false)

    for _, tier in ipairs(CONFIG.ANIM_TIERS) do
        local s_cw  = make_piston_side_anim(false, tier.length)
        local s_ccw = make_piston_side_anim(true,  tier.length)

        for _, is_ext in ipairs({false, true}) do
            local ext_tag = is_ext and "_ext" or ""
            local f_tex   = is_ext and BACK_POLE_SOCKET_TEX or head_front_tex
            local nbox    = is_ext and PISTON_EXTENDED_NODEBOX or PISTON_RETRACTED_NODEBOX

            local n_cw  = base_name .. ext_tag .. "_" .. tier.name .. "_cw"
            local n_ccw = base_name .. ext_tag .. "_" .. tier.name .. "_ccw"

            register_piston_variant(n_cw,  base_name, desc, f_tex, s_cw,  s_ccw, nbox, false)
            register_piston_variant(n_ccw, base_name, desc, f_tex, s_ccw, s_cw,  nbox, false)
        end
    end

    if kinetica.register_kinetic_machine then
        kinetica.register_kinetic_machine(base_name, {
            can_ride_piston = true,
            get_demand_ku   = function(rpm, pos, node)
                return get_piston_demand_ku(rpm, pos, node)
            end,
            has_axle_port   = function(node, d)
                local push_dir = get_push_dir(node.param2)
                return (d.x * push_dir.x + d.y * push_dir.y + d.z * push_dir.z) == 0
            end,
            set_idle = set_piston_idle,
            wake     = wake_piston,
        })
    end
end

register_piston_family(
    PISTON_STD,
    string.format("Mechanical Piston (Min %d RPM | Power Sides | Add up to %d Poles to Back)", CONFIG.MIN_RPM, CONFIG.MAX_POLES),
    HEAD_FRONT_STD
)

register_piston_family(
    PISTON_STICKY,
    string.format("Sticky Mechanical Piston (Min %d RPM | Pushes & Pulls Glued Contraptions | Up to %d Poles)", CONFIG.MIN_RPM, CONFIG.MAX_POLES),
    HEAD_FRONT_STK
)

core.register_lbm({
    label             = "Wake kinetica Mechanical Pistons on chunk load",
    name              = "kinetica:wake_pistons_lbm",
    nodenames         = {"group:kinetica_piston"},
    run_at_every_load = true,
    action = function(pos, node)
        sync_piston_visual_state(pos)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TICK_INTERVAL)
        end
    end,
})

local wood_item  = core.registered_items["mcl_core:wood"]          and "mcl_core:wood"          or "group:wood"
local slime_item = core.registered_items["mcl_mobitems:slimeball"] and "mcl_mobitems:slimeball" or "default:mese_crystal_fragment"

core.register_craft({
    output = POLE_NAME .. " 8",
    recipe = {
        {wood_item},
        {"kinetica:andesite_alloy"},
        {wood_item},
    },
})

core.register_craft({
    output = PISTON_STD,
    recipe = {
        {"",               wood_item,                  ""},
        {"kinetica:shaft", "kinetica:andesite_casing", ""},
        {"",               POLE_NAME,                  ""},
    },
})

core.register_craft({
    output = PISTON_STICKY,
    recipe = {
        {slime_item},
        {PISTON_STD},
    },
})