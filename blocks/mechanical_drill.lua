kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""


local BORE_SPIN_TUNING = {

    LOCAL_SPIN_AXIS = "y",

    INVERT_SPIN_DIR = false,
    DIR_OFFSET_DEG = {
        UP    = {x = 0, y = 0, z = 0},
        DOWN  = {x = 0, y = 0, z = 0},
        NORTH = {x = 0, y = 0, z = 0},
        SOUTH = {x = 0, y = 0, z = 0},
        EAST  = {x = 0, y = 0, z = 0},
        WEST  = {x = 0, y = 0, z = 0},
    },
}


local SOUND_CONFIG = {
    ENABLE_SOUND                   = true,
    SOUND_NAME                     = "driller",            -- Custom .ogg in sounds/ folder (without .ogg)
    SOUND_FALLBACK                 = "default_dig_cracky", -- Built-in fallback sound if custom .ogg is missing
    SOUND_BLOCK_BROKEN             = "default_dug_node",   -- Sound played when a block finishes breaking
    SOUND_GAIN                     = 0.22,                 -- Volume while spinning/drilling (0.0 to 1.0)
    SOUND_BROKEN_GAIN              = 0.85,                 -- Volume of the block-broken sound
    SOUND_PITCH                    = 0.90,                 -- Base pitch when SCALE_PITCH_WITH_RPM = false
    SCALE_PITCH_WITH_RPM           = true,                 -- Scale pitch dynamically with shaft RPM
    MIN_PITCH                      = 0.75,                 -- Pitch at MIN_RPM (16 RPM)
    MAX_PITCH                      = 1.35,                 -- Pitch at 512+ RPM
    SOUND_INTERVAL                 = 0.80,                 -- Seconds between sound triggers while active
    MAX_HEAR_DISTANCE              = 12,                   -- Max distance (blocks) players can hear it
    SOUND_ONLY_WHEN_DRILLING_BLOCK = false,                -- true = only play when mining a block; false = play whenever spinning
}

local CONFIG = {
    DRILL_FACES_PLAYER              = true,
    ENABLE_DRILL_UI_MENU            = true,
    HIDE_INFOTEXT_WITHOUT_GLASSES   = false,
    ALLOW_BREAKING_KINETICA_BLOCKS  = true,
    MIN_RPM                         = 16,
    KU_PER_RPM                      = 4,
    MIN_KU                          = 32,
    MAX_KU                          = 128,
    MAX_RPM_CAP                     = 3072,
    ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    shaft_len = 0.85, drill_len = 0.55 },
        { name = "slow",   max_rpm = 15,   shaft_len = 0.48, drill_len = 0.34 },
        { name = "medium", max_rpm = 63,   shaft_len = 0.24, drill_len = 0.20 },
        { name = "fast",   max_rpm = 255,  shaft_len = 0.11, drill_len = 0.10 },
        { name = "hyper",  max_rpm = 1024, shaft_len = 0.05, drill_len = 0.05 },
        { name = "ultra",  max_rpm = 3072, shaft_len = 0.03, drill_len = 0.03 },
    },
    TICK_INTERVAL                   = 0.20,
    BASE_TIME_AT_MIN_RPM            = 1.20,
    BASE_TIME_AT_512_RPM            = 0.20,
    SCALE_TIME_BY_HARDNESS          = true,
    MAX_MINEABLE_HARDNESS           = 55.0,
    MIN_DRILL_TIME_SEC              = 0.20,
    MAX_DRILL_TIME_SEC              = 10.0,
    ENABLE_STACKED_STORAGE_MODE     = true,
    DEFAULT_STORAGE_MODE_ON         = true,
    SYNC_TOGGLE_ACROSS_STACK        = true,
    MAX_STACKED_DRILLS_SEARCH       = 64,
    COBBLE_GEN_SPEED_BOOST          = true,
    SPAWN_DRILL_SPARKS              = true,
    DEAL_ENTITY_DAMAGE              = true,
    DAMAGE_HP_AT_MIN_RPM            = 2,
    DAMAGE_HP_AT_512_RPM            = 8,
    DAMAGE_INTERVAL_SEC             = 0.80,
    DAMAGE_RADIUS                   = 0.78,
    BASE_SPIN_RAD_PER_SEC           = 4.0,
    MAX_SPIN_RAD_PER_SEC            = 24.0,
    UI_COLORS = {
        BG_WINDOW  = "#14171D",
        BG_HEADER  = "#1F242D",
        BG_CARD    = "#1B2028",
        ACCENT_CYN = "#00D4FF",
        ACCENT_AMB = "#FFB300",
        ACCENT_GRN = "#00E676",
        ACCENT_RED = "#FF5252",
        TEXT_TITLE = "#F5B041",
        TEXT_LABEL = "#ABB2B9",
        TEXT_VALUE = "#FFFFFF",
    },
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
local ACT_CW          = "kinetica:mechanical_drill_active_cw"
local ACT_CCW         = "kinetica:mechanical_drill_active_ccw"
local BIT_MESH_NODE   = "kinetica:mechanical_drill_bit_mesh"
local BIT_ENTITY_NAME = "kinetica:mechanical_drill_bit"
local INV_MESH_NODE   = "kinetica:mechanical_drill_inv_mesh"

local function is_drill_node(name)
    if not name then return false end
    return (name == IDLE_NAME or string.sub(name, 1, #IDLE_NAME + 1) == (IDLE_NAME .. "_"))
       and name ~= BIT_MESH_NODE
       and name ~= INV_MESH_NODE
end
kinetica.is_mechanical_drill = is_drill_node

local function file_exists(rel_path)
    local f = io.open(modpath .. "/" .. rel_path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local TEX_TOP  = file_exists("textures/" .. CONFIG.TEX_DRILL_CASING_TOP)  and CONFIG.TEX_DRILL_CASING_TOP  or CONFIG.TEX_FALLBACK_TOP
local TEX_BACK = file_exists("textures/" .. CONFIG.TEX_DRILL_CASING_BACK) and CONFIG.TEX_DRILL_CASING_BACK or CONFIG.TEX_FALLBACK_BACK
local TEX_SIDE = file_exists("textures/" .. CONFIG.TEX_DRILL_CASING_SIDE) and CONFIG.TEX_DRILL_CASING_SIDE or CONFIG.TEX_FALLBACK_SIDE
local TEX_SAW  = CONFIG.TEX_FALLBACK_DRILL_HEAD

local ACTIVE_DRILL_SOUND = (SOUND_CONFIG.SOUND_NAME ~= "" and file_exists("sounds/" .. SOUND_CONFIG.SOUND_NAME .. ".ogg"))
    and SOUND_CONFIG.SOUND_NAME
    or  SOUND_CONFIG.SOUND_FALLBACK

local function rpm_factor(rpm)
    if not rpm or rpm <= CONFIG.MIN_RPM then return 0.0 end
    return math.min(1.0, math.max(0.0, (rpm - CONFIG.MIN_RPM) / (512 - CONFIG.MIN_RPM)))
end

local function lerp(a, b, t)
    return a + t * (b - a)
end

local function play_drill_active_sound(pos, meta, rpm, can_drill, dt)
    if not SOUND_CONFIG.ENABLE_SOUND or not ACTIVE_DRILL_SOUND or ACTIVE_DRILL_SOUND == "" then
        return
    end
    if SOUND_CONFIG.SOUND_ONLY_WHEN_DRILLING_BLOCK and not can_drill then
        return
    end

    local sound_timer = meta:get_float("drill_sound_timer") + (dt or CONFIG.TICK_INTERVAL)
    if sound_timer < (SOUND_CONFIG.SOUND_INTERVAL or 0.80) then
        meta:set_float("drill_sound_timer", sound_timer)
        return
    end
    meta:set_float("drill_sound_timer", 0)

    local pitch = SOUND_CONFIG.SOUND_PITCH or 0.90
    if SOUND_CONFIG.SCALE_PITCH_WITH_RPM then
        pitch = lerp(SOUND_CONFIG.MIN_PITCH or 0.75, SOUND_CONFIG.MAX_PITCH or 1.35, rpm_factor(rpm))
    end

    core.sound_play(ACTIVE_DRILL_SOUND, {
        pos               = pos,
        max_hear_distance = SOUND_CONFIG.MAX_HEAR_DISTANCE or 12,
        gain              = SOUND_CONFIG.SOUND_GAIN or 0.22,
        pitch             = pitch,
    }, true)
end

local function get_drill_demand_ku(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then
        return CONFIG.MIN_KU
    end
    return math.min(CONFIG.MAX_KU, math.max(CONFIG.MIN_KU, math.floor(rpm * CONFIG.KU_PER_RPM)))
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

local function get_active_drill_node_name(rpm, spin_dir)
    local tier_name = get_anim_tier_name(rpm)
    local dir_tag   = (spin_dir == 1) and "cw" or "ccw"
    local candidate = IDLE_NAME .. "_" .. tier_name .. "_" .. dir_tag
    if core.registered_nodes[candidate] then
        return candidate
    end
    return (spin_dir == 1) and ACT_CW or ACT_CCW
end

local AXIS_TO_DRILL_DIR = {
    [0] = {x =  0, y =  1, z =  0},
    [1] = {x =  0, y =  0, z =  1},
    [2] = {x =  0, y =  0, z = -1},
    [3] = {x =  1, y =  0, z =  0},
    [4] = {x = -1, y =  0, z =  0},
    [5] = {x =  0, y = -1, z =  0},
}

local ALL_6_DIRS = {
    {x =  1, y =  0, z =  0},
    {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0},
    {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1},
    {x =  0, y =  0, z = -1},
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

local function get_flipped_drill_param2(drill_dir)
    local axisdir = 0
    if drill_dir.y > 0 then
        axisdir = 0
    elseif drill_dir.y < 0 then
        axisdir = 5
    elseif drill_dir.z > 0 then
        axisdir = 1
    elseif drill_dir.z < 0 then
        axisdir = 2
    elseif drill_dir.x > 0 then
        axisdir = 3
    elseif drill_dir.x < 0 then
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

-- ============================================================================
-- 3D DRILL BORE GEOMETRY & SPLIT-UV TEXTURES FOR INVENTORY / HAND / ENTITY
-- ============================================================================
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

local bit_mesh_boxes = {
    type  = "fixed",
    fixed = drill_bore_boxes,
}

local bit_saw_frame = TEX_SAW .. "^[sheet:1x3:0,0"
local bit_flute_tex = "(" .. CONFIG.TEX_FALLBACK_COLLAR .. ")^(" .. bit_saw_frame .. ")"
local bit_top_tex   = "(" .. CONFIG.TEX_FALLBACK_COLLAR .. ")^(" .. bit_saw_frame .. ")"

-- Split Side Texture for the 3D Inventory/Wield Nodebox:
--   Top 8 pixels (y = 0..7, which maps to nodebox Y = 0..+8/16): Stonecutter Bore Texture
--   Bottom 8 pixels (y = 8..15, which maps to nodebox Y = -8/16..0): Drill Casing Side Texture
local esc_saw_frame = TEX_SAW .. "\\^[sheet\\:1x3\\:0,0"
local split_side_idle_tex = "[combine:16x16" ..
    ":0,0="  .. CONFIG.TEX_FALLBACK_COLLAR ..
    ":0,0="  .. esc_saw_frame ..
    ":0,8="  .. TEX_SIDE

core.register_node(BIT_MESH_NODE, {
    description         = "Mechanical Drill Bit Mesh",
    drawtype            = "nodebox",
    paramtype           = "light",
    sunlight_propagates = true,
    use_texture_alpha   = "clip",
    tiles = {
        bit_top_tex,
        CONFIG.TEX_FALLBACK_COLLAR,
        bit_flute_tex,
        bit_flute_tex,
        bit_flute_tex,
        bit_flute_tex,
    },
    node_box = bit_mesh_boxes,
    groups   = {not_in_creative_inventory = 1},
})

-- ============================================================================
-- EXACT 3D ROTATION MATRIX -> LUANTI EULER DECOMPOSITION
-- Multiplies R_total = R_align(drill_dir) * R_local_spin(angle) so the bore
-- ALWAYS spins around its own pointed +Y tip axis before aiming in drill_dir.
-- ============================================================================
local function mat3_mul(A, B)
    return {
        {
            A[1][1]*B[1][1] + A[1][2]*B[2][1] + A[1][3]*B[3][1],
            A[1][1]*B[1][2] + A[1][2]*B[2][2] + A[1][3]*B[3][2],
            A[1][1]*B[1][3] + A[1][2]*B[2][3] + A[1][3]*B[3][3],
        },
        {
            A[2][1]*B[1][1] + A[2][2]*B[2][1] + A[2][3]*B[3][1],
            A[2][1]*B[1][2] + A[2][2]*B[2][2] + A[2][3]*B[3][2],
            A[2][1]*B[1][3] + A[2][2]*B[2][3] + A[2][3]*B[3][3],
        },
        {
            A[3][1]*B[1][1] + A[3][2]*B[2][1] + A[3][3]*B[3][1],
            A[3][1]*B[1][2] + A[3][2]*B[2][2] + A[3][3]*B[3][2],
            A[3][1]*B[1][3] + A[3][2]*B[2][3] + A[3][3]*B[3][3],
        },
    }
end

local function local_spin_matrix(angle)
    local raw_axis = string.lower(BORE_SPIN_TUNING.LOCAL_SPIN_AXIS or "y")
    local sign = 1
    if string.sub(raw_axis, 1, 1) == "-" then
        sign = -1
        raw_axis = string.sub(raw_axis, 2)
    elseif string.sub(raw_axis, 1, 1) == "+" then
        raw_axis = string.sub(raw_axis, 2)
    end

    local eff = angle * sign
    local c   = math.cos(eff)
    local s   = math.sin(eff)

    if raw_axis == "x" then
        return {
            {1,  0,  0},
            {0,  c, -s},
            {0,  s,  c},
        }
    elseif raw_axis == "z" then
        return {
            { c, -s, 0},
            { s,  c, 0},
            { 0,  0, 1},
        }
    else
        -- Default "y": spin around the bore's +Y center shaft axis
        return {
            { c, 0,  s},
            { 0, 1,  0},
            {-s, 0,  c},
        }
    end
end

-- Alignment matrix whose 2nd column (the local +Y tip of the drill bit) equals drill_dir
local function dir_align_matrix(drill_dir)
    if drill_dir.y > 0 then
        -- UP (+Y)
        return {
            {1, 0, 0},
            {0, 1, 0},
            {0, 0, 1},
        }, "UP"
    elseif drill_dir.y < 0 then
        -- DOWN (-Y)
        return {
            { 1,  0,  0},
            { 0, -1,  0},
            { 0,  0, -1},
        }, "DOWN"
    elseif drill_dir.z > 0 then
        -- NORTH (+Z): maps local +Y -> +Z, local +Z -> -Y, local +X -> +X
        return {
            {1,  0,  0},
            {0,  0, -1},
            {0,  1,  0},
        }, "NORTH"
    elseif drill_dir.z < 0 then
        -- SOUTH (-Z): maps local +Y -> -Z, local +Z -> +Y, local +X -> +X
        return {
            {1,  0, 0},
            {0,  0, 1},
            {0, -1, 0},
        }, "SOUTH"
    elseif drill_dir.x > 0 then
        -- EAST (+X): maps local +Y -> +X, local +X -> -Y, local +Z -> +Z
        return {
            { 0, 1, 0},
            {-1, 0, 0},
            { 0, 0, 1},
        }, "EAST"
    else
        -- WEST (-X): maps local +Y -> -X, local +X -> +Y, local +Z -> +Z
        return {
            {0, -1, 0},
            {1,  0, 0},
            {0,  0, 1},
        }, "WEST"
    end
end

-- Decompose 3x3 orthogonal matrix into Luanti's exact entity Euler angles {x, y, z}.
-- Luanti's setPitchYawRollRad applies First Roll (Z), then Pitch (X), then Yaw (Y)
-- in right-handed sense within Luanti's (X=East, Y=Up, Z=North) axes:
--   R[1] = {  cy*cz + sy*sx*sz,   cy*sz - sy*sx*cz,  -sy*cx }
--   R[2] = { -cx*sz,              cx*cz,             -sx    }
--   R[3] = {  sy*cz - cy*sx*sz,   sy*sz + cy*sx*cz,   cy*cx }
local function mat3_to_luanti_euler(R)
    local sx = math.max(-1.0, math.min(1.0, -R[2][3]))
    local x  = math.asin(sx)
    local cx = math.cos(x)
    local y, z
    if math.abs(cx) > 1e-4 then
        y = math.atan2(-R[1][3], R[3][3])
        z = math.atan2(-R[2][1], R[2][2])
    else
        y = math.atan2(R[3][1], R[1][1])
        z = 0
    end
    return {x = x, y = y, z = z}
end

local function compute_bit_euler(drill_dir, angle)
    local eff_angle = BORE_SPIN_TUNING.INVERT_SPIN_DIR and (-angle) or angle
    local R_align, dir_key = dir_align_matrix(drill_dir)
    local R_spin  = local_spin_matrix(eff_angle)
    local R_total = mat3_mul(R_align, R_spin)
    local euler   = mat3_to_luanti_euler(R_total)

    local ofs = BORE_SPIN_TUNING.DIR_OFFSET_DEG and BORE_SPIN_TUNING.DIR_OFFSET_DEG[dir_key]
    if ofs then
        local deg2rad = math.pi / 180.0
        euler.x = euler.x + (ofs.x or 0) * deg2rad
        euler.y = euler.y + (ofs.y or 0) * deg2rad
        euler.z = euler.z + (ofs.z or 0) * deg2rad
    end
    return euler
end

core.register_entity(BIT_ENTITY_NAME, {
    initial_properties = {
        physical             = false,
        collide_with_objects = false,
        pointable            = false,
        visual               = "wielditem",
        wield_item           = BIT_MESH_NODE,
        visual_size          = {x = 0.6667, y = 0.6667, z = 0.6667},
        static_save          = true,
        shaded               = true,
    },

    on_activate = function(self, staticdata)
        self.object:set_armor_groups({immortal = 1})
        self.angle      = 0
        self.speed      = 0
        self.drill_dir  = {x = 0, y = 1, z = 0}
        self._check_acc = 0

        local pos = self.object:get_pos()
        if pos then
            local bpos = vector.round(pos)
            local node = core.get_node(bpos)
            if is_drill_node(node.name) then
                self.drill_dir = get_drill_dir(node.param2)
                local meta     = core.get_meta(bpos)
                local rpm      = meta:get_float("rpm")
                local spin_dir = meta:get_int("spin_dir")
                if node.name ~= IDLE_NAME and rpm >= CONFIG.MIN_RPM and spin_dir ~= 0 then
                    self.speed = lerp(CONFIG.BASE_SPIN_RAD_PER_SEC, CONFIG.MAX_SPIN_RAD_PER_SEC, rpm_factor(rpm)) * spin_dir
                end
                self.object:set_rotation(compute_bit_euler(self.drill_dir, self.angle))
            else
                self.object:remove()
            end
        end
    end,

    on_step = function(self, dtime)
        self._check_acc = (self._check_acc or 0) + dtime
        if self._check_acc >= 0.5 then
            self._check_acc = 0
            local pos = self.object:get_pos()
            if not pos or not is_drill_node(core.get_node(vector.round(pos)).name) then
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
    for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.55)) do
        local le = obj:get_luaentity()
        if le and le.name == BIT_ENTITY_NAME then
            obj:remove()
        end
    end
end

local function sync_drill_bit_entity(pos, param2, rpm, spin_dir)
    local drill_dir = get_drill_dir(param2)
    local bit_obj   = nil

    for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.45)) do
        local le = obj:get_luaentity()
        if le and le.name == BIT_ENTITY_NAME then
            if not bit_obj then
                bit_obj = obj
            else
                obj:remove()
            end
        end
    end

    if not bit_obj then
        bit_obj = core.add_entity(pos, BIT_ENTITY_NAME)
    end

    if bit_obj then
        local le = bit_obj:get_luaentity()
        if le then
            le.drill_dir = drill_dir
            local spd = 0
            if rpm and rpm >= CONFIG.MIN_RPM and spin_dir and spin_dir ~= 0 then
                spd = lerp(CONFIG.BASE_SPIN_RAD_PER_SEC, CONFIG.MAX_SPIN_RAD_PER_SEC, rpm_factor(rpm)) * spin_dir
            end
            le.speed = spd
            bit_obj:set_rotation(compute_bit_euler(drill_dir, le.angle or 0))
        end
    end
end

local SILK_TO_NORMAL_DROPS = {
    ["mcl_core:stone"]                       = "mcl_core:cobble",
    ["mcl_deepslate:deepslate"]              = "mcl_deepslate:deepslate_cobbled",
    ["mcl_core:dirt_with_grass"]             = "mcl_core:dirt",
    ["mcl_core:dirt_with_grass_snow"]        = "mcl_core:dirt",
    ["mcl_core:podzol"]                      = "mcl_core:dirt",
    ["mcl_core:mycelium"]                    = "mcl_core:dirt",
    ["mcl_core:stone_with_coal"]             = "mcl_core:coal_lump",
    ["mcl_deepslate:deepslate_with_coal"]    = "mcl_core:coal_lump",
    ["mcl_core:stone_with_iron"]             = "mcl_raw_ores:raw_iron",
    ["mcl_deepslate:deepslate_with_iron"]    = "mcl_raw_ores:raw_iron",
    ["mcl_copper:stone_with_copper"]         = "mcl_copper:raw_copper 2",
    ["mcl_deepslate:deepslate_with_copper"]  = "mcl_copper:raw_copper 2",
    ["mcl_core:stone_with_gold"]             = "mcl_raw_ores:raw_gold",
    ["mcl_deepslate:deepslate_with_gold"]    = "mcl_raw_ores:raw_gold",
    ["mcl_core:stone_with_diamond"]          = "mcl_core:diamond",
    ["mcl_deepslate:deepslate_with_diamond"] = "mcl_core:diamond",
    ["mcl_core:stone_with_emerald"]          = "mcl_core:emerald",
    ["mcl_deepslate:deepslate_with_emerald"] = "mcl_core:emerald",
    ["mcl_core:stone_with_lapis"]            = "mcl_core:lapis 4",
    ["mcl_deepslate:deepslate_with_lapis"]   = "mcl_core:lapis 4",
    ["mcl_core:stone_with_redstone"]         = "mcl_redstone:redstone 4",
    ["mcl_deepslate:deepslate_with_redstone"]= "mcl_redstone:redstone 4",
    ["mcl_nether:quartz_ore"]                = "mcl_nether:quartz",
    ["mcl_nether:nether_gold_ore"]           = "mcl_core:gold_nugget 4",
}

local function get_guaranteed_drill_drops(target_node)
    local nname = target_node.name
    if SILK_TO_NORMAL_DROPS[nname] then
        local mapped = SILK_TO_NORMAL_DROPS[nname]
        local base_item = string.match(mapped, "^([^%s]+)")
        if core.registered_items[base_item] then
            return {mapped}
        end
    end

    local def = core.registered_nodes[nname]
    if def and def.drop == "" then
        return {}
    end

    local tool_name = core.registered_items["mcl_tools:pick_diamond"] and "mcl_tools:pick_diamond"
                   or (core.registered_items["default:pick_diamond"] and "default:pick_diamond" or "")

    local drops = core.get_node_drops(nname, tool_name)
    if drops and #drops > 0 then
        return drops
    end

    if def then
        if type(def.drop) == "string" and def.drop ~= "" then
            return {def.drop}
        elseif type(def.drop) == "table" and def.drop.items then
            local out = {}
            for _, item_entry in ipairs(def.drop.items) do
                if item_entry.items and #item_entry.items > 0 then
                    out[#out + 1] = item_entry.items[1]
                    break
                end
            end
            if #out > 0 then
                return out
            end
        end
    end

    return {nname}
end

local function is_ore_block(name)
    if not name then return false end
    return string.find(name, "_ore") ~= nil or
           string.find(name, "stone_with_") ~= nil or
           string.find(name, "deepslate_with_") ~= nil or
           string.find(name, "ancient_debris") ~= nil or
           string.find(name, "gilded_blackstone") ~= nil or
           string.find(name, "nether_gold") ~= nil or
           string.find(name, "quartz_ore") ~= nil
end

local PROTECTED_TECHNICAL_NODES = {
    [BIT_MESH_NODE]                 = true,
    [INV_MESH_NODE]                 = true,
    ["kinetica:piston_head"]        = true,
    ["kinetica:piston_head_sticky"] = true,
}

local function is_drillable_node(name)
    if not name or name == "air" or name == "ignore" then
        return false, 0
    end
    if PROTECTED_TECHNICAL_NODES[name] then
        return false, 0
    end
    if not CONFIG.ALLOW_BREAKING_KINETICA_BLOCKS and string.sub(name, 1, 9) == "kinetica:" then
        return false, 0
    end

    local def = core.registered_nodes[name]
    if not def or def.diggable == false then
        return false, 0
    end

    if def.liquidtype and def.liquidtype ~= "none" then
        return false, 0
    end
    if core.get_item_group(name, "water") > 0 or
       core.get_item_group(name, "lava") > 0 or
       core.get_item_group(name, "fire") > 0 then
        return false, 0
    end

    local hardness = def._mcl_hardness
    if hardness and (hardness < 0 or hardness > CONFIG.MAX_MINEABLE_HARDNESS) then
        return false, 0
    end
    if core.get_item_group(name, "unbreakable") > 0 or
       core.get_item_group(name, "immortal") > 0 or
       string.find(name, "bedrock") or
       string.find(name, "barrier") or
       string.find(name, "portal") or
       string.find(name, "command_block") then
        return false, 0
    end

    if def.groups and def.groups.container and def.groups.container > 0 then
        return false, 0
    end

    local eff_hardness = math.max(0.2, tonumber(hardness) or 1.5)
    return true, eff_hardness
end

local function is_cobble_gen_target(target_pos, target_name)
    if not CONFIG.COBBLE_GEN_SPEED_BOOST then return false end
    if not (string.find(target_name, "cobble") or
            string.find(target_name, "stone") or
            string.find(target_name, "basalt")) then
        return false
    end
    for _, d in ipairs(ALL_6_DIRS) do
        local np = {x = target_pos.x + d.x, y = target_pos.y + d.y, z = target_pos.z + d.z}
        local nn = core.get_node(np).name
        if core.get_item_group(nn, "lava") > 0 or core.get_item_group(nn, "water") > 0 or
           string.find(nn, "lava") or string.find(nn, "water") or string.find(nn, "blue_ice") then
            return true
        end
    end
    return false
end

local function get_required_drill_seconds(rpm, hardness, is_cobble_gen)
    local base = lerp(CONFIG.BASE_TIME_AT_MIN_RPM, CONFIG.BASE_TIME_AT_512_RPM, rpm_factor(rpm))
    if CONFIG.SCALE_TIME_BY_HARDNESS and hardness then
        local h_mult = math.max(0.35, math.pow(hardness / 1.5, 0.65))
        base = base * h_mult
    end
    if is_cobble_gen then
        base = base * 0.65
    end
    return math.min(CONFIG.MAX_DRILL_TIME_SEC, math.max(CONFIG.MIN_DRILL_TIME_SEC, base))
end

local function get_stacked_drill_cluster(start_pos)
    local start_key = core.hash_node_position(start_pos)
    local visited   = {[start_key] = true}
    local cluster   = {start_pos}
    local head      = 1

    while head <= #cluster and #cluster < CONFIG.MAX_STACKED_DRILLS_SEARCH do
        local cur = cluster[head]
        head = head + 1

        for _, d in ipairs(ALL_6_DIRS) do
            local np = {x = cur.x + d.x, y = cur.y + d.y, z = cur.z + d.z}
            local nk = core.hash_node_position(np)
            if not visited[nk] then
                visited[nk] = true
                local nn = core.get_node(np)
                if is_drill_node(nn.name) then
                    cluster[#cluster + 1] = np
                end
            end
        end
    end
    return cluster
end

local function try_insert_into_storage_node(dest_pos, stack)
    if not stack or stack:is_empty() then
        return ItemStack(""), false
    end

    local dnode = core.get_node(dest_pos)
    local dname = dnode.name
    if dname == "air" or dname == "ignore" or is_drill_node(dname) then
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

        if string.find(dname, "chest") then
            for _, hd in ipairs({{x=1,y=0,z=0}, {x=-1,y=0,z=0}, {x=0,y=0,z=1}, {x=0,y=0,z=-1}}) do
                local adj_pos  = {x = dest_pos.x + hd.x, y = dest_pos.y, z = dest_pos.z + hd.z}
                local adj_node = core.get_node(adj_pos)
                if string.find(adj_node.name, "chest") then
                    local ainv = core.get_meta(adj_pos):get_inventory()
                    if ainv and ainv:get_size("main") > 0 and ainv:room_for_item("main", stack) then
                        local leftover = ainv:add_item("main", stack)
                        return leftover, true
                    end
                end
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
        core.add_item({x = dest_pos.x, y = dest_pos.y + 0.32, z = dest_pos.z}, stack)
        local dt = core.get_node_timer(dest_pos)
        if dt and not dt:is_started() then dt:start(0.20) end
        return ItemStack(""), true
    end

    if dname == "kinetica:chute" or dname == "kinetica:smart_chute" or
       core.get_item_group(dname, "kinetica_chute") > 0 then
        core.add_item({x = dest_pos.x, y = dest_pos.y + 0.55, z = dest_pos.z}, stack)
        local ct = core.get_node_timer(dest_pos)
        if ct and not ct:is_started() then ct:start(0.20) end
        return ItemStack(""), true
    end

    if (kinetica.is_belt and kinetica.is_belt(dname)) or
       core.get_item_group(dname, "mechanical_belt") > 0 then
        core.add_item({x = dest_pos.x, y = dest_pos.y + 0.32, z = dest_pos.z}, stack)
        local bt = core.get_node_timer(dest_pos)
        if bt and not bt:is_started() then bt:start(0.20) end
        return ItemStack(""), true
    end

    return stack, false
end

local function get_cluster_storage_candidates(drill_pos)
    local cluster    = get_stacked_drill_cluster(drill_pos)
    local candidates = {}
    local seen       = {}

    local function add_cand(p)
        local hk = core.hash_node_position(p)
        if not seen[hk] then
            seen[hk] = true
            candidates[#candidates + 1] = p
        end
    end

    for _, dpos in ipairs(cluster) do
        local dnode = core.get_node(dpos)
        local bdir  = get_back_dir(dnode.param2)
        add_cand({x = dpos.x,          y = dpos.y - 1,      z = dpos.z})
        add_cand({x = dpos.x + bdir.x, y = dpos.y + bdir.y, z = dpos.z + bdir.z})
    end

    for _, dpos in ipairs(cluster) do
        for _, d in ipairs(ALL_6_DIRS) do
            add_cand({x = dpos.x + d.x, y = dpos.y + d.y, z = dpos.z + d.z})
        end
    end

    return candidates, #cluster
end

local function deliver_mined_drops(drill_pos, drill_node, target_pos, drops, storage_mode_on)
    local candidates = nil
    if CONFIG.ENABLE_STACKED_STORAGE_MODE and storage_mode_on then
        candidates = get_cluster_storage_candidates(drill_pos)
    end

    for _, item in ipairs(drops) do
        local stack = ItemStack(item)
        if not stack:is_empty() and candidates then
            for _, cpos in ipairs(candidates) do
                local leftover, _ = try_insert_into_storage_node(cpos, stack)
                stack = leftover
                if stack:is_empty() then
                    break
                end
            end
        end

        if not stack:is_empty() then
            local below_target = {x = target_pos.x, y = target_pos.y - 1, z = target_pos.z}
            local bname = core.get_node(below_target).name
            if (kinetica.is_belt and kinetica.is_belt(bname)) or
               core.get_item_group(bname, "mechanical_belt") > 0 or
               bname == "kinetica:depot" then
                core.add_item({x = below_target.x, y = below_target.y + 0.32, z = below_target.z}, stack)
                local bt = core.get_node_timer(below_target)
                if bt and not bt:is_started() then bt:start(0.10) end
            else
                core.add_item(target_pos, stack)
            end
        end
    end
end

local function deal_drill_entity_damage(pos, head_pos, rpm)
    if not CONFIG.DEAL_ENTITY_DAMAGE then return end
    local meta    = core.get_meta(pos)
    local dmg_acc = meta:get_float("dmg_timer") + CONFIG.TICK_INTERVAL
    if dmg_acc < CONFIG.DAMAGE_INTERVAL_SEC then
        meta:set_float("dmg_timer", dmg_acc)
        return
    end
    meta:set_float("dmg_timer", 0)

    local hp_dmg = math.floor(lerp(CONFIG.DAMAGE_HP_AT_MIN_RPM, CONFIG.DAMAGE_HP_AT_512_RPM, rpm_factor(rpm)) + 0.5)
    local mid_pt = {
        x = (pos.x + head_pos.x) * 0.5,
        y = (pos.y + head_pos.y) * 0.5,
        z = (pos.z + head_pos.z) * 0.5,
    }

    local hit_seen = {}
    for _, scan_pt in ipairs({mid_pt, head_pos}) do
        local objs = core.get_objects_inside_radius(scan_pt, CONFIG.DAMAGE_RADIUS)
        for _, obj in ipairs(objs) do
            if not hit_seen[obj] then
                hit_seen[obj] = true
                local luaent = obj:get_luaentity()
                if obj:is_player() or (luaent and (luaent.is_mob or luaent._cmi_is_mob or luaent.health)) then
                    obj:punch(obj, 1.0, {
                        full_punch_interval = 1.0,
                        damage_groups = {fleshy = hp_dmg},
                    }, nil)
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
        amount     = 6,
        time       = CONFIG.TICK_INTERVAL,
        minpos     = {x = target_pos.x - 0.28, y = target_pos.y - 0.28, z = target_pos.z - 0.28},
        maxpos     = {x = target_pos.x + 0.28, y = target_pos.y + 0.28, z = target_pos.z + 0.28},
        minvel     = {x = -0.9, y = 0.4, z = -0.9},
        maxvel     = {x =  0.9, y = 1.6, z =  0.9},
        minexptime = 0.20,
        maxexptime = 0.48,
        minsize    = 1.1,
        maxsize    = 2.1,
        texture    = tex,
    })

    if CONFIG.SPAWN_DRILL_SPARKS and (hardness >= 2.0 or is_ore_block(target_node.name)) then
        core.add_particlespawner({
            amount     = 3,
            time       = CONFIG.TICK_INTERVAL,
            minpos     = {x = target_pos.x - 0.22, y = target_pos.y - 0.22, z = target_pos.z - 0.22},
            maxpos     = {x = target_pos.x + 0.22, y = target_pos.y + 0.22, z = target_pos.z + 0.22},
            minvel     = {x = -1.4, y = 0.6, z = -1.4},
            maxvel     = {x =  1.4, y = 2.0, z =  1.4},
            minexptime = 0.15,
            maxexptime = 0.35,
            minsize    = 0.9,
            maxsize    = 1.5,
            glow       = 13,
            texture    = CONFIG.TEX_SHAFT_OVERLAY .. "^[sheet:1x4:0,0^[colorize:#ffb300:220",
        })
    end
end

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

local function format_drill_glasses_info(pos, node)
    local meta      = core.get_meta(pos)
    local rpm       = meta:get_float("rpm")
    local supply_ku = meta:get_int("network_supply_ku")
    local avail_ku  = meta:get_int("rotational_power")
    local demand_ku = meta:get_int("machine_demand_ku")
    if demand_ku <= 0 then demand_ku = get_drill_demand_ku(rpm) end
    local used_ku   = (supply_ku > 0) and math.max(0, supply_ku - avail_ku) or 0
    local now       = math.floor(core.get_gametime())

    local is_over   = (meta:get_int("network_overstressed") == 1)
    local is_active = (node.name ~= IDLE_NAME) and (supply_ku > 0 and rpm >= CONFIG.MIN_RPM and now < meta:get_int("lit_until"))
    local low_rpm   = (supply_ku > 0 and rpm > 0 and rpm < CONFIG.MIN_RPM and now < meta:get_int("lit_until"))

    local target_nm  = meta:get_string("drill_target_name")
    local pct        = meta:get_int("drill_pct")
    local storage_on = (meta:get_int("storage_mode") ~= 0)
    local stack_cnt  = math.max(1, meta:get_int("cluster_size"))

    local state_str = "IDLE"
    if is_over then
        state_str = "OVERSTRESSED!"
    elseif is_active then
        state_str = (target_nm ~= "") and string.format("DRILLING (%d%%)", pct) or "ACTIVE (Spinning)"
    elseif low_rpm then
        state_str = string.format("TOO SLOW (Min %d RPM)", CONFIG.MIN_RPM)
    end

    local short_target = "None"
    if target_nm ~= "" then
        local tdef = core.registered_nodes[target_nm]
        short_target = (tdef and tdef.description) and string.match(tdef.description, "^[^\n%(]+") or target_nm
        short_target = string.gsub(short_target, "%s+$", "")
    end

    return table.concat({
        LINE_TOP,
        "│  Mechanical Drill",
        "│  ● STATE    : " .. state_str,
        LINE_NET,
        kv_row("Speed",      string.format("%.1f RPM  (Min: %d)", is_active and rpm or 0, CONFIG.MIN_RPM)),
        kv_row("Block Load", string.format("-%d KU (1x1 Drill)", is_active and demand_ku or 0)),
        kv_row("Net Pool",   string.format("%d / %d KU Avail", is_active and avail_ku or 0, supply_ku)),
        kv_row("Net Stress", make_progress_bar(is_active and used_ku or 0, supply_ku)),
        LINE_DET,
        kv_row("Target",     short_target),
        kv_row("Progress",   make_progress_bar(pct, 100)),
        kv_row("Drill Wall", string.format("%d Stacked Drill(s)", stack_cnt)),
        kv_row("Storage",    storage_on and "ON (Routes to Shared Chest)" or "OFF (Drops in Front)"),
        LINE_BOT,
    }, "\n")
end

kinetica._glasses_formatters[IDLE_NAME] = format_drill_glasses_info

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

local function C(hex, text)
    return core.colorize(hex, tostring(text))
end

local function show_drill_ui_formspec(pos, player)
    if not CONFIG.ENABLE_DRILL_UI_MENU or not player or not player:is_player() then
        return
    end
    local meta    = core.get_meta(pos)
    local U       = CONFIG.UI_COLORS
    local cluster = get_stacked_drill_cluster(pos)
    meta:set_int("cluster_size", #cluster)

    local rpm        = meta:get_float("rpm")
    local supply_ku  = meta:get_int("network_supply_ku")
    local avail_ku   = meta:get_int("rotational_power")
    local demand_ku  = get_drill_demand_ku(rpm)
    local storage_on = (meta:get_int("storage_mode") ~= 0)

    local storage_status = storage_on
        and C(U.ACCENT_GRN, "ENABLED — All " .. #cluster .. " Stacked Drill(s) send drops to any Chest/Depot/Belt below or behind!")
        or  C(U.ACCENT_AMB, "DISABLED — Drops items directly in front at the mined block")

    local fs = {
        "size[9.2,4.4]",
        "bgcolor[" .. U.BG_WINDOW .. ";false]",
        "box[0,0;9.2,0.95;" .. U.BG_HEADER .. "]",
        "box[0,0.92;9.2,0.05;" .. (storage_on and U.ACCENT_GRN or U.ACCENT_AMB) .. "]",
        "label[0.3,0.12;" .. C(U.TEXT_TITLE, "MECHANICAL DRILL — STACKED STORAGE MENU") .. "]",
        "label[0.3,0.48;" .. C(U.TEXT_LABEL, string.format("Speed: %.1f RPM  |  Load: -%d KU  |  Network Pool: %d / %d KU  |  Connected Drills: %d", rpm, demand_ku, avail_ku, supply_ku, #cluster)) .. "]",
        "box[0.2,1.15;8.8,2.15;" .. U.BG_CARD .. "]",
        "label[0.4,1.25;" .. C(U.ACCENT_CYN, "STACKED DRILL SHARED CHEST / STORAGE MODE:") .. "]",
        "label[0.4,1.62;" .. storage_status .. "]",
        "button[0.4,2.12;8.4,0.95;toggle_storage;" .. core.formspec_escape(
            storage_on
                and "Storage Mode: ON (Click to Turn OFF for all " .. #cluster .. " Stacked Drills)"
                or  "Storage Mode: OFF (Click to Turn ON Shared Chest Routing)"
        ) .. "]",
        "button_exit[3.1,3.50;3.0,0.72;close_btn;Close Menu]",
    }

    local formname = "kinetica:drill_ui_" .. core.pos_to_string(pos)
    core.show_formspec(player:get_player_name(), formname, table.concat(fs))
end

core.register_on_player_receive_fields(function(player, formname, fields)
    if string.sub(formname or "", 1, 18) ~= "kinetica:drill_ui_" then
        return false
    end
    local pos_str = string.sub(formname, 19)
    local pos     = core.string_to_pos(pos_str)
    if not pos then return true end

    local pname = player:get_player_name()
    if core.is_protected(pos, pname) then
        return true
    end

    local node = core.get_node(pos)
    if not is_drill_node(node.name) then
        return true
    end

    local meta    = core.get_meta(pos)
    local cluster = CONFIG.SYNC_TOGGLE_ACROSS_STACK and get_stacked_drill_cluster(pos) or {pos}

    if fields.toggle_storage then
        local new_val = (meta:get_int("storage_mode") == 0) and 1 or 0
        for _, dpos in ipairs(cluster) do
            local dmeta = core.get_meta(dpos)
            dmeta:set_int("storage_mode", new_val)
            dmeta:set_int("cluster_size", #cluster)
            dmeta:set_string("glasses_info", format_drill_glasses_info(dpos, core.get_node(dpos)))
        end
        core.sound_play("default_place_node_hard", {pos = pos, max_hear_distance = 10, gain = 0.45}, true)
        show_drill_ui_formspec(pos, player)
    end
    return true
end)

local function place_mechanical_drill(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then
        return itemstack
    end

    local under_pos  = pointed_thing.under
    local above_pos  = pointed_thing.above
    local under_node = core.get_node(under_pos)
    local under_def  = core.registered_nodes[under_node.name]
    local sneaking   = placer and placer:is_player() and placer:get_player_control().sneak

    if under_def and under_def.on_rightclick and not sneaking and not is_drill_node(under_node.name) then
        return under_def.on_rightclick(under_pos, under_node, placer, itemstack, pointed_thing) or itemstack
    end

    local diff = {
        x = above_pos.x - under_pos.x,
        y = above_pos.y - under_pos.y,
        z = above_pos.z - under_pos.z,
    }

    local drill_dir = nil

    if not sneaking and is_drill_node(under_node.name) then
        drill_dir = get_drill_dir(under_node.param2)
    elseif not sneaking then
        if (kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(under_node.name)) or
           under_node.name == "kinetica:piston_head" or
           under_node.name == "kinetica:piston_head_sticky" or
           (kinetica.is_sticky_contraption_frame and kinetica.is_sticky_contraption_frame(under_node.name)) or
           (kinetica.has_axle_port and kinetica.has_axle_port(under_node, diff, under_pos)) then
            drill_dir = diff
        end
    end

    if not drill_dir then
        local ldir   = look_to_unit_dir(placer)
        local invert = CONFIG.DRILL_FACES_PLAYER
        if sneaking then invert = not invert end
        if invert then
            drill_dir = {x = -ldir.x, y = -ldir.y, z = -ldir.z}
        else
            drill_dir = ldir
        end
    end

    local param2 = get_flipped_drill_param2(drill_dir)
    local placed_stack, place_pos = core.item_place_node(itemstack, placer, pointed_thing, param2)

    if place_pos then
        local meta  = core.get_meta(place_pos)
        local owner = placer and placer.get_player_name and placer:get_player_name() or ""
        meta:set_string("owner", (owner ~= "") and owner or "$unknown")
        meta:set_int("storage_mode", CONFIG.DEFAULT_STORAGE_MODE_ON and 1 or 0)
        meta:set_float("drill_sound_timer", 0)

        sync_drill_bit_entity(place_pos, param2, 0, 0)

        local cluster = get_stacked_drill_cluster(place_pos)
        for _, dpos in ipairs(cluster) do
            core.get_meta(dpos):set_int("cluster_size", #cluster)
        end
    end

    return placed_stack
end

local function on_drill_rightclick(pos, node, clicker, itemstack, pointed_thing)
    if not clicker or not clicker:is_player() then
        return itemstack
    end

    if itemstack and not itemstack:is_empty() then
        local wname = itemstack:get_name()
        if is_drill_node(wname) then
            return place_mechanical_drill(itemstack, clicker, pointed_thing)
        elseif core.registered_nodes[wname] or string.find(wname, "belt_item") then
            return core.item_place_node(itemstack, clicker, pointed_thing)
        end
        return itemstack
    end

    if CONFIG.ENABLE_DRILL_UI_MENU then
        show_drill_ui_formspec(pos, clicker)
    end
    return itemstack
end

local function set_drill_idle(pos, node, reason_text)
    node = node or core.get_node(pos)
    local meta = core.get_meta(pos)
    meta:set_float("drill_progress", 0)
    meta:set_int("drill_pct", 0)
    meta:set_string("drill_target_name", "")
    meta:set_float("drill_sound_timer", 0)

    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
    else
        meta:set_string("infotext", reason_text or string.format(
            "Mechanical Drill: Idle (Min %d RPM | Empty-Hand Right-Click for Storage Menu)",
            CONFIG.MIN_RPM
        ))
    end

    if node.name ~= IDLE_NAME then
        core.swap_node(pos, {name = IDLE_NAME, param2 = node.param2})
    end
    sync_drill_bit_entity(pos, node.param2, 0, 0)
    meta:set_string("glasses_info", format_drill_glasses_info(pos, core.get_node(pos)))
end

local function wake_drill(pos, node, rpm, spin_dir, demand_ku, avail_ku, supply_ku)
    node = node or core.get_node(pos)
    if rpm < CONFIG.MIN_RPM then
        set_drill_idle(pos, node, string.format(
            "Mechanical Drill: Too Slow (%.0f RPM / Min %d RPM required!)",
            rpm, CONFIG.MIN_RPM
        ))
        return
    end

    if spin_dir == 0 then spin_dir = 1 end
    local target_node = get_active_drill_node_name(rpm, spin_dir)
    if node.name ~= target_node then
        core.swap_node(pos, {name = target_node, param2 = node.param2})
    end
    sync_drill_bit_entity(pos, node.param2, rpm, spin_dir)

    local timer = core.get_node_timer(pos)
    if not timer:is_started() then
        timer:start(CONFIG.TICK_INTERVAL)
    end
end

local function drill_timer(pos, elapsed)
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
    local demand_ku = meta:get_int("machine_demand_ku")
    if demand_ku <= 0 then demand_ku = get_drill_demand_ku(rpm) end
    local spin_dir  = meta:get_int("spin_dir")
    if spin_dir == 0 then spin_dir = 1 end

    if supply_ku <= 0 or rpm < CONFIG.MIN_RPM or now >= meta:get_int("lit_until") then
        set_drill_idle(pos, node)
        return false
    end

    local target_active = get_active_drill_node_name(rpm, spin_dir)
    if node.name ~= target_active then
        core.swap_node(pos, {name = target_active, param2 = node.param2})
        node.name = target_active
    end

    sync_drill_bit_entity(pos, node.param2, rpm, spin_dir)

    local drill_dir  = get_drill_dir(node.param2)
    local target_pos = {
        x = pos.x + drill_dir.x,
        y = pos.y + drill_dir.y,
        z = pos.z + drill_dir.z,
    }

    deal_drill_entity_damage(pos, target_pos, rpm)

    local target_node         = core.get_node(target_pos)
    local can_drill, hardness = is_drillable_node(target_node.name)

    play_drill_active_sound(pos, meta, rpm, can_drill, CONFIG.TICK_INTERVAL)

    local storage_on = (meta:get_int("storage_mode") ~= 0)
    local mode_tag   = storage_on and "Shared Storage: ON" or "Storage: OFF"

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

            local owner = meta:get_string("owner")
            if not core.is_protected(target_pos, owner) then
                local broken_name = target_node.name
                local drops = get_guaranteed_drill_drops(target_node)
                core.remove_node(target_pos)
                core.check_for_falling(target_pos)

                if string.sub(broken_name, 1, 9) == "kinetica:" and kinetica.schedule_network_update then
                    kinetica.schedule_network_update(target_pos)
                end

                deliver_mined_drops(pos, node, target_pos, drops, storage_on)
                if SOUND_CONFIG.SOUND_BLOCK_BROKEN and SOUND_CONFIG.SOUND_BLOCK_BROKEN ~= "" then
                    core.sound_play(SOUND_CONFIG.SOUND_BLOCK_BROKEN, {
                        pos               = target_pos,
                        max_hear_distance = 16,
                        gain              = SOUND_CONFIG.SOUND_BROKEN_GAIN or 0.85,
                    }, true)
                end
            end
        else
            meta:set_float("drill_progress", progress)
            local pct = math.min(99, math.floor((progress / math.max(0.05, req_time)) * 100))
            meta:set_int("drill_pct", pct)
        end

        local pct = meta:get_int("drill_pct")
        if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
            meta:set_string("infotext", "")
        else
            meta:set_string("infotext", string.format(
                "Mechanical Drill [%s]: DRILLING %d%% (-%d KU | %d/%d KU avail | %.0f RPM)",
                mode_tag, pct, demand_ku, avail_ku, supply_ku, rpm
            ))
        end
    else
        meta:set_float("drill_progress", 0)
        meta:set_int("drill_pct", 0)
        meta:set_string("drill_target_name", "")
        if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
            meta:set_string("infotext", "")
        else
            meta:set_string("infotext", string.format(
                "Mechanical Drill [%s]: ACTIVE (-%d KU | %d/%d KU avail | %.0f RPM)",
                mode_tag, demand_ku, avail_ku, supply_ku, rpm
            ))
        end
    end

    meta:set_string("glasses_info", format_drill_glasses_info(pos, node))
    core.get_node_timer(pos):start(CONFIG.TICK_INTERVAL)
    return false
end

if kinetica.register_kinetic_machine then
    kinetica.register_kinetic_machine(IDLE_NAME, {
        can_ride_piston = true,
        get_demand_ku   = function(rpm, pos, node)
            return get_drill_demand_ku(rpm)
        end,
        has_axle_port   = function(node, d)
            local back_dir = get_back_dir(node.param2)
            return (d.x == back_dir.x and d.y == back_dir.y and d.z == back_dir.z)
        end,
        should_pause_contraption = function(pos, node, move_dir)
            local drill_dir  = get_drill_dir(node.param2)
            local target_pos = {
                x = pos.x + drill_dir.x,
                y = pos.y + drill_dir.y,
                z = pos.z + drill_dir.z,
            }
            local can_drill, _ = is_drillable_node(core.get_node(target_pos).name)
            if can_drill then
                return true, "Waiting for Mechanical Drill to break block"
            end
            return false, nil
        end,
        set_idle = set_drill_idle,
        wake     = wake_drill,
    })
end

-- World placed nodes use the half-casing base (and BIT_ENTITY_NAME renders the bore);
-- Inventory/Hand item uses the full 3D nodebox with split UV textures so the bore has the exact stonecutter saw texture!
local full_3d_drill_boxes = {
    {-8/16, -8/16, -8/16, 8/16, 0/16, 8/16},
}
for _, box in ipairs(drill_bore_boxes) do
    full_3d_drill_boxes[#full_3d_drill_boxes + 1] = box
end

local drill_full_3d_nodebox = {
    type  = "fixed",
    fixed = full_3d_drill_boxes,
}

local drill_base_nodebox = {
    type  = "fixed",
    fixed = {
        {-8/16, -8/16, -8/16, 8/16, 0/16, 8/16},
    },
}

local drill_collision_box = {
    type = "fixed",
    fixed = {
        {-8/16, -8/16, -8/16, 8/16, 6/16, 8/16},
    },
}

local drill_selection_box = {
    type = "fixed",
    fixed = {-8/16, -8/16, -8/16, 8/16, 8/16, 8/16},
}

local back_idle = "[combine:16x16:0,0=" .. TEX_BACK .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY
local side_idle = TEX_SIDE
local top_idle  = "[combine:16x16:0,0=" .. TEX_TOP  .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY

local function make_drill_back_anim(reverse, anim_length)
    local bg = TEX_BACK
    local ov = CONFIG.TEX_SHAFT_OVERLAY

    local bg_strip = "[combine:16x64:0,0=" .. bg .. ":0,16=" .. bg .. ":0,32=" .. bg .. ":0,48=" .. bg
    local ov_strip = ov
    if reverse then
        ov_strip = "[combine:16x64" ..
            ":0,0="  .. ov .. "\\^[sheet\\:1x4\\:0,0" ..
            ":0,16=" .. ov .. "\\^[sheet\\:1x4\\:0,3" ..
            ":0,32=" .. ov .. "\\^[sheet\\:1x4\\:0,2" ..
            ":0,48=" .. ov .. "\\^[sheet\\:1x4\\:0,1"
    end

    return {
        name = "(" .. bg_strip .. ")^(" .. ov_strip .. ")",
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length or 0.24,
        },
    }
end

local function make_drill_top_anim(reverse, anim_length)
    local bg = TEX_TOP
    local ov = CONFIG.TEX_SHAFT_OVERLAY

    local bg_strip = "[combine:16x64:0,0=" .. bg .. ":0,16=" .. bg .. ":0,32=" .. bg .. ":0,48=" .. bg
    local ov_strip = ov
    if reverse then
        ov_strip = "[combine:16x64" ..
            ":0,0="  .. ov .. "\\^[sheet\\:1x4\\:0,0" ..
            ":0,16=" .. ov .. "\\^[sheet\\:1x4\\:0,3" ..
            ":0,32=" .. ov .. "\\^[sheet\\:1x4\\:0,2" ..
            ":0,48=" .. ov .. "\\^[sheet\\:1x4\\:0,1"
    end

    return {
        name = "(" .. bg_strip .. ")^(" .. ov_strip .. ")",
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length or 0.20,
        },
    }
end

local common_groups = {handy = 1, pickaxey = 1, axey = 1, kinetic_receiver = 1, kinetica_drill = 1}
local active_groups = {handy = 1, pickaxey = 1, axey = 1, kinetic_receiver = 1, kinetica_drill = 1, not_in_creative_inventory = 1}

local function register_drill_variant(node_name, top_tile, back_tile, side_tile_a, side_tile_b, is_base)
    core.register_node(node_name, {
        description = is_base
            and string.format("Mechanical Drill (Min %d RPM | 1x1 Rotary Miner | Stacked Drills Share Chest Storage)", CONFIG.MIN_RPM)
            or  "Mechanical Drill",
        drawtype = "nodebox",
        -- Base node uses the full 3D drill nodebox with split-UV textures so Inventory & Wield hand
        -- display the stonecutter saw bore on top and the casing on the bottom!
        node_box = is_base and drill_full_3d_nodebox or drill_base_nodebox,
        collision_box = drill_collision_box,
        selection_box = drill_selection_box,
        paramtype = "light",
        paramtype2 = "facedir",
        sunlight_propagates = true,
        use_texture_alpha = "clip",
        is_ground_content = false,
        tiles = {
            is_base and bit_top_tex or top_tile,
            back_tile,
            is_base and split_side_idle_tex or side_tile_a,
            is_base and split_side_idle_tex or side_tile_b,
            is_base and split_side_idle_tex or side_tile_a,
            is_base and split_side_idle_tex or side_tile_b,
        },
        on_place = is_base and place_mechanical_drill or nil,
        on_rightclick = on_drill_rightclick,
        drop = is_base and nil or IDLE_NAME,
        groups = is_base and common_groups or active_groups,
        _mcl_hardness = 2.5,
        _mcl_blast_resistance = 3.5,
        sounds = mcl_sounds and mcl_sounds.node_sound_metal_defaults and mcl_sounds.node_sound_metal_defaults() or nil,

        on_construct = is_base and function(pos)
            local meta = core.get_meta(pos)
            meta:set_int("storage_mode", CONFIG.DEFAULT_STORAGE_MODE_ON and 1 or 0)
            meta:set_int("cluster_size", 1)
            meta:set_float("drill_sound_timer", 0)
            set_drill_idle(pos, core.get_node(pos))
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end or nil,

        on_destruct = function(pos)
            remove_drill_bit_entity(pos)
        end,

        after_dig_node = function(pos)
            remove_drill_bit_entity(pos)
            for _, d in ipairs(ALL_6_DIRS) do
                local np = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
                if is_drill_node(core.get_node(np).name) then
                    local cluster = get_stacked_drill_cluster(np)
                    for _, cpos in ipairs(cluster) do
                        core.get_meta(cpos):set_int("cluster_size", #cluster)
                    end
                end
            end
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end,

        on_timer = drill_timer,
    })
end

register_drill_variant(IDLE_NAME, top_idle, back_idle, side_idle, side_idle, true)

local med_top_cw   = make_drill_top_anim(false,  0.20)
local med_top_ccw  = make_drill_top_anim(true,   0.20)
local med_back_cw  = make_drill_back_anim(false, 0.24)
local med_back_ccw = make_drill_back_anim(true,  0.24)

register_drill_variant(ACT_CW,  med_top_cw,  med_back_ccw, side_idle, side_idle, false)
register_drill_variant(ACT_CCW, med_top_ccw, med_back_cw,  side_idle, side_idle, false)

for _, tier in ipairs(CONFIG.ANIM_TIERS) do
    local t_cw  = make_drill_top_anim(false,  tier.drill_len)
    local t_ccw = make_drill_top_anim(true,   tier.drill_len)
    local b_cw  = make_drill_back_anim(false, tier.shaft_len)
    local b_ccw = make_drill_back_anim(true,  tier.shaft_len)

    register_drill_variant(IDLE_NAME .. "_" .. tier.name .. "_cw",  t_cw,  b_ccw, side_idle, side_idle, false)
    register_drill_variant(IDLE_NAME .. "_" .. tier.name .. "_ccw", t_ccw, b_cw,  side_idle, side_idle, false)
end

core.register_alias("kinetica:mechanical_drill_active", ACT_CW)

core.register_lbm({
    label             = "Wake kinetica Mechanical Drills on chunk load",
    name              = "kinetica:wake_drills_lbm",
    nodenames         = {"group:kinetica_drill"},
    run_at_every_load = true,
    action = function(pos, node)
        local meta     = core.get_meta(pos)
        local rpm      = meta:get_float("rpm")
        local spin_dir = meta:get_int("spin_dir")
        if node.name == IDLE_NAME or rpm < CONFIG.MIN_RPM then
            sync_drill_bit_entity(pos, node.param2, 0, 0)
        else
            sync_drill_bit_entity(pos, node.param2, rpm, spin_dir ~= 0 and spin_dir or 1)
        end
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TICK_INTERVAL)
        end
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