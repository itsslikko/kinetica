-- kinetica/recipes.lua
local modname = core.get_current_modname() or "kinetica"

-- Ensure API is loaded
if not kinetica.api or not kinetica.api.recipes then
    core.log("error", "[Kinetica] Cannot load recipes: API not found!")
    return
end

-- ============================================================================
-- 1. CRUSHING WHEEL RECIPES
-- ============================================================================

local crushing_recipes = {
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

    -- Overworld & Deepslate Ores
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

for iname, rdef in pairs(crushing_recipes) do
    kinetica.api.recipes.register_crushing(iname, rdef)
end

-- ============================================================================
-- 2. PRESSING & COMPACTING RECIPES
-- ============================================================================

local pressing_recipes = {
    -- 1-to-1 Sheet & Block Pressing
    ["mcl_core:iron_ingot"]          = {output = "kinetica:sheet_iron 1",          input_count = 1, time = 1.0},
    ["mcl_core:gold_ingot"]          = {output = "kinetica:sheet_gold 1",          input_count = 1, time = 1.0},
    ["mcl_copper:copper_ingot"]      = {output = "kinetica:sheet_copper 1",        input_count = 1, time = 1.0},
    ["mcl_core:reeds"]               = {output = "mcl_core:paper 1",               input_count = 1, time = 0.8},
    ["mcl_core:dirt_with_grass"]     = {output = "mcl_core:grass_path 1",          input_count = 1, time = 0.8},
    ["mcl_core:dirt"]                = {output = "mcl_core:coarse_dirt 1",         input_count = 1, time = 0.8},

    -- 2x2 & 3x3 Automatic Mechanical Compacting
    ["mcl_core:iron_nugget"]         = {output = "mcl_core:iron_ingot 1",          input_count = 9, time = 1.2},
    ["mcl_core:gold_nugget"]         = {output = "mcl_core:gold_ingot 1",          input_count = 9, time = 1.2},
    ["mcl_core:diamond"]             = {output = "mcl_core:diamondblock 1",        input_count = 9, time = 1.4},
    ["mcl_core:emerald"]             = {output = "mcl_core:emeraldblock 1",        input_count = 9, time = 1.4},
    ["mcl_core:coal_lump"]           = {output = "mcl_core:coalblock 1",           input_count = 9, time = 1.2},
    ["mcl_core:lapis"]               = {output = "mcl_core:lapisblock 1",          input_count = 9, time = 1.2},
    ["mesecons:redstone"]            = {output = "mesecons_torch:redstoneblock 1", input_count = 9, time = 1.2},
    ["mcl_redstone:redstone"]        = {output = "mcl_redstone:redstone_block 1",  input_count = 9, time = 1.2},
    ["mcl_raw_ores:raw_iron"]        = {output = "mcl_raw_ores:raw_iron_block 1",  input_count = 9, time = 1.3},
    ["mcl_raw_ores:raw_gold"]        = {output = "mcl_raw_ores:raw_gold_block 1",  input_count = 9, time = 1.3},
    ["mcl_copper:raw_copper"]        = {output = "mcl_copper:block_raw 1",         input_count = 9, time = 1.3},
    ["mcl_bone_meal:bone_meal"]      = {output = "mcl_bone_meal:bone_block 1",     input_count = 9, time = 1.1},
    ["mcl_ocean:dried_kelp"]         = {output = "mcl_ocean:dried_kelp_block 1",   input_count = 9, time = 1.1},
    ["mcl_farming:wheat_item"]       = {output = "mcl_farming:hay_block 1",        input_count = 9, time = 1.1},
    ["mcl_mobitems:slimeball"]       = {output = "mcl_core:slimeblock 1",          input_count = 9, time = 1.1},
    ["mcl_farming:melon_item"]       = {output = "mcl_farming:melon 1",            input_count = 9, time = 1.1},
    ["mcl_core:clay_lump"]           = {output = "mcl_core:clay 1",                input_count = 4, time = 1.0},
    ["mcl_core:brick"]               = {output = "mcl_core:brick_block 1",         input_count = 4, time = 1.0},
    ["mcl_nether:netherbrick"]       = {output = "mcl_nether:nether_brick 1",      input_count = 4, time = 1.0},
    ["mcl_nether:quartz"]            = {output = "mcl_nether:quartz_block 1",      input_count = 4, time = 1.0},
    ["mcl_nether:glowstone_dust"]    = {output = "mcl_nether:glowstone 1",         input_count = 4, time = 1.0},
    ["mcl_amethyst:amethyst_shard"]  = {output = "mcl_amethyst:amethyst_block 1",  input_count = 4, time = 1.0},
    ["mcl_throwing:snowball"]        = {output = "mcl_core:snowblock 1",           input_count = 4, time = 0.9},
    ["mcl_core:sand"]                = {output = "mcl_core:sandstone 1",           input_count = 4, time = 1.1},
    ["mcl_core:redsand"]             = {output = "mcl_core:redsandstone 1",        input_count = 4, time = 1.1},
}

for iname, rdef in pairs(pressing_recipes) do
    kinetica.api.recipes.register_pressing(iname, rdef)
end

-- ============================================================================
-- 3. FAN PROCESSING RECIPES
-- ============================================================================

local washing_recipes = {
    ["mcl_core:gravel"] = {
        {item = "mcl_core:flint",        chance = 0.25,  rolls = 1, count = 1},
        {item = "mcl_core:iron_nugget",  chance = 0.125, rolls = 1, count = 1},
    },
    ["mcl_core:sand"] = {
        {item = "mcl_core:clay_lump",    chance = 0.25,  rolls = 1, count = 1},
    },
    ["mcl_core:redsand"] = {
        {item = "mcl_core:gold_nugget",  chance = 0.125, rolls = 3, count = 1},
        {item = "mcl_core:deadbush",     chance = 0.05,  rolls = 1, count = 1},
    },
    ["mcl_nether:soul_sand"] = {
        {item = "mcl_nether:quartz",     chance = 0.125, rolls = 4, count = 1},
        {item = "mcl_core:gold_nugget",  chance = 0.02,  rolls = 1, count = 1},
    },
    ["mcl_raw_ores:raw_iron"] = {
        {item = "mcl_core:iron_nugget",  chance = 1.00,  rolls = 1, count = 9},
        {item = "mcl_redstone:redstone", chance = 0.75,  rolls = 1, count = 1},
    },
    ["mcl_raw_ores:raw_gold"] = {
        {item = "mcl_core:gold_nugget",  chance = 1.00,  rolls = 1, count = 9},
        {item = "mcl_nether:quartz",     chance = 0.50,  rolls = 1, count = 1},
    },
    ["mcl_copper:raw_copper"] = {
        {item = "mcl_copper:copper_ingot", chance = 1.00, rolls = 1, count = 1},
        {item = "mcl_core:clay_lump",      chance = 0.50, rolls = 1, count = 1},
    },
}

for iname, rdef in pairs(washing_recipes) do
    kinetica.api.recipes.register_fan_processing("washing", iname, rdef)
end

local haunting_recipes = {
    ["mcl_core:lapis"] = {
        {item = "mcl_ocean:prismarine_shard",    chance = 0.75,  rolls = 1, count = 1},
        {item = "mcl_ocean:prismarine_crystals", chance = 0.125, rolls = 1, count = 1},
    },
}

for iname, rdef in pairs(haunting_recipes) do
    kinetica.api.recipes.register_fan_processing("haunting", iname, rdef)
end