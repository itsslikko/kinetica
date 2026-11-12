-- kinetica/glue.lua
kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

-- ============================================================================
-- TOP CONFIGURATION SECTION
-- ============================================================================
local CONFIG = {
    MAX_GLUE_SPAN         = 32,
    MAX_GLUE_VOLUME       = 2048,
    SUPER_GLUE_USES       = 250,
    MAX_TILE_RENDER_SPAN  = 12,
    BOX_PAD               = 0.015,
    VISIBILITY_CHECK_SEC  = 0.20,
    HOLD_VIEW_DISTANCE    = 48,
    PREVIEW_RAY_DISTANCE  = 7.0,
    PREVIEW_AIR_DISTANCE  = 4.5,
    GLUE_COLOR            = "FF00E677",
    PREVIEW_VALID_COLOR   = "FF00E677",
    PREVIEW_INVALID_COLOR = "#FF5252",
    TEX_CUSTOM_GLUE_ICON  = "kinetica_super_glue.png",
    TEX_CUSTOM_GLUE_BOX   = "kinetica_super_glue_box.png",
    FALLBACK_BASE_TEX     = "kinetica_belt_side.png",
    -- PARENT CONTRAPTION POWER SETTINGS
    ENABLE_GLUE_POWER     = true,
    POWER_TICK_SEC        = 0.20,
    MAX_POLE_TRACE        = 34,
    -- Add future parent blocks here (e.g., "kinetica:windmill_bearing", "kinetica:mechanical_bearing")
    PARENT_SOURCES = {
        "kinetica:mechanical_piston",
        "kinetica:sticky_mechanical_piston",
        "kinetica:piston_head",
        "kinetica:piston_head_sticky",
        "kinetica:piston_pole",
        "kinetica:piston_extension_pole",
    },
}

if kinetica.register_glue_parent_source then
    for _, pref in ipairs(CONFIG.PARENT_SOURCES) do
        kinetica.register_glue_parent_source(pref)
    end
end

local GLUE_TOOL_NAME   = "kinetica:super_glue"
local GLUE_ENTITY_NAME = "kinetica:super_glue_box"
local PREVIEW_ENT_NAME = "kinetica:super_glue_preview"

local player_selections = {}
local preview_entities  = {}

local ALL_6_DIRS = {
    {x =  1, y =  0, z =  0}, {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0}, {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1}, {x =  0, y =  0, z = -1},
}

local function file_exists(filename)
    if not filename or filename == "" then return false end
    local ok, f = pcall(io.open, modpath .. "/textures/" .. filename, "r")
    if ok and f then f:close(); return true end
    return false
end

local function is_glue_tool_name(name)
    return name == GLUE_TOOL_NAME or name == "kinetica:resin_glue"
end
kinetica.is_glue_tool = is_glue_tool_name

local function is_player_holding_glue(player)
    if not player or not player:is_player() then return false end
    local wield = player:get_wielded_item()
    if wield and is_glue_tool_name(wield:get_name()) then return true end
    local inv = player:get_inventory()
    if inv and inv:get_size("offhand") > 0 then
        local off = inv:get_stack("offhand", 1)
        if off and is_glue_tool_name(off:get_name()) then return true end
    end
    return false
end

local function is_any_player_holding_glue_near(pos)
    for _, player in ipairs(core.get_connected_players()) do
        if is_player_holding_glue(player) then
            local ppos = player:get_pos()
            if not pos or not ppos or vector.distance(pos, ppos) <= CONFIG.HOLD_VIEW_DISTANCE then
                return true
            end
        end
    end
    return false
end

-- =========================================================
-- TEXTURE OVERLAY BUILDERS
-- =========================================================
local function get_base_canvas_tex()
    return file_exists(CONFIG.FALLBACK_BASE_TEX) and CONFIG.FALLBACK_BASE_TEX or "default_stone.png"
end

local function build_single_cell_tile(hex_color, fill_alpha, border_alpha)
    if file_exists(CONFIG.TEX_CUSTOM_GLUE_BOX) then return "(" .. CONFIG.TEX_CUSTOM_GLUE_BOX .. "\\^[resize\\:16x16)" end
    local b = get_base_canvas_tex()
    local fill = "(" .. b .. "\\^[resize\\:16x16\\^[colorize\\:" .. hex_color .. "\\:255\\^[opacity\\:" .. tostring(fill_alpha or 55) .. ")"
    local h_bar = "(" .. b .. "\\^[resize\\:16x1\\^[colorize\\:" .. hex_color .. "\\:255\\^[opacity\\:" .. tostring(border_alpha or 210) .. ")"
    local v_bar = "(" .. b .. "\\^[resize\\:1x16\\^[colorize\\:" .. hex_color .. "\\:255\\^[opacity\\:" .. tostring(border_alpha or 210) .. ")"
    return "([combine:16x16:0,0=" .. fill .. ":0,0=" .. h_bar .. ":0,15=" .. h_bar .. ":0,0=" .. v_bar .. ":15,0=" .. v_bar .. ")"
end

local function build_face_texture(blocks_w, blocks_h, hex_color, is_preview)
    local w = math.max(1, math.min(CONFIG.MAX_TILE_RENDER_SPAN, math.floor(blocks_w + 0.5)))
    local h = math.max(1, math.min(CONFIG.MAX_TILE_RENDER_SPAN, math.floor(blocks_h + 0.5)))
    local pw, ph = w * 16, h * 16
    local b = get_base_canvas_tex()

    if file_exists(CONFIG.TEX_CUSTOM_GLUE_BOX) then
        local tile = "(" .. CONFIG.TEX_CUSTOM_GLUE_BOX .. "\\^[resize\\:16x16)"
        local parts = {"[combine:" .. pw .. "x" .. ph}
        for gx = 0, w - 1 do
            for gy = 0, h - 1 do
                parts[#parts + 1] = ":" .. (gx * 16) .. "," .. (gy * 16) .. "=" .. tile
            end
        end
        local combined = table.concat(parts)
        if is_preview and hex_color == CONFIG.PREVIEW_INVALID_COLOR then combined = combined .. "^[colorize:" .. hex_color .. ":160" end
        return combined .. "^[opacity:" .. tostring(is_preview and 195 or 165)
    end

    local fill_op = is_preview and 65 or 48
    local grid_op = is_preview and 115 or 95
    local border_op = is_preview and 240 or 215

    local bg_fill = "(" .. b .. "\\^[resize\\:" .. pw .. "x" .. ph .. "\\^[colorize\\:" .. hex_color .. "\\:220\\^[opacity\\:" .. fill_op .. ")"
    local grid_v = "(" .. b .. "\\^[resize\\:1x" .. ph .. "\\^[colorize\\:" .. hex_color .. "\\:240\\^[opacity\\:" .. grid_op .. ")"
    local grid_h = "(" .. b .. "\\^[resize\\:" .. pw .. "x1\\^[colorize\\:" .. hex_color .. "\\:240\\^[opacity\\:" .. grid_op .. ")"
    local edge_top = "(" .. b .. "\\^[resize\\:" .. pw .. "x2\\^[colorize\\:#ffffff\\:80\\^[colorize\\:" .. hex_color .. "\\:220\\^[opacity\\:" .. border_op .. ")"
    local edge_side = "(" .. b .. "\\^[resize\\:2x" .. ph .. "\\^[colorize\\:#ffffff\\:80\\^[colorize\\:" .. hex_color .. "\\:220\\^[opacity\\:" .. border_op .. ")"

    local parts = {"[combine:" .. pw .. "x" .. ph, ":0,0=" .. bg_fill}
    for gx = 1, w - 1 do parts[#parts + 1] = ":" .. (gx * 16) .. ",0=" .. grid_v end
    for gy = 1, h - 1 do parts[#parts + 1] = ":0," .. (gy * 16) .. "=" .. grid_h end
    parts[#parts + 1] = ":0,0=" .. edge_top
    parts[#parts + 1] = ":0," .. (ph - 2) .. "=" .. edge_top
    parts[#parts + 1] = ":0,0=" .. edge_side
    parts[#parts + 1] = ":" .. (pw - 2) .. ",0=" .. edge_side
    return table.concat(parts)
end

local function build_aligned_box_textures(minp, maxp, hex_color, is_preview)
    local bw, bh, bd = (maxp.x - minp.x) + 1, (maxp.y - minp.y) + 1, (maxp.z - minp.z) + 1
    local tex_y = build_face_texture(bw, bd, hex_color, is_preview)
    local tex_x = build_face_texture(bd, bh, hex_color, is_preview)
    local tex_z = build_face_texture(bw, bh, hex_color, is_preview)
    return {tex_y, tex_y, tex_x, tex_x, tex_z, tex_z}
end

local function build_super_glue_icon()
    if file_exists(CONFIG.TEX_CUSTOM_GLUE_ICON) then return CONFIG.TEX_CUSTOM_GLUE_ICON end
    local b = get_base_canvas_tex()
    local function rect(w, h, hex) return "(" .. b .. "\\^[resize\\:" .. w .. "x" .. h .. "\\^[sheet\\:1x1\\:0,0\\^[colorize\\:" .. hex .. "\\:240)" end
    return "[combine:16x16:7,1=" .. rect(2, 2, "#E0E6ED") .. ":9,1=" .. rect(2, 2, "#00E676") .. ":6,3=" .. rect(4, 2, "#B0BAC5") .. ":4,5=" .. rect(8, 2, "#263238") .. ":4,7=" .. rect(8, 7, "#00C853") .. ":4,9=" .. rect(8, 3, "#ECEFF1") .. ":6,10=" .. rect(4, 1, "#00E676") .. ":4,14=" .. rect(8, 2, "#78909C")
end

-- =========================================================
-- MATH HELPERS
-- =========================================================
local function bounds_equal(a_min, a_max, b_min, b_max)
    return a_min.x == b_min.x and a_min.y == b_min.y and a_min.z == b_min.z and
           a_max.x == b_max.x and a_max.y == b_max.y and a_max.z == b_max.z
end

local function compute_glue_bounds(p1, p2)
    local minp = {x = math.min(p1.x, p2.x), y = math.min(p1.y, p2.y), z = math.min(p1.z, p2.z)}
    local maxp = {x = math.max(p1.x, p2.x), y = math.max(p1.y, p2.y), z = math.max(p1.z, p2.z)}
    local sx, sy, sz = (maxp.x - minp.x) + 1, (maxp.y - minp.y) + 1, (maxp.z - minp.z) + 1
    local volume = sx * sy * sz
    local center = {x = (minp.x + maxp.x) * 0.5, y = (minp.y + maxp.y) * 0.5, z = (minp.z + maxp.z) * 0.5}
    local visual_size = {x = sx + CONFIG.BOX_PAD, y = sy + CONFIG.BOX_PAD, z = sz + CONFIG.BOX_PAD}
    
    if sx > CONFIG.MAX_GLUE_SPAN or sy > CONFIG.MAX_GLUE_SPAN or sz > CONFIG.MAX_GLUE_SPAN then
        return minp, maxp, center, visual_size, volume, false, string.format("Span too wide (%dx%dx%d; max is %d blocks)!", sx, sy, sz, CONFIG.MAX_GLUE_SPAN)
    end
    if volume > CONFIG.MAX_GLUE_VOLUME then
        return minp, maxp, center, visual_size, volume, false, string.format("Volume too large (%d blocks; max is %d)!", volume, CONFIG.MAX_GLUE_VOLUME)
    end
    return minp, maxp, center, visual_size, volume, true, nil
end

local function has_any_solid_block_in_bounds(minp, maxp)
    if not minp or not maxp then return false end
    for x = minp.x, maxp.x do
        for y = minp.y, maxp.y do
            for z = minp.z, maxp.z do
                local nn = core.get_node({x = x, y = y, z = z}).name
                if nn ~= "air" then
                    if nn == "ignore" then return true end
                    local def = core.registered_nodes[nn]
                    if not def or not def.liquidtype or def.liquidtype == "none" then return true end
                end
            end
        end
    end
    return false
end

local function ray_intersects_glue_box(origin, dir, max_dist, minp, maxp)
    local bmin = {x = minp.x - 0.51, y = minp.y - 0.51, z = minp.z - 0.51}
    local bmax = {x = maxp.x + 0.51, y = maxp.y + 0.51, z = maxp.z + 0.51}
    local tmin, tmax = 0.0, max_dist

    for _, axis in ipairs({"x", "y", "z"}) do
        local o, d = origin[axis], dir[axis]
        if math.abs(d) < 1e-6 then
            if o < bmin[axis] or o > bmax[axis] then return nil end
        else
            local t1, t2 = (bmin[axis] - o) / d, (bmax[axis] - o) / d
            if t1 > t2 then t1, t2 = t2, t1 end
            if t1 > tmin then tmin = t1 end
            if t2 < tmax then tmax = t2 end
            if tmin > tmax then return nil end
        end
    end
    return tmin
end

local function find_raycasted_glue_box(player)
    local eye_pos = vector.add(player:get_pos(), {x = 0, y = (player:get_properties().eye_height or 1.62), z = 0})
    local look_dir, best_box, best_dist = player:get_look_dir(), nil, math.huge

    if kinetica.api and kinetica.api.contraptions and kinetica.api.contraptions.active_glue_boxes then
        for self, _ in pairs(kinetica.api.contraptions.active_glue_boxes) do
            if self.object and self.object:get_luaentity() and self.minp and self.maxp then
                local hit_t = ray_intersects_glue_box(eye_pos, look_dir, CONFIG.PREVIEW_RAY_DISTANCE, self.minp, self.maxp)
                if hit_t and hit_t < best_dist then
                    best_dist = hit_t
                    best_box  = self
                end
            end
        end
    end
    return best_box
end

local function spawn_glue_particles(minp, maxp, hex_color, burst_count)
    local tex = build_single_cell_tile(hex_color or CONFIG.GLUE_COLOR, 180, 255)
    core.add_particlespawner({
        amount = burst_count or 20, time = 0.15,
        minpos = {x = minp.x - 0.45, y = minp.y - 0.45, z = minp.z - 0.45},
        maxpos = {x = maxp.x + 0.45, y = maxp.y + 0.45, z = maxp.z + 0.45},
        minvel = {x = -0.5, y = 0.2, z = -0.5}, maxvel = {x = 0.5, y = 0.9, z = 0.5},
        minexptime = 0.25, maxexptime = 0.55, minsize = 1.2, maxsize = 2.2, glow = 12, texture = tex,
    })
end

local function play_glue_sound(pos, pitch)
    core.sound_play("default_place_node_hard", {pos = pos, gain = 0.55, pitch = pitch or 1.15, max_hear_distance = 16}, true)
end

-- =========================================================
-- ENTITY & PARENT POWER LOGIC
-- =========================================================
local function apply_glue_box_visuals(self)
    if not self.minp or not self.maxp then return end
    local minp, maxp, center, visual_size = compute_glue_bounds(self.minp, self.maxp)
    self.minp, self.maxp = minp, maxp

    local show_now = is_any_player_holding_glue_near(center)
    self._shown = show_now

    self.object:set_pos(center)
    self.object:set_properties({
        visual = "cube", visual_size = visual_size,
        textures = build_aligned_box_textures(minp, maxp, CONFIG.GLUE_COLOR, false),
        use_texture_alpha = true, backface_culling = false, shaded = false, glow = 8,
        is_visible = show_now, pointable = false, collisionbox = {0, 0, 0, 0, 0, 0}, selectionbox = {0, 0, 0, 0, 0, 0},
    })
end

local function get_first_solid(minp, maxp)
    if not minp or not maxp then return nil, nil end
    for x = minp.x, maxp.x do
        for y = minp.y, maxp.y do
            for z = minp.z, maxp.z do
                local name = core.get_node({x = x, y = y, z = z}).name
                if name ~= "air" and name ~= "ignore" then
                    return {x = x, y = y, z = z}, name
                end
            end
        end
    end
    return nil, nil
end

local function find_machine_def_for_glue(node_name)
    if kinetica.get_machine_def then
        return kinetica.get_machine_def(node_name)
    end
    if not node_name or type(kinetica.registered_machines) ~= "table" then return nil end
    for prefix, mdef in pairs(kinetica.registered_machines) do
        if node_name == prefix or string.sub(node_name, 1, #prefix + 1) == (prefix .. "_") then
            if #prefix > 0 then return mdef end
        end
    end
    return nil
end

local function is_registered_parent_node(node_name)
    if not node_name or node_name == "air" or node_name == "ignore" then return false end
    local list = (kinetica.glue_parent_prefixes) or CONFIG.PARENT_SOURCES
    for _, prefix in ipairs(list) do
        if node_name == prefix or string.sub(node_name, 1, #prefix + 1) == (prefix .. "_") then
            return true
        end
    end
    return false
end

local function resolve_parent_controller_pos(cand_pos, cand_node)
    local cname = cand_node.name
    if kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(cname) then
        return cand_pos, cand_node
    end

    if (kinetica.is_piston_pole_or_head and kinetica.is_piston_pole_or_head(cname)) or
       string.find(cname, "piston_head") or string.find(cname, "piston_pole") then
        local push_dir = kinetica.get_piston_push_dir and kinetica.get_piston_push_dir(cand_node.param2)
        if not push_dir then
            local axisdir = math.floor(((cand_node.param2 or 0) % 24) / 4)
            local map = {
                [0] = {x = 0, y = 1, z = 0}, [1] = {x = 0, y = 0, z = 1},
                [2] = {x = 0, y = 0, z = -1}, [3] = {x = 1, y = 0, z = 0},
                [4] = {x = -1, y = 0, z = 0}, [5] = {x = 0, y = -1, z = 0},
            }
            push_dir = map[axisdir] or {x = 0, y = 1, z = 0}
        end

        for _, sign in ipairs({-1, 1}) do
            local step = {x = push_dir.x * sign, y = push_dir.y * sign, z = push_dir.z * sign}
            for i = 1, (CONFIG.MAX_POLE_TRACE or 34) do
                local cpos  = {x = cand_pos.x + step.x * i, y = cand_pos.y + step.y * i, z = cand_pos.z + step.z * i}
                local cnode = core.get_node(cpos)
                if kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(cnode.name) then
                    return cpos, cnode
                elseif not ((kinetica.is_piston_pole_or_head and kinetica.is_piston_pole_or_head(cnode.name)) or string.find(cnode.name, "piston_pole")) then
                    break
                end
            end
        end
        return nil, nil
    end

    return cand_pos, cand_node
end

local function read_parent_power_state(parent_pos, parent_node)
    local pmeta = core.get_meta(parent_pos)
    local now   = math.floor(core.get_gametime())

    local lit_ok   = (pmeta:get_int("lit_until") > now) or (pmeta:get_int("contraption_powered_until") > now) or (pmeta:get_int("source_active") == 1)
    local over     = (pmeta:get_int("network_overstressed") == 1)
    local rpm      = pmeta:get_float("rpm")
    local supply   = pmeta:get_int("network_supply_ku")
    local avail    = pmeta:get_int("rotational_power")
    local spin_dir = pmeta:get_int("spin_dir")

    if rpm <= 0 and pmeta:get_int("source_active") == 1 then
        rpm      = pmeta:get_float("source_rpm")
        supply   = pmeta:get_int("source_ku")
        avail    = supply
        spin_dir = pmeta:get_int("source_spin")
    end
    if spin_dir == 0 then spin_dir = 1 end

    if not lit_ok or over or rpm < 1 or supply <= 0 then
        return false, 0, 1, 0, 0
    end
    return true, rpm, spin_dir, supply, avail
end

local function get_machine_ku_demand(bpos, bnode, rpm)
    local bname = bnode.name
    local mdef  = find_machine_def_for_glue(bname)
    if mdef and mdef.get_demand_ku then
        local ok, d = pcall(mdef.get_demand_ku, rpm, bpos, bnode)
        if ok and type(d) == "number" and d > 0 then
            return math.floor(d)
        end
    end
    if kinetica.is_water_pump and kinetica.is_water_pump(bname) then
        return kinetica.get_pump_demand_ku and kinetica.get_pump_demand_ku(rpm) or 16
    end
    return 16
end

local function set_glued_machine_idle(bpos, bnode)
    local bname = bnode.name
    local meta  = core.get_meta(bpos)
    if meta:get_int("glue_powered") == 0 and meta:get_float("rpm") == 0 then
        return
    end

    meta:set_int("glue_powered", 0)
    meta:set_float("rpm", 0)
    meta:set_int("network_supply_ku", 0)
    meta:set_int("rotational_power", 0)
    meta:set_int("lit_until", 0)
    meta:set_int("contraption_powered_until", 0)
    meta:set_int("source_active", 0)
    meta:set_float("source_rpm", 0)
    meta:set_int("source_ku", 0)

    local mdef = find_machine_def_for_glue(bname)
    if mdef and mdef.set_idle then
        pcall(mdef.set_idle, bpos, bnode)
    elseif kinetica.set_node_idle then
        pcall(kinetica.set_node_idle, bpos, bnode)
    end
end

local function clear_parent_glue_load(self)
    if self and self._last_parent_pos then
        local pmeta = core.get_meta(self._last_parent_pos)
        if pmeta:get_int("glue_attached_ku") ~= 0 then
            pmeta:set_int("glue_attached_ku", 0)
            if kinetica.api and kinetica.api.network and kinetica.api.network.schedule_update then
                kinetica.api.network.schedule_update(self._last_parent_pos)
            end
        end
        self._last_parent_pos = nil
        self._last_parent_ku  = 0
    end
end

local function update_glue_box_parent_power(self)
    if not CONFIG.ENABLE_GLUE_POWER or not self.minp or not self.maxp then return end

    local now = math.floor(core.get_gametime())

    local anchor = self.anchor_pos or get_first_solid(self.minp, self.maxp)
    local cluster_positions = {}

    if anchor and kinetica.api and kinetica.api.contraptions and kinetica.api.contraptions.get_glued_cluster_positions then
        cluster_positions = kinetica.api.contraptions.get_glued_cluster_positions(anchor)
    end
    if #cluster_positions == 0 then
        for x = self.minp.x, self.maxp.x do
            for y = self.minp.y, self.maxp.y do
                for z = self.minp.z, self.maxp.z do
                    local bp = {x = x, y = y, z = z}
                    local nn = core.get_node(bp).name
                    if nn ~= "air" and nn ~= "ignore" then
                        cluster_positions[#cluster_positions + 1] = bp
                    end
                end
            end
        end
    end

    local found_parent_pos, found_parent_node = nil, nil
    local checked_candidates = {}

    local function check_candidate(p)
        local hk = core.hash_node_position(p)
        if checked_candidates[hk] then return false end
        checked_candidates[hk] = true

        local n = core.get_node(p)
        if is_registered_parent_node(n.name) then
            local ppos, pnode = resolve_parent_controller_pos(p, n)
            if ppos and pnode then
                local is_act = read_parent_power_state(ppos, pnode)
                if is_act then
                    found_parent_pos, found_parent_node = ppos, pnode
                    return true
                elseif not found_parent_pos then
                    found_parent_pos, found_parent_node = ppos, pnode
                end
            end
        end
        return false
    end

    for _, cp in ipairs(cluster_positions) do
        if check_candidate(cp) then break end
        for _, d in ipairs(ALL_6_DIRS) do
            if check_candidate({x = cp.x + d.x, y = cp.y + d.y, z = cp.z + d.z}) then break end
        end
        if found_parent_pos and read_parent_power_state(found_parent_pos, found_parent_node) then
            break
        end
    end

    local parent_hash = found_parent_pos and core.hash_node_position(found_parent_pos) or nil

    local glued_machines = {}
    for x = self.minp.x, self.maxp.x do
        for y = self.minp.y, self.maxp.y do
            for z = self.minp.z, self.maxp.z do
                local bpos  = {x = x, y = y, z = z}
                local bhash = core.hash_node_position(bpos)
                if bhash ~= parent_hash then
                    local bnode = core.get_node(bpos)
                    local bname = bnode.name
                    if bname ~= "air" and bname ~= "ignore" and not is_registered_parent_node(bname) then
                        local mdef = find_machine_def_for_glue(bname)
                        local is_mach = (mdef ~= nil)
                            or (core.get_item_group(bname, "kinetic_receiver") > 0)
                            or (kinetica.is_water_pump and kinetica.is_water_pump(bname))
                            or (kinetica.is_mechanical_drill and kinetica.is_mechanical_drill(bname))
                            or (kinetica.is_mechanical_saw and kinetica.is_mechanical_saw(bname))
                            or (kinetica.is_mechanical_press and kinetica.is_mechanical_press(bname))
                            or (kinetica.is_crushing_wheel and kinetica.is_crushing_wheel(bname))
                            or (kinetica.is_deployer and kinetica.is_deployer(bname))

                        if is_mach then
                            glued_machines[#glued_machines + 1] = {pos = bpos, node = bnode, mdef = mdef}
                        end
                    end
                end
            end
        end
    end

    if not found_parent_pos or not found_parent_node then
        clear_parent_glue_load(self)
        for _, gm in ipairs(glued_machines) do
            set_glued_machine_idle(gm.pos, gm.node)
        end
        return
    end

    local p_active, p_rpm, p_spin, p_supply, p_avail = read_parent_power_state(found_parent_pos, found_parent_node)
    if not p_active then
        clear_parent_glue_load(self)
        for _, gm in ipairs(glued_machines) do
            set_glued_machine_idle(gm.pos, gm.node)
        end
        return
    end

    local total_glue_ku = 0
    for _, gm in ipairs(glued_machines) do
        local d_ku = get_machine_ku_demand(gm.pos, gm.node, p_rpm)
        gm.demand_ku  = d_ku
        total_glue_ku = total_glue_ku + d_ku
    end

    local pmeta        = core.get_meta(found_parent_pos)
    local prev_glue_ku = pmeta:get_int("glue_attached_ku")

    if self._last_parent_pos and core.hash_node_position(self._last_parent_pos) ~= parent_hash then
        clear_parent_glue_load(self)
    end
    self._last_parent_pos = {x = found_parent_pos.x, y = found_parent_pos.y, z = found_parent_pos.z}
    self._last_parent_ku  = total_glue_ku

    if prev_glue_ku ~= total_glue_ku then
        pmeta:set_int("glue_attached_ku", total_glue_ku)
        if kinetica.api and kinetica.api.network and kinetica.api.network.update then
            kinetica.api.network.update(found_parent_pos)
            p_active, p_rpm, p_spin, p_supply, p_avail = read_parent_power_state(found_parent_pos, core.get_node(found_parent_pos))
        end
    end

    if not p_active or p_supply <= 0 then
        for _, gm in ipairs(glued_machines) do
            set_glued_machine_idle(gm.pos, gm.node)
        end
        return
    end

    for _, gm in ipairs(glued_machines) do
        local bpos  = gm.pos
        local bnode = gm.node
        local bname = bnode.name
        local meta  = core.get_meta(bpos)

        local node_spin = p_spin
        if kinetica.is_crushing_wheel and kinetica.is_crushing_wheel(bname) then
            node_spin = ((bpos.x + bpos.y + bpos.z) % 2 == 0) and p_spin or (-p_spin)
        end

        meta:set_int("glue_powered", 1)
        meta:set_float("rpm", p_rpm)
        meta:set_int("spin_dir", node_spin)
        meta:set_int("local_spin", node_spin)
        meta:set_int("machine_demand_ku", gm.demand_ku or 16)
        meta:set_int("network_supply_ku", p_supply)
        meta:set_int("rotational_power", p_avail)
        meta:set_int("network_used_ku", math.max(0, p_supply - p_avail))
        meta:set_int("network_overstressed", 0)
        meta:set_int("lit_until", now + 4)
        meta:set_int("contraption_powered_until", now + 4)
        meta:set_int("source_active", 1)
        meta:set_float("source_rpm", p_rpm)
        meta:set_int("source_ku", p_supply)
        meta:set_int("source_spin", node_spin)

        if gm.mdef and gm.mdef.wake then
            pcall(gm.mdef.wake, bpos, bnode, p_rpm, node_spin, gm.demand_ku or 16, p_avail, p_supply)
        end

        local timer = core.get_node_timer(bpos)
        if timer and not timer:is_started() then
            timer:start(0.20)
        end
    end
end

local function destroy_glue_box(self, notify_player_name, reason_msg)
    if not self then return end
    clear_parent_glue_load(self)
    if self.minp and self.maxp then
        for x = self.minp.x, self.maxp.x do
            for y = self.minp.y, self.maxp.y do
                for z = self.minp.z, self.maxp.z do
                    local bp = {x = x, y = y, z = z}
                    set_glued_machine_idle(bp, core.get_node(bp))
                end
            end
        end
        spawn_glue_particles(self.minp, self.maxp, CONFIG.GLUE_COLOR, 22)
    end
    if kinetica.api and kinetica.api.contraptions then kinetica.api.contraptions.active_glue_boxes[self] = nil end
    if self.object then
        local p = self.object:get_pos()
        if p then play_glue_sound(p, 0.85) end
        self.object:remove()
    end
    if notify_player_name and notify_player_name ~= "" then
        core.chat_send_player(notify_player_name, reason_msg or "[Kinetica] Super Glue region removed.")
    end
end

core.register_entity(GLUE_ENTITY_NAME, {
    initial_properties = {
        physical = false, collide_with_objects = false, pointable = false, visual = "cube",
        visual_size = {x = 1.015, y = 1.015, z = 1.015}, textures = {"blank.png", "blank.png", "blank.png", "blank.png", "blank.png", "blank.png"},
        use_texture_alpha = true, backface_culling = false, shaded = false, glow = 8, static_save = true,
    },
    on_activate = function(self, staticdata)
        self.object:set_armor_groups({immortal = 1})
        self._vis_timer, self._empty_check = 0, 0
        self._move_timer, self._power_timer = 0, 0
        
        if staticdata and staticdata ~= "" then
            local data = core.deserialize(staticdata)
            if type(data) == "table" then
                if data.minp and data.maxp then
                    self.minp, self.maxp = vector.round(data.minp), vector.round(data.maxp)
                end
                if data.anchor_pos and data.anchor_name then
                    self.anchor_pos = vector.round(data.anchor_pos)
                    self.anchor_name = data.anchor_name
                end
            end
        end
        if not self.minp or not self.maxp then
            local p = vector.round(self.object:get_pos() or {x = 0, y = 0, z = 0})
            self.minp, self.maxp = p, p
        end
        if not self.anchor_pos then
            self.anchor_pos, self.anchor_name = get_first_solid(self.minp, self.maxp)
        end
        if kinetica.api and kinetica.api.contraptions then kinetica.api.contraptions.active_glue_boxes[self] = true end
        apply_glue_box_visuals(self)
        update_glue_box_parent_power(self)
    end,
    get_staticdata = function(self) 
        return core.serialize({minp = self.minp, maxp = self.maxp, anchor_pos = self.anchor_pos, anchor_name = self.anchor_name}) 
    end,
    on_deactivate = function(self)
        clear_parent_glue_load(self)
        if kinetica.api and kinetica.api.contraptions then kinetica.api.contraptions.active_glue_boxes[self] = nil end
    end,
    on_step = function(self, dtime)
        -- 1. High-frequency shift tracking when pushed/pulled by a Piston
        self._move_timer = (self._move_timer or 0) + dtime
        if self._move_timer >= 0.05 then
            self._move_timer = 0
            if self.minp and self.maxp then
                if self.anchor_pos and self.anchor_name then
                    local current = core.get_node(self.anchor_pos).name
                    if current ~= self.anchor_name then
                        local shifted = false
                        for _, d in ipairs(ALL_6_DIRS) do
                            local cand_name = core.get_node(vector.add(self.anchor_pos, d)).name
                            if cand_name == self.anchor_name or (string.sub(cand_name, 1, 9) == "kinetica:" and string.sub(self.anchor_name, 1, 9) == "kinetica:") then
                                self.anchor_pos = vector.add(self.anchor_pos, d)
                                self.anchor_name = cand_name
                                self.minp = vector.add(self.minp, d)
                                self.maxp = vector.add(self.maxp, d)
                                apply_glue_box_visuals(self)
                                update_glue_box_parent_power(self)
                                shifted = true
                                break
                            end
                        end
                        if not shifted then
                            self.anchor_pos, self.anchor_name = get_first_solid(self.minp, self.maxp)
                        end
                    end
                else
                    self.anchor_pos, self.anchor_name = get_first_solid(self.minp, self.maxp)
                end
            end
        end

        -- 2. Parent Contraption Power & KU Load Sync
        self._power_timer = (self._power_timer or 0) + dtime
        if self._power_timer >= (CONFIG.POWER_TICK_SEC or 0.20) then
            self._power_timer = 0
            if self.minp and self.maxp then
                update_glue_box_parent_power(self)
            end
        end

        -- 3. Visibility & Empty checks
        self._vis_timer = (self._vis_timer or 0) + dtime
        if self._vis_timer < CONFIG.VISIBILITY_CHECK_SEC then return end
        local dt = self._vis_timer
        self._vis_timer = 0

        if not self.minp or not self.maxp then
            clear_parent_glue_load(self)
            if kinetica.api and kinetica.api.contraptions then kinetica.api.contraptions.active_glue_boxes[self] = nil end
            self.object:remove()
            return
        end

        self._empty_check = (self._empty_check or 0) + dt
        if self._empty_check >= 0.60 then
            self._empty_check = 0
            if not has_any_solid_block_in_bounds(self.minp, self.maxp) then
                destroy_glue_box(self, nil, nil)
                return
            end
        end

        local center = {x = (self.minp.x + self.maxp.x) * 0.5, y = (self.minp.y + self.maxp.y) * 0.5, z = (self.minp.z + self.maxp.z) * 0.5}
        local should_show = is_any_player_holding_glue_near(center)
        if should_show ~= self._shown then apply_glue_box_visuals(self) end
    end,
})

core.register_on_dignode(function(pos)
    if kinetica.api and kinetica.api.contraptions and kinetica.api.contraptions.active_glue_boxes then
        for self, _ in pairs(kinetica.api.contraptions.active_glue_boxes) do
            if self.object and self.object:get_luaentity() and self.minp and self.maxp then
                if kinetica.api.contraptions.is_pos_inside_bounds(pos, self.minp, self.maxp) then
                    if not has_any_solid_block_in_bounds(self.minp, self.maxp) then
                        destroy_glue_box(self, nil, nil)
                    end
                end
            else
                kinetica.api.contraptions.active_glue_boxes[self] = nil
            end
        end
    end
end)

core.register_entity(PREVIEW_ENT_NAME, {
    initial_properties = {
        physical = false, collide_with_objects = false, pointable = false, visual = "cube",
        visual_size = {x = 1.02, y = 1.02, z = 1.02}, textures = {"blank.png", "blank.png", "blank.png", "blank.png", "blank.png", "blank.png"},
        use_texture_alpha = true, backface_culling = false, shaded = false, glow = 11, static_save = false,
    },
    on_activate = function(self) self.object:set_armor_groups({immortal = 1}) end,
    on_step = function(self)
        if not self.owner_name then self.object:remove(); return end
        local player = core.get_player_by_name(self.owner_name)
        if not player or not player_selections[self.owner_name] or not is_player_holding_glue(player) then
            preview_entities[self.owner_name] = nil
            self.object:remove()
        end
    end,
})

local function remove_player_preview(pname)
    local obj = preview_entities[pname]
    if obj and obj:get_luaentity() then obj:remove() end
    preview_entities[pname] = nil
end

local function get_player_target_pos(player, allow_air)
    local eye_pos = vector.add(player:get_pos(), {x = 0, y = (player:get_properties().eye_height or 1.62), z = 0})
    local look_dir = player:get_look_dir()
    local end_pos = vector.add(eye_pos, vector.multiply(look_dir, CONFIG.PREVIEW_RAY_DISTANCE))
    
    for pointed in core.raycast(eye_pos, end_pos, false, false) do
        if pointed.type == "node" and pointed.under then
            local nname = core.get_node(pointed.under).name
            if nname ~= "air" and nname ~= "ignore" then return vector.round(pointed.under), true end
        end
    end
    if allow_air then return vector.round(vector.add(eye_pos, vector.multiply(look_dir, CONFIG.PREVIEW_AIR_DISTANCE))), false end
    return nil, false
end

local function update_player_preview(player, pname, pos1, pos2)
    local minp, maxp, center, visual_size, _, is_valid = compute_glue_bounds(pos1, pos2)
    local obj = preview_entities[pname]

    if not obj or not obj:get_luaentity() then
        obj = core.add_entity(center, PREVIEW_ENT_NAME)
        if not obj then return end
        local le = obj:get_luaentity()
        if le then le.owner_name = pname end
        preview_entities[pname] = obj
    end

    local le = obj:get_luaentity()
    if not le then return end

    obj:set_pos(center)
    if not le.last_minp or not bounds_equal(le.last_minp, le.last_maxp, minp, maxp) or le.last_valid ~= is_valid then
        le.last_minp, le.last_maxp, le.last_valid = {x = minp.x, y = minp.y, z = minp.z}, {x = maxp.x, y = maxp.y, z = maxp.z}, is_valid
        local col = is_valid and CONFIG.PREVIEW_VALID_COLOR or CONFIG.PREVIEW_INVALID_COLOR
        obj:set_properties({
            visual_size = {x = visual_size.x + 0.01, y = visual_size.y + 0.01, z = visual_size.z + 0.01},
            textures = build_aligned_box_textures(minp, maxp, col, true),
        })
    end
end

local preview_tick_acc = 0
core.register_globalstep(function(dtime)
    preview_tick_acc = preview_tick_acc + dtime
    if preview_tick_acc < 0.08 then return end
    preview_tick_acc = 0

    for pname, sel in pairs(player_selections) do
        local player = core.get_player_by_name(pname)
        if not player or not is_player_holding_glue(player) then
            remove_player_preview(pname)
        else
            local target_pos = get_player_target_pos(player, true)
            if target_pos then update_player_preview(player, pname, sel.pos1, target_pos) end
        end
    end
end)

core.register_on_leaveplayer(function(player)
    local pname = player:get_player_name()
    player_selections[pname] = nil
    remove_player_preview(pname)
end)

function kinetica.create_super_glue_box(minp, maxp)
    if not kinetica.api or not kinetica.api.contraptions then return nil end
    for self, _ in pairs(kinetica.api.contraptions.active_glue_boxes) do
        if self.object and self.object:get_luaentity() and self.minp and self.maxp then
            if bounds_equal(self.minp, self.maxp, minp, maxp) then return self.object end
        else
            kinetica.api.contraptions.active_glue_boxes[self] = nil
        end
    end
    local _, _, center = compute_glue_bounds(minp, maxp)
    local obj = core.add_entity(center, GLUE_ENTITY_NAME, core.serialize({minp = minp, maxp = maxp}))
    if obj and obj:get_luaentity() then
        local le = obj:get_luaentity()
        le.minp, le.maxp = {x = minp.x, y = minp.y, z = minp.z}, {x = maxp.x, y = maxp.y, z = maxp.z}
        kinetica.api.contraptions.active_glue_boxes[le] = true
        apply_glue_box_visuals(le)
        update_glue_box_parent_power(le)
    end
    return obj
end

-- =========================================================
-- SUPER GLUE TOOL INTERACTION HANDLERS 
-- =========================================================
local function handle_glue_rightclick(itemstack, player, pointed_thing)
    if not player or not player:is_player() then return itemstack end
    local pname = player:get_player_name()
    local sel   = player_selections[pname]

    if not sel then
        local target_pos = nil
        if pointed_thing and pointed_thing.type == "node" and pointed_thing.under then
            local nn = core.get_node(pointed_thing.under).name
            if nn ~= "air" and nn ~= "ignore" then target_pos = vector.round(pointed_thing.under) end
        end
        if not target_pos then target_pos = get_player_target_pos(player, false) end

        if not target_pos then
            core.chat_send_player(pname, "[Kinetica] Right-click a solid block to start Super Glue Corner 1!")
            return itemstack
        end

        if core.is_protected(target_pos, pname) then
            core.record_protection_violation(target_pos, pname)
            return itemstack
        end

        player_selections[pname] = {pos1 = target_pos}
        spawn_glue_particles(target_pos, target_pos, CONFIG.GLUE_COLOR, 14)
        play_glue_sound(target_pos, 1.25)
        update_player_preview(player, pname, target_pos, target_pos)
        core.chat_send_player(pname, string.format(
            "[Kinetica] Super Glue Corner 1 set at (%d, %d, %d). Right-click any block OR in the air to confirm! (Left-click to cancel)",
            target_pos.x, target_pos.y, target_pos.z
        ))
        return itemstack
    end

    local end_pos = (pointed_thing and pointed_thing.type == "node" and pointed_thing.under) and vector.round(pointed_thing.under) or get_player_target_pos(player, true)
    if not end_pos then return itemstack end

    local minp, maxp, _, _, volume, is_valid, err_msg = compute_glue_bounds(sel.pos1, end_pos)
    if not is_valid then
        play_glue_sound(end_pos, 0.65)
        core.chat_send_player(pname, "[Kinetica] " .. (err_msg or "Invalid Super Glue region!"))
        return itemstack
    end

    if core.is_protected(minp, pname) or core.is_protected(maxp, pname) then
        core.record_protection_violation(end_pos, pname)
        return itemstack
    end

    player_selections[pname] = nil
    remove_player_preview(pname)

    kinetica.create_super_glue_box(minp, maxp)
    spawn_glue_particles(minp, maxp, CONFIG.GLUE_COLOR, 30)
    play_glue_sound(end_pos, 1.05)

    local sx, sy, sz = (maxp.x - minp.x) + 1, (maxp.y - minp.y) + 1, (maxp.z - minp.z) + 1
    core.chat_send_player(pname, string.format("[Kinetica] Super Glued %dx%dx%d region (%d block%s)!", sx, sy, sz, volume, (volume == 1) and "" or "s"))

    if not core.is_creative_enabled(pname) then itemstack:add_wear(math.floor(65535 / CONFIG.SUPER_GLUE_USES)) end
    return itemstack
end

local function handle_glue_leftclick(itemstack, player, pointed_thing)
    if not player or not player:is_player() then return itemstack end
    local pname = player:get_player_name()

    if player_selections[pname] then
        player_selections[pname] = nil
        remove_player_preview(pname)
        core.chat_send_player(pname, "[Kinetica] Super Glue selection cancelled.")
        return itemstack
    end

    local hit_box = find_raycasted_glue_box(player)
    if not hit_box and pointed_thing and pointed_thing.type == "node" and pointed_thing.under and kinetica.api and kinetica.api.contraptions then
        local boxes = kinetica.api.contraptions.get_glue_boxes_at(pointed_thing.under)
        if #boxes > 0 then hit_box = boxes[#boxes] end
    end

    if hit_box then
        if hit_box.minp and core.is_protected(hit_box.minp, pname) then
            core.record_protection_violation(hit_box.minp, pname)
            return itemstack
        end
        destroy_glue_box(hit_box, pname, "[Kinetica] Super Glue region removed.")
    end

    return itemstack
end

core.register_tool(GLUE_TOOL_NAME, {
    description = "Super Glue\n" ..
                  "• Right-Click a block to start Corner 1, then Right-Click any block or in the air to glue!\n" ..
                  "• Overlap multiple glue boxes to build L-shapes, T-shapes, and custom contraptions.\n" ..
                  "• Glued Drills & Saws automatically store mined items into any Chest inside the glue!\n" ..
                  "• Left-Click a glued region while holding Super Glue to remove it.",
    inventory_image  = build_super_glue_icon(),
    wield_image      = build_super_glue_icon(),
    groups           = {kinetica_super_glue = 1},
    on_place         = handle_glue_rightclick,
    on_secondary_use = handle_glue_rightclick,
    on_use           = handle_glue_leftclick,
})

core.register_alias("kinetica:resin_glue", GLUE_TOOL_NAME)

local sheet_item  = core.registered_items["kinetica:sheet_iron"]    and "kinetica:sheet_iron"    or "mcl_core:iron_ingot"
local slime_item  = core.registered_items["mcl_mobitems:slimeball"] and "mcl_mobitems:slimeball" or "default:mese_crystal_fragment"
local nugget_item = core.registered_items["mcl_core:iron_nugget"]   and "mcl_core:iron_nugget"   or "default:steel_ingot"

core.register_craft({
    output = GLUE_TOOL_NAME,
    recipe = {
        {slime_item, nugget_item},
        {sheet_item, slime_item},
    },
})