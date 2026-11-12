-- kinetica/blocks/glasses.lua
kinetica = kinetica or {}

local CONFIG = {
    REQUIRE_HEAD_ARMOR_SLOT = true,  -- Strictly worn on the Head slot (or toggled headband state)
    ALLOW_RIGHTCLICK_EQUIP  = true,  -- Right-click in hand to snap onto your head
    HIDE_DEFAULT_INFOTEXT   = false,
    HUD_SCAN_INTERVAL       = 0.10,
    HUD_HOLD_SECONDS        = 0.30,
    HUD_REACH_DISTANCE      = 10.0,
    HUD_POS_X               = 0.015,
    HUD_POS_Y               = 0.28,
    HUD_OFFSET_X            = 10,
    HUD_OFFSET_Y            = 0,
    COLORS = {
        ACTIVE   = 0x00E676,
        IDLE     = 0xFFB300,
        DANGER   = 0xFF5252,
        LOGISTIC = 0x00D4FF,
    },
    TEX_GLASSES_ICON        = "kinetica_glass.png",
    TEX_HEADBAND_ARMOR      = "kinetica_glasses_armor.png",
    TEX_FALLBACK_ICON       = "kinetica_shaft_connecting_overlay.png^[sheet:1x4:0,0^[colorize:#ffb300:150",
}

local modname = core.get_current_modname() or "kinetica"
local modpath = core.get_modpath(modname) or ""

local function file_exists(filename)
    local f = io.open(modpath .. "/textures/" .. filename, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local GLASSES_ICON = file_exists(CONFIG.TEX_GLASSES_ICON)
    and CONFIG.TEX_GLASSES_ICON
    or  CONFIG.TEX_FALLBACK_ICON

-- Procedural 64x32 armor skin texture for the headband if custom armor PNG is missing
local HEADBAND_ARMOR_TEX = file_exists(CONFIG.TEX_HEADBAND_ARMOR)
    and CONFIG.TEX_HEADBAND_ARMOR
    or  ("[combine:64x32:0,0=(" .. GLASSES_ICON .. "\\^[resize\\:32x16)")

local function is_kinetica_node_name(name)
    return type(name) == "string" and string.sub(name, 1, 9) == "kinetica:"
end

local function is_glasses_item(name)
    return name == "kinetica:glasses" or name == "kinetica:goggles"
end

-- ============================================================================
-- 1. HEADWEAR DETECTION & EQUIPPING (MINECLONIA + 3D_ARMOR + FALLBACK)
-- ============================================================================

local function get_head_armor_slot_index(player, inv)
    if not inv then return nil end
    local armor_size = inv:get_size("armor")
    if armor_size and armor_size > 0 then
        -- In both Mineclonia (mcl_armor) and 3d_armor, Slot 1 is ALWAYS the Head slot!
        return 1, "armor"
    end
    return nil, nil
end

function kinetica.player_has_glasses(player)
    if not player or not player:is_player() then
        return false
    end

    local pmeta = player:get_meta()
    if pmeta and pmeta:get_int("kinetica_glasses_forced") == 1 then
        return true
    end

    local inv = player:get_inventory()
    if inv then
        -- Check standard "armor" inventory list (Mineclonia & 3d_armor)
        local armor_size = inv:get_size("armor")
        if armor_size and armor_size > 0 then
            -- Check Slot 1 (Head) specifically first, then scan all armor slots just in case
            local head_stack = inv:get_stack("armor", 1)
            if head_stack and is_glasses_item(head_stack:get_name()) then
                return true
            end
            for i = 1, armor_size do
                local st = inv:get_stack("armor", i)
                if st and is_glasses_item(st:get_name()) then
                    return true
                end
            end
            if CONFIG.REQUIRE_HEAD_ARMOR_SLOT then
                return false
            end
        end
    end

    -- Fallback for games without an "armor" inventory list: use player metadata headband state
    if pmeta and pmeta:get_int("kinetica_glasses_worn") == 1 then
        return true
    end

    if not CONFIG.REQUIRE_HEAD_ARMOR_SLOT and inv then
        return inv:contains_item("main", "kinetica:glasses") or
               inv:contains_item("main", "kinetica:goggles")
    end

    return false
end

local function refresh_armor_visuals(user)
    if mcl_armor then
        if type(mcl_armor.update) == "function" then
            pcall(mcl_armor.update, user)
        end
        if type(mcl_armor.update_player_visuals) == "function" then
            pcall(mcl_armor.update_player_visuals, user)
        end
    elseif rawget(_G, "armor") and type(armor.set_player_armor) == "function" then
        pcall(armor.set_player_armor, armor, user)
    end
end

local function equip_glasses_to_head_slot(itemstack, user)
    if not CONFIG.ALLOW_RIGHTCLICK_EQUIP or not user or not user:is_player() then
        return itemstack
    end

    local inv   = user:get_inventory()
    local pname = user:get_player_name()
    local hslot, listname = get_head_armor_slot_index(user, inv)

    if hslot and listname then
        local current_head = inv:get_stack(listname, hslot)
        if is_glasses_item(current_head:get_name()) then
            -- Unequip if already wearing and right-clicking with another pair, or notify
            core.chat_send_player(pname, "[Kinetica] Engineer's Glasses are already equipped on your head!")
            return itemstack
        end

        local to_equip = itemstack:peek_item(1)
        itemstack:take_item(1)
        inv:set_stack(listname, hslot, to_equip)

        refresh_armor_visuals(user)

        core.sound_play("default_place_node_hard", {pos = user:get_pos(), max_hear_distance = 8, gain = 0.5}, true)
        core.chat_send_player(pname, "[Kinetica] Equipped Engineer's Glasses on your head!")

        if not current_head:is_empty() then
            if itemstack:is_empty() then
                return current_head
            elseif inv:room_for_item("main", current_head) then
                inv:add_item("main", current_head)
            else
                core.add_item(user:get_pos(), current_head)
            end
        end
        return itemstack
    end

    -- Fallback toggle if no armor mod is present
    local pmeta  = user:get_meta()
    local next_v = (pmeta:get_int("kinetica_glasses_worn") == 1) and 0 or 1
    pmeta:set_int("kinetica_glasses_worn", next_v)
    core.sound_play("default_place_node_hard", {pos = user:get_pos(), max_hear_distance = 8, gain = 0.5}, true)
    core.chat_send_player(
        pname,
        next_v == 1
            and "[Kinetica] Equipped Engineer's Glasses (Headband Active)."
            or  "[Kinetica] Unequipped Engineer's Glasses."
    )
    return itemstack
end

-- ============================================================================
-- 2. ITEM REGISTRATION (HEAD ARMOR COMPATIBLE)
-- ============================================================================

local glasses_def = {
    description         = "Kinetic Engineer's Glasses (Headband)\nEquip in your Head Armor Slot (or Right-Click in hand) to view live machine telemetry on the left side.",
    inventory_image     = GLASSES_ICON,
    wield_image         = GLASSES_ICON,
    stack_max           = 1,
    groups              = {
        armor             = 1,
        armor_head        = 1,
        mcl_armor_head    = 1,
        combat_armor      = 1,
        combat_armor_head = 1,
        mcl_armor_points  = 1,
        mcl_armor_uses    = 0,
    },
    _mcl_armor_element  = "head",
    _mcl_armor_texture  = HEADBAND_ARMOR_TEX,
    on_secondary_use    = function(itemstack, user, pointed_thing)
        return equip_glasses_to_head_slot(itemstack, user)
    end,
    on_place            = function(itemstack, placer, pointed_thing)
        if pointed_thing and pointed_thing.type == "node" and pointed_thing.under then
            local unode = core.get_node(pointed_thing.under)
            local udef  = core.registered_nodes[unode.name]
            if udef and udef.on_rightclick and not (placer and placer:get_player_control().sneak) then
                return udef.on_rightclick(pointed_thing.under, unode, placer, itemstack, pointed_thing) or itemstack
            end
        end
        return equip_glasses_to_head_slot(itemstack, placer)
    end,
}

if core.registered_items["kinetica:glasses"] then
    core.override_item("kinetica:glasses", glasses_def)
else
    core.register_tool("kinetica:glasses", glasses_def)
    core.register_craft({
        output = "kinetica:glasses",
        recipe = {
            {"mcl_core:glass", "mcl_core:gold_ingot", "mcl_core:glass"},
            {"",               "mcl_core:stick",      ""},
        },
    })
end

core.register_alias("kinetica:goggles", "kinetica:glasses")

-- ============================================================================
-- 3. UNIVERSAL FALLBACK TELEMETRY BUILDER
-- Guarantees that Shafts, Gearboxes, Water Wheels, Pipes, etc. ALWAYS show data
-- ============================================================================

local function build_universal_kinetica_telemetry(pos, node)
    local meta = core.get_meta(pos)
    
    -- 1. Check if the block already wrote its own glasses_info string to metadata
    local stored = meta:get_string("glasses_info")
    if stored and stored ~= "" then
        return stored
    end

    -- 2. Otherwise dynamically build a clean Engineer's Glasses panel from its network metadata!
    local ndef = core.registered_nodes[node.name]
    local raw_desc = (ndef and ndef.description) and string.match(ndef.description, "^[^\n%(]+") or node.name
    raw_desc = string.gsub(raw_desc, "%s+$", "")

    local overstressed = (meta:get_int("network_overstressed") == 1)
    local rpm          = meta:get_float("rpm")
    local src_rpm      = meta:get_float("source_rpm")
    if rpm <= 0 and src_rpm > 0 then rpm = src_rpm end

    local supply_ku    = meta:get_int("network_supply_ku")
    local src_ku       = meta:get_int("source_ku")
    if supply_ku <= 0 and src_ku > 0 then supply_ku = src_ku end

    local used_ku      = meta:get_int("network_used_ku")
    local avail_ku     = meta:get_int("rotational_power")
    if avail_ku <= 0 and supply_ku > 0 and not overstressed then
        avail_ku = math.max(0, supply_ku - used_ku)
    end

    local spin_dir     = meta:get_int("spin_dir")
    if spin_dir == 0 then spin_dir = meta:get_int("source_spin") end
    local spin_str     = (spin_dir == 1) and "CW" or ((spin_dir == -1) and "CCW" or "Stopped")

    local infotext     = meta:get_string("infotext")
    if infotext == "" then infotext = meta:get_string("_kinetica_raw_infotext") end

    local state_str = "IDLE"
    if overstressed or string.find(infotext, "OVERSTRESSED") or string.find(infotext, "OVERLOADED") or string.find(infotext, "JAMMED") then
        state_str = "OVERSTRESSED / JAMMED"
    elseif rpm > 0 or string.find(infotext, "ACTIVE") or string.find(infotext, "BOILING") then
        state_str = "ACTIVE"
    end

    local T = kinetica.api and kinetica.api.telemetry
    local kv = (T and T.kv_row) or function(k, v) return string.format("│  %-11s: %s", k, tostring(v)) end
    local bar = (T and T.draw_progress_bar) or function(u, t) return string.format("%d / %d", u or 0, t or 0) end

    local lines = {
        "┌─ ENGINEER'S GLASSES ──────────────",
        "│  " .. raw_desc,
        "│  ● STATE    : " .. state_str,
    }

    if supply_ku > 0 or rpm > 0 or overstressed then
        lines[#lines + 1] = "├─ KINETIC NETWORK ─────────────────"
        lines[#lines + 1] = kv("Speed",      string.format("%.1f RPM (%s)", rpm, spin_str))
        lines[#lines + 1] = kv("Net Pool",   string.format("%d / %d KU Avail", avail_ku, supply_ku))
        lines[#lines + 1] = kv("Net Stress", bar(used_ku, supply_ku, 10))
    end

    if infotext ~= "" then
        lines[#lines + 1] = "├─ DETAILS ─────────────────────────"
        lines[#lines + 1] = "│  " .. infotext
    end

    lines[#lines + 1] = "└───────────────────────────────────"
    return table.concat(lines, "\n")
end

-- ============================================================================
-- 4. HUD SCANNER & RENDERING LOOP
-- ============================================================================

local active_huds = {}
local scan_timer  = 0

core.register_on_leaveplayer(function(player)
    if player then
        active_huds[player:get_player_name()] = nil
    end
end)

core.register_globalstep(function(dtime)
    scan_timer = scan_timer + dtime
    if scan_timer < CONFIG.HUD_SCAN_INTERVAL then
        return
    end
    scan_timer = 0
    local now_us = core.get_us_time() / 1e6

    for _, player in ipairs(core.get_connected_players()) do
        local pname       = player:get_player_name()
        local has_glasses = kinetica.player_has_glasses(player)
        local panel_text  = ""
        local panel_col   = CONFIG.COLORS.ACTIVE

        if has_glasses then
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
                    if n.name ~= "air" and n.name ~= "ignore" then
                        local info_str = ""
                        if kinetica.get_glasses_info then
                            info_str = kinetica.get_glasses_info(pointed.under, n)
                        end
                        if (not info_str or info_str == "") and is_kinetica_node_name(n.name) then
                            info_str = build_universal_kinetica_telemetry(pointed.under, n)
                        end

                        if info_str and info_str ~= "" then
                            panel_text = info_str
                            if string.find(panel_text, "OVERSTRESSED") or
                               string.find(panel_text, "OVERLOADED") or
                               string.find(panel_text, "JAMMED") or
                               string.find(panel_text, "TOO SLOW") or
                               string.find(panel_text, "FAULT") then
                                panel_col = CONFIG.COLORS.DANGER
                            elseif string.find(panel_text, "IDLE") or string.find(panel_text, "Idle") then
                                panel_col = CONFIG.COLORS.IDLE
                            else
                                panel_col = CONFIG.COLORS.ACTIVE
                            end
                        end
                        break
                    end
                end
            end
        end

        local cur_hud = active_huds[pname]
        if not cur_hud then
            -- Uses both `type` (Luanti 5.9+) and `hud_elem_type` (legacy) so it never fails!
            local id = player:hud_add({
                type          = "text",
                hud_elem_type = "text",
                position      = {x = CONFIG.HUD_POS_X, y = CONFIG.HUD_POS_Y},
                alignment     = {x = 1, y = 0},
                offset        = {x = CONFIG.HUD_OFFSET_X, y = CONFIG.HUD_OFFSET_Y},
                text          = "",
                number        = panel_col,
                scale         = {x = 100, y = 100},
                z_index       = 100,
            })
            cur_hud = {id = id, text = "", color = panel_col, hold_until = 0}
            active_huds[pname] = cur_hud
        end

        if panel_text ~= "" then
            cur_hud.hold_until = now_us + CONFIG.HUD_HOLD_SECONDS
            if cur_hud.text ~= panel_text then
                player:hud_change(cur_hud.id, "text", panel_text)
                cur_hud.text = panel_text
            end
            if cur_hud.color ~= panel_col then
                player:hud_change(cur_hud.id, "number", panel_col)
                cur_hud.color = panel_col
            end
        elseif not has_glasses or now_us >= (cur_hud.hold_until or 0) then
            if cur_hud.text ~= "" then
                player:hud_change(cur_hud.id, "text", "")
                cur_hud.text = ""
            end
        end
    end
end)