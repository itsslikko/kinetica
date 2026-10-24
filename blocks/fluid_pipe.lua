kinetica = kinetica or {}

local CONFIG = {
    MAX_FLUID_CAPACITY            = 100,
    PIPE_TRANSFER_RATIO           = 0.60,
    MACHINE_INJECT_MAX            = 40,
    VENT_DRAIN_PER_SEC            = 12,
    STEAM_JET_REACH               = 3,
    STEAM_COOK_SECONDS            = 60,
    ALLOW_SNEAK_FLUSH_PIPE        = true,
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,
    TEX_PIPE_BASE                 = "kinetica_pipe.png",
    WATER_COLORIZE                = "^[colorize:#2266ff:110",
    STEAM_COLORIZE                = "^[colorize:#ffffff:110",
}

local pipe_dirs = {
    {x =  1, y =  0, z =  0, bit = 1,  box = { 4/16, -3/16, -3/16,  8/16,  3/16,  3/16}},
    {x = -1, y =  0, z =  0, bit = 2,  box = {-8/16, -3/16, -3/16, -4/16,  3/16,  3/16}},
    {x =  0, y =  1, z =  0, bit = 4,  box = {-3/16,  4/16, -3/16,  3/16,  8/16,  3/16}},
    {x =  0, y = -1, z =  0, bit = 8,  box = {-3/16, -8/16, -3/16,  3/16, -4/16,  3/16}},
    {x =  0, y =  0, z =  1, bit = 16, box = {-3/16, -3/16,  4/16,  3/16,  3/16,  8/16}},
    {x =  0, y =  0, z = -1, bit = 32, box = {-3/16, -3/16, -8/16,  3/16,  3/16, -4/16}},
}

function kinetica.is_pipe(name)
return name == "kinetica:steam_pipe" or
string.sub(name or "", 1, 19) == "kinetica:steam_pipe"
end

local function is_water_pump_node(name)
if not name then return false end
    if kinetica.is_water_pump and kinetica.is_water_pump(name) then
        return true
        end
        return name == "kinetica:water_pump" or
        string.sub(name, 1, 20) == "kinetica:water_pump_"
        end

        local function is_turbine_node(name)
        if not name then return false end
            if kinetica.is_turbine and kinetica.is_turbine(name) then
                return true
                end
                return name == "kinetica:turbine" or
                string.sub(name, 1, 17) == "kinetica:turbine_"
                end

                function kinetica.can_pipe_accept(pos, wanted_type)
                local node = core.get_node(pos)
                if not kinetica.is_pipe(node.name) then return false end
                    local meta  = core.get_meta(pos)
                    local ftype = meta:get_string("fluid_type")
                    return (ftype == "" or ftype == "none" or ftype == wanted_type)
                    end

                    local function is_at_turbine_right_input(pipe_pos, turb_pos, turb_param2)
                    local back_dir  = core.facedir_to_dir((turb_param2 or 0) % 4)
                    local right_dir = {x = back_dir.z, y = 0, z = -back_dir.x}
                    return (pipe_pos.x == turb_pos.x + right_dir.x) and
                    (pipe_pos.y == turb_pos.y) and
                    (pipe_pos.z == turb_pos.z + right_dir.z)
                    end

                    local function is_at_turbine_top_vent(pipe_pos, turb_pos)
                    return (pipe_pos.x == turb_pos.x) and
                    (pipe_pos.y == turb_pos.y + 1) and
                    (pipe_pos.z == turb_pos.z)
                    end

                    local function is_at_generator_front(pipe_pos, gen_pos, gen_param2)
                    local back_dir  = core.facedir_to_dir((gen_param2 or 0) % 4)
                    local front_dir = {x = -back_dir.x, y = 0, z = -back_dir.z}
                    return (pipe_pos.x == gen_pos.x + front_dir.x) and
                    (pipe_pos.y == gen_pos.y) and
                    (pipe_pos.z == gen_pos.z + front_dir.z)
                    end

                    local function get_neighbor_designated_type(pos, dir, npos, nnode)
                    local nname = nnode.name

                    if kinetica.is_pipe(nname) then
                        local ntype = core.get_meta(npos):get_string("fluid_type")
                        if ntype == "water" or ntype == "steam" or ntype == "exhaust" then
                            return ntype
                            end
                            return nil
                            end

                            if is_water_pump_node(nname) then
                                if dir.y == -1 then
                                    return "water"
                                    end
                                    return nil
                                    end

                                    if nname == "kinetica:steam_generator" or nname == "kinetica:steam_generator_active" then
                                        if dir.y == -1 then
                                            return "steam"
                                            elseif not (dir.y == 0 and is_at_generator_front(pos, npos, nnode.param2)) then
                                                return "water"
                                                end
                                                end

                                                if is_turbine_node(nname) then
                                                    if is_at_turbine_right_input(pos, npos, nnode.param2) then
                                                        return "steam"
                                                        elseif is_at_turbine_top_vent(pos, npos) then
                                                            return "exhaust"
                                                            end
                                                            end

                                                            return nil
                                                            end

                                                            local function can_connect_to_port(pos, my_type, dir, npos, nnode)
                                                            local nname = nnode.name

                                                            if kinetica.is_pipe(nname) then
                                                                local ntype = core.get_meta(npos):get_string("fluid_type")
                                                                if ntype == "" then ntype = "none" end
                                                                    if my_type == "none" or ntype == "none" or my_type == ntype then
                                                                        return true
                                                                        end
                                                                        return false
                                                                        end

                                                                        local port_type = get_neighbor_designated_type(pos, dir, npos, nnode)
                                                                        if port_type then
                                                                            return (my_type == "none" or my_type == port_type)
                                                                            end

                                                                            return false
                                                                            end

                                                                            function kinetica.update_pipe_visuals(pos, update_neighbors)
                                                                            local node = core.get_node(pos)
                                                                            if not kinetica.is_pipe(node.name) then return end

                                                                                local meta   = core.get_meta(pos)
                                                                                local ftype  = meta:get_string("fluid_type")
                                                                                local amount = math.max(0, meta:get_int("fluid_amount"))

                                                                                if ftype == "" then
                                                                                    ftype = "none"
                                                                                    end

                                                                                    if ftype == "none" then
                                                                                        for _, d in ipairs(pipe_dirs) do
                                                                                            local npos     = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
                                                                                            local nnode    = core.get_node(npos)
                                                                                            local detected = get_neighbor_designated_type(pos, d, npos, nnode)
                                                                                            if detected then
                                                                                                ftype = detected
                                                                                                meta:set_string("fluid_type", ftype)
                                                                                                update_neighbors = true
                                                                                                break
                                                                                                end
                                                                                                end
                                                                                                end

                                                                                                local mask       = 0
                                                                                                local port_count = 0
                                                                                                for _, d in ipairs(pipe_dirs) do
                                                                                                    local npos  = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
                                                                                                    local nnode = core.get_node(npos)
                                                                                                    if can_connect_to_port(pos, ftype, d, npos, nnode) then
                                                                                                        mask       = mask + d.bit
                                                                                                        port_count = port_count + 1
                                                                                                        end
                                                                                                        end
                                                                                                        meta:set_int("port_count", port_count)

                                                                                                        local prefix = "kinetica:steam_pipe_empty_"
                                                                                                        if ftype == "water" then
                                                                                                            prefix = "kinetica:steam_pipe_water_"
                                                                                                            if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
                                                                                                                meta:set_string("infotext", "Water Pipe (Water: " .. amount .. "%)")
                                                                                                                end
                                                                                                                elseif ftype == "steam" then
                                                                                                                    prefix = "kinetica:steam_pipe_steam_"
                                                                                                                    if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
                                                                                                                        meta:set_string("infotext", "Steam Pipe (Steam: " .. amount .. "%)")
                                                                                                                        end
                                                                                                                        elseif ftype == "exhaust" then
                                                                                                                            prefix = "kinetica:steam_pipe_exhaust_"
                                                                                                                            if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
                                                                                                                                meta:set_string("infotext", "Exhaust Pipe (Exhaust: " .. amount .. "%)")
                                                                                                                                end
                                                                                                                                else
                                                                                                                                    if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
                                                                                                                                        meta:set_string("infotext", "Copper Pipe (Unassigned)")
                                                                                                                                        end
                                                                                                                                        end

                                                                                                                                        local target_name = (ftype == "none" and mask == 0) and "kinetica:steam_pipe" or (prefix .. mask)
                                                                                                                                        if node.name ~= target_name then
                                                                                                                                            core.swap_node(pos, {name = target_name, param2 = 0})
                                                                                                                                            end

                                                                                                                                            if update_neighbors then
                                                                                                                                                for _, d in ipairs(pipe_dirs) do
                                                                                                                                                    local npos = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
                                                                                                                                                    if kinetica.is_pipe(core.get_node(npos).name) then
                                                                                                                                                        kinetica.update_pipe_visuals(npos, false)
                                                                                                                                                        end
                                                                                                                                                        end
                                                                                                                                                        end
                                                                                                                                                        end

                                                                                                                                                        function kinetica.add_fluid_to_pipe(pos, wanted_type, add_amount)
                                                                                                                                                        if not kinetica.can_pipe_accept(pos, wanted_type) then return false end
                                                                                                                                                            local meta     = core.get_meta(pos)
                                                                                                                                                            local old_type = meta:get_string("fluid_type")
                                                                                                                                                            local cur      = meta:get_int("fluid_amount")
                                                                                                                                                            meta:set_string("fluid_type", wanted_type)
                                                                                                                                                            meta:set_int("fluid_amount", math.min(CONFIG.MAX_FLUID_CAPACITY, cur + add_amount))
                                                                                                                                                            kinetica.update_pipe_visuals(pos, old_type ~= wanted_type)
                                                                                                                                                            local timer = core.get_node_timer(pos)
                                                                                                                                                            if not timer:is_started() then
                                                                                                                                                                timer:start(1.0)
                                                                                                                                                                end
                                                                                                                                                                return true
                                                                                                                                                                end

                                                                                                                                                                local function is_edible_food(item_name)
                                                                                                                                                                local def = core.registered_items[item_name]
                                                                                                                                                                if not def then return false end
                                                                                                                                                                    return (core.get_item_group(item_name, "eatable") > 0) or
                                                                                                                                                                    (core.get_item_group(item_name, "food") > 0) or
                                                                                                                                                                    (def._mcl_saturation ~= nil)
                                                                                                                                                                    end

                                                                                                                                                                    local function handle_steam_jet_effects(pos, vent_dir)
                                                                                                                                                                    local pmeta    = core.get_meta(pos)
                                                                                                                                                                    local dmg_tick = (pmeta:get_int("dmg_tick") + 1) % 2
                                                                                                                                                                    pmeta:set_int("dmg_tick", dmg_tick)
                                                                                                                                                                    local deal_damage_this_tick = (dmg_tick == 0)

                                                                                                                                                                    for dist = 1, CONFIG.STEAM_JET_REACH do
                                                                                                                                                                        local check_pos = {
                                                                                                                                                                            x = pos.x + (vent_dir.x * dist),
                                                                                                                                                                            y = pos.y + (vent_dir.y * dist),
                                                                                                                                                                            z = pos.z + (vent_dir.z * dist),
                                                                                                                                                                        }

                                                                                                                                                                        local check_node = core.get_node(check_pos)
                                                                                                                                                                        local ndef       = core.registered_nodes[check_node.name]
                                                                                                                                                                        if ndef and ndef.walkable then
                                                                                                                                                                            break
                                                                                                                                                                            end

                                                                                                                                                                            local objs = core.get_objects_inside_radius(check_pos, 0.75)
                                                                                                                                                                            for _, obj in ipairs(objs) do
                                                                                                                                                                                local luaent = obj:get_luaentity()

                                                                                                                                                                                if obj:is_player() or (luaent and (luaent.is_mob or luaent._cmi_is_mob or luaent.health)) then
                                                                                                                                                                                    if deal_damage_this_tick then
                                                                                                                                                                                        obj:punch(obj, 1.0, {
                                                                                                                                                                                            full_punch_interval = 1.0,
                                                                                                                                                                                            damage_groups       = {fleshy = 1},
                                                                                                                                                                                        }, nil)
                                                                                                                                                                                        end
                                                                                                                                                                                        elseif luaent and luaent.name == "__builtin:item" and luaent.itemstring then
                                                                                                                                                                                            local stack       = ItemStack(luaent.itemstring)
                                                                                                                                                                                            local single_item = ItemStack(stack:get_name() .. " 1")
                                                                                                                                                                                            local cooked, _   = core.get_craft_result({
                                                                                                                                                                                                method = "cooking",
                                                                                                                                                                                                width  = 1,
                                                                                                                                                                                                items  = {single_item},
                                                                                                                                                                                            })

                                                                                                                                                                                            if cooked and not cooked.item:is_empty() and is_edible_food(cooked.item:get_name()) then
                                                                                                                                                                                                luaent._steam_cook_time = (luaent._steam_cook_time or 0) + 1

                                                                                                                                                                                                local ipos = obj:get_pos()
                                                                                                                                                                                                if ipos then
                                                                                                                                                                                                    core.add_particlespawner({
                                                                                                                                                                                                        amount     = 3,
                                                                                                                                                                                                        time       = 0.5,
                                                                                                                                                                                                        minpos     = {x = ipos.x - 0.1, y = ipos.y,       z = ipos.z - 0.1},
                                                                                                                                                                                                        maxpos     = {x = ipos.x + 0.1, y = ipos.y + 0.2, z = ipos.z + 0.1},
                                                                                                                                                                                                        minvel     = {x = -0.1,         y = 0.3,          z = -0.1},
                                                                                                                                                                                                        maxvel     = {x =  0.1,         y = 0.6,          z =  0.1},
                                                                                                                                                                                                        minexptime = 0.3,
                                                                                                                                                                                                        maxexptime = 0.6,
                                                                                                                                                                                                        minsize    = 1.0,
                                                                                                                                                                                                        maxsize    = 1.8,
                                                                                                                                                                                                        texture    = "mcl_particles_smoke.png",
                                                                                                                                                                                                    })
                                                                                                                                                                                                    end

                                                                                                                                                                                                    if luaent._steam_cook_time >= CONFIG.STEAM_COOK_SECONDS then
                                                                                                                                                                                                        local cooked_stack = ItemStack(cooked.item:get_name() .. " " .. stack:get_count())
                                                                                                                                                                                                        luaent:set_item(cooked_stack:to_string())
                                                                                                                                                                                                        luaent._steam_cook_time = 0
                                                                                                                                                                                                        if ipos then
                                                                                                                                                                                                            core.sound_play("fire_extinguish_flame", {pos = ipos, max_hear_distance = 10, gain = 0.3}, true)
                                                                                                                                                                                                            end
                                                                                                                                                                                                            end
                                                                                                                                                                                                            end
                                                                                                                                                                                                            end
                                                                                                                                                                                                            end
                                                                                                                                                                                                            end
                                                                                                                                                                                                            end

                                                                                                                                                                                                            local function pipe_timer(pos, elapsed)
                                                                                                                                                                                                            local meta   = core.get_meta(pos)
                                                                                                                                                                                                            local ftype  = meta:get_string("fluid_type")
                                                                                                                                                                                                            local amount = meta:get_int("fluid_amount")

                                                                                                                                                                                                            if amount <= 0 or ftype == "" or ftype == "none" then
                                                                                                                                                                                                                meta:set_int("fluid_amount", 0)
                                                                                                                                                                                                                meta:set_int("is_venting", 0)
                                                                                                                                                                                                                kinetica.update_pipe_visuals(pos, false)
                                                                                                                                                                                                                return false
                                                                                                                                                                                                                end

                                                                                                                                                                                                                local connections        = 0
                                                                                                                                                                                                                local last_connected_dir = nil

                                                                                                                                                                                                                for _, d in ipairs(pipe_dirs) do
                                                                                                                                                                                                                    local npos  = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
                                                                                                                                                                                                                    local nnode = core.get_node(npos)

                                                                                                                                                                                                                    if can_connect_to_port(pos, ftype, d, npos, nnode) then
                                                                                                                                                                                                                        connections        = connections + 1
                                                                                                                                                                                                                        last_connected_dir = d

                                                                                                                                                                                                                        if kinetica.is_pipe(nnode.name) then
                                                                                                                                                                                                                            local nmeta   = core.get_meta(npos)
                                                                                                                                                                                                                            local namount = nmeta:get_int("fluid_amount")
                                                                                                                                                                                                                            if amount > namount + 1 then
                                                                                                                                                                                                                                local transfer  = math.ceil((amount - namount) * CONFIG.PIPE_TRANSFER_RATIO)
                                                                                                                                                                                                                                amount          = amount - transfer
                                                                                                                                                                                                                                local old_ntype = nmeta:get_string("fluid_type")
                                                                                                                                                                                                                                nmeta:set_string("fluid_type", ftype)
                                                                                                                                                                                                                                nmeta:set_int("fluid_amount", math.min(CONFIG.MAX_FLUID_CAPACITY, namount + transfer))
                                                                                                                                                                                                                                kinetica.update_pipe_visuals(npos, old_ntype ~= ftype)
                                                                                                                                                                                                                                local ntimer = core.get_node_timer(npos)
                                                                                                                                                                                                                                if not ntimer:is_started() then ntimer:start(1.0) end
                                                                                                                                                                                                                                    end

                                                                                                                                                                                                                                    elseif (nnode.name == "kinetica:steam_generator" or nnode.name == "kinetica:steam_generator_active")
                                                                                                                                                                                                                                        and d.y ~= -1 and ftype == "water" then
                                                                                                                                                                                                                                        local gmeta   = core.get_meta(npos)
                                                                                                                                                                                                                                        local g_water = gmeta:get_int("water_level")
                                                                                                                                                                                                                                        if g_water < 100 and amount > 0 then
                                                                                                                                                                                                                                            local give      = math.min(amount, CONFIG.MACHINE_INJECT_MAX, 100 - g_water)
                                                                                                                                                                                                                                            amount          = amount - give
                                                                                                                                                                                                                                            local new_water = g_water + give
                                                                                                                                                                                                                                            gmeta:set_int("water_level", new_water)
                                                                                                                                                                                                                                            gmeta:set_int("display_water", new_water)

                                                                                                                                                                                                                                            local ginv      = gmeta:get_inventory()
                                                                                                                                                                                                                                            local show_icon = ginv:get_stack("water", 1):is_empty()
                                                                                                                                                                                                                                            local b_time    = gmeta:get_float("burn_time")
                                                                                                                                                                                                                                            local m_burn    = math.max(1, gmeta:get_float("max_burn"))
                                                                                                                                                                                                                                            local b_pct     = (b_time > 0) and ((b_time / m_burn) * 100) or 0
                                                                                                                                                                                                                                            gmeta:set_string("formspec", kinetica.get_steam_gen_formspec(b_pct, new_water, show_icon))

                                                                                                                                                                                                                                            local gtimer = core.get_node_timer(npos)
                                                                                                                                                                                                                                            if not gtimer:is_started() then gtimer:start(1.0) end
                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                elseif is_turbine_node(nnode.name)
                                                                                                                                                                                                                                                    and ftype == "steam" and is_at_turbine_right_input(pos, npos, nnode.param2) then
                                                                                                                                                                                                                                                    if amount > 0 then
                                                                                                                                                                                                                                                        local tmeta   = core.get_meta(npos)
                                                                                                                                                                                                                                                        local t_steam = tmeta:get_int("steam")
                                                                                                                                                                                                                                                        if t_steam < 100 then
                                                                                                                                                                                                                                                            local give = math.min(amount, CONFIG.MACHINE_INJECT_MAX, 100 - t_steam)
                                                                                                                                                                                                                                                            amount     = amount - give
                                                                                                                                                                                                                                                            tmeta:set_int("steam", t_steam + give)
                                                                                                                                                                                                                                                            local ttimer = core.get_node_timer(npos)
                                                                                                                                                                                                                                                            if not ttimer:is_started() then ttimer:start(1.0) end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if connections <= 1 and amount > 0 then
                                                                                                                                                                                                                                                                meta:set_int("is_venting", 1)
                                                                                                                                                                                                                                                                local vent_dir = {x = 0, y = 1, z = 0}
                                                                                                                                                                                                                                                                if last_connected_dir then
                                                                                                                                                                                                                                                                vent_dir = {x = -last_connected_dir.x, y = -last_connected_dir.y, z = -last_connected_dir.z}
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if ftype == "steam" or ftype == "exhaust" then
                                                                                                                                                                                                                                                                core.add_particlespawner({
                                                                                                                                                                                                                                                                amount     = 14,
                                                                                                                                                                                                                                                                time       = 1.0,
                                                                                                                                                                                                                                                                minpos     = {x = pos.x + (vent_dir.x * 0.3) - 0.12, y = pos.y + (vent_dir.y * 0.3) - 0.12, z = pos.z + (vent_dir.z * 0.3) - 0.12},
                                                                                                                                                                                                                                                                maxpos     = {x = pos.x + (vent_dir.x * 0.3) + 0.12, y = pos.y + (vent_dir.y * 0.3) + 0.12, z = pos.z + (vent_dir.z * 0.3) + 0.12},
                                                                                                                                                                                                                                                                minvel     = {x = vent_dir.x * 1.8 - 0.15,           y = vent_dir.y * 1.8 - 0.1,            z = vent_dir.z * 1.8 - 0.15},
                                                                                                                                                                                                                                                                maxvel     = {x = vent_dir.x * 2.6 + 0.15,           y = vent_dir.y * 2.6 + 0.2,            z = vent_dir.z * 2.6 + 0.15},
                                                                                                                                                                                                                                                                minexptime = 1.1,
                                                                                                                                                                                                                                                                maxexptime = 1.5,
                                                                                                                                                                                                                                                                minsize    = 1.8,
                                                                                                                                                                                                                                                                maxsize    = 3.8,
                                                                                                                                                                                                                                                                texture    = "mcl_particles_smoke.png",
                                                                                                                                                                                                                                                                })

                                                                                                                                                                                                                                                                handle_steam_jet_effects(pos, vent_dir)
                                                                                                                                                                                                                                                                amount = math.max(0, amount - CONFIG.VENT_DRAIN_PER_SEC)
                                                                                                                                                                                                                                                                elseif ftype == "water" then
                                                                                                                                                                                                                                                                core.add_particlespawner({
                                                                                                                                                                                                                                                                amount     = 8,
                                                                                                                                                                                                                                                                time       = 1.0,
                                                                                                                                                                                                                                                                minpos     = {x = pos.x + (vent_dir.x * 0.25) - 0.1, y = pos.y + (vent_dir.y * 0.25) - 0.1, z = pos.z + (vent_dir.z * 0.25) - 0.1},
                                                                                                                                                                                                                                                                maxpos     = {x = pos.x + (vent_dir.x * 0.25) + 0.1, y = pos.y + (vent_dir.y * 0.25) + 0.1, z = pos.z + (vent_dir.z * 0.25) + 0.1},
                                                                                                                                                                                                                                                                minvel     = {x = vent_dir.x * 0.6 - 0.1,            y = vent_dir.y * 0.4 - 0.5,            z = vent_dir.z * 0.6 - 0.1},
                                                                                                                                                                                                                                                                maxvel     = {x = vent_dir.x * 1.0 + 0.1,            y = vent_dir.y * 0.8 - 0.1,            z = vent_dir.z * 1.0 + 0.1},
                                                                                                                                                                                                                                                                minexptime = 0.5,
                                                                                                                                                                                                                                                                maxexptime = 1.0,
                                                                                                                                                                                                                                                                minsize    = 1.0,
                                                                                                                                                                                                                                                                maxsize    = 2.0,
                                                                                                                                                                                                                                                                texture    = CONFIG.TEX_PIPE_BASE .. "^[colorize:#2266ff:200",
                                                                                                                                                                                                                                                                })
                                                                                                                                                                                                                                                                amount = math.max(0, amount - CONFIG.VENT_DRAIN_PER_SEC)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                meta:set_int("is_venting", 0)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                meta:set_int("fluid_amount", amount)
                                                                                                                                                                                                                                                                kinetica.update_pipe_visuals(pos, false)
                                                                                                                                                                                                                                                                return (amount > 0)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local old_item_place = core.item_place
                                                                                                                                                                                                                                                                function core.item_place(itemstack, placer, pointed_thing, param2)
                                                                                                                                                                                                                                                                if CONFIG.ALLOW_SNEAK_FLUSH_PIPE
                                                                                                                                                                                                                                                                and pointed_thing
                                                                                                                                                                                                                                                                and pointed_thing.type == "node"
                                                                                                                                                                                                                                                                and placer
                                                                                                                                                                                                                                                                and placer:is_player()
                                                                                                                                                                                                                                                                and placer:get_player_control().sneak
                                                                                                                                                                                                                                                                and (not itemstack or itemstack:is_empty()) then

                                                                                                                                                                                                                                                                local pos  = pointed_thing.under
                                                                                                                                                                                                                                                                local node = core.get_node(pos)
                                                                                                                                                                                                                                                                if kinetica.is_pipe(node.name) then
                                                                                                                                                                                                                                                                local pname = placer:get_player_name()
                                                                                                                                                                                                                                                                if not core.is_protected(pos, pname) then
                                                                                                                                                                                                                                                                local meta = core.get_meta(pos)
                                                                                                                                                                                                                                                                meta:set_string("fluid_type", "none")
                                                                                                                                                                                                                                                                meta:set_int("fluid_amount", 0)
                                                                                                                                                                                                                                                                meta:set_int("is_venting", 0)
                                                                                                                                                                                                                                                                kinetica.update_pipe_visuals(pos, true)
                                                                                                                                                                                                                                                                core.sound_play("fire_extinguish_flame", {pos = pos, max_hear_distance = 8, gain = 0.25}, true)
                                                                                                                                                                                                                                                                core.chat_send_player(pname, "[Kinetica] Copper Pipe flushed and reset.")
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                return itemstack, nil
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                return old_item_place(itemstack, placer, pointed_thing, param2)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local pipe_types = {
                                                                                                                                                                                                                                                                {id = "empty",   tex = CONFIG.TEX_PIPE_BASE},
                                                                                                                                                                                                                                                                {id = "water",   tex = CONFIG.TEX_PIPE_BASE .. CONFIG.WATER_COLORIZE},
                                                                                                                                                                                                                                                                {id = "steam",   tex = CONFIG.TEX_PIPE_BASE .. CONFIG.STEAM_COLORIZE},
                                                                                                                                                                                                                                                                {id = "exhaust", tex = CONFIG.TEX_PIPE_BASE},
                                                                                                                                                                                                                                                                }

                                                                                                                                                                                                                                                                for _, ptype in ipairs(pipe_types) do
                                                                                                                                                                                                                                                                for mask = 0, 63 do
                                                                                                                                                                                                                                                                local boxes = {{-4/16, -4/16, -4/16, 4/16, 4/16, 4/16}}
                                                                                                                                                                                                                                                                local rem   = mask
                                                                                                                                                                                                                                                                for i = #pipe_dirs, 1, -1 do
                                                                                                                                                                                                                                                                local d = pipe_dirs[i]
                                                                                                                                                                                                                                                                if rem >= d.bit then
                                                                                                                                                                                                                                                                table.insert(boxes, d.box)
                                                                                                                                                                                                                                                                rem = rem - d.bit
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local is_base_item = (ptype.id == "empty" and mask == 0)
                                                                                                                                                                                                                                                                local node_name    = is_base_item and "kinetica:steam_pipe" or ("kinetica:steam_pipe_" .. ptype.id .. "_" .. mask)
                                                                                                                                                                                                                                                                local groups       = {pickaxey = 1, steam_connectable = 1, kinetica_fluid_pipe = 1}
                                                                                                                                                                                                                                                                if not is_base_item then
                                                                                                                                                                                                                                                                groups.not_in_creative_inventory = 1
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                core.register_node(node_name, {
                                                                                                                                                                                                                                                                description           = "Copper Fluid Pipe\nConnects to Water Pumps, Steam Generators & Steam Turbines.\nSneak + Right-Click (empty hand) to flush & reset fluid type.",
                                                                                                                                                                                                                                                                drawtype              = "nodebox",
                                                                                                                                                                                                                                                                paramtype             = "light",
                                                                                                                                                                                                                                                                sunlight_propagates   = true,
                                                                                                                                                                                                                                                                tiles                 = {ptype.tex},
                                                                                                                                                                                                                                                                node_box = {
                                                                                                                                                                                                                                                                type  = "fixed",
                                                                                                                                                                                                                                                                fixed = boxes,
                                                                                                                                                                                                                                                                },
                                                                                                                                                                                                                                                                drop                  = "kinetica:steam_pipe",
                                                                                                                                                                                                                                                                groups                = groups,
                                                                                                                                                                                                                                                                _mcl_hardness         = 2.0,
                                                                                                                                                                                                                                                                _mcl_blast_resistance = 3.0,
                                                                                                                                                                                                                                                                sounds                = mcl_sounds.node_sound_metal_defaults(),

                                                                                                                                                                                                                                                                on_construct = is_base_item and function(pos)
                                                                                                                                                                                                                                                                local meta = core.get_meta(pos)
                                                                                                                                                                                                                                                                meta:set_string("fluid_type", "none")
                                                                                                                                                                                                                                                                meta:set_int("fluid_amount", 0)
                                                                                                                                                                                                                                                                if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
                                                                                                                                                                                                                                                                meta:set_string("infotext", "Copper Pipe (Unassigned)")
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                kinetica.update_pipe_visuals(pos, true)
                                                                                                                                                                                                                                                                core.get_node_timer(pos):start(1.0)
                                                                                                                                                                                                                                                                end or nil,

                                                                                                                                                                                                                                                                after_dig_node = function(pos)
                                                                                                                                                                                                                                                                for _, d in ipairs(pipe_dirs) do
                                                                                                                                                                                                                                                                local npos = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
                                                                                                                                                                                                                                                                if kinetica.is_pipe(core.get_node(npos).name) then
                                                                                                                                                                                                                                                                kinetica.update_pipe_visuals(npos, false)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end,

                                                                                                                                                                                                                                                                on_timer = pipe_timer,
                                                                                                                                                                                                                                                                })
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                core.register_lbm({
                                                                                                                                                                                                                                                                label             = "Wake kinetica Fluid Pipes on chunk load",
                                                                                                                                                                                                                                                                name              = "kinetica:wake_fluid_pipes_lbm",
                                                                                                                                                                                                                                                                nodenames         = {"group:kinetica_fluid_pipe"},
                                                                                                                                                                                                                                                                run_at_every_load = true,
                                                                                                                                                                                                                                                                action = function(pos, node)
                                                                                                                                                                                                                                                                local meta = core.get_meta(pos)
                                                                                                                                                                                                                                                                if meta:get_int("fluid_amount") > 0 then
                                                                                                                                                                                                                                                                local timer = core.get_node_timer(pos)
                                                                                                                                                                                                                                                                if not timer:is_started() then
                                                                                                                                                                                                                                                                timer:start(1.0)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end,
                                                                                                                                                                                                                                                                })

                                                                                                                                                                                                                                                                core.register_on_placenode(function(pos, newnode)
                                                                                                                                                                                                                                                                if core.get_item_group(newnode.name, "steam_connectable") > 0 then
                                                                                                                                                                                                                                                                for _, d in ipairs(pipe_dirs) do
                                                                                                                                                                                                                                                                local npos = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
                                                                                                                                                                                                                                                                if kinetica.is_pipe(core.get_node(npos).name) then
                                                                                                                                                                                                                                                                kinetica.update_pipe_visuals(npos, true)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end)

                                                                                                                                                                                                                                                                core.register_on_dignode(function(pos, oldnode)
                                                                                                                                                                                                                                                                if core.get_item_group(oldnode.name, "steam_connectable") > 0 then
                                                                                                                                                                                                                                                                for _, d in ipairs(pipe_dirs) do
                                                                                                                                                                                                                                                                local npos = {x = pos.x + d.x, y = pos.y + d.y, z = pos.z + d.z}
                                                                                                                                                                                                                                                                if kinetica.is_pipe(core.get_node(npos).name) then
                                                                                                                                                                                                                                                                kinetica.update_pipe_visuals(npos, false)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end)

                                                                                                                                                                                                                                                                core.register_craft({
                                                                                                                                                                                                                                                                output = "kinetica:steam_pipe 8",
                                                                                                                                                                                                                                                                recipe = {
                                                                                                                                                                                                                                                                {"kinetica:sheet_copper", "kinetica:sheet_copper", "kinetica:sheet_copper"},
                                                                                                                                                                                                                                                                },
                                                                                                                                                                                                                                                                })
