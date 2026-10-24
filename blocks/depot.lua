kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

local CONFIG = {
    TICK_INTERVAL               = 0.20,
    DEPOT_TOP_Y                 = 4 / 16,
    ITEM_VISUAL_OFFSET_Y        = 0.05,
    LAY_ITEMS_FLAT              = true,
    CATCH_DROPPED_ITEMS         = true,
    AUTO_EJECT_TO_OUTGOING_BELT = true,
    BELT_EJECT_BATCH_SIZE       = 16,
    ENABLE_FAN_PROCESSING       = true,
    FAN_RANGE_AT_5_RPM          = 1,
    FAN_RANGE_AT_512_RPM        = 12,
    PROCESS_TIME_AT_5_RPM       = 6.0,
    PROCESS_TIME_AT_512_RPM     = 0.8,
    SCALE_TIME_BY_STACK_SIZE    = true,

    TEX_DEPOT_TOP               = "kinetica_depot_top.png",
    TEX_DEPOT_SIDE              = "kinetica_andisite_casing.png",
    TEX_DEPOT_BOTTOM            = "kinetica_andisite_casing.png",
    TEX_DEPOT_SINGLE            = "kinetica_depot.png",
    TEX_FALLBACK_TOP            = "mcl_stonecutter_bottom.png",
    TEX_FALLBACK_SIDE           = "kinetica_chain_drive_side.png",
    TEX_FALLBACK_BOTTOM         = "mcl_stonecutter_bottom.png",
}

local DEPOT_NAME   = "kinetica:depot"
local VISUAL_ENT   = "kinetica:depot_item_visual"
local CHUTE_NAME   = "kinetica:chute"
local OUTPUT_SLOTS = 4

local function file_exists(filename)
    local f = io.open(modpath .. "/textures/" .. filename, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function get_depot_tiles()
    if file_exists(CONFIG.TEX_DEPOT_TOP) and file_exists(CONFIG.TEX_DEPOT_SIDE) then
        local bot = file_exists(CONFIG.TEX_DEPOT_BOTTOM) and CONFIG.TEX_DEPOT_BOTTOM or CONFIG.TEX_DEPOT_TOP
        return {
            CONFIG.TEX_DEPOT_TOP,
            bot,
            CONFIG.TEX_DEPOT_SIDE,
            CONFIG.TEX_DEPOT_SIDE,
            CONFIG.TEX_DEPOT_SIDE,
            CONFIG.TEX_DEPOT_SIDE,
        }
    end

    if file_exists(CONFIG.TEX_DEPOT_SINGLE) then
        local s = CONFIG.TEX_DEPOT_SINGLE
        return {s, s, s, s, s, s}
    end

    local side_tex = file_exists(CONFIG.TEX_FALLBACK_SIDE)
        and CONFIG.TEX_FALLBACK_SIDE
        or "mcl_stonecutter_side.png"

    return {
        CONFIG.TEX_FALLBACK_TOP,
        CONFIG.TEX_FALLBACK_BOTTOM,
        side_tex,
        side_tex,
        side_tex,
        side_tex,
    }
end

local function rpm_factor(rpm)
    if not rpm or rpm <= 5 then return 0.0 end
    return math.min(1.0, math.max(0.0, (rpm - 5) / (512 - 5)))
end

local function lerp(a, b, t)
    return a + t * (b - a)
end

local function get_fan_range(rpm)
    return math.floor(lerp(CONFIG.FAN_RANGE_AT_5_RPM, CONFIG.FAN_RANGE_AT_512_RPM, rpm_factor(rpm)) + 0.5)
end

local function get_process_time(rpm, stack_count)
    local base = lerp(CONFIG.PROCESS_TIME_AT_5_RPM, CONFIG.PROCESS_TIME_AT_512_RPM, rpm_factor(rpm))
    if CONFIG.SCALE_TIME_BY_STACK_SIZE and stack_count and stack_count > 16 then
        local mult = math.min(4, math.ceil(stack_count / 16))
        return base * mult
    end
    return base
end

local function notify_comparators(pos)
    if mcl_redstone and mcl_redstone.update_comparators then
        pcall(mcl_redstone.update_comparators, vector.new(pos.x, pos.y, pos.z))
    end
end

local function ensure_depot_inventory(meta)
    local inv = meta:get_inventory()
    if inv:get_size("input") ~= 1 then
        inv:set_size("input", 1)
    end
    if inv:get_size("main") ~= 1 then
        inv:set_size("main", 1)
    end
    if inv:get_size("output") ~= OUTPUT_SLOTS then
        inv:set_size("output", OUTPUT_SLOTS)
    end
    return inv
end

local function get_displayed_stack(inv)
    local in_s = inv:get_stack("input", 1)
    if not in_s:is_empty() then
        return in_s, "input", 1
    end
    local main_s = inv:get_stack("main", 1)
    if not main_s:is_empty() then
        return main_s, "main", 1
    end
    for i = 1, OUTPUT_SLOTS do
        local out_s = inv:get_stack("output", i)
        if not out_s:is_empty() then
            return out_s, "output", i
        end
    end
    return ItemStack(""), nil, nil
end

local function get_active_hold_stack(inv)
    local in_s   = inv:get_stack("input", 1)
    local main_s = inv:get_stack("main", 1)

    if not in_s:is_empty() and not main_s:is_empty() then
        if in_s:get_name() == main_s:get_name() then
            local leftover = in_s:add_item(main_s)
            inv:set_stack("input", 1, in_s)
            inv:set_stack("main", 1, leftover)
        end
        return inv:get_stack("input", 1), "input"
    elseif not in_s:is_empty() then
        return in_s, "input"
    elseif not main_s:is_empty() then
        return main_s, "main"
    end
    return ItemStack(""), "main"
end

local function insert_onto_depot(inv, stack)
    if not stack or stack:is_empty() then
        return ItemStack("")
    end

    local held, slot_list = get_active_hold_stack(inv)
    if held:is_empty() then
        inv:set_stack("main", 1, stack)
        return ItemStack("")
    elseif held:get_name() == stack:get_name() then
        local leftover = held:add_item(stack)
        inv:set_stack(slot_list, 1, held)
        return leftover
    end

    return stack
end

core.register_entity(VISUAL_ENT, {
    initial_properties = {
        physical             = false,
        collide_with_objects = false,
        pointable            = false,
        visual               = "wielditem",
        wield_item           = "mcl_core:iron_ingot",
        visual_size          = {x = 0.30, y = 0.30, z = 0.30},
        automatic_rotate     = CONFIG.LAY_ITEMS_FLAT and 0 or 1.0,
        static_save          = false,
    },

    on_activate = function(self)
        self.object:set_armor_groups({immortal = 1})
        if CONFIG.LAY_ITEMS_FLAT and self.object.set_rotation then
            self.object:set_rotation({x = math.pi / 2, y = 0, z = 0})
        end
    end,

    on_step = function(self, dtime)
        self._check_timer = (self._check_timer or 0) + dtime
        if self._check_timer >= 0.5 then
            self._check_timer = 0
            local pos = self.object:get_pos()
            if not pos then
                self.object:remove()
                return
            end
            local bpos = {
                x = math.floor(pos.x + 0.5),
                y = math.floor(pos.y - CONFIG.DEPOT_TOP_Y - CONFIG.ITEM_VISUAL_OFFSET_Y + 0.5),
                z = math.floor(pos.z + 0.5),
            }
            if core.get_node(bpos).name ~= DEPOT_NAME then
                self.object:remove()
            end
        end
    end,
})

local function sync_depot_visual_entity(pos, inv)
    local disp_stack = get_displayed_stack(inv)
    local vpos = {
        x = pos.x,
        y = pos.y + CONFIG.DEPOT_TOP_Y + CONFIG.ITEM_VISUAL_OFFSET_Y,
        z = pos.z,
    }

    local found_obj = nil
    local objs = core.get_objects_inside_radius(vpos, 0.55)
    for _, obj in ipairs(objs) do
        local luaent = obj:get_luaentity()
        if luaent and luaent.name == VISUAL_ENT then
            if not found_obj then
                found_obj = obj
            else
                obj:remove()
            end
        end
    end

    if disp_stack:is_empty() then
        if found_obj then
            found_obj:remove()
        end
        return
    end

    local itemname = disp_stack:get_name()
    if not found_obj then
        found_obj = core.add_entity(vpos, VISUAL_ENT)
    end

    if found_obj then
        local luaent = found_obj:get_luaentity()
        if luaent and luaent._displayed_item ~= itemname then
            luaent._displayed_item = itemname
            found_obj:set_properties({
                wield_item  = itemname,
                visual_size = {x = 0.30, y = 0.30, z = 0.30},
            })
            if CONFIG.LAY_ITEMS_FLAT and found_obj.set_rotation then
                found_obj:set_rotation({x = math.pi / 2, y = 0, z = 0})
            end
        end
    end
end

local function remove_depot_visual_entity(pos)
    local vpos = {
        x = pos.x,
        y = pos.y + CONFIG.DEPOT_TOP_Y + CONFIG.ITEM_VISUAL_OFFSET_Y,
        z = pos.z,
    }
    local objs = core.get_objects_inside_radius(vpos, 0.75)
    for _, obj in ipairs(objs) do
        local luaent = obj:get_luaentity()
        if luaent and luaent.name == VISUAL_ENT then
            obj:remove()
        end
    end
end

local WASHING_CHANCE_RECIPES = {
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

local WASHING_DIRECT_RECIPES = {
    ["mcl_core:ice"]        = "mcl_core:packed_ice",
    ["mcl_nether:magma"]    = "mcl_core:obsidian",
    ["mcl_core:cobble"]     = "mcl_core:mossycobble",
    ["mcl_core:stonebrick"] = "mcl_core:stonebrickmossy",
    ["mcl_mud:mud"]         = "mcl_core:clay",
    ["mcl_sponges:sponge"]  = "mcl_sponges:sponge_wet",
    ["mcl_torches:torch"]   = "mcl_core:stick",
}

local HAUNTING_CHANCE_RECIPES = {
    ["mcl_core:lapis"] = {
        {item = "mcl_ocean:prismarine_shard",    chance = 0.75,  rolls = 1, count = 1},
        {item = "mcl_ocean:prismarine_crystals", chance = 0.125, rolls = 1, count = 1},
    },
}

local HAUNTING_DIRECT_RECIPES = {
    ["mcl_core:sand"]                 = "mcl_nether:soul_sand",
    ["mcl_core:redsand"]              = "mcl_nether:soul_sand",
    ["mcl_core:dirt"]                 = "mcl_blackstone:soul_soil",
    ["mcl_core:dirt_with_grass"]      = "mcl_blackstone:soul_soil",
    ["mcl_core:cobble"]               = "mcl_blackstone:blackstone",
    ["mcl_core:stone"]                = "mcl_core:cobble",
    ["mcl_core:stonebrick"]           = "mcl_core:stonebrickcracked",
    ["mcl_torches:torch"]             = "mcl_blackstone:soul_torch",
    ["mcl_lanterns:lantern_floor"]    = "mcl_lanterns:soul_lantern_floor",
    ["mcl_campfires:campfire"]        = "mcl_campfires:soul_campfire",
    ["mcl_campfires:campfire_lit"]    = "mcl_campfires:soul_campfire_lit",
    ["mcl_farming:bread"]             = "mcl_farming:potato_item_poison",
    ["mcl_sweet_berry:sweet_berries"] = "mcl_lush_caves:glow_berry",
    ["mcl_Farming:sweet_berry"]       = "mcl_lush_caves:glow_berry",
    ["mcl_mushrooms:mushroom_brown"]  = "mcl_crimson:crimson_fungus",
    ["mcl_mushrooms:mushroom_red"]    = "mcl_crimson:warped_fungus",
    ["mcl_nether:netherbrick"]        = "mcl_nether:red_nether_brick_block",
    ["mcl_ocean:prismarine"]          = "mcl_ocean:prismarine_dark",
    ["mcl_core:coal_lump"]            = "mcl_nether:glowstone_dust",
}

local FREEZING_RECIPES = {
    ["mcl_buckets:bucket_water"]       = "mcl_core:ice",
    ["mcl_buckets:bucket_river_water"] = "mcl_core:ice",
    ["mcl_buckets:bucket_lava"]        = "mcl_core:obsidian",
    ["mcl_core:ice"]                   = "mcl_core:packed_ice",
    ["mcl_core:packed_ice"]            = "mcl_core:blue_ice",
    ["mcl_mobitems:magma_cream"]       = "mcl_mobitems:slimeball",
    ["mcl_potions:water"]              = "mcl_throwing:snowball",
}

local function is_food_item(itemname)
    local def = core.registered_items[itemname]
    if not def then return false end
    if def.groups and (def.groups.food or def.groups.eatable) then
        return true
    end
    if string.find(itemname, "beef") or
       string.find(itemname, "pork") or
       string.find(itemname, "chicken") or
       string.find(itemname, "mutton") or
       string.find(itemname, "rabbit") or
       string.find(itemname, "cod") or
       string.find(itemname, "salmon") or
       string.find(itemname, "potato") or
       string.find(itemname, "kelp") or
       string.find(itemname, "bread") or
       string.find(itemname, "cooked") then
        return true
    end
    return false
end

local function get_special_washed_item(itemname)
    local direct = WASHING_DIRECT_RECIPES[itemname]
    if direct and core.registered_items[direct] then
        return direct
    end
    if string.find(itemname, "concrete_powder") then
        local hardened = string.gsub(itemname, "_powder", "")
        if core.registered_items[hardened] then
            return hardened
        end
    end
    if string.sub(itemname, 1, 9) == "mcl_wool:" and itemname ~= "mcl_wool:white" then
        if not string.find(itemname, "carpet") and core.registered_items["mcl_wool:white"] then
            return "mcl_wool:white"
        elseif string.find(itemname, "carpet") and core.registered_items["mcl_wool:white_carpet"] then
            return "mcl_wool:white_carpet"
        end
    end
    if string.sub(itemname, 1, 15) == "mcl_core:glass_" and core.registered_items["mcl_core:glass"] then
        return "mcl_core:glass"
    end
    if string.sub(itemname, 1, 12) == "xpanes:pane_" and core.registered_items["xpanes:bar_flat"] then
        return "xpanes:bar_flat"
    end
    return nil
end

local function can_item_be_processed(itemname, catalyst)
    if not itemname or itemname == "" or not catalyst then
        return false, nil
    end

    if catalyst == "washing" then
        if WASHING_CHANCE_RECIPES[itemname] or get_special_washed_item(itemname) then
            return true, nil
        end
    elseif catalyst == "haunting" then
        local out = HAUNTING_DIRECT_RECIPES[itemname]
        if HAUNTING_CHANCE_RECIPES[itemname] or (out and core.registered_items[out]) then
            return true, nil
        end
    elseif catalyst == "freezing" then
        local out = FREEZING_RECIPES[itemname]
        if out and core.registered_items[out] then
            return true, nil
        end
    elseif catalyst == "smoking" or catalyst == "blasting" then
        local cooked = core.get_craft_result({
            method = "cooking",
            width  = 1,
            items  = {ItemStack(itemname)},
        })
        if cooked and cooked.item and not cooked.item:is_empty() then
            local out_name = cooked.item:get_name()
            if catalyst == "smoking" then
                if is_food_item(itemname) or is_food_item(out_name) then
                    return true, cooked
                end
            else
                return true, cooked
            end
        end
    end

    return false, nil
end

local AXIS_TO_FAN_DIR = {
    [0] = {x =  0, y =  1, z =  0},
    [1] = {x =  0, y =  0, z =  1},
    [2] = {x =  0, y =  0, z = -1},
    [3] = {x =  1, y =  0, z =  0},
    [4] = {x = -1, y =  0, z =  0},
    [5] = {x =  0, y = -1, z =  0},
}

local function get_fan_dir(param2)
    local axisdir = math.floor(((param2 or 0) % 24) / 4)
    local d = AXIS_TO_FAN_DIR[axisdir] or AXIS_TO_FAN_DIR[0]
    return {x = d.x, y = d.y, z = d.z}
end

local function is_fan_pulling(fmeta, cnode)
    if fmeta:get_int("is_pull") == 1 then
        return true
    end
    local spin_dir = fmeta:get_int("spin_dir")
    local is_pull  = (spin_dir == -1) or (cnode.name == "kinetica:encased_fan_active_ccw")
    if fmeta:get_int("invert_dir") == 1 then
        is_pull = not is_pull
    end
    return is_pull
end

local CATALYST_PRIORITY = {
    washing  = 1,
    freezing = 2,
    smoking  = 3,
    haunting = 4,
    blasting = 5,
}

local function classify_stream_cell(node_name)
    if node_name == "air" or
       node_name == DEPOT_NAME or
       node_name == CHUTE_NAME or
       core.get_item_group(node_name, "mechanical_belt") > 0 then
        return true, nil
    end
    if node_name == "ignore" then
        return false, nil
    end
    if core.get_item_group(node_name, "lava") > 0 or string.find(node_name, "lava") then
        return true, "blasting"
    end
    if string.find(node_name, "soul_fire") or string.find(node_name, "soul_campfire") then
        return true, "haunting"
    end
    if core.get_item_group(node_name, "fire") > 0 or
       string.find(node_name, ":fire") or
       string.find(node_name, "campfire") then
        return true, "smoking"
    end
    if core.get_item_group(node_name, "water") > 0 or string.find(node_name, "water") then
        return true, "washing"
    end
    if string.find(node_name, "powder_snow") or
       node_name == "mcl_core:ice" or
       node_name == "mcl_core:packed_ice" or
       node_name == "mcl_core:blue_ice" then
        return true, "freezing"
    end
    if string.find(node_name, "iron_bars") or
       string.find(node_name, "fence") or
       string.find(node_name, "chain") or
       string.find(node_name, "trapdoor") or
       core.get_item_group(node_name, "leaves") > 0 then
        return true, nil
    end
    local def = core.registered_nodes[node_name]
    if def and def.walkable == false then
        return true, nil
    end
    return false, nil
end

local SCAN_DIRS = {
    {x =  1, y =  0, z =  0},
    {x = -1, y =  0, z =  0},
    {x =  0, y =  0, z =  1},
    {x =  0, y =  0, z = -1},
    {x =  0, y =  1, z =  0},
    {x =  0, y = -1, z =  0},
}

local function find_fan_catalyst_on_depot(pos)
    local target_levels = {
        {pt = pos,                                    same_level = true},
        {pt = {x = pos.x, y = pos.y + 1, z = pos.z}, same_level = false},
    }

    for _, lvl in ipairs(target_levels) do
        local tpos = lvl.pt
        for _, d in ipairs(SCAN_DIRS) do
            local best_cat = nil
            for dist = 1, CONFIG.FAN_RANGE_AT_512_RPM do
                local cpos = {
                    x = tpos.x + d.x * dist,
                    y = tpos.y + d.y * dist,
                    z = tpos.z + d.z * dist,
                }
                local cnode = core.get_node(cpos)

                if core.get_item_group(cnode.name, "encased_fan") > 0 then
                    local fmeta = core.get_meta(cpos)
                    if fmeta:get_string("active") == "true" then
                        local fdir = get_fan_dir(cnode.param2)
                        if fdir.x == -d.x and fdir.y == -d.y and fdir.z == -d.z then
                            local rpm     = fmeta:get_float("rpm")
                            local max_r   = get_fan_range(rpm)
                            local pulling = is_fan_pulling(fmeta, cnode)
                            if dist <= max_r then
                                local eff_cat = (not pulling) and best_cat or nil
                                return true, eff_cat, rpm, pulling
                            end
                        end
                    end
                    break
                end

                local passable, cat = classify_stream_cell(cnode.name)
                if not passable then
                    break
                end
                if cat then
                    if not best_cat or (CATALYST_PRIORITY[cat] or 0) >= (CATALYST_PRIORITY[best_cat] or 0) then
                        best_cat = cat
                    end
                end
            end
        end
    end
    return false, nil, 0, false
end

local function get_catalyst_bubble_style(catalyst)
    if catalyst == "blasting" then
        return "bubble.png^[colorize:#ff3b00:235", "bubble.png^[colorize:#ffb300:220", 14
    elseif catalyst == "smoking" then
        return "bubble.png^[colorize:#262626:230", "bubble.png^[colorize:#707070:200", 0
    elseif catalyst == "haunting" then
        return "bubble.png^[colorize:#00f0ff:230", "bubble.png^[colorize:#008090:215", 13
    elseif catalyst == "washing" then
        return "bubble.png^[colorize:#1ca3ec:215", "bubble.png^[colorize:#8be0ff:200", 0
    elseif catalyst == "freezing" then
        return "bubble.png^[colorize:#b0f4ff:230", "bubble.png^[colorize:#ffffff:230", 6
    end
    return "bubble.png^[colorize:#ffffff:155", nil, 0
end

local function spawn_depot_item_reaction_particles(pos, catalyst)
    if not catalyst then return end
    local tex1, tex2, glow = get_catalyst_bubble_style(catalyst)
    local vpos = {
        x = pos.x,
        y = pos.y + CONFIG.DEPOT_TOP_Y + 0.12,
        z = pos.z,
    }

    core.add_particlespawner({
        amount     = 5,
        time       = CONFIG.TICK_INTERVAL,
        minpos     = {x = vpos.x - 0.18, y = vpos.y - 0.04, z = vpos.z - 0.18},
        maxpos     = {x = vpos.x + 0.18, y = vpos.y + 0.16, z = vpos.z + 0.18},
        minvel     = {x = -0.25, y = 0.45, z = -0.25},
        maxvel     = {x =  0.25, y = 0.95, z =  0.25},
        minexptime = 0.20,
        maxexptime = 0.45,
        minsize    = 1.1,
        maxsize    = 1.9,
        collisiondetection = false,
        glow       = glow,
        texture    = tex2 or tex1,
    })
end

local function deposit_processed_output(pos, inv, out_stack)
    if not out_stack or out_stack:is_empty() then return end
    local leftover = inv:add_item("output", out_stack)
    if not leftover:is_empty() then
        core.add_item({x = pos.x, y = pos.y + CONFIG.DEPOT_TOP_Y + 0.25, z = pos.z}, leftover)
    end
end

local function deposit_chance_table_to_depot(pos, inv, count, chance_table)
    local out_totals = {}
    for _ = 1, count do
        for _, rule in ipairs(chance_table) do
            if core.registered_items[rule.item] then
                local rolls = rule.rolls or 1
                local qty   = rule.count or 1
                for _ = 1, rolls do
                    if math.random() <= rule.chance then
                        out_totals[rule.item] = (out_totals[rule.item] or 0) + qty
                    end
                end
            end
        end
    end

    for item_name, total_qty in pairs(out_totals) do
        local max_s = ItemStack(item_name):get_stack_max()
        while total_qty > 0 do
            local batch = math.min(total_qty, max_s)
            deposit_processed_output(pos, inv, ItemStack(item_name .. " " .. batch))
            total_qty = total_qty - batch
        end
    end
end

local function complete_depot_processing(pos, inv, stack, catalyst, cooked_res)
    local itemname = stack:get_name()
    local count    = stack:get_count()

    inv:set_stack("input", 1, ItemStack(""))
    inv:set_stack("main",  1, ItemStack(""))

    if catalyst == "washing" then
        local direct = get_special_washed_item(itemname)
        if direct then
            deposit_processed_output(pos, inv, ItemStack(direct .. " " .. count))
            return
        end
        local drops = WASHING_CHANCE_RECIPES[itemname]
        if drops then
            deposit_chance_table_to_depot(pos, inv, count, drops)
        end
        return
    end

    if catalyst == "haunting" then
        local drops = HAUNTING_CHANCE_RECIPES[itemname]
        if drops then
            deposit_chance_table_to_depot(pos, inv, count, drops)
            return
        end
        local out_name = HAUNTING_DIRECT_RECIPES[itemname]
        if out_name and core.registered_items[out_name] then
            deposit_processed_output(pos, inv, ItemStack(out_name .. " " .. count))
        end
        return
    end

    if catalyst == "freezing" then
        local out_name = FREEZING_RECIPES[itemname]
        if out_name and core.registered_items[out_name] then
            deposit_processed_output(pos, inv, ItemStack(out_name .. " " .. count))
            if string.find(itemname, "bucket_") and core.registered_items["mcl_buckets:bucket_empty"] then
                deposit_processed_output(pos, inv, ItemStack("mcl_buckets:bucket_empty " .. count))
            end
        end
        return
    end

    if (catalyst == "smoking" or catalyst == "blasting") and cooked_res and cooked_res.item then
        local out_name  = cooked_res.item:get_name()
        local total_out = cooked_res.item:get_count() * count
        deposit_processed_output(pos, inv, ItemStack(out_name .. " " .. total_out))
    end
end

local function catch_incoming_items_on_depot(pos, inv)
    if not CONFIG.CATCH_DROPPED_ITEMS then return false end

    local scan_pt = {x = pos.x, y = pos.y + CONFIG.DEPOT_TOP_Y + 0.15, z = pos.z}
    local objs    = core.get_objects_inside_radius(scan_pt, 0.72)
    local caught  = false

    for _, obj in ipairs(objs) do
        local luaent = obj:get_luaentity()
        if luaent and luaent.name == "__builtin:item" and
           not luaent._kinetica_vacuumed and
           luaent.itemstring and luaent.itemstring ~= "" then
            local opos = obj:get_pos()
            if opos and
               math.abs(opos.x - pos.x) <= 0.62 and
               math.abs(opos.z - pos.z) <= 0.62 and
               opos.y >= (pos.y - 0.15) and opos.y <= (pos.y + 0.85) then
                local istack   = ItemStack(luaent.itemstring)
                local orig_cnt = istack:get_count()
                local leftover = insert_onto_depot(inv, istack)

                if leftover:is_empty() then
                    luaent._kinetica_vacuumed = true
                    luaent._kinetica_on_belt  = false
                    luaent.itemstring         = ""
                    obj:remove()
                    caught = true
                elseif leftover:get_count() < orig_cnt then
                    luaent.itemstring = leftover:to_string()
                    caught = true
                end
            end
        end
    end
    return caught
end

local HORIZ_DIRS = {
    {x =  1, y = 0, z =  0},
    {x = -1, y = 0, z =  0},
    {x =  0, y = 0, z =  1},
    {x =  0, y = 0, z = -1},
}

local function get_belt_outgoing_move_dir(bnode)
    if not kinetica.is_belt or not kinetica.is_belt(bnode.name) then
        return nil
    end
    if bnode.name == "kinetica:belt" or
       bnode.name == "kinetica:belt_ns" or
       string.find(bnode.name, "_idle", 1, true) or
       string.find(bnode.name, "sideways", 1, true) then
        return nil
    end

    local d     = core.facedir_to_dir((bnode.param2 or 0) % 4) or {x = 0, y = 0, z = 1}
    local fwd   = {x = -d.x, y = 0, z = -d.z}
    local tsign = string.find(bnode.name, "_rev", 1, true) and -1 or 1
    return {x = fwd.x * tsign, y = 0, z = fwd.z * tsign}
end

local function try_eject_to_outgoing_belt(pos, inv, can_eject_main)
    if not CONFIG.AUTO_EJECT_TO_OUTGOING_BELT then return false end

    local target_list = nil
    local target_idx  = nil
    local stack       = nil

    for i = 1, OUTPUT_SLOTS do
        local s = inv:get_stack("output", i)
        if not s:is_empty() then
            stack       = s
            target_list = "output"
            target_idx  = i
            break
        end
    end

    if not stack and can_eject_main then
        local ms = inv:get_stack("main", 1)
        if not ms:is_empty() then
            stack       = ms
            target_list = "main"
            target_idx  = 1
        end
    end

    if not stack or stack:is_empty() then
        return false
    end

    for _, d in ipairs(HORIZ_DIRS) do
        local bpos  = {x = pos.x + d.x, y = pos.y, z = pos.z + d.z}
        local bnode = core.get_node(bpos)
        local mdir  = get_belt_outgoing_move_dir(bnode)

        if mdir and mdir.x == d.x and mdir.z == d.z then
            local belt_top = {x = bpos.x, y = bpos.y + CONFIG.DEPOT_TOP_Y + 0.08, z = bpos.z}
            local crowded  = false
            for _, obj in ipairs(core.get_objects_inside_radius(belt_top, 0.45)) do
                local lent = obj:get_luaentity()
                if lent and lent.name == "__builtin:item" then
                    crowded = true
                    break
                end
            end

            if not crowded then
                local eject_cnt   = math.min(stack:get_count(), CONFIG.BELT_EJECT_BATCH_SIZE)
                local eject_stack = stack:peek_item(eject_cnt)
                local obj         = core.add_item(belt_top, eject_stack)
                if obj then
                    stack:take_item(eject_cnt)
                    inv:set_stack(target_list, target_idx, stack)
                    return true
                end
            end
        end
    end
    return false
end

local function update_depot_infotext(meta, inv, catalyst, pct, is_pull)
    local disp_stack = get_displayed_stack(inv)
    if disp_stack:is_empty() then
        if catalyst and not is_pull then
            meta:set_string("infotext", string.format("Depot: Empty [Fan Stream: %s]", string.upper(catalyst)))
        else
            meta:set_string("infotext", "Depot: Empty (Right-Click or use Chute/Belt to place items)")
        end
        return
    end

    local iname = disp_stack:get_name()
    local idef  = core.registered_items[iname]
    local desc  = (idef and idef.description) and string.match(idef.description, "^[^\n]+") or iname

    local total_cnt = 0
    for _, lname in ipairs({"input", "main", "output"}) do
        for i = 1, inv:get_size(lname) do
            local s = inv:get_stack(lname, i)
            if not s:is_empty() then
                total_cnt = total_cnt + s:get_count()
            end
        end
    end

    if not is_pull and catalyst and pct and pct > 0 then
        meta:set_string("infotext", string.format(
            "Depot: %s x%d [%s %d%%]",
            desc, total_cnt, string.upper(catalyst), pct
        ))
    elseif not is_pull and catalyst then
        meta:set_string("infotext", string.format(
            "Depot: %s x%d [Fan Stream: %s]",
            desc, total_cnt, string.upper(catalyst)
        ))
    else
        meta:set_string("infotext", string.format("Depot: %s x%d", desc, total_cnt))
    end
end

local function depot_timer(pos, elapsed)
    local meta = core.get_meta(pos)
    local inv  = ensure_depot_inventory(meta)

    local changed = catch_incoming_items_on_depot(pos, inv)

    local has_fan, catalyst, rpm, is_pull = find_fan_catalyst_on_depot(pos)
    local held, slot_list = get_active_hold_stack(inv)
    local is_processing   = false
    local pct             = 0

    if CONFIG.ENABLE_FAN_PROCESSING and has_fan and not is_pull and catalyst and not held:is_empty() then
        local can_proc, cooked_res = can_item_be_processed(held:get_name(), catalyst)
        if can_proc then
            is_processing = true
            if slot_list ~= "input" then
                inv:set_stack("input", 1, held)
                inv:set_stack("main",  1, ItemStack(""))
            end

            local prev_cat  = meta:get_string("proc_cat")
            local prev_item = meta:get_string("proc_item")
            local prog      = meta:get_float("proc_time")

            if prev_cat ~= catalyst or prev_item ~= held:get_name() then
                prog = 0
                meta:set_string("proc_cat", catalyst)
                meta:set_string("proc_item", held:get_name())
            end

            prog = prog + CONFIG.TICK_INTERVAL
            local req_time = get_process_time(rpm, held:get_count())

            if prog >= req_time then
                meta:set_float("proc_time", 0)
                complete_depot_processing(pos, inv, held, catalyst, cooked_res)
                changed = true
                pct = 100
            else
                meta:set_float("proc_time", prog)
                pct = math.min(99, math.floor((prog / math.max(0.05, req_time)) * 100))
            end
        end
    end

    if not is_processing then
        meta:set_float("proc_time", 0)
        local in_s = inv:get_stack("input", 1)
        if not in_s:is_empty() then
            local leftover = inv:add_item("main", in_s)
            inv:set_stack("input", 1, leftover)
        end
    else
        spawn_depot_item_reaction_particles(pos, catalyst)
    end

    if try_eject_to_outgoing_belt(pos, inv, not is_processing) then
        changed = true
    end

    sync_depot_visual_entity(pos, inv)
    update_depot_infotext(meta, inv, catalyst, pct, is_pull)
    if changed then
        notify_comparators(pos)
    end

    core.get_node_timer(pos):start(CONFIG.TICK_INTERVAL)
    return false
end

local function give_or_drop_to_player(pos, player, stack)
    if not stack or stack:is_empty() then return end
    local pinv = player and player:get_inventory()
    if pinv then
        local leftover = pinv:add_item("main", stack)
        if not leftover:is_empty() then
            core.add_item({x = pos.x, y = pos.y + 0.5, z = pos.z}, leftover)
        end
    else
        core.add_item({x = pos.x, y = pos.y + 0.5, z = pos.z}, stack)
    end
end

local function extract_all_from_depot_to_player(pos, inv, player, single_item_only)
    local took_any = false

    for i = 1, OUTPUT_SLOTS do
        local s = inv:get_stack("output", i)
        if not s:is_empty() then
            if single_item_only then
                give_or_drop_to_player(pos, player, s:peek_item(1))
                s:take_item(1)
                inv:set_stack("output", i, s)
                return true
            else
                give_or_drop_to_player(pos, player, s)
                inv:set_stack("output", i, ItemStack(""))
                took_any = true
            end
        end
    end

    for _, lname in ipairs({"main", "input"}) do
        local s = inv:get_stack(lname, 1)
        if not s:is_empty() then
            if single_item_only then
                give_or_drop_to_player(pos, player, s:peek_item(1))
                s:take_item(1)
                inv:set_stack(lname, 1, s)
                return true
            else
                give_or_drop_to_player(pos, player, s)
                inv:set_stack(lname, 1, ItemStack(""))
                took_any = true
            end
        end
    end

    return took_any
end

local function on_depot_rightclick(pos, node, clicker, itemstack, pointed_thing)
    if not clicker or not clicker:is_player() then
        return itemstack
    end
    local pname = clicker:get_player_name()
    if core.is_protected(pos, pname) then
        return itemstack
    end

    local meta     = core.get_meta(pos)
    local inv      = ensure_depot_inventory(meta)
    local sneaking = clicker:get_player_control().sneak

    if not itemstack or itemstack:is_empty() then
        if extract_all_from_depot_to_player(pos, inv, clicker, sneaking) then
            core.sound_play("default_place_node_hard", {pos = pos, max_hear_distance = 10, gain = 0.4}, true)
            sync_depot_visual_entity(pos, inv)
            update_depot_infotext(meta, inv, nil, 0, false)
            notify_comparators(pos)
        end
        return itemstack
    end

    local held, slot_list = get_active_hold_stack(inv)
    if held:is_empty() and inv:is_empty("output") then
        inv:set_stack("main", 1, ItemStack(itemstack))
        if not core.is_creative_enabled(pname) then
            itemstack:clear()
        end
    elseif not held:is_empty() and held:get_name() == itemstack:get_name() then
        local leftover = held:add_item(itemstack)
        inv:set_stack(slot_list, 1, held)
        if not core.is_creative_enabled(pname) then
            itemstack = leftover
        end
    else
        extract_all_from_depot_to_player(pos, inv, clicker, false)
        inv:set_stack("main", 1, ItemStack(itemstack))
        if not core.is_creative_enabled(pname) then
            itemstack:clear()
        end
    end

    core.sound_play("default_place_node_hard", {pos = pos, max_hear_distance = 10, gain = 0.5}, true)
    sync_depot_visual_entity(pos, inv)
    update_depot_infotext(meta, inv, nil, 0, false)
    notify_comparators(pos)

    local timer = core.get_node_timer(pos)
    if not timer:is_started() then
        timer:start(CONFIG.TICK_INTERVAL)
    end

    return itemstack
end

local function on_hopper_in(hopper_pos, to_pos)
    local h_inv  = core.get_meta(hopper_pos):get_inventory()
    local d_meta = core.get_meta(to_pos)
    local d_inv  = ensure_depot_inventory(d_meta)

    for i = 1, h_inv:get_size("main") do
        local stack = h_inv:get_stack("main", i)
        if not stack:is_empty() then
            local single   = stack:peek_item(1)
            local leftover = insert_onto_depot(d_inv, single)
            if leftover:is_empty() then
                stack:take_item(1)
                h_inv:set_stack("main", i, stack)
                sync_depot_visual_entity(to_pos, d_inv)
                notify_comparators(to_pos)
                return true
            end
        end
    end
    return false
end

local function on_hopper_out(from_pos, to_hopper_pos)
    local d_meta = core.get_meta(from_pos)
    local d_inv  = ensure_depot_inventory(d_meta)
    local h_inv  = core.get_meta(to_hopper_pos):get_inventory()

    for i = 1, OUTPUT_SLOTS do
        local out_s = d_inv:get_stack("output", i)
        if not out_s:is_empty() then
            local single = out_s:peek_item(1)
            if h_inv:room_for_item("main", single) then
                h_inv:add_item("main", single)
                out_s:take_item(1)
                d_inv:set_stack("output", i, out_s)
                sync_depot_visual_entity(from_pos, d_inv)
                notify_comparators(from_pos)
                return true
            end
        end
    end

    local main_s = d_inv:get_stack("main", 1)
    if not main_s:is_empty() then
        local single = main_s:peek_item(1)
        if h_inv:room_for_item("main", single) then
            h_inv:add_item("main", single)
            main_s:take_item(1)
            d_inv:set_stack("main", 1, main_s)
            sync_depot_visual_entity(from_pos, d_inv)
            notify_comparators(from_pos)
            return true
        end
    end
    return false
end

local DEPOT_NODEBOX = {
    type  = "fixed",
    fixed = {
        {-8/16, -8/16, -8/16,  8/16,  1/16,  8/16},
        {-7/16,  1/16, -7/16,  7/16,  2/16,  7/16},
        {-8/16,  2/16, -8/16,  8/16,  4/16,  8/16},
    },
}

local DEPOT_SELECTION_BOX = {
    type  = "fixed",
    fixed = {-8/16, -8/16, -8/16, 8/16, 4/16, 8/16},
}

core.register_node(DEPOT_NAME, {
    description = "Depot (Holds Items for Encased Fan Bulk Processing, Chutes & Mechanical Belts)",
    drawtype = "nodebox",
    node_box = DEPOT_NODEBOX,
    collision_box = DEPOT_SELECTION_BOX,
    selection_box = DEPOT_SELECTION_BOX,
    tiles = get_depot_tiles(),
    paramtype = "light",
    sunlight_propagates = true,
    use_texture_alpha = "clip",
    is_ground_content = false,

    groups = {
        handy = 1,
        pickaxey = 1,
        axey = 1,
        container = 2,
        kinetica_depot = 1,
        depot = 1,
    },

    _mcl_hardness = 2.0,
    _mcl_blast_resistance = 3.0,
    sounds = mcl_sounds and mcl_sounds.node_sound_stone_defaults and mcl_sounds.node_sound_stone_defaults() or nil,

    on_construct = function(pos)
        local meta = core.get_meta(pos)
        local inv  = ensure_depot_inventory(meta)
        update_depot_infotext(meta, inv, nil, 0, false)
        core.get_node_timer(pos):start(CONFIG.TICK_INTERVAL)
    end,

    on_rightclick = on_depot_rightclick,

    after_dig_node = function(pos, oldnode, oldmetadata, digger)
        remove_depot_visual_entity(pos)
        if oldmetadata and oldmetadata.inventory then
            for _, listname in ipairs({"input", "main", "output"}) do
                local list = oldmetadata.inventory[listname]
                if list then
                    for _, item in ipairs(list) do
                        local st = ItemStack(item)
                        if not st:is_empty() then
                            core.add_item(pos, st)
                        end
                    end
                end
            end
        end
        notify_comparators(pos)
    end,

    on_timer = depot_timer,
    _on_hopper_in = on_hopper_in,
    _on_hopper_out = on_hopper_out,
})

core.register_lbm({
    label             = "Wake kinetica Depots on chunk load",
    name              = "kinetica:wake_depots_lbm",
    nodenames         = {DEPOT_NAME},
    run_at_every_load = true,
    action = function(pos, node)
        local meta = core.get_meta(pos)
        local inv  = ensure_depot_inventory(meta)
        sync_depot_visual_entity(pos, inv)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TICK_INTERVAL)
        end
    end,
})

core.register_craft({
    output = "kinetica:depot",
    recipe = {
        {"kinetica:andesite_alloy"},
        {"kinetica:andesite_casing"},
    },
})