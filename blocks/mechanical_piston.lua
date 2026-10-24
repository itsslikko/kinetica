kinetica = kinetica or {}

local CONFIG = {
    MAX_EXTENSION_POLES           = kinetica.MAX_PISTON_POLES or 16,
    MAX_PUSH_BLOCKS               = 32,
    KU_PER_PUSH_BLOCK             = 8,
    EXTEND_ON_CW                  = true,
    MIN_RPM                       = 32,
    KU_PER_RPM                    = 2,
    MIN_KU                        = 32,
    MAX_KU                        = 128,
    MAX_RPM_CAP                   = 1024,
    ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    length = 0.85 },
        { name = "slow",   max_rpm = 15,   length = 0.48 },
        { name = "medium", max_rpm = 63,   length = 0.24 },
        { name = "fast",   max_rpm = 255,  length = 0.11 },
        { name = "hyper",  max_rpm = 1024, length = 0.05 },
    },
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    STEP_SEC_AT_MIN_RPM           = 1.20,
    STEP_SEC_AT_512_RPM           = 0.25,
    TEX_PISTON_SIDE               = "mesecons_piston_bottom.png",
    TEX_PISTON_BACK               = "mesecons_piston_back.png",
    TEX_PISTON_OPEN               = "mesecons_piston_on_front.png",
    TEX_HEAD_NORMAL               = "mesecons_piston_pusher_front.png",
    TEX_HEAD_STICKY               = "mesecons_piston_pusher_front_sticky.png",
    TEX_HEAD_BACK                 = "mesecons_piston_pusher_back.png",
    TEX_HEAD_TOP                  = "mesecons_piston_pusher_top.png",
    TEX_HEAD_BOTTOM               = "mesecons_piston_pusher_bottom.png",
    TEX_HEAD_LEFT                 = "mesecons_piston_pusher_left.png",
    TEX_HEAD_RIGHT                = "mesecons_piston_pusher_right.png",
    TEX_EXTENSION_POLE            = "mesecons_piston_pusher_top.png",
    TEX_SHAFT_OVERLAY             = "kinetica_shaft_connecting_overlay.png",
}

kinetica.PISTON_MIN_RPM = CONFIG.MIN_RPM

function kinetica.get_piston_demand_ku(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then
        return CONFIG.MIN_KU
    end
    return math.min(CONFIG.MAX_KU, math.max(CONFIG.MIN_KU, math.floor(rpm * CONFIG.KU_PER_RPM)))
end

local ALL_DIRS = {
    {x =  1, y =  0, z =  0},
    {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0},
    {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1},
    {x =  0, y =  0, z = -1},
}

local function get_step_interval(rpm)
    if not rpm or rpm <= CONFIG.MIN_RPM then return CONFIG.STEP_SEC_AT_MIN_RPM end
    local t = math.min(1.0, math.max(0.0, (rpm - CONFIG.MIN_RPM) / (512 - CONFIG.MIN_RPM)))
    return CONFIG.STEP_SEC_AT_MIN_RPM - t * (CONFIG.STEP_SEC_AT_MIN_RPM - CONFIG.STEP_SEC_AT_512_RPM)
end

local function get_anim_tier_name(rpm)
    local clamped = math.min(CONFIG.MAX_RPM_CAP, math.max(0, rpm or 0))
    for _, tier in ipairs(CONFIG.ANIM_TIERS) do
        if clamped <= tier.max_rpm then
            return tier.name
        end
    end
    return CONFIG.ANIM_TIERS[#CONFIG.ANIM_TIERS].name
end

local function get_ku_push_limit(avail_ku, demand_ku)
    local total_pool_ku = math.max(0, (avail_ku or 0) + (demand_ku or 0))
    if total_pool_ku <= 0 then
        return 0
    end
    local allowed = math.floor(total_pool_ku / math.max(1, CONFIG.KU_PER_PUSH_BLOCK))
    return math.min(CONFIG.MAX_PUSH_BLOCKS, math.max(1, allowed))
end

if mcl_pistons and mcl_pistons.register_on_move then
    mcl_pistons.register_on_move(function(moved_nodes)
        for _, moved in ipairs(moved_nodes) do
            if kinetica.is_kinetic_node and kinetica.is_kinetic_node(moved.node.name) then
                if kinetica.schedule_network_update then
                    kinetica.schedule_network_update(moved.old_pos)
                    kinetica.schedule_network_update(moved.pos)
                end
            end
        end
    end)
end

local function get_back_dir(param2)
    local d = core.facedir_to_dir(param2 or 0) or {x = 0, y = 0, z = 1}
    return vector.new(d.x, d.y, d.z)
end

local function get_push_dir(param2)
    local b = get_back_dir(param2)
    return vector.new(-b.x, -b.y, -b.z)
end

local function same_axis_dir(d1, d2)
    return math.abs(d1.x) == math.abs(d2.x) and
           math.abs(d1.y) == math.abs(d2.y) and
           math.abs(d1.z) == math.abs(d2.z)
end

function kinetica.piston_has_axle_port(node, d)
    local b = get_back_dir(node.param2)
    return (d.x * b.x + d.y * b.y + d.z * b.z) == 0
end

local function orient_piston_on_place(pos, placer)
    if not placer then return end
    local pitch = placer:get_look_vertical() * (180 / math.pi)
    local node = core.get_node(pos)
    if pitch > 55 then
        core.swap_node(pos, {name = node.name, param2 = core.dir_to_facedir(vector.new(0, -1, 0), true)})
    elseif pitch < -55 then
        core.swap_node(pos, {name = node.name, param2 = core.dir_to_facedir(vector.new(0, 1, 0), true)})
    end
    local meta = core.get_meta(pos)
    local owner = placer.get_player_name and placer:get_player_name() or ""
    meta:set_string("owner", (owner ~= "") and owner or "$unknown")
end

local function should_contraption_pause(piston_pos, piston_node, ext_len, move_dir)
    if not kinetica.get_machine_def then return false, nil end

    local push_dir   = get_push_dir(piston_node.param2)
    local first_pos  = vector.add(piston_pos, vector.multiply(push_dir, ext_len + 1))
    local first_node = core.get_node(first_pos)

    local first_mdef   = kinetica.get_machine_def(first_node.name)
    local first_sticky = kinetica.is_sticky_contraption_frame and kinetica.is_sticky_contraption_frame(first_node.name)
    if not first_mdef and not first_sticky then
        return false, nil
    end

    local visited = {[core.hash_node_position(first_pos)] = true}
    local queue   = {{pos = first_pos, node = first_node}}
    local head    = 1

    while head <= #queue and #queue <= CONFIG.MAX_PUSH_BLOCKS do
        local cur = queue[head]
        head = head + 1

        local mdef = kinetica.get_machine_def(cur.node.name)
        if mdef and mdef.should_pause_contraption then
            local pause, reason = mdef.should_pause_contraption(cur.pos, cur.node, move_dir)
            if pause then
                local mtimer = core.get_node_timer(cur.pos)
                if not mtimer:is_started() then
                    mtimer:start(0.2)
                end
                return true, reason or "Waiting for Contraption Machine"
            end
        end

        local cur_sticky = kinetica.is_sticky_contraption_frame and kinetica.is_sticky_contraption_frame(cur.node.name)
        for _, d in ipairs(ALL_DIRS) do
            local np = {x = cur.pos.x + d.x, y = cur.pos.y + d.y, z = cur.pos.z + d.z}
            local nk = core.hash_node_position(np)
            if not visited[nk] then
                local nn = core.get_node(np)
                local nmdef = kinetica.get_machine_def(nn.name)
                local nsticky = kinetica.is_sticky_contraption_frame and kinetica.is_sticky_contraption_frame(nn.name)

                if (cur_sticky and (nsticky or (nmdef and nmdef.can_ride_piston ~= false))) or
                   (mdef and nmdef and mdef.prefix == nmdef.prefix) then
                    visited[nk] = true
                    queue[#queue + 1] = {pos = np, node = nn}
                end
            end
        end
    end
    return false, nil
end

local function make_piston_side_idle(rot_transform)
    local base = CONFIG.TEX_PISTON_SIDE .. (rot_transform or "")
    return "[combine:16x16:0,0=(" .. base .. "):0,0=" .. CONFIG.TEX_SHAFT_OVERLAY
end

local function make_piston_side_anim(rot_transform, reverse, anim_length)
    local base = CONFIG.TEX_PISTON_SIDE .. (rot_transform or "")
    local ov   = CONFIG.TEX_SHAFT_OVERLAY

    local base_strip = "[combine:16x64" ..
        ":0,0=("  .. base .. ")" ..
        ":0,16=(" .. base .. ")" ..
        ":0,32=(" .. base .. ")" ..
        ":0,48=(" .. base .. ")"

    local ov_strip = ov
    if reverse then
        ov_strip = "[combine:16x64" ..
            ":0,0=("  .. ov .. "\\^[sheet\\:1x4\\:0,0)" ..
            ":0,16=(" .. ov .. "\\^[sheet\\:1x4\\:0,3)" ..
            ":0,32=(" .. ov .. "\\^[sheet\\:1x4\\:0,2)" ..
            ":0,48=(" .. ov .. "\\^[sheet\\:1x4\\:0,1)"
    end

    return {
        name = "(" .. base_strip .. ")^(" .. ov_strip .. ")",
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length or 0.24,
        },
    }
end

local function build_piston_tiles(front_tex, spin_mode, anim_length)
    if spin_mode == "idle" then
        return {
            make_piston_side_idle("^[transformR180"),
            make_piston_side_idle(""),
            make_piston_side_idle("^[transformR90"),
            make_piston_side_idle("^[transformR270"),
            CONFIG.TEX_PISTON_BACK,
            front_tex,
        }
    elseif spin_mode == "cw" then
        return {
            make_piston_side_anim("^[transformR180", false, anim_length),
            make_piston_side_anim("",                true,  anim_length),
            make_piston_side_anim("^[transformR90",  true,  anim_length),
            make_piston_side_anim("^[transformR270", false, anim_length),
            CONFIG.TEX_PISTON_BACK,
            front_tex,
        }
    else
        return {
            make_piston_side_anim("^[transformR180", true,  anim_length),
            make_piston_side_anim("",                false, anim_length),
            make_piston_side_anim("^[transformR90",  false, anim_length),
            make_piston_side_anim("^[transformR270", true,  anim_length),
            CONFIG.TEX_PISTON_BACK,
            front_tex,
        }
    end
end

local pole_nodebox = {
    type = "fixed",
    fixed = {
        {-2/16, -2/16, -8/16,  2/16,  2/16,  8/16},
        {-3/16, -3/16, -8/16,  3/16,  3/16, -6/16},
        {-3/16, -3/16,  6/16,  3/16,  3/16,  8/16},
    },
}

local pt = 4/16
local piston_head_box = {
    type = "fixed",
    fixed = {
        {-2/16, -2/16, -0.5 + pt, 2/16, 2/16,  0.5},
        {-0.5,  -0.5,  -0.5,      0.5,  0.5,  -0.5 + pt},
    },
}

local piston_extended_body_box = {
    type = "fixed",
    fixed = {
        {-0.5,  -0.5,  -0.5 + pt, 0.5,  0.5,  0.5},
        {-2/16, -2/16, -0.5,      2/16, 2/16, -0.5 + pt},
    },
}

local function place_extension_pole(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then return itemstack end
    local under_node = core.get_node(pointed_thing.under)
    local p2 = 0

    if kinetica.is_mechanical_piston(under_node.name) or
       under_node.name == "kinetica:piston_extension_pole" then
        p2 = under_node.param2
    else
        local diff = vector.subtract(pointed_thing.above, pointed_thing.under)
        p2 = core.dir_to_facedir(diff, true)
    end
    return core.item_place_node(itemstack, placer, pointed_thing, p2)
end

core.register_node("kinetica:piston_extension_pole", {
    description = string.format("Piston Extension Pole (Place behind Mechanical Piston - Max %d)", CONFIG.MAX_EXTENSION_POLES),
    drawtype = "nodebox",
    paramtype = "light",
    paramtype2 = "facedir",
    sunlight_propagates = true,
    tiles = {
        CONFIG.TEX_EXTENSION_POLE,
        CONFIG.TEX_EXTENSION_POLE,
        CONFIG.TEX_EXTENSION_POLE .. "^[transformR90",
        CONFIG.TEX_EXTENSION_POLE .. "^[transformR90",
        CONFIG.TEX_HEAD_BACK,
        CONFIG.TEX_HEAD_BACK,
    },
    node_box = pole_nodebox,
    selection_box = pole_nodebox,
    on_place = place_extension_pole,
    groups = {handy = 1, axey = 1, pickaxey = 1, piston_extension_pole = 1},
    _mcl_hardness = 1.5,
    _mcl_blast_resistance = 2.0,
    sounds = mcl_sounds.node_sound_wood_defaults(),
})

local is_cleaning_piston = false

local function cleanup_from_broken_front(broken_pos, oldnode)
    if is_cleaning_piston then return end
    is_cleaning_piston = true

    local back_dir = get_back_dir(oldnode.param2)
    for dist = 1, CONFIG.MAX_EXTENSION_POLES do
        local check_pos = vector.add(broken_pos, vector.multiply(back_dir, dist))
        local check_node = core.get_node(check_pos)
        if kinetica.is_mechanical_piston(check_node.name) then
            local meta = core.get_meta(check_pos)
            local ext_len = meta:get_int("extended_len")
            local push_dir = get_push_dir(check_node.param2)

            for i = 1, ext_len do
                local fpos = vector.add(check_pos, vector.multiply(push_dir, i))
                if not vector.equals(fpos, broken_pos) then
                    local fnode = core.get_node(fpos)
                    if fnode.name == "kinetica:piston_pole_extended" or
                       fnode.name == "kinetica:piston_head" or
                       fnode.name == "kinetica:piston_head_sticky" then
                        core.remove_node(fpos)
                        core.add_item(fpos, "kinetica:piston_extension_pole")
                    end
                end
            end

            meta:set_int("extended_len", 0)
            if kinetica.refresh_piston_node_visual then
                kinetica.refresh_piston_node_visual(check_pos)
            end
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(check_pos)
            end
            break
        end
    end

    is_cleaning_piston = false
end

core.register_node("kinetica:piston_pole_extended", {
    description = "Extended Piston Pole",
    drawtype = "nodebox",
    paramtype = "light",
    paramtype2 = "facedir",
    sunlight_propagates = true,
    tiles = {
        CONFIG.TEX_EXTENSION_POLE,
        CONFIG.TEX_EXTENSION_POLE,
        CONFIG.TEX_EXTENSION_POLE .. "^[transformR90",
        CONFIG.TEX_EXTENSION_POLE .. "^[transformR90",
        CONFIG.TEX_HEAD_BACK,
        CONFIG.TEX_HEAD_BACK,
    },
    node_box = pole_nodebox,
    selection_box = pole_nodebox,
    drop = "kinetica:piston_extension_pole",
    groups = {handy = 1, pickaxey = 1, not_in_creative_inventory = 1, unmovable_by_piston = 1},
    _mcl_hardness = 1.5,
    _mcl_blast_resistance = 2.0,
    sounds = mcl_sounds.node_sound_wood_defaults(),
    after_dig_node = cleanup_from_broken_front,
})

core.register_node("kinetica:piston_head", {
    description = "Mechanical Piston Head",
    drawtype = "nodebox",
    paramtype = "light",
    paramtype2 = "facedir",
    sunlight_propagates = true,
    tiles = {
        CONFIG.TEX_HEAD_TOP,
        CONFIG.TEX_HEAD_BOTTOM,
        CONFIG.TEX_HEAD_LEFT,
        CONFIG.TEX_HEAD_RIGHT,
        CONFIG.TEX_HEAD_BACK,
        CONFIG.TEX_HEAD_NORMAL,
    },
    node_box = piston_head_box,
    selection_box = piston_head_box,
    drop = "kinetica:piston_extension_pole",
    groups = {handy = 1, pickaxey = 1, not_in_creative_inventory = 1, unmovable_by_piston = 1},
    _mcl_hardness = 1.5,
    _mcl_blast_resistance = 2.0,
    sounds = mcl_sounds.node_sound_wood_defaults(),
    after_dig_node = cleanup_from_broken_front,
})

core.register_node("kinetica:piston_head_sticky", {
    description = "Sticky Mechanical Piston Head",
    drawtype = "nodebox",
    paramtype = "light",
    paramtype2 = "facedir",
    sunlight_propagates = true,
    tiles = {
        CONFIG.TEX_HEAD_TOP,
        CONFIG.TEX_HEAD_BOTTOM,
        CONFIG.TEX_HEAD_LEFT,
        CONFIG.TEX_HEAD_RIGHT,
        CONFIG.TEX_HEAD_BACK,
        CONFIG.TEX_HEAD_STICKY,
    },
    node_box = piston_head_box,
    selection_box = piston_head_box,
    drop = "kinetica:piston_extension_pole",
    groups = {handy = 1, pickaxey = 1, not_in_creative_inventory = 1, unmovable_by_piston = 1},
    _mcl_hardness = 1.5,
    _mcl_blast_resistance = 2.0,
    sounds = mcl_sounds.node_sound_wood_defaults(),
    after_dig_node = cleanup_from_broken_front,
})

local function is_sticky_piston_name(name)
    return string.find(name or "", "sticky") ~= nil
end

local function get_piston_node_name(is_sticky, is_extended, spin_mode, rpm)
    local base = is_sticky and "kinetica:mechanical_sticky_piston" or "kinetica:mechanical_piston"
    if spin_mode == "idle" then
        return is_extended and (base .. "_extended") or base
    end

    local tier_name = get_anim_tier_name(rpm)
    local state_tag = is_extended and "_extended_" or "_active_"
    local candidate = base .. state_tag .. tier_name .. "_" .. spin_mode
    if core.registered_nodes[candidate] then
        return candidate
    end
    return base .. state_tag .. spin_mode
end

local function count_rear_poles(pos, back_dir, max_scan)
    local count = 0
    for i = 1, max_scan do
        local rpos = vector.add(pos, vector.multiply(back_dir, i))
        local rnode = core.get_node(rpos)
        if rnode.name == "kinetica:piston_extension_pole" and
           same_axis_dir(back_dir, get_back_dir(rnode.param2)) then
            count = count + 1
        else
            break
        end
    end
    return count
end

kinetica._glasses_formatters = kinetica._glasses_formatters or {}

local function format_piston_glasses_info(pos, node)
    local meta       = core.get_meta(pos)
    local is_sticky  = is_sticky_piston_name(node.name)
    local label      = is_sticky and "Sticky Mechanical Piston" or "Mechanical Piston"
    local rpm        = meta:get_float("rpm")
    local supply_ku  = meta:get_int("network_supply_ku")
    local avail_ku   = meta:get_int("rotational_power")
    local demand_ku  = meta:get_int("piston_demand_ku")
    if demand_ku <= 0 then demand_ku = kinetica.get_piston_demand_ku(rpm) end
    local ext_len    = meta:get_int("extended_len")
    local last_state = meta:get_string("last_status")
    local now        = math.floor(core.get_gametime())

    local is_active  = (supply_ku > 0 and rpm >= CONFIG.MIN_RPM and now < meta:get_int("lit_until"))
    local low_rpm    = (supply_ku > 0 and rpm > 0 and rpm < CONFIG.MIN_RPM and now < meta:get_int("lit_until"))
    local push_limit = is_active and get_ku_push_limit(avail_ku, demand_ku) or 0

    local state_str = "IDLE"
    if is_active then
        state_str = (last_state ~= "") and ("ACTIVE — " .. last_state) or "ACTIVE"
    elseif low_rpm then
        state_str = string.format("TOO SLOW (Needs >= %d RPM)", CONFIG.MIN_RPM)
    end

    return table.concat({
        "=== KINETIC GLASSES TELEMETRY ===",
        "Machine:    " .. label,
        "State:      " .. state_str,
        string.format("Speed:      %.1f RPM (Min %d RPM)", rpm, CONFIG.MIN_RPM),
        string.format("Stress:     -%d KU Load (%d / %d KU Avail)", is_active and demand_ku or 0, avail_ku, supply_ku),
        string.format("Extension:  %d / %d Poles", ext_len, CONFIG.MAX_EXTENSION_POLES),
        string.format("Push/Pull:  Up to %d / %d Blocks (%d KU/blk)", push_limit, CONFIG.MAX_PUSH_BLOCKS, CONFIG.KU_PER_PUSH_BLOCK),
    }, "\n")
end

kinetica._glasses_formatters["kinetica:mechanical_piston"]        = format_piston_glasses_info
kinetica._glasses_formatters["kinetica:mechanical_sticky_piston"] = format_piston_glasses_info

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

function kinetica.refresh_piston_node_visual(pos)
    local node = core.get_node(pos)
    if not kinetica.is_mechanical_piston(node.name) then return end
    local meta        = core.get_meta(pos)
    local is_sticky   = is_sticky_piston_name(node.name)
    local is_extended = meta:get_int("extended_len") > 0
    local rpm         = meta:get_float("rpm")
    local spin        = meta:get_int("spin_dir")

    local spin_mode = "idle"
    if rpm >= CONFIG.MIN_RPM and spin ~= 0 then
        spin_mode = (spin == 1) and "cw" or "ccw"
    end

    local target = get_piston_node_name(is_sticky, is_extended, spin_mode, rpm)
    if node.name ~= target then
        core.swap_node(pos, {name = target, param2 = node.param2})
    end
end

function kinetica.set_piston_idle(pos, node, reason_text)
    node = node or core.get_node(pos)
    local meta      = core.get_meta(pos)
    local is_sticky = is_sticky_piston_name(node.name)
    local ext_len   = meta:get_int("extended_len")
    local label     = is_sticky and "Sticky Mechanical Piston" or "Mechanical Piston"

    local target = get_piston_node_name(is_sticky, ext_len > 0, "idle", 0)
    if node.name ~= target then
        core.swap_node(pos, {name = target, param2 = node.param2})
    end

    meta:set_string("last_status", "Idle")
    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
    else
        meta:set_string("infotext", reason_text or string.format(
            "%s: Idle [Extended %d/%d] (Min %d RPM | Place Extension Poles behind)",
            label, ext_len, CONFIG.MAX_EXTENSION_POLES, CONFIG.MIN_RPM
        ))
    end
    meta:set_string("glasses_info", format_piston_glasses_info(pos, core.get_node(pos)))
end

function kinetica.wake_mechanical_piston(pos, node, rpm, spin_dir, demand_ku, avail_ku, supply_ku)
    if rpm < CONFIG.MIN_RPM then
        local is_sticky = is_sticky_piston_name(node.name)
        local label     = is_sticky and "Sticky Mechanical Piston" or "Mechanical Piston"
        kinetica.set_piston_idle(pos, node, string.format(
            "%s: Too Slow (%.0f RPM / Min %d RPM required!)",
            label, rpm, CONFIG.MIN_RPM
        ))
        return
    end
    kinetica.refresh_piston_node_visual(pos)
    local timer = core.get_node_timer(pos)
    if not timer:is_started() then
        timer:start(get_step_interval(rpm))
    end
end

local function step_extend(pos, node, meta, is_sticky, max_push_blocks)
    local ext_len = meta:get_int("extended_len")
    if ext_len >= CONFIG.MAX_EXTENSION_POLES then
        return false, "Max Extension Reached"
    end

    local back_dir   = get_back_dir(node.param2)
    local push_dir   = get_push_dir(node.param2)
    local rear_poles = count_rear_poles(pos, back_dir, CONFIG.MAX_EXTENSION_POLES)

    if rear_poles <= 0 then
        return false, "No Extension Poles Behind Piston"
    end

    local paused, pause_reason = should_contraption_pause(pos, node, ext_len, push_dir)
    if paused then
        if kinetica.update_network then
            kinetica.update_network(pos)
        end
        return false, pause_reason
    end

    local next_len    = ext_len + 1
    local head_target = vector.add(pos, vector.multiply(push_dir, next_len))
    local owner       = meta:get_string("owner")
    local ppos_vec    = vector.new(pos.x, pos.y, pos.z)

    local tnode = core.get_node(head_target)
    local tdef  = core.registered_nodes[tnode.name]
    local is_front_empty = (tnode.name == "air" or (tdef and tdef.buildable_to))

    if not is_front_empty then
        if max_push_blocks <= 0 then
            return false, "Not Enough KU to Push Blocks"
        end
        if mcl_pistons and mcl_pistons.push then
            local ok = mcl_pistons.push(head_target, push_dir, max_push_blocks, owner, ppos_vec)
            if not ok then
                return false, string.format("Blocked or Too Heavy (KU Push Limit: %d/%d blk)", max_push_blocks, CONFIG.MAX_PUSH_BLOCKS)
            end
        else
            return false, "Blocked in Front"
        end
    end

    local tail_pole_pos = vector.add(pos, vector.multiply(back_dir, rear_poles))
    core.remove_node(tail_pole_pos)

    if ext_len >= 1 then
        local prev_head_pos = vector.add(pos, vector.multiply(push_dir, ext_len))
        core.set_node(prev_head_pos, {name = "kinetica:piston_pole_extended", param2 = node.param2})
    end

    local head_name = is_sticky and "kinetica:piston_head_sticky" or "kinetica:piston_head"
    core.set_node(head_target, {name = head_name, param2 = node.param2})

    meta:set_int("extended_len", next_len)
    kinetica.refresh_piston_node_visual(pos)

    if kinetica.update_network then
        kinetica.update_network(pos)
    end

    core.sound_play("piston_extend", {pos = pos, max_hear_distance = 24, gain = 0.3}, true)
    return true, "Extending"
end

local function step_retract(pos, node, meta, is_sticky, max_push_blocks)
    local ext_len = meta:get_int("extended_len")
    if ext_len <= 0 then
        return false, "Fully Retracted"
    end

    local back_dir = get_back_dir(node.param2)
    local push_dir = get_push_dir(node.param2)

    if is_sticky then
        local paused, pause_reason = should_contraption_pause(pos, node, ext_len, back_dir)
        if paused then
            if kinetica.update_network then
                kinetica.update_network(pos)
            end
            return false, pause_reason
        end
    end

    local rear_poles  = count_rear_poles(pos, back_dir, CONFIG.MAX_EXTENSION_POLES)
    local rear_target = vector.add(pos, vector.multiply(back_dir, rear_poles + 1))
    local owner       = meta:get_string("owner")
    local ppos_vec    = vector.new(pos.x, pos.y, pos.z)

    local rnode = core.get_node(rear_target)
    local rdef  = core.registered_nodes[rnode.name]
    if not (rnode.name == "air" or (rdef and rdef.buildable_to)) then
        if max_push_blocks > 0 and mcl_pistons and mcl_pistons.push then
            local pushed_back = mcl_pistons.push(rear_target, back_dir, max_push_blocks, owner, ppos_vec)
            if not pushed_back then
                return false, "Rear Pole Output Blocked"
            end
        else
            return false, "Rear Pole Output Blocked"
        end
    end

    local cur_head_pos = vector.add(pos, vector.multiply(push_dir, ext_len))
    local new_len      = ext_len - 1

    if new_len >= 1 then
        local new_head_pos = vector.add(pos, vector.multiply(push_dir, new_len))
        local head_name = is_sticky and "kinetica:piston_head_sticky" or "kinetica:piston_head"
        core.set_node(new_head_pos, {name = head_name, param2 = node.param2})
    end

    is_cleaning_piston = true
    core.remove_node(cur_head_pos)
    is_cleaning_piston = false

    if is_sticky and max_push_blocks > 0 and mcl_pistons and mcl_pistons.push then
        local pull_pos  = vector.add(pos, vector.multiply(push_dir, ext_len + 1))
        local pull_node = core.get_node(pull_pos)
        local pull_def  = core.registered_nodes[pull_node.name]
        if pull_def and not pull_def.buildable_to and core.get_item_group(pull_node.name, "unsticky") == 0 then
            mcl_pistons.push(pull_pos, back_dir, max_push_blocks, owner, ppos_vec)
        end
    end

    core.set_node(rear_target, {name = "kinetica:piston_extension_pole", param2 = node.param2})

    meta:set_int("extended_len", new_len)
    kinetica.refresh_piston_node_visual(pos)

    if kinetica.update_network then
        kinetica.update_network(pos)
    end

    core.sound_play("piston_retract", {pos = pos, max_hear_distance = 24, gain = 0.3}, true)
    return true, "Retracting"
end

local function mechanical_piston_timer(pos, elapsed)
    local now  = math.floor(core.get_gametime())
    local meta = core.get_meta(pos)
    local node = core.get_node(pos)

    if now >= meta:get_int("lit_until") and kinetica.update_network then
        kinetica.update_network(pos)
        node = core.get_node(pos)
    end

    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local demand_ku = meta:get_int("piston_demand_ku")
    if demand_ku <= 0 then demand_ku = kinetica.get_piston_demand_ku(rpm) end
    local spin_dir  = meta:get_int("spin_dir")
    local is_sticky = is_sticky_piston_name(node.name)
    local label     = is_sticky and "Sticky Mechanical Piston" or "Mechanical Piston"

    if supply_ku <= 0 or rpm < CONFIG.MIN_RPM or now >= meta:get_int("lit_until") then
        kinetica.set_piston_idle(pos, node)
        return false
    end

    local max_push_blocks = get_ku_push_limit(avail_ku, demand_ku)
    local want_extend     = (spin_dir == 1 and CONFIG.EXTEND_ON_CW) or (spin_dir == -1 and not CONFIG.EXTEND_ON_CW)
    local status          = ""

    if want_extend then
        local _, msg = step_extend(pos, core.get_node(pos), meta, is_sticky, max_push_blocks)
        status = msg
    else
        local _, msg = step_retract(pos, core.get_node(pos), meta, is_sticky, max_push_blocks)
        status = msg
    end

    meta:set_string("last_status", status)
    kinetica.refresh_piston_node_visual(pos)

    local ext_len = meta:get_int("extended_len")
    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
    else
        meta:set_string("infotext", string.format(
            "%s: ACTIVE [%s | Ext %d/%d | Push Limit %d/%d blk] (-%d KU used | %d/%d KU avail | %.0f RPM)",
            label, status, ext_len, CONFIG.MAX_EXTENSION_POLES,
            max_push_blocks, CONFIG.MAX_PUSH_BLOCKS,
            demand_ku, avail_ku, supply_ku, rpm
        ))
    end

    meta:set_string("glasses_info", format_piston_glasses_info(pos, core.get_node(pos)))
    core.get_node_timer(pos):start(get_step_interval(rpm))
    return false
end

local function on_piston_after_dig(pos, oldnode, oldmetadata)
    if not is_cleaning_piston and oldmetadata and oldmetadata.fields then
        local ext_len = tonumber(oldmetadata.fields.extended_len) or 0
        if ext_len > 0 then
            is_cleaning_piston = true
            local push_dir = get_push_dir(oldnode.param2)
            for i = 1, ext_len do
                local fpos  = vector.add(pos, vector.multiply(push_dir, i))
                local fnode = core.get_node(fpos)
                if fnode.name == "kinetica:piston_pole_extended" or
                   fnode.name == "kinetica:piston_head" or
                   fnode.name == "kinetica:piston_head_sticky" then
                    core.remove_node(fpos)
                    core.add_item(fpos, "kinetica:piston_extension_pole")
                end
            end
            is_cleaning_piston = false
        end
    end
    if kinetica.schedule_network_update then
        kinetica.schedule_network_update(pos)
    end
end

local function register_single_piston_node(node_name, base_name, desc, is_ext, front_tex, mode, anim_len, is_creative)
    local groups = {
        handy = 1,
        pickaxey = 1,
        kinetic_receiver = 1,
        kinetica_piston = 1,
        unmovable_by_piston = 1,
    }
    if not is_creative then
        groups.not_in_creative_inventory = 1
    end

    core.register_node(node_name, {
        description = is_creative and desc or "Mechanical Piston",
        drawtype = is_ext and "nodebox" or "normal",
        node_box = is_ext and piston_extended_body_box or nil,
        selection_box = is_ext and piston_extended_body_box or nil,
        paramtype = "light",
        paramtype2 = "facedir",
        is_ground_content = false,
        tiles = build_piston_tiles(front_tex, mode, anim_len),
        drop = base_name,
        groups = groups,
        _mcl_hardness = 2.0,
        _mcl_blast_resistance = 3.0,
        sounds = mcl_sounds.node_sound_stone_defaults(),

        after_place_node = is_creative and function(pos, placer)
            orient_piston_on_place(pos, placer)
            kinetica.set_piston_idle(pos, core.get_node(pos))
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end or nil,

        after_dig_node = on_piston_after_dig,
        on_timer = mechanical_piston_timer,
    })
end

local function register_piston_family(is_sticky)
    local base_name = is_sticky and "kinetica:mechanical_sticky_piston" or "kinetica:mechanical_piston"
    local desc      = is_sticky
        and string.format("Sticky Mechanical Piston (Min %d RPM | Max %d Poles | Push/Pull up to %d Blocks by KU)", CONFIG.MIN_RPM, CONFIG.MAX_EXTENSION_POLES, CONFIG.MAX_PUSH_BLOCKS)
        or  string.format("Mechanical Piston (Min %d RPM | Max %d Poles | Pushes up to %d Blocks by KU)", CONFIG.MIN_RPM, CONFIG.MAX_EXTENSION_POLES, CONFIG.MAX_PUSH_BLOCKS)
    local head_tex  = is_sticky and CONFIG.TEX_HEAD_STICKY or CONFIG.TEX_HEAD_NORMAL

    local base_states = {
        {suffix = "",              ext = false, mode = "idle", len = 0.24, creative = true},
        {suffix = "_active_cw",    ext = false, mode = "cw",   len = 0.24, creative = false},
        {suffix = "_active_ccw",   ext = false, mode = "ccw",  len = 0.24, creative = false},
        {suffix = "_extended",     ext = true,  mode = "idle", len = 0.24, creative = false},
        {suffix = "_extended_cw",  ext = true,  mode = "cw",   len = 0.24, creative = false},
        {suffix = "_extended_ccw", ext = true,  mode = "ccw",  len = 0.24, creative = false},
    }

    for _, st in ipairs(base_states) do
        local front_tex = st.ext and CONFIG.TEX_PISTON_OPEN or head_tex
        register_single_piston_node(base_name .. st.suffix, base_name, desc, st.ext, front_tex, st.mode, st.len, st.creative)
    end

    for _, tier in ipairs(CONFIG.ANIM_TIERS) do
        for _, mode in ipairs({"cw", "ccw"}) do
            register_single_piston_node(
                base_name .. "_active_" .. tier.name .. "_" .. mode,
                base_name, desc, false, head_tex, mode, tier.length, false
            )
            register_single_piston_node(
                base_name .. "_extended_" .. tier.name .. "_" .. mode,
                base_name, desc, true, CONFIG.TEX_PISTON_OPEN, mode, tier.length, false
            )
        end
    end
end

register_piston_family(false)
register_piston_family(true)

core.register_lbm({
    label             = "Wake kinetica Mechanical Pistons on chunk load",
    name              = "kinetica:wake_pistons_lbm",
    nodenames         = {"group:kinetica_piston"},
    run_at_every_load = true,
    action = function(pos, node)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(0.5)
        end
    end,
})

core.register_craft({
    output = "kinetica:piston_extension_pole 8",
    recipe = {
        {"group:wood"},
        {"kinetica:andesite_alloy"},
        {"group:wood"},
    },
})

core.register_craft({
    output = "kinetica:mechanical_piston",
    recipe = {
        {"group:wood",     "group:wood",                 "group:wood"},
        {"mcl_core:cobble", "kinetica:andesite_casing",   "mcl_core:cobble"},
        {"kinetica:shaft",  "kinetica:piston_extension_pole", "kinetica:shaft"},
    },
})

core.register_craft({
    output = "kinetica:mechanical_sticky_piston",
    recipe = {
        {"mcl_mobitems:slimeball"},
        {"kinetica:mechanical_piston"},
    },
})