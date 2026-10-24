kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

local CONFIG = {
    ALLOY_CRAFT_YIELD            = 2,
    SHAFT_NUGGET_SLAB_YIELD      = 8,
    ENABLE_INWORLD_CASING_CLICK  = true,
    CONSUME_ITEM_ON_INWORLD_CLICK= true,
    SYNC_MOD_PROGRESSION_RECIPES = true,
    TEX_ANDESITE_ALLOY           = "kinetica_andesite_alloy.png",
    TEX_SHEET_IRON               = "kinetica_sheet_iron.png",
    TEX_SHEET_COPPER             = "kinetica_sheet_copper.png",
    TEX_SHEET_GOLD               = "kinetica_sheet_gold.png",
    TEX_ANDESITE_CASING_TOP      = "kinetica_andisite_casing.png",
    TEX_ANDESITE_CASING_SIDE     = "kinetica_andisite_casing.png",
    TEX_COPPER_CASING_TOP        = "kinetica_copper_casing.png",
    TEX_COPPER_CASING_SIDE       = "kinetica_copper_casing.png",
    TEX_GOLD_CASING_TOP          = "kinetica_gold_casing.png",
    TEX_GOLD_CASING_SIDE         = "kinetica_gold_casing.png",
    FALLBACK_CASING_TOP          = "kinetica_steam_maker_down.png",
    FALLBACK_CASING_SIDE         = "kinetica_chain_drive_side.png",
    ALLOY_TINT_HEX               = "#767d78",
    IRON_SHEET_TINT_HEX          = "#e2e6ea",
    COPPER_SHEET_TINT_HEX        = "#d46a38",
    GOLD_SHEET_TINT_HEX          = "#f2b624",
    COPPER_CASING_TINT           = "^[colorize:#c85a28:115",
    GOLD_CASING_TINT             = "^[colorize:#e5a418:125",
}

local ALLOY_NAME    = "kinetica:andesite_alloy"
local SHEET_IRON    = "kinetica:sheet_iron"
local SHEET_COPPER  = "kinetica:sheet_copper"
local SHEET_GOLD    = "kinetica:sheet_gold"
local CASING_ANDESITE = "kinetica:andesite_casing"
local CASING_COPPER   = "kinetica:copper_casing"
local CASING_GOLD     = "kinetica:gold_casing"

function kinetica.is_sheet(name)
    return name == SHEET_IRON or name == SHEET_COPPER or name == SHEET_GOLD
end

function kinetica.is_casing(name)
    return name == CASING_ANDESITE or name == CASING_COPPER or name == CASING_GOLD
end

local function file_exists(filename)
    if not filename or filename == "" then return false end
    local ok, f = pcall(io.open, modpath .. "/textures/" .. filename, "r")
    if ok and f then
        f:close()
        return true
    end
    return false
end

local function get_registered_item_tex(item_name, fallback)
    local def = core.registered_items[item_name]
    if def then
        if type(def.inventory_image) == "string" and def.inventory_image ~= "" then
            return def.inventory_image
        end
        if def.tiles and def.tiles[1] then
            local t = def.tiles[1]
            if type(t) == "string" and t ~= "" then
                return t
            elseif type(t) == "table" and type(t.name) == "string" then
                return t.name
            end
        end
    end
    return fallback
end

local function build_sheet_inventory_icon(custom_png, base_block_item, base_ingot_item, tint_hex)
    if file_exists(custom_png) then
        return custom_png
    end

    local block_tex = get_registered_item_tex(base_block_item, CONFIG.FALLBACK_CASING_TOP)
    local clean_blk = string.match(block_tex, "^[^%^]+") or CONFIG.FALLBACK_CASING_TOP

    local rim_plate   = "(" .. clean_blk .. "\\^[resize\\:14x14\\^[colorize\\:#1b1e24\\:165)"
    local inner_plate = "(" .. clean_blk .. "\\^[resize\\:12x12\\^[colorize\\:" .. tint_hex .. "\\:120)"
    local shine_bar   = "(" .. clean_blk .. "\\^[resize\\:10x2\\^[colorize\\:#ffffff\\:110)"
    local rivet_px    = "(" .. clean_blk .. "\\^[resize\\:1x1\\^[colorize\\:#22262e\\:200)"

    return "[combine:16x16" ..
        ":1,1="   .. rim_plate ..
        ":2,2="   .. inner_plate ..
        ":3,4="   .. shine_bar ..
        ":3,3="   .. rivet_px ..
        ":12,3="  .. rivet_px ..
        ":3,12="  .. rivet_px ..
        ":12,12=" .. rivet_px
end

local function build_alloy_inventory_icon()
    if file_exists(CONFIG.TEX_ANDESITE_ALLOY) then
        return CONFIG.TEX_ANDESITE_ALLOY
    end
    local ingot_tex = get_registered_item_tex("mcl_core:iron_ingot", "default_steel_ingot.png")
    local clean_ing = string.match(ingot_tex, "^[^%^]+") or ingot_tex
    return clean_ing .. "^[colorize:" .. CONFIG.ALLOY_TINT_HEX .. ":135"
end

local function get_casing_tiles(custom_top, custom_side, tint_modifier)
    tint_modifier = tint_modifier or ""
    local top_tex = file_exists(custom_top)
        and custom_top
        or  (CONFIG.FALLBACK_CASING_TOP .. tint_modifier)
    local side_tex = file_exists(custom_side)
        and custom_side
        or  (CONFIG.FALLBACK_CASING_SIDE .. tint_modifier)

    return {
        top_tex,
        top_tex,
        side_tex,
        side_tex,
        side_tex,
        side_tex,
    }
end

local function is_wood_or_log_node(node_name)
    if not node_name or node_name == "air" or node_name == "ignore" then
        return false
    end
    if kinetica.is_casing(node_name) then
        return false
    end
    return core.get_item_group(node_name, "tree") > 0 or
           core.get_item_group(node_name, "wood") > 0 or
           string.find(node_name, "_log") ~= nil or
           string.find(node_name, "_bark") ~= nil or
           string.find(node_name, "_planks") ~= nil
end

local function try_apply_casing_inworld(itemstack, placer, pointed_thing, target_casing_name)
    if not CONFIG.ENABLE_INWORLD_CASING_CLICK then
        return itemstack
    end
    if not pointed_thing or pointed_thing.type ~= "node" or not pointed_thing.under then
        return itemstack
    end

    local pos   = pointed_thing.under
    local unode = core.get_node(pos)
    local udef  = core.registered_nodes[unode.name]
    local sneak = placer and placer:is_player() and placer:get_player_control().sneak

    if udef and udef.on_rightclick and not sneak then
        return udef.on_rightclick(pos, unode, placer, itemstack, pointed_thing) or itemstack
    end

    if not is_wood_or_log_node(unode.name) then
        return itemstack
    end

    local pname = placer and placer:is_player() and placer:get_player_name() or ""
    if core.is_protected(pos, pname) then
        return itemstack
    end

    core.set_node(pos, {name = target_casing_name, param2 = 0})
    core.sound_play("default_place_node_hard", {pos = pos, max_hear_distance = 12, gain = 0.75}, true)

    local cdef = core.registered_nodes[target_casing_name]
    local ptex = (cdef and cdef.tiles and cdef.tiles[3]) or CONFIG.FALLBACK_CASING_SIDE
    core.add_particlespawner({
        amount     = 12,
        time       = 0.15,
        minpos     = {x = pos.x - 0.52, y = pos.y - 0.52, z = pos.z - 0.52},
        maxpos     = {x = pos.x + 0.52, y = pos.y + 0.52, z = pos.z + 0.52},
        minvel     = {x = -0.8, y = 0.3, z = -0.8},
        maxvel     = {x =  0.8, y = 1.2, z =  0.8},
        minexptime = 0.20,
        maxexptime = 0.45,
        minsize    = 1.2,
        maxsize    = 2.2,
        texture    = ptex,
    })

    if CONFIG.CONSUME_ITEM_ON_INWORLD_CLICK and pname ~= "" and not core.is_creative_enabled(pname) then
        itemstack:take_item(1)
    end
    return itemstack
end

core.register_craftitem(ALLOY_NAME, {
    description     = "Andesite Alloy\nFoundational structural alloy used to craft Casings, Shafts & Kinetic Machines.\nTip: Right-click any Wood Log in the world to turn it into an Andesite Casing!",
    inventory_image = build_alloy_inventory_icon(),
    wield_image     = build_alloy_inventory_icon(),
    groups          = {craftitem = 1, kinetica_alloy = 1},
    on_place        = function(itemstack, placer, pointed_thing)
        return try_apply_casing_inworld(itemstack, placer, pointed_thing, CASING_ANDESITE)
    end,
})

local iron_sheet_icon = build_sheet_inventory_icon(
    CONFIG.TEX_SHEET_IRON, "mcl_core:ironblock", "mcl_core:iron_ingot", CONFIG.IRON_SHEET_TINT_HEX
)
core.register_craftitem(SHEET_IRON, {
    description     = "Iron Sheet\nStamped from an Iron Ingot using a Mechanical Press.\nUsed to craft Saws, Chutes & Heavy Kinetic Machinery.",
    inventory_image = iron_sheet_icon,
    wield_image     = iron_sheet_icon,
    groups          = {craftitem = 1, kinetica_sheet = 1, sheet_iron = 1},
})

local copper_sheet_icon = build_sheet_inventory_icon(
    CONFIG.TEX_SHEET_COPPER, "mcl_copper:block", "mcl_copper:copper_ingot", CONFIG.COPPER_SHEET_TINT_HEX
)
core.register_craftitem(SHEET_COPPER, {
    description     = "Copper Sheet\nStamped from a Copper Ingot using a Mechanical Press.\nUsed to craft Copper Casings, Fluid Pipes, Water Pumps & Steam Power.",
    inventory_image = copper_sheet_icon,
    wield_image     = copper_sheet_icon,
    groups          = {craftitem = 1, kinetica_sheet = 1, sheet_copper = 1},
    on_place        = function(itemstack, placer, pointed_thing)
        return try_apply_casing_inworld(itemstack, placer, pointed_thing, CASING_COPPER)
    end,
})

local gold_sheet_icon = build_sheet_inventory_icon(
    CONFIG.TEX_SHEET_GOLD, "mcl_core:goldblock", "mcl_core:gold_ingot", CONFIG.GOLD_SHEET_TINT_HEX
)
core.register_craftitem(SHEET_GOLD, {
    description     = "Gold Sheet\nStamped from a Gold Ingot using a Mechanical Press.\nUsed to craft Gold Casings, Smart Chutes & Smart Sorting Funnels.",
    inventory_image = gold_sheet_icon,
    wield_image     = gold_sheet_icon,
    groups          = {craftitem = 1, kinetica_sheet = 1, sheet_gold = 1},
    on_place        = function(itemstack, placer, pointed_thing)
        return try_apply_casing_inworld(itemstack, placer, pointed_thing, CASING_GOLD)
    end,
})

local sound_wood_metal = (mcl_sounds and mcl_sounds.node_sound_metal_defaults)
    and mcl_sounds.node_sound_metal_defaults()
    or  nil

core.register_node(CASING_ANDESITE, {
    description           = "Andesite Casing (Tier 1 Machine Housing)\nUsed to build Gearboxes, Chain Drives, Drills, Saws, Depots, Pistons & the Mechanical Press.",
    drawtype              = "normal",
    tiles                 = get_casing_tiles(CONFIG.TEX_ANDESITE_CASING_TOP, CONFIG.TEX_ANDESITE_CASING_SIDE, ""),
    paramtype2            = "facedir",
    is_ground_content     = false,
    groups                = {handy = 1, pickaxey = 1, axey = 1, building_block = 1, kinetica_casing = 1},
    _mcl_hardness         = 2.5,
    _mcl_blast_resistance = 3.5,
    sounds                = sound_wood_metal,
})

core.register_node(CASING_COPPER, {
    description           = "Copper Casing (Tier 2 Fluid & Steam Housing)\nUsed to build Water Pumps, Steam Generators & Steam Turbines.",
    drawtype              = "normal",
    tiles                 = get_casing_tiles(CONFIG.TEX_COPPER_CASING_TOP, CONFIG.TEX_COPPER_CASING_SIDE, CONFIG.COPPER_CASING_TINT),
    paramtype2            = "facedir",
    is_ground_content     = false,
    groups                = {handy = 1, pickaxey = 1, axey = 1, building_block = 1, kinetica_casing = 1},
    _mcl_hardness         = 3.0,
    _mcl_blast_resistance = 4.0,
    sounds                = sound_wood_metal,
})

core.register_node(CASING_GOLD, {
    description           = "Gold Casing (Tier 3 Smart Logic Housing)\nUsed to build Smart Sorting Funnels & Precision Logistics.",
    drawtype              = "normal",
    tiles                 = get_casing_tiles(CONFIG.TEX_GOLD_CASING_TOP, CONFIG.TEX_GOLD_CASING_SIDE, CONFIG.GOLD_CASING_TINT),
    paramtype2            = "facedir",
    is_ground_content     = false,
    groups                = {handy = 1, pickaxey = 1, axey = 1, building_block = 1, kinetica_casing = 1},
    _mcl_hardness         = 3.0,
    _mcl_blast_resistance = 4.0,
    sounds                = sound_wood_metal,
})

kinetica._glasses_formatters = kinetica._glasses_formatters or {}

local LINE_TOP = "┌─ ENGINEER'S GLASSES ──────────────"
local LINE_DET = "├─ CASING DETAILS ──────────────────"
local LINE_BOT = "└───────────────────────────────────"

local function kv_row(label, value)
    return string.format("│  %-11s: %s", label, tostring(value))
end

local function format_casing_glasses_info(pos, node)
    local name = node and node.name or ""
    local title, tier_str, mat_str, use_str = "Andesite Casing", "Tier 1 (Basic Kinetics)", "Andesite Alloy + Wood", "Press, Drill, Saw, Gearbox, Depot"

    if name == CASING_COPPER then
        title    = "Copper Casing"
        tier_str = "Tier 2 (Fluids & Steam)"
        mat_str  = "Copper Sheets + Wood"
        use_str  = "Water Pump, Boiler, Steam Turbine"
    elseif name == CASING_GOLD then
        title    = "Gold Casing"
        tier_str = "Tier 3 (Smart Logistics)"
        mat_str  = "Gold Sheets + Wood"
        use_str  = "Smart Funnel & Precision Routing"
    end

    return table.concat({
        LINE_TOP,
        "│  " .. title,
        "│  ● TIER     : " .. tier_str,
        LINE_DET,
        kv_row("Composition", mat_str),
        kv_row("Used For",    use_str),
        LINE_BOT,
    }, "\n")
end

kinetica._glasses_formatters[CASING_ANDESITE] = format_casing_glasses_info
kinetica._glasses_formatters[CASING_COPPER]   = format_casing_glasses_info
kinetica._glasses_formatters[CASING_GOLD]     = format_casing_glasses_info

core.register_craft({
    type   = "shapeless",
    output = "kinetica:andesite_alloy 2",
    recipe = {"mcl_core:andesite", "mcl_core:iron_ingot"},
})

core.register_craft({
    output = "kinetica:andesite_alloy 4",
    recipe = {
        {"mcl_core:andesite",   "mcl_core:iron_ingot"},
        {"mcl_core:iron_ingot", "mcl_core:andesite"},
    },
})

core.register_craft({
    output = "kinetica:andesite_alloy 1",
    recipe = {
        {"mcl_core:andesite",    "mcl_core:iron_nugget"},
        {"mcl_core:iron_nugget", "mcl_core:andesite"},
    },
})

for _, wood_group in ipairs({"group:tree", "group:wood"}) do
    core.register_craft({
        output = "kinetica:andesite_casing",
        recipe = {
            {"", "kinetica:andesite_alloy", ""},
            {"", wood_group,                    ""},
            {"", "kinetica:andesite_alloy", ""},
        },
    })

    core.register_craft({
        output = "kinetica:copper_casing",
        recipe = {
            {"", "kinetica:sheet_copper", ""},
            {"", wood_group,                  ""},
            {"", "kinetica:sheet_copper", ""},
        },
    })

    core.register_craft({
        output = "kinetica:gold_casing",
        recipe = {
            {"", "kinetica:sheet_gold", ""},
            {"", wood_group,                ""},
            {"", "kinetica:sheet_gold", ""},
        },
    })
end