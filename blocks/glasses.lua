kinetica = kinetica or {}

local CONFIG = {
    REQUIRE_HEAD_ARMOR_SLOT       = true,
    ALLOW_RIGHTCLICK_EQUIP        = true,
    HIDE_DEFAULT_INFOTEXT         = true,
    HUD_SCAN_INTERVAL             = 0.12,
    HUD_HOLD_SECONDS              = 0.25,
    HUD_REACH_DISTANCE            = 8.0,
    HUD_POS_X                     = 0.012,
    HUD_POS_Y                     = 0.25,
    HUD_OFFSET_X                  = 10,
    HUD_OFFSET_Y                  = 0,
    STRESS_BAR_SLOTS              = 10,
    COLORS = {
        ACTIVE   = 0x00E676,
        IDLE     = 0xFFB300,
        DANGER   = 0xFF5252,
        LOGISTIC = 0x00D4FF,
    },
    TEX_GLASSES_ICON              = "kinetica_glass.png",
    TEX_HEADBAND_ARMOR            = "kinetica_glasses_armor.png",
    TEX_FALLBACK_ICON             = "kinetica_shaft_connecting_overlay.png^[sheet:1x4:0,0^[colorize:#ffb300:150",
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

local HEADBAND_ARMOR_TEX = file_exists(CONFIG.TEX_HEADBAND_ARMOR)
    and CONFIG.TEX_HEADBAND_ARMOR
    or  "blank.png"

local function is_kinetica_node_name(name)
    return type(name) == "string" and string.sub(name, 1, 9) == "kinetica:"
end

local function is_glasses_item(name)
    return name == "kinetica:glasses" or name == "kinetica:goggles"
end

local raw_get_meta = core.get_meta

local function wrap_kinetica_meta(raw_meta)
    if not raw_meta then return nil end
    if raw_meta:get_string("infotext") ~= "" then
        raw_meta:set_string("_kinetica_raw_infotext", raw_meta:get_string("infotext"))
        raw_meta:set_string("infotext", "")
    end

    return setmetatable({}, {
        __index = function(_, method_name)
            if method_name == "set_string" then
                return function(_, key, val)
                    if key == "infotext" and CONFIG.HIDE_DEFAULT_INFOTEXT then
                        raw_meta:set_string("_kinetica_raw_infotext", tostring(val or ""))
                        return raw_meta:set_string("infotext", "")
                    end
                    return raw_meta:set_string(key, val)
                end
            end
            local member = raw_meta[method_name]
            if type(member) == "function" then
                return function(_, ...)
                    return member(raw_meta, ...)
                end
            end
            return member
        end,
    })
end

function core.get_meta(pos)
    local raw_meta = raw_get_meta(pos)
    if not CONFIG.HIDE_DEFAULT_INFOTEXT or not pos then
        return raw_meta
    end
    local node = core.get_node_or_nil(pos)
    if node and is_kinetica_node_name(node.name) then
        return wrap_kinetica_meta(raw_meta)
    end
    return raw_meta
end
minetest.get_meta = core.get_meta

core.register_on_mods_loaded(function()
    kinetica.player_has_glasses = function() return false end

    if not CONFIG.HIDE_DEFAULT_INFOTEXT then return end
    local kinetica_nodenames = {}
    for name, _ in pairs(core.registered_nodes) do
        if is_kinetica_node_name(name) then
            kinetica_nodenames[#kinetica_nodenames + 1] = name
        end
    end

    if #kinetica_nodenames > 0 then
        core.register_lbm({
            label             = "Clear default infotext on all kinetica blocks",
            name              = ":kinetica:clear_default_infotext_lbm",
            nodenames         = kinetica_nodenames,
            run_at_every_load = true,
            action = function(pos)
                local rm = raw_get_meta(pos)
                if rm and rm:get_string("infotext") ~= "" then
                    rm:set_string("_kinetica_raw_infotext", rm:get_string("infotext"))
                    rm:set_string("infotext", "")
                end
            end,
        })
    end
end)

function kinetica.player_has_glasses(_player)
    return false
end

local function get_head_armor_slot_index(inv)
    if not inv then return nil end
    local armor_size = inv:get_size("armor")
    if armor_size <= 0 then return nil end
    if armor_size >= 2 then
        return 2
    end
    return 1
end

local function is_wearing_glasses_on_head(player)
    if not player or not player:is_player() then
        return false
    end

    local inv = player:get_inventory()
    if inv and inv:get_size("armor") > 0 then
        if inv:contains_item("armor", "kinetica:glasses") or
           inv:contains_item("armor", "kinetica:goggles") then
            return true
        end
        if CONFIG.REQUIRE_HEAD_ARMOR_SLOT then
            return false
        end
    end

    local pmeta = player:get_meta()
    if pmeta and pmeta:get_int("kinetica_glasses_worn") == 1 then
        return true
    end

    if not CONFIG.REQUIRE_HEAD_ARMOR_SLOT and inv then
        return inv:contains_item("main", "kinetica:glasses") or
               inv:contains_item("main", "kinetica:goggles")
    end
    return false
end

local function equip_glasses_to_head_slot(itemstack, user)
    if not CONFIG.ALLOW_RIGHTCLICK_EQUIP or not user or not user:is_player() then
        return itemstack
    end

    local inv   = user:get_inventory()
    local pname = user:get_player_name()
    local hslot = get_head_armor_slot_index(inv)

    if hslot then
        local current_head = inv:get_stack("armor", hslot)
        if is_glasses_item(current_head:get_name()) then
            core.chat_send_player(pname, "[Kinetica] Engineer's Glasses are already worn on your head.")
            return itemstack
        end

        local to_equip = ItemStack(itemstack:get_name())
        itemstack:take_item(1)
        inv:set_stack("armor", hslot, to_equip)

        if mcl_armor and type(mcl_armor.update) == "function" then
            pcall(mcl_armor.update, user)
        elseif armor and type(armor.set_player_armor) == "function" then
            pcall(armor.set_player_armor, armor, user)
        end

        core.sound_play("default_place_node_hard", {pos = user:get_pos(), max_hear_distance = 8, gain = 0.5}, true)
        core.chat_send_player(pname, "[Kinetica] Put on Engineer's Glasses (Headband Equipped).")

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

    local pmeta  = user:get_meta()
    local next_v = (pmeta:get_int("kinetica_glasses_worn") == 1) and 0 or 1
    pmeta:set_int("kinetica_glasses_worn", next_v)
    core.sound_play("default_place_node_hard", {pos = user:get_pos(), max_hear_distance = 8, gain = 0.5}, true)
    core.chat_send_player(
        pname,
        next_v == 1
            and "[Kinetica] Put on Engineer's Glasses."
            or  "[Kinetica] Took off Engineer's Glasses."
    )
    return itemstack
end

local LINE_TOP = "┌─ ENGINEER'S GLASSES ──────────────"
local LINE_NET = "├─ KINETIC NETWORK ─────────────────"
local LINE_DET = "├─ MACHINE DETAILS ─────────────────"
local LINE_BOT = "└───────────────────────────────────"

local function kv_row(label, value)
    return string.format("│  %-11s: %s", label, tostring(value))
end

local function make_progress_bar(used, total)
    local slots = CONFIG.STRESS_BAR_SLOTS
    if not total or total <= 0 then
        return "[" .. string.rep("░", slots) .. "] 0%"
    end
    local ratio  = math.min(1.0, math.max(0.0, (used or 0) / total))
    local filled = math.floor(ratio * slots + 0.5)
    local pct    = math.min(100, math.floor(ratio * 100 + 0.5))
    return string.format(
        "[%s%s] %d%%",
        string.rep("█", filled),
        string.rep("░", slots - filled),
        pct
    )
end

local function short_item_desc(stack)
    if not stack or stack:is_empty() then
        return "Empty"
    end
    local iname = stack:get_name()
    local idef  = core.registered_items[iname]
    local desc  = (idef and idef.description) and string.match(idef.description, "^[^\n%(]+") or iname
    desc = string.gsub(desc, "%s+$", "")
    return string.format("%s x%d", desc, stack:get_count())
end

local function assemble_panel(title, state_str, net_rows, detail_rows)
    local lines = {
        LINE_TOP,
        "│  " .. title,
        "│  ● STATE    : " .. state_str,
    }

    if net_rows and #net_rows > 0 then
        lines[#lines + 1] = LINE_NET
        for _, r in ipairs(net_rows) do
            lines[#lines + 1] = r
        end
    end

    if detail_rows and #detail_rows > 0 then
        lines[#lines + 1] = LINE_DET
        for _, r in ipairs(detail_rows) do
            lines[#lines + 1] = r
        end
    end

    lines[#lines + 1] = LINE_BOT
    return table.concat(lines, "\n")
end

local function build_clean_left_hud(pos, node)
    local name = node.name or ""
    if not is_kinetica_node_name(name) then
        return "", CONFIG.COLORS.IDLE
    end

    local meta     = raw_get_meta(pos)
    local now      = math.floor(core.get_gametime())
    local raw_info = meta:get_string("_kinetica_raw_infotext")
    local is_over  = (meta:get_int("network_overstressed") == 1) or
                     (string.find(raw_info, "OVERSTRESSED", 1, true) ~= nil) or
                     (string.find(raw_info, "OVERLOADED",   1, true) ~= nil) or
                     (string.find(raw_info, "JAMMED",       1, true) ~= nil)

    if name == "kinetica:steam_generator" or name == "kinetica:steam_generator_active" or
       (kinetica.is_steam_generator and kinetica.is_steam_generator(name)) then
        local inv             = meta:get_inventory()
        local burn_time       = meta:get_float("burn_time")
        local max_burn        = math.max(1, meta:get_float("max_burn"))
        local water_boil_time = meta:get_float("water_boil_time")
        local piped_water     = meta:get_int("water_level")
        local water_stack     = inv and inv:get_stack("water", 1) or ItemStack("")
        local fuel_stack      = inv and inv:get_stack("fuel", 1) or ItemStack("")

        local has_bucket      = (water_stack:get_name() == "mcl_buckets:bucket_water" or
                                 water_stack:get_name() == "mcl_buckets:bucket_river_water")
        local display_water   = has_bucket
            and ((water_boil_time > 0) and math.floor((water_boil_time / 20) * 100) or 100)
            or  piped_water
        local burn_pct        = (burn_time > 0) and math.min(100, math.floor((burn_time / max_burn) * 100)) or 0
        local is_boiling      = (name == "kinetica:steam_generator_active") or
                                (burn_time > 0 and (has_bucket or piped_water >= 10))
        local no_water        = (not has_bucket and piped_water < 10)

        local state_str = is_boiling and "BOILING (30 Steam/s)"
            or (no_water and "WAITING FOR WATER" or "IDLE (Add Fuel)")
        local col = is_boiling and CONFIG.COLORS.ACTIVE or (no_water and CONFIG.COLORS.DANGER or CONFIG.COLORS.IDLE)

        return assemble_panel(
            "Steam Generator",
            state_str,
            nil,
            {
                kv_row("Water Level", make_progress_bar(display_water, 100)),
                kv_row("Water Input", has_bucket and "Water Bucket (-1 / 20s)" or "Piped Water (-10/s)"),
                kv_row("Firebox",     make_progress_bar(burn_pct, 100)),
                kv_row("Fuel Slot",   short_item_desc(fuel_stack)),
                kv_row("Steam Out",   is_boiling and "30 Steam/s (Top Port)" or "0 Steam/s"),
            }
        ), col
    end

    if name == "kinetica:water_pump" or
       name == "kinetica:water_pump_active_cw" or
       name == "kinetica:water_pump_active_ccw" or
       (kinetica.is_water_pump and kinetica.is_water_pump(name)) then
        local rpm        = meta:get_float("rpm")
        local supply     = meta:get_int("network_supply_ku")
        local avail      = meta:get_int("rotational_power")
        local demand     = meta:get_int("pump_demand_ku")
        if demand <= 0 then
            demand = kinetica.get_pump_demand_ku and kinetica.get_pump_demand_ku(rpm) or 20
        end
        local used       = (supply > 0) and math.max(0, supply - avail) or 0
        local is_powered = (supply > 0 and rpm > 0 and now < meta:get_int("lit_until"))
        local low_rpm    = (is_powered and rpm < 4)
        local overloaded = (meta:get_int("pump_overloaded") == 1)
        local is_active  = is_powered and (not low_rpm) and (not overloaded)

        local bottom_name = core.get_node({x = pos.x, y = pos.y - 1, z = pos.z}).name
        local has_water   = (meta:get_int("has_water_below") == 1) or
                            (core.get_item_group(bottom_name, "water") > 0)
        local calc_rate   = is_active and math.min(100, math.max(20, 19 + math.floor((rpm / 512) * 81))) or 0
        local pump_rate   = (is_active and has_water) and calc_rate or 0
        local chain_sz    = math.max(1, meta:get_int("chain_size"))

        local state_str = "IDLE"
        local col       = CONFIG.COLORS.IDLE
        if is_over or overloaded then
            state_str = overloaded and "CHAIN OVERLOAD (Max 5)" or "OVERSTRESSED!"
            col       = CONFIG.COLORS.DANGER
        elseif low_rpm then
            state_str = "TOO SLOW (Min 4 RPM)"
            col       = CONFIG.COLORS.DANGER
        elseif is_active then
            if has_water then
                state_str = string.format("PUMPING (%d Water/s)", pump_rate)
                col       = CONFIG.COLORS.ACTIVE
            else
                state_str = "RUNNING DRY (No Water Below!)"
                col       = CONFIG.COLORS.DANGER
            end
        end

        return assemble_panel(
            "Mechanical Water Pump",
            state_str,
            {
                kv_row("Speed",       string.format("%.1f RPM  (Min: 4)", is_powered and rpm or 0)),
                kv_row("Block Load",  string.format("-%d KU", is_active and demand or 0)),
                kv_row("Net Pool",    string.format("%d / %d KU Avail", is_powered and avail or 0, supply)),
                kv_row("Net Stress",  make_progress_bar(is_powered and used or 0, supply)),
            },
            {
                kv_row("Pump Output", string.format("%d Water/s (Top Port)", pump_rate)),
                kv_row("Intake (-Y)", has_water and "Water Source Ready" or "Dry (Place over Water!)"),
                kv_row("Pump Chain",  string.format("%d / 5 Pumps", chain_sz)),
            }
        ), col
    end

    if kinetica.is_pipe and kinetica.is_pipe(name) then
        local ftype      = meta:get_string("fluid_type")
        local amount     = math.max(0, meta:get_int("fluid_amount"))
        local port_count = meta:get_int("port_count")
        local is_venting = (meta:get_int("is_venting") == 1) or (port_count <= 1 and amount > 0)

        local type_lbl   = "UNASSIGNED"
        local title_lbl  = "Copper Fluid Pipe"
        if ftype == "water" then
            type_lbl  = "WATER LINE (Blue)"
            title_lbl = "Copper Water Pipe"
        elseif ftype == "steam" then
            type_lbl  = "HIGH-PRESSURE STEAM (White)"
            title_lbl = "Copper Steam Pipe"
        elseif ftype == "exhaust" then
            type_lbl  = "EXHAUST VENT LINE"
            title_lbl = "Copper Exhaust Pipe"
        end

        local state_str = (amount > 0)
            and (is_venting and "VENTING JET (Open End)" or "FLOWING")
            or  ((ftype ~= "" and ftype ~= "none") and "EMPTY (Locked to " .. string.upper(ftype) .. ")" or "UNASSIGNED")

        return assemble_panel(
            title_lbl,
            state_str,
            nil,
            {
                kv_row("Fluid Type",  type_lbl),
                kv_row("Fluid Level", make_progress_bar(amount, 100)),
                kv_row("Connections", string.format("%d Active Port(s)", port_count)),
                kv_row("Quick Reset", "Sneak + Right-Click (Empty Hand)"),
            }
        ), (amount > 0 and CONFIG.COLORS.ACTIVE or CONFIG.COLORS.LOGISTIC)
    end

    if kinetica.is_turbine and kinetica.is_turbine(name) then
        local active     = (meta:get_int("source_active") == 1)
        local my_ku      = meta:get_int("source_ku")
        local my_rpm     = meta:get_float("source_rpm")
        local steam      = meta:get_int("steam")
        local supply     = meta:get_int("network_supply_ku")
        local avail      = meta:get_int("rotational_power")
        local used       = (supply > 0) and math.max(0, supply - avail) or 0
        local choked     = (meta:get_int("exhaust_blocked") == 1)
        local piped_exh  = (meta:get_int("exhaust_piped") == 1)
        local chain_len  = math.max(1, meta:get_int("chain_len"))
        local chain_over = (meta:get_int("chain_overloaded") == 1)

        local state_str  = "IDLE (Needs >= 10% Steam)"
        local col        = CONFIG.COLORS.IDLE
        if is_over or chain_over then
            state_str = chain_over and "CHAIN OVERLOAD (Max 3!)" or "OVERSTRESSED!"
            col       = CONFIG.COLORS.DANGER
        elseif choked then
            state_str = "CHOKED (Top Exhaust Blocked!)"
            col       = CONFIG.COLORS.DANGER
        elseif active then
            state_str = "GENERATING POWER"
            col       = CONFIG.COLORS.ACTIVE
        end

        local vent_lbl = choked and "BLOCKED (Clear Top +Y!)"
            or (piped_exh and "Piped (15 Exhaust/s)" or "Open Air Vent (Clear)")

        return assemble_panel(
            "Steam Turbine",
            state_str,
            {
                kv_row("Output RPM",  string.format("%.1f RPM", active and my_rpm or 0)),
                kv_row("Turbine Gen", string.format("+%d KU", active and my_ku or 0)),
                kv_row("Net Pool",    string.format("%d / %d KU Avail", avail, supply)),
                kv_row("Net Stress",  make_progress_bar(used, supply)),
            },
            {
                kv_row("Steam Tank",  make_progress_bar(steam, 100)),
                kv_row("Steam Use",   active and "15 Steam/s (Right Port)" or "0 Steam/s"),
                kv_row("Top Exhaust", vent_lbl),
                kv_row("Daisy Chain", string.format("%d / 3 Turbines", chain_len)),
            }
        ), col
    end

    if kinetica.is_water_wheel and kinetica.is_water_wheel(name) then
        local active = (meta:get_int("source_active") == 1)
        local my_ku  = meta:get_int("source_ku")
        local my_rpm = meta:get_float("source_rpm")
        local supply = meta:get_int("network_supply_ku")
        local avail  = meta:get_int("rotational_power")
        local used   = (supply > 0) and math.max(0, supply - avail) or 0

        local state_str = is_over and "OVERSTRESSED!" or (active and "GENERATING POWER" or "IDLE (Add Flowing Water)")
        local col       = is_over and CONFIG.COLORS.DANGER or (active and CONFIG.COLORS.ACTIVE or CONFIG.COLORS.IDLE)

        return assemble_panel(
            "Big Water Wheel",
            state_str,
            {
                kv_row("Output RPM", string.format("%.1f RPM", active and my_rpm or 0)),
                kv_row("Wheel Gen",  string.format("+%d KU", active and my_ku or 0)),
                kv_row("Net Pool",   string.format("%d / %d KU Avail", avail, supply)),
                kv_row("Net Stress", make_progress_bar(used, supply)),
            },
            {
                kv_row("Series Cap", string.format("Max %d Wheels", kinetica.MAX_WATER_WHEELS or 10)),
            }
        ), col
    end

    if kinetica.is_speed_controller and kinetica.is_speed_controller(name) then
        local in_rpm     = meta:get_float("true_in_rpm")
        local in_supply  = meta:get_int("true_in_supply_ku")
        local in_avail   = meta:get_int("true_in_avail_ku")
        local in_demand  = meta:get_int("true_in_demand_ku")
        local out_active = (meta:get_int("sc_out_active") == 1)
        local out_rpm    = meta:get_float("source_rpm")
        local out_ku     = meta:get_int("sc_out_ku")
        local down_ku    = meta:get_int("last_downstream_ku")
        local slider_idx = meta:get_int("slider_idx")
        local over       = is_over or (meta:get_int("sc_overstressed") == 1)
        local used_in    = (in_supply > 0) and math.max(0, in_supply - in_avail) or 0

        local state_str = "IDLE (No Input)"
        local col       = CONFIG.COLORS.IDLE
        if over then
            state_str = "OVERSTRESSED!"
            col       = CONFIG.COLORS.DANGER
        elseif in_supply > 0 and in_rpm > 0 then
            if slider_idx == 0 or not out_active then
                state_str = "NEUTRAL (Clutch Open)"
                col       = CONFIG.COLORS.IDLE
            elseif slider_idx < 0 then
                state_str = "ENGAGED (Speed Overdrive)"
                col       = CONFIG.COLORS.ACTIVE
            else
                state_str = "ENGAGED (Torque Drive)"
                col       = CONFIG.COLORS.ACTIVE
            end
        end

        return assemble_panel(
            "Variable Speed Controller",
            state_str,
            {
                kv_row("Input RPM",   string.format("%.1f RPM", in_rpm)),
                kv_row("Input Load",  string.format("-%d KU (incl. 1 fine)", in_demand)),
                kv_row("Input Pool",  string.format("%d / %d KU Avail", in_avail, in_supply)),
                kv_row("Net Stress",  make_progress_bar(used_in, in_supply)),
            },
            {
                kv_row("Slider Pos",  string.format("Notch [%s%d]", slider_idx > 0 and "+" or "", slider_idx)),
                kv_row("Output RPM",  string.format("%.1f RPM", out_active and out_rpm or 0)),
                kv_row("Output Load", string.format("%d / %d KU Max", down_ku, out_active and out_ku or 0)),
            }
        ), col
    end

    if kinetica.is_shaft and kinetica.is_shaft(name) then
        local rpm    = meta:get_float("rpm")
        local supply = meta:get_int("network_supply_ku")
        local avail  = meta:get_int("rotational_power")
        local used   = meta:get_int("network_used_ku")
        local sdist  = meta:get_int("shaft_dist")
        if sdist <= 0 then sdist = 1 end
        local active = (name ~= "kinetica:shaft") and (supply > 0 and rpm > 0 and now < meta:get_int("lit_until"))
        local ax     = kinetica.abs_axis and kinetica.abs_axis(node.param2) or {x = 0, y = 0, z = 1}
        local ax_str = (ax.y ~= 0) and "Vertical (Y)" or ((ax.x ~= 0) and "East-West (X)" or "North-South (Z)")

        local state_str = is_over and "OVERSTRESSED!" or (active and "ACTIVE" or "IDLE")
        local col       = is_over and CONFIG.COLORS.DANGER or (active and CONFIG.COLORS.ACTIVE or CONFIG.COLORS.IDLE)

        return assemble_panel(
            "Square Tube Shaft",
            state_str,
            {
                kv_row("Speed",      string.format("%.1f RPM", active and rpm or 0)),
                kv_row("Net Pool",   string.format("%d / %d KU Avail", active and avail or 0, supply)),
                kv_row("Net Stress", make_progress_bar(active and used or 0, supply)),
            },
            {
                kv_row("Shaft Run",  string.format("%d / %d Blocks", active and sdist or 0, kinetica.MAX_SHAFT_RUN or 32)),
                kv_row("Axis",       ax_str),
            }
        ), col
    end

    if kinetica.is_gearbox and kinetica.is_gearbox(name) then
        local is_vert = string.find(name, "vertical") ~= nil
        local is_idle = (name == "kinetica:gearbox" or name == "kinetica:gearbox_vertical")
        local rpm     = meta:get_float("rpm")
        local supply  = meta:get_int("network_supply_ku")
        local avail   = meta:get_int("rotational_power")
        local used    = (supply > 0) and math.max(0, supply - avail) or 0
        local active  = (not is_idle) and (supply > 0 and rpm > 0 and now < meta:get_int("lit_until"))

        local state_str = is_over and "OVERSTRESSED!" or (active and "ACTIVE" or "IDLE")
        local col       = is_over and CONFIG.COLORS.DANGER or (active and CONFIG.COLORS.ACTIVE or CONFIG.COLORS.IDLE)

        return assemble_panel(
            is_vert and "Vertical Gearbox" or "Gearbox",
            state_str,
            {
                kv_row("Speed",      string.format("%.1f RPM", active and rpm or 0)),
                kv_row("Block Load", "-1 KU (Friction Fine)"),
                kv_row("Net Pool",   string.format("%d / %d KU Avail", active and avail or 0, supply)),
                kv_row("Net Stress", make_progress_bar(active and used or 0, supply)),
            },
            {
                kv_row("Relay Mode", is_vert and "4-Way Vertical" or "4-Way Horizontal"),
            }
        ), col
    end

    if kinetica.is_chain_drive and kinetica.is_chain_drive(name) then
        local is_idle = (name == "kinetica:chain_drive")
        local rpm     = meta:get_float("rpm")
        local supply  = meta:get_int("network_supply_ku")
        local avail   = meta:get_int("rotational_power")
        local used    = (supply > 0) and math.max(0, supply - avail) or 0
        local active  = (not is_idle) and (supply > 0 and rpm > 0 and now < meta:get_int("lit_until"))

        local state_str = is_over and "OVERSTRESSED!" or (active and "ACTIVE" or "IDLE")
        local col       = is_over and CONFIG.COLORS.DANGER or (active and CONFIG.COLORS.ACTIVE or CONFIG.COLORS.IDLE)

        return assemble_panel(
            "Encased Chain Drive",
            state_str,
            {
                kv_row("Speed",      string.format("%.1f RPM", active and rpm or 0)),
                kv_row("Block Load", "-1 KU (Friction Fine)"),
                kv_row("Net Pool",   string.format("%d / %d KU Avail", active and avail or 0, supply)),
                kv_row("Net Stress", make_progress_bar(active and used or 0, supply)),
            },
            {
                kv_row("Chain Link", "Parallel Sideways Coupling"),
            }
        ), col
    end

    if kinetica.is_belt and kinetica.is_belt(name) then
        local rpm       = meta:get_float("rpm")
        local supply    = meta:get_int("network_supply_ku")
        local avail     = meta:get_int("rotational_power")
        local demand    = meta:get_int("machine_demand_ku")
        local used      = (supply > 0) and math.max(0, supply - avail) or 0
        local has_shaft = (meta:get_int("has_shaft") == 1)
        local is_relay  = (meta:get_int("source_active") == 1)
        local seg_len   = meta:get_int("seg_len")
        local b_idx     = meta:get_int("belt_index")
        local active    = (supply > 0 and rpm >= 6)

        local role_str  = has_shaft and (is_relay and "Relay Pulley" or "Driven Pulley") or "Conveyor Span"
        local col       = is_over and CONFIG.COLORS.DANGER or (active and CONFIG.COLORS.ACTIVE or ((supply > 0 and rpm > 0) and CONFIG.COLORS.DANGER or CONFIG.COLORS.IDLE))
        local state_str = is_over and "OVERSTRESSED!" or (active and "MOVING" or ((supply > 0 and rpm > 0) and "TOO SLOW (Min 6 RPM)" or "IDLE"))

        return assemble_panel(
            "Mechanical Belt",
            state_str,
            {
                kv_row("Speed",      string.format("%.1f RPM  (Min: 6)", active and rpm or 0)),
                kv_row("Span Load",  string.format("-%d KU", active and math.max(1, demand) or 0)),
                kv_row("Net Pool",   string.format("%d / %d KU Avail", active and avail or 0, supply)),
                kv_row("Net Stress", make_progress_bar(active and used or 0, supply)),
            },
            {
                kv_row("Segment",    string.format("%s [%d / %d]", role_str, b_idx + 1, seg_len + 1)),
            }
        ), col
    end

    if core.get_item_group(name, "encased_fan") > 0 then
        local rpm      = meta:get_float("rpm")
        local supply   = meta:get_int("network_supply_ku")
        local avail    = meta:get_int("rotational_power")
        local demand   = meta:get_int("machine_demand_ku")
        local used     = (supply > 0) and math.max(0, supply - avail) or 0
        local is_pull  = (meta:get_int("is_pull") == 1)
        local reach    = meta:get_int("last_reach")
        local catalyst = meta:get_string("last_catalyst")
        local active   = (name ~= "kinetica:encased_fan") and (supply > 0 and rpm >= 16 and now < meta:get_int("lit_until"))
        local low_rpm  = (supply > 0 and rpm > 0 and rpm < 16)

        local state_str = is_over and "OVERSTRESSED!"
            or (active and (is_pull and "PULLING (Suction)" or "PUSHING (Blowing)")
            or (low_rpm and "TOO SLOW (Min 16 RPM)" or "IDLE"))
        local col = (is_over or low_rpm) and CONFIG.COLORS.DANGER or (active and CONFIG.COLORS.ACTIVE or CONFIG.COLORS.IDLE)

        return assemble_panel(
            "Encased Fan",
            state_str,
            {
                kv_row("Speed",      string.format("%.1f RPM  (Min: 16)", rpm)),
                kv_row("Block Load", string.format("-%d KU", active and demand or 0)),
                kv_row("Net Pool",   string.format("%d / %d KU Avail", active and avail or 0, supply)),
                kv_row("Net Stress", make_progress_bar(active and used or 0, supply)),
            },
            {
                kv_row("Air Reach",  string.format("%d Blocks", active and reach or 0)),
                kv_row("Catalyst",   (active and catalyst ~= "") and string.upper(catalyst) or "None (Clean Air)"),
            }
        ), col
    end

    if kinetica.is_mechanical_saw and kinetica.is_mechanical_saw(name) then
        local rpm      = meta:get_float("rpm")
        local supply   = meta:get_int("network_supply_ku")
        local avail    = meta:get_int("rotational_power")
        local demand   = meta:get_int("machine_demand_ku")
        local used     = (supply > 0) and math.max(0, supply - avail) or 0
        local target   = meta:get_string("cut_target_name")
        local active   = (name ~= "kinetica:mechanical_saw") and (supply > 0 and rpm >= 32 and now < meta:get_int("lit_until"))
        local low_rpm  = (supply > 0 and rpm > 0 and rpm < 32)

        local state_str = is_over and "OVERSTRESSED!"
            or (active and ((target ~= "") and "CUTTING TARGET" or "ACTIVE (Spinning)")
            or (low_rpm and "TOO SLOW (Min 32 RPM)" or "IDLE"))
        local col = (is_over or low_rpm) and CONFIG.COLORS.DANGER or (active and CONFIG.COLORS.ACTIVE or CONFIG.COLORS.IDLE)

        return assemble_panel(
            "Mechanical Saw",
            state_str,
            {
                kv_row("Speed",      string.format("%.1f RPM  (Min: 32)", rpm)),
                kv_row("Block Load", string.format("-%d KU", active and demand or 0)),
                kv_row("Net Pool",   string.format("%d / %d KU Avail", active and avail or 0, supply)),
                kv_row("Net Stress", make_progress_bar(active and used or 0, supply)),
            },
            {
                kv_row("Target",     (target ~= "") and target or "None"),
                kv_row("Blade Dmg",  "1 Heart (2 HP/s)"),
            }
        ), col
    end

    if kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(name) then
        local is_sticky  = string.find(name, "sticky") ~= nil
        local rpm        = meta:get_float("rpm")
        local supply     = meta:get_int("network_supply_ku")
        local avail      = meta:get_int("rotational_power")
        local demand     = meta:get_int("piston_demand_ku")
        local used       = (supply > 0) and math.max(0, supply - avail) or 0
        local ext_len    = meta:get_int("extended_len")
        local last_stat  = meta:get_string("last_status")
        local active     = (supply > 0 and rpm >= 32 and now < meta:get_int("lit_until"))
        local low_rpm    = (supply > 0 and rpm > 0 and rpm < 32)
        local push_limit = active and math.min(32, math.max(1, math.floor((avail + demand) / 8))) or 0

        local state_str = is_over and "OVERSTRESSED!"
            or (active and ((last_stat ~= "") and ("ACTIVE (" .. last_stat .. ")") or "ACTIVE")
            or (low_rpm and "TOO SLOW (Min 32 RPM)" or "IDLE"))
        local col = (is_over or low_rpm) and CONFIG.COLORS.DANGER or (active and CONFIG.COLORS.ACTIVE or CONFIG.COLORS.IDLE)

        return assemble_panel(
            is_sticky and "Sticky Mechanical Piston" or "Mechanical Piston",
            state_str,
            {
                kv_row("Speed",      string.format("%.1f RPM  (Min: 32)", rpm)),
                kv_row("Block Load", string.format("-%d KU", active and demand or 0)),
                kv_row("Net Pool",   string.format("%d / %d KU Avail", active and avail or 0, supply)),
                kv_row("Net Stress", make_progress_bar(active and used or 0, supply)),
            },
            {
                kv_row("Extension",  string.format("%d / 16 Poles", ext_len)),
                kv_row("Push Limit", string.format("%d / 32 Blocks (by KU)", push_limit)),
            }
        ), col
    end

    if kinetica.is_feeder and kinetica.is_feeder(name) then
        local inv      = meta:get_inventory()
        local rpm      = meta:get_float("rpm")
        local supply   = meta:get_int("network_supply_ku")
        local avail    = meta:get_int("rotational_power")
        local demand   = meta:get_int("machine_demand_ku")
        local used     = (supply > 0) and math.max(0, supply - avail) or 0
        local last_act = meta:get_string("last_action")
        local active   = (name ~= "kinetica:feeder") and (supply > 0 and rpm >= 4 and now < meta:get_int("lit_until"))
        local low_rpm  = (supply > 0 and rpm > 0 and rpm < 4)

        local hoe_s = inv and inv:get_stack("hoe", 1) or ItemStack("")
        local s1    = inv and inv:get_stack("seed", 1) or ItemStack("")
        local p1    = inv and inv:get_stack("profit", 1) or ItemStack("")
        local p2    = (inv and inv:get_size("profit") >= 2) and inv:get_stack("profit", 2) or ItemStack("")

        local state_str = is_over and "OVERSTRESSED!"
            or (active and ((last_act ~= "") and ("ACTIVE (" .. last_act .. ")") or "ACTIVE")
            or (low_rpm and "TOO SLOW (Min 4 RPM)" or "IDLE"))
        local col = (is_over or low_rpm) and CONFIG.COLORS.DANGER or (active and CONFIG.COLORS.ACTIVE or CONFIG.COLORS.IDLE)

        return assemble_panel(
            "Mechanical Feeder",
            state_str,
            {
                kv_row("Speed",      string.format("%.1f RPM  (Min: 4)", rpm)),
                kv_row("Block Load", string.format("-%d KU", active and demand or 0)),
                kv_row("Net Pool",   string.format("%d / %d KU Avail", active and avail or 0, supply)),
                kv_row("Net Stress", make_progress_bar(active and used or 0, supply)),
            },
            {
                kv_row("Hoe Slot",   hoe_s:is_empty() and "None" or "Equipped"),
                kv_row("Seed Bank",  short_item_desc(s1)),
                kv_row("Profit 1",   short_item_desc(p1)),
                kv_row("Profit 2",   short_item_desc(p2)),
            }
        ), col
    end

    if name == "kinetica:depot" or core.get_item_group(name, "kinetica_depot") > 0 then
        local inv       = meta:get_inventory()
        local in_s      = inv and inv:get_stack("input", 1) or ItemStack("")
        local main_s    = inv and inv:get_stack("main", 1) or ItemStack("")
        local held      = not in_s:is_empty() and in_s or main_s
        local out_cnt   = 0
        local first_out = ItemStack("")
        if inv and inv:get_size("output") > 0 then
            for i = 1, inv:get_size("output") do
                local os = inv:get_stack("output", i)
                if not os:is_empty() then
                    out_cnt = out_cnt + os:get_count()
                    if first_out:is_empty() then first_out = os end
                end
            end
        end

        local proc_cat  = meta:get_string("proc_cat")
        local proc_time = meta:get_float("proc_time")
        local is_proc   = (not in_s:is_empty() and proc_time > 0)

        local state_str = is_proc and ("PROCESSING (" .. string.upper(proc_cat) .. ")")
            or ((not held:is_empty() or out_cnt > 0) and "HOLDING ITEMS" or "EMPTY")

        return assemble_panel(
            "Depot",
            state_str,
            nil,
            {
                kv_row("Tray Item",  not held:is_empty() and short_item_desc(held) or short_item_desc(first_out)),
                kv_row("Output Bin", (out_cnt > 0) and (out_cnt .. " Finished Items") or "Empty"),
            }
        ), (is_proc and CONFIG.COLORS.ACTIVE or CONFIG.COLORS.LOGISTIC)
    end

    if kinetica.is_chute and kinetica.is_chute(name) then
        local is_smart = (name == "kinetica:smart_chute")
        if not is_smart then
            return assemble_panel(
                "Chute",
                "PASSIVE LOGISTICS",
                nil,
                {
                    kv_row("Transfer", "Up to 16 Items / Tick"),
                    kv_row("Filter",   "None (Pulls All Items)"),
                }
            ), CONFIG.COLORS.LOGISTIC
        else
            local inv    = meta:get_inventory()
            local mode   = meta:get_string("filter_mode")
            local batch  = meta:get_int("stack_size")
            local exact  = (meta:get_string("exact_mode") == "exact")
            local f_list = {}
            if inv and inv:get_size("filter") > 0 then
                for i = 1, inv:get_size("filter") do
                    local fs = inv:get_stack("filter", i)
                    if not fs:is_empty() then
                        f_list[#f_list + 1] = short_item_desc(fs):gsub(" x%d+$", "")
                    end
                end
            end
            return assemble_panel(
                "Smart Chute",
                "FILTERED LOGISTICS",
                nil,
                {
                    kv_row("Filter Mode", (mode == "blacklist") and "BLACKLIST (Block)" or "WHITELIST (Allow)"),
                    kv_row("Batch Size",  (exact and "Exact " or "Up to ") .. tostring(batch > 0 and batch or 64)),
                    kv_row("Items Set",   (#f_list > 0) and table.concat(f_list, ", ") or "Any Item"),
                }
            ), CONFIG.COLORS.LOGISTIC
        end
    end

    if kinetica._glasses_formatters then
        for prefix, fn in pairs(kinetica._glasses_formatters) do
            if name == prefix or string.sub(name, 1, #prefix + 1) == (prefix .. "_") then
                return fn(pos, node), (is_over and CONFIG.COLORS.DANGER or CONFIG.COLORS.ACTIVE)
            end
        end
    end

    local ndef  = core.registered_nodes[name]
    local title = (ndef and ndef.description) and string.match(ndef.description, "^[^\n%(]+") or name
    return assemble_panel(
        title,
        is_over and "OVERSTRESSED!" or "READY",
        nil,
        nil
    ), (is_over and CONFIG.COLORS.DANGER or CONFIG.COLORS.LOGISTIC)
end

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
    on_secondary_use    = equip_glasses_to_head_slot,
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
        local has_glasses = is_wearing_glasses_on_head(player)
        local panel_text  = ""
        local panel_col   = CONFIG.COLORS.ACTIVE

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
                    if CONFIG.HIDE_DEFAULT_INFOTEXT and is_kinetica_node_name(n.name) then
                        local rm = raw_get_meta(pointed.under)
                        if rm and rm:get_string("infotext") ~= "" then
                            rm:set_string("_kinetica_raw_infotext", rm:get_string("infotext"))
                            rm:set_string("infotext", "")
                        end
                    end
                    if has_glasses and is_kinetica_node_name(n.name) then
                        panel_text, panel_col = build_clean_left_hud(pointed.under, n)
                    end
                    break
                end
            end
        end

        local cur_hud = active_huds[pname]
        if not cur_hud then
            local id = player:hud_add({
                hud_elem_type = "text",
                position      = {x = CONFIG.HUD_POS_X, y = CONFIG.HUD_POS_Y},
                alignment     = {x = 1, y = 0},
                offset        = {x = CONFIG.HUD_OFFSET_X, y = CONFIG.HUD_OFFSET_Y},
                text          = "",
                number        = panel_col,
                scale         = {x = 100, y = 100},
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