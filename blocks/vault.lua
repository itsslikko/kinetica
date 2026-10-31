kinetica = kinetica or {}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

-- =========================================================
-- CUSTOMIZATION & CONFIGURATION HEADER
-- =========================================================
local CONFIG = {
    SLOTS_PER_VAULT_BLOCK         = 20,    -- 20 stacks (1,280 items) per individual Vault block
    MAX_CONNECTED_VAULTS          = 36,    -- Max Vault blocks that merge into a single multi-block pool
    BALANCE_INTERVAL              = 0.20,  -- Fast 0.20s tick so extractors never starve
    MAX_GLASSES_ITEM_ROWS         = 8,     -- How many sorted item rows to show in Engineer's Glasses
    DROP_CONTENTS_ON_DIG          = true,  -- Drop stored items if a Vault block is broken
    HIDE_INFOTEXT_WITHOUT_GLASSES = true,  -- Keep screen clean unless wearing Engineer's Glasses

    -- Textures (Customize these anytime; uses procedural metallic fallback if missing)
    TEX_VAULT_FRONT               = "kinetica_vault.png",
    TEX_VAULT_SIDE                = "kinetica_vault.png",
    TEX_VAULT_TOP                 = "kinetica_vault.png",
    FALLBACK_BASE_TEX             = "kinetica_andisite_casing.png",
}

local VAULT_NAME   = "kinetica:item_vault"
local raw_get_node = core.get_node

local ALL_6_DIRS = kinetica.directions or {
    {x =  1, y =  0, z =  0},
    {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0},
    {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1},
    {x =  0, y =  0, z = -1},
}

local HORIZ_DIRS = {
    {x =  1, y = 0, z =  0},
    {x = -1, y = 0, z =  0},
    {x =  0, y = 0, z =  1},
    {x =  0, y = 0, z = -1},
}

local function is_item_vault(name)
    return name == VAULT_NAME
end
kinetica.is_item_vault = is_item_vault

-- =========================================================
-- CLEAN ITEM NAME RESOLVER (FIXES MINECLONIA ESCAPE CODES)
-- =========================================================
local function clean_item_label(item_name)
    if not item_name or item_name == "" then
        return "Unknown Item"
    end

    local idef = core.registered_items[item_name]
    local raw  = (idef and (idef._tt_original_description or idef.short_description or idef.description)) or ""

    -- 1. Resolve Luanti translation strings if available
    if raw ~= "" and core.get_translated_string then
        local ok, trans = pcall(core.get_translated_string, "", raw)
        if ok and type(trans) == "string" and trans ~= "" then
            raw = trans
        end
    end

    -- 2. Strip color codes & translation escape sequences (\27(T@...)\27E)
    if raw ~= "" and core.strip_colors then
        raw = core.strip_colors(raw)
    end
    raw = string.gsub(raw, "\27%([^)]*%)", "")
    raw = string.gsub(raw, "\27.", "")

    -- 3. Take first non-empty line and trim
    local first_line = string.match(raw, "^%s*([^\r\n]+)") or ""
    first_line = string.gsub(first_line, "%s+$", "")

    -- 4. Fallback: convert "mcl_core:cobblestone" -> "Cobblestone" if description was empty/escaped
    if first_line == "" or string.find(first_line, "^[%s%p]*$") then
        local short_id = string.match(item_name, ":(.+)$") or item_name
        short_id = string.gsub(short_id, "_", " ")
        first_line = string.gsub(" " .. short_id, "%W%l", string.upper):sub(2)
    end

    return first_line
end

-- =========================================================
-- PROCEDURAL TEXTURE GENERATOR & CUSTOM PNG LOADER
-- =========================================================
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

local function get_vault_tiles()
    if file_exists(CONFIG.TEX_VAULT_FRONT) and file_exists(CONFIG.TEX_VAULT_SIDE) then
        local top = file_exists(CONFIG.TEX_VAULT_TOP) and CONFIG.TEX_VAULT_TOP or CONFIG.TEX_VAULT_SIDE
        return {
            top,
            top,
            CONFIG.TEX_VAULT_SIDE,
            CONFIG.TEX_VAULT_SIDE,
            CONFIG.TEX_VAULT_FRONT,
            CONFIG.TEX_VAULT_FRONT,
        }
    end

    local b = file_exists(CONFIG.FALLBACK_BASE_TEX) and CONFIG.FALLBACK_BASE_TEX or "kinetica_super_glue_box.png"
    local hull_bg    = slice_strip(b, "#2b333c", 235, 1,  1)
    local dark_seam  = slice_strip(b, "#161a1f", 245, 1,  16)
    local border_v   = slice_strip(b, "#161a1f", 245, 16, 1)
    local rib_h      = slice_strip(b, "#45515e", 215, 1,  8)
    local brass_lock = slice_strip(b, "#d99b26", 230, 4,  4)
    local lock_core  = slice_strip(b, "#21262d", 245, 8,  8)

    local side_tile = "[combine:16x16" ..
        ":0,0="  .. hull_bg ..
        ":0,3="  .. rib_h ..
        ":0,11=" .. rib_h ..
        ":0,0="  .. dark_seam ..
        ":0,7="  .. dark_seam ..
        ":0,15=" .. dark_seam ..
        ":0,0="  .. border_v ..
        ":15,0=" .. border_v

    local front_tile = side_tile ..
        ":6,6=" .. brass_lock ..
        ":7,7=" .. lock_core

    return {
        side_tile,  -- Top
        side_tile,  -- Bottom
        side_tile,  -- +X
        side_tile,  -- -X
        front_tile, -- +Z
        front_tile, -- -Z
    }
end

-- =========================================================
-- INVENTORY INITIALIZATION & MULTI-BLOCK CLUSTER DISCOVERY
-- =========================================================
local function ensure_vault_inventory(pos)
    local meta = core.get_meta(pos)
    local inv  = meta:get_inventory()
    if inv:get_size("main") ~= CONFIG.SLOTS_PER_VAULT_BLOCK then
        inv:set_size("main", CONFIG.SLOTS_PER_VAULT_BLOCK)
    end
    -- Also keep "dst" and "src" aliases synced for any Mineclonia hoppers that check furnace-style lists
    return meta, inv
end

local function get_vault_cluster(start_pos)
    local cluster = {}
    local queue   = {vector.round(start_pos)}
    local visited = {[core.hash_node_position(queue[1])] = true}

    local head = 1
    while head <= #queue and #cluster < CONFIG.MAX_CONNECTED_VAULTS do
        local cur = queue[head]
        head      = head + 1

        if raw_get_node(cur).name == VAULT_NAME then
            local meta, inv = ensure_vault_inventory(cur)
            cluster[#cluster + 1] = {pos = cur, meta = meta, inv = inv}

            for _, d in ipairs(ALL_6_DIRS) do
                local np = {x = cur.x + d.x, y = cur.y + d.y, z = cur.z + d.z}
                local hk = core.hash_node_position(np)
                if not visited[hk] and raw_get_node(np).name == VAULT_NAME then
                    visited[hk]       = true
                    queue[#queue + 1] = np
                end
            end
        end
    end

    table.sort(cluster, function(a, b)
        if a.pos.y ~= b.pos.y then return a.pos.y < b.pos.y end
        if a.pos.x ~= b.pos.x then return a.pos.x < b.pos.x end
        return a.pos.z < b.pos.z
    end)

    return cluster
end
kinetica.get_vault_cluster = get_vault_cluster

-- =========================================================
-- EXTRACTION HELPER & MULTI-BLOCK POOLING
-- =========================================================
-- Checks if a Vault block has an extractor (Chute/Hopper below, Funnel/PI on side)
local function has_attached_extractor(vpos)
    -- 1. Check below for Chute, Smart Chute, or Hopper
    local below_pos  = {x = vpos.x, y = vpos.y - 1, z = vpos.z}
    local below_name = raw_get_node(below_pos).name
    if (kinetica.is_chute and kinetica.is_chute(below_name)) or
       string.find(below_name, "chute") or
       string.find(below_name, "hopper") then
        local btimer = core.get_node_timer(below_pos)
        if btimer and not btimer:is_started() then
            btimer:start(0.20)
        end
        return true
    end

    -- 2. Check all 6 sides for Portable Interface or Funnel
    for _, d in ipairs(ALL_6_DIRS) do
        local npos  = {x = vpos.x + d.x, y = vpos.y + d.y, z = vpos.z + d.z}
        local nnode = raw_get_node(npos)
        local nname = nnode.name

        if kinetica.is_portable_interface and kinetica.is_portable_interface(nname) then
            return true
        end

        if (kinetica.is_funnel and kinetica.is_funnel(nname)) or string.find(nname, "funnel") then
            local ftimer = core.get_node_timer(npos)
            if ftimer and not ftimer:is_started() then
                ftimer:start(0.15)
            end
            return true
        end
    end

    return false
end

-- Feeds Mineclonia hoppers directly below the Vault if the hopper's own ABM hasn't pulled yet
local function try_push_to_hopper_below(vpos, vinv)
    if vinv:is_empty("main") then return end
    local below_pos  = {x = vpos.x, y = vpos.y - 1, z = vpos.z}
    local below_node = raw_get_node(below_pos)
    if not string.find(below_node.name or "", "hopper") then
        return
    end

    local hmeta = core.get_meta(below_pos)
    local hinv  = hmeta and hmeta:get_inventory()
    if not hinv then return end

    for _, hlist in ipairs({"main", "src"}) do
        if hinv:get_size(hlist) > 0 then
            local sz = vinv:get_size("main")
            for i = 1, sz do
                local st = vinv:get_stack("main", i)
                if not st:is_empty() then
                    local one = st:peek_item(1)
                    if hinv:room_for_item(hlist, one) then
                        hinv:add_item(hlist, one)
                        st:take_item(1)
                        vinv:set_stack("main", i, st)
                        return
                    end
                end
            end
        end
    end
end

local function balance_vault_cluster(cluster)
    -- Always assist any Hopper directly underneath a Vault block
    for _, entry in ipairs(cluster) do
        try_push_to_hopper_below(entry.pos, entry.inv)
    end

    if #cluster <= 1 then return end

    -- 1. Prioritize filling any Vault block that has an attached Extractor (Funnel/Chute/Hopper/PI)
    for _, dst in ipairs(cluster) do
        if has_attached_extractor(dst.pos) then
            -- Keep at least 2 stacks available in extractor-connected blocks whenever the cluster has items
            local occupied = 0
            local d_sz = dst.inv:get_size("main")
            for i = 1, d_sz do
                if not dst.inv:get_stack("main", i):is_empty() then
                    occupied = occupied + 1
                end
            end

            if occupied < 2 then
                for _, src in ipairs(cluster) do
                    if src ~= dst and not src.inv:is_empty("main") then
                        local s_sz = src.inv:get_size("main")
                        for i = s_sz, 1, -1 do
                            local st = src.inv:get_stack("main", i)
                            if not st:is_empty() and dst.inv:room_for_item("main", st) then
                                local leftover = dst.inv:add_item("main", st)
                                src.inv:set_stack("main", i, leftover)
                                occupied = occupied + 1
                                if occupied >= 2 then break end
                            end
                        end
                        if occupied >= 2 then break end
                    end
                end
            end
        end
    end

    -- 2. Share at least 1 stack to any completely empty Vault block so newly placed extractors work immediately
    for _, dst in ipairs(cluster) do
        if dst.inv:is_empty("main") then
            for _, src in ipairs(cluster) do
                if src ~= dst and not src.inv:is_empty("main") then
                    local sz = src.inv:get_size("main")
                    for i = sz, 1, -1 do
                        local st = src.inv:get_stack("main", i)
                        if not st:is_empty() then
                            dst.inv:set_stack("main", 1, st)
                            src.inv:set_stack("main", i, ItemStack(""))
                            break
                        end
                    end
                    break
                end
            end
        end
    end

    -- 3. Shift 1 stack out of any completely full Vault block so incoming Chutes/Funnels never jam
    for _, src in ipairs(cluster) do
        local has_empty_slot = false
        local sz = src.inv:get_size("main")
        for i = 1, sz do
            if src.inv:get_stack("main", i):is_empty() then
                has_empty_slot = true
                break
            end
        end

        if not has_empty_slot then
            local last_stack = src.inv:get_stack("main", sz)
            for _, dst in ipairs(cluster) do
                if dst ~= src and dst.inv:room_for_item("main", last_stack) then
                    local leftover = dst.inv:add_item("main", last_stack)
                    src.inv:set_stack("main", sz, leftover)
                    break
                end
            end
        end
    end
end

-- =========================================================
-- ENGINEER'S GLASSES TELEMETRY (CLEAN ITEM NAMES + COUNTS)
-- =========================================================
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

local function inspect_cluster_contents(cluster)
    local total_slots    = #cluster * CONFIG.SLOTS_PER_VAULT_BLOCK
    local used_slots     = 0
    local total_items    = 0
    local counts_by_name = {}

    for _, entry in ipairs(cluster) do
        local sz = entry.inv:get_size("main")
        for i = 1, sz do
            local st = entry.inv:get_stack("main", i)
            if not st:is_empty() then
                used_slots  = used_slots + 1
                local cnt   = st:get_count()
                local iname = st:get_name()
                total_items = total_items + cnt
                counts_by_name[iname] = (counts_by_name[iname] or 0) + cnt
            end
        end
    end

    local sorted = {}
    for iname, cnt in pairs(counts_by_name) do
        local idef = core.registered_items[iname]
        local smax = (idef and idef.stack_max and idef.stack_max > 0) and idef.stack_max or 64
        sorted[#sorted + 1] = {
            name      = iname,
            label     = clean_item_label(iname),
            count     = cnt,
            stack_max = smax,
        }
    end

    table.sort(sorted, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.label < b.label
    end)

    return total_items, used_slots, total_slots, sorted
end

kinetica._glasses_formatters = kinetica._glasses_formatters or {}

local LINE_TOP = "┌─ ENGINEER'S GLASSES ──────────────"
local LINE_CAP = "├─ VAULT CAPACITY ──────────────────"
local LINE_CNT = "├─ STORED ITEMS ────────────────────"
local LINE_BOT = "└───────────────────────────────────"

local function kv_row(label, value)
    return string.format("│  %-11s: %s", label, tostring(value))
end

local function format_vault_glasses_info(pos, node)
    local cluster = get_vault_cluster(pos)
    local total_items, used_slots, total_slots, sorted_items = inspect_cluster_contents(cluster)

    local state_str = "EMPTY"
    if used_slots >= total_slots and total_slots > 0 then
        state_str = "FULL"
    elseif total_items > 0 then
        state_str = "STORING ITEMS"
    end

    local lines = {
        LINE_TOP,
        "│  Item Vault",
        "│  ● STATE    : " .. state_str,
        LINE_CAP,
        kv_row("Multi-Block", string.format("%d Connected Block%s", #cluster, #cluster == 1 and "" or "s")),
        kv_row("Total Items", tostring(total_items)),
        kv_row("Stacks Used", string.format("%d / %d", used_slots, total_slots)),
        kv_row("Fill Level",  make_progress_bar(used_slots, total_slots)),
        LINE_CNT,
    }

    if #sorted_items == 0 then
        lines[#lines + 1] = "│  (Empty)"
    else
        local max_rows = CONFIG.MAX_GLASSES_ITEM_ROWS
        for i = 1, math.min(max_rows, #sorted_items) do
            local entry = sorted_items[i]
            lines[#lines + 1] = string.format("│  • %s x%d", entry.label, entry.count)
        end
        if #sorted_items > max_rows then
            lines[#lines + 1] = string.format("│  + %d more item type(s)...", #sorted_items - max_rows)
        end
    end

    lines[#lines + 1] = LINE_BOT
    return table.concat(lines, "\n")
end

kinetica._glasses_formatters[VAULT_NAME] = format_vault_glasses_info

local function update_vault_telemetry(pos)
    local cluster = get_vault_cluster(pos)
    balance_vault_cluster(cluster)

    if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        local total_items, used_slots, total_slots, _ = inspect_cluster_contents(cluster)
        for _, entry in ipairs(cluster) do
            entry.meta:set_string("infotext", string.format(
                "Item Vault (%d Block%s | %d Items | %d/%d Stacks)",
                #cluster, #cluster == 1 and "" or "s", total_items, used_slots, total_slots
            ))
        end
    end
end

-- =========================================================
-- NODE REGISTRATION (AUTOMATION-READY & HOPPER/CHUTE/FUNNEL SAFE)
-- =========================================================
local sound_metal = (mcl_sounds and mcl_sounds.node_sound_metal_defaults)
    and mcl_sounds.node_sound_metal_defaults()
    or  nil

core.register_node(VAULT_NAME, {
    description           = string.format("Item Vault (%d Stacks/Block | Piston-Safe Contraption Storage | View with Engineer's Glasses)", CONFIG.SLOTS_PER_VAULT_BLOCK),
    drawtype              = "normal",
    paramtype2            = "facedir",
    is_ground_content     = false,
    tiles                 = get_vault_tiles(),
    -- `container = 2` + `tubedevice = 1` ensures Mineclonia Hoppers, Funnels, Chutes, and PIs all recognize it
    groups = {
        handy          = 1,
        pickaxey       = 1,
        container      = 2,
        tubedevice     = 1,
        kinetica_vault = 1,
    },
    _mcl_hardness         = 3.0,
    _mcl_blast_resistance = 6.0,
    sounds                = sound_metal,

    on_construct = function(pos)
        ensure_vault_inventory(pos)
        update_vault_telemetry(pos)
        core.get_node_timer(pos):start(CONFIG.BALANCE_INTERVAL)
    end,

    after_dig_node = function(pos, oldnode, oldmetadata, digger)
        if CONFIG.DROP_CONTENTS_ON_DIG and oldmetadata and oldmetadata.inventory and oldmetadata.inventory.main then
            for _, stack in ipairs(oldmetadata.inventory.main) do
                local st = ItemStack(stack)
                if not st:is_empty() then
                    core.add_item(pos, st)
                end
            end
        end
        for _, d in ipairs(ALL_6_DIRS) do
            local np = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
            if raw_get_node(np).name == VAULT_NAME then
                update_vault_telemetry(np)
            end
        end
    end,

    -- Hopper & Automation callbacks (allow non-player / fake-player automation, block real players)
    allow_metadata_inventory_put = function(pos, listname, index, stack, player)
        if player and type(player.is_player) == "function" and player:is_player() and not player.is_fake_player then
            return 0
        end
        return stack:get_count()
    end,
    allow_metadata_inventory_take = function(pos, listname, index, stack, player)
        if player and type(player.is_player) == "function" and player:is_player() and not player.is_fake_player then
            return 0
        end
        return stack:get_count()
    end,
    allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
        if player and type(player.is_player) == "function" and player:is_player() and not player.is_fake_player then
            return 0
        end
        return count
    end,

    on_timer = function(pos, elapsed)
        update_vault_telemetry(pos)
        return true
    end,
})

core.register_lbm({
    label             = "Wake Kinetica Item Vaults on chunk load",
    name              = "kinetica:wake_item_vaults_lbm",
    nodenames         = {"group:kinetica_vault"},
    run_at_every_load = true,
    action = function(pos)
        ensure_vault_inventory(pos)
        local timer = core.get_node_timer(pos)
        if not timer:is_started() then
            timer:start(CONFIG.BALANCE_INTERVAL)
        end
    end,
})

-- =========================================================
-- CRAFTING RECIPE
-- =========================================================
local barrel_or_chest = core.registered_items["mcl_barrels:barrel_closed"]
    and "mcl_barrels:barrel_closed"
    or  (core.registered_items["mcl_chests:chest"] and "mcl_chests:chest" or "default:chest")

core.register_craft({
    output = VAULT_NAME,
    recipe = {
        {"", "kinetica:sheet_iron", ""},
        {"", barrel_or_chest,       ""},
        {"", "kinetica:sheet_iron", ""},
    },
})