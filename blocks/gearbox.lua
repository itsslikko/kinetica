kinetica = kinetica or {}

local CONFIG = {
    FRICTION_FINE_KU              = 1,
    TIMER_INTERVAL                = 0.25,
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    TEX_SOLID_FACE                = "kinetica_andisite_casing.png",
    TEX_GEAR_IDLE                 = "kinetica_gear_box_gear_side.png",
    TEX_GEAR_ACTIVE               = "kinetica_gear_box_gear_side_on.png",
    TEX_SHAFT_OVERLAY             = "kinetica_shaft_connecting_overlay.png",
}

kinetica.GEARBOX_FINE_KU = CONFIG.FRICTION_FINE_KU

local HORIZ_IDLE = "kinetica:gearbox"
local VERT_IDLE  = "kinetica:gearbox_vertical"

local function is_vert_gearbox(name)
    return name and (name == VERT_IDLE or string.sub(name, 1, #VERT_IDLE + 1) == (VERT_IDLE .. "_"))
end

local function is_any_gearbox(name)
    if not name then return false end
    return is_vert_gearbox(name) or name == HORIZ_IDLE or string.sub(name, 1, #HORIZ_IDLE + 1) == (HORIZ_IDLE .. "_")
end
kinetica.is_gearbox = is_any_gearbox

local function is_blocked_by_solid_face(pos, node)
    if not kinetica.has_axle_port then return false end
    for _, d in ipairs(kinetica.directions) do
        if not kinetica.has_axle_port(node, d) then
            local npos  = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
            local nnode = core.get_node(npos)
            local rev   = {x = -d.x, y = -d.y, z = -d.z}
            if kinetica.has_axle_port(nnode, rev) then
                local nmeta = core.get_meta(npos)
                if nmeta:get_float("rpm") > 0 or nmeta:get_int("source_active") == 1 then
                    return true
                end
            end
        end
    end
    return false
end

local function format_gearbox_glasses_info(pos, node)
    local meta      = core.get_meta(pos)
    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local now       = math.floor(core.get_gametime())
    local is_vert   = is_vert_gearbox(node.name)
    local is_idle   = (node.name == HORIZ_IDLE or node.name == VERT_IDLE)
    local is_active = (not is_idle) and (supply_ku > 0 and rpm > 0 and now < meta:get_int("lit_until"))
    local blocked   = (not is_active) and is_blocked_by_solid_face(pos, node)

    local state_str = is_active and "ACTIVE" or (blocked and "BLOCKED (Solid Face)" or "IDLE")
    local ports_str = is_vert and "4-Way Vertical (+Y, -Y, Horizontal)" or "4-Way Horizontal (+X, -X, +Z, -Z)"

    local T = kinetica.api.telemetry
    if not T then return "" end

    return table.concat({
        "┌─ ENGINEER'S GLASSES ──────────────",
        "│  Machine: " .. (is_vert and "Vertical Gearbox" or "Gearbox"),
        "│  ● STATE: " .. state_str,
        "├─ KINETIC NETWORK ─────────────────",
        T.kv_row("Speed",  string.format("%.1f RPM", is_active and rpm or 0)),
        T.kv_row("Stress", string.format("-1 KU Fine (%d / %d KU Avail)", is_active and avail_ku or 0, supply_ku)),
        "├─ MACHINE DETAILS ─────────────────",
        T.kv_row("Ports",  ports_str),
        "└───────────────────────────────────",
    }, "\n")
end

if kinetica.api and kinetica.api.telemetry then
    kinetica.api.telemetry.register_formatter(HORIZ_IDLE, format_gearbox_glasses_info)
    kinetica.api.telemetry.register_formatter(VERT_IDLE,  format_gearbox_glasses_info)
end

local function set_gearbox_idle(pos, node, reason_text)
    node = node or core.get_node(pos)
    local is_vert = is_vert_gearbox(node.name)
    local idle_nm = is_vert and VERT_IDLE or HORIZ_IDLE

    if node.name ~= idle_nm then
        core.swap_node(pos, {name = idle_nm, param2 = node.param2})
    end

    local meta = core.get_meta(pos)
    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
    else
        meta:set_string("infotext", reason_text or string.format(
            "%s: Idle (1 KU Fine | Shares KU & RPM on Demand)",
            is_vert and "Vertical Gearbox" or "Gearbox"
        ))
    end
    meta:set_string("glasses_info", format_gearbox_glasses_info(pos, node))
end

local function wake_gearbox(pos, node, rpm, spin_dir, demand_ku, avail_ku, supply_ku)
    node = node or core.get_node(pos)
    local is_vert = is_vert_gearbox(node.name)
    local base_nm = is_vert and VERT_IDLE or HORIZ_IDLE
    
    local tier = "medium"
    if kinetica.api and kinetica.api.registration then
        local clamped = math.min(1024, math.max(0, rpm or 0))
        for _, t in ipairs(kinetica.api.registration.ANIM_TIERS) do
            if clamped <= t.max_rpm then tier = t.name; break end
        end
    end

    local dir_tag = (spin_dir == 1) and "cw" or "ccw"
    if spin_dir == -1 or string.sub(node.name, -4) == "_ccw" then dir_tag = "ccw" end

    local target = base_nm .. "_" .. tier .. "_" .. dir_tag
    if not core.registered_nodes[target] then
        target = base_nm .. "_active_" .. dir_tag
    end

    if node.name ~= target then
        core.swap_node(pos, {name = target, param2 = node.param2})
    end
    
    local meta = core.get_meta(pos)
    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
    else
        meta:set_string("infotext", string.format(
            "%s: ACTIVE (-1 KU fine | %d KU avail / %d KU total | %.0f RPM)",
            is_vert and "Vertical Gearbox" or "Gearbox", avail_ku, supply_ku, rpm
        ))
    end
    meta:set_string("glasses_info", format_gearbox_glasses_info(pos, core.get_node(pos)))
end

local function gearbox_timer(pos, elapsed)
    local now  = math.floor(core.get_gametime())
    local meta = core.get_meta(pos)
    if now < meta:get_int("lit_until") then return true end

    if kinetica.api and kinetica.api.network.update then
        kinetica.api.network.update(pos)
    end

    if math.floor(core.get_gametime()) < meta:get_int("lit_until") then return true end

    local node = core.get_node(pos)
    if is_blocked_by_solid_face(pos, node) then
        set_gearbox_idle(pos, node, "Gearbox: Blocked (Power hitting solid casing!)")
    else
        set_gearbox_idle(pos, node)
    end
    return false
end

-- Texture Generation Helpers
local function make_gear_overlay(reverse, length_mult)
    local gear  = CONFIG.TEX_GEAR_ACTIVE
    local shaft = CONFIG.TEX_SHAFT_OVERLAY
    local gear_strip, shaft_strip

    if reverse then
        gear_strip = "[combine:16x64:0,0=" .. gear .. "\\^[sheet\\:1x3\\:0,0:0,16=" .. gear .. "\\^[sheet\\:1x3\\:0,2:0,32=" .. gear .. "\\^[sheet\\:1x3\\:0,1:0,48=" .. gear .. "\\^[sheet\\:1x3\\:0,2"
        shaft_strip = "[combine:16x64:0,0=" .. shaft .. "\\^[sheet\\:1x4\\:0,0:0,16=" .. shaft .. "\\^[sheet\\:1x4\\:0,3:0,32=" .. shaft .. "\\^[sheet\\:1x4\\:0,2:0,48=" .. shaft .. "\\^[sheet\\:1x4\\:0,1"
    else
        gear_strip = "[combine:16x64:0,0=" .. gear .. "\\^[sheet\\:1x3\\:0,0:0,16=" .. gear .. "\\^[sheet\\:1x3\\:0,1:0,32=" .. gear .. "\\^[sheet\\:1x3\\:0,2:0,48=" .. gear .. "\\^[sheet\\:1x3\\:0,1"
        shaft_strip = shaft
    end

    return {
        name = "(" .. gear_strip .. ")^(" .. shaft_strip .. ")",
        animation = { type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = length_mult or 0.24 },
    }
end

local idle_face = "[combine:16x16:0,0=" .. CONFIG.TEX_GEAR_IDLE .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY

if kinetica.api and kinetica.api.registration then
    local base_groups = {pickaxey = 1, kinetic_receiver = 1, kinetica_gearbox = 1}

    -- 1. Horizontal Gearbox
    kinetica.api.registration.register_rotary_machine(HORIZ_IDLE, {
        description   = "Gearbox (1 KU Fine | Shares KU & RPM on Demand)",
        drawtype      = "nodebox",
        node_box      = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5}},
        paramtype2    = "facedir",
        groups_idle   = base_groups,
        hardness      = 2.5,
        sounds        = mcl_sounds.node_sound_metal_defaults(),
        tiles_idle    = {CONFIG.TEX_SOLID_FACE, CONFIG.TEX_SOLID_FACE, idle_face, idle_face, idle_face, idle_face},
        tiles_active_cw  = {CONFIG.TEX_SOLID_FACE, CONFIG.TEX_SOLID_FACE, make_gear_overlay(true, 0.24), make_gear_overlay(false, 0.24), make_gear_overlay(true, 0.24), make_gear_overlay(false, 0.24)},
        tiles_active_ccw = {CONFIG.TEX_SOLID_FACE, CONFIG.TEX_SOLID_FACE, make_gear_overlay(false, 0.24), make_gear_overlay(true, 0.24), make_gear_overlay(false, 0.24), make_gear_overlay(true, 0.24)},
        
        build_tier_tiles = function(tier, is_ccw)
            local cw_tex  = make_gear_overlay(false, tier.length_mult)
            local ccw_tex = make_gear_overlay(true,  tier.length_mult)
            if is_ccw then
                return {CONFIG.TEX_SOLID_FACE, CONFIG.TEX_SOLID_FACE, cw_tex, ccw_tex, cw_tex, ccw_tex}
            else
                return {CONFIG.TEX_SOLID_FACE, CONFIG.TEX_SOLID_FACE, ccw_tex, cw_tex, ccw_tex, cw_tex}
            end
        end,

        on_construct = function(pos)
            local node = core.get_node(pos)
            if node.param2 ~= 0 then core.swap_node(pos, {name = node.name, param2 = 0}) end
            set_gearbox_idle(pos, node)
        end,
        on_timer      = gearbox_timer,
        get_demand_ku = function(rpm) return 1 end,
        has_axle_port = function(node, d) return (d.y == 0) end,
        set_idle      = set_gearbox_idle,
        wake          = wake_gearbox,
    })

    -- 2. Vertical Gearbox
    kinetica.api.registration.register_rotary_machine(VERT_IDLE, {
        description   = "Vertical Gearbox (1 KU Fine | Up/Down & Front/Back Relay)",
        drawtype      = "nodebox",
        node_box      = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5}},
        paramtype2    = "facedir",
        groups_idle   = base_groups,
        hardness      = 2.5,
        sounds        = mcl_sounds.node_sound_metal_defaults(),
        tiles_idle    = {idle_face, idle_face, CONFIG.TEX_SOLID_FACE, CONFIG.TEX_SOLID_FACE, idle_face, idle_face},
        tiles_active_cw  = {make_gear_overlay(false, 0.24), make_gear_overlay(true, 0.24), CONFIG.TEX_SOLID_FACE, CONFIG.TEX_SOLID_FACE, make_gear_overlay(false, 0.24), make_gear_overlay(true, 0.24)},
        tiles_active_ccw = {make_gear_overlay(true, 0.24), make_gear_overlay(false, 0.24), CONFIG.TEX_SOLID_FACE, CONFIG.TEX_SOLID_FACE, make_gear_overlay(true, 0.24), make_gear_overlay(false, 0.24)},
        
        build_tier_tiles = function(tier, is_ccw)
            local cw_tex  = make_gear_overlay(false, tier.length_mult)
            local ccw_tex = make_gear_overlay(true,  tier.length_mult)
            if is_ccw then
                return {ccw_tex, cw_tex, CONFIG.TEX_SOLID_FACE, CONFIG.TEX_SOLID_FACE, ccw_tex, cw_tex}
            else
                return {cw_tex, ccw_tex, CONFIG.TEX_SOLID_FACE, CONFIG.TEX_SOLID_FACE, cw_tex, ccw_tex}
            end
        end,

        on_construct = function(pos)
            local node = core.get_node(pos)
            local p2 = (node.param2 or 0) % 2
            if node.param2 ~= p2 then core.swap_node(pos, {name = node.name, param2 = p2}) end
            set_gearbox_idle(pos, node)
        end,
        on_timer      = gearbox_timer,
        get_demand_ku = function(rpm) return 1 end,
        has_axle_port = function(node, d) 
            if d.y ~= 0 then return true end
            local fdir = core.facedir_to_dir((node.param2 or 0) % 4) or {x = 0, y = 0, z = 1}
            return (math.abs(d.x) == math.abs(fdir.x) and math.abs(d.z) == math.abs(fdir.z))
        end,
        set_idle      = set_gearbox_idle,
        wake          = wake_gearbox,
    })
end

core.register_lbm({
    label             = "Sync kinetica Gearboxes on chunk load",
    name              = "kinetica:sync_gearboxes_lbm",
    nodenames         = {"group:kinetica_gearbox"},
    run_at_every_load = true,
    action = function(pos)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then timer:start(CONFIG.TIMER_INTERVAL) end
    end,
})

core.register_craft({
    output = "kinetica:gearbox",
    recipe = {
        {"",               "kinetica:shaft",           ""},
        {"kinetica:shaft", "kinetica:andesite_casing", "kinetica:shaft"},
        {"",               "kinetica:shaft",           ""},
    },
})

core.register_craft({ output = "kinetica:gearbox_vertical", recipe = {{"kinetica:gearbox"}} })
core.register_craft({ output = "kinetica:gearbox", recipe = {{"kinetica:gearbox_vertical"}} })