local modname = core.get_current_modname() or "kinetica"

kinetica = kinetica or {}
kinetica.registered_machines = kinetica.registered_machines or {}

kinetica.api = {
    math = {},
    network = {},
    machines = {},
    recipes = {},
    telemetry = {},
    contraptions = {}
}

-- ============================================================================
-- 1. MATH & ROTATION API
-- Universal 3D matrix-to-Euler math and RPM scaling for entity animations.
-- ============================================================================

function kinetica.api.math.mat3_mul(A, B)
    return {
        {
            A[1][1]*B[1][1] + A[1][2]*B[2][1] + A[1][3]*B[3][1],
            A[1][1]*B[1][2] + A[1][2]*B[2][2] + A[1][3]*B[3][2],
            A[1][1]*B[1][3] + A[1][2]*B[2][3] + A[1][3]*B[3][3],
        },
        {
            A[2][1]*B[1][1] + A[2][2]*B[2][1] + A[2][3]*B[3][1],
            A[2][1]*B[1][2] + A[2][2]*B[2][2] + A[2][3]*B[3][2],
            A[2][1]*B[1][3] + A[2][2]*B[2][3] + A[2][3]*B[3][3],
        },
        {
            A[3][1]*B[1][1] + A[3][2]*B[2][1] + A[3][3]*B[3][1],
            A[3][1]*B[1][2] + A[3][2]*B[2][2] + A[3][3]*B[3][2],
            A[3][1]*B[1][3] + A[3][2]*B[2][3] + A[3][3]*B[3][3],
        },
    }
end

function kinetica.api.math.mat3_to_luanti_euler(R)
    local sx = math.max(-1.0, math.min(1.0, -R[2][3]))
    local x  = math.asin(sx)
    local cx = math.cos(x)
    local y, z
    if math.abs(cx) > 1e-4 then
        y = math.atan2(-R[1][3], R[3][3])
        z = math.atan2(-R[2][1], R[2][2])
    else
        y = math.atan2(R[3][1], R[1][1])
        z = 0
    end
    return {x = x, y = y, z = z}
end

function kinetica.api.math.dir_align_matrix(dir)
    if dir.y > 0 then return {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}, "UP"
    elseif dir.y < 0 then return {{ 1, 0, 0}, { 0, -1, 0}, { 0, 0, -1}}, "DOWN"
    elseif dir.z > 0 then return {{1, 0, 0}, {0, 0, -1}, {0, 1, 0}}, "NORTH"
    elseif dir.z < 0 then return {{1, 0, 0}, {0, 0, 1}, {0, -1, 0}}, "SOUTH"
    elseif dir.x > 0 then return {{ 0, 1, 0}, {-1, 0, 0}, { 0, 0, 1}}, "EAST"
    else return {{0, -1, 0}, {1, 0, 0}, {0, 0, 1}}, "WEST" end
end

function kinetica.api.math.rpm_factor(rpm, min_rpm, max_rpm)
    min_rpm = min_rpm or 16
    max_rpm = max_rpm or 512
    if not rpm or rpm <= min_rpm then return 0.0 end
    return math.min(1.0, math.max(0.0, (rpm - min_rpm) / (max_rpm - min_rpm)))
end

function kinetica.api.math.lerp(a, b, t)
    return a + t * (b - a)
end

-- ============================================================================
-- 2. NETWORK SOLVER API
-- Handles all power transmission, load balancing, and overstress calculations.
-- ============================================================================

kinetica.api.network.solver_depth = 0
local MAX_SOLVER_DEPTH = 8
local ALL_DIRS = {
    {x =  1, y =  0, z =  0}, {x = -1, y =  0, z =  0},
    {x =  0, y =  1, z =  0}, {x =  0, y = -1, z =  0},
    {x =  0, y =  0, z =  1}, {x =  0, y =  0, z = -1},
}

local function are_contraption_coupled(nodeA, nodeB, dir, posA, posB)
    local nameA, nameB = nodeA.name, nodeB.name

    -- NEW: Power routes continuously through Super Glued regions
    if posA and posB and kinetica.api.contraptions.are_positions_glued(posA, posB) then
        return true
    end

    if kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(nameA) and kinetica.is_piston_pole_or_head and kinetica.is_piston_pole_or_head(nameB) then
        local backA = core.facedir_to_dir(nodeA.param2 or 0) or {x = 0, y = 0, z = 1}
        if dir.x == -backA.x and dir.y == -backA.y and dir.z == -backA.z and nodeA.param2 == nodeB.param2 then return true end
    end
    if kinetica.is_piston_pole_or_head and kinetica.is_piston_pole_or_head(nameA) and kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(nameB) then
        local backB = core.facedir_to_dir(nodeB.param2 or 0) or {x = 0, y = 0, z = 1}
        if dir.x == backB.x and dir.y == backB.y and dir.z == backB.z and nodeA.param2 == nodeB.param2 then return true end
    end

    if kinetica.is_piston_pole_or_head and kinetica.is_piston_pole_or_head(nameA) and kinetica.is_piston_pole_or_head(nameB) then
        local backA = core.facedir_to_dir(nodeA.param2 or 0) or {x = 0, y = 0, z = 1}
        if nodeA.param2 == nodeB.param2 and math.abs(dir.x) == math.abs(backA.x) and math.abs(dir.y) == math.abs(backA.y) and math.abs(dir.z) == math.abs(backA.z) then
            return true
        end
    end

    if (kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(nameA)) or nameA == "kinetica:piston_head" or nameA == "kinetica:piston_head_sticky" then
        local backA = core.facedir_to_dir(nodeA.param2 or 0) or {x = 0, y = 0, z = 1}
        if dir.x == -backA.x and dir.y == -backA.y and dir.z == -backA.z then
            local mdefB = kinetica.get_machine_def and kinetica.get_machine_def(nameB)
            if (mdefB and mdefB.can_ride_piston ~= false) or (kinetica.is_sticky_contraption_frame and kinetica.is_sticky_contraption_frame(nameB)) then return true end
        end
    end
    if (kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(nameB)) or nameB == "kinetica:piston_head" or nameB == "kinetica:piston_head_sticky" then
        local backB = core.facedir_to_dir(nodeB.param2 or 0) or {x = 0, y = 0, z = 1}
        if dir.x == backB.x and dir.y == backB.y and dir.z == backB.z then
            local mdefA = kinetica.get_machine_def and kinetica.get_machine_def(nameA)
            if (mdefA and mdefA.can_ride_piston ~= false) or (kinetica.is_sticky_contraption_frame and kinetica.is_sticky_contraption_frame(nameA)) then return true end
        end
    end

    local stickyA = kinetica.is_sticky_contraption_frame and kinetica.is_sticky_contraption_frame(nameA)
    local stickyB = kinetica.is_sticky_contraption_frame and kinetica.is_sticky_contraption_frame(nameB)
    local mdefA   = kinetica.get_machine_def and kinetica.get_machine_def(nameA)
    local mdefB   = kinetica.get_machine_def and kinetica.get_machine_def(nameB)

    if stickyA and stickyB then return true end
    if stickyA and (mdefB and mdefB.can_ride_piston ~= false) then return true end
    if stickyB and (mdefA and mdefA.can_ride_piston ~= false) then return true end
    return false
end

function kinetica.api.network.are_coupled(nodeA, nodeB, dir, posA, posB)
    if kinetica.is_chain_drive and kinetica.is_chain_drive(nodeA.name) and kinetica.is_chain_drive(nodeB.name) then
        local axA = kinetica.abs_axis(nodeA.param2)
        local axB = kinetica.abs_axis(nodeB.param2)
        if axA.x == axB.x and axA.y == axB.y and axA.z == axB.z and not (math.abs(dir.x) == axA.x and math.abs(dir.y) == axA.y and math.abs(dir.z) == axA.z) then
            return true, "chain_side"
        end
    end

    local rev = {x = -dir.x, y = -dir.y, z = -dir.z}
    if kinetica.has_axle_port and kinetica.has_axle_port(nodeA, dir, posA) and kinetica.has_axle_port(nodeB, rev, posB) then
        return true, "axle"
    end

    -- NEW: Pass the posA and posB variables we added above
    if are_contraption_coupled(nodeA, nodeB, dir, posA, posB) then
        return true, "contraption"
    end
    return false, nil
end


local function gearbox_port_alpha(node_name, p)
    local is_vert = string.find(node_name, "vertical") ~= nil
    if is_vert then return (p.y ~= 0) and 1 or -1
    else return (p.z ~= 0) and 1 or -1 end
end

local function is_gearshift_powered_at(pos)
    if not pos then return false end
    if kinetica.gearshift_has_redstone then return kinetica.gearshift_has_redstone(pos) end
    if mcl_redstone and mcl_redstone.get_power then
        local ok, pwr = pcall(mcl_redstone.get_power, vector.new(pos.x, pos.y, pos.z))
        if ok and type(pwr) == "number" and pwr > 0 then return true end
    end
    return false
end

local function get_edge_spin_mult(nodeA, nodeB, dir, posA, posB)
    local mult = 1
    if kinetica.is_gearbox and kinetica.is_gearbox(nodeA.name) then
        local sigma_out = dir.x + dir.y + dir.z
        local alpha_out = gearbox_port_alpha(nodeA.name, dir)
        mult = mult * (-sigma_out * alpha_out)
    end
    if kinetica.is_gearbox and kinetica.is_gearbox(nodeB.name) then
        local in_port = {x = -dir.x, y = -dir.y, z = -dir.z}
        local sigma_in = in_port.x + in_port.y + in_port.z
        local alpha_in = gearbox_port_alpha(nodeB.name, in_port)
        mult = mult * (-sigma_in * alpha_in)
    end
    if kinetica.is_gearshift and kinetica.is_gearshift(nodeA.name) and is_gearshift_powered_at(posA) then
        if (dir.x + dir.y + dir.z) > 0 then mult = mult * -1 end
    end
    if kinetica.is_gearshift and kinetica.is_gearshift(nodeB.name) and is_gearshift_powered_at(posB) then
        local in_port = {x = -dir.x, y = -dir.y, z = -dir.z}
        if (in_port.x + in_port.y + in_port.z) > 0 then mult = mult * -1 end
    end
    return mult
end

function kinetica.api.network.break_conflicting_shaft(cpos)
    local cnode = core.get_node(cpos)
    local drop_item = nil

    if kinetica.is_shaft and kinetica.is_shaft(cnode.name) then drop_item = "kinetica:shaft"
    elseif kinetica.is_gearshift and kinetica.is_gearshift(cnode.name) then drop_item = "kinetica:gearshift"
    elseif kinetica.is_chain_drive and kinetica.is_chain_drive(cnode.name) then drop_item = "kinetica:chain_drive"
    elseif kinetica.is_gearbox and kinetica.is_gearbox(cnode.name) then
        local is_vert = string.find(cnode.name, "vertical") ~= nil
        drop_item = is_vert and "kinetica:gearbox_vertical" or "kinetica:gearbox"
    else return false end

    core.remove_node(cpos)
    core.add_item(cpos, drop_item)
    core.sound_play("default_break_metal", {pos = cpos, max_hear_distance = 16, gain = 1.0}, true)
    core.add_particlespawner({
        amount = 18, time = 0.25,
        minpos = {x = cpos.x - 0.25, y = cpos.y - 0.25, z = cpos.z - 0.25},
        maxpos = {x = cpos.x + 0.25, y = cpos.y + 0.25, z = cpos.z + 0.25},
        minvel = {x = -1.3, y = 0.6, z = -1.3}, maxvel = {x = 1.3, y = 2.4, z = 1.3},
        minexptime = 0.3, maxexptime = 0.8, minsize = 1.5, maxsize = 3.2,
        texture = "mcl_particles_smoke.png",
    })
    return true
end

local function find_conflict_shaft(k1, k2, parent, nodes_by_key)
    local ancestors1 = {}
    local cur = k1
    while cur do
        ancestors1[cur] = true
        cur = parent[cur]
    end

    local path2 = {}
    cur = k2
    while cur and not ancestors1[cur] do
        table.insert(path2, cur)
        cur = parent[cur]
    end
    local lca = cur

    local path = {}
    cur = k1
    while cur and cur ~= lca do
        table.insert(path, cur)
        cur = parent[cur]
    end
    if lca then table.insert(path, lca) end
    for i = #path2, 1, -1 do
        table.insert(path, path2[i])
    end

    local path_shafts = {}
    local path_relays = {}
    for _, k in ipairs(path) do
        local info = nodes_by_key[k]
        if info then
            if kinetica.is_shaft and kinetica.is_shaft(info.node.name) then table.insert(path_shafts, info.pos)
            elseif (kinetica.is_gearbox and kinetica.is_gearbox(info.node.name)) or
                   (kinetica.is_gearshift and kinetica.is_gearshift(info.node.name)) or
                   (kinetica.is_chain_drive and kinetica.is_chain_drive(info.node.name)) then
                table.insert(path_relays, info.pos)
            end
        end
    end

    if #path_shafts > 0 then return path_shafts[math.ceil(#path_shafts / 2)] end
    for _, info in pairs(nodes_by_key) do
        if kinetica.is_shaft and kinetica.is_shaft(info.node.name) then return info.pos end
    end
    if #path_relays > 0 then return path_relays[math.ceil(#path_relays / 2)] end
    return nil
end

local function read_source_state(pos, node)
    if kinetica.is_water_wheel and kinetica.is_water_wheel(node.name) and kinetica.refresh_water_wheel then
        kinetica.refresh_water_wheel(pos, node)
    elseif kinetica.is_turbine and kinetica.is_turbine(node.name) and kinetica.refresh_turbine then
        kinetica.refresh_turbine(pos, node)
    end
    local meta   = core.get_meta(pos)
    local active = meta:get_int("source_active") == 1
    local ku     = meta:get_int("source_ku")
    local rpm    = meta:get_float("source_rpm")
    local spin   = meta:get_int("source_spin")
    if spin == 0 then spin = 1 end
    return active and (ku > 0) and (rpm > 0), ku, rpm, spin
end

local function run_post_solve_actions(actions)
    for i = 1, #actions do actions[i]() end
end

function kinetica.api.network.update(start_pos)
    if kinetica.api.network.solver_depth >= MAX_SOLVER_DEPTH or not start_pos then return end
    local start_node = core.get_node(start_pos)
    if not (kinetica.is_kinetic_node and kinetica.is_kinetic_node(start_node.name)) then return end

    kinetica.api.network.solver_depth = kinetica.api.network.solver_depth + 1
    local now = math.floor(core.get_gametime())
    local post_actions = {}

    local start_key = core.hash_node_position(start_pos)
    local nodes_by_key = {}
    local parent = {}
    local queue = {start_key}

    nodes_by_key[start_key] = {
        key       = start_key,
        pos       = vector.new(start_pos.x, start_pos.y, start_pos.z),
        node      = start_node,
        pol       = 1,
        shaft_run = (kinetica.is_shaft and kinetica.is_shaft(start_node.name)) and 1 or 0,
        in_dir    = {x = 0, y = 0, z = 0},
    }

    local self_loop_conflict = nil
    local head = 1

    while head <= #queue and #queue < (kinetica.MAX_NETWORK_NODES or 512) do
        local cur_key = queue[head]
        head = head + 1
        local cur = nodes_by_key[cur_key]

        for _, d in ipairs(ALL_DIRS) do
            local npos  = vector.new(cur.pos.x + d.x, cur.pos.y + d.y, cur.pos.z + d.z)
            local nnode = core.get_node(npos)

            if kinetica.is_kinetic_node(nnode.name) then
                local coupled, link_type = kinetica.api.network.are_coupled(cur.node, nnode, d, cur.pos, npos)
                if coupled then
                    local next_run = (kinetica.is_shaft and kinetica.is_shaft(nnode.name)) and (cur.shaft_run + 1) or 0
                    if next_run <= (kinetica.MAX_SHAFT_RUN or 32) then
                        local nkey = core.hash_node_position(npos)
                        local mult = (link_type == "contraption") and 1 or get_edge_spin_mult(cur.node, nnode, d, cur.pos, npos)
                        local expected_pol = cur.pol * mult

                        if not nodes_by_key[nkey] then
                            parent[nkey] = cur_key
                            nodes_by_key[nkey] = {
                                key       = nkey,
                                pos       = npos,
                                node      = nnode,
                                pol       = expected_pol,
                                shaft_run = next_run,
                                in_dir    = d,
                            }
                            queue[#queue + 1] = nkey
                        else
                            if link_type ~= "contraption" and nodes_by_key[nkey].pol ~= expected_pol and not self_loop_conflict then
                                self_loop_conflict = {k1 = cur_key, k2 = nkey}
                            end
                        end
                    end
                end
            end
        end
    end

    local water_wheel_count = 0
    local active_sources    = {}

    for _, k in ipairs(queue) do
        local info = nodes_by_key[k]
        if kinetica.is_water_wheel and kinetica.is_water_wheel(info.node.name) then
            water_wheel_count = water_wheel_count + 1
        end
        if kinetica.is_source_node and kinetica.is_source_node(info.node.name, info.pos) then
            local is_act, ku, rpm, spin = read_source_state(info.pos, info.node)
            if is_act then
                table.insert(active_sources, {
                    key = k, pos = info.pos, node = info.node,
                    ku = ku, rpm = rpm, spin = spin, pol = info.pol,
                })
            end
        end
    end

    local max_ww = kinetica.MAX_WATER_WHEELS or 10
    if water_wheel_count > max_ww then
        local limit_msg = string.format("OVERLOADED! (Max %d Water Wheels in series - %d connected!)", max_ww, water_wheel_count)
        for _, k in ipairs(queue) do
            local info = nodes_by_key[k]
            if not kinetica.is_source_node(info.node.name, info.pos) then
                post_actions[#post_actions + 1] = function()
                    kinetica.set_node_idle(info.pos, info.node, limit_msg)
                    core.get_meta(info.pos):set_int("network_overstressed", 1)
                end
            else
                local smeta = core.get_meta(info.pos)
                smeta:set_int("network_overstressed", 1)
                smeta:set_int("network_supply_ku", 0)
                smeta:set_int("network_used_ku", 0)
                smeta:set_int("rotational_power", 0)
                smeta:set_string("infotext", limit_msg)
            end
        end
        kinetica.api.network.solver_depth = kinetica.api.network.solver_depth - 1
        run_post_solve_actions(post_actions)
        return
    end

    if #active_sources == 0 then
        for _, k in ipairs(queue) do
            local info = nodes_by_key[k]
            if not kinetica.is_source_node(info.node.name, info.pos) then
                post_actions[#post_actions + 1] = function() kinetica.set_node_idle(info.pos, info.node) end
            else
                local smeta = core.get_meta(info.pos)
                smeta:set_int("network_overstressed", 0)
                smeta:set_int("network_supply_ku", 0)
                smeta:set_int("network_used_ku", 0)
                smeta:set_int("rotational_power", 0)
            end
        end
        kinetica.api.network.solver_depth = kinetica.api.network.solver_depth - 1
        run_post_solve_actions(post_actions)
        return
    end

    if self_loop_conflict then
        local break_pos = find_conflict_shaft(self_loop_conflict.k1, self_loop_conflict.k2, parent, nodes_by_key)
        kinetica.api.network.solver_depth = kinetica.api.network.solver_depth - 1
        if break_pos and kinetica.api.network.break_conflicting_shaft(break_pos) then
            for _, src in ipairs(active_sources) do
                kinetica.api.network.update(src.pos)
            end
        end
        return
    end

    local ref = active_sources[1]
    local base_spin = ref.spin * ref.pol
    local total_supply_ku = ref.ku
    local shared_rpm = ref.rpm

    for i = 2, #active_sources do
        local s = active_sources[i]
        local expected_s_spin = base_spin * s.pol
        local rpm_mismatch  = math.abs(s.rpm - shared_rpm) > 0.01
        local spin_mismatch = (s.spin ~= expected_s_spin)

        if rpm_mismatch or spin_mismatch then
            local break_pos = find_conflict_shaft(ref.key, s.key, parent, nodes_by_key)
            kinetica.api.network.solver_depth = kinetica.api.network.solver_depth - 1
            if break_pos and kinetica.api.network.break_conflicting_shaft(break_pos) then
                kinetica.api.network.update(ref.pos)
                kinetica.api.network.update(s.pos)
            else
                local reason = rpm_mismatch
                    and string.format("JAMMED: RPM Mismatch (%s RPM vs %s RPM)!", kinetica.format_rpm(shared_rpm), kinetica.format_rpm(s.rpm))
                    or "JAMMED: Conflicting Rotation Directions!"
                for _, k in ipairs(queue) do
                    local info = nodes_by_key[k]
                    if not kinetica.is_source_node(info.node.name, info.pos) then
                        kinetica.set_node_idle(info.pos, info.node, reason)
                    else
                        local smeta = core.get_meta(info.pos)
                        smeta:set_int("network_overstressed", 1)
                        smeta:set_string("infotext", reason)
                    end
                end
            end
            return
        end
        total_supply_ku = total_supply_ku + s.ku
    end

    local gearbox_count     = 0
    local gearshift_count   = 0
    local chain_drive_count = 0
    local pump_count        = 0
    local piston_count      = 0
    local custom_machine_ku = 0

    local per_pump_ku       = kinetica.get_pump_demand_ku and kinetica.get_pump_demand_ku(shared_rpm) or 16
    local per_piston_ku     = kinetica.get_piston_demand_ku and kinetica.get_piston_demand_ku(shared_rpm) or 16

    for _, k in ipairs(queue) do
        local info  = nodes_by_key[k]
        local nname = info.node.name
        if not kinetica.is_source_node(nname, info.pos) then
            if kinetica.is_gearbox and kinetica.is_gearbox(nname) then gearbox_count = gearbox_count + 1
            elseif kinetica.is_gearshift and kinetica.is_gearshift(nname) then gearshift_count = gearshift_count + 1
            elseif kinetica.is_chain_drive and kinetica.is_chain_drive(nname) then chain_drive_count = chain_drive_count + 1
            elseif kinetica.is_water_pump and kinetica.is_water_pump(nname) then pump_count = pump_count + 1
            elseif kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(nname) then
                piston_count = piston_count + 1
                local glue_ku = core.get_meta(info.pos):get_int("glue_attached_ku")
                if glue_ku > 0 then
                    custom_machine_ku = custom_machine_ku + glue_ku
                end
            else
                local mdef = kinetica.get_machine_def and kinetica.get_machine_def(nname)
                if mdef then
                    local m_ku = mdef.get_demand_ku and mdef.get_demand_ku(shared_rpm, info.pos, info.node, total_supply_ku) or 16
                    info.machine_demand_ku = m_ku
                    custom_machine_ku = custom_machine_ku + m_ku
                end
            end
        end
    end

    local total_fines        = (gearbox_count * (kinetica.GEARBOX_FINE_KU or 1))
                             + (gearshift_count * (kinetica.GEARSHIFT_FINE_KU or 1))
                             + (chain_drive_count * (kinetica.CHAIN_DRIVE_FINE_KU or 1))
    local after_fines_ku     = math.max(0, total_supply_ku - total_fines)
    local total_demand_ku    = total_fines + (pump_count * per_pump_ku) + (piston_count * per_piston_ku) + custom_machine_ku

    if total_supply_ku < total_demand_ku or (total_fines > 0 and after_fines_ku <= 0) then
        local over_msg = string.format("OVERSTRESSED! (Network Demand: %s KU > Supply: %s KU @ %s RPM)",
            kinetica.format_int(total_demand_ku), kinetica.format_int(total_supply_ku), kinetica.format_rpm(shared_rpm))
        for _, k in ipairs(queue) do
            local info = nodes_by_key[k]
            local nspin = (base_spin * info.pol >= 0) and 1 or -1
            if not kinetica.is_source_node(info.node.name, info.pos) then
                local mdef = kinetica.get_machine_def and kinetica.get_machine_def(info.node.name)
                post_actions[#post_actions + 1] = function()
                    kinetica.set_node_idle(info.pos, info.node, over_msg)
                    local m = core.get_meta(info.pos)
                    m:set_int("network_overstressed", 1)
                    m:set_int("network_supply_ku", total_supply_ku)
                    m:set_int("network_used_ku", total_demand_ku)
                    if mdef and mdef.on_overstress then
                        mdef.on_overstress(info.pos, core.get_node(info.pos), shared_rpm, nspin, total_supply_ku, total_demand_ku, info.machine_demand_ku or 0)
                    end
                end
            else
                local smeta = core.get_meta(info.pos)
                smeta:set_int("network_overstressed", 1)
                smeta:set_int("network_supply_ku", total_supply_ku)
                smeta:set_int("network_used_ku", total_demand_ku)
                smeta:set_int("rotational_power", 0)
                smeta:set_string("infotext", over_msg)
            end
        end
        kinetica.api.network.solver_depth = kinetica.api.network.solver_depth - 1
        run_post_solve_actions(post_actions)
        return
    end

    local shared_avail_ku = math.max(0, total_supply_ku - total_demand_ku)
    local dist_map = {}
    local dqueue = {}
    for _, k in ipairs(queue) do
        local info = nodes_by_key[k]
        if not (kinetica.is_shaft and kinetica.is_shaft(info.node.name)) then
            dist_map[k] = 0
            dqueue[#dqueue + 1] = k
        end
    end
    local dhead = 1
    while dhead <= #dqueue do
        local ck = dqueue[dhead]
        dhead = dhead + 1
        local cinfo = nodes_by_key[ck]
        local cdist = dist_map[ck]
        for _, d in ipairs(ALL_DIRS) do
            local npos = {x = cinfo.pos.x + d.x, y = cinfo.pos.y + d.y, z = cinfo.pos.z + d.z}
            local nkey = core.hash_node_position(npos)
            local ninfo = nodes_by_key[nkey]
            if ninfo and dist_map[nkey] == nil then
                local coupled, _ = kinetica.api.network.are_coupled(cinfo.node, ninfo.node, d, cinfo.pos, ninfo.pos)
                if coupled then
                    dist_map[nkey] = cdist + 1
                    dqueue[#dqueue + 1] = nkey
                end
            end
        end
    end

    local function get_anim_tier_name(rpm)
        local clamped = math.min(kinetica.MAX_RPM_CAP or 3072, math.max(0, rpm or 0))
        for _, tier in ipairs(kinetica.api.registration.ANIM_TIERS) do
            if clamped <= tier.max_rpm then return tier.name end
        end
        return kinetica.api.registration.ANIM_TIERS[#kinetica.api.registration.ANIM_TIERS].name
    end
    
    local tier_name = get_anim_tier_name(shared_rpm)

    for _, k in ipairs(queue) do
        local info  = nodes_by_key[k]
        local pos   = info.pos
        local node  = info.node
        local name  = node.name

        if not (kinetica.is_contraption_conductor and kinetica.is_contraption_conductor(name)) then
            local meta  = core.get_meta(pos)
            local nspin = (base_spin * info.pol >= 0) and 1 or -1

            meta:set_int("rotational_power", shared_avail_ku)
            meta:set_int("network_supply_ku", total_supply_ku)
            meta:set_int("network_used_ku", total_demand_ku)
            meta:set_int("network_overstressed", 0)
            meta:set_float("rpm", shared_rpm)
            meta:set_int("spin_dir", nspin)
            meta:set_int("lit_until", now + 2)
            meta:set_int("in_dir_x", info.in_dir.x)
            meta:set_int("in_dir_y", info.in_dir.y)
            meta:set_int("in_dir_z", info.in_dir.z)

            if kinetica.is_shaft and kinetica.is_shaft(name) then
                local sdist = math.min(kinetica.MAX_SHAFT_RUN or 32, dist_map[k] or 1)
                meta:set_int("shaft_dist", sdist)
                local canon_p2 = kinetica.get_canonical_shaft_param2(kinetica.abs_axis(node.param2))
                local target   = (nspin == 1) and "kinetica:shaft_active_cw" or "kinetica:shaft_active_ccw"
                if core.registered_nodes["kinetica:shaft_" .. tier_name .. "_" .. ((nspin == 1) and "cw" or "ccw")] then
                    target = "kinetica:shaft_" .. tier_name .. "_" .. ((nspin == 1) and "cw" or "ccw")
                end

                if name ~= target or node.param2 ~= canon_p2 then
                    core.swap_node(pos, {name = target, param2 = canon_p2})
                end

                meta:set_string("infotext", string.format("Square Tube Shaft [%d/%d]: ACTIVE (%s KU avail | %s RPM)", sdist, kinetica.MAX_SHAFT_RUN or 32, kinetica.format_int(shared_avail_ku), kinetica.format_rpm(shared_rpm)))
                if kinetica.get_glasses_info then meta:set_string("glasses_info", kinetica.get_glasses_info(pos, core.get_node(pos))) end
                core.get_node_timer(pos):start(2.0)

            elseif kinetica.is_gearbox and kinetica.is_gearbox(name) then
                local is_vert = string.find(name, "vertical") ~= nil
                local gb_base = is_vert and "kinetica:gearbox_vertical" or "kinetica:gearbox"
                local dir_tag = (nspin == 1) and "cw" or "ccw"
                local tier_cand = gb_base .. "_" .. tier_name .. "_" .. dir_tag
                local target  = core.registered_nodes[tier_cand] and tier_cand or (gb_base .. "_active_" .. dir_tag)

                if name ~= target then core.swap_node(pos, {name = target, param2 = node.param2}) end
                meta:set_string("infotext", string.format("%s: ACTIVE (%s KU avail | %s RPM)", is_vert and "Vertical Gearbox" or "Gearbox", kinetica.format_int(shared_avail_ku), kinetica.format_rpm(shared_rpm)))
                core.get_node_timer(pos):start(2.0)

            elseif kinetica.is_gearshift and kinetica.is_gearshift(name) then
                if kinetica.update_gearshift_node then kinetica.update_gearshift_node(pos) end
                core.get_node_timer(pos):start(0.5)

            elseif kinetica.is_chain_drive and kinetica.is_chain_drive(name) then
                local back = core.facedir_to_dir(node.param2) or {x = 0, y = 0, z = 1}
                local axis_sign = back.x + back.y + back.z
                local vis = (nspin * axis_sign >= 0) and 1 or -1
                local dir_tag = (vis == 1) and "cw" or "ccw"
                local tier_cand = "kinetica:chain_drive_" .. tier_name .. "_" .. dir_tag
                local target = core.registered_nodes[tier_cand] and tier_cand or ("kinetica:chain_drive_active_" .. dir_tag)

                if name ~= target then core.swap_node(pos, {name = target, param2 = node.param2}) end
                meta:set_string("infotext", string.format("Encased Chain Drive: ACTIVE (%s KU avail | %s RPM)", kinetica.format_int(shared_avail_ku), kinetica.format_rpm(shared_rpm)))
                core.get_node_timer(pos):start(2.0)

            elseif kinetica.is_water_pump and kinetica.is_water_pump(name) then
                meta:set_int("pump_demand_ku", per_pump_ku)
                local ptimer = core.get_node_timer(pos)
                if not ptimer:is_started() then ptimer:start(1.0) end

            elseif kinetica.is_mechanical_piston and kinetica.is_mechanical_piston(name) then
                meta:set_int("piston_demand_ku", per_piston_ku)
                if kinetica.wake_mechanical_piston then
                    post_actions[#post_actions + 1] = function()
                        kinetica.wake_mechanical_piston(pos, core.get_node(pos), shared_rpm, nspin, per_piston_ku, shared_avail_ku, total_supply_ku)
                    end
                else
                    local ptimer = core.get_node_timer(pos)
                    if not ptimer:is_started() then ptimer:start(0.5) end
                end

            elseif kinetica.is_source_node and kinetica.is_source_node(name, pos) then
                local my_ku = meta:get_int("source_ku")
                if kinetica.is_water_wheel and kinetica.is_water_wheel(name) then
                    meta:set_string("infotext", string.format("Big Water Wheel: ACTIVE (+%s KU | %s RPM)", kinetica.format_int(my_ku), kinetica.format_rpm(shared_rpm)))
                elseif kinetica.is_turbine and kinetica.is_turbine(name) then
                    meta:set_string("infotext", string.format("Steam Turbine: %s (+%s KU | %s RPM)", my_ku>0 and "ACTIVE" or "PASSIVE", kinetica.format_int(my_ku), kinetica.format_rpm(shared_rpm)))
                end

            elseif kinetica.is_registered_machine and kinetica.is_registered_machine(name) then
                local mdef = kinetica.get_machine_def(name)
                local m_ku = info.machine_demand_ku or 16
                meta:set_int("machine_demand_ku", m_ku)
                if mdef and mdef.wake then
                    post_actions[#post_actions + 1] = function()
                        mdef.wake(pos, core.get_node(pos), shared_rpm, nspin, m_ku, shared_avail_ku, total_supply_ku)
                    end
                else
                    local mtimer = core.get_node_timer(pos)
                    if not mtimer:is_started() then mtimer:start(0.5) end
                end

            elseif core.get_item_group(name, "kinetic_receiver") > 0 then
                local rtimer = core.get_node_timer(pos)
                if not rtimer:is_started() then rtimer:start(1.0) end
            end
        end
    end

    kinetica.api.network.solver_depth = kinetica.api.network.solver_depth - 1
    run_post_solve_actions(post_actions)
end

function kinetica.api.network.schedule_update(pos)
    local p = vector.new(pos.x, pos.y, pos.z)
    core.after(0.05, function()
        if kinetica.is_kinetic_node and kinetica.is_kinetic_node(core.get_node(p).name) then
            kinetica.api.network.update(p)
        end
        for _, d in ipairs(ALL_DIRS) do
            local np = vector.new(p.x + d.x, p.y + d.y, p.z + d.z)
            if kinetica.is_kinetic_node and kinetica.is_kinetic_node(core.get_node(np).name) then
                kinetica.api.network.update(np)
            end
        end
    end)
end

-- Link Legacy names to API
kinetica.update_network          = kinetica.api.network.update
kinetica.schedule_network_update = kinetica.api.network.schedule_update
kinetica.break_conflicting_shaft = kinetica.api.network.break_conflicting_shaft
kinetica.are_nodes_coupled       = kinetica.api.network.are_coupled


-- ============================================================================
-- 3. MACHINE REGISTRATION API
-- Automates the registration of idle, active, and speed-tiered kinetic nodes.
-- ============================================================================
kinetica.api.registration = {}

-- Standard speed tiers used across Kinetica (includes both length and length_mult)
kinetica.api.registration.ANIM_TIERS = {
    { name = "crawl",  max_rpm = 5,    length = 0.85, length_mult = 3.5 },
    { name = "slow",   max_rpm = 15,   length = 0.48, length_mult = 2.0 },
    { name = "medium", max_rpm = 63,   length = 0.24, length_mult = 1.0 },
    { name = "fast",   max_rpm = 255,  length = 0.11, length_mult = 0.45 },
    { name = "hyper",  max_rpm = 1024, length = 0.05, length_mult = 0.20 },
    { name = "ultra",  max_rpm = 3072, length = 0.03, length_mult = 0.12 },
}

function kinetica.register_kinetic_machine(base_name, mdef)
    kinetica.registered_machines = kinetica.registered_machines or {}
    kinetica.registered_machines[base_name] = mdef
end

-- The master factory function
function kinetica.api.registration.register_rotary_machine(base_name, def)
    kinetica.registered_machines = kinetica.registered_machines or {}

    local base_groups = def.groups_idle or {handy = 1, pickaxey = 1, kinetic_receiver = 1}
    local act_groups  = table.copy(base_groups)
    act_groups.not_in_creative_inventory = 1

    -- 1. Register the Base IDLE Node
    core.register_node(base_name, {
        description           = def.description,
        drawtype              = def.drawtype or "nodebox",
        node_box              = def.node_box,
        selection_box         = def.selection_box or def.node_box,
        collision_box         = def.collision_box or def.node_box,
        paramtype             = "light",
        paramtype2            = def.paramtype2 or "facedir",
        sunlight_propagates   = true,
        is_ground_content     = false,
        tiles                 = def.tiles_idle,
        groups                = base_groups,
        _mcl_hardness         = def.hardness or 2.5,
        _mcl_blast_resistance = def.blast_resistance or 3.5,
        sounds                = def.sounds,
        on_place              = def.on_place,
        on_rightclick         = def.on_rightclick,
        
        on_construct = function(pos)
            if def.on_construct then def.on_construct(pos) end
            if kinetica.api.network.update then
                core.after(0.05, function() kinetica.api.network.update(pos) end)
            end
        end,
        
        after_dig_node = function(pos, oldnode, oldmeta, digger)
            if def.after_dig_node then def.after_dig_node(pos, oldnode, oldmeta, digger) end
            if kinetica.api.network.update then
                core.after(0.05, function() kinetica.api.network.update(pos) end)
            end
        end,
        
        on_timer = def.on_timer,
    })

    -- 2. If it has animations, automatically generate the CW/CCW active tiers
    if def.tiles_active_cw and def.tiles_active_ccw then
        local function register_tier(suffix, tiles)
            core.register_node(base_name .. suffix, {
                description           = def.description_active or def.description,
                drawtype              = def.drawtype or "nodebox",
                node_box              = def.node_box_active or def.node_box,
                selection_box         = def.selection_box or def.node_box,
                collision_box         = def.collision_box or def.node_box,
                paramtype             = "light",
                paramtype2            = def.paramtype2 or "facedir",
                sunlight_propagates   = true,
                is_ground_content     = false,
                drop                  = base_name,
                tiles                 = tiles,
                groups                = act_groups,
                _mcl_hardness         = def.hardness or 2.5,
                _mcl_blast_resistance = def.blast_resistance or 3.5,
                sounds                = def.sounds,
                on_rightclick         = def.on_rightclick,
                after_dig_node        = function(pos, oldnode, oldmeta, digger)
                    if def.after_dig_node then def.after_dig_node(pos, oldnode, oldmeta, digger) end
                    if kinetica.api.network.update then
                        core.after(0.05, function() kinetica.api.network.update(pos) end)
                    end
                end,
                on_timer              = def.on_timer,
            })
        end

        -- Generate standard Active CW and CCW
        register_tier("_active_cw", def.tiles_active_cw)
        register_tier("_active_ccw", def.tiles_active_ccw)

        -- Automatically alias `<base_name>_active` so blocks like Mechanical Press never crash on swap_node
        if not core.registered_nodes[base_name .. "_active"] then
            core.register_alias(base_name .. "_active", base_name .. "_active_cw")
        end

        -- Generate the speed tiers
        if type(def.build_tier_tiles) == "function" then
            for _, tier in ipairs(kinetica.api.registration.ANIM_TIERS) do
                register_tier("_" .. tier.name .. "_cw", def.build_tier_tiles(tier, false))
                register_tier("_" .. tier.name .. "_ccw", def.build_tier_tiles(tier, true))
            end
        end
    end

    -- 3. Hook into the network solver
    kinetica.registered_machines[base_name] = {
        get_demand_ku   = def.get_demand_ku,
        has_axle_port   = def.has_axle_port,
        set_idle        = def.set_idle,
        wake            = def.wake,
        on_overstress   = def.on_overstress,
        can_ride_piston = def.can_ride_piston,
    }
end

-- ============================================================================
-- 4. RECIPES API
-- Centralized registry for all processing machine outputs.
-- ============================================================================
kinetica.api.recipes = {
    crushing = {},
    pressing = {},
    washing = {},
    haunting = {},
    smoking = {},
    freezing = {}
}

function kinetica.api.recipes.register_crushing(input_item, def)
    if not input_item or not def.output then return false end
    kinetica.api.recipes.crushing[input_item] = {
        output = def.output,
        time   = def.time or 1.0,
        extra  = def.extra or {}, 
        xp     = def.xp or 0,
    }
    return true
end

function kinetica.api.recipes.register_pressing(input_item, def)
    if not input_item or not def.output then return false end
    kinetica.api.recipes.pressing[input_item] = {
        output      = def.output,
        input_count = math.max(1, def.input_count or 1),
        time        = def.time or 1.0,
    }
    return true
end

function kinetica.api.recipes.register_fan_processing(catalyst, input_item, def)
    if not kinetica.api.recipes[catalyst] then return false end
    kinetica.api.recipes[catalyst][input_item] = def
    return true
end

-- ============================================================================
-- 5. TELEMETRY API
-- Shared UI elements for the Engineer's Glasses.
-- ============================================================================
kinetica.api.telemetry = {
    formatters = {}
}

function kinetica.api.telemetry.register_formatter(node_name, func)
    kinetica.api.telemetry.formatters[node_name] = func
end

function kinetica.api.telemetry.draw_progress_bar(used, total, slots)
    slots = slots or 10
    if not total or total <= 0 then
        return "[" .. string.rep("░", slots) .. "] 0%"
    end
    local ratio = math.min(1.0, math.max(0.0, (used or 0) / total))
    local filled = math.floor(ratio * slots + 0.5)
    local pct = math.min(100, math.floor(ratio * 100 + 0.5))
    return string.format("[%s%s] %d%%", string.rep("█", filled), string.rep("░", slots - filled), pct)
end

function kinetica.api.telemetry.kv_row(label, value)
    return string.format("│  %-11s: %s", label, tostring(value))
end

-- Replaces the manual lookups in your individual files
function kinetica.get_glasses_info(pos, node)
    node = node or core.get_node(pos)
    local best_fn = nil
    local best_len = -1
    for prefix, fn in pairs(kinetica.api.telemetry.formatters) do
        if node.name == prefix or string.sub(node.name or "", 1, #prefix + 1) == (prefix .. "_") then
            if #prefix > best_len then
                best_len = #prefix
                best_fn = fn
            end
        end
    end
    if best_fn then return best_fn(pos, node) end
    return core.get_meta(pos):get_string("glasses_info")
end

-- ============================================================================
-- 6. CONTRAPTIONS API
-- Handles super glue clustering and routing items to moving/glued chests.
-- ============================================================================
kinetica.api.contraptions = {
    active_glue_boxes = {}
}

function kinetica.api.contraptions.is_pos_inside_bounds(pos, minp, maxp)
    return pos.x >= minp.x and pos.x <= maxp.x and
           pos.y >= minp.y and pos.y <= maxp.y and
           pos.z >= minp.z and pos.z <= maxp.z
end

function kinetica.api.contraptions.get_glue_boxes_at(pos)
    local p = vector.round(pos)
    local list = {}
    for self, _ in pairs(kinetica.api.contraptions.active_glue_boxes) do
        if self.object and self.object:get_luaentity() and self.minp and self.maxp then
            if kinetica.api.contraptions.is_pos_inside_bounds(p, self.minp, self.maxp) then
                list[#list + 1] = self
            end
        else
            kinetica.api.contraptions.active_glue_boxes[self] = nil
        end
    end
    return list
end

function kinetica.api.contraptions.get_glued_cluster_positions(start_pos)
    local p0          = vector.round(start_pos)
    local results     = {}
    local visited_pos = {}
    local visited_box = {}
    local pos_queue   = {}

    local initial_boxes = kinetica.api.contraptions.get_glue_boxes_at(p0)
    if #initial_boxes == 0 then return results end

    local p0_hash = core.hash_node_position(p0)
    visited_pos[p0_hash] = true
    pos_queue[1] = p0

    local n0 = core.get_node(p0).name
    if n0 ~= "air" and n0 ~= "ignore" then
        results[#results + 1] = p0
    end

    local head = 1
    while head <= #pos_queue and #results < 2048 do
        local cur = pos_queue[head]
        head = head + 1

        for self, _ in pairs(kinetica.api.contraptions.active_glue_boxes) do
            if not visited_box[self] and self.object and self.object:get_luaentity() and self.minp and self.maxp then
                if kinetica.api.contraptions.is_pos_inside_bounds(cur, self.minp, self.maxp) then
                    visited_box[self] = true
                    for x = self.minp.x, self.maxp.x do
                        for y = self.minp.y, self.maxp.y do
                            for z = self.minp.z, self.maxp.z do
                                local bp = {x = x, y = y, z = z}
                                local hk = core.hash_node_position(bp)
                                if not visited_pos[hk] then
                                    visited_pos[hk] = true
                                    local nn = core.get_node(bp).name
                                    if nn ~= "air" and nn ~= "ignore" then
                                        results[#results + 1]   = bp
                                        pos_queue[#pos_queue+1] = bp
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return results
end

function kinetica.api.contraptions.are_positions_glued(pos1, pos2)
    local p1 = vector.round(pos1)
    local p2 = vector.round(pos2)
    for self, _ in pairs(kinetica.api.contraptions.active_glue_boxes) do
        if self.object and self.object:get_luaentity() and self.minp and self.maxp then
            if kinetica.api.contraptions.is_pos_inside_bounds(p1, self.minp, self.maxp) and
               kinetica.api.contraptions.is_pos_inside_bounds(p2, self.minp, self.maxp) then
                return true
            end
        else
            kinetica.api.contraptions.active_glue_boxes[self] = nil
        end
    end

    local cluster = kinetica.api.contraptions.get_glued_cluster_positions(p1)
    local p2_hash = core.hash_node_position(p2)
    for _, cp in ipairs(cluster) do
        if core.hash_node_position(cp) == p2_hash then
            return true
        end
    end
    return false
end

-- Routes mined items from glued Drills/Saws directly into any Chest, Barrel, Hopper, or Vault in the glue cluster
function kinetica.api.contraptions.try_store_in_glued_contraption(source_pos, stack)
    local st = ItemStack(stack)
    if st:is_empty() then return st end

    local cluster = kinetica.api.contraptions.get_glued_cluster_positions(source_pos)
    if #cluster == 0 then return st end

    local STORAGE_LISTS = {"main", "vault", "items", "storage", "chest", "input", "src"}

    for _, cpos in ipairs(cluster) do
        local cnode = core.get_node(cpos)
        local cname = cnode.name

        local is_storage = (core.get_item_group(cname, "container") > 0) or
                           (core.get_item_group(cname, "chest") > 0) or
                           (kinetica.is_item_vault and kinetica.is_item_vault(cname)) or
                           string.find(cname, "vault") ~= nil or
                           string.find(cname, "chest") ~= nil or
                           string.find(cname, "barrel") ~= nil or
                           string.find(cname, "hopper") ~= nil or
                           string.find(cname, "shulker") ~= nil

        if is_storage and not (kinetica.is_deployer and kinetica.is_deployer(cname)) then
            local cmeta = core.get_meta(cpos)
            local cinv  = cmeta and cmeta:get_inventory()
            if cinv then
                for _, listname in ipairs(STORAGE_LISTS) do
                    if cinv:get_size(listname) > 0 and cinv:room_for_item(listname, st) then
                        st = cinv:add_item(listname, st)
                        if st:is_empty() then
                            return st
                        end
                    end
                end
            end
        end
    end

    return st
end

-- Legacy mappings for glue.lua, mechanical_drill.lua, and mechanical_saw.lua compatibility
kinetica.get_glued_cluster_positions      = kinetica.api.contraptions.get_glued_cluster_positions
kinetica.are_positions_glued              = kinetica.api.contraptions.are_positions_glued
kinetica.is_glued_together                = kinetica.api.contraptions.are_positions_glued
kinetica.get_glue_boxes_at                = kinetica.api.contraptions.get_glue_boxes_at
kinetica.try_store_in_glued_contraption   = kinetica.api.contraptions.try_store_in_glued_contraption


-- ============================================================================
-- 7. UNIVERSAL POWER & GLUE PARENT API
-- ============================================================================
kinetica.glue_parent_prefixes = {
    "kinetica:mechanical_piston",
    "kinetica:sticky_mechanical_piston",
    "kinetica:piston_head",
    "kinetica:piston_head_sticky",
    "kinetica:piston_pole",
    "kinetica:piston_extension_pole",
}

function kinetica.register_glue_parent_source(node_prefix)
    if not node_prefix or node_prefix == "" then return end
    for _, p in ipairs(kinetica.glue_parent_prefixes) do
        if p == node_prefix then return end
    end
    table.insert(kinetica.glue_parent_prefixes, node_prefix)
end

function kinetica.get_machine_def(node_name)
    if not node_name or type(kinetica.registered_machines) ~= "table" then return nil end
    if kinetica.registered_machines[node_name] then
        return kinetica.registered_machines[node_name]
    end
    for prefix, mdef in pairs(kinetica.registered_machines) do
        if node_name == prefix or string.sub(node_name, 1, #prefix + 1) == (prefix .. "_") then
            if #prefix > 0 then return mdef end
        end
    end
    return nil
end

function kinetica.is_registered_machine(node_name)
    return kinetica.get_machine_def(node_name) ~= nil
end

function kinetica.get_node_power(pos, meta)
    meta = meta or core.get_meta(pos)
    local now = math.floor(core.get_gametime())

    if meta:get_int("lit_until") > now or meta:get_int("contraption_powered_until") > now then
        local rpm = meta:get_float("rpm")
        local sup = meta:get_int("network_supply_ku")
        local ava = meta:get_int("rotational_power")
        local spn = meta:get_int("spin_dir")
        if rpm >= 1 and sup > 0 and meta:get_int("network_overstressed") == 0 then
            return true, rpm, sup, ava, spn == 0 and 1 or spn
        end
    end
    return false, 0, 0, 0, 1
end