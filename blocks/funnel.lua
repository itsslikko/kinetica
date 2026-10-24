kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

local CONFIG = {
    TIMER_INTERVAL             = 0.15,
    FAST_SIFT_INTERVAL         = 0.04,
    BELT_CAPTURE_HALF_WIDTH    = 0.76,
    HOLD_MATCHING_BELT_ITEMS   = true,
    FUNNEL_DEFAULT_STACK       = 16,
    SMART_FUNNEL_DEFAULT_STACK = 64,
    MAX_ENTITIES_AT_OUTLET     = 8,
    EJECT_IMMUNITY_SECONDS     = 1.25,
    MAX_CHUTE_TRACE_HEIGHT     = 32,
    SPAWN_TRANSFER_PARTICLES   = true,
    AUTO_SNAP_TO_CONTAINERS    = true,
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    EXTRACT_LISTS              = {"profit", "profit_bin", "output", "dst", "main", "contents", "input"},
    EXTRACT_SKIP_LISTS         = {hoe = true, seed = true, fuel = true, src = true, filter = true},
    INSERT_LISTS               = {"main", "contents", "input", "src", "fuel"},
    UI_COLORS = {
        BG_WINDOW  = "#14171D",
        BG_HEADER  = "#1F242D",
        BG_CARD    = "#1B2028",
        BG_INV     = "#171B22",
        ACCENT_CYN = "#00D4FF",
        ACCENT_AMB = "#FFB300",
        ACCENT_GRN = "#00E676",
        ACCENT_RED = "#FF5252",
        TEXT_TITLE = "#F5B041",
        TEXT_LABEL = "#ABB2B9",
        TEXT_VALUE = "#FFFFFF",
    },
    TEX_FUNNEL_TOP             = "kinetica_funnel_top.png",
    TEX_FUNNEL_SIDE            = "kinetica_funnel_side.png",
    TEX_FUNNEL_FRONT           = "kinetica_funnel_front.png",
    TEX_SMART_FUNNEL_TOP       = "kinetica_smart_funnel_top.png",
    TEX_SMART_FUNNEL_SIDE      = "kinetica_smart_funnel_side.png",
    TEX_SMART_FUNNEL_FRONT     = "kinetica_smart_funnel_front.png",
    FALLBACK_BASE_TEX          = "kinetica_steam_maker_down.png",
}

local FUNNEL_NAME            = "kinetica:funnel"
local FUNNEL_BELT_NAME       = "kinetica:funnel_belt"
local SMART_FUNNEL_NAME      = "kinetica:smart_funnel"
local SMART_FUNNEL_BELT_NAME = "kinetica:smart_funnel_belt"

local FILTER_SLOTS   = 3
local NORMAL_PRESETS = {1, 4, 8, 16}
local SMART_PRESETS  = {1, 8, 16, 32, 64}

local HORIZ_DIRS = {
    {x =  1, y = 0, z =  0},
    {x = -1, y = 0, z =  0},
    {x =  0, y = 0, z =  1},
    {x =  0, y = 0, z = -1},
}

local in_funnel_rc        = false
local active_funnel_nodes = {}

local function is_normal_funnel(name)
    return name == FUNNEL_NAME or name == FUNNEL_BELT_NAME
end

local function is_smart_funnel(name)
    return name == SMART_FUNNEL_NAME or name == SMART_FUNNEL_BELT_NAME
end

local function is_any_funnel(name)
    return is_normal_funnel(name) or is_smart_funnel(name)
end
kinetica.is_funnel = is_any_funnel

local function short_item_label(item_name)
    if not item_name or item_name == "" then return "None" end
    local idef = core.registered_items[item_name]
    local desc = (idef and idef.description) and string.match(idef.description, "^[^\n%(]+") or item_name
    return string.gsub(desc, "%s+$", "")
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

local function slice_strip(base_tex, hex, alpha, cols, rows)
    return base_tex .. "\\^[colorize\\:" .. hex .. "\\:" .. tostring(alpha) ..
           "\\^[sheet\\:" .. tostring(cols) .. "x" .. tostring(rows) .. "\\:0,0"
end

local function build_create_arch_tile(frame_hex, border_hex, highlight_hex, emblem_hex, is_belt_shifted)
    local b = CONFIG.FALLBACK_BASE_TEX
    local curtain_bg     = slice_strip(b, "#21242b", 245, 1,  1)
    local curtain_stripe = slice_strip(b, "#121418", 250, 16, 1)
    local pillar_fill    = slice_strip(b, frame_hex,     215, 8,  1)
    local border_v       = slice_strip(b, border_hex,    235, 16, 1)
    local highlight_v    = slice_strip(b, highlight_hex, 210, 16, 1)
    local header_fill    = slice_strip(b, frame_hex,     215, 1,  4)
    local border_h       = slice_strip(b, border_hex,    235, 1,  16)
    local highlight_h    = slice_strip(b, highlight_hex, 210, 1,  16)
    local emblem_box     = slice_strip(b, border_hex,    235, 4,  4)
    local emblem_core    = slice_strip(b, emblem_hex,    225, 8,  8)
    local hy = is_belt_shifted and 4 or 0

    return "[combine:16x16" ..
        ":0,0="  .. curtain_bg ..
        ":4,0="  .. curtain_stripe ..
        ":6,0="  .. curtain_stripe ..
        ":8,0="  .. curtain_stripe ..
        ":10,0=" .. curtain_stripe ..
        ":12,0=" .. curtain_stripe ..
        ":0," .. tostring(hy)     .. "=" .. border_h ..
        ":0," .. tostring(hy + 1) .. "=" .. header_fill ..
        ":0," .. tostring(hy + 1) .. "=" .. highlight_h ..
        ":0," .. tostring(hy + 4) .. "=" .. border_h ..
        ":0,0="  .. border_v ..
        ":1,0="  .. pillar_fill ..
        ":1,0="  .. highlight_v ..
        ":3,0="  .. border_v ..
        ":12,0=" .. border_v ..
        ":13,0=" .. pillar_fill ..
        ":14,0="  .. highlight_v ..
        ":15,0=" .. border_v ..
        ":6," .. tostring(hy + 1) .. "=" .. emblem_box ..
        ":7," .. tostring(hy + 2) .. "=" .. emblem_core
end

local function build_create_casing_tile(frame_hex, border_hex, highlight_hex)
    local b          = CONFIG.FALLBACK_BASE_TEX
    local plate_fill = slice_strip(b, frame_hex,     215, 1,  1)
    local border_v   = slice_strip(b, border_hex,    235, 16, 1)
    local border_h   = slice_strip(b, border_hex,    235, 1,  16)
    local inner_rib  = slice_strip(b, highlight_hex, 210, 8,  1)

    return "[combine:16x16" ..
        ":0,0="  .. plate_fill ..
        ":3,0="  .. inner_rib ..
        ":11,0=" .. inner_rib ..
        ":0,0="  .. border_v ..
        ":15,0=" .. border_v ..
        ":0,0="  .. border_h ..
        ":0,15=" .. border_h
end

local function get_funnel_tiles(is_smart, is_belt_variant)
    if not is_smart and file_exists(CONFIG.TEX_FUNNEL_FRONT) and file_exists(CONFIG.TEX_FUNNEL_SIDE) then
        local top = file_exists(CONFIG.TEX_FUNNEL_TOP) and CONFIG.TEX_FUNNEL_TOP or CONFIG.TEX_FUNNEL_SIDE
        return {top, top, CONFIG.TEX_FUNNEL_SIDE, CONFIG.TEX_FUNNEL_SIDE, top, CONFIG.TEX_FUNNEL_FRONT}
    elseif is_smart and file_exists(CONFIG.TEX_SMART_FUNNEL_FRONT) and file_exists(CONFIG.TEX_SMART_FUNNEL_SIDE) then
        local top = file_exists(CONFIG.TEX_SMART_FUNNEL_TOP) and CONFIG.TEX_SMART_FUNNEL_TOP or CONFIG.TEX_SMART_FUNNEL_SIDE
        return {top, top, CONFIG.TEX_SMART_FUNNEL_SIDE, CONFIG.TEX_SMART_FUNNEL_SIDE, top, CONFIG.TEX_SMART_FUNNEL_FRONT}
    end

    local frame_hex     = is_smart and "#e0ab3c" or "#848e96"
    local border_hex    = is_smart and "#684218" or "#363b40"
    local highlight_hex = is_smart and "#f7db7c" or "#aeb8c0"
    local emblem_hex    = is_smart and "#ffd859" or "#606870"

    local arch_tile   = build_create_arch_tile(frame_hex, border_hex, highlight_hex, emblem_hex, is_belt_variant)
    local casing_tile = build_create_casing_tile(frame_hex, border_hex, highlight_hex)

    if is_belt_variant then
        return {
            casing_tile,
            casing_tile,
            arch_tile,
            arch_tile,
            arch_tile,
            arch_tile,
        }
    else
        return {
            casing_tile,
            casing_tile,
            casing_tile,
            casing_tile,
            arch_tile,
            arch_tile,
        }
    end
end

local function normalize_funnel_param2(param2)
    return (param2 or 0) % 4
end

local function get_back_dir(param2)
    local d = core.facedir_to_dir(normalize_funnel_param2(param2)) or {x = 0, y = 0, z = 1}
    return {x = d.x, y = 0, z = d.z}
end

local function get_front_dir(param2)
    local b = get_back_dir(param2)
    return {x = -b.x, y = 0, z = -b.z}
end

local function is_belt_node_name(name)
    return (kinetica.is_belt and kinetica.is_belt(name)) or
           (core.get_item_group(name or "", "mechanical_belt") > 0)
end

local function is_depot_node_name(name)
    return name == "kinetica:depot" or
           (core.get_item_group(name or "", "kinetica_depot") > 0)
end

local function is_chute_node_name(name)
    return (kinetica.is_chute and kinetica.is_chute(name)) or
           name == "kinetica:chute" or
           name == "kinetica:smart_chute" or
           (core.get_item_group(name or "", "kinetica_chute") > 0 and not is_any_funnel(name))
end

local function has_belt_or_depot_underneath(pos)
    local bnode = core.get_node({x = pos.x, y = pos.y - 1, z = pos.z})
    return is_belt_node_name(bnode.name) or is_depot_node_name(bnode.name)
end

local function has_valid_container_or_chute(pos, node)
    node = node or core.get_node(pos)
    local name = node.name
    if not name or name == "air" or name == "ignore" or is_any_funnel(name) or is_belt_node_name(name) then
        return false
    end
    if is_chute_node_name(name) or is_depot_node_name(name) then
        return true
    end
    if core.get_item_group(name, "container") > 0 or
       string.find(name, "chest") or
       string.find(name, "barrel") or
       string.find(name, "shulker_box") or
       string.find(name, "hopper") or
       string.find(name, "furnace") or
       string.find(name, "smoker") or
       string.find(name, "blast_furnace") or
       string.find(name, "dispenser") or
       string.find(name, "dropper") then
        return true
    end
    local meta = core.get_meta(pos)
    local inv  = meta and meta:get_inventory()
    if not inv then return false end
    local lists = inv:get_lists()
    return (lists ~= nil and next(lists) ~= nil)
end

local function sync_funnel_shape_variant(pos, node)
    node = node or core.get_node(pos)
    if not is_any_funnel(node.name) then return node end

    local on_belt  = has_belt_or_depot_underneath(pos)
    local is_smart = is_smart_funnel(node.name)
    local p2       = normalize_funnel_param2(node.param2)

    local want_name
    if is_smart then
        want_name = on_belt and SMART_FUNNEL_BELT_NAME or SMART_FUNNEL_NAME
    else
        want_name = on_belt and FUNNEL_BELT_NAME or FUNNEL_NAME
    end

    if node.name ~= want_name or node.param2 ~= p2 then
        core.swap_node(pos, {name = want_name, param2 = p2})
        node.name   = want_name
        node.param2 = p2
    end
    return node
end

local function find_attached_container(pos, node)
    node = sync_funnel_shape_variant(pos, node)
    local p2   = normalize_funnel_param2(node.param2)
    local bdir = get_back_dir(p2)

    local back_same = {x = pos.x + bdir.x, y = pos.y, z = pos.z + bdir.z}
    local nd_same   = core.get_node(back_same)
    if has_valid_container_or_chute(back_same, nd_same) then
        return back_same, nd_same, "back"
    end

    local back_down = {x = pos.x + bdir.x, y = pos.y - 1, z = pos.z + bdir.z}
    local nd_down   = core.get_node(back_down)
    if has_valid_container_or_chute(back_down, nd_down) and not is_depot_node_name(nd_down.name) then
        return back_down, nd_down, "back_down"
    end

    if CONFIG.AUTO_SNAP_TO_CONTAINERS then
        for _, dy in ipairs({0, -1}) do
            for _, d in ipairs(HORIZ_DIRS) do
                local npos  = {x = pos.x + d.x, y = pos.y + dy, z = pos.z + d.z}
                local nnode = core.get_node(npos)
                if has_valid_container_or_chute(npos, nnode) and not is_depot_node_name(nnode.name) then
                    local new_p2 = normalize_funnel_param2(core.dir_to_facedir(d, false))
                    if node.param2 ~= new_p2 then
                        core.swap_node(pos, {name = node.name, param2 = new_p2})
                        node.param2 = new_p2
                    end
                    return npos, nnode, (dy == 0) and "back" or "back_down"
                end
            end
        end
    end

    local top_pos = {x = pos.x, y = pos.y + 1, z = pos.z}
    local top_nd  = core.get_node(top_pos)
    if has_valid_container_or_chute(top_pos, top_nd) then
        return top_pos, top_nd, "top"
    end

    return nil, nil, nil
end

local function place_funnel_node(itemstack, placer, pointed_thing)
    if not pointed_thing or pointed_thing.type ~= "node" then
        return itemstack
    end

    local under_pos  = pointed_thing.under
    local above_pos  = pointed_thing.above
    local under_node = core.get_node(under_pos)
    local under_def  = core.registered_nodes[under_node.name]
    local sneaking   = placer and placer:is_player() and placer:get_player_control().sneak

    if under_def and under_def.on_rightclick and not sneaking and not in_funnel_rc and
       not is_any_funnel(under_node.name) and
       not has_valid_container_or_chute(under_pos, under_node) and
       not is_belt_node_name(under_node.name) then
        return under_def.on_rightclick(under_pos, under_node, placer, itemstack, pointed_thing) or itemstack
    end

    local place_pos = (under_def and under_def.buildable_to) and under_pos or above_pos
    local diff = {
        x = above_pos.x - under_pos.x,
        y = above_pos.y - under_pos.y,
        z = above_pos.z - under_pos.z,
    }

    local back_dir = nil

    if diff.y == 0 and (diff.x ~= 0 or diff.z ~= 0) then
        if has_valid_container_or_chute(under_pos, under_node) or is_belt_node_name(under_node.name) then
            back_dir = {x = -diff.x, y = 0, z = -diff.z}
        end
    end

    if not back_dir then
        for _, dy in ipairs({0, -1}) do
            for _, d in ipairs(HORIZ_DIRS) do
                local npos  = {x = place_pos.x + d.x, y = place_pos.y + dy, z = place_pos.z + d.z}
                local nnode = core.get_node(npos)
                if has_valid_container_or_chute(npos, nnode) and not is_depot_node_name(nnode.name) then
                    back_dir = d
                    break
                end
            end
            if back_dir then break end
        end
    end

    if not back_dir then
        for _, dy in ipairs({0, -1}) do
            for _, d in ipairs(HORIZ_DIRS) do
                local npos  = {x = place_pos.x + d.x, y = place_pos.y + dy, z = place_pos.z + d.z}
                local nnode = core.get_node(npos)
                if is_belt_node_name(nnode.name) then
                    back_dir = {x = -d.x, y = 0, z = -d.z}
                    break
                end
            end
            if back_dir then break end
        end
    end

    if not back_dir then
        local look = placer and placer:get_look_dir() or {x = 0, y = 0, z = 1}
        if math.abs(look.x) >= math.abs(look.z) then
            back_dir = {x = (look.x >= 0) and 1 or -1, y = 0, z = 0}
        else
            back_dir = {x = 0, y = 0, z = (look.z >= 0) and 1 or -1}
        end
    end

    local param2 = normalize_funnel_param2(core.dir_to_facedir(back_dir, false))
    local placed_stack, placed_pos = core.item_place_node(itemstack, placer, pointed_thing, param2)
    if placed_pos then
        sync_funnel_shape_variant(placed_pos, core.get_node(placed_pos))
        active_funnel_nodes[core.hash_node_position(placed_pos)] = {
            x = placed_pos.x, y = placed_pos.y, z = placed_pos.z
        }
    end
    return placed_stack
end

local function ensure_funnel_meta(pos, is_smart)
    local meta = core.get_meta(pos)
    if meta:get_string("dir_mode") == "" then
        meta:set_string("dir_mode", "auto")
    end
    if meta:get_string("rs_mode") == "" then
        meta:set_string("rs_mode", "lock_on_power")
    end
    if meta:get_int("stack_size") <= 0 then
        meta:set_int("stack_size", is_smart and CONFIG.SMART_FUNNEL_DEFAULT_STACK or CONFIG.FUNNEL_DEFAULT_STACK)
    end
    if is_smart then
        local inv = meta:get_inventory()
        if inv:get_size("filter") ~= FILTER_SLOTS then
            inv:set_size("filter", FILTER_SLOTS)
        end
        if meta:get_string("filter_mode") == "" then
            meta:set_string("filter_mode", "whitelist")
        end
        if meta:get_string("exact_mode") == "" then
            meta:set_string("exact_mode", "upto")
        end
        if meta:get_string("match_type") == "" then
            meta:set_string("match_type", "exact_item")
        end
        return meta, inv
    end
    return meta, nil
end

local function has_redstone_signal(pos)
    if mcl_redstone and mcl_redstone.get_power then
        local ok, pwr = pcall(mcl_redstone.get_power, vector.new(pos.x, pos.y, pos.z))
        if ok and pwr and pwr > 0 then
            return true
        end
    end
    return false
end

local function is_funnel_paused_by_redstone(pos, meta)
    meta = meta or core.get_meta(pos)
    local powered = has_redstone_signal(pos)
    local rs_mode = meta:get_string("rs_mode")
    if rs_mode == "require_power" then
        return not powered
    else
        return powered
    end
end

local IGNORED_GROUPS = {
    handy = true, pickaxey = true, axey = true, shovely = true, swordy = true,
    hoey = true, shearsy = true, creative_breakable = true, building_block = true,
    deco_block = true, craftitem = true, dig_immediate = true, flammable = true,
    attached_node = true, fall_damage_add_percent = true, not_in_creative_inventory = true,
}

local function do_items_share_category(filter_name, cand_name)
    if filter_name == cand_name then return true end
    local fdef = core.registered_items[filter_name]
    local cdef = core.registered_items[cand_name]
    if not fdef or not cdef then return false end

    if fdef.groups and cdef.groups then
        for gname, gval in pairs(fdef.groups) do
            if gval and gval > 0 and not IGNORED_GROUPS[gname] and (cdef.groups[gname] or 0) > 0 then
                return true
            end
        end
    end

    local patterns = {"_ingot$", "_nugget$", "^mcl_raw_ores:", "_ore$", "stone_with_", "deepslate_with_", "_seeds$", "sapling"}
    for _, pat in ipairs(patterns) do
        if string.find(filter_name, pat) and string.find(cand_name, pat) then
            return true
        end
    end
    return false
end

local function has_any_filter_configured(pos, node)
    if not is_smart_funnel(node.name) then return false end
    local _, inv = ensure_funnel_meta(pos, true)
    for i = 1, FILTER_SLOTS do
        if not inv:get_stack("filter", i):is_empty() then
            return true
        end
    end
    return false
end

local function is_item_allowed_by_funnel(pos, node, item_name)
    if not item_name or item_name == "" then
        return false
    end
    local is_smart  = is_smart_funnel(node.name)
    local meta, inv = ensure_funnel_meta(pos, is_smart)
    if is_funnel_paused_by_redstone(pos, meta) then
        return false
    end
    if not is_smart then
        return true
    end

    local mode       = meta:get_string("filter_mode")
    local group_mode = (meta:get_string("match_type") == "group_match")

    local has_any_filter = false
    local matches_filter = false

    for i = 1, FILTER_SLOTS do
        local fstack = inv:get_stack("filter", i)
        if not fstack:is_empty() then
            has_any_filter = true
            local fname = fstack:get_name()
            if fname == item_name or (group_mode and do_items_share_category(fname, item_name)) then
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

local function get_funnel_transfer_settings(pos, node)
    local is_smart = is_smart_funnel(node.name)
    local meta, _  = ensure_funnel_meta(pos, is_smart)
    local batch    = meta:get_int("stack_size")
    if batch <= 0 then
        batch = is_smart and CONFIG.SMART_FUNNEL_DEFAULT_STACK or CONFIG.FUNNEL_DEFAULT_STACK
    end
    local exact = is_smart and (meta:get_string("exact_mode") == "exact") or false
    return math.max(1, math.min(64, batch)), exact
end

local function notify_container_updated(cpos, cnode)
    if mcl_redstone and mcl_redstone.update_comparators then
        pcall(mcl_redstone.update_comparators, vector.new(cpos.x, cpos.y, cpos.z))
    end
    local ct  = core.get_node_timer(cpos)
    local def = core.registered_nodes[cnode.name]
    if ct and not ct:is_started() and def and def.on_timer then
        ct:start(0.15)
    end
end

local function trace_container_above_chute_column(chute_pos)
    local cur = {x = chute_pos.x, y = chute_pos.y, z = chute_pos.z}
    for _ = 1, CONFIG.MAX_CHUTE_TRACE_HEIGHT do
        local above_pos  = {x = cur.x, y = cur.y + 1, z = cur.z}
        local above_node = core.get_node(above_pos)
        if is_chute_node_name(above_node.name) then
            cur = above_pos
        elseif has_valid_container_or_chute(above_pos, above_node) then
            return above_pos, above_node
        else
            break
        end
    end
    return nil, nil
end

local function get_container_inventories(cpos, cnode)
    cnode = cnode or core.get_node(cpos)

    if is_chute_node_name(cnode.name) then
        local top_cpos, top_cnode = trace_container_above_chute_column(cpos)
        if top_cpos and top_cnode then
            cpos  = top_cpos
            cnode = top_cnode
        else
            return {}
        end
    end

    local list = {}
    local meta = core.get_meta(cpos)
    local inv  = meta and meta:get_inventory()
    if inv then
        list[#list + 1] = {pos = cpos, node = cnode, inv = inv}
    end

    if string.find(cnode.name or "", "chest") then
        for _, hd in ipairs(HORIZ_DIRS) do
            local adj_pos  = {x = cpos.x + hd.x, y = cpos.y, z = cpos.z + hd.z}
            local adj_node = core.get_node(adj_pos)
            if string.find(adj_node.name or "", "chest") then
                local ainv = core.get_meta(adj_pos):get_inventory()
                if ainv and ainv:get_size("main") > 0 then
                    list[#list + 1] = {pos = adj_pos, node = adj_node, inv = ainv}
                    break
                end
            end
        end
    end
    return list
end

local function insert_stack_into_container_or_chute(cpos, cnode, stack, max_batch)
    if not stack or stack:is_empty() then
        return stack, 0
    end

    local to_push = ItemStack(stack)
    if to_push:get_count() > max_batch then
        to_push:set_count(max_batch)
    end
    local orig_push_cnt = to_push:get_count()

    if is_chute_node_name(cnode.name) then
        local spawn_p = {x = cpos.x, y = cpos.y + 0.20, z = cpos.z}
        local obj = core.add_item(spawn_p, to_push)
        if obj then
            obj:set_velocity({x = 0, y = -2.0, z = 0})
            notify_container_updated(cpos, cnode)
            stack:take_item(orig_push_cnt)
            return stack, orig_push_cnt
        end
        return stack, 0
    end

    local inv_entries = get_container_inventories(cpos, cnode)
    for _, entry in ipairs(inv_entries) do
        local cinv  = entry.inv
        local cname = entry.node.name

        if string.find(cname, ":feeder") then
            if cinv:get_size("seed") > 0 and cinv:room_for_item("seed", to_push) then
                to_push = cinv:add_item("seed", to_push)
            end
            if not to_push:is_empty() and cinv:get_size("profit") > 0 and cinv:room_for_item("profit", to_push) then
                to_push = cinv:add_item("profit", to_push)
            end
        elseif is_depot_node_name(cname) then
            if cinv:get_size("main") > 0 and cinv:room_for_item("main", to_push) then
                to_push = cinv:add_item("main", to_push)
            end
        else
            for _, lname in ipairs(CONFIG.INSERT_LISTS) do
                if cinv:get_size(lname) > 0 and cinv:room_for_item(lname, to_push) then
                    to_push = cinv:add_item(lname, to_push)
                    if to_push:is_empty() then break end
                end
            end

            if not to_push:is_empty() then
                local all_lists = cinv:get_lists()
                if all_lists then
                    for lname, _ in pairs(all_lists) do
                        if not CONFIG.EXTRACT_SKIP_LISTS[lname] and cinv:room_for_item(lname, to_push) then
                            to_push = cinv:add_item(lname, to_push)
                            if to_push:is_empty() then break end
                        end
                    end
                end
            end
        end

        if to_push:get_count() < orig_push_cnt then
            notify_container_updated(entry.pos, entry.node)
        end
        if to_push:is_empty() then
            break
        end
    end

    local inserted_cnt = orig_push_cnt - to_push:get_count()
    if inserted_cnt > 0 then
        stack:take_item(inserted_cnt)
    end
    return stack, inserted_cnt
end

local function get_extractable_lists_for_node(cnode, cinv)
    if string.find(cnode.name or "", ":feeder") then
        if cinv:get_size("profit") > 0 and not cinv:is_empty("profit") then
            return {"profit"}
        end
        return {}
    end

    local result = {}
    local seen   = {}
    for _, lname in ipairs(CONFIG.EXTRACT_LISTS) do
        if not CONFIG.EXTRACT_SKIP_LISTS[lname] then
            local sz = cinv:get_size(lname)
            if sz and sz > 0 and not cinv:is_empty(lname) then
                result[#result + 1] = lname
                seen[lname]         = true
            end
        end
    end

    local all_lists = cinv:get_lists()
    if all_lists then
        for lname, _ in pairs(all_lists) do
            if not seen[lname] and not CONFIG.EXTRACT_SKIP_LISTS[lname] and not cinv:is_empty(lname) then
                result[#result + 1] = lname
                seen[lname]         = true
            end
        end
    end

    return result
end

local function spawn_funnel_particles(pos, dir_vec, is_smart)
    if not CONFIG.SPAWN_TRANSFER_PARTICLES then return end
    local col = is_smart and "#ffb300:180" or "#d0d6dc:160"
    core.add_particlespawner({
        amount             = 3,
        time               = 0.10,
        minpos             = {x = pos.x - 0.12, y = pos.y - 0.35, z = pos.z - 0.12},
        maxpos             = {x = pos.x + 0.12, y = pos.y - 0.15, z = pos.z + 0.12},
        minvel             = {x = dir_vec.x * 0.4 - 0.1, y = -0.1, z = dir_vec.z * 0.4 - 0.1},
        maxvel             = {x = dir_vec.x * 0.9 + 0.1, y =  0.2, z = dir_vec.z * 0.9 + 0.1},
        minexptime         = 0.15,
        maxexptime         = 0.30,
        minsize            = 0.9,
        maxsize            = 1.5,
        collisiondetection = false,
        texture            = "bubble.png^[colorize:" .. col,
    })
end

local function record_last_sorted_item(pos, item_name, count)
    local meta = core.get_meta(pos)
    meta:set_string("last_sorted_item", string.format("%s x%d", short_item_label(item_name), count or 1))
end

local function deliver_stack_to_destination(pos, node, stack, dest_pos, out_dir, source_cpos)
    if not stack or stack:is_empty() then return 0 end

    local dnode = core.get_node(dest_pos)
    if has_valid_container_or_chute(dest_pos, dnode) and (not source_cpos or not vector.equals(dest_pos, source_cpos)) then
        local _, ins_cnt = insert_stack_into_container_or_chute(dest_pos, dnode, stack, stack:get_count())
        return ins_cnt
    end

    local below_dest = {x = dest_pos.x, y = dest_pos.y - 1, z = dest_pos.z}
    for _, cand in ipairs({dest_pos, below_dest, {x = pos.x, y = pos.y - 1, z = pos.z}}) do
        if not source_cpos or not vector.equals(cand, source_cpos) then
            local cn = core.get_node(cand)
            if is_depot_node_name(cn.name) then
                local dinv = core.get_meta(cand):get_inventory()
                if dinv and dinv:get_size("main") > 0 and dinv:room_for_item("main", stack) then
                    local leftover = dinv:add_item("main", stack)
                    local ins_cnt  = stack:get_count() - leftover:get_count()
                    if ins_cnt > 0 then
                        notify_container_updated(cand, cn)
                        return ins_cnt
                    end
                end
                return 0
            end
        end
    end

    local belt_target = nil
    for _, cand in ipairs({dest_pos, below_dest, {x = pos.x, y = pos.y - 1, z = pos.z}}) do
        if not source_cpos or not vector.equals(cand, source_cpos) then
            if is_belt_node_name(core.get_node(cand).name) then
                belt_target = cand
                break
            end
        end
    end

    local spawn_pt
    if belt_target then
        spawn_pt = {
            x = belt_target.x,
            y = belt_target.y + 0.32,
            z = belt_target.z,
        }
    else
        spawn_pt = {
            x = pos.x + out_dir.x * 0.48,
            y = pos.y - 0.20,
            z = pos.z + out_dir.z * 0.48,
        }
    end

    local nearby_items = 0
    for _, obj in ipairs(core.get_objects_inside_radius(spawn_pt, 0.36)) do
        local le = obj:get_luaentity()
        if le and le.name == "__builtin:item" and not le._kinetica_vacuumed then
            nearby_items = nearby_items + 1
            if belt_target then
                return 0
            end
        end
    end
    if nearby_items >= CONFIG.MAX_ENTITIES_AT_OUTLET then
        return 0
    end

    local obj = core.add_item(spawn_pt, stack)
    if obj then
        local le = obj:get_luaentity()
        if le then
            le._kinetica_ejected_by  = core.hash_node_position(pos)
            le._kinetica_eject_until = (core.get_us_time() / 1e6) + CONFIG.EJECT_IMMUNITY_SECONDS
        end
        if belt_target then
            obj:set_velocity({x = out_dir.x * 0.45, y = 0, z = out_dir.z * 0.45})
            local btimer = core.get_node_timer(belt_target)
            if btimer and not btimer:is_started() then
                btimer:start(0.05)
            end
        else
            obj:set_velocity({x = out_dir.x * 0.85, y = -0.6, z = out_dir.z * 0.85})
        end
        return stack:get_count()
    end

    return 0
end

local function find_side_output_target(pos, node, main_belt_pos)
    local bdir = get_back_dir(node.param2)
    local fdir = get_front_dir(node.param2)

    local cpos, cnode, _ = find_attached_container(pos, node)
    if cpos and cnode and (not main_belt_pos or not vector.equals(cpos, main_belt_pos)) then
        return cpos, cnode, bdir, "container"
    end

    if main_belt_pos then
        local mb_node = core.get_node(main_belt_pos)
        local mb_back = core.facedir_to_dir((mb_node.param2 or 0) % 4) or {x = 0, y = 0, z = 1}
        local side_dirs = {
            {x =  mb_back.z, y = 0, z = -mb_back.x},
            {x = -mb_back.z, y = 0, z =  mb_back.x},
            fdir,
            bdir,
        }
        for _, sd in ipairs(side_dirs) do
            for _, dy in ipairs({-1, 0}) do
                local cand = {x = pos.x + sd.x, y = pos.y + dy, z = pos.z + sd.z}
                local cn   = core.get_node(cand)
                if is_belt_node_name(cn.name) or is_depot_node_name(cn.name) or has_valid_container_or_chute(cand, cn) then
                    return cand, cn, sd, "side_branch"
                end
            end
        end
    end

    local out_pos = {x = pos.x + fdir.x, y = pos.y, z = pos.z + fdir.z}
    return out_pos, core.get_node(out_pos), fdir, "eject"
end

local function try_drag_matching_items_from_belt(pos, node, dir_mode)
    local max_batch, require_exact = get_funnel_transfer_settings(pos, node)
    local fdir     = get_front_dir(node.param2)
    local bdir     = get_back_dir(node.param2)
    local my_hash  = core.hash_node_position(pos)
    local now_sec  = core.get_us_time() / 1e6
    local on_belt  = has_belt_or_depot_underneath(pos)
    local is_smart = is_smart_funnel(node.name)

    local main_belt_pos = on_belt and {x = pos.x, y = pos.y - 1, z = pos.z} or nil
    local dest_pos, _, out_dir, dest_kind = find_side_output_target(pos, node, main_belt_pos)

    if on_belt and dir_mode == "auto" and dest_kind == "eject" and not has_any_filter_configured(pos, node) then
        return false
    end

    local scan_belts = {}
    if on_belt then
        scan_belts[#scan_belts + 1] = {x = pos.x, y = pos.y - 1, z = pos.z}
    end
    for _, d in ipairs({fdir, bdir}) do
        for _, dy in ipairs({0, -1}) do
            local bp = {x = pos.x + d.x, y = pos.y + dy, z = pos.z + d.z}
            if not dest_pos or not vector.equals(bp, dest_pos) then
                local bn = core.get_node(bp)
                if is_belt_node_name(bn.name) or is_depot_node_name(bn.name) then
                    scan_belts[#scan_belts + 1] = bp
                end
            end
        end
    end

    for _, bp in ipairs(scan_belts) do
        local bn = core.get_node(bp)
        if is_depot_node_name(bn.name) and (not dest_pos or not vector.equals(bp, dest_pos)) then
            local dinv = core.get_meta(bp):get_inventory()
            if dinv then
                for _, lname in ipairs({"output", "main"}) do
                    for i = 1, dinv:get_size(lname) do
                        local st = dinv:get_stack(lname, i)
                        if not st:is_empty() and is_item_allowed_by_funnel(pos, node, st:get_name()) then
                            if not require_exact or st:get_count() >= max_batch then
                                local pull_cnt  = require_exact and max_batch or math.min(st:get_count(), max_batch)
                                local iname     = st:get_name()
                                local delivered = deliver_stack_to_destination(pos, node, st:peek_item(pull_cnt), dest_pos, out_dir, bp)
                                if delivered > 0 then
                                    st:take_item(delivered)
                                    dinv:set_stack(lname, i, st)
                                    notify_container_updated(bp, bn)
                                    record_last_sorted_item(pos, iname, delivered)
                                    spawn_funnel_particles(pos, out_dir, is_smart)
                                    return true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local cap_hw    = CONFIG.BELT_CAPTURE_HALF_WIDTH
    local seen_objs = {}

    for _, bp in ipairs(scan_belts) do
        local scan_pt = {x = bp.x, y = bp.y + 0.30, z = bp.z}
        for _, obj in ipairs(core.get_objects_inside_radius(scan_pt, 0.90)) do
            if not seen_objs[obj] then
                seen_objs[obj] = true
                local le   = obj:get_luaentity()
                local opos = obj:get_pos()
                if le and opos and le.name == "__builtin:item" and
                   not le._kinetica_vacuumed and
                   le.itemstring and le.itemstring ~= "" then
                    local immune = (le._kinetica_ejected_by == my_hash) and
                                   (le._kinetica_eject_until and now_sec < le._kinetica_eject_until)
                    if not immune and
                       math.abs(opos.x - bp.x) <= cap_hw and
                       math.abs(opos.z - bp.z) <= cap_hw and
                       math.abs(opos.y - scan_pt.y) <= 0.65 then
                        local st = ItemStack(le.itemstring)
                        if not st:is_empty() then
                            local iname = st:get_name()
                            if is_item_allowed_by_funnel(pos, node, iname) then
                                local avail = st:get_count()
                                if not require_exact or avail >= max_batch then
                                    local pull_cnt  = require_exact and max_batch or math.min(avail, max_batch)
                                    local delivered = deliver_stack_to_destination(pos, node, st:peek_item(pull_cnt), dest_pos, out_dir, bp)
                                    if delivered > 0 then
                                        st:take_item(delivered)
                                        if st:is_empty() then
                                            le._kinetica_vacuumed = true
                                            le._kinetica_on_belt  = false
                                            le.itemstring         = ""
                                            obj:remove()
                                        else
                                            le.itemstring = st:to_string()
                                            if le.set_item then
                                                le:set_item(st:to_string())
                                            end
                                        end
                                        record_last_sorted_item(pos, iname, delivered)
                                        spawn_funnel_particles(pos, out_dir, is_smart)
                                        return true
                                    elseif CONFIG.HOLD_MATCHING_BELT_ITEMS then
                                        obj:set_velocity({x = 0, y = 0, z = 0})
                                        obj:set_pos({x = bp.x, y = opos.y, z = bp.z})
                                    end
                                elseif CONFIG.HOLD_MATCHING_BELT_ITEMS then
                                    obj:set_velocity({x = 0, y = 0, z = 0})
                                    obj:set_pos({x = bp.x, y = opos.y, z = bp.z})
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

local function try_funnel_extract_from_container_or_chute(pos, node, cpos, cnode)
    local max_batch, require_exact = get_funnel_transfer_settings(pos, node)
    local fdir     = get_front_dir(node.param2)
    local out_pos  = {x = pos.x + fdir.x, y = pos.y, z = pos.z + fdir.z}
    local my_hash  = core.hash_node_position(pos)
    local now_sec  = core.get_us_time() / 1e6
    local is_smart = is_smart_funnel(node.name)

    if is_chute_node_name(cnode.name) then
        for dy = 0, 1 do
            local ch_pt = {x = cpos.x, y = cpos.y + dy, z = cpos.z}
            for _, obj in ipairs(core.get_objects_inside_radius(ch_pt, 0.78)) do
                local le   = obj:get_luaentity()
                local opos = obj:get_pos()
                if le and opos and le.name == "__builtin:item" and
                   not le._kinetica_vacuumed and
                   le.itemstring and le.itemstring ~= "" then
                    local immune = (le._kinetica_ejected_by == my_hash) and
                                   (le._kinetica_eject_until and now_sec < le._kinetica_eject_until)
                    if not immune then
                        local st = ItemStack(le.itemstring)
                        if not st:is_empty() and is_item_allowed_by_funnel(pos, node, st:get_name()) then
                            local avail = st:get_count()
                            if not require_exact or avail >= max_batch then
                                local pull_cnt  = require_exact and max_batch or math.min(avail, max_batch)
                                local iname     = st:get_name()
                                local delivered = deliver_stack_to_destination(pos, node, st:peek_item(pull_cnt), out_pos, fdir, cpos)
                                if delivered > 0 then
                                    st:take_item(delivered)
                                    if st:is_empty() then
                                        le._kinetica_vacuumed = true
                                        le.itemstring         = ""
                                        obj:remove()
                                    else
                                        le.itemstring = st:to_string()
                                        if le.set_item then
                                            le:set_item(st:to_string())
                                        end
                                    end
                                    record_last_sorted_item(pos, iname, delivered)
                                    spawn_funnel_particles(pos, fdir, is_smart)
                                    return true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local inv_entries = get_container_inventories(cpos, cnode)
    for _, entry in ipairs(inv_entries) do
        local cinv   = entry.inv
        local elists = get_extractable_lists_for_node(entry.node, cinv)

        for _, lname in ipairs(elists) do
            local sz = cinv:get_size(lname)
            for i = 1, sz do
                local st = cinv:get_stack(lname, i)
                if not st:is_empty() and is_item_allowed_by_funnel(pos, node, st:get_name()) then
                    local avail = st:get_count()
                    if not require_exact or avail >= max_batch then
                        local pull_cnt  = require_exact and max_batch or math.min(avail, max_batch)
                        local iname     = st:get_name()
                        local out_cand  = st:peek_item(pull_cnt)
                        local delivered = deliver_stack_to_destination(pos, node, out_cand, out_pos, fdir, entry.pos)
                        if delivered > 0 then
                            st:take_item(delivered)
                            cinv:set_stack(lname, i, st)
                            notify_container_updated(entry.pos, entry.node)
                            record_last_sorted_item(pos, iname, delivered)
                            spawn_funnel_particles(pos, fdir, is_smart)
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

kinetica._glasses_formatters = kinetica._glasses_formatters or {}

local LINE_TOP = "┌─ ENGINEER'S GLASSES ──────────────"
local LINE_FLT = "├─ FILTER & SORTING ────────────────"
local LINE_DET = "├─ LOGISTICS DETAILS ───────────────"
local LINE_BOT = "└───────────────────────────────────"

local function kv_row(label, value)
    return string.format("│  %-11s: %s", label, tostring(value))
end

local function get_dir_mode_label(dir_mode)
    if dir_mode == "extract" then
        return "EXTRACT (Chest/Chute -> Belt)"
    elseif dir_mode == "insert" then
        return "DRAG / INSERT (Belt -> Side)"
    end
    return "AUTO (Belt Sorter & Chute Sync)"
end

local function get_rs_mode_label(rs_mode)
    if rs_mode == "require_power" then
        return "Pulse / Require Redstone"
    end
    return "Lock on Redstone"
end

local function format_funnel_glasses_info(pos, node)
    local is_smart  = is_smart_funnel(node.name)
    local meta, inv = ensure_funnel_meta(pos, is_smart)
    local paused    = is_funnel_paused_by_redstone(pos, meta)
    local dir_mode  = meta:get_string("dir_mode")
    local rs_mode   = meta:get_string("rs_mode")
    local batch     = meta:get_int("stack_size")
    local last_sort = meta:get_string("last_sorted_item")
    if last_sort == "" then last_sort = "None yet" end
    local on_belt   = has_belt_or_depot_underneath(pos)
    local cpos, cnode, _ = find_attached_container(pos, node)

    local cont_lbl = "Belt Sorter (No Chest)"
    if cpos and cnode then
        cont_lbl = short_item_label(cnode.name)
    end

    local state_str = paused and "PAUSED BY REDSTONE" or get_dir_mode_label(dir_mode)
    local mount_lbl = on_belt and "Full-Block Belt Tunnel" or "Side Archway Funnel"

    if not is_smart then
        return table.concat({
            LINE_TOP,
            "│  Andesite Funnel",
            "│  ● STATE    : " .. state_str,
            LINE_FLT,
            kv_row("Filter",     "Unfiltered (All Items)"),
            kv_row("Last Moved", last_sort),
            LINE_DET,
            kv_row("Mounting",   mount_lbl),
            kv_row("Connected",  cont_lbl),
            kv_row("Batch Size", "Up to " .. tostring(batch) .. " Items / Tick"),
            kv_row("Redstone",   get_rs_mode_label(rs_mode)),
            LINE_BOT,
        }, "\n")
    end

    local fmode      = meta:get_string("filter_mode")
    local exact      = (meta:get_string("exact_mode") == "exact")
    local group_mode = (meta:get_string("match_type") == "group_match")

    local slot_labels = {}
    local active_cnt  = 0
    for i = 1, FILTER_SLOTS do
        local s = inv and inv:get_stack("filter", i) or ItemStack("")
        if not s:is_empty() then
            active_cnt     = active_cnt + 1
            slot_labels[i] = short_item_label(s:get_name())
        else
            slot_labels[i] = "Empty"
        end
    end

    local mode_str = (active_cnt == 0)
        and "NONE SET (Allows All Items)"
        or  ((fmode == "blacklist") and "BLACKLIST (Block Listed)" or "WHITELIST (Allow Only)")

    return table.concat({
        LINE_TOP,
        "│  Smart Funnel (Brass/Gold Sorter)",
        "│  ● STATE    : " .. state_str,
        LINE_FLT,
        kv_row("Filter Mode", mode_str),
        kv_row("Match Rule",  group_mode and "CATEGORY / GROUP" or "EXACT ITEM"),
        kv_row("Filter [1]",  slot_labels[1]),
        kv_row("Filter [2]",  slot_labels[2]),
        kv_row("Filter [3]",  slot_labels[3]),
        kv_row("Last Sorted", last_sort),
        LINE_DET,
        kv_row("Mounting",    mount_lbl),
        kv_row("Connected",   cont_lbl),
        kv_row("Batch Size",  (exact and "Exact " or "Up to ") .. tostring(batch)),
        kv_row("Redstone",    get_rs_mode_label(rs_mode)),
        LINE_BOT,
    }, "\n")
end

kinetica._glasses_formatters[FUNNEL_NAME]            = format_funnel_glasses_info
kinetica._glasses_formatters[FUNNEL_BELT_NAME]       = format_funnel_glasses_info
kinetica._glasses_formatters[SMART_FUNNEL_NAME]      = format_funnel_glasses_info
kinetica._glasses_formatters[SMART_FUNNEL_BELT_NAME] = format_funnel_glasses_info

local function C(hex, text)
    return core.colorize(hex, tostring(text))
end

local function show_normal_funnel_formspec(pos, player)
    if not player or not player:is_player() then return end
    local meta, _  = ensure_funnel_meta(pos, false)
    local U        = CONFIG.UI_COLORS
    local paused   = is_funnel_paused_by_redstone(pos, meta)
    local dir_mode = meta:get_string("dir_mode")
    local rs_mode  = meta:get_string("rs_mode")
    local batch    = meta:get_int("stack_size")

    local status_str = paused
        and C(U.ACCENT_RED, "PAUSED BY REDSTONE (" .. get_rs_mode_label(rs_mode) .. ")")
        or  C(U.ACCENT_GRN, "ACTIVE — " .. get_dir_mode_label(dir_mode))

    local fs = {
        "size[8.8,4.8]",
        "bgcolor[" .. U.BG_WINDOW .. ";false]",
        "box[0,0;8.8,0.95;" .. U.BG_HEADER .. "]",
        "box[0,0.92;8.8,0.05;" .. (paused and U.ACCENT_RED or U.ACCENT_CYN) .. "]",
        "label[0.3,0.12;" .. C(U.TEXT_TITLE, "ANDESITE FUNNEL — LOGISTICS CONTROL MENU") .. "]",
        "label[0.3,0.48;" .. status_str .. "]",
        "box[0.2,1.15;8.4,2.60;" .. U.BG_CARD .. "]",
        "label[0.4,1.25;" .. C(U.ACCENT_CYN, "FLOW DIRECTION, BATCH SIZE & REDSTONE MODE:") .. "]",
        "button[0.4,1.72;5.3,0.85;cycle_dir;"   .. core.formspec_escape("Flow: " .. get_dir_mode_label(dir_mode)) .. "]",
        "button[5.9,1.72;2.5,0.85;cycle_stack;" .. core.formspec_escape("Batch: " .. batch .. " / Tick") .. "]",
        "button[0.4,2.70;8.0,0.85;cycle_rs;"    .. core.formspec_escape("Redstone: " .. get_rs_mode_label(rs_mode) .. " (Click to Switch)") .. "]",
        "button_exit[2.9,3.92;3.0,0.72;close_btn;Close Menu]",
    }

    local formname = "kinetica:funnel_ui_" .. core.pos_to_string(pos)
    core.show_formspec(player:get_player_name(), formname, table.concat(fs))
end

local function get_smart_funnel_formspec(pos)
    local meta, _    = ensure_funnel_meta(pos, true)
    local U          = CONFIG.UI_COLORS
    local paused     = is_funnel_paused_by_redstone(pos, meta)
    local dir_mode   = meta:get_string("dir_mode")
    local rs_mode    = meta:get_string("rs_mode")
    local fmode      = meta:get_string("filter_mode")
    local batch      = meta:get_int("stack_size")
    local exact      = (meta:get_string("exact_mode") == "exact")
    local group_mode = (meta:get_string("match_type") == "group_match")

    local status_str = paused
        and C(U.ACCENT_RED, "PAUSED BY REDSTONE (" .. get_rs_mode_label(rs_mode) .. ")")
        or  C(U.ACCENT_GRN, "ACTIVE — " .. get_dir_mode_label(dir_mode))

    local mode_btn_lbl  = (fmode == "blacklist") and "Filter: BLACKLIST" or "Filter: WHITELIST"
    local match_btn_lbl = group_mode and "Match: CATEGORY/GROUP" or "Match: EXACT ITEM"
    local exact_btn_lbl = exact and ("Count: EXACT " .. batch) or ("Count: UP TO " .. batch)
    local dir_btn_lbl   = "Flow: " .. get_dir_mode_label(dir_mode)
    local rs_btn_lbl    = "RS: " .. get_rs_mode_label(rs_mode)

    local slot_bg = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(3.4, 1.55, 3, 1) or ""
    local inv_bg1 = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(0.4, 5.15, 9, 3) or ""
    local inv_bg2 = mcl_formspec and mcl_formspec.get_itemslot_bg and mcl_formspec.get_itemslot_bg(0.4, 8.30, 9, 1) or ""

    local fs = {
        "size[9.8,9.4]",
        "bgcolor[" .. U.BG_WINDOW .. ";false]",
        "box[0,0;9.8,0.98;" .. U.BG_HEADER .. "]",
        "box[0,0.94;9.8,0.05;" .. (paused and U.ACCENT_RED or U.ACCENT_AMB) .. "]",
        "label[0.3,0.10;" .. C(U.TEXT_TITLE, "SMART FUNNEL — BELT TUNNEL SORTER & CHUTE FILTER") .. "]",
        "label[0.3,0.48;" .. status_str .. "]",
        "box[0.25,1.10;9.3,3.70;" .. U.BG_CARD .. "]",
        "label[0.45,1.18;" .. C(U.ACCENT_CYN, "3 GHOST FILTER SLOTS:") .. "]",
        slot_bg,
        "list[context;filter;3.4,1.55;3,1;]",
        "button[6.8,1.60;2.5,0.80;clear_filter;Clear Filter]",
        "button[0.45,2.68;2.9,0.80;toggle_mode;"  .. core.formspec_escape(mode_btn_lbl)  .. "]",
        "button[3.45,2.68;3.1,0.80;toggle_group;" .. core.formspec_escape(match_btn_lbl) .. "]",
        "button[6.65,2.68;1.2,0.80;cycle_stack;"  .. batch .. "]",
        "button[7.95,2.68;1.4,0.80;toggle_exact;" .. core.formspec_escape(exact_btn_lbl) .. "]",
        "button[0.45,3.65;5.1,0.82;cycle_dir;" .. core.formspec_escape(dir_btn_lbl) .. "]",
        "button[5.65,3.65;3.7,0.82;cycle_rs;"  .. core.formspec_escape(rs_btn_lbl)  .. "]",
        "box[0.25,4.92;9.3,4.35;" .. U.BG_INV .. "]",
        "label[0.40,4.82;" .. C(U.TEXT_LABEL, "Player Inventory (Filtered items drag off the belt, others pass straight through!)") .. "]",
        "list[current_player;main;0.4,5.15;9,3;9]",
        inv_bg1,
        "list[current_player;main;0.4,8.30;9,1;]",
        inv_bg2,
        "listring[current_player;main]",
        "listring[context;filter]",
    }

    return table.concat(fs)
end

local function update_funnel_infotext_and_ui(pos, node)
    node = sync_funnel_shape_variant(pos, node)
    local is_smart  = is_smart_funnel(node.name)
    local meta, inv = ensure_funnel_meta(pos, is_smart)
    local paused    = is_funnel_paused_by_redstone(pos, meta)
    local dir_mode  = meta:get_string("dir_mode")
    local batch     = meta:get_int("stack_size")
    local lock_tag  = paused and " [PAUSED]" or ""

    if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        if not is_smart then
            meta:set_string("infotext", string.format(
                "Andesite Funnel%s: %s (Batch %d | Right-Click for Menu)",
                lock_tag, get_dir_mode_label(dir_mode), batch
            ))
        else
            local fmode = (meta:get_string("filter_mode") == "blacklist") and "Blacklist" or "Whitelist"
            local names = {}
            for i = 1, FILTER_SLOTS do
                local s = inv:get_stack("filter", i)
                if not s:is_empty() then
                    names[#names + 1] = short_item_label(s:get_name())
                end
            end
            local fstr = (#names > 0) and table.concat(names, ", ") or "Any Item"
            meta:set_string("infotext", string.format(
                "Smart Funnel%s [%s | %s | Batch %d]: %s",
                lock_tag, get_dir_mode_label(dir_mode), fmode, batch, fstr
            ))
        end
    else
        meta:set_string("infotext", "")
    end

    if is_smart then
        meta:set_string("formspec", get_smart_funnel_formspec(pos))
    end
    meta:set_string("glasses_info", format_funnel_glasses_info(pos, node))
end

local fast_sift_accum = 0
core.register_globalstep(function(dtime)
    fast_sift_accum = fast_sift_accum + dtime
    if fast_sift_accum < CONFIG.FAST_SIFT_INTERVAL then
        return
    end
    fast_sift_accum = 0

    for hkey, fpos in pairs(active_funnel_nodes) do
        local fnode = core.get_node_or_nil(fpos)
        if fnode and is_any_funnel(fnode.name) then
            local meta = core.get_meta(fpos)
            if not is_funnel_paused_by_redstone(fpos, meta) then
                local dir_mode = meta:get_string("dir_mode")
                if dir_mode ~= "extract" then
                    if try_drag_matching_items_from_belt(fpos, fnode, dir_mode) then
                        meta:set_string("glasses_info", format_funnel_glasses_info(fpos, fnode))
                    end
                end
            end
        elseif fnode and fnode.name ~= "ignore" then
            active_funnel_nodes[hkey] = nil
        end
    end
end)

local function funnel_on_timer(pos, elapsed)
    local node = core.get_node(pos)
    if not is_any_funnel(node.name) then
        active_funnel_nodes[core.hash_node_position(pos)] = nil
        return false
    end

    active_funnel_nodes[core.hash_node_position(pos)] = {x = pos.x, y = pos.y, z = pos.z}
    node = sync_funnel_shape_variant(pos, node)
    local is_smart = is_smart_funnel(node.name)
    local meta, _  = ensure_funnel_meta(pos, is_smart)

    if not is_funnel_paused_by_redstone(pos, meta) then
        local dir_mode       = meta:get_string("dir_mode")
        local cpos, cnode, _ = find_attached_container(pos, node)

        if dir_mode == "insert" then
            try_drag_matching_items_from_belt(pos, node, dir_mode)
        elseif dir_mode == "extract" then
            if cpos and cnode then
                try_funnel_extract_from_container_or_chute(pos, node, cpos, cnode)
            else
                try_drag_matching_items_from_belt(pos, node, dir_mode)
            end
        else
            if not try_drag_matching_items_from_belt(pos, node, dir_mode) then
                if cpos and cnode then
                    try_funnel_extract_from_container_or_chute(pos, node, cpos, cnode)
                end
            end
        end
    end

    update_funnel_infotext_and_ui(pos, core.get_node(pos))
    core.get_node_timer(pos):start(CONFIG.TIMER_INTERVAL)
    return false
end

local function cycle_funnel_direction_mode(pos, node, player)
    local meta, _ = ensure_funnel_meta(pos, is_smart_funnel(node.name))
    local cur     = meta:get_string("dir_mode")
    local next_m  = "extract"
    if cur == "extract" then
        next_m = "insert"
    elseif cur == "insert" then
        next_m = "auto"
    end
    meta:set_string("dir_mode", next_m)
    update_funnel_infotext_and_ui(pos, node)

    if player and player:is_player() then
        core.chat_send_player(
            player:get_player_name(),
            "[Kinetica] Funnel Flow Mode: " .. get_dir_mode_label(next_m)
        )
    end
end

local function cycle_funnel_redstone_mode(pos, node)
    local meta, _ = ensure_funnel_meta(pos, is_smart_funnel(node.name))
    local cur     = meta:get_string("rs_mode")
    local next_rs = (cur == "require_power") and "lock_on_power" or "require_power"
    meta:set_string("rs_mode", next_rs)
    update_funnel_infotext_and_ui(pos, node)
end

local function on_normal_funnel_rightclick(pos, node, clicker, itemstack, pointed_thing)
    if not clicker or not clicker:is_player() then
        return itemstack
    end
    if itemstack and not itemstack:is_empty() then
        if in_funnel_rc then
            return core.item_place_node(itemstack, clicker, pointed_thing)
        end
        local wname = itemstack:get_name()
        if is_any_funnel(wname) then
            in_funnel_rc = true
            local res = place_funnel_node(itemstack, clicker, pointed_thing)
            in_funnel_rc = false
            return res
        elseif core.registered_nodes[wname] then
            return core.item_place_node(itemstack, clicker, pointed_thing)
        end
        return itemstack
    end

    if core.is_protected(pos, clicker:get_player_name()) then
        return itemstack
    end

    if clicker:get_player_control().sneak then
        cycle_funnel_direction_mode(pos, node, clicker)
    else
        show_normal_funnel_formspec(pos, clicker)
    end
    return itemstack
end

core.register_on_player_receive_fields(function(player, formname, fields)
    if string.sub(formname or "", 1, 23) ~= "kinetica:funnel_ui_" then
        return false
    end
    local pos = core.string_to_pos(string.sub(formname, 24))
    if not pos then return true end

    local pname = player:get_player_name()
    if core.is_protected(pos, pname) then return true end

    local node = core.get_node(pos)
    if not is_normal_funnel(node.name) then return true end

    local meta, _ = ensure_funnel_meta(pos, false)
    if fields.cycle_dir then
        cycle_funnel_direction_mode(pos, node, player)
        show_normal_funnel_formspec(pos, player)
    elseif fields.cycle_stack then
        local cur = meta:get_int("stack_size")
        local next_val = NORMAL_PRESETS[1]
        for i, v in ipairs(NORMAL_PRESETS) do
            if v == cur then
                next_val = NORMAL_PRESETS[(i % #NORMAL_PRESETS) + 1]
                break
            end
        end
        meta:set_int("stack_size", next_val)
        update_funnel_infotext_and_ui(pos, node)
        show_normal_funnel_formspec(pos, player)
    elseif fields.cycle_rs then
        cycle_funnel_redstone_mode(pos, node)
        show_normal_funnel_formspec(pos, player)
    end
    return true
end)

local function smart_allow_put(pos, listname, index, stack, player)
    if listname ~= "filter" then return 0 end
    if player and player:is_player() and core.is_protected(pos, player:get_player_name()) then
        return 0
    end
    local _, inv = ensure_funnel_meta(pos, true)
    inv:set_stack("filter", index, stack:peek_item(1))
    update_funnel_infotext_and_ui(pos, core.get_node(pos))
    return 0
end

local function smart_allow_take(pos, listname, index, stack, player)
    if listname ~= "filter" then return 0 end
    if player and player:is_player() and core.is_protected(pos, player:get_player_name()) then
        return 0
    end
    local _, inv = ensure_funnel_meta(pos, true)
    inv:set_stack("filter", index, ItemStack(""))
    update_funnel_infotext_and_ui(pos, core.get_node(pos))
    return 0
end

local function smart_allow_move(pos, from_list, from_index, to_list, to_index, count, player)
    if player and player:is_player() and core.is_protected(pos, player:get_player_name()) then
        return 0
    end
    if from_list == "filter" and to_list == "filter" then
        local _, inv = ensure_funnel_meta(pos, true)
        local s_from = inv:get_stack("filter", from_index)
        local s_to   = inv:get_stack("filter", to_index)
        inv:set_stack("filter", to_index, s_from)
        inv:set_stack("filter", from_index, s_to)
        update_funnel_infotext_and_ui(pos, core.get_node(pos))
    end
    return 0
end

local function smart_on_receive_fields(pos, formname, fields, sender)
    if sender and sender:is_player() and core.is_protected(pos, sender:get_player_name()) then
        return
    end
    local node      = core.get_node(pos)
    local meta, inv = ensure_funnel_meta(pos, true)

    if fields.toggle_mode then
        local cur = meta:get_string("filter_mode")
        meta:set_string("filter_mode", (cur == "blacklist") and "whitelist" or "blacklist")
        update_funnel_infotext_and_ui(pos, node)
    elseif fields.toggle_group then
        local cur = meta:get_string("match_type")
        meta:set_string("match_type", (cur == "group_match") and "exact_item" or "group_match")
        update_funnel_infotext_and_ui(pos, node)
    elseif fields.cycle_stack then
        local cur = meta:get_int("stack_size")
        local next_val = SMART_PRESETS[1]
        for i, v in ipairs(SMART_PRESETS) do
            if v == cur then
                next_val = SMART_PRESETS[(i % #SMART_PRESETS) + 1]
                break
            end
        end
        meta:set_int("stack_size", next_val)
        update_funnel_infotext_and_ui(pos, node)
    elseif fields.toggle_exact then
        local cur = meta:get_string("exact_mode")
        meta:set_string("exact_mode", (cur == "exact") and "upto" or "exact")
        update_funnel_infotext_and_ui(pos, node)
    elseif fields.cycle_dir then
        cycle_funnel_direction_mode(pos, node, sender)
    elseif fields.cycle_rs then
        cycle_funnel_redstone_mode(pos, node)
    elseif fields.clear_filter then
        for i = 1, FILTER_SLOTS do
            inv:set_stack("filter", i, ItemStack(""))
        end
        update_funnel_infotext_and_ui(pos, node)
    end
end

local WALL_FUNNEL_NODEBOX = {
    type  = "fixed",
    fixed = {
        {-8/16, -8/16,  1/16, -5/16,  8/16,  6/16},
        { 5/16, -8/16,  1/16,  8/16,  8/16,  6/16},
        {-5/16,  3/16,  1/16,  5/16,  8/16,  6/16},
        {-2/16,  4/16,  0.5/16, 2/16, 7/16,  1.5/16},
        {-8/16, -8/16,  0/16, -4/16, -6/16,  8/16},
        { 4/16, -8/16,  0/16,  8/16, -6/16,  8/16},
        {-7/16, -4/16,  6/16,  7/16,  7/16,  8/16},
        {-5/16, -7/16,  2.5/16, 5/16, 3/16,  5.5/16},
    },
}

local WALL_SELECTION_BOX = {
    type  = "fixed",
    fixed = {-8/16, -8/16, 0/16, 8/16, 8/16, 8/16},
}

local BELT_FUNNEL_NODEBOX = {
    type  = "fixed",
    fixed = {
        {-8/16,   0/16, -8/16,  8/16,  4/16,  8/16},
        {-8/16, -12/16, -8/16, -5/16,  0/16, -5/16},
        { 5/16, -12/16, -8/16,  8/16,  0/16, -5/16},
        {-8/16, -12/16,  5/16, -5/16,  0/16,  8/16},
        { 5/16, -12/16,  5/16,  8/16,  0/16,  8/16},
        {-5/16, -11/16, -7/16,   5/16,  0/16, -5.5/16},
        {-5/16, -11/16,  5.5/16, 5/16,  0/16,  7/16},
        {-7/16, -11/16, -5/16,  -5.5/16, 0/16, 5/16},
        { 5.5/16,-11/16, -5/16,  7/16,  0/16,  5/16},
    },
}

local BELT_SELECTION_BOX = {
    type  = "fixed",
    fixed = {-8/16, -12/16, -8/16, 8/16, 4/16, 8/16},
}

local sound_metal = (mcl_sounds and mcl_sounds.node_sound_metal_defaults)
    and mcl_sounds.node_sound_metal_defaults()
    or  nil

local function register_funnel_pair(base_name, belt_name, desc, is_smart)
    local common_groups = {
        handy           = 1,
        pickaxey        = 1,
        axey            = 1,
        deco_block      = 1,
        kinetica_chute  = 1,
        kinetica_funnel = 1,
    }
    if is_smart then
        common_groups.smart_funnel = 1
    end

    local belt_groups = table.copy(common_groups)
    belt_groups.not_in_creative_inventory = 1

    local wall_tiles = get_funnel_tiles(is_smart, false)
    local belt_tiles = get_funnel_tiles(is_smart, true)

    local function make_def(is_belt_variant)
        return {
            description           = desc,
            drawtype              = "nodebox",
            node_box              = is_belt_variant and BELT_FUNNEL_NODEBOX or WALL_FUNNEL_NODEBOX,
            selection_box         = is_belt_variant and BELT_SELECTION_BOX  or WALL_SELECTION_BOX,
            walkable              = false,
            paramtype             = "light",
            paramtype2            = "facedir",
            sunlight_propagates   = true,
            use_texture_alpha     = "clip",
            is_ground_content     = false,
            tiles                 = is_belt_variant and belt_tiles or wall_tiles,
            drop                  = base_name,
            on_place              = (not is_belt_variant) and place_funnel_node or nil,
            on_rightclick         = (not is_smart) and on_normal_funnel_rightclick or nil,
            groups                = is_belt_variant and belt_groups or common_groups,
            sounds                = sound_metal,
            _mcl_blast_resistance = is_smart and 3.5 or 3.0,
            _mcl_hardness         = is_smart and 2.5 or 2.0,

            on_construct = function(pos)
                active_funnel_nodes[core.hash_node_position(pos)] = {x = pos.x, y = pos.y, z = pos.z}
                ensure_funnel_meta(pos, is_smart)
                find_attached_container(pos, core.get_node(pos))
                update_funnel_infotext_and_ui(pos, core.get_node(pos))
                core.get_node_timer(pos):start(CONFIG.TIMER_INTERVAL)
            end,

            on_destruct = function(pos)
                active_funnel_nodes[core.hash_node_position(pos)] = nil
            end,

            allow_metadata_inventory_put  = is_smart and smart_allow_put  or nil,
            allow_metadata_inventory_take = is_smart and smart_allow_take or nil,
            allow_metadata_inventory_move = is_smart and smart_allow_move or nil,
            on_receive_fields             = is_smart and smart_on_receive_fields or nil,
            on_timer                      = funnel_on_timer,
        }
    end

    core.register_node(base_name, make_def(false))
    core.register_node(belt_name, make_def(true))
end

register_funnel_pair(
    FUNNEL_NAME,
    FUNNEL_BELT_NAME,
    "Andesite Funnel (Belt Tunnel & Side Sorter | Pulls from Chests & Chutes | Right-Click Menu)",
    false
)

register_funnel_pair(
    SMART_FUNNEL_NAME,
    SMART_FUNNEL_BELT_NAME,
    "Smart Funnel (Brass/Gold Belt Tunnel & Side Sorter | 3-Slot Filter, Category Match & Chute Support)",
    true
)

core.register_on_mods_loaded(function()
    for nname, ndef in pairs(core.registered_nodes) do
        if ndef.on_rightclick and not is_any_funnel(nname) and
           (is_belt_node_name(nname) or is_depot_node_name(nname) or is_chute_node_name(nname) or
            core.get_item_group(nname, "container") > 0 or
            string.find(nname, "chest") or string.find(nname, "barrel") or string.find(nname, "hopper")) then
            local orig_rc = ndef.on_rightclick
            core.override_item(nname, {
                on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
                    if itemstack and not itemstack:is_empty() and is_any_funnel(itemstack:get_name()) then
                        return place_funnel_node(itemstack, clicker, pointed_thing)
                    end
                    return orig_rc(pos, node, clicker, itemstack, pointed_thing)
                end,
            })
        end
    end
end)

core.register_lbm({
    label             = "Wake kinetica Funnels & Smart Funnels on chunk load",
    name              = "kinetica:wake_funnels_lbm",
    nodenames         = {"group:kinetica_funnel"},
    run_at_every_load = true,
    action = function(pos, node)
        active_funnel_nodes[core.hash_node_position(pos)] = {x = pos.x, y = pos.y, z = pos.z}
        ensure_funnel_meta(pos, is_smart_funnel(node.name))
        update_funnel_infotext_and_ui(pos, node)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.TIMER_INTERVAL)
        end
    end,
})

local redstone_item = core.registered_items["mcl_redstone:redstone"]
    and "mcl_redstone:redstone"
    or  "mesecons:redstone"

core.register_craft({
    output = FUNNEL_NAME .. " 2",
    recipe = {
        {"", "kinetica:andesite_alloy", ""},
        {"", "kinetica:sheet_iron",     ""},
        {"", "mcl_ocean:dried_kelp",        ""},
    },
})

core.register_craft({
    output = SMART_FUNNEL_NAME,
    recipe = {
        {"", "kinetica:sheet_gold", ""},
        {"", FUNNEL_NAME,               ""},
        {"", redstone_item,             ""},
    },
})

core.register_craft({
    output = SMART_FUNNEL_NAME .. " 2",
    recipe = {
        {"",            "kinetica:sheet_gold",  ""},
        {redstone_item, "kinetica:gold_casing", redstone_item},
        {"",            "mcl_ocean:dried_kelp",     ""},
    },
})