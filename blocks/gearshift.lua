kinetica = kinetica or {}

-- ============================================================================
-- TOP CONFIGURATION SECTION
-- ============================================================================
local CONFIG = {
    FRICTION_FINE_KU = 1,
    MAX_RPM_CAP      = 3072,
    TIMER_INTERVAL   = 0.5,
    PLAY_SHIFT_SOUND = true,
    ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    length = 0.85 },
        { name = "slow",   max_rpm = 15,   length = 0.48 },
        { name = "medium", max_rpm = 63,   length = 0.24 },
        { name = "fast",   max_rpm = 255,  length = 0.11 },
        { name = "hyper",  max_rpm = 1024, length = 0.05 },
        { name = "ultra",  max_rpm = 3072, length = 0.03 },
    },
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    TEX_CASING        = "kinetica_andisite_casing.png",
    TEX_SIDE_SHEET    = "gearshift_side.png",
    TEX_SHAFT_OVERLAY = "kinetica_shaft_connecting_overlay.png",
}

kinetica.GEARSHIFT_FINE_KU = CONFIG.FRICTION_FINE_KU

local GEARSHIFT_IDLE    = "kinetica:gearshift"
local GEARSHIFT_ON_IDLE = "kinetica:gearshift_on_idle"
local raw_get_node      = core.get_node
local raw_swap_node     = core.swap_node

local ADJ_DIRS = {
    {x =  1, y =  0, z =  0},
    {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0},
    {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1},
    {x =  0, y =  0, z = -1},
}

function kinetica.is_gearshift(name)
    if not name then return false end
    return name == GEARSHIFT_IDLE or string.sub(name, 1, #GEARSHIFT_IDLE + 1) == (GEARSHIFT_IDLE .. "_")
end

-- Always pass vector.new(...) into mcl_redstone.get_power so plain tables never fail
local function has_redstone_signal(pos)
    if not pos then return false end
    if mcl_redstone and mcl_redstone.get_power then
        local vpos = vector.new(pos.x, pos.y, pos.z)
        local ok, pwr = pcall(mcl_redstone.get_power, vpos)
        if ok and type(pwr) == "number" and pwr > 0 then
            return true
        end
        for _, d in ipairs(ADJ_DIRS) do
            local np    = vector.new(pos.x + d.x, pos.y + d.y, pos.z + d.z)
            local nname = raw_get_node(np).name
            if not kinetica.is_kinetic_node or not kinetica.is_kinetic_node(nname) then
                local ok2, pwr2 = pcall(mcl_redstone.get_power, np)
                if ok2 and type(pwr2) == "number" and pwr2 > 0 then
                    return true
                end
            end
        end
    end
    if mesecons and mesecons.is_powered and mesecons.is_powered(pos) then
        return true
    end
    return false
end

function kinetica.gearshift_has_redstone(pos)
    if not pos then return false end
    local live = has_redstone_signal(pos)
    core.get_meta(pos):set_int("last_rs", live and 1 or 0)
    return live
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

local function format_gearshift_glasses_info(pos, node)
    local meta      = core.get_meta(pos)
    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local powered   = has_redstone_signal(pos)
    local now       = math.floor(core.get_gametime())
    local is_active = (supply_ku > 0 and rpm > 0 and now < meta:get_int("lit_until"))

    return table.concat({
        "=== KINETIC GLASSES TELEMETRY ===",
        "Block:    Gearshift",
        "State:    " .. (is_active and "ACTIVE" or "IDLE"),
        string.format("Redstone: %s", powered and "POWERED (Reversed)" or "UNPOWERED (Normal)"),
        string.format("Speed:    %.1f RPM", is_active and rpm or 0),
        string.format("Power:    %d / %d KU Avail (-%d KU Fine)", is_active and avail_ku or 0, supply_ku, CONFIG.FRICTION_FINE_KU),
    }, "\n")
end

kinetica._glasses_formatters = kinetica._glasses_formatters or {}
kinetica._glasses_formatters[GEARSHIFT_IDLE] = format_gearshift_glasses_info

local function make_gearshift_end_texture(reverse, anim_length)
    local casing = CONFIG.TEX_CASING
    local shaft  = CONFIG.TEX_SHAFT_OVERLAY
    local f0 = "(" .. casing .. "^(" .. shaft .. "\\^[sheet\\:1x4\\:0,0))"
    local f1 = "(" .. casing .. "^(" .. shaft .. "\\^[sheet\\:1x4\\:0,1))"
    local f2 = "(" .. casing .. "^(" .. shaft .. "\\^[sheet\\:1x4\\:0,2))"
    local f3 = "(" .. casing .. "^(" .. shaft .. "\\^[sheet\\:1x4\\:0,3))"

    local strip
    if reverse then
        strip = "[combine:16x64" ..
            ":0,0="  .. f0 ..
            ":0,16=" .. f3 ..
            ":0,32=" .. f2 ..
            ":0,48=" .. f1
    else
        strip = "[combine:16x64" ..
            ":0,0="  .. f0 ..
            ":0,16=" .. f1 ..
            ":0,32=" .. f2 ..
            ":0,48=" .. f3
    end
    return {
        name = strip,
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length or 0.4,
        },
    }
end

-- 2-Frame Static Side Sheet (1x2): Frame 0 = OFF, Frame 1 = ON
local side_off_tex = CONFIG.TEX_SIDE_SHEET .. "^[sheet:1x2:0,0"
local side_on_tex  = CONFIG.TEX_SIDE_SHEET .. "^[sheet:1x2:0,1"
local idle_end     = CONFIG.TEX_CASING .. "^(" .. CONFIG.TEX_SHAFT_OVERLAY .. "^[sheet:1x4:0,0)"

local function get_canonical_gearshift_param2(dir)
    if kinetica.get_canonical_shaft_param2 then
        return kinetica.get_canonical_shaft_param2(dir)
    end
    if dir.y ~= 0 then
        return 4
    elseif dir.x ~= 0 then
        return 1
    end
    return 0
end

local function update_gearshift_node(pos, reason_text)
    local node = raw_get_node(pos)
    if not kinetica.is_gearshift(node.name) then return end

    local meta      = core.get_meta(pos)
    local powered   = kinetica.gearshift_has_redstone(pos)
    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local spin_dir  = meta:get_int("spin_dir")
    local now       = math.floor(core.get_gametime())
    local is_active = (supply_ku > 0 and rpm > 0 and now < meta:get_int("lit_until"))

    local axis_vec = core.facedir_to_dir(node.param2 or 0) or {x = 0, y = 0, z = 1}
    local canon_p2 = get_canonical_gearshift_param2({
        x = math.abs(axis_vec.x),
        y = math.abs(axis_vec.y),
        z = math.abs(axis_vec.z),
    })

    local target = powered and GEARSHIFT_ON_IDLE or GEARSHIFT_IDLE
    if is_active then
        local dir_tag   = (spin_dir == 1) and "cw" or "ccw"
        local state_tag = powered and "on" or "off"
        local tier      = get_anim_tier_name(rpm)
        local cand      = string.format("kinetica:gearshift_%s_%s_%s", state_tag, tier, dir_tag)
        if core.registered_nodes[cand] then
            target = cand
        end
    end

    if node.name ~= target or node.param2 ~= canon_p2 then
        raw_swap_node(pos, {name = target, param2 = canon_p2})
        node.name   = target
        node.param2 = canon_p2
    end

    meta:set_string("glasses_info", format_gearshift_glasses_info(pos, node))
    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
    elseif reason_text then
        meta:set_string("infotext", reason_text)
    elseif is_active then
        meta:set_string("infotext", string.format(
            "Gearshift%s: ACTIVE (%d KU avail / %d KU total | -%d KU Fine | %s RPM)",
            powered and " [REVERSED]" or "",
            avail_ku,
            supply_ku,
            CONFIG.FRICTION_FINE_KU,
            kinetica.format_rpm and kinetica.format_rpm(rpm) or tostring(rpm)
        ))
    else
        meta:set_string("infotext", string.format(
            "Gearshift%s: Idle (-%d KU Fine)",
            powered and " [REVERSED]" or "",
            CONFIG.FRICTION_FINE_KU
        ))
    end
end
kinetica.update_gearshift_node = update_gearshift_node

local function play_shift_click(pos, meta)
    if not CONFIG.PLAY_SHIFT_SOUND then return end
    local now_us = core.get_us_time and core.get_us_time() or 0
    if now_us - meta:get_int("last_sfx_us") < 150000 then return end
    meta:set_int("last_sfx_us", now_us)
    core.sound_play("default_place_node_metal", {pos = pos, gain = 0.35, max_hear_distance = 12}, true)
end

local function refresh_gearshift_network(pos)
    if kinetica.update_network then
        kinetica.update_network(pos)
        for _, d in ipairs(ADJ_DIRS) do
            local np = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
            local nn = raw_get_node(np)
            if kinetica.is_kinetic_node and kinetica.is_kinetic_node(nn.name) then
                kinetica.update_network(np)
            end
        end
    end
    update_gearshift_node(pos)
end

local function on_gearshift_redstone_change(pos)
    local p = vector.new(pos.x, pos.y, pos.z)
    core.after(0, function()
        if not kinetica.is_gearshift(raw_get_node(p).name) then return end
        local meta      = core.get_meta(p)
        local was_pwred = (meta:get_int("last_rs") == 1)
        local now_pwred = has_redstone_signal(p)
        meta:set_int("last_rs", now_pwred and 1 or 0)
        if was_pwred ~= now_pwred then
            play_shift_click(p, meta)
        end
        refresh_gearshift_network(p)
    end)
end

local function place_gearshift(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then
        return itemstack
    end
    local diff = {
        x = pointed_thing.above.x - pointed_thing.under.x,
        y = pointed_thing.above.y - pointed_thing.under.y,
        z = pointed_thing.above.z - pointed_thing.under.z,
    }
    local param2 = get_canonical_gearshift_param2(diff)
    return core.item_place_node(itemstack, placer, pointed_thing, param2)
end

local base_groups   = {pickaxey = 1, handy = 1, kinetic_receiver = 1, kinetica_gearshift = 1}
local active_groups = {pickaxey = 1, handy = 1, kinetic_receiver = 1, kinetica_gearshift = 1, not_in_creative_inventory = 1}

local function register_gearshift_variant(name, side_tile, back_tile, front_tile, is_base)
    core.register_node(name, {
        description = is_base
            and "Gearshift (Reverses rotational direction when powered by Redstone)"
            or  "Gearshift",
        tiles = {side_tile, side_tile, side_tile, side_tile, back_tile, front_tile},
        paramtype2 = "facedir",
        is_ground_content = false,
        on_place = is_base and place_gearshift or nil,
        drop = is_base and nil or GEARSHIFT_IDLE,
        groups = is_base and base_groups or active_groups,
        _mcl_hardness = 2.5,
        _mcl_blast_resistance = 3.0,
        sounds = mcl_sounds and mcl_sounds.node_sound_metal_defaults and mcl_sounds.node_sound_metal_defaults() or nil,
        _mcl_redstone = {
            connects_to = function()
                return true
            end,
            update = function(pos)
                on_gearshift_redstone_change(pos)
            end,
        },
        on_construct = is_base and function(pos)
            local meta = core.get_meta(pos)
            meta:set_int("last_rs", has_redstone_signal(pos) and 1 or 0)
            update_gearshift_node(pos)
            core.get_node_timer(pos):start(CONFIG.TIMER_INTERVAL)
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end or nil,
        after_dig_node = function(pos)
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end,
        on_timer = function(pos)
            local meta      = core.get_meta(pos)
            local was_pwred = (meta:get_int("last_rs") == 1)
            local now_pwred = has_redstone_signal(pos)
            if was_pwred ~= now_pwred then
                meta:set_int("last_rs", now_pwred and 1 or 0)
                play_shift_click(pos, meta)
                refresh_gearshift_network(pos)
                return true
            end

            local now = math.floor(core.get_gametime())
            if now < meta:get_int("lit_until") then
                update_gearshift_node(pos)
                return true
            end
            if kinetica.update_network then
                kinetica.update_network(pos)
            end
            if math.floor(core.get_gametime()) < meta:get_int("lit_until") then
                update_gearshift_node(pos)
                return true
            end
            if kinetica.set_node_idle then
                kinetica.set_node_idle(pos, raw_get_node(pos))
            end
            return true
        end,
    })
end

-- Idle Variants (Frame 0 = OFF, Frame 1 = ON)
register_gearshift_variant(GEARSHIFT_IDLE,    side_off_tex, idle_end, idle_end, true)
register_gearshift_variant(GEARSHIFT_ON_IDLE, side_on_tex,  idle_end, idle_end, false)

-- Active Tier Variants
for _, tier in ipairs(CONFIG.ANIM_TIERS) do
    local e_cw  = make_gearshift_end_texture(false, tier.length)
    local e_ccw = make_gearshift_end_texture(true,  tier.length)

    -- OFF State (Frame 0 static side, normal straight-through shaft ends)
    register_gearshift_variant(string.format("kinetica:gearshift_off_%s_cw",  tier.name), side_off_tex, e_ccw, e_cw,  false)
    register_gearshift_variant(string.format("kinetica:gearshift_off_%s_ccw", tier.name), side_off_tex, e_cw,  e_ccw, false)

    -- ON State (Frame 1 static side, +axis end reversed relative to -axis end)
    register_gearshift_variant(string.format("kinetica:gearshift_on_%s_cw",   tier.name), side_on_tex,  e_cw,  e_cw,  false)
    register_gearshift_variant(string.format("kinetica:gearshift_on_%s_ccw",  tier.name), side_on_tex,  e_ccw, e_ccw, false)
end

core.register_lbm({
    label             = "Wake kinetica Gearshifts on chunk load",
    name              = "kinetica:wake_gearshifts_lbm",
    nodenames         = {"group:kinetica_gearshift"},
    run_at_every_load = true,
    action = function(pos)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TIMER_INTERVAL)
        end
    end,
})

core.register_craft({
    output = GEARSHIFT_IDLE,
    recipe = {
        {"",               "kinetica:shaft",           ""},
        {"kinetica:shaft", "kinetica:andesite_casing", "mcl_redstone:redstone"},
        {"",               "kinetica:shaft",           ""},
    },
})