kinetica = kinetica or {}

local CONFIG = {
    MIN_RPM                       = 1,
    BASE_SPEED_RPM                = 16,
    KU_PER_RPM                    = 4,
    MIN_DEMAND_KU                 = 16,
    MAX_DEMAND_KU                 = 1024,
    RPM_SPEED_EXPONENT            = 1.00,
    STACK_TIME_LOG_FACTOR         = 0.16,
    TIMER_INTERVAL                = 0.10,
    ALLOW_GEAR_MESH_PARTNER       = true,
    SOLO_SPIN_DIR                 = 1,
    WHEEL_SCALE_BELT_GAP          = 1.55,
    WHEEL_SCALE_ADJACENT          = 1.16,
    BASE_SPIN_RAD_PER_SEC         = 1.80,
    MAX_SPIN_RAD_PER_SEC          = 16.0,
    INVERT_VISUAL_SPIN            = false,
    DRAG_PULL_SPEED               = 7.50,
    MAX_BATCH_SIZE                = 64,
    AUTO_MERGE_INTAKE_STACKS      = true,
    SPAWN_CRUSH_XP_ORBS           = true,
    XP_ORB_CHANCE_PER_ITEM        = 0.75,
    DEAL_CRUSH_DAMAGE             = true,
    CRUSH_DAMAGE_BASE_HP          = 6,
    CRUSH_DAMAGE_MAX_HP           = 16,
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    TEX_STONE_FALLBACK            = "default_stone.png",
    TEX_SHAFT_OVERLAY             = "kinetica_shaft_connecting_overlay.png",
    ENABLE_WHEEL_SOUND            = true,
    SOUND_WHEEL_CUSTOM            = "stone_crusher", 
    SOUND_WHEEL_GAIN              = 0.4,
    SOUND_WHEEL_MAX_DISTANCE      = 10,
    SOUND_WHEEL_INTERVAL_SEC      = 0, 
}

local IDLE_NAME         = "kinetica:crushing_wheel"
local ACTIVE_NAME       = "kinetica:crushing_wheel_active"
local MESH_UPRIGHT_NAME = "kinetica:crushing_wheel_mesh_upright"
local MESH_FLAT_NAME    = "kinetica:crushing_wheel_mesh_flat"
local ENTITY_NAME       = "kinetica:crushing_wheel_rotor"

-- Safe 2D hypotenuse (Lua 5.1 / LuaJIT does not provide math.hypot)
local function hypot2(dx, dz)
    return math.sqrt(dx * dx + dz * dz)
end
math.hypot = math.hypot or hypot2

-- Persistent crushing progress per wheel pair hash so Mineclonia item merges never reset progress
local PAIR_CRUSH_STATE = {}

local function resolve_stone_texture()
    local st_def = core.registered_nodes["mcl_core:stone"]
    if st_def and st_def.tiles and st_def.tiles[1] then
        local t = st_def.tiles[1]
        if type(t) == "string" and t ~= "" then
            return t
        elseif type(t) == "table" and type(t.name) == "string" then
            return t.name
        end
    end
    return CONFIG.TEX_STONE_FALLBACK
end

local STONE_TEX    = resolve_stone_texture()
local GROOVE_TEX   = STONE_TEX .. "^[multiply:#9a9a9a"
local HUB_AXLE_TEX = STONE_TEX .. "^(" .. CONFIG.TEX_SHAFT_OVERLAY .. "^[sheet:1x4:0,0)"

local function resolve_item_particle_texture(item_name)
    local def = core.registered_items[item_name]
    if not def then return STONE_TEX end
    if def.tiles and def.tiles[1] then
        local t = def.tiles[1]
        if type(t) == "string" and t ~= "" then
            return t
        elseif type(t) == "table" and type(t.name) == "string" and t.name ~= "" then
            return t.name
        end
    end
    if type(def.inventory_image) == "string" and def.inventory_image ~= "" then
        return def.inventory_image
    end
    return STONE_TEX
end

-- Resolve item aliases across Mineclonia versions (e.g. mcl_redstone vs mesecons, mcl_dyes vs mcl_dye)
local function resolve_valid_itemstring(item_with_count)
    if not item_with_count or item_with_count == "" then return item_with_count end
    local name, cnt = string.match(item_with_count, "^(%S+)%s*(%d*)$")
    if not name then return item_with_count end
    cnt = (cnt and cnt ~= "") and (" " .. cnt) or " 1"

    if core.registered_items[name] then
        return name .. cnt
    end

    local fallbacks = {
        ["mesecons:redstone"]     = "mcl_redstone:redstone",
        ["mcl_redstone:redstone"] = "mesecons:redstone",
        ["mcl_dyes:black"]        = "mcl_dye:black",
        ["mcl_dye:black"]         = "mcl_dyes:black",
        ["mcl_dyes:green"]        = "mcl_dye:green",
        ["mcl_dye:green"]         = "mcl_dyes:green",
        ["mcl_dyes:red"]          = "mcl_dye:red",
        ["mcl_dye:red"]           = "mcl_dyes:red",
        ["mcl_dyes:lime"]         = "mcl_dye:lime",
        ["mcl_dye:lime"]          = "mcl_dyes:lime",
        ["mcl_dyes:white"]        = "mcl_dye:white",
        ["mcl_dye:white"]         = "mcl_dyes:white",
    }
    local alt = fallbacks[name]
    if alt and core.registered_items[alt] then
        return alt .. cnt
    end
    return name .. cnt
end

kinetica.crushing_recipes = kinetica.crushing_recipes or {}

function kinetica.register_crushing_recipe(input_item, def)
    if not input_item or not def or not def.output then return end
    kinetica.crushing_recipes[input_item] = {
        output = def.output,
        extra  = def.extra or {},
        time   = def.time  or 1.2,
        xp     = def.xp    or 0,
    }
end

-- Exact Create-Mod Crushing Wheel Conversions for Mineclonia
local DEFAULT_RECIPES = {
    -- Stone, Cobble, Gravel, Sand & Rock Cycle
    ["mcl_core:stone"]                         = {output = "mcl_core:cobble 1",                  time = 1.0},
    ["mcl_core:stone_smooth"]                  = {output = "mcl_core:cobble 1",                  time = 1.0},
    ["mcl_core:cobble"]                        = {output = "mcl_core:gravel 1",                  time = 1.0},
    ["mcl_core:mossycobble"]                   = {output = "mcl_core:gravel 1",                  time = 1.0},
    ["mcl_core:gravel"]                        = {output = "mcl_core:sand 1",                    time = 1.0, extra = {
        {item = "mcl_core:flint 1",     chance = 0.10},
        {item = "mcl_core:clay_lump 1", chance = 0.05},
    }},
    ["mcl_core:sand"]                          = {output = "mcl_core:clay_lump 1",               time = 1.0, extra = {
        {item = "mcl_bone_meal:bone_meal 1", chance = 0.15},
    }},
    ["mcl_core:redsand"]                       = {output = "mcl_core:clay_lump 1",               time = 1.0, extra = {
        {item = "mcl_core:gold_nugget 1", chance = 0.12},
        {item = "mcl_core:deadbush 1",    chance = 0.05},
    }},
    ["mcl_core:sandstone"]                     = {output = "mcl_core:sand 2",                    time = 1.0},
    ["mcl_core:sandstonesmooth"]               = {output = "mcl_core:sand 2",                    time = 1.0},
    ["mcl_core:sandstonecarved"]               = {output = "mcl_core:sand 2",                    time = 1.0},
    ["mcl_core:redsandstone"]                  = {output = "mcl_core:redsand 2",                 time = 1.0},
    ["mcl_core:redsandstonesmooth"]            = {output = "mcl_core:redsand 2",                 time = 1.0},
    ["mcl_core:redsandstonecarved"]            = {output = "mcl_core:redsand 2",                 time = 1.0},
    ["mcl_core:stonebrick"]                    = {output = "mcl_core:stonebrickcracked 1",       time = 1.0},
    ["mcl_core:stonebrickmossy"]               = {output = "mcl_core:stonebrickcracked 1",       time = 1.0},
    ["mcl_core:stonebrickcarved"]              = {output = "mcl_core:stonebrickcracked 1",       time = 1.0},
    ["mcl_core:stonebrickcracked"]             = {output = "mcl_core:cobble 1",                  time = 1.0},

    -- Igneous & Create Mineral Rocks (Andesite, Diorite, Granite, Tuff, Calcite, Dripstone, Deepslate)
    ["mcl_core:andesite"]                      = {output = "mcl_core:cobble 1",                  time = 1.1, extra = {
        {item = "mcl_core:flint 1", chance = 0.25},
    }},
    ["mcl_core:andesite_smooth"]               = {output = "mcl_core:cobble 1",                  time = 1.1},
    ["mcl_core:diorite"]                       = {output = "mcl_nether:quartz 1",                time = 1.2, extra = {
        {item = "mcl_nether:quartz 1", chance = 0.25},
    }},
    ["mcl_core:diorite_smooth"]                = {output = "mcl_nether:quartz 1",                time = 1.2, extra = {
        {item = "mcl_nether:quartz 1", chance = 0.25},
    }},
    ["mcl_core:granite"]                       = {output = "mcl_core:redsand 1",                 time = 1.1, extra = {
        {item = "mcl_nether:quartz 1", chance = 0.10},
    }},
    ["mcl_core:granite_smooth"]                = {output = "mcl_core:redsand 1",                 time = 1.1},
    ["mcl_amethyst:calcite"]                   = {output = "mcl_bone_meal:bone_meal 1",          time = 1.1, extra = {
        {item = "mcl_bone_meal:bone_meal 1", chance = 0.75},
    }},
    ["mcl_dripstone:dripstone_block"]          = {output = "mcl_core:clay_lump 1",               time = 1.1, extra = {
        {item = "mcl_core:clay_lump 1", chance = 0.50},
    }},
    ["mcl_dripstone:pointed_dripstone"]        = {output = "mcl_core:clay_lump 1",               time = 1.0, extra = {
        {item = "mcl_core:clay_lump 1", chance = 0.50},
    }},
    ["mcl_deepslate:deepslate"]                = {output = "mcl_deepslate:deepslate_cobbled 1",  time = 1.2},
    ["mcl_deepslate:deepslate_cobbled"]        = {output = "mcl_core:gravel 1",                  time = 1.2, extra = {
        {item = "mcl_core:flint 1", chance = 0.15},
    }},
    ["mcl_deepslate:tuff"]                     = {output = "mcl_core:flint 1",                   time = 1.4, extra = {
        {item = "mcl_core:iron_nugget 1",  chance = 0.25},
        {item = "mcl_core:gold_nugget 1",  chance = 0.20},
        {item = "mcl_copper:raw_copper 1", chance = 0.25},
    }},

    -- Nether, Blackstone & Obsidian
    ["mcl_nether:netherrack"]                  = {output = "mcl_nether:soul_sand 1",             time = 1.1, extra = {
        {item = "mcl_core:gold_nugget 1", chance = 0.15},
    }},
    ["mcl_nether:soul_soil"]                   = {output = "mcl_nether:soul_sand 1",             time = 1.0},
    ["mcl_blackstone:blackstone"]              = {output = "mcl_core:gravel 1",                  time = 1.2, extra = {
        {item = "mcl_core:coal_lump 1", chance = 0.25},
    }},
    ["mcl_blackstone:basalt"]                  = {output = "mcl_core:gravel 1",                  time = 1.2, extra = {
        {item = "mcl_mobitems:gunpowder 1", chance = 0.25},
    }},
    ["mcl_blackstone:basalt_smooth"]           = {output = "mcl_core:gravel 1",                  time = 1.2},
    ["mcl_blackstone:basalt_polished"]         = {output = "mcl_core:gravel 1",                  time = 1.2},
    ["mcl_end:end_stone"]                      = {output = "mcl_core:cobble 1",                  time = 1.4, extra = {
        {item = "mcl_throwing:ender_pearl 1", chance = 0.15},
    }},
    ["mcl_core:obsidian"]                      = {output = "mcl_core:crying_obsidian 1",         time = 2.4, extra = {
        {item = "mcl_core:obsidian 1", chance = 0.75},
    }},
    ["mcl_core:crying_obsidian"]               = {output = "mcl_core:obsidian 1",                time = 2.2, xp = 2, extra = {
        {item = "mcl_mobitems:ghast_tear 1", chance = 0.25},
    }},

    -- Overworld & Deepslate Ores (with Create's 12.5% Stone/Deepslate bonus drop + XP)
    ["mcl_core:stone_with_iron"]               = {output = "mcl_raw_ores:raw_iron 2",            time = 1.6, xp = 2, extra = {
        {item = "mcl_raw_ores:raw_iron 1", chance = 0.50},
        {item = "mcl_core:cobble 1",       chance = 0.125},
    }},
    ["mcl_deepslate:deepslate_with_iron"]      = {output = "mcl_raw_ores:raw_iron 3",            time = 1.8, xp = 3, extra = {
        {item = "mcl_raw_ores:raw_iron 1",             chance = 0.50},
        {item = "mcl_deepslate:deepslate_cobbled 1",   chance = 0.125},
    }},
    ["mcl_copper:stone_with_copper"]           = {output = "mcl_copper:raw_copper 5",            time = 1.6, xp = 2, extra = {
        {item = "mcl_copper:raw_copper 2", chance = 0.50},
        {item = "mcl_core:cobble 1",       chance = 0.125},
    }},
    ["mcl_core:stone_with_copper"]             = {output = "mcl_copper:raw_copper 5",            time = 1.6, xp = 2, extra = {
        {item = "mcl_copper:raw_copper 2", chance = 0.50},
        {item = "mcl_core:cobble 1",       chance = 0.125},
    }},
    ["mcl_deepslate:deepslate_with_copper"]    = {output = "mcl_copper:raw_copper 7",            time = 1.8, xp = 3, extra = {
        {item = "mcl_copper:raw_copper 2",             chance = 0.50},
        {item = "mcl_deepslate:deepslate_cobbled 1",   chance = 0.125},
    }},
    ["mcl_core:stone_with_gold"]               = {output = "mcl_raw_ores:raw_gold 2",            time = 1.6, xp = 3, extra = {
        {item = "mcl_raw_ores:raw_gold 1", chance = 0.50},
        {item = "mcl_core:cobble 1",       chance = 0.125},
    }},
    ["mcl_deepslate:deepslate_with_gold"]      = {output = "mcl_raw_ores:raw_gold 3",            time = 1.8, xp = 4, extra = {
        {item = "mcl_raw_ores:raw_gold 1",             chance = 0.50},
        {item = "mcl_deepslate:deepslate_cobbled 1",   chance = 0.125},
    }},
    ["mcl_nether:nether_gold_ore"]             = {output = "mcl_core:gold_nugget 18",            time = 1.5, xp = 3, extra = {
        {item = "mcl_core:gold_nugget 6",  chance = 0.50},
        {item = "mcl_nether:netherrack 1", chance = 0.125},
    }},
    ["mcl_blackstone:blackstone_gilded"]       = {output = "mcl_core:gold_nugget 18",            time = 1.6, xp = 4, extra = {
        {item = "mcl_core:gold_nugget 6",      chance = 0.50},
        {item = "mcl_blackstone:blackstone 1", chance = 0.125},
    }},
    ["mcl_core:stone_with_coal"]               = {output = "mcl_core:coal_lump 2",               time = 1.4, xp = 2, extra = {
        {item = "mcl_core:coal_lump 1", chance = 0.75},
        {item = "mcl_core:cobble 1",    chance = 0.125},
    }},
    ["mcl_deepslate:deepslate_with_coal"]      = {output = "mcl_core:coal_lump 3",               time = 1.6, xp = 2, extra = {
        {item = "mcl_core:coal_lump 1",              chance = 0.75},
        {item = "mcl_deepslate:deepslate_cobbled 1", chance = 0.125},
    }},
    ["mcl_core:stone_with_diamond"]            = {output = "mcl_core:diamond 2",                 time = 2.0, xp = 5, extra = {
        {item = "mcl_core:diamond 1", chance = 0.50},
        {item = "mcl_core:cobble 1",  chance = 0.125},
    }},
    ["mcl_deepslate:deepslate_with_diamond"]   = {output = "mcl_core:diamond 2",                 time = 2.2, xp = 6, extra = {
        {item = "mcl_core:diamond 1",                chance = 0.75},
        {item = "mcl_deepslate:deepslate_cobbled 1", chance = 0.125},
    }},
    ["mcl_core:stone_with_emerald"]            = {output = "mcl_core:emerald 2",                 time = 2.0, xp = 5, extra = {
        {item = "mcl_core:emerald 1", chance = 0.50},
        {item = "mcl_core:cobble 1",  chance = 0.125},
    }},
    ["mcl_deepslate:deepslate_with_emerald"]   = {output = "mcl_core:emerald 2",                 time = 2.2, xp = 6, extra = {
        {item = "mcl_core:emerald 1",                chance = 0.75},
        {item = "mcl_deepslate:deepslate_cobbled 1", chance = 0.125},
    }},
    ["mcl_core:stone_with_lapis"]              = {output = "mcl_core:lapis 10",                  time = 1.5, xp = 3, extra = {
        {item = "mcl_core:lapis 4",  chance = 0.50},
        {item = "mcl_core:cobble 1", chance = 0.125},
    }},
    ["mcl_deepslate:deepslate_with_lapis"]     = {output = "mcl_core:lapis 12",                  time = 1.7, xp = 4, extra = {
        {item = "mcl_core:lapis 4",                  chance = 0.50},
        {item = "mcl_deepslate:deepslate_cobbled 1", chance = 0.125},
    }},
    ["mcl_core:stone_with_redstone"]           = {output = "mesecons:redstone 6",                time = 1.5, xp = 3, extra = {
        {item = "mesecons:redstone 2", chance = 0.50},
        {item = "mcl_core:cobble 1",   chance = 0.125},
    }},
    ["mcl_core:stone_with_redstone_lit"]       = {output = "mesecons:redstone 6",                time = 1.5, xp = 3, extra = {
        {item = "mesecons:redstone 2", chance = 0.50},
        {item = "mcl_core:cobble 1",   chance = 0.125},
    }},
    ["mcl_deepslate:deepslate_with_redstone"]  = {output = "mesecons:redstone 7",                time = 1.7, xp = 3, extra = {
        {item = "mesecons:redstone 2",               chance = 0.50},
        {item = "mcl_deepslate:deepslate_cobbled 1", chance = 0.125},
    }},
    ["mcl_deepslate:deepslate_with_redstone_lit"] = {output = "mesecons:redstone 7",             time = 1.7, xp = 3, extra = {
        {item = "mesecons:redstone 2",               chance = 0.50},
        {item = "mcl_deepslate:deepslate_cobbled 1", chance = 0.125},
    }},
    ["mcl_nether:quartz_ore"]                  = {output = "mcl_nether:quartz 3",                time = 1.5, xp = 3, extra = {
        {item = "mcl_nether:quartz 1",     chance = 0.50},
        {item = "mcl_nether:netherrack 1", chance = 0.125},
    }},
    ["mcl_nether:ancient_debris"]              = {output = "mcl_nether:netherite_scrap 1",       time = 2.8, xp = 8, extra = {
        {item = "mcl_nether:netherite_scrap 1", chance = 0.50},
    }},

    -- Raw Ores & Raw Ore Storage Blocks
    ["mcl_raw_ores:raw_iron"]                  = {output = "mcl_core:iron_nugget 9",             time = 1.2, xp = 1, extra = {
        {item = "mcl_core:iron_nugget 6", chance = 0.50},
    }},
    ["mcl_raw_ores:raw_gold"]                  = {output = "mcl_core:gold_nugget 9",             time = 1.2, xp = 2, extra = {
        {item = "mcl_core:gold_nugget 6", chance = 0.50},
    }},
    ["mcl_copper:raw_copper"]                  = {output = "mcl_copper:copper_ingot 1",          time = 1.2, xp = 1, extra = {
        {item = "mcl_copper:copper_ingot 1", chance = 0.50},
    }},
    ["mcl_raw_ores:raw_iron_block"]            = {output = "mcl_core:iron_ingot 9",              time = 2.4, xp = 9, extra = {
        {item = "mcl_core:iron_ingot 3", chance = 0.75},
    }},
    ["mcl_raw_ores:raw_gold_block"]            = {output = "mcl_core:gold_ingot 9",              time = 2.4, xp = 14, extra = {
        {item = "mcl_core:gold_ingot 3", chance = 0.75},
    }},
    ["mcl_copper:block_raw"]                   = {output = "mcl_copper:copper_ingot 9",          time = 2.4, xp = 9, extra = {
        {item = "mcl_copper:copper_ingot 3", chance = 0.75},
    }},

    -- Mob Drops, Plants, Dyes & Storage Blocks
    ["mcl_mobitems:bone"]                      = {output = "mcl_bone_meal:bone_meal 3",          time = 0.9, extra = {
        {item = "mcl_bone_meal:bone_meal 3", chance = 0.50},
    }},
    ["mcl_bone_meal:bone_block"]               = {output = "mcl_bone_meal:bone_meal 9",          time = 1.2, extra = {
        {item = "mcl_bone_meal:bone_meal 3", chance = 0.50},
    }},
    ["mcl_mobitems:blaze_rod"]                 = {output = "mcl_mobitems:blaze_powder 3",        time = 1.1, extra = {
        {item = "mcl_mobitems:blaze_powder 3", chance = 0.50},
    }},
    ["mcl_nether:magma"]                       = {output = "mcl_mobitems:magma_cream 2",         time = 1.2, extra = {
        {item = "mcl_mobitems:magma_cream 2", chance = 0.50},
    }},
    ["mcl_core:reeds"]                         = {output = "mcl_core:sugar 2",                   time = 0.9, extra = {
        {item = "mcl_core:sugar 1", chance = 0.50},
    }},
    ["mcl_farming:wheat_item"]                 = {output = "mcl_farming:bread 1",                time = 1.0, extra = {
        {item = "mcl_farming:wheat_seeds 2", chance = 0.50},
    }},
    ["mcl_farming:beetroot_item"]              = {output = "mcl_dyes:red 2",                     time = 0.9, extra = {
        {item = "mcl_core:sugar 1", chance = 0.10},
    }},
    ["mcl_core:cactus"]                        = {output = "mcl_dyes:green 2",                   time = 0.9, extra = {
        {item = "mcl_dyes:green 1", chance = 0.50},
    }},
    ["mcl_core:coal_lump"]                     = {output = "mcl_dyes:black 1",                   time = 0.9, extra = {
        {item = "mcl_dyes:black 1", chance = 0.25},
    }},
    ["mcl_core:charcoal_lump"]                 = {output = "mcl_dyes:black 1",                   time = 0.9, extra = {
        {item = "mcl_dyes:black 1", chance = 0.25},
    }},
    ["mcl_mobitems:ink_sac"]                   = {output = "mcl_dyes:black 2",                   time = 0.9, extra = {
        {item = "mcl_dyes:black 1", chance = 0.50},
    }},
    ["mcl_nether:glowstone"]                   = {output = "mcl_nether:glowstone_dust 4",        time = 0.9},
    ["mcl_nether:quartz_block"]                = {output = "mcl_nether:quartz 4",                time = 1.1},
    ["mcl_nether:quartz_pillar"]               = {output = "mcl_nether:quartz 4",                time = 1.1},
    ["mcl_nether:quartz_chiseled"]             = {output = "mcl_nether:quartz 4",                time = 1.1},
    ["mcl_nether:quartz_smooth"]               = {output = "mcl_nether:quartz 4",                time = 1.1},
    ["mcl_amethyst:amethyst_block"]            = {output = "mcl_amethyst:amethyst_shard 3",      time = 1.1, extra = {
        {item = "mcl_amethyst:amethyst_shard 1", chance = 0.50},
    }},
    ["mcl_amethyst:amethyst_cluster"]          = {output = "mcl_amethyst:amethyst_shard 7",      time = 1.1, extra = {
        {item = "mcl_amethyst:amethyst_shard 1", chance = 0.50},
    }},
    ["mcl_ocean:prismarine"]                   = {output = "mcl_ocean:prismarine_shard 4",       time = 1.2},
    ["mcl_ocean:prismarine_brick"]             = {output = "mcl_ocean:prismarine_shard 9",       time = 1.4},
    ["mcl_ocean:prismarine_dark"]              = {output = "mcl_ocean:prismarine_shard 8",       time = 1.4, extra = {
        {item = "mcl_dyes:black 1", chance = 1.0},
    }},
    ["mcl_ocean:sea_lantern"]                  = {output = "mcl_ocean:prismarine_crystals 5",    time = 1.1},
    ["mcl_core:clay"]                          = {output = "mcl_core:clay_lump 4",               time = 0.9},
    ["mcl_core:brick_block"]                   = {output = "mcl_core:brick 4",                   time = 1.1},
    ["mcl_nether:nether_brick"]                = {output = "mcl_nether:netherbrick 4",           time = 1.1},
    ["mcl_colorblocks:hardened_clay"]          = {output = "mcl_core:redsand 1",                 time = 1.1, extra = {
        {item = "mcl_core:clay_lump 1", chance = 0.25},
    }},
    ["mcl_core:cobweb"]                        = {output = "mcl_mobitems:string 2",              time = 0.9, extra = {
        {item = "mcl_mobitems:string 1", chance = 0.50},
    }},
    ["mcl_mobitems:saddle"]                    = {output = "mcl_mobitems:leather 2",             time = 1.4, extra = {
        {item = "mcl_mobitems:leather 2", chance = 0.50},
        {item = "mcl_core:iron_ingot 1",  chance = 0.50},
    }},
    ["mcl_sculk:sculk"]                        = {output = "mcl_bone_meal:bone_meal 1",          time = 0.9, xp = 2},
    ["mcl_sculk:catalyst"]                     = {output = "mcl_bone_meal:bone_meal 3",          time = 1.4, xp = 10},
    ["mcl_sculk:shrieker"]                     = {output = "mcl_bone_meal:bone_meal 3",          time = 1.4, xp = 10},
}

for iname, rdef in pairs(DEFAULT_RECIPES) do
    kinetica.register_crushing_recipe(iname, rdef)
end

local function get_crushing_recipe_for_item(item_name, stack)
    if not item_name or item_name == "" then return nil end
    if kinetica.crushing_recipes[item_name] then
        return kinetica.crushing_recipes[item_name]
    end

    if core.get_item_group(item_name, "wool") > 0 then
        return {
            output = "mcl_mobitems:string 2",
            time   = 1.0,
            extra  = {{item = "mcl_mobitems:string 2", chance = 0.50}},
        }
    end

    if core.get_item_group(item_name, "carpet") > 0 then
        return {
            output = "mcl_mobitems:string 1",
            time   = 0.8,
            extra  = {{item = "mcl_mobitems:string 1", chance = 0.50}},
        }
    end

    if core.get_item_group(item_name, "hardened_clay") > 0 or
       string.find(item_name, "^mcl_colorblocks:hardened_clay") then
        return {
            output = "mcl_core:redsand 1",
            time   = 1.1,
            extra  = {{item = "mcl_core:clay_lump 1", chance = 0.25}},
        }
    end

    if core.get_item_group(item_name, "flower") > 0 then
        local res = core.get_craft_result({method = "normal", width = 1, items = {ItemStack(item_name .. " 1")}})
        if res and res.item and not res.item:is_empty() then
            local dname = res.item:get_name()
            local dcnt  = math.max(1, res.item:get_count())
            return {
                output = dname .. " " .. (dcnt * 2),
                time   = 0.9,
                extra  = {
                    {item = dname .. " 1",          chance = 0.50},
                    {item = "mcl_dyes:green 1",     chance = 0.10},
                },
            }
        end
    end

    if core.get_item_group(item_name, "leaves") > 0 then
        return {
            output = "mcl_core:stick 1",
            time   = 0.8,
            extra  = {{item = "mcl_bone_meal:bone_meal 1", chance = 0.20}},
        }
    end

    if string.find(item_name, "horse_armor") then
        if string.find(item_name, "iron") then
            return {output = "mcl_core:iron_ingot 2", time = 1.6, extra = {{item = "mcl_core:iron_nugget 4", chance = 0.50}}}
        elseif string.find(item_name, "gold") then
            return {output = "mcl_core:gold_ingot 2", time = 1.6, extra = {{item = "mcl_core:gold_nugget 4", chance = 0.50}}}
        elseif string.find(item_name, "diamond") then
            return {output = "mcl_core:diamond 2", time = 2.0, extra = {{item = "mcl_core:diamond 1", chance = 0.50}}}
        elseif string.find(item_name, "leather") then
            return {output = "mcl_mobitems:leather 2", time = 1.2, extra = {{item = "mcl_mobitems:leather 2", chance = 0.50}}}
        end
    end

    local is_gear = (core.get_item_group(item_name, "tool") > 0 or
                     core.get_item_group(item_name, "armor") > 0 or
                     core.get_item_group(item_name, "weapon") > 0 or
                     string.find(item_name, "helmet") or string.find(item_name, "chestplate") or
                     string.find(item_name, "leggings") or string.find(item_name, "boots") or
                     string.find(item_name, "sword") or string.find(item_name, "pick") or
                     string.find(item_name, "axe") or string.find(item_name, "shovel") or string.find(item_name, "hoe"))

    if is_gear then
        local wear_ratio = 1.0
        if stack and stack:get_wear() > 0 then
            wear_ratio = math.max(0.25, 1.0 - (stack:get_wear() / 65535))
        end
        local is_heavy = (string.find(item_name, "chestplate") or string.find(item_name, "leggings") or
                          string.find(item_name, "pick") or string.find(item_name, "axe"))

        if string.find(item_name, "netherite_") then
            return {output = "mcl_core:diamond 1", time = 2.4, xp = 4, extra = {{item = "mcl_nether:netherite_scrap 1", chance = 0.50 * wear_ratio}}}
        elseif string.find(item_name, "diamond_") then
            local d_cnt = is_heavy and math.max(1, math.floor(2 * wear_ratio + 0.5)) or 1
            return {output = "mcl_core:diamond " .. d_cnt, time = 2.0, xp = 2}
        elseif string.find(item_name, "iron_") or string.find(item_name, "chainmail_") then
            local base_nug = math.max(3, math.floor((is_heavy and 12 or 6) * wear_ratio))
            return {output = "mcl_core:iron_nugget " .. base_nug, time = 1.4, xp = 1}
        elseif string.find(item_name, "gold_") then
            local base_nug = math.max(3, math.floor((is_heavy and 12 or 6) * wear_ratio))
            return {output = "mcl_core:gold_nugget " .. base_nug, time = 1.4, xp = 1}
        end
    end
    return nil
end

local function add_smooth_disc(boxes, axis_mode, a1, a2, radius, steps)
    local step_size = (radius * 2) / steps
    for i = 0, steps - 1 do
        local u1  = -radius + i * step_size
        local u2  = u1 + step_size
        local mid = (u1 + u2) * 0.5
        local half_chord = math.sqrt(math.max(0, radius * radius - mid * mid))
        if half_chord > 0.01 then
            if axis_mode == "x" then
                boxes[#boxes + 1] = {a1, u1, -half_chord, a2, u2, half_chord}
                boxes[#boxes + 1] = {a1, -half_chord, u1, a2, half_chord, u2}
            else
                boxes[#boxes + 1] = {u1, a1, -half_chord, u2, a2, half_chord}
                boxes[#boxes + 1] = {-half_chord, a1, u1, half_chord, a2, u2}
            end
        end
    end
end

local function build_circular_crushing_wheel_boxes(axis_mode)
    local boxes = {}
    if axis_mode == "x" then
        boxes[#boxes + 1] = {-8/16, -3/16, -3/16,  8/16,  3/16,  3/16}
    else
        boxes[#boxes + 1] = {-3/16, -8/16, -3/16,  3/16,  8/16,  3/16}
    end

    add_smooth_disc(boxes, axis_mode, -6.5/16, 6.5/16, 6.4/16, 16)
    local rings = {
        {-6.2/16, -4.6/16},
        {-2.8/16, -0.9/16},
        { 0.9/16,  2.8/16},
        { 4.6/16,  6.2/16},
    }
    for _, r in ipairs(rings) do
        add_smooth_disc(boxes, axis_mode, r[1], r[2], 7.6/16, 20)
    end

    local tooth_spans = {
        {-1.1/16, 1.1/16, 8.0/16},
        {-4.2/16, -2.6/16, 7.85/16},
        { 2.6/16,  4.2/16, 7.85/16},
    }
    for _, ts in ipairs(tooth_spans) do
        local u1, u2, ext = ts[1], ts[2], ts[3]
        if axis_mode == "x" then
            boxes[#boxes + 1] = {-6.0/16, u1, -ext, 6.0/16, u2, ext}
            boxes[#boxes + 1] = {-6.0/16, -ext, u1, 6.0/16, ext, u2}
        else
            boxes[#boxes + 1] = {u1, -6.0/16, -ext, u2, 6.0/16, ext}
            boxes[#boxes + 1] = {-ext, -6.0/16, u1, ext, 6.0/16, u2}
        end
    end
    return boxes
end

local WHEEL_BOXES_UPRIGHT = build_circular_crushing_wheel_boxes("x")
local WHEEL_BOXES_FLAT    = build_circular_crushing_wheel_boxes("y")

local HUB_COLLISION_BOX = {
    type  = "fixed",
    fixed = {{-3/16, -3/16, -3/16, 3/16, 3/16, 3/16}},
}

local WHEEL_SELECTION_BOX = {
    type  = "fixed",
    fixed = {{-7/16, -7/16, -7/16, 7/16, 7/16, 7/16}},
}

core.register_node(MESH_UPRIGHT_NAME, {
    description         = "Crushing Wheel Upright Rotor Mesh",
    drawtype            = "nodebox",
    paramtype           = "light",
    sunlight_propagates = true,
    tiles = {
        STONE_TEX,
        STONE_TEX,
        HUB_AXLE_TEX,
        HUB_AXLE_TEX,
        GROOVE_TEX,
        GROOVE_TEX,
    },
    node_box = {
        type  = "fixed",
        fixed = WHEEL_BOXES_UPRIGHT,
    },
    groups = {not_in_creative_inventory = 1},
})

core.register_node(MESH_FLAT_NAME, {
    description         = "Crushing Wheel Flat Rotor Mesh",
    drawtype            = "nodebox",
    paramtype           = "light",
    sunlight_propagates = true,
    tiles = {
        HUB_AXLE_TEX,
        HUB_AXLE_TEX,
        STONE_TEX,
        STONE_TEX,
        GROOVE_TEX,
        GROOVE_TEX,
    },
    node_box = {
        type  = "fixed",
        fixed = WHEEL_BOXES_FLAT,
    },
    groups = {not_in_creative_inventory = 1},
})

function kinetica.is_crushing_wheel(name)
    return name == IDLE_NAME or name == ACTIVE_NAME
end

function kinetica.get_crushing_wheel_axis(param2)
    local p2  = (param2 or 0) % 24
    local dir = core.facedir_to_dir(p2) or {x = 0, y = 0, z = 1}
    return {
        x = math.abs(dir.x),
        y = math.abs(dir.y),
        z = math.abs(dir.z),
    }
end

local function normalize_wheel_param2(axis)
    if axis.y ~= 0 then
        return 4
    elseif axis.x ~= 0 then
        return 1
    else
        return 0
    end
end

local function get_upright_wheel_yaw(axis)
    if axis.x ~= 0 then
        return 0
    else
        return math.pi * 0.5
    end
end

local function calc_wheel_demand_ku(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then return 0 end
    local raw = math.floor(rpm * CONFIG.KU_PER_RPM)
    return math.min(CONFIG.MAX_DEMAND_KU, math.max(CONFIG.MIN_DEMAND_KU, raw))
end

local function calc_spin_rad_per_sec(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then return 0 end
    local ratio = math.min(1.0, math.max(0.0, (rpm - CONFIG.MIN_RPM) / (512 - CONFIG.MIN_RPM)))
    return CONFIG.BASE_SPIN_RAD_PER_SEC + ratio * (CONFIG.MAX_SPIN_RAD_PER_SEC - CONFIG.BASE_SPIN_RAD_PER_SEC)
end

local function calc_crush_speed_multiplier(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then return 0.25 end
    return math.max(0.25, (rpm / CONFIG.BASE_SPEED_RPM) ^ CONFIG.RPM_SPEED_EXPONENT)
end

local function get_node_abs_axis(param2)
    if kinetica.abs_axis then
        return kinetica.abs_axis(param2)
    end
    local d = core.facedir_to_dir((param2 or 0) % 24) or {x = 0, y = 0, z = 1}
    return {x = math.abs(d.x), y = math.abs(d.y), z = math.abs(d.z)}
end

local function neighbor_has_port_facing_wheel(enode, ename, emeta, axis, dir_to_wheel)
    if not ename or ename == "air" or ename == "ignore" or kinetica.is_crushing_wheel(ename) then
        return false
    end
    if kinetica.has_axle_port and kinetica.has_axle_port(enode, dir_to_wheel) then
        return true
    end
    if (kinetica.is_shaft and kinetica.is_shaft(ename)) or
       core.get_item_group(ename, "shaft") > 0 or
       string.find(ename, "shaft") then
        local s_ax = get_node_abs_axis(enode.param2)
        return (s_ax.x == axis.x and s_ax.y == axis.y and s_ax.z == axis.z)
    end
    if (kinetica.is_cogwheel and kinetica.is_cogwheel(ename)) or
       core.get_item_group(ename, "cogwheel") > 0 or
       string.find(ename, "cog") then
        local c_ax = get_node_abs_axis(enode.param2)
        return (c_ax.x == axis.x and c_ax.y == axis.y and c_ax.z == axis.z)
    end
    if (kinetica.is_gearbox and kinetica.is_gearbox(ename)) or string.find(ename, "gearbox") then
        local is_vert = (string.find(ename, "vertical") ~= nil)
        if not is_vert then
            return (axis.y == 0)
        else
            if axis.y ~= 0 then
                return true
            end
            local fdir = core.facedir_to_dir((enode.param2 or 0) % 4) or {x = 0, y = 0, z = 1}
            return (math.abs(fdir.x) == axis.x and math.abs(fdir.z) == axis.z)
        end
    end
    if (kinetica.is_chain_drive and kinetica.is_chain_drive(ename)) or string.find(ename, "chain_drive") then
        local cd_ax = get_node_abs_axis(enode.param2)
        return (cd_ax.x == axis.x and cd_ax.y == axis.y and cd_ax.z == axis.z)
    end
    if (kinetica.is_speed_controller and kinetica.is_speed_controller(ename)) or string.find(ename, "speed_controller") then
        if axis.y ~= 0 then return false end
        local fdir = core.facedir_to_dir((enode.param2 or 0) % 4) or {x = 0, y = 0, z = 1}
        return (math.abs(fdir.x) == axis.x and math.abs(fdir.z) == axis.z)
    end
    if (kinetica.is_belt and kinetica.is_belt(ename)) or string.find(ename, "belt") then
        if emeta:get_int("has_shaft") ~= 1 or axis.y ~= 0 then
            return false
        end
        local bdir = core.facedir_to_dir((enode.param2 or 0) % 4) or {x = 0, y = 0, z = 1}
        local pulley_ax_x = math.abs(bdir.z)
        local pulley_ax_z = math.abs(bdir.x)
        return (pulley_ax_x == axis.x and pulley_ax_z == axis.z)
    end
    if ename == "kinetica:water_wheel_big" or
       (kinetica.is_water_wheel and kinetica.is_water_wheel(ename)) or
       string.find(ename, "water_wheel") then
        if axis.y ~= 0 then return false end
        local canon_p2 = (enode.param2 or 0) % 2
        local bdir     = core.facedir_to_dir(canon_p2) or {x = 0, y = 0, z = 1}
        return (math.abs(bdir.x) == axis.x and math.abs(bdir.z) == axis.z)
    end
    if (kinetica.is_turbine and kinetica.is_turbine(ename)) or string.find(ename, "turbine") or string.find(ename, "windmill") then
        if axis.y ~= 0 then return false end
        local fdir = core.facedir_to_dir((enode.param2 or 0) % 4) or {x = 0, y = 0, z = 1}
        return (math.abs(dir_to_wheel.x) == math.abs(fdir.x) and math.abs(dir_to_wheel.z) == math.abs(fdir.z))
    end
    if core.get_item_group(ename, "rotational_source") > 0 or
       core.get_item_group(ename, "kinetic_source") > 0 or
       emeta:get_float("rpm") > 0 or
       emeta:get_float("source_rpm") > 0 then
        return true
    end
    return false
end

local function extract_meta_power(m)
    local rpm  = m:get_float("rpm")
    local sup  = m:get_int("network_supply_ku")
    local ava  = m:get_int("rotational_power")
    local spn  = m:get_int("spin_dir")

    if (rpm <= 0 or sup <= 0) and m:get_int("source_active") == 1 then
        local s_rpm = m:get_float("source_rpm")
        local s_ku  = m:get_int("source_ku")
        if s_rpm > 0 then rpm = s_rpm end
        if s_ku > 0 then
            sup = s_ku
            ava = s_ku
        end
        if spn == 0 then spn = m:get_int("source_spin") end
    end

    if rpm > 0 and sup <= 0 then
        sup = math.max(128, calc_wheel_demand_ku(rpm))
        if ava <= 0 then ava = sup end
    end
    if spn == 0 then spn = m:get_int("local_spin") end
    if spn == 0 then spn = 1 end

    return (rpm >= CONFIG.MIN_RPM and sup > 0), rpm, sup, ava, spn
end

local function read_wheel_direct_power(pos, axis, meta)
    local ends = {
        {x =  axis.x, y =  axis.y, z =  axis.z},
        {x = -axis.x, y = -axis.y, z = -axis.z},
    }

    local has_connected_port = false
    for _, d_out in ipairs(ends) do
        local epos         = {x = pos.x + d_out.x, y = pos.y + d_out.y, z = pos.z + d_out.z}
        local dir_to_wheel = {x = -d_out.x,        y = -d_out.y,        z = -d_out.z}
        local enode        = core.get_node(epos)
        local ename        = enode.name
        local emeta        = core.get_meta(epos)

        if neighbor_has_port_facing_wheel(enode, ename, emeta, axis, dir_to_wheel) then
            has_connected_port = true
            local ok, erpm, esup, eava, espn = extract_meta_power(emeta)
            if ok then
                return true, erpm, esup, eava, espn
            end
        end
    end

    -- Fallback to wheel's own network metadata if a port neighbor is attached
    if has_connected_port then
        local ok, mrpm, msup, mava, mspn = extract_meta_power(meta)
        if ok then
            return true, mrpm, msup, mava, mspn
        end
    end

    return false, 0, 0, 0, 1
end

local function is_valid_middle_space(name)
    if not name or name == "air" then return true end
    if kinetica.is_belt and kinetica.is_belt(name) then return true end
    if string.find(name, "belt") or string.find(name, "depot") or
       string.find(name, "chute") or string.find(name, "hopper") then
        return true
    end
    if name == "kinetica:depot" or core.get_item_group(name, "kinetica_depot") > 0 then return true end
    if kinetica.is_chute and kinetica.is_chute(name) then return true end
    local ndef = core.registered_nodes[name]
    if ndef and (not ndef.walkable or ndef.buildable_to) then
        return true
    end
    return false
end

local function find_paired_wheel(pos, axis, my_pow, my_rpm, my_sup, my_ava, my_spin)
    local perp_dirs = {}
    if axis.y ~= 0 then
        perp_dirs = {
            {x =  1, y = 0, z =  0},
            {x = -1, y = 0, z =  0},
            {x =  0, y = 0, z =  1},
            {x =  0, y = 0, z = -1},
        }
    elseif axis.x ~= 0 then
        perp_dirs = {
            {x = 0, y =  0, z =  1},
            {x = 0, y =  0, z = -1},
            {x = 0, y =  1, z =  0},
            {x = 0, y = -1, z =  0},
        }
    else
        perp_dirs = {
            {x =  1, y =  0, z = 0},
            {x = -1, y =  0, z = 0},
            {x =  0, y =  1, z = 0},
            {x =  0, y = -1, z = 0},
        }
    end

    for _, d in ipairs(perp_dirs) do
        for dist = 1, 2 do
            local ppos  = {x = pos.x + d.x * dist, y = pos.y + d.y * dist, z = pos.z + d.z * dist}
            local pnode = core.get_node(ppos)
            if kinetica.is_crushing_wheel(pnode.name) then
                local p_axis = kinetica.get_crushing_wheel_axis(pnode.param2)
                if p_axis.x == axis.x and p_axis.y == axis.y and p_axis.z == axis.z then
                    local mid_ok  = true
                    local mid_pos = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
                    if dist == 2 then
                        mid_ok = is_valid_middle_space(core.get_node(mid_pos).name)
                    end

                    if mid_ok then
                        local pmeta = core.get_meta(ppos)
                        local p_pow, p_rpm, p_sup, p_ava, p_spin = read_wheel_direct_power(ppos, p_axis, pmeta)

                        local eff_pow    = my_pow or (CONFIG.ALLOW_GEAR_MESH_PARTNER and p_pow)
                        local eff_rpm    = my_pow and my_rpm or ((CONFIG.ALLOW_GEAR_MESH_PARTNER and p_pow) and p_rpm or 0)
                        local eff_sup    = my_pow and my_sup or ((CONFIG.ALLOW_GEAR_MESH_PARTNER and p_pow) and p_sup or 0)
                        local eff_ava    = my_pow and my_ava or ((CONFIG.ALLOW_GEAR_MESH_PARTNER and p_pow) and p_ava or 0)
                        local eff_spin   = my_pow and my_spin or ((CONFIG.ALLOW_GEAR_MESH_PARTNER and p_pow) and (-p_spin) or 1)
                        local pair_ready = false
                        local pair_rpm   = 0

                        if my_pow and p_pow and my_rpm >= CONFIG.MIN_RPM and p_rpm >= CONFIG.MIN_RPM then
                            pair_ready = true
                            pair_rpm   = math.max(my_rpm, p_rpm)
                        elseif CONFIG.ALLOW_GEAR_MESH_PARTNER and eff_pow and eff_rpm >= CONFIG.MIN_RPM then
                            pair_ready = true
                            pair_rpm   = eff_rpm
                        end

                        local is_master = (pos.x < ppos.x) or
                                          (pos.x == ppos.x and pos.y < ppos.y) or
                                          (pos.x == ppos.x and pos.y == ppos.y and pos.z < ppos.z)

                        local seam_pos = {
                            x = (pos.x + ppos.x) * 0.5,
                            y = (pos.y + ppos.y) * 0.5,
                            z = (pos.z + ppos.z) * 0.5,
                        }

                        local feed_dir        = {x = 0, y = -1, z = 0}
                        local inward_vis_spin = eff_spin
                        local mid_name        = core.get_node(mid_pos).name

                        if axis.y == 0 and d.y == 0 then
                            if dist == 2 and ((kinetica.is_belt and kinetica.is_belt(mid_name)) or string.find(mid_name, "belt")) then
                                local bnode = core.get_node(mid_pos)
                                local bdir  = core.facedir_to_dir((bnode.param2 or 0) % 4)
                                if bdir then
                                    local tsign = string.find(bnode.name, "_rev", 1, true) and -1 or 1
                                    feed_dir = {x = -bdir.x * tsign, y = 0, z = -bdir.z * tsign}
                                end
                            end
                            local side_sign = (d.x + d.z)
                            inward_vis_spin = (side_sign > 0) and 1 or -1
                        else
                            local horiz_perp = {x = -d.z, y = 0, z = d.x}
                            if horiz_perp.x == 0 and horiz_perp.z == 0 then
                                horiz_perp = (axis.x ~= 0) and {x = 0, y = 0, z = 1} or {x = 1, y = 0, z = 0}
                            end
                            if dist == 2 and ((kinetica.is_belt and kinetica.is_belt(mid_name)) or string.find(mid_name, "belt")) then
                                local bnode = core.get_node(mid_pos)
                                local bdir  = core.facedir_to_dir((bnode.param2 or 0) % 4)
                                if bdir then
                                    local tsign = string.find(bnode.name, "_rev", 1, true) and -1 or 1
                                    horiz_perp = {x = -bdir.x * tsign, y = 0, z = -bdir.z * tsign}
                                end
                            end
                            feed_dir = {
                                x = (horiz_perp.x ~= 0) and (horiz_perp.x > 0 and 1 or -1) or 0,
                                y = 0,
                                z = (horiz_perp.z ~= 0) and (horiz_perp.z > 0 and 1 or -1) or 0,
                            }
                            local side_sign = (d.x + d.y + d.z)
                            inward_vis_spin = (side_sign > 0) and 1 or -1
                        end

                        return {
                            partner_pos     = ppos,
                            dir_to_part     = d,
                            dist            = dist,
                            is_master       = is_master,
                            seam_pos        = seam_pos,
                            eff_pow         = eff_pow,
                            eff_rpm         = eff_rpm,
                            eff_sup         = eff_sup,
                            eff_ava         = eff_ava,
                            eff_spin        = eff_spin,
                            pair_ready      = pair_ready,
                            pair_rpm        = pair_rpm,
                            feed_dir        = feed_dir,
                            inward_vis_spin = inward_vis_spin,
                        }
                    end
                end
            end
        end
    end
    return nil
end

core.register_entity(ENTITY_NAME, {
    initial_properties = {
        physical             = false,
        collide_with_objects = false,
        pointable            = false,
        visual               = "wielditem",
        wield_item           = MESH_UPRIGHT_NAME,
        visual_size          = {
            x = 0.6667,
            y = 0.6667 * CONFIG.WHEEL_SCALE_BELT_GAP,
            z = 0.6667 * CONFIG.WHEEL_SCALE_BELT_GAP,
        },
        static_save          = false,
        shaded               = true,
    },

    on_activate = function(self, staticdata)
        self.object:set_armor_groups({immortal = 1})
        self.angle   = 0
        self.speed   = 0
        self.yaw     = 0
        self.is_flat = false
        self.scale   = CONFIG.WHEEL_SCALE_BELT_GAP

        core.after(0.2, function()
            if self.object and self.object:get_luaentity() then
                local pos = self.object:get_pos()
                if pos then
                    local node = core.get_node(vector.round(pos))
                    if not kinetica.is_crushing_wheel(node.name) then
                        self.object:remove()
                    end
                end
            end
        end)
    end,

    on_step = function(self, dtime)
        if self.speed and self.speed ~= 0 then
            self.angle = self.angle + (self.speed * dtime)
            if self.angle > math.pi * 2 then self.angle = self.angle - (math.pi * 2) end
            if self.angle < -math.pi * 2 then self.angle = self.angle + (math.pi * 2) end

            if self.is_flat then
                self.object:set_rotation({x = 0, y = self.angle, z = 0})
            else
                self.object:set_rotation({x = self.angle, y = self.yaw or 0, z = 0})
            end
        end
    end,
})

local function sync_crushing_wheel_entity(pos, axis, speed_rad, scale_mult)
    local wheel_obj = nil
    for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.5)) do
        local luaent = obj:get_luaentity()
        if luaent and luaent.name == ENTITY_NAME then
            if not wheel_obj then
                wheel_obj = obj
            else
                obj:remove()
            end
        end
    end

    if not wheel_obj then
        wheel_obj = core.add_entity(pos, ENTITY_NAME)
    end

    if wheel_obj then
        local luaent = wheel_obj:get_luaentity()
        if luaent then
            local want_flat = (axis.y ~= 0)
            local want_item = want_flat and MESH_FLAT_NAME or MESH_UPRIGHT_NAME
            local vs
            if want_flat then
                vs = {
                    x = 0.6667 * scale_mult,
                    y = 0.6667,
                    z = 0.6667 * scale_mult,
                }
            else
                vs = {
                    x = 0.6667,
                    y = 0.6667 * scale_mult,
                    z = 0.6667 * scale_mult,
                }
            end

            if luaent.is_flat ~= want_flat or math.abs((luaent.scale or 0) - scale_mult) > 0.01 then
                luaent.is_flat = want_flat
                luaent.scale   = scale_mult
                wheel_obj:set_properties({
                    wield_item  = want_item,
                    visual_size = vs,
                })
            end

            luaent.yaw   = get_upright_wheel_yaw(axis)
            luaent.speed = speed_rad

            if want_flat then
                wheel_obj:set_rotation({x = 0, y = luaent.angle or 0, z = 0})
            else
                wheel_obj:set_rotation({x = luaent.angle or 0, y = luaent.yaw, z = 0})
            end
        end
    end
end

local function remove_wheel_entity(pos)
    for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.65)) do
        local le = obj:get_luaentity()
        if le and le.name == ENTITY_NAME then
            obj:remove()
        end
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

local function make_bar(used, total)
    local slots = 10
    if not total or total <= 0 then
        return "[" .. string.rep("░", slots) .. "] 0%"
    end
    local ratio  = math.min(1.0, math.max(0.0, (used or 0) / total))
    local filled = math.floor(ratio * slots + 0.5)
    local pct    = math.min(100, math.floor(ratio * 100 + 0.5))
    return string.format("[%s%s] %d%%", string.rep("█", filled), string.rep("░", slots - filled), pct)
end

local function dir_to_compass(v)
    if not v then return "Top (+Y) -> Down (-Y)" end
    if v.y < 0 then return "Drop from TOP (+Y) -> Down (-Y)" end
    if v.x > 0 then return "From WEST (-X) -> East (+X)" end
    if v.x < 0 then return "From EAST (+X) -> West (-X)" end
    if v.z > 0 then return "From SOUTH (-Z) -> North (+Z)" end
    if v.z < 0 then return "From NORTH (+Z) -> South (-Z)" end
    return "Center Seam"
end

local function format_crushing_wheel_glasses_info(pos, node)
    local meta   = core.get_meta(pos)
    local axis   = kinetica.get_crushing_wheel_axis(node.param2)
    local my_pow, my_rpm, my_sup, my_ava, my_spin = read_wheel_direct_power(pos, axis, meta)
    local pair   = find_paired_wheel(pos, axis, my_pow, my_rpm, my_sup, my_ava, my_spin)

    local eff_pow = pair and pair.eff_pow or my_pow
    local eff_rpm = pair and pair.eff_rpm or (my_pow and my_rpm or 0)
    local supply  = pair and pair.eff_sup or my_sup
    local avail   = pair and pair.eff_ava or my_ava
    local demand  = (eff_pow and eff_rpm >= CONFIG.MIN_RPM) and calc_wheel_demand_ku(eff_rpm) or 0
    local used    = (supply > 0) and math.max(0, supply - avail) or 0

    local orient_str = (axis.y ~= 0) and "Laying Flat (Vertical Y Axle)" or "Standing Upright (Horiz Axle)"
    local pair_str   = "Unpaired (Place 2nd Wheel Next to Rim)"
    local feed_str   = (axis.y ~= 0) and "Single Inward Angle (Horiz)" or "Drop from TOP (+Y) / Belt"
    local item_str   = ""
    local prog_pct   = 0
    local state_str  = "IDLE (Connect Energy Port to Axle)"
    local speed_mult = 0.0

    if pair then
        local mmeta = pair.is_master and meta or core.get_meta(pair.partner_pos)
        item_str    = mmeta:get_string("crushing_item")
        prog_pct    = mmeta:get_int("crush_pct")
        pair_str    = (pair.dist == 2) and "Paired (Touching Over Middle Gap/Belt)" or "Paired (Touching Directly)"
        feed_str    = dir_to_compass(pair.feed_dir)

        if pair.pair_ready then
            speed_mult = calc_crush_speed_multiplier(pair.pair_rpm)
            state_str  = (item_str ~= "") and ("CRUSHING (" .. item_str .. ")") or "PAIRED & SPINNING INWARD"
        elseif eff_pow and eff_rpm >= CONFIG.MIN_RPM then
            state_str = "SPINNING (Power Partner Wheel Axle!)"
        elseif eff_pow and eff_rpm > 0 then
            state_str = string.format("TOO SLOW (Min %d RPM)", CONFIG.MIN_RPM)
        else
            state_str = "PAIRED (Connect Energy Port to Axle)"
        end
    elseif eff_pow then
        if eff_rpm < CONFIG.MIN_RPM then
            state_str = string.format("TOO SLOW (Min %d RPM)", CONFIG.MIN_RPM)
        else
            state_str = "SPINNING SOLO (Place 2nd Wheel to Crush!)"
        end
    end

    return table.concat({
        LINE_TOP,
        "│  Mechanical Crushing Wheel",
        "│  ● STATE    : " .. state_str,
        LINE_NET,
        kv_row("Speed",       string.format("%.1f RPM  (%.2fx Crush Speed)", eff_pow and eff_rpm or 0, speed_mult)),
        kv_row("Wheel Load",  string.format("-%d KU", demand)),
        kv_row("Net Pool",    string.format("%d / %d KU Avail", eff_pow and avail or 0, supply)),
        kv_row("Net Stress",  make_bar(eff_pow and used or 0, supply)),
        LINE_DET,
        kv_row("Orientation", orient_str),
        kv_row("Wheel Pair",  pair_str),
        kv_row("Inward Feed", feed_str),
        kv_row("Max Batch",   string.format("%d Items / Stack", CONFIG.MAX_BATCH_SIZE)),
        kv_row("Crushing",    (item_str ~= "") and item_str or "Waiting for Items"),
        kv_row("Progress",    make_bar(prog_pct, 100)),
        LINE_BOT,
    }, "\n")
end

kinetica._glasses_formatters[IDLE_NAME]   = format_crushing_wheel_glasses_info
kinetica._glasses_formatters[ACTIVE_NAME] = format_crushing_wheel_glasses_info

local function spawn_crush_xp_orbs(seam_pos, feed_dir, total_xp)
    if not CONFIG.SPAWN_CRUSH_XP_ORBS or not total_xp or total_xp <= 0 then return end
    local xp_pos = {
        x = seam_pos.x + feed_dir.x * 0.35,
        y = (feed_dir.y < 0) and (seam_pos.y - 0.25) or (seam_pos.y + 0.20),
        z = seam_pos.z + feed_dir.z * 0.35,
    }
    if mcl_experience and mcl_experience.throw_xp then
        mcl_experience.throw_xp(xp_pos, total_xp)
    elseif core.registered_entities["mcl_experience:orb"] then
        local orb = core.add_entity(xp_pos, "mcl_experience:orb")
        if orb and orb:get_luaentity() then
            orb:get_luaentity()._xp = total_xp
        end
    end
end

local function try_insert_into_container_or_depot(target_pos, stack)
    if not stack or stack:is_empty() then return stack end
    local tnode = core.get_node(target_pos)
    local tname = tnode.name

    local tmeta = core.get_meta(target_pos)
    local tinv  = tmeta and tmeta:get_inventory()
    if not tinv then return stack end

    local is_depot = (tname == "kinetica:depot" or
                      core.get_item_group(tname, "kinetica_depot") > 0 or
                      string.find(tname, "depot") ~= nil)

    local candidate_lists = is_depot
        and {"output", "main"}
        or  {"main", "input", "dst"}

    for _, listname in ipairs(candidate_lists) do
        if tinv:get_size(listname) > 0 and tinv:room_for_item(listname, stack) then
            local leftover = tinv:add_item(listname, stack)
            local timer    = core.get_node_timer(target_pos)
            if timer and not timer:is_started() and
               (is_depot or (kinetica.is_chute and kinetica.is_chute(tname)) or string.find(tname, "chute")) then
                timer:start(0.20)
            end
            return leftover
        end
    end

    return stack
end

local function compute_safe_eject_pos(seam_pos, feed_dir)
    if feed_dir.y < 0 then
        local below_pos  = vector.round({x = seam_pos.x, y = seam_pos.y - 1, z = seam_pos.z})
        local below_node = core.get_node(below_pos)
        local below_def  = core.registered_nodes[below_node.name]
        local is_belt_below = (kinetica.is_belt and kinetica.is_belt(below_node.name)) or string.find(below_node.name, "belt")

        if below_node.name == "air" or (below_def and not below_def.walkable) then
            return {x = seam_pos.x, y = seam_pos.y - 0.52, z = seam_pos.z}
        elseif is_belt_below then
            return {x = seam_pos.x, y = below_pos.y + 0.30, z = seam_pos.z}
        else
            -- Solid floor directly under the wheels: spawn above the floor surface so items never bury
            return {x = seam_pos.x, y = seam_pos.y - 0.20, z = seam_pos.z}
        end
    else
        return {
            x = seam_pos.x + feed_dir.x * 0.48,
            y = seam_pos.y + 0.25,
            z = seam_pos.z + feed_dir.z * 0.48,
        }
    end
end

local function eject_crushed_outputs(master_pos, partner_pos, seam_pos, feed_dir, outputs, total_xp)
    local pair_hash = core.hash_node_position(master_pos)
    local check_containers = {
        vector.round(seam_pos),
        vector.round({x = seam_pos.x + feed_dir.x, y = seam_pos.y + feed_dir.y, z = seam_pos.z + feed_dir.z}),
        vector.round({x = seam_pos.x, y = seam_pos.y - 1, z = seam_pos.z}),
        {x = master_pos.x,  y = master_pos.y - 1,  z = master_pos.z},
        {x = partner_pos.x, y = partner_pos.y - 1, z = partner_pos.z},
    }

    local spawn_p = compute_safe_eject_pos(seam_pos, feed_dir)

    for _, out_str in ipairs(outputs) do
        local resolved_str = resolve_valid_itemstring(out_str)
        local stack        = ItemStack(resolved_str)
        if not stack:is_empty() then
            for _, cpos in ipairs(check_containers) do
                stack = try_insert_into_container_or_depot(cpos, stack)
                if stack:is_empty() then break end
            end

            if not stack:is_empty() then
                local obj = core.add_item(spawn_p, stack)
                if obj then
                    local ent = obj:get_luaentity()
                    if ent then
                        ent._kinetica_vacuumed        = false
                        ent._kinetica_crushed_by_pair = pair_hash
                        ent._kinetica_crush_cd        = (core.get_us_time() / 1e6) + 2.50
                    end
                    obj:set_acceleration({x = 0, y = -9.81, z = 0})
                    obj:set_velocity({
                        x = feed_dir.x * 1.4,
                        y = (feed_dir.y < 0) and -1.0 or 0.10,
                        z = feed_dir.z * 1.4,
                    })
                end
            end
        end
    end

    if total_xp and total_xp > 0 then
        spawn_crush_xp_orbs(seam_pos, feed_dir, total_xp)
    end
end

local function is_in_intake_zone(ipos, master_pos, partner_pos, seam_pos, axis, feed_dir)
    if axis.y ~= 0 then
        if math.abs(ipos.y - seam_pos.y) > 1.10 then
            return false
        end
        local rel_x = ipos.x - seam_pos.x
        local rel_z = ipos.z - seam_pos.z
        if hypot2(rel_x, rel_z) > 1.55 then
            return false
        end
        local along = rel_x * feed_dir.x + rel_z * feed_dir.z
        return (along <= 0.65)
    else
        if ipos.y < seam_pos.y - 0.95 or ipos.y > seam_pos.y + 2.10 then
            return false
        end
        local d1 = hypot2(ipos.x - master_pos.x,  ipos.z - master_pos.z)
        local d2 = hypot2(ipos.x - partner_pos.x, ipos.z - partner_pos.z)
        local ds = hypot2(ipos.x - seam_pos.x,    ipos.z - seam_pos.z)
        return (d1 <= 1.45 or d2 <= 1.45 or ds <= 1.45)
    end
end

local function pull_from_intake_inventories(seam_pos, master_pos, partner_pos, dist)
    local candidates = {}
    if dist == 2 then
        candidates[#candidates + 1] = vector.round(seam_pos)
    end
    candidates[#candidates + 1] = vector.round({x = seam_pos.x, y = seam_pos.y + 1, z = seam_pos.z})
    candidates[#candidates + 1] = {x = master_pos.x,  y = master_pos.y + 1,  z = master_pos.z}
    candidates[#candidates + 1] = {x = partner_pos.x, y = partner_pos.y + 1, z = partner_pos.z}

    for _, cpos in ipairs(candidates) do
        local cnode = core.get_node(cpos)
        local cname = cnode.name
        local is_depot  = (cname == "kinetica:depot" or core.get_item_group(cname, "kinetica_depot") > 0 or string.find(cname, "depot"))
        local is_feeder = is_depot or (kinetica.is_chute and kinetica.is_chute(cname)) or string.find(cname, "chute") or string.find(cname, "hopper")

        if is_feeder then
            local cinv = core.get_meta(cpos):get_inventory()
            if cinv then
                for _, lname in ipairs({"input", "main"}) do
                    local sz = cinv:get_size(lname)
                    for slot = 1, sz do
                        local st = cinv:get_stack(lname, slot)
                        if not st:is_empty() and get_crushing_recipe_for_item(st:get_name(), st) then
                            local spawned = core.add_item({x = seam_pos.x, y = seam_pos.y + 0.30, z = seam_pos.z}, st)
                            if spawned then
                                cinv:set_stack(lname, slot, ItemStack(""))
                                local dt = core.get_node_timer(cpos)
                                if dt and not dt:is_started() then dt:start(0.20) end
                                return
                            end
                        end
                    end
                end
            end
        end
    end
end

local function process_pair_crushing(master_pos, meta, axis, pair)
    local seam_pos    = pair.seam_pos
    local partner_pos = pair.partner_pos
    local feed_dir    = pair.feed_dir
    local eff_rpm     = pair.pair_rpm
    local now_sec     = core.get_us_time() / 1e6
    local pair_hash   = core.hash_node_position(master_pos)

    if CONFIG.DEAL_CRUSH_DAMAGE then
        local dmg_tick = (meta:get_int("dmg_tick") + 1) % 8
        meta:set_int("dmg_tick", dmg_tick)
        if dmg_tick == 0 then
            local rpm_ratio = math.min(1.0, math.max(0.0, (eff_rpm - CONFIG.MIN_RPM) / (256 - CONFIG.MIN_RPM)))
            local scaled_hp = math.floor(CONFIG.CRUSH_DAMAGE_BASE_HP + rpm_ratio * (CONFIG.CRUSH_DAMAGE_MAX_HP - CONFIG.CRUSH_DAMAGE_BASE_HP))
            for _, obj in ipairs(core.get_objects_inside_radius(seam_pos, 0.95)) do
                local luaent = obj:get_luaentity()
                if obj:is_player() or (luaent and (luaent.is_mob or luaent._cmi_is_mob or luaent.health)) then
                    obj:punch(obj, 1.0, {
                        full_punch_interval = 1.0,
                        damage_groups       = {fleshy = scaled_hp},
                    }, nil)
                end
            end
        end
    end

    pull_from_intake_inventories(seam_pos, master_pos, partner_pos, pair.dist)

    local target_obj    = nil
    local target_ent    = nil
    local target_stack  = nil
    local target_recipe = nil
    local intake_items  = {}

    for _, obj in ipairs(core.get_objects_inside_radius(seam_pos, 2.60)) do
        local ent  = obj:get_luaentity()
        local ipos = obj:get_pos()

        if ent and ent.name ~= ENTITY_NAME and ipos and
           is_in_intake_zone(ipos, master_pos, partner_pos, seam_pos, axis, feed_dir) then

            if ent.name == "__builtin:falling_node" and ent.node and ent.node.name then
                local fn_name = ent.node.name
                obj:remove()
                local spawned = core.add_item(ipos, ItemStack(fn_name .. " 1"))
                if spawned then
                    obj  = spawned
                    ent  = spawned:get_luaentity()
                    ipos = spawned:get_pos()
                end
            end

            local same_pair_cd = (ent and ent._kinetica_crushed_by_pair == pair_hash) and
                                 (ent._kinetica_crush_cd and now_sec < ent._kinetica_crush_cd)

            if ent and ent.name == "__builtin:item" and ent.itemstring and ent.itemstring ~= "" and not same_pair_cd then
                local st  = ItemStack(ent.itemstring)
                local rec = get_crushing_recipe_for_item(st:get_name(), st)

                local dx         = seam_pos.x - ipos.x
                local dz         = seam_pos.z - ipos.z
                local dist_horiz = hypot2(dx, dz)
                local hold_y     = seam_pos.y + 0.15

                -- Pull both crushable and non-crushable items toward the center seam
                ent._kinetica_vacuumed = true
                obj:set_acceleration({x = 0, y = 0, z = 0})
                obj:set_velocity({x = 0, y = 0, z = 0})

                if dist_horiz > 0.22 then
                    local step = math.min(dist_horiz, CONFIG.DRAG_PULL_SPEED * CONFIG.TIMER_INTERVAL)
                    local nx   = ipos.x + (dx / dist_horiz) * step
                    local nz   = ipos.z + (dz / dist_horiz) * step
                    local ny   = math.max(hold_y, ipos.y - 0.10)
                    obj:set_pos({x = nx, y = ny, z = nz})
                else
                    obj:set_pos({
                        x = seam_pos.x,
                        y = hold_y,
                        z = seam_pos.z,
                    })
                end

                if rec then
                    intake_items[#intake_items + 1] = {
                        obj  = obj,
                        ent  = ent,
                        st   = st,
                        rec  = rec,
                        dist = dist_horiz,
                    }

                    local cur_prog  = ent._kinetica_crush_prog or 0
                    local best_prog = target_ent and (target_ent._kinetica_crush_prog or 0) or -1
                    if not target_obj or cur_prog > best_prog or
                       (cur_prog == best_prog and dist_horiz < (target_ent._last_dist or 99)) then
                        target_obj            = obj
                        target_ent            = ent
                        target_ent._last_dist = dist_horiz
                        target_stack          = st
                        target_recipe         = rec
                    end
                elseif dist_horiz <= 0.25 then
                    -- Non-crushable item reached the seam: pass it cleanly through the wheels
                    ent._kinetica_vacuumed = false
                    obj:set_acceleration({x = 0, y = -9.81, z = 0})
                    local leftover  = st
                    local below_pos = vector.round({x = seam_pos.x + feed_dir.x, y = seam_pos.y + feed_dir.y, z = seam_pos.z + feed_dir.z})
                    leftover = try_insert_into_container_or_depot(below_pos, leftover)
                    if leftover:is_empty() then
                        obj:remove()
                    else
                        ent:set_item(leftover:to_string())
                        ent._kinetica_crushed_by_pair = pair_hash
                        ent._kinetica_crush_cd        = now_sec + 1.80
                        obj:set_pos(compute_safe_eject_pos(seam_pos, feed_dir))
                    end
                end
            end
        end
    end

    if not target_obj or not target_stack or not target_recipe then
        PAIR_CRUSH_STATE[pair_hash] = nil
        meta:set_string("crushing_item", "")
        meta:set_int("crush_pct", 0)
        return
    end

    if CONFIG.AUTO_MERGE_INTAKE_STACKS and target_stack:get_wear() == 0 then
        local tname = target_stack:get_name()
        local cur_c = target_stack:get_count()
        local max_c = math.min(CONFIG.MAX_BATCH_SIZE, target_stack:get_stack_max())

        if cur_c < max_c and #intake_items > 1 then
            local changed = false
            for _, entry in ipairs(intake_items) do
                if entry.obj ~= target_obj and entry.st:get_name() == tname and entry.st:get_wear() == 0 then
                    local room = max_c - cur_c
                    if room <= 0 then break end
                    local other_c = entry.st:get_count()
                    local take    = math.min(room, other_c)
                    cur_c         = cur_c + take
                    changed       = true
                    if take >= other_c then
                        entry.obj:remove()
                    else
                        entry.st:set_count(other_c - take)
                        entry.ent:set_item(entry.st:to_string())
                    end
                end
            end
            if changed then
                target_stack:set_count(cur_c)
                target_ent:set_item(target_stack:to_string())
            end
        end
    end

    local total_count = target_stack:get_count()
    local batch_count = math.min(CONFIG.MAX_BATCH_SIZE, total_count)
    local item_name   = target_stack:get_name()
    local idef        = core.registered_items[item_name]
    local clean_desc  = (idef and idef.description) and string.match(idef.description, "^[^\n%(]+") or item_name
    meta:set_string("crushing_item", string.format("%s x%d", clean_desc, batch_count))

    local speed_mult = calc_crush_speed_multiplier(eff_rpm)
    local stack_mult = 1.0 + CONFIG.STACK_TIME_LOG_FACTOR * math.log(math.max(1, batch_count))
    local total_need = math.max(0.10, (target_recipe.time * stack_mult) / speed_mult)

    local pstate = PAIR_CRUSH_STATE[pair_hash]
    if not pstate or pstate.item_name ~= item_name then
        pstate = {
            item_name = item_name,
            prog      = target_ent._kinetica_crush_prog or 0,
        }
        PAIR_CRUSH_STATE[pair_hash] = pstate
    end

    local new_prog = math.max(pstate.prog, target_ent._kinetica_crush_prog or 0) + CONFIG.TIMER_INTERVAL
    pstate.prog                    = new_prog
    target_ent._kinetica_crush_prog = new_prog

    local pct = math.min(100, math.floor((new_prog / total_need) * 100))
    meta:set_int("crush_pct", pct)

    local part_tex = resolve_item_particle_texture(item_name)
    core.add_particlespawner({
        amount     = 5,
        time       = CONFIG.TIMER_INTERVAL,
        minpos     = {x = seam_pos.x - 0.24, y = seam_pos.y - 0.10, z = seam_pos.z - 0.24},
        maxpos     = {x = seam_pos.x + 0.24, y = seam_pos.y + 0.24, z = seam_pos.z + 0.24},
        minvel     = {x = -0.5, y = -0.3, z = -0.5},
        maxvel     = {x =  0.5, y =  0.6, z =  0.5},
        minexptime = 0.20,
        maxexptime = 0.45,
        minsize    = 1.1,
        maxsize    = 2.4,
        texture    = part_tex,
    })

    if new_prog >= total_need then
        local out_base  = ItemStack(resolve_valid_itemstring(target_recipe.output))
        local out_name  = out_base:get_name()
        local out_per_1 = math.max(1, out_base:get_count())
        local total_pri = out_per_1 * batch_count

        local outputs_to_eject = {}
        while total_pri > 0 do
            local b = math.min(64, total_pri)
            outputs_to_eject[#outputs_to_eject + 1] = out_name .. " " .. b
            total_pri = total_pri - b
        end

        for _, bonus in ipairs(target_recipe.extra or {}) do
            local b_stack = ItemStack(resolve_valid_itemstring(bonus.item))
            local b_name  = b_stack:get_name()
            local b_per_1 = math.max(1, b_stack:get_count())
            local b_total = 0
            for _ = 1, batch_count do
                if math.random() <= (bonus.chance or 0.25) then
                    b_total = b_total + b_per_1
                end
            end
            while b_total > 0 do
                local b = math.min(64, b_total)
                outputs_to_eject[#outputs_to_eject + 1] = b_name .. " " .. b
                b_total = b_total - b
            end
        end

        local total_xp = 0
        if target_recipe.xp and target_recipe.xp > 0 then
            for _ = 1, batch_count do
                if math.random() <= CONFIG.XP_ORB_CHANCE_PER_ITEM then
                    total_xp = total_xp + target_recipe.xp
                end
            end
        end

        PAIR_CRUSH_STATE[pair_hash] = nil

        if total_count > batch_count then
            target_stack:set_count(total_count - batch_count)
            target_ent:set_item(target_stack:to_string())
            target_ent._kinetica_crush_prog = 0
        else
            target_obj:remove()
        end

        meta:set_string("crushing_item", "")
        meta:set_int("crush_pct", 0)
        eject_crushed_outputs(master_pos, partner_pos, seam_pos, feed_dir, outputs_to_eject, total_xp)
    end
end

local function wheel_timer(pos, elapsed)
    local node = core.get_node(pos)
    if not kinetica.is_crushing_wheel(node.name) then
        remove_wheel_entity(pos)
        return false
    end

    local meta    = core.get_meta(pos)
    local axis    = kinetica.get_crushing_wheel_axis(node.param2)
    local norm_p2 = normalize_wheel_param2(axis)

    if node.name ~= ACTIVE_NAME or node.param2 ~= norm_p2 then
        core.swap_node(pos, {name = ACTIVE_NAME, param2 = norm_p2})
        node = core.get_node(pos)
    end

    local my_pow, my_rpm, my_sup, my_ava, my_spin = read_wheel_direct_power(pos, axis, meta)
    local pair = find_paired_wheel(pos, axis, my_pow, my_rpm, my_sup, my_ava, my_spin)

    local eff_pow    = pair and pair.eff_pow or my_pow
    local eff_rpm    = pair and pair.eff_rpm or (my_pow and my_rpm or 0)
    local vis_spin   = pair and pair.inward_vis_spin or (my_spin ~= 0 and my_spin or CONFIG.SOLO_SPIN_DIR)
    local pair_dist  = pair and pair.dist or 2
    local scale_mult = (pair_dist == 1) and CONFIG.WHEEL_SCALE_ADJACENT or CONFIG.WHEEL_SCALE_BELT_GAP

    local is_active = eff_pow and (eff_rpm >= CONFIG.MIN_RPM)
    local demand_ku = is_active and calc_wheel_demand_ku(eff_rpm) or 0
    meta:set_int("machine_demand_ku", demand_ku)

    if CONFIG.ENABLE_WHEEL_SOUND then
        if is_active then
            local sound_timer = meta:get_float("wheel_sound_timer") + CONFIG.TIMER_INTERVAL
            if sound_timer >= CONFIG.SOUND_WHEEL_INTERVAL_SEC then
                core.sound_play(CONFIG.SOUND_WHEEL_CUSTOM, {
                    pos = pos,
                    max_hear_distance = CONFIG.SOUND_WHEEL_MAX_DISTANCE,
                    gain = CONFIG.SOUND_WHEEL_GAIN
                }, true)
                sound_timer = 0
            end
            meta:set_float("wheel_sound_timer", sound_timer)
        else
            
            meta:set_float("wheel_sound_timer", CONFIG.SOUND_WHEEL_INTERVAL_SEC)
        end
    end


    local speed_rad = 0
    if is_active then
        speed_rad = calc_spin_rad_per_sec(eff_rpm) * vis_spin
        if CONFIG.INVERT_VISUAL_SPIN then
            speed_rad = -speed_rad
        end
    end

    sync_crushing_wheel_entity(pos, axis, speed_rad, scale_mult)

    if is_active then
        if pair and pair.pair_ready and pair.is_master then
            process_pair_crushing(pos, meta, axis, pair)
        else
            meta:set_string("crushing_item", "")
            meta:set_int("crush_pct", 0)
        end
    else
        meta:set_string("crushing_item", "")
        meta:set_int("crush_pct", 0)
    end

    meta:set_string("glasses_info", format_crushing_wheel_glasses_info(pos, node))
    return true
end

local function determine_wheel_param2(pos, placer, pointed_thing)
    if pointed_thing and pointed_thing.under then
        local unode = core.get_node(pointed_thing.under)
        local uname = unode.name
        if kinetica.is_crushing_wheel(uname) then
            return normalize_wheel_param2(kinetica.get_crushing_wheel_axis(unode.param2))
        elseif kinetica.is_shaft and kinetica.is_shaft(uname) and kinetica.abs_axis then
            return normalize_wheel_param2(kinetica.abs_axis(unode.param2))
        end
    end

    local check_offsets = {
        {x =  1, y = 0, z =  0}, {x = -1, y = 0, z =  0},
        {x =  0, y = 0, z =  1}, {x =  0, y = 0, z = -1},
        {x =  2, y = 0, z =  0}, {x = -2, y = 0, z =  0},
        {x =  0, y = 0, z =  2}, {x =  0, y = 0, z = -2},
    }
    for _, off in ipairs(check_offsets) do
        local nnode = core.get_node({x = pos.x + off.x, y = pos.y + off.y, z = pos.z + off.z})
        if kinetica.is_crushing_wheel(nnode.name) then
            return normalize_wheel_param2(kinetica.get_crushing_wheel_axis(nnode.param2))
        end
    end

    if placer and placer:is_player() then
        local look = placer:get_look_dir()
        if look and math.abs(look.y) > 0.72 then
            return 4
        elseif look and math.abs(look.x) > math.abs(look.z) then
            return 1
        end
    end

    return 0
end

local function on_wheel_rightclick(pos, node, clicker, itemstack, pointed_thing)
    if not clicker or not clicker:is_player() or not itemstack or itemstack:is_empty() then
        return itemstack
    end
    local iname = itemstack:get_name()
    if is_valid_middle_space(iname) or kinetica.is_crushing_wheel(iname) or
       (kinetica.is_shaft and kinetica.is_shaft(iname)) then
        return core.item_place_node(itemstack, clicker, pointed_thing)
    end

    if get_crushing_recipe_for_item(iname, itemstack) then
        local take_cnt = math.min(itemstack:get_count(), CONFIG.MAX_BATCH_SIZE)
        local drop_st  = ItemStack(itemstack:to_string())
        drop_st:set_count(take_cnt)
        itemstack:take_item(take_cnt)

        local meta = core.get_meta(pos)
        local axis = kinetica.get_crushing_wheel_axis(node.param2)
        local my_pow, my_rpm, my_sup, my_ava, my_spin = read_wheel_direct_power(pos, axis, meta)
        local pair = find_paired_wheel(pos, axis, my_pow, my_rpm, my_sup, my_ava, my_spin)
        local spawn_pos = pair and {x = pair.seam_pos.x, y = pair.seam_pos.y + 0.25, z = pair.seam_pos.z}
                               or  {x = pos.x,           y = pos.y + 0.65,           z = pos.z}

        core.add_item(spawn_pos, drop_st)
        return itemstack
    end

    return itemstack
end

local function wake_nearby_wheels(pos)
    for dx = -2, 2 do
        for dy = -2, 2 do
            for dz = -2, 2 do
                local npos = {x = pos.x + dx, y = pos.y + dy, z = pos.z + dz}
                if kinetica.is_crushing_wheel(core.get_node(npos).name) then
                    local t = core.get_node_timer(npos)
                    t:start(CONFIG.TIMER_INTERVAL)
                end
            end
        end
    end
end

core.register_node(IDLE_NAME, {
    description = "Mechanical Crushing Wheel\n" ..
                  "Place 2 wheels side-by-side (or straddling a Belt) to crush up to 64 items at once.\n" ..
                  "• Crushes Ores, Raw Ores & Storage Blocks into bonus yields + Experience Orbs!\n" ..
                  "• Upright: Drop items on top of either wheel — they drag to the center & crush!\n" ..
                  "• Flat (look down to place): Feed from the single inward-spinning angle.",
    drawtype              = "nodebox",
    paramtype             = "light",
    paramtype2            = "facedir",
    sunlight_propagates   = true,
    tiles = {
        STONE_TEX,
        STONE_TEX,
        HUB_AXLE_TEX,
        HUB_AXLE_TEX,
        GROOVE_TEX,
        GROOVE_TEX,
    },
    node_box = {
        type  = "fixed",
        fixed = WHEEL_BOXES_UPRIGHT,
    },
    selection_box         = WHEEL_SELECTION_BOX,
    collision_box         = HUB_COLLISION_BOX,
    groups                = {pickaxey = 2, kinetic_receiver = 1, kinetica_crushing_wheel = 1},
    _mcl_hardness         = 3.5,
    _mcl_blast_resistance = 4.0,
    sounds                = mcl_sounds.node_sound_stone_defaults(),

    on_place = function(itemstack, placer, pointed_thing)
        if not pointed_thing or pointed_thing.type ~= "node" then
            return itemstack
        end
        local p2 = determine_wheel_param2(pointed_thing.above, placer, pointed_thing)
        return core.item_place(itemstack, placer, pointed_thing, p2)
    end,

    on_construct = function(pos)
        local meta = core.get_meta(pos)
        meta:set_int("machine_demand_ku", 0)
        meta:set_int("crush_pct", 0)
        meta:set_string("crushing_item", "")
        local node = core.get_node(pos)
        local axis = kinetica.get_crushing_wheel_axis(node.param2)
        local p2   = normalize_wheel_param2(axis)
        core.swap_node(pos, {name = ACTIVE_NAME, param2 = p2})
        sync_crushing_wheel_entity(pos, axis, 0, CONFIG.WHEEL_SCALE_BELT_GAP)
        core.get_node_timer(pos):start(CONFIG.TIMER_INTERVAL)
        wake_nearby_wheels(pos)
        if kinetica.schedule_network_update then
            kinetica.schedule_network_update(pos)
        end
    end,

    on_destruct = function(pos)
        remove_wheel_entity(pos)
        PAIR_CRUSH_STATE[core.hash_node_position(pos)] = nil
    end,

    after_dig_node = function(pos)
        remove_wheel_entity(pos)
        wake_nearby_wheels(pos)
        if kinetica.schedule_network_update then
            kinetica.schedule_network_update(pos)
        end
    end,

    on_rightclick = on_wheel_rightclick,
    on_timer      = wheel_timer,
})

core.register_node(ACTIVE_NAME, {
    description           = "Mechanical Crushing Wheel",
    drawtype              = "airlike",
    paramtype             = "light",
    paramtype2            = "facedir",
    sunlight_propagates   = true,
    walkable              = true,
    selection_box         = WHEEL_SELECTION_BOX,
    collision_box         = HUB_COLLISION_BOX,
    drop                  = IDLE_NAME,
    groups                = {pickaxey = 2, kinetic_receiver = 1, kinetica_crushing_wheel = 1, not_in_creative_inventory = 1},
    _mcl_hardness         = 3.5,
    _mcl_blast_resistance = 4.0,
    sounds                = mcl_sounds.node_sound_stone_defaults(),

    on_destruct = function(pos)
        remove_wheel_entity(pos)
        PAIR_CRUSH_STATE[core.hash_node_position(pos)] = nil
    end,

    after_dig_node = function(pos)
        remove_wheel_entity(pos)
        wake_nearby_wheels(pos)
        if kinetica.schedule_network_update then
            kinetica.schedule_network_update(pos)
        end
    end,

    on_rightclick = on_wheel_rightclick,
    on_timer      = wheel_timer,
})

core.register_alias("kinetica:crushing_wheel_mesh", MESH_UPRIGHT_NAME)
for _, tier in ipairs({"crawl", "slow", "medium", "fast", "hyper"}) do
    core.register_alias(IDLE_NAME .. "_active_cw_"  .. tier,           ACTIVE_NAME)
    core.register_alias(IDLE_NAME .. "_active_ccw_" .. tier,           ACTIVE_NAME)
    core.register_alias(IDLE_NAME .. "_active_cw_"  .. tier .. "_gap", ACTIVE_NAME)
    core.register_alias(IDLE_NAME .. "_active_ccw_" .. tier .. "_gap", ACTIVE_NAME)
end
core.register_alias(IDLE_NAME .. "_gap", ACTIVE_NAME)

if kinetica.register_kinetic_machine then
    local machine_def = {
        can_ride_piston = false,
        min_rpm         = CONFIG.MIN_RPM,
        has_axle_port   = function(node, d)
            local axis = kinetica.get_crushing_wheel_axis(node.param2)
            return (math.abs(d.x) == axis.x) and
                   (math.abs(d.y) == axis.y) and
                   (math.abs(d.z) == axis.z)
        end,
        get_demand_ku   = function(rpm, pos, node)
            return calc_wheel_demand_ku(rpm)
        end,
        set_idle        = function(pos, node, reason_text)
            local axis = kinetica.get_crushing_wheel_axis(node.param2)
            sync_crushing_wheel_entity(pos, axis, 0, CONFIG.WHEEL_SCALE_BELT_GAP)
            local meta = core.get_meta(pos)
            meta:set_float("rpm", 0)
            meta:set_int("network_supply_ku", 0)
            meta:set_int("rotational_power", 0)
            meta:set_string("crushing_item", "")
            meta:set_int("crush_pct", 0)
            meta:set_string("glasses_info", format_crushing_wheel_glasses_info(pos, node))
            wake_nearby_wheels(pos)
        end,
        wake            = function(pos, node, rpm, spin_dir, demand_ku, avail_ku, supply_ku)
            local meta = core.get_meta(pos)
            if rpm and rpm > 0 then
                meta:set_float("rpm", rpm)
                meta:set_int("spin_dir", spin_dir or 1)
                meta:set_int("rotational_power", avail_ku or supply_ku or 0)
                meta:set_int("network_supply_ku", supply_ku or avail_ku or 0)
                meta:set_int("lit_until", math.floor(core.get_gametime()) + 5)
            end
            local timer = core.get_node_timer(pos)
            if not timer:is_started() then
                timer:start(CONFIG.TIMER_INTERVAL)
            end
            wake_nearby_wheels(pos)
        end,
    }
    -- Register BOTH the idle and active swapped node names with the kinetic network
    kinetica.register_kinetic_machine(IDLE_NAME, machine_def)
    kinetica.register_kinetic_machine(ACTIVE_NAME, machine_def)
end

core.register_lbm({
    label             = "Wake kinetica Crushing Wheels & sync 3D rotor on chunk load",
    name              = "kinetica:wake_crushing_wheels_lbm",
    nodenames         = {"group:kinetica_crushing_wheel"},
    run_at_every_load = true,
    action = function(pos, node)
        local axis = kinetica.get_crushing_wheel_axis(node.param2)
        sync_crushing_wheel_entity(pos, axis, 0, CONFIG.WHEEL_SCALE_BELT_GAP)
        local timer = core.get_node_timer(pos)
        timer:start(CONFIG.TIMER_INTERVAL)
    end,
})

core.register_craft({
    output = "kinetica:crushing_wheel 2",
    recipe = {
        {"kinetica:andesite_alloy", "mcl_core:stone", "kinetica:andesite_alloy"},
        {"mcl_core:stone",          "kinetica:shaft", "mcl_core:stone"},
        {"kinetica:andesite_alloy", "mcl_core:stone", "kinetica:andesite_alloy"},
    },
})