kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""
local S = core.get_translator(modname)

local CONFIG = {
    TIMER_INTERVAL            = 0.20,
    CHUTE_STACK_SIZE          = 16,
    SMART_CHUTE_DEFAULT_STACK = 64,
    MAX_CHAIN_DEPTH           = 64,
    VACUUM_SEARCH_RADIUS      = 1.15,
    VACUUM_HALF_WIDTH         = 0.65,
    VACUUM_MIN_Y              = -0.55,
    VACUUM_MAX_Y              = 1.35,
    MAX_ENTITIES_BELOW        = 12,
    FAN_MAX_DISTANCE          = 12,
    FAN_UPDRAFT_SPEED         = 3.0,
    FAN_HOVER_TOP_SPEED       = 0.35,
    FAN_SPAWN_PARTICLES       = true,
    FAN_NODE_NAMES = {
        [modname .. ":encased_fan"]            = true,
        [modname .. ":encased_fan_active"]     = true,
        [modname .. ":encased_fan_active_cw"]  = true,
        [modname .. ":encased_fan_active_ccw"] = true,
        [modname .. ":fan"]                    = true,
    },
    TEXTURE_MAIN              = "kinetica_Chute.png",
    TEXTURE_TOP               = "kinetica_chute_top.png",
    TEXTURE_SIDE              = "kinetica_chute_side.png",
    TEXTURE_SMART_MAIN        = "kinetica_smart_chute.png",
    TEXTURE_SMART_SIDE        = "kinetica_smart_chute_side.png",
    EXTRACT_LISTS             = { "profit", "profit_bin", "output", "dst", "main", "input" },
    EXTRACT_SKIP_LISTS        = { hoe = true, seed = true, fuel = true, src = true, filter = true },
    INSERT_LISTS              = { "main", "src", "input" },
    ENABLE_CRAFTING           = true,
}

local CHUTE_NODE_NAME       = modname .. ":chute"
local SMART_CHUTE_NODE_NAME = modname .. ":smart_chute"
local FILTER_SLOTS          = 3
local STACK_SIZE_PRESETS    = { 1, 8, 16, 32, 64 }

local function is_any_chute(node_name)
    return node_name == CHUTE_NODE_NAME or node_name == SMART_CHUTE_NODE_NAME
end
kinetica.is_chute = is_any_chute

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function get_normal_chute_tiles()
    local top_path  = modpath .. "/textures/" .. CONFIG.TEXTURE_TOP
    local side_path = modpath .. "/textures/" .. CONFIG.TEXTURE_SIDE

    if file_exists(top_path) and file_exists(side_path) then
        return {
            CONFIG.TEXTURE_TOP,
            CONFIG.TEXTURE_TOP,
            CONFIG.TEXTURE_SIDE,
            CONFIG.TEXTURE_SIDE,
            CONFIG.TEXTURE_SIDE,
            CONFIG.TEXTURE_SIDE,
        }
    end

    local base_tex = CONFIG.TEXTURE_MAIN
    local rim_tex  = base_tex .. "^[colorize:#18181c:60"
    return {
        rim_tex,
        rim_tex,
        base_tex,
        base_tex,
        base_tex,
        base_tex,
    }
end

local function get_smart_chute_tiles()
    local smart_side_path = modpath .. "/textures/" .. CONFIG.TEXTURE_SMART_SIDE
    local smart_main_path = modpath .. "/textures/" .. CONFIG.TEXTURE_SMART_MAIN
    local top_path        = modpath .. "/textures/" .. CONFIG.TEXTURE_TOP

    if file_exists(smart_side_path) then
        local top_tex = file_exists(top_path) and CONFIG.TEXTURE_TOP or (CONFIG.TEXTURE_SMART_SIDE .. "^[colorize:#241c0e:70")
        return {
            top_tex,
            top_tex,
            CONFIG.TEXTURE_SMART_SIDE,
            CONFIG.TEXTURE_SMART_SIDE,
            CONFIG.TEXTURE_SMART_SIDE,
            CONFIG.TEXTURE_SMART_SIDE,
        }
    end

    if file_exists(smart_main_path) then
        local rim_tex = CONFIG.TEXTURE_SMART_MAIN .. "^[colorize:#241c0e:70"
        return {
            rim_tex,
            rim_tex,
            CONFIG.TEXTURE_SMART_MAIN,
            CONFIG.TEXTURE_SMART_MAIN,
            CONFIG.TEXTURE_SMART_MAIN,
            CONFIG.TEXTURE_SMART_MAIN,
        }
    end

    local brass_side = CONFIG.TEXTURE_MAIN .. "^[colorize:#e0a82e:135"
    local brass_rim  = CONFIG.TEXTURE_MAIN .. "^[colorize:#9c6f16:155"
    return {
        brass_rim,
        brass_rim,
        brass_side,
        brass_side,
        brass_side,
        brass_side,
    }
end

local function ensure_smart_chute_meta(pos)
    local meta = core.get_meta(pos)
    local inv  = meta:get_inventory()
    if inv:get_size("filter") ~= FILTER_SLOTS then
        inv:set_size("filter", FILTER_SLOTS)
    end
    if meta:get_string("filter_mode") == "" then
        meta:set_string("filter_mode", "whitelist")
    end
    if meta:get_int("stack_size") <= 0 then
        meta:set_int("stack_size", CONFIG.SMART_CHUTE_DEFAULT_STACK)
    end
    if meta:get_string("exact_mode") == "" then
        meta:set_string("exact_mode", "upto")
    end
    return meta, inv
end

local function is_smart_chute_redstone_locked(pos)
    local vpos = vector.new(pos.x, pos.y, pos.z)
    if mcl_redstone and mcl_redstone.get_power then
        local ok, pwr = pcall(mcl_redstone.get_power, vpos)
        if ok and pwr and pwr > 0 then
            return true
        end
    end
    return false
end

local function is_item_allowed_by_chute(chute_pos, chute_node, item_name)
    if not item_name or item_name == "" then
        return false
    end
    chute_node = chute_node or core.get_node(chute_pos)
    if chute_node.name ~= SMART_CHUTE_NODE_NAME then
        return true
    end

    if is_smart_chute_redstone_locked(chute_pos) then
        return false
    end

    local meta, inv = ensure_smart_chute_meta(chute_pos)
    local mode = meta:get_string("filter_mode")

    local has_any_filter = false
    local matches_filter = false

    for i = 1, FILTER_SLOTS do
        local fstack = inv:get_stack("filter", i)
        if not fstack:is_empty() then
            has_any_filter = true
            if fstack:get_name() == item_name then
                matches_filter = true
                break
            end
        end
    end

    if not has_any_filter then
        return true
    end

    if mode == "blacklist" then
        return not matches_filter
    else
        return matches_filter
    end
end

local function get_chute_transfer_settings(chute_pos, chute_node)
    chute_node = chute_node or core.get_node(chute_pos)
    if chute_node.name ~= SMART_CHUTE_NODE_NAME then
        return CONFIG.CHUTE_STACK_SIZE, false
    end
    local meta, _ = ensure_smart_chute_meta(chute_pos)
    local batch   = meta:get_int("stack_size")
    local exact   = (meta:get_string("exact_mode") == "exact")
    return math.max(1, math.min(64, batch)), exact
end

local function update_smart_chute_infotext(pos)
    local meta, inv = ensure_smart_chute_meta(pos)
    local locked    = is_smart_chute_redstone_locked(pos)
    local mode      = meta:get_string("filter_mode")
    local batch     = meta:get_int("stack_size")
    local exact     = (meta:get_string("exact_mode") == "exact")

    local filter_names = {}
    for i = 1, FILTER_SLOTS do
        local s = inv:get_stack("filter", i)
        if not s:is_empty() then
            local idef = core.registered_items[s:get_name()]
            local desc = (idef and idef.description) and string.match(idef.description, "^[^\n]+") or s:get_name()
            filter_names[#filter_names + 1] = desc
        end
    end

    local filter_str = (#filter_names > 0) and table.concat(filter_names, ", ") or "Any Item"
    local mode_lbl   = (mode == "blacklist") and "BLACKLIST (Block)" or "WHITELIST (Allow)"
    local count_lbl  = exact and ("Exact " .. batch) or ("Up to " .. batch)
    local lock_lbl   = locked and " [REDSTONE LOCKED]" or ""

    meta:set_string("infotext", string.format(
        "Smart Chute%s\nMode: %s | Stack: %s\nFilter: %s",
        lock_lbl, mode_lbl, count_lbl, filter_str
    ))
end

local function get_smart_chute_formspec(pos)
    local meta, _ = ensure_smart_chute_meta(pos)
    local locked  = is_smart_chute_redstone_locked(pos)
    local mode    = meta:get_string("filter_mode")
    local batch   = meta:get_int("stack_size")
    local exact   = (meta:get_string("exact_mode") == "exact")

    local status_str = locked
        and "Status: LOCKED BY REDSTONE (Paused)"
        or  "Status: ACTIVE (Filtering Extractions & Falling Items)"
    local mode_btn_lbl = (mode == "blacklist")
        and "Mode: BLACKLIST (Block Listed)"
        or  "Mode: WHITELIST (Allow Listed)"
    local exact_btn_lbl = exact
        and ("Count: EXACT " .. batch)
        or  ("Count: UP TO " .. batch)

    local slot_bg = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(3.0, 1.5, 3, 1) or ""
    local inv_bg1 = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(0, 4.5, 9, 3) or ""
    local inv_bg2 = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(0, 7.74, 9, 1) or ""

    return "size[9,8.75]" ..
        "label[0,0;Smart Chute (Item Filter, Stack Control & Redstone Lock)]" ..
        "label[0,0.45;" .. core.formspec_escape(status_str) .. "]" ..
        "label[2.7,1.0;Filter Slots (Up to 3 Items):]" ..
        slot_bg ..
        "list[context;filter;3.0,1.5;3,1;]" ..
        "button[0.4,2.75;4.0,0.8;toggle_mode;" .. core.formspec_escape(mode_btn_lbl) .. "]" ..
        "button[4.6,2.75;2.1,0.8;cycle_stack;Batch: " .. batch .. "]" ..
        "button[6.8,2.75;1.8,0.8;toggle_exact;" .. core.formspec_escape(exact_btn_lbl) .. "]" ..
        "button[6.8,1.55;1.8,0.8;clear_filter;Clear All]" ..
        "label[0,3.85;Inventory (Tip: Blacklist Gravel to keep it on a Depot until washed!)]" ..
        "list[current_player;main;0,4.5;9,3;9]" ..
        inv_bg1 ..
        "list[current_player;main;0,7.74;9,1;]" ..
        inv_bg2 ..
        "listring[current_player;main]" ..
        "listring[context;filter]"
end

local function refresh_smart_chute_ui(pos)
    update_smart_chute_infotext(pos)
    local meta = core.get_meta(pos)
    meta:set_string("formspec", get_smart_chute_formspec(pos))
end

local function notify_inventory_change(pos, node)
    local vpos = vector.new(pos.x, pos.y, pos.z)

    if mcl_redstone and mcl_redstone.update_comparators then
        pcall(mcl_redstone.update_comparators, vpos)
    end

    local def = core.registered_nodes[node.name]
    local timer = core.get_node_timer(vpos)
    if timer and not timer:is_started() and def and def.on_timer then
        timer:start(0.25)
    end
end

local function is_mechanical_belt(node_name)
    if not node_name or node_name == "ignore" then
        return false
    end
    if core.get_item_group(node_name, "kinetica_belt") ~= 0 or
       core.get_item_group(node_name, "mechanical_belt") ~= 0 then
        return true
    end
    if string.find(node_name, ":belt") or string.find(node_name, "_belt") then
        return true
    end
    return false
end

local function is_open_space(node_name)
    if node_name == "air" then
        return true
    end
    local def = core.registered_nodes[node_name]
    if not def then
        return false
    end
    return def.walkable == false
end

local function is_upward_fan(pos, node)
    if not node or node.name == "ignore" then
        return false
    end

    local is_fan = CONFIG.FAN_NODE_NAMES[node.name] or
                   core.get_item_group(node.name, "kinetica_fan") ~= 0 or
                   core.get_item_group(node.name, "encased_fan") ~= 0 or
                   string.find(node.name, "encased_fan") ~= nil

    if not is_fan then
        return false
    end

    local meta = core.get_meta(pos)
    if meta then
        local active_flag = meta:get_string("active")
        if active_flag == "false" or active_flag == "0" or node.name == (modname .. ":encased_fan") then
            return false
        end
        local dir_flag = meta:get_string("airflow_dir")
        if dir_flag ~= "" and dir_flag ~= "up" then
            return false
        end
    end
    return true
end

local function has_upward_airflow(chute_pos)
    local vpos = vector.new(chute_pos.x, chute_pos.y, chute_pos.z)
    for dist = 1, CONFIG.FAN_MAX_DISTANCE do
        local check_pos  = vector.offset(vpos, 0, -dist, 0)
        local check_node = core.get_node(check_pos)
        if is_upward_fan(check_pos, check_node) then
            return true
        end
        if not is_any_chute(check_node.name) and not is_open_space(check_node.name) then
            return false
        end
    end
    return false
end

local function get_node_inventory(pos)
    local vpos = vector.new(pos.x, pos.y, pos.z)
    local meta = core.get_meta(vpos)
    local inv  = meta and meta:get_inventory()
    if not inv then
        return nil
    end
    local lists = inv:get_lists()
    if not lists or next(lists) == nil then
        return nil
    end
    return inv
end

local function get_extractable_lists(above_node, inv)
    if not inv then return {} end

    if string.find(above_node.name or "", ":feeder") then
        if inv:get_size("profit") > 0 and not inv:is_empty("profit") then
            return { "profit" }
        end
        return {}
    end

    local result = {}
    local seen   = {}

    for _, listname in ipairs(CONFIG.EXTRACT_LISTS) do
        if not CONFIG.EXTRACT_SKIP_LISTS[listname] then
            local sz = inv:get_size(listname)
            if sz and sz > 0 and not inv:is_empty(listname) then
                result[#result + 1] = listname
                seen[listname] = true
            end
        end
    end

    local all_lists = inv:get_lists()
    if all_lists then
        for listname, _ in pairs(all_lists) do
            if not seen[listname] and not CONFIG.EXTRACT_SKIP_LISTS[listname] and not inv:is_empty(listname) then
                result[#result + 1] = listname
            end
        end
    end

    return result
end

local function find_insert_list(inv, stack)
    if not inv then
        return nil
    end

    for _, listname in ipairs(CONFIG.INSERT_LISTS) do
        local size = inv:get_size(listname)
        if size and size > 0 and inv:room_for_item(listname, stack) then
            return listname
        end
    end

    local all_lists = inv:get_lists()
    if all_lists then
        for listname, _ in pairs(all_lists) do
            if not CONFIG.EXTRACT_SKIP_LISTS[listname] and inv:room_for_item(listname, stack) then
                return listname
            end
        end
    end
    return nil
end

local function try_insert_into_node(target_pos, target_node, stack, max_batch)
    if stack:is_empty() then
        return stack, false
    end

    local target_inv = get_node_inventory(target_pos)
    if not target_inv then
        return stack, false
    end

    local listname = find_insert_list(target_inv, stack)
    if not listname then
        return stack, false
    end

    local to_insert = ItemStack(stack)
    if to_insert:get_count() > max_batch then
        to_insert:set_count(max_batch)
    end

    local leftover = target_inv:add_item(listname, to_insert)
    local inserted_count = to_insert:get_count() - leftover:get_count()

    if inserted_count > 0 then
        stack:take_item(inserted_count)
        notify_inventory_change(target_pos, target_node)
        return stack, true
    end
    return stack, false
end

local function try_spit_item_below(bottom_chute_pos, below_pos, below_node, stack, max_batch)
    if stack:is_empty() then
        return stack, false
    end

    local is_belt = is_mechanical_belt(below_node.name)
    local is_open = is_open_space(below_node.name)

    if not is_belt and not is_open then
        return stack, false
    end

    local existing_objs = core.get_objects_inside_radius(below_pos, 0.7)
    local item_count = 0
    for _, obj in ipairs(existing_objs) do
        local ent = obj:get_luaentity()
        if ent and ent.name == "__builtin:item" then
            item_count = item_count + 1
        end
    end
    if item_count >= CONFIG.MAX_ENTITIES_BELOW then
        return stack, false
    end

    local drop_y = bottom_chute_pos.y - 0.60
    if is_belt then
        drop_y = below_pos.y + 0.35
    end

    local drop_pos = vector.new(bottom_chute_pos.x, drop_y, bottom_chute_pos.z)

    local to_drop = ItemStack(stack)
    if to_drop:get_count() > max_batch then
        to_drop:set_count(max_batch)
    end

    local obj = core.add_item(drop_pos, to_drop)
    if obj then
        obj:set_velocity(vector.new(0, -1.8, 0))
        stack:take_item(to_drop:get_count())
        return stack, true
    end
    return stack, false
end

local function push_stack_down_chute_chain(start_chute_pos, stack, max_batch)
    if stack:is_empty() then
        return stack, false
    end

    local start_node = core.get_node(start_chute_pos)
    local item_name  = stack:get_name()

    if not is_item_allowed_by_chute(start_chute_pos, start_node, item_name) then
        return stack, false
    end

    local batch_limit = max_batch or CONFIG.CHUTE_STACK_SIZE
    local bottom_chute_pos = vector.new(start_chute_pos.x, start_chute_pos.y, start_chute_pos.z)

    for _ = 1, CONFIG.MAX_CHAIN_DEPTH do
        local next_pos  = vector.offset(bottom_chute_pos, 0, -1, 0)
        local next_node = core.get_node(next_pos)
        if is_any_chute(next_node.name) then
            if not is_item_allowed_by_chute(next_pos, next_node, item_name) then
                return stack, false
            end
            local next_batch, _ = get_chute_transfer_settings(next_pos, next_node)
            batch_limit = math.min(batch_limit, next_batch)
            bottom_chute_pos = next_pos
        else
            break
        end
    end

    local below_pos  = vector.offset(bottom_chute_pos, 0, -1, 0)
    local below_node = core.get_node(below_pos)

    if below_node.name == "ignore" then
        return stack, false
    end

    local below_inv = get_node_inventory(below_pos)
    if below_inv and not is_any_chute(below_node.name) then
        return try_insert_into_node(below_pos, below_node, stack, batch_limit)
    end

    if is_mechanical_belt(below_node.name) or is_open_space(below_node.name) then
        return try_spit_item_below(bottom_chute_pos, below_pos, below_node, stack, batch_limit)
    end
    return stack, false
end

local function extract_from_inventory_above(chute_pos, chute_node, above_pos, above_node, above_inv)
    if chute_node.name == SMART_CHUTE_NODE_NAME and is_smart_chute_redstone_locked(chute_pos) then
        return false
    end

    local max_batch, require_exact = get_chute_transfer_settings(chute_pos, chute_node)
    local candidate_lists = get_extractable_lists(above_node, above_inv)

    for _, listname in ipairs(candidate_lists) do
        local size = above_inv:get_size(listname)
        for i = 1, size do
            local stack = above_inv:get_stack(listname, i)
            if not stack:is_empty() then
                local item_name = stack:get_name()

                if is_item_allowed_by_chute(chute_pos, chute_node, item_name) then
                    local avail_count = stack:get_count()
                    if not require_exact or avail_count >= max_batch then
                        local pull_count    = require_exact and max_batch or math.min(avail_count, max_batch)
                        local extract_stack = stack:peek_item(pull_count)
                        local initial_count = extract_stack:get_count()
                        local leftover, moved = push_stack_down_chute_chain(chute_pos, extract_stack, pull_count)

                        if moved then
                            local consumed = initial_count - leftover:get_count()
                            stack:take_item(consumed)
                            above_inv:set_stack(listname, i, stack)
                            notify_inventory_change(above_pos, above_node)
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

local function handle_falling_items(chute_pos, chute_node)
    local vpos = vector.new(chute_pos.x, chute_pos.y, chute_pos.z)
    local objs = core.get_objects_inside_radius(vpos, CONFIG.VACUUM_SEARCH_RADIUS)

    for _, obj in ipairs(objs) do
        local ent = obj:get_luaentity()
        if ent and ent.name == "__builtin:item" and ent.itemstring and ent.itemstring ~= "" then
            local opos = obj:get_pos()
            if opos then
                local dx = math.abs(opos.x - vpos.x)
                local dz = math.abs(opos.z - vpos.z)
                local dy = opos.y - vpos.y

                if dx <= CONFIG.VACUUM_HALF_WIDTH and
                   dz <= CONFIG.VACUUM_HALF_WIDTH and
                   dy >= CONFIG.VACUUM_MIN_Y and
                   dy <= CONFIG.VACUUM_MAX_Y then

                    local item_stack = ItemStack(ent.itemstring)
                    if not item_stack:is_empty() then
                        local item_name = item_stack:get_name()
                        local allowed   = is_item_allowed_by_chute(vpos, chute_node, item_name)

                        if not allowed then
                            if dy < 0.55 then
                                obj:set_pos(vector.new(opos.x, vpos.y + 0.58, opos.z))
                            end
                            local vel = obj:get_velocity() or vector.new(0, 0, 0)
                            if vel.y < 0 then
                                obj:set_velocity(vector.new(vel.x * 0.5, 0, vel.z * 0.5))
                            end
                        else
                            local max_batch, require_exact = get_chute_transfer_settings(vpos, chute_node)
                            if not require_exact or item_stack:get_count() >= max_batch then
                                local leftover, moved = push_stack_down_chute_chain(vpos, item_stack, max_batch)
                                if moved then
                                    if leftover:is_empty() then
                                        ent.itemstring = ""
                                        obj:remove()
                                    else
                                        ent.itemstring = leftover:to_string()
                                    end
                                    return true
                                end
                            end

                            if dx > 0.05 or dz > 0.05 then
                                local cx = vpos.x + (opos.x - vpos.x) * 0.25
                                local cz = vpos.z + (opos.z - vpos.z) * 0.25
                                obj:set_pos(vector.new(cx, opos.y, cz))
                            end
                            local vel = obj:get_velocity() or vector.new(0, -2.0, 0)
                            obj:set_velocity(vector.new(0, math.min(vel.y, -2.2), 0))
                        end
                    end
                end
            end
        end
    end
    return false
end

local function handle_upward_airflow(chute_pos, chute_node)
    local vpos       = vector.new(chute_pos.x, chute_pos.y, chute_pos.z)
    local above_pos  = vector.offset(vpos, 0, 1, 0)
    local above_node = core.get_node(above_pos)
    local above_inv  = (not is_any_chute(above_node.name)) and get_node_inventory(above_pos) or nil

    if CONFIG.FAN_SPAWN_PARTICLES and math.random(1, 2) == 1 then
        core.add_particle({
            pos = vector.new(
                vpos.x + (math.random() - 0.5) * 0.35,
                vpos.y - 0.35,
                vpos.z + (math.random() - 0.5) * 0.35
            ),
            velocity           = vector.new(0, CONFIG.FAN_UPDRAFT_SPEED, 0),
            acceleration       = vector.new(0, 0.5, 0),
            expirationtime     = 0.35,
            size               = 1.3,
            collisiondetection = false,
            texture            = "bubble.png^[colorize:#ffffff:180",
        })
    end

    local max_batch, _ = get_chute_transfer_settings(vpos, chute_node)
    local objs = core.get_objects_inside_radius(vpos, 1.05)

    for _, obj in ipairs(objs) do
        local ent = obj:get_luaentity()
        if ent and ent.name == "__builtin:item" and ent.itemstring and ent.itemstring ~= "" then
            local opos = obj:get_pos()
            if opos then
                local dx = math.abs(opos.x - vpos.x)
                local dz = math.abs(opos.z - vpos.z)
                local dy = opos.y - vpos.y

                if dx <= 0.55 and dz <= 0.55 and dy >= -0.85 and dy <= 0.95 then
                    local item_stack = ItemStack(ent.itemstring)
                    if not item_stack:is_empty() and is_item_allowed_by_chute(vpos, chute_node, item_stack:get_name()) then
                        if dy >= 0.25 and above_inv then
                            local leftover, inserted = try_insert_into_node(above_pos, above_node, item_stack, max_batch)
                            if inserted then
                                if leftover:is_empty() then
                                    ent.itemstring = ""
                                    obj:remove()
                                else
                                    ent.itemstring = leftover:to_string()
                                end
                                return true
                            end
                        end

                        local target_x = vpos.x + (opos.x - vpos.x) * 0.25
                        local target_z = vpos.z + (opos.z - vpos.z) * 0.25
                        obj:set_pos(vector.new(target_x, opos.y, target_z))

                        if dy >= 0.45 and is_open_space(above_node.name) then
                            obj:set_velocity(vector.new(0, CONFIG.FAN_HOVER_TOP_SPEED, 0))
                        else
                            obj:set_velocity(vector.new(0, CONFIG.FAN_UPDRAFT_SPEED, 0))
                        end
                    end
                end
            end
        end
    end
    return true
end

local function chute_on_timer(pos, elapsed)
    local vpos = vector.new(pos.x, pos.y, pos.z)
    local node = core.get_node(vpos)

    if node.name == SMART_CHUTE_NODE_NAME then
        update_smart_chute_infotext(vpos)
    end

    if has_upward_airflow(vpos) then
        handle_upward_airflow(vpos, node)
        return true
    end

    local above_pos  = vector.offset(vpos, 0, 1, 0)
    local above_node = core.get_node(above_pos)

    if above_node.name ~= "ignore" and not is_any_chute(above_node.name) then
        local above_inv = get_node_inventory(above_pos)
        if above_inv then
            extract_from_inventory_above(vpos, node, above_pos, above_node, above_inv)
        end
    end

    handle_falling_items(vpos, node)
    return true
end

local function smart_allow_put(pos, listname, index, stack, player)
    if listname ~= "filter" then return 0 end
    if player and player:is_player() and core.is_protected(pos, player:get_player_name()) then
        return 0
    end
    local _, inv = ensure_smart_chute_meta(pos)
    local ghost  = stack:peek_item(1)
    inv:set_stack("filter", index, ghost)
    refresh_smart_chute_ui(pos)
    return 0
end

local function smart_allow_take(pos, listname, index, stack, player)
    if listname ~= "filter" then return 0 end
    if player and player:is_player() and core.is_protected(pos, player:get_player_name()) then
        return 0
    end
    local _, inv = ensure_smart_chute_meta(pos)
    inv:set_stack("filter", index, ItemStack(""))
    refresh_smart_chute_ui(pos)
    return 0
end

local function smart_allow_move(pos, from_list, from_index, to_list, to_index, count, player)
    if player and player:is_player() and core.is_protected(pos, player:get_player_name()) then
        return 0
    end
    if from_list == "filter" and to_list == "filter" then
        local _, inv = ensure_smart_chute_meta(pos)
        local s_from = inv:get_stack("filter", from_index)
        local s_to   = inv:get_stack("filter", to_index)
        inv:set_stack("filter", to_index, s_from)
        inv:set_stack("filter", from_index, s_to)
        refresh_smart_chute_ui(pos)
    end
    return 0
end

local function smart_on_receive_fields(pos, formname, fields, sender)
    if sender and sender:is_player() and core.is_protected(pos, sender:get_player_name()) then
        return
    end
    local meta, inv = ensure_smart_chute_meta(pos)

    if fields.toggle_mode then
        local cur = meta:get_string("filter_mode")
        meta:set_string("filter_mode", (cur == "blacklist") and "whitelist" or "blacklist")
        refresh_smart_chute_ui(pos)
    elseif fields.cycle_stack then
        local cur = meta:get_int("stack_size")
        local next_val = STACK_SIZE_PRESETS[1]
        for i, v in ipairs(STACK_SIZE_PRESETS) do
            if v == cur then
                next_val = STACK_SIZE_PRESETS[(i % #STACK_SIZE_PRESETS) + 1]
                break
            end
        end
        meta:set_int("stack_size", next_val)
        refresh_smart_chute_ui(pos)
    elseif fields.toggle_exact then
        local cur = meta:get_string("exact_mode")
        meta:set_string("exact_mode", (cur == "exact") and "upto" or "exact")
        refresh_smart_chute_ui(pos)
    elseif fields.clear_filter then
        for i = 1, FILTER_SLOTS do
            inv:set_stack("filter", i, ItemStack(""))
        end
        refresh_smart_chute_ui(pos)
    end
end

local WIDER_HOLLOW_CHUTE_WALLS = {
    { -7/16, -0.500, -7/16,  7/16,  0.500, -6/16 },
    { -7/16, -0.500,  6/16,  7/16,  0.500,  7/16 },
    { -7/16, -0.500, -6/16, -6/16,  0.500,  6/16 },
    {  6/16, -0.500, -6/16,  7/16,  0.500,  6/16 },
}

local WIDER_SELECTION_BOX = {
    type  = "fixed",
    fixed = { -7/16, -0.5, -7/16, 7/16, 0.5, 7/16 },
}

local sound_metal = (mcl_sounds and mcl_sounds.node_sound_metal_defaults)
    and mcl_sounds.node_sound_metal_defaults()
    or nil

core.register_node(CHUTE_NODE_NAME, {
    description         = S("Chute (Wider Hollow Vertical Pipe | Pulls All Items)"),
    _doc_items_longdesc = S("A wide hollow vertical logistics pipe. Extracts any item from containers/Depots above or funnels dropped items straight down."),
    drawtype            = "nodebox",
    paramtype           = "light",
    sunlight_propagates = true,
    use_texture_alpha   = "clip",
    is_ground_content   = false,
    tiles               = get_normal_chute_tiles(),

    node_box = {
        type  = "fixed",
        fixed = WIDER_HOLLOW_CHUTE_WALLS,
    },
    collision_box = {
        type  = "fixed",
        fixed = WIDER_HOLLOW_CHUTE_WALLS,
    },
    selection_box = WIDER_SELECTION_BOX,

    groups = {
        pickaxey       = 1,
        axey           = 1,
        handy          = 1,
        deco_block     = 1,
        kinetica_chute = 1,
    },

    sounds                = sound_metal,
    _mcl_blast_resistance = 3.0,
    _mcl_hardness         = 2.0,

    on_construct = function(pos)
        local meta = core.get_meta(pos)
        meta:set_string("infotext", "Chute (Unfiltered | Up to 16 items/tick)")
        core.get_node_timer(vector.new(pos.x, pos.y, pos.z)):start(CONFIG.TIMER_INTERVAL)
    end,

    on_timer = chute_on_timer,
})

core.register_node(SMART_CHUTE_NODE_NAME, {
    description         = S("Smart Chute (Whitelist/Blacklist Filter, Stack Size & Redstone Lock)"),
    _doc_items_longdesc = S("An upgraded Brass Chute with 3 filter slots, Whitelist/Blacklist modes, adjustable stack sizes, and Redstone locking."),
    drawtype            = "nodebox",
    paramtype           = "light",
    sunlight_propagates = true,
    use_texture_alpha   = "clip",
    is_ground_content   = false,
    tiles               = get_smart_chute_tiles(),

    node_box = {
        type  = "fixed",
        fixed = WIDER_HOLLOW_CHUTE_WALLS,
    },
    collision_box = {
        type  = "fixed",
        fixed = WIDER_HOLLOW_CHUTE_WALLS,
    },
    selection_box = WIDER_SELECTION_BOX,

    groups = {
        pickaxey       = 1,
        axey           = 1,
        handy          = 1,
        deco_block     = 1,
        kinetica_chute = 1,
        smart_chute    = 1,
    },

    sounds                = sound_metal,
    _mcl_blast_resistance = 3.5,
    _mcl_hardness         = 2.5,

    on_construct = function(pos)
        ensure_smart_chute_meta(pos)
        refresh_smart_chute_ui(pos)
        core.get_node_timer(vector.new(pos.x, pos.y, pos.z)):start(CONFIG.TIMER_INTERVAL)
    end,

    allow_metadata_inventory_put  = smart_allow_put,
    allow_metadata_inventory_take = smart_allow_take,
    allow_metadata_inventory_move = smart_allow_move,
    on_receive_fields             = smart_on_receive_fields,
    on_timer                      = chute_on_timer,
})

core.register_lbm({
    label             = "Restart kinetica Chute & Smart Chute timers",
    name              = modname .. ":restart_chute_timers",
    nodenames         = { CHUTE_NODE_NAME, SMART_CHUTE_NODE_NAME },
    run_at_every_load = true,
    action = function(pos, node)
        local vpos  = vector.new(pos.x, pos.y, pos.z)
        if node.name == SMART_CHUTE_NODE_NAME then
            ensure_smart_chute_meta(vpos)
            refresh_smart_chute_ui(vpos)
        end
        local timer = core.get_node_timer(vpos)
        if not timer:is_started() then
            timer:start(CONFIG.TIMER_INTERVAL)
        end
    end,
})

if CONFIG.ENABLE_CRAFTING then
    local redstone_item = core.registered_items["mcl_redstone:redstone"]
        and "mcl_redstone:redstone"
        or  "mesecons:redstone"

    core.register_craft({
        output = "kinetica:chute 4",
        recipe = {
            {"kinetica:sheet_iron", "",                    "kinetica:sheet_iron"},
            {"kinetica:sheet_iron", "",                    "kinetica:sheet_iron"},
            {"",                    "mcl_core:iron_ingot", ""},
        },
    })

    core.register_craft({
        output = "kinetica:smart_chute",
        recipe = {
            {"", "kinetica:sheet_gold", ""},
            {"", "kinetica:chute",      ""},
            {"", redstone_item,         ""},
        },
    })
end