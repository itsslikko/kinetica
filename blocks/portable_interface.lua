kinetica = kinetica or {}

-- =========================================================
-- CUSTOMIZATION & CONFIGURATION HEADER
-- =========================================================
local CONFIG = {
    -- Timing & Range
    TICK_INTERVAL            = 0.50,  -- Seconds between radar/transfer ticks
    MAX_INTERFACE_GAP        = 2,     -- Max air blocks between two facing interfaces (1 or 2)
    BLIMP_SCAN_DIST          = 3.5,   -- How far in front of the nozzle to scan for a blimp
    BLIMP_SCAN_RADIUS        = 4.5,   -- Detection radius around the scan point for blimp hulls
    ITEMS_PER_TICK           = 8,     -- Max items moved per tick (Storage Interface)
    WATER_PER_TICK           = 2,     -- Max water units moved per tick (Fluid Interface)
    HOLD_EXTENDED_SECONDS    = 1.5,   -- Keep extended & locked this long after last item moves

    -- Visuals & Textures (Change these anytime!)
    TEX_BASE_CASING          = "kinetica_andisite_casing.png",
    TEX_ITEM_FRONT           = "portabal_transfer_nozel.png",
    TEX_FLUID_FRONT          = "portabal_fluid_transfer_nozel.png",

    -- Blimp Behavior Toggles
    BLIMP_AUTO_FUEL          = true,  -- Inject coal/wood directly into blimp furnace (_energy)
    BLIMP_AUTO_REPAIR        = true,  -- Use gold ingots/lumps to repair blimp hull (hp)
    BLIMP_AUTO_CARGO         = true,  -- Transfer items between dock storage and blimp trunk (_inv)
    BLIMP_AUTO_WATER         = true,  -- Fluid Interface: inject water into boiler (_water_level)
    FREE_WATER_FROM_PIPES    = true,  -- If true, adjacent water source or kinetica pipe fills boiler

    -- Future-Proof Storage Recognition (Chests, Vaults, Barrels, Shulkers)
    STORAGE_INV_LISTS        = {"main", "vault", "storage", "src", "dst"},
    VAULT_NODE_PATTERNS      = {
        "vault", "chest", "barrel", "shulker", "crate", "hopper", "depot", "chute"
    },
    FLUID_SOURCE_NODES       = {
        ["kinetica:fluid_pipe"]         = "pipe",
        ["kinetica:water_pump"]         = "pipe",
        ["mcl_core:water_source"]       = "infinite",
        ["default:water_source"]        = "infinite",
        ["default:river_water_source"]  = "infinite",
    },

    -- Target Blimp Entities
    BLIMP_ENTITIES = {
        ["steampunk_blimp:blimp"]           = true,
        ["steampunk_blimp:cannon_blimp"]    = true,
        ["steampunk_blimp:hsa"]             = true,
        ["steampunk_blimp:ephemeral_blimp"] = true,
    },

    -- Fallback Fuel/Water/Repair Tables (Used if steampunk_blimp globals aren't loaded yet)
    FALLBACK_FUEL = {
        ["default:coal_lump"]   = 1,
        ["default:coalblock"]   = 10,
        ["mcl_core:coal_lump"]  = 1,
        ["mcl_core:coalblock"]  = 10,
        ["mcl_core:charcoal"]   = 1,
    },
    FALLBACK_WATER = {
        ["bucket:bucket_water"]             = { amount = 1, empty = "bucket:bucket_empty" },
        ["bucket:bucket_river_water"]       = { amount = 1, empty = "bucket:bucket_empty" },
        ["mcl_buckets:bucket_water"]        = { amount = 1, empty = "mcl_buckets:bucket_empty" },
        ["mcl_buckets:bucket_river_water"]  = { amount = 1, empty = "mcl_buckets:bucket_empty" },
        ["default:water_source"]            = { amount = 1, empty = nil },
        ["mcl_core:water_source"]           = { amount = 1, empty = nil },
    },
    FALLBACK_REPAIR = {
        ["default:gold_lump"]   = 5,
        ["default:gold_ingot"]  = 10,
        ["mcl_core:gold_nugget"]= 1,
        ["mcl_core:gold_ingot"] = 10,
    },
}

-- =========================================================
-- NODE NAMES & DIRECTION MAPPING
-- =========================================================
local ITEM_BASE  = "kinetica:portable_storage_interface"
local ITEM_EXT   = "kinetica:portable_storage_interface_ext"
local FLUID_BASE = "kinetica:portable_fluid_interface"
local FLUID_EXT  = "kinetica:portable_fluid_interface_ext"

local raw_get_node  = core.get_node
local raw_swap_node = core.swap_node

local ALL_6_DIRS = kinetica.directions or {
    {x =  1, y =  0, z =  0},
    {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0},
    {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1},
    {x =  0, y =  0, z = -1},
}

-- Matches mechanical_piston.lua facedir convention (+Y local = front facing direction)
local AXIS_TO_PUSH_DIR = {
    [0] = {x =  0, y =  1, z =  0},
    [1] = {x =  0, y =  0, z =  1},
    [2] = {x =  0, y =  0, z = -1},
    [3] = {x =  1, y =  0, z =  0},
    [4] = {x = -1, y =  0, z =  0},
    [5] = {x =  0, y = -1, z =  0},
}

local MODE_NAMES = {
    [0] = "AUTO (Smart Balance / Blimp Refill)",
    [1] = "SEND ONLY (Push to Target / Blimp)",
    [2] = "RECEIVE ONLY (Pull from Target / Blimp)",
}

-- =========================================================
-- 3D NODEBOX SHAPES (RETRACTED & EXTENDED)
-- =========================================================
local INTERFACE_RETRACTED_NODEBOX = {
    type = "fixed",
    fixed = {
        {-8/16, -8/16, -8/16,  8/16,  2/16,  8/16}, -- Main Casing Base
        {-6/16,  2/16, -6/16,  6/16,  5/16,  6/16}, -- Middle Collar
        {-7/16,  5/16, -7/16,  7/16,  8/16,  7/16}, -- Retracted Docking Lip
    },
}

local INTERFACE_EXTENDED_NODEBOX = {
    type = "fixed",
    fixed = {
        {-8/16, -8/16, -8/16,  8/16,  2/16,  8/16}, -- Main Casing Base
        {-6/16,  2/16, -6/16,  6/16,  5/16,  6/16}, -- Middle Collar
        {-4/16,  5/16, -4/16,  4/16, 14/16,  4/16}, -- Extended Telescopic Bellows
        {-6/16, 14/16, -6/16,  6/16, 16/16,  6/16}, -- Extended Docking Clamp Ring
    },
}

local FULL_SELECTION_BOX = {
    type  = "fixed",
    fixed = {-8/16, -8/16, -8/16, 8/16, 8/16, 8/16},
}

-- =========================================================
-- HELPER FUNCTIONS: ORIENTATION & NODE IDENTIFICATION
-- =========================================================
local function get_facing_dir(param2)
    local axisdir = math.floor(((param2 or 0) % 24) / 4)
    local d = AXIS_TO_PUSH_DIR[axisdir] or AXIS_TO_PUSH_DIR[0]
    return {x = d.x, y = d.y, z = d.z}
end

local function dir_to_interface_param2(dir)
    local axisdir = 0
    if dir.y > 0 then axisdir = 0
    elseif dir.y < 0 then axisdir = 5
    elseif dir.z > 0 then axisdir = 1
    elseif dir.z < 0 then axisdir = 2
    elseif dir.x > 0 then axisdir = 3
    elseif dir.x < 0 then axisdir = 4
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

local function is_item_interface(name)
    return name == ITEM_BASE or name == ITEM_EXT
end

local function is_fluid_interface(name)
    return name == FLUID_BASE or name == FLUID_EXT
end

local function is_any_interface(name)
    return is_item_interface(name) or is_fluid_interface(name)
end
kinetica.is_portable_interface = is_any_interface

local function is_extended_variant(name)
    return name == ITEM_EXT or name == FLUID_EXT
end

local function set_interface_extended(pos, node, should_extend)
    local target_name
    if is_item_interface(node.name) then
        target_name = should_extend and ITEM_EXT or ITEM_BASE
    elseif is_fluid_interface(node.name) then
        target_name = should_extend and FLUID_EXT or FLUID_BASE
    else
        return
    end

    if node.name ~= target_name then
        raw_swap_node(pos, {name = target_name, param2 = node.param2})
        node.name = target_name
        core.sound_play("default_place_node_hard", {
            pos = pos,
            gain = 0.35,
            pitch = should_extend and 1.15 or 0.85,
            max_hear_distance = 12,
        }, true)
    end
end

-- =========================================================
-- STORAGE & VAULT DISCOVERY (BACK / SIDES / GLUED CLUSTER)
-- =========================================================
local function is_valid_storage_node(pos, node_name)
    if not node_name or node_name == "air" or node_name == "ignore" or is_any_interface(node_name) then
        return false, nil, nil
    end

    local meta = core.get_meta(pos)
    local inv  = meta and meta:get_inventory()
    if not inv then
        return false, nil, nil
    end

    for _, listname in ipairs(CONFIG.STORAGE_INV_LISTS) do
        local sz = inv:get_size(listname)
        if sz and sz > 0 then
            return true, inv, listname
        end
    end
    return false, nil, nil
end

local function get_connected_inventories(pos, node)
    local fdir      = get_facing_dir(node.param2)
    local candidate = {}
    local seen      = {[core.hash_node_position(pos)] = true}

    local back_pos = {x = pos.x - fdir.x, y = pos.y - fdir.y, z = pos.z - fdir.z}
    candidate[#candidate + 1] = back_pos
    seen[core.hash_node_position(back_pos)] = true

    for _, d in ipairs(ALL_6_DIRS) do
        if not (d.x == fdir.x and d.y == fdir.y and d.z == fdir.z) then
            local np = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
            local hk = core.hash_node_position(np)
            if not seen[hk] then
                seen[hk] = true
                candidate[#candidate + 1] = np
            end
        end
    end

    if kinetica.get_glued_cluster_positions then
        for _, gpos in ipairs(kinetica.get_glued_cluster_positions(pos)) do
            local hk = core.hash_node_position(gpos)
            if not seen[hk] then
                seen[hk] = true
                candidate[#candidate + 1] = gpos
            end
        end
    end

    local stores = {}
    local i = 1
    while i <= #candidate and #candidate <= 64 do
        local cpos  = candidate[i]
        i = i + 1
        local cnode = raw_get_node(cpos)
        local ok, inv, listname = is_valid_storage_node(cpos, cnode.name)
        if ok then
            stores[#stores + 1] = {pos = cpos, inv = inv, list = listname, name = cnode.name}

            if string.find(cnode.name, "vault") then
                for _, d in ipairs(ALL_6_DIRS) do
                    local vp = {x = cpos.x + d.x, y = cpos.y + d.y, z = cpos.z + d.z}
                    local hk = core.hash_node_position(vp)
                    if not seen[hk] and raw_get_node(vp).name == cnode.name then
                        seen[hk] = true
                        candidate[#candidate + 1] = vp
                    end
                end
            end
        end
    end

    return stores
end

local function count_total_items_in_stores(stores)
    local total = 0
    for _, st in ipairs(stores) do
        local sz = st.inv:get_size(st.list)
        for idx = 1, sz do
            local stack = st.inv:get_stack(st.list, idx)
            if not stack:is_empty() then
                total = total + stack:get_count()
            end
        end
    end
    return total
end

local function try_insert_into_stores(stores, stack)
    local leftover = ItemStack(stack)
    for _, st in ipairs(stores) do
        if st.inv:room_for_item(st.list, leftover) then
            leftover = st.inv:add_item(st.list, leftover)
            if leftover:is_empty() then
                return ItemStack("")
            end
        end
    end
    return leftover
end

-- =========================================================
-- STEAMPUNK BLIMP DETECTION & FUEL/WATER/CARGO LOGIC
-- =========================================================
local function get_fuel_value(item_name)
    if item_name == "" then return nil end
    if steampunk_blimp and steampunk_blimp.fuel and steampunk_blimp.fuel[item_name] then
        return steampunk_blimp.fuel[item_name].amount
    end
    if CONFIG.FALLBACK_FUEL[item_name] then
        return CONFIG.FALLBACK_FUEL[item_name]
    end
    if core.get_item_group(item_name, "tree") == 1 then
        return 4
    elseif core.get_item_group(item_name, "wood") == 1 then
        return 1
    end
    return nil
end

local function get_water_info(item_name)
    if item_name == "" then return nil end
    if CONFIG.FALLBACK_WATER[item_name] then
        return CONFIG.FALLBACK_WATER[item_name]
    end
    if steampunk_blimp and steampunk_blimp.water and steampunk_blimp.water[item_name] then
        local empty_bucket = nil
        if string.find(item_name, "mcl_buckets:bucket") then
            empty_bucket = "mcl_buckets:bucket_empty"
        elseif string.find(item_name, "bucket:bucket") then
            empty_bucket = "bucket:bucket_empty"
        end
        return {amount = steampunk_blimp.water[item_name].amount, empty = empty_bucket}
    end
    return nil
end

local function get_repair_value(item_name)
    if item_name == "" then return nil end
    if steampunk_blimp and steampunk_blimp.rep_material and steampunk_blimp.rep_material[item_name] then
        return steampunk_blimp.rep_material[item_name].amount
    end
    return CONFIG.FALLBACK_REPAIR[item_name]
end

local function find_nearby_blimp(pos, fdir)
    local scan_center = {
        x = pos.x + fdir.x * CONFIG.BLIMP_SCAN_DIST,
        y = pos.y + fdir.y * CONFIG.BLIMP_SCAN_DIST,
        z = pos.z + fdir.z * CONFIG.BLIMP_SCAN_DIST,
    }
    local objs = core.get_objects_inside_radius(scan_center, CONFIG.BLIMP_SCAN_RADIUS)
    for _, obj in ipairs(objs) do
        local ent = obj:get_luaentity()
        if ent and ent.name then
            if CONFIG.BLIMP_ENTITIES[ent.name] then
                return ent, obj
            end
            if string.find(ent.name, "^steampunk_blimp:") then
                local parent = obj:get_attach()
                local pent   = parent and parent:get_luaentity()
                if pent and CONFIG.BLIMP_ENTITIES[pent.name] then
                    return pent, parent
                end
            end
        end
    end
    return nil, nil
end

local function spawn_transfer_particles(pos_a, pos_b, is_fluid)
    local tex = is_fluid and "bubble.png" or CONFIG.TEX_BASE_CASING
    core.add_particlespawner({
        amount = 6,
        time = 0.25,
        minpos = pos_a,
        maxpos = pos_b,
        minvel = {x = -0.2, y = 0.1, z = -0.2},
        maxvel = {x =  0.2, y = 0.4, z =  0.2},
        minacc = {x = 0, y = 0, z = 0},
        maxacc = {x = 0, y = 0, z = 0},
        minexptime = 0.2,
        maxexptime = 0.4,
        minsize = 1.0,
        maxsize = 2.0,
        texture = tex,
    })
end

local function process_blimp_item_transfer(pos, node, meta, blimp_ent, blimp_obj)
    local stores   = get_connected_inventories(pos, node)
    local max_fuel = (steampunk_blimp and steampunk_blimp.MAX_FUEL) or 99
    local max_hp   = (steampunk_blimp and steampunk_blimp.max_hp)   or 50
    local mode     = meta:get_int("transfer_mode")
    local moved    = 0

    if mode == 0 or mode == 1 then
        for _, st in ipairs(stores) do
            local sz = st.inv:get_size(st.list)
            for idx = 1, sz do
                if moved >= CONFIG.ITEMS_PER_TICK then break end
                local stack = st.inv:get_stack(st.list, idx)
                if not stack:is_empty() then
                    local iname = stack:get_name()
                    local fval = CONFIG.BLIMP_AUTO_FUEL and get_fuel_value(iname)
                    if fval and (blimp_ent._energy or 0) < max_fuel then
                        while not stack:is_empty() and (blimp_ent._energy or 0) < max_fuel and moved < CONFIG.ITEMS_PER_TICK do
                            stack:take_item(1)
                            blimp_ent._energy = math.min(max_fuel, (blimp_ent._energy or 0) + fval)
                            moved = moved + 1
                        end
                        st.inv:set_stack(st.list, idx, stack)
                    else
                        local rval = CONFIG.BLIMP_AUTO_REPAIR and get_repair_value(iname)
                        if rval and (blimp_ent.hp or max_hp) < max_hp then
                            while not stack:is_empty() and (blimp_ent.hp or max_hp) < max_hp and moved < CONFIG.ITEMS_PER_TICK do
                                stack:take_item(1)
                                blimp_ent.hp = math.min(max_hp, (blimp_ent.hp or max_hp) + rval)
                                moved = moved + 1
                            end
                            st.inv:set_stack(st.list, idx, stack)
                            if steampunk_blimp and steampunk_blimp.setText then
                                pcall(steampunk_blimp.setText, blimp_ent, blimp_ent._vehicle_name or "Steampunk Blimp")
                            end
                        end
                    end
                end
            end
        end
    end

    local binv = blimp_ent._inv
    if CONFIG.BLIMP_AUTO_CARGO and binv and moved < CONFIG.ITEMS_PER_TICK then
        if mode == 1 then
            for _, st in ipairs(stores) do
                local sz = st.inv:get_size(st.list)
                for idx = 1, sz do
                    if moved >= CONFIG.ITEMS_PER_TICK then break end
                    local stack = st.inv:get_stack(st.list, idx)
                    if not stack:is_empty() then
                        local take_cnt = math.min(stack:get_count(), CONFIG.ITEMS_PER_TICK - moved)
                        local to_move  = ItemStack(stack)
                        to_move:set_count(take_cnt)
                        if binv:room_for_item("main", to_move) then
                            local leftover = binv:add_item("main", to_move)
                            local actual   = take_cnt - leftover:get_count()
                            if actual > 0 then
                                stack:take_item(actual)
                                st.inv:set_stack(st.list, idx, stack)
                                moved = moved + actual
                            end
                        end
                    end
                end
            end
            if moved > 0 and airutils and airutils.save_inventory then
                pcall(airutils.save_inventory, blimp_ent)
            end
        elseif mode == 2 then
            local bsize = binv:get_size("main") or 0
            for idx = 1, bsize do
                if moved >= CONFIG.ITEMS_PER_TICK then break end
                local stack = binv:get_stack("main", idx)
                if not stack:is_empty() then
                    local take_cnt = math.min(stack:get_count(), CONFIG.ITEMS_PER_TICK - moved)
                    local to_move  = ItemStack(stack)
                    to_move:set_count(take_cnt)
                    local leftover = try_insert_into_stores(stores, to_move)
                    local actual   = take_cnt - leftover:get_count()
                    if actual > 0 then
                        stack:take_item(actual)
                        binv:set_stack("main", idx, stack)
                        moved = moved + actual
                    end
                end
            end
            if moved > 0 and airutils and airutils.save_inventory then
                pcall(airutils.save_inventory, blimp_ent)
            end
        end
    end

    if moved > 0 then
        spawn_transfer_particles(pos, blimp_obj:get_pos(), false)
    end

    local status = string.format(
        "Docked to %s | Fuel: %.0f/%d | HP: %.0f/%d",
        blimp_ent._vehicle_name or "Blimp",
        blimp_ent._energy or 0, max_fuel,
        blimp_ent.hp or 0, max_hp
    )
    return moved > 0, status
end

local function process_blimp_fluid_transfer(pos, node, meta, blimp_ent, blimp_obj)
    local max_water = (steampunk_blimp and steampunk_blimp.MAX_WATER) or 10
    local cur_water = blimp_ent._water_level or 0
    local moved     = 0

    if CONFIG.BLIMP_AUTO_WATER and cur_water < max_water then
        if CONFIG.FREE_WATER_FROM_PIPES then
            local fdir = get_facing_dir(node.param2)
            for _, d in ipairs(ALL_6_DIRS) do
                if not (d.x == fdir.x and d.y == fdir.y and d.z == fdir.z) then
                    local np    = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
                    local nname = raw_get_node(np).name
                    if CONFIG.FLUID_SOURCE_NODES[nname] then
                        local add = math.min(CONFIG.WATER_PER_TICK, max_water - cur_water)
                        blimp_ent._water_level = cur_water + add
                        cur_water = blimp_ent._water_level
                        moved = moved + add
                        break
                    end
                end
            end
        end

        if cur_water < max_water and moved < CONFIG.WATER_PER_TICK then
            local stores = get_connected_inventories(pos, node)
            for _, st in ipairs(stores) do
                local sz = st.inv:get_size(st.list)
                for idx = 1, sz do
                    if cur_water >= max_water or moved >= CONFIG.WATER_PER_TICK then break end
                    local stack = st.inv:get_stack(st.list, idx)
                    if not stack:is_empty() then
                        local winfo = get_water_info(stack:get_name())
                        if winfo then
                            stack:take_item(1)
                            if winfo.empty then
                                if stack:is_empty() then
                                    stack = ItemStack(winfo.empty)
                                else
                                    local leftover = try_insert_into_stores(stores, ItemStack(winfo.empty))
                                    if not leftover:is_empty() then
                                        core.add_item(pos, leftover)
                                    end
                                end
                            end
                            st.inv:set_stack(st.list, idx, stack)
                            blimp_ent._water_level = math.min(max_water, cur_water + winfo.amount)
                            cur_water = blimp_ent._water_level
                            moved = moved + winfo.amount
                        end
                    end
                end
            end
        end
    end

    if moved > 0 then
        spawn_transfer_particles(pos, blimp_obj:get_pos(), true)
    end

    local status = string.format(
        "Docked to %s | Boiler Water: %.1f/%d",
        blimp_ent._vehicle_name or "Blimp",
        blimp_ent._water_level or 0, max_water
    )
    return moved > 0, status
end

-- =========================================================
-- INTERFACE-TO-INTERFACE (CONTRAPTION <-> STATIC DOCK) LOGIC
-- =========================================================
local function find_opposing_interface(pos, node)
    local fdir      = get_facing_dir(node.param2)
    local want_item = is_item_interface(node.name)

    for dist = 1, CONFIG.MAX_INTERFACE_GAP do
        local cpos  = {x = pos.x + fdir.x * dist, y = pos.y + fdir.y * dist, z = pos.z + fdir.z * dist}
        local cnode = raw_get_node(cpos)

        local match = (want_item and is_item_interface(cnode.name)) or
                      (not want_item and is_fluid_interface(cnode.name))

        if match then
            local odir = get_facing_dir(cnode.param2)
            if odir.x == -fdir.x and odir.y == -fdir.y and odir.z == -fdir.z then
                return cpos, cnode, dist
            end
            return nil, nil, nil
        elseif cnode.name ~= "air" then
            return nil, nil, nil
        end
    end
    return nil, nil, nil
end

local function decide_transfer_direction(meta_a, meta_b, stores_a, stores_b)
    local mode_a = meta_a:get_int("transfer_mode")
    local mode_b = meta_b:get_int("transfer_mode")

    if mode_a == 1 and mode_b ~= 1 then return "A_TO_B" end
    if mode_b == 1 and mode_a ~= 1 then return "B_TO_A" end
    if mode_a == 2 and mode_b ~= 2 then return "B_TO_A" end
    if mode_b == 2 and mode_a ~= 2 then return "A_TO_B" end

    local count_a = count_total_items_in_stores(stores_a)
    local count_b = count_total_items_in_stores(stores_b)

    if count_a == 0 and count_b == 0 then
        meta_a:set_string("locked_role", "")
        meta_b:set_string("locked_role", "")
        return "NONE"
    end

    local role_a = meta_a:get_string("locked_role")
    local role_b = meta_b:get_string("locked_role")

    if role_a == "SEND" or role_b == "RECEIVE" then
        meta_a:set_string("locked_role", "SEND")
        meta_b:set_string("locked_role", "RECEIVE")
        return (count_a > 0) and "A_TO_B" or "NONE"
    elseif role_a == "RECEIVE" or role_b == "SEND" then
        meta_a:set_string("locked_role", "RECEIVE")
        meta_b:set_string("locked_role", "SEND")
        return (count_b > 0) and "B_TO_A" or "NONE"
    end

    if count_a >= count_b and count_a > 0 then
        meta_a:set_string("locked_role", "SEND")
        meta_b:set_string("locked_role", "RECEIVE")
        return "A_TO_B"
    elseif count_b > count_a then
        meta_a:set_string("locked_role", "RECEIVE")
        meta_b:set_string("locked_role", "SEND")
        return "B_TO_A"
    end

    return "NONE"
end

local function move_items_between_stores(src_stores, dst_stores, max_items, fluid_only)
    local moved = 0
    for _, src in ipairs(src_stores) do
        local sz = src.inv:get_size(src.list)
        for idx = 1, sz do
            if moved >= max_items then break end
            local stack = src.inv:get_stack(src.list, idx)
            if not stack:is_empty() then
                local allow = true
                if fluid_only and not get_water_info(stack:get_name()) then
                    allow = false
                end
                if allow then
                    local take_cnt = math.min(stack:get_count(), max_items - moved)
                    local to_move  = ItemStack(stack)
                    to_move:set_count(take_cnt)
                    local leftover = try_insert_into_stores(dst_stores, to_move)
                    local actual   = take_cnt - leftover:get_count()
                    if actual > 0 then
                        stack:take_item(actual)
                        src.inv:set_stack(src.list, idx, stack)
                        moved = moved + actual
                    end
                end
            end
        end
    end
    return moved
end

-- =========================================================
-- MAIN INTERFACE TIMER & LOCK/UNLOCK MANAGEMENT
-- =========================================================
local function update_interface_infotext(pos, node, meta, state_str, extra_info)
    local title = is_fluid_interface(node.name) and "Portable Fluid Interface" or "Portable Storage Interface"
    local m_idx = meta:get_int("transfer_mode")
    local m_str = MODE_NAMES[m_idx] or MODE_NAMES[0]
    local role  = meta:get_string("locked_role")
    local r_str = (role ~= "") and (" | Latch: " .. role .. "ING") or ""
    local lock  = is_extended_variant(node.name) and "LOCKED (Immovable)" or "MOVABLE"

    meta:set_string("infotext", string.format(
        "%s [%s]\nMode: %s%s | %s\n%s (Right-Click to Toggle Mode)",
        title, state_str, m_str, r_str, lock, extra_info or ""
    ))
end

local function interface_timer(pos, elapsed)
    local node = raw_get_node(pos)
    if not is_any_interface(node.name) then return false end

    local meta     = core.get_meta(pos)
    local now      = core.get_gametime()
    local fdir     = get_facing_dir(node.param2)
    local is_fluid = is_fluid_interface(node.name)

    local opp_pos, opp_node = find_opposing_interface(pos, node)
    if opp_pos and opp_node then
        local opp_meta = core.get_meta(opp_pos)
        local stores_a = get_connected_inventories(pos, node)
        local stores_b = get_connected_inventories(opp_pos, opp_node)

        local flow_dir = decide_transfer_direction(meta, opp_meta, stores_a, stores_b)
        local moved    = 0

        if flow_dir == "A_TO_B" then
            moved = move_items_between_stores(stores_a, stores_b, CONFIG.ITEMS_PER_TICK, is_fluid)
        elseif flow_dir == "B_TO_A" then
            moved = move_items_between_stores(stores_b, stores_a, CONFIG.ITEMS_PER_TICK, is_fluid)
        end

        if moved > 0 then
            meta:set_float("hold_until", now + CONFIG.HOLD_EXTENDED_SECONDS)
            opp_meta:set_float("hold_until", now + CONFIG.HOLD_EXTENDED_SECONDS)
            spawn_transfer_particles(pos, opp_pos, is_fluid)
        end

        local active_hold = (now < meta:get_float("hold_until")) or (now < opp_meta:get_float("hold_until"))
        if active_hold then
            set_interface_extended(pos, node, true)
            set_interface_extended(opp_pos, opp_node, true)
            update_interface_infotext(pos, node, meta, "TRANSFERRING",
                string.format("Connected to opposing interface (%d items/tick)", moved))
        else
            set_interface_extended(pos, node, false)
            set_interface_extended(opp_pos, opp_node, false)
            local role = meta:get_string("locked_role")
            local msg  = (role ~= "")
                and ("Latched as " .. role .. "ER (Empty both chests or separate to reset)")
                or  "Both chests empty — Ready for new transfer"
            update_interface_infotext(pos, node, meta, "ALIGNED (IDLE)", msg)
        end

        return true
    end

    if meta:get_string("locked_role") ~= "" then
        meta:set_string("locked_role", "")
    end

    local blimp_ent, blimp_obj = find_nearby_blimp(pos, fdir)
    if blimp_ent and blimp_obj then
        local moved, status_str
        if is_fluid then
            moved, status_str = process_blimp_fluid_transfer(pos, node, meta, blimp_ent, blimp_obj)
        else
            moved, status_str = process_blimp_item_transfer(pos, node, meta, blimp_ent, blimp_obj)
        end

        if moved then
            meta:set_float("hold_until", now + CONFIG.HOLD_EXTENDED_SECONDS)
        end

        local keep_locked = moved or (now < meta:get_float("hold_until"))
        set_interface_extended(pos, node, keep_locked)
        update_interface_infotext(pos, node, meta, keep_locked and "BLIMP DOCKED" or "BLIMP FULL/READY", status_str)
        return true
    end

    if is_extended_variant(node.name) and now >= meta:get_float("hold_until") then
        set_interface_extended(pos, node, false)
    end
    local stores = get_connected_inventories(pos, node)
    update_interface_infotext(pos, node, meta, "STANDBY",
        string.format("Connected Storages/Vaults: %d", #stores))

    return true
end

-- =========================================================
-- PLACEMENT & RIGHT-CLICK MODE CYCLING
-- =========================================================
local function place_interface_node(itemstack, placer, pointed_thing)
    if not pointed_thing or pointed_thing.type ~= "node" then
        return itemstack
    end
    local sneaking = placer and placer:is_player() and placer:get_player_control().sneak
    local ldir     = look_to_unit_dir(placer)
    local face_dir = sneaking and ldir or {x = -ldir.x, y = -ldir.y, z = -ldir.z}
    local param2   = dir_to_interface_param2(face_dir)

    local placed_stack, place_pos = core.item_place_node(itemstack, placer, pointed_thing, param2)
    if place_pos then
        local meta = core.get_meta(place_pos)
        meta:set_int("transfer_mode", 0)
        meta:set_string("locked_role", "")
        core.get_node_timer(place_pos):start(CONFIG.TICK_INTERVAL)
    end
    return placed_stack
end

local function on_interface_rightclick(pos, node, clicker, itemstack, pointed_thing)
    if not clicker or not clicker:is_player() then return itemstack end
    if itemstack and kinetica.is_glue_tool and kinetica.is_glue_tool(itemstack:get_name()) then
        return itemstack
    end

    local meta     = core.get_meta(pos)
    local new_mode = (meta:get_int("transfer_mode") + 1) % 3
    meta:set_int("transfer_mode", new_mode)
    meta:set_string("locked_role", "")

    local opp_pos = find_opposing_interface(pos, node)
    if opp_pos then
        core.get_meta(opp_pos):set_string("locked_role", "")
    end

    local pname = clicker:get_player_name()
    core.chat_send_player(pname, "[Kinetica] Interface Mode: " .. MODE_NAMES[new_mode])
    interface_timer(pos, 0)
    return itemstack
end

-- =========================================================
-- NODE REGISTRATIONS (FIXED TEXTURE MAPPING)
-- =========================================================
local groups_movable = {
    handy = 1, pickaxey = 1, axey = 1,
    kinetica_interface = 1,
}

local groups_locked_ext = {
    handy = 1, pickaxey = 1, axey = 1,
    immovable = 1,
    kinetica_interface = 1,
    not_in_creative_inventory = 1,
}

local function register_interface_pair(base_name, ext_name, desc, tex_front)
    -- Retracted Node: Uses casing texture on all faces so it looks uniform
    core.register_node(base_name, {
        description           = desc,
        drawtype              = "nodebox",
        node_box              = INTERFACE_RETRACTED_NODEBOX,
        selection_box         = FULL_SELECTION_BOX,
        collision_box         = FULL_SELECTION_BOX,
        paramtype             = "light",
        paramtype2            = "facedir",
        sunlight_propagates   = true,
        is_ground_content     = false,
        tiles = {
            tex_front,             -- +Y local: Front facing nozzle
            CONFIG.TEX_BASE_CASING, -- -Y local: Back face
            CONFIG.TEX_BASE_CASING, -- +X
            CONFIG.TEX_BASE_CASING, -- -X
            CONFIG.TEX_BASE_CASING, -- +Z
            CONFIG.TEX_BASE_CASING, -- -Z
        },
        groups                = groups_movable,
        _mcl_hardness         = 2.5,
        _mcl_blast_resistance = 3.5,
        on_place              = place_interface_node,
        on_rightclick         = on_interface_rightclick,
        on_construct          = function(pos)
            local meta = core.get_meta(pos)
            meta:set_int("transfer_mode", 0)
            update_interface_infotext(pos, raw_get_node(pos), meta, "STANDBY", "")
            core.get_node_timer(pos):start(CONFIG.TICK_INTERVAL)
        end,
        on_timer              = interface_timer,
    })

    -- Extended Node: Keeps casing on the 4 side faces, but applies the nozzle texture to the extending tip (+Y)
    core.register_node(ext_name, {
        description           = desc .. " (Extended/Locked)",
        drawtype              = "nodebox",
        node_box              = INTERFACE_EXTENDED_NODEBOX,
        selection_box         = FULL_SELECTION_BOX,
        collision_box         = FULL_SELECTION_BOX,
        paramtype             = "light",
        paramtype2            = "facedir",
        sunlight_propagates   = true,
        is_ground_content     = false,
        drop                  = base_name,
        tiles = {
            tex_front,              -- +Y local: Extended nozzle tip
            CONFIG.TEX_BASE_CASING,  -- -Y local: Back face
            CONFIG.TEX_BASE_CASING,  -- +X side (Stays clean casing instead of stretching nozzle!)
            CONFIG.TEX_BASE_CASING,  -- -X side
            CONFIG.TEX_BASE_CASING,  -- +Z side
            CONFIG.TEX_BASE_CASING,  -- -Z side
        },
        groups                = groups_locked_ext,
        _mcl_hardness         = 2.5,
        _mcl_blast_resistance = 3.5,
        on_rightclick         = on_interface_rightclick,
        on_timer              = interface_timer,
    })
end

register_interface_pair(
    ITEM_BASE,
    ITEM_EXT,
    "Portable Storage Interface (Bridges Contraption Chests/Vaults & Refuels Blimps)",
    CONFIG.TEX_ITEM_FRONT
)

register_interface_pair(
    FLUID_BASE,
    FLUID_EXT,
    "Portable Fluid Interface (Transfers Fluids & Refills Blimp Boilers)",
    CONFIG.TEX_FLUID_FRONT
)

core.register_lbm({
    label             = "Wake Kinetica Portable Interfaces",
    name              = "kinetica:wake_portable_interfaces_lbm",
    nodenames         = {"group:kinetica_interface"},
    run_at_every_load = true,
    action = function(pos)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TICK_INTERVAL)
        end
    end,
})

core.register_craft({
    output = ITEM_BASE,
    recipe = {
        {"", "kinetica:chute", ""},
        {"kinetica:andesite_alloy", "kinetica:andesite_casing", "kinetica:andesite_alloy"},
    },
})

core.register_craft({
    output = FLUID_BASE,
    recipe = {
        {"", "kinetica:fluid_pipe", ""},
        {"kinetica:andesite_alloy", "kinetica:andesite_casing", "kinetica:andesite_alloy"},
    },
})