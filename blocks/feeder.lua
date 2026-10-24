kinetica = kinetica or {}

local CONFIG = {
    FRONT_FACES_PLAYER        = false,
    ALLOW_VERTICAL_PLACEMENT  = false,
    MIN_RPM                   = 4,
    KU_PER_RPM                = 4,
    MIN_KU                    = 16,
    MAX_KU                    = 64,
    MAX_RPM_CAP               = 1024,
    CYCLE_SEC_AT_5_RPM        = 1.0,
    CYCLE_SEC_AT_512_RPM      = 0.20,
    BACK_ANIM_TIERS = {
        { name = "crawl",  max_rpm = 5,    length = 0.85 },
        { name = "slow",   max_rpm = 15,   length = 0.48 },
        { name = "medium", max_rpm = 63,   length = 0.24 },
        { name = "fast",   max_rpm = 255,  length = 0.11 },
        { name = "hyper",  max_rpm = 1024, length = 0.05 },
    },
    PROFIT_SLOTS              = 2,
    DAMAGE_HOE_ON_TILL        = true,
    AUTO_COLLECT_HARVEST      = true,
    PLANT_THROUGH_SAW         = true,
    ZONE_HALF_WIDTH           = 1.65,
    ZONE_HALF_HEIGHT          = 1.65,
    ZONE_DEPTH_MIN            = 0.20,
    ZONE_DEPTH_MAX            = 3.65,
    LOVE_DURATION_SEC         = 30.0,
    MATE_DELAY_SEC            = 1.5,
    BREED_COOLDOWN_SEC        = 45.0,
    ENABLE_GLASSES_HUD        = true,
    REGISTER_GLASSES_ITEM     = true,
    REQUIRE_GLASSES_FOR_HUD   = true,
    HIDE_INFOTEXT_WITHOUT_GLASSES = true,
    HUD_SCAN_INTERVAL         = 0.20,
    HUD_REACH_DISTANCE        = 8.0,
    HUD_POS_X                 = 0.015,
    HUD_POS_Y                 = 0.45,
    HUD_TEXT_COLOR            = 0x00E676,
    GLASSES_ITEM_NAMES = {
        ["kinetica:glasses"] = true,
        ["kinetica:goggles"] = true,
    },
    UI_COLORS = {
        BG_WINDOW          = "#14171D",
        BG_HEADER          = "#1F242D",
        BG_CARD            = "#1B2028",
        BG_INV_PANEL       = "#171B22",
        ACCENT_ACTIVE      = "#00E676",
        ACCENT_IDLE        = "#F5B041",
        ACCENT_HOE         = "#00D4FF",
        ACCENT_SEED        = "#2ECC71",
        ACCENT_PROFIT      = "#FFB300",
        TEXT_TITLE         = "#F5B041",
        TEXT_SUBTITLE      = "#ABB2B9",
        TEXT_LABEL         = "#95A5A6",
        TEXT_VALUE         = "#FFFFFF",
        TEXT_OK            = "#00E676",
        TEXT_IDLE          = "#F39C12",
        BTN_CLEAR_BG       = "#3D2323",
        BTN_CLEAR_TXT      = "#FF8A80",
    },
    TEX_FRONT                 = "kinetica_feeder_front.png",
    TEX_SIDE                  = "kinetica_feeder_side.png",
    TEX_TOP                   = "kinetica_feeder_side.png",
    TEX_BOTTOM                = "kinetica_feeder_side.png",
    TEX_BACK                  = "kinetica_feeder_side.png",
    TEX_SHAFT_OVERLAY         = "kinetica_shaft_connecting_overlay.png",
}

local IDLE_NAME    = "kinetica:feeder"
local PROFIT_SLOTS = CONFIG.PROFIT_SLOTS or 2

local function is_feeder_node(name)
    if not name then return false end
    return name == IDLE_NAME or string.sub(name, 1, #IDLE_NAME + 1) == (IDLE_NAME .. "_")
end
kinetica.is_feeder = is_feeder_node

local function get_feeder_demand_ku(rpm)
    if not rpm or rpm < CONFIG.MIN_RPM then
        return CONFIG.MIN_KU
    end
    return math.min(CONFIG.MAX_KU, math.max(CONFIG.MIN_KU, math.floor(rpm * CONFIG.KU_PER_RPM)))
end

local function get_cycle_interval(rpm)
    if not rpm or rpm <= 0 then return CONFIG.CYCLE_SEC_AT_5_RPM end
    local t = math.min(1.0, math.max(0.0, (rpm - 5) / (512 - 5)))
    return CONFIG.CYCLE_SEC_AT_5_RPM - t * (CONFIG.CYCLE_SEC_AT_5_RPM - CONFIG.CYCLE_SEC_AT_512_RPM)
end

local function get_back_dir(param2)
    local d = core.facedir_to_dir(param2 or 0) or {x = 0, y = 0, z = 1}
    return {x = d.x, y = d.y, z = d.z}
end

local function get_front_dir(param2)
    local b = get_back_dir(param2)
    return {x = -b.x, y = -b.y, z = -b.z}
end

local function is_pos_in_front_3x3(feeder_pos, front_dir, target_pos, extra_margin)
    local m = extra_margin or 0
    local rel = {
        x = target_pos.x - feeder_pos.x,
        y = target_pos.y - feeder_pos.y,
        z = target_pos.z - feeder_pos.z,
    }

    local forward = rel.x * front_dir.x + rel.y * front_dir.y + rel.z * front_dir.z
    if forward < (CONFIG.ZONE_DEPTH_MIN - m) or forward > (CONFIG.ZONE_DEPTH_MAX + m) then
        return false
    end

    if front_dir.y == 0 then
        local right = math.abs(rel.x * front_dir.z - rel.z * front_dir.x)
        local up    = math.abs(rel.y)
        return (right <= CONFIG.ZONE_HALF_WIDTH + m) and (up <= CONFIG.ZONE_HALF_HEIGHT + m)
    else
        return (math.abs(rel.x) <= CONFIG.ZONE_HALF_WIDTH + m) and
               (math.abs(rel.z) <= CONFIG.ZONE_HALF_WIDTH + m)
    end
end

local HOE_MATERIAL_USES = {
    wood      = 60,
    gold      = 33,
    stone     = 132,
    iron      = 251,
    diamond   = 1562,
    netherite = 2032,
}

local function is_hoe_item(item_name)
    if not item_name or item_name == "" then return false end
    return core.get_item_group(item_name, "hoe") > 0 or string.find(item_name, ":hoe_") ~= nil
end

local function has_valid_hoe_in_slot(inv)
    if not inv or inv:get_size("hoe") < 1 then
        return false, ItemStack("")
    end
    local hoe_stack = inv:get_stack("hoe", 1)
    if hoe_stack:is_empty() then
        return false, ItemStack("")
    end
    local hoe_name = hoe_stack:get_name()
    if not is_hoe_item(hoe_name) then
        return false, ItemStack("")
    end
    return true, hoe_stack
end

local function get_hoe_max_uses(hoe_name)
    local def = core.registered_items[hoe_name]
    if def then
        if type(def._mcl_uses) == "number" and def._mcl_uses > 0 then
            return def._mcl_uses
        end
        if def.tool_capabilities and def.tool_capabilities.groupcaps then
            for _, gcap in pairs(def.tool_capabilities.groupcaps) do
                if type(gcap.uses) == "number" and gcap.uses > 0 then
                    return gcap.uses
                end
            end
        end
    end
    for mat, uses in pairs(HOE_MATERIAL_USES) do
        if string.find(hoe_name, mat) then
            return uses
        end
    end
    return 251
end

local function damage_hoe_in_slot(inv, pos)
    if not CONFIG.DAMAGE_HOE_ON_TILL then return end
    local has_hoe, hoe_stack = has_valid_hoe_in_slot(inv)
    if not has_hoe then return end

    local unbreaking = 0
    if mcl_enchanting and type(mcl_enchanting.get_enchantment) == "function" then
        unbreaking = mcl_enchanting.get_enchantment(hoe_stack, "unbreaking") or 0
    end
    if unbreaking > 0 and math.random(1, unbreaking + 1) > 1 then
        return
    end

    local uses      = get_hoe_max_uses(hoe_stack:get_name())
    local wear_step = math.max(1, math.ceil(65535 / math.max(1, uses)))
    hoe_stack:add_wear(wear_step)

    if hoe_stack:is_empty() then
        core.sound_play("default_tool_breaks", {pos = pos, max_hear_distance = 12, gain = 0.8}, true)
    end
    inv:set_stack("hoe", 1, hoe_stack)
end

local function ensure_feeder_inventory(meta)
    local inv = meta:get_inventory()
    if inv:get_size("hoe") ~= 1 then
        inv:set_size("hoe", 1)
    end
    if inv:get_size("seed") ~= 1 then
        inv:set_size("seed", 1)
    end
    if inv:get_size("profit") ~= PROFIT_SLOTS then
        inv:set_size("profit", PROFIT_SLOTS)
    end
    return inv
end

local function sync_seed_filter(meta, inv)
    local s1 = inv:get_stack("seed", 1)
    if not s1:is_empty() and not is_hoe_item(s1:get_name()) then
        meta:set_string("seed_filter", s1:get_name())
    end
end

local function rebalance_seed_bank(meta, inv)
    sync_seed_filter(meta, inv)
    local s1     = inv:get_stack("seed", 1)
    local wanted = not s1:is_empty() and s1:get_name() or meta:get_string("seed_filter")
    if wanted == "" then
        return
    end

    for i = 1, PROFIT_SLOTS do
        local p_stack = inv:get_stack("profit", i)
        if not p_stack:is_empty() and p_stack:get_name() == wanted then
            local max_stack = p_stack:get_stack_max()
            local cur_count = s1:is_empty() and 0 or s1:get_count()
            local need      = max_stack - cur_count
            if need <= 0 then
                break
            end

            local move_count = math.min(need, p_stack:get_count())
            if move_count > 0 then
                local moved = p_stack:peek_item(move_count)
                if s1:is_empty() then
                    s1 = moved
                else
                    s1:set_count(cur_count + move_count)
                end
                inv:set_stack("seed", 1, s1)
                p_stack:take_item(move_count)
                inv:set_stack("profit", i, p_stack)
            end
        end
    end
end

local function insert_vacuumed_stack(meta, inv, stack)
    if not stack or stack:is_empty() then
        return ItemStack("")
    end

    sync_seed_filter(meta, inv)
    local s1     = inv:get_stack("seed", 1)
    local wanted = not s1:is_empty() and s1:get_name() or meta:get_string("seed_filter")
    local remaining = ItemStack(stack)

    if wanted ~= "" and remaining:get_name() == wanted and not is_hoe_item(wanted) then
        local max_s1 = remaining:get_stack_max()
        local cur_s1 = s1:is_empty() and 0 or s1:get_count()
        if cur_s1 < max_s1 then
            remaining = inv:add_item("seed", remaining)
        end
    end

    if not remaining:is_empty() then
        remaining = inv:add_item("profit", remaining)
    end

    rebalance_seed_bank(meta, inv)
    return remaining
end

local function format_slot_summary(stack)
    if not stack or stack:is_empty() then
        return "Empty"
    end
    local iname = stack:get_name()
    local idef  = core.registered_items[iname]
    local desc  = (idef and idef.description) and string.match(idef.description, "^[^\n]+") or iname
    return string.format("%s x%d", desc, stack:get_count())
end

local function C(hex, text)
    return core.colorize(hex, tostring(text))
end

local function get_feeder_formspec(meta)
    local U           = CONFIG.UI_COLORS
    local status_line = C(U.TEXT_IDLE, "IDLE — Connect Rotating Shaft to Back or Push with Piston")
    local bar_color   = U.ACCENT_IDLE
    local seed_filter = ""
    local rpm         = 0
    local demand_ku   = CONFIG.MIN_KU
    local avail_ku    = 0
    local supply_ku   = 0

    if meta then
        rpm         = meta:get_float("rpm")
        supply_ku   = meta:get_int("network_supply_ku")
        avail_ku    = meta:get_int("rotational_power")
        demand_ku   = meta:get_int("machine_demand_ku")
        if demand_ku <= 0 then demand_ku = get_feeder_demand_ku(rpm) end
        seed_filter = meta:get_string("seed_filter")

        if supply_ku > 0 and rpm >= CONFIG.MIN_RPM then
            bar_color   = U.ACCENT_ACTIVE
            status_line = C(U.TEXT_OK, string.format(
                "ACTIVE — %.0f RPM  |  -%d KU Load  |  %d / %d KU Network Pool",
                rpm, demand_ku, avail_ku, supply_ku
            ))
        end
    end

    local filter_desc = "Auto-Assigns to Slot 1"
    if seed_filter ~= "" then
        local idef = core.registered_items[seed_filter]
        filter_desc = (idef and idef.description) and string.match(idef.description, "^[^\n]+") or seed_filter
    end

    local slot_bg_hoe    = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(1.05, 1.95, 1, 1) or ""
    local slot_bg_seed   = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(4.15, 1.95, 1, 1) or ""
    local slot_bg_profit = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(6.95, 1.95, 2, 1) or ""
    local inv_bg_1       = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(0.4,  4.85, 9, 3) or ""
    local inv_bg_2       = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(0.4,  8.00, 9, 1) or ""

    local fs = {
        "size[9.8,9.1]",
        "bgcolor[" .. U.BG_WINDOW .. ";false]",
        "box[0,0;9.8,1.05;" .. U.BG_HEADER .. "]",
        "box[0,1.02;9.8,0.05;" .. bar_color .. "]",
        "label[0.3,0.12;" .. C(U.TEXT_TITLE, "MECHANICAL FEEDER, TREE PLANTER & HARVESTER") .. "]",
        "label[0.3,0.52;" .. status_line .. "]",
        "box[0.25,1.25;2.6,2.15;" .. U.BG_CARD .. "]",
        "box[0.25,1.25;0.07,2.15;" .. U.ACCENT_HOE .. "]",
        "label[0.45,1.35;" .. C(U.ACCENT_HOE, "HOE SLOT") .. "]",
        slot_bg_hoe,
        "list[context;hoe;1.05,1.95;1,1;]",
        "label[0.45,3.00;" .. C(U.TEXT_LABEL, "Tills Farmland") .. "]",
        "box[3.10,1.25;3.0,2.15;" .. U.BG_CARD .. "]",
        "box[3.10,1.25;0.07,2.15;" .. U.ACCENT_SEED .. "]",
        "label[3.30,1.35;" .. C(U.ACCENT_SEED, "SEED / SAPLING BANK") .. "]",
        slot_bg_seed,
        "list[context;seed;4.15,1.95;1,1;]",
        "label[3.30,3.00;" .. C(U.TEXT_LABEL, "Plants & Feeds (Locked)") .. "]",
        "box[6.35,1.25;3.2,2.15;" .. U.BG_CARD .. "]",
        "box[6.35,1.25;0.07,2.15;" .. U.ACCENT_PROFIT .. "]",
        "label[6.55,1.35;" .. C(U.ACCENT_PROFIT, "PROFIT BINS (2 SLOTS)") .. "]",
        slot_bg_profit,
        "list[context;profit;6.95,1.95;2,1;]",
        "label[6.55,3.00;" .. C(U.TEXT_LABEL, "Chute / Hopper Output") .. "]",
        "box[0.25,3.55;9.3,0.75;" .. U.BG_CARD .. "]",
        "label[0.45,3.73;" .. C(U.TEXT_LABEL, "Active Memory Filter:") .. " " .. C(U.TEXT_VALUE, filter_desc) .. "]",
        "style[clear_filter;bgcolor=" .. U.BTN_CLEAR_BG .. ";textcolor=" .. U.BTN_CLEAR_TXT .. "]",
        "button[7.35,3.60;2.05,0.65;clear_filter;Clear Memory]",
        "box[0.25,4.42;9.3,4.55;" .. U.BG_INV_PANEL .. "]",
        "label[0.40,4.45;" .. C(U.TEXT_SUBTITLE, "Player Inventory") .. "]",
        "list[current_player;main;0.4,4.85;9,3;9]",
        inv_bg_1,
        "list[current_player;main;0.4,8.00;9,1;]",
        inv_bg_2,
        "listring[current_player;main]",
        "listring[context;hoe]",
        "listring[current_player;main]",
        "listring[context;seed]",
        "listring[current_player;main]",
        "listring[context;profit]",
    }
    return table.concat(fs)
end

local function refresh_feeder_formspec(pos)
    local meta = core.get_meta(pos)
    meta:set_string("formspec", get_feeder_formspec(meta))
end

local FARMLAND_SOILS = {
    ["mcl_farming:soil"]     = true,
    ["mcl_farming:soil_wet"] = true,
}

local SOUL_SAND_SOILS = {
    ["mcl_nether:soul_sand"]     = true,
    ["mcl_blackstone:soul_soil"] = true,
}

local TREE_AND_BERRY_SOILS = {
    ["mcl_core:dirt"]                 = true,
    ["mcl_core:dirt_with_grass"]      = true,
    ["mcl_core:dirt_with_grass_snow"] = true,
    ["mcl_core:podzol"]               = true,
    ["mcl_core:coarse_dirt"]          = true,
    ["mcl_core:mycelium"]             = true,
    ["mcl_mud:mud"]                   = true,
    ["mcl_mangrove:muddy_mangrove_roots"] = true,
    ["mcl_lush_caves:moss"]           = true,
    ["mcl_farming:soil"]              = true,
    ["mcl_farming:soil_wet"]          = true,
}

local FUNGUS_SOILS = {
    ["mcl_crimson:crimson_nylium"]    = true,
    ["mcl_crimson:warped_nylium"]     = true,
    ["mcl_nether:soul_sand"]          = true,
    ["mcl_blackstone:soul_soil"]      = true,
    ["mcl_core:dirt"]                 = true,
    ["mcl_core:dirt_with_grass"]      = true,
    ["mcl_core:podzol"]               = true,
    ["mcl_core:mycelium"]             = true,
}

local SEED_TO_CROP = {
    ["mcl_farming:wheat_seeds"]       = {node = "mcl_farming:wheat_1",                soils = FARMLAND_SOILS,       is_tree = false},
    ["mcl_farming:carrot_item"]       = {node = "mcl_farming:carrot_1",               soils = FARMLAND_SOILS,       is_tree = false},
    ["mcl_farming:potato_item"]       = {node = "mcl_farming:potato_1",               soils = FARMLAND_SOILS,       is_tree = false},
    ["mcl_farming:beetroot_seeds"]    = {node = "mcl_farming:beetroot_0",             soils = FARMLAND_SOILS,       is_tree = false},
    ["mcl_farming:pumpkin_seeds"]     = {node = "mcl_farming:pumpkin_1",              soils = FARMLAND_SOILS,       is_tree = false},
    ["mcl_farming:melon_seeds"]       = {node = "mcl_farming:melontige_1",            soils = FARMLAND_SOILS,       is_tree = false},
    ["mcl_farming:torchflower_seeds"] = {node = "mcl_farming:torchflower_1",          soils = FARMLAND_SOILS,       is_tree = false},
    ["mcl_farming:pitcher_pod"]       = {node = "mcl_farming:pitcher_crop_1",         soils = FARMLAND_SOILS,       is_tree = false},
    ["mcl_nether:nether_wart_item"]   = {node = "mcl_nether:nether_wart_0",           soils = SOUL_SAND_SOILS,      is_tree = false},
    ["mcl_sweet_berry:sweet_berries"] = {node = "mcl_sweet_berry:sweet_berry_bush_0", soils = TREE_AND_BERRY_SOILS, is_tree = true},

    ["mcl_core:sapling"]                  = {node = "mcl_core:sapling",                  soils = TREE_AND_BERRY_SOILS, is_tree = true},
    ["mcl_core:sprucesapling"]            = {node = "mcl_core:sprucesapling",            soils = TREE_AND_BERRY_SOILS, is_tree = true},
    ["mcl_core:birchsapling"]             = {node = "mcl_core:birchsapling",             soils = TREE_AND_BERRY_SOILS, is_tree = true},
    ["mcl_core:junglesapling"]            = {node = "mcl_core:junglesapling",            soils = TREE_AND_BERRY_SOILS, is_tree = true},
    ["mcl_core:acaciasapling"]            = {node = "mcl_core:acaciasapling",            soils = TREE_AND_BERRY_SOILS, is_tree = true},
    ["mcl_core:darksapling"]              = {node = "mcl_core:darksapling",              soils = TREE_AND_BERRY_SOILS, is_tree = true},
    ["mcl_mangrove:propagule"]            = {node = "mcl_mangrove:propagule",            soils = TREE_AND_BERRY_SOILS, is_tree = true},
    ["mcl_cherry_blossom:cherrysapling"]  = {node = "mcl_cherry_blossom:cherrysapling",  soils = TREE_AND_BERRY_SOILS, is_tree = true},
    ["mcl_crimson:crimson_fungus"]        = {node = "mcl_crimson:crimson_fungus",        soils = FUNGUS_SOILS,         is_tree = true},
    ["mcl_crimson:warped_fungus"]         = {node = "mcl_crimson:warped_fungus",         soils = FUNGUS_SOILS,         is_tree = true},
    ["mcl_bamboo:bamboo"]                 = {node = "mcl_bamboo:bamboo",                 soils = TREE_AND_BERRY_SOILS, is_tree = true},
}

local function get_plantable_entry(item_name)
    if not item_name or item_name == "" then
        return nil
    end
    if SEED_TO_CROP[item_name] then
        return SEED_TO_CROP[item_name]
    end
    if (core.get_item_group(item_name, "sapling") > 0 or
        string.find(item_name, "sapling") or
        string.find(item_name, "propagule")) and
       core.registered_nodes[item_name] then
        return {
            node    = item_name,
            soils   = TREE_AND_BERRY_SOILS,
            is_tree = true,
        }
    end
    return nil
end

local MATURE_CROPS = {
    ["mcl_farming:wheat"]                  = true,
    ["mcl_farming:carrot"]                 = true,
    ["mcl_farming:potato"]                 = true,
    ["mcl_farming:beetroot"]               = true,
    ["mcl_nether:nether_wart"]             = true,
    ["mcl_sweet_berry:sweet_berry_bush_3"] = true,
    ["mcl_farming:pumpkin"]                = true,
    ["mcl_farming:pumpkin_face"]           = true,
    ["mcl_farming:melon"]                  = true,
    ["mcl_farming:torchflower"]            = true,
    ["mcl_farming:pitcher_plant"]          = true,
}

core.register_on_mods_loaded(function()
    if mcl_farming and type(mcl_farming.plant_lists) == "table" then
        for _, pdata in pairs(mcl_farming.plant_lists) do
            if pdata.full_grown then
                MATURE_CROPS[pdata.full_grown] = true
            end
        end
    end
end)

local function is_mature_crop(node_name)
    if not node_name or node_name == "air" or node_name == "ignore" then
        return false
    end
    return MATURE_CROPS[node_name] == true
end

local function is_tillable_dirt(node_name)
    if not node_name or node_name == "air" or FARMLAND_SOILS[node_name] then
        return false
    end
    if node_name == "mcl_core:dirt" or
       node_name == "mcl_core:dirt_with_grass" or
       node_name == "mcl_core:dirt_with_grass_snow" or
       node_name == "mcl_core:grass_path" or
       node_name == "mcl_core:dirt_path" or
       node_name == "mcl_core:coarse_dirt" then
        return true
    end
    if core.get_item_group(node_name, "cultivatable") > 0 then
        return true
    end
    local def = core.registered_nodes[node_name]
    if def and def._on_hoe_place then
        return true
    end
    return false
end

local function is_valid_soil_for_seed(soil_name, seed_entry)
    if not soil_name or not seed_entry then return false end
    if seed_entry.soils and seed_entry.soils[soil_name] then
        return true
    end
    if seed_entry.is_tree and (core.get_item_group(soil_name, "soil") > 0 or core.get_item_group(soil_name, "dirt") > 0) then
        return true
    end
    if seed_entry.soils == FARMLAND_SOILS and core.get_item_group(soil_name, "soil") >= 2 then
        return true
    end
    return false
end

local function is_mechanical_saw_node(node_name)
    if not node_name or node_name == "air" then
        return false
    end
    return string.find(node_name, "mechanical_saw", 1, true) ~= nil
end

local function resolve_front_farm_positions(pos, front_dir)
    local step1_pos  = {x = pos.x + front_dir.x, y = pos.y + front_dir.y, z = pos.z + front_dir.z}
    local step1_node = core.get_node(step1_pos)
    local step1_up   = core.get_node({x = step1_pos.x, y = step1_pos.y + 1, z = step1_pos.z})

    local target_pos = step1_pos
    if CONFIG.PLANT_THROUGH_SAW and (is_mechanical_saw_node(step1_node.name) or is_mechanical_saw_node(step1_up.name)) then
        target_pos = {
            x = pos.x + front_dir.x * 2,
            y = pos.y + front_dir.y * 2,
            z = pos.z + front_dir.z * 2,
        }
    end

    local target_node = core.get_node(target_pos)
    local above_pos   = {x = target_pos.x, y = target_pos.y + 1, z = target_pos.z}
    local below_pos   = {x = target_pos.x, y = target_pos.y - 1, z = target_pos.z}

    if FARMLAND_SOILS[target_node.name] or
       SOUL_SAND_SOILS[target_node.name] or
       TREE_AND_BERRY_SOILS[target_node.name] or
       is_tillable_dirt(target_node.name) or
       core.get_item_group(target_node.name, "soil") >= 1 or
       core.get_item_group(target_node.name, "dirt") >= 1 then
        return target_pos, above_pos
    end
    return below_pos, target_pos
end

local ANIMAL_FOODS = {
    ["mobs_mc:cow"] = {
        ["mcl_farming:wheat_item"] = true,
        ["mcl_farming:wheat"]      = true,
    },
    ["mobs_mc:mooshroom"] = {
        ["mcl_farming:wheat_item"] = true,
        ["mcl_farming:wheat"]      = true,
    },
    ["mobs_mc:sheep"] = {
        ["mcl_farming:wheat_item"] = true,
        ["mcl_farming:wheat"]      = true,
    },
    ["mobs_mc:pig"] = {
        ["mcl_farming:carrot_item"]   = true,
        ["mcl_farming:potato_item"]   = true,
        ["mcl_farming:beetroot_item"] = true,
        ["mcl_farming:carrot"]        = true,
        ["mcl_farming:potato"]        = true,
        ["mcl_farming:beetroot"]      = true,
    },
    ["mobs_mc:chicken"] = {
        ["mcl_farming:wheat_seeds"]       = true,
        ["mcl_farming:beetroot_seeds"]    = true,
        ["mcl_farming:pumpkin_seeds"]     = true,
        ["mcl_farming:melon_seeds"]       = true,
        ["mcl_farming:torchflower_seeds"] = true,
        ["mcl_farming:pitcher_pod"]       = true,
    },
    ["mobs_mc:rabbit"] = {
        ["mcl_farming:carrot_item"]      = true,
        ["mcl_farming:carrot_item_gold"] = true,
        ["mcl_flowers:dandelion"]        = true,
    },
}

local function does_animal_eat_item(luaent, item_name)
    if not luaent or not item_name or item_name == "" then
        return false
    end

    local food_map = ANIMAL_FOODS[luaent.name]
    if food_map and food_map[item_name] then
        return true
    end

    if type(luaent.follow) == "string" then
        return luaent.follow == item_name
    elseif type(luaent.follow) == "table" then
        for _, f in ipairs(luaent.follow) do
            if f == item_name then
                return true
            end
        end
    end
    return false
end

local function spawn_heart_particles(apos, count, duration)
    if not apos then return end
    core.add_particlespawner({
        amount     = count or 6,
        time       = duration or 0.6,
        minpos     = {x = apos.x - 0.35, y = apos.y + 0.45, z = apos.z - 0.35},
        maxpos     = {x = apos.x + 0.35, y = apos.y + 0.95, z = apos.z + 0.35},
        minvel     = {x = -0.2, y = 0.35, z = -0.2},
        maxvel     = {x =  0.2, y = 0.85, z =  0.2},
        minexptime = 0.5,
        maxexptime = 1.0,
        minsize    = 1.6,
        maxsize    = 2.6,
        texture    = "heart.png",
    })
end

local function is_valid_adult_animal(luaent)
    if not luaent then return false end
    if not (luaent.is_mob or luaent._cmi_is_mob or ANIMAL_FOODS[luaent.name]) then
        return false
    end
    if (luaent.health and luaent.health <= 0) or luaent.child == true then
        return false
    end
    return (ANIMAL_FOODS[luaent.name] ~= nil) or (luaent.follow ~= nil)
end

local function is_animal_in_love(luaent, now_sec)
    if not is_valid_adult_animal(luaent) then return false end
    if luaent._kinetica_breed_cooldown_until and now_sec < luaent._kinetica_breed_cooldown_until then
        return false
    end
    if luaent._kinetica_love_until and now_sec < luaent._kinetica_love_until then
        return true
    end
    return false
end

local function can_animal_be_fed(luaent, now_sec)
    if not is_valid_adult_animal(luaent) then return false end
    if is_animal_in_love(luaent, now_sec) then return false end
    if luaent._kinetica_breed_cooldown_until and now_sec < luaent._kinetica_breed_cooldown_until then
        return false
    end
    if luaent.horny == true then
        return false
    end
    return true
end

local function enter_animal_love_mode(obj, luaent, now_sec)
    luaent._kinetica_love_until   = now_sec + CONFIG.LOVE_DURATION_SEC
    luaent._kinetica_love_started = now_sec
    luaent._kinetica_mating_lock  = false
    luaent.tamed                  = true
    luaent.persistent             = true
    luaent.horny                  = false
    luaent.hornytimer             = 0

    local apos = obj:get_pos()
    if apos then
        spawn_heart_particles(apos, 7, 0.7)
        core.sound_play("default_place_node_hard", {pos = apos, max_hear_distance = 12, gain = 0.4}, true)
    end
end

local function steer_mates_together(objA, luaentA, objB, luaentB)
    local posA = objA and objA:get_pos()
    local posB = objB and objB:get_pos()
    if not posA or not posB then return end

    local dx   = posB.x - posA.x
    local dz   = posB.z - posA.z
    local dist = math.sqrt(dx * dx + dz * dz)

    if dist > 0.75 then
        local nx = dx / dist
        local nz = dz / dist
        local speed = 1.2
        local velA = objA:get_velocity() or {x = 0, y = 0, z = 0}
        local velB = objB:get_velocity() or {x = 0, y = 0, z = 0}

        objA:set_velocity({x = nx * speed, y = velA.y, z = nz * speed})
        objB:set_velocity({x = -nx * speed, y = velB.y, z = -nz * speed})

        if objA.set_yaw then objA:set_yaw(math.atan2(dz, dx) - math.pi / 2) end
        if objB.set_yaw then objB:set_yaw(math.atan2(-dz, -dx) - math.pi / 2) end
    end
end

local function spawn_baby_between_parents(objA, luaentA, objB, luaentB)
    local posA = objA and objA:get_pos()
    local posB = objB and objB:get_pos()
    if not posA or not posB then return false end
    if not luaentA or not luaentB then return false end

    local now_sec  = core.get_gametime() or 0
    local mob_name = luaentA.name
    local mid_pos  = {
        x = (posA.x + posB.x) * 0.5,
        y = math.max(posA.y, posB.y) + 0.1,
        z = (posA.z + posB.z) * 0.5,
    }

    luaentA._kinetica_love_until           = 0
    luaentB._kinetica_love_until           = 0
    luaentA._kinetica_mating_lock          = false
    luaentB._kinetica_mating_lock          = false
    luaentA._kinetica_breed_cooldown_until = now_sec + CONFIG.BREED_COOLDOWN_SEC
    luaentB._kinetica_breed_cooldown_until = now_sec + CONFIG.BREED_COOLDOWN_SEC
    luaentA.horny                          = false
    luaentB.horny                          = false
    luaentA.hornytimer                     = 31
    luaentB.hornytimer                     = 31

    local child_obj = nil

    if mcl_mobs and type(mcl_mobs.add_child) == "function" then
        child_obj = mcl_mobs.add_child(mid_pos, mob_name)
    elseif mobs and type(mobs.add_child) == "function" then
        child_obj = mobs:add_child(mid_pos, mob_name)
    end

    if not child_obj then
        local staticdata = core.serialize({
            child      = true,
            tamed      = true,
            persistent = true,
            owner      = luaentA.owner or "",
        })
        child_obj = core.add_entity(mid_pos, mob_name, staticdata)
    end

    if child_obj then
        local child_ent = child_obj:get_luaentity()
        if child_ent then
            child_ent.child      = true
            child_ent.tamed      = true
            child_ent.persistent = true

            local parent_props = objA:get_properties()
            local child_props  = child_obj:get_properties()
            if parent_props and child_props and parent_props.visual_size and child_props.visual_size then
                if child_props.visual_size.x >= parent_props.visual_size.x * 0.85 then
                    local new_vs = {
                        x = parent_props.visual_size.x * 0.5,
                        y = parent_props.visual_size.y * 0.5,
                        z = (parent_props.visual_size.z or parent_props.visual_size.x) * 0.5,
                    }
                    local new_cb = nil
                    if parent_props.collisionbox then
                        new_cb = {}
                        for i = 1, 6 do
                            new_cb[i] = parent_props.collisionbox[i] * 0.5
                        end
                    end
                    child_obj:set_properties({
                        visual_size  = new_vs,
                        collisionbox = new_cb or child_props.collisionbox,
                    })
                end
            end

            if child_ent.color == nil and luaentA.color ~= nil then
                child_ent.color = (math.random(1, 2) == 1) and luaentA.color or (luaentB.color or luaentA.color)
            end
            if type(luaentA.on_breed) == "function" then
                pcall(luaentA.on_breed, luaentA, luaentB, child_obj)
            end
        end
    end

    spawn_heart_particles(mid_pos, 14, 1.0)
    core.sound_play("default_place_node", {pos = mid_pos, max_hear_distance = 12, gain = 0.7}, true)
    if mcl_experience and type(mcl_experience.throw_xp) == "function" then
        pcall(mcl_experience.throw_xp, mid_pos, math.random(1, 5))
    end

    return true
end

local function process_love_pairs_in_zone(pos, front, objs, now_sec)
    local by_species = {}

    for _, obj in ipairs(objs) do
        local opos = obj:get_pos()
        if opos and is_pos_in_front_3x3(pos, front, opos, 0.65) then
            local luaent = obj:get_luaentity()
            if luaent and is_animal_in_love(luaent, now_sec) then
                spawn_heart_particles(opos, 4, 0.6)
                if not luaent._kinetica_mating_lock then
                    local sp = luaent.name
                    by_species[sp] = by_species[sp] or {}
                    table.insert(by_species[sp], {obj = obj, luaent = luaent})
                end
            end
        end
    end

    local bred_any = false
    for _, list in pairs(by_species) do
        local i = 1
        while i + 1 <= #list do
            local a = list[i]
            local b = list[i + 1]
            i = i + 2

            a.luaent._kinetica_mating_lock = true
            b.luaent._kinetica_mating_lock = true
            steer_mates_together(a.obj, a.luaent, b.obj, b.luaent)

            core.after(CONFIG.MATE_DELAY_SEC * 0.5, function()
                if a.obj:get_pos() and b.obj:get_pos() then
                    steer_mates_together(a.obj, a.luaent, b.obj, b.luaent)
                    spawn_heart_particles(a.obj:get_pos(), 5, 0.5)
                    spawn_heart_particles(b.obj:get_pos(), 5, 0.5)
                end
            end)

            core.after(CONFIG.MATE_DELAY_SEC, function()
                if a.obj:get_pos() and b.obj:get_pos() then
                    spawn_baby_between_parents(a.obj, a.luaent, b.obj, b.luaent)
                else
                    if a.luaent then a.luaent._kinetica_mating_lock = false end
                    if b.luaent then b.luaent._kinetica_mating_lock = false end
                end
            end)
            bred_any = true
        end
    end
    return bred_any
end

local function execute_feeder_cycle(pos, node, is_piston_move)
    node = node or core.get_node(pos)
    if not is_feeder_node(node.name) then return "" end

    local meta  = core.get_meta(pos)
    local inv   = ensure_feeder_inventory(meta)
    local owner = meta:get_string("owner")
    local front = get_front_dir(node.param2)

    rebalance_seed_bank(meta, inv)

    local actions_done = {}
    local soil_pos, crop_pos = resolve_front_farm_positions(pos, front)
    local can_edit_soil = not core.is_protected(soil_pos, owner)
    local can_edit_crop = not core.is_protected(crop_pos, owner)

    local crop_node = core.get_node(crop_pos)
    if can_edit_crop and is_mature_crop(crop_node.name) then
        if crop_node.name == "mcl_sweet_berry:sweet_berry_bush_3" then
            core.swap_node(crop_pos, {name = "mcl_sweet_berry:sweet_berry_bush_1", param2 = crop_node.param2})
            local berry_drop = ItemStack("mcl_sweet_berry:sweet_berries " .. math.random(2, 3))
            local leftover = CONFIG.AUTO_COLLECT_HARVEST and insert_vacuumed_stack(meta, inv, berry_drop) or berry_drop
            if not leftover:is_empty() then
                core.add_item(crop_pos, leftover)
            end
            actions_done[#actions_done + 1] = "Harvested"
        else
            local drops = core.get_node_drops(crop_node, "")
            core.remove_node(crop_pos)
            core.sound_play("default_dig_snappy", {pos = crop_pos, max_hear_distance = 12, gain = 0.6}, true)

            for _, itemstr in ipairs(drops) do
                local dstack = ItemStack(itemstr)
                local leftover = CONFIG.AUTO_COLLECT_HARVEST and insert_vacuumed_stack(meta, inv, dstack) or dstack
                if not leftover:is_empty() then
                    core.add_item(crop_pos, leftover)
                end
            end
            actions_done[#actions_done + 1] = "Harvested"
        end
        crop_node = core.get_node(crop_pos)
    end

    local soil_node      = core.get_node(soil_pos)
    local has_hoe, _     = has_valid_hoe_in_slot(inv)
    local s1_check       = inv:get_stack("seed", 1)
    local s1_entry       = get_plantable_entry(not s1_check:is_empty() and s1_check:get_name() or meta:get_string("seed_filter"))
    local holding_sapling= (s1_entry and s1_entry.is_tree) or false

    if can_edit_soil and has_hoe and not holding_sapling and is_tillable_dirt(soil_node.name) then
        local above_soil_pos  = {x = soil_pos.x, y = soil_pos.y + 1, z = soil_pos.z}
        local above_soil_node = core.get_node(above_soil_pos)
        local above_def       = core.registered_nodes[above_soil_node.name]

        if above_soil_node.name == "air" or (above_def and above_def.buildable_to and core.get_item_group(above_soil_node.name, "liquid") == 0) then
            if above_soil_node.name ~= "air" and can_edit_crop then
                local g_drops = core.get_node_drops(above_soil_node, "")
                core.remove_node(above_soil_pos)
                for _, itemstr in ipairs(g_drops) do
                    local dstack = ItemStack(itemstr)
                    local leftover = CONFIG.AUTO_COLLECT_HARVEST and insert_vacuumed_stack(meta, inv, dstack) or dstack
                    if not leftover:is_empty() then
                        core.add_item(above_soil_pos, leftover)
                    end
                end
            end

            if core.registered_nodes["mcl_farming:soil"] then
                damage_hoe_in_slot(inv, pos)
                core.set_node(soil_pos, {name = "mcl_farming:soil", param2 = 0})
                soil_node = core.get_node(soil_pos)
                core.sound_play("default_dig_crumbly", {pos = soil_pos, max_hear_distance = 12, gain = 0.6}, true)
                actions_done[#actions_done + 1] = "Tilled"
            end
        end
    end

    rebalance_seed_bank(meta, inv)
    local s1_stack = inv:get_stack("seed", 1)
    crop_node      = core.get_node(crop_pos)
    soil_node      = core.get_node(soil_pos)

    local crop_def = core.registered_nodes[crop_node.name]
    local can_replace_crop_air = (crop_node.name == "air") or
        (crop_def and crop_def.buildable_to and core.get_item_group(crop_node.name, "liquid") == 0)

    if can_edit_crop and not s1_stack:is_empty() and can_replace_crop_air then
        local seed_name  = s1_stack:get_name()
        local seed_entry = get_plantable_entry(seed_name)

        if seed_entry and core.registered_nodes[seed_entry.node] and
           is_valid_soil_for_seed(soil_node.name, seed_entry) then
            local plant_def = core.registered_nodes[seed_entry.node]
            local plant_p2  = (plant_def and plant_def.place_param2) or 0

            core.set_node(crop_pos, {name = seed_entry.node, param2 = plant_p2})
            s1_stack:take_item(1)
            inv:set_stack("seed", 1, s1_stack)
            rebalance_seed_bank(meta, inv)

            core.sound_play("default_place_node", {pos = crop_pos, max_hear_distance = 12, gain = 0.5}, true)
            actions_done[#actions_done + 1] = seed_entry.is_tree and "Planted Tree" or "Planted"
        end
    end

    local scan_center = {
        x = pos.x + front.x * 1.85,
        y = pos.y + front.y * 1.85,
        z = pos.z + front.z * 1.85,
    }
    local objs    = core.get_objects_inside_radius(scan_center, 3.6)
    local now_sec = core.get_gametime() or 0
    local fed_any = false
    local vac_any = false

    for _, obj in ipairs(objs) do
        local opos = obj:get_pos()
        if opos and is_pos_in_front_3x3(pos, front, opos, 0) then
            local luaent = obj:get_luaentity()

            if luaent then
                if luaent.name == "__builtin:item" and not luaent._kinetica_vacuumed and
                   luaent.itemstring and luaent.itemstring ~= "" then
                    local istack   = ItemStack(luaent.itemstring)
                    local orig_cnt = istack:get_count()
                    local leftover = insert_vacuumed_stack(meta, inv, istack)

                    if leftover:is_empty() then
                        luaent._kinetica_vacuumed = true
                        obj:remove()
                        vac_any = true
                    elseif leftover:get_count() < orig_cnt then
                        if luaent.set_item then
                            luaent:set_item(leftover:to_string())
                        else
                            luaent.itemstring = leftover:to_string()
                        end
                        vac_any = true
                    end

                elseif can_animal_be_fed(luaent, now_sec) then
                    rebalance_seed_bank(meta, inv)
                    s1_stack = inv:get_stack("seed", 1)
                    if not s1_stack:is_empty() and does_animal_eat_item(luaent, s1_stack:get_name()) then
                        s1_stack:take_item(1)
                        inv:set_stack("seed", 1, s1_stack)
                        rebalance_seed_bank(meta, inv)
                        enter_animal_love_mode(obj, luaent, now_sec)
                        fed_any = true
                    end
                end
            end
        end
    end

    local bred_pair = process_love_pairs_in_zone(pos, front, objs, now_sec)

    if bred_pair then
        actions_done[#actions_done + 1] = "Bred Animals"
    elseif fed_any then
        actions_done[#actions_done + 1] = "Fed Animal"
    end
    if vac_any then
        actions_done[#actions_done + 1] = "Vacuumed"
    end

    refresh_feeder_formspec(pos)
    return table.concat(actions_done, " + ")
end

local moved_step_guard = {}

if mcl_pistons and mcl_pistons.register_on_move then
    mcl_pistons.register_on_move(function(moved_nodes)
        local now_us = core.get_us_time()
        for _, moved in ipairs(moved_nodes) do
            if moved.node and is_feeder_node(moved.node.name) then
                local dest = {x = moved.pos.x, y = moved.pos.y, z = moved.pos.z}
                local hkey = core.hash_node_position(dest)
                if not moved_step_guard[hkey] or (now_us - moved_step_guard[hkey]) > 50000 then
                    moved_step_guard[hkey] = now_us
                    core.after(0, function()
                        local cur_node = core.get_node(dest)
                        if is_feeder_node(cur_node.name) then
                            execute_feeder_cycle(dest, cur_node, true)
                        end
                    end)
                end
            end
        end
    end)
end

local function look_to_unit_dir(placer, allow_vertical)
    local look = placer and placer:get_look_dir() or {x = 0, y = 0, z = 1}
    local ax, ay, az = math.abs(look.x), math.abs(look.y), math.abs(look.z)
    if allow_vertical and ay > ax and ay > az then
        return {x = 0, y = (look.y > 0) and 1 or -1, z = 0}
    elseif ax >= az then
        return {x = (look.x > 0) and 1 or -1, y = 0, z = 0}
    else
        return {x = 0, y = 0, z = (look.z > 0) and 1 or -1}
    end
end

local function place_feeder(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then
        return itemstack
    end

    local under_pos  = pointed_thing.under
    local above_pos  = pointed_thing.above
    local under_node = core.get_node(under_pos)
    local under_def  = core.registered_nodes[under_node.name]
    local sneaking   = placer and placer:is_player() and placer:get_player_control().sneak

    if under_def and under_def.on_rightclick and not sneaking then
        return under_def.on_rightclick(under_pos, under_node, placer, itemstack, pointed_thing) or itemstack
    end

    local diff = {
        x = above_pos.x - under_pos.x,
        y = above_pos.y - under_pos.y,
        z = above_pos.z - under_pos.z,
    }

    local front_dir = nil

    if not sneaking then
        if (kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(under_node.name)) or
           under_node.name == "kinetica:piston_head" or
           under_node.name == "kinetica:piston_head_sticky" or
           (kinetica.is_sticky_contraption_frame and kinetica.is_sticky_contraption_frame(under_node.name)) or
           (kinetica.has_axle_port and kinetica.has_axle_port(under_node, diff)) then
            if CONFIG.ALLOW_VERTICAL_PLACEMENT or diff.y == 0 then
                front_dir = diff
            end
        end
    end

    if not front_dir then
        local ldir = look_to_unit_dir(placer, CONFIG.ALLOW_VERTICAL_PLACEMENT)
        local invert = CONFIG.FRONT_FACES_PLAYER
        if sneaking then invert = not invert end
        if invert then
            front_dir = {x = -ldir.x, y = -ldir.y, z = -ldir.z}
        else
            front_dir = ldir
        end
    end

    local back_dir = {x = -front_dir.x, y = -front_dir.y, z = -front_dir.z}
    local param2   = core.dir_to_facedir(back_dir, CONFIG.ALLOW_VERTICAL_PLACEMENT)
    local placed_stack, place_pos = core.item_place_node(itemstack, placer, pointed_thing, param2)

    if place_pos then
        local meta  = core.get_meta(place_pos)
        local owner = placer and placer.get_player_name and placer:get_player_name() or ""
        meta:set_string("owner", (owner ~= "") and owner or "$unknown")
    end

    return placed_stack
end

local function make_feeder_back_idle()
    return "[combine:16x16:0,0=" .. CONFIG.TEX_BACK .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY
end

local function make_feeder_back_anim(reverse, anim_length)
    local bg = CONFIG.TEX_BACK
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
            length   = anim_length or 0.4,
        },
    }
end

local back_idle = make_feeder_back_idle()

local function get_back_anim_tier_name(rpm)
    local clamped = math.min(CONFIG.MAX_RPM_CAP, math.max(0, rpm or 0))
    for _, tier in ipairs(CONFIG.BACK_ANIM_TIERS) do
        if clamped <= tier.max_rpm then
            return tier.name
        end
    end
    return CONFIG.BACK_ANIM_TIERS[#CONFIG.BACK_ANIM_TIERS].name
end

local function get_active_feeder_node_name(param2, spin_dir, rpm)
    local back      = get_back_dir(param2)
    local axis_sign = back.x + back.y + back.z
    local vis       = ((spin_dir or 1) * axis_sign >= 0) and 1 or -1
    local dir_tag   = (vis == 1) and "cw" or "ccw"
    local tier_name = get_back_anim_tier_name(rpm)
    return IDLE_NAME .. "_" .. tier_name .. "_" .. dir_tag
end

local function update_feeder_hover_infotext(meta, is_active, action_str)
    if CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        meta:set_string("infotext", "")
        return
    end

    local inv        = ensure_feeder_inventory(meta)
    local has_hoe, _ = has_valid_hoe_in_slot(inv)
    local s1         = inv:get_stack("seed", 1)
    local p1         = inv:get_stack("profit", 1)
    local p2         = inv:get_stack("profit", 2)
    local p_total    = p1:get_count() + p2:get_count()

    if not is_active then
        meta:set_string("infotext", string.format(
            "Mechanical Feeder: Idle [Hoe: %s | Seed: %d | Profit: %d]",
            has_hoe and "Ready" or "None", s1:get_count(), p_total
        ))
    else
        local rpm       = meta:get_float("rpm")
        local demand_ku = meta:get_int("machine_demand_ku")
        local act_tag   = (action_str and action_str ~= "") and (" [" .. action_str .. "]") or ""
        meta:set_string("infotext", string.format(
            "Mechanical Feeder: Active%s [Seed: %d | Profit: %d | -%d KU @ %.0f RPM]",
            act_tag, s1:get_count(), p_total, demand_ku, rpm
        ))
    end
end

local function set_feeder_idle(pos, node, reason_text)
    node = node or core.get_node(pos)
    local meta = core.get_meta(pos)
    ensure_feeder_inventory(meta)

    meta:set_string("last_action", "Idle")
    update_feeder_hover_infotext(meta, false, "")

    if node.name ~= IDLE_NAME then
        core.swap_node(pos, {name = IDLE_NAME, param2 = node.param2})
    end
    refresh_feeder_formspec(pos)
end

local function wake_feeder(pos, node, rpm, spin_dir, demand_ku, avail_ku, supply_ku)
    node = node or core.get_node(pos)
    local target = get_active_feeder_node_name(node.param2, spin_dir, rpm)
    if node.name ~= target then
        core.swap_node(pos, {name = target, param2 = node.param2})
    end
    local timer = core.get_node_timer(pos)
    if not timer:is_started() then
        timer:start(get_cycle_interval(rpm))
    end
end

local function feeder_timer(pos, elapsed)
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
    if demand_ku <= 0 then demand_ku = get_feeder_demand_ku(rpm) end
    local spin_dir  = meta:get_int("spin_dir")

    if supply_ku <= 0 or rpm < CONFIG.MIN_RPM or now >= meta:get_int("lit_until") then
        set_feeder_idle(pos, node)
        return false
    end

    local target = get_active_feeder_node_name(node.param2, spin_dir, rpm)
    if node.name ~= target then
        core.swap_node(pos, {name = target, param2 = node.param2})
        node.name = target
    end

    local action_str = execute_feeder_cycle(pos, core.get_node(pos), false)
    if action_str ~= "" then
        meta:set_string("last_action", action_str)
    elseif meta:get_string("last_action") == "" or meta:get_string("last_action") == "Idle" then
        meta:set_string("last_action", "Scanning")
    end

    update_feeder_hover_infotext(meta, true, action_str)
    core.get_node_timer(pos):start(get_cycle_interval(rpm))
    return false
end

if kinetica.register_kinetic_machine then
    kinetica.register_kinetic_machine("kinetica:feeder", {
        can_ride_piston = true,
        get_demand_ku   = function(rpm, pos, node)
            return get_feeder_demand_ku(rpm)
        end,
        has_axle_port   = function(node, d)
            local back_dir = get_back_dir(node.param2)
            return (d.x == back_dir.x and d.y == back_dir.y and d.z == back_dir.z)
        end,
        should_pause_contraption = function(pos, node, move_dir)
            execute_feeder_cycle(pos, node, true)
            return false, nil
        end,
        set_idle = set_feeder_idle,
        wake     = wake_feeder,
    })
end

local function allow_put(pos, listname, index, stack, player)
    if player and player:is_player() and core.is_protected(pos, player:get_player_name()) then
        return 0
    end
    if listname == "hoe" then
        if is_hoe_item(stack:get_name()) then
            return stack:get_count()
        end
        return 0
    elseif listname == "seed" then
        if is_hoe_item(stack:get_name()) then
            return 0
        end
        return stack:get_count()
    elseif listname == "profit" then
        return stack:get_count()
    end
    return 0
end

local function allow_take(pos, listname, index, stack, player)
    if listname == "hoe" or listname == "seed" then
        if not (player and player:is_player()) then
            return 0
        end
    end
    if player and player:is_player() and core.is_protected(pos, player:get_player_name()) then
        return 0
    end
    return stack:get_count()
end

local function allow_move(pos, from_list, from_index, to_list, to_index, count, player)
    if player and player:is_player() and core.is_protected(pos, player:get_player_name()) then
        return 0
    end
    local inv   = core.get_meta(pos):get_inventory()
    local stack = inv:get_stack(from_list, from_index)
    if stack:is_empty() then return 0 end

    if to_list == "hoe" and not is_hoe_item(stack:get_name()) then
        return 0
    end
    if to_list == "seed" and is_hoe_item(stack:get_name()) then
        return 0
    end

    local dst = inv:get_stack(to_list, to_index)
    if not dst:is_empty() and dst:get_name() ~= stack:get_name() then
        return 0
    end
    local free = dst:is_empty() and stack:get_stack_max() or (dst:get_stack_max() - dst:get_count())
    return math.min(count, free)
end

local function on_inv_change(pos, listname, index, stack, player)
    local meta = core.get_meta(pos)
    local inv  = ensure_feeder_inventory(meta)
    if listname == "seed" then
        local s1 = inv:get_stack("seed", 1)
        if not s1:is_empty() and not is_hoe_item(s1:get_name()) then
            meta:set_string("seed_filter", s1:get_name())
        elseif player and player:is_player() then
            meta:set_string("seed_filter", "")
        end
    end
    rebalance_seed_bank(meta, inv)
    refresh_feeder_formspec(pos)
end

local function on_receive_fields(pos, formname, fields, sender)
    if fields.clear_filter then
        if sender and sender:is_player() and core.is_protected(pos, sender:get_player_name()) then
            return
        end
        local meta = core.get_meta(pos)
        local inv  = ensure_feeder_inventory(meta)
        local s1   = inv:get_stack("seed", 1)
        meta:set_string("seed_filter", s1:is_empty() and "" or s1:get_name())
        refresh_feeder_formspec(pos)
    end
end

local function on_hopper_in(hopper_pos, to_pos)
    local h_inv  = core.get_meta(hopper_pos):get_inventory()
    local f_meta = core.get_meta(to_pos)
    local f_inv  = ensure_feeder_inventory(f_meta)

    for i = 1, h_inv:get_size("main") do
        local stack = h_inv:get_stack("main", i)
        if not stack:is_empty() then
            local item_name = stack:get_name()
            if is_hoe_item(item_name) then
                if f_inv:get_stack("hoe", 1):is_empty() then
                    local moved_hoe = stack:peek_item(1)
                    f_inv:set_stack("hoe", 1, moved_hoe)
                    stack:take_item(1)
                    h_inv:set_stack("main", i, stack)
                    refresh_feeder_formspec(to_pos)
                    return true
                end
            else
                local single = stack:peek_item(1)
                local s1     = f_inv:get_stack("seed", 1)
                local filter = f_meta:get_string("seed_filter")

                if (s1:is_empty() and (filter == "" or filter == item_name)) or
                   (not s1:is_empty() and s1:get_name() == item_name and f_inv:room_for_item("seed", single)) then
                    f_inv:add_item("seed", single)
                    f_meta:set_string("seed_filter", item_name)
                    stack:take_item(1)
                    h_inv:set_stack("main", i, stack)
                    refresh_feeder_formspec(to_pos)
                    return true
                end

                if f_inv:room_for_item("profit", single) then
                    f_inv:add_item("profit", single)
                    stack:take_item(1)
                    h_inv:set_stack("main", i, stack)
                    refresh_feeder_formspec(to_pos)
                    return true
                end
            end
        end
    end
    return true
end

local function on_hopper_out(from_pos, to_hopper_pos)
    local f_meta = core.get_meta(from_pos)
    local f_inv  = ensure_feeder_inventory(f_meta)
    local h_inv  = core.get_meta(to_hopper_pos):get_inventory()

    for slot_idx = 1, PROFIT_SLOTS do
        local profit_stack = f_inv:get_stack("profit", slot_idx)
        if not profit_stack:is_empty() then
            local single = profit_stack:peek_item(1)
            if h_inv:room_for_item("main", single) then
                h_inv:add_item("main", single)
                profit_stack:take_item(1)
                f_inv:set_stack("profit", slot_idx, profit_stack)
                refresh_feeder_formspec(from_pos)
                return true
            end
        end
    end
    return true
end

local function on_feeder_after_dig(pos, oldnode, oldmetadata, digger)
    if oldmetadata and oldmetadata.inventory then
        for _, listname in ipairs({"hoe", "seed", "profit"}) do
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
    if kinetica.schedule_network_update then
        kinetica.schedule_network_update(pos)
    end
end

local base_groups   = {handy = 1, pickaxey = 1, axey = 1, container = 2, kinetic_receiver = 1, kinetica_feeder = 1}
local active_groups = {handy = 1, pickaxey = 1, axey = 1, container = 2, kinetic_receiver = 1, kinetica_feeder = 1, not_in_creative_inventory = 1}

local function register_feeder_variant(node_name, desc, back_tile, is_base)
    core.register_node(node_name, {
        description = desc,
        tiles = {
            CONFIG.TEX_TOP,
            CONFIG.TEX_BOTTOM,
            CONFIG.TEX_SIDE,
            CONFIG.TEX_SIDE,
            back_tile,
            CONFIG.TEX_FRONT,
        },
        paramtype2 = "facedir",
        is_ground_content = false,
        on_place = is_base and place_feeder or nil,
        drop = IDLE_NAME,
        groups = is_base and base_groups or active_groups,
        _mcl_hardness = 2.5,
        _mcl_blast_resistance = 3.0,
        sounds = mcl_sounds.node_sound_wood_defaults(),

        on_construct = is_base and function(pos)
            local meta = core.get_meta(pos)
            ensure_feeder_inventory(meta)
            set_feeder_idle(pos, core.get_node(pos))
            if kinetica.schedule_network_update then
                kinetica.schedule_network_update(pos)
            end
        end or nil,

        after_dig_node = on_feeder_after_dig,
        on_timer = feeder_timer,
        on_receive_fields = on_receive_fields,
        allow_metadata_inventory_put = allow_put,
        allow_metadata_inventory_take = allow_take,
        allow_metadata_inventory_move = allow_move,
        on_metadata_inventory_put = on_inv_change,
        on_metadata_inventory_take = on_inv_change,
        on_metadata_inventory_move = function(pos)
            local meta = core.get_meta(pos)
            local inv  = ensure_feeder_inventory(meta)
            rebalance_seed_bank(meta, inv)
            refresh_feeder_formspec(pos)
        end,
        _on_hopper_in = on_hopper_in,
        _on_hopper_out = on_hopper_out,
    })
end

register_feeder_variant(
    IDLE_NAME,
    "Mechanical Feeder (Plants Crops & Trees | 2 Profit Bins | 3x3 Breeder & Vacuum)",
    back_idle,
    true
)

for _, tier in ipairs(CONFIG.BACK_ANIM_TIERS) do
    local back_cw  = make_feeder_back_anim(false, tier.length)
    local back_ccw = make_feeder_back_anim(true,  tier.length)

    register_feeder_variant(
        IDLE_NAME .. "_" .. tier.name .. "_cw",
        "Mechanical Feeder",
        back_ccw,
        false
    )
    register_feeder_variant(
        IDLE_NAME .. "_" .. tier.name .. "_ccw",
        "Mechanical Feeder",
        back_cw,
        false
    )
end

core.register_alias("kinetica:feeder_active_cw",  IDLE_NAME .. "_medium_cw")
core.register_alias("kinetica:feeder_active_ccw", IDLE_NAME .. "_medium_ccw")

core.register_lbm({
    label             = "Upgrade kinetica Feeders to 2 Profit Bins",
    name              = "kinetica:upgrade_feeder_profit_bins_lbm",
    nodenames         = {"group:kinetica_feeder"},
    run_at_every_load = true,
    action = function(pos, node)
        local meta = core.get_meta(pos)
        ensure_feeder_inventory(meta)
        refresh_feeder_formspec(pos)
    end,
})

if CONFIG.REGISTER_GLASSES_ITEM and not core.registered_items["kinetica:glasses"] then
    core.register_craftitem("kinetica:glasses", {
        description     = "Kinetic Engineer's Glasses\nCarry in your hotbar/inventory or wield to view live machine stats on the left side of the screen.",
        inventory_image = "kinetica_shaft_connecting_overlay.png^[sheet:1x4:0,0^[colorize:#ffb300:140",
        wield_image     = "kinetica_shaft_connecting_overlay.png^[sheet:1x4:0,0^[colorize:#ffb300:140",
        stack_max       = 1,
    })

    core.register_craft({
        output = "kinetica:glasses",
        recipe = {
            {"mcl_core:glass", "mcl_core:gold_ingot", "mcl_core:glass"},
            {"",               "mcl_core:stick",      ""},
        },
    })
end

function kinetica.player_has_glasses(player)
    if not CONFIG.REQUIRE_GLASSES_FOR_HUD then
        return true
    end
    if not player or not player:is_player() then
        return false
    end

    local wield = player:get_wielded_item()
    if wield and CONFIG.GLASSES_ITEM_NAMES[wield:get_name()] then
        return true
    end

    local inv = player:get_inventory()
    if not inv then
        return false
    end

    for item_name, _ in pairs(CONFIG.GLASSES_ITEM_NAMES) do
        if inv:contains_item("main", item_name) or
           (inv:get_size("armor") > 0 and inv:contains_item("armor", item_name)) or
           (inv:get_size("offhand") > 0 and inv:contains_item("offhand", item_name)) then
            return true
        end
    end

    return false
end

local function build_glasses_telemetry_text(pos, node)
    local meta = core.get_meta(pos)

    if is_feeder_node(node.name) then
        local inv      = ensure_feeder_inventory(meta)
        local rpm      = meta:get_float("rpm")
        local supply   = meta:get_int("network_supply_ku")
        local avail    = meta:get_int("rotational_power")
        local demand   = meta:get_int("machine_demand_ku")
        if demand <= 0 then demand = get_feeder_demand_ku(rpm) end
        local active   = (supply > 0 and rpm >= CONFIG.MIN_RPM)
        local act_str  = meta:get_string("last_action")
        if act_str == "" then act_str = active and "Ready" or "Idle" end

        local hoe_s = inv:get_stack("hoe", 1)
        local s1    = inv:get_stack("seed", 1)
        local p1    = inv:get_stack("profit", 1)
        local p2    = inv:get_stack("profit", 2)

        return table.concat({
            "=== KINETIC GLASSES TELEMETRY ===",
            "Machine: Mechanical Feeder",
            string.format("State:   %s (%s)", active and "ACTIVE" or "IDLE", act_str),
            string.format("Speed:   %.1f RPM (Min %d RPM)", active and rpm or 0, CONFIG.MIN_RPM),
            string.format("Stress:  -%d KU Load  (%d / %d KU Avail)", active and demand or 0, avail, supply),
            "---------------------------------",
            "Hoe Slot:     " .. (hoe_s:is_empty() and "None" or "Equipped"),
            "Seed Bank:    " .. format_slot_summary(s1),
            "Profit Bin 1: " .. format_slot_summary(p1),
            "Profit Bin 2: " .. format_slot_summary(p2),
        }, "\n")
    end

    if string.sub(node.name or "", 1, 9) == "kinetica:" then
        local ndef   = core.registered_nodes[node.name]
        local title  = (ndef and ndef.description) and string.match(ndef.description, "^[^\n%(]+") or node.name
        local rpm    = meta:get_float("true_in_rpm")
        if rpm <= 0 then rpm = meta:get_float("rpm") end
        if rpm <= 0 then rpm = meta:get_float("source_rpm") end

        local supply = meta:get_int("true_in_supply_ku")
        if supply <= 0 then supply = meta:get_int("network_supply_ku") end
        if supply <= 0 then supply = meta:get_int("source_ku") end

        local avail  = meta:get_int("true_in_avail_ku")
        if avail <= 0 then avail = meta:get_int("rotational_power") end

        local demand = meta:get_int("machine_demand_ku")
        if demand <= 0 then demand = meta:get_int("piston_demand_ku") end

        return table.concat({
            "=== KINETIC GLASSES TELEMETRY ===",
            "Block:  " .. title,
            string.format("Speed:  %.1f RPM", rpm),
            string.format("Power:  %d / %d KU Avail (-%d KU Load)", avail, supply, demand),
        }, "\n")
    end
    return ""
end

local player_glasses_huds = {}
local hud_accum = 0

if CONFIG.ENABLE_GLASSES_HUD then
    core.register_on_leaveplayer(function(player)
        if player then
            player_glasses_huds[player:get_player_name()] = nil
        end
    end)

    core.register_globalstep(function(dtime)
        hud_accum = hud_accum + dtime
        if hud_accum < CONFIG.HUD_SCAN_INTERVAL then
            return
        end
        hud_accum = 0

        for _, player in ipairs(core.get_connected_players()) do
            local pname    = player:get_player_name()
            local hud_text = ""

            if kinetica.player_has_glasses(player) then
                local ppos  = player:get_pos()
                local props = player:get_properties()
                local eye_h = (props and props.eye_height) or 1.62
                local eye   = {x = ppos.x, y = ppos.y + eye_h, z = ppos.z}
                local look  = player:get_look_dir()
                local target = {
                    x = eye.x + look.x * CONFIG.HUD_REACH_DISTANCE,
                    y = eye.y + look.y * CONFIG.HUD_REACH_DISTANCE,
                    z = eye.z + look.z * CONFIG.HUD_REACH_DISTANCE,
                }

                local ray = core.raycast(eye, target, false, false)
                for pointed in ray do
                    if pointed.type == "node" and pointed.under then
                        local n = core.get_node(pointed.under)
                        if n.name ~= "air" then
                            hud_text = build_glasses_telemetry_text(pointed.under, n)
                            break
                        end
                    end
                end
            end

            local hud_info = player_glasses_huds[pname]
            if hud_text ~= "" then
                if not hud_info then
                    local id = player:hud_add({
                        hud_elem_type = "text",
                        position      = {x = CONFIG.HUD_POS_X, y = CONFIG.HUD_POS_Y},
                        alignment     = {x = 1, y = 0},
                        offset        = {x = 12, y = 0},
                        text          = hud_text,
                        number        = CONFIG.HUD_TEXT_COLOR,
                        scale         = {x = 100, y = 100},
                    })
                    player_glasses_huds[pname] = {id = id, last_text = hud_text}
                elseif hud_info.last_text ~= hud_text then
                    player:hud_change(hud_info.id, "text", hud_text)
                    hud_info.last_text = hud_text
                end
            elseif hud_info then
                player:hud_remove(hud_info.id)
                player_glasses_huds[pname] = nil
            end
        end
    end)
end

core.register_craft({
    output = "kinetica:feeder",
    recipe = {
        {"mcl_farming:hoe_iron", "mcl_chests:chest",           "mcl_hoppers:hopper"},
        {"kinetica:shaft",       "kinetica:andesite_casing",   ""},
    },
})