-- kinetica/windmill_bearing.lua
kinetica = kinetica or {}

-- ============================================================================
-- TOP CONFIGURATION SECTION
-- ============================================================================
local CONFIG = {
    MIN_SAILS                     = 8,
    SAILS_PER_RPM_STEP            = 8,
    BASE_RPM_PER_STEP             = 2,
    MAX_RPM                       = 16,
    KU_PER_SAIL                   = 64,
    MAX_KU_CAP                    = 8192,
    MAX_BLOCKS_PER_MILL           = 2048,
    VISUAL_SPEED_MULT             = 0.1,
    ACCEL_RATE                    = 2.8,   -- Smooth inertia ramp when starting/stopping/reversing
    DTIME_SMOOTHING               = 0.82,  -- Filters out server step jitter
    INVERT_VISUAL_SPIN            = false, -- Flip true if 3D sails spin opposite to CW/CCW label
    INVERT_BACK_OVERLAY           = true, -- Flip true if the bearing's back overlay spins opposite to sails
    INVERT_OUTPUT_SPIN            = false, -- Flip true if attached shafts/chain drives spin opposite to sails
    ALLOW_VERTICAL_PLACEMENT      = true,
    HIDE_INFOTEXT_WITHOUT_GLASSES = false,

    TEX_FRONT                     = "create_windmill_bearing_top.png",
    TEX_CASING                    = "create_windmill_bearing_side.png",
    TEX_SHAFT_OVERLAY             = "kinetica_shaft_connecting_overlay.png",
}

local IDLE_NAME       = "kinetica:windmill_bearing"
local ACTIVE_CW_NAME  = "kinetica:windmill_bearing_active_cw"
local ACTIVE_CCW_NAME = "kinetica:windmill_bearing_active_ccw"
local ACTIVE_LEGACY   = "kinetica:windmill_bearing_active"

kinetica.WINDMILL_MAX_KU = CONFIG.MAX_KU_CAP

-- ============================================================================
-- KINETICA API & SOLVER HOOKS
-- ============================================================================
local function is_windmill_bearing(name)
    return name == IDLE_NAME
        or name == ACTIVE_CW_NAME
        or name == ACTIVE_CCW_NAME
        or name == ACTIVE_LEGACY
end
kinetica.is_windmill_bearing = is_windmill_bearing

local orig_is_source_node = kinetica.is_source_node
function kinetica.is_source_node(name, pos)
    if is_windmill_bearing(name) then return true end
    if orig_is_source_node then return orig_is_source_node(name, pos) end
    return false
end

local orig_is_kinetic_node = kinetica.is_kinetic_node
function kinetica.is_kinetic_node(name)
    if is_windmill_bearing(name) then return true end
    if orig_is_kinetic_node then return orig_is_kinetic_node(name) end
    return false
end

local function get_back_dir(param2)
    local d = core.facedir_to_dir(param2 or 0) or {x = 0, y = 0, z = 1}
    return {x = d.x, y = d.y, z = d.z}
end

local function get_front_dir(param2)
    local b = get_back_dir(param2)
    return {x = -b.x, y = -b.y, z = -b.z}
end

-- Synchronizes 3D sail spin, back port overlay, and rear shaft network spin independently
local function get_effective_spins(param2, preferred_spin)
    local pref = (preferred_spin == -1) and -1 or 1
    local front = get_front_dir(param2)
    local axis_sign = front.x + front.y + front.z
    if axis_sign == 0 then axis_sign = 1 end

    -- 1. Visual 3D sail spin
    local vis_spin = (-pref) * (CONFIG.INVERT_VISUAL_SPIN and -1 or 1)

    -- 2. Rear shaft network spin (aligned with canonical +X, +Y, +Z shaft orientation)
    local net_spin = (-pref * axis_sign) * (CONFIG.INVERT_OUTPUT_SPIN and -1 or 1)
    if net_spin >= 0 then net_spin = 1 else net_spin = -1 end

    return vis_spin, net_spin
end

-- Single, clean function that selects CW or CCW back-overlay animation from preferred_spin
local function get_active_node_name_for_spin(param2, preferred_spin)
    local pref = (preferred_spin == -1) and -1 or 1
    local ov_spin = pref * (CONFIG.INVERT_BACK_OVERLAY and -1 or 1)
    return (ov_spin < 0) and ACTIVE_CCW_NAME or ACTIVE_CW_NAME
end

local orig_has_axle_port = kinetica.has_axle_port
function kinetica.has_axle_port(node, dir, pos)
    if node and is_windmill_bearing(node.name) then
        local back = get_back_dir(node.param2)
        return (dir.x == back.x and dir.y == back.y and dir.z == back.z)
    end
    if orig_has_axle_port then return orig_has_axle_port(node, dir, pos) end
    return false
end

if kinetica.register_glue_parent_source then
    kinetica.register_glue_parent_source(IDLE_NAME)
    kinetica.register_glue_parent_source(ACTIVE_CW_NAME)
    kinetica.register_glue_parent_source(ACTIVE_CCW_NAME)
    kinetica.register_glue_parent_source(ACTIVE_LEGACY)
end

-- ============================================================================
-- 3D ROTATION MATH & CREATE-STYLE SCALING
-- ============================================================================
local function is_sail_node(name)
    if not name or name == "air" or name == "ignore" then return false end
    return core.get_item_group(name, "wool") > 0
        or core.get_item_group(name, "windmill_sail") > 0
        or string.find(name, "wool") ~= nil
end

local function get_windmill_stats(sail_count)
    if sail_count < CONFIG.MIN_SAILS then
        return 0, 0
    end
    local tier = math.floor(sail_count / CONFIG.SAILS_PER_RPM_STEP)
    if tier < 1 then tier = 1 end
    local rpm = math.min(CONFIG.MAX_RPM, tier * CONFIG.BASE_RPM_PER_STEP)
    local ku  = math.min(CONFIG.MAX_KU_CAP, sail_count * CONFIG.KU_PER_SAIL)
    return rpm, ku
end

local function rotate_rel_pos_steps(rel, axis, steps)
    steps = (steps % 4 + 4) % 4
    local x, y, z = rel.x, rel.y, rel.z
    for _ = 1, steps do
        if axis.z > 0 then x, y = -y, x
        elseif axis.z < 0 then x, y = y, -x
        elseif axis.x > 0 then y, z = -z, y
        elseif axis.x < 0 then y, z = z, -y
        elseif axis.y > 0 then x, z = z, -x
        elseif axis.y < 0 then x, z = -z, x end
    end
    return {x = x, y = y, z = z}
end

local function get_axis_euler_rotation(axis, angle)
    if axis.x ~= 0 then
        return {x = angle * axis.x, y = 0, z = 0}
    elseif axis.y ~= 0 then
        return {x = 0, y = -angle * axis.y, z = 0}
    else
        return {x = 0, y = 0, z = angle * axis.z}
    end
end

-- ============================================================================
-- STRICT SUPER GLUE CONTRAPTION TRACER & GLUE BOX SNAPSHOTTER
-- ============================================================================
local function collect_windmill_contraption(bearing_pos, bearing_node)
    local front_dir   = get_front_dir(bearing_node.param2)
    local anchor_pos  = vector.add(bearing_pos, front_dir)
    local anchor_node = core.get_node(anchor_pos)

    if anchor_node.name == "air" or anchor_node.name == "ignore" then
        return {}, 0, {}, "Place a block on the front face of the Windmill Bearing first!"
    end
    if is_windmill_bearing(anchor_node.name) then
        return {}, 0, {}, "Cannot attach another Windmill Bearing to the front face!"
    end

    local raw_positions = {}
    local seen_hashes   = { [core.hash_node_position(bearing_pos)] = true }

    if kinetica.api and kinetica.api.contraptions and kinetica.api.contraptions.get_glued_cluster_positions then
        local cluster_a = kinetica.api.contraptions.get_glued_cluster_positions(anchor_pos)
        local cluster_b = kinetica.api.contraptions.get_glued_cluster_positions(bearing_pos)
        for _, p in ipairs(cluster_a) do
            local h = core.hash_node_position(p)
            if not seen_hashes[h] then
                seen_hashes[h] = true
                raw_positions[#raw_positions + 1] = p
            end
        end
        for _, p in ipairs(cluster_b) do
            local h = core.hash_node_position(p)
            if not seen_hashes[h] then
                seen_hashes[h] = true
                raw_positions[#raw_positions + 1] = p
            end
        end
    end

    local anchor_hash = core.hash_node_position(anchor_pos)
    if not seen_hashes[anchor_hash] then
        seen_hashes[anchor_hash] = true
        raw_positions[#raw_positions + 1] = anchor_pos
    end

    local blocks      = {}
    local sail_count  = 0
    local glue_boxes  = {}
    local seen_gboxes = {}

    for _, wp in ipairs(raw_positions) do
        if #blocks >= CONFIG.MAX_BLOCKS_PER_MILL then break end
        local n = core.get_node(wp)
        if n.name ~= "air" and n.name ~= "ignore" and not is_windmill_bearing(n.name) then
            local def = core.registered_nodes[n.name]
            if not def or not def.liquidtype or def.liquidtype == "none" then
                if is_sail_node(n.name) then
                    sail_count = sail_count + 1
                end
                blocks[#blocks + 1] = {
                    name   = n.name,
                    param2 = n.param2,
                    rel    = vector.subtract(wp, bearing_pos),
                    pos    = wp,
                    meta   = core.get_meta(wp):to_table(),
                }
                if kinetica.api and kinetica.api.contraptions and kinetica.api.contraptions.get_glue_boxes_at then
                    for _, gbox in ipairs(kinetica.api.contraptions.get_glue_boxes_at(wp)) do
                        if not seen_gboxes[gbox] and gbox.minp and gbox.maxp then
                            seen_gboxes[gbox] = true
                            glue_boxes[#glue_boxes + 1] = {
                                entity   = gbox,
                                rel_minp = vector.subtract(gbox.minp, bearing_pos),
                                rel_maxp = vector.subtract(gbox.maxp, bearing_pos),
                            }
                        end
                    end
                end
            end
        end
    end

    if kinetica.api and kinetica.api.contraptions and kinetica.api.contraptions.get_glue_boxes_at then
        for _, gbox in ipairs(kinetica.api.contraptions.get_glue_boxes_at(bearing_pos)) do
            if not seen_gboxes[gbox] and gbox.minp and gbox.maxp then
                seen_gboxes[gbox] = true
                glue_boxes[#glue_boxes + 1] = {
                    entity   = gbox,
                    rel_minp = vector.subtract(gbox.minp, bearing_pos),
                    rel_maxp = vector.subtract(gbox.maxp, bearing_pos),
                }
            end
        end
    end

    if sail_count < CONFIG.MIN_SAILS then
        return {}, sail_count, {}, string.format(
            "Assembly Failed: Glue at least %d Wool/Sail blocks to the front block (Found %d)!",
            CONFIG.MIN_SAILS, sail_count
        )
    end

    return blocks, sail_count, glue_boxes, nil
end

-- ============================================================================
-- ENTITIES: RIGID PARENT-CHILD ATTACHMENT CONTROLLER & SMOOTH INTERPOLATION
-- ============================================================================
local active_pivots_by_hash = {}

local function clear_windmill_entities(pos)
    local h = core.hash_node_position(pos)
    local tracked = active_pivots_by_hash[h]
    if tracked and tracked:get_luaentity() then
        local ple = tracked:get_luaentity()
        if ple and ple.child_entries then
            for _, ce in ipairs(ple.child_entries) do
                if ce.obj and ce.obj:get_luaentity() then
                    ce.obj:set_detach()
                    ce.obj:remove()
                end
            end
        end
        tracked:remove()
    end
    active_pivots_by_hash[h] = nil

    local objs = core.get_objects_inside_radius(pos, CONFIG.MAX_BLOCKS_PER_MILL > 32 and 24 or 16)
    for _, obj in ipairs(objs) do
        local le = obj:get_luaentity()
        if le and (le.name == "kinetica:windmill_pivot" or le.name == "kinetica:windmill_block_visual") then
            if le.bearing_pos and vector.equals(le.bearing_pos, pos) then
                if le.child_entries then
                    for _, ce in ipairs(le.child_entries) do
                        if ce.obj and ce.obj:get_luaentity() then
                            ce.obj:set_detach()
                            ce.obj:remove()
                        end
                    end
                end
                obj:set_detach()
                obj:remove()
            end
        end
    end
end

local function spawn_windmill_entities(pos, axis, target_speed_rad, blocks, initial_angle)
    clear_windmill_entities(pos)

    local pivot = core.add_entity(pos, "kinetica:windmill_pivot")
    if not pivot then return nil end

    local ple = pivot:get_luaentity()
    local angle = initial_angle or 0
    local rot_euler = get_axis_euler_rotation(axis, angle)
    local child_entries = {}

    for _, b in ipairs(blocks or {}) do
        local child = core.add_entity(pos, "kinetica:windmill_block_visual", b.name)
        if child then
            local cle = child:get_luaentity()
            if cle then
                cle.bearing_pos = vector.new(pos.x, pos.y, pos.z)
                cle.parent_obj  = pivot
                cle.item_name   = b.name
            end
            child:set_properties({wield_item = b.name, textures = {b.name}})
            local child_euler = kinetica.api.math.facedir_to_euler(b.param2)
            child:set_attach(
                pivot,
                "",
                {x = b.rel.x * 10, y = b.rel.y * 10, z = b.rel.z * 10},
                child_euler
            )
            child_entries[#child_entries + 1] = {
                obj  = child,
                rel  = {x = b.rel.x, y = b.rel.y, z = b.rel.z},
                name = b.name,
            }
        end
    end

    pivot:set_rotation(rot_euler)

    if ple then
        ple.bearing_pos   = vector.new(pos.x, pos.y, pos.z)
        ple.axis          = axis
        ple.target_speed  = target_speed_rad or 0
        ple.cur_speed     = 0
        ple.angle         = angle
        ple.child_entries = child_entries
    end

    active_pivots_by_hash[core.hash_node_position(pos)] = pivot
    return pivot
end

core.register_entity("kinetica:windmill_block_visual", {
    initial_properties = {
        physical             = false,
        collide_with_objects = false,
        pointable            = false,
        visual               = "wielditem",
        visual_size          = {x = 0.667, y = 0.667, z = 0.667},
        wield_item           = "mcl_core:wood",
        static_save          = false,
    },
    on_activate = function(self, staticdata)
        self.object:set_armor_groups({immortal = 1})
        self._watchdog = 0
        if staticdata and staticdata ~= "" then
            self.item_name = staticdata
            self.object:set_properties({wield_item = staticdata, textures = {staticdata}})
        end
    end,
    on_step = function(self, dtime)
        self._watchdog = (self._watchdog or 0) + dtime
        if self._watchdog >= 0.5 then
            self._watchdog = 0
            if not self.parent_obj or not self.parent_obj:get_luaentity() then
                self.object:set_detach()
                self.object:remove()
            end
        end
    end,
})

core.register_entity("kinetica:windmill_pivot", {
    initial_properties = {
        physical             = false,
        collide_with_objects = false,
        pointable            = false,
        visual               = "cube",
        textures             = {"blank.png", "blank.png", "blank.png", "blank.png", "blank.png", "blank.png"},
        use_texture_alpha    = true,
        visual_size          = {x = 1, y = 1, z = 1},
        is_visible           = true,
        static_save          = false,
    },
    on_activate = function(self)
        self.object:set_armor_groups({immortal = 1})
        self.angle         = self.angle or 0
        self.cur_speed     = self.cur_speed or 0
        self.target_speed  = self.target_speed or 0
        self.axis          = self.axis or {x = 0, y = 0, z = 1}
        self.child_entries = self.child_entries or {}
        self._check_acc    = 0
        self._smooth_dt    = 0.05
    end,
    on_step = function(self, dtime)
        local bpos = self.bearing_pos or vector.round(self.object:get_pos() or {x = 0, y = 0, z = 0})
        self._check_acc = (self._check_acc or 0) + dtime
        if self._check_acc >= 0.5 then
            self._check_acc = 0
            local bnode = core.get_node(bpos)
            if not is_windmill_bearing(bnode.name) or core.get_meta(bpos):get_int("windmill_assembled") ~= 1 then
                if self.child_entries then
                    for _, ce in ipairs(self.child_entries) do
                        if ce.obj and ce.obj:get_luaentity() then
                            ce.obj:set_detach()
                            ce.obj:remove()
                        end
                    end
                end
                active_pivots_by_hash[core.hash_node_position(bpos)] = nil
                self.object:remove()
                return
            end
        end

        local clamped_dt = math.min(0.15, math.max(0.005, dtime))
        local alpha = CONFIG.DTIME_SMOOTHING or 0.82
        self._smooth_dt = (self._smooth_dt or clamped_dt) * alpha + clamped_dt * (1.0 - alpha)
        local dt = self._smooth_dt

        local target = self.target_speed or 0
        local cur    = self.cur_speed or 0
        if math.abs(target - cur) > 1e-4 then
            local max_delta = (CONFIG.ACCEL_RATE or 2.8) * dt
            if cur < target then
                cur = math.min(target, cur + max_delta)
            else
                cur = math.max(target, cur - max_delta)
            end
            self.cur_speed = cur
        else
            self.cur_speed = target
            cur = target
        end

        if math.abs(cur) > 1e-4 then
            self.angle = (self.angle or 0) + (cur * dt)
            if self.angle > math.pi * 2 then self.angle = self.angle - (math.pi * 2) end
            if self.angle < -math.pi * 2 then self.angle = self.angle + (math.pi * 2) end

            local axis = self.axis or {x = 0, y = 0, z = 1}
            self.object:set_rotation(get_axis_euler_rotation(axis, self.angle))
        end
    end,
})

-- ============================================================================
-- ENGINEER'S GLASSES & INFOTEXT TELEMETRY
-- ============================================================================
local function format_windmill_glasses_info(pos, node)
    local meta         = core.get_meta(pos)
    local is_assembled = (meta:get_int("windmill_assembled") == 1)
    local sail_count   = meta:get_int("sail_count")
    local block_count  = meta:get_int("block_count")
    local source_ku    = meta:get_int("source_ku")
    local source_rpm   = meta:get_float("source_rpm")
    local overstressed = (meta:get_int("network_overstressed") == 1)
    local net_used     = meta:get_int("network_used_ku")
    local net_supply   = meta:get_int("network_supply_ku")
    local pref_spin    = meta:get_int("preferred_spin")
    if pref_spin == 0 then pref_spin = 1 end

    local state_str = "DISASSEMBLED (IDLE)"
    if overstressed then
        state_str = "OVERSTRESSED (STALLED)"
    elseif is_assembled then
        state_str = "ROTATING (GENERATING POWER)"
    end

    local T = kinetica.api and kinetica.api.telemetry or nil
    if not T then return "" end

    return table.concat({
        "┌─ ENGINEER'S GLASSES ──────────────",
        "│  Machine: Windmill Bearing",
        "│  ● STATE: " .. state_str,
        "├─ WINDMILL GENERATOR ──────────────",
        T.kv_row("Output Speed", string.format("%.0f RPM (%s)", is_assembled and source_rpm or 0, pref_spin == 1 and "CW" or "CCW")),
        T.kv_row("Power Output", string.format("+%d / %d KU Max", is_assembled and source_ku or 0, CONFIG.MAX_KU_CAP)),
        T.kv_row("Wool Sails",   string.format("%d Connected (Min %d)", sail_count, CONFIG.MIN_SAILS)),
        T.kv_row("Total Blocks", string.format("%d / %d Blocks", block_count, CONFIG.MAX_BLOCKS_PER_MILL)),
        T.kv_row("Grid Load",    T.draw_progress_bar(net_used, math.max(source_ku, net_supply), 10)),
        "│  Tip: Sneak + Right-Click to Reverse",
        "└───────────────────────────────────",
    }, "\n")
end

if kinetica.api and kinetica.api.telemetry then
    kinetica.api.telemetry.register_formatter(IDLE_NAME,       format_windmill_glasses_info)
    kinetica.api.telemetry.register_formatter(ACTIVE_CW_NAME,  format_windmill_glasses_info)
    kinetica.api.telemetry.register_formatter(ACTIVE_CCW_NAME, format_windmill_glasses_info)
end

local function update_windmill_infotext(pos, node)
    node = node or core.get_node(pos)
    local meta         = core.get_meta(pos)
    local is_assembled = (meta:get_int("windmill_assembled") == 1)
    local sail_count   = meta:get_int("sail_count")
    local block_count  = meta:get_int("block_count")
    local source_ku    = meta:get_int("source_ku")
    local source_rpm   = meta:get_float("source_rpm")
    local overstressed = (meta:get_int("network_overstressed") == 1)
    local pref_spin    = meta:get_int("preferred_spin")
    if pref_spin == 0 then pref_spin = 1 end
    local dir_label    = (pref_spin == 1) and "CW" or "CCW"

    if not CONFIG.HIDE_INFOTEXT_WITHOUT_GLASSES then
        if overstressed then
            meta:set_string("infotext", string.format(
                "Windmill Bearing: OVERSTRESSED! (+%d KU @ %.0f RPM %s | %d Sails)",
                source_ku, source_rpm, dir_label, sail_count
            ))
        elseif is_assembled then
            local cap_note = (sail_count * CONFIG.KU_PER_SAIL >= CONFIG.MAX_KU_CAP) and " [MAX CAP]" or ""
            meta:set_string("infotext", string.format(
                "Windmill Bearing: ACTIVE (+%d KU%s @ %.0f RPM %s | %d Sails | R-Click: Stop | Sneak+R-Click: Reverse)",
                source_ku, cap_note, source_rpm, dir_label, sail_count
            ))
        else
            meta:set_string("infotext", string.format(
                "Windmill Bearing: Idle [%s] (Glue %d+ Wool Sails to Front & R-Click | Sneak+R-Click: Reverse)",
                dir_label, CONFIG.MIN_SAILS
            ))
        end
    end
    meta:set_string("glasses_info", format_windmill_glasses_info(pos, node))
end

-- ============================================================================
-- ASSEMBLE, DISASSEMBLE & LIVE DIRECTION TOGGLE
-- ============================================================================
local function get_active_pivot_at(pos)
    local h = core.hash_node_position(pos)
    local tracked = active_pivots_by_hash[h]
    if tracked and tracked:get_luaentity() then
        return tracked, tracked:get_luaentity()
    end
    local objs = core.get_objects_inside_radius(pos, 1.5)
    for _, obj in ipairs(objs) do
        local le = obj:get_luaentity()
        if le and le.name == "kinetica:windmill_pivot" then
            active_pivots_by_hash[h] = obj
            return obj, le
        end
    end
    return nil, nil
end

local function push_windmill_network_update(pos, param2)
    if kinetica.api and kinetica.api.network and kinetica.api.network.update then
        kinetica.api.network.update(pos)
        local back_pos = vector.add(pos, get_back_dir(param2))
        if kinetica.is_kinetic_node and kinetica.is_kinetic_node(core.get_node(back_pos).name) then
            kinetica.api.network.update(back_pos)
        end
    end
end

local function assemble_windmill(pos, node, player)
    local pname = player and player:is_player() and player:get_player_name() or ""
    if pname ~= "" and core.is_protected(pos, pname) then
        core.record_protection_violation(pos, pname)
        return false
    end

    local blocks, sail_count, glue_boxes, err = collect_windmill_contraption(pos, node)
    if err then
        if pname ~= "" then
            core.chat_send_player(pname, "[Kinetica] " .. err)
        end
        core.sound_play("default_cool_lava", {pos = pos, gain = 0.4, max_hear_distance = 12}, true)
        return false
    end

    local meta = core.get_meta(pos)
    local pref_spin = meta:get_int("preferred_spin")
    if pref_spin == 0 then pref_spin = 1 end

    local saved_glues = {}
    for _, gb in ipairs(glue_boxes) do
        saved_glues[#saved_glues + 1] = {
            rel_minp = gb.rel_minp,
            rel_maxp = gb.rel_maxp,
        }
        if gb.entity then
            if kinetica.api and kinetica.api.contraptions and kinetica.api.contraptions.active_glue_boxes then
                kinetica.api.contraptions.active_glue_boxes[gb.entity] = nil
            end
            if gb.entity.object and gb.entity.object:get_luaentity() then
                gb.entity.object:remove()
            end
        end
    end

    local saved_blocks = {}
    for _, b in ipairs(blocks) do
        saved_blocks[#saved_blocks + 1] = {
            name   = b.name,
            param2 = b.param2,
            rel    = b.rel,
            meta   = b.meta,
        }
        core.remove_node(b.pos)
    end

    local target_rpm, total_ku = get_windmill_stats(sail_count)
    local front_axis           = get_front_dir(node.param2)
    local vis_spin, net_spin   = get_effective_spins(node.param2, pref_spin)
    local speed_rad            = target_rpm * CONFIG.VISUAL_SPEED_MULT * vis_spin

    meta:set_int("windmill_assembled",   1)
    meta:set_string("windmill_blocks",   core.serialize(saved_blocks))
    meta:set_string("windmill_glues",    core.serialize(saved_glues))
    meta:set_int("sail_count",           sail_count)
    meta:set_int("block_count",          #saved_blocks)
    meta:set_int("source_active",        1)
    meta:set_int("source_ku",            total_ku)
    meta:set_float("source_rpm",         target_rpm)
    meta:set_int("source_spin",          net_spin)
    meta:set_int("local_spin",           net_spin)
    meta:set_int("network_overstressed", 0)

    local target_node_name = get_active_node_name_for_spin(node.param2, pref_spin)
    if node.name ~= target_node_name then
        core.swap_node(pos, {name = target_node_name, param2 = node.param2})
        node = core.get_node(pos)
    end

    spawn_windmill_entities(pos, front_axis, speed_rad, saved_blocks, 0)
    core.sound_play("default_place_node_hard", {pos = pos, gain = 0.7, pitch = 0.9, max_hear_distance = 16}, true)

    push_windmill_network_update(pos, node.param2)
    update_windmill_infotext(pos, node)
    core.get_node_timer(pos):start(0.5)

    if pname ~= "" then
        core.chat_send_player(pname, string.format(
            "[Kinetica] Windmill Assembled (%s): %d Wool Sail(s), %d Block(s) -> Generating %d KU @ %.0f RPM!",
            (pref_spin == 1) and "CW" or "CCW", sail_count, #saved_blocks, total_ku, target_rpm
        ))
    end
    return true
end

local function disassemble_windmill(pos, node, player, drop_all_on_dig)
    local meta = core.get_meta(pos)
    if meta:get_int("windmill_assembled") ~= 1 then
        clear_windmill_entities(pos)
        return false
    end

    local pname = player and player:is_player() and player:get_player_name() or ""
    if not drop_all_on_dig and pname ~= "" and core.is_protected(pos, pname) then
        core.record_protection_violation(pos, pname)
        return false
    end

    local _, ple = get_active_pivot_at(pos)
    local cur_angle  = (ple and ple.angle) or 0
    local front_axis = get_front_dir(node.param2)

    local quarter_steps = math.floor((cur_angle / (math.pi * 0.5)) + 0.5) % 4

    local raw_str      = meta:get_string("windmill_blocks")
    local saved_blocks = (raw_str ~= "" and core.deserialize(raw_str)) or {}
    local glue_str     = meta:get_string("windmill_glues")
    local saved_glues  = (glue_str ~= "" and core.deserialize(glue_str)) or {}

    clear_windmill_entities(pos)

    for _, b in ipairs(saved_blocks) do
        local rot_rel    = rotate_rel_pos_steps(b.rel, front_axis, quarter_steps)
        local target_pos = vector.add(pos, rot_rel)

        if drop_all_on_dig then
            core.add_item(target_pos, b.name)
        else
            local existing = core.get_node(target_pos)
            local edef     = core.registered_nodes[existing.name]
            if existing.name == "air" or (edef and edef.buildable_to) then
                -- Intercept and calculate the rotated param2 here
                local final_p2 = kinetica.api.math.rotate_facedir(b.param2, front_axis, quarter_steps)
                
                core.set_node(target_pos, {name = b.name, param2 = final_p2})
                if b.meta and type(b.meta) == "table" then
                    core.get_meta(target_pos):from_table(b.meta)
                end
            else
                core.add_item(pos, b.name)
            end
        end
    end

    if not drop_all_on_dig and kinetica.create_super_glue_box then
        for _, gb in ipairs(saved_glues) do
            if gb.rel_minp and gb.rel_maxp then
                local r1 = rotate_rel_pos_steps(gb.rel_minp, front_axis, quarter_steps)
                local r2 = rotate_rel_pos_steps(gb.rel_maxp, front_axis, quarter_steps)
                local p1 = vector.add(pos, r1)
                local p2 = vector.add(pos, r2)
                local minp = {x = math.min(p1.x, p2.x), y = math.min(p1.y, p2.y), z = math.min(p1.z, p2.z)}
                local maxp = {x = math.max(p1.x, p2.x), y = math.max(p1.y, p2.y), z = math.max(p1.z, p2.z)}
                kinetica.create_super_glue_box(minp, maxp)
            end
        end
    end

    meta:set_int("windmill_assembled",   0)
    meta:set_string("windmill_blocks",   "")
    meta:set_string("windmill_glues",    "")
    meta:set_int("sail_count",           0)
    meta:set_int("block_count",          0)
    meta:set_int("source_active",        0)
    meta:set_int("source_ku",            0)
    meta:set_float("source_rpm",         0)
    meta:set_int("network_overstressed", 0)

    if not drop_all_on_dig then
        if node.name ~= IDLE_NAME then
            core.swap_node(pos, {name = IDLE_NAME, param2 = node.param2})
            node = core.get_node(pos)
        end
        core.sound_play("default_Close_door", {pos = pos, gain = 0.6, pitch = 0.85, max_hear_distance = 16}, true)
        update_windmill_infotext(pos, node)
    end

    push_windmill_network_update(pos, node.param2)
    if kinetica.api and kinetica.api.network and kinetica.api.network.schedule_update then
        local back = get_back_dir(node.param2)
        kinetica.api.network.schedule_update(vector.add(pos, back))
    end

    if not drop_all_on_dig and pname ~= "" then
        core.chat_send_player(pname, "[Kinetica] Windmill Stopped & Disassembled (Super Glue preserved).")
    end
    return true
end

local function toggle_windmill_direction(pos, node, player)
    local pname = player and player:is_player() and player:get_player_name() or ""
    if pname ~= "" and core.is_protected(pos, pname) then
        core.record_protection_violation(pos, pname)
        return
    end

    local meta     = core.get_meta(pos)
    local cur_pref = meta:get_int("preferred_spin")
    if cur_pref == 0 then cur_pref = 1 end
    local new_pref = -cur_pref
    meta:set_int("preferred_spin", new_pref)

    local is_assembled = (meta:get_int("windmill_assembled") == 1)
    if is_assembled then
        local vis_spin, net_spin = get_effective_spins(node.param2, new_pref)
        meta:set_int("source_spin", net_spin)
        meta:set_int("local_spin",  net_spin)

        local target_node_name = get_active_node_name_for_spin(node.param2, new_pref)
        if node.name ~= target_node_name then
            core.swap_node(pos, {name = target_node_name, param2 = node.param2})
            node = core.get_node(pos)
        end

        push_windmill_network_update(pos, node.param2)

        local is_overstressed = (meta:get_int("network_overstressed") == 1)
        local rpm             = meta:get_float("source_rpm")
        local target_spd      = is_overstressed and 0 or (rpm * CONFIG.VISUAL_SPEED_MULT * vis_spin)

        local _, ple = get_active_pivot_at(pos)
        if ple then
            ple.target_speed = target_spd
        end
    end

    core.sound_play("default_place_node_hard", {pos = pos, gain = 0.5, pitch = 1.15, max_hear_distance = 12}, true)
    if pname ~= "" then
        core.chat_send_player(pname, string.format(
            "[Kinetica] Windmill Bearing rotation direction reversed to %s!",
            (new_pref == 1) and "Clockwise (CW)" or "Counter-Clockwise (CCW)"
        ))
    end
    update_windmill_infotext(pos, node)
end

-- ============================================================================
-- REFRESH & NODE TIMER
-- ============================================================================
function kinetica.refresh_windmill_bearing(pos, node)
    node = node or core.get_node(pos)
    local meta = core.get_meta(pos)
    if meta:get_int("windmill_assembled") == 1 then
        local sail_count           = meta:get_int("sail_count")
        local target_rpm, total_ku = get_windmill_stats(sail_count)
        local pref_spin            = meta:get_int("preferred_spin")
        if pref_spin == 0 then pref_spin = 1 end
        local _, net_spin          = get_effective_spins(node.param2, pref_spin)

        meta:set_int("source_active", 1)
        meta:set_int("source_ku",     total_ku)
        meta:set_float("source_rpm",  target_rpm)
        meta:set_int("source_spin",   net_spin)
        meta:set_int("local_spin",    net_spin)
        return true, net_spin
    else
        meta:set_int("source_active", 0)
        meta:set_int("source_ku",     0)
        meta:set_float("source_rpm",  0)
        return false, 0
    end
end

local function windmill_timer(pos, elapsed)
    local node = core.get_node(pos)
    local meta = core.get_meta(pos)

    if meta:get_int("windmill_assembled") ~= 1 then
        clear_windmill_entities(pos)
        update_windmill_infotext(pos, node)
        return false
    end

    kinetica.refresh_windmill_bearing(pos, node)
    push_windmill_network_update(pos, node.param2)

    local is_overstressed    = (meta:get_int("network_overstressed") == 1)
    local pref_spin          = meta:get_int("preferred_spin")
    if pref_spin == 0 then pref_spin = 1 end
    local vis_spin, _        = get_effective_spins(node.param2, pref_spin)
    local rpm                = meta:get_float("source_rpm")

    local target_node_name = is_overstressed and IDLE_NAME or get_active_node_name_for_spin(node.param2, pref_spin)
    if node.name ~= target_node_name then
        core.swap_node(pos, {name = target_node_name, param2 = node.param2})
        node = core.get_node(pos)
    end

    local front_axis = get_front_dir(node.param2)
    local target_spd = is_overstressed and 0 or (rpm * CONFIG.VISUAL_SPEED_MULT * vis_spin)

    local pivot, ple = get_active_pivot_at(pos)
    if not pivot or not ple or not ple.child_entries or #ple.child_entries == 0 then
        local raw_str      = meta:get_string("windmill_blocks")
        local saved_blocks = (raw_str ~= "" and core.deserialize(raw_str)) or {}
        if #saved_blocks > 0 then
            spawn_windmill_entities(pos, front_axis, target_spd, saved_blocks, 0)
        end
    else
        ple.axis         = front_axis
        ple.target_speed = target_spd
    end

    update_windmill_infotext(pos, node)
    return true
end

-- ============================================================================
-- PLACEMENT & INTERACTION HANDLERS
-- ============================================================================
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

local function place_windmill_bearing(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then return itemstack end
    local under_pos  = pointed_thing.under
    local under_node = core.get_node(under_pos)
    local under_def  = core.registered_nodes[under_node.name]
    local sneaking   = placer and placer:is_player() and placer:get_player_control().sneak

    if under_def and under_def.on_rightclick then
        if not sneaking or is_windmill_bearing(under_node.name) then
            return under_def.on_rightclick(under_pos, under_node, placer, itemstack, pointed_thing) or itemstack
        end
    end

    local ldir   = look_to_unit_dir(placer, CONFIG.ALLOW_VERTICAL_PLACEMENT)
    local back_d = sneaking and {x = -ldir.x, y = -ldir.y, z = -ldir.z} or ldir
    local param2 = core.dir_to_facedir(back_d, CONFIG.ALLOW_VERTICAL_PLACEMENT)

    local placed_stack, final_pos = core.item_place_node(itemstack, placer, pointed_thing, param2)
    if final_pos then
        local meta = core.get_meta(final_pos)
        meta:set_int("preferred_spin", 1)
        update_windmill_infotext(final_pos, core.get_node(final_pos))
        if kinetica.api and kinetica.api.network and kinetica.api.network.schedule_update then
            kinetica.api.network.schedule_update(final_pos)
        end
    end
    return placed_stack
end

local function on_bearing_rightclick(pos, node, clicker, itemstack, pointed_thing)
    if not clicker or not clicker:is_player() then return itemstack end

    local wield_name = itemstack and itemstack:get_name() or ""
    if kinetica.is_glue_tool and kinetica.is_glue_tool(wield_name) then
        return itemstack
    end

    local sneaking = clicker:get_player_control().sneak
    if sneaking then
        local is_placeable_block = (wield_name ~= "" and core.registered_nodes[wield_name] ~= nil and not is_windmill_bearing(wield_name))
        if not is_placeable_block then
            toggle_windmill_direction(pos, node, clicker)
            return itemstack
        else
            return core.item_place_node(itemstack, clicker, pointed_thing)
        end
    end

    local meta = core.get_meta(pos)
    if meta:get_int("windmill_assembled") == 1 then
        disassemble_windmill(pos, node, clicker, false)
    else
        assemble_windmill(pos, node, clicker)
    end
    return itemstack
end

-- ============================================================================
-- NODE REGISTRATIONS & LBM
-- ============================================================================
local BACK_PORT_IDLE = "[combine:16x16:0,0=" .. CONFIG.TEX_CASING .. ":0,0=" .. CONFIG.TEX_SHAFT_OVERLAY

-- Matches mechanical_piston.lua's exact make_piston_side_anim syntax
local function make_back_port_anim(reverse, anim_length)
    local casing, shaft = CONFIG.TEX_CASING, CONFIG.TEX_SHAFT_OVERLAY
    local casing_strip = "[combine:16x64:0,0=" .. casing .. ":0,16=" .. casing .. ":0,32=" .. casing .. ":0,48=" .. casing
    local shaft_strip = shaft
    if reverse then
        shaft_strip = "[combine:16x64:0,0=" .. shaft .. "\\^[sheet\\:1x4\\:0,0:0,16=" .. shaft .. "\\^[sheet\\:1x4\\:0,3:0,32=" .. shaft .. "\\^[sheet\\:1x4\\:0,2:0,48=" .. shaft .. "\\^[sheet\\:1x4\\:0,1"
    end
    return {
        name = "(" .. casing_strip .. ")^(" .. shaft_strip .. ")",
        animation = {
            type     = "vertical_frames",
            aspect_w = 16,
            aspect_h = 16,
            length   = anim_length or 0.36,
        },
    }
end

local bearing_tiles_idle = {
    CONFIG.TEX_CASING,
    CONFIG.TEX_CASING,
    CONFIG.TEX_CASING,
    CONFIG.TEX_CASING,
    BACK_PORT_IDLE,
    CONFIG.TEX_FRONT,
}

local bearing_tiles_active_cw = {
    CONFIG.TEX_CASING,
    CONFIG.TEX_CASING,
    CONFIG.TEX_CASING,
    CONFIG.TEX_CASING,
    make_back_port_anim(false, 0.36),
    CONFIG.TEX_FRONT,
}

local bearing_tiles_active_ccw = {
    CONFIG.TEX_CASING,
    CONFIG.TEX_CASING,
    CONFIG.TEX_CASING,
    CONFIG.TEX_CASING,
    make_back_port_anim(true, 0.36),
    CONFIG.TEX_FRONT,
}

local sound_metal = (mcl_sounds and mcl_sounds.node_sound_metal_defaults)
    and mcl_sounds.node_sound_metal_defaults()
    or  nil

core.register_node(IDLE_NAME, {
    description           = string.format("Windmill Bearing (Glue %d+ Wool Sails & R-Click | Sneak+R-Click: Reverse Direction)", CONFIG.MIN_SAILS),
    drawtype              = "normal",
    tiles                 = bearing_tiles_idle,
    paramtype2            = "facedir",
    is_ground_content     = false,
    groups                = {handy = 1, pickaxey = 1, axey = 1, rotational_source = 1, windmill_bearing = 1},
    _mcl_hardness         = 3.0,
    _mcl_blast_resistance = 4.0,
    sounds                = sound_metal,
    on_place              = place_windmill_bearing,
    on_rightclick         = on_bearing_rightclick,

    on_construct = function(pos)
        local meta = core.get_meta(pos)
        meta:set_int("preferred_spin", 1)
        update_windmill_infotext(pos, core.get_node(pos))
    end,

    on_destruct = function(pos)
        local node = core.get_node(pos)
        if core.get_meta(pos):get_int("windmill_assembled") == 1 then
            disassemble_windmill(pos, node, nil, true)
        end
    end,

    on_timer = windmill_timer,
})

local function register_active_bearing(node_name, tiles)
    core.register_node(node_name, {
        description           = "Windmill Bearing (Active)",
        drawtype              = "normal",
        tiles                 = tiles,
        paramtype2            = "facedir",
        is_ground_content     = false,
        drop                  = IDLE_NAME,
        groups                = {handy = 1, pickaxey = 1, axey = 1, rotational_source = 1, windmill_bearing = 1, not_in_creative_inventory = 1},
        _mcl_hardness         = 3.0,
        _mcl_blast_resistance = 4.0,
        sounds                = sound_metal,
        on_rightclick         = on_bearing_rightclick,

        on_destruct = function(pos)
            local node = core.get_node(pos)
            if core.get_meta(pos):get_int("windmill_assembled") == 1 then
                disassemble_windmill(pos, node, nil, true)
            end
        end,

        on_timer = windmill_timer,
    })
end

register_active_bearing(ACTIVE_CW_NAME,  bearing_tiles_active_cw)
register_active_bearing(ACTIVE_CCW_NAME, bearing_tiles_active_ccw)
core.register_alias(ACTIVE_LEGACY, ACTIVE_CW_NAME)

core.register_on_punchnode(function(pos, node, puncher)
    if is_windmill_bearing(node.name) and puncher and puncher:is_player() then
        if puncher:get_player_control().sneak then
            toggle_windmill_direction(pos, node, puncher)
        end
    end
end)

core.register_lbm({
    label             = "Wake Kinetica Windmill Bearings on chunk load",
    name              = "kinetica:wake_windmill_bearings_lbm",
    nodenames         = {"group:windmill_bearing"},
    run_at_every_load = true,
    action = function(pos, node)
        local meta = core.get_meta(pos)
        if meta:get_int("windmill_assembled") == 1 then
            local timer = core.get_node_timer(pos)
            if not timer:is_started() then
                timer:start(0.2)
            end
        end
    end,
})

core.register_craft({
    output = IDLE_NAME,
    recipe = {
        {"",                        "kinetica:super_glue",  ""},
        {"kinetica:andesite_alloy", "kinetica:gold_casing", "kinetica:andesite_alloy"},
        {"",                        "kinetica:shaft",       ""},
    },
})