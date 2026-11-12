kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

-- ============================================================================
-- TOP CONFIGURATION SECTION
-- ============================================================================
local BORE_SPIN_TUNING = {
    INVERT_SPIN_DIR = false,
}

local SOUND_CONFIG = {
    ENABLE_SOUND                   = true,
    SOUND_NAME                     = "driller",
    SOUND_FALLBACK                 = "default_dig_cracky",
    SOUND_BLOCK_BROKEN             = "default_dug_node",
    SOUND_GAIN                     = 0.22,
    SOUND_BROKEN_GAIN              = 0.85,
    SOUND_PITCH                    = 0.90,
    SCALE_PITCH_WITH_RPM           = true,
    MIN_PITCH                      = 0.75,
    MAX_PITCH                      = 1.35,
    SOUND_INTERVAL                 = 27.0,
    MAX_HEAR_DISTANCE              = 12,
    SOUND_ONLY_WHEN_DRILLING_BLOCK = false,
}

local CONFIG = {
    DRILL_FACES_PLAYER              = true,
    HIDE_INFOTEXT_WITHOUT_GLASSES   = false,
    ALLOW_BREAKING_KINETICA_BLOCKS  = true,
    MIN_RPM                         = 16,
    KU_PER_RPM                      = 4,
    MIN_KU                          = 32,
    MAX_KU                          = 128,
    TICK_INTERVAL                   = 0.25,
    BASE_TIME_AT_MIN_RPM            = 1.20,
    BASE_TIME_AT_512_RPM            = 0.20,
    SCALE_TIME_BY_HARDNESS          = true,
    MAX_MINEABLE_HARDNESS           = 55.0,
    MIN_DRILL_TIME_SEC              = 0.20,
    MAX_DRILL_TIME_SEC              = 10.0,
    COBBLE_GEN_SPEED_BOOST          = true,
    SPAWN_DRILL_SPARKS              = true,
    DEAL_ENTITY_DAMAGE              = true,
    DAMAGE_HP_AT_MIN_RPM            = 2,
    DAMAGE_HP_AT_512_RPM            = 8,
    DAMAGE_INTERVAL_SEC             = 0.80,
    DAMAGE_RADIUS                   = 0.78,
    BASE_SPIN_RAD_PER_SEC           = 4.0,
    MAX_SPIN_RAD_PER_SEC            = 24.0,
    TEX_DRILL_CASING_TOP            = "kinetica_drill_top.png",
    TEX_DRILL_CASING_BACK           = "kinetica_drill_back.png",
    TEX_DRILL_CASING_SIDE           = "kinetica_drill_side.png",
    TEX_DRILL_HEAD                  = "kinetica_drill_head.png",
    TEX_FALLBACK_TOP                = "mcl_stonecutter_top.png",
    TEX_FALLBACK_BACK               = "kinetica_chain_drive_front.png",
    TEX_FALLBACK_SIDE               = "kinetica_chain_drive_side.png",
    TEX_FALLBACK_DRILL_HEAD         = "mcl_stonecutter_saw.png",
    TEX_FALLBACK_COLLAR             = "mcl_stonecutter_bottom.png",
    TEX_SHAFT_OVERLAY               = "kinetica_shaft_connecting_overlay.png",
}

local IDLE_NAME       = "kinetica:mechanical_drill"
local WORLD_IDLE_NAME = "kinetica:mechanical_drill_casing"
local BIT_MESH_NODE   = "kinetica:mechanical_drill_bit_mesh"
local BIT_ENTITY_NAME = "kinetica:mechanical_drill_bit"

local BIT_MESH_BY_DIR = {
    UP    = BIT_MESH_NODE,
    DOWN  = BIT_MESH_NODE .. "_down",
    NORTH = BIT_MESH_NODE .. "_north",
    SOUTH = BIT_MESH_NODE .. "_south",
    EAST  = BIT_MESH_NODE .. "_east",
    WEST  = BIT_MESH_NODE .. "_west",
}

local IS_BIT_MESH_NODE = {}
for _, mname in pairs(BIT_MESH_BY_DIR) do
    IS_BIT_MESH_NODE[mname] = true
end

local active_bit_entities = {}

local function is_drill_node(name)
    if not name or IS_BIT_MESH_NODE[name] then return false end
    return (name == IDLE_NAME or string.sub(name, 1, #IDLE_NAME + 1) == (IDLE_NAME .. "_"))
end
kinetica.is_mechanical_drill = is_drill_node

local function file_exists(rel_path)
    local f = io.open(modpath .. "/" .. rel_path, "r")
    if f then f:close(); return true end
    return false
end

local TEX_TOP  = file_exists("textures/" .. CONFIG.TEX_DRILL_CASING_TOP)  and CONFIG.TEX_DRILL_CASING_TOP  or CONFIG.TEX_FALLBACK_TOP
local TEX_BACK = file_exists("textures/" .. CONFIG.TEX_DRILL_CASING_BACK) and CONFIG.TEX_DRILL_CASING_BACK or CONFIG.TEX_FALLBACK_BACK
local TEX_SIDE = file_exists("textures/" .. CONFIG.TEX_DRILL_CASING_SIDE) and CONFIG.TEX_DRILL_CASING_SIDE or CONFIG.TEX_FALLBACK_SIDE
local TEX_SAW  = file_exists("textures/" .. CONFIG.TEX_DRILL_HEAD)        and CONFIG.TEX_DRILL_HEAD        or CONFIG.TEX_FALLBACK_DRILL_HEAD

local ACTIVE_DRILL_SOUND = (SOUND_CONFIG.SOUND_NAME ~= "" and file_exists("sounds/" .. SOUND_CONFIG.SOUND_NAME .. ".ogg"))
    and SOUND_CONFIG.SOUND_NAME
    or  SOUND_CONFIG.SOUND_FALLBACK

local function play_drill_active_sound(pos, meta, rpm, can_drill, dt)
    if not SOUND_CONFIG.ENABLE_SOUND or not ACTIVE_DRILL_SOUND or ACTIVE_DRILL_SOUND == "" then return end
    if SOUND_CONFIG.SOUND_ONLY_WHEN_DRILLING_BLOCK and not can_drill then return end

    local sound_timer = meta:get_float("drill_sound_timer") + (dt or CONFIG.TICK_INTERVAL)
    if sound_timer < (SOUND_CONFIG.SOUND_INTERVAL or 1.50) then
        meta:set_float("drill_sound_timer", sound_timer)
        return
    end
    meta:set_float("drill_sound_timer", 0)

    local pitch = SOUND_CONFIG.SOUND_PITCH or 0.90
    if SOUND_CONFIG.SCALE_PITCH_WITH_RPM then
        local t = kinetica.api and kinetica.api.math.rpm_factor(rpm, CONFIG.MIN_RPM, 512) or 0
        local min_p = SOUND_CONFIG.MIN_PITCH or 0.75
        local max_p = SOUND_CONFIG.MAX_PITCH or 1.35
        pitch = min_p + t * (max_p - min_p)
    end

    core.sound_play(ACTIVE_DRILL_SOUND, {
        pos               = pos,
        max_hear_distance = SOUND_CONFIG.MAX_HEAR_DISTANCE or 12,
        gain              = SOUND_CONFIG.SOUND_GAIN or 0.22,
        pitch             = pitch,
    }, true)
end

local function get_drill_demand_ku(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then return CONFIG.MIN_KU end
    return math.min(CONFIG.MAX_KU, math.max(CONFIG.MIN_KU, math.floor(rpm * CONFIG.KU_PER_RPM)))
end

local AXIS_TO_DRILL_DIR = {
    [0] = {x =  0, y =  1, z =  0}, [1] = {x =  0, y =  0, z =  1},
    [2] = {x =  0, y =  0, z = -1}, [3] = {x =  1, y =  0, z =  0},
    [4] = {x = -1, y =  0, z =  0}, [5] = {x =  0, y = -1, z =  0},
}

local ALL_6_DIRS = {
    {x =  1, y =  0, z =  0}, {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0}, {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1}, {x =  0, y =  0, z = -1},
}

local function get_drill_dir(param2)
    local axisdir = math.floor(((param2 or 0) % 24) / 4)
    local d = AXIS_TO_DRILL_DIR[axisdir] or AXIS_TO_DRILL_DIR[0]
    return {x = d.x, y = d.y, z = d.z}
end

local function get_back_dir(param2)
    local d = get_drill_dir(param2)
    return {x = -d.x, y = -d.y, z = -d.z}
end

local function get_drill_dir_key(dir)
    if dir.y > 0 then return "UP"
    elseif dir.y < 0 then return "DOWN"
    elseif dir.z > 0 then return "NORTH"
    elseif dir.z < 0 then return "SOUTH"
    elseif dir.x > 0 then return "EAST"
    else return "WEST" end
end

local function get_flipped_drill_param2(drill_dir)
    local axisdir = 0
    if drill_dir.y > 0 then axisdir = 0
    elseif drill_dir.y < 0 then axisdir = 5
    elseif drill_dir.z > 0 then axisdir = 1
    elseif drill_dir.z < 0 then axisdir = 2
    elseif drill_dir.x > 0 then axisdir = 3
    elseif drill_dir.x < 0 then axisdir = 4 end

    if axisdir >= 1 and axisdir <= 4 then
        for rot = 0, 3 do
            local p2 = axisdir * 4 + rot
            local zdir = core.facedir_to_dir(p2)
            if zdir and zdir.y == 1 then return p2 end
        end
    end
    return axisdir * 4
end

local function look_to_unit_dir(placer)
    local look = placer and placer:get_look_dir() or {x = 0, y = 0, z = 1}
    local ax, ay, az = math.abs(look.x), math.abs(look.y), math.abs(look.z)
    if ay > ax and ay > az then return {x = 0, y = (look.y > 0) and 1 or -1, z = 0}
    elseif ax >= az then return {x = (look.x > 0) and 1 or -1, y = 0, z = 0}
    else return {x = 0, y = 0, z = (look.z > 0) and 1 or -1} end
end

local function get_active_drill_node_name(rpm, spin_dir)
    local dir_tag = (spin_dir and spin_dir < 0) and "ccw" or "cw"
    if kinetica.api and kinetica.api.registration and kinetica.api.registration.ANIM_TIERS then
        local clamped = math.min(kinetica.MAX_RPM_CAP or 3072, math.max(0, rpm or 0))
        for _, tier in ipairs(kinetica.api.registration.ANIM_TIERS) do
            if clamped <= tier.max_rpm then
                local cand = IDLE_NAME .. "_" .. tier.name .. "_" .. dir_tag
                if core.registered_nodes[cand] then return cand end
            end
        end
    end
    local fallback = IDLE_NAME .. "_active_" .. dir_tag
    if core.registered_nodes[fallback] then return fallback end
    return WORLD_IDLE_NAME
end

local drill_bore_boxes = {
    {-5/16,    0/16,   -5/16,    5/16,    1.5/16,  5/16},
    {-4/16,    1.5/16, -4/16,    4/16,    3.5/16,  4/16},
    {-6/16,    1.2/16, -1/16,    6/16,    3.4/16,  1/16},
    {-1/16,    1.2/16, -6/16,    1/16,    3.4/16,  6/16},
    {-3/16,    3.5/16, -3/16,    3/16,    5.5/16,  3/16},
    {-4.5/16,  3.5/16, -0.85/16, 4.5/16,  5.4/16,  0.85/16},
    {-0.85/16, 3.5/16, -4.5/16,  0.85/16, 5.4/16,  4.5/16},
    {-2/16,    5.5/16, -2/16,    2/16,    7.0/16,  2/16},
    {-3/16,    5.5/16, -0.65/16, 3/16,    6.9/16,  0.65/16},
    {-0.65/16, 5.5/16, -3/16,    0.65/16, 6.9/16,  3/16},
    {-1/16,    7.0/16, -1/16,    1/16,    8.0/16,  1/16},
}

-- Builds the exact 11-box bore geometry oriented along any of the 6 cardinal directions
-- so every direction spins purely on a single axis with zero gimbal lock!
local function build_directional_bore_boxes(dir_key)
    local out = {}
    for _, b in ipairs(drill_bore_boxes) do
        local u1, a1, v1, u2, a2, v2 = b[1], b[2], b[3], b[4], b[5], b[6]
        if dir_key == "UP" then
            out[#out + 1] = {u1,  a1, v1, u2,  a2, v2}
        elseif dir_key == "DOWN" then
            out[#out + 1] = {u1, -a2, v1, u2, -a1, v2}
        elseif dir_key == "NORTH" then
            out[#out + 1] = {u1, v1,  a1, u2, v2,  a2}
        elseif dir_key == "SOUTH" then
            out[#out + 1] = {u1, v1, -a2, u2, v2, -a1}
        elseif dir_key == "EAST" then
            out[#out + 1] = { a1, u1, v1,  a2, u2, v2}
        elseif dir_key == "WEST" then
            out[#out + 1] = {-a2, u1, v1, -a1, u2, v2}
        end
    end
    return out
end

-- Full 3D nodebox (casing + bore) used ONLY for the inventory item (`kinetica:mechanical_drill`)
local drill_full_3d_nodebox = {
    type  = "fixed",
    fixed = {
        {-8/16, -8/16, -8/16, 8/16, 0/16, 8/16},
    },
}
for _, box in ipairs(drill_bore_boxes) do
    drill_full_3d_nodebox.fixed[#drill_full_3d_nodebox.fixed + 1] = box
end

-- Casing-only nodebox used for all placed blocks in the world so only the 3D entity renders the bore
local CASING_ONLY_NODEBOX = {
    type  = "fixed",
    fixed = {
        {-8/16, -8/16, -8/16, 8/16, 0/16, 8/16},
    },
}

local bit_saw_frame = TEX_SAW .. "^[sheet:1x3:0,0"
local bit_flute_tex = "(" .. CONFIG.TEX_FALLBACK_COLLAR .. ")^(" .. bit_saw_frame .. ")"
local bit_top_tex   = "(" .. CONFIG.TEX_FALLBACK_COLLAR .. ")^(" .. bit_saw_frame .. ")"
local esc_saw_frame = TEX_SAW .. "\\^[sheet\\:1x3\\:0,0"
local inv_side_tex  = "[combine:16x16:0,0=" .. CONFIG.TEX_FALLBACK_COLLAR .. ":0,0=" .. esc_saw_frame .. ":0,8=" .. TEX_SIDE

local casing_top_tex  = TEX_TOP
local casing_side_tex = TEX_SIDE

local function get_directional_bore_tiles(dir_key)
    local col = CONFIG.TEX_FALLBACK_COLLAR
    if dir_key == "UP" then
        return {bit_top_tex, col, bit_flute_tex, bit_flute_tex, bit_flute_tex, bit_flute_tex}
    elseif dir_key == "DOWN" then
        return {col, bit_top_tex, bit_flute_tex, bit_flute_tex, bit_flute_tex, bit_flute_tex}
    elseif dir_key == "NORTH" then
        return {bit_flute_tex, bit_flute_tex, bit_flute_tex, bit_flute_tex, bit_top_tex, col}
    elseif dir_key == "SOUTH" then
        return {bit_flute_tex, bit_flute_tex, bit_flute_tex, bit_flute_tex, col, bit_top_tex}
    elseif dir_key == "EAST" then
        return {bit_flute_tex, bit_flute_tex, bit_top_tex, col, bit_flute_tex, bit_flute_tex}
    else -- WEST
        return {bit_flute_tex, bit_flute_tex, col, bit_top_tex, bit_flute_tex, bit_flute_tex}
    end
end

for dir_key, mesh_name in pairs(BIT_MESH_BY_DIR) do
    core.register_node(mesh_name, {
        description         = "Mechanical Drill Bit Mesh (" .. dir_key .. ")",
        drawtype            = "nodebox",
        paramtype           = "light",
        sunlight_propagates = true,
        use_texture_alpha   = "clip",
        tiles               = get_directional_bore_tiles(dir_key),
        node_box            = {type = "fixed", fixed = build_directional_bore_boxes(dir_key)},
        groups              = {not_in_creative_inventory = 1},
    })
end

-- Pure single-axis rotation: 2 of the 3 Euler angles are ALWAYS 0, eliminating gimbal lock!
local function compute_bit_euler(drill_dir, angle)
    local eff_angle = BORE_SPIN_TUNING.INVERT_SPIN_DIR and (-angle) or angle
    if drill_dir.y > 0 then
        return {x = 0, y = eff_angle, z = 0}
    elseif drill_dir.y < 0 then
        return {x = 0, y = -eff_angle, z = 0}
    elseif drill_dir.z > 0 then
        return {x = 0, y = 0, z = eff_angle}
    elseif drill_dir.z < 0 then
        return {x = 0, y = 0, z = -eff_angle}
    elseif drill_dir.x > 0 then
        return {x = eff_angle, y = 0, z = 0}
    else
        return {x = -eff_angle, y = 0, z = 0}
    end
end

core.register_entity(BIT_ENTITY_NAME, {
    initial_properties = {
        physical             = false,
        collide_with_objects = false,
        pointable            = false,
        visual               = "wielditem",
        wield_item           = BIT_MESH_NODE,
        visual_size          = {x = 0.6667, y = 0.6667, z = 0.6667},
        static_save          = false,
        shaded               = true,
    },
    on_activate = function(self)
        self.object:set_armor_groups({immortal = 1})
        self.angle     = 0
        self.speed     = 0
        self.drill_dir = {x = 0, y = 1, z = 0}
        self.dir_key   = "UP"
        self._check_acc = 0

        local pos = self.object:get_pos()
        if pos then
            local bpos = vector.round(pos)
            local node = core.get_node(bpos)
            if is_drill_node(node.name) then
                local hk = core.hash_node_position(bpos)
                if active_bit_entities[hk] and active_bit_entities[hk] ~= self.object and active_bit_entities[hk]:get_luaentity() then
                    self.object:remove()
                    return
                end
                active_bit_entities[hk] = self.object
                self.drill_dir = get_drill_dir(node.param2)
                self.dir_key   = get_drill_dir_key(self.drill_dir)
                local want_mesh = BIT_MESH_BY_DIR[self.dir_key] or BIT_MESH_NODE
                self.object:set_properties({wield_item = want_mesh})
                self.object:set_rotation(compute_bit_euler(self.drill_dir, self.angle))
            else
                self.object:remove()
            end
        end
    end,
    on_step = function(self, dtime)
        self._check_acc = (self._check_acc or 0) + dtime
        if self._check_acc >= 1.0 then
            self._check_acc = 0
            local pos = self.object:get_pos()
            if not pos or not is_drill_node(core.get_node(vector.round(pos)).name) then
                if pos then active_bit_entities[core.hash_node_position(vector.round(pos))] = nil end
                self.object:remove()
                return
            end
        end
        if self.speed and self.speed ~= 0 then
            self.angle = (self.angle + self.speed * dtime) % (math.pi * 2)
            self.object:set_rotation(compute_bit_euler(self.drill_dir, self.angle))
        end
    end,
})

local function remove_drill_bit_entity(pos)
    local hk = core.hash_node_position(pos)
    local cached = active_bit_entities[hk]
    if cached then
        cached:remove()
        active_bit_entities[hk] = nil
    end
    for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.65)) do
        local le = obj:get_luaentity()
        if le and le.name == BIT_ENTITY_NAME then
            obj:remove()
        end
    end
end

local function sync_drill_bit_entity(pos, param2, rpm, spin_dir)
    local hk        = core.hash_node_position(pos)
    local drill_dir = get_drill_dir(param2)
    local dir_key   = get_drill_dir_key(drill_dir)
    local want_mesh = BIT_MESH_BY_DIR[dir_key] or BIT_MESH_NODE
    local bit_obj   = active_bit_entities[hk]

    if not (bit_obj and bit_obj:get_luaentity()) then
        bit_obj = nil
        for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.65)) do
            local le = obj:get_luaentity()
            if le and le.name == BIT_ENTITY_NAME then
                if not bit_obj then bit_obj = obj else obj:remove() end
            end
        end
        if not bit_obj then bit_obj = core.add_entity(pos, BIT_ENTITY_NAME) end
        active_bit_entities[hk] = bit_obj
    else
        for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.65)) do
            local le = obj:get_luaentity()
            if le and le.name == BIT_ENTITY_NAME and obj ~= bit_obj then
                obj:remove()
            end
        end
    end

    if bit_obj then
        local le = bit_obj:get_luaentity()
        if le then
            local spd = 0
            if rpm and rpm >= CONFIG.MIN_RPM and spin_dir and spin_dir ~= 0 then
                local ratio = kinetica.api and kinetica.api.math.rpm_factor(rpm, CONFIG.MIN_RPM, 512) or 0
                spd = (CONFIG.BASE_SPIN_RAD_PER_SEC + ratio * (CONFIG.MAX_SPIN_RAD_PER_SEC - CONFIG.BASE_SPIN_RAD_PER_SEC)) * spin_dir
            end
            local dir_changed = (le.dir_key ~= dir_key) or (not le.drill_dir) or
                                (le.drill_dir.x ~= drill_dir.x or le.drill_dir.y ~= drill_dir.y or le.drill_dir.z ~= drill_dir.z)
            local spd_changed = math.abs((le.speed or 0) - spd) > 0.01

            le.drill_dir = drill_dir
            le.dir_key   = dir_key
            le.speed     = spd

            if dir_changed then
                bit_obj:set_properties({wield_item = want_mesh})
            end
            if dir_changed or (spd == 0 and spd_changed) then
                bit_obj:set_rotation(compute_bit_euler(drill_dir, le.angle or 0))
            end
        end
    end
end

local SILK_TO_NORMAL_DROPS = {
    ["mcl_core:stone"]                       = "mcl_core:cobble",
    ["mcl_deepslate:deepslate"]              = "mcl_deepslate:deepslate_cobbled",
    ["mcl_core:dirt_with_grass"]             = "mcl_core:dirt",
    ["mcl_core:stone_with_coal"]             = "mcl_core:coal_lump",
    ["mcl_deepslate:deepslate_with_coal"]    = "mcl_core:coal_lump",
    ["mcl_core:stone_with_iron"]             = "mcl_raw_ores:raw_iron",
    ["mcl_deepslate:deepslate_with_iron"]    = "mcl_raw_ores:raw_iron",
    ["mcl_copper:stone_with_copper"]         = "mcl_copper:raw_copper 2",
    ["mcl_deepslate:deepslate_with_copper"]  = "mcl_copper:raw_copper 2",
    ["mcl_core:stone_with_gold"]             = "mcl_raw_ores:raw_gold",
    ["mcl_deepslate:deepslate_with_gold"]    = "mcl_raw_ores:raw_gold",
    ["mcl_core:stone_with_diamond"]          = "mcl_core:diamond",
    ["mcl_core:stone_with_emerald"]          = "mcl_core:emerald",
    ["mcl_core:stone_with_lapis"]            = "mcl_core:lapis 4",
    ["mcl_core:stone_with_redstone"]         = "mcl_redstone:redstone 4",
    ["mcl_nether:quartz_ore"]                = "mcl_nether:quartz",
}

local function get_guaranteed_drill_drops(target_node)
    local nname = target_node.name
    if SILK_TO_NORMAL_DROPS[nname] then
        local mapped = SILK_TO_NORMAL_DROPS[nname]
        local base_item = string.match(mapped, "^([^%s]+)")
        if core.registered_items[base_item] then return {mapped} end
    end
    local tool_name = core.registered_items["mcl_tools:pick_diamond"] and "mcl_tools:pick_diamond" or "default:pick_diamond"
    local drops = core.get_node_drops(nname, tool_name)
    if drops and #drops > 0 then return drops end
    local def = core.registered_nodes[nname]
    if def and def.drop ~= "" then return {def.drop} end
    return {nname}
end

local function is_ore_block(name)
    if not name then return false end
    return string.find(name, "_ore") ~= nil or string.find(name, "stone_with_") ~= nil or string.find(name, "deepslate_with_") ~= nil
end

local PROTECTED_TECHNICAL_NODES = {
    ["kinetica:piston_head"]        = true,
    ["kinetica:piston_head_sticky"] = true,
}
for _, mname in pairs(BIT_MESH_BY_DIR) do
    PROTECTED_TECHNICAL_NODES[mname] = true
end

local function is_drillable_node(name)
    if not name or name == "air" or name == "ignore" or PROTECTED_TECHNICAL_NODES[name] then return false, 0 end
    if not CONFIG.ALLOW_BREAKING_KINETICA_BLOCKS and string.sub(name, 1, 9) == "kinetica:" then return false, 0 end

    local def = core.registered_nodes[name]
    if not def or def.diggable == false or (def.liquidtype and def.liquidtype ~= "none") then return false, 0 end
    if core.get_item_group(name, "water") > 0 or core.get_item_group(name, "lava") > 0 or core.get_item_group(name, "fire") > 0 then return false, 0 end

    local hardness = def._mcl_hardness
    if hardness and (hardness < 0 or hardness > CONFIG.MAX_MINEABLE_HARDNESS) then return false, 0 end
    if core.get_item_group(name, "unbreakable") > 0 or string.find(name, "bedrock") or string.find(name, "barrier") then return false, 0 end
    if def.groups and def.groups.container and def.groups.container > 0 then return false, 0 end

    return true, math.max(0.2, tonumber(hardness) or 1.5)
end

local function is_cobble_gen_target(target_pos, target_name)
    if not CONFIG.COBBLE_GEN_SPEED_BOOST then return false end
    if not (string.find(target_name, "cobble") or string.find(target_name, "stone") or string.find(target_name, "basalt")) then return false end
    for _, d in ipairs(ALL_6_DIRS) do
        local nn = core.get_node({x = target_pos.x + d.x, y = target_pos.y + d.y, z = target_pos.z + d.z}).name
        if core.get_item_group(nn, "lava") > 0 or string.find(nn, "water") then return true end
    end
    return false
end

local function get_required_drill_seconds(rpm, hardness, is_cobble_gen)
    local rfactor = kinetica.api and kinetica.api.math.rpm_factor(rpm, CONFIG.MIN_RPM, 512) or 0
    local base = CONFIG.BASE_TIME_AT_MIN_RPM + rfactor * (CONFIG.BASE_TIME_AT_512_RPM - CONFIG.BASE_TIME_AT_MIN_RPM)
    if CONFIG.SCALE_TIME_BY_HARDNESS and hardness then
        base = base * math.max(0.35, math.pow(hardness / 1.5, 0.65))
    end
    if is_cobble_gen then base = base * 0.65 end
    return math.min(CONFIG.MAX_DRILL_TIME_SEC, math.max(CONFIG.MIN_DRILL_TIME_SEC, base))
end

local function deliver_mined_drops(drill_pos, drill_node, target_pos, drops)
    for _, item in ipairs(drops) do
        local stack = ItemStack(item)
        if not stack:is_empty() then
            if kinetica.api and kinetica.api.contraptions and kinetica.api.contraptions.try_store_in_glued_contraption then
                stack = kinetica.api.contraptions.try_store_in_glued_contraption(drill_pos, stack)
            end

            if not stack:is_empty() then
                local below = {x = target_pos.x, y = target_pos.y - 1, z = target_pos.z}
                local bname = core.get_node(below).name
                if (kinetica.is_belt and kinetica.is_belt(bname)) or bname == "kinetica:depot" then
                    core.add_item({x = below.x, y = below.y + 0.32, z = below.z}, stack)
                else
                    core.add_item(target_pos, stack)
                end
            end
        end
    end
end

local function deal_drill_entity_damage(pos, head_pos, rpm)
    if not CONFIG.DEAL_ENTITY_DAMAGE then return end
    local meta = core.get_meta(pos)
    local dmg_acc = meta:get_float("dmg_timer") + CONFIG.TICK_INTERVAL
    if dmg_acc < CONFIG.DAMAGE_INTERVAL_SEC then
        meta:set_float("dmg_timer", dmg_acc)
        return
    end
    meta:set_float("dmg_timer", 0)

    local rfactor = kinetica.api and kinetica.api.math.rpm_factor(rpm, CONFIG.MIN_RPM, 512) or 0
    local hp_dmg = math.floor(CONFIG.DAMAGE_HP_AT_MIN_RPM + rfactor * (CONFIG.DAMAGE_HP_AT_512_RPM - CONFIG.DAMAGE_HP_AT_MIN_RPM) + 0.5)
    local mid_pt = {x = (pos.x + head_pos.x) * 0.5, y = (pos.y + head_pos.y) * 0.5, z = (pos.z + head_pos.z) * 0.5}

    local hit_seen = {}
    for _, scan_pt in ipairs({mid_pt, head_pos}) do
        for _, obj in ipairs(core.get_objects_inside_radius(scan_pt, CONFIG.DAMAGE_RADIUS)) do
            if not hit_seen[obj] then
                hit_seen[obj] = true
                local luaent = obj:get_luaentity()
                if obj:is_player() or (luaent and (luaent.is_mob or luaent._cmi_is_mob or luaent.health)) then
                    obj:punch(obj, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = hp_dmg}}, nil)
                end
            end
        end
    end
end

local function spawn_drilling_particles(target_pos, target_node, hardness)
    local ndef = core.registered_nodes[target_node.name]
    local tile = (ndef and ndef.tiles and ndef.tiles[1])
    local tex  = (type(tile) == "table" and tile.name) or (type(tile) == "string" and tile) or CONFIG.TEX_FALLBACK_COLLAR

    core.add_particlespawner({
        amount = 4, time = CONFIG.TICK_INTERVAL,
        minpos = {x = target_pos.x - 0.28, y = target_pos.y - 0.28, z = target_pos.z - 0.28},
        maxpos = {x = target_pos.x + 0.28, y = target_pos.y + 0.28, z = target_pos.z + 0.28},
        minvel = {x = -0.9, y = 0.4, z = -0.9}, maxvel = {x =  0.9, y = 1.6, z =  0.9},
        minexptime = 0.20, maxexptime = 0.48, minsize = 1.1, maxsize = 2.1, texture = tex,
    })
    if CONFIG.SPAWN_DRILL_SPARKS and (hardness >= 2.0 or is_ore_block(target_node.name)) then
        core.add_particlespawner({
            amount = 2, time = CONFIG.TICK_INTERVAL,
            minpos = {x = target_pos.x - 0.22, y = target_pos.y - 0.22, z = target_pos.z - 0.22},
            maxpos = {x = target_pos.x + 0.22, y = target_pos.y + 0.22, z = target_pos.z + 0.22},
            minvel = {x = -1.4, y = 0.6, z = -1.4}, maxvel = {x =  1.4, y = 2.0, z =  1.4},
            minexptime = 0.15, maxexptime = 0.35, minsize = 0.9, maxsize = 1.5, glow = 13, texture = CONFIG.TEX_SHAFT_OVERLAY .. "^[sheet:1x4:0,0^[colorize:#ffb300:220",
        })
    end
end

local function format_drill_glasses_info(pos, node)
    local meta      = core.get_meta(pos)
    local is_pow, uni_rpm, uni_sup, uni_ava, _ = kinetica.get_node_power(pos, meta)
    local rpm       = is_pow and uni_rpm or meta:get_float("rpm")
    local supply_ku = is_pow and uni_sup or meta:get_int("network_supply_ku")
    local avail_ku  = is_pow and uni_ava or meta:get_int("rotational_power")
    local demand_ku = meta:get_int("machine_demand_ku")
    if demand_ku <= 0 then demand_ku = get_drill_demand_ku(rpm) end

    local is_over   = (meta:get_int("network_overstressed") == 1)
    local is_active = is_pow and (rpm >= CONFIG.MIN_RPM)
    local low_rpm   = is_pow and (rpm > 0 and rpm < CONFIG.MIN_RPM)

    local target_nm = meta:get_string("drill_target_name")
    local pct       = meta:get_int("drill_pct")

    local state_str = "IDLE"
    if is_over then state_str = "OVERSTRESSED!"
    elseif is_active then state_str = (target_nm ~= "") and string.format("DRILLING (%d%%)", pct) or "ACTIVE (Spinning)"
    elseif low_rpm then state_str = string.format("TOO SLOW (Min %d RPM)", CONFIG.MIN_RPM) end

    local short_target = "None"
    if target_nm ~= "" then
        local tdef = core.registered_nodes[target_nm]
        short_target = (tdef and tdef.description) and string.match(tdef.description, "^[^\n%(]+") or target_nm
        short_target = string.gsub(short_target, "%s+$", "")
    end

    local T = kinetica.api and kinetica.api.telemetry
    if not T then return "" end

    return table.concat({
        "┌─ ENGINEER'S GLASSES ──────────────",
        "│  Machine: Mechanical Drill",
        "│  ● STATE: " .. state_str,
        "├─ KINETIC NETWORK ─────────────────",
        T.kv_row("Speed",    string.format("%.1f RPM", is_active and rpm or 0)),
        T.kv_row("Stress",   string.format("-%d KU Load (%d / %d KU Avail)", is_active and demand_ku or 0, avail_ku, supply_ku)),
        "├─ MACHINE DETAILS ─────────────────",
        T.kv_row("Target",   short_target),
        T.kv_row("Progress", T.draw_progress_bar(pct, 100)),
        "└───────────────────────────────────",
    }, "\n")
end

if kinetica.api and kinetica.api.telemetry then
    kinetica.api.telemetry.register_formatter(IDLE_NAME, format_drill_glasses_info)
end

local function place_mechanical_drill(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then return itemstack end
    local under_node = core.get_node(pointed_thing.under)
    local under_def  = core.registered_nodes[under_node.name]
    local sneaking   = placer and placer:is_player() and placer:get_player_control().sneak
    if under_def and under_def.on_rightclick and not sneaking and not is_drill_node(under_node.name) then
        return under_def.on_rightclick(pointed_thing.under, under_node, placer, itemstack, pointed_thing) or itemstack
    end

    local drill_dir = nil
    if not sneaking and is_drill_node(under_node.name) then
        drill_dir = get_drill_dir(under_node.param2)
    elseif not sneaking then
        local diff = {x = pointed_thing.above.x - pointed_thing.under.x, y = pointed_thing.above.y - pointed_thing.under.y, z = pointed_thing.above.z - pointed_thing.under.z}
        if (kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(under_node.name)) or under_node.name == "kinetica:piston_head" or under_node.name == "kinetica:piston_head_sticky" or (kinetica.is_sticky_contraption_frame and kinetica.is_sticky_contraption_frame(under_node.name)) or (kinetica.has_axle_port and kinetica.has_axle_port(under_node, diff, pointed_thing.under)) then
            drill_dir = diff
        end
    end

    if not drill_dir then
        local ldir = look_to_unit_dir(placer)
        local invert = CONFIG.DRILL_FACES_PLAYER
        if sneaking then invert = not invert end
        drill_dir = invert and {x = -ldir.x, y = -ldir.y, z = -ldir.z} or ldir
    end

    local target_p2 = get_flipped_drill_param2(drill_dir)
    local placed_stack, place_pos = core.item_place_node(itemstack, placer, pointed_thing, target_p2)
    if place_pos then
        local meta = core.get_meta(place_pos)
        meta:set_string("owner", (placer and placer.get_player_name and placer:get_player_name() or "$unknown"))
        meta:set_float("drill_sound_timer", 0)
        core.swap_node(place_pos, {name = WORLD_IDLE_NAME, param2 = target_p2})
        sync_drill_bit_entity(place_pos, target_p2, 0, 0)
    end
    return placed_stack
end

local function on_drill_rightclick(pos, node, clicker, itemstack, pointed_thing)
    if not clicker or not clicker:is_player() then return itemstack end
    if itemstack and not itemstack:is_empty() then
        local wname = itemstack:get_name()
        if is_drill_node(wname) then return place_mechanical_drill(itemstack, clicker, pointed_thing)
        elseif core.registered_nodes[wname] or string.find(wname, "belt_item") then return core.item_place_node(itemstack, clicker, pointed_thing) end
    end
    return itemstack
end

local function set_drill_idle(pos, node, reason_text)
    node = node or core.get_node(pos)
    if is_drill_node(node.name) and node.name ~= WORLD_IDLE_NAME then
        core.swap_node(pos, {name = WORLD_IDLE_NAME, param2 = node.param2})
        node = core.get_node(pos)
    end

    local meta = core.get_meta(pos)
    meta:set_float("drill_progress", 0)
    meta:set_int("drill_pct", 0)
    meta:set_string("drill_target_name", "")
    meta:set_float("drill_sound_timer", 0)

    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
    else
        meta:set_string("infotext", reason_text or string.format("Mechanical Drill: Idle (Min %d RPM)", CONFIG.MIN_RPM))
    end
    sync_drill_bit_entity(pos, node.param2, 0, 0)
    meta:set_string("glasses_info", format_drill_glasses_info(pos, node))
end

local function wake_drill(pos, node, rpm, spin_dir, demand_ku, avail_ku, supply_ku)
    node = node or core.get_node(pos)
    if rpm < CONFIG.MIN_RPM then
        set_drill_idle(pos, node, string.format("Mechanical Drill: Too Slow (%.0f RPM / Min %d RPM)", rpm or 0, CONFIG.MIN_RPM))
        return
    end

    local eff_spin = (spin_dir == 0 or not spin_dir) and 1 or spin_dir
    local target_name = get_active_drill_node_name(rpm, eff_spin)
    if node.name ~= target_name then
        core.swap_node(pos, {name = target_name, param2 = node.param2})
        node = core.get_node(pos)
    end

    local meta = core.get_meta(pos)
    meta:set_float("rpm", rpm)
    meta:set_int("spin_dir", eff_spin)
    if avail_ku then meta:set_int("rotational_power", avail_ku) end
    if supply_ku and supply_ku > 0 then meta:set_int("network_supply_ku", supply_ku) end
    if demand_ku and demand_ku > 0 then meta:set_int("machine_demand_ku", demand_ku) end
    meta:set_int("lit_until", math.floor(core.get_gametime()) + 4)

    sync_drill_bit_entity(pos, node.param2, rpm, eff_spin)
    local timer = core.get_node_timer(pos)
    if not timer:is_started() then timer:start(CONFIG.TICK_INTERVAL) end
end

local function drill_timer(pos, elapsed)
    local now  = math.floor(core.get_gametime())
    local meta = core.get_meta(pos)
    local node = core.get_node(pos)

    if now >= meta:get_int("lit_until") then
        if kinetica.api and kinetica.api.network.update then
            local bdir = get_back_dir(node.param2)
            local bpos = {x = pos.x + bdir.x, y = pos.y + bdir.y, z = pos.z + bdir.z}
            if kinetica.is_kinetic_node and kinetica.is_kinetic_node(core.get_node(bpos).name) then
                kinetica.api.network.update(bpos)
            else
                kinetica.api.network.update(pos)
            end
        end
        node = core.get_node(pos)
    end

    local is_powered, rpm, supply_ku, avail_ku, spin_dir = kinetica.get_node_power(pos, meta)
    if not is_powered or rpm < CONFIG.MIN_RPM then
        set_drill_idle(pos, node)
        return false
    end

    local demand_ku = meta:get_int("machine_demand_ku")
    if demand_ku <= 0 then demand_ku = get_drill_demand_ku(rpm) end

    local target_node_name = get_active_drill_node_name(rpm, spin_dir)
    if node.name ~= target_node_name then
        core.swap_node(pos, {name = target_node_name, param2 = node.param2})
        node = core.get_node(pos)
    end

    sync_drill_bit_entity(pos, node.param2, rpm, spin_dir)

    local drill_dir  = get_drill_dir(node.param2)
    local target_pos = {x = pos.x + drill_dir.x, y = pos.y + drill_dir.y, z = pos.z + drill_dir.z}

    deal_drill_entity_damage(pos, target_pos, rpm)

    local target_node         = core.get_node(target_pos)
    local can_drill, hardness = is_drillable_node(target_node.name)

    play_drill_active_sound(pos, meta, rpm, can_drill, CONFIG.TICK_INTERVAL)

    if can_drill then
        local prev_target = meta:get_string("drill_target_name")
        local progress    = meta:get_float("drill_progress")
        if prev_target ~= target_node.name then
            progress = 0
            meta:set_string("drill_target_name", target_node.name)
        end

        local cobble_boost = is_cobble_gen_target(target_pos, target_node.name)
        local req_time     = get_required_drill_seconds(rpm, hardness, cobble_boost)
        progress           = progress + CONFIG.TICK_INTERVAL

        spawn_drilling_particles(target_pos, target_node, hardness)

        if progress >= req_time then
            meta:set_float("drill_progress", 0)
            meta:set_int("drill_pct", 0)
            meta:set_string("drill_target_name", "")

            if not core.is_protected(target_pos, meta:get_string("owner")) then
                local broken_name = target_node.name
                local drops = get_guaranteed_drill_drops(target_node)
                core.remove_node(target_pos)
                core.check_for_falling(target_pos)

                if kinetica.api and kinetica.api.network.schedule_update and string.sub(broken_name, 1, 9) == "kinetica:" then
                    kinetica.api.network.schedule_update(target_pos)
                end

                deliver_mined_drops(pos, node, target_pos, drops)
                if SOUND_CONFIG.SOUND_BLOCK_BROKEN and SOUND_CONFIG.SOUND_BLOCK_BROKEN ~= "" then
                    core.sound_play(SOUND_CONFIG.SOUND_BLOCK_BROKEN, {pos = target_pos, max_hear_distance = 16, gain = SOUND_CONFIG.SOUND_BROKEN_GAIN or 0.85}, true)
                end
            end
        else
            meta:set_float("drill_progress", progress)
            meta:set_int("drill_pct", math.min(99, math.floor((progress / math.max(0.05, req_time)) * 100)))
        end

        if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then meta:set_string("infotext", "") else
            meta:set_string("infotext", string.format("Mechanical Drill: DRILLING %d%% (-%d KU | %d/%d KU avail | %.0f RPM)", meta:get_int("drill_pct"), demand_ku, avail_ku, supply_ku, rpm))
        end
    else
        meta:set_float("drill_progress", 0)
        meta:set_int("drill_pct", 0)
        meta:set_string("drill_target_name", "")
        if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then meta:set_string("infotext", "") else
            meta:set_string("infotext", string.format("Mechanical Drill: ACTIVE (-%d KU | %d/%d KU avail | %.0f RPM)", demand_ku, avail_ku, supply_ku, rpm))
        end
    end

    meta:set_string("glasses_info", format_drill_glasses_info(pos, node))
    core.get_node_timer(pos):start(CONFIG.TICK_INTERVAL)
    return false
end

local function make_drill_back_anim(reverse, anim_length)
    local bg = TEX_BACK
    local ov = CONFIG.TEX_SHAFT_OVERLAY
    local bg_strip = "[combine:16x64:0,0=" .. bg .. ":0,16=" .. bg .. ":0,32=" .. bg .. ":0,48=" .. bg
    local ov_strip = ov
    if reverse then
        ov_strip = "[combine:16x64:0,0=" .. ov .. "\\^[sheet\\:1x4\\:0,0:0,16=" .. ov .. "\\^[sheet\\:1x4\\:0,3:0,32=" .. ov .. "\\^[sheet\\:1x4\\:0,2:0,48=" .. ov .. "\\^[sheet\\:1x4\\:0,1"
    end
    return { name = "(" .. bg_strip .. ")^(" .. ov_strip .. ")", animation = { type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = anim_length or 0.24 } }
end

-- World-placed idle casing node (has only the half-block casing so the 3D bore entity is the only bore in the world)
core.register_node(WORLD_IDLE_NAME, {
    description           = "Mechanical Drill",
    drawtype              = "nodebox",
    node_box              = CASING_ONLY_NODEBOX,
    collision_box         = { type = "fixed", fixed = {{-8/16, -8/16, -8/16, 8/16, 6/16, 8/16}} },
    selection_box         = { type = "fixed", fixed = {{-8/16, -8/16, -8/16, 8/16, 8/16, 8/16}} },
    paramtype             = "light",
    paramtype2            = "facedir",
    sunlight_propagates   = true,
    is_ground_content     = false,
    drop                  = IDLE_NAME,
    tiles = {
        casing_top_tex,
        "[combine:16x16:0,0=" .. TEX_BACK .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY,
        casing_side_tex,
        casing_side_tex,
        casing_side_tex,
        casing_side_tex,
    },
    groups                = {handy = 1, pickaxey = 1, kinetic_receiver = 1, kinetica_drill = 1, not_in_creative_inventory = 1},
    _mcl_hardness         = 2.5,
    _mcl_blast_resistance = 3.5,
    sounds                = mcl_sounds and mcl_sounds.node_sound_metal_defaults and mcl_sounds.node_sound_metal_defaults() or nil,
    on_rightclick         = on_drill_rightclick,
    on_destruct           = function(pos)
        remove_drill_bit_entity(pos)
    end,
    after_dig_node        = function(pos)
        remove_drill_bit_entity(pos)
        if kinetica.api and kinetica.api.network.update then
            core.after(0.05, function() kinetica.api.network.update(pos) end)
        end
    end,
    on_timer              = drill_timer,
})

if kinetica.api and kinetica.api.registration then
    kinetica.api.registration.register_rotary_machine(IDLE_NAME, {
        description        = string.format("Mechanical Drill (Min %d RPM | 1x1 Rotary Miner)", CONFIG.MIN_RPM),
        description_active = "Mechanical Drill",
        groups_idle        = {handy = 1, pickaxey = 1, kinetic_receiver = 1, kinetica_drill = 1},
        node_box           = drill_full_3d_nodebox,
        node_box_active    = CASING_ONLY_NODEBOX,
        collision_box      = { type = "fixed", fixed = {{-8/16, -8/16, -8/16, 8/16, 6/16, 8/16}} },
        selection_box      = { type = "fixed", fixed = {{-8/16, -8/16, -8/16, 8/16, 8/16, 8/16}} },
        paramtype2         = "facedir",
        tiles_idle         = {
            bit_top_tex,
            "[combine:16x16:0,0=" .. TEX_BACK .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY,
            inv_side_tex,
            inv_side_tex,
            inv_side_tex,
            inv_side_tex,
        },
        tiles_active_cw    = {
            casing_top_tex,
            make_drill_back_anim(true, 0.24),
            casing_side_tex,
            casing_side_tex,
            casing_side_tex,
            casing_side_tex,
        },
        tiles_active_ccw   = {
            casing_top_tex,
            make_drill_back_anim(false, 0.24),
            casing_side_tex,
            casing_side_tex,
            casing_side_tex,
            casing_side_tex,
        },
        build_tier_tiles   = function(tier, is_ccw)
            return {
                casing_top_tex,
                make_drill_back_anim(not is_ccw, tier.length),
                casing_side_tex,
                casing_side_tex,
                casing_side_tex,
                casing_side_tex,
            }
        end,
        hardness           = 2.5,
        sounds             = mcl_sounds and mcl_sounds.node_sound_metal_defaults and mcl_sounds.node_sound_metal_defaults() or nil,
        on_place           = place_mechanical_drill,
        on_rightclick      = on_drill_rightclick,
        on_construct       = function(pos)
            local node = core.get_node(pos)
            set_drill_idle(pos, node)
        end,
        after_dig_node     = function(pos)
            remove_drill_bit_entity(pos)
        end,
        on_timer           = drill_timer,
        get_demand_ku      = function(rpm, pos, node) return get_drill_demand_ku(rpm) end,
        has_axle_port      = function(node, d)
            local back_dir = get_back_dir(node.param2)
            return (d.x == back_dir.x and d.y == back_dir.y and d.z == back_dir.z)
        end,
        set_idle           = set_drill_idle,
        wake               = wake_drill,
    })

    for nname, ndef in pairs(core.registered_nodes) do
        if is_drill_node(nname) then
            core.override_item(nname, {
                on_destruct = function(pos)
                    remove_drill_bit_entity(pos)
                end,
            })
        end
    end
end

core.register_lbm({
    label             = "Wake kinetica Mechanical Drills on chunk load",
    name              = "kinetica:wake_drills_lbm",
    nodenames         = {"group:kinetica_drill"},
    run_at_every_load = true,
    action = function(pos, node)
        local meta     = core.get_meta(pos)
        local rpm      = meta:get_float("rpm")
        local spin_dir = meta:get_int("spin_dir")
        if node.name == IDLE_NAME then
            core.swap_node(pos, {name = WORLD_IDLE_NAME, param2 = node.param2})
            node = core.get_node(pos)
        end
        if node.name == WORLD_IDLE_NAME or rpm < CONFIG.MIN_RPM then
            sync_drill_bit_entity(pos, node.param2, 0, 0)
        else
            sync_drill_bit_entity(pos, node.param2, rpm, spin_dir ~= 0 and spin_dir or 1)
        end
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then timer:start(CONFIG.TICK_INTERVAL) end
    end,
})

core.register_craft({
    output = "kinetica:mechanical_drill",
    recipe = {
        {"",               "mcl_core:iron_ingot",      ""},
        {"",               "mcl_core:iron_ingot",      ""},
        {"kinetica:shaft", "kinetica:andesite_casing", ""},
    },
})