kinetica = kinetica or {}

local BIG_WHEEL_KU       = 256
local BIG_WHEEL_RPM      = 4
local MAX_WATER_WHEELS   = kinetica.MAX_WATER_WHEELS or 10
local VISUAL_SPEED_MULT  = 0.25
local YAW_OFFSET_DEG     = 90
local INVERT_VISUAL_SPIN = false

kinetica.BIG_WHEEL_KU  = BIG_WHEEL_KU
kinetica.BIG_WHEEL_RPM = BIG_WHEEL_RPM

local function is_water(pos)
    local node = core.get_node(pos)
    return node.name == "mcl_core:water_source" or
           node.name == "mcl_core:water_flowing" or
           node.name == "mclx_core:river_water_source" or
           node.name == "mclx_core:river_water_flowing" or
           core.get_item_group(node.name, "water") > 0
end

local function get_canon_wheel_param2(param2)
    return (param2 or 0) % 2
end

local function get_wheel_yaw(param2)
    local p2 = get_canon_wheel_param2(param2)
    local base_yaw = (p2 == 1) and (-math.pi / 2) or 0
    return base_yaw + math.rad(YAW_OFFSET_DEG)
end

core.register_entity("kinetica:water_wheel_big_mesh", {
    initial_properties = {
        physical = false,
        collide_with_objects = false,
        pointable = false,
        visual = "mesh",
        mesh = "kinetica_water_wheel_big.obj",
        textures = {
            "kinetica_water_wheel_core.png",
            "kinetica_waterwheel_panel.png",
        },
        visual_size = {x = 10, y = 10, z = 10},
    },

    on_activate = function(self, staticdata)
        self.object:set_armor_groups({immortal = 1})
        self.angle = 0
        self.speed = 0
        self.yaw = 0

        if staticdata and staticdata ~= "" then
            local data = core.deserialize(staticdata)
            if data then
                self.angle = data.angle or 0
                self.speed = data.speed or 0
                self.yaw = data.yaw or 0
                self.object:set_rotation({x = self.angle, y = self.yaw, z = 0})
            end
        end

        core.after(0.2, function()
            if self.object:get_luaentity() then
                local pos = self.object:get_pos()
                local node = core.get_node(pos)
                if node.name ~= "kinetica:water_wheel_big" then
                    self.object:remove()
                end
            end
        end)
    end,

    get_staticdata = function(self)
        return core.serialize({
            angle = self.angle,
            speed = self.speed,
            yaw = self.yaw,
        })
    end,

    on_step = function(self, dtime)
        if self.speed and self.speed ~= 0 then
            self.angle = self.angle + (self.speed * dtime)
            if self.angle > math.pi * 2 then self.angle = self.angle - (math.pi * 2) end
            if self.angle < -math.pi * 2 then self.angle = self.angle + (math.pi * 2) end
            self.object:set_rotation({x = self.angle, y = self.yaw, z = 0})
        end
    end,
})

local function sync_wheel_entity(pos, param2, speed_rad)
    local wheel_obj = nil
    local objs = core.get_objects_inside_radius(pos, 0.5)
    for _, obj in ipairs(objs) do
        local luaent = obj:get_luaentity()
        if luaent and luaent.name == "kinetica:water_wheel_big_mesh" then
            if not wheel_obj then
                wheel_obj = obj
            else
                obj:remove()
            end
        elseif luaent and luaent.name == "kinetica:water_wheel_big_pivot" then
            obj:remove()
        end
    end

    if not wheel_obj then
        wheel_obj = core.add_entity(pos, "kinetica:water_wheel_big_mesh")
    end

    if wheel_obj then
        local luaent = wheel_obj:get_luaentity()
        if luaent then
            luaent.yaw = get_wheel_yaw(param2)
            luaent.speed = speed_rad
            wheel_obj:set_rotation({x = luaent.angle or 0, y = luaent.yaw, z = 0})
        end
    end
end

local function remove_wheel_entities(pos)
    local objs = core.get_objects_inside_radius(pos, 1.0)
    for _, obj in ipairs(objs) do
        local luaent = obj:get_luaentity()
        if luaent and (luaent.name == "kinetica:water_wheel_big_mesh" or
                       luaent.name == "kinetica:water_wheel_big_pivot") then
            obj:remove()
        end
    end
end

function kinetica.refresh_water_wheel(pos, node)
    node = node or core.get_node(pos)
    local meta = core.get_meta(pos)
    local canon_p2 = get_canon_wheel_param2(node.param2)

    if node.param2 ~= canon_p2 then
        core.swap_node(pos, {name = node.name, param2 = canon_p2})
        node.param2 = canon_p2
    end

    local back_dir  = core.facedir_to_dir(canon_p2)
    local right_dir = {x = back_dir.z, y = 0, z = -back_dir.x}

    local torque = 0
    for dy = -1, 1 do
        for lr = -1, 1 do
            if dy ~= 0 or lr ~= 0 then
                local scan_pos = {
                    x = pos.x + (right_dir.x * lr),
                    y = pos.y + dy,
                    z = pos.z + (right_dir.z * lr),
                }
                if is_water(scan_pos) then
                    if lr > 0 then torque = torque + 1 end
                    if lr < 0 then torque = torque - 1 end
                end
            end
        end
    end

    local spin_dir = 0
    if torque > 0 then spin_dir = 1 end
    if torque < 0 then spin_dir = -1 end

    if spin_dir == 0 then
        meta:set_int("source_active", 0)
        meta:set_int("source_ku", 0)
        meta:set_float("source_rpm", 0)
        meta:set_int("source_spin", 0)
        meta:set_int("local_spin", 0)
        return false, 0
    else
        meta:set_int("source_active", 1)
        meta:set_int("source_ku", BIG_WHEEL_KU)
        meta:set_float("source_rpm", BIG_WHEEL_RPM)
        meta:set_int("source_spin", spin_dir)
        meta:set_int("local_spin", spin_dir)
        return true, spin_dir
    end
end

local function water_wheel_timer(pos, elapsed)
    local node = core.get_node(pos)
    local meta = core.get_meta(pos)
    local canon_p2 = get_canon_wheel_param2(node.param2)

    local active, spin_dir = kinetica.refresh_water_wheel(pos, node)

    if kinetica.update_network then
        kinetica.update_network(pos)
    end

    local is_overstressed = meta:get_int("network_overstressed") == 1

    if not active and not is_overstressed then
        meta:set_string("infotext", string.format(
            "Big Water Wheel: Idle (Place water on Left or Right paddles -> %d KU @ %d RPM | Max %d in series)",
            BIG_WHEEL_KU, BIG_WHEEL_RPM, MAX_WATER_WHEELS
        ))
    end

    local visual_speed = 0
    if active and not is_overstressed then
        visual_speed = BIG_WHEEL_RPM * VISUAL_SPEED_MULT * spin_dir
        if INVERT_VISUAL_SPIN then
            visual_speed = -visual_speed
        end
    end

    sync_wheel_entity(pos, canon_p2, visual_speed)
    return true
end

core.register_node("kinetica:water_wheel_big", {
    description = string.format("Big Water Wheel (%d KU | %d RPM | Max %d in Series)", BIG_WHEEL_KU, BIG_WHEEL_RPM, MAX_WATER_WHEELS),
    drawtype = "airlike",
    inventory_image = "kinetica_water_wheel_core.png",
    wield_image = "kinetica_water_wheel_core.png",
    paramtype = "light",
    paramtype2 = "facedir",
    sunlight_propagates = true,
    groups = {pickaxey = 1, handy = 1, axey = 1, rotational_source = 1},
    _mcl_hardness = 2.0,
    _mcl_blast_resistance = 2.0,

    collision_box = {
        type = "fixed",
        fixed = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
    },
    selection_box = {
        type = "fixed",
        fixed = {-1.5, -1.5, -0.5, 1.5, 1.5, 0.5},
    },

    on_construct = function(pos)
        local node = core.get_node(pos)
        local canon_p2 = get_canon_wheel_param2(node.param2)
        if node.param2 ~= canon_p2 then
            core.swap_node(pos, {name = node.name, param2 = canon_p2})
        end
        sync_wheel_entity(pos, canon_p2, 0)
        core.get_meta(pos):set_string("infotext", string.format(
            "Big Water Wheel: Idle (Place water on Left or Right paddles -> %d KU @ %d RPM | Max %d in series)",
            BIG_WHEEL_KU, BIG_WHEEL_RPM, MAX_WATER_WHEELS
        ))
        core.get_node_timer(pos):start(1.0)
        if kinetica.schedule_network_update then
            kinetica.schedule_network_update(pos)
        end
    end,

    after_dig_node = function(pos)
        remove_wheel_entities(pos)
        if kinetica.schedule_network_update then
            kinetica.schedule_network_update(pos)
        end
    end,

    on_timer = water_wheel_timer,
})

core.register_craft({
    output = "kinetica:water_wheel_big",
    recipe = {
        {"group:wood",     "mcl_core:stick",              "group:wood"},
        {"mcl_core:stick", "kinetica:shaft",              "mcl_core:stick"},
        {"group:wood",     "kinetica:andesite_alloy",     "group:wood"},
    },
})