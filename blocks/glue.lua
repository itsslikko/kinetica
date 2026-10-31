kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

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
}

local GLUE_TOOL_NAME   = "kinetica:super_glue"
local GLUE_ENTITY_NAME = "kinetica:super_glue_box"
local PREVIEW_ENT_NAME = "kinetica:super_glue_preview"

local player_selections = {}
local preview_entities  = {}
local active_glue_boxes = {}

local ALL_6_DIRS = {
    {x =  1, y =  0, z =  0},
    {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0},
    {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1},
    {x =  0, y =  0, z = -1},
}

local function file_exists(filename)
    if not filename or filename == "" then return false end
    local ok, f = pcall(io.open, modpath .. "/textures/" .. filename, "r")
    if ok and f then
        f:close()
        return true
    end
    return false
end

local function is_glue_tool_name(name)
    return name == GLUE_TOOL_NAME or name == "kinetica:resin_glue"
end
kinetica.is_glue_tool = is_glue_tool_name

local function is_player_holding_glue(player)
    if not player or not player:is_player() then return false end
    local wield = player:get_wielded_item()
    if wield and is_glue_tool_name(wield:get_name()) then
        return true
    end
    local inv = player:get_inventory()
    if inv and inv:get_size("offhand") > 0 then
        local off = inv:get_stack("offhand", 1)
        if off and is_glue_tool_name(off:get_name()) then
            return true
        end
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
-- PERFECTLY ALIGNED 6-FACE BOX TEXTURE OVERLAY BUILDER
-- =========================================================
local function get_base_canvas_tex()
    if file_exists(CONFIG.FALLBACK_BASE_TEX) then
        return CONFIG.FALLBACK_BASE_TEX
    end
    return "default_stone.png"
end

local function build_single_cell_tile(hex_color, fill_alpha, border_alpha)
    if file_exists(CONFIG.TEX_CUSTOM_GLUE_BOX) then
        return "(" .. CONFIG.TEX_CUSTOM_GLUE_BOX .. "\\^[resize\\:16x16)"
    end

    local b     = get_base_canvas_tex()
    local fill  = "(" .. b .. "\\^[resize\\:16x16\\^[colorize\\:" .. hex_color .. "\\:255\\^[opacity\\:" .. tostring(fill_alpha or 55) .. ")"
    local h_bar = "(" .. b .. "\\^[resize\\:16x1\\^[colorize\\:" .. hex_color .. "\\:255\\^[opacity\\:" .. tostring(border_alpha or 210) .. ")"
    local v_bar = "(" .. b .. "\\^[resize\\:1x16\\^[colorize\\:" .. hex_color .. "\\:255\\^[opacity\\:" .. tostring(border_alpha or 210) .. ")"

    return "([combine:16x16" ..
        ":0,0="  .. fill ..
        ":0,0="  .. h_bar ..
        ":0,15=" .. h_bar ..
        ":0,0="  .. v_bar ..
        ":15,0=" .. v_bar .. ")"
end

local function build_face_texture(blocks_w, blocks_h, hex_color, is_preview)
    local w = math.max(1, math.min(CONFIG.MAX_TILE_RENDER_SPAN, math.floor(blocks_w + 0.5)))
    local h = math.max(1, math.min(CONFIG.MAX_TILE_RENDER_SPAN, math.floor(blocks_h + 0.5)))

    local pw = w * 16
    local ph = h * 16
    local b  = get_base_canvas_tex()

    if file_exists(CONFIG.TEX_CUSTOM_GLUE_BOX) then
        local tile  = "(" .. CONFIG.TEX_CUSTOM_GLUE_BOX .. "\\^[resize\\:16x16)"
        local parts = {"[combine:" .. pw .. "x" .. ph}
        for gx = 0, w - 1 do
            for gy = 0, h - 1 do
                parts[#parts + 1] = ":" .. (gx * 16) .. "," .. (gy * 16) .. "=" .. tile
            end
        end
        local combined = table.concat(parts)
        if is_preview and hex_color == CONFIG.PREVIEW_INVALID_COLOR then
            combined = combined .. "^[colorize:" .. hex_color .. ":160"
        end
        return combined .. "^[opacity:" .. tostring(is_preview and 195 or 165)
    end

    local fill_op   = is_preview and 65  or 48
    local grid_op   = is_preview and 115 or 95
    local border_op = is_preview and 240 or 215

    local bg_fill   = "(" .. b .. "\\^[resize\\:" .. pw .. "x" .. ph .. "\\^[colorize\\:" .. hex_color .. "\\:220\\^[opacity\\:" .. fill_op .. ")"
    local grid_v    = "(" .. b .. "\\^[resize\\:1x" .. ph .. "\\^[colorize\\:" .. hex_color .. "\\:240\\^[opacity\\:" .. grid_op .. ")"
    local grid_h    = "(" .. b .. "\\^[resize\\:" .. pw .. "x1\\^[colorize\\:" .. hex_color .. "\\:240\\^[opacity\\:" .. grid_op .. ")"
    local edge_top  = "(" .. b .. "\\^[resize\\:" .. pw .. "x2\\^[colorize\\:#ffffff\\:80\\^[colorize\\:" .. hex_color .. "\\:220\\^[opacity\\:" .. border_op .. ")"
    local edge_side = "(" .. b .. "\\^[resize\\:2x" .. ph .. "\\^[colorize\\:#ffffff\\:80\\^[colorize\\:" .. hex_color .. "\\:220\\^[opacity\\:" .. border_op .. ")"

    local parts = {
        "[combine:" .. pw .. "x" .. ph,
        ":0,0=" .. bg_fill,
    }

    for gx = 1, w - 1 do
        parts[#parts + 1] = ":" .. (gx * 16) .. ",0=" .. grid_v
    end
    for gy = 1, h - 1 do
        parts[#parts + 1] = ":0," .. (gy * 16) .. "=" .. grid_h
    end

    parts[#parts + 1] = ":0,0=" .. edge_top
    parts[#parts + 1] = ":0," .. (ph - 2) .. "=" .. edge_top
    parts[#parts + 1] = ":0,0=" .. edge_side
    parts[#parts + 1] = ":" .. (pw - 2) .. ",0=" .. edge_side

    return table.concat(parts)
end

local function build_aligned_box_textures(minp, maxp, hex_color, is_preview)
    local bw = (maxp.x - minp.x) + 1
    local bh = (maxp.y - minp.y) + 1
    local bd = (maxp.z - minp.z) + 1

    local tex_y = build_face_texture(bw, bd, hex_color, is_preview)
    local tex_x = build_face_texture(bd, bh, hex_color, is_preview)
    local tex_z = build_face_texture(bw, bh, hex_color, is_preview)

    return {tex_y, tex_y, tex_x, tex_x, tex_z, tex_z}
end

local function build_super_glue_icon()
    if file_exists(CONFIG.TEX_CUSTOM_GLUE_ICON) then
        return CONFIG.TEX_CUSTOM_GLUE_ICON
    end

    local b = get_base_canvas_tex()
    local function rect(w, h, hex)
        return "(" .. b .. "\\^[resize\\:" .. w .. "x" .. h .. "\\^[sheet\\:1x1\\:0,0\\^[colorize\\:" .. hex .. "\\:240)"
    end

    local cap_tip    = rect(2, 2, "#E0E6ED")
    local nozzle     = rect(4, 2, "#B0BAC5")
    local slime_drop = rect(2, 2, "#00E676")
    local collar     = rect(8, 2, "#263238")
    local tube_body  = rect(8, 7, "#00C853")
    local label_band = rect(8, 3, "#ECEFF1")
    local label_dot  = rect(4, 1, "#00E676")
    local crimp_end  = rect(8, 2, "#78909C")

    return "[combine:16x16" ..
        ":7,1="  .. cap_tip ..
        ":9,1="  .. slime_drop ..
        ":6,3="  .. nozzle ..
        ":4,5="  .. collar ..
        ":4,7="  .. tube_body ..
        ":4,9="  .. label_band ..
        ":6,10=" .. label_dot ..
        ":4,14=" .. crimp_end
end

-- =========================================================
-- BOUNDING BOX GEOMETRY, OVERLAP & RAY-AABB MATH
-- =========================================================
local function compute_glue_bounds(p1, p2)
    local minp = {
        x = math.min(p1.x, p2.x),
        y = math.min(p1.y, p2.y),
        z = math.min(p1.z, p2.z),
    }
    local maxp = {
        x = math.max(p1.x, p2.x),
        y = math.max(p1.y, p2.y),
        z = math.max(p1.z, p2.z),
    }
    local sx = (maxp.x - minp.x) + 1
    local sy = (maxp.y - minp.y) + 1
    local sz = (maxp.z - minp.z) + 1
    local volume = sx * sy * sz

    local center = {
        x = (minp.x + maxp.x) * 0.5,
        y = (minp.y + maxp.y) * 0.5,
        z = (minp.z + maxp.z) * 0.5,
    }
    local visual_size = {
        x = sx + CONFIG.BOX_PAD,
        y = sy + CONFIG.BOX_PAD,
        z = sz + CONFIG.BOX_PAD,
    }
    local half_ext = {
        x = sx * 0.5 + 0.01,
        y = sy * 0.5 + 0.01,
        z = sz * 0.5 + 0.01,
    }

    if sx > CONFIG.MAX_GLUE_SPAN or sy > CONFIG.MAX_GLUE_SPAN or sz > CONFIG.MAX_GLUE_SPAN then
        return minp, maxp, center, visual_size, half_ext, volume, false,
            string.format("Span too wide (%dx%dx%d; max is %d blocks)!", sx, sy, sz, CONFIG.MAX_GLUE_SPAN)
    end
    if volume > CONFIG.MAX_GLUE_VOLUME then
        return minp, maxp, center, visual_size, half_ext, volume, false,
            string.format("Volume too large (%d blocks; max is %d)!", volume, CONFIG.MAX_GLUE_VOLUME)
    end

    return minp, maxp, center, visual_size, half_ext, volume, true, nil
end

local function is_pos_inside_bounds(pos, minp, maxp)
    return pos.x >= minp.x and pos.x <= maxp.x and
           pos.y >= minp.y and pos.y <= maxp.y and
           pos.z >= minp.z and pos.z <= maxp.z
end

local function bounds_equal(a_min, a_max, b_min, b_max)
    return a_min.x == b_min.x and a_min.y == b_min.y and a_min.z == b_min.z and
           a_max.x == b_max.x and a_max.y == b_max.y and a_max.z == b_max.z
end

-- Checks if any non-air solid block still exists inside the glue box (Create mod auto-dissolve rule)
local function has_any_solid_block_in_bounds(minp, maxp)
    if not minp or not maxp then return false end
    for x = minp.x, maxp.x do
        for y = minp.y, maxp.y do
            for z = minp.z, maxp.z do
                local nn = core.get_node({x = x, y = y, z = z}).name
                if nn ~= "air" then
                    if nn == "ignore" then
                        return true
                    end
                    local def = core.registered_nodes[nn]
                    if not def or not def.liquidtype or def.liquidtype == "none" then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Ray-AABB slab intersection so players can left-click any glue box without blocking right-clicks!
local function ray_intersects_glue_box(origin, dir, max_dist, minp, maxp)
    local bmin = {x = minp.x - 0.51, y = minp.y - 0.51, z = minp.z - 0.51}
    local bmax = {x = maxp.x + 0.51, y = maxp.y + 0.51, z = maxp.z + 0.51}

    local tmin = 0.0
    local tmax = max_dist

    for _, axis in ipairs({"x", "y", "z"}) do
        local o = origin[axis]
        local d = dir[axis]
        if math.abs(d) < 1e-6 then
            if o < bmin[axis] or o > bmax[axis] then
                return nil
            end
        else
            local t1 = (bmin[axis] - o) / d
            local t2 = (bmax[axis] - o) / d
            if t1 > t2 then t1, t2 = t2, t1 end
            if t1 > tmin then tmin = t1 end
            if t2 < tmax then tmax = t2 end
            if tmin > tmax then
                return nil
            end
        end
    end

    return tmin
end

local function find_raycasted_glue_box(player)
    local eye_pos = vector.add(player:get_pos(), {
        x = 0,
        y = (player:get_properties().eye_height or 1.62),
        z = 0,
    })
    local look_dir  = player:get_look_dir()
    local best_box  = nil
    local best_dist = math.huge

    for self, _ in pairs(active_glue_boxes) do
        if self.object and self.object:get_luaentity() and self.minp and self.maxp then
            local hit_t = ray_intersects_glue_box(eye_pos, look_dir, CONFIG.PREVIEW_RAY_DISTANCE, self.minp, self.maxp)
            if hit_t and hit_t < best_dist then
                best_dist = hit_t
                best_box  = self
            end
        else
            active_glue_boxes[self] = nil
        end
    end
    return best_box
end

-- =========================================================
-- PARTICLES & AUDIO EFFECTS
-- =========================================================
local function spawn_glue_particles(minp, maxp, hex_color, burst_count)
    local tex = build_single_cell_tile(hex_color or CONFIG.GLUE_COLOR, 180, 255)
    core.add_particlespawner({
        amount     = burst_count or 20,
        time       = 0.15,
        minpos     = {x = minp.x - 0.45, y = minp.y - 0.45, z = minp.z - 0.45},
        maxpos     = {x = maxp.x + 0.45, y = maxp.y + 0.45, z = maxp.z + 0.45},
        minvel     = {x = -0.5, y =  0.2, z = -0.5},
        maxvel     = {x =  0.5, y =  0.9, z =  0.5},
        minexptime = 0.25,
        maxexptime = 0.55,
        minsize    = 1.2,
        maxsize    = 2.2,
        glow       = 12,
        texture    = tex,
    })
end

local function play_glue_sound(pos, pitch)
    local snd = (mcl_sounds and mcl_sounds.node_sound_slime_defaults) and "default_place_node" or "default_place_node_hard"
    core.sound_play(snd, {
        pos               = pos,
        gain              = 0.55,
        pitch             = pitch or 1.15,
        max_hear_distance = 16,
    }, true)
end

-- =========================================================
-- PERSISTENT 3D SUPER GLUE BOX ENTITY
-- =========================================================
local function apply_glue_box_visuals(self)
    if not self.minp or not self.maxp then return end
    local minp, maxp, center, visual_size = compute_glue_bounds(self.minp, self.maxp)
    self.minp = minp
    self.maxp = maxp

    local show_now = is_any_player_holding_glue_near(center)
    self._shown    = show_now

    -- Keep `pointable = false` so existing glue boxes NEVER block right-clicking blocks inside them
    -- or overlapping multiple glue boxes! Left-clicking uses `find_raycasted_glue_box`.
    self.object:set_pos(center)
    self.object:set_properties({
        visual            = "cube",
        visual_size       = visual_size,
        textures          = build_aligned_box_textures(minp, maxp, CONFIG.GLUE_COLOR, false),
        use_texture_alpha = true,
        backface_culling  = false,
        shaded            = false,
        glow              = 8,
        is_visible        = show_now,
        pointable         = false,
        collisionbox      = {0, 0, 0, 0, 0, 0},
        selectionbox      = {0, 0, 0, 0, 0, 0},
    })
end

local function destroy_glue_box(self, notify_player_name, reason_msg)
    if not self then return end
    active_glue_boxes[self] = nil
    if self.minp and self.maxp then
        spawn_glue_particles(self.minp, self.maxp, CONFIG.GLUE_COLOR, 22)
    end
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
        physical             = false,
        collide_with_objects = false,
        pointable            = false,
        visual               = "cube",
        visual_size          = {x = 1.015, y = 1.015, z = 1.015},
        textures             = {"blank.png", "blank.png", "blank.png", "blank.png", "blank.png", "blank.png"},
        use_texture_alpha    = true,
        backface_culling     = false,
        shaded               = false,
        glow                 = 8,
        static_save          = true,
    },

    on_activate = function(self, staticdata)
        self.object:set_armor_groups({immortal = 1})
        self._vis_timer   = 0
        self._empty_Check = 0

        if staticdata and staticdata ~= "" then
            local data = core.deserialize(staticdata)
            if type(data) == "table" and data.minp and data.maxp then
                self.minp = vector.round(data.minp)
                self.maxp = vector.round(data.maxp)
            end
        end

        if not self.minp or not self.maxp then
            local p = vector.round(self.object:get_pos() or {x = 0, y = 0, z = 0})
            self.minp = p
            self.maxp = p
        end

        active_glue_boxes[self] = true
        apply_glue_box_visuals(self)
    end,

    get_staticdata = function(self)
        return core.serialize({
            minp = self.minp,
            maxp = self.maxp,
        })
    end,

    on_deactivate = function(self)
        active_glue_boxes[self] = nil
    end,

    on_step = function(self, dtime)
        self._vis_timer = (self._vis_timer or 0) + dtime
        if self._vis_timer < CONFIG.VISIBILITY_CHECK_SEC then
            return
        end
        local dt = self._vis_timer
        self._vis_timer = 0

        if not self.minp or not self.maxp then
            active_glue_boxes[self] = nil
            self.object:remove()
            return
        end

        -- Auto-destroy if all blocks inside the glue box have been removed (Create Mod behavior)
        self._empty_check = (self._empty_check or 0) + dt
        if self._empty_check >= 0.60 then
            self._empty_check = 0
            if not has_any_solid_block_in_bounds(self.minp, self.maxp) then
                destroy_glue_box(self, nil, nil)
                return
            end
        end

        local center = {
            x = (self.minp.x + self.maxp.x) * 0.5,
            y = (self.minp.y + self.maxp.y) * 0.5,
            z = (self.minp.z + self.maxp.z) * 0.5,
        }
        local should_show = is_any_player_holding_glue_near(center)
        if should_show ~= self._shown then
            apply_glue_box_visuals(self)
        end
    end,
})

-- Immediate check when a node is dug so emptied glue boxes dissolve right away
core.register_on_dignode(function(pos)
    for self, _ in pairs(active_glue_boxes) do
        if self.object and self.object:get_luaentity() and self.minp and self.maxp then
            if is_pos_inside_bounds(pos, self.minp, self.maxp) then
                if not has_any_solid_block_in_bounds(self.minp, self.maxp) then
                    destroy_glue_box(self, nil, nil)
                end
            end
        else
            active_glue_boxes[self] = nil
        end
    end
end)

-- =========================================================
-- LIVE SELECTION PREVIEW ENTITY & RAYCASTING
-- =========================================================
core.register_entity(PREVIEW_ENT_NAME, {
    initial_properties = {
        physical             = false,
        collide_with_objects = false,
        pointable            = false,
        visual               = "cube",
        visual_size          = {x = 1.02, y = 1.02, z = 1.02},
        textures             = {"blank.png", "blank.png", "blank.png", "blank.png", "blank.png", "blank.png"},
        use_texture_alpha    = true,
        backface_culling     = false,
        shaded               = false,
        glow                 = 11,
        static_save          = false,
    },

    on_activate = function(self)
        self.object:set_armor_groups({immortal = 1})
    end,

    on_step = function(self)
        if not self.owner_name then
            self.object:remove()
            return
        end
        local player = core.get_player_by_name(self.owner_name)
        if not player or not player_selections[self.owner_name] or not is_player_holding_glue(player) then
            preview_entities[self.owner_name] = nil
            self.object:remove()
        end
    end,
})

local function remove_player_preview(pname)
    local obj = preview_entities[pname]
    if obj and obj:get_luaentity() then
        obj:remove()
    end
    preview_entities[pname] = nil
end

-- Raycasts for a solid node first; if pointing at open air, returns the air block at `PREVIEW_AIR_DISTANCE`
local function get_player_target_pos(player, allow_air)
    local eye_pos = vector.add(player:get_pos(), {
        x = 0,
        y = (player:get_properties().eye_height or 1.62),
        z = 0,
    })
    local look_dir = player:get_look_dir()
    local end_pos  = vector.add(eye_pos, vector.multiply(look_dir, CONFIG.PREVIEW_RAY_DISTANCE))
    local ray      = core.raycast(eye_pos, end_pos, false, false)

    for pointed in ray do
        if pointed.type == "node" and pointed.under then
            local nname = core.get_node(pointed.under).name
            if nname ~= "air" and nname ~= "ignore" then
                return vector.round(pointed.under), true
            end
        end
    end

    if allow_air then
        local air_target = vector.add(eye_pos, vector.multiply(look_dir, CONFIG.PREVIEW_AIR_DISTANCE))
        return vector.round(air_target), false
    end

    return nil, false
end

local function update_player_preview(player, pname, pos1, pos2)
    local minp, maxp, center, visual_size, _, _, is_valid = compute_glue_bounds(pos1, pos2)
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
        le.last_minp  = {x = minp.x, y = minp.y, z = minp.z}
        le.last_maxp  = {x = maxp.x, y = maxp.y, z = maxp.z}
        le.last_valid = is_valid

        local col = is_valid and CONFIG.PREVIEW_VALID_COLOR or CONFIG.PREVIEW_INVALID_COLOR
        obj:set_properties({
            visual_size = {
                x = visual_size.x + 0.01,
                y = visual_size.y + 0.01,
                z = visual_size.z + 0.01,
            },
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
            if target_pos then
                update_player_preview(player, pname, sel.pos1, target_pos)
            end
        end
    end
end)

core.register_on_leaveplayer(function(player)
    local pname = player:get_player_name()
    player_selections[pname] = nil
    remove_player_preview(pname)
end)

-- =========================================================
-- TRANSITIVE MULTI-SEGMENT CONTRAPTION & STORAGE API
-- =========================================================
local function spawn_or_replace_glue_box(minp, maxp)
    for self, _ in pairs(active_glue_boxes) do
        if self.object and self.object:get_luaentity() and self.minp and self.maxp then
            if bounds_equal(self.minp, self.maxp, minp, maxp) then
                return self.object
            end
        else
            active_glue_boxes[self] = nil
        end
    end

    local _, _, center = compute_glue_bounds(minp, maxp)
    local obj = core.add_entity(center, GLUE_ENTITY_NAME, core.serialize({minp = minp, maxp = maxp}))
    if obj and obj:get_luaentity() then
        local le = obj:get_luaentity()
        le.minp = {x = minp.x, y = minp.y, z = minp.z}
        le.maxp = {x = maxp.x, y = maxp.y, z = maxp.z}
        active_glue_boxes[le] = true
        apply_glue_box_visuals(le)
    end
    return obj
end
kinetica.create_super_glue_box = spawn_or_replace_glue_box

function kinetica.get_glue_boxes_at(pos)
    local p    = vector.round(pos)
    local list = {}
    for self, _ in pairs(active_glue_boxes) do
        if self.object and self.object:get_luaentity() and self.minp and self.maxp then
            if is_pos_inside_bounds(p, self.minp, self.maxp) then
                list[#list + 1] = self
            end
        else
            active_glue_boxes[self] = nil
        end
    end
    return list
end

-- Transitive BFS across ALL overlapping Super Glue boxes so L-shapes, T-shapes, and multi-segments connect!
function kinetica.get_glued_cluster_positions(start_pos)
    local p0          = vector.round(start_pos)
    local results     = {}
    local visited_pos = {}
    local visited_box = {}
    local pos_queue   = {}

    local initial_boxes = kinetica.get_glue_boxes_at(p0)
    if #initial_boxes == 0 then
        return results
    end

    local p0_hash = core.hash_node_position(p0)
    visited_pos[p0_hash] = true
    pos_queue[1] = p0

    local n0 = core.get_node(p0).name
    if n0 ~= "air" and n0 ~= "ignore" then
        results[#results + 1] = p0
    end

    local head = 1
    while head <= #pos_queue and #results < CONFIG.MAX_GLUE_VOLUME do
        local cur = pos_queue[head]
        head = head + 1

        for self, _ in pairs(active_glue_boxes) do
            if not visited_box[self] and self.object and self.object:get_luaentity() and self.minp and self.maxp then
                if is_pos_inside_bounds(cur, self.minp, self.maxp) then
                    visited_box[self] = true
                    for x = self.minp.x, self.maxp.x do
                        for y = self.minp.y, self.maxp.y do
                            for z = self.minp.z, self.maxp.z do
                                local bp = {x = x, y = y, z = z}
                                local hk = core.hash_node_position(bp)
                                if not visited_pos[hk] then
                                    visited_pos[hk] = true
                                    local nn = core.get_node(bp).name
                                    if nn ~= "air" and nn ~= "ignore" then
                                        results[#results + 1]   = bp
                                        pos_queue[#pos_queue+1] = bp
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return results
end

function kinetica.are_positions_glued(pos1, pos2)
    local p1 = vector.round(pos1)
    local p2 = vector.round(pos2)
    for self, _ in pairs(active_glue_boxes) do
        if self.object and self.object:get_luaentity() and self.minp and self.maxp then
            if is_pos_inside_bounds(p1, self.minp, self.maxp) and
               is_pos_inside_bounds(p2, self.minp, self.maxp) then
                return true
            end
        else
            active_glue_boxes[self] = nil
        end
    end

    local cluster = kinetica.get_glued_cluster_positions(p1)
    local p2_hash = core.hash_node_position(p2)
    for _, cp in ipairs(cluster) do
        if core.hash_node_position(cp) == p2_hash then
            return true
        end
    end
    return false
end
kinetica.is_glued_together = kinetica.are_positions_glued

function kinetica.shift_glue_boxes_in_volume(moved_positions, move_dir)
    if not moved_positions or not move_dir then return end
    local moved_hashes = {}
    for _, mp in ipairs(moved_positions) do
        moved_hashes[core.hash_node_position(vector.round(mp))] = true
    end

    for self, _ in pairs(active_glue_boxes) do
        if self.object and self.object:get_luaentity() and self.minp and self.maxp then
            local touches = false
            for x = self.minp.x, self.maxp.x do
                for y = self.minp.y, self.maxp.y do
                    for z = self.minp.z, self.maxp.z do
                        if moved_hashes[core.hash_node_position({x = x, y = y, z = z})] then
                            touches = true
                            break
                        end
                    end
                    if touches then break end
                end
                if touches then break end
            end

            if touches then
                self.minp = vector.add(self.minp, move_dir)
                self.maxp = vector.add(self.maxp, move_dir)
                apply_glue_box_visuals(self)
            end
        else
            active_glue_boxes[self] = nil
        end
    end
end

-- =========================================================
-- GLUED CONTRAPTION SHARED STORAGE ROUTING (DRILLS, SAWS, ETC.)
-- =========================================================
local function is_contraption_harvester_node(name)
    if not name or name == "air" then return false end
    if kinetica.is_mechanical_drill and kinetica.is_mechanical_drill(name) then
        return true
    end
    if kinetica.is_mechanical_saw and kinetica.is_mechanical_saw(name) then
        return true
    end
    if string.find(name, "kinetica:mechanical_drill", 1, true) or
       string.find(name, "kinetica:mechanical_saw", 1, true) or
       string.find(name, "kinetica:harvester", 1, true) or
       string.find(name, "kinetica:plough", 1, true) then
        return true
    end
    return false
end

local function try_insert_stack_into_glued_storage(dest_pos, stack)
    if not stack or stack:is_empty() then
        return ItemStack(""), false
    end

    local dnode = core.get_node(dest_pos)
    local dname = dnode.name
    if dname == "air" or dname == "ignore" or is_contraption_harvester_node(dname) then
        return stack, false
    end

    local dmeta = core.get_meta(dest_pos)
    local dinv  = dmeta and dmeta:get_inventory()
    if dinv then
        for _, listname in ipairs({"main", "input", "src", "contents"}) do
            if dinv:get_size(listname) > 0 and dinv:room_for_item(listname, stack) then
                local leftover = dinv:add_item(listname, stack)
                local ct = core.get_node_timer(dest_pos)
                if ct and not ct:is_started() then ct:start(0.20) end
                if mcl_redstone and mcl_redstone.update_comparators then
                    pcall(mcl_redstone.update_comparators, vector.new(dest_pos.x, dest_pos.y, dest_pos.z))
                end
                return leftover, true
            end
        end
    end

    if dname == "kinetica:depot" or core.get_item_group(dname, "kinetica_depot") > 0 then
        if dinv and dinv:get_size("output") > 0 and dinv:room_for_item("output", stack) then
            local leftover = dinv:add_item("output", stack)
            local dt = core.get_node_timer(dest_pos)
            if dt and not dt:is_started() then dt:start(0.20) end
            return leftover, true
        end
    end

    return stack, false
end

-- Routes an ItemStack into any Chest/Barrel/Storage glued to the same contraption as `harvester_pos`
function kinetica.try_store_in_glued_contraption(harvester_pos, stack)
    stack = ItemStack(stack)
    if stack:is_empty() then return stack, true end

    local hnode = core.get_node(harvester_pos)
    if kinetica.is_mechanical_drill and kinetica.is_mechanical_drill(hnode.name) then
        if core.get_meta(harvester_pos):get_int("storage_mode") == 0 then
            return stack, false
        end
    end

    local cluster = kinetica.get_glued_cluster_positions(harvester_pos)
    if #cluster == 0 then
        return stack, false
    end

    local stored_any = false
    for _, cpos in ipairs(cluster) do
        local leftover, did_store = try_insert_stack_into_glued_storage(cpos, stack)
        if did_store then
            stored_any = true
            stack      = leftover
            if stack:is_empty() then
                break
            end
        end
    end

    return stack, stored_any
end

-- Intercepts drops spawned by glued Drills/Saws (`core.add_item`) and routes them into glued Chests!
local in_glue_add_item_hook = false
local orig_core_add_item    = core.add_item

function core.add_item(pos, item)
    if not in_glue_add_item_hook and pos and item and next(active_glue_boxes) then
        local stack = ItemStack(item)
        if not stack:is_empty() then
            local rpos = vector.round(pos)
            local harvester_pos = nil

            -- Check `rpos` and its 6 neighbors for a glued Drill, Saw, or Harvester
            if is_contraption_harvester_node(core.get_node(rpos).name) and #kinetica.get_glue_boxes_at(rpos) > 0 then
                harvester_pos = rpos
            else
                for _, d in ipairs(ALL_6_DIRS) do
                    local np = {x = rpos.x + d.x, y = rpos.y + d.y, z = rpos.z + d.z}
                    if is_contraption_harvester_node(core.get_node(np).name) and #kinetica.get_glue_boxes_at(np) > 0 then
                        harvester_pos = np
                        break
                    end
                end
            end

            if harvester_pos then
                in_glue_add_item_hook = true
                local leftover, did_store = kinetica.try_store_in_glued_contraption(harvester_pos, stack)
                in_glue_add_item_hook = false

                if did_store then
                    if leftover:is_empty() then
                        return nil
                    end
                    return orig_core_add_item(pos, leftover)
                end
            end
        end
    end
    return orig_core_add_item(pos, item)
end

-- =========================================================
-- SUPER GLUE TOOL INTERACTION HANDLERS (NO RECURSION!)
-- =========================================================
local function handle_glue_rightclick(itemstack, player, pointed_thing)
    if not player or not player:is_player() then
        return itemstack
    end
    local pname = player:get_player_name()
    local sel   = player_selections[pname]

    -- STEP 1: Starting Corner 1 requires clicking a mandatory solid block!
    if not sel then
        local target_pos = nil
        if pointed_thing and pointed_thing.type == "node" and pointed_thing.under then
            local nn = core.get_node(pointed_thing.under).name
            if nn ~= "air" and nn ~= "ignore" then
                target_pos = vector.round(pointed_thing.under)
            end
        end
        if not target_pos then
            target_pos = get_player_target_pos(player, false)
        end

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

    -- STEP 2: Confirming Corner 2 works on ANY block OR in open air!
    local end_pos = nil
    if pointed_thing and pointed_thing.type == "node" and pointed_thing.under then
        end_pos = vector.round(pointed_thing.under)
    else
        end_pos = get_player_target_pos(player, true)
    end

    if not end_pos then
        return itemstack
    end

    local minp, maxp, _, _, _, volume, is_valid, err_msg = compute_glue_bounds(sel.pos1, end_pos)
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

    spawn_or_replace_glue_box(minp, maxp)
    spawn_glue_particles(minp, maxp, CONFIG.GLUE_COLOR, 30)
    play_glue_sound(end_pos, 1.05)

    local sx = (maxp.x - minp.x) + 1
    local sy = (maxp.y - minp.y) + 1
    local sz = (maxp.z - minp.z) + 1
    core.chat_send_player(pname, string.format(
        "[Kinetica] Super Glued %dx%dx%d region (%d block%s)!",
        sx, sy, sz, volume, (volume == 1) and "" or "s"
    ))

    if not core.is_creative_enabled(pname) then
        itemstack:add_wear(math.floor(65535 / CONFIG.SUPER_GLUE_USES))
    end
    return itemstack
end

local function handle_glue_leftclick(itemstack, player, pointed_thing)
    if not player or not player:is_player() then
        return itemstack
    end
    local pname = player:get_player_name()

    -- 1. If currently selecting a box, left-clicking cancels the selection
    if player_selections[pname] then
        player_selections[pname] = nil
        remove_player_preview(pname)
        core.chat_send_player(pname, "[Kinetica] Super Glue selection cancelled.")
        return itemstack
    end

    -- 2. Raycast against all active glue boxes so you can left-click any glue box (even in mid-air) to remove it!
    local hit_box = find_raycasted_glue_box(player)
    if not hit_box and pointed_thing and pointed_thing.type == "node" and pointed_thing.under then
        local boxes = kinetica.get_glue_boxes_at(pointed_thing.under)
        if #boxes > 0 then
            hit_box = boxes[#boxes]
        end
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

-- =========================================================
-- REGISTER SUPER GLUE TOOL & CRAFTING RECIPES
-- =========================================================
local glue_icon = build_super_glue_icon()

core.register_tool(GLUE_TOOL_NAME, {
    description = "Super Glue\n" ..
                  "• Right-Click a block to start Corner 1, then Right-Click any block or in the air to glue!\n" ..
                  "• Overlap multiple glue boxes to build L-shapes, T-shapes, and custom contraptions.\n" ..
                  "• Glued Drills & Saws automatically store mined items into any Chest inside the glue!\n" ..
                  "• Left-Click a glued region while holding Super Glue to remove it.",
    inventory_image  = glue_icon,
    wield_image      = glue_icon,
    groups           = {kinetica_super_glue = 1},
    on_place         = handle_glue_rightclick,
    on_secondary_use = handle_glue_rightclick,
    on_use           = handle_glue_leftclick,
})

core.register_alias("kinetica:resin_glue", GLUE_TOOL_NAME)

local sheet_item  = core.registered_items["kinetica:iron_sheet"]    and "kinetica:iron_sheet"    or "mcl_core:iron_ingot"
local slime_item  = core.registered_items["mcl_mobitems:slimeball"] and "mcl_mobitems:slimeball" or "default:mese_crystal_fragment"
local nugget_item = core.registered_items["mcl_core:iron_nugget"]   and "mcl_core:iron_nugget"   or "default:steel_ingot"

core.register_craft({
    output = GLUE_TOOL_NAME,
    recipe = {
        {slime_item, nugget_item},
        {sheet_item, slime_item},
    },
})