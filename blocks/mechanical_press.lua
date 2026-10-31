kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""
local PRESS_SOUND_NAME = nil

local CONFIG = {
    MIN_RPM                       = 1,
    BASE_SPEED_RPM                = 16,
    KU_PER_RPM                    = 4,
    MIN_DEMAND_KU                 = 16,
    MAX_DEMAND_KU                 = 512,
    RPM_SPEED_EXPONENT            = 1.00,
    STACK_TIME_LOG_FACTOR         = 0.14,
    TIMER_INTERVAL                = 0.10,
    MAX_BATCH_SIZE                = 64,
    MAX_STROKE_OFFSET             = 0.75,
    TEX_STONE_FALLBACK            = "default_stone.png",
    TEX_IRON_FALLBACK             = "create_mechanical_press_head.png",
    TEX_WOOD_FALLBACK             = "create_mechanical_press_head.png",
    TEX_SHAFT_OVERLAY             = "kinetica_shaft_connecting_overlay.png",
}

local IDLE_NAME     = "kinetica:mechanical_press"
local ACTIVE_NAME   = "kinetica:mechanical_press_active"
local RAM_MESH_NAME = "kinetica:mechanical_press_ram_mesh"
local ENTITY_NAME   = "kinetica:mechanical_press_ram"

local PRESS_STATE = {}

local function resolve_node_texture(node_name, fallback)
    local ndef = core.registered_nodes[node_name]
    if ndef and ndef.tiles and ndef.tiles[1] then
        local t = ndef.tiles[1]
        if type(t) == "string" and t ~= "" then
            return t
        elseif type(t) == "table" and type(t.name) == "string" and t.name ~= "" then
            return t.name
        end
    end
    return fallback
end

local STONE_TEX  = resolve_node_texture("mcl_core:stone",       CONFIG.TEX_STONE_FALLBACK)
local IRON_TEX   = resolve_node_texture("mcl_core:ironblock",   CONFIG.TEX_IRON_FALLBACK)
local WOOD_TEX   = resolve_node_texture("mcl_core:wood",        CONFIG.TEX_WOOD_FALLBACK)
local CASING_TEX = STONE_TEX .. "^[multiply:#7c858c"
local DARK_TEX   = STONE_TEX .. "^[multiply:#454a4f"
local RAM_TEX    = IRON_TEX  .. "^[multiply:#b0b8c0"
local AXLE_TEX   = CASING_TEX .. "^(" .. CONFIG.TEX_SHAFT_OVERLAY .. "^[sheet:1x4:0,0)"

-- Ensure metal sheets exist in the inventory even if another file hasn't registered them yet
local function ensure_sheet_item(name, desc, base_ingot, color_hex)
    if core.registered_items[name] then return end
    local base_def = core.registered_items[base_ingot]
    local inv_img  = (base_def and base_def.inventory_image and base_def.inventory_image ~= "")
        and (base_def.inventory_image .. "^[colorize:" .. color_hex .. ":45")
        or  (IRON_TEX .. "^[colorize:" .. color_hex .. ":140")

    core.register_craftitem(name, {
        description     = desc,
        inventory_image = inv_img,
        groups          = {craftitem = 1, metal_sheet = 1},
    })
end

ensure_sheet_item("kinetica:sheet_iron",   "Iron Sheet",   "mcl_core:iron_ingot",     "#e0e4e8")
ensure_sheet_item("kinetica:sheet_gold",   "Golden Sheet", "mcl_core:gold_ingot",     "#ffd83d")
ensure_sheet_item("kinetica:sheet_copper", "Copper Sheet", "mcl_copper:copper_ingot", "#e07a45")

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

local function resolve_press_sound()
    local custom = "kinetica_press_stamp"
    local f = io.open(modpath .. "/sounds/" .. custom .. ".ogg", "r")
    if f then
        f:close()
        return custom
    end
    if mcl_sounds and mcl_sounds.node_sound_metal_defaults then
        local ms = mcl_sounds.node_sound_metal_defaults()
        if ms and ms.dug and ms.dug.name then
            return ms.dug.name
        end
    end
    local iron_def = core.registered_nodes["mcl_core:ironblock"]
    if iron_def and iron_def.sounds and iron_def.sounds.place and iron_def.sounds.place.name then
        return iron_def.sounds.place.name
    end
    return "default_place_node_hard"
end

local function play_press_stamp_sound(pos)
    if not PRESS_SOUND_NAME then
        PRESS_SOUND_NAME = resolve_press_sound()
    end
    core.sound_play(PRESS_SOUND_NAME, {
        pos               = pos,
        gain              = 0.85,
        pitch             = 0.75 + math.random() * 0.10,
        max_hear_distance = 16,
    }, true)
end

kinetica.pressing_recipes = kinetica.pressing_recipes or {}

function kinetica.register_pressing_recipe(input_item, def)
    if not input_item or not def or not def.output then return end
    kinetica.pressing_recipes[input_item] = {
        output      = def.output,
        input_count = math.max(1, def.input_count or 1),
        time        = def.time or 1.0,
    }
end

-- Create-Mod Pressing & Compacting Recipes for Mineclonia
local DEFAULT_PRESS_RECIPES = {
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

for iname, rdef in pairs(DEFAULT_PRESS_RECIPES) do
    kinetica.register_pressing_recipe(iname, rdef)
end

local function get_pressing_recipe_for_stack(stack)
    if not stack or stack:is_empty() then return nil end
    local name  = stack:get_name()
    local count = stack:get_count()

    if core.get_item_group(name, "tree") > 0 then
        return {output = "mcl_core:wood 4", input_count = 1, time = 1.0}
    end

    local rec = kinetica.pressing_recipes[name]
    if rec and count >= (rec.input_count or 1) then
        return rec
    end
    return nil
end

-- Nodeboxes for the Mechanical Press Housing and Animated Ram
local PRESS_HOUSING_BOXES = {
    -- Top heavy cap
    {-8/16,  4/16, -8/16,  8/16,  8/16,  8/16},
    -- Corner structural pillars
    {-8/16, -6/16, -8/16, -5/16,  4/16, -5/16},
    { 5/16, -6/16, -8/16,  8/16,  4/16, -5/16},
    {-8/16, -6/16,  5/16, -5/16,  4/16,  8/16},
    { 5/16, -6/16,  5/16,  8/16,  4/16,  8/16},
    -- Lower guide collar
    {-7/16, -8/16, -7/16,  7/16, -5/16,  7/16},
    -- Inner axle gearbox core
    {-5/16, -3/16, -5/16,  5/16,  4/16,  5/16},
}

local IDLE_PRESS_BOXES = table.copy(PRESS_HOUSING_BOXES)
IDLE_PRESS_BOXES[#IDLE_PRESS_BOXES + 1] = {-2/16, -9/16,  -2/16, 2/16,  6/16,  2/16}
IDLE_PRESS_BOXES[#IDLE_PRESS_BOXES + 1] = {-6/16, -11/16, -6/16, 6/16, -8/16,  6/16}

local RAM_MESH_BOXES = {
    -- Vertical plunger shaft
    {-2/16, -7/16,  -2/16, 2/16,  8/16,  2/16},
    -- Heavy iron stamping plate
    {-6/16, -11/16, -6/16, 6/16, -7/16,  6/16},
    {-5/16, -12/16, -5/16, 5/16, -11/16, 5/16},
}

core.register_node(RAM_MESH_NAME, {
    description         = "Mechanical Press Ram Mesh",
    drawtype            = "nodebox",
    paramtype           = "light",
    sunlight_propagates = true,
    tiles = {
        RAM_TEX,
        DARK_TEX,
        WOOD_TEX,
        WOOD_TEX,
        RAM_TEX,
        RAM_TEX,
    },
    node_box = {
        type  = "fixed",
        fixed = RAM_MESH_BOXES,
    },
    groups = {not_in_creative_inventory = 1},
})

core.register_entity(ENTITY_NAME, {
    initial_properties = {
        physical             = false,
        collide_with_objects = false,
        pointable            = false,
        visual               = "wielditem",
        wield_item           = RAM_MESH_NAME,
        visual_size          = {x = 0.6667, y = 0.6667, z = 0.6667},
        static_save          = false,
        shaded               = true,
    },

    on_activate = function(self)
        self.object:set_armor_groups({immortal = 1})
        core.after(0.2, function()
            if self.object and self.object:get_luaentity() then
                local pos = self.object:get_pos()
                if pos and self.base_pos then
                    local node = core.get_node(self.base_pos)
                    if not kinetica.is_mechanical_press(node.name) then
                        self.object:remove()
                    end
                end
            end
        end)
    end,
})

function kinetica.is_mechanical_press(name)
    return name == IDLE_NAME or name == ACTIVE_NAME
end

function kinetica.get_press_axis(param2)
    local p2  = (param2 or 0) % 4
    local dir = core.facedir_to_dir(p2) or {x = 0, y = 0, z = 1}
    -- Facedir 0/2 has front/back along Z, so axle ports on left/right or front/back
    return {
        x = math.abs(dir.x),
        y = 0,
        z = math.abs(dir.z),
    }
end

local function normalize_press_param2(axis)
    return (axis.x ~= 0) and 1 or 0
end

local function sync_press_ram_entity(pos, stroke_ratio)
    local ram_obj = nil
    for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.95)) do
        local le = obj:get_luaentity()
        if le and le.name == ENTITY_NAME then
            if not ram_obj then
                ram_obj = obj
            else
                obj:remove()
            end
        end
    end

    if not ram_obj then
        ram_obj = core.add_entity(pos, ENTITY_NAME)
    end

    if ram_obj then
        local le = ram_obj:get_luaentity()
        if le then
            le.base_pos = {x = pos.x, y = pos.y, z = pos.z}
        end
        local dy = -(math.max(0.0, math.min(1.0, stroke_ratio or 0.0)) * CONFIG.MAX_STROKE_OFFSET)
        ram_obj:set_pos({x = pos.x, y = pos.y + dy, z = pos.z})
    end
end

local function remove_press_ram_entity(pos)
    for _, obj in ipairs(core.get_objects_inside_radius(pos, 1.15)) do
        local le = obj:get_luaentity()
        if le and le.name == ENTITY_NAME then
            obj:remove()
        end
    end
end

local function calc_press_demand_ku(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then return 0 end
    local raw = math.floor(rpm * CONFIG.KU_PER_RPM)
    return math.min(CONFIG.MAX_DEMAND_KU, math.max(CONFIG.MIN_DEMAND_KU, raw))
end

local function calc_press_speed_multiplier(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then return 0.25 end
    return math.max(0.25, (rpm / CONFIG.BASE_SPEED_RPM) ^ CONFIG.RPM_SPEED_EXPONENT)
end

local function extract_meta_power(m)
    local rpm = m:get_float("rpm")
    local sup = m:get_int("network_supply_ku")
    local ava = m:get_int("rotational_power")
    local spn = m:get_int("spin_dir")

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
        sup = math.max(64, calc_press_demand_ku(rpm))
        if ava <= 0 then ava = sup end
    end
    if spn == 0 then spn = m:get_int("local_spin") end
    if spn == 0 then spn = 1 end

    return (rpm >= CONFIG.MIN_RPM and sup > 0), rpm, sup, ava, spn
end

local function read_press_direct_power(pos, axis, meta)
    local check_dirs = {
        {x =  axis.x, y = 0, z =  axis.z},
        {x = -axis.x, y = 0, z = -axis.z},
        {x =  axis.z, y = 0, z =  axis.x},
        {x = -axis.z, y = 0, z = -axis.x},
        {x = 0,       y = 1, z = 0},
    }

    local has_neighbor = false
    for _, d in ipairs(check_dirs) do
        local epos  = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
        local enode = core.get_node(epos)
        local ename = enode.name
        if ename and ename ~= "air" and ename ~= "ignore" and not kinetica.is_mechanical_press(ename) then
            local emeta = core.get_meta(epos)
            local ok, erpm, esup, eava, espn = extract_meta_power(emeta)
            if ok then
                return true, erpm, esup, eava, espn
            end
            if (kinetica.is_shaft and kinetica.is_shaft(ename)) or
               string.find(ename, "shaft") or string.find(ename, "cog") or
               string.find(ename, "gearbox") or string.find(ename, "water_wheel") then
                has_neighbor = true
            end
        end
    end

    if has_neighbor then
        local ok, mrpm, msup, mava, mspn = extract_meta_power(meta)
        if ok then
            return true, mrpm, msup, mava, mspn
        end
    end

    return false, 0, 0, 0, 1
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

local function format_press_glasses_info(pos, node)
    local meta = core.get_meta(pos)
    local axis = kinetica.get_press_axis(node.param2)
    local pow, rpm, supply, avail, _ = read_press_direct_power(pos, axis, meta)

    local is_active  = pow and (rpm >= CONFIG.MIN_RPM)
    local demand     = is_active and calc_press_demand_ku(rpm) or 0
    local used       = (supply > 0) and math.max(0, supply - avail) or 0
    local speed_mult = is_active and calc_press_speed_multiplier(rpm) or 0.0
    local item_str   = meta:get_string("pressing_item")
    local prog_pct   = meta:get_int("press_pct")

    local state_str = "IDLE (Connect Shaft to Side Axle)"
    if is_active then
        state_str = (item_str ~= "") and ("STAMPING (" .. item_str .. ")") or "READY (Place Depot / Belt Below)"
    end

    return table.concat({
        LINE_TOP,
        "│  Mechanical Press",
        "│  ● STATE    : " .. state_str,
        LINE_NET,
        kv_row("Speed",      string.format("%.1f RPM  (%.2fx Press Speed)", is_active and rpm or 0, speed_mult)),
        kv_row("Press Load", string.format("-%d KU", demand)),
        kv_row("Net Pool",   string.format("%d / %d KU Avail", is_active and avail or 0, supply)),
        kv_row("Net Stress", make_bar(is_active and used or 0, supply)),
        LINE_DET,
        kv_row("Target",     "1 or 2 Blocks Below (-Y)"),
        kv_row("Pressing",   (item_str ~= "") and item_str or "Waiting for Ingots / Stacks"),
        kv_row("Progress",   make_bar(prog_pct, 100)),
        LINE_BOT,
    }, "\n")
end

kinetica._glasses_formatters[IDLE_NAME]   = format_press_glasses_info
kinetica._glasses_formatters[ACTIVE_NAME] = format_press_glasses_info

local function process_mechanical_press(pos, meta, rpm)
    local phash = core.hash_node_position(pos)
    local found_kind   = nil
    local found_pos    = nil
    local found_obj    = nil
    local found_ent    = nil
    local found_stack  = nil
    local found_recipe = nil
    local found_list   = nil
    local found_slot   = nil

    -- Check 1 and 2 blocks underneath for a Depot/Container or Belt/Dropped Item
    for _, dy in ipairs({-1, -2}) do
        local bpos  = {x = pos.x, y = pos.y + dy, z = pos.z}
        local bnode = core.get_node(bpos)
        local bname = bnode.name

        local is_depot = (bname == "kinetica:depot" or
                          core.get_item_group(bname, "kinetica_depot") > 0 or
                          string.find(bname, "depot") or
                          string.find(bname, "basin"))

        if is_depot then
            local binv = core.get_meta(bpos):get_inventory()
            if binv then
                for _, lname in ipairs({"input", "main"}) do
                    local sz = binv:get_size(lname)
                    for slot = 1, sz do
                        local st  = binv:get_stack(lname, slot)
                        local rec = get_pressing_recipe_for_stack(st)
                        if rec then
                            found_kind   = "depot"
                            found_pos    = bpos
                            found_stack  = st
                            found_recipe = rec
                            found_list   = lname
                            found_slot   = slot
                            break
                        end
                    end
                    if found_recipe then break end
                end
            end
        end

        if found_recipe then break end

        -- Check for item entities on a Belt or Floor at this height
        for _, obj in ipairs(core.get_objects_inside_radius({x = bpos.x, y = bpos.y + 0.35, z = bpos.z}, 0.85)) do
            local le = obj:get_luaentity()
            if le and le.name == "__builtin:item" and le.itemstring and le.itemstring ~= "" then
                local st  = ItemStack(le.itemstring)
                local rec = get_pressing_recipe_for_stack(st)
                if rec then
                    found_kind   = "entity"
                    found_pos    = bpos
                    found_obj    = obj
                    found_ent    = le
                    found_stack  = st
                    found_recipe = rec
                    break
                end
            end
        end

        if found_recipe then break end
    end

    if not found_recipe or not found_stack then
        PRESS_STATE[phash] = nil
        meta:set_string("pressing_item", "")
        meta:set_int("press_pct", 0)
        sync_press_ram_entity(pos, 0.0)
        return
    end

    if found_kind == "entity" and found_obj and found_ent then
        found_ent._kinetica_vacuumed = true
        found_obj:set_velocity({x = 0, y = 0, z = 0})
    end

    local in_per_craft = math.max(1, found_recipe.input_count or 1)
    local max_crafts   = math.min(CONFIG.MAX_BATCH_SIZE, math.floor(found_stack:get_count() / in_per_craft))
    local consume_cnt  = max_crafts * in_per_craft
    local item_name    = found_stack:get_name()
    local idef         = core.registered_items[item_name]
    local clean_desc   = (idef and idef.description) and string.match(idef.description, "^[^\n%(]+") or item_name
    meta:set_string("pressing_item", string.format("%s x%d", clean_desc, consume_cnt))

    local speed_mult = calc_press_speed_multiplier(rpm)
    local stack_mult = 1.0 + CONFIG.STACK_TIME_LOG_FACTOR * math.log(math.max(1, max_crafts))
    local total_need = math.max(0.15, (found_recipe.time * stack_mult) / speed_mult)

    local pstate = PRESS_STATE[phash]
    if not pstate or pstate.item_name ~= item_name then
        pstate = {item_name = item_name, prog = 0, stamped_sound = false}
        PRESS_STATE[phash] = pstate
    end

    pstate.prog = pstate.prog + CONFIG.TIMER_INTERVAL
    local ratio = math.min(1.0, pstate.prog / total_need)
    local pct   = math.min(100, math.floor(ratio * 100))
    meta:set_int("press_pct", pct)

    -- Triangle wave stroke: plunges down to 1.0 at 70% progress, then retracts
    local stroke = (ratio <= 0.70) and (ratio / 0.70) or ((1.0 - ratio) / 0.30)
    sync_press_ram_entity(pos, stroke)

    -- Play stamping sound once when the ram reaches full extension
    if ratio >= 0.70 and not pstate.stamped_sound then
        pstate.stamped_sound = true
        play_press_stamp_sound(pos)
    end

    if pstate.prog >= total_need then
        local out_base  = ItemStack(found_recipe.output)
        local out_name  = out_base:get_name()
        local out_per_1 = math.max(1, out_base:get_count())
        local out_total = out_per_1 * max_crafts
        local out_stack = ItemStack(out_name .. " " .. out_total)

        local part_tex = resolve_item_particle_texture(item_name)
        core.add_particlespawner({
            amount     = 10,
            time       = 0.08,
            minpos     = {x = found_pos.x - 0.25, y = found_pos.y + 0.15, z = found_pos.z - 0.25},
            maxpos     = {x = found_pos.x + 0.25, y = found_pos.y + 0.45, z = found_pos.z + 0.25},
            minvel     = {x = -0.8, y = 0.2, z = -0.8},
            maxvel     = {x =  0.8, y = 1.1, z =  0.8},
            minexptime = 0.20,
            maxexptime = 0.45,
            minsize    = 1.2,
            maxsize    = 2.4,
            texture    = part_tex,
        })

        if found_kind == "depot" then
            local binv = core.get_meta(found_pos):get_inventory()
            if binv then
                found_stack:take_item(consume_cnt)
                binv:set_stack(found_list, found_slot, found_stack)
                local target_list = (binv:get_size("output") > 0) and "output" or "main"
                local leftover    = binv:add_item(target_list, out_stack)
                if not leftover:is_empty() then
                    core.add_item({x = found_pos.x, y = found_pos.y + 0.45, z = found_pos.z}, leftover)
                end
                local dt = core.get_node_timer(found_pos)
                if dt and not dt:is_started() then dt:start(0.15) end
            end
        elseif found_kind == "entity" and found_obj and found_ent then
            local spawn_p = found_obj:get_pos() or {x = found_pos.x, y = found_pos.y + 0.35, z = found_pos.z}
            found_stack:take_item(consume_cnt)
            if found_stack:is_empty() then
                found_obj:remove()
            else
                found_ent._kinetica_vacuumed = false
                found_ent:set_item(found_stack:to_string())
            end
            core.add_item(spawn_p, out_stack)
        end

        PRESS_STATE[phash] = nil
        meta:set_string("pressing_item", "")
        meta:set_int("press_pct", 0)
        sync_press_ram_entity(pos, 0.0)
    end
end

local function press_timer(pos, elapsed)
    local node = core.get_node(pos)
    if not kinetica.is_mechanical_press(node.name) then
        remove_press_ram_entity(pos)
        return false
    end

    local meta    = core.get_meta(pos)
    local axis    = kinetica.get_press_axis(node.param2)
    local norm_p2 = normalize_press_param2(axis)

    if node.name ~= ACTIVE_NAME or node.param2 ~= norm_p2 then
        core.swap_node(pos, {name = ACTIVE_NAME, param2 = norm_p2})
        node = core.get_node(pos)
    end

    local pow, rpm, _, _, _ = read_press_direct_power(pos, axis, meta)
    local is_active = pow and (rpm >= CONFIG.MIN_RPM)
    local demand_ku = is_active and calc_press_demand_ku(rpm) or 0
    meta:set_int("machine_demand_ku", demand_ku)

    if is_active then
        process_mechanical_press(pos, meta, rpm)
    else
        PRESS_STATE[core.hash_node_position(pos)] = nil
        meta:set_string("pressing_item", "")
        meta:set_int("press_pct", 0)
        sync_press_ram_entity(pos, 0.0)
    end

    meta:set_string("glasses_info", format_press_glasses_info(pos, node))
    return true
end

local PRESS_TILES = {
    CASING_TEX,
    DARK_TEX,
    AXLE_TEX,
    AXLE_TEX,
    AXLE_TEX,
    AXLE_TEX,
}

core.register_node(IDLE_NAME, {
    description = "Mechanical Press\n" ..
                  "Stamps Ingots into Metal Sheets and compacts 2x2 / 3x3 stacks automatically.\n" ..
                  "• Place 1 or 2 blocks above a Depot, Mechanical Belt, or Floor.\n" ..
                  "• Connect a Shaft or Cogwheel to any side port.",
    drawtype              = "nodebox",
    paramtype             = "light",
    paramtype2            = "facedir",
    sunlight_propagates   = true,
    tiles                 = PRESS_TILES,
    node_box = {
        type  = "fixed",
        fixed = IDLE_PRESS_BOXES,
    },
    groups = {
        pickaxey                  = 2,
        handy                     = 1,
        building_block            = 1,
        deco_block                = 1,
        kinetic_receiver          = 1,
        kinetica_mechanical_press = 1,
    },
    _mcl_hardness         = 3.5,
    _mcl_blast_resistance = 4.0,
    sounds                = mcl_sounds and mcl_sounds.node_sound_stone_defaults() or nil,

    on_construct = function(pos)
        local meta = core.get_meta(pos)
        meta:set_int("machine_demand_ku", 0)
        meta:set_int("press_pct", 0)
        meta:set_string("pressing_item", "")
        local node = core.get_node(pos)
        local axis = kinetica.get_press_axis(node.param2)
        local p2   = normalize_press_param2(axis)
        core.swap_node(pos, {name = ACTIVE_NAME, param2 = p2})
        sync_press_ram_entity(pos, 0.0)
        core.get_node_timer(pos):start(CONFIG.TIMER_INTERVAL)
        if kinetica.schedule_network_update then
            kinetica.schedule_network_update(pos)
        end
    end,

    on_destruct = function(pos)
        remove_press_ram_entity(pos)
        PRESS_STATE[core.hash_node_position(pos)] = nil
    end,

    after_dig_node = function(pos)
        remove_press_ram_entity(pos)
        if kinetica.schedule_network_update then
            kinetica.schedule_network_update(pos)
        end
    end,

    on_timer = press_timer,
})

core.register_node(ACTIVE_NAME, {
    description           = "Mechanical Press",
    drawtype              = "nodebox",
    paramtype             = "light",
    paramtype2            = "facedir",
    sunlight_propagates   = true,
    tiles                 = PRESS_TILES,
    node_box = {
        type  = "fixed",
        fixed = PRESS_HOUSING_BOXES,
    },
    drop                  = IDLE_NAME,
    groups = {
        pickaxey                  = 2,
        handy                     = 1,
        kinetic_receiver          = 1,
        kinetica_mechanical_press = 1,
        not_in_creative_inventory = 1,
    },
    _mcl_hardness         = 3.5,
    _mcl_blast_resistance = 4.0,
    sounds                = mcl_sounds and mcl_sounds.node_sound_stone_defaults() or nil,

    on_destruct = function(pos)
        remove_press_ram_entity(pos)
        PRESS_STATE[core.hash_node_position(pos)] = nil
    end,

    after_dig_node = function(pos)
        remove_press_ram_entity(pos)
        if kinetica.schedule_network_update then
            kinetica.schedule_network_update(pos)
        end
    end,

    on_timer = press_timer,
})

if kinetica.register_kinetic_machine then
    local machine_def = {
        can_ride_piston = true,
        min_rpm         = CONFIG.MIN_RPM,
        has_axle_port   = function(node, d)
            return (d.y == 0)
        end,
        get_demand_ku   = function(rpm, pos, node)
            return calc_press_demand_ku(rpm)
        end,
        set_idle        = function(pos, node, reason_text)
            sync_press_ram_entity(pos, 0.0)
            local meta = core.get_meta(pos)
            meta:set_float("rpm", 0)
            meta:set_int("network_supply_ku", 0)
            meta:set_int("rotational_power", 0)
            meta:set_string("pressing_item", "")
            meta:set_int("press_pct", 0)
            meta:set_string("glasses_info", format_press_glasses_info(pos, node))
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
        end,
    }
    kinetica.register_kinetic_machine(IDLE_NAME, machine_def)
    kinetica.register_kinetic_machine(ACTIVE_NAME, machine_def)
end

core.register_lbm({
    label             = "Wake kinetica Mechanical Presses on chunk load",
    name              = "kinetica:wake_mechanical_press_lbm",
    nodenames         = {"group:kinetica_mechanical_press"},
    run_at_every_load = true,
    action = function(pos, node)
        sync_press_ram_entity(pos, 0.0)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TIMER_INTERVAL)
        end
    end,
})

local casing_item = core.registered_items["kinetica:andesite_casing"]
    and "kinetica:andesite_casing"
    or  "kinetica:andesite_alloy"

core.register_craft({
    output = IDLE_NAME,
    recipe = {
        {"",          "kinetica:shaft",       ""},
        {"",          casing_item,            ""},
        {"",          "mcl_core:ironblock",   ""},
    },
})